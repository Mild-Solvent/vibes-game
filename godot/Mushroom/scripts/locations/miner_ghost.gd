extends Node3D
## "The Miner": the ghost of a hewer who died in the Hodruša adit in 1908. He drifts through the
## rock towards whoever has a lamp lit and pinches it out ("Šetri baterku, synak."). He doesn't
## kill; he just leaves you in the dark. The host moves him; everyone sees the synced transform.

const ModelFit := preload("res://scripts/model_fit.gd")
const SPEED := 2.3
const REACH := 1.3
const REST := 14.0  # seconds he sulks after pinching a lamp
const LINES := [
	"A cold hand pinches out your lamp. \"Šetri baterku, synak.\"",
	"Someone blows your lamp out. \"Zdar Boh...\"",
	"Your lamp dies. Something laughs in the rock.",
	"\"Svetlo plaší kobolda,\" whispers the dark. Your lamp is out.",
]

var location: Node  # the mine: has _lamp_out() as an RPC
var bounds := AABB()  # parent space: he haunts this box
var _home := Vector3.ZERO
var _rest := 3.0
var _rng := RandomNumberGenerator.new()
var _wander := Vector3.ZERO
var _light: OmniLight3D


func build(model_path: String, home: Vector3, seed_value: int) -> void:
	name = "Miner"
	_home = home
	_wander = home
	position = home
	_rng.seed = seed_value
	var model := ModelFit.fit(model_path, Vector3(3.0, 1.8, 3.0), 0.0)
	model.position.y += 0.9
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.45, 0.75, 1.0, 0.35)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).material_override = mat
	add_child(model)
	for anim in model.find_children("*", "AnimationPlayer", true, false):
		if anim.has_animation("idle"):
			anim.get_animation("idle").loop_mode = Animation.LOOP_LINEAR
			anim.play("idle")
	# His helmet lamp, long dead, glowing faintly blue.
	var helmet := MeshInstance3D.new()
	var helmet_mesh := CylinderMesh.new()
	helmet_mesh.top_radius = 0.3
	helmet_mesh.bottom_radius = 0.42
	helmet_mesh.height = 0.22
	helmet.mesh = helmet_mesh
	helmet.material_override = mat
	helmet.position = Vector3(0, 1.85, 0)
	add_child(helmet)
	_light = OmniLight3D.new()
	_light.light_color = Color(0.4, 0.7, 1.0)
	_light.light_energy = 0.7
	_light.omni_range = 4.5
	_light.position = Vector3(0, 1.6, 0.3)
	add_child(_light)
	var sync := MultiplayerSynchronizer.new()
	sync.name = "Sync"
	var config := SceneReplicationConfig.new()
	config.add_property(NodePath(".:position"))
	config.add_property(NodePath(".:rotation"))
	sync.replication_config = config
	add_child(sync)


## Host: back to the bottom of the shaft for a new day.
func reset() -> void:
	position = _home
	_wander = _home
	_rest = 3.0


func _process(_delta: float) -> void:
	# Every peer: he flickers like a bad lamp.
	var t := Time.get_ticks_msec() / 1000.0
	_light.light_energy = 0.5 + 0.3 * sin(t * 9.0) * sin(t * 3.3)
	visible = fmod(t * 0.7, 6.0) > 0.25


func _physics_process(delta: float) -> void:
	if not multiplayer.is_server():
		return
	var parent := get_parent() as Node3D
	var goal := _wander
	var speed := SPEED * 0.4
	var prey: Node3D = null
	_rest -= delta
	if _rest <= 0.0:
		prey = _find_prey(parent)
	if prey:
		goal = parent.to_local(prey.global_position) + Vector3(0, 0.2, 0)
		speed = SPEED
		if global_position.distance_to(prey.global_position + Vector3(0, 0.2, 0)) < REACH:
			location._lamp_out.rpc_id(prey.peer_id)
			Team.tell(prey.peer_id, LINES[_rng.randi() % LINES.size()])
			Sfx.play_all("hag_whisper", global_position)
			_rest = REST
			_wander = _home
	elif position.distance_to(_wander) < 0.5:
		_wander = Vector3(_rng.randf_range(bounds.position.x, bounds.end.x), _home.y,
			_rng.randf_range(bounds.position.z, bounds.end.z))
	var to_goal := goal - position
	if to_goal.length() > 0.05:
		position += to_goal.limit_length(speed * delta)
		var flat := Vector2(to_goal.x, to_goal.z)
		if flat.length() > 0.05:
			rotation.y = lerp_angle(rotation.y, atan2(to_goal.x, to_goal.z), 0.1)


func _find_prey(parent: Node3D) -> Node3D:
	var best: Node3D = null
	var best_d := INF
	for p in get_tree().get_nodes_in_group("players"):
		if not p.flashlight_on or not Team.is_alive(p.peer_id) or p.in_car():
			continue
		if not bounds.has_point(parent.to_local(p.global_position)):
			continue
		var d := global_position.distance_to(p.global_position)
		if d < best_d:
			best = p
			best_d = d
	return best
