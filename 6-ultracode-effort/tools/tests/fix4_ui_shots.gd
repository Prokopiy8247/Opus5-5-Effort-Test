extends Node
## s25 / s28 regression in the real game: F12 while driving must not stall the frame (wall-clock
## frame_post_draw intervals), the async PNG must match the rendered frame, photo mode capture too, and
## F12 with the HUD hidden (F3, world map) must confirm on screen right away without a late toast.
##   Godot_console.exe --audio-driver Dummy --resolution 1920x1080 --path . res://tools/tests/fix4_ui_shots.tscn -- --part=f12|hidden|photo
## Prints "[shots] PASS|FAIL ..." and "failures: N". Screenshots written by the run are deleted again.

const OUT := "res://qa_output/fix4_ui/shots"
const Shot := preload("res://scripts/ui/screenshot.gd")

var main: Node
var follower: RoadFollower
var fails := 0
var _ticks: PackedInt64Array = []
var _shots_before: PackedStringArray = []
var _settings_backup: Dictionary = {}


func _arg(key: String, default: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--%s=" % key):
			return a.get_slice("=", 1)
	return default


func log_line(s: String) -> void:
	print("[shots] ", s)


func check(ok: bool, what: String) -> void:
	log_line(("PASS " if ok else "FAIL ") + what)
	if not ok:
		fails += 1


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	_settings_backup = Settings.values.duplicate(true)
	SaveGame.enabled = false
	SaveGame.pending = {}
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(main)
	RenderingServer.frame_post_draw.connect(func() -> void: _ticks.append(Time.get_ticks_usec()))
	Game.notification.connect(func(t: String, b: String, k: StringName) -> void: log_line("NOTIFY [%s] %s | %s" % [k, t, b]))
	_run.call_deferred()


func _physics_process(delta: float) -> void:
	var car := Game.player_car
	if follower != null and car != null and is_instance_valid(car):
		car.in_hold = false
		follower.drive(car, delta)


func _wait(s: float) -> void:
	await get_tree().create_timer(s, true, false, true).timeout


func _settle() -> void:
	var w := Game.world as World
	var t0 := Time.get_ticks_msec()
	while w != null and not w.is_ready_near() and Time.get_ticks_msec() - t0 < 20000:
		await get_tree().process_frame
	await _wait(1.0)


func key(code: Key) -> void:
	for pressed: bool in [true, false]:
		var e := InputEventKey.new()
		e.keycode = code
		e.physical_keycode = code
		e.pressed = pressed
		Input.parse_input_event(e)
		await get_tree().process_frame


func _shot(n: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OUT.path_join(n + ".png"))


func _user_shots() -> PackedStringArray:
	var d := DirAccess.open(Shot.DIR)
	return d.get_files() if d != null else PackedStringArray()


func _run() -> void:
	while main.get("is_loading"):
		await get_tree().process_frame
	if Game.traffic != null and Game.traffic.has_method("set_density"):
		Game.traffic.call("set_density", 0.0)
	Game.set_time_of_day(13.0)
	Game.set_weather("clear", true)
	_shots_before = _user_shots()
	await _wait(1.0)
	match _arg("part", "f12"):
		"f12":
			await _part_f12()
		"hidden":
			await _part_hidden()
		"photo":
			await _part_photo()
	follower = null
	for f in _user_shots():
		if f not in _shots_before:
			DirAccess.remove_absolute(Shot.DIR.path_join(f))
			log_line("removed test screenshot %s" % f)
	Settings.values = _settings_backup
	log_line("failures: %d" % fails)
	get_tree().quit(0 if fails == 0 else 1)


## Longest wall-clock interval among the `n` frames after tick index `from`.
func _worst_after(from: int, n: int) -> float:
	var worst := 0.0
	for i in range(maxi(from, 1), mini(from + n, _ticks.size())):
		worst = maxf(worst, (_ticks[i] - _ticks[i - 1]) / 1000.0)
	return worst


func _median_ms(from: int, to: int) -> float:
	var arr: Array[float] = []
	for i in range(maxi(from, 1), mini(to, _ticks.size())):
		arr.append((_ticks[i] - _ticks[i - 1]) / 1000.0)
	arr.sort()
	return arr[arr.size() / 2] if not arr.is_empty() else 0.0


func _drive_to(s_target: float, timeout: float) -> void:
	var t := 0.0
	while follower.s < s_target and t < timeout:
		await get_tree().process_frame
		t += get_process_delta_time()


# ------------------------------------------------------------------ s25: F12 while driving

func _part_f12() -> void:
	var ring: RoadNetwork.Road = (Game.world as World).data.network.get_road("ring")
	Game.main.teleport_to({"position": ring.surface_point(470.0, ring.lane_offset(1)), "forward": ring.flat_tangent_at(470.0)})
	await _settle()
	follower = RoadFollower.new()
	follower.setup(ring, 470.0, 1, ring.lane_offset(1))
	follower.respect_traffic = false
	follower.target_speed = 90.0 / 3.6
	var ui: Node = Game.hud
	await _drive_to(540.0, 30.0)
	var t_base := _ticks.size()
	for s_press: float in [560.0, 620.0, 680.0]:
		await _drive_to(s_press, 20.0)
		var before := String(ui.get("last_screenshot"))
		var i0 := _ticks.size()
		var kmh := Game.player_car.get_speed_kmh()
		await key(KEY_F12)
		var t0 := Time.get_ticks_msec()
		while String(ui.get("last_screenshot")) == before and Time.get_ticks_msec() - t0 < 5000:
			await get_tree().process_frame
		var saved_ms := Time.get_ticks_msec() - t0
		var worst := _worst_after(i0, _ticks.size() - i0 + 1)
		var path := String(ui.get("last_screenshot"))
		var img := Image.load_from_file(ProjectSettings.globalize_path(path)) if path != before else null
		log_line("F12 at s=%.0f %.0f km/h: file after %d ms, worst frame interval until then %.1f ms (median %.1f ms), %s %s" % [s_press, kmh,
			saved_ms, worst, _median_ms(i0, _ticks.size()), path.get_file(), str(img.get_size()) if img else "no image"])
		check(path != before and img != null and img.get_size() == Vector2i(get_viewport().get_texture().get_size()),
			"F12 at s=%.0f saved a full-size PNG (%s)" % [s_press, path.get_file()])
		check(worst < 60.0, "F12 at s=%.0f: no frame stall (worst interval %.1f ms < 60 ms; the synchronous save took 450-650 ms)" % [s_press, worst])
	await _shot("f12_after_presses")
	var keep := String(ui.get("last_screenshot"))
	if keep != "":
		DirAccess.copy_absolute(ProjectSettings.globalize_path(keep), ProjectSettings.globalize_path(OUT.path_join("f12_saved_file.png")))
	var rd := RenderingServer.get_rendering_device()
	var tex := RenderingServer.texture_get_rd_texture(get_viewport().get_texture().get_rid()) if rd != null else RID()
	log_line("readback: rd texture valid %s, format %d (RGBA8 unorm %d / srgb %d)" % [str(tex.is_valid()), rd.texture_get_format(tex).format if tex.is_valid() else -1,
		RenderingDevice.DATA_FORMAT_R8G8B8A8_UNORM, RenderingDevice.DATA_FORMAT_R8G8B8A8_SRGB])
	# Reference: the old synchronous path (readback + encode on the main thread) on the same frame size.
	await RenderingServer.frame_post_draw
	var i_sync := _ticks.size()
	var sp := Shot.save_viewport(get_viewport())
	await get_tree().process_frame
	await get_tree().process_frame
	log_line("reference: synchronous save_viewport frame interval %.1f ms (%s)" % [_worst_after(i_sync, 3), sp.get_file()])
	log_line("driving frames before the presses: median %.1f ms, worst %.1f ms" % [_median_ms(t_base - 200, t_base), _worst_after(t_base - 200, 200)])
	# Content: the background readback must give exactly the rendered frame.
	await RenderingServer.frame_post_draw
	var got := [""]
	Shot.save_viewport_async(get_viewport(), func(p: String) -> void: got[0] = p)
	var ref := get_viewport().get_texture().get_image()
	ref.convert(Image.FORMAT_RGB8)
	var t1 := Time.get_ticks_msec()
	while String(got[0]) == "" and Time.get_ticks_msec() - t1 < 5000:
		await get_tree().process_frame
	var out := Image.load_from_file(ProjectSettings.globalize_path(String(got[0]))) if String(got[0]) != "" else null
	var diff := 999
	if out != null and out.get_size() == ref.get_size():
		out.convert(Image.FORMAT_RGB8)
		var a := out.get_data()
		var b := ref.get_data()
		diff = 0
		for i in range(0, a.size(), 997):
			diff = maxi(diff, absi(a[i] - b[i]))
	check(diff <= 1, "async PNG equals the synchronously read frame (max channel difference %d over sampled bytes)" % diff)
	follower = null


# ------------------------------------------------------------------ s28: F12 with the HUD hidden

func _shot_toasts() -> int:
	var n := 0
	var notes: Node = Game.hud.get("notifications")
	for t: Dictionary in notes.get("_toasts"):
		if String(t["title"]).begins_with("Screenshot"):
			n += 1
	return n


func _banner_visible() -> bool:
	var b: Variant = Game.hud.get("_banner")
	if b == null or not is_instance_valid(b):
		return false
	return (b as Control).is_visible_in_tree() and (b as Control).modulate.a > 0.5


func _menu_toast_text(m: Node) -> String:
	for c in m.get_children():
		if c is PanelContainer:
			for l in (c as Node).find_children("*", "Label", true, false):
				if (l as Label).text.begins_with("Screenshot"):
					return (l as Label).text
	return ""


func _f12_and_wait(ui: Node) -> String:
	var before := String(ui.get("last_screenshot"))
	await key(KEY_F12)
	var t0 := Time.get_ticks_msec()
	while String(ui.get("last_screenshot")) == before and Time.get_ticks_msec() - t0 < 5000:
		await get_tree().process_frame
	return String(ui.get("last_screenshot"))


func _part_hidden() -> void:
	var ui: Node = Game.hud
	var ring: RoadNetwork.Road = (Game.world as World).data.network.get_road("ring")
	follower = RoadFollower.new()
	follower.setup(ring, 40.0, 1, ring.lane_offset(1))
	follower.respect_traffic = false
	follower.target_speed = 80.0 / 3.6
	await _wait(4.0)
	# Case A: F3 (HUD off), F12.
	await key(KEY_F3)
	await _wait(0.3)
	check(not (ui.get("hud_root") as Control).visible, "F3 hides the HUD")
	var p := await _f12_and_wait(ui)
	await _wait(0.4)
	await _shot("a_hud_hidden_after_f12")
	check(p != "" and _banner_visible() and _shot_toasts() == 0, "HUD hidden: F12 shows the confirmation banner at once (banner %s, toasts queued in the hidden HUD %d)" % [str(_banner_visible()), _shot_toasts()])
	await _wait(3.4)
	check(not _banner_visible(), "the banner goes away again after about 3 s")
	await key(KEY_F3)
	await _wait(0.6)
	await _shot("b_hud_back")
	check((ui.get("hud_root") as Control).visible and _shot_toasts() == 0, "HUD back on: no late 'Screenshot saved' toast pops up (%d)" % _shot_toasts())
	# Case B: world map open.
	await key(KEY_M)
	await _wait(0.8)
	var wm: Node = ui.get("world_map")
	check(bool(wm.get("is_open")), "world map open")
	p = await _f12_and_wait(ui)
	await _wait(0.4)
	await _shot("c_map_after_f12")
	check(_banner_visible() and _shot_toasts() == 0, "world map open: F12 confirmation shows over the map (banner %s, hidden toasts %d)" % [str(_banner_visible()), _shot_toasts()])
	await key(KEY_M)
	await _wait(0.8)
	await _shot("d_map_closed")
	check(not bool(wm.get("is_open")) and _shot_toasts() == 0, "map closed: no late toast (%d)" % _shot_toasts())
	await _wait(3.0)
	# Case C: HUD visible -> the normal toast stack.
	p = await _f12_and_wait(ui)
	await _wait(0.5)
	await _shot("e_hud_visible_toast")
	check(_shot_toasts() == 1 and not _banner_visible(), "HUD visible: the normal toast confirms (%d toasts)" % _shot_toasts())
	# Case D: pause menu open -> the menu's own toast (unchanged behaviour).
	follower = null
	await _wait(5.5)
	await key(KEY_ESCAPE)
	await _wait(0.6)
	var pm: Node = null
	for n: Node in get_tree().get_nodes_in_group(&"sunward_menus"):
		if n.get("menu_id") == &"pause":
			pm = n
	check(pm != null and bool(pm.get("is_open")), "pause menu open")
	p = await _f12_and_wait(ui)
	await _wait(0.3)
	await _shot("f_pause_menu_after_f12")
	var mt := _menu_toast_text(pm)
	check(mt != "" and not _banner_visible(), "pause menu: confirmation toast inside the menu ('%s')" % mt)
	await key(KEY_ESCAPE)
	await _wait(0.4)


# ------------------------------------------------------------------ s25: photo mode capture

func _part_photo() -> void:
	await key(KEY_P)
	await _wait(1.0)
	var ph: Node = null
	for n: Node in get_tree().get_nodes_in_group(&"sunward_menus"):
		if n.get("menu_id") == &"photo":
			ph = n
	check(ph != null and bool(ph.get("is_open")), "photo mode open")
	for k in 2:
		var before := String(ph.get("last_shot"))
		var i0 := _ticks.size()
		await key(KEY_F12)
		var t0 := Time.get_ticks_msec()
		while String(ph.get("last_shot")) == before and Time.get_ticks_msec() - t0 < 5000:
			await get_tree().process_frame
		var worst := _worst_after(i0, _ticks.size() - i0 + 1)
		var path := String(ph.get("last_shot"))
		log_line("photo %d: saved after %d ms, worst frame interval %.1f ms, %s" % [k, Time.get_ticks_msec() - t0, worst, path.get_file()])
		check(path != before and FileAccess.file_exists(path), "photo mode F12 saved %s" % path.get_file())
		if k == 0 and path != before:
			DirAccess.copy_absolute(ProjectSettings.globalize_path(path), ProjectSettings.globalize_path(OUT.path_join("photo_saved_file.png")))
		check(worst < 60.0, "photo mode capture: no stall (worst interval %.1f ms)" % worst)
		await _wait(0.2)
		await _shot("photo_%d_toast" % k)
		await _wait(0.6)
	var panel: Control = ph.get("_panel")
	check(panel.visible, "photo panel back after the capture")
	await key(KEY_P)
	await _wait(0.5)
