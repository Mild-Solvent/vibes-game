extends Node
## Autoload "Net": hosting/joining over ENet and the player roster.
## Peer 1 (the host) is the authority for spawning, props and the show.

signal player_joined(peer_id: int, player_name: String)
signal player_left(peer_id: int)
signal status_changed(text: String)

const DEFAULT_PORT := 7777
const MAX_PLAYERS := 8

var player_name := "Crew"


func _ready() -> void:
	_setup_input()
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


func host(port: int = DEFAULT_PORT) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, MAX_PLAYERS)
	if err != OK:
		status_changed.emit("Could not host on port %d (error %d)" % [port, err])
		return err
	multiplayer.multiplayer_peer = peer
	status_changed.emit("Hosting on port %d" % port)
	player_joined.emit(1, player_name)
	return OK


func join(address: String, port: int = DEFAULT_PORT) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, port)
	if err != OK:
		status_changed.emit("Could not connect (error %d)" % err)
		return err
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
	_bind_mouse("throw", MOUSE_BUTTON_RIGHT)
	_bind_keys("taste", [KEY_F])


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
