extends RefCounted
class_name RestSiteManager

const DataLoader = preload("res://scripts/core/data_loader.gd")

var database: Dictionary


func _init(content_database: Dictionary = {}) -> void:
	database = content_database if not content_database.is_empty() else DataLoader.load_content_database()


func open_rest(rest_id: String, run_state: Dictionary) -> Dictionary:
	if not database.get("rest_sites", {}).has(rest_id):
		return _error("ERR_REST_ID", "Unknown rest site", {"rest_id": rest_id})
	var rest: Dictionary = database.rest_sites[rest_id]
	var heal_amount := _heal_amount(rest, run_state)
	var instance := {
		"kind": "rest",
		"instance_id": "rest-%s" % String(run_state.get("current_node_id", "")),
		"rest_id": rest_id,
		"node_id": String(run_state.get("current_node_id", "")),
		"actions": {
			"heal": {
				"enabled": bool(rest.get("heal", {}).get("enabled", true)),
				"amount": heal_amount,
				"actual_heal": min(heal_amount, int(run_state.get("max_hp", 1)) - int(run_state.get("hp", 0)))
			},
			"upgrade": {
				"enabled": bool(rest.get("upgrade", {}).get("enabled", true)) and not _upgrade_candidates(run_state).is_empty(),
				"candidate_instance_ids": _upgrade_candidates(run_state)
			}
		},
		"selected_action": null,
		"complete": false
	}
	return {"ok": true, "code": "OK", "rest": instance}


func resolve(run_state: Dictionary, rest_instance: Dictionary, action: String, card_instance_id: String = "") -> Dictionary:
	if bool(rest_instance.get("complete", false)):
		return _error("ERR_REST_COMPLETE", "Rest site is already complete")
	match action:
		"heal":
			if not bool(rest_instance.actions.heal.get("enabled", false)):
				return _error("ERR_REST_ACTION_DISABLED", "Heal is disabled")
			run_state.hp = min(int(run_state.get("max_hp", 1)), int(run_state.get("hp", 0)) + int(rest_instance.actions.heal.get("amount", 0)))
		"upgrade":
			if not bool(rest_instance.actions.upgrade.get("enabled", false)):
				return _error("ERR_REST_ACTION_DISABLED", "Upgrade is disabled")
			if not rest_instance.actions.upgrade.get("candidate_instance_ids", []).has(card_instance_id):
				return _error("ERR_CARD_NOT_UPGRADABLE", "Card is not a legal upgrade target")
			for index in range(run_state.get("deck", []).size()):
				if String(run_state.deck[index].get("instance_id", "")) == card_instance_id:
					run_state.deck[index].upgrade = 1
					break
		_:
			return _error("ERR_REST_ACTION", "Unknown rest action")
	rest_instance.selected_action = action
	rest_instance.complete = true
	return {"ok": true, "code": "OK"}


func _heal_amount(rest: Dictionary, run_state: Dictionary) -> int:
	var base_ratio := float(rest.get("heal", {}).get("base_max_hp_ratio", 0.30))
	var difficulty_multiplier := float(run_state.get("difficulty_snapshot", {}).get("base_adjustments", {}).get("rest_heal_multiplier", 1.0))
	return max(1, int(floor(float(run_state.get("max_hp", 1)) * base_ratio * difficulty_multiplier)))


func _upgrade_candidates(run_state: Dictionary) -> Array:
	var result := []
	for card_instance in run_state.get("deck", []):
		if int(card_instance.get("upgrade", 0)) == 0:
			result.append(String(card_instance.get("instance_id", "")))
	return result


func _error(code: String, message: String, details: Dictionary = {}) -> Dictionary:
	return {"ok": false, "code": code, "message": message, "details": details}
