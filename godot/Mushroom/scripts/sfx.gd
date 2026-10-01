extends Node
## Autoload "Sfx": sound effects and ambience. (Placeholder, being built.)


## This peer only: play a one-shot sound at a position (Vector3.INF = not positional).
func play(_sound: String, _pos := Vector3.INF, _volume_db := 0.0) -> void:
	pass


## Any peer: play a sound for everyone.
func play_all(sound: String, pos := Vector3.INF, volume_db := 0.0) -> void:
	play(sound, pos, volume_db)


## Every peer, by the level: 0 = morning ... 1 = midnight; picks the ambience.
func set_time_of_day(_t: float) -> void:
	pass
