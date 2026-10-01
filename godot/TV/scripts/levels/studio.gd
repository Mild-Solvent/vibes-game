extends "res://scripts/levels/level.gd"
## "We're Live!": grey-box TV news studio.
##
## Layout (local metres, looking from the back of the room towards the set):
##   z = -8 .. -4  the SET: backdrop, news desk, anchor spot (DESK_ZONE, green tape)
##   z ~  1        the on-air camera; yellow floor tape marks the edges of its shot
##   z =  3 .. 10  BACKSTAGE: prop table, control desk, big broadcast monitor
##
## Rules: exactly one anchor on the green tape and nobody else in shot -> ratings climb.
## Nobody at the desk -> dead air. Crew visible to the on-air camera -> ratings drain.

enum Event { NONE, DEAD_AIR, CREW_IN_SHOT }

const FURNITURE := "res://assets/kenney/furniture-kit/"
const DESK_ZONE := AABB(Vector3(-1.5, -1.0, -6.4), Vector3(3.0, 4.0, 1.8))
const ON_AIR_CAMERA_POS := Vector3(0, 1.6, 1.0)
const ON_AIR_CAMERA_TARGET := Vector3(0, 1.25, -5.0)
const ON_AIR_FOV := 50.0

var on_air_camera: Camera3D

var _tally_material: StandardMaterial3D
var _status_tag: Label
var _card: ColorRect
var _card_label: Label


func _ready() -> void:
	_add_overview(Vector3(9, 7, 9), Vector3(0, 1, -2))
	_light(Vector3(-2.5, 3.6, -3.0), 1.6, 7.0)
	_light(Vector3(2.5, 3.6, -3.0), 1.6, 7.0)
	_light(Vector3(0, 3.6, 6.0), 1.0, 10.0, Color(0.8, 0.85, 1.0))
	_build_room()
	_build_set()
	_build_broadcast()
	_build_props()


# --- show rules ----------------------------------------------------------------


func title() -> String:
	return "We're Live! (TV studio)"


func score_name() -> String:
	return "RATINGS"


func server_tick(delta: float, director: Node) -> void:
	var anchors := 0
	var crew_in_shot := 0
	for player in get_tree().get_nodes_in_group("players"):
		var feet: Vector3 = player.global_position
		if DESK_ZONE.has_point(to_local(feet)):
			anchors += 1
		elif _in_shot(feet):
			crew_in_shot += 1

	var extra := crew_in_shot + maxi(anchors - 1, 0)
	if anchors == 0:
		director.event = Event.DEAD_AIR
		director.score -= 3.0 * delta
	elif extra > 0:
		director.event = Event.CREW_IN_SHOT
		director.score -= 4.0 * delta * extra
	else:
		director.event = Event.NONE
		director.score += 1.0 * delta


func apply_state(phase: int, event: int, _sub: int, _time_left: float) -> void:
	var live := phase == Phase.LIVE
	_tally_material.emission_enabled = live
	_tally_material.albedo_color = Color(1, 0.1, 0.1) if live else Color(0.25, 0.05, 0.05)
	match phase:
		Phase.PREP:
			_status_tag.text = " STANDBY "
			_status_tag.modulate = Color(1, 0.85, 0.3)
		Phase.LIVE:
			_status_tag.text = " ● LIVE "
			_status_tag.modulate = Color(1, 0.3, 0.3)
		Phase.WRAP:
			_status_tag.text = " OFF AIR "
			_status_tag.modulate = Color(0.7, 0.7, 0.7)
	_card.visible = not live or event == Event.DEAD_AIR
	if phase == Phase.PREP:
		_card_label.text = "CHANNEL 6\nPROGRAMME STARTS SHORTLY"
	elif phase == Phase.WRAP:
		_card_label.text = "THANKS FOR WATCHING\nCHANNEL 6"
	else:
		_card_label.text = "TECHNICAL DIFFICULTIES\nPLEASE STAND BY"


func phase_text(phase: int, clock: String, score: float, _sub: int) -> String:
	match phase:
		Phase.PREP:
			return "PREP  %s  -  anchor on the green tape, crew out of shot" % clock
		Phase.LIVE:
			return "● ON AIR  %s" % clock
	return "WRAP  -  final ratings %d%%" % int(score)


func rules_text() -> String:
	return """[b]WE'RE LIVE![/b]   Channel 6 Evening News. Three minutes, live, no second takes.

[b]ROLES[/b]
 - [b]Anchor[/b]: stands on the green tape behind the news desk and reads the news.
 - [b]Crew[/b]: everyone else. Stay behind the yellow floor tape: that is the edge of the shot.

[b]GOAL[/b]: keep the RATINGS up for the whole show.
 - One anchor at the desk and nobody else in frame: ratings climb.
 - Nobody at the desk: dead air. Crew walking into the shot: ratings drain.

[b]CONTROLS[/b]: E / left click grab props (tapes, boxes, coffee), Q throws them."""


func event_text(event: int) -> String:
	match event:
		Event.DEAD_AIR:
			return "DEAD AIR! Nobody is at the desk!"
		Event.CREW_IN_SHOT:
			return "CREW IN SHOT! Get out of the frame!"
	return ""


func _in_shot(feet: Vector3) -> bool:
	var chest := feet + Vector3.UP
	return on_air_camera.is_position_in_frustum(chest) and on_air_camera.global_position.distance_to(chest) < 14.0


# --- building --------------------------------------------------------------------


func _build_room() -> void:
	var wall := Color(0.32, 0.33, 0.36)
	_box(Vector3(24, 0.2, 18), Vector3(0, -0.1, 1), Color(0.22, 0.22, 0.24))
	_box(Vector3(24, 4, 0.3), Vector3(0, 2, -8.15), wall)
	_box(Vector3(24, 4, 0.3), Vector3(0, 2, 10.15), wall)
	_box(Vector3(0.3, 4, 18), Vector3(-12.15, 2, 1), wall)
	_box(Vector3(0.3, 4, 18), Vector3(12.15, 2, 1), wall)
	var prop_table := Vector3(3, 0.9, 1)
	_dress(_box(prop_table, Vector3(-6, 0.45, 6), Color(0.45, 0.32, 0.2)), FURNITURE + "tableCross.glb", prop_table, 0.0, true)
	_sign("PROPS", Vector3(-6, 1.6, 6))
	var control_desk := Vector3(3, 0.9, 1)
	_dress(_box(control_desk, Vector3(6, 0.45, 6), Color(0.2, 0.2, 0.25)), FURNITURE + "desk.glb", control_desk, PI, true)
	var screen := Vector3(0.6, 0.5, 0.2)
	for x in [5.4, 6.6]:
		_dress(_box(screen, Vector3(x, 1.15, 6.3), Color.BLACK), FURNITURE + "computerScreen.glb", screen, PI)
	var shelf := Vector3(1.0, 1.8, 0.4)
	_dress(_box(shelf, Vector3(-10.5, 0.9, 9.6), Color.GRAY), FURNITURE + "bookcaseOpen.glb", shelf, PI, true)
	_sign("CONTROL", Vector3(6, 1.6, 6))


func _build_set() -> void:
	_box(Vector3(8, 3, 0.1), Vector3(0, 2, -7.75), Color(0.12, 0.25, 0.55), false)
	var logo := Label3D.new()
	logo.text = "CHANNEL 6\nEVENING NEWS"
	logo.font_size = 96
	logo.pixel_size = 0.006
	logo.position = Vector3(0, 2.6, -7.68)
	add_child(logo)

	var news_desk := Vector3(3, 1, 0.8)
	_dress(_box(news_desk, Vector3(0, 0.5, -4.2), Color(0.75, 0.75, 0.8)), FURNITURE + "desk.glb", news_desk, 0.0, true)
	_box(Vector3(3.1, 0.06, 0.9), Vector3(0, 1.03, -4.2), Color(0.1, 0.2, 0.45))
	_tape_rect(DESK_ZONE, Color(0.2, 0.9, 0.4))

	# The on-air camera rig, with a tally light that glows when LIVE.
	_box(Vector3(0.3, 1.3, 0.3), Vector3(0, 0.65, 1.55), Color(0.15, 0.15, 0.15))
	_box(Vector3(0.5, 0.45, 0.8), Vector3(0, 1.5, 1.55), Color(0.1, 0.1, 0.12))
	_tally_material = _mat(Color(0.25, 0.05, 0.05))
	_tally_material.emission = Color(1, 0.1, 0.1)
	_tally_material.emission_energy_multiplier = 3.0
	var tally := _box(Vector3(0.15, 0.1, 0.05), Vector3(0, 1.8, 1.2), Color.WHITE, false) as MeshInstance3D
	tally.material_override = _tally_material

	# Yellow tape roughly where the shot's edges are. Cross it and you're on TV.
	var half_hfov := atan(tan(deg_to_rad(ON_AIR_FOV / 2.0)) * 16.0 / 9.0)
	var origin := Vector2(ON_AIR_CAMERA_POS.x, ON_AIR_CAMERA_POS.z)
	for side in [-1.0, 1.0]:
		_tape(origin, origin + Vector2(side * tan(half_hfov) * 8.5, -8.5), Color(1, 0.85, 0.1))


## The on-air camera renders into a SubViewport; that texture is "the broadcast", shown on a big
## monitor backstage and a confidence monitor for the anchor. The director's camera switcher
## and The Tape recording plug in here later.
func _build_broadcast() -> void:
	var viewport := _make_feed(ON_AIR_CAMERA_POS, ON_AIR_CAMERA_TARGET, ON_AIR_FOV)
	on_air_camera = viewport.get_child(0)

	var overlay := Control.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	viewport.add_child(overlay)

	var bar := ColorRect.new()
	bar.color = Color(0.08, 0.15, 0.4, 0.9)
	bar.anchor_top = 0.8
	bar.anchor_bottom = 0.92
	bar.anchor_right = 1.0
	overlay.add_child(bar)
	var lower_third := Label.new()
	lower_third.text = "  CHANNEL 6 EVENING NEWS  |  Local man finds cat. More at eleven."
	lower_third.add_theme_font_size_override("font_size", 22)
	lower_third.set_anchors_preset(Control.PRESET_FULL_RECT)
	lower_third.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	bar.add_child(lower_third)

	_status_tag = Label.new()
	_status_tag.add_theme_font_size_override("font_size", 26)
	_status_tag.position = Vector2(16, 12)
	overlay.add_child(_status_tag)

	_card = ColorRect.new()
	_card.color = Color(0.15, 0.15, 0.18)
	_card.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(_card)
	_card_label = Label.new()
	_card_label.add_theme_font_size_override("font_size", 34)
	_card_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_card_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_card_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_card.add_child(_card_label)

	var feed := viewport.get_texture()
	_monitor(feed, Vector3(0, 2.4, 9.95), Vector2(4.8, 2.7), Vector3(0, 1.6, 0))
	_box(Vector3(0.1, 1.0, 0.1), Vector3(3.6, 0.5, -2.6), Color(0.15, 0.15, 0.15))
	_monitor(feed, Vector3(3.6, 1.3, -2.6), Vector2(1.2, 0.675), Vector3(0, 1.4, -5.4))

	apply_state(Phase.PREP, Event.NONE, 0, 0.0)


func _build_props() -> void:
	var tape := Vector3(0.32, 0.07, 0.2)
	_prop("VT_CAT_TREE", tape, Color(0.9, 0.9, 0.9), 0.4, Vector3(-6.8, 1.0, 6))
	_prop("VT_CAT_TREE_FINAL_v2", tape, Color(0.85, 0.85, 0.7), 0.4, Vector3(-6.2, 1.0, 6))
	_prop("VT_WEATHER", tape, Color(0.5, 0.8, 1.0), 0.4, Vector3(-5.6, 1.0, 6))
	_prop("CUE_SHEET", Vector3(0.3, 0.02, 0.4), Color(1, 1, 0.85), 0.2, Vector3(-5.0, 1.0, 6.2))
	var crate := Vector3(0.6, 0.6, 0.6)
	var box_a := _prop("BOX_A", crate, Color(0.65, 0.48, 0.3), 3.0, Vector3(-8.5, 0.4, 3.5))
	_dress(box_a, FURNITURE + "cardboardBoxClosed.glb", crate, 0.0, true)
	var box_b := _prop("BOX_B", crate, Color(0.65, 0.48, 0.3), 3.0, Vector3(-8.5, 1.1, 3.5))
	_dress(box_b, FURNITURE + "cardboardBoxClosed.glb", crate, 0.0, true)
	var chair := Vector3(0.55, 0.9, 0.55)
	var anchor_chair := _prop("ANCHOR_CHAIR", chair, Color(0.15, 0.15, 0.2), 6.0, Vector3(0.8, 0.5, -5.6))
	_dress(anchor_chair, FURNITURE + "chairDesk.glb", chair)
	_prop("COFFEE", Vector3(0.09, 0.14, 0.09), Color(0.95, 0.95, 0.95), 0.3, Vector3(0.6, 1.2, -4.2))
	var cone := Vector3(0.35, 0.55, 0.35)
	var traffic_cone := _prop("TRAFFIC_CONE", cone, Color(1, 0.45, 0.1), 1.0, Vector3(6.5, 0.4, 3.5))
	_dress(traffic_cone, "res://assets/kenney/car-kit/cone.glb", cone)
	var plant := Vector3(0.4, 1.2, 0.4)
	_dress(_prop("PLANT", plant, Color(0.2, 0.6, 0.25), 2.0, Vector3(-3.5, 0.7, -6.8)), FURNITURE + "pottedPlant.glb", plant)
