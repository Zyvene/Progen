class_name FreeCamera
extends Camera3D

@export var move_speed: float = 10.0
@export var boost_multiplier: float = 3.0
@export var look_sensitivity: float = 0.005
@export var zoom_speed: float = 1.5

var _yaw: float = 0.0
var _pitch: float = 0.0
var _last_mouse_pos: Vector2 = Vector2.ZERO
var _has_last_mouse: bool = false

func _ready() -> void:
	_yaw = rotation.y
	_pitch = rotation.x

func sync_look_from_rotation() -> void:
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
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
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
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			translate_object_local(Vector3(0.0, 0.0, -zoom_speed))
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			translate_object_local(Vector3(0.0, 0.0, zoom_speed))
