class_name ViewCube
extends Control

signal face_pressed(normal: Vector3)

const FACES := [
	{"normal": Vector3(0, 0, 1), "label": "+X", "color": Color("#e5484d")},
	{"normal": Vector3(0, 0, -1), "label": "−X", "color": Color("#9b2c2f")},
	{"normal": Vector3(-1, 0, 0), "label": "+Y", "color": Color("#30a46c")},
	{"normal": Vector3(1, 0, 0), "label": "−Y", "color": Color("#1d6b45")},
	{"normal": Vector3(0, 1, 0), "label": "+Z", "color": Color("#3e63dd")},
	{"normal": Vector3(0, -1, 0), "label": "−Z", "color": Color("#273f8f")},
]
const ARROW_COLOR := Color("#155dfc")

var camera: Camera3D
var label_font: Font
var _last_basis: Basis = Basis()
var _polygons: Array = []
var _arrows: Array = []
var _hovered: int = -1
var _hovered_arrow: int = -1

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

func _process(_delta: float) -> void:
	if camera == null:
		return
	var basis := camera.global_transform.basis
	if not basis.is_equal_approx(_last_basis):
		_last_basis = basis
		queue_redraw()

func _project(point: Vector3, basis: Basis, center: Vector2, scale: float) -> Vector2:
	var view := basis.transposed() * point
	return center + Vector2(view.x, -view.y) * scale

func _snap_axis(direction: Vector3) -> Vector3:
	var a := direction.abs()
	if a.x >= a.y and a.x >= a.z:
		return Vector3(signf(direction.x), 0, 0)
	if a.y >= a.z:
		return Vector3(0, signf(direction.y), 0)
	return Vector3(0, 0, signf(direction.z))

func _draw() -> void:
	_polygons.clear()
	_arrows.clear()
	if camera == null:
		return
	var basis := camera.global_transform.basis.orthonormalized()
	var center := size / 2.0
	var scale: float = min(size.x, size.y) * 0.28
	for i in range(FACES.size()):
		var face: Dictionary = FACES[i]
		var normal: Vector3 = face["normal"]
		var facing := normal.dot(basis.z)
		if facing <= 0.001:
			continue
		var u := Vector3(normal.y, normal.z, normal.x)
		var w := normal.cross(u)
		var corners := PackedVector2Array()
		for offset in [u + w, -u + w, -u - w, u - w]:
			corners.append(_project(normal + offset, basis, center, scale))
		_polygons.append({"index": i, "points": corners})
		var color: Color = face["color"]
		color = color.darkened(0.35 * (1.0 - facing))
		if i == _hovered:
			color = color.lightened(0.25)
		draw_colored_polygon(corners, color)
		var outline := corners.duplicate()
		outline.append(corners[0])
		draw_polyline(outline, Color(1, 1, 1, 0.85), 1.5, true)
		if facing > 0.3 and label_font != null:
			var font_size := int(round(scale * 0.55))
			var text: String = face["label"]
			var text_size := label_font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
			var middle := _project(normal, basis, center, scale)
			var origin := middle + Vector2(-text_size.x / 2.0, text_size.y / 4.0)
			draw_string(label_font, origin, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(1, 1, 1, clamp(facing * 1.4, 0.0, 1.0)))
	if _polygons.size() == 1:
		_draw_arrows(basis, center, scale)

func _draw_arrows(basis: Basis, center: Vector2, scale: float) -> void:
	var reach: float = scale + (min(size.x, size.y) / 2.0 - scale) / 2.0
	var half := 7.0
	var length := 8.0
	var directions := [
		[Vector2(0, -1), basis.y],
		[Vector2(0, 1), -basis.y],
		[Vector2(-1, 0), -basis.x],
		[Vector2(1, 0), basis.x],
	]
	for i in range(directions.size()):
		var screen: Vector2 = directions[i][0]
		var side := Vector2(-screen.y, screen.x)
		var base := center + screen * (reach - length / 2.0)
		var tip := base + screen * length
		var triangle := PackedVector2Array([tip, base + side * half, base - side * half])
		var hit := PackedVector2Array([
			base + side * (half + 5.0) - screen * 5.0,
			tip + side * (half + 5.0) + screen * 4.0,
			tip - side * (half + 5.0) + screen * 4.0,
			base - side * (half + 5.0) - screen * 5.0,
		])
		_arrows.append({"points": hit, "normal": _snap_axis(directions[i][1])})
		var color := ARROW_COLOR.lightened(0.35) if i == _hovered_arrow else ARROW_COLOR
		draw_colored_polygon(triangle, color)

func arrow_normal(direction: String) -> Vector3:
	var basis := camera.global_transform.basis.orthonormalized()
	match direction:
		"up":
			return _snap_axis(basis.y)
		"down":
			return _snap_axis(-basis.y)
		"left":
			return _snap_axis(-basis.x)
	return _snap_axis(basis.x)

func _face_at(point: Vector2) -> int:
	for entry in _polygons:
		if Geometry2D.is_point_in_polygon(point, entry["points"]):
			return int(entry["index"])
	return -1

func _arrow_at(point: Vector2) -> int:
	for i in range(_arrows.size()):
		if Geometry2D.is_point_in_polygon(point, _arrows[i]["points"]):
			return i
	return -1

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var hovered := _face_at(event.position)
		var hovered_arrow := _arrow_at(event.position)
		if hovered != _hovered or hovered_arrow != _hovered_arrow:
			_hovered = hovered
			_hovered_arrow = hovered_arrow
			queue_redraw()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var arrow := _arrow_at(event.position)
		if arrow != -1:
			face_pressed.emit(_arrows[arrow]["normal"])
			accept_event()
			return
		var index := _face_at(event.position)
		if index != -1:
			face_pressed.emit(FACES[index]["normal"])
			accept_event()

func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT and (_hovered != -1 or _hovered_arrow != -1):
		_hovered = -1
		_hovered_arrow = -1
		queue_redraw()
