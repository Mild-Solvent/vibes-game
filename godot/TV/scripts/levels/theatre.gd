extends "res://scripts/levels/level.gd"
## "Places, Please!": grey-box theatre, backstage crew during a live play.
##
## Layout (local metres):
##   z = -10 .. -2  the STAGE (raised 0.8 m). Proscenium wall at z = -2 with an opening |x| < 5,
##                  so the wings (|x| 5..10) are hidden from the audience.
##   z =   1 .. 10  the AUDIENCE seats. Crew can watch the audience view on the monitor in the
##                  stage-left wing.
##
## LIVE is a loop of SCENE (lights up) and BLACKOUT (dark, glowing tape shows where every set
## piece goes for the next scene). When the lights come back the audience judges the set.
## During a scene: exactly one actor on the star mark; any other crew in the light = caught.

enum Event { NONE, EMPTY_STAGE, CAUGHT_IN_LIGHT, WRONG_SET, SET_PERFECT }

const STAGE_TOP := 0.8
const LIT_ZONE := AABB(Vector3(-5.0, 0.5, -10.0), Vector3(10.0, 4.0, 8.0))
const ACTOR_ZONE := AABB(Vector3(-0.8, 0.5, -6.8), Vector3(1.6, 4.0, 1.6))
const SCENE_TIME := 25.0
const BLACKOUT_TIME := 12.0
const SET_TOLERANCE := 1.0
const VERDICT_TIME := 3.0

## Set piece name, size, colour.
const KENNEY := "res://assets/kenney/"
## Model per entry in PIECES, and whether to stretch it to fill the piece's box.
const PIECE_MODELS := [
	["castle-kit/tree-large.glb", false],
	["castle-kit/wall.glb", false],
	["furniture-kit/loungeDesignChair.glb", false],
]
const PIECES := [
	["TREE", Vector3(0.6, 2.2, 0.6), Color(0.2, 0.55, 0.2)],
	["CASTLE_WALL", Vector3(2.0, 1.8, 0.3), Color(0.55, 0.55, 0.6)],
	["THRONE", Vector3(0.8, 1.4, 0.8), Color(0.85, 0.7, 0.2)],
]
## Where each piece must stand (x, z) in each scene. Scene 0 is the starting layout.
const LAYOUTS := [
	[Vector2(-3.0, -8.0), Vector2(3.0, -9.2), Vector2(3.5, -4.0)],
	[Vector2(3.0, -5.0), Vector2(-2.5, -9.2), Vector2(0.0, -8.5)],
	[Vector2(-3.8, -4.0), Vector2(0.5, -9.2), Vector2(-2.0, -7.5)],
]
const SCENE_NAMES := ["Act 1: The Forest", "Act 2: The Castle", "Act 3: The Throne Room"]

var _pieces: Array[RigidBody3D] = []
var _marks: Array[MeshInstance3D] = []
var _mark_labels: Array[Label3D] = []
var _stage_lights: Array[OmniLight3D] = []
var _work_light: OmniLight3D
var _feed_card: ColorRect
var _feed_label: Label
var _verdict_left := 0.0
var _verdict_event := 0
var _last_sub := -1  # which layout/phase the marks currently show


func _ready() -> void:
	_add_overview(Vector3(0, 6, 11), Vector3(0, 1, -5))
	_build_house()
	_build_stage()
	_build_audience_feed()
	for i in PIECES.size():
		var p: Array = PIECES[i]
		var size: Vector3 = p[1]
		var spot: Vector2 = LAYOUTS[0][i]
		var piece := _prop(p[0], size, p[2], 8.0, Vector3(spot.x, STAGE_TOP + size.y / 2.0 + 0.05, spot.y))
		_dress(piece, KENNEY + PIECE_MODELS[i][0], size, 0.0, PIECE_MODELS[i][1])
		_pieces.append(piece)
	_prop("SKULL", Vector3(0.2, 0.22, 0.24), Color(0.95, 0.93, 0.85), 0.5, Vector3(7.5, STAGE_TOP + 1.0, -4.5))
	_prop("SWORD", Vector3(0.08, 0.08, 1.1), Color(0.8, 0.8, 0.85), 1.0, Vector3(7.5, STAGE_TOP + 1.0, -5.5))
	_prop("FOG_MACHINE", Vector3(0.6, 0.4, 0.5), Color(0.2, 0.2, 0.2), 4.0, Vector3(-7.5, STAGE_TOP + 0.3, -8.0))
	apply_state(Phase.PREP, Event.NONE, 0, 0.0)


# --- show rules ----------------------------------------------------------------


func title() -> String:
	return "Places, Please! (theatre)"


func score_name() -> String:
	return "APPLAUSE"


func live_duration() -> float:
	# The last scene ends the show, so there is one blackout fewer than scenes.
	return SCENE_TIME * LAYOUTS.size() + BLACKOUT_TIME * (LAYOUTS.size() - 1)


func spawn_point(index: int) -> Vector3:
	var side := -1.0 if index % 2 == 0 else 1.0
	return Vector3(side * 7.5, STAGE_TOP + 0.2, -3.5 - (index / 2) * 1.2)


## sub = scene * 2 + (1 while blackout)
static func sub_for(elapsed: float) -> int:
	var cycle := SCENE_TIME + BLACKOUT_TIME
	var scene := int(elapsed / cycle)
	var blackout := fmod(elapsed, cycle) >= SCENE_TIME
	return scene * 2 + (1 if blackout else 0)


func server_tick(delta: float, director: Node) -> void:
	var sub := sub_for(director.live_elapsed())
	var scene := sub / 2
	var blackout := sub % 2 == 1
	if sub != director.sub and not blackout and scene > 0:
		_judge_set(scene % LAYOUTS.size(), director)
	director.sub = sub

	if _verdict_left > 0.0:
		_verdict_left -= delta
		director.event = _verdict_event
		return
	if blackout:
		director.event = Event.NONE
		return

	var actors := 0
	var caught := 0
	for feet in local_player_positions():
		if ACTOR_ZONE.has_point(feet):
			actors += 1
		elif LIT_ZONE.has_point(feet):
			caught += 1
	caught += maxi(actors - 1, 0)
	if actors == 0:
		director.event = Event.EMPTY_STAGE
		director.score -= 3.0 * delta
	elif caught > 0:
		director.event = Event.CAUGHT_IN_LIGHT
		director.score -= 4.0 * delta * caught
	else:
		director.event = Event.NONE
		director.score += 1.0 * delta


## Lights up: the audience sees whether the set is right.
func _judge_set(layout: int, director: Node) -> void:
	var wrong := 0
	for i in _pieces.size():
		var p := _pieces[i].position
		var target: Vector2 = LAYOUTS[layout][i]
		if Vector2(p.x, p.z).distance_to(target) > SET_TOLERANCE or p.y < STAGE_TOP:
			wrong += 1
	director.score += 6.0 * (_pieces.size() - wrong) - 8.0 * wrong
	_verdict_event = Event.WRONG_SET if wrong > 0 else Event.SET_PERFECT
	_verdict_left = VERDICT_TIME


func server_reset() -> void:
	super.server_reset()
	_verdict_left = 0.0


func apply_state(phase: int, _event: int, sub: int, _time_left: float) -> void:
	var live := phase == Phase.LIVE
	var blackout := live and sub % 2 == 1
	for light in _stage_lights:
		light.light_energy = 0.05 if blackout else 1.8
	_work_light.light_energy = 0.6 if blackout else 0.25

	# During a blackout the tape shows the NEXT scene's marks; otherwise the current one.
	var scene := sub / 2 if live else 0
	var layout := (scene + 1) % LAYOUTS.size() if blackout else scene % LAYOUTS.size()
	var marks_key := layout * 10 + phase
	if marks_key != _last_sub:
		_last_sub = marks_key
		for i in _marks.size():
			var spot: Vector2 = LAYOUTS[layout][i]
			_marks[i].position = Vector3(spot.x, STAGE_TOP + 0.01, spot.y)
			_mark_labels[i].position = _marks[i].position + Vector3(0, 0.25, 0.5)
	for i in _marks.size():
		_marks[i].visible = blackout or not live
		_mark_labels[i].visible = blackout or not live

	_feed_card.visible = blackout or not live
	if phase == Phase.PREP:
		_feed_label.text = "HOUSE LIGHTS UP\nThe play begins shortly"
	elif phase == Phase.WRAP:
		_feed_label.text = "CURTAIN CALL"
	elif blackout:
		_feed_label.text = "(blackout)\nThe audience can hear you."


func phase_text(phase: int, clock: String, score: float, sub: int) -> String:
	match phase:
		Phase.PREP:
			return "PREP  %s  -  actor on the yellow STAR, crew in the wings" % clock
		Phase.LIVE:
			if sub % 2 == 1:
				return "BLACKOUT  %s  -  move the set to the glowing marks, quietly!" % clock
			var scene := sub / 2
			return "CURTAIN UP  %s  -  %s" % [clock, SCENE_NAMES[mini(scene, SCENE_NAMES.size() - 1)]]
	return "CURTAIN CALL  -  applause %d" % int(score)


func event_text(event: int) -> String:
	match event:
		Event.EMPTY_STAGE:
			return "EMPTY STAGE! Somebody get on the star!"
		Event.CAUGHT_IN_LIGHT:
			return "CAUGHT IN THE LIGHT! Freeze... or run!"
		Event.WRONG_SET:
			return "WRONG SET! The audience is laughing at you."
		Event.SET_PERFECT:
			return "Perfect scene change! Applause!"
	return ""


# --- building --------------------------------------------------------------------


func _build_house() -> void:
	var wall := Color(0.25, 0.12, 0.12)
	_box(Vector3(28, 0.2, 26), Vector3(0, -0.1, 1), Color(0.18, 0.1, 0.1))
	_box(Vector3(28, 7, 0.3), Vector3(0, 3.5, -12.15), wall)
	_box(Vector3(28, 7, 0.3), Vector3(0, 3.5, 14.15), wall)
	_box(Vector3(0.3, 7, 26), Vector3(-14.15, 3.5, 1), wall)
	_box(Vector3(0.3, 7, 26), Vector3(14.15, 3.5, 1), wall)
	# Seats.
	for row in 6:
		for x in [-6.0, -3.0, 0.0, 3.0, 6.0]:
			var seats := _box(Vector3(2.4, 0.5, 0.6), Vector3(x, 0.25, 2.0 + row * 1.5), Color(0.5, 0.08, 0.1))
			_dress(seats, KENNEY + "furniture-kit/benchCushion.glb", Vector3(2.4, 0.5, 0.6), PI, true)
	_work_light = _light(Vector3(0, 5, 6), 0.25, 14.0, Color(0.6, 0.7, 1.0))


func _build_stage() -> void:
	_box(Vector3(20, STAGE_TOP, 8), Vector3(0, STAGE_TOP / 2.0, -6), Color(0.35, 0.25, 0.15))
	for side in [-1.0, 1.0]:
		_box(Vector3(1.5, 0.4, 1.2), Vector3(side * 10.8, 0.2, -3.5), Color(0.3, 0.3, 0.3))  # steps
		# Proscenium: hides the wings from the audience.
		_box(Vector3(9, 7, 0.4), Vector3(side * 9.5, 3.5, -2.0), Color(0.45, 0.08, 0.1))
	_box(Vector3(10, 1.6, 0.4), Vector3(0, 6.2, -2.0), Color(0.45, 0.08, 0.1))  # header
	_box(Vector3(10, 5, 0.1), Vector3(0, STAGE_TOP + 2.5, -11.8), Color(0.15, 0.15, 0.25), false)  # cyc
	_tape_rect(ACTOR_ZONE, Color(1, 0.9, 0.2), STAGE_TOP + 0.006)
	_sign("STAR", Vector3(0, STAGE_TOP + 0.3, -6), 64)
	_sign("STAGE LEFT", Vector3(7.5, STAGE_TOP + 2.2, -6))
	_sign("STAGE RIGHT", Vector3(-7.5, STAGE_TOP + 2.2, -6))
	for x in [-3.0, 0.0, 3.0]:
		_stage_lights.append(_light(Vector3(x, 5.0, -4.0), 1.8, 8.0, Color(1.0, 0.92, 0.8)))
	# Blue backstage work lights so the wings are never pitch black.
	_light(Vector3(7.5, 3.0, -6.0), 0.5, 5.0, Color(0.4, 0.5, 1.0))
	_light(Vector3(-7.5, 3.0, -6.0), 0.5, 5.0, Color(0.4, 0.5, 1.0))
	# Glow tape marks (moved around per scene in apply_state).
	for i in PIECES.size():
		var mark := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.9, 0.02, 0.9)
		mark.mesh = mesh
		mark.material_override = _mat(Color(0.3, 1.0, 0.6), 2.5)
		add_child(mark)
		_marks.append(mark)
		var label := _sign(PIECES[i][0], Vector3.ZERO, 40)
		label.modulate = Color(0.4, 1.0, 0.7)
		_mark_labels.append(label)


func _build_audience_feed() -> void:
	var viewport := _make_feed(Vector3(0, 2.6, 9.0), Vector3(0, 1.8, -6.0), 45.0)
	var overlay := Control.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	viewport.add_child(overlay)
	var tag := Label.new()
	tag.text = " AUDIENCE VIEW "
	tag.add_theme_font_size_override("font_size", 22)
	tag.position = Vector2(12, 10)
	overlay.add_child(tag)
	_feed_card = ColorRect.new()
	_feed_card.color = Color(0, 0, 0, 0.75)
	_feed_card.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(_feed_card)
	_feed_label = Label.new()
	_feed_label.add_theme_font_size_override("font_size", 30)
	_feed_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_feed_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_feed_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_feed_card.add_child(_feed_label)
	# Monitors in both wings so the crew can see what the audience sees.
	var feed := viewport.get_texture()
	_monitor(feed, Vector3(9.5, STAGE_TOP + 2.0, -9.5), Vector2(2.4, 1.35), Vector3(7.5, 2, -5))
	_monitor(feed, Vector3(-9.5, STAGE_TOP + 2.0, -9.5), Vector2(2.4, 1.35), Vector3(-7.5, 2, -5))
