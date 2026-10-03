class_name MemberVisual
extends MeshInstance3D

static var _mesh_cache: Dictionary = {}
static var _material_cache: Dictionary = {}

static func clear_caches() -> void:
	_mesh_cache.clear()
	_material_cache.clear()

static func _i_profile_mesh(section: Dictionary, length: float) -> Mesh:
	var key := "%s|%.4f" % [section["name"], length]
	if _mesh_cache.has(key):
		return _mesh_cache[key]
	var d: float = section["d_m"]
	var bf: float = section["bf_m"]
	var tf: float = section["tf_m"]
	var tw: float = section["tw_m"]
	var plates := [
		[Vector3(bf, tf, length), Vector3(0.0, d / 2.0 - tf / 2.0, 0.0)],
		[Vector3(bf, tf, length), Vector3(0.0, -d / 2.0 + tf / 2.0, 0.0)],
		[Vector3(tw, d - 2.0 * tf, length), Vector3.ZERO],
	]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for plate in plates:
		var box := BoxMesh.new()
		box.size = plate[0]
		st.append_from(box, 0, Transform3D(Basis.IDENTITY, plate[1]))
	var mesh := st.commit()
	_mesh_cache[key] = mesh
	return mesh

static func _material(color: Color) -> StandardMaterial3D:
	var key := color.to_html()
	if _material_cache.has(key):
		return _material_cache[key]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	_material_cache[key] = mat
	return mat

var _base_length: float = 0.0
var _depth_hint: Vector3 = Vector3.UP

func setup(color: Color, a: Vector3, b: Vector3, section: Dictionary, depth_hint: Vector3) -> void:
	var length := (b - a).length()
	if length < 0.001:
		return
	_base_length = length
	_depth_hint = depth_hint
	mesh = _i_profile_mesh(section, length)
	material_override = _material(color)
	place(a, b)

func place(a: Vector3, b: Vector3) -> void:
	var diff := b - a
	var length := diff.length()
	if length < 0.001 or _base_length <= 0.0:
		return
	var axis := diff / length
	var depth_axis := (_depth_hint - axis * _depth_hint.dot(axis))
	if depth_axis.length() < 0.001:
		depth_axis = Vector3.UP if abs(axis.dot(Vector3.UP)) < 0.999 else Vector3.RIGHT
		depth_axis = (depth_axis - axis * depth_axis.dot(axis))
	depth_axis = depth_axis.normalized()
	var width_axis := depth_axis.cross(axis).normalized()
	transform = Transform3D(Basis(width_axis, depth_axis, axis * (length / _base_length)), (a + b) * 0.5)

func set_color(color: Color) -> void:
	material_override = _material(color)
