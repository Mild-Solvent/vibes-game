extends "res://scripts/prop.gd"
## The handheld FIELD CAM: a prop anyone can grab and carry outside. It is also a broadcast
## source, so the director can TAKE it: while someone holds it, it films what they look at;
## lying around, it films whatever its lens points at.

var label := "FIELD CAM"
var fov := 60.0
var on_air := false

var _tally_mat: StandardMaterial3D


## Call after `setup`: the camera body, lens and tally light (the grey box is hidden).
func dress() -> void:
	for child in get_children():
		if child is MeshInstance3D:
			child.visible = false
	var body := BoxMesh.new()
	body.size = Vector3(0.22, 0.24, 0.42)
	_part(body, Vector3.ZERO, Color(0.15, 0.15, 0.17))
	var lens := CylinderMesh.new()
	lens.top_radius = 0.08
	lens.bottom_radius = 0.09
	lens.height = 0.18
	lens.radial_segments = 10
	_part(lens, Vector3(0, 0.0, -0.28), Color(0.08, 0.08, 0.1)).rotation.x = PI / 2.0
	var handle := BoxMesh.new()
	handle.size = Vector3(0.05, 0.05, 0.3)
	_part(handle, Vector3(0, 0.15, 0), Color(0.3, 0.3, 0.32))
	var logo := BoxMesh.new()
	logo.size = Vector3(0.005, 0.1, 0.16)
	_part(logo, Vector3(0.112, 0, 0.05), Color(0.85, 0.1, 0.1))
	var tally := BoxMesh.new()
	tally.size = Vector3(0.06, 0.03, 0.03)
	_tally_mat = _part(tally, Vector3(0, 0.13, -0.18), Color(0.25, 0.05, 0.05)).material_override
	_tally_mat.emission = Color(1, 0.1, 0.1)
	_tally_mat.emission_energy_multiplier = 3.0


func view_transform() -> Transform3D:
	var holder := _find_holder()
	if holder != null:
		# From just in front of the camera in their hands, looking where they look.
		var basis: Basis = holder.head.global_basis
		return Transform3D(basis, holder.hold_point() - basis.z * 0.4)
	return global_transform.translated_local(Vector3(0, 0, -0.4))


func _process(_delta: float) -> void:
	if _tally_mat:
		_tally_mat.emission_enabled = on_air


func _part(mesh: Mesh, pos: Vector3, color: Color) -> MeshInstance3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = pos
	instance.material_override = mat
	add_child(instance)
	return instance
