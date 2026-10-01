extends "res://scripts/locations/location.gd"
## Sanatórium Hôrka: an abandoned 1960s trade-union sanatorium. A raised ground floor of patient
## rooms off one long dark corridor, and a "basement" (the souterrain under it) with the boiler
## room, the archive and the morgue, where Mother's Mould grows on the drawers of the dead.
##
## The Nurse walks the halls. She is blind and hunts by sound: running, clanging trays, the PA.
## Take the mould and the alarm goes off: red lights, the front door locks until morning, and
## everybody in the building hears it, her included. Ways out: the laundry chute (a slide from
## the laundry room down to the yard) or the broken window in the end room (a 4 m drop).
##
## Build frame: front (the porch) is +Z, the building spans x -20..20, z -11..11. Basement floor
## y 0, ground floor y 3.6. Root is turned so the porch faces the road.

const NurseScript := preload("res://scripts/locations/nurse.gd")
const INGREDIENT := "mothers_mould"
const FRONT_YAW := PI  # the road comes in from global -Z
const FY := 3.6  # ground floor level
const GC := 7.0  # ground floor ceiling
const BC := 3.3  # basement ceiling
const WHEELCHAIR := "res://assets/kenney/mini-characters-extra/wheelchair.glb"
const ANNOUNCEMENTS := [
	"Pacienti, vráťte sa do izieb.\nSestra robí obchôdzku.",
	"Návštevné hodiny skončili\nv roku 1991.",
	"Pán primár Hruška,\nvolajte márnicu. Opäť.",
	"Ticho na chodbách.\nOna počúva.",
	"Obed sa podáva o polnoci.\nNemeškajte.",
	"Pacient z izby 6\nsa vrátil. Privítajte ho.",
]

var _nurse: Node3D
var _lights: Array = []  # [OmniLight3D, base colour, base energy]
var _alarm := false
var _door_leaves: Array[Node3D] = []
var _door_block: StaticBody3D
var _locked_label: Label3D
var _pa_labels: Array[Label3D] = []
var _pa_spots: Array[Vector3] = []
var _pa_timer := 40.0
var _pa_clear := 0.0
var _alarm_sound := 0.0
var _night_window: OmniLight3D
var _night_glow: MeshInstance3D
var _rng := RandomNumberGenerator.new()
var _loud: Array = []
var _m := {}  # materials by role


func build() -> void:
	_begin(FRONT_YAW)
	_rng.seed = 1961
	_m = {
		"facade": _paint(Color(0.6, 0.55, 0.46)),
		"plinth": _paint(Color(0.36, 0.35, 0.33)),
		"plaster": _paint(Color(0.55, 0.55, 0.5)),
		"green": _paint(Color(0.17, 0.3, 0.25)),
		"bplaster": _paint(Color(0.42, 0.43, 0.4)),
		"bgreen": _paint(Color(0.2, 0.24, 0.22)),
		"tile": _paint(Color(0.55, 0.6, 0.58)),
		"floor": _paint(Color(0.36, 0.28, 0.23)),
		"concrete": _paint(Color(0.27, 0.28, 0.27)),
		"ceiling": _paint(Color(0.42, 0.42, 0.4)),
		"metal": _paint(Color(0.42, 0.44, 0.46)),
		"rust": _paint(Color(0.38, 0.2, 0.12)),
		"wood": _paint(Color(0.3, 0.19, 0.12)),
		"dark": _paint(Color(0.04, 0.05, 0.06), false),
		"glass": _paint(Color(0.08, 0.1, 0.12), false),
		"sheet": _paint(Color(0.75, 0.75, 0.7)),
		"mould": _paint(Color(0.22, 0.27, 0.18), true, 0.12),
		"red": _paint(Color(0.5, 0.06, 0.05)),
		"roof": _paint(Color(0.25, 0.25, 0.25)),
	}
	_build_shell()
	_build_ground_floor()
	_build_basement()
	_build_stairs()
	_build_chute()
	_build_porch()
	_build_yard()
	_build_lights()
	_build_props()
	_build_morgue()
	_build_nurse()
	for i in 3:
		var spot: Vector3 = [Vector3(17.7, 0, -9.0), Vector3(18.4, 0, -8.3), Vector3(17.0, 0, -8.1)][i]
		_ingredient("MothersMould%d" % i, INGREDIENT, spot, i * 2.1)
	_interior(AABB(Vector3(-19.7, -0.3, -10.7), Vector3(39.4, 7.4, 21.4)))
	_quiet_zones.append(AABB(Vector3(-19.6, -0.5, -10.6), Vector3(39.2, 7.5, 21.2)))
	_glass_zones.append(AABB(Vector3(-18.8, FY - 0.5, 8.4), Vector3(3.6, 2.0, 2.2)))  # under the broken window
	_glass_zones.append(AABB(Vector3(2.6, -0.5, -1.5), Vector3(2.2, 2.0, 1.7)))  # outside the morgue
	_finish()


# --- contract ------------------------------------------------------------------------------


func server_reset() -> void:
	_reset_ingredients()
	for prop in _loud:
		prop.reset_to_home()
	if _nurse:
		_nurse.reset()
	_pa_timer = _rng.randf_range(30.0, 60.0)
	_set_alarm.rpc(false)


func set_night(is_night: bool) -> void:
	night = is_night
	if _nurse:
		_nurse.night = is_night
	if _night_window:
		_night_window.visible = is_night
		_night_glow.visible = is_night


func entrance_position() -> Vector3:
	return _g(Vector3(0, 0, 21.0))


# --- running ---------------------------------------------------------------------------------


func _process(delta: float) -> void:
	_update_flicker()
	if _alarm:
		var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 1000.0 * 6.0)
		for entry in _lights:
			var light: OmniLight3D = entry[0]
			light.light_color = Color(1.0, 0.08, 0.05)
			light.light_energy = entry[2] * (0.4 + 1.4 * pulse)
		_alarm_sound -= delta
		if _alarm_sound <= 0.0:
			_alarm_sound = 2.5
			Sfx.play("police_siren", _g(Vector3(0, FY + 2.5, 0)))
	if _pa_clear > 0.0:
		_pa_clear -= delta
		if _pa_clear <= 0.0:
			for label in _pa_labels:
				label.text = ""


func _physics_process(delta: float) -> void:
	if not multiplayer.is_server():
		return
	_report_footsteps(delta)
	if not _alarm and _ingredient_taken():
		_trigger_alarm()
	_pa_timer -= delta
	if _pa_timer <= 0.0:
		_pa_timer = _rng.randf_range(35.0, 80.0)
		var line := _rng.randi() % ANNOUNCEMENTS.size()
		_pa.rpc(line)
		for spot in _pa_spots:
			Hearing.emit(_g(spot), 30.0)
		for p in _players_in(_quiet_zones):
			Team.tell(p.peer_id, "PA: \"%s\"" % ANNOUNCEMENTS[line].replace("\n", " "))


## Host: the mould was taken.
func _trigger_alarm() -> void:
	_set_alarm.rpc(true)
	var morgue := _g(Vector3(12, 1, -6))
	Hearing.emit(morgue, 90.0)
	if _nurse:
		_nurse.alert(Vector3(10, 0, -5))
	for p in _players_in(_quiet_zones):
		Team.tell(p.peer_id, "ALARM! The front door slams shut. Find another way out - quietly.")


## Every peer: alarm on (red lights, door locked) or off (new day).
@rpc("authority", "call_local", "reliable")
func _set_alarm(on: bool) -> void:
	_alarm = on
	_set_body(_door_block, on)
	_door_block.visible = false
	_locked_label.visible = on
	for i in _door_leaves.size():
		_door_leaves[i].rotation.y = 0.0 if on else (-1.75 if i == 0 else 1.75)
	if on:
		Sfx.play("police_siren", _g(Vector3(0, FY + 2.5, 0)))
		Sfx.play("door_close", _g(Vector3(0, FY + 1.3, 10.8)))
	else:
		for entry in _lights:
			entry[0].light_color = entry[1]
			entry[0].light_energy = entry[2]


## Every peer: the PA crackles.
@rpc("authority", "call_local", "reliable")
func _pa(line: int) -> void:
	for i in _pa_labels.size():
		_pa_labels[i].text = ANNOUNCEMENTS[line]
		Sfx.play("pa_chime", _g(_pa_spots[i]))
	_pa_clear = 9.0


# --- building: walls and floors ------------------------------------------------------------------


func _build_shell() -> void:
	var door := [-1.2, 1.2, FY, FY + 2.6]
	var window := [-17.6, -16.2, FY + 0.5, FY + 2.6]
	var chute := [-6.6, -5.4, FY, FY + 2.3]
	# Outer skin: grey plinth up to the ground floor, faded ochre above.
	_wall_run(true, 10.85, -20.0, 20.0, 0.0, 7.4, [door, window], _m["plinth"], _m["facade"], FY, 0.3)
	_wall_run(true, -10.85, -20.0, 20.0, 0.0, 7.4, [], _m["plinth"], _m["facade"], FY, 0.3)
	_wall_run(false, 19.85, -10.7, 10.7, 0.0, 7.4, [chute], _m["plinth"], _m["facade"], FY, 0.3)
	_wall_run(false, -19.85, -10.7, 10.7, 0.0, 7.4, [], _m["plinth"], _m["facade"], FY, 0.3)
	# Inner skin, per storey, two-tone like every Czechoslovak hospital corridor.
	for storey in [[0.0, BC, _m["bgreen"], _m["bplaster"]], [FY, GC, _m["green"], _m["plaster"]]]:
		var y0: float = storey[0]
		var y1: float = storey[1]
		_wall_run(true, 10.65, -19.7, 19.7, y0, y1, [door, window], storey[2], storey[3], y0 + 1.4, 0.1)
		_wall_run(true, -10.65, -19.7, 19.7, y0, y1, [], storey[2], storey[3], y0 + 1.4, 0.1)
		_wall_run(false, 19.65, -10.6, 10.6, y0, y1, [chute], storey[2], storey[3], y0 + 1.4, 0.1)
		_wall_run(false, -19.65, -10.6, 10.6, y0, y1, [], storey[2], storey[3], y0 + 1.4, 0.1)
	# Floors and ceilings. The ground floor slab has a hole for the stairs (x -1.3..1.3, z -9.5..-2).
	_slab(Vector3(-19.6, -0.2, -10.6), Vector3(19.6, 0.03, 10.6), _m["concrete"])
	var mid := [BC, FY]
	_slab(Vector3(-19.6, mid[0], -10.6), Vector3(-1.3, mid[1], 10.6), _m["floor"])
	_slab(Vector3(1.3, mid[0], -10.6), Vector3(19.6, mid[1], 10.6), _m["floor"])
	_slab(Vector3(-1.3, mid[0], -2.0), Vector3(1.3, mid[1], 10.6), _m["floor"])
	_slab(Vector3(-1.3, mid[0], -10.6), Vector3(1.3, mid[1], -9.5), _m["floor"])
	_slab(Vector3(-19.6, GC, -10.6), Vector3(19.6, GC + 0.4, 10.6), _m["ceiling"])
	# Roof: tar, a parapet, a water tank and an old aerial.
	_slab(Vector3(-20.1, 7.4, -11.1), Vector3(20.1, 7.5, 11.1), _m["roof"])
	_slab(Vector3(-20.1, 7.5, 10.8), Vector3(20.1, 8.3, 11.1), _m["facade"])
	_slab(Vector3(-20.1, 7.5, -11.1), Vector3(20.1, 8.3, -10.8), _m["facade"])
	_slab(Vector3(19.8, 7.5, -10.8), Vector3(20.1, 8.3, 10.8), _m["facade"])
	_slab(Vector3(-20.1, 7.5, -10.8), Vector3(-19.8, 8.3, 10.8), _m["facade"])
	_slab(Vector3(-14, 7.5, -7), Vector3(-10, 10.0, -3), _m["rust"])
	_slab(Vector3(8.0, 7.5, -2.0), Vector3(8.15, 12.0, -1.85), _m["metal"], false)
	_slab(Vector3(7.0, 11.0, -1.95), Vector3(9.2, 11.08, -1.9), _m["metal"], false)
	# Facade: a cornice at the ground floor line and pilasters every 5 m.
	_slab(Vector3(-20.15, FY - 0.25, 11.0), Vector3(20.15, FY, 11.2), _m["plaster"], false)
	_slab(Vector3(-20.15, FY - 0.25, -11.2), Vector3(20.15, FY, -11.0), _m["plaster"], false)
	for i in 9:
		var x := -20.0 + i * 5.0
		if absf(x) < 3.0:
			continue
		_slab(Vector3(x - 0.25, FY, 11.0), Vector3(x + 0.25, 7.4, 11.15), _m["facade"], false)
		_slab(Vector3(x - 0.25, FY, -11.15), Vector3(x + 0.25, 7.4, -11.0), _m["facade"], false)
	# Windows: boarded up, except the broken one in room 1.
	for x in [-11.5, -6.5, 6.5, 11.5, 16.8]:
		_window(Vector3(x, FY, 11.0), 0.0)
	for x in [-16.8, -11.5, -6.5, 6.5, 11.5, 16.8]:
		_window(Vector3(x, FY, -11.0), PI)
	for z in [-6.0, 6.0]:
		_window(Vector3(-20.0, FY, z), -PI / 2.0)
	_window(Vector3(20.0, FY, 6.0), PI / 2.0)
	for x in [-15.0, -9.0, -3.5, 3.5, 9.0, 15.0]:
		_cellar_window(Vector3(x, 2.2, 11.0), 0.0)
		_cellar_window(Vector3(x, 2.2, -11.0), PI)
	# The broken window: a frame, jagged glass, shards inside.
	var frame: Material = _m["wood"]
	_slab(Vector3(-17.7, FY + 0.4, 10.95), Vector3(-16.1, FY + 0.5, 11.15), frame, false)
	_slab(Vector3(-17.7, FY + 2.6, 10.95), Vector3(-16.1, FY + 2.7, 11.15), frame, false)
	for i in 4:
		var x := -17.5 + i * 0.4
		_slab(Vector3(x, FY + 2.2 - i * 0.07, 10.97), Vector3(x + 0.12, FY + 2.6, 10.99), _m["glass"], false)
	_scatter_glass(Vector3(-17.0, FY, 9.4), Vector2(1.6, 1.0), 26)
	_label("Pozor: sklo", Vector3(-15.4, FY + 1.6, 10.55), PI, 28, Color(0.5, 0.47, 0.4), true)


## A boarded window on the outside wall at `pos` (bottom centre at floor level), facing out (yaw).
func _window(pos: Vector3, yaw: float) -> void:
	var b := Basis(Vector3.UP, yaw)
	var o := pos
	_block(Vector3(1.6, 1.9, 0.06), Transform3D(b, o + b * Vector3(0, 1.75, 0.05)), _m["dark"], false)
	_block(Vector3(1.8, 0.12, 0.2), Transform3D(b, o + b * Vector3(0, 0.75, 0.1)), _m["plaster"], false)
	for i in 3:
		var plank := Basis(Vector3.UP, yaw) * Basis(Vector3.BACK, [0.25, -0.18, 0.05][i])
		_block(Vector3(1.85, 0.2, 0.04), Transform3D(plank, o + b * Vector3(0, 1.2 + i * 0.5, 0.11)),
			_m["wood"], false)
	# The inside of the same window: dark glass behind boards, so rooms aren't windowless.
	_block(Vector3(1.4, 1.7, 0.03), Transform3D(b, o + b * Vector3(0, 1.75, -0.36)), _m["glass"], false)


func _cellar_window(pos: Vector3, yaw: float) -> void:
	var b := Basis(Vector3.UP, yaw)
	_block(Vector3(0.9, 0.5, 0.06), Transform3D(b, pos + b * Vector3(0, 0, 0.05)), _m["dark"], false)
	for i in 4:
		_block(Vector3(0.04, 0.5, 0.04), Transform3D(b, pos + b * Vector3(-0.3 + i * 0.2, 0, 0.1)),
			_m["rust"], false)


func _scatter_glass(centre: Vector3, half: Vector2, count: int) -> void:
	var glass := _paint(Color(0.55, 0.7, 0.75), false, 0.15)
	for i in count:
		var p := centre + Vector3(_rng.randf_range(-half.x, half.x), 0.01, _rng.randf_range(-half.y, half.y))
		var basis := Basis(Vector3.UP, _rng.randf() * TAU)
		_block(Vector3(_rng.randf_range(0.05, 0.18), 0.01, _rng.randf_range(0.04, 0.12)),
			Transform3D(basis, p), glass, false)


func _build_ground_floor() -> void:
	var g: Material = _m["green"]
	var p: Material = _m["plaster"]
	var split := FY + 1.4
	var top := FY + 2.4
	var front := [
		[-17.5, -16.1, FY, top], [-12.2, -10.8, FY, top], [-7.2, -5.8, FY, top], [-3.9, 3.9, FY, FY + 2.9],
		[5.8, 7.2, FY, top], [10.8, 12.2, FY, top], [16.1, 17.5, FY, top],
	]
	var back := [
		[-17.5, -16.1, FY, top], [-12.2, -10.8, FY, top], [-7.2, -5.8, FY, top], [-3.6, -2.0, FY, top],
		[2.0, 3.6, FY, top], [5.8, 7.2, FY, top], [10.8, 12.2, FY, top], [16.1, 17.5, FY, top],
	]
	_wall_run(true, 1.6, -19.6, 19.6, FY, GC, front, g, p, split)
	_wall_run(true, -1.6, -19.6, 19.6, FY, GC, back, g, p, split)
	for x in [-14.0, -9.0, -4.0, 4.0, 9.0, 14.0]:
		_wall_run(false, x, 1.7, 10.6, FY, GC, [], g, p, split)
		_wall_run(false, x, -10.6, -1.7, FY, GC, [], g, p, split)
	# Skirting radiators and a long rubber runner down the corridor.
	_slab(Vector3(-19.5, FY, -0.6), Vector3(19.5, FY + 0.01, 0.6), _paint(Color(0.18, 0.2, 0.17)), false)
	for x in [-15.0, -8.5, 8.5, 15.0]:
		_slab(Vector3(x - 0.6, FY + 0.15, 1.38), Vector3(x + 0.6, FY + 0.75, 1.5), _m["metal"])
	# Room numbers over the doors.
	var n := 1
	for x in [-16.8, -11.5, -6.5, 6.5, 11.5, 16.8]:
		_label("%d" % n, Vector3(x, top + 0.3, 1.45), PI, 56, Color(0.75, 0.72, 0.62), true)
		n += 1
	for entry in [[-16.8, "7"], [-11.5, "8"], [-6.5, "9"], [6.5, "PRIMÁR"], [11.5, "PROCEDÚRY"],
			[16.8, "PRÁČOVŇA"]]:
		_label(entry[1], Vector3(entry[0], top + 0.3, -1.45), 0.0, 40, Color(0.75, 0.72, 0.62), true)
	_label("SCHODISKO\n↓ SUTERÉN", Vector3(-2.8, top + 0.45, -1.45), 0.0, 30, Color(0.75, 0.72, 0.62), true)
	_label("NEBEHAJTE\nPO CHODBÁCH!", Vector3(-9.0, FY + 2.1, 1.48), PI, 40, Color(0.55, 0.1, 0.08), true)
	_label("TICHO\nPACIENTI SPIA", Vector3(9.0, FY + 2.1, -1.48), 0.0, 40, Color(0.55, 0.1, 0.08), true)


func _build_basement() -> void:
	var g: Material = _m["bgreen"]
	var p: Material = _m["bplaster"]
	var split := 1.4
	var top := 2.3
	var front := [[-12.7, -11.3, 0.0, top], [-0.7, 0.7, 0.0, top], [9.3, 10.7, 0.0, top]]
	var back := [[-8.7, -7.3, 0.0, top], [-1.4, 1.4, 0.0, BC], [5.0, 7.0, 0.0, top], [16.0, 17.2, 0.0, top]]
	_wall_run(true, 1.6, -19.6, 19.6, 0.0, BC, front, g, p, split)
	_wall_run(true, -1.6, -19.6, 19.6, 0.0, BC, back, g, p, split)
	for x in [-4.0, 4.0]:
		_wall_run(false, x, 1.7, 10.6, 0.0, BC, [], g, p, split)
	for x in [-1.5, 1.5]:
		_wall_run(false, x, -10.6, -1.7, 0.0, BC, [], g, p, split)
	# Pipes along the corridor ceiling.
	for z in [-1.2, -0.9, 1.1]:
		_slab(Vector3(-19.5, BC - 0.35, z - 0.08), Vector3(19.5, BC - 0.2, z + 0.08), _m["rust"], false)
	_label("MÁRNICA →", Vector3(3.6, 2.2, -1.48), 0.0, 44, Color(0.7, 0.68, 0.6), true)
	_label("← KOTOLŇA", Vector3(-6.0, 2.2, -1.48), 0.0, 44, Color(0.7, 0.68, 0.6), true)
	_label("ARCHÍV", Vector3(-12.0, 2.6, 1.48), PI, 40, Color(0.7, 0.68, 0.6), true)
	_label("AGREGÁT", Vector3(0.0, 2.6, 1.48), PI, 40, Color(0.7, 0.68, 0.6), true)
	_label("CHLADIACA\nMIESTNOSŤ", Vector3(10.0, 2.7, 1.48), PI, 30, Color(0.7, 0.68, 0.6), true)
	_scatter_glass(Vector3(3.7, 0.0, -0.65), Vector2(1.0, 0.8), 30)


func _build_stairs() -> void:
	# Down from the back of the stairwell (ground floor) to the basement corridor.
	var top := Vector3(0, FY, -9.5)
	var bottom := Vector3(0, 0, -2.0)
	_ramp(top, bottom, 2.6)
	_steps(top, bottom, 2.6, 18, _m["concrete"], 0.0)
	# Railings round the hole upstairs.
	for x in [-1.38, 1.38]:
		_slab(Vector3(x - 0.04, FY, -9.5), Vector3(x + 0.04, FY + 1.0, -2.0), _m["metal"])
	_slab(Vector3(-1.42, FY, -2.06), Vector3(1.42, FY + 1.0, -1.98), _m["metal"])
	_label("↓ SUTERÉN\nMÁRNICA", Vector3(0, FY + 2.2, -10.5), 0.0, 40, Color(0.7, 0.68, 0.6), true)


## The laundry chute: a steel trough from the laundry room out through the east wall into the yard.
## Too steep to stand on, so you slide; there's no climbing back up.
func _build_chute() -> void:
	var top := Vector3(19.6, FY, -6.0)
	var bottom := Vector3(22.9, -0.1, -6.0)
	_ramp(top, bottom, 1.2, _m["metal"])
	for side in [-0.65, 0.65]:
		_chute_side(top, bottom, side)
	# A hood over the top, and laundry piled where you land.
	_slab(Vector3(20.0, FY + 2.3, -6.8), Vector3(21.2, FY + 2.45, -5.2), _m["rust"], false)
	for i in 5:
		var p := Vector3(23.6 + _rng.randf_range(-0.6, 0.8), 0, -6.0 + _rng.randf_range(-0.9, 0.9))
		_block(Vector3(0.9, 0.45, 0.7), Transform3D(Basis(Vector3.UP, _rng.randf() * TAU), p + Vector3(0, 0.2, 0)),
			_m["sheet"], false)
	_label("NÚDZOVÝ VÝCHOD\n(PRÁČOVŇA)", Vector3(19.5, FY + 2.6, -6.0), -PI / 2.0, 34, Color(0.2, 0.9, 0.35))
	_label("BIELIZEŇ", Vector3(20.6, FY + 2.6, -6.0), PI / 2.0, 34, Color(0.6, 0.55, 0.45), true)


func _chute_side(top: Vector3, bottom: Vector3, side: float) -> void:
	var run := bottom - top
	var fwd := run.normalized()
	var up := Vector3.BACK.cross(fwd).normalized()
	if up.y < 0.0:
		up = -up
	var basis := Basis(up.cross(fwd).normalized(), up, fwd)
	var centre := (top + bottom) / 2.0 + Vector3(0, 0, side) + up * 0.45
	_block(Vector3(0.08, 0.9, run.length()), Transform3D(basis, centre), _m["metal"], true)


func _build_porch() -> void:
	_slab(Vector3(-5.0, 0.0, 11.0), Vector3(5.0, FY, 13.6), _m["plinth"])
	_slab(Vector3(-5.0, FY - 0.05, 11.0), Vector3(5.0, FY, 13.6), _m["floor"])
	var top := Vector3(0, FY, 13.6)
	var bottom := Vector3(0, 0, 19.6)
	_ramp(top, bottom, 6.0)
	_steps(top, bottom, 6.0, 18, _m["plinth"], 0.0)
	# Wedge cheeks either side of the steps (solid walls hidden by the steps' sides).
	for x in [-3.2, 3.2]:
		_ramp(Vector3(x, FY + 0.9, 13.6), Vector3(x, 0.9, 19.6), 0.3, _m["plinth"])
	# Canopy on four columns.
	for x in [-4.5, -1.6, 1.6, 4.5]:
		_slab(Vector3(x - 0.2, FY, 13.0), Vector3(x + 0.2, 6.6, 13.4), _m["plaster"])
	_slab(Vector3(-5.3, 6.6, 11.0), Vector3(5.3, 7.0, 13.8), _m["plaster"])
	_label("ZOTAVOVŇA ROH", Vector3(0, 6.8, 13.82), 0.0, 64, Color(0.3, 0.12, 0.08), true)
	_label("SANATÓRIUM HÔRKA", Vector3(0, 8.6, 11.15), 0.0, 220, Color(0.55, 0.16, 0.1), true)
	_label("★", Vector3(0, 9.9, 11.15), 0.0, 200, Color(0.55, 0.12, 0.08), true)
	# The front door: two leaves that stand open by day and slam shut on alarm.
	for i in 2:
		var hinge := Node3D.new()
		hinge.position = Vector3(-1.2 if i == 0 else 1.2, FY, 10.85)
		_root.add_child(hinge)
		var leaf := MeshInstance3D.new()
		var leaf_mesh := BoxMesh.new()
		leaf_mesh.size = Vector3(1.2, 2.6, 0.08)
		leaf.mesh = leaf_mesh
		leaf.material_override = _paint(Color(0.22, 0.3, 0.24))
		leaf.position = Vector3(0.6 if i == 0 else -0.6, 1.3, 0)
		hinge.add_child(leaf)
		hinge.rotation.y = -1.75 if i == 0 else 1.75
		_door_leaves.append(hinge)
	_door_block = StaticBody3D.new()
	_door_block.name = "DoorBlock"
	_door_block.position = Vector3(0, FY + 1.3, 10.85)
	var shape := BoxShape3D.new()
	shape.size = Vector3(2.4, 2.6, 0.3)
	var col := CollisionShape3D.new()
	col.shape = shape
	col.disabled = true
	_door_block.add_child(col)
	_root.add_child(_door_block)
	_locked_label = _label("ZAMKNUTÉ", Vector3(0, FY + 2.85, 10.5), PI, 48, Color(1.0, 0.15, 0.1))
	_locked_label.visible = false
	_board("VSTUP ZAKÁZANÝ\nObjekt v správe ROH.\nNebezpečenstvo úrazu.", Vector3(3.6, FY + 1.3, 11.3), 0.0,
		Vector2(1.5, 1.0), Color(0.75, 0.72, 0.62), Color(0.5, 0.06, 0.04), 36)


func _build_yard() -> void:
	# A rusty iron fence round the front, broken in places, with a gate on the road side.
	var fence := GRAVE + "iron-fence.glb"
	var r := 29.0
	for i in 34:
		var a := -PI * 0.08 + i * (PI * 1.16 / 34.0)
		var p := Vector3(cos(a) * r, 0, sin(a) * r)
		if absf(p.x) < 3.2 and p.z > 0.0:
			continue  # the gate
		if i % 7 == 3:
			continue  # fallen sections
		_tint(_solid(fence, Vector3(2.7, 1.6, 0.3), p, -a + PI / 2.0), Color(0.13, 0.11, 0.1))
	for x in [-3.4, 3.4]:
		_slab(Vector3(x - 0.3, 0, r - 0.3), Vector3(x + 0.3, 2.6, r + 0.3), _m["plinth"])
	_board("SANATÓRIUM HÔRKA\nliečebňa dýchacích ciest", Vector3(-3.4, 2.9, r + 0.35), 0.0,
		Vector2(2.4, 0.8), Color(0.62, 0.6, 0.55), Color(0.15, 0.17, 0.2), 34)
	_board("VSTUP\nZAKÁZANÝ", Vector3(3.4, 2.0, r + 0.35), 0.0, Vector2(1.2, 0.8),
		Color(0.85, 0.82, 0.7), Color(0.6, 0.05, 0.03), 44)
	var gate: Node3D = _solid(fence, Vector3(2.7, 1.6, 0.3), Vector3(1.6, 0, r + 2.0), 1.1)
	_tint(gate, Color(0.13, 0.11, 0.1))
	gate.rotation.z = 0.05
	# Dead trees, a bench, overgrowth.
	for p in [Vector3(-24, 0, 14), Vector3(24, 0, 12), Vector3(-25, 0, -8), Vector3(26, 0, -14)]:
		var tree := _solid(GRAVE + "pine-crooked.glb", Vector3(3.5, 8.0, 3.5), p, p.x * 0.3)
		_tint(tree, Color(0.2, 0.17, 0.14))
	for i in 14:
		var side := -1.0 if i % 2 == 0 else 1.0
		var x := side * _rng.randf_range(6.0, 19.0)
		var path: String = NATURE + ["plant_bushLarge.glb", "plant_bushDetailed.glb", "plant_flatTall.glb"][i % 3]
		_model(path, Vector3(1.4, 1.2, 1.4), Vector3(x, 0, 11.8 + _rng.randf_range(0.0, 1.5)), _rng.randf() * TAU)
	for i in 8:
		var z := _rng.randf_range(-9.0, 9.0)
		_model(NATURE + "plant_bushLarge.glb", Vector3(1.6, 1.3, 1.6), Vector3(-21.2, 0, z), _rng.randf() * TAU)
	_model(FURNITURE + "bench.glb", Vector3(1.6, 0.8, 0.6), Vector3(-9, 0, 18), 0.2)
	_model(WHEELCHAIR, Vector3(0.7, 0.95, 0.9), Vector3(7.5, 0, 17.5), 2.4)


func _build_lights() -> void:
	var cold := Color(0.75, 0.85, 1.0)
	var warm := Color(1.0, 0.78, 0.5)
	var green := Color(0.6, 1.0, 0.75)
	var specs := [
		[Vector3(-11.0, GC - 0.4, 0.0), cold, 1.1, 8.0, true],
		[Vector3(11.0, GC - 0.4, 0.0), cold, 0.7, 7.0, false],
		[Vector3(0.0, GC - 0.4, 6.0), warm, 0.9, 8.0, true],
		[Vector3(0.0, GC - 0.6, -6.0), Color(1.0, 0.25, 0.15), 0.6, 6.0, false],
		[Vector3(-9.0, BC - 0.4, 0.0), cold, 0.9, 7.0, true],
		[Vector3(8.0, BC - 0.4, 0.0), green, 0.6, 6.5, false],
		[Vector3(12.0, BC - 0.4, -6.0), green, 1.2, 9.0, true],
	]
	for s in specs:
		var light := _lamp(s[0], s[1], s[2], s[3], s[4])
		_lights.append([light, s[1], s[2]])
		_model(FURNITURE + "lampSquareCeiling.glb", Vector3(0.6, 0.25, 0.6), s[0] + Vector3(0, 0.15, 0))
	# Someone's light in room 6, at night only. Seen from the road.
	_night_window = _lamp(Vector3(16.8, FY + 1.8, 9.2), Color(1.0, 0.55, 0.25), 1.2, 4.5)
	_night_window.visible = false
	_night_glow = MeshInstance3D.new()
	var glow_mesh := BoxMesh.new()
	glow_mesh.size = Vector3(1.3, 1.6, 0.02)
	_night_glow.mesh = glow_mesh
	_night_glow.material_override = _paint(Color(1.0, 0.5, 0.2), false, 1.5)
	_night_glow.position = Vector3(16.8, FY + 1.75, 11.12)
	_night_glow.visible = false
	_root.add_child(_night_glow)


func _build_props() -> void:
	# Patient rooms: two beds, a bedside table, a chair; some knocked about.
	var rooms := [
		[-16.8, 6.0, 0.0], [-11.5, 6.0, 0.1], [-6.5, 6.0, -0.3], [11.5, 6.0, 0.0], [16.8, 6.0, 0.2],
		[-16.8, -6.0, PI], [-11.5, -6.0, PI + 0.2], [-6.5, -6.0, PI],
	]
	for i in rooms.size():
		var r: Array = rooms[i]
		var c := Vector3(r[0], FY, r[1])
		var inward := 1.0 if r[1] > 0.0 else -1.0
		for side in [-1.2, 1.2]:
			var tilt := 0.6 if (i + int(side)) % 3 == 0 else 0.0
			_solid(FURNITURE + "bedSingle.glb", Vector3(1.0, 0.65, 2.0), c + Vector3(side, 0, inward * 2.0), r[2] + tilt)
		_solid(FURNITURE + "sideTable.glb", Vector3(0.5, 0.55, 0.45), c + Vector3(0, 0, inward * 3.6), r[2])
		_model(FURNITURE + "chair.glb", Vector3(0.5, 0.9, 0.5), c + Vector3(1.6, 0, -inward * 1.6), r[2] + 2.0 + i)
	# Room 4 (front, east of the lobby) is the dayroom: a TV that sometimes turns itself on.
	var day := Vector3(6.5, FY, 6.0)
	_solid(FURNITURE + "cabinetTelevision.glb", Vector3(1.2, 0.5, 0.5), day + Vector3(0, 0, 3.8), PI)
	_model(FURNITURE + "televisionVintage.glb", Vector3(0.7, 0.6, 0.5), day + Vector3(0, 0.5, 3.8), PI)
	for i in 4:
		_model(FURNITURE + "chairCushion.glb", Vector3(0.6, 0.9, 0.6), day + Vector3(-1.5 + i, 0, 0.5), PI + (i - 1.5) * 0.3)
	# Primár's office (back, east).
	var office := Vector3(6.5, FY, -6.0)
	_solid(FURNITURE + "desk.glb", Vector3(1.6, 0.8, 0.8), office + Vector3(0, 0, -1.5), 0.0)
	_model(FURNITURE + "chairDesk.glb", Vector3(0.6, 1.0, 0.6), office + Vector3(0, 0, -2.4), 0.0)
	_solid(FURNITURE + "bookcaseClosedWide.glb", Vector3(1.8, 2.0, 0.5), office + Vector3(0, 0, -4.2), 0.0)
	_model(FURNITURE + "radio.glb", Vector3(0.4, 0.25, 0.2), office + Vector3(0.5, 0.8, -1.5), 0.3)
	# Procedures room: tubs for the "healing waters".
	var proc := Vector3(11.5, FY, -6.0)
	_solid(FURNITURE + "bathtub.glb", Vector3(0.9, 0.6, 1.9), proc + Vector3(-1.2, 0, -2.5), 0.0)
	_solid(FURNITURE + "bathtub.glb", Vector3(0.9, 0.6, 1.9), proc + Vector3(1.2, 0, -2.5), 0.0)
	_solid(FURNITURE + "bathroomSink.glb", Vector3(0.6, 0.9, 0.5), proc + Vector3(2.0, 0, 1.5), -PI / 2.0)
	# Laundry: washers, a sorting table, the chute hatch (on the east wall).
	var laundry := Vector3(16.8, FY, -6.0)
	for i in 3:
		_solid(FURNITURE + "washer.glb", Vector3(0.75, 0.9, 0.75), laundry + Vector3(-1.8 + i * 0.85, 0, -4.0), 0.0)
	_solid(FURNITURE + "table.glb", Vector3(1.6, 0.8, 0.8), laundry + Vector3(-1.5, 0, 1.0), PI / 2.0)
	# The lobby: a reception desk, a row of chairs, a dead plant, the notice board, the PA.
	var lobby := Vector3(0, FY, 6.0)
	_solid(FURNITURE + "kitchenBar.glb", Vector3(2.6, 1.1, 0.7), lobby + Vector3(-2.4, 0, -0.5), PI / 2.0)
	_model(FURNITURE + "chairDesk.glb", Vector3(0.6, 1.0, 0.6), lobby + Vector3(-3.2, 0, -0.5), PI / 2.0)
	for i in 4:
		_model(FURNITURE + "chairCushion.glb", Vector3(0.6, 0.9, 0.6), lobby + Vector3(3.3, 0, -1.6 + i * 0.75), -PI / 2.0)
	_model(FURNITURE + "pottedPlant.glb", Vector3(0.6, 1.2, 0.6), lobby + Vector3(-3.3, 0, 4.0), 0.0)
	_model(FURNITURE + "coatRackStanding.glb", Vector3(0.5, 1.8, 0.5), lobby + Vector3(3.3, 0, 4.0), 0.4)
	_board("ROZPIS PROCEDÚR\n07:00 rozcvička\n08:00 inhalácie\n12:00 obed\n00:00 sestra robí obchôdzku\n"
		+ "Nebehajte. Nekričte. Sestra počuje všetko.", lobby + Vector3(-3.92, 1.7, 1.5), PI / 2.0,
		Vector2(1.7, 1.3), Color(0.32, 0.26, 0.18), Color(0.85, 0.82, 0.72), 22)
	_pa_speaker(lobby + Vector3(0, 2.7, 4.5), PI)
	_pa_speaker(Vector3(-12.0, 2.6, -1.4), 0.0)
	# Corridors: wheelchairs, gurneys, a tray trolley, a bench, a mop bucket.
	_model(WHEELCHAIR, Vector3(0.7, 0.95, 0.9), Vector3(-14.5, FY, -0.9), 0.4)
	_model(WHEELCHAIR, Vector3(0.7, 0.95, 0.9), Vector3(13.6, FY, 1.0), 2.8)
	_model(WHEELCHAIR, Vector3(0.7, 0.95, 0.9), Vector3(-5.0, 0, 0.9), -1.2)
	_model(FURNITURE + "bench.glb", Vector3(1.6, 0.6, 0.5), Vector3(-2.5, FY, 1.2), PI)
	_loud.append(_gurney("Gurney1", Vector3(-8.0, FY, -0.8), PI / 2.0, false))
	_loud.append(_gurney("Gurney2", Vector3(15.2, 0, -0.6), PI / 2.0 + 0.2, true))
	_loud.append(_gurney("Gurney3", Vector3(2.8, FY, 0.9), PI / 2.0, false))
	_slab(Vector3(4.6, FY, -1.45), Vector3(5.6, FY + 0.85, -0.95), _m["metal"])  # tray trolley
	for i in 3:
		_loud.append(_loud_prop("SteelTray%d" % i, "", Vector3(0.45, 0.04, 0.32),
			Vector3(4.85 + i * 0.25, FY + 0.87 + i * 0.05, -1.2), 1.0, 34.0, "tray_drop", 0.2 * i))
	_loud.append(_loud_prop("MopBucket", SURVIVAL + "bucket.glb", Vector3(0.45, 0.45, 0.45),
		Vector3(-17.5, 0, 0.8), 3.0, 28.0, "metal_hit"))
	_loud.append(_loud_prop("Bedpan", SURVIVAL + "bucket.glb", Vector3(0.35, 0.25, 0.35),
		Vector3(-11.2, FY, 3.6), 1.0, 26.0, "tray_drop"))
	for prop in _loud:
		prop.set("_quiet_for", 3.0)
	# Basement rooms: boiler, archive, generator, cold room.
	_slab(Vector3(-15.5, 0, -9.0), Vector3(-12.5, 2.4, -6.0), _m["rust"])
	_slab(Vector3(-14.5, 2.4, -7.9), Vector3(-13.5, BC, -7.1), _m["rust"], false)
	_slab(Vector3(-19.5, 0, -10.5), Vector3(-17.0, 0.6, -8.0), _paint(Color(0.08, 0.08, 0.08)))
	for i in 4:
		_solid(FURNITURE + "bookcaseOpen.glb", Vector3(1.0, 2.0, 0.4), Vector3(-17.0 + i * 1.6, 0, 5.0), 0.2 * (i % 2))
		_model(FURNITURE + "cardboardBoxClosed.glb", Vector3(0.5, 0.4, 0.5), Vector3(-16.5 + i * 1.4, 0, 8.0), i)
	_slab(Vector3(-1.5, 0, 6.0), Vector3(1.5, 1.6, 8.5), _paint(Color(0.25, 0.3, 0.22)))
	_label("AGREGÁT 3x380V\nNEDOTÝKAŤ SA", Vector3(0, 1.0, 5.98), PI, 24, Color(0.85, 0.75, 0.2), true)
	for i in 4:
		_solid(FURNITURE + "washer.glb", Vector3(0.75, 0.9, 0.75), Vector3(12.0 + i * 0.9, 0, 9.8), PI)


func _pa_speaker(pos: Vector3, yaw: float) -> void:
	_model(FURNITURE + "speaker.glb", Vector3(0.45, 0.5, 0.3), pos, yaw)
	var label := _label("", pos + Basis(Vector3.UP, yaw) * Vector3(0, -0.45, 0.25), yaw, 26,
		Color(0.9, 0.85, 0.6))
	_pa_labels.append(label)
	_pa_spots.append(pos)


## A hospital gurney you can push (or throw): it clatters, and the Nurse hears it.
func _gurney(prop_name: String, pos: Vector3, yaw: float, covered: bool) -> RigidBody3D:
	var size := Vector3(0.75, 0.9, 2.0)
	var prop := _loud_prop(prop_name, "", size, pos, 25.0, 40.0, "gurney", yaw)
	for child in prop.get_children():
		if child is MeshInstance3D:
			child.visible = false
	var metal: Material = _m["metal"]
	var parts := [
		[Vector3(0.75, 0.08, 2.0), Vector3(0, 0.3, 0), metal],
		[Vector3(0.7, 0.1, 1.9), Vector3(0, 0.39, 0), _m["sheet"]],
	]
	for x in [-0.32, 0.32]:
		for z in [-0.9, 0.9]:
			parts.append([Vector3(0.05, 0.8, 0.05), Vector3(x, -0.1, z), metal])
			parts.append([Vector3(0.08, 0.1, 0.1), Vector3(x, -0.42, z), _m["dark"]])
	if covered:
		parts.append([Vector3(0.5, 0.25, 1.7), Vector3(0, 0.55, 0.05), _m["sheet"]])
		parts.append([Vector3(0.3, 0.22, 0.3), Vector3(0, 0.55, -0.85), _m["sheet"]])
	for part in parts:
		var mi := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = part[0]
		mi.mesh = mesh
		mi.material_override = part[2]
		mi.position = part[1]
		prop.add_child(mi)
	return prop


func _build_morgue() -> void:
	# White tiles to shoulder height, the wall of drawers at the back, two slabs, a scale, a drain.
	var tile: Material = _m["tile"]
	_slab(Vector3(1.62, 0.0, -10.58), Vector3(19.58, 1.8, -10.55), tile, false)
	_slab(Vector3(1.62, 0.0, -1.72), Vector3(19.58, 1.8, -1.68), tile, false)
	_slab(Vector3(19.52, 0.0, -10.58), Vector3(19.55, 1.8, -1.7), tile, false)
	_slab(Vector3(2.5, 0.0, -10.55), Vector3(19.0, 2.6, -9.85), _m["metal"])
	for row in 3:
		for col in 8:
			var x := 3.1 + col * 2.05
			var y := 0.45 + row * 0.8
			_slab(Vector3(x - 0.42, y - 0.32, -9.86), Vector3(x + 0.42, y + 0.32, -9.8), _paint(Color(0.55, 0.57, 0.58)), false)
			_slab(Vector3(x - 0.15, y - 0.03, -9.8), Vector3(x + 0.15, y + 0.03, -9.74), _m["dark"], false)
			_label("%d" % (row * 8 + col + 1), Vector3(x, y + 0.18, -9.79), 0.0, 20, Color(0.1, 0.1, 0.1), true)
	# One drawer hangs open, with a foot out.
	_slab(Vector3(15.4, 1.0, -9.8), Vector3(16.2, 1.12, -8.4), _m["metal"])
	_slab(Vector3(15.6, 1.12, -8.9), Vector3(16.0, 1.3, -8.45), _m["sheet"], false)
	for x in [8.5, 12.5]:
		_slab(Vector3(x - 0.5, 0.0, -7.6), Vector3(x + 0.5, 0.85, -5.6), _m["metal"])
		_slab(Vector3(x - 0.35, 0.85, -7.4), Vector3(x + 0.35, 1.1, -5.8), _m["sheet"], false)
		_slab(Vector3(x - 0.12, 0.85, -7.5), Vector3(x + 0.12, 1.15, -7.25), _m["sheet"], false)
	_solid(FURNITURE + "bathroomSink.glb", Vector3(0.6, 0.9, 0.5), Vector3(3.0, 0, -2.2), PI)
	_slab(Vector3(10.2, 0.001, -4.0), Vector3(10.8, 0.01, -3.4), _m["dark"], false)
	_loud.append(_loud_prop("Scalpels", "", Vector3(0.4, 0.04, 0.3), Vector3(12.5, 1.1, -5.6), 0.8, 30.0, "tray_drop"))
	# The mould: grey-green bloom crawling over the drawers and the floor in the corner.
	for i in 22:
		var x := _rng.randf_range(15.0, 19.4)
		var y := _rng.randf_range(0.05, 2.5)
		var s := _rng.randf_range(0.2, 0.7)
		_slab(Vector3(x - s, y - s * 0.6, -9.74), Vector3(x + s, y + s * 0.6, -9.7), _m["mould"], false)
	for i in 14:
		var p := Vector3(_rng.randf_range(15.5, 19.3), 0.0, _rng.randf_range(-9.7, -7.2))
		var s := _rng.randf_range(0.2, 0.6)
		_slab(p - Vector3(s, 0, s * 0.7), p + Vector3(s, 0.02, s * 0.7), _m["mould"], false)
	_label("PATOLÓGIA - MÁRNICA\nVstup len pre personál", Vector3(6.0, 2.85, -1.75), PI, 30,
		Color(0.7, 0.68, 0.6), true)


func _build_nurse() -> void:
	var graph := AStar3D.new()
	var ids := {}
	var add := func(key: String, p: Vector3) -> void:
		var id := graph.get_available_point_id()
		graph.add_point(id, p)
		ids[key] = id
	var link := func(a: String, b: String) -> void:
		graph.connect_points(ids[a], ids[b])
	# Ground floor corridor, its rooms, the lobby, the stairwell.
	var gx := [-16.8, -11.5, -6.5, -2.8, 0.0, 2.8, 6.5, 11.5, 16.8]
	for i in gx.size():
		add.call("g%d" % i, Vector3(gx[i], FY, 0))
		if i > 0:
			link.call("g%d" % (i - 1), "g%d" % i)
	for i in [0, 1, 2, 6, 7, 8]:
		add.call("gf%d" % i, Vector3(gx[i], FY, 5.5))
		link.call("g%d" % i, "gf%d" % i)
		add.call("gb%d" % i, Vector3(gx[i], FY, -5.0))
		link.call("g%d" % i, "gb%d" % i)
	add.call("lobby", Vector3(0, FY, 5.0))
	add.call("door", Vector3(0, FY, 9.6))
	link.call("lobby", "door")
	for k in ["g3", "g4", "g5"]:
		link.call("lobby", k)
	add.call("sl1", Vector3(-2.8, FY, -5.0))
	add.call("sl2", Vector3(-2.8, FY, -10.1))
	add.call("sr1", Vector3(2.8, FY, -5.0))
	add.call("sr2", Vector3(2.8, FY, -10.1))
	add.call("stop", Vector3(0, FY, -10.1))
	add.call("sedge", Vector3(0, FY, -9.5))
	add.call("sfoot", Vector3(0, 0, -2.0))
	for pair in [["g3", "sl1"], ["sl1", "sl2"], ["sl2", "stop"], ["g5", "sr1"], ["sr1", "sr2"], ["sr2", "stop"],
			["stop", "sedge"], ["sedge", "sfoot"]]:
		link.call(pair[0], pair[1])
	# Basement corridor and rooms.
	var bx := [-16.8, -12.0, -8.0, -3.0, 0.0, 3.0, 6.0, 10.0, 16.6]
	for i in bx.size():
		add.call("b%d" % i, Vector3(bx[i], 0, 0))
		if i > 0:
			link.call("b%d" % (i - 1), "b%d" % i)
	link.call("sfoot", "b4")
	add.call("boiler", Vector3(-8.0, 0, -5.0))
	add.call("boiler2", Vector3(-11.0, 0, -4.5))
	link.call("b2", "boiler")
	link.call("boiler", "boiler2")
	add.call("archive", Vector3(-12.0, 0, 3.6))
	link.call("b1", "archive")
	add.call("gen", Vector3(0, 0, 4.5))
	link.call("b4", "gen")
	add.call("cold", Vector3(10.0, 0, 5.5))
	add.call("cold2", Vector3(15.0, 0, 5.5))
	link.call("b7", "cold")
	link.call("cold", "cold2")
	for i in 4:
		add.call("m%d" % i, Vector3([6.0, 10.0, 14.0, 16.6][i], 0, -4.5))
		if i > 0:
			link.call("m%d" % (i - 1), "m%d" % i)
	link.call("b6", "m0")
	link.call("b8", "m3")
	_nurse = NurseScript.new()
	_nurse.graph = graph
	_root.add_child(_nurse)
	_nurse.build(CHARS + "character-female-b.glb", Vector3(3.0, 0, 0), 1961)
