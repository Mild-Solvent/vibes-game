extends "res://scripts/locations/graph_walker.gd"
## A crypt skeleton. It sleeps in its niche until someone takes a Bone morel off the saint's
## coffin. Then it hunts the nearest living friend, but only moves while nobody (within 25 m,
## with a clear line of sight) is looking at it. Look away, blink, turn to run... and it's there.
## A touch kills. The host runs it; everyone sees the synced transform.

const SPEED := 5.0
const WATCH_RANGE := 25.0
const WATCH_DOT := 0.6
const TOUCH := 0.8
const HUNT_RANGE := 40.0

var awake := false  # synced
var _niche := Vector3.ZERO
var _niche_yaw := 0.0
var _repath := 0.0
var _eyes: Array[MeshInstance3D] = []


func build(node_name: String, model_path: String, niche: Vector3, yaw: float) -> void:
	name = node_name
	_niche = niche
	_niche_yaw = yaw
	position = niche
	rotation.y = yaw
	var model := ModelFit.fit(model_path, Vector3(3.0, 1.85, 3.0), 0.0)
	model.position.y += 1.85 / 2.0
	set_model(model)
	var eye_mat := StandardMaterial3D.new()
	eye_mat.albedo_color = Color(1.0, 0.1, 0.05)
	eye_mat.emission_enabled = true
	eye_mat.emission = Color(1.0, 0.1, 0.05)
	eye_mat.emission_energy_multiplier = 4.0
	for x in [-0.12, 0.12]:
		var eye := MeshInstance3D.new()
		var mesh := SphereMesh.new()
		mesh.radius = 0.045
		mesh.height = 0.09
		eye.mesh = mesh
		eye.material_override = eye_mat
		eye.position = Vector3(x, 1.5, 0.27)
		eye.visible = false
		add_child(eye)
		_eyes.append(eye)
	var sync := MultiplayerSynchronizer.new()
	sync.name = "Sync"
	var config := SceneReplicationConfig.new()
	for path in [NodePath(".:position"), NodePath(".:rotation"), NodePath(".:moving"), NodePath(".:awake")]:
		config.add_property(path)
	sync.replication_config = config
	add_child(sync)


## Host: back in its niche, asleep.
func reset() -> void:
	stop()
	awake = false
	position = _niche
	rotation.y = _niche_yaw


func wake() -> void:
	awake = true


func _process(delta: float) -> void:
	super._process(delta)
	for eye in _eyes:
		eye.visible = awake
	# Frozen mid-step while watched: the animation stops with it.
	if _anim:
		_anim.speed_scale = 1.0 if moving or not awake else 0.0


func _physics_process(delta: float) -> void:
	if not multiplayer.is_server() or not awake or graph == null:
		return
	var prey := _nearest_prey()
	if prey == null:
		moving = false
		return
	if _watched():
		moving = false
		return
	_repath -= delta
	if _repath <= 0.0 or not has_goal():
		_repath = 0.4
		go_to((get_parent() as Node3D).to_local(prey.global_position), true)
	walk(delta, SPEED)
	fast = false
	var d: Vector3 = prey.global_position - global_position
	if absf(d.y) < 1.6 and Vector2(d.x, d.z).length() < TOUCH:
		Team.kill(prey.peer_id, "a skeleton. Somebody blinked.")
		Sfx.play_all("scream", prey.global_position)


func _nearest_prey() -> Node3D:
	var best: Node3D = null
	var best_d := HUNT_RANGE
	for p in get_tree().get_nodes_in_group("players"):
		if not Team.is_alive(p.peer_id) or p.in_car():
			continue
		var d := global_position.distance_to(p.global_position)
		if d < best_d:
			best = p
			best_d = d
	return best


## Is any living friend looking at it, with nothing in between?
func _watched() -> bool:
	var chest := global_position + Vector3(0, 1.2, 0)
	var space := get_world_3d().direct_space_state
	var exclude: Array[RID] = []
	for p in get_tree().get_nodes_in_group("players"):
		exclude.append(p.get_rid())
	for p in get_tree().get_nodes_in_group("props"):
		exclude.append(p.get_rid())
	for p in get_tree().get_nodes_in_group("players"):
		if not Team.is_alive(p.peer_id) or p.in_car():
			continue
		var eye: Vector3 = p.head.global_position
		var to_me := chest - eye
		if to_me.length() > WATCH_RANGE:
			continue
		var look: Vector3 = -p.head.global_basis.z
		if look.dot(to_me.normalized()) < WATCH_DOT:
			continue
		var ray := PhysicsRayQueryParameters3D.create(eye, chest)
		ray.exclude = exclude
		if space.intersect_ray(ray).is_empty():
			return true
	return false
