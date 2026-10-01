extends "res://scripts/prop.gd"
## A mushroom: pick it (E), inspect it up close (hold right mouse), throw it (Q), or taste it (F).
## Names are hidden: only Babka Hela in the village tells you what something is. Tasting is a
## gamble whose effect kicks in later. Thrown too hard too often, it breaks into bits.
##
## Many species have look-alikes with the same silhouette and almost the same colour. The tell is a
## detail you only see up close: the gill colour or style under the cap, a ring on the stem, a cup
## (volva) at the base, a net pattern on the stem, scales on the cap, or how it bruises when held.

enum Effect { FOOD, TRIP, STRONG, POISON, WITCH, CURE }

const BREAK_SPEED := 6.0
const BREAK_HITS := 3

## kind: [effect, price €, cap colour, stem colour, cap radius, stem height, stem radius, name, glow, shape]
## shape: "dome", "flat" (parasol), "tall" (cone cap), "ball" (puffball), "finger", "funnel"
const KINDS := {
	# Boletes: porcini / bitter bolete / Satan's bolete.
	"porcini": [Effect.FOOD, 20, Color(0.45, 0.28, 0.12), Color(0.9, 0.85, 0.7), 0.16, 0.14, 0.06,
		"Porcini (hríb dubový)", false, "dome"],
	"bitter_bolete": [Effect.FOOD, 1, Color(0.47, 0.3, 0.14), Color(0.88, 0.8, 0.62), 0.16, 0.14, 0.06,
		"Bitter bolete (hríb žlčník)", false, "dome"],
	"satans_bolete": [Effect.POISON, 0, Color(0.6, 0.55, 0.48), Color(0.75, 0.3, 0.22), 0.16, 0.14, 0.06,
		"Satan's bolete", false, "dome"],
	# White caps: field mushroom / yellow stainer / death cap.
	"field_mushroom": [Effect.FOOD, 12, Color(0.95, 0.93, 0.88), Color(0.95, 0.94, 0.9), 0.1, 0.09, 0.03,
		"Field mushroom (pečiarka)", false, "dome"],
	"yellow_stainer": [Effect.POISON, 0, Color(0.96, 0.95, 0.9), Color(0.95, 0.94, 0.9), 0.1, 0.09, 0.03,
		"Yellow stainer", false, "dome"],
	"death_cap": [Effect.POISON, 0, Color(0.9, 0.92, 0.82), Color(0.94, 0.94, 0.9), 0.1, 0.11, 0.03,
		"Death cap (muchotrávka zelená)", false, "dome"],
	# Parasols: parasol / shaggy parasol / brown dapperling.
	"parasol": [Effect.FOOD, 15, Color(0.8, 0.72, 0.58), Color(0.7, 0.6, 0.5), 0.22, 0.35, 0.03,
		"Parasol (bedľa vysoká)", false, "flat"],
	"shaggy_parasol": [Effect.FOOD, 12, Color(0.82, 0.73, 0.6), Color(0.85, 0.8, 0.72), 0.17, 0.2, 0.035,
		"Shaggy parasol (bedľa červenejúca)", false, "flat"],
	"dapperling": [Effect.POISON, 0, Color(0.78, 0.66, 0.52), Color(0.82, 0.76, 0.68), 0.08, 0.1, 0.018,
		"Brown dapperling (bedlička)", false, "flat"],
	# Orange funnels: chanterelle / false chanterelle / jack-o'-lantern.
	"chanterelle": [Effect.FOOD, 10, Color(1.0, 0.75, 0.2), Color(1.0, 0.8, 0.35), 0.08, 0.07, 0.03,
		"Chanterelle (kuriatko)", false, "funnel"],
	"false_chanterelle": [Effect.TRIP, 12, Color(1.0, 0.62, 0.15), Color(1.0, 0.66, 0.22), 0.08, 0.07, 0.03,
		"False chanterelle", false, "funnel"],
	"jack_o_lantern": [Effect.POISON, 0, Color(1.0, 0.58, 0.12), Color(1.0, 0.62, 0.2), 0.09, 0.08, 0.03,
		"Jack-o'-lantern", false, "funnel"],
	# Moon caps (made up): the trippy one and its toxic twin.
	"moon_cap": [Effect.TRIP, 28, Color(0.75, 0.85, 1.0), Color(0.88, 0.9, 0.95), 0.09, 0.16, 0.022,
		"Moon cap", true, "tall"],
	"false_moon_cap": [Effect.POISON, 0, Color(0.72, 0.84, 1.0), Color(0.86, 0.9, 0.96), 0.09, 0.16, 0.022,
		"False moon cap", true, "tall"],
	# The crazy ones.
	"glowcap": [Effect.TRIP, 30, Color(0.2, 0.95, 1.0), Color(0.6, 0.9, 1.0), 0.1, 0.18, 0.025,
		"Glowcap", true, "tall"],
	"rainbow_bolete": [Effect.STRONG, 45, Color(0.9, 0.2, 0.85), Color(0.3, 0.9, 0.4), 0.15, 0.14, 0.06,
		"Rainbow bolete", true, "dome"],
	"golden_chanterelle": [Effect.FOOD, 60, Color(1.0, 0.9, 0.3), Color(1.0, 0.95, 0.6), 0.09, 0.08, 0.03,
		"Golden chanterelle", true, "funnel"],
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
		"Drowned chanterelle", true, "funnel"],
}

## The details you have to look for. gills: colour of the underside; style: "blade" (thin gills),
## "ridges" (shallow forked ridges running down the stem), "pores" (sponge). ring/volva: bools.
## net: colour of a net pattern on the stem (or none). scales: colour of flakes on the cap (or none).
## bruise: colour it turns where you handle it (or none).
const FEATURES := {
	"porcini": {"gills": Color(0.95, 0.93, 0.85), "style": "pores", "net": Color(0.97, 0.95, 0.9)},
	"bitter_bolete": {"gills": Color(0.95, 0.75, 0.75), "style": "pores", "net": Color(0.3, 0.2, 0.12)},
	"satans_bolete": {"gills": Color(0.85, 0.2, 0.15), "style": "pores", "net": Color(0.7, 0.15, 0.1),
		"bruise": Color(0.2, 0.3, 0.8)},
	"field_mushroom": {"gills": Color(0.9, 0.55, 0.6), "style": "blade", "ring": true},
	"yellow_stainer": {"gills": Color(0.85, 0.82, 0.8), "style": "blade", "ring": true,
		"bruise": Color(1.0, 0.85, 0.1)},
	"death_cap": {"gills": Color(0.98, 0.98, 0.96), "style": "blade", "ring": true, "volva": true},
	"parasol": {"gills": Color(0.97, 0.96, 0.92), "style": "blade", "ring": true, "net": Color(0.45, 0.35, 0.25),
		"scales": Color(0.45, 0.32, 0.2)},
	"shaggy_parasol": {"gills": Color(0.97, 0.95, 0.9), "style": "blade", "ring": true,
		"scales": Color(0.5, 0.35, 0.22), "bruise": Color(0.85, 0.35, 0.2)},
	"dapperling": {"gills": Color(0.97, 0.96, 0.92), "style": "blade", "scales": Color(0.45, 0.3, 0.18)},
	"chanterelle": {"gills": Color(1.0, 0.78, 0.25), "style": "ridges"},
	"false_chanterelle": {"gills": Color(1.0, 0.5, 0.1), "style": "blade"},
	"jack_o_lantern": {"gills": Color(1.0, 0.6, 0.15), "style": "blade", "net": Color(0.85, 0.45, 0.1)},
	"moon_cap": {"gills": Color(0.97, 0.97, 1.0), "style": "blade", "ring": true},
	"false_moon_cap": {"gills": Color(0.4, 0.55, 1.0), "style": "blade", "ring": true},
	"glowcap": {"gills": Color(0.4, 0.9, 1.0), "style": "blade"},
	"rainbow_bolete": {"gills": Color(1.0, 0.9, 0.2), "style": "pores", "net": Color(0.9, 0.3, 0.9)},
	"golden_chanterelle": {"gills": Color(1.0, 0.92, 0.4), "style": "ridges"},
	"devils_cigar": {"gills": Color(0.2, 0.1, 0.06), "style": "blade", "volva": true},
	"kobold_cap": {"gills": Color(0.7, 0.9, 0.3), "style": "blade"},
	"drowned_chanterelle": {"gills": Color(0.3, 0.8, 0.75), "style": "ridges"},
}

## What the field guide says to look for (sketchy notes), once Babka has named the species.
const TELLS := {
	"porcini": "pale net on the stem, white pores", "bitter_bolete": "DARK net on the stem, pinkish pores",
	"satans_bolete": "red stem with a red net, bruises blue",
	"field_mushroom": "pink gills, a ring, NO cup at the base", "yellow_stainer": "grey-white gills, bruises YELLOW",
	"death_cap": "white gills, a ring AND a cup at the base",
	"parasol": "huge, snakeskin stem, a ring", "shaggy_parasol": "shorter, shaggy scales, bruises orange-red",
	"dapperling": "small, no ring",
	"chanterelle": "ridges running down the stem, not gills", "false_chanterelle": "real thin gills, more orange",
	"jack_o_lantern": "real gills, orange net on the stem",
	"moon_cap": "white gills under the cap", "false_moon_cap": "BLUE gills under the cap",
}

## How often each kind spawns (rarer = smaller).
const WEIGHTS := {
	"porcini": 8, "bitter_bolete": 6, "satans_bolete": 5, "field_mushroom": 8, "yellow_stainer": 5, "death_cap": 6,
	"parasol": 7, "shaggy_parasol": 5, "dapperling": 4, "chanterelle": 8, "false_chanterelle": 5,
	"jack_o_lantern": 4, "moon_cap": 4, "false_moon_cap": 4, "glowcap": 5, "rainbow_bolete": 3,
	"golden_chanterelle": 2, "screaming_puffball": 5, "devils_cigar": 4, "witch_finger": 4,
}
const BRUISE_SECONDS := 4.0

signal tasted(peer_id: int)

var kind := "porcini"
var effect := Effect.FOOD
var price := 0
var display_name := ""
var bruise := 0.0  # 0..1, how much it has turned from being handled (every peer, from holder_id)
var _hits := 0
var _visual: Node3D


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


## What you can tell just by looking: "a round-capped mushroom, white". Look-alikes read the same;
## inspect them (right mouse) for the details. Names are Babka's job.
static func describe(mushroom_kind: String) -> String:
	var k: Array = KINDS[mushroom_kind]
	var shape: String = {"dome": "round-capped", "flat": "flat-capped", "tall": "pointy", "ball": "ball-shaped",
		"finger": "finger-shaped", "funnel": "funnel-shaped"}[k[9]]
	var size := "small" if k[4] < 0.09 else ("big" if k[4] > 0.15 else "")
	var glow := ", glowing" if k[8] else ""
	return ("a %s %s mushroom, %s%s" % [size, shape, _colour_word(k[2]), glow]).replace("  ", " ")


## The name if Babka Hela has told you, else a description.
static func label_of(mushroom_kind: String) -> String:
	return name_of(mushroom_kind) if Team.known.has(mushroom_kind) else describe(mushroom_kind)


static func tell_of(mushroom_kind: String) -> String:
	return TELLS.get(mushroom_kind, "")


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
		return "pale blue" if c.s < 0.4 else "blue"
	return "purple" if h < 300.0 else "pink"


## Villagers buy food and the fun ones (Babka knows them all).
static func sellable(mushroom_kind: String) -> bool:
	var e: int = KINDS[mushroom_kind][0]
	return e == Effect.FOOD or e == Effect.TRIP or e == Effect.STRONG


## The whole mushroom as a model, with every detail (gills, ring, cup, net, scales). Used for the
## prop itself and for the close-up copy when you inspect one. Origin = middle of the stem.
## `detailed` builds every gill and flake (for inspecting); the hundreds of mushrooms lying in the
## forest get a cheap underside in the gill colour instead.
static func make_visual(mushroom_kind: String, detailed := false) -> Node3D:
	var k: Array = KINDS[mushroom_kind]
	var f: Dictionary = FEATURES.get(mushroom_kind, {})
	var cap_colour: Color = k[2]
	var stem_colour: Color = k[3]
	var cap_r: float = k[4]
	var stem_h: float = k[5]
	var stem_r: float = k[6]
	var glow: bool = k[8]
	var shape_kind: String = k[9]
	var root := Node3D.new()
	root.name = "Visual"

	# Stem, with a net pattern if it has one.
	var stem := MeshInstance3D.new()
	var stem_mesh := CylinderMesh.new()
	stem_mesh.top_radius = stem_r * (1.6 if shape_kind == "funnel" else 1.0)
	stem_mesh.bottom_radius = stem_r * (0.8 if shape_kind == "funnel" else 1.25)
	stem_mesh.height = stem_h
	stem_mesh.radial_segments = 12
	stem_mesh.rings = 2
	stem.mesh = stem_mesh
	var stem_mat := StandardMaterial3D.new()
	stem_mat.albedo_color = stem_colour
	if f.has("net"):
		stem_mat.albedo_texture = _net_texture(stem_colour, f["net"])
		stem_mat.uv1_scale = Vector3(3, 2, 1)
	stem.material_override = stem_mat
	stem.name = "Stem"
	root.add_child(stem)

	# Cap.
	var cap := MeshInstance3D.new()
	match shape_kind:
		"flat":
			var m := CylinderMesh.new()
			m.top_radius = cap_r * 0.35
			m.bottom_radius = cap_r
			m.height = cap_r * 0.35
			m.radial_segments = 16
			m.rings = 1
			cap.mesh = m
		"tall", "finger":
			var m := CylinderMesh.new()
			m.top_radius = 0.0 if shape_kind == "tall" else cap_r * 0.6
			m.bottom_radius = cap_r
			m.height = cap_r * (2.6 if shape_kind == "tall" else 2.0)
			m.radial_segments = 12
			m.rings = 1
			cap.mesh = m
		"funnel":
			var m := CylinderMesh.new()
			m.top_radius = cap_r
			m.bottom_radius = cap_r * 0.4
			m.height = cap_r * 0.6
			m.radial_segments = 14
			m.rings = 1
			cap.mesh = m
		"ball":
			var m := SphereMesh.new()
			m.radius = cap_r
			m.height = cap_r * 1.8
			m.radial_segments = 14
			m.rings = 7
			cap.mesh = m
		_:
			var m := SphereMesh.new()
			m.radius = cap_r
			m.height = cap_r * 1.1
			m.is_hemisphere = true
			m.radial_segments = 16
			m.rings = 6
			cap.mesh = m
	cap.position.y = stem_h / 2.0
	var cap_mat := StandardMaterial3D.new()
	cap_mat.albedo_color = cap_colour
	if glow:
		cap_mat.emission_enabled = true
		cap_mat.emission = cap_colour
		cap_mat.emission_energy_multiplier = 1.4
	cap.material_override = cap_mat
	cap.name = "Cap"
	root.add_child(cap)

	if shape_kind == "ball":
		return root

	# Underside: gills / ridges / pores, in their colour.
	var under_y := stem_h / 2.0 - (0.004 if shape_kind != "funnel" else -cap_r * 0.28)
	var gill_mat := StandardMaterial3D.new()
	gill_mat.albedo_color = f.get("gills", cap_colour.darkened(0.2))
	var style: String = f.get("style", "blade")
	if style == "pores" or not detailed:
		var disc := MeshInstance3D.new()
		var d := CylinderMesh.new()
		d.top_radius = cap_r * 0.95
		d.bottom_radius = cap_r * 0.95
		d.height = 0.006
		d.radial_segments = 16
		d.rings = 1
		disc.mesh = d
		disc.material_override = gill_mat
		disc.position.y = under_y
		root.add_child(disc)
	else:
		var count := 28 if style == "blade" else 10
		var reach := cap_r * (0.95 if style == "blade" else 0.9)
		for i in count:
			var gill := MeshInstance3D.new()
			var box := BoxMesh.new()
			if style == "blade":
				box.size = Vector3(0.0025, cap_r * 0.18, reach - stem_r)
			else:
				box.size = Vector3(0.006, cap_r * 0.08, reach - stem_r * 0.5)
			gill.mesh = box
			gill.material_override = gill_mat
			var a := i * TAU / count
			var mid := (reach + stem_r) / 2.0
			gill.position = Vector3(sin(a) * mid, under_y - box.size.y / 2.0, cos(a) * mid)
			gill.rotation.y = a
			if style == "ridges":
				gill.rotation.x = 0.5  # running down the stem
				gill.position.y -= cap_r * 0.12
			root.add_child(gill)

	# Ring on the stem.
	if f.get("ring", false):
		var ring := MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.inner_radius = stem_r * 1.05
		torus.outer_radius = stem_r * 1.7
		torus.rings = 12
		torus.ring_segments = 5
		ring.mesh = torus
		var ring_mat := StandardMaterial3D.new()
		ring_mat.albedo_color = stem_colour.lightened(0.1)
		ring.material_override = ring_mat
		ring.scale.y = 0.6
		ring.position.y = stem_h * 0.22
		root.add_child(ring)

	# Cup (volva) at the base: half-buried, look carefully.
	if f.get("volva", false):
		var cup := MeshInstance3D.new()
		var c := CylinderMesh.new()
		c.top_radius = stem_r * 2.0
		c.bottom_radius = stem_r * 1.4
		c.height = stem_h * 0.18
		c.radial_segments = 12
		c.rings = 1
		c.cap_top = false
		cup.mesh = c
		var cup_mat := StandardMaterial3D.new()
		cup_mat.albedo_color = Color(0.93, 0.92, 0.88)
		cup_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		cup.material_override = cup_mat
		cup.position.y = -stem_h / 2.0 + c.height / 2.0
		root.add_child(cup)

	# Scales / flakes on the cap.
	if f.has("scales"):
		var flake_mat := StandardMaterial3D.new()
		flake_mat.albedo_color = f["scales"]
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(mushroom_kind)
		for i in (18 if detailed else 5):
			var flake := MeshInstance3D.new()
			var b := BoxMesh.new()
			b.size = Vector3(cap_r * 0.12, 0.003, cap_r * 0.08)
			flake.mesh = b
			flake.material_override = flake_mat
			var a := rng.randf() * TAU
			var r := sqrt(rng.randf()) * cap_r * 0.85
			var top := cap_r * 0.35 if shape_kind == "flat" else sqrt(maxf(cap_r * cap_r - r * r, 0.0)) * 1.1
			flake.position = Vector3(cos(a) * r, stem_h / 2.0 + top * (0.95 if shape_kind != "flat" else 1.0), sin(a) * r)
			flake.rotation.y = rng.randf() * TAU
			root.add_child(flake)
	return root


## A little net texture for stems (cached per colour pair).
static var _nets := {}


static func _net_texture(base: Color, line: Color) -> Texture2D:
	var key := "%s_%s" % [base.to_html(), line.to_html()]
	if _nets.has(key):
		return _nets[key]
	var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	for y in 16:
		for x in 16:
			var on := (x + y) % 8 == 0 or (x - y + 16) % 8 == 0
			img.set_pixel(x, y, line if on else base)
	var tex := ImageTexture.create_from_image(img)
	_nets[key] = tex
	return tex


func setup_mushroom(prop_name: String, mushroom_kind: String) -> void:
	kind = mushroom_kind
	var k: Array = KINDS[kind]
	effect = k[0]
	price = k[1]
	display_name = k[7]
	var cap_radius: float = k[4]
	var stem_height: float = k[5]
	var stem_radius: float = k[6]
	var stem := CylinderMesh.new()
	stem.top_radius = stem_radius
	stem.bottom_radius = stem_radius
	stem.height = stem_height
	var shape := BoxShape3D.new()
	shape.size = Vector3(maxf(cap_radius, stem_radius) * 2.0, stem_height + cap_radius * 0.6, maxf(cap_radius, stem_radius) * 2.0)
	setup(prop_name, stem, shape, k[3], 0.2)
	for child in get_children():
		if child is MeshInstance3D:
			child.visible = false  # the detailed visual replaces the plain stem
	_visual = make_visual(kind)
	add_child(_visual)


## Every peer: handled mushrooms bruise (some species change colour where you hold them).
func _process(delta: float) -> void:
	var colour = FEATURES.get(kind, {}).get("bruise")
	if colour == null or _visual == null:
		return
	var target := 1.0 if holder_id != 0 else bruise
	bruise = move_toward(bruise, target, delta / BRUISE_SECONDS)
	apply_bruise(_visual, kind, bruise)


## Tint a mushroom visual by how bruised it is (also used on the inspect copy).
static func apply_bruise(visual: Node3D, mushroom_kind: String, amount: float) -> void:
	var colour = FEATURES.get(mushroom_kind, {}).get("bruise")
	if colour == null:
		return
	var k: Array = KINDS[mushroom_kind]
	var stem: MeshInstance3D = visual.get_node_or_null("Stem")
	var cap: MeshInstance3D = visual.get_node_or_null("Cap")
	if stem:
		(stem.material_override as StandardMaterial3D).albedo_color = (k[3] as Color).lerp(colour, amount * 0.7)
	if cap:
		(cap.material_override as StandardMaterial3D).albedo_color = (k[2] as Color).lerp(colour, amount * 0.35)


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
	bruise = 0.0


## Every peer: a little puff of mushroom bits where it broke (visual only).
@rpc("authority", "call_local", "reliable")
func _shatter(at: Vector3, cap_colour: Color) -> void:
	Sfx.play("mushroom_break", at)
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
