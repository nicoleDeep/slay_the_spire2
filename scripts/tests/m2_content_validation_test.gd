extends SceneTree

const ContentValidator = preload("res://scripts/core/content_validator.gd")
const DataLoader = preload("res://scripts/core/data_loader.gd")


func _init() -> void:
	var database := DataLoader.load_content_database()
	var result := ContentValidator.validate_all(database)
	if not result.ok:
		push_error("M2 content validation failed: %s" % str(result.errors))
		quit(1)
		return
	print("M2 content validation passed")
	quit(0)
