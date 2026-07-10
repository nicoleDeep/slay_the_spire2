extends RefCounted
class_name CombatManager

const DataLoader = preload("res://scripts/core/data_loader.gd")
const DifficultyManager = preload("res://scripts/core/difficulty_manager.gd")
const PotionManager = preload("res://scripts/potions/potion_manager.gd")
const RelicManager = preload("res://scripts/relics/relic_manager.gd")
const RngStream = preload("res://scripts/core/rng_stream.gd")

const HAND_LIMIT := 10

var database: Dictionary
var difficulty_manager: DifficultyManager
var potion_manager: PotionManager
var relic_manager: RelicManager
var rng: RngStream
var state: Dictionary = {}
var combat_log: Array[String] = []

func _init(content_database: Dictionary = {}) -> void:
	database = content_database if not content_database.is_empty() else DataLoader.load_content_database()
	difficulty_manager = DifficultyManager.new(database)
	potion_manager = PotionManager.new(database)
	relic_manager = RelicManager.new(database)


func start_combat(character_id: String, difficulty_id: String, enemy_ids: Array[String], seed: int = 1001) -> Dictionary:
	rng = RngStream.new(seed)
	combat_log.clear()
	var profile := difficulty_manager.get_profile(difficulty_id)
	var character := difficulty_manager.apply_character_adjustments(database.characters[character_id], profile)
	var deck := _build_starting_deck(character)
	state = {
		"phase": "starting",
		"difficulty": profile,
		"character_id": character_id,
		"player": {
			"max_hp": int(character.max_hp),
			"hp": int(character.max_hp),
			"block": 0,
			"energy": 0,
			"max_energy": int(character.get("base_energy", 3)),
			"gold": int(character.starting_gold)
		},
		"draw_pile": deck,
		"discard_pile": [],
		"exhaust_pile": [],
		"hand": [],
		"enemies": _create_enemies(enemy_ids, profile),
		"turn_index": 0,
		"result": ""
	}
	_choose_all_enemy_intents()
	rng.shuffle_array(state.draw_pile)
	_start_player_turn()
	_log("Combat started: %s on %s seed %d" % [character_id, difficulty_id, seed])
	return get_public_state()


func start_run_combat(run_state: Dictionary, enemy_ids: Array[String], combat_rng: RngStream) -> Dictionary:
	rng = combat_rng
	combat_log.clear()
	state = {
		"phase": "starting",
		"difficulty": run_state.get("difficulty_snapshot", {}),
		"character_id": String(run_state.get("character_id", "")),
		"player": {
			"max_hp": int(run_state.get("max_hp", 1)),
			"hp": int(run_state.get("hp", 1)),
			"block": 0,
			"energy": 0,
			"max_energy": int(database.get("characters", {}).get(String(run_state.get("character_id", "")), {}).get("base_energy", 3)),
			"gold": int(run_state.get("gold", 0))
		},
		"draw_pile": _build_run_deck(run_state),
		"discard_pile": [],
		"exhaust_pile": [],
		"hand": [],
		"enemies": _create_enemies(enemy_ids, run_state.get("difficulty_snapshot", {})),
		"turn_index": 0,
		"result": ""
	}
	var created := _trigger_relic_hook(run_state, "combat_created")
	if not created.ok:
		state.phase = "config_error"
		return get_public_state()
	var started := _trigger_relic_hook(run_state, "combat_start")
	if not started.ok:
		state.phase = "config_error"
		return get_public_state()
	_choose_all_enemy_intents()
	rng.shuffle_array(state.draw_pile)
	_start_player_turn()
	_log("Run combat started: %s enemies %s" % [run_state.get("character_id", ""), str(enemy_ids)])
	return get_public_state()


func use_potion(run_state: Dictionary, slot: int, target_index: int = 0) -> Dictionary:
	if state.get("phase", "") != "player_turn":
		return _error("ERR_COMBAT_PHASE", "Potions can only be used during player turn")
	var context := {
		"use_context": "combat",
		"target_index": target_index,
		"valid_enemy_targets": _living_enemy_indices()
	}
	var used := potion_manager.use_potion(run_state, slot, context)
	if not used.ok:
		return used
	var before := _trigger_relic_hook(run_state, "before_potion_used")
	if not before.ok:
		return before
	for effect in used.get("effects", []):
		_resolve_effect(effect, "player", target_index)
		_check_combat_end()
	var after := _trigger_relic_hook(run_state, "after_potion_used")
	if not after.ok:
		return after
	_check_combat_end()
	return {"ok": true, "code": "OK", "combat_state": get_public_state(), "combat_result": build_result()}


func debug_force_victory() -> Dictionary:
	for index in range(state.get("enemies", []).size()):
		state.enemies[index].hp = 0
	_check_combat_end()
	return build_result()


func build_result() -> Dictionary:
	return {
		"ok": true,
		"code": "OK",
		"result": String(state.get("result", "")),
		"player": state.get("player", {}).duplicate(true),
		"combat_rng": rng.snapshot() if rng != null else {}
	}


func can_play_card(hand_index: int, target_index: int = 0) -> bool:
	if state.get("phase", "") != "player_turn":
		return false
	if hand_index < 0 or hand_index >= state.hand.size():
		return false
	var card := _card(state.hand[hand_index])
	if int(card.cost) > int(state.player.energy):
		return false
	if _requires_enemy_target(card) and not _is_valid_enemy_target(target_index):
		return false
	return true


func play_card(hand_index: int, target_index: int = 0) -> bool:
	if not can_play_card(hand_index, target_index):
		_log("Cannot play card at hand index %d" % hand_index)
		return false
	var card_id: String = state.hand[hand_index]
	var card := _card(card_id)
	state.player.energy = int(state.player.energy) - int(card.cost)
	state.hand.remove_at(hand_index)
	_log("Played %s" % card.name)
	for effect in card.effects:
		_resolve_effect(effect, "player", target_index)
		_check_combat_end()
	state.discard_pile.append(card_id)
	_check_combat_end()
	return true


func end_player_turn() -> void:
	if state.get("phase", "") != "player_turn":
		return
	state.phase = "enemy_turn"
	state.discard_pile.append_array(state.hand)
	state.hand.clear()
	_log("Player ended turn")
	_run_enemy_turn()


func draw_cards(count: int) -> void:
	for i in range(count):
		if state.draw_pile.is_empty():
			if state.discard_pile.is_empty():
				_log("No cards available to draw")
				return
			state.draw_pile = state.discard_pile.duplicate()
			state.discard_pile.clear()
			rng.shuffle_array(state.draw_pile)
			_log("Shuffled discard pile into draw pile")
		var card_id: String = state.draw_pile.pop_back()
		if state.hand.size() >= HAND_LIMIT:
			state.discard_pile.append(card_id)
			_log("Hand full; %s moved to discard" % _card(card_id).name)
		else:
			state.hand.append(card_id)


func get_public_state() -> Dictionary:
	var copy := state.duplicate(true)
	copy["combat_log"] = combat_log.duplicate()
	copy["rng"] = rng.snapshot() if rng != null else {}
	return copy


func get_card(card_id: String) -> Dictionary:
	return _card(card_id)


func _start_player_turn() -> void:
	if state.phase in ["victory", "defeat"]:
		return
	state.turn_index = int(state.turn_index) + 1
	state.phase = "player_turn"
	if int(state.turn_index) > 1:
		state.player.block = 0
	state.player.energy = int(state.player.max_energy)
	draw_cards(5)
	_log("Turn %d started: drew to %d cards" % [state.turn_index, state.hand.size()])
	_check_combat_end()


func _run_enemy_turn() -> void:
	for enemy in state.enemies:
		if state.phase in ["victory", "defeat"]:
			return
		if int(enemy.hp) <= 0:
			continue
		var move: Dictionary = enemy.get("intent_move", {})
		if move.is_empty():
			continue
		_log("%s used %s" % [enemy.name, move.id])
		for effect in move.effects:
			_resolve_effect(effect, "enemy", -1, enemy)
			_check_combat_end()
			if state.phase in ["victory", "defeat"]:
				return
	_choose_all_enemy_intents()
	_check_combat_end()
	if not (state.phase in ["victory", "defeat"]):
		_start_player_turn()


func _resolve_effect(effect: Dictionary, source: String, target_index: int = 0, source_enemy: Dictionary = {}) -> void:
	var op := String(effect.get("op", ""))
	match op:
		"damage":
			var count := int(effect.get("count", 1))
			for i in range(count):
				_resolve_damage(effect, source, target_index)
				_check_combat_end()
		"gain_block":
			_resolve_gain_block(effect, source, source_enemy)
		"draw":
			if source == "player":
				draw_cards(int(effect.get("count", 1)))
		"heal":
			if source == "player":
				state.player.hp = min(int(state.player.max_hp), int(state.player.hp) + int(effect.get("value", 0)))
				_log("Player healed %d, hp %d/%d" % [int(effect.get("value", 0)), state.player.hp, state.player.max_hp])
		"apply_status":
			_log("Status op not yet materialized in M2 combat slice: %s" % String(effect.get("status", "")))
		_:
			_log("Unsupported op skipped: %s" % op)


func _resolve_damage(effect: Dictionary, source: String, target_index: int) -> void:
	var damage := int(effect.get("value", 0))
	if source == "enemy":
		damage = difficulty_manager.apply_enemy_damage(damage, state.difficulty)
		var blocked: int = min(int(state.player.block), damage)
		state.player.block = int(state.player.block) - blocked
		var hp_loss := damage - blocked
		state.player.hp = max(0, int(state.player.hp) - hp_loss)
		_log("Player took %d damage (%d blocked), hp %d/%d" % [hp_loss, blocked, state.player.hp, state.player.max_hp])
		return
	if not _is_valid_enemy_target(target_index):
		_log("Damage skipped: no legal target")
		return
	var enemy: Dictionary = state.enemies[target_index]
	var blocked_enemy: int = min(int(enemy.block), damage)
	enemy.block = int(enemy.block) - blocked_enemy
	var enemy_hp_loss := damage - blocked_enemy
	enemy.hp = max(0, int(enemy.hp) - enemy_hp_loss)
	state.enemies[target_index] = enemy
	_log("%s took %d damage (%d blocked), hp %d/%d" % [enemy.name, enemy_hp_loss, blocked_enemy, enemy.hp, enemy.max_hp])


func _resolve_gain_block(effect: Dictionary, source: String, source_enemy: Dictionary = {}) -> void:
	var value := int(effect.get("value", 0))
	var target := String(effect.get("target", "player" if source == "player" else "self"))
	if source == "enemy" or target == "self":
		if source_enemy.is_empty():
			return
		for i in range(state.enemies.size()):
			if state.enemies[i].instance_id == source_enemy.instance_id:
				state.enemies[i].block = int(state.enemies[i].block) + value
				_log("%s gained %d block" % [state.enemies[i].name, value])
				return
	state.player.block = int(state.player.block) + value
	_log("Player gained %d block" % value)


func _check_combat_end() -> void:
	if int(state.player.hp) <= 0:
		state.phase = "defeat"
		state.result = "defeat"
		_log("Combat defeat")
		return
	var any_alive := false
	for enemy in state.enemies:
		if int(enemy.hp) > 0:
			any_alive = true
			break
	if not any_alive:
		state.phase = "victory"
		state.result = "victory"
		_log("Combat victory")


func _choose_all_enemy_intents() -> void:
	for i in range(state.enemies.size()):
		if int(state.enemies[i].hp) <= 0:
			continue
		_tick_move_cooldowns(i)
		var legal_moves := []
		for move in state.enemies[i].moves:
			var move_weight := difficulty_manager.apply_enemy_move_weight(
				String(state.enemies[i].id),
				String(move.get("id", "")),
				int(move.get("weight", 0)),
				state.difficulty
			)
			if move_weight > 0 and _move_phase_is_active(state.enemies[i], move) and _move_timing_is_legal(state.enemies[i], move):
				var weighted_move: Dictionary = move.duplicate(true)
				weighted_move.weight = move_weight
				legal_moves.append(weighted_move)
		if legal_moves.is_empty():
			for move in state.enemies[i].moves:
				var fallback_weight := difficulty_manager.apply_enemy_move_weight(
					String(state.enemies[i].id),
					String(move.get("id", "")),
					int(move.get("weight", 0)),
					state.difficulty
				)
				if fallback_weight > 0 and _move_phase_is_active(state.enemies[i], move):
					var fallback_move: Dictionary = move.duplicate(true)
					fallback_move.weight = fallback_weight
					legal_moves.append(fallback_move)
		var picked := rng.pick_weighted(legal_moves)
		state.enemies[i].intent_move = picked
		_mark_move_selected(i, picked)


func _create_enemies(enemy_ids: Array[String], profile: Dictionary) -> Array:
	var enemies := []
	var index := 0
	for enemy_id in enemy_ids:
		var enemy_data: Dictionary = database.enemies[enemy_id]
		var max_hp := difficulty_manager.apply_enemy_hp(enemy_data, profile)
		var instance := enemy_data.duplicate(true)
		instance.instance_id = "%s_%d" % [enemy_id, index]
		instance.max_hp = max_hp
		instance.hp = max_hp
		instance.block = 0
		instance.intent_move = {}
		instance.move_cooldowns = {}
		instance.last_move_id = ""
		instance.consecutive_count = 0
		enemies.append(instance)
		index += 1
	return enemies


func _build_starting_deck(character: Dictionary) -> Array:
	var deck: Array[String] = []
	for entry in character.starting_deck:
		for i in range(int(entry.count)):
			deck.append(String(entry.card_id))
	return deck


func _build_run_deck(run_state: Dictionary) -> Array:
	var deck: Array[String] = []
	for card in run_state.get("deck", []):
		deck.append(String(card.get("card_id", "")))
	return deck


func _living_enemy_indices() -> Array:
	var result := []
	for index in range(state.get("enemies", []).size()):
		if int(state.enemies[index].get("hp", 0)) > 0:
			result.append(index)
	return result


func _trigger_relic_hook(run_state: Dictionary, hook: String) -> Dictionary:
	var context := {
		"node_id": String(run_state.get("current_node_id", "")),
		"depth": 0
	}
	var triggered := relic_manager.trigger_combat(run_state, state, hook, context)
	if not triggered.ok:
		return triggered
	for change in triggered.get("changes", []):
		_log("Relic %s triggered %s" % [String(change.get("relic_id", "")), hook])
	return triggered


func _card(card_id: String) -> Dictionary:
	return database.cards[card_id]


func _requires_enemy_target(card: Dictionary) -> bool:
	for effect in card.effects:
		if String(effect.get("target", card.get("target", "none"))) == "selected_enemy":
			return true
	return false


func _is_valid_enemy_target(target_index: int) -> bool:
	return target_index >= 0 and target_index < state.enemies.size() and int(state.enemies[target_index].hp) > 0


func _move_phase_is_active(enemy: Dictionary, move: Dictionary) -> bool:
	if not move.has("phase") or not enemy.has("phases"):
		return true
	var phase_id := String(move.phase)
	var hp_ratio: float = float(enemy.hp) / maxf(1.0, float(enemy.max_hp))
	for phase in enemy.phases:
		if String(phase.get("id", "")) != phase_id:
			continue
		if phase.has("hp_above_ratio") and hp_ratio <= float(phase.hp_above_ratio):
			return false
		if phase.has("hp_at_or_below_ratio") and hp_ratio > float(phase.hp_at_or_below_ratio):
			return false
		return true
	return true


func _move_timing_is_legal(enemy: Dictionary, move: Dictionary) -> bool:
	var move_id := String(move.get("id", ""))
	if int(enemy.get("move_cooldowns", {}).get(move_id, 0)) > 0:
		return false
	var max_consecutive := int(move.get("max_consecutive", 0))
	if max_consecutive > 0 and String(enemy.get("last_move_id", "")) == move_id and int(enemy.get("consecutive_count", 0)) >= max_consecutive:
		return false
	return true


func _tick_move_cooldowns(enemy_index: int) -> void:
	var cooldowns: Dictionary = state.enemies[enemy_index].get("move_cooldowns", {})
	for move_id in cooldowns.keys():
		cooldowns[move_id] = max(0, int(cooldowns[move_id]) - 1)
	state.enemies[enemy_index].move_cooldowns = cooldowns


func _mark_move_selected(enemy_index: int, move: Dictionary) -> void:
	if move.is_empty():
		return
	var move_id := String(move.get("id", ""))
	if String(state.enemies[enemy_index].get("last_move_id", "")) == move_id:
		state.enemies[enemy_index].consecutive_count = int(state.enemies[enemy_index].get("consecutive_count", 0)) + 1
	else:
		state.enemies[enemy_index].last_move_id = move_id
		state.enemies[enemy_index].consecutive_count = 1
	if int(move.get("cooldown", 0)) > 0:
		var cooldowns: Dictionary = state.enemies[enemy_index].get("move_cooldowns", {})
		cooldowns[move_id] = int(move.cooldown)
		state.enemies[enemy_index].move_cooldowns = cooldowns


func _log(message: String) -> void:
	combat_log.append(message)
	if combat_log.size() > 80:
		combat_log.pop_front()


func _error(code: String, message: String, details: Dictionary = {}) -> Dictionary:
	return {"ok": false, "code": code, "message": message, "details": details}
