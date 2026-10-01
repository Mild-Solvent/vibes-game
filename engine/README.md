# engine/

The portable Godot editor both games run on. It is not committed (about 150 MB unpacked):
`play.bat` in the repo root downloads the pinned version
(see `tools/launcher.ps1`) into this folder on first use.

The `._sc_` file puts Godot in self-contained mode, so its editor settings stay in this folder.
To upgrade, change `$GodotVersion` in `tools/launcher.ps1` and delete `godot.exe`.
