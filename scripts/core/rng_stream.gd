extends RefCounted
class_name RngStream

const ALGORITHM := "godot_rng_v1"

var seed_value: int
var draw_count: int = 0
var _rng := RandomNumberGenerator.new()

func _init(initial_seed: int = 1, previous_snapshot: Dictionary = {}) -> void:
	seed_value = initial_seed
	_rng.seed = seed_value
	draw_count = 0
	if not previous_snapshot.is_empty():
		var result := restore(previous_snapshot)
		assert(result.ok, String(result.get("message", "Invalid RNG snapshot")))


func randf() -> float:
	return next_float()


func randi_range(min_value: int, max_value: int) -> int:
	return next_int_range(min_value, max_value)


func next_float() -> float:
	draw_count += 1
	return _rng.randf()


func next_int_range(min_value: int, max_value: int) -> int:
	if max_value < min_value:
		return min_value
	draw_count += 1
	return _rng.randi_range(min_value, max_value)


func pick_weighted(items: Array, weight_key: String = "weight") -> Dictionary:
	var total := 0
	for item in items:
		if item is Dictionary:
			total += int(item.get(weight_key, 0))
	if total <= 0:
		return {}
	var roll := next_int_range(1, total)
	var cursor := 0
	for item in items:
		cursor += int(item.get(weight_key, 0))
		if roll <= cursor:
			return item
	return items.back() if not items.is_empty() else {}


func shuffle_array(values: Array) -> void:
	if values.size() <= 1:
		return
	for i in range(values.size() - 1, 0, -1):
		var j := next_int_range(0, i)
		var tmp: Variant = values[i]
		values[i] = values[j]
		values[j] = tmp


func snapshot() -> Dictionary:
	return {
		"algorithm": ALGORITHM,
		"seed": seed_value,
		"draw_count": draw_count,
		"state": _rng.state
	}


func restore(value: Dictionary) -> Dictionary:
	if String(value.get("algorithm", "")) != ALGORITHM:
		return {"ok": false, "code": "ERR_RNG_ALGORITHM", "message": "Unsupported RNG algorithm"}
	if int(value.get("draw_count", -1)) < 0:
		return {"ok": false, "code": "ERR_RNG_DRAW_COUNT", "message": "RNG draw_count must be non-negative"}
	seed_value = int(value.get("seed", 0))
	_rng.seed = seed_value
	_rng.state = int(value.get("state", 0))
	draw_count = int(value.draw_count)
	return {"ok": true, "code": "OK"}
