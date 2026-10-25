extends Node3D
## Automated drive tests (run headless):
##   Godot_console --headless --path . res://scenes/dev/drive_test.tscn -- [car_id|all] [--assists-off]
## Measures 0-100 km/h, 0-200, top speed (60 s flat out), 100-0 braking distance,
## skidpad lateral g, high-speed lane change stability, jump landing, gravel/sand traction.

var ground: TestGround
var car: Car
var results := []
var _cars_to_test: Array[CarSpec] = []
var _log_lines: PackedStringArray = []
var _upgraded := false


func _ready() -> void:
	ground = TestGround.new()
	add_child(ground)
	var args := OS.get_cmdline_user_args()
	var which := "all"
	for a in args:
		if a == "--upgraded":
			_upgraded = true
		elif a == "--wet":
			Game.weather_grip = 0.78
			Game.wetness = 1.0
		elif a == "--assists-off":
			for k in ["tcs", "stm", "abs", "steer"]:
				Game.assists[k] = false
		elif not a.begins_with("--"):
			which = a
	for c in Game.cars:
		if which == "all" or c.id == which:
			_cars_to_test.append(c)
	_run_all.call_deferred()


func _spawn(spec: CarSpec, pos: Vector3, heading_deg: float = 0.0) -> Car:
	if car:
		car.queue_free()
		await get_tree().physics_frame
	car = Car.new()
	if _upgraded:
		var c := Game.custom_for(spec.id)
		c["upgrades"] = {"engine": 3, "tires": 3, "suspension": 3, "brakes": 3, "weight": 3, "aero": 3}
	car.setup(spec, true)
	if _upgraded:
		Tuning.apply(car)
	car.external_input = true
	if OS.get_cmdline_user_args().has("--verbose"):
		car.gear_changed.connect(func(g: int) -> void: _log("   shift->%d rpm=%.0f kmh=%.1f ground=%d" % [g, car.rpm, car.forward_speed * 3.6, car.wheels_on_ground]))
	add_child(car)
	car.teleport(Transform3D(Basis(Vector3.UP, deg_to_rad(heading_deg)), pos + Vector3.UP * 0.4))
	await _frames(150)
	if OS.get_cmdline_user_args().has("--verbose"):
		for w in car.wheels:
			_log("  wheel %s r=%.3f rest=%s mount=%s contact=%s comp=%.3f load=%.0f" % [w.name, w.radius, w.rest_pos, w.mount, w.contact, w.compression, w.load])
		var sl := 0.0
		for w in car.wheels:
			sl += w.load
		_log("  loadsum=%.0f weight=%.0f vy=%.3f" % [sl, car.mass * 9.8 * car.gravity_scale, car.linear_velocity.y])
		_log("  mass=%.0f inertia=%s final=%.2f drag=%.3f pos=%s aabb=%s" % [car.mass, car.inertia, car.final_drive, car.drag_area, car.global_position, car._body_aabb])
	return car


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _set_in(t: float, b: float, s: float, hb: float = 0.0) -> void:
	car.in_throttle = t
	car.in_brake = b
	car.in_steer = s
	car.in_handbrake = hb


func _log(s: String) -> void:
	print(s)
	_log_lines.append(s)


func _run_all() -> void:
	Engine.time_scale = 1.0
	for spec in _cars_to_test:
		await _test_car(spec)
	var path := "user://drive_tests.txt"
	var fa := FileAccess.open(path, FileAccess.WRITE)
	fa.store_string("\n".join(_log_lines))
	_log("DRIVE TESTS DONE -> " + ProjectSettings.globalize_path(path))
	get_tree().quit()


func _test_car(spec: CarSpec) -> void:
	var r := {"car": spec.id}
	var dt := 1.0 / Engine.physics_ticks_per_second
	# --- acceleration + top speed
	await _spawn(spec, Vector3(0, 0, 1400))
	var t := 0.0
	var t100 := -1.0
	var t200 := -1.0
	var vmax := 0.0
	var max_tilt := 0.0
	_set_in(1.0, 0.0, 0.0)
	while t < 70.0:
		await get_tree().physics_frame
		t += dt
		var kmh := car.forward_speed * 3.6
		vmax = maxf(vmax, kmh)
		if t100 < 0.0 and kmh >= 100.0:
			t100 = t
		if t200 < 0.0 and kmh >= 200.0:
			t200 = t
		if OS.get_cmdline_user_args().has("--verbose") and fmod(t, 1.0) < dt * 0.99 and t < 12.0:
			var fw := car.wheels[0]
			_log("   t=%.1f kmh=%.1f gear=%d rpm=%.0f tcs=%s loadF=%.0f loadR=%.0f eng=%.0f slipL=%.2f" % [t, kmh, car.gear, car.rpm, car.tcs_active, fw.load, car.wheels[2].load, car.engine_torque_out, fw.slip_long])
		max_tilt = maxf(max_tilt, rad_to_deg(acos(clampf(car.global_transform.basis.y.dot(Vector3.UP), -1, 1))))
		if car.global_position.z < -1400.0:
			break
	r["0_100"] = t100
	r["0_200"] = t200
	r["vmax"] = vmax
	r["tilt_at_speed"] = max_tilt
	# --- braking 100-0
	await _spawn(spec, Vector3(-100, 0, 1400))
	car.set_velocity_forward(100.0 / 3.6)
	await _frames(2)
	var p0 := car.global_position
	_set_in(0.0, 1.0, 0.0)
	t = 0.0
	while car.forward_speed > 0.3 and t < 15.0:
		await get_tree().physics_frame
		t += dt
	r["brake_100_0_m"] = p0.distance_to(car.global_position)
	# --- skidpad: hold a steady circle at ~60 km/h-ish with partial throttle, measure lateral g
	await _spawn(spec, Vector3(-600, 0, 0))
	car.set_velocity_forward(60.0 / 3.6)
	var lat_g := 0.0
	t = 0.0
	while t < 14.0:
		await get_tree().physics_frame
		t += dt
		var target := 60.0 / 3.6
		var thr := clampf((target - car.forward_speed) * 0.5, 0.0, 1.0)
		var brk := clampf((car.forward_speed - target) * 0.3, 0.0, 1.0)
		_set_in(thr, brk, 1.0)
		if t > 6.0:
			var v := car.linear_velocity
			var w := car.angular_velocity.y
			lat_g = maxf(lat_g, absf(v.length() * w) / 9.8)
	r["skidpad_g"] = lat_g
	# --- high-speed lane change at 200 km/h (or 85% of vmax)
	await _spawn(spec, Vector3(-900, 0, 1400))
	var vt := minf(200.0, vmax * 0.85) / 3.6
	car.set_velocity_forward(vt)
	t = 0.0
	var max_yaw := 0.0
	var spun := false
	while t < 6.0:
		await get_tree().physics_frame
		t += dt
		var s := 0.0
		if t > 0.5 and t < 1.2:
			s = 0.6
		elif t > 1.2 and t < 1.9:
			s = -0.6
		_set_in(0.5, 0.0, s)
		max_yaw = maxf(max_yaw, absf(car.drift_angle))
		if car.global_transform.basis.y.y < 0.5:
			spun = true
	r["lanechange_max_slip_deg"] = max_yaw
	r["lanechange_upright"] = not spun
	# --- jump: approach the ramp at 110 km/h
	await _spawn(spec, Vector3(-300, 0, -330))
	car.set_velocity_forward(110.0 / 3.6)
	t = 0.0
	var air := 0.0
	var max_air := 0.0
	var landed_ok := true
	var start_z := car.global_position.z
	var land_z := 0.0
	while t < 7.0:
		await get_tree().physics_frame
		t += dt
		_set_in(0.6, 0.0, 0.0)
		if car.wheels_on_ground == 0:
			air += dt
			max_air = maxf(max_air, air)
		else:
			if air > 0.3 and land_z == 0.0:
				land_z = car.global_position.z
			air = 0.0
		if car.global_transform.basis.y.y < 0.3:
			landed_ok = false
	r["jump_air_s"] = max_air
	r["jump_upright"] = landed_ok and car.global_transform.basis.y.y > 0.8
	# --- off-road traction: 0-60 km/h on gravel and sand
	for surf_x in [[300.0, "gravel"], [600.0, "sand"]]:
		await _spawn(spec, Vector3(surf_x[0], 0, 500))
		_set_in(1.0, 0.0, 0.0)
		t = 0.0
		var t60 := -1.0
		while t < 20.0:
			await get_tree().physics_frame
			t += dt
			if car.forward_speed * 3.6 >= 60.0:
				t60 = t
				break
		r["0_60_" + surf_x[1]] = t60
	results.append(r)
	_log("RESULT %s" % JSON.stringify(r))
