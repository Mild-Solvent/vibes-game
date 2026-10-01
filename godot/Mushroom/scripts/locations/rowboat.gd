extends AnimatableBody3D
## The leaky rowboat to the island. Two oars (E on each): it only really moves when both are
## pulled within the same second; one oar alone just turns it. More than three aboard and it
## sinks (back at the jetty a bit later). Out on open water something big bumps it now and then.
## The host moves it; everyone sees the synced transform.

const Terrain := preload("res://scripts/world/terrain.gd")
const ModelFit := preload("res://scripts/model_fit.gd")
const PAIR_WINDOW := 1.0  # both oars within this many seconds = a proper stroke
const STROKE := 1.6  # m/s added by a proper stroke
const SOLO_PUSH := 0.25
const SOLO_TURN := 0.32  # rad/s added by one oar alone
const DRAG := 0.55
const TURN_DRAG := 1.4
const MAX_ABOARD := 3
const SINK_SECONDS := 3.0
const BACK_AFTER := 9.0
const HALF := Vector3(1.0, 1.6, 1.75)  # who counts as aboard (boat space, from the floor up)

signal bumped(side: float)  # host: something hit the boat; the island shows it to everyone

var _dock := Transform3D.IDENTITY  # parent space
var _speed := 0.0
var _turn := 0.0
var _side := 0.0  # sideways drift (after a bump)
var _last_oar := [-10.0, -10.0]  # host time of the last pull, left / right
var _sinking := -1.0  # seconds since it started going down, -1 = afloat
var _water_y := 0.0  # parent space
var _bump_timer := 15.0
var _rng := RandomNumberGenerator.new()


func build(model_path: String, dock: Transform3D, water_y: float, wood: Material, seed_value: int) -> void:
	name = "Rowboat"
	_dock = dock
	_water_y = water_y
	transform = dock
	sync_to_physics = false  # moved by script; kinematic bodies still report platform velocity
	_rng.seed = seed_value
	# The model's box includes its paddles sticking out sideways: this makes the hull ~2 x 3.3 m.
	var model := ModelFit.fit(model_path, Vector3(3.9, 1.2, 3.35), 0.0)
	model.position.y += 0.6 - 0.15  # floats: only a hand's width of hull under the surface
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).material_override = wood  # weathered planks, reads well on the water
	add_child(model)
	var parts := [
		[Vector3(1.7, 0.1, 3.1), Vector3(0, 0.15, 0)],
		[Vector3(0.08, 0.6, 3.1), Vector3(0.9, 0.45, 0)],
		[Vector3(0.08, 0.6, 3.1), Vector3(-0.9, 0.45, 0)],
		[Vector3(1.8, 0.6, 0.08), Vector3(0, 0.45, 1.6)],
		[Vector3(1.8, 0.6, 0.08), Vector3(0, 0.45, -1.6)],
	]
	for part in parts:
		var shape := BoxShape3D.new()
		shape.size = part[0]
		var col := CollisionShape3D.new()
		col.shape = shape
		col.position = part[1]
		add_child(col)
	# Bilge water sloshing in the bottom: it's leaky, everybody knows.
	var puddle := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(1.3, 0.02, 2.4)
	puddle.mesh = mesh
	var water := StandardMaterial3D.new()
	water.albedo_color = Color(0.15, 0.3, 0.32, 0.8)
	water.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	puddle.material_override = water
	puddle.position.y = 0.21
	add_child(puddle)
	var sync := MultiplayerSynchronizer.new()
	sync.name = "Sync"
	var config := SceneReplicationConfig.new()
	config.add_property(NodePath(".:position"))
	config.add_property(NodePath(".:rotation"))
	sync.replication_config = config
	add_child(sync)


## Host: back at the jetty, afloat, for a new day.
func reset() -> void:
	transform = _dock
	_speed = 0.0
	_turn = 0.0
	_side = 0.0
	_sinking = -1.0


## Host: someone pulled an oar (0 = left, 1 = right). Returns a line for them.
func pull(oar: int, peer: int) -> String:
	if _sinking >= 0.0:
		return "Row harder? It's underwater."
	if not _is_aboard(peer):
		return "Get in the boat first."
	var now := Time.get_ticks_msec() / 1000.0
	var other: float = _last_oar[1 - oar]
	_last_oar[oar] = now
	Sfx.play_all("splash", global_position)
	var turn_sign := -1.0 if oar == 0 else 1.0
	if now - other <= PAIR_WINDOW:
		_last_oar = [-10.0, -10.0]
		_speed += STROKE
		_turn += turn_sign * SOLO_TURN  # cancels the first oar's turn (it had the other sign)
		return "Together! The boat surges forward."
	_speed += SOLO_PUSH
	_turn += turn_sign * SOLO_TURN
	return "One oar: the boat turns. Pull together (within a second)!"


func aboard() -> Array:
	var result := []
	for p in get_tree().get_nodes_in_group("players"):
		if Team.is_alive(p.peer_id) and _local_in(to_local(p.global_position)):
			result.append(p)
	return result


func _is_aboard(peer: int) -> bool:
	for p in aboard():
		if p.peer_id == peer:
			return true
	return false


static func _local_in(p: Vector3) -> bool:
	return absf(p.x) < HALF.x and absf(p.z) < HALF.z and p.y > -0.4 and p.y < HALF.y


func _physics_process(delta: float) -> void:
	if not multiplayer.is_server():
		return
	if _sinking >= 0.0:
		_sinking += delta
		position.y = _water_y - minf(_sinking / SINK_SECONDS, 1.0) * 2.2
		rotation.z = minf(_sinking / SINK_SECONDS, 1.0) * 0.5
		if _sinking > BACK_AFTER:
			reset()
		return
	var crew := aboard()
	if crew.size() > MAX_ABOARD:
		_sinking = 0.0
		Sfx.play_all("splash", global_position)
		for p in crew:
			Team.tell(p.peer_id, "Four in a leaky boat? Glub glub. Swim for it!")
		return
	_speed *= exp(-DRAG * delta)
	_turn *= exp(-TURN_DRAG * delta)
	_side *= exp(-1.5 * delta)
	rotation.y += _turn * delta
	rotation.x = lerpf(rotation.x, 0.0, 3.0 * delta)
	rotation.z = lerpf(rotation.z, 0.0, 3.0 * delta)
	var fwd := Basis(Vector3.UP, rotation.y) * Vector3(0, 0, 1)
	var right := Basis(Vector3.UP, rotation.y) * Vector3(1, 0, 0)
	var step := fwd * _speed * delta + right * _side * delta
	if _grounded(position + fwd * 1.9 * signf(_speed) + step):
		_speed = 0.0
		step = right * _side * delta
	if _grounded(position + step + right * 0.8 * signf(_side)):
		_side = 0.0
		step = fwd * _speed * delta
	position += step
	position.y = _water_y + sin(Time.get_ticks_msec() / 700.0) * 0.03
	# Out on open water, something down there takes an interest.
	if not crew.is_empty() and position.distance_to(_dock.origin) > 10.0:
		_bump_timer -= delta
		if _bump_timer <= 0.0:
			_bump_timer = _rng.randf_range(10.0, 22.0)
			var side := 1.0 if _rng.randf() < 0.5 else -1.0
			_side += side * 1.4
			_turn += side * 0.7
			rotation.z = side * 0.2
			bumped.emit(side)
			for p in crew:
				Team.tell(p.peer_id, ["Something big bumps the boat.", "THUD. Under the boat. Keep rowing.",
					"A huge dark shape slides under you. Sumec?"][_rng.randi() % 3])


## Would the hull hit the lake bed here (parent space)?
func _grounded(p: Vector3) -> bool:
	var g := (get_parent() as Node3D).to_global(p)
	return Terrain.height(g.x, g.z) > Terrain.WATER_Y - 0.35
