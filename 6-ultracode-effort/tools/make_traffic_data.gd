extends SceneTree
## Generates the civilian traffic vehicle types (res://data/traffic/<id>.tres).
##   Godot_console.exe --headless --path <project> --script res://tools/make_traffic_data.gd
## Road classes: 0 highway, 1 regional, 2 mountain, 3 street. Regions: 0 vale, 1 highlands, 2 mesa, 3 coast.

const DATA_SCRIPT := preload("res://scripts/traffic/traffic_vehicle_data.gd")

const TYPES := [
	{"id": "hatch_small", "name": "City Hatch", "mass": 1050.0, "len": 3.9, "w": 1.72, "h": 1.5, "wb": 2.45, "wr": 0.30,
	 "com": 0.52, "fwd": true, "vmax": 155.0, "acc": 2.2, "dec": 3.2, "kw": 70.0, "cg": 0.30, "gap": 1.8, "lf": 1.0,
	 "classes": [0, 1, 2, 3], "regions": [], "weight": 0.40, "horn": 520.0, "finishes": [0, 2],
	 "paints": ["red", "blue", "white", "silver", "yellow", "teal", "mint", "green", "orange", "grey"]},
	{"id": "van_delivery", "name": "Delivery Van", "mass": 2300.0, "len": 5.3, "w": 1.98, "h": 2.4, "wb": 3.3, "wr": 0.34,
	 "com": 0.8, "fwd": false, "vmax": 135.0, "acc": 1.5, "dec": 2.8, "kw": 105.0, "cg": 0.24, "gap": 2.0, "lf": 0.97,
	 "classes": [0, 1, 2, 3], "regions": [], "weight": 0.16, "horn": 400.0, "finishes": [0],
	 "paints": ["white", "white", "silver", "yellow", "blue", "grey"]},
	{"id": "lorry_box", "name": "Box Lorry", "mass": 9500.0, "len": 8.6, "w": 2.45, "h": 3.4, "wb": 5.0, "wr": 0.5,
	 "com": 1.25, "fwd": false, "vmax": 95.0, "acc": 0.85, "dec": 2.2, "kw": 200.0, "cg": 0.17, "gap": 2.4, "lf": 0.9,
	 "classes": [0, 1], "regions": [], "weight": 0.10, "horn": 250.0, "finishes": [0],
	 "paints": ["white", "red", "blue", "green", "silver", "orange"]},
	{"id": "bus_coach", "name": "Coach", "mass": 12500.0, "len": 12.0, "w": 2.5, "h": 3.5, "wb": 6.2, "wr": 0.52,
	 "com": 1.3, "fwd": false, "vmax": 100.0, "acc": 0.8, "dec": 2.0, "kw": 260.0, "cg": 0.16, "gap": 2.4, "lf": 0.92,
	 "classes": [0, 1, 3], "regions": [], "weight": 0.06, "horn": 280.0, "finishes": [0],
	 "paints": ["white", "teal", "yellow", "blue", "orange"]},
	{"id": "tractor_farm", "name": "Farm Tractor", "mass": 4200.0, "len": 4.3, "w": 2.3, "h": 2.9, "wb": 2.5, "wr": 0.75,
	 "com": 1.0, "fwd": false, "vmax": 38.0, "acc": 0.9, "dec": 2.5, "kw": 70.0, "cg": 0.2, "gap": 2.0, "lf": 1.0,
	 "classes": [1, 3], "regions": [0], "weight": 0.08, "horn": 330.0, "finishes": [0],
	 "paints": ["green", "red", "orange", "yellow", "blue"]},
	{"id": "pickup_work", "name": "Work Pickup", "mass": 2200.0, "len": 5.4, "w": 1.95, "h": 1.85, "wb": 3.3, "wr": 0.38,
	 "com": 0.75, "fwd": false, "vmax": 150.0, "acc": 1.9, "dec": 3.0, "kw": 140.0, "cg": 0.27, "gap": 1.9, "lf": 1.0,
	 "classes": [0, 1, 2, 3], "regions": [], "weight": 0.18, "horn": 370.0, "finishes": [0, 2],
	 "paints": ["white", "grey", "black", "red", "blue", "silver", "brown", "green"]},
]


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://data/traffic"))
	for t: Dictionary in TYPES:
		var d: Resource = DATA_SCRIPT.new()
		d.id = t["id"]
		d.display_name = t["name"]
		d.model_path = "res://assets/imported/traffic/%s.glb" % t["id"]
		d.mass = t["mass"]
		d.length = t["len"]
		d.width = t["w"]
		d.height = t["h"]
		d.wheelbase = t["wb"]
		d.wheel_radius = t["wr"]
		d.com_height = t["com"]
		d.front_drive = t["fwd"]
		d.max_speed_kmh = t["vmax"]
		d.accel = t["acc"]
		d.decel = t["dec"]
		d.power_kw = t["kw"]
		d.corner_g = t["cg"]
		d.time_gap = t["gap"]
		d.limit_factor = t["lf"]
		d.allowed_classes = PackedInt32Array(t["classes"])
		d.allowed_regions = PackedInt32Array(t["regions"])
		d.spawn_weight = t["weight"]
		d.paints = PackedStringArray(t["paints"])
		d.finishes = PackedInt32Array(t["finishes"])
		d.horn_hz = t["horn"]
		var path := "res://data/traffic/%s.tres" % d.id
		print("traffic type %-13s err=%d" % [d.id, ResourceSaver.save(d, path)])
	quit(0)
