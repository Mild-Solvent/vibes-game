extends AnimatableBody3D
## A rusty mine cart on a straight rail between two stops. Pull a lever (E) and it rolls to the
## other end; climb in first to ride it. The host moves it, everyone sees the synced position.
## It squeals the whole way, so everything that hunts by sound hears it coming.

const SPEED := 3.2
const SQUEAL_EVERY := 1.0

var stop_a := Vector3.ZERO  # parent space
var stop_b := Vector3.ZERO
var blocked: Callable  # host: func() -> bool, true while rubble lies on the rails
var _t := 0.0  # 0 at stop_a, 1 at stop_b
var _target := 0.0
var _squeal := 0.0


func build(a: Vector3, b: Vector3, rust: Material, dark: Material) -> void:
	name = "MineCart"
	stop_a = a
	stop_b = b
	position = a
	sync_to_physics = true
	var parts := [
		[Vector3(1.3, 0.1, 1.9), Vector3(0, 0.4, 0), rust, true],
		[Vector3(1.3, 0.6, 0.08), Vector3(0, 0.75, 0.93), rust, true],
		[Vector3(1.3, 0.6, 0.08), Vector3(0, 0.75, -0.93), rust, true],
		[Vector3(0.08, 0.6, 1.9), Vector3(0.63, 0.75, 0), rust, true],
		[Vector3(0.08, 0.6, 1.9), Vector3(-0.63, 0.75, 0), rust, true],
		[Vector3(1.0, 0.3, 1.5), Vector3(0, 0.2, 0), dark, false],
	]
	for x in [-0.45, 0.45]:
		for z in [-0.6, 0.6]:
			parts.append([Vector3(0.1, 0.32, 0.32), Vector3(x, 0.18, z), dark, false])
	for part in parts:
		var mesh := BoxMesh.new()
		mesh.size = part[0]
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = part[2]
		mi.position = part[1]
		add_child(mi)
		if part[3]:
			var shape := BoxShape3D.new()
			shape.size = part[0]
			var col := CollisionShape3D.new()
			col.shape = shape
			col.position = part[1]
			add_child(col)
	var sync := MultiplayerSynchronizer.new()
	sync.name = "Sync"
	var config := SceneReplicationConfig.new()
	config.add_property(NodePath(".:position"))
	sync.replication_config = config
	add_child(sync)


## Host: a lever was pulled. Returns a line for whoever pulled it.
func send() -> String:
	if _t != _target:
		return "The cart is already rolling."
	if blocked.is_valid() and blocked.call():
		return "Rubble on the rails. Dig it out first."
	_target = 1.0 - roundf(_t)
	_squeal = 0.0
	return "Clunk. The cart starts to roll."


## Host: park it outside for a new day.
func reset() -> void:
	_t = 0.0
	_target = 0.0
	position = stop_a


func _physics_process(delta: float) -> void:
	if not multiplayer.is_server() or _t == _target:
		return
	if blocked.is_valid() and blocked.call():
		_target = _t  # stuck against fresh rubble
		return
	var length := stop_a.distance_to(stop_b)
	_t = move_toward(_t, _target, SPEED * delta / maxf(length, 0.1))
	position = stop_a.lerp(stop_b, _t)
	_squeal -= delta
	if _squeal <= 0.0:
		_squeal = SQUEAL_EVERY
		Hearing.emit(global_position, 22.0, 0)
		Sfx.play_all("gurney", global_position)
	if _t == _target:
		Hearing.emit(global_position, 26.0, 0)
		Sfx.play_all("metal_hit", global_position)
