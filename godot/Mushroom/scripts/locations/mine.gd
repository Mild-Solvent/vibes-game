extends "res://scripts/locations/location.gd"
## Banská štôlňa Hodruša: an old silver mine in a rocky knoll. A straight adit with a mine cart
## (pull the lever, ride it to the hall), a shaft with a ladder up to the upper gallery, a narrow
## squeeze, and the grotto where the Kobold caps glow.
##
## Dangers: anything loud (>30: shouting, whistles, flares) brings the roof down near it - the
## rubble splits the group until somebody digs through it (E, several times). The marked gas
## pocket by the entrance blows up if a flare (>=100) goes off in it. And the Miner, a ghost,
## drifts through the rock to whoever has a lamp lit and pinches it out.
##
## Build frame: the portal faces +Z; the mine goes into the knoll towards -Z. Tunnels are carved
## out of a 1 m voxel grid (cell (x, y, z) spans x-0.5..x+0.5, y..y+1, z-0.5..z+0.5) and only
## the rock touching a tunnel is built. Everything stays within ~19 m of the place centre: the
## forest is only cleared that far round a place.

const CartScript := preload("res://scripts/locations/mine_cart.gd")
const GhostScript := preload("res://scripts/locations/miner_ghost.gd")
const INGREDIENT := "kobold_cap"
const FRONT_YAW := PI / 2.0  # the road comes in from global +X
const YOFF := 0.03  # tunnel floors sit just above the flat ground (no z-fighting with it)
const CELLS_X := Vector2i(-13, 14)
const CELLS_Y := Vector2i(-1, 9)
const CELLS_Z := Vector2i(-18, -2)
const CAVE_IN_LOUD := 30.0
const GAS_LOUD := 100.0
const GAS_CENTRE := Vector3(-7.5, 1.0, -3.5)
const GAS_RADIUS := 8.0
const DIG_HITS := 6
## Rubble that comes down in a cave-in: [centre (floor), size]
const RUBBLE := [
	[Vector3(0, 0, -11.5), Vector3(3.0, 3.0, 1.2)],
	[Vector3(-5.0, 0, -8.0), Vector3(1.2, 3.0, 3.0)],
	[Vector3(1.0, 6.0, -14.0), Vector3(1.2, 3.0, 3.0)],
	[Vector3(-3.0, 0, -3.5), Vector3(1.2, 3.0, 2.0)],
	[Vector3(0, 0, -6.0), Vector3(3.0, 3.0, 1.2)],
]

var _empty := {}  # Vector3i -> true: carved cells
var _rubble: Array[StaticBody3D] = []
var _rubble_hits: Array[int] = []
var _rubble_cool: Array[float] = []
var _last_heard := 0.0
var _gas_gone := false
var _gas_haze: Array[MeshInstance3D] = []
var _cart: AnimatableBody3D
var _ghost: Node3D
var _portal_light: OmniLight3D
var _check := 0.0
var _rng := RandomNumberGenerator.new()
var _m := {}


func build() -> void:
	_begin(FRONT_YAW)
	_rng.seed = 1908
	_m = {
		"rock": _paint(Color(0.34, 0.31, 0.28)),
		"floor": _paint(Color(0.27, 0.22, 0.17)),
		"mountain": _paint(Color(0.33, 0.31, 0.28)),
		"wood": _paint(Color(0.36, 0.24, 0.14)),
		"rust": _paint(Color(0.4, 0.21, 0.11)),
		"metal": _paint(Color(0.32, 0.33, 0.34)),
		"dark": _paint(Color(0.05, 0.05, 0.05), false),
		"crystal": _paint(Color(0.55, 1.0, 0.45), false, 4.0),
		"gas": _paint(Color(0.55, 0.75, 0.3), false, 0.0, 0.07),
		"warn": _paint(Color(0.85, 0.7, 0.1)),
	}
	_carve_tunnels()
	_build_rock()
	_build_mountain()
	_build_portal()
	_build_timbering()
	_build_ladders()
	_build_grotto()
	_build_gas()
	_build_rubble()
	_build_cart()
	_build_lights()
	_ghost = GhostScript.new()
	_ghost.location = self
	_ghost.bounds = AABB(Vector3(-13, -0.5, -18), Vector3(27, 10.5, 17))
	_root.add_child(_ghost)
	_ghost.build(CHARS + "character-male-d.glb", Vector3(-10, YOFF, -9), 1908)
	for i in 3:
		var spot: Vector3 = [Vector3(10.6, YOFF, -9.6), Vector3(11.4, YOFF, -8.8), Vector3(10.0, YOFF, -8.3)][i]
		_ingredient("KoboldCap%d" % i, INGREDIENT, spot, i * 1.7)
	_interior(AABB(Vector3(-13.5, -1.0, -18.5), Vector3(28, 11.5, 16.6)), Color(0.03, 0.03, 0.035))
	_quiet_zones.append(AABB(Vector3(-13.5, -1.0, -18.5), Vector3(28, 11.5, 16.6)))
	_check_terrain()
	_finish()


# --- contract ------------------------------------------------------------------------------


func server_reset() -> void:
	_reset_ingredients()
	if _cart:
		_cart.reset()
	if _ghost:
		_ghost.reset()
	for i in _rubble.size():
		_rubble_cool[i] = 5.0
		_set_rubble.rpc(i, false, 0)
	_set_gas.rpc(true)


func set_night(is_night: bool) -> void:
	night = is_night
	if _portal_light:
		_portal_light.visible = is_night


func entrance_position() -> Vector3:
	return _g(Vector3(0, 0, 11.0))


# --- running ---------------------------------------------------------------------------------


func _process(_delta: float) -> void:
	_update_flicker()
	var t := Time.get_ticks_msec() / 1000.0
	for i in _gas_haze.size():
		_gas_haze[i].position.y = 0.9 + i * 0.35 + sin(t * 0.6 + i) * 0.12


func _physics_process(delta: float) -> void:
	if not multiplayer.is_server():
		return
	_report_footsteps(delta)
	for i in _rubble_cool.size():
		_rubble_cool[i] -= delta
	_check -= delta
	if _check > 0.0:
		return
	_check = 0.2
	if not _gas_gone:
		var boom := Hearing.loudest_heard(_g(GAS_CENTRE), 7.0)
		if not boom.is_empty() and boom["loud"] >= GAS_LOUD and boom["time"] > _last_heard:
			_last_heard = boom["time"]
			_explode()
			return
	for i in RUBBLE.size():
		if _rubble[i].visible or _rubble_cool[i] > 0.0:
			continue
		var heard := Hearing.loudest_heard(_g(RUBBLE[i][0] + Vector3(0, 1.5, 0)), 10.0)
		if heard.is_empty() or heard["loud"] <= CAVE_IN_LOUD or heard["time"] <= _last_heard:
			continue
		_last_heard = heard["time"]
		_set_rubble.rpc(i, true, 0)
		for p in _players_in(_quiet_zones):
			Team.tell(p.peer_id, "The roof comes down! Too loud. (Dig through the rubble: E)")
		break


## Host: the gas pocket goes up. Everyone near it dies; the tunnel mouth caves in.
func _explode() -> void:
	_set_gas.rpc(false)
	var space := get_world_3d().direct_space_state
	for p in _alive_players():
		var chest: Vector3 = p.global_position + Vector3(0, 1.0, 0)
		if chest.distance_to(_g(GAS_CENTRE)) > GAS_RADIUS:
			continue
		var ray := PhysicsRayQueryParameters3D.create(_g(GAS_CENTRE), chest)
		ray.exclude = [p.get_rid()]
		if space.intersect_ray(ray).is_empty():  # the blast doesn't go through rock
			Team.kill(p.peer_id, "lighting a flare in a gas pocket. Bold.")
	_set_rubble.rpc(3, true, 0)
	Hearing.emit(_g(GAS_CENTRE), 150.0, 0)


## Every peer: rubble `i` comes down / is dug at / is gone.
@rpc("authority", "call_local", "reliable")
func _set_rubble(i: int, on: bool, hits: int) -> void:
	var was := _rubble[i].visible
	_rubble_hits[i] = hits
	_set_body(_rubble[i], on)
	_rubble[i].set("prompt", "dig through the rubble (%d/%d)" % [hits, DIG_HITS])
	var pile := _rubble[i].get_node("Pile") as Node3D
	pile.scale = Vector3(1, 1.0 - 0.1 * hits, 1)
	if on and not was:
		Sfx.play("cave_in", _g(RUBBLE[i][0]))
		_dust(RUBBLE[i][0] + Vector3(0, 2.0, 0), 60)
	elif not on and was:
		Sfx.play("rock_hit", _g(RUBBLE[i][0]))
		_dust(RUBBLE[i][0] + Vector3(0, 0.5, 0), 25)


## Every peer: the gas is there (new day) or gone (it blew up).
@rpc("authority", "call_local", "reliable")
func _set_gas(present: bool) -> void:
	if not present and not _gas_gone:
		Sfx.play("explosion", _g(GAS_CENTRE))
		var flash := _lamp(GAS_CENTRE + Vector3(0, 1, 0), Color(1.0, 0.55, 0.2), 8.0, 16.0)
		get_tree().create_timer(0.35).timeout.connect(flash.queue_free)
		_dust(GAS_CENTRE, 90, Color(0.2, 0.18, 0.15))
	_gas_gone = not present
	for haze in _gas_haze:
		haze.visible = present


func _dig(peer: int, i: int) -> void:
	if not _rubble[i].visible:
		return
	var hits := _rubble_hits[i] + 1
	Sfx.play_all("rock_hit", _g(RUBBLE[i][0]))
	Hearing.emit(_g(RUBBLE[i][0]), 12.0, peer)
	if hits >= DIG_HITS:
		_rubble_cool[i] = 20.0
		_set_rubble.rpc(i, false, 0)
		Team.tell(peer, "You're through!")
	else:
		_set_rubble.rpc(i, true, hits)


func _use_lever(peer: int) -> void:
	Team.tell(peer, _cart.send())
	Sfx.play_all("metal_hit", _cart.global_position)


func _rails_blocked() -> bool:
	return _rubble[0].visible or _rubble[4].visible


# --- building: carving the rock --------------------------------------------------------------


## Marks cells (inclusive index ranges) as tunnel.
func _carve(x: Vector2i, y: Vector2i, z: Vector2i) -> void:
	for ix in range(x.x, x.y + 1):
		for iy in range(y.x, y.y + 1):
			for iz in range(z.x, z.y + 1):
				_empty[Vector3i(ix, iy, iz)] = true


func _carve_tunnels() -> void:
	_carve(Vector2i(-1, 1), Vector2i(0, 2), Vector2i(-14, -2))  # the adit
	_carve(Vector2i(-3, 3), Vector2i(0, 3), Vector2i(-17, -15))  # the hall at its end
	_carve(Vector2i(-7, -2), Vector2i(0, 2), Vector2i(-9, -7))  # branch to the shaft
	_carve(Vector2i(-12, -8), Vector2i(0, 8), Vector2i(-14, -6))  # the shaft
	_carve(Vector2i(-7, 9), Vector2i(6, 8), Vector2i(-15, -13))  # upper gallery
	_carve(Vector2i(6, 13), Vector2i(0, 8), Vector2i(-12, -4))  # the grotto
	_carve(Vector2i(-10, -2), Vector2i(0, 2), Vector2i(-4, -3))  # gas pocket
	# The squeeze: one cell wide, two high, three bends.
	_carve(Vector2i(4, 6), Vector2i(0, 1), Vector2i(-16, -16))
	_carve(Vector2i(6, 6), Vector2i(0, 1), Vector2i(-16, -14))
	_carve(Vector2i(6, 8), Vector2i(0, 1), Vector2i(-14, -14))
	_carve(Vector2i(8, 8), Vector2i(0, 1), Vector2i(-14, -13))


func _is_rock(c: Vector3i) -> bool:
	if c.x < CELLS_X.x or c.x > CELLS_X.y or c.y < CELLS_Y.x or c.y > CELLS_Y.y:
		return false
	if c.z < CELLS_Z.x or c.z > CELLS_Z.y:
		return false
	return not _empty.has(c)


## Builds every rock cell that touches a tunnel, merged into rectangles layer by layer.
func _build_rock() -> void:
	var dirs := [Vector3i.LEFT, Vector3i.RIGHT, Vector3i.UP, Vector3i.DOWN, Vector3i.FORWARD, Vector3i.BACK]
	for iy in range(CELLS_Y.x, CELLS_Y.y + 1):
		var walls := {}
		var floors := {}
		for ix in range(CELLS_X.x, CELLS_X.y + 1):
			for iz in range(CELLS_Z.x, CELLS_Z.y + 1):
				var c := Vector3i(ix, iy, iz)
				if not _is_rock(c):
					continue
				if _empty.has(c + Vector3i.UP):
					floors[Vector2i(ix, iz)] = true
					continue
				for d in dirs:
					if _empty.has(c + d):
						walls[Vector2i(ix, iz)] = true
						break
		_merge_layer(walls, iy, _m["rock"])
		_merge_layer(floors, iy, _m["floor"])


## Greedy rectangles over one layer of cells.
func _merge_layer(cells: Dictionary, iy: int, mat: Material) -> void:
	var done := {}
	var keys := cells.keys()
	keys.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.y < b.y or (a.y == b.y and a.x < b.x))
	for k in keys:
		if done.has(k):
			continue
		var x1: int = k.x
		while cells.has(Vector2i(x1 + 1, k.y)) and not done.has(Vector2i(x1 + 1, k.y)):
			x1 += 1
		var z1: int = k.y
		var grow := true
		while grow:
			for x in range(k.x, x1 + 1):
				var n := Vector2i(x, z1 + 1)
				if not cells.has(n) or done.has(n):
					grow = false
					break
			if grow:
				z1 += 1
		for x in range(k.x, x1 + 1):
			for z in range(k.y, z1 + 1):
				done[Vector2i(x, z)] = true
		_slab(Vector3(k.x - 0.5, iy + YOFF, k.y - 0.5), Vector3(x1 + 0.5, iy + 1 + YOFF, z1 + 0.5), mat)


## The knoll round the tunnels: a hollow shell of big rock slabs (the gap between it and the
## tunnels is never seen), with tilted boulders on top for a mountain-ish skyline.
func _build_mountain() -> void:
	var m: Material = _m["mountain"]
	var lo := -14.0
	_slab(Vector3(-18, lo, -21), Vector3(-13.5, 12, -1.5), m)
	_slab(Vector3(14.5, lo, -21), Vector3(19, 12, -1.5), m)
	_slab(Vector3(-18, lo, -22), Vector3(19, 12, -18.5), m)
	_slab(Vector3(-18, 10.03, -21), Vector3(19, 12, -1.5), m)
	_slab(Vector3(-18, lo, -2.5), Vector3(-1.5, 10.03, -1.5), m)
	_slab(Vector3(1.5, lo, -2.5), Vector3(19, 10.03, -1.5), m)
	_slab(Vector3(-1.5, 3.03, -2.5), Vector3(1.5, 10.03, -1.5), m)
	var boulders := [
		[Vector3(-8, 13, -11), Vector3(14, 6, 12), Vector3(0.2, 0.4, 0.1)],
		[Vector3(6, 14, -12), Vector3(13, 8, 11), Vector3(-0.15, -0.3, 0.2)],
		[Vector3(-1, 17, -14), Vector3(10, 7, 9), Vector3(0.3, 0.8, -0.2)],
		[Vector3(12, 11, -5), Vector3(8, 6, 7), Vector3(0.0, 0.5, 0.35)],
		[Vector3(-13, 11, -4), Vector3(8, 5, 7), Vector3(0.1, -0.4, -0.3)],
		[Vector3(-16, 4, -10), Vector3(5, 12, 14), Vector3(0.0, 0.2, -0.25)],
		[Vector3(17, 4, -11), Vector3(5, 12, 14), Vector3(0.0, -0.2, 0.25)],
		[Vector3(3, 18, -17), Vector3(7, 5, 6), Vector3(-0.4, 0.2, 0.0)],
	]
	for b in boulders:
		_block(b[1], Transform3D(Basis.from_euler(b[2]), b[0]), m)
	# A few stunted pines up top, and scree and rocks at the foot.
	for p in [Vector3(-14, 12, -6), Vector3(-6, 12, -3.5), Vector3(13, 12, -16), Vector3(16, 12, -3),
			Vector3(-15, 12, -17)]:
		_model(NATURE + "tree_pineSmallA.glb", Vector3(2.5, 4.0, 2.5), p, p.x)
	for i in 16:
		var x := _rng.randf_range(-16.0, 16.0)
		if absf(x) < 3.5:
			continue
		var s := _rng.randf_range(0.6, 1.8)
		var basis := Basis.from_euler(Vector3(_rng.randf() * 0.6, _rng.randf() * TAU, _rng.randf() * 0.6))
		_block(Vector3(s, s * 0.7, s), Transform3D(basis, Vector3(x, s * 0.2, _rng.randf_range(-1.2, 1.5))), m)


func _build_portal() -> void:
	var w: Material = _m["wood"]
	# Timber portal frame, a sign, the miners' greeting.
	_slab(Vector3(-1.9, 0, -1.6), Vector3(-1.5, 3.4, -1.2), w)
	_slab(Vector3(1.5, 0, -1.6), Vector3(1.9, 3.4, -1.2), w)
	_slab(Vector3(-2.2, 3.03, -1.6), Vector3(2.2, 3.5, -1.1), w)
	_board("BANSKÁ ŠTÔLŇA HODRUŠA\n1786", Vector3(0, 4.3, -1.35), 0.0, Vector2(4.2, 1.1),
		Color(0.32, 0.22, 0.13), Color(0.92, 0.85, 0.65), 52)
	_label("ZDAR BOH!", Vector3(0, 5.3, -1.4), 0.0, 64, Color(0.75, 0.68, 0.5), true)
	_label("⚒", Vector3(-3.0, 4.3, -1.4), 0.0, 120, Color(0.75, 0.68, 0.5), true)
	_label("⚒", Vector3(3.0, 4.3, -1.4), 0.0, 120, Color(0.75, 0.68, 0.5), true)
	_board("VSTUP ZAKÁZANÝ\nNebezpečenstvo závalu!\nNEKRIČTE V ŠTÔLNI", Vector3(3.4, 1.6, 0.3), -0.3,
		Vector2(1.6, 1.0), Color(0.85, 0.8, 0.65), Color(0.55, 0.06, 0.04), 30)
	# The yard: spoil heap, barrels, a crate, pickaxes, a lantern post.
	for i in 7:
		var p := Vector3(-9.0 + _rng.randf_range(-2.5, 2.5), 0, 6.0 + _rng.randf_range(-2.5, 2.5))
		var s := _rng.randf_range(1.0, 2.4)
		var basis := Basis.from_euler(Vector3(_rng.randf() * 0.5, _rng.randf() * TAU, _rng.randf() * 0.5))
		_block(Vector3(s, s * 0.6, s), Transform3D(basis, p), _m["floor"])
	_solid(SURVIVAL + "barrel.glb", Vector3(0.8, 1.1, 0.8), Vector3(4.5, 0, 3.0), 0.0)
	_solid(SURVIVAL + "barrel.glb", Vector3(0.8, 1.1, 0.8), Vector3(5.3, 0, 3.6), 0.4)
	_solid(SURVIVAL + "box-large.glb", Vector3(1.2, 1.0, 1.2), Vector3(5.0, 0, 5.5), 0.3)
	_model(SURVIVAL_X + "tool-pickaxe.glb", Vector3(0.4, 1.0, 0.2), Vector3(4.6, 0.95, 5.5), 1.2)
	_model(SURVIVAL_X + "tool-shovel.glb", Vector3(0.3, 1.2, 0.2), Vector3(-2.6, 0, -0.8), 0.2)
	_solid(SURVIVAL_X + "workbench-anvil.glb", Vector3(1.0, 0.8, 0.6), Vector3(-5.0, 0, 2.0), 0.6)
	_slab(Vector3(2.8, 0, 9.0), Vector3(3.0, 3.2, 9.2), _m["wood"])
	_model(GRAVE + "lantern-candle.glb", Vector3(0.4, 0.6, 0.4), Vector3(2.9, 3.2, 9.1), 0.0)
	_board("Šachta ŠTEFAN\nhĺbka 212 m\nposledná šichta 1908", Vector3(-4.0, 1.4, 9.0), 0.4,
		Vector2(1.4, 0.8), Color(0.32, 0.22, 0.13), Color(0.85, 0.8, 0.65), 28)
	_slab(Vector3(-4.05, 0, 8.95), Vector3(-3.95, 1.0, 9.05), _m["wood"])


## Wooden frames along the adit and the gallery, so it reads as a mine and not a corridor.
func _build_timbering() -> void:
	var w: Material = _m["wood"]
	for i in 5:
		var z := -3.5 - i * 2.6
		_slab(Vector3(-1.45, YOFF, z - 0.12), Vector3(-1.25, 2.9, z + 0.12), w)
		_slab(Vector3(1.25, YOFF, z - 0.12), Vector3(1.45, 2.9, z + 0.12), w)
		_slab(Vector3(-1.5, 2.75, z - 0.14), Vector3(1.5, 3.0, z + 0.14), w, false)
	for i in 6:
		var x := -6.0 + i * 2.8
		_slab(Vector3(x - 0.12, 6 + YOFF, -15.45), Vector3(x + 0.12, 8.9, -15.25), w)
		_slab(Vector3(x - 0.12, 6 + YOFF, -12.75), Vector3(x + 0.12, 8.9, -12.55), w)
		_slab(Vector3(x - 0.14, 8.75, -15.5), Vector3(x + 0.14, 9.0, -12.5), w, false)
	_board("ŠACHTA →", Vector3(-1.45, 2.0, -8.0), PI / 2.0, Vector2(0.9, 0.35), Color(0.3, 0.2, 0.12),
		Color(0.85, 0.8, 0.65), 28)
	_board("← NEPOUŽÍVAŤ: PLYN", Vector3(-1.45, 2.0, -4.6), PI / 2.0, Vector2(1.3, 0.35), Color(0.85, 0.7, 0.1),
		Color(0.1, 0.05, 0.02), 26)
	_board("ÚZKA CHODBA\nlen jednotlivo", Vector3(3.45, 1.7, -16.0), -PI / 2.0, Vector2(1.0, 0.5),
		Color(0.3, 0.2, 0.12), Color(0.85, 0.8, 0.65), 24)
	# Old junk on the floor.
	_model(SURVIVAL_X + "tool-pickaxe.glb", Vector3(0.4, 1.0, 0.2), Vector3(-2.5, YOFF, -16.5), 0.4)
	_solid(SURVIVAL + "box-large.glb", Vector3(1.0, 0.8, 1.0), Vector3(2.5, YOFF, -16.6), 0.2)
	_loud_prop("OldBucket", SURVIVAL + "bucket.glb", Vector3(0.45, 0.45, 0.45), Vector3(-2.6, YOFF, -15.2), 2.0,
		26.0, "metal_hit")


## Steep ladder ramps (too steep to jog up casually, fine to climb): shaft and grotto.
func _build_ladders() -> void:
	# The ledge in the shaft (top of the ladder) and in the grotto (end of the gallery).
	_slab(Vector3(-12.5, 5.6, -14.5), Vector3(-7.5, 6 + YOFF, -12.5), _m["wood"])
	_slab(Vector3(5.5, 5.6, -12.5), Vector3(9.5, 6 + YOFF, -10.5), _m["wood"])
	_slab(Vector3(-11.2, 6 + YOFF, -12.6), Vector3(-7.5, 7.0, -12.5), _m["wood"])
	_slab(Vector3(6.8, 6 + YOFF, -10.6), Vector3(9.5, 7.0, -10.5), _m["wood"])
	_ladder(Vector3(-11.8, 6 + YOFF, -12.5), Vector3(-11.8, YOFF, -5.8))
	_ladder(Vector3(6.2, 6 + YOFF, -10.5), Vector3(6.2, YOFF, -3.9))


func _ladder(top: Vector3, bottom: Vector3) -> void:
	_ramp(top, bottom, 1.2)
	var run := bottom - top
	var fwd := run.normalized()
	var up := Vector3(0, fwd.z, -fwd.y)
	if up.y < 0.0:
		up = -up
	var basis := Basis(up.cross(fwd).normalized(), up, fwd)
	for side in [-0.5, 0.5]:
		_block(Vector3(0.08, 0.1, run.length()), Transform3D(basis, (top + bottom) / 2.0 + Vector3(side, 0, 0)),
			_m["wood"], false)
	var steps := int(run.length() / 0.35)
	for i in steps:
		var p := top + run * (float(i) + 0.5) / steps
		_block(Vector3(1.0, 0.06, 0.08), Transform3D(basis, p + up * 0.04), _m["wood"], false)


func _build_grotto() -> void:
	# Stalactites, pillars and the glowing crystals the Kobold caps grow among.
	var rock: Material = _m["rock"]
	for i in 18:
		var p := Vector3(_rng.randf_range(6.0, 13.5), 9 + YOFF, _rng.randf_range(-12.0, -4.0))
		var cone := MeshInstance3D.new()
		var mesh := CylinderMesh.new()
		mesh.top_radius = _rng.randf_range(0.2, 0.5)
		mesh.bottom_radius = 0.0
		mesh.height = _rng.randf_range(0.8, 2.5)
		mesh.radial_segments = 5
		mesh.rings = 1
		cone.mesh = mesh
		cone.material_override = rock
		cone.position = p - Vector3(0, mesh.height / 2.0, 0)
		_root.add_child(cone)
	_block(Vector3(1.4, 9.0, 1.2), Transform3D(Basis.from_euler(Vector3(0.05, 0.4, 0)), Vector3(12.2, 4.5, -5.5)), rock)
	_block(Vector3(1.0, 9.0, 1.4), Transform3D(Basis.from_euler(Vector3(-0.04, 1.1, 0)), Vector3(8.5, 4.5, -6.0)), rock)
	for i in 14:
		var p := Vector3(_rng.randf_range(9.0, 13.3), YOFF, _rng.randf_range(-11.8, -7.0))
		var h := _rng.randf_range(0.3, 1.1)
		var basis := Basis.from_euler(Vector3(_rng.randf_range(-0.5, 0.5), _rng.randf() * TAU, _rng.randf_range(-0.5, 0.5)))
		_block(Vector3(0.14, h, 0.14), Transform3D(basis, p + Vector3(0, h * 0.4, 0)), _m["crystal"], false)
	_label("tu rastú\nkoboldie hríby", Vector3(13.45, 2.2, -9.0), -PI / 2.0, 36, Color(0.6, 1.0, 0.5), true)


func _build_gas() -> void:
	# Warning signs, a dead canary in its cage, and a sickly haze that hangs in the pocket.
	_board("POZOR! BANSKÝ PLYN\nNEZAPAĽOVAŤ\nžiadne svetlice", Vector3(-2.2, 1.8, -2.55), 0.0, Vector2(1.6, 0.8),
		Color(0.85, 0.7, 0.1), Color(0.1, 0.05, 0.02), 26)
	_label("☠", Vector3(-6.0, 2.2, -2.55), PI, 90, Color(0.75, 0.7, 0.15), true)
	_slab(Vector3(-9.2, 1.4, -3.8), Vector3(-8.8, 1.8, -3.4), _m["metal"], false)
	_slab(Vector3(-9.08, 1.42, -3.66), Vector3(-8.92, 1.48, -3.54), _paint(Color(0.9, 0.8, 0.1)), false)
	for i in 4:
		var haze := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(7.5 - i * 1.2, 0.35, 1.8)
		haze.mesh = mesh
		haze.material_override = _m["gas"]
		haze.position = Vector3(-6.2, 0.9 + i * 0.35, -3.5)
		_root.add_child(haze)
		_gas_haze.append(haze)


func _build_rubble() -> void:
	for i in RUBBLE.size():
		var centre: Vector3 = RUBBLE[i][0]
		var size: Vector3 = RUBBLE[i][1]
		var it := InteractableScript.new()
		it.configure("Rubble%d" % i, size, centre + Vector3(0, size.y / 2.0 + YOFF, 0),
			"dig through the rubble (0/%d)" % DIG_HITS, _dig.bind(i))
		_root.add_child(it)
		var pile := Node3D.new()
		pile.name = "Pile"
		pile.position.y = -size.y / 2.0
		it.add_child(pile)
		for k in 9:
			var s := _rng.randf_range(0.6, 1.3)
			var mi := MeshInstance3D.new()
			var mesh := BoxMesh.new()
			mesh.size = Vector3(s, s * 0.8, s)
			mi.mesh = mesh
			mi.material_override = _m["rock"]
			mi.position = Vector3(_rng.randf_range(-size.x, size.x) * 0.35, _rng.randf_range(0.3, size.y - 0.4),
				_rng.randf_range(-size.z, size.z) * 0.35)
			mi.rotation = Vector3(_rng.randf(), _rng.randf() * TAU, _rng.randf())
			pile.add_child(mi)
		_set_body(it, false)
		_rubble.append(it)
		_rubble_hits.append(0)
		_rubble_cool.append(5.0)


func _build_cart() -> void:
	# Rails from the yard to the hall, and a buffer at each end.
	for x in [-0.45, 0.45]:
		_slab(Vector3(x - 0.04, YOFF, -14.3), Vector3(x + 0.04, YOFF + 0.08, 9.6), _m["metal"], false)
	for i in 30:
		var z := 9.4 - i * 0.8
		_slab(Vector3(-0.7, YOFF - 0.01, z - 0.1), Vector3(0.7, YOFF + 0.03, z + 0.1), _m["wood"], false)
	_slab(Vector3(-0.8, YOFF, 9.6), Vector3(0.8, 0.7, 9.9), _m["wood"])
	_cart = CartScript.new()
	_cart.blocked = _rails_blocked
	_root.add_child(_cart)
	_cart.build(Vector3(0, YOFF, 8.0), Vector3(0, YOFF, -13.2), _m["rust"], _m["dark"])
	for spot in [[Vector3(1.4, 0.6, 7.0), 0.0], [Vector3(1.9, 0.6, -14.8), 0.0]]:
		var p: Vector3 = spot[0]
		_slab(p + Vector3(-0.2, -0.6, -0.2), p + Vector3(0.2, -0.2, 0.2), _m["metal"])
		var stick := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.06, 0.8, 0.06)
		stick.mesh = mesh
		stick.material_override = _m["warn"]
		stick.position = p + Vector3(0, 0.1, 0)
		stick.rotation.x = 0.5
		_root.add_child(stick)
	var prompt := "pull the lever (send the cart)"
	_interactable("LeverOut", Vector3(0.6, 1.2, 0.6), Vector3(1.4, 0.6, 7.0), prompt, _use_lever)
	_interactable("LeverIn", Vector3(0.6, 1.2, 0.6), Vector3(1.9, 0.6, -14.8), prompt, _use_lever)


func _build_lights() -> void:
	var warm := Color(1.0, 0.7, 0.4)
	_lamp(Vector3(0, 2.6, -8.0), warm, 0.9, 7.0, true)
	_lamp(Vector3(0, 3.4, -16.0), warm, 1.0, 7.0)
	_lamp(Vector3(-10.0, 5.0, -9.0), Color(0.7, 0.75, 0.9), 0.5, 8.0)
	_lamp(Vector3(2.0, 8.4, -14.0), warm, 0.6, 6.0, true)
	_lamp(Vector3(10.5, 3.0, -8.5), Color(0.6, 1.0, 0.4), 2.2, 11.0)
	_lamp(Vector3(-7.0, 1.6, -3.5), Color(0.6, 0.8, 0.3), 0.5, 4.0)
	for p in [Vector3(0, 2.4, -8.0), Vector3(0, 3.2, -16.0), Vector3(2.0, 8.2, -14.0)]:
		_model(GRAVE + "lantern-candle.glb", Vector3(0.3, 0.45, 0.3), p, 0.0)
	_portal_light = _lamp(Vector3(2.9, 3.6, 9.1), warm, 1.6, 10.0)
	_portal_light.visible = false


## The knoll's tunnels must not dip into the ground outside the flat place.
func _check_terrain() -> void:
	for c in _empty:
		var cell: Vector3i = c
		if cell.y != 0:
			continue
		var ground := _ground_at(Vector3(cell.x, 0, cell.z))
		if ground > YOFF + 0.5:
			push_warning("Mine: terrain pokes into the tunnel at cell %s (%.1f m)" % [cell, ground])
			return
