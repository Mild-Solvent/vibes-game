extends Node
## The lobby roster: who is here and who pressed Ready. Lives inside the menu as a node called
## "Lobby", so it sits at the same node path on every peer and can use RPCs.
##
## The host keeps the truth (names come from Net.player_joined, which fires on the host for the host
## itself and for every client that registers) and broadcasts the whole roster whenever it changes.
## Clients only send their own ready flag to the host.

signal roster_changed
signal started  ## everyone: the host pressed Start (also sent to friends who join later)

## Everyone: [{"id": int, "name": String, "ready": bool}], host first, then in join order.
var roster: Array = []
var has_started := false

var _names := {}  # host: peer id -> name, in join order
var _ready_flags := {}  # host: peer id -> bool


func _ready() -> void:
	Net.player_joined.connect(_on_joined)
	Net.player_left.connect(_on_left)
	multiplayer.peer_disconnected.connect(_on_left)
	multiplayer.server_disconnected.connect(clear)


## Forget everything (call when leaving a session).
func clear() -> void:
	roster.clear()
	_names.clear()
	_ready_flags.clear()
	has_started = false
	roster_changed.emit()


## This peer is (not) ready.
func set_ready(on: bool) -> void:
	if not Net.is_online():
		return
	if multiplayer.is_server():
		_apply_ready(1, on)
	else:
		_request_ready.rpc_id(1, on)


func is_ready(peer_id: int) -> bool:
	for p in roster:
		if p["id"] == peer_id:
			return p["ready"]
	return false


func all_ready() -> bool:
	if roster.is_empty():
		return false
	for p in roster:
		if not p["ready"]:
			return false
	return true


func ready_count() -> int:
	var n := 0
	for p in roster:
		if p["ready"]:
			n += 1
	return n


## Host: start the game for everyone in the lobby.
func start() -> void:
	if not multiplayer.is_server():
		return
	has_started = true
	_go.rpc()


func _on_joined(peer_id: int, player_name: String) -> void:
	if not multiplayer.is_server():
		return
	_names[peer_id] = player_name
	_ready_flags[peer_id] = _ready_flags.get(peer_id, false)
	_broadcast()
	if has_started and peer_id != 1:
		_go.rpc_id(peer_id)


func _on_left(peer_id: int) -> void:
	if not multiplayer.is_server() or not _names.has(peer_id):
		return
	_names.erase(peer_id)
	_ready_flags.erase(peer_id)
	_broadcast()


func _apply_ready(peer_id: int, on: bool) -> void:
	if not _names.has(peer_id):
		return
	_ready_flags[peer_id] = on
	_broadcast()


func _broadcast() -> void:
	var list := []
	for id in _names:
		list.append({"id": id, "name": _names[id], "ready": _ready_flags.get(id, false)})
	if Net.is_online():
		_roster.rpc(list)
	else:
		_roster(list)


@rpc("any_peer", "reliable")
func _request_ready(on: bool) -> void:
	if multiplayer.is_server():
		_apply_ready(multiplayer.get_remote_sender_id(), on)


@rpc("authority", "call_local", "reliable")
func _roster(list: Array) -> void:
	roster = list
	roster_changed.emit()


@rpc("authority", "call_local", "reliable")
func _go() -> void:
	has_started = true
	started.emit()
