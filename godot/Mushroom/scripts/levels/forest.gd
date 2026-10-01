extends "res://scripts/levels/level.gd"
## The world of Mushroom Foraging. Four friends lost their jobs and now live in a junk camp in
## the forest. Every day they pick weird mushrooms and bring them to Babka Hela in the village,
## who tells them what they are and buys the good ones. Uncle Fero wants his money every 3 days.
## Nights get properly dark: wolves come out, and the Hungry Hag hunts anything that makes noise.
## Sick or dead friends go to the witch, who sends you somewhere horrible for the cure.
##
## A round is one day: PREP is dawn at camp, LIVE the day sliding into night, WRAP the night recap.
## The whole map comes from a fixed seed, so every peer builds the same world.

const Terrain := preload("res://scripts/world/terrain.gd")
const Vegetation := preload("res://scripts/world/vegetation.gd")
const MushroomScript := preload("res://scripts/mushroom.gd")
const BasketScript := preload("res://scripts/basket.gd")
const OldSlotScript := preload("res://scripts/old_slot.gd")
const CarScript := preload("res://scripts/car.gd")
const BoarScript := preload("res://scripts/boar.gd")
const WolfScript := preload("res://scripts/wolf.gd")
const HagScript := preload("res://scripts/hag.gd")
const InteractableScript := preload("res://scripts/interactable.gd")
const PlayerScript := preload("res://scripts/player.gd")
const CritterScript := preload("res://scripts/critter.gd")
const BodyScript := preload("res://scripts/body.gd")
const DuelScript := preload("res://scripts/duel.gd")
const TrapScript := preload("res://scripts/trap.gd")
const BrambleScript := preload("res://scripts/bramble.gd")

const K := "res://assets/kenney/"
const NATURE := K + "nature-kit/"
const PP := "res://assets/polypizza/"
const SEED := 20261001
const MUSHROOM_COUNT := 420
const BOAR_COUNT := 10
const WOLF_COUNT := 9
const SPARE_BASKETS := 4
const BEAR_TRAPS := 46
const MUD_PATCHES := 16
const HOLE_COUNT := 14
const BRAMBLES := 40
const HOLLOW_MUSHROOMS := 40  # rare ones, in the fog hollows
const RARE := ["golden_chanterelle", "rainbow_bolete", "glowcap", "witch_finger", "golden_chanterelle", "porcini"]
## Harmless animals: [model, count, size, speed]
const CRITTERS := [
	["animal-deer.glb", 30, Vector3(0.9, 1.5, 1.4), 2.2],
	["animal-bunny.glb", 40, Vector3(0.35, 0.45, 0.5), 2.8],
	["animal-fox.glb", 16, Vector3(0.5, 0.6, 0.9), 3.0],
]
## Scary places the witch sends you to: [place, script, ingredient, how she says it]
const LOCATIONS := [
	["sanatorium", "res://scripts/locations/sanatorium.gd", "mothers_mould",
		"Mother's mould, from the morgue of Sanatórium Hôrka"],
	["mine", "res://scripts/locations/mine.gd", "kobold_cap", "a Kobold cap, from deep in the Hodruša mine"],
	["crypt", "res://scripts/locations/crypt.gd", "bone_morel", "a Bone morel, from the saint's coffin in the chapel crypt"],
	["island", "res://scripts/locations/island.gd", "drowned_chanterelle",
		"a Drowned chanterelle, from the island in the lake. At midnight."],
]
const SHOP := [
	["medkit", "MEDKIT - cures poison, wakes the passed-out"], ["battery", "BATTERY - for everyone's torches"],
	["basket", "BASKET"], ["compass", "COMPASS - no more getting lost"], ["flare", "FLARE - everyone sees it. Everything hears it."],
	["whistle", "WHISTLE"], ["walkie", "WALKIE-TALKIE (hold V)"], ["wine", "CHEAP WINE"], ["duck", "RUBBER DUCK"],
	["lottery", "LOTTERY TICKET"], ["rope", "ROPE - pull a friend out of a hole"],
]
const EPITAPHS := [
	"HERE LIES JOŽO\nhe said it was a chanterelle", "R.I.P. MILAN\nate the pretty one", "FERO'S LAST CUSTOMER\npaid late",
	"TONO\n'I know a shortcut'", "UNKNOWN FORAGER\nstill has 3 € on him", "MAREK\nwent to check on the noise",
	"HERE LIES A TOURIST\ndrank from the pond", "PALO\nwhistled at night", "ANNA\nshe was right, we didn't listen",
	"VLADO\ndrove like he walked",
]

var _sun: DirectionalLight3D
var _env: Environment
var _night := false
var _night_lights: Array[Light3D] = []
var _day_only: Array[Node3D] = []  # villagers etc. who go home to sleep at night
var _mushrooms: Array = []
var _boars: Array = []
var _wolves: Array = []
var _hag: Node3D
var _bodies := {}  # peer id -> the body prop left behind (dead, or passed out)
var _house: Node3D
var _basket: RigidBody3D
var _spare_baskets: Array = []
var _car: VehicleBody3D
var _camp_fire: OmniLight3D
var _locations := {}  # place name -> location node
var _witch_orders := {}  # host: peer id -> ingredient kind
var _counter: Area3D  # Babka's stall
var _counter_scan := 0.0
var _rng := RandomNumberGenerator.new()
var _started := false
var _police_check := 0.0
var spawn_override := ""  # testing: spawn at a named place instead of camp
var monsters_enabled := true  # cheat: switch the hag and wolves off
# Daylight as the clock sets it; zones (old growth, fog hollows) then darken / fog it locally.
var _base_fog := 0.01
var _base_ambient := 0.3
var _base_sun := 0.9
var _base_fog_colour := Color.GRAY
var _night_amount := 0.0
var _dusk_amount := 0.0
var _in_old := 0.0
var _in_hollow := 0.0
var _eerie_in := 8.0


func _ready() -> void:
	add_to_group("level")
	_add_overview(Vector3(22, 16, 30), Vector3(0, 0, 0))
	_sun = DirectionalLight3D.new()
	_sun.shadow_enabled = true
	_sun.directional_shadow_max_distance = 60.0
	add_child(_sun)
	add_child(Terrain.build())
	_build_water()
	_rng.seed = SEED
	Vegetation.build(self, _rng)
	_build_camp()
	_build_village()
	_build_casino()
	_build_witch()
	_build_ruin()
	_build_locations()
	_build_signs()
	_build_mushrooms()
	_build_animals()
	_build_hunters()
	_build_traps()
	var duel := DuelScript.new()
	duel.name = "Duel"
	add_child(duel)
	for light in _night_lights:
		light.visible = false
	Team.died.connect(_on_died)
	Team.revived.connect(_on_revived)
	Team.changed.connect(_on_team_changed)
	Team.flare_fired.connect(_on_flare)
	Team.game_over.connect(_on_game_over)


## Host, all the time (not just while the day runs): Babka looks at her counter.
func _physics_process(delta: float) -> void:
	if not multiplayer.is_server():
		return
	_counter_scan += delta
	if _counter_scan > 0.5:
		_counter_scan = 0.0
		_check_counter()


# --- show rules ----------------------------------------------------------------------


func title() -> String:
	return "The forest"


func score_name() -> String:
	return "CASH"


func start_score() -> float:
	return float(Team.cash)


func prep_duration() -> float:
	return 30.0


func live_duration() -> float:
	return 900.0


func wrap_duration() -> float:
	return 25.0


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
	# Mist pools in the low ground (valleys, the lake, the fog hollows).
	_env.fog_height = Terrain.WATER_Y + 2.5
	_env.fog_height_density = 0.09
	# Bloom on lanterns, torches and anything glowing.
	_env.glow_intensity = 0.75
	_env.glow_bloom = 0.06
	_env.glow_hdr_threshold = 0.85
	_apply_quality()
	if not Settings.changed.is_connected(_apply_quality):
		Settings.changed.connect(_apply_quality)
	_apply_daylight(0.0, 0.0)
	return _env


## Graphics quality: shadows, bloom (everything else reads Settings when it's built).
func _apply_quality() -> void:
	var q: int = Settings.quality if "quality" in Settings else 2
	if _env:
		_env.glow_enabled = q >= 1
		_env.fog_height_density = [0.05, 0.08, 0.1][q]
	if _sun:
		_sun.shadow_enabled = q >= 1 and (Settings.shadows if "shadows" in Settings else true)
		_sun.directional_shadow_max_distance = [40.0, 60.0, 90.0][q]


## Every peer: where's MY player? Old growth is dark, fog hollows are thick. Smoothly.
func _process(delta: float) -> void:
	var me: Node3D = null
	for p in get_tree().get_nodes_in_group("players"):
		if p.is_multiplayer_authority():
			me = p
	var old_target := 0.0
	var hollow_target := 0.0
	if me:
		old_target = Terrain.zone_amount(me.global_position.x, me.global_position.z, Terrain.OLD_GROWTH)
		hollow_target = Terrain.zone_amount(me.global_position.x, me.global_position.z, Terrain.FOG_HOLLOWS)
	_in_old = move_toward(_in_old, old_target, delta * 0.5)
	_in_hollow = move_toward(_in_hollow, hollow_target, delta * 0.35)
	if _env:
		var q: int = Settings.quality if "quality" in Settings else 2
		var hollow_fog: float = [0.07, 0.1, 0.13][q]
		_env.fog_density = _base_fog + _in_hollow * hollow_fog + _in_old * 0.012
		_env.fog_light_color = _base_fog_colour.lerp(Color(0.42, 0.45, 0.42) * (1.0 - _night_amount * 0.9), _in_hollow * 0.8)
		_env.ambient_light_energy = _base_ambient * (1.0 - 0.55 * _in_old)
	if _sun:
		_sun.light_energy = _base_sun * (1.0 - 0.75 * _in_old)
	get_tree().call_group("hud", "set_grade", _night_amount, _dusk_amount, _in_old, _in_hollow)
	# The hollows sound wrong.
	if _in_hollow > 0.5:
		_eerie_in -= delta
		if _eerie_in <= 0.0 and me:
			_eerie_in = randf_range(7.0, 16.0)
			var around: Vector3 = me.global_position + Vector3(randf_range(-1, 1), 0.3, randf_range(-1, 1)).normalized() * 9.0
			Sfx.play(["hag_whisper", "branch_snap", "owl_hoot"][randi() % 3], around, -4.0)


func server_tick(delta: float, director: Node) -> void:
	director.score = float(Team.cash)
	_police_check += delta
	if _police_check > 1.0:
		_check_missing(_police_check)
		_police_check = 0.0


func server_reset() -> void:
	# A new morning (not the very first one): the forest regrows somewhere else.
	if _started:
		Team.next_day()
	_started = true
	for m in _mushrooms:
		m.reset_to_home()
		var hollow: int = m.get_meta("hollow", -1)
		m.position = _hollow_spot(hollow) if hollow >= 0 else _mushroom_spot()
		m.rotation.y = _rng.randf() * TAU
	for prop in find_children("*", "RigidBody3D", true, false):
		if prop.has_method("reset_to_home") and not prop is MushroomScript and not prop is BodyScript:
			prop.reset_to_home()
	for loc in _locations.values():
		loc.server_reset()
	if _hag:
		_hag.server_reset()


func apply_state(phase: int, _event: int, _sub: int, time_left: float) -> void:
	var t := 0.0  # 0 = morning, 1 = midnight
	var dawn := 0.0  # 1 = first light, 0 = full morning
	if phase == Phase.PREP:
		dawn = clampf(time_left / prep_duration(), 0.0, 1.0)
	elif phase == Phase.LIVE:
		t = clampf(1.0 - time_left / live_duration(), 0.0, 1.0)
	elif phase == Phase.WRAP:
		t = 1.0
	_apply_daylight(t, dawn)
	Sfx.set_time_of_day(t)
	var night := t > 0.68
	if night != _night:
		_night = night
		for light in _night_lights:
			light.visible = night
		for node in _day_only:
			node.visible = not night
		for boar in _boars:
			boar.night = night
		_set_monsters_night()
		for loc in _locations.values():
			loc.set_night(night)


func _set_monsters_night() -> void:
	for wolf in _wolves:
		wolf.night = _night and monsters_enabled
	if _hag:
		_hag.night = _night and monsters_enabled


## Every peer: the run ended. Bodies go, everyone wakes up at camp, the next run starts at day 1.
func _on_game_over(_stats: Dictionary) -> void:
	for body in _bodies.values():
		body.put_away()
	_witch_orders.clear()
	_started = false
	for p in get_tree().get_nodes_in_group("players"):
		if p.is_multiplayer_authority():
			p.global_position = spawn_point(0)


## Host: cheats the level knows how to do (Team handles the rest).
func cheat(what: String, peer: int) -> void:
	var director := get_tree().get_first_node_in_group("director")
	match what:
		"morning", "dusk", "midnight":
			var t: float = {"morning": 0.05, "dusk": 0.55, "midnight": 0.9}[what]
			if director:
				if director.phase != Phase.LIVE:
					director._enter(Phase.LIVE)
				director.time_left = live_duration() * (1.0 - t)
		"monsters":
			monsters_enabled = not monsters_enabled
			_set_monsters_night()
			Team.tell(peer, "Hag and wolves %s." % ("ON" if monsters_enabled else "OFF"))
		_:
			if what.begins_with("spawn:"):
				var kind := what.trim_prefix("spawn:")
				var p := _player(peer)
				if p == null:
					return
				for m in _mushrooms + find_children("*", "", true, false):
					if m is MushroomScript and m.kind == kind:
						m.reset_to_home()
						m.global_position = p.global_position - p.global_basis.z * 1.5 + Vector3(0, 1.0, 0)
						return
				# None of that kind out here (cure ingredients live in their places): turn one into it.
				var spare = _mushrooms[0]
				spare.reset_to_home()
				spare.global_position = p.global_position - p.global_basis.z * 1.5 + Vector3(0, 1.0, 0)
				Team.tell(peer, "No %s nearby to fetch; there's another mushroom instead." % kind)


func phase_text(phase: int, clock: String, _score: float, _sub: int) -> String:
	var fero := "Uncle Fero wants %d € at the end of day %d" % [Team.quota_amount(), Team.quota_day()]
	match phase:
		Phase.PREP:
			return "DAY %d  -  dawn at camp  -  %s\n%s" % [Team.day, clock, fero]
		Phase.LIVE:
			return "DAY %d  -  %s until midnight\n%s" % [Team.day, clock, fero]
	return "NIGHT %d  -  get back to camp" % Team.day


func guide_text() -> String:
	var lines := ["FIELD JOURNAL - what Babka Hela told you"]
	for k in MushroomScript.KINDS:
		if Team.known.has(k):
			var e: int = MushroomScript.KINDS[k][0]
			var what: String = ["food", "trippy", "VERY trippy", "POISON", "witchy", "cure"][e]
			var worth := "%d €" % MushroomScript.price_of(k) if MushroomScript.sellable(k) else "worthless"
			lines.append("%s (%s): %s, %s" % [MushroomScript.name_of(k), MushroomScript.describe(k), what, worth])
	if lines.size() == 1:
		lines.append("Nothing yet. Put mushrooms on Babka's counter in the village.")
	return "\n".join(lines)


# --- daylight ------------------------------------------------------------------------


func _apply_daylight(t: float, dawn: float) -> void:
	# Dawn in the morning prep, day until ~0.45, sunset to ~0.68, then night.
	var day := (1.0 - smoothstep(0.45, 0.7, t)) * (1.0 - dawn * 0.75)
	var sunset := smoothstep(0.35, 0.58, t) * (1.0 - smoothstep(0.6, 0.72, t))
	var glow := maxf(sunset, dawn * (1.0 - dawn) * 3.0)  # pink-orange at sunrise and sunset
	if _sun:
		var rise := lerpf(-0.08, -0.6, 1.0 - dawn)
		_sun.rotation = Vector3(lerpf(rise, -0.05, smoothstep(0.1, 0.7, t)) if t > 0.0 else rise, 0.7, 0.0)
		_base_sun = lerpf(0.0, 0.95, day)
		_sun.light_color = Color(1, 0.96, 0.88).lerp(Color(1, 0.6, 0.4), glow * 0.8)
		_sun.visible = day > 0.01
	if _env:
		var sky := Color(0.55, 0.7, 0.85).lerp(Color(0.9, 0.55, 0.45), glow * 0.7)
		sky = sky.lerp(Color(0.01, 0.012, 0.025), 1.0 - day)
		_env.background_color = sky
		_env.ambient_light_color = Color(0.85, 0.85, 0.8).lerp(Color(0.25, 0.3, 0.5), 1.0 - day)
		_base_ambient = lerpf(0.03, 0.32, day)
		var mist := Color(0.6, 0.68, 0.72).lerp(sky, 0.5).lerp(Color(0.015, 0.02, 0.03), 1.0 - day)
		_base_fog_colour = mist
		# Foggy forest: thick at night, misty at dawn, never really clear.
		_base_fog = lerpf(0.045, 0.009, day) + dawn * 0.012
		_env.fog_height_density = ([0.05, 0.08, 0.1][Settings.quality if "quality" in Settings else 2]) * (1.0 + dawn * 1.5)
	_night_amount = 1.0 - day
	_dusk_amount = glow


# --- people coming and going ------------------------------------------------------------


func _on_died(peer_id: int, reason: String) -> void:
	var player := _player(peer_id)
	var player_name: String = Team.players[peer_id]["name"] if Team.players.has(peer_id) else "Somebody"
	get_tree().call_group("hud", "show_toast", "%s died of %s." % [player_name, reason])
	get_tree().call_group("hud", "remember_highlight", "%s died of %s" % [player_name, reason], peer_id)
	if multiplayer.is_server() and _car.seat_of(peer_id) >= 0:
		_car.leave(peer_id)
	if player != null:
		_drop_body(peer_id, player)


## Every peer: leave a floppy body where the player fell. It's a real prop: carry it to the
## witch, or throw it in the car. Same name everywhere, so it syncs.
func _drop_body(peer_id: int, player: Node3D) -> void:
	var body: RigidBody3D = _bodies.get(peer_id)
	if body == null:
		body = BodyScript.new()
		body.build(peer_id, player.variant, Team.players.get(peer_id, {}).get("name", "?"))
		add_child(body)
		_bodies[peer_id] = body
	body.lay_down(player.global_position + Vector3(0, 0.5, 0), player.rotation.y)


func _on_revived(peer_id: int) -> void:
	var at := Terrain.place_centre("witch") + Vector3(3, 1.0, 3)
	if _bodies.has(peer_id):
		_bodies[peer_id].put_away()
	var player := _player(peer_id)
	if player and player.is_multiplayer_authority():
		player.global_position = at
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


# --- missing friend: the police ----------------------------------------------------------


## Host: somebody alive has been far from everyone else for too long -> police timer. If it runs
## out, the police raid the camp. Finding the friend (anyone within 20 m) calls it off.
func _check_missing(step: float) -> void:
	var alive := []
	for p in get_tree().get_nodes_in_group("players"):
		if Team.is_alive(p.peer_id):
			alive.append(p)
	if alive.size() < 2:
		if Team.police_left >= 0.0:
			Team.set_police(-1.0, 0)
		return
	var lost: Node3D = null
	for p in alive:
		var nearest := INF
		for q in alive:
			if q != p:
				nearest = minf(nearest, p.global_position.distance_to(q.global_position))
		if nearest > 160.0:
			lost = p
			break
	if lost == null:
		if Team.police_left >= 0.0:
			var found: String = Team.players.get(Team.missing_peer, {}).get("name", "your friend")
			Team.tell(0, "Found %s! Nobody calls the police." % found)
			Team.set_police(-1.0, 0)
		lost_for.clear()
		return
	lost_for[lost.peer_id] = lost_for.get(lost.peer_id, 0.0) + step
	if Team.police_left < 0.0 and lost_for[lost.peer_id] > 150.0:
		Team.set_police(Team.POLICE_SECONDS, lost.peer_id)
		Team.tell(0, "Somebody in the village reported %s missing. Find them before the police come!" % Team.players[lost.peer_id]["name"])
	elif Team.police_left == 0.0:
		_police_raid(lost.peer_id)


var lost_for := {}  # host: peer id -> seconds far from everyone


func _police_raid(missing: int) -> void:
	var lost_cash := Team.cash / 2
	Team.add_cash(-lost_cash)
	_basket.dump_all()
	Team.set_police(-1.0, 0)
	lost_for.clear()
	Sfx.play_all("police_siren", Vector3.ZERO)
	Team.highlight("Police raid at camp")
	Team.tell(0, "POLICE RAID at camp! \"Where is %s?!\" They took %d € and your mushrooms." % [
		Team.players.get(missing, {}).get("name", "your friend"), lost_cash])


# --- building: water ----------------------------------------------------------------------


func _build_water() -> void:
	var lake_c: Vector2 = Terrain.LAKE[0]
	var mesh := PlaneMesh.new()
	mesh.size = Vector2.ONE * Terrain.LAKE[1] * 2.8
	var water := MeshInstance3D.new()
	water.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.12, 0.28, 0.32, 0.85)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.roughness = 0.1
	water.material_override = mat
	water.position = Vector3(lake_c.x, Terrain.WATER_Y, lake_c.y)
	add_child(water)
	for i in 24:
		var a := _rng.randf() * TAU
		var r := _rng.randf_range(16.0, Terrain.LAKE[1] * 0.85)
		var p := Vector3(lake_c.x + cos(a) * r, Terrain.WATER_Y + 0.02, lake_c.y + sin(a) * r)
		_model(NATURE + ("lily_large.glb" if i % 2 else "lily_small.glb"), Vector3(1.2, 0.1, 1.2), p, _rng.randf() * TAU)


# --- building: places ----------------------------------------------------------------------


func _build_camp() -> void:
	var c := Terrain.place_centre("camp")
	var sk := K + "survival-kit/"
	_signpost("JUNK CAMP\nhome sweet home", Vector3(9, 0, -9), PI * 0.75)
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

	_basket = BasketScript.new()
	_basket.build(K + "mini-market/shopping-basket.glb")
	_basket.position = c + Vector3(3.5, 1.4, 4)
	add_child(_basket)

	_car = CarScript.new()
	_car.build(K + "car-kit/suv.glb")
	_car.position = c + Vector3(10, 1.0, -2)
	_car.rotation.y = PI / 2.0 + 0.4  # nose towards the road
	add_child(_car)

	var plot := InteractableScript.new()
	plot.configure("HousePlot", Vector3(1.2, 1.4, 0.3), Vector3(-9, c.y + 0.7, 8),
		"build a house here (%d €)" % Team.PRICES["house"], _use_house_plot)
	add_child(plot)
	_signpost("HOUSE PLOT\n%d €" % Team.PRICES["house"], Vector3(-9, 0, 8), 0.0)

	# The field guide: one book, one reader. Everyone else has to listen to them describe it.
	var guide := preload("res://scripts/field_guide.gd").new()
	guide.build()
	guide.position = c + Vector3(-4, 1.2, 3)
	add_child(guide)


func _build_village() -> void:
	var c := Terrain.place_centre("village")
	_signpost("HORNÁ LEHOTA", Vector3(c.x - 44, 0, c.z - 6), -PI / 2.0, 60)
	var houses := ["a", "b", "d", "e", "f", "g", "h", "b", "e", "a", "d"]
	for i in houses.size():
		var a := i * TAU / houses.size() + 0.3
		if i == 0:
			continue  # gap where the road comes in
		var p := c + Vector3(cos(a) * 29, 0, sin(a) * 29)
		_solid(K + "city-kit-suburban/building-type-%s.glb" % houses[i], Vector3(8, 7, 8), p, -a - PI / 2.0)
		_night_lights.append(_light(p + Vector3(0, 2.5, 0) - Vector3(cos(a), 0, sin(a)) * 4.5, 0.8, 6.0, Color(1, 0.8, 0.5)))
	var ft := K + "fantasy-town-kit/"
	_solid(ft + "fountain-round.glb", Vector3(4, 1.6, 4), c, 0.0)
	_solid(ft + "stall-red.glb", Vector3(3, 2.6, 2), c + Vector3(-6, 0, 7), PI)
	_solid(ft + "stall-green.glb", Vector3(3, 2.6, 2), c + Vector3(8, 0, 7), PI)
	_solid(ft + "cart.glb", Vector3(1.6, 1.4, 2.6), c + Vector3(10, 0, -6), 0.6)
	for i in 6:
		var a := i * TAU / 6.0
		var p := c + Vector3(cos(a) * 13, 0, sin(a) * 13)
		_model(ft + "lantern.glb", Vector3(0.6, 2.6, 0.6), p, 0.0)
		_night_lights.append(_light(p + Vector3(0, 2.6, 0), 1.6, 12.0, Color(1.0, 0.8, 0.45)))

	# Babka Hela: put mushrooms on her counter (or bring the basket) and she names and buys them.
	_day_only.append(_npc_model(PP + "grandmother.glb", c + Vector3(-6, 0, 8.6), PI, 1.5))
	_signpost("BABKA HELA\nputs a name to any mushroom\nbuys the good ones", Vector3(c.x - 8.5, 0, c.z + 6), 0.4, 28)
	var babka := InteractableScript.new()
	babka.configure("Babka", Vector3(3, 2, 1.2), c + Vector3(-6, 1, 6.6), "talk to Babka Hela (sell the basket)", _use_babka)
	add_child(babka)
	_counter = Area3D.new()
	var counter_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(3.2, 1.2, 1.6)
	counter_shape.shape = box
	_counter.add_child(counter_shape)
	_counter.position = c + Vector3(-6, 1.2, 6.8)
	add_child(_counter)

	# Jano's shop: every item is a spot on his counter you press E at.
	_day_only.append(_npc_model(K + "mini-characters/character-male-e.glb", c + Vector3(8, 0, 8.6), PI, 1.75))
	_signpost("JANO'S POTRAVINY\neverything a forager needs\n(and some things they don't)", Vector3(c.x + 11.5, 0, c.z + 6), -0.4, 28)
	for i in SHOP.size():
		var item: String = SHOP[i][0]
		var x := -2.2 + (i % 5) * 1.1
		var row := 0.0 if i < 5 else 1.2
		var spot := c + Vector3(8 + x, 1, 5.6 - row)
		var buy := InteractableScript.new()
		buy.configure("Buy_%s" % item, Vector3(1.0, 1.6, 0.8), spot,
			"buy %s (%d €)" % [SHOP[i][1], Team.PRICES[item]], func(peer): _buy(peer, item))
		add_child(buy)
	for i in SPARE_BASKETS:
		var spare := BasketScript.new()
		spare.build(K + "mini-market/shopping-basket.glb")
		spare.name = "SpareBasket%d" % i
		spare.position = c + Vector3(5.5 + i * 0.9, 1.3, 4.6)
		add_child(spare)
		spare.hide_until_bought()
		_spare_baskets.append(spare)

	_day_only.append(_npc_model(K + "mini-characters/character-male-f.glb", c + Vector3(3, 0, -8), 0.5, 1.75))
	_day_only.append(_npc_model(K + "mini-characters/character-female-f.glb", c + Vector3(-8, 0, -4), 2.0, 1.7))
	_signpost("UNCLE FERO\nloans. no questions.\npayback every 3 days", Vector3(c.x + 14, 0, c.z - 12), -2.3, 28)


func _build_casino() -> void:
	var c := Terrain.place_centre("casino")
	_solid(K + "city-kit-commercial/building-c.glb", Vector3(14, 12, 12), c + Vector3(0, 0, -8), 0.0)
	_model(K + "city-kit-commercial/detail-awning-wide.glb", Vector3(10, 1.2, 3), c + Vector3(0, 3.6, -1.4), 0.0)
	var neon := _sign("CASINO ROYALE\nZVOLEN", c + Vector3(0, 8.5, -1.8), 128, 0.0)
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
	_npc_model(K + "mini-arcade/character-employee.glb", c + Vector3(-7, 0, 1), 0.4, 1.75)


func _build_witch() -> void:
	var c := Terrain.place_centre("witch")
	var gy := K + "graveyard-kit/"
	_signpost("THE WITCH\nbring her the sick, the dead,\nand whatever she asks for", Vector3(c.x + 14, 0, c.z + 14), PI * 0.25, 30)
	_solid(gy + "crypt.glb", Vector3(5, 5, 6), c + Vector3(0, 0, -10), 0.0)
	for i in 10:
		var a := _rng.randf() * TAU
		var r := _rng.randf_range(7, 15)
		var model := gy + ("gravestone-round.glb" if i % 2 else "gravestone-cross.glb")
		var yaw := _rng.randf() * TAU
		var pos := c + Vector3(cos(a) * r, 0, sin(a) * r)
		_solid(model, Vector3(0.9, 1.2, 0.3), pos, yaw)
		var epitaph := _sign(EPITAPHS[i % EPITAPHS.size()], pos + Vector3(0, 0.75, 0) + Basis(Vector3.UP, yaw) * Vector3(0, 0, 0.17), 18, yaw)
		epitaph.modulate = Color(0.15, 0.15, 0.15)
		epitaph.outline_size = 0
	for i in 6:
		var a := i * TAU / 6.0 + 0.2
		_solid(gy + "pine-crooked.glb", Vector3(3, 8, 3), c + Vector3(cos(a) * 17, 0, sin(a) * 17), a)
	_model(gy + "detail-bowl.glb", Vector3(1.6, 0.9, 1.6), c + Vector3(0, 0, -2), 0.0)
	_light(c + Vector3(0, 1.5, -2), 2.5, 10.0, Color(0.4, 1.0, 0.3))
	_model(gy + "fire-basket.glb", Vector3(0.7, 1.2, 0.7), c + Vector3(-3, 0, -3), 0.0)
	_model(gy + "fire-basket.glb", Vector3(0.7, 1.2, 0.7), c + Vector3(3, 0, -3), 0.0)
	_model(gy + "candle-multiple.glb", Vector3(0.6, 0.5, 0.6), c + Vector3(1.4, 0, -0.6), 0.0)
	_model(gy + "pumpkin-carved.glb", Vector3(0.6, 0.6, 0.6), c + Vector3(-1.6, 0, -0.8), 0.6)
	var witch := _npc_model(PP + "witch.glb", c + Vector3(0, 0, -4), 0.0, 1.8)
	for anim in witch.find_children("*", "AnimationPlayer", true, false):
		if anim.has_animation("CharacterArmature|Idle"):
			anim.get_animation("CharacterArmature|Idle").loop_mode = Animation.LOOP_LINEAR
			anim.play("CharacterArmature|Idle")
	var cauldron := InteractableScript.new()
	cauldron.configure("Cauldron", Vector3(1.8, 1.2, 1.8), c + Vector3(0, 0.6, -2),
		"talk to the witch (bring the sick one, and what she asked for)", _use_cauldron)
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


## The scary places (built by their own scripts, if they exist yet).
func _build_locations() -> void:
	for entry in LOCATIONS:
		if not ResourceLoader.exists(entry[1]):
			continue
		var script: Script = load(entry[1])
		if script == null or not script.can_instantiate():
			continue  # not finished yet
		var loc: Node3D = script.new()
		loc.name = (entry[0] as String).capitalize()
		if entry[0] == "island":
			var ic: Vector2 = Terrain.ISLAND[0]
			loc.position = Vector3(ic.x, Terrain.height(ic.x, ic.y), ic.y)
		else:
			loc.position = Terrain.place_centre(entry[0])
		add_child(loc)
		loc.build()
		_locations[entry[0]] = loc


## Wooden signposts at the forks. No map, no minimap: read the signs or buy a compass.
func _build_signs() -> void:
	_signpost("← VILLAGE 380 m\n→ CHAPEL\n↓ OLD MINE", Vector3(14, 0, 12), -0.8)
	_signpost("VILLAGE →\nCASINO ↘\nSANATÓRIUM ↑", Vector3(166, 0, 40), -1.6)
	_signpost("SANATÓRIUM HÔRKA\nVSTUP ZAKÁZANÝ", Vector3(214, 0, 268), -2.6)
	_signpost("CASINO →", Vector3(338, 0, 82), -1.2)
	_signpost("→ the witch\n(don't)", Vector3(-12, 0, -222), 1.2)
	_signpost("LAKE ↓\nno swimming. seriously.", Vector3(36, 0, -120), 0.4)
	_signpost("CHAPEL & CRYPT →", Vector3(66, 0, -320), 2.4)
	_signpost("BANSKÁ ŠTÔLŇA\nHODRUŠA →", Vector3(-332, 0, 140), -1.9)
	_signpost("CLIFF\ncareful", Vector3(-226, 0, 30), 1.0)
	_signpost("old ruin ↑", Vector3(-84, 0, 196), 0.6)


func _build_mushrooms() -> void:
	var kind_rng := RandomNumberGenerator.new()
	kind_rng.seed = SEED + 7
	for i in MUSHROOM_COUNT:
		var mushroom := MushroomScript.new()
		var hollow := i % Terrain.FOG_HOLLOWS.size() if i < HOLLOW_MUSHROOMS else -1
		var kind: String = RARE[kind_rng.randi() % RARE.size()] if hollow >= 0 else MushroomScript.pick_kind(kind_rng)
		mushroom.setup_mushroom("Mushroom_%d" % i, kind)
		mushroom.set_meta("hollow", hollow)
		mushroom.position = _hollow_spot(hollow) if hollow >= 0 else _mushroom_spot()
		mushroom.rotation.y = _rng.randf() * TAU
		add_child(mushroom)
		_mushrooms.append(mushroom)


## Deep in one of the fog hollows.
func _hollow_spot(hollow: int) -> Vector3:
	var zone: Array = Terrain.FOG_HOLLOWS[hollow]
	var c: Vector2 = zone[0]
	var a := _rng.randf() * TAU
	var d: float = sqrt(_rng.randf()) * zone[1] * 0.7
	var x: float = c.x + cos(a) * d
	var z: float = c.y + sin(a) * d
	return Vector3(x, Terrain.height(x, z) + 0.3, z)


## Somewhere in the woods, not on roads, not in the lake, not in town.
func _mushroom_spot() -> Vector3:
	for i in 60:
		var x := _rng.randf_range(-Terrain.SIZE * 0.39, Terrain.SIZE * 0.39)
		var z := _rng.randf_range(-Terrain.SIZE * 0.39, Terrain.SIZE * 0.39)
		if Vector2(x, z).length() < 30.0 or not Terrain.is_clear(x, z, -2.0):
			continue
		var h := Terrain.height(x, z)
		if h > Terrain.WATER_Y + 0.5:
			return Vector3(x, h + 0.3, z)
	return Vector3(30, Terrain.height(30, 30) + 0.3, 30)


func _build_animals() -> void:
	for i in BOAR_COUNT:
		var boar := BoarScript.new()
		boar.name = "Boar%d" % i
		boar.build(K + "cube-pets/animal-hog.glb", _mushroom_spot(), SEED + i)
		add_child(boar)
		_boars.append(boar)
	var n := 0
	for entry in CRITTERS:
		for i in entry[1]:
			n += 1
			var size: Vector3 = entry[2]
			var model := ModelFit.fit(K + "cube-pets/" + entry[0], size, 0.0)
			model.position.y += size.y / 2.0
			var critter := CritterScript.new()
			critter.setup(model, _mushroom_spot(), entry[3], SEED + 100 + n)
			add_child(critter)


## Traps, hidden but fair: bear traps in the grass next to mushrooms (bait) and along paths,
## mud in the dips, holes between boulders off the paths, brambles in the thick of the forest.
func _build_traps() -> void:
	var n := 0
	for i in BEAR_TRAPS:
		var at: Vector3
		if i % 2 == 0 and i / 2 < _mushrooms.size():
			var m: Node3D = _mushrooms[(i * 7) % _mushrooms.size()]
			var a := _rng.randf() * TAU
			at = m.position + Vector3(cos(a), 0, sin(a)) * _rng.randf_range(0.7, 1.3)
		else:
			var path: Array = Terrain.PATHS[i % Terrain.PATHS.size()]
			var seg := i % (path.size() - 1)
			var pa: Vector2 = path[seg]
			var pb: Vector2 = path[seg + 1]
			var side := (pb - pa).normalized().orthogonal() * _rng.randf_range(-3.0, 3.0)
			var p2 := pa.lerp(pb, _rng.randf()) + side
			at = Vector3(p2.x, 0, p2.y)
		_add_trap("bear trap", at, n)
		n += 1
	var muds := 0
	var tries := 0
	while muds < MUD_PATCHES and tries < 3000:
		tries += 1
		var x := _rng.randf_range(-Terrain.SIZE * 0.38, Terrain.SIZE * 0.38)
		var z := _rng.randf_range(-Terrain.SIZE * 0.38, Terrain.SIZE * 0.38)
		if not Terrain.is_clear(x, z, 4.0) or not _is_dip(x, z):
			continue
		_add_trap("mud", Vector3(x, 0, z), n)
		n += 1
		muds += 1
	for i in HOLE_COUNT:
		var path: Array = Terrain.PATHS[i % Terrain.PATHS.size()]
		var seg := i % (path.size() - 1)
		var pa: Vector2 = path[seg]
		var pb: Vector2 = path[seg + 1]
		var side := (pb - pa).normalized().orthogonal() * (_rng.randf_range(6.0, 12.0) * (1.0 if i % 2 else -1.0))
		var p2 := pa.lerp(pb, 0.2 + 0.6 * _rng.randf()) + side
		_add_trap("hole", Vector3(p2.x, 0, p2.y), n)
		n += 1
	var thickets := 0
	tries = 0
	while thickets < BRAMBLES and tries < 2000:
		tries += 1
		var x := _rng.randf_range(-Terrain.SIZE * 0.38, Terrain.SIZE * 0.38)
		var z := _rng.randf_range(-Terrain.SIZE * 0.38, Terrain.SIZE * 0.38)
		if not Terrain.is_clear(x, z, 2.0):
			continue
		var bramble := BrambleScript.new()
		bramble.name = "Bramble%d" % thickets
		bramble.build(Vector3(x, Terrain.height(x, z), z), SEED + 900 + thickets)
		add_child(bramble)
		thickets += 1


func _add_trap(kind: String, at: Vector3, n: int) -> void:
	var trap := TrapScript.new()
	trap.name = "Trap%d" % n
	trap.build(kind, Vector3(at.x, Terrain.height(at.x, at.z), at.z), SEED + 600 + n)
	add_child(trap)


## A dip: lower than the ground around it (where water would gather).
func _is_dip(x: float, z: float) -> bool:
	var h := Terrain.height(x, z)
	var around := 0.0
	for i in 8:
		var a := i * TAU / 8.0
		around += Terrain.height(x + cos(a) * 14.0, z + sin(a) * 14.0)
	return h < around / 8.0 - 0.7


## Every peer: a red flare rises and burns over the trees for a while.
func _on_flare(pos: Vector3) -> void:
	var flare := Node3D.new()
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.15, 0.1)
	light.light_energy = 6.0
	light.omni_range = 70.0
	flare.add_child(light)
	var ball := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.4
	sphere.height = 0.8
	ball.mesh = sphere
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1, 0.2, 0.1)
	mat.emission_enabled = true
	mat.emission = Color(1, 0.2, 0.1)
	mat.emission_energy_multiplier = 8.0
	ball.material_override = mat
	flare.add_child(ball)
	flare.position = pos + Vector3(0, 2, 0)
	add_child(flare)
	var tween := create_tween()
	tween.tween_property(flare, "position:y", pos.y + 45.0, 3.0).set_ease(Tween.EASE_OUT)
	tween.tween_property(flare, "position:y", pos.y + 30.0, 20.0)
	tween.tween_callback(flare.queue_free)


func _build_hunters() -> void:
	for i in WOLF_COUNT:
		var wolf := WolfScript.new()
		wolf.name = "Wolf%d" % i
		wolf.build(PP + "wolf.glb", _mushroom_spot(), SEED + 300 + i)
		add_child(wolf)
		_wolves.append(wolf)
	_hag = HagScript.new()
	_hag.name = "Hag"
	_hag.build(PP + "hag.glb", SEED + 500)
	add_child(_hag)


# --- uses (host) ---------------------------------------------------------------------------


func _buy(peer: int, item: String) -> void:
	var price: int = Team.PRICES[item]
	if _night:
		Team.tell(peer, "The shop is closed. Jano is asleep. Come back in the morning.")
		return
	if Team.cash < price:
		Team.tell(peer, "Jano: \"%d € or get out.\" (team cash: %d €)" % [price, Team.cash])
		return
	if item == "basket":
		var spare = null
		for b in _spare_baskets:
			if b.for_sale:
				spare = b
				break
		if spare == null:
			Team.tell(peer, "Jano: \"Out of baskets. You lot keep losing them.\"")
			return
		spare.bring_out()
	else:
		Team.give(peer, item)
	Team.add_cash(-price)
	Sfx.play_all("buy", Terrain.place_centre("village") + Vector3(8, 1, 6))
	var hint := {"medkit": " H uses it on whoever you look at.", "flare": " G fires it.", "whistle": " B blows it.",
		"walkie": " Hold V to talk.", "compass": " It shows on screen now.", "wine": " G drinks it.",
		"duck": " G squeezes it.", "lottery": " G scratches it."}
	Team.tell(peer, "Bought a %s.%s" % [Team.ITEM_NAMES.get(item, item), hint.get(item, "")])


## Every half second: Babka looks at what's on her counter. Mushrooms get a name and, if
## they're any good, money. A basket on the counter gets the same treatment.
func _check_counter() -> void:
	if _night:
		return
	for body in _counter.get_overlapping_bodies():
		if body is MushroomScript and not body.removed and body.holder_id == 0:
			_babka_judges(body)
		elif body is BasketScript and not body.removed and body.holder_id == 0 and not body.contents.is_empty():
			_babka_buys_basket(body)


func _babka_judges(m: Node) -> void:
	var kind: String = m.kind
	var name := MushroomScript.name_of(kind)
	Team.identify(kind)
	if MushroomScript.sellable(kind):
		var price: int = MushroomScript.price_of(kind)
		m.remove_from_play()
		Team.add_cash(price)
		Sfx.play_all("cash", m.global_position)
		Team.tell(0, "Babka Hela: \"%s, dear. %d €.\"" % [name, price])
	elif MushroomScript.KINDS[kind][0] == MushroomScript.Effect.CURE:
		if not m.get_meta("babka_saw", false):
			m.set_meta("babka_saw", true)
			Team.tell(0, "Babka Hela: \"%s?! Take that to the witch, child, and don't wave it around.\"" % name)
	else:
		m.remove_from_play()
		Team.tell(0, "Babka Hela: \"That's a %s! Don't you dare eat that.\" She throws it in the bin." % name)


func _babka_buys_basket(basket: Node) -> void:
	for k in basket.contents:
		Team.identify(k)
	var result: Array = basket.sell(Team.known)
	Team.add_cash(result[0])
	if result[0] > 0:
		Sfx.play_all("cash", basket.global_position)
	var text := "Babka Hela went through the basket: %d mushrooms for %d €." % [result[1], result[0]]
	if result[2] > 0:
		text += " %d were rubbish or poison; she binned them." % result[2]
	Team.tell(0, text)


func _use_babka(peer: int) -> void:
	if _night:
		Team.tell(peer, "Babka Hela is asleep. Even grannies sleep.")
		return
	var c := Terrain.place_centre("village") + Vector3(-6, 0, 6)
	for b in [_basket] + _spare_baskets:
		if not b.removed and b.global_position.distance_to(c) < 7.0 and not b.contents.is_empty():
			_babka_buys_basket(b)
			return
	Team.tell(peer, "Babka Hela: \"Put them on my counter, dear, one by one. Or bring the basket.\"")


func _use_slot(peer: int) -> void:
	var cost: int = Team.PRICES["slot"]
	if Team.cash < cost:
		Team.tell(peer, "The bouncer looks at your wallet and laughs.")
		return
	Team.add_cash(-cost)
	Sfx.play_all("slot_spin", Terrain.place_centre("casino"))
	var roll := randi() % 100
	var player_name: String = Team.players[peer]["name"]
	if roll < 2:
		Team.add_cash(500)
		Sfx.play_all("slot_win", Terrain.place_centre("casino"))
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
		Team.tell(peer, "You already have a house. Boars and wolves can't get you at camp.")
		return
	var price: int = Team.PRICES["house"]
	if Team.cash < price:
		Team.tell(peer, "A house costs %d €. You have %d €." % [price, Team.cash])
		return
	Team.add_cash(-price)
	Team.house = true
	Team.push_all()
	Team.tell(0, "You built a HOUSE! Animals won't come into camp any more.")


## The witch: bring her the sick one (alive and poisoned, or a body). She names what she needs,
## and when it's in her cauldron (or the basket next to it) she fixes them.
func _use_cauldron(peer: int) -> void:
	var c := Terrain.place_centre("witch")
	var sick := []
	for p in Team.players:
		if not Team.is_alive(p) or Team.poison_left(p) > 0.0:
			sick.append(p)
	if sick.is_empty():
		Team.tell(peer, "The witch: \"Nobody's sick, dearie. Yet. Hehehe.\"")
		return
	var here := []
	for p in sick:
		var at := _patient_position(p)
		if at.distance_to(c) < 10.0:
			here.append(p)
	if here.is_empty():
		Team.tell(peer, "The witch: \"Bring me the guy, dearie. I can't cure what I can't see.\"")
		return
	var patient: int = here[0]
	var who: String = Team.players[patient]["name"]
	if not _witch_orders.has(patient):
		_witch_orders[patient] = _pick_ingredient()
	var want: String = _witch_orders[patient]
	if _take_from_cauldron(want, c):
		_witch_orders.erase(patient)
		Sfx.play_all("witch_cackle", c)
		if Team.is_alive(patient):
			Team.cure(patient)
			Team.tell(0, "The witch stirs, %s drinks something awful, and the poison is gone." % who)
		else:
			Team.revive(patient)
		return
	Team.tell(0, "The witch: \"For %s I need %s. Put it in my cauldron. Hurry, dearie.\"" % [
		who, _ingredient_text(want)])


func _patient_position(peer_id: int) -> Vector3:
	if not Team.is_alive(peer_id) and _bodies.has(peer_id):
		return _bodies[peer_id].global_position
	var p := _player(peer_id)
	return p.global_position if p else Vector3.INF


func _pick_ingredient() -> String:
	var options := []
	for entry in LOCATIONS:
		if _locations.has(entry[0]):
			options.append(entry[2])
	if options.is_empty():
		return "witch_finger"
	return options[randi() % options.size()]


func _ingredient_text(kind: String) -> String:
	for entry in LOCATIONS:
		if entry[2] == kind:
			return entry[3]
	return "a Witch's finger. They grow in the forest, if you know where to look"


## Host: a mushroom of `kind` lying in the cauldron, or in a basket right next to it.
func _take_from_cauldron(kind: String, c: Vector3) -> bool:
	var bowl := c + Vector3(0, 0.5, -2)
	for m in find_children("*", "", true, false):
		if m is MushroomScript and not m.removed and m.kind == kind and m.holder_id == 0:
			if m.global_position.distance_to(bowl) < 2.0:
				m.remove_from_play()
				return true
	for b in [_basket] + _spare_baskets:
		if not b.removed and b.global_position.distance_to(bowl) < 6.0 and b.take(kind, 1):
			return true
	return false


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


## A wooden signpost at (x, z) on the ground, board facing `yaw`, text on both sides.
func _signpost(text: String, at: Vector3, yaw: float, size := 36) -> void:
	var ground := Terrain.height(at.x, at.z)
	var post := StaticBody3D.new()
	post.position = Vector3(at.x, ground, at.z)
	post.rotation.y = yaw
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.2, 2.6, 0.2)
	col.shape = shape
	col.position.y = 1.3
	post.add_child(col)
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.42, 0.3, 0.18)
	var pole := MeshInstance3D.new()
	var pole_mesh := BoxMesh.new()
	pole_mesh.size = Vector3(0.14, 2.6, 0.14)
	pole.mesh = pole_mesh
	pole.position.y = 1.3
	pole.material_override = wood
	post.add_child(pole)
	var rows := text.split("\n")
	var longest := 0
	for row in rows:
		longest = maxi(longest, row.length())
	var em := size * 0.005  # metres per font size unit at pixel_size 0.005
	var board := MeshInstance3D.new()
	var board_mesh := BoxMesh.new()
	board_mesh.size = Vector3(longest * em * 0.58 + 0.3, rows.size() * em * 1.25 + 0.2, 0.06)
	board.mesh = board_mesh
	board.position.y = 1.9 + board_mesh.size.y / 2.0
	board.material_override = wood
	post.add_child(board)
	for side in [1.0, -1.0]:
		var label := Label3D.new()
		label.text = text
		label.font_size = size
		label.pixel_size = 0.005
		label.modulate = Color(0.95, 0.9, 0.75)
		label.outline_size = 0
		label.position = Vector3(0, board.position.y, 0.035 * side)
		label.rotation.y = 0.0 if side > 0.0 else PI
		post.add_child(label)
	add_child(post)


## A standing villager (no collision), playing its idle animation if it has one.
func _npc_model(path: String, pos: Vector3, yaw: float, height: float) -> Node3D:
	var model := _model(path, Vector3(height * 0.7, height, height * 0.7), pos, yaw)
	for anim in model.find_children("*", "AnimationPlayer", true, false):
		for name in ["idle", "Idle"]:
			if anim.has_animation(name):
				anim.get_animation(name).loop_mode = Animation.LOOP_LINEAR
				anim.play(name)
	return model
