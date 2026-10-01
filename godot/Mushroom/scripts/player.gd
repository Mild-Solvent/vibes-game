extends CharacterBody3D
## One of the four jobless friends. Each peer drives its own player (client-authoritative
## movement); everyone else sees it through the MultiplayerSynchronizer.
##
## Statuses come from Team: tripping (visuals), passed out (can't move), poisoned (death timer),
## dead (you float around as a ghost until the witch brings you back). Falling too far and
## staying under water too long kill you; so do cars and boars (judged elsewhere).

const PropScript := preload("res://scripts/prop.gd")
const ModelFit := preload("res://scripts/model_fit.gd")
const Terrain := preload("res://scripts/world/terrain.gd")
const InteractableScript := preload("res://scripts/interactable.gd")
const CHARACTERS := [
	"male-a", "female-a", "male-b", "female-b", "male-c", "female-c", "male-d", "female-d",
]

const WALK_SPEED := 4.5
const SPRINT_SPEED := 7.5
const SWIM_SPEED := 2.2
const GHOST_SPEED := 9.0
const JUMP_VELOCITY := 4.8
const MOUSE_SENSITIVITY := 0.0025
const REACH := 3.2
const HOLD_DISTANCE := 1.6
const LOCAL_ONLY_LAYER := 2  # render layer for our own body, hidden from our own camera
const DEADLY_FALL_SPEED := 17.0  # landing faster than this (m/s) is fatal
const BREATH_SECONDS := 10.0
const BATTERY_SECONDS := 150.0  # one battery keeps the flashlight on this long

var peer_id := 1
var display_name := "Crew"
var color := Color.WHITE
var variant := 0
var head: Node3D
var camera: Camera3D
var flashlight_on := false  # synced, so everyone sees your torch
var battery := 1.0  # this player's own torch charge (0..1), local

var _anim: AnimationPlayer
var _model: Node3D
var _torch: SpotLight3D
var _name_label: Label3D
var _last_position := Vector3.ZERO
var _held = null
var _spawn_position := Vector3.ZERO
var _visuals: Array[VisualInstance3D] = []
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _fall_speed := 0.0
var _under_water := 0.0
var _spin := Vector2.ZERO


func setup(id: int, player_name: String, body_color: Color, character := 0) -> void:
	peer_id = id
	variant = character
	display_name = player_name
	color = body_color
	name = str(id)
	set_multiplayer_authority(id)
	add_to_group("players")
	_build()


func _ready() -> void:
	_spawn_position = position
	if not is_multiplayer_authority():
		return
	camera.current = true
	camera.cull_mask &= ~LOCAL_ONLY_LAYER
	for visual in _visuals:
		visual.layers = LOCAL_ONLY_LAYER
	for visual in _model.find_children("*", "VisualInstance3D", true, false):
		visual.layers = LOCAL_ONLY_LAYER
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	Team.battery_installed.connect(func(): battery = 1.0)


func hold_point() -> Vector3:
	return head.global_position + aim_direction() * HOLD_DISTANCE


func aim_direction() -> Vector3:
	return -head.global_basis.z


func status() -> int:
	return Team.status_of(peer_id)


func get_car() -> Node3D:
	return get_tree().get_first_node_in_group("car")


func in_car() -> bool:
	var car := get_car()
	return car != null and car.seat_of(peer_id) >= 0


func held() -> Node:
	return _held if is_instance_valid(_held) else null


# --- movement ------------------------------------------------------------------------


func _physics_process(delta: float) -> void:
	if not is_multiplayer_authority():
		return
	var s := status()
	var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	$Collision.disabled = s == Team.Status.DEAD or in_car()

	if in_car():
		var car := get_car()
		global_position = car.seat_position(car.seat_of(peer_id)) - Vector3(0, 0.6, 0)
		velocity = Vector3.ZERO
		_fall_speed = 0.0
		_update_torch(delta)
		return

	if s == Team.Status.DEAD:
		_ghost_move(delta, captured)
		return
	if s == Team.Status.PASSED_OUT:
		velocity.x = 0.0
		velocity.z = 0.0
		velocity.y -= _gravity * delta
		move_and_slide()
		return

	var water := Terrain.WATER_Y
	var swimming := global_position.y + 0.9 < water
	if swimming:
		velocity.y = move_toward(velocity.y, -0.6, _gravity * 0.4 * delta)
		if captured and Input.is_action_pressed("jump"):
			velocity.y = 2.5
	elif not is_on_floor():
		velocity.y -= _gravity * delta
	elif captured and Input.is_action_just_pressed("jump"):
		velocity.y = JUMP_VELOCITY

	var input := Vector2.ZERO
	if captured:
		input = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	if s == Team.Status.TRIPPING:
		input = input.rotated(sin(Time.get_ticks_msec() * 0.0013) * 0.6)  # the ground keeps moving
	var direction := (transform.basis * Vector3(input.x, 0.0, input.y)).normalized()
	var speed := SPRINT_SPEED if Input.is_action_pressed("sprint") else WALK_SPEED
	if swimming:
		speed = SWIM_SPEED
	velocity.x = direction.x * speed
	velocity.z = direction.z * speed

	var falling := -velocity.y
	move_and_slide()
	if is_on_floor() and _fall_speed > DEADLY_FALL_SPEED and not swimming:
		Team.request_die.rpc_id(1, "falling from a great height")
	_fall_speed = falling if not is_on_floor() else 0.0

	# Head under water too long.
	if head.global_position.y < water - 0.1:
		_under_water += delta
		if _under_water > BREATH_SECONDS:
			_under_water = 0.0
			Team.request_die.rpc_id(1, "drowning in the lake")
	else:
		_under_water = 0.0

	if global_position.y < -40.0:
		position = _spawn_position
		velocity = Vector3.ZERO
	_update_torch(delta)


func _ghost_move(delta: float, captured: bool) -> void:
	var input := Vector2.ZERO
	if captured:
		input = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var dir := (head.global_basis * Vector3(input.x, 0.0, input.y)).normalized()
	if captured and Input.is_action_pressed("jump"):
		dir.y += 1.0
	velocity = dir * GHOST_SPEED
	global_position += velocity * delta
	var ground := Terrain.height(global_position.x, global_position.z) + 0.5
	global_position.y = maxf(global_position.y, ground)
	_update_torch(delta)


func _update_torch(delta: float) -> void:
	if flashlight_on:
		battery -= delta / BATTERY_SECONDS
		if battery <= 0.0:
			battery = 0.0
			flashlight_on = false
			if Team.count(peer_id, "battery") > 0:
				Team.request_battery.rpc_id(1)
			else:
				Team.toast.emit("Flashlight's dead. Batteries at the village shop.")


# --- input ---------------------------------------------------------------------------


func _unhandled_input(event: InputEvent) -> void:
	if not is_multiplayer_authority():
		return
	if event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		return
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		if event is InputEventMouseButton and event.pressed:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			get_viewport().set_input_as_handled()
		return

	if event is InputEventMouseMotion:
		if status() == Team.Status.PASSED_OUT:
			return
		rotate_y(-event.relative.x * MOUSE_SENSITIVITY)
		head.rotate_x(-event.relative.y * MOUSE_SENSITIVITY)
		head.rotation.x = clampf(head.rotation.x, deg_to_rad(-85), deg_to_rad(85))
		return
	if event.is_action_pressed("flashlight"):
		if battery <= 0.0 and Team.count(peer_id, "battery") > 0:
			Team.request_battery.rpc_id(1)
		flashlight_on = not flashlight_on and battery > 0.0
		return
	if status() == Team.Status.DEAD or status() == Team.Status.PASSED_OUT:
		return

	if event.is_action_pressed("grab"):
		_use_or_grab()
	elif event.is_action_pressed("taste"):
		_taste_or_use()
	elif event.is_action_pressed("throw"):
		if held():
			_held.request_release.rpc_id(1, true)
		_held = null
	elif event.is_action_pressed("medkit"):
		var target = _aimed_at()
		var target_id: int = target.peer_id if target != null and target.is_in_group("players") else 0
		Team.request_medkit.rpc_id(1, target_id)
	elif event.is_action_pressed("spin") or event.is_action_pressed("spin_back"):
		if held():
			var step := 0.4 if event.is_action_pressed("spin") else -0.4
			_spin.x = wrapf(_spin.x + step, -PI, PI)
			if Input.is_key_pressed(KEY_CTRL):
				_spin.y = wrapf(_spin.y + step, -PI, PI)
			_held.set_spin.rpc_id(1, _spin)


## E: get out of the car, drop what you hold, or grab / use / get into what you look at.
func _use_or_grab() -> void:
	var car := get_car()
	if in_car():
		car.request_exit.rpc_id(1)
		return
	if held():
		_held.request_release.rpc_id(1, false)
		_held = null
		return
	var hit = _aimed_at()
	if hit == null:
		return
	if hit is PropScript:
		_held = hit
		_spin = Vector2.ZERO
		_held.request_grab.rpc_id(1)
	elif hit is InteractableScript:
		hit.request_use.rpc_id(1)
	elif hit.is_in_group("car"):
		hit.request_enter.rpc_id(1)


## F: taste the mushroom you hold, tip out the basket, or use the thing you look at.
func _taste_or_use() -> void:
	if held():
		if _held.has_method("request_taste"):
			_held.request_taste.rpc_id(1)
			_held = null
		elif _held.has_method("request_dump"):
			_held.request_dump.rpc_id(1)
		return
	var hit = _aimed_at()
	if hit != null and hit.has_method("request_use"):
		hit.request_use.rpc_id(1)


func _aimed_at() -> Node:
	var from := camera.global_position
	var query := PhysicsRayQueryParameters3D.create(from, from + aim_direction() * REACH)
	query.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return null
	var node: Node = hit.collider
	# The car's body is a child shape of the VehicleBody, so the collider is the car itself.
	return node


## What the crosshair is on, for the HUD hint.
func look_hint() -> String:
	if in_car():
		return "W/S drive · A/D steer · Space brake · E get out" if get_car().seat_of(peer_id) == 0 else "E get out"
	if held():
		var h := "Q throw · E drop · wheel/R turn it"
		if _held.has_method("request_taste"):
			h += " · F TASTE"
		elif _held.has_method("request_dump"):
			h += " · F tip it out"
		return "%s\n%s" % [_held.get("display_name") if _held.get("display_name") else _held.name, h]
	var hit = _aimed_at()
	if hit == null:
		return ""
	if hit is InteractableScript:
		return "E  " + hit.prompt
	if hit.is_in_group("car"):
		return "E  get in the car"
	if hit is PropScript:
		var label: String = hit.get("display_name") if hit.get("display_name") else String(hit.name)
		var extra := ""
		if hit.has_method("request_use"):
			extra = " · F " + hit.get("prompt")
		if hit.has_method("request_taste") and not Team.known.has(hit.kind):
			label = "Unknown mushroom"
		return "%s\nE pick up%s" % [label, extra]
	if hit.is_in_group("players"):
		return "%s\nH use a medkit on them" % hit.display_name
	return ""


# --- looks ---------------------------------------------------------------------------


func _build() -> void:
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.35
	capsule.height = 1.7
	var collision := CollisionShape3D.new()
	collision.name = "Collision"
	collision.shape = capsule
	collision.position.y = 0.85
	add_child(collision)

	# Kenney mini character, turned to face -Z (Godot's forward), feet on the floor.
	var path := "res://assets/kenney/mini-characters/character-%s.glb" % CHARACTERS[variant % CHARACTERS.size()]
	_model = ModelFit.fit(path, Vector3(1.2, 1.7, 1.2), PI)
	_model.position.y += 0.85
	add_child(_model)
	var players := _model.find_children("*", "AnimationPlayer", true, false)
	if not players.is_empty():
		_anim = players[0]
		for anim_name in ["idle", "walk", "sprint", "sit", "die"]:
			if _anim.has_animation(anim_name):
				_anim.get_animation(anim_name).loop_mode = (
					Animation.LOOP_NONE if anim_name == "die" else Animation.LOOP_LINEAR
				)
		_anim.play("idle")

	head = Node3D.new()
	head.name = "Head"
	head.position.y = 1.55
	add_child(head)

	camera = Camera3D.new()
	camera.fov = 80
	camera.near = 0.05
	head.add_child(camera)

	_torch = SpotLight3D.new()
	_torch.spot_range = 28.0
	_torch.spot_angle = 26.0
	_torch.light_energy = 3.0
	_torch.light_color = Color(1.0, 0.95, 0.8)
	_torch.position = Vector3(0.2, -0.15, -0.2)
	_torch.visible = false
	head.add_child(_torch)

	_name_label = Label3D.new()
	_name_label.text = display_name
	_name_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_name_label.position.y = 2.1
	_name_label.pixel_size = 0.004
	_name_label.font_size = 48
	_name_label.outline_size = 12
	add_child(_name_label)
	_visuals.append(_name_label)

	var sync := MultiplayerSynchronizer.new()
	sync.name = "Sync"
	var config := SceneReplicationConfig.new()
	config.add_property(NodePath(".:position"))
	config.add_property(NodePath(".:rotation"))
	config.add_property(NodePath("Head:rotation"))
	config.add_property(NodePath(".:flashlight_on"))
	sync.replication_config = config
	add_child(sync)


## Every peer: animation, torch, how the status looks.
func _process(delta: float) -> void:
	_torch.visible = flashlight_on
	var s := status()
	# Dead friends are ghosts (their body stays where they died, see the level); the passed-out
	# lie down.
	_model.visible = s != Team.Status.DEAD
	_name_label.text = display_name + (" (ghost)" if s == Team.Status.DEAD else "")
	_name_label.modulate = Color(0.7, 0.8, 1.0, 0.6) if s == Team.Status.DEAD else Color.WHITE
	_model.rotation.x = -PI / 2.0 if s == Team.Status.PASSED_OUT else 0.0
	if is_multiplayer_authority():
		camera.rotation.z = 1.3 if s == Team.Status.PASSED_OUT else 0.0
	if _anim == null or delta <= 0.0:
		return
	var moved := global_position - _last_position
	_last_position = global_position
	var speed := Vector2(moved.x, moved.z).length() / delta
	var wanted := "idle"
	if in_car():
		wanted = "sit"
	elif speed > (WALK_SPEED + SPRINT_SPEED) / 2.0:
		wanted = "sprint"
	elif speed > 0.5:
		wanted = "walk"
	if _anim.current_animation != wanted and _anim.has_animation(wanted):
		_anim.play(wanted, 0.15)
