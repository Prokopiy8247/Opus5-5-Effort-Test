class_name CarSpec
extends Resource
## Handling and presentation data for one player car.

@export var id := ""
@export var display_name := ""
@export var category := ""
@export var glb_path := ""
@export var mass := 1300.0
@export var com_offset := Vector3(0, -0.15, 0)
@export var power_kw := 150.0
@export var peak_rpm := 6000.0
@export var redline := 7000.0
@export var idle_rpm := 900.0
@export var gear_ratios := PackedFloat32Array([3.4, 2.1, 1.5, 1.15, 0.92, 0.76])
@export var final_drive := 3.9
@export_enum("FWD", "RWD", "AWD") var drivetrain := 1
@export var awd_front_split := 0.4
@export var top_speed_kmh := 220.0
@export var grip := 1.1                 # peak friction coefficient on dry asphalt
@export var offroad_grip := 0.85        # multiplier applied to loose-surface grip
@export var lat_stiffness := 0.13       # slip angle (rad) at ~76% of peak grip
@export var susp_travel := 0.22
@export var susp_freq := 1.9            # Hz
@export var susp_damping := 0.38        # damping ratio
@export var anti_roll := 9000.0
@export var downforce := 0.3            # N per (m/s)^2
@export var brake_force := 11000.0
@export var brake_bias := 0.62
@export var steer_lock_deg := 34.0
@export var engine_voice := 1.0         # pitch multiplier of the procedural engine
@export var cylinders := 4
@export var turbo := false
@export var base_color := Color(0.8, 0.1, 0.05)
@export_enum("Gloss", "Matte", "Metallic") var finish := 0

func class_rating() -> String:
	var pi := performance_index()
	if pi < 400: return "D %d" % pi
	if pi < 500: return "C %d" % pi
	if pi < 600: return "B %d" % pi
	if pi < 700: return "A %d" % pi
	if pi < 800: return "S1 %d" % pi
	return "S2 %d" % pi

func performance_index() -> int:
	var pw := power_kw / mass * 1000.0       # W/kg
	var v := pw * 2.2 + top_speed_kmh * 0.9 + grip * 160.0 + (40.0 if drivetrain == 2 else 0.0)
	return clampi(int(v - 150.0), 100, 999)
