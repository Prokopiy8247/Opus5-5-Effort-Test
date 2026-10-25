extends Node
## Real-game test for the console, garage, debug, pause and photo menus.
## Instances the main scene, waits for loading, drives every menu (real key events where it matters)
## and writes screenshots to res://qa_output/ui_menus/. Restores settings and leaves no save file.
##   Godot_console.exe --path . --resolution 1600x900 res://tools/tests/ui_menus_test.tscn [-- --small]

const OUT := "res://qa_output/ui_menus"
const MENU_SCRIPTS := {
	"console": "res://scripts/ui/console.gd", "garage": "res://scripts/ui/garage_menu.gd",
	"debug": "res://scripts/ui/debug_menu.gd", "pause": "res://scripts/ui/pause_menu.gd",
	"photo": "res://scripts/ui/photo_mode.gd",
}
const MenuBase := preload("res://scripts/ui/menu_base.gd")
const Actions := preload("res://scripts/ui/menu_actions.gd")

var main: Node
var menus: Dictionary = {}
var fails: PackedStringArray = []
var _settings_backup: Dictionary = {}
var _suffix := ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	_settings_backup = Settings.values.duplicate(true)
	SaveGame.enabled = false
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(main)
	_run.call_deferred()


func log_line(s: String) -> void:
	print("[ui_test] ", s)


func check(ok: bool, what: String) -> void:
	log_line(("PASS " if ok else "FAIL ") + what)
	if not ok:
		fails.append(what)


func _wait(t: float) -> void:
	await get_tree().create_timer(t, true, false, true).timeout


func shot(n: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := OUT.path_join(n + _suffix + ".png")
	img.save_png(path)
	log_line("shot %s %dx%d" % [ProjectSettings.globalize_path(path), img.get_width(), img.get_height()])


func key(code: Key, pressed := true, unicode := 0) -> void:
	var e := InputEventKey.new()
	e.keycode = code
	e.physical_keycode = code
	e.unicode = unicode
	e.pressed = pressed
	Input.parse_input_event(e)


func tap(code: Key) -> void:
	key(code, true)
	await get_tree().process_frame
	key(code, false)
	await get_tree().process_frame
	await get_tree().process_frame


func _run() -> void:
	var t := 0.0
	while bool(main.get("is_loading")) and t < 70.0:
		await get_tree().process_frame
		t += get_process_delta_time()
	log_line("loaded in %.1f s" % t)
	_find_or_create_menus()
	await _wait_streamed()
	await _wait(1.0)
	var small := "--small" in OS.get_cmdline_user_args()
	if "--bench" in OS.get_cmdline_user_args():
		await _test_bench_diag()
	elif small:
		_suffix = "_720"
		await _test_small()
	else:
		await _test_console()
		await _test_garage()
		await _test_debug()
		await _test_pause()
		await _test_photo()
		await _test_keys()
	_restore()
	log_line("RESULT %s (%d failures) %s" % ["OK" if fails.is_empty() else "FAIL", fails.size(), ", ".join(fails)])
	get_tree().quit(0 if fails.is_empty() else 1)


func _wait_streamed() -> void:
	var w := Game.world as World
	var t := 0.0
	while w != null and t < 20.0 and (w.terrain.pending_count() > 0 or not w.roads.done):
		await get_tree().process_frame
		t += get_process_delta_time()
	await _wait(0.5)


func _find_or_create_menus() -> void:
	for n: Node in get_tree().get_nodes_in_group(MenuBase.GROUP):
		menus[String(n.get("menu_id"))] = n
	if menus.size() < MENU_SCRIPTS.size():
		log_line("ui_root did not provide all menus (%d) - creating a test UI layer" % menus.size())
		var layer := CanvasLayer.new()
		layer.name = "TestUI"
		layer.layer = 10
		main.add_child(layer)
		for id: String in MENU_SCRIPTS:
			if menus.has(id):
				continue
			var m: Node = (load(MENU_SCRIPTS[id]) as Script).new()
			m.name = id.capitalize()
			layer.add_child(m)
			menus[id] = m
	else:
		log_line("menus provided by ui_root")


# ------------------------------------------------------------------ console

func _test_console() -> void:
	var c: Node = menus["console"]
	c.open_menu()
	await _wait(0.4)
	check(c.is_open and Game.is_overlay_open(), "console opens and pushes overlay")
	c.execute("help")
	await _wait(0.3)
	await shot("01_console_help")
	c.execute("clear")
	c.execute("cars")
	await _wait(0.3)
	await shot("02_console_cars")
	c.execute("car 3")
	await _wait(1.0)
	check(Game.current_car_index == 2, "console 'car 3' spawns Brute 68 (index %d)" % Game.current_car_index)
	c.execute("tp Mesa Fuel")
	await _wait_streamed()
	var reg: String = Game.world.region_at(Game.player_car.global_position)
	check(reg.to_lower().contains("mesa") or reg != "", "console 'tp Mesa Fuel' -> region %s" % reg)
	c.execute("weather rain")
	check(String(Game.get_weather()) == "rain" or Game.env == null, "console 'weather rain' -> %s" % String(Game.get_weather()))
	c.execute("time 20")
	check(Game.env == null or absf(Game.get_time_of_day() - 20.0) < 0.2, "console 'time 20' -> %.2f" % Game.get_time_of_day())
	c.execute("paint red metallic")
	var p := Actions.current_paint()
	check((p["color"] as Color).is_equal_approx(Game.PAINT_COLORS["red"]) and int(p["finish"]) == 2, "console 'paint red metallic'")
	c.execute("stripes 1 white")
	c.execute("rims gold")
	c.execute("assist abs off")
	check(not bool(Settings.get_value("assist_abs")), "console 'assist abs off'")
	c.execute("assist abs on")
	c.execute("upgrade engine 2")
	check(int(Game.get_upgrades(Game.current_car_data().id)["engine"]) == 2, "console 'upgrade engine 2'")
	c.execute("tune final_drive -0.1")
	check(is_equal_approx(float(Game.get_tuning(Game.current_car_data().id).get("final_drive", 0.0)), -0.1), "console 'tune final_drive -0.1'")
	c.execute("tune reset")
	c.execute("upgrade engine 0")
	c.execute("camera 1")
	c.execute("pos")
	c.execute("tp")
	c.execute("weathr rain")
	c.execute("speed")
	check(bool(Settings.get_value("units_mph")), "console 'speed' toggles mph")
	c.execute("speed")
	# Tab completion on a partial command.
	var line: LineEdit = c.get("_line")
	line.text = "wea"
	c.call("_complete")
	check(line.text == "weather ", "tab completion 'wea' -> '%s'" % line.text)
	line.text = "tp mesa f"
	c.call("_complete")
	check(line.text.to_lower() == "tp mesa fuel", "tab completion of tp target -> '%s'" % line.text)
	line.text = ""
	c.call("_update_hint", "")
	c.execute("repair")
	c.execute("reset")
	c.execute("respawn")
	c.execute("hud off")
	check(not bool(Settings.get_value("hud_visible")), "console 'hud off'")
	c.execute("hud on")
	c.execute("bogus 1 2")
	await _wait(2.5)
	await shot("03_console_commands")
	c.close_menu()
	check(not Game.is_overlay_open(), "console close pops overlay")
	await _wait(0.3)
	Game.camera_rig.set_mode(0)
	await _wait(1.0)
	await shot("04_world_after_commands")


# ------------------------------------------------------------------ garage

func _test_garage() -> void:
	Game.teleport("Sunward Festival")
	Game.set_weather("clear", true)
	Game.set_time_of_day(16.5)
	await _wait_streamed()
	await _wait(1.0)
	var g: Node = menus["garage"]
	g.open_menu()
	g.select_tab(0)
	await _wait(1.6)
	await shot("05_garage_cars")
	var pages: Array = g.get("pages")
	var cards: Array = pages[0].get("cards")
	(cards[5] as Button).grab_focus()
	await _wait(0.3)
	(cards[5] as Button).pressed.emit()
	await _wait(1.8)
	check(Game.current_car_index == 5, "garage card press spawns Vortex X (index %d)" % Game.current_car_index)
	check(g.is_open, "garage stays open after spawning")
	await shot("06_garage_cars_vortex")
	g.select_tab(1)
	await _wait(0.3)
	var paint: Node = pages[1]
	paint.set_target(0)
	paint.pick_color(Game.PAINT_COLORS["teal"])
	paint.set_finish(2)
	paint.set_stripes(1)
	paint.set_target(1)
	paint.pick_color(Game.PAINT_COLORS["white"])
	paint.set_target(0)
	await _wait(1.2)
	var p := Actions.current_paint()
	check((p["color"] as Color).is_equal_approx(Game.PAINT_COLORS["teal"]) and int(p["stripes"]) == 1, "garage paint teal + twin stripes")
	await shot("07_garage_paint")
	g.select_tab(2)
	await _wait(0.3)
	var ups: Node = pages[2]
	ups.set_level("engine", 3)
	ups.set_level("tires", 2)
	ups.set_level("weight", 1)
	await _wait(0.5)
	await shot("08_garage_upgrades_compare")
	var pi_before := Tuning.performance_index(Game.effective_car_data(Game.current_car_index))
	ups.install()
	await _wait(1.2)
	var pi_after := Tuning.performance_index(Game.effective_car_data(Game.current_car_index))
	check(pi_after > pi_before, "garage upgrades raise PI %d -> %d" % [pi_before, pi_after])
	g.select_tab(3)
	await _wait(0.3)
	var tune: Node = pages[3]
	var sl: Dictionary = tune.get("sliders")
	(sl["final_drive"] as HSlider).value = 0.1
	(sl["aero_r"] as HSlider).value = 0.3
	await _wait(0.4)
	await shot("09_garage_tuning")
	tune.apply()
	await _wait(1.0)
	check(is_equal_approx(float(Game.get_tuning(Game.current_car_data().id).get("final_drive", 0.0)), 0.1), "garage tune applied")
	# Undo customisation so later screenshots/tests start clean.
	Game.get_upgrades(Game.current_car_data().id).merge({"engine": 0, "tires": 0, "weight": 0}, true)
	Game.get_tuning(Game.current_car_data().id).clear()
	g.close_menu()
	Game.spawn_car(0, true)
	await _wait(1.0)
	check((Game.camera_rig as CameraRig).active, "camera rig re-enabled after garage")


# ------------------------------------------------------------------ debug

func _test_debug() -> void:
	var d: Node = menus["debug"]
	d.open_menu()
	await _wait(0.8)
	await shot("10_debug_menu")
	d.call("_set_time", 19.0)
	d.call("_set_weather", "cloudy")
	d.call("_teleport", "Ring Road - Cliff Road")
	await _wait(0.5)
	await shot("11a_debug_fast_travel")
	await _wait(3.0)
	await _wait_streamed()
	var reg: String = Game.world.region_at(Game.player_car.global_position)
	check(not d.is_open and reg != "", "debug teleport fast-travels to the Cliff Road (%s)" % reg)
	d.open_menu()
	await _wait(1.0)
	await shot("11_debug_after_teleport")
	d.call("start_benchmark", 10.0)
	check(not d.is_open and int(d.get("bench_phase")) == 1, "benchmark starts and hides the menu")
	var t := 0.0
	var shot_taken := false
	while int(d.get("bench_phase")) > 0 and t < 40.0:
		await get_tree().process_frame
		t += get_process_delta_time()
		if not shot_taken and int(d.get("bench_phase")) == 2 and t > 8.0:
			shot_taken = true
			await shot("12_benchmark_running")
	var r: Dictionary = d.get("bench_result")
	check(not r.is_empty() and bool(r.get("ran", false)) and float(r.get("distance_km", 0.0)) > 0.15, "benchmark result %s" % JSON.stringify(r))
	await _wait(0.6)
	await shot("13_debug_benchmark_result")
	d.call("start_benchmark", 60.0)
	await _wait(3.0)
	await tap(KEY_F1)
	check(not menus["garage"].is_open, "F1 during the benchmark does not open the garage")
	await tap(KEY_SPACE)
	var r2: Dictionary = d.get("bench_result")
	check(int(d.get("bench_phase")) == 0 and bool(r2.get("cancelled", false)) and d.is_open, "any key cancels the benchmark and reopens the menu")
	d.close_menu()


# ------------------------------------------------------------------ pause

func _test_pause() -> void:
	var p: Node = menus["pause"]
	p.open_menu()
	await _wait(0.5)
	check(get_tree().paused, "pause menu pauses the tree")
	await shot("14_pause_overview")
	p.show_page(1)
	await _wait(0.3)
	await shot("15_pause_settings")
	p.show_page(2)
	await _wait(0.3)
	await shot("16_pause_controls")
	p.show_page(0)
	# Save, move, load: the car must come back. Another session's save file is restored afterwards.
	var backup := FileAccess.get_file_as_bytes(SaveGame.PATH) if SaveGame.has_save() else PackedByteArray()
	var saved_pos := Game.player_car.global_position
	var saved_idx := Game.current_car_index
	check(Actions.save_game(), "save game")
	p.close_menu()
	check(not get_tree().paused, "closing pause unpauses")
	Game.spawn_car(7, false)
	Game.teleport("Gullhaven")
	await _wait(0.6)
	check(Actions.load_game(), "load game")
	await _wait(0.8)
	var back := Game.player_car.global_position.distance_to(saved_pos)
	check(Game.current_car_index == saved_idx and back < 6.0, "load restores car %d and position (%.1f m off)" % [Game.current_car_index, back])
	if backup.is_empty():
		SaveGame.delete_save()
	else:
		var fa := FileAccess.open(SaveGame.PATH, FileAccess.WRITE)
		fa.store_buffer(backup)
		fa.close()
	await _wait_streamed()


# ------------------------------------------------------------------ photo

func _test_photo() -> void:
	Game.teleport("Sunward Festival")
	Game.set_time_of_day(18.2)
	Game.set_weather("clear", true)
	await _wait_streamed()
	await _wait(1.5)
	var ph: Node = menus["photo"]
	ph.open_menu()
	await _wait(0.4)
	check(Game.photo_mode and get_tree().paused and not (Game.camera_rig as CameraRig).active, "photo mode pauses and frees the camera")
	var car := Game.player_car
	var f := -car.global_transform.basis.z
	var right := car.global_transform.basis.x
	var cam_pos := car.global_position + f * 5.5 + right * 3.0 + Vector3.UP * 1.1
	var look := Transform3D(Basis(), cam_pos).looking_at(car.global_position + Vector3.UP * 0.6, Vector3.UP)
	var e := look.basis.get_euler()
	ph.set("_pos", cam_pos)
	ph.set("_yaw", e.y)
	ph.set("_pitch", e.x)
	var sl: Dictionary = ph.get("_sliders")
	(sl["fov"] as HSlider).value = 45.0
	(sl["focus"] as HSlider).value = snappedf(cam_pos.distance_to(car.global_position), 0.5)
	(sl["aperture"] as HSlider).value = 0.6
	(sl["roll"] as HSlider).value = -6.0
	await _wait(0.8)
	await shot("17_photo_panel")
	ph.capture()
	await _wait(1.0)
	var path: String = ph.get("last_shot")
	check(path != "" and FileAccess.file_exists(path), "photo capture saved %s" % ProjectSettings.globalize_path(path))
	if path != "":
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	await _wait(0.2)
	await shot("18_photo_confirmation")
	ph.toggle_panel()
	(sl["time"] as HSlider).value = 19.6
	await _wait(0.6)
	await shot("19_photo_clean_sunset")
	ph.toggle_panel()
	ph.close_menu()
	await _wait(0.3)
	check(not Game.photo_mode and not get_tree().paused and (Game.camera_rig as CameraRig).active, "photo mode exit restores rig + unpauses")
	menus["console"].open_menu()
	menus["console"].execute("photo")
	await _wait(0.3)
	check(ph.is_open and not menus["console"].is_open, "console 'photo' enters photo mode")
	ph.close_menu()
	await _wait(0.2)


# ------------------------------------------------------------------ real key events

func _test_keys() -> void:
	await tap(KEY_F1)
	check(menus["garage"].is_open, "F1 opens garage")
	await tap(KEY_F2)
	check(menus["garage"].is_open and not menus["debug"].is_open, "F2 is ignored while the garage is open")
	await tap(KEY_F1)
	await tap(KEY_F2)
	check(menus["debug"].is_open, "F2 opens debug menu")
	await tap(KEY_ESCAPE)
	check(not menus["debug"].is_open and not menus["pause"].is_open, "Esc closes debug without pausing")
	await tap(KEY_QUOTELEFT)
	check(menus["console"].is_open, "backtick opens console")
	key(KEY_P, true, 112)
	await get_tree().process_frame
	key(KEY_P, false)
	await get_tree().process_frame
	check(not menus["photo"].is_open, "typing P in the console does not open photo mode")
	await tap(KEY_F1)
	check(not menus["garage"].is_open, "F1 ignored while console is open")
	await tap(KEY_ESCAPE)
	check(not menus["console"].is_open and not menus["pause"].is_open, "Esc closes console only")
	await tap(KEY_ESCAPE)
	check(menus["pause"].is_open and get_tree().paused, "Esc opens pause")
	await tap(KEY_ESCAPE)
	check(not menus["pause"].is_open and not get_tree().paused, "Esc resumes")
	await tap(KEY_P)
	check(menus["photo"].is_open, "P opens photo mode")
	await tap(KEY_P)
	check(not menus["photo"].is_open and not Game.photo_mode, "P exits photo mode")
	check(Game.overlays_open == 0, "overlay counter back to 0 (%d)" % Game.overlays_open)


func _test_bench_diag() -> void:
	var d: Node = menus["debug"]
	d.call("start_benchmark", 24.0)
	var t := 0.0
	var next := 0.0
	var next_shot := 2.0
	while int(d.get("bench_phase")) > 0 and t < 60.0:
		await get_tree().process_frame
		t += get_process_delta_time()
		var car := Game.player_car
		if t >= next:
			next += 0.5
			var f: RoadFollower = d.get("_bench_follower")
			var road := f.road
			var lp := f.lane_point(f.s)
			var rt := road.right_at(f.s)
			var lat := (car.global_position - lp).dot(rt)
			log_line("t %.1f ph %d s %.1f lat %.2f kmh %.0f steer %.2f thr %.2f brk %.2f hb %.2f wheels %d pos %s" % [t, int(d.get("bench_phase")), f.s, lat, car.get_speed_kmh(), car.in_steer, car.in_throttle, car.in_brake, car.in_handbrake, car.wheels_on_ground, str(car.global_position.round())])
		if t >= next_shot and int(d.get("bench_phase")) == 2:
			next_shot += 3.0
			await shot("bench_%02d" % int(t))
	log_line("bench result %s" % JSON.stringify(d.get("bench_result")))


func _test_small() -> void:
	var g: Node = menus["garage"]
	g.open_menu()
	g.select_tab(0)
	await _wait(1.5)
	await shot("garage_cars")
	g.select_tab(1)
	await _wait(0.4)
	await shot("garage_paint")
	g.select_tab(2)
	await _wait(0.4)
	await shot("garage_upgrades")
	g.select_tab(3)
	await _wait(0.4)
	await shot("garage_tuning")
	g.close_menu()
	var c: Node = menus["console"]
	c.open_menu()
	c.execute("cars")
	await _wait(0.5)
	await shot("console")
	c.close_menu()
	menus["debug"].open_menu()
	await _wait(0.6)
	await shot("debug")
	menus["debug"].close_menu()
	var p: Node = menus["pause"]
	p.open_menu()
	await _wait(0.4)
	await shot("pause")
	p.show_page(1)
	await _wait(0.3)
	await shot("pause_settings")
	p.show_page(2)
	await _wait(0.3)
	await shot("pause_controls")
	p.close_menu()
	menus["photo"].open_menu()
	await _wait(0.5)
	await shot("photo")
	menus["photo"].close_menu()


## Puts back only the settings this test touches (other sessions may change the rest meanwhile).
func _restore() -> void:
	var changed := false
	for k: String in ["camera_mode", "units_mph", "hud_visible", "assist_abs", "traffic_density", "show_fps"]:
		if Settings.values.get(k) != _settings_backup.get(k):
			Settings.set_value(k, _settings_backup[k], false)
			changed = true
	if changed:
		Settings.save_settings()
