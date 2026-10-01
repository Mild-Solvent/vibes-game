# Notes for Claude sessions

Godot 4 (GDScript) prototype of "STANDBY... GO!", a co-op friendslop game where players are
the crew of a live TV show. Design docs: `docs/design/` (start with `01-concept/pitch.md`
and `02-gdd/00-gdd-core.md`). Record decisions in `docs/design/05-production/decisions.md`.

- Layout: `godot/engine/` (the user's Godot 4.7.2 exe, gitignored), `godot/Mushroom/`, `godot/TV/`,
  plus empty `Unreal/` and `Unity/`. The user opens the engine, imports a project and presses F5;
  don't add launcher scripts or a shared code folder. Each project is self-contained: common
  scripts (net, player, prop, hud, game_director, model_fit, levels/level.gd) are copies in each.
- Smoke test: `godot/engine/godot.exe --headless --log-file <f> --path godot/<Game> --quit-after 400 -- --host`.
- Art: free assets (Kenney etc.), matching the low-poly Kenney car look. Track each in that game's
  `CREDITS.md`. Models replace grey boxes through `_dress()` in `level.gd`, colliders unchanged.
- Engine: Godot 4.7.2 stable (latest); projects target 4.7, GL Compatibility renderer (potato PCs matter for this genre).
- Everything is built from code for now (`godot/<Game>/scripts/`); `scenes/main.tscn` only hosts `main.gd`.
  Scripts reference each other with `preload` consts, not `class_name`.
- Levels (`scripts/levels/`) extend `level.gd`, are all built on every peer at different world
  offsets, and define their rules in `server_tick` / `apply_state`. Add a show = add a level to
  `LEVELS` in that game's `scripts/main.gd`.
- Networking: peer 1 (host) owns spawning, props and the show state; each player owns its
  own movement. RPCs that clients send to the host use `any_peer` + `call_local`.
- The team: Adam writes in Slovak, Denis mostly in English. The artist owns the art direction.
