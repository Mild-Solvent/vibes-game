extends Area3D
## A trap in the forest: a bear trap, a patch of sucking mud, or a hole. All of them sit visibly
## on top of the ground: pay attention and you'll walk round them.
## - Bear trap / mud: you're stuck until you win the escape minigame or a friend pulls you out.
## - Hole: there's a warning sign and a skull. Fall in anyway and only a friend with a rope
##   (Jano's shop) can get you out.
## The host springs it; every peer sees the same trap.

const Terrain := preload("res://scripts/world/terrain.gd")
const REARM_SECONDS := 20.0

var kind := "bear trap"
var _armed_at := 0.0


func build(trap_kind: String, at: Vector3) -> void:
	kind = trap_kind
	var radius: float = {"bear trap": 0.6, "mud": 1.8, "hole": 1.3}[kind]
	# Sit on the highest ground under the trap, so it's never buried on a slope.
	var top := at.y
	for i in 8:
		var a := i * TAU / 8.0
		top = maxf(top, Terrain.height(at.x + cos(a) * radius, at.z + sin(a) * radius))
	position = Vector3(at.x, top, at.z)
	var shape := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = radius * (0.9 if kind == "hole" else 1.0)
	cyl.height = 1.2
	shape.shape = cyl
	shape.position.y = 0.6
	add_child(shape)
	match kind:
		"bear trap":
			_build_bear_trap()
		"mud":
			_build_mud(radius)
		"hole":
			_build_hole(radius)
	body_entered.connect(_on_body_entered)


func _build_bear_trap() -> void:
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color(0.5, 0.47, 0.42)
	metal.metallic = 0.7
	metal.roughness = 0.35
	var plate := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 0.22
	disc.bottom_radius = 0.26
	disc.height = 0.06
	plate.mesh = disc
	plate.material_override = metal
	plate.position.y = 0.04
	add_child(plate)
	for side in [-1.0, 1.0]:
		var jaw := MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.inner_radius = 0.36
		torus.outer_radius = 0.44
		torus.rings = 14
		torus.ring_segments = 5
		jaw.mesh = torus
		jaw.material_override = metal
		jaw.rotation.z = side * 0.45
		jaw.position.y = 0.12
		add_child(jaw)
		for t in 6:  # teeth
			var tooth := MeshInstance3D.new()
			var cone := CylinderMesh.new()
			cone.top_radius = 0.0
			cone.bottom_radius = 0.035
			cone.height = 0.1
			tooth.mesh = cone
			tooth.material_override = metal
			var a := -1.2 + t * 0.48
			tooth.position = Vector3(sin(a) * 0.4, 0.2 + side * 0.04, cos(a) * 0.4 * side)
			add_child(tooth)


func _build_mud(radius: float) -> void:
	var wet := StandardMaterial3D.new()
	wet.albedo_color = Color(0.2, 0.14, 0.08)
	wet.roughness = 0.08
	wet.metallic = 0.15
	var puddle := MeshInstance3D.new()
	var blob := SphereMesh.new()
	blob.radius = radius
	blob.height = radius * 0.22
	blob.radial_segments = 14
	blob.rings = 4
	puddle.mesh = blob
	puddle.material_override = wet
	puddle.position.y = 0.03
	add_child(puddle)
	var ring_mat := StandardMaterial3D.new()
	ring_mat.albedo_color = Color(0.12, 0.09, 0.05)
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = radius * 0.95
	torus.outer_radius = radius * 1.18
	torus.rings = 18
	torus.ring_segments = 4
	ring.mesh = torus
	ring.material_override = ring_mat
	ring.scale.y = 0.25
	ring.position.y = 0.04
	add_child(ring)
	var bubble_mat := StandardMaterial3D.new()
	bubble_mat.albedo_color = Color(0.32, 0.25, 0.15)
	bubble_mat.roughness = 0.05
	for i in 5:
		var bubble := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = 0.06 + 0.03 * (i % 2)
		sphere.height = sphere.radius * 1.6
		bubble.mesh = sphere
		bubble.material_override = bubble_mat
		var a := i * 1.3
		bubble.position = Vector3(cos(a) * radius * 0.5, radius * 0.11, sin(a) * radius * 0.45)
		add_child(bubble)
	_flies()


func _build_hole(radius: float) -> void:
	var black := StandardMaterial3D.new()
	black.albedo_color = Color(0.01, 0.01, 0.01)
	black.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var pit := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = radius
	disc.bottom_radius = radius
	disc.height = 0.02
	disc.radial_segments = 16
	pit.mesh = disc
	pit.material_override = black
	pit.position.y = 0.03
	add_child(pit)
	var stone := StandardMaterial3D.new()
	stone.albedo_color = Color(0.45, 0.43, 0.4)
	for i in 10:
		var rock := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.35, 0.25, 0.3)
		rock.mesh = box
		rock.material_override = stone
		var a := i * TAU / 10.0
		rock.position = Vector3(cos(a) * (radius + 0.15), 0.12, sin(a) * (radius + 0.15))
		rock.rotation.y = a
		add_child(rock)
	# The warning sign, with a skull on a stick next to it.
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.42, 0.3, 0.18)
	var post := MeshInstance3D.new()
	var pole := BoxMesh.new()
	pole.size = Vector3(0.1, 1.6, 0.1)
	post.mesh = pole
	post.material_override = wood
	post.position = Vector3(radius + 0.9, 0.8, 0)
	add_child(post)
	var board := MeshInstance3D.new()
	var plank := BoxMesh.new()
	plank.size = Vector3(1.1, 0.45, 0.05)
	board.mesh = plank
	board.material_override = wood
	board.position = Vector3(radius + 0.9, 1.45, 0)
	add_child(board)
	for side in [1.0, -1.0]:
		var label := Label3D.new()
		label.text = "DIERA!\n(HOLE)"
		label.font_size = 40
		label.pixel_size = 0.005
		label.modulate = Color(0.9, 0.15, 0.1)
		label.position = Vector3(radius + 0.9, 1.45, 0.03 * side)
		label.rotation.y = 0.0 if side > 0.0 else PI
		add_child(label)
	var bone := StandardMaterial3D.new()
	bone.albedo_color = Color(0.92, 0.9, 0.82)
	var skull := MeshInstance3D.new()
	var head := SphereMesh.new()
	head.radius = 0.16
	head.height = 0.3
	skull.mesh = head
	skull.material_override = bone
	skull.position = Vector3(-radius - 0.6, 1.2, 0.3)
	add_child(skull)
	var stick := MeshInstance3D.new()
	var stick_mesh := BoxMesh.new()
	stick_mesh.size = Vector3(0.05, 1.1, 0.05)
	stick.mesh = stick_mesh
	stick.material_override = wood
	stick.position = Vector3(-radius - 0.6, 0.55, 0.3)
	add_child(stick)


## A few flies buzzing over the mud (local animation, not synced).
func _flies() -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.02, 0.02, 0.02)
	for i in 4:
		var fly := MeshInstance3D.new()
		var dot := SphereMesh.new()
		dot.radius = 0.03
		dot.height = 0.06
		fly.mesh = dot
		fly.material_override = mat
		fly.position = Vector3(0, 0.6 + i * 0.12, 0)
		add_child(fly)
		var tween := fly.create_tween().set_loops()
		var r := 0.5 + i * 0.25
		for step in 4:
			var a := step * TAU / 4.0 + i
			tween.tween_property(fly, "position", Vector3(cos(a) * r, 0.5 + randf() * 0.5, sin(a) * r), 0.3 + i * 0.07)


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
	var how := "Someone has to pull them out (E on them), or they wriggle free." if kind != "hole" else \
		"They're down a HOLE. Only a friend with a rope (Jano's) can get them out."
	Team.tell(0, "%s is stuck in a %s! %s" % [Team.players[peer]["name"], kind, how])
	Team.highlight("%s steps in a %s" % [Team.players[peer]["name"], kind])
