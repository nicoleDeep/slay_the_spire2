extends SceneTree

const CombatManager = preload("res://scripts/combat/combat_manager.gd")
const DataLoader = preload("res://scripts/core/data_loader.gd")

var failed := false


func _init() -> void:
	var database := DataLoader.load_content_database()
	_test_full_hand(database)
	_test_illegal_target(database)
	_test_multihit_mid_resolution_kill(database)
	if failed:
		quit(1)
		return
	print("M1 boundary fixtures passed")
	quit(0)


func _test_full_hand(database: Dictionary) -> void:
	var combat := CombatManager.new(database)
	combat.start_combat("ember_ranger", "D1", ["mote_biter"], 101)
	combat.state.hand = []
	for index in range(10):
		combat.state.hand.append("ash_guard")
	combat.state.draw_pile = ["ember_cut"]
	var discard_before: int = combat.state.discard_pile.size()
	combat.draw_cards(1)
	_assert(combat.state.hand.size() == 10, "full hand must remain capped at 10")
	_assert(combat.state.discard_pile.size() == discard_before + 1, "overflow draw must move to discard")


func _test_illegal_target(database: Dictionary) -> void:
	var combat := CombatManager.new(database)
	combat.start_combat("ember_ranger", "D1", ["mote_biter"], 202)
	combat.state.hand = ["ember_cut"]
	combat.state.player.energy = 3
	combat.state.enemies[0].hp = 0
	var before := combat.get_public_state()
	_assert(not combat.play_card(0, 0), "dead enemy must not be a legal target")
	var after := combat.get_public_state()
	_assert(after.hand == before.hand, "illegal target must not remove card")
	_assert(after.player.energy == before.player.energy, "illegal target must not spend energy")


func _test_multihit_mid_resolution_kill(database: Dictionary) -> void:
	var combat := CombatManager.new(database)
	combat.start_combat("ember_ranger", "D1", ["mote_biter"], 303)
	combat.state.hand = ["char_mark"]
	combat.state.player.energy = 3
	combat.state.enemies[0].hp = 2
	_assert(combat.play_card(0, 0), "multi-hit card should be playable")
	var after := combat.get_public_state()
	_assert(after.phase == "victory", "first hit lethal must produce victory")
	_assert(after.combat_log.has("Damage skipped: no legal target"), "later target-dependent hit must be skipped")


func _assert(condition: bool, message: String) -> void:
	if not condition:
		failed = true
		push_error(message)
