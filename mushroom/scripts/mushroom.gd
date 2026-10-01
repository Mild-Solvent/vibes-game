extends "res://scripts/prop.gd"
## A mushroom you can pick, carry to the basket, or taste (F while holding it).
## Every edible kind has a poisonous look-alike. Tasting a bad one makes you "see things".

signal tasted(peer_id: int, edible: bool)

## kind: [edible, points, cap colour, stem colour, cap radius, stem height, stem radius, display name]
const KINDS := {
	"porcini": [true, 10, Color(0.45, 0.28, 0.12), Color(0.9, 0.85, 0.7), 0.16, 0.14, 0.06, "Porcini (hríb)"],
	"satans_bolete": [false, -15, Color(0.6, 0.55, 0.48), Color(0.75, 0.3, 0.22), 0.16, 0.14, 0.06, "Satan's bolete"],
	"parasol": [true, 8, Color(0.8, 0.72, 0.58), Color(0.7, 0.6, 0.5), 0.22, 0.35, 0.03, "Parasol (bedľa)"],
	"death_cap": [false, -20, Color(0.78, 0.82, 0.62), Color(0.92, 0.92, 0.88), 0.14, 0.24, 0.035, "Death cap"],
	"chanterelle": [true, 5, Color(1.0, 0.75, 0.2), Color(1.0, 0.8, 0.35), 0.08, 0.07, 0.03, "Chanterelle (kuriatko)"],
	"false_chanterelle":
	[false, -8, Color(1.0, 0.55, 0.12), Color(1.0, 0.6, 0.2), 0.08, 0.07, 0.03, "False chanterelle"],
}

var kind := "porcini"
var edible := true
var points := 0
var display_name := ""


func setup_mushroom(prop_name: String, mushroom_kind: String) -> void:
	kind = mushroom_kind
	var k: Array = KINDS[kind]
	edible = k[0]
	points = k[1]
	display_name = k[7]
	var cap_radius: float = k[4]
	var stem_height: float = k[5]
	var stem_radius: float = k[6]

	var stem := CylinderMesh.new()
	stem.top_radius = stem_radius
	stem.bottom_radius = stem_radius * 1.2
	stem.height = stem_height
	var shape := BoxShape3D.new()
	shape.size = Vector3(cap_radius * 2.0, stem_height + cap_radius * 0.6, cap_radius * 2.0)
	setup(prop_name, stem, shape, k[3], 0.2)

	var cap_mesh := SphereMesh.new()
	cap_mesh.radius = cap_radius
	cap_mesh.height = cap_radius * 1.1
	cap_mesh.is_hemisphere = true
	var cap := MeshInstance3D.new()
	cap.mesh = cap_mesh
	cap.position.y = stem_height / 2.0
	var mat := StandardMaterial3D.new()
	mat.albedo_color = k[2]
	cap.material_override = mat
	add_child(cap)


## Holder only. The mushroom is eaten either way.
@rpc("any_peer", "call_local", "reliable")
func request_taste() -> void:
	if not multiplayer.is_server() or removed:
		return
	var sender := _sender_id()
	if sender != holder_id:
		return
	remove_from_play()
	tasted.emit(sender, edible)
	_tasted.rpc_id(sender, edible, display_name)


@rpc("authority", "call_local", "reliable")
func _tasted(was_edible: bool, mushroom_name: String) -> void:
	get_tree().call_group("hud", "on_tasted", was_edible, mushroom_name)
