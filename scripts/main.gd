extends Node3D
## Bootstraps a session: builds every level, the player spawner, the director and the UI.
##
## All levels exist on every peer at once (far apart), so props and synchronizers always have
## matching node paths. The host picks which level is played; clients learn it from the director.
##
## Quick local testing from the command line (two terminals):
##   godot --path . -- --host --show=2 --name=Adam
##   godot --path . -- --join=127.0.0.1 --name=Denis

const PlayerScript := preload("res://scripts/player.gd")
const DirectorScript := preload("res://scripts/game_director.gd")
const HudScript := preload("res://scripts/hud.gd")
const LEVELS := [
	[preload("res://scripts/levels/studio.gd"), "Studio", Vector3(0, 0, 0)],
	[preload("res://scripts/levels/theatre.gd"), "Theatre", Vector3(400, 0, 0)],
	[preload("res://scripts/levels/forest.gd"), "Forest", Vector3(-400, 0, 0)],
]

const PLAYER_COLORS := [
	Color("e6194b"),
	Color("3cb44b"),
	Color("ffe119"),
	Color("4363d8"),
	Color("f58231"),
	Color("911eb4"),
	Color("46f0f0"),
	Color("f032e6"),
]

var levels: Array = []
var players_root: Node3D
var spawner: MultiplayerSpawner
var director: DirectorScript
var hud: HudScript

var _world_env: WorldEnvironment
var _environments: Array[Environment] = []
var _active_mode := -1
var _joined_count := 0


func _ready() -> void:
	_world_env = WorldEnvironment.new()
	add_child(_world_env)

	var levels_root := Node3D.new()
	levels_root.name = "Levels"
	add_child(levels_root)
	for entry in LEVELS:
		var level: Node3D = entry[0].new()
		level.name = entry[1]
		level.position = entry[2]
		levels_root.add_child(level)
		levels.append(level)
		_environments.append(level.make_environment())

	players_root = Node3D.new()
	players_root.name = "Players"
	add_child(players_root)

	spawner = MultiplayerSpawner.new()
	spawner.name = "PlayerSpawner"
	spawner.spawn_path = NodePath("../Players")
	spawner.spawn_function = _spawn_player
	add_child(spawner)

	director = DirectorScript.new()
	director.name = "Director"
	director.levels = levels
	add_child(director)

	hud = HudScript.new()
	add_child(hud)
	var titles := []
	for level in levels:
		titles.append(level.title())
	hud.set_levels(titles)

	hud.host_pressed.connect(_on_host_pressed)
	hud.join_pressed.connect(_on_join_pressed)
	Net.status_changed.connect(hud.set_status)
	Net.player_joined.connect(_on_player_joined)
	Net.player_left.connect(_on_player_left)
	multiplayer.connected_to_server.connect(hud.show_game)
	director.changed.connect(_on_director_changed)

	_activate(0)
	_handle_command_line()


func _on_host_pressed(player_name: String, mode: int) -> void:
	Net.player_name = player_name
	_activate(mode)
	director.start(mode)
	if Net.host() == OK:
		hud.show_game()
	else:
		director.running = false


func _on_join_pressed(player_name: String, address: String) -> void:
	Net.player_name = player_name
	Net.join(address if not address.is_empty() else "127.0.0.1")


## Host only: someone (including the host) is ready for a body.
func _on_player_joined(peer_id: int, player_name: String) -> void:
	if not multiplayer.is_server():
		return
	var index := _joined_count
	_joined_count += 1
	var level: Node3D = levels[director.mode]
	var spawn_data := {
		"id": peer_id,
		"name": player_name,
		"color": index % PLAYER_COLORS.size(),
		"pos": level.position + level.spawn_point(index),
	}
	spawner.spawn(spawn_data)


func _on_player_left(peer_id: int) -> void:
	var player := players_root.get_node_or_null(str(peer_id))
	if player:
		player.queue_free()


## Runs on every peer (host and clients) with the same data.
func _spawn_player(data: Variant) -> Node:
	var player := PlayerScript.new()
	player.setup(data["id"], data["name"], PLAYER_COLORS[data["color"]])
	player.position = data["pos"]
	return player


func _on_director_changed() -> void:
	_activate(director.mode)
	var level: Node3D = levels[director.mode]
	var secs := maxi(int(ceil(director.time_left)), 0)
	var clock := "%d:%02d" % [secs / 60, secs % 60]
	level.apply_state(director.phase, director.event, director.sub, director.time_left)
	hud.update_state(
		level.phase_text(director.phase, clock, director.score, director.sub),
		level.score_name(),
		director.score,
		level.event_text(director.event),
		level.guide_text()
	)


## Switch lighting, fog and the menu camera to the given level on this peer.
func _activate(mode: int) -> void:
	if mode == _active_mode:
		return
	_active_mode = mode
	_world_env.environment = _environments[mode]
	for i in levels.size():
		levels[i].set_active(i == mode)
	hud.set_mode(mode)
	var current := get_viewport().get_camera_3d()
	if current == null or not players_root.is_ancestor_of(current):
		levels[mode].overview_camera.current = true


func _handle_command_line() -> void:
	var host := false
	var join_address := ""
	for arg in OS.get_cmdline_user_args():
		if arg == "--host":
			host = true
		elif arg.begins_with("--join="):
			join_address = arg.trim_prefix("--join=")
		elif arg.begins_with("--name="):
			hud.set_player_name(arg.trim_prefix("--name="))
		elif arg.begins_with("--show="):
			hud.set_mode(clampi(arg.trim_prefix("--show=").to_int(), 0, levels.size() - 1))
	if host:
		_on_host_pressed(hud.get_player_name(), hud.get_mode())
	elif not join_address.is_empty():
		_on_join_pressed(hud.get_player_name(), join_address)
