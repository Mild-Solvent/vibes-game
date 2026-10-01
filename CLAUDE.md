# Notes for Claude sessions

Godot 4 (GDScript) prototype of "STANDBY... GO!", a co-op friendslop game where players are
the crew of a live TV show. Design docs: `docs/design/` (start with `01-concept/pitch.md`
and `02-gdd/00-gdd-core.md`). Record decisions in `docs/design/05-production/decisions.md`.

- Engine: Godot 4.4+, GL Compatibility renderer (potato PCs matter for this genre).
- Everything is built from code for now (`scripts/`); `scenes/main.tscn` only hosts `main.gd`.
  Scripts reference each other with `preload` consts, not `class_name`.
- Levels (`scripts/levels/`) extend `level.gd`, are all built on every peer at different world
  offsets, and define their rules in `server_tick` / `apply_state`. Add a show = add a level to
  `LEVELS` in `main.gd`.
- Networking: peer 1 (host) owns spawning, props and the show state; each player owns its
  own movement. RPCs that clients send to the host use `any_peer` + `call_local`.
- Keep the grey-box until the artist delivers assets (asset list: `docs/design/04-art/`).
- Before committing: `gdformat --line-length 120 scripts/ && gdlint scripts/`.
- The team: Adam writes in Slovak, Denis mostly in English. The artist owns the art direction.
