extends Area3D
## A bramble thicket in the thick forest: thorny, dark, and you can't run through it.
## Every peer's own player slows down while inside (players own their movement).

const ModelFit := preload("res://scripts/model_fit.gd")
const Terrain := preload("res://scripts/world/terrain.gd")
const NATURE := "res://assets/kenney/nature-kit/"

var radius := 3.0


func build(at: Vector3, seed_value: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	radius = rng.randf_range(2.5, 4.5)
	position = at
	var shape := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = radius
	cyl.height = 2.0
	shape.shape = cyl
	shape.position.y = 1.0
	add_child(shape)
	var thorn := StandardMaterial3D.new()
	thorn.albedo_color = Color(0.16, 0.2, 0.1)
	var berry := StandardMaterial3D.new()
	berry.albedo_color = Color(0.35, 0.05, 0.15)
	for i in int(radius * 4):
		var a := rng.randf() * TAU
		var r := sqrt(rng.randf()) * radius
		var x := cos(a) * r
		var z := sin(a) * r
		var bush := ModelFit.fit(NATURE + ("plant_bushDetailed.glb" if i % 2 else "plant_bushSmall.glb"),
			Vector3(1.4, rng.randf_range(0.7, 1.3), 1.4), rng.randf() * TAU)
		bush.position += Vector3(x, Terrain.height(at.x + x, at.z + z) - at.y + 0.5, z)
		for mi in bush.find_children("*", "MeshInstance3D", true, false):
			mi.material_override = thorn
		add_child(bush)
		if i % 3 == 0:
			var dot := MeshInstance3D.new()
			var sphere := SphereMesh.new()
			sphere.radius = 0.05
			sphere.height = 0.1
			dot.mesh = sphere
			dot.material_override = berry
			dot.position = bush.position + Vector3(0.2, 0.4, 0.1)
			add_child(dot)
	body_entered.connect(func(b): _touch(b, 1))
	body_exited.connect(func(b): _touch(b, -1))


func _touch(body: Node, step: int) -> void:
	if body.is_in_group("players") and body.is_multiplayer_authority():
		body.brambles = maxi(body.brambles + step, 0)
		if step > 0:
			Sfx.play("branch_snap", global_position, -6.0)
