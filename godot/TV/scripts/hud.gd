extends CanvasLayer
## Main menu (pick a show, host / join) and the in-game HUD.

signal host_pressed(player_name: String, mode: int)
signal join_pressed(player_name: String, address: String)

const GENERAL_RULES := """[b]STANDBY... GO![/b]   Everyone's watching. Nobody's ready.

You are the crew of a live show. Every round goes [b]PREP[/b] (get in position) -> [b]LIVE[/b] (the show
runs and the meter moves) -> [b]WRAP[/b] (final score), then the next round starts.
The host picks the show in the menu; everyone else joins the host's IP.

[b]CONTROLS (every show)[/b]
 - WASD / arrows: walk.  Shift: sprint.  Space: jump.  Mouse: look.
 - E: use the thing you look at (sit at a desk, take a camera) or grab / drop a prop.
 - Left click: grab / drop.  Q or right click: throw what you hold.
 - Esc: leave a seat, or free the mouse (click the game to recapture it).

Each show has its own tab with the roles, the goal and its extra controls."""

var _menu: Control
var _game: Control
var _name_edit: LineEdit
var _address_edit: LineEdit
var _mode_select: OptionButton
var _status: Label
var _phase_label: Label
var _score_name: Label
var _score: ProgressBar
var _event_label: Label
var _guide: Label
var _toast: Label
var _prompt: Label
var _help: Label
var _rules_panel: Control
var _menu_center: Control
var _rules_tabs: TabContainer
var _toast_left := 0.0


func _ready() -> void:
	add_to_group("hud")
	_build_menu()
	_build_game()
	show_menu()


func _process(delta: float) -> void:
	if _toast_left > 0.0:
		_toast_left -= delta
		_toast.visible = _toast_left > 0.0


## `titles` and `rules` are parallel arrays, one entry per level (show).
func set_levels(titles: Array, rules: Array = []) -> void:
	_mode_select.clear()
	for t in titles:
		_mode_select.add_item(t)
	for child in _rules_tabs.get_children():
		if child.name != "General":
			child.queue_free()
	for i in rules.size():
		var page := _rules_page(rules[i])
		page.name = str(titles[i]).get_slice(" (", 0)
		_rules_tabs.add_child(page)


func show_menu() -> void:
	_menu.visible = true
	_game.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func show_game() -> void:
	_menu.visible = false
	_game.visible = true


func set_status(text: String) -> void:
	_status.text = text


func set_player_name(player_name: String) -> void:
	_name_edit.text = player_name


func get_player_name() -> String:
	return _name_edit.text


func set_mode(mode: int) -> void:
	_mode_select.select(mode)


func get_mode() -> int:
	return _mode_select.selected


func update_state(phase_text: String, score_name: String, score: float, event_text: String, guide: String) -> void:
	_phase_label.text = phase_text
	_score_name.text = score_name
	_score.value = score
	_event_label.text = event_text
	_guide.text = guide


## What pressing E would do right now (empty hides it). Set every frame by the local player.
func set_prompt(text: String) -> void:
	_prompt.text = text


## Bottom-left key help; levels and seats change it.
func set_help(text: String) -> void:
	_help.text = text


func show_toast(text: String, seconds := 4.0) -> void:
	_toast.text = text
	_toast.visible = true
	_toast_left = seconds


func show_rules(open := true) -> void:
	_rules_panel.visible = open
	_menu_center.visible = not open


func _build_menu() -> void:
	_menu = Control.new()
	_menu.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_menu)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_menu.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_menu.add_child(center)
	_menu_center = center

	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(440, 0)
	box.add_theme_constant_override("separation", 10)
	center.add_child(box)

	box.add_child(_label(ProjectSettings.get_setting("application/config/name"), 48))
	box.add_child(_label(ProjectSettings.get_setting("application/config/description"), 16))

	box.add_child(_label("Your name", 16, HORIZONTAL_ALIGNMENT_LEFT))
	_name_edit = LineEdit.new()
	_name_edit.text = "Crew %d" % randi_range(1, 99)
	_name_edit.max_length = 20
	box.add_child(_name_edit)

	box.add_child(_label("Show (host picks)", 16, HORIZONTAL_ALIGNMENT_LEFT))
	_mode_select = OptionButton.new()
	box.add_child(_mode_select)

	box.add_child(_label("Host address (to join)", 16, HORIZONTAL_ALIGNMENT_LEFT))
	_address_edit = LineEdit.new()
	_address_edit.text = "127.0.0.1"
	box.add_child(_address_edit)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 10)
	box.add_child(buttons)
	var host_button := Button.new()
	host_button.text = "Host (port %d)" % Net.port
	host_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	host_button.pressed.connect(func(): host_pressed.emit(_name_edit.text, _mode_select.selected))
	buttons.add_child(host_button)
	var join_button := Button.new()
	join_button.text = "Join"
	join_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	join_button.pressed.connect(func(): join_pressed.emit(_name_edit.text, _address_edit.text.strip_edges()))
	buttons.add_child(join_button)

	var rules_button := Button.new()
	rules_button.text = "RULES & CONTROLS"
	rules_button.pressed.connect(show_rules)
	box.add_child(rules_button)

	_status = _label("", 16)
	box.add_child(_status)

	_build_rules()


## A full-screen panel with one tab of rules per show, opened from the menu.
func _build_rules() -> void:
	_rules_panel = PanelContainer.new()
	_rules_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 40)
	_rules_panel.visible = false
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.08, 0.12, 0.97)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(24)
	_rules_panel.add_theme_stylebox_override("panel", style)
	_menu.add_child(_rules_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	_rules_panel.add_child(box)
	box.add_child(_label("RULES", 32))
	_rules_tabs = TabContainer.new()
	_rules_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(_rules_tabs)
	var general := _rules_page(GENERAL_RULES)
	general.name = "General"
	_rules_tabs.add_child(general)
	var close := Button.new()
	close.text = "Back"
	close.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	close.custom_minimum_size = Vector2(200, 0)
	close.pressed.connect(show_rules.bind(false))
	box.add_child(close)


func _rules_page(bbcode: String) -> RichTextLabel:
	var text := RichTextLabel.new()
	text.bbcode_enabled = true
	text.text = bbcode
	text.add_theme_font_size_override("normal_font_size", 17)
	text.add_theme_font_size_override("bold_font_size", 18)
	text.add_theme_constant_override("line_separation", 3)
	return text


func _build_game() -> void:
	_game = Control.new()
	_game.set_anchors_preset(Control.PRESET_FULL_RECT)
	_game.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_game)

	var top := VBoxContainer.new()
	top.set_anchors_preset(Control.PRESET_FULL_RECT)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_theme_constant_override("separation", 6)
	_game.add_child(top)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 8)
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(spacer)

	_phase_label = _label("", 22)
	top.add_child(_phase_label)

	_score = ProgressBar.new()
	_score.custom_minimum_size = Vector2(320, 18)
	_score.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_score.show_percentage = false
	_score.max_value = 100
	_score.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(_score)
	_score_name = _label("", 12)
	top.add_child(_score_name)

	_event_label = _label("", 30)
	_event_label.modulate = Color(1, 0.25, 0.25)
	top.add_child(_event_label)

	_toast = _label("", 22)
	_toast.modulate = Color(1, 0.9, 0.5)
	_toast.visible = false
	top.add_child(_toast)

	var crosshair_holder := CenterContainer.new()
	crosshair_holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	crosshair_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_game.add_child(crosshair_holder)
	crosshair_holder.add_child(_label("+", 22))

	_prompt = _label("", 18)
	_prompt.set_anchors_preset(Control.PRESET_CENTER)
	_prompt.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_prompt.position.y += 28
	_prompt.modulate = Color(1, 1, 0.7)
	_prompt.add_theme_constant_override("outline_size", 6)
	_game.add_child(_prompt)

	_help = _label("E use / grab · Q throw · Esc mouse", 14, HORIZONTAL_ALIGNMENT_LEFT)
	_help.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_help.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_MINSIZE, 12)
	_help.modulate = Color(1, 1, 1, 0.6)
	_game.add_child(_help)

	_guide = _label("", 13, HORIZONTAL_ALIGNMENT_RIGHT)
	_guide.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_guide.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_guide.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, 12)
	_guide.modulate = Color(0.85, 1, 0.85, 0.85)
	_game.add_child(_guide)


func _label(text: String, size: int, align := HORIZONTAL_ALIGNMENT_CENTER) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = align
	label.add_theme_font_size_override("font_size", size)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label
