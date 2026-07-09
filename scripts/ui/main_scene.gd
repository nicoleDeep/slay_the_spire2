extends Control

const ContentValidator = preload("res://scripts/core/content_validator.gd")
const DataLoader = preload("res://scripts/core/data_loader.gd")

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
	title.text = "M1 Combat Slice"
	title.add_theme_font_size_override("font_size", 32)
	layout.add_child(title)

	var validation := ContentValidator.validate_all(DataLoader.load_content_database())
	var status := Label.new()
	status.text = "Content validation: OK" if validation.ok else "Content validation failed: %s" % str(validation.errors)
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	layout.add_child(status)

	var start_button := Button.new()
	start_button.text = "Start D1 Test Combat"
	start_button.pressed.connect(func() -> void:
		get_tree().change_scene_to_file("res://scenes/combat/combat.tscn")
	)
	layout.add_child(start_button)
