extends Control
## Getting yourself out of a trap, alone. A friend pressing E on you is always faster.
## - Mud: wiggle out in rhythm. Press A, then D, then A... each time the marker is in the green
##   window. A miss sinks you deeper; sink all the way and you drown in it.
## - Bear trap: like picking a lock. Move the mouse to turn the dial and feel for the sweet spot
##   (the bar warms up), then hold SPACE to prise the jaws open. Hold it in the wrong place and
##   the jaws snap back: you pass out from the pain.
## Holes have no minigame: you need a friend with a rope.

const MUD_NEEDED := 7
const MUD_MISSES := 7
const MUD_GRACE := 2.0  # seconds after getting stuck before presses count (you were just walking)
const BEAR_HOLD := 1.4
const BEAR_SWEET := 0.22  # radians either side of the sweet spot

var _kind := ""
var _t := 0.0
# mud
var _progress := 0
var _misses := 0
var _expect_a := true
var _last_press := 0
# bear trap
var _dial := 0.0
var _sweet := 0.0
var _hold := 0.0
var _wrong_hold := 0.0
var _rng := RandomNumberGenerator.new()

var _title: Label
var _prompt: Label
var _bar: ProgressBar
var _info: Label
var _marker: ColorRect
var _window: ColorRect
var _track: ColorRect


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rng.randomize()
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.grow_vertical = Control.GROW_DIRECTION_BOTH
	box.position.y += 140
	box.add_theme_constant_override("separation", 10)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)
	_title = _make_label(30, Color(1, 0.75, 0.3))
	box.add_child(_title)
	_prompt = _make_label(64, Color(1, 1, 1))
	box.add_child(_prompt)
	_track = ColorRect.new()
	_track.custom_minimum_size = Vector2(520, 26)
	_track.color = Color(0.1, 0.08, 0.06, 0.85)
	_track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_track)
	_window = ColorRect.new()
	_window.color = Color(0.3, 0.8, 0.3, 0.8)
	_window.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_track.add_child(_window)
	_marker = ColorRect.new()
	_marker.color = Color(1, 0.95, 0.6)
	_marker.size = Vector2(8, 34)
	_marker.position.y = -4
	_marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_track.add_child(_marker)
	_bar = ProgressBar.new()
	_bar.custom_minimum_size = Vector2(520, 18)
	_bar.show_percentage = false
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_bar)
	_info = _make_label(18, Color(0.9, 0.9, 0.85))
	box.add_child(_info)
	visible = false


func _make_label(size: int, colour: Color) -> Label:
	var label := Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_constant_override("outline_size", 8)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.modulate = colour
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _local_player() -> Node:
	for p in get_tree().get_nodes_in_group("players"):
		if p.is_multiplayer_authority():
			return p
	return null


func _process(delta: float) -> void:
	var me := _local_player()
	var kind := ""
	if me and Team.is_alive(me.peer_id) and Team.status_of(me.peer_id) != Team.Status.PASSED_OUT:
		kind = Team.stuck_in(me.peer_id)
	if kind != _kind:
		_start(kind)
	visible = kind == "mud" or kind == "bear trap"
	if not visible:
		return
	_t += delta
	if _kind == "mud":
		_update_mud()
	else:
		_update_bear(delta)


func _start(kind: String) -> void:
	_kind = kind
	_t = 0.0
	_progress = 0
	_misses = 0
	_expect_a = true
	_dial = 0.0
	_sweet = _rng.randf() * TAU
	_hold = 0.0
	_wrong_hold = 0.0


# --- mud ---------------------------------------------------------------------------------


func _mud_cursor() -> float:
	var speed := 1.6 + _progress * 0.18
	return sin(_t * speed * PI) * 0.5 + 0.5


func _update_mud() -> void:
	_title.text = "STUCK IN THE MUD - wiggle out!"
	_prompt.text = "A" if _expect_a else "D"
	_window.visible = true
	_window.position = Vector2(_track.size.x * 0.36, 0)
	_window.size = Vector2(_track.size.x * 0.28, _track.size.y)
	_marker.position.x = _mud_cursor() * (_track.size.x - _marker.size.x)
	_bar.value = 100.0 * _progress / MUD_NEEDED
	_info.text = ("Get ready..." if _t < MUD_GRACE else "Tap the letter ONCE when the marker is in the green.") + "   %d/%d   sunk: %s" % [
		_progress, MUD_NEEDED, "▮".repeat(_misses) + "▯".repeat(MUD_MISSES - _misses)]


func _mud_press(is_a: bool) -> void:
	if _t < MUD_GRACE:
		return
	var now := Time.get_ticks_msec()
	var mashing := now - _last_press < 220  # held-down / mashed walking keys don't count
	_last_press = now
	var c := _mud_cursor()
	if is_a == _expect_a and c > 0.36 and c < 0.64:
		_progress += 1
		_expect_a = not _expect_a
		Sfx.play("splash", Vector3.INF, -8.0)
		if _progress >= MUD_NEEDED:
			Team.request_self_free.rpc_id(1)
	elif not mashing:
		_misses += 1
		Sfx.play("splash", Vector3.INF, 0.0)
		if _misses >= MUD_MISSES:
			Team.request_die.rpc_id(1, "sinking into the mud")


# --- bear trap ------------------------------------------------------------------------------


func _closeness() -> float:
	var d := absf(wrapf(_dial - _sweet, -PI, PI))
	return 1.0 - d / PI


func _update_bear(delta: float) -> void:
	_title.text = "BEAR TRAP - feel for the spot (mouse), then hold SPACE"
	_window.visible = false
	var near := absf(wrapf(_dial - _sweet, -PI, PI)) < BEAR_SWEET
	_marker.position.x = fposmod(_dial / TAU, 1.0) * (_track.size.x - _marker.size.x)
	_track.color = Color(0.1, 0.08, 0.06).lerp(Color(0.85, 0.35, 0.1), pow(_closeness(), 4.0))
	var holding := Input.is_physical_key_pressed(KEY_SPACE)
	if holding and near:
		_hold += delta
		_wrong_hold = 0.0
		if _hold >= BEAR_HOLD:
			Team.request_self_free.rpc_id(1)
			_hold = 0.0
	elif holding:
		_wrong_hold += delta
		_hold = 0.0
		if _wrong_hold > 0.45:
			_wrong_hold = 0.0
			_sweet = _rng.randf() * TAU  # the jaws shift
			Sfx.play("metal_hit", Vector3.INF, 0.0)
			Team.request_trap_hurt.rpc_id(1)
	else:
		_hold = maxf(_hold - delta * 2.0, 0.0)
		_wrong_hold = 0.0
	_prompt.text = "HOLD SPACE" if near else ("warmer..." if _closeness() > 0.75 else "turn...")
	_bar.value = 100.0 * _hold / BEAR_HOLD
	_info.text = "The bar glows hotter the closer you are. A friend can just pull you out (E)."


# --- input: while a minigame is up it eats the keys and the mouse --------------------------


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if _kind == "mud" and event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_A or event.physical_keycode == KEY_D:
			_mud_press(event.physical_keycode == KEY_A)
			get_viewport().set_input_as_handled()
	elif _kind == "bear trap" and event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_dial = wrapf(_dial + event.relative.x * 0.004, 0.0, TAU)
		get_viewport().set_input_as_handled()
