class_name AutoTest
extends Node
## Scripted QA driven from the command line:
##   godot --path . -- --shots=<dir>      take a set of screenshots and quit
##   godot --path . -- --drivetest        run handling tests for every car and quit
##   godot --path . -- --lap              drive the full loop on autopilot, log perf
## Inputs are written straight into the Car, bypassing the InputMap.

var main: Node
var args: Dictionary = {}
var autopilot := false
var ap_target_kmh := 140.0
var ap_road := 0

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=")
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	if args.is_empty(): return
	await get_tree().create_timer(0.5).timeout
	main = Game.main
	main.menus.process_mode = Node.PROCESS_MODE_DISABLED
	if args.has("shots"): await _shots(args.shots)
	if args.has("drivetest"): await _drivetest()
	if args.has("lap"): await _lap()
	if args.has("aptest"): await _aptest()
	if args.has("functest"): await _functest()
	if args.has("carshots"): await _carshots(args.carshots)
	get_tree().quit()

func _wait(t: float) -> void:
	await get_tree().create_timer(t).timeout

func _shot(dir: String, name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(dir.path_join(name + ".png"))
	print("[shot] ", name)

func _physics_process(_dt: float) -> void:
	if not autopilot or main == null: return
	var car: Car = main.player
	var w: WorldGen = main.world
	var p := car.global_position
	var rs := w.raster_sample(p.x, p.z)
	if rs.z < 0: return
	var ri := int(rs.z)
	var idx := int(rs.w)
	var fwd := -car.global_basis.z
	var dir_sign := 1 if w.road_dir(ri, idx).dot(fwd) >= 0.0 else -1
	var look := clampi(int(6 + absf(car.speed) * 0.35), 6, 30)
	var target := w.road_point(ri, idx + look * dir_sign)
	var right_v := w.road_dir(ri, idx + look * dir_sign).cross(Vector3.UP).normalized() * float(dir_sign)
	target += right_v * w.roads[ri].width * 0.22
	var to := target - p
	var local := car.global_basis.inverse() * to
	var ang := atan2(local.x, -local.z)
	car.in_steer = clampf(ang * 2.2, -1.0, 1.0)
	# corner speed from curvature ahead
	var want := ap_target_kmh / 3.6
	for k in [8, 16, 28, 44]:
		var c := absf(w.roads[ri].curv[posmod(idx + k * dir_sign, w.roads[ri].pts.size())])
		if c > 0.0004: want = minf(want, sqrt(7.0 / c))
	var err := want - car.speed
	car.in_throttle = clampf(err * 0.5, 0.0, 1.0)
	car.in_brake = clampf(-err * 0.3, 0.0, 1.0) if err < -2.0 else 0.0
	car.in_handbrake = false

func _shots(dir: String) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	main.set_physics_process(false)
	var list := [
		["vale_noon", "tp village", 13.0, "clear", 0],
		["vale_chase_drive", "tp vale", 9.5, "clear", 0],
		["highpine", "tp switchbacks", 11.0, "clear", 1],
		["mesa", "tp mesa", 16.5, "clear", 0],
		["coast_sunset", "tp coast", 18.8, "clear", 1],
		["highway_rain", "tp highway", 12.0, "rain", 0],
		["night", "tp village", 22.5, "clear", 0],
		["fog", "tp pinecut", 8.0, "fog", 0],
		["cockpit", "tp loop", 14.0, "cloudy", 3],
		["harbour", "tp harbour", 15.0, "clear", 1],
	]
	if args.has("only"):
		list = list.filter(func(x: Array) -> bool: return (x[0] as String).contains(args.only))
	for s in list:
		main.exec(s[1]); main.exec("time %s" % s[2]); main.exec("weather " + s[3])
		main.sky.set_weather(s[3], true)
		main.cam.mode = s[4]
		autopilot = true
		ap_target_kmh = 90.0
		await _wait(4.0)
		autopilot = false
		await _wait(0.3)
		await _shot(dir, s[0])
	# garage menu + console overlay shots
	main.menus.process_mode = Node.PROCESS_MODE_INHERIT
	main.menus.toggle_garage()
	await _wait(0.5)
	await _shot(dir, "garage")
	main.menus.toggle_garage()
	main.menus.toggle_console()
	main.menus.log_line(main.exec("cars"))
	await _wait(0.3)
	await _shot(dir, "console")
	main.menus.toggle_console()
	main.menus.toggle_debug()
	await _wait(0.3)
	await _shot(dir, "debug")
	main.menus.toggle_debug()
	main.hud.minimap.full = true
	Hud._at(main.hud.minimap, Control.PRESET_FULL_RECT, Vector2(80, 60), Vector2(0, 0))
	main.hud.minimap.offset_right = -80; main.hud.minimap.offset_bottom = -60
	await _wait(0.3)
	await _shot(dir, "map")

const PAD_Y := 900.0

func _make_pad() -> void:
	# flat asphalt test pad high above the map: 6 km straight + 600 m skidpad
	var body := StaticBody3D.new()
	body.set_meta("surface", WorldGen.Surface.ASPHALT)
	for sz in [[Vector3(40, 2, 6000), Vector3(0, PAD_Y - 1.0, -2800)], [Vector3(600, 2, 600), Vector3(0, PAD_Y - 1.0, 500)]]:
		var cs := CollisionShape3D.new()
		var bx := BoxShape3D.new(); bx.size = sz[0]
		cs.shape = bx; cs.position = sz[1]
		body.add_child(cs)
	main.add_child(body)

func _place(car_i: int, at: Vector3) -> Car:
	main.exec("car %d" % (car_i + 1))
	var car: Car = main.player
	car.reset_to(Transform3D(Basis.IDENTITY, at + Vector3.UP * 0.8))
	car.in_throttle = 0.0; car.in_brake = 0.0; car.in_steer = 0.0; car.in_handbrake = false
	for k in 60: await get_tree().physics_frame
	return car

func _hold_heading(car: Car) -> void:
	var f := -car.global_basis.z
	car.in_steer = clampf(-f.x * 3.0 + car.global_position.x * -0.05, -1.0, 1.0)

func _drivetest() -> void:
	main.set_physics_process(false)
	main.exec("traffic 0")
	main.sky.set_weather("clear", true)
	_make_pad()
	var out := "| Car | Class | 0-100 km/h (s) | 0-200 km/h (s) | Top speed (km/h, 60 s) | 100-0 braking (m) | Skidpad (g) | Stable at top |
|---|---|---|---|---|---|---|---|
"
	var from := int(args.get("from", "1")) - 1
	for i in range(from, Game.cars.size()):
		var car := await _place(i, Vector3(0, PAD_Y, 0))
		var t := 0.0; var t100 := -1.0; var t200 := -1.0; var top := 0.0; var stable := true
		while t < 60.0:
			await get_tree().physics_frame
			t += get_physics_process_delta_time()
			car.in_throttle = 1.0
			_hold_heading(car)
			var kmh := absf(car.speed) * 3.6
			top = maxf(top, kmh)
			if t100 < 0.0 and kmh >= 100.0: t100 = t
			if t200 < 0.0 and kmh >= 200.0: t200 = t
			if args.has("dbg") and fmod(t, 3.0) < get_physics_process_delta_time():
				print("[dbg] t=%.0f kmh=%.0f gear=%d rpm=%.0f F=%.0f tcs=%s slip=%.2f loads=%.0f,%.0f,%.0f,%.0f" % [t, kmh, car.gear, car.rpm, car._engine_force(), car.tcs_active, car.max_slip, car.wheels[0].load, car.wheels[1].load, car.wheels[2].load, car.wheels[3].load])
			if kmh > 150.0 and (absf(car.angular_velocity.y) > 0.6 or car.global_basis.y.y < 0.9): stable = false
		# braking from 100
		car = await _place(i, Vector3(0, PAD_Y, 0))
		while absf(car.speed) * 3.6 < 100.0:
			await get_tree().physics_frame
			car.in_throttle = 1.0; _hold_heading(car)
		car.in_throttle = 0.0; car.in_brake = 1.0
		var start := car.global_position
		var tt := 0.0
		while absf(car.speed) > 0.3 and tt < 10.0:
			await get_tree().physics_frame
			tt += get_physics_process_delta_time(); _hold_heading(car)
		var brake_d := car.global_position.distance_to(start)
		car.in_brake = 0.0
		# skidpad: hold ~55 km/h with partial lock on the big pad, measure steady lateral g
		car = await _place(i, Vector3(0, PAD_Y, 700))
		var acc_g := 0.0; var samples := 0
		tt = 0.0
		while tt < 14.0:
			await get_tree().physics_frame
			var dt := get_physics_process_delta_time()
			tt += dt
			var kmh := absf(car.speed) * 3.6
			car.in_throttle = clampf((55.0 - kmh) * 0.08, 0.0, 1.0)
			car.in_steer = 0.0 if tt < 3.0 else 0.75
			if tt > 8.0:
				var v := car.linear_velocity
				acc_g += v.length() * absf(car.angular_velocity.y) / 9.81; samples += 1
		car.in_steer = 0.0; car.in_throttle = 0.0
		var line := "| %s | %s | %s | %s | %d | %.1f | %.2f | %s |
" % [car.spec.display_name, car.spec.class_rating(), ("%.1f" % t100) if t100 > 0 else "n/a", ("%.1f" % t200) if t200 > 0 else "n/a", int(top), brake_d, acc_g / maxi(samples, 1), "yes" if stable else "NO"]
		print("[drivetest] ", line.strip_edges())
		out += line
	var f := FileAccess.open("res://drivetest_results.md", FileAccess.WRITE if from == 0 else FileAccess.READ_WRITE)
	if from > 0:
		f.seek_end()
		out = out.substr(out.find("|---|---|---|---|---|---|---|---|") + 34)
	f.store_string(out)

func _lap() -> void:
	main.set_physics_process(false)
	main.exec("tp loop")
	main.exec("car 5")
	main.exec("tp loop")
	main.exec("traffic 0.6")
	await _wait(1.0)
	autopilot = true; ap_target_kmh = float(args.get("kmh", "160"))
	var car: Car = main.player
	var t := 0.0
	var dist := 0.0
	var last := car.global_position
	var fps_min := 1e9; var fps_sum := 0.0; var frames := 0
	var falls := 0
	var max_t := float(args.get("seconds", "900"))
	var mem0 := Performance.get_monitor(Performance.MEMORY_STATIC)
	var report_t := 0.0
	var worst_frame := 0.0
	var stuck_t := 0.0
	var stuck_n := 0
	while t < max_t and dist < 20500.0:
		await get_tree().process_frame
		var dt := get_process_delta_time()
		t += dt; report_t += dt
		worst_frame = maxf(worst_frame, dt)
		var p := car.global_position
		dist += Vector2(p.x - last.x, p.z - last.z).length()
		last = p
		var fps := Engine.get_frames_per_second()
		if t > 3.0:
			fps_min = minf(fps_min, fps); fps_sum += fps; frames += 1
		if p.y < -20.0: falls += 1
		if report_t > 30.0:
			report_t = 0.0
			print("[lap] t=%d dist=%.0f m fps=%d chunks=%d traffic=%d mem=%.0fMB pos=%s" % [t, dist, fps, main.terrain.chunks.size(), main.traffic.active.size(), Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0, p])
		stuck_t = stuck_t + dt if absf(car.speed) < 2.0 else 0.0
		if stuck_t > 4.0:
			# stuck: log the spot, then respawn further along the loop
			stuck_t = 0.0
			stuck_n += 1
			print("[lap] STUCK at ", p, " speed ", car.speed)
			await _shot(OS.get_user_data_dir(), "stuck_%d" % stuck_n)
			var rs: Vector4 = main.world.raster_sample(p.x, p.z)
			car.reset_to(main.spawn_transform(0, int(rs.w) + 15 if rs.z == 0 else 30))
	print("[lap] done: %.0f s, %.0f m, avg fps %.1f, min fps %d, worst frame %.1f ms, stuck %d, falls %d, mem growth %.1f MB" % [t, dist, fps_sum / maxi(frames, 1), fps_min, worst_frame * 1000.0, stuck_n, falls, (Performance.get_monitor(Performance.MEMORY_STATIC) - mem0) / 1048576.0])

func _aptest() -> void:
	main.set_physics_process(false)
	main.exec("tp loop")
	await _wait(0.5)
	autopilot = true; ap_target_kmh = 100.0
	var car: Car = main.player
	for k in 20:
		await _wait(1.0)
		var p := car.global_position
		var rs: Vector4 = main.world.raster_sample(p.x, p.z)
		var c: Vector3 = main.world.road_point(int(rs.z), int(rs.w))
		var d: Vector3 = main.world.road_dir(int(rs.z), int(rs.w))
		var lat := (p - c).dot(d.cross(Vector3.UP).normalized())
		print("[ap] t=%d kmh=%d gear=%d rpm=%d lat=%.2f steer=%.2f thr=%.2f road=%d" % [k, int(car.speed * 3.6), car.gear, int(car.rpm), lat, car.in_steer, car.in_throttle, int(rs.z)])

func _carshots(dir: String) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	main.set_physics_process(false)
	main.exec("tp highway"); main.exec("time 11"); main.exec("traffic 0")
	main.sky.set_weather("clear", true)
	var only := int(args.get("car", "0"))
	for i in Game.cars.size():
		if only > 0 and i + 1 != only: continue
		main.exec("car %d" % (i + 1))
		main.exec("tp highway")
		var car: Car = main.player
		car.in_handbrake = true
		await _wait(1.5)
		main.cam.mode = 0
		main.cam.photo = true
		var c: Vector3 = car.global_position
		var side := car.global_basis.x
		var fwd := -car.global_basis.z
		main.cam.global_position = c + side * 4.5 + fwd * 3.2 + Vector3.UP * 1.6
		main.cam.look_at(c + Vector3.UP * 0.6, Vector3.UP)
		main.cam.fov = 55.0
		await _wait(0.2)
		await _shot(dir, "car%02d_front" % (i + 1))
		main.cam.global_position = c - side * 4.0 - fwd * 4.5 + Vector3.UP * 1.8
		main.cam.look_at(c + Vector3.UP * 0.6, Vector3.UP)
		await _wait(0.2)
		await _shot(dir, "car%02d_rear" % (i + 1))
		main.cam.photo = false
		main.cam.mode = 3
		await _wait(0.3)
		print("[cockpit] cam ", main.cam.global_position, " car ", c, " lp ", car.cockpit_pos)
		await _shot(dir, "car%02d_cockpit" % (i + 1))
		main.cam.mode = 0

func _functest() -> void:
	main.set_physics_process(false)
	var ev: EventManager = main.events
	Game.notify.connect(func(t: String, _k: String) -> void: print("[toast] ", t))
	# drive through each road event from 60 samples before its start gate
	for e in ev.events:
		if e.type == "trial": continue
		if args.has("only") and e.type != args.only and not (args.only as String).contains(e.type): continue
		var start: int = maxi(int(e.a) - (60 if e.type != "jump" else 70), 1)
		main.player.reset_to(main.spawn_transform(e.road, start))
		main.terrain.focus = main.player.global_position
		main.terrain.update_stream(true)
		await _wait(0.5)
		autopilot = true
		ap_target_kmh = 130.0 if e.type != "drift" else 70.0
		var span: int = int(e.b) - int(e.a)
		var limit := 25.0 + span * 4.0 / 15.0
		var t := 0.0
		while t < minf(limit, 70.0):
			await get_tree().physics_frame
			t += get_physics_process_delta_time()
			if e.type == "drift": main.player.in_handbrake = fmod(t, 1.5) < 0.25
		main.player.in_handbrake = false
		print("[func] %s %s best=%s" % [e.type, e.name, str(Game.personal_bests.get(e.name, "-"))])
		ev.cancel_all()
	autopilot = false
	print("[func] traffic active: ", main.traffic.active.size())
	main.exec("weather rain"); main.sky.set_weather("rain", true)
	await _wait(1.0)
	print("[func] rain grip factor ", main.sky.grip_factor)
	main.exec("car 7"); main.exec("paint blue"); main.exec("upgrade engine 2")
	main.save_state()
	main.exec("car 1")
	print("[func] ", main.exec("load"), " -> car ", main.player.spec.display_name, " engine stage ", main.player.upgrades.engine, " paint ", main.player.paint_mat.albedo_color)
