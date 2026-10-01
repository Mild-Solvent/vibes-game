extends CanvasLayer
## Main menu (host / join) and the in-game HUD (show clock, ratings, warnings).

signal host_pressed(player_name: String)
signal join_pressed(player_name: String, address: String)

const ShowDirector := preload("res://scripts/show_director.gd")

var _menu: Control
var _game: Control
var _name_edit: LineEdit
var _address_edit: LineEdit
var _status: Label
var _phase_label: Label
var _ratings: ProgressBar
var _event_label: Label


func _ready() -> void:
	_build_menu()
	_build_game()
	show_menu()


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


func update_show(phase: int, time_left: float, ratings: float, event: int) -> void:
	var secs := maxi(int(ceil(time_left)), 0)
	var clock := "%d:%02d" % [secs / 60, secs % 60]
	match phase:
		ShowDirector.Phase.PREP:
			_phase_label.text = "PREP  %s  -  anchor to the green tape, crew out of shot" % clock
			_phase_label.modulate = Color(1, 0.85, 0.3)
		ShowDirector.Phase.LIVE:
			_phase_label.text = "● ON AIR  %s" % clock
			_phase_label.modulate = Color(1, 0.35, 0.35)
		ShowDirector.Phase.WRAP:
			_phase_label.text = "WRAP  -  final ratings %d%%" % int(ratings)
			_phase_label.modulate = Color(0.8, 0.8, 0.8)
	_ratings.value = ratings
	match event:
		ShowDirector.Event.DEAD_AIR:
			_event_label.text = "DEAD AIR! Nobody is at the desk!"
		ShowDirector.Event.CREW_IN_SHOT:
			_event_label.text = "CREW IN SHOT! Get out of the frame!"
		_:
			_event_label.text = ""


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

	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(420, 0)
	box.add_theme_constant_override("separation", 10)
	center.add_child(box)

	var title := _label("STANDBY... GO!", 48)
	box.add_child(title)
	box.add_child(_label("Everyone's watching. Nobody's ready.", 18))

	box.add_child(_label("Your name", 16, HORIZONTAL_ALIGNMENT_LEFT))
	_name_edit = LineEdit.new()
	_name_edit.text = "Crew %d" % randi_range(1, 99)
	_name_edit.max_length = 20
	box.add_child(_name_edit)

	box.add_child(_label("Host address (to join)", 16, HORIZONTAL_ALIGNMENT_LEFT))
	_address_edit = LineEdit.new()
	_address_edit.text = "127.0.0.1"
	box.add_child(_address_edit)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 10)
	box.add_child(buttons)
	var host_button := Button.new()
	host_button.text = "Host (port %d)" % Net.DEFAULT_PORT
	host_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	host_button.pressed.connect(func(): host_pressed.emit(_name_edit.text))
	buttons.add_child(host_button)
	var join_button := Button.new()
	join_button.text = "Join"
	join_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	join_button.pressed.connect(func(): join_pressed.emit(_name_edit.text, _address_edit.text.strip_edges()))
	buttons.add_child(join_button)

	_status = _label("", 16)
	box.add_child(_status)
	var controls := "WASD move · Shift sprint · Space jump\n"
	controls += "E / left click grab & drop · Q / right click throw\n"
	controls += "Esc frees the mouse, click to recapture"
	box.add_child(_label(controls, 14))


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

	_phase_label = _label("", 24)
	top.add_child(_phase_label)

	_ratings = ProgressBar.new()
	_ratings.custom_minimum_size = Vector2(320, 18)
	_ratings.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_ratings.show_percentage = false
	_ratings.max_value = 100
	_ratings.value = 50
	_ratings.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(_ratings)
	top.add_child(_label("RATINGS", 12))

	_event_label = _label("", 30)
	_event_label.modulate = Color(1, 0.25, 0.25)
	top.add_child(_event_label)

	var crosshair_holder := CenterContainer.new()
	crosshair_holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	crosshair_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_game.add_child(crosshair_holder)
	crosshair_holder.add_child(_label("+", 22))

	var help := _label("E grab · Q throw · Esc mouse", 14, HORIZONTAL_ALIGNMENT_LEFT)
	help.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_MINSIZE, 12)
	help.modulate = Color(1, 1, 1, 0.6)
	_game.add_child(help)


func _label(text: String, size: int, align := HORIZONTAL_ALIGNMENT_CENTER) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = align
	label.add_theme_font_size_override("font_size", size)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label
