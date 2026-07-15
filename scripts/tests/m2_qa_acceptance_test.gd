extends SceneTree

const DataLoader = preload("res://scripts/core/data_loader.gd")
const RunManager = preload("res://scripts/run/run_manager.gd")

const FIXED_SEEDS := [101, 202, 303, 404, 505, 606, 707, 808, 909, 1001]
const SAVE_PATH := "user://m2_qa_acceptance_run.json"

var failed := false
var database: Dictionary


func _init() -> void:
	database = DataLoader.load_content_database()
	for seed in FIXED_SEEDS:
		_cleanup(SAVE_PATH)
		_run_full_act(seed, "D1")
	_cleanup(SAVE_PATH)
	if failed:
		quit(1)
		return
	print("M2 QA acceptance test passed: %d fixed seeds completed full Act with save/resume checks" % FIXED_SEEDS.size())
	quit(0)


func _run_full_act(seed: int, difficulty_id: String) -> void:
	var run := RunManager.new(database, SAVE_PATH)
	var created := run.create_run("ember_ranger", difficulty_id, seed)
	_assert(created.ok, "seed %d create run failed: %s" % [seed, str(created)])
	if not created.ok:
		return
	run = _reload_and_compare(run, "seed %d after create" % seed)
	var stats := {
		"nodes": 0,
		"combats": 0,
		"elites": 0,
		"shops": 0,
		"events": 0,
		"rests": 0,
		"treasures": 0
	}
	var path: Array[String] = []
	var guard := 0
	while String(run.get_state().get("phase", "")) != "act_complete" and guard < 40:
		guard += 1
		_assert(String(run.get_state().get("phase", "")) == "map", "seed %d expected map phase, got %s" % [seed, String(run.get_state().get("phase", ""))])
		if failed:
			return
		var node := _pick_available_node(run.get_state())
		_assert(not node.is_empty(), "seed %d has no available node at step %d" % [seed, guard])
		if node.is_empty():
			return
		var node_id := String(node.get("id", ""))
		var node_type := String(node.get("type", ""))
		path.append("%s:%s" % [node_id, node_type])
		var entered := run.enter_node(node_id)
		_assert(entered.ok, "seed %d enter %s failed: %s" % [seed, node_id, str(entered)])
		if not entered.ok:
			return
		var started := run.start_current_node_resolution()
		_assert(started.ok, "seed %d start %s failed: %s" % [seed, node_id, str(started)])
		if not started.ok:
			return
		run = _reload_and_compare(run, "seed %d pending %s" % [seed, node_id])
		var resolved := _resolve_pending(run, stats)
		_assert(resolved.ok, "seed %d resolve %s failed: %s" % [seed, node_id, str(resolved)])
		if not resolved.ok:
			return
		stats.nodes = int(stats.nodes) + 1
		run = _reload_and_compare(run, "seed %d completed %s" % [seed, node_id])
	_assert(String(run.get_state().get("phase", "")) == "act_complete", "seed %d did not complete Act, path=%s" % [seed, " > ".join(path)])
	_assert(int(stats.combats) >= 5, "seed %d expected at least five combats, got %d" % [seed, int(stats.combats)])
	print("M2 QA seed %d path=%s stats=%s" % [seed, " > ".join(path), str(stats)])


func _resolve_pending(run: RunManager, stats: Dictionary) -> Dictionary:
	var pending: Dictionary = run.get_state().get("pending_resolution", {})
	match String(pending.get("kind", "")):
		"combat":
			stats.combats = int(stats.combats) + 1
			if String(pending.get("source", "")) == "elite_combat":
				stats.elites = int(stats.elites) + 1
			var combat := run.debug_autoresolve_current_combat_victory()
			if not combat.ok:
				return combat
			return _resolve_pending(run, stats)
		"reward":
			if String(pending.get("source", "")) == "treasure":
				stats.treasures = int(stats.treasures) + 1
			return _resolve_reward(run, pending)
		"shop":
			stats.shops = int(stats.shops) + 1
			return run.shop_close()
		"event":
			stats.events = int(stats.events) + 1
			return run.event_choose_option(_safe_event_option(pending))
		"rest":
			stats.rests = int(stats.rests) + 1
			return run.rest_resolve("heal")
	return {"ok": false, "code": "ERR_TEST_PENDING_KIND", "message": "Unknown pending kind: %s" % String(pending.get("kind", ""))}


func _resolve_reward(run: RunManager, reward: Dictionary) -> Dictionary:
	if reward.get("gold") != null and not bool(reward.gold.get("claimed", false)):
		var gold := run.reward_claim_gold()
		if not gold.ok:
			return gold
	var card_offer: Dictionary = reward.get("card_offer", {})
	if not bool(card_offer.get("skipped", false)) and card_offer.get("selected_instance_id") == null:
		var skipped := run.reward_skip_card()
		if not skipped.ok:
			return skipped
	if reward.get("relic_offer") != null and not bool(reward.relic_offer.get("claimed", false)):
		var relic := run.reward_claim_relic()
		if not relic.ok:
			return relic
	if reward.get("potion_offer") != null:
		var potion_offer: Dictionary = reward.potion_offer
		if not bool(potion_offer.get("claimed", false)) and not bool(potion_offer.get("declined", false)):
			var potion := run.reward_claim_or_decline_potion(null, true)
			if not potion.ok:
				return potion
	return run.reward_finish()


func _safe_event_option(event_instance: Dictionary) -> String:
	for option in event_instance.get("options", []):
		if bool(option.get("safe_exit", false)) and bool(option.get("legal", false)):
			return String(option.get("id", ""))
	for option in event_instance.get("options", []):
		if bool(option.get("legal", false)):
			return String(option.get("id", ""))
	return "leave"


func _pick_available_node(state: Dictionary) -> Dictionary:
	for floor_data in state.get("map", {}).get("floors", []):
		var nodes: Array = floor_data.get("nodes", []).duplicate(true)
		nodes.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			if int(a.get("floor", 0)) == int(b.get("floor", 0)):
				return float(a.get("x", 0.0)) < float(b.get("x", 0.0))
			return int(a.get("floor", 0)) < int(b.get("floor", 0))
		)
		for node in nodes:
			if String(node.get("status", "")) == "available":
				return node
	return {}


func _reload_and_compare(run: RunManager, context: String) -> RunManager:
	var before := _canonical_json(JSON.parse_string(JSON.stringify(run.get_state())))
	var loaded := RunManager.new(database, SAVE_PATH)
	var result := loaded.load_run()
	_assert(result.ok, "%s load failed: %s" % [context, str(result)])
	if not result.ok:
		return run
	var after := _canonical_json(JSON.parse_string(JSON.stringify(loaded.get_state())))
	_assert(before == after, "%s changed after save/load" % context)
	return loaded


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


func _cleanup(path: String) -> void:
	var target := ProjectSettings.globalize_path(path)
	for candidate in [target, target.trim_suffix(".json") + ".tmp", target.trim_suffix(".json") + ".bak"]:
		if FileAccess.file_exists(candidate):
			DirAccess.remove_absolute(candidate)


func _assert(condition: bool, message: String) -> void:
	if not condition:
		failed = true
		push_error(message)
