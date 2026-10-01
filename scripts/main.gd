extends Node3D
## Bootstraps a session: builds the studio, the player spawner, the show director and the UI.
##
## Quick local testing from the command line (two terminals):
##   godot --path . -- --host --name=Adam
##   godot --path . -- --join=127.0.0.1 --name=Denis

const StudioScript := preload("res://scripts/studio.gd")
const PlayerScript := preload("res://scripts/player.gd")
const ShowDirectorScript := preload("res://scripts/show_director.gd")
const HudScript := preload("res://scripts/hud.gd")

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

var studio: StudioScript
var players_root: Node3D
var spawner: MultiplayerSpawner
var show_director: ShowDirectorScript
var hud: HudScript

var _joined_count := 0


func _ready() -> void:
	studio = StudioScript.new()
	studio.name = "Studio"
	add_child(studio)

	players_root = Node3D.new()
	players_root.name = "Players"
	add_child(players_root)

	spawner = MultiplayerSpawner.new()
	spawner.name = "PlayerSpawner"
	spawner.spawn_path = NodePath("../Players")
	spawner.spawn_function = _spawn_player
	add_child(spawner)

	show_director = ShowDirectorScript.new()
	show_director.name = "Show"
	show_director.on_air_camera = studio.on_air_camera
	add_child(show_director)

	hud = HudScript.new()
	add_child(hud)

	hud.host_pressed.connect(_on_host_pressed)
	hud.join_pressed.connect(_on_join_pressed)
	Net.status_changed.connect(hud.set_status)
	Net.player_joined.connect(_on_player_joined)
	Net.player_left.connect(_on_player_left)
	multiplayer.connected_to_server.connect(hud.show_game)
	show_director.changed.connect(_on_show_changed)

	_handle_command_line()


func _on_host_pressed(player_name: String) -> void:
	Net.player_name = player_name
	if Net.host() == OK:
		show_director.running = true
		hud.show_game()


func _on_join_pressed(player_name: String, address: String) -> void:
	Net.player_name = player_name
	Net.join(address if not address.is_empty() else "127.0.0.1")


## Host only: someone (including the host) is ready for a body.
func _on_player_joined(peer_id: int, player_name: String) -> void:
	if not multiplayer.is_server():
		return
	var index := _joined_count
	_joined_count += 1
	var spawn_data := {
		"id": peer_id,
		"name": player_name,
		"color": index % PLAYER_COLORS.size(),
		"pos": studio.spawn_point(index),
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


func _on_show_changed() -> void:
	hud.update_show(show_director.phase, show_director.time_left, show_director.ratings, show_director.event)
	studio.set_show_state(show_director.phase, show_director.event)


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
	var player_name := hud.get_player_name()
	if host:
		_on_host_pressed(player_name)
	elif not join_address.is_empty():
		_on_join_pressed(player_name, join_address)
