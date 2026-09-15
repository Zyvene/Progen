class_name StaticStructureView
extends Node3D

## Purely visual, physics-free rendering of a generated topology: plain box
## meshes positioned once at generation time and never touched again, so
## this view stays put regardless of what the live simulation (StructureView)
## elsewhere is doing. Reuses ShakeTable only for its platform mesh -- start()
## is never called on it here, so it never shakes.

var platform: ShakeTable
var _visuals: Array = []

func _ready() -> void:
	platform = ShakeTable.new()
	platform.name = "Platform"
	add_child(platform)

func clear() -> void:
	for child in get_children():
		if child == platform:
			continue
		remove_child(child)
		child.queue_free()
	_visuals.clear()

func build(params: Dictionary) -> Dictionary:
	clear()
	var topo := StructureGenerator.generate(params)
	var nodes: Dictionary = topo["nodes"]

	var footprint_x: float = float(params["bay_count_x"]) * float(params["bay_width_x"])
	var footprint_z: float = float(params["bay_count_y"]) * float(params["bay_width_y"])
	var story_height: float = params["story_height"]
	platform.configure(footprint_x / 2.0, footprint_z / 2.0, footprint_x, footprint_z, story_height, story_height)

	var columns: Array = topo["columns"]
	var beams: Array = topo["beams"]
	for pair in columns:
		_add_visual(pair[0], nodes[pair[0]], nodes[pair[1]], StructureView.COLUMN_COLOR)
	for pair in beams:
		_add_visual(pair[0], nodes[pair[0]], nodes[pair[1]], StructureView.BEAM_COLOR)

	return {
		"node_count": nodes.size(),
		"column_count": columns.size(),
		"beam_count": beams.size(),
	}

func _add_visual(key_a: Vector3i, pos_a: Vector3, pos_b: Vector3, color: Color) -> void:
	if key_a.x == 0:
		return  # ground-story columns stay buried inside the platform
	var visual := MemberVisual.new()
	visual.setup(color, StructureView.MEMBER_THICKNESS)
	add_child(visual)
	visual.update_between(pos_a, pos_b)
	_visuals.append(visual)
