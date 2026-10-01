extends Node3D
## Shared plumbing for the scary cure locations (sanatorium, mine, crypt, island).
##
## A location is built identically on every peer by `build()`, under a "Root" node turned so
## the location's front (+Z in the build frame) faces the road. Static walls are merged into a
## few meshes per material and per 14 m chunk (cheap to draw, and each chunk only meets a few
## lights) and one StaticBody full of box shapes. The host runs traps and monsters; the cure
## ingredients are ordinary mushroom props.

const ModelFit := preload("res://scripts/model_fit.gd")
const Terrain := preload("res://scripts/world/terrain.gd")
const MushroomScript := preload("res://scripts/mushroom.gd")
const InteractableScript := preload("res://scripts/interactable.gd")
const PropScript := preload("res://scripts/prop.gd")
const LoudPropScript := preload("res://scripts/locations/loud_prop.gd")

const CHUNK := 14.0
## Footsteps inside a location's quiet zones are reported to Hearing (players don't report their own).
const FOOTSTEP_NOISE := true
const WALK_LOUD := 5.0
const SPRINT_LOUD := 14.0
const GLASS_LOUD := 24.0
## The ingredient counts as taken once it is held or moved this far from its spot.
const TAKEN_DISTANCE := 0.8

const K := "res://assets/kenney/"
const FURNITURE := "res://assets/kenney/furniture-kit/"
const GRAVE := "res://assets/kenney/graveyard-kit/"
const GRAVE_X := "res://assets/kenney/graveyard-kit-extra/"
const SURVIVAL := "res://assets/kenney/survival-kit/"
const SURVIVAL_X := "res://assets/kenney/survival-kit-extra/"
const NATURE := "res://assets/kenney/nature-kit/"
const CHARS := "res://assets/kenney/mini-characters/"

static var _grime: NoiseTexture2D

var night := false
var _root: Node3D
var _static: StaticBody3D
var _chunks := {}  # "material id|chunk" -> [SurfaceTool, Material]
var _mats := {}
var _ingredients: Array = []  # mushroom props
var _quiet_zones: Array[AABB] = []  # root-local: footsteps here are heard
var _glass_zones: Array[AABB] = []  # root-local: broken glass, loud underfoot
var _last_pos := {}  # host: peer id -> Vector3
var _step_timer := {}  # host: peer id -> seconds until the next footstep report
var _flicker: Array = []  # [OmniLight3D, base energy, seed]


# --- frame ---------------------------------------------------------------------------


## Starts building: makes the turned Root and the shared static body.
func _begin(yaw: float) -> void:
	_root = Node3D.new()
	_root.name = "Root"
	_root.rotation.y = yaw
	add_child(_root)
	_static = StaticBody3D.new()
	_static.name = "Static"
	_root.add_child(_static)


## An interior: inside this root-local box the sky's ambient light is replaced by `ambient`
## (so a building is dark inside even at noon). Reflection probes, no baking.
func _interior(box: AABB, ambient := Color(0.05, 0.055, 0.06), energy := 1.0) -> ReflectionProbe:
	var probe := ReflectionProbe.new()
	probe.position = box.get_center()
	probe.size = box.size
	probe.interior = true
	probe.ambient_mode = ReflectionProbe.AMBIENT_COLOR
	probe.ambient_color = ambient
	probe.ambient_color_energy = energy
	probe.update_mode = ReflectionProbe.UPDATE_ONCE
	probe.intensity = 0.0
	probe.blend_distance = 0.5
	_root.add_child(probe)
	return probe


## Finishes building: turns the merged geometry into meshes.
func _finish() -> void:
	for key in _chunks:
		var entry: Array = _chunks[key]
		var st: SurfaceTool = entry[0]
		var mi := MeshInstance3D.new()
		mi.mesh = st.commit()
		mi.material_override = entry[1]
		_root.add_child(mi)
	_chunks.clear()


func _g(local_pos: Vector3) -> Vector3:
	return _root.to_global(local_pos)


func _l(global_pos: Vector3) -> Vector3:
	return _root.to_local(global_pos)


## Terrain height under a root-local point, in root-local y.
func _ground_at(local_pos: Vector3) -> float:
	var g := _g(local_pos)
	return Terrain.height(g.x, g.z) - _root.global_position.y


# --- materials -------------------------------------------------------------------------


static func _grime_texture() -> NoiseTexture2D:
	if _grime == null:
		var noise := FastNoiseLite.new()
		noise.seed = 1987
		noise.frequency = 0.09
		noise.fractal_octaves = 3
		_grime = NoiseTexture2D.new()
		_grime.width = 256
		_grime.height = 256
		_grime.seamless = true
		_grime.noise = noise
		var ramp := Gradient.new()
		ramp.set_color(0, Color(0.74, 0.72, 0.68))
		ramp.set_color(1, Color(1, 1, 1))
		_grime.color_ramp = ramp
	return _grime


## A matte material, optionally with world-space grime (so merged boxes need no UVs).
func _paint(color: Color, grime := true, emission := 0.0, alpha := 1.0) -> StandardMaterial3D:
	var key := "%s|%s|%s|%s" % [color.to_html(), grime, emission, alpha]
	if _mats.has(key):
		return _mats[key]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(color.r, color.g, color.b, alpha)
	mat.roughness = 1.0
	if grime:
		mat.albedo_texture = _grime_texture()
		mat.uv1_triplanar = true
		mat.uv1_world_triplanar = true
		mat.uv1_scale = Vector3.ONE * 0.3
	if emission > 0.0:
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = emission
	if alpha < 1.0:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mats[key] = mat
	return mat


# --- static geometry -------------------------------------------------------------------


## A box merged into the static geometry. `xform` is root-local; `solid` adds a collider.
func _block(size: Vector3, xform: Transform3D, mat: Material, solid := true) -> void:
	var cell := Vector3i((xform.origin / CHUNK).floor())
	var key := "%d|%s" % [mat.get_instance_id(), cell]
	if not _chunks.has(key):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		_chunks[key] = [st, mat]
	var box := BoxMesh.new()
	box.size = size
	(_chunks[key][0] as SurfaceTool).append_from(box, 0, xform)
	if solid:
		var shape := BoxShape3D.new()
		shape.size = size
		var col := CollisionShape3D.new()
		col.shape = shape
		col.transform = xform
		_static.add_child(col)


## An axis-aligned box from corner `a` to corner `b` (root-local).
func _slab(a: Vector3, b: Vector3, mat: Material, solid := true) -> void:
	var lo := Vector3(minf(a.x, b.x), minf(a.y, b.y), minf(a.z, b.z))
	var hi := Vector3(maxf(a.x, b.x), maxf(a.y, b.y), maxf(a.z, b.z))
	_block(hi - lo, Transform3D(Basis(), (lo + hi) / 2.0), mat, solid)


## A walkable ramp from `top` to `bottom` (centres of its top edge and bottom edge), `width` wide.
## Collider only by default; pass a material to see it.
func _ramp(top: Vector3, bottom: Vector3, width: float, mat: Material = null, thick := 0.12) -> void:
	var run := bottom - top
	var length := run.length()
	var fwd := run.normalized()
	var side := Vector3.UP.cross(fwd).normalized()
	if side.length() < 0.5:
		side = Vector3.RIGHT
	var up := fwd.cross(side).normalized()
	if up.y < 0.0:
		up = -up
		side = -side
	var rot := Basis(side, up, fwd)
	var centre := (top + bottom) / 2.0 - up * thick / 2.0
	var size := Vector3(width, thick, length)
	if mat:
		_block(size, Transform3D(rot, centre), mat, true)
	else:
		var shape := BoxShape3D.new()
		shape.size = size
		var col := CollisionShape3D.new()
		col.shape = shape
		col.transform = Transform3D(rot, centre)
		_static.add_child(col)


## Visual steps under a ramp from `top` to `bottom` (straight along one axis), solid to `floor_y`.
func _steps(top: Vector3, bottom: Vector3, width: float, count: int, mat: Material, floor_y: float) -> void:
	var run := bottom - top
	for i in count:
		var t0 := float(i) / count
		var t1 := float(i + 1) / count
		var p0 := top + run * t0
		var p1 := top + run * t1
		var h := top.y + run.y * t1  # each step sits at its lower edge's height
		var lo := Vector3(minf(p0.x, p1.x), floor_y, minf(p0.z, p1.z))
		var hi := Vector3(maxf(p0.x, p1.x), h, maxf(p0.z, p1.z))
		if absf(run.x) > absf(run.z):
			lo.z = top.z - width / 2.0
			hi.z = top.z + width / 2.0
		else:
			lo.x = top.x - width / 2.0
			hi.x = top.x + width / 2.0
		if hi.y - lo.y > 0.01:
			_slab(lo, hi, mat, false)


## A wall along X (at z = `at`) or along Z (at x = `at`) from `a` to `b`, y0..y1, painted two-tone
## (`lower` up to `split`, `upper` above), with openings [from, to, bottom y, top y].
func _wall_run(along_x: bool, at: float, a: float, b: float, y0: float, y1: float, gaps: Array,
		lower: Material, upper: Material, split: float, thick := 0.2) -> void:
	var cursor := a
	var sorted := gaps.duplicate()
	sorted.sort_custom(func(p, q): return p[0] < q[0])
	for g in sorted:
		_wall_piece(along_x, at, cursor, g[0], y0, y1, lower, upper, split, thick)
		_wall_piece(along_x, at, g[0], g[1], y0, g[2], lower, upper, split, thick)
		_wall_piece(along_x, at, g[0], g[1], g[3], y1, lower, upper, split, thick)
		cursor = g[1]
	_wall_piece(along_x, at, cursor, b, y0, y1, lower, upper, split, thick)


func _wall_piece(along_x: bool, at: float, a: float, b: float, y0: float, y1: float,
		lower: Material, upper: Material, split: float, thick: float) -> void:
	if b - a < 0.01 or y1 - y0 < 0.01:
		return
	var parts := [[y0, minf(y1, split), lower], [maxf(y0, split), y1, upper]]
	for part in parts:
		if part[1] - part[0] < 0.01:
			continue
		if along_x:
			_slab(Vector3(a, part[0], at - thick / 2.0), Vector3(b, part[1], at + thick / 2.0), part[2])
		else:
			_slab(Vector3(at - thick / 2.0, part[0], a), Vector3(at + thick / 2.0, part[1], b), part[2])


## A separate box body (for things that change: doors, trapdoors, rubble). Root-local.
func _body(node_name: String, size: Vector3, pos: Vector3, mat: Material) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = node_name
	body.position = pos
	var shape := BoxShape3D.new()
	shape.size = size
	var col := CollisionShape3D.new()
	col.shape = shape
	body.add_child(col)
	var mesh := BoxMesh.new()
	mesh.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	body.add_child(mi)
	_root.add_child(body)
	return body


## Turns a `_body` on or off (collision and looks).
static func _set_body(body: CollisionObject3D, on: bool) -> void:
	body.visible = on
	for child in body.get_children():
		if child is CollisionShape3D:
			child.set_deferred("disabled", not on)


# --- models, lights, signs ---------------------------------------------------------------


## A model standing on `pos` (feet at pos.y), no collision. Root-local.
func _model(path: String, size: Vector3, pos: Vector3, yaw := 0.0, parent: Node3D = null) -> Node3D:
	var model := ModelFit.fit(path, size, yaw)
	model.position += pos + Vector3(0, size.y / 2.0, 0)
	(parent if parent else _root).add_child(model)
	return model


## Paints every mesh of a model one flat colour (rusty iron, dead wood).
func _tint(node: Node, color: Color) -> Node:
	var mat := _paint(color, false)
	for mi in node.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).material_override = mat
	return node


## Same, with a box collider (85% of the footprint, so you can squeeze past).
func _solid(path: String, size: Vector3, pos: Vector3, yaw := 0.0) -> Node3D:
	var body := StaticBody3D.new()
	body.position = pos + Vector3(0, size.y / 2.0, 0)
	body.rotation.y = yaw
	var shape := BoxShape3D.new()
	shape.size = size * Vector3(0.85, 1.0, 0.85)
	var col := CollisionShape3D.new()
	col.shape = shape
	body.add_child(col)
	body.add_child(ModelFit.fit(path, size))
	_root.add_child(body)
	return body


## A loud physics prop (tray, gurney, bucket): makes noise the Hearing autoload hears when it hits something.
func _loud_prop(prop_name: String, path: String, size: Vector3, pos: Vector3, body_mass: float,
		loudness: float, sound: String, yaw := 0.0) -> RigidBody3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var shape := BoxShape3D.new()
	shape.size = size
	var prop := LoudPropScript.new()
	prop.setup(prop_name, mesh, shape, Color(0.6, 0.6, 0.6), body_mass)
	prop.loudness = loudness
	prop.sound = sound
	prop.display_name = prop_name.capitalize().rstrip("0123456789 ")
	if path != "":
		for child in prop.get_children():
			if child is MeshInstance3D:
				child.visible = false
		prop.add_child(ModelFit.fit(path, size, 0.0, true))
	prop.position = pos + Vector3(0, size.y / 2.0 + 0.02, 0)
	prop.rotation.y = yaw
	_root.add_child(prop)
	return prop


func _lamp(pos: Vector3, color: Color, energy: float, light_range: float, flicker := false) -> OmniLight3D:
	var light := OmniLight3D.new()
	light.position = pos
	light.light_color = color
	light.light_energy = energy
	light.omni_range = light_range
	light.omni_attenuation = 1.4
	_root.add_child(light)
	if flicker:
		_flicker.append([light, energy, _flicker.size() * 7.31 + 1.0])
	return light


## A fixed (not billboard) sign. `yaw` turns it; it reads from both sides.
func _label(text: String, pos: Vector3, yaw := 0.0, size := 64, color := Color(0.9, 0.88, 0.8),
		shaded := false) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.font_size = size
	label.pixel_size = 0.006
	label.outline_size = 0
	label.modulate = color
	label.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	label.double_sided = true
	label.shaded = shaded
	label.position = pos
	label.rotation.y = yaw
	_root.add_child(label)
	return label


## A wooden or metal board with text on it, facing +Z after `yaw`.
func _board(text: String, pos: Vector3, yaw: float, size: Vector2, board: Color, ink: Color,
		font := 48) -> void:
	var holder := Node3D.new()
	holder.position = pos
	holder.rotation.y = yaw
	_root.add_child(holder)
	var mesh := BoxMesh.new()
	mesh.size = Vector3(size.x, size.y, 0.06)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _paint(board)
	holder.add_child(mi)
	for side in [1.0, -1.0]:
		var label := Label3D.new()
		label.text = text
		label.font_size = font
		label.pixel_size = 0.005
		label.modulate = ink
		label.outline_size = 0
		label.double_sided = false
		label.shaded = true
		label.width = size.x / 0.005 * 0.92
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.position = Vector3(0, 0, 0.035 * side)
		label.rotation.y = 0.0 if side > 0.0 else PI
		holder.add_child(label)


func _interactable(node_name: String, size: Vector3, pos: Vector3, prompt: String, use: Callable,
		parent: Node3D = null) -> StaticBody3D:
	var it := InteractableScript.new()
	it.configure(node_name, size, pos, prompt, use)
	(parent if parent else _root).add_child(it)
	return it


## Synchronises position + rotation (+ extra properties) of a host-driven node.
static func _add_sync(node: Node, extra: Array = []) -> void:
	var sync := MultiplayerSynchronizer.new()
	sync.name = "Sync"
	var config := SceneReplicationConfig.new()
	for path in [NodePath(".:position"), NodePath(".:rotation")] + extra:
		config.add_property(path)
	sync.replication_config = config
	node.add_child(sync)


# --- ingredients -----------------------------------------------------------------------------


## A cure-ingredient mushroom at a root-local spot.
func _ingredient(node_name: String, kind: String, pos: Vector3, yaw := 0.0) -> RigidBody3D:
	var m := MushroomScript.new()
	m.setup_mushroom(node_name, kind)
	m.position = pos + Vector3(0, 0.15, 0)
	m.rotation.y = yaw
	_root.add_child(m)
	_ingredients.append(m)
	return m


## Host: has anybody picked, moved, packed or eaten an ingredient?
func _ingredient_taken() -> bool:
	for m in _ingredients:
		if m.removed or m.holder_id != 0:
			return true
		if m.transform.origin.distance_to(m.get("_home").origin) > TAKEN_DISTANCE:
			return true
	return false


## Host: put every ingredient back on its spot.
func _reset_ingredients() -> void:
	for m in _ingredients:
		m.reset_to_home()


# --- players ---------------------------------------------------------------------------------


## Living players on foot.
func _alive_players() -> Array:
	var result := []
	for p in get_tree().get_nodes_in_group("players"):
		if Team.is_alive(p.peer_id) and not p.in_car():
			result.append(p)
	return result


func _local_player() -> Node3D:
	var me := multiplayer.get_unique_id()
	for p in get_tree().get_nodes_in_group("players"):
		if p.peer_id == me:
			return p
	return null


func _player_by_id(peer_id: int) -> Node3D:
	for p in get_tree().get_nodes_in_group("players"):
		if p.peer_id == peer_id:
			return p
	return null


static func _in_zones(zones: Array[AABB], local_pos: Vector3) -> bool:
	for zone in zones:
		if zone.has_point(local_pos):
			return true
	return false


## Players (alive, on foot) whose feet are inside any of `zones` (root-local).
func _players_in(zones: Array[AABB]) -> Array:
	var result := []
	for p in _alive_players():
		if _in_zones(zones, _l(p.global_position)):
			result.append(p)
	return result


## Host: report footsteps of players moving inside the quiet zones (and crunching glass).
func _report_footsteps(delta: float) -> void:
	if not FOOTSTEP_NOISE:
		return
	for p in _alive_players():
		var pos: Vector3 = p.global_position
		var last: Vector3 = _last_pos.get(p.peer_id, pos)
		_last_pos[p.peer_id] = pos
		var timer: float = _step_timer.get(p.peer_id, 0.0) - delta
		_step_timer[p.peer_id] = timer
		if timer > 0.0:
			continue
		var local := _l(pos)
		if not _in_zones(_quiet_zones, local):
			continue
		var speed := Vector2(pos.x - last.x, pos.z - last.z).length() / maxf(delta, 0.001)
		if speed < 1.5:
			continue
		var loud := SPRINT_LOUD if speed > 6.0 else WALK_LOUD
		if _in_zones(_glass_zones, local):
			loud = maxf(loud, GLASS_LOUD)
			Sfx.play_all("branch_snap", pos)
		Hearing.emit(pos, loud, p.peer_id)
		_step_timer[p.peer_id] = 0.45


## Every peer: the flickering lamps.
func _update_flicker() -> void:
	var t := Time.get_ticks_msec() / 1000.0
	for entry in _flicker:
		var light: OmniLight3D = entry[0]
		var s: float = entry[2]
		var wobble := 0.75 + 0.25 * sin(t * 13.0 + s) * sin(t * 7.3 + s * 2.0)
		var dropout := sin(t * 1.7 + s * 3.1) + sin(t * 2.9 + s)
		light.light_energy = entry[1] * (0.05 if dropout > 1.55 else wobble)


## Every peer: turn this player's own flashlight off (the Miner pinches it out).
@rpc("authority", "call_local", "reliable")
func _lamp_out() -> void:
	var me := _local_player()
	if me:
		me.flashlight_on = false


## A one-shot puff of dust at a root-local spot (visual only, every peer).
func _dust(pos: Vector3, amount := 40, color := Color(0.45, 0.4, 0.35)) -> void:
	var p := CPUParticles3D.new()
	p.position = pos
	p.one_shot = true
	p.emitting = true
	p.amount = amount
	p.lifetime = 2.5
	p.explosiveness = 0.9
	p.direction = Vector3.UP
	p.spread = 80.0
	p.initial_velocity_min = 0.5
	p.initial_velocity_max = 2.5
	p.gravity = Vector3(0, -1.0, 0)
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.5
	var mesh := BoxMesh.new()
	mesh.size = Vector3.ONE * 0.15
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mesh.material = mat
	p.mesh = mesh
	_root.add_child(p)
	get_tree().create_timer(4.0).timeout.connect(p.queue_free)
