class_name StructureGenerator
extends RefCounted

## Pure topology logic: turns validated structural params into a beam-column
## grid. Mirrors the node/column/beam conventions in model_builder.py (repo
## root) so the two pipelines stay conceptually parallel, translated into
## Godot's Y-up convention: plan X/Y -> world X/Z, story height -> world Y.

static func generate(params: Dictionary) -> Dictionary:
	var floor_count: int = params["floor_count"]
	var bay_count_x: int = params["bay_count_x"]
	var bay_count_y: int = params["bay_count_y"]
	var bay_width_x: float = params["bay_width_x"]
	var bay_width_y: float = params["bay_width_y"]
	var story_height: float = params["story_height"]

	var n_nodes_x := bay_count_x + 1
	var n_nodes_y := bay_count_y + 1
	var n_levels := floor_count + 1

	var nodes: Dictionary = {}  # Vector3i(level, row, col) -> Vector3 world pos
	var base_keys: Array = []

	for level in range(n_levels):
		var y := level * story_height
		for row in range(n_nodes_y):
			var z := row * bay_width_y
			for col in range(n_nodes_x):
				var x := col * bay_width_x
				var key := Vector3i(level, row, col)
				nodes[key] = Vector3(x, y, z)
				if level == 0:
					base_keys.append(key)

	# Columns: one per grid point per story, level -> level+1.
	var columns: Array = []
	for level in range(floor_count):
		for row in range(n_nodes_y):
			for col in range(n_nodes_x):
				columns.append([
					Vector3i(level, row, col),
					Vector3i(level + 1, row, col),
				])

	# Beams: full X/Y grid at every level 1..floor_count. No beams at level 0.
	var beams: Array = []
	for level in range(1, n_levels):
		for row in range(n_nodes_y):
			for col in range(n_nodes_x - 1):
				beams.append([
					Vector3i(level, row, col),
					Vector3i(level, row, col + 1),
				])
		for col in range(n_nodes_x):
			for row in range(n_nodes_y - 1):
				beams.append([
					Vector3i(level, row, col),
					Vector3i(level, row + 1, col),
				])

	return {
		"nodes": nodes,
		"columns": columns,
		"beams": beams,
		"base_keys": base_keys,
		"n_levels": n_levels,
		"n_nodes_x": n_nodes_x,
		"n_nodes_y": n_nodes_y,
	}
