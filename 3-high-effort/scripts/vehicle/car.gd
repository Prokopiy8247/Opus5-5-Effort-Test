class_name Car
extends RigidBody3D
## Project-owned raycast vehicle on a Jolt RigidBody3D.
## Suspension: one ray per wheel, spring/damper + anti-roll bars.
## Tyres: slip-angle lateral curve, longitudinal force limited by a friction circle,
## wheel-spin / lock states derived from the circle (stable at 120 Hz).

signal impact(strength: float)
signal gear_changed(gear: int)

const LAYER_WORLD := 1
const LAYER_PLAYER := 2
const LAYER_TRAFFIC := 4
const AIR_DENSITY := 1.225

class Wheel:
	var name := ""
	var node: Node3D
	var caliper: Node3D
	var caliper_offset := Vector3.ZERO
	var rest_pos := Vector3.ZERO
	var mount := Vector3.ZERO
	var radius := 0.32
	var front := false
	var left := false
	var driven := false
	var drive_share := 0.0
	var k := 30000.0
	var c := 3000.0
	var compression := 0.0
	var prev_compression := 0.0
	var contact := false
	var hit_point := Vector3.ZERO
	var hit_normal := Vector3.UP
	var surface := 0
	var collider: Object = null
	var load := 0.0
	var spin_angle := 0.0
	var omega := 0.0
	var slip_lat := 0.0
	var slip_long := 0.0
	var v_long := 0.0
	var v_lat := 0.0
	var steer := 0.0
	var visual_offset := 0.0
	var bump_phase := 0.0

var spec: CarSpec
var model: Node3D
var wheels: Array[Wheel] = []
var is_player := false
var controls_enabled := true
## When true, in_* inputs are driven externally (drive tests, AI) even for the player car.
var external_input := false

# control inputs (0..1, steer -1..1)
var in_throttle := 0.0
var in_brake := 0.0
var in_steer := 0.0
var in_handbrake := 0.0
var steer_value := 0.0

# drivetrain state
var gear := 1  # -1 reverse, 0 neutral, 1..n
var rpm := 900.0
var shift_timer := 0.0
var shift_cooldown := 0.0
var clutch := 1.0
var engine_torque_out := 0.0
var final_drive := 3.7
var drag_area := 0.7
var downforce_area := 0.2
var peak_power_w := 100000.0
var wheelbase := 2.6
var track := 1.5
var max_gear := 6

# telemetry
var speed := 0.0
var speed_kmh := 0.0
var forward_speed := 0.0
var drift_angle := 0.0
var is_drifting := false
var airborne_time := 0.0
var wheels_on_ground := 0
var surface_id := 0
var throttle_applied := 0.0
var tcs_active := false
var abs_active := false
var last_impact := 0.0
var headlights_on := false
var braking_light := false
var odometer := 0.0

# upgrades/tuning multipliers (filled by Tuning)
var mod_power := 1.0
var mod_grip := 1.0
var mod_brake := 1.0
var mod_mass := 1.0
var mod_spring := 1.0
var mod_arb := 1.0
var mod_downforce := 1.0
var mod_final := 1.0
var mod_brake_bias := 0.0
var mod_tire_pressure := 0.0
var mod_camber := 0.0
var mod_top := 1.0

var _light_mats := {}
var _paint_mat: StandardMaterial3D
var _steering_wheel: Node3D
var _steering_wheel_basis := Basis()
var markers := {}
var _body_aabb := AABB()
var _space: PhysicsDirectSpaceState3D
var _ray := PhysicsRayQueryParameters3D.new()


func setup(car_spec: CarSpec, player: bool) -> void:
	spec = car_spec
	is_player = player
	name = "Car_" + spec.id
	collision_layer = LAYER_PLAYER if player else LAYER_TRAFFIC
	collision_mask = LAYER_WORLD | LAYER_TRAFFIC | LAYER_PLAYER
	continuous_cd = true
	contact_monitor = true
	max_contacts_reported = 4
	can_sleep = false
	gravity_scale = 1.15
	linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	linear_damp = 0.0
	angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	angular_damp = 0.25
	var pm := PhysicsMaterial.new()
	pm.friction = 0.35
	pm.bounce = 0.05
	physics_material_override = pm
	_build_model()
	_apply_mass()
	_derive_powertrain()
	body_entered.connect(_on_body_entered)


func _build_model() -> void:
	var ps := load(spec.model_path) as PackedScene
	model = ps.instantiate() as Node3D
	model.name = "Model"
	add_child(model)
	var found := {}
	_collect_nodes(model, found)
	var aabb := AABB()
	var first := true
	if found.has("Body"):
		var b: MeshInstance3D = found["Body"]
		aabb = _node_aabb_in(b, model)
		first = false
	_body_aabb = aabb
	for key in ["Wheel_FL", "Wheel_FR", "Wheel_RL", "Wheel_RR"]:
		var wn: Node3D = found.get(key)
		if wn == null:
			push_error("Car model %s missing %s" % [spec.model_path, key])
			continue
		var w := Wheel.new()
		w.name = key
		w.node = wn
		w.rest_pos = wn.position
		w.front = key.begins_with("Wheel_F")
		w.left = key.ends_with("L")
		var wa := _node_aabb_in(wn, wn)
		w.radius = maxf(wa.size.y, wa.size.z) * 0.5
		var cal: Node3D = found.get("Caliper_" + key.substr(6))
		if cal != null:
			w.caliper = cal
			w.caliper_offset = cal.position - wn.position
		wheels.append(w)
	if found.has("SteeringWheel"):
		_steering_wheel = found["SteeringWheel"]
		_steering_wheel_basis = _steering_wheel.basis
	for mk in ["Mk_Cockpit", "Mk_Hood", "Mk_Bumper"]:
		if found.has(mk):
			markers[mk] = (found[mk] as Node3D).position
	# materials: paint + lights
	_setup_materials(found)
	# collision boxes from the body bounds (simple, never per-triangle)
	if not first:
		var ride := 0.0
		for w in wheels:
			ride = maxf(ride, w.rest_pos.y - w.radius)
		var bottom := aabb.position.y + 0.18
		var top := aabb.end.y
		var lower_top := bottom + (top - bottom) * 0.55
		var shape := BoxShape3D.new()
		shape.size = Vector3(aabb.size.x * 0.9, lower_top - bottom, aabb.size.z * 0.97)
		var cs := CollisionShape3D.new()
		cs.shape = shape
		cs.position = Vector3(aabb.get_center().x, (bottom + lower_top) * 0.5, aabb.get_center().z)
		add_child(cs)
		var cabin := BoxShape3D.new()
		cabin.size = Vector3(aabb.size.x * 0.72, (top - lower_top) * 0.9, aabb.size.z * 0.5)
		var cs2 := CollisionShape3D.new()
		cs2.shape = cabin
		cs2.position = Vector3(0, lower_top + cabin.size.y * 0.5, aabb.get_center().z + aabb.size.z * 0.03)
		add_child(cs2)
	if wheels.size() == 4:
		wheelbase = absf(wheels[0].rest_pos.z - wheels[2].rest_pos.z)
		track = absf(wheels[0].rest_pos.x - wheels[1].rest_pos.x)


func _collect_nodes(n: Node, out: Dictionary) -> void:
	var nm := String(n.name)
	var base := nm
	var us := nm.rfind("_")
	if us > 0 and nm.substr(us + 1).is_valid_int() and nm.length() - us == 4:
		base = nm.substr(0, us)
	if not out.has(base):
		out[base] = n
	for ch in n.get_children():
		_collect_nodes(ch, out)


func _node_aabb_in(n: Node3D, space: Node3D) -> AABB:
	var result := AABB()
	var has := false
	var stack: Array[Node] = [n]
	while not stack.is_empty():
		var cur := stack.pop_back() as Node
		if cur is MeshInstance3D:
			var mi := cur as MeshInstance3D
			var a := _rel_xf(mi, space) * mi.get_aabb()
			if has:
				result = result.merge(a)
			else:
				result = a
				has = true
		stack.append_array(cur.get_children())
	return result


func _rel_xf(n: Node3D, ancestor: Node3D) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var cur: Node = n
	while cur != null and cur != ancestor:
		if cur is Node3D:
			xf = (cur as Node3D).transform * xf
		cur = cur.get_parent()
	return xf


func _setup_materials(found: Dictionary) -> void:
	var custom := Game.custom_for(spec.id)
	_paint_mat = StandardMaterial3D.new()
	_paint_mat.resource_name = "CarPaint"
	apply_paint(custom.get("color", spec.paint_color), custom.get("finish", spec.paint_finish))
	var rim_mat: StandardMaterial3D = null
	for mi in _all_meshes(model):
		var mesh := mi.mesh
		if mesh == null:
			continue
		for si in mesh.get_surface_count():
			var m := mesh.surface_get_material(si)
			if m == null:
				continue
			var mn := String(m.resource_name)
			if mn.begins_with("M_Paint"):
				mi.set_surface_override_material(si, _paint_mat)
			elif mn.begins_with("M_Rim"):
				if rim_mat == null:
					rim_mat = (m as StandardMaterial3D).duplicate() if m is StandardMaterial3D else StandardMaterial3D.new()
					rim_mat.albedo_color = custom.get("rim_color", spec.rim_color)
					rim_mat.metallic = 0.9
					rim_mat.roughness = 0.25
				mi.set_surface_override_material(si, rim_mat)
			elif mn == "M_Glass":
				var g := StandardMaterial3D.new()
				g.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				g.albedo_color = Color(0.06, 0.08, 0.1, 0.42)
				g.roughness = 0.04
				g.metallic = 0.2
				g.metallic_specular = 0.9
				g.cull_mode = BaseMaterial3D.CULL_DISABLED
				mi.set_surface_override_material(si, g)
	for key in ["Lights_Head", "Lights_Tail", "Lights_Reverse", "Lights_Brake"]:
		if not found.has(key):
			continue
		var mi2 := found[key] as MeshInstance3D
		if mi2 == null:
			continue
		var lm := StandardMaterial3D.new()
		lm.emission_enabled = true
		match key:
			"Lights_Head":
				lm.albedo_color = Color(0.85, 0.88, 0.92)
				lm.emission = Color(1.0, 0.95, 0.85)
				lm.metallic = 0.6
				lm.roughness = 0.08
			"Lights_Reverse":
				lm.albedo_color = Color(0.45, 0.45, 0.47)
				lm.metallic = 0.7
				lm.emission = Color(1, 1, 1)
				lm.roughness = 0.2
			_:
				lm.albedo_color = Color(0.7, 0.03, 0.03)
				lm.emission = Color(1.0, 0.04, 0.02)
				lm.roughness = 0.15
		lm.emission_energy_multiplier = 0.0
		mi2.material_override = lm
		_light_mats[key] = lm
	# Real lights for the player only (cheap: two spots, no shadows)
	if is_player:
		for sx in [-1.0, 1.0]:
			var sl := SpotLight3D.new()
			sl.name = "HeadSpot"
			sl.light_color = Color(1.0, 0.95, 0.85)
			sl.spot_range = 70.0
			sl.spot_angle = 32.0
			sl.spot_attenuation = 0.8
			sl.light_energy = 0.0
			sl.shadow_enabled = false
			var front_z := _body_aabb.position.z + 0.1
			sl.position = Vector3(sx * _body_aabb.size.x * 0.32, 0.7, front_z)
			sl.rotation_degrees = Vector3(-4.0, 0.0, 0.0)
			add_child(sl)
		var tail := OmniLight3D.new()
		tail.name = "TailGlow"
		tail.light_color = Color(1.0, 0.1, 0.05)
		tail.omni_range = 4.0
		tail.light_energy = 0.0
		tail.position = Vector3(0, 0.8, _body_aabb.end.z + 0.3)
		add_child(tail)


func _all_meshes(n: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	var stack: Array[Node] = [n]
	while not stack.is_empty():
		var cur: Node = stack.pop_back()
		if cur is MeshInstance3D:
			out.append(cur)
		stack.append_array(cur.get_children())
	return out


func apply_paint(color: Color, finish: String) -> void:
	if _paint_mat == null:
		return
	_paint_mat.albedo_color = color
	_paint_mat.clearcoat_enabled = finish != "matte"
	_paint_mat.clearcoat = 1.0
	_paint_mat.clearcoat_roughness = 0.08
	match finish:
		"gloss":
			_paint_mat.metallic = 0.1
			_paint_mat.roughness = 0.18
		"matte":
			_paint_mat.metallic = 0.05
			_paint_mat.roughness = 0.7
		"pearl":
			_paint_mat.metallic = 0.55
			_paint_mat.roughness = 0.22
			_paint_mat.rim_enabled = true
			_paint_mat.rim = 0.4
			_paint_mat.rim_tint = 0.8
		_:
			_paint_mat.metallic = 0.75
			_paint_mat.roughness = 0.3
	if finish != "pearl":
		_paint_mat.rim_enabled = false


func set_rim_color(color: Color) -> void:
	for mi in _all_meshes(model):
		for si in mi.get_surface_override_material_count():
			var m := mi.get_surface_override_material(si)
			if m is StandardMaterial3D and mi.mesh.surface_get_material(si) != null \
					and String(mi.mesh.surface_get_material(si).resource_name).begins_with("M_Rim"):
				(m as StandardMaterial3D).albedo_color = color
				return


func _apply_mass() -> void:
	mass = spec.mass * mod_mass
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = spec.com_offset
	var size := _body_aabb.size
	if size == Vector3.ZERO:
		size = Vector3(1.8, 1.3, 4.3)
	var h := size.y * 0.7
	inertia = Vector3(
		mass / 12.0 * (h * h + size.z * size.z) * spec.inertia_scale.x,
		mass / 12.0 * (size.x * size.x + size.z * size.z) * spec.inertia_scale.y,
		mass / 12.0 * (size.x * size.x + h * h) * spec.inertia_scale.z) * 0.85
	var nf := 0
	var nr := 0
	for w in wheels:
		if w.front:
			nf += 1
		else:
			nr += 1
	# static load per wheel from the COM position between the axles
	var zf := 0.0
	var zr := 0.0
	for w in wheels:
		if w.front:
			zf = w.rest_pos.z
		else:
			zr = w.rest_pos.z
	var front_frac := clampf((zr - spec.com_offset.z) / maxf(zr - zf, 0.1), 0.25, 0.75)
	var g := 9.8 * gravity_scale
	for w in wheels:
		var corner := mass * (front_frac if w.front else 1.0 - front_frac) * 0.5
		var hz := (spec.spring_hz_front if w.front else spec.spring_hz_rear)
		w.k = corner * pow(TAU * hz, 2.0) * mod_spring
		w.c = 2.0 * spec.damping_ratio * sqrt(w.k * corner)
		var sag := corner * g / w.k
		w.mount = w.rest_pos + Vector3.UP * (spec.suspension_rest - sag)


func _derive_powertrain() -> void:
	# peak power from the torque curve
	# drag is fitted to the stock car's power so engine upgrades really raise top speed
	peak_power_w = 0.0
	var r := spec.idle_rpm
	while r <= spec.redline_rpm:
		peak_power_w = maxf(peak_power_w, spec.torque_at(r) * r * TAU / 60.0)
		r += 50.0
	var vtop := spec.top_speed_kmh / 3.6
	var eff := spec.drivetrain_efficiency
	# drag area so that power balances drag + rolling at the target top speed
	var roll := spec.rolling_resistance * mass * 9.8 * vtop
	drag_area = maxf(0.25, 2.0 * (peak_power_w * eff * 0.97 - roll) / (AIR_DENSITY * pow(vtop, 3.0)))
	downforce_area = spec.downforce_area * mod_downforce
	max_gear = spec.gear_ratios.size()
	var top_ratio := spec.gear_ratios[max_gear - 1]
	var radius := wheels[2].radius if wheels.size() > 2 else 0.32
	# gear the top ratio so peak power arrives near the target top speed
	var rpm_at_top := spec.redline_rpm * 0.93
	final_drive = (rpm_at_top * TAU / 60.0) * radius / (vtop * mod_top * top_ratio) * mod_final
	peak_power_w *= mod_power
	var nd := 0
	for w in wheels:
		match spec.drivetrain:
			CarSpec.Drivetrain.FWD:
				w.driven = w.front
			CarSpec.Drivetrain.RWD:
				w.driven = not w.front
			_:
				w.driven = true
		if w.driven:
			nd += 1
	for w in wheels:
		if not w.driven:
			w.drive_share = 0.0
		elif spec.drivetrain == CarSpec.Drivetrain.AWD:
			w.drive_share = (spec.awd_front_split if w.front else 1.0 - spec.awd_front_split) * 0.5
		else:
			w.drive_share = 1.0 / float(nd)


func refresh_tuning() -> void:
	_apply_mass()
	_derive_powertrain()


# ------------------------------------------------------------------ input
func _read_player_input(delta: float) -> void:
	if not controls_enabled:
		# menus open: bring the car to a gentle stop
		in_throttle = 0.0
		in_brake = 0.5 if forward_speed > 0.5 else 0.0
		in_handbrake = 0.0
		in_steer = 0.0
		return
	in_throttle = Input.get_action_strength("accelerate")
	in_brake = Input.get_action_strength("brake")
	in_handbrake = Input.get_action_strength("handbrake")
	in_steer = Input.get_action_strength("steer_right") - Input.get_action_strength("steer_left")


func _unhandled_input(event: InputEvent) -> void:
	if not is_player or not controls_enabled:
		return
	if event.is_action_pressed("shift_up") and not Game.assists.auto:
		shift(gear + 1)
	elif event.is_action_pressed("shift_down") and not Game.assists.auto:
		shift(gear - 1)
	elif event.is_action_pressed("headlights"):
		headlights_on = not headlights_on


func shift(target: int) -> void:
	target = clampi(target, -1, max_gear)
	if target == gear:
		return
	gear = target
	shift_timer = spec.shift_time if gear > 0 else 0.0
	shift_cooldown = spec.shift_time + 0.35
	gear_changed.emit(gear)


func gear_ratio(g: int) -> float:
	if g == -1:
		return -spec.reverse_ratio
	if g <= 0:
		return 0.0
	return spec.gear_ratios[g - 1]


# ------------------------------------------------------------------ physics
func _physics_process(delta: float) -> void:
	var _t0 := Time.get_ticks_usec()
	_physics_process_inner(delta)
	Game.prof_add("car_phys", Time.get_ticks_usec() - _t0)


func _physics_process_inner(delta: float) -> void:
	if spec == null or wheels.size() != 4:
		return
	if is_player and not external_input:
		_read_player_input(delta)
	_space = get_world_3d().direct_space_state
	var xf := global_transform
	var basis_n := xf.basis.orthonormalized()
	var up := basis_n.y
	var fwd := -basis_n.z
	var right := basis_n.x
	var vel := linear_velocity
	speed = vel.length()
	speed_kmh = speed * 3.6
	forward_speed = vel.dot(fwd)
	odometer += speed * delta

	_update_steering(delta, basis_n)
	_update_gearbox(delta)

	# ---- suspension rays
	wheels_on_ground = 0
	_ray.exclude = [get_rid()]
	_ray.collision_mask = LAYER_WORLD
	_ray.hit_back_faces = false
	for w in wheels:
		var mount_g := xf * w.mount
		var ray_len := spec.suspension_rest + w.radius
		_ray.from = mount_g + up * 0.25
		_ray.to = mount_g - up * ray_len
		var hit := _space.intersect_ray(_ray)
		w.prev_compression = w.compression
		if hit.is_empty():
			w.contact = false
			w.compression = 0.0
			w.load = 0.0
			continue
		var dist: float = (hit.position as Vector3).distance_to(mount_g + up * 0.25) - 0.25
		w.contact = true
		w.hit_point = hit.position
		w.hit_normal = hit.normal
		w.collider = hit.collider
		w.surface = _surface_of(hit)
		var surf := Game.surface(w.surface)
		var bump := 0.0
		if surf.bumpiness > 0.0 and speed > 1.0:
			w.bump_phase += speed * delta * 1.7
			bump = (sin(w.bump_phase * 2.3) * 0.6 + sin(w.bump_phase * 5.1 + 1.3) * 0.4) * surf.bumpiness
		w.compression = clampf(spec.suspension_rest - (dist - w.radius) + bump, 0.0, spec.suspension_rest)
		wheels_on_ground += 1

	# ---- anti-roll per axle
	var arb_f := spec.anti_roll_front * mod_arb
	var arb_r := spec.anti_roll_rear * mod_arb
	var roll_f := (wheels[0].compression - wheels[1].compression) * arb_f
	var roll_r := (wheels[2].compression - wheels[3].compression) * arb_r

	# ---- engine torque
	var ratio := gear_ratio(gear)
	var driven_omega := 0.0
	var nd := 0
	for w in wheels:
		if w.driven:
			driven_omega += w.omega
			nd += 1
	driven_omega /= maxf(nd, 1)
	var wheel_rpm := absf(driven_omega) * absf(ratio) * final_drive * 60.0 / TAU
	var throttle := in_throttle
	var brake := in_brake
	# reverse handling: brake held at standstill engages reverse (auto box)
	if Game.assists.auto or not is_player:
		if gear >= 1 and in_brake > 0.3 and in_throttle < 0.1 and forward_speed < 0.8:
			shift(-1)
		elif gear == -1 and in_throttle > 0.3 and forward_speed > -0.8:
			shift(1)
	if gear == -1:
		var t := throttle
		throttle = brake
		brake = t
	var target_rpm := maxf(wheel_rpm, spec.idle_rpm)
	if (gear == 1 or gear == -1) and throttle > 0.05:
		# slipping clutch at low wheel speed lets the engine reach launch revs
		var launch_rpm := lerpf(spec.idle_rpm * 1.4, minf(spec.redline_rpm * 0.55, 4200.0), throttle)
		target_rpm = maxf(target_rpm, launch_rpm * clampf(1.0 - wheel_rpm / launch_rpm, 0.0, 1.0) + wheel_rpm)
	if gear == 0 or shift_timer > 0.0:
		target_rpm = lerpf(spec.idle_rpm, spec.redline_rpm, throttle * 0.95) if gear == 0 else maxf(wheel_rpm, spec.idle_rpm)
	rpm = lerpf(rpm, target_rpm, clampf(delta * 18.0, 0.0, 1.0))
	rpm = clampf(rpm, spec.idle_rpm * 0.8, spec.redline_rpm * 1.02)
	var limiter := rpm >= spec.redline_rpm
	var eng_t := spec.torque_at(rpm) * mod_power * throttle
	if limiter:
		eng_t = 0.0
	if shift_timer > 0.0:
		eng_t = 0.0
	var engine_brake_t := spec.peak_torque * spec.engine_brake * (1.0 - throttle) * clampf(rpm / spec.redline_rpm, 0.0, 1.0)
	engine_torque_out = eng_t
	var wheel_torque_total := (eng_t * signf(ratio) - engine_brake_t * signf(driven_omega) * (1.0 if gear != 0 else 0.0)) \
		* absf(ratio) * final_drive * spec.drivetrain_efficiency
	throttle_applied = throttle

	# ---- per-wheel forces
	var mass_corner := mass * 0.25
	var grip_base := spec.grip * mod_grip * (1.0 - absf(mod_tire_pressure) * 0.06)
	var bias := clampf(spec.brake_bias + mod_brake_bias, 0.3, 0.8)
	var com_g := xf * center_of_mass
	tcs_active = false
	abs_active = false
	var total_slip := 0.0
	var surface_votes := {}
	for i in wheels.size():
		var w := wheels[i]
		var steer_basis := basis_n.rotated(up, -w.steer) if w.front else basis_n
		var wf := -steer_basis.z
		var wr := steer_basis.x
		if not w.contact:
			# free wheel spins down slowly / driven wheels follow engine
			if w.driven and gear != 0:
				w.omega = lerpf(w.omega, rpm * TAU / 60.0 / maxf(absf(ratio) * final_drive, 0.01) * signf(ratio), delta * 4.0)
			else:
				w.omega = lerpf(w.omega, 0.0, delta * 0.5)
			w.slip_lat = 0.0
			w.slip_long = 0.0
			continue
		var n := w.hit_normal
		# project tyre axes onto the ground plane
		wf = (wf - n * wf.dot(n)).normalized()
		wr = (wr - n * wr.dot(n)).normalized()
		var rel := w.hit_point - com_g
		var pv := vel + angular_velocity.cross(w.hit_point - global_position)
		w.v_long = pv.dot(wf)
		w.v_lat = pv.dot(wr)

		# suspension
		var comp_vel := (w.compression - w.prev_compression) / delta
		var fs := w.k * w.compression + w.c * comp_vel
		var arb := roll_f if i < 2 else roll_r
		fs += arb if w.left else -arb
		if w.compression > spec.suspension_rest * 0.92:
			fs += (w.compression - spec.suspension_rest * 0.92) * w.k * 8.0
		fs = maxf(fs, 0.0)
		w.load = fs
		apply_force(n.lerp(up, 0.5).normalized() * fs, w.hit_point - global_position)

		var surf := Game.surface(w.surface)
		var tire_idx := int(spec.tire_type)
		var sgrip := surf.grip_by_tire[tire_idx] if tire_idx < surf.grip_by_tire.size() else 1.0
		var wet := lerpf(1.0, Game.weather_grip, surf.wet_sensitivity)
		var mu := grip_base * sgrip * wet * (spec.grip_rear_bias if not w.front else 1.0)
		var load_eff := minf(fs, mass_corner * 9.8 * 2.6)
		var cap := mu * load_eff * (1.0 - 0.08 * clampf(load_eff / (mass_corner * 9.8) - 1.0, 0.0, 2.0))

		# lateral force from slip angle
		var slip_angle := atan2(w.v_lat, maxf(absf(w.v_long), 1.0))
		var peak := deg_to_rad(spec.peak_slip_angle_deg + mod_camber * 0.6)
		var x := absf(slip_angle) / peak
		var coef := sin(minf(x, 1.0) * PI * 0.5) if x < 1.0 else lerpf(1.0, spec.slide_grip, clampf((x - 1.0) / 2.5, 0.0, 1.0))
		var fy := -signf(slip_angle) * coef * cap
		if absf(w.v_long) < 3.0:
			# low speed: viscous lateral grip so the car does not creep sideways
			var visc := clampf(-w.v_lat * mass_corner * 6.0, -cap, cap)
			fy = lerpf(visc, fy, clampf(absf(w.v_long) / 3.0, 0.0, 1.0))

		# longitudinal
		var drive_f := wheel_torque_total * w.drive_share / w.radius
		var brake_f := brake * spec.brake_force * mod_brake * (bias if w.front else 1.0 - bias) * 0.5 * 2.0
		if not w.front and in_handbrake > 0.1:
			brake_f += spec.handbrake_force * in_handbrake
		var fx := drive_f
		var locked := false
		if brake_f > 0.0:
			if absf(w.v_long) > 0.6:
				fx -= signf(w.v_long) * brake_f
			else:
				fx += clampf(-w.v_long * mass_corner * 8.0, -brake_f, brake_f)
		fx -= signf(w.v_long) * surf.rolling_resistance * fs * (1.0 if absf(w.v_long) > 0.3 else absf(w.v_long) / 0.3)
		var lat_need := absf(fy)
		var long_cap := sqrt(maxf(cap * cap - lat_need * lat_need, cap * cap * 0.04))
		var spin_excess := 0.0
		var handbraking := not w.front and in_handbrake > 0.1
		if absf(fx) > long_cap:
			var braking_dir := brake_f > 0.0 and signf(fx) == -signf(w.v_long)
			if braking_dir:
				if (Game.assists.abs or not is_player) and not handbraking:
					fx = signf(fx) * long_cap * 0.97
					abs_active = true
				else:
					locked = true
					fx = signf(fx) * cap * spec.slide_grip
					fy *= 0.35
			else:
				if w.driven and Game.assists.tcs and is_player:
					fx = signf(fx) * long_cap * 0.98
					tcs_active = true
				elif w.driven:
					spin_excess = (absf(fx) - long_cap) / maxf(cap, 1.0)
					fx = signf(fx) * cap * lerpf(0.95, spec.slide_grip, clampf(spin_excess, 0.0, 1.0))
					# spinning tyre loses lateral grip (power oversteer)
					fy *= clampf(1.0 - spin_excess * 0.9, 0.2, 1.0)
		if handbraking:
			fy *= 0.45
			locked = absf(w.v_long) > 1.0
		# final friction circle
		var tot := Vector2(fx, fy).length()
		if tot > cap and tot > 0.0:
			var sc := cap / tot
			fx *= sc
			fy *= sc
		var force := wf * fx + wr * fy
		var app := w.hit_point + up * (w.radius * 0.35)
		apply_force(force, app - global_position)

		# wheel spin state (visual, rpm, audio)
		var free_omega := w.v_long / w.radius
		if locked:
			w.omega = lerpf(w.omega, 0.0, clampf(delta * 30.0, 0.0, 1.0))
		elif spin_excess > 0.0:
			w.omega = free_omega + signf(drive_f) * clampf(spin_excess, 0.0, 1.5) * 40.0
		else:
			w.omega = free_omega
		w.slip_lat = clampf(x, 0.0, 4.0) if absf(w.v_long) > 2.0 or absf(w.v_lat) > 1.0 else 0.0
		w.slip_long = 1.0 if locked else clampf(spin_excess * 2.0, 0.0, 1.0)
		total_slip += w.slip_lat
		surface_votes[w.surface] = int(surface_votes.get(w.surface, 0)) + 1

	if not surface_votes.is_empty():
		var bestn := -1
		for k in surface_votes:
			if surface_votes[k] > bestn:
				bestn = surface_votes[k]
				surface_id = k

	# ---- aero
	var v2 := forward_speed * forward_speed
	if speed > 1.0:
		apply_central_force(-vel.normalized() * 0.5 * AIR_DENSITY * drag_area * speed * speed)
	# soft surfaces (sand, grass, mud) bog the car down
	var sdrag := Game.surface(surface_id).drag
	if wheels_on_ground > 0 and speed > 0.5 and sdrag > 0.0:
		apply_central_force(-vel.normalized() * sdrag * mass * 9.8 * minf(speed / 8.0, 1.0) * wheels_on_ground / 4.0)
	var df := 0.5 * AIR_DENSITY * downforce_area * v2
	if wheels_on_ground > 0:
		var fz := (wheels[0].rest_pos.z + wheels[1].rest_pos.z) * 0.5
		var rz := (wheels[2].rest_pos.z + wheels[3].rest_pos.z) * 0.5
		apply_force(-up * df * spec.aero_balance, basis_n * Vector3(0, 0.3, fz))
		apply_force(-up * df * (1.0 - spec.aero_balance), basis_n * Vector3(0, 0.3, rz))

	# ---- stability control / arcade yaw help
	var yaw_rate := angular_velocity.dot(up)
	var lat_v := vel.dot(right)
	drift_angle = rad_to_deg(atan2(lat_v, maxf(absf(forward_speed), 0.1))) if speed > 3.0 else 0.0
	is_drifting = absf(drift_angle) > 12.0 and speed > 9.0 and wheels_on_ground >= 3
	if wheels_on_ground >= 2 and speed > 4.0:
		var target_yaw := forward_speed * tan(steer_value) / maxf(wheelbase, 1.0)
		var err := yaw_rate - (-target_yaw)
		var gain := 0.0
		if Game.assists.stm or not is_player:
			gain = 0.55 if absf(drift_angle) > 6.0 else 0.25
		else:
			gain = 0.06
		apply_torque(-up * err * gain * inertia.y)
		# keep long-wheelbase cars from feeling numb at speed: slight yaw damping only
	# ---- air control & landing stability
	if wheels_on_ground == 0:
		airborne_time += delta
		var level_axis := up.cross(Vector3.UP)
		apply_torque(level_axis * inertia.x * 2.5 - angular_velocity * inertia.x * 0.8)
	else:
		airborne_time = 0.0
	if shift_timer > 0.0:
		shift_timer -= delta
	braking_light = brake > 0.1 and gear != -1 or (gear == -1 and in_throttle > 0.1 and false)
	_update_lights()


func _surface_of(hit: Dictionary) -> int:
	var col: Object = hit.collider
	if col != null and col.has_meta("surface"):
		return int(col.get_meta("surface"))
	if col != null and col.has_meta("terrain") and Game.world != null:
		var p: Vector3 = hit.position
		return Game.world.surface_at(p.x, p.z)
	return Game.Surf.ASPHALT


func _update_steering(delta: float, b: Basis) -> void:
	var v := absf(forward_speed)
	var lock := deg_to_rad(spec.steer_lock_deg)
	var speed_factor := clampf(1.0 / (1.0 + pow(v / 12.0 * (spec.steer_speed_falloff / 0.014), 1.5)), 0.07, 1.0)
	var target := in_steer * lock * speed_factor
	if (Game.assists.steer or not is_player) and v > 5.0 and wheels_on_ground >= 2:
		# counter-steer help: bias the wheels toward the direction of travel
		var slip := deg_to_rad(drift_angle)
		target += clampf(slip * 0.55, -lock * 0.5, lock * 0.5) * (1.0 - absf(in_steer) * 0.4)
	var rate := 2.6 if absf(target) > absf(steer_value) else 4.0
	if not is_player:
		rate = 3.0
	steer_value = move_toward(steer_value, target, rate * lock * delta)
	for w in wheels:
		if w.front:
			# simple Ackermann: inner wheel turns more
			var inner := (steer_value > 0.0 and not w.left) or (steer_value < 0.0 and w.left)
			w.steer = steer_value * (1.08 if inner else 0.94)


func _update_gearbox(delta: float) -> void:
	if not (Game.assists.auto or not is_player):
		return
	shift_cooldown -= delta
	if shift_timer > 0.0 or gear <= 0 or shift_cooldown > 0.0:
		if gear == 0 and in_throttle > 0.1:
			shift(1)
		return
	if rpm > spec.redline_rpm * 0.955 and gear < max_gear and wheels_on_ground >= 2:
		var nr := rpm * gear_ratio(gear + 1) / gear_ratio(gear)
		if nr > spec.idle_rpm * 1.2:
			shift(gear + 1)
	elif gear > 1:
		var lower_rpm := rpm * gear_ratio(gear - 1) / gear_ratio(gear)
		var thresh := spec.redline_rpm * (0.82 if in_throttle > 0.6 else 0.6)
		if lower_rpm < thresh and rpm < spec.redline_rpm * (0.55 if in_throttle > 0.6 else 0.38):
			shift(gear - 1)


func _process(delta: float) -> void:
	if spec == null:
		return
	# wheel visuals: suspension travel, steering, spin
	for w in wheels:
		var droop := spec.suspension_rest - w.compression
		var pos := w.mount - Vector3.UP * droop
		w.spin_angle = wrapf(w.spin_angle - w.omega * delta, -TAU, TAU)
		var b := Basis(Vector3.UP, -w.steer if w.front else 0.0)
		w.node.transform = Transform3D(b * Basis(Vector3.RIGHT, w.spin_angle), pos)
		if w.caliper:
			w.caliper.transform = Transform3D(b, pos + b * w.caliper_offset)
	if _steering_wheel:
		_steering_wheel.basis = _steering_wheel_basis * Basis(Vector3(0, 0.37, -0.93).normalized(), steer_value * 6.0)


func _update_lights() -> void:
	var night := Game.time_of_day < 6.8 or Game.time_of_day > 19.3 or Game.weather_name in ["fog", "storm", "rain"]
	var head := headlights_on or night
	if _light_mats.has("Lights_Head"):
		(_light_mats["Lights_Head"] as StandardMaterial3D).emission_energy_multiplier = 3.0 if head else 0.0
	var tail_e := 0.25
	if head:
		tail_e = 1.2
	if braking_light:
		tail_e = 4.5
	if _light_mats.has("Lights_Tail"):
		(_light_mats["Lights_Tail"] as StandardMaterial3D).emission_energy_multiplier = tail_e
	if _light_mats.has("Lights_Brake"):
		(_light_mats["Lights_Brake"] as StandardMaterial3D).emission_energy_multiplier = 4.5 if braking_light else 0.0
	if _light_mats.has("Lights_Reverse"):
		(_light_mats["Lights_Reverse"] as StandardMaterial3D).emission_energy_multiplier = 3.0 if gear == -1 else 0.0
	if is_player:
		for ch in get_children():
			if ch is SpotLight3D:
				(ch as SpotLight3D).light_energy = 6.0 if head else 0.0
			elif ch is OmniLight3D:
				(ch as OmniLight3D).light_energy = (1.2 if braking_light else 0.25) if head or braking_light else 0.0


func _on_body_entered(body: Node) -> void:
	var s := linear_velocity.length()
	last_impact = s
	impact.emit(s)


# ------------------------------------------------------------------ utilities
func teleport(xform: Transform3D) -> void:
	global_transform = xform
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	for w in wheels:
		w.omega = 0.0
		w.compression = 0.0
		w.prev_compression = 0.0
	rpm = spec.idle_rpm
	gear = 1
	steer_value = 0.0
	PhysicsServer3D.body_set_state(get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM, xform)
	PhysicsServer3D.body_set_state(get_rid(), PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY, Vector3.ZERO)
	PhysicsServer3D.body_set_state(get_rid(), PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY, Vector3.ZERO)


func set_velocity_forward(mps: float) -> void:
	linear_velocity = -global_transform.basis.z * mps
	for w in wheels:
		w.omega = mps / w.radius
	# pick the gear the automatic box would be in at this speed
	gear = 1
	for g in range(1, max_gear + 1):
		var r := mps / wheels[0].radius * gear_ratio(g) * final_drive * 60.0 / TAU
		gear = g
		if r < spec.redline_rpm * 0.85:
			break
	rpm = clampf(mps / wheels[0].radius * gear_ratio(gear) * final_drive * 60.0 / TAU, spec.idle_rpm, spec.redline_rpm)


func avg_slip() -> float:
	var s := 0.0
	for w in wheels:
		s += w.slip_lat
	return s / 4.0


func wheel_contact_count() -> int:
	return wheels_on_ground
