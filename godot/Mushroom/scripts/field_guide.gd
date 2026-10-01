extends "res://scripts/prop.gd"
## The field guide: the one book that lists what Babka Hela has told you. Only whoever is
## holding it can read it (J), so everyone else has to listen to them describe mushrooms.

const SIZE := Vector3(0.32, 0.08, 0.42)

var display_name := "Field guide (J to read)"


func build() -> void:
	var mesh := BoxMesh.new()
	mesh.size = SIZE
	var shape := BoxShape3D.new()
	shape.size = SIZE
	setup("FIELD_GUIDE", mesh, shape, Color(0.55, 0.12, 0.1), 0.6)
	var stripe := MeshInstance3D.new()
	var stripe_mesh := BoxMesh.new()
	stripe_mesh.size = Vector3(SIZE.x + 0.004, SIZE.y * 0.3, SIZE.z * 0.95)
	stripe.mesh = stripe_mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.95, 0.9, 0.75)
	stripe.material_override = mat
	add_child(stripe)
	var title := Label3D.new()
	title.text = "ATLAS HÚB"
	title.font_size = 24
	title.pixel_size = 0.004
	title.rotation.x = -PI / 2.0
	title.position.y = SIZE.y / 2.0 + 0.002
	title.modulate = Color(1, 0.85, 0.3)
	add_child(title)


## The book stays where you left it between days.
func reset_to_home() -> void:
	if position.y < -10.0:
		super.reset_to_home()
