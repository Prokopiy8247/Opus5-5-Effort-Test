class_name CarController
extends RigidBody3D
## Project-owned raycast vehicle on a Jolt RigidBody3D.
## Suspension: one ray per wheel, spring/damper + bump stop + anti-roll bars.
## Tyres: slip-angle lateral curve + force-request longitudinal model inside a friction circle.
## Drivetrain: torque curve, gearbox (auto/manual), FWD/RWD/AWD with a limited-slip differential.
## Inputs are plain floats so the same class serves the player and AI traffic.

signal gear_changed(gear: int)
## Manual gearbox: a downshift to `requested` was refused because the engine would over-rev at this speed.
signal shift_refused(requested: int)
signal impact(strength: float, world_position: Vector3)

const RHO := 1.225
const GRAVITY := 9.81
const KMH := 3.6
## Auto gearbox: below this fraction of the redline full throttle lugs (quick kick-down); a kick-down never
## lands above KICK_MAX.
const KICK_LUG := 0.33
const KICK_MAX := 0.86
## Wetness from which paved roads use their wet presentation surface.
const WET_LOOK := 0.35
## Reverse limiter: drive fades out over the last REVERSE_FADE km/h below CarData.reverse_max_kmh.
const REVERSE_FADE := 4.0

## Callable(world_pos: Vector3) -> SurfaceData used when a wheel hits the terrain. Set by the world.
static var terrain_surface_lookup: Callable = Callable()
## 0..1 global wetness (rain). Set by the weather controller.
static var wetness: float = 0.0

class Wheel:
	var id: String
	var front: bool
	var left: bool
	var center: Vector3
	var radius: float = 0.32
	var width: float = 0.22
	var k: float = 45000.0
	var rest_len: float = 0.2
	var max_len: float = 0.2
	var mount: Vector3
	var length: float = 0.2
	var prev_length: float = 0.2
	var contact: bool = false
	var point: Vector3
	var normal: Vector3 = Vector3.UP
	var load: float = 0.0
	var static_load: float = 3000.0
	var grip_cap: float = 0.0
	var surface: SurfaceData
	## Ground collider is under a roof (tunnel road, meta covered): stays dry in rain.
	var covered: bool = false
	## Effective wetness at this wheel's contact (0 when covered).
	var wetness: float = 0.0
	var steer: float = 0.0
	var omega: float = 0.0
	var spin: float = 0.0
	var slip_long: float = 0.0
	var slip_angle: float = 0.0
	var skid: float = 0.0
	var drive_torque: float = 0.0
	var brake_force: float = 0.0
	var long_force: float = 0.0
	var lat_force: float = 0.0
	var node: Node3D
	var caliper: Node3D
	var ray: PhysicsRayQueryParameters3D

# --- inputs (written by CarInput / AI) ---
var in_throttle: float = 0.0
var in_brake: float = 0.0
var in_steer: float = 0.0
var in_handbrake: float = 0.0
var in_shift_up: bool = false
var in_shift_down: bool = false
## Gear-independent hold (menus open): no drive, service brakes on, no gear changes.
var in_hold: bool = false

# --- assists ---
var assist_tcs: bool = true
var assist_stm: bool = true
var assist_abs: bool = true
var assist_steer: bool = true
var auto_gearbox: bool = true
## AI cars skip some player-only niceties.
var is_player: bool = false

# --- state / telemetry ---
var data: CarData
var wheels: Array[Wheel] = []
var gear: int = 1
var rpm: float = 900.0
var throttle_applied: float = 0.0
var speed_ms: float = 0.0
var forward_speed: float = 0.0
var steer_angle: float = 0.0
var body_slip_deg: float = 0.0
var lateral_g: float = 0.0
var longitudinal_g: float = 0.0
var wheels_on_ground: int = 0
var air_time: float = 0.0
var damage: float = 0.0
var grip_multiplier: float = 1.0
var power_multiplier: float = 1.0
var headlights_on: bool = false
## Rewind is scrubbing the car (frozen; telemetry shows the recorded state, tyres are quiet).
var rewinding: bool = false
var engine_load: float = 0.0
var shifting: bool = false
var tcs_active: bool = false
var abs_active: bool = false
var stm_active: bool = false
var limiter_hit: bool = false

var _shift_timer: float = 0.0
## Manual shift requests not applied yet (+ up, - down): taps during a shift are queued, not lost.
var _shift_queue: int = 0
## Auto gearbox: pedal demand, the pedal smoothed over about a second so keyboard taps read as part throttle
## (held while braking).
var _shift_demand: float = 0.0
## Seconds the pedal has been floored; seconds of steady part throttle before that (analog kick-down).
var _floor_t: float = 0.0
var _part_t: float = 0.0
var _kicked: bool = false
## Auto gearbox: runs down after each shift; no part-throttle shift back the other way until it is out
## (kick-down and redline shifts excepted).
var _auto_lock: float = 0.0
var _auto_last_dir: int = 0
## Wheel speed the driven wheels free-rev toward in the air (clutch engaged, near redline), signed.
var _free_omega: float = 0.0
var _reverse_hold: float = 0.0
var _limiter_timer: float = 0.0
var _prev_velocity: Vector3 = Vector3.ZERO
var _impact_cooldown: float = 0.0
var _wheelbase: float = 2.6
var _yaw_inertia: float = 2000.0
var _front_axle_z: float = -1.3
var _rear_axle_z: float = 1.3
var _vis_spin_cap: float = 0.75


func setup(car_data: CarData, wheel_defs: Array) -> void:
	## wheel_defs: Array of Dictionary {id, center: Vector3, radius, width, node, caliper}
	data = car_data
	mass = data.mass
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = data.com
	continuous_cd = true
	can_sleep = false
	contact_monitor = true
	max_contacts_reported = 6
	linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	linear_damp = 0.0
	angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	angular_damp = 0.05
	var pm := PhysicsMaterial.new()
	pm.friction = 0.35
	pm.bounce = 0.05
	physics_material_override = pm

	wheels.clear()
	var zf := 0.0
	var zr := 0.0
	var nf := 0
	var nr := 0
	for d: Dictionary in wheel_defs:
		var w := Wheel.new()
		w.id = d["id"]
		w.front = w.id.ends_with("FL") or w.id.ends_with("FR")
		w.left = w.id.ends_with("L")
		w.center = d["center"]
		w.radius = d["radius"]
		w.width = d.get("width", 0.22)
		w.node = d.get("node")
		w.caliper = d.get("caliper")
		w.ray = PhysicsRayQueryParameters3D.new()
		w.ray.collision_mask = 1 | 16
		w.ray.exclude = [get_rid()]
		wheels.append(w)
		if w.front:
			zf += w.center.z
			nf += 1
		else:
			zr += w.center.z
			nr += 1
	_front_axle_z = zf / maxf(nf, 1)
	_rear_axle_z = zr / maxf(nr, 1)
	_wheelbase = absf(_rear_axle_z - _front_axle_z)
	_configure_suspension()
	_configure_inertia()
	rpm = data.idle_rpm


func _configure_suspension() -> void:
	# Static axle loads from the centre-of-mass position between the axles.
	var com_z := data.com.z
	var rear_share := clampf((_front_axle_z - com_z) / (_front_axle_z - _rear_axle_z), 0.2, 0.8)
	var front_share := 1.0 - rear_share
	for w in wheels:
		var share := front_share if w.front else rear_share
		w.static_load = data.mass * GRAVITY * share * 0.5
		w.k = data.spring_front if w.front else data.spring_rear
		var sag := w.static_load / w.k
		var bump := data.suspension_travel * 0.55
		var droop := data.suspension_travel * 0.45
		var c := w.center + Vector3(0.0, data.ride_height, 0.0)
		w.mount = c + Vector3.UP * bump
		w.rest_len = bump + sag
		w.max_len = bump + droop
		w.length = bump
		w.prev_length = bump
		w.surface = Surfaces.get_surface(Surfaces.DEFAULT_ID)


func _configure_inertia() -> void:
	var s := data.body_size
	var m := data.mass
	var ix := m / 12.0 * (s.y * s.y + s.z * s.z) * data.inertia_scale.x
	var iy := m / 12.0 * (s.x * s.x + s.z * s.z) * data.inertia_scale.y
	var iz := m / 12.0 * (s.x * s.x + s.y * s.y) * data.inertia_scale.z
	inertia = Vector3(ix, iy, iz)
	_yaw_inertia = iy


# ---------------------------------------------------------------- physics

func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if data == null or wheels.is_empty():
		return
	var dt := state.step
	var xf := state.transform
	var b := xf.basis
	var up := b.y
	var fwd := -b.z
	var right := b.x
	var lin := state.linear_velocity
	var ang := state.angular_velocity
	var com_world := xf.origin + state.center_of_mass
	speed_ms = lin.length()
	forward_speed = lin.dot(fwd)
	var lat_speed := lin.dot(right)
	body_slip_deg = rad_to_deg(atan2(lat_speed, absf(forward_speed))) if speed_ms > 2.0 else 0.0
	var accel := (lin - _prev_velocity) / dt
	_prev_velocity = lin
	lateral_g = lerpf(lateral_g, accel.dot(right) / GRAVITY, 0.1)
	longitudinal_g = lerpf(longitudinal_g, accel.dot(fwd) / GRAVITY, 0.1)

	_update_gear_logic(dt)
	_update_steering(dt, lat_speed)

	var space := state.get_space_state()
	# ---------------- suspension pass
	wheels_on_ground = 0
	for w in wheels:
		var start_local := w.mount + Vector3.UP * w.radius
		var start := xf * start_local
		var ray_len := w.radius * 2.0 + w.max_len
		w.ray.from = start
		w.ray.to = start - up * ray_len
		var hit := space.intersect_ray(w.ray)
		w.prev_length = w.length
		if hit.is_empty():
			w.contact = false
			w.length = w.max_len
			w.load = 0.0
			continue
		var dist: float = start.distance_to(hit["position"])
		var len := dist - w.radius * 2.0
		w.contact = true
		wheels_on_ground += 1
		w.point = hit["position"]
		w.normal = hit["normal"]
		var col: Object = hit.get("collider")
		w.covered = col != null and bool(col.get_meta(&"covered", false))
		w.wetness = 0.0 if w.covered else wetness
		w.surface = _surface_from_hit(hit, w.wetness)
		var clamped := clampf(len, 0.0, w.max_len)
		w.length = clamped
		var compression := w.rest_len - clamped
		var comp_vel := clampf((w.prev_length - clamped) / dt, -6.0, 6.0)
		var c_damp := data.damper_bump if comp_vel > 0.0 else data.damper_rebound
		var f := w.k * compression + c_damp * comp_vel
		if len < 0.0:
			# Bump stop: progressive and heavily damped.
			f += w.k * 8.0 * (-len) + c_damp * 2.0 * maxf(comp_vel, 0.0)
		if w.surface.roughness > 0.0 and speed_ms > 1.0:
			f += w.k * w.surface.roughness * sin(Time.get_ticks_msec() * 0.031 + w.center.x * 13.0 + w.center.z * 7.0) * minf(speed_ms / 15.0, 1.0)
		w.load = clampf(f, 0.0, w.static_load * 5.0)

	# ---------------- anti-roll bars
	_apply_anti_roll()

	# ---------------- tyre capacity
	for w in wheels:
		if not w.contact:
			w.grip_cap = 0.0
			continue
		var base := data.tire_grip * (data.grip_front if w.front else data.grip_rear)
		var mu := base * w.surface.grip_for(data.offroad_tires, w.wetness) * grip_multiplier
		var load_ratio := w.load / maxf(w.static_load, 1.0)
		mu *= clampf(1.0 - data.load_sensitivity * (load_ratio - 1.0), 0.75, 1.15)
		w.grip_cap = mu * w.load

	# ---------------- drivetrain + brakes
	_update_drivetrain(dt)
	_update_brakes()

	# ---------------- tyre forces + suspension forces
	var mass_share := mass * 0.25
	var roll_lift := up * data.com.y * 0.35
	var driven_grounded := false
	for w in wheels:
		driven_grounded = driven_grounded or (w.contact and _is_driven(w))
	for w in wheels:
		if not w.contact:
			# Free wheels keep their road speed. A lifted driven wheel follows the driven wheels still on the
			# ground (set below); with the whole drive in the air they free-rev with throttle (clutch engaged)
			# and are dragged down by the engine off throttle. Others coast; brakes stop them.
			if w.brake_force > 1.0:
				w.omega = move_toward(w.omega, 0.0, dt * 60.0)
			elif _is_driven(w) and driven_grounded:
				pass
			elif _is_driven(w) and _free_omega != 0.0:
				if throttle_applied > 0.05:
					var rate := 30.0 * throttle_applied if absf(w.omega) < absf(_free_omega) else 60.0
					w.omega = move_toward(w.omega, _free_omega, dt * rate)
				else:
					w.omega = lerpf(w.omega, 0.0, dt * 0.6)
			else:
				w.omega = lerpf(w.omega, 0.0, dt * 0.1)
			w.skid = 0.0
			w.slip_long = 0.0
			continue
		var n := w.normal
		var wf := fwd.rotated(up, -w.steer)
		wf = (wf - n * wf.dot(n)).normalized()
		var wr := wf.cross(n).normalized()
		var p := w.point
		var v := lin + ang.cross(p - com_world)
		var vl := v.dot(wf)
		var vs := v.dot(wr)
		var cap := maxf(w.grip_cap, 1.0)

		# Longitudinal request.
		var f_long := w.drive_torque / w.radius
		var brake := w.brake_force
		# Hill hold: at a standstill with no pedal input the car does not roll away.
		if brake <= 0.0 and in_throttle < 0.02 and in_brake < 0.02 and absf(forward_speed) < 1.2 and gear != 0:
			brake = data.brake_force * 0.25
		var locked := false
		if brake > 0.0:
			var stop_cap := mass_share * absf(vl) / dt
			if absf(vl) < 0.4:
				# Holding: static friction against creeping.
				f_long += clampf(-vl * mass_share / dt, -brake, brake)
			else:
				var b_eff := minf(brake, stop_cap)
				if assist_abs and b_eff > cap * 0.96 and not (in_handbrake > 0.1 and not w.front):
					b_eff = cap * 0.96
					abs_active = true
				f_long -= signf(vl) * b_eff
				locked = brake > cap * 1.02 and not (assist_abs and not (in_handbrake > 0.1 and not w.front))
		# Rolling resistance (+ soft surfaces).
		var rr := (data.rolling_resistance + w.surface.rolling_drag) * w.load
		f_long -= clampf(vl * 4.0, -1.0, 1.0) * rr

		var util := absf(f_long) / cap
		w.slip_long = 0.0
		if util > 1.0:
			w.slip_long = util - 1.0
			f_long = signf(f_long) * cap * data.long_slide_grip
			if brake > 0.0 and absf(vl) > 0.5 and signf(f_long) != signf(vl) and not (assist_abs and not (in_handbrake > 0.1 and not w.front)):
				locked = true
		# Friction ellipse, softened (arcade-sim): full traction use still leaves some cornering grip.
		var lu := f_long / cap
		var lat_cap := cap * sqrt(maxf(1.0 - lu * lu * 0.82, 0.0))
		if w.slip_long > 0.0:
			lat_cap *= lerpf(1.0, 0.5, clampf(w.slip_long, 0.0, 1.0))
		if locked:
			lat_cap *= 0.45
		if not w.front and in_handbrake > 0.1:
			lat_cap *= lerpf(1.0, 0.35, in_handbrake)

		# Lateral: slip-angle curve.
		var slip := atan2(vs, absf(vl) + 0.6)
		w.slip_angle = slip
		var a := absf(slip)
		var peak := deg_to_rad(data.peak_slip_deg)
		var g: float
		if a < peak:
			var x := a / peak
			g = x * (2.0 - x)
		else:
			g = lerpf(1.0, data.slide_grip * w.surface.slide_for(w.wetness), clampf((a - peak) / (peak * 2.5), 0.0, 1.0))
		var f_lat := -signf(slip) * g * lat_cap
		var lat_stop := mass_share * absf(vs) / dt * 0.9
		f_lat = clampf(f_lat, -lat_stop, lat_stop)

		w.long_force = f_long
		w.lat_force = f_lat
		# Wheel angular velocity (visual + engine rpm feedback).
		var roll_omega := vl / w.radius
		if locked:
			w.omega = 0.0
		elif w.slip_long > 0.0 and w.drive_torque != 0.0:
			w.omega = roll_omega + signf(w.drive_torque) * minf(w.slip_long, 3.0) * 18.0
		else:
			w.omega = roll_omega
		var slide_amt := clampf((a - peak) / (peak * 1.5), 0.0, 1.0) * clampf(absf(vs) / 4.0, 0.0, 1.0)
		w.skid = clampf(maxf(slide_amt, minf(w.slip_long, 1.0) * clampf((absf(vl) + 3.0) / 6.0, 0.0, 1.0) + (0.8 if locked and absf(vl) > 2.0 else 0.0)), 0.0, 1.0)

		var rel := p - xf.origin
		state.apply_force(up * w.load, rel)
		state.apply_force(wf * f_long, rel)
		state.apply_force(wr * f_lat, rel + roll_lift)

	if driven_grounded:
		var w_drive := _driven_omega()
		for w in wheels:
			if not w.contact and _is_driven(w) and w.brake_force <= 1.0:
				w.omega = w_drive

	# ---------------- aero
	var v2 := forward_speed * forward_speed
	if speed_ms > 0.5:
		state.apply_central_force(-lin.normalized() * 0.5 * RHO * data.drag_area * speed_ms * speed_ms)
	if wheels_on_ground > 0:
		var df := 0.5 * RHO * v2
		state.apply_force(-up * df * data.downforce_front, b * Vector3(0, data.com.y, _front_axle_z))
		state.apply_force(-up * df * data.downforce_rear, b * Vector3(0, data.com.y, _rear_axle_z))

	# ---------------- stability / handling helpers
	_stability(state, dt, up, fwd)

	# ---------------- air control
	if wheels_on_ground == 0:
		air_time += dt
		var axis := up.cross(Vector3.UP)
		state.apply_torque(axis * mass * 2.2 - ang * mass * 0.25)
	else:
		air_time = 0.0

	_check_impacts(state, dt)


## Paved surfaces switch to their wet presentation surface (HUD name, no smoke, lighter marks) once the road
## looks wet; grip is unaffected by the switch (it scales with the wheel's wetness on both).
func _surface_from_hit(hit: Dictionary, wet: float) -> SurfaceData:
	var col: Object = hit.get("collider")
	var s: SurfaceData = null
	if col != null and col.has_meta(&"surface"):
		s = Surfaces.get_surface(col.get_meta(&"surface"))
	elif col != null and col.has_meta(&"terrain") and terrain_surface_lookup.is_valid():
		s = terrain_surface_lookup.call(hit["position"])
	if s == null:
		s = Surfaces.get_surface(Surfaces.DEFAULT_ID)
	if s.wet_id != &"" and wet > WET_LOOK:
		return Surfaces.get_surface(s.wet_id)
	return s


func _apply_anti_roll() -> void:
	for axle: bool in [true, false]:
		var l: Wheel = null
		var r: Wheel = null
		for w in wheels:
			if w.front == axle:
				if w.left:
					l = w
				else:
					r = w
		if l == null or r == null:
			continue
		var k := data.anti_roll_front if axle else data.anti_roll_rear
		var cl := (l.rest_len - l.length) if l.contact else 0.0
		var cr := (r.rest_len - r.length) if r.contact else 0.0
		var f := (cl - cr) * k
		if l.contact:
			l.load = maxf(l.load + f, 0.0)
		if r.contact:
			r.load = maxf(r.load - f, 0.0)


func _update_steering(dt: float, lat_speed: float) -> void:
	var v := absf(forward_speed)
	var max_deg := data.max_steer_deg
	var t := clampf((v - 4.0) / 50.0, 0.0, 1.0)
	if assist_steer:
		max_deg = lerpf(data.max_steer_deg, data.high_speed_steer_deg, pow(t, 0.75))
	else:
		max_deg = lerpf(data.max_steer_deg, data.high_speed_steer_deg * 1.6, pow(t, 0.9))
	var target := in_steer * deg_to_rad(max_deg)
	if assist_steer and forward_speed > 6.0 and wheels_on_ground >= 2:
		# Counter-steer help: steer toward the direction of travel when the rear slides.
		var beta := atan2(lat_speed, absf(forward_speed))
		var help := clampf(beta * 0.75, -deg_to_rad(data.max_steer_deg), deg_to_rad(data.max_steer_deg))
		target = clampf(target + help * (1.0 - absf(in_steer) * 0.4), -deg_to_rad(data.max_steer_deg), deg_to_rad(data.max_steer_deg))
	var rate := data.steer_rate * (1.6 if absf(target) < absf(steer_angle) else 1.0)
	steer_angle = move_toward(steer_angle, target, rate * dt)
	for w in wheels:
		if w.front:
			# Mild Ackermann: the inner wheel steers a little more.
			var inner := (steer_angle > 0.0 and not w.left) or (steer_angle < 0.0 and w.left)
			w.steer = steer_angle * (1.08 if inner else 0.94)
		else:
			w.steer = 0.0


func _gear_ratio(g: int) -> float:
	if g > 0:
		return data.gear_ratios[g - 1]
	if g < 0:
		return -data.reverse_ratio
	return 0.0


func _update_gear_logic(dt: float) -> void:
	if _shift_timer > 0.0:
		_shift_timer -= dt
		shifting = _shift_timer > 0.0
	_auto_lock = maxf(_auto_lock - dt, 0.0)
	var n_gears := data.gear_ratios.size()
	# Manual requests are one-frame flags; queue them so taps during a shift still count.
	if in_shift_up:
		_shift_queue += 1
	if in_shift_down:
		_shift_queue -= 1
	in_shift_up = false
	in_shift_down = false
	if auto_gearbox or in_hold:
		_shift_queue = 0
	_shift_queue = clampi(_shift_queue, -n_gears, n_gears)
	# Shift demand is the pedal averaged over about a second (faster up than down), held while braking: a
	# keyboard driver tapping W to hold a speed reads as part throttle and short-shifts; a sustained floor or a
	# braking zone keeps the sporty shift points.
	if in_throttle > _shift_demand:
		_shift_demand += (in_throttle - _shift_demand) * (1.0 - exp(-dt / 0.6))
	elif in_brake <= 0.1:
		_shift_demand += (in_throttle - _shift_demand) * (1.0 - exp(-dt / 1.2))
	if in_throttle >= 0.9:
		_floor_t += dt
	else:
		if _floor_t > 0.0:
			_part_t = 0.0
		_floor_t = 0.0
		_kicked = false
		_part_t = _part_t + dt if in_throttle > 0.08 else 0.0
	# Reverse engagement (automatic for both gearbox modes, like most arcade racers).
	if in_hold:
		_reverse_hold = 0.0
	elif gear >= 1 and forward_speed < 0.8 and in_brake > 0.3 and in_throttle < 0.1:
		_reverse_hold += dt
		if _reverse_hold > 0.25:
			_set_gear(-1)
	elif gear == -1 and in_throttle > 0.2 and forward_speed > -1.0:
		_set_gear(1)
		_reverse_hold = 0.0
	else:
		_reverse_hold = 0.0
	if shifting:
		return
	if auto_gearbox:
		# Hold the gear in the air: the wheels say nothing about road speed until they land.
		if gear >= 1 and wheels_on_ground >= 2:
			_auto_shift()
	elif _shift_queue > 0:
		_shift_queue -= 1
		if gear < n_gears:
			_set_gear(1 if gear == -1 else gear + 1)
	elif _shift_queue < 0:
		_shift_queue += 1
		if gear > 1:
			# Over-rev protection: a downshift that would take the engine past the redline at this speed is
			# refused, and the taps queued behind it are dropped.
			if _shift_rpm(gear - 1) > data.redline_rpm:
				_shift_queue = 0
				shift_refused.emit(gear - 1)
			else:
				_set_gear(gear - 1)


## Automatic shift map: shift points from the pedal demand (short-shift when cruising, near the redline
## when pushing), decided on the rpm the driven wheels imply so engine lag after a shift cannot hunt.
## Part-throttle upshifts never land below the kick-down band, so a cruise gear can take full throttle.
## Kick-down goes straight to the gear that suits the speed (one shift, one torque cut): at once when the
## pedal is floored from a steady part throttle (analog) or the engine is lugging, and after a sustained hold
## when the revs are merely low (a keyboard tap to hold a speed never kicks down).
func _auto_shift() -> void:
	var n_gears := data.gear_ratios.size()
	var red := data.redline_rpm
	var r_now := _drive_rpm(gear)
	var up_rpm := red * lerpf(0.48, 0.965, smoothstep(0.2, 0.9, _shift_demand))
	var lug_rpm := maxf(red * KICK_LUG, data.idle_rpm * 1.4)
	if gear < n_gears:
		var driven_slip := 0.0
		for w in wheels:
			if _is_driven(w):
				driven_slip = maxf(driven_slip, w.slip_long)
		var r_up := r_now * data.gear_ratios[gear] / data.gear_ratios[gear - 1]
		# Part-throttle upshifts come at least half a second apart, and a second after a downshift.
		var settled := _auto_lock <= 0.0 or (_auto_last_dir > 0 and _auto_lock <= 0.5)
		var lugs := r_up < lug_rpm * 1.08
		# Pressing the pedal (it leads the smoothed demand) never short-shifts.
		var pressing := in_throttle > _shift_demand + 0.15
		if driven_slip < 0.6 and (r_now > red * 0.965 or (r_now > up_rpm and settled and not lugs and not pressing)):
			_auto_set(gear + 1)
			return
	if gear > 1:
		# Locked wheels (no ABS) must not walk the box down: use road speed when it says more.
		r_now = maxf(r_now, _road_rpm(gear))
		var r_down := r_now * data.gear_ratios[gear - 2] / data.gear_ratios[gear - 1]
		if _floor_t > 0.0 and not _kicked and r_down < red * KICK_MAX and r_now < red * 0.55:
			# How long the pedal must stay floored: at once from a steady part throttle or when the engine
			# bogs down, longer the closer the revs are to the power band.
			var hold := 0.12
			if _part_t < 0.4:
				if r_now < lug_rpm:
					hold = lerpf(0.12, 1.4, clampf((r_now - red * 0.25) / maxf(lug_rpm - red * 0.25, 1.0), 0.0, 1.0))
				else:
					hold = lerpf(1.4, 2.6, clampf((r_now - lug_rpm) / (red * 0.55 - lug_rpm), 0.0, 1.0))
			if _floor_t >= hold:
				_kicked = true
				_auto_set(_kick_gear(r_now))
				return
		var lugging := r_now < maxf(data.idle_rpm * 1.2, red * 0.2)
		var low := r_now < red * lerpf(0.26, 0.34, _shift_demand) and r_down < up_rpm * 0.92
		if r_down < red * KICK_MAX and (lugging or (low and (_auto_lock <= 0.0 or _auto_last_dir < 0))):
			_auto_set(gear - 1)


## Lowest gear that keeps the engine below the kick-down ceiling at the current road speed.
func _kick_gear(r_now: float) -> int:
	var g := gear
	while g > 1 and r_now * data.gear_ratios[g - 2] / data.gear_ratios[gear - 1] < data.redline_rpm * KICK_MAX:
		g -= 1
	return g


func _auto_set(g: int) -> void:
	_auto_last_dir = signi(g - gear)
	_auto_lock = 1.0
	_set_gear(g)


## Engine rpm implied by the driven wheels' speed in gear g.
func _drive_rpm(g: int) -> float:
	return absf(_driven_omega() * _gear_ratio(g) * data.final_drive) * 60.0 / TAU


## Mean speed of the driven wheels on the ground (all driven wheels when none touches).
func _driven_omega() -> float:
	var w_sum := 0.0
	var w_n := 0
	var a_sum := 0.0
	var a_n := 0
	for w in wheels:
		if _is_driven(w):
			a_sum += w.omega
			a_n += 1
			if w.contact:
				w_sum += w.omega
				w_n += 1
	return w_sum / w_n if w_n > 0 else a_sum / maxf(a_n, 1)


## Engine rpm gear g would run at once engaged: road speed, or the driven wheels when they spin faster
## (on the ground; in the air they free-rev and say nothing about the landing).
func _shift_rpm(g: int) -> float:
	var r := _road_rpm(g)
	if wheels_on_ground >= 2:
		r = maxf(r, _drive_rpm(g))
	return r


## Engine rpm in gear g if the driven wheels rolled at the car's forward speed.
func _road_rpm(g: int) -> float:
	var r_sum := 0.0
	var w_n := 0
	for w in wheels:
		if _is_driven(w):
			r_sum += w.radius
			w_n += 1
	var r := r_sum / w_n if w_n > 0 else 0.32
	return absf(forward_speed / maxf(r, 0.1) * _gear_ratio(g) * data.final_drive) * 60.0 / TAU


func _set_gear(g: int) -> void:
	if g == gear:
		return
	var old := gear
	gear = g
	if old >= 1 and g >= 1:
		_shift_timer = data.shift_time
		shifting = true
	gear_changed.emit(gear)


func _is_driven(w: Wheel) -> bool:
	match data.drivetrain:
		CarData.Drivetrain.FWD:
			return w.front
		CarData.Drivetrain.RWD:
			return not w.front
	return true


func _update_drivetrain(dt: float) -> void:
	var ratio := _gear_ratio(gear) * data.final_drive
	# Pedal mapping: in reverse the brake pedal drives backwards, faded out at the reverse speed limit.
	var pedal := in_throttle
	if gear == -1:
		pedal = in_brake * clampf((data.reverse_max_kmh + 0.5 + forward_speed * KMH) / REVERSE_FADE, 0.0, 1.0)
	if in_hold:
		pedal = 0.0
	if data.top_speed_kmh > 0.0 and speed_ms * KMH > data.top_speed_kmh * 1.01:
		pedal = 0.0
	# Engine speed from driven wheels.
	var wheel_rpm := absf(_driven_omega() * ratio) * 60.0 / TAU
	_free_omega = 0.0 if (ratio == 0.0 or shifting) else data.redline_rpm * 0.92 * TAU / 60.0 / ratio
	var target: float
	if ratio == 0.0:
		target = data.idle_rpm + pedal * (data.max_rpm - data.idle_rpm) * 0.7
	else:
		# During a shift the clutch brings the engine to the new gear's speed (gear is already set).
		target = wheel_rpm
		if absi(gear) == 1:
			# Launch: clutch slip keeps the engine in its power band.
			var launch := data.idle_rpm + pedal * (data.redline_rpm * 0.55 - data.idle_rpm)
			target = maxf(target, launch)
		elif in_handbrake > 0.1 and data.drivetrain != CarData.Drivetrain.FWD:
			# Handbrake turn: the clutch is in, the engine keeps its revs for the exit.
			target = maxf(target, data.idle_rpm + pedal * (data.redline_rpm * 0.6 - data.idle_rpm))
		target = maxf(target, data.idle_rpm)
	var resp := 14.0 if (shifting or ratio == 0.0) else 28.0
	rpm = lerpf(rpm, target, clampf(resp * dt, 0.0, 1.0))
	rpm = clampf(rpm, data.idle_rpm * 0.8, data.max_rpm * 1.02)
	# Rev limiter.
	if _limiter_timer > 0.0:
		_limiter_timer -= dt
	if rpm >= data.max_rpm:
		_limiter_timer = 0.06
	limiter_hit = _limiter_timer > 0.0
	var thr := pedal
	if limiter_hit:
		thr = 0.0
	var dmg_mult := 1.0 - clampf(damage, 0.0, 1.0) * 0.2
	var t_engine := data.torque_at(rpm) * thr * power_multiplier * dmg_mult
	var moving := clampf(absf(forward_speed) / 3.0, 0.0, 1.0)
	t_engine -= data.peak_torque * data.engine_brake * (1.0 - thr) * (rpm / data.max_rpm) * moving
	if shifting:
		t_engine = 0.0
	engine_load = clampf(thr, 0.0, 1.0)
	throttle_applied = thr
	var total := t_engine * ratio * data.drivetrain_efficiency
	# Axle split.
	var front_t := 0.0
	var rear_t := 0.0
	match data.drivetrain:
		CarData.Drivetrain.FWD:
			front_t = total
		CarData.Drivetrain.RWD:
			rear_t = total
		_:
			front_t = total * data.awd_front_split
			rear_t = total * (1.0 - data.awd_front_split)
	# Centre coupling for AWD: shift excess torque from a saturated axle to the other one.
	if data.drivetrain == CarData.Drivetrain.AWD and total > 0.0:
		var cf := _axle_capacity(true)
		var cr := _axle_capacity(false)
		if front_t > cf and cr > rear_t:
			var moved := minf(front_t - cf, cr - rear_t) * 0.8
			front_t -= moved
			rear_t += moved
		elif rear_t > cr and cf > front_t:
			var moved2 := minf(rear_t - cr, cf - front_t) * 0.8
			rear_t -= moved2
			front_t += moved2
	# Traction control: cap axle torque slightly above available traction (an axle in the air has none to
	# protect, so it is left alone: no cut and no TCS lamp mid-jump).
	tcs_active = false
	if assist_tcs and total > 0.0:
		var capf := _axle_capacity(true) * 0.985
		var capr := _axle_capacity(false) * 0.985
		if front_t > capf and _axle_grounded(true):
			front_t = capf
			tcs_active = true
		if rear_t > capr and _axle_grounded(false):
			rear_t = capr
			tcs_active = true
	_split_axle(true, front_t)
	_split_axle(false, rear_t)


func _axle_capacity(front: bool) -> float:
	var c := 0.0
	for w in wheels:
		if w.front == front:
			c += w.grip_cap * w.radius
	return c


func _axle_grounded(front: bool) -> bool:
	for w in wheels:
		if w.front == front and w.contact:
			return true
	return false


func _split_axle(front: bool, torque: float) -> void:
	var l: Wheel = null
	var r: Wheel = null
	for w in wheels:
		if w.front == front:
			if w.left:
				l = w
			else:
				r = w
	if l == null or r == null:
		return
	var half := torque * 0.5
	var cl := l.grip_cap * l.radius
	var cr := r.grip_cap * r.radius
	l.drive_torque = half
	r.drive_torque = half
	if torque == 0.0:
		return
	# Limited-slip behaviour: when the weaker wheel saturates, the stronger one only receives
	# the weak wheel's torque plus the locking fraction of the difference.
	var a := absf(half)
	if a > minf(cl, cr):
		var weak := l if cl < cr else r
		var strong := r if weak == l else l
		var cw := minf(cl, cr)
		strong.drive_torque = signf(half) * lerpf(cw, a, data.diff_lock)
		weak.drive_torque = half


func _update_brakes() -> void:
	var pedal := in_brake
	if gear == -1:
		pedal = in_throttle
		# Reverse limiter downhill: S holds the speed a little above the limit with the service brakes.
		var over := -forward_speed * KMH - data.reverse_max_kmh - 2.0
		if over > 0.0:
			pedal = maxf(pedal, in_brake * clampf(over / 6.0, 0.0, 0.6))
	if in_hold:
		pedal = maxf(pedal, 0.6)
	abs_active = false
	for w in wheels:
		var share := data.brake_bias if w.front else (1.0 - data.brake_bias)
		w.brake_force = pedal * data.brake_force * share * 0.5
		if not w.front:
			w.brake_force += in_handbrake * data.handbrake_force * 0.5


func _stability(state: PhysicsDirectBodyState3D, dt: float, up: Vector3, fwd: Vector3) -> void:
	stm_active = false
	if wheels_on_ground < 3 or speed_ms < 3.0:
		return
	var yaw_rate := state.angular_velocity.dot(up)
	var v := maxf(absf(forward_speed), 1.0)
	var expected := -v * tan(steer_angle) / maxf(_wheelbase, 1.0)
	var mu_g := data.tire_grip * GRAVITY * 1.1
	expected = clampf(expected, -mu_g / v, mu_g / v)
	var excess := yaw_rate - expected
	if assist_stm:
		# Damp only over-rotation (oversteer); leave understeer to the driver.
		if absf(yaw_rate) > absf(expected) + 0.08 and signf(yaw_rate) == signf(excess):
			var t := -excess * _yaw_inertia * 6.0
			state.apply_torque(up * clampf(t, -_yaw_inertia * 4.0, _yaw_inertia * 4.0))
			stm_active = true
	# Always-on gentle yaw damping at large body slip so slides stay catchable.
	var slip := absf(body_slip_deg)
	if slip > 12.0:
		var k := clampf((slip - 12.0) / 40.0, 0.0, 1.0) * 1.2
		state.apply_torque(-up * yaw_rate * _yaw_inertia * k)


func _check_impacts(state: PhysicsDirectBodyState3D, dt: float) -> void:
	_impact_cooldown = maxf(_impact_cooldown - dt, 0.0)
	var n := state.get_contact_count()
	if n == 0 or _impact_cooldown > 0.0:
		return
	var best := 0.0
	var pos := Vector3.ZERO
	for i in n:
		var imp: Vector3 = state.get_contact_impulse(i)
		var mag := imp.length() / mass
		if mag > best:
			best = mag
			pos = state.get_contact_collider_position(i)
	if best > 1.5:
		_impact_cooldown = 0.25
		damage = clampf(damage + best * 0.01, 0.0, 1.0)
		impact.emit(best, pos)


# ---------------------------------------------------------------- visuals

func _process(delta: float) -> void:
	if data == null:
		return
	for w in wheels:
		var d := clampf(w.omega * delta, -_vis_spin_cap, _vis_spin_cap)
		w.spin = wrapf(w.spin + d, -PI, PI)
		var center := w.mount - Vector3.UP * w.length
		if w.node != null:
			w.node.transform = Transform3D(Basis(Vector3.UP, -w.steer) * Basis(Vector3.RIGHT, -w.spin), center)
		if w.caliper != null:
			w.caliper.transform = Transform3D(Basis(Vector3.UP, -w.steer), center)


# ---------------------------------------------------------------- helpers

func get_speed_kmh() -> float:
	return speed_ms * KMH


func get_wheel(id: String) -> Wheel:
	for w in wheels:
		if w.id.ends_with(id):
			return w
	return null


func max_skid() -> float:
	var m := 0.0
	for w in wheels:
		m = maxf(m, w.skid)
	return m


func dominant_surface() -> SurfaceData:
	for w in wheels:
		if w.contact and w.surface != null:
			return w.surface
	return null


## Places the car (wheels settled) with optional velocities to resume with (rewind, rebuild at speed).
## At rest it starts in 1st at idle; when moving, the wheels roll at road speed, the gearbox resumes in
## `with_gear` (0 = a gear that suits the speed) and the engine runs at the matching rpm.
func place_at(t: Transform3D, vel := Vector3.ZERO, ang_vel := Vector3.ZERO, with_gear := 0) -> void:
	freeze = true
	global_transform = t
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	_prev_velocity = vel
	forward_speed = vel.dot(-t.basis.z)
	for w in wheels:
		w.omega = forward_speed / w.radius
		w.length = w.rest_len - w.static_load / w.k
		w.prev_length = w.length
	gear = 1
	if absf(forward_speed) > 1.0:
		gear = clampi(with_gear, -1, data.gear_ratios.size()) if with_gear != 0 else _gear_for_speed()
	_shift_timer = 0.0
	shifting = false
	_shift_queue = 0
	_reverse_hold = 0.0
	_auto_lock = 0.0
	_floor_t = 0.0
	_part_t = 0.0
	_kicked = false
	rpm = clampf(_drive_rpm(gear), data.idle_rpm, data.max_rpm)
	reset_physics_interpolation()
	freeze = false
	# Velocities only stick once the body is unfrozen.
	linear_velocity = vel
	# Telemetry (HUD speedo) is otherwise only refreshed by _integrate_forces, which does not run while frozen.
	speed_ms = vel.length()
	forward_speed = vel.dot(-t.basis.z)
	angular_velocity = ang_vel


func _gear_for_speed() -> int:
	if forward_speed < 0.0:
		return -1
	var n := data.gear_ratios.size()
	for g in range(1, n + 1):
		if _drive_rpm(g) < data.redline_rpm * 0.75:
			return g
	return n


func repair() -> void:
	damage = 0.0
