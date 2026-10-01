extends "res://scripts/locations/graph_walker.gd"
## The Nurse of Sanatórium Hôrka. Blind: she hunts only by sound (the Hearing autoload). She shuffles
## her rounds slowly; anything she hears, she runs to, faster than you walk. Stand still and keep
## quiet and she passes right by. If she touches you, that's it. The host runs her.

const PATROL_SPEED := 1.3
const CHASE_SPEED := 5.4
const CHASE_SPEED_NIGHT := 6.1
const HEAR_RANGE := 45.0
const TOUCH := 0.85
const MIN_LOUD := 3.0

var night := false
var chasing := false  # synced, for the looks
var _state := 0  # 0 patrol, 1 chase, 2 listen
var _listen := 0.0
var _hear_timer := 0.0
var _last_heard := 0.0
var _scream_cd := 0.0
var _rng := RandomNumberGenerator.new()
var _home := Vector3.ZERO


func build(model_path: String, home: Vector3, seed_value: int) -> void:
	name = "Nurse"
	_home = home
	position = home
	_rng.seed = seed_value
	# Wide box so her height decides the scale: she's a head taller than anybody.
	var model := ModelFit.fit(model_path, Vector3(4.0, 2.1, 4.0), 0.0)
	model.position.y += 2.1 / 2.0
	var pale := StandardMaterial3D.new()
	pale.albedo_color = Color(0.82, 0.84, 0.8)
	pale.emission_enabled = true
	pale.emission = Color(0.55, 0.6, 0.58)
	pale.emission_energy_multiplier = 0.12
	pale.roughness = 1.0
	tint(model, pale)
	set_model(model)
	# Her cap with the red cross, and the bandage over her eyes.
	var cap := MeshInstance3D.new()
	var cap_mesh := BoxMesh.new()
	cap_mesh.size = Vector3(0.62, 0.2, 0.42)
	cap.mesh = cap_mesh
	cap.material_override = pale
	cap.position = Vector3(0, 2.12, 0.05)
	add_child(cap)
	var cross := Label3D.new()
	cross.text = "+"
	cross.font_size = 96
	cross.pixel_size = 0.004
	cross.modulate = Color(0.6, 0.05, 0.05)
	cross.position = Vector3(0, 2.12, 0.27)
	cross.shaded = true
	add_child(cross)
	var band := MeshInstance3D.new()
	var band_mesh := BoxMesh.new()
	band_mesh.size = Vector3(1.02, 0.13, 0.9)
	band.mesh = band_mesh
	var band_mat := StandardMaterial3D.new()
	band_mat.albedo_color = Color(0.35, 0.03, 0.03)
	band.material_override = band_mat
	band.position = Vector3(0, 1.66, 0.0)
	add_child(band)
	_add_sync()
	_play("idle")


func _add_sync() -> void:
	var sync := MultiplayerSynchronizer.new()
	sync.name = "Sync"
	var config := SceneReplicationConfig.new()
	for path in [NodePath(".:position"), NodePath(".:rotation"), NodePath(".:moving"), NodePath(".:fast")]:
		config.add_property(path)
	sync.replication_config = config
	add_child(sync)


## Host: back to her station, calm, for a new day.
func reset() -> void:
	stop()
	position = _home
	_state = 0
	chasing = false
	_listen = 3.0


## Host: something loud happened at `local_pos` (parent space) that she must come and see.
func alert(local_pos: Vector3) -> void:
	_chase(local_pos)


func _physics_process(delta: float) -> void:
	if not multiplayer.is_server() or graph == null:
		return
	_scream_cd -= delta
	_hear_timer -= delta
	if _hear_timer <= 0.0:
		_hear_timer = 0.2
		_listen_for_noise()
	match _state:
		1:
			if walk(delta, CHASE_SPEED_NIGHT if night else CHASE_SPEED):
				_state = 2
				_listen = _rng.randf_range(2.5, 5.0)
		2:
			moving = false
			_listen -= delta
			if _listen <= 0.0:
				_state = 0
				chasing = false
		_:
			if walk(delta, PATROL_SPEED):
				var ids := graph.get_point_ids()
				go_to(graph.get_point_position(ids[_rng.randi() % ids.size()]), false)
	_touch()


func _listen_for_noise() -> void:
	var heard := Hearing.loudest_heard(global_position, HEAR_RANGE * (1.3 if night else 1.0))
	if heard.is_empty() or heard["loud"] < MIN_LOUD or heard["time"] <= _last_heard:
		return
	_last_heard = heard["time"]
	_chase((get_parent() as Node3D).to_local(heard["pos"]))


func _chase(local_pos: Vector3) -> void:
	if _state != 1 and _scream_cd <= 0.0:
		_scream_cd = 8.0
		Sfx.play_all("scream", global_position + Vector3(0, 1.6, 0))
	_state = 1
	chasing = true
	go_to(local_pos, true)


func _touch() -> void:
	for p in get_tree().get_nodes_in_group("players"):
		if not Team.is_alive(p.peer_id) or p.in_car():
			continue
		var d: Vector3 = p.global_position - global_position
		if absf(d.y) < 1.6 and Vector2(d.x, d.z).length() < TOUCH:
			Team.kill(p.peer_id, "the Nurse")
			Sfx.play_all("scream", global_position + Vector3(0, 1.6, 0))
			_state = 2
			_listen = 4.0
			stop()
