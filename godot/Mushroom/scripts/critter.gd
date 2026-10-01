extends Node3D
## A harmless forest animal (deer, bunny, fox) that potters about near home. Pure scenery: each
## peer moves its own copy, so they aren't synced and don't need to be.

const Terrain := preload("res://scripts/world/terrain.gd")

var speed := 1.5
var _home := Vector3.ZERO
var _target := Vector3.ZERO
var _rest := 0.0
var _rng := RandomNumberGenerator.new()


func setup(model: Node3D, home: Vector3, move_speed: float, seed_value: int) -> void:
	add_child(model)
	_home = home
	_target = home
	position = home
	speed = move_speed
	_rng.seed = seed_value


func _process(delta: float) -> void:
	if _rest > 0.0:
		_rest -= delta
		return
	var flat := Vector3(_target.x - position.x, 0, _target.z - position.z)
	if flat.length() < 0.3:
		_rest = _rng.randf_range(1.0, 6.0)
		_target = _home + Vector3(_rng.randf_range(-15, 15), 0, _rng.randf_range(-15, 15))
		return
	var step := flat.normalized() * minf(speed * delta, flat.length())
	position += step
	rotation.y = atan2(step.x, step.z)
	position.y = Terrain.height(position.x, position.z)
