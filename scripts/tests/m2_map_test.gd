extends SceneTree

const DataLoader = preload("res://scripts/core/data_loader.gd")
const DifficultyManager = preload("res://scripts/core/difficulty_manager.gd")
const MapGenerator = preload("res://scripts/map/map_generator.gd")
const MapValidator = preload("res://scripts/map/map_validator.gd")
const RngStreamRegistry = preload("res://scripts/core/rng_stream_registry.gd")

var failed := false


func _init() -> void:
	var database := DataLoader.load_content_database()
	var difficulty_manager := DifficultyManager.new(database)
	var act: Dictionary = database.acts["act1_emberwood_m2"]
	var generator := MapGenerator.new()

	var first_registry := RngStreamRegistry.new(424242, "ember_ranger", "D1")
	var second_registry := RngStreamRegistry.new(424242, "ember_ranger", "D1")
	var first := generator.generate(act, difficulty_manager.create_snapshot("D1"), first_registry.get_stream("map_rng"))
	var second := generator.generate(act, difficulty_manager.create_snapshot("D1"), second_registry.get_stream("map_rng"))
	_assert(first == second, "same character/difficulty/seed must generate identical maps")
	_assert(first_registry.snapshot_all().map_rng == second_registry.snapshot_all().map_rng, "map RNG snapshots must match")

	for seed in range(1000):
		var registry := RngStreamRegistry.new(seed, "ember_ranger", "D3")
		var map_data := generator.generate(act, difficulty_manager.create_snapshot("D3"), registry.get_stream("map_rng"))
		var validation := MapValidator.validate(map_data, act)
		if not validation.ok:
			_assert(false, "seed %d failed map validation: %s" % [seed, str(validation.errors)])
			break

	if failed:
		quit(1)
		return
	print("M2 map test passed: 1000 seeds")
	quit(0)


func _assert(condition: bool, message: String) -> void:
	if not condition:
		failed = true
		push_error(message)
