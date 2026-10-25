extends SceneTree
## Generates res://data/cars/*.tres from the table below (reproducible handling data).
## godot --headless --path . --script res://tools/make_car_defs.gd

# id, name, maker, class, pi, drive, mass, torque, torque_rpm, redline, top_kmh, wheel_r, sag, grip, loose, B,
# steer, cyl, pitch, rough, paint, finish, downforce, gears, desc, turbo, arb_f, arb_r, brake, falloff, year
const D := CarDef.Drive
const TABLE: Array = [
	["hatch", "Pico GTi", "Velora", "C", 565, D.FWD, 1090.0, 270.0, 4600.0, 7200.0, 212.0, 0.31, 0.075, 1.04, 1.0, 9.5, 36.0, 4, 1.15, 0.25, Color(0.85, 0.12, 0.1), 0, 0.3, [3.3, 2.05, 1.5, 1.18, 0.96, 0.8], "Nimble front-drive hot hatch. Darts into corners, forgiving at the limit.", true, 20000.0, 14000.0, 10000.0, 0.55, 2019],
	["sedan", "Meridian Touring", "Aster Motors", "B", 610, D.RWD, 1480.0, 360.0, 4200.0, 6800.0, 232.0, 0.33, 0.09, 1.02, 0.95, 8.8, 34.0, 6, 1.0, 0.18, Color(0.18, 0.28, 0.42), 1, 0.4, [3.6, 2.2, 1.55, 1.2, 1.0, 0.82, 0.68], "Comfortable rear-drive saloon with a silky straight-six.", true, 18000.0, 12000.0, 12000.0, 0.5, 2021],
	["muscle", "Thunderhawk 440", "Brannock", "A", 715, D.RWD, 1660.0, 640.0, 3800.0, 6100.0, 258.0, 0.34, 0.09, 0.98, 0.9, 7.2, 32.0, 8, 0.7, 0.75, Color(0.95, 0.62, 0.05), 0, 0.2, [2.6, 1.75, 1.32, 1.0], "Big-block V8 muscle. Huge torque, light rear end, loves to step out.", false, 16000.0, 8000.0, 12500.0, 0.6, 1970],
	["coupe", "Kestrel S", "Sakura Line", "A", 745, D.RWD, 1290.0, 420.0, 5600.0, 8200.0, 262.0, 0.33, 0.07, 1.1, 0.92, 9.8, 35.0, 4, 1.25, 0.3, Color(0.92, 0.92, 0.95), 0, 0.9, [3.2, 2.15, 1.62, 1.3, 1.07, 0.88], "High-revving rear-drive coupe, balanced and precise. A drift favourite.", true, 22000.0, 15000.0, 12000.0, 0.62, 2004],
	["gt", "Corsair GT", "Halden", "S1", 845, D.RWD, 1720.0, 720.0, 5200.0, 7400.0, 318.0, 0.35, 0.075, 1.12, 0.88, 9.0, 32.0, 12, 0.95, 0.12, Color(0.08, 0.32, 0.18), 1, 1.4, [3.1, 2.1, 1.6, 1.3, 1.08, 0.9, 0.74], "Front-engine V12 grand tourer. Devastating top speed, rock stable.", false, 26000.0, 18000.0, 16000.0, 0.65, 2023],
	["super", "Vortice R", "Moretti Fabbrica", "S2", 935, D.AWD, 1460.0, 790.0, 6400.0, 8900.0, 348.0, 0.35, 0.06, 1.22, 0.85, 10.5, 30.0, 10, 1.3, 0.3, Color(0.75, 0.82, 0.1), 0, 2.4, [3.4, 2.35, 1.8, 1.45, 1.2, 1.0, 0.84], "Mid-engine all-wheel-drive hypercar. Brutal launches, huge downforce.", false, 30000.0, 22000.0, 19000.0, 0.7, 2025],
	["rally", "Torrent RS", "Nordvik", "A", 760, D.AWD, 1260.0, 440.0, 4400.0, 7600.0, 226.0, 0.33, 0.11, 1.02, 1.38, 8.5, 38.0, 4, 1.1, 0.5, Color(0.1, 0.35, 0.85), 0, 0.8, [3.0, 2.2, 1.7, 1.38, 1.15, 0.98], "Turbo AWD rally weapon. Unmatched on gravel and dirt.", true, 16000.0, 12000.0, 11500.0, 0.55, 2012],
	["suv", "Ridgeback 4x4", "Atlas Overland", "B", 625, D.AWD, 2120.0, 560.0, 3400.0, 5900.0, 196.0, 0.42, 0.15, 0.94, 1.28, 7.5, 34.0, 8, 0.75, 0.55, Color(0.38, 0.4, 0.3), 2, 0.1, [4.0, 2.4, 1.55, 1.15, 0.9, 0.75], "Long-travel off-roader. Shrugs off rough tracks, rolls in fast corners.", true, 14000.0, 10000.0, 15000.0, 0.5, 2018],
	["pickup", "Hauler V8", "Brannock", "C", 585, D.RWD, 2280.0, 610.0, 3300.0, 5600.0, 188.0, 0.41, 0.14, 0.92, 1.1, 7.0, 33.0, 8, 0.65, 0.65, Color(0.62, 0.08, 0.08), 0, 0.0, [3.2, 2.0, 1.4, 1.0, 0.8], "Heavy rear-drive pickup truck. Torquey, loose rear, lots of body roll.", false, 9000.0, 6000.0, 15000.0, 0.55, 1996],
	["roadster", "Aurelia 1600", "Lucent", "D", 380, D.RWD, 830.0, 145.0, 4200.0, 6600.0, 168.0, 0.31, 0.1, 0.92, 0.95, 8.0, 38.0, 4, 1.05, 0.45, Color(0.55, 0.78, 0.82), 0, 0.0, [3.5, 2.2, 1.45, 1.0], "Charming vintage roadster. Light, slow and wonderfully playful.", false, 9000.0, 5000.0, 7000.0, 0.5, 1962],
]


func _init() -> void:
	DirAccess.make_dir_recursive_absolute("res://data/cars")
	for row in TABLE:
		var c := CarDef.new()
		c.id = row[0]
		c.display_name = row[1]
		c.maker = row[2]
		c.car_class = row[3]
		c.pi = row[4]
		c.drive = row[5]
		c.mass = row[6]
		c.peak_torque = row[7]
		c.peak_torque_rpm = row[8]
		c.redline = row[9]
		c.top_speed_kmh = row[10]
		var r: float = row[11]
		var sag: float = row[12]
		c.grip = row[13]
		c.loose_grip = row[14]
		c.lateral_stiffness = row[15]
		c.steer_lock = row[16]
		c.cylinders = row[17]
		c.sound_pitch = row[18]
		c.sound_rough = row[19]
		c.paint_color = row[20]
		c.paint_finish = row[21]
		c.downforce = row[22]
		c.gears = PackedFloat32Array(row[23])
		c.description = row[24]
		c.turbo = row[25]
		c.arb_front = row[26]
		c.arb_rear = row[27]
		c.brake_force = row[28]
		c.torque_falloff = row[29]
		c.year = row[30]
		c.model_path = "res://assets/imported/cars/%s.glb" % c.id
		c.idle_rpm = 800.0 if c.cylinders < 8 else 700.0
		# final drive so that top gear reaches the target top speed slightly below the redline
		var v_top: float = c.top_speed_kmh / 3.6
		var top_gear: float = c.gears[c.gears.size() - 1]
		c.final_drive = (c.redline * 0.97 * TAU / 60.0) * r / (v_top * 1.02 * top_gear)
		var corner: float = c.mass * 0.25
		c.spring = corner * 9.81 / sag
		var crit: float = 2.0 * sqrt(c.spring * corner)
		c.damper_bump = crit * 0.32
		c.damper_rebound = crit * 0.48
		c.rest_length = clampf(sag * 2.6 + 0.12, 0.28, 0.55)
		c.com_offset = Vector3(0, -0.2 if row[0] != "suv" and row[0] != "pickup" else -0.1, 0.05 if c.drive == D.FWD else (-0.1 if row[0] == "super" else 0.0))
		c.aero_balance = 0.45
		c.brake_bias = 0.6 if row[0] != "super" else 0.56
		c.steer_speed_reduction = 0.7
		c.rim_color = Color(0.78, 0.79, 0.8) if row[0] != "rally" else Color(0.95, 0.95, 0.95)
		var err: int = ResourceSaver.save(c, "res://data/cars/%s.tres" % c.id)
		print("%s  fd=%.2f spring=%.0f  kW=%.0f  err=%d" % [c.id, c.final_drive, c.spring, c.peak_power_kw(), err])
	quit()
