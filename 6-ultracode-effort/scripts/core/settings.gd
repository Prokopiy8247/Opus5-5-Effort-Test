extends Node
## Persistent user settings (user://settings.cfg). Autoload "Settings".

signal changed(key: String, value: Variant)

const PATH := "user://settings.cfg"

var values: Dictionary = {
	# display / HUD
	"units_mph": false,
	"show_fps": true,
	"show_telemetry": false,
	"show_minimap": true,
	"hud_visible": true,
	# assists
	"assist_tcs": true,
	"assist_stm": true,
	"assist_abs": true,
	"assist_steer": true,
	"auto_gearbox": true,
	"braking_line": false,
	# camera
	"camera_mode": 0,
	"camera_shake": 1.0,
	# world
	"traffic_density": 0.6,
	# audio
	"volume_master": 0.85,
	"volume_engine": 1.0,
	"volume_effects": 0.9,
	"volume_ambient": 0.7,
	# graphics: 0 low, 1 medium, 2 high, 3 ultra
	"quality": 2,
	"vsync": true,
	"fullscreen": false,
	"render_scale": 1.0,
}


## True when the game runs under a test harness (a test scene, a --script tool or a --qa mode): the master bus is
## muted so automated test runs are silent. A normal launch of the game keeps its sound. Never saved.
var test_run := false


func _ready() -> void:
	test_run = _detect_test_run()
	load_settings()
	_apply_display()
	if test_run:
		AudioServer.set_bus_mute(0, true)
		print("[settings] test run: master audio muted")


static func _detect_test_run() -> bool:
	for a: String in OS.get_cmdline_args():
		if a.ends_with(".tscn") or a.ends_with(".gd") or a == "-s" or a == "--script":
			return true
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--qa"):
			return true
	return false


func get_value(key: String, default: Variant = null) -> Variant:
	return values.get(key, default)


func set_value(key: String, value: Variant, save := true) -> void:
	values[key] = value
	if key in ["vsync", "fullscreen", "render_scale"]:
		_apply_display()
	changed.emit(key, value)
	if save:
		save_settings()


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	for key: String in values.keys():
		if cfg.has_section_key("settings", key):
			values[key] = cfg.get_value("settings", key)


## Test runs never write the player's settings (QA overrides such as --traffic=0 would stick to the next launch).
func save_settings() -> void:
	if test_run:
		return
	var cfg := ConfigFile.new()
	for key: String in values.keys():
		cfg.set_value("settings", key, values[key])
	cfg.save(PATH)


func _apply_display() -> void:
	if DisplayServer.get_name() == "headless":
		return
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if values["vsync"] else DisplayServer.VSYNC_DISABLED)
	var want_fs: bool = values["fullscreen"]
	var mode := DisplayServer.window_get_mode()
	if want_fs and mode != DisplayServer.WINDOW_MODE_FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	elif not want_fs and mode == DisplayServer.WINDOW_MODE_FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	var vp := get_viewport()
	if vp:
		vp.scaling_3d_scale = clampf(float(values["render_scale"]), 0.5, 1.0)
