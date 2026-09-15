class_name StructureView
extends Node3D

## Builds the physics/visual representation of a generated topology:
## one RigidBody3D per non-base node (gravity_scale = 0 -- the structure sits
## inert until shaken, not sagging under self-weight; a documented v1
## simplification, same spirit as SectionProps's placeholder in schema.py),
## and one springy Generic6DOFJoint3D + one stretched box mesh per
## non-buried column/beam.
##
## Level-1 nodes (tops of the buried ground-story columns) are frozen into
## KINEMATIC RigidBody3Ds and driven directly from the ShakeTable's
## transform every physics step, rather than held there by a physics
## joint. Early versions welded them with a Generic6DOFJoint3D instead, but
## with ~dozens to ~100+ of those simultaneously pinning different points
## to one shared body, the iterative solver couldn't always fully converge
## and the base visibly sagged/drifted off the platform. Direct transform
## copy is exact by construction -- no solver involved, no drift possible.
##
## Above FAILURE_MAGNITUDE_THRESHOLD, members can snap: each still-intact
## member rolls a small per-second chance of failure while the shake runs,
## weighted toward upper floors (a height-factor heuristic, not a real
## stress calculation -- Godot's high-level Joint3D API doesn't expose
## per-joint constraint force). A broken member's connecting joint is
## freed, and its OWN mesh (the same beam/column, not a stand-in) is
## promoted into an independent RigidBody3D with a matching collision box,
## so it detaches and physically falls/tumbles away rather than being
## deleted and replaced by debris spawned elsewhere.
##
## Not engineering-accurate -- reactive to the generated topology (taller
## structures visibly sway and fail more at the top) rather than a real
## stiffness/stress model. Known limitation: near the top of the thesis's
## own range (10 floors x 10x10 bays, ~1300 nodes / 3000+ joints) real-time
## physics gets noticeably heavier; not artificially capped here, just
## disclosed.

const NODE_RADIUS := 0.35
const MEMBER_THICKNESS := 0.15
const COLUMN_COLOR := Color(0.19, 0.32, 0.55)
const BEAM_COLOR := Color(0.6, 0.65, 0.72)
const ANGULAR_LIMIT := 0.06981317008  # 4 degrees, in radians -- stiff but not welded
const ANGULAR_STIFFNESS := 160.0
const ANGULAR_DAMPING := 12.0
const STRUCTURE_LAYER := 4

const FAILURE_MAGNITUDE_THRESHOLD := 7.0  # below this, nothing ever breaks
const FAILURE_RATE := 0.15  # hazard rate/sec at full severity + full height weight
const FALLEN_CLEANUP_Y := -30.0

signal shake_finished
signal structural_failure(count: int)

var shake_table: ShakeTable
var _node_bodies: Dictionary = {}  # Vector3i -> RigidBody3D
var _anchor_offsets: Dictionary = {}  # Vector3i -> Vector3, level-1 nodes only
var _members: Array = []  # MemberVisual, still-attached
var _fallen: Array = []  # RigidBody3D, detached members now falling freely
var _building_height: float = 1.0
var _failure_active: bool = false
var _failure_severity: float = 0.0
var _failure_count: int = 0

func _ready() -> void:
	shake_table = ShakeTable.new()
	shake_table.name = "ShakeTable"
	add_child(shake_table)
	shake_table.shake_finished.connect(_on_table_shake_finished)

func clear() -> void:
	for child in get_children():
		if child == shake_table:
			continue
		remove_child(child)
		child.queue_free()
	_node_bodies.clear()
	_anchor_offsets.clear()
	_members.clear()
	_fallen.clear()
	_failure_active = false
	_failure_count = 0
	if shake_table:
		shake_table.stop()

func build(params: Dictionary) -> Dictionary:
	clear()
	var topo := StructureGenerator.generate(params)
	var nodes: Dictionary = topo["nodes"]

	var footprint_x: float = float(params["bay_count_x"]) * float(params["bay_width_x"])
	var footprint_z: float = float(params["bay_count_y"]) * float(params["bay_width_y"])
	var story_height: float = params["story_height"]
	_building_height = max(float(params["floor_count"]) * story_height, 0.01)
	# Platform top sits at level 1 (first visible floor); its block fully
	# encloses the ground-story columns below, so the "foundation" reads as
	# buried inside a solid pedestal instead of floating struts at grade.
	# Configure the table BEFORE spawning bodies so anchor offsets below are
	# computed against its final position, not whatever it was left at.
	shake_table.configure(footprint_x / 2.0, footprint_z / 2.0, footprint_x, footprint_z, story_height, story_height)

	for key: Vector3i in nodes.keys():
		if key.x == 0:
			continue  # buried -- no body, no joint; level 1 above it is the real anchor
		var is_anchor: bool = key.x == 1
		var body := _make_node_body(key, nodes[key], is_anchor)
		_node_bodies[key] = body
		if is_anchor:
			_anchor_offsets[key] = nodes[key] - shake_table.position

	var columns: Array = topo["columns"]
	var beams: Array = topo["beams"]
	for pair in columns:
		_add_member(pair[0], pair[1], nodes[pair[0]], nodes[pair[1]], COLUMN_COLOR)
	for pair in beams:
		_add_member(pair[0], pair[1], nodes[pair[0]], nodes[pair[1]], BEAM_COLOR)

	return {
		"node_count": nodes.size(),
		"column_count": columns.size(),
		"beam_count": beams.size(),
	}

func start_shake(magnitude: float, duration: float) -> void:
	shake_table.start(magnitude, duration)
	_failure_active = magnitude >= FAILURE_MAGNITUDE_THRESHOLD
	_failure_severity = clamp(
		(magnitude - FAILURE_MAGNITUDE_THRESHOLD) / (10.0 - FAILURE_MAGNITUDE_THRESHOLD), 0.0, 1.0
	)

func stop_shake() -> void:
	shake_table.stop()
	_failure_active = false

func _on_table_shake_finished() -> void:
	_failure_active = false
	shake_finished.emit()

func _physics_process(delta: float) -> void:
	var ground_pos := shake_table.global_position + shake_table.get_ground_offset()
	for key in _anchor_offsets.keys():
		var body: RigidBody3D = _node_bodies.get(key)
		if body and is_instance_valid(body):
			body.global_position = ground_pos + _anchor_offsets[key]

	if _failure_active:
		_evaluate_failures(delta)

	_cleanup_fallen()

func _process(_delta: float) -> void:
	for visual in _members:
		if not is_instance_valid(visual):
			continue
		var body_a: Node3D = visual.get_meta("body_a")
		var body_b: Node3D = visual.get_meta("body_b")
		if is_instance_valid(body_a) and is_instance_valid(body_b):
			visual.update_between(body_a.global_position, body_b.global_position)

func _make_node_body(key: Vector3i, pos: Vector3, frozen: bool) -> RigidBody3D:
	var body := RigidBody3D.new()
	body.gravity_scale = 0.0
	body.mass = 40.0
	body.linear_damp = 2.5
	body.angular_damp = 2.5
	body.can_sleep = false
	body.collision_layer = STRUCTURE_LAYER
	body.collision_mask = 0
	body.position = pos
	body.set_meta("node_key", key)
	if frozen:
		body.freeze = true
		body.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = NODE_RADIUS
	shape.shape = sphere
	body.add_child(shape)
	add_child(body)
	return body

func _add_member(key_a: Vector3i, key_b: Vector3i, pos_a: Vector3, pos_b: Vector3, color: Color) -> void:
	if key_a.x == 0:
		return  # buried ground-story column -- level 1 above is already pinned, nothing to connect

	var body_a: RigidBody3D = _node_bodies[key_a]
	var body_b: RigidBody3D = _node_bodies[key_b]

	var joint := Generic6DOFJoint3D.new()
	add_child(joint)
	joint.global_position = (pos_a + pos_b) * 0.5
	joint.node_a = joint.get_path_to(body_a)
	joint.node_b = joint.get_path_to(body_b)
	_configure_joint(joint)

	var height_factor: float = clamp(((pos_a.y + pos_b.y) * 0.5) / _building_height, 0.0, 1.0)

	var visual := MemberVisual.new()
	visual.setup(color, MEMBER_THICKNESS)
	add_child(visual)
	visual.update_between(pos_a, pos_b)
	visual.set_meta("body_a", body_a)
	visual.set_meta("body_b", body_b)
	visual.set_meta("joint", joint)
	visual.set_meta("height_factor", height_factor)
	_members.append(visual)

func _configure_joint(joint: Generic6DOFJoint3D) -> void:
	_configure_axis(joint.set_flag_x, joint.set_param_x)
	_configure_axis(joint.set_flag_y, joint.set_param_y)
	_configure_axis(joint.set_flag_z, joint.set_param_z)

func _configure_axis(set_flag: Callable, set_param: Callable) -> void:
	set_flag.call(Generic6DOFJoint3D.FLAG_ENABLE_LINEAR_LIMIT, true)
	set_param.call(Generic6DOFJoint3D.PARAM_LINEAR_LOWER_LIMIT, 0.0)
	set_param.call(Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT, 0.0)
	set_flag.call(Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_LIMIT, true)
	set_param.call(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT, -ANGULAR_LIMIT)
	set_param.call(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT, ANGULAR_LIMIT)
	set_flag.call(Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_SPRING, true)
	set_param.call(Generic6DOFJoint3D.PARAM_ANGULAR_SPRING_STIFFNESS, ANGULAR_STIFFNESS)
	set_param.call(Generic6DOFJoint3D.PARAM_ANGULAR_SPRING_DAMPING, ANGULAR_DAMPING)

func _evaluate_failures(delta: float) -> void:
	var to_break: Array = []
	for visual in _members:
		if not is_instance_valid(visual):
			continue
		var height_factor: float = visual.get_meta("height_factor", 0.5)
		var hazard := FAILURE_RATE * _failure_severity * (0.35 + 0.65 * height_factor)
		if randf() < hazard * delta:
			to_break.append(visual)
	for visual in to_break:
		_break_member(visual)

func _break_member(visual: MemberVisual) -> void:
	if not is_instance_valid(visual):
		return
	var joint: Generic6DOFJoint3D = visual.get_meta("joint")

	_members.erase(visual)
	if is_instance_valid(joint):
		joint.queue_free()

	_drop_member(visual)

	_failure_count += 1
	structural_failure.emit(_failure_count)

## Promotes the broken member's OWN mesh into a free-falling RigidBody3D --
## the same beam/column keeps its exact shape, color and current pose, it
## just stops being driven by update_between() and starts falling under
## real gravity instead.
func _drop_member(visual: MemberVisual) -> void:
	var world_xform := visual.global_transform
	var length := visual.current_length()
	if length <= 0.001:
		visual.queue_free()
		return

	var debris := RigidBody3D.new()
	debris.mass = max(length * 4.0, 4.0)
	debris.linear_damp = 0.2
	debris.angular_damp = 0.3
	debris.collision_layer = STRUCTURE_LAYER
	debris.collision_mask = STRUCTURE_LAYER  # can land on the platform / pile against the frame
	add_child(debris)
	debris.global_transform = world_xform
	debris.angular_velocity = Vector3(randf_range(-2.0, 2.0), randf_range(-2.0, 2.0), randf_range(-2.0, 2.0))

	var shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = Vector3(MEMBER_THICKNESS, MEMBER_THICKNESS, length)
	shape.shape = box_shape
	debris.add_child(shape)

	visual.get_parent().remove_child(visual)
	debris.add_child(visual)
	visual.transform = Transform3D.IDENTITY

	_fallen.append(debris)

func _cleanup_fallen() -> void:
	for i in range(_fallen.size() - 1, -1, -1):
		var piece = _fallen[i]
		if not is_instance_valid(piece):
			_fallen.remove_at(i)
			continue
		if piece.global_position.y < FALLEN_CLEANUP_Y:
			piece.queue_free()
			_fallen.remove_at(i)
