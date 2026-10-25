extends Node
## Windowed visual check of effects: handbrake drift (tyre smoke + skid marks), gravel dust,
## night village (window glow, street lamps), rain, and photo mode. Saves PNGs to qa/tmp/fx.
##   godot --path . -- --qa=fx_test --fresh

const OUT := "res://qa/tmp/fx"
var mode := ""
var cap := 90.0


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	Game.main.driver.car = null
	_run()


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [OUT, name])
	print("SHOT ", name)


func _run() -> void:
	await get_tree().create_timer(2.0).timeout
	Game.sky.set_time(16.5)
	Game.sky.set_weather("clear", true)
	# 1. drift on the expressway
	Game.main.teleport_to(Game.main.find_place("road:highway:0.3"))
	mode = "auto"
	cap = 95.0
	await get_tree().create_timer(9.0).timeout
	mode = "drift"
	await get_tree().create_timer(1.3).timeout
	Game.camera.mode = CarCamera.Mode.CHASE_FAR
	await _shot("01_drift")
	mode = "brake"
	await get_tree().create_timer(2.0).timeout
	Game.camera.enabled_follow = false
	var c := Game.player.global_position
	Game.camera.global_position = c + Vector3(6, 9, 6)
	Game.camera.look_at(c - (-Game.player.global_transform.basis.z) * 8.0, Vector3.UP)
	await get_tree().create_timer(0.3).timeout
	await _shot("02_skidmarks")
	Game.camera.enabled_follow = true
	# 2. dust on gravel
	Game.main.teleport_to(Game.main.find_place("road:canyon:0.6"))
	mode = "auto"
	cap = 75.0
	await get_tree().create_timer(7.0).timeout
	await _shot("03_dust")
	# 3. night village + rain
	Game.main.teleport_to(Game.main.find_place("village"))
	mode = "brake"
	Game.sky.set_time(21.3)
	await get_tree().create_timer(3.0).timeout
	Game.camera.mode = CarCamera.Mode.CHASE_FAR
	await get_tree().create_timer(0.5).timeout
	await _shot("04_night_village")
	Game.sky.set_weather("storm", true)
	await get_tree().create_timer(3.0).timeout
	await _shot("05_night_storm")
	Game.sky.set_time(10.5)
	Game.sky.set_weather("rain", true)
	await get_tree().create_timer(3.0).timeout
	await _shot("06_rain_day")
	# 4. photo mode
	Game.sky.set_weather("clear", true)
	Game.sky.set_time(18.2)
	var ui: Node = Game.hud
	var photo: Node = ui.get("photo")
	if photo != null and photo.has_method("toggle"):
		photo.toggle()
		await get_tree().create_timer(1.0).timeout
		await _shot("07_photo_mode")
		photo.toggle()
	print("FX_TEST done")
	get_tree().quit(0)


func _physics_process(_d: float) -> void:
	var car := Game.player
	if car == null:
		return
	match mode:
		"auto":
			car.in_steer = Game.world.autopilot_steer(car)
			var ped: Vector2 = Game.world.autopilot_pedals(car, cap)
			car.in_throttle = ped.x
			car.in_brake = ped.y
			car.in_handbrake = false
		"drift":
			car.in_steer = 0.8
			car.in_throttle = 0.6
			car.in_brake = 0.0
			car.in_handbrake = true
		"brake":
			car.in_steer = 0.0
			car.in_throttle = 0.0
			car.in_brake = 1.0
			car.in_handbrake = false
