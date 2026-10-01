extends Node
## Autoload "Settings": the player's settings (volume, mic, mouse, window, graphics) and the last
## name / address / port used, saved to user://settings.cfg.
##
## Read the values directly (Settings.fov, Settings.mouse_sensitivity, Settings.foliage_density...).
## Change them with set_value("key", value): it applies what needs applying, emits `changed` and
## saves a moment later. Volumes are linear 0..1 on the buses Master, Music, SFX and Voice (+ Walkie);
## Music and SFX are created here if nobody made them yet.

signal changed

const PATH := "user://settings.cfg"
const SECTION := "settings"
const QUALITY_NAMES := ["Low", "Medium", "High"]
const FOLIAGE := [0.4, 0.7, 1.0]
const SAVE_DELAY := 0.6
## Keys saved to disk (everything a menu can change).
const KEYS := [
	"master_volume", "music_volume", "sfx_volume", "voice_volume", "mic_device", "push_to_talk",
	"mouse_sensitivity", "invert_y", "fov", "fullscreen", "vsync", "quality",
	"last_name", "last_address", "last_port",
]

var master_volume := 0.8
var music_volume := 0.7
var sfx_volume := 0.8
var voice_volume := 1.0
var mic_device := ""  ## "" = system default
var push_to_talk := false  ## false = open mic, true = hold the talk key

var mouse_sensitivity := 0.0025  ## radians per pixel (0.0005..0.008)
var invert_y := false
var fov := 80.0  ## degrees, 60..100

var fullscreen := false
var vsync := true
var quality := 2  ## 0 Low, 1 Medium, 2 High; fog_quality / shadows / foliage_density follow it
var fog_quality := 2  ## 0 cheap fog, 1 normal, 2 full (volumetric-looking layers if the level has them)
var shadows := true
var foliage_density := 1.0  ## multiply grass / bush counts by this

var last_name := ""
var last_address := "127.0.0.1"
var last_port := 7777

var _save_left := -1.0


func _ready() -> void:
	_ensure_bus("Music")
	_ensure_bus("SFX")
	_ensure_bus("Voice")
	load_settings()
	apply()


func _process(delta: float) -> void:
	if _save_left > 0.0:
		_save_left -= delta
		if _save_left <= 0.0:
			save_settings()


## Read user://settings.cfg (missing keys keep their defaults).
func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		_derive()
		return
	for key in KEYS:
		if cfg.has_section_key(SECTION, key):
			var v: Variant = cfg.get_value(SECTION, key)
			if typeof(v) == typeof(get(key)) or (typeof(get(key)) == TYPE_FLOAT and typeof(v) == TYPE_INT):
				set(key, v)
	mouse_sensitivity = clampf(mouse_sensitivity, 0.0005, 0.008)
	fov = clampf(fov, 60.0, 100.0)
	quality = clampi(quality, 0, 2)
	_derive()


func save_settings() -> void:
	_save_left = -1.0
	var cfg := ConfigFile.new()
	for key in KEYS:
		cfg.set_value(SECTION, key, get(key))
	var err := cfg.save(PATH)
	if err != OK:
		push_warning("Settings: could not save %s (error %d)" % [PATH, err])


## Push volumes, mic device, window mode and vsync to the engine.
func apply() -> void:
	_apply_audio()
	_apply_mic()
	_apply_window()


## Change one setting by name, apply it, emit `changed` and save shortly after.
func set_value(key: String, value: Variant) -> void:
	set(key, value)
	match key:
		"master_volume", "music_volume", "sfx_volume", "voice_volume":
			_apply_audio()
		"mic_device":
			_apply_mic()
		"fullscreen", "vsync":
			_apply_window()
		"quality":
			_derive()
	changed.emit()
	_save_left = SAVE_DELAY


func quality_name() -> String:
	return QUALITY_NAMES[clampi(quality, 0, 2)]


func _derive() -> void:
	fog_quality = quality
	shadows = quality >= 1
	foliage_density = FOLIAGE[clampi(quality, 0, 2)]


func _apply_audio() -> void:
	_set_bus("Master", master_volume)
	_set_bus("Music", music_volume)
	_set_bus("SFX", sfx_volume)
	_set_bus("Voice", voice_volume)
	_set_bus("Walkie", voice_volume)


func _apply_mic() -> void:
	var devices := AudioServer.get_input_device_list()
	var want := mic_device if devices.has(mic_device) else "Default"
	if AudioServer.input_device != want and devices.has(want):
		AudioServer.input_device = want


func _apply_window() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var vs := DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED
	if DisplayServer.window_get_vsync_mode() != vs:
		DisplayServer.window_set_vsync_mode(vs)
	var mode := DisplayServer.window_get_mode()
	var is_full := mode in [DisplayServer.WINDOW_MODE_FULLSCREEN, DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN]
	if fullscreen and not is_full:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	elif not fullscreen and is_full:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)


func _set_bus(bus_name: String, linear: float) -> void:
	var i := AudioServer.get_bus_index(bus_name)
	if i < 0:
		return
	AudioServer.set_bus_volume_db(i, linear_to_db(maxf(linear, 0.0001)))
	AudioServer.set_bus_mute(i, linear <= 0.001)


func _ensure_bus(bus_name: String) -> void:
	if AudioServer.get_bus_index(bus_name) >= 0:
		return
	AudioServer.add_bus()
	var i := AudioServer.bus_count - 1
	AudioServer.set_bus_name(i, bus_name)
	AudioServer.set_bus_send(i, "Master")
