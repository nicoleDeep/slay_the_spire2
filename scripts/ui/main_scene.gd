extends Control

signal feedback_requested(kind: String, payload: Dictionary)
signal sfx_requested(sfx_id: String)
signal save_feedback(ok: bool, code: String)

const ContentValidator = preload("res://scripts/core/content_validator.gd")
const DataLoader = preload("res://scripts/core/data_loader.gd")
const RunManager = preload("res://scripts/run/run_manager.gd")

const ICONS := {
	"normal": "res://art/ui/m2/node_normal.svg",
	"elite": "res://art/ui/m2/node_elite.svg",
	"boss": "res://art/ui/m2/node_boss.svg",
	"shop": "res://art/ui/m2/node_shop.svg",
	"event": "res://art/ui/m2/node_event.svg",
	"rest": "res://art/ui/m2/node_rest.svg",
	"treasure": "res://art/ui/m2/node_treasure.svg",
	"reward": "res://art/ui/m2/icon_reward.svg",
	"relic": "res://art/ui/m2/icon_relic.svg",
	"potion": "res://art/ui/m2/icon_potion.svg",
	"save": "res://art/ui/m2/icon_save.svg",
	"intent_attack": "res://art/ui/m2/intent_attack.svg",
	"intent_block": "res://art/ui/m2/intent_block.svg"
}

const SFX := {
	"button": "res://audio/sfx/m2/ui_tick.wav",
	"reward": "res://audio/sfx/m2/reward_chime.wav",
	"gold": "res://audio/sfx/m2/gold_gain.wav",
	"error": "res://audio/sfx/m2/error_low.wav",
	"save_ok": "res://audio/sfx/m2/save_ok.wav",
	"node": "res://audio/sfx/m2/node_select.wav",
	"shop": "res://audio/sfx/m2/shop_buy.wav",
	"rest": "res://audio/sfx/m2/rest_soft.wav"
}

var database: Dictionary
var run_manager: RunManager
var selected_node_id := ""
var selected_deck_card_id := ""
var selected_potion_slot := -1

var audio_player: AudioStreamPlayer
var title_label: Label
var status_label: Label
var save_label: Label
var resource_label: Label
var setup_panel: VBoxContainer
var run_panel: HBoxContainer
var map_grid: GridContainer
var detail_panel: VBoxContainer
var action_panel: VBoxContainer
var deck_select: OptionButton
var potion_slot_select: OptionButton
var character_select: OptionButton
var difficulty_select: OptionButton
var seed_input: LineEdit
var icon_cache := {}


func _ready() -> void:
	database = DataLoader.load_content_database()
	_build_ui()
	_connect_feedback()
	_validate_content()


func _build_ui() -> void:
	var root := MarginContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("margin_left", 18)
	root.add_theme_constant_override("margin_top", 18)
	root.add_theme_constant_override("margin_right", 18)
	root.add_theme_constant_override("margin_bottom", 18)
	add_child(root)

	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 10)
	root.add_child(layout)

	var top_bar := HBoxContainer.new()
	top_bar.add_theme_constant_override("separation", 10)
	layout.add_child(top_bar)

	title_label = Label.new()
	title_label.text = "M2 Run"
	title_label.add_theme_font_size_override("font_size", 28)
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_bar.add_child(title_label)

	var load_button := Button.new()
	load_button.text = "Continue"
	load_button.icon = _icon("save")
	load_button.pressed.connect(_load_run)
	top_bar.add_child(load_button)

	var combat_button := Button.new()
	combat_button.text = "M1 Combat"
	combat_button.pressed.connect(func() -> void:
		_emit_sfx("button")
		get_tree().change_scene_to_file("res://scenes/combat/combat.tscn")
	)
	top_bar.add_child(combat_button)

	status_label = Label.new()
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	layout.add_child(status_label)

	resource_label = Label.new()
	resource_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	layout.add_child(resource_label)

	save_label = Label.new()
	save_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	layout.add_child(save_label)

	setup_panel = VBoxContainer.new()
	setup_panel.add_theme_constant_override("separation", 8)
	layout.add_child(setup_panel)
	_build_setup_panel()

	run_panel = HBoxContainer.new()
	run_panel.add_theme_constant_override("separation", 14)
	run_panel.visible = false
	run_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(run_panel)

	var map_scroll := ScrollContainer.new()
	map_scroll.custom_minimum_size = Vector2(620, 520)
	map_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	map_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	run_panel.add_child(map_scroll)

	map_grid = GridContainer.new()
	map_grid.columns = 1
	map_grid.add_theme_constant_override("h_separation", 6)
	map_grid.add_theme_constant_override("v_separation", 6)
	map_scroll.add_child(map_grid)

	var right_column := VBoxContainer.new()
	right_column.custom_minimum_size = Vector2(480, 520)
	right_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_column.add_theme_constant_override("separation", 10)
	run_panel.add_child(right_column)

	detail_panel = VBoxContainer.new()
	detail_panel.add_theme_constant_override("separation", 8)
	right_column.add_child(detail_panel)

	action_panel = VBoxContainer.new()
	action_panel.add_theme_constant_override("separation", 8)
	right_column.add_child(action_panel)

	audio_player = AudioStreamPlayer.new()
	add_child(audio_player)


func _build_setup_panel() -> void:
	var character_label := Label.new()
	character_label.text = "Character"
	setup_panel.add_child(character_label)
	character_select = OptionButton.new()
	for character_id in database.characters.keys():
		var index := character_select.item_count
		character_select.add_item(_character_name(String(character_id)))
		character_select.set_item_metadata(index, character_id)
	setup_panel.add_child(character_select)

	var difficulty_label := Label.new()
	difficulty_label.text = "Difficulty"
	setup_panel.add_child(difficulty_label)
	difficulty_select = OptionButton.new()
	var difficulty_ids: Array = database.difficulties.keys()
	difficulty_ids.sort()
	for difficulty_id in difficulty_ids:
		var index := difficulty_select.item_count
		difficulty_select.add_item("%s - %s" % [difficulty_id, database.difficulties[difficulty_id].name])
		difficulty_select.set_item_metadata(index, difficulty_id)
	difficulty_select.select(mini(1, max(0, difficulty_select.item_count - 1)))
	setup_panel.add_child(difficulty_select)

	seed_input = LineEdit.new()
	seed_input.placeholder_text = "Run seed"
	seed_input.text = "424242"
	setup_panel.add_child(seed_input)

	var create_button := Button.new()
	create_button.text = "Create Run"
	create_button.icon = _icon("normal")
	create_button.pressed.connect(_create_run)
	setup_panel.add_child(create_button)


func _connect_feedback() -> void:
	sfx_requested.connect(_play_sfx)
	save_feedback.connect(func(ok: bool, code: String) -> void:
		save_label.text = "Save OK" if ok else "Save failed: %s" % code
		save_label.add_theme_color_override("font_color", Color("#d6ffe2") if ok else Color("#ffb0a5"))
		_emit_sfx("save_ok" if ok else "error")
	)
	feedback_requested.connect(func(kind: String, payload: Dictionary) -> void:
		status_label.text = "%s: %s" % [kind, payload.get("message", payload.get("code", "OK"))]
	)


func _validate_content() -> void:
	var validation := ContentValidator.validate_all(database)
	if validation.ok:
		status_label.text = "Content validation OK. Create or continue a run."
	else:
		status_label.text = "Content validation failed: %s" % str(validation.errors)
		status_label.add_theme_color_override("font_color", Color("#ffb0a5"))


func _create_run() -> void:
	var character_id := String(character_select.get_item_metadata(character_select.selected))
	var difficulty_id := String(difficulty_select.get_item_metadata(difficulty_select.selected))
	run_manager = RunManager.new(database)
	var result := run_manager.create_run(character_id, difficulty_id, int(seed_input.text))
	_handle_result(result, "run_created")
	if result.ok:
		selected_node_id = ""
		selected_deck_card_id = ""
		selected_potion_slot = -1
		setup_panel.visible = false
		run_panel.visible = true
		_render()


func _load_run() -> void:
	run_manager = RunManager.new(database)
	var result := run_manager.load_run()
	_handle_result(result, "run_loaded")
	if result.ok:
		selected_node_id = ""
		selected_deck_card_id = ""
		selected_potion_slot = -1
		setup_panel.visible = false
		run_panel.visible = true
		_render()


func _render() -> void:
	_clear(map_grid)
	_clear(detail_panel)
	_clear(action_panel)
	if run_manager == null or run_manager.get_state().is_empty():
		return
	var state := run_manager.get_state()
	_render_resources(state)
	_render_map(state)
	_render_detail(state)
	_render_actions(state)


func _render_resources(state: Dictionary) -> void:
	var potion_parts: Array[String] = []
	for i in range(state.get("potions", []).size()):
		var potion_id = state.potions[i]
		potion_parts.append("Slot %d: %s" % [i + 1, "empty" if potion_id == null else _potion_name(String(potion_id))])
	resource_label.text = "Phase %s | HP %d/%d | Gold %d | Deck %d | Relics %d | Potions [%s]" % [
		state.get("phase", ""),
		int(state.get("hp", 0)),
		int(state.get("max_hp", 0)),
		int(state.get("gold", 0)),
		state.get("deck", []).size(),
		state.get("relic_ids", []).size(),
		"; ".join(potion_parts)
	]


func _render_map(state: Dictionary) -> void:
	var floors: Array = state.get("map", {}).get("floors", [])
	map_grid.columns = 1
	for floor_data in floors:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		map_grid.add_child(row)

		var floor_label := Label.new()
		floor_label.custom_minimum_size = Vector2(62, 34)
		floor_label.text = "F%02d" % int(floor_data.get("floor", 0))
		row.add_child(floor_label)

		var nodes: Array = floor_data.get("nodes", [])
		nodes.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return float(a.get("x", 0.0)) < float(b.get("x", 0.0))
		)
		for node in nodes:
			var node_id := String(node.get("id", ""))
			var node_type := String(node.get("type", "normal"))
			var status := String(node.get("status", "locked"))
			var button := Button.new()
			button.custom_minimum_size = Vector2(112, 54)
			button.text = "%s\n%s" % [_short_node_label(node_type), status]
			button.icon = _icon(node_type)
			button.disabled = not status in ["available", "current", "completed"]
			button.tooltip_text = "%s | %s | edges: %s" % [node_id, node_type, ", ".join(_string_array(node.get("edges", [])))]
			_style_node_button(button, status, node_id == selected_node_id)
			button.pressed.connect(func() -> void:
				selected_node_id = node_id
				_emit_sfx("node")
				_render()
			)
			row.add_child(button)


func _render_detail(state: Dictionary) -> void:
	var heading := Label.new()
	heading.add_theme_font_size_override("font_size", 20)
	detail_panel.add_child(heading)
	var node := _selected_or_current_node(state)
	if node.is_empty():
		heading.text = "Select an available route node"
		_add_note(detail_panel, "Locked nodes are disabled. Available nodes are bright. Completed nodes stay visible but cannot be re-entered.")
		return
	heading.text = "%s %s" % [_node_name(String(node.get("type", ""))), String(node.get("id", ""))]
	_add_note(detail_panel, "Status: %s" % String(node.get("status", "")))
	_add_note(detail_panel, "Routes onward: %s" % ", ".join(_string_array(node.get("edges", []))))
	var ref = node.get("content_ref")
	if ref != null:
		_add_note(detail_panel, "Content: %s" % String(ref))
	if state.get("pending_resolution") != null:
		_add_note(detail_panel, "Pending: %s" % String(state.pending_resolution.get("kind", "")))


func _render_actions(state: Dictionary) -> void:
	var heading := Label.new()
	heading.text = "Actions"
	heading.add_theme_font_size_override("font_size", 20)
	action_panel.add_child(heading)
	if String(state.get("phase", "")) == "map":
		_render_map_actions(state)
		return
	var pending = state.get("pending_resolution")
	if pending == null:
		_render_node_entry_actions()
		return
	match String(pending.get("kind", "")):
		"combat":
			_render_combat_actions(pending)
		"reward":
			_render_reward_actions(state, pending)
		"shop":
			_render_shop_actions(state, pending)
		"event":
			_render_event_actions(state, pending)
		"rest":
			_render_rest_actions(state, pending)
		_:
			_add_note(action_panel, "Unknown pending resolution.")


func _render_map_actions(state: Dictionary) -> void:
	var node := _selected_or_current_node(state)
	if node.is_empty():
		_add_note(action_panel, "Choose one of the available route nodes.")
		return
	var enter_button := Button.new()
	enter_button.text = "Enter %s" % _node_name(String(node.get("type", "")))
	enter_button.icon = _icon(String(node.get("type", "normal")))
	enter_button.disabled = String(node.get("status", "")) != "available"
	enter_button.pressed.connect(func() -> void:
		var result := run_manager.enter_node(String(node.get("id", "")))
		_handle_result(result, "node_entered")
		if result.ok:
			result = run_manager.start_current_node_resolution()
			_handle_result(result, "node_opened")
		_render()
	)
	action_panel.add_child(enter_button)
	_add_note(action_panel, "Completed and unreachable nodes are intentionally not actionable.")


func _render_node_entry_actions() -> void:
	var open_button := Button.new()
	open_button.text = "Open Node"
	open_button.pressed.connect(func() -> void:
		var result := run_manager.start_current_node_resolution()
		_handle_result(result, "node_opened")
		_render()
	)
	action_panel.add_child(open_button)


func _render_combat_actions(pending: Dictionary) -> void:
	_add_note(action_panel, "Combat placeholder uses M1 combat state, enemy silhouette, and intent icon.")
	var combat_state: Dictionary = pending.get("combat_state", {})
	for enemy in combat_state.get("enemies", []):
		var intent: Dictionary = enemy.get("intent_move", {})
		var enemy_line := HBoxContainer.new()
		enemy_line.add_theme_constant_override("separation", 8)
		action_panel.add_child(enemy_line)
		var icon := TextureRect.new()
		icon.texture = _icon("intent_attack" if String(intent.get("intent", "")) == "attack" else "intent_block")
		icon.custom_minimum_size = Vector2(40, 40)
		enemy_line.add_child(icon)
		var label := Label.new()
		label.text = "%s HP %d/%d | Intent %s" % [
			enemy.get("name", "Enemy"),
			int(enemy.get("hp", 0)),
			int(enemy.get("max_hp", 0)),
			intent.get("intent", "unknown")
		]
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		enemy_line.add_child(label)
	var win_button := Button.new()
	win_button.text = "Resolve Test Victory"
	win_button.icon = _icon("reward")
	win_button.pressed.connect(func() -> void:
		var result := run_manager.debug_autoresolve_current_combat_victory()
		_handle_result(result, "combat_victory")
		_render()
	)
	action_panel.add_child(win_button)


func _render_reward_actions(state: Dictionary, reward: Dictionary) -> void:
	_emit_feedback("reward_visible", {"message": "Reward can be taken or skipped without reading debug logs."})
	_add_note(action_panel, "Gold: %d %s" % [int(reward.get("gold", {}).get("amount", 0)), "(claimed)" if bool(reward.get("gold", {}).get("claimed", false)) else ""])
	var gold_button := Button.new()
	gold_button.text = "Claim Gold"
	gold_button.icon = _icon("reward")
	gold_button.disabled = bool(reward.get("gold", {}).get("claimed", false))
	gold_button.pressed.connect(func() -> void:
		_handle_result(run_manager.reward_claim_gold(), "gold_claimed")
		_emit_sfx("gold")
		_render()
	)
	action_panel.add_child(gold_button)

	var card_offer: Dictionary = reward.get("card_offer", {})
	for card_id in card_offer.get("candidate_ids", []):
		var id := String(card_id)
		var button := Button.new()
		button.custom_minimum_size = Vector2(220, 86)
		button.text = _card_button_text(id)
		button.disabled = bool(card_offer.get("skipped", false)) or card_offer.get("selected_instance_id") != null
		button.pressed.connect(func() -> void:
			_handle_result(run_manager.reward_choose_card(id), "card_chosen")
			_emit_sfx("reward")
			_render()
		)
		action_panel.add_child(button)
	var skip_button := Button.new()
	skip_button.text = "Skip Card Reward"
	skip_button.disabled = bool(card_offer.get("skipped", false)) or card_offer.get("selected_instance_id") != null
	skip_button.pressed.connect(func() -> void:
		_handle_result(run_manager.reward_skip_card(), "card_skipped")
		_emit_sfx("button")
		_render()
	)
	action_panel.add_child(skip_button)

	if reward.get("relic_offer") != null:
		var relic_id := String(reward.relic_offer.get("relic_id", ""))
		var relic_button := Button.new()
		relic_button.text = "Claim Relic: %s" % _relic_name(relic_id)
		relic_button.icon = _icon("relic")
		relic_button.disabled = bool(reward.relic_offer.get("claimed", false))
		relic_button.pressed.connect(func() -> void:
			_handle_result(run_manager.reward_claim_relic(), "relic_claimed")
			_emit_sfx("reward")
			_render()
		)
		action_panel.add_child(relic_button)

	if reward.get("potion_offer") != null:
		_render_potion_offer(state, reward.potion_offer)

	var finish_button := Button.new()
	finish_button.text = "Finish Reward and Save"
	finish_button.icon = _icon("save")
	finish_button.disabled = not bool(reward.get("complete", false))
	finish_button.pressed.connect(func() -> void:
		_handle_result(run_manager.reward_finish(), "reward_finished")
		_render()
	)
	action_panel.add_child(finish_button)


func _render_potion_offer(state: Dictionary, offer: Dictionary) -> void:
	var potion_id := String(offer.get("potion_id", ""))
	_add_note(action_panel, "Potion: %s %s" % [_potion_name(potion_id), "(resolved)" if bool(offer.get("claimed", false)) or bool(offer.get("declined", false)) else ""])
	var full := _first_empty_potion_slot(state) == -1
	if full:
		_add_note(action_panel, "Potion slots full: choose a replacement slot or decline.")
	_render_potion_slot_select(state)
	var claim := Button.new()
	claim.text = "Claim Potion" if not full else "Replace Selected Potion"
	claim.icon = _icon("potion")
	claim.disabled = bool(offer.get("claimed", false)) or bool(offer.get("declined", false)) or (full and selected_potion_slot < 0)
	claim.pressed.connect(func() -> void:
		var replace_slot = null if selected_potion_slot < 0 else selected_potion_slot
		_handle_result(run_manager.reward_claim_or_decline_potion(replace_slot, false), "potion_claimed")
		_emit_sfx("reward")
		_render()
	)
	action_panel.add_child(claim)
	var decline := Button.new()
	decline.text = "Decline Potion"
	decline.disabled = bool(offer.get("claimed", false)) or bool(offer.get("declined", false))
	decline.pressed.connect(func() -> void:
		_handle_result(run_manager.reward_claim_or_decline_potion(null, true), "potion_declined")
		_emit_sfx("button")
		_render()
	)
	action_panel.add_child(decline)


func _render_shop_actions(state: Dictionary, shop: Dictionary) -> void:
	_add_note(action_panel, "Shop prices reflect current difficulty and gold. Unaffordable items are disabled.")
	for item in shop.get("items", []):
		var item_data: Dictionary = item
		var buy := Button.new()
		buy.text = "%s %s - %d gold%s" % [
			String(item_data.get("kind", "")).capitalize(),
			_content_name(String(item_data.get("kind", "")), String(item_data.get("content_id", ""))),
			int(item_data.get("final_price", 0)),
			" (sold)" if bool(item_data.get("sold", false)) else ""
		]
		buy.icon = _icon("potion" if String(item_data.get("kind", "")) == "potion" else "relic" if String(item_data.get("kind", "")) == "relic" else "reward")
		buy.disabled = bool(item_data.get("sold", false)) or int(state.get("gold", 0)) < int(item_data.get("final_price", 0)) or (String(item_data.get("kind", "")) == "potion" and _first_empty_potion_slot(state) == -1 and selected_potion_slot < 0)
		buy.tooltip_text = "Need %d gold" % int(item_data.get("final_price", 0)) if int(state.get("gold", 0)) < int(item_data.get("final_price", 0)) else ""
		buy.pressed.connect(func() -> void:
			var replace_slot = null if selected_potion_slot < 0 else selected_potion_slot
			_handle_result(run_manager.shop_buy(String(item_data.get("slot_id", "")), replace_slot), "shop_bought")
			_emit_sfx("shop")
			_render()
		)
		action_panel.add_child(buy)
	if _first_empty_potion_slot(state) == -1:
		_add_note(action_panel, "Potion slots full: potion purchases require a selected replacement slot.")
		_render_potion_slot_select(state)

	_render_deck_select(state, "Remove target")
	var remove_service: Dictionary = shop.get("remove_service", {})
	var remove_button := Button.new()
	remove_button.text = "Remove Selected Card - %d gold%s" % [
		int(remove_service.get("final_price", 0)),
		" (used)" if bool(remove_service.get("used", false)) else ""
	]
	remove_button.disabled = bool(remove_service.get("used", false)) or selected_deck_card_id.is_empty() or int(state.get("gold", 0)) < int(remove_service.get("final_price", 0))
	remove_button.pressed.connect(func() -> void:
		_handle_result(run_manager.shop_remove_card(selected_deck_card_id), "card_removed")
		_emit_sfx("shop")
		selected_deck_card_id = ""
		_render()
	)
	action_panel.add_child(remove_button)

	var close := Button.new()
	close.text = "Leave Shop and Save"
	close.icon = _icon("save")
	close.pressed.connect(func() -> void:
		_handle_result(run_manager.shop_close(), "shop_closed")
		_render()
	)
	action_panel.add_child(close)


func _render_event_actions(state: Dictionary, event_instance: Dictionary) -> void:
	var event_id := String(event_instance.get("event_id", ""))
	var event_data: Dictionary = database.get("events", {}).get(event_id, {})
	_add_note(action_panel, event_data.get("title", event_id))
	_render_deck_select(state, "Manual card selection")
	for option in event_instance.get("options", []):
		var option_data: Dictionary = option
		var button := Button.new()
		button.text = "%s%s" % [
			String(option_data.get("id", "")),
			" - unavailable: %s" % String(option_data.get("unavailable_reason", "")) if not bool(option_data.get("legal", false)) else ""
		]
		button.disabled = not bool(option_data.get("legal", false)) or _option_needs_card(option_data) and selected_deck_card_id.is_empty()
		button.pressed.connect(func() -> void:
			var selection := {}
			if _option_needs_card(option_data):
				selection.card_instance_id = selected_deck_card_id
			_handle_result(run_manager.event_choose_option(String(option_data.get("id", "")), selection), "event_option")
			_emit_sfx("reward")
			selected_deck_card_id = ""
			_render()
		)
		action_panel.add_child(button)


func _render_rest_actions(state: Dictionary, rest: Dictionary) -> void:
	_add_note(action_panel, "Rest site: choose one legal action.")
	var heal: Dictionary = rest.get("actions", {}).get("heal", {})
	var heal_button := Button.new()
	heal_button.text = "Heal %d HP" % int(heal.get("amount", 0))
	heal_button.icon = _icon("rest")
	heal_button.disabled = not bool(heal.get("enabled", false))
	heal_button.pressed.connect(func() -> void:
		_handle_result(run_manager.rest_resolve("heal"), "rest_heal")
		_emit_sfx("rest")
		_render()
	)
	action_panel.add_child(heal_button)

	_render_deck_select(state, "Upgrade target")
	var upgrade: Dictionary = rest.get("actions", {}).get("upgrade", {})
	var upgrade_button := Button.new()
	upgrade_button.text = "Upgrade Selected Card"
	upgrade_button.disabled = not bool(upgrade.get("enabled", false)) or selected_deck_card_id.is_empty() or not upgrade.get("candidate_instance_ids", []).has(selected_deck_card_id)
	upgrade_button.pressed.connect(func() -> void:
		_handle_result(run_manager.rest_resolve("upgrade", selected_deck_card_id), "rest_upgrade")
		_emit_sfx("rest")
		selected_deck_card_id = ""
		_render()
	)
	action_panel.add_child(upgrade_button)
	if not bool(upgrade.get("enabled", false)):
		_add_note(action_panel, "Upgrade unavailable: no legal card targets.")


func _render_deck_select(state: Dictionary, label_text: String) -> void:
	var label := Label.new()
	label.text = label_text
	action_panel.add_child(label)
	deck_select = OptionButton.new()
	deck_select.add_item("No card selected")
	deck_select.set_item_metadata(0, "")
	var index := 1
	for card_instance in state.get("deck", []):
		var card: Dictionary = card_instance
		var card_id := String(card.get("card_id", ""))
		deck_select.add_item("%s | %s%s" % [
			String(card.get("instance_id", "")),
			_card_name(card_id),
			"+" if int(card.get("upgrade", 0)) > 0 else ""
		])
		deck_select.set_item_metadata(index, String(card.get("instance_id", "")))
		if String(card.get("instance_id", "")) == selected_deck_card_id:
			deck_select.select(index)
		index += 1
	deck_select.item_selected.connect(func(item_index: int) -> void:
		selected_deck_card_id = String(deck_select.get_item_metadata(item_index))
		_render()
	)
	action_panel.add_child(deck_select)


func _render_potion_slot_select(state: Dictionary) -> void:
	var label := Label.new()
	label.text = "Potion replacement slot"
	action_panel.add_child(label)
	potion_slot_select = OptionButton.new()
	potion_slot_select.add_item("No slot selected")
	potion_slot_select.set_item_metadata(0, -1)
	for i in range(state.get("potions", []).size()):
		var potion_id = state.potions[i]
		var index := potion_slot_select.item_count
		potion_slot_select.add_item("Slot %d: %s" % [i + 1, "empty" if potion_id == null else _potion_name(String(potion_id))])
		potion_slot_select.set_item_metadata(index, i)
		if i == selected_potion_slot:
			potion_slot_select.select(index)
	potion_slot_select.item_selected.connect(func(item_index: int) -> void:
		selected_potion_slot = int(potion_slot_select.get_item_metadata(item_index))
		_render()
	)
	action_panel.add_child(potion_slot_select)


func _selected_or_current_node(state: Dictionary) -> Dictionary:
	if not selected_node_id.is_empty():
		var selected := _find_node(state, selected_node_id)
		if not selected.is_empty():
			return selected
	var current_id = state.get("current_node_id")
	if current_id != null:
		return _find_node(state, String(current_id))
	return {}


func _find_node(state: Dictionary, node_id: String) -> Dictionary:
	for floor_data in state.get("map", {}).get("floors", []):
		for node in floor_data.get("nodes", []):
			if String(node.get("id", "")) == node_id:
				return node
	return {}


func _handle_result(result: Dictionary, kind: String) -> void:
	if result.get("ok", false):
		_emit_feedback(kind, {"message": result.get("code", "OK")})
		emit_signal("save_feedback", true, result.get("code", "OK"))
	else:
		_emit_feedback(kind, {"message": "%s: %s" % [result.get("code", "ERR"), result.get("message", "")]})
		if String(result.get("code", "")).begins_with("ERR_SAVE"):
			emit_signal("save_feedback", false, result.get("code", "ERR_SAVE"))
		else:
			_emit_sfx("error")


func _style_node_button(button: Button, status: String, selected: bool) -> void:
	var color := Color("#30343a")
	match status:
		"available":
			color = Color("#165b4f")
		"current":
			color = Color("#7a5c12")
		"completed":
			color = Color("#344c78")
		"locked":
			color = Color("#20242a")
	if selected:
		color = Color("#b56a32")
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = Color("#f4f1df")
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	button.add_theme_stylebox_override("normal", style)
	button.add_theme_color_override("font_color", Color("#f8f4e8"))


func _add_note(parent: Node, text: String) -> void:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(label)


func _clear(node: Node) -> void:
	for child in node.get_children():
		child.queue_free()


func _icon(id: String) -> Texture2D:
	if icon_cache.has(id):
		return icon_cache[id]
	var path := String(ICONS.get(id, ICONS.normal))
	var texture: Texture2D = _load_svg_texture(path)
	icon_cache[id] = texture
	return texture


func _load_svg_texture(path: String) -> Texture2D:
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.is_empty():
		return null
	var image := Image.new()
	var error := image.load_svg_from_buffer(bytes, 1.0)
	if error != OK:
		return null
	return ImageTexture.create_from_image(image)


func _play_sfx(sfx_id: String) -> void:
	var path := String(SFX.get(sfx_id, ""))
	if path.is_empty():
		return
	var stream: AudioStream = load(path)
	if stream == null:
		return
	audio_player.stream = stream
	audio_player.play()


func _emit_sfx(sfx_id: String) -> void:
	emit_signal("sfx_requested", sfx_id)


func _emit_feedback(kind: String, payload: Dictionary) -> void:
	emit_signal("feedback_requested", kind, payload)


func _string_array(values: Array) -> Array[String]:
	var result: Array[String] = []
	for value in values:
		result.append(String(value))
	return result


func _first_empty_potion_slot(state: Dictionary) -> int:
	for i in range(state.get("potions", []).size()):
		if state.potions[i] == null:
			return i
	return -1


func _option_needs_card(option: Dictionary) -> bool:
	for effect in option.get("effects", []):
		if String(effect.get("op", "")) in ["upgrade_card", "remove_card"]:
			return true
	return false


func _node_name(node_type: String) -> String:
	match node_type:
		"normal":
			return "Normal Combat"
		"elite":
			return "Elite"
		"boss":
			return "Boss"
		"shop":
			return "Shop"
		"event":
			return "Event"
		"rest":
			return "Rest"
		"treasure":
			return "Treasure"
		_:
			return node_type.capitalize()


func _short_node_label(node_type: String) -> String:
	match node_type:
		"normal":
			return "Combat"
		"treasure":
			return "Chest"
		_:
			return _node_name(node_type)


func _card_button_text(card_id: String) -> String:
	var card: Dictionary = database.get("cards", {}).get(card_id, {})
	return "%s\nCost %d | %s\n%s" % [
		card.get("name", card_id),
		int(card.get("cost", 0)),
		String(card.get("rarity", "")),
		_describe_effects(card.get("effects", []))
	]


func _describe_effects(effects: Array) -> String:
	var parts: Array[String] = []
	for effect in effects:
		match String(effect.get("op", "")):
			"damage":
				parts.append("Damage %d" % int(effect.get("value", 0)))
			"gain_block":
				parts.append("Block %d" % int(effect.get("value", 0)))
			"draw":
				parts.append("Draw %d" % int(effect.get("count", 1)))
			"heal":
				parts.append("Heal %d" % int(effect.get("value", 0)))
			_:
				parts.append(String(effect.get("op", "")))
	return ", ".join(parts)


func _content_name(kind: String, content_id: String) -> String:
	match kind:
		"card":
			return _card_name(content_id)
		"relic":
			return _relic_name(content_id)
		"potion":
			return _potion_name(content_id)
		_:
			return content_id


func _character_name(character_id: String) -> String:
	return String(database.get("characters", {}).get(character_id, {}).get("display_name", character_id))


func _card_name(card_id: String) -> String:
	return String(database.get("cards", {}).get(card_id, {}).get("name", card_id))


func _relic_name(relic_id: String) -> String:
	return String(database.get("relics", {}).get(relic_id, {}).get("name", relic_id))


func _potion_name(potion_id: String) -> String:
	return String(database.get("potions", {}).get(potion_id, {}).get("name", potion_id))
