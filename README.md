# vibes-game

Co-op friendslop games, each one its own engine project.

```
godot/
  engine/     put the Godot 4.7.2 editor here (godot.exe; not committed)
  Mushroom/   Godot project: Mushroom Foraging
  TV/         Godot project: STANDBY... GO! (TV studio + theatre)
Unreal/       empty for now
Unity/        empty for now
docs/         design docs and scenario write-ups
```

## Play / edit (Godot)

1. Get **Godot 4.7.2** (standard build, not .NET) from
   [godotengine.org](https://godotengine.org/download) and put `godot.exe` in `godot/engine/`.
2. Open it, click **Import**, pick `godot/Mushroom/project.godot` or `godot/TV/project.godot`.
3. Press **F5**.

Multiplayer: one player clicks **Host** in the menu, the others type the host's IP and click
**Join** (UDP port 7777). Over the internet, the host forwards UDP 7777, or everyone joins the same
Tailscale / ZeroTier / Radmin VPN and uses the host's VPN IP.

Testing alone with two windows: in the editor, **Debug → Customize Run Instances**, enable 2
instances, give one `-- --host --name=Adam` and the other `-- --join=127.0.0.1 --name=Denis`.

Each game is fully self-contained: copy one folder anywhere and it opens. Art credits are in each
game's `CREDITS.md`.

## What's in the prototype

Three playable grey-box demos across the two games. In STANDBY... GO! the host picks the show in the menu.

| Show | You are | Win by | Lose by |
|---|---|---|---|
| **We're Live!** (TV studio) | the crew of Channel 6's live news | one anchor on the green tape behind the desk, everyone else out of shot | dead air, walking into the on-air camera's frame (yellow floor tape) |
| **Places, Please!** (theatre) | the backstage crew of a live play | one actor on the STAR during scenes; in each blackout, moving the TREE / CASTLE_WALL / THRONE to the glowing marks | an empty stage, crew caught in the light, the wrong set when the lights come up |
| **Mushroom foraging** (forest) | friends lost in a foggy Slovak forest | filling the basket by the car with good mushrooms before dark | poisonous look-alikes in the basket; tasting one (F) makes you trip for 25 s |

Both games have (each its own copy):
- **Round loop** (`scripts/game_director.gd`, host-run): PREP → LIVE → WRAP, with a score meter
  (ratings / applause / basket). Each level's rules live in `scripts/levels/*.gd`.
- **Multiplayer** (`scripts/net.gd`): ENet host/join, MultiplayerSpawner for players,
  client-authoritative movement, host-simulated physics props. Every level of a game is built on
  every peer (far apart), so node paths always match.
- **Grab, throw and taste** props (`scripts/prop.gd`, `Mushroom/scripts/mushroom.gd`).
- The TV studio's on-air camera and the theatre's audience view render to monitors the crew
  can watch (the start of "The Tape").



