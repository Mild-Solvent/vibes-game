extends PanelContainer
## The cheat panel (F1), for testing alone. Only opens while the host has cheats on (pause menu).
## Teleports and noclip are done by your own player; everything else asks the host.

const Terrain := preload("res://scripts/world/terrain.gd")
const MushroomScript := preload("res://scripts/mushroom.gd")
const PLACES := ["camp", "village", "casino", "witch", "ruin", "sanatorium", "mine", "crypt", "island"]

var _kinds: OptionButton


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_CENTER_LEFT, Control.PRESET_MODE_MINSIZE, 20)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.1, 0.07, 0.94)
	style.border_color = Color(0.85, 0.3, 0.2)
	style.set_border_width_all(3)
	style.set_corner_radius_all(10)
	style.set_content_margin_all(14)
	add_theme_stylebox_override("panel", style)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	add_child(box)
	var title := Label.new()
	title.text = "CHEATS (F1 closes)"
	title.add_theme_font_size_override("font_size", 22)
	title.modulate = Color(1, 0.5, 0.35)
	box.add_child(title)
	_row(box, [["Free + heal me", func(): _ask("free")], ["+500 €", func(): _ask("cash")],
		["God mode", func(): _ask("god")]])
	_row(box, [["Noclip", _toggle_noclip], ["Revive all", func(): _ask("revive_all")],
		["Identify all", func(): _ask("identify_all")]])
	_row(box, [["Morning", func(): _ask("morning")], ["Dusk", func(): _ask("dusk")],
		["Midnight", func(): _ask("midnight")], ["Monsters on/off", func(): _ask("monsters")]])
	var tp := Label.new()
	tp.text = "Teleport to:"
	box.add_child(tp)
	var places_a: Array = []
	var places_b: Array = []
	for i in PLACES.size():
		var place: String = PLACES[i]
		(places_a if i < 5 else places_b).append([place.capitalize(), func(): _teleport(place)])
	_row(box, places_a)
	_row(box, places_b)
	var spawn := HBoxContainer.new()
	box.add_child(spawn)
	_kinds = OptionButton.new()
	for k in MushroomScript.KINDS:
		_kinds.add_item(MushroomScript.name_of(k))
		_kinds.set_item_metadata(_kinds.item_count - 1, k)
	spawn.add_child(_kinds)
	var go := Button.new()
	go.text = "Fetch that mushroom"
	go.pressed.connect(func(): _ask("spawn:" + str(_kinds.get_item_metadata(_kinds.selected))))
	spawn.add_child(go)
	visible = false


func _row(parent: Node, buttons: Array) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	parent.add_child(row)
	for b in buttons:
		var button := Button.new()
		button.text = b[0]
		button.pressed.connect(b[1])
		row.add_child(button)


func toggle() -> void:
	if not Team.cheats:
		visible = false
		Team.toast.emit("Cheats are off. The host can switch them on in the pause menu.")
		return
	visible = not visible
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if visible else Input.MOUSE_MODE_CAPTURED


func _process(_delta: float) -> void:
	if visible and not Team.cheats:
		visible = false


func _ask(what: String) -> void:
	Team.request_cheat.rpc_id(1, what)


func _me() -> Node:
	for p in get_tree().get_nodes_in_group("players"):
		if p.is_multiplayer_authority():
			return p
	return null


func _toggle_noclip() -> void:
	var me := _me()
	if me:
		me.noclip = not me.noclip
		Team.toast.emit("Noclip %s. Space flies up." % ("ON" if me.noclip else "OFF"))


func _teleport(place: String) -> void:
	var me := _me()
	if me == null:
		return
	var at := Terrain.place_centre(place)
	if place == "island":
		var c: Vector2 = Terrain.ISLAND[0]
		at = Vector3(c.x, Terrain.height(c.x, c.y), c.y)
	var x := at.x + 6.0
	var z := at.z + 14.0
	me.global_position = Vector3(x, Terrain.height(x, z) + 1.0, z)
	me.velocity = Vector3.ZERO
