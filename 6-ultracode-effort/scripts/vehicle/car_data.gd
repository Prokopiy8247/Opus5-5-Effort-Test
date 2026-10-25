class_name CarData
extends Resource
## Handling + presentation data for one car. One .tres per car in res://data/cars/.
## Units: SI (kg, m, N, N*m, rad/s). Speeds shown to the player are converted in the UI.

enum Drivetrain { FWD, RWD, AWD }
enum Finish { GLOSS, MATTE, METALLIC }

@export_group("Identity")
@export var id: String = ""
@export var display_name: String = ""
@export var category: String = ""
@export_multiline var blurb: String = ""
@export var perf_class: String = "C"
@export var perf_index: int = 500
@export var model_path: String = ""
@export var year_style: String = ""

@export_group("Paint")
@export var default_color: Color = Color(0.8, 0.1, 0.1)
@export var default_finish: Finish = Finish.GLOSS

@export_group("Mass")
@export var mass: float = 1300.0
## Centre of mass relative to the car origin (ground, mid-wheelbase). y is height above ground.
@export var com: Vector3 = Vector3(0.0, 0.45, 0.0)
## Multiplies the inertia computed from the box approximation of the body.
@export var inertia_scale: Vector3 = Vector3(1.0, 1.0, 1.0)

@export_group("Engine")
@export var idle_rpm: float = 900.0
@export var redline_rpm: float = 6800.0
@export var max_rpm: float = 7200.0
@export var peak_torque: float = 320.0
## Normalised torque (0..1) over normalised rpm (rpm / max_rpm).
@export var torque_curve: Curve
@export var engine_brake: float = 0.18
@export var turbo: bool = false
@export var cylinders: int = 4
## 0 = smooth, 1 = raspy/aggressive exhaust note.
@export var exhaust_rasp: float = 0.4
@export var engine_pitch: float = 1.0

@export_group("Gearbox")
@export var gear_ratios: PackedFloat32Array = PackedFloat32Array([3.30, 2.10, 1.50, 1.17, 0.95, 0.80])
@export var reverse_ratio: float = 3.2
## Reverse speed limiter (km/h): drive fades out towards it; downhill the brakes hold the speed close to it.
@export var reverse_max_kmh: float = 30.0
@export var final_drive: float = 3.9
@export var shift_time: float = 0.16
@export var drivetrain_efficiency: float = 0.88

@export_group("Drivetrain")
@export var drivetrain: Drivetrain = Drivetrain.RWD
## Torque fraction to the front axle for AWD.
@export var awd_front_split: float = 0.4
## 0 = open differential, 1 = locked.
@export var diff_lock: float = 0.45

@export_group("Tyres")
@export var tire_grip: float = 1.05
@export var grip_front: float = 1.0
@export var grip_rear: float = 1.0
@export var peak_slip_deg: float = 7.5
## Lateral grip remaining at large slip angles relative to peak (drift friendliness).
@export var slide_grip: float = 0.80
## Longitudinal grip when spinning/locked relative to peak.
@export var long_slide_grip: float = 0.82
## 0 = road tyres, 1 = full off-road tyres (changes the surface multipliers).
@export var offroad_tires: float = 0.0
@export var load_sensitivity: float = 0.10

@export_group("Wheels (fallback geometry, replaced by the model's measured wheels)")
@export var wheelbase: float = 2.6
@export var track_front: float = 1.55
@export var track_rear: float = 1.55
@export var wheel_radius_front: float = 0.32
@export var wheel_radius_rear: float = 0.32
@export var body_size: Vector3 = Vector3(1.8, 1.3, 4.3)

@export_group("Suspension")
@export var spring_front: float = 48000.0
@export var spring_rear: float = 44000.0
@export var damper_bump: float = 3600.0
@export var damper_rebound: float = 5200.0
@export var suspension_travel: float = 0.20
@export var anti_roll_front: float = 16000.0
@export var anti_roll_rear: float = 10000.0
## Lowers (-) or raises (+) the static ride height relative to the authored model.
@export var ride_height: float = 0.0

@export_group("Aero")
@export var drag_area: float = 0.68
@export var downforce_front: float = 0.25
@export var downforce_rear: float = 0.35
@export var rolling_resistance: float = 0.013

@export_group("Brakes & steering")
@export var brake_force: float = 15000.0
@export var brake_bias: float = 0.64
@export var handbrake_force: float = 7000.0
@export var max_steer_deg: float = 33.0
@export var high_speed_steer_deg: float = 7.0
@export var steer_rate: float = 3.2
@export var top_speed_kmh: float = 250.0


## Torque in N*m at a given rpm for full throttle.
func torque_at(rpm: float) -> float:
	var x := clampf(rpm / max_rpm, 0.0, 1.0)
	if torque_curve == null:
		# Generic bell-shaped curve peaking at ~55% of max rpm.
		return peak_torque * clampf(1.0 - pow((x - 0.55) / 0.62, 2.0), 0.25, 1.0)
	return peak_torque * torque_curve.sample_baked(x)


## Approximate peak power in kW, scanning the torque curve.
func peak_power_kw() -> float:
	var best := 0.0
	var rpm := idle_rpm
	while rpm <= redline_rpm:
		best = maxf(best, torque_at(rpm) * rpm * TAU / 60.0)
		rpm += 100.0
	return best / 1000.0


func peak_power_hp() -> float:
	return peak_power_kw() * 1.341


func drivetrain_name() -> String:
	return ["FWD", "RWD", "AWD"][drivetrain]
