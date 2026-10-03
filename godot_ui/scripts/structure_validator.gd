class_name StructureValidator
extends RefCounted

static func validate(params: Dictionary, topo: Dictionary) -> Dictionary:
	var errors: Array[String] = []
	var warnings: Array[String] = []

	var nodes: Dictionary = topo["nodes"]
	var columns: Array = topo["columns"]
	var beams: Array = topo["beams"]
	var base_keys: Array = topo["base_keys"]
	var n_levels: int = topo["n_levels"]
	var n_nodes_x: int = topo["n_nodes_x"]
	var n_nodes_y: int = topo["n_nodes_y"]
	var floor_count: int = params["floor_count"]

	var n_nodes_expected := n_levels * n_nodes_x * n_nodes_y
	if nodes.size() != n_nodes_expected:
		errors.append("expected %d nodes, found %d" % [n_nodes_expected, nodes.size()])

	var n_cols_expected := floor_count * n_nodes_x * n_nodes_y
	if columns.size() != n_cols_expected:
		errors.append("expected %d column elements, found %d" % [n_cols_expected, columns.size()])

	var n_beams_per_level := n_nodes_y * (n_nodes_x - 1) + n_nodes_x * (n_nodes_y - 1)
	var n_beams_expected := n_beams_per_level * floor_count
	if beams.size() != n_beams_expected:
		errors.append("expected %d beam elements, found %d" % [n_beams_expected, beams.size()])

	var expected_base_nodes := n_nodes_x * n_nodes_y
	if base_keys.size() != expected_base_nodes:
		errors.append("expected %d fixed base nodes, found %d" % [expected_base_nodes, base_keys.size()])

	var adjacency: Dictionary = {}
	for key in nodes.keys():
		adjacency[key] = []
	for pair in columns:
		adjacency[pair[0]].append(pair[1])
		adjacency[pair[1]].append(pair[0])
	for pair in beams:
		adjacency[pair[0]].append(pair[1])
		adjacency[pair[1]].append(pair[0])

	var base_set: Dictionary = {}
	for key in base_keys:
		base_set[key] = true

	var orphaned: Array = []
	for key in nodes.keys():
		if adjacency[key].is_empty() and not base_set.has(key):
			orphaned.append(key)
	if not orphaned.is_empty():
		errors.append("%d orphaned node(s) with no elements" % orphaned.size())

	var visited: Dictionary = {}
	var frontier: Array = base_keys.duplicate()
	for key in frontier:
		visited[key] = true
	while not frontier.is_empty():
		var next_frontier: Array = []
		for key in frontier:
			for neighbor in adjacency.get(key, []):
				if not visited.has(neighbor):
					visited[neighbor] = true
					next_frontier.append(neighbor)
		frontier = next_frontier

	var unreachable_count := 0
	for key in nodes.keys():
		if not visited.has(key):
			unreachable_count += 1
	if unreachable_count > 0:
		errors.append("%d node(s) not connected to the base through the element graph" % unreachable_count)

	return {"ok": errors.is_empty(), "errors": errors, "warnings": warnings}
