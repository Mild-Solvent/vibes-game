extends "res://scripts/locations/location.gd"
## Kaplnka sv. Urbana: a little hilltop chapel on a stone podium, with an organ, candles that keep
## going out, and stairs behind the pews down to the crypt, where Bone morels grow on the saint's
## coffin. Take one and the three skeletons in the niches wake up: they only move while nobody is
## looking at them. The middle of the crypt floor is rotten: more than two people on it and it
## drops them into the ossuary pit below (there's a ramp of bones back up).
##
## Build frame: the door faces +Z. Pit floor y 0, crypt floor y 2.2, chapel floor y 4.9.

const SkeletonScript := preload("res://scripts/locations/skeleton.gd")
const INGREDIENT := "bone_morel"
const FRONT_YAW := -PI / 4.0  # the road comes in from global -X +Z
const PF := 0.03  # pit floor
const KF := 2.2  # crypt floor
const KC := 4.6  # crypt ceiling
const CF := 4.9  # chapel floor
const WT := 10.0  # chapel wall top
const MIDDLE := AABB(Vector3(-2.0, KF - 0.3, -4.0), Vector3(4.0, 1.8, 6.0))
## Candles that can go out: [position, energy]
const CANDLES := [
	[Vector3(-0.7, CF + 1.35, -7.6), 1.0], [Vector3(0.7, CF + 1.35, -7.6), 1.0],
	[Vector3(3.4, CF + 1.4, -2.9), 0.7], [Vector3(0.0, KF + 1.25, 3.1), 0.9],
]

var _skeletons: Array = []
var _awake := false
var _floor_gone := false
var _floor: StaticBody3D
var _pit_ids: Array[int] = []
var _graph: AStar3D
var _candles: Array[OmniLight3D] = []
var _flames: Array[MeshInstance3D] = []
var _candle_timer := 30.0
var _organ_timer := 90.0
var _creak_cd := 0.0
var _rng := RandomNumberGenerator.new()
var _m := {}


func build() -> void:
	_begin(FRONT_YAW)
	_rng.seed = 1347
	_m = {
		"stone": _paint(Color(0.45, 0.43, 0.4)),
		"dark_stone": _paint(Color(0.3, 0.29, 0.27)),
		"plaster": _paint(Color(0.62, 0.6, 0.55)),
		"floor": _paint(Color(0.38, 0.33, 0.28)),
		"wood": _paint(Color(0.28, 0.17, 0.1)),
		"roof": _paint(Color(0.22, 0.2, 0.2)),
		"bone": _paint(Color(0.78, 0.74, 0.62)),
		"earth": _paint(Color(0.22, 0.18, 0.14)),
		"metal": _paint(Color(0.55, 0.5, 0.35)),
		"flame": _paint(Color(1.0, 0.7, 0.3), false, 3.0),
	}
	_build_podium()
	_build_chapel()
	_build_crypt()
	_build_pit()
	_build_organ()
	_build_candles()
	_build_yard()
	_build_skeletons()
	for i in 3:
		var spot: Vector3 = [Vector3(-0.35, KF + 1.05, 3.5), Vector3(0.0, KF + 1.05, 3.9), Vector3(0.35, KF + 1.05, 3.4)][i]
		_ingredient("BoneMorel%d" % i, INGREDIENT, spot, i * 1.3)
	_interior(AABB(Vector3(-4.7, PF - 0.1, -8.7), Vector3(9.4, WT + 3.0, 13.4)), Color(0.04, 0.04, 0.05))
	_quiet_zones.append(AABB(Vector3(-4.7, PF - 0.1, -8.7), Vector3(9.4, WT, 13.4)))
	_finish()


# --- contract ------------------------------------------------------------------------------


func server_reset() -> void:
	_reset_ingredients()
	for s in _skeletons:
		s.reset()
	_awake = false
	_set_floor.rpc(true)
	for i in _candles.size():
		_set_candle.rpc(i, true)
	_candle_timer = _rng.randf_range(25.0, 45.0)


func set_night(is_night: bool) -> void:
	night = is_night


func entrance_position() -> Vector3:
	return _g(Vector3(0, 0, 14.0))


# --- running ---------------------------------------------------------------------------------


func _process(_delta: float) -> void:
	var t := Time.get_ticks_msec() / 1000.0
	for i in _candles.size():
		if _candles[i].visible:
			_candles[i].light_energy = CANDLES[i][1] * (0.85 + 0.15 * sin(t * 11.0 + i * 2.0) * sin(t * 5.3 + i))


func _physics_process(delta: float) -> void:
	if not multiplayer.is_server():
		return
	_report_footsteps(delta)
	if not _awake and _ingredient_taken():
		_wake()
	# The rotten floor.
	if not _floor_gone:
		var on_it := 0
		for p in _alive_players():
			if MIDDLE.has_point(_l(p.global_position)):
				on_it += 1
		_creak_cd -= delta
		if on_it > 2:
			_set_floor.rpc(false)
			for p in _alive_players():
				if MIDDLE.grow(1.0).has_point(_l(p.global_position)):
					Team.tell(p.peer_id, "CRACK! The crypt floor gives way.")
		elif on_it == 2 and _creak_cd <= 0.0:
			_creak_cd = 12.0
			Sfx.play_all("branch_snap", _g(Vector3(0, KF, -1)))
			for p in _alive_players():
				if MIDDLE.has_point(_l(p.global_position)):
					Team.tell(p.peer_id, "The floor creaks under you two. Don't bring a third.")
	# Candles go out by themselves; at night the organ plays itself.
	_candle_timer -= delta
	if _candle_timer <= 0.0:
		_candle_timer = _rng.randf_range(20.0, 45.0)
		var lit := []
		for i in _candles.size():
			if _candles[i].visible:
				lit.append(i)
		if not lit.is_empty():
			_set_candle.rpc(lit[_rng.randi() % lit.size()], false)
	_organ_timer -= delta
	if _organ_timer <= 0.0:
		_organ_timer = _rng.randf_range(70.0, 140.0)
		if night or _awake:
			Sfx.play_all("organ", _g(Vector3(3.5, CF + 2.0, -4.6)))


## Host: a Bone morel left the coffin.
func _wake() -> void:
	_awake = true
	for s in _skeletons:
		s.wake()
	for i in _candles.size():
		_set_candle.rpc(i, false)
	Sfx.play_all("organ", _g(Vector3(3.5, CF + 2.0, -4.6)))
	Sfx.play_all("hag_whisper", _g(Vector3(0, KF + 1.5, 0)))
	for p in _players_in(_quiet_zones):
		Team.tell(p.peer_id, "Bones rattle in the niches. Whatever you do, don't look away.")


## Every peer: the middle of the crypt floor is there / gone.
@rpc("authority", "call_local", "reliable")
func _set_floor(present: bool) -> void:
	if not present and not _floor_gone:
		Sfx.play("cave_in", _g(Vector3(0, KF, -1)))
		_dust(Vector3(0, KF, -1), 50, Color(0.4, 0.36, 0.3))
	_floor_gone = not present
	_set_body(_floor, present)
	for id in _pit_ids:
		_graph.set_point_disabled(id, present)


## Every peer: a candle goes out / is lit.
@rpc("authority", "call_local", "reliable")
func _set_candle(i: int, lit: bool) -> void:
	if _candles[i].visible and not lit:
		Sfx.play("hag_breath", _g(CANDLES[i][0]))
	_candles[i].visible = lit
	_flames[i].visible = lit


func _use_candle(peer: int, i: int) -> void:
	if _candles[i].visible:
		Team.tell(peer, "It's lit. For now.")
		return
	_set_candle.rpc(i, true)


func _use_organ(peer: int) -> void:
	Sfx.play_all("organ", _g(Vector3(3.5, CF + 2.0, -4.6)))
	Hearing.emit(_g(Vector3(3.5, CF + 2.0, -4.6)), 70.0, peer)
	Team.tell(peer, ["Toccata and fugue in D minor. Badly.", "The organ wheezes like a dying cow.",
		"Something in the crypt below taps along."][_rng.randi() % 3])


# --- building -----------------------------------------------------------------------------------


func _build_podium() -> void:
	var s: Material = _m["stone"]
	# Solid podium walls up to the chapel floor, with the steps in front.
	_wall_run(true, 4.8, -5.0, 5.0, 0.0, CF, [], s, s, CF, 0.4)
	_wall_run(true, -8.8, -5.0, 5.0, 0.0, CF, [], s, s, CF, 0.4)
	_wall_run(false, 4.8, -8.6, 4.6, 0.0, CF, [], s, s, CF, 0.4)
	_wall_run(false, -4.8, -8.6, 4.6, 0.0, CF, [], s, s, CF, 0.4)
	_slab(Vector3(-2.2, 0.0, 5.0), Vector3(2.2, CF, 6.0), s)
	var top := Vector3(0, CF, 6.0)
	var bottom := Vector3(0, PF, 12.5)
	_ramp(top, bottom, 3.0)
	_steps(top, bottom, 3.0, 16, _m["dark_stone"], 0.0)
	for x in [-1.7, 1.7]:
		_ramp(Vector3(x, CF + 0.8, 6.0), Vector3(x, 0.8, 12.5), 0.3, s)
	_slab(Vector3(-2.2, CF - 0.05, 5.0), Vector3(2.2, CF, 6.0), _m["floor"])
	# Crypt floor (with a hole where the rotten middle is), crypt ceiling = chapel floor.
	var f: Material = _m["floor"]
	_slab(Vector3(-4.6, KF - 0.3, -8.6), Vector3(4.6, KF, MIDDLE.position.z), f)
	_slab(Vector3(-4.6, KF - 0.3, MIDDLE.end.z), Vector3(4.6, KF, 4.6), f)
	_slab(Vector3(-4.6, KF - 0.3, MIDDLE.position.z), Vector3(-2.0, KF, MIDDLE.end.z), f)
	_slab(Vector3(2.0, KF - 0.3, MIDDLE.position.z), Vector3(4.6, KF, MIDDLE.end.z), f)
	_floor = _body("RottenFloor", Vector3(4.0, 0.3, 6.0), Vector3(0, KF - 0.15, -1.0), _paint(Color(0.33, 0.28, 0.24)))
	# Chapel floor with the stair hole (x -4.6..-3.2, z -6.5..-2).
	_slab(Vector3(-3.2, KC, -8.6), Vector3(4.6, CF, 4.6), f)
	_slab(Vector3(-4.6, KC, -8.6), Vector3(-3.2, CF, -6.5), f)
	_slab(Vector3(-4.6, KC, -2.0), Vector3(-3.2, CF, 4.6), f)


func _build_chapel() -> void:
	var p: Material = _m["plaster"]
	var s: Material = _m["stone"]
	var door := [-1.0, 1.0, CF, CF + 2.8]
	_wall_run(true, 4.8, -5.0, 5.0, CF, WT, [door], s, p, CF + 0.6, 0.4)
	_wall_run(true, -8.8, -5.0, 5.0, CF, WT, [], s, p, CF + 0.6, 0.4)
	_wall_run(false, 4.8, -8.6, 4.6, CF, WT, [], s, p, CF + 0.6, 0.4)
	_wall_run(false, -4.8, -8.6, 4.6, CF, WT, [], s, p, CF + 0.6, 0.4)
	_slab(Vector3(-4.6, WT - 0.2, -8.6), Vector3(4.6, WT, 4.6), _m["wood"])
	# Gable roof and the front gable, a little bell-cote and a cross.
	var pitch := 0.62
	for side in [-1.0, 1.0]:
		var rot := Basis(Vector3.BACK, -side * pitch)
		_block(Vector3(6.4, 0.3, 14.6), Transform3D(rot, Vector3(side * 2.55, WT + 1.7, -2.0)), _m["roof"])
	for z in [4.85, -8.85]:
		for i in 6:
			var w := 9.8 * (1.0 - float(i) / 6.0)
			_slab(Vector3(-w / 2.0, WT + i * 0.6, z - 0.2), Vector3(w / 2.0, WT + i * 0.6 + 0.6, z + 0.2), p)
	_slab(Vector3(-0.6, WT + 3.4, 3.6), Vector3(0.6, WT + 5.0, 4.8), p)
	_slab(Vector3(-0.8, WT + 5.0, 3.4), Vector3(0.8, WT + 5.3, 5.0), _m["roof"])
	_slab(Vector3(-0.06, WT + 5.3, 4.14), Vector3(0.06, WT + 6.5, 4.26), _m["metal"], false)
	_slab(Vector3(-0.35, WT + 6.0, 4.14), Vector3(0.35, WT + 6.12, 4.26), _m["metal"], false)
	# Stained glass slits on both long walls (they glow faintly from candlelight within).
	var glass := [_paint(Color(0.6, 0.15, 0.12), false, 0.5), _paint(Color(0.15, 0.25, 0.6), false, 0.5),
		_paint(Color(0.6, 0.5, 0.12), false, 0.5)]
	for i in 3:
		var z := -6.0 + i * 3.6
		for side in [1.0, -1.0]:
			var outer: float = side * 5.02
			var inner: float = side * 4.58
			_slab(Vector3(outer - 0.02, CF + 1.6, z - 0.35), Vector3(outer + 0.02, CF + 3.8, z + 0.35), glass[i], false)
			_slab(Vector3(inner - 0.02, CF + 1.7, z - 0.3), Vector3(inner + 0.02, CF + 3.7, z + 0.3), glass[i], false)
	# Door leaves standing open, signs.
	for side in [-1.0, 1.0]:
		var leaf := Transform3D(Basis(Vector3.UP, side * 1.9), Vector3(side * 1.0, CF + 1.4, 4.75))
		_block(Vector3(0.08, 2.8, 1.0), leaf.translated_local(Vector3(0, 0, 0.5)), _m["wood"], false)
	_board("KAPLNKA SV. URBANA\npatróna vinárov\nkrypta - vstup zakázaný", Vector3(2.9, CF + 2.0, 5.04), 0.0,
		Vector2(2.2, 1.1), Color(0.3, 0.22, 0.14), Color(0.9, 0.85, 0.7), 30)
	_label("PAX", Vector3(0, CF + 3.3, 5.03), 0.0, 90, Color(0.3, 0.28, 0.25), true)
	# Pews, the altar, a crucifix.
	for row in 4:
		for x in [-2.4, 2.4]:
			var path := GRAVE_X + ("bench-damaged.glb" if (row + int(x)) % 3 == 0 else "bench.glb")
			_solid(path, Vector3(2.2, 0.9, 0.6), Vector3(x, CF, -0.5 + row * 1.4), PI)
	_slab(Vector3(-2.5, CF, -8.6), Vector3(2.5, CF + 0.12, -6.6), _m["dark_stone"], false)
	_solid(GRAVE_X + "altar-wood.glb", Vector3(2.4, 1.1, 0.9), Vector3(0, CF + 0.12, -7.6), 0.0)
	_model(GRAVE_X + "cross-wood.glb", Vector3(1.0, 1.8, 0.2), Vector3(0, CF + 3.0, -8.5), 0.0)
	for x in [-0.7, 0.7]:
		_model(GRAVE + "candle-multiple.glb", Vector3(0.35, 0.3, 0.35), Vector3(x, CF + 1.12, -7.6), x)
	# Railing round the stair hole, and a sign.
	_slab(Vector3(-3.24, CF, -6.5), Vector3(-3.14, CF + 1.0, -2.0), _m["wood"])
	_slab(Vector3(-4.6, CF, -6.6), Vector3(-3.14, CF + 1.0, -6.5), _m["wood"])
	_label("KRYPTA ↓", Vector3(-4.55, CF + 1.9, -3.0), PI / 2.0, 44, Color(0.75, 0.7, 0.6), true)


func _build_crypt() -> void:
	var s: Material = _m["dark_stone"]
	# Stairs down from behind the pews (along the west wall), and the wall that boxes them in.
	var top := Vector3(-3.9, CF, -2.0)
	var bottom := Vector3(-3.9, KF, -6.5)
	_ramp(top, bottom, 1.4)
	_steps(top, bottom, 1.4, 12, s, KF)
	_slab(Vector3(-3.2, KF, -6.5), Vector3(-3.0, KC, -1.8), s)
	_slab(Vector3(-4.6, KF, -2.0), Vector3(-3.0, KC, -1.8), s)
	# Vaulted look: ribs across the ceiling, pillars.
	for i in 5:
		var z := -7.6 + i * 2.8
		_slab(Vector3(-4.6, KC - 0.3, z - 0.15), Vector3(4.6, KC, z + 0.15), _m["stone"], false)
	for p in [Vector3(-2.6, KF, -5.0), Vector3(2.6, KF, -5.0), Vector3(2.6, KF, 2.6), Vector3(-2.6, KF, 2.6)]:
		_slab(p - Vector3(0.25, 0, 0.25), p + Vector3(0.25, KC - KF, 0.25), _m["stone"])
	# The saint's coffin on its tomb, with a candle.
	_slab(Vector3(-1.2, KF, 2.5), Vector3(1.2, KF + 0.6, 4.5), _m["stone"])
	_model(GRAVE_X + "coffin-old.glb", Vector3(0.9, 0.45, 2.0), Vector3(0, KF + 0.6, 3.5), 0.0)
	_model(GRAVE_X + "candle.glb", Vector3(0.15, 0.3, 0.15), Vector3(0.0, KF + 1.0, 3.1), 0.0)
	_label("S. VRBANVS\n† MCCCXLVII", Vector3(0, KF + 0.3, 2.48), PI, 30, Color(0.7, 0.66, 0.55), true)
	_label("Neber, čo nie je tvoje.", Vector3(0, KC - 0.5, 4.55), PI, 30, Color(0.6, 0.55, 0.45), true)
	# Niches with arches, and the ossuary shelves.
	for n in _niches():
		var pos: Vector3 = n[0]
		var b := Basis(Vector3.UP, n[1])
		var back := pos - b * Vector3(0, 0, 0.5)
		_block(Vector3(1.4, 0.3, 0.5), Transform3D(b, back + Vector3(0, 2.15, 0)), _m["stone"], false)
		for side in [-0.75, 0.75]:
			_block(Vector3(0.2, 2.2, 0.5), Transform3D(b, back + b * Vector3(side, 1.1, 0)), _m["stone"])
	for z in [-7.5, 3.2]:
		for shelf in 3:
			var y := KF + 0.4 + shelf * 0.6
			_slab(Vector3(4.2, y, z - 0.9), Vector3(4.6, y + 0.05, z + 0.9), _m["wood"], false)
			for k in 5:
				var skull := Vector3(4.35, y + 0.13, z - 0.7 + k * 0.35)
				_block(Vector3(0.2, 0.2, 0.22), Transform3D(Basis(Vector3.UP, _rng.randf()), skull), _m["bone"], false)
	_model(GRAVE_X + "urn-round.glb", Vector3(0.4, 0.6, 0.4), Vector3(-4.1, KF, 0.5), 0.0)
	_model(GRAVE_X + "urn-round.glb", Vector3(0.4, 0.6, 0.4), Vector3(-4.1, KF, 1.3), 0.5)
	_model(GRAVE_X + "debris.glb", Vector3(1.2, 0.3, 1.2), Vector3(3.4, KF, -7.6), 0.3)
	# Cracks on the rotten middle so a careful eye can see it.
	for i in 7:
		var p := Vector3(_rng.randf_range(-1.6, 1.6), KF + 0.005, _rng.randf_range(-3.6, 1.6))
		_block(Vector3(_rng.randf_range(0.6, 1.4), 0.01, 0.04), Transform3D(Basis(Vector3.UP, _rng.randf() * TAU), p),
			_paint(Color(0.05, 0.04, 0.03), false), false)


## [position (feet), yaw facing into the crypt]
func _niches() -> Array:
	return [
		[Vector3(4.0, KF, -5.6), -PI / 2.0],
		[Vector3(4.0, KF, -1.0), -PI / 2.0],
		[Vector3(-4.0, KF, 3.2), PI / 2.0],
	]


func _build_pit() -> void:
	var s: Material = _m["dark_stone"]
	_slab(Vector3(-2.2, PF - 0.2, -4.2), Vector3(2.2, PF, 2.2), _m["earth"])
	_slab(Vector3(-2.2, PF, -4.2), Vector3(-2.0, KF - 0.3, 2.2), s)
	_slab(Vector3(2.0, PF, -4.2), Vector3(2.2, KF - 0.3, 2.2), s)
	_slab(Vector3(-2.0, PF, 2.0), Vector3(2.0, KF - 0.3, 2.2), s)
	_slab(Vector3(-2.0, PF, -4.2), Vector3(2.0, KF - 0.3, -4.0), s)
	# A ramp of bones and rubble back up to the back of the crypt.
	_ramp(Vector3(-1.35, KF, -4.0), Vector3(-1.35, PF, 1.6), 1.2, _m["earth"])
	for i in 40:
		var p := Vector3(_rng.randf_range(-1.9, 1.9), PF + 0.05, _rng.randf_range(-3.9, 1.9))
		var size := Vector3(_rng.randf_range(0.05, 0.12), 0.05, _rng.randf_range(0.25, 0.5))
		_block(size, Transform3D(Basis(Vector3.UP, _rng.randf() * TAU), p), _m["bone"], false)
	_model(GRAVE_X + "character-skeleton.glb", Vector3(3.0, 1.6, 3.0), Vector3(1.0, PF, 0.5), 0.8).rotation.x = -1.4
	_label("OSSUARIUM", Vector3(0, KF - 0.7, 1.98), PI, 30, Color(0.55, 0.5, 0.42), true)


func _build_organ() -> void:
	var w: Material = _m["wood"]
	_slab(Vector3(2.7, CF, -6.2), Vector3(4.6, CF + 1.0, -3.4), w)
	_slab(Vector3(2.9, CF + 1.0, -6.0), Vector3(3.3, CF + 1.3, -3.6), _m["bone"], false)
	_slab(Vector3(4.1, CF + 1.0, -6.2), Vector3(4.6, CF + 2.2, -3.4), w)
	for i in 9:
		var h := 2.0 + (4 - absi(i - 4)) * 0.55
		var pipe := MeshInstance3D.new()
		var mesh := CylinderMesh.new()
		mesh.top_radius = 0.1
		mesh.bottom_radius = 0.1
		mesh.height = h
		mesh.radial_segments = 8
		mesh.rings = 1
		pipe.mesh = mesh
		pipe.material_override = _m["metal"]
		pipe.position = Vector3(4.35, CF + 2.2 + h / 2.0, -6.0 + i * 0.3)
		_root.add_child(pipe)
	_interactable("Organ", Vector3(2.1, 1.4, 2.9), Vector3(3.6, CF + 0.7, -4.8), "play the organ", _use_organ)


func _build_candles() -> void:
	for i in CANDLES.size():
		var pos: Vector3 = CANDLES[i][0]
		var light := _lamp(pos + Vector3(0, 0.15, 0), Color(1.0, 0.65, 0.3), CANDLES[i][1], 6.0)
		_candles.append(light)
		var flame := MeshInstance3D.new()
		var mesh := SphereMesh.new()
		mesh.radius = 0.04
		mesh.height = 0.12
		flame.mesh = mesh
		flame.material_override = _m["flame"]
		flame.position = pos
		_root.add_child(flame)
		_flames.append(flame)
		_interactable("Candle%d" % i, Vector3(0.35, 0.5, 0.35), pos - Vector3(0, 0.15, 0), "light the candle",
			_use_candle.bind(i))
	_model(GRAVE_X + "candle.glb", Vector3(0.2, 0.4, 0.2), CANDLES[2][0] - Vector3(0, 0.4, 0), 0.0)
	_slab(Vector3(3.3, CF, -3.0), Vector3(3.5, CF + 1.0, -2.8), _m["metal"])


func _build_yard() -> void:
	# A few graves round the chapel, crooked crosses, a dead tree, a fence.
	for i in 12:
		var a := -0.9 + i * 0.42
		var r := _rng.randf_range(9.0, 13.0)
		var p := Vector3(cos(a + PI) * r, 0, sin(a + PI) * r - 2.0)
		if p.z > 4.0 and absf(p.x) < 3.5:
			continue
		var path: String = [GRAVE + "gravestone-cross.glb", GRAVE + "gravestone-round.glb",
			GRAVE_X + "gravestone-broken.glb",
			GRAVE_X + "cross-wood.glb"][i % 4]
		_solid(path, Vector3(0.8, 1.1, 0.3), p, _rng.randf_range(-0.3, 0.3) + a)
	for p in [Vector3(-9, 0, 6), Vector3(9.5, 0, -8)]:
		var tree := _solid(GRAVE + "pine-crooked.glb", Vector3(3.0, 7.0, 3.0), p, p.x)
		_tint(tree, Color(0.18, 0.15, 0.13))
	_model(GRAVE_X + "lightpost-single.glb", Vector3(0.6, 3.0, 0.6), Vector3(2.6, 0, 13.5), 0.0)


func _build_skeletons() -> void:
	_graph = AStar3D.new()
	var ids := {}
	var add := func(key: String, p: Vector3) -> void:
		var id := _graph.get_available_point_id()
		_graph.add_point(id, p)
		ids[key] = id
	var link := func(a: String, b: String) -> void:
		_graph.connect_points(ids[a], ids[b])
	# Crypt: back strip, east side, by the coffin, west front corner; the pit (only once it's open).
	add.call("kb_w", Vector3(-3.8, KF, -7.4))
	add.call("kb_c", Vector3(0.0, KF, -7.0))
	add.call("kb_e", Vector3(3.3, KF, -7.0))
	add.call("ke_1", Vector3(3.3, KF, -3.0))
	add.call("ke_2", Vector3(3.3, KF, 1.0))
	add.call("kf_e", Vector3(2.2, KF, 3.6))
	add.call("kf_c", Vector3(0.0, KF, 2.2))
	add.call("kf_w", Vector3(-2.2, KF, 3.6))
	add.call("kw", Vector3(-2.5, KF, 0.2))
	add.call("n0", Vector3(4.0, KF, -5.6))
	add.call("n1", Vector3(4.0, KF, -1.0))
	add.call("n2", Vector3(-4.0, KF, 3.2))
	for pair in [["kb_w", "kb_c"], ["kb_c", "kb_e"], ["kb_e", "ke_1"], ["ke_1", "ke_2"], ["ke_2", "kf_e"],
			["kf_e", "kf_c"], ["kf_c", "kf_w"], ["kf_w", "kw"], ["n0", "ke_1"], ["n0", "kb_e"], ["n1", "ke_1"],
			["n1", "ke_2"], ["n2", "kf_w"], ["n2", "kw"]]:
		link.call(pair[0], pair[1])
	add.call("pit_top", Vector3(-1.35, KF, -4.3))
	add.call("pit_low", Vector3(-1.35, PF, 1.4))
	add.call("pit_mid", Vector3(0.5, PF, -1.0))
	link.call("pit_top", "kb_c")
	link.call("pit_top", "pit_low")
	link.call("pit_low", "pit_mid")
	for k in ["pit_top", "pit_low", "pit_mid"]:
		_pit_ids.append(ids[k])
		_graph.set_point_disabled(ids[k], true)
	# Up the stairs, through the chapel, out of the door and down the steps.
	add.call("st_low", Vector3(-3.9, KF, -6.9))
	add.call("st_top", Vector3(-3.9, CF, -1.5))
	link.call("st_low", "kb_w")
	link.call("st_low", "st_top")
	add.call("c_w", Vector3(-3.9, CF, 3.5))
	add.call("c_back", Vector3(0.0, CF, -5.5))
	add.call("c_mid", Vector3(0.0, CF, -1.5))
	add.call("c_front", Vector3(0.0, CF, 3.6))
	add.call("door", Vector3(0.0, CF, 5.5))
	add.call("steps", Vector3(0.0, PF, 13.0))
	for pair in [["st_top", "c_mid"], ["st_top", "c_w"], ["c_w", "c_front"], ["c_back", "c_mid"],
			["c_mid", "c_front"], ["c_front", "door"], ["door", "steps"]]:
		link.call(pair[0], pair[1])
	var yard := [Vector3(-7, PF, 9), Vector3(7, PF, 9), Vector3(-8, PF, -2), Vector3(8, PF, -2), Vector3(0, PF, -12)]
	for i in yard.size():
		add.call("y%d" % i, yard[i])
	for pair in [["steps", "y0"], ["steps", "y1"], ["y0", "y2"], ["y1", "y3"], ["y2", "y4"], ["y3", "y4"]]:
		link.call(pair[0], pair[1])
	var niches := _niches()
	for i in niches.size():
		var s := SkeletonScript.new()
		s.graph = _graph
		_root.add_child(s)
		s.build("Skeleton%d" % i, GRAVE_X + "character-skeleton.glb", niches[i][0], niches[i][1])
		_skeletons.append(s)
