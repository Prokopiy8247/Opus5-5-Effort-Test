class_name CarController
extends RigidBody3D
## Project-owned raycast/spring vehicle on a RigidBody3D (Jolt, 120 Hz).
## Per tick: wheel ray casts -> spring/damper/anti-roll -> powertrain -> sub-stepped
## combined-slip tyre model with wheel spin integration -> aero -> assists.
## Inputs (in_*) are written by PlayerDriver or an AI driver before each physics tick.

signal impact(strength: float, at: Vector3)
signal gear_changed(gear: int)

const SUBSTEPS := 10
const AIR_DENSITY := 1.225
const SLIP_V_FLOOR := 6.0
const WHEEL_INERTIA := 1.5

class Wheel:
	var rest_pos := Vector3.ZERO
	var anchor := Vector3.ZERO
	var rest_ext := 0.2
	var radius := 0.33
	var front := true
	var left := true
	var driven := false
	var k := 40000.0
	var c := 3500.0
	var l_max := 0.3
	var l_min := 0.1
	var length := 0.2
	var prev_length := 0.2
	var omega := 0.0
	var spin := 0.0
	var steer := 0.0
	var contact := false
	var point := Vector3.ZERO
	var normal := Vector3.UP
	var fz := 0.0
	var slip_ratio := 0.0
	var slip_angle := 0.0
	var v_long := 0.0
	var v_lat := 0.0
	var fx := 0.0
	var fy := 0.0
	var surface: SurfaceData
	var collider: Object
	var drive_torque := 0.0
	var brake_torque := 0.0
	var inertia := WHEEL_INERTIA
	var query: PhysicsRayQueryParameters3D
	var skid := 0.0
	var air_time := 0.0

var data: CarData
var visual: CarVisual
var wheels: Array[Wheel] = []

# ---- inputs
var in_throttle := 0.0
var in_brake := 0.0
var in_steer := 0.0
var in_handbrake := false
var in_shift := 0  # +1 / -1 request (manual)

# ---- assists / options
var assist_abs := true
var assist_tcs := true
var assist_stm := true
var assist_steer := true
var auto_gear := true
var mods := {"power": 1.0, "grip": 1.0, "brake": 1.0, "mass": 1.0, "aero": 1.0, "susp": 1.0, "top": 1.0}
var tune := {"final_drive": 1.0, "brake_bias": 0.0, "spring": 1.0, "damper": 1.0, "arb_f": 1.0, "arb_r": 1.0,
		"aero": 1.0, "tire_pressure": 0.0, "camber": 0.0}
var wetness := 0.0
var weather_grip := 1.0

# ---- state (read by HUD/audio/camera)
var gear := 1
var rpm := 900.0
var speed := 0.0          ## signed forward speed m/s
var speed_abs := 0.0
var grounded := 0
var steer_angle := 0.0
var throttle_out := 0.0
var brake_out := 0.0
var tcs_active := false
var abs_active := false
var stm_active := false
var shift_timer := 0.0
var body_slip := 0.0       ## rad, velocity vs heading
var drift_angle := 0.0
var air_time := 0.0
var surface_name := "Asphalt"
var max_slip := 0.0
var engine_load := 0.0
var lights_on := false
var reversing := false
var odometer := 0.0
var last_impact := 0.0
var _reverse_timer := 0.0
var _shift_cooldown := 0.0
var _upside_timer := 0.0
var _wheelbase := 2.6
var _front_frac := 0.5
var _axle_front_z := -1.3
var _axle_rear_z := 1.3
var _yaw_inertia := 2500.0
var _prev_velocity := Vector3.ZERO
var _frozen_for_setup := false


func setup(car_data: CarData, car_visual: CarVisual) -> void:
	data = car_data
	visual = car_visual
	mass = data.mass * float(mods.mass)
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = data.com_offset
	continuous_cd = true
	can_sleep = false
	contact_monitor = true
	max_contacts_reported = 6
	linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	linear_damp = 0.0
	angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	angular_damp = 0.05
	collision_layer = 2
	collision_mask = 1 | 2 | 4
	var pm := PhysicsMaterial.new()
	pm.friction = 0.35
	pm.bounce = 0.05
	physics_material_override = pm
	for ch in get_children():
		if ch is CollisionShape3D:
			ch.queue_free()
	var cs := CollisionShape3D.new()
	cs.name = "Hull"
	cs.shape = visual.build_collision_shape()
	add_child(cs)
	_build_wheels()
	var aabb := visual.body_aabb()
	var lx := aabb.size.x
	var ly := aabb.size.y
	var lz := aabb.size.z
	var m := mass
	inertia = Vector3(m * (ly * ly + lz * lz) / 14.0 * data.inertia_scale.x,
			m * (lx * lx + lz * lz) / 13.0 * data.inertia_scale.y,
			m * (lx * lx + ly * ly) / 13.0 * data.inertia_scale.z)
	_yaw_inertia = inertia.y
	gear = 1
	rpm = data.idle_rpm


func _build_wheels() -> void:
	wheels.clear()
	var pos := visual.wheel_rest_positions()
	_axle_front_z = (pos[0].z + pos[1].z) * 0.5
	_axle_rear_z = (pos[2].z + pos[3].z) * 0.5
	_wheelbase = absf(_axle_rear_z - _axle_front_z)
	_front_frac = clampf((_axle_rear_z - data.com_offset.z) / _wheelbase, 0.2, 0.8)
	for i in 4:
		var w := Wheel.new()
		w.front = i < 2
		w.left = i % 2 == 0
		w.rest_pos = pos[i]
		w.radius = visual.wheel_radius_front if w.front else visual.wheel_radius_rear
		match data.drivetrain:
			CarData.Drivetrain.FWD:
				w.driven = w.front
			CarData.Drivetrain.RWD:
				w.driven = not w.front
			_:
				w.driven = true
		var susp_mul := float(tune.spring) * float(mods.susp)
		w.k = (data.spring_front if w.front else data.spring_rear) * susp_mul
		w.c = (data.damper_front if w.front else data.damper_rear) * float(tune.damper) * sqrt(float(mods.susp))
		var load := mass * 9.81 * (_front_frac if w.front else 1.0 - _front_frac) * 0.5
		var sag := load / w.k
		w.rest_ext = data.bump_travel + 0.06
		w.anchor = w.rest_pos + Vector3.UP * w.rest_ext
		w.l_max = w.rest_ext + sag
		w.l_min = w.rest_ext - data.bump_travel
		w.length = w.rest_ext
		w.prev_length = w.rest_ext
		w.query = PhysicsRayQueryParameters3D.new()
		w.query.collision_mask = 1
		w.query.exclude = [get_rid()]
		w.surface = Surfaces.get_kind(SurfaceData.Kind.ASPHALT)
		wheels.append(w)


func refresh_tuning() -> void:
	if data == null:
		return
	mass = data.mass * float(mods.mass)
	_build_wheels()


# ------------------------------------------------------------------ physics
func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if data == null or wheels.is_empty() or freeze:
		return
	var dt := state.step
	var xf := state.transform
	var b := xf.basis
	var up := b.y
	var fwd := -b.z
	var right := b.x
	var com := xf * center_of_mass
	var lv := state.linear_velocity
	var av := state.angular_velocity
	speed = lv.dot(fwd)
	speed_abs = lv.length()
	odometer += speed_abs * dt
	var flat_v := lv - up * lv.dot(up)
	body_slip = atan2(flat_v.dot(right), absf(flat_v.dot(fwd))) if flat_v.length() > 2.0 else 0.0
	drift_angle = rad_to_deg(absf(body_slip)) if speed > 5.0 else 0.0

	_update_drive_inputs(dt)
	_update_steering(dt)

	# ---- suspension ray casts
	var space := state.get_space_state()
	grounded = 0
	for w in wheels:
		var a := xf * w.anchor
		w.query.from = a
		w.query.to = a - up * (w.l_max + w.radius)
		var hit := space.intersect_ray(w.query)
		w.prev_length = w.length
		if hit.is_empty():
			w.contact = false
			w.length = w.l_max
			w.fz = 0.0
			w.air_time += dt
			continue
		w.contact = true
		w.air_time = 0.0
		grounded += 1
		w.point = hit.position
		w.normal = hit.normal
		w.collider = hit.collider
		w.length = maxf(a.distance_to(w.point) - w.radius, 0.0)
		w.surface = _surface_for(hit.collider, w.point)
	air_time = 0.0 if grounded > 0 else air_time + dt

	# ---- springs, dampers, anti-roll bars
	var comp := PackedFloat32Array([0, 0, 0, 0])
	for i in 4:
		comp[i] = (wheels[i].l_max - wheels[i].length) if wheels[i].contact else 0.0
	var arb := PackedFloat32Array([0, 0, 0, 0])
	var arb_f := data.arb_front * float(tune.arb_f) * float(mods.susp)
	var arb_r := data.arb_rear * float(tune.arb_r) * float(mods.susp)
	arb[0] = arb_f * (comp[0] - comp[1])
	arb[1] = -arb[0]
	arb[2] = arb_r * (comp[2] - comp[3])
	arb[3] = -arb[2]
	var total_fz := 0.0
	for i in 4:
		var w := wheels[i]
		if not w.contact:
			continue
		var vel := (w.prev_length - w.length) / dt
		var damp := w.c * vel * (1.0 if vel > 0.0 else data.rebound_ratio)
		var f := w.k * comp[i] + damp + arb[i]
		if w.length < w.l_min:
			f += w.k * 10.0 * (w.l_min - w.length) + w.c * 2.0 * maxf(vel, 0.0)
		f = maxf(f, 0.0)
		w.fz = f * clampf(up.dot(w.normal), 0.3, 1.0)
		total_fz += w.fz
		var wc := xf * w.anchor - up * w.length
		state.apply_force(up * f, wc - xf.origin)

	# ---- powertrain
	_powertrain(dt)

	# ---- tyres
	var mu_base := data.grip * float(mods.grip) * weather_grip
	var tan_peak := tan(deg_to_rad(data.peak_slip_angle_deg + float(tune.tire_pressure) * -0.8))
	var kappa_peak := data.peak_slip_ratio
	var shape_c := data.tire_shape
	var shape_b := tan(PI / (2.0 * shape_c))
	var h := dt / float(SUBSTEPS)
	var nominal_fz := mass * 9.81 * 0.25
	max_slip = 0.0
	tcs_active = false
	abs_active = false
	for w in wheels:
		w.fx = 0.0
		w.fy = 0.0
		if not w.contact:
			w.slip_angle = 0.0
			w.slip_ratio = 0.0
			w.skid = 0.0
			continue
		var n := w.normal
		var wheel_fwd := fwd.rotated(up, -w.steer)
		var wf := (wheel_fwd - n * wheel_fwd.dot(n)).normalized()
		var ws := wf.cross(n)
		var v := lv + av.cross(w.point - com)
		w.v_long = v.dot(wf)
		w.v_lat = v.dot(ws)
		w.slip_angle = atan2(w.v_lat, maxf(absf(w.v_long), 1.0))

	# brake torques (+ ABS) and drive torques are set; integrate wheel spin with sub-steps
	for w in wheels:
		var bt := brake_out * data.brake_torque * float(mods.brake) * 0.5
		var bias := clampf(data.brake_bias + float(tune.brake_bias), 0.3, 0.85)
		bt *= bias if w.front else (1.0 - bias)
		if in_handbrake and not w.front:
			bt += data.handbrake_torque
		if assist_abs and brake_out > 0.05 and w.contact and w.slip_ratio < -0.16 and not (in_handbrake and not w.front):
			bt *= 0.3
			abs_active = true
		w.brake_torque = bt
		w.inertia = WHEEL_INERTIA

	var drv_ratio := _total_ratio()
	if drv_ratio != 0.0 and shift_timer <= 0.0:
		var n_driven := 4.0 if data.drivetrain == CarData.Drivetrain.AWD else 2.0
		for w in wheels:
			if w.driven:
				w.inertia += data.engine_inertia * drv_ratio * drv_ratio / n_driven * 0.6

	var fx_acc := PackedFloat32Array([0, 0, 0, 0])
	var fy_acc := PackedFloat32Array([0, 0, 0, 0])
	var lsd_k := data.lsd * 1800.0
	for _s in SUBSTEPS:
		for i in 4:
			var w := wheels[i]
			if not w.contact:
				w.omega += w.drive_torque / w.inertia * h
				w.omega *= 0.999
				_brake_wheel(w, h)
				continue
			var mu := mu_base * w.surface.grip * _tire_mult(w.surface) * (data.grip_front_scale if w.front else data.grip_rear_scale)
			if w.surface.paved:
				mu *= lerpf(1.0, w.surface.wet_grip, wetness)
			mu *= clampf(1.0 - data.load_sensitivity * (w.fz / nominal_fz - 1.0), 0.75, 1.15)
			var loose := 1.0 if w.surface.paved else 1.7
			var kappa := (w.omega * w.radius - w.v_long) / maxf(absf(w.v_long), SLIP_V_FLOOR)
			var sx := kappa / (kappa_peak * loose)
			var sy := tan(clampf(w.slip_angle, -1.45, 1.45)) / (tan_peak * (1.0 + (loose - 1.0) * 0.4))
			var sm := sqrt(sx * sx + sy * sy)
			var fx := 0.0
			var fy := 0.0
			if sm > 1e-5:
				var ftot := mu * w.fz * sin(shape_c * atan(shape_b * sm))
				fx = ftot * sx / sm
				fy = -ftot * sy / sm
			# tyre torque drives omega towards rolling speed; never let it overshoot that equilibrium
			var omega_eq := w.v_long / w.radius
			var before := w.omega - omega_eq
			w.omega += (w.drive_torque - fx * w.radius) / w.inertia * h
			var after := w.omega - omega_eq
			if before * after < 0.0 and absf(w.drive_torque) < absf(fx * w.radius):
				w.omega = omega_eq
			_brake_wheel(w, h)
			fx_acc[i] += fx
			fy_acc[i] += fy
			w.slip_ratio = kappa
		# limited-slip coupling inside each driven axle (and centre coupling for AWD)
		for pair: Array in [[0, 1], [2, 3]]:
			var wl := wheels[pair[0]]
			var wr := wheels[pair[1]]
			if wl.driven and wr.driven:
				var t := lsd_k * (wl.omega - wr.omega)
				wl.omega -= t / wl.inertia * h
				wr.omega += t / wr.inertia * h
		# hydraulic-handbrake style: pulling it opens the AWD centre coupling so the rear can lock and rotate
		if data.drivetrain == CarData.Drivetrain.AWD and not in_handbrake:
			var of := (wheels[0].omega + wheels[1].omega) * 0.5
			var orr := (wheels[2].omega + wheels[3].omega) * 0.5
			var tc := lsd_k * 0.6 * (of - orr)
			for i in 2:
				wheels[i].omega -= tc / wheels[i].inertia * h * 0.5
				wheels[i + 2].omega += tc / wheels[i + 2].inertia * h * 0.5

	var mass_share := mass / maxf(total_fz, 1.0)
	for i in 4:
		var w := wheels[i]
		w.spin = fmod(w.spin + w.omega * dt, TAU)
		if not w.contact:
			continue
		var fx := fx_acc[i] / float(SUBSTEPS)
		var fy := fy_acc[i] / float(SUBSTEPS)
		# don't let lateral force overshoot zero lateral speed in one tick
		var m_w := w.fz * mass_share
		var fy_cap := absf(w.v_lat) * m_w / dt * 0.95
		fy = clampf(fy, -fy_cap, fy_cap)
		# rolling resistance and soft-surface sink drag
		if absf(w.v_long) > 0.05:
			fx -= signf(w.v_long) * w.fz * (w.surface.rolling_resistance + w.surface.sink_drag * minf(absf(w.v_long), 20.0) * 0.05)
		w.fx = fx
		w.fy = fy
		var n := w.normal
		var wheel_fwd := fwd.rotated(up, -w.steer)
		var wf := (wheel_fwd - n * wheel_fwd.dot(n)).normalized()
		var ws := wf.cross(n)
		var app := w.point + n * (w.radius * 0.35)
		state.apply_force(wf * fx + ws * fy, app - xf.origin)
		var slip_mag := maxf(absf(w.slip_ratio) / 0.25, absf(w.slip_angle) / deg_to_rad(12.0))
		w.skid = clampf((slip_mag - 0.75) * 1.2, 0.0, 1.0) * clampf(speed_abs / 4.0, 0.0, 1.0)
		max_slip = maxf(max_slip, w.skid)
		if w.driven and w.slip_ratio > 0.2 and assist_tcs:
			tcs_active = true

	# ---- aero
	var v2 := lv.length_squared()
	if v2 > 1.0:
		var drag := -lv.normalized() * 0.5 * AIR_DENSITY * data.drag_area * v2
		state.apply_force(drag, com - xf.origin + b.z * 0.4)
		var fwd_speed := maxf(speed, 0.0)
		var df := 0.5 * AIR_DENSITY * data.downforce * float(mods.aero) * float(tune.aero) * fwd_speed * fwd_speed
		if grounded > 0:
			var bal := data.aero_balance
			state.apply_force(-up * df * bal, xf.basis * Vector3(0, 0.3, _axle_front_z))
			state.apply_force(-up * df * (1.0 - bal), xf.basis * Vector3(0, 0.3, _axle_rear_z))

	# ---- stability control / yaw damping
	stm_active = false
	var yaw_rate := av.dot(up)
	if grounded >= 3 and speed > 6.0:
		var avg_steer := (wheels[0].steer + wheels[1].steer) * 0.5
		var expected := -speed * tan(avg_steer) / _wheelbase
		var limit := absf(expected) + (0.12 if assist_stm else 0.6)
		var excess := yaw_rate - clampf(yaw_rate, -limit, limit)
		if assist_stm and absf(excess) > 0.0:
			stm_active = absf(excess) > 0.05
			state.apply_torque(-up * excess * _yaw_inertia * 6.0)
		# gentle high-speed yaw damping keeps 250+ km/h straight-line running calm
		var hs := clampf((speed - 30.0) / 40.0, 0.0, 1.0)
		state.apply_torque(-up * yaw_rate * _yaw_inertia * 0.6 * hs)

	# ---- air control: settle pitch/roll so jumps land on the wheels
	if grounded == 0:
		var level := up.cross(Vector3.UP)
		state.apply_torque(level * mass * 9.0)
		var ang_no_yaw := av - Vector3.UP * av.dot(Vector3.UP)
		state.apply_torque(-ang_no_yaw * mass * 0.9)
	elif grounded <= 2 and up.dot(Vector3.UP) < 0.7:
		state.apply_torque(up.cross(Vector3.UP) * mass * 6.0)

	# ---- impacts (velocity change not explained by our own forces)
	var dv := (lv - _prev_velocity).length()
	_prev_velocity = lv
	if dv > 3.0 and state.get_contact_count() > 0:
		last_impact = dv
		impact.emit(dv, state.get_contact_collider_position(0) if state.get_contact_count() > 0 else xf.origin)

	# ---- auto-recover when upside down
	if up.dot(Vector3.UP) < 0.25 and speed_abs < 3.0:
		_upside_timer += dt
		if _upside_timer > 2.5:
			_upside_timer = 0.0
			call_deferred("flip_upright")
	else:
		_upside_timer = 0.0


func _brake_wheel(w: Wheel, h: float) -> void:
	if w.brake_torque <= 0.0:
		return
	var d := w.brake_torque / w.inertia * h
	if absf(w.omega) <= d:
		w.omega = 0.0
	else:
		w.omega -= signf(w.omega) * d


func _tire_mult(s: SurfaceData) -> float:
	var t := int(data.tire_type)
	return s.tire_mults[t] if t < s.tire_mults.size() else 1.0


func _surface_for(collider: Object, p: Vector3) -> SurfaceData:
	if collider != null and collider.has_meta("surface"):
		return Surfaces.get_kind(int(collider.get_meta("surface")))
	if collider != null and collider.has_meta("terrain") and Game.world != null:
		return Surfaces.get_kind(Game.world.terrain_surface_at(p))
	return Surfaces.get_kind(SurfaceData.Kind.ASPHALT)


func _total_ratio() -> float:
	if gear > 0:
		return data.gear_ratios[gear - 1] * data.final_drive * float(tune.final_drive)
	if gear < 0:
		return -data.reverse_ratio * data.final_drive * float(tune.final_drive)
	return 0.0


# ---------------------------------------------------------------- controls
func _update_drive_inputs(dt: float) -> void:
	# arcade reverse: holding brake at a standstill engages reverse, throttle returns to drive
	var thr := in_throttle
	var brk := in_brake
	if gear >= 0:
		if speed < 0.6 and brk > 0.5 and thr < 0.1:
			_reverse_timer += dt
			if _reverse_timer > 0.25:
				_set_gear(-1)
				_reverse_timer = 0.0
		else:
			_reverse_timer = 0.0
	elif gear == -1:
		if thr > 0.3 and speed > -0.8:
			_set_gear(1)
	reversing = gear == -1
	if reversing:
		# reverse is limited to ~45 km/h like a real reverse gear at its rev range
		throttle_out = brk * clampf((12.5 + speed) / 3.0, 0.0, 1.0)
		brake_out = thr
	else:
		throttle_out = thr
		brake_out = brk
	# manual gearbox requests
	if in_shift != 0:
		if not auto_gear or gear <= 0:
			var ng := clampi(gear + in_shift, -1, data.gear_ratios.size())
			if not (gear == 1 and in_shift < 0 and speed > 1.0):
				_set_gear(ng)
		in_shift = 0


func _update_steering(dt: float) -> void:
	var spd := absf(speed)
	var t := pow(clampf(spd / 50.0, 0.0, 1.0), 0.8)
	var lock := deg_to_rad(lerpf(data.max_steer_deg, data.high_speed_steer_deg, t))
	var target := in_steer * lock
	if assist_steer and speed > 4.0:
		# counter-steer help: bias the wheels toward the direction of travel while sliding
		target += clampf(body_slip * 0.75, -lock * 0.9, lock * 0.9) * (1.0 - absf(in_steer) * 0.5)
	target = clampf(target, -deg_to_rad(data.max_steer_deg), deg_to_rad(data.max_steer_deg))
	var rate := data.steer_speed * (1.6 if absf(target) < absf(steer_angle) else 1.0)
	steer_angle = move_toward(steer_angle, target, rate * dt)
	# Ackermann geometry
	var track := absf(wheels[0].rest_pos.x - wheels[1].rest_pos.x) if wheels.size() == 4 else 1.5
	if absf(steer_angle) < 0.0005:
		for i in 2:
			wheels[i].steer = 0.0
	else:
		var r := _wheelbase / tan(absf(steer_angle))
		var inner := atan(_wheelbase / maxf(r - track * 0.5, 0.5))
		var outer := atan(_wheelbase / (r + track * 0.5))
		var sgn := signf(steer_angle)
		# right turn (positive): right wheel (index 1) is inner
		wheels[1].steer = sgn * (inner if sgn > 0 else outer)
		wheels[0].steer = sgn * (outer if sgn > 0 else inner)


func _powertrain(dt: float) -> void:
	var ratio := _total_ratio()
	var n_gears := data.gear_ratios.size()
	var driven_omega := 0.0
	var n := 0
	for w in wheels:
		if w.driven:
			driven_omega += w.omega
			n += 1
	driven_omega /= maxf(n, 1)
	var wheel_rpm := absf(driven_omega * ratio) * 60.0 / TAU
	var thr := throttle_out
	# traction control: trim throttle when driven wheels spin up
	var spin_slip := 0.0
	for w in wheels:
		if w.driven and w.contact:
			spin_slip = maxf(spin_slip, w.slip_ratio)
	var tcs_lim := 0.16
	for w in wheels:
		if w.driven and w.contact and not w.surface.paved:
			tcs_lim = 0.28
	if assist_tcs and spin_slip > tcs_lim:
		thr *= clampf(1.0 - (spin_slip - tcs_lim) * 3.0, 0.3, 1.0)
	if stm_active:
		thr *= 0.6
	# automatic gearbox: decisions use ground speed (not spinning wheels) plus a cooldown
	if shift_timer > 0.0:
		shift_timer -= dt
	_shift_cooldown = maxf(_shift_cooldown - dt, 0.0)
	if auto_gear and gear >= 1 and grounded >= 2 and shift_timer <= 0.0 and _shift_cooldown <= 0.0:
		var r_avg := (wheels[2].radius + wheels[0].radius) * 0.5
		var ground_omega := maxf(speed, 0.0) / r_avg
		var fd := data.final_drive * float(tune.final_drive)
		# light throttle short-shifts like a road automatic; full throttle holds to the redline
		var up_rpm := data.redline_rpm * lerpf(0.55, 0.97, clampf((thr - 0.2) / 0.7, 0.0, 1.0))
		if rpm > up_rpm and gear < n_gears:
			var next_rpm := ground_omega * data.gear_ratios[gear] * fd * 60.0 / TAU
			# part throttle needs margin above the downshift point (no hunting); at full throttle the
			# downshift guard below already stops a shift back into the limiter
			var min_next := 0.42 if thr > 0.85 else maxf(0.42, lerpf(0.36, 0.58, thr) + 0.05)
			if next_rpm > data.redline_rpm * min_next:
				_set_gear(gear + 1)
				_shift_cooldown = 0.7
		elif gear > 1:
			var cur_rpm := ground_omega * data.gear_ratios[gear - 1] * fd * 60.0 / TAU
			var lower := ground_omega * data.gear_ratios[gear - 2] * fd * 60.0 / TAU
			var down_rpm := data.redline_rpm * lerpf(0.36, 0.58, thr)
			if cur_rpm < down_rpm and lower < data.redline_rpm * 0.86:
				_set_gear(gear - 1)
				_shift_cooldown = 0.7
	# engine speed: clutch slips below the launch speed
	var launch := lerpf(data.idle_rpm + 250.0, data.redline_rpm * 0.55, thr)
	var target_rpm := wheel_rpm
	var clutch_slip := false
	if gear == 0:
		target_rpm = lerpf(data.idle_rpm, data.redline_rpm, thr)
	elif shift_timer > 0.0:
		target_rpm = wheel_rpm
	elif wheel_rpm < launch:
		target_rpm = launch
		clutch_slip = true
	target_rpm = clampf(target_rpm, data.idle_rpm * 0.95, data.max_rpm)
	var rate := 26000.0 if target_rpm > rpm else 18000.0
	rpm = move_toward(rpm, target_rpm, rate * dt)
	# engine torque
	var t_eng := 0.0
	engine_load = 0.0
	if gear != 0 and shift_timer <= 0.0:
		var limiter := rpm >= data.max_rpm - 40.0
		var eff_thr := 0.0 if limiter else thr
		t_eng = data.torque_at(rpm) * eff_thr * float(mods.power)
		engine_load = eff_thr
		if not clutch_slip:
			var eb := data.engine_brake * data.torque_at(rpm) * (1.0 - thr) * clampf((rpm - data.idle_rpm) / (data.max_rpm - data.idle_rpm), 0.0, 1.0)
			t_eng -= eb
	var t_wheels := t_eng * ratio * 0.9
	for w in wheels:
		w.drive_torque = 0.0
	match data.drivetrain:
		CarData.Drivetrain.FWD:
			wheels[0].drive_torque = t_wheels * 0.5
			wheels[1].drive_torque = t_wheels * 0.5
		CarData.Drivetrain.RWD:
			wheels[2].drive_torque = t_wheels * 0.5
			wheels[3].drive_torque = t_wheels * 0.5
		_:
			var fs := data.awd_front_split
			wheels[0].drive_torque = t_wheels * fs * 0.5
			wheels[1].drive_torque = t_wheels * fs * 0.5
			wheels[2].drive_torque = t_wheels * (1.0 - fs) * 0.5
			wheels[3].drive_torque = t_wheels * (1.0 - fs) * 0.5


func _set_gear(g: int) -> void:
	if g == gear:
		return
	var was := gear
	gear = g
	if was != 0 and g != 0 and signi(was) == signi(g):
		shift_timer = data.shift_time
	gear_changed.emit(gear)


func request_shift(dir: int) -> void:
	if auto_gear and gear >= 1:
		return
	in_shift = dir


# ----------------------------------------------------------------- helpers
func flip_upright() -> void:
	var xf := global_transform
	var fwd := -xf.basis.z
	fwd.y = 0.0
	if fwd.length() < 0.1:
		fwd = Vector3.FORWARD
	teleport(xf.origin + Vector3.UP * 1.2, fwd.normalized())


func teleport(pos: Vector3, forward: Vector3, keep_speed := 0.0) -> void:
	var basis := Basis.looking_at(forward.normalized(), Vector3.UP)
	var xf := Transform3D(basis, pos)
	PhysicsServer3D.body_set_state(get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM, xf)
	global_transform = xf
	linear_velocity = forward.normalized() * keep_speed
	angular_velocity = Vector3.ZERO
	_prev_velocity = linear_velocity
	for w in wheels:
		w.omega = keep_speed / w.radius
		w.length = w.rest_ext
		w.prev_length = w.rest_ext
	reset_physics_interpolation()


func kmh() -> float:
	return speed_abs * 3.6


func wheel_count_on(kind: int) -> int:
	var c := 0
	for w in wheels:
		if w.contact and w.surface != null and int(w.surface.kind) == kind:
			c += 1
	return c


func dominant_surface() -> SurfaceData:
	for w in wheels:
		if w.contact and w.surface != null:
			return w.surface
	return null


func _physics_process(_delta: float) -> void:
	if visual != null and not wheels.is_empty():
		visual.update_from_car(self)
		var s := dominant_surface()
		if s != null:
			surface_name = s.display_name
