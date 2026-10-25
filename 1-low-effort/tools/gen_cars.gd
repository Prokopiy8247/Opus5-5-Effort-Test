extends SceneTree
## Regenerates res://data/cars/*.tres from the table below.
## Run: godot --headless --path . --script tools/gen_cars.gd

const T := [
	# id, name, category, mass, kw, peak, red, gears, final, drive, top, grip, offroad, freq, travel, df, brake, lock, voice, cyl, turbo, colour, finish
	["car01_kestrel", "Kestrel GTi", "Hot Hatch", 1180.0, 165.0, 6200.0, 7200.0, [3.3, 2.1, 1.55, 1.2, 0.98, 0.82], 4.1, 0, 228.0, 1.12, 0.82, 2.1, 0.2, 0.25, 10500.0, 36.0, 1.25, 4, true, Color(0.85, 0.12, 0.08), 0],
	["car02_meridian", "Meridian Saloon", "Sedan", 1450.0, 140.0, 5600.0, 6500.0, [3.6, 2.2, 1.5, 1.12, 0.9, 0.74], 3.7, 1, 210.0, 1.02, 0.85, 1.6, 0.22, 0.15, 10000.0, 34.0, 0.9, 4, false, Color(0.15, 0.22, 0.38), 2],
	["car03_ironhorse", "Ironhorse 440", "Muscle", 1620.0, 320.0, 5200.0, 6200.0, [2.9, 1.9, 1.35, 1.0, 0.8], 3.4, 1, 262.0, 1.0, 0.75, 1.5, 0.22, 0.2, 11500.0, 33.0, 0.62, 8, false, Color(0.95, 0.65, 0.05), 0],
	["car04_arrow", "Arrow S", "Sports Coupe", 1290.0, 245.0, 7200.0, 8200.0, [3.2, 2.15, 1.6, 1.28, 1.05, 0.88], 4.0, 1, 258.0, 1.2, 0.78, 2.2, 0.18, 0.45, 12500.0, 35.0, 1.1, 6, false, Color(0.1, 0.55, 0.85), 2],
	["car05_solstice", "Solstice GT", "Grand Tourer", 1680.0, 390.0, 6500.0, 7400.0, [3.0, 2.0, 1.45, 1.12, 0.9, 0.75, 0.63], 3.5, 1, 305.0, 1.22, 0.75, 1.8, 0.18, 0.65, 14500.0, 32.0, 0.8, 12, false, Color(0.2, 0.2, 0.22), 2],
	["car06_vortex", "Vortex R", "Supercar", 1420.0, 560.0, 7800.0, 8800.0, [3.1, 2.15, 1.65, 1.32, 1.08, 0.9, 0.76], 3.6, 2, 340.0, 1.38, 0.7, 2.6, 0.14, 1.1, 17000.0, 31.0, 1.0, 10, true, Color(0.55, 0.9, 0.1), 0],
	["car07_dustrunner", "Dustrunner WRC", "Rally", 1250.0, 240.0, 6000.0, 7500.0, [3.2, 2.2, 1.65, 1.3, 1.05, 0.88], 4.4, 2, 215.0, 1.15, 1.08, 1.7, 0.28, 0.4, 12000.0, 38.0, 1.15, 4, true, Color(0.95, 0.95, 0.95), 0],
	["car08_ridgeback", "Ridgeback 4x4", "Off-road SUV", 2050.0, 230.0, 5000.0, 6000.0, [4.0, 2.4, 1.6, 1.2, 0.95, 0.78], 3.9, 2, 195.0, 0.95, 1.12, 1.35, 0.34, 0.1, 13000.0, 34.0, 0.7, 6, true, Color(0.35, 0.42, 0.25), 1],
	["car09_haulmark", "Haulmark 2500", "Pickup", 2300.0, 280.0, 4800.0, 5800.0, [3.8, 2.3, 1.5, 1.1, 0.85, 0.7], 3.7, 1, 200.0, 0.92, 0.95, 1.25, 0.3, 0.08, 13500.0, 33.0, 0.55, 8, false, Color(0.55, 0.08, 0.08), 2],
	["car10_breeze", "Breeze Roadster '58", "Vintage Roadster", 880.0, 75.0, 5200.0, 6000.0, [3.5, 2.1, 1.4, 1.0], 4.0, 1, 165.0, 0.95, 0.8, 1.5, 0.22, 0.0, 7000.0, 36.0, 1.4, 4, false, Color(0.55, 0.85, 0.8), 0],
]

func _init() -> void:
	DirAccess.make_dir_recursive_absolute("res://data/cars")
	for row in T:
		var s := CarSpec.new()
		s.id = row[0]; s.display_name = row[1]; s.category = row[2]
		s.glb_path = "res://assets/imported/vehicles/%s.glb" % row[0]
		s.mass = row[3]; s.power_kw = row[4]; s.peak_rpm = row[5]; s.redline = row[6]
		s.gear_ratios = PackedFloat32Array(row[7]); s.final_drive = row[8]; s.drivetrain = row[9]
		s.top_speed_kmh = row[10]; s.grip = row[11]; s.offroad_grip = row[12]; s.susp_freq = row[13]
		s.susp_travel = row[14]; s.downforce = row[15]; s.brake_force = row[16]; s.steer_lock_deg = row[17]
		s.engine_voice = row[18]; s.cylinders = row[19]; s.turbo = row[20]; s.base_color = row[21]; s.finish = row[22]
		s.anti_roll = s.mass * 6.0
		s.com_offset = Vector3(0, -0.12 - s.susp_travel * 0.3, 0)
		var err := ResourceSaver.save(s, "res://data/cars/%s.tres" % s.id)
		print(s.id, " ", s.class_rating(), " err=", err)
	quit()
