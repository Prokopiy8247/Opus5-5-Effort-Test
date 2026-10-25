extends SceneTree
## Generates the data-driven Resources (.tres): surfaces and the 10-car roster.
## Run:  Godot_console.exe --headless --path <project> --script res://tools/build_data.gd
## The .tres files are the runtime source of truth; this tool documents/rebuilds the defaults.

const TQ_TURBO_I4 := [0.48, 0.8, 0.98, 1.0, 1.0, 0.96, 0.88, 0.76]
const TQ_NA_I4 := [0.62, 0.74, 0.85, 0.93, 0.99, 1.0, 0.95, 0.86]
const TQ_BIG_V8 := [0.74, 0.88, 0.97, 1.0, 0.97, 0.91, 0.83, 0.72]
const TQ_V12 := [0.6, 0.72, 0.83, 0.92, 0.98, 1.0, 0.98, 0.91]
const TQ_V10 := [0.56, 0.68, 0.8, 0.9, 0.96, 1.0, 0.99, 0.94]
const TQ_TRUCK_V8 := [0.8, 0.93, 1.0, 0.98, 0.92, 0.85, 0.77, 0.66]
const TQ_I6_TURBO := [0.5, 0.84, 1.0, 1.0, 0.99, 0.95, 0.89, 0.8]
const TQ_VINTAGE := [0.7, 0.82, 0.92, 0.98, 1.0, 0.95, 0.86, 0.74]


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://data/surfaces"))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://data/cars"))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://data/upgrades"))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://data/traffic"))
	_surfaces()
	_cars()
	_upgrades()
	_traffic()
	print("[build_data] done")
	quit()


func _save(res: Resource, path: String) -> void:
	var err := ResourceSaver.save(res, path)
	print("  ", path, " -> ", error_string(err))


func _surfaces() -> void:
	# key, name, grip, peak_scale, slide, loose, rr, soft_drag, bump, wet, dust color, particle, sound, skid
	var rows := [
		["asphalt", "Asphalt", 1.0, 1.0, 0.72, 0.0, 0.012, 0.0, 0.0, 0.72, Color(0.6, 0.6, 0.6, 0.0), 0, 0, true],
		["concrete", "Concrete", 0.97, 1.0, 0.74, 0.0, 0.012, 0.0, 0.002, 0.78, Color(0.7, 0.7, 0.7, 0.0), 0, 0, true],
		["dirt", "Dirt", 0.7, 1.6, 0.86, 1.0, 0.028, 0.0, 0.012, 0.74, Color(0.55, 0.42, 0.3, 0.9), 1, 2, true],
		["gravel", "Gravel", 0.66, 1.8, 0.88, 1.0, 0.032, 0.0, 0.016, 0.86, Color(0.62, 0.58, 0.52, 0.9), 2, 1, true],
		["grass", "Grass", 0.55, 1.5, 0.8, 0.7, 0.045, 0.25, 0.022, 0.7, Color(0.35, 0.45, 0.2, 0.6), 3, 3, false],
		["sand", "Sand", 0.52, 2.0, 0.9, 1.0, 0.08, 0.55, 0.012, 1.0, Color(0.85, 0.72, 0.5, 0.9), 4, 4, false],
		["snow", "Snow", 0.42, 1.6, 0.86, 0.9, 0.04, 0.2, 0.01, 1.0, Color(0.95, 0.96, 1.0, 0.9), 5, 5, false],
		["rock", "Rock", 0.78, 1.2, 0.8, 0.3, 0.02, 0.0, 0.03, 0.8, Color(0.55, 0.52, 0.5, 0.6), 1, 1, false],
	]
	for i in rows.size():
		var r: Array = rows[i]
		var s := SurfaceDef.new()
		s.id = i
		s.key = StringName(r[0])
		s.display_name = r[1]
		s.grip = r[2]
		s.slip_peak_scale = r[3]
		s.slide_ratio = r[4]
		s.loose = r[5]
		s.rolling_resistance = r[6]
		s.soft_drag = r[7]
		s.bumpiness = r[8]
		s.wet_grip = r[9]
		s.dust_color = r[10]
		s.particle = r[11]
		s.sound = r[12]
		s.skidmarks = r[13]
		_save(s, "res://data/surfaces/%s.tres" % r[0])


func _car(id: String, name: String, maker: String, category: String, year: int, engine: String) -> CarDefinition:
	var d := CarDefinition.new()
	d.id = StringName(id)
	d.display_name = name
	d.maker = maker
	d.category = category
	d.year = year
	d.engine_label = engine
	d.model_path = "res://assets/imported/cars/%s.glb" % id
	return d


func _finish_car(d: CarDefinition, top_kmh: float, radius: float, first_gear: float, gears: int) -> void:
	## Derives gearing and drag from a target top speed so that each car is consistent.
	d.wheel_radius_front = radius if d.wheel_radius_front <= 0.0 else d.wheel_radius_front
	d.wheel_radius_rear = radius if d.wheel_radius_rear <= 0.0 else d.wheel_radius_rear
	var r := d.wheel_radius_rear
	var v_top := top_kmh / 3.6
	var n := gears
	# top gear reaches redline slightly above the drag-limited top speed
	var top_total := d.redline_rpm * TAU / 60.0 * r / (v_top * 1.03)
	var top_ratio := top_total / d.final_drive
	var ratios := PackedFloat32Array()
	for i in n:
		var t := float(i) / float(n - 1)
		# progressive gearbox: bigger steps in low gears
		var g := first_gear * pow(top_ratio / first_gear, pow(t, 0.85))
		ratios.append(snappedf(g, 0.01))
	d.gear_ratios = ratios
	d.reverse_ratio = snappedf(first_gear * 0.95, 0.01)
	var p := d.peak_power_kw() * 1000.0 * d.drivetrain_efficiency
	var rolling := 0.013 * d.mass * 9.81 * v_top
	d.drag_area = snappedf(maxf((p * 0.97 - rolling) / (0.5 * 1.225 * pow(v_top, 3.0)), 0.25), 0.001)
	d.power_kw = snappedf(d.peak_power_kw(), 1.0)
	d.top_speed_kmh = top_kmh
	var pw := d.power_kw / (d.mass / 1000.0)
	var grip := (d.grip_front + d.grip_rear) * 0.5 * d.tire_grip
	d.performance_index = clampi(int(130.0 + pw * 1.2 + grip * 260.0 + top_kmh * 0.55 + d.downforce_area * 120.0), 100, 998)
	d.performance_class = _class_for(d.performance_index)


func _class_for(pi: int) -> String:
	if pi <= 500:
		return "D"
	if pi <= 600:
		return "C"
	if pi <= 700:
		return "B"
	if pi <= 800:
		return "A"
	if pi <= 900:
		return "S1"
	return "S2"


func _cars() -> void:
	var list: Array[CarDefinition] = []
	var gears := 6

	# 1 — compact hot hatch (FWD)
	var d := _car("01_pico_furia", "Pico Furia R", "Pico", "Hot Hatch", 2021, "1.6 Turbo I4")
	d.description = "Short, eager and loud. A front-driven hot hatch that loves tight valley roads."
	d.drivetrain = CarDefinition.Drivetrain.FWD
	d.mass = 1190.0
	d.com_offset = Vector3(0.0, 0.12, -0.18)
	d.max_torque_nm = 300.0
	d.torque_curve = PackedFloat32Array(TQ_TURBO_I4)
	d.idle_rpm = 950.0
	d.redline_rpm = 6900.0
	d.turbo = true
	d.turbo_lag = 0.45
	gears = 6
	d.final_drive = 4.1
	d.diff_lock = 0.45
	d.tire_grip = 1.02
	d.grip_front = 1.0
	d.grip_rear = 1.02
	d.spring_hz_front = 1.95
	d.spring_hz_rear = 2.1
	d.anti_roll_front = 20000.0
	d.anti_roll_rear = 18000.0
	d.brake_torque = 2400.0
	d.steer_lock_deg = 35.0
	d.downforce_area = 0.1
	d.cylinders = 4
	d.engine_tone = 1.15
	d.engine_roughness = 0.35
	d.exhaust_pop = 0.6
	d.default_color = Color(0.85, 0.12, 0.08)
	d.default_finish = CarDefinition.Finish.GLOSS
	_finish_car(d, 228.0, 0.31, 3.45, gears)
	list.append(d)

	# 2 — everyday sedan (FWD)
	d = _car("02_alder_sedan", "Alder Sedan 2.0", "Alder", "Sedan", 2019, "2.0 I4")
	d.description = "Comfortable family sedan. Soft, predictable and surprisingly willing."
	d.drivetrain = CarDefinition.Drivetrain.FWD
	d.mass = 1430.0
	d.com_offset = Vector3(0.0, 0.16, -0.15)
	d.max_torque_nm = 215.0
	d.torque_curve = PackedFloat32Array(TQ_NA_I4)
	d.redline_rpm = 6300.0
	gears = 6
	d.final_drive = 3.85
	d.diff_lock = 0.1
	d.tire_grip = 0.94
	d.spring_hz_front = 1.45
	d.spring_hz_rear = 1.55
	d.damping_bump = 0.28
	d.damping_rebound = 0.48
	d.anti_roll_front = 15000.0
	d.anti_roll_rear = 9000.0
	d.brake_torque = 2300.0
	d.steer_lock_deg = 36.0
	d.downforce_area = 0.0
	d.cylinders = 4
	d.engine_tone = 0.95
	d.engine_roughness = 0.2
	d.exhaust_pop = 0.0
	d.default_color = Color(0.25, 0.32, 0.4)
	d.default_finish = CarDefinition.Finish.METALLIC
	_finish_car(d, 205.0, 0.32, 3.6, gears)
	list.append(d)

	# 3 — classic muscle car (RWD, tail-happy)
	d = _car("03_brutus_fastback", "Brutus 427 Fastback", "Brutus", "Muscle", 1969, "7.0 V8")
	d.description = "Big-block brawler from another era. Huge torque, skinny grip, smoke on demand."
	d.drivetrain = CarDefinition.Drivetrain.RWD
	d.mass = 1590.0
	d.com_offset = Vector3(0.0, 0.2, -0.12)
	d.inertia_scale = Vector3(1.0, 0.95, 1.0)
	d.max_torque_nm = 640.0
	d.torque_curve = PackedFloat32Array(TQ_BIG_V8)
	d.idle_rpm = 750.0
	d.redline_rpm = 6000.0
	d.engine_inertia = 0.3
	gears = 4
	d.final_drive = 3.55
	d.diff_lock = 0.42
	d.tire_grip = 0.92
	d.grip_front = 1.02
	d.grip_rear = 0.9
	d.slide_ratio = 0.78
	d.spring_hz_front = 1.4
	d.spring_hz_rear = 1.5
	d.damping_bump = 0.26
	d.damping_rebound = 0.42
	d.anti_roll_front = 18000.0
	d.anti_roll_rear = 7000.0
	d.brake_torque = 2750.0
	d.brake_bias = 0.62
	d.steer_lock_deg = 33.0
	d.downforce_area = 0.0
	d.frontal_lift = 0.05
	d.cylinders = 8
	d.engine_tone = 0.62
	d.engine_roughness = 0.75
	d.exhaust_pop = 0.8
	d.default_color = Color(0.9, 0.55, 0.05)
	d.default_finish = CarDefinition.Finish.GLOSS
	_finish_car(d, 222.0, 0.34, 2.6, gears)
	list.append(d)

	# 4 — sports coupe (RWD)
	d = _car("04_kaze_coupe", "Kaze S Coupe", "Kaze", "Sports Coupe", 2022, "3.0 Turbo I6")
	d.description = "Balanced front-engine, rear-drive coupe. Precise, playful and quick."
	d.drivetrain = CarDefinition.Drivetrain.RWD
	d.mass = 1340.0
	d.com_offset = Vector3(0.0, 0.1, -0.05)
	d.max_torque_nm = 470.0
	d.torque_curve = PackedFloat32Array(TQ_I6_TURBO)
	d.redline_rpm = 7300.0
	d.turbo = true
	d.turbo_lag = 0.4
	gears = 6
	d.final_drive = 3.46
	d.diff_lock = 0.55
	d.tire_grip = 1.08
	d.grip_front = 1.0
	d.grip_rear = 1.0
	d.spring_hz_front = 2.1
	d.spring_hz_rear = 2.2
	d.anti_roll_front = 26000.0
	d.anti_roll_rear = 17000.0
	d.brake_torque = 2900.0
	d.steer_lock_deg = 34.0
	d.downforce_area = 0.22
	d.cylinders = 6
	d.engine_tone = 1.0
	d.engine_roughness = 0.3
	d.exhaust_pop = 0.7
	d.default_color = Color(0.95, 0.95, 0.97)
	d.default_finish = CarDefinition.Finish.PEARL
	_finish_car(d, 262.0, 0.325, 3.3, gears)
	list.append(d)

	# 5 — grand tourer (front-engine, fast, stable)
	d = _car("05_meridian_gt", "Meridian GT V12", "Meridian", "Grand Tourer", 2023, "6.5 V12")
	d.description = "Long-legged V12 grand tourer. Effortless speed and rock-solid stability."
	d.drivetrain = CarDefinition.Drivetrain.RWD
	d.mass = 1740.0
	d.com_offset = Vector3(0.0, 0.08, -0.1)
	d.inertia_scale = Vector3(1.05, 1.12, 1.0)
	d.max_torque_nm = 720.0
	d.torque_curve = PackedFloat32Array(TQ_V12)
	d.idle_rpm = 850.0
	d.redline_rpm = 7400.0
	d.engine_inertia = 0.25
	gears = 7
	d.final_drive = 3.2
	d.diff_lock = 0.5
	d.tire_grip = 1.12
	d.grip_front = 1.0
	d.grip_rear = 1.05
	d.spring_hz_front = 1.9
	d.spring_hz_rear = 2.0
	d.anti_roll_front = 30000.0
	d.anti_roll_rear = 22000.0
	d.brake_torque = 3800.0
	d.steer_lock_deg = 32.0
	d.steer_high_speed_deg = 3.4
	d.downforce_area = 0.42
	d.cylinders = 12
	d.engine_tone = 0.9
	d.engine_roughness = 0.15
	d.exhaust_pop = 0.4
	d.default_color = Color(0.08, 0.2, 0.15)
	d.default_finish = CarDefinition.Finish.METALLIC
	_finish_car(d, 318.0, 0.35, 3.15, gears)
	list.append(d)

	# 6 — mid-engine supercar (AWD)
	d = _car("06_volta_x9", "Volta X9", "Volta", "Supercar", 2024, "5.2 V10")
	d.description = "Mid-engine, all-wheel-drive missile with active aero. The fastest car in the festival."
	d.drivetrain = CarDefinition.Drivetrain.AWD
	d.awd_front_split = 0.32
	d.mass = 1500.0
	d.com_offset = Vector3(0.0, 0.02, 0.12)
	d.inertia_scale = Vector3(0.95, 0.92, 0.9)
	d.max_torque_nm = 760.0
	d.torque_curve = PackedFloat32Array(TQ_V10)
	d.idle_rpm = 1000.0
	d.redline_rpm = 8600.0
	d.engine_inertia = 0.16
	gears = 7
	d.final_drive = 3.3
	d.diff_lock = 0.55
	d.tire_grip = 1.22
	d.grip_front = 1.0
	d.grip_rear = 1.04
	d.spring_hz_front = 2.5
	d.spring_hz_rear = 2.6
	d.travel_up = 0.07
	d.travel_down = 0.09
	d.anti_roll_front = 34000.0
	d.anti_roll_rear = 28000.0
	d.brake_torque = 4400.0
	d.brake_bias = 0.62
	d.steer_lock_deg = 31.0
	d.steer_high_speed_deg = 3.2
	d.downforce_area = 0.85
	d.aero_balance = 0.42
	d.wheel_radius_front = 0.335
	d.wheel_radius_rear = 0.35
	d.cylinders = 10
	d.engine_tone = 1.3
	d.engine_roughness = 0.25
	d.exhaust_pop = 0.9
	d.default_color = Color(0.1, 0.55, 0.15)
	d.default_finish = CarDefinition.Finish.PEARL
	_finish_car(d, 342.0, 0.35, 3.1, gears)
	list.append(d)

	# 7 — rally car (AWD, great on gravel/dirt)
	d = _car("07_gravelo_rs", "Gravelo RS Rally", "Gravelo", "Rally", 2020, "2.0 Turbo I4")
	d.description = "Stage-bred rally weapon. Long travel, short gears and grip on any surface."
	d.drivetrain = CarDefinition.Drivetrain.AWD
	d.awd_front_split = 0.45
	d.mass = 1320.0
	d.com_offset = Vector3(0.0, 0.14, -0.05)
	d.max_torque_nm = 450.0
	d.torque_curve = PackedFloat32Array(TQ_TURBO_I4)
	d.redline_rpm = 7600.0
	d.turbo = true
	d.turbo_lag = 0.35
	gears = 6
	d.final_drive = 4.4
	d.diff_lock = 0.6
	d.tire_grip = 1.0
	d.offroad_grip = 1.4
	d.slide_ratio = 0.82
	d.spring_hz_front = 1.7
	d.spring_hz_rear = 1.75
	d.travel_up = 0.12
	d.travel_down = 0.16
	d.anti_roll_front = 20000.0
	d.anti_roll_rear = 16000.0
	d.brake_torque = 2900.0
	d.handbrake_torque = 3200.0
	d.brake_bias = 0.6
	d.steer_lock_deg = 38.0
	d.steer_speed = 3.8
	d.downforce_area = 0.3
	d.cylinders = 4
	d.engine_tone = 1.2
	d.engine_roughness = 0.5
	d.exhaust_pop = 1.0
	d.default_color = Color(0.1, 0.25, 0.75)
	d.default_finish = CarDefinition.Finish.GLOSS
	_finish_car(d, 205.0, 0.32, 3.2, gears)
	list.append(d)

	# 8 — off-road SUV (tall suspension)
	d = _car("08_tundrax_4x4", "Tundrax 4x4", "Tundrax", "Off-Road SUV", 2022, "4.4 V8")
	d.description = "Tall, tough off-roader. Long-travel suspension shrugs off rocks, ruts and riverbeds."
	d.drivetrain = CarDefinition.Drivetrain.AWD
	d.awd_front_split = 0.45
	d.mass = 2180.0
	d.com_offset = Vector3(0.0, 0.32, -0.05)
	d.inertia_scale = Vector3(1.05, 1.05, 1.1)
	d.max_torque_nm = 560.0
	d.torque_curve = PackedFloat32Array(TQ_TRUCK_V8)
	d.idle_rpm = 700.0
	d.redline_rpm = 5900.0
	d.engine_inertia = 0.3
	gears = 6
	d.final_drive = 3.9
	d.diff_lock = 0.65
	d.tire_grip = 0.92
	d.offroad_grip = 1.35
	d.slide_ratio = 0.8
	d.load_sensitivity = 0.1
	d.spring_hz_front = 1.3
	d.spring_hz_rear = 1.35
	d.damping_bump = 0.3
	d.damping_rebound = 0.5
	d.travel_up = 0.16
	d.travel_down = 0.22
	d.anti_roll_front = 26000.0
	d.anti_roll_rear = 19000.0
	d.brake_torque = 3400.0
	d.steer_lock_deg = 36.0
	d.downforce_area = 0.0
	d.cylinders = 8
	d.engine_tone = 0.7
	d.engine_roughness = 0.55
	d.exhaust_pop = 0.2
	d.default_color = Color(0.32, 0.36, 0.22)
	d.default_finish = CarDefinition.Finish.MATTE
	_finish_car(d, 192.0, 0.4, 3.9, gears)
	list.append(d)

	# 9 — pickup truck (heavy, body roll)
	d = _car("09_haulmark_p30", "Haulmark P30", "Haulmark", "Pickup", 2018, "5.7 V8")
	d.description = "Heavy work truck with a lazy V8. Leans in corners, never quits."
	d.drivetrain = CarDefinition.Drivetrain.RWD
	d.mass = 2280.0
	d.com_offset = Vector3(0.0, 0.34, -0.3)
	d.inertia_scale = Vector3(1.1, 1.1, 1.05)
	d.max_torque_nm = 540.0
	d.torque_curve = PackedFloat32Array(TQ_TRUCK_V8)
	d.idle_rpm = 650.0
	d.redline_rpm = 5600.0
	d.engine_inertia = 0.32
	gears = 6
	d.final_drive = 3.7
	d.diff_lock = 0.25
	d.tire_grip = 0.9
	d.offroad_grip = 1.15
	d.grip_rear = 0.95
	d.spring_hz_front = 1.2
	d.spring_hz_rear = 1.35
	d.damping_bump = 0.24
	d.damping_rebound = 0.4
	d.travel_up = 0.14
	d.travel_down = 0.18
	d.anti_roll_front = 14000.0
	d.anti_roll_rear = 6000.0
	d.brake_torque = 3300.0
	d.steer_lock_deg = 37.0
	d.steer_speed = 2.6
	d.downforce_area = 0.0
	d.cylinders = 8
	d.engine_tone = 0.6
	d.engine_roughness = 0.6
	d.exhaust_pop = 0.1
	d.default_color = Color(0.55, 0.08, 0.06)
	d.default_finish = CarDefinition.Finish.METALLIC
	_finish_car(d, 186.0, 0.39, 3.5, gears)
	list.append(d)

	# 10 — vintage roadster (light, slow, charming)
	d = _car("10_libella_spider", "Libella Spider '58", "Libella", "Vintage Roadster", 1958, "1.5 I4")
	d.description = "Featherweight open roadster from the golden age. Slow, honest and pure joy."
	d.drivetrain = CarDefinition.Drivetrain.RWD
	d.mass = 840.0
	d.com_offset = Vector3(0.0, 0.12, 0.0)
	d.max_torque_nm = 135.0
	d.torque_curve = PackedFloat32Array(TQ_VINTAGE)
	d.idle_rpm = 800.0
	d.redline_rpm = 6100.0
	d.engine_inertia = 0.12
	gears = 4
	d.final_drive = 4.3
	d.diff_lock = 0.1
	d.tire_grip = 0.86
	d.slide_ratio = 0.8
	d.slip_angle_peak_deg = 8.0
	d.spring_hz_front = 1.5
	d.spring_hz_rear = 1.55
	d.anti_roll_front = 9000.0
	d.anti_roll_rear = 4000.0
	d.brake_torque = 1500.0
	d.steer_lock_deg = 36.0
	d.steer_speed = 2.8
	d.downforce_area = 0.0
	d.wheel_mass = 14.0
	d.cylinders = 4
	d.engine_tone = 1.05
	d.engine_roughness = 0.45
	d.exhaust_pop = 0.3
	d.default_color = Color(0.62, 0.8, 0.85)
	d.default_finish = CarDefinition.Finish.GLOSS
	_finish_car(d, 168.0, 0.3, 3.6, gears)
	list.append(d)

	for c in list:
		_save(c, "res://data/cars/%s.tres" % c.id)
		print("    %s  %s  %.0f kW  CdA %.3f  gears %s  PI %d (%s)" % [c.id, c.display_name, c.power_kw, c.drag_area, c.gear_ratios, c.performance_index, c.performance_class])


func _upgrades() -> void:
	# part, level, name, description, {field: value}
	var rows := [
		["engine", 1, "Street Intake & Exhaust", "Freer-flowing intake and exhaust.", {"torque_mult": 1.07, "redline_add": 100.0}],
		["engine", 2, "Sport Cams & Tune", "Hotter cams and an aggressive engine map.", {"torque_mult": 1.08, "redline_add": 150.0}],
		["engine", 3, "Race Build", "Forged internals and race ECU.", {"torque_mult": 1.1, "redline_add": 200.0, "mass_mult": 0.99}],
		["tires", 1, "Sport Compound", "Stickier road compound.", {"grip_mult": 1.04}],
		["tires", 2, "Semi-Slick", "Track-day rubber; a little worse off-road.", {"grip_mult": 1.05, "offroad_mult": 0.96}],
		["tires", 3, "Race Slick", "Maximum tarmac grip; poor on loose ground.", {"grip_mult": 1.06, "offroad_mult": 0.9}],
		["suspension", 1, "Sport Springs", "Firmer springs and thicker anti-roll bars.", {"spring_mult": 1.07, "arb_mult": 1.1}],
		["suspension", 2, "Coilovers", "Adjustable coilovers.", {"spring_mult": 1.07, "arb_mult": 1.1}],
		["suspension", 3, "Race Suspension", "Stiff race geometry.", {"spring_mult": 1.08, "arb_mult": 1.15}],
		["brakes", 1, "Sport Pads", "Higher-friction pads.", {"brake_mult": 1.1}],
		["brakes", 2, "Big Brake Kit", "Larger discs and calipers.", {"brake_mult": 1.1}],
		["brakes", 3, "Race Brakes", "Carbon-ceramic race brakes.", {"brake_mult": 1.12, "mass_mult": 0.995}],
		["weight", 1, "Interior Strip", "Lighter seats and trim.", {"mass_mult": 0.97}],
		["weight", 2, "Light Panels", "Composite bonnet and boot.", {"mass_mult": 0.96}],
		["weight", 3, "Race Shell", "Carbon panels and polycarbonate glass.", {"mass_mult": 0.95}],
		["aero", 1, "Lip & Spoiler", "Small front lip and rear spoiler.", {"downforce_add": 0.12, "drag_mult": 1.02}],
		["aero", 2, "Splitter & Wing", "Adjustable splitter and wing.", {"downforce_add": 0.18, "drag_mult": 1.03}],
		["aero", 3, "Race Aero", "Full race aero package.", {"downforce_add": 0.25, "drag_mult": 1.04}],
	]
	for r in rows:
		var u := UpgradeDef.new()
		u.part = r[0]
		u.level = r[1]
		u.display_name = r[2]
		u.description = r[3]
		var fx: Dictionary = r[4]
		for k in fx:
			u.set(k, fx[k])
		u.price = 4000 * int(r[1]) * int(r[1])
		_save(u, "res://data/upgrades/%s_%d.tres" % [r[0], r[1]])


func _traffic() -> void:
	# id, name, mass, torque, redline, drive, gears, top kmh, radius, spring hz, grip, tq curve
	var rows := [
		["t_compact", "Civic Compact", 1080.0, 165.0, 6200.0, CarDefinition.Drivetrain.FWD, 5, 175.0, 0.3, 1.5, 0.95, TQ_NA_I4],
		["t_van", "Delivery Van", 2150.0, 330.0, 4600.0, CarDefinition.Drivetrain.RWD, 6, 150.0, 0.35, 1.35, 0.9, TQ_TRUCK_V8],
		["t_lorry", "Box Lorry", 7600.0, 950.0, 2600.0, CarDefinition.Drivetrain.RWD, 6, 100.0, 0.5, 1.25, 0.85, TQ_TRUCK_V8],
		["t_bus", "Coach", 11500.0, 1500.0, 2400.0, CarDefinition.Drivetrain.RWD, 6, 105.0, 0.52, 1.2, 0.85, TQ_TRUCK_V8],
		["t_tractor", "Farm Tractor", 4200.0, 700.0, 2300.0, CarDefinition.Drivetrain.RWD, 4, 40.0, 0.8, 1.6, 1.0, TQ_TRUCK_V8],
		["t_pickup", "Work Pickup", 1950.0, 400.0, 5200.0, CarDefinition.Drivetrain.RWD, 6, 170.0, 0.38, 1.35, 0.9, TQ_TRUCK_V8],
	]
	for r in rows:
		var d := CarDefinition.new()
		d.id = StringName(r[0])
		d.display_name = r[1]
		d.category = "Traffic"
		d.model_path = "res://assets/imported/traffic/%s.glb" % r[0]
		d.mass = r[2]
		d.max_torque_nm = r[3]
		d.redline_rpm = r[4]
		d.idle_rpm = minf(800.0, r[4] * 0.3)
		d.drivetrain = r[5]
		d.torque_curve = PackedFloat32Array(r[11])
		d.spring_hz_front = r[9]
		d.spring_hz_rear = r[9] + 0.1
		d.tire_grip = r[10]
		d.com_offset = Vector3(0.0, 0.25 if r[2] > 3000.0 else 0.12, 0.0)
		d.brake_torque = r[2] * 2.6
		d.handbrake_torque = r[2] * 1.5
		d.anti_roll_front = r[2] * 14.0
		d.anti_roll_rear = r[2] * 10.0
		d.travel_up = 0.1 if r[2] < 3000.0 else 0.12
		d.travel_down = 0.14 if r[2] < 3000.0 else 0.16
		d.steer_lock_deg = 36.0
		d.wheel_mass = 20.0 if r[2] < 3000.0 else 60.0
		_finish_car(d, r[7], r[8], 3.5, r[6])
		_save(d, "res://data/traffic/%s.tres" % r[0])
