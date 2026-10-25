class_name Car
extends RigidBody3D
## Project-owned raycast vehicle: 4 spring/damper rays, combined-slip tyre model with
## per-surface grip, engine + automatic/manual gearbox, FWD/RWD/AWD, aero, anti-roll
## and assists (TCS, ABS, stability, steering assist). Used for player cars only.

signal gear_changed(gear: int)

const G := 9.81
const SURFACE_GRIP := [1.0, 0.97, 0.72, 0.68, 0.6, 0.55, 0.45] # asphalt concrete dirt gravel grass sand snow
const SURFACE_ROLL := [0.012, 0.012, 0.03, 0.035, 0.05, 0.08, 0.04]

var spec: CarSpec
var world: WorldGen
var upgrades := {"engine": 0, "tires": 0, "suspension": 0, "brakes": 0, "weight": 0, "aero": 0}
var tuning := {"final_drive": 1.0, "brake_bias": 0.62, "spring": 1.0, "arb": 1.0, "downforce": 1.0, "tire_pressure": 1.0, "toe": 0.0}
var assists := {"tcs": true, "abs": true, "stm": true, "steer": true, "auto": true}

# input (set by controller)
var in_throttle := 0.0
var in_brake := 0.0
var in_steer := 0.0
var in_handbrake := false
var lights_on := false

# runtime state
var model: Node3D
var wheels: Array[Dictionary] = []
var gear := 1          # -1 reverse, 0 neutral, 1.. forward
var rpm := 900.0
var speed := 0.0       # m/s forward
var steer_angle := 0.0
var shift_timer := 0.0
var surface := 0
var weather_grip := 1.0
var wheelbase := 2.5
var eff := {}          # effective (upgraded/tuned) parameters
var paint_mat: StandardMaterial3D
var light_f_mat: StandardMaterial3D
var light_r_mat: StandardMaterial3D
var head_lights: Array[SpotLight3D] = []
var brake_light: OmniLight3D
var steering_wheel: Node3D
var airborne_time := 0.0
var max_slip := 0.0
var drift_angle := 0.0
var tcs_active := false
var abs_active := false
var damage := 0.0
var impact_cb: Callable
var cockpit_pos := Vector3.ZERO
var hood_pos := Vector3.ZERO
var bumper_pos := Vector3.ZERO
var body_size := Vector3.ONE

func setup(s: CarSpec, w: WorldGen) -> void:
	spec = s
	world = w
	collision_layer = 4
	collision_mask = 1 | 2
	continuous_cd = true
	contact_monitor = true
	max_contacts_reported = 4
	can_sleep = false
	# replace (not combine) the project default damping: drag is modelled explicitly
	linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	linear_damp = 0.0
	angular_damp = 0.4
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	var ps := load(s.glb_path) as PackedScene
	model = ps.instantiate()
	model.name = "Model"
	add_child(model)
	_setup_parts()
	apply_tuning()
	body_entered.connect(_on_body_entered)

func _find(suffix: String) -> Node3D:
	for c in model.find_children("*", "Node3D", true, false):
		if String(c.name).ends_with(suffix): return c as Node3D
	return null

func _setup_parts() -> void:
	# strip the authored collision proxy (we build our own compound shape)
	for c in model.find_children("*", "StaticBody3D", true, false):
		c.get_parent().remove_child(c); c.queue_free()
	var body := _find("_Body") as MeshInstance3D
	var aabb := body.mesh.get_aabb()
	body_size = aabb.size
	paint_mat = StandardMaterial3D.new()
	paint_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	light_f_mat = StandardMaterial3D.new()
	light_r_mat = StandardMaterial3D.new()
	for mi: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		for si in mi.mesh.get_surface_count():
			var m := mi.mesh.surface_get_material(si)
			if m == null: continue
			match m.resource_name:
				"Paint": mi.set_surface_override_material(si, paint_mat)
				"LightF": mi.set_surface_override_material(si, light_f_mat)
				"LightR": mi.set_surface_override_material(si, light_r_mat)
				"Glass":
					var g := (m as BaseMaterial3D).duplicate() as BaseMaterial3D
					g.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
					g.albedo_color = Color(0.04, 0.06, 0.08, 0.5)
					g.cull_mode = BaseMaterial3D.CULL_DISABLED
					g.metallic_specular = 1.0; g.roughness = 0.05
					mi.set_surface_override_material(si, g)
	light_f_mat.albedo_color = Color(1, 1, 0.92); light_f_mat.emission_enabled = true; light_f_mat.emission = Color(1, 0.97, 0.85)
	light_r_mat.albedo_color = Color(0.6, 0.02, 0.02); light_r_mat.emission_enabled = true; light_r_mat.emission = Color(1, 0.05, 0.03)
	set_paint(spec.base_color, spec.finish)
	# collision: lower body box + cabin box
	var cs := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	var low_h := aabb.size.y * 0.55
	bx.size = Vector3(aabb.size.x * 0.92, low_h, aabb.size.z * 0.96)
	cs.shape = bx
	cs.position = aabb.position + Vector3(aabb.size.x * 0.5, low_h * 0.5 + 0.08, aabb.size.z * 0.5)
	add_child(cs)
	var cs2 := CollisionShape3D.new()
	var bx2 := BoxShape3D.new()
	bx2.size = Vector3(aabb.size.x * 0.75, aabb.size.y * 0.4, aabb.size.z * 0.5)
	cs2.shape = bx2
	cs2.position = aabb.position + Vector3(aabb.size.x * 0.5, aabb.size.y * 0.78, aabb.size.z * 0.5)
	add_child(cs2)
	var pm := PhysicsMaterial.new(); pm.friction = 0.35; pm.bounce = 0.05
	physics_material_override = pm
	# wheels
	wheels.clear()
	for nm in ["FL", "FR", "RL", "RR"]:
		var wn := _find("_Wheel_" + nm) as MeshInstance3D
		var br := _find("_Brake_" + nm)
		var r := wn.mesh.get_aabb().size.y * 0.5
		var pivot := Node3D.new(); pivot.name = "Hub_" + nm
		model.add_child(pivot)
		pivot.position = wn.position
		wn.get_parent().remove_child(wn); pivot.add_child(wn); wn.position = Vector3.ZERO
		if br:
			br.get_parent().remove_child(br); pivot.add_child(br); br.position = Vector3(signf(pivot.position.x) * -0.1, 0, 0)
		wheels.append({"name": nm, "front": nm[0] == "F", "left": nm[1] == "L", "pivot": pivot, "mesh": wn, "radius": r,
			"rest_pos": pivot.position, "mount": Vector3.ZERO, "comp": 0.0, "prev_comp": 0.0, "contact": false,
			"normal": Vector3.UP, "point": Vector3.ZERO, "load": 0.0, "spin": 0.0, "omega": 0.0, "slip_lat": 0.0, "slip_long": 0.0,
			"surface": 0, "collider": null})
	wheelbase = absf(wheels[0].rest_pos.z - wheels[2].rest_pos.z)
	steering_wheel = _find("_SteeringWheel")
	var seat_x: float = steering_wheel.position.x if steering_wheel else -0.35
	var seat_z: float = steering_wheel.position.z + 0.55 if steering_wheel else 0.0
	cockpit_pos = Vector3(seat_x, (steering_wheel.position.y + 0.32) if steering_wheel else 1.1, seat_z)
	hood_pos = Vector3(0, aabb.position.y + aabb.size.y * 0.75, aabb.position.z + aabb.size.z * 0.35)
	bumper_pos = Vector3(0, aabb.position.y + 0.45, aabb.position.z - 0.1)
	# lights
	for side in [-1.0, 1.0]:
		var sl := SpotLight3D.new()
		sl.position = Vector3(side * aabb.size.x * 0.3, aabb.position.y + 0.5, aabb.position.z + 0.1)
		sl.rotation_degrees = Vector3(-4, 0, 0)
		sl.spot_range = 60.0; sl.spot_angle = 32.0; sl.light_energy = 6.0
		sl.light_color = Color(1, 0.95, 0.85); sl.shadow_enabled = false
		sl.visible = false
		add_child(sl); head_lights.append(sl)
	brake_light = OmniLight3D.new()
	brake_light.position = Vector3(0, aabb.position.y + 0.6, aabb.end.z + 0.3)
	brake_light.light_color = Color(1, 0.1, 0.05); brake_light.omni_range = 4.0; brake_light.light_energy = 0.0
	add_child(brake_light)

func set_paint(c: Color, finish: int) -> void:
	paint_mat.albedo_color = c
	match finish:
		0: paint_mat.metallic = 0.15; paint_mat.roughness = 0.18; paint_mat.clearcoat_enabled = true; paint_mat.clearcoat = 1.0
		1: paint_mat.metallic = 0.0; paint_mat.roughness = 0.75; paint_mat.clearcoat_enabled = false
		2: paint_mat.metallic = 0.8; paint_mat.roughness = 0.3; paint_mat.clearcoat_enabled = true; paint_mat.clearcoat = 0.7
	paint_mat.set_meta("finish", finish)

func apply_tuning() -> void:
	var u := upgrades
	var m: float = spec.mass * (1.0 - 0.05 * u.weight)
	mass = m
	center_of_mass = spec.com_offset + Vector3(0, 0.3, 0)
	eff.power = spec.power_kw * 1000.0 * (1.0 + 0.12 * u.engine)
	eff.top = spec.top_speed_kmh / 3.6 * (1.0 + 0.03 * u.engine)
	eff.grip = spec.grip * (1.0 + 0.06 * u.tires) * (1.0 + 0.08 * (1.0 - absf(tuning.tire_pressure - 1.0) * 4.0) - 0.08)
	eff.brake = spec.brake_force * (1.0 + 0.15 * u.brakes)
	eff.downforce = spec.downforce * (1.0 + 0.35 * u.aero) * tuning.downforce
	eff.final = spec.final_drive * tuning.final_drive
	eff.bias = tuning.brake_bias
	eff.arb = spec.anti_roll * (1.0 + 0.2 * u.suspension) * tuning.arb
	var freq: float = spec.susp_freq * (1.0 + 0.08 * u.suspension) * sqrt(tuning.spring)
	var corner := m / 4.0
	eff.k = corner * pow(TAU * freq, 2.0)
	eff.c = 2.0 * spec.susp_damping * sqrt(eff.k * corner) * (1.0 + 0.1 * u.suspension)
	# drag coefficient chosen so that power balances drag at the rated top speed
	var v: float = eff.top
	eff.cda = maxf((eff.power * 0.92 - SURFACE_ROLL[0] * m * G * v) / (0.5 * 1.225 * pow(v, 3.0)), 0.15)
	eff.torque_peak = eff.power / (spec.peak_rpm * TAU / 60.0) * 1.15
	var x0: float = corner * G / eff.k
	var travel: float = spec.susp_travel
	for w in wheels:
		w.rest_len = travel * 1.6
		w.mount = (w.rest_pos as Vector3) + Vector3.UP * (w.rest_len - x0)

func set_lights(on: bool) -> void:
	lights_on = on
	for l in head_lights: l.visible = on

# ------------------------------------------------------------------ physics
func _physics_process(dt: float) -> void:
	if spec == null: return
	var xf := global_transform
	var basis := xf.basis
	var fwd := -basis.z
	var up := basis.y
	var vel := linear_velocity
	speed = vel.dot(fwd)
	var kmh := absf(speed) * 3.6
	# steering: speed-sensitive lock, smoothed
	var lock := deg_to_rad(spec.steer_lock_deg) / (1.0 + absf(speed) / 22.0)
	var target := in_steer * lock
	if assists.steer and absf(speed) > 8.0:
		# counter-steer help: bias towards the direction of travel when sliding
		var lv := basis.inverse() * vel
		var slip := atan2(lv.x, -lv.z)
		target += clampf(slip * 0.6, -0.25, 0.25) * (1.0 - absf(in_steer) * 0.5)
	steer_angle = move_toward(steer_angle, target, dt * (3.5 + 1.5 / (1.0 + absf(speed) * 0.05)))
	_gearbox(dt)
	var space := get_world_3d().direct_space_state
	var any_contact := false
	var drive_wheels: Array = []
	var total_load := 0.0
	# suspension pass
	for w in wheels:
		var mount_w := xf * (w.mount as Vector3)
		var ray_len: float = w.rest_len + w.radius
		var q := PhysicsRayQueryParameters3D.create(mount_w, mount_w - up * ray_len, 1)
		q.exclude = [get_rid()]
		var hit := space.intersect_ray(q)
		w.prev_comp = w.comp
		if hit.is_empty():
			w.contact = false; w.comp = 0.0; w.load = 0.0
		else:
			any_contact = true
			var dist := mount_w.distance_to(hit.position)
			w.contact = true
			w.comp = clampf(w.rest_len + w.radius - dist, 0.0, w.rest_len)
			w.point = hit.position; w.normal = hit.normal
			w.collider = hit.collider
			w.surface = _surface_from(hit)
	# anti-roll
	for pair in [[0, 1], [2, 3]]:
		var a: Dictionary = wheels[pair[0]]; var b: Dictionary = wheels[pair[1]]
		var diff: float = (a.comp - b.comp) * eff.arb
		a.arb = diff; b.arb = -diff
	var drive_force_total := _engine_force()
	var dn_split := [0.0, 0.0, 0.0, 0.0]
	match spec.drivetrain:
		0: dn_split = [0.5, 0.5, 0.0, 0.0]
		1: dn_split = [0.0, 0.0, 0.5, 0.5]
		2: dn_split = [spec.awd_front_split * 0.5, spec.awd_front_split * 0.5, (1.0 - spec.awd_front_split) * 0.5, (1.0 - spec.awd_front_split) * 0.5]
	var brake_total: float = in_brake * eff.brake if gear >= 0 or speed < -0.5 else 0.0
	if gear == -1 and in_brake > 0.0: brake_total = 0.0
	max_slip = 0.0
	tcs_active = false; abs_active = false
	var surf_counts := {}
	for i in 4:
		var w: Dictionary = wheels[i]
		var piv: Node3D = w.pivot
		if not w.contact:
			w.omega = lerpf(w.omega, w.omega * 0.98, dt)
			piv.position = (w.mount as Vector3) - Vector3.UP * w.rest_len
			continue
		var comp_v: float = (w.comp - w.prev_comp) / dt
		var fs: float = eff.k * w.comp + eff.c * comp_v + w.get("arb", 0.0)
		fs = maxf(fs, 0.0)
		w.load = fs
		total_load += fs
		var n: Vector3 = w.normal
		apply_force(n * fs, (w.point as Vector3) - global_position)
		# tyre frame
		var wf := fwd
		if w.front: wf = fwd.rotated(up, -steer_angle)
		var wr := wf.cross(n).normalized()
		wf = n.cross(wr).normalized()
		var pv := vel + angular_velocity.cross((w.point as Vector3) - global_position)
		var v_long := pv.dot(wf)
		var v_lat := pv.dot(wr)
		var mu: float = eff.grip * SURFACE_GRIP[w.surface] * weather_grip
		if w.surface >= 2: mu *= spec.offroad_grip
		var fmax := mu * fs
		# longitudinal
		var f_drive: float = drive_force_total * dn_split[i]
		var f_brake := 0.0
		var bias: float = eff.bias if w.front else 1.0 - eff.bias
		f_brake = brake_total * bias * 0.5 * 2.0
		if in_handbrake and not w.front: f_brake += eff.brake * 0.6
		if assists.abs and f_brake > fmax * 0.92 and absf(v_long) > 2.0:
			f_brake = fmax * 0.92; abs_active = true
		var f_long := f_drive - signf(v_long) * minf(f_brake, absf(v_long) * mass * 0.25 / dt)
		if absf(v_long) < 0.5 and f_brake > 0.0: f_long = f_drive - v_long * mass * 0.25
		if assists.tcs and absf(f_drive) > fmax * 0.95:
			f_long = signf(f_drive) * fmax * 0.95; tcs_active = true
		f_long -= v_long * SURFACE_ROLL[w.surface] * fs * 0.1
		# lateral (saturating)
		var slip_angle := atan2(v_lat, maxf(absf(v_long), 1.5))
		var lat_mu := mu
		if in_handbrake and not w.front: lat_mu *= 0.42
		var f_lat := -lat_mu * fs * tanh(slip_angle / spec.lat_stiffness)
		if absf(v_long) < 1.5 and absf(v_lat) < 1.5:
			f_lat = -v_lat * mass * 0.25 / dt * 0.25
		# combined slip: friction ellipse
		var lim := lat_mu * fs
		var lsum := sqrt(f_long * f_long / maxf(fmax * fmax, 1.0) + f_lat * f_lat / maxf(lim * lim, 1.0))
		var spin_excess := 0.0
		if lsum > 1.0:
			if absf(f_drive) > fmax: spin_excess = (absf(f_drive) - fmax) / maxf(fmax, 1.0)
			f_long /= lsum; f_lat /= lsum
		var force := wf * f_long + wr * f_lat
		apply_force(force, (w.point as Vector3) - global_position + up * 0.12)
		w.slip_lat = slip_angle
		w.slip_long = spin_excess
		max_slip = maxf(max_slip, maxf(absf(slip_angle) * (1.0 if absf(v_long) > 3.0 else 0.0), spin_excess * 0.6))
		if in_handbrake and not w.front and absf(v_long) > 3.0: max_slip = maxf(max_slip, 0.3)
		surf_counts[w.surface] = surf_counts.get(w.surface, 0) + 1
		# visuals
		w.omega = v_long / w.radius * (1.0 + spin_excess * 2.0)
		if in_handbrake and not w.front: w.omega = 0.0
		piv.position = (w.mount as Vector3) - Vector3.UP * (w.rest_len - w.comp)
	# dominant surface
	var best := -1
	for k in surf_counts.keys():
		if best == -1 or surf_counts[k] > surf_counts[best]: best = k
	if best >= 0: surface = best
	# aero
	var v2 := vel.length_squared()
	apply_central_force(-vel.normalized() * 0.5 * 1.225 * eff.cda * v2 if v2 > 0.01 else Vector3.ZERO)
	if any_contact:
		apply_central_force(-up * eff.downforce * v2)
		airborne_time = 0.0
	else:
		airborne_time += dt
		# gentle air control keeps landings on all fours
		var tq := up.cross(Vector3.UP) * mass * 6.0
		apply_torque(tq - angular_velocity * mass * 0.6)
	# stability control: damp yaw rate beyond the steering request
	if assists.stm and any_contact and absf(speed) > 10.0:
		var yaw := angular_velocity.dot(up)
		var desired := speed * tan(steer_angle) / wheelbase
		var err := yaw - desired
		if absf(err) > 0.25: apply_torque(-up * err * mass * 1.6)
	var lvv := basis.inverse() * vel
	drift_angle = rad_to_deg(atan2(lvv.x, -lvv.z)) if vel.length() > 5.0 else 0.0
	# brake lights
	brake_light.light_energy = 2.0 if in_brake > 0.1 else (0.4 if lights_on else 0.0)
	light_r_mat.emission_energy_multiplier = 4.0 if in_brake > 0.1 else (1.2 if lights_on else 0.3)
	light_f_mat.emission_energy_multiplier = 3.0 if lights_on else 0.4

func _surface_from(hit: Dictionary) -> int:
	var c: Object = hit.collider
	if c and c.has_meta("surface"): return c.get_meta("surface")
	var p: Vector3 = hit.position
	return world.surface_at(p.x, p.z) if world else 0

func _engine_force() -> float:
	if gear == 0 or shift_timer > 0.0: return 0.0
	var ratio := _ratio()
	var r: float = wheels[2].radius
	var tf := _torque_factor(rpm)
	var torque: float = eff.torque_peak * tf * in_throttle
	if gear == -1: torque = eff.torque_peak * 0.6 * in_brake
	if rpm >= spec.redline * 0.995 and gear > 0: torque *= 0.1
	var f := torque * ratio / r * 0.9
	# soft governor near rated top speed
	if gear > 0 and absf(speed) > eff.top * 1.02: f = 0.0
	return f if gear > 0 else -absf(f)

func _torque_factor(r: float) -> float:
	var x := r / spec.peak_rpm
	return clampf(0.62 + 0.55 * x - 0.3 * x * x * x, 0.35, 1.0)

func _ratio() -> float:
	if gear == -1: return 3.4 * eff.final
	if gear <= 0: return 0.0
	return spec.gear_ratios[gear - 1] * eff.final

func _gearbox(dt: float) -> void:
	shift_timer = maxf(shift_timer - dt, 0.0)
	var r: float = wheels[2].radius if not wheels.is_empty() else 0.33
	var wheel_rpm := absf(speed) / r * 60.0 / TAU
	var ratio := _ratio()
	var target_rpm: float = maxf(spec.idle_rpm, wheel_rpm * ratio) if gear != 0 else spec.idle_rpm + in_throttle * (spec.redline - spec.idle_rpm)
	# clutch slip at launch
	if gear != 0 and wheel_rpm * ratio < spec.idle_rpm * 2.0:
		target_rpm = maxf(target_rpm, spec.idle_rpm + in_throttle * spec.peak_rpm * 0.5)
	var spinning := 0.0
	for w in wheels: spinning = maxf(spinning, w.slip_long)
	target_rpm += spinning * 1500.0
	rpm = lerpf(rpm, clampf(target_rpm, spec.idle_rpm, spec.redline), clampf(dt * 12.0, 0.0, 1.0))
	# direction changes
	if speed < 1.0 and in_brake > 0.3 and in_throttle < 0.1 and gear >= 1 and speed < 0.5:
		gear = -1; gear_changed.emit(gear)
	elif gear == -1 and in_throttle > 0.1 and speed > -1.0:
		gear = 1; gear_changed.emit(gear)
	if not assists.auto or gear <= 0 or shift_timer > 0.0: return
	var up_rpm: float = lerpf(spec.peak_rpm * 0.75, spec.redline * 0.94, clampf(in_throttle * 1.2, 0.0, 1.0))
	if rpm > up_rpm and gear < spec.gear_ratios.size() and in_brake < 0.1:
		shift(1)
	elif gear > 1 and rpm < spec.peak_rpm * (0.42 + 0.25 * maxf(in_throttle, in_brake)):
		var lower_rpm: float = wheel_rpm * spec.gear_ratios[gear - 2] * eff.final
		if lower_rpm < spec.redline * 0.85: shift(-1)

func shift(d: int) -> void:
	var ng := clampi(gear + d, -1, spec.gear_ratios.size())
	if ng == gear: return
	gear = ng
	shift_timer = 0.12
	gear_changed.emit(gear)

func _process(_dt: float) -> void:
	if spec == null: return
	for w in wheels:
		var piv: Node3D = w.pivot
		w.spin = fmod(w.spin + w.omega * _dt, TAU)
		var steer := steer_angle if w.front else 0.0
		piv.basis = Basis(Vector3.UP, steer)
		(w.mesh as Node3D).basis = Basis(Vector3.RIGHT, -w.spin)
	if steering_wheel:
		steering_wheel.rotation.z = -steer_angle * 8.0

func reset_to(xf: Transform3D) -> void:
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	global_transform = xf
	PhysicsServer3D.body_set_state(get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM, xf)
	gear = 1; rpm = spec.idle_rpm; steer_angle = 0.0
	for w in wheels: w.comp = 0.0; w.prev_comp = 0.0

func _on_body_entered(b: Node) -> void:
	var imp := linear_velocity.length()
	damage = minf(damage + imp * 0.002, 1.0)
	if impact_cb.is_valid(): impact_cb.call(imp, b)

func telemetry() -> Dictionary:
	return {"rpm": rpm, "gear": gear, "kmh": absf(speed) * 3.6, "slip": max_slip, "surface": surface, "drift": drift_angle,
		"tcs": tcs_active, "abs": abs_active, "air": airborne_time}
