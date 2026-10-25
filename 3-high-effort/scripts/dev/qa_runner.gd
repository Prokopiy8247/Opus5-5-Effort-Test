extends Node
## Automated visual/perf QA, enabled by user args after "--":
##   --qa-shots[=set]   teleport through viewpoints, save PNGs to res://qa_out/, then quit
##   --qa-perf=<sec>    drive the loop on autopilot, log frame times, then quit
##   --qa-quit=<sec>    just quit after N seconds (smoke test)

var main: Node
var out_dir := "res://qa_out/"
var _log: PackedStringArray = []


func _ready() -> void:
	main = get_parent()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--qa-shots"):
			var set_name := a.get_slice("=", 1) if a.contains("=") else "default"
			_shots(set_name)
			return
		if a.begins_with("--qa-crash"):
			_crash_test()
			return
		if a.begins_with("--qa-map"):
			_map_shots()
			return
		if a.begins_with("--qa-swapperf"):
			_swap_perf()
			return
		if a.begins_with("--qa-cars"):
			_cars_shots()
			return
		if a.begins_with("--qa-places"):
			_places_shots()
			return
		if a.begins_with("--qa-loop"):
			_loop_test()
			return
		if a.begins_with("--qa-save-write"):
			_save_write()
			return
		if a.begins_with("--qa-save-read"):
			_save_read()
			return
		if a.begins_with("--qa-events"):
			_events()
			return
		if a.begins_with("--qa-ui"):
			_ui_shots()
			return
		if a.begins_with("--qa-perf"):
			_perf(float(a.get_slice("=", 1)) if a.contains("=") else 120.0)
			return
		if a.begins_with("--qa-quit"):
			await get_tree().create_timer(float(a.get_slice("=", 1))).timeout
			_finish()
			return


func _say(s: String) -> void:
	print("[QA] " + s)
	_log.append(s)


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var p := out_dir + name + ".png"
	img.save_png(ProjectSettings.globalize_path(p))
	_say("shot %s fps=%d draws=%d prims=%d" % [name, Engine.get_frames_per_second(),
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)])


func _goto_road(road_id: String, frac: float, hour: float, weather: String, cam: int = 0) -> void:
	var w: World = main.world
	var road := w.data.road_by_id(road_id)
	if road == null:
		_say("missing road " + road_id)
		return
	var i := int(clampf(frac, 0.0, 1.0) * (road.pts.size() - 2))
	var xf := w.data.road_spawn(road, i, road.width * 0.25)
	main.teleport_player(xf)
	Game.time_of_day = hour
	w.sky.set_weather(weather, true)
	main.camera.mode = cam
	main.player.external_input = true
	main.player.in_throttle = 0.0
	main.player.in_brake = 0.0


func _shots(set_name: String) -> void:
	await _wait(3.0)
	var views: Array = [
		["spawn_chase", "festival_loop", 0.0, 10.5, "clear", 0],
		["coast_bridge", "festival_loop", 0.165, 9.0, "clear", 0],
		["hairpins", "festival_loop", 0.5, 15.0, "clear", 1],
		["desert", "mesa_run", 0.5, 17.5, "clear", 0],
		["highway", "valley_highway", 0.4, 12.0, "cloudy", 0],
		["valley_rain", "river_road", 0.5, 13.0, "rain", 0],
		["sunset_coast", "festival_loop", 0.08, 19.0, "clear", 0],
		["night_village", "river_road", 0.3, 22.5, "clear", 0],
		["fog_forest", "pinewood_gravel", 0.4, 8.0, "fog", 0],
		["cockpit", "festival_loop", 0.02, 11.0, "clear", 4],
	]
	if set_name != "default":
		views = views.filter(func(v: Array) -> bool: return (v[0] as String).begins_with(set_name))
	for v in views:
		await _goto_road(v[1], v[2], v[3], v[4], v[5])
		main.world.sky.time_frozen = true
		await _wait(2.5)
		# roll forward a bit so the camera settles behind the car
		main.player.in_throttle = 0.35
		await _wait(1.5)
		main.player.in_throttle = 0.0
		main.player.in_brake = 0.4
		await _wait(0.8)
		await _shot(v[0])
	_finish()


func _find_ui(method: String) -> Node:
	for n in main.ui.get_children():
		if n.has_method(method):
			return n
	return null


func _find_ui_script(path_end: String) -> Node:
	for n in main.ui.get_children():
		if n.get_script() and (n.get_script() as Script).resource_path.ends_with(path_end):
			return n
	return null


func _ui_shots() -> void:
	await _wait(3.0)
	main.world.sky.time_frozen = true
	Game.time_of_day = 10.5
	main.player.external_input = true
	main.player.in_throttle = 0.6
	await _wait(6.0)
	main.player.in_throttle = 0.3
	await _shot("ui_hud_drive")
	var garage := _find_ui_script("garage_menu.gd")
	garage.toggle()
	await _wait(2.0)
	await _shot("ui_garage")
	garage.list.select(5)
	garage._on_select(5)
	garage.tabs.current_tab = 1
	await _wait(0.5)
	await _shot("ui_garage_upgrades")
	garage.toggle()
	var console := _find_ui("execute")
	console.toggle()
	console._on_submit("cars")
	await _wait(0.5)
	await _shot("ui_console")
	console.toggle()
	var dbg := _find_ui_script("debug_menu.gd")
	dbg.toggle()
	await _wait(0.5)
	await _shot("ui_debug")
	dbg.toggle()
	Game.settings.traffic_density = 1.0
	var tr: TrafficManager = main.world.traffic
	await _wait(4.0)
	_say("traffic cars=%d spawned=%d" % [tr.cars.size(), tr.stats.spawned])
	# put the camera behind the nearest traffic car
	if tr.cars.size() > 0:
		var best: TrafficManager.TCar = tr.cars[0]
		for t in tr.cars:
			if t.node.global_position.distance_to(main.player.global_position) < best.node.global_position.distance_to(main.player.global_position):
				best = t
		var xf := best.node.global_transform
		main.teleport_player(Transform3D(xf.basis, xf.origin - xf.basis.z * -14.0 + Vector3.UP * 0.6))
		await _wait(3.0)
		await _shot("traffic_follow")
	_finish()


func _events() -> void:
	await _wait(3.0)
	Game.notify.connect(func(t: String, b: String, k: String) -> void: _say("NOTIFY [%s] %s — %s" % [k, t, b]))
	Game.settings.traffic_density = 0.0
	main.world.traffic.clear_all()
	var acts: Activities = main.world.activities
	var targets := acts.event_targets()
	var tests := [["valley radar", 150.0], ["highway haste", 170.0], ["crown hairpins", 70.0], ["dune leap", 95.0],
		["coast sprint", 160.0], ["festival board 2", 60.0], ["velora grand tour", 160.0]]
	var only := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--qa-events="):
			only = a.get_slice("=", 1)
	if only != "":
		tests = tests.filter(func(x: Array) -> bool: return (x[0] as String).begins_with(only))
	if only == "crown":
		main.spawn_car(3, main.player.global_transform)
	var ap_script := load("res://scripts/vehicle/autopilot.gd")
	for tcase in tests:
		var name: String = tcase[0]
		if not targets.has(name) and not name.begins_with("festival board"):
			_say("missing event target " + name)
			continue
		var p: Activities.Placed = null
		for q in acts.placed:
			if q.def.display_name.to_lower() == name:
				p = q
		if p.def.kind != EventDef.Kind.BOARD:
			main.teleport_player(targets[name])
		else:
			main.teleport_player(main.world.data.road_spawn(p.road, maxi(p.i0 - 20, 1), p.road.width * 0.25))
		await _wait(1.0)
		var ap: Node = ap_script.new()
		ap.name = "Autopilot"
		main.player.add_child(ap)
		ap.setup(main.player, main.world.data, p.road.id)
		ap.max_kmh = tcase[1]
		if p.def.kind == EventDef.Kind.RACE:
			# stop in the start box, then let the autopilot race after the countdown
			main.player.teleport(main.world.data.road_spawn(p.road, p.i0, p.road.width * 0.25))
			ap.set_physics_process(false)
			await _wait(1.5)
			ap.set_physics_process(true)
		var t := 0.0
		_say("event %s started test (running=%s)" % [name, acts.running != null])
		var max_drift := 0.0
		if p.def.kind == EventDef.Kind.JUMP:
			main.player.set_velocity_forward(30.0)
		if p.def.kind == EventDef.Kind.BOARD:
			main.player.teleport(main.world.data.road_spawn(p.road, maxi(p.i0 - 20, 1), p.road.width * 0.25))
			ap.lane = 0.55
		var limit := 1300.0 if p.def.kind == EventDef.Kind.TIME_TRIAL else 150.0
		while t < limit:
			if p.def.kind == EventDef.Kind.BOARD and p.collected:
				break
			await get_tree().physics_frame
			t += 1.0 / 120.0
			if p.def.kind == EventDef.Kind.DRIFT_ZONE:
				# provoke slides: handbrake pulses on corner entry with throttle held
				var car: Car = main.player
				car.in_handbrake = 1.0 if (absf(car.in_steer) > 0.35 and car.speed > 11.0 and fmod(t, 2.0) < 0.35) else 0.0
				if car.in_handbrake > 0.0:
					car.in_throttle = 1.0
				max_drift = maxf(max_drift, absf(car.drift_angle))
			if acts.running == null and t > 3.0 and acts._cooldown > 0.0:
				break
		_say("event %s finished after %.1f s, state=%s max_drift=%.1f score=%.0f" % [name, t, acts.state, max_drift, acts.score])
		ap.queue_free()
		main.player.external_input = false
		await _wait(0.5)
	_finish()


func _measure(label: String, secs: float) -> void:
	Game.prof.clear()
	var t := 0.0
	var frames := 0
	var t0 := Time.get_ticks_usec()
	while t < secs:
		await get_tree().process_frame
		t += get_process_delta_time()
		frames += 1
	var real := (Time.get_ticks_usec() - t0) / 1000000.0
	_say("%s: %.1f fps  nodes=%d objects=%d proc=%.1fms phys=%.1fms" % [label, frames / real, get_tree().get_node_count(),
		Performance.get_monitor(Performance.OBJECT_COUNT), Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0])
	var keys := Game.prof.keys()
	keys.sort_custom(func(a: String, b: String) -> bool: return Game.prof[a] > Game.prof[b])
	var parts: PackedStringArray = []
	for k in keys:
		parts.append("%s=%.2fms" % [k, Game.prof[k] / 1000.0 / maxf(frames, 1)])
	_say("   per-frame: " + ", ".join(parts))


func _crash_test() -> void:
	await _wait(3.0)
	Game.settings.traffic_density = 1.0
	var tr: TrafficManager = main.world.traffic
	await _wait(5.0)
	var target: TrafficManager.TCar = null
	for t in tr.cars:
		if t.state == 0 and t.speed > 5.0:
			target = t
			break
	if target == null:
		_say("CRASH no suitable traffic car (cars=%d)" % tr.cars.size())
		_finish()
		return
	var xf := target.node.global_transform
	var fwd := -xf.basis.z
	var dbg_tries := 0
	if Game.settings.traffic_density > 0.0:
		dbg_tries = 1
	main.teleport_player(Transform3D(xf.basis, xf.origin - fwd * 30.0 + Vector3.UP * 0.5))
	main.player.set_velocity_forward(target.speed + 14.0)
	main.player.external_input = true
	var t := 0.0
	var closest := INF
	while t < 8.0 and target.state == 0:
		await get_tree().physics_frame
		t += 1.0 / 120.0
		# aim straight at the traffic car
		var to: Vector3 = target.node.global_position - main.player.global_position
		var f: Vector3 = -main.player.global_transform.basis.z
		main.player.in_steer = clampf(-f.signed_angle_to(Vector3(to.x, 0, to.z).normalized(), Vector3.UP) * 3.0, -1.0, 1.0)
		main.player.in_throttle = 1.0
		closest = minf(closest, main.player.global_position.distance_to(target.node.global_position))
	_say("CRASH closest approach %.1f m, shape disabled=%s, contacts=%d" % [closest, target.shape.disabled, main.player.get_contact_count()])
	main.player.in_throttle = 0.0
	main.player.in_brake = 1.0
	await _wait(7.0)
	_say("CRASH result: traffic state=%d (0 drive,1 crashed,2 stopped) crashes=%d honk_cd=%.1f" % [target.state, tr.stats.crashes, target.honk_cd])
	_finish()


func _map_shots() -> void:
	await _wait(3.0)
	var console := _find_ui("execute")
	_say(console.execute("waypoint saltcliff light"))
	await _wait(1.0)
	_say("route points=%d length=%.0fm" % [main.route_2d.size(), main._route_length()])
	var map := _find_ui_script("map_screen.gd")
	map.toggle()
	await _wait(1.0)
	await _shot("ui_map")
	map.toggle()
	await _wait(0.5)
	main.camera.mode = 1
	await _wait(1.5)
	await _shot("gps_route")
	main.toggle_photo_mode()
	await _wait(0.5)
	main.photo.cam.global_position = main.player.global_position + Vector3(4.0, 1.2, 4.0)
	main.photo.yaw = atan2(4.0, 4.0)
	main.photo.pitch = -0.1
	await _wait(0.5)
	await _shot("photo_mode")
	main.toggle_photo_mode()
	_finish()


func _swap_perf() -> void:
	await _wait(3.0)
	await _measure("baseline", 5.0)
	var xf: Transform3D = main.player.global_transform
	for k in 3:
		for i in Game.cars.size():
			main.spawn_car(i, xf)
			await _wait(0.3)
		await _measure("after swap round %d" % (k + 1), 5.0)
	_finish()


func _cars_shots() -> void:
	await _wait(3.0)
	Game.settings.traffic_density = 0.0
	main.world.traffic.clear_all()
	main.world.sky.time_frozen = true
	Game.time_of_day = 15.0
	var xf: Transform3D = main.player.global_transform
	for i in Game.cars.size():
		main.spawn_car(i, xf)
		main.player.teleport(xf)
		main.camera.orbit = true
		main.camera._orbit_angle = 2.3
		await _wait(2.2)
		await _shot("car_%02d_%s" % [i + 1, Game.cars[i].id])
		_say("car %s mass=%.0f wheels=%d grounded=%d" % [Game.cars[i].id, main.player.mass, main.player.wheels.size(), main.player.wheels_on_ground])
	main.camera.orbit = false
	_finish()


func _places_shots() -> void:
	await _wait(3.0)
	var console := _find_ui("execute")
	main.world.sky.time_frozen = true
	for name in ["velora festival", "meadowmere", "saltcliff harbour", "mesa fuel", "saltcliff light", "ravenhold ruins",
			"brightmoor wind farm", "tunnel", "bay bridge", "valley radar", "dune leap"]:
		_say(console.execute("tp " + name))
		Game.time_of_day = 16.5 if name != "meadowmere" else 20.8
		main.camera.mode = 1
		await _wait(2.0)
		main.player.external_input = true
		main.player.in_throttle = 0.3
		await _wait(1.2)
		main.player.in_throttle = 0.0
		main.player.in_brake = 0.5
		await _wait(1.0)
		main.player.in_brake = 0.0
		await _shot("place_" + name.replace(" ", "_"))
	_finish()


func _loop_test() -> void:
	await _wait(2.0)
	var ap: Node = load("res://scripts/vehicle/autopilot.gd").new()
	ap.name = "Autopilot"
	main.player.add_child(ap)
	ap.setup(main.player, main.world.data, "festival_loop")
	ap.max_kmh = 150.0
	var t := 0.0
	var vmax := 0.0
	var min_clear := INF
	var below := 0
	var resets := 0
	var last_stuck := 0.0
	var dist := 0.0
	var last: Vector3 = main.player.global_position
	while t < 1500.0 and ap.laps < 1:
		await get_tree().physics_frame
		t += 1.0 / Engine.physics_ticks_per_second
		var p: Vector3 = main.player.global_position
		dist += p.distance_to(last)
		last = p
		vmax = maxf(vmax, main.player.speed_kmh)
		var ground: float = main.world.height_at(p.x, p.z)
		var nr: Dictionary = main.world.data.nearest_road(p, 10.0)
		var surf_y := ground
		if not nr.is_empty():
			surf_y = maxf(surf_y, (nr.point as Vector3).y) if (nr.road as WorldData.Road).flags[nr.seg] != 2 else (nr.point as Vector3).y
		var clear := p.y - surf_y
		min_clear = minf(min_clear, clear)
		if clear < -2.0:
			below += 1
		if p.y < -50.0:
			_say("FELL OUT OF WORLD at %s" % p)
			break
		if int(t) % 60 == 0 and int(t) != int(last_stuck):
			last_stuck = t
			_say("loop t=%.0fs dist=%.0fm idx=%d speed=%.0f" % [t, dist, int(ap.idx), main.player.speed_kmh])
	_say("LOOP laps=%d time=%.1fs dist=%.0fm avg=%.1fkmh vmax=%.0fkmh min_clearance=%.2f frames_below_surface=%d" % [ap.laps, t, dist, dist / maxf(t, 1.0) * 3.6, vmax, min_clear, below])
	_finish()


func _save_write() -> void:
	await _wait(2.0)
	main.spawn_car(4, main.player.global_transform)
	var c := Game.custom_for(Game.cars[4].id)
	c["color"] = Color(0.1, 0.3, 0.85)
	c["finish"] = "matte"
	c["upgrades"] = {"engine": 2}
	Game.time_of_day = 18.25
	main.world.sky.set_weather("rain", true)
	Game.personal_bests["event_qa_probe"] = 123.0
	Game.save_game()
	_say("SAVE_WRITE car=%s time=%.2f weather=%s pos=%s" % [Game.cars[Game.current_car_index].id, Game.time_of_day, Game.weather_name, main.player.global_position])
	_finish()


func _save_read() -> void:
	await _wait(2.0)
	var c := Game.custom_for(Game.cars[Game.current_car_index].id)
	_say("SAVE_READ car=%s time=%.2f weather=%s pos=%s color=%s finish=%s upgrades=%s pb=%s" % [Game.cars[Game.current_car_index].id,
		Game.time_of_day, Game.weather_name, main.player.global_position, c.get("color"), c.get("finish"), c.get("upgrades"),
		Game.personal_bests.get("event_qa_probe")])
	_finish()


func _perf(seconds: float) -> void:
	await _wait(2.0)
	var ap_script := load("res://scripts/vehicle/autopilot.gd")
	var ap: Node = null
	if ap_script:
		ap = ap_script.new()
		ap.name = "Autopilot"
		main.player.add_child(ap)
		ap.setup(main.player, main.world.data, "festival_loop")
	var t := 0.0
	var frames := 0
	var worst := 0.0
	var times := PackedFloat32Array()
	var start_mem := OS.get_static_memory_usage()
	var start_pos: Vector3 = main.player.global_position
	var dist := 0.0
	var last := start_pos
	var min_y := INF
	while t < seconds:
		await get_tree().process_frame
		var dt := get_process_delta_time()
		t += dt
		frames += 1
		times.append(dt)
		worst = maxf(worst, dt)
		var p: Vector3 = main.player.global_position
		dist += p.distance_to(last)
		last = p
		var ground: float = main.world.height_at(p.x, p.z)
		min_y = minf(min_y, p.y - ground)
		if frames % 600 == 0:
			_say("t=%.0f fps=%d dist=%.0fm speed=%.0fkmh laps=%d near_chunks=%d nodes=%d mem=%.0fMB proc=%.1fms phys=%.1fms draws=%d traffic=%d" % [t, Engine.get_frames_per_second(),
				dist, main.player.speed_kmh, ap.laps if ap else 0, main.world.terrain.near_chunk_count(), get_tree().get_node_count(),
				OS.get_static_memory_usage() / 1048576.0, Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
				Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
				RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
				(main.world.traffic as TrafficManager).cars.size()])
	times.sort()
	var avg := t / frames
	var p99 := times[int(times.size() * 0.99)]
	_say("PERF frames=%d avg_ms=%.2f avg_fps=%.1f p99_ms=%.2f worst_ms=%.2f dist=%.0fm mem_start=%.0fMB mem_end=%.0fMB min_clearance=%.2f" % [
		frames, avg * 1000.0, 1.0 / avg, p99 * 1000.0, worst * 1000.0, dist, start_mem / 1048576.0,
		OS.get_static_memory_usage() / 1048576.0, min_y])
	_finish()


func _finish() -> void:
	var fa := FileAccess.open(out_dir + "qa_log.txt", FileAccess.WRITE)
	if fa:
		fa.store_string("\n".join(_log))
	get_tree().quit()
