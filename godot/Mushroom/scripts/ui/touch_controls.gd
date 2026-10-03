extends CanvasLayer
## Autoload "Touch": on-screen controls for phones and tablets, only on mobile builds
## (or with `-- --touch` on the command line, to try it on PC with a touchscreen).
##
## - Left thumb: a floating joystick that drives the move_* actions (and steers the car).
## - Right half: drag to look. player.gd pulls the drag with take_look() every frame.
## - Buttons send the same input actions as the keyboard (jump, sprint, grab = E, throw = Q,
##   taste = F, flashlight = T, voice_mute = M, ui_cancel = Esc), so the game code doesn't
##   know the difference.
## The controls show only while playing (HUD up, no menu); menus are tapped like normal buttons.
## A phone without a mouse can't "capture" it, so gameplay code asks Touch.captured() instead of
## checking Input.mouse_mode itself.
## Also asks for the microphone permission on Android and starts voice once it's granted.

const STICK_RADIUS := 90.0
const LOOK_SPEED := 0.005  ## radians per (stretched) pixel, scaled by the mouse sensitivity setting

## True on touch builds; everything else in here is idle otherwise.
var active := false

var _look := Vector2.ZERO
var _stick_finger := -1
var _stick_origin := Vector2.ZERO
var _stick_pos := Vector2.ZERO
var _look_finger := -1
var _button_fingers := {}  # finger index -> button id
var _sprint := false
var _canvas: Control
var _buttons: Array = []  # [{id, action, label, center, radius, toggle}]
var _font: Font


func _ready() -> void:
	active = OS.has_feature("mobile") or "--touch" in OS.get_cmdline_user_args()
	if not active:
		set_process(false)
		set_process_input(false)
		return
	layer = 90
	_font = ThemeDB.fallback_font
	_canvas = Control.new()
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.draw.connect(_draw_controls)
	add_child(_canvas)
	get_viewport().size_changed.connect(_layout)
	_layout()
	if OS.get_name() == "Android":
		get_tree().on_request_permissions_result.connect(_on_permission)
		OS.request_permissions()


## The look drag since the last call (player.gd turns the camera with it).
func take_look() -> Vector2:
	var d := _look * LOOK_SPEED
	_look = Vector2.ZERO
	if "mouse_sensitivity" in Settings:
		d *= Settings.mouse_sensitivity / 0.0025
	return d


## Is the player in control of their character? Mouse captured on PC; HUD up and no menu on touch.
func captured() -> bool:
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		return true
	if not active:
		return false
	var hud = get_tree().get_first_node_in_group("hud")
	return hud != null and hud.has_method("playing") and hud.playing()


func _playing() -> bool:
	return active and captured()


func _layout() -> void:
	var vp := get_viewport().get_visible_rect().size
	var r := 54.0
	var right := vp.x - 90.0
	var bottom := vp.y - 90.0
	_buttons = [
		{"id": "jump", "action": "jump", "label": "JUMP", "center": Vector2(right, bottom), "radius": r + 10.0},
		{"id": "grab", "action": "grab", "label": "E", "center": Vector2(right - 140.0, bottom + 10.0), "radius": r},
		{"id": "throw", "action": "throw", "label": "Q", "center": Vector2(right - 20.0, bottom - 140.0), "radius": r * 0.85},
		{"id": "taste", "action": "taste", "label": "EAT", "center": Vector2(right - 140.0, bottom - 120.0), "radius": r * 0.75},
		{"id": "flashlight", "action": "flashlight", "label": "LIGHT", "center": Vector2(right - 260.0, bottom + 20.0), "radius": r * 0.75},
		{"id": "sprint", "action": "sprint", "label": "RUN", "center": Vector2(250.0, bottom + 20.0), "radius": r * 0.75, "toggle": true},
		{"id": "mute", "action": "voice_mute", "label": "MIC", "center": Vector2(vp.x - 60.0, 150.0), "radius": 34.0},
		{"id": "pause", "action": "ui_cancel", "label": "II", "center": Vector2(vp.x - 60.0, 60.0), "radius": 34.0},
	]
	_canvas.queue_redraw()


func _process(_delta: float) -> void:
	var show := _playing()
	if _canvas.visible != show:
		_canvas.visible = show
		if not show:
			_release_all()
	if show:
		_canvas.queue_redraw()


func _input(event: InputEvent) -> void:
	if not _playing():
		return
	# Touches also arrive as emulated mouse clicks and drags (that's how menus work on a phone).
	# In game those would grab (left click) and spin the camera, so drop them here.
	if event is InputEventMouse and event.device == InputEvent.DEVICE_ID_EMULATION:
		get_viewport().set_input_as_handled()
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			_touch_down(event.index, event.position)
		else:
			_touch_up(event.index)
		get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag:
		if event.index == _stick_finger:
			_stick_pos = event.position
			_update_stick()
		elif event.index == _look_finger:
			_look += event.relative
		get_viewport().set_input_as_handled()


func _touch_down(finger: int, pos: Vector2) -> void:
	for b in _buttons:
		if pos.distance_to(b["center"]) <= b["radius"] * 1.15:
			_button_fingers[finger] = b["id"]
			if b.get("toggle", false):
				_sprint = not _sprint
				_send(b["action"], _sprint)
			else:
				_send(b["action"], true)
			return
	var vp := get_viewport().get_visible_rect().size
	if pos.x < vp.x * 0.45 and _stick_finger < 0:
		_stick_finger = finger
		_stick_origin = pos
		_stick_pos = pos
		_update_stick()
	elif _look_finger < 0:
		_look_finger = finger


func _touch_up(finger: int) -> void:
	if _button_fingers.has(finger):
		var id: String = _button_fingers[finger]
		_button_fingers.erase(finger)
		for b in _buttons:
			if b["id"] == id and not b.get("toggle", false):
				_send(b["action"], false)
	if finger == _stick_finger:
		_stick_finger = -1
		_set_move(Vector2.ZERO)
		if _sprint:
			_sprint = false
			_send("sprint", false)
	if finger == _look_finger:
		_look_finger = -1


func _update_stick() -> void:
	var v := (_stick_pos - _stick_origin) / STICK_RADIUS
	if v.length() > 1.0:
		_stick_origin = _stick_pos - v.normalized() * STICK_RADIUS  # drag the base along
		v = v.normalized()
	_set_move(v)


func _set_move(v: Vector2) -> void:
	_axis("move_left", "move_right", v.x)
	_axis("move_forward", "move_back", v.y)


func _axis(neg: String, pos: String, value: float) -> void:
	if value < -0.15:
		Input.action_press(neg, -value)
		Input.action_release(pos)
	elif value > 0.15:
		Input.action_press(pos, value)
		Input.action_release(neg)
	else:
		Input.action_release(neg)
		Input.action_release(pos)


## Send an action as a real input event, so _unhandled_input handlers see it too.
func _send(action: String, pressed: bool) -> void:
	if not InputMap.has_action(action):
		return
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = pressed
	Input.parse_input_event(ev)


func _release_all() -> void:
	for finger in _button_fingers.keys():
		_touch_up(finger)
	_button_fingers.clear()
	_stick_finger = -1
	_look_finger = -1
	_set_move(Vector2.ZERO)
	if _sprint:
		_sprint = false
		_send("sprint", false)
	_look = Vector2.ZERO


func _draw_controls() -> void:
	var white := Color(1, 1, 1, 0.55)
	var fill := Color(0, 0, 0, 0.28)
	if _stick_finger >= 0:
		_canvas.draw_circle(_stick_origin, STICK_RADIUS, fill)
		_canvas.draw_arc(_stick_origin, STICK_RADIUS, 0, TAU, 48, white, 3.0)
		_canvas.draw_circle(_stick_origin + (_stick_pos - _stick_origin).limit_length(STICK_RADIUS), 36.0, white)
	else:
		var vp := get_viewport().get_visible_rect().size
		var hint := Vector2(150.0, vp.y - 150.0)
		_canvas.draw_arc(hint, STICK_RADIUS, 0, TAU, 48, Color(1, 1, 1, 0.18), 3.0)
	var muted: bool = "muted" in Voice and Voice.muted
	for b in _buttons:
		var down: bool = b["id"] in _button_fingers.values() or (b["id"] == "sprint" and _sprint)
		var bg := Color(1, 1, 1, 0.35) if down else fill
		if b["id"] == "mute" and muted:
			bg = Color(0.8, 0.1, 0.1, 0.5)
		_canvas.draw_circle(b["center"], b["radius"], bg)
		_canvas.draw_arc(b["center"], b["radius"], 0, TAU, 40, white, 2.5)
		var label: String = "MUTED" if b["id"] == "mute" and muted else b["label"]
		var size := 22 if b["radius"] > 45.0 else 16
		var w := _font.get_string_size(label, HORIZONTAL_ALIGNMENT_CENTER, -1, size).x
		_canvas.draw_string(_font, b["center"] + Vector2(-w * 0.5, size * 0.35), label,
			HORIZONTAL_ALIGNMENT_CENTER, -1, size, Color(1, 1, 1, 0.9))


func _on_permission(permission: String, granted: bool) -> void:
	if granted and permission.ends_with("RECORD_AUDIO") and Voice.has_method("restart_mic"):
		Voice.restart_mic()
