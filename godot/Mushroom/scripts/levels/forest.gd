extends "res://scripts/levels/level.gd"
## The world of Mushroom Foraging. Four friends lost their jobs and now live in a junk camp in
## the forest. Every day they pick weird mushrooms, taste them to find out which are safe, and
## sell the safe ones in the village. Cash buys medkits, batteries, a house, and casino spins.
## Night gets properly dark (flashlights, boars). Dead friends can be brought back by the witch.
##
## A round is one day: PREP is the morning, LIVE the day sliding into night, WRAP the night recap.
## The whole map comes from a fixed seed, so every peer builds the same world.

const Terrain := preload("res://scripts/world/terrain.gd")
const MushroomScript := preload("res://scripts/mushroom.gd")
const BasketScript := preload("res://scripts/basket.gd")
const OldSlotScript := preload("res://scripts/old_slot.gd")
const CarScript := preload("res://scripts/car.gd")
const BoarScript := preload("res://scripts/boar.gd")
const InteractableScript := preload("res://scripts/interactable.gd")
const PlayerScript := preload("res://scripts/player.gd")

const K := "res://assets/kenney/"
const NATURE := K + "nature-kit/"
const SEED := 20261001
const MUSHROOM_COUNT := 160
const BOAR_COUNT := 7
const WITCH_RECIPE := {"witch_finger": 2, "glowcap": 1}
const SELL_RANGE := 7.0

## Scattered scenery: [model, count, height range, collider radius (0 = walk through)]
const FOREST := [
	["tree_pineTallA.glb", 70, Vector2(8, 13), 0.35], ["tree_pineTallB.glb", 70, Vector2(8, 13), 0.35],
	["tree_pineTallC.glb", 60, Vector2(7, 12), 0.35], ["tree_pineTallD.glb", 60, Vector2(7, 12), 0.35],
	["tree_pineRoundB.glb", 50, Vector2(6, 10), 0.35], ["tree_pineDefaultA.glb", 50, Vector2(6, 9), 0.3],
	["tree_pineDefaultB.glb", 50, Vector2(6, 9), 0.3], ["tree_pineSmallA.glb", 50, Vector2(2.5, 4), 0.2],
	["tree_default.glb", 45, Vector2(6, 9), 0.35], ["tree_oak.glb", 40, Vector2(7, 10), 0.45],
	["tree_fat.glb", 30, Vector2(5, 8), 0.45], ["tree_tall.glb", 40, Vector2(8, 12), 0.3],
	["tree_thin.glb", 40, Vector2(6, 9), 0.25], ["tree_cone.glb", 30, Vector2(5, 8), 0.3],
	["tree_simple.glb", 30, Vector2(5, 8), 0.3], ["tree_small.glb", 40, Vector2(2.5, 4), 0.2],
	["tree_default_dark.glb", 40, Vector2(6, 9), 0.35], ["tree_oak_fall.glb", 25, Vector2(7, 10), 0.45],
	["plant_bushLarge.glb", 140, Vector2(1.0, 1.6), 0.0], ["plant_bushDetailed.glb", 140, Vector2(0.7, 1.2), 0.0],
	["plant_bushSmall.glb", 160, Vector2(0.4, 0.8), 0.0], ["plant_flatTall.glb", 220, Vector2(0.6, 1.1), 0.0],
	["plant_flatShort.glb", 220, Vector2(0.3, 0.6), 0.0], ["grass.glb", 400, Vector2(0.3, 0.6), 0.0],
	["grass_leafs.glb", 300, Vector2(0.3, 0.6), 0.0], ["flower_purpleA.glb", 90, Vector2(0.3, 0.5), 0.0],
	["flower_redA.glb", 90, Vector2(0.3, 0.5), 0.0], ["flower_yellowA.glb", 90, Vector2(0.3, 0.5), 0.0],
	["rock_tallA.glb", 40, Vector2(1.2, 2.6), 0.7], ["rock_smallA.glb", 120, Vector2(0.3, 0.6), 0.0],
	["stone_largeA.glb", 50, Vector2(0.8, 1.6), 0.8], ["stone_tallB.glb", 25, Vector2(1.5, 3.0), 0.6],
	["log.glb", 70, Vector2(0.4, 0.6), 0.0], ["stump_round.glb", 60, Vector2(0.4, 0.7), 0.35],
]

var _sun: DirectionalLight3D
var _env: Environment
var _night := false
var _night_lights: Array[Light3D] = []
var _mushrooms: Array = []
var _boars: Array = []
var _corpses := {}  # peer id -> Node3D
var _house: Node3D
var _basket: RigidBody3D
var _car: VehicleBody3D
var _camp_fire: OmniLight3D
var _rng := RandomNumberGenerator.new()
var _started := false
var spawn_override := ""  # testing: spawn at a named place instead of camp


func _ready() -> void:
	_add_overview(Vector3(22, 16, 30), Vector3(0, 0, 0))
	_sun = DirectionalLight3D.new()
	_sun.shadow_enabled = true
	_sun.directional_shadow_max_distance = 60.0
	add_child(_sun)
	add_child(Terrain.build())
	_build_water()
	_rng.seed = SEED
	_scatter_forest()
	_build_camp()
	_build_village()
	_build_casino()
	_build_witch()
	_build_ruin()
	_build_signs()
	_build_mushrooms()
	_build_animals()
	for light in _night_lights:
		light.visible = false
	Team.died.connect(_on_died)
	Team.revived.connect(_on_revived)
	Team.changed.connect(_on_team_changed)


# --- show rules ----------------------------------------------------------------------


func title() -> String:
	return "The forest"


func score_name() -> String:
	return "CASH"


func start_score() -> float:
	return float(Team.cash)


func prep_duration() -> float:
	return 25.0


func live_duration() -> float:
	return 600.0


func wrap_duration() -> float:
	return 20.0


func spawn_point(index: int) -> Vector3:
	var angle := index * TAU / 8.0 + 0.4
	var centre := Terrain.place_centre(spawn_override) if spawn_override != "" else Vector3.ZERO
	var x := centre.x + cos(angle) * 4.5
	var z := centre.z + sin(angle) * 4.5 + (12.0 if spawn_override != "" else 0.0)
	return Vector3(x, Terrain.height(x, z) + 0.5, z)


func make_environment() -> Environment:
	_env = Environment.new()
	_env.background_mode = Environment.BG_COLOR
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_env.fog_enabled = true
	_env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	_apply_daylight(0.0)
	return _env


func server_tick(_delta: float, director: Node) -> void:
	director.score = float(Team.cash)


func server_reset() -> void:
	# A new morning (not the very first one): the forest regrows somewhere else.
	if _started:
		Team.next_day()
	_started = true
	for m in _mushrooms:
		m.reset_to_home()
		m.position = _mushroom_spot()
		m.rotation.y = _rng.randf() * TAU
	for prop in find_children("*", "RigidBody3D", true, false):
		if prop.has_method("reset_to_home") and not prop is MushroomScript:
			prop.reset_to_home()


func apply_state(phase: int, _event: int, _sub: int, time_left: float) -> void:
	var t := 0.0  # 0 = morning, 1 = midnight
	if phase == Phase.LIVE:
		t = clampf(1.0 - time_left / live_duration(), 0.0, 1.0)
	elif phase == Phase.WRAP:
		t = 1.0
	_apply_daylight(t)
	var night := t > 0.68
	if night != _night:
		_night = night
		for light in _night_lights:
			light.visible = night
		for boar in _boars:
			boar.night = night


func phase_text(phase: int, clock: String, _score: float, _sub: int) -> String:
	match phase:
		Phase.PREP:
			return "DAY %d  -  morning at camp  -  %s" % [Team.day, clock]
		Phase.LIVE:
			return "DAY %d  -  %s until midnight" % [Team.day, clock]
	return "NIGHT %d  -  get back to camp" % Team.day


func guide_text() -> String:
	var lines := ["FIELD JOURNAL (J)"]
	for k in MushroomScript.KINDS:
		if Team.known.has(k):
			var e: int = MushroomScript.KINDS[k][0]
			var what: String = ["food", "trippy", "VERY trippy", "POISON", "witchy"][e]
			var worth := "%d €" % MushroomScript.price_of(k) if MushroomScript.sellable(k) else "worthless"
			lines.append("%s: %s, %s" % [MushroomScript.name_of(k), what, worth])
	if lines.size() == 1:
		lines.append("Nothing identified yet. Somebody has to taste one...")
	return "\n".join(lines)


# --- daylight ------------------------------------------------------------------------


func _apply_daylight(t: float) -> void:
	# Day until ~0.5, sunset to ~0.68, then night.
	var day := 1.0 - smoothstep(0.45, 0.7, t)
	var sunset := smoothstep(0.35, 0.58, t) * (1.0 - smoothstep(0.6, 0.72, t))
	if _sun:
		_sun.rotation = Vector3(lerpf(-1.1, -0.05, smoothstep(0.0, 0.7, t)), 0.7, 0.0)
		_sun.light_energy = lerpf(0.0, 0.95, day)
		_sun.light_color = Color(1, 0.96, 0.88).lerp(Color(1, 0.62, 0.4), sunset * 0.7)
		_sun.visible = day > 0.01
	if _env:
		var sky := Color(0.55, 0.7, 0.85).lerp(Color(0.85, 0.55, 0.4), sunset * 0.6)
		sky = sky.lerp(Color(0.01, 0.012, 0.025), 1.0 - day)
		_env.background_color = sky
		_env.ambient_light_color = Color(0.85, 0.85, 0.8).lerp(Color(0.25, 0.3, 0.5), 1.0 - day)
		_env.ambient_light_energy = lerpf(0.03, 0.32, day)
		_env.fog_light_color = Color(0.6, 0.68, 0.72).lerp(sky, 0.5)
		_env.fog_density = lerpf(0.03, 0.0035, day)


# --- people coming and going ------------------------------------------------------------


func _on_died(peer_id: int, reason: String) -> void:
	var player := _player(peer_id)
	var player_name: String = Team.players[peer_id]["name"] if Team.players.has(peer_id) else "Somebody"
	get_tree().call_group("hud", "show_toast", "%s died of %s." % [player_name, reason])
	if multiplayer.is_server() and _car.seat_of(peer_id) >= 0:
		_car.leave(peer_id)
	if player == null:
		return
	var corpse := ModelFit.fit(
		"res://assets/kenney/mini-characters/character-%s.glb" % PlayerScript.CHARACTERS[player.variant % PlayerScript.CHARACTERS.size()],
		Vector3(1.2, 1.7, 1.2),
		0.0
	)
	corpse.rotation = Vector3(-PI / 2.0, player.rotation.y, 0)
	corpse.position = player.global_position + Vector3(0, 0.35, 0)
	var tag := Label3D.new()
	tag.text = "RIP %s" % player_name
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.pixel_size = 0.004
	tag.font_size = 40
	tag.position = player.global_position + Vector3(0, 1.0, 0)
	var holder := Node3D.new()
	holder.add_child(corpse)
	holder.add_child(tag)
	add_child(holder)
	if _corpses.has(peer_id):
		_corpses[peer_id].queue_free()
	_corpses[peer_id] = holder


func _on_revived(peer_id: int) -> void:
	if _corpses.has(peer_id):
		_corpses[peer_id].queue_free()
		_corpses.erase(peer_id)
	var player := _player(peer_id)
	if player and player.is_multiplayer_authority():
		player.global_position = Terrain.place_centre("witch") + Vector3(3, 1.0, 3)
	var player_name: String = Team.players[peer_id]["name"] if Team.players.has(peer_id) else "Somebody"
	get_tree().call_group("hud", "show_toast", "The witch cackles. %s crawls out of the mud, alive!" % player_name)


func _on_team_changed() -> void:
	if Team.house and _house == null:
		_house = Node3D.new()
		var model := ModelFit.fit(K + "city-kit-suburban/building-type-c.glb", Vector3(9, 7, 9), PI / 2.0)
		model.position.y += 3.5
		_house.add_child(model)
		_house.position = Vector3(-12, Terrain.height(-12, 8), 8)
		add_child(_house)


func _player(peer_id: int) -> Node3D:
	for p in get_tree().get_nodes_in_group("players"):
		if p.peer_id == peer_id:
			return p
	return null


# --- building: the ground and the forest ------------------------------------------------


func _build_water() -> void:
	var lake_c: Vector2 = Terrain.LAKE[0]
	var mesh := PlaneMesh.new()
	mesh.size = Vector2.ONE * Terrain.LAKE[1] * 2.8
	var water := MeshInstance3D.new()
	water.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.15, 0.35, 0.45, 0.78)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.roughness = 0.1
	mat.metallic = 0.3
	water.material_override = mat
	water.position = Vector3(lake_c.x, Terrain.WATER_Y, lake_c.y)
	add_child(water)
	for i in 14:
		var a := _rng.randf() * TAU
		var r := _rng.randf_range(4.0, Terrain.LAKE[1] * 0.7)
		var p := Vector3(lake_c.x + cos(a) * r, Terrain.WATER_Y + 0.02, lake_c.y + sin(a) * r)
		_model(NATURE + ("lily_large.glb" if i % 2 else "lily_small.glb"), Vector3(1.2, 0.1, 1.2), p, _rng.randf() * TAU)
	_model(NATURE + "canoe.glb", Vector3(1.0, 0.5, 3.6), Vector3(lake_c.x - 30, Terrain.WATER_Y + 0.1, lake_c.y + 10), 0.6)


## Hundreds of trees and plants as one MultiMesh per model (cheap to draw), plus trunk colliders.
func _scatter_forest() -> void:
	var trunks := StaticBody3D.new()
	trunks.name = "Trunks"
	add_child(trunks)
	for entry in FOREST:
		var info := _mesh_info(NATURE + entry[0])
		if info.is_empty():
			continue
		var mesh: Mesh = info[0]
		var local: Transform3D = info[1]
		var aabb: AABB = info[2]
		var transforms: Array[Transform3D] = []
		var tries := 0
		while transforms.size() < entry[1] and tries < entry[1] * 20:
			tries += 1
			var x := _rng.randf_range(-Terrain.SIZE * 0.4, Terrain.SIZE * 0.4)
			var z := _rng.randf_range(-Terrain.SIZE * 0.4, Terrain.SIZE * 0.4)
			var big: bool = entry[3] > 0.0
			if not Terrain.is_clear(x, z, 0.0 if big else -3.0):
				continue
			var h := Terrain.height(x, z)
			if h < Terrain.WATER_Y + 0.3:
				continue
			var height: float = _rng.randf_range(entry[2].x, entry[2].y)
			var s := height / aabb.size.y
			var basis := Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3.ONE * s)
			var origin := Vector3(x, h - aabb.position.y * s - 0.05, z)
			transforms.append(Transform3D(basis, origin) * local)
			if big:
				var shape := CylinderShape3D.new()
				shape.radius = entry[3] * clampf(height / 8.0, 0.6, 1.4)
				shape.height = minf(height, 4.0)
				var col := CollisionShape3D.new()
				col.shape = shape
				col.position = Vector3(x, h + shape.height / 2.0, z)
				trunks.add_child(col)
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mesh
		mm.instance_count = transforms.size()
		for i in transforms.size():
			mm.set_instance_transform(i, transforms[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		if entry[3] == 0.0:
			mmi.visibility_range_end = 70.0  # small stuff fades out in the distance
		add_child(mmi)


## The first mesh in a model, its transform inside the model, and its bounds in model space.
func _mesh_info(path: String) -> Array:
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


# --- building: places ----------------------------------------------------------------------


func _build_camp() -> void:
	var c := Terrain.place_centre("camp")
	_sign("JUNK CAMP\nhome sweet home", c + Vector3(0, 3.2, -9), 72)
	var sk := K + "survival-kit/"
	_solid(NATURE + "tent_smallOpen.glb", Vector3(3.0, 2.0, 3.0), c + Vector3(-7, 0, -5), 0.9)
	_solid(NATURE + "tent_smallOpen.glb", Vector3(3.4, 2.3, 3.4), c + Vector3(-1, 0, -8), 0.1)
	_solid(NATURE + "tent_smallOpen.glb", Vector3(2.6, 1.8, 2.6), c + Vector3(6, 0, -6), -0.5)
	_model(sk + "campfire-pit.glb", Vector3(1.4, 0.5, 1.4), c + Vector3(0, 0, 0), 0.0)
	_camp_fire = _light(c + Vector3(0, 1.2, 0), 2.2, 14.0, Color(1.0, 0.6, 0.25))
	for i in 4:
		var a := i * TAU / 4.0 + 0.4
		_model(sk + "bedroll.glb", Vector3(0.9, 0.2, 2.0), c + Vector3(cos(a) * 2.6, 0, sin(a) * 2.6), -a)
	_solid(sk + "chest.glb", Vector3(1.0, 0.8, 0.7), c + Vector3(-4, 0, 3), 0.3)
	_solid(sk + "workbench.glb", Vector3(2.0, 1.0, 1.0), c + Vector3(3.5, 0, 4), 0.0)
	_solid(sk + "barrel.glb", Vector3(0.8, 1.1, 0.8), c + Vector3(8, 0, 2), 0.0)
	_solid(sk + "barrel.glb", Vector3(0.8, 1.1, 0.8), c + Vector3(8.9, 0, 2.6), 0.0)
	_solid(sk + "box-large.glb", Vector3(1.2, 1.0, 1.2), c + Vector3(-9, 0, 0), 0.2)
	_model(sk + "signpost.glb", Vector3(1.0, 2.2, 0.3), c + Vector3(11, 0, 2), -0.3)

	_basket = BasketScript.new()
	_basket.build(K + "mini-market/shopping-basket.glb")
	_basket.position = c + Vector3(3.5, 1.4, 4)
	add_child(_basket)

	_car = CarScript.new()
	_car.build(K + "car-kit/suv.glb")
	_car.position = c + Vector3(10, 1.0, -2)
	_car.rotation.y = PI / 2.0 + 0.2  # nose towards the road
	add_child(_car)

	var plot := InteractableScript.new()
	plot.configure("HousePlot", Vector3(1.2, 1.4, 0.3), Vector3(-9, c.y + 0.7, 8),
		"build a house here (%d €)" % Team.PRICES["house"], _use_house_plot)
	add_child(plot)
	_model(sk + "signpost.glb", Vector3(1.0, 1.4, 0.3), Vector3(-9, c.y, 8), 0.0)
	_sign("HOUSE PLOT\n%d €" % Team.PRICES["house"], Vector3(-9, c.y + 2.0, 8), 40)


func _build_village() -> void:
	var c := Terrain.place_centre("village")
	_sign("HORNÁ LEHOTA\n(village)", c + Vector3(-30, 6, 0), 96)
	var houses := ["a", "b", "d", "e", "f", "g", "h", "b", "e"]
	for i in houses.size():
		var a := i * TAU / houses.size() + 0.3
		var p := c + Vector3(cos(a) * 27, 0, sin(a) * 27)
		if i == 0:
			continue  # gap where the road comes in
		_solid(K + "city-kit-suburban/building-type-%s.glb" % houses[i], Vector3(8, 7, 8), p, -a - PI / 2.0)
	var ft := K + "fantasy-town-kit/"
	_solid(ft + "fountain-round.glb", Vector3(4, 1.6, 4), c, 0.0)
	_solid(ft + "stall-red.glb", Vector3(3, 2.6, 2), c + Vector3(-6, 0, 7), PI)
	_solid(ft + "stall-green.glb", Vector3(3, 2.6, 2), c + Vector3(7, 0, 7), PI)
	_solid(ft + "cart.glb", Vector3(1.6, 1.4, 2.6), c + Vector3(10, 0, -6), 0.6)
	for i in 6:
		var a := i * TAU / 6.0
		var p := c + Vector3(cos(a) * 12, 0, sin(a) * 12)
		_model(ft + "lantern.glb", Vector3(0.6, 2.6, 0.6), p, 0.0)
		_night_lights.append(_light(p + Vector3(0, 2.6, 0), 1.6, 12.0, Color(1.0, 0.8, 0.45)))

	# Babka Hela buys mushrooms at the red stall; Jano runs the shop at the green one.
	_npc("character-female-e", c + Vector3(-6, 0, 8.6), PI, "BABKA HELA\nbuys identified mushrooms")
	var buyer := InteractableScript.new()
	buyer.configure("Buyer", Vector3(3, 2, 1.2), c + Vector3(-6, 1, 6.6), "sell the basket to Babka Hela", _use_buyer)
	add_child(buyer)
	_npc("character-male-e", c + Vector3(7, 0, 8.6), PI, "JANO'S SHOP")
	var medkit := InteractableScript.new()
	medkit.configure("BuyMedkit", Vector3(1.4, 2, 1.2), c + Vector3(6.2, 1, 6.6),
		"buy a MEDKIT (%d €)" % Team.PRICES["medkit"], func(peer): _buy(peer, "medkit"))
	add_child(medkit)
	var battery := InteractableScript.new()
	battery.configure("BuyBattery", Vector3(1.4, 2, 1.2), c + Vector3(7.8, 1, 6.6),
		"buy a BATTERY (%d €)" % Team.PRICES["battery"], func(peer): _buy(peer, "battery"))
	add_child(battery)
	_sign("MEDKIT %d €   BATTERY %d €" % [Team.PRICES["medkit"], Team.PRICES["battery"]], c + Vector3(7, 3.3, 6.4), 40)
	_npc("character-male-f", c + Vector3(3, 0, -8), 0.5, "")
	_npc("character-female-f", c + Vector3(-8, 0, -4), 2.0, "")


func _build_casino() -> void:
	var c := Terrain.place_centre("casino")
	_solid(K + "city-kit-commercial/building-c.glb", Vector3(14, 12, 12), c + Vector3(0, 0, -8), 0.0)
	_model(K + "city-kit-commercial/detail-awning-wide.glb", Vector3(10, 1.2, 3), c + Vector3(0, 3.6, -1.4), 0.0)
	var neon := _sign("CASINO ROYALE\nZVOLEN", c + Vector3(0, 8.5, -1.8), 128)
	neon.modulate = Color(1.0, 0.3, 0.8)
	_night_lights.append(_light(c + Vector3(0, 5, 2), 2.5, 16.0, Color(1.0, 0.3, 0.8)))
	_light(c + Vector3(0, 3, 1), 1.0, 10.0, Color(1.0, 0.5, 0.9))
	for i in 3:
		var x := -4.0 + i * 4.0
		var p := c + Vector3(x, 0, 0)
		_model(K + "mini-arcade/gambling-machine.glb", Vector3(1.2, 2.0, 1.0), p, 0.0)
		var slot := InteractableScript.new()
		slot.configure("Slot%d" % i, Vector3(1.2, 2.0, 1.0), p + Vector3(0, 1.0, 0),
			"spin the slot machine (%d €)" % Team.PRICES["slot"], _use_slot)
		add_child(slot)
	_solid(K + "mini-arcade/vending-machine.glb", Vector3(1.2, 2.2, 1.0), c + Vector3(8, 0, -1), -0.3)
	_npc("character-employee", c + Vector3(-7, 0, 1), 0.4, "BOUNCER\n(no refunds)", K + "mini-arcade/")


func _build_witch() -> void:
	var c := Terrain.place_centre("witch")
	var gy := K + "graveyard-kit/"
	_sign("THE WITCH\nbrings back the dead", c + Vector3(0, 5, -8), 72)
	_solid(gy + "crypt.glb", Vector3(5, 5, 6), c + Vector3(0, 0, -10), 0.0)
	for i in 9:
		var a := _rng.randf() * TAU
		var r := _rng.randf_range(7, 15)
		var model := gy + ("gravestone-round.glb" if i % 2 else "gravestone-cross.glb")
		_solid(model, Vector3(0.9, 1.2, 0.3), c + Vector3(cos(a) * r, 0, sin(a) * r), _rng.randf() * TAU)
	for i in 6:
		var a := i * TAU / 6.0 + 0.2
		_solid(gy + "pine-crooked.glb", Vector3(3, 8, 3), c + Vector3(cos(a) * 17, 0, sin(a) * 17), a)
	_model(gy + "detail-bowl.glb", Vector3(1.6, 0.9, 1.6), c + Vector3(0, 0, -2), 0.0)
	_light(c + Vector3(0, 1.5, -2), 2.5, 10.0, Color(0.4, 1.0, 0.3))
	_model(gy + "fire-basket.glb", Vector3(0.7, 1.2, 0.7), c + Vector3(-3, 0, -3), 0.0)
	_model(gy + "fire-basket.glb", Vector3(0.7, 1.2, 0.7), c + Vector3(3, 0, -3), 0.0)
	_model(gy + "candle-multiple.glb", Vector3(0.6, 0.5, 0.6), c + Vector3(1.4, 0, -0.6), 0.0)
	_model(gy + "pumpkin-carved.glb", Vector3(0.6, 0.6, 0.6), c + Vector3(-1.6, 0, -0.8), 0.6)
	_npc("character-keeper", c + Vector3(0, 0, -4), 0.0,
		"THE WITCH\n2 Witch's fingers + 1 Glowcap\nin the basket = one dead friend back", gy)
	var cauldron := InteractableScript.new()
	cauldron.configure("Cauldron", Vector3(1.8, 1.2, 1.8), c + Vector3(0, 0.6, -2),
		"ask the witch to revive your dead (basket nearby)", _use_cauldron)
	add_child(cauldron)


func _build_ruin() -> void:
	var c := Terrain.place_centre("ruin")
	_solid(NATURE + "statue_column.glb", Vector3(1, 4, 1), c + Vector3(-4, 0, -3), 0.0)
	_solid(NATURE + "statue_columnDamaged.glb", Vector3(1, 2.5, 1), c + Vector3(4, 0, -3), 0.0)
	_solid(NATURE + "statue_block.glb", Vector3(1.6, 1, 1.6), c + Vector3(-3, 0, 4), 0.4)
	_solid(NATURE + "statue_columnDamaged.glb", Vector3(1, 2, 1), c + Vector3(4, 0, 4), 1.0)
	var slot := OldSlotScript.new()
	var size := Vector3(1.0, 1.7, 0.9)
	var mesh := BoxMesh.new()
	mesh.size = size
	var shape := BoxShape3D.new()
	shape.size = size
	slot.setup("OLD_SLOT", mesh, shape, Color(0.4, 0.35, 0.3), 25.0)
	_dress(slot, K + "mini-arcade/gambling-machine.glb", size)
	slot.position = c + Vector3(0, size.y / 2.0 + 0.1, 0)
	add_child(slot)


func _build_signs() -> void:
	_sign("→ VILLAGE\n→ CASINO", Vector3(58, Terrain.height(58, 8) + 2.5, 8), 48)
	_sign("CASINO ↓", Vector3(118, Terrain.height(118, 22) + 2.5, 22), 48)
	_sign("→ the witch\n(don't)", Vector3(-38, Terrain.height(-38, -32) + 2.2, -32), 44)
	_sign("→ old ruin", Vector3(-30, Terrain.height(-30, 50) + 2.2, 50), 44)
	_sign("→ lake", Vector3(30, Terrain.height(30, -52) + 2.2, -52), 44)
	_sign("CLIFF\ncareful", Vector3(-95, Terrain.height(-95, 60) + 2.5, 60), 44)


func _build_mushrooms() -> void:
	var kind_rng := RandomNumberGenerator.new()
	kind_rng.seed = SEED + 7
	for i in MUSHROOM_COUNT:
		var mushroom := MushroomScript.new()
		mushroom.setup_mushroom("Mushroom_%d" % i, MushroomScript.pick_kind(kind_rng))
		mushroom.position = _mushroom_spot()
		mushroom.rotation.y = _rng.randf() * TAU
		add_child(mushroom)
		_mushrooms.append(mushroom)


## Somewhere in the woods, not on roads, not in the lake, not in town.
func _mushroom_spot() -> Vector3:
	for i in 50:
		var x := _rng.randf_range(-Terrain.SIZE * 0.38, Terrain.SIZE * 0.38)
		var z := _rng.randf_range(-Terrain.SIZE * 0.38, Terrain.SIZE * 0.38)
		if Vector2(x, z).length() < 25.0 or not Terrain.is_clear(x, z, -2.0):
			continue
		var h := Terrain.height(x, z)
		if h > Terrain.WATER_Y + 0.5:
			return Vector3(x, h + 0.3, z)
	return Vector3(30, Terrain.height(30, 30) + 0.3, 30)


func _build_animals() -> void:
	for i in BOAR_COUNT:
		var boar := BoarScript.new()
		boar.name = "Boar%d" % i
		var home := _mushroom_spot()
		boar.build(K + "cube-pets/animal-hog.glb", home, SEED + i)
		add_child(boar)
		_boars.append(boar)


# --- uses (host) ---------------------------------------------------------------------------


func _buy(peer: int, item: String) -> void:
	var price: int = Team.PRICES[item]
	if Team.cash < price:
		Team.tell(peer, "Jano: \"%d € or get out.\" (team cash: %d €)" % [price, Team.cash])
		return
	Team.add_cash(-price)
	Team.give(peer, item)
	Team.tell(peer, "Bought a %s. (H uses a medkit, T is the flashlight)" % item)


func _use_buyer(peer: int) -> void:
	var c := Terrain.place_centre("village") + Vector3(-6, 0, 6)
	if _basket.global_position.distance_to(c) > SELL_RANGE:
		Team.tell(peer, "Babka Hela: \"Bring me the basket, child.\"")
		return
	if _basket.contents.is_empty():
		Team.tell(peer, "Babka Hela: \"It's empty. Are you on something?\"")
		return
	var result: Array = _basket.sell(Team.known)
	Team.add_cash(result[0])
	var text := "Babka Hela bought %d mushrooms for %d €." % [result[1], result[0]]
	if result[2] > 0:
		text += " She won't touch the other %d (unknown or poisonous - taste first!)." % result[2]
	Team.tell(0, text)


func _use_slot(peer: int) -> void:
	var cost: int = Team.PRICES["slot"]
	if Team.cash < cost:
		Team.tell(peer, "The bouncer looks at your wallet and laughs.")
		return
	Team.add_cash(-cost)
	var roll := randi() % 100
	var player_name: String = Team.players[peer]["name"]
	if roll < 2:
		Team.add_cash(500)
		Team.tell(0, "JACKPOT!!! %s won 500 €!" % player_name)
	elif roll < 10:
		Team.add_cash(100)
		Team.tell(0, "%s hit three cherries: +100 €" % player_name)
	elif roll < 30:
		Team.add_cash(40)
		Team.tell(peer, "Two bells. +40 €")
	else:
		Team.tell(peer, ["Nothing.", "So close.", "The machine burps.", "Lemon, lemon, mushroom."][randi() % 4])


func _use_house_plot(peer: int) -> void:
	if Team.house:
		Team.tell(peer, "You already have a house. Boars can't get you at camp.")
		return
	var price: int = Team.PRICES["house"]
	if Team.cash < price:
		Team.tell(peer, "A house costs %d €. You have %d €." % [price, Team.cash])
		return
	Team.add_cash(-price)
	Team.house = true
	Team.push_all()
	Team.tell(0, "You built a HOUSE! Boars won't come into camp any more.")


func _use_cauldron(peer: int) -> void:
	var c := Terrain.place_centre("witch")
	var dead := []
	for p in Team.players:
		if not Team.is_alive(p):
			dead.append(p)
	if dead.is_empty():
		Team.tell(peer, "The witch: \"Nobody's dead, dearie. Yet.\"")
		return
	if _basket.global_position.distance_to(c) > 10.0:
		Team.tell(peer, "The witch: \"Bring the basket. 2 Witch's fingers and a Glowcap.\"")
		return
	for k in WITCH_RECIPE:
		if _basket.contents.count(k) < WITCH_RECIPE[k]:
			Team.tell(peer, "The witch: \"Not enough. 2 Witch's fingers and a Glowcap, I said.\"")
			return
	for k in WITCH_RECIPE:
		_basket.take(k, WITCH_RECIPE[k])
	Team.revive(dead[0])


# --- helpers --------------------------------------------------------------------------------


## A model standing on the ground at `pos` (feet at pos.y), no collision.
func _model(path: String, size: Vector3, pos: Vector3, yaw: float) -> Node3D:
	var model := ModelFit.fit(path, size, yaw)
	model.position += pos + Vector3(0, size.y / 2.0, 0)
	add_child(model)
	return model


## Same, with a box collider.
func _solid(path: String, size: Vector3, pos: Vector3, yaw: float) -> Node3D:
	var body := StaticBody3D.new()
	body.position = pos + Vector3(0, size.y / 2.0, 0)
	body.rotation.y = yaw
	var shape := BoxShape3D.new()
	shape.size = size * Vector3(0.85, 1.0, 0.85)
	var col := CollisionShape3D.new()
	col.shape = shape
	body.add_child(col)
	body.add_child(ModelFit.fit(path, size))
	add_child(body)
	return body


## A villager standing about, with a sign over their head.
func _npc(character: String, pos: Vector3, yaw: float, text: String, folder := "") -> void:
	var path := (folder if folder != "" else K + "mini-characters/") + character + ".glb"
	var model := _model(path, Vector3(1.2, 1.75, 1.2), pos, yaw)
	for anim in model.find_children("*", "AnimationPlayer", true, false):
		if anim.has_animation("idle"):
			anim.get_animation("idle").loop_mode = Animation.LOOP_LINEAR
			anim.play("idle")
	if text != "":
		_sign(text, pos + Vector3(0, 2.4, 0), 36)
