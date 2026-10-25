extends Node
## Automated QA in a real rendering window: screenshot sequences and frame-time benchmarks.
## Usage: Godot_console.exe --path . -- --qa=shots [--set=basic] [--out=qa_out]
##        Godot_console.exe --path . -- --qa=bench [--seconds=60]

var out_dir: String = "res://qa_out"
var _frame_times: PackedFloat32Array = PackedFloat32Array()


func _ready() -> void:
	out_dir = String(Game.qa_args.get("out", "res://qa_out"))
	if not out_dir.begins_with("res://") and not out_dir.begins_with("user://"):
		out_dir = "res://" + out_dir
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	_run.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _shot(file: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := ProjectSettings.globalize_path(out_dir.path_join(file))
	img.save_png(path)
	print("[qa] saved ", path, " fps=", Engine.get_frames_per_second())


func _run() -> void:
	await _frames(30)
	var mode := String(Game.qa_args.get("qa", "shots"))
	if mode == "shots":
		await _shots(String(Game.qa_args.get("set", "basic")))
	elif mode == "bench":
		await _bench(float(Game.qa_args.get("seconds", "45")))
	elif mode == "script":
		var scr := load(String(Game.qa_args.get("script_path", ""))) as GDScript
		if scr != null:
			var n := scr.new() as Node
			add_child(n)
			await n.call("run", self)
	get_tree().quit()


func _set_view(time: float, weather: String, cam_mode: int, orbit: bool) -> void:
	var env := Game.environment as EnvironmentController
	env.set_time(time)
	env.time_frozen = true
	env.set_weather_by_name(weather)
	env.set_weather(env.weather, true)
	var rig := Game.camera_rig as CameraRig
	rig.orbit_mode = orbit
	rig.mode = cam_mode as CameraRig.Mode
	rig.snap()


func _shots(set_name: String) -> void:
	var rig := Game.camera_rig as CameraRig
	var shots: Array = []
	match set_name:
		"basic":
			shots = [
				{"file": "car_chase_day.png", "time": 11.0, "weather": "clear", "cam": 0, "orbit": false, "wait": 60},
				{"file": "car_orbit_day.png", "time": 15.5, "weather": "clear", "cam": 0, "orbit": true, "wait": 90},
				{"file": "car_cockpit.png", "time": 11.0, "weather": "clear", "cam": 3, "orbit": false, "wait": 40},
				{"file": "car_sunset.png", "time": 18.4, "weather": "cloudy", "cam": 0, "orbit": true, "wait": 120},
				{"file": "car_night.png", "time": 22.5, "weather": "clear", "cam": 0, "orbit": false, "wait": 60},
				{"file": "car_rain.png", "time": 13.0, "weather": "rain", "cam": 0, "orbit": false, "wait": 60},
			]
		"garage":
			for i in Game.car_defs.size():
				shots.append({"file": "garage_%02d.png" % (i + 1), "time": 14.0, "weather": "clear", "cam": 0, "orbit": true, "wait": 45, "car": i})
		_:
			if Game.world != null and Game.world.has_method("qa_shot_list"):
				shots = Game.world.call("qa_shot_list", set_name)
	for s in shots:
		if s.has("car"):
			Game.main.call("switch_car", int(s["car"]))
		if s.has("teleport"):
			Game.main.call("teleport", String(s["teleport"]))
		if s.has("pos"):
			var p: Vector3 = s["pos"]
			var h: Vector3 = s.get("heading", Vector3.FORWARD)
			if Game.world.has_method("prepare_area"):
				Game.world.call("prepare_area", p)
			Game.player_car.reset_to(Transform3D(Basis.looking_at(h.normalized(), Vector3.UP), p))
		_set_view(float(s.get("time", 12.0)), String(s.get("weather", "clear")), int(s.get("cam", 0)), bool(s.get("orbit", false)))
		if s.has("orbit_angle"):
			rig.orbit_angle = float(s["orbit_angle"])
		if s.has("drive"):
			Game.player_car.input_throttle = float(s["drive"])
		var ap: Node = null
		if s.get("autopilot", false) and Game.world.has_method("create_autopilot"):
			ap = Game.world.call("create_autopilot", Game.player_car)
			ap.set("max_speed_kmh", float(s.get("ap_speed", 90.0)))
			ap.set("lane_offset", float(s.get("ap_lane", 1.75)))
		await _frames(int(s.get("wait", 60)))
		if ap != null:
			ap.queue_free()
		if Game.traffic != null:
			print("[qa] traffic stats ", Game.traffic.get("stats"), " active=", Game.traffic.call("_active_count"))
		if s.has("free_cam"):
			var fc: Array = s["free_cam"]
			rig.frozen = true
			rig.camera.global_transform = Transform3D(Basis.looking_at((fc[1] as Vector3) - (fc[0] as Vector3), Vector3.UP), fc[0])
			await _frames(3)
		await _shot(String(s["file"]))
		rig.frozen = false
		Game.player_car.input_throttle = 0.0


func _bench(seconds: float) -> void:
	## Drives the player car with the world's autopilot (if any) and records frame times.
	var auto: Node = null
	if Game.world != null and Game.world.has_method("create_autopilot"):
		auto = Game.world.call("create_autopilot", Game.player_car)
	var t := 0.0
	var worst := 0.0
	var mem_start := OS.get_static_memory_usage()
	var nodes_start := Performance.get_monitor(Performance.OBJECT_NODE_COUNT)
	# engine-side timings: CPU render submission and GPU time of this viewport, script process/physics
	var vp := get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp, true)
	var gpu: Array[float] = []
	var sums := {"render_cpu": 0.0}
	var hitch_log := 0
	var prev_prof := {}
	for k in Game.prof:
		prev_prof[k] = int((Game.prof[k] as Array)[0])
	var last_us := Time.get_ticks_usec()
	while t < seconds:
		await get_tree().process_frame
		# wall clock: get_process_delta_time() is clamped to max_physics_steps_per_frame physics ticks
		var now_us := Time.get_ticks_usec()
		var dt := (now_us - last_us) / 1000000.0
		last_us = now_us
		t += dt
		if t > 3.0:
			_frame_times.append(dt * 1000.0)
			worst = maxf(worst, dt * 1000.0)
			var g := RenderingServer.viewport_get_measured_render_time_gpu(vp)
			var rc := RenderingServer.viewport_get_measured_render_time_cpu(vp) + RenderingServer.get_frame_setup_time_cpu()
			gpu.append(g)
			sums["render_cpu"] += rc
			# hitch breakdown: which profiled sections ran during this long frame
			var parts: Array = []
			for k in Game.prof:
				var tot := int((Game.prof[k] as Array)[0])
				var d := tot - int(prev_prof.get(k, 0))
				prev_prof[k] = tot
				if d > 1500:
					parts.append("%s=%.1f" % [k, d / 1000.0])
			if dt > 0.040 and hitch_log < 25:
				hitch_log += 1
				print("[hitch] t=%.1f frame=%.1fms gpu=%.1f render_cpu=%.1f %s" % [t, dt * 1000.0, g, rc, " ".join(parts)])
	var sorted := _frame_times.duplicate()
	sorted.sort()
	var n := sorted.size()
	var avg := 0.0
	for v in sorted:
		avg += v
	avg /= maxf(float(n), 1.0)
	var p99 := sorted[int(n * 0.99)] if n > 0 else 0.0
	var p95 := sorted[int(n * 0.95)] if n > 0 else 0.0
	var hitches := 0
	for v in sorted:
		if v > 33.4:
			hitches += 1
	var report := {
		"seconds": seconds, "frames": n, "avg_ms": avg, "avg_fps": 1000.0 / maxf(avg, 0.001), "p95_ms": p95, "p99_ms": p99,
		"worst_ms": worst, "frames_over_33ms": hitches, "static_mem_start_mb": mem_start / 1048576.0,
		"static_mem_end_mb": OS.get_static_memory_usage() / 1048576.0,
		"nodes_start": nodes_start, "nodes_end": Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
		"draw_calls": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
		"primitives": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME),
		"video_mem_mb": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED) / 1048576.0,
		"distance_m": auto.get("distance") if auto != null else 0.0,
	}
	gpu.sort()
	var gn := maxi(gpu.size(), 1)
	var gsum := 0.0
	for g in gpu:
		gsum += g
	report["gpu_avg_ms"] = gsum / gn
	report["gpu_p95_ms"] = gpu[int(gpu.size() * 0.95)] if not gpu.is_empty() else 0.0
	report["render_cpu_avg_ms"] = float(sums["render_cpu"]) / gn
	print("[bench] ", JSON.stringify(report))
	print("[bench] profile
", Game.prof_report())
	var f := FileAccess.open(ProjectSettings.globalize_path(out_dir.path_join("bench.json")), FileAccess.WRITE)
	f.store_string(JSON.stringify(report, "  "))
	f.close()
