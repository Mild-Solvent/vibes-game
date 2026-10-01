extends Node
## Autoload "SessionLog": an always-on log of each play session, for playtest reports.
##
## Where: a "logs" folder next to the game's exe (exported builds), or user://logs-session when
## run from the editor. One file per session, session-YYYYMMDD-HHMMSS.log; the newest 10 are kept.
## What: the build, host/client, who joined and left, once a second the connection and voice
## numbers (ping, KB/s, FPS, voice queue), lag spikes, gameplay events (deaths, rescues, toasts),
## and every engine/script error and print.
## Keys: F8 marks "something went wrong here" (a line plus a screenshot), F9 opens the folder.
## Summarize a log with `python godot/Mushroom/tools/summarize_logs.py <file or folder>`.

const KEEP := 10
const SPIKE_PING_MS := 200
const SPIKE_QUEUE_MS := 150

var dir := ""
var path := ""
var _file: FileAccess
var _mutex := Mutex.new()
var _second := 0.0
var _frames := 0
var _queue_max := 0
var _logger: Logger


## Engine and script errors, warnings and prints all land in the session log too.
class Catcher extends Logger:
	var owner_log: Node

	func _log_message(message: String, error: bool) -> void:
		owner_log.write("ERR " if error else "OUT ", message.strip_edges())

	func _log_error(function: String, file: String, line: int, code: String, rationale: String,
			_editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		var kind: String = ["ERROR", "WARNING", "SCRIPT ERROR", "SHADER ERROR"][clampi(error_type, 0, 3)]
		var what := rationale if not rationale.is_empty() else code
		owner_log.write("ERR ", "%s: %s (%s:%d %s)" % [kind, what, file.get_file(), line, function])


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if OS.has_feature("template"):
		dir = OS.get_executable_path().get_base_dir().path_join("logs")
	else:
		dir = ProjectSettings.globalize_path("user://logs-session")
	DirAccess.make_dir_recursive_absolute(dir)
	_rotate()
	path = dir.path_join("session-%s.log" % Time.get_datetime_string_from_system().replace("-", "")
		.replace(":", "").replace("T", "-"))
	_file = FileAccess.open(path, FileAccess.WRITE)
	if _file == null:
		push_warning("SessionLog: can't write %s" % path)
		return
	write("INFO", "Mushroom Foraging build %s · Godot %s · %s · %s" % [
		ProjectSettings.get_setting("application/config/version", "?"), Engine.get_version_info()["string"],
		OS.get_name(), OS.get_processor_name()])
	_logger = Catcher.new()
	_logger.owner_log = self
	OS.add_logger(_logger)
	multiplayer.connected_to_server.connect(func(): write("NET ", "connected to the host as peer %d"
		% multiplayer.get_unique_id()))
	multiplayer.connection_failed.connect(func(): write("NET ", "connection failed"))
	multiplayer.server_disconnected.connect(func(): write("NET ", "the host disconnected"))
	multiplayer.peer_connected.connect(func(id): write("NET ", "peer %d connected" % id))
	multiplayer.peer_disconnected.connect(func(id): write("NET ", "peer %d disconnected" % id))
	Net.status_changed.connect(func(text): write("NET ", text))
	Net.player_joined.connect(func(id, n): write("NET ", "player %s joined (peer %d)" % [n, id]))
	Team.died.connect(func(id, reason): write("GAME", "%s died: %s" % [_name(id), reason]))
	Team.revived.connect(func(id): write("GAME", "%s revived" % _name(id)))
	Team.toast.connect(func(text): write("GAME", "toast: %s" % text))
	Team.game_over.connect(func(stats): write("GAME", "game over: %s" % JSON.stringify(stats)))


func _exit_tree() -> void:
	if _logger:
		OS.remove_logger(_logger)
	if _file:
		write("INFO", "session ended")
		_file.close()


## Any script: `SessionLog.event("rescue", "Denis pulled Nina out of the mud")`.
func event(kind: String, text: String) -> void:
	write("GAME", "%s: %s" % [kind, text])


## Thread-safe (the engine logger can call from any thread).
func write(kind: String, text: String) -> void:
	if _file == null:
		return
	var t := Time.get_time_dict_from_system()
	var ms := Time.get_ticks_msec() % 1000
	_mutex.lock()
	_file.store_line("%02d:%02d:%02d.%03d %s %s" % [t["hour"], t["minute"], t["second"], ms, kind, text])
	_file.flush()
	_mutex.unlock()


func _process(delta: float) -> void:
	_frames += 1
	var connected := _connected()
	if connected:
		_queue_max = maxi(_queue_max, int(Voice.net_stats()["queue_ms"]))
	_second += delta
	if _second < 1.0:
		return
	var fps := _frames / _second
	_second = 0.0
	_frames = 0
	if not connected:
		return
	var n: Dictionary = Voice.net_stats()
	write("STAT", ("role=%s players=%d fps=%.0f ping=%d pmin=%d pavg=%d pmax=%d out=%.1f in=%.1f "
		+ "mic=%d queue=%d qmax=%d sent=%d recv=%d skip=%d clear=%d") % [
		"host" if multiplayer.is_server() else "client", multiplayer.get_peers().size() + 1, fps,
		n["ping"], n["ping_min"], n["ping_avg"], n["ping_max"], n["out_kbs"], n["in_kbs"], n["mic_ms"],
		n["queue_ms"], _queue_max, n["sent"], n["recv"], n["skip"], n["clear"]])
	if int(n["ping"]) > SPIKE_PING_MS or _queue_max > SPIKE_QUEUE_MS:
		write("LAG ", "spike: ping %d ms, voice queue up to %d ms, fps %.0f, out %.1f KB/s" % [
			n["ping"], _queue_max, fps, n["out_kbs"]])
	_queue_max = 0


func _input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if event.physical_keycode == KEY_F8:
		mark_bug()
	elif event.physical_keycode == KEY_F9:
		OS.shell_open(dir)


## F8: a marker line plus a screenshot, so a moment can be found in the log later.
func mark_bug() -> void:
	var stamp := Time.get_datetime_string_from_system().replace(":", "").replace("-", "").replace("T", "-")
	var shot := dir.path_join("bug-%s.png" % stamp)
	var image := get_viewport().get_texture().get_image()
	if image:
		image.save_png(shot)
	write("BUG ", "F8 pressed · screenshot %s" % shot.get_file())
	Team.toast.emit("Bug marked in the log (F9 opens the logs folder).")


func _name(id: int) -> String:
	return str(Team.players.get(id, {}).get("name", "peer %d" % id))


func _connected() -> bool:
	var mp := multiplayer.multiplayer_peer
	return mp != null and not (mp is OfflineMultiplayerPeer) \
			and mp.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


## Keep the newest KEEP session logs (and their screenshots' worth of clutter: 30 bug shots).
func _rotate() -> void:
	for pattern in [["session-", ".log", KEEP - 1], ["bug-", ".png", 30]]:
		var names: Array[String] = []
		for f in DirAccess.get_files_at(dir):
			if f.begins_with(pattern[0]) and f.ends_with(pattern[1]):
				names.append(f)
		names.sort()
		while names.size() > int(pattern[2]):
			DirAccess.remove_absolute(dir.path_join(names.pop_front()))
