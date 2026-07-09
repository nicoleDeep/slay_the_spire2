extends RefCounted
class_name DataLoader

static func load_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		push_error("JSON file not found: %s" % path)
		return null
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("Could not open JSON file: %s" % path)
		return null
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed == null:
		push_error("Could not parse JSON file: %s" % path)
	return parsed


static func load_json_array(path: String) -> Array:
	var data: Variant = load_json(path)
	if data is Array:
		return data
	if data is Dictionary and data.has("items") and data["items"] is Array:
		return data["items"]
	push_error("Expected JSON array in %s" % path)
	return []


static func load_json_object(path: String) -> Dictionary:
	var data: Variant = load_json(path)
	if data is Dictionary:
		return data
	push_error("Expected JSON object in %s" % path)
	return {}


static func index_by_id(items: Array) -> Dictionary:
	var indexed := {}
	for item in items:
		if item is Dictionary and item.has("id"):
			indexed[item.id] = item
	return indexed


static func load_content_database() -> Dictionary:
	var characters := load_json_array("res://data/characters/ember_ranger.json")
	var cards := load_json_array("res://data/cards/ember_ranger_cards.json")
	var enemies := load_json_array("res://data/enemies/m1_enemies.json")
	var difficulties := load_json_array("res://data/difficulties/difficulties.json")
	return {
		"characters": index_by_id(characters),
		"cards": index_by_id(cards),
		"enemies": index_by_id(enemies),
		"difficulties": index_by_id(difficulties),
		"raw": {
			"characters": characters,
			"cards": cards,
			"enemies": enemies,
			"difficulties": difficulties
		}
	}
