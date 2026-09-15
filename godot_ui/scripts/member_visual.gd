class_name MemberVisual
extends MeshInstance3D

## A thin box mesh that re-orients and re-stretches itself between two live
## world points every call to update_between(). Used to draw a beam/column
## between its two node bodies each frame.

var thickness: float = 0.15

func setup(color: Color, thickness_value: float) -> void:
	thickness = thickness_value
	mesh = BoxMesh.new()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	material_override = mat

func update_between(a: Vector3, b: Vector3) -> void:
	var diff := b - a
	var length := diff.length()
	if length < 0.001:
		return
	global_position = (a + b) * 0.5
	var dir := diff / length
	var up := Vector3.UP
	if abs(dir.dot(up)) > 0.999:
		up = Vector3.FORWARD
	look_at(global_position + dir, up)
	if mesh is BoxMesh:
		(mesh as BoxMesh).size = Vector3(thickness, thickness, length)

func current_length() -> float:
	if mesh is BoxMesh:
		return (mesh as BoxMesh).size.z
	return 0.0
