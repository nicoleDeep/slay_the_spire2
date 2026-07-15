extends RefCounted
class_name RunManager

const DataLoader = preload("res://scripts/core/data_loader.gd")
const DifficultyManager = preload("res://scripts/core/difficulty_manager.gd")
const MapGenerator = preload("res://scripts/map/map_generator.gd")
const MapValidator = preload("res://scripts/map/map_validator.gd")
const CombatManager = preload("res://scripts/combat/combat_manager.gd")
const RewardManager = preload("res://scripts/rewards/reward_manager.gd")
const ShopManager = preload("res://scripts/shop/shop_manager.gd")
const EventManager = preload("res://scripts/events/event_manager.gd")
const RestSiteManager = preload("res://scripts/rest/rest_site_manager.gd")
const RelicManager = preload("res://scripts/relics/relic_manager.gd")
const RngStream = preload("res://scripts/core/rng_stream.gd")
const RngStreamRegistry = preload("res://scripts/core/rng_stream_registry.gd")
const SaveManager = preload("res://scripts/save/save_manager.gd")

var database: Dictionary
var difficulty_manager: DifficultyManager
var map_generator := MapGenerator.new()
var combat_manager: CombatManager
var reward_manager: RewardManager
var shop_manager: ShopManager
var event_manager: EventManager
var rest_manager: RestSiteManager
var relic_manager: RelicManager
var save_manager: SaveManager
var rng_registry: RngStreamRegistry
var run_state: Dictionary = {}
var save_path: String
var save_blocked := false


func _init(content_database: Dictionary = {}, target_save_path: String = SaveManager.DEFAULT_PATH) -> void:
	database = content_database if not content_database.is_empty() else DataLoader.load_content_database()
	difficulty_manager = DifficultyManager.new(database)
	combat_manager = CombatManager.new(database)
	reward_manager = RewardManager.new(database)
	shop_manager = ShopManager.new(database)
	event_manager = EventManager.new(database)
	rest_manager = RestSiteManager.new(database)
	relic_manager = RelicManager.new(database)
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
	_lock_unselected_available_nodes_on_floor(int(location.floor_index), node_id)
	var save_result := _save()
	if not save_result.ok:
		return save_result
	return {"ok": true, "code": "OK", "node": location.node.duplicate(true)}


func complete_node(node_id: String, resolution_id: String) -> Dictionary:
	var location := _find_node(node_id)
	if location.is_empty():
		return _error("ERR_NODE_ID", "Unknown node ID")
	if location.node.get("resolution_id") != null and String(location.node.resolution_id) == resolution_id:
		return {"ok": true, "code": "OK_IDEMPOTENT", "run_state": run_state.duplicate(true)}
	return _error("ERR_NODE_RESOLUTION_REQUIRED", "Node completion must go through its subsystem resolution")


func start_current_node_resolution() -> Dictionary:
	if save_blocked:
		return _error("ERR_SAVE_REQUIRED", "The previous save failed; retry before resolving the node")
	if run_state.get("phase", "") != "node_active":
		return _error("ERR_RUN_PHASE", "Run is not inside an active node")
	if run_state.get("pending_resolution") != null:
		return {"ok": true, "code": "OK_PENDING_EXISTS", "pending_resolution": run_state.pending_resolution.duplicate(true)}
	var node_id := String(run_state.get("current_node_id", ""))
	var location := _find_node(node_id)
	if location.is_empty():
		return _error("ERR_NODE_ID", "Unknown current node")
	var node: Dictionary = location.node
	var result := {}
	match String(node.get("type", "")):
		"normal":
			result = _begin_combat_for_node(node, "normal_combat")
		"elite":
			result = _begin_combat_for_node(node, "elite_combat")
		"boss":
			result = _begin_combat_for_node(node, "boss_combat")
		"treasure":
			result = _begin_first_entry_reward(location, node, "treasure")
		"shop":
			result = _begin_shop(location, node)
		"event":
			result = _begin_event(location, node)
		"rest":
			result = _begin_rest(node)
		_:
			return _error("ERR_NODE_TYPE", "Unsupported node type")
	if not result.ok:
		return result
	run_state.pending_resolution = result.pending_resolution
	run_state.phase = "reward_pending" if String(result.pending_resolution.get("kind", "")) == "reward" else "node_active"
	var save_result := _save()
	if not save_result.ok:
		return save_result
	return {"ok": true, "code": "OK", "pending_resolution": run_state.pending_resolution.duplicate(true)}


func submit_combat_result(combat_result: Dictionary) -> Dictionary:
	var resolution := _pending_resolution("combat")
	if not resolution.ok:
		return resolution
	if not combat_result.get("ok", true):
		return combat_result
	var result_kind := String(combat_result.get("result", ""))
	var node_id := String(run_state.pending_resolution.get("node_id", run_state.get("current_node_id", "")))
	var location := _find_node(node_id)
	if location.is_empty():
		return _error("ERR_NODE_ID", "Unknown combat node")
	var node: Dictionary = location.node
	if not combat_result.get("combat_rng", {}).is_empty():
		var restored := rng_registry.get_stream("combat_rng").restore(combat_result.combat_rng)
		if not restored.ok:
			return restored
	if result_kind == "defeat":
		run_state.hp = 0
		run_state.phase = "defeated"
		run_state.pending_resolution = null
		return _save()
	if result_kind != "victory":
		return _error("ERR_COMBAT_RESULT", "Combat result must be victory or defeat")
	run_state.hp = clampi(int(combat_result.get("player", {}).get("hp", run_state.get("hp", 1))), 0, int(run_state.get("max_hp", 1)))
	_record_combat_victory(node)
	var generated := _begin_reward_for_node(node, String(run_state.pending_resolution.get("source", "normal_combat")))
	if not generated.ok:
		return generated
	run_state.pending_resolution = generated.pending_resolution
	run_state.phase = "reward_pending"
	var save_result := _save()
	if not save_result.ok:
		return save_result
	return {"ok": true, "code": "OK", "pending_resolution": run_state.pending_resolution.duplicate(true)}


func debug_autoresolve_current_combat_victory() -> Dictionary:
	var resolution := _pending_resolution("combat")
	if not resolution.ok:
		return resolution
	combat_manager.state = run_state.pending_resolution.get("combat_state", {}).duplicate(true)
	var rng_snapshot: Dictionary = run_state.pending_resolution.get("combat_rng", {})
	if not rng_snapshot.is_empty():
		combat_manager.rng = RngStream.new(int(rng_snapshot.get("seed", 1)), rng_snapshot)
	var combat_result := combat_manager.debug_force_victory()
	return submit_combat_result(combat_result)


func reward_claim_gold() -> Dictionary:
	var resolution := _pending_resolution("reward")
	if not resolution.ok:
		return resolution
	var result := reward_manager.claim_gold(run_state, run_state.pending_resolution)
	return _save_after_resolution_change(result)


func reward_choose_card(card_id: String) -> Dictionary:
	var resolution := _pending_resolution("reward")
	if not resolution.ok:
		return resolution
	var result := reward_manager.choose_card(run_state, run_state.pending_resolution, card_id)
	return _save_after_resolution_change(result)


func reward_skip_card() -> Dictionary:
	var resolution := _pending_resolution("reward")
	if not resolution.ok:
		return resolution
	var result := reward_manager.skip_card(run_state, run_state.pending_resolution)
	return _save_after_resolution_change(result)


func reward_claim_relic() -> Dictionary:
	var resolution := _pending_resolution("reward")
	if not resolution.ok:
		return resolution
	var result := reward_manager.claim_relic(run_state, run_state.pending_resolution)
	return _save_after_resolution_change(result)


func reward_claim_or_decline_potion(replace_slot: Variant = null, decline: bool = false) -> Dictionary:
	var resolution := _pending_resolution("reward")
	if not resolution.ok:
		return resolution
	var result := reward_manager.claim_or_decline_potion(run_state, run_state.pending_resolution, replace_slot, decline)
	return _save_after_resolution_change(result)


func reward_finish() -> Dictionary:
	var resolution := _pending_resolution("reward")
	if not resolution.ok:
		return resolution
	if not bool(run_state.pending_resolution.get("complete", false)):
		return _error("ERR_REWARD_INCOMPLETE", "Reward is not complete")
	var node_id := String(run_state.pending_resolution.get("node_id", run_state.get("current_node_id", "")))
	var resolution_id := String(run_state.pending_resolution.get("resolution_id", ""))
	run_state.pending_resolution = null
	run_state.phase = "node_active"
	return _commit_active_node(node_id, resolution_id)


func reward_take_all_skip_card(decline_potion_if_full: bool = true) -> Dictionary:
	var result := reward_claim_gold()
	if not result.ok:
		return result
	result = reward_skip_card()
	if not result.ok:
		return result
	result = reward_claim_relic()
	if not result.ok:
		return result
	result = reward_claim_or_decline_potion(null, decline_potion_if_full)
	if not result.ok and result.code == "ERR_POTION_SLOTS_FULL" and decline_potion_if_full:
		result = reward_claim_or_decline_potion(null, true)
	if not result.ok:
		return result
	return reward_finish()


func shop_buy(slot_id: String, replace_potion_slot: Variant = null) -> Dictionary:
	var resolution := _pending_resolution("shop")
	if not resolution.ok:
		return resolution
	var result := shop_manager.buy_item(run_state, run_state.pending_resolution, slot_id, replace_potion_slot)
	return _save_after_resolution_change(result)


func shop_remove_card(card_instance_id: String) -> Dictionary:
	var resolution := _pending_resolution("shop")
	if not resolution.ok:
		return resolution
	var result := shop_manager.remove_card(run_state, run_state.pending_resolution, card_instance_id)
	return _save_after_resolution_change(result)


func shop_close() -> Dictionary:
	var resolution := _pending_resolution("shop")
	if not resolution.ok:
		return resolution
	var result := shop_manager.close_shop(run_state.pending_resolution)
	if not result.ok:
		return result
	var node_id := String(run_state.pending_resolution.get("node_id", run_state.get("current_node_id", "")))
	var resolution_id := String(run_state.pending_resolution.get("instance_id", ""))
	run_state.pending_resolution = null
	return _commit_active_node(node_id, resolution_id)


func event_choose_option(option_id: String, selection: Dictionary = {}) -> Dictionary:
	var resolution := _pending_resolution("event")
	if not resolution.ok:
		return resolution
	var result := event_manager.choose_option(run_state, run_state.pending_resolution, option_id, selection)
	if not result.ok:
		return result
	var node_id := String(run_state.pending_resolution.get("node_id", run_state.get("current_node_id", "")))
	var resolution_id := String(run_state.pending_resolution.get("instance_id", ""))
	run_state.pending_resolution = null
	return _commit_active_node(node_id, resolution_id)


func rest_resolve(action: String, card_instance_id: String = "") -> Dictionary:
	var resolution := _pending_resolution("rest")
	if not resolution.ok:
		return resolution
	var result := rest_manager.resolve(run_state, run_state.pending_resolution, action, card_instance_id)
	if not result.ok:
		return result
	var node_id := String(run_state.pending_resolution.get("node_id", run_state.get("current_node_id", "")))
	var resolution_id := String(run_state.pending_resolution.get("instance_id", ""))
	run_state.pending_resolution = null
	return _commit_active_node(node_id, resolution_id)


func _commit_active_node(node_id: String, resolution_id: String) -> Dictionary:
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
	var trigger_context := {"node_id": node_id, "depth": 0}
	var node_trigger := relic_manager.trigger(run_state, "node_completed", trigger_context)
	if not node_trigger.ok:
		return node_trigger
	if String(location.node.type) == "boss":
		var act_trigger := relic_manager.trigger(run_state, "act_completed", trigger_context)
		if not act_trigger.ok:
			return act_trigger
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


func _begin_reward_for_node(node: Dictionary, source: String) -> Dictionary:
	var generated := reward_manager.generate_reward(source, run_state, rng_registry.get_stream("reward_rng"))
	if not generated.ok:
		return generated
	var reward: Dictionary = generated.resolution
	reward.node_id = String(node.get("id", run_state.get("current_node_id", "")))
	var trigger_result := relic_manager.trigger(run_state, "reward_generated", {"node_id": reward.node_id, "depth": 0})
	if not trigger_result.ok:
		return trigger_result
	return {"ok": true, "code": "OK", "pending_resolution": reward}


func _begin_combat_for_node(node: Dictionary, source: String) -> Dictionary:
	var encounter_id := String(node.get("content_ref", ""))
	if encounter_id.is_empty() or not database.get("enemies", {}).has(encounter_id):
		return _error("ERR_ENCOUNTER_ID", "Combat node has no valid encounter", {"content_ref": encounter_id})
	var combat_state := combat_manager.start_run_combat(run_state, [encounter_id], rng_registry.get_stream("combat_rng"))
	if String(combat_state.get("phase", "")) == "config_error":
		return _error("ERR_COMBAT_START", "Combat failed to start")
	var resolution := {
		"kind": "combat",
		"resolution_id": "combat-%s" % String(node.get("id", run_state.get("current_node_id", ""))),
		"source": source,
		"node_id": String(node.get("id", run_state.get("current_node_id", ""))),
		"encounter_id": encounter_id,
		"combat_state": combat_state,
		"combat_rng": combat_state.get("rng", {}).duplicate(true),
		"complete": false
	}
	return {"ok": true, "code": "OK", "pending_resolution": resolution}


func _record_combat_victory(node: Dictionary) -> void:
	run_state.stats.combats_won = int(run_state.stats.get("combats_won", 0)) + 1
	match String(node.get("type", "")):
		"elite":
			run_state.stats.elites_won = int(run_state.stats.get("elites_won", 0)) + 1
		"boss":
			var boss_id := String(node.get("content_ref", ""))
			if not run_state.boss_history.has(boss_id):
				run_state.boss_history.append(boss_id)


func _begin_first_entry_reward(location: Dictionary, node: Dictionary, source: String) -> Dictionary:
	var generated := _begin_reward_for_node(node, source)
	if not generated.ok:
		return generated
	if node.get("content_ref") == null:
		node.content_ref = generated.pending_resolution.resolution_id
		_set_node(location, node)
	return generated


func _begin_shop(location: Dictionary, node: Dictionary) -> Dictionary:
	var pool_id := String(database.get("acts", {}).get(String(run_state.get("act_id", "")), {}).get("pools", {}).get("shops", ""))
	if node.get("content_ref") != null and run_state.get("pending_resolution") != null:
		return {"ok": true, "code": "OK", "pending_resolution": run_state.pending_resolution}
	var opened := shop_manager.open_shop(pool_id, run_state, rng_registry.get_stream("shop_rng"))
	if not opened.ok:
		return opened
	node.content_ref = opened.shop.instance_id
	_set_node(location, node)
	var trigger_result := relic_manager.trigger(run_state, "shop_entered", {"node_id": String(node.id), "depth": 0})
	if not trigger_result.ok:
		return trigger_result
	return {"ok": true, "code": "OK", "pending_resolution": opened.shop}


func _begin_event(location: Dictionary, node: Dictionary) -> Dictionary:
	var pool_id := String(database.get("acts", {}).get(String(run_state.get("act_id", "")), {}).get("pools", {}).get("events", ""))
	var opened := event_manager.open_event(pool_id, run_state, rng_registry.get_stream("event_rng"))
	if not opened.ok:
		return opened
	node.content_ref = opened.event.event_id
	_set_node(location, node)
	return {"ok": true, "code": "OK", "pending_resolution": opened.event}


func _begin_rest(node: Dictionary) -> Dictionary:
	var rest_id := String(node.get("content_ref", ""))
	var opened := rest_manager.open_rest(rest_id, run_state)
	if not opened.ok:
		return opened
	var trigger_result := relic_manager.trigger(run_state, "rest_site_entered", {"node_id": String(node.id), "depth": 0})
	if not trigger_result.ok:
		return trigger_result
	return {"ok": true, "code": "OK", "pending_resolution": opened.rest}


func _pending_resolution(kind: String) -> Dictionary:
	if run_state.get("pending_resolution") == null:
		return _error("ERR_PENDING_RESOLUTION", "No pending resolution")
	if String(run_state.pending_resolution.get("kind", "")) != kind:
		return _error("ERR_PENDING_RESOLUTION_KIND", "Pending resolution has a different kind")
	return {"ok": true, "code": "OK", "pending_resolution": run_state.pending_resolution}


func _save_after_resolution_change(result: Dictionary) -> Dictionary:
	if not result.ok:
		return result
	var save_result := _save()
	if not save_result.ok:
		return save_result
	result.pending_resolution = run_state.pending_resolution.duplicate(true) if run_state.get("pending_resolution") != null else null
	return result


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


func _lock_unselected_available_nodes_on_floor(floor_index: int, selected_node_id: String) -> void:
	var nodes: Array = run_state.map.floors[floor_index].nodes
	for node_index in range(nodes.size()):
		var node: Dictionary = nodes[node_index]
		if String(node.get("id", "")) != selected_node_id and String(node.get("status", "")) == "available":
			node.status = "locked"
			run_state.map.floors[floor_index].nodes[node_index] = node


func _error(code: String, message: String, details: Dictionary = {}) -> Dictionary:
	return {"ok": false, "code": code, "message": message, "details": details}
