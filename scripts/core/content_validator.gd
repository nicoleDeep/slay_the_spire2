extends RefCounted
class_name ContentValidator

const ALLOWED_OPS := [
	"damage", "damage_all", "gain_block", "draw", "discard", "exhaust",
	"gain_energy", "apply_status", "remove_status", "add_card_to_draw",
	"add_card_to_discard", "add_card_to_hand", "heal", "lose_hp",
	"gain_gold", "lose_gold", "upgrade_card", "remove_card", "gain_relic",
	"gain_potion", "modify_cost", "create_choice"
]
const ALLOWED_TARGETS := ["self", "player", "selected_enemy", "all_enemies", "random_enemy", "none"]
const ALLOWED_CARD_TYPES := ["attack", "skill", "power", "status", "curse", "special"]
const ALLOWED_RARITIES := ["starter", "common", "uncommon", "rare", "special", "boss"]
const ALLOWED_INTENTS := ["attack", "defend", "attack_defend", "debuff", "buff", "unknown"]
const ALLOWED_DIFFICULTIES := ["D0", "D1", "D2", "D3"]
const ALLOWED_NODE_TYPES := ["normal", "elite", "boss", "shop", "event", "rest", "treasure"]
const ALLOWED_MODIFIERS := ["more_safe_routes", "remove_cost_up", "more_elite_routes", "act1_harder_move_weights"]
const ALLOWED_HOOKS := [
	"run_start", "combat_created", "combat_start", "turn_start", "turn_end",
	"before_card_played", "after_card_played", "card_drawn", "card_exhausted",
	"enemy_killed", "player_damaged", "hp_lost", "gold_gained",
	"before_potion_used", "after_potion_used", "combat_victory",
	"reward_generated", "shop_entered", "rest_site_entered",
	"node_completed", "act_completed"
]
const DEPRECATED_HOOKS := ["card_played", "potion_used"]
const ALLOWED_CONDITIONS := ["always", "has_status", "hp_at_least", "gold_at_least", "card_in_hand", "deck_has_tag", "enemy_count_at_least"]
const ALLOWED_STATUSES := ["strength", "dexterity", "vulnerable", "weak", "frail", "poison", "regeneration", "ritual", "artifact"]

static func validate_all(database: Dictionary) -> Dictionary:
	var errors: Array[String] = []
	var warnings: Array[String] = []
	var cards: Dictionary = database.get("cards", {})
	var characters: Dictionary = database.get("characters", {})
	var enemies: Dictionary = database.get("enemies", {})
	var difficulties: Dictionary = database.get("difficulties", {})
	var acts: Dictionary = database.get("acts", {})
	var relics: Dictionary = database.get("relics", {})
	var potions: Dictionary = database.get("potions", {})
	var events: Dictionary = database.get("events", {})
	var reward_pools: Dictionary = database.get("reward_pools", {})
	var shop_pools: Dictionary = database.get("shop_pools", {})
	var rest_sites: Dictionary = database.get("rest_sites", {})

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
	for id in acts.keys():
		_validate_act(id, acts[id], enemies, reward_pools, shop_pools, rest_sites, errors)
	for id in relics.keys():
		_validate_relic(id, relics[id], errors)
	for id in potions.keys():
		_validate_potion(id, potions[id], errors)
	for id in events.keys():
		_validate_event(id, events[id], errors)
	for id in reward_pools.keys():
		_validate_reward_pool(id, reward_pools[id], cards, relics, potions, events, errors)
	for id in shop_pools.keys():
		_validate_shop_pool(id, shop_pools[id], cards, relics, potions, errors)
	for id in rest_sites.keys():
		_validate_rest_site(id, rest_sites[id], errors)
	if cards.size() < 5:
		errors.append("M1 requires at least 5 cards; found %d" % cards.size())
	if characters.size() < 1:
		errors.append("M1 requires at least 1 character")
	if enemies.size() < 1:
		errors.append("M1 requires at least 1 enemy")
	if not acts.has("act1_emberwood_m2"):
		errors.append("Missing required M2 Act: act1_emberwood_m2")
	for required_relic in [
		"charcoal_compass", "relic_pathfinder_lens", "relic_bankers_ember",
		"relic_quiet_bellows", "relic_split_flint", "relic_cooling_rivet",
		"relic_ashwood_token", "relic_hollow_canteen", "relic_trailward_knot",
		"relic_brass_seed"
	]:
		if not relics.has(required_relic):
			errors.append("Missing required M2 relic: %s" % required_relic)
	for required_potion in ["potion_coal_skin", "potion_flash_draw", "potion_kindled_focus", "potion_cinder_burst", "potion_clear_breath"]:
		if not potions.has(required_potion):
			errors.append("Missing required M2 potion: %s" % required_potion)
	for required_event in ["event_echo_toll", "event_soot_archive", "event_broken_waystone", "event_warm_rain", "event_lantern_exchange"]:
		if not events.has(required_event):
			errors.append("Missing required M2 event: %s" % required_event)
	for required_pool in [
		"pool_reward_ember_ranger_m2", "pool_relic_common_m2", "pool_relic_elite_m2",
		"pool_relic_boss_m2", "pool_potion_m2", "pool_event_act1_m2",
		"pool_shop_act1_m2", "pool_treasure_act1_m2"
	]:
		if not reward_pools.has(required_pool) and not shop_pools.has(required_pool):
			errors.append("Missing required M2 pool: %s" % required_pool)
	if _contains_deprecated_id(database.get("raw", {})):
		errors.append("ERR_DEPRECATED_CONTENT_ID: role_forge_wayfarer/fw_* is not allowed")
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
	for key in [
		"enemy_hp_multiplier", "enemy_damage_multiplier", "elite_hp_multiplier",
		"boss_hp_multiplier", "shop_price_multiplier", "remove_cost_multiplier",
		"rest_heal_multiplier", "potion_drop_multiplier"
	]:
		var value := float(adjustments.get(key, 1.0))
		if value <= 0.0 or value > 3.0:
			errors.append("Difficulty %s %s out of range: %s" % [id, key, value])
	for modifier in difficulty.get("modifiers", []):
		var modifier_id := String(modifier.get("id", ""))
		if not ALLOWED_MODIFIERS.has(modifier_id):
			errors.append("Difficulty %s references unknown modifier %s" % [id, modifier_id])


static func _validate_act(id: String, act: Dictionary, enemies: Dictionary, reward_pools: Dictionary, shop_pools: Dictionary, rest_sites: Dictionary, errors: Array[String]) -> void:
	if int(act.get("floor_count", 0)) != 12 or int(act.get("boss_floor", 0)) != 12:
		errors.append("Act %s must use the frozen 12-floor M2 profile" % id)
	if int(act.get("start_node_count", 0)) < 1:
		errors.append("Act %s has no start nodes" % id)
	var weights: Dictionary = act.get("node_weights", {})
	for node_type in ALLOWED_NODE_TYPES:
		if node_type == "boss":
			continue
		if int(weights.get(node_type, -1)) < 0:
			errors.append("Act %s has invalid weight for %s" % [id, node_type])
	var pools: Dictionary = act.get("pools", {})
	for pool_name in ["normal_encounters", "elite_encounters", "bosses"]:
		var pool: Array = pools.get(pool_name, [])
		if pool.is_empty():
			errors.append("Act %s pool %s is empty" % [id, pool_name])
		for enemy_id in pool:
			if not enemies.has(String(enemy_id)):
				errors.append("Act %s pool %s references missing enemy %s" % [id, pool_name, enemy_id])
	for pool_name in ["events", "treasures"]:
		var pool_id := String(pools.get(pool_name, ""))
		if not reward_pools.has(pool_id):
			errors.append("Act %s references missing pool %s" % [id, pool_id])
	var shop_pool_id := String(pools.get("shops", ""))
	if not shop_pools.has(shop_pool_id):
		errors.append("Act %s references missing shop pool %s" % [id, shop_pool_id])
	var rest_id := String(act.get("rest_definition_id", ""))
	if not rest_sites.has(rest_id):
		errors.append("Act %s references missing rest site %s" % [id, rest_id])


static func _validate_relic(id: String, relic: Dictionary, errors: Array[String]) -> void:
	_require_string(relic, "name", "Relic %s" % id, errors)
	if not ALLOWED_RARITIES.has(relic.get("rarity", "")):
		errors.append("Relic %s has invalid rarity %s" % [id, relic.get("rarity", "")])
	if not relic.has("triggers") or not relic.triggers is Array:
		errors.append("Relic %s missing triggers array" % id)
		return
	for trigger in relic.triggers:
		var hook := String(trigger.get("hook", ""))
		if DEPRECATED_HOOKS.has(hook):
			errors.append("ERR_DEPRECATED_HOOK_ID: Relic %s uses %s" % [id, hook])
		elif not ALLOWED_HOOKS.has(hook):
			errors.append("Relic %s uses unknown hook %s" % [id, hook])
		_validate_condition(trigger.get("condition", {"op": "always"}), "Relic %s hook %s" % [id, hook], errors)
		_validate_effects(trigger.get("effects", []), "Relic %s hook %s" % [id, hook], errors, true)
		var scope := String(trigger.get("limit", {}).get("scope", "per_run"))
		if not ["per_turn", "per_combat", "per_node", "per_run"].has(scope):
			errors.append("Relic %s has invalid limit scope %s" % [id, scope])


static func _validate_potion(id: String, potion: Dictionary, errors: Array[String]) -> void:
	_require_string(potion, "name", "Potion %s" % id, errors)
	if String(potion.get("use_context", "")) != "combat":
		errors.append("Potion %s has invalid M2 use_context %s" % [id, potion.get("use_context", "")])
	if not ALLOWED_TARGETS.has(potion.get("target", "")):
		errors.append("Potion %s has invalid target %s" % [id, potion.get("target", "")])
	_validate_effects(potion.get("effects", []), "Potion %s" % id, errors)


static func _validate_event(id: String, event: Dictionary, errors: Array[String]) -> void:
	_require_string(event, "title", "Event %s" % id, errors)
	if not event.has("options") or not event.options is Array or event.options.is_empty():
		errors.append("Event %s must have options" % id)
		return
	var has_safe_exit := false
	for option in event.options:
		if bool(option.get("safe_exit", false)) and String(option.get("condition", {}).get("op", "always")) == "always":
			has_safe_exit = true
		_validate_condition(option.get("condition", {"op": "always"}), "Event %s option %s" % [id, option.get("id", "")], errors)
		_validate_effects(option.get("costs", []), "Event %s option %s costs" % [id, option.get("id", "")], errors, true)
		_validate_effects(option.get("effects", []), "Event %s option %s effects" % [id, option.get("id", "")], errors, true)
	if not has_safe_exit:
		errors.append("Event %s must have an always-legal safe_exit option" % id)


static func _validate_reward_pool(id: String, pool: Dictionary, cards: Dictionary, relics: Dictionary, potions: Dictionary, events: Dictionary, errors: Array[String]) -> void:
	for card_id in pool.get("cards", []):
		if not cards.has(String(card_id)):
			errors.append("Reward pool %s references missing card %s" % [id, card_id])
	for relic_id in pool.get("relics", []):
		if not relics.has(String(relic_id)):
			errors.append("Reward pool %s references missing relic %s" % [id, relic_id])
	for potion_id in pool.get("potions", []):
		if not potions.has(String(potion_id)):
			errors.append("Reward pool %s references missing potion %s" % [id, potion_id])
	for event_id in pool.get("events", []):
		if not events.has(String(event_id)):
			errors.append("Reward pool %s references missing event %s" % [id, event_id])
	var relic_pool_id := String(pool.get("relic_pool_id", ""))
	if not relic_pool_id.is_empty() and not pool.has("relics"):
		pass
	if id == "pool_reward_ember_ranger_m2" and pool.get("cards", []).is_empty():
		errors.append("pool_reward_ember_ranger_m2 must not be empty")


static func _validate_shop_pool(id: String, pool: Dictionary, cards: Dictionary, relics: Dictionary, potions: Dictionary, errors: Array[String]) -> void:
	for card_id in pool.get("cards", []):
		if not cards.has(String(card_id)):
			errors.append("Shop pool %s references missing card %s" % [id, card_id])
	for relic_id in pool.get("relics", []):
		if not relics.has(String(relic_id)):
			errors.append("Shop pool %s references missing relic %s" % [id, relic_id])
	for potion_id in pool.get("potions", []):
		if not potions.has(String(potion_id)):
			errors.append("Shop pool %s references missing potion %s" % [id, potion_id])


static func _validate_rest_site(id: String, rest: Dictionary, errors: Array[String]) -> void:
	if not rest.has("heal") or not rest.has("upgrade"):
		errors.append("Rest site %s must define heal and upgrade actions" % id)


static func _validate_effects(effects: Array, scope: String, errors: Array[String], allow_empty: bool = false) -> void:
	if effects.is_empty() and not allow_empty:
		errors.append("%s has no effects" % scope)
	for effect in effects:
		if not effect is Dictionary:
			errors.append("%s has invalid effect entry" % scope)
			continue
		var op := String(effect.get("op", ""))
		if not ALLOWED_OPS.has(op):
			errors.append("%s uses unsupported op %s" % [scope, op])
		if effect.has("target") and not ALLOWED_TARGETS.has(effect.target):
			errors.append("%s effect %s has invalid target %s" % [scope, op, effect.target])
		if op in ["damage", "damage_all", "gain_block", "heal", "lose_hp", "gain_gold", "lose_gold"]:
			_require_int_min(effect, "value", 0, "%s effect %s" % [scope, op], errors)
		if op == "draw":
			_require_int_min(effect, "count", 1, "%s effect draw" % scope, errors)
		if op == "apply_status":
			if not ALLOWED_STATUSES.has(String(effect.get("status", ""))):
				errors.append("%s effect apply_status has invalid status %s" % [scope, effect.get("status", "")])
			_require_int_min(effect, "value", 1, "%s effect apply_status" % scope, errors)
		if op == "remove_status" and not ALLOWED_STATUSES.has(String(effect.get("status", ""))):
			errors.append("%s effect remove_status has invalid status %s" % [scope, effect.get("status", "")])
		if op in ["upgrade_card", "remove_card"] and String(effect.get("selection", "")) == "":
			errors.append("%s effect %s missing selection" % [scope, op])
		if effect.has("count"):
			_require_int_min(effect, "count", 1, "%s effect %s" % [scope, op], errors)


static func _validate_condition(condition: Dictionary, scope: String, errors: Array[String]) -> void:
	var op := String(condition.get("op", "always"))
	if not ALLOWED_CONDITIONS.has(op):
		errors.append("%s has unsupported condition %s" % [scope, op])


static func _require_string(data: Dictionary, key: String, scope: String, errors: Array[String]) -> void:
	if not data.has(key) or String(data[key]).is_empty():
		errors.append("%s missing string field %s" % [scope, key])


static func _require_int_min(data: Dictionary, key: String, minimum: int, scope: String, errors: Array[String]) -> void:
	if not data.has(key) or int(data[key]) < minimum:
		errors.append("%s field %s must be >= %d" % [scope, key, minimum])


static func _contains_deprecated_id(value: Variant) -> bool:
	if value is String:
		return value == "role_forge_wayfarer" or value.begins_with("fw_")
	if value is Array:
		for item in value:
			if _contains_deprecated_id(item):
				return true
	if value is Dictionary:
		for key in value.keys():
			if _contains_deprecated_id(key) or _contains_deprecated_id(value[key]):
				return true
	return false
