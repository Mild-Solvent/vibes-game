extends RefCounted
## The forest: thousands of trees, bushes, ferns, flowers, rocks and logs. Drawn as MultiMeshes,
## one per model per 128 m chunk, so far-away chunks fade out on their own (one MultiMesh for
## the whole map gets culled by its centre, which made plants vanish as you walked up to them).
## Trunks and big rocks get colliders; small stuff you walk through.
##
## Density follows a noise field: thickets you get lost in, and clearings between them.

const ModelFit := preload("res://scripts/model_fit.gd")
const Terrain := preload("res://scripts/world/terrain.gd")

const NATURE := "res://assets/kenney/nature-kit/"
const CHUNK := 128.0
const TREE_FADE := 300.0
const SMALL_FADE := 150.0  # a chunk centre can be ~90 m away while you stand in its corner

## [model, count, height range, collider radius (0 = walk through)]
const PLANTS := [
	["tree_pineTallA.glb", 900, Vector2(9, 15), 0.35], ["tree_pineTallB.glb", 900, Vector2(9, 15), 0.35],
	["tree_pineTallC.glb", 750, Vector2(8, 14), 0.35], ["tree_pineTallD.glb", 750, Vector2(8, 14), 0.35],
	["tree_pineRoundB.glb", 500, Vector2(6, 11), 0.35], ["tree_pineDefaultA.glb", 500, Vector2(6, 10), 0.3],
	["tree_pineDefaultB.glb", 500, Vector2(6, 10), 0.3], ["tree_pineSmallA.glb", 700, Vector2(2.5, 4.5), 0.2],
	["tree_default.glb", 300, Vector2(6, 9), 0.35], ["tree_oak.glb", 250, Vector2(7, 10), 0.45],
	["tree_fat.glb", 150, Vector2(5, 8), 0.45], ["tree_tall.glb", 300, Vector2(8, 12), 0.3],
	["tree_thin.glb", 300, Vector2(6, 9), 0.25], ["tree_cone.glb", 250, Vector2(5, 8), 0.3],
	["tree_simple.glb", 200, Vector2(5, 8), 0.3], ["tree_small.glb", 500, Vector2(2.5, 4), 0.2],
	["tree_default_dark.glb", 400, Vector2(6, 9), 0.35], ["tree_oak_fall.glb", 150, Vector2(7, 10), 0.45],
	["plant_bushLarge.glb", 1400, Vector2(1.0, 1.8), 0.0], ["plant_bushDetailed.glb", 1400, Vector2(0.7, 1.3), 0.0],
	["plant_bushSmall.glb", 1500, Vector2(0.4, 0.8), 0.0], ["plant_flatTall.glb", 2200, Vector2(0.6, 1.2), 0.0],
	["plant_flatShort.glb", 2200, Vector2(0.3, 0.6), 0.0], ["grass.glb", 3500, Vector2(0.3, 0.6), 0.0],
	["grass_leafs.glb", 2500, Vector2(0.3, 0.6), 0.0], ["flower_purpleA.glb", 600, Vector2(0.3, 0.5), 0.0],
	["flower_redA.glb", 600, Vector2(0.3, 0.5), 0.0], ["flower_yellowA.glb", 600, Vector2(0.3, 0.5), 0.0],
	["rock_tallA.glb", 250, Vector2(1.2, 2.8), 0.7], ["rock_smallA.glb", 900, Vector2(0.3, 0.6), 0.0],
	["stone_largeA.glb", 350, Vector2(0.8, 1.7), 0.8], ["stone_tallB.glb", 150, Vector2(1.5, 3.2), 0.6],
	["log.glb", 700, Vector2(0.4, 0.6), 0.0], ["stump_round.glb", 500, Vector2(0.4, 0.7), 0.35],
]

static var _density: FastNoiseLite


## Giant trees in the old-growth zones: [model, per zone, height range, collider radius]
const GIANTS := [
	["tree_pineTallA.glb", 110, Vector2(28, 42), 0.8], ["tree_pineTallB.glb", 110, Vector2(28, 42), 0.8],
	["tree_pineTallC.glb", 90, Vector2(26, 38), 0.8], ["tree_pineTallD.glb", 90, Vector2(26, 38), 0.8],
	["tree_tall.glb", 50, Vector2(22, 32), 0.6], ["stump_round.glb", 30, Vector2(0.5, 0.9), 0.4],
	["log_large.glb", 30, Vector2(0.6, 0.9), 0.0], ["plant_flatTall.glb", 120, Vector2(0.5, 0.9), 0.0],
]


## Builds everything under `parent`. Uses `rng` (seeded) so every peer gets the same forest.
## Graphics quality only thins out what's DRAWN (Settings.foliage_density), never the colliders,
## so every peer still walks into the same trees.
static func build(parent: Node3D, rng: RandomNumberGenerator) -> void:
	var density: float = Settings.foliage_density if "foliage_density" in Settings else 1.0
	_density = FastNoiseLite.new()
	_density.seed = Terrain.SEED + 3
	_density.frequency = 0.008
	var trunks := StaticBody3D.new()
	trunks.name = "Trunks"
	parent.add_child(trunks)
	var half := Terrain.SIZE * 0.41
	for entry in PLANTS:
		var info := mesh_info(NATURE + entry[0])
		if info.is_empty():
			continue
		var mesh: Mesh = info[0]
		var local: Transform3D = info[1]
		var aabb: AABB = info[2]
		var big: bool = entry[3] > 0.0
		var chunks := {}  # Vector2i -> Array[Transform3D]
		var placed := 0
		var tries := 0
		while placed < entry[1] and tries < entry[1] * 12:
			tries += 1
			var x := rng.randf_range(-half, half)
			var z := rng.randf_range(-half, half)
			# Thickets and clearings: skip spots where the density noise says "clearing".
			var dense := _density.get_noise_2d(x, z) * 0.5 + 0.5
			if rng.randf() > dense * 1.35:
				continue
			if Terrain.zone_amount(x, z, Terrain.OLD_GROWTH) > 0.3:
				continue  # the giants have this ground
			if not Terrain.is_clear(x, z, 0.0 if big else -3.0):
				continue
			var h := Terrain.height(x, z)
			if h < Terrain.WATER_Y + 0.3:
				continue
			var height: float = rng.randf_range(entry[2].x, entry[2].y)
			if entry[2].y > 3.0:
				height *= 1.5  # a proper forest: tall trees everywhere
			var s := height / aabb.size.y
			var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * s)
			var origin := Vector3(x, h - aabb.position.y * s - 0.05, z)
			var key := Vector2i(floori(x / CHUNK), floori(z / CHUNK))
			if not chunks.has(key):
				chunks[key] = []
			if big or rng.randf() < density:
				chunks[key].append(Transform3D(basis, origin) * local)
			placed += 1
			if big:
				var shape := CylinderShape3D.new()
				shape.radius = entry[3] * clampf(height / 8.0, 0.6, 1.4)
				shape.height = minf(height, 4.0)
				var col := CollisionShape3D.new()
				col.shape = shape
				col.position = Vector3(x, h + shape.height / 2.0, z)
				trunks.add_child(col)
		_add_chunks(parent, chunks, mesh, big or entry[2].y > 3.0)
	_build_giants(parent, rng, trunks)


static func _add_chunks(parent: Node3D, chunks: Dictionary, mesh: Mesh, tall: bool) -> void:
	for key in chunks:
		var list: Array = chunks[key]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mesh
		mm.instance_count = list.size()
		for i in list.size():
			mm.set_instance_transform(i, list[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.visibility_range_end = TREE_FADE if tall else SMALL_FADE
		mmi.visibility_range_end_margin = 20.0
		mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
		parent.add_child(mmi)


## The old-growth zones: huge trees packed close, a closed canopy, moss and fallen logs.
static func _build_giants(parent: Node3D, rng: RandomNumberGenerator, trunks: StaticBody3D) -> void:
	for entry in GIANTS:
		var info := mesh_info(NATURE + entry[0])
		if info.is_empty():
			continue
		var mesh: Mesh = info[0]
		var local: Transform3D = info[1]
		var aabb: AABB = info[2]
		var chunks := {}
		for zone in Terrain.OLD_GROWTH:
			var centre: Vector2 = zone[0]
			var r: float = zone[1]
			var placed := 0
			var tries := 0
			while placed < entry[1] and tries < entry[1] * 10:
				tries += 1
				var a := rng.randf() * TAU
				var d := sqrt(rng.randf()) * r
				var x := centre.x + cos(a) * d
				var z := centre.y + sin(a) * d
				if not Terrain.is_clear(x, z, 0.0):
					continue
				var h := Terrain.height(x, z)
				var height: float = rng.randf_range(entry[2].x, entry[2].y)
				var s := height / aabb.size.y
				# Giants are wider too, so the crowns close overhead.
				var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s * 0.9, s, s * 0.9))
				var key := Vector2i(floori(x / CHUNK), floori(z / CHUNK))
				if not chunks.has(key):
					chunks[key] = []
				chunks[key].append(Transform3D(basis, Vector3(x, h - aabb.position.y * s - 0.1, z)) * local)
				placed += 1
				if entry[3] > 0.0:
					var shape := CylinderShape3D.new()
					shape.radius = entry[3] * height / 34.0
					shape.height = 5.0
					var col := CollisionShape3D.new()
					col.shape = shape
					col.position = Vector3(x, h + 2.5, z)
					trunks.add_child(col)
		_add_chunks(parent, chunks, mesh, entry[2].y > 3.0)


## The first mesh in a model, its transform inside the model, and its bounds in model space.
static func mesh_info(path: String) -> Array:
	var scene: Node3D = load(path).instantiate()
	ModelFit.fix_materials(scene)
	var found: MeshInstance3D = null
	for n in scene.find_children("*", "MeshInstance3D", true, false):
		found = n
		break
	if found == null:
		scene.free()
		return []
	var local := Transform3D.IDENTITY
	var node: Node = found
	while node != scene:
		local = (node as Node3D).transform * local
		node = node.get_parent()
	var result := [found.mesh, local, local * found.mesh.get_aabb()]
	scene.free()
	return result
