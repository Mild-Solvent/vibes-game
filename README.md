# STANDBY... GO! (working title)

A co-op friendslop game: **you and your friends are the crew of a live TV show.**
The audience only sees what's on camera. Everything behind it is chaos.

This repo is the Godot 4 prototype. The design docs from the research session live in
[docs/design](docs/design/README.md) (pitch, GDD, mode ideas, art direction, roadmap).

## Run it

1. Install [Godot 4.4+](https://godotengine.org/download) (standard build, no .NET needed).
2. Open Godot, **Import** this folder (`project.godot`), press **F5**.
3. One player clicks **Host**, everyone else types the host's IP and clicks **Join** (UDP port 7777).

Playing over the internet: the host forwards UDP 7777, or everyone joins the same
Tailscale / ZeroTier / Radmin VPN network and uses the host's VPN IP. Steam lobbies come later.

Testing alone with two windows: in the editor, **Debug → Customize Run Instances**,
enable 2 instances, give one `-- --host --name=Adam` and the other
`-- --join=127.0.0.1 --name=Denis`. Or from a terminal:

```sh
godot --path . -- --host --name=Adam
godot --path . -- --join=127.0.0.1 --name=Denis
```

## What's in the prototype

- **TV studio grey-box** (built in code, `scripts/studio.gd`): set with news desk and backdrop,
  the on-air camera with a tally light, backstage prop table and control desk.
- **The broadcast**: the on-air camera renders into a SubViewport shown on a big monitor
  backstage and a confidence monitor for the anchor, with a lower third, LIVE tag and a
  "technical difficulties" card on dead air.
- **Show loop** (`scripts/show_director.gd`, host-run): PREP 20 s → LIVE 3 min → WRAP.
  Ratings go up with exactly one anchor on the green tape and a clean shot, and drain on
  dead air or when crew wander into frame (the yellow floor tape marks the shot edges).
- **Multiplayer** (`scripts/net.gd`): ENet host/join, MultiplayerSpawner for players,
  client-authoritative movement, host-simulated physics props.
- **Grab and throw** props (`scripts/prop.gd`): VT tapes, the cue sheet, boxes, the anchor's chair, coffee...

Controls: WASD, Shift sprint, Space jump, E / left click grab & drop, Q / right click throw, Esc frees the mouse.

## Next spikes (from the roadmap)

- **T2 voice**: proximity voice + a live mic that routes nearby voices into the broadcast
  (AudioEffectCapture → network → AudioStreamGenerator, or GodotSteam voice). Biggest risk.
- **T3 director**: 2–3 cameras and a TAKE button in the control room switching the broadcast.
- **T4 The Tape**: record transforms + events during LIVE and replay them after WRAP.
- Teleprompter typed live by one player, read by the anchor.

## Code style

GDScript, formatted with [gdtoolkit](https://github.com/Scony/godot-gdscript-toolkit):
`gdformat --line-length 120 scripts/ && gdlint scripts/`.
