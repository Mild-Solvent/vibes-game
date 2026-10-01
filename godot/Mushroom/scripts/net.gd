extends Node
## Autoload "Net": hosting/joining over ENet and the player roster.
## Peer 1 (the host) is the authority for spawning, props and the show.

signal player_joined(peer_id: int, player_name: String)
signal player_left(peer_id: int)
signal status_changed(text: String)

const DEFAULT_PORT := 7777
const MAX_PLAYERS := 8
## Sync rates. A synchronizer left at its default sends every frame (60-140 a second); with ~480 of
## them that was ~2 Mbit/s from the host even standing still, enough to clog a home upload and push
## the ping (and voice) to 300+ ms. Players move smoothly at 30 Hz, everything else is fine at 20.
const PLAYER_SYNC_HZ := 30.0
const OTHER_SYNC_HZ := 20.0

var player_name := "Crew"
var port := DEFAULT_PORT  # --port=N on the command line changes it (handy for testing)


func _ready() -> void:
	_setup_input()
	status_changed.connect(func(text): print("[net] ", text))
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	get_tree().node_added.connect(_tune_sync)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


func host() -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, MAX_PLAYERS)
	if err != OK:
		status_changed.emit("Could not host on port %d (error %d)" % [port, err])
		return err
	peer.host.compress(ENetConnection.COMPRESS_RANGE_CODER)
	multiplayer.multiplayer_peer = peer
	status_changed.emit("Hosting on port %d" % port)
	player_joined.emit(1, player_name)
	return OK


func join(address: String) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, port)
	if err != OK:
		status_changed.emit("Could not connect (error %d)" % err)
		return err
	peer.host.compress(ENetConnection.COMPRESS_RANGE_CODER)  # must match the host
	multiplayer.multiplayer_peer = peer
	status_changed.emit("Connecting to %s:%d..." % [address, port])
	return OK


func leave() -> void:
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()


func is_online() -> bool:
	return not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer)


func _on_connected_to_server() -> void:
	status_changed.emit("Connected")
	_register.rpc_id(1, player_name)


func _on_connection_failed() -> void:
	leave()
	status_changed.emit("Connection failed")


func _on_server_disconnected() -> void:
	leave()
	get_tree().reload_current_scene()


func _on_peer_disconnected(peer_id: int) -> void:
	if multiplayer.is_server():
		player_left.emit(peer_id)


## Clients announce themselves to the host once connected.
@rpc("any_peer", "reliable")
func _register(requested_name: String) -> void:
	if not multiplayer.is_server():
		return
	var clean := requested_name.strip_edges().substr(0, 20)
	if clean.is_empty():
		clean = "Crew"
	player_joined.emit(multiplayer.get_remote_sender_id(), clean)


func _setup_input() -> void:
	_bind_keys("move_forward", [KEY_W, KEY_UP])
	_bind_keys("move_back", [KEY_S, KEY_DOWN])
	_bind_keys("move_left", [KEY_A, KEY_LEFT])
	_bind_keys("move_right", [KEY_D, KEY_RIGHT])
	_bind_keys("jump", [KEY_SPACE])
	_bind_keys("sprint", [KEY_SHIFT])
	_bind_keys("grab", [KEY_E])
	_bind_mouse("grab", MOUSE_BUTTON_LEFT)
	_bind_keys("throw", [KEY_Q])
	_bind_mouse("inspect", MOUSE_BUTTON_RIGHT)
	_bind_keys("taste", [KEY_F])
	_bind_keys("flashlight", [KEY_T])
	_bind_keys("medkit", [KEY_H])
	_bind_keys("journal", [KEY_J, KEY_TAB])
	_bind_keys("use_item", [KEY_G])
	_bind_keys("whistle", [KEY_B])
	_bind_keys("spin", [KEY_R])
	_bind_mouse("spin", MOUSE_BUTTON_WHEEL_UP)
	_bind_mouse("spin_back", MOUSE_BUTTON_WHEEL_DOWN)


func _ensure_action(action: String) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)


func _bind_keys(action: String, keys: Array) -> void:
	_ensure_action(action)
	for key in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = key
		InputMap.action_add_event(action, ev)


func _bind_mouse(action: String, button: MouseButton) -> void:
	_ensure_action(action)
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	InputMap.action_add_event(action, ev)


## Every MultiplayerSynchronizer anywhere gets a sane send rate (see PLAYER_SYNC_HZ).
func _tune_sync(node: Node) -> void:
	if not node is MultiplayerSynchronizer:
		return
	var sync := node as MultiplayerSynchronizer
	if sync.replication_interval > 0.0:
		return  # someone chose a rate on purpose
	var parent := sync.get_parent()
	var hz := PLAYER_SYNC_HZ if parent != null and parent.is_in_group("players") else OTHER_SYNC_HZ
	sync.replication_interval = 1.0 / hz
	sync.delta_interval = 1.0 / hz


## Bytes per second in and out over the last call (for the F3 overlay); call about once a second.
var _bw_t := 0.0
var _bw := Vector2.ZERO


func bandwidth() -> Vector2:
	var mp := multiplayer.multiplayer_peer
	if not mp is ENetMultiplayerPeer or (mp as ENetMultiplayerPeer).host == null:
		return Vector2.ZERO
	var now := Time.get_ticks_msec() / 1000.0
	if now - _bw_t >= 1.0:
		var host := (mp as ENetMultiplayerPeer).host
		var dt := maxf(now - _bw_t, 0.001)
		_bw = Vector2(host.pop_statistic(ENetConnection.HOST_TOTAL_SENT_DATA),
			host.pop_statistic(ENetConnection.HOST_TOTAL_RECEIVED_DATA)) / dt
		_bw_t = now
	return _bw
