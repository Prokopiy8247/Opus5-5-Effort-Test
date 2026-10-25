extends SceneTree
## Generates the data-driven resources: surfaces, upgrades and car handling profiles (.tres).
## Run: godot --headless --path . --script res://tools/gen_data.gd

const SURFACES := [
	{"file": "asphalt", "kind": 0, "display_name": "Asphalt", "grip": 1.0, "wet_grip": 0.72, "rolling_resistance": 0.012,
		"tire_mults": [1.0, 1.06, 0.97, 0.9, 0.93], "paved": true, "particle_color": Color(0.85, 0.85, 0.85, 0.55), "skid_sound": &"squeal"},
	{"file": "concrete", "kind": 1, "display_name": "Concrete", "grip": 0.97, "wet_grip": 0.76, "rolling_resistance": 0.013,
		"tire_mults": [1.0, 1.05, 0.97, 0.9, 0.93], "paved": true, "particle_color": Color(0.85, 0.85, 0.85, 0.55), "skid_sound": &"squeal"},
	{"file": "dirt", "kind": 2, "display_name": "Dirt", "grip": 0.7, "wet_grip": 0.85, "rolling_resistance": 0.03, "bumpiness": 0.3,
		"tire_mults": [0.95, 0.86, 1.22, 1.18, 0.95], "paved": false, "particle_color": Color(0.55, 0.42, 0.3, 0.7), "particle_amount": 1.6, "skid_sound": &"dirt", "roll_sound": &"gravel"},
	{"file": "gravel", "kind": 3, "display_name": "Gravel", "grip": 0.64, "wet_grip": 0.9, "rolling_resistance": 0.035, "bumpiness": 0.5,
		"tire_mults": [0.95, 0.85, 1.25, 1.15, 0.95], "paved": false, "particle_color": Color(0.6, 0.57, 0.52, 0.7), "particle_amount": 1.5, "skid_sound": &"dirt", "roll_sound": &"gravel"},
	{"file": "grass", "kind": 4, "display_name": "Grass", "grip": 0.56, "wet_grip": 0.85, "rolling_resistance": 0.06, "sink_drag": 0.1, "bumpiness": 0.35,
		"tire_mults": [1.0, 0.9, 1.15, 1.22, 1.0], "paved": false, "particle_color": Color(0.35, 0.42, 0.2, 0.6), "particle_amount": 1.0, "skid_sound": &"dirt", "roll_sound": &"grass"},
	{"file": "sand", "kind": 5, "display_name": "Sand", "grip": 0.5, "wet_grip": 1.0, "rolling_resistance": 0.08, "sink_drag": 0.3, "bumpiness": 0.2,
		"tire_mults": [1.0, 0.85, 1.15, 1.3, 1.0], "paved": false, "particle_color": Color(0.85, 0.72, 0.5, 0.75), "particle_amount": 2.0, "skid_sound": &"dirt", "roll_sound": &"gravel"},
	{"file": "snow", "kind": 6, "display_name": "Snow", "grip": 0.42, "wet_grip": 1.0, "rolling_resistance": 0.05, "sink_drag": 0.15, "bumpiness": 0.15,
		"tire_mults": [1.0, 0.85, 1.25, 1.3, 1.0], "paved": false, "particle_color": Color(0.95, 0.96, 1.0, 0.8), "particle_amount": 1.8, "skid_sound": &"dirt", "roll_sound": &"grass"},
	{"file": "rock", "kind": 7, "display_name": "Rock", "grip": 0.8, "wet_grip": 0.8, "rolling_resistance": 0.02, "bumpiness": 0.6,
		"tire_mults": [1.0, 1.0, 1.1, 1.1, 1.0], "paved": false, "particle_color": Color(0.6, 0.58, 0.55, 0.6), "particle_amount": 0.8, "skid_sound": &"squeal", "roll_sound": &"gravel"},
]

const UPGRADES := {
	"engine": [{}, {"power": 1.08, "top": 1.025}, {"power": 1.17, "top": 1.05}, {"power": 1.28, "top": 1.08}],
	"tires": [{}, {"grip": 1.04}, {"grip": 1.08}, {"grip": 1.13}],
	"suspension": [{}, {"susp": 1.1}, {"susp": 1.2}, {"susp": 1.32}],
	"brakes": [{}, {"brake": 1.1}, {"brake": 1.2}, {"brake": 1.32}],
	"weight": [{}, {"mass": 0.96}, {"mass": 0.92}, {"mass": 0.88}],
	"aero": [{}, {"aero": 1.35}, {"aero": 1.7}, {"aero": 2.1}],
}
const UPGRADE_DESC := {
	"engine": "Intake, exhaust and ECU work: more power at every rpm.",
	"tires": "Stickier compounds: more grip on every surface.",
	"suspension": "Stiffer springs, dampers and anti-roll bars: less roll, sharper response.",
	"brakes": "Bigger discs and better pads: more stopping torque.",
	"weight": "Lighter panels and stripped trim: less mass to move.",
	"aero": "Splitter and wing: more downforce at speed.",
}

const CARS := preload("res://tools/car_handling.gd").CARS

const TRAFFIC := [
	{"id": &"compact", "display_name": "City car", "model_path": "res://assets/imported/traffic/TrafficCompact.glb", "mass": 1050.0,
		"speed_factor": 0.95, "accel": 2.0, "decel": 4.5, "length": 3.7, "class_weights": [2.0, 3.0, 3.0, 3.5, 0.6, 0.3]},
	{"id": &"estate", "display_name": "Estate", "model_path": "res://assets/imported/traffic/TrafficEstate.glb", "mass": 1450.0,
		"speed_factor": 1.0, "accel": 2.2, "decel": 4.5, "length": 4.8, "class_weights": [3.0, 3.0, 2.5, 2.0, 0.8, 0.4]},
	{"id": &"van", "display_name": "Delivery van", "model_path": "res://assets/imported/traffic/TrafficVan.glb", "mass": 2400.0,
		"speed_factor": 0.92, "accel": 1.6, "decel": 4.0, "length": 5.4, "class_weights": [2.0, 1.5, 1.0, 1.5, 0.3, 0.1]},
	{"id": &"lorry", "display_name": "Box lorry", "model_path": "res://assets/imported/traffic/TrafficLorry.glb", "mass": 9000.0,
		"speed_factor": 0.8, "accel": 1.0, "decel": 3.2, "length": 7.8, "class_weights": [2.0, 1.0, 0.4, 0.3, 0.0, 0.0]},
	{"id": &"bus", "display_name": "Coach", "model_path": "res://assets/imported/traffic/TrafficBus.glb", "mass": 12000.0,
		"speed_factor": 0.82, "accel": 0.9, "decel": 3.0, "length": 11.2, "class_weights": [1.0, 0.8, 0.4, 0.2, 0.0, 0.0]},
	{"id": &"tractor", "display_name": "Farm tractor", "model_path": "res://assets/imported/traffic/TrafficTractor.glb", "mass": 4500.0,
		"speed_factor": 0.4, "accel": 0.8, "decel": 3.0, "length": 4.2, "class_weights": [0.0, 0.25, 0.0, 0.6, 1.5, 2.0], "farm_only": true},
]
const TRAFFIC_COLORS := [Color(0.85, 0.85, 0.87), Color(0.1, 0.1, 0.12), Color(0.55, 0.05, 0.06), Color(0.08, 0.2, 0.55),
	Color(0.35, 0.36, 0.38), Color(0.12, 0.35, 0.18), Color(0.9, 0.8, 0.55), Color(0.7, 0.12, 0.08), Color(0.95, 0.95, 0.94)]

const WEATHER := [
	{"id": &"clear", "display_name": "Clear", "cloud_coverage": 0.25, "cloud_darkness": 0.0, "fog_density": 0.00012,
		"fog_height_density": 0.0, "volumetric_fog": 0.0, "rain": 0.0, "wetness": 0.0, "sun_energy": 1.0, "ambient": 1.0,
		"wind": 2.0, "grip": 1.0, "weight": 4.0},
	{"id": &"cloudy", "display_name": "Cloudy", "cloud_coverage": 0.72, "cloud_darkness": 0.35, "fog_density": 0.00025,
		"fog_height_density": 0.0, "volumetric_fog": 0.0, "rain": 0.0, "wetness": 0.0, "sun_energy": 0.72, "ambient": 0.9,
		"wind": 4.0, "grip": 1.0, "weight": 2.5},
	{"id": &"rain", "display_name": "Rain", "cloud_coverage": 0.95, "cloud_darkness": 0.75, "fog_density": 0.0007,
		"fog_height_density": 0.002, "volumetric_fog": 0.0, "rain": 0.7, "wetness": 1.0, "sun_energy": 0.35, "ambient": 0.65,
		"wind": 6.0, "grip": 0.97, "weight": 1.5},
	{"id": &"fog", "display_name": "Fog", "cloud_coverage": 0.65, "cloud_darkness": 0.35, "fog_density": 0.0042,
		"fog_height_density": 0.015, "volumetric_fog": 0.0, "rain": 0.0, "wetness": 0.35, "sun_energy": 0.45, "ambient": 0.8,
		"wind": 1.0, "grip": 1.0, "weight": 1.0},
	{"id": &"storm", "display_name": "Storm", "cloud_coverage": 1.0, "cloud_darkness": 0.95, "fog_density": 0.0013,
		"fog_height_density": 0.003, "volumetric_fog": 0.0, "rain": 1.0, "lightning": true, "wetness": 1.0, "sun_energy": 0.18,
		"ambient": 0.45, "wind": 11.0, "grip": 0.93, "weight": 0.8},
]


func _init() -> void:
	DirAccess.make_dir_recursive_absolute("res://data/surfaces")
	DirAccess.make_dir_recursive_absolute("res://data/upgrades")
	DirAccess.make_dir_recursive_absolute("res://data/cars")
	DirAccess.make_dir_recursive_absolute("res://data/traffic")
	for t: Dictionary in TRAFFIC:
		var tt := TrafficType.new()
		for k: String in t:
			var v: Variant = t[k]
			if k == "class_weights":
				v = PackedFloat32Array(v)
			tt.set(k, v)
		var cols: Array[Color] = []
		for col: Color in TRAFFIC_COLORS:
			cols.append(col)
		if String(t.id) == "tractor":
			cols = [Color(0.12, 0.45, 0.12), Color(0.7, 0.08, 0.05), Color(0.15, 0.25, 0.6)]
		elif String(t.id) in ["lorry", "bus"]:
			cols = [Color(0.95, 0.95, 0.94), Color(0.08, 0.3, 0.6), Color(0.85, 0.5, 0.05), Color(0.7, 0.1, 0.1)]
		tt.colors = cols
		_save(tt, "res://data/traffic/%s.tres" % String(t.id))
	DirAccess.make_dir_recursive_absolute("res://data/weather")
	for w: Dictionary in WEATHER:
		var wp := WeatherPreset.new()
		for k: String in w:
			wp.set(k, w[k])
		_save(wp, "res://data/weather/%s.tres" % String(w.id))
	for s: Dictionary in SURFACES:
		var r := SurfaceData.new()
		for k: String in s:
			if k == "file":
				continue
			var v: Variant = s[k]
			if k == "tire_mults":
				v = PackedFloat32Array(v)
			r.set(k, v)
		_save(r, "res://data/surfaces/%s.tres" % s.file)
	var names := ["Stock", "Street", "Sport", "Race"]
	for cat: String in UPGRADES:
		var levels: Array = UPGRADES[cat]
		for lvl in levels.size():
			var u := UpgradeData.new()
			u.category = cat
			u.level = lvl
			u.display_name = "%s %s" % [names[lvl], cat.capitalize()]
			u.description = UPGRADE_DESC[cat]
			u.cost = [0, 8000, 20000, 45000][lvl]
			u.multipliers = levels[lvl]
			_save(u, "res://data/upgrades/%s_%d.tres" % [cat, lvl])
	for c: Dictionary in CARS:
		var d := CarData.new()
		for k: String in c:
			var v: Variant = c[k]
			if k == "torque_curve":
				var arr := PackedVector2Array()
				for p: Array in v:
					arr.append(Vector2(p[0], p[1]))
				v = arr
			elif k == "gear_ratios":
				v = PackedFloat32Array(v)
			d.set(k, v)
		_save(d, "res://data/cars/%s.tres" % String(c.id).to_snake_case())
	quit(0)


func _save(r: Resource, path: String) -> void:
	var err := ResourceSaver.save(r, path)
	print(path, " -> ", error_string(err))
