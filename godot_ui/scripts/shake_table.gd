class_name ShakeTable
extends AnimatableBody3D

## The visual ground plate. Its own transform is set once by configure()
## and never touched again -- it stays visually identical to the static
## structure view's platform at all times, including mid-shake, so the two
## previews can never look like they're sitting on different foundations.
##
## The "shake" itself is a ground-motion SIGNAL (get_ground_offset()), not
## a movement of this node: StructureView reads that offset each physics
## step and applies it only to the structure's base-anchored bodies, so the
## building visibly sways relative to a platform that never itself moves.
## An earlier version moved this node directly, which meant the platform
## visibly slid out from under the structure mid-shake -- fixed by this
## split. Not engineering-accurate; a heuristic sine-sweep sized off
## Magnitude/Duration for a v1 visual demo.

signal shake_finished

const STRUCTURE_LAYER := 4

var _rest_position: Vector3 = Vector3.ZERO
var _shaking: bool = false
var _elapsed: float = 0.0
var _duration: float = 0.0
var _amplitude: float = 0.0
var _frequency: float = 1.8
var _ground_offset: Vector3 = Vector3.ZERO

var _collision_shape: CollisionShape3D
var _mesh_instance: MeshInstance3D

func _ready() -> void:
	sync_to_physics = true
	collision_layer = STRUCTURE_LAYER
	collision_mask = 0
	_rest_position = position

	_collision_shape = CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = Vector3(10.0, 0.4, 10.0)
	_collision_shape.shape = box_shape
	add_child(_collision_shape)

	_mesh_instance = MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = Vector3(10.0, 0.2, 10.0)
	_mesh_instance.mesh = box_mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.82, 0.85, 0.89)
	_mesh_instance.material_override = mat
	add_child(_mesh_instance)

func configure(center_x: float, center_z: float, size_x: float, size_z: float, top_y: float, thickness: float) -> void:
	var margin := 3.0
	var sx: float = max(size_x + margin, 2.0)
	var sz: float = max(size_z + margin, 2.0)
	var sy: float = max(thickness, 0.4)
	(_collision_shape.shape as BoxShape3D).size = Vector3(sx, sy, sz)
	(_mesh_instance.mesh as BoxMesh).size = Vector3(sx, sy, sz)
	position = Vector3(center_x, top_y - sy / 2.0, center_z)
	_rest_position = position

func start(magnitude: float, duration: float) -> void:
	# Heuristic placeholder curve, not derived from real seismology: bigger
	# magnitude -> exponentially bigger sway, clamped so it stays legible.
	_amplitude = clamp(0.01 * pow(1.6, magnitude), 0.01, 1.2)
	_frequency = 1.6 + randf() * 0.6
	_duration = max(duration, 1.0)
	_elapsed = 0.0
	_shaking = true

func stop() -> void:
	_shaking = false
	_elapsed = 0.0
	_ground_offset = Vector3.ZERO

func get_ground_offset() -> Vector3:
	return _ground_offset

func _physics_process(delta: float) -> void:
	if not _shaking:
		return
	_elapsed += delta
	if _elapsed >= _duration:
		stop()
		shake_finished.emit()
		return
	var envelope := _envelope(_elapsed, _duration)
	var offset_x := _amplitude * envelope * sin(TAU * _frequency * _elapsed)
	var offset_z := _amplitude * envelope * 0.6 * sin(TAU * _frequency * 0.8 * _elapsed + PI / 3.0)
	_ground_offset = Vector3(offset_x, 0.0, offset_z)

func _envelope(t: float, duration: float) -> float:
	var attack: float = min(duration * 0.15, 1.5)
	var release_start: float = duration * 0.75
	if t < attack:
		return t / attack
	elif t > release_start:
		return max(0.0, 1.0 - (t - release_start) / (duration - release_start))
	return 1.0
