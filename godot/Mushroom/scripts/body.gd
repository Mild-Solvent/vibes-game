extends "res://scripts/prop.gd"
## A dead friend's body: floppy, heavy, but you can carry it (E), throw it in the car (on the
## roof rack) and haul it to the witch. Built on every peer with the same name when someone
## dies, so it syncs like any prop.

const ModelFit := preload("res://scripts/model_fit.gd")
const PlayerScript := preload("res://scripts/player.gd")
const SIZE := Vector3(0.7, 0.45, 1.7)

var display_name := "Body"
var peer := 0


func build(peer_id: int, variant: int, player_name: String) -> void:
	peer = peer_id
	display_name = "%s (dead)" % player_name
	var mesh := BoxMesh.new()
	mesh.size = SIZE
	var shape := BoxShape3D.new()
	shape.size = SIZE
	setup("Body_%d" % peer_id, mesh, shape, Color(0.5, 0.5, 0.5), 45.0)
	for child in get_children():
		if child is MeshInstance3D:
			child.visible = false
	var path := "res://assets/kenney/mini-characters/character-%s.glb" % PlayerScript.CHARACTERS[variant % PlayerScript.CHARACTERS.size()]
	var model := ModelFit.fit(path, Vector3(1.2, 1.7, 1.2), 0.0)
	var lying := Node3D.new()
	lying.rotation.x = -PI / 2.0
	lying.position = Vector3(0, -SIZE.y / 2.0 + 0.05, 0.85)
	model.position.y += 0.85
	lying.add_child(model)
	add_child(lying)
	var tag := Label3D.new()
	tag.text = "RIP %s" % player_name
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.pixel_size = 0.004
	tag.font_size = 40
	tag.outline_size = 8
	tag.position.y = 0.9
	add_child(tag)


## Every peer: (re)appear where the player fell.
func lay_down(at: Vector3, yaw: float) -> void:
	removed = false
	visible = true
	for child in get_children():
		if child is CollisionShape3D:
			child.set_deferred("disabled", false)
	global_position = at
	rotation = Vector3(0, yaw, 0)


## Every peer: the friend is alive again; the body goes away.
func put_away() -> void:
	if multiplayer.is_server():
		remove_from_play()
	else:
		visible = false


## Bodies stay where they are between days.
func reset_to_home() -> void:
	if position.y < -10.0 and not removed:
		super.reset_to_home()
