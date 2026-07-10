extends SceneTree

const DataLoader = preload("res://scripts/core/data_loader.gd")
const RunManager = preload("res://scripts/run/run_manager.gd")
const RngStreamRegistry = preload("res://scripts/core/rng_stream_registry.gd")
const SaveManager = preload("res://scripts/save/save_manager.gd")
const STREAM_NAMES := ["map_rng", "combat_rng", "reward_rng", "event_rng", "shop_rng"]

const SAVE_PATH := "user://sla10_active_run.json"
const NEWER_PATH := "user://sla10_newer_run.json"
const NODE_PATH := "user://sla10_node_run.json"

var failed := false


func _init() -> void:
	_cleanup(SAVE_PATH)
	_cleanup(NEWER_PATH)
	_cleanup(NODE_PATH)
	var database := DataLoader.load_content_database()
	_test_stream_isolation()
	var running := RunManager.new(database, SAVE_PATH)
	var created := running.create_run("ember_ranger", "D2", 918273)
	_assert(created.ok, "run creation/save failed: %s" % str(created))

	for stream_name in STREAM_NAMES:
		running.rng_registry.get_stream(stream_name).next_int_range(0, 1000000)
	var save_result := running._save()
	_assert(save_result.ok, "second save failed: %s" % str(save_result))

	var restored := RunManager.new(database, SAVE_PATH)
	var load_result := restored.load_run()
	_assert(load_result.ok, "saved run did not load: %s" % str(load_result))
	if not load_result.ok:
		_cleanup(SAVE_PATH)
		quit(1)
		return
	for stream_name in STREAM_NAMES:
		var uninterrupted_next := running.rng_registry.get_stream(stream_name).next_int_range(0, 1000000)
		var restored_next := restored.rng_registry.get_stream(stream_name).next_int_range(0, 1000000)
		_assert(uninterrupted_next == restored_next, "%s next result changed after restart" % stream_name)
		_assert(
			running.rng_registry.get_stream(stream_name).snapshot() == restored.rng_registry.get_stream(stream_name).snapshot(),
			"%s snapshot changed after restart: %s != %s" % [
				stream_name,
				str(running.rng_registry.get_stream(stream_name).snapshot()),
				str(restored.rng_registry.get_stream(stream_name).snapshot())
			]
		)

	var target := ProjectSettings.globalize_path(SAVE_PATH)
	var corrupt := FileAccess.open(target, FileAccess.WRITE)
	corrupt.store_string("{truncated")
	corrupt.close()
	var recovered := SaveManager.new(database).load_run(SAVE_PATH)
	_assert(recovered.ok and recovered.code == "OK_BACKUP_RECOVERED", "corrupt primary must recover explicit backup")

	var newer_file := FileAccess.open(ProjectSettings.globalize_path(NEWER_PATH), FileAccess.WRITE)
	newer_file.store_string(JSON.stringify({"schema_version": 999, "run_state": {}}))
	newer_file.close()
	var newer := SaveManager.new(database).load_run(NEWER_PATH)
	_assert(not newer.ok and newer.code == "ERR_SAVE_VERSION_NEWER", "newer schema must return ERR_SAVE_VERSION_NEWER")

	var node_run := RunManager.new(database, NODE_PATH)
	var node_created := node_run.create_run("ember_ranger", "D1", 777)
	_assert(node_created.ok, "node lifecycle run creation failed")
	var node_id := String(node_run.get_state().map.floors[0].nodes[0].id)
	_assert(node_run.enter_node(node_id).ok, "available node should be enterable")
	_assert(not node_run.complete_node(node_id, "resolution-test-1").ok, "direct active node completion should be rejected")
	_assert(node_run.start_current_node_resolution().ok, "node resolution should start")
	_assert(node_run.debug_autoresolve_current_combat_victory().ok, "combat node should resolve through combat boundary")
	_assert(node_run.reward_take_all_skip_card(true).ok, "combat reward should commit node")
	var resolution_id := String(node_run.get_state().map.floors[0].nodes[0].resolution_id)
	var repeated := node_run.complete_node(node_id, resolution_id)
	_assert(repeated.ok and repeated.code == "OK_IDEMPOTENT", "same resolution must be idempotent")
	var loaded_node_run := RunManager.new(database, NODE_PATH)
	var loaded_node := loaded_node_run.load_run()
	_assert(loaded_node.ok, "committed node save must load")
	_assert(
		String(loaded_node_run.get_state().map.floors[0].nodes[0].status) == "completed",
		"completed node state must persist"
	)

	_cleanup(SAVE_PATH)
	_cleanup(NEWER_PATH)
	_cleanup(NODE_PATH)
	if failed:
		quit(1)
		return
	print("M2 save/RNG test passed")
	quit(0)


func _cleanup(path: String) -> void:
	var target := ProjectSettings.globalize_path(path)
	for candidate in [target, target.trim_suffix(".json") + ".tmp", target.trim_suffix(".json") + ".bak"]:
		if FileAccess.file_exists(candidate):
			DirAccess.remove_absolute(candidate)


func _test_stream_isolation() -> void:
	var control := RngStreamRegistry.new(445566, "ember_ranger", "D1")
	var perturbed := RngStreamRegistry.new(445566, "ember_ranger", "D1")
	for draw_index in range(20):
		perturbed.get_stream("reward_rng").next_int_range(0, 1000)
	for stream_name in ["map_rng", "combat_rng", "event_rng", "shop_rng"]:
		_assert(
			control.get_stream(stream_name).next_int_range(0, 1000000)
			== perturbed.get_stream(stream_name).next_int_range(0, 1000000),
			"extra reward_rng draws changed %s" % stream_name
		)


func _assert(condition: bool, message: String) -> void:
	if not condition:
		failed = true
		push_error(message)
