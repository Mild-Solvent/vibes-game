extends Node
## Runs the show on the host: PREP -> LIVE -> WRAP, and the ratings meter.
## Clients only receive the state through _push().
##
## Scoring (first pass of the GDD's "audience" system):
## - nobody at the anchor desk while LIVE  -> dead air, ratings drain
## - crew visible to the on-air camera     -> ratings drain per person
## - exactly one anchor and a clean shot   -> ratings slowly climb

signal changed

enum Phase { PREP, LIVE, WRAP }
enum Event { NONE, DEAD_AIR, CREW_IN_SHOT }

const PREP_TIME := 20.0
const LIVE_TIME := 180.0
const WRAP_TIME := 12.0
const PUSH_INTERVAL := 0.15

## Where the anchor stands, behind the news desk (player feet positions).
const DESK_ZONE := AABB(Vector3(-1.5, -1.0, -6.4), Vector3(3.0, 4.0, 1.8))

var running := false
var phase: int = Phase.PREP
var time_left := PREP_TIME
var ratings := 50.0
var event: int = Event.NONE
var on_air_camera: Camera3D

var _push_timer := 0.0


func _process(delta: float) -> void:
	if not running or not multiplayer.is_server():
		return
	time_left -= delta
	match phase:
		Phase.PREP:
			event = Event.NONE
			if time_left <= 0.0:
				_enter(Phase.LIVE, LIVE_TIME)
		Phase.LIVE:
			_score(delta)
			if time_left <= 0.0:
				_enter(Phase.WRAP, WRAP_TIME)
		Phase.WRAP:
			event = Event.NONE
			if time_left <= 0.0:
				ratings = 50.0
				_enter(Phase.PREP, PREP_TIME)

	_push_timer -= delta
	if _push_timer <= 0.0:
		_push_timer = PUSH_INTERVAL
		_push.rpc(phase, time_left, ratings, event)


func _enter(next_phase: int, duration: float) -> void:
	phase = next_phase
	time_left = duration
	_push_timer = 0.0


func _score(delta: float) -> void:
	var anchors := 0
	var crew_in_shot := 0
	for player in get_tree().get_nodes_in_group("players"):
		var feet: Vector3 = player.global_position
		if DESK_ZONE.has_point(feet):
			anchors += 1
		elif _in_shot(feet):
			crew_in_shot += 1

	var extra := crew_in_shot + maxi(anchors - 1, 0)
	if anchors == 0:
		event = Event.DEAD_AIR
		ratings -= 3.0 * delta
	elif extra > 0:
		event = Event.CREW_IN_SHOT
		ratings -= 4.0 * delta * extra
	else:
		event = Event.NONE
		ratings += 1.0 * delta
	ratings = clampf(ratings, 0.0, 100.0)


func _in_shot(feet: Vector3) -> bool:
	if on_air_camera == null:
		return false
	var chest := feet + Vector3.UP
	return on_air_camera.is_position_in_frustum(chest) and on_air_camera.global_position.distance_to(chest) < 14.0


@rpc("authority", "call_local", "unreliable_ordered")
func _push(new_phase: int, new_time_left: float, new_ratings: float, new_event: int) -> void:
	phase = new_phase
	time_left = new_time_left
	ratings = new_ratings
	event = new_event
	changed.emit()
