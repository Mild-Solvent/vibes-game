extends "res://scripts/prop.gd"
## The basket: carry it around (E), drop mushrooms into it, take it to the village to sell.
## Mushrooms that land in it are packed away (taken out of play) and counted; the host keeps
## the list and tells everyone how full it is.

const MushroomScript := preload("res://scripts/mushroom.gd")
const SIZE := Vector3(0.7, 0.4, 0.5)

var display_name := "Basket"
var for_sale := false  # a spare still on Jano's shelf
var contents: Array[String] = []  # mushroom kinds, host-authoritative, mirrored for the label
var _label: Label3D
var _catcher: Area3D
var _scan := 0.0


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
	_catcher = catcher
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


## Host: also check what's sitting in the basket now and then. A mushroom that was still in
## someone's hand when it entered never fires body_entered again once they let go.
func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if not multiplayer.is_server() or removed:
		return
	_scan += delta
	if _scan < 0.25:
		return
	_scan = 0.0
	for body in _catcher.get_overlapping_bodies():
		_on_body_entered(body)


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
	var binned := 0
	for k in contents:
		if known.has(k) and MushroomScript.sellable(k):
			earned += MushroomScript.price_of(k)
			sold += 1
		elif MushroomScript.KINDS[k][0] == MushroomScript.Effect.CURE:
			kept.append(k)  # the witch's stuff stays in the basket
		else:
			binned += 1
	var refused := binned
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
		lines.append("%d× %s" % [counts[k], MushroomScript.label_of(k)])
	_label.text = "\n".join(lines)


## Stays where you left it between days (it only comes back if it fell off the world).
## Spare baskets come out of hiding when they're bought (reset_to_home from the shop).
func reset_to_home() -> void:
	if not for_sale and position.y < -10.0:
		super.reset_to_home()


## Host: Jano sold this spare basket; it appears on his counter.
func bring_out() -> void:
	for_sale = false
	super.reset_to_home()


## Every peer, at build: a spare basket waits out of sight in Jano's shop until someone buys it.
func hide_until_bought() -> void:
	for_sale = true
	removed = true
	_set_out(true)
	position = Vector3(position.x, -100.0, position.z)


## Host: the police take everything.
func dump_all() -> void:
	contents.clear()
	_mirror.rpc(contents)
