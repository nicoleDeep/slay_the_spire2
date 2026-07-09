extends RefCounted
class_name RngStream

var seed_value: int
var draw_count: int = 0
var _state: int

const _MODULUS := 2147483648
const _MASK := 2147483647
const _MULTIPLIER := 1103515245
const _INCREMENT := 12345

func _init(initial_seed: int = 1, previous_draw_count: int = 0) -> void:
	seed_value = initial_seed
	_state = _normalize_seed(seed_value)
	draw_count = 0
	for i in range(previous_draw_count):
		next_float()


func randf() -> float:
	return next_float()


func randi_range(min_value: int, max_value: int) -> int:
	return next_int_range(min_value, max_value)


func next_float() -> float:
	draw_count += 1
	return float(_next_int()) / float(_MASK)


func next_int_range(min_value: int, max_value: int) -> int:
	if max_value < min_value:
		return min_value
	draw_count += 1
	var span := max_value - min_value + 1
	return min_value + (_next_int() % span)


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
		"seed": seed_value,
		"draw_count": draw_count,
		"state": _state
	}


func _next_int() -> int:
	_state = (_state * _MULTIPLIER + _INCREMENT) % _MODULUS
	return _state & _MASK


func _normalize_seed(value: int) -> int:
	var normalized: int = int(abs(value)) % _MODULUS
	return 1 if normalized == 0 else normalized
