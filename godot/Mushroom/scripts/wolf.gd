extends Node3D
## A wolf. Asleep (out of sight) by day; at night it roams near its den, hears noise, sees
## torches, and runs down whoever it notices. Two bites and you're done. Wolves won't come into
## the camp once you've built the house, and they never go near the camp fire.
## The host moves it; everyone sees the synced transform and animation.

const ModelFit := preload("res://scripts/model_fit.gd")
const Terrain := preload("res://scripts/world/terrain.gd")
const WALK_SPEED := 2.2
const RUN_SPEED := 7.0  # a sprinting friend (7.5) can just about get away
const SIGHT := 26.0
const TORCH_SIGHT := 45.0
const BITE_RANGE := 1.4
const BITE_EVERY := 1.6

var night := false  # every peer, set by the level
var anim_state := "Idle"  # synced, so everyone sees it run
var _home := Vector3.ZERO
var _target := Vector3.ZERO
var _rng := RandomNumberGenerator.new()
var _bite_cooldown := 0.0
var _bites := {}  # host: peer id -> msec of their last bite
var _anim: AnimationPlayer
var _howled := false


func build(model_path: String, home: Vector3, seed_value: int) -> void:
	_home = home
	position = home
	_target = home
	_rng.seed = seed_value
	var model := ModelFit.fit(model_path, Vector3(0.7, 1.0, 1.6), 0.0)
	model.position.y += 0.5
	add_child(model)
	var players := model.find_children("*", "AnimationPlayer", true, false)
	if not players.is_empty():
		_anim = players[0]
		for a in ["Idle", "Walk", "Gallop", "Attack"]:
			if _anim.has_animation(a):
				_anim.get_animation(a).loop_mode = Animation.LOOP_LINEAR
	var sync := MultiplayerSynchronizer.new()
	sync.name = "Sync"
	var config := SceneReplicationConfig.new()
	for p in [NodePath(".:position"), NodePath(".:rotation"), NodePath(".:anim_state")]:
		config.add_property(p)
	sync.replication_config = config
	add_child(sync)
	visible = false


func _process(_delta: float) -> void:
	visible = night
	if _anim and _anim.current_animation != anim_state and _anim.has_animation(anim_state):
		_anim.play(anim_state, 0.2)


func _physics_process(delta: float) -> void:
	if not multiplayer.is_server():
		return
	if not night:
		position = _home
		_howled = false
		return
	if not _howled:
		_howled = true
		if _rng.randf() < 0.4:
			Sfx.play_all("wolf_howl", global_position)
	_bite_cooldown -= delta
	var prey: Node3D = _find_prey()
	var speed := WALK_SPEED
	anim_state = "Walk"
	if prey:
		_target = prey.global_position
		speed = RUN_SPEED
		anim_state = "Gallop"
		var d := global_position.distance_to(prey.global_position)
		if d < BITE_RANGE and _bite_cooldown <= 0.0:
			_bite_cooldown = BITE_EVERY
			anim_state = "Attack"
			_bite(prey.peer_id)
	else:
		var heard := Hearing.loudest_heard(global_position, 70.0)
		if not heard.is_empty():
			_target = heard["pos"]
			speed = RUN_SPEED * 0.7
			anim_state = "Gallop"
		elif global_position.distance_to(_target) < 1.5:
			_target = _home + Vector3(_rng.randf_range(-30, 30), 0, _rng.randf_range(-30, 30))
	_target = _keep_out_of_camp(_target)
	var flat := Vector3(_target.x - position.x, 0, _target.z - position.z)
	if flat.length() > 0.3:
		var step := flat.normalized() * minf(speed * delta, flat.length())
		position += step
		rotation.y = atan2(step.x, step.z)
	else:
		anim_state = "Idle"
	position.y = Terrain.height(position.x, position.z)


func _bite(peer_id: int) -> void:
	var now := Time.get_ticks_msec()
	Sfx.play_all("wolf_growl", global_position)
	if _bites.has(peer_id) and now - _bites[peer_id] < 12000:
		_bites.erase(peer_id)
		Team.kill(peer_id, "wolves")
	else:
		_bites[peer_id] = now
		Team.tell(peer_id, "A WOLF BIT YOU! Run! One more and you're dinner.")


func _find_prey() -> Node3D:
	var best: Node3D = null
	var best_d := INF
	for p in get_tree().get_nodes_in_group("players"):
		if not Team.is_alive(p.peer_id) or p.in_car() or _safe_at_camp(p.global_position):
			continue
		var d := global_position.distance_to(p.global_position)
		var reach := TORCH_SIGHT if p.flashlight_on else SIGHT
		if d < reach and d < best_d:
			best = p
			best_d = d
	return best


func _safe_at_camp(pos: Vector3) -> bool:
	var r := 22.0 if Team.house else 9.0  # the camp fire keeps them off; a house keeps them out
	return Vector2(pos.x, pos.z).length() < r


func _keep_out_of_camp(t: Vector3) -> Vector3:
	var flat := Vector2(t.x, t.z)
	var r := 24.0 if Team.house else 11.0
	if flat.length() < r:
		flat = flat.normalized() * r
	return Vector3(flat.x, t.y, flat.y)
