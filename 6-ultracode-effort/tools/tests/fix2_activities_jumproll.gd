extends Node
## Activities regression test (fix2): jump wipe-outs (rolling off the ramp edge), reset while armed, walking-pace
## roll-off and a drift zone driven without drifting. Prints every result / notification / credit change.
##   Godot_console.exe --path . --resolution 1600x900 res://tools/tests/fix2_activities_jumproll.tscn -- --cases=roll,reset,slow,short,drift --out=res://qa_output/<dir>

const MAIN := preload("res://scenes/main.tscn")

var out_dir := "res://qa_output/fix2_activities"
var results: Dictionary = {}
var last_hud := ""


func _ready() -> void:
	SaveGame.enabled = false
	Game.personal_bests = {}
	Game.discovered = {}
	out_dir = _arg("out", out_dir)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	Game.activity_finished.connect(func(id: String, r: Dictionary) -> void:
		results[id] = r
		print("[jr] RESULT %s %s" % [id, JSON.stringify(r)]))
	Game.activity_update.connect(func(i: Dictionary) -> void: last_hud = "%s | %s" % [i.get("primary", ""), i.get("secondary", "")])
	Game.notification.connect(func(t: String, b: String, k: StringName) -> void:
		if k != &"discovery":
			print("[jr] NOTIFY [%s] %s | %s" % [k, t, b]))
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
	var path := out_dir.path_join("%s.png" % n)
	get_viewport().get_texture().get_image().save_png(path)
	print("[jr] shot ", ProjectSettings.globalize_path(path))


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


func _car(id: String) -> void:
	var idx := Game.find_car_index(id)
	if idx >= 0 and Game.current_car_index != idx:
		Game.spawn_car(idx, true)
		await _wait(0.3)


func _run() -> void:
	while Game.main == null or Game.main.is_loading:
		await get_tree().process_frame
	Game.main.car_input.process_mode = Node.PROCESS_MODE_DISABLED
	var dens0: float = Game.traffic.get_density() if Game.traffic != null else 0.0
	if Game.traffic != null:
		Game.traffic.set_density(0.0)
	Game.set_time_of_day(13.0)
	Game.set_weather("clear", true)
	await _wait(1.0)
	var cases := _arg("cases", "roll,reset,slow,short,drift").split(",")
	if cases.has("roll"):
		for lat: float in [-3.0, -3.2, -3.4]:
			await _roll(lat)
	if cases.has("reset"):
		await _reset_armed()
	if cases.has("slow"):
		await _slow(29.0)
	if cases.has("short"):
		for kmh: float in [38.0, 44.0, 50.0]:
			await _slow(kmh)
	if cases.has("drift"):
		await _no_drift()
	if Game.traffic != null:
		Game.traffic.set_density(dens0)
	print("[jr] DONE")
	get_tree().quit(0)


func _drive_on(road: RoadNetwork.Road, s0: float, d: int, lat: float, kmh: float) -> RoadFollower:
	var fwd := road.flat_tangent_at(s0) * d
	Game.main.teleport_to({"position": road.surface_point(s0, lat * d), "forward": fwd})
	await _wait_streamed()
	var car := Game.player_car
	car.repair()
	car.freeze = false
	await get_tree().physics_frame
	_launch(car, fwd, kmh)
	var f := RoadFollower.new()
	f.setup(road, s0, d, lat)
	f.target_speed = kmh / 3.6
	f.lat_accel = 3.5
	return f


## Rolls the car off the left edge of the Redwall ramp (half the car beside the deck).
func _roll(lat: float) -> void:
	await _car("granite_rs")
	var mgr: Node = Game.activities
	var road := (Game.world as World).data.network.get_road("canyon_floor")
	results.erase("dj_redwall")
	var cr0 := Game.credits
	var f: RoadFollower = await _drive_on(road, 560.0, 1, 0.0, 79.0)
	var t := 0.0
	var max_tilt := 0.0
	var log_t := 0.0
	var shot := 0
	var stopped_t := 0.0
	while t < 40.0:
		await get_tree().physics_frame
		var dt := get_physics_process_delta_time()
		t += dt
		var car := Game.player_car
		f.lane_offset = lat if f.s > 680.0 else 0.0
		var tilt := rad_to_deg(acos(clampf(car.global_basis.y.y, -1.0, 1.0)))
		max_tilt = maxf(max_tilt, tilt)
		f.drive(car, dt)
		if tilt > 45.0 or f.s > 805.0:
			car.in_throttle = 0.0
		log_t += dt
		if log_t >= 0.25 and f.s > 760.0:
			log_t = 0.0
			print("[jr]   t=%.2f s=%.0f tilt %.0f wheels %d %.0f km/h session '%s' hud '%s'" % [t, f.s, tilt, car.wheels_on_ground, car.get_speed_kmh(), mgr.get_session_id(), last_hud])
		if shot == 0 and tilt > 60.0:
			shot = 1
			await _shot("roll_%.1f_tilt" % lat)
		if f.s > 790.0 and car.speed_ms < 0.5:
			stopped_t += dt
			if stopped_t > 3.0:
				break
	var car2 := Game.player_car
	await _shot("roll_%.1f_stopped" % lat)
	print("[jr] ROLL lat %.1f: max tilt %.0f, end tilt %.0f, session '%s', result %s, credits +%d" % [lat, max_tilt,
		rad_to_deg(acos(clampf(car2.global_basis.y.y, -1.0, 1.0))), mgr.get_session_id(), JSON.stringify(results.get("dj_redwall", {})), Game.credits - cr0])
	# The player now presses R: must not score anything.
	Game.respawn()
	await _wait(2.0)
	print("[jr] ROLL lat %.1f after reset: session '%s', result %s, credits +%d" % [lat, mgr.get_session_id(), JSON.stringify(results.get("dj_redwall", {})), Game.credits - cr0])
	mgr.cancel_session("test")
	Game.personal_bests = {}


## Arms the jump, then resets (R) 40 m before the lip.
func _reset_armed() -> void:
	await _car("kestrel_r4")
	var mgr: Node = Game.activities
	var road := (Game.world as World).data.network.get_road("canyon_floor")
	results.erase("dj_redwall")
	var cr0 := Game.credits
	var f: RoadFollower = await _drive_on(road, 560.0, 1, 0.0, 60.0)
	var t := 0.0
	var reset := false
	while t < 25.0:
		await get_tree().physics_frame
		var dt := get_physics_process_delta_time()
		t += dt
		f.drive(Game.player_car, dt)
		if not reset and f.s > 753.0:
			reset = true
			print("[jr] RESET at s=%.0f session '%s'" % [f.s, mgr.get_session_id()])
			Game.respawn()
			await _wait(4.0)
			break
	print("[jr] RESET result: session '%s', result %s, credits +%d" % [mgr.get_session_id(), JSON.stringify(results.get("dj_redwall", {})), Game.credits - cr0])
	mgr.cancel_session("test")
	Game.personal_bests = {}


## Drives over the Redwall ramp at a steady low speed.
func _slow(kmh: float) -> void:
	await _car("sora_s2")
	var mgr: Node = Game.activities
	var road := (Game.world as World).data.network.get_road("canyon_floor")
	while float(mgr.by_id["dj_redwall"].get("cooldown")) > 0.0:
		await get_tree().physics_frame
	results.erase("dj_redwall")
	var cr0 := Game.credits
	var f: RoadFollower = await _drive_on(road, 603.0, 1, 0.0, kmh)
	var t := 0.0
	var shot := false
	while t < 40.0 and not results.has("dj_redwall"):
		await get_tree().physics_frame
		var dt := get_physics_process_delta_time()
		t += dt
		f.drive(Game.player_car, dt)
	await _wait(0.6)
	await _shot("slow_%d_banner" % int(kmh))
	print("[jr] SLOW %d km/h result %s, credits +%d, PB stored %s" % [int(kmh), JSON.stringify(results.get("dj_redwall", {})), Game.credits - cr0, str(Game.personal_bests.get("activity:dj_redwall"))])
	mgr.cancel_session("test")
	Game.personal_bests = {}


## Drives the Ember Spur Esses drift zone in the lane without sliding.
func _no_drift() -> void:
	await _car("sora_s2")
	var mgr: Node = Game.activities
	var road := (Game.world as World).data.network.get_road("ring")
	results.erase("dz_ember_spur")
	var cr0 := Game.credits
	var f: RoadFollower = await _drive_on(road, 8088.0, 1, road.lane_offset(1), 70.0)
	var t := 0.0
	var max_slip := 0.0
	var started := false
	var ended_t := -1.0
	while t < 80.0:
		await get_tree().physics_frame
		var dt := get_physics_process_delta_time()
		t += dt
		var car := Game.player_car
		f.drive(car, dt)
		if mgr.get_session_id() == "dz_ember_spur":
			started = true
			max_slip = maxf(max_slip, absf(car.body_slip_deg))
		elif started and ended_t < 0.0:
			ended_t = t
			await _wait(0.3)
			await _shot("nodrift_end")
		if ended_t > 0.0 and t > ended_t + 1.5:
			break
	print("[jr] NODRIFT started %s, max slip %.1f deg, result %s, credits +%d, PB %s" % [started, max_slip, JSON.stringify(results.get("dz_ember_spur", {})),
		Game.credits - cr0, str(Game.personal_bests.get("activity:dz_ember_spur"))])
	mgr.cancel_session("test")
