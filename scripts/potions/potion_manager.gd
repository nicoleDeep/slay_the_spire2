extends RefCounted
class_name PotionManager

const DataLoader = preload("res://scripts/core/data_loader.gd")

var database: Dictionary


func _init(content_database: Dictionary = {}) -> void:
	database = content_database if not content_database.is_empty() else DataLoader.load_content_database()


func gain_potion(run_state: Dictionary, potion_id: String, replace_slot: Variant = null) -> Dictionary:
	if not database.get("potions", {}).has(potion_id):
		return _error("ERR_POTION_ID", "Unknown potion", {"potion_id": potion_id})
	var slot := _first_empty_slot(run_state)
	if slot == -1:
		if replace_slot == null:
			return _error("ERR_POTION_SLOTS_FULL", "Potion slots are full")
		slot = int(replace_slot)
	if slot < 0 or slot >= run_state.get("potions", []).size():
		return _error("ERR_POTION_SLOT", "Invalid potion slot")
	run_state.potions[slot] = potion_id
	return {"ok": true, "code": "OK", "slot": slot}


func discard_potion(run_state: Dictionary, slot: int) -> Dictionary:
	if slot < 0 or slot >= run_state.get("potions", []).size():
		return _error("ERR_POTION_SLOT", "Invalid potion slot")
	run_state.potions[slot] = null
	return {"ok": true, "code": "OK"}


func use_potion(run_state: Dictionary, slot: int, context: Dictionary = {}) -> Dictionary:
	if slot < 0 or slot >= run_state.get("potions", []).size():
		return _error("ERR_POTION_SLOT", "Invalid potion slot")
	var potion_id = run_state.potions[slot]
	if potion_id == null:
		return _error("ERR_POTION_EMPTY", "Potion slot is empty")
	var potion: Dictionary = database.get("potions", {}).get(String(potion_id), {})
	if String(potion.get("use_context", "combat")) != String(context.get("use_context", "combat")):
		return _error("ERR_POTION_CONTEXT", "Potion cannot be used in this context")
	run_state.potions[slot] = null
	return {"ok": true, "code": "OK", "effects": potion.get("effects", []).duplicate(true)}


func _first_empty_slot(run_state: Dictionary) -> int:
	for index in range(run_state.get("potions", []).size()):
		if run_state.potions[index] == null:
			return index
	return -1


func _error(code: String, message: String, details: Dictionary = {}) -> Dictionary:
	return {"ok": false, "code": code, "message": message, "details": details}
