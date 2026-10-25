class_name CarDefinition
extends Resource
## Data-driven description of one car: model, mass, engine, gearbox, tyres, suspension,
## brakes, steering, aero, sound and default paint. One .tres per car in res://data/cars/.

enum Drivetrain { FWD, RWD, AWD }
enum Finish { GLOSS, METALLIC, MATTE, PEARL }

@export_group("Identity")
@export var id: StringName = &"car"
@export var display_name: String = "Car"
@export var maker: String = ""
@export var category: String = "Road"
@export var year: int = 2020
@export_multiline var description: String = ""
@export var engine_label: String = "2.0 I4"
@export_file("*.glb") var model_path: String = ""
## Fallback if the model has no Wheel_* nodes (local, metres, +Z = rear in Godot).
@export var fallback_wheel_positions: PackedVector3Array = PackedVector3Array()

@export_group("Mass")
@export var mass: float = 1300.0
## Centre of mass relative to the midpoint between the four wheel centres (local axes).
@export var com_offset: Vector3 = Vector3(0.0, 0.05, 0.0)
## Multiplies the box-approximated inertia tensor (x = pitch, y = yaw, z = roll).
@export var inertia_scale: Vector3 = Vector3(1.0, 1.0, 1.0)

@export_group("Engine")
@export var max_torque_nm: float = 300.0
## Normalised torque (0..1) over normalised rpm (0 = idle, 1 = redline).
@export var torque_curve: PackedFloat32Array = PackedFloat32Array([0.55, 0.72, 0.86, 0.95, 1.0, 0.98, 0.92, 0.82])
@export var idle_rpm: float = 900.0
@export var redline_rpm: float = 7000.0
@export var engine_inertia: float = 0.18
@export var engine_brake_torque: float = 45.0
@export var turbo: bool = false
@export var turbo_lag: float = 0.6

@export_group("Transmission")
@export var drivetrain: Drivetrain = Drivetrain.RWD
@export var gear_ratios: PackedFloat32Array = PackedFloat32Array([3.4, 2.15, 1.55, 1.2, 0.98, 0.82])
@export var reverse_ratio: float = 3.3
@export var final_drive: float = 3.7
@export var shift_time: float = 0.16
@export_range(0.0, 1.0) var awd_front_split: float = 0.4
## 0 = open differential, 1 = fully locked.
@export_range(0.0, 1.0) var diff_lock: float = 0.35
@export var drivetrain_efficiency: float = 0.88

@export_group("Tyres")
@export var tire_grip: float = 1.0
## Front / rear peak grip multipliers (balance).
@export var grip_front: float = 1.0
@export var grip_rear: float = 1.0
@export var slip_ratio_peak: float = 0.1
@export var slip_angle_peak_deg: float = 7.0
## Grip retained in a full slide relative to peak (asphalt reference).
@export var slide_ratio: float = 0.72
@export var load_sensitivity: float = 0.12
## How well the tyre copes with loose surfaces (rally/off-road tyres > 1).
@export var offroad_grip: float = 1.0
@export var wheel_radius_front: float = 0.0
@export var wheel_radius_rear: float = 0.0
@export var wheel_mass: float = 18.0

@export_group("Suspension")
@export var spring_hz_front: float = 1.7
@export var spring_hz_rear: float = 1.8
@export var damping_bump: float = 0.32
@export var damping_rebound: float = 0.55
@export var travel_up: float = 0.09
@export var travel_down: float = 0.12
@export var anti_roll_front: float = 22000.0
@export var anti_roll_rear: float = 14000.0
## Visual ride height offset applied to the body (negative lowers the car).
@export var ride_height_offset: float = 0.0

@export_group("Brakes")
@export var brake_torque: float = 2600.0
@export_range(0.0, 1.0) var brake_bias: float = 0.66
@export var handbrake_torque: float = 2200.0

@export_group("Steering")
@export var steer_lock_deg: float = 34.0
@export var steer_high_speed_deg: float = 3.8
@export var steer_speed: float = 3.2

@export_group("Aero")
@export var drag_area: float = 0.68
@export var downforce_area: float = 0.15
@export_range(0.0, 1.0) var aero_balance: float = 0.45
@export var frontal_lift: float = 0.0

@export_group("Sound")
@export var cylinders: int = 4
@export var engine_tone: float = 1.0
@export var engine_roughness: float = 0.3
@export var exhaust_pop: float = 0.3

@export_group("Presentation")
@export var performance_class: String = "B"
@export var performance_index: int = 500
@export var default_color: Color = Color(0.8, 0.1, 0.1)
@export var default_finish: Finish = Finish.METALLIC
@export var top_speed_kmh: float = 220.0
@export var power_kw: float = 150.0
@export var zero_to_100_s: float = 7.0


func torque_at(rpm_norm: float) -> float:
	## Normalised torque (0..1) at normalised rpm (0 idle .. 1 redline), linear interpolation.
	var n := torque_curve.size()
	if n == 0:
		return 1.0
	var x := clampf(rpm_norm, 0.0, 1.0) * float(n - 1)
	var i := mini(int(x), n - 2)
	if n == 1:
		return torque_curve[0]
	return lerpf(torque_curve[i], torque_curve[i + 1], x - float(i))


func peak_power_kw() -> float:
	var best := 0.0
	for k in 41:
		var t := float(k) / 40.0
		var rpm := lerpf(idle_rpm, redline_rpm, t)
		best = maxf(best, torque_at(t) * max_torque_nm * rpm * TAU / 60.0)
	return best / 1000.0


func drivetrain_label() -> String:
	return ["FWD", "RWD", "AWD"][drivetrain]


func finish_label(f: int) -> String:
	return ["Gloss", "Metallic", "Matte", "Pearl"][clampi(f, 0, 3)]
