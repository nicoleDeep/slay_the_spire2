extends SceneTree

const CombatManager = preload("res://scripts/combat/combat_manager.gd")
const DataLoader = preload("res://scripts/core/data_loader.gd")
const DifficultyManager = preload("res://scripts/core/difficulty_manager.gd")
const EventManager = preload("res://scripts/events/event_manager.gd")
const MapGenerator = preload("res://scripts/map/map_generator.gd")
const PotionManager = preload("res://scripts/potions/potion_manager.gd")
const RelicManager = preload("res://scripts/relics/relic_manager.gd")
const RestSiteManager = preload("res://scripts/rest/rest_site_manager.gd")
const RngStream = preload("res://scripts/core/rng_stream.gd")
const RngStreamRegistry = preload("res://scripts/core/rng_stream_registry.gd")
const RunManager = preload("res://scripts/run/run_manager.gd")
const ShopManager = preload("res://scripts/shop/shop_manager.gd")

const SAVE_PATH := "user://sla11_node_run.json"

var failed := false
var database: Dictionary


func _init() -> void:
	_cleanup(SAVE_PATH)
	database = DataLoader.load_content_database()
	_test_five_combat_reward_path()
	_test_shop_edges()
	_test_event_edges()
	_test_rest_edges()
	_test_potion_and_relic_edges()
	_test_difficulty_four_systems()
	_test_enemy_move_constraints()
	_cleanup(SAVE_PATH)
	if failed:
		quit(1)
		return
	print("M2 node system test passed")
	quit(0)


func _test_five_combat_reward_path() -> void:
	var run := RunManager.new(database, SAVE_PATH)
	var created := run.create_run("ember_ranger", "D1", 11111)
	_assert(created.ok, "run create failed: %s" % str(created))
	var combats := 0
	var guard := 0
	while combats < 5 and guard < 40:
		guard += 1
		var node := _pick_available_node(run.get_state(), true)
		if node.is_empty():
			node = _pick_available_node(run.get_state(), false)
		_assert(not node.is_empty(), "no available node while seeking five combats")
		if node.is_empty():
			return
		var entered := run.enter_node(String(node.id))
		_assert(entered.ok, "enter node failed: %s" % str(entered))
		var pending := run.start_current_node_resolution()
		_assert(pending.ok, "start node resolution failed: %s" % str(pending))
		if String(node.type) in ["normal", "elite", "boss"]:
			combats += 1
		var resolved := _resolve_pending(run)
		_assert(resolved.ok, "resolve node failed: %s" % str(resolved))
	_assert(combats >= 5, "expected at least five combat nodes, got %d" % combats)
	_assert(int(run.get_state().stats.cards_skipped) >= 5, "combat rewards should be skippable")


func _test_shop_edges() -> void:
	var run_state := _base_run_state("D3")
	var shop_manager := ShopManager.new(database)
	var opened := shop_manager.open_shop("pool_shop_act1_m2", run_state, RngStream.new(3001))
	_assert(opened.ok, "shop open failed: %s" % str(opened))
	_assert(int(opened.shop.remove_service.final_price) == 93, "D3 remove price should be floor(75*1.08*1.15)=93")
	run_state.gold = 0
	var denied := shop_manager.buy_item(run_state, opened.shop, String(opened.shop.items[0].slot_id))
	_assert(not denied.ok and denied.code == "ERR_NOT_ENOUGH_GOLD", "0-gold purchase should be denied")
	run_state.gold = 500
	var old_deck_size: int = run_state.deck.size()
	var bought := shop_manager.buy_item(run_state, opened.shop, String(opened.shop.items[0].slot_id))
	_assert(bought.ok, "shop buy failed: %s" % str(bought))
	_assert(run_state.deck.size() == old_deck_size + 1, "buying a card should add to deck")
	var removed := shop_manager.remove_card(run_state, opened.shop, String(run_state.deck[0].instance_id))
	_assert(removed.ok, "shop remove failed: %s" % str(removed))
	_assert(int(run_state.shop_remove_count) == 1, "shop remove count should increment")
	var repeat_remove := shop_manager.remove_card(run_state, opened.shop, String(run_state.deck[0].instance_id))
	_assert(not repeat_remove.ok and repeat_remove.code == "ERR_REMOVE_USED", "same shop remove service should be one-shot")


func _test_event_edges() -> void:
	var event_database := database.duplicate(true)
	event_database.reward_pools.pool_event_act1_m2.events = ["event_echo_toll"]
	var event_manager: EventManager = EventManager.new(event_database)
	var run_state := _base_run_state("D1")
	run_state.gold = 0
	var opened: Dictionary = event_manager.open_event("pool_event_act1_m2", run_state, RngStream.new(4001))
	_assert(opened.ok, "event open failed: %s" % str(opened))
	var illegal: Dictionary = event_manager.choose_option(run_state, opened.event, "pay_gold_upgrade", {"card_instance_id": String(run_state.deck[0].instance_id)})
	_assert(not illegal.ok and illegal.code == "ERR_EVENT_OPTION_ILLEGAL", "unaffordable event option should be illegal")
	var left: Dictionary = event_manager.choose_option(run_state, opened.event, "leave")
	_assert(left.ok and opened.event.complete, "safe exit should complete event")
	run_state = _base_run_state("D1")
	run_state.gold = 50
	opened = event_manager.open_event("pool_event_act1_m2", run_state, RngStream.new(4001))
	var upgraded: Dictionary = event_manager.choose_option(run_state, opened.event, "pay_gold_upgrade", {"card_instance_id": String(run_state.deck[0].instance_id)})
	_assert(upgraded.ok, "paid event upgrade failed: %s" % str(upgraded))
	_assert(int(run_state.gold) == 10 and int(run_state.deck[0].upgrade) == 1, "event should charge gold then upgrade selected card")


func _test_rest_edges() -> void:
	var rest_manager := RestSiteManager.new(database)
	var run_state := _base_run_state("D3")
	run_state.hp = 10
	var opened := rest_manager.open_rest("rest_emberwood_m2", run_state)
	_assert(opened.ok, "rest open failed")
	_assert(int(opened.rest.actions.heal.amount) == 18, "D3 rest heal should use rest_heal_multiplier")
	var upgraded := rest_manager.resolve(run_state, opened.rest, "upgrade", String(run_state.deck[0].instance_id))
	_assert(upgraded.ok and int(run_state.deck[0].upgrade) == 1, "rest upgrade should upgrade one card")
	run_state = _base_run_state("D1")
	for index in range(run_state.deck.size()):
		run_state.deck[index].upgrade = 1
	opened = rest_manager.open_rest("rest_emberwood_m2", run_state)
	_assert(not bool(opened.rest.actions.upgrade.enabled), "upgrade should disable with no legal targets")
	var healed := rest_manager.resolve(run_state, opened.rest, "heal")
	_assert(healed.ok and opened.rest.complete, "heal should remain legal at full HP")


func _test_potion_and_relic_edges() -> void:
	var potion_manager := PotionManager.new(database)
	var run_state := _base_run_state("D1")
	run_state.potions = ["potion_coal_skin", "potion_flash_draw", "potion_cinder_burst"]
	var full := potion_manager.gain_potion(run_state, "potion_clear_breath")
	_assert(not full.ok and full.code == "ERR_POTION_SLOTS_FULL", "full potion slots should require replacement or decline")
	var replaced := potion_manager.gain_potion(run_state, "potion_clear_breath", 1)
	_assert(replaced.ok and run_state.potions[1] == "potion_clear_breath", "potion replacement should use selected slot")
	var relic_manager := RelicManager.new(database)
	var duplicate := relic_manager.add_relic(run_state, "charcoal_compass")
	_assert(not duplicate.ok and duplicate.code == "ERR_RELIC_DUPLICATE", "unique relic duplicate should be rejected")
	var added := relic_manager.add_relic(run_state, "relic_bankers_ember")
	_assert(added.ok, "new relic should be added")
	var gold_before := int(run_state.gold)
	var triggered := relic_manager.trigger(run_state, "node_completed", {"node_id": "n1", "depth": 0})
	_assert(triggered.ok and int(run_state.gold) == gold_before + 3, "node_completed relic should trigger once")
	var triggered_again := relic_manager.trigger(run_state, "node_completed", {"node_id": "n1", "depth": 0})
	_assert(triggered_again.ok and int(run_state.gold) == gold_before + 3, "per-node relic limit should block repeat")


func _test_difficulty_four_systems() -> void:
	var difficulty := DifficultyManager.new(database)
	var d1 := difficulty.create_snapshot("D1")
	var d3 := difficulty.create_snapshot("D3")
	_assert(difficulty.apply_enemy_damage(100, d3) > difficulty.apply_enemy_damage(100, d1), "D3 enemy damage should be higher")
	var act: Dictionary = database.acts.act1_emberwood_m2
	var map_generator := MapGenerator.new()
	var d0_map := map_generator.generate(act, difficulty.create_snapshot("D0"), RngStreamRegistry.new(555, "ember_ranger", "D0").get_stream("map_rng"))
	var d3_map := map_generator.generate(act, d3, RngStreamRegistry.new(555, "ember_ranger", "D3").get_stream("map_rng"))
	_assert(_count_nodes_of_type(d0_map, "elite") <= _count_nodes_of_type(d3_map, "elite"), "D3 should not have fewer elite nodes than D0 for same seed")
	var d1_shop: Dictionary = ShopManager.new(database).open_shop("pool_shop_act1_m2", _base_run_state("D1"), RngStream.new(1)).shop
	var d3_shop: Dictionary = ShopManager.new(database).open_shop("pool_shop_act1_m2", _base_run_state("D3"), RngStream.new(1)).shop
	_assert(int(d3_shop.items[0].final_price) > int(d1_shop.items[0].final_price), "D3 shop prices should be higher")
	var d1_rest: Dictionary = RestSiteManager.new(database).open_rest("rest_emberwood_m2", _base_run_state("D1")).rest
	var d3_rest: Dictionary = RestSiteManager.new(database).open_rest("rest_emberwood_m2", _base_run_state("D3")).rest
	_assert(int(d3_rest.actions.heal.amount) < int(d1_rest.actions.heal.amount), "D3 rest heal should be lower")
	_assert(float(d3.base_adjustments.potion_drop_multiplier) < float(d1.base_adjustments.potion_drop_multiplier), "D3 reward potion multiplier should be lower")


func _test_enemy_move_constraints() -> void:
	var combat := CombatManager.new(database)
	combat.start_combat("ember_ranger", "D3", ["glass_mite"], 9001)
	var saw_brace := false
	var consecutive_stabs := 0
	for turn in range(8):
		var state := combat.get_public_state()
		var move_id := String(state.enemies[0].intent_move.get("id", ""))
		if move_id == "stab":
			consecutive_stabs += 1
		else:
			consecutive_stabs = 0
		if move_id == "brace":
			saw_brace = true
		_assert(consecutive_stabs <= 2, "max_consecutive should prevent more than two stabs")
		combat.end_player_turn()
		if combat.get_public_state().phase in ["victory", "defeat"]:
			break
	_assert(saw_brace, "max_consecutive should force a non-stab move in repeated selections")


func _resolve_pending(run: RunManager) -> Dictionary:
	var pending: Dictionary = run.get_state().get("pending_resolution", {})
	match String(pending.get("kind", "")):
		"reward":
			return run.reward_take_all_skip_card(true)
		"shop":
			return run.shop_close()
		"event":
			var option_id := "leave"
			for option in pending.get("options", []):
				if bool(option.get("safe_exit", false)) and bool(option.get("legal", false)):
					option_id = String(option.id)
					break
			return run.event_choose_option(option_id)
		"rest":
			return run.rest_resolve("heal")
	return {"ok": false, "code": "ERR_TEST_PENDING_KIND"}


func _pick_available_node(run_state: Dictionary, prefer_combat: bool) -> Dictionary:
	for floor in run_state.map.floors:
		for node in floor.nodes:
			if String(node.status) != "available":
				continue
			var is_combat := String(node.type) in ["normal", "elite", "boss"]
			if prefer_combat == is_combat:
				return node
	return {}


func _base_run_state(difficulty_id: String) -> Dictionary:
	var difficulty := DifficultyManager.new(database)
	var character: Dictionary = database.characters.ember_ranger
	var run_state := {
		"run_id": "test",
		"run_seed": 1,
		"character_id": "ember_ranger",
		"difficulty_id": difficulty_id,
		"difficulty_snapshot": difficulty.create_snapshot(difficulty_id),
		"phase": "map",
		"act_id": "act1_emberwood_m2",
		"current_node_id": "test_node",
		"last_completed_node_id": null,
		"hp": int(character.max_hp),
		"max_hp": int(character.max_hp),
		"gold": int(character.starting_gold),
		"deck": [],
		"relic_ids": ["charcoal_compass"],
		"relic_state": {},
		"potions": [null, null, null],
		"event_history": [],
		"shop_remove_count": 0,
		"stats": {"cards_skipped": 0, "nodes_completed": 0, "combats_won": 0, "elites_won": 0}
	}
	var index := 0
	for entry in character.starting_deck:
		for count_index in range(int(entry.count)):
			run_state.deck.append({"instance_id": "card-%03d" % index, "card_id": String(entry.card_id), "upgrade": 0, "run_cost_delta": 0})
			index += 1
	return run_state


func _count_nodes_of_type(map_data: Dictionary, node_type: String) -> int:
	var total := 0
	for floor in map_data.floors:
		for node in floor.nodes:
			if String(node.type) == node_type:
				total += 1
	return total


func _cleanup(path: String) -> void:
	var target := ProjectSettings.globalize_path(path)
	for candidate in [target, target.trim_suffix(".json") + ".tmp", target.trim_suffix(".json") + ".bak"]:
		if FileAccess.file_exists(candidate):
			DirAccess.remove_absolute(candidate)


func _assert(condition: bool, message: String) -> void:
	if not condition:
		failed = true
		push_error(message)
