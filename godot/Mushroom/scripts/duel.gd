extends Node
## Force-feeding: hold a mushroom, look at a friend, spam T. They spam T to keep their mouth shut.
## A meter swings towards whoever's mashing faster. Feeder wins: the friend eats it. Friend wins:
## the mushroom goes flying. Lives at the same path on every peer; the host referees.

const WIN_SCORE := 14
const MAX_SECONDS := 7.0

var feeder := 0
var victim := 0
var running := false
var _score := 0
var _mushroom: Node = null
var _ends_at := 0.0


func involves(peer_id: int) -> bool:
	return running and (peer_id == feeder or peer_id == victim)


@rpc("any_peer", "call_local", "reliable")
func request_start(victim_id: int, mushroom_path: NodePath) -> void:
	if not multiplayer.is_server() or running:
		return
	var sender := _sender()
	var m := get_node_or_null(mushroom_path)
	if m == null or m.holder_id != sender or not m.has_method("request_taste"):
		return
	if not Team.is_alive(sender) or not Team.is_alive(victim_id) or victim_id == sender:
		return
	feeder = sender
	victim = victim_id
	_mushroom = m
	_score = 0
	running = true
	_ends_at = Time.get_ticks_msec() / 1000.0 + MAX_SECONDS
	Team.tell(0, "%s is trying to FORCE-FEED %s a mushroom! Spam T!" % [_name(feeder), _name(victim)])
	_state.rpc(feeder, victim, 0.0, true)


@rpc("any_peer", "call_local", "unreliable_ordered")
func press() -> void:
	if not multiplayer.is_server() or not running:
		return
	var sender := _sender()
	if sender == feeder:
		_score += 1
	elif sender == victim:
		_score -= 1
	else:
		return
	_state.rpc(feeder, victim, clampf(float(_score) / WIN_SCORE, -1.0, 1.0), true)
	if absi(_score) >= WIN_SCORE:
		_finish()


func _process(_delta: float) -> void:
	if running and multiplayer.is_server() and Time.get_ticks_msec() / 1000.0 > _ends_at:
		_finish()


func _finish() -> void:
	running = false
	var m := _mushroom
	_mushroom = null
	_state.rpc(feeder, victim, 0.0, false)
	if m == null or m.removed:
		return
	if _score > 0:
		m.remove_from_play()
		Sfx.play_all("eat", m.global_position)
		Team.apply_mushroom(victim, m.effect, m.display_name)
		Team.tell(0, "%s shoved the mushroom into %s's mouth. Gulp." % [_name(feeder), _name(victim)])
	else:
		m._drop()
		m.linear_velocity = Vector3(randf_range(-6, 6), 5, randf_range(-6, 6))
		Team.tell(0, "%s slapped the mushroom away! It flies into the bushes." % _name(victim))


## Every peer: show the tug-of-war meter to the two people in it.
@rpc("authority", "call_local", "reliable")
func _state(feeder_id: int, victim_id: int, meter: float, is_running: bool) -> void:
	feeder = feeder_id
	victim = victim_id
	running = is_running
	var me := multiplayer.get_unique_id()
	if me == feeder_id or me == victim_id:
		get_tree().call_group("hud", "show_duel", is_running, meter, me == feeder_id)


func _name(peer_id: int) -> String:
	return Team.players.get(peer_id, {}).get("name", "someone")


func _sender() -> int:
	var id := multiplayer.get_remote_sender_id()
	return id if id != 0 else multiplayer.get_unique_id()
