extends Node
## Prototype of Godot's built-in VehicleBody3D with the Solano's mass, geometry and powertrain,
## run through the same proving-ground tests as the project raycast vehicle.
##   godot --headless --fixed-fps 120 --path . -- --test-track --qa=vehiclebody_compare

var vb: VehicleBody3D
var wheels: Array[VehicleWheel3D] = []
var data: CarData
var tests := ["rest", "accel", "brake", "lanechange", "top", "handbrake"]
var idx := -1
var t := 0.0
var st := {}
var results := {}
var gear := 1


func _ready() -> void:
	Game.main.driver.car = null
	var player := Game.player
	data = player.data
	var wheel_pos := player.visual.wheel_rest_positions().duplicate()
	var radius := player.visual.wheel_radius_front
	var hull := player.get_node("Hull") as CollisionShape3D
	player.process_mode = Node.PROCESS_MODE_DISABLED
	player.global_position = Vector3(-1500, -50, -7000)
	player.freeze = true
	vb = VehicleBody3D.new()
	vb.mass = data.mass
	vb.center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	vb.center_of_mass = data.com_offset
	vb.continuous_cd = true
	var cs := CollisionShape3D.new()
	cs.shape = hull.shape
	vb.add_child(cs)
	for i in 4:
		var w := VehicleWheel3D.new()
		w.position = wheel_pos[i] + Vector3.UP * 0.12
		w.wheel_radius = radius
		w.wheel_rest_length = 0.2
		w.suspension_travel = 0.15
		w.suspension_stiffness = 48.0
		w.suspension_max_force = 12000.0
		w.damping_compression = 1.8
		w.damping_relaxation = 2.4
		w.wheel_friction_slip = 2.4
		w.wheel_roll_influence = 0.15
		w.use_as_steering = i < 2
		w.use_as_traction = i >= 2
		vb.add_child(w)
		wheels.append(w)
	Game.main.add_child(vb)
	_next()


func _place(z: float, kmh: float) -> void:
	vb.global_transform = Transform3D(Basis.IDENTITY, Vector3(0, 0.7, z))
	vb.linear_velocity = Vector3.FORWARD * kmh / 3.6
	vb.angular_velocity = Vector3.ZERO
	gear = 1


func _next() -> void:
	idx += 1
	t = 0.0
	st = {}
	vb.engine_force = 0.0
	vb.brake = 0.0
	vb.steering = 0.0
	if idx >= tests.size():
		results.model = "VehicleBody3D prototype (same mass/CoM/wheel positions/torque curve)"
		DirAccess.make_dir_recursive_absolute("res://qa/results")
		var f := FileAccess.open("res://qa/results/vehiclebody_compare.json", FileAccess.WRITE)
		f.store_string(JSON.stringify(results, "  ", false))
		f.close()
		print("VB_COMPARE ", JSON.stringify(results))
		get_tree().quit(0)
		return
	match tests[idx]:
		"rest":
			_place(7000, 0)
		"accel", "top":
			_place(7900 if tests[idx] == "top" else 7000, 0)
		"brake":
			_place(7000, 100)
		"lanechange":
			_place(7000, 200)
		"handbrake":
			_place(6000, 80)


func _drive(throttle: float) -> void:
	var v := -vb.global_transform.basis.z.dot(vb.linear_velocity)
	var ratio := data.gear_ratios[gear - 1] * data.final_drive
	var rpm := maxf(v / wheels[2].wheel_radius * ratio * 60.0 / TAU, data.idle_rpm)
	if rpm > data.redline_rpm and gear < data.gear_ratios.size():
		gear += 1
	rpm = minf(rpm, data.max_rpm)
	vb.engine_force = data.torque_at(rpm) * ratio * 0.9 / wheels[2].wheel_radius * throttle
	var drag := -vb.linear_velocity * vb.linear_velocity.length() * 0.5 * 1.225 * data.drag_area
	vb.apply_central_force(drag)


func _physics_process(delta: float) -> void:
	if idx < 0 or idx >= tests.size():
		return
	t += delta
	var kmh := vb.linear_velocity.length() * 3.6
	var up_dot := vb.global_transform.basis.y.dot(Vector3.UP)
	match tests[idx]:
		"rest":
			if t > 1.0:
				st.jit = maxf(float(st.get("jit", 0.0)), absf(vb.linear_velocity.y))
			if t > 4.0:
				results.rest_max_vertical_speed_m_s = snappedf(float(st.get("jit", 0.0)), 0.0001)
				_next()
		"accel":
			_drive(1.0)
			if kmh >= 100.0 and not st.has("t100"):
				st.t100 = t
			if st.has("t100") or t > 30.0:
				results.accel_0_100_s = snappedf(float(st.get("t100", -1.0)), 0.01)
				_next()
		"brake":
			if t < 0.25:
				st.start = vb.global_position
				return
			vb.brake = 60.0
			if kmh < 0.5 or t > 15.0:
				results.brake_100_0_m = snappedf(vb.global_position.distance_to(st.start), 0.1)
				_next()
		"lanechange":
			_drive(0.75)
			var s := 0.0
			if t > 1.0 and t < 2.0:
				s = -0.35 * deg_to_rad(data.high_speed_steer_deg) * 3.0
			elif t >= 2.0 and t < 3.0:
				s = 0.35 * deg_to_rad(data.high_speed_steer_deg) * 3.0
			vb.steering = s
			var fwd := -vb.global_transform.basis.z
			var slip := rad_to_deg(absf(fwd.signed_angle_to(vb.linear_velocity.normalized(), Vector3.UP))) if kmh > 10.0 else 0.0
			st.max_slip = maxf(float(st.get("max_slip", 0.0)), slip)
			st.min_up = minf(float(st.get("min_up", 1.0)), up_dot)
			if t > 6.0:
				results.lanechange_200_max_body_slip_deg = snappedf(float(st.max_slip), 0.1)
				results.lanechange_200_min_up_dot = snappedf(float(st.min_up), 0.01)
				results.lanechange_200_stable = float(st.max_slip) < 15.0 and up_dot > 0.95
				_next()
		"top":
			_drive(1.0)
			st.vmax = maxf(float(st.get("vmax", 0.0)), kmh)
			if t > 60.0 or vb.global_position.z < -7800:
				results.top_speed_kmh = snappedf(float(st.vmax), 0.1)
				_next()
		"handbrake":
			_drive(0.4)
			if t > 0.5 and t < 1.6:
				vb.steering = -0.35
				wheels[2].brake = 40.0 if t < 1.1 else 0.0
				wheels[3].brake = 40.0 if t < 1.1 else 0.0
			else:
				vb.steering = 0.0
			var fwd := -vb.global_transform.basis.z
			var slip := rad_to_deg(absf(fwd.signed_angle_to(vb.linear_velocity.normalized(), Vector3.UP))) if kmh > 5.0 else 0.0
			st.max_drift = maxf(float(st.get("max_drift", 0.0)), slip)
			if t > 5.0:
				results.handbrake_turn_max_drift_deg = snappedf(float(st.max_drift), 0.1)
				results.handbrake_recovered = slip < 10.0 and up_dot > 0.95
				_next()
