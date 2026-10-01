# STANDBY... GO! (working title)

A co-op friendslop game: **you and your friends are the crew of a live show** (TV and theatre).
The audience only sees what's on camera or on stage. Everything behind it is chaos.
Plus a mushroom-foraging demo, because the artist liked that idea best.

This repo holds two separate Godot 4 projects, one per game:

| Folder | Game | Shows inside |
|---|---|---|
| [`tv-theatre/`](tv-theatre) | **STANDBY... GO!** | We're Live! (TV studio), Places, Please! (theatre) |
| [`mushroom/`](mushroom) | **Mushroom Foraging** | the foggy forest |

Each folder is its own Godot project with its own `project.godot`. The netcode, player, props,
HUD and round loop started as one shared codebase and are copied into both, so the games can
now drift apart freely. The design docs from the research session live in
[docs/design](docs/design/README.md) (pitch, GDD, mode ideas, art direction, roadmap).

## Run it

1. Install [Godot 4.4+](https://godotengine.org/download) (standard build, no .NET needed).
2. Open Godot, click **Import**, pick `tv-theatre/project.godot` or `mushroom/project.godot`,
   then press **F5**. Import both if you want both games in the project list.
3. One player clicks **Host**, everyone else types the host's IP and clicks **Join** (UDP port 7777).

Playing over the internet: the host forwards UDP 7777, or everyone joins the same
Tailscale / ZeroTier / Radmin VPN network and uses the host's VPN IP. Steam lobbies come later.

Testing alone with two windows: in the editor, **Debug → Customize Run Instances**,
enable 2 instances, give one `-- --host --name=Adam` and the other
`-- --join=127.0.0.1 --name=Denis`. Or from a terminal:

```sh
godot --path tv-theatre -- --host --show=0 --name=Adam   # 0 TV, 1 theatre
godot --path tv-theatre -- --join=127.0.0.1 --name=Denis
godot --path mushroom -- --host --name=Adam
```

## What's in the prototype

Three playable grey-box demos across the two projects. In STANDBY... GO! the host picks the show in the menu.

| Show | You are | Win by | Lose by |
|---|---|---|---|
| **We're Live!** (TV studio) | the crew of Channel 6's live news | one anchor on the green tape behind the desk, everyone else out of shot | dead air, walking into the on-air camera's frame (yellow floor tape) |
| **Places, Please!** (theatre) | the backstage crew of a live play | one actor on the STAR during scenes; in each blackout, moving the TREE / CASTLE_WALL / THRONE to the glowing marks | an empty stage, crew caught in the light, the wrong set when the lights come up |
| **Mushroom foraging** (forest) | friends lost in a foggy Slovak forest | filling the basket by the car with good mushrooms before dark | poisonous look-alikes in the basket; tasting one (F) makes you trip for 25 s |

Shared bits (paths are inside each project folder):
- **Round loop** (`scripts/game_director.gd`, host-run): PREP → LIVE → WRAP, with a score meter
  (ratings / applause / basket). Each level's rules live in `scripts/levels/*.gd`.
- **Multiplayer** (`scripts/net.gd`): ENet host/join, MultiplayerSpawner for players,
  client-authoritative movement, host-simulated physics props. Every level of a game is built on
  every peer (far apart), so node paths always match.
- **Grab, throw and taste** props (`scripts/prop.gd`, `mushroom/scripts/mushroom.gd`).
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
`gdformat --line-length 120 tv-theatre/scripts mushroom/scripts && gdlint tv-theatre/scripts mushroom/scripts`.
