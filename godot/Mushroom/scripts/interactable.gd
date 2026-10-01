extends StaticBody3D
## Something you use with E: a shopkeeper, a slot machine, the witch's cauldron, the house plot.
## The player asks the host (request_use); the host runs `on_use(peer_id)`, set by the level.

var prompt := ""  # shown in the HUD when you look at it
var on_use: Callable  # host: func(peer_id: int)


func configure(node_name: String, size: Vector3, pos: Vector3, prompt_text: String, use: Callable) -> void:
	name = node_name
	prompt = prompt_text
	position = pos
	on_use = use
	var shape := BoxShape3D.new()
	shape.size = size
	var col := CollisionShape3D.new()
	col.shape = shape
	add_child(col)


@rpc("any_peer", "call_local", "reliable")
func request_use() -> void:
	if not multiplayer.is_server() or not on_use.is_valid():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender == 0:
		sender = multiplayer.get_unique_id()
	if Team.is_alive(sender):
		on_use.call(sender)
