extends Node3D
## Bootstraps a session: builds every level, the player spawner, the director and the UI.
##
## All levels exist on every peer at once (far apart), so props and synchronizers always have
## matching node paths. The host picks which level is played; clients learn it from the director.
##
## Quick local testing from the command line (two terminals):
##   godot --path . -- --host --name=Adam
##   godot --path . -- --join=127.0.0.1 --name=Denis

const PlayerScript := preload("res://scripts/player.gd")
const DirectorScript := preload("res://scripts/game_director.gd")
const HudScript := preload("res://scripts/hud.gd")
const MenuScript := preload("res://scripts/ui/menu.gd")
const LEVELS := [
	[preload("res://scripts/levels/forest.gd"), "Forest", Vector3(0, 0, 0)],
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
var menu: CanvasLayer

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
	director.add_to_group("director")
	director.levels = levels
	add_child(director)

	hud = HudScript.new()
	add_child(hud)
	var titles := []
	for level in levels:
		titles.append(level.title())
	hud.set_levels(titles)

	# The real menu (main menu, lobby, settings, pause). Same path on every peer: the lobby syncs.
	menu = MenuScript.new()
	menu.name = "Menu"
	add_child(menu)
	menu.host_requested.connect(_on_menu_host)
	menu.join_requested.connect(_on_menu_join)
	menu.start_requested.connect(func(): menu.lobby.start())
	menu.lobby_started.connect(_on_lobby_started)
	menu.leave_requested.connect(_on_leave)
	menu.journal_requested.connect(hud.toggle_journal)
	hud.menu = menu

	Net.player_joined.connect(_on_player_joined)
	Net.player_left.connect(_on_player_left)
	director.changed.connect(_on_director_changed)
	Team.game_over.connect(_on_game_over)

	_activate(0)
	_handle_command_line()


## Menu: host a game. Players arrive in the lobby; the day starts when the host presses Start.
func _on_menu_host(player_name: String, port: int) -> void:
	Net.player_name = player_name
	Net.port = port
	Team.reset()
	_activate(0)
	if Net.host() != OK:
		menu.show_main()


func _on_menu_join(player_name: String, address: String, port: int) -> void:
	Net.player_name = player_name
	Net.port = port
	Net.join(address if not address.is_empty() else "127.0.0.1")


## Every peer: the host pressed Start in the lobby.
func _on_lobby_started() -> void:
	if multiplayer.is_server() and not director.running:
		director.start(0)
	if menu.in_game:
		return  # already playing (the lobby re-announces the start to late joiners)
	hud.show_game()
	menu.in_game = true
	menu.hide_all()


## Host: after a game over, the next run starts from a fresh morning.
func _on_game_over(_stats: Dictionary) -> void:
	if multiplayer.is_server() and director.running:
		director.start(0)


func _on_leave() -> void:
	Net.leave()
	get_tree().reload_current_scene()


## Command line / quick start: host and start the day straight away.
func _on_host_pressed(player_name: String, mode: int) -> void:
	Net.player_name = player_name
	Team.reset()
	_activate(mode)
	director.start(mode)
	if Net.host() == OK:
		hud.show_game()
		menu.in_game = true
		menu.hide_all()
	else:
		director.running = false


func _on_join_pressed(player_name: String, address: String) -> void:
	Net.player_name = player_name
	multiplayer.connected_to_server.connect(func(): _on_lobby_started(), CONNECT_ONE_SHOT)
	Net.join(address if not address.is_empty() else "127.0.0.1")


## Host only: someone (including the host) is ready for a body.
func _on_player_joined(peer_id: int, player_name: String) -> void:
	if not multiplayer.is_server():
		return
	Team.add_player(peer_id, player_name)
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
	var car := get_tree().get_first_node_in_group("car")
	if car:
		car.leave(peer_id)
	Team.remove_player(peer_id)
	var player := players_root.get_node_or_null(str(peer_id))
	if player:
		player.queue_free()


## Runs on every peer (host and clients) with the same data.
func _spawn_player(data: Variant) -> Node:
	var player := PlayerScript.new()
	player.setup(data["id"], data["name"], PLAYER_COLORS[data["color"]], data["color"])
	player.position = data["pos"]
	return player


func _on_director_changed() -> void:
	_activate(director.mode)
	var level: Node3D = levels[director.mode]
	var secs := maxi(int(ceil(director.time_left)), 0)
	var clock := "%d:%02d" % [secs / 60, secs % 60]
	level.apply_state(director.phase, director.event, director.sub, director.time_left)
	hud.set_phase(director.phase)
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
	var day_time := -1.0
	var autodrive := false
	for arg in OS.get_cmdline_user_args():
		if arg == "--host":
			host = true
		elif arg.begins_with("--join="):
			join_address = arg.trim_prefix("--join=")
		elif arg.begins_with("--name="):
			hud.set_player_name(arg.trim_prefix("--name="))
		elif arg == "--autodrive":
			autodrive = true
		elif arg == "--skip-intro":
			hud.intro_enabled = false
		elif arg.begins_with("--spawn="):
			levels[0].spawn_override = arg.trim_prefix("--spawn=")
		elif arg.begins_with("--day-time="):
			day_time = arg.trim_prefix("--day-time=").to_float()
		elif arg.begins_with("--port="):
			Net.port = arg.trim_prefix("--port=").to_int()
		elif arg.begins_with("--show="):
			hud.set_mode(clampi(arg.trim_prefix("--show=").to_int(), 0, levels.size() - 1))
	if host or not join_address.is_empty():
		menu.auto_lobby = false  # command line skips the lobby
	if host:
		_on_host_pressed(hud.get_player_name(), hud.get_mode())
		if day_time >= 0.0:  # testing: jump straight into the day at this point (0 morning, 1 midnight)
			director._enter(1)
			director.time_left = levels[0].live_duration() * (1.0 - day_time)
		if autodrive:  # testing: the host gets in the car and floors it
			var car := get_tree().get_first_node_in_group("car")
			car.request_enter()
			car.autodrive = true
	elif not join_address.is_empty():
		_on_join_pressed(hud.get_player_name(), join_address)
