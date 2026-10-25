extends Node
## Windowed screenshot tour. Run:
##   godot --path . -- --qa=screens [--test-track] [--shots=chase,hood,cockpit,bumper] [--drive=1]
##       [--out=qa/tmp] [--time=17.5] [--weather=clear] [--warmup=3.0] [--tp=x,z]
## Saves PNGs and prints frame-time statistics, then quits.

var drive := false
var measuring := false
var fps_samples: PackedFloat32Array = []


func _ready() -> void:
	var main: Node = Game.main
	var shots: PackedStringArray = String(main.arg("shots", "chase,hood,cockpit,bumper")).split(",")
	var out_dir: String = "res://" + String(main.arg("out", "qa/tmp"))
	drive = String(main.arg("drive")) != ""
	DirAccess.make_dir_recursive_absolute(out_dir)
	if String(main.arg("tp")) != "" and Game.world.has_method("transform_near"):
		var p: PackedStringArray = String(main.arg("tp")).split(",")
		var xf: Transform3D = Game.world.transform_near(Vector3(float(p[0]), 0, float(p[1])))
		Game.player.teleport(xf.origin + Vector3.UP * 0.5, -xf.basis.z, 0.0)
	if Game.sky != null and String(main.arg("time")) != "" and Game.sky.has_method("set_time"):
		Game.sky.set_time(float(main.arg("time")))
	if Game.sky != null and String(main.arg("weather")) != "" and Game.sky.has_method("set_weather"):
		Game.sky.set_weather(String(main.arg("weather")), true)
	if drive:
		main.driver.car = null
	_run(shots, out_dir, float(main.arg("warmup", "3.0")))


func _run(shots: PackedStringArray, out_dir: String, warmup: float) -> void:
	await get_tree().create_timer(warmup).timeout
	measuring = true
	for i in shots.size():
		var s := shots[i]
		var cam := Game.camera
		cam.enabled_follow = true
		match s:
			"chase":
				cam.mode = CarCamera.Mode.CHASE_NEAR
			"far":
				cam.mode = CarCamera.Mode.CHASE_FAR
			"hood":
				cam.mode = CarCamera.Mode.HOOD
			"cockpit":
				cam.mode = CarCamera.Mode.COCKPIT
			"bumper":
				cam.mode = CarCamera.Mode.BUMPER
			"garage", "map", "console", "debug":
				var ui: Node = Game.hud
				var target: Node = {"garage": ui.get("garage"), "map": ui.get("map_screen"), "console": ui.get("console"), "debug": ui.get("debug")}[s]
				target.call("toggle")
				if s == "console":
					target.call("run", "cars")
				await get_tree().create_timer(1.5).timeout
				await RenderingServer.frame_post_draw
				var img2 := get_viewport().get_texture().get_image()
				img2.save_png("%s/%02d_%s.png" % [out_dir, i, s])
				print("SHOT ", ProjectSettings.globalize_path("%s/%02d_%s.png" % [out_dir, i, s]))
				target.call("toggle")
				continue
			_:
				_place_orbit(s)
		await get_tree().create_timer(0.8).timeout
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		var path := "%s/%02d_%s.png" % [out_dir, i, s]
		img.save_png(path)
		print("SHOT ", ProjectSettings.globalize_path(path))
	Game.camera.enabled_follow = true
	_report()
	if Game.audio != null and Game.audio.get("stats") != null:
		var st: Dictionary = Game.audio.stats
		print("AUDIO samples_ms=%d engine_synth_us_per_s=%.0f" % [st.sample_gen_ms, float(st.fill_us) / maxf(float(st.fill_frames) / 22050.0, 0.001)])
	get_tree().quit(0)


func _process(delta: float) -> void:
	if measuring:
		fps_samples.append(delta)
	if drive and Game.player != null:
		if Game.world.has_method("autopilot_steer"):
			Game.player.in_steer = Game.world.autopilot_steer(Game.player)
			var ped: Vector2 = Game.world.autopilot_pedals(Game.player, 90.0)
			Game.player.in_throttle = ped.x
			Game.player.in_brake = ped.y


func _place_orbit(kind: String) -> void:
	var cam := Game.camera
	cam.enabled_follow = false
	var car := Game.player
	var xf := car.get_global_transform_interpolated()
	var off := Vector3(5.2, 1.5, 0.0)
	if kind.begins_with("traffic") and Game.traffic != null:
		# frame the n-th nearest civilian car (traffic, traffic2, ...)
		var cars: Array = Game.traffic.active.duplicate()
		cars.sort_custom(func(a: Node3D, b: Node3D) -> bool:
			return a.global_position.distance_squared_to(xf.origin) < b.global_position.distance_squared_to(xf.origin))
		var n := maxi(int(kind.trim_prefix("traffic")) - 1, 0) if kind != "traffic" else 0
		if cars.size() > n:
			var t: Node3D = cars[n]
			var tx := t.global_transform
			cam.global_position = tx * Vector3(4.5, 2.2, -8.0)
			cam.look_at(tx.origin + Vector3.UP * 1.0, Vector3.UP)
			cam.fov = 55.0
			print("TRAFFIC_SHOT ", t.name, " ", t.get("ttype").id if t.get("ttype") != null else "?")
			return
	match kind:
		"front":
			off = Vector3(0.0, 1.3, -6.5)
		"front34":
			off = Vector3(4.2, 1.4, -4.8)
		"rear34":
			off = Vector3(-4.2, 1.6, 5.0)
		"top":
			off = Vector3(0.5, 9.0, 0.5)
		"aerial", "aerial_l", "aerial_r":
			# elevated view over the car towards what lies ahead (or to one side)
			var side := {"aerial": 0.0, "aerial_l": -1.0, "aerial_r": 1.0}[kind] as float
			var look := xf.origin + (xf.basis * Vector3(side * 45.0, 0.0, -35.0 * (1.0 - absf(side) * 0.6)))
			cam.global_position = xf * Vector3(-side * 20.0, 26.0, 30.0 * (1.0 - absf(side) * 0.5))
			cam.look_at(look, Vector3.UP)
			cam.fov = 60.0
			return
	cam.global_position = xf * off
	cam.look_at(xf.origin + Vector3.UP * 0.6, Vector3.UP)
	cam.fov = 50.0


func _report() -> void:
	var sorted := fps_samples.duplicate()
	sorted.sort()
	var n := sorted.size()
	if n == 0:
		return
	var avg := 0.0
	for d in sorted:
		avg += d
	avg /= n
	print("FRAMES n=%d avg_ms=%.2f p50_ms=%.2f p95_ms=%.2f p99_ms=%.2f max_ms=%.2f fps_avg=%.1f" % [
		n, avg * 1000.0, sorted[n / 2] * 1000.0, sorted[int(n * 0.95)] * 1000.0, sorted[int(n * 0.99)] * 1000.0,
		sorted[n - 1] * 1000.0, 1.0 / avg])
	print("RENDER draw_calls=%d objects=%d primitives=%d vram_mb=%.0f" % [
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME),
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME),
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED) / 1048576.0])
