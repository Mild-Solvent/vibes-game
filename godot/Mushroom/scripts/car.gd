extends VehicleBody3D
## The friends' car. E to get in (first in drives) or out. The driver's machine simulates the
## car (multiplayer authority moves to the driver) and everyone else follows the synced
## transform. Hit someone fast and they die; hit a tree really fast and everyone inside does.

const ModelFit := preload("res://scripts/model_fit.gd")
const BODY_SIZE := Vector3(1.9, 1.7, 4.1)
## Seat spots in the car's local space; the first one drives. The car's front is +Z.
const SEATS := [Vector3(-0.42, 0.55, 0.3), Vector3(0.42, 0.55, 0.3), Vector3(-0.42, 0.55, -0.75),
	Vector3(0.42, 0.55, -0.75)]
const ENGINE_FORCE := 2400.0
const BRAKE_FORCE := 40.0
const MAX_STEER := 0.55
const RUN_OVER_SPEED := 7.0
const CRASH_SPEED := 17.0

var seats := [0, 0, 0, 0]  # peer ids; the host decides and mirrors them through Team.car_seats
var _home := Transform3D.IDENTITY
var _last_speed := 0.0
var autodrive := false  # testing: full throttle, straight ahead


func build(model_path: String) -> void:
	name = "Car"
	mass = 900.0
	add_to_group("car")
	var shape := BoxShape3D.new()
	shape.size = Vector3(BODY_SIZE.x, 1.0, BODY_SIZE.z)
	var col := CollisionShape3D.new()
	col.shape = shape
	col.position.y = 0.95
	add_child(col)
	var model := ModelFit.fit(model_path, BODY_SIZE)
	model.position.y += BODY_SIZE.y / 2.0
	add_child(model)
	for x in [-0.82, 0.82]:
		for z in [1.35, -1.35]:
			var wheel := VehicleWheel3D.new()
			wheel.position = Vector3(x, 0.45, z)
			wheel.wheel_radius = 0.36
			wheel.wheel_rest_length = 0.22
			wheel.suspension_travel = 0.25
			wheel.suspension_stiffness = 45.0
			wheel.damping_compression = 1.9
			wheel.damping_relaxation = 2.2
			wheel.wheel_friction_slip = 2.6
			wheel.use_as_steering = z > 0.0
			wheel.use_as_traction = true
			add_child(wheel)

	var sync := MultiplayerSynchronizer.new()
	sync.name = "Sync"
	var config := SceneReplicationConfig.new()
	config.add_property(NodePath(".:position"))
	config.add_property(NodePath(".:rotation"))
	sync.replication_config = config
	add_child(sync)

	contact_monitor = true
	max_contacts_reported = 4
	body_entered.connect(_on_body_entered)


func _ready() -> void:
	_home = transform
	Team.changed.connect(_on_team_changed)


## Every peer: seats arrive with the team state. The driver simulates; with nobody at the wheel
## the host does.
func _on_team_changed() -> void:
	if Team.car_seats == seats:
		return
	seats = Team.car_seats.duplicate()
	set_multiplayer_authority(seats[0] if seats[0] != 0 else 1, true)


func seat_of(peer_id: int) -> int:
	return seats.find(peer_id)


func seat_position(index: int) -> Vector3:
	return to_global(SEATS[index])


func _physics_process(_delta: float) -> void:
	var mine := is_multiplayer_authority()
	freeze = not mine
	if not mine:
		return
	var driving: bool = seats[0] != 0 and seats[0] == multiplayer.get_unique_id()
	if driving and (autodrive or Input.mouse_mode == Input.MOUSE_MODE_CAPTURED):
		var throttle := 1.0 if autodrive else Input.get_axis("move_back", "move_forward")
		var steer := Input.get_axis("move_right", "move_left")
		var forward_speed := linear_velocity.dot(global_basis.z)
		if throttle < 0.0 and forward_speed > 1.0:
			brake = BRAKE_FORCE
			engine_force = 0.0
		else:
			brake = 0.0
			engine_force = throttle * ENGINE_FORCE
		if Input.is_action_pressed("jump"):
			brake = BRAKE_FORCE * 2.0
		steering = move_toward(steering, steer * MAX_STEER, 0.05)
	else:
		engine_force = 0.0
		steering = move_toward(steering, 0.0, 0.05)
		brake = 8.0
	_last_speed = linear_velocity.length()
	if global_position.y < -30.0:
		_reset()


func _reset() -> void:
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	transform = _home


## Authority: hits are judged by whoever simulates the car, reported to the host.
func _on_body_entered(body: Node) -> void:
	if not is_multiplayer_authority():
		return
	if body.is_in_group("players"):
		if _last_speed > RUN_OVER_SPEED and seat_of(body.peer_id) < 0:
			Team.request_kill.rpc_id(1, body.peer_id, "being run over by %s" % _driver_name())
	elif body is StaticBody3D and _last_speed > CRASH_SPEED:
		for peer in seats:
			if peer != 0:
				Team.request_kill.rpc_id(1, peer, "a car crash (driver: %s)" % _driver_name())


func _driver_name() -> String:
	if seats[0] != 0 and Team.players.has(seats[0]):
		return Team.players[seats[0]]["name"]
	return "nobody"


## Get in: drive if the wheel is free, else ride along.
@rpc("any_peer", "call_local", "reliable")
func request_enter() -> void:
	if not multiplayer.is_server():
		return
	var peer := _sender()
	if seat_of(peer) >= 0 or not Team.is_alive(peer):
		return
	var new_seats: Array = Team.car_seats.duplicate()
	var seat := new_seats.find(0)
	if seat < 0:
		Team.tell(peer, "The car is full.")
		return
	new_seats[seat] = peer
	Team.car_seats = new_seats
	Team.push_all()


@rpc("any_peer", "call_local", "reliable")
func request_exit() -> void:
	if multiplayer.is_server():
		leave(_sender())


## Host: empty a seat (on exit, death or disconnect).
func leave(peer: int) -> void:
	var new_seats: Array = Team.car_seats.duplicate()
	var seat := new_seats.find(peer)
	if seat < 0:
		return
	new_seats[seat] = 0
	Team.car_seats = new_seats
	Team.push_all()


func _sender() -> int:
	var id := multiplayer.get_remote_sender_id()
	return id if id != 0 else multiplayer.get_unique_id()
