extends Node
## Activities regression test (fix2): festival ramps driven in the jump direction at fixed speeds (scored distance)
## and against the jump direction at 70 km/h (speed drop / impacts / damage / passes the ramp).
##   Godot_console.exe --path . --resolution 1600x900 res://tools/tests/fix2_activities_ramps.tscn -- --tag=after
## Options: --ids=dj_a,dj_b (default: every festival ramp) --speeds=60,90 --rev=1 --fwd=1 --rev-kmh=70 --lat=0 --out=res://qa_output/fix2_activities

const MAIN := preload("res://scenes/main.tscn")

var out_dir := "res://qa_output/fix2_activities"
var tag := "run"
var results: Dictionary = {}
var _impacts: Array[float] = []


func _ready() -> void:
	SaveGame.enabled = false
	Game.personal_bests = {}
	Game.discovered = {}
	out_dir = _arg("out", out_dir)
	tag = _arg("tag", tag)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	Game.activity_finished.connect(func(id: String, r: Dictionary) -> void:
		results[id] = r
		print("[rt] RESULT %s %s" % [id, JSON.stringify(r)]))
	Game.notification.connect(func(t: String, b: String, k: StringName) -> void: print("[rt] NOTIFY [%s] %s | %s" % [k, t, b]))
	add_child(MAIN.instantiate())
	_run.call_deferred()


static func _arg(key: String, default: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--" + key + "="):
			return a.substr(key.length() + 3)
	return default


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds, true, false, true).timeout


func _wait_streamed() -> void:
	await get_tree().process_frame
	var w := Game.world as World
	var t := 0.0
	while t < 20.0 and (w.terrain.pending_count() > 0 or not w.roads.done):
		await get_tree().process_frame
		t += get_process_delta_time()
	await _wait(0.5)


func _shot(n: String) -> void:
	await RenderingServer.frame_post_draw
	var path := out_dir.path_join("%s_%s.png" % [tag, n])
	get_viewport().get_texture().get_image().save_png(path)
	print("[rt] shot ", ProjectSettings.globalize_path(path))


func _launch(car: CarController, fwd: Vector3, kmh: float) -> void:
	var v := kmh / 3.6
	car.linear_velocity = fwd * v
	var best := 1
	for g in car.data.gear_ratios.size():
		best = g + 1
		if v / car.wheels[0].radius * car.data.gear_ratios[g] * car.data.final_drive * 60.0 / TAU < car.data.redline_rpm * 0.85:
			break
	car.gear = best
	for w in car.wheels:
		w.omega = v / w.radius


func _run() -> void:
	while Game.main == null or Game.main.is_loading:
		await get_tree().process_frame
	Game.main.car_input.process_mode = Node.PROCESS_MODE_DISABLED
	var dens0: float = Game.traffic.get_density() if Game.traffic != null else 0.0
	if Game.traffic != null:
		Game.traffic.set_density(0.0)
	Game.set_time_of_day(13.0)
	Game.set_weather("clear", true)
	if Game.current_car_index != 0:
		Game.spawn_car(0, true)
	Game.player_car.impact.connect(func(s: float, _p: Vector3) -> void: _impacts.append(s))
	await _wait(1.0)
	var mgr: Node = Game.activities
	var ids := _arg("ids", "").split(",", false)
	for ev: Dictionary in mgr.get_activity_list():
		var ramp := bool(((mgr.by_id[ev["id"]] as RefCounted).get("data") as Resource).get("extra").get("ramp", false))
		if not (ids.has(ev["id"]) or (ids.is_empty() and ramp)):
			continue
		if _arg("fwd", "1") == "1":
			for sp in _arg("speeds", "60,90").split(","):
				await _forward(mgr, ev, float(sp))
		if _arg("rev", "1") == "1":
			await _reverse(mgr, ev, float(_arg("rev-kmh", "70")), float(_arg("lat", "0")))
	if Game.traffic != null:
		Game.traffic.set_density(dens0)
	print("[rt] DONE")
	get_tree().quit(0)


func _forward(mgr: Node, ev: Dictionary, kmh: float) -> void:
	var road := (Game.world as World).data.network.get_road(ev["road"])
	var d: int = ev["dir"]
	var lip: float = ev["gates"][1]
	var s0 := lip - d * 210.0
	var fwd := road.flat_tangent_at(s0) * d
	results.erase(ev["id"])
	while float(mgr.by_id[ev["id"]].get("cooldown")) > 0.0:
		await get_tree().physics_frame
	Game.main.teleport_to({"position": road.surface_point(s0, 0.0), "forward": fwd})
	await _wait_streamed()
	var car := Game.player_car
	car.freeze = false
	await get_tree().physics_frame
	_launch(car, fwd, kmh)
	var f := RoadFollower.new()
	f.setup(road, s0, d, 0.0)
	f.target_speed = kmh / 3.6
	f.lat_accel = 3.5
	var t := 0.0
	var take_kmh := 0.0
	var max_tilt := 0.0
	var shot := false
	while t < 30.0 and not results.has(ev["id"]):
		await get_tree().physics_frame
		var dt := get_physics_process_delta_time()
		t += dt
		car = Game.player_car
		var past := (f.s - lip) * d
		if past < 0.0:
			take_kmh = car.get_speed_kmh()
		max_tilt = maxf(max_tilt, rad_to_deg(acos(clampf(car.global_basis.y.y, -1.0, 1.0))))
		if not shot and past > 4.0:
			shot = true
			await _shot("%s_fwd%d_air" % [ev["id"], int(kmh)])
		f.drive(car, dt)
	var r: Dictionary = results.get(ev["id"], {})
	print("[rt] FWD %s @%d km/h: lip speed %.0f km/h, result %s (%s), max tilt %.1f, session '%s'" % [ev["id"], int(kmh), take_kmh,
		r.get("score_text", "none"), "pb %s cr %s medal %s" % [r.get("personal_best", "-"), r.get("credits", "-"), r.get("medal", "-")], max_tilt, mgr.get_session_id()])
	mgr.cancel_session("test")
	Game.personal_bests = {}


func _reverse(mgr: Node, ev: Dictionary, kmh: float, lat: float) -> void:
	var road := (Game.world as World).data.network.get_road(ev["road"])
	var d: int = -int(ev["dir"])
	var lip: float = ev["gates"][1]
	var s0 := lip - d * 95.0
	var fwd := road.flat_tangent_at(s0) * d
	Game.main.teleport_to({"position": road.surface_point(s0, lat * d), "forward": fwd})
	await _wait_streamed()
	var car := Game.player_car
	car.repair()
	car.freeze = false
	await get_tree().physics_frame
	_launch(car, fwd, kmh)
	_impacts.clear()
	var f := RoadFollower.new()
	f.setup(road, s0, d, lat)
	f.target_speed = kmh / 3.6
	f.lat_accel = 3.5
	var t := 0.0
	var prev_v := car.get_speed_kmh()
	var max_drop := 0.0
	var max_tilt := 0.0
	var air := 0.0
	var shots := 0
	var passed := false
	while t < 14.0:
		await get_tree().physics_frame
		var dt := get_physics_process_delta_time()
		t += dt
		car = Game.player_car
		var v := car.get_speed_kmh()
		max_drop = maxf(max_drop, prev_v - v)
		prev_v = v
		max_tilt = maxf(max_tilt, rad_to_deg(acos(clampf(car.global_basis.y.y, -1.0, 1.0))))
		if car.wheels_on_ground == 0:
			air += dt
		var to_lip := (lip - f.s) * d
		if shots == 0 and t > 0.4:
			shots = 1
			await _shot("%s_rev_sign" % ev["id"])
		elif shots == 1 and to_lip < 22.0:
			shots = 2
			await _shot("%s_rev_approach" % ev["id"])
		elif shots == 2 and to_lip < -3.0:
			shots = 3
			await _shot("%s_rev_over" % ev["id"])
		if to_lip < -45.0:
			passed = true
			break
		f.drive(car, dt)
	print("[rt] REV %s @%d km/h lat %.1f: passed %s, max single-frame drop %.1f km/h, impacts %s, damage %.2f, end speed %.0f, max tilt %.1f, air %.2f s, session '%s'" % [
		ev["id"], int(kmh), lat, passed, max_drop, str(_impacts), car.damage, car.get_speed_kmh(), max_tilt, air, mgr.get_session_id()])
	await _shot("%s_rev_end" % ev["id"])
