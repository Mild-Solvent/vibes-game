extends Node3D
## A harmless forest animal (deer, bunny, fox) that potters about near home and bolts when a
## person gets close. Pure scenery: each peer moves its own copy, so they aren't synced.

const Terrain := preload("res://scripts/world/terrain.gd")
const SCARE_DISTANCE := 11.0

var speed := 1.5
var _home := Vector3.ZERO
var _target := Vector3.ZERO
var _rest := 0.0
var _fleeing := 0.0
var _rng := RandomNumberGenerator.new()
var _look_timer := 0.0


func setup(model: Node3D, home: Vector3, move_speed: float, seed_value: int) -> void:
	add_child(model)
	_home = home
	_target = home
	position = home
	speed = move_speed
	_rng.seed = seed_value


func _process(delta: float) -> void:
	_look_timer -= delta
	if _look_timer <= 0.0:
		_look_timer = 0.3
		_check_scared()
	if _fleeing > 0.0:
		_fleeing -= delta
	elif _rest > 0.0:
		_rest -= delta
		return
	var flat := Vector3(_target.x - position.x, 0, _target.z - position.z)
	if flat.length() < 0.3:
		_rest = _rng.randf_range(1.0, 6.0)
		_target = _home + Vector3(_rng.randf_range(-15, 15), 0, _rng.randf_range(-15, 15))
		return
	var run := speed * (3.0 if _fleeing > 0.0 else 1.0)
	var step := flat.normalized() * minf(run * delta, flat.length())
	position += step
	rotation.y = atan2(step.x, step.z)  # the cube pets face +Z
	position.y = Terrain.height(position.x, position.z)


## Somebody close? Run the other way.
func _check_scared() -> void:
	for p in get_tree().get_nodes_in_group("players"):
		var away: Vector3 = global_position - p.global_position
		away.y = 0.0
		if away.length() < SCARE_DISTANCE:
			_fleeing = 3.0
			_rest = 0.0
			_target = global_position + away.normalized() * 18.0
			return
