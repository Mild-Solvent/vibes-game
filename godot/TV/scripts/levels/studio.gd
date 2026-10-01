extends "res://scripts/levels/level.gd"
## "We're Live!": Channel 6's TV news studio.
##
## Layout (local metres, looking from the back of the room towards the set):
##   z = -8 .. -4  the SET: backdrop, news desk, anchor spot (DESK_ZONE, green tape)
##   z ~ -2 ..  2  three studio cameras on pedestals (CAM 1 is the default shot; yellow tape
##                 marks the edges of its frame)
##   z =  3 .. 10  BACKSTAGE: prop table, the control desk (gallery), big broadcast monitor
##
## Rules: one anchor on the green tape, in frame of the camera on air, nobody else in that
## frame -> ratings climb. Nobody at the desk -> dead air. Crew in the on-air shot or the
## anchor out of frame -> ratings drain.
##
## Show state outside the director (which camera is on air, REC, the teleprompter text) lives
## here: anyone asks the host (`request_*`), the host broadcasts `_show_state` to everyone.

enum Event { NONE, DEAD_AIR, CREW_IN_SHOT, OFF_FRAME, NOTHING_TO_SEE, FIELD_REPORT }

const CameraRig := preload("res://scripts/camera_rig.gd")
const ControlDesk := preload("res://scripts/control_desk.gd")
const Broadcast := preload("res://scripts/broadcast.gd")
const City := preload("res://scripts/levels/city.gd")
const FieldCamera := preload("res://scripts/field_camera.gd")

const FURNITURE := "res://assets/kenney/furniture-kit/"
const DESK_ZONE := AABB(Vector3(-1.5, -1.0, -6.4), Vector3(3.0, 4.0, 1.8))
const ANCHOR_SPOT := Vector3(0, 1.3, -5.4)
## Studio cameras: label, floor position, point it looks at, field of view.
const CAMERAS := [
	["CAM 1  wide", Vector3(0, 0, 1.55), Vector3(0, 1.25, -5.0), 50.0],
	["CAM 2  left", Vector3(-4.5, 0, -0.8), Vector3(0, 1.3, -5.2), 38.0],
	["CAM 3  close", Vector3(4.2, 0, -1.6), Vector3(0, 1.45, -5.3), 26.0],
]
const SHOT_RANGE := 22.0
const STATE_INTERVAL := 1.0
const NEWS_LINE := "CHANNEL 6 EVENING NEWS  |  Local man finds cat. More at eleven."
const TICKER := "Weather: grey, then greyer  ·  Traffic: yes  ·  Local cat found  ·  Stay tuned"

# Synced show state (host decides, everyone gets it through _show_state).
var take := 0
var recording := false
var subtitle := ""

var broadcast: Broadcast
var rigs: Array = []
var field_camera: FieldCamera

var _phase := Phase.PREP
var _state_timer := 0.0
var _prompter_text: Label3D
var _sun: DirectionalLight3D
var _door_light: StandardMaterial3D


func _ready() -> void:
	_add_overview(Vector3(10, 3.4, 9), Vector3(0, 1, -3))
	_light(Vector3(-2.5, 3.6, -3.0), 1.6, 7.0)
	_light(Vector3(2.5, 3.6, -3.0), 1.6, 7.0)
	_light(Vector3(0, 3.6, 6.0), 1.0, 10.0, Color(0.8, 0.85, 1.0))
	_build_room()
	_build_set()
	_build_cameras()
	_build_field_camera()
	_build_broadcast()
	_build_props()
	City.new().build(self)


func make_environment() -> Environment:
	var env := Environment.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.32, 0.52, 0.85)
	sky_mat.sky_horizon_color = Color(0.72, 0.8, 0.9)
	sky_mat.ground_horizon_color = Color(0.6, 0.62, 0.6)
	sky_mat.ground_bottom_color = Color(0.4, 0.42, 0.4)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.6, 0.62, 0.68)
	env.ambient_light_energy = 0.7
	return env


## The sun is global (lights every level), so it is on only while the studio is played.
func set_active(active: bool) -> void:
	_sun.visible = active


# --- show rules ----------------------------------------------------------------


func title() -> String:
	return "We're Live! (TV studio)"


func score_name() -> String:
	return "RATINGS"


func is_live() -> bool:
	return _phase == Phase.LIVE


func server_tick(delta: float, director: Node) -> void:
	if broadcast.sources[take] == field_camera:
		_field_tick(delta, director)
		return
	var cam := broadcast.active_camera()
	var anchors := 0
	var anchors_in_frame := 0
	var crew_in_shot := 0
	var blockers := _non_static_rids()
	var operators := []
	for rig in rigs:
		operators.append(rig.operator_id)
	for player in get_tree().get_nodes_in_group("players"):
		if player.peer_id in operators:
			continue  # behind their own camera
		var feet: Vector3 = player.global_position
		var seen := _visible_to(cam, feet + Vector3.UP * 1.5, blockers) or _visible_to(cam, feet + Vector3.UP, blockers)
		if DESK_ZONE.has_point(to_local(player.global_position)):
			anchors += 1
			if seen:
				anchors_in_frame += 1
		elif seen:
			crew_in_shot += 1

	var extra := crew_in_shot + maxi(anchors_in_frame - 1, 0)
	if anchors == 0:
		director.event = Event.DEAD_AIR
		director.score -= 3.0 * delta
	elif extra > 0:
		director.event = Event.CREW_IN_SHOT
		director.score -= 4.0 * delta * extra
	elif anchors_in_frame == 0:
		director.event = Event.OFF_FRAME
		director.score -= 2.0 * delta
	else:
		director.event = Event.NONE
		director.score += 1.0 * delta


## The field camera is on air: anyone in its picture is "our reporter on the scene".
func _field_tick(delta: float, director: Node) -> void:
	var cam := broadcast.active_camera()
	var blockers := _non_static_rids()
	var on_screen := 0
	for player in get_tree().get_nodes_in_group("players"):
		if player.peer_id == field_camera.holder_id:
			continue
		var feet: Vector3 = player.global_position
		if _visible_to(cam, feet + Vector3.UP * 1.5, blockers) or _visible_to(cam, feet + Vector3.UP, blockers):
			on_screen += 1
	if on_screen > 0:
		director.event = Event.FIELD_REPORT
		director.score += 1.0 * delta
	else:
		director.event = Event.NOTHING_TO_SEE
		director.score -= 1.5 * delta


func server_reset() -> void:
	super.server_reset()
	for rig in rigs:
		rig.reset_aim()
	take = 0
	recording = false
	subtitle = ""
	_send_state()


func apply_state(phase: int, event: int, _sub: int, _time_left: float) -> void:
	var phase_changed := phase != _phase
	_phase = phase
	var live := phase == Phase.LIVE
	_door_light.emission_enabled = live
	for i in broadcast.sources.size():
		broadcast.sources[i].on_air = live and i == take
	match phase:
		Phase.PREP:
			broadcast.set_status(" STANDBY ", Color(1, 0.85, 0.3))
		Phase.LIVE:
			broadcast.set_status(" ● LIVE ", Color(1, 0.3, 0.3))
		Phase.WRAP:
			broadcast.set_status(" OFF AIR ", Color(0.7, 0.7, 0.7))
	if phase == Phase.PREP:
		broadcast.set_card(true, "CHANNEL 6\nPROGRAMME STARTS SHORTLY")
	elif phase == Phase.WRAP:
		broadcast.set_card(true, "THANKS FOR WATCHING\nCHANNEL 6")
	else:
		broadcast.set_card(event == Event.DEAD_AIR, "TECHNICAL DIFFICULTIES\nPLEASE STAND BY")
	broadcast.set_recording(recording, live)
	if phase_changed:
		if phase == Phase.PREP:
			broadcast.clear_tape()
		elif phase == Phase.WRAP:
			broadcast.start_replay()


func phase_text(phase: int, clock: String, score: float, _sub: int) -> String:
	match phase:
		Phase.PREP:
			return "PREP  %s  -  anchor on the green tape, crew to the cameras and the control desk" % clock
		Phase.LIVE:
			return "● ON AIR  %s   (%s)" % [clock, broadcast.sources[take].label]
	return "WRAP  -  final ratings %d%%" % int(score)


func rules_text() -> String:
	return """[b]WE'RE LIVE![/b]   Channel 6 Evening News. Three minutes, live, no second takes.

[b]ROLES[/b]
 - [b]Anchor[/b]: stands on the green tape behind the news desk and reads the teleprompter out loud.
 - [b]Director[/b]: sits at the CONTROL desk (E). Watches every camera and TAKEs the one that goes on air.
   Also presses RECORD: the recording plays back as "The Tape" on every monitor at the end.
 - [b]Prompter op[/b]: also at the control desk. Types the teleprompter: it shows on the anchor's
   prompter screen and as subtitles on air, live, letter by letter.
 - [b]Camera ops[/b]: E at CAM 1 / 2 / 3 to operate it. Keep the anchor in frame.
 - [b]Field crew[/b]: grab the FIELD CAM from the table by the EXIT and go out into the city.
   When the director TAKEs it, whatever you point it at is on air: get a reporter in the picture.
 - [b]Floor crew[/b]: everyone else. Props, coffee, chaos. Stay out of the on-air shot.

[b]GOAL[/b]: keep the RATINGS up for the whole show.
 - One anchor at the desk, in frame of the camera on air, nobody else in frame: ratings climb.
 - Nobody at the desk: dead air. Crew in the on-air shot, or the anchor out of frame: ratings drain.
 - The yellow floor tape shows CAM 1's default frame. The red tally light shows which camera is on air.

[b]CONTROLS[/b]
 - Control desk: 1-4 or click TAKE, R record, T (or click) to type, Enter = next line, Esc leave.
 - Camera: mouse aims, mouse wheel zooms, Esc leaves.
 - Props: E / left click grab, Q throw."""


func event_text(event: int) -> String:
	match event:
		Event.DEAD_AIR:
			return "DEAD AIR! Nobody is at the desk!"
		Event.CREW_IN_SHOT:
			return "CREW IN SHOT! Get out of the frame!"
		Event.OFF_FRAME:
			return "WHERE'S THE ANCHOR? The camera on air can't see them!"
		Event.NOTHING_TO_SEE:
			return "The FIELD CAM is on air and shows nobody! Find a reporter!"
		Event.FIELD_REPORT:
			return "LIVE FROM THE SCENE"
	return ""


func guide_text() -> String:
	return "E at CONTROL: TAKE cameras, REC, teleprompter\nE at a CAM: operate it\nFIELD CAM by the EXIT: take it outside"


## True if `point` is inside `cam`'s picture and nothing solid is in the way.
func _visible_to(cam: Camera3D, point: Vector3, exclude: Array[RID]) -> bool:
	if not cam.is_position_in_frustum(point):
		return false
	var from := cam.global_position
	if from.distance_to(point) > SHOT_RANGE:
		return false
	var query := PhysicsRayQueryParameters3D.create(from, point)
	query.exclude = exclude
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()


## Players and props don't block the view (they are what we look for).
func _non_static_rids() -> Array[RID]:
	var result: Array[RID] = []
	for node in get_tree().get_nodes_in_group("players"):
		result.append(node.get_rid())
	for node in get_tree().get_nodes_in_group("props"):
		result.append(node.get_rid())
	return result


## Testing (--seat=desk / --seat=cam1..3 on the command line).
func debug_seat(player: Node, seat: String) -> void:
	if seat == "field":  # out in the city with the field camera, on air
		player.global_position = to_global(Vector3(31, 0.1, 30))
		player.rotation.y = -PI * 0.6
		field_camera.global_position = player.hold_point()
		player._held = field_camera
		field_camera.request_grab.rpc_id(1)
		request_take.rpc_id(1, broadcast.sources.find(field_camera))
	elif seat == "anchor":
		player.global_position = to_global(Vector3(0, 0.1, -5.4))
		player.rotation.y = PI
	elif seat == "desk":
		get_node("ControlDesk").interact(player)
	elif seat.begins_with("cam"):
		rigs[clampi(seat.trim_prefix("cam").to_int() - 1, 0, rigs.size() - 1)].interact(player)


# --- networked show state ------------------------------------------------------------


@rpc("any_peer", "call_local", "reliable")
func request_take(index: int) -> void:
	if multiplayer.is_server() and index >= 0 and index < broadcast.sources.size():
		take = index
		_send_state()


@rpc("any_peer", "call_local", "reliable")
func request_record(on: bool) -> void:
	if multiplayer.is_server():
		recording = on
		_send_state()


@rpc("any_peer", "call_local", "reliable")
func request_subtitle(text: String) -> void:
	if multiplayer.is_server():
		subtitle = text.substr(0, 90)
		_send_state()


func _send_state() -> void:
	_state_timer = STATE_INTERVAL
	if Net.is_online():
		_show_state.rpc(take, recording, subtitle)


@rpc("authority", "call_local", "reliable")
func _show_state(new_take: int, new_recording: bool, new_subtitle: String) -> void:
	take = new_take
	recording = new_recording
	subtitle = new_subtitle
	broadcast.set_active(take)
	broadcast.set_subtitle(subtitle)
	broadcast.set_recording(recording, is_live())
	_prompter_text.text = subtitle if not subtitle.is_empty() else "PROMPTER"
	for i in broadcast.sources.size():
		broadcast.sources[i].on_air = is_live() and i == take


func _process(delta: float) -> void:
	if not Net.is_online() or not multiplayer.is_server():
		return
	_state_timer -= delta
	if _state_timer <= 0.0:
		_send_state()


# --- building --------------------------------------------------------------------


func _build_room() -> void:
	var wall := Color(0.32, 0.33, 0.36)
	_box(Vector3(24, 0.2, 18), Vector3(0, -0.1, 1), Color(0.22, 0.22, 0.24))
	_box(Vector3(24, 4, 0.3), Vector3(0, 2, -8.15), wall)
	_box(Vector3(24, 4, 0.3), Vector3(0, 2, 10.15), wall)
	_box(Vector3(0.3, 4, 18), Vector3(-12.15, 2, 1), wall)
	# East wall with the door to the city (z 2.8 .. 5.2).
	_box(Vector3(0.3, 4, 10.8), Vector3(12.15, 2, -2.6), wall)
	_box(Vector3(0.3, 4, 4.8), Vector3(12.15, 2, 7.6), wall)
	_box(Vector3(0.3, 1.2, 2.4), Vector3(12.15, 3.4, 4.0), wall)
	_box(Vector3(24.6, 0.3, 18.6), Vector3(0, 4.15, 1), Color(0.25, 0.25, 0.27))  # roof
	_sign("EXIT -> CITY", Vector3(11.6, 3.1, 4.0), 48)
	var facade := Label3D.new()
	facade.text = "CHANNEL 6 STUDIOS"
	facade.font_size = 160
	facade.pixel_size = 0.01
	facade.outline_size = 24
	facade.modulate = Color(1, 0.85, 0.3)
	facade.position = Vector3(12.32, 3.5, -3.5)
	facade.rotation.y = PI / 2.0
	add_child(facade)
	_door_light = _mat(Color(0.3, 0.05, 0.05))
	_door_light.emission = Color(1, 0.1, 0.1)
	_door_light.emission_energy_multiplier = 2.5
	var on_air_sign := _box(Vector3(0.1, 0.4, 1.2), Vector3(12.35, 3.2, 4.0), Color.WHITE, false) as MeshInstance3D
	on_air_sign.material_override = _door_light
	var on_air_text := Label3D.new()
	on_air_text.text = "ON AIR"
	on_air_text.font_size = 48
	on_air_text.pixel_size = 0.006
	on_air_text.position = Vector3(12.41, 3.2, 4.0)
	on_air_text.rotation.y = PI / 2.0
	add_child(on_air_text)

	_sun = DirectionalLight3D.new()
	_sun.rotation = Vector3(deg_to_rad(-55), deg_to_rad(35), 0)
	_sun.light_energy = 1.1
	_sun.shadow_enabled = true
	_sun.directional_shadow_max_distance = 70.0
	add_child(_sun)
	var prop_table := Vector3(3, 0.9, 1)
	var table := _box(prop_table, Vector3(-6, 0.45, 6), Color(0.45, 0.32, 0.2))
	_dress(table, FURNITURE + "tableCross.glb", prop_table, 0.0, true)
	_sign("PROPS", Vector3(-6, 1.6, 6))
	_sign("CONTROL", Vector3(6, 1.9, 6.4))
	var shelf := Vector3(1.0, 1.8, 0.4)
	_dress(_box(shelf, Vector3(-10.5, 0.9, 9.6), Color.GRAY), FURNITURE + "bookcaseOpen.glb", shelf, PI, true)


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

	# Yellow tape roughly where CAM 1's default shot ends. Cross it and you're on TV.
	var cam1: Array = CAMERAS[0]
	var half_hfov := atan(tan(deg_to_rad(cam1[3] / 2.0)) * 16.0 / 9.0)
	var origin := Vector2(cam1[1].x, cam1[1].z - 0.6)
	for side in [-1.0, 1.0]:
		_tape(origin, origin + Vector2(side * tan(half_hfov) * 8.0, -8.0), Color(1, 0.85, 0.1))

	# Teleprompter: a screen on a stand facing the anchor; shows what the prompter op types.
	# It stands beside CAM 1, out of every camera's default shot.
	var prompter_pos := Vector3(-1.4, 1.55, 0.7)
	_box(Vector3(0.08, 1.1, 0.08), Vector3(prompter_pos.x, 0.55, prompter_pos.z), Color(0.15, 0.15, 0.15))
	var screen := _box(Vector3(1.5, 0.85, 0.08), prompter_pos, Color(0.03, 0.03, 0.05), false)
	screen.look_at_from_position(prompter_pos, prompter_pos * 2.0 - ANCHOR_SPOT)
	_prompter_text = Label3D.new()
	_prompter_text.text = "PROMPTER"
	_prompter_text.font_size = 56
	_prompter_text.pixel_size = 0.004
	_prompter_text.outline_size = 0
	_prompter_text.width = 360.0
	_prompter_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_prompter_text.modulate = Color(0.95, 1, 0.95)
	_prompter_text.position = Vector3(0, 0, 0.05)  # +Z faces the anchor
	screen.add_child(_prompter_text)


func _build_cameras() -> void:
	for entry in CAMERAS:
		var rig := CameraRig.new()
		rig.position = entry[1]
		add_child(rig)
		rig.setup(entry[0], entry[2], entry[3])
		rigs.append(rig)

	var control_size := Vector3(3, 0.9, 1)
	var desk := ControlDesk.new()
	desk.position = Vector3(6, 0.45, 6)
	desk.setup(self, control_size)
	add_child(desk)
	desk.add_child(ModelFit.fit(FURNITURE + "desk.glb", control_size, PI, true))
	var screen := Vector3(0.6, 0.5, 0.2)
	for x in [-0.6, 0.6]:
		var monitor := ModelFit.fit(FURNITURE + "computerScreen.glb", screen, PI)
		monitor.position += Vector3(x, 0.7, 0.3)
		desk.add_child(monitor)


## The handheld camera, on a table by the exit door.
func _build_field_camera() -> void:
	var table_size := Vector3(1.6, 0.8, 0.8)
	var table := _box(table_size, Vector3(10.6, 0.4, 7.6), Color(0.45, 0.32, 0.2))
	_dress(table, FURNITURE + "tableCross.glb", table_size, PI / 2.0, true)
	_sign("FIELD KIT", Vector3(10.6, 1.7, 7.6), 48)
	var size := Vector3(0.24, 0.26, 0.6)
	var mesh := BoxMesh.new()
	mesh.size = size
	var shape := BoxShape3D.new()
	shape.size = size
	field_camera = FieldCamera.new()
	field_camera.setup("FIELD_CAM", mesh, shape, Color(0.15, 0.15, 0.17), 2.0)
	field_camera.position = Vector3(10.6, 1.0, 7.6)
	field_camera.rotation.y = PI / 2.0
	add_child(field_camera)
	field_camera.dress()


## The broadcast: the cameras feed the PROGRAM (with the channel graphics); its texture is
## shown on the big monitor backstage, a confidence monitor for the anchor and the desk.
func _build_broadcast() -> void:
	broadcast = Broadcast.new()
	broadcast.name = "Broadcast"
	broadcast.sources = rigs.duplicate()
	broadcast.sources.append(field_camera)
	add_child(broadcast)
	broadcast.build()
	broadcast.set_lower_third("", NEWS_LINE)
	broadcast.set_ticker(TICKER)

	var feed := broadcast.texture()
	_monitor(feed, Vector3(0, 2.4, 9.95), Vector2(4.8, 2.7), Vector3(0, 2.4, 0))
	_box(Vector3(0.1, 1.1, 0.1), Vector3(1.4, 0.55, 0.7), Color(0.15, 0.15, 0.15))
	_monitor(feed, Vector3(1.4, 1.5, 0.7), Vector2(1.4, 0.79), ANCHOR_SPOT)
	_monitor(feed, Vector3(6, 1.75, 6.75), Vector2(1.6, 0.9), Vector3(6, 1.75, 4))
	_show_state(take, recording, subtitle)
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
