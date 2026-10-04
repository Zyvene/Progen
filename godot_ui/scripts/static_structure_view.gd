class_name StaticStructureView
extends Node3D

const COLUMN_COLOR := Color(0.19, 0.32, 0.55)
const BEAM_COLOR := Color(0.6, 0.65, 0.72)
const BRACE_COLOR := Color(0.95, 0.55, 0.1)
const STRUT_COLOR := Color(0.55, 0.25, 0.75)
const UPSIZED_COLOR := Color(0.86, 0.2, 0.2)
const STARTING_SECTION := "W12X26"
const GRAVITY_M_S2 := 9.81
const TOPPLE_MIN_S := 0.6

var _visuals: Array = []
var _sections: Dictionary = {}
var _section_order: Array = []
var _frame_ids: PackedStringArray = PackedStringArray()
var _node_rest: Dictionary = {}
var _node_support: Dictionary = {}
var _node_order: Array = []

func set_sections(section_list: Array) -> void:
	_sections.clear()
	_section_order.clear()
	for entry in section_list:
		_sections[entry["name"]] = entry
		_section_order.append(entry["name"])

func has_sections() -> bool:
	return not _sections.is_empty()

func next_section(name: String) -> String:
	var index := _section_order.find(name)
	if index < 0 or index + 1 >= _section_order.size():
		return name
	return _section_order[index + 1]

func clear() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_visuals.clear()
	_frame_ids.clear()
	_node_rest.clear()
	_node_support.clear()
	_node_order.clear()

func build(topo: Dictionary) -> void:
	build_state(topo, {}, [])

static func member_id(a: Vector3i, b: Vector3i) -> String:
	return "%d,%d,%d|%d,%d,%d" % [a.x, a.y, a.z, b.x, b.y, b.z]

static func node_id(key: Vector3i) -> String:
	return "%d,%d,%d" % [key.x, key.y, key.z]

static func mid_node_id(story: int, row: int, col: int) -> String:
	return "mid:%d,%d,%d" % [story, row, col]

static func frame_node_id(key: Array) -> String:
	if key.size() == 4:
		return mid_node_id(int(key[1]), int(key[2]), int(key[3]))
	return "%d,%d,%d" % [int(key[0]), int(key[1]), int(key[2])]

func set_frame_nodes(node_keys: Array) -> void:
	_frame_ids.clear()
	for key in node_keys:
		_frame_ids.append(frame_node_id(key))

func apply_frame(values: PackedFloat32Array, magnification: float) -> void:
	var offsets := {}
	var count: int = min(_frame_ids.size(), values.size() / 2)
	for i in range(count):
		offsets[_frame_ids[i]] = Vector3(values[2 * i], 0.0, values[2 * i + 1]) * magnification
	if _node_order.is_empty():
		_node_order = _node_rest.keys()
		_node_order.sort_custom(func(p, q): return (_node_rest[p] as Vector3).y < (_node_rest[q] as Vector3).y)
	var positions := {}
	for id in _node_order:
		var moved: Vector3 = _node_rest[id] + offsets.get(id, Vector3.ZERO)
		if _node_support.has(id) and positions.has(_node_support[id][0]):
			var below_id: String = _node_support[id][0]
			var length: float = _node_support[id][1]
			var drift: Vector3 = offsets.get(id, Vector3.ZERO) - offsets.get(below_id, Vector3.ZERO)
			if drift.length() > length:
				drift = drift.normalized() * length
			moved = positions[below_id] + drift + Vector3.UP * sqrt(max(length * length - drift.length_squared(), 0.0))
		positions[id] = moved
	for entry in _visuals:
		if entry.get("fall_time", -1.0) >= 0.0:
			continue
		var visual: MemberVisual = entry["visual"]
		visual.place(positions.get(entry["na"], entry["a"]), positions.get(entry["nb"], entry["b"]))

func reset_frame() -> void:
	for entry in _visuals:
		entry["fall_time"] = -1.0
		var visual: MemberVisual = entry["visual"]
		visual.place(entry["a"], entry["b"])

func drop_member(node_keys: Array) -> int:
	if node_keys.size() != 2:
		return 0
	var id_a := frame_node_id(node_keys[0])
	var id_b := frame_node_id(node_keys[1])
	var dropped := 0
	for entry in _visuals:
		if entry.get("fall_time", -1.0) >= 0.0:
			continue
		if not ((entry["na"] == id_a and entry["nb"] == id_b) or (entry["na"] == id_b and entry["nb"] == id_a)):
			continue
		var visual: MemberVisual = entry["visual"]
		var basis := visual.transform.basis
		var axis := basis.z.normalized()
		var flat := Vector3(axis.x, 0.0, axis.z)
		if flat.length() < 0.2:
			var lean: Vector3 = visual.transform.origin - (entry["a"] + entry["b"]) * 0.5
			flat = Vector3(lean.x, 0.0, lean.z)
			if flat.length() < 0.001:
				flat = Vector3.RIGHT
		var start := Quaternion(basis.orthonormalized())
		entry["fall_time"] = 0.0
		entry["fall_origin"] = visual.transform.origin
		entry["fall_start"] = start
		entry["fall_end"] = Quaternion(axis, flat.normalized()) * start
		entry["fall_scale"] = 1.0
		entry["fall_length"] = visual._base_length
		entry["fall_rest"] = float(_sections[entry["section"]]["d_m"]) * 0.5
		dropped += 1
	return dropped

func update_falls(delta: float) -> void:
	for entry in _visuals:
		var t: float = entry.get("fall_time", -1.0)
		if t < 0.0:
			continue
		t += delta
		entry["fall_time"] = t
		var origin: Vector3 = entry["fall_origin"]
		var rest: float = entry["fall_rest"]
		var land_s: float = max(sqrt(2.0 * max(origin.y - rest, 0.0) / GRAVITY_M_S2), TOPPLE_MIN_S)
		var turn: Quaternion = (entry["fall_start"] as Quaternion).slerp(entry["fall_end"], min(t / land_s, 1.0))
		var basis := Basis(turn)
		var half_height: float = float(entry["fall_length"]) * 0.5 * abs(basis.z.y)
		var y: float = max(origin.y - 0.5 * GRAVITY_M_S2 * t * t, rest + half_height)
		basis.z *= float(entry["fall_scale"])
		var visual: MemberVisual = entry["visual"]
		visual.transform = Transform3D(basis, Vector3(origin.x, y, origin.z))

func build_state(topo: Dictionary, model_state: Dictionary, highlighted: Array) -> void:
	clear()
	if not has_sections():
		return
	var nodes: Dictionary = topo["nodes"]
	var n_nodes_x: int = topo["n_nodes_x"]
	var n_nodes_y: int = topo["n_nodes_y"]
	var member_sections: Dictionary = model_state.get("member_sections", {})
	var strut_mids := {}
	for entry in model_state.get("struts", []):
		for key in _strut_keys(int(entry["story"]), entry["axis"], int(entry["line"]), int(entry["bay"])):
			strut_mids[mid_node_id(key.x, key.y, key.z)] = true

	for pair in (topo["columns"] as Array):
		var a: Vector3i = pair[0]
		var b: Vector3i = pair[1]
		var mid := member_id(a, b)
		var color := UPSIZED_COLOR if highlighted.has(mid) else COLUMN_COLOR
		var section_name: String = member_sections.get(mid, STARTING_SECTION)
		var perimeter := _is_perimeter(a, n_nodes_x, n_nodes_y)
		var split_id := mid_node_id(b.x, b.y, b.z)
		if strut_mids.has(split_id):
			var middle: Vector3 = (nodes[a] + nodes[b]) * 0.5
			_add_member("column", a, b, nodes[a], middle, section_name, Vector3.RIGHT, color, perimeter,
				[node_id(a), split_id])
			_add_member("column", a, b, middle, nodes[b], section_name, Vector3.RIGHT, color, perimeter,
				[split_id, node_id(b)])
		else:
			_add_member("column", a, b, nodes[a], nodes[b], section_name, Vector3.RIGHT, color, perimeter)
	for pair in (topo["beams"] as Array):
		var a: Vector3i = pair[0]
		var b: Vector3i = pair[1]
		var mid := member_id(a, b)
		var color := UPSIZED_COLOR if highlighted.has(mid) else BEAM_COLOR
		_add_member("beam", a, b, nodes[a], nodes[b], member_sections.get(mid, STARTING_SECTION), Vector3.UP,
			color, _is_perimeter(a, n_nodes_x, n_nodes_y) and _is_perimeter(b, n_nodes_x, n_nodes_y))
	for entry in model_state.get("braces", []):
		var label := "brace:%d:%s:%d:%d" % [int(entry["story"]), entry["axis"], int(entry["line"]), int(entry["bay"])]
		var color := UPSIZED_COLOR if highlighted.has(label) else BRACE_COLOR
		_add_brace_bay(nodes, int(entry["story"]), entry["axis"], int(entry["line"]), int(entry["bay"]),
			entry.get("section", STARTING_SECTION), color)
	for entry in model_state.get("struts", []):
		var label := "strut:%d:%s:%d:%d" % [int(entry["story"]), entry["axis"], int(entry["line"]), int(entry["bay"])]
		var color := UPSIZED_COLOR if highlighted.has(label) else STRUT_COLOR
		_add_strut(nodes, int(entry["story"]), entry["axis"], int(entry["line"]), int(entry["bay"]),
			entry.get("section", STARTING_SECTION), color)

func preview_rule(rule_number: int, topo: Dictionary) -> String:
	var floor_count: int = int(topo["n_levels"]) - 1
	match rule_number:
		1:
			_upsize_where(func(e): return e["kind"] == "column" or e["kind"] == "beam")
			return "members upsized one W-shape step (%s -> %s) where peak stress exceeds yield; example shows every member" % [STARTING_SECTION, next_section(STARTING_SECTION)]
		2:
			_add_struts(topo, [1], "y")
			return "mid-height struts added along the columns' weak axis (Y); example shows story 1"
		3:
			_upsize_where(func(e): return e["kind"] == "column" or e["kind"] == "beam")
			return "members upsized one W-shape step where peak strain exceeds elongation at break; example shows every member"
		4:
			_add_bracing(topo, [1], "x", false)
			_add_bracing(topo, [1], "y", false)
			return "X-bracing added in all bays of the exceeding floor, both directions; example shows floor 1"
		5:
			_upsize_where(func(e): return e["kind"] == "column" and e["story"] == 1)
			return "columns of the soft story upsized one W-shape step; example shows story 1"
		6:
			var mid_levels: Array = range(2, floor_count)
			if mid_levels.is_empty():
				return "not applicable -- mid-story concentration only triggers on buildings with 3+ floors"
			_add_bracing(topo, mid_levels, "x", true)
			_add_bracing(topo, mid_levels, "y", true)
			return "X-bracing added on the perimeter bays of the mid-height floors"
		7:
			_add_bracing(topo, range(1, floor_count + 1), "y", false)
			return "X-bracing added in the bays of the weak direction; example shows Y (the columns' weak axis) on all floors"
		8:
			_upsize_where(func(e): return e["kind"] == "column" and e["story"] == 1)
			return "columns of the story with the greatest drift upsized one W-shape step; example shows story 1"
		9:
			_add_bracing(topo, range(1, floor_count + 1), "x", true)
			_add_bracing(topo, range(1, floor_count + 1), "y", true)
			return "X-bracing added on all perimeter bays, all floors"
		10:
			_upsize_where(func(e): return e["kind"] == "column" or e["kind"] == "beam")
			return "every member upsized one W-shape step (mean stress approaching yield)"
		_:
			return ""

func _is_perimeter(key: Vector3i, n_nodes_x: int, n_nodes_y: int) -> bool:
	return key.y == 0 or key.y == n_nodes_y - 1 or key.z == 0 or key.z == n_nodes_x - 1

func _add_member(kind: String, a_key, b_key, pos_a: Vector3, pos_b: Vector3, section_name: String,
		depth_hint: Vector3, color: Color, is_perimeter: bool, ids: Array = []) -> void:
	var visual := MemberVisual.new()
	add_child(visual)
	visual.setup(color, pos_a, pos_b, _sections[section_name], depth_hint)
	var story := 0
	if a_key is Vector3i and b_key is Vector3i:
		story = max((a_key as Vector3i).x, (b_key as Vector3i).x)
	if ids.is_empty():
		ids = [node_id(a_key), node_id(b_key)]
	_node_rest[ids[0]] = pos_a
	_node_rest[ids[1]] = pos_b
	_node_order.clear()
	if kind == "column":
		_node_support[ids[1]] = [ids[0], pos_a.distance_to(pos_b)]
	_visuals.append({
		"visual": visual, "kind": kind, "section": section_name, "story": story, "color": color,
		"is_perimeter": is_perimeter, "a": pos_a, "b": pos_b, "depth_hint": depth_hint,
		"na": ids[0], "nb": ids[1],
	})

func _upsize_where(predicate: Callable) -> void:
	for entry in _visuals:
		if not predicate.call(entry):
			continue
		var upsized := next_section(entry["section"])
		entry["section"] = upsized
		var visual: MemberVisual = entry["visual"]
		visual.setup(UPSIZED_COLOR, entry["a"], entry["b"], _sections[upsized], entry["depth_hint"])
		entry["color"] = UPSIZED_COLOR

func set_highlights(visible_colors: bool) -> void:
	for entry in _visuals:
		var visual: MemberVisual = entry["visual"]
		if visible_colors:
			visual.set_color(entry["color"])
		else:
			visual.set_color(COLUMN_COLOR if entry["kind"] == "column" else BEAM_COLOR)

func _add_bracing(topo: Dictionary, levels: Array, axis: String, perimeter_only: bool) -> void:
	var nodes: Dictionary = topo["nodes"]
	var n_nodes_x: int = topo["n_nodes_x"]
	var n_nodes_y: int = topo["n_nodes_y"]
	var lines: int = n_nodes_y if axis == "x" else n_nodes_x
	var bays: int = (n_nodes_x if axis == "x" else n_nodes_y) - 1
	for level in levels:
		for line in range(lines):
			if perimeter_only and line != 0 and line != lines - 1:
				continue
			for bay in range(bays):
				_add_brace_bay(nodes, level, axis, line, bay, STARTING_SECTION, BRACE_COLOR)

func _add_brace_bay(nodes: Dictionary, level: int, axis: String, line: int, bay: int,
		section_name: String, color: Color) -> void:
	var diagonals: Array
	var frame_normal: Vector3
	if axis == "x":
		diagonals = [
			[Vector3i(level - 1, line, bay), Vector3i(level, line, bay + 1)],
			[Vector3i(level - 1, line, bay + 1), Vector3i(level, line, bay)],
		]
		frame_normal = Vector3.BACK
	else:
		diagonals = [
			[Vector3i(level - 1, bay, line), Vector3i(level, bay + 1, line)],
			[Vector3i(level - 1, bay + 1, line), Vector3i(level, bay, line)],
		]
		frame_normal = Vector3.RIGHT
	for pair in diagonals:
		var pa: Vector3 = nodes[pair[0]]
		var pb: Vector3 = nodes[pair[1]]
		var in_plane_depth := frame_normal.cross((pb - pa).normalized())
		_add_member("brace", pair[0], pair[1], pa, pb, section_name, in_plane_depth, color, false)

func _add_struts(topo: Dictionary, levels: Array, axis: String) -> void:
	var nodes: Dictionary = topo["nodes"]
	var n_nodes_x: int = topo["n_nodes_x"]
	var n_nodes_y: int = topo["n_nodes_y"]
	var lines: int = n_nodes_y if axis == "x" else n_nodes_x
	var bays: int = (n_nodes_x if axis == "x" else n_nodes_y) - 1
	for level in levels:
		for line in range(lines):
			for bay in range(bays):
				_add_strut(nodes, level, axis, line, bay, STARTING_SECTION, STRUT_COLOR)

func _strut_keys(level: int, axis: String, line: int, bay: int) -> Array:
	if axis == "x":
		return [Vector3i(level, line, bay), Vector3i(level, line, bay + 1)]
	return [Vector3i(level, bay, line), Vector3i(level, bay + 1, line)]

func _add_strut(nodes: Dictionary, level: int, axis: String, line: int, bay: int,
		section_name: String, color: Color) -> void:
	var keys := _strut_keys(level, axis, line, bay)
	var a_key: Vector3i = keys[0]
	var b_key: Vector3i = keys[1]
	var below_a: Vector3 = nodes[Vector3i(level - 1, a_key.y, a_key.z)]
	var below_b: Vector3 = nodes[Vector3i(level - 1, b_key.y, b_key.z)]
	var mid_a: Vector3 = (below_a + nodes[a_key]) * 0.5
	var mid_b: Vector3 = (below_b + nodes[b_key]) * 0.5
	_add_member("strut", a_key, b_key, mid_a, mid_b, section_name, Vector3.UP, color, false,
		[mid_node_id(a_key.x, a_key.y, a_key.z), mid_node_id(b_key.x, b_key.y, b_key.z)])
