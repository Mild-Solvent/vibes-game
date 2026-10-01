extends Node3D
## Grey-box TV studio for "We're Live!". Built from code so it is easy to tweak
## until the artist's real assets replace it.
##
## Layout (metres, looking from the back of the room towards the set):
##   z = -8 .. -4  the SET: backdrop, news desk, anchor spot (DESK_ZONE)
##   z ~  1        the on-air camera; yellow floor tape marks the edges of its shot
##   z =  3 .. 10  BACKSTAGE: prop table, control desk, big broadcast monitor

const PropScript := preload("res://scripts/prop.gd")
const ShowDirector := preload("res://scripts/show_director.gd")

const ON_AIR_CAMERA_POS := Vector3(0, 1.6, 1.0)
const ON_AIR_CAMERA_TARGET := Vector3(0, 1.25, -5.0)
const ON_AIR_FOV := 50.0
const BROADCAST_SIZE := Vector2i(640, 360)

var on_air_camera: Camera3D
var overview_camera: Camera3D

var _tally_material: StandardMaterial3D
var _status_tag: Label
var _lower_third: Label
var _card: ColorRect
var _card_label: Label


func _ready() -> void:
	_build_environment()
	_build_room()
	_build_set()
	_build_backstage()
	_build_broadcast()
	_build_props()


func spawn_point(index: int) -> Vector3:
	return Vector3(-4.0 + (index % 5) * 2.0, 0.2, 5.0 + (index / 5) * 1.5)


## Updates everything the "audience" sees: tally light, on-screen graphics, cards.
func set_show_state(phase: int, event: int) -> void:
	var live := phase == ShowDirector.Phase.LIVE
	_tally_material.emission_enabled = live
	_tally_material.albedo_color = Color(1, 0.1, 0.1) if live else Color(0.25, 0.05, 0.05)
	match phase:
		ShowDirector.Phase.PREP:
			_status_tag.text = " STANDBY "
			_status_tag.modulate = Color(1, 0.85, 0.3)
		ShowDirector.Phase.LIVE:
			_status_tag.text = " ● LIVE "
			_status_tag.modulate = Color(1, 0.3, 0.3)
		ShowDirector.Phase.WRAP:
			_status_tag.text = " OFF AIR "
			_status_tag.modulate = Color(0.7, 0.7, 0.7)
	_card.visible = phase != ShowDirector.Phase.LIVE or event == ShowDirector.Event.DEAD_AIR
	if phase == ShowDirector.Phase.PREP:
		_card_label.text = "CHANNEL 6\nPROGRAMME STARTS SHORTLY"
	elif phase == ShowDirector.Phase.WRAP:
		_card_label.text = "THANKS FOR WATCHING\nCHANNEL 6"
	else:
		_card_label.text = "TECHNICAL DIFFICULTIES\nPLEASE STAND BY"


# --- building blocks -------------------------------------------------------


func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.05, 0.05, 0.07)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.55, 0.6)
	env.ambient_light_energy = 0.6
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	var sun := DirectionalLight3D.new()
	sun.light_energy = 0.35
	sun.transform = Transform3D(Basis(), Vector3.ZERO).looking_at(Vector3(0.3, -1, -0.4))
	add_child(sun)

	# Studio lights over the set: this is where the "front" lives.
	for x in [-2.5, 2.5]:
		var key := OmniLight3D.new()
		key.position = Vector3(x, 3.6, -3.0)
		key.omni_range = 7.0
		key.light_energy = 1.6
		key.light_color = Color(1.0, 0.95, 0.85)
		add_child(key)

	# The menu camera before you have a body.
	overview_camera = Camera3D.new()
	overview_camera.transform = Transform3D(Basis(), Vector3(9, 7, 9)).looking_at(Vector3(0, 1, -2))
	overview_camera.current = true
	add_child(overview_camera)


func _build_room() -> void:
	var wall := Color(0.32, 0.33, 0.36)
	_box(Vector3(24, 0.2, 18), Vector3(0, -0.1, 1), Color(0.22, 0.22, 0.24))  # floor
	_box(Vector3(24, 4, 0.3), Vector3(0, 2, -8.15), wall)
	_box(Vector3(24, 4, 0.3), Vector3(0, 2, 10.15), wall)
	_box(Vector3(0.3, 4, 18), Vector3(-12.15, 2, 1), wall)
	_box(Vector3(0.3, 4, 18), Vector3(12.15, 2, 1), wall)


func _build_set() -> void:
	# Backdrop with the channel logo.
	_box(Vector3(8, 3, 0.1), Vector3(0, 2, -7.75), Color(0.12, 0.25, 0.55), false)
	var logo := Label3D.new()
	logo.text = "CHANNEL 6\nEVENING NEWS"
	logo.font_size = 96
	logo.pixel_size = 0.006
	logo.outline_size = 0
	logo.position = Vector3(0, 2.6, -7.68)
	add_child(logo)

	# News desk; the anchor stands behind it (DESK_ZONE).
	_box(Vector3(3, 1, 0.8), Vector3(0, 0.5, -4.2), Color(0.75, 0.75, 0.8))
	_box(Vector3(3.1, 0.06, 0.9), Vector3(0, 1.03, -4.2), Color(0.1, 0.2, 0.45))
	_tape_rect(ShowDirector.DESK_ZONE, Color(0.2, 0.9, 0.4))

	# The on-air camera rig, with a tally light that glows when LIVE.
	_box(Vector3(0.3, 1.3, 0.3), Vector3(0, 0.65, 1.55), Color(0.15, 0.15, 0.15))
	_box(Vector3(0.5, 0.45, 0.8), Vector3(0, 1.5, 1.55), Color(0.1, 0.1, 0.12))
	_tally_material = StandardMaterial3D.new()
	_tally_material.albedo_color = Color(0.25, 0.05, 0.05)
	_tally_material.emission = Color(1, 0.1, 0.1)
	_tally_material.emission_energy_multiplier = 3.0
	var tally := MeshInstance3D.new()
	var tally_mesh := BoxMesh.new()
	tally_mesh.size = Vector3(0.15, 0.1, 0.05)
	tally.mesh = tally_mesh
	tally.material_override = _tally_material
	tally.position = Vector3(0, 1.8, 1.2)
	add_child(tally)

	# Yellow tape on the floor roughly where the shot's edges are. Cross it and you're on TV.
	var half_hfov := atan(tan(deg_to_rad(ON_AIR_FOV / 2.0)) * 16.0 / 9.0)
	var origin := Vector2(ON_AIR_CAMERA_POS.x, ON_AIR_CAMERA_POS.z)
	var depth := 8.5
	for side in [-1.0, 1.0]:
		var end := origin + Vector2(side * tan(half_hfov) * depth, -depth)
		_tape(origin, end, Color(1, 0.85, 0.1))


func _build_backstage() -> void:
	_box(Vector3(3, 0.9, 1), Vector3(-6, 0.45, 6), Color(0.45, 0.32, 0.2))  # prop table
	_sign("PROPS", Vector3(-6, 1.6, 6))
	_box(Vector3(3, 0.9, 1), Vector3(6, 0.45, 6), Color(0.2, 0.2, 0.25))  # control desk
	_sign("CONTROL", Vector3(6, 1.6, 6))


## The on-air camera renders into a SubViewport; that texture is "the broadcast".
## It is shown on a big monitor backstage and a confidence monitor for the anchor.
## Later this is where the director's camera switcher and The Tape recording plug in.
func _build_broadcast() -> void:
	var viewport := SubViewport.new()
	viewport.size = BROADCAST_SIZE
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)

	on_air_camera = Camera3D.new()
	on_air_camera.fov = ON_AIR_FOV
	on_air_camera.transform = Transform3D(Basis(), ON_AIR_CAMERA_POS).looking_at(ON_AIR_CAMERA_TARGET)
	on_air_camera.current = true
	viewport.add_child(on_air_camera)

	var overlay := Control.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	viewport.add_child(overlay)

	var bar := ColorRect.new()
	bar.color = Color(0.08, 0.15, 0.4, 0.9)
	bar.anchor_top = 0.8
	bar.anchor_bottom = 0.92
	bar.anchor_right = 1.0
	overlay.add_child(bar)
	_lower_third = Label.new()
	_lower_third.text = "  CHANNEL 6 EVENING NEWS  |  Local man finds cat. More at eleven."
	_lower_third.add_theme_font_size_override("font_size", 22)
	_lower_third.set_anchors_preset(Control.PRESET_FULL_RECT)
	_lower_third.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	bar.add_child(_lower_third)

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

	set_show_state(ShowDirector.Phase.PREP, ShowDirector.Event.NONE)


func _build_props() -> void:
	# name, mesh size / radius+height, colour, mass, position
	var props := [
		["VT_CAT_TREE", Vector3(0.32, 0.07, 0.2), Color(0.9, 0.9, 0.9), 0.4, Vector3(-6.8, 1.0, 6)],
		["VT_CAT_TREE_FINAL_v2", Vector3(0.32, 0.07, 0.2), Color(0.85, 0.85, 0.7), 0.4, Vector3(-6.2, 1.0, 6)],
		["VT_WEATHER", Vector3(0.32, 0.07, 0.2), Color(0.5, 0.8, 1.0), 0.4, Vector3(-5.6, 1.0, 6)],
		["CUE_SHEET", Vector3(0.3, 0.02, 0.4), Color(1, 1, 0.85), 0.2, Vector3(-5.0, 1.0, 6.2)],
		["BOX_A", Vector3(0.6, 0.6, 0.6), Color(0.65, 0.48, 0.3), 3.0, Vector3(-8.5, 0.4, 3.5)],
		["BOX_B", Vector3(0.6, 0.6, 0.6), Color(0.65, 0.48, 0.3), 3.0, Vector3(-8.5, 1.1, 3.5)],
		["ANCHOR_CHAIR", Vector3(0.55, 0.9, 0.55), Color(0.15, 0.15, 0.2), 6.0, Vector3(0.8, 0.5, -5.6)],
		["COFFEE", Vector3(0.09, 0.14, 0.09), Color(0.95, 0.95, 0.95), 0.3, Vector3(0.6, 1.2, -4.2)],
		["TRAFFIC_CONE", Vector3(0.35, 0.55, 0.35), Color(1, 0.45, 0.1), 1.0, Vector3(6.5, 0.4, 3.5)],
		["PLANT", Vector3(0.4, 1.2, 0.4), Color(0.2, 0.6, 0.25), 2.0, Vector3(-3.5, 0.7, -6.8)],
	]
	for i in props.size():
		var p: Array = props[i]
		var size: Vector3 = p[1]
		var mesh := BoxMesh.new()
		mesh.size = size
		var shape := BoxShape3D.new()
		shape.size = size
		var prop := PropScript.new()
		prop.setup(p[0], mesh, shape, p[2], p[3])
		prop.position = p[4]
		add_child(prop)
		var tag := Label3D.new()
		tag.text = p[0]
		tag.font_size = 32
		tag.pixel_size = 0.003
		tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		tag.position.y = size.y / 2.0 + 0.12
		prop.add_child(tag)


# --- helpers ----------------------------------------------------------------


func _box(size: Vector3, pos: Vector3, color: Color, solid := true) -> Node3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var visual := MeshInstance3D.new()
	visual.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	visual.material_override = mat
	if not solid:
		visual.position = pos
		add_child(visual)
		return visual
	var body := StaticBody3D.new()
	body.position = pos
	var shape := BoxShape3D.new()
	shape.size = size
	var collision := CollisionShape3D.new()
	collision.shape = shape
	body.add_child(collision)
	body.add_child(visual)
	add_child(body)
	return body


## A strip of floor tape from a to b (x/z plane).
func _tape(a: Vector2, b: Vector2, color: Color) -> void:
	var d := b - a
	var strip := _box(
		Vector3(0.08, 0.01, d.length()), Vector3((a.x + b.x) / 2.0, 0.006, (a.y + b.y) / 2.0), color, false
	)
	strip.rotation.y = atan2(d.x, d.y)


func _tape_rect(zone: AABB, color: Color) -> void:
	var x0 := zone.position.x
	var x1 := zone.end.x
	var z0 := zone.position.z
	var z1 := zone.end.z
	_tape(Vector2(x0, z0), Vector2(x1, z0), color)
	_tape(Vector2(x0, z1), Vector2(x1, z1), color)
	_tape(Vector2(x0, z0), Vector2(x0, z1), color)
	_tape(Vector2(x1, z0), Vector2(x1, z1), color)


func _sign(text: String, pos: Vector3) -> void:
	var label := Label3D.new()
	label.text = text
	label.font_size = 64
	label.pixel_size = 0.005
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position = pos
	add_child(label)


## A screen showing `texture`, placed at `pos` and facing `viewer`.
func _monitor(texture: Texture2D, pos: Vector3, size: Vector2, viewer: Vector3) -> void:
	var quad := QuadMesh.new()
	quad.size = size
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_texture = texture
	var screen := MeshInstance3D.new()
	screen.mesh = quad
	screen.material_override = mat
	# QuadMesh faces +Z, so point -Z away from the viewer.
	screen.transform = Transform3D(Basis(), pos).looking_at(pos + (pos - viewer))
	add_child(screen)

	var frame := MeshInstance3D.new()
	var frame_mesh := BoxMesh.new()
	frame_mesh.size = Vector3(size.x + 0.1, size.y + 0.1, 0.05)
	frame.mesh = frame_mesh
	var frame_mat := StandardMaterial3D.new()
	frame_mat.albedo_color = Color(0.05, 0.05, 0.05)
	frame.material_override = frame_mat
	frame.transform = screen.transform.translated_local(Vector3(0, 0, -0.04))
	add_child(frame)
