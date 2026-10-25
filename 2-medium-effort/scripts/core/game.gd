extends Node
## Global game state (autoload "Game"): world data, catalog, settings, references and signals.

signal notify(title: String, body: String, color: Color)
signal car_changed(car: Node)
signal region_changed(region_name: String)

const TITLE: String = "Verdant Ridge Festival"
const CAR_DIR: String = "res://data/cars/"

var world: WorldData
var cars: Array[CarDef] = []
var player: Node = null  # Car
var camera: Node = null
var sky: Node = null
var traffic: Node = null
var activities: Node = null
var streamer: Node = null
var hud: Node = null
var current_car_index: int = 0

# settings / assists
var settings: Dictionary = {
	"units_mph": false, "show_fps": true, "show_speed": true, "traffic_density": 0.6,
	"assist_tcs": true, "assist_esc": true, "assist_abs": true, "assist_steer": true,
	"manual_gears": false, "racing_line": false, "master_volume": 0.8,
}
var paint_overrides: Dictionary = {}  # car id -> {"color": Color, "finish": int, "rim": Color, "stripe": int}
var upgrades: Dictionary = {}  # car id -> {"engine": lvl, ...}
var tuning: Dictionary = {}  # car id -> {"final_drive": f, ...}
var bests: Dictionary = {}  # activity id -> float
var credits: int = 0
var prof: Dictionary = {}  # system -> max ms (QA profiling)


func prof_add(sys: String, t0_usec: int) -> void:
	var ms: float = (Time.get_ticks_usec() - t0_usec) / 1000.0
	if ms > prof.get(sys, 0.0):
		prof[sys] = ms


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	InputSetup.register()
	_load_cars()


func _load_cars() -> void:
	cars.clear()
	var ids: PackedStringArray = ["hatch", "sedan", "muscle", "coupe", "gt", "super", "rally", "suv", "pickup", "roadster"]
	for id in ids:
		var path: String = CAR_DIR + id + ".tres"
		if ResourceLoader.exists(path):
			var d: CarDef = load(path)
			cars.append(d)
		else:
			push_error("Missing car def " + path)


func find_car(name_or_index: String) -> int:
	if name_or_index.is_valid_int():
		var i: int = name_or_index.to_int()
		if i >= 1 and i <= cars.size():
			return i - 1
		if i == 0:
			return 0
		return -1
	var q: String = name_or_index.to_lower()
	for i in cars.size():
		if cars[i].id == q or cars[i].display_name.to_lower().contains(q):
			return i
	return -1


func get_upgrades(id: String) -> Dictionary:
	if not upgrades.has(id):
		upgrades[id] = {"engine": 0, "tires": 0, "suspension": 0, "brakes": 0, "weight": 0, "aero": 0}
	return upgrades[id]


func get_tuning(id: String) -> Dictionary:
	if not tuning.has(id):
		tuning[id] = {"final_drive": 1.0, "tire_pressure": 0.0, "camber": 0.0, "spring": 1.0, "damper": 1.0, "arb": 1.0, "aero": 1.0, "brake_bias": 0.0}
	return tuning[id]


func toast(title: String, body: String = "", color: Color = Color(1, 0.55, 0.1)) -> void:
	notify.emit(title, body, color)
