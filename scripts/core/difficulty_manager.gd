extends RefCounted
class_name DifficultyManager

const DataLoader = preload("res://scripts/core/data_loader.gd")

var profiles: Dictionary = {}

func _init(content_database: Dictionary = {}) -> void:
	if content_database.has("difficulties"):
		profiles = content_database.difficulties
	else:
		profiles = DataLoader.load_content_database().difficulties


func get_profile(id: String) -> Dictionary:
	return profiles.get(id, profiles.get("D1", {})).duplicate(true)


func has_profile(id: String) -> bool:
	return profiles.has(id)


func create_snapshot(id: String) -> Dictionary:
	if not profiles.has(id):
		return {}
	var profile: Dictionary = profiles[id]
	return {
		"profile_id": id,
		"profile_version": int(profile.get("profile_version", 1)),
		"base_adjustments": profile.get("base_adjustments", {}).duplicate(true),
		"modifiers": profile.get("modifiers", []).duplicate(true)
	}


func get_adjustment(profile: Dictionary, key: String, fallback: Variant) -> Variant:
	return profile.get("base_adjustments", {}).get(key, fallback)


func apply_character_adjustments(character_data: Dictionary, profile: Dictionary) -> Dictionary:
	var adjusted := character_data.duplicate(true)
	adjusted.max_hp = int(adjusted.get("max_hp", 1)) + int(get_adjustment(profile, "starting_max_hp_delta", 0))
	adjusted.starting_gold = int(adjusted.get("starting_gold", 0)) + int(get_adjustment(profile, "starting_gold_delta", 0))
	return adjusted


func apply_enemy_hp(enemy_data: Dictionary, profile: Dictionary) -> int:
	var hp_min := int(enemy_data.get("hp_min", 1))
	var hp_max := int(enemy_data.get("hp_max", hp_min))
	var base_hp := int(round((hp_min + hp_max) / 2.0))
	var multiplier := float(get_adjustment(profile, "enemy_hp_multiplier", 1.0))
	if enemy_data.get("tags", []).has("elite"):
		multiplier *= float(get_adjustment(profile, "elite_hp_multiplier", 1.0))
	if enemy_data.get("tags", []).has("boss"):
		multiplier *= float(get_adjustment(profile, "boss_hp_multiplier", 1.0))
	return max(1, int(round(base_hp * multiplier)))


func apply_enemy_damage(base_damage: int, profile: Dictionary) -> int:
	var multiplier := float(get_adjustment(profile, "enemy_damage_multiplier", 1.0))
	return max(0, int(round(float(base_damage) * multiplier)))


func apply_enemy_move_weight(enemy_id: String, move_id: String, base_weight: int, profile: Dictionary) -> int:
	var result := base_weight
	for modifier in profile.get("modifiers", []):
		if String(modifier.get("id", "")) != "act1_harder_move_weights":
			continue
		for change in modifier.get("params", {}).get("changes", []):
			if String(change.get("enemy_id", "")) != enemy_id:
				continue
			result += int(change.get("move_weight_delta", {}).get(move_id, 0))
	return max(0, result)
