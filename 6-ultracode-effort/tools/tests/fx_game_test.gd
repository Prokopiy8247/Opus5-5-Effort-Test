extends Node
## Vehicle effects inside the real game world (needs a renderer):
##   Godot_console.exe --path <project> --resolution 1600x900 res://tools/tests/fx_game_test.tscn -- [--out=res://qa_output/fx_game] [--car=brute_68]
## Loads the main scene, sets midday, then scripts a burnout + donut at the festival start (asphalt + verge),
## a dirt/grass excursion and a rain run, screenshotting from a scripted camera.

const DT := 1.0 / 120.0

var main: Node
var cam: Camera3D
var car: CarController
var out_dir := "res://qa_output/fx_game"
var _follow := false
var _offset := Vector3(6, 3, 8)
var _world_offset := true


func _arg(key: String, default: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--" + key + "="):
			return a.substr(key.length() + 3)
	return default


func _ready() -> void:
	out_dir = _arg("out", out_dir)
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(main)
	_run.call_deferred()


func _process(delta: float) -> void:
	if _follow and car != null and is_instance_valid(car):
		var target := car.global_position + _offset
		if not _world_offset:
			var b := car.global_basis.orthonormalized()
			var flat := Vector3(b.z.x, 0, b.z.z).normalized()
			var right := Vector3(b.x.x, 0, b.x.z).normalized()
			target = car.global_position + flat * _offset.z + right * _offset.x + Vector3.UP * _offset.y
		cam.global_position = cam.global_position.lerp(target, clampf(delta * 3.0, 0.0, 1.0))
		cam.look_at(car.global_position + Vector3.UP * 0.6, Vector3.UP)


func _frames(seconds: float, step: Callable) -> void:
	var t := 0.0
	var log_t := 0.0
	while t < seconds:
		if car != Game.player_car:
			car = Game.player_car
			_strip_fx()
		step.call(t)
		await get_tree().physics_frame
		t += DT
		log_t += DT
		if log_t >= 1.0:
			log_t = 0.0
			var fx: Node = car.get_node_or_null("CarEffects")
			var st: Dictionary = fx.call("debug_state") if fx != null else {}
			print("    fps=%d gpu_ms=%.2f proc_ms=%.1f phys_ms=%.1f nodes=%d fx_us avg=%s max=%s" % [Engine.get_frames_per_second(), RenderingServer.viewport_get_measured_render_time_gpu(get_viewport().get_viewport_rid()), Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
				Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0, Performance.get_monitor(Performance.OBJECT_NODE_COUNT), st.get("cpu_us_avg", "-"), st.get("cpu_us_max", "-")])


func _strip_fx() -> void:
	if _arg("no-fx", "") != "" and car != null:
		var fx := car.get_node_or_null("CarEffects")
		if fx != null:
			fx.free()


func _road_run(road_id: String, car_id: String, kmh: float, shot_name: String, start_s := 60.0) -> void:
	var road := (Game.world as World).data.network.get_road(road_id)
	if road == null:
		print("  no road ", road_id)
		return
	var f := RoadFollower.new()
	f.setup(road, start_s, 1, road.lane_offset(1) if road.traffic else 0.0)
	f.target_speed = kmh / 3.6
	f.respect_traffic = false
	(main as Node).teleport_to({"position": f.lane_point(start_s), "forward": road.flat_tangent_at(start_s)})
	var idx := Game.find_car_index(car_id)
	if idx >= 0:
		Game.spawn_car(idx, true)
	await get_tree().create_timer(2.5).timeout
	car = Game.player_car
	_strip_fx()
	car.assist_stm = false
	_follow = true
	_world_offset = false
	_offset = Vector3(2.2, 2.3, 8.5)
	await _frames(7.0, func(_t: float) -> void: f.drive(car, DT))
	await _shot(shot_name)
	await _frames(1.4, func(t: float) -> void:
		f.drive(car, DT)
		car.in_throttle = 1.0
		car.in_handbrake = 1.0 if t < 0.35 else 0.0
		car.in_steer = clampf(car.in_steer + (-0.8 if t < 0.5 else 0.3), -1.0, 1.0))
	await _shot(shot_name + "_slide")
	car.in_handbrake = 0.0


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(out_dir.path_join(name + ".png"))
	var fx: Node = car.get_node_or_null("CarEffects")
	print("  shot %s %s fps=%d" % [name, JSON.stringify(fx.call("debug_state")) if fx else "{}", Engine.get_frames_per_second()])


func _run() -> void:
	while main.is_loading:
		await get_tree().process_frame
	(main.car_input as CarInput).enabled = false
	Game.set_time_of_day(13.0)
	if Game.env and Game.env.has_method("set_time_scale"):
		Game.set_time_scale(0.0)
	var idx := Game.find_car_index(_arg("car", "brute_68"))
	if idx >= 0:
		Game.spawn_car(idx, true)
	await get_tree().create_timer(1.5).timeout
	car = Game.player_car
	_strip_fx()
	car.assist_tcs = false
	car.assist_stm = false
	car.assist_abs = false
	cam = Camera3D.new()
	cam.fov = 62.0
	cam.far = 3000.0
	cam.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(cam)
	var b := car.global_basis.orthonormalized()
	cam.global_position = car.global_position + b.x * 9.0 + Vector3.UP * 3.5 + b.z * 4.0
	cam.make_current()
	_follow = true
	_offset = b.x * 9.0 + Vector3.UP * 3.5 + b.z * 4.0
	print("=== burnout")
	await _frames(1.0, func(_t: float) -> void:
		car.in_throttle = 1.0
		car.in_brake = 0.0
		car.in_steer = 0.0)
	print("=== donut")
	await _frames(4.5, func(_t: float) -> void:
		car.in_throttle = 1.0
		car.in_steer = -1.0)
	await _shot("game_donut")
	await _frames(1.5, func(_t: float) -> void:
		car.in_throttle = 0.0
		car.in_brake = 0.6
		car.in_steer = 0.0)
	_follow = false
	var p := car.global_position
	cam.global_position = p + Vector3(6, 9, 6)
	cam.look_at(p, Vector3.UP)
	await _frames(2.0, func(_t: float) -> void: car.in_brake = 0.3)
	await _shot("game_marks")
	print("=== dirt road")
	await _road_run(_arg("dirt", "plateau_stage"), "granite_rally", 85.0, "game_dirt")
	print("=== sand road")
	await _road_run("dune_track", "ridgeback_sx", 70.0, "game_sand")
	print("=== rain")
	Game.set_weather("rain", true)
	await get_tree().create_timer(1.0).timeout
	print("  wetness=", CarController.wetness)
	await _road_run("ring", "kestrel_r4", 105.0, "game_rain", 300.0)
	Game.set_weather("clear", true)
	print("FX_GAME_DONE")
	get_tree().quit(0)
