extends RefCounted
## Derived car figures for the garage / console: 0-100 estimate, top speed, braking, 0..10 ratings.
## Small longitudinal simulations on the CarData values (same torque curve, gearing and grip as the car).

const G := 9.81
const RHO := 1.225
const STAT_NAMES: Array[String] = ["Speed", "Acceleration", "Handling", "Braking", "Off-road"]


static func zero_to_100(d: CarData) -> float:
	var awd := d.drivetrain == CarData.Drivetrain.AWD
	var fwd := d.drivetrain == CarData.Drivetrain.FWD
	var r := d.wheel_radius_front if fwd else d.wheel_radius_rear
	var L := maxf(d.wheelbase, 1.5)
	var rear_static := clampf(0.5 + d.com.z / L, 0.25, 0.75)
	var mu := d.tire_grip * 0.97
	var v := 0.0
	var t := 0.0
	var a := 0.0
	var gear := 1
	var shift_left := 0.0
	var dt := 0.01
	var n := d.gear_ratios.size()
	while v < 100.0 / 3.6 and t < 40.0:
		var ratio := d.gear_ratios[gear - 1] * d.final_drive
		var rpm := v / r * ratio * 60.0 / TAU
		if rpm >= d.redline_rpm * 0.97 and gear < n:
			gear += 1
			shift_left = d.shift_time
			continue
		if gear == 1:
			rpm = maxf(rpm, d.redline_rpm * 0.55)
		rpm = clampf(rpm, d.idle_rpm, d.max_rpm)
		var f := 0.0
		if shift_left <= 0.0:
			f = d.torque_at(rpm) * ratio * d.drivetrain_efficiency / r
		var transfer := a / G * d.com.y / L
		var share := 1.0 if awd else ((1.0 - rear_static - transfer) if fwd else (rear_static + transfer))
		f = minf(f, mu * d.mass * G * clampf(share, 0.2, 1.0))
		var resist := 0.5 * RHO * d.drag_area * v * v + d.rolling_resistance * d.mass * G
		a = (f - resist) / d.mass
		v += a * dt
		shift_left -= dt
		t += dt
	return t


## Top speed in km/h: the authored limiter or the drag-limited speed, whichever is lower.
static func top_speed(d: CarData) -> float:
	var p := d.peak_power_kw() * 1000.0 * d.drivetrain_efficiency
	var v := 10.0
	while v < 160.0:
		var need := (0.5 * RHO * d.drag_area * v * v + d.rolling_resistance * d.mass * G) * v
		if need > p:
			break
		v += 0.25
	var kmh := v * 3.6
	return minf(kmh, d.top_speed_kmh) if d.top_speed_kmh > 0.0 else kmh


## 100-0 km/h stopping distance in metres.
static func braking_distance(d: CarData) -> float:
	var decel := minf(d.brake_force / d.mass, d.tire_grip * 0.97 * G)
	var v := 100.0 / 3.6
	# 1.1: ABS margin + brake ramp-in, matched against the physics drive tests.
	return v * v / (2.0 * maxf(decel, 1.0)) * 1.1


## Steady cornering grip in g at ~120 km/h, including downforce.
static func cornering_g(d: CarData) -> float:
	var v := 120.0 / 3.6
	var df := 0.5 * RHO * v * v * (d.downforce_front + d.downforce_rear)
	var grip := d.tire_grip * (d.grip_front + d.grip_rear) * 0.5
	return grip * (1.0 + df / (d.mass * G) * 0.85)


## 0..10 ratings: {"Speed", "Acceleration", "Handling", "Braking", "Off-road"} plus raw figures.
static func ratings(d: CarData) -> Dictionary:
	var top := top_speed(d)
	var acc := zero_to_100(d)
	var brk := braking_distance(d)
	var cg := cornering_g(d)
	var off := d.offroad_tires * 5.0 + clampf((d.suspension_travel - 0.12) / 0.18, 0.0, 1.0) * 2.5
	off += 1.5 if d.drivetrain == CarData.Drivetrain.AWD else 0.0
	off += clampf((d.com.y - 0.4) / 0.3, 0.0, 1.0) * 1.0
	return {
		"Speed": clampf((top - 110.0) / 24.0, 0.5, 10.0),
		"Acceleration": clampf(10.0 - (acc - 2.6) * 1.05, 0.5, 10.0),
		"Handling": clampf((cg - 0.74) / 0.072, 0.5, 10.0),
		"Braking": clampf(10.0 - (brk - 33.0) * 0.45, 0.5, 10.0),
		"Off-road": clampf(off, 0.5, 10.0),
		"top_kmh": top, "zero_100": acc, "brake_m": brk, "lat_g": cg,
		"hp": d.peak_power_hp(), "kg": d.mass,
		"pi": Tuning.performance_index(d),
	}
