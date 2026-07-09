extends RefCounted
class_name ContentValidator

const ALLOWED_OPS := ["damage", "gain_block", "draw"]
const ALLOWED_TARGETS := ["self", "player", "selected_enemy", "all_enemies", "random_enemy", "none"]
const ALLOWED_CARD_TYPES := ["attack", "skill", "power", "status", "curse", "special"]
const ALLOWED_RARITIES := ["starter", "common", "uncommon", "rare", "special"]
const ALLOWED_INTENTS := ["attack", "defend", "attack_defend", "unknown"]
const ALLOWED_DIFFICULTIES := ["D0", "D1"]

static func validate_all(database: Dictionary) -> Dictionary:
	var errors: Array[String] = []
	var warnings: Array[String] = []
	var cards: Dictionary = database.get("cards", {})
	var characters: Dictionary = database.get("characters", {})
	var enemies: Dictionary = database.get("enemies", {})
	var difficulties: Dictionary = database.get("difficulties", {})

	for id in characters.keys():
		_validate_character(id, characters[id], cards, errors)
	for id in cards.keys():
		_validate_card(id, cards[id], errors)
	for id in enemies.keys():
		_validate_enemy(id, enemies[id], errors)
	for id in ALLOWED_DIFFICULTIES:
		if not difficulties.has(id):
			errors.append("Missing required difficulty profile: %s" % id)
	for id in difficulties.keys():
		_validate_difficulty(id, difficulties[id], errors)
	if cards.size() < 5:
		errors.append("M1 requires at least 5 cards; found %d" % cards.size())
	if characters.size() < 1:
		errors.append("M1 requires at least 1 character")
	if enemies.size() < 1:
		errors.append("M1 requires at least 1 enemy")
	return {
		"ok": errors.is_empty(),
		"errors": errors,
		"warnings": warnings
	}


static func _validate_character(id: String, character: Dictionary, cards: Dictionary, errors: Array[String]) -> void:
	_require_string(character, "display_name", "Character %s" % id, errors)
	_require_int_min(character, "max_hp", 1, "Character %s" % id, errors)
	_require_int_min(character, "starting_gold", 0, "Character %s" % id, errors)
	if not character.has("starting_deck") or not character.starting_deck is Array:
		errors.append("Character %s missing starting_deck array" % id)
		return
	for entry in character.starting_deck:
		if not entry is Dictionary:
			errors.append("Character %s has invalid starting_deck entry" % id)
			continue
		var card_id := String(entry.get("card_id", ""))
		if not cards.has(card_id):
			errors.append("Character %s references missing card %s" % [id, card_id])
		_require_int_min(entry, "count", 1, "Character %s starting_deck %s" % [id, card_id], errors)


static func _validate_card(id: String, card: Dictionary, errors: Array[String]) -> void:
	_require_string(card, "name", "Card %s" % id, errors)
	if not ALLOWED_CARD_TYPES.has(card.get("type", "")):
		errors.append("Card %s has invalid type %s" % [id, card.get("type", "")])
	if not ALLOWED_RARITIES.has(card.get("rarity", "")):
		errors.append("Card %s has invalid rarity %s" % [id, card.get("rarity", "")])
	_require_int_min(card, "cost", 0, "Card %s" % id, errors)
	if not ALLOWED_TARGETS.has(card.get("target", "")):
		errors.append("Card %s has invalid target %s" % [id, card.get("target", "")])
	_validate_effects(card.get("effects", []), "Card %s" % id, errors)


static func _validate_enemy(id: String, enemy: Dictionary, errors: Array[String]) -> void:
	_require_string(enemy, "name", "Enemy %s" % id, errors)
	_require_int_min(enemy, "hp_min", 1, "Enemy %s" % id, errors)
	_require_int_min(enemy, "hp_max", 1, "Enemy %s" % id, errors)
	if int(enemy.get("hp_max", 0)) < int(enemy.get("hp_min", 0)):
		errors.append("Enemy %s hp_max is lower than hp_min" % id)
	if not enemy.has("moves") or not enemy.moves is Array or enemy.moves.is_empty():
		errors.append("Enemy %s must have at least one move" % id)
		return
	var has_weighted_move := false
	for move in enemy.moves:
		if not move is Dictionary:
			errors.append("Enemy %s has invalid move" % id)
			continue
		if int(move.get("weight", 0)) > 0:
			has_weighted_move = true
		if not ALLOWED_INTENTS.has(move.get("intent", "")):
			errors.append("Enemy %s move %s has invalid intent" % [id, move.get("id", "")])
		_validate_effects(move.get("effects", []), "Enemy %s move %s" % [id, move.get("id", "")], errors)
	if not has_weighted_move:
		errors.append("Enemy %s must have at least one move with weight > 0" % id)


static func _validate_difficulty(id: String, difficulty: Dictionary, errors: Array[String]) -> void:
	if not difficulty.has("base_adjustments") or not difficulty.base_adjustments is Dictionary:
		errors.append("Difficulty %s missing base_adjustments" % id)
		return
	var adjustments: Dictionary = difficulty.base_adjustments
	for key in ["enemy_hp_multiplier", "enemy_damage_multiplier", "elite_hp_multiplier", "boss_hp_multiplier"]:
		var value := float(adjustments.get(key, 1.0))
		if value <= 0.0 or value > 3.0:
			errors.append("Difficulty %s %s out of range: %s" % [id, key, value])


static func _validate_effects(effects: Array, scope: String, errors: Array[String]) -> void:
	if effects.is_empty():
		errors.append("%s has no effects" % scope)
	for effect in effects:
		if not effect is Dictionary:
			errors.append("%s has invalid effect entry" % scope)
			continue
		var op := String(effect.get("op", ""))
		if not ALLOWED_OPS.has(op):
			errors.append("%s uses unsupported M1 op %s" % [scope, op])
		if effect.has("target") and not ALLOWED_TARGETS.has(effect.target):
			errors.append("%s effect %s has invalid target %s" % [scope, op, effect.target])
		if op in ["damage", "gain_block"]:
			_require_int_min(effect, "value", 0, "%s effect %s" % [scope, op], errors)
		if op == "draw":
			_require_int_min(effect, "count", 1, "%s effect draw" % scope, errors)
		if effect.has("count"):
			_require_int_min(effect, "count", 1, "%s effect %s" % [scope, op], errors)


static func _require_string(data: Dictionary, key: String, scope: String, errors: Array[String]) -> void:
	if not data.has(key) or String(data[key]).is_empty():
		errors.append("%s missing string field %s" % [scope, key])


static func _require_int_min(data: Dictionary, key: String, minimum: int, scope: String, errors: Array[String]) -> void:
	if not data.has(key) or int(data[key]) < minimum:
		errors.append("%s field %s must be >= %d" % [scope, key, minimum])
