extends RefCounted
class_name ShopManager

const DataLoader = preload("res://scripts/core/data_loader.gd")

var database: Dictionary


func _init(content_database: Dictionary = {}) -> void:
	database = content_database if not content_database.is_empty() else DataLoader.load_content_database()


func open_shop(pool_id: String, run_state: Dictionary, shop_rng: RngStream) -> Dictionary:
	if not database.get("shop_pools", {}).has(pool_id):
		return _error("ERR_SHOP_POOL_ID", "Unknown shop pool", {"pool_id": pool_id})
	var pool: Dictionary = database.shop_pools[pool_id]
	var snapshot: Dictionary = run_state.get("difficulty_snapshot", {}).get("base_adjustments", {})
	var shop_multiplier := float(snapshot.get("shop_price_multiplier", 1.0))
	var remove_multiplier := float(snapshot.get("remove_cost_multiplier", 1.0))
	var instance := {
		"kind": "shop",
		"instance_id": "shop-%08d" % shop_rng.next_int_range(0, 99999999),
		"pool_id": pool_id,
		"node_id": String(run_state.get("current_node_id", "")),
		"items": [],
		"remove_service": {
			"base_price": int(pool.get("remove_base_price", 75)),
			"increment": int(pool.get("remove_increment", 25)),
			"final_price": max(0, int(floor(float(int(pool.get("remove_base_price", 75)) + int(run_state.get("shop_remove_count", 0)) * int(pool.get("remove_increment", 25))) * shop_multiplier * remove_multiplier))),
			"used": false
		},
		"closed": false,
		"complete": false
	}
	_add_items(instance.items, "card", pool.get("cards", []), int(pool.get("card_slots", 5)), pool.get("prices", {}).get("card", {}), shop_multiplier, shop_rng)
	_add_items(instance.items, "relic", _filter_owned_relics(pool.get("relics", []), run_state), int(pool.get("relic_slots", 2)), pool.get("prices", {}).get("relic", {}), shop_multiplier, shop_rng)
	_add_items(instance.items, "potion", pool.get("potions", []), int(pool.get("potion_slots", 2)), pool.get("prices", {}).get("potion", {}), shop_multiplier, shop_rng)
	return {"ok": true, "code": "OK", "shop": instance}


func buy_item(run_state: Dictionary, shop: Dictionary, slot_id: String, replace_potion_slot: Variant = null) -> Dictionary:
	if bool(shop.get("closed", false)):
		return _error("ERR_SHOP_CLOSED", "Shop is closed")
	for index in range(shop.get("items", []).size()):
		var item: Dictionary = shop.items[index]
		if String(item.get("slot_id", "")) != slot_id:
			continue
		if bool(item.get("sold", false)):
			return _error("ERR_SHOP_SOLD", "Item is already sold")
		var price := int(item.get("final_price", 0))
		if int(run_state.get("gold", 0)) < price:
			return _error("ERR_NOT_ENOUGH_GOLD", "Not enough gold", {"needed": price - int(run_state.get("gold", 0))})
		var apply_result := _grant_item(run_state, item, replace_potion_slot)
		if not apply_result.ok:
			return apply_result
		run_state.gold = int(run_state.gold) - price
		item.sold = true
		shop.items[index] = item
		return {"ok": true, "code": "OK"}
	return _error("ERR_SHOP_SLOT", "Unknown shop slot")


func remove_card(run_state: Dictionary, shop: Dictionary, card_instance_id: String) -> Dictionary:
	if bool(shop.get("closed", false)):
		return _error("ERR_SHOP_CLOSED", "Shop is closed")
	var service: Dictionary = shop.get("remove_service", {})
	if bool(service.get("used", false)):
		return _error("ERR_REMOVE_USED", "Remove service already used")
	var price := int(service.get("final_price", 0))
	if int(run_state.get("gold", 0)) < price:
		return _error("ERR_NOT_ENOUGH_GOLD", "Not enough gold", {"needed": price - int(run_state.get("gold", 0))})
	for index in range(run_state.get("deck", []).size()):
		if String(run_state.deck[index].get("instance_id", "")) == card_instance_id:
			run_state.deck.remove_at(index)
			run_state.gold = int(run_state.gold) - price
			run_state.shop_remove_count = int(run_state.get("shop_remove_count", 0)) + 1
			service.used = true
			shop.remove_service = service
			return {"ok": true, "code": "OK"}
	return _error("ERR_CARD_INSTANCE_ID", "No removable card with this instance ID")


func close_shop(shop: Dictionary) -> Dictionary:
	shop.closed = true
	shop.complete = true
	return {"ok": true, "code": "OK"}


func _add_items(target: Array, kind: String, values: Array, count: int, price_config: Dictionary, multiplier: float, shop_rng: RngStream) -> void:
	var candidates := []
	for value in values:
		if not candidates.has(String(value)):
			candidates.append(String(value))
	candidates.sort()
	var slot_index := 0
	while slot_index < count and not candidates.is_empty():
		var index := shop_rng.next_int_range(0, candidates.size() - 1)
		var content_id := String(candidates[index])
		candidates.remove_at(index)
		var base_price := int(price_config.get("base", 50))
		target.append({
			"slot_id": "%s_%d" % [kind, slot_index],
			"kind": kind,
			"content_id": content_id,
			"base_price": base_price,
			"final_price": max(0, int(floor(float(base_price) * multiplier))),
			"sold": false
		})
		slot_index += 1


func _filter_owned_relics(relic_ids: Array, run_state: Dictionary) -> Array:
	var result := []
	for relic_id in relic_ids:
		var id := String(relic_id)
		var relic: Dictionary = database.get("relics", {}).get(id, {})
		if bool(relic.get("unique", true)) and run_state.get("relic_ids", []).has(id):
			continue
		result.append(id)
	return result


func _grant_item(run_state: Dictionary, item: Dictionary, replace_potion_slot: Variant) -> Dictionary:
	var content_id := String(item.get("content_id", ""))
	match String(item.get("kind", "")):
		"card":
			var instance_id := "card-%03d" % int(run_state.get("deck", []).size())
			run_state.deck.append({"instance_id": instance_id, "card_id": content_id, "upgrade": 0, "run_cost_delta": 0})
		"relic":
			if not run_state.relic_ids.has(content_id):
				run_state.relic_ids.append(content_id)
		"potion":
			var slot := _first_empty_potion_slot(run_state)
			if slot == -1:
				if replace_potion_slot == null:
					return _error("ERR_POTION_SLOTS_FULL", "Potion slots are full")
				slot = int(replace_potion_slot)
			if slot < 0 or slot >= run_state.get("potions", []).size():
				return _error("ERR_POTION_SLOT", "Invalid potion slot")
			run_state.potions[slot] = content_id
	return {"ok": true, "code": "OK"}


func _first_empty_potion_slot(run_state: Dictionary) -> int:
	for index in range(run_state.get("potions", []).size()):
		if run_state.potions[index] == null:
			return index
	return -1


func _error(code: String, message: String, details: Dictionary = {}) -> Dictionary:
	return {"ok": false, "code": code, "message": message, "details": details}
