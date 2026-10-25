class_name CarDef
extends Resource
## Data-driven definition of one car: model, class, handling, engine sound and default paint.

enum Drive { FWD, RWD, AWD }

@export var id: String = ""
@export var display_name: String = ""
@export var maker: String = ""
@export var description: String = ""
@export var car_class: String = "C"
@export var pi: int = 500
@export var model_path: String = ""
@export var year: int = 2020

@export_group("Mass")
@export var mass: float = 1300.0
@export var com_offset: Vector3 = Vector3(0, -0.15, 0)

@export_group("Engine")
@export var peak_torque: float = 300.0  ## Nm
@export var peak_torque_rpm: float = 4200.0
@export var redline: float = 7000.0
@export var idle_rpm: float = 850.0
@export var torque_falloff: float = 0.45  ## torque fraction left at redline
@export var gears: PackedFloat32Array = PackedFloat32Array([3.4, 2.1, 1.5, 1.15, 0.92, 0.75])
@export var reverse_ratio: float = 3.3
@export var final_drive: float = 3.9
@export var shift_time: float = 0.22
@export var drive: Drive = Drive.RWD
@export var awd_front: float = 0.4
@export var turbo: bool = false

@export_group("Tyres")
@export var grip: float = 1.05  ## dry asphalt friction coefficient
@export var loose_grip: float = 1.0  ## multiplier on dirt/gravel/sand/grass
@export var lateral_stiffness: float = 9.0  ## Pacejka B
@export var tire_rolloff: float = 0.85  ## sliding friction vs peak

@export_group("Suspension")
@export var rest_length: float = 0.32
@export var spring: float = 42000.0  ## N/m per wheel
@export var damper_bump: float = 3200.0
@export var damper_rebound: float = 4200.0
@export var arb_front: float = 18000.0
@export var arb_rear: float = 12000.0

@export_group("Brakes / Steering")
@export var brake_force: float = 11000.0  ## total N per axle at full pedal (scaled by load internally)
@export var brake_bias: float = 0.62
@export var steer_lock: float = 34.0  ## degrees
@export var steer_speed_reduction: float = 0.72

@export_group("Aero")
@export var top_speed_kmh: float = 220.0
@export var downforce: float = 0.6  ## ClA
@export var aero_balance: float = 0.45  ## front share

@export_group("Sound")
@export var cylinders: int = 4
@export var sound_pitch: float = 1.0
@export var sound_rough: float = 0.3

@export_group("Paint")
@export var paint_color: Color = Color(0.8, 0.1, 0.1)
@export var paint_finish: int = 0  ## 0 gloss, 1 metallic, 2 matte
@export var rim_color: Color = Color(0.75, 0.76, 0.78)


func peak_power_kw() -> float:
	# approximate from torque curve sampled across the rev range
	var best: float = 0.0
	var rpm: float = 1000.0
	while rpm <= redline:
		best = maxf(best, torque_at(rpm) * rpm * TAU / 60.0 / 1000.0)
		rpm += 100.0
	return best


func torque_at(rpm: float) -> float:
	if rpm <= peak_torque_rpm:
		var t: float = clampf((rpm - idle_rpm * 0.5) / maxf(1.0, peak_torque_rpm - idle_rpm * 0.5), 0.0, 1.0)
		return peak_torque * lerpf(0.55, 1.0, sin(t * PI * 0.5))
	var u: float = clampf((rpm - peak_torque_rpm) / maxf(1.0, redline - peak_torque_rpm), 0.0, 1.0)
	return peak_torque * lerpf(1.0, torque_falloff, u * u)
