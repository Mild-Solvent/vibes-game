extends RigidBody3D
## A physics prop anyone can grab and throw (R.E.P.O.-style hands).
## The host simulates it; clients see a frozen copy that follows the host's transform.

const HOLD_STIFFNESS := 14.0
const MAX_HOLD_SPEED := 14.0
const THROW_SPEED := 10.0

var holder_id := 0
var removed := false  # eaten / used up; parked out of sight until the round resets
var _home := Transform3D.IDENTITY
## Host: how the holder has turned the prop in their hands (yaw, pitch), see set_spin().
var hold_spin := Vector2.ZERO
var _last_speed := 0.0


func setup(prop_name: String, mesh: Mesh, shape: Shape3D, color: Color, body_mass: float) -> void:
	name = prop_name
	mass = body_mass
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	add_to_group("props")

	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mesh_instance.material_override = mat
	add_child(mesh_instance)

	var collision := CollisionShape3D.new()
	collision.shape = shape
	add_child(collision)

	var sync := MultiplayerSynchronizer.new()
	sync.name = "Sync"
	var config := SceneReplicationConfig.new()
	# Only send changes: most of the forest's props lie still most of the time.
	for property in [NodePath(".:position"), NodePath(".:rotation")]:
		config.add_property(property)
		config.property_set_replication_mode(property, SceneReplicationConfig.REPLICATION_MODE_ON_CHANGE)
	sync.replication_config = config
	add_child(sync)


func _ready() -> void:
	_home = transform
	if multiplayer.is_server():
		contact_monitor = true
		max_contacts_reported = 4
		body_entered.connect(func(_body): _on_impact(_last_speed))


## Host only: this prop hit something at `speed` m/s. Override to react (mushrooms break).
func _on_impact(_speed: float) -> void:
	pass


## Host only.
func reset_to_home() -> void:
	_drop()
	removed = false
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	transform = _home


## Host only: take the prop out of play (it stays in the tree so node paths keep matching).
func remove_from_play() -> void:
	_drop()
	removed = true
	linear_velocity = Vector3.ZERO
	position = Vector3(position.x, -100.0, position.z)


func _physics_process(_delta: float) -> void:
	var simulating := multiplayer.is_server() and not removed
	if freeze == simulating:
		freeze = not simulating
	if not simulating:
		return

	if position.y < -10.0:
		reset_to_home()
		return

	if holder_id == 0:
		_last_speed = linear_velocity.length()
		return
	_last_speed = 0.0
	var holder = _find_holder()
	if holder == null:
		_drop()
		return
	var to_hand: Vector3 = holder.hold_point() - global_position
	linear_velocity = (to_hand * HOLD_STIFFNESS).limit_length(MAX_HOLD_SPEED)
	# Turn towards the holder's view, plus however they've spun it (mouse wheel / R).
	var target: Basis = holder.global_basis * Basis.from_euler(Vector3(hold_spin.y, hold_spin.x, 0.0))
	var diff := (target * global_basis.inverse()).get_rotation_quaternion()
	var angle := diff.get_angle()
	if angle > PI:
		angle -= TAU
	angular_velocity = diff.get_axis() * angle * 10.0 if angle > 0.001 else Vector3.ZERO


@rpc("any_peer", "call_local", "reliable")
func request_grab() -> void:
	if not multiplayer.is_server() or removed:
		return
	var sender := _sender_id()
	if holder_id != 0 and holder_id != sender and _find_holder() != null:
		return  # someone else has it
	# One prop per pair of hands.
	for other in get_tree().get_nodes_in_group("props"):
		if other != self and other.holder_id == sender:
			other._drop()
	holder_id = sender
	hold_spin = Vector2.ZERO
	sleeping = false
	var holder = _find_holder()
	if holder:
		add_collision_exception_with(holder)


## Holder: turn the prop in your hands to have a look at it.
@rpc("any_peer", "call_local", "unreliable_ordered")
func set_spin(spin: Vector2) -> void:
	if multiplayer.is_server() and _sender_id() == holder_id:
		hold_spin = spin


@rpc("any_peer", "call_local", "reliable")
func request_release(throw: bool) -> void:
	if not multiplayer.is_server() or _sender_id() != holder_id:
		return
	var holder = _find_holder()
	_drop()
	if throw and holder:
		linear_velocity = holder.aim_direction() * THROW_SPEED


func _drop() -> void:
	var holder = _find_holder()
	if holder:
		remove_collision_exception_with(holder)
	holder_id = 0


func _find_holder() -> Node3D:
	if holder_id == 0:
		return null
	for player in get_tree().get_nodes_in_group("players"):
		if player.peer_id == holder_id:
			return player
	return null


func _sender_id() -> int:
	var id := multiplayer.get_remote_sender_id()
	return id if id != 0 else multiplayer.get_unique_id()
