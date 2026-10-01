extends "res://scripts/locations/location.gd"
## The island in the middle of the lake, at midnight. A dead tree, a wayside shrine to the drowned,
## and the Drowned chanterelles that only grow there at night (by day there's nothing but mud).
## Getting there: the leaky rowboat at the jetty on the north shore, where the footpath meets the
## lake. Two people have to row together; four in the boat sinks it. Something lives in the lake.
##
## Build frame: Root is not turned (+Z is global +Z); this node sits on the island's centre. The
## jetty is found at build time: where the footpath's direction from the island meets the shore.

const BoatScript := preload("res://scripts/locations/rowboat.gd")
const INGREDIENT := "drowned_chanterelle"
const FRONT_YAW := 0.0
const JETTY_DIR := Vector3(-0.447, 0, 0.894)  # from the island towards where the footpath arrives
const WATERCRAFT := "res://assets/kenney/watercraft-kit/"

var _boat: AnimatableBody3D
var _jetty := Vector3.ZERO  # root space: the shore end of the jetty
var _water := 0.0  # root-space y of the lake surface
var _night_lights: Array[OmniLight3D] = []
var _drowned: Node3D
var _hidden := {}  # host: ingredient -> true while the day hides it
var _shape: Node3D  # the thing in the lake, shown when it bumps the boat
var _shape_t := 0.0
var _rng := RandomNumberGenerator.new()
var _m := {}


func build() -> void:
	_begin(FRONT_YAW)
	_rng.seed = 1987
	_water = Terrain.WATER_Y - global_position.y
	_m = {
		"wood": _paint(Color(0.3, 0.22, 0.15)),
		"old_wood": _paint(Color(0.22, 0.2, 0.18)),
		"stone": _paint(Color(0.4, 0.4, 0.38)),
		"mud": _paint(Color(0.2, 0.17, 0.13)),
		"dark": _paint(Color(0.02, 0.03, 0.03), false),
	}
	_build_island()
	_build_jetty()
	_build_lake_things()
	for i in 3:
		var spot: Vector3 = [Vector3(1.6, 0, 1.2), Vector3(2.3, 0, 0.4), Vector3(1.1, 0, 2.1)][i]
		spot.y = _ground_at(spot)
		_ingredient("DrownedChanterelle%d" % i, INGREDIENT, spot, i * 2.0)
	_finish()


# --- contract ------------------------------------------------------------------------------


func server_reset() -> void:
	_reset_ingredients()
	_hidden.clear()
	if _boat:
		_boat.reset()
	_apply_night_host()


func set_night(is_night: bool) -> void:
	night = is_night
	for light in _night_lights:
		light.visible = is_night
	if multiplayer.is_server():
		_apply_night_host()


func entrance_position() -> Vector3:
	return _g(_jetty)


## Host: the chanterelles are there only at night. By day the ones lying about are taken away
## (whoever is holding one keeps it); at night the ones the day took come back.
func _apply_night_host() -> void:
	for m in _ingredients:
		if night and _hidden.has(m):
			_hidden.erase(m)
			m.reset_to_home()
		elif not night and not m.removed and m.holder_id == 0:
			_hidden[m] = true
			m.remove_from_play()


# --- running ---------------------------------------------------------------------------------


func _process(delta: float) -> void:
	# The drowned man stands in the shallows at night, and isn't there when you get close.
	var me := _local_player()
	var far := me == null or me.global_position.distance_to(_drowned.global_position) > 14.0
	_drowned.visible = night and far
	if _shape_t > 0.0:
		_shape_t -= delta
		_shape.position.y = _water - 0.4 + sin((1.6 - _shape_t) / 1.6 * PI) * 0.55
		_shape.visible = _shape_t > 0.0


## Host: the boat got bumped; show everyone what did it.
func _on_bumped(side: float) -> void:
	var at := _boat.position + Basis(Vector3.UP, _boat.rotation.y) * Vector3(side * 1.6, 0, 0)
	_show_shape.rpc(at, _boat.rotation.y)
	Hearing.emit(_g(at), 20.0, 0)


## Every peer: the dark back of something huge breaks the surface for a moment.
@rpc("authority", "call_local", "reliable")
func _show_shape(at: Vector3, yaw: float) -> void:
	_shape.position = at
	_shape.rotation.y = yaw
	_shape_t = 1.6
	_shape.visible = true
	Sfx.play("splash", _g(at))


func _row(peer: int, oar: int) -> void:
	Team.tell(peer, _boat.pull(oar, peer))


# --- building -----------------------------------------------------------------------------------


func _build_island() -> void:
	# The dead tree: a huge bare crooked pine, its roots, a rope swing nobody uses.
	var base := Vector3(0, _ground_at(Vector3.ZERO) - 0.2, 0)
	var tree := _solid(GRAVE + "pine-crooked.glb", Vector3(5.0, 10.0, 5.0), base, 0.7)
	_tint(tree, Color(0.17, 0.16, 0.15))
	for i in 5:
		var a := i * TAU / 5.0 + 0.3
		var rot := Basis(Vector3.UP, -a) * Basis(Vector3.BACK, 0.35)
		var p := Vector3(cos(a) * 1.2, _ground_at(Vector3.ZERO) + 0.1, sin(a) * 1.2)
		_block(Vector3(2.0, 0.3, 0.35), Transform3D(rot, p), _m["old_wood"], false)
	_slab(Vector3(-2.3, 3.2, 0.4), Vector3(-2.27, 6.4, 0.43), _paint(Color(0.5, 0.45, 0.35)), false)
	_slab(Vector3(-2.6, 3.15, 0.3), Vector3(-2.0, 3.25, 0.55), _m["wood"], false)
	# A wayside shrine to the drowned.
	var sp := Vector3(-3.5, 0, -3.0)
	sp.y = _ground_at(sp)
	_slab(sp + Vector3(-0.5, 0, -0.5), sp + Vector3(0.5, 1.8, 0.5), _m["stone"])
	_slab(sp + Vector3(-0.7, 1.8, -0.7), sp + Vector3(0.7, 2.0, 0.7), _m["old_wood"])
	_slab(sp + Vector3(-0.3, 1.0, 0.5), sp + Vector3(0.3, 1.6, 0.52), _m["dark"], false)
	_label("Pamiatke utopených\n1954 · 1971 · 1987\nNechoďte k vode v noci.", sp + Vector3(0, 0.6, 0.53), 0.0,
		22, Color(0.75, 0.72, 0.62), true)
	_model(GRAVE + "lantern-candle.glb", Vector3(0.3, 0.45, 0.3), sp + Vector3(0, 2.0, 0), 0.0)
	_night_lights.append(_lamp(sp + Vector3(0, 2.4, 0.3), Color(0.55, 0.8, 1.0), 1.2, 9.0))
	# Rocks, reeds, a sunk boat, mud where the chanterelles come up.
	for i in 9:
		var a := _rng.randf() * TAU
		var r := _rng.randf_range(4.0, 10.0)
		var p := Vector3(cos(a) * r, 0, sin(a) * r)
		p.y = _ground_at(p)
		var rock: String = NATURE + ["rock_tallA.glb", "stone_largeA.glb", "rock_smallA.glb"][i % 3]
		_solid(rock, Vector3(1.2, 1.0, 1.2) * (1.4 - (i % 3) * 0.3), p, _rng.randf() * TAU)
	for i in 30:
		var a := _rng.randf() * TAU
		var r := _rng.randf_range(10.5, 13.5)
		var p := Vector3(cos(a) * r, 0, sin(a) * r)
		p.y = maxf(_ground_at(p), _water - 0.2)
		_model(NATURE + "plant_flatTall.glb", Vector3(0.7, 1.3, 0.7), p, _rng.randf() * TAU)
	var mud := Vector3(1.7, 0, 1.2)
	mud.y = _ground_at(mud) + 0.01
	_block(Vector3(2.4, 0.02, 2.0), Transform3D(Basis(Vector3.UP, 0.4), mud), _m["mud"], false)
	var wreck := Vector3(8.5, 0, -6.0)
	wreck.y = _ground_at(wreck) - 0.2
	_model(WATERCRAFT + "boat-row-small.glb", Vector3(1.4, 0.6, 3.2), wreck, 1.2).rotation.z = 0.5


func _build_jetty() -> void:
	# Walk out from the island along the footpath's direction until we hit the far shore.
	var shore := 70.0
	for i in 140:
		var r := 30.0 + i * 0.5
		if _ground_at(JETTY_DIR * r) + global_position.y >= Terrain.WATER_Y + 0.15:
			shore = r
			break
	_jetty = JETTY_DIR * (shore + 1.0)
	_jetty.y = _ground_at(_jetty)
	var deck_y := _water + 0.5
	var yaw := atan2(JETTY_DIR.x, JETTY_DIR.z)
	var b := Basis(Vector3.UP, yaw)
	var mid := JETTY_DIR * (shore - 2.25)
	_block(Vector3(1.6, 0.15, 8.5), Transform3D(b, Vector3(mid.x, deck_y, mid.z)), _m["wood"])
	_ramp(Vector3(_jetty.x, deck_y + 0.07, _jetty.z), _jetty + JETTY_DIR * 1.5, 1.6)
	for k in 5:
		var p := JETTY_DIR * (shore + 1.0 - k * 1.8)
		for side in [-0.7, 0.7]:
			var post := p + b * Vector3(side, 0, 0)
			_block(Vector3(0.15, 2.4, 0.15), Transform3D(b, Vector3(post.x, deck_y - 0.9, post.z)), _m["old_wood"],
				false)
	var sign_pos := JETTY_DIR * (shore + 2.5)
	sign_pos.y = _ground_at(sign_pos)
	_slab(sign_pos + Vector3(-0.05, 0, -0.05), sign_pos + Vector3(0.05, 1.6, 0.05), _m["old_wood"])
	_board("POŽIČOVŇA LODIEK\nZATVORENÉ\nčln je deravý, max. 3 osoby\nveslujte spolu!",
		sign_pos + Vector3(0, 1.9, 0), yaw, Vector2(1.6, 1.0), Color(0.75, 0.72, 0.6), Color(0.15, 0.1, 0.08), 22)
	var lantern := JETTY_DIR * (shore - 5.5) + b * Vector3(0.7, 0, 0)
	lantern.y = deck_y + 0.07
	_model(GRAVE + "lantern-candle.glb", Vector3(0.3, 0.45, 0.3), lantern, 0.0)
	_night_lights.append(_lamp(lantern + Vector3(0, 0.6, 0), Color(1.0, 0.7, 0.4), 1.0, 8.0))
	# The boat waits beside the end of the jetty, bow towards the island.
	var dock_at := JETTY_DIR * (shore - 5.0) + b * Vector3(2.0, 0, 0)
	dock_at.y = _water
	var dock := Transform3D(Basis(Vector3.UP, yaw + PI), dock_at)
	_boat = BoatScript.new()
	_boat.build(WATERCRAFT + "boat-row-small.glb", dock, _water, _m["wood"], 1987)
	_root.add_child(_boat)  # after build: an AnimatableBody keeps the transform it enters with
	_boat.bumped.connect(_on_bumped)
	_interactable("OarLeft", Vector3(0.6, 0.5, 0.8), Vector3(-1.25, 0.8, 0.0), "pull the LEFT oar",
		_row.bind(0), _boat)
	_interactable("OarRight", Vector3(0.6, 0.5, 0.8), Vector3(1.25, 0.8, 0.0), "pull the RIGHT oar",
		_row.bind(1), _boat)


func _build_lake_things() -> void:
	# The drowned man in the shallows (night only, never when you're close).
	var spot := Vector3(-11.5, 0, 12.5)  # just off the beach, in the water
	var feet := Vector3(spot.x, _water - 0.9, spot.z)
	_drowned = _model(CHARS + "character-male-c.glb", Vector3(3.0, 1.75, 3.0), feet, 2.4)
	var pale := _paint(Color(0.4, 0.55, 0.5), false, 1.2)
	for mi in _drowned.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).material_override = pale
	_drowned.visible = false
	# The thing in the lake: a long dark back with a fin.
	_shape = Node3D.new()
	_shape.name = "LakeThing"
	_root.add_child(_shape)
	var dark := _paint(Color(0.05, 0.07, 0.06), false)
	var body := MeshInstance3D.new()
	var mesh := CapsuleMesh.new()
	mesh.radius = 0.7
	mesh.height = 5.0
	body.mesh = mesh
	body.rotation.x = PI / 2.0
	body.material_override = dark
	_shape.add_child(body)
	var fin := MeshInstance3D.new()
	var fin_mesh := PrismMesh.new()
	fin_mesh.size = Vector3(0.1, 0.8, 1.2)
	fin.mesh = fin_mesh
	fin.position = Vector3(0, 0.8, 0.4)
	fin.material_override = dark
	_shape.add_child(fin)
	_shape.visible = false
