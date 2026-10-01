extends RefCounted
## Breaking news for "We're Live!". When the show goes LIVE the host picks a random story and
## its stupid prop(s) turn up somewhere in the city; at half time a second story breaks.
## Getting a story prop into the picture of the camera on air pays big ratings.
##
## Data-driven: add a story to STORIES (and any new prop to PROPS) and it is in the game.
## The story index travels in the director's `sub` (index + 1, 0 = no story yet).

const KENNEY := "res://assets/kenney/"

## Headline (lower third), ticker line, props that turn up (names from PROPS).
const STORIES := [
	["SHARK LOOSE DOWNTOWN", "Police: do not pet the shark · Shark: no comment", ["SHARK"]],
	["NATIONAL POTATO SHORTAGE: LAST POTATO SEEN IN TOWN", "Chips rationed · Mash cancelled", ["POTATO"]],
	["SHOPPING CART RAMPAGE ON MAIN STREET", "Supermarket denies everything", ["SHOPPING_CART"]],
	["MAYOR STUCK IN A CAR TIRE", "Mayor: 'this is fine' · Tire: re-election likely", ["MAYOR"]],
	["BRICK FALLS FROM CLEAR SKY", "Nobody hurt · Brick fine · Sky under investigation", ["BRICK"]],
	["TRAFFIC CONE RUNS FOR CITY COUNCIL", "Polls: cone leads by 12 points", ["CANDIDATE_CONE"]],
	["PENGUIN ESCAPES ZOO, SEEN BUYING ICE", "Zoo: 'he will be back for fish o'clock'", ["PENGUIN"]],
	["PIG ON THE LOOSE NEAR THE PLAZA", "Bacon jokes banned by court order", ["PIG"]],
	["LOCAL CAT FOUND. AGAIN.", "Cat has questions", ["CAT"]],
	["SNOWMAN APPEARS IN OCTOBER", "Meteorologists 'deeply confused'", ["SNOWMAN"]],
	["GIANT DONUT BLOCKS TRAFFIC", "Police surround donut · Then eat donut", ["DONUT"]],
	["MYSTERY TOILET IN THE STREET", "Residents: 'it was not there yesterday'", ["TOILET"]],
]

## Story prop: model, size of its box, mass, yaw of the model inside the box.
const PROPS := {
	"SHARK": ["quaternius/shark.glb", Vector3(0.8, 0.75, 2.4), 20.0, 0.0],
	"POTATO": ["kaylousberg/potato.glb", Vector3(0.5, 0.6, 0.5), 3.0, 0.0],
	"SHOPPING_CART": ["kenney/mini-market/shopping-cart.glb", Vector3(0.7, 0.95, 1.1), 12.0, 0.0],
	"MAYOR": ["kenney/mini-characters/character-male-e.glb", Vector3(1.1, 1.7, 1.1), 15.0, PI],
	"BRICK": ["", Vector3(0.45, 0.22, 0.22), 6.0, 0.0],
	"CANDIDATE_CONE": ["kenney/car-kit/cone.glb", Vector3(0.6, 0.8, 0.6), 2.0, 0.0],
	"PENGUIN": ["kenney/cube-pets/animal-penguin.glb", Vector3(0.9, 0.8, 0.6), 6.0, 0.0],
	"PIG": ["kenney/cube-pets/animal-pig.glb", Vector3(0.8, 1.0, 0.95), 15.0, 0.0],
	"CAT": ["kenney/cube-pets/animal-cat.glb", Vector3(0.5, 0.7, 0.75), 4.0, 0.0],
	"SNOWMAN": ["kenney/holiday-kit/snowman.glb", Vector3(1.0, 1.0, 0.65), 15.0, 0.0],
	"DONUT": ["kenney/food-kit/donut.glb", Vector3(1.4, 0.5, 1.4), 10.0, 0.0],
	"TOILET": ["kenney/furniture-kit/toilet.glb", Vector3(0.6, 0.85, 0.9), 20.0, PI],
}

const SEEN_RANGE := 30.0

var level: Node3D
var props := {}  # name -> prop
var spots: Array = []
var forced := -1  # testing: --story=N always breaks story N first


func build(target: Node3D, story_spots: Array) -> void:
	level = target
	spots = story_spots
	var parked := Vector3(0, -100, 0)
	for prop_name in PROPS:
		var entry: Array = PROPS[prop_name]
		var size: Vector3 = entry[1]
		var prop: RigidBody3D = level._prop("NEWS_" + prop_name, size, Color(0.6, 0.25, 0.2), entry[2], parked, false)
		if not str(entry[0]).is_empty():
			level._dress(prop, "res://assets/" + entry[0], size, entry[3])
		if prop_name == "MAYOR":
			_add_tire(prop)
		elif prop_name == "CANDIDATE_CONE":
			_add_rosette(prop)
		prop.removed = true  # out of play until its story breaks
		props[prop_name] = prop
		parked.x += 3.0


static func headline(story: int) -> String:
	return STORIES[story][0] if story >= 0 and story < STORIES.size() else ""


static func ticker(story: int) -> String:
	return STORIES[story][1] if story >= 0 and story < STORIES.size() else ""


## The story running for a director `sub` value (-1: none yet). sub = story + 1, plus 1000
## once the half-time story has broken.
static func story_of(sub: int) -> int:
	return sub % 1000 - 1


## Host only. Called every LIVE tick; breaks stories, returns the one now running.
func server_tick(director: Node) -> int:
	if director.sub == 0:
		director.sub = _pick(-1) + 1
	elif director.sub < 1000 and director.live_elapsed() >= director.time_left:  # half time
		director.sub = _pick(story_of(director.sub)) + 1 + 1000
	return story_of(director.sub)


## Host only: is any prop of `story` in the picture of `cam`?
func on_camera(story: int, cam: Camera3D, visible_to: Callable) -> bool:
	if story < 0:
		return false
	for prop_name in STORIES[story][2]:
		var prop: RigidBody3D = props[prop_name]
		if prop.removed or cam.global_position.distance_to(prop.global_position) > SEEN_RANGE:
			continue
		if visible_to.call(prop.global_position):
			return true
	return false


## Host only, new round: everything back out of play.
func server_reset() -> void:
	for prop in props.values():
		prop.remove_from_play()


## Host only: pick a story other than `previous`, and drop its props somewhere in the city.
func _pick(previous: int) -> int:
	var story := randi() % STORIES.size()
	if forced >= 0 and previous < 0:
		story = forced % STORIES.size()
	elif story == previous:
		story = (story + 1) % STORIES.size()
	var free_spots := spots.duplicate()
	free_spots.shuffle()
	for prop_name in STORIES[story][2]:
		var size: Vector3 = PROPS[prop_name][1]
		var spot: Vector3 = free_spots.pop_back()
		props[prop_name].bring_into_play(spot + Vector3(0, size.y / 2.0, 0))
	return story


## The mayor wears the car tire around his waist.
func _add_tire(prop: Node3D) -> void:
	var tire: Node3D = load(KENNEY + "car-kit/wheel-default.glb").instantiate()
	tire.rotation.z = PI / 2.0
	tire.scale = Vector3.ONE * 1.4
	tire.position.y = -0.45
	prop.add_child(tire)
	var sash := Label3D.new()
	sash.text = "MAYOR"
	sash.font_size = 36
	sash.pixel_size = 0.004
	sash.outline_size = 10
	sash.modulate = Color(1, 0.85, 0.3)
	sash.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sash.position.y = 1.05
	prop.add_child(sash)


## The candidate cone gets a VOTE CONE sign.
func _add_rosette(prop: Node3D) -> void:
	var sign := Label3D.new()
	sign.text = "VOTE\nCONE"
	sign.font_size = 40
	sign.pixel_size = 0.004
	sign.outline_size = 10
	sign.modulate = Color(0.3, 0.6, 1.0)
	sign.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sign.position.y = 0.75
	prop.add_child(sign)
