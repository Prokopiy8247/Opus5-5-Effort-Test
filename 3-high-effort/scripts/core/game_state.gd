extends Node
## Global game state (autoload "Game"): car roster, surfaces, assists, settings,
## personal bests, input map and save/load.

signal car_changed(car: Node)
signal notify(title: String, body: String, kind: String)
signal assists_changed
signal settings_changed

const TITLE := "Velora Roads"
const SAVE_PATH := "user://velora_save.json"
const CAR_DIR := "res://data/cars/"
const SURFACE_DIR := "res://data/surfaces/"

enum Surf { ASPHALT, CONCRETE, DIRT, GRAVEL, GRASS, SAND, SNOW, ROCK }

var cars: Array[CarSpec] = []
var surfaces: Array[SurfaceDef] = []

var assists := {
	"tcs": true,
	"stm": true,
	"abs": true,
	"steer": true,
	"auto": true,
}

var settings := {
	"units_mph": false,
	"show_fps": false,
	"show_speed": true,
	"traffic_density": 0.6,
	"camera": 0,
	"master_volume": 0.8,
	"minimap": true,
}

## Per-car customisation: car_id -> {color, finish, rim_color, stripe, upgrades:{}, tune:{}}
var car_custom := {}
var personal_bests := {}
var credits: int = 0
var current_car_index: int = 0

## Runtime references (not persisted)
var player: Node = null
var world: Node = null
var weather_grip: float = 1.0
var wetness: float = 0.0
var time_of_day: float = 9.5
var weather_name: String = "clear"
var pending_load := {}
## Lightweight per-system frame-time accounting (microseconds), read by QA perf runs.
var prof := {}


func prof_add(key: String, usec: int) -> void:
	prof[key] = int(prof.get(key, 0)) + usec


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_input()
	_load_surfaces()
	_load_cars()
	# "--fresh" (after --) ignores the save file; "--reset-save" deletes it
	if OS.get_cmdline_user_args().has("--reset-save"):
		reset_save()
	if not OS.get_cmdline_user_args().has("--fresh"):
		load_game()


# ------------------------------------------------------------------ data loading
func _load_cars() -> void:
	cars.clear()
	var files := ResourceLoader.list_directory(CAR_DIR)
	var names: Array[String] = []
	for f in files:
		if f.ends_with(".tres"):
			names.append(f)
	names.sort()
	for f in names:
		var spec := load(CAR_DIR + f) as CarSpec
		if spec != null and ResourceLoader.exists(spec.model_path):
			cars.append(spec)


func _load_surfaces() -> void:
	surfaces.clear()
	surfaces.resize(8)
	for f in ResourceLoader.list_directory(SURFACE_DIR):
		if not f.ends_with(".tres"):
			continue
		var s := load(SURFACE_DIR + f) as SurfaceDef
		if s != null and s.id >= 0 and s.id < surfaces.size():
			surfaces[s.id] = s
	for i in surfaces.size():
		if surfaces[i] == null:
			var d := SurfaceDef.new()
			d.id = i
			surfaces[i] = d


func surface(id: int) -> SurfaceDef:
	return surfaces[clampi(id, 0, surfaces.size() - 1)]


func car_index_by_name(q: String) -> int:
	q = q.to_lower().strip_edges()
	if q.is_valid_int():
		var i := q.to_int() - 1
		return i if i >= 0 and i < cars.size() else -1
	for i in cars.size():
		var c := cars[i]
		if c.id.to_lower() == q or c.display_name.to_lower().begins_with(q) or c.id.to_lower().begins_with(q):
			return i
	for i in cars.size():
		if cars[i].display_name.to_lower().contains(q):
			return i
	return -1


func custom_for(car_id: String) -> Dictionary:
	if not car_custom.has(car_id):
		car_custom[car_id] = {"upgrades": {}, "tune": {}}
	return car_custom[car_id]


func set_assist(key: String, on: bool) -> void:
	assists[key] = on
	assists_changed.emit()


func toast(title: String, body: String = "", kind: String = "info") -> void:
	notify.emit(title, body, kind)


func speed_text(mps: float) -> String:
	if settings.units_mph:
		return "%d" % roundi(mps * 2.23694)
	return "%d" % roundi(mps * 3.6)


func speed_unit() -> String:
	return "MPH" if settings.units_mph else "KM/H"


# ------------------------------------------------------------------ personal bests
## Returns true when value beats the stored best. higher_is_better selects ordering.
func submit_best(key: String, value: float, higher_is_better: bool) -> bool:
	var better := false
	if not personal_bests.has(key):
		better = true
	else:
		var old: float = personal_bests[key]
		better = value > old if higher_is_better else value < old
	if better:
		personal_bests[key] = value
		save_game()
	return better


func best(key: String, default_value: float = -1.0) -> float:
	return personal_bests.get(key, default_value)


# ------------------------------------------------------------------ save / load
func save_game() -> void:
	var data := {
		"version": 1,
		"car_index": current_car_index,
		"assists": assists,
		"settings": settings,
		"car_custom": _encode_custom(car_custom),
		"personal_bests": personal_bests,
		"credits": credits,
		"time_of_day": time_of_day,
		"weather": weather_name,
	}
	if is_instance_valid(player):
		var t: Transform3D = player.global_transform
		data["position"] = [t.origin.x, t.origin.y, t.origin.z]
		var f := -t.basis.z
		data["heading"] = atan2(f.x, f.z)
	var fa := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if fa == null:
		push_warning("Save failed: %s" % FileAccess.get_open_error())
		return
	fa.store_string(JSON.stringify(data, "\t"))


func load_game() -> bool:
	if not FileAccess.file_exists(SAVE_PATH):
		return false
	var txt := FileAccess.get_file_as_string(SAVE_PATH)
	var parsed: Variant = JSON.parse_string(txt)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("Save file unreadable, starting fresh")
		return false
	var d: Dictionary = parsed
	current_car_index = clampi(int(d.get("car_index", 0)), 0, maxi(cars.size() - 1, 0))
	for k in d.get("assists", {}):
		assists[k] = bool(d.assists[k])
	for k in d.get("settings", {}):
		settings[k] = d.settings[k]
	car_custom = _decode_custom(d.get("car_custom", {}))
	personal_bests = d.get("personal_bests", {})
	credits = int(d.get("credits", 0))
	time_of_day = float(d.get("time_of_day", time_of_day))
	weather_name = str(d.get("weather", weather_name))
	pending_load = d
	return true


func _encode_custom(src: Dictionary) -> Dictionary:
	var out := {}
	for k in src:
		var c: Dictionary = (src[k] as Dictionary).duplicate(true)
		for ck in ["color", "rim_color"]:
			if c.has(ck) and c[ck] is Color:
				c[ck] = (c[ck] as Color).to_html(false)
		out[k] = c
	return out


func _decode_custom(src: Dictionary) -> Dictionary:
	var out := {}
	for k in src:
		var c: Dictionary = src[k]
		for ck in ["color", "rim_color"]:
			if c.has(ck) and c[ck] is String:
				c[ck] = Color.html(c[ck])
		for nk in ["upgrades", "tune"]:
			if not c.has(nk):
				c[nk] = {}
		var ups: Dictionary = c.upgrades
		for uk in ups:
			ups[uk] = int(ups[uk])
		out[k] = c
	return out


func reset_save() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	car_custom = {}
	personal_bests = {}
	credits = 0
	pending_load = {}


# ------------------------------------------------------------------ input map
func _key(action: String, keys: Array, joy_buttons: Array = [], joy_axes: Array = []) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action, 0.15)
	for k in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = k
		InputMap.action_add_event(action, ev)
	for b in joy_buttons:
		var jb := InputEventJoypadButton.new()
		jb.button_index = b
		InputMap.action_add_event(action, jb)
	for a in joy_axes:
		var ja := InputEventJoypadMotion.new()
		ja.axis = a[0]
		ja.axis_value = a[1]
		InputMap.action_add_event(action, ja)


func _setup_input() -> void:
	# keyboard + mouse only (no gamepad support by request)
	_key("accelerate", [KEY_W, KEY_UP])
	_key("brake", [KEY_S, KEY_DOWN])
	_key("steer_left", [KEY_A, KEY_LEFT])
	_key("steer_right", [KEY_D, KEY_RIGHT])
	_key("handbrake", [KEY_SPACE])
	_key("horn", [KEY_H])
	_key("camera_next", [KEY_C])
	_key("look_back", [KEY_B])
	_key("look_left", [KEY_Z])
	_key("look_right", [KEY_X])
	_key("reset_car", [KEY_R])
	_key("headlights", [KEY_L])
	_key("shift_up", [KEY_E])
	_key("shift_down", [KEY_Q])
	_key("garage_menu", [KEY_TAB, KEY_F1])
	_key("debug_menu", [KEY_F2])
	_key("toggle_console", [KEY_QUOTELEFT])
	_key("map", [KEY_M])
	_key("photo_mode", [KEY_P])
	_key("screenshot", [KEY_F12])
	_key("waypoint", [KEY_G])
	_key("ui_toggle_hud", [KEY_F3])
