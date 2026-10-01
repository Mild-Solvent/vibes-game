extends RefCounted
## The map: one heightfield shared by every peer (fixed seed, pure functions), with flat spots for
## the places, painted dirt roads and footpaths, a lake, a big hill with a cliff, and mountains
## around the edge so nobody wanders off the world.
##
## World units are metres; the camp is at the origin.

const SIZE := 480.0  # the map is SIZE x SIZE, centred on the camp
const STEP := 2.0  # grid spacing of the heightfield
const WATER_Y := -1.2
const SEED := 20261001

## Flat places: [name, centre (x, z), radius, height]
const PLACES := [
	["camp", Vector2(0, 0), 16.0, 0.6],
	["village", Vector2(170, 40), 38.0, 1.0],
	["casino", Vector2(180, -62), 20.0, 0.8],
	["witch", Vector2(-170, -150), 18.0, -0.4],
	["ruin", Vector2(-62, 128), 10.0, 6.0],
]
## Roads the car can use (wide, dirt) and footpaths (narrow), as polylines.
const ROADS := [
	[Vector2(0, 0), Vector2(55, 12), Vector2(115, 26), Vector2(170, 40)],
	[Vector2(115, 26), Vector2(150, -20), Vector2(180, -62)],
]
const PATHS := [
	[Vector2(0, 0), Vector2(-35, -35), Vector2(-95, -80), Vector2(-135, -128), Vector2(-170, -150)],
	[Vector2(-10, 5), Vector2(-30, 55), Vector2(-50, 100), Vector2(-62, 128)],
	[Vector2(8, -6), Vector2(30, -55), Vector2(55, -78)],
]
const LAKE := [Vector2(70, -115), 38.0]
const HILL := [Vector2(-125, 55), 42.0, 24.0]  # centre, radius, height (steep on the east side)

const ROAD_HALF_WIDTH := 4.0
const PATH_HALF_WIDTH := 1.3

static var _noise: FastNoiseLite


static func _get_noise() -> FastNoiseLite:
	if _noise == null:
		_noise = FastNoiseLite.new()
		_noise.seed = SEED
		_noise.frequency = 0.012
		_noise.fractal_octaves = 3
	return _noise


## Ground height at (x, z).
static func height(x: float, z: float) -> float:
	var p := Vector2(x, z)
	var h := _get_noise().get_noise_2d(x, z) * 5.0

	# The hill, with a cliff on its east face.
	var hill_c: Vector2 = HILL[0]
	var d := p.distance_to(hill_c) / HILL[1]
	if d < 1.0:
		var bump: float = HILL[2] * smoothstep(1.0, 0.25, d)
		if x > hill_c.x + 6.0 and d > 0.25:
			bump *= smoothstep(1.0, 0.85, d * 1.6)  # sheer drop
		h += bump

	# The lake bowl.
	var lake_d := p.distance_to(LAKE[0]) / LAKE[1]
	if lake_d < 1.3:
		h = lerpf(h, -4.5, smoothstep(1.3, 0.6, lake_d))

	# Mountains around the edge.
	var edge := maxf(absf(x), absf(z)) / (SIZE / 2.0)
	if edge > 0.82:
		h += pow((edge - 0.82) / 0.18, 2.0) * 40.0

	# Roads get smoothed so the car doesn't bounce off every bump.
	var road_d := _distance_to_lines(p, ROADS)
	if road_d < ROAD_HALF_WIDTH * 3.0:
		h = lerpf(h, h * 0.35, smoothstep(ROAD_HALF_WIDTH * 3.0, ROAD_HALF_WIDTH, road_d))

	# Flat places on top of everything.
	for place in PLACES:
		var pd: float = p.distance_to(place[1])
		var r: float = place[2]
		if pd < r * 1.8:
			h = lerpf(h, place[3], smoothstep(r * 1.8, r, pd))
	return h


## Ground colour at (x, z): grass with variation, dirt roads, footpaths, sand by the lake, rock high up.
static func colour(x: float, z: float, h: float) -> Color:
	var p := Vector2(x, z)
	var n := _get_noise().get_noise_2d(x * 3.1 + 500.0, z * 3.1)
	var grass := Color(0.27, 0.42, 0.18).lerp(Color(0.36, 0.48, 0.2), n * 0.5 + 0.5)
	var c := grass
	if h > 12.0:
		c = c.lerp(Color(0.45, 0.43, 0.4), smoothstep(12.0, 20.0, h))
	var lake_d := p.distance_to(LAKE[0])
	if lake_d < LAKE[1] * 1.15:
		c = c.lerp(Color(0.72, 0.65, 0.45), smoothstep(LAKE[1] * 1.15, LAKE[1] * 0.9, lake_d))
	var path_d := _distance_to_lines(p, PATHS)
	if path_d < PATH_HALF_WIDTH + 0.6:
		c = c.lerp(Color(0.5, 0.4, 0.27), smoothstep(PATH_HALF_WIDTH + 0.6, PATH_HALF_WIDTH - 0.4, path_d))
	var road_d := _distance_to_lines(p, ROADS)
	if road_d < ROAD_HALF_WIDTH + 1.0:
		c = c.lerp(Color(0.42, 0.33, 0.22), smoothstep(ROAD_HALF_WIDTH + 1.0, ROAD_HALF_WIDTH - 0.8, road_d))
	for place in PLACES:
		var pd: float = p.distance_to(place[1])
		if pd < place[2]:
			c = c.lerp(Color(0.4, 0.36, 0.26), smoothstep(place[2], place[2] * 0.6, pd) * 0.6)
	return c


## True where you shouldn't put a tree: places, roads, paths, the lake.
static func is_clear(x: float, z: float, margin := 0.0) -> bool:
	var p := Vector2(x, z)
	for place in PLACES:
		if p.distance_to(place[1]) < place[2] + 4.0 + margin:
			return false
	if _distance_to_lines(p, ROADS) < ROAD_HALF_WIDTH + 2.5 + margin:
		return false
	if _distance_to_lines(p, PATHS) < PATH_HALF_WIDTH + 1.5 + margin:
		return false
	if p.distance_to(LAKE[0]) < LAKE[1] * 1.05 + margin:
		return false
	return absf(x) < SIZE * 0.4 and absf(z) < SIZE * 0.4


static func place_centre(place_name: String) -> Vector3:
	for place in PLACES:
		if place[0] == place_name:
			var c: Vector2 = place[1]
			return Vector3(c.x, place[3], c.y)
	return Vector3.ZERO


static func _distance_to_lines(p: Vector2, lines: Array) -> float:
	var best := INF
	for line in lines:
		for i in line.size() - 1:
			var a: Vector2 = line[i]
			var b: Vector2 = line[i + 1]
			best = minf(best, p.distance_to(Geometry2D.get_closest_point_to_segment(p, a, b)))
	return best


## Builds the ground (mesh + collision) as a StaticBody3D.
static func build() -> StaticBody3D:
	var count := int(SIZE / STEP) + 1
	var half := SIZE / 2.0
	var heights := PackedFloat32Array()
	heights.resize(count * count)
	for zi in count:
		for xi in count:
			heights[zi * count + xi] = height(-half + xi * STEP, -half + zi * STEP)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for zi in count:
		for xi in count:
			var x := -half + xi * STEP
			var z := -half + zi * STEP
			var h := heights[zi * count + xi]
			st.set_color(colour(x, z, h))
			st.add_vertex(Vector3(x, h, z))
	for zi in count - 1:
		for xi in count - 1:
			var i := zi * count + xi
			st.add_index(i)
			st.add_index(i + 1)
			st.add_index(i + count)
			st.add_index(i + 1)
			st.add_index(i + count + 1)
			st.add_index(i + count)
	st.generate_normals()
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 1.0
	st.set_material(mat)

	var body := StaticBody3D.new()
	body.name = "Ground"
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = st.commit()
	body.add_child(mesh_instance)

	# HeightMapShape3D has 1 m cells; scale it uniformly by STEP (non-uniform shape scale isn't
	# supported), so the heights go in divided by STEP.
	var scaled := PackedFloat32Array(heights)
	for i in scaled.size():
		scaled[i] /= STEP
	var shape := HeightMapShape3D.new()
	shape.map_width = count
	shape.map_depth = count
	shape.map_data = scaled
	var collision := CollisionShape3D.new()
	collision.shape = shape
	collision.scale = Vector3.ONE * STEP
	body.add_child(collision)
	return body
