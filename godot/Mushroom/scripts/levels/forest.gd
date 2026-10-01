extends "res://scripts/levels/level.gd"
## Mushroom foraging: friends lost in a foggy Slovak forest, filling one basket before dark.
## Every good mushroom has a poisonous look-alike. Pick, carry (E), throw (Q) or taste (F).
## Bad mushrooms in the basket cost points; tasting a bad one makes you see things.
##
## Layout: the car and the basket are at the local origin; the forest spreads ~55 m around it.
## Trees and mushrooms come from a fixed seed so every peer builds the same forest.

enum Event { NONE, SOMEONE_TRIPPING }

const MushroomScript := preload("res://scripts/mushroom.gd")

const SEED := 20261001
const FOREST_RADIUS := 55.0
const TREE_COUNT := 160
const SCENERY_COUNT := 140
const NATURE := "res://assets/kenney/nature-kit/"
const TREE_MODELS := [
	"tree_pineTallA.glb", "tree_pineTallB.glb", "tree_pineTallC.glb",
	"tree_pineTallD.glb", "tree_pineRoundA.glb", "tree_pineRoundC.glb",
]
## [model, size, solid]
const SCENERY := [
	["rock_largeA.glb", Vector3(1.6, 1.0, 1.4), true],
	["rock_largeC.glb", Vector3(1.4, 0.8, 1.2), true],
	["stump_old.glb", Vector3(0.9, 0.6, 0.9), true],
	["log_large.glb", Vector3(0.6, 0.5, 2.6), true],
	["plant_bush.glb", Vector3(1.2, 0.8, 1.2), false],
	["grass_large.glb", Vector3(0.8, 0.5, 0.8), false],
]
const MUSHROOM_COUNT := 48
const BASKET_ZONE := AABB(Vector3(2.0, -0.5, -1.0), Vector3(2.0, 2.0, 2.0))
const TRIP_SECONDS := 25.0

var _sun: DirectionalLight3D
var _env: Environment
var _mushrooms: Array = []
var _trips := {}  # peer id -> msec when the trip ends (host only)


func _ready() -> void:
	_add_overview(Vector3(10, 6, 12), Vector3(2, 0, 0))
	_sun = DirectionalLight3D.new()
	_sun.transform = Transform3D(Basis(), Vector3.ZERO).looking_at(Vector3(0.4, -1, -0.3))
	_sun.light_energy = 0.9
	_sun.visible = false  # only the active level's sun shines (see set_active)
	add_child(_sun)
	_build_ground()
	_build_camp()
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	_build_trees(rng)
	_build_scenery(rng)
	_build_mushrooms(rng)


## Main calls this on every peer when the host picks a level.
func set_active(active: bool) -> void:
	_sun.visible = active


# --- show rules ----------------------------------------------------------------


func title() -> String:
	return "Mushroom foraging (forest)"


func score_name() -> String:
	return "BASKET"


func start_score() -> float:
	return 0.0


func live_duration() -> float:
	return 240.0


func spawn_point(index: int) -> Vector3:
	var angle := index * TAU / 8.0
	return Vector3(cos(angle) * 3.0 - 1.0, 0.3, sin(angle) * 3.0 + 3.5)


func make_environment() -> Environment:
	_env = Environment.new()
	_env.background_mode = Environment.BG_COLOR
	_env.background_color = Color(0.55, 0.6, 0.58)
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_env.ambient_light_color = Color(0.6, 0.68, 0.6)
	_env.ambient_light_energy = 0.7
	_env.fog_enabled = true
	_env.fog_light_color = Color(0.6, 0.65, 0.62)
	_env.fog_density = 0.045
	return _env


func server_tick(_delta: float, director: Node) -> void:
	var good := 0
	var bad := 0
	var total := 0
	for m in _mushrooms:
		if m.removed or not BASKET_ZONE.has_point(m.position):
			continue
		total += m.points
		if m.edible:
			good += 1
		else:
			bad += 1
	director.score = total
	director.sub = good * 100 + bad

	var now := Time.get_ticks_msec()
	director.event = Event.NONE
	for peer in _trips.keys():
		if _trips[peer] > now:
			director.event = Event.SOMEONE_TRIPPING


func server_reset() -> void:
	super.server_reset()
	_trips.clear()


func apply_state(phase: int, _event: int, _sub: int, time_left: float) -> void:
	# Dusk falls during the round: less light, thicker fog.
	var dusk := 0.0
	if phase == Phase.LIVE:
		dusk = clampf(1.0 - time_left / live_duration(), 0.0, 1.0)
	elif phase == Phase.WRAP:
		dusk = 1.0
	_sun.light_energy = lerpf(0.9, 0.08, dusk)
	if _env:
		_env.ambient_light_energy = lerpf(0.7, 0.18, dusk)
		_env.background_color = Color(0.55, 0.6, 0.58).lerp(Color(0.05, 0.06, 0.1), dusk)
		_env.fog_light_color = Color(0.6, 0.65, 0.62).lerp(Color(0.04, 0.05, 0.08), dusk)
		_env.fog_density = lerpf(0.045, 0.07, dusk)


func phase_text(phase: int, clock: String, score: float, sub: int) -> String:
	match phase:
		Phase.PREP:
			return "PREP  %s  -  grab nothing yet, read the field guide (bottom right)" % clock
		Phase.LIVE:
			return "FORAGING  %s until dark  -  bring mushrooms to the basket by the car" % clock
	return "BACK AT THE CAR  -  %d good, %d poisonous, %d points" % [sub / 100, sub % 100, int(score)]


func event_text(event: int) -> String:
	if event == Event.SOMEONE_TRIPPING:
		return "Somebody tasted the wrong one..."
	return ""


func guide_text() -> String:
	return (
		"FIELD GUIDE\n"
		+ "Porcini: brown cap, pale stem. Satan's bolete: greyer cap, RED stem.\n"
		+ "Parasol: big flat cap, thin tall stem. Death cap: greenish, smaller. Deadly!\n"
		+ "Chanterelle: yellow-gold. False chanterelle: deeper orange.\n"
		+ "F while holding = taste it. Brave."
	)


func _on_tasted(peer_id: int, edible: bool) -> void:
	if not edible:
		_trips[peer_id] = Time.get_ticks_msec() + int(TRIP_SECONDS * 1000.0)


# --- building --------------------------------------------------------------------


func _build_ground() -> void:
	_box(Vector3(FOREST_RADIUS * 2.4, 0.2, FOREST_RADIUS * 2.4), Vector3(0, -0.1, 0), Color(0.22, 0.3, 0.15))


func _build_camp() -> void:
	# The car (a Škoda-ish box) and the basket next to it.
	var car := Vector3(2.0, 1.8, 4.2)
	_dress(_box(car, Vector3(-1.2, 0.9, 0), Color(0.15, 0.35, 0.25)), "res://assets/kenney/car-kit/suv.glb", car)
	var basket := Color(0.6, 0.42, 0.22)
	var c := BASKET_ZONE.get_center()
	_box(Vector3(2.0, 0.05, 2.0), Vector3(c.x, 0.03, c.z), basket)
	_box(Vector3(2.0, 0.4, 0.1), Vector3(c.x, 0.2, c.z - 1.0), basket)
	_box(Vector3(2.0, 0.4, 0.1), Vector3(c.x, 0.2, c.z + 1.0), basket)
	_box(Vector3(0.1, 0.4, 2.0), Vector3(c.x - 1.0, 0.2, c.z), basket)
	_box(Vector3(0.1, 0.4, 2.0), Vector3(c.x + 1.0, 0.2, c.z), basket)
	_sign("BASKET", Vector3(c.x, 1.2, c.z))
	_light(Vector3(-1.2, 2.5, 2.5), 1.2, 9.0, Color(1.0, 0.85, 0.6))  # car headlights-ish glow


func _build_trees(rng: RandomNumberGenerator) -> void:
	for i in TREE_COUNT:
		var pos := _random_spot(rng, 6.0)
		var height := rng.randf_range(6.0, 11.0)
		var width := rng.randf_range(2.8, 4.4)
		var body := StaticBody3D.new()
		body.position = pos
		var shape := CylinderShape3D.new()
		shape.radius = 0.3
		shape.height = height
		var collision := CollisionShape3D.new()
		collision.shape = shape
		collision.position.y = height / 2.0
		body.add_child(collision)
		var model := ModelFit.fit(NATURE + TREE_MODELS[rng.randi() % TREE_MODELS.size()], Vector3(width, height, width), rng.randf() * TAU)
		model.position.y += height / 2.0
		body.add_child(model)
		add_child(body)


## Rocks, stumps, logs and bushes between the trees. Rocks and stumps block you; plants don't.
func _build_scenery(rng: RandomNumberGenerator) -> void:
	for i in SCENERY_COUNT:
		var entry: Array = SCENERY[rng.randi() % SCENERY.size()]
		var size: Vector3 = entry[1] * rng.randf_range(0.7, 1.3)
		var pos := _random_spot(rng, 7.0) + Vector3(0, size.y / 2.0, 0)
		var yaw := rng.randf() * TAU
		if entry[2]:
			_dress(_box(size * Vector3(0.8, 1.0, 0.8), pos, Color.WHITE), NATURE + entry[0], size, yaw)
		else:
			var model := ModelFit.fit(NATURE + entry[0], size, yaw)
			model.position += pos
			add_child(model)


func _build_mushrooms(rng: RandomNumberGenerator) -> void:
	var kinds: Array = MushroomScript.KINDS.keys()
	for i in MUSHROOM_COUNT:
		var mushroom := MushroomScript.new()
		mushroom.setup_mushroom("Mushroom_%d" % i, kinds[i % kinds.size()])
		mushroom.position = _random_spot(rng, 8.0) + Vector3(0, 0.25, 0)
		mushroom.rotation.y = rng.randf() * TAU
		mushroom.tasted.connect(_on_tasted)
		add_child(mushroom)
		_mushrooms.append(mushroom)


## A random point in the forest, at least `clear` metres from the camp.
func _random_spot(rng: RandomNumberGenerator, clear: float) -> Vector3:
	var angle := rng.randf() * TAU
	var dist := lerpf(clear, FOREST_RADIUS, sqrt(rng.randf()))
	return Vector3(cos(angle) * dist, 0.0, sin(angle) * dist)
