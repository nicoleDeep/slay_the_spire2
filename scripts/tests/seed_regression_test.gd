extends SceneTree

const CombatManager = preload("res://scripts/combat/combat_manager.gd")
const DataLoader = preload("res://scripts/core/data_loader.gd")
const RngStream = preload("res://scripts/core/rng_stream.gd")

var failed := false

func _init() -> void:
	var database := DataLoader.load_content_database()

	_assert_same_rng_shuffle()
	_assert_same_combat_seed(database)
	_assert_difficulty_values_still_differ(database)

	if failed:
		quit(1)
		return
	print("Seed regression test passed")
	quit(0)


func _assert_same_rng_shuffle() -> void:
	var first := ["ember_cut", "ash_guard", "spark_survey", "ember_cut", "ash_guard"]
	var second := first.duplicate()

	var first_rng := RngStream.new(424242)
	var second_rng := RngStream.new(424242)
	first_rng.shuffle_array(first)
	second_rng.shuffle_array(second)

	_assert(_arrays_equal(first, second), "same seed should shuffle arrays identically")
	_assert(first_rng.snapshot() == second_rng.snapshot(), "same shuffle should consume the same rng state")


func _assert_same_combat_seed(database: Dictionary) -> void:
	var first_combat := CombatManager.new(database)
	first_combat.start_combat("ember_ranger", "D1", ["mote_biter", "glass_mite"], 424242)
	var first_state := first_combat.get_public_state()

	var second_combat := CombatManager.new(database)
	second_combat.start_combat("ember_ranger", "D1", ["mote_biter", "glass_mite"], 424242)
	var second_state := second_combat.get_public_state()

	_assert(_arrays_equal(first_state.hand, second_state.hand), "same combat seed should produce identical opening hands")
	_assert(_arrays_equal(_intent_ids(first_state), _intent_ids(second_state)), "same combat seed should produce identical enemy intents")
	_assert(first_state.rng == second_state.rng, "same combat seed should consume identical rng state")


func _assert_difficulty_values_still_differ(database: Dictionary) -> void:
	var d0_combat := CombatManager.new(database)
	d0_combat.start_combat("ember_ranger", "D0", ["mote_biter"], 424242)
	var d0_state := d0_combat.get_public_state()

	var d1_combat := CombatManager.new(database)
	d1_combat.start_combat("ember_ranger", "D1", ["mote_biter"], 424242)
	var d1_state := d1_combat.get_public_state()

	_assert(int(d0_state.player.max_hp) > int(d1_state.player.max_hp), "D0 player max hp should remain higher than D1")
	_assert(int(d0_state.enemies[0].max_hp) < int(d1_state.enemies[0].max_hp), "D0 enemy max hp should remain lower than D1")

	var enemy_data: Dictionary = database.enemies["mote_biter"]
	var d0_damage := _first_configured_damage(enemy_data, d0_state.difficulty)
	var d1_damage := _first_configured_damage(enemy_data, d1_state.difficulty)
	_assert(d0_damage < d1_damage, "D0 enemy attack damage should remain lower than D1")


func _arrays_equal(first: Array, second: Array) -> bool:
	if first.size() != second.size():
		return false
	for i in range(first.size()):
		if first[i] != second[i]:
			return false
	return true


func _intent_ids(combat_state: Dictionary) -> Array[String]:
	var ids: Array[String] = []
	for enemy in combat_state.enemies:
		ids.append(String(enemy.get("intent_move", {}).get("id", "")))
	return ids


func _first_configured_damage(enemy_data: Dictionary, difficulty: Dictionary) -> int:
	for move in enemy_data.moves:
		for effect in move.get("effects", []):
			if String(effect.get("op", "")) == "damage":
				return int(round(float(effect.get("value", 0)) * float(difficulty.base_adjustments.enemy_damage_multiplier)))
	return 0


func _assert(condition: bool, message: String) -> void:
	if not condition:
		failed = true
		push_error(message)
