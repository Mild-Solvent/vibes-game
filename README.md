# vibes-game

Two co-op friendslop games made in Godot 4, sharing one codebase.

- **STANDBY... GO!** You and your friends are the crew of a live TV show or theatre play.
  The audience only sees what's on camera or on stage. Everything behind it is chaos.
- **Mushroom Foraging.** Friends lost in a foggy Slovak forest, filling a basket before dark.

## Play

Double-click **`play.bat`** and pick a number. The first run downloads Godot (about 85 MB) into
`engine/`; after that it starts instantly. Nothing else needs installing.

To play together, one person picks **Host** in the game's menu and the others type the host's IP
and click **Join** (UDP port 7777). Over the internet, the host forwards UDP 7777, or everyone joins
the same Tailscale / ZeroTier / Radmin VPN network and uses the host's VPN IP.

Controls: WASD, Shift sprint, Space jump, E / left click grab & drop, Q / right click throw,
F taste (mushrooms), Esc frees the mouse.

## Folders

```
play.bat           the launcher (play, test with two windows, open in the editor)
games/tv-theatre/  Godot project: STANDBY... GO! (TV studio + theatre)
games/mushroom/    Godot project: Mushroom Foraging
shared/            code both games use (multiplayer, player, props, HUD, round loop)
engine/            portable Godot, filled in by play.bat (not in git)
tools/             launcher script
docs/design/       pitch, game design docs, art direction, roadmap
```

`shared/` is linked into each game as `games/<game>/shared` (a Windows directory junction that
`play.bat` creates), so both games load it as `res://shared/...` and an edit in either editor
changes the one copy.

## What's in the prototype

Three playable grey-box demos across the two games. In STANDBY... GO! the host picks the show in the menu.

| Show | You are | Win by | Lose by |
|---|---|---|---|
| **We're Live!** (TV studio) | the crew of Channel 6's live news | one anchor on the green tape behind the desk, everyone else out of shot | dead air, walking into the on-air camera's frame (yellow floor tape) |
| **Places, Please!** (theatre) | the backstage crew of a live play | one actor on the STAR during scenes; in each blackout, moving the TREE / CASTLE_WALL / THRONE to the glowing marks | an empty stage, crew caught in the light, the wrong set when the lights come up |
| **Mushroom foraging** (forest) | friends lost in a foggy Slovak forest | filling the basket by the car with good mushrooms before dark | poisonous look-alikes in the basket; tasting one (F) makes you trip for 25 s |

Shared bits:
- **Round loop** (`shared/game_director.gd`, host-run): PREP → LIVE → WRAP, with a score meter
  (ratings / applause / basket). Each level's rules live in `games/<game>/scripts/levels/*.gd`.
- **Multiplayer** (`shared/net.gd`): ENet host/join, MultiplayerSpawner for players,
  client-authoritative movement, host-simulated physics props. Every level of a game is built on
  every peer (far apart), so node paths always match.
- **Grab, throw and taste** props (`shared/prop.gd`, `games/mushroom/scripts/mushroom.gd`).
- The TV studio's on-air camera and the theatre's audience view render to monitors the crew
  can watch (the start of "The Tape").



## Next spikes (from the roadmap)

- **T2 voice**: proximity voice + a live mic that routes nearby voices into the broadcast
  (AudioEffectCapture → network → AudioStreamGenerator, or GodotSteam voice). Biggest risk.
- **T3 director**: 2–3 cameras and a TAKE button in the control room switching the broadcast.
- **T4 The Tape**: record transforms + events during LIVE and replay them after WRAP.
- Teleprompter typed live by one player, read by the anchor.

## Code style

GDScript, formatted with [gdtoolkit](https://github.com/Scony/godot-gdscript-toolkit):
`gdformat --line-length 120 shared games && gdlint shared games`.

## Credits

Third-party art and licences: [CREDITS.md](CREDITS.md).
