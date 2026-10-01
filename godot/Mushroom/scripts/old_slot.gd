extends "res://scripts/prop.gd"
## The old slot machine somebody dumped in the forest ruin. Heavy, but you can carry it. Once
## it's at camp, F spins it for a few euros and it coughs up something random.

const Terrain := preload("res://scripts/world/terrain.gd")
const CAMP_RADIUS := 18.0

var display_name := "Old slot machine"
var prompt := "spin it (%d €)" % Team.PRICES["old_slot"]


@rpc("any_peer", "call_local", "reliable")
func request_use() -> void:
	if not multiplayer.is_server() or removed:
		return
	var peer := _sender_id()
	if not Team.is_alive(peer):
		return
	if Vector2(global_position.x, global_position.z).length() > CAMP_RADIUS:
		Team.tell(peer, "It's rusted shut. Maybe if you took it home and gave it a good kick...")
		return
	var cost: int = Team.PRICES["old_slot"]
	if Team.cash < cost:
		Team.tell(peer, "It wants %d €. You're broke." % cost)
		return
	Team.add_cash(-cost)
	var roll := randi() % 100
	if roll < 25:
		Team.give(peer, "battery")
		Team.tell(0, "Ka-chunk. The old slot spits out a BATTERY.")
	elif roll < 40:
		Team.give(peer, "medkit")
		Team.tell(0, "Ding ding! The old slot spits out a MEDKIT.")
	elif roll < 52:
		Team.add_cash(40)
		Team.tell(0, "Coins everywhere! +40 €")
	elif roll < 54:
		Team.add_cash(250)
		Team.tell(0, "JACKPOT!!! +250 €. Nobody tell the casino.")
	elif roll < 64:
		Team.set_status(peer, Team.Status.TRIPPING, Team.TRIP_SECONDS)
		Team.tell(0, "A cloud of spores puffs out into %s's face." % Team.players[peer]["name"])
	else:
		Team.tell(peer, "Whirr... a moth flies out. Nothing.")


## Stays where you left it between days (it only comes back if it fell off the world).
func reset_to_home() -> void:
	if position.y < -10.0:
		super.reset_to_home()
