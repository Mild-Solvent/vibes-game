extends Node
## Autoload "Updater" (listed first): small in-game updates for the Android build.
##
## A full APK is ~35 MB, so most updates ship as a patch PCK holding only the files that changed
## since that APK (Godot's --export-patch). The game reads a manifest from the "android-latest"
## GitHub release:
##   {"build": 3, "apk_url": "...", "apk_mb": 34, "patch": 2, "pck_url": "...", "pck_kb": 180, "notes": "..."}
## - Same build, newer patch: download the PCK to user://patch/, restart, and it's loaded in _init
##   below, before every other script (that's why this autoload is first: the others then load
##   from the patch).
## - Newer build: the APK itself changed (engine, permissions, new autoload...), so the menu
##   button opens the APK download in the browser instead.
## A patch only applies to the APK it was made from; a stale one is deleted.
## Off on PC unless started with `-- --updater` (for testing the patch loading).
## Publish with tools/android_release.sh.

signal state_changed

## Bump together with version/code in export_presets.cfg for every new APK.
const BUILD := 3
const MANIFEST_URL := "https://github.com/Mild-Solvent/vibes-game/releases/download/android-latest/update.json"
const DIR := "user://patch"
const APPLIED := "user://patch/applied.cfg"

## "", "checking", "latest", "available", "downloading", "ready", "apk", "error"
var status := ""
var patch := 0  ## the patch number running now (0 = the APK as installed)
var remote := {}
var enabled := false

var _http: HTTPRequest
var _file := ""


func _init() -> void:
	enabled = OS.has_feature("mobile") or "--updater" in OS.get_cmdline_user_args()
	if not enabled:
		return
	var cfg := ConfigFile.new()
	if cfg.load(APPLIED) != OK:
		return
	var file: String = cfg.get_value("patch", "file", "")
	if int(cfg.get_value("patch", "build", 0)) != BUILD or file.is_empty():
		_clear_patches("")  # made for another APK: the new APK already has all of it
		return
	_clear_patches(file)
	if ProjectSettings.load_resource_pack(DIR.path_join(file), true):
		patch = int(cfg.get_value("patch", "number", 0))
		print("[updater] build %d, patch %d loaded" % [BUILD, patch])
	else:
		push_warning("[updater] could not load %s" % file)


func _ready() -> void:
	if not enabled:
		return
	_http = HTTPRequest.new()
	_http.timeout = 30.0
	_http.request_completed.connect(_on_done)
	add_child(_http)
	check()


## "Build 3", or "Build 3.2" with patch 2 applied.
func version_text() -> String:
	return "Build %d%s" % [BUILD, (".%d" % patch) if patch > 0 else ""]


func check() -> void:
	if _busy():
		return
	_set_status("checking")
	_http.download_file = ""
	if _http.request(MANIFEST_URL + "?t=%d" % Time.get_unix_time_from_system()) != OK:
		_set_status("error")


## The menu button: does whatever the current state calls for.
func press() -> void:
	match status:
		"available":
			_download()
		"ready":
			OS.set_restart_on_exit(true)
			get_tree().quit()
		"apk":
			OS.shell_open(str(remote.get("apk_url", "")))
		"checking", "downloading":
			pass
		_:
			check()


func progress() -> float:
	if status != "downloading" or _http.get_body_size() <= 0:
		return 0.0
	return float(_http.get_downloaded_bytes()) / _http.get_body_size()


func _download() -> void:
	var url := str(remote.get("pck_url", ""))
	if url.is_empty():
		_set_status("error")
		return
	DirAccess.make_dir_recursive_absolute(DIR)
	_file = "patch-%d-%d.pck" % [BUILD, int(remote.get("patch", 0))]
	_http.download_file = DIR.path_join(_file + ".part")
	_set_status("downloading")
	if _http.request(url) != OK:
		_set_status("error")


func _on_done(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var ok := result == HTTPRequest.RESULT_SUCCESS and code == 200
	if status == "checking":
		var data = JSON.parse_string(body.get_string_from_utf8()) if ok else null
		if not data is Dictionary:
			_set_status("error")
			return
		remote = data
		if int(remote.get("build", 0)) > BUILD:
			_set_status("apk")
		elif int(remote.get("build", 0)) == BUILD and int(remote.get("patch", 0)) > patch:
			_set_status("available")
		else:
			_set_status("latest")
	elif status == "downloading":
		var part := DIR.path_join(_file + ".part")
		if not ok or DirAccess.rename_absolute(part, DIR.path_join(_file)) != OK:
			DirAccess.remove_absolute(part)
			_set_status("error")
			return
		var cfg := ConfigFile.new()
		cfg.set_value("patch", "build", BUILD)
		cfg.set_value("patch", "number", int(remote.get("patch", 0)))
		cfg.set_value("patch", "file", _file)
		cfg.save(APPLIED)
		_set_status("ready")


func _busy() -> bool:
	return status == "checking" or status == "downloading"


func _set_status(s: String) -> void:
	status = s
	state_changed.emit()


## Delete every patch file except `keep` (old patches pile up otherwise).
func _clear_patches(keep: String) -> void:
	var dir := DirAccess.open(DIR)
	if dir == null:
		return
	for f in dir.get_files():
		if f.ends_with(".pck") or f.ends_with(".part"):
			if f != keep:
				dir.remove(f)
	if keep.is_empty():
		dir.remove("applied.cfg")
