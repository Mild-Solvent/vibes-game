extends "res://scripts/prop.gd"
## A mushroom: pick it (E), turn it over to look at it (mouse wheel / R), throw it (Q), or taste
## it (F). Tasting identifies the whole species for the team: villagers only buy species you've
## identified ("Is it safe?" "My friend ate one and he's fine. Mostly.").
## Thrown too hard too often, it breaks into bits.

enum Effect { FOOD, TRIP, STRONG, POISON, WITCH, CURE }

const BREAK_SPEED := 6.0
const BREAK_HITS := 3

## kind: [effect, price €, cap colour, stem colour, cap radius, stem height, stem radius, name, glow, shape]
## shape: "dome", "flat" (parasol), "tall" (cone cap), "ball" (puffball), "finger"
const KINDS := {
	"porcini": [Effect.FOOD, 20, Color(0.45, 0.28, 0.12), Color(0.9, 0.85, 0.7), 0.16, 0.14, 0.06,
		"Porcini (hríb)", false, "dome"],
	"satans_bolete": [Effect.POISON, 0, Color(0.6, 0.55, 0.48), Color(0.75, 0.3, 0.22), 0.16, 0.14, 0.06,
		"Satan's bolete", false, "dome"],
	"parasol": [Effect.FOOD, 15, Color(0.8, 0.72, 0.58), Color(0.7, 0.6, 0.5), 0.22, 0.35, 0.03,
		"Parasol (bedľa)", false, "flat"],
	"death_cap": [Effect.POISON, 0, Color(0.78, 0.82, 0.62), Color(0.92, 0.92, 0.88), 0.14, 0.24, 0.035,
		"Death cap (muchotrávka)", false, "flat"],
	"chanterelle": [Effect.FOOD, 10, Color(1.0, 0.75, 0.2), Color(1.0, 0.8, 0.35), 0.08, 0.07, 0.03,
		"Chanterelle (kuriatko)", false, "dome"],
	"false_chanterelle": [Effect.TRIP, 12, Color(1.0, 0.55, 0.12), Color(1.0, 0.6, 0.2), 0.08, 0.07, 0.03,
		"False chanterelle", false, "dome"],
	# The crazy ones.
	"glowcap": [Effect.TRIP, 30, Color(0.2, 0.95, 1.0), Color(0.6, 0.9, 1.0), 0.1, 0.18, 0.025,
		"Glowcap", true, "tall"],
	"rainbow_bolete": [Effect.STRONG, 45, Color(0.9, 0.2, 0.85), Color(0.3, 0.9, 0.4), 0.15, 0.14, 0.06,
		"Rainbow bolete", true, "dome"],
	"golden_chanterelle": [Effect.FOOD, 60, Color(1.0, 0.9, 0.3), Color(1.0, 0.95, 0.6), 0.09, 0.08, 0.03,
		"Golden chanterelle", true, "dome"],
	"screaming_puffball": [Effect.FOOD, 18, Color(0.95, 0.95, 0.9), Color(0.9, 0.9, 0.85), 0.14, 0.04, 0.05,
		"Screaming puffball", false, "ball"],
	"devils_cigar": [Effect.POISON, 0, Color(0.25, 0.12, 0.08), Color(0.35, 0.2, 0.1), 0.05, 0.3, 0.04,
		"Devil's cigar", false, "tall"],
	"witch_finger": [Effect.WITCH, 0, Color(0.15, 0.1, 0.2), Color(0.3, 0.6, 0.25), 0.04, 0.34, 0.03,
		"Witch's finger", true, "finger"],
	# Cure ingredients the witch sends you for. They only grow in the scary places, never randomly.
	"mothers_mould": [Effect.CURE, 0, Color(0.55, 0.62, 0.5), Color(0.4, 0.45, 0.38), 0.13, 0.05, 0.06,
		"Mother's mould", false, "ball"],
	"kobold_cap": [Effect.CURE, 0, Color(0.85, 1.0, 0.3), Color(0.6, 0.7, 0.3), 0.1, 0.12, 0.03,
		"Kobold cap", true, "dome"],
	"bone_morel": [Effect.CURE, 0, Color(0.95, 0.92, 0.8), Color(0.9, 0.88, 0.8), 0.07, 0.2, 0.03,
		"Bone morel", false, "tall"],
	"drowned_chanterelle": [Effect.CURE, 0, Color(0.2, 0.75, 0.7), Color(0.3, 0.6, 0.6), 0.09, 0.08, 0.03,
		"Drowned chanterelle", true, "dome"],
}
## How often each kind spawns (rarer = smaller).
const WEIGHTS := {
	"porcini": 10, "satans_bolete": 8, "parasol": 9, "death_cap": 8, "chanterelle": 10,
	"false_chanterelle": 8, "glowcap": 6, "rainbow_bolete": 4, "golden_chanterelle": 2,
	"screaming_puffball": 6, "devils_cigar": 6, "witch_finger": 4,
}

signal tasted(peer_id: int)

var kind := "porcini"
var effect := Effect.FOOD
var price := 0
var display_name := ""
var _hits := 0


static func pick_kind(rng: RandomNumberGenerator) -> String:
	var total := 0
	for k in WEIGHTS:
		total += WEIGHTS[k]
	var roll := rng.randi() % total
	for k in WEIGHTS:
		roll -= WEIGHTS[k]
		if roll < 0:
			return k
	return "porcini"


static func price_of(mushroom_kind: String) -> int:
	return KINDS[mushroom_kind][1]


static func name_of(mushroom_kind: String) -> String:
	return KINDS[mushroom_kind][7]


## What you can tell just by looking: "a tall cone-capped mushroom, greenish". Names are Babka's job.
static func describe(mushroom_kind: String) -> String:
	var k: Array = KINDS[mushroom_kind]
	var shape: String = {"dome": "round-capped", "flat": "flat-capped", "tall": "pointy", "ball": "ball-shaped",
		"finger": "finger-shaped"}[k[9]]
	var size := "small" if k[4] < 0.09 else ("big" if k[4] > 0.15 else "")
	var glow := ", glowing" if k[8] else ""
	return ("a %s %s mushroom, %s%s" % [size, shape, _colour_word(k[2]), glow]).replace("  ", " ")


## The name if Babka Hela has told you, else a description.
static func label_of(mushroom_kind: String) -> String:
	return name_of(mushroom_kind) if Team.known.has(mushroom_kind) else describe(mushroom_kind)


static func _colour_word(c: Color) -> String:
	if c.s < 0.25:
		return "white" if c.v > 0.8 else ("grey" if c.v > 0.4 else "black")
	var h := c.h * 360.0
	if h < 20.0 or h > 340.0:
		return "red"
	if h < 45.0:
		return "brown" if c.v < 0.6 else "orange"
	if h < 70.0:
		return "yellow"
	if h < 160.0:
		return "greenish"
	if h < 200.0:
		return "teal"
	if h < 260.0:
		return "blue"
	return "purple" if h < 300.0 else "pink"


## Villagers buy food and the fun ones, but only once the species is identified.
static func sellable(mushroom_kind: String) -> bool:
	var e: int = KINDS[mushroom_kind][0]
	return e == Effect.FOOD or e == Effect.TRIP or e == Effect.STRONG


func setup_mushroom(prop_name: String, mushroom_kind: String) -> void:
	kind = mushroom_kind
	var k: Array = KINDS[kind]
	effect = k[0]
	price = k[1]
	display_name = k[7]
	var cap_colour: Color = k[2]
	var cap_radius: float = k[4]
	var stem_height: float = k[5]
	var stem_radius: float = k[6]
	var glow: bool = k[8]
	var shape_kind: String = k[9]

	var stem := CylinderMesh.new()
	stem.top_radius = stem_radius
	stem.bottom_radius = stem_radius * 1.2
	stem.height = stem_height
	stem.radial_segments = 8
	stem.rings = 1
	var shape := BoxShape3D.new()
	shape.size = Vector3(maxf(cap_radius, stem_radius) * 2.0, stem_height + cap_radius * 0.6, maxf(cap_radius, stem_radius) * 2.0)
	setup(prop_name, stem, shape, k[3], 0.2)

	var cap := MeshInstance3D.new()
	match shape_kind:
		"flat":
			var m := CylinderMesh.new()
			m.top_radius = cap_radius * 0.35
			m.bottom_radius = cap_radius
			m.height = cap_radius * 0.35
			m.radial_segments = 10
			m.rings = 1
			cap.mesh = m
		"tall", "finger":
			var m := CylinderMesh.new()
			m.top_radius = 0.0 if shape_kind == "tall" else cap_radius * 0.6
			m.bottom_radius = cap_radius
			m.height = cap_radius * (2.6 if shape_kind == "tall" else 2.0)
			m.radial_segments = 8
			m.rings = 1
			cap.mesh = m
		"ball":
			var m := SphereMesh.new()
			m.radius = cap_radius
			m.height = cap_radius * 1.8
			m.radial_segments = 10
			m.rings = 5
			cap.mesh = m
		_:
			var m := SphereMesh.new()
			m.radius = cap_radius
			m.height = cap_radius * 1.1
			m.is_hemisphere = true
			m.radial_segments = 10
			m.rings = 4
			cap.mesh = m
	cap.position.y = stem_height / 2.0
	var mat := StandardMaterial3D.new()
	mat.albedo_color = cap_colour
	if glow:
		mat.emission_enabled = true
		mat.emission = cap_colour
		mat.emission_energy_multiplier = 1.4
	cap.material_override = mat
	add_child(cap)


## Holder only. The mushroom is eaten either way.
@rpc("any_peer", "call_local", "reliable")
func request_taste() -> void:
	if not multiplayer.is_server() or removed:
		return
	var sender := _sender_id()
	if sender != holder_id or not Team.is_alive(sender):
		return
	remove_from_play()
	Sfx.play_all("eat", global_position)
	Team.tell(sender, Team.apply_mushroom(sender, effect, display_name))
	tasted.emit(sender)


func _on_impact(speed: float) -> void:
	if not multiplayer.is_server() or removed or speed < BREAK_SPEED:
		return
	_hits += 1
	if _hits < BREAK_HITS:
		return
	var at := global_position
	remove_from_play()
	_shatter.rpc(at, KINDS[kind][2])


func reset_to_home() -> void:
	super.reset_to_home()
	_hits = 0


## Every peer: a little puff of mushroom bits where it broke (visual only).
@rpc("authority", "call_local", "reliable")
func _shatter(at: Vector3, cap_colour: Color) -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = cap_colour
	for i in 7:
		var bit := RigidBody3D.new()
		bit.collision_layer = 0
		bit.collision_mask = 1
		var mesh := BoxMesh.new()
		mesh.size = Vector3.ONE * randf_range(0.03, 0.07)
		var visual := MeshInstance3D.new()
		visual.mesh = mesh
		visual.material_override = mat
		bit.add_child(visual)
		var col := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = mesh.size
		col.shape = box
		bit.add_child(col)
		get_parent().add_child(bit)
		bit.global_position = at + Vector3(randf_range(-0.1, 0.1), 0.1, randf_range(-0.1, 0.1))
		bit.linear_velocity = Vector3(randf_range(-2, 2), randf_range(1, 3), randf_range(-2, 2))
		get_tree().create_timer(5.0).timeout.connect(bit.queue_free)
