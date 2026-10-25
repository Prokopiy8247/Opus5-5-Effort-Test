extends SceneTree
## Generates the data-driven Resources (cars, surfaces, weather presets, upgrades).
## Run: Godot_console --headless --path . --script res://tools/make_data.gd

const CARS := [
	{
		"id": "kestrel_gti", "name": "Kestrel GTi", "maker": "Kestrel", "year": 2021, "style": "Hot hatch",
		"cls": "B", "pi": 655, "desc": "Feisty front-drive hatch. Light, eager and happiest on twisty B-roads.",
		"model": "kestrel_gti", "mass": 1190.0, "com": Vector3(0, 0.52, -0.25),
		"torque": 340.0, "curve": [Vector2(1000, 0.5), Vector2(2000, 0.95), Vector2(4500, 1.0), Vector2(6000, 0.86), Vector2(6800, 0.72)],
		"idle": 900.0, "redline": 6900.0, "cyl": 4, "layout": "I4 turbo", "turbo": true, "pitch": 1.05, "rough": 0.25,
		"drive": CarSpec.Drivetrain.FWD, "gears": [3.4, 2.15, 1.55, 1.2, 0.98, 0.82], "top": 245.0,
		"tire": CarSpec.TireType.SPORT, "grip": 1.08, "rear_bias": 1.0, "peak_slip": 8.0, "slide": 0.8,
		"rest": 0.16, "hzf": 1.75, "hzr": 1.9, "damp": 0.42, "arbf": 11000.0, "arbr": 13000.0,
		"brake": 12500.0, "bias": 0.64, "hb": 5200.0, "lock": 35.0, "df": 0.25, "bal": 0.5,
		"paint": Color(0.82, 0.07, 0.05), "finish": "gloss", "rim": Color(0.12, 0.12, 0.13),
		"stats": [6.2, 7.3, 6.4, 5.5, 6.8, 3.5], "hp": 245,
	},
	{
		"id": "arden_saloon", "name": "Arden S4 Saloon", "maker": "Arden", "year": 2018, "style": "Family saloon",
		"cls": "D", "pi": 470, "desc": "A comfortable four-door commuter. Forgiving, quiet and surprisingly willing.",
		"model": "arden_saloon", "mass": 1430.0, "com": Vector3(0, 0.55, -0.2),
		"torque": 250.0, "curve": [Vector2(1000, 0.6), Vector2(2500, 0.95), Vector2(4000, 1.0), Vector2(5600, 0.85), Vector2(6200, 0.7)],
		"idle": 800.0, "redline": 6200.0, "cyl": 4, "layout": "I4", "turbo": false, "pitch": 0.95, "rough": 0.15,
		"drive": CarSpec.Drivetrain.FWD, "gears": [3.6, 2.1, 1.4, 1.05, 0.84, 0.7], "top": 205.0,
		"tire": CarSpec.TireType.ROAD, "grip": 0.96, "rear_bias": 1.02, "peak_slip": 7.0, "slide": 0.78,
		"rest": 0.18, "hzf": 1.35, "hzr": 1.45, "damp": 0.36, "arbf": 8000.0, "arbr": 6000.0,
		"brake": 11000.0, "bias": 0.66, "hb": 4500.0, "lock": 36.0, "df": 0.05, "bal": 0.5,
		"paint": Color(0.18, 0.3, 0.5), "finish": "metallic", "rim": Color(0.72, 0.73, 0.75),
		"stats": [4.8, 5.0, 4.2, 4.5, 5.2, 3.8], "hp": 165,
	},
	{
		"id": "brute_69", "name": "Brute 69", "maker": "Brute Motor Co.", "year": 1969, "style": "Muscle car",
		"cls": "B", "pi": 690, "desc": "Big-block bravado. Enormous torque, skinny tyres and a tail that wants to lead.",
		"model": "brute_69", "mass": 1640.0, "com": Vector3(0, 0.55, -0.15),
		"torque": 640.0, "curve": [Vector2(900, 0.62), Vector2(2200, 0.92), Vector2(3400, 1.0), Vector2(5000, 0.86), Vector2(5900, 0.7)],
		"idle": 750.0, "redline": 5900.0, "cyl": 8, "layout": "V8 big-block", "turbo": false, "pitch": 0.7, "rough": 0.7,
		"drive": CarSpec.Drivetrain.RWD, "gears": [2.6, 1.8, 1.3, 1.0], "top": 240.0,
		"tire": CarSpec.TireType.VINTAGE, "grip": 0.98, "rear_bias": 0.93, "peak_slip": 7.5, "slide": 0.8,
		"rest": 0.2, "hzf": 1.3, "hzr": 1.4, "damp": 0.3, "arbf": 9000.0, "arbr": 4000.0,
		"brake": 11000.0, "bias": 0.62, "hb": 6000.0, "lock": 34.0, "df": 0.0, "bal": 0.5,
		"paint": Color(0.95, 0.55, 0.05), "finish": "gloss", "rim": Color(0.8, 0.8, 0.82),
		"stats": [6.8, 4.6, 7.4, 5.0, 4.5, 3.0], "hp": 430,
	},
	{
		"id": "sora_coupe", "name": "Sora Coupe", "maker": "Sora", "year": 2003, "style": "Sports coupe",
		"cls": "A", "pi": 765, "desc": "High-revving rear-drive coupe with a perfectly balanced chassis. A drifter's dream.",
		"model": "sora_coupe", "mass": 1290.0, "com": Vector3(0, 0.48, 0.0),
		"torque": 360.0, "curve": [Vector2(1000, 0.5), Vector2(3000, 0.78), Vector2(5500, 1.0), Vector2(7500, 0.92), Vector2(8200, 0.8)],
		"idle": 950.0, "redline": 8200.0, "cyl": 6, "layout": "I6 twin-turbo", "turbo": true, "pitch": 1.1, "rough": 0.3,
		"drive": CarSpec.Drivetrain.RWD, "gears": [3.2, 2.2, 1.6, 1.25, 1.0, 0.82], "top": 265.0,
		"tire": CarSpec.TireType.SPORT, "grip": 1.12, "rear_bias": 0.98, "peak_slip": 8.5, "slide": 0.84,
		"rest": 0.15, "hzf": 2.0, "hzr": 2.1, "damp": 0.45, "arbf": 14000.0, "arbr": 10000.0,
		"brake": 13500.0, "bias": 0.6, "hb": 6500.0, "lock": 38.0, "df": 0.35, "bal": 0.45,
		"paint": Color(0.92, 0.92, 0.94), "finish": "pearl", "rim": Color(0.1, 0.1, 0.1),
		"stats": [7.2, 7.8, 7.0, 6.0, 7.2, 3.0], "hp": 320,
	},
	{
		"id": "valcourt_gt", "name": "Valcourt GT", "maker": "Valcourt", "year": 2022, "style": "Grand tourer",
		"cls": "S1", "pi": 860, "desc": "Front-engined V12 grand tourer. Devastatingly fast and calm at three hundred.",
		"model": "valcourt_gt", "mass": 1720.0, "com": Vector3(0, 0.5, -0.1),
		"torque": 700.0, "curve": [Vector2(1000, 0.55), Vector2(2500, 0.88), Vector2(5000, 1.0), Vector2(7000, 0.9), Vector2(7400, 0.82)],
		"idle": 800.0, "redline": 7400.0, "cyl": 12, "layout": "V12", "turbo": false, "pitch": 0.9, "rough": 0.2,
		"drive": CarSpec.Drivetrain.RWD, "gears": [3.1, 2.15, 1.6, 1.28, 1.05, 0.88, 0.74], "top": 315.0,
		"tire": CarSpec.TireType.SPORT, "grip": 1.15, "rear_bias": 1.03, "peak_slip": 8.0, "slide": 0.82,
		"rest": 0.15, "hzf": 1.8, "hzr": 1.9, "damp": 0.45, "arbf": 15000.0, "arbr": 12000.0,
		"brake": 17000.0, "bias": 0.6, "hb": 6500.0, "lock": 33.0, "df": 0.55, "bal": 0.45,
		"paint": Color(0.06, 0.2, 0.15), "finish": "metallic", "rim": Color(0.6, 0.6, 0.62),
		"stats": [9.0, 7.6, 8.2, 6.8, 8.0, 2.5], "hp": 620,
	},
	{
		"id": "nyx_strata", "name": "Nyx Strata", "maker": "Nyx", "year": 2024, "style": "Mid-engine hypercar",
		"cls": "S2", "pi": 955, "desc": "All-wheel-drive mid-engine missile with real downforce. Brutal launch, glued to the road.",
		"model": "nyx_strata", "mass": 1460.0, "com": Vector3(0, 0.42, 0.15),
		"torque": 820.0, "curve": [Vector2(1000, 0.5), Vector2(3000, 0.9), Vector2(6000, 1.0), Vector2(8200, 0.9), Vector2(8800, 0.8)],
		"idle": 1000.0, "redline": 8800.0, "cyl": 10, "layout": "V10 hybrid", "turbo": false, "pitch": 1.2, "rough": 0.25,
		"drive": CarSpec.Drivetrain.AWD, "awd": 0.35, "gears": [3.2, 2.3, 1.75, 1.4, 1.15, 0.97, 0.83], "top": 345.0,
		"tire": CarSpec.TireType.SPORT, "grip": 1.28, "rear_bias": 1.04, "peak_slip": 8.5, "slide": 0.84,
		"rest": 0.13, "hzf": 2.4, "hzr": 2.5, "damp": 0.5, "arbf": 18000.0, "arbr": 15000.0,
		"brake": 21000.0, "bias": 0.58, "hb": 7000.0, "lock": 32.0, "df": 1.2, "bal": 0.42,
		"paint": Color(0.45, 0.85, 0.15), "finish": "metallic", "rim": Color(0.08, 0.08, 0.09),
		"stats": [10.0, 9.4, 9.8, 9.8, 9.5, 2.0], "hp": 860,
	},
	{
		"id": "mistral_r5", "name": "Mistral R5", "maker": "Mistral", "year": 2016, "style": "Rally car",
		"cls": "A", "pi": 735, "desc": "Purpose-built gravel weapon. Short gearing, long-travel dampers and AWD bite on loose roads.",
		"model": "mistral_r5", "mass": 1240.0, "com": Vector3(0, 0.5, -0.1),
		"torque": 450.0, "curve": [Vector2(1000, 0.55), Vector2(2500, 0.95), Vector2(4500, 1.0), Vector2(6800, 0.85), Vector2(7500, 0.75)],
		"idle": 1000.0, "redline": 7500.0, "cyl": 4, "layout": "I4 turbo (anti-lag)", "turbo": true, "pitch": 1.0, "rough": 0.55,
		"drive": CarSpec.Drivetrain.AWD, "awd": 0.45, "gears": [3.3, 2.4, 1.85, 1.48, 1.22, 1.03], "top": 210.0,
		"tire": CarSpec.TireType.RALLY, "grip": 1.08, "rear_bias": 0.98, "peak_slip": 10.0, "slide": 0.86,
		"rest": 0.22, "hzf": 1.5, "hzr": 1.6, "damp": 0.45, "arbf": 9000.0, "arbr": 7000.0,
		"brake": 13000.0, "bias": 0.58, "hb": 8000.0, "lock": 38.0, "df": 0.3, "bal": 0.45,
		"paint": Color(0.12, 0.35, 0.85), "finish": "gloss", "rim": Color(0.95, 0.95, 0.95),
		"stats": [5.6, 7.4, 7.6, 8.6, 6.6, 9.0], "hp": 330,
	},
	{
		"id": "trailhound", "name": "Trailhound 4x4", "maker": "Hound Works", "year": 2020, "style": "Off-road SUV",
		"cls": "C", "pi": 560, "desc": "Tall, tough and unstoppable off the tarmac. Leans in corners, shrugs at rocks.",
		"model": "trailhound", "mass": 2150.0, "com": Vector3(0, 0.8, -0.05),
		"torque": 560.0, "curve": [Vector2(900, 0.7), Vector2(2000, 1.0), Vector2(3800, 0.96), Vector2(5200, 0.8), Vector2(5800, 0.66)],
		"idle": 750.0, "redline": 5800.0, "cyl": 6, "layout": "V6 turbo diesel", "turbo": true, "pitch": 0.75, "rough": 0.5,
		"drive": CarSpec.Drivetrain.AWD, "awd": 0.48, "gears": [4.2, 2.6, 1.7, 1.25, 1.0, 0.8], "top": 190.0,
		"tire": CarSpec.TireType.OFFROAD, "grip": 1.0, "rear_bias": 1.02, "peak_slip": 9.0, "slide": 0.8,
		"rest": 0.3, "hzf": 1.15, "hzr": 1.25, "damp": 0.4, "arbf": 12000.0, "arbr": 9000.0,
		"brake": 15000.0, "bias": 0.6, "hb": 6000.0, "lock": 36.0, "df": 0.0, "bal": 0.5,
		"paint": Color(0.38, 0.4, 0.3), "finish": "matte", "rim": Color(0.2, 0.2, 0.21),
		"stats": [4.6, 4.2, 4.8, 6.0, 4.6, 9.6], "hp": 300,
	},
	{
		"id": "haulmark_2500", "name": "Haulmark 2500", "maker": "Haulmark", "year": 2019, "style": "Pickup truck",
		"cls": "D", "pi": 480, "desc": "Full-size work truck. Heavy, softly sprung and endearingly wallowy in the bends.",
		"model": "haulmark_2500", "mass": 2350.0, "com": Vector3(0, 0.82, -0.3),
		"torque": 620.0, "curve": [Vector2(800, 0.7), Vector2(2000, 1.0), Vector2(3500, 0.95), Vector2(4800, 0.8), Vector2(5400, 0.65)],
		"idle": 700.0, "redline": 5400.0, "cyl": 8, "layout": "V8", "turbo": false, "pitch": 0.68, "rough": 0.6,
		"drive": CarSpec.Drivetrain.RWD, "gears": [3.6, 2.2, 1.5, 1.15, 0.9, 0.72], "top": 185.0,
		"tire": CarSpec.TireType.OFFROAD, "grip": 0.94, "rear_bias": 0.97, "peak_slip": 8.0, "slide": 0.8,
		"rest": 0.26, "hzf": 1.1, "hzr": 1.3, "damp": 0.32, "arbf": 7000.0, "arbr": 3000.0,
		"brake": 15000.0, "bias": 0.64, "hb": 6000.0, "lock": 36.0, "df": 0.0, "bal": 0.5,
		"paint": Color(0.55, 0.06, 0.06), "finish": "gloss", "rim": Color(0.78, 0.78, 0.8),
		"stats": [4.4, 3.2, 4.6, 4.8, 3.8, 7.6], "hp": 390,
	},
	{
		"id": "spatz_roadster", "name": "Spatz Roadster", "maker": "Spatz", "year": 1958, "style": "Vintage roadster",
		"cls": "D", "pi": 310, "desc": "Tiny open two-seater from another era. Slow, light, and pure joy on a sunny coast road.",
		"model": "spatz_roadster", "mass": 820.0, "com": Vector3(0, 0.45, 0.0),
		"torque": 135.0, "curve": [Vector2(900, 0.65), Vector2(2200, 0.95), Vector2(3600, 1.0), Vector2(5200, 0.85), Vector2(5800, 0.7)],
		"idle": 750.0, "redline": 5800.0, "cyl": 4, "layout": "I4 twin-carb", "turbo": false, "pitch": 1.15, "rough": 0.55,
		"drive": CarSpec.Drivetrain.RWD, "gears": [3.5, 2.2, 1.4, 1.0], "top": 160.0,
		"tire": CarSpec.TireType.VINTAGE, "grip": 0.92, "rear_bias": 0.98, "peak_slip": 7.0, "slide": 0.8,
		"rest": 0.18, "hzf": 1.4, "hzr": 1.5, "damp": 0.32, "arbf": 4000.0, "arbr": 2500.0,
		"brake": 7000.0, "bias": 0.62, "hb": 3500.0, "lock": 34.0, "df": 0.0, "bal": 0.5,
		"paint": Color(0.55, 0.78, 0.72), "finish": "gloss", "rim": Color(0.85, 0.85, 0.86),
		"stats": [2.6, 5.6, 2.8, 3.0, 3.6, 3.2], "hp": 95,
	},
]

# surfaces: id, key, name, grip per tyre [ROAD, SPORT, RALLY, OFFROAD, VINTAGE], rr, drag, bump, wet, offroad, colour, squeal, rumble
const SURFACES := [
	[0, "asphalt", "Asphalt", [1.0, 1.08, 0.97, 0.88, 0.92], 0.012, 0.0, 0.0, 1.0, false, Color(0.75, 0.75, 0.75, 0.55), 1.0, 0.0],
	[1, "concrete", "Concrete", [0.97, 1.03, 0.95, 0.87, 0.9], 0.012, 0.0, 0.002, 0.85, false, Color(0.8, 0.8, 0.78, 0.5), 1.0, 0.1],
	[2, "dirt", "Dirt", [0.66, 0.62, 0.9, 0.86, 0.64], 0.028, 0.015, 0.012, 1.1, true, Color(0.55, 0.42, 0.28, 0.7), 0.15, 0.5],
	[3, "gravel", "Gravel", [0.62, 0.58, 0.88, 0.82, 0.6], 0.032, 0.02, 0.016, 0.7, true, Color(0.62, 0.58, 0.5, 0.7), 0.1, 0.8],
	[4, "grass", "Grass", [0.52, 0.48, 0.7, 0.76, 0.52], 0.045, 0.05, 0.02, 1.2, true, Color(0.35, 0.42, 0.22, 0.6), 0.05, 0.6],
	[5, "sand", "Sand", [0.46, 0.42, 0.62, 0.74, 0.46], 0.08, 0.1, 0.012, 0.4, true, Color(0.85, 0.72, 0.5, 0.75), 0.05, 0.4],
	[6, "snow", "Snow", [0.42, 0.38, 0.58, 0.62, 0.4], 0.04, 0.04, 0.01, 0.3, true, Color(0.95, 0.96, 1.0, 0.8), 0.05, 0.3],
	[7, "rock", "Rock", [0.72, 0.7, 0.82, 0.86, 0.68], 0.025, 0.0, 0.03, 0.8, true, Color(0.5, 0.48, 0.45, 0.6), 0.3, 1.0],
]


# weather: key, name, clouds, darkness, fog, vfog, rain, wet, grip, wind, sun, ambient, lightning, visibility
const WEATHER := [
	["clear", "Clear", 0.18, 0.0, 0.00035, 0.0, 0.0, 0.0, 1.0, 0.25, 1.0, 1.0, false, 8000.0],
	["cloudy", "Cloudy", 0.65, 0.35, 0.0006, 0.0, 0.0, 0.0, 1.0, 0.45, 0.6, 0.85, false, 6000.0],
	["rain", "Rain", 0.9, 0.7, 0.0016, 0.004, 0.75, 1.0, 0.78, 0.6, 0.35, 0.7, false, 2500.0],
	["fog", "Fog", 0.7, 0.45, 0.012, 0.03, 0.0, 0.35, 0.92, 0.1, 0.4, 0.8, false, 250.0],
	["storm", "Storm", 1.0, 0.92, 0.0028, 0.008, 1.0, 1.0, 0.68, 1.0, 0.2, 0.55, true, 1500.0],
]


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://data/cars"))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://data/surfaces"))
	var idx := 0
	for c in CARS:
		idx += 1
		var s := CarSpec.new()
		s.id = c.id
		s.display_name = c.name
		s.maker = c.maker
		s.year = c.year
		s.body_style = c.style
		s.car_class = c.cls
		s.pi = c.pi
		s.description = c.desc
		s.model_path = "res://assets/imported/cars/%s.glb" % c.model
		s.mass = c.mass
		s.com_offset = c.com
		s.peak_torque = c.torque
		s.torque_curve = PackedVector2Array(c.curve)
		s.idle_rpm = c.idle
		s.redline_rpm = c.redline
		s.cylinders = c.cyl
		s.engine_layout = c.layout
		s.turbo = c.turbo
		s.sound_base_pitch = c.pitch
		s.sound_roughness = c.rough
		s.drivetrain = c.drive
		s.awd_front_split = c.get("awd", 0.4)
		s.gear_ratios = PackedFloat32Array(c.gears)
		s.top_speed_kmh = c.top
		s.tire_type = c.tire
		s.grip = c.grip
		s.grip_rear_bias = c.rear_bias
		s.peak_slip_angle_deg = c.peak_slip
		s.slide_grip = c.slide
		s.suspension_rest = c.rest
		s.spring_hz_front = c.hzf
		s.spring_hz_rear = c.hzr
		s.damping_ratio = c.damp
		s.anti_roll_front = c.arbf
		s.anti_roll_rear = c.arbr
		s.brake_force = c.brake
		s.brake_bias = c.bias
		s.handbrake_force = c.hb
		s.steer_lock_deg = c.lock
		s.downforce_area = c.df
		s.aero_balance = c.bal
		s.paint_color = c.paint
		s.paint_finish = c.finish
		s.rim_color = c.rim
		var st: Array = c.stats
		s.stat_speed = st[0]
		s.stat_handling = st[1]
		s.stat_accel = st[2]
		s.stat_launch = st[3]
		s.stat_braking = st[4]
		s.stat_offroad = st[5]
		s.power_hp = c.hp
		var path := "res://data/cars/%02d_%s.tres" % [idx, c.id]
		var err := ResourceSaver.save(s, path)
		print("saved ", path, " err=", err)
	for row in SURFACES:
		var d := SurfaceDef.new()
		d.id = row[0]
		d.key = row[1]
		d.display_name = row[2]
		d.grip_by_tire = PackedFloat32Array(row[3])
		d.rolling_resistance = row[4]
		d.drag = row[5]
		d.bumpiness = row[6]
		d.wet_sensitivity = row[7]
		d.is_offroad = row[8]
		d.particle_color = row[9]
		d.squeal = row[10]
		d.rumble = row[11]
		var p := "res://data/surfaces/%d_%s.tres" % [d.id, d.key]
		print("saved ", p, " err=", ResourceSaver.save(d, p))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://data/weather"))
	for w in WEATHER:
		var wp := WeatherPreset.new()
		wp.key = w[0]
		wp.display_name = w[1]
		wp.cloud_coverage = w[2]
		wp.cloud_darkness = w[3]
		wp.fog_density = w[4]
		wp.volumetric_fog = w[5]
		wp.rain = w[6]
		wp.wetness = w[7]
		wp.grip = w[8]
		wp.wind = w[9]
		wp.sun_energy = w[10]
		wp.ambient_energy = w[11]
		wp.lightning = w[12]
		wp.visibility_m = w[13]
		print("saved weather ", w[0], " err=", ResourceSaver.save(wp, "res://data/weather/%s.tres" % w[0]))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://data/upgrades"))
	var ups := [
		["1_engine", "engine", "Engine", {"mod_power": [1.0, 1.08, 1.17, 1.28], "mod_top": [1.0, 1.03, 1.06, 1.1]}, 22, 4000],
		["2_tires", "tires", "Tyres", {"mod_grip": [1.0, 1.04, 1.08, 1.13]}, 18, 2500],
		["3_suspension", "suspension", "Suspension", {"mod_spring": [1.0, 1.1, 1.2, 1.32], "mod_arb": [1.0, 1.12, 1.25, 1.4]}, 10, 2000],
		["4_brakes", "brakes", "Brakes", {"mod_brake": [1.0, 1.1, 1.2, 1.32]}, 8, 1500],
		["5_weight", "weight", "Weight reduction", {"mod_mass": [1.0, 0.96, 0.92, 0.87]}, 15, 3000],
		["6_aero", "aero", "Aero", {"mod_downforce": [1.0, 1.3, 1.7, 2.2]}, 10, 2000],
	]
	for u in ups:
		var d := UpgradeDef.new()
		d.key = u[1]
		d.display_name = u[2]
		d.effects = u[3]
		d.pi_per_level = u[4]
		d.cost_per_level = u[5]
		print("saved upgrade ", u[1], " err=", ResourceSaver.save(d, "res://data/upgrades/%s.tres" % u[0]))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://data/events"))
	var K := EventDef.Kind
	# id, name, kind, road, start(xz or frac), end, stars, opponents, laps, spacing, reward, description
	var evs := [
		["trap_valley", "Valley Radar", K.SPEED_TRAP, "valley_highway", 0.3, 0.3, [130, 165, 200], 0, 1, 600, 800, "Blast through the camera on the highway."],
		["trap_speedway", "Speedway Snap", K.SPEED_TRAP, "ochre_speedway", 0.55, 0.55, [110, 140, 170], 0, 1, 600, 800, ""],
		["trap_mesa", "Ochre Flash", K.SPEED_TRAP, "mesa_run", 0.55, 0.55, [110, 140, 170], 0, 1, 600, 800, ""],
		["trap_coast", "Clifftop Camera", K.SPEED_TRAP, "festival_loop", Vector2(1290, -480), Vector2(1290, -480), [100, 130, 160], 0, 1, 600, 800, ""],
		["zone_highway", "Highway Haste", K.SPEED_ZONE, "valley_highway", 0.55, 0.8, [110, 140, 165], 0, 1, 600, 1200, ""],
		["zone_river", "River Run", K.SPEED_ZONE, "river_road", 0.15, 0.5, [80, 100, 120], 0, 1, 600, 1200, ""],
		["zone_coast", "Saltcliff Stretch", K.SPEED_ZONE, "festival_loop", Vector2(1370, 400), Vector2(1270, -60), [90, 115, 140], 0, 1, 600, 1200, ""],
		["drift_hairpins", "Crown Hairpins", K.DRIFT_ZONE, "festival_loop", Vector2(-1560, -1335), Vector2(-1540, -1160), [1500, 3500, 6000], 0, 1, 600, 1500, ""],
		["drift_pinewood", "Pinewood Slide", K.DRIFT_ZONE, "pinewood_gravel", Vector2(-400, -1060), Vector2(-760, -660), [1500, 3500, 6000], 0, 1, 600, 1500, ""],
		["drift_dunes", "Dune Drift", K.DRIFT_ZONE, "dune_track", 0.08, 0.92, [800, 2000, 3500], 0, 1, 600, 1200, ""],
		["drift_ravenhold", "Ravenhold Drift", K.DRIFT_ZONE, "castle_climb", Vector2(-860, -900), Vector2(-920, -1200), [1200, 2800, 5000], 0, 1, 600, 1500, ""],
		["jump_dunes", "Dune Leap", K.JUMP, "dune_track", 0.5, 0.5, [20, 32, 45], 0, 1, 600, 1000, ""],
		["jump_hollow", "Hollow Oak Hop", K.JUMP, "hollow_track", 0.55, 0.55, [20, 32, 45], 0, 1, 600, 1000, ""],
		["jump_windmill", "Windmill Air", K.JUMP, "windmill_track", Vector2(580, -800), Vector2(580, -800), [20, 32, 45], 0, 1, 600, 1000, ""],
		["race_coast", "Coast Sprint", K.RACE, "festival_loop", Vector2(1250, 900), Vector2(1120, -1450), [200, 170, 145], 3, 1, 500, 4000, "Sprint north along the Saltcliff cliffs, across the bay bridge."],
		["race_desert", "Desert Run", K.RACE, "festival_loop", Vector2(-1760, 660), Vector2(-20, 1380), [220, 185, 160], 3, 1, 500, 4000, "Wind through the Ochre Mesa and back to the valley."],
		["race_highway", "Highway Charge", K.RACE, "valley_highway", Vector2(-1600, 1640), Vector2(1260, -720), [140, 115, 95], 3, 1, 600, 4000, "Flat out from the desert to the coast."],
		["tt_grand_tour", "Velora Grand Tour", K.TIME_TRIAL, "festival_loop", Vector2(300, 1150), Vector2(300, 1150), [900, 720, 600], 0, 1, 1000, 8000, "The full 20 km Festival Loop against the clock."],
	]
	var board_spots := [["valley_highway", 0.12], ["valley_highway", 0.66], ["river_road", 0.7], ["festival_loop", 0.03], ["festival_loop", 0.09],
		["festival_loop", 0.27], ["festival_loop", 0.36], ["festival_loop", 0.44], ["festival_loop", 0.58], ["festival_loop", 0.69],
		["festival_loop", 0.86], ["festival_loop", 0.95], ["pinewood_gravel", 0.6], ["windmill_track", 0.25], ["redwell_lane", 0.4],
		["ochre_cutoff", 0.5], ["south_lane", 0.5], ["clifftop_track", 0.5], ["mill_lane", 0.4], ["back_road", 0.5]]
	for bi in board_spots.size():
		evs.append(["board_%02d" % bi, "Festival board %d" % (bi + 1), K.BOARD, board_spots[bi][0], board_spots[bi][1], board_spots[bi][1], [0, 0, 0], 0, 1, 600, 500, ""])
	for f in DirAccess.get_files_at(ProjectSettings.globalize_path("res://data/events")):
		DirAccess.remove_absolute(ProjectSettings.globalize_path("res://data/events/" + f))
	for e in evs:
		var d := EventDef.new()
		d.id = e[0]
		d.display_name = e[1]
		d.kind = e[2]
		d.road_id = e[3]
		if e[4] is Vector2:
			d.start_xz = e[4]
			d.end_xz = e[5]
		else:
			d.start_frac = e[4]
			d.end_frac = e[5]
		d.stars = PackedFloat32Array(e[6])
		d.opponents = e[7]
		d.laps = e[8]
		d.checkpoint_spacing_m = e[9]
		d.reward = e[10]
		d.description = e[11]
		ResourceSaver.save(d, "res://data/events/%s.tres" % d.id)
	print("saved events ", evs.size())
	quit()
