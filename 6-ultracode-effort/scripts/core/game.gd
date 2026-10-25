extends Node
## Global services + gameplay API. Autoload "Game".
## Console, menus and activities talk to the game ONLY through this API; subsystems register
## themselves here (main, world, env, traffic, activities, hud, camera_rig).
##
## Subsystem contracts (duck-typed):
##   world: height_at(x, z) -> float; surface_at(pos) -> SurfaceData; region_at(pos) -> String;
##          nearest_road_point(pos) -> Dictionary {position, forward, road_id, s};
##          get_teleport_targets() -> Array[Dictionary {name, kind, position, forward}]
##   env:   set_time_of_day(h); get_time_of_day() -> float; set_time_scale(s); set_weather(id, instant);
##          get_weather() -> StringName; get_weather_ids() -> Array[StringName]; is_night() -> bool
##   traffic: set_density(v); get_density() -> float (user setting); set_density_cap(v); effective_density();
##            active_count() -> int; obstacles_near(pos, radius)
##   activities: get_ai_cars(); respawn_override(pos); get_session_id(); cancel_session(reason)
##   main:  spawn_player_car(index, keep_transform) ; respawn_on_road() ; flip_reset() ; teleport_to(target_dict)

signal car_spawned(car: CarController)
signal notification(title: String, body: String, kind: StringName)
signal region_changed(region_name: String)
signal weather_changed(weather_id: StringName)
signal paint_changed()
signal stats_changed()
signal activity_finished(activity_id: String, result: Dictionary)
signal ui_overlay_changed(open: bool)
signal activity_update(info: Dictionary)
signal waypoint_changed(pos: Vector3)
signal photo_mode_changed(on: bool)

const GAME_TITLE := "Sunward Roads"
const FESTIVAL_NAME := "Sunward Festival"
## Group for nodes whose visuals follow the time of day / weather (lights, lamp pool, windows, traffic
## lights). They join it in _ready; photo mode runs them for a moment (PROCESS_MODE_ALWAYS, ~0.6 s) after
## changing time or weather while the tree is paused, then restores each node's own process_mode.
const TIME_REACTIVE_GROUP := &"sunward_time_reactive"
const CAR_IDS: Array[String] = [
	"kestrel_r4", "aurelia_sedan", "brute_68", "sora_s2", "castellan_gt",
	"vortex_x", "granite_rally", "ridgeback_sx", "hauler_2500", "lark_roadster",
]
const PAINT_COLORS := {
	"red": Color(0.62, 0.06, 0.05), "blue": Color(0.05, 0.18, 0.55), "yellow": Color(0.95, 0.75, 0.05),
	"green": Color(0.08, 0.35, 0.15), "white": Color(0.92, 0.92, 0.9), "black": Color(0.02, 0.02, 0.025),
	"silver": Color(0.62, 0.63, 0.65), "orange": Color(0.92, 0.35, 0.05), "purple": Color(0.32, 0.08, 0.45),
	"pink": Color(0.95, 0.4, 0.62), "teal": Color(0.05, 0.5, 0.5), "mint": Color(0.62, 0.85, 0.77),
	"gold": Color(0.75, 0.58, 0.2), "brown": Color(0.3, 0.17, 0.08), "grey": Color(0.25, 0.26, 0.28),
}

var main: Node
var world: Node
var env: Node
var traffic: Node
var activities: Node
var hud: Node
var camera_rig: Node
var player_car: CarController

var car_catalog: Array[CarData] = []
var current_car_index: int = 0
## Per-car customisation: car_id -> {color, finish, stripes, stripe_color, rim_color}
var paints: Dictionary = {}
## Per-car upgrades: car_id -> {engine, tires, suspension, brakes, weight, aero} (levels 0..3)
var upgrades: Dictionary = {}
## Per-car tuning: car_id -> {final_drive, tire_pressure, camber, spring_f, spring_r, arb_f, arb_r, aero_f, aero_r, brake_bias}
var tuning: Dictionary = {}
var personal_bests: Dictionary = {}
var credits: int = 0
var discovered: Dictionary = {}
var overlays_open: int = 0
var photo_mode: bool = false:
	set(v):
		photo_mode = v
		photo_mode_changed.emit(v)
## Map waypoint (Vector3.INF when none).
var waypoint: Vector3 = Vector3.INF
## Who set the waypoint: &"" = the player (map / console), &"activity" = a running event steering the GPS
## to its next gate. The GPS only announces arrival and clears player waypoints.
var waypoint_owner: StringName = &""
var benchmark_mode: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load_catalog()


func _load_catalog() -> void:
	car_catalog.clear()
	for id in CAR_IDS:
		var path := "res://data/cars/%s.tres" % id
		if ResourceLoader.exists(path):
			var d: CarData = load(path)
			if d != null:
				car_catalog.append(d)


func get_car_catalog() -> Array[CarData]:
	return car_catalog


func find_car_index(key: String) -> int:
	if key.is_valid_int():
		var i := key.to_int()
		# Accept 1-based (console) indices.
		if i >= 1 and i <= car_catalog.size():
			return i - 1
		return -1
	var k := key.to_lower()
	for i in car_catalog.size():
		var d := car_catalog[i]
		if d.id == k or d.display_name.to_lower() == k or d.display_name.to_lower().begins_with(k) or d.id.begins_with(k):
			return i
	return -1


func current_car_data() -> CarData:
	if car_catalog.is_empty():
		return null
	return car_catalog[clampi(current_car_index, 0, car_catalog.size() - 1)]


# ----------------------------------------------------------------- car control API

func spawn_car(index: int, keep_transform := true) -> bool:
	if index < 0 or index >= car_catalog.size() or main == null:
		return false
	current_car_index = index
	main.spawn_player_car(index, keep_transform)
	return true


func respawn() -> void:
	if main:
		main.respawn_on_road()


func flip_reset() -> void:
	if main:
		main.flip_reset()


func repair() -> void:
	if player_car:
		player_car.repair()
		notify("Repaired", "Car fully repaired", &"info")


func teleport(target: String) -> bool:
	if world == null or main == null:
		return false
	var t := target.to_lower()
	for d: Dictionary in world.get_teleport_targets():
		var n: String = String(d["name"]).to_lower()
		if n == t or n.begins_with(t) or n.replace(" ", "_") == t:
			main.teleport_to(d)
			return true
	return false


func get_teleport_targets() -> Array:
	return world.get_teleport_targets() if world else []


# ----------------------------------------------------------------- world API

func set_time_of_day(hour: float) -> void:
	if env:
		env.set_time_of_day(hour)


func get_time_of_day() -> float:
	return env.get_time_of_day() if env else 12.0


func get_time_scale() -> float:
	return float(env.get("time_scale")) if env and "time_scale" in env else 1.0


func set_time_scale(s: float) -> void:
	if env:
		env.set_time_scale(s)


func set_weather(id: String, instant := false) -> bool:
	if env == null:
		return false
	var sid := StringName(id.to_lower())
	if not sid in env.get_weather_ids():
		return false
	env.set_weather(sid, instant)
	weather_changed.emit(sid)
	return true


func get_weather() -> StringName:
	return env.get_weather() if env else &"clear"


func get_weather_ids() -> Array:
	return env.get_weather_ids() if env else []


func set_traffic_density(v: float) -> void:
	Settings.set_value("traffic_density", clampf(v, 0.0, 1.0))
	if traffic:
		traffic.set_density(clampf(v, 0.0, 1.0))


func get_traffic_density() -> float:
	return traffic.get_density() if traffic else float(Settings.get_value("traffic_density", 0.6))


# ----------------------------------------------------------------- assists

const ASSISTS := {
	"tcs": "assist_tcs", "traction": "assist_tcs", "stm": "assist_stm", "stability": "assist_stm",
	"abs": "assist_abs", "steering": "assist_steer", "steer": "assist_steer",
	"auto": "auto_gearbox", "gearbox": "auto_gearbox", "line": "braking_line", "brakingline": "braking_line",
}


func set_assist(name: String, on: bool) -> bool:
	var key: String = ASSISTS.get(name.to_lower(), "")
	if key == "":
		return false
	Settings.set_value(key, on)
	apply_assists_to(player_car)
	return true


func get_assists() -> Dictionary:
	return {
		"tcs": Settings.get_value("assist_tcs"), "stm": Settings.get_value("assist_stm"),
		"abs": Settings.get_value("assist_abs"), "steering": Settings.get_value("assist_steer"),
		"auto": Settings.get_value("auto_gearbox"), "line": Settings.get_value("braking_line"),
	}


func apply_assists_to(car: CarController) -> void:
	if car == null:
		return
	car.assist_tcs = Settings.get_value("assist_tcs")
	car.assist_stm = Settings.get_value("assist_stm")
	car.assist_abs = Settings.get_value("assist_abs")
	car.assist_steer = Settings.get_value("assist_steer")
	car.auto_gearbox = Settings.get_value("auto_gearbox")


# ----------------------------------------------------------------- paint / upgrades / tuning

func get_paint(car_id: String) -> Dictionary:
	if not paints.has(car_id):
		var d := _data_for(car_id)
		paints[car_id] = {
			"color": d.default_color if d else Color.RED,
			"finish": int(d.default_finish) if d else 0,
			"stripes": 0,
			"stripe_color": Color(0.95, 0.95, 0.95),
			"rim_color": Color(-1, -1, -1),
		}
	return paints[car_id]


func set_paint(color: Color, finish := -1, stripes := -1, stripe_color := Color(-1, -1, -1)) -> void:
	var d := current_car_data()
	if d == null:
		return
	var p := get_paint(d.id)
	p["color"] = color
	if finish >= 0:
		p["finish"] = finish
	if stripes >= 0:
		p["stripes"] = stripes
	if stripe_color.r >= 0.0:
		p["stripe_color"] = stripe_color
	if player_car:
		CarFactory.apply_paint(player_car, p)
	paint_changed.emit()


func set_rim_color(color: Color) -> void:
	var d := current_car_data()
	if d == null:
		return
	get_paint(d.id)["rim_color"] = color
	if player_car:
		CarFactory.apply_paint(player_car, get_paint(d.id))
	paint_changed.emit()


func get_upgrades(car_id: String) -> Dictionary:
	if not upgrades.has(car_id):
		upgrades[car_id] = {"engine": 0, "tires": 0, "suspension": 0, "brakes": 0, "weight": 0, "aero": 0}
	return upgrades[car_id]


func get_tuning(car_id: String) -> Dictionary:
	if not tuning.has(car_id):
		tuning[car_id] = {}
	return tuning[car_id]


## Returns the effective (upgraded + tuned) handling data for a car.
func effective_car_data(index: int) -> CarData:
	var base := car_catalog[index]
	return Tuning.build_effective(base, get_upgrades(base.id), get_tuning(base.id))


func _data_for(car_id: String) -> CarData:
	for d in car_catalog:
		if d.id == car_id:
			return d
	return null


# ----------------------------------------------------------------- misc

## owner_id: see waypoint_owner (activities pass &"activity").
func set_waypoint(pos: Vector3, owner_id: StringName = &"") -> void:
	waypoint = pos
	waypoint_owner = owner_id
	waypoint_changed.emit(pos)


func clear_waypoint() -> void:
	waypoint = Vector3.INF
	waypoint_owner = &""
	waypoint_changed.emit(waypoint)


func notify(title: String, body := "", kind: StringName = &"info") -> void:
	notification.emit(title, body, kind)


func record_personal_best(key: String, value: float, higher_is_better := true) -> bool:
	var old: Variant = personal_bests.get(key)
	var better: bool = old == null or (value > float(old) if higher_is_better else value < float(old))
	if better:
		personal_bests[key] = value
	return better


func push_overlay(open: bool) -> void:
	overlays_open = maxi(overlays_open + (1 if open else -1), 0)
	ui_overlay_changed.emit(overlays_open > 0)


func is_overlay_open() -> bool:
	return overlays_open > 0
