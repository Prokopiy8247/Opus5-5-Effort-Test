class_name CarController
extends RigidBody3D
## Project-owned raycast vehicle on a Jolt RigidBody3D.
## - one ray per wheel, spring/damper/bump-stop suspension with anti-roll bars (weight transfer
##   emerges from the per-wheel loads),
## - combined-slip tyre model (normalised slip ratio + slip angle on a friction ellipse,
##   surface- and weather-dependent grip, load sensitivity),
## - wheel spin integrated implicitly in sub-steps (stable at 120 Hz with stiff tyres),
## - engine torque curve, clutch slip at launch, rev limiter, automatic/manual gearbox,
##   FWD/RWD/AWD with a limited-slip differential, brakes with bias, ABS, handbrake,
## - aero drag/downforce, traction control, stability control, steering assist,
##   air stabilisation and flip recovery.
## Inputs are written by a PlayerInput or an AI driver; the controller never reads devices.

signal gear_changed(gear: int)
signal impact(strength: float, world_point: Vector3)
signal reset_done

enum ControlMode { NONE, PLAYER, AI }

const AIR_DENSITY := 1.225
const V_MIN := 2.5
const SUBSTEPS := 3
## Global arcade grip gain over the per-car tyre values.
const GRIP_GAIN := 1.08
const LAYER_WORLD := 1
const LAYER_PLAYER := 2
const LAYER_TRAFFIC := 4

class Wheel:
	extends RefCounted
	var name: String = ""
	var node: Node3D
	var base_basis: Basis = Basis.IDENTITY
	var caliper: Node3D
	var caliper_base: Transform3D = Transform3D.IDENTITY
	var front: bool = true
	var left: bool = true
	var driven: bool = false
	var radius: float = 0.33
	var width: float = 0.22
	var center_rest: Vector3 = Vector3.ZERO
	var steer: float = 0.0
	var x: float = 0.0
	var prev_x: float = 0.0
	var contact: bool = false
	var point: Vector3 = Vector3.ZERO
	var normal: Vector3 = Vector3.UP
	var surface: int = 0
	var omega: float = 0.0
	var spin_angle: float = 0.0
	var load: float = 0.0
	var static_load: float = 3000.0
	var spring_k: float = 40000.0
	var x0: float = 0.0
	var damp_bump: float = 3000.0
	var damp_reb: float = 4500.0
	var arb: float = 0.0
	var slip_ratio: float = 0.0
	var slip_angle: float = 0.0
	var slip: float = 0.0
	var fx: float = 0.0
	var fy: float = 0.0
	var drive_torque: float = 0.0
	var brake_torque: float = 0.0
	var inertia: float = 1.0
	var abs_factor: float = 1.0
	var v_long: float = 0.0
	var v_lat: float = 0.0
	var grip: float = 1.0
	var bump_phase: float = 0.0

@export var definition: CarDefinition
@export var control_mode: ControlMode = ControlMode.PLAYER

# --- inputs (0..1, steer -1..1) -------------------------------------------------------------
var input_throttle: float = 0.0
var input_brake: float = 0.0
var input_steer: float = 0.0
var input_handbrake: float = 0.0
var input_shift_up: bool = false
var input_shift_down: bool = false

# --- assists ----------------------------------------------------------------------------------
var assist_tcs: bool = true
var assist_esc: bool = true
var assist_abs: bool = true
var assist_steer: bool = true
var auto_gearbox: bool = true
## Global grip multiplier from weather (1 = dry).
var wetness: float = 0.0
var grip_scale: float = 1.0
var power_scale: float = 1.0
## For AI traffic: simpler, cheaper settings.
var simplified: bool = false

# --- state ------------------------------------------------------------------------------------
var wheels: Array[Wheel] = []
var gear: int = 1
var rpm: float = 900.0
var shift_timer: float = 0.0
var limiter_timer: float = 0.0
var steer_angle: float = 0.0
var speed_kmh: float = 0.0
var forward_speed: float = 0.0
var body_slip_deg: float = 0.0
var grounded_wheels: int = 0
var airborne_time: float = 0.0
var upside_down_time: float = 0.0
var throttle_effective: float = 0.0
var tcs_factor: float = 1.0
var tcs_trim: float = 1.0
var tcs_grip_torque: float = 0.0
var esc_throttle: float = 1.0
var tcs_active: bool = false
var abs_active: bool = false
var esc_active: bool = false
var turbo_boost: float = 0.0
var reversing: bool = false
var g_force: Vector3 = Vector3.ZERO
var odometer_m: float = 0.0
var last_shift_up: bool = true
var engine_load: float = 0.0
var exhaust_pop_signal: float = 0.0
var surface_under: int = 0

var _prev_velocity: Vector3 = Vector3.ZERO
var _reverse_hold: float = 0.0
var _query: PhysicsRayQueryParameters3D
var _wheelbase: float = 2.6
var _track: float = 1.55
var _com_height: float = 0.5
var _front_axle_z: float = -1.3
var _rear_axle_z: float = 1.3
var _yaw_inertia: float = 2000.0
var _ready_ok: bool = false
var _roll_center: float = 0.18
var _terrain_surface_cb: Callable


func setup(def: CarDefinition, wheel_nodes: Dictionary, body_size: Vector3) -> void:
	## Called by CarFactory once the model is attached. wheel_nodes: "FL","FR","RL","RR" -> Node3D
	## (pivot at the axle centre, positioned in this body's local space).
	definition = def
	mass = def.mass
	wheels.clear()
	for key in ["FL", "FR", "RL", "RR"]:
		var w := Wheel.new()
		w.name = key
		w.front = key.begins_with("F")
		w.left = key.ends_with("L")
		var n: Node3D = wheel_nodes.get(key)
		if n != null:
			w.node = n
			w.base_basis = n.transform.basis
			w.center_rest = n.transform.origin
			var aabb := _node_aabb(n)
			if aabb.size != Vector3.ZERO:
				w.radius = maxf(aabb.size.y, aabb.size.z) * 0.5
				w.width = aabb.size.x
		var cal: Node3D = wheel_nodes.get("Caliper_" + key)
		if cal != null:
			w.caliper = cal
			w.caliper_base = cal.transform
		if w.front and def.wheel_radius_front > 0.0:
			w.radius = def.wheel_radius_front
		elif not w.front and def.wheel_radius_rear > 0.0:
			w.radius = def.wheel_radius_rear
		match def.drivetrain:
			CarDefinition.Drivetrain.FWD:
				w.driven = w.front
			CarDefinition.Drivetrain.RWD:
				w.driven = not w.front
			_:
				w.driven = true
		wheels.append(w)

	_front_axle_z = (wheels[0].center_rest.z + wheels[1].center_rest.z) * 0.5
	_rear_axle_z = (wheels[2].center_rest.z + wheels[3].center_rest.z) * 0.5
	_wheelbase = absf(_rear_axle_z - _front_axle_z)
	_track = absf(wheels[0].center_rest.x - wheels[1].center_rest.x)
	var mid := Vector3.ZERO
	for w in wheels:
		mid += w.center_rest
	mid /= 4.0
	var com := mid + def.com_offset
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = com
	_com_height = com.y
	# Box-approximated inertia, tuned per car.
	var l := maxf(body_size.z, _wheelbase + 1.0)
	var wdt := maxf(body_size.x, _track + 0.2)
	var h := maxf(body_size.y, 1.0)
	inertia = Vector3(
		mass / 12.0 * (h * h + l * l) * def.inertia_scale.x,
		mass / 12.0 * (wdt * wdt + l * l) * def.inertia_scale.y,
		mass / 12.0 * (wdt * wdt + h * h) * def.inertia_scale.z)
	_yaw_inertia = inertia.y

	# Static loads -> springs with preload so that the car sits at the modelled ride height.
	var front_frac := clampf((_rear_axle_z - com.z) / maxf(_wheelbase, 0.5), 0.2, 0.8)
	var g := 9.81
	for w in wheels:
		var frac := front_frac if w.front else (1.0 - front_frac)
		w.static_load = mass * g * frac * 0.5
		var hz := def.spring_hz_front if w.front else def.spring_hz_rear
		var corner_mass := w.static_load / g
		w.spring_k = corner_mass * pow(TAU * hz, 2.0)
		w.x0 = def.travel_down - w.static_load / w.spring_k
		var crit := 2.0 * sqrt(w.spring_k * corner_mass)
		w.damp_bump = crit * def.damping_bump
		w.damp_reb = crit * def.damping_rebound
		w.arb = def.anti_roll_front if w.front else def.anti_roll_rear
		w.x = def.travel_down
		w.prev_x = w.x
		w.inertia = 0.5 * def.wheel_mass * w.radius * w.radius + 0.4
		w.bump_phase = randf() * 100.0

	gravity_scale = 1.0
	linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	linear_damp = 0.0
	angular_damp = 0.05
	continuous_cd = true
	can_sleep = false
	contact_monitor = false
	physics_material_override = PhysicsMaterial.new()
	physics_material_override.friction = 0.35
	physics_material_override.bounce = 0.05

	_query = PhysicsRayQueryParameters3D.new()
	_query.collision_mask = LAYER_WORLD
	_query.exclude = [get_rid()]
	_query.hit_back_faces = false
	rpm = def.idle_rpm
	gear = 1
	_prev_velocity = linear_velocity
	_ready_ok = true


static func _node_aabb(n: Node3D) -> AABB:
	var result := AABB()
	var first := true
	for c in n.find_children("*", "MeshInstance3D", true, false):
		var mi := c as MeshInstance3D
		if mi.mesh == null:
			continue
		var rel := Transform3D.IDENTITY
		var p: Node = mi
		while p != null and p != n:
			rel = (p as Node3D).transform * rel
			p = p.get_parent()
		var box := rel * mi.mesh.get_aabb()
		if first:
			result = box
			first = false
		else:
			result = result.merge(box)
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		var own := (n as MeshInstance3D).mesh.get_aabb()
		result = own if first else result.merge(own)
	return result


func set_terrain_surface_callback(cb: Callable) -> void:
	_terrain_surface_cb = cb


# =================================================================================================
func _physics_process(delta: float) -> void:
	if not _ready_ok or freeze:
		return
	var def := definition
	var xf := global_transform
	var b := xf.basis.orthonormalized()
	var up := b.y
	var fwd := -b.z
	var right := b.x
	var vel := linear_velocity
	var angv := angular_velocity
	var com_global := xf * center_of_mass

	forward_speed = vel.dot(fwd)
	speed_kmh = vel.length() * 3.6
	odometer_m += vel.length() * delta
	var accel := (vel - _prev_velocity) / delta
	_prev_velocity = vel
	g_force = Vector3(accel.dot(right), accel.dot(up), -accel.dot(fwd)) / 9.81
	var dv := accel.length() * delta
	if dv > 4.0:
		impact.emit(dv, global_position)

	_update_steering(delta, vel, fwd, right, angv, up)
	_update_gearbox(delta)

	# ---------------------------------------------------------------- suspension raycasts
	var space := get_world_3d().direct_space_state
	var travel_total := def.travel_up + def.travel_down
	grounded_wheels = 0
	for w in wheels:
		var top_local := w.center_rest + Vector3(0.0, def.travel_up, 0.0)
		var origin := xf * top_local
		var length := travel_total + w.radius
		_query.from = origin
		_query.to = origin - up * length
		var hit := space.intersect_ray(_query)
		w.prev_x = w.x
		if hit.is_empty():
			w.contact = false
			w.x = maxf(w.x - delta * 2.5, 0.0)
			w.load = 0.0
		else:
			var dist := origin.distance_to(hit.position)
			w.contact = true
			w.point = hit.position
			w.normal = hit.normal
			w.x = clampf(length - dist, 0.0, travel_total + 0.08)
			w.surface = _surface_from_hit(hit)
			var sdef := Surfaces.get_def(w.surface)
			if sdef.bumpiness > 0.0 and not simplified:
				w.bump_phase += absf(forward_speed) * delta * 0.9
				w.x += sdef.bumpiness * (sin(w.bump_phase * 2.3) * 0.6 + sin(w.bump_phase * 5.1 + 1.3) * 0.4)
			grounded_wheels += 1
	surface_under = wheels[2].surface if wheels[2].contact else wheels[0].surface

	# ---------------------------------------------------------------- suspension forces / loads
	for i in 4:
		var w := wheels[i]
		if not w.contact:
			continue
		var other := wheels[i ^ 1]
		var xv := (w.x - w.prev_x) / delta
		var f_spring := w.spring_k * (w.x - w.x0)
		var f_damp := xv * (w.damp_bump if xv > 0.0 else w.damp_reb)
		var f_arb := w.arb * (w.x - (other.x if other.contact else def.travel_down * 0.3))
		var f_stop := 0.0
		if w.x > travel_total - 0.015:
			f_stop = (w.x - (travel_total - 0.015)) * w.spring_k * 12.0 + maxf(xv, 0.0) * w.damp_bump * 3.0
		var f := maxf(f_spring + f_damp + f_arb + f_stop, 0.0)
		w.load = minf(f, w.static_load * 6.0)
		var p := xf * Vector3(w.center_rest.x, w.center_rest.y, w.center_rest.z)
		apply_force(up * f, p - global_position)

	# ---------------------------------------------------------------- drivetrain torque split
	var total_wheel_torque := _engine_torque_at_wheels(delta)
	var driven_count := 0
	for w in wheels:
		w.drive_torque = 0.0
		if w.driven:
			driven_count += 1
	if driven_count > 0:
		var front_t := 0.0
		var rear_t := 0.0
		match def.drivetrain:
			CarDefinition.Drivetrain.FWD:
				front_t = total_wheel_torque
			CarDefinition.Drivetrain.RWD:
				rear_t = total_wheel_torque
			_:
				front_t = total_wheel_torque * def.awd_front_split
				rear_t = total_wheel_torque * (1.0 - def.awd_front_split)
		_split_axle(wheels[0], wheels[1], front_t)
		_split_axle(wheels[2], wheels[3], rear_t)

	# ---------------------------------------------------------------- brakes
	var brake_in := input_brake
	if reversing:
		brake_in = input_throttle
	var front_brake := def.brake_torque * def.brake_bias * brake_in
	var rear_brake := def.brake_torque * (1.0 - def.brake_bias) * brake_in
	for w in wheels:
		w.brake_torque = front_brake if w.front else rear_brake
		if not w.front:
			w.brake_torque += def.handbrake_torque * input_handbrake
	# parking hold when nearly stopped with no throttle
	if absf(forward_speed) < 0.6 and throttle_effective < 0.02 and not reversing:
		for w in wheels:
			w.brake_torque = maxf(w.brake_torque, 600.0)

	# ---------------------------------------------------------------- reflected inertia
	var ratio := _total_ratio()
	var clutch_in := shift_timer <= 0.0 and gear != 0
	for w in wheels:
		var base_i := 0.5 * def.wheel_mass * w.radius * w.radius + 0.4
		if w.driven and clutch_in and driven_count > 0:
			w.inertia = base_i + def.engine_inertia * ratio * ratio / float(driven_count)
		else:
			w.inertia = base_i

	# ---------------------------------------------------------------- tyre contact kinematics
	var abs_any := false
	var tcs_slip := 0.0
	var total_force := Vector3.ZERO
	for w in wheels:
		if not w.contact:
			# free wheel: driven wheels still receive torque, brakes clamp towards zero
			var free_omega := w.omega + w.drive_torque / w.inertia * delta
			free_omega = move_toward(free_omega, 0.0, delta * 2.0)
			var bstep_air := w.brake_torque * 2.0 * delta / w.inertia
			w.omega = 0.0 if absf(free_omega) <= bstep_air else free_omega - signf(free_omega) * bstep_air
			w.fx = 0.0
			w.fy = 0.0
			w.slip = 0.0
			continue
		var n := w.normal
		var wheel_fwd := fwd.rotated(up, -w.steer)
		var f_ground := (wheel_fwd - n * n.dot(wheel_fwd)).normalized()
		var r_ground := f_ground.cross(n).normalized()
		var r := w.point - com_global
		var v_point := vel + angv.cross(r)
		w.v_long = v_point.dot(f_ground)
		w.v_lat = v_point.dot(r_ground)
		var sdef := Surfaces.get_def(w.surface)
		var mu := def.tire_grip * sdef.grip * grip_scale * GRIP_GAIN
		mu *= def.grip_front if w.front else def.grip_rear
		if sdef.loose > 0.0:
			mu *= lerpf(1.0, def.offroad_grip, sdef.loose)
		elif def.offroad_grip > 1.0:
			mu *= 1.0 - (def.offroad_grip - 1.0) * 0.12
		mu *= lerpf(1.0, sdef.wet_grip, wetness if Surfaces.is_paved(w.surface) else wetness * 0.6)
		var load_ratio := w.load / maxf(w.static_load, 1.0)
		mu *= clampf(1.0 - def.load_sensitivity * (load_ratio - 1.0), 0.55, 1.25)
		w.grip = mu
		var kp := def.slip_ratio_peak * sdef.slip_peak_scale
		var ap := deg_to_rad(def.slip_angle_peak_deg) * sdef.slip_peak_scale
		var slide := lerpf(def.slide_ratio, sdef.slide_ratio, 0.5)
		var denom_v := maxf(absf(w.v_long), V_MIN)
		w.slip_angle = atan2(w.v_lat, denom_v)
		var fz := w.load

		# implicit sub-stepped wheel spin
		var h := delta / float(SUBSTEPS)
		var fx_acc := 0.0
		for _s in SUBSTEPS:
			var kappa := (w.omega * w.radius - w.v_long) / denom_v
			var fxy := _tire(kappa, w.slip_angle, fz, mu, kp, ap, slide)
			var fx0 := fxy.x
			var eps := 0.01
			var fx1 := _tire(kappa + eps, w.slip_angle, fz, mu, kp, ap, slide).x
			var dfdo := maxf((fx1 - fx0) / eps, 0.0) * w.radius / denom_v
			var rr := sdef.rolling_resistance * fz * w.radius * signf(w.omega)
			var soft := sdef.soft_drag * fz * 0.001 * w.v_long * w.radius
			var net := w.drive_torque - w.radius * fx0 - rr - soft
			var den := w.inertia + h * w.radius * dfdo
			var omega_free := w.omega + h * net / den
			var bt := w.brake_torque
			if assist_abs and bt > 1.0 and not (not w.front and input_handbrake > 0.1):
				if kappa < -kp * 1.25:
					w.abs_factor = maxf(w.abs_factor - 0.35, 0.25)
					abs_any = true
				else:
					w.abs_factor = minf(w.abs_factor + 0.08, 1.0)
				bt *= w.abs_factor
			var bstep := h * bt / den
			if absf(omega_free) <= bstep:
				w.omega = 0.0
			else:
				w.omega = omega_free - signf(omega_free) * bstep
			fx_acc += fx0
		var kappa_f := (w.omega * w.radius - w.v_long) / denom_v
		w.slip_ratio = kappa_f
		var ff := _tire(kappa_f, w.slip_angle, fz, mu, kp, ap, slide)
		w.fx = fx_acc / float(SUBSTEPS)
		w.fy = ff.y
		w.slip = sqrt(pow(kappa_f / kp, 2.0) + pow(w.slip_angle / ap, 2.0))
		if w.driven:
			tcs_slip = maxf(tcs_slip, kappa_f / kp)
		var force := f_ground * w.fx + r_ground * w.fy
		# soft surfaces: extra drag
		if sdef.soft_drag > 0.0:
			force -= f_ground * w.v_long * sdef.soft_drag * fz * 0.001
		var app := w.point + up * minf(_roll_center, _com_height * 0.6)
		apply_force(force, app - global_position)
		total_force += force
	abs_active = abs_any

	# traction control: feed-forward wheel-torque cap from the grip available at the driven
	# wheels (computed for the next tick) plus an integral slip trim
	tcs_grip_torque = 0.0
	for w in wheels:
		if w.driven and w.contact:
			tcs_grip_torque += w.grip * w.load * w.radius * 1.04
	if assist_tcs and gear != 0:
		if tcs_slip > 1.15:
			tcs_trim = maxf(tcs_trim - delta * (tcs_slip - 1.15) * 2.5, 0.45)
		else:
			tcs_trim = minf(tcs_trim + delta * 0.8, 1.15)
	else:
		tcs_trim = 1.0

	_apply_aero(vel, fwd, up, xf)
	_apply_stability(delta, vel, fwd, right, up, angv)

	# wheel visuals
	for w in wheels:
		w.spin_angle = wrapf(w.spin_angle + w.omega * delta, -TAU * 50.0, TAU * 50.0)
		_update_wheel_visual(w)


func _tire(kappa: float, alpha: float, fz: float, mu: float, kp: float, ap: float, slide: float) -> Vector2:
	var sx := kappa / kp
	var sy := alpha / ap
	var s := sqrt(sx * sx + sy * sy)
	if s < 1e-5:
		return Vector2.ZERO
	var f: float
	if s <= 1.0:
		f = s * (2.0 - s)
	else:
		f = slide + (1.0 - slide) * exp(-(s - 1.0) * 1.4)
	var mag := mu * fz * f
	return Vector2(mag * sx / s * 1.05, -mag * sy / s)


func _surface_from_hit(hit: Dictionary) -> int:
	var col: Object = hit.get("collider")
	if col != null:
		if col.has_meta("surface"):
			return int(col.get_meta("surface"))
		if col.has_meta("terrain") and _terrain_surface_cb.is_valid():
			var p: Vector3 = hit.position
			return int(_terrain_surface_cb.call(p.x, p.z))
	return Surfaces.ASPHALT


func _split_axle(wl: Wheel, wr: Wheel, torque: float) -> void:
	if not wl.driven and not wr.driven:
		return
	var half := torque * 0.5
	var lock := definition.diff_lock
	var d_omega := wl.omega - wr.omega
	var max_transfer := absf(torque) * 0.5 * lock + 40.0 * lock
	var transfer := clampf(d_omega * 60.0 * lock, -max_transfer, max_transfer)
	wl.drive_torque = half - transfer
	wr.drive_torque = half + transfer


# =================================================================================================
func _update_steering(delta: float, vel: Vector3, fwd: Vector3, right: Vector3, angv: Vector3, up: Vector3) -> void:
	var def := definition
	var v := absf(forward_speed)
	var t := clampf(v / 55.0, 0.0, 1.0)
	var lock := lerpf(def.steer_lock_deg, def.steer_high_speed_deg, pow(t, 0.75))
	var desired := input_steer * lock
	# body slip angle (positive = sliding to the right)
	var v_lat := vel.dot(right)
	var v_long := vel.dot(fwd)
	if v > 3.0:
		body_slip_deg = rad_to_deg(atan2(v_lat, absf(v_long)))
	else:
		body_slip_deg = 0.0
	if assist_steer and v > 4.0 and v_long > 0.0:
		# counter-steer towards the direction of travel when the rear steps out
		var counter := clampf(body_slip_deg * 0.55, -def.steer_lock_deg * 0.8, def.steer_lock_deg * 0.8)
		var w := smoothstep(2.0, 10.0, absf(body_slip_deg))
		desired = lerpf(desired, desired * 0.35 + counter, w * (1.0 - absf(input_steer) * 0.35))
	desired = clampf(desired, -def.steer_lock_deg, def.steer_lock_deg)
	var rate := def.steer_speed * 57.3 * (1.6 if absf(desired) < absf(steer_angle) else 1.0)
	steer_angle = move_toward(steer_angle, desired, rate * delta)
	var a := deg_to_rad(steer_angle)
	# Ackermann: the inner wheel steers more
	var inner := a * (1.0 + 0.12 * absf(a))
	var outer := a * (1.0 - 0.08 * absf(a))
	if a >= 0.0:
		wheels[0].steer = outer
		wheels[1].steer = inner
	else:
		wheels[0].steer = inner
		wheels[1].steer = outer
	wheels[2].steer = 0.0
	wheels[3].steer = 0.0


func _total_ratio() -> float:
	var def := definition
	if gear == 0:
		return 0.0
	if gear < 0:
		return -def.reverse_ratio * def.final_drive
	return def.gear_ratios[clampi(gear - 1, 0, def.gear_ratios.size() - 1)] * def.final_drive


func _driven_omega() -> float:
	var s := 0.0
	var c := 0
	for w in wheels:
		if w.driven:
			s += w.omega
			c += 1
	return s / maxf(float(c), 1.0)


func _update_gearbox(delta: float) -> void:
	var def := definition
	var top := def.gear_ratios.size()
	if shift_timer > 0.0:
		shift_timer -= delta
	var v := forward_speed
	# automatic reverse engagement: hold brake at standstill
	if auto_gearbox or control_mode == ControlMode.AI:
		if not reversing and v < 1.0 and input_brake > 0.3 and input_throttle < 0.1:
			_reverse_hold += delta
			if _reverse_hold > 0.35:
				reversing = true
				_set_gear(-1)
		elif reversing and v > -1.0 and input_throttle > 0.3 and input_brake < 0.1:
			reversing = false
			_reverse_hold = 0.0
			_set_gear(1)
		elif not (input_brake > 0.3 and v < 1.0):
			_reverse_hold = 0.0
		if reversing:
			return
		if gear < 1:
			_set_gear(1)
			return
		if shift_timer > 0.0:
			return
		var redline := def.redline_rpm
		var spin := 0.0
		for w in wheels:
			if w.driven and w.contact:
				spin = maxf(spin, w.slip_ratio)
		if gear < top and rpm > redline * 0.965 and throttle_effective > 0.1 and spin < 0.35:
			_set_gear(gear + 1)
		elif gear > 1:
			var ratio_now := def.gear_ratios[gear - 1]
			var ratio_down := def.gear_ratios[gear - 2]
			var rpm_after := rpm * ratio_down / ratio_now
			var low := 0.52 if input_throttle > 0.5 else 0.38
			if input_brake > 0.3:
				low = 0.62
			if rpm < redline * low and rpm_after < redline * 0.9:
				_set_gear(gear - 1)
	else:
		if input_shift_up:
			if gear == -1:
				_set_gear(0)
			elif gear < top:
				_set_gear(gear + 1)
		if input_shift_down:
			if gear > 1:
				_set_gear(gear - 1)
			elif gear == 1:
				_set_gear(0)
			elif gear == 0 and absf(v) < 2.0:
				_set_gear(-1)
		reversing = gear == -1
	input_shift_up = false
	input_shift_down = false


func _set_gear(g: int) -> void:
	if g == gear:
		return
	last_shift_up = g > gear
	gear = g
	shift_timer = definition.shift_time if g > 0 else 0.05
	if last_shift_up and throttle_effective > 0.5:
		exhaust_pop_signal = 1.0
	gear_changed.emit(gear)


func _engine_torque_at_wheels(delta: float) -> float:
	var def := definition
	var throttle := input_throttle
	if reversing:
		throttle = input_brake
	throttle = clampf(throttle, 0.0, 1.0)
	if shift_timer > 0.0:
		throttle_effective = 0.0
	else:
		throttle_effective = throttle * esc_throttle
	var ratio := _total_ratio()
	var wheel_rpm := absf(_driven_omega() * ratio) * 60.0 / TAU
	var idle := def.idle_rpm
	var redline := def.redline_rpm
	var transmitted := 0.0
	if gear == 0 or shift_timer > 0.0:
		var target := lerpf(idle, redline * 0.92, throttle)
		if shift_timer > 0.0 and gear != 0:
			target = clampf(wheel_rpm, idle, redline)
		rpm = move_toward(rpm, target, delta * (redline * (2.5 if gear == 0 else 6.0)))
	else:
		var launch := lerpf(idle * 1.15, redline * 0.5, throttle)
		if wheel_rpm < launch:
			rpm = lerpf(rpm, launch, 1.0 - exp(-delta * 10.0))
		else:
			rpm = lerpf(rpm, wheel_rpm, 1.0 - exp(-delta * 40.0))
	rpm = clampf(rpm, idle * 0.85, redline * 1.04)
	# rev limiter with a short hysteresis cut
	if rpm >= redline * 1.0:
		limiter_timer = 0.06
	if limiter_timer > 0.0:
		limiter_timer -= delta
		throttle_effective = 0.0
	var norm := clampf((rpm - idle) / maxf(redline - idle, 1.0), 0.0, 1.0)
	# turbo spool
	if def.turbo:
		var target_boost := throttle_effective * smoothstep(0.15, 0.55, norm)
		turbo_boost = move_toward(turbo_boost, target_boost, delta / maxf(def.turbo_lag, 0.05))
	else:
		turbo_boost = throttle_effective
	var torque := def.torque_at(norm) * def.max_torque_nm * power_scale
	var drive := torque * (throttle_effective if not def.turbo else lerpf(throttle_effective * 0.6, throttle_effective, turbo_boost))
	var engine_brake := def.engine_brake_torque * norm * (1.0 - throttle)
	engine_load = clampf(throttle_effective, 0.0, 1.0)
	if gear == 0 or shift_timer > 0.0:
		return 0.0
	transmitted = (drive - engine_brake) * ratio * def.drivetrain_efficiency
	# traction control cap (see _physics_process): never ask more of the tyres than they can give
	tcs_active = false
	tcs_factor = 1.0
	if assist_tcs and transmitted > 0.0 and grounded_wheels > 0:
		var cap := tcs_grip_torque * tcs_trim
		if transmitted > cap:
			tcs_factor = cap / transmitted
			transmitted = cap
			tcs_active = tcs_factor < 0.95
	if exhaust_pop_signal > 0.0:
		exhaust_pop_signal = maxf(exhaust_pop_signal - delta * 3.0, 0.0)
	if throttle < 0.05 and norm > 0.6 and randf() < 0.04 * def.exhaust_pop:
		exhaust_pop_signal = 1.0
	return transmitted


func _apply_aero(vel: Vector3, fwd: Vector3, up: Vector3, xf: Transform3D) -> void:
	var def := definition
	var v2 := vel.length_squared()
	if v2 < 0.25:
		return
	var drag := -vel.normalized() * 0.5 * AIR_DENSITY * def.drag_area * v2
	apply_central_force(drag)
	var vf := vel.dot(fwd)
	var down := 0.5 * AIR_DENSITY * def.downforce_area * vf * vf
	if grounded_wheels == 0:
		down *= 0.25
	var front_p := xf * Vector3(0.0, _com_height, _front_axle_z)
	var rear_p := xf * Vector3(0.0, _com_height, _rear_axle_z)
	apply_force(-up * down * def.aero_balance, front_p - global_position)
	apply_force(-up * down * (1.0 - def.aero_balance), rear_p - global_position)


func _apply_stability(delta: float, vel: Vector3, fwd: Vector3, right: Vector3, up: Vector3, angv: Vector3) -> void:
	var def := definition
	var v := vel.length()
	# airborne: gently level the car so that jumps land on the wheels
	if grounded_wheels == 0:
		airborne_time += delta
		var axis := up.cross(Vector3.UP)
		var level_torque := axis * 2.2 * _yaw_inertia
		var damp := -(angv - up * angv.dot(up)) * 0.9 * _yaw_inertia
		apply_torque(level_torque + damp)
	else:
		airborne_time = 0.0
	# roll assist (arcade): balanced on one or two wheels and leaning hard (wall ride, kerb strike),
	# help the car back onto its wheels instead of letting it tip over
	if grounded_wheels > 0 and grounded_wheels < 3 and v > 4.0:
		var lean := up.dot(Vector3.UP)
		if lean > 0.0 and lean < 0.85:
			var roll_axis := up.cross(Vector3.UP)
			var roll_rate := angv.dot(fwd)
			apply_torque(roll_axis * 7.0 * inertia.z - fwd * roll_rate * 0.6 * inertia.z)
	# electronic stability control (arcade): limit yaw rate to what grip can sustain and
	# rotate the nose back towards the velocity when the body slip angle grows too large
	esc_active = false
	esc_throttle = 1.0
	if assist_esc and grounded_wheels >= 3 and v > 5.0 and forward_speed > 0.0:
		var yaw_rate := angv.dot(up)
		var r_max := 9.81 * 1.15 * grip_scale / v
		var torque_y := 0.0
		var excess_r := absf(yaw_rate) - r_max * 1.1
		if excess_r > 0.0:
			torque_y -= signf(yaw_rate) * excess_r * 9.0
		var beta := body_slip_deg
		var beta_max := 6.5
		if absf(beta) > beta_max:
			torque_y -= signf(beta) * deg_to_rad(absf(beta) - beta_max) * 14.0
		if torque_y != 0.0:
			apply_torque(up * torque_y * _yaw_inertia)
			esc_active = true
			esc_throttle = clampf(1.0 - (absf(beta) - beta_max) / 12.0, 0.35, 1.0)
	# high speed yaw stability (always on, mild) to avoid twitchiness at 250+ km/h
	if grounded_wheels >= 2 and v > 30.0 and absf(body_slip_deg) < 6.0:
		var yaw := angv.dot(up)
		apply_torque(-up * yaw * _yaw_inertia * 0.35 * smoothstep(30.0, 80.0, v))
	# flip detection
	if up.dot(Vector3.UP) < 0.25 and v < 3.0:
		upside_down_time += delta
		if upside_down_time > 2.5:
			flip_upright()
	else:
		upside_down_time = 0.0


func flip_upright() -> void:
	var xf := global_transform
	var fwd := -xf.basis.z
	fwd.y = 0.0
	if fwd.length() < 0.1:
		fwd = Vector3.FORWARD
	fwd = fwd.normalized()
	var t := Transform3D(Basis.looking_at(fwd, Vector3.UP), xf.origin + Vector3.UP * 1.5)
	reset_to(t)


func reset_to(t: Transform3D, keep_speed: float = 0.0) -> void:
	global_transform = t
	reset_physics_interpolation()
	linear_velocity = -t.basis.z * keep_speed
	angular_velocity = Vector3.ZERO
	_prev_velocity = linear_velocity
	for w in wheels:
		w.omega = keep_speed / w.radius
		w.x = definition.travel_down
		w.prev_x = w.x
	rpm = definition.idle_rpm
	reversing = false
	gear = 1
	shift_timer = 0.0
	upside_down_time = 0.0
	reset_done.emit()


func _update_wheel_visual(w: Wheel) -> void:
	if w.node == null:
		return
	var off := w.x - definition.travel_down
	var pos := w.center_rest + Vector3(0.0, off, 0.0)
	var steer_b := Basis(Vector3.UP, -w.steer)
	w.node.transform = Transform3D(steer_b * Basis(Vector3.RIGHT, -w.spin_angle) * w.base_basis, pos)
	if w.caliper != null:
		var cb := w.caliper_base
		var rel := cb.origin - w.center_rest
		w.caliper.transform = Transform3D(steer_b * cb.basis, pos + steer_b * rel)


func kinematic_visuals(speed: float, delta: float) -> void:
	## wheel spin/suspension pose while the body is moved kinematically (traffic LOD)
	for w in wheels:
		w.omega = speed / maxf(w.radius, 0.1)
		w.spin_angle = wrapf(w.spin_angle + w.omega * delta, -TAU * 50.0, TAU * 50.0)
		w.x = definition.travel_down
		w.steer = 0.0
		_update_wheel_visual(w)
	speed_kmh = speed * 3.6
	forward_speed = speed


func get_telemetry() -> Dictionary:
	var slips: Array[float] = []
	var surfaces: Array[int] = []
	for w in wheels:
		slips.append(snappedf(w.slip, 0.01))
		surfaces.append(w.surface)
	return {
		"speed_kmh": speed_kmh, "rpm": rpm, "gear": gear, "slip": slips, "surfaces": surfaces,
		"body_slip": body_slip_deg, "g": g_force, "tcs": tcs_active, "abs": abs_active, "esc": esc_active,
	}


func wheel_slip_max() -> float:
	var m := 0.0
	for w in wheels:
		if w.contact:
			m = maxf(m, w.slip)
	return m
