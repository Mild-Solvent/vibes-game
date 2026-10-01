# Notes for Claude sessions

Godot 4 (GDScript) prototype of "STANDBY... GO!", a co-op friendslop game where players are
the crew of a live TV show. Design docs: `docs/design/` (start with `01-concept/pitch.md`
and `02-gdd/00-gdd-core.md`). Record decisions in `docs/design/05-production/decisions.md`.

- Two Godot projects: `tv-theatre/` (STANDBY... GO!: studio + theatre) and `mushroom/` (forest).
  Common code lives once in `shared/` and is linked into each project as `<game>/shared` by
  `tools/run.ps1` (directory junction, gitignored), so scripts reference it as `res://shared/...`.
  A change in `shared/` affects both games; check both still boot.
- `engine/` holds the pinned portable Godot (`$GodotVersion` in `tools/run.ps1`), not committed.
  Smoke test: `engine/godot.exe --headless --log-file <f> --path <game> --quit-after 400 -- --host`.
- Engine: Godot 4.7 (4.4+ works), GL Compatibility renderer (potato PCs matter for this genre).
- Everything is built from code for now (`shared/`, `<game>/scripts/`); `scenes/main.tscn` only hosts `main.gd`.
  Scripts reference each other with `preload` consts, not `class_name`.
- Levels (`scripts/levels/`) extend `level.gd`, are all built on every peer at different world
  offsets, and define their rules in `server_tick` / `apply_state`. Add a show = add a level to
  `LEVELS` in that game's `scripts/main.gd`.
- Networking: peer 1 (host) owns spawning, props and the show state; each player owns its
  own movement. RPCs that clients send to the host use `any_peer` + `call_local`.
- Keep the grey-box until the artist delivers assets (asset list: `docs/design/04-art/`).
- Before committing: `gdformat --line-length 120 shared tv-theatre/scripts mushroom/scripts && gdlint shared tv-theatre/scripts mushroom/scripts`.
- The team: Adam writes in Slovak, Denis mostly in English. The artist owns the art direction.
