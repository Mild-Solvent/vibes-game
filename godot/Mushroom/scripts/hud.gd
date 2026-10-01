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
var _gag_left := 0.0
var _journal_open := false
var _compass: Label
var _duel: ProgressBar
var _duel_label: Label
var _reel: ColorRect
var _reel_grid: GridContainer
var _reel_title: Label
var _highlights: Array[Dictionary] = []
var _phase := -1
var menu: CanvasLayer  # the real menu (scripts/ui/menu.gd), set by main
var _cheat_panel: Control
var _cheat_tag: Label
var _over: ColorRect
var _over_text: Label
var _over_grid: GridContainer
var intro_enabled := true


func _ready() -> void:
	add_to_group("hud")
	_build_menu()
	_build_game()
	show_menu()
	Team.toast.connect(show_toast)
	Team.game_over.connect(_show_game_over)


func _process(delta: float) -> void:
	if _toast_left > 0.0:
		_toast_left -= delta
		_toast.visible = _toast_left > 0.0
	if _gag_left > 0.0:
		_gag_left -= delta
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
	elif event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_F1 \
			and _game.visible:
		_cheat_panel.toggle()
	elif event.is_action_pressed("journal"):
		var me := _local_player()
		if me and me.holding_guide():
			_journal_open = not _journal_open
		else:
			show_toast("Only whoever holds the field guide can read it. It's on the chest at camp.")


func set_levels(titles: Array) -> void:
	_mode_select.clear()
	for t in titles:
		_mode_select.add_item(t)


func show_menu() -> void:
	_menu.visible = false  # the old menu; scripts/ui/menu.gd is the real one now
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
	_cheat_tag.visible = Team.cheats
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
	var lines: Array[String] = []
	if Team.is_tripping(id):
		strength = clampf(maxf(Team.players[id]["trip"], Team.players[id]["out"]) / 5.0, 0.0, 1.0)
	match status:
		Team.Status.TRIPPING:
			lines.append("TRIPPING (%d s)" % left)
		Team.Status.PASSED_OUT:
			dark = 0.9
			lines.append("PASSED OUT (%d s)... the colours, man" % left)
		Team.Status.DEAD:
			tint = Color(0.55, 0.6, 0.75)
			lines.append("YOU'RE DEAD. Float around as a ghost.\nGet your friends to carry your body to the witch.")
	var poison := Team.poison_left(id)
	if poison > 0.0 and status != Team.Status.DEAD:
		tint = Color(0.75, 1.0, 0.7)
		dark = maxf(dark, 0.5 * (1.0 - poison / Team.POISON_SECONDS))
		lines.append("POISONED - dead in %d s - MEDKIT (H) or the witch" % int(ceil(poison)))
	if Team.stuck_in(id) != "":
		lines.append("STUCK in a %s - a friend has to pull you out" % Team.stuck_in(id))
	if Team.police_left > 0.0:
		var missing: String = Team.players.get(Team.missing_peer, {}).get("name", "someone")
		lines.append("POLICE coming in %d s - find %s!" % [int(Team.police_left), missing])
	_status_label.text = "\n".join(lines)
	if _gag_left > 0.0:
		tint = Color(0.7, 1.0, 0.4)
		strength = maxf(strength, 0.4)
	_effect.visible = strength > 0.0 or dark > 0.0 or tint != Color.WHITE
	mat.set_shader_parameter("strength", strength)
	mat.set_shader_parameter("dark", dark)
	mat.set_shader_parameter("tint", Vector3(tint.r, tint.g, tint.b))
	var pockets := []
	for item in ["flare", "whistle", "walkie", "compass", "wine", "duck", "lottery"]:
		var n := Team.count(id, item)
		if n > 0:
			pockets.append("%s%s" % [Team.ITEM_NAMES[item], " x%d" % n if n > 1 else ""])
	_inventory_label.text = "Medkits: %d   Team batteries: %d   Torch (T): %d%%%s" % [
		Team.count(id, "medkit"), Team.batteries, int(me.battery * 100.0),
		("\nPockets (G/B/V): " + ", ".join(pockets)) if not pockets.is_empty() else ""
	]
	_hint.text = me.look_hint()
	_guide.visible = _journal_open and me.holding_guide()
	_compass.visible = Team.count(id, "compass") > 0 and status != Team.Status.DEAD
	if _compass.visible:
		_compass.text = _compass_strip(fposmod(rad_to_deg(-me.global_rotation.y), 360.0))


## "· · NW · N · NE · ·" centred on where you're facing (0 = north = -Z).
func _compass_strip(heading: float) -> String:
	var marks := {0: "N", 45: "NE", 90: "E", 135: "SE", 180: "S", 225: "SW", 270: "W", 315: "NW"}
	var parts: Array[String] = []
	for i in range(-4, 5):
		var deg := int(round(fposmod(heading + i * 15.0, 360.0) / 15.0)) * 15 % 360
		parts.append(marks.get(deg, "·"))
	return "[  " + "   ".join(parts) + "  ]"


# --- the extra bits other scripts call through the "hud" group ----------------------------------


func is_night() -> bool:
	var level := get_tree().get_first_node_in_group("level")
	return level != null and level.get("_night") == true


func menu_open() -> bool:
	return menu != null and menu.is_open()


## The pause menu's "field journal" button.
func toggle_journal() -> void:
	var me := _local_player()
	if me and me.holding_guide():
		_journal_open = not _journal_open
	else:
		show_toast("Only whoever holds the field guide can read it. It's on the chest at camp.")


## A screen-wide gag (vomit...).
func play_gag(gag: String) -> void:
	if gag == "vomit":
		_gag_left = 3.0


## Force-feeding tug-of-war meter (only shown to the two people in it).
func show_duel(running: bool, meter: float, am_feeder: bool) -> void:
	_duel.visible = running
	_duel.value = (meter * (1.0 if am_feeder else -1.0)) * 50.0 + 50.0
	_duel_label.visible = running
	_duel_label.text = "SPAM T!  shove it in!" if am_feeder else "SPAM T!  keep your mouth shut!"


## Seeing things in the dark: the Hag, for a split second, just at the edge of your torch.
func show_shadow_figure() -> void:
	var me := _local_player()
	if me == null:
		return
	var ModelFit := preload("res://scripts/model_fit.gd")
	var ghost := ModelFit.fit("res://assets/polypizza/hag.glb", Vector3(1.2, 2.5, 1.2), 0.0)
	var side := 1.0 if randf() < 0.5 else -1.0
	var dir: Vector3 = (-me.global_basis.z).rotated(Vector3.UP, side * deg_to_rad(randf_range(30, 50)))
	get_tree().current_scene.add_child(ghost)
	ghost.global_position = me.global_position + dir * randf_range(8, 14) + Vector3(0, 1.25, 0)
	ghost.look_at(me.global_position + Vector3(0, 1.25, 0))
	get_tree().create_timer(randf_range(0.25, 0.6)).timeout.connect(ghost.queue_free)
	Sfx.play("hag_whisper", ghost.global_position)


## A moment for the end-of-day reel: what happened, plus a snapshot of this player's screen.
func remember_highlight(text: String, _peer_id := 0) -> void:
	var image: Image = null
	if DisplayServer.get_name() != "headless":
		image = get_viewport().get_texture().get_image()
	if image:
		image.resize(320, 180)
	_highlights.append({"text": text, "image": image})
	if _highlights.size() > 8:
		_highlights.pop_front()


func add_child_minigame_and_cheats() -> void:
	_game.add_child(preload("res://scripts/ui/escape_minigame.gd").new())
	_cheat_panel = preload("res://scripts/ui/cheat_panel.gd").new()
	_game.add_child(_cheat_panel)
	_cheat_tag = _label("CHEATS ON", 16, HORIZONTAL_ALIGNMENT_LEFT)
	_cheat_tag.modulate = Color(1, 0.4, 0.3)
	_cheat_tag.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT, Control.PRESET_MODE_MINSIZE, 14)
	_cheat_tag.visible = false
	_game.add_child(_cheat_tag)


## The game over screen: how everyone died, how long you lasted, the highlights. Click to go again.
func _build_game_over() -> void:
	_over = ColorRect.new()
	_over.color = Color(0.03, 0.02, 0.02, 0.93)
	_over.set_anchors_preset(Control.PRESET_FULL_RECT)
	_over.visible = false
	add_child(_over)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_over.add_child(center)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 16)
	center.add_child(box)
	var title := _label("GAME OVER", 72)
	title.modulate = Color(0.95, 0.25, 0.2)
	box.add_child(title)
	_over_text = _label("", 20)
	box.add_child(_over_text)
	_over_grid = GridContainer.new()
	_over_grid.columns = 4
	_over_grid.add_theme_constant_override("h_separation", 12)
	_over_grid.add_theme_constant_override("v_separation", 12)
	box.add_child(_over_grid)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 16)
	box.add_child(buttons)
	var again := Button.new()
	again.text = "  Go again (day 1)  "
	again.add_theme_font_size_override("font_size", 24)
	again.pressed.connect(func():
		_over.visible = false
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED)
	buttons.add_child(again)
	var leave := Button.new()
	leave.text = "  Leave to menu  "
	leave.add_theme_font_size_override("font_size", 24)
	leave.pressed.connect(func():
		Net.leave()
		get_tree().reload_current_scene())
	buttons.add_child(leave)
	var quit := Button.new()
	quit.text = "  Quit  "
	quit.add_theme_font_size_override("font_size", 24)
	quit.pressed.connect(func(): get_tree().quit())
	buttons.add_child(quit)


func _show_game_over(stats: Dictionary) -> void:
	var lines: Array[String] = [stats.get("reason", "")]
	lines.append("")
	lines.append("Survived %d day%s · earned %d € · still owed Uncle Fero %d €" % [
		stats.get("days", 1), "" if stats.get("days", 1) == 1 else "s", stats.get("earned", 0), stats.get("owed", 0)])
	var deaths: Array = stats.get("deaths", [])
	if not deaths.is_empty():
		lines.append("")
		lines.append("HOW IT WENT:")
		for d in deaths:
			lines.append("✝ " + str(d))
	_over_text.text = "\n".join(lines)
	for child in _over_grid.get_children():
		child.queue_free()
	for h in _highlights.slice(-8):
		var cell := VBoxContainer.new()
		if h["image"]:
			var tex := TextureRect.new()
			tex.texture = ImageTexture.create_from_image(h["image"])
			tex.custom_minimum_size = Vector2(200, 112)
			tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
			cell.add_child(tex)
		var cap := _label(h["text"], 13)
		cap.custom_minimum_size = Vector2(200, 0)
		cap.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		cell.add_child(cap)
		_over_grid.add_child(cell)
	_highlights.clear()
	_over.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


## Main calls this with the round phase; the reel shows at night (WRAP = 2).
func set_phase(phase: int) -> void:
	if phase == _phase:
		return
	_phase = phase
	if phase == 2:
		_show_reel()
	else:
		_reel.visible = false
		if phase == 0:
			_highlights.clear()


func _show_reel() -> void:
	for child in _reel_grid.get_children():
		child.queue_free()
	_reel_title.text = "TODAY'S HIGHLIGHTS" if not _highlights.is_empty() else "TODAY'S HIGHLIGHTS\nNothing happened. Suspicious."
	for h in _highlights:
		var box := VBoxContainer.new()
		if h["image"]:
			var tex := TextureRect.new()
			tex.texture = ImageTexture.create_from_image(h["image"])
			tex.custom_minimum_size = Vector2(240, 135)
			tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
			box.add_child(tex)
		var cap := _label(h["text"], 14)
		cap.custom_minimum_size = Vector2(240, 0)
		cap.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(cap)
		_reel_grid.add_child(box)
	_reel.visible = true


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
	_guide.modulate = Color(0.85, 1, 0.85, 0.95)
	_guide.visible = false
	_game.add_child(_guide)

	_compass = _label("", 20)
	_compass.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE, 70)
	_compass.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_compass.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_compass.modulate = Color(1, 0.95, 0.75)
	_game.add_child(_compass)

	var duel_box := VBoxContainer.new()
	duel_box.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)
	duel_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	duel_box.grow_vertical = Control.GROW_DIRECTION_BOTH
	duel_box.position.y += 110
	duel_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_game.add_child(duel_box)
	_duel_label = _label("", 22)
	_duel_label.modulate = Color(1, 0.6, 0.3)
	_duel_label.visible = false
	duel_box.add_child(_duel_label)
	_duel = ProgressBar.new()
	_duel.custom_minimum_size = Vector2(420, 26)
	_duel.show_percentage = false
	_duel.value = 50.0
	_duel.visible = false
	_duel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	duel_box.add_child(_duel)

	_reel = ColorRect.new()
	_reel.color = Color(0, 0, 0, 0.8)
	_reel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_reel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_reel.visible = false
	_game.add_child(_reel)
	var reel_center := CenterContainer.new()
	reel_center.set_anchors_preset(Control.PRESET_FULL_RECT)
	reel_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_reel.add_child(reel_center)
	var reel_box := VBoxContainer.new()
	reel_box.add_theme_constant_override("separation", 14)
	reel_center.add_child(reel_box)
	_reel_title = _label("TODAY'S HIGHLIGHTS", 34)
	_reel_title.modulate = Color(1, 0.9, 0.5)
	reel_box.add_child(_reel_title)
	_reel_grid = GridContainer.new()
	_reel_grid.columns = 4
	_reel_grid.add_theme_constant_override("h_separation", 14)
	_reel_grid.add_theme_constant_override("v_separation", 14)
	reel_box.add_child(_reel_grid)

	add_child_minigame_and_cheats()
	_build_game_over()

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
