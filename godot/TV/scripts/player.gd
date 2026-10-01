extends CharacterBody3D
## A crew member. Each peer drives its own player (client-authoritative movement);
## everyone else sees it through the MultiplayerSynchronizer.

const PropScript := preload("res://scripts/prop.gd")
const ModelFit := preload("res://scripts/model_fit.gd")
const CHARACTERS := [
	"male-a", "female-a", "male-b", "female-b", "male-c", "female-c", "male-d", "female-d",
]

const WALK_SPEED := 4.5
const SPRINT_SPEED := 7.5
const JUMP_VELOCITY := 4.8
const MOUSE_SENSITIVITY := 0.0025
const REACH := 3.0
const HOLD_DISTANCE := 1.6
const LOCAL_ONLY_LAYER := 2
const HELP := "E use / grab · Q throw · Esc mouse"  # render layer for our own body, hidden from our own camera

var peer_id := 1
var display_name := "Crew"
var color := Color.WHITE

var head: Node3D
var variant := 0
var _anim: AnimationPlayer
var _last_position := Vector3.ZERO
var camera: Camera3D
## What this (local) player sits at: a camera rig, the control desk... null when walking.
## A seat implements seat_enter(player), seat_exit(player, notify), seat_input(event),
## seat_help() and seat_status().
var seat: Node = null
var _held = null
var _spawn_position := Vector3.ZERO
var _visuals: Array[VisualInstance3D] = []
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")


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
	for visual in find_children("*", "VisualInstance3D", true, false):
		visual.layers = LOCAL_ONLY_LAYER
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func hold_point() -> Vector3:
	return head.global_position + aim_direction() * HOLD_DISTANCE


func aim_direction() -> Vector3:
	return -head.global_basis.z


func _physics_process(delta: float) -> void:
	if not is_multiplayer_authority():
		return
	if not is_on_floor():
		velocity.y -= _gravity * delta
	_update_prompt()
	if seat != null:
		velocity = Vector3(0.0, minf(velocity.y, 0.0), 0.0)
		move_and_slide()
		return

	var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	if captured and Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = JUMP_VELOCITY

	var input := Vector2.ZERO
	if captured:
		input = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction := (transform.basis * Vector3(input.x, 0.0, input.y)).normalized()
	var speed := SPRINT_SPEED if Input.is_action_pressed("sprint") else WALK_SPEED
	velocity.x = direction.x * speed
	velocity.z = direction.z * speed
	move_and_slide()

	if global_position.y < -20.0:
		position = _spawn_position
		velocity = Vector3.ZERO


func _unhandled_input(event: InputEvent) -> void:
	if not is_multiplayer_authority():
		return
	if seat != null:
		if event.is_action_pressed("ui_cancel"):
			stand_up()
		else:
			seat.seat_input(event)
		get_viewport().set_input_as_handled()
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
		rotate_y(-event.relative.x * MOUSE_SENSITIVITY)
		head.rotate_x(-event.relative.y * MOUSE_SENSITIVITY)
		head.rotation.x = clampf(head.rotation.x, deg_to_rad(-85), deg_to_rad(85))
	elif event.is_action_pressed("grab"):
		_use()
	elif event.is_action_pressed("throw"):
		if is_instance_valid(_held):
			_held.request_release.rpc_id(1, true)
		_held = null


## Local player only: sit at / operate `new_seat` (already granted).
func sit(new_seat: Node) -> void:
	if seat != null:
		stand_up()
	if is_instance_valid(_held):
		_held.request_release.rpc_id(1, false)
		_held = null
	seat = new_seat
	velocity = Vector3.ZERO
	seat.seat_enter(self)
	_set_help(seat.seat_help())


## Local player only. `notify` = tell the seat (false when the host already took it away).
func stand_up(notify := true) -> void:
	if seat == null:
		return
	var old := seat
	seat = null
	old.seat_exit(self, notify)
	camera.current = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_set_help(HELP)


## E: use what we look at (desk, camera...) if it can be used, else grab / drop a prop.
func _use() -> void:
	if is_instance_valid(_held):
		_held.request_release.rpc_id(1, false)
		_held = null
		return
	var target := _look_target()
	if target == null:
		return
	if target.has_method("interact"):
		target.interact(self)
	elif target is PropScript:
		_held = target
		_held.request_grab.rpc_id(1)


func _look_target() -> Node:
	var from := camera.global_position
	var query := PhysicsRayQueryParameters3D.create(from, from + aim_direction() * REACH)
	query.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return null
	return hit.collider


## Tells the HUD what E would do right now.
func _update_prompt() -> void:
	var hud := get_tree().get_first_node_in_group("hud")
	if hud == null:
		return
	var text := ""
	if seat != null:
		text = seat.seat_status()
	elif is_instance_valid(_held):
		text = "E drop · Q throw"
	else:
		var target := _look_target()
		if target != null and target.has_method("interact_prompt"):
			text = target.interact_prompt(self)
		elif target is PropScript:
			text = "E  grab %s" % target.name
	hud.set_prompt(text)


func _set_help(text: String) -> void:
	var hud := get_tree().get_first_node_in_group("hud")
	if hud:
		hud.set_help(text)


func _build() -> void:
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.35
	capsule.height = 1.7
	var collision := CollisionShape3D.new()
	collision.shape = capsule
	collision.position.y = 0.85
	add_child(collision)

	# Kenney mini character, turned to face -Z (Godot's forward), feet on the floor.
	var path := "res://assets/kenney/mini-characters/character-%s.glb" % CHARACTERS[variant % CHARACTERS.size()]
	var body := ModelFit.fit(path, Vector3(1.2, 1.7, 1.2), PI)
	body.position.y += 0.85
	add_child(body)
	var players := body.find_children("*", "AnimationPlayer", true, false)
	if not players.is_empty():
		_anim = players[0]
		for anim_name in ["idle", "walk", "sprint"]:
			if _anim.has_animation(anim_name):
				_anim.get_animation(anim_name).loop_mode = Animation.LOOP_LINEAR
		_anim.play("idle")

	head = Node3D.new()
	head.name = "Head"
	head.position.y = 1.55
	add_child(head)

	camera = Camera3D.new()
	camera.fov = 80
	camera.near = 0.05
	head.add_child(camera)

	var label := Label3D.new()
	label.text = display_name
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position.y = 2.1
	label.pixel_size = 0.004
	label.font_size = 48
	label.outline_size = 12
	add_child(label)
	_visuals.append(label)

	var sync := MultiplayerSynchronizer.new()
	sync.name = "Sync"
	var config := SceneReplicationConfig.new()
	config.add_property(NodePath(".:position"))
	config.add_property(NodePath(".:rotation"))
	config.add_property(NodePath("Head:rotation"))
	sync.replication_config = config
	add_child(sync)


## Every peer: pick idle / walk / sprint from how fast this player actually moved, so remote
## players (whose velocity isn't synced) animate too.
func _process(delta: float) -> void:
	if _anim == null or delta <= 0.0:
		return
	var moved := global_position - _last_position
	_last_position = global_position
	var speed := Vector2(moved.x, moved.z).length() / delta
	var wanted := "idle"
	if speed > (WALK_SPEED + SPRINT_SPEED) / 2.0:
		wanted = "sprint"
	elif speed > 0.5:
		wanted = "walk"
	if _anim.current_animation != wanted and _anim.has_animation(wanted):
		_anim.play(wanted, 0.15)


func _material(albedo: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = albedo
	return mat
