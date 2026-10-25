extends Node
## Scenario runner for tools/drive_test.gd. Each scenario spawns a fresh car on the TestTrack,
## drives it with scripted inputs and records measurements.

const DT := 1.0 / 120.0
var track: TestTrack
var results: Array = []
var args: Dictionary = {}


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := String(a).trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	track = TestTrack.new()
	add_child(track)
	_run.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _spawn(def: CarDefinition, pos: Vector3, yaw: float = 0.0) -> CarController:
	var car := CarFactory.build(def, def.default_color, def.default_finish)
	car.control_mode = CarController.ControlMode.AI
	add_child(car)
	car.global_transform = Transform3D(Basis(Vector3.UP, yaw), pos + Vector3(0, 0.3, 0))
	await _frames(90)
	return car


func _kill(n: Node) -> void:
	n.queue_free()
	await _frames(2)


func _run() -> void:
	var defs: Array[CarDefinition] = []
	var dir := "res://data/cars/"
	var files := DirAccess.get_files_at(dir)
	var pick: Array[int] = []
	if args.has("cars"):
		for s in String(args["cars"]).split(","):
			pick.append(int(s))
	var idx := 0
	for f in files:
		if not f.ends_with(".tres"):
			continue
		idx += 1
		if pick.is_empty() or pick.has(idx):
			defs.append(load(dir + f) as CarDefinition)
	var quick := args.has("quick")
	for def in defs:
		var r := {"id": String(def.id), "name": def.display_name}
		print("--- ", def.display_name)
		var acc := await _test_accel(def, Vector3(-1500.0, 0.0, 5500.0), quick)
		r.merge(acc)
		r["brake_100_0_m"] = await _test_brake(def)
		if not quick:
			r["skidpad_g"] = await _test_skidpad(def)
			r.merge(await _test_lane_change(def, float(r.get("top_speed_kmh", 200.0))))
			r.merge(await _test_jump(def))
			r["gravel_0_100_s"] = (await _test_accel(def, Vector3(TestTrack.PAD_GRAVEL_X, 0.05, 600.0), true)).get("0_100_s", -1.0)
			r.merge(await _test_drift(def))
		print("    ", r)
		results.append(r)
	if args.has("proto"):
		results.append(await _proto_vehicle_body())
	_report()
	get_tree().quit()


# ------------------------------------------------------------------------------------------------
func _test_accel(def: CarDefinition, pos: Vector3, short: bool) -> Dictionary:
	var car := await _spawn(def, pos)
	var t := 0.0
	var t100 := -1.0
	var t200 := -1.0
	var t_quarter := -1.0
	var start := car.global_position
	var vmax := 0.0
	var last_gain_t := 0.0
	var limit := 25.0 if short else 150.0
	car.input_throttle = 1.0
	while t < limit:
		await get_tree().physics_frame
		t += DT
		var v := car.speed_kmh
		if v > vmax + 0.05:
			vmax = v
			last_gain_t = t
		if t100 < 0.0 and v >= 100.0:
			t100 = t
		if t200 < 0.0 and v >= 200.0:
			t200 = t
		if t_quarter < 0.0 and car.global_position.distance_to(start) >= 402.3:
			t_quarter = t
		if args.has("trace") and int(t * 120.0) % 30 == 0:
			var sl := ""
			for w in car.wheels:
				sl += "%.2f/%.2f " % [w.slip_ratio, rad_to_deg(w.slip_angle)]
			print("  t=%.2f v=%.1f g=%d rpm=%d thr=%.2f tcs=%.2f esc=%.2f beta=%.1f yaw=%.2f slips=%s" % [t, v, car.gear, car.rpm, car.throttle_effective, car.tcs_factor, car.esc_throttle, car.body_slip_deg, car.angular_velocity.y, sl])
		if short and t100 > 0.0:
			break
		if not short and t - last_gain_t > 6.0 and t > 20.0:
			break
	var res := {"0_100_s": snappedf(t100, 0.01), "0_200_s": snappedf(t200, 0.01), "quarter_mile_s": snappedf(t_quarter, 0.01),
		"top_speed_kmh": snappedf(vmax, 0.1)}
	await _kill(car)
	return res


func _test_brake(def: CarDefinition) -> float:
	var car := await _spawn(def, Vector3(0, 0, 3000))
	car.input_throttle = 1.0
	while car.speed_kmh < 108.0:
		await get_tree().physics_frame
	car.input_throttle = 0.0
	car.input_brake = 1.0
	var p0 := Vector3.ZERO
	var started := false
	var guard := 0.0
	while car.speed_kmh > 0.5 and guard < 20.0:
		await get_tree().physics_frame
		guard += DT
		if not started and car.speed_kmh <= 100.0:
			started = true
			p0 = car.global_position
	var dist := car.global_position.distance_to(p0) if started else -1.0
	await _kill(car)
	return snappedf(dist, 0.1)


func _test_skidpad(def: CarDefinition) -> float:
	var radius := 60.0
	var car := await _spawn(def, Vector3(-3000, 0, 0))
	var center := car.global_position + Vector3(radius, 0, 0)
	var target_kmh := 30.0
	var best_g := 0.0
	var stable_t := 0.0
	var off_t := 0.0
	var t := 0.0
	while t < 90.0:
		await get_tree().physics_frame
		t += DT
		var p := car.global_position
		var to_c := Vector3(center.x - p.x, 0, center.z - p.z)
		var dist := to_c.length()
		var err := dist - radius
		# pure pursuit to a point ahead on the circle (clockwise from above)
		var ang := atan2(p.z - center.z, p.x - center.x)
		var v := maxf(car.forward_speed, 1.0)
		var look := 10.0 + v * 0.45
		var ang2 := ang + look / radius
		var tgt := center + Vector3(cos(ang2) * radius, 0, sin(ang2) * radius)
		var local := car.global_transform.affine_inverse() * tgt
		var alpha := atan2(local.x, -local.z)
		var wheelbase := 2.6
		var steer_rad := atan(2.0 * wheelbase * sin(alpha) / look)
		var lock := lerpf(def.steer_lock_deg, def.steer_high_speed_deg, pow(clampf(absf(car.forward_speed) / 55.0, 0.0, 1.0), 0.75))
		car.input_steer = clampf(rad_to_deg(steer_rad) / lock, -1.0, 1.0)
		target_kmh += DT * 0.6
		var spd_err := target_kmh - car.speed_kmh
		car.input_throttle = clampf(spd_err * 0.15 + 0.25, 0.0, 1.0)
		car.input_brake = clampf(-spd_err * 0.1, 0.0, 1.0)
		if absf(err) < 2.5:
			stable_t += DT
			off_t = 0.0
			if stable_t > 2.0:
				var vv := car.linear_velocity.length()
				best_g = maxf(best_g, vv * vv / (dist * 9.81))
		else:
			stable_t = 0.0
			off_t += DT
			if off_t > 2.0 and t > 10.0:
				break
	await _kill(car)
	return snappedf(best_g, 0.01)


func _test_lane_change(def: CarDefinition, vtop: float) -> Dictionary:
	var target := minf(250.0, vtop * 0.93)
	var car := await _spawn(def, Vector3(2000, 0, 5500))
	car.input_throttle = 1.0
	var guard := 0.0
	while car.speed_kmh < target and guard < 120.0:
		await get_tree().physics_frame
		guard += DT
	var v0 := car.speed_kmh
	var max_slip := 0.0
	var max_yaw := 0.0
	var t := 0.0
	car.input_throttle = 0.6
	while t < 6.0:
		await get_tree().physics_frame
		t += DT
		var s := 0.0
		if t < 0.7:
			s = 0.4
		elif t < 1.4:
			s = -0.4
		car.input_steer = s
		max_slip = maxf(max_slip, absf(car.body_slip_deg))
		max_yaw = maxf(max_yaw, absf(car.angular_velocity.y))
	var stable := max_slip < 12.0 and car.global_transform.basis.y.dot(Vector3.UP) > 0.9
	var res := {"lane_change_kmh": snappedf(v0, 1.0), "lane_change_max_slip_deg": snappedf(max_slip, 0.1),
		"lane_change_max_yaw_rad_s": snappedf(max_yaw, 0.01), "lane_change_stable": stable}
	await _kill(car)
	return res


func _test_jump(def: CarDefinition) -> Dictionary:
	var start := TestTrack.RAMP_POS + Vector3(0, 0, 450)
	var car := await _spawn(def, start)
	var target := 110.0
	var t := 0.0
	var air := 0.0
	var max_air := 0.0
	var takeoff := Vector3.ZERO
	var landing := Vector3.ZERO
	var was_air := false
	var landed := false
	var max_tilt_after := 0.0
	var after_t := 0.0
	while t < 40.0:
		await get_tree().physics_frame
		t += DT
		var spd_err := target - car.speed_kmh
		car.input_throttle = clampf(spd_err * 0.2, 0.0, 1.0) if not was_air else 0.0
		car.input_steer = clampf(-car.global_position.x * 0.05, -0.3, 0.3)
		if car.grounded_wheels == 0 and car.global_position.z < TestTrack.RAMP_POS.z + 15.0:
			if not was_air:
				takeoff = car.global_position
			was_air = true
			air += DT
			max_air = maxf(max_air, air)
		elif was_air and car.grounded_wheels >= 2 and not landed:
			landed = true
			landing = car.global_position
		if landed:
			after_t += DT
			var up := car.global_transform.basis.y
			max_tilt_after = maxf(max_tilt_after, rad_to_deg(acos(clampf(up.dot(Vector3.UP), -1.0, 1.0))))
			if after_t > 2.5:
				break
	var res := {"jump_airtime_s": snappedf(max_air, 0.01), "jump_distance_m": snappedf(Vector2(landing.x - takeoff.x, landing.z - takeoff.z).length(), 0.1),
		"jump_max_tilt_after_deg": snappedf(max_tilt_after, 0.1), "jump_ok": landed and max_tilt_after < 25.0}
	await _kill(car)
	return res


func _test_drift(def: CarDefinition) -> Dictionary:
	var car := await _spawn(def, Vector3(-2000, 0, -2000))
	car.input_throttle = 1.0
	var guard := 0.0
	while car.speed_kmh < 85.0 and guard < 30.0:
		await get_tree().physics_frame
		guard += DT
	var t := 0.0
	var max_slip := 0.0
	var spun := false
	while t < 6.0:
		await get_tree().physics_frame
		t += DT
		if t < 0.55:
			car.input_steer = 0.8
			car.input_handbrake = 1.0
			car.input_throttle = 0.5
		else:
			car.input_handbrake = 0.0
			car.input_throttle = 0.65
			# counter-steer proportional to slip (simple driver model)
			car.input_steer = clampf(car.body_slip_deg / 25.0, -1.0, 1.0)
		max_slip = maxf(max_slip, absf(car.body_slip_deg))
		if absf(car.body_slip_deg) > 85.0:
			spun = true
	var res := {"drift_max_slip_deg": snappedf(max_slip, 0.1), "drift_spun": spun,
		"drift_recovered": absf(car.body_slip_deg) < 12.0}
	await _kill(car)
	return res


# ------------------------------------------------------------------------------------------------
func _proto_vehicle_body() -> Dictionary:
	## Godot built-in VehicleBody3D configured like the hot hatch, for comparison.
	var def := load("res://data/cars/01_pico_furia.tres") as CarDefinition
	var out := {"id": "proto_vehiclebody3d", "name": "VehicleBody3D prototype (hatch-like)"}
	var r := await _proto_run(def, "accel")
	out.merge(r)
	out["brake_100_0_m"] = (await _proto_run(def, "brake")).get("brake", -1.0)
	out.merge(await _proto_run(def, "lane"))
	return out


func _proto_make(def: CarDefinition, pos: Vector3) -> VehicleBody3D:
	var vb := VehicleBody3D.new()
	vb.mass = def.mass
	vb.center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	vb.center_of_mass = Vector3(0, 0.45, -0.18)
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.75, 0.6, 4.0)
	cs.shape = box
	cs.position = Vector3(0, 0.75, 0)
	vb.add_child(cs)
	var positions := [Vector3(-0.76, 0.31, -1.27), Vector3(0.76, 0.31, -1.27), Vector3(-0.76, 0.31, 1.27), Vector3(0.76, 0.31, 1.27)]
	for i in 4:
		var w := VehicleWheel3D.new()
		w.position = positions[i] + Vector3(0, 0.1, 0)
		w.wheel_radius = 0.31
		w.wheel_rest_length = 0.15
		w.suspension_travel = 0.2
		w.suspension_stiffness = 45.0
		w.damping_compression = 2.5
		w.damping_relaxation = 3.5
		w.wheel_friction_slip = 2.4
		w.wheel_roll_influence = 0.15
		w.suspension_max_force = 20000.0
		w.use_as_steering = i < 2
		w.use_as_traction = i < 2
		vb.add_child(w)
	add_child(vb)
	vb.global_position = pos + Vector3(0, 0.4, 0)
	return vb


func _proto_run(def: CarDefinition, mode: String) -> Dictionary:
	var pos := Vector3(4000, 0, 4000) if mode != "lane" else Vector3(-4000, 0, 5500)
	var vb := _proto_make(def, pos)
	await _frames(90)
	var gear := 1
	var t := 0.0
	var t100 := -1.0
	var vmax := 0.0
	var res := {}
	var max_slip := 0.0
	var phase := 0
	var p0 := Vector3.ZERO
	var lane_t := 0.0
	var lane_v0 := 0.0
	var spun := false
	while t < 100.0:
		await get_tree().physics_frame
		t += DT
		var v := vb.linear_velocity.length()
		var kmh := v * 3.6
		vmax = maxf(vmax, kmh)
		# simple automatic gearbox using wheel rpm
		var ratio := def.gear_ratios[gear - 1] * def.final_drive
		var rpm := absf(v / 0.31) * ratio * 60.0 / TAU
		if rpm > def.redline_rpm * 0.96 and gear < def.gear_ratios.size():
			gear += 1
		elif gear > 1 and rpm < def.redline_rpm * 0.45:
			gear -= 1
		var norm := clampf((maxf(rpm, def.idle_rpm) - def.idle_rpm) / (def.redline_rpm - def.idle_rpm), 0.0, 1.0)
		var force := def.torque_at(norm) * def.max_torque_nm * ratio * def.drivetrain_efficiency / 0.31
		if rpm > def.redline_rpm:
			force = 0.0
		var fwd := -vb.global_transform.basis.z
		var right := vb.global_transform.basis.x
		var slip := rad_to_deg(atan2(vb.linear_velocity.dot(right), absf(vb.linear_velocity.dot(fwd)))) if v > 3.0 else 0.0
		max_slip = maxf(max_slip, absf(slip)) if phase == 1 else max_slip
		# aero drag like the real model
		vb.apply_central_force(-vb.linear_velocity * v * 0.5 * 1.225 * def.drag_area)
		match mode:
			"accel":
				vb.engine_force = force
				if t100 < 0.0 and kmh >= 100.0:
					t100 = t
				if t > 60.0:
					break
			"brake":
				if phase == 0:
					vb.engine_force = force
					if kmh >= 108.0:
						phase = 1
				else:
					vb.engine_force = 0.0
					vb.brake = 30.0 * def.mass / 1000.0
					if p0 == Vector3.ZERO and kmh <= 100.0:
						p0 = vb.global_position
					if kmh < 0.5:
						res["brake"] = snappedf(vb.global_position.distance_to(p0), 0.1)
						break
			"lane":
				if phase == 0:
					vb.engine_force = force
					if kmh >= minf(200.0, vmax) and t > 5.0 and (kmh >= 200.0 or t > 50.0):
						phase = 1
						lane_v0 = kmh
				else:
					lane_t += DT
					vb.engine_force = force * 0.6
					var s := 0.0
					if lane_t < 0.7:
						s = 0.4
					elif lane_t < 1.4:
						s = -0.4
					vb.steering = deg_to_rad(s * def.steer_high_speed_deg)
					if absf(slip) > 60.0:
						spun = true
					if lane_t > 6.0:
						break
	match mode:
		"accel":
			res = {"0_100_s": snappedf(t100, 0.01), "top_speed_kmh": snappedf(vmax, 0.1)}
		"lane":
			res = {"lane_change_kmh": snappedf(lane_v0, 1.0), "lane_change_max_slip_deg": snappedf(max_slip, 0.1), "lane_change_stable": not spun and max_slip < 12.0}
	vb.queue_free()
	await _frames(2)
	return res


func _report() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://qa_out"))
	var f := FileAccess.open("res://qa_out/drive_tests.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(results, "  "))
	f.close()
	var cols := ["name", "0_100_s", "0_200_s", "quarter_mile_s", "top_speed_kmh", "brake_100_0_m", "skidpad_g",
		"lane_change_kmh", "lane_change_max_slip_deg", "lane_change_stable", "jump_airtime_s", "jump_distance_m", "jump_ok",
		"gravel_0_100_s", "drift_max_slip_deg", "drift_recovered"]
	var line := "| " + " | ".join(cols) + " |"
	print(line)
	print("|" + "---|".repeat(cols.size()))
	for r in results:
		var vals: Array[String] = []
		for c in cols:
			vals.append(str(r.get(c, "")))
		print("| " + " | ".join(vals) + " |")
