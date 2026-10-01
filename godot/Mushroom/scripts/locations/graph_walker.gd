extends Node3D
## Something that walks a waypoint graph (an AStar3D in its parent's space): the Nurse, the crypt
## skeletons. The host moves it; every peer sees the synced transform and plays the animation.
## The last leg to an off-graph target is walked straight, but only with a clear line to it.

const ModelFit := preload("res://scripts/model_fit.gd")

var graph: AStar3D
var moving := false  # synced: walking or not
var fast := false  # synced: running or not
var _path: PackedVector3Array = PackedVector3Array()
var _final := Vector3.INF
var _anim: AnimationPlayer
var _anim_now := ""


## Puts a mini-character style model under this node (feet at 0, facing +Z of the walker).
func set_model(model: Node3D) -> void:
	add_child(model)
	var players := model.find_children("*", "AnimationPlayer", true, false)
	if not players.is_empty():
		_anim = players[0]
		for anim_name in ["idle", "walk", "sprint"]:
			if _anim.has_animation(anim_name):
				_anim.get_animation(anim_name).loop_mode = Animation.LOOP_LINEAR
		_play("idle")


## Host: head for `target` (parent space) along the graph, then straight to it if `direct`.
func go_to(target: Vector3, direct := true) -> void:
	if graph == null or graph.get_point_count() == 0:
		return
	var from := graph.get_closest_point(position)
	var to := graph.get_closest_point(target)
	_path = graph.get_point_path(from, to)
	var end := graph.get_point_position(to)
	_final = Vector3(target.x, end.y, target.z) if direct else Vector3.INF


func stop() -> void:
	_path = PackedVector3Array()
	_final = Vector3.INF
	moving = false


func has_goal() -> bool:
	return not _path.is_empty() or _final != Vector3.INF


## Host: walk along. Returns true once there's nowhere left to go.
func walk(delta: float, speed: float) -> bool:
	var budget := speed * delta
	while budget > 0.0001:
		var goal := Vector3.INF
		if not _path.is_empty():
			goal = _path[0]
		elif _final != Vector3.INF:
			if not _clear_line(position, _final):
				_final = Vector3.INF
				break
			goal = _final
		if goal == Vector3.INF:
			break
		var to_goal := goal - position
		var dist := to_goal.length()
		if dist <= budget:
			position = goal
			budget -= dist
			if not _path.is_empty():
				_path.remove_at(0)
			else:
				_final = Vector3.INF
		else:
			position += to_goal / dist * budget
			budget = 0.0
		var flat := Vector2(to_goal.x, to_goal.z)
		if flat.length() > 0.01:
			rotation.y = lerp_angle(rotation.y, atan2(to_goal.x, to_goal.z), 0.35)
	moving = has_goal()
	fast = moving and speed > 3.0
	return not has_goal()


## Host: nothing solid (walls, doors) between two points in parent space? Players don't count.
func _clear_line(a: Vector3, b: Vector3) -> bool:
	var parent := get_parent() as Node3D
	var from := parent.to_global(a + Vector3(0, 1.2, 0))
	var to := parent.to_global(b + Vector3(0, 1.2, 0))
	var query := PhysicsRayQueryParameters3D.create(from, to)
	var exclude: Array[RID] = []
	for p in get_tree().get_nodes_in_group("players"):
		exclude.append(p.get_rid())
	for p in get_tree().get_nodes_in_group("props"):
		exclude.append(p.get_rid())
	query.exclude = exclude
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()


func _process(_delta: float) -> void:
	if moving:
		_play("sprint" if fast else "walk")
	else:
		_play("idle")


func _play(anim_name: String) -> void:
	if _anim == null or _anim_now == anim_name or not _anim.has_animation(anim_name):
		return
	_anim_now = anim_name
	_anim.play(anim_name)


## Every material on the model swapped for one (a pale nurse, a ghost).
static func tint(model: Node, mat: Material) -> void:
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).material_override = mat
