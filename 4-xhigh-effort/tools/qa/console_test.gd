extends Node
## Runs every console command once and checks the state it should change.
##   godot --headless --path . -- --qa=console_test --fresh

var out := {}


func _ready() -> void:
	_run()


func _run() -> void:
	await get_tree().create_timer(1.0).timeout
	var con: Node = Game.hud.get("console")
	var checks := []
	var cmds := ["help", "help tp", "cars", "car 6", "car kestrel", "respawn", "reset", "repair", "tp highlands", "tp coast",
		"tp 100 200", "tp village", "time 21.5", "weather rain", "weather auto", "traffic 0.5", "speed", "speed", "fps", "fps",
		"coords", "coords", "telemetry", "telemetry", "assist tcs off", "assist all on", "paint #2266ff metallic", "paint red matte",
		"stripe 1 white", "upgrade engine 2", "camera hood", "camera chase", "waypoint lighthouse", "waypoint clear", "pois",
		"events", "event Expressway Radar", "bench 1", "nosuchcommand"]
	for c: String in cmds:
		con.run(c)
		await get_tree().physics_frame
		await get_tree().physics_frame
		match c:
			"car 6":
				checks.append(["car 6 -> Vortex", String(Game.cars[Game.current_car].id) == "VortexS9"])
			"car kestrel":
				checks.append(["car kestrel", String(Game.cars[Game.current_car].id) == "KestrelHatch" and String(Game.player.data.id) == "KestrelHatch"])
			"tp highlands":
				checks.append(["tp highlands", Game.player.global_position.distance_to(Vector3(-1010, 0, -1265) * Vector3(1, 0, 1) + Vector3.UP * Game.player.global_position.y) < 400.0])
			"time 21.5":
				checks.append(["time", absf(float(Game.sky.time_of_day) - 21.5) < 0.2])
			"weather rain":
				checks.append(["weather rain", String(Game.sky.weather_name()).to_lower().contains("rain")])
			"traffic 0.5":
				checks.append(["traffic density", absf(float(Game.settings.traffic_density) - 0.5) < 0.01])
			"assist tcs off":
				checks.append(["assist tcs off", not Game.player.assist_tcs])
			"assist all on":
				checks.append(["assist all on", Game.player.assist_tcs and Game.player.assist_abs])
			"paint red matte":
				checks.append(["paint", (Game.paint_for(Game.player.data.id).color as Color).r > 0.6 and int(Game.paint_for(Game.player.data.id).finish) == 2])
			"upgrade engine 2":
				checks.append(["upgrade", int(Game.upgrades_for(Game.player.data.id).engine) == 2])
			"camera hood":
				checks.append(["camera hood", Game.camera.mode == CarCamera.Mode.HOOD])
			"waypoint lighthouse":
				checks.append(["waypoint", Game.main.nav.waypoint() != Vector3.INF])
			"event Expressway Radar":
				checks.append(["event tp", Game.player.global_position.distance_to(Game.activities.find("Expressway Radar").pos) < 200.0])
	var log_label: RichTextLabel = con.get("log_box")
	var text := log_label.get_parsed_text() if log_label != null else ""
	var failed := checks.filter(func(c: Array) -> bool: return not c[1])
	out = {"commands": cmds.size(), "checks": checks.size(), "failed": failed, "unknown_reported": text.contains("nosuchcommand") or text.to_lower().contains("unknown")}
	print("CONSOLE_TEST ", JSON.stringify(out))
	get_tree().quit(0)
