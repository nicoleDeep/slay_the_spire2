extends RefCounted
class_name MapValidator

const NODE_TYPES := ["normal", "elite", "boss", "shop", "event", "rest", "treasure"]


static func validate(map_data: Dictionary, act_config: Dictionary) -> Dictionary:
	var errors: Array[String] = []
	var floors: Array = map_data.get("floors", [])
	var nodes := _index_nodes(floors, errors)
	var floor_count := int(act_config.get("floor_count", 0))
	if floors.size() != floor_count:
		errors.append("Expected %d floors, found %d" % [floor_count, floors.size()])
	if floors.is_empty():
		return {"ok": false, "code": "ERR_MAP_INVALID", "errors": errors}
	if floors[0].nodes.size() != int(act_config.get("start_node_count", 0)):
		errors.append("Incorrect start node count")

	var incoming := {}
	for node_id in nodes.keys():
		incoming[node_id] = 0
	for node_id in nodes.keys():
		var node: Dictionary = nodes[node_id]
		if not NODE_TYPES.has(String(node.get("type", ""))):
			errors.append("Node %s has invalid type" % node_id)
		for target_id in node.get("edges", []):
			if not nodes.has(target_id):
				errors.append("Node %s has dangling edge %s" % [node_id, target_id])
				continue
			if int(nodes[target_id].floor) != int(node.floor) + 1:
				errors.append("Edge %s -> %s does not advance one floor" % [node_id, target_id])
			incoming[target_id] = int(incoming[target_id]) + 1
		if node.get("edges", []).size() > int(act_config.get("constraints", {}).get("max_out_degree", 3)):
			errors.append("Node %s exceeds max_out_degree" % node_id)
		if int(node.floor) < floor_count and node.get("edges", []).is_empty():
			errors.append("Node %s has no outgoing edge" % node_id)

	for node_id in nodes.keys():
		if int(nodes[node_id].floor) > 1 and int(incoming[node_id]) == 0:
			errors.append("Node %s is an island" % node_id)

	var boss_id := String(map_data.get("boss_node", ""))
	if not nodes.has(boss_id) or String(nodes.get(boss_id, {}).get("type", "")) != "boss":
		errors.append("Boss node is missing or invalid")
	var starts: Array = floors[0].nodes
	for start in starts:
		if not _can_reach(String(start.id), boss_id, nodes, {}):
			errors.append("Start %s cannot reach boss" % start.id)
	if not _has_path_with_flags(starts, boss_id, nodes, false, false):
		errors.append("No elite-free path reaches boss")
	if _has_path_with_flags(starts, boss_id, nodes, true, false):
		errors.append("A path reaches boss without pre-boss recovery")
	if _has_adjacent_elite_path(starts, boss_id, nodes):
		errors.append("A path contains consecutive elites")
	var path_error := _find_path_constraint_error(starts, boss_id, nodes, act_config.get("constraints", {}))
	if not path_error.is_empty():
		errors.append(path_error)

	return {
		"ok": errors.is_empty(),
		"code": "OK" if errors.is_empty() else "ERR_MAP_INVALID",
		"errors": errors
	}


static func _index_nodes(floors: Array, errors: Array[String]) -> Dictionary:
	var result := {}
	for floor in floors:
		for node in floor.get("nodes", []):
			var node_id := String(node.get("id", ""))
			if node_id.is_empty() or result.has(node_id):
				errors.append("Duplicate or empty node id: %s" % node_id)
			result[node_id] = node
	return result


static func _can_reach(current_id: String, target_id: String, nodes: Dictionary, visited: Dictionary) -> bool:
	if current_id == target_id:
		return true
	if visited.has(current_id):
		return false
	visited[current_id] = true
	for next_id in nodes[current_id].get("edges", []):
		if _can_reach(String(next_id), target_id, nodes, visited):
			return true
	return false


static func _has_path_with_flags(starts: Array, boss_id: String, nodes: Dictionary, require_no_recovery: bool, allow_elite: bool) -> bool:
	var stack: Array = []
	for start in starts:
		stack.append({"id": String(start.id), "recovery": false, "elite": false})
	while not stack.is_empty():
		var cursor: Dictionary = stack.pop_back()
		var node: Dictionary = nodes[cursor.id]
		var recovery := bool(cursor.recovery) or String(node.type) == "rest" or bool(node.get("metadata", {}).get("equivalent_recovery", false))
		var elite := bool(cursor.elite) or String(node.type) == "elite"
		if cursor.id == boss_id:
			if require_no_recovery and not recovery:
				return true
			if not require_no_recovery and (allow_elite or not elite):
				return true
			continue
		for next_id in node.get("edges", []):
			stack.append({"id": String(next_id), "recovery": recovery, "elite": elite})
	return false


static func _has_adjacent_elite_path(starts: Array, boss_id: String, nodes: Dictionary) -> bool:
	var stack: Array = []
	for start in starts:
		stack.append({"id": String(start.id), "previous_elite": false})
	while not stack.is_empty():
		var cursor: Dictionary = stack.pop_back()
		var node: Dictionary = nodes[cursor.id]
		var is_elite := String(node.type) == "elite"
		if bool(cursor.previous_elite) and is_elite:
			return true
		if cursor.id == boss_id:
			continue
		for next_id in node.get("edges", []):
			stack.append({"id": String(next_id), "previous_elite": is_elite})
	return false


static func _find_path_constraint_error(starts: Array, boss_id: String, nodes: Dictionary, constraints: Dictionary) -> String:
	var stack: Array = []
	for start in starts:
		stack.append({"id": String(start.id), "elite_count": 0, "last_rest_floor": -100, "has_gold_source": false})
	while not stack.is_empty():
		var cursor: Dictionary = stack.pop_back()
		var node: Dictionary = nodes[cursor.id]
		var elite_count := int(cursor.elite_count) + (1 if String(node.type) == "elite" else 0)
		if elite_count > int(constraints.get("max_elites_per_path", 3)):
			return "A path exceeds max_elites_per_path"
		var last_rest_floor := int(cursor.last_rest_floor)
		if String(node.type) == "rest":
			var rest_gap := int(node.floor) - last_rest_floor
			var is_pre_boss_exception := int(node.floor) >= int(nodes[boss_id].floor) - 1
			if rest_gap < int(constraints.get("min_rest_gap", 2)) and not is_pre_boss_exception:
				return "A path violates min_rest_gap"
			last_rest_floor = int(node.floor)
		var has_gold_source := bool(cursor.has_gold_source) or String(node.type) in ["normal", "event", "treasure"]
		if String(node.type) == "shop" and not has_gold_source:
			return "A shop is reachable without a prior gold source"
		if cursor.id == boss_id:
			continue
		for next_id in node.get("edges", []):
			stack.append({
				"id": String(next_id),
				"elite_count": elite_count,
				"last_rest_floor": last_rest_floor,
				"has_gold_source": has_gold_source
			})
	return ""
