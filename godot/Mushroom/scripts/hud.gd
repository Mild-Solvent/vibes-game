extends CanvasLayer
## Main menu (host / join), the intro story, and the in-game HUD: day and cash, your status,
## inventory and flashlight, what the crosshair is on, toasts, and the field journal (J).

signal host_pressed(player_name: String, mode: int)
signal join_pressed(player_name: String, address: String)

const TRIP_SHADER := """
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture;
uniform float strength = 0.0;
uniform float dark = 0.0;
uniform vec3 tint = vec3(1.0);
void fragment() {
	vec2 uv = SCREEN_UV;
	uv.x += sin(uv.y * 14.0 + TIME * 2.3) * 0.012 * strength;
	uv.y += cos(uv.x * 11.0 + TIME * 1.7) * 0.012 * strength;
	vec3 c = texture(screen_tex, uv).rgb;
	vec3 ghost = texture(screen_tex, uv + vec2(sin(TIME) * 0.02, cos(TIME * 0.7) * 0.02) * strength).rgb;
	float t = sin(TIME * 0.9) * 0.5 + 0.5;
	vec3 hue = mix(c.gbr, c.brg, t);
	c = mix(c, mix(hue, ghost, 0.35), strength) * tint;
	float v = distance(SCREEN_UV, vec2(0.5));
	c *= 1.0 - dark * smoothstep(0.15, 0.7, v);
	COLOR = vec4(c, 1.0);
}
"""
const INTRO := [
	"Four friends lost their jobs on the same Monday.",
	"Rent was due Tuesday. By Wednesday they lived in a junk camp in the forest.",
	"They can't do anything useful. But the forest is full of weird mushrooms,\nand the village pays for the good ones.",
	"Nobody knows which ones are good.\nSo somebody has to taste them.",
	"Pick mushrooms (E). Taste one (F) to identify its kind. Fill the basket.\nDrive it to the village and sell it to Babka Hela. Don't die. Probably.",
]

var _menu: Control
var _game: Control
var _name_edit: LineEdit
var _address_edit: LineEdit
var _mode_select: OptionButton
var _status: Label
var _phase_label: Label
var _cash_label: Label
var _status_label: Label
var _inventory_label: Label
var _hint: Label
var _guide: Label
var _toast: Label
var _effect: ColorRect
var _intro: Control
var _intro_label: Label
var _intro_index := -1
var _intro_left := 0.0
var _toast_left := 0.0
var intro_enabled := true


func _ready() -> void:
	add_to_group("hud")
	_build_menu()
	_build_game()
	show_menu()
	Team.toast.connect(show_toast)


func _process(delta: float) -> void:
	if _toast_left > 0.0:
		_toast_left -= delta
		_toast.visible = _toast_left > 0.0
	if _intro_index >= 0:
		_intro_left -= delta
		if _intro_left <= 0.0:
			_next_intro()
	if _game.visible:
		_update_game()


func _unhandled_input(event: InputEvent) -> void:
	if _intro_index >= 0 and (event.is_action_pressed("jump") or event.is_action_pressed("grab")):
		_next_intro()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("journal"):
		_guide.visible = not _guide.visible


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
	_intro_index = -1
	if intro_enabled:
		_next_intro()


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


func update_state(phase_text: String, _score_name: String, _score: float, _event_text: String, guide: String) -> void:
	_phase_label.text = phase_text
	_guide.text = guide


func show_toast(text: String) -> void:
	if text.is_empty():
		return
	_toast.text = text
	_toast.visible = true
	_toast_left = 6.0


func _next_intro() -> void:
	_intro_index += 1
	if _intro_index >= INTRO.size():
		_intro_index = -1
		_intro.visible = false
		return
	_intro.visible = true
	_intro_label.text = INTRO[_intro_index]
	_intro_left = 7.0


func _local_player() -> Node:
	for p in get_tree().get_nodes_in_group("players"):
		if p.is_multiplayer_authority():
			return p
	return null


func _update_game() -> void:
	_cash_label.text = "DAY %d     %d €" % [Team.day, Team.cash]
	var me := _local_player()
	if me == null:
		return
	var id: int = me.peer_id
	var status := Team.status_of(id)
	var left := int(ceil(Team.time_left(id)))
	var mat := _effect.material as ShaderMaterial
	var strength := 0.0
	var dark := 0.0
	var tint := Color.WHITE
	match status:
		Team.Status.TRIPPING:
			strength = clampf(Team.time_left(id) / 5.0, 0.0, 1.0)
			_status_label.text = "TRIPPING (%d s)" % left
		Team.Status.PASSED_OUT:
			strength = 1.0
			dark = 0.9
			_status_label.text = "PASSED OUT (%d s)... the colours, man" % left
		Team.Status.POISONED:
			tint = Color(0.75, 1.0, 0.7)
			dark = 0.5 * (1.0 - Team.time_left(id) / Team.POISON_SECONDS)
			_status_label.text = "POISONED - dead in %d s - get a MEDKIT (H)" % left
		Team.Status.DEAD:
			tint = Color(0.55, 0.6, 0.75)
			_status_label.text = "YOU'RE DEAD. Float around as a ghost.\nThe witch can bring you back (2 Witch's fingers + 1 Glowcap)."
		_:
			_status_label.text = ""
	_effect.visible = strength > 0.0 or dark > 0.0 or tint != Color.WHITE
	mat.set_shader_parameter("strength", strength)
	mat.set_shader_parameter("dark", dark)
	mat.set_shader_parameter("tint", Vector3(tint.r, tint.g, tint.b))
	_inventory_label.text = "Medkits: %d   Batteries: %d   Flashlight (T): %d%%" % [
		Team.count(id, "medkit"), Team.count(id, "battery"), int(me.battery * 100.0)
	]
	_hint.text = me.look_hint()


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

	box.add_child(_label(ProjectSettings.get_setting("application/config/name"), 48))
	box.add_child(_label(ProjectSettings.get_setting("application/config/description"), 16))

	box.add_child(_label("Your name", 16, HORIZONTAL_ALIGNMENT_LEFT))
	_name_edit = LineEdit.new()
	_name_edit.text = "Friend %d" % randi_range(1, 99)
	_name_edit.max_length = 20
	box.add_child(_name_edit)

	_mode_select = OptionButton.new()
	_mode_select.visible = false  # one world, nothing to pick
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
	host_button.pressed.connect(func(): host_pressed.emit(_name_edit.text, 0))
	buttons.add_child(host_button)
	var join_button := Button.new()
	join_button.text = "Join"
	join_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	join_button.pressed.connect(func(): join_pressed.emit(_name_edit.text, _address_edit.text.strip_edges()))
	buttons.add_child(join_button)

	_status = _label("", 16)
	box.add_child(_status)
	var controls := "WASD move · Shift sprint · Space jump/swim · E grab, use, get in the car\n"
	controls += "Q throw · F taste / use · R or wheel turn what you hold · H medkit · T flashlight\n"
	controls += "J journal · Esc frees the mouse"
	box.add_child(_label(controls, 14))


func _build_game() -> void:
	_game = Control.new()
	_game.set_anchors_preset(Control.PRESET_FULL_RECT)
	_game.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_game)

	_effect = ColorRect.new()
	_effect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_effect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shader := Shader.new()
	shader.code = TRIP_SHADER
	var mat := ShaderMaterial.new()
	mat.shader = shader
	_effect.material = mat
	_effect.visible = false
	_game.add_child(_effect)

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
	_status_label = _label("", 26)
	_status_label.modulate = Color(1, 0.35, 0.35)
	top.add_child(_status_label)
	_toast = _label("", 22)
	_toast.modulate = Color(1, 0.9, 0.5)
	_toast.visible = false
	_toast.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	top.add_child(_toast)

	_cash_label = _label("", 26, HORIZONTAL_ALIGNMENT_RIGHT)
	_cash_label.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_cash_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, 14)
	_cash_label.modulate = Color(1, 0.95, 0.6)
	_game.add_child(_cash_label)

	var crosshair_holder := CenterContainer.new()
	crosshair_holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	crosshair_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_game.add_child(crosshair_holder)
	var cross := VBoxContainer.new()
	cross.mouse_filter = Control.MOUSE_FILTER_IGNORE
	crosshair_holder.add_child(cross)
	cross.add_child(_label("+", 22))
	_hint = _label("", 16)
	_hint.modulate = Color(1, 1, 1, 0.85)
	cross.add_child(_hint)

	_inventory_label = _label("", 15, HORIZONTAL_ALIGNMENT_LEFT)
	_inventory_label.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_inventory_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_MINSIZE, 12)
	_game.add_child(_inventory_label)

	_guide = _label("", 13, HORIZONTAL_ALIGNMENT_RIGHT)
	_guide.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_guide.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_guide.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, 12)
	_guide.modulate = Color(0.85, 1, 0.85, 0.9)
	_game.add_child(_guide)

	_intro = ColorRect.new()
	(_intro as ColorRect).color = Color(0, 0, 0, 0.85)
	_intro.set_anchors_preset(Control.PRESET_FULL_RECT)
	_intro.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_intro.visible = false
	_game.add_child(_intro)
	var intro_center := CenterContainer.new()
	intro_center.set_anchors_preset(Control.PRESET_FULL_RECT)
	intro_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_intro.add_child(intro_center)
	var intro_box := VBoxContainer.new()
	intro_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	intro_center.add_child(intro_box)
	_intro_label = _label("", 30)
	intro_box.add_child(_intro_label)
	var skip := _label("Space / E: next", 14)
	skip.modulate = Color(1, 1, 1, 0.5)
	intro_box.add_child(skip)


func _label(text: String, size: int, align := HORIZONTAL_ALIGNMENT_CENTER) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = align
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_constant_override("outline_size", 6)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label
