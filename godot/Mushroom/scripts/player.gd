extends CharacterBody3D
## One of the four jobless friends. Each peer drives its own player (client-authoritative
## movement); everyone else sees it through the MultiplayerSynchronizer.
##
## Statuses come from Team: tripping (wobbly controls; friends look like monsters), passed out
## (on the floor; friends can drag you), poisoned (death timer), stuck (a friend pulls you out),
## dead (you float around as a ghost; your body stays behind). Falling too far and staying under
## water too long kill you; so do cars, wolves and the Hag (judged elsewhere).
## Too long in the dark without a light and you start hearing and seeing things.

const PropScript := preload("res://scripts/prop.gd")
const ModelFit := preload("res://scripts/model_fit.gd")
const Terrain := preload("res://scripts/world/terrain.gd")
const InteractableScript := preload("res://scripts/interactable.gd")
const FieldGuideScript := preload("res://scripts/field_guide.gd")
const CHARACTERS := [
	"male-a", "female-a", "male-b", "female-b", "male-c", "female-c", "male-d", "female-d",
]
const MONSTER := "res://assets/kenney/graveyard-kit/character-zombie.glb"

const WALK_SPEED := 4.5
const SPRINT_SPEED := 7.5
const SWIM_SPEED := 2.2
const GHOST_SPEED := 9.0
const JUMP_VELOCITY := 4.8
const REACH := 3.2
const HOLD_DISTANCE := 1.6
const LOCAL_ONLY_LAYER := 2  # render layer for our own body, hidden from our own camera
const EYE_HEIGHT := 1.28  # middle of the big chibi head (head spans ~0.87-1.70 on a 1.7 m character)
const EYE_FORWARD := -0.32  # just in front of the face
const LEAN_DOWN := 0.3  # extra forward when looking straight down (clears the chunky body)
const DEADLY_FALL_SPEED := 17.0
const DEADLY_FALL_HEIGHT := 9.0  # metres you have to actually drop for it to kill you  # landing faster than this (m/s) is fatal
const BREATH_SECONDS := 10.0
const BATTERY_SECONDS := 150.0  # one battery keeps the flashlight on this long
const DARK_SECONDS := 35.0  # this long in the dark without light and things start happening
const POCKET := ["flare", "wine", "duck", "lottery"]  # G uses the first one you have

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
var _monster: Node3D  # what tripping friends see instead of you
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
var _car_look := 0.0  # yaw offset from the car's heading while riding
var _knock := Vector3.ZERO  # shove momentum, decays
var _dark := 0.0  # seconds spent in the dark with no light
var _spook_in := 5.0
var _step := 0.0
var _pond_nag := 30.0
var noclip := false  # cheat: fly through everything
var _holding := false
var _holding_checked := 0
var _jump_was_down := false
var _fall_from := 0.0
var _alive_for := 0.0  # seconds since spawning: no fall damage in the first few (joining, loading)
var brambles := 0  # how many bramble thickets I'm in (set by the thickets)
var _beam: MeshInstance3D
# Inspecting a held mushroom up close (local only): a detailed copy in front of the camera.
var _inspecting := false
var _inspect_copy: Node3D
var _inspect_lamp: OmniLight3D
var _inspect_dist := 0.4
var _model_base := 0.0


const BEAM_SHADER := preload("res://shaders/torch_beam.gdshader")

## Where the owner says this body is (synced ~30 times a second); other peers glide towards it.
var net_pos := Vector3.INF
var net_rot := Vector3.ZERO


func setup(id: int, player_name: String, body_color: Color, character := 0) -> void:
	peer_id = id
	variant = character
	display_name = player_name
	color = body_color
	name = str(id)
	add_to_group("players")
	_build()
	# After _build: the authority has to reach the Sync node too (it only applies to existing
	# children). Otherwise the host owns every player's sync and pins joiners in place.
	set_multiplayer_authority(id)


func _ready() -> void:
	_spawn_position = position
	if not is_multiplayer_authority():
		return
	camera.current = true
	camera.cull_mask &= ~LOCAL_ONLY_LAYER
	_beam.layers = LOCAL_ONLY_LAYER  # your own torch beam: others see it, you never do
	for visual in _visuals:
		visual.layers = LOCAL_ONLY_LAYER
	# You see your own body when you look down; only your head is hidden from your own camera.
	for visual in _model.find_children("*", "VisualInstance3D", true, false):
		if String(visual.name).to_lower().begins_with("head"):
			visual.layers = LOCAL_ONLY_LAYER
	camera.position.z = EYE_FORWARD  # eyes at the front of the face, not inside the skull
	for visual in _monster.find_children("*", "VisualInstance3D", true, false):
		visual.layers = LOCAL_ONLY_LAYER
	if not _menu_open() and get_window().has_focus():
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
	return _held if is_instance_valid(_held) and not _held.removed and _held.holder_id == peer_id else null


## Every peer: is this player carrying something (for the arms-out pose)?
func _held_by_me() -> bool:
	var now := Time.get_ticks_msec()
	if now - _holding_checked > 300:
		_holding_checked = now
		_holding = false
		for prop in get_tree().get_nodes_in_group("props"):
			if prop.holder_id == peer_id and not prop.removed:
				_holding = true
				break
	return _holding


func holding_guide() -> bool:
	return held() is FieldGuideScript


func _sensitivity() -> float:
	return Settings.mouse_sensitivity if "mouse_sensitivity" in Settings else 0.0025


# --- movement ------------------------------------------------------------------------


func _physics_process(delta: float) -> void:
	if not is_multiplayer_authority():
		return
	var s := status()
	var captured: bool = Touch.captured()
	$Collision.disabled = s == Team.Status.DEAD or in_car()
	camera.fov = Settings.fov if "fov" in Settings else 80.0

	if in_car():
		var car := get_car()
		global_position = car.seat_position(car.seat_of(peer_id)) - Vector3(0, 0.6, 0)
		# Face where the car faces (its front is +Z, ours is -Z), plus however you've looked round.
		rotation.y = car.global_rotation.y + PI + _car_look
		# Chase camera behind and above the car. The head's pitch would swing that offset round
		# (look up and the camera ends up under the car), so undo the pitch on the offset and keep
		# the tilt small.
		head.rotation.x = clampf(head.rotation.x, deg_to_rad(-35), deg_to_rad(15))
		camera.position = Vector3(0, 1.4, 6.5).rotated(Vector3.RIGHT, -head.rotation.x)
		velocity = Vector3.ZERO
		_fall_speed = 0.0
		_update_torch(delta)
		return
	# Eyes in front of the face, level with it whatever the pitch (rotated with the head, looking
	# down sank the camera into your own chest). Looking down also leans forward a little, so you
	# see your feet rather than a wall of jacket.
	var down := maxf(0.0, -sin(head.rotation.x))
	camera.position = Vector3(0, 0, EYE_FORWARD - LEAN_DOWN * down).rotated(Vector3.RIGHT, -head.rotation.x)
	_car_look = 0.0

	if s == Team.Status.DEAD or noclip:
		$Collision.disabled = true
		_ghost_move(delta, captured)
		return
	if s == Team.Status.PASSED_OUT:
		_fall_speed = 0.0  # being dragged around never counts as a fall
		_alive_for = 0.0
		var dragger := _player(Team.dragged_by(peer_id))
		if dragger:
			# A friend has you by the collar.
			var to := dragger.global_position - dragger.global_basis.z * -1.2
			global_position = global_position.lerp(Vector3(to.x, global_position.y, to.z), 0.15)
		velocity.x = 0.0
		velocity.z = 0.0
		velocity.y -= _gravity * delta
		move_and_slide()
		return

	var jump_now := _jump_pressed()  # every frame, so the edge detection never goes stale
	var swimming := Terrain.in_water(global_position + Vector3(0, 0.9, 0))
	if swimming:
		velocity.y = move_toward(velocity.y, -0.6, _gravity * 0.4 * delta)
		if captured and Input.is_action_pressed("jump"):
			velocity.y = 2.5
	elif not is_on_floor():
		velocity.y -= _gravity * delta
	elif captured and jump_now and Team.stuck_in(peer_id) == "":
		velocity.y = JUMP_VELOCITY

	var input := Vector2.ZERO
	if captured:
		input = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	if Team.is_tripping(peer_id):
		input = input.rotated(sin(Time.get_ticks_msec() * 0.0013) * 0.6)  # the ground keeps moving
	if Team.stuck_in(peer_id) != "" or _inspecting:
		input = Vector2.ZERO
	var direction := (transform.basis * Vector3(input.x, 0.0, input.y)).normalized()
	var speed := SPRINT_SPEED if Input.is_action_pressed("sprint") else WALK_SPEED
	if swimming:
		speed = SWIM_SPEED
	if holding_heavy():
		speed *= 0.6
	if brambles > 0:
		speed = minf(speed, WALK_SPEED * 0.45)  # thorns: no running, barely walking
	velocity.x = direction.x * speed + _knock.x
	velocity.z = direction.z * speed + _knock.z
	if _knock.y > 0.0:
		velocity.y = maxf(velocity.y, _knock.y)
	_knock = _knock.move_toward(Vector3.ZERO, 14.0 * delta)
	_knock.y = 0.0 if is_on_floor() else _knock.y

	var falling := -velocity.y
	var was_on_floor := is_on_floor()
	if was_on_floor:
		_fall_from = global_position.y
	move_and_slide()
	_alive_for += delta
	# Deadly only if you really dropped a long way (velocity spikes from riding props don't count).
	var dropped := _fall_from - global_position.y
	if is_on_floor() and not was_on_floor:
		_fall_from = global_position.y
	if is_on_floor() and _fall_speed > DEADLY_FALL_SPEED and dropped > DEADLY_FALL_HEIGHT and not swimming \
			and _alive_for > 4.0:
		SessionLog.event("fall", "%s died falling %.1f m at %.1f m/s" % [display_name, dropped, _fall_speed])
		Team.request_die.rpc_id(1, "falling from a great height")
	elif is_on_floor() and not was_on_floor and _fall_speed > 6.0:
		Sfx.play_all("jump_land", global_position)
	_fall_speed = falling if not is_on_floor() else 0.0
	_footsteps(delta, Vector2(velocity.x, velocity.z).length())

	# Head under water too long.
	if Terrain.in_water(head.global_position + Vector3(0, 0.1, 0)):
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
	_update_dark(delta)
	_pond_thoughts(delta)
	_update_inspect(delta)
	_pull_friends(delta)


## The owner publishes its pose; everyone else eases towards the last one received, so a 30 Hz
## sync still moves smoothly on a 144 Hz screen. A big jump (respawn, being pulled out) snaps.
func _smooth_remote(delta: float) -> void:
	if is_multiplayer_authority():
		net_pos = position
		net_rot = rotation
		return
	if net_pos == Vector3.INF:
		return  # nothing received yet
	if position.distance_to(net_pos) > 4.0:
		position = net_pos
	else:
		position = position.lerp(net_pos, 1.0 - exp(-delta * 20.0))
	rotation.y = lerp_angle(rotation.y, net_rot.y, 1.0 - exp(-delta * 20.0))
	rotation.x = net_rot.x
	rotation.z = net_rot.z


## Space as a fresh press, whatever modifiers are held (Shift+Space while sprinting counts).
func _jump_pressed() -> bool:
	var down := Input.is_physical_key_pressed(KEY_SPACE) or Input.is_action_pressed("jump")
	var fresh := down and not _jump_was_down
	_jump_was_down = down
	return fresh


## A stuck friend in front of you, within pulling range (so you can stay on solid ground).
func _stuck_friend_ahead() -> Node:
	var hit = _aimed_at(Team.RESCUE_RANGE)
	if hit != null and hit.is_in_group("players") and hit != self and Team.stuck_in(hit.peer_id) != "":
		return hit
	return null


var _pull_tick := 0.0


## Hold E on a stuck friend: keep telling the host you're pulling.
func _pull_friends(delta: float) -> void:
	if not Touch.captured() or not Input.is_action_pressed("grab"):
		return
	var friend := _stuck_friend_ahead()
	if friend == null:
		return
	_pull_tick -= delta
	if _pull_tick <= 0.0:
		_pull_tick = 0.1
		Team.request_pull.rpc_id(1, friend.peer_id)


## After being lifted out of something: no fall damage from the teleport.
func reset_fall() -> void:
	_fall_speed = 0.0
	_fall_from = global_position.y
	_alive_for = 2.5


func holding_heavy() -> bool:
	var h := held()
	return h != null and h.mass > 20.0


func _footsteps(delta: float, speed: float) -> void:
	if not is_on_floor() or speed < 1.0:
		return
	_step += speed * delta
	if _step > (2.2 if speed > 6.0 else 1.6):
		_step = 0.0
		Sfx.play("footstep", global_position, -4.0)
		if speed > 6.0:
			Hearing.emit(global_position, 10.0, peer_id)  # sprinting through the woods isn't quiet


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


func _update_torch(delta: float) -> void:
	if flashlight_on:
		battery -= delta / BATTERY_SECONDS
		if battery <= 0.0:
			battery = 0.0
			flashlight_on = false
			if Team.count(peer_id, "battery") > 0:
				Team.request_battery.rpc_id(1)
			else:
				Team.toast.emit("Flashlight's dead. The team's out of batteries. Jano sells them.")


## Sanity: too long in the dark with no light and you hear whispers and see things. A torch (or
## a fire, or the village lamps) makes it stop at once.
func _update_dark(delta: float) -> void:
	var lit := flashlight_on or _near_light()
	var night := get_tree().get_first_node_in_group("hud") != null and _is_night()
	if lit or not night:
		_dark = 0.0
		return
	_dark += delta
	if _dark < DARK_SECONDS:
		return
	_spook_in -= delta
	if _spook_in > 0.0:
		return
	_spook_in = randf_range(6.0, 16.0)
	var around := global_position + Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized() * randf_range(6, 14)
	match randi() % 3:
		0:
			if Voice.has_method("play_whisper"):
				Voice.play_whisper(around + Vector3(0, 1.5, 0))
			else:
				Sfx.play("hag_whisper", around)
		1:
			Sfx.play("footstep", around, 2.0)
		2:
			get_tree().call_group("hud", "show_shadow_figure")


func _near_light() -> bool:
	if Vector2(global_position.x, global_position.z).length() < 14.0:
		return true  # the camp fire
	for p in get_tree().get_nodes_in_group("players"):
		if p != self and p.flashlight_on and p.global_position.distance_to(global_position) < 10.0:
			return true
	var village := Terrain.place_centre("village")
	return global_position.distance_to(village) < 40.0


func _is_night() -> bool:
	var hud = get_tree().get_first_node_in_group("hud")
	return hud.is_night() if hud and hud.has_method("is_night") else false


## The pond is RIGHT THERE. You could just... drink it.
func _pond_thoughts(delta: float) -> void:
	var lake: Vector2 = Terrain.LAKE[0]
	if Vector2(global_position.x, global_position.z).distance_to(lake) > Terrain.LAKE[1] * 1.3:
		return
	_pond_nag -= delta
	if _pond_nag <= 0.0:
		_pond_nag = randf_range(40.0, 90.0)
		Team.toast.emit(["Intrusive thought: drink the pond water.", "The pond looks refreshing. It is not.",
			"You could drink from the pond (F at the water). You shouldn't."][randi() % 3])


# --- input ---------------------------------------------------------------------------


func _unhandled_input(event: InputEvent) -> void:
	if not is_multiplayer_authority():
		return
	if event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		return
	if not Touch.captured():
		if event is InputEventMouseButton and event.pressed and not _menu_open():
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			get_viewport().set_input_as_handled()
		return

	if _inspecting:
		_inspect_input(event)
		return
	if event.is_action_pressed("inspect"):
		var h := held()
		if h and h.has_method("request_taste"):
			_start_inspect(h)
			return

	if event is InputEventMouseMotion:
		_look(event.relative * _sensitivity())
		return
	if event.is_action_pressed("flashlight"):
		_flashlight_or_feed()
		return
	if status() == Team.Status.DEAD or status() == Team.Status.PASSED_OUT:
		return

	if event.is_action_pressed("grab"):
		_use_or_grab()
	elif event.is_action_pressed("taste"):
		_taste_or_use()
	elif event.is_action_pressed("throw"):
		if held():
			SessionLog.event("throw", "%s threw %s" % [display_name, _held.name])
			_held.request_release.rpc_id(1, true)
			Sfx.play_all("throw", global_position)
			_held = null
		else:
			_shove()
	elif event.is_action_pressed("medkit"):
		var target = _aimed_at()
		var target_id: int = target.peer_id if target != null and target.is_in_group("players") else 0
		Team.request_medkit.rpc_id(1, target_id)
	elif event.is_action_pressed("use_item"):
		for item in POCKET:
			if Team.count(peer_id, item) > 0:
				Team.request_use_item.rpc_id(1, item)
				return
		Team.toast.emit("Your pockets are empty. Jano sells flares, wine, ducks and lottery tickets.")
	elif event.is_action_pressed("whistle"):
		if Team.count(peer_id, "whistle") > 0:
			Team.request_use_item.rpc_id(1, "whistle")
		else:
			Team.toast.emit("You don't have a whistle. You whistle with your mouth. It's pathetic.")
			Hearing.emit(global_position, 25.0, peer_id)
	elif event.is_action_pressed("spin") or event.is_action_pressed("spin_back"):
		if held():
			var step := 0.4 if event.is_action_pressed("spin") else -0.4
			_spin.x = wrapf(_spin.x + step, -PI, PI)
			if Input.is_key_pressed(KEY_CTRL):
				_spin.y = wrapf(_spin.y + step, -PI, PI)
			_held.set_spin.rpc_id(1, _spin)


## Turn the camera by `turn` radians (mouse, or the touch look drag).
func _look(turn: Vector2) -> void:
	if status() == Team.Status.PASSED_OUT:
		return
	var invert := -1.0 if ("invert_y" in Settings and Settings.invert_y) else 1.0
	if in_car():
		_car_look = wrapf(_car_look - turn.x, -PI, PI)
	else:
		rotate_y(-turn.x)
	head.rotate_x(-turn.y * invert)
	head.rotation.x = clampf(head.rotation.x, deg_to_rad(-85), deg_to_rad(85))


# --- inspecting ------------------------------------------------------------------------


func _start_inspect(mushroom: Node) -> void:
	const Mushroom := preload("res://scripts/mushroom.gd")
	_inspecting = true
	_inspect_dist = 0.4
	_inspect_copy = Mushroom.make_visual(mushroom.kind, true)
	_inspect_copy.position = Vector3(0, -0.02, -_inspect_dist)
	_inspect_copy.rotation = Vector3(0.3, 0.0, 0.0)
	camera.add_child(_inspect_copy)
	_inspect_lamp = OmniLight3D.new()
	_inspect_lamp.light_energy = 0.35
	_inspect_lamp.omni_range = 1.5
	_inspect_lamp.position = Vector3(0.15, 0.2, 0.05)
	camera.add_child(_inspect_lamp)
	mushroom.visible = false
	get_tree().call_group("hud", "set_inspecting", true)


func _stop_inspect() -> void:
	_inspecting = false
	if _inspect_copy:
		_inspect_copy.queue_free()
		_inspect_copy = null
	if _inspect_lamp:
		_inspect_lamp.queue_free()
		_inspect_lamp = null
	if is_instance_valid(_held):
		_held.visible = not _held.removed
	get_tree().call_group("hud", "set_inspecting", false)


## While inspecting: mouse turns it (yaw / pitch), wheel brings it closer or further,
## Q / E roll it (held, see _process), letting go of right mouse puts it away.
func _inspect_input(event: InputEvent) -> void:
	if event.is_action_released("inspect") or held() == null:
		_stop_inspect()
		return
	if event is InputEventMouseMotion:
		var sens := _sensitivity() * 1.6
		_inspect_copy.global_rotate(camera.global_basis.y.normalized(), event.relative.x * sens)
		_inspect_copy.global_rotate(camera.global_basis.x.normalized(), event.relative.y * sens)
	elif event.is_action_pressed("spin"):
		_inspect_dist = maxf(_inspect_dist - 0.04, 0.12)
	elif event.is_action_pressed("spin_back"):
		_inspect_dist = minf(_inspect_dist + 0.04, 0.9)


func _update_inspect(delta: float) -> void:
	if not _inspecting:
		return
	if held() == null or status() == Team.Status.DEAD or status() == Team.Status.PASSED_OUT:
		_stop_inspect()
		return
	var roll := 0.0
	if Input.is_physical_key_pressed(KEY_Q):
		roll += 1.0
	if Input.is_physical_key_pressed(KEY_E):
		roll -= 1.0
	if roll != 0.0:
		_inspect_copy.global_rotate(camera.global_basis.z.normalized(), roll * 2.2 * delta)
	_inspect_copy.position = _inspect_copy.position.lerp(Vector3(0, -0.02, -_inspect_dist), 0.25)
	const Mushroom := preload("res://scripts/mushroom.gd")
	Mushroom.apply_bruise(_inspect_copy, _held.kind, _held.bruise)


func _menu_open() -> bool:
	var hud = get_tree().get_first_node_in_group("hud")
	return hud != null and hud.has_method("menu_open") and hud.menu_open()


## T: in a force-feeding fight, mash it. Holding a mushroom and looking at a friend: start one.
## Otherwise: the flashlight.
func _flashlight_or_feed() -> void:
	var duel := _duel()
	if duel and duel.involves(peer_id):
		duel.press.rpc_id(1)
		return
	var h := held()
	var target = _aimed_at()
	if duel and h and h.has_method("request_taste") and target != null and target.is_in_group("players") \
			and target.global_position.distance_to(global_position) < 3.0 and status() != Team.Status.DEAD:
		duel.request_start.rpc_id(1, target.peer_id, h.get_path())
		return
	if battery <= 0.0 and Team.count(peer_id, "battery") > 0:
		Team.request_battery.rpc_id(1)
	flashlight_on = not flashlight_on and battery > 0.0
	Sfx.play("flashlight_click", global_position)


func _duel() -> Node:
	var level := get_tree().get_first_node_in_group("level")
	return level.get_node_or_null("Duel") if level else null


## Q with empty hands: shove whoever's in front of you. Near a cliff or the lake: hilarious.
func _shove() -> void:
	var target = _aimed_at()
	if target == null or not target.is_in_group("players") or status() == Team.Status.DEAD:
		return
	var dir: Vector3 = (target.global_position - global_position)
	dir.y = 0.0
	target.be_shoved.rpc_id(target.peer_id, dir.normalized() * 9.0 + Vector3(0, 4.0, 0))
	Sfx.play_all("drop", target.global_position)


## The shoved player's own machine applies the push (it owns its movement).
@rpc("any_peer", "call_local", "reliable")
func be_shoved(push: Vector3) -> void:
	if is_multiplayer_authority() and status() != Team.Status.DEAD:
		_knock = push


## E: get out of the car, drop what you hold, or grab / use / get into / help whatever you look at.
func _use_or_grab() -> void:
	var car := get_car()
	if in_car():
		car.request_exit.rpc_id(1)
		return
	var hit = _aimed_at()
	if _stuck_friend_ahead() != null:
		return  # holding E pulls them out (see _pull_friends)
	# Helping a friend works with your hands full: drag a passed-out friend along.
	if hit != null and hit.is_in_group("players") and hit != self:
		if hit.status() == Team.Status.PASSED_OUT:
			Team.request_drag.rpc_id(1, hit.peer_id)
			return
	if held():
		SessionLog.event("drop", "%s dropped %s" % [display_name, _held.name])
		_held.request_release.rpc_id(1, false)
		Sfx.play("drop", global_position)
		_held = null
		return
	if hit == null:
		return
	if hit is PropScript:
		_held = hit
		_spin = Vector2.ZERO
		_held.request_grab.rpc_id(1)
		SessionLog.event("pickup", "%s picked up %s" % [display_name, hit.name])
		Sfx.play("pickup", global_position)
	elif hit is InteractableScript:
		hit.request_use.rpc_id(1)
		Sfx.play("ui_click", global_position)
	elif hit.is_in_group("car"):
		if hit.is_flipped():
			hit.request_lift.rpc_id(1)
		else:
			hit.request_enter.rpc_id(1)
	elif hit.is_in_group("players"):
		if Team.stuck_in(hit.peer_id) != "":
			Team.request_free.rpc_id(1, hit.peer_id)
		elif hit.status() == Team.Status.PASSED_OUT:
			Team.request_drag.rpc_id(1, hit.peer_id)


## F: taste the mushroom you hold, tip out the basket, use the thing you look at, or drink the pond.
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
		return
	if _looking_at_water():
		_drink.rpc_id(1)
		Team.toast.emit("You drink the pond water. It tastes like frog. Nothing happens. Yet.")
		Sfx.play("splash", global_position)


func _looking_at_water() -> bool:
	if aim_direction().y > -0.3:
		return false
	var spot := head.global_position + aim_direction() * 2.5
	spot.y = Terrain.WATER_Y - 0.05
	return Terrain.in_water(spot) and head.global_position.y - Terrain.WATER_Y < 2.6


## Host: someone drank from the pond. It catches up with them.
@rpc("any_peer", "call_local", "reliable")
func _drink() -> void:
	if multiplayer.is_server():
		Team.queue_gag(peer_id, "pond_water", randf_range(30.0, 50.0))


func _aimed_at(reach := REACH) -> Node:
	var from := camera.global_position
	var query := PhysicsRayQueryParameters3D.create(from, from + aim_direction() * reach)
	var skip := [get_rid()]
	if held():
		skip.append(_held.get_rid())  # don't aim at the thing in your own hands
	query.exclude = skip
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return null
	return hit.collider


## What the crosshair is on, for the HUD hint.
func look_hint() -> String:
	var hint := _look_hint()
	if Touch.active:  # name the on-screen buttons instead of keys
		hint = hint.replace("· F ", "· EAT ")
		if hint.begins_with("F  "):
			hint = "EAT" + hint.substr(1)
		hint = hint.replace("SPAM T!", "SPAM LIGHT!").replace("T at a friend", "LIGHT at a friend")
		hint = hint.replace(" · wheel/R turn it", "").replace(" · hold RMB: INSPECT", "")
	return hint


func _look_hint() -> String:
	if in_car():
		if get_car().seat_of(peer_id) != 0:
			return "E get out"
		return ("joystick drive & steer · JUMP brake · E get out" if Touch.active
			else "W/S drive · A/D steer · Space brake · E get out")
	if Team.stuck_in(peer_id) != "":
		return "You're stuck in a %s! Shout for a friend to pull you out." % Team.stuck_in(peer_id)
	var duel := _duel()
	if duel and duel.involves(peer_id):
		return "SPAM T!"
	if held():
		var h := "Q throw · E drop · wheel/R turn it"
		var label := _label_of(_held)
		if _inspecting:
			return "%s\nmouse: turn · Q/E: roll · wheel: closer/further · let go of RMB" % label
		if _held.has_method("request_taste"):
			h += " · hold RMB: INSPECT · F TASTE · T at a friend: force-feed"
		elif _held.has_method("request_dump"):
			h += " · F tip it out"
		elif _held is FieldGuideScript:
			h += " · J read it"
		return "%s\n%s" % [label, h]
	var friend := _stuck_friend_ahead()
	if friend:
		return "HOLD E  pull %s out of the %s" % [friend.display_name, Team.stuck_in(friend.peer_id)]
	var hit = _aimed_at()
	if hit == null:
		return "F  drink the pond water (don't)" if _looking_at_water() else ""
	if hit is InteractableScript:
		return "E  " + hit.prompt
	if hit.is_in_group("car"):
		return "E  lift the car (needs two of you)" if hit.is_flipped() else "E  get in the car"
	if hit is PropScript:
		var extra := ""
		if hit.has_method("request_use"):
			extra = " · F " + hit.get("prompt")
		return "%s\nE pick up%s" % [_label_of(hit), extra]
	if hit.is_in_group("players"):
		if Team.stuck_in(hit.peer_id) != "":
			return "HOLD E  pull %s out" % hit.display_name
		if hit.status() == Team.Status.PASSED_OUT:
			return "E  drag %s along" % hit.display_name
		return "%s\nH medkit · Q shove" % hit.display_name
	return ""


func _label_of(prop: Node) -> String:
	if prop.has_method("request_taste"):
		const Mushroom := preload("res://scripts/mushroom.gd")
		return Mushroom.label_of(prop.kind)
	var n = prop.get("display_name")
	return n if n else String(prop.name)


func _player(id: int) -> Node3D:
	if id == 0:
		return null
	for p in get_tree().get_nodes_in_group("players"):
		if p.peer_id == id:
			return p
	return null


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
	# Sized by height (the box is wider than the chunky character), so everyone is 1.7 m tall
	# and eye heights match.
	_model = ModelFit.fit(path, Vector3(2.4, 1.7, 2.4), PI)
	_model.position.y += 0.85
	_model_base = _model.position.y
	add_child(_model)
	_monster = ModelFit.fit(MONSTER, Vector3(1.4, 2.1, 1.4), PI)
	_monster.position.y += 1.05
	_monster.visible = false
	add_child(_monster)
	var players := _model.find_children("*", "AnimationPlayer", true, false)
	if not players.is_empty():
		_anim = players[0]
		for anim_name in ["idle", "walk", "sprint", "sit", "die", "holding-both"]:
			if _anim.has_animation(anim_name):
				_anim.get_animation(anim_name).loop_mode = (
					Animation.LOOP_NONE if anim_name == "die" else Animation.LOOP_LINEAR
				)
		_anim.play("idle")

	head = Node3D.new()
	head.name = "Head"
	head.position.y = EYE_HEIGHT
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
	# A faint beam other players see cutting through the fog: a cone, narrow at the torch, that
	# fades out along its length and towards its silhouette so it reads as light, not a solid shape.
	# Never drawn for its owner (you'd be standing inside it).
	_beam = MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 3.2  # far end (the cone is tipped forward, top first)
	cone.bottom_radius = 0.06  # at the torch
	cone.height = 16.0
	cone.radial_segments = 16
	cone.rings = 1
	cone.cap_top = false
	cone.cap_bottom = false
	_beam.mesh = cone
	var beam_mat := ShaderMaterial.new()
	beam_mat.shader = BEAM_SHADER
	_beam.material_override = beam_mat
	_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_beam.rotation.x = -PI / 2.0
	_beam.position = Vector3(0, 0, -8.2)
	_beam.visible = false
	_torch.add_child(_beam)

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
	config.add_property(NodePath(".:net_pos"))
	config.add_property(NodePath(".:net_rot"))
	config.add_property(NodePath("Head:rotation"))
	config.add_property(NodePath(".:flashlight_on"))
	sync.replication_config = config
	add_child(sync)


## Every peer: animation, torch, how the status looks, and monster disguise for trippers.
func _process(delta: float) -> void:
	_smooth_remote(delta)
	if Touch.active and is_multiplayer_authority():
		var turn: Vector2 = Touch.take_look()
		if turn != Vector2.ZERO and not _inspecting and Touch.captured():
			_look(turn)
	_torch.visible = flashlight_on
	_beam.visible = flashlight_on and (Settings.quality if "quality" in Settings else 2) >= 1
	var s := status()
	var me := multiplayer.get_unique_id()
	var viewer_tripping := Team.is_tripping(me) and me != peer_id
	_model.visible = s != Team.Status.DEAD and not viewer_tripping
	_monster.visible = s != Team.Status.DEAD and viewer_tripping
	var talking: bool = Voice.has_method("is_talking") and Voice.is_talking(peer_id)
	_name_label.text = display_name + (" (ghost)" if s == Team.Status.DEAD else "") + (" ♪" if talking else "")
	_name_label.modulate = Color(0.7, 0.8, 1.0, 0.6) if s == Team.Status.DEAD else Color.WHITE
	_name_label.visible = not viewer_tripping
	_model.rotation.x = -PI / 2.0 if s == Team.Status.PASSED_OUT else 0.0
	# Down a hole: only your head sticks out.
	var sunk := -1.3 if Team.stuck_in(peer_id) == "hole" else 0.0
	_model.position.y = move_toward(_model.position.y, _model_base + sunk, 0.1)
	head.position.y = move_toward(head.position.y, EYE_HEIGHT + sunk, 0.1)
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
	if wanted == "idle" and _held_by_me():
		wanted = "holding-both"
	if _anim.current_animation != wanted and _anim.has_animation(wanted):
		_anim.play(wanted, 0.15)
