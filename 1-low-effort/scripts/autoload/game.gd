extends Node
## Global services: input map, car database, settings, save/load and notifications.

signal notify(text: String, kind: String)
signal car_changed(car: Car)

const SAVE_PATH := "user://savegame.json"
const TITLE := "Horizon Drift: Four Valleys"

var cars: Array[CarSpec] = []
var main: Node = null
var settings := {"units_kmh": true, "show_fps": true, "show_speed": true, "traffic_density": 0.6, "camera": 0, "volume": 0.8}
var personal_bests: Dictionary = {}
var paint_state: Dictionary = {}    # car id -> {color, finish}
var upgrade_state: Dictionary = {}  # car id -> upgrades dict

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_input()
	for f in DirAccess.get_files_at("res://data/cars"):
		var fn := f.trim_suffix(".remap")
		if fn.ends_with(".tres"):
			cars.append(load("res://data/cars/" + fn) as CarSpec)
	cars.sort_custom(func(a: CarSpec, b: CarSpec) -> bool: return a.id < b.id)

func _key(action: String, keys: Array) -> void:
	if not InputMap.has_action(action): InputMap.add_action(action, 0.15)
	for k in keys:
		var e := InputEventKey.new(); e.physical_keycode = k; InputMap.action_add_event(action, e)

func _setup_input() -> void:
	# keyboard + mouse only (no gamepad support by request)
	_key("throttle", [KEY_W, KEY_UP])
	_key("brake", [KEY_S, KEY_DOWN])
	_key("steer_left", [KEY_A, KEY_LEFT])
	_key("steer_right", [KEY_D, KEY_RIGHT])
	_key("handbrake", [KEY_SPACE])
	_key("shift_up", [KEY_E])
	_key("shift_down", [KEY_Q])
	_key("camera", [KEY_C])
	_key("look_back", [KEY_B])
	_key("horn", [KEY_H])
	_key("lights", [KEY_L])
	_key("reset_car", [KEY_R])
	_key("garage", [KEY_F1, KEY_TAB])
	_key("debug_menu", [KEY_F2])
	_key("photo_mode", [KEY_P])
	_key("screenshot", [KEY_F12])
	_key("map", [KEY_M])
	_key("console", [KEY_QUOTELEFT])
	_key("look_left", [KEY_Z])
	_key("look_right", [KEY_X])

func find_car(q: String) -> int:
	if q.is_valid_int():
		var i := q.to_int() - 1
		return i if i >= 0 and i < cars.size() else -1
	q = q.to_lower()
	for i in cars.size():
		if cars[i].id.to_lower().contains(q) or cars[i].display_name.to_lower().contains(q): return i
	return -1

func toast(text: String, kind: String = "info") -> void:
	notify.emit(text, kind)

func record_best(key: String, value: float, higher_is_better: bool = true) -> bool:
	var old: Variant = personal_bests.get(key)
	if old == null or (higher_is_better and value > old) or (not higher_is_better and value < old):
		personal_bests[key] = value
		return true
	return false

func save_game(state: Dictionary) -> void:
	var data := {"version": 1, "settings": settings, "bests": personal_bests, "paint": {}, "upgrades": upgrade_state, "state": state}
	for k in paint_state.keys():
		var p: Dictionary = paint_state[k]
		data.paint[k] = {"color": (p.color as Color).to_html(), "finish": p.finish}
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null: return
	f.store_string(JSON.stringify(data, "  "))

func load_game() -> Dictionary:
	if not FileAccess.file_exists(SAVE_PATH): return {}
	var txt := FileAccess.get_file_as_string(SAVE_PATH)
	var d: Variant = JSON.parse_string(txt)
	if typeof(d) != TYPE_DICTIONARY: return {}
	var dd: Dictionary = d
	if dd.has("settings"): settings.merge(dd.settings, true)
	personal_bests = dd.get("bests", {})
	upgrade_state = dd.get("upgrades", {})
	paint_state.clear()
	var pd: Dictionary = dd.get("paint", {})
	for k in pd.keys():
		paint_state[k] = {"color": Color.html(pd[k].color), "finish": int(pd[k].finish)}
	return dd.get("state", {})
