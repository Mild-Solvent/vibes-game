extends Node
## Runs the round on the host: PREP -> LIVE -> WRAP -> PREP ... for the active level.
## The level decides the rules (server_tick); clients only receive state through _push().

signal changed

const Level := preload("res://scripts/levels/level.gd")
const PUSH_INTERVAL := 0.15

var running := false
var prep_override := -1.0  # testing: --prep=<seconds> on the command line
var live_override := -1.0  # testing: --live=<seconds>
var levels: Array = []

# Synced state.
var mode := 0
var phase: int = Level.Phase.PREP
var time_left := 20.0
var score := 50.0
var event := 0
var sub := 0  # level-specific (e.g. theatre scene / blackout)

var _push_timer := 0.0


func level() -> Node:
	return levels[mode]


## Host only.
func start(new_mode: int) -> void:
	mode = new_mode
	running = true
	_enter(Level.Phase.PREP)


func live_elapsed() -> float:
	return _live_duration() - time_left


func _live_duration() -> float:
	return level().live_duration() if live_override < 0.0 else live_override


func _process(delta: float) -> void:
	if not running or not multiplayer.is_server():
		return
	time_left -= delta
	match phase:
		Level.Phase.PREP:
			if time_left <= 0.0:
				_enter(Level.Phase.LIVE)
		Level.Phase.LIVE:
			level().server_tick(delta, self)
			score = clampf(score, 0.0, 100.0)
			if time_left <= 0.0:
				_enter(Level.Phase.WRAP)
		Level.Phase.WRAP:
			if time_left <= 0.0:
				_enter(Level.Phase.PREP)

	_push_timer -= delta
	if _push_timer <= 0.0:
		_push_timer = PUSH_INTERVAL
		_push.rpc(mode, phase, time_left, score, event, sub)


func _enter(next_phase: int) -> void:
	phase = next_phase
	event = 0
	if next_phase != Level.Phase.WRAP:
		sub = 0  # WRAP keeps the level's last sub (e.g. the forest's basket tally)
	_push_timer = 0.0
	match next_phase:
		Level.Phase.PREP:
			time_left = level().prep_duration() if prep_override < 0.0 else prep_override
			score = level().start_score()
			level().server_reset()
		Level.Phase.LIVE:
			time_left = _live_duration()
		Level.Phase.WRAP:
			time_left = level().wrap_duration()


@rpc("authority", "call_local", "unreliable_ordered")
func _push(new_mode: int, new_phase: int, new_time_left: float, new_score: float, new_event: int, new_sub: int) -> void:
	mode = new_mode
	phase = new_phase
	time_left = new_time_left
	score = new_score
	event = new_event
	sub = new_sub
	changed.emit()
