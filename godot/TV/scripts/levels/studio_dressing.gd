extends RefCounted
## Set dressing for Channel 6's studio: the stuff that makes it look like TV, and the stupid
## physics props that make it a friendslop game. Visual pieces are static; anything with a
## NAME in capitals is a grabbable prop (host-simulated, like every prop).
##
## Areas (studio level space): the news set at z -8 .. -4; WEATHER corner x -11 .. -6 and the
## INTERVIEW corner x 6 .. 11 beside it; the coffee station by the west wall; a wall of TVs
## around the big monitor on the back wall; stupid props on and around the PROPS table.

const FakeChannel := preload("res://scripts/fake_channel.gd")
const ModelFit := preload("res://scripts/model_fit.gd")
const K := "res://assets/kenney/"
const FURNITURE := K + "furniture-kit/"
const FOOD := K + "food-kit/"

var level: Node3D


func build(target: Node3D) -> void:
	level = target
	_news_set()
	_rigging()
	_weather_corner()
	_interview_corner()
	_coffee_station()
	_tv_wall()
	_studio_props()
	_street_props()


# --- static set pieces ----------------------------------------------------------------


func _news_set() -> void:
	# Dark stage floor under the set, and a strip of blue LED along the backdrop.
	level._box(Vector3(10, 0.02, 4.6), Vector3(0, 0.01, -5.7), Color(0.1, 0.12, 0.2), false)
	var led := level._box(Vector3(8, 0.08, 0.06), Vector3(0, 0.5, -7.68), Color.WHITE, false) as MeshInstance3D
	led.material_override = level._mat(Color(0.2, 0.5, 1.0), 2.0)
	for x in [-4.6, 4.6]:
		_roll_up(Vector3(x, 0, -6.9), "CHANNEL 6\nNEWS", Color(0.1, 0.25, 0.65))
	_model(FURNITURE + "pottedPlant.glb", Vector3(-3.6, 0, -7.2), Vector3(0.6, 1.5, 0.6))
	_model(FURNITURE + "pottedPlant.glb", Vector3(3.6, 0, -7.2), Vector3(0.6, 1.5, 0.6))
	_model(FURNITURE + "plantSmall2.glb", Vector3(-1.2, 0.76, -4.0), Vector3(0.2, 0.3, 0.2))
	_model(FOOD + "mug.glb", Vector3(-0.8, 0.76, -4.0), Vector3(0.14, 0.12, 0.12), PI)
	_model(FURNITURE + "laptop.glb", Vector3(1.05, 0.76, -4.15), Vector3(0.45, 0.28, 0.4), PI)
	for x in [-5.6, 5.6]:
		_model(FURNITURE + "speaker.glb", Vector3(x, 0, -7.4), Vector3(0.4, 1.6, 0.4))


## A roll-up banner: a base, a pole-straight printed panel.
func _roll_up(pos: Vector3, text: String, color: Color) -> void:
	level._box(Vector3(0.9, 0.08, 0.3), pos + Vector3(0, 0.04, 0), Color(0.75, 0.75, 0.78), false)
	var panel := level._box(Vector3(0.85, 2.1, 0.02), pos + Vector3(0, 1.13, 0), color, false) as MeshInstance3D
	panel.material_override = level._mat(color, 0.25)
	level._box(Vector3(0.85, 0.3, 0.025), pos + Vector3(0, 0.45, 0), Color(0.9, 0.1, 0.1), false)
	var label := Label3D.new()
	label.text = text
	label.font_size = 72
	label.pixel_size = 0.004
	label.outline_size = 0
	label.position = pos + Vector3(0, 1.6, 0.02)
	level.add_child(label)
	var logo := Label3D.new()
	logo.text = "6"
	logo.font_size = 160
	logo.pixel_size = 0.004
	logo.modulate = Color(1, 0.85, 0.3)
	logo.position = pos + Vector3(0, 0.95, 0.02)
	level.add_child(logo)


## Lighting truss over the set: two bars with lamp cans, and two real spotlights on the anchor.
func _rigging() -> void:
	var metal := Color(0.3, 0.3, 0.33)
	for z in [-2.6, -6.2]:
		level._box(Vector3(10, 0.12, 0.12), Vector3(0, 3.7, z), metal, false)
		for x in [-4.0, -2.0, 0.0, 2.0, 4.0]:
			var can: Node3D = level._box(Vector3(0.25, 0.35, 0.25), Vector3(x, 3.45, z), Color(0.12, 0.12, 0.13), false)
			can.rotation.x = deg_to_rad(-25.0 if z > -4.0 else 25.0)
			var lens := level._box(Vector3(0.18, 0.02, 0.18), Vector3(x, 3.26, z), Color.WHITE, false) as MeshInstance3D
			lens.material_override = level._mat(Color(1, 0.95, 0.8), 3.0)
	for x in [-2.2, 2.2]:
		var spot := SpotLight3D.new()
		spot.position = Vector3(x, 3.5, -2.6)
		spot.light_energy = 2.5
		spot.spot_range = 7.0
		spot.spot_angle = 28.0
		spot.light_color = Color(1, 0.95, 0.85)
		level.add_child(spot)
		spot.look_at(level.to_global(Vector3(0, 1.2, -5.4)))
	# Floor lamps at the edges of the set.
	_model(FURNITURE + "lampSquareFloor.glb", Vector3(-5.2, 0, -4.4), Vector3(0.4, 1.9, 0.4))
	_model(FURNITURE + "lampRoundFloor.glb", Vector3(5.2, 0, -4.4), Vector3(0.45, 1.9, 0.45))


func _weather_corner() -> void:
	level._box(Vector3(4.0, 2.8, 0.1), Vector3(-8.8, 1.45, -7.9), Color(0.1, 0.75, 0.25), false)  # green screen
	level._box(Vector3(4.0, 0.02, 2.5), Vector3(-8.8, 0.012, -6.6), Color(0.1, 0.7, 0.25), false)
	level._sign("WEATHER", Vector3(-8.8, 3.3, -7.6), 56)
	var channel := _channel(FakeChannel.Kind.WEATHER)
	level._box(Vector3(0.1, 1.2, 0.1), Vector3(-6.4, 0.6, -4.6), Color(0.15, 0.15, 0.15))
	level._monitor(channel, Vector3(-6.4, 1.6, -4.6), Vector2(1.4, 0.79), Vector3(-9, 1.6, -6.6))


func _interview_corner() -> void:
	level._sign("INTERVIEW", Vector3(8.6, 3.3, -7.6), 48)
	level._box(Vector3(5.0, 3.0, 0.08), Vector3(8.6, 1.5, -7.92), Color(0.55, 0.2, 0.25), false)
	_model(FURNITURE + "rugRectangle.glb", Vector3(8.6, 0.01, -5.6), Vector3(3.2, 0.02, 2.2), 0.0, true)
	_solid_model(FURNITURE + "loungeDesignSofa.glb", Vector3(8.6, 0, -7.1), Vector3(2.6, 0.95, 0.95))
	_solid_model(FURNITURE + "loungeDesignChair.glb", Vector3(10.6, 0, -5.4), Vector3(1.0, 0.95, 1.6), -PI / 2.0)
	_solid_model(FURNITURE + "tableCoffee.glb", Vector3(8.6, 0, -5.5), Vector3(1.3, 0.45, 0.8))
	_model(FOOD + "cup-coffee.glb", Vector3(8.3, 0.45, -5.5), Vector3(0.18, 0.12, 0.2))
	_model(FURNITURE + "books.glb", Vector3(8.9, 0.45, -5.4), Vector3(0.3, 0.2, 0.2))
	_model(FURNITURE + "lampRoundFloor.glb", Vector3(11.3, 0, -7.4), Vector3(0.45, 1.9, 0.45))
	_model(FURNITURE + "pottedPlant.glb", Vector3(6.4, 0, -7.4), Vector3(0.6, 1.4, 0.6))
	# Tonight's guest, waiting for a question nobody prepared.
	var guest := ModelFit.fit(K + "mini-characters/character-female-e.glb", Vector3(1.2, 1.7, 1.2))
	guest.position += Vector3(7.6, 0.85, -6.3)
	level.add_child(guest)
	var anims := guest.find_children("*", "AnimationPlayer", true, false)
	if not anims.is_empty() and anims[0].has_animation("idle"):
		anims[0].get_animation("idle").loop_mode = Animation.LOOP_LINEAR
		anims[0].play("idle")
	var tag: Label3D = level._sign("GUEST", Vector3(7.6, 2.0, -6.3), 32)
	tag.modulate = Color(1, 0.85, 0.5)


func _coffee_station() -> void:
	var counter := Vector3(0.8, 0.9, 2.0)
	var table: Node3D = level._box(counter, Vector3(-11.4, 0.45, 1.0), Color(0.4, 0.3, 0.22))
	level._dress(table, FURNITURE + "tableCross.glb", counter, PI / 2.0, true)
	_model(FURNITURE + "kitchenCoffeeMachine.glb", Vector3(-11.4, 0.9, 0.5), Vector3(0.45, 0.45, 0.45), PI / 2.0)
	_model(FOOD + "pizza-box.glb", Vector3(-11.4, 0.9, 1.5), Vector3(0.5, 0.06, 0.5))
	_model(FURNITURE + "coatRackStanding.glb", Vector3(-11.3, 0, -1.4), Vector3(0.6, 1.8, 0.6))
	_model(FURNITURE + "trashcan.glb", Vector3(-11.4, 0, 2.6), Vector3(0.4, 0.7, 0.4))
	level._sign("COFFEE", Vector3(-11.4, 2.0, 1.0), 40)


## The back wall: other channels on a wall of screens around the big programme monitor.
func _tv_wall() -> void:
	var kinds := [
		FakeChannel.Kind.COOKING, FakeChannel.Kind.SPORTS, FakeChannel.Kind.TELESHOP, FakeChannel.Kind.CARTOON,
	]
	var spots := [Vector2(-3.6, 3.2), Vector2(-3.6, 1.95), Vector2(3.6, 3.2), Vector2(3.6, 1.95)]
	for i in kinds.size():
		var pos := Vector3(spots[i].x, spots[i].y, 9.95)
		level._monitor(_channel(kinds[i]), pos, Vector2(1.8, 1.01), Vector3(pos.x, pos.y, 0))
	# A vintage TV on the coffee counter showing the cartoons too, and one by the props table.
	_model(FURNITURE + "televisionVintage.glb", Vector3(-6.0, 0.9, 6.3), Vector3(0.7, 0.5, 0.5), PI)
	_model(FURNITURE + "radio.glb", Vector3(-7.2, 0.9, 6.3), Vector3(0.4, 0.3, 0.15), PI)


# --- grabbable stupid props --------------------------------------------------------------


func _studio_props() -> void:
	# On and around the props table.
	_stupid("POTATO", "res://assets/kaylousberg/potato.glb", Vector3(0.16, 0.2, 0.16), 0.3, Vector3(-6.6, 1.2, 5.8))
	_stupid("ANOTHER_POTATO", "res://assets/kaylousberg/potato.glb", Vector3(0.14, 0.18, 0.14), 0.3, Vector3(-6.4, 1.2, 6.2))
	_brick("BRICK", Vector3(-5.4, 1.2, 5.8))
	_stupid("CAR_TIRE", K + "car-kit/wheel-default.glb", Vector3(0.45, 0.7, 0.7), 8.0, Vector3(-8.0, 0.4, 6.8))
	_stupid("SPARE_TIRE", K + "car-kit/debris-tire.glb", Vector3(0.4, 0.65, 0.65), 7.0, Vector3(-8.6, 0.4, 7.4))
	_stupid("SHOPPING_CART", K + "mini-market/shopping-cart.glb", Vector3(0.7, 0.95, 1.1), 10.0, Vector3(-9.5, 0.6, 8.2))
	_stupid("WATERMELON", FOOD + "watermelon.glb", Vector3(0.35, 0.36, 0.35), 4.0, Vector3(-7.0, 1.2, 6.0))
	_stupid("FISH", FOOD + "fish.glb", Vector3(0.18, 0.28, 0.55), 1.0, Vector3(-5.0, 1.2, 5.9))
	_stupid("BARREL", K + "survival-kit/barrel.glb", Vector3(0.55, 0.8, 0.55), 12.0, Vector3(-10.6, 0.5, 4.6))
	_stupid("PRESENT", K + "holiday-kit/present-a-cube.glb", Vector3(0.4, 0.5, 0.4), 1.5, Vector3(-9.6, 0.4, 4.6))
	_stupid("FRUIT_DISPLAY", K + "mini-market/display-fruit.glb", Vector3(0.7, 0.6, 0.7), 8.0, Vector3(-10.4, 0.4, 7.6))
	_stupid("BANANA", FOOD + "banana.glb", Vector3(0.08, 0.1, 0.3), 0.2, Vector3(-11.2, 1.2, 1.9))
	_stupid("DONUT", FOOD + "donut.glb", Vector3(0.18, 0.07, 0.2), 0.2, Vector3(-11.3, 1.2, 0.1))
	_stupid("BURGER", FOOD + "burger.glb", Vector3(0.18, 0.13, 0.18), 0.3, Vector3(6.8, 1.2, 6.1))
	_stupid("MUG", FOOD + "mug.glb", Vector3(0.14, 0.12, 0.12), 0.3, Vector3(5.2, 1.2, 6.1))
	_stupid("RETRO_TV", FURNITURE + "televisionVintage.glb", Vector3(0.6, 0.42, 0.42), 6.0, Vector3(-8.5, 1.5, 3.5))
	_stupid("STOOL_CHAIR", FURNITURE + "chairModernCushion.glb", Vector3(0.5, 0.95, 0.5), 4.0, Vector3(4.6, 0.6, 4.8))
	_stupid("FLOOR_PLANT", FURNITURE + "pottedPlant.glb", Vector3(0.45, 1.1, 0.45), 2.0, Vector3(11.3, 0.7, 9.3))


## A few things lying around in the city for the field crew to play with.
func _street_props() -> void:
	var cone := K + "car-kit/cone.glb"
	_stupid("STREET_CONE_1", cone, Vector3(0.35, 0.55, 0.35), 1.0, Vector3(24, 0.4, -2))
	_stupid("STREET_CONE_2", cone, Vector3(0.35, 0.55, 0.35), 1.0, Vector3(25, 0.4, -1.4))
	_stupid("ABANDONED_CART", K + "mini-market/shopping-cart.glb", Vector3(0.7, 0.95, 1.1), 10.0, Vector3(38, 0.6, -9))
	_stupid("STREET_TIRE", K + "car-kit/wheel-default.glb", Vector3(0.45, 0.7, 0.7), 8.0, Vector3(42, 0.5, -16))
	_stupid("STREET_BARREL", K + "survival-kit/barrel.glb", Vector3(0.55, 0.8, 0.55), 12.0, Vector3(40.5, 0.5, -11))
	_stupid("PLAZA_WATERMELON", FOOD + "watermelon.glb", Vector3(0.35, 0.36, 0.35), 4.0, Vector3(33, 0.4, 16))


func _stupid(prop_name: String, path: String, size: Vector3, mass: float, pos: Vector3) -> RigidBody3D:
	var prop: RigidBody3D = level._prop(prop_name, size, Color(0.6, 0.6, 0.6), mass, pos, false)
	level._dress(prop, path, size)
	return prop


## A brick is a box. The most honest prop in the building.
func _brick(prop_name: String, pos: Vector3) -> void:
	level._prop(prop_name, Vector3(0.22, 0.07, 0.11), Color(0.62, 0.25, 0.18), 2.5, pos, false)


# --- helpers -----------------------------------------------------------------------------


func _channel(kind: int) -> Texture2D:
	var channel := FakeChannel.new()
	level.add_child(channel)
	channel.start(kind)
	return channel.texture()


## A model fitted into `size`, standing on `floor` (no collider).
func _model(path: String, floor: Vector3, size: Vector3, yaw := 0.0, stretch := false) -> Node3D:
	var model := ModelFit.fit(path, size, yaw, stretch)
	model.position += floor + Vector3(0, size.y / 2.0, 0)
	level.add_child(model)
	return model


## Same, with a box collider of `size`.
func _solid_model(path: String, floor: Vector3, size: Vector3, yaw := 0.0) -> void:
	var box: Node3D = level._box(size, floor + Vector3(0, size.y / 2.0, 0), Color.GRAY)
	level._dress(box, path, size, yaw)
