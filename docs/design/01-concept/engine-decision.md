# Engine decision

**Status: DECIDED Godot 4 (2026-10-01).** The Unity analysis below is kept for reference; the voice risk it describes still applies, so spike T2 early.

## Short version
Unity is what the genre runs on. Lethal Company, R.E.P.O., Content Warning, Peak,
Phasmophobia, Schedule I and Among Us are all Unity. The whole toolchain we need
(Steam lobbies, proximity voice, physics, low-poly pipeline) is solved there and
documented with examples, and C# works very well for AI-assisted "vibe" coding.

## Comparison for *this* game

| | Unity 6 | Godot 4 | Unreal 5 |
|---|---|---|---|
| Genre precedent | Nearly all friendslop hits | Webfishing (proves it's possible) | Rare for this genre |
| Steam lobbies / P2P | Mature: Facepunch.Steamworks, Steamworks.NET, FishNet/NGO Steam transports | GodotSteam, works but fewer examples | Built-in Online Subsystem Steam, good |
| Proximity voice | Dissonance (used by the Lethal Company family), Photon Voice, or Steam voice | DIY or immature addons; **biggest risk** | Built-in VoIP, okay |
| **Voice → "live mic" broadcast mix** (core to us) | Dissonance exposes audio streams for rerouting | DIY | Possible, more C++ |
| **Render-to-texture camera feeds, The Tape recording** | Easy (RenderTextures, multiple cameras) | Easy (SubViewports) | Easy, but heavy |
| Low-poly art pipeline for the artist | Blender → FBX, trivial | Blender → glTF, trivial | Overkill |
| Iteration speed / build size | Good | Best | Slowest, large builds |
| AI-assisted coding | Excellent (huge C# corpus) | Good (GDScript) | Weaker (C++/Blueprints) |
| Cost | Free under $200k revenue/yr (Unity Personal) | Free, MIT | Free, then 5% royalty past $1M gross |

## Why not Godot?
It's a real option, and Webfishing shipped on it. But our core mechanic is
**routing voice into an in-game broadcast and recording it**, and Godot's multiplayer
voice story is the weakest of the three. I don't want our riskiest tech on our least
supported stack.

## Why not Unreal?
Too heavy for low-poly 2–6 player jank. It has slow iteration, big builds, and C++ or
Blueprints are harder to vibe-code. Its strengths (fidelity, Nanite, big worlds) are
things we don't need.

## Proposed Unity stack (to validate in tech spikes)
- **Unity 6 LTS**, URP (low-poly, runs on potato PCs, which matters for streamers' viewers)
- **Networking:** FishNet (free, clean API) + FishySteamworks transport, *or* Netcode for
  GameObjects + Facepunch transport. Decide after spike T1.
- **Steam:** Facepunch.Steamworks (lobbies, invites, friends)
- **Voice:** Dissonance (paid asset, ~$70) *or* Steam voice via Facepunch. Decide after spike T2.
- **Physics:** built-in PhysX, deliberately a bit floppy
- **Version control:** git + Git LFS for art (set up when the Unity project is created)

## Tech spikes before committing (see roadmap)
- **T1** Steam lobby → 4 players in a room, synced physics props
- **T2** Proximity voice + a "live mic" object that picks up voices near it and routes
  them into a separate "broadcast" audio bus
- **T3** 2–3 in-world cameras → director switcher → "broadcast" RenderTexture
- **T4** The Tape: record transforms, events and voice during a show, replay it
  afterwards. Stretch goal: export to MP4 or WebM (Content Warning exports clips; that's our bar)
