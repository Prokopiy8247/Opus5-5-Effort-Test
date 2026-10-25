extends Node
## Global game state (autoload "Game"): car roster, settings, customisation, personal bests,
## references to the running systems, notifications and UI focus.

signal player_car_changed(car: CarController)
signal notified(title: String, body: String, kind: String)
signal settings_changed

const CARS_DIR := "res://data/cars/"

var main: Node
var world: Node
var player: CarController
var camera: CarCamera
var sky: Node
var traffic: Node
var activities: Node
var hud: Node
var audio: Node

var cars: Array[CarData] = []
var current_car := 0
var ui_focus := {}              ## open modal UIs block driving input
var headlights_manual := false

var settings := {
	"units_kmh": true,
	"show_fps": true,
	"show_telemetry": false,
	"camera_mode": 0,
	"traffic_density": 1.0,
	"master_volume": 0.8,
	"assists": {"abs": true, "tcs": true, "stm": true, "steer": true, "auto_gear": true, "brake_line": false},
	"minimap_rotate": true,
}
## per car id -> {"color": Color, "finish": int, "stripe": int, "stripe_color": Color, "rim": Color}
var paint := {}
## per car id -> {"engine": 0..3, "tires": 0..3, "suspension": 0..3, "brakes": 0..3, "weight": 0..3, "aero": 0..3}
var upgrades := {}
## per car id -> tuning dictionary (see CarController.tune)
var tuning := {}
## activity id -> best value
var personal_bests := {}
var credits := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	load_cars()


func load_cars() -> void:
	cars.clear()
	# ResourceLoader.list_directory also sees remapped resources inside an exported .pck
	var files := ResourceLoader.list_directory(CARS_DIR)
	if files.is_empty():
		push_error("No car data directory")
		return
	for fname in files:
		if fname.ends_with(".tres") or fname.ends_with(".res"):
			var d := load(CARS_DIR + fname) as CarData
			if d != null:
				cars.append(d)
	cars.sort_custom(func(a: CarData, b: CarData) -> bool: return a.order < b.order)
	current_car = maxi(car_index_by_name("SolanoCoupe"), 0)


func car_index_by_name(s: String) -> int:
	if s.is_valid_int():
		var i := int(s) - 1
		return i if i >= 0 and i < cars.size() else -1
	var low := s.to_lower()
	for i in cars.size():
		if String(cars[i].id).to_lower() == low or cars[i].display_name.to_lower() == low:
			return i
	for i in cars.size():
		if cars[i].display_name.to_lower().contains(low) or String(cars[i].id).to_lower().contains(low):
			return i
	return -1


func paint_for(id: StringName) -> Dictionary:
	if not paint.has(id):
		var d := cars[car_index_by_name(String(id))] if car_index_by_name(String(id)) >= 0 else null
		paint[id] = {"color": d.default_color if d else Color.RED, "finish": d.default_finish if d else 1,
				"stripe": 0, "stripe_color": Color(0.95, 0.95, 0.95), "rim": d.default_rim_color if d else Color.GRAY}
	return paint[id]


func upgrades_for(id: StringName) -> Dictionary:
	if not upgrades.has(id):
		upgrades[id] = {"engine": 0, "tires": 0, "suspension": 0, "brakes": 0, "weight": 0, "aero": 0}
	return upgrades[id]


func tuning_for(id: StringName) -> Dictionary:
	if not tuning.has(id):
		tuning[id] = {"final_drive": 1.0, "brake_bias": 0.0, "spring": 1.0, "damper": 1.0, "arb_f": 1.0, "arb_r": 1.0,
				"aero": 1.0, "tire_pressure": 0.0, "camber": 0.0}
	return tuning[id]


## Upgrade levels -> multipliers consumed by CarController.mods (data in res://data/upgrades/).
func mods_for(id: StringName) -> Dictionary:
	var u := upgrades_for(id)
	return Upgrades.multipliers(u)


## Festival credits earned from activities (persisted by SaveSystem).
func add_credits(n: int) -> void:
	credits += n


func notify(title: String, body: String = "", kind: String = "info") -> void:
	notified.emit(title, body, kind)


func set_ui_focus(key: String, on: bool) -> void:
	if on:
		ui_focus[key] = true
	else:
		ui_focus.erase(key)
	var any_modal := not ui_focus.is_empty()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func input_blocked() -> bool:
	return not ui_focus.is_empty()


func reset_player_to_road() -> void:
	if main != null and main.has_method("reset_player_to_road"):
		main.reset_player_to_road()


func assist(name: String) -> bool:
	return bool(settings.assists.get(name, false))


func set_assist(name: String, on: bool) -> void:
	settings.assists[name] = on
	apply_assists()
	settings_changed.emit()


func apply_assists() -> void:
	if player == null:
		return
	player.assist_abs = assist("abs")
	player.assist_tcs = assist("tcs")
	player.assist_stm = assist("stm")
	player.assist_steer = assist("steer")
	player.auto_gear = assist("auto_gear")


func speed_text(ms: float) -> String:
	if settings.units_kmh:
		return "%d" % roundi(ms * 3.6)
	return "%d" % roundi(ms * 2.23694)


func speed_unit() -> String:
	return "KM/H" if settings.units_kmh else "MPH"
