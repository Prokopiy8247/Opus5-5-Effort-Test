extends Node3D
## Automated drive tests on a flat proving ground (scripted inputs, fixed 120 Hz).
##   Godot_console.exe --headless --path <project> res://tools/tests/drive_test.tscn --fixed-fps 120 -- --car=all --out=res://qa_output/drive_tests.json
## Tests: 0-100 / 0-200 / top speed, 100-0 braking distance, skidpad lateral g, high-speed lane change,
## jump landing (gear must hold in the air), gravel 0-100, power drift, gearbox regressions (cruise: part-throttle
## upshifts to a relaxed rpm; keyboard: binary-throttle taps / pulses hold a gear without hunting and a floored
## pedal kicks down in one shift; manualq: three quick downshift taps all count; manualprot: downshifts that would
## over-rev are refused; resume: a placement at speed keeps the engine at road speed, no idle-rpm gear hunt;
## reverse / reverse_hill: reverse is speed-limited on the flat and down a 12 % slope). Results printed and written
## as JSON; the gearbox and reverse checks also print "[drive] PASS|FAIL" lines and "[drive] failures: N".

const DT := 1.0 / 120.0

var track: TestTrack
var car: CarController
var results: Dictionary = {}
var _tests: PackedStringArray = ["launch", "brake", "skidpad", "lanechange", "jump", "gravel", "drift", "cruise", "keyboard", "manualq",
	"manualprot", "resume", "reverse", "reverse_hill"]
var _fails := 0


func _ready() -> void:
	track = TestTrack.new()
	add_child(track)
	var sun := DirectionalLight3D.new()
	add_child(sun)
	_run.call_deferred()


func _arg(key: String, default: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--" + key + "="):
			return a.substr(key.length() + 3)
	return default


func _run() -> void:
	var which := _arg("car", "kestrel_r4")
	var only := _arg("tests", "")
	if only != "":
		_tests = only.split(",")
	var ids: Array = Game.CAR_IDS.duplicate() if which == "all" else which.split(",")
	for id: String in ids:
		var r := {}
		print("=== %s ===" % id)
		for t in _tests:
			var res: Dictionary = await call("_test_" + t, id)
			r[t] = res
			print("  %-11s %s" % [t, JSON.stringify(res)])
			if res.has("ok"):
				print("[drive] %s %s %s" % ["PASS" if res["ok"] else "FAIL", id, t])
				if not res["ok"]:
					_fails += 1
		results[id] = r
	var out := _arg("out", "res://qa_output/drive_tests.json")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out.get_base_dir()))
	var f := FileAccess.open(out, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(results, "\t"))
		f.close()
	print("[drive] failures: %d" % _fails)
	print("DRIVE_TEST_DONE wrote ", ProjectSettings.globalize_path(out))
	get_tree().quit(0)


func _spawn(id: String, surface: StringName = &"asphalt", at := Vector3(0, 0.05, 4000.0), heading := 0.0) -> CarController:
	if car != null and is_instance_valid(car):
		car.queue_free()
		await get_tree().physics_frame
	track.set_surface(surface)
	var base: CarData = load("res://data/cars/%s.tres" % id)
	var d: CarData = base.duplicate(true)
	car = CarFactory.build(d, {}, true)
	add_child(car)
	car.place_at(Transform3D(Basis(Vector3.UP, heading), at))
	Game.apply_assists_to(car)
	for i in 90:
		await get_tree().physics_frame
	return car


func _step() -> void:
	await get_tree().physics_frame
	if car != null and car.global_position.z < -4500.0:
		var xf := car.global_transform
		xf.origin.z += 9000.0
		car.global_transform = xf


func _hold_heading(target_yaw: float, gain := 1.6) -> void:
	var f := -car.global_transform.basis.z
	var yaw := atan2(-f.x, -f.z)
	var err := wrapf(yaw - target_yaw, -PI, PI)
	car.in_steer = clampf(err * gain, -1.0, 1.0)


func _test_launch(id: String) -> Dictionary:
	await _spawn(id)
	var t := 0.0
	var t100 := -1.0
	var t200 := -1.0
	var vmax := 0.0
	var last_check := 0.0
	var last_v := 0.0
	var dist_start := car.global_position
	var d400 := -1.0
	while t < 150.0:
		car.in_throttle = 1.0
		car.in_brake = 0.0
		_hold_heading(0.0)
		await _step()
		t += DT
		var kmh := car.get_speed_kmh()
		vmax = maxf(vmax, kmh)
		if t100 < 0.0 and kmh >= 100.0:
			t100 = t
		if t200 < 0.0 and kmh >= 200.0:
			t200 = t
		if d400 < 0.0 and car.global_position.distance_to(dist_start) >= 402.3:
			d400 = t
		if _arg("verbose", "") != "" and fmod(t, 3.0) < DT:
			print("    t=%.1f kmh=%.1f gear=%d rpm=%.0f z=%.0f ground=%d thr=%.2f slip=%.2f" % [t, kmh, car.gear, car.rpm, car.global_position.z, car.wheels_on_ground, car.throttle_applied, car.body_slip_deg])
		if t - last_check >= 6.0:
			if kmh - last_v < 0.4 and t > 20.0:
				break
			last_v = kmh
			last_check = t
	car.in_throttle = 0.0
	return {"t_0_100": snappedf(t100, 0.01), "t_0_200": snappedf(t200, 0.01), "quarter_mile_s": snappedf(d400, 0.01), "top_speed_kmh": snappedf(vmax, 0.1), "gear": car.gear}


func _test_brake(id: String) -> Dictionary:
	await _spawn(id)
	var t := 0.0
	while car.get_speed_kmh() < 101.0 and t < 40.0:
		car.in_throttle = 1.0
		_hold_heading(0.0)
		await _step()
		t += DT
	car.in_throttle = 0.0
	var start := car.global_position
	var tb := 0.0
	var max_slip := 0.0
	while car.get_speed_kmh() > 0.5 and tb < 15.0:
		car.in_brake = 1.0
		_hold_heading(0.0)
		await _step()
		tb += DT
		max_slip = maxf(max_slip, absf(car.body_slip_deg))
	car.in_brake = 0.0
	return {"dist_100_0_m": snappedf(start.distance_to(car.global_position), 0.1), "time_s": snappedf(tb, 0.01), "max_body_slip_deg": snappedf(max_slip, 0.1)}


func _test_skidpad(id: String) -> Dictionary:
	# Follow a 60 m radius circle with ramping target speed; record sustained lateral g.
	var radius := 60.0
	var center := Vector3(0, 0, 0)
	await _spawn(id, &"asphalt", center + Vector3(radius, 0.05, 0), 0.0)
	var t := 0.0
	var best_g := 0.0
	var target_kmh := 30.0
	var g_window: Array[float] = []
	while t < 70.0:
		var p := car.global_position
		var rel := Vector3(p.x - center.x, 0, p.z - center.z)
		var r := rel.length()
		# Tangent for counter-clockwise travel seen from above (turning left).
		var tangent := Vector3(-rel.z, 0, rel.x).normalized() * -1.0
		var aim := (center + rel.normalized() * radius + tangent * 12.0) - p
		aim.y = 0.0
		var f := -car.global_transform.basis.z
		f.y = 0.0
		var ang := f.signed_angle_to(aim.normalized(), Vector3.UP)
		car.in_steer = clampf(-ang * 2.2 + (r - radius) * -0.02, -1.0, 1.0)
		target_kmh = minf(30.0 + t * 1.6, 160.0)
		var v := car.get_speed_kmh()
		car.in_throttle = clampf((target_kmh - v) * 0.15, 0.0, 1.0)
		car.in_brake = clampf((v - target_kmh - 3.0) * 0.1, 0.0, 1.0)
		await _step()
		t += DT
		var g := absf(car.lateral_g)
		if absf(r - radius) < 4.0:
			g_window.append(g)
			if g_window.size() > 240:
				g_window.pop_front()
			if g_window.size() == 240:
				var avg := 0.0
				for x in g_window:
					avg += x
				best_g = maxf(best_g, avg / 240.0)
	return {"lateral_g": snappedf(best_g, 0.01), "radius_m": radius}


func _test_lanechange(id: String) -> Dictionary:
	await _spawn(id)
	var t := 0.0
	var top: float = minf(200.0, load("res://data/cars/%s.tres" % id).top_speed_kmh * 0.85)
	while car.get_speed_kmh() < top and t < 60.0:
		car.in_throttle = 1.0
		_hold_heading(0.0)
		await _step()
		t += DT
	var v0 := car.get_speed_kmh()
	var max_slip := 0.0
	var max_roll := 0.0
	var tl := 0.0
	# Double lane change: steer sine for 2.4 s, then hold straight 4 s.
	while tl < 6.4:
		car.in_throttle = 0.7
		if tl < 2.4:
			car.in_steer = sin(tl / 2.4 * TAU) * 0.55
		else:
			_hold_heading(0.0, 1.0)
		await _step()
		tl += DT
		max_slip = maxf(max_slip, absf(car.body_slip_deg))
		var up := car.global_transform.basis.y
		max_roll = maxf(max_roll, rad_to_deg(acos(clampf(up.y, -1.0, 1.0))))
	var f := -car.global_transform.basis.z
	var final_yaw_dev := rad_to_deg(absf(atan2(-f.x, -f.z)))
	return {"entry_kmh": snappedf(v0, 0.1), "max_body_slip_deg": snappedf(max_slip, 0.1), "max_roll_deg": snappedf(max_roll, 0.1),
		"final_heading_dev_deg": snappedf(final_yaw_dev, 0.1), "stable": max_slip < 12.0 and final_yaw_dev < 20.0}


func _test_jump(id: String) -> Dictionary:
	await _spawn(id, &"asphalt", Vector3(0, 0.05, 3000.0))
	track.add_ramp(Vector3(0, 0, 2700.0), 14.0, 2.6, 10.0)
	var t := 0.0
	while car.global_position.z > 2720.0 and t < 40.0:
		var v := car.get_speed_kmh()
		car.in_throttle = clampf((110.0 - v) * 0.2, 0.0, 1.0)
		car.in_brake = clampf((v - 115.0) * 0.1, 0.0, 1.0)
		_hold_heading(0.0)
		await _step()
		t += DT
	var takeoff := car.global_position
	var air := 0.0
	var airborne := false
	var land_t := -1.0
	var max_tilt_after := 0.0
	var tt := 0.0
	var landed_pos := Vector3.ZERO
	var takeoff_gear := car.gear
	var air_shifts := 0
	var g_prev := car.gear
	while tt < 8.0:
		car.in_throttle = 0.3
		_hold_heading(0.0, 1.0)
		await _step()
		tt += DT
		if car.wheels_on_ground == 0:
			airborne = true
			air += DT
			if car.gear != g_prev:
				air_shifts += 1
		elif airborne and land_t < 0.0:
			land_t = tt
			landed_pos = car.global_position
		g_prev = car.gear
		if land_t > 0.0:
			var up := car.global_transform.basis.y
			max_tilt_after = maxf(max_tilt_after, rad_to_deg(acos(clampf(up.y, -1.0, 1.0))))
	var upright := car.global_transform.basis.y.y > 0.9 and car.wheels_on_ground >= 3
	track.clear_ramps()
	return {"air_time_s": snappedf(air, 0.01), "jump_dist_m": snappedf(Vector2(landed_pos.x - takeoff.x, landed_pos.z - takeoff.z).length(), 0.1),
		"max_tilt_after_landing_deg": snappedf(max_tilt_after, 0.1), "upright_after": upright, "damage": snappedf(car.damage, 0.01),
		"takeoff_gear": takeoff_gear, "air_gear_changes": air_shifts}


func _test_gravel(id: String) -> Dictionary:
	await _spawn(id, &"gravel")
	var t := 0.0
	var t100 := -1.0
	var t60 := -1.0
	while t < 30.0 and t100 < 0.0:
		car.in_throttle = 1.0
		_hold_heading(0.0)
		await _step()
		t += DT
		var kmh := car.get_speed_kmh()
		if t60 < 0.0 and kmh >= 60.0:
			t60 = t
		if kmh >= 100.0:
			t100 = t
	return {"t_0_60": snappedf(t60, 0.01), "t_0_100": snappedf(t100, 0.01)}


func _test_drift(id: String) -> Dictionary:
	# Skilled-driver drift: initiate with handbrake, then hold ~30 deg body slip with counter-steer
	# and throttle modulation. Measures how long the drift is sustained and whether it stays catchable.
	await _spawn(id)
	Game.apply_assists_to(car)
	car.assist_stm = false
	car.assist_tcs = false
	var t := 0.0
	while car.get_speed_kmh() < 75.0 and t < 20.0:
		car.in_throttle = 1.0
		_hold_heading(0.0)
		await _step()
		t += DT
	var max_slip := 0.0
	var in_band := 0.0
	var td := 0.0
	var spun := false
	while td < 6.0:
		var slip := car.body_slip_deg
		if td < 0.5:
			car.in_steer = -1.0
			car.in_handbrake = 1.0 if td < 0.3 else 0.0
			car.in_throttle = 1.0
		else:
			car.in_handbrake = 0.0
			# slip > 0 when the tail is out to the right during this left-hand drift.
			car.in_steer = clampf((slip - 30.0) * 0.045 + 0.15, -1.0, 1.0)
			car.in_throttle = clampf(0.75 + (30.0 - slip) * 0.03, 0.15, 1.0)
		await _step()
		td += DT
		max_slip = maxf(max_slip, absf(slip))
		if absf(slip) > 15.0 and absf(slip) < 55.0 and car.forward_speed > 5.0:
			in_band += DT
		if absf(slip) > 100.0 or car.forward_speed < 0.0:
			spun = true
	var tr := 0.0
	while tr < 3.0:
		car.in_throttle = 0.25
		car.in_steer = clampf(car.body_slip_deg * 0.05, -1.0, 1.0)
		await _step()
		tr += DT
	var recovered := absf(car.body_slip_deg) < 10.0 and car.forward_speed > 3.0
	return {"max_body_slip_deg": snappedf(max_slip, 0.1), "drift_hold_s": snappedf(in_band, 0.01), "spun": spun, "recovered": recovered, "end_kmh": snappedf(car.get_speed_kmh(), 0.1)}


func _test_cruise(id: String) -> Dictionary:
	# Gentle acceleration to 80 km/h, then hold it with a light, smooth pedal: the automatic gearbox should
	# short-shift to a relaxed rpm instead of holding a low gear near the redline.
	await _spawn(id)
	var t := 0.0
	while car.get_speed_kmh() < 78.0 and t < 40.0:
		car.in_throttle = 0.35
		_hold_heading(0.0)
		await _step()
		t += DT
	var integ := 0.2
	var changes := 0
	var g0 := car.gear
	var rpm_max := 0.0
	var tc := 0.0
	while tc < 10.0:
		var err := 80.0 - car.get_speed_kmh()
		integ = clampf(integ + err * 0.002, 0.0, 0.7)
		car.in_throttle = move_toward(car.in_throttle, clampf(err * 0.04 + integ, 0.0, 1.0), DT * 0.8)
		_hold_heading(0.0)
		await _step()
		tc += DT
		if _arg("verbose", "") != "" and fmod(tc, 0.5) < DT:
			print("    cruise t=%.1f kmh=%.1f gear=%d rpm=%.0f thr=%.2f" % [tc, car.get_speed_kmh(), car.gear, car.rpm, car.in_throttle])
		if tc > 3.0:
			rpm_max = maxf(rpm_max, car.rpm)
			if car.gear != g0:
				changes += 1
		g0 = car.gear
	car.in_throttle = 0.0
	return {"kmh": snappedf(car.get_speed_kmh(), 0.1), "gear": car.gear, "gears": car.data.gear_ratios.size(),
		"rpm_max_pct_redline": snappedf(rpm_max / car.data.redline_rpm * 100.0, 0.1), "gear_changes_last_7s": changes}


## Keyboard throttle (binary W through CarInput's ramp): tapping to hold 100 km/h and 0.5 s / 1.0 s pulses must
## not hunt or sit near the redline; flooring from a steady analog part throttle kicks down in one shift.
func _test_keyboard(id: String) -> Dictionary:
	await _spawn(id)
	var w_down := false
	var thr := 0.0
	var t := 0.0
	while car.get_speed_kmh() < 95.0 and t < 40.0:
		thr = move_toward(thr, 1.0, DT * 6.0)
		car.in_throttle = thr
		_hold_heading(0.0)
		await _step()
		t += DT
	var res := {}
	for pattern: String in ["hold", "pulse"]:
		var shifts := 0
		var rpm_sum := 0.0
		var n := 0
		var g0 := car.gear
		var tp := 0.0
		while tp < 20.0:
			var kmh := car.get_speed_kmh()
			if pattern == "hold":
				w_down = (kmh < 97.0) or (w_down and kmh < 103.0)
			else:
				w_down = fmod(tp, 1.5) < 0.5
			thr = move_toward(thr, 1.0 if w_down else 0.0, DT * (6.0 if w_down else 10.0))
			car.in_throttle = thr
			_hold_heading(0.0)
			await _step()
			tp += DT
			if tp > 4.0:
				rpm_sum += car.rpm / car.data.redline_rpm
				n += 1
				if car.gear != g0:
					shifts += 1
			g0 = car.gear
		res[pattern + "_shifts"] = shifts
		res[pattern + "_rpm_pct"] = snappedf(rpm_sum / maxi(n, 1) * 100.0, 0.1)
		res[pattern + "_gear"] = car.gear
		res[pattern + "_kmh"] = snappedf(car.get_speed_kmh(), 0.1)
	# Analog kick-down: steady part throttle at 80 km/h, then floor it.
	await _spawn(id)
	t = 0.0
	while car.get_speed_kmh() < 78.0 and t < 40.0:
		car.in_throttle = 0.35
		_hold_heading(0.0)
		await _step()
		t += DT
	var integ := 0.2
	var tc := 0.0
	while tc < 8.0:
		var err := 80.0 - car.get_speed_kmh()
		integ = clampf(integ + err * 0.002, 0.0, 0.7)
		car.in_throttle = clampf(err * 0.03 + integ, 0.05, 0.6)
		_hold_heading(0.0)
		await _step()
		tc += DT
	# A steady part throttle just before flooring it (the analog kick-down case).
	for i in 72:
		car.in_throttle = 0.3
		_hold_heading(0.0)
		await _step()
	var from := car.gear
	var downs := 0
	var cut := 0.0
	var g1 := car.gear
	var v0 := car.forward_speed
	for i in 120:
		car.in_throttle = 1.0
		_hold_heading(0.0)
		await _step()
		if car.gear < g1:
			downs += 1
		g1 = car.gear
		if car.shifting:
			cut += DT
	res["kick_from"] = from
	res["kick_to"] = car.gear
	res["kick_downshifts_1s"] = downs
	res["kick_cut_s"] = snappedf(cut, 0.01)
	res["kick_gain_1s_ms"] = snappedf(car.forward_speed - v0, 0.01)
	car.in_throttle = 0.0
	return res


func _test_manualq(id: String) -> Dictionary:
	# Manual gearbox: up to 4th (or the top gear), slow down until three gears lower stays below the redline
	# (over-rev protection refuses anything faster), then three downshift taps 33 ms apart (one-frame requests,
	# like CarInput): every tap must count.
	await _spawn(id)
	car.auto_gearbox = false
	var top := mini(4, car.data.gear_ratios.size())
	var t := 0.0
	while car.gear < top and t < 40.0:
		car.in_throttle = 1.0
		if car.rpm > car.data.redline_rpm * 0.92 and not car.shifting:
			car.in_shift_up = true
		_hold_heading(0.0)
		await _step()
		t += DT
	car.in_throttle = 0.0
	var before := car.gear
	var target := maxi(before - 3, 1)
	t = 0.0
	while car._road_rpm(target) > car.data.redline_rpm * 0.85 and t < 20.0:
		car.in_brake = 0.6
		_hold_heading(0.0)
		await _step()
		t += DT
	car.in_brake = 0.0
	var kmh := car.get_speed_kmh()
	for i in 12:
		if i % 4 == 0:
			car.in_shift_down = true
		_hold_heading(0.0)
		await _step()
	for i in 96:
		_hold_heading(0.0)
		await _step()
	return {"from_gear": before, "gear": car.gear, "expected": target, "kmh_at_taps": snappedf(kmh, 0.1), "ok": car.gear == target}


## Manual over-rev protection (playtest 3 s17): in top gear at 190 km/h (85 % of the top speed on slower cars),
## 0.6 s on the throttle, then four downshift taps 0.12 s apart and lift: only the downshifts that keep the engine
## at or below the redline are taken, the rest are refused, and the engine never reaches the limiter. Slowed
## down, a further tap is accepted again.
func _test_manualprot(id: String) -> Dictionary:
	await _spawn(id)
	car.auto_gearbox = false
	var n := car.data.gear_ratios.size()
	var kmh := minf(190.0, car.data.top_speed_kmh * 0.85)
	car.place_at(car.global_transform, -car.global_transform.basis.z * kmh / 3.6, Vector3.ZERO, n)
	var refused: Array[int] = []
	var on_refused := func(g: int) -> void: refused.append(g)
	car.shift_refused.connect(on_refused)
	for i in 72:
		car.in_throttle = 1.0
		_hold_heading(0.0)
		await _step()
	var kmh_taps := car.get_speed_kmh()
	# The lowest gear the taps may reach: road-speed rpm at or below the redline at the moment of the taps.
	var safe := car.gear
	while safe > 1 and car._road_rpm(safe - 1) <= car.data.redline_rpm:
		safe -= 1
	var expected := maxi(n - 4, safe)
	var rpm_max := 0.0
	var road_pct_max := 0.0
	var limiter := 0
	for i in 144:
		car.in_throttle = 0.0
		if i % 14 == 0 and i < 56:
			car.in_shift_down = true
		_hold_heading(0.0)
		await _step()
		rpm_max = maxf(rpm_max, car.rpm)
		road_pct_max = maxf(road_pct_max, car._road_rpm(car.gear) / car.data.redline_rpm * 100.0)
		if car.limiter_hit:
			limiter += 1
	var gear_fast := car.gear
	# Slow down until one gear lower is safe, then tap once more: accepted.
	var t := 0.0
	while gear_fast > 1 and car._road_rpm(gear_fast - 1) > car.data.redline_rpm * 0.9 and t < 20.0:
		car.in_brake = 0.6
		_hold_heading(0.0)
		await _step()
		t += DT
	car.in_brake = 0.0
	var kmh_slow := car.get_speed_kmh()
	car.in_shift_down = true
	for i in 60:
		_hold_heading(0.0)
		await _step()
	car.shift_refused.disconnect(on_refused)
	var later_ok := gear_fast == 1 or car.gear == gear_fast - 1
	var ok := gear_fast == expected and limiter == 0 and road_pct_max <= 101.0 and later_ok \
		and (refused.size() > 0) == (n - 4 < safe)
	return {"kmh_at_taps": snappedf(kmh_taps, 0.1), "from_gear": n, "gear_after_taps": gear_fast, "expected": expected,
		"refused": refused.size(), "rpm_max": snappedf(rpm_max, 1.0), "max_rpm": car.data.max_rpm,
		"road_rpm_pct_redline_max": snappedf(road_pct_max, 0.1), "limiter_frames": limiter,
		"tap_at_kmh": snappedf(kmh_slow, 0.1), "gear_after_slow_tap": car.gear, "ok": ok}


## Reverse speed limit (playtest 3 s18): from a stop, hold the brake: reverse engages and the car settles at its
## reverse limit (CarData.reverse_max_kmh, 25-35 km/h) instead of reverse gear's rev limiter (51-96 km/h before).
func _test_reverse(id: String) -> Dictionary:
	await _spawn(id)
	return await _reverse_run(5.0)


## Reverse down a 12 % slope with the brake held: the limiter holds the speed close to the limit (service brakes
## help when gravity alone would run past it).
func _test_reverse_hill(id: String) -> Dictionary:
	track.rotation.x = atan(0.12)
	# Facing uphill (-z is up the slope), so reverse runs downhill.
	await _spawn(id, &"asphalt", Vector3(0, 1.0, 0))
	var res := await _reverse_run(8.0)
	track.rotation.x = 0.0
	return res


func _reverse_run(margin: float) -> Dictionary:
	var start := car.global_position
	var t := 0.0
	var t_rev := -1.0
	var vmax := 0.0
	var v_sum := 0.0
	var v_n := 0
	while t < 8.0:
		car.in_brake = 1.0
		car.in_throttle = 0.0
		car.in_steer = 0.0
		await _step()
		t += DT
		if car.gear == -1 and t_rev < 0.0:
			t_rev = t
		var back := -car.forward_speed * 3.6
		vmax = maxf(vmax, back)
		if t > 6.0:
			v_sum += back
			v_n += 1
	car.in_brake = 0.0
	var cap := car.data.reverse_max_kmh
	var v_end := v_sum / maxi(v_n, 1)
	var ok := t_rev >= 0.0 and vmax <= cap + margin and v_end >= cap - 3.0
	return {"reverse_after_s": snappedf(t_rev, 0.01), "limit_kmh": cap, "max_kmh": snappedf(vmax, 0.1),
		"avg_kmh_6_8s": snappedf(v_end, 0.1), "rpm": snappedf(car.rpm, 1.0), "dist_m": snappedf(start.distance_to(car.global_position), 0.1),
		"ok": ok}


func _test_resume(id: String) -> Dictionary:
	# Placement at speed (rewind release / rebuild): wheels and engine must resume at road speed in the given gear.
	await _spawn(id)
	var f := -car.global_transform.basis.z
	car.place_at(car.global_transform, f * 27.0, Vector3.ZERO, 3)
	var rpm0 := car.rpm
	var changes := 0
	var g0 := car.gear
	var rpm_min := INF
	for i in 120:
		car.in_throttle = 0.0
		_hold_heading(0.0)
		await _step()
		rpm_min = minf(rpm_min, car.rpm)
		if car.gear != g0:
			changes += 1
		g0 = car.gear
	return {"rpm_at_resume": snappedf(rpm0, 1.0), "rpm_min_1s": snappedf(rpm_min, 1.0), "idle_rpm": car.data.idle_rpm, "gear_changes_1s": changes, "gear": car.gear}
