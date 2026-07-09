extends Control

const ContentValidator = preload("res://scripts/core/content_validator.gd")
const DataLoader = preload("res://scripts/core/data_loader.gd")
const RunManager = preload("res://scripts/run/run_manager.gd")

var run_manager: RunManager

func _ready() -> void:
	var root := MarginContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("margin_left", 40)
	root.add_theme_constant_override("margin_top", 40)
	root.add_theme_constant_override("margin_right", 40)
	root.add_theme_constant_override("margin_bottom", 40)
	add_child(root)

	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 16)
	root.add_child(layout)

	var title := Label.new()
	title.text = "M2 Run Setup"
	title.add_theme_font_size_override("font_size", 32)
	layout.add_child(title)

	var database := DataLoader.load_content_database()
	var validation := ContentValidator.validate_all(database)
	var status := Label.new()
	status.text = "Content validation: OK" if validation.ok else "Content validation failed: %s" % str(validation.errors)
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	layout.add_child(status)

	var character_label := Label.new()
	character_label.text = "Character"
	layout.add_child(character_label)
	var character_select := OptionButton.new()
	for character_id in database.characters.keys():
		var index := character_select.item_count
		character_select.add_item(String(database.characters[character_id].display_name))
		character_select.set_item_metadata(index, character_id)
	layout.add_child(character_select)

	var difficulty_label := Label.new()
	difficulty_label.text = "Difficulty"
	layout.add_child(difficulty_label)
	var difficulty_select := OptionButton.new()
	var difficulty_ids: Array = database.difficulties.keys()
	difficulty_ids.sort()
	for difficulty_id in difficulty_ids:
		var index := difficulty_select.item_count
		difficulty_select.add_item("%s — %s" % [difficulty_id, database.difficulties[difficulty_id].name])
		difficulty_select.set_item_metadata(index, difficulty_id)
	difficulty_select.select(1)
	layout.add_child(difficulty_select)

	var seed_input := LineEdit.new()
	seed_input.placeholder_text = "Run seed"
	seed_input.text = "424242"
	layout.add_child(seed_input)

	var result_label := Label.new()
	result_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	layout.add_child(result_label)

	var create_button := Button.new()
	create_button.text = "Create Run"
	create_button.pressed.connect(func() -> void:
		var character_id := String(character_select.get_item_metadata(character_select.selected))
		var difficulty_id := String(difficulty_select.get_item_metadata(difficulty_select.selected))
		run_manager = RunManager.new(database)
		var result := run_manager.create_run(character_id, difficulty_id, int(seed_input.text))
		if result.ok:
			result_label.text = "Run created: %s / %s / seed %s — 12-floor map saved." % [character_id, difficulty_id, seed_input.text]
		else:
			result_label.text = "%s: %s" % [result.code, result.get("message", "Run creation failed")]
	)
	layout.add_child(create_button)

	var combat_button := Button.new()
	combat_button.text = "Open M1 Test Combat"
	combat_button.pressed.connect(func() -> void:
		get_tree().change_scene_to_file("res://scenes/combat/combat.tscn")
	)
	layout.add_child(combat_button)
