extends SceneTree
## Generates the data-driven resources (.tres): cars, surfaces, upgrades, weather presets.
##   Godot_console.exe --headless --path <project> --script res://tools/make_game_data.gd
## Gear ratios and drag area are solved from each car's target power and top speed so the
## numbers stay physically consistent when specs are edited here.

const RHO := 1.225

const CURVES := {
	"turbo": [[0.0, 0.52], [0.14, 0.72], [0.3, 1.0], [0.74, 1.0], [0.9, 0.86], [1.0, 0.74]],
	"na_high": [[0.0, 0.5], [0.2, 0.68], [0.5, 0.88], [0.76, 1.0], [0.9, 0.95], [1.0, 0.84]],
	"v8_low": [[0.0, 0.68], [0.2, 0.88], [0.45, 1.0], [0.7, 0.93], [0.9, 0.8], [1.0, 0.72]],
	"v12": [[0.0, 0.55], [0.25, 0.78], [0.55, 0.95], [0.75, 1.0], [0.92, 0.94], [1.0, 0.86]],
	"truck": [[0.0, 0.66], [0.18, 0.94], [0.4, 1.0], [0.7, 0.88], [1.0, 0.66]],
	"vintage": [[0.0, 0.6], [0.3, 0.86], [0.55, 1.0], [0.8, 0.9], [1.0, 0.78]],
}

# id, name, category, class blurb, numbers. Dimensions mirror docs/ASSET_CONVENTIONS.md specs.
const CARS := [
	{"id": "kestrel_r4", "name": "Kestrel R4", "cat": "Hot Hatch", "style": "Modern",
	 "blurb": "Featherweight turbo hatch. Darty front end, playful on lift-off, loves mountain switchbacks.",
	 "hp": 245, "mass": 1230, "idle": 850, "red": 6700, "max": 7000, "curve": "turbo", "turbo": true,
	 "gears": 6, "first_kmh": 62, "rev": 32, "top": 245, "final": 3.9, "dt": 0, "split": 0.0, "lock": 0.35,
	 "grip": 1.08, "gf": 1.0, "gr": 1.03, "peak": 7.5, "slide": 0.82, "off": 0.0,
	 "sf": 52000, "sr": 48000, "db": 3800, "drb": 5200, "travel": 0.19, "arbf": 17000, "arbr": 15000,
	 "com": Vector3(0, 0.5, -0.26), "df": 0.12, "dr": 0.2, "bias": 0.66, "steer": 34.0, "hs": 7.0,
	 "wb": 2.55, "tf": 1.53, "tr": 1.52, "rf": 0.315, "rr": 0.315, "size": Vector3(1.78, 1.44, 4.05),
	 "cyl": 4, "rasp": 0.55, "pitch": 1.1, "color": Color(0.95, 0.76, 0.0), "finish": 0, "inertia": Vector3(1, 0.88, 1)},
	{"id": "aurelia_sedan", "name": "Aurelia Saloon", "cat": "Family Sedan", "style": "Modern",
	 "blurb": "Comfortable, predictable everyday saloon. Soft springs, safe understeer, a calm long-distance cruiser.",
	 "hp": 172, "mass": 1420, "idle": 750, "red": 6200, "max": 6500, "curve": "turbo", "turbo": true,
	 "gears": 6, "first_kmh": 55, "rev": 28, "top": 218, "final": 3.6, "dt": 0, "split": 0.0, "lock": 0.15,
	 "grip": 0.97, "gf": 1.0, "gr": 1.06, "peak": 7.0, "slide": 0.78, "off": 0.1,
	 "sf": 40000, "sr": 38000, "db": 3000, "drb": 4300, "travel": 0.21, "arbf": 14000, "arbr": 7000,
	 "com": Vector3(0, 0.53, -0.22), "df": 0.05, "dr": 0.08, "bias": 0.68, "steer": 33.0, "hs": 7.5,
	 "wb": 2.78, "tf": 1.57, "tr": 1.56, "rf": 0.325, "rr": 0.325, "size": Vector3(1.82, 1.45, 4.75),
	 "cyl": 4, "rasp": 0.15, "pitch": 0.95, "color": Color(0.24, 0.35, 0.5), "finish": 2, "inertia": Vector3(1, 1.0, 1)},
	{"id": "brute_68", "name": "Brute 68", "cat": "Classic Muscle", "style": "1968",
	 "blurb": "Big-block V8, four speeds and skinny old-school grip. Smoke on demand, respect on the brakes.",
	 "hp": 425, "mass": 1620, "idle": 700, "red": 5800, "max": 6200, "curve": "v8_low", "turbo": false,
	 "gears": 4, "first_kmh": 88, "rev": 30, "top": 232, "final": 3.55, "dt": 1, "split": 0.0, "lock": 0.6,
	 "grip": 0.97, "gf": 1.0, "gr": 0.97, "peak": 8.5, "slide": 0.86, "off": 0.0,
	 "sf": 42000, "sr": 38000, "db": 3000, "drb": 4200, "travel": 0.22, "arbf": 15000, "arbr": 6000,
	 "com": Vector3(0, 0.52, -0.12), "df": 0.0, "dr": 0.02, "bias": 0.62, "steer": 32.0, "hs": 7.0,
	 "wb": 2.80, "tf": 1.55, "tr": 1.55, "rf": 0.34, "rr": 0.34, "size": Vector3(1.9, 1.33, 4.95),
	 "cyl": 8, "rasp": 0.75, "pitch": 0.7, "color": Color(0.62, 0.1, 0.1), "finish": 0, "inertia": Vector3(1, 0.95, 1)},
	{"id": "sora_s2", "name": "Sora S2", "cat": "Sports Coupe", "style": "Modern",
	 "blurb": "Balanced front-mid-engine coupe with a high-revving heart. Precise, adjustable, rewarding.",
	 "hp": 305, "mass": 1290, "idle": 900, "red": 7800, "max": 8200, "curve": "na_high", "turbo": false,
	 "gears": 6, "first_kmh": 68, "rev": 32, "top": 258, "final": 4.1, "dt": 1, "split": 0.0, "lock": 0.55,
	 "grip": 1.1, "gf": 1.0, "gr": 1.0, "peak": 7.5, "slide": 0.83, "off": 0.0,
	 "sf": 60000, "sr": 56000, "db": 4000, "drb": 5600, "travel": 0.17, "arbf": 18000, "arbr": 14000,
	 "com": Vector3(0, 0.46, -0.06), "df": 0.15, "dr": 0.25, "bias": 0.62, "steer": 33.0, "hs": 6.5,
	 "wb": 2.55, "tf": 1.54, "tr": 1.56, "rf": 0.32, "rr": 0.32, "size": Vector3(1.8, 1.27, 4.35),
	 "cyl": 4, "rasp": 0.45, "pitch": 1.2, "color": Color(0.9, 0.9, 0.88), "finish": 0, "inertia": Vector3(1, 0.85, 1)},
	{"id": "castellan_gt", "name": "Castellan GT", "cat": "Grand Tourer", "style": "Modern",
	 "blurb": "Front-engined V12 continent crusher. Huge stability at 300 km/h, effortless pace on the highway.",
	 "hp": 620, "mass": 1780, "idle": 800, "red": 7600, "max": 8000, "curve": "v12", "turbo": false,
	 "gears": 7, "first_kmh": 78, "rev": 30, "top": 325, "final": 3.3, "dt": 1, "split": 0.0, "lock": 0.5,
	 "grip": 1.13, "gf": 1.0, "gr": 1.05, "peak": 7.0, "slide": 0.8, "off": 0.0,
	 "sf": 64000, "sr": 62000, "db": 4400, "drb": 6000, "travel": 0.17, "arbf": 21000, "arbr": 16000,
	 "com": Vector3(0, 0.48, -0.14), "df": 0.28, "dr": 0.45, "bias": 0.63, "steer": 32.0, "hs": 5.5,
	 "wb": 2.85, "tf": 1.66, "tr": 1.65, "rf": 0.35, "rr": 0.35, "size": Vector3(1.98, 1.28, 4.85),
	 "cyl": 12, "rasp": 0.5, "pitch": 1.0, "color": Color(0.12, 0.24, 0.17), "finish": 2, "inertia": Vector3(1, 1.0, 1)},
	{"id": "vortex_x", "name": "Vortex X", "cat": "Supercar", "style": "Modern",
	 "blurb": "Mid-engined twin-turbo AWD missile with real downforce. Brutal launch, glued at speed.",
	 "hp": 810, "mass": 1480, "idle": 950, "red": 8200, "max": 8600, "curve": "turbo", "turbo": true,
	 "gears": 7, "first_kmh": 88, "rev": 35, "top": 352, "final": 3.4, "dt": 2, "split": 0.35, "lock": 0.6,
	 "grip": 1.22, "gf": 1.0, "gr": 1.04, "peak": 6.8, "slide": 0.8, "off": 0.0,
	 "sf": 82000, "sr": 86000, "db": 5000, "drb": 7000, "travel": 0.14, "arbf": 24000, "arbr": 20000,
	 "com": Vector3(0, 0.42, 0.22), "df": 0.45, "dr": 0.75, "bias": 0.6, "steer": 31.0, "hs": 5.0,
	 "wb": 2.70, "tf": 1.70, "tr": 1.65, "rf": 0.345, "rr": 0.36, "size": Vector3(2.04, 1.12, 4.6),
	 "cyl": 8, "rasp": 0.65, "pitch": 1.15, "color": Color(0.91, 0.35, 0.05), "finish": 2, "inertia": Vector3(1, 0.8, 1)},
	{"id": "granite_rally", "name": "Granite RS", "cat": "Rally", "style": "1990s",
	 "blurb": "Gravel-spec AWD turbo on long-travel dampers. Flat-out on dirt, sideways on demand.",
	 "hp": 330, "mass": 1260, "idle": 1000, "red": 7500, "max": 7800, "curve": "turbo", "turbo": true,
	 "gears": 6, "first_kmh": 58, "rev": 35, "top": 222, "final": 4.4, "dt": 2, "split": 0.45, "lock": 0.7,
	 "grip": 1.02, "gf": 1.0, "gr": 0.98, "peak": 9.0, "slide": 0.88, "off": 0.75,
	 "sf": 38000, "sr": 36000, "db": 3400, "drb": 4800, "travel": 0.27, "arbf": 12000, "arbr": 10000,
	 "com": Vector3(0, 0.52, -0.1), "df": 0.1, "dr": 0.18, "bias": 0.6, "steer": 35.0, "hs": 7.5,
	 "wb": 2.55, "tf": 1.58, "tr": 1.58, "rf": 0.33, "rr": 0.33, "size": Vector3(1.85, 1.4, 4.2),
	 "cyl": 4, "rasp": 0.8, "pitch": 1.05, "color": Color(0.96, 0.96, 0.94), "finish": 0, "inertia": Vector3(1, 0.82, 1)},
	{"id": "ridgeback_sx", "name": "Ridgeback SX", "cat": "Off-Road SUV", "style": "Modern",
	 "blurb": "Tall, tough and unstoppable off the tarmac. Long-travel suspension shrugs off ruts and jumps.",
	 "hp": 345, "mass": 2150, "idle": 700, "red": 6200, "max": 6500, "curve": "turbo", "turbo": true,
	 "gears": 6, "first_kmh": 50, "rev": 28, "top": 208, "final": 3.9, "dt": 2, "split": 0.45, "lock": 0.75,
	 "grip": 0.95, "gf": 1.0, "gr": 1.0, "peak": 9.5, "slide": 0.84, "off": 0.9,
	 "sf": 52000, "sr": 54000, "db": 4600, "drb": 6600, "travel": 0.33, "arbf": 17000, "arbr": 12000,
	 "com": Vector3(0, 0.74, -0.1), "df": 0.0, "dr": 0.0, "bias": 0.62, "steer": 34.0, "hs": 8.0,
	 "wb": 2.85, "tf": 1.65, "tr": 1.65, "rf": 0.40, "rr": 0.40, "size": Vector3(1.95, 1.85, 4.7),
	 "cyl": 6, "rasp": 0.35, "pitch": 0.85, "color": Color(0.42, 0.42, 0.23), "finish": 1, "inertia": Vector3(1.1, 1.05, 1.1)},
	{"id": "hauler_2500", "name": "Hauler 2500", "cat": "Pickup Truck", "style": "Modern",
	 "blurb": "Heavy V8 pickup. Leans hard, pulls like a train, surprisingly fun on gravel.",
	 "hp": 405, "mass": 2450, "idle": 650, "red": 5600, "max": 6000, "curve": "truck", "turbo": false,
	 "gears": 6, "first_kmh": 48, "rev": 25, "top": 200, "final": 3.73, "dt": 2, "split": 0.3, "lock": 0.6,
	 "grip": 0.93, "gf": 1.0, "gr": 0.97, "peak": 9.0, "slide": 0.84, "off": 0.6,
	 "sf": 56000, "sr": 64000, "db": 4200, "drb": 6000, "travel": 0.31, "arbf": 10000, "arbr": 6000,
	 "com": Vector3(0, 0.8, -0.38), "df": 0.0, "dr": 0.0, "bias": 0.64, "steer": 33.0, "hs": 8.0,
	 "wb": 3.55, "tf": 1.72, "tr": 1.72, "rf": 0.40, "rr": 0.40, "size": Vector3(2.0, 1.9, 5.6),
	 "cyl": 8, "rasp": 0.55, "pitch": 0.72, "color": Color(0.18, 0.2, 0.22), "finish": 2, "inertia": Vector3(1.15, 1.15, 1.15)},
	{"id": "lark_roadster", "name": "Lark Roadster", "cat": "Vintage Roadster", "style": "1959",
	 "blurb": "A featherweight open two-seater from a gentler era. Slow, skinny-tyred, and endlessly charming.",
	 "hp": 96, "mass": 860, "idle": 750, "red": 5500, "max": 6000, "curve": "vintage", "turbo": false,
	 "gears": 4, "first_kmh": 50, "rev": 26, "top": 166, "final": 4.2, "dt": 1, "split": 0.0, "lock": 0.25,
	 "grip": 0.88, "gf": 1.0, "gr": 0.98, "peak": 8.5, "slide": 0.86, "off": 0.15,
	 "sf": 26000, "sr": 24000, "db": 2100, "drb": 2900, "travel": 0.22, "arbf": 6000, "arbr": 3000,
	 "com": Vector3(0, 0.42, -0.05), "df": 0.0, "dr": 0.0, "bias": 0.6, "steer": 36.0, "hs": 9.0,
	 "wb": 2.30, "tf": 1.30, "tr": 1.28, "rf": 0.33, "rr": 0.33, "size": Vector3(1.55, 1.2, 3.9),
	 "cyl": 4, "rasp": 0.3, "pitch": 0.9, "color": Color(0.62, 0.85, 0.77), "finish": 0, "inertia": Vector3(1, 0.9, 1)},
]

const SURFACES := [
	# id, name, road, offroad, wet, rolling, rough, slide, particle, smokes, audio, skid, wet_slide, paved, wet_id
	# A wet presentation surface (asphalt_wet, concrete_wet) repeats its dry surface's grip numbers: grip keeps
	# scaling with wetness, only the HUD name, smoke and marks change once the road looks wet.
	["asphalt", "Asphalt", 1.0, 0.9, 0.74, 0.0, 0.0, 1.0, Color(0.85, 0.85, 0.85, 0.55), true, 0, Color(0.03, 0.03, 0.03, 0.55), 0.94, true, "asphalt_wet"],
	["asphalt_wet", "Wet Asphalt", 1.0, 0.9, 0.74, 0.0, 0.0, 1.0, Color(0.75, 0.8, 0.85, 0.45), false, 0, Color(0.03, 0.03, 0.03, 0.25), 0.94, true, ""],
	["concrete", "Concrete", 0.97, 0.88, 0.76, 0.0, 0.002, 1.0, Color(0.85, 0.85, 0.85, 0.5), true, 0, Color(0.05, 0.05, 0.05, 0.5), 0.94, true, "concrete_wet"],
	["concrete_wet", "Wet Concrete", 0.97, 0.88, 0.76, 0.0, 0.002, 1.0, Color(0.75, 0.8, 0.85, 0.45), false, 0, Color(0.05, 0.05, 0.05, 0.25), 0.94, true, ""],
	["dirt", "Dirt", 0.66, 0.84, 0.82, 0.006, 0.01, 0.95, Color(0.55, 0.43, 0.3, 0.6), false, 1, Color(0.22, 0.16, 0.1, 0.55), 1.0, false, ""],
	["gravel", "Gravel", 0.62, 0.8, 0.9, 0.008, 0.012, 0.93, Color(0.62, 0.58, 0.5, 0.6), false, 1, Color(0.25, 0.22, 0.18, 0.5), 1.0, false, ""],
	["grass", "Grass", 0.55, 0.68, 0.8, 0.02, 0.012, 0.9, Color(0.35, 0.45, 0.2, 0.45), false, 2, Color(0.12, 0.18, 0.06, 0.45), 1.0, false, ""],
	["sand", "Sand", 0.5, 0.66, 1.0, 0.045, 0.006, 0.92, Color(0.85, 0.75, 0.55, 0.65), false, 2, Color(0.55, 0.47, 0.32, 0.5), 1.0, false, ""],
	["snow", "Snow", 0.42, 0.56, 0.95, 0.02, 0.006, 0.9, Color(0.95, 0.96, 1.0, 0.7), false, 2, Color(0.75, 0.78, 0.82, 0.5), 1.0, false, ""],
]

const UPGRADES := [
	{"slot": "engine", "name": "Engine", "cost": 9000, "torque_per_level": 0.09, "rpm_per_level": 150.0, "top_speed_per_level": 0.025},
	{"slot": "tires", "name": "Tyres", "cost": 5000, "grip_per_level": 0.035},
	{"slot": "suspension", "name": "Suspension", "cost": 6000, "stiffness_per_level": 0.08, "lower_per_level": 0.008},
	{"slot": "brakes", "name": "Brakes", "cost": 4000, "brake_per_level": 0.1},
	{"slot": "weight", "name": "Weight Reduction", "cost": 7000, "weight_per_level": 0.035},
	{"slot": "aero", "name": "Aero", "cost": 6500, "downforce_per_level": 0.25, "drag_per_level": 0.015},
]


func _init() -> void:
	_make_dir("res://data/cars")
	_make_dir("res://data/surfaces")
	_make_dir("res://data/upgrades")
	for spec: Dictionary in CARS:
		var d := _make_car(spec)
		var err := ResourceSaver.save(d, "res://data/cars/%s.tres" % d.id)
		print("car %-14s err=%d  %.0f hp  %.0f Nm  PI=%d %s  drag=%.3f  gears=%s fd=%.2f" % [d.id, err, d.peak_power_hp(), d.peak_torque, d.perf_index, d.perf_class, d.drag_area, str(d.gear_ratios), d.final_drive])
	for s: Array in SURFACES:
		var sd := SurfaceData.new()
		sd.id = StringName(s[0])
		sd.display_name = s[1]
		sd.grip_road = s[2]
		sd.grip_offroad = s[3]
		sd.wet_grip = s[4]
		sd.rolling_drag = s[5]
		sd.roughness = s[6]
		sd.slide_factor = s[7]
		sd.particle_color = s[8]
		sd.smokes = s[9]
		sd.audio_kind = s[10]
		sd.skid_color = s[11]
		sd.wet_slide = s[12]
		sd.paved = s[13]
		sd.wet_id = StringName(s[14])
		print("surface ", sd.id, " err=", ResourceSaver.save(sd, "res://data/surfaces/%s.tres" % sd.id))
	for u: Dictionary in UPGRADES:
		var ud := UpgradeData.new()
		ud.slot = u["slot"]
		ud.display_name = u["name"]
		ud.cost_per_level = u["cost"]
		for k: String in u.keys():
			if k.ends_with("_per_level"):
				ud.set(k, u[k])
		print("upgrade ", ud.slot, " err=", ResourceSaver.save(ud, "res://data/upgrades/%s.tres" % ud.slot))
	quit(0)


func _make_dir(p: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(p))


func _make_car(s: Dictionary) -> CarData:
	var d := CarData.new()
	d.id = s["id"]
	d.display_name = s["name"]
	d.category = s["cat"]
	d.blurb = s["blurb"]
	d.year_style = s["style"]
	d.model_path = "res://assets/imported/cars/%s.glb" % d.id
	d.default_color = s["color"]
	d.default_finish = s["finish"]
	d.mass = s["mass"]
	d.com = s["com"]
	d.inertia_scale = s["inertia"]
	d.idle_rpm = s["idle"]
	d.redline_rpm = s["red"]
	d.max_rpm = s["max"]
	d.turbo = s["turbo"]
	d.cylinders = s["cyl"]
	d.exhaust_rasp = s["rasp"]
	d.engine_pitch = s["pitch"]
	var curve := Curve.new()
	for p: Array in CURVES[s["curve"]]:
		curve.add_point(Vector2(p[0], p[1]))
	curve.bake()
	d.torque_curve = curve
	# Solve peak torque for the target power.
	d.peak_torque = 100.0
	var p100 := d.peak_power_kw()
	d.peak_torque = 100.0 * (float(s["hp"]) / 1.341) / p100
	d.drivetrain = s["dt"]
	d.awd_front_split = s["split"]
	d.diff_lock = s["lock"]
	d.tire_grip = s["grip"]
	d.grip_front = s["gf"]
	d.grip_rear = s["gr"]
	d.peak_slip_deg = s["peak"]
	d.slide_grip = s["slide"]
	d.offroad_tires = s["off"]
	d.spring_front = s["sf"]
	d.spring_rear = s["sr"]
	d.damper_bump = s["db"]
	d.damper_rebound = s["drb"]
	d.suspension_travel = s["travel"]
	d.anti_roll_front = s["arbf"]
	d.anti_roll_rear = s["arbr"]
	d.downforce_front = s["df"]
	d.downforce_rear = s["dr"]
	d.brake_bias = s["bias"]
	d.max_steer_deg = s["steer"]
	d.high_speed_steer_deg = s["hs"]
	d.brake_force = d.mass * 9.81 * 1.35
	d.handbrake_force = d.mass * 9.81 * 0.75
	d.wheelbase = s["wb"]
	d.track_front = s["tf"]
	d.track_rear = s["tr"]
	d.wheel_radius_front = s["rf"]
	d.wheel_radius_rear = s["rr"]
	d.body_size = s["size"]
	d.top_speed_kmh = s["top"]
	# Gearing: top gear reaches the top speed just under the redline; first gear reaches first_kmh.
	var r_drive: float = s["rr"] if d.drivetrain != CarData.Drivetrain.FWD else s["rf"]
	var v_top: float = float(s["top"]) / 3.6
	var w_red := d.redline_rpm * TAU / 60.0
	d.final_drive = s["final"]
	var top_ratio := w_red * r_drive / (v_top * 1.03) / d.final_drive
	var first_ratio := w_red * r_drive / (float(s["first_kmh"]) / 3.6) / d.final_drive
	var n: int = s["gears"]
	var ratios := PackedFloat32Array()
	for i in n:
		var t := float(i) / float(n - 1)
		# Slightly progressive spacing (closer at the top) like real gearboxes.
		var tt := pow(t, 0.9)
		ratios.append(snappedf(first_ratio * pow(top_ratio / first_ratio, tt), 0.001))
	d.gear_ratios = ratios
	d.reverse_ratio = first_ratio * 0.95
	# Reverse speed limit (km/h): enough to back out of trouble, never highway speed backwards.
	d.reverse_max_kmh = s["rev"]
	# Drag area so that available wheel power balances drag + rolling at the top speed.
	var rpm_top := d.redline_rpm / 1.03
	var p_w := d.torque_at(rpm_top) * rpm_top * TAU / 60.0 * d.drivetrain_efficiency
	var roll := d.rolling_resistance * d.mass * 9.81 * v_top
	d.drag_area = maxf((p_w - roll) * 2.0 / (RHO * pow(v_top, 3.0)), 0.25)
	# Downforce adds drag-free grip here; nothing else to solve.
	d.perf_index = Tuning.performance_index(d)
	d.perf_class = Tuning.class_for(d.perf_index)
	return d
