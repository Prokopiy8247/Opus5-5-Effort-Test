class_name CarSpec
extends Resource
## Handling, engine and presentation data for one garage car.

enum Drivetrain { FWD, RWD, AWD }
enum TireType { ROAD, SPORT, RALLY, OFFROAD, VINTAGE }

@export_group("Identity")
@export var id: String = ""
@export var display_name: String = ""
@export var maker: String = ""
@export var year: int = 2020
@export var body_style: String = ""
@export var car_class: String = "C"
@export var pi: int = 500
@export_multiline var description: String = ""
@export_file("*.glb") var model_path: String = ""

@export_group("Mass")
@export var mass: float = 1300.0
## Centre of mass relative to the model origin (ground, mid-wheelbase). -Z is forward.
@export var com_offset: Vector3 = Vector3(0.0, 0.5, 0.0)
@export var inertia_scale: Vector3 = Vector3.ONE

@export_group("Engine")
@export var peak_torque: float = 300.0
## (rpm, fraction of peak torque) points.
@export var torque_curve: PackedVector2Array = PackedVector2Array([Vector2(1000, 0.55), Vector2(3000, 0.9), Vector2(4500, 1.0), Vector2(6500, 0.85), Vector2(7000, 0.7)])
@export var idle_rpm: float = 900.0
@export var redline_rpm: float = 6800.0
@export var engine_inertia: float = 0.25
@export var engine_brake: float = 0.18
@export var cylinders: int = 4
@export var engine_layout: String = "I4"
@export var turbo: bool = false
@export var sound_base_pitch: float = 1.0
@export var sound_roughness: float = 0.3

@export_group("Transmission")
@export var drivetrain: Drivetrain = Drivetrain.RWD
@export var awd_front_split: float = 0.4
@export var gear_ratios: PackedFloat32Array = PackedFloat32Array([3.3, 2.1, 1.5, 1.15, 0.92, 0.76])
@export var reverse_ratio: float = 3.2
@export var final_drive: float = 3.7
@export var shift_time: float = 0.18
@export var drivetrain_efficiency: float = 0.85

@export_group("Tyres")
@export var tire_type: TireType = TireType.ROAD
@export var grip: float = 1.0
@export var grip_rear_bias: float = 1.0
@export var peak_slip_angle_deg: float = 8.0
@export var slide_grip: float = 0.78
@export var rolling_resistance: float = 0.012

@export_group("Suspension")
@export var suspension_rest: float = 0.16
@export var suspension_travel: float = 0.14
@export var spring_hz_front: float = 1.6
@export var spring_hz_rear: float = 1.7
@export var damping_ratio: float = 0.35
@export var anti_roll_front: float = 9000.0
@export var anti_roll_rear: float = 7000.0

@export_group("Brakes & Steering")
@export var brake_force: float = 11000.0
@export var brake_bias: float = 0.62
@export var handbrake_force: float = 5000.0
@export var steer_lock_deg: float = 34.0
@export var steer_speed_falloff: float = 0.014

@export_group("Aero")
@export var drag_area: float = 0.68
@export var downforce_area: float = 0.25
@export var aero_balance: float = 0.45
@export var top_speed_kmh: float = 220.0

@export_group("Paint")
@export var paint_color: Color = Color(0.8, 0.1, 0.08)
@export_enum("gloss", "metallic", "matte", "pearl") var paint_finish: String = "metallic"
@export var rim_color: Color = Color(0.75, 0.76, 0.78)

@export_group("Presentation")
## Displayed stats (0..10)
@export var stat_speed: float = 5.0
@export var stat_handling: float = 5.0
@export var stat_accel: float = 5.0
@export var stat_launch: float = 5.0
@export var stat_braking: float = 5.0
@export var stat_offroad: float = 5.0
@export var power_hp: int = 200


func torque_at(rpm: float) -> float:
	var c := torque_curve
	if c.is_empty():
		return peak_torque
	if rpm <= c[0].x:
		return c[0].y * peak_torque
	for i in range(1, c.size()):
		if rpm <= c[i].x:
			var t := (rpm - c[i - 1].x) / (c[i].x - c[i - 1].x)
			return lerpf(c[i - 1].y, c[i].y, t) * peak_torque
	return c[c.size() - 1].y * peak_torque
