extends Node3D
## Prototype comparison: Godot's built-in VehicleBody3D vs the project-owned raycast CarController,
## same car (Kestrel R4 mass/geometry/power), same scripted manoeuvres on the flat proving ground.
##   Godot_console.exe --headless --path <project> res://tools/tests/vehiclebody_compare.tscn --fixed-fps 120
## Results are printed and written to qa_output/vehiclebody_compare.json.

const DT := 1.0 / 120.0

var track: TestTrack
var results := {}


func _ready() -> void:
	track = TestTrack.new()
	add_child(track)
	_run.call_deferred()


func _make_vehicle_body(d: CarData) -> VehicleBody3D:
	var vb := VehicleBody3D.new()
	vb.mass = d.mass
	vb.center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	vb.center_of_mass = d.com
	vb.continuous_cd = true
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(d.body_size.x * 0.94, 0.7, d.body_size.z * 0.97)
	cs.shape = box
	cs.position = Vector3(0, 0.6, 0)
	vb.add_child(cs)
	for id: String in ["FL", "FR", "RL", "RR"]:
		var w := VehicleWheel3D.new()
		var front := id.begins_with("F")
		var r := d.wheel_radius_front if front else d.wheel_radius_rear
		w.position = Vector3((-0.765 if id.ends_with("L") else 0.765), r + 0.12, -1.275 if front else 1.275)
		w.wheel_radius = r
		w.wheel_rest_length = 0.22
		w.suspension_travel = 0.2
		# VehicleWheel3D stiffness/damping are mass-normalised and in different units than ours; use the
		# documented typical ranges (stiffness 50-200 for sport cars, damping 0.1-0.5 x stiffness).
		w.suspension_stiffness = 60.0
		w.damping_compression = 3.0
		w.damping_relaxation = 4.5
		w.wheel_friction_slip = 1.6
		w.wheel_roll_influence = 0.12
		w.use_as_steering = front
		w.use_as_traction = front
		w.suspension_max_force = d.mass * 9.81 * 2.0
		vb.add_child(w)
	return vb


func _drive_force(d: CarData, speed: float) -> float:
	# Same peak power, simple gearing-free traction curve (VehicleBody3D has no drivetrain model).
	var p := d.peak_power_kw() * 1000.0 * d.drivetrain_efficiency
	var f_max := d.peak_torque * d.gear_ratios[0] * d.final_drive * d.drivetrain_efficiency / d.wheel_radius_front
	return minf(f_max, p / maxf(speed, 1.0))


func _run() -> void:
	var d: CarData = (load("res://data/cars/kestrel_r4.tres") as CarData).duplicate(true)
	results["vehiclebody3d"] = await _test_vb(d)
	results["raycast_controller"] = await _test_rc(d)
	print("VB_COMPARE ", JSON.stringify(results))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://qa_output"))
	var f := FileAccess.open("res://qa_output/vehiclebody_compare.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(results, "\t"))
	get_tree().quit(0)


func _yaw_err(n: Node3D, target: float) -> float:
	var fw := -n.global_transform.basis.z
	return wrapf(atan2(-fw.x, -fw.z) - target, -PI, PI)


func _test_vb(d: CarData) -> Dictionary:
	var vb := _make_vehicle_body(d)
	add_child(vb)
	vb.global_position = Vector3(0, 0.6, 4000)
	for i in 120:
		await get_tree().physics_frame
	var t := 0.0
	var t100 := -1.0
	var vmax := 0.0
	var max_slip := 0.0
	var max_roll := 0.0
	var phase := 0
	var tl := 0.0
	var flipped := false
	while t < 90.0:
		var v := vb.linear_velocity.length()
		var kmh := v * 3.6
		vmax = maxf(vmax, kmh)
		if t100 < 0.0 and kmh >= 100.0:
			t100 = t
		if phase == 0:
			vb.engine_force = _drive_force(d, v)
			vb.steering = clampf(_yaw_err(vb, 0.0) * 1.5, -0.4, 0.4)
			if kmh >= 200.0 or t > 70.0:
				phase = 1
		elif phase == 1:
			# Same double lane change as the raycast drive test.
			vb.engine_force = _drive_force(d, v) * 0.7
			vb.steering = -sin(tl / 2.4 * TAU) * 0.55 * deg_to_rad(7.0) / 0.4 if tl < 2.4 else clampf(_yaw_err(vb, 0.0) * 1.0, -0.2, 0.2)
			tl += DT
			var fw := -vb.global_transform.basis.z
			var lat := vb.linear_velocity.dot(vb.global_transform.basis.x)
			max_slip = maxf(max_slip, rad_to_deg(absf(atan2(lat, absf(vb.linear_velocity.dot(fw))))))
			max_roll = maxf(max_roll, rad_to_deg(acos(clampf(vb.global_transform.basis.y.y, -1.0, 1.0))))
			if vb.global_transform.basis.y.y < 0.3:
				flipped = true
			if tl > 6.4:
				break
		await get_tree().physics_frame
		t += DT
		if vb.global_position.z < -4500.0:
			vb.global_position.z += 9000.0
	var res := {"t_0_100": snappedf(t100, 0.01), "top_reached_kmh": snappedf(vmax, 0.1), "lane_change_max_slip_deg": snappedf(max_slip, 0.1),
		"lane_change_max_roll_deg": snappedf(max_roll, 0.1), "flipped": flipped}
	vb.queue_free()
	await get_tree().physics_frame
	return res


func _test_rc(d: CarData) -> Dictionary:
	var car := CarFactory.build(d, {}, true)
	add_child(car)
	car.place_at(Transform3D(Basis(), Vector3(0, 0.05, 4000)))
	for i in 120:
		await get_tree().physics_frame
	var t := 0.0
	var t100 := -1.0
	var vmax := 0.0
	var max_slip := 0.0
	var max_roll := 0.0
	var phase := 0
	var tl := 0.0
	while t < 90.0:
		var kmh := car.get_speed_kmh()
		vmax = maxf(vmax, kmh)
		if t100 < 0.0 and kmh >= 100.0:
			t100 = t
		if phase == 0:
			car.in_throttle = 1.0
			car.in_steer = clampf(_yaw_err(car, 0.0) * 1.6, -1.0, 1.0)
			if kmh >= 200.0 or t > 70.0:
				phase = 1
		else:
			car.in_throttle = 0.7
			car.in_steer = sin(tl / 2.4 * TAU) * 0.55 if tl < 2.4 else clampf(_yaw_err(car, 0.0), -1.0, 1.0)
			tl += DT
			max_slip = maxf(max_slip, absf(car.body_slip_deg))
			max_roll = maxf(max_roll, rad_to_deg(acos(clampf(car.global_transform.basis.y.y, -1.0, 1.0))))
			if tl > 6.4:
				break
		await get_tree().physics_frame
		t += DT
		if car.global_position.z < -4500.0:
			var xf := car.global_transform
			xf.origin.z += 9000.0
			car.global_transform = xf
	var res := {"t_0_100": snappedf(t100, 0.01), "top_reached_kmh": snappedf(vmax, 0.1), "lane_change_max_slip_deg": snappedf(max_slip, 0.1),
		"lane_change_max_roll_deg": snappedf(max_roll, 0.1), "flipped": car.global_transform.basis.y.y < 0.3}
	car.queue_free()
	return res
