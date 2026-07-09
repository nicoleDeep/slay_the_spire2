extends RefCounted
class_name RngStreamRegistry

const RngStream = preload("res://scripts/core/rng_stream.gd")
const STREAM_NAMES := ["map_rng", "combat_rng", "reward_rng", "event_rng", "shop_rng"]
const DERIVATION_PREFIX := "sts2like:m2:v1"

var streams: Dictionary = {}


func _init(run_seed: int, character_id: String, difficulty_id: String, snapshots: Dictionary = {}) -> void:
	for stream_name in STREAM_NAMES:
		var stream_seed := derive_seed(run_seed, character_id, difficulty_id, stream_name)
		var snapshot: Dictionary = snapshots.get(stream_name, {})
		streams[stream_name] = RngStream.new(stream_seed, snapshot)


func get_stream(stream_name: String) -> RngStream:
	assert(STREAM_NAMES.has(stream_name), "Unknown RNG stream: %s" % stream_name)
	return streams[stream_name]


func snapshot_all() -> Dictionary:
	var result := {}
	for stream_name in STREAM_NAMES:
		result[stream_name] = get_stream(stream_name).snapshot()
	return result


static func derive_seed(run_seed: int, character_id: String, difficulty_id: String, stream_name: String) -> int:
	var input := "%s|%d|%s|%s|%s" % [DERIVATION_PREFIX, run_seed, character_id, difficulty_id, stream_name]
	var hashing := HashingContext.new()
	hashing.start(HashingContext.HASH_SHA256)
	hashing.update(input.to_utf8_buffer())
	var digest := hashing.finish()
	var little_endian := PackedByteArray()
	for index in range(7, -1, -1):
		little_endian.append(digest[index])
	return little_endian.decode_u64(0)
