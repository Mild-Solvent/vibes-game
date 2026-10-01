extends RigidBody3D
## A physics prop anyone can grab and throw (R.E.P.O.-style hands).
## The host simulates it; clients see a frozen copy that follows the host's transform.

const HOLD_STIFFNESS := 14.0
const MAX_HOLD_SPEED := 14.0
const THROW_SPEED := 10.0

var holder_id := 0
var _home := Vector3.ZERO


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
	config.add_property(NodePath(".:position"))
	config.add_property(NodePath(".:rotation"))
	sync.replication_config = config
	add_child(sync)


func _ready() -> void:
	_home = position


func _physics_process(_delta: float) -> void:
	var simulating := multiplayer.is_server()
	if freeze == simulating:
		freeze = not simulating
	if not simulating:
		return

	if global_position.y < -10.0:
		_drop()
		linear_velocity = Vector3.ZERO
		position = _home
		return

	if holder_id == 0:
		return
	var holder = _find_holder()
	if holder == null:
		_drop()
		return
	var to_hand: Vector3 = holder.hold_point() - global_position
	linear_velocity = (to_hand * HOLD_STIFFNESS).limit_length(MAX_HOLD_SPEED)
	angular_velocity = angular_velocity.lerp(Vector3.ZERO, 0.2)


@rpc("any_peer", "call_local", "reliable")
func request_grab() -> void:
	if not multiplayer.is_server():
		return
	var sender := _sender_id()
	if holder_id != 0 and holder_id != sender and _find_holder() != null:
		return  # someone else has it
	# One prop per pair of hands.
	for other in get_tree().get_nodes_in_group("props"):
		if other != self and other.holder_id == sender:
			other._drop()
	holder_id = sender
	sleeping = false
	var holder = _find_holder()
	if holder:
		add_collision_exception_with(holder)


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
