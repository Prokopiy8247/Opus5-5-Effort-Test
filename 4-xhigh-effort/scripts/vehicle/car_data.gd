class_name CarData
extends Resource
## Handling, presentation and audio profile of one car. One .tres per car in res://data/cars/.

enum Drivetrain { FWD, RWD, AWD }
enum TireType { ROAD, SPORT, RALLY, OFFROAD, VINTAGE }

@export_group("Identity")
@export var id: StringName
@export var display_name := ""
@export var maker := ""
@export var model_year := 2026
@export var body_style := ""
@export_multiline var description := ""
@export var model_path := ""
@export var order := 0
@export var default_color := Color(0.8, 0.1, 0.08)
@export var default_finish := 1
@export var default_rim_color := Color(0.75, 0.76, 0.78)

@export_group("Chassis")
@export var mass := 1350.0
## Centre of mass relative to the model origin (ground centre between axles). -Z is forward.
@export var com_offset := Vector3(0.0, 0.48, 0.0)
@export var inertia_scale := Vector3(1.0, 1.0, 1.0)

@export_group("Engine")
@export var drivetrain := Drivetrain.RWD
@export var idle_rpm := 850.0
@export var redline_rpm := 7000.0
@export var max_rpm := 7300.0
## (rpm, torque Nm) points, linear interpolation.
@export var torque_curve := PackedVector2Array([Vector2(1000, 280), Vector2(4000, 380), Vector2(6500, 340), Vector2(7300, 280)])
@export var engine_inertia := 0.22
@export var engine_brake := 0.18
@export var gear_ratios := PackedFloat32Array([3.4, 2.2, 1.6, 1.25, 1.0, 0.82])
@export var reverse_ratio := 3.3
@export var final_drive := 3.6
@export var shift_time := 0.16
@export var awd_front_split := 0.4
@export var lsd := 0.4
@export var turbo := false
@export var cylinders := 6
@export var engine_sound := &"v6"

@export_group("Suspension")
@export var spring_front := 42000.0
@export var spring_rear := 40000.0
@export var damper_front := 3600.0
@export var damper_rear := 3400.0
@export var rebound_ratio := 1.35
@export var arb_front := 14000.0
@export var arb_rear := 9000.0
@export var bump_travel := 0.11
@export var droop_travel := 0.14

@export_group("Tyres")
@export var tire_type := TireType.SPORT
@export var grip := 1.08
@export var grip_front_scale := 1.0
@export var grip_rear_scale := 1.0
@export var peak_slip_angle_deg := 7.5
@export var peak_slip_ratio := 0.11
@export var tire_shape := 1.45
@export var load_sensitivity := 0.08

@export_group("Brakes and steering")
@export var brake_torque := 3600.0
@export var brake_bias := 0.64
@export var handbrake_torque := 3000.0
@export var max_steer_deg := 33.0
@export var high_speed_steer_deg := 6.5
@export var steer_speed := 4.0

@export_group("Aero")
@export var drag_area := 0.66
@export var downforce := 0.35
@export var aero_balance := 0.45

@export_group("Presentation")
@export var car_class := "B"
@export var top_speed_kmh := 260.0


func torque_at(rpm: float) -> float:
	var c := torque_curve
	if c.is_empty():
		return 0.0
	if rpm <= c[0].x:
		return c[0].y
	for i in range(1, c.size()):
		if rpm <= c[i].x:
			var a := c[i - 1]
			var b := c[i]
			return lerpf(a.y, b.y, (rpm - a.x) / maxf(b.x - a.x, 1.0))
	return c[c.size() - 1].y


func peak_power_kw() -> float:
	var best := 0.0
	var r := idle_rpm
	while r <= max_rpm:
		best = maxf(best, torque_at(r) * r * TAU / 60.0 / 1000.0)
		r += 100.0
	return best


func peak_torque() -> float:
	var best := 0.0
	for p in torque_curve:
		best = maxf(best, p.y)
	return best


func drivetrain_name() -> String:
	return ["FWD", "RWD", "AWD"][drivetrain]


## Five 1..10 ratings for the garage menu (computed, not hand-entered).
func ratings(mods: Dictionary = {}) -> Dictionary:
	var pw := peak_power_kw() * float(mods.get("power", 1.0))
	var m := mass * float(mods.get("mass", 1.0))
	var g := grip * float(mods.get("grip", 1.0))
	var pwr := pw / m * 1000.0  # W/kg
	var speed := clampf((top_speed_kmh * float(mods.get("top", 1.0)) - 140.0) / 22.0, 1.0, 10.0)
	var accel := clampf(pwr / 45.0 * (1.15 if drivetrain == Drivetrain.AWD else 1.0), 1.0, 10.0)
	var handling := clampf((g - 0.7) * 14.0 + downforce * 2.0 + (arb_front + arb_rear) / 12000.0 * 0.5, 1.0, 10.0)
	var braking := clampf(brake_torque * float(mods.get("brake", 1.0)) / m * 1.7 * g, 1.0, 10.0)
	var offroad := clampf(2.0 + (droop_travel + bump_travel) * 18.0 + (3.0 if tire_type >= TireType.RALLY and tire_type <= TireType.OFFROAD else 0.0) + (1.0 if drivetrain == Drivetrain.AWD else 0.0), 1.0, 10.0)
	return {"speed": speed, "accel": accel, "handling": handling, "braking": braking, "offroad": offroad}


func class_rating(mods: Dictionary = {}) -> int:
	var r := ratings(mods)
	return int(clampf((r.speed * 0.25 + r.accel * 0.3 + r.handling * 0.3 + r.braking * 0.15) * 100.0, 100.0, 999.0))
