extends CanvasLayer
## Main menu (pick a show, host / join) and the in-game HUD.

signal host_pressed(player_name: String, mode: int)
signal join_pressed(player_name: String, address: String)

const TRIP_SECONDS := 25.0
const TRIP_SHADER := """
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture;
uniform float strength = 0.0;
void fragment() {
	vec2 uv = SCREEN_UV;
	uv.x += sin(uv.y * 14.0 + TIME * 2.3) * 0.012 * strength;
	uv.y += cos(uv.x * 11.0 + TIME * 1.7) * 0.012 * strength;
	vec3 c = texture(screen_tex, uv).rgb;
	vec3 ghost = texture(screen_tex, uv + vec2(sin(TIME) * 0.02, cos(TIME * 0.7) * 0.02) * strength).rgb;
	float t = sin(TIME * 0.9) * 0.5 + 0.5;
	vec3 hue = mix(c.gbr, c.brg, t);
	COLOR = vec4(mix(c, mix(hue, ghost, 0.35), strength), 1.0);
}
"""

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
var _trip_rect: ColorRect
var _trip_left := 0.0
var _toast_left := 0.0


func _ready() -> void:
	add_to_group("hud")
	_build_menu()
	_build_game()
	show_menu()


func _process(delta: float) -> void:
	if _trip_left > 0.0:
		_trip_left -= delta
		var strength := clampf(_trip_left / 4.0, 0.0, 1.0)  # fades out over the last 4 s
		_trip_rect.visible = _trip_left > 0.0
		(_trip_rect.material as ShaderMaterial).set_shader_parameter("strength", strength)
	if _toast_left > 0.0:
		_toast_left -= delta
		_toast.visible = _toast_left > 0.0


func set_levels(titles: Array) -> void:
	_mode_select.clear()
	for t in titles:
		_mode_select.add_item(t)


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


## Called through the "hud" group when this player tasted a mushroom.
func on_tasted(edible: bool, mushroom_name: String) -> void:
	if edible:
		_show_toast("Mmm. %s. Tasty, and you're fine." % mushroom_name)
	else:
		_show_toast("That was a %s..." % mushroom_name)
		_trip_left = TRIP_SECONDS


func _show_toast(text: String) -> void:
	_toast.text = text
	_toast.visible = true
	_toast_left = 4.0


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
	box.custom_minimum_size = Vector2(440, 0)
	box.add_theme_constant_override("separation", 10)
	center.add_child(box)

	box.add_child(_label("STANDBY... GO!", 48))
	box.add_child(_label("Friendslop demos. Everyone's watching. Nobody's ready.", 16))

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
	host_button.text = "Host (port %d)" % Net.DEFAULT_PORT
	host_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	host_button.pressed.connect(func(): host_pressed.emit(_name_edit.text, _mode_select.selected))
	buttons.add_child(host_button)
	var join_button := Button.new()
	join_button.text = "Join"
	join_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	join_button.pressed.connect(func(): join_pressed.emit(_name_edit.text, _address_edit.text.strip_edges()))
	buttons.add_child(join_button)

	_status = _label("", 16)
	box.add_child(_status)
	var controls := "WASD move · Shift sprint · Space jump\n"
	controls += "E / left click grab & drop · Q / right click throw · F taste\n"
	controls += "Esc frees the mouse, click to recapture"
	box.add_child(_label(controls, 14))


func _build_game() -> void:
	_game = Control.new()
	_game.set_anchors_preset(Control.PRESET_FULL_RECT)
	_game.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_game)

	_trip_rect = ColorRect.new()
	_trip_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_trip_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shader := Shader.new()
	shader.code = TRIP_SHADER
	var mat := ShaderMaterial.new()
	mat.shader = shader
	_trip_rect.material = mat
	_trip_rect.visible = false
	_game.add_child(_trip_rect)

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

	var help := _label("E grab · Q throw · F taste · Esc mouse", 14, HORIZONTAL_ALIGNMENT_LEFT)
	help.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_MINSIZE, 12)
	help.modulate = Color(1, 1, 1, 0.6)
	_game.add_child(help)

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
