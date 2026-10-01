extends Area3D
## A bear trap or a patch of sucking mud in the forest. Step in and you're stuck until a friend
## pulls you out (E on you). The host springs it; every peer sees the same trap.

const Terrain := preload("res://scripts/world/terrain.gd")
const REARM_SECONDS := 20.0

var kind := "bear trap"
var _armed_at := 0.0


func build(trap_kind: String, at: Vector3) -> void:
	kind = trap_kind
	position = at
	var shape := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 0.6 if kind == "bear trap" else 1.8
	cyl.height = 1.0
	shape.shape = cyl
	shape.position.y = 0.5
	add_child(shape)
	if kind == "bear trap":
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.35, 0.33, 0.3)
		mat.metallic = 0.6
		mat.roughness = 0.5
		for side in [-1.0, 1.0]:
			var jaw := MeshInstance3D.new()
			var torus := TorusMesh.new()
			torus.inner_radius = 0.26
			torus.outer_radius = 0.32
			torus.rings = 12
			torus.ring_segments = 4
			jaw.mesh = torus
			jaw.material_override = mat
			jaw.rotation.z = side * 0.35
			jaw.position.y = 0.05
			add_child(jaw)
	else:
		var mud := MeshInstance3D.new()
		var disc := CylinderMesh.new()
		disc.top_radius = 1.9
		disc.bottom_radius = 1.9
		disc.height = 0.05
		disc.radial_segments = 10
		mud.mesh = disc
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.22, 0.16, 0.1)
		mat.roughness = 0.2
		mud.material_override = mat
		mud.position.y = 0.03
		add_child(mud)
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node) -> void:
	if not multiplayer.is_server() or not body.is_in_group("players"):
		return
	var now := Time.get_ticks_msec() / 1000.0
	var peer: int = body.peer_id
	if now < _armed_at or not Team.is_alive(peer) or Team.stuck_in(peer) != "" or body.in_car():
		return
	_armed_at = now + REARM_SECONDS
	Team.set_stuck(peer, kind)
	Sfx.play_all("metal_hit" if kind == "bear trap" else "splash", global_position)
	Hearing.emit(global_position, 25.0, peer)
	Team.tell(0, "%s is stuck in a %s! Someone has to pull them out (E on them)." % [
		Team.players[peer]["name"], kind])
