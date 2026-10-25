extends Node
## Final validation (Section 15.3) in a real window: every console command, a save/load round
## trip, weather x time-of-day screenshots and a traffic count. Prints PASS/FAIL lines.
## Run: Godot_console.exe --path . --resolution 1920x1080 -- --fresh --qa=script --script_path=res://tools/tests/final_check.gd --out=qa_out/final

var fails := 0


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _check(name: String, ok: bool, detail: String = "") -> void:
	print("[final] %s %s %s" % ["PASS" if ok else "FAIL", name, detail])
	if not ok:
		fails += 1


func _cmd(line: String) -> String:
	var console: Node = Game.main.get("console")
	var parts := line.split(" ", false)
	var args: Array[String] = []
	for i in range(1, parts.size()):
		args.append(parts[i])
	var cmds: Dictionary = console.get("_commands")
	if not cmds.has(parts[0]):
		return "<missing>"
	var res = (cmds[parts[0]]["fn"] as Callable).call(args)
	return str(res) if res != null else ""


func run(qa: Node) -> void:
	# --- console
	var lines := ["help", "cars", "car 3", "car volta", "respawn", "reset", "tp", "tp canyon", "time 19.5", "weather fog",
		"weather clear", "traffic 0.8", "speed", "speed", "fps", "fps", "assist tcs off", "assist tcs on", "paint blue metallic",
		"finish gloss", "units mph", "units kmh", "pos", "camera", "upgrade engine 2", "tune", "event list", "waypoint 0 0",
		"waypoint clear", "daylength 24"]
	for l in lines:
		var out := _cmd(l)
		await _frames(5)
		_check("console '%s'" % l, out != "<missing>" and not out.to_lower().contains("unknown"), out.split("\n")[0].left(70))
	# --- save / load round trip
	_cmd("car 5")
	await _frames(20)
	(Game.environment as EnvironmentController).set_time(17.25)
	(Game.environment as EnvironmentController).set_weather_by_name("rain")
	var saved_car: String = Game.car_defs[Game.current_car_index].id
	var saved_pos := Game.player_car.global_position
	_check("save_game", bool(Game.main.call("save_game")))
	_cmd("car 1")
	(Game.environment as EnvironmentController).set_time(8.0)
	(Game.environment as EnvironmentController).set_weather_by_name("clear")
	await _frames(20)
	_check("load_game", bool(Game.main.call("load_game")))
	await _frames(30)
	var env := Game.environment as EnvironmentController
	_check("restored car", Game.car_defs[Game.current_car_index].id == saved_car, saved_car)
	_check("restored time", absf(env.time_of_day - 17.25) < 0.2, "%.2f" % env.time_of_day)
	_check("restored weather", env.weather_name() == "rain", env.weather_name())
	_check("restored position", Game.player_car.global_position.distance_to(saved_pos) < 8.0,
		"%.1f m" % Game.player_car.global_position.distance_to(saved_pos))
	# --- weather x time screenshots (Meridian GT on the scenic loop)
	_cmd("car meridian")
	_cmd("tp loop_start")
	await _frames(30)
	var rig := Game.camera_rig as CameraRig
	var looks := [[10.5, "clear"], [18.6, "clear"], [22.5, "clear"], [13.0, "rain"], [9.0, "fog"], [16.0, "storm"], [12.0, "cloudy"]]
	for k in looks.size():
		env.set_time(float(looks[k][0]))
		env.time_frozen = true
		env.set_weather_by_name(String(looks[k][1]))
		env.set_weather(env.weather, true)
		rig.orbit_mode = true
		rig.orbit_angle = 0.6 + k * 0.5
		await _frames(70)
		await qa.call("_shot", "final_%02d_%s_%02d.png" % [k, looks[k][1], int(looks[k][0])])
		_check("weather %s at %.1f h" % [looks[k][1], float(looks[k][0])], true, "grip x%.2f wet %.2f" % [Game.player_car.grip_scale, env.wetness])
	rig.orbit_mode = false
	env.set_weather_by_name("clear")
	env.set_weather(env.weather, true)
	env.set_time(12.0)
	# --- traffic
	var ap: Node = Game.world.call("create_autopilot", Game.player_car)
	ap.set("max_speed_kmh", 90.0)
	await _frames(600)
	var active := int(Game.traffic.call("_active_count")) if Game.traffic != null else 0
	_check("traffic running", active > 5, "%d vehicles active, stats %s" % [active, str(Game.traffic.get("stats"))])
	await qa.call("_shot", "final_traffic.png")
	ap.queue_free()
	print("[final] DONE fails=%d" % fails)
