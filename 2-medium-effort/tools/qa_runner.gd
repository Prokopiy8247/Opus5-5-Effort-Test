extends Node
## In-game QA automation (run: godot --path . -- --qa [--qa-shots] [--qa-drive=SECONDS] [--qa-loop]).
## Drives the player car with the autopilot, logs speed/FPS/frame-times and saves screenshots.

var main: Node
var log_lines: PackedStringArray = []
var args: PackedStringArray


func _ready() -> void:
	main = get_parent()
	args = OS.get_cmdline_user_args()
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run()


func _arg(prefix: String, def: String) -> String:
	for a in args:
		if a.begins_with(prefix + "="):
			return a.substr(prefix.length() + 1)
	return def


func _log(s: String) -> void:
	print("[qa] " + s)
	log_lines.append(s)
	var f := FileAccess.open("res://qa/qa_live.txt", FileAccess.READ_WRITE if FileAccess.file_exists("res://qa/qa_live.txt") else FileAccess.WRITE)
	if f:
		f.seek_end()
		f.store_line(s)
		f.close()


func shot(nm: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png("res://qa/screens/%s.png" % nm)
	_log("screenshot " + nm)


func wait(sec: float) -> void:
	await get_tree().create_timer(sec, true, false, true).timeout


func _run() -> void:
	DirAccess.make_dir_recursive_absolute("res://qa/screens")
	await wait(1.5)
	var mode: String = _arg("--qa-mode", "shots")
	if mode == "shots":
		await _shots()
	elif mode == "drive":
		await _drive_test(float(_arg("--qa-drive", "40")))
	elif mode == "cars":
		await _car_tests()
	elif mode == "loop":
		await _loop_test()
	elif mode == "showcase":
		await _showcase()
	elif mode == "compare":
		main.player_input.enabled = false
		var cmp: Node = load("res://tools/vehiclebody_compare.gd").new()
		add_child(cmp)
		var res: PackedStringArray = await cmp.run()
		for r in res:
			_log(r)
	elif mode == "probe":
		await _probe(_arg("--qa-road", "West Coast Road"), float(_arg("--qa-s", "120")))
	elif mode == "perf":
		await _perf(_arg("--qa-road", "Highland Pass"))
	elif mode == "save":
		await _save_test()
	elif mode == "jump":
		await _jump_test()
	elif mode == "drift":
		await _drift_test()
	elif mode == "ui":
		await _ui_test()
	elif mode == "events":
		await _events_test()
	var f := FileAccess.open("res://qa/qa_log_%s.txt" % mode, FileAccess.WRITE)
	f.store_string("\n".join(log_lines))
	f.close()
	get_tree().quit()


func _shots() -> void:
	var car: Car = main.car
	main.player_input.enabled = false
	Game.sky.time_frozen = true
	Game.sky.set_hour(float(_arg("--qa-hour", "10.5")))
	await wait(1.0)
	_log("hud=%s size=%s visible=%s ui=%s" % [str(Game.hud), str(Game.hud.size) if Game.hud else "-", str(Game.hud.is_visible_in_tree()) if Game.hud else "-", str(main.ui)])
	await shot("spawn_chase")
	var ap := RoadAutopilot.new(Game.world, main.road_index(main.START_ROAD), main.START_S)
	ap.target_speed = 30.0
	var t: float = 0.0
	while t < 8.0:
		ap.update(car, 0.016)
		await get_tree().physics_frame
		t += 1.0 / 120.0
	_log("speed after 8s: %.1f km/h" % car.kmh())
	await shot("driving_chase")
	main.camera.mode = ChaseCamera.Mode.COCKPIT
	await wait(0.3)
	await shot("driving_cockpit")
	main.camera.mode = ChaseCamera.Mode.CHASE_NEAR
	for poi in ["mountains", "desert", "village", "bridge", "canyon"]:
		var ok: bool = main.teleport_poi(poi)
		await wait(1.5)
		_log("poi %s ok=%s car at %s" % [poi, str(ok), str(main.car.global_position.round())])
		await shot("poi_" + poi)
	_log("fps %.1f" % Engine.get_frames_per_second())
	if Game.traffic:
		_log("traffic active=%d stats=%s" % [Game.traffic.active_count(), str(Game.traffic.stats)])


func _drive_test(dur: float) -> void:
	var car: Car = main.car
	main.player_input.enabled = false
	var start_road: String = _arg("--qa-road", main.START_ROAD)
	var t0: Transform3D = main.road_transform_by_name(start_road, 30.0)
	main.teleport_to(t0)
	await wait(0.5)
	var ap := RoadAutopilot.new(Game.world, main.road_index(start_road), 30.0)
	ap.target_speed = float(_arg("--qa-speed", "60")) / 3.6
	var t: float = 0.0
	var frames: int = 0
	var shots_taken: int = 0
	var worst: float = 0.0
	var acc_t: float = 0.0
	while t < dur:
		var dt: float = get_process_delta_time()
		ap.update(car, dt)
		await get_tree().process_frame
		t += dt
		frames += 1
		worst = maxf(worst, dt)
		acc_t += dt
		if int(t) % 5 == 0 and acc_t > 4.9:
			acc_t = 0.0
			_log("t=%.0f speed=%.0f km/h gear=%d rpm=%.0f fps=%.0f pos=%s chunks=%d proc=%.1fms phys=%.1fms draws=%d prims=%d traffic=%d" % [t, car.kmh(), car.gear, car.rpm, Engine.get_frames_per_second(), str(car.global_position.round()), main.streamer.loaded_count(), Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0, Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME), Game.traffic.active_count() if Game.traffic else -1])
		if Game.traffic and shots_taken < 4 and t > 6.0:
			for tv in Game.traffic.pool:
				if tv.active and not tv.wrecked and tv.global_position.distance_to(car.global_position) < 45.0 and main.camera.is_position_in_frustum(tv.global_position):
					shots_taken += 1
					await shot("traffic_%d" % shots_taken)
					_log("traffic shot: %s v=%.0f km/h road=%s" % [tv.kind, tv.v * 3.6, Game.world.roads[tv.road].name])
					break
	_log("avg fps %.1f worst frame %.1f ms" % [frames / t, worst * 1000.0])
	if Game.traffic:
		_log("traffic stats %s active %d" % [str(Game.traffic.stats), Game.traffic.active_count()])


## Scripted performance tests for every car on a flat 12 km test strip (physics only, high above the map):
## 0-100 km/h, top speed (60 s full throttle), braking 100-0, 60 m skidpad lateral g, high-speed stability.
func _car_tests() -> void:
	main.player_input.enabled = false
	var strip := StaticBody3D.new()
	strip.collision_layer = 1
	strip.set_meta("road_surface", 0)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(400, 2, 12000)
	cs.shape = bs
	strip.add_child(cs)
	main.add_child(strip)
	strip.global_position = Vector3(0, 999, 0)
	var only: String = _arg("--qa-car", "")
	var only_list: PackedStringArray = only.split(",", false)
	for i in Game.cars.size():
		if not only_list.is_empty() and not (Game.cars[i].id in only_list):
			continue
		var start := Transform3D(Basis(), Vector3(0, 1000.8, 5900))
		main.spawn_car(i, start)
		var car: Car = main.car
		await wait(0.8)
		car.teleport(start)
		await get_tree().physics_frame
		var t: float = 0.0
		var t100: float = -1.0
		var t200: float = -1.0
		var vmax: float = 0.0
		var max_roll: float = 0.0
		var tcs_n: int = 0
		var n100: int = 0
		while t < 50.0:
			car.in_throttle = 1.0
			car.in_brake = 0.0
			car.in_steer = clampf(-car.global_position.x * 0.05 - car.angular_velocity.y * 0.3, -0.2, 0.2)
			await get_tree().physics_frame
			t += 1.0 / 120.0
			var k: float = car.kmh()
			vmax = maxf(vmax, k)
			if t100 < 0.0 and k >= 100.0:
				t100 = t
			if t100 < 0.0:
				tcs_n += 1 if car.tcs_active else 0
				n100 += 1
				if int(t * 120.0) % 60 == 0:
					_log("   launch t=%.2f v=%.0f gear=%d rpm=%.0f tcs=%s grounded=%d loads=%s" % [t, k, car.gear, car.rpm, str(car.tcs_active), car.grounded_wheels, str(car.wheels.map(func(w): return int(w.load)))])
			if t200 < 0.0 and k >= 200.0:
				t200 = t
			if k > 150.0:
				max_roll = maxf(max_roll, absf(rad_to_deg(car.global_transform.basis.get_euler().z)))
			if car.global_position.z < -5800.0:
				break
		# braking from 100 km/h
		car.teleport(start)
		await get_tree().physics_frame
		await get_tree().physics_frame
		for k in 90:
			await get_tree().physics_frame
		car.set_speed_forward(100.0 / 3.6)
		await get_tree().physics_frame
		var p0: Vector3 = car.global_position
		t = 0.0
		while car.kmh() > 0.5 and t < 10.0:
			car.in_throttle = 0.0
			car.in_brake = 1.0
			car.in_steer = 0.0
			await get_tree().physics_frame
			t += 1.0 / 120.0
		var bd: float = car.global_position.distance_to(p0) - 0.0
		# skidpad: hold a 60 m radius circle, raise speed until it can no longer hold the line
		car.teleport(Transform3D(Basis(), Vector3(-100, 1000.8, 0)))
		await get_tree().physics_frame
		var center := Vector3(-160, 1000.8, 0)
		var lat_g: float = 0.0
		t = 0.0
		var target_v: float = 10.0
		while t < 28.0:
			var to_c: Vector3 = center - car.global_position
			to_c.y = 0.0
			var r_now: float = to_c.length()
			var tangent: Vector3 = Vector3.UP.cross(to_c.normalized())
			var fwd: Vector3 = -car.global_transform.basis.z
			var want: Vector3 = (tangent + to_c.normalized() * (r_now - 60.0) * 0.05).normalized()
			var ang: float = atan2(want.dot(car.global_transform.basis.x), want.dot(fwd))
			car.in_steer = clampf(ang * 2.5, -1.0, 1.0)
			var v: float = car.linear_velocity.length()
			target_v += (1.0 / 120.0) * 0.9
			car.in_throttle = clampf((target_v - v) * 0.5, 0.0, 1.0)
			car.in_brake = 0.0
			await get_tree().physics_frame
			t += 1.0 / 120.0
			if absf(r_now - 60.0) < 4.0 and t > 5.0:
				lat_g = maxf(lat_g, v * v / r_now / 9.81)
			if absf(r_now - 60.0) > 12.0 and t > 8.0:
				break
		_log("%-9s 0-100 %5.2f s | 0-200 %5.2f s | vmax %4.0f km/h (target %3.0f) | 100-0 %5.1f m | skidpad %.2f g | roll@speed %.1f deg" % [car.def.id, t100, t200, vmax, car.def.top_speed_kmh, bd, lat_g, max_roll])
	strip.queue_free()


func _loop_test() -> void:
	# drive the whole scenic loop with the autopilot and report time, falls and FPS
	main.player_input.enabled = false
	if Game.activities:
		Game.activities.process_mode = Node.PROCESS_MODE_DISABLED
	var route: Array = []
	for i in Game.world.roads.size():
		if Game.world.roads[i].loop:
			route.append([i, 1])
	var first: Array = route.pop_front()
	var t0: Transform3D = Game.world.road_point(first[0], 5.0, 1.6)
	t0.origin.y += 0.5
	main.teleport_to(t0)
	await wait(0.5)
	var car: Car = main.car
	var ap := RoadAutopilot.new(Game.world, first[0], 5.0)
	ap.route = route
	ap.target_speed = float(_arg("--qa-speed", "40"))
	var t: float = 0.0
	var resets: int = 0
	var worst: float = 0.0
	var frames: int = 0
	var mem0: float = Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0
	var hitches: int = 0
	var stuck_t: float = 0.0
	var stuck_n: int = 0
	var last_log: float = 0.0
	var dist: float = 0.0
	var last_p: Vector3 = car.global_position
	while t < 1500.0:
		var dt: float = get_process_delta_time()
		ap.update(car, dt)
		await get_tree().process_frame
		t += dt
		frames += 1
		if t > 3.0:
			worst = maxf(worst, dt)
			if dt > 0.05:
				hitches += 1
		dist += car.global_position.distance_to(last_p)
		last_p = car.global_position
		if car.linear_velocity.length() < 1.0 and t > 5.0:
			stuck_t += dt
			if stuck_t > 6.0:
				stuck_t = 0.0
				stuck_n += 1
				var near_list: Array = []
				for tv in Game.traffic.pool:
					if tv.active and tv.global_position.distance_to(car.global_position) < 15.0:
						near_list.append("%s wrecked=%s v=%.1f road=%s" % [tv.kind, str(tv.wrecked), tv.v, Game.world.roads[tv.road].name])
				_log("STUCK at %s road=%s s=%.0f near=%s colliding=%s" % [str(car.global_position.round()), Game.world.roads[ap.road].name, ap.s, str(near_list), str(car.get_colliding_bodies().map(func(b): return b.name))])
				ap.s += 25.0 * ap.dir
				var tr: Transform3D = Game.world.road_point(ap.road, ap.s, Game.world.roads[ap.road].lane * 0.5)
				tr.origin.y += 0.8
				main.teleport_to(tr)
		else:
			stuck_t = 0.0
		if t - last_log > 20.0:
			last_log = t
			_log("t=%.0f road=%s s=%.0f v=%.0f fps=%.0f chunks=%d mem=%.0fMB" % [t, Game.world.roads[ap.road].name, ap.s, car.kmh(), Engine.get_frames_per_second(), main.streamer.loaded_count(), Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0])
		if ap.finished:
			break
	var mem1: float = Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0
	_log("loop finished=%s time=%.0f s distance=%.0f m avg fps=%.1f worst frame=%.1f ms mem %.0f->%.0f MB hitches(>50ms)=%d resets(falls)=%d stuck=%d chunks=%d nodes=%d" % [str(ap.finished), t, dist, frames / t, worst * 1000.0, mem0, mem1, hitches, main.reset_count, stuck_n, main.streamer.loaded_count(), Performance.get_monitor(Performance.OBJECT_NODE_COUNT)])


func _showcase() -> void:
	main.player_input.enabled = false
	Game.sky.time_frozen = true
	var hour: float = float(_arg("--qa-hour", "17.5"))
	Game.sky.set_hour(hour)
	Game.sky.set_weather(_arg("--qa-weather", "clear"), true)
	var names: Array = _arg("--qa-pois", "village").split(",")
	for nm in names:
		main.teleport_poi(nm)
		await wait(2.0)
		var car: Car = main.car
		var ap := RoadAutopilot.new(Game.world, Game.world.nearest_road_point(car.global_position).road, Game.world.nearest_road_point(car.global_position).s)
		ap.target_speed = 22.0
		var t: float = 0.0
		while t < 4.0:
			ap.update(car, 1.0 / 60.0)
			await get_tree().process_frame
			t += get_process_delta_time()
		await shot("show_%s_%s_%d" % [nm, _arg("--qa-weather", "clear"), int(hour)])


func _ui_test() -> void:
	var ui: Node = main.ui
	var con: Node = ui.console
	Game.sky.time_frozen = true
	Game.sky.set_hour(16.0)
	for cmd in ["help", "cars", "car 6", "paint lime metallic", "stripe centre black", "rims gold", "upgrade engine 3",
			"tp castle", "time 18.5", "weather cloudy", "traffic 0.8", "assist tcs off", "assist tcs on", "gears manual", "gears auto",
			"speed", "speed", "events", "tp list", "car rally", "respawn", "repair", "flip", "save", "load", "car 99", "bogus"]:
		var r: String = con.run(cmd)
		_log("console> %s => %s" % [cmd, r.replace("
", " | ").left(160)])
		await wait(0.3)
	main.teleport_poi("village")
	await wait(1.5)
	ui._toggle(ui.garage)
	await wait(0.5)
	await shot("ui_garage")
	ui._garage_select(5)
	await wait(0.2)
	await shot("ui_garage_super")
	ui._toggle(ui.garage)
	ui._toggle(ui.debug_menu)
	await wait(0.3)
	await shot("ui_debug")
	ui._toggle(ui.debug_menu)
	ui._toggle(ui.tuning)
	await wait(0.3)
	await shot("ui_tuning")
	ui._toggle(ui.tuning)
	ui._toggle(ui.map_screen)
	ui.map_screen.set_waypoint(Vector2(1750, 1540))
	await wait(0.5)
	await shot("ui_map")
	ui._toggle(ui.map_screen)
	con.toggle()
	await wait(0.3)
	await shot("ui_console")
	con.toggle()
	Game.hud.show_telemetry = true
	await wait(0.3)
	await shot("ui_telemetry")
	Game.hud.show_telemetry = false
	# photo mode
	ui._enter_photo()
	await wait(0.5)
	await shot("ui_photo")
	ui._exit_photo()
	# resolution check
	get_window().size = Vector2i(1280, 720)
	await wait(0.8)
	await shot("ui_1280x720")


func _events_test() -> void:
	# drive the autopilot through every speed trap, a speed zone and a drift zone; then run a race start
	main.player_input.enabled = false
	var am: Node = Game.activities
	var car: Car = main.car
	for e in am.events:
		if e.type != "trap" and e.type != "zone":
			continue
		var r: Dictionary = Game.world.roads[e.road]
		var s0: float = maxf(0.0, e.s - 250.0)
		var t0: Transform3D = Game.world.road_point(e.road, s0, r.lane * 0.5)
		t0.origin.y += 0.6
		main.teleport_to(t0)
		await wait(0.4)
		var ap := RoadAutopilot.new(Game.world, e.road, s0)
		ap.target_speed = 45.0
		var t: float = 0.0
		var lim: float = 30.0 if e.type == "trap" else 50.0
		var end_s: float = e.s + 20.0 if e.type == "trap" else e.s1 + 20.0
		while t < lim and ap.s < end_s:
			ap.update(car, 1.0 / 60.0)
			await get_tree().process_frame
			t += get_process_delta_time()
		_log("event %s %s: passed=%s bests=%s" % [e.type, e.name, str(ap.s >= end_s), str(Game.bests.get(e.id))])
		if e.type == "trap" and not Game.bests.has(e.id):
			await shot("event_fail_" + e.id)
	_log("activity stats %s" % str(am.stats))
	# race start + a few seconds of racing
	_log(am.start_race_by_index(1))
	await wait(4.5)
	await shot("event_race_start")
	var race_e: Dictionary = am.active.ev
	var ap2 := RoadAutopilot.new(Game.world, race_e.legs[0], 40.0)
	ap2.route = []
	for li in range(1, race_e.legs.size()):
		ap2.route.append([race_e.legs[li], 1])
	ap2.target_speed = 40.0
	var t2: float = 0.0
	while t2 < 25.0:
		ap2.update(car, 1.0 / 60.0)
		await get_tree().process_frame
		t2 += get_process_delta_time()
	await shot("event_race_running")
	_log("race state cp=%d t=%.1f rivals=%d" % [am.active.get("cp", -1), am.active.get("t", 0.0), am.rivals.size()])


func _probe(rname: String, s: float) -> void:
	main.player_input.enabled = false
	Game.settings.traffic_density = 0.0
	var ri: int = main.road_index(rname)
	var t: Transform3D = Game.world.road_point(ri, s, Game.world.roads[ri].lane * 0.5)
	t.origin.y += 0.6
	main.teleport_to(t)
	await wait(1.0)
	var car: Car = main.car
	var ap := RoadAutopilot.new(Game.world, ri, s)
	ap.target_speed = 15.0
	var tt: float = 0.0
	while tt < 6.0:
		ap.update(car, 1.0 / 60.0)
		await get_tree().process_frame
		tt += get_process_delta_time()
	_log("probe pos=%s s=%.1f v=%.1f grounded=%d contacts=%s" % [str(car.global_position), ap.s, car.kmh(), car.grounded_wheels, str(car.get_colliding_bodies().map(func(b): return b.name + ":" + str(b.get_meta("road_surface", "-")) + ":" + str(b.global_position.round()))) ])
	var q: Dictionary = Game.world.road_query(car.global_position.x, car.global_position.z)
	_log("road q=%s terrain h=%.2f" % [str(q), Game.world.height(car.global_position.x, car.global_position.z)])
	await shot("probe")
	main.camera.mode = ChaseCamera.Mode.CHASE_FAR
	await wait(0.4)
	await shot("probe_far")


func _perf(rname: String) -> void:
	main.player_input.enabled = false
	if Game.activities:
		Game.activities.process_mode = Node.PROCESS_MODE_DISABLED
	var ri: int = main.road_index(rname)
	var s_start: float = float(_arg("--qa-s", "30"))
	var t0: Transform3D = Game.world.road_point(ri, s_start, Game.world.roads[ri].lane * 0.5)
	t0.origin.y += 0.6
	main.teleport_to(t0)
	await wait(2.0)
	var car: Car = main.car
	var ap := RoadAutopilot.new(Game.world, ri, s_start)
	ap.target_speed = 45.0
	var t: float = 0.0
	var spikes: Array = []
	var frames: int = 0
	while t < 60.0 and not ap.finished:
		var dt: float = get_process_delta_time()
		ap.update(car, dt)
		var up0: int = main.streamer.stats_uploaded
		var u0: float = main.streamer.prof.upload_ms_sum
		var c0: float = main.streamer.prof.collision_ms_sum
		await get_tree().process_frame
		frames += 1
		t += dt
		if dt > 0.025 and t > 2.0:
			spikes.append("%.0fms up=%d upms=%.1f colms=%.1f proc=%.1f phys=%.1f draws=%d prims=%d" % [dt * 1000.0, main.streamer.stats_uploaded - up0, main.streamer.prof.upload_ms_sum - u0, main.streamer.prof.collision_ms_sum - c0, Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0, Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)])
	_log("perf %s frames=%d avg fps=%.1f spikes>25ms=%d prof=%s" % [rname, frames, frames / t, spikes.size(), str(main.streamer.prof)])
	_log("system max ms: " + str(Game.prof))
	_log("end s=%.0f finished=%s pos=%s" % [ap.s, str(ap.finished), str(car.global_position.round())])
	await shot("perf_end")
	for sp in spikes.slice(0, 25):
		_log("  spike " + sp)


func _save_test() -> void:
	var con: Node = main.ui.console
	for c in ["car 3", "paint teal matte", "upgrade engine 2", "time 7.5", "weather rain", "tp desert"]:
		con.run(c)
	await wait(1.0)
	var pos_saved: Vector3 = main.car.global_position
	Game.bests["test_pb"] = 123.0
	_log("save -> " + con.run("save"))
	for c in ["car 1", "time 15", "weather clear", "upgrade engine 0", "tp harbour"]:
		con.run(c)
	await wait(1.0)
	Game.upgrades.clear()
	Game.bests.clear()
	_log("load -> " + con.run("load"))
	await wait(1.5)
	var d: CarDef = main.car.def
	var p: Dictionary = Game.paint_overrides.get(d.id, {})
	_log("after load: car=%s hour=%.1f weather=%s engine_up=%d paint=%s finish=%s pb=%s dist_to_saved=%.0f m" % [d.id, Game.sky.hour, Game.sky.weather, Game.get_upgrades(d.id).engine, str(p.get("color")), str(p.get("finish")), str(Game.bests.get("test_pb")), main.car.global_position.distance_to(pos_saved)])


func _jump_test() -> void:
	main.player_input.enabled = false
	var am: Node = Game.activities
	var car: Car = main.car
	for e in am.events:
		if e.type != "jump":
			continue
		var ri: int = e.road
		var s0: float = maxf(0.0, e.s - 300.0)
		var t0: Transform3D = Game.world.road_point(ri, s0, 0.0)
		t0.origin.y += 0.6
		main.teleport_to(t0)
		await wait(0.5)
		var ap := RoadAutopilot.new(Game.world, ri, s0)
		ap.lane_offset = 0.0
		ap.target_speed = 34.0
		var t: float = 0.0
		var max_air: float = 0.0
		while t < 25.0 and ap.s < e.s + 120.0:
			ap.update(car, 1.0 / 60.0)
			car.in_throttle = 1.0 if ap.s < e.s else car.in_throttle
			car.in_brake = 0.0 if ap.s < e.s else car.in_brake
			await get_tree().process_frame
			t += get_process_delta_time()
			max_air = maxf(max_air, car.air_time)
			if absf(ap.s - e.s) < 25.0 and not am.has_meta("shot_" + e.id):
				am.set_meta("shot_" + e.id, true)
		_log("jump %s: speed at ramp area ok, max air %.2f s, best=%s, upright=%s" % [e.name, max_air, str(Game.bests.get(e.id)), str(car.global_transform.basis.y.y > 0.7)])
	_log("activity stats %s" % str(am.stats))


func _drift_test() -> void:
	main.player_input.enabled = false
	Game.settings.assist_esc = false
	Game.settings.assist_tcs = false
	main.switch_car(Game.find_car("coupe"))
	await wait(0.5)
	var am: Node = Game.activities
	var car: Car = main.car
	for e in am.events:
		if e.type != "drift":
			continue
		var r: Dictionary = Game.world.roads[e.road]
		var s0: float = maxf(0.0, e.s - 120.0)
		var t0: Transform3D = Game.world.road_point(e.road, s0, r.lane * 0.5)
		t0.origin.y += 0.6
		main.teleport_to(t0)
		await wait(0.5)
		var ap := RoadAutopilot.new(Game.world, e.road, s0)
		ap.target_speed = 22.0
		var t: float = 0.0
		var max_angle: float = 0.0
		var peak_score: float = 0.0
		var hb_t: float = 0.0
		while t < 60.0 and ap.s < e.s1 + 30.0:
			ap.update(car, 1.0 / 60.0)
			var k: float = absf(r.curv[clampi(int(ap.s / 4.0) + 6, 0, r.curv.size() - 1)])
			if k > 1.0 / 90.0 and car.kmh() > 45.0 and hb_t <= 0.0:
				hb_t = 0.35
			if hb_t > 0.0:
				hb_t -= get_process_delta_time()
				car.in_handbrake = true
				car.in_throttle = 0.6
			else:
				car.in_throttle = maxf(car.in_throttle, 0.5) if absf(car.drift_angle) > 8.0 else car.in_throttle
			await get_tree().process_frame
			t += get_process_delta_time()
			max_angle = maxf(max_angle, absf(car.drift_angle))
			if not am.active.is_empty() and am.active.ev.type == "drift":
				peak_score = maxf(peak_score, am.active.score)
		_log("drift %s: max angle %.0f deg, peak live score %.0f, best=%s" % [e.name, max_angle, peak_score, str(Game.bests.get(e.id))])
	_log("activity stats %s" % str(am.stats))
