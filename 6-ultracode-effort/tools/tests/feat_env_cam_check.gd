extends Node
## Feature checks for the task-1 additions, in the real game (main scene):
##   Godot_console.exe --path . res://tools/tests/feat_env_cam_check.tscn -- --part=env|cam|both
## env  - environment side panel (N): open/close without pausing, weather buttons, time slider + presets,
##        day-speed switch, number keys, live sync; screenshot with the panel open.
## cam  - chase orbit: full 360 yaw + wide pitch via RMB, wheel distance, pin (V) keeps the angle and
##        follows the car, unpin returns to centre, attached head turn limits, wheel bounds.
## Prints "[feat1] PASS|FAIL ..." and "failures: N" (exit code 1 on failure). SaveGame disabled, settings
## are only changed in memory. Screenshots go to qa_output/task1/.

const Shot := preload("res://scripts/ui/screenshot.gd")

var main: Node
var part := ""
var fails := 0
var hold := false


func _arg(key: String, default: String) -> String:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--%s=" % key):
			return a.get_slice("=", 1)
	return default


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	part = _arg("part", "both")
	SaveGame.enabled = false
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(main)
	_run.call_deferred()


func log_line(s: String) -> void:
	print("[feat1] ", s)


func check(ok: bool, what: String) -> void:
	log_line(("PASS " if ok else "FAIL ") + what)
	if not ok:
		fails += 1


func _wait(s: float) -> void:
	await get_tree().create_timer(s).timeout


func _physics_hold() -> void:
	if main == null or main.player_car == null:
		return
	main.player_car.in_hold = hold


func _shot(fname: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img != null and not img.is_empty():
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://qa_output/task1"))
		img.save_png("res://qa_output/task1/%s.png" % fname)
		log_line("shot qa_output/task1/%s.png" % fname)


func _tap(action: String) -> void:
	# menu_base._input only accepts real input events (key/mouse), so send the action's actual key.
	var key: Key = KEY_N
	match action:
		"camera_pin":
			key = KEY_V
		"toggle_debug_menu":
			key = KEY_F2
		"toggle_environment":
			key = KEY_N
		_:
			push_error("unknown action %s" % action)
	var k := InputEventKey.new()
	k.keycode = key
	k.physical_keycode = key
	k.pressed = true
	Input.parse_input_event(k)
	await get_tree().process_frame
	var k2 := k.duplicate()
	k2.pressed = false
	Input.parse_input_event(k2)
	await get_tree().process_frame


func _motion(dx: float, dy: float) -> void:
	var mm := InputEventMouseMotion.new()
	mm.relative = Vector2(dx, dy)
	Input.parse_input_event(mm)
	await get_tree().process_frame


func _wheel(up: bool) -> void:
	var mb := InputEventMouseButton.new()
	mb.button_index = MOUSE_BUTTON_WHEEL_UP if up else MOUSE_BUTTON_WHEEL_DOWN
	mb.pressed = true
	Input.parse_input_event(mb)
	await get_tree().process_frame
	var mb2 := InputEventMouseButton.new()
	mb2.button_index = mb.button_index
	mb2.pressed = false
	Input.parse_input_event(mb2)
	await get_tree().process_frame


func _panel() -> Node:
	for n in get_tree().get_nodes_in_group("sunward_menus"):
		if n.menu_id == &"environment":
			return n
	return null


func _run() -> void:
	# Wait for the world to stream in.
	var t := 0.0
	while bool(main.get("is_loading")) and t < 60.0:
		await _wait(0.5)
		t += 0.5
	hold = true
	get_tree().physics_frame.connect(_physics_hold)
	await _wait(1.0)

	var car: CarController = main.player_car
	var rig: CameraRig = main.camera_rig
	check(car != null and rig != null, "game ready (car + camera rig)")

	if part in ["env", "both"]:
		await _run_env()
	if part in ["cam", "both"]:
		await _run_cam()

	get_tree().physics_frame.disconnect(_physics_hold)
	hold = false
	log_line("failures: %d" % fails)
	get_tree().quit(1 if fails > 0 else 0)


# ------------------------------------------------------------------ env panel

func _run_env() -> void:
	var panel := _panel()
	check(panel != null, "environment panel registered in ui_root")
	if panel == null:
		return
	await _tap("toggle_environment")
	await _wait(0.3)
	check(panel.is_open, "panel opens by hotkey (N)")
	check(not get_tree().paused, "game keeps running with the panel open")
	var ids: Array = Game.get_weather_ids()
	check(ids.size() == 5, "5 weather buttons for %s" % [ids])
	Game.set_time_scale(1.0)
	Game.set_weather("rain")
	Game.set_time_of_day(12.0)
	await _wait(0.5)
	check(String(Game.get_weather()) == "rain", "weather set from the panel default state")
	# Time presets.
	panel.call("_set_time", 19.0)
	await _wait(0.3)
	check(absf(Game.get_time_of_day() - 19.0) < 0.1, "preset sets time to 19:00 (got %.2f)" % Game.get_time_of_day())
	# Day speed: freeze then live.
	panel.call("_set_scale", 0.0)
	await _wait(0.3)
	var t0 := Game.get_time_of_day()
	await _wait(0.6)
	check(absf(Game.get_time_of_day() - t0) < 0.001, "freeze stops the clock")
	panel.call("_set_scale", 60.0)
	await _wait(0.6)
	check(Game.get_time_of_day() > t0 + 0.05, "60x advances the clock (%.3f -> %.3f)" % [t0, Game.get_time_of_day()])
	# Number key 2 = second weather.
	if ids.size() >= 2:
		var k := InputEventKey.new()
		k.keycode = KEY_2
		k.physical_keycode = KEY_2
		k.pressed = true
		Input.parse_input_event(k)
		await _wait(0.3)
		check(String(Game.get_weather()) == String(ids[1]), "key 2 picks weather %s (got %s)" % [ids[1], Game.get_weather()])
	Game.set_time_scale(1.0)
	await _shot("env_panel_open")
	# The panel follows console edits while open.
	Game.set_time_of_day(5.5)
	await _wait(0.4)
	var lbl: Label = panel.get("_time_label")
	check(lbl != null and lbl.text == "05:30", "panel shows console-set time 05:30 (got %s)" % (lbl.text if lbl else "?"))
	await _tap("toggle_environment")
	await _wait(0.3)
	check(not panel.is_open and not get_tree().paused, "panel closes by hotkey, no pause left behind")
	# Other menus still work after the panel.
	await _tap("toggle_debug_menu")
	await _wait(0.3)
	var dbg: Node = null
	for n in get_tree().get_nodes_in_group("sunward_menus"):
		if n.menu_id == &"debug":
			dbg = n
	check(dbg != null and dbg.is_open, "debug menu opens after the panel was used")
	if dbg:
		dbg.call("close_menu")
	await _wait(0.2)


# ------------------------------------------------------------------ orbit camera

func _yaw_of(rig: CameraRig) -> float:
	return atan2(-rig.global_transform.basis.z.x, -rig.global_transform.basis.z.z)


func _run_cam() -> void:
	var rig: CameraRig = main.camera_rig
	var car: CarController = main.player_car
	if rig == null or car == null:
		check(false, "cam: rig/car missing")
		return
	# Return to a clean chase state.
	rig.set_mode(0, false)
	rig._pinned = false
	await _wait(1.5)
	var dist0 := rig._dist_smooth

	# RMB orbit: mouse motion with free_look held.
	Input.action_press("free_look")
	await _motion(260.0, -160.0)
	await _wait(0.2)
	check(absf(rig._free_yaw) > 0.2, "RMB drag spins the orbit (yaw %.2f rad)" % rig._free_yaw)
	check(rig._free_pitch > 0.1, "drag up raises the camera (pitch %.2f rad)" % rig._free_pitch)
	var cam_h := rig.global_position.y - car.global_position.y
	check(cam_h > 2.5, "camera is above the car in orbit (%.1f m)" % cam_h)
	# Full 360: keep spinning, yaw must not clamp.
	await _motion(900.0, 0.0)
	await _motion(900.0, 0.0)
	await _motion(900.0, 0.0)
	await _motion(900.0, 0.0)
	check(absf(rig._free_yaw) > 3.0, "yaw is unclamped (360° orbit possible, %.2f rad)" % rig._free_yaw)
	# Wheel zoom while orbiting.
	await _wheel(true)
	await _wheel(true)
	await _wait(0.5)
	check(rig._orbit_dist > dist0, "wheel out grows the distance (%.1f -> %.1f)" % [dist0, rig._orbit_dist])
	var d_hi := rig._orbit_dist
	for i in 30:
		await _wheel(false)
	check(absf(rig._orbit_dist - rig.ORBIT_DIST_MIN) < 0.01, "distance clamps at minimum (%.1f)" % rig._orbit_dist)
	for i in 25:
		await _wheel(true)
	check(absf(rig._orbit_dist - rig.ORBIT_DIST_MAX) < 0.01, "distance clamps at maximum (%.1f)" % rig._orbit_dist)
	for i in 10:
		await _wheel(false)
	await _wait(0.6)
	await _shot("cam_orbit_low")
	# Pin: release RMB, pin, the angle stays and follows the car.
	Input.action_release("free_look")
	await _tap("camera_pin")
	await _wait(1.5)
	check(rig._pinned, "camera_pin latches the pin mode")
	var yaw_pinned := rig._free_yaw
	await _wait(1.5)
	check(absf(rig._free_yaw - yaw_pinned) < 0.02, "pinned angle does not auto-return")
	await _shot("cam_orbit_pinned")
	# Unpin: angle returns to centre (the orbit yaw accumulated several turns in the drag phase,
	# lerp_angle walks the shortest arc, so compare the wrapped angle, not the raw value).
	await _tap("camera_pin")
	await _wait(2.5)
	check(absf(wrapf(rig._free_yaw, -PI, PI)) < 0.1 and absf(rig._free_pitch) < 0.1,
			"after unpin the camera returns to centre (wrapped yaw %.3f, pitch %.3f)" % [wrapf(rig._free_yaw, -PI, PI), rig._free_pitch])
	# Attached views: head turn limits.
	rig.set_mode(4, false)  # cockpit
	await _wait(0.3)
	Input.action_press("free_look")
	await _motion(2000.0, -1200.0)
	Input.action_release("free_look")
	await _wait(0.2)
	check(absf(rig._free_yaw) <= rig.HEAD_YAW_MAX + 0.01, "cockpit head yaw clamps ( %.2f )" % rig._free_yaw)
	check(rig._free_pitch <= rig.HEAD_PITCH_MAX + 0.01, "cockpit head pitch clamps (%.2f)" % rig._free_pitch)
	await _shot("cam_cockpit_head")
	await _tap("camera_pin")  # make sure pin is off for the next look
	await _wait(1.2)
	rig.set_mode(0, false)
	rig._pinned = false
