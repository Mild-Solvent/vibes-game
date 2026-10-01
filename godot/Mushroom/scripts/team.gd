extends Node
## Autoload "Team": the four jobless friends' shared state. The host owns it and mirrors every
## change to everyone with _sync(); clients ask for things through request_* RPCs.
##
## Per player: a status (fine / tripping / passed out / poisoned / dead) with time left, and an
## inventory (medkits, batteries). Shared: cash, which mushroom species are identified, the house.

signal changed
signal died(peer_id: int, reason: String)
signal revived(peer_id: int)
signal toast(text: String)
signal battery_installed

enum Status { OK, TRIPPING, PASSED_OUT, POISONED, DEAD }

const PRICES := {"medkit": 40, "battery": 8, "house": 300, "slot": 20, "old_slot": 5}
const POISON_SECONDS := 90.0
const TRIP_SECONDS := 30.0
const PASS_OUT_SECONDS := 18.0
const OVERDOSE_TRIPS := 3  # this many trips inside OVERDOSE_WINDOW and you pass out
const OVERDOSE_WINDOW := 90.0

var cash := 0
var day := 1
var known := {}  # mushroom kind -> true once somebody tasted one
var house := false
var car_seats := [0, 0, 0, 0]  # peer ids in the car, driver first
## peer id -> {"name", "status", "left", "medkit", "battery"}
var players := {}

var _recent_trips := {}  # host: peer id -> Array of msec timestamps


func _process(delta: float) -> void:
	var expired := []
	for peer in players:
		var p: Dictionary = players[peer]
		if p["left"] > 0.0:
			p["left"] = maxf(p["left"] - delta, 0.0)
			if p["left"] == 0.0:
				expired.append(peer)
	if not multiplayer.is_server():
		return
	for peer in expired:
		match players[peer]["status"]:
			Status.TRIPPING:
				set_status(peer, Status.OK)
			Status.PASSED_OUT:
				set_status(peer, Status.TRIPPING, TRIP_SECONDS)
			Status.POISONED:
				kill(peer, "the poison")


# --- reading (any peer) -----------------------------------------------------------


func status_of(peer_id: int) -> int:
	return players[peer_id]["status"] if players.has(peer_id) else Status.OK


func time_left(peer_id: int) -> float:
	return players[peer_id]["left"] if players.has(peer_id) else 0.0


func count(peer_id: int, item: String) -> int:
	return players[peer_id].get(item, 0) if players.has(peer_id) else 0


func is_alive(peer_id: int) -> bool:
	return status_of(peer_id) != Status.DEAD


# --- host API ---------------------------------------------------------------------


func reset() -> void:
	cash = 0
	day = 1
	known.clear()
	house = false
	car_seats = [0, 0, 0, 0]
	players.clear()
	_recent_trips.clear()


func add_player(peer_id: int, player_name: String) -> void:
	if not players.has(peer_id):
		players[peer_id] = {"name": player_name, "status": Status.OK, "left": 0.0, "medkit": 0, "battery": 1}
	_push()


func remove_player(peer_id: int) -> void:
	players.erase(peer_id)
	_push()


func set_status(peer_id: int, status: int, seconds := 0.0) -> void:
	if not players.has(peer_id):
		return
	players[peer_id]["status"] = status
	players[peer_id]["left"] = seconds
	_push()


## Host: a mushroom took effect on `peer_id`. Returns the toast for the taster.
func apply_mushroom(peer_id: int, effect: int, display_name: String) -> String:
	const Mushroom := preload("res://scripts/mushroom.gd")
	if not is_alive(peer_id):
		return ""
	match effect:
		Mushroom.Effect.FOOD:
			return "%s. Tasty, and you're fine. Villagers will buy these." % display_name
		Mushroom.Effect.TRIP, Mushroom.Effect.WITCH:
			if _count_trip(peer_id) >= OVERDOSE_TRIPS:
				set_status(peer_id, Status.PASSED_OUT, PASS_OUT_SECONDS)
				return "One %s too many. Lights out." % display_name
			if status_of(peer_id) != Status.POISONED:
				set_status(peer_id, Status.TRIPPING, TRIP_SECONDS)
			return "%s. Oh. Oh no. The trees are breathing." % display_name
		Mushroom.Effect.STRONG:
			set_status(peer_id, Status.PASSED_OUT, PASS_OUT_SECONDS)
			return "%s. You see the face of God, then the ground." % display_name
		Mushroom.Effect.POISON:
			set_status(peer_id, Status.POISONED, POISON_SECONDS)
			return "%s. Your stomach says no. Get a MEDKIT in %d s or you're dead." % [
				display_name, int(POISON_SECONDS)
			]
	return ""


func kill(peer_id: int, reason: String) -> void:
	if not players.has(peer_id) or not is_alive(peer_id):
		return
	set_status(peer_id, Status.DEAD)
	_died.rpc(peer_id, reason)


func revive(peer_id: int) -> void:
	if players.has(peer_id) and not is_alive(peer_id):
		set_status(peer_id, Status.OK)
		_revived.rpc(peer_id)


func add_cash(amount: int) -> void:
	cash += amount
	_push()


func give(peer_id: int, item: String, amount := 1) -> void:
	if players.has(peer_id):
		players[peer_id][item] = players[peer_id].get(item, 0) + amount
		_push()


func take(peer_id: int, item: String) -> bool:
	if count(peer_id, item) <= 0:
		return false
	players[peer_id][item] -= 1
	_push()
	return true


func identify(kind: String) -> void:
	if not known.has(kind):
		known[kind] = true
		_push()


func next_day() -> void:
	day += 1
	_push()


## Host: show a toast to one player (or everyone with peer_id 0).
func tell(peer_id: int, text: String) -> void:
	if peer_id == 0:
		_toast.rpc(text)
	elif peer_id == multiplayer.get_unique_id():
		toast.emit(text)
	else:
		_toast.rpc_id(peer_id, text)


## Host: send the whole state to everyone (it's small).
func push_all() -> void:
	_push()


# --- client requests ----------------------------------------------------------------


@rpc("any_peer", "call_local", "reliable")
func request_buy(item: String) -> void:
	if not multiplayer.is_server():
		return
	var peer := _sender()
	var price: int = PRICES.get(item, -1)
	if price < 0 or not is_alive(peer):
		return
	if cash < price:
		tell(peer, "Not enough cash. That's %d €, you have %d €." % [price, cash])
		return
	cash -= price
	give(peer, item)
	tell(peer, "Bought a %s for %d €." % [item, price])


## Use a medkit on `target` (0 = yourself). Cures poison and wakes people up.
@rpc("any_peer", "call_local", "reliable")
func request_medkit(target: int) -> void:
	if not multiplayer.is_server():
		return
	var peer := _sender()
	if not is_alive(peer):
		return
	if target == 0 or not players.has(target):
		target = peer
	var status := status_of(target)
	if status == Status.DEAD:
		tell(peer, "Too late for a medkit. Maybe the witch can help...")
		return
	if status == Status.OK or status == Status.TRIPPING:
		tell(peer, "%s doesn't need a medkit." % players[target]["name"])
		return
	if not take(peer, "medkit"):
		tell(peer, "You have no medkit. The village shop sells them.")
		return
	set_status(target, Status.OK)
	tell(peer, "Patched up %s." % players[target]["name"])
	if target != peer:
		tell(target, "%s saved your life with a medkit." % players[peer]["name"])


## The flashlight ran dry and wants a fresh battery.
@rpc("any_peer", "call_local", "reliable")
func request_battery() -> void:
	if not multiplayer.is_server():
		return
	var peer := _sender()
	if not take(peer, "battery"):
		return
	if peer == multiplayer.get_unique_id():
		_battery_ok()
	else:
		_battery_ok.rpc_id(peer)


## Whoever simulates a car or an animal reports who it killed.
@rpc("any_peer", "call_local", "reliable")
func request_kill(peer_id: int, reason: String) -> void:
	if multiplayer.is_server():
		kill(peer_id, reason)


## Clients report their own silly deaths (falling, drowning).
@rpc("any_peer", "call_local", "reliable")
func request_die(reason: String) -> void:
	if multiplayer.is_server():
		kill(_sender(), reason)


# --- mirroring ------------------------------------------------------------------------


@rpc("authority", "call_local", "reliable")
func _battery_ok() -> void:
	battery_installed.emit()


func _push() -> void:
	if not multiplayer.is_server():
		return
	if Net.is_online():
		_sync.rpc({"cash": cash, "day": day, "known": known, "house": house, "players": players, "car": car_seats})
	changed.emit()


@rpc("authority", "call_remote", "reliable")
func _sync(state: Dictionary) -> void:
	cash = state["cash"]
	day = state["day"]
	known = state["known"]
	house = state["house"]
	players = state["players"]
	car_seats = state["car"]
	changed.emit()


@rpc("authority", "call_local", "reliable")
func _died(peer_id: int, reason: String) -> void:
	died.emit(peer_id, reason)


@rpc("authority", "call_local", "reliable")
func _revived(peer_id: int) -> void:
	revived.emit(peer_id)


@rpc("authority", "call_local", "reliable")
func _toast(text: String) -> void:
	toast.emit(text)


func _count_trip(peer_id: int) -> int:
	var now := Time.get_ticks_msec()
	var trips: Array = _recent_trips.get(peer_id, [])
	trips = trips.filter(func(t): return now - t < OVERDOSE_WINDOW * 1000.0)
	trips.append(now)
	_recent_trips[peer_id] = trips
	return trips.size()


func _sender() -> int:
	var id := multiplayer.get_remote_sender_id()
	return id if id != 0 else multiplayer.get_unique_id()
