extends "res://scripts/prop.gd"
## The basket: carry it around (E), drop mushrooms into it, take it to the village to sell.
## Mushrooms that land in it are packed away (taken out of play) and counted; the host keeps
## the list and tells everyone how full it is.

const MushroomScript := preload("res://scripts/mushroom.gd")
const SIZE := Vector3(0.7, 0.4, 0.5)

var display_name := "Basket"
var contents: Array[String] = []  # mushroom kinds, host-authoritative, mirrored for the label
var _label: Label3D


func build(model_path: String) -> void:
	var mesh := BoxMesh.new()
	mesh.size = SIZE
	var shape := BoxShape3D.new()
	shape.size = SIZE
	setup("BASKET", mesh, shape, Color(0.6, 0.42, 0.22), 2.0)
	for child in get_children():
		if child is MeshInstance3D:
			child.visible = false
	var ModelFit := preload("res://scripts/model_fit.gd")
	add_child(ModelFit.fit(model_path, SIZE))

	var catcher := Area3D.new()
	var catch_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(SIZE.x, 0.6, SIZE.z)
	catch_shape.shape = box
	catch_shape.position.y = 0.3
	catcher.add_child(catch_shape)
	catcher.body_entered.connect(_on_body_entered)
	add_child(catcher)

	_label = Label3D.new()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.pixel_size = 0.003
	_label.font_size = 36
	_label.outline_size = 8
	_label.position.y = 0.55
	add_child(_label)
	_refresh()


func _on_body_entered(body: Node) -> void:
	if not multiplayer.is_server() or removed:
		return
	if not body is MushroomScript or body.removed or body.holder_id != 0:
		return
	contents.append(body.kind)
	body.remove_from_play()
	_mirror.rpc(contents)


## Host: sell what villagers will take. Returns [cash earned, count sold, count refused].
func sell(known: Dictionary) -> Array:
	var earned := 0
	var sold := 0
	var kept: Array[String] = []
	for k in contents:
		if known.has(k) and MushroomScript.sellable(k):
			earned += MushroomScript.price_of(k)
			sold += 1
		else:
			kept.append(k)
	var refused := kept.size()
	contents = kept
	_mirror.rpc(contents)
	return [earned, sold, refused]


## Host: take `amount` of `mushroom_kind` out (the witch's recipe). False if there aren't enough.
func take(mushroom_kind: String, amount: int) -> bool:
	if contents.count(mushroom_kind) < amount:
		return false
	for i in amount:
		contents.erase(mushroom_kind)
	_mirror.rpc(contents)
	return true


## Holder: tip everything out (F), so unsellable stuff doesn't clog it.
@rpc("any_peer", "call_local", "reliable")
func request_dump() -> void:
	if multiplayer.is_server() and _sender_id() == holder_id and not contents.is_empty():
		contents.clear()
		_mirror.rpc(contents)


@rpc("authority", "call_local", "reliable")
func _mirror(kinds: Array) -> void:
	contents.assign(kinds)
	_refresh()


func _refresh() -> void:
	if _label == null:
		return
	if contents.is_empty():
		_label.text = "BASKET (empty)"
		return
	var counts := {}
	for k in contents:
		counts[k] = counts.get(k, 0) + 1
	var lines := ["BASKET (%d)" % contents.size()]
	for k in counts:
		var tag := "" if Team.known.has(k) else " ?"
		lines.append("%d× %s%s" % [counts[k], MushroomScript.name_of(k), tag])
	_label.text = "\n".join(lines)


## Stays where you left it between days (it only comes back if it fell off the world).
func reset_to_home() -> void:
	if position.y < -10.0:
		super.reset_to_home()
