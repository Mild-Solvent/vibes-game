extends Node
## Autoload "Hearing": the sounds monsters can hear. Anything loud reports itself here (voices,
## walkies, flares, whistles, dropped trays, car horns...). The host keeps a short memory of them;
## hunters (the hag, the Nurse, the Miner...) ask for the loudest recent one near them.
##
## Loudness is roughly "metres away it can be heard from": a whisper is 4, talking 15,
## shouting 35, a whistle 80, a flare 120.

const MEMORY_SECONDS := 4.0

var _events: Array[Dictionary] = []  # host: {"pos": Vector3, "loud": float, "time": float, "peer": int}


## Any peer: something made a noise at `pos`. `peer` is who made it (0 = nobody in particular).
func emit(pos: Vector3, loudness: float, peer := 0) -> void:
	if loudness <= 0.5:
		return
	if multiplayer.is_server():
		_remember(pos, loudness, peer)
	else:
		_report.rpc_id(1, pos, loudness, peer)


## Host: the loudest noise in the last few seconds that can be heard at `listener`.
## Returns {} if nothing, else {"pos", "loud", "peer"}. Louder and closer wins.
func loudest_heard(listener: Vector3, max_range := 200.0) -> Dictionary:
	var now := Time.get_ticks_msec() / 1000.0
	var best := {}
	var best_score := 0.0
	for e in _events:
		var age: float = now - e["time"]
		if age > MEMORY_SECONDS:
			continue
		var d := listener.distance_to(e["pos"])
		if d > max_range or d > e["loud"]:
			continue
		var score: float = (e["loud"] - d) * (1.0 - age / MEMORY_SECONDS)
		if score > best_score:
			best_score = score
			best = e
	return best


func _process(_delta: float) -> void:
	if _events.is_empty():
		return
	var now := Time.get_ticks_msec() / 1000.0
	_events = _events.filter(func(e): return now - e["time"] < MEMORY_SECONDS)


func _remember(pos: Vector3, loudness: float, peer: int) -> void:
	_events.append({"pos": pos, "loud": loudness, "time": Time.get_ticks_msec() / 1000.0, "peer": peer})
	if _events.size() > 256:
		_events.pop_front()


@rpc("any_peer", "unreliable")
func _report(pos: Vector3, loudness: float, peer: int) -> void:
	if multiplayer.is_server():
		_remember(pos, loudness, peer)
