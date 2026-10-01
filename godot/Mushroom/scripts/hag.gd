extends Node3D
## The Hungry Hag. She comes out at dusk and hunts by SOUND: voices, walkies, whistles, flares,
## the car. She also sees torches. Stand still in the dark and shut up, and she wanders past.
## If she reaches you: hold out a mushroom and she snatches it and leaves you alone for a bit;
## empty-handed, you're dinner. Now and then she calls out in a friend's voice.
## The host moves her; everyone sees the synced transform.

const ModelFit := preload("res://scripts/model_fit.gd")
const Terrain := preload("res://scripts/world/terrain.gd")
const WANDER_SPEED := 2.4
const HUNT_SPEED := 6.4
const HEARING := 140.0
const TORCH_SIGHT := 40.0
const GRAB_RANGE := 1.8
const FED_SECONDS := 75.0

var night := false  # every peer, set by the level
var active := false  # synced: is she out?
var state := "hidden"  # synced: hidden / wander / hunt / fed (for looks)
var _target := Vector3.ZERO
var _rng := RandomNumberGenerator.new()
var _fed_until := 0.0
var _mimic_in := 30.0
var _lair := Vector3.ZERO
var _breath: AudioStreamPlayer3D
var _laughed := false


func build(model_path: String, seed_value: int) -> void:
	_rng.seed = seed_value
	_lair = Terrain.place_centre("witch") + Vector3(-60, 0, 40)
	_lair.y = Terrain.height(_lair.x, _lair.z)
	position = _lair
	var model := ModelFit.fit(model_path, Vector3(1.2, 2.5, 1.2), 0.0)
	model.position.y += 1.25
	add_child(model)
	# She's darker and greyer than any friendly witch.
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		mi.material_overlay = _overlay()
	var eyes := OmniLight3D.new()
	eyes.light_color = Color(1.0, 0.25, 0.1)
	eyes.light_energy = 1.2
	eyes.omni_range = 3.0
	eyes.position = Vector3(0, 2.2, 0.3)
	add_child(eyes)
	var sync := MultiplayerSynchronizer.new()
	sync.name = "Sync"
	var config := SceneReplicationConfig.new()
	for p in [NodePath(".:position"), NodePath(".:rotation"), NodePath(".:active"), NodePath(".:state")]:
		config.add_property(p)
	sync.replication_config = config
	add_child(sync)
	visible = false


func _ready() -> void:
	_breath = Sfx.loop("hag_breath", self) if Sfx.has_method("loop") else null


func server_reset() -> void:
	position = _lair
	active = false
	state = "hidden"
	_fed_until = 0.0


func _overlay() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.05, 0.08, 0.04, 0.45)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return mat


func _process(_delta: float) -> void:
	visible = active
	if _breath:
		if active and not _breath.playing:
			_breath.play()
		elif not active and _breath.playing:
			_breath.stop()


func _physics_process(delta: float) -> void:
	if not multiplayer.is_server():
		return
	if not night:
		if active:
			server_reset()
		return
	if not active:
		active = true
		state = "wander"
		position = _lair
		Team.tell(0, "Somewhere in the forest, something starts to hum a lullaby.")
	var now := Time.get_ticks_msec() / 1000.0
	var speed := WANDER_SPEED
	var prey := _find_prey()
	if now < _fed_until:
		state = "fed"
		prey = null
	if prey:
		state = "hunt"
		_target = prey.global_position
		speed = HUNT_SPEED
		if not _laughed:
			_laughed = true
			Sfx.play_all("hag_laugh", global_position)
		if global_position.distance_to(prey.global_position) < GRAB_RANGE:
			_grab(prey)
	else:
		_laughed = false
		var heard := Hearing.loudest_heard(global_position, HEARING)
		if not heard.is_empty():
			state = "hunt"
			_target = heard["pos"]
			speed = HUNT_SPEED * 0.85
		else:
			state = "wander" if now >= _fed_until else "fed"
			if global_position.distance_to(_target) < 2.0:
				_target = _wander_spot()
	var flat := Vector3(_target.x - position.x, 0, _target.z - position.z)
	if flat.length() > 0.3:
		var step := flat.normalized() * minf(speed * delta, flat.length())
		position += step
		rotation.y = atan2(step.x, step.z)
	position.y = Terrain.height(position.x, position.z)
	_mimic(delta)


## Somebody she can see (a torch) or is right on top of.
func _find_prey() -> Node3D:
	var best: Node3D = null
	var best_d := INF
	for p in get_tree().get_nodes_in_group("players"):
		if not Team.is_alive(p.peer_id) or p.in_car():
			continue
		var d := global_position.distance_to(p.global_position)
		var sees: bool = d < 6.0 or (p.flashlight_on and d < TORCH_SIGHT)
		if sees and d < best_d:
			best = p
			best_d = d
	return best


func _grab(p: Node3D) -> void:
	var held = p.held()
	if held != null and held.has_method("request_taste") and not held.removed:
		held.remove_from_play()
		_fed_until = Time.get_ticks_msec() / 1000.0 + FED_SECONDS
		_target = _wander_spot()
		Sfx.play_all("hag_laugh", global_position)
		Team.tell(0, "The Hag snatches the mushroom out of %s's hand, sniffs it, and shuffles away... for now." %
			Team.players[p.peer_id]["name"])
		Team.highlight("%s bribes the Hag with a mushroom" % Team.players[p.peer_id]["name"])
	else:
		Sfx.play_all("hag_scream", global_position)
		Team.kill(p.peer_id, "the Hungry Hag (should've had a mushroom)")
		_fed_until = Time.get_ticks_msec() / 1000.0 + 20.0


## Every so often, call out to someone in a friend's voice, from wherever she is.
func _mimic(delta: float) -> void:
	_mimic_in -= delta
	if _mimic_in > 0.0:
		return
	_mimic_in = _rng.randf_range(35.0, 80.0)
	var ids := Team.players.keys().filter(func(id): return Team.is_alive(id))
	if ids.is_empty():
		return
	var near := false
	for p in get_tree().get_nodes_in_group("players"):
		if global_position.distance_to(p.global_position) < 70.0:
			near = true
	if near and Voice.has_method("mimic_all"):
		Voice.mimic_all.rpc(ids[_rng.randi() % ids.size()], global_position + Vector3(0, 1.6, 0))


func _wander_spot() -> Vector3:
	# Drift towards the friends' side of the forest, so she isn't stuck in a corner.
	var anchor := Vector3.ZERO
	var players := get_tree().get_nodes_in_group("players")
	if not players.is_empty() and _rng.randf() < 0.6:
		anchor = players[_rng.randi() % players.size()].global_position
	return anchor + Vector3(_rng.randf_range(-60, 60), 0, _rng.randf_range(-60, 60))
