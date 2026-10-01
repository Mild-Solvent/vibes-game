extends StaticBody3D
## A studio camera on a pedestal. Press E at it to operate it: your view becomes its viewfinder,
## the mouse pans / tilts it and the wheel zooms. One operator at a time (the host decides).
##
## The operator owns the aim and sends it to everyone; the host re-sends the whole state every
## half second so late joiners catch up. The broadcast reads `view_transform()` / `fov`.

const AIM_SENSITIVITY := 0.0018
const MIN_FOV := 18.0
const MAX_FOV := 75.0
const STATE_INTERVAL := 0.5
const AIM_SEND_INTERVAL := 0.05

var label := "CAM"
var operator_id := 0
var yaw := 0.0  # radians, around +Y, 0 = looking down -Z
var pitch := 0.0
var fov := 50.0
## Set by the studio each frame: this camera feeds the broadcast and the show is LIVE.
var on_air := false

var head: Node3D
var viewfinder: Camera3D
var _tally_mat: StandardMaterial3D
var _name_tag: Label3D
var _state_timer := 0.0
var _aim_timer := 0.0
var _aim_dirty := false
var _home := Vector3.ZERO  # yaw, pitch, fov at round start


## `aim_at` is a point in the parent level's local space.
func setup(cam_label: String, aim_at: Vector3, start_fov: float) -> void:
	label = cam_label
	name = cam_label.replace(" ", "")
	fov = start_fov
	_build()
	var local_target := aim_at - position - head.position
	yaw = atan2(-local_target.x, -local_target.z)
	pitch = atan2(local_target.y, Vector2(local_target.x, local_target.z).length())
	_home = Vector3(yaw, pitch, fov)
	_apply_aim()


func view_transform() -> Transform3D:
	return viewfinder.global_transform


# --- interaction (called by the local player) ---------------------------------------


func interact_prompt(_player: Node) -> String:
	if operator_id != 0 and operator_id != multiplayer.get_unique_id():
		return "%s is taken" % label
	return "E  operate %s" % label


func interact(_player: Node) -> void:
	request_operate.rpc_id(1)


## Seat callbacks: the local player sits here after the host granted it.
func seat_enter(player: Node) -> void:
	# Stand behind the camera, looking where it looks.
	var back := Vector3(sin(yaw), 0.0, cos(yaw)) * 0.9
	player.global_position = global_position + back + Vector3(0, 0.05, 0)
	player.rotation.y = yaw
	viewfinder.current = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## `notify` is false when the host already took the seat away.
func seat_exit(player: Node, notify: bool) -> void:
	player.camera.current = true
	if notify:
		request_leave.rpc_id(1)


func seat_help() -> String:
	return "Mouse aim · wheel zoom · Esc leave the camera"


func seat_status() -> String:
	return "%s  %s   zoom %d mm" % [label, "● ON AIR" if on_air else "standby", int(1200.0 / fov)]


func seat_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var zoom := fov / 50.0  # slower when zoomed in
		yaw -= event.relative.x * AIM_SENSITIVITY * zoom
		pitch = clampf(pitch - event.relative.y * AIM_SENSITIVITY * zoom, deg_to_rad(-60), deg_to_rad(50))
		_aim_dirty = true
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			fov = maxf(fov - 3.0, MIN_FOV)
			_aim_dirty = true
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			fov = minf(fov + 3.0, MAX_FOV)
			_aim_dirty = true
	_apply_aim()


# --- networking ------------------------------------------------------------------------


@rpc("any_peer", "call_local", "reliable")
func request_operate() -> void:
	if not multiplayer.is_server():
		return
	var sender := _sender_id()
	if operator_id != 0 and operator_id != sender and _player(operator_id) != null:
		return
	_set_operator.rpc(sender)  # sets operator_id everywhere, the host included


@rpc("any_peer", "call_local", "reliable")
func request_leave() -> void:
	if multiplayer.is_server() and _sender_id() == operator_id:
		_set_operator.rpc(0)


@rpc("authority", "call_local", "reliable")
func _set_operator(id: int) -> void:
	var was_me := operator_id == multiplayer.get_unique_id() and operator_id != 0
	operator_id = id
	_name_tag.text = label if id == 0 else "%s\n(%s)" % [label, _player_name(id)]
	var me := multiplayer.get_unique_id()
	if id == me and not was_me:
		var player = _player(me)
		if player:
			player.sit(self)
	elif was_me and id != me:
		var player = _player(me)
		if player and player.seat == self:
			player.stand_up(false)


@rpc("any_peer", "call_remote", "unreliable_ordered")
func _aim(new_yaw: float, new_pitch: float, new_fov: float) -> void:
	if multiplayer.get_remote_sender_id() != operator_id:
		return
	yaw = new_yaw
	pitch = new_pitch
	fov = new_fov
	_apply_aim()


@rpc("authority", "call_remote", "unreliable_ordered")
func _state(id: int, new_yaw: float, new_pitch: float, new_fov: float) -> void:
	if id != operator_id:
		_set_operator(id)
	if id != multiplayer.get_unique_id():
		yaw = new_yaw
		pitch = new_pitch
		fov = new_fov
		_apply_aim()


## Host only, when a new round starts.
func reset_aim() -> void:
	if operator_id != 0:
		return
	yaw = _home.x
	pitch = _home.y
	fov = _home.z
	_apply_aim()


func _process(delta: float) -> void:
	_tally_mat.emission_enabled = on_air
	_tally_mat.albedo_color = Color(1, 0.1, 0.1) if on_air else Color(0.2, 0.05, 0.05)
	if not Net.is_online():
		return
	if _aim_dirty and operator_id == multiplayer.get_unique_id():
		_aim_timer -= delta
		if _aim_timer <= 0.0:
			_aim_timer = AIM_SEND_INTERVAL
			_aim_dirty = false
			_aim.rpc(yaw, pitch, fov)
	if multiplayer.is_server():
		_state_timer -= delta
		if _state_timer <= 0.0:
			_state_timer = STATE_INTERVAL
			if operator_id != 0 and _player(operator_id) == null:
				_set_operator.rpc(0)
			_state.rpc(operator_id, yaw, pitch, fov)


func _apply_aim() -> void:
	head.rotation = Vector3(0.0, yaw, 0.0)
	head.get_child(0).rotation.x = pitch
	viewfinder.fov = fov


func _player(id: int) -> Node:
	for player in get_tree().get_nodes_in_group("players"):
		if player.peer_id == id:
			return player
	return null


func _player_name(id: int) -> String:
	var player = _player(id)
	return player.display_name if player else "?"


func _sender_id() -> int:
	var id := multiplayer.get_remote_sender_id()
	return id if id != 0 else multiplayer.get_unique_id()


# --- building --------------------------------------------------------------------------


func _build() -> void:
	var dark := _mat(Color(0.12, 0.12, 0.14))
	var metal := _mat(Color(0.45, 0.46, 0.5))
	# Collider: the pedestal column + head, so players can bump into it and aim E at it.
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.6, 1.8, 0.6)
	var collision := CollisionShape3D.new()
	collision.shape = shape
	collision.position.y = 0.9
	add_child(collision)

	# Pedestal: a wheeled base, a column and a steering ring.
	_add_mesh(_cylinder(0.45, 0.45, 0.12, 6), Vector3(0, 0.12, 0), dark)
	for i in 3:
		var a := TAU * i / 3.0
		_add_mesh(_sphere(0.07), Vector3(cos(a) * 0.4, 0.07, sin(a) * 0.4), dark)
	_add_mesh(_cylinder(0.07, 0.09, 1.1, 8), Vector3(0, 0.7, 0), metal)
	var ring := TorusMesh.new()
	ring.inner_radius = 0.22
	ring.outer_radius = 0.26
	_add_mesh(ring, Vector3(0, 1.05, 0), dark)

	head = Node3D.new()
	head.position.y = 1.45
	add_child(head)
	var tilt := Node3D.new()
	head.add_child(tilt)
	var body := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.3, 0.32, 0.55)
	body.mesh = box
	body.material_override = _mat(Color(0.18, 0.19, 0.22))
	tilt.add_child(body)
	var lens := MeshInstance3D.new()
	lens.mesh = _cylinder(0.11, 0.13, 0.3, 12)
	lens.rotation.x = PI / 2.0
	lens.position = Vector3(0, 0, -0.4)
	lens.material_override = dark
	tilt.add_child(lens)
	var glass := MeshInstance3D.new()
	glass.mesh = _cylinder(0.09, 0.09, 0.01, 12)
	glass.rotation.x = PI / 2.0
	glass.position = Vector3(0, 0, -0.56)
	glass.material_override = _mat(Color(0.15, 0.3, 0.5), 0.4)
	tilt.add_child(glass)
	var finder := MeshInstance3D.new()
	var finder_box := BoxMesh.new()
	finder_box.size = Vector3(0.22, 0.16, 0.12)
	finder.mesh = finder_box
	finder.position = Vector3(-0.2, 0.12, 0.2)
	finder.material_override = dark
	tilt.add_child(finder)
	var handle := MeshInstance3D.new()
	handle.mesh = _cylinder(0.025, 0.025, 0.5, 6)
	handle.rotation.z = PI / 2.0
	handle.position = Vector3(0, -0.05, 0.4)
	handle.material_override = metal
	tilt.add_child(handle)
	_tally_mat = _mat(Color(0.2, 0.05, 0.05))
	_tally_mat.emission = Color(1, 0.1, 0.1)
	_tally_mat.emission_energy_multiplier = 3.0
	var tally := MeshInstance3D.new()
	var tally_box := BoxMesh.new()
	tally_box.size = Vector3(0.12, 0.06, 0.04)
	tally.mesh = tally_box
	tally.position = Vector3(0, 0.2, -0.2)
	tally.material_override = _tally_mat
	tilt.add_child(tally)

	viewfinder = Camera3D.new()
	viewfinder.near = 0.1
	viewfinder.position = Vector3(0, 0, -0.6)
	tilt.add_child(viewfinder)

	_name_tag = Label3D.new()
	_name_tag.text = label
	_name_tag.font_size = 40
	_name_tag.pixel_size = 0.004
	_name_tag.outline_size = 10
	_name_tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_name_tag.position.y = 2.0
	add_child(_name_tag)


func _add_mesh(mesh: Mesh, pos: Vector3, mat: Material) -> void:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = pos
	instance.material_override = mat
	add_child(instance)


func _cylinder(top: float, bottom: float, height: float, sides: int) -> CylinderMesh:
	var mesh := CylinderMesh.new()
	mesh.top_radius = top
	mesh.bottom_radius = bottom
	mesh.height = height
	mesh.radial_segments = sides
	mesh.rings = 1
	return mesh


func _sphere(radius: float) -> SphereMesh:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 8
	mesh.rings = 4
	return mesh


func _mat(color: Color, emission := 0.0) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	if emission > 0.0:
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = emission
	return mat
