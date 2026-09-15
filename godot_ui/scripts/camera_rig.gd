class_name FreeCamera
extends Camera3D

## Implements the camera controls already promised by the legend built in
## main.gd's _build_app_view(): WASD fly, C/Space down/up, scroll to
## dolly, right-click-drag to look around, left-click to inspect a grid
## node (raycast against the physics bodies structure_view.gd already
## created for the shake simulation, so picking is effectively free).
##
## WASD/C/Space/right-drag are all polled in _process (not input events) so
## they work regardless of SubViewport input-forwarding edge cases; only the
## momentary wheel/click events go through _unhandled_input.

signal member_inspected(text: String)

## Only the camera in the currently "big" preview pane should respond to
## input -- with two cameras live at once (structure + simulation panes),
## an inactive one must ignore WASD/mouse entirely so it doesn't drift or
## steal clicks while it's just a small background preview.
@export var active: bool = true

@export var move_speed: float = 10.0
@export var boost_multiplier: float = 3.0
@export var look_sensitivity: float = 0.005
@export var zoom_speed: float = 1.5
@export var pick_mask: int = 4

var _yaw: float = 0.0
var _pitch: float = 0.0
var _last_mouse_pos: Vector2 = Vector2.ZERO
var _has_last_mouse: bool = false

func _ready() -> void:
	_yaw = rotation.y
	_pitch = rotation.x

## Copies another camera's transform verbatim (used so the simulation
## preview starts from wherever you were just looking at the structure
## preview, instead of snapping back to a generic default angle). Also
## re-syncs the internal yaw/pitch tracking, or the next right-drag would
## snap the view back to the old orientation.
func copy_from(other: Camera3D) -> void:
	global_transform = other.global_transform
	_yaw = rotation.y
	_pitch = rotation.x

func _process(delta: float) -> void:
	_update_look()
	_update_move(delta)

func _update_look() -> void:
	var vp := get_viewport()
	if vp == null:
		return
	var mouse_pos: Vector2 = vp.get_mouse_position()
	if active and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		if _has_last_mouse:
			var mouse_delta: Vector2 = mouse_pos - _last_mouse_pos
			_yaw -= mouse_delta.x * look_sensitivity
			_pitch -= mouse_delta.y * look_sensitivity
			_pitch = clamp(_pitch, deg_to_rad(-85.0), deg_to_rad(85.0))
			rotation = Vector3(_pitch, _yaw, 0.0)
		_has_last_mouse = true
	else:
		_has_last_mouse = false
	_last_mouse_pos = mouse_pos

func _update_move(delta: float) -> void:
	if not active:
		return
	var dir := Vector3.ZERO
	if Input.is_key_pressed(KEY_W):
		dir -= transform.basis.z
	if Input.is_key_pressed(KEY_S):
		dir += transform.basis.z
	if Input.is_key_pressed(KEY_A):
		dir -= transform.basis.x
	if Input.is_key_pressed(KEY_D):
		dir += transform.basis.x
	if Input.is_key_pressed(KEY_SPACE):
		dir += Vector3.UP
	if Input.is_key_pressed(KEY_C):
		dir -= Vector3.UP
	if dir.length_squared() > 0.0:
		var speed := move_speed
		if Input.is_key_pressed(KEY_SHIFT):
			speed *= boost_multiplier
		global_position += dir.normalized() * speed * delta

func _unhandled_input(event: InputEvent) -> void:
	if not active:
		return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			translate_object_local(Vector3(0.0, 0.0, -zoom_speed))
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			translate_object_local(Vector3(0.0, 0.0, zoom_speed))
		elif event.button_index == MOUSE_BUTTON_LEFT:
			_inspect_at(event.position)

func _inspect_at(screen_pos: Vector2) -> void:
	var world := get_world_3d()
	if world == null:
		return
	var space_state := world.direct_space_state
	var from: Vector3 = project_ray_origin(screen_pos)
	var to: Vector3 = from + project_ray_normal(screen_pos) * 1000.0
	var query := PhysicsRayQueryParameters3D.create(from, to, pick_mask)
	var result := space_state.intersect_ray(query)
	if result.is_empty():
		return
	var collider: Object = result["collider"]
	if collider.has_meta("node_key"):
		var key: Vector3i = collider.get_meta("node_key")
		member_inspected.emit("selected grid node -- level %d, row %d, col %d" % [key.x, key.y, key.z])
	else:
		member_inspected.emit("selected the base / shake table")
