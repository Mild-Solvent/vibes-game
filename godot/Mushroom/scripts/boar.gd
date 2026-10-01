extends Node3D
## A wild boar. By day it snuffles around its patch; at night it charges the nearest friend in
## range, and if it reaches you, that's it. The host moves it; everyone sees the synced transform.
## A friend inside the camp is safe once the house is built.

const ModelFit := preload("res://scripts/model_fit.gd")
const Terrain := preload("res://scripts/world/terrain.gd")
const WANDER_SPEED := 1.2
const CHARGE_SPEED := 6.2
const SIGHT := 22.0
const BITE := 1.1

var night := false  # set by the level on every peer
var _home := Vector3.ZERO
var _target := Vector3.ZERO
var _rng := RandomNumberGenerator.new()


func build(model_path: String, home: Vector3, seed_value: int) -> void:
	_home = home
	position = home
	_target = home
	_rng.seed = seed_value
	var model := ModelFit.fit(model_path, Vector3(0.9, 0.8, 1.3), PI)
	model.position.y += 0.4
	add_child(model)
	var sync := MultiplayerSynchronizer.new()
	sync.name = "Sync"
	var config := SceneReplicationConfig.new()
	config.add_property(NodePath(".:position"))
	config.add_property(NodePath(".:rotation"))
	sync.replication_config = config
	add_child(sync)


func _physics_process(delta: float) -> void:
	if not multiplayer.is_server():
		return
	var prey: Node3D = _find_prey() if night else null
	var speed := WANDER_SPEED
	if prey:
		_target = prey.global_position
		speed = CHARGE_SPEED
		if global_position.distance_to(prey.global_position) < BITE:
			Team.kill(prey.peer_id, "a wild boar")
			_target = _home
	elif global_position.distance_to(_target) < 1.0:
		_target = _home + Vector3(_rng.randf_range(-12, 12), 0, _rng.randf_range(-12, 12))
	var flat := Vector3(_target.x - position.x, 0, _target.z - position.z)
	if flat.length() > 0.2:
		var step := flat.normalized() * minf(speed * delta, flat.length())
		position += step
		rotation.y = atan2(step.x, step.z)
	position.y = Terrain.height(position.x, position.z)


func _find_prey() -> Node3D:
	var best: Node3D = null
	var best_d := SIGHT
	for p in get_tree().get_nodes_in_group("players"):
		if not Team.is_alive(p.peer_id) or p.in_car():
			continue
		if Team.house and Vector2(p.global_position.x, p.global_position.z).length() < 16.0:
			continue  # safe at camp once there's a house
		var d := global_position.distance_to(p.global_position)
		if d < best_d:
			best = p
			best_d = d
	return best
