extends RefCounted
class_name RewardManager

const DataLoader = preload("res://scripts/core/data_loader.gd")

var database: Dictionary


func _init(content_database: Dictionary = {}) -> void:
	database = content_database if not content_database.is_empty() else DataLoader.load_content_database()


func generate_reward(source: String, run_state: Dictionary, reward_rng: RngStream) -> Dictionary:
	var pool_id := _pool_id_for_source(source)
	if not database.get("reward_pools", {}).has(pool_id):
		return _error("ERR_REWARD_POOL_ID", "Unknown reward pool", {"pool_id": pool_id})
	var pool: Dictionary = database.reward_pools[pool_id]
	var resolution := {
		"kind": "reward",
		"resolution_id": _make_resolution_id("reward", source, reward_rng),
		"source": source,
		"node_id": String(run_state.get("current_node_id", "")),
		"gold": {
			"amount": reward_rng.next_int_range(int(pool.get("gold_min", 0)), int(pool.get("gold_max", 0))),
			"claimed": false
		},
		"card_offer": {
			"pool_id": String(pool.get("card_pool_id", "")),
			"candidate_ids": _pick_unique(pool.get("cards", []), int(pool.get("card_offer_count", 3)), reward_rng),
			"selected_instance_id": null,
			"skipped": false
		},
		"relic_offer": null,
		"potion_offer": null,
		"complete": false
	}
	var relic_pool_id := String(pool.get("relic_pool_id", ""))
	if not relic_pool_id.is_empty():
		var relic_id := _pick_relic(relic_pool_id, run_state, reward_rng)
		if relic_id.is_empty():
			resolution.gold.amount = int(resolution.gold.amount) + int(pool.get("empty_relic_pool_gold", 25))
		else:
			resolution.relic_offer = {"relic_id": relic_id, "claimed": false}
	var potion_roll := reward_rng.next_float()
	var potion_chance := clampf(
		float(pool.get("potion_chance", 0.0)) * float(run_state.get("difficulty_snapshot", {}).get("base_adjustments", {}).get("potion_drop_multiplier", 1.0)),
		0.0,
		1.0
	)
	if potion_roll < potion_chance:
		var potion_ids := _pick_unique(pool.get("potions", []), 1, reward_rng)
		if not potion_ids.is_empty():
			resolution.potion_offer = {
				"potion_id": String(potion_ids[0]),
				"claimed": false,
				"declined": false,
				"replace_slot": null
			}
	_update_complete(resolution)
	return {"ok": true, "code": "OK", "resolution": resolution}


func claim_gold(run_state: Dictionary, resolution: Dictionary) -> Dictionary:
	if not _is_reward(resolution):
		return _error("ERR_REWARD_STATE", "Pending resolution is not a reward")
	if not bool(resolution.gold.get("claimed", false)):
		run_state.gold = int(run_state.get("gold", 0)) + int(resolution.gold.get("amount", 0))
		resolution.gold.claimed = true
	_update_complete(resolution)
	return {"ok": true, "code": "OK"}


func choose_card(run_state: Dictionary, resolution: Dictionary, card_id: String) -> Dictionary:
	if not _is_reward(resolution):
		return _error("ERR_REWARD_STATE", "Pending resolution is not a reward")
	var offer: Dictionary = resolution.get("card_offer", {})
	if bool(offer.get("skipped", false)) or offer.get("selected_instance_id") != null:
		return _error("ERR_REWARD_ALREADY_CLAIMED", "Card reward is already resolved")
	if not offer.get("candidate_ids", []).has(card_id):
		return _error("ERR_REWARD_CARD_ID", "Card is not in the offer")
	var instance_id := "card-%03d" % int(run_state.get("deck", []).size())
	run_state.deck.append({"instance_id": instance_id, "card_id": card_id, "upgrade": 0, "run_cost_delta": 0})
	offer.selected_instance_id = instance_id
	resolution.card_offer = offer
	_update_complete(resolution)
	return {"ok": true, "code": "OK", "instance_id": instance_id}


func skip_card(run_state: Dictionary, resolution: Dictionary) -> Dictionary:
	if not _is_reward(resolution):
		return _error("ERR_REWARD_STATE", "Pending resolution is not a reward")
	var offer: Dictionary = resolution.get("card_offer", {})
	if offer.get("selected_instance_id") != null:
		return _error("ERR_REWARD_ALREADY_CLAIMED", "Card reward is already resolved")
	if not bool(offer.get("skipped", false)):
		offer.skipped = true
		resolution.card_offer = offer
		run_state.stats.cards_skipped = int(run_state.get("stats", {}).get("cards_skipped", 0)) + 1
	_update_complete(resolution)
	return {"ok": true, "code": "OK"}


func claim_relic(run_state: Dictionary, resolution: Dictionary) -> Dictionary:
	if not _is_reward(resolution):
		return _error("ERR_REWARD_STATE", "Pending resolution is not a reward")
	if resolution.get("relic_offer") == null:
		return {"ok": true, "code": "OK_NO_RELIC"}
	var offer: Dictionary = resolution.relic_offer
	if not bool(offer.get("claimed", false)):
		var relic_id := String(offer.get("relic_id", ""))
		if not run_state.relic_ids.has(relic_id):
			run_state.relic_ids.append(relic_id)
		offer.claimed = true
		resolution.relic_offer = offer
	_update_complete(resolution)
	return {"ok": true, "code": "OK"}


func claim_or_decline_potion(run_state: Dictionary, resolution: Dictionary, replace_slot: Variant = null, decline: bool = false) -> Dictionary:
	if not _is_reward(resolution):
		return _error("ERR_REWARD_STATE", "Pending resolution is not a reward")
	if resolution.get("potion_offer") == null:
		return {"ok": true, "code": "OK_NO_POTION"}
	var offer: Dictionary = resolution.potion_offer
	if bool(offer.get("claimed", false)) or bool(offer.get("declined", false)):
		_update_complete(resolution)
		return {"ok": true, "code": "OK"}
	if decline:
		offer.declined = true
		resolution.potion_offer = offer
		_update_complete(resolution)
		return {"ok": true, "code": "OK"}
	var slot := _first_empty_potion_slot(run_state)
	if slot == -1:
		if replace_slot == null:
			return _error("ERR_POTION_SLOTS_FULL", "Potion slots are full")
		slot = int(replace_slot)
		if slot < 0 or slot >= run_state.get("potions", []).size():
			return _error("ERR_POTION_SLOT", "Invalid potion slot")
	run_state.potions[slot] = String(offer.get("potion_id", ""))
	offer.claimed = true
	offer.replace_slot = slot
	resolution.potion_offer = offer
	_update_complete(resolution)
	return {"ok": true, "code": "OK", "slot": slot}


func _update_complete(resolution: Dictionary) -> void:
	var gold_done := bool(resolution.get("gold", {}).get("claimed", false))
	var card_offer: Dictionary = resolution.get("card_offer", {})
	var cards: Array = card_offer.get("candidate_ids", [])
	var card_done := cards.is_empty() or bool(card_offer.get("skipped", false)) or card_offer.get("selected_instance_id") != null
	var relic_done := resolution.get("relic_offer") == null or bool(resolution.relic_offer.get("claimed", false))
	var potion_done := resolution.get("potion_offer") == null or bool(resolution.potion_offer.get("claimed", false)) or bool(resolution.potion_offer.get("declined", false))
	resolution.complete = gold_done and card_done and relic_done and potion_done


func _pool_id_for_source(source: String) -> String:
	match source:
		"normal_combat":
			return "pool_reward_normal_m2"
		"elite_combat":
			return "pool_reward_elite_m2"
		"boss_combat":
			return "pool_reward_boss_m2"
		"treasure":
			return "pool_treasure_act1_m2"
		_:
			return "pool_reward_normal_m2"


func _pick_relic(pool_id: String, run_state: Dictionary, reward_rng: RngStream) -> String:
	var pool: Dictionary = database.get("reward_pools", {}).get(pool_id, {})
	var candidates: Array = []
	for relic_id in pool.get("relics", []):
		var id := String(relic_id)
		var relic: Dictionary = database.get("relics", {}).get(id, {})
		if bool(relic.get("unique", true)) and run_state.get("relic_ids", []).has(id):
			continue
		candidates.append(id)
	candidates.sort()
	if candidates.is_empty():
		return ""
	return String(candidates[reward_rng.next_int_range(0, candidates.size() - 1)])


func _pick_unique(values: Array, count: int, rng_stream: RngStream) -> Array:
	var candidates := []
	for value in values:
		if not candidates.has(String(value)):
			candidates.append(String(value))
	candidates.sort()
	var result := []
	while result.size() < count and not candidates.is_empty():
		var index := rng_stream.next_int_range(0, candidates.size() - 1)
		result.append(candidates[index])
		candidates.remove_at(index)
	return result


func _first_empty_potion_slot(run_state: Dictionary) -> int:
	for index in range(run_state.get("potions", []).size()):
		if run_state.potions[index] == null:
			return index
	return -1


func _make_resolution_id(prefix: String, source: String, rng_stream: RngStream) -> String:
	return "%s-%s-%08d" % [prefix, source, rng_stream.next_int_range(0, 99999999)]


func _is_reward(resolution: Dictionary) -> bool:
	return String(resolution.get("kind", "")) == "reward"


func _error(code: String, message: String, details: Dictionary = {}) -> Dictionary:
	return {"ok": false, "code": code, "message": message, "details": details}
