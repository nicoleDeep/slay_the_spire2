extends RefCounted
class_name SaveManager

const SCHEMA_VERSION := 1
const CONTENT_VERSION := "m2-v1"
const DEFAULT_PATH := "user://active_run.json"

var database: Dictionary


func _init(content_database: Dictionary = {}) -> void:
	database = content_database


func save_run(run_state: Dictionary, path: String = DEFAULT_PATH) -> Dictionary:
	var validation := validate_run_state(run_state)
	if not validation.ok:
		return validation
	var state_for_save := run_state.duplicate(true)
	_add_exact_rng_fields(state_for_save)
	var payload := {
		"schema_version": SCHEMA_VERSION,
		"content_version": CONTENT_VERSION,
		"save_id": "active_run",
		"written_at_utc": Time.get_datetime_string_from_system(true) + "Z",
		"run_state": state_for_save
	}
	payload = JSON.parse_string(JSON.stringify(payload))
	var envelope := payload.duplicate(true)
	envelope.checksum = "sha256:" + _sha256(_canonical_json(payload))
	var target := ProjectSettings.globalize_path(path)
	var tmp_path := target.trim_suffix(".json") + ".tmp"
	var backup_path := target.trim_suffix(".json") + ".bak"
	var directory_path := target.get_base_dir()
	var mkdir_error := DirAccess.make_dir_recursive_absolute(directory_path)
	if mkdir_error != OK:
		return _error("ERR_SAVE_IO", "Could not create save directory", {"error": mkdir_error})
	var file := FileAccess.open(tmp_path, FileAccess.WRITE)
	if file == null:
		return _error("ERR_SAVE_IO", "Could not open temporary save", {"file_error": FileAccess.get_open_error()})
	file.store_string(JSON.stringify(envelope))
	file.flush()
	file.close()
	if FileAccess.file_exists(backup_path):
		DirAccess.remove_absolute(backup_path)
	if FileAccess.file_exists(target):
		var backup_error := DirAccess.rename_absolute(target, backup_path)
		if backup_error != OK:
			DirAccess.remove_absolute(tmp_path)
			return _error("ERR_SAVE_IO", "Could not rotate save backup", {"error": backup_error})
	var replace_error := DirAccess.rename_absolute(tmp_path, target)
	if replace_error != OK:
		if FileAccess.file_exists(backup_path):
			DirAccess.rename_absolute(backup_path, target)
		return _error("ERR_SAVE_IO", "Could not atomically replace save", {"error": replace_error})
	return {"ok": true, "code": "OK", "path": path, "envelope": envelope}


func load_run(path: String = DEFAULT_PATH) -> Dictionary:
	var target := ProjectSettings.globalize_path(path)
	var primary := _load_envelope(target)
	if primary.ok:
		return primary
	if primary.code in ["ERR_SAVE_VERSION_NEWER", "ERR_SAVE_MIGRATION_UNAVAILABLE", "ERR_SAVE_CONTENT_MISMATCH", "ERR_DEPRECATED_CONTENT_ID"]:
		return primary
	var backup_path := target.trim_suffix(".json") + ".bak"
	var backup := _load_envelope(backup_path)
	if backup.ok:
		backup.code = "OK_BACKUP_RECOVERED"
		backup.warning = "Primary save is invalid; recovered previous node from backup"
		backup.primary_error = primary
		return backup
	return primary


func validate_run_state(run_state: Dictionary) -> Dictionary:
	if String(run_state.get("character_id", "")) != "ember_ranger":
		return _error("ERR_SAVE_CONTENT_MISMATCH", "Unsupported or deprecated character ID")
	if String(run_state.get("difficulty_id", "")) not in ["D0", "D1", "D2", "D3"]:
		return _error("ERR_SAVE_CONTENT_MISMATCH", "Unknown difficulty ID")
	if int(run_state.get("max_hp", 0)) < 1:
		return _error("ERR_SAVE_INVALID", "max_hp must be positive")
	if int(run_state.get("hp", -1)) < 0 or int(run_state.get("hp", 0)) > int(run_state.max_hp):
		return _error("ERR_SAVE_INVALID", "hp is outside valid range")
	if int(run_state.get("gold", -1)) < 0:
		return _error("ERR_SAVE_INVALID", "gold must be non-negative")
	if _contains_deprecated_id(run_state):
		return _error("ERR_DEPRECATED_CONTENT_ID", "Save contains deprecated role_forge_wayfarer/fw_* content")
	if not database.is_empty():
		for card_instance in run_state.get("deck", []):
			if not database.get("cards", {}).has(String(card_instance.get("card_id", ""))):
				return _error("ERR_SAVE_CONTENT_MISMATCH", "Save references a missing card ID")
		if not database.get("acts", {}).has(String(run_state.get("act_id", ""))):
			return _error("ERR_SAVE_CONTENT_MISMATCH", "Save references a missing Act ID")
	var rng_streams: Dictionary = run_state.get("rng_streams", {})
	for stream_name in ["map_rng", "combat_rng", "reward_rng", "event_rng", "shop_rng"]:
		var snapshot: Dictionary = rng_streams.get(stream_name, {})
		if (
			String(snapshot.get("algorithm", "")) != "godot_rng_v1"
			or int(snapshot.get("draw_count", -1)) < 0
			or not snapshot.has("seed")
			or not snapshot.has("state")
		):
			return _error("ERR_SAVE_INVALID", "Invalid RNG snapshot", {"stream": stream_name})
	return {"ok": true, "code": "OK"}


func _load_envelope(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return _error("ERR_SAVE_NOT_FOUND", "Save file does not exist", {"path": path})
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _error("ERR_SAVE_IO", "Could not open save file", {"file_error": FileAccess.get_open_error()})
	var parser := JSON.new()
	if parser.parse(file.get_as_text()) != OK:
		return _error("ERR_SAVE_CORRUPT", "Save JSON is truncated or malformed")
	var parsed: Variant = parser.data
	if not parsed is Dictionary:
		return _error("ERR_SAVE_CORRUPT", "Save root must be an object")
	var envelope: Dictionary = parsed
	var version := int(envelope.get("schema_version", -1))
	if version > SCHEMA_VERSION:
		return _error("ERR_SAVE_VERSION_NEWER", "Save was written by a newer schema", {"version": version})
	if version < SCHEMA_VERSION:
		return _error("ERR_SAVE_MIGRATION_UNAVAILABLE", "No migration is registered for this save", {"version": version})
	var checksum := String(envelope.get("checksum", ""))
	var payload := envelope.duplicate(true)
	payload.erase("checksum")
	var expected := "sha256:" + _sha256(_canonical_json(payload))
	if checksum != expected:
		return _error("ERR_SAVE_CHECKSUM", "Save checksum does not match")
	_restore_exact_rng_fields(envelope.run_state)
	var validation := validate_run_state(envelope.get("run_state", {}))
	if not validation.ok:
		return validation
	return {"ok": true, "code": "OK", "run_state": envelope.run_state, "envelope": envelope, "path": path}


func _canonical_json(value: Variant) -> String:
	if value is Dictionary:
		var keys: Array = value.keys()
		keys.sort()
		var parts: Array[String] = []
		for key in keys:
			parts.append("%s:%s" % [JSON.stringify(String(key)), _canonical_json(value[key])])
		return "{" + ",".join(parts) + "}"
	if value is Array:
		var parts: Array[String] = []
		for item in value:
			parts.append(_canonical_json(item))
		return "[" + ",".join(parts) + "]"
	return JSON.stringify(value)


func _sha256(value: String) -> String:
	var hashing := HashingContext.new()
	hashing.start(HashingContext.HASH_SHA256)
	hashing.update(value.to_utf8_buffer())
	return hashing.finish().hex_encode()


func _contains_deprecated_id(value: Variant) -> bool:
	if value is String:
		return value == "role_forge_wayfarer" or value.begins_with("fw_")
	if value is Array:
		for item in value:
			if _contains_deprecated_id(item):
				return true
	if value is Dictionary:
		for key in value.keys():
			if _contains_deprecated_id(key) or _contains_deprecated_id(value[key]):
				return true
	return false


func _add_exact_rng_fields(state_for_save: Dictionary) -> void:
	for snapshot in state_for_save.get("rng_streams", {}).values():
		if snapshot is Dictionary:
			snapshot.seed_exact = str(int(snapshot.get("seed", 0)))
			snapshot.state_exact = str(int(snapshot.get("state", 0)))


func _restore_exact_rng_fields(state_from_save: Dictionary) -> void:
	for snapshot in state_from_save.get("rng_streams", {}).values():
		if not snapshot is Dictionary:
			continue
		if snapshot.has("seed_exact"):
			snapshot.seed = int(String(snapshot.seed_exact))
			snapshot.erase("seed_exact")
		if snapshot.has("state_exact"):
			snapshot.state = int(String(snapshot.state_exact))
			snapshot.erase("state_exact")


func _error(code: String, message: String, details: Dictionary = {}) -> Dictionary:
	return {"ok": false, "code": code, "message": message, "details": details}
