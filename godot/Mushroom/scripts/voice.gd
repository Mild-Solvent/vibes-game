extends Node
## Autoload "Voice": proximity voice chat and walkie-talkies. (Placeholder, being built.)


## Every peer: play a friend's recent voice from `pos` (the hag mimicking them, or the dark).
func play_mimic(_peer_id: int, _pos: Vector3) -> void:
	pass


## Any peer: how loud this friend is talking right now (0..1).
func level_of(_peer_id: int) -> float:
	return 0.0
