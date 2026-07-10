extends RefCounted
class_name RelicManager

const DataLoader = preload("res://scripts/core/data_loader.gd")

var database: Dictionary


func _init(content_database: Dictionary = {}) -> void:
	database = content_database if not content_database.is_empty() else DataLoader.load_content_database()


func add_relic(run_state: Dictionary, relic_id: String) -> Dictionary:
	if not database.get("relics", {}).has(relic_id):
		return _error("ERR_RELIC_ID", "Unknown relic", {"relic_id": relic_id})
	var relic: Dictionary = database.relics[relic_id]
	if bool(relic.get("unique", true)) and run_state.get("relic_ids", []).has(relic_id):
		return _error("ERR_RELIC_DUPLICATE", "Unique relic already owned")
	run_state.relic_ids.append(relic_id)
	return {"ok": true, "code": "OK"}


func trigger(run_state: Dictionary, hook: String, context: Dictionary = {}) -> Dictionary:
	var depth := int(context.get("depth", 0))
	if depth > 32:
		return _error("ERR_TRIGGER_DEPTH", "Relic trigger depth exceeded")
	var changes := []
	for relic_id in run_state.get("relic_ids", []):
		var relic: Dictionary = database.get("relics", {}).get(String(relic_id), {})
		for trigger_data in relic.get("triggers", []):
			if String(trigger_data.get("hook", "")) != hook:
				continue
			var limit_result := _check_and_mark_limit(run_state, String(relic_id), trigger_data, context)
			if not limit_result.ok:
				continue
			for effect in trigger_data.get("effects", []):
				_apply_run_effect(run_state, effect)
				changes.append({"relic_id": String(relic_id), "effect": effect.duplicate(true)})
	return {"ok": true, "code": "OK", "changes": changes}


func trigger_combat(run_state: Dictionary, combat_state: Dictionary, hook: String, context: Dictionary = {}) -> Dictionary:
	var depth := int(context.get("depth", 0))
	if depth > 32:
		return _error("ERR_TRIGGER_DEPTH", "Relic trigger depth exceeded")
	var changes := []
	for relic_id in run_state.get("relic_ids", []):
		var relic: Dictionary = database.get("relics", {}).get(String(relic_id), {})
		for trigger_data in relic.get("triggers", []):
			if String(trigger_data.get("hook", "")) != hook:
				continue
			var limit_result := _check_and_mark_limit(run_state, String(relic_id), trigger_data, context)
			if not limit_result.ok:
				continue
			for effect in trigger_data.get("effects", []):
				_apply_combat_effect(run_state, combat_state, effect)
				changes.append({"relic_id": String(relic_id), "effect": effect.duplicate(true)})
	return {"ok": true, "code": "OK", "changes": changes}


func _check_and_mark_limit(run_state: Dictionary, relic_id: String, trigger_data: Dictionary, context: Dictionary) -> Dictionary:
	var limit: Dictionary = trigger_data.get("limit", {})
	if limit.is_empty():
		return {"ok": true, "code": "OK"}
	var scope := String(limit.get("scope", "per_run"))
	var key := "%s:%s:%s" % [scope, context.get("node_id", run_state.get("current_node_id", "")), trigger_data.get("hook", "")]
	if not run_state.relic_state.has(relic_id):
		run_state.relic_state[relic_id] = {}
	var state: Dictionary = run_state.relic_state[relic_id]
	var current := int(state.get(key, 0))
	if current >= int(limit.get("count", 1)):
		return _error("ERR_RELIC_LIMIT", "Relic limit reached")
	state[key] = current + 1
	run_state.relic_state[relic_id] = state
	return {"ok": true, "code": "OK"}


func _apply_run_effect(run_state: Dictionary, effect: Dictionary) -> void:
	match String(effect.get("op", "")):
		"gain_gold":
			run_state.gold = int(run_state.get("gold", 0)) + int(effect.get("value", 0))
		"heal":
			run_state.hp = min(int(run_state.get("max_hp", 1)), int(run_state.get("hp", 0)) + int(effect.get("value", 0)))


func _apply_combat_effect(run_state: Dictionary, combat_state: Dictionary, effect: Dictionary) -> void:
	match String(effect.get("op", "")):
		"gain_block":
			if String(effect.get("target", "player")) == "player":
				combat_state.player.block = int(combat_state.player.get("block", 0)) + int(effect.get("value", 0))
		"heal":
			combat_state.player.hp = min(int(combat_state.player.get("max_hp", 1)), int(combat_state.player.get("hp", 0)) + int(effect.get("value", 0)))
		"gain_gold":
			run_state.gold = int(run_state.get("gold", 0)) + int(effect.get("value", 0))


func _error(code: String, message: String, details: Dictionary = {}) -> Dictionary:
	return {"ok": false, "code": code, "message": message, "details": details}
