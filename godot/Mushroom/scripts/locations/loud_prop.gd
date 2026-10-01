extends "res://scripts/prop.gd"
## A clattery prop (steel tray, gurney, bucket, tin can): when it hits something, or gets shoved
## along fast, everything that hunts by sound hears it. Host-side, like every prop.

const COOLDOWN := 0.6

var display_name := "Junk"
var loudness := 30.0  # Hearing loudness of a proper clang
var sound := "tray_drop"
var _quiet_for := 1.5  # not while the world settles at startup


func _on_impact(speed: float) -> void:
	if not multiplayer.is_server() or removed or _quiet_for > 0.0 or speed < 1.2:
		return
	_clang(clampf(speed / 4.0, 0.5, 1.5))


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if not multiplayer.is_server():
		return
	_quiet_for -= delta
	# Wheels squeal when it's pushed or dragged about.
	if _quiet_for <= 0.0 and holder_id == 0 and linear_velocity.length() > 2.0:
		_clang(0.5)


func reset_to_home() -> void:
	super.reset_to_home()
	_quiet_for = 1.5


func _clang(strength: float) -> void:
	_quiet_for = COOLDOWN
	Hearing.emit(global_position, loudness * strength, holder_id)
	Sfx.play_all(sound, global_position)
