extends Node
## Automated drive tests on the proving ground. Run (fast, headless):
##   godot --headless --fixed-fps 120 --path . -- --test-track --qa=drive_test [--car=<id>]
## Writes qa/results/drive_<car>.json and prints a summary line.

var car: CarController
var tests := ["accel", "brake", "top", "skidpad", "lanechange", "jump", "gravel", "handbrake"]
var idx := -1
var t := 0.0
var st := {}
var results := {}


func _ready() -> void:
	Game.main.driver.car = null
	car = Game.player
	if Game.main.arg("tests") != "":
		tests = Array(Game.main.arg("tests").split(","))
	_next()


func _next() -> void:
	idx += 1
	t = 0.0
	st = {}
	if idx >= tests.size():
		_finish()
		return
	var name: String = tests[idx]
	car.in_throttle = 0.0
	car.in_brake = 0.0
	car.in_steer = 0.0
	car.in_handbrake = false
	match name:
		"accel":
			car.teleport(Vector3(0, 0.5, 7000), Vector3.FORWARD, 0.0)
		"brake":
			car.teleport(Vector3(0, 0.5, 7000), Vector3.FORWARD, 100.0 / 3.6)
		"top":
			car.teleport(Vector3(0, 0.5, 7900), Vector3.FORWARD, 0.0)
		"skidpad":
			car.teleport(Vector3(640, 0.5, 0), Vector3.FORWARD, 30.0 / 3.6)
			st.target = 40.0
		"lanechange":
			car.teleport(Vector3(0, 0.5, 7000), Vector3.FORWARD, 200.0 / 3.6)
		"jump":
			car.teleport(Vector3(300, 0.5, -250), Vector3.FORWARD, 100.0 / 3.6)
		"gravel":
			car.teleport(Vector3(-300, 0.5, -120), Vector3.FORWARD, 0.0)
		"handbrake":
			car.teleport(Vector3(-1200, 0.5, 6000), Vector3.FORWARD, 80.0 / 3.6)


func _physics_process(delta: float) -> void:
	if idx < 0 or idx >= tests.size():
		return
	t += delta
	var name: String = tests[idx]
	if Game.main.arg("verbose") != "" and fmod(t, 0.5) < delta:
		var w := car.wheels
		print("%s t=%.1f kmh=%.1f g=%d rpm=%d thr=%.2f grounded=%d y=%.2f z=%.1f | R slip %.2f/%.2f fz %d/%d fx %d/%d om %.1f surf %s tcs %s" % [
			name, t, car.kmh(), car.gear, car.rpm, car.throttle_out, car.grounded, car.global_position.y, car.global_position.z,
			w[2].slip_ratio, w[3].slip_ratio, w[2].fz, w[3].fz, w[2].fx, w[3].fx, w[2].omega,
			w[2].surface.display_name if w[2].surface else "-", car.tcs_active])
	var kmh := car.kmh()
	var pos := car.global_position
	var up_dot := car.global_transform.basis.y.dot(Vector3.UP)
	match name:
		"accel":
			car.in_throttle = 1.0
			if kmh >= 100.0 and not st.has("t100"):
				st.t100 = t
			if kmh >= 200.0 and not st.has("t200"):
				st.t200 = t
			if st.has("t200") or t > 40.0:
				results.accel_0_100_s = snappedf(st.get("t100", -1.0), 0.01)
				results.accel_0_200_s = snappedf(st.get("t200", -1.0), 0.01)
				_next()
		"brake":
			if t < 0.25:
				car.in_throttle = 0.3
				st.start = pos
				return
			car.in_throttle = 0.0
			car.in_brake = 1.0
			if kmh < 0.5 or t > 15.0:
				results.brake_100_0_m = snappedf(pos.distance_to(st.start), 0.1)
				_next()
		"top":
			car.in_throttle = 1.0
			st.vmax = maxf(float(st.get("vmax", 0.0)), kmh)
			if pos.z < -7800.0 or t > 90.0:
				results.top_speed_kmh = snappedf(float(st.vmax), 0.1)
				results.top_speed_time_s = snappedf(t, 0.1)
				_next()
		"skidpad":
			var c := Vector3(600, 0, 0)
			var rel := Vector3(pos.x - c.x, 0, pos.z - c.z)
			var r := rel.length()
			var tangent := Vector3(rel.z, 0, -rel.x).normalized()  # direction of a left-hand lap
			var fwd := -car.global_transform.basis.z
			fwd.y = 0.0
			fwd = fwd.normalized()
			var head_err := fwd.signed_angle_to(tangent, Vector3.UP)
			var ff := -atan(2.6 / 40.0) / deg_to_rad(car.data.max_steer_deg)
			car.in_steer = clampf(ff - head_err * 1.8 + (r - 40.0) * -0.08, -1.0, 1.0)
			var target_kmh := 30.0 + t * 2.0
			car.in_throttle = clampf((target_kmh - kmh) * 0.15, 0.0, 1.0)
			car.in_brake = 0.0
			if absf(r - 40.0) < 2.5 and t > 4.0:
				var v := car.speed_abs
				st.best = maxf(float(st.get("best", 0.0)), v * v / 40.0 / 9.81)
			if (absf(r - 40.0) > 6.0 and t > 6.0) or t > 60.0:
				results.skidpad_lat_g = snappedf(float(st.get("best", 0.0)), 0.01)
				_next()
		"lanechange":
			car.in_throttle = 0.75
			var s := 0.0
			if t > 1.0 and t < 2.0:
				s = 0.35
			elif t >= 2.0 and t < 3.0:
				s = -0.35
			car.in_steer = s
			st.max_yaw = maxf(float(st.get("max_yaw", 0.0)), absf(car.angular_velocity.y))
			st.max_slip = maxf(float(st.get("max_slip", 0.0)), rad_to_deg(absf(car.body_slip)))
			if t > 6.0:
				var fwd := -car.global_transform.basis.z
				results.lanechange_200_max_yaw_rad_s = snappedf(float(st.max_yaw), 0.01)
				results.lanechange_200_max_body_slip_deg = snappedf(float(st.max_slip), 0.1)
				results.lanechange_200_final_heading_deg = snappedf(rad_to_deg(Vector3.FORWARD.angle_to(Vector3(fwd.x, 0, fwd.z))), 0.1)
				results.lanechange_200_stable = float(st.max_slip) < 15.0 and up_dot > 0.95
				_next()
		"jump":
			car.in_throttle = 0.6
			if car.grounded == 0 and not st.has("air_from") and t > 1.0:
				st.air_from = pos
				st.air_t = t
			if st.has("air_from") and car.grounded >= 2:
				if t - float(st.air_t) > float(st.get("best_air", 0.0)):
					st.best_air = t - float(st.air_t)
					st.takeoff = st.air_from
					st.land = pos
					st.t_off = st.air_t
					st.t_land = t
				st.erase("air_from")
			st.min_up = minf(float(st.get("min_up", 1.0)), up_dot)
			if (st.has("land") and pos.z < -420.0 and t - float(st.t_land) > 2.0) or t > 14.0:
				if st.has("land"):
					var a: Vector3 = st.takeoff
					var b: Vector3 = st.land
					results.jump_distance_m = snappedf(Vector2(a.x, a.z).distance_to(Vector2(b.x, b.z)), 0.1)
					results.jump_airtime_s = snappedf(float(st.t_land) - float(st.t_off), 0.01)
				results.jump_min_up_dot = snappedf(float(st.min_up), 0.02)
				results.jump_landed_upright = up_dot > 0.9 and kmh > 30.0
				_next()
		"gravel":
			car.in_throttle = 1.0
			if kmh >= 100.0 and not st.has("t100"):
				st.t100 = t
			if st.has("t100") or t > 30.0:
				results.gravel_0_100_s = snappedf(float(st.get("t100", -1.0)), 0.01)
				_next()
		"handbrake":
			car.in_throttle = 0.4
			if t > 0.5 and t < 1.6:
				car.in_steer = 0.6
				car.in_handbrake = t < 1.1
			else:
				car.in_steer = 0.0
				car.in_handbrake = false
			st.max_drift = maxf(float(st.get("max_drift", 0.0)), car.drift_angle)
			if t > 5.0:
				results.handbrake_turn_max_drift_deg = snappedf(float(st.max_drift), 0.1)
				results.handbrake_recovered = car.drift_angle < 10.0 and up_dot > 0.95
				_next()


func _finish() -> void:
	var id := String(car.data.id)
	results.car = id
	DirAccess.make_dir_recursive_absolute("res://qa/results")
	# partial runs (--tests=...) update the stored numbers instead of replacing them
	var path := "res://qa/results/drive_%s.json" % id
	if FileAccess.file_exists(path):
		var old: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if old is Dictionary:
			(old as Dictionary).merge(results, true)
			results = old
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(results, "  ", false))
	f.close()
	print("DRIVE_TEST ", JSON.stringify(results))
	get_tree().quit(0)
