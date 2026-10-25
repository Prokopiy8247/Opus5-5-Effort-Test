extends Node
## Traffic soak test: autopilot drive along the loop with traffic, periodic stats and screenshots.
##   godot --path . -- --qa=traffic_test [--secs=60]

var t := 0.0
var secs := 60.0
var next_report := 5.0
var shots := [12.0, 30.0]
var frames := PackedFloat32Array()


func _ready() -> void:
	secs = float(Game.main.arg("secs", "60"))
	Game.main.teleport_to(Game.main.find_place("road:loop:0.02"))
	Game.main.driver.car = null
	Game.settings.traffic_density = float(Game.main.arg("density", "1.0"))
	DirAccess.make_dir_recursive_absolute("res://qa/tmp/traffic")


func _process(delta: float) -> void:
	t += delta
	frames.append(delta)
	var car := Game.player
	car.in_steer = Game.world.autopilot_steer(car)
	var ped: Vector2 = Game.world.autopilot_pedals(car, 100.0)
	car.in_throttle = ped.x
	car.in_brake = ped.y
	if t >= next_report:
		next_report += 5.0
		var tm: Node = Game.traffic
		print("TRAFFIC t=%.0f active=%d stats=%s player_kmh=%.0f fps=%d" % [t, tm.active.size(), str(tm.stats), car.kmh(), Engine.get_frames_per_second()])
	if not shots.is_empty() and t >= shots[0]:
		shots.pop_front()
		_shot()
	if t >= secs:
		var sorted := frames.duplicate()
		sorted.sort()
		var avg := 0.0
		for d in frames:
			avg += d
		avg /= frames.size()
		print("FRAMES n=%d avg_ms=%.2f p99_ms=%.2f max_ms=%.2f" % [frames.size(), avg * 1000.0, sorted[int(sorted.size() * 0.99)] * 1000.0, sorted[sorted.size() - 1] * 1000.0])
		get_tree().quit(0)


func _shot() -> void:
	await RenderingServer.frame_post_draw
	var path := "res://qa/tmp/traffic/t%03d.png" % int(t)
	get_viewport().get_texture().get_image().save_png(path)
	print("SHOT ", ProjectSettings.globalize_path(path))
