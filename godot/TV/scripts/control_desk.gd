extends StaticBody3D
## The control room desk. Press E at it to sit down (any number of people can); you get the
## gallery UI: the PROGRAM feed, a preview of every camera with TAKE buttons, the RECORD button
## and the teleprompter / subtitle keyboard. Everything is a request to the host through the
## studio (`studio.request_take`, `request_record`, `request_subtitle`); the host broadcasts it.

var studio: Node  # the studio level (owns the show state and the broadcast)

var _ui: CanvasLayer
var _program: TextureRect
var _take_buttons: Array[Button] = []
var _previews: Array[TextureRect] = []
var _rec_button: Button
var _rec_label: Label
var _prompter: LineEdit
var _player: Node
var _send_timer := 0.0
var _pending_text := ""
var _dirty := false


func setup(level: Node, size: Vector3) -> void:
	studio = level
	name = "ControlDesk"
	var shape := BoxShape3D.new()
	shape.size = size
	var collision := CollisionShape3D.new()
	collision.shape = shape
	add_child(collision)


func interact_prompt(_player_node: Node) -> String:
	return "E  sit at the control desk (TAKE cameras, RECORD, teleprompter)"


func interact(player: Node) -> void:
	player.sit(self)


func seat_enter(player: Node) -> void:
	_player = player
	player.global_position = global_position + Vector3(0, -0.4, -1.1)
	player.rotation.y = PI  # face the desk (+Z)
	if _ui == null:
		_build_ui()
	_ui.visible = true
	_prompter.text = studio.subtitle
	studio.broadcast.set_previews(true)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func seat_exit(_player_node: Node, _notify: bool) -> void:
	_flush_text()
	_player = null
	_ui.visible = false
	_prompter.release_focus()
	studio.broadcast.set_previews(false)


func seat_help() -> String:
	return "1-4 TAKE · R record · type in the box · Esc leave"


func seat_status() -> String:
	return ""


## Keys that reach us here are the ones the text box didn't eat.
func seat_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	var key: Key = event.physical_keycode
	if key >= KEY_1 and key <= KEY_9:
		studio.request_take.rpc_id(1, key - KEY_1)
	elif key == KEY_R:
		studio.request_record.rpc_id(1, not studio.recording)
	elif key == KEY_T or key == KEY_ENTER:
		_prompter.grab_focus()


func _input(event: InputEvent) -> void:
	if _ui == null or not _ui.visible or _player == null:
		return
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_player.stand_up()


func _process(delta: float) -> void:
	if _ui == null or not _ui.visible:
		return
	var broadcast: Node = studio.broadcast
	for i in _take_buttons.size():
		var on_air: bool = i == studio.take
		_take_buttons[i].text = "%s%d  %s" % ["● " if on_air else "TAKE ", i + 1, broadcast.sources[i].label]
		_take_buttons[i].modulate = Color(1, 0.45, 0.45) if on_air else Color.WHITE
	_rec_button.text = "■ STOP (R)" if studio.recording else "● REC (R)"
	_rec_button.modulate = Color(1, 0.4, 0.4) if studio.recording else Color.WHITE
	var secs := int(broadcast.recorded_seconds())
	_rec_label.text = "tape %d:%02d%s" % [secs / 60, secs % 60, "" if studio.is_live() else "  (records while LIVE)"]
	if _dirty:
		_send_timer -= delta
		if _send_timer <= 0.0:
			_flush_text()


func _flush_text() -> void:
	if not _dirty:
		return
	_dirty = false
	_send_timer = 0.1
	studio.request_subtitle.rpc_id(1, _pending_text)


func _on_text_changed(text: String) -> void:
	_pending_text = text
	_dirty = true


## Enter: the line has been read, clear the box for the next one (the old line stays on air
## until you type the next).
func _on_text_submitted(_text: String) -> void:
	_prompter.text = ""


func _build_ui() -> void:
	_ui = CanvasLayer.new()
	_ui.layer = 5
	add_child(_ui)
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 24)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.06, 0.09, 0.94)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(16)
	panel.add_theme_stylebox_override("panel", style)
	_ui.add_child(panel)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	panel.add_child(root)
	root.add_child(_label("CHANNEL 6  -  GALLERY", 22))

	var row := HBoxContainer.new()
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 14)
	root.add_child(row)

	var program_box := VBoxContainer.new()
	program_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	program_box.size_flags_stretch_ratio = 1.6
	row.add_child(program_box)
	program_box.add_child(_label("PROGRAM (what the viewers see)", 14))
	_program = TextureRect.new()
	_program.texture = studio.broadcast.texture()
	_program.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_program.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_program.size_flags_vertical = Control.SIZE_EXPAND_FILL
	program_box.add_child(_program)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	row.add_child(grid)
	for i in studio.broadcast.sources.size():
		var cell := VBoxContainer.new()
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(cell)
		var preview := TextureRect.new()
		preview.texture = studio.broadcast.source_texture(i)
		preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		preview.custom_minimum_size = Vector2(200, 112)
		cell.add_child(preview)
		_previews.append(preview)
		var take := Button.new()
		take.focus_mode = Control.FOCUS_NONE
		take.pressed.connect(func(): studio.request_take.rpc_id(1, i))
		cell.add_child(take)
		_take_buttons.append(take)

	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 10)
	root.add_child(bottom)
	_rec_button = Button.new()
	_rec_button.focus_mode = Control.FOCUS_NONE
	_rec_button.custom_minimum_size = Vector2(130, 0)
	_rec_button.pressed.connect(func(): studio.request_record.rpc_id(1, not studio.recording))
	bottom.add_child(_rec_button)
	_rec_label = _label("", 14)
	_rec_label.custom_minimum_size = Vector2(150, 0)
	bottom.add_child(_rec_label)
	_prompter = LineEdit.new()
	_prompter.placeholder_text = "Teleprompter / subtitles: type here (T), it goes on air live. Enter = next line."
	_prompter.max_length = 90
	if "keep_editing_on_text_submit" in _prompter:
		_prompter.set("keep_editing_on_text_submit", true)
	_prompter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_prompter.text_changed.connect(_on_text_changed)
	_prompter.text_submitted.connect(_on_text_submitted)
	bottom.add_child(_prompter)
	var clear := Button.new()
	clear.text = "Clear"
	clear.focus_mode = Control.FOCUS_NONE
	clear.pressed.connect(func():
		_prompter.text = ""
		_on_text_changed(""))
	bottom.add_child(clear)
	var leave := Button.new()
	leave.text = "Leave (Esc)"
	leave.focus_mode = Control.FOCUS_NONE
	leave.pressed.connect(func(): _player.stand_up())
	bottom.add_child(leave)
	root.add_child(_label("1-4 TAKE a camera · R record · T type · Esc leave", 13))


func _label(text: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	return label
