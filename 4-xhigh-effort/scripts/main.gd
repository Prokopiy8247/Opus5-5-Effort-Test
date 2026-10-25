extends Node3D
## Bootstraps free roam: environment, world (open world or proving ground), player car,
## camera, traffic, activities and UI. Optional QA driver via --qa=<name> user argument.

var driver: PlayerDriver
var camera: CarCamera
var world_root: Node3D
var ui_root: CanvasLayer
var use_test_track := false
var nav: Node3D
var intro_done := false
var _args := {}
var _autosave := 60.0
var _bench := {}


func _ready() -> void:
	Game.main = self
	for a: String in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		_args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	use_test_track = _args.has("test-track")
	if not use_test_track and not ResourceLoader.exists(WorldData.resolve_path()):
		await _generate_world()
	_build_environment()
	if use_test_track:
		world_root = TestTrack.new()
		world_root.name = "TestTrack"
		add_child(world_root)
	else:
		var wm := load("res://scripts/world/world_manager.gd") as GDScript
		world_root = wm.new()
		world_root.name = "World"
		add_child(world_root)
	Game.world = world_root
	camera = CarCamera.new()
	camera.name = "CarCamera"
	add_child(camera)
	Game.camera = camera
	driver = PlayerDriver.new()
	driver.name = "PlayerDriver"
	add_child(driver)
	var rewind := Rewind.new()
	rewind.name = "Rewind"
	add_child(rewind)
	var car_idx := Game.car_index_by_name(String(_args.get("car", "")))
	if car_idx >= 0:
		Game.current_car = car_idx
	var spawn: Transform3D = world_root.get_spawn()
	spawn_player(Game.current_car, spawn)
	if not use_test_track:
		nav = (load("res://scripts/world/navigation.gd") as GDScript).new()
		nav.name = "Navigation"
		add_child(nav)
		for sys: Array in [["res://scripts/traffic/traffic_manager.gd", "Traffic", "traffic"], ["res://scripts/activities/activity_manager.gd", "Activities", "activities"],
				["res://scripts/audio/audio_manager.gd", "Audio", "audio"]]:
			if ResourceLoader.exists(sys[0]):
				var node: Node = (load(sys[0]) as GDScript).new()
				node.name = sys[1]
				add_child(node)
				Game.set(sys[2], node)
		if not _args.has("qa") and not _args.has("fresh") and SaveSystem.has_save():
			SaveSystem.load_game(true)
	_build_ui()
	intro_done = true
	if not _args.has("qa"):
		Game.notify("Welcome to VALORIA", "Open Road Festival · F1 garage · F2 debug · ` console", "info")
	if _args.has("selftest"):
		# build check usable in exported games: `VALORIA.exe -- --selftest=30`
		var secs := float(_args.selftest) if String(_args.selftest).is_valid_float() and _args.selftest != "1" else 20.0
		get_tree().create_timer(secs).timeout.connect(_selftest_finish)
	if _args.has("qa"):
		# watchdog: automated runs never hang (exit code 3 on timeout or failed QA script)
		get_tree().create_timer(float(_args.get("qa-timeout", "240")), true, false, true).timeout.connect(
				func() -> void:
					push_error("QA watchdog timeout")
					get_tree().quit(3))
		var qa_script := load("res://tools/qa/%s.gd" % _args.qa) as GDScript
		if qa_script != null and qa_script.can_instantiate():
			var qa: Node = qa_script.new()
			qa.name = "QA"
			add_child(qa)
		else:
			push_error("QA script not found or invalid: " + String(_args.qa))
			get_tree().quit(3)


## First launch: bake the seeded world on a thread while showing a simple progress screen.
func _generate_world() -> void:
	var layer := CanvasLayer.new()
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.07, 0.12)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(bg)
	var lbl := Label.new()
	lbl.text = "VALORIA: Open Road Festival\nGenerating the island for the first time (about 30 s)..."
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	lbl.add_theme_font_size_override("font_size", 32)
	layer.add_child(lbl)
	add_child(layer)
	var th := Thread.new()
	th.start(func() -> void: WorldBaker.new().bake(false))
	while th.is_alive():
		await get_tree().process_frame
	th.wait_to_finish()
	layer.queue_free()


## Writes user://selftest.png (the game's own viewport) and a status line to the log, then quits.
func _selftest_finish() -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("user://selftest.png")
	var kit: Node = world_root.get("kit") if world_root != null else null
	var structures: Node = world_root.get("structures") if world_root != null else null
	var kit_n: int = (kit.get("_scenes") as Dictionary).size() if kit != null else 0
	print("SELFTEST exported=%s cars=%d kit_pieces=%d structures_placed=%d structures_missing=%s traffic_types=%d traffic_active=%d fps=%d player=%s world=%s" % [
		OS.has_feature("template"), Game.cars.size(), kit_n, int(structures.get("placed")) if structures != null else -1,
		str(structures.get("missing")) if structures != null else "?", Game.traffic.types.size() if Game.traffic != null else -1,
		Game.traffic.active.size() if Game.traffic != null else -1, Engine.get_frames_per_second(),
		String(Game.player.data.id) if Game.player != null else "none", WorldData.resolve_path()])
	get_tree().quit(0)


func arg(key: String, default: String = "") -> String:
	return String(_args.get(key, default))


func _build_environment() -> void:
	var sky_script := load("res://scripts/world/sky_weather.gd") as GDScript
	if sky_script != null:
		var sky: Node = sky_script.new()
		sky.name = "SkyWeather"
		add_child(sky)
		Game.sky = sky


func _build_ui() -> void:
	var hud_script := load("res://scripts/ui/ui_root.gd") as GDScript
	if hud_script != null:
		ui_root = hud_script.new()
		ui_root.name = "UI"
		ui_root.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(ui_root)


func spawn_player(index: int, xf: Transform3D, keep_speed := 0.0) -> CarController:
	index = clampi(index, 0, Game.cars.size() - 1)
	var data := Game.cars[index]
	var old := Game.player
	var lights := false
	if old != null and is_instance_valid(old):
		lights = old.lights_on
		old.queue_free()
		Game.player = null
	var car := CarController.new()
	car.name = "PlayerCar"
	var visual := CarVisual.new()
	visual.name = "Visual"
	car.add_child(visual)
	add_child(car)
	car.global_transform = xf
	visual.load_model(data.model_path, String(data.id))
	car.mods = Game.mods_for(data.id)
	car.tune = Game.tuning_for(data.id)
	car.setup(data, visual)
	var fx := CarFX.new()
	fx.name = "FX"
	car.add_child(fx)
	fx.setup(car)
	car.impact.connect(func(s: float, at: Vector3) -> void:
		if Game.audio != null and Game.audio.has_method("impact"):
			Game.audio.impact(s, at))
	var p := Game.paint_for(data.id)
	visual.set_paint(p.color, p.finish, p.stripe, p.stripe_color)
	visual.set_rim_color(p.rim)
	car.lights_on = lights
	car.teleport(xf.origin, -xf.basis.z, keep_speed)
	Game.current_car = index
	Game.player = car
	Game.apply_assists()
	driver.car = car
	camera.set_target(car)
	Game.player_car_changed.emit(car)
	return car


func reset_player_to_road() -> void:
	var car := Game.player
	if car == null:
		return
	var xf: Transform3D = world_root.nearest_road_transform(car.global_position)
	car.teleport(xf.origin + Vector3.UP * 0.6, -xf.basis.z, 0.0)
	Game.notify("Reset", "Back on the road", "small")


func switch_car(index: int, keep_position := true) -> void:
	var car := Game.player
	var xf := world_root.get_spawn() as Transform3D
	var spd := 0.0
	if keep_position and car != null:
		var fwd := -car.global_transform.basis.z
		fwd.y = 0.0
		xf = Transform3D(Basis.looking_at(fwd.normalized(), Vector3.UP), car.global_position + Vector3.UP * 0.5)
		spd = maxf(car.speed, 0.0)
	spawn_player(index, xf, spd)
	Game.notify(Game.cars[index].display_name, Game.cars[index].body_style + " · " + Game.cars[index].drivetrain_name(), "car")


## Re-applies upgrades and tuning to the current car without respawning it.
func apply_car_setup() -> void:
	var car := Game.player
	if car == null:
		return
	car.mods = Game.mods_for(car.data.id)
	car.tune = Game.tuning_for(car.data.id)
	car.refresh_tuning()


## Resolves a place name (region, POI id/name, "tunnel" or "road:<id>:<fraction>") to a position.
func find_place(name: String) -> Vector3:
	if use_test_track:
		return Vector3.INF
	var wd: WorldData = world_root.wd
	var low := name.to_lower().strip_edges()
	var regions := {"valley": Vector3(600, 0, 700), "verdana": Vector3(600, 0, 700), "highlands": Vector3(-1010, 0, -1265),
		"pinecrest": Vector3(-1010, 0, -1265), "mountain": Vector3(-1010, 0, -1265), "canyons": Vector3(-1500, 0, 600),
		"redmesa": Vector3(-1500, 0, 600), "desert": Vector3(-1500, 0, 600), "coast": Vector3(1500, 0, -600), "marisol": Vector3(1500, 0, -600)}
	if regions.has(low):
		return regions[low]
	if low.begins_with("road:"):
		var parts := low.split(":")
		for r: Dictionary in wd.roads:
			if String(r.id) == parts[1]:
				var pts: PackedVector3Array = r.pts
				return pts[clampi(int(float(parts[2]) * pts.size()), 0, pts.size() - 1)]
	if low == "tunnel":
		for r: Dictionary in wd.roads:
			for t: Array in r.tunnels:
				var pts: PackedVector3Array = r.pts
				return pts[maxi(int(t[0]) - 60, 0)]
	for p: Dictionary in wd.pois:
		if String(p.id).to_lower() == low or String(p.name).to_lower().contains(low):
			return p.pos
	return Vector3.INF


func teleport_to(p: Vector3) -> void:
	var xf: Transform3D = world_root.nearest_road_transform(p)
	if Game.player != null:
		Game.player.teleport(xf.origin + Vector3.UP * 0.6, -xf.basis.z, 0.0)
	camera.reset_physics_interpolation()


## Autopilot benchmark: drives the loop and reports frame-time statistics.
func start_benchmark(seconds: float) -> void:
	teleport_to(find_place("road:loop:0.05"))
	driver.car = null
	_bench = {"t": seconds, "frames": PackedFloat32Array(), "start": Game.player.global_position}
	Game.notify("Benchmark", "%d s autopilot drive" % roundi(seconds), "info")


func _process(delta: float) -> void:
	if not _bench.is_empty():
		_bench.t = float(_bench.t) - delta
		(_bench.frames as PackedFloat32Array).append(delta)
		var car := Game.player
		car.in_steer = world_root.autopilot_steer(car)
		var ped: Vector2 = world_root.autopilot_pedals(car, 120.0)
		car.in_throttle = ped.x
		car.in_brake = ped.y
		if float(_bench.t) <= 0.0:
			var fr: PackedFloat32Array = _bench.frames
			var sorted := fr.duplicate()
			sorted.sort()
			var avg := 0.0
			for d in fr:
				avg += d
			avg /= maxf(fr.size(), 1)
			var msg := "avg %.1f fps · p99 %.1f ms · max %.1f ms" % [1.0 / avg, sorted[int(sorted.size() * 0.99)] * 1000.0, sorted[sorted.size() - 1] * 1000.0]
			print("BENCHMARK ", msg, " frames=", fr.size())
			Game.notify("Benchmark done", msg, "big")
			_bench = {}
			driver.car = Game.player
	if not use_test_track and not _args.has("qa"):
		_autosave -= delta
		if _autosave <= 0.0:
			_autosave = 60.0
			SaveSystem.save_game()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and not use_test_track and not _args.has("qa"):
		SaveSystem.save_game()