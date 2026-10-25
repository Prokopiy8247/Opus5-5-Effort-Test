extends Node
## Global game state (autoload "Game"): references to the running systems, car catalogue,
## assists/settings, UI focus, and command-line QA options.

signal car_changed(car: CarController)
signal notify(title: String, body: String, kind: String)
signal region_entered(region_name: String)
signal settings_changed

const CAR_DIR := "res://data/cars/"

var main: Node = null
var world: Node = null
var player_car: CarController = null
var camera_rig: Node = null
var traffic: Node = null
var environment: Node = null
var activities: Node = null
var hud: Node = null

var car_defs: Array[CarDefinition] = []
var current_car_index: int = 0
var paint_color: Color = Color(0.8, 0.1, 0.1)
var paint_finish: int = 1
var assists: Dictionary = {"tcs": true, "esc": true, "abs": true, "steer": true, "auto_gear": true, "line": false}
var settings: Dictionary = {"units_mph": false, "show_fps": false, "show_speed": true, "traffic_density": 0.6,
	"master_volume": 0.8, "camera_shake": true, "minimap_rotate": true}
var ui_focus: Dictionary = {}
var prof: Dictionary = {}          # name -> [total_us, max_us, calls]
var _prof_t: Dictionary = {}
var qa_args: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_parse_args()
	_register_shader_globals()
	load_car_catalogue()


func _register_shader_globals() -> void:
	var defs := [
		["wetness", RenderingServer.GLOBAL_VAR_TYPE_FLOAT, 0.0],
		["wind_strength", RenderingServer.GLOBAL_VAR_TYPE_FLOAT, 0.3],
		["night_amount", RenderingServer.GLOBAL_VAR_TYPE_FLOAT, 0.0],
		["snow_line", RenderingServer.GLOBAL_VAR_TYPE_FLOAT, 420.0],
		["player_pos", RenderingServer.GLOBAL_VAR_TYPE_VEC3, Vector3.ZERO],
	]
	for d in defs:
		RenderingServer.global_shader_parameter_add(d[0], d[1], d[2])


func _parse_args() -> void:
	for a in OS.get_cmdline_user_args():
		var s := String(a)
		if s.begins_with("--"):
			s = s.substr(2)
		var kv := s.split("=", true, 1)
		qa_args[kv[0]] = kv[1] if kv.size() > 1 else "1"


func load_car_catalogue() -> void:
	car_defs.clear()
	var dir := DirAccess.open(CAR_DIR)
	if dir == null:
		return
	var files: Array[String] = []
	for f in dir.get_files():
		var fname := f.trim_suffix(".remap")
		if fname.ends_with(".tres"):
			files.append(fname)
	files.sort()
	for f in files:
		var def := load(CAR_DIR + f) as CarDefinition
		if def != null:
			car_defs.append(def)


func find_car_index(query: String) -> int:
	if query.is_valid_int():
		var i := int(query) - 1
		return i if i >= 0 and i < car_defs.size() else -1
	var q := query.to_lower()
	for i in car_defs.size():
		if String(car_defs[i].id).to_lower() == q or car_defs[i].display_name.to_lower().contains(q):
			return i
	return -1


func set_ui_focus(owner_name: String, blocks: bool) -> void:
	if blocks:
		ui_focus[owner_name] = true
	else:
		ui_focus.erase(owner_name)


func ui_blocks_driving() -> bool:
	return not ui_focus.is_empty()


func show_notification(title: String, body: String = "", kind: String = "info") -> void:
	notify.emit(title, body, kind)


func speed_text(kmh: float) -> String:
	if settings.get("units_mph", false):
		return "%d" % int(round(kmh * 0.621371))
	return "%d" % int(round(kmh))


func speed_unit() -> String:
	return "MPH" if settings.get("units_mph", false) else "KM/H"


func prof_begin(n: String) -> void:
	_prof_t[n] = Time.get_ticks_usec()


func prof_end(n: String) -> void:
	var dt := Time.get_ticks_usec() - int(_prof_t.get(n, Time.get_ticks_usec()))
	var e: Array = prof.get(n, [0, 0, 0])
	e[0] += dt
	e[1] = maxi(e[1], dt)
	e[2] += 1
	prof[n] = e


func prof_report() -> String:
	var lines: Array[String] = []
	for k in prof:
		var e: Array = prof[k]
		lines.append("%s total=%.0fms max=%.1fms avg=%.2fms calls=%d" % [k, e[0] / 1000.0, e[1] / 1000.0, e[0] / 1000.0 / maxf(e[2], 1), e[2]])
	return "
".join(lines)
