# engine/

The portable Godot editor both games run on. It is not committed (about 150 MB unpacked):
`setup.bat` in the repo root, or any `play-*.bat` / `edit-*.bat`, downloads the pinned version
(see `tools/run.ps1`) into this folder on first use.

The `._sc_` file puts Godot in self-contained mode, so its editor settings stay in this folder.
To upgrade, change `$GodotVersion` in `tools/run.ps1` and delete `godot.exe`.
