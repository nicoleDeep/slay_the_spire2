extends Control

const CombatManager = preload("res://scripts/combat/combat_manager.gd")
const ContentValidator = preload("res://scripts/core/content_validator.gd")
const DataLoader = preload("res://scripts/core/data_loader.gd")

var combat: CombatManager
var selected_enemy_index := 0

var summary_label: Label
var enemy_box: VBoxContainer
var hand_box: HBoxContainer
var log_label: Label
var end_turn_button: Button
var restart_d0_button: Button
var restart_d1_button: Button

func _ready() -> void:
	_build_ui()
	_start("D1")


func _build_ui() -> void:
	var root := MarginContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("margin_left", 18)
	root.add_theme_constant_override("margin_top", 18)
	root.add_theme_constant_override("margin_right", 18)
	root.add_theme_constant_override("margin_bottom", 18)
	add_child(root)

	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 12)
	root.add_child(layout)

	var top_bar := HBoxContainer.new()
	top_bar.add_theme_constant_override("separation", 10)
	layout.add_child(top_bar)

	summary_label = Label.new()
	summary_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_bar.add_child(summary_label)

	restart_d0_button = Button.new()
	restart_d0_button.text = "D0"
	restart_d0_button.pressed.connect(func() -> void: _start("D0"))
	top_bar.add_child(restart_d0_button)

	restart_d1_button = Button.new()
	restart_d1_button.text = "D1"
	restart_d1_button.pressed.connect(func() -> void: _start("D1"))
	top_bar.add_child(restart_d1_button)

	end_turn_button = Button.new()
	end_turn_button.text = "End Turn"
	end_turn_button.pressed.connect(func() -> void:
		combat.end_player_turn()
		_render()
	)
	top_bar.add_child(end_turn_button)

	enemy_box = VBoxContainer.new()
	enemy_box.add_theme_constant_override("separation", 8)
	layout.add_child(enemy_box)

	hand_box = HBoxContainer.new()
	hand_box.add_theme_constant_override("separation", 8)
	layout.add_child(hand_box)

	log_label = Label.new()
	log_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	log_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(log_label)


func _start(difficulty: String) -> void:
	var database := DataLoader.load_content_database()
	var validation := ContentValidator.validate_all(database)
	if not validation.ok:
		push_error("Content validation failed: %s" % str(validation.errors))
	combat = CombatManager.new(database)
	combat.start_combat("ember_ranger", difficulty, ["mote_biter"], 424242)
	selected_enemy_index = 0
	_render()


func _render() -> void:
	var state := combat.get_public_state()
	summary_label.text = "Difficulty %s | HP %d/%d | Block %d | Energy %d | Draw %d | Discard %d | Turn %d | %s" % [
		state.difficulty.id,
		state.player.hp,
		state.player.max_hp,
		state.player.block,
		state.player.energy,
		state.draw_pile.size(),
		state.discard_pile.size(),
		state.turn_index,
		state.phase
	]
	end_turn_button.disabled = state.phase != "player_turn"

	for child in enemy_box.get_children():
		child.queue_free()
	for i in range(state.enemies.size()):
		var enemy_index := i
		var enemy: Dictionary = state.enemies[i]
		var button := Button.new()
		var intent := enemy.get("intent_move", {})
		var intent_text := "%s (%s)" % [intent.get("id", "none"), intent.get("intent", "unknown")]
		button.text = "%s HP %d/%d Block %d Intent %s" % [enemy.name, enemy.hp, enemy.max_hp, enemy.block, intent_text]
		button.disabled = int(enemy.hp) <= 0
		button.pressed.connect(func() -> void:
			selected_enemy_index = enemy_index
			_render()
		)
		enemy_box.add_child(button)

	for child in hand_box.get_children():
		child.queue_free()
	for i in range(state.hand.size()):
		var hand_index := i
		var card_id: String = state.hand[i]
		var card := combat.get_card(card_id)
		var card_button := Button.new()
		card_button.custom_minimum_size = Vector2(150, 110)
		card_button.text = "%s\nCost %d\n%s" % [card.name, card.cost, _describe_effects(card.effects)]
		card_button.disabled = not combat.can_play_card(i, selected_enemy_index)
		card_button.pressed.connect(func() -> void:
			combat.play_card(hand_index, selected_enemy_index)
			_render()
		)
		hand_box.add_child(card_button)

	var recent_log := state.combat_log.slice(max(0, state.combat_log.size() - 12), state.combat_log.size())
	log_label.text = "\n".join(recent_log)


func _describe_effects(effects: Array) -> String:
	var parts: Array[String] = []
	for effect in effects:
		match String(effect.get("op", "")):
			"damage":
				parts.append("Damage %d x%d" % [effect.get("value", 0), effect.get("count", 1)])
			"gain_block":
				parts.append("Block %d" % effect.get("value", 0))
			"draw":
				parts.append("Draw %d" % effect.get("count", 1))
	return ", ".join(parts)
