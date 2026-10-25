class_name Car
extends RigidBody3D
## Project-owned raycast vehicle: spring/damper suspension with anti-roll bars, Pacejka-style lateral grip,
## friction circle, engine torque curve + automatic/manual gearbox, FWD/RWD/AWD split, aero drag and
## downforce, TCS / ESC / ABS / steering assist, handbrake, surface + weather grip.

signal impact(strength: float)
signal landed(air_time: float, distance: float)

const RHO: float = 1.225
const LAT_BOOST: float = 1.15
const SURF_GRIP: PackedFloat32Array = [1.0, 0.97, 0.74, 0.7, 0.62, 0.55, 0.42, 0.78]
const SURF_DRAG: PackedFloat32Array = [0.0, 0.0, 25.0, 30.0, 55.0, 110.0, 60.0, 20.0]
const SURF_BUMP: PackedFloat32Array = [0.0, 0.002, 0.012, 0.016, 0.02, 0.01, 0.006, 0.02]
const LOOSE: PackedByteArray = [0, 0, 1, 1, 1, 1, 1, 0]

var def: CarDef
var model: Node3D
var wheels: Array[Dictionary] = []
var wheelbase: float = 2.6
var paint_mat: ShaderMaterial
var head_mat: StandardMaterial3D
var tail_mat: StandardMaterial3D
var rev_mat: StandardMaterial3D
var head_lights: Array[SpotLight3D] = []
var tail_light: OmniLight3D
var steering_wheel: Node3D
var body_aabb: AABB
var audio: Node = null
var fx: Node = null

# inputs (0..1, steer -1..1)
var in_throttle: float = 0.0
var in_brake: float = 0.0
var in_steer: float = 0.0
var in_handbrake: bool = false
var ai_controlled: bool = false

# drivetrain state
var rpm: float = 900.0
var gear: int = 1
var shift_timer: float = 0.0
var steer_angle: float = 0.0
var speed: float = 0.0  # m/s forward
var tcs_active: bool = false
var abs_active: bool = false
var esc_active: bool = false
var lights_on: bool = false
var max_slip: float = 0.0
var drift_angle: float = 0.0
var surface_now: int = 0
var damage: float = 0.0
var grounded_wheels: int = 0
var air_time: float = 0.0
var _air_start: Vector3
var _prev_vel: Vector3 = Vector3.ZERO
var _pending_tp: Variant = null
var _cda: float = 0.4
var _cla: float = 0.5
var mods: Dictionary = {"power": 1.0, "grip": 1.0, "brake": 1.0, "mass": 1.0, "aero": 1.0, "spring": 1.0, "damper": 1.0, "arb": 1.0, "final": 1.0, "bias": 0.0}
var weather_grip: float = 1.0
var weather_wet: float = 0.0


func setup(d: CarDef) -> void:
	def = d
	name = "Car_" + d.id
	collision_layer = 4
	collision_mask = 1 | 4 | 8
	continuous_cd = true
	can_sleep = false
	contact_monitor = true
	max_contacts_reported = 4
	var pm := PhysicsMaterial.new()
	pm.friction = 0.25
	pm.bounce = 0.05
	physics_material_override = pm
	linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	linear_damp = 0.0
	angular_damp = 0.4
	_build_model()
	apply_mods()


func apply_mods() -> void:
	var up: Dictionary = Game.get_upgrades(def.id)
	var tu: Dictionary = Game.get_tuning(def.id)
	mods.power = 1.0 + 0.08 * up.engine
	mods.grip = 1.0 + 0.04 * up.tires + tu.tire_pressure * -0.03 + absf(tu.camber) * 0.01
	mods.brake = 1.0 + 0.12 * up.brakes
	mods.mass = 1.0 - 0.04 * up.weight
	mods.aero = (1.0 + 0.35 * up.aero) * tu.aero
	mods.spring = (1.0 + 0.1 * up.suspension) * tu.spring
	mods.damper = (1.0 + 0.1 * up.suspension) * tu.damper
	mods.arb = (1.0 + 0.12 * up.suspension) * tu.arb
	mods.final = tu.final_drive
	mods.bias = tu.brake_bias
	mass = def.mass * mods.mass
	var p_w: float = def.peak_power_kw() * 1000.0 * 0.86
	var v_top: float = def.top_speed_kmh / 3.6
	# drag area chosen so that power balances drag + rolling losses at the design top speed
	_cda = maxf(0.2, (p_w - 0.015 * mass * 9.81 * v_top) / (0.5 * RHO * v_top * v_top * v_top))
	_cla = def.downforce * mods.aero


func _build_model() -> void:
	var scene: PackedScene = load(def.model_path)
	model = scene.instantiate()
	model.name = "Model"
	add_child(model)
	var meshes: Array[MeshInstance3D] = []
	_collect_meshes(model, meshes)
	var wheel_nodes: Dictionary = {}
	var brake_nodes: Dictionary = {}
	body_aabb = AABB()
	var first: bool = true
	paint_mat = ShaderMaterial.new()
	paint_mat.shader = load("res://shaders/car_paint.gdshader")
	head_mat = StandardMaterial3D.new()
	head_mat.albedo_color = Color(0.95, 0.95, 0.9)
	head_mat.emission_enabled = true
	head_mat.emission = Color(1.0, 0.96, 0.85)
	head_mat.emission_energy_multiplier = 0.3
	tail_mat = StandardMaterial3D.new()
	tail_mat.albedo_color = Color(0.5, 0.02, 0.02)
	tail_mat.emission_enabled = true
	tail_mat.emission = Color(1.0, 0.05, 0.02)
	tail_mat.emission_energy_multiplier = 0.4
	rev_mat = StandardMaterial3D.new()
	rev_mat.albedo_color = Color(0.8, 0.8, 0.8)
	rev_mat.emission_enabled = true
	rev_mat.emission = Color(1, 1, 1)
	rev_mat.emission_energy_multiplier = 0.0
	var glass := ShaderMaterial.new()
	glass.shader = load("res://shaders/car_glass.gdshader")
	var rim := StandardMaterial3D.new()
	rim.albedo_color = def.rim_color
	rim.metallic = 0.9
	rim.roughness = 0.25
	set_meta("rim_mat", rim)
	for mi in meshes:
		var nm: String = mi.name
		for key in ["Wheel_FL", "Wheel_FR", "Wheel_RL", "Wheel_RR"]:
			if nm.begins_with(key):
				wheel_nodes[key.substr(6)] = mi
		for key in ["Brake_FL", "Brake_FR", "Brake_RL", "Brake_RR"]:
			if nm.begins_with(key):
				brake_nodes[key.substr(6)] = mi
		if nm.begins_with("SteeringWheel"):
			steering_wheel = mi
		if nm.begins_with("Body"):
			var bb: AABB = mi.transform * mi.mesh.get_aabb()
			body_aabb = bb if first else body_aabb.merge(bb)
			first = false
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		for s in mi.mesh.get_surface_count():
			var m: Material = mi.mesh.surface_get_material(s)
			if m == null:
				continue
			var mn: String = m.resource_name
			if mn.begins_with("Paint"):
				mi.set_surface_override_material(s, paint_mat)
			elif mn.begins_with("Glass"):
				mi.set_surface_override_material(s, glass)
			elif mn.begins_with("HeadLight"):
				mi.set_surface_override_material(s, head_mat)
			elif mn.begins_with("TailLight"):
				mi.set_surface_override_material(s, tail_mat)
			elif mn.begins_with("ReverseLight"):
				mi.set_surface_override_material(s, rev_mat)
			elif mn.begins_with("Rim"):
				mi.set_surface_override_material(s, rim)
	set_paint(def.paint_color, def.paint_finish, 0, Color.WHITE)
	# collision: lower body box + cabin box from the body bounds
	var size: Vector3 = body_aabb.size
	var c: Vector3 = body_aabb.get_center()
	var low_h: float = size.y * 0.55
	var box1 := BoxShape3D.new()
	box1.size = Vector3(size.x * 0.94, low_h, size.z * 0.97)
	var cs1 := CollisionShape3D.new()
	cs1.shape = box1
	cs1.position = Vector3(c.x, body_aabb.position.y + low_h * 0.5 + 0.06, c.z)
	add_child(cs1)
	var box2 := BoxShape3D.new()
	box2.size = Vector3(size.x * 0.8, size.y * 0.42, size.z * 0.5)
	var cs2 := CollisionShape3D.new()
	cs2.shape = box2
	cs2.position = Vector3(c.x, body_aabb.position.y + low_h + size.y * 0.21, c.z)
	add_child(cs2)
	# wheels
	var sag: float = def.mass * 0.25 * 9.81 / def.spring
	var zs: Array = []
	for key in ["FL", "FR", "RL", "RR"]:
		var mi: MeshInstance3D = wheel_nodes.get(key)
		if mi == null:
			push_error("wheel missing " + key)
			continue
		var aabb: AABB = mi.mesh.get_aabb()
		var radius: float = maxf(aabb.size.y, aabb.size.z) * 0.5
		var center: Vector3 = mi.position
		var pivot := Node3D.new()
		pivot.name = "Pivot_" + key
		model.add_child(pivot)
		pivot.position = center
		mi.owner = null
		mi.reparent(pivot, false)
		mi.position = Vector3.ZERO
		var br: MeshInstance3D = brake_nodes.get(key)
		if br:
			var off: Vector3 = br.position - center
			br.owner = null
			br.reparent(pivot, false)
			br.position = off
		var front: bool = key[0] == "F"
		var drive_share: float = 0.0
		match def.drive:
			CarDef.Drive.FWD: drive_share = 0.5 if front else 0.0
			CarDef.Drive.RWD: drive_share = 0.0 if front else 0.5
			CarDef.Drive.AWD: drive_share = def.awd_front * 0.5 if front else (1.0 - def.awd_front) * 0.5
		wheels.append({
			"key": key, "front": front, "left": key[1] == "L", "center": center, "radius": radius,
			"anchor": center + Vector3(0, def.rest_length - sag, 0), "pivot": pivot, "mesh": mi,
			"drive": drive_share, "x": 0.0, "px": 0.0, "contact": false, "spin": 0.0, "spin_v": 0.0,
			"surface": 0, "load": 0.0, "slip": 0.0, "slip_lat": 0.0, "point": Vector3.ZERO, "normal": Vector3.UP,
			"spring_len": def.rest_length - sag, "locked": false, "spinning": false,
		})
		zs.append(center.z)
	if zs.size() == 4:
		wheelbase = absf(zs[0] - zs[2])
	var cg_y: float = clampf(body_aabb.position.y + size.y * 0.33 + def.com_offset.y, 0.3, 0.85)
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3(0, cg_y, def.com_offset.z)
	# lights
	for sx in [-1.0, 1.0]:
		var sl := SpotLight3D.new()
		sl.position = Vector3(sx * size.x * 0.33, body_aabb.position.y + size.y * 0.45, body_aabb.position.z + 0.1)
		sl.rotation_degrees = Vector3(-4, 0, 0)
		sl.spot_range = 70.0
		sl.spot_angle = 28.0
		sl.light_energy = 6.0
		sl.light_color = Color(1.0, 0.95, 0.85)
		sl.shadow_enabled = sx > 0.0
		sl.visible = false
		add_child(sl)
		head_lights.append(sl)
	tail_light = OmniLight3D.new()
	tail_light.position = Vector3(0, body_aabb.position.y + size.y * 0.5, body_aabb.end.z + 0.3)
	tail_light.light_color = Color(1, 0.05, 0.02)
	tail_light.omni_range = 4.0
	tail_light.light_energy = 0.0
	add_child(tail_light)


func _collect_meshes(n: Node, out: Array[MeshInstance3D]) -> void:
	if n is MeshInstance3D:
		out.append(n)
	for ch in n.get_children():
		_collect_meshes(ch, out)


func set_paint(color: Color, finish: int, stripe: int, stripe_color: Color) -> void:
	paint_mat.set_shader_parameter("base_color", color)
	paint_mat.set_shader_parameter("finish", finish)
	paint_mat.set_shader_parameter("stripe_mode", stripe)
	paint_mat.set_shader_parameter("stripe_color", stripe_color)
	paint_mat.set_shader_parameter("body_width", body_aabb.size.x)


func set_rim_color(c: Color) -> void:
	(get_meta("rim_mat") as StandardMaterial3D).albedo_color = c


func set_lights(on: bool) -> void:
	lights_on = on
	for l in head_lights:
		l.visible = on
	head_mat.emission_energy_multiplier = 6.0 if on else 0.3


func kmh() -> float:
	return linear_velocity.length() * 3.6


func gear_ratio() -> float:
	if gear < 0:
		return -def.reverse_ratio
	return def.gears[clampi(gear - 1, 0, def.gears.size() - 1)]


func _physics_process(delta: float) -> void:
	var _pf: int = Time.get_ticks_usec()
	_inner_car(delta)
	Game.prof_add("car", _pf)


func _inner_car(delta: float) -> void:
	if def == null or freeze or delta <= 0.00001:
		return
	var xf: Transform3D = global_transform
	var bas: Basis = xf.basis
	var up: Vector3 = bas.y
	var fwd: Vector3 = -bas.z
	var right: Vector3 = bas.x
	var vel: Vector3 = linear_velocity
	speed = vel.dot(fwd)
	var spd: float = vel.length()
	var space := get_world_3d().direct_space_state
	var com_g: Vector3 = xf * center_of_mass

	# ---- impacts (velocity change not explained by our own forces)
	var dv: float = (vel - _prev_vel).length()
	if dv > 5.0 and _prev_vel.length() > 4.0:
		var strength: float = clampf((dv - 5.0) / 15.0, 0.0, 1.0)
		damage = minf(100.0, damage + strength * 12.0)
		impact.emit(strength)
	_prev_vel = vel

	# ---- steering
	var steer_target: float = in_steer
	var max_lock: float = deg_to_rad(def.steer_lock) * (1.0 - def.steer_speed_reduction * WorldData.smooth(0.0, 55.0, absf(speed)))
	var driver_angle: float = 0.0
	var beta: float = 0.0
	if spd > 3.0:
		beta = atan2(vel.dot(right), absf(speed) + 0.5)
	drift_angle = rad_to_deg(beta)
	var assist: float = 0.0
	if Game.settings.assist_steer and not ai_controlled and speed > 4.0:
		assist = clampf(-beta * 0.55, -0.35, 0.35)
	var rate: float = 3.2 if absf(steer_target) > absf(steer_angle / maxf(max_lock, 0.01)) else 5.0
	driver_angle = -steer_target * max_lock
	var target_angle: float = driver_angle + assist
	steer_angle = move_toward(steer_angle, target_angle, rate * delta)
	steer_angle = clampf(steer_angle, -deg_to_rad(def.steer_lock) - 0.35, deg_to_rad(def.steer_lock) + 0.35)
	if steering_wheel:
		steering_wheel.rotation.y = 0.0
		steering_wheel.rotation.z = -steer_angle * 8.0

	# ---- gearbox / engine
	var throttle: float = in_throttle
	var brake: float = in_brake
	if gear < 0:
		# in reverse the pedals swap
		throttle = in_brake
		brake = in_throttle
	if not Game.settings.manual_gears or ai_controlled:
		if gear > 0 and speed < 1.0 and in_brake > 0.4 and in_throttle < 0.1:
			gear = -1
		elif gear < 0 and speed > -1.0 and in_throttle > 0.3:
			gear = 1
	else:
		if gear < 0 and in_throttle > 0.3 and speed > -1.0:
			gear = 1
		if gear == 1 and speed < 0.8 and in_brake > 0.4 and in_throttle < 0.1:
			gear = -1
	shift_timer = maxf(0.0, shift_timer - delta)
	var driven_v: float = 0.0
	var dn: int = 0
	for w in wheels:
		if w.drive > 0.0:
			driven_v += w.spin_v * w.radius
			dn += 1
	driven_v = absf(driven_v / maxi(dn, 1))
	var ratio: float = absf(gear_ratio()) * def.final_drive * mods.final
	var wheel_rpm: float = driven_v / wheels[0].radius * 60.0 / TAU
	var target_rpm: float = wheel_rpm * ratio
	if absf(gear) == 1 and absf(speed) < 9.0:
		target_rpm = maxf(target_rpm, def.idle_rpm + throttle * (def.peak_torque_rpm * 0.9 - def.idle_rpm))
	target_rpm = maxf(target_rpm, def.idle_rpm)
	if shift_timer > 0.0:
		target_rpm = lerpf(rpm, target_rpm, 0.5)
	rpm = lerpf(rpm, minf(target_rpm, def.redline * 1.02), clampf(delta * 18.0, 0.0, 1.0))
	if (not Game.settings.manual_gears or ai_controlled) and gear > 0 and shift_timer <= 0.0 and grounded_wheels >= 2:
		var n_g: int = def.gears.size()
		var up_rpm: float = def.redline * (0.95 if throttle > 0.7 else lerpf(0.55, 0.85, throttle / 0.7))
		var next_rpm: float = rpm * def.gears[mini(gear, n_g - 1)] / def.gears[gear - 1]
		if rpm > up_rpm and gear < n_g and (throttle > 0.7 or next_rpm > def.redline * 0.32):
			_shift(1)
		elif gear > 1:
			var down_rpm: float = rpm * def.gears[gear - 2] / def.gears[gear - 1]
			var thr: float = def.redline * (0.25 + 0.35 * throttle)
			if rpm < thr and down_rpm < def.redline * 0.86:
				_shift(-1)
	var engine_t: float = def.torque_at(rpm) * mods.power * throttle
	if rpm >= def.redline:
		engine_t = 0.0
	if shift_timer > 0.0:
		engine_t *= 0.15
	if esc_active:
		engine_t *= 0.6
	var drive_total: float = engine_t * gear_ratio() * def.final_drive * mods.final * 0.88
	if gear < 0:
		drive_total = -absf(drive_total)

	# ---- suspension + tyres
	grounded_wheels = 0
	tcs_active = false
	abs_active = false
	max_slip = 0.0
	var mu_base: float = def.grip * mods.grip
	var static_load: float = mass * 9.81 * 0.25
	var comp: Array[float] = [0.0, 0.0, 0.0, 0.0]
	var hits: Array = []
	for i in wheels.size():
		var w: Dictionary = wheels[i]
		var anchor: Vector3 = xf * w.anchor
		var reach: float = def.rest_length + w.radius
		var q := PhysicsRayQueryParameters3D.create(anchor, anchor - up * reach, 1)
		q.exclude = [get_rid()]
		var hit: Dictionary = space.intersect_ray(q)
		hits.append(hit)
		if hit.is_empty():
			w.contact = false
			w.px = w.x
			w.x = 0.0
			w.spring_len = move_toward(w.spring_len, def.rest_length, delta * 3.0)
			comp[i] = 0.0
		else:
			w.contact = true
			grounded_wheels += 1
			var d: float = anchor.distance_to(hit.position)
			w.px = w.x
			w.x = clampf(def.rest_length - (d - w.radius), 0.0, def.rest_length)
			w.spring_len = d - w.radius
			comp[i] = w.x
			var col: Object = hit.collider
			if col and col.has_meta("road_surface"):
				w.surface = col.get_meta("road_surface")
			else:
				var hp: Vector3 = hit.position
				w.surface = Game.world.terrain_surface(hp.x, hp.z, hp.y) if Game.world else 4
	var arb_f: Array[float] = [0.0, 0.0, 0.0, 0.0]
	if wheels.size() == 4:
		var fa: float = (comp[0] - comp[1]) * def.arb_front * mods.arb
		var ra: float = (comp[2] - comp[3]) * def.arb_rear * mods.arb
		arb_f = [fa, -fa, ra, -ra]
	var esc_brake_side: float = 0.0
	# ESC: compare yaw rate with what the steering asks for
	esc_active = false
	var yaw: float = angular_velocity.dot(up)
	if Game.settings.assist_esc and not ai_controlled and speed > 8.0 and grounded_wheels >= 3:
		var target_yaw: float = speed * tan(driver_angle) / maxf(wheelbase, 1.5)
		var lim: float = 9.81 * mu_base * 1.1 / maxf(speed, 1.0)
		target_yaw = clampf(target_yaw, -lim, lim)
		var err: float = yaw - target_yaw
		if absf(err) > 0.2:
			esc_active = true
			esc_brake_side = err
			apply_torque(-up * (absf(err) - 0.2) * signf(err) * mass * 2.2)
	for i in wheels.size():
		var w: Dictionary = wheels[i]
		var hit: Dictionary = hits[i]
		var pivot: Node3D = w.pivot
		var vis_len: float = w.spring_len
		pivot.position = w.anchor - Vector3(0, vis_len, 0)
		pivot.rotation.y = steer_angle * (1.08 if (steer_angle > 0) == w.left else 0.94) if w.front else 0.0
		if not w.contact:
			w.load = 0.0
			# free wheel: driven wheels spin up with throttle
			if w.drive > 0.0:
				w.spin_v = move_toward(w.spin_v, signf(drive_total) * throttle * 80.0, delta * 60.0)
			w.slip = 0.0
			continue
		var n: Vector3 = hit.normal
		w.normal = n
		w.point = hit.position
		var xv: float = (w.x - w.px) / delta
		var k: float = def.spring * mods.spring
		var f_s: float = k * w.x + (def.damper_bump if xv > 0.0 else def.damper_rebound) * mods.damper * xv
		if w.x > def.rest_length * 0.8:
			f_s += (w.x - def.rest_length * 0.8) * k * 10.0
		f_s = maxf(0.0, f_s + arb_f[i])
		# rough surfaces: small random load variation for feel
		var bump: float = SURF_BUMP[w.surface]
		if bump > 0.0 and spd > 3.0:
			f_s *= 1.0 + randf_range(-1.0, 1.0) * bump * 8.0
		var cp: Vector3 = hit.position
		apply_force(up * f_s, (xf * w.anchor) - xf.origin)
		w.load = f_s
		# tyre frame
		var wf: Vector3 = fwd.rotated(up, pivot.rotation.y)
		var f: Vector3 = (wf - n * wf.dot(n)).normalized()
		var s: Vector3 = f.cross(n).normalized()
		var v: Vector3 = vel + angular_velocity.cross(cp - com_g)
		var vl: float = v.dot(f)
		var vs: float = v.dot(s)
		var fz: float = f_s
		var load_sens: float = 1.0 - 0.06 * clampf(fz / static_load - 1.0, -1.0, 2.0)
		var mu: float = mu_base * SURF_GRIP[w.surface] * load_sens
		if LOOSE[w.surface] == 1:
			mu *= def.loose_grip
		else:
			mu *= weather_grip
		var cap: float = mu * fz
		# lateral (Pacejka-like)
		var alpha: float = atan2(vs, maxf(absf(vl), 1.5))
		var bx: float = def.lateral_stiffness * alpha
		var fy_n: float = sin(1.45 * atan(bx - 0.3 * (bx - atan(bx))))
		# arcade-sim lateral boost: tyres corner a little harder than they brake
		var fy: float = -cap * fy_n * LAT_BOOST
		if spd < 4.0:
			var ls: float = clampf(-vs * mass * 0.25 / delta * 0.2, -cap, cap)
			fy = lerpf(ls, fy, WorldData.smooth(1.0, 4.0, spd))
		# longitudinal
		var fd: float = drive_total * w.drive / w.radius
		var bshare: float = (def.brake_bias + mods.bias) if w.front else (1.0 - def.brake_bias - mods.bias)
		var fb: float = brake * def.brake_force * mods.brake * bshare
		if esc_active and absf(esc_brake_side) > 0.3:
			# brake the outside front wheel to kill oversteer
			if w.front and ((esc_brake_side > 0.0) == (not w.left)):
				fb += def.brake_force * 0.25
		var fx_v: float = 0.0
		var lat_cap: float = 1.0
		w.locked = false
		w.spinning = false
		if absf(vl) > 0.6:
			fx_v = -signf(vl) * fb
		else:
			fx_v = clampf(-vl * mass * 0.25 / delta * 0.3, -fb, fb)
		if fb > cap * 0.98 and absf(vl) > 2.0:
			if Game.settings.assist_abs or ai_controlled:
				fx_v = -signf(vl) * cap * 0.97
				abs_active = true
				lat_cap = 0.6
			else:
				fx_v = -signf(vl) * cap * def.tire_rolloff
				lat_cap = 0.3
				w.locked = true
		if in_handbrake and not w.front:
			if absf(vl) > 1.0:
				fx_v = -signf(vl) * cap * 0.8
			else:
				fx_v = clampf(-vl * mass * 0.25 / delta * 0.3, -cap, cap)
			lat_cap = 0.38
			w.locked = true
		if absf(fd) > 0.0:
			if absf(fd) > cap * 1.02:
				if (Game.settings.assist_tcs or ai_controlled) and absf(vl) < 75.0:
					fd = signf(fd) * cap * 0.98
					tcs_active = true
				else:
					fd = signf(fd) * cap * def.tire_rolloff
					w.spinning = true
					lat_cap = minf(lat_cap, 0.55)
			fx_v += fd
		# rolling resistance and soft-surface drag
		var soft: float = SURF_DRAG[w.surface] * (1.0 if not LOOSE[w.surface] or def.loose_grip < 1.2 else 0.5)
		fx_v += -clampf(vl, -1.0, 1.0) * fz * 0.015 - clampf(vl * soft, -fz * 0.12, fz * 0.12)
		fy *= lat_cap
		var cap_lat: float = cap * LAT_BOOST
		var tot: float = sqrt(fx_v * fx_v + fy * fy * (cap / cap_lat) * (cap / cap_lat))
		if tot > cap and tot > 0.0:
			var scale: float = cap / tot
			fx_v *= scale
			fy *= scale
		var fapp: Vector3 = cp + up * (w.radius * 0.55) - xf.origin
		apply_force(f * fx_v + s * fy, fapp)
		w.slip_lat = absf(alpha)
		# visual wheel speed
		var target_spin: float = vl / w.radius
		if w.locked:
			target_spin = 0.0
		elif w.spinning:
			target_spin = (vl + signf(fd) * (8.0 + throttle * 18.0)) / w.radius
		w.spin_v = lerpf(w.spin_v, target_spin, clampf(delta * 20.0, 0.0, 1.0))
		var long_slip: float = absf(w.spin_v * w.radius - vl) / maxf(absf(vl), 3.0)
		w.slip = maxf(long_slip, absf(alpha) * 2.2 - 0.25)
		max_slip = maxf(max_slip, w.slip)
		if w.front:
			surface_now = w.surface
	# wheel spin visuals
	for w in wheels:
		w.spin = fmod(w.spin + w.spin_v * delta, TAU)
		(w.mesh as Node3D).rotation.x = -w.spin

	# ---- aero
	if spd > 1.0:
		apply_central_force(-vel.normalized() * 0.5 * RHO * _cda * spd * spd)
		var down: float = 0.5 * RHO * _cla * spd * spd
		var fz_front: float = (body_aabb.position.z + body_aabb.size.z * 0.2)
		var fz_rear: float = (body_aabb.end.z - body_aabb.size.z * 0.2)
		apply_force(-up * down * def.aero_balance, bas * Vector3(0, 0.3, fz_front))
		apply_force(-up * down * (1.0 - def.aero_balance), bas * Vector3(0, 0.3, fz_rear))

	# ---- air control + landing
	if grounded_wheels == 0:
		if air_time == 0.0:
			_air_start = global_position
		air_time += delta
		var correct: Vector3 = up.cross(Vector3.UP)
		apply_torque(correct * mass * 3.0 - angular_velocity * mass * 0.6)
	else:
		if air_time > 0.6:
			landed.emit(air_time, Vector2(global_position.x - _air_start.x, global_position.z - _air_start.z).length())
		air_time = 0.0
	# low-speed yaw damping to stop creeping spin
	if grounded_wheels >= 3 and spd < 2.0 and absf(in_throttle) < 0.05:
		angular_velocity = angular_velocity.lerp(Vector3.ZERO, 0.08)

	# ---- lights
	var braking: bool = (brake > 0.1 and gear > 0) or (gear < 0 and in_throttle > 0.1)
	tail_mat.emission_energy_multiplier = 5.0 if braking else (1.5 if lights_on else 0.3)
	tail_light.light_energy = 1.5 if braking else (0.4 if lights_on else 0.0)
	rev_mat.emission_energy_multiplier = 3.0 if gear < 0 else 0.0


func _shift(dir: int) -> void:
	gear = clampi(gear + dir, 1, def.gears.size())
	shift_timer = def.shift_time
	if audio and audio.has_method("on_shift"):
		audio.on_shift(dir)


func shift_manual(dir: int) -> void:
	if gear < 0 and dir > 0:
		gear = 1
		return
	if gear == 1 and dir < 0 and absf(speed) < 2.0:
		gear = -1
		return
	if gear > 0:
		_shift(dir)


func teleport(t: Transform3D) -> void:
	_pending_tp = t
	global_transform = t
	PhysicsServer3D.body_set_state(get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM, t)
	PhysicsServer3D.body_set_state(get_rid(), PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY, Vector3.ZERO)
	PhysicsServer3D.body_set_state(get_rid(), PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY, Vector3.ZERO)
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	_prev_vel = Vector3.ZERO
	for w in wheels:
		w.spin_v = 0.0
		w.x = 0.0
		w.px = 0.0
	gear = 1
	rpm = def.idle_rpm


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if _pending_tp != null:
		state.transform = _pending_tp
		state.linear_velocity = Vector3.ZERO
		state.angular_velocity = Vector3.ZERO
		_pending_tp = null


func set_speed_forward(v: float) -> void:
	linear_velocity = -global_transform.basis.z * v
	_prev_vel = linear_velocity
