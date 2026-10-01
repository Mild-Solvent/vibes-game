extends RefCounted
## Builds the few blocks of city outside Channel 6's studio (part of the studio level, east of
## the building, through the EXIT door). Kenney city kits at 8 m per road tile.
##
## Local layout (studio level space, metres):
##   x = 12   the studio's east wall (door at z ~ 4)
##   x = 20   MAIN STREET, north-south          z = 4   the cross street, east
##   x = 52   SECOND STREET, north-south        (52, 4) the crossroad
##   plaza in the north-east block, parking lot in the south-east block,
##   houses north of the studio, shops south of it, skyscrapers beyond the edges.
## Invisible walls keep players between x = 12 .. 60 and z = -40 .. 48 (and in the studio).

const TILE := 8.0
const ROADS := "res://assets/kenney/city-kit-roads/"
const SHOPS := "res://assets/kenney/city-kit-commercial/"
const HOUSES := "res://assets/kenney/city-kit-suburban/"
const CARS := "res://assets/kenney/car-kit/"
const MIN := Vector2(12.4, -40.0)
const MAX := Vector2(60.0, 48.0)
const ROAD_Y := -0.05

## Where the breaking-news props turn up (level-local, on the ground).
const STORY_SPOTS := [
	Vector3(40, 0.6, 28), Vector3(36, 0.6, -10), Vector3(20, 0.6, 30), Vector3(52, 0.6, -18),
	Vector3(44, 0.6, 4), Vector3(20, 0.6, -24), Vector3(30, 0.6, 40), Vector3(56, 0.6, 30),
]

var level: Node3D


func build(target: Node3D) -> void:
	level = target
	# Ground (a touch below the studio floor so they don't z-fight) and the edges of the world.
	level._box(Vector3(140, 0.2, 120), Vector3(30, -0.13, 4), Color(0.42, 0.45, 0.4))
	level._barrier(Vector3(1, 12, MAX.y - MIN.y), Vector3(MAX.x + 0.5, 6, (MIN.y + MAX.y) / 2.0))
	level._barrier(Vector3(MAX.x - MIN.x, 12, 1), Vector3((MIN.x + MAX.x) / 2.0, 6, MIN.y - 0.5))
	level._barrier(Vector3(MAX.x - MIN.x, 12, 1), Vector3((MIN.x + MAX.x) / 2.0, 6, MAX.y + 0.5))
	# West of main street: the studio's own wall, plus walls along the house and shop rows.
	level._barrier(Vector3(1, 12, MAX.y - 10.3), Vector3(MIN.x - 0.5, 6, (10.3 + MAX.y) / 2.0))
	level._barrier(Vector3(1, 12, -8.3 - MIN.y), Vector3(MIN.x - 0.5, 6, (MIN.y - 8.3) / 2.0))
	_roads()
	_buildings()
	_street_furniture()
	_parked_cars()


func _tile(model: String, x: float, z: float, yaw := 0.0) -> void:
	level._place(ROADS + model + ".glb", Vector3(x, ROAD_Y, z), TILE, yaw)


func _roads() -> void:
	for i in 11:
		var z := -36.0 + i * TILE
		if is_equal_approx(z, 4.0):
			_tile("road-intersection", 20, z, PI / 2.0)
		else:
			_tile("road-straight", 20, z)
	for x in [28.0, 36.0, 44.0]:
		_tile("road-straight", x, 4, PI / 2.0)
	_tile("road-end", 60, 4, -PI / 2.0)
	for i in 9:
		var z := -28.0 + i * TILE
		if is_equal_approx(z, 4.0):
			_tile("road-crossroad", 52, z)
		else:
			_tile("road-straight", 52, z)


func _buildings() -> void:
	# North-east block, facing main street and the cross street.
	_building(SHOPS + "building-a.glb", 28.5, 13, -PI / 2.0)
	_building(SHOPS + "building-c.glb", 28.5, 22, -PI / 2.0)
	_building(SHOPS + "building-g.glb", 28.5, 42, -PI / 2.0)
	_building(SHOPS + "building-e.glb", 44, 12.5, PI)
	_building(SHOPS + "building-m.glb", 44, 43, 0.0)
	# South-east block: shops along main street, a parking lot towards the cross street.
	_building(SHOPS + "building-b.glb", 28.5, -20, -PI / 2.0)
	_building(SHOPS + "building-k.glb", 30, -34, -PI / 2.0)
	_building(SHOPS + "building-h.glb", 44, -34, 0.0)
	_building(SHOPS + "building-d.glb", 44, -24, PI / 2.0)
	# West of main street: houses north of the studio, shops south of it.
	_building(HOUSES + "building-type-a.glb", 7, 18, PI / 2.0, 7.0)
	_building(HOUSES + "building-type-c.glb", 7, 30, PI / 2.0, 7.0)
	_building(HOUSES + "building-type-f.glb", 7, 42, PI / 2.0, 6.0)
	_building(SHOPS + "building-f.glb", 7.5, -16, PI / 2.0)
	_building(SHOPS + "building-k.glb", 6, -30, PI / 2.0)
	# Skyline beyond the edges (out of reach).
	var towers := ["building-skyscraper-a", "building-skyscraper-b", "building-skyscraper-c", "building-skyscraper-e"]
	for i in 7:
		_building(SHOPS + towers[i % towers.size()] + ".glb", 68, -36 + i * 13.0, PI / 2.0 * (i % 4))
	for i in 4:
		_building(SHOPS + towers[(i + 1) % towers.size()] + ".glb", 26 + i * 12.0, 58, PI * (i % 2))
		_building(SHOPS + towers[(i + 2) % towers.size()] + ".glb", 26 + i * 12.0, -50, PI * (i % 2))


func _building(path: String, x: float, z: float, yaw: float, scale := TILE) -> void:
	level._place(path, Vector3(x, 0, z), scale, yaw, true)


func _street_furniture() -> void:
	# Street lights along both sides of main street and the second street.
	for i in 6:
		var z := -34.0 + i * 16.0
		level._place(ROADS + "light-square.glb", Vector3(15.0, 0, z), TILE, PI / 2.0)
		level._place(ROADS + "light-square.glb", Vector3(25.0, 0, z + 8.0), TILE, -PI / 2.0)
		level._place(ROADS + "light-curved.glb", Vector3(57.0, 0, z + 4.0), TILE, -PI / 2.0)
	level._place(ROADS + "traffic-light.glb", Vector3(25, 0, -0.5), TILE, PI)
	level._place(ROADS + "traffic-light.glb", Vector3(47, 0, 8.5), TILE)
	level._place(ROADS + "traffic-light.glb", Vector3(57, 0, -0.5), TILE, PI / 2.0)
	level._place(ROADS + "road-sign-stop.glb", Vector3(25, 0, 8.5), TILE, -PI / 2.0)
	level._place(ROADS + "dumpster.glb", Vector3(41, 0, -14), TILE * 0.8, PI / 2.0, true)
	level._place(ROADS + "dumpster.glb", Vector3(41, 0, -18), TILE * 0.8, PI / 2.0, true)
	for z in [-6.0, -4.5, -3.0]:
		level._place(ROADS + "construction-cone.glb", Vector3(23, 0, z), TILE)
	level._place(ROADS + "construction-barrier.glb", Vector3(22.5, 0, -8), TILE, PI / 2.0, true)

	# Paved plaza and an asphalt parking lot with painted bays.
	level._box(Vector3(20, 0.02, 30), Vector3(38, -0.015, 26), Color(0.62, 0.6, 0.56), false)
	level._box(Vector3(20, 0.02, 9), Vector3(38, -0.015, -6.5), Color(0.25, 0.26, 0.28), false)
	for x in [31.0, 35.0, 39.0, 43.0, 47.0]:
		level._box(Vector3(0.12, 0.02, 4), Vector3(x, -0.005, -6.5), Color(0.9, 0.9, 0.9), false)
	# The plaza: trees, planters, café parasols.
	for p in [Vector2(36, 20), Vector2(46, 22), Vector2(34, 34), Vector2(46, 34), Vector2(40, 40)]:
		level._place(HOUSES + "tree-large.glb", Vector3(p.x, 0, p.y), TILE, p.x, true)
	for p in [Vector2(38, 27), Vector2(42, 31), Vector2(36, 29)]:
		level._place(HOUSES + "planter.glb", Vector3(p.x, 0, p.y), TILE * 0.6, 0.0, true)
	for p in [Vector2(32, 16), Vector2(35, 15)]:
		level._place(SHOPS + "detail-parasol-a.glb", Vector3(p.x, 0, p.y), TILE * 0.6)
	# Trees along the houses.
	for z in [12.0, 24.0, 36.0, 46.0]:
		level._place(HOUSES + "tree-small.glb", Vector3(13.5, 0, z), TILE, z, true)
	level._place(HOUSES + "fence-low.glb", Vector3(10, 0, 24), TILE * 0.6, PI / 2.0)


func _parked_cars() -> void:
	var cars := [
		["sedan", Vector3(17.6, 0, -18), 0.0], ["taxi", Vector3(17.6, 0, 22), PI],
		["police", Vector3(22.4, 0, 14), 0.0], ["van", Vector3(22.4, 0, -30), PI],
		["delivery", Vector3(49.6, 0, 20), PI], ["garbage-truck", Vector3(54.4, 0, -14), 0.0],
		["sedan", Vector3(33, 0, -6), PI / 2.0], ["taxi", Vector3(37, 0, -6), PI / 2.0],
		["van", Vector3(45, 0, -6), PI / 2.0],
	]
	for car in cars:
		level._place(CARS + car[0] + ".glb", car[1], 1.3, car[2], true)
