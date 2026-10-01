extends Node3D
## Base class for a playable level ("show"). Every level is built on every peer at startup,
## each at its own spot in the world, so node paths (props, synchronizers) always match.
## The host picks which one is active; the GameDirector drives it.
##
## Override the "show rules" section in a subclass. Positions inside a level are local.

enum Phase { PREP, LIVE, WRAP }

const PropScript := preload("res://scripts/prop.gd")
const ModelFit := preload("res://scripts/model_fit.gd")

var overview_camera: Camera3D

# --- show rules (override) -------------------------------------------------


func title() -> String:
	return "Level"


func score_name() -> String:
	return "SCORE"


func prep_duration() -> float:
	return 20.0


func live_duration() -> float:
	return 180.0


func wrap_duration() -> float:
	return 12.0


func start_score() -> float:
	return 50.0


## Local spawn spot for the n-th player.
func spawn_point(index: int) -> Vector3:
	return Vector3(-4.0 + (index % 5) * 2.0, 0.2, 5.0 + (index / 5) * 1.5)


func make_environment() -> Environment:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.05, 0.05, 0.07)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.55, 0.6)
	env.ambient_light_energy = 0.6
	return env


## Host only, every frame while LIVE. Update director.score / director.event / director.sub.
func server_tick(_delta: float, _director: Node) -> void:
	pass


## Every peer, whenever new show state arrives. Update lights, screens, markers.
func apply_state(_phase: int, _event: int, _sub: int, _time_left: float) -> void:
	pass


func phase_text(phase: int, clock: String, score: float, _sub: int) -> String:
	match phase:
		Phase.PREP:
			return "PREP  %s" % clock
		Phase.LIVE:
			return "LIVE  %s" % clock
	return "WRAP  -  final %s %d" % [score_name().to_lower(), int(score)]


func event_text(_event: int) -> String:
	return ""


## Extra help shown in the corner of the HUD for this level.
func guide_text() -> String:
	return ""


## Every peer: called when the host picks a level (and with false for the others).
func set_active(_active: bool) -> void:
	pass


## Host only, when a new round starts: put every prop back.
func server_reset() -> void:
	for prop in find_children("*", "RigidBody3D", true, false):
		if prop.has_method("reset_to_home"):
			prop.reset_to_home()


## Players' feet positions in this level's local space.
func local_player_positions() -> Array[Vector3]:
	var result: Array[Vector3] = []
	for player in get_tree().get_nodes_in_group("players"):
		result.append(to_local(player.global_position))
	return result


# --- building helpers --------------------------------------------------------


func _add_overview(pos: Vector3, target: Vector3) -> void:
	overview_camera = Camera3D.new()
	overview_camera.transform = Transform3D(Basis(), pos).looking_at(target)
	add_child(overview_camera)


func _box(size: Vector3, pos: Vector3, color: Color, solid := true) -> Node3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var visual := MeshInstance3D.new()
	visual.mesh = mesh
	visual.material_override = _mat(color)
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


## Swaps the grey box of a `_box` / `_prop` node for a model fitted to the same `size`.
## The collider is untouched, so gameplay doesn't change. Returns the node.
func _dress(node: Node3D, model_path: String, size: Vector3, yaw := 0.0, stretch := false) -> Node3D:
	for child in node.get_children():
		if child is MeshInstance3D:
			child.visible = false
	node.add_child(ModelFit.fit(model_path, size, yaw, stretch))
	return node


func _mat(color: Color, emission := 0.0) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	if emission > 0.0:
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = emission
	return mat


## A strip of floor tape from a to b (x/z plane) at height y.
func _tape(a: Vector2, b: Vector2, color: Color, y := 0.006, emission := 0.0) -> MeshInstance3D:
	var d := b - a
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.08, 0.01, d.length())
	var strip := MeshInstance3D.new()
	strip.mesh = mesh
	strip.material_override = _mat(color, emission)
	strip.position = Vector3((a.x + b.x) / 2.0, y, (a.y + b.y) / 2.0)
	strip.rotation.y = atan2(d.x, d.y)
	add_child(strip)
	return strip


func _tape_rect(zone: AABB, color: Color, y := 0.006) -> void:
	var x0 := zone.position.x
	var x1 := zone.end.x
	var z0 := zone.position.z
	var z1 := zone.end.z
	_tape(Vector2(x0, z0), Vector2(x1, z0), color, y)
	_tape(Vector2(x0, z1), Vector2(x1, z1), color, y)
	_tape(Vector2(x0, z0), Vector2(x0, z1), color, y)
	_tape(Vector2(x1, z0), Vector2(x1, z1), color, y)


## A floating label. Billboarded by default (name tags); pass `yaw` to make it a fixed,
## two-sided sign facing that way instead.
func _sign(text: String, pos: Vector3, size := 64, yaw := INF) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.font_size = size
	label.pixel_size = 0.005
	label.outline_size = 10
	if yaw == INF:
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	else:
		label.double_sided = true
		label.rotation.y = yaw
	label.position = pos
	add_child(label)
	return label


func _light(pos: Vector3, energy: float, light_range: float, color := Color(1.0, 0.95, 0.85)) -> OmniLight3D:
	var light := OmniLight3D.new()
	light.position = pos
	light.omni_range = light_range
	light.light_energy = energy
	light.light_color = color
	add_child(light)
	return light


## A camera that renders into its own texture ("the feed"). SubViewport cameras are outside
## this node's 3D transform, so the level origin is added by hand.
func _make_feed(cam_pos: Vector3, target: Vector3, fov: float, size := Vector2i(640, 360)) -> SubViewport:
	var viewport := SubViewport.new()
	viewport.size = size
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	var cam := Camera3D.new()
	cam.fov = fov
	cam.transform = Transform3D(Basis(), position + cam_pos).looking_at(position + target)
	cam.current = true
	viewport.add_child(cam)
	return viewport


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
	frame.material_override = _mat(Color(0.05, 0.05, 0.05))
	frame.transform = screen.transform.translated_local(Vector3(0, 0, -0.04))
	add_child(frame)


func _prop(prop_name: String, size: Vector3, color: Color, body_mass: float, pos: Vector3, tag := true) -> RigidBody3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var shape := BoxShape3D.new()
	shape.size = size
	var prop := PropScript.new()
	prop.setup(prop_name, mesh, shape, color, body_mass)
	prop.position = pos
	add_child(prop)
	if tag:
		var label := Label3D.new()
		label.text = prop_name
		label.font_size = 32
		label.pixel_size = 0.003
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.position.y = size.y / 2.0 + 0.12
		prop.add_child(label)
	return prop
