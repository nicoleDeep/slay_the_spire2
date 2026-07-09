extends RefCounted
class_name MapGenerator


func generate(act_config: Dictionary, difficulty_snapshot: Dictionary, map_rng: RngStream) -> Dictionary:
	var floor_count := int(act_config.get("floor_count", 0))
	var boss_floor := int(act_config.get("boss_floor", floor_count))
	var floors: Array = []
	for floor_number in range(1, floor_count + 1):
		var count := 1 if floor_number == boss_floor else _node_count_for_floor(act_config, floor_number, map_rng)
		var nodes: Array = []
		for column in range(count):
			nodes.append(_new_node(floor_number, column, count))
		floors.append({"floor": floor_number, "nodes": nodes})

	for floor_index in range(floors.size() - 1):
		var current_nodes: Array = floors[floor_index].nodes
		var next_nodes: Array = floors[floor_index + 1].nodes
		for column in range(current_nodes.size()):
			var edge_indices: Array[int] = [mini(column, next_nodes.size() - 1)]
			if next_nodes.size() > 1:
				edge_indices.append(mini(column + 1, next_nodes.size() - 1))
			edge_indices.sort()
			for edge_index in edge_indices:
				var target_id: String = next_nodes[edge_index].id
				if not current_nodes[column].edges.has(target_id):
					current_nodes[column].edges.append(target_id)

	var previous_floor_has_elite := false
	var previous_floor_has_rest := false
	var elite_floors_used := 0
	var max_elite_floors := int(act_config.get("constraints", {}).get("max_elites_per_path", 3))
	for floor_index in range(floors.size()):
		var floor_number := floor_index + 1
		var floor_has_elite := false
		var floor_has_rest := false
		for column in range(floors[floor_index].nodes.size()):
			var node: Dictionary = floors[floor_index].nodes[column]
			node.type = _type_for_node(
				act_config,
				difficulty_snapshot,
				floor_number,
				column,
				previous_floor_has_elite or elite_floors_used >= max_elite_floors,
				previous_floor_has_rest,
				map_rng
			)
			_set_content_contract(node, act_config, map_rng)
			node.status = "available" if floor_number == 1 else "locked"
			floors[floor_index].nodes[column] = node
			floor_has_elite = floor_has_elite or node.type == "elite"
			floor_has_rest = floor_has_rest or node.type == "rest"
		if floor_has_elite:
			elite_floors_used += 1
		previous_floor_has_elite = floor_has_elite
		previous_floor_has_rest = floor_has_rest

	return {
		"act_id": String(act_config.get("id", "")),
		"floor_count": floor_count,
		"boss_node": String(floors.back().nodes[0].id),
		"floors": floors
	}


func _node_count_for_floor(act_config: Dictionary, floor_number: int, map_rng: RngStream) -> int:
	if floor_number == 1:
		return int(act_config.get("start_node_count", 3))
	var limits: Dictionary = act_config.get("nodes_per_floor", {})
	return map_rng.next_int_range(int(limits.get("min", 2)), int(limits.get("max", 5)))


func _new_node(floor_number: int, column: int, count: int) -> Dictionary:
	return {
		"id": "f%02d_n%02d" % [floor_number, column],
		"floor": floor_number,
		"column": column,
		"x": (float(column) + 1.0) / (float(count) + 1.0),
		"type": "normal",
		"edges": [],
		"status": "locked",
		"content_ref": null,
		"content_ref_owner": "static",
		"content_ref_timing": "config",
		"resolution_id": null,
		"metadata": {"environment_tags": ["emberwood"]}
	}


func _type_for_node(
	act_config: Dictionary,
	difficulty_snapshot: Dictionary,
	floor_number: int,
	column: int,
	block_elite: bool,
	block_rest: bool,
	map_rng: RngStream
) -> String:
	for rule in act_config.get("floor_rules", []):
		if _rule_applies(rule, floor_number) and rule.has("force_type"):
			return String(rule.force_type)
	if column == 0:
		return "normal"
	var weights: Dictionary = act_config.get("node_weights", {}).duplicate(true)
	for rule in act_config.get("floor_rules", []):
		if not _rule_applies(rule, floor_number):
			continue
		for key in rule.get("weight_multiplier", {}).keys():
			weights[key] = int(round(float(weights.get(key, 0)) * float(rule.weight_multiplier[key])))
	for modifier in difficulty_snapshot.get("modifiers", []):
		if String(modifier.get("system", "")) == "map":
			weights.elite = maxi(0, int(weights.get("elite", 0)) + int(modifier.get("params", {}).get("elite_weight_delta", 0)))
	if block_elite:
		weights.elite = 0
	if block_rest:
		weights.rest = 0
	var candidates: Array = []
	var keys: Array = weights.keys()
	keys.sort()
	for key in keys:
		if int(weights[key]) > 0:
			candidates.append({"id": String(key), "weight": int(weights[key])})
	var picked := map_rng.pick_weighted(candidates)
	return String(picked.get("id", "normal"))


func _rule_applies(rule: Dictionary, floor_number: int) -> bool:
	for configured_floor in rule.get("floors", []):
		if int(configured_floor) == floor_number:
			return true
	return false


func _set_content_contract(node: Dictionary, act_config: Dictionary, map_rng: RngStream) -> void:
	match String(node.type):
		"normal":
			node.content_ref_owner = "map_rng"
			node.content_ref_timing = "run_creation"
			node.content_ref = _pick_stable(act_config.get("pools", {}).get("normal_encounters", []), map_rng)
		"elite":
			node.content_ref_owner = "map_rng"
			node.content_ref_timing = "run_creation"
			node.content_ref = _pick_stable(act_config.get("pools", {}).get("elite_encounters", []), map_rng)
		"boss":
			node.content_ref_owner = "map_rng"
			node.content_ref_timing = "run_creation"
			node.content_ref = _pick_stable(act_config.get("pools", {}).get("bosses", []), map_rng)
		"event":
			node.content_ref_owner = "event_rng"
			node.content_ref_timing = "first_entry"
		"shop":
			node.content_ref_owner = "shop_rng"
			node.content_ref_timing = "first_entry"
		"treasure":
			node.content_ref_owner = "reward_rng"
			node.content_ref_timing = "first_entry"
		"rest":
			node.content_ref_owner = "static"
			node.content_ref_timing = "config"
			node.content_ref = String(act_config.get("rest_definition_id", ""))


func _pick_stable(values: Array, map_rng: RngStream) -> Variant:
	if values.is_empty():
		return null
	var stable := values.duplicate()
	stable.sort()
	return stable[map_rng.next_int_range(0, stable.size() - 1)]
