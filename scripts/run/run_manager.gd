extends RefCounted
class_name RunManager

const DataLoader = preload("res://scripts/core/data_loader.gd")
const DifficultyManager = preload("res://scripts/core/difficulty_manager.gd")
const MapGenerator = preload("res://scripts/map/map_generator.gd")
const MapValidator = preload("res://scripts/map/map_validator.gd")
const RngStreamRegistry = preload("res://scripts/core/rng_stream_registry.gd")
const SaveManager = preload("res://scripts/save/save_manager.gd")

var database: Dictionary
var difficulty_manager: DifficultyManager
var map_generator := MapGenerator.new()
var save_manager: SaveManager
var rng_registry: RngStreamRegistry
var run_state: Dictionary = {}
var save_path: String
var save_blocked := false


func _init(content_database: Dictionary = {}, target_save_path: String = SaveManager.DEFAULT_PATH) -> void:
	database = content_database if not content_database.is_empty() else DataLoader.load_content_database()
	difficulty_manager = DifficultyManager.new(database)
	save_manager = SaveManager.new(database)
	save_path = target_save_path


func create_run(character_id: String, difficulty_id: String, run_seed: int, act_id: String = "act1_emberwood_m2") -> Dictionary:
	if character_id == "role_forge_wayfarer" or character_id.begins_with("fw_"):
		return _error("ERR_DEPRECATED_CONTENT_ID", "Deprecated character ID")
	if not database.get("characters", {}).has(character_id):
		return _error("ERR_CHARACTER_ID", "Unknown character ID")
	if not difficulty_manager.has_profile(difficulty_id):
		return _error("ERR_DIFFICULTY_ID", "Unknown difficulty ID")
	if not database.get("acts", {}).has(act_id):
		return _error("ERR_ACT_ID", "Unknown Act ID")
	var character: Dictionary = difficulty_manager.apply_character_adjustments(
		database.characters[character_id],
		difficulty_manager.get_profile(difficulty_id)
	)
	var difficulty_snapshot := difficulty_manager.create_snapshot(difficulty_id)
	rng_registry = RngStreamRegistry.new(run_seed, character_id, difficulty_id)
	var act_config: Dictionary = database.acts[act_id]
	var map_data := map_generator.generate(act_config, difficulty_snapshot, rng_registry.get_stream("map_rng"))
	var map_validation := MapValidator.validate(map_data, act_config)
	if not map_validation.ok:
		return _error("ERR_MAP_INVALID", "Generated map failed validation", {
			"seed": run_seed,
			"errors": map_validation.errors
		})
	run_state = {
		"run_id": _create_run_id(character_id, difficulty_id, run_seed),
		"run_seed": run_seed,
		"character_id": character_id,
		"difficulty_id": difficulty_id,
		"difficulty_snapshot": difficulty_snapshot,
		"phase": "map",
		"act_id": act_id,
		"current_node_id": null,
		"last_completed_node_id": null,
		"hp": int(character.max_hp),
		"max_hp": int(character.max_hp),
		"gold": int(character.starting_gold),
		"deck": _build_deck(character),
		"relic_ids": [String(character.get("starting_relic", ""))],
		"relic_state": {},
		"potions": [null, null, null],
		"map": map_data,
		"encounter_history": [],
		"event_history": [],
		"boss_history": [],
		"shop_remove_count": 0,
		"pending_resolution": null,
		"rng_streams": rng_registry.snapshot_all(),
		"stats": {
			"combats_won": 0,
			"elites_won": 0,
			"nodes_completed": 0,
			"cards_skipped": 0
		}
	}
	var save_result := _save()
	if not save_result.ok:
		return save_result
	return {"ok": true, "code": "OK", "run_state": run_state.duplicate(true)}


func load_run() -> Dictionary:
	var result := save_manager.load_run(save_path)
	if not result.ok:
		return result
	run_state = result.run_state.duplicate(true)
	rng_registry = RngStreamRegistry.new(
		int(run_state.run_seed),
		String(run_state.character_id),
		String(run_state.difficulty_id),
		run_state.rng_streams
	)
	return {"ok": true, "code": result.code, "run_state": run_state.duplicate(true)}


func enter_node(node_id: String) -> Dictionary:
	if save_blocked:
		return _error("ERR_SAVE_REQUIRED", "The previous save failed; retry before entering another node")
	if run_state.get("phase", "") != "map":
		return _error("ERR_RUN_PHASE", "Run is not waiting for a map choice")
	var location := _find_node(node_id)
	if location.is_empty() or String(location.node.status) != "available":
		return _error("ERR_NODE_UNAVAILABLE", "Node is not available", {"node_id": node_id})
	location.node.status = "current"
	run_state.current_node_id = node_id
	run_state.phase = "node_active"
	_set_node(location, location.node)
	var save_result := _save()
	if not save_result.ok:
		return save_result
	return {"ok": true, "code": "OK", "node": location.node.duplicate(true)}


func complete_node(node_id: String, resolution_id: String) -> Dictionary:
	var location := _find_node(node_id)
	if location.is_empty():
		return _error("ERR_NODE_ID", "Unknown node ID")
	if location.node.get("resolution_id") != null:
		if String(location.node.resolution_id) == resolution_id:
			return {"ok": true, "code": "OK_IDEMPOTENT", "run_state": run_state.duplicate(true)}
		return _error("ERR_NODE_ALREADY_RESOLVED", "Node already has a different resolution")
	if run_state.get("phase", "") != "node_active" or String(run_state.get("current_node_id", "")) != node_id:
		return _error("ERR_RUN_PHASE", "Node is not active")
	location.node.status = "completed"
	location.node.resolution_id = resolution_id
	_set_node(location, location.node)
	for edge_id in location.node.edges:
		var edge_location := _find_node(String(edge_id))
		if not edge_location.is_empty() and String(edge_location.node.status) == "locked":
			edge_location.node.status = "available"
			_set_node(edge_location, edge_location.node)
	run_state.last_completed_node_id = node_id
	run_state.current_node_id = null
	run_state.phase = "act_complete" if String(location.node.type) == "boss" else "map"
	run_state.stats.nodes_completed = int(run_state.stats.nodes_completed) + 1
	var save_result := _save()
	if not save_result.ok:
		return save_result
	return {"ok": true, "code": "OK", "run_state": run_state.duplicate(true)}


func get_state() -> Dictionary:
	return run_state.duplicate(true)


func retry_save() -> Dictionary:
	return _save()


func _save() -> Dictionary:
	run_state.rng_streams = rng_registry.snapshot_all()
	var result := save_manager.save_run(run_state, save_path)
	if not result.ok:
		save_blocked = true
		return result
	save_blocked = false
	return {"ok": true, "code": "OK", "save_required": false}


func _build_deck(character: Dictionary) -> Array:
	var result: Array = []
	var instance_index := 0
	for entry in character.get("starting_deck", []):
		for count_index in range(int(entry.get("count", 0))):
			result.append({
				"instance_id": "card-%03d" % instance_index,
				"card_id": String(entry.get("card_id", "")),
				"upgrade": 0,
				"run_cost_delta": 0
			})
			instance_index += 1
	return result


func _create_run_id(character_id: String, difficulty_id: String, run_seed: int) -> String:
	var source := "run|%s|%s|%d|%d" % [
		character_id,
		difficulty_id,
		run_seed,
		Time.get_ticks_usec()
	]
	var hashing := HashingContext.new()
	hashing.start(HashingContext.HASH_SHA256)
	hashing.update(source.to_utf8_buffer())
	var hex := hashing.finish().hex_encode().substr(0, 32)
	return "%s-%s-%s-%s-%s" % [
		hex.substr(0, 8),
		hex.substr(8, 4),
		hex.substr(12, 4),
		hex.substr(16, 4),
		hex.substr(20, 12)
	]


func _find_node(node_id: String) -> Dictionary:
	for floor_index in range(run_state.get("map", {}).get("floors", []).size()):
		var nodes: Array = run_state.map.floors[floor_index].nodes
		for node_index in range(nodes.size()):
			if String(nodes[node_index].id) == node_id:
				return {"floor_index": floor_index, "node_index": node_index, "node": nodes[node_index]}
	return {}


func _set_node(location: Dictionary, node: Dictionary) -> void:
	run_state.map.floors[int(location.floor_index)].nodes[int(location.node_index)] = node


func _error(code: String, message: String, details: Dictionary = {}) -> Dictionary:
	return {"ok": false, "code": code, "message": message, "details": details}
