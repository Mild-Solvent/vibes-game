extends Node
## "The broadcast": every camera source renders into its own SubViewport; the PROGRAM viewport
## shows the source the director TOOK plus the channel graphics (status tag, lower third,
## ticker, subtitles, REC badge, test card). Its texture is what every monitor shows.
##
## A source is any object with `label: String`, `fov: float`, `on_air: bool` and
## `view_transform() -> Transform3D` (studio camera rigs, the handheld field camera).
## Only the active source renders every frame; the others render while previews are wanted
## (someone on this peer sits at the control desk).
##
## Recording is local on every peer (each renders the same show): while REC is on during LIVE
## the program picture is sampled a few times a second, and at WRAP it is played back as
## "THE TAPE" on every monitor.

const SIZE := Vector2i(640, 360)
const TAPE_SIZE := Vector2i(320, 180)
const TAPE_FPS := 5.0
const TAPE_MAX_FRAMES := 180  # 36 s

var sources: Array = []
var active := 0
var program: SubViewport
var recording := false

var _views: Array[SubViewport] = []
var _cams: Array[Camera3D] = []
var _previews := false
var _picture: TextureRect
var _graphics: Control
var _status_tag: Label
var _rec_badge: Label
var _source_tag: Label
var _lower_third: Label
var _breaking: Label
var _ticker: Label
var _ticker_text := ""
var _subtitle: Label
var _subtitle_bg: ColorRect
var _card: ColorRect
var _card_label: Label
var _replay_tag: Label

var _frames: Array[Image] = []
var _capture_timer := 0.0
var _capturing := false
var _replaying := false
var _replay_index := 0
var _replay_timer := 0.0
var _replay_texture: ImageTexture
var _can_capture := DisplayServer.get_name() != "headless"


## Call once, after `sources` is filled and this node is in the tree.
func build() -> void:
	for source in sources:
		var view := SubViewport.new()
		view.size = SIZE
		view.render_target_update_mode = SubViewport.UPDATE_DISABLED
		add_child(view)
		var cam := Camera3D.new()
		cam.current = true
		view.add_child(cam)
		_views.append(view)
		_cams.append(cam)
	_build_program()
	set_active(0)


func texture() -> Texture2D:
	return program.get_texture()


func source_texture(index: int) -> Texture2D:
	return _views[index].get_texture()


## The Camera3D that renders `index` (for frustum checks).
func source_camera(index: int) -> Camera3D:
	return _cams[index]


func active_camera() -> Camera3D:
	return _cams[active]


func set_active(index: int) -> void:
	active = clampi(index, 0, sources.size() - 1)
	_picture.texture = _views[active].get_texture() if not _replaying else _replay_texture
	_source_tag.text = sources[active].label
	_update_render_modes()


## Render every source (for the desk's preview monitors) or only the active one.
func set_previews(on: bool) -> void:
	_previews = on
	_update_render_modes()


func set_status(text: String, color: Color) -> void:
	_status_tag.text = text
	_status_tag.modulate = color


func set_card(show_card: bool, text := "") -> void:
	_card.visible = show_card and not _replaying
	_card_label.text = text


func set_lower_third(breaking: String, text: String) -> void:
	_breaking.text = breaking
	_breaking.visible = not breaking.is_empty()
	_lower_third.text = text


func set_ticker(text: String) -> void:
	_ticker_text = text + "   ·   "
	_ticker.text = _ticker_text.repeat(4)


func set_subtitle(text: String) -> void:
	_subtitle.text = text
	_subtitle_bg.visible = not text.strip_edges().is_empty()


## `capture` = the show is LIVE (only then does REC actually record).
func set_recording(on: bool, capture: bool) -> void:
	recording = on
	_capturing = on and capture


func recorded_seconds() -> float:
	return _frames.size() / TAPE_FPS


func clear_tape() -> void:
	_frames.clear()
	stop_replay()


## Plays the recorded tape on the program (and so on every monitor). False if there is none.
func start_replay() -> bool:
	if _frames.is_empty():
		return false
	if _replaying:
		return true
	_replaying = true
	_replay_index = 0
	_replay_texture = ImageTexture.create_from_image(_frames[0])
	_picture.texture = _replay_texture
	_graphics.visible = false
	_card.visible = false
	_replay_tag.visible = true
	return true


func stop_replay() -> void:
	if not _replaying:
		return
	_replaying = false
	_graphics.visible = true
	_replay_tag.visible = false
	set_active(active)


func _process(delta: float) -> void:
	for i in sources.size():
		if _views[i].render_target_update_mode != SubViewport.UPDATE_DISABLED or i == active:
			_cams[i].global_transform = sources[i].view_transform()
			_cams[i].fov = sources[i].fov
	_ticker.position.x -= delta * 70.0
	if _ticker.position.x < -_ticker.get_minimum_size().x / 4.0:
		_ticker.position.x = 0.0
	var secs := int(recorded_seconds())
	_rec_badge.visible = recording and int(Time.get_ticks_msec() / 500) % 2 == 0
	_rec_badge.text = "● REC %d:%02d" % [secs / 60, secs % 60]

	if _capturing and _can_capture:
		_capture_timer -= delta
		if _capture_timer <= 0.0:
			_capture_timer = 1.0 / TAPE_FPS
			_capture()
	if _replaying:
		_replay_timer -= delta
		if _replay_timer <= 0.0:
			_replay_timer = 1.0 / TAPE_FPS
			_replay_index = (_replay_index + 1) % _frames.size()
			_replay_texture.update(_frames[_replay_index])


func _capture() -> void:
	var image := program.get_texture().get_image()
	if image == null or image.is_empty():
		return
	image.resize(TAPE_SIZE.x, TAPE_SIZE.y, Image.INTERPOLATE_BILINEAR)
	if image.get_format() != Image.FORMAT_RGBA8:
		image.convert(Image.FORMAT_RGBA8)
	_frames.append(image)
	if _frames.size() > TAPE_MAX_FRAMES:
		_frames.pop_front()


func _update_render_modes() -> void:
	for i in _views.size():
		var on := i == active or _previews
		_views[i].render_target_update_mode = SubViewport.UPDATE_ALWAYS if on else SubViewport.UPDATE_DISABLED


func _build_program() -> void:
	program = SubViewport.new()
	program.size = SIZE
	program.disable_3d = true
	program.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(program)

	var root := Control.new()
	root.size = Vector2(SIZE)
	program.add_child(root)
	_picture = TextureRect.new()
	_picture.size = Vector2(SIZE)
	_picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_picture.stretch_mode = TextureRect.STRETCH_SCALE
	root.add_child(_picture)

	_graphics = Control.new()
	_graphics.size = Vector2(SIZE)
	root.add_child(_graphics)

	_subtitle_bg = _rect(Color(0, 0, 0, 0.7), Rect2(40, 222, 560, 44))
	_graphics.add_child(_subtitle_bg)
	_subtitle = _text("", 22, Rect2(0, 0, 560, 44))
	_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_subtitle.clip_text = true
	_subtitle_bg.add_child(_subtitle)
	_subtitle_bg.visible = false

	_breaking = _text("", 18, Rect2(0, 270, 0, 26))
	_breaking.add_theme_color_override("font_color", Color.WHITE)
	var breaking_bg := StyleBoxFlat.new()
	breaking_bg.bg_color = Color(0.8, 0.05, 0.05)
	breaking_bg.content_margin_left = 10
	breaking_bg.content_margin_right = 10
	_breaking.add_theme_stylebox_override("normal", breaking_bg)
	_graphics.add_child(_breaking)
	var bar := _rect(Color(0.06, 0.13, 0.38, 0.95), Rect2(0, 296, 640, 36))
	_graphics.add_child(bar)
	_lower_third = _text("", 20, Rect2(10, 0, 620, 36))
	bar.add_child(_lower_third)
	var ticker_bar := _rect(Color(0.95, 0.8, 0.1), Rect2(0, 332, 640, 24))
	ticker_bar.clip_contents = true
	_graphics.add_child(ticker_bar)
	_ticker = _text("", 15, Rect2(0, 0, 4000, 24))
	_ticker.add_theme_color_override("font_color", Color(0.05, 0.05, 0.1))
	ticker_bar.add_child(_ticker)

	var logo := _text("6", 34, Rect2(578, 8, 50, 44))
	logo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var logo_bg := StyleBoxFlat.new()
	logo_bg.bg_color = Color(0.85, 0.1, 0.1, 0.85)
	logo_bg.set_corner_radius_all(22)
	logo.add_theme_stylebox_override("normal", logo_bg)
	_graphics.add_child(logo)
	_status_tag = _text("", 22, Rect2(14, 8, 200, 32))
	_graphics.add_child(_status_tag)
	_rec_badge = _text("", 18, Rect2(14, 38, 200, 26))
	_rec_badge.add_theme_color_override("font_color", Color(1, 0.2, 0.2))
	_graphics.add_child(_rec_badge)
	_source_tag = _text("", 14, Rect2(470, 60, 160, 20))
	_source_tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_source_tag.modulate = Color(1, 1, 1, 0.6)
	_graphics.add_child(_source_tag)

	_card = _rect(Color(0.12, 0.12, 0.16), Rect2(Vector2.ZERO, Vector2(SIZE)))
	root.add_child(_card)
	for i in 7:  # colour bars
		var colors := [Color.WHITE, Color.YELLOW, Color.CYAN, Color.GREEN, Color.MAGENTA, Color.RED, Color.BLUE]
		var bar_rect := _rect(colors[i] * Color(0.75, 0.75, 0.75), Rect2(i * 640.0 / 7.0, 0, 640.0 / 7.0 + 1, 150))
		_card.add_child(bar_rect)
	_card_label = _text("", 30, Rect2(0, 160, 640, 200))
	_card_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_card_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_card.add_child(_card_label)

	_replay_tag = _text("▶ THE TAPE - replay", 22, Rect2(14, 8, 400, 32))
	_replay_tag.add_theme_color_override("font_color", Color(1, 0.85, 0.3))
	_replay_tag.add_theme_constant_override("outline_size", 6)
	_replay_tag.visible = false
	root.add_child(_replay_tag)


func _rect(color: Color, rect: Rect2) -> ColorRect:
	var r := ColorRect.new()
	r.color = color
	r.position = rect.position
	r.size = rect.size
	return r


func _text(text: String, font_size: int, rect: Rect2) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.position = rect.position
	label.size = rect.size
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return label
