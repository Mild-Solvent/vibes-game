# STANDBY... GO! (working title)

A co-op friendslop game: **you and your friends are the crew of a live show** (TV and theatre).
The audience only sees what's on camera or on stage. Everything behind it is chaos.
Plus a mushroom-foraging demo, because the artist liked that idea best.

## Layout

| Folder | What |
|---|---|
| [`tv-theatre/`](tv-theatre) | Godot project: **STANDBY... GO!** with We're Live! (TV studio) and Places, Please! (theatre) |
| [`mushroom/`](mushroom) | Godot project: **Mushroom Foraging** (the foggy forest) |
| [`shared/`](shared) | Code both games use: netcode, player, props, HUD, round loop, level base |
| `engine/` | Portable Godot 4.7.2, downloaded on first run (not in git) |
| [`tools/run.ps1`](tools/run.ps1) | Setup + launcher the `.bat` files call |
| [`docs/design`](docs/design/README.md) | Pitch, GDD, mode ideas, art direction, roadmap |

`shared/` is linked into each game as `<game>/shared` (a Windows directory junction made by setup),
so both games load it as `res://shared/...` and an edit from either editor changes the one copy.

## Run it (Windows)

Double-click a `.bat` in the repo root. The first one you run downloads Godot into `engine/`
and links `shared/` (or run `setup.bat` once up front).

| File | Does |
|---|---|
| `play-tv-theatre.bat` / `play-mushroom.bat` | starts the game |
| `edit-tv-theatre.bat` / `edit-mushroom.bat` | opens it in the Godot editor (F5 runs it) |
| `test2p-tv-theatre.bat` / `test2p-mushroom.bat` | two windows on this PC, one hosts and one joins |

In the menu, one player clicks **Host**, everyone else types the host's IP and clicks **Join** (UDP port 7777).

Playing over the internet: the host forwards UDP 7777, or everyone joins the same
Tailscale / ZeroTier / Radmin VPN network and uses the host's VPN IP. Steam lobbies come later.

From a terminal: `engine\godot.exe --path tv-theatre -- --host --show=0 --name=Adam` (0 TV, 1 theatre),
`engine\godot.exe --path mushroom -- --join=127.0.0.1 --name=Denis`.

## What's in the prototype

Three playable grey-box demos across the two games. In STANDBY... GO! the host picks the show in the menu.

| Show | You are | Win by | Lose by |
|---|---|---|---|
| **We're Live!** (TV studio) | the crew of Channel 6's live news | one anchor on the green tape behind the desk, everyone else out of shot | dead air, walking into the on-air camera's frame (yellow floor tape) |
| **Places, Please!** (theatre) | the backstage crew of a live play | one actor on the STAR during scenes; in each blackout, moving the TREE / CASTLE_WALL / THRONE to the glowing marks | an empty stage, crew caught in the light, the wrong set when the lights come up |
| **Mushroom foraging** (forest) | friends lost in a foggy Slovak forest | filling the basket by the car with good mushrooms before dark | poisonous look-alikes in the basket; tasting one (F) makes you trip for 25 s |

Shared bits:
- **Round loop** (`shared/game_director.gd`, host-run): PREP → LIVE → WRAP, with a score meter
  (ratings / applause / basket). Each level's rules live in `<game>/scripts/levels/*.gd`.
- **Multiplayer** (`shared/net.gd`): ENet host/join, MultiplayerSpawner for players,
  client-authoritative movement, host-simulated physics props. Every level of a game is built on
  every peer (far apart), so node paths always match.
- **Grab, throw and taste** props (`shared/prop.gd`, `mushroom/scripts/mushroom.gd`).
- The TV studio's on-air camera and the theatre's audience view render to monitors the crew
  can watch (the start of "The Tape").

Controls: WASD, Shift sprint, Space jump, E / left click grab & drop, Q / right click throw,
F taste (mushrooms), Esc frees the mouse.

## Next spikes (from the roadmap)

- **T2 voice**: proximity voice + a live mic that routes nearby voices into the broadcast
  (AudioEffectCapture → network → AudioStreamGenerator, or GodotSteam voice). Biggest risk.
- **T3 director**: 2–3 cameras and a TAKE button in the control room switching the broadcast.
- **T4 The Tape**: record transforms + events during LIVE and replay them after WRAP.
- Teleprompter typed live by one player, read by the anchor.

## Code style

GDScript, formatted with [gdtoolkit](https://github.com/Scony/godot-gdscript-toolkit):
`gdformat --line-length 120 shared tv-theatre/scripts mushroom/scripts && gdlint shared tv-theatre/scripts mushroom/scripts`.
