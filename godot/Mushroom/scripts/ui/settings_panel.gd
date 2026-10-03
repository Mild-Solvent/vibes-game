extends VBoxContainer
## The settings page body (shared by the main menu and the pause overlay): Audio / Controls / Video
## tabs bound to the Settings autoload. While it is open (opened() .. closed()) it plays the mic
## into a muted "MicTest" bus and shows the input level, so you can check the right mic is picked.

const T := preload("res://scripts/ui/theme.gd")
const MIC_BUS := "MicTest"

var first_focus: Control

var _tabs: Array[Button] = []
var _bodies: Array[Control] = []
var _mic_select: OptionButton
var _meter: ProgressBar
var _meter_label: Label
var _mic: AudioStreamPlayer
var _capture: AudioEffectCapture
var _level := 0.0
var _popups: Array[PopupMenu] = []


func _ready() -> void:
	add_theme_constant_override("separation", 14)
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 8)
	add_child(bar)
	var group := ButtonGroup.new()
	for title in ["Audio", "Controls", "Video"]:
		var b := Button.new()
		b.text = title
		b.theme_type_variation = "Tab"
		b.toggle_mode = true
		b.button_group = group
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var index := _tabs.size()
		b.pressed.connect(func(): _show_tab(index))
		bar.add_child(b)
		_tabs.append(b)
	first_focus = _tabs[0]

	var holder := PanelContainer.new()
	holder.theme_type_variation = "Inset"
	holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(holder)
	for body in [_audio_tab(), _controls_tab(), _video_tab()]:
		var scroll := ScrollContainer.new()
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		var pad := MarginContainer.new()
		pad.add_theme_constant_override("margin_right", 16)
		pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		pad.add_child(body)
		scroll.add_child(pad)
		holder.add_child(scroll)
		_bodies.append(scroll)
	_tabs[0].button_pressed = true
	_show_tab(0)
	set_process(false)


## Start the mic test (call when the page becomes visible).
func opened() -> void:
	_refresh_devices()
	_start_mic()
	set_process(true)


## Stop the mic test (call when the page is hidden).
func closed() -> void:
	set_process(false)
	if _mic:
		_mic.stop()
		_mic.queue_free()
		_mic = null
	_level = 0.0
	if _meter:
		_meter.value = 0.0


## OptionButton popups are separate (embedded) windows; scale them with the menu.
func set_ui_scale(s: float) -> void:
	for p in _popups:
		p.content_scale_factor = s


func _process(delta: float) -> void:
	var peak := 0.0
	if _capture:
		var n := _capture.get_frames_available()
		if n > 0:
			var buf := _capture.get_buffer(n)
			for f in buf:
				peak = maxf(peak, maxf(absf(f.x), absf(f.y)))
	_level = maxf(peak, _level - delta * 0.8)
	var db := linear_to_db(maxf(_level, 0.00001))
	_meter.value = clampf((db + 60.0) / 60.0, 0.0, 1.0)
	if _mic == null:
		_meter_label.text = "No microphone input" if DisplayServer.get_name() != "headless" else "Mic test off"
	elif _level < 0.003:
		_meter_label.text = "Silence... say something!"
	elif db > -6.0:
		_meter_label.text = "LOUD. The hag heard that."
	else:
		_meter_label.text = "Hearing you"


func _show_tab(i: int) -> void:
	for j in _bodies.size():
		_bodies[j].visible = j == i
		_tabs[j].set_pressed_no_signal(j == i)


# --- tabs -------------------------------------------------------------------------


func _audio_tab() -> Control:
	var box := _column()
	box.add_child(_section("Volume"))
	box.add_child(_volume_row("Master", "master_volume"))
	box.add_child(_volume_row("Music", "music_volume"))
	box.add_child(_volume_row("Sound effects", "sfx_volume"))
	box.add_child(_volume_row("Friends' voices", "voice_volume"))
	box.add_child(_section("Microphone"))
	_mic_select = OptionButton.new()
	_mic_select.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_mic_select.fit_to_longest_item = false
	_mic_select.clip_text = true
	_mic_select.item_selected.connect(_on_mic_selected)
	_popups.append(_mic_select.get_popup())
	box.add_child(_row("Input device", _mic_select))
	var meter_box := VBoxContainer.new()
	meter_box.add_theme_constant_override("separation", 4)
	meter_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_meter = ProgressBar.new()
	_meter.min_value = 0.0
	_meter.max_value = 1.0
	_meter.step = 0.0
	_meter.show_percentage = false
	_meter.custom_minimum_size = Vector2(0, 22)
	meter_box.add_child(_meter)
	_meter_label = _small("")
	meter_box.add_child(_meter_label)
	box.add_child(_row("Input level", meter_box))
	var ptt := _option(["Open mic (talk freely)", "Push-to-talk (hold V)"], 1 if Settings.push_to_talk else 0,
		func(i: int): Settings.set_value("push_to_talk", i == 1))
	box.add_child(_row("Voice mode", ptt))
	box.add_child(_hint("M mutes your mic any time. The hag hunts by sound, so open mic is brave."))
	return box


func _controls_tab() -> Control:
	var box := _column()
	var touch := OS.has_feature("mobile")
	box.add_child(_section("Touch" if touch else "Mouse"))
	box.add_child(_slider_row("Look sensitivity" if touch else "Mouse sensitivity", 0.0005, 0.008, 0.0001, Settings.mouse_sensitivity,
		func(v: float): Settings.set_value("mouse_sensitivity", v), func(v: float): return "%.1f" % (v * 1000.0)))
	box.add_child(_toggle_row("Invert Y axis", Settings.invert_y, func(on: bool): Settings.set_value("invert_y", on)))
	box.add_child(_section("Camera"))
	box.add_child(_slider_row("Field of view", 60.0, 100.0, 1.0, Settings.fov,
		func(v: float): Settings.set_value("fov", v), func(v: float): return "%d°" % int(v)))
	box.add_child(_hint("The on-screen buttons are explained on the Controls page." if touch
		else "Every key is listed on the Controls page."))
	return box


func _video_tab() -> Control:
	var box := _column()
	box.add_child(_section("Window"))
	box.add_child(_toggle_row("Fullscreen", Settings.fullscreen, func(on: bool): Settings.set_value("fullscreen", on)))
	box.add_child(_toggle_row("V-Sync", Settings.vsync, func(on: bool): Settings.set_value("vsync", on)))
	box.add_child(_section("Graphics"))
	var q := _option(["Low (potato)", "Medium", "High"], Settings.quality,
		func(i: int): Settings.set_value("quality", i))
	box.add_child(_row("Quality preset", q))
	box.add_child(_hint("Low: thinner grass, cheap fog, no shadows. Changes apply to the next forest you load."))
	return box


# --- mic --------------------------------------------------------------------------


func _refresh_devices() -> void:
	_mic_select.clear()
	var devices := AudioServer.get_input_device_list()
	var current := Settings.mic_device if devices.has(Settings.mic_device) else "Default"
	for d in devices:
		_mic_select.add_item("System default" if d == "Default" else d)
		_mic_select.set_item_metadata(_mic_select.item_count - 1, d)
		if d == current:
			_mic_select.select(_mic_select.item_count - 1)
	if devices.is_empty():
		_mic_select.add_item("No microphone found")
		_mic_select.disabled = true


func _on_mic_selected(i: int) -> void:
	var d: String = _mic_select.get_item_metadata(i)
	Settings.set_value("mic_device", "" if d == "Default" else d)
	if _mic:
		_mic.stop()
		_mic.play()


func _start_mic() -> void:
	if _mic != null or DisplayServer.get_name() == "headless":
		return
	if not ProjectSettings.get_setting("audio/driver/enable_input", false):
		return
	var idx := AudioServer.get_bus_index(MIC_BUS)
	if idx < 0:
		AudioServer.add_bus()
		idx = AudioServer.bus_count - 1
		AudioServer.set_bus_name(idx, MIC_BUS)
		AudioServer.set_bus_send(idx, "Master")
		var cap := AudioEffectCapture.new()
		cap.buffer_length = 0.25
		AudioServer.add_bus_effect(idx, cap)
	AudioServer.set_bus_mute(idx, true)
	_capture = null
	for i in AudioServer.get_bus_effect_count(idx):
		if AudioServer.get_bus_effect(idx, i) is AudioEffectCapture:
			_capture = AudioServer.get_bus_effect(idx, i)
	if _capture:
		_capture.clear_buffer()
	_mic = AudioStreamPlayer.new()
	_mic.stream = AudioStreamMicrophone.new()
	_mic.bus = MIC_BUS
	add_child(_mic)
	_mic.play()


# --- building blocks --------------------------------------------------------------


func _column() -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	return box


func _section(text: String) -> Control:
	var l := Label.new()
	l.text = text.to_upper()
	l.theme_type_variation = "Heading"
	l.add_theme_font_size_override("font_size", 22)
	l.add_theme_color_override("font_color", T.GOLD)
	return l


func _small(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.theme_type_variation = "Small"
	return l


func _hint(text: String) -> Label:
	var l := _small(text)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(300, 0)
	return l


func _row(text: String, control: Control) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	var l := Label.new()
	l.text = text
	l.custom_minimum_size = Vector2(230, 0)
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(l)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	control.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(control)
	return row


func _slider_row(text: String, lo: float, hi: float, step: float, value: float, on_change: Callable,
		fmt: Callable) -> HBoxContainer:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	var slider := HSlider.new()
	slider.min_value = lo
	slider.max_value = hi
	slider.step = step
	slider.value = value
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.custom_minimum_size = Vector2(0, 28)
	box.add_child(slider)
	var shown := Label.new()
	shown.custom_minimum_size = Vector2(64, 0)
	shown.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	shown.text = fmt.call(value)
	box.add_child(shown)
	slider.value_changed.connect(_on_slider.bind(shown, fmt, on_change))
	return _row(text, box)


func _volume_row(text: String, key: String) -> HBoxContainer:
	return _slider_row(text, 0.0, 1.0, 0.01, Settings.get(key),
		func(v: float): Settings.set_value(key, v), func(v: float): return "%d%%" % roundi(v * 100.0))


func _toggle_row(text: String, on: bool, on_change: Callable) -> HBoxContainer:
	var b := CheckButton.new()
	b.button_pressed = on
	b.text = "On" if on else "Off"
	b.toggled.connect(_on_toggle.bind(b, on_change))
	var row := _row(text, b)
	b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	return row


func _option(items: Array, selected: int, on_change: Callable) -> OptionButton:
	var o := OptionButton.new()
	for it in items:
		o.add_item(it)
	o.select(selected)
	o.item_selected.connect(_on_option.bind(on_change))
	_popups.append(o.get_popup())
	return o


func _on_slider(v: float, shown: Label, fmt: Callable, on_change: Callable) -> void:
	shown.text = fmt.call(v)
	on_change.call(v)


func _on_toggle(v: bool, b: CheckButton, on_change: Callable) -> void:
	b.text = "On" if v else "Off"
	Sfx.play("ui_click")
	on_change.call(v)


func _on_option(i: int, on_change: Callable) -> void:
	Sfx.play("ui_click")
	on_change.call(i)
