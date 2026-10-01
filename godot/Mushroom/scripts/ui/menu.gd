extends CanvasLayer
## The whole out-of-game UI, built in code: main menu, host / join screens, lobby (with network
## ready state), settings, controls, how to play, credits and the in-game pause overlay.
## The 3D world keeps rendering behind it; nothing here pauses the tree (multiplayer keeps going).
##
## Everything is laid out for 1280x720 and the layer is scaled to the window, so it looks the same
## at 1080p. Esc goes back one screen; in game (in_game = true) Esc opens / closes the pause overlay.
## The node is called "Menu" and holds a "Lobby" node with RPCs, so add it at the same path on every
## peer (e.g. as a child of main).

signal host_requested(player_name: String, port: int)
signal join_requested(player_name: String, address: String, port: int)
signal start_requested  ## host pressed Start in the lobby (before the lobby tells everyone)
signal leave_requested  ## leave the session and go back to the main menu
signal quit_requested  ## quit to desktop (if nothing is connected, the menu quits by itself)
signal journal_requested  ## pause overlay: open the field journal
signal lobby_started  ## every peer: the host started the game, the menu has hidden itself

const UiTheme := preload("res://scripts/ui/theme.gd")
const Icon := preload("res://scripts/ui/icons.gd")
const LobbyScript := preload("res://scripts/ui/lobby.gd")
const SettingsPanel := preload("res://scripts/ui/settings_panel.gd")
const Pages := preload("res://scripts/ui/info_pages.gd")

const REF_SIZE := Vector2(1280, 720)
const TIPS := [
	"Babka Hela names every mushroom you put on her counter. For everyone.",
	"Tasting is free. The consequences are not.",
	"The hag hears your voice. Maybe whisper.",
	"All flashlights share one battery stash. Turn yours off.",
	"Uncle Fero comes every third day. He does not take mushrooms.",
	"Lost? Use the walkie (V). After a while somebody calls the police.",
	"Throw a mushroom too hard, three times, and it breaks.",
	"The witch can cure you. She just wants something from a scary place first.",
]

## Set by main while gameplay runs: Esc then toggles the pause overlay and closing menus
## captures the mouse again.
var in_game := false
## Show the lobby by itself after hosting succeeds / after a client connects.
var auto_lobby := true
var lobby: LobbyScript

var _root: Control
var _vignette: TextureRect
var _shade: ColorRect
var _pages := {}  # page name -> Control
var _focus := {}  # page name -> Control focused when it opens
var _stack: Array[String] = []
var _shown := ""
var _status: Label
var _status_box: Control
var _confirm_box: Control
var _confirm_label: Label
var _confirm_yes: Button
var _confirm_action := Callable()
var _player_name := ""
var _name_edits: Array[LineEdit] = []
var _host_port: LineEdit
var _host_ips: VBoxContainer
var _join_address: LineEdit
var _join_port: LineEdit
var _lobby_list: VBoxContainer
var _lobby_info: Label
var _lobby_count: Label
var _ready_button: Button
var _start_button: Button
var _settings: SettingsPanel
var _howto_holder: Control
var _howto_page := 0
var _howto_label: Label
var _howto_prev: Button
var _howto_next: Button
var _pause_day: Label
var _pause_cash: Label
var _pause_quota: Label
var _pause_extra: Label
var _pause_crew: Label
var _cheats_button: Button  # host only
var _tip: Label
var _tip_index := 0
var _tip_left := 8.0
var _info_left := 0.0


func _init() -> void:
	name = "Menu"
	layer = 20


func _ready() -> void:
	_player_name = Settings.last_name if not Settings.last_name.is_empty() else "Friend %d" % randi_range(1, 99)
	lobby = LobbyScript.new()
	lobby.name = "Lobby"
	add_child(lobby)
	lobby.roster_changed.connect(_refresh_lobby)
	lobby.started.connect(_on_lobby_started)

	_root = Control.new()
	_root.theme = UiTheme.build()
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)
	_build_backdrop()
	_add_page("main", _build_main())
	_add_page("host", _build_host())
	_add_page("join", _build_join())
	_add_page("lobby", _build_lobby())
	_add_page("settings", _build_settings())
	_add_page("controls", _build_controls())
	_add_page("howto", _build_howto())
	_add_page("credits", _build_credits())
	_add_page("pause", _build_pause())
	_build_status()
	_build_confirm()

	get_viewport().size_changed.connect(_rescale)
	_rescale()
	Net.status_changed.connect(set_status)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(_on_connection_failed)
	show_main()


func _process(delta: float) -> void:
	if _shown == "main":
		_tip_left -= delta
		if _tip_left <= 0.0:
			_tip_left = 8.0
			_tip_index = (_tip_index + 1) % TIPS.size()
			_tip.text = TIPS[_tip_index]
	elif _shown == "pause":
		_info_left -= delta
		if _info_left <= 0.0:
			_info_left = 0.5
			_update_pause_info()


func _input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel") or event.is_echo():
		return
	if _confirm_box.visible:
		_confirm_box.visible = false
		_focus_top()
	elif is_open():
		_back()
	elif in_game:
		toggle_pause()
	else:
		return
	get_viewport().set_input_as_handled()


# --- public API -------------------------------------------------------------------


## The title screen (also leaves in_game mode).
func show_main() -> void:
	in_game = false
	if not Net.is_online():
		lobby.clear()
	_stack = ["main"]
	_show_top()


## The lobby: who's here, ready toggles, host Start.
func show_lobby() -> void:
	_stack = ["lobby"]
	_refresh_lobby()
	_show_top()


## Close every menu. In game this also captures the mouse again.
func hide_all() -> void:
	_stack.clear()
	_confirm_box.visible = false
	_show_top()
	if in_game and get_window().has_focus():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func set_status(text: String) -> void:
	_status.text = text
	_update_status_box()


## In game: open the pause overlay, or close whatever menu is open and resume.
func toggle_pause() -> void:
	set_paused_overlay(not is_open())


func set_paused_overlay(open: bool) -> void:
	if open:
		_stack = ["pause"]
		_info_left = 0.0
		_show_top()
	else:
		hide_all()


## Any menu or overlay is showing (the player script should not grab the mouse).
func is_open() -> bool:
	return not _stack.is_empty()


func set_player_name(player_name: String) -> void:
	_player_name = player_name
	for e in _name_edits:
		e.text = player_name


func get_player_name() -> String:
	var n := _player_name.strip_edges()
	return n if not n.is_empty() else "Friend"


## This PC's IPv4 addresses friends can use: [[address, "LAN" / "Tailscale" / ...]], LAN first.
static func local_addresses() -> Array:
	var lan := []
	var vpn := []
	for a in IP.get_local_addresses():
		var parts: PackedStringArray = a.split(".")
		if parts.size() != 4:
			continue
		var o0 := parts[0].to_int()
		var o1 := parts[1].to_int()
		if o0 == 192 and o1 == 168 or o0 == 10 or o0 == 172 and o1 >= 16 and o1 <= 31:
			lan.append([a, "home network"])
		elif o0 == 100 and o1 >= 64 and o1 <= 127:
			vpn.append([a, "Tailscale"])
		elif o0 == 26:
			vpn.append([a, "Radmin VPN"])
		elif o0 == 25:
			vpn.append([a, "Hamachi"])
	lan.sort_custom(func(a: Array, b: Array): return a[0].begins_with("192.168") and not b[0].begins_with("192.168"))
	return (lan + vpn).slice(0, 6)


# --- navigation -------------------------------------------------------------------


func _open(page: String) -> void:
	_stack.append(page)
	_show_top()


func _back() -> void:
	if _stack.is_empty():
		return
	Sfx.play("ui_click")
	match _stack.back():
		"main":
			pass
		"lobby":
			_confirm("Leave the camp and go back to the main menu?", "Leave", _leave)
		"pause":
			hide_all()
		_:
			_stack.pop_back()
			_show_top()


func _show_top() -> void:
	var top: String = _stack.back() if not _stack.is_empty() else ""
	if _shown == "settings" and top != "settings":
		_settings.closed()
	if top == "settings" and _shown != "settings":
		_settings.opened()
	_shown = top
	for n in _pages:
		_pages[n].visible = n == top
	_root.visible = top != ""
	_shade.visible = top != "main"
	_shade.color = Color(0.02, 0.04, 0.02, 0.35 if in_game else 0.55)
	match top:
		"host":
			_refresh_ips()
		"lobby":
			_refresh_lobby()
		"pause":
			_update_pause_info()
	_update_status_box()
	if top != "":
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		_focus_top()


func _focus_top() -> void:
	var c: Control = _focus.get(_shown)
	if c and c.is_inside_tree():
		c.grab_focus.call_deferred()


func _confirm(text: String, yes_text: String, action: Callable) -> void:
	_confirm_label.text = text
	_confirm_yes.text = yes_text
	_confirm_action = action
	_confirm_box.visible = true
	_confirm_yes.grab_focus.call_deferred()


func _leave() -> void:
	lobby.clear()
	in_game = false
	leave_requested.emit()
	show_main()


func _quit() -> void:
	quit_requested.emit()
	if quit_requested.get_connections().is_empty():
		get_tree().quit()


func _rescale() -> void:
	var vp := get_viewport().get_visible_rect().size
	var s := maxf(minf(vp.x / REF_SIZE.x, vp.y / REF_SIZE.y), 0.5)
	scale = Vector2(s, s)
	_root.position = Vector2.ZERO
	_root.size = vp / s
	_settings.set_ui_scale(s)


func _update_status_box() -> void:
	_status_box.visible = not _status.text.is_empty() and _shown in ["main", "host", "join", "lobby"]


# --- actions ----------------------------------------------------------------------


func _on_host() -> void:
	var port := _parse_port(_host_port.text)
	_host_port.text = str(port)
	Settings.set_value("last_name", get_player_name())
	Settings.set_value("last_port", port)
	set_status("Starting the camp on port %d..." % port)
	host_requested.emit(get_player_name(), port)
	if auto_lobby and Net.is_online() and multiplayer.is_server():
		show_lobby()


func _on_join() -> void:
	var address := _join_address.text.strip_edges()
	if address.is_empty():
		address = "127.0.0.1"
	var port := _parse_port(_join_port.text)
	_join_port.text = str(port)
	Settings.set_value("last_name", get_player_name())
	Settings.set_value("last_address", address)
	Settings.set_value("last_port", port)
	set_status("Connecting to %s:%d..." % [address, port])
	join_requested.emit(get_player_name(), address, port)


func _on_connected() -> void:
	if auto_lobby and _shown in ["join", "main", "host"]:
		show_lobby()


func _on_connection_failed() -> void:
	set_status("Could not reach the host. Right address and port? Is the game hosting?")


func _on_lobby_started() -> void:
	in_game = true
	hide_all()
	lobby_started.emit()


func _on_start() -> void:
	if lobby.all_ready():
		_start_game()
	else:
		_confirm("Only %d of %d friends are ready. Start anyway?" % [lobby.ready_count(), lobby.roster.size()],
			"Start anyway", _start_game)


func _start_game() -> void:
	start_requested.emit()
	lobby.start()


func _on_confirm_cancel() -> void:
	_confirm_box.visible = false
	_focus_top()


func _on_confirm_yes() -> void:
	_confirm_box.visible = false
	if _confirm_action.is_valid():
		_confirm_action.call()


func _on_journal() -> void:
	hide_all()
	journal_requested.emit()


func _on_howto_next() -> void:
	if _howto_page >= Pages.how_to_pages() - 1:
		_back()
	else:
		_set_howto(_howto_page + 1)


func _on_ready_toggled(on: bool) -> void:
	Sfx.play("ui_click")
	lobby.set_ready(on)


func _on_name_changed(text: String, edit: LineEdit) -> void:
	_player_name = text
	for other in _name_edits:
		if other != edit:
			other.text = text


func _parse_port(text: String) -> int:
	var p := text.strip_edges().to_int()
	return p if p >= 1024 and p <= 65535 else Net.DEFAULT_PORT


# --- page refreshers --------------------------------------------------------------


func _refresh_ips() -> void:
	for c in _host_ips.get_children():
		c.queue_free()
	var list := local_addresses()
	if list.is_empty():
		list = [["127.0.0.1", "this PC only"]]
	for entry in list:
		var row := HBoxContainer.new()
		var ip := Label.new()
		ip.text = entry[0]
		ip.theme_type_variation = "Heading"
		ip.add_theme_font_size_override("font_size", 24)
		ip.add_theme_color_override("font_color", UiTheme.GOLD)
		ip.add_theme_constant_override("outline_size", 0)
		row.add_child(ip)
		var tag := Label.new()
		tag.text = entry[1]
		tag.theme_type_variation = "Dim"
		tag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(tag)
		_host_ips.add_child(row)


func _refresh_lobby() -> void:
	if _lobby_list == null:
		return
	for c in _lobby_list.get_children():
		c.queue_free()
	var me := multiplayer.get_unique_id() if Net.is_online() else 1
	for p in lobby.roster:
		var card := PanelContainer.new()
		card.theme_type_variation = "Card"
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 14)
		card.add_child(row)
		row.add_child(Icon.new("tick" if p["ready"] else "wait", 34.0))
		var n := Label.new()
		n.text = p["name"] + ("  (you)" if p["id"] == me else "")
		n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		n.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		n.clip_text = true
		row.add_child(n)
		if p["id"] == 1:
			row.add_child(Icon.new("host", 30.0))
		var state := Label.new()
		state.text = "READY" if p["ready"] else "not ready"
		state.theme_type_variation = "Small"
		state.custom_minimum_size = Vector2(90, 0)
		state.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		state.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		if p["ready"]:
			state.add_theme_color_override("font_color", UiTheme.GOLD)
		row.add_child(state)
		_lobby_list.add_child(card)
	if lobby.roster.is_empty():
		var waiting := Label.new()
		waiting.text = "Waiting for the camp roster..."
		waiting.theme_type_variation = "Dim"
		_lobby_list.add_child(waiting)
	var is_host := Net.is_online() and multiplayer.is_server()
	_lobby_count.text = "%d of %d ready  ·  room for %d" % [lobby.ready_count(), lobby.roster.size(), Net.MAX_PLAYERS]
	_start_button.visible = is_host
	_start_button.text = "Start the day!" if lobby.all_ready() else "Start anyway..."
	var mine := lobby.is_ready(me)
	_ready_button.set_pressed_no_signal(mine)
	_ready_button.text = "Ready! (undo)" if mine else "I'm ready"
	_ready_button.theme_type_variation = "Big" if not mine else "Tab"
	if is_host:
		var lines := PackedStringArray()
		for entry in local_addresses():
			lines.append("%s  (%s)" % [entry[0], entry[1]])
		if lines.is_empty():
			lines.append("127.0.0.1 (this PC only)")
		_lobby_info.text = "Friends join at port %d:\n%s" % [Net.port, "\n".join(lines)]
	else:
		_lobby_info.text = "You're at the camp. The host starts the day when everyone is ready."


func _update_pause_info() -> void:
	if _pause_day == null:
		return
	_pause_day.text = "DAY %d" % Team.day
	if _cheats_button:
		_cheats_button.visible = multiplayer.is_server()
		_cheats_button.text = "Cheats: %s" % ("ON" if Team.cheats else "OFF")
	_pause_cash.text = "%d €" % Team.cash
	var due := Team.quota_day()
	var left := due - Team.day
	var when := "today" if left <= 0 else ("tomorrow" if left == 1 else "in %d days" % left)
	_pause_quota.text = "Uncle Fero wants %d € at the end of day %d (%s)." % [Team.quota_amount(), due, when]
	var short := Team.quota_amount() - Team.cash
	_pause_extra.text = ("You have enough. Don't spend it all at the casino." if short <= 0
		else "Still %d € short. Shared batteries: %d" % [short, Team.batteries])
	var lines := PackedStringArray()
	for id in Team.players:
		lines.append("%s  -  %s" % [Team.players[id].get("name", "?"), _status_word(id)])
	_pause_crew.text = "\n".join(lines) if not lines.is_empty() else "Just you and the trees."


func _status_word(peer_id: int) -> String:
	if not str(Team.players[peer_id].get("stuck", "")).is_empty():
		return "stuck!"
	match Team.status_of(peer_id):
		Team.Status.TRIPPING:
			return "tripping"
		Team.Status.PASSED_OUT:
			return "passed out"
		Team.Status.POISONED:
			return "POISONED"
		Team.Status.DEAD:
			return "dead (ghost)"
	return "fine"


# --- page builders ----------------------------------------------------------------


func _add_page(page_name: String, page: Control) -> void:
	page.visible = false
	_pages[page_name] = page
	_root.add_child(page)


func _full(c: Control) -> Control:
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return c


func _build_backdrop() -> void:
	var g := Gradient.new()
	g.set_color(0, Color(0.04, 0.07, 0.03, 0.0))
	g.set_color(1, Color(0.02, 0.03, 0.015, 0.92))
	g.add_point(0.55, Color(0.03, 0.05, 0.03, 0.35))
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.45)
	tex.fill_to = Vector2(1.15, 1.05)
	tex.width = 256
	tex.height = 256
	_vignette = TextureRect.new()
	_vignette.texture = tex
	_vignette.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_vignette.stretch_mode = TextureRect.STRETCH_SCALE
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_full(_vignette))
	_shade = ColorRect.new()
	_shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_full(_shade))


func _build_main() -> Control:
	var page := _full(Control.new())
	var side := Gradient.new()
	side.set_color(0, Color(0.03, 0.05, 0.02, 0.85))
	side.set_color(1, Color(0.03, 0.05, 0.02, 0.0))
	var side_tex := GradientTexture2D.new()
	side_tex.gradient = side
	side_tex.fill_from = Vector2(0.15, 0)
	side_tex.fill_to = Vector2(0.7, 0)
	var shade := TextureRect.new()
	shade.texture = side_tex
	shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.add_child(_full(shade))

	var margin := _full(MarginContainer.new())
	margin.add_theme_constant_override("margin_left", 72)
	margin.add_theme_constant_override("margin_top", 34)
	margin.add_theme_constant_override("margin_bottom", 34)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.add_child(margin)
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	col.add_theme_constant_override("separation", 16)
	margin.add_child(col)

	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 14)
	col.add_child(title_row)
	var logo := Icon.new("mushroom", 140.0)
	logo.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	title_row.add_child(logo)
	var words := VBoxContainer.new()
	words.add_theme_constant_override("separation", -26)
	title_row.add_child(words)
	var w1 := _label("MUSHROOM", "Title")
	w1.add_theme_color_override("font_color", UiTheme.CREAM)
	words.add_child(w1)
	words.add_child(_label("FORAGING", "Title"))

	var plank := PanelContainer.new()
	plank.theme_type_variation = "Plank"
	plank.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	plank.add_child(_label("Four broke friends. One forest. Which ones can you eat?", ""))
	col.add_child(plank)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(430, 0)
	panel.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	col.add_child(panel)
	var buttons := VBoxContainer.new()
	buttons.add_theme_constant_override("separation", 10)
	panel.add_child(buttons)
	var host := _button("Host Game", func(): _open("host"), "Big")
	buttons.add_child(host)
	buttons.add_child(_button("Join Game", func(): _open("join"), "Big"))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	buttons.add_child(grid)
	for entry in [["Settings", "settings"], ["Controls", "controls"], ["How to Play", "howto"],
			["Credits", "credits"]]:
		var b := _button(entry[0], _open.bind(entry[1]))
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(b)
	buttons.add_child(_button("Quit", _quit, "Danger"))
	_focus["main"] = host

	var tip_card := PanelContainer.new()
	tip_card.theme_type_variation = "Card"
	tip_card.custom_minimum_size = Vector2(380, 0)
	tip_card.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, 28)
	tip_card.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	tip_card.grow_vertical = Control.GROW_DIRECTION_BEGIN
	page.add_child(tip_card)
	var tip_row := HBoxContainer.new()
	tip_card.add_child(tip_row)
	tip_row.add_child(Icon.new("mystery", 56.0))
	var tip_col := VBoxContainer.new()
	tip_col.add_theme_constant_override("separation", 2)
	tip_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tip_row.add_child(tip_col)
	var tip_head := _label("FORAGER'S TIP", "Small")
	tip_head.add_theme_color_override("font_color", UiTheme.GOLD)
	tip_col.add_child(tip_head)
	_tip_index = randi() % TIPS.size()
	_tip = _label(TIPS[_tip_index], "")
	_tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tip.add_theme_font_size_override("font_size", 18)
	tip_col.add_child(_tip)
	return page


## A centred window with a wooden title plank; returns [page, content VBox].
func _window(title: String, min_size: Vector2) -> Array:
	var page := _full(Control.new())
	page.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var center := _full(CenterContainer.new())
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.add_child(center)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", -24)
	center.add_child(stack)
	var plank := PanelContainer.new()
	plank.theme_type_variation = "Plank"
	plank.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	plank.z_index = 1
	plank.add_child(_label(title, "Heading"))
	stack.add_child(plank)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = min_size
	stack.add_child(panel)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_top", 18)
	panel.add_child(margin)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 14)
	margin.add_child(content)
	return [page, content]


func _footer(content: VBoxContainer, back_text := "Back") -> HBoxContainer:
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(spacer)
	var row := HBoxContainer.new()
	content.add_child(row)
	if not back_text.is_empty():
		row.add_child(_button(back_text, _back))
	var fill := Control.new()
	fill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(fill)
	return row


func _build_host() -> Control:
	var w := _window("HOST A GAME", Vector2(760, 520))
	var content: VBoxContainer = w[1]
	_host_port = LineEdit.new()
	_host_port.text = str(Settings.last_port)
	_host_port.max_length = 5
	_host_port.custom_minimum_size = Vector2(140, 0)
	_host_port.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_host_port.text_submitted.connect(func(_t): _on_host())
	var name_edit := _make_name_edit()
	name_edit.text_submitted.connect(func(_t): _on_host())
	content.add_child(_form([["Your name", name_edit], ["Port (UDP)", _host_port]]))
	var inset := PanelContainer.new()
	inset.theme_type_variation = "Inset"
	content.add_child(inset)
	var ips_col := VBoxContainer.new()
	ips_col.add_theme_constant_override("separation", 4)
	inset.add_child(ips_col)
	ips_col.add_child(_label("Friends type one of these addresses to join you:", "Dim"))
	_host_ips = VBoxContainer.new()
	_host_ips.add_theme_constant_override("separation", 2)
	ips_col.add_child(_host_ips)
	content.add_child(_note("Same Wi-Fi or LAN: use the home network address. Over the internet: everyone "
		+ "installs Tailscale or Radmin VPN, joins the same network and uses your VPN address "
		+ "(100.x for Tailscale, 26.x for Radmin). Or forward the UDP port on your router."))
	var row := _footer(content)
	var go := _button("Host Game", _on_host, "Big")
	row.add_child(go)
	_focus["host"] = go
	return w[0]


func _build_join() -> Control:
	var w := _window("JOIN A GAME", Vector2(760, 470))
	var content: VBoxContainer = w[1]
	var name_edit := _make_name_edit()
	_join_address = LineEdit.new()
	_join_address.text = Settings.last_address
	_join_address.placeholder_text = "e.g. 192.168.1.20"
	_join_address.select_all_on_focus = true
	_join_port = LineEdit.new()
	_join_port.text = str(Settings.last_port)
	_join_port.max_length = 5
	_join_port.custom_minimum_size = Vector2(140, 0)
	_join_port.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	for e in [name_edit, _join_address, _join_port]:
		e.text_submitted.connect(func(_t): _on_join())
	content.add_child(_form([["Your name", name_edit], ["Host address", _join_address], ["Port (UDP)", _join_port]]))
	content.add_child(_note("Ask the host for the address on their Host screen. Same Wi-Fi: 192.168.x.x. "
		+ "Over the internet: their Tailscale (100.x) or Radmin VPN (26.x) address. Same PC: 127.0.0.1."))
	var row := _footer(content)
	var go := _button("Join", _on_join, "Big")
	row.add_child(go)
	_focus["join"] = _join_address
	return w[0]


func _build_lobby() -> Control:
	var w := _window("THE CAMP", Vector2(900, 540))
	var content: VBoxContainer = w[1]
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 22)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(cols)

	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(left)
	var who := _label("WHO'S HERE", "Small")
	who.add_theme_color_override("font_color", UiTheme.GOLD)
	left.add_child(who)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(scroll)
	_lobby_list = VBoxContainer.new()
	_lobby_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_lobby_list.add_theme_constant_override("separation", 8)
	scroll.add_child(_lobby_list)
	_lobby_count = _label("", "Dim")
	left.add_child(_lobby_count)

	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(320, 0)
	cols.add_child(right)
	var info := PanelContainer.new()
	info.theme_type_variation = "Inset"
	right.add_child(info)
	_lobby_info = _label("", "")
	_lobby_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_lobby_info.add_theme_font_size_override("font_size", 18)
	info.add_child(_lobby_info)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(spacer)
	_ready_button = Button.new()
	_ready_button.toggle_mode = true
	_ready_button.theme_type_variation = "Big"
	_ready_button.toggled.connect(_on_ready_toggled)
	right.add_child(_ready_button)
	_start_button = _button("Start the day!", _on_start, "Big")
	right.add_child(_start_button)
	right.add_child(_button("Leave", func(): _confirm("Leave the camp and go back to the main menu?", "Leave", _leave),
		"Danger"))
	_focus["lobby"] = _ready_button
	return w[0]


func _build_settings() -> Control:
	var w := _window("SETTINGS", Vector2(820, 560))
	var content: VBoxContainer = w[1]
	_settings = SettingsPanel.new()
	_settings.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(_settings)
	var row := HBoxContainer.new()
	content.add_child(row)
	var back := _button("Back", _back)
	row.add_child(back)
	var saved := _label("Saved automatically", "Small")
	saved.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	saved.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	saved.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(saved)
	_focus["settings"] = _settings.first_focus
	return w[0]


func _build_controls() -> Control:
	var w := _window("CONTROLS", Vector2(860, 590))
	var content: VBoxContainer = w[1]
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(scroll)
	var grid := Pages.controls()
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(grid)
	var row := HBoxContainer.new()
	content.add_child(row)
	var back := _button("Back", _back)
	row.add_child(back)
	var note := _label("Left mouse also grabs, right mouse also throws.", "Small")
	note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	note.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(note)
	_focus["controls"] = back
	return w[0]


func _build_howto() -> Control:
	var w := _window("HOW TO PLAY", Vector2(900, 560))
	var content: VBoxContainer = w[1]
	_howto_holder = MarginContainer.new()
	_howto_holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(_howto_holder)
	var row := HBoxContainer.new()
	content.add_child(row)
	row.add_child(_button("Back", _back))
	var fill := Control.new()
	fill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(fill)
	_howto_prev = _button("< Prev", func(): _set_howto(_howto_page - 1))
	row.add_child(_howto_prev)
	_howto_label = _label("", "Dim")
	_howto_label.custom_minimum_size = Vector2(90, 0)
	_howto_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_howto_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_howto_label)
	_howto_next = _button("Next >", _on_howto_next)
	row.add_child(_howto_next)
	_focus["howto"] = _howto_next
	_set_howto(0)
	return w[0]


func _set_howto(i: int) -> void:
	_howto_page = clampi(i, 0, Pages.how_to_pages() - 1)
	for c in _howto_holder.get_children():
		c.queue_free()
	_howto_holder.add_child(Pages.how_to_page(_howto_page))
	_howto_label.text = "%d / %d" % [_howto_page + 1, Pages.how_to_pages()]
	_howto_prev.disabled = _howto_page == 0
	_howto_next.text = "Got it" if _howto_page == Pages.how_to_pages() - 1 else "Next >"


func _build_credits() -> Control:
	var w := _window("CREDITS", Vector2(820, 570))
	var content: VBoxContainer = w[1]
	var inset := PanelContainer.new()
	inset.theme_type_variation = "Inset"
	inset.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(inset)
	var text := RichTextLabel.new()
	text.bbcode_enabled = true
	text.scroll_active = true
	text.selection_enabled = false
	text.focus_mode = Control.FOCUS_ALL
	text.text = Pages.credits_bbcode()
	inset.add_child(text)
	var row := HBoxContainer.new()
	content.add_child(row)
	var back := _button("Back", _back)
	row.add_child(back)
	_focus["credits"] = back
	return w[0]


func _build_pause() -> Control:
	var w := _window("PAUSE", Vector2(780, 530))
	var content: VBoxContainer = w[1]
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 24)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(cols)
	var buttons := VBoxContainer.new()
	buttons.custom_minimum_size = Vector2(300, 0)
	buttons.add_theme_constant_override("separation", 10)
	cols.add_child(buttons)
	var resume := _button("Resume", hide_all, "Big")
	buttons.add_child(resume)
	buttons.add_child(_button("Settings", _open.bind("settings")))
	buttons.add_child(_button("Controls", _open.bind("controls")))
	buttons.add_child(_button("Field Journal", _on_journal))
	_cheats_button = _button("Cheats: OFF", func(): Team.request_cheats.rpc_id(1, not Team.cheats))
	buttons.add_child(_cheats_button)
	buttons.add_child(_button("Leave to Menu", func(): _confirm(
		"Leave this game? Your friends keep playing without you.", "Leave", _leave), "Danger"))
	buttons.add_child(_button("Quit to Desktop", func(): _confirm("Quit the game?", "Quit", _quit), "Danger"))
	_focus["pause"] = resume

	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(right)
	var card := PanelContainer.new()
	card.theme_type_variation = "Card"
	right.add_child(card)
	var info := VBoxContainer.new()
	info.add_theme_constant_override("separation", 6)
	card.add_child(info)
	var top := HBoxContainer.new()
	info.add_child(top)
	_pause_day = _label("", "Heading")
	_pause_day.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(_pause_day)
	_pause_cash = _label("", "Heading")
	_pause_cash.add_theme_color_override("font_color", UiTheme.GOLD)
	top.add_child(_pause_cash)
	var fero := HBoxContainer.new()
	info.add_child(fero)
	fero.add_child(Icon.new("fero", 72.0))
	_pause_quota = _label("", "")
	_pause_quota.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_pause_quota.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_pause_quota.custom_minimum_size = Vector2(200, 0)
	_pause_quota.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	fero.add_child(_pause_quota)
	_pause_extra = _label("", "Dim")
	_pause_extra.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_pause_extra.custom_minimum_size = Vector2(200, 0)
	info.add_child(_pause_extra)
	var crew_head := _label("THE CREW", "Small")
	crew_head.add_theme_color_override("font_color", UiTheme.GOLD)
	right.add_child(crew_head)
	_pause_crew = _label("", "")
	_pause_crew.add_theme_font_size_override("font_size", 18)
	right.add_child(_pause_crew)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(spacer)
	var note := _label("The game keeps running while this menu is open. The forest does not wait.", "Small")
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size = Vector2(200, 0)
	right.add_child(note)
	return w[0]


func _build_status() -> void:
	var box := PanelContainer.new()
	box.theme_type_variation = "Inset"
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE, 18)
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_root.add_child(box)
	_status = _label("", "")
	_status.add_theme_font_size_override("font_size", 18)
	box.add_child(_status)
	_status_box = box
	box.visible = false


func _build_confirm() -> void:
	_confirm_box = _full(Control.new())
	_confirm_box.visible = false
	_root.add_child(_confirm_box)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	_confirm_box.add_child(_full(dim))
	var center := _full(CenterContainer.new())
	_confirm_box.add_child(center)
	var panel := PanelContainer.new()
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 22)
	panel.add_child(box)
	_confirm_label = _label("", "")
	_confirm_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_confirm_label.custom_minimum_size = Vector2(440, 0)
	_confirm_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_confirm_label.add_theme_font_size_override("font_size", 22)
	box.add_child(_confirm_label)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 16)
	box.add_child(row)
	row.add_child(_button("Cancel", _on_confirm_cancel))
	_confirm_yes = _button("Yes", _on_confirm_yes, "Danger")
	row.add_child(_confirm_yes)


# --- small helpers ----------------------------------------------------------------


func _label(text: String, variation: String) -> Label:
	var l := Label.new()
	l.text = text
	if not variation.is_empty():
		l.theme_type_variation = variation
	return l


func _button(text: String, action: Callable, variation := "") -> Button:
	var b := Button.new()
	b.text = text
	if not variation.is_empty():
		b.theme_type_variation = variation
	b.pressed.connect(func():
		Sfx.play("ui_click")
		action.call())
	return b


func _note(text: String) -> Control:
	var card := PanelContainer.new()
	card.theme_type_variation = "Card"
	var l := _label(text, "")
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(300, 0)
	l.add_theme_font_size_override("font_size", 17)
	l.add_theme_color_override("font_color", UiTheme.CREAM_DIM)
	card.add_child(l)
	return card


func _form(rows: Array) -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 10)
	for r in rows:
		var l := _label(r[0], "")
		l.custom_minimum_size = Vector2(170, 0)
		grid.add_child(l)
		var c: Control = r[1]
		if c.size_flags_horizontal != Control.SIZE_SHRINK_BEGIN:
			c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(c)
	return grid


func _make_name_edit() -> LineEdit:
	var e := LineEdit.new()
	e.text = _player_name
	e.max_length = 20
	e.placeholder_text = "Your name"
	e.text_changed.connect(_on_name_changed.bind(e))
	_name_edits.append(e)
	return e
