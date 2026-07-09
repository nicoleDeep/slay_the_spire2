extends SceneTree

const CombatManager = preload("res://scripts/combat/combat_manager.gd")
const ContentValidator = preload("res://scripts/core/content_validator.gd")
const DataLoader = preload("res://scripts/core/data_loader.gd")

func _init() -> void:
	var database := DataLoader.load_content_database()
	var validation := ContentValidator.validate_all(database)
	_assert(validation.ok, "content validation failed: %s" % str(validation.errors))
	_assert(database.characters.has("ember_ranger"), "missing ember_ranger")
	_assert(database.cards.size() >= 25, "expected at least 25 cards")
	_assert(database.enemies.size() >= 11, "expected 11 M1 enemies")
	_assert(database.difficulties.has("D0") and database.difficulties.has("D1"), "missing D0/D1")

	var d0_combat := CombatManager.new(database)
	d0_combat.start_combat("ember_ranger", "D0", ["mote_biter"], 777)
	var d0_state := d0_combat.get_public_state()
	var d1_combat := CombatManager.new(database)
	d1_combat.start_combat("ember_ranger", "D1", ["mote_biter"], 777)
	var d1_state := d1_combat.get_public_state()
	_assert(d0_state.hand.size() == 5, "D0 should draw 5 cards")
	_assert(d1_state.hand.size() == 5, "D1 should draw 5 cards")
	_assert(int(d0_state.enemies[0].max_hp) < int(d1_state.enemies[0].max_hp), "D0 enemy hp should be lower than D1")

	var played_damage := _play_first_card_with_op(d1_combat, "damage")
	_assert(played_damage, "could not play a damage card from opening hand")
	var after_damage := d1_combat.get_public_state()
	_assert(int(after_damage.enemies[0].hp) < int(d1_state.enemies[0].hp), "damage card did not reduce enemy hp")

	var block_combat := CombatManager.new(database)
	block_combat.start_combat("ember_ranger", "D1", ["mote_biter"], 2)
	var played_block := _play_first_card_with_op(block_combat, "gain_block")
	_assert(played_block, "could not play a block card from opening hand")
	_assert(int(block_combat.get_public_state().player.block) > 0, "block card did not add block")

	var lethal := CombatManager.new(database)
	lethal.start_combat("ember_ranger", "D1", ["ash_flock_a"], 11)
	for i in range(12):
		if lethal.get_public_state().phase == "victory":
			break
		if not _play_first_card_with_op(lethal, "damage"):
			lethal.end_player_turn()
	_assert(lethal.get_public_state().phase == "victory", "enemy should be killable")

	var defeat := CombatManager.new(database)
	defeat.start_combat("ember_ranger", "D1", ["brass_heartwood"], 5)
	defeat.state.player.hp = 1
	for i in range(8):
		if defeat.get_public_state().phase == "defeat":
			break
		defeat.end_player_turn()
	_assert(defeat.get_public_state().phase == "defeat", "player should be killable")

	print("M1 smoke test passed")
	quit(0)


func _play_first_card_with_op(combat: CombatManager, op: String) -> bool:
	for turn_attempt in 6:
		var state := combat.get_public_state()
		if state.phase != "player_turn":
			return false
		for i in range(state.hand.size()):
			var card := combat.get_card(state.hand[i])
			for effect in card.effects:
				if String(effect.get("op", "")) == op and combat.can_play_card(i, 0):
					return combat.play_card(i, 0)
		combat.end_player_turn()
		if combat.get_public_state().phase in ["victory", "defeat"]:
			return false
	return false


func _assert(condition: bool, message: String) -> void:
	if not condition:
		push_error(message)
		quit(1)
