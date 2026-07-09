extends RefCounted
class_name EventManager

const DataLoader = preload("res://scripts/core/data_loader.gd")

var database: Dictionary


func _init(content_database: Dictionary = {}) -> void:
	database = content_database if not content_database.is_empty() else DataLoader.load_content_database()


func open_event(pool_id: String, run_state: Dictionary, event_rng: RngStream) -> Dictionary:
	var pool: Dictionary = database.get("reward_pools", {}).get(pool_id, {})
	var event_ids: Array = pool.get("events", [])
	var candidates: Array = []
	for event_id in event_ids:
		var id := String(event_id)
		if run_state.get("event_history", []).has(id):
			var history_event_data: Dictionary = database.get("events", {}).get(id, {})
			if bool(history_event_data.get("once_per_run", true)):
				continue
		if database.get("events", {}).has(id):
			candidates.append(id)
	candidates.sort()
	if candidates.is_empty():
		return _error("ERR_EVENT_POOL_EMPTY", "No legal event candidates")
	var event_id := String(candidates[event_rng.next_int_range(0, candidates.size() - 1)])
	var event_data: Dictionary = database.events[event_id].duplicate(true)
	var instance: Dictionary = {
		"kind": "event",
		"instance_id": "event-%08d" % event_rng.next_int_range(0, 99999999),
		"event_id": event_id,
		"node_id": String(run_state.get("current_node_id", "")),
		"options": [],
		"selected_option_id": null,
		"complete": false
	}
	for option in event_data.get("options", []):
		var prepared: Dictionary = option.duplicate(true)
		prepared.legal = _condition_met(run_state, prepared.get("condition", {"op": "always"}))
		prepared.unavailable_reason = "" if prepared.legal else _unavailable_reason(run_state, prepared.get("condition", {}))
		prepared.costs = _scale_costs(prepared.get("costs", []), run_state)
		instance.options.append(prepared)
	var has_legal: bool = false
	for option in instance.options:
		has_legal = has_legal or bool(option.get("legal", false))
	if not has_legal:
		return _error("ERR_EVENT_NO_LEGAL_OPTION", "Event has no legal option", {"event_id": event_id})
	return {"ok": true, "code": "OK", "event": instance}


func choose_option(run_state: Dictionary, event_instance: Dictionary, option_id: String, selection: Dictionary = {}) -> Dictionary:
	if bool(event_instance.get("complete", false)):
		return _error("ERR_EVENT_COMPLETE", "Event is already complete")
	var option: Dictionary = {}
	for candidate in event_instance.get("options", []):
		if String(candidate.get("id", "")) == option_id:
			option = candidate
			break
	if option.is_empty():
		return _error("ERR_EVENT_OPTION_ID", "Unknown event option")
	if not bool(option.get("legal", false)):
		return _error("ERR_EVENT_OPTION_ILLEGAL", "Event option is not legal", {"reason": option.get("unavailable_reason", "")})
	var cost_check: Dictionary = _validate_costs(run_state, option.get("costs", []))
	if not cost_check.ok:
		return cost_check
	for cost in option.get("costs", []):
		_apply_effect(run_state, cost, selection)
	for effect in option.get("effects", []):
		var result: Dictionary = _apply_effect(run_state, effect, selection)
		if not result.ok:
			return result
	event_instance.selected_option_id = option_id
	event_instance.complete = true
	var event_id := String(event_instance.get("event_id", ""))
	if not event_id.is_empty() and not run_state.event_history.has(event_id):
		run_state.event_history.append(event_id)
	return {"ok": true, "code": "OK"}


func _scale_costs(costs: Array, run_state: Dictionary) -> Array:
	var multiplier := float(run_state.get("difficulty_snapshot", {}).get("base_adjustments", {}).get("event_cost_multiplier", 1.0))
	var result: Array = []
	for cost in costs:
		var scaled: Dictionary = cost.duplicate(true)
		if String(scaled.get("op", "")) in ["lose_gold", "lose_hp"]:
			scaled.value = max(0, int(floor(float(int(scaled.get("value", 0))) * multiplier)))
		result.append(scaled)
	return result


func _condition_met(run_state: Dictionary, condition: Dictionary) -> bool:
	match String(condition.get("op", "always")):
		"always":
			return true
		"gold_at_least":
			return int(run_state.get("gold", 0)) >= int(condition.get("value", 0))
		"hp_at_least":
			return int(run_state.get("hp", 0)) >= int(condition.get("value", 0))
		_:
			return false


func _unavailable_reason(run_state: Dictionary, condition: Dictionary) -> String:
	match String(condition.get("op", "")):
		"gold_at_least":
			return "need_%d_gold" % int(condition.get("value", 0))
		"hp_at_least":
			return "need_%d_hp" % int(condition.get("value", 0))
		_:
			return "condition_not_met"


func _validate_costs(run_state: Dictionary, costs: Array) -> Dictionary:
	for cost in costs:
		match String(cost.get("op", "")):
			"lose_gold":
				if int(run_state.get("gold", 0)) < int(cost.get("value", 0)):
					return _error("ERR_NOT_ENOUGH_GOLD", "Not enough gold")
			"lose_hp":
				if int(run_state.get("hp", 0)) <= int(cost.get("value", 0)):
					return _error("ERR_NOT_ENOUGH_HP", "Not enough HP")
	return {"ok": true, "code": "OK"}


func _apply_effect(run_state: Dictionary, effect: Dictionary, selection: Dictionary) -> Dictionary:
	match String(effect.get("op", "")):
		"gain_gold":
			run_state.gold = int(run_state.get("gold", 0)) + int(effect.get("value", 0))
		"lose_gold":
			run_state.gold = max(0, int(run_state.get("gold", 0)) - int(effect.get("value", 0)))
		"heal":
			run_state.hp = min(int(run_state.get("max_hp", 1)), int(run_state.get("hp", 0)) + int(effect.get("value", 0)))
		"lose_hp":
			run_state.hp = max(0, int(run_state.get("hp", 0)) - int(effect.get("value", 0)))
		"upgrade_card":
			return _upgrade_card(run_state, String(selection.get("card_instance_id", "")))
		"remove_card":
			return _remove_card(run_state, String(selection.get("card_instance_id", "")))
	return {"ok": true, "code": "OK"}


func _upgrade_card(run_state: Dictionary, card_instance_id: String) -> Dictionary:
	for index in range(run_state.get("deck", []).size()):
		if String(run_state.deck[index].get("instance_id", "")) == card_instance_id:
			if int(run_state.deck[index].get("upgrade", 0)) > 0:
				return _error("ERR_CARD_NOT_UPGRADABLE", "Card is already upgraded")
			run_state.deck[index].upgrade = 1
			return {"ok": true, "code": "OK"}
	return _error("ERR_CARD_INSTANCE_ID", "Missing card selection")


func _remove_card(run_state: Dictionary, card_instance_id: String) -> Dictionary:
	for index in range(run_state.get("deck", []).size()):
		if String(run_state.deck[index].get("instance_id", "")) == card_instance_id:
			run_state.deck.remove_at(index)
			return {"ok": true, "code": "OK"}
	return _error("ERR_CARD_INSTANCE_ID", "Missing card selection")


func _error(code: String, message: String, details: Dictionary = {}) -> Dictionary:
	return {"ok": false, "code": code, "message": message, "details": details}
