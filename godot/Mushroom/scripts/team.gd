extends Node
## Autoload "Team": the four jobless friends' shared state. The host owns it and mirrors every
## change to everyone with _sync(); clients ask for things through request_* RPCs.
##
## Per player: separate timers for poison, tripping and being passed out (so one never cures the
## other), dead or alive, and an inventory. Shared: cash, batteries, which mushroom species Babka
## Hela has named for you, the house, the car seats, Uncle Fero's debt, and the police.
##
## Mushrooms don't hit straight away: tasting one queues its effect, which kicks in after a while.

signal changed
signal died(peer_id: int, reason: String)
signal revived(peer_id: int)
signal toast(text: String)
signal battery_installed
signal game_over(stats: Dictionary)
signal flare_fired(pos: Vector3)

enum Status { OK, TRIPPING, PASSED_OUT, POISONED, DEAD }

const PRICES := {
	"medkit": 40, "battery": 8, "house": 300, "slot": 20, "old_slot": 5, "basket": 15, "compass": 25,
	"flare": 12, "whistle": 6, "walkie": 30, "wine": 4, "duck": 3, "lottery": 2, "rope": 10,
}
const ITEM_NAMES := {
	"medkit": "medkit", "battery": "battery", "basket": "basket", "compass": "compass", "flare": "flare",
	"whistle": "whistle", "walkie": "walkie-talkie", "wine": "bottle of cheap wine", "duck": "rubber duck",
	"lottery": "lottery ticket", "rope": "rope",
}
const POISON_SECONDS := 240.0  # once it kicks in: get a medkit or get to the witch
const TRIP_SECONDS := 40.0
const PASS_OUT_SECONDS := 25.0
const OVERDOSE_TRIPS := 3  # this many trips inside OVERDOSE_WINDOW and you pass out
const OVERDOSE_WINDOW := 120.0
const QUOTA_EVERY := 3  # Uncle Fero comes every 3 days
const QUOTAS := [150, 350, 600, 1000, 1500, 2200]
const POLICE_SECONDS := 120.0

var cash := 0
var day := 1
var batteries := 2  # shared by everyone
var known := {}  # mushroom kind -> true once Babka Hela named it
var house := false
var car_seats := [0, 0, 0, 0]  # peer ids in the car, driver first
var quota_index := 0
var police_left := -1.0  # counting down while a friend is missing (-1 = nobody missing)
var missing_peer := 0
var cheats := false  # the host can switch these on from the pause menu (for testing alone)
var earned := 0  # everything ever made this run (for the game over screen)
## A rescue in progress: {"target": peer, "by": peer, "progress": 0..1} or {} (synced).
var rescue := {}
var _rescue_last_pull := 0.0
const RESCUE_SECONDS := 1.6  # holding E this long pulls a friend out (their wiggling helps)
const RESCUE_RANGE := 4.6
var _deaths: Array[String] = []  # host: "Adam - the Hungry Hag", this run
## peer id -> {"name", "status", "left", "poison", "trip", "out", "dead", items...}
var players := {}

var _recent_trips := {}  # host: peer id -> Array of msec timestamps
var _pending: Array[Dictionary] = []  # host: {"peer", "effect", "at", "name"}


func _process(delta: float) -> void:
	var dirty := false
	for peer in players:
		var p: Dictionary = players[peer]
		for timer in ["poison", "trip", "out"]:
			if p[timer] > 0.0:
				p[timer] = maxf(p[timer] - delta, 0.0)
				if p[timer] == 0.0:
					dirty = true
		_derive(p)
	if police_left > 0.0:
		police_left = maxf(police_left - delta, 0.0)
	if not multiplayer.is_server():
		return
	if not rescue.is_empty() and Time.get_ticks_msec() / 1000.0 - _rescue_last_pull > 0.6:
		rescue = {}  # they let go
		dirty = true
	var now := Time.get_ticks_msec() / 1000.0
	var due := _pending.filter(func(e): return e["at"] <= now)
	if not due.is_empty():
		_pending = _pending.filter(func(e): return e["at"] > now)
		for e in due:
			_kick_in(e["peer"], e["effect"], e["name"])
	for peer in players:
		var p: Dictionary = players[peer]
		if p["dead"]:
			continue
		if p["poison"] == 0.0 and p.get("was_poisoned", false):
			p["was_poisoned"] = false
			kill(peer, "mushroom poisoning")
		elif p["out"] == 0.0 and p.get("was_out", false):
			p["was_out"] = false
			p["dragged_by"] = 0
			p["trip"] = maxf(p["trip"], 15.0)  # you wake up still seeing things
			dirty = true
	if dirty:
		_push()


# --- reading (any peer) -----------------------------------------------------------


func status_of(peer_id: int) -> int:
	return players[peer_id]["status"] if players.has(peer_id) else Status.OK


func time_left(peer_id: int) -> float:
	return players[peer_id]["left"] if players.has(peer_id) else 0.0


func poison_left(peer_id: int) -> float:
	return players[peer_id]["poison"] if players.has(peer_id) else 0.0


func is_tripping(peer_id: int) -> bool:
	return players.has(peer_id) and (players[peer_id]["trip"] > 0.0 or players[peer_id]["out"] > 0.0)


func count(peer_id: int, item: String) -> int:
	if item == "battery":
		return batteries
	return players[peer_id].get(item, 0) if players.has(peer_id) else 0


func is_alive(peer_id: int) -> bool:
	return status_of(peer_id) != Status.DEAD


func quota_amount() -> int:
	return QUOTAS[mini(quota_index, QUOTAS.size() - 1)]


## The day Uncle Fero comes for the money (he collects at the end of that day).
func quota_day() -> int:
	return (quota_index + 1) * QUOTA_EVERY


# --- host API ---------------------------------------------------------------------


func reset() -> void:
	cash = 0
	day = 1
	batteries = 2
	known.clear()
	house = false
	car_seats = [0, 0, 0, 0]
	quota_index = 0
	police_left = -1.0
	missing_peer = 0
	earned = 0
	_deaths.clear()
	for peer in players:
		players[peer] = _fresh(players[peer]["name"])
	_recent_trips.clear()
	_pending.clear()
	_push()


func add_player(peer_id: int, player_name: String) -> void:
	if not players.has(peer_id):
		players[peer_id] = _fresh(player_name)
	_push()


func remove_player(peer_id: int) -> void:
	players.erase(peer_id)
	_push()


## Old-style API: put one status on (OK clears everything but death).
func set_status(peer_id: int, status: int, seconds := 0.0) -> void:
	if not players.has(peer_id):
		return
	var p: Dictionary = players[peer_id]
	match status:
		Status.OK:
			p["poison"] = 0.0
			p["trip"] = 0.0
			p["out"] = 0.0
			p["was_poisoned"] = false
			p["was_out"] = false
			p["dead"] = false
		Status.TRIPPING:
			p["trip"] = maxf(p["trip"], seconds)
		Status.PASSED_OUT:
			p["out"] = maxf(p["out"], seconds)
			p["was_out"] = true
		Status.POISONED:
			p["poison"] = seconds
			p["was_poisoned"] = true
		Status.DEAD:
			p["dead"] = true
	_derive(p)
	_push()


## Host: somebody ate a mushroom. Nothing happens yet; the effect is queued and kicks in later.
## The taster only gets a vague first impression.
func apply_mushroom(peer_id: int, effect: int, display_name: String) -> String:
	const Mushroom := preload("res://scripts/mushroom.gd")
	if not is_alive(peer_id):
		return ""
	var delay := 0.0
	match effect:
		Mushroom.Effect.TRIP, Mushroom.Effect.WITCH:
			delay = randf_range(18.0, 35.0)
		Mushroom.Effect.STRONG:
			delay = randf_range(25.0, 40.0)
		Mushroom.Effect.POISON:
			delay = randf_range(35.0, 60.0)
	if delay > 0.0:
		_pending.append({"peer": peer_id, "effect": effect, "at": Time.get_ticks_msec() / 1000.0 + delay,
			"name": display_name})
	return ["Chewy. Tastes like... mushroom. You feel fine. For now.",
		"Earthy, a bit bitter. Probably fine?", "Crunchy. Your tongue tingles slightly.",
		"Tastes like the forest floor. Delicious."][randi() % 4]


## Host: something nasty you drank or ate catches up with you later.
func queue_gag(peer_id: int, gag: String, delay: float) -> void:
	_pending.append({"peer": peer_id, "effect": -1, "at": Time.get_ticks_msec() / 1000.0 + delay, "name": gag})


func kill(peer_id: int, reason: String) -> void:
	if not players.has(peer_id) or not is_alive(peer_id):
		return
	var p: Dictionary = players[peer_id]
	if cheats and p.get("god", false):
		tell(peer_id, "God mode saved you from %s." % reason)
		return
	_deaths.append("%s - %s" % [p["name"], reason])
	p["dead"] = true
	p["poison"] = 0.0
	p["trip"] = 0.0
	p["out"] = 0.0
	p["was_poisoned"] = false
	p["was_out"] = false
	_pending = _pending.filter(func(e): return e["peer"] != peer_id)
	_derive(p)
	_push()
	_died.rpc(peer_id, reason)
	var anyone_alive := false
	for other in players:
		if not players[other]["dead"]:
			anyone_alive = true
	if not anyone_alive:
		_end_run("Everybody's dead. The forest keeps the mushrooms.")


func revive(peer_id: int) -> void:
	if players.has(peer_id) and not is_alive(peer_id):
		set_status(peer_id, Status.OK)
		_revived.rpc(peer_id)


## Host: cure poison and wake someone up (medkit, the witch).
func cure(peer_id: int) -> void:
	if not players.has(peer_id):
		return
	var p: Dictionary = players[peer_id]
	p["poison"] = 0.0
	p["out"] = 0.0
	p["was_poisoned"] = false
	p["was_out"] = false
	_pending = _pending.filter(func(e): return e["peer"] != peer_id or e["effect"] < 0)
	_derive(p)
	_push()


func add_cash(amount: int) -> void:
	cash += amount
	if amount > 0:
		earned += amount
	_push()


func give(peer_id: int, item: String, amount := 1) -> void:
	if item == "battery":
		batteries += amount
	elif players.has(peer_id):
		players[peer_id][item] = players[peer_id].get(item, 0) + amount
	_push()


func take(peer_id: int, item: String) -> bool:
	if count(peer_id, item) <= 0:
		return false
	if item == "battery":
		batteries -= 1
	else:
		players[peer_id][item] -= 1
	_push()
	return true


func identify(kind: String) -> void:
	if not known.has(kind):
		known[kind] = true
		_push()


## Host: the end of a day. Uncle Fero collects every QUOTA_EVERY days; can't pay, run's over.
func next_day() -> void:
	if day % QUOTA_EVERY == 0:
		var amount := quota_amount()
		if cash >= amount:
			cash -= amount
			quota_index += 1
			tell(0, "Uncle Fero took his %d €. \"Same time in %d days, boys. It'll be %d.\"" % [
				amount, QUOTA_EVERY, quota_amount()])
		else:
			_end_run("Uncle Fero came for %d € and you had %d €. He took the car, the tents and a kidney." % [
				amount, cash])
			return
	day += 1
	_push()


## Host: caught in a bear trap / sunk in mud ("" frees). Only a friend can get you out.
func set_stuck(peer_id: int, what: String) -> void:
	if players.has(peer_id):
		players[peer_id]["stuck"] = what
		_push()


func stuck_in(peer_id: int) -> String:
	return players[peer_id].get("stuck", "") if players.has(peer_id) else ""


func dragged_by(peer_id: int) -> int:
	return players[peer_id].get("dragged_by", 0) if players.has(peer_id) else 0


func set_police(seconds_left: float, peer_id: int) -> void:
	police_left = seconds_left
	missing_peer = peer_id
	_push()


## Host: show a toast to one player (or everyone with peer_id 0).
func tell(peer_id: int, text: String) -> void:
	if text.is_empty():
		return
	if peer_id == 0:
		_toast.rpc(text)
	elif peer_id == multiplayer.get_unique_id():
		toast.emit(text)
	else:
		_toast.rpc_id(peer_id, text)


## Host: the run is over. Everyone gets the game over screen; the world starts again at day 1.
func _end_run(reason: String) -> void:
	var stats := {"reason": reason, "days": day, "earned": earned, "owed": quota_amount(), "deaths": _deaths.duplicate()}
	_game_over.rpc(stats)
	reset()


## Host: something worth seeing again in the end-of-day reel. Every peer snaps its own screen.
func highlight(text: String) -> void:
	_highlight.rpc(text)


@rpc("authority", "call_local", "reliable")
func _highlight(text: String) -> void:
	get_tree().call_group("hud", "remember_highlight", text)


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
	tell(peer, "Bought a %s for %d €." % [ITEM_NAMES.get(item, item), price])


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
	var p: Dictionary = players[target]
	if p["dead"]:
		tell(peer, "Too late for a medkit. Maybe the witch can help...")
		return
	if p["poison"] <= 0.0 and p["out"] <= 0.0 and not _has_pending_poison(target):
		tell(peer, "%s doesn't need a medkit." % p["name"])
		return
	if not take(peer, "medkit"):
		tell(peer, "You have no medkit. Jano's shop in the village sells them.")
		return
	cure(target)
	tell(peer, "Patched up %s." % p["name"])
	if target != peer:
		tell(target, "%s saved your life with a medkit." % players[peer]["name"])


## The flashlight ran dry and wants a fresh battery from the shared stash.
@rpc("any_peer", "call_local", "reliable")
func request_battery() -> void:
	if not multiplayer.is_server():
		return
	var peer := _sender()
	if not take(peer, "battery"):
		tell(peer, "No batteries left. Somebody buy some at Jano's!")
		return
	if peer == multiplayer.get_unique_id():
		_battery_ok()
	else:
		_battery_ok.rpc_id(peer)


## You won the escape minigame and got yourself out (not out of a hole: those need a friend).
@rpc("any_peer", "call_local", "reliable")
func request_self_free() -> void:
	if not multiplayer.is_server():
		return
	var peer := _sender()
	var what := stuck_in(peer)
	if what == "" or what == "hole":
		return
	set_stuck(peer, "")
	tell(peer, "You wriggle free of the %s!" % what)


## You botched getting out of a bear trap. It hurts. A lot.
@rpc("any_peer", "call_local", "reliable")
func request_trap_hurt() -> void:
	if not multiplayer.is_server():
		return
	var peer := _sender()
	if stuck_in(peer) == "bear trap":
		set_status(peer, Status.PASSED_OUT, 10.0)
		tell(0, "%s fumbled the bear trap and passed out from the pain." % players[peer]["name"])


## Host only: switch cheats on or off for everyone.
@rpc("any_peer", "call_local", "reliable")
func request_cheats(on: bool) -> void:
	if multiplayer.is_server() and _sender() == 1:
		cheats = on
		_push()
		tell(0, "CHEATS %s. F1 free and heal yourself, F2 +500 €, F3 back to camp." % ("ON" if on else "OFF"))


## A cheat key (only works while the host has cheats on).
@rpc("any_peer", "call_local", "reliable")
func request_cheat(what: String) -> void:
	if not multiplayer.is_server() or not cheats:
		return
	var peer := _sender()
	match what:
		"free":
			set_stuck(peer, "")
			cure(peer)
			set_status(peer, Status.OK)
			if players.has(peer) and players[peer]["dead"]:
				revive(peer)
		"cash":
			add_cash(500)
		"god":
			if players.has(peer):
				players[peer]["god"] = not players[peer].get("god", false)
				tell(peer, "God mode %s." % ("ON" if players[peer]["god"] else "OFF"))
				_push()
		"revive_all":
			for other in players:
				cure(other)
				set_stuck(other, "")
				if players[other]["dead"]:
					revive(other)
		"identify_all":
			const Mushroom := preload("res://scripts/mushroom.gd")
			for k in Mushroom.KINDS:
				known[k] = true
			_push()
		_:
			var level := get_tree().get_first_node_in_group("level")
			if level and level.has_method("cheat"):
				level.cheat(what, peer)


## Pull a stuck friend out of a trap, the mud or a hole: hold E on them (from a few metres away,
## so you don't get stuck too). Sent every ~0.1 s while E is held; the host adds up the pulling.
@rpc("any_peer", "call_local", "unreliable_ordered")
func request_pull(target: int) -> void:
	if not multiplayer.is_server():
		return
	var peer := _sender()
	if peer == target or not is_alive(peer) or stuck_in(target) == "":
		return
	var a := _player_pos(peer)
	var b := _player_pos(target)
	if a == Vector3.INF or b == Vector3.INF or a.distance_to(b) > RESCUE_RANGE + 0.5:
		return
	if rescue.is_empty() or rescue.get("target") != target:
		if stuck_in(target) == "hole" and not take(peer, "rope"):
			tell(peer, "%s is down a hole. You need a ROPE (Jano's shop) to get them out." % players[target]["name"])
			return
		rescue = {"target": target, "by": peer, "progress": 0.0}
		tell(target, "%s is pulling you out! Wiggle (A/D in the green) to help!" % players[peer]["name"])
	if rescue["by"] != peer:
		return
	_rescue_last_pull = Time.get_ticks_msec() / 1000.0
	_add_rescue(0.1 / RESCUE_SECONDS)


## The stuck player wiggled well (a good press in the mud game): it helps whoever's pulling.
@rpc("any_peer", "call_local", "reliable")
func request_wiggle_help() -> void:
	if multiplayer.is_server() and not rescue.is_empty() and rescue["target"] == _sender():
		_add_rescue(0.12)


func _add_rescue(amount: float) -> void:
	rescue["progress"] = minf(float(rescue["progress"]) + amount, 1.0)
	if rescue["progress"] >= 1.0:
		var target: int = rescue["target"]
		var by: int = rescue["by"]
		var what := stuck_in(target)
		rescue = {}
		set_stuck(target, "")
		tell(0, "%s pulled %s out of the %s!" % [players[by]["name"], players[target]["name"], what])
		_rescued.rpc(target, by)
	else:
		_push()


## Kept for old callers: start pulling (one tick).
@rpc("any_peer", "call_local", "reliable")
func request_free(target: int) -> void:
	request_pull(target)


## Every peer: the rescued friend's own machine lifts them onto solid ground next to the rescuer.
@rpc("authority", "call_local", "reliable")
func _rescued(target: int, by: int) -> void:
	var me: Node3D = null
	var helper: Node3D = null
	for p in get_tree().get_nodes_in_group("players"):
		if p.peer_id == target:
			me = p
		elif p.peer_id == by:
			helper = p
	if me and helper and me.is_multiplayer_authority():
		var side: Vector3 = helper.global_basis.x * 0.9
		me.global_position = helper.global_position + side + Vector3(0, 0.3, 0)
		me.velocity = Vector3.ZERO
		me.reset_fall()


## Grab a passed-out friend by the collar and drag them along (E again lets go).
@rpc("any_peer", "call_local", "reliable")
func request_drag(target: int) -> void:
	if not multiplayer.is_server() or not players.has(target):
		return
	var peer := _sender()
	if peer == target or not is_alive(peer):
		return
	var p: Dictionary = players[target]
	if p["dragged_by"] == peer:
		p["dragged_by"] = 0
	elif p["out"] > 0.0:
		p["dragged_by"] = peer
	_push()


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


## Use a one-shot item from your pockets (wine, duck, lottery ticket, flare, whistle).
@rpc("any_peer", "call_local", "reliable")
func request_use_item(item: String) -> void:
	if not multiplayer.is_server():
		return
	var peer := _sender()
	if not is_alive(peer) or not take(peer, item):
		return
	var who: String = players[peer]["name"]
	var pos := _player_pos(peer)
	match item:
		"flare":
			Hearing.emit(pos, 120.0, peer)
			Sfx.play_all("flare", pos)
			_flare.rpc(pos)
			tell(0, "%s fired a FLARE! Everyone can see it. Everything can hear it." % who)
		"whistle":
			give(peer, "whistle")  # you keep the whistle
			Hearing.emit(pos, 80.0, peer)
			Sfx.play_all("whistle", pos)
		"wine":
			set_status(peer, Status.TRIPPING, 20.0)
			tell(peer, "Cheap wine. The world goes soft and wobbly.")
		"duck":
			tell(0, "%s squeezes a rubber duck. *squeak*. Morale +1." % who)
			give(peer, "duck")  # you keep the duck
		"lottery":
			if randi() % 20 == 0:
				add_cash(100)
				tell(0, "%s scratched a winning lottery ticket! +100 €" % who)
			else:
				tell(peer, "Not a winner. Of course.")


# --- mirroring ------------------------------------------------------------------------


@rpc("authority", "call_local", "reliable")
func _battery_ok() -> void:
	battery_installed.emit()


func _push() -> void:
	if not multiplayer.is_server():
		return
	if Net.is_online():
		_sync.rpc({
			"cash": cash, "day": day, "batteries": batteries, "known": known, "house": house,
			"players": players, "car": car_seats, "quota": quota_index, "police": police_left,
			"missing": missing_peer, "cheats": cheats, "rescue": rescue,
		})
	changed.emit()


@rpc("authority", "call_remote", "reliable")
func _sync(state: Dictionary) -> void:
	cash = state["cash"]
	day = state["day"]
	batteries = state["batteries"]
	known = state["known"]
	house = state["house"]
	players = state["players"]
	car_seats = state["car"]
	quota_index = state["quota"]
	police_left = state["police"]
	missing_peer = state["missing"]
	cheats = state.get("cheats", false)
	rescue = state.get("rescue", {})
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


@rpc("authority", "call_local", "reliable")
func _flare(pos: Vector3) -> void:
	flare_fired.emit(pos)


@rpc("authority", "call_local", "reliable")
func _game_over(stats: Dictionary) -> void:
	game_over.emit(stats)


## Host: a queued effect kicks in now.
func _kick_in(peer_id: int, effect: int, display_name: String) -> void:
	const Mushroom := preload("res://scripts/mushroom.gd")
	if not players.has(peer_id) or not is_alive(peer_id):
		return
	if effect < 0:
		match display_name:
			"pond_water":
				tell(peer_id, "Your stomach makes a noise like a drain. You throw up everywhere. Now you're STARVING.")
				Sfx.play_all("vomit", _player_pos(peer_id))
				_gag.rpc(peer_id, "vomit")
		return
	match effect:
		Mushroom.Effect.TRIP, Mushroom.Effect.WITCH:
			if _count_trip(peer_id) >= OVERDOSE_TRIPS:
				set_status(peer_id, Status.PASSED_OUT, PASS_OUT_SECONDS)
				tell(peer_id, "That mushroom from earlier... and the one before... Lights out.")
			else:
				set_status(peer_id, Status.TRIPPING, TRIP_SECONDS)
				tell(peer_id, "Oh. Oh no. The trees are breathing. That mushroom from earlier...")
				highlight("%s starts tripping" % players[peer_id]["name"])
		Mushroom.Effect.STRONG:
			highlight("%s passes out face-first" % players[peer_id]["name"])
			set_status(peer_id, Status.PASSED_OUT, PASS_OUT_SECONDS)
			set_status(peer_id, Status.TRIPPING, PASS_OUT_SECONDS + 20.0)
			tell(peer_id, "You see the face of God. Then the ground.")
		Mushroom.Effect.POISON:
			set_status(peer_id, Status.POISONED, POISON_SECONDS)
			tell(peer_id, "Cramps. Cold sweat. That mushroom was POISON. Medkit or the witch, %d s." % int(POISON_SECONDS))
			tell(0, "%s looks green. Really green." % players[peer_id]["name"])


## Every peer: a gag effect on one player's screen (vomit...). The HUD listens.
@rpc("authority", "call_local", "reliable")
func _gag(peer_id: int, gag: String) -> void:
	if peer_id == multiplayer.get_unique_id():
		get_tree().call_group("hud", "play_gag", gag)


func _player_pos(peer_id: int) -> Vector3:
	for p in get_tree().get_nodes_in_group("players"):
		if p.peer_id == peer_id:
			return p.global_position
	return Vector3.INF


func _has_pending_poison(peer_id: int) -> bool:
	const Mushroom := preload("res://scripts/mushroom.gd")
	for e in _pending:
		if e["peer"] == peer_id and e["effect"] == Mushroom.Effect.POISON:
			return true
	return false


func _fresh(player_name: String) -> Dictionary:
	return {"name": player_name, "status": Status.OK, "left": 0.0, "poison": 0.0, "trip": 0.0, "out": 0.0,
		"dead": false, "medkit": 0, "was_poisoned": false, "was_out": false, "stuck": "", "dragged_by": 0}


## The status to show: the worst thing going on, and its time left.
func _derive(p: Dictionary) -> void:
	if p["dead"]:
		p["status"] = Status.DEAD
		p["left"] = 0.0
	elif p["out"] > 0.0:
		p["status"] = Status.PASSED_OUT
		p["left"] = p["out"]
	elif p["poison"] > 0.0:
		p["status"] = Status.POISONED
		p["left"] = p["poison"]
	elif p["trip"] > 0.0:
		p["status"] = Status.TRIPPING
		p["left"] = p["trip"]
	else:
		p["status"] = Status.OK
		p["left"] = 0.0


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
