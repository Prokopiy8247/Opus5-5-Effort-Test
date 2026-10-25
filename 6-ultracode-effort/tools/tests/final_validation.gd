extends Node
## Section 15.3 validation inside the real game (needs a renderer):
##   Godot_console.exe --path <project> --resolution 1920x1080 res://tools/tests/final_validation.tscn [-- --shots=res://docs/screenshots/final]
## Checks spawn-on-road, the console, all cars drivable with their Blender model, traffic, weather + time of day,
## and a save/load round trip. The user's save file and settings are backed up and restored.
## Prints "[final] PASS|FAIL <check>" lines and "[final] failures: N".

var main: Node
var fails := 0
var shots := ""
var _save_backup: Variant = null
var _settings_backup := {}


func _arg(key: String, default: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--" + key + "="):
			return a.substr(key.length() + 3)
	return default


func _ready() -> void:
	shots = _arg("shots", "")
	if shots != "":
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(shots))
	if FileAccess.file_exists(SaveGame.PATH):
		_save_backup = FileAccess.get_file_as_string(SaveGame.PATH)
	for k: String in ["traffic_density", "braking_line"]:
		_settings_backup[k] = Settings.get_value(k)
	SaveGame.enabled = false
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(main)
	_run.call_deferred()


func _check(label: String, ok: bool, detail: String) -> void:
	print("[final] %s %s  %s" % ["PASS" if ok else "FAIL", label, detail])
	if not ok:
		fails += 1


func _wait(s: float) -> void:
	await get_tree().create_timer(s).timeout


func _settle(w: World) -> void:
	var t0 := Time.get_ticks_msec()
	while not w.is_ready_near() and Time.get_ticks_msec() - t0 < 20000:
		await get_tree().process_frame
	await _wait(1.2)


func _shot(shot_name: String) -> void:
	if shots == "":
		return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(shots.path_join(shot_name + ".png"))


func _on_road(car: CarController) -> Dictionary:
	var near: Dictionary = (Game.world as World).data.network.nearest(car.global_position, 40.0)
	if near.is_empty():
		return {"ok": false, "lat": INF}
	var r: RoadNetwork.Road = near["road"]
	var lat := absf(float(near["lateral"]))
	return {"ok": lat < r.width * 0.5 + r.shoulder + 0.5 and car.wheels_on_ground >= 3, "lat": lat}


func _console() -> Node:
	for n in get_tree().root.find_children("*", "", true, false):
		var sc: Script = n.get_script()
		if sc != null and sc.resource_path == "res://scripts/ui/console.gd":
			return n
	return null


func _run() -> void:
	var t_load := Time.get_ticks_msec()
	while main.get("is_loading"):
		await get_tree().process_frame
	print("[final] loading took %d ms" % (Time.get_ticks_msec() - t_load))
	var w := Game.world as World
	await _wait(2.0)
	var car := Game.player_car
	var road := _on_road(car)
	_check("player spawns in a car on a road", car != null and road["ok"], "lateral %.1f m, wheels %d" % [road["lat"], car.wheels_on_ground])
	await _shot("01_spawn")

	# Console commands.
	var con := _console()
	_check("console exists", con != null, "")
	if con != null:
		var gi := Game.find_car_index("granite")
		con.call("execute", "car granite")
		await _wait(1.0)
		_check("console: car granite", Game.current_car_index == gi and gi >= 0, "index %d" % Game.current_car_index)
		con.call("execute", "time 20")
		con.call("execute", "weather rain")
		con.call("execute", "traffic 0.5")
		await _wait(0.5)
		var t_ok := absf(Game.get_time_of_day() - 20.0) < 0.2
		var w_ok := String(Game.get_weather()) == "rain"
		var d_ok := absf(float(Settings.get_value("traffic_density")) - 0.5) < 0.01
		_check("console: time / weather / traffic", t_ok and w_ok and d_ok, "t=%.2f w=%s d=%s" % [Game.get_time_of_day(), Game.get_weather(), str(Settings.get_value("traffic_density"))])
		con.call("execute", "tp Millbrook")
		await _settle(w)
		var mb := Game.player_car.global_position
		_check("console: tp Millbrook", _on_road(Game.player_car)["ok"], "at %s" % str(mb.round()))
		con.call("execute", "assist abs off")
		var abs_off := not Game.player_car.assist_abs
		con.call("execute", "assist abs on")
		_check("console: assist abs off/on", abs_off and Game.player_car.assist_abs, "")
		con.call("execute", "paint red metallic")
		con.call("execute", "respawn")
		con.call("execute", "help")
		con.call("execute", "cars")
		await _wait(1.0)
		_check("console: paint / respawn / help / cars run", _on_road(Game.player_car)["ok"], "")
		con.call("execute", "weather clear")
		con.call("execute", "time 13")

	# Traffic runs.
	Game.set_traffic_density(0.6)
	Game.teleport("Ring Road - Festival Start")
	await _settle(w)
	await _wait(8.0)
	var tc: int = Game.traffic.call(&"active_count") if Game.traffic != null else 0
	_check("traffic runs", tc > 0, "%d vehicles active" % tc)
	await _shot("02_traffic")

	# Weather + time of day (instant switches, screenshots for the docs).
	for wid: String in ["clear", "cloudy", "rain", "fog", "storm"]:
		Game.set_weather(wid, true)
		await _wait(1.5)
		await _shot("03_weather_" + wid)
	var wet := CarController.wetness
	Game.set_weather("clear", true)
	_check("weather changes grip (wetness after storm)", wet > 0.05, "wetness %.2f" % wet)
	for h: float in [6.5, 13.0, 19.2, 23.0]:
		Game.set_time_of_day(h)
		await _wait(1.0)
		await _shot("04_time_%02d" % int(h))
	Game.set_time_of_day(13.0)

	# Every car: own Blender model, drives on the straight.
	Game.set_traffic_density(0.0)
	(main.get("car_input") as CarInput).enabled = false
	var catalog := Game.get_car_catalog()
	for i in catalog.size():
		var id := String(catalog[i].id)
		Game.teleport("Ring Road - Mesa Straight")
		await _settle(w)
		Game.spawn_car(i, true)
		await _wait(0.6)
		var c := Game.player_car
		var glb := FileAccess.file_exists("res://assets/imported/cars/%s.glb" % id)
		var t0 := Time.get_ticks_msec()
		var top := 0.0
		while Time.get_ticks_msec() - t0 < 7000:
			await get_tree().physics_frame
			c.in_throttle = 1.0
			c.in_brake = 0.0
			c.in_steer = 0.0
			top = maxf(top, c.speed_ms * 3.6)
		c.in_throttle = 0.0
		var up := c.global_transform.basis.y.y > 0.9
		_check("car %d %s drivable" % [i + 1, id], top > 80.0 and up and glb, "%.0f km/h in 7 s, upright %s, blender glb %s" % [top, str(up), str(glb)])
		await _shot("05_car_%02d_%s" % [i + 1, id])
	(main.get("car_input") as CarInput).enabled = true

	# Save / load round trip.
	Game.spawn_car(maxi(Game.find_car_index("kestrel"), 0), true)
	Game.teleport("Gullhaven")
	await _settle(w)
	var p_saved := Game.player_car.global_position
	var ok_save := SaveGame.save_now()
	Game.teleport("Highmoor")
	await _settle(w)
	var actions: Script = load("res://scripts/ui/menu_actions.gd")
	var ok_load: bool = actions.call(&"load_game")
	await _settle(w)
	var dist := Game.player_car.global_position.distance_to(p_saved)
	_check("save/load round trip", ok_save and ok_load and dist < 1.5, "car back within %.2f m" % dist)

	print("[final] failures: %d" % fails)
	_restore()
	get_tree().quit()


func _restore() -> void:
	if _save_backup != null:
		var f := FileAccess.open(SaveGame.PATH, FileAccess.WRITE)
		f.store_string(_save_backup)
		f.close()
	elif FileAccess.file_exists(SaveGame.PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveGame.PATH))
	for k: String in _settings_backup:
		Settings.set_value(k, _settings_backup[k])
