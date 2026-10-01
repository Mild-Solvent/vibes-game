extends Area3D
## A trap in the forest, hidden but fair: you can spot every one if you pay attention.
## - Bear trap: hidden in tall grass and ferns, often right next to a mushroom (bait). The steel
##   glints when a torch or the low sun catches it.
## - Mud: a swampy patch in a dip. The ground is a bit darker and wetter, with reeds, cattails and
##   dead wood around it: the "no-no square" a friend can shout about.
## - Hole: an old shaft between boulders, half covered by ferns and branches. Mostly no sign.
##   Only a friend with a rope (Jano's shop) can get you out.
## Bear traps and mud have escape minigames; a friend pressing E frees you instantly.
## The host springs it; every peer builds the same trap (seeded).

const Terrain := preload("res://scripts/world/terrain.gd")
const ModelFit := preload("res://scripts/model_fit.gd")
const NATURE := "res://assets/kenney/nature-kit/"
const REARM_SECONDS := 20.0

var kind := "bear trap"
var radius := 0.6
var _armed_at := 0.0
var _glint: MeshInstance3D
var _rng := RandomNumberGenerator.new()


func build(trap_kind: String, at: Vector3, seed_value := 0) -> void:
	kind = trap_kind
	_rng.seed = seed_value
	radius = {"bear trap": 0.55, "mud": _rng.randf_range(4.0, 6.5), "hole": 1.2}[kind]
	position = at
	var shape := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = radius * (0.8 if kind == "mud" else 0.9)
	cyl.height = 1.2
	shape.shape = cyl
	shape.position.y = 0.6
	add_child(shape)
	match kind:
		"bear trap":
			_build_bear_trap()
		"mud":
			_build_mud()
		"hole":
			_build_hole()
	body_entered.connect(_on_body_entered)


# --- bear trap: in the grass, glints in the light ---------------------------------------------


func _build_bear_trap() -> void:
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color(0.32, 0.3, 0.27)
	metal.metallic = 0.6
	metal.roughness = 0.45
	var jaws := Node3D.new()
	jaws.position.y = -0.04  # half sunk in the leaf litter
	add_child(jaws)
	for side in [-1.0, 1.0]:
		var jaw := MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.inner_radius = 0.3
		torus.outer_radius = 0.36
		torus.rings = 12
		torus.ring_segments = 4
		jaw.mesh = torus
		jaw.material_override = metal
		jaw.rotation.z = side * 0.3
		jaw.position.y = 0.06
		jaws.add_child(jaw)
	# Tall grass and ferns all over it.
	for i in 7:
		var a := i * TAU / 7.0 + _rng.randf()
		var r := _rng.randf_range(0.0, 0.7)
		var model := "grass_large.glb" if i % 3 else "plant_flatTall.glb"
		var tuft := ModelFit.fit(NATURE + model, Vector3(0.9, _rng.randf_range(0.55, 0.9), 0.9), _rng.randf() * TAU)
		tuft.position += Vector3(cos(a) * r, 0.35, sin(a) * r)
		add_child(tuft)
	# The glint: a tiny bright spark, shown only when light catches the steel.
	_glint = MeshInstance3D.new()
	var spark := SphereMesh.new()
	spark.radius = 0.05
	spark.height = 0.1
	_glint.mesh = spark
	var shine := StandardMaterial3D.new()
	shine.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	shine.albedo_color = Color(1, 1, 0.9)
	shine.emission_enabled = true
	shine.emission = Color(1, 1, 0.85)
	shine.emission_energy_multiplier = 6.0
	_glint.material_override = shine
	_glint.position = Vector3(0.28, 0.12, 0.05)
	_glint.visible = false
	add_child(_glint)


## Every peer, for its own player: does a torch beam (or the low evening sun) catch the steel?
func _process(_delta: float) -> void:
	if _glint == null:
		return
	var me: Node3D = null
	for p in get_tree().get_nodes_in_group("players"):
		if p.is_multiplayer_authority():
			me = p
	if me == null:
		_glint.visible = false
		return
	var to: Vector3 = global_position - me.head.global_position
	var d: float = to.length()
	var lit: bool = me.flashlight_on and d < 18.0 and (-me.head.global_basis.z).dot(to / d) > 0.93
	var flicker := sin(Time.get_ticks_msec() * 0.02 + global_position.x) > 0.2
	_glint.visible = lit and flicker


# --- mud: the no-no square ---------------------------------------------------------------------


func _build_mud() -> void:
	# A wet, darker skin that hugs the ground and fades out at the edge.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 14
	var size := radius * 1.25
	for zi in n + 1:
		for xi in n + 1:
			var lx := lerpf(-size, size, float(xi) / n)
			var lz := lerpf(-size, size, float(zi) / n)
			var d := Vector2(lx, lz).length() / size
			var wobble := 0.12 * sin(lx * 1.7) * cos(lz * 1.3)
			var alpha := clampf((1.0 - d - wobble) * 2.2, 0.0, 0.85)
			st.set_color(Color(0.16, 0.13, 0.08, alpha))
			st.add_vertex(Vector3(lx, Terrain.height(position.x + lx, position.z + lz) - position.y + 0.04, lz))
	for zi in n:
		for xi in n:
			var i := zi * (n + 1) + xi
			st.add_index(i)
			st.add_index(i + 1)
			st.add_index(i + n + 1)
			st.add_index(i + 1)
			st.add_index(i + n + 2)
			st.add_index(i + n + 1)
	st.generate_normals()
	var wet := StandardMaterial3D.new()
	wet.vertex_color_use_as_albedo = true
	wet.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	wet.roughness = 0.12
	wet.metallic_specular = 0.8
	var skin := MeshInstance3D.new()
	skin.mesh = st.commit()
	skin.material_override = wet
	add_child(skin)

	# Reeds and cattails around the rim (one MultiMesh each, cheap).
	var reed_mat := StandardMaterial3D.new()
	reed_mat.albedo_color = Color(0.36, 0.42, 0.2)
	var head_mat := StandardMaterial3D.new()
	head_mat.albedo_color = Color(0.32, 0.2, 0.1)
	var reed_mesh := BoxMesh.new()
	reed_mesh.size = Vector3(0.03, 1.4, 0.03)
	reed_mesh.material = reed_mat
	var head_mesh := CylinderMesh.new()
	head_mesh.top_radius = 0.045
	head_mesh.bottom_radius = 0.045
	head_mesh.height = 0.22
	head_mesh.radial_segments = 6
	head_mesh.rings = 1
	head_mesh.material = head_mat
	var reeds := MultiMesh.new()
	reeds.transform_format = MultiMesh.TRANSFORM_3D
	reeds.mesh = reed_mesh
	var heads := MultiMesh.new()
	heads.transform_format = MultiMesh.TRANSFORM_3D
	heads.mesh = head_mesh
	var count := int(radius * 14)
	reeds.instance_count = count
	heads.instance_count = count / 2
	for i in count:
		var a := _rng.randf() * TAU
		var r := radius * _rng.randf_range(0.75, 1.15)
		var x := cos(a) * r
		var z := sin(a) * r
		var y := Terrain.height(position.x + x, position.z + z) - position.y
		var h := _rng.randf_range(0.7, 1.3)
		var lean := Basis(Vector3(_rng.randf_range(-1, 1), 0, _rng.randf_range(-1, 1)).normalized(), _rng.randf_range(0.0, 0.2))
		var t := Transform3D(lean.scaled(Vector3(1, h, 1)), Vector3(x, y + 0.7 * h, z))
		reeds.set_instance_transform(i, t)
		if i < count / 2:
			heads.set_instance_transform(i, Transform3D(lean, Vector3(x, y + 1.25 * h, z) + lean.y * 0.15))
	for mm in [reeds, heads]:
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		add_child(mmi)
	# A dead stump or a fallen log at the edge, and a few slow bubbles.
	var a2 := _rng.randf() * TAU
	var wood := ModelFit.fit(NATURE + ("stump_old.glb" if _rng.randf() < 0.5 else "log_large.glb"),
		Vector3(1.0, 0.7, 2.2), _rng.randf() * TAU)
	wood.position += Vector3(cos(a2) * radius, Terrain.height(position.x + cos(a2) * radius, position.z + sin(a2) * radius) - position.y + 0.3, sin(a2) * radius)
	add_child(wood)
	var bubble_mat := StandardMaterial3D.new()
	bubble_mat.albedo_color = Color(0.22, 0.18, 0.12)
	bubble_mat.roughness = 0.05
	for i in 4:
		var bubble := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = 0.05
		sphere.height = 0.06
		bubble.mesh = sphere
		bubble.material_override = bubble_mat
		var a := _rng.randf() * TAU
		var r := _rng.randf() * radius * 0.6
		bubble.position = Vector3(cos(a) * r, Terrain.height(position.x + cos(a) * r, position.z + sin(a) * r) - position.y + 0.05, sin(a) * r)
		add_child(bubble)


# --- hole: between boulders, half hidden ---------------------------------------------------------


func _build_hole() -> void:
	var black := StandardMaterial3D.new()
	black.albedo_color = Color(0.015, 0.012, 0.01)
	var pit := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = radius
	disc.bottom_radius = radius * 0.8
	disc.height = 0.5
	disc.radial_segments = 12
	disc.rings = 1
	pit.mesh = disc
	pit.material_override = black
	pit.position.y = -0.22
	add_child(pit)
	# Boulders around it, so you come round a rock and there it is.
	for i in 3:
		var a := i * TAU / 3.0 + _rng.randf() * 0.8
		var r := radius + _rng.randf_range(0.6, 1.4)
		var rock := ModelFit.fit(NATURE + ("rock_tallA.glb" if i % 2 else "stone_largeA.glb"),
			Vector3(1.8, _rng.randf_range(1.2, 2.2), 1.8), _rng.randf() * TAU)
		rock.position += Vector3(cos(a) * r, 0.6, sin(a) * r)
		add_child(rock)
	# Ferns and a couple of branches half over the opening.
	for i in 5:
		var a := _rng.randf() * TAU
		var r := radius * _rng.randf_range(0.6, 1.1)
		var fern := ModelFit.fit(NATURE + "plant_flatTall.glb", Vector3(1.1, 0.9, 1.1), _rng.randf() * TAU)
		fern.position += Vector3(cos(a) * r, 0.4, sin(a) * r)
		add_child(fern)
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.35, 0.25, 0.15)
	for i in 2:
		var branch := MeshInstance3D.new()
		var stick := CylinderMesh.new()
		stick.top_radius = 0.04
		stick.bottom_radius = 0.06
		stick.height = radius * 2.4
		stick.radial_segments = 5
		stick.rings = 1
		branch.mesh = stick
		branch.material_override = wood
		branch.rotation = Vector3(PI / 2.0, _rng.randf() * TAU, 0.05)
		branch.position = Vector3(_rng.randf_range(-0.3, 0.3), 0.05, _rng.randf_range(-0.3, 0.3))
		add_child(branch)
	# One in four has a rotten, leaning sign. The rest: good luck.
	if _rng.randf() < 0.25:
		var post := MeshInstance3D.new()
		var pole := BoxMesh.new()
		pole.size = Vector3(0.08, 1.3, 0.08)
		post.mesh = pole
		post.material_override = wood
		post.position = Vector3(radius + 0.4, 0.6, 0.3)
		post.rotation.z = 0.35
		add_child(post)
		var label := Label3D.new()
		label.text = "POZOR"
		label.font_size = 28
		label.pixel_size = 0.005
		label.modulate = Color(0.45, 0.35, 0.25)
		label.double_sided = true
		label.position = Vector3(radius + 0.2, 1.05, 0.35)
		label.rotation.z = 0.35
		add_child(label)


func _on_body_entered(body: Node) -> void:
	if not multiplayer.is_server() or not body.is_in_group("players"):
		return
	var now := Time.get_ticks_msec() / 1000.0
	var peer: int = body.peer_id
	if now < _armed_at or not Team.is_alive(peer) or Team.stuck_in(peer) != "" or body.in_car():
		return
	if kind == "hole" and body.global_position.distance_to(global_position) > radius * 0.8:
		return  # only the middle of the hole swallows you
	_armed_at = now + REARM_SECONDS
	Team.set_stuck(peer, kind)
	Sfx.play_all("metal_hit" if kind == "bear trap" else ("splash" if kind == "mud" else "branch_snap"), global_position)
	Hearing.emit(global_position, 25.0, peer)
	var how := "Someone has to pull them out (E on them), or they wriggle free." if kind != "hole" else \
		"They fell down a HOLE. Only a friend with a rope (Jano's) can get them out."
	Team.tell(0, "%s is stuck in %s! %s" % [Team.players[peer]["name"], {"bear trap": "a bear trap", "mud": "the mud",
		"hole": "a hole"}[kind], how])
	Team.highlight("%s steps in %s" % [Team.players[peer]["name"], {"bear trap": "a bear trap", "mud": "the mud",
		"hole": "a hole"}[kind]])
