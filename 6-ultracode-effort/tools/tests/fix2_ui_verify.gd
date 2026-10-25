extends Node
## Regression test for the fix2 UI playtest defects, in the real game (main scene). One part per run (each < 3 min):
##   Godot_console.exe --path . --resolution 1920x1080 res://tools/tests/fix2_ui_verify.tscn -- --part=<part>
## Parts: bench (p14 benchmark drives + p22 banner centred), tach (p16 numerals vs assist lamps, all cars),
## garage (p19 mph in Upgrades/Tuning, p21 preset swatch after load), console (p23 input validation),
## map (p20 region names vs markers / pin / tags), gps (p33 activity vs player waypoint arrival),
## race (p33 real rc_coast race, --race=<id>), banner (p34 result banner vs region popup, incl. Beach Road),
## ghost (p17 map screenshots at max zoom; --tex=<png> swaps in another map base for comparison).
## Round-2 parts (playtest2, written to qa_output/fix3_ui/<part>): menus (q8 every menu hotkey from every
## open menu, Tab focus in pause/debug), photo (q7 photo panel by keyboard), phototime (q33 time slider in
## photo mode vs the time-reactive group), nightgarage (q11 showroom lights), controls (q12 rewind row),
## debugtime (q13 time readouts at 60x), telemetry (q14 wheel row spacing), minimap (q15 region plate),
## stripes (q16 completion), result (q30 race place / flag name in the banner).
## Round-3 parts (playtest3, written to qa_output/fix4_ui/<part>): garagefit (s26 showroom car inside the free
## area at every orbit angle, no fence between camera and car); bench also covers s27 (traffic capped to 0,
## no event toasts during the run, traffic back afterwards). F12 / photo capture stalls and the hidden-HUD
## confirmation (s25 / s28) are in fix4_ui_shots.tscn, the pipeline warm-up (s24) in fix4_ui_pipewarm.tscn.
## Writes qa_output/fix2_ui/<part>/*.png, prints "[fix2ui] PASS|FAIL ..." and "failures: N" (exit code 1 on failure).
## SaveGame is disabled and settings are only changed in memory (restored at the end); photos the test takes
## in user://screenshots are deleted again.

const OUT := "res://qa_output/fix2_ui"
const OUT3 := "res://qa_output/fix3_ui"
const FIX3_PARTS: PackedStringArray = ["menus", "photo", "phototime", "nightgarage", "controls", "debugtime", "telemetry", "minimap", "stripes", "result"]
const OUT4 := "res://qa_output/fix4_ui"
const FIX4_PARTS: PackedStringArray = ["garagefit"]
const Shot := preload("res://scripts/ui/screenshot.gd")
const Mats := preload("res://scripts/world/dressing_materials.gd")
const MapData := preload("res://scripts/ui/hud_map_data.gd")
const Actions := preload("res://scripts/ui/menu_actions.gd")
const MenuBaseScript := preload("res://scripts/ui/menu_base.gd")
const Style3 := preload("res://scripts/ui/ui_style.gd")
const MStyle := preload("res://scripts/ui/menu_style.gd")

var main: Node
var part := ""
var dir := ""
var fails := 0
var _settings_backup: Dictionary = {}
var follower: RoadFollower
var notes: Array[String] = []
## Keeps the player car parked (in_hold) every physics frame; `manual` drives it directly (in_* values).
var hold := false
var manual: Dictionary = {}
var _shots_before: PackedStringArray = []


func _arg(key: String, default: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--%s=" % key):
			return a.get_slice("=", 1)
	return default


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	part = _arg("part", "bench")
	dir = (OUT4 if part in FIX4_PARTS else (OUT3 if part in FIX3_PARTS else OUT)).path_join(part)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	_settings_backup = Settings.values.duplicate(true)
	SaveGame.enabled = false
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(main)
	Game.notification.connect(func(t: String, b: String, k: StringName) -> void:
		notes.append("%s|%s|%s" % [t, b, k])
		log_line("NOTIFY [%s] %s | %s" % [k, t, b]))
	_run.call_deferred()


func log_line(s: String) -> void:
	print("[fix2ui] ", s)


func check(ok: bool, what: String) -> void:
	log_line(("PASS " if ok else "FAIL ") + what)
	if not ok:
		fails += 1


func _wait(s: float) -> void:
	await get_tree().create_timer(s, true, false, true).timeout


func _settle() -> void:
	var w := Game.world as World
	var t0 := Time.get_ticks_msec()
	while w != null and not w.is_ready_near() and Time.get_ticks_msec() - t0 < 20000:
		await get_tree().process_frame
	await _wait(1.0)


func shot(shot_name: String, crop := Rect2(), zoom := 1) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if crop.size.x > 0.0:
		img = img.get_region(Rect2i(crop))
		if zoom > 1:
			img.resize(img.get_width() * zoom, img.get_height() * zoom, Image.INTERPOLATE_NEAREST)
	img.save_png(dir.path_join(shot_name + ".png"))


func key(code: Key, unicode := 0) -> void:
	for pressed: bool in [true, false]:
		var e := InputEventKey.new()
		e.keycode = code
		e.physical_keycode = code
		e.unicode = unicode if pressed else 0
		e.pressed = pressed
		Input.parse_input_event(e)
		await get_tree().process_frame


func type_text(t: String) -> void:
	for ch in t:
		var code: Key = KEY_MINUS if ch == "-" else (KEY_PERIOD if ch == "." else (KEY_SPACE if ch == " " else OS.find_keycode_from_string(ch.to_upper())))
		await key(code, ch.unicode_at(0))


func click(pos: Vector2) -> void:
	for pressed: bool in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.position = pos
		e.global_position = pos
		e.pressed = pressed
		Input.parse_input_event(e)
		await get_tree().process_frame


func menu(id: StringName) -> Node:
	for n: Node in get_tree().get_nodes_in_group(&"sunward_menus"):
		if n.get("menu_id") == id:
			return n
	return null


func car_input(on: bool) -> void:
	var ci: Variant = main.get("car_input")
	if ci is CarInput:
		(ci as CarInput).enabled = on


func no_traffic() -> void:
	if Game.traffic != null and Game.traffic.has_method("set_density"):
		Game.traffic.call("set_density", 0.0)


func _physics_process(delta: float) -> void:
	var car := Game.player_car
	if car == null or not is_instance_valid(car):
		return
	if follower != null:
		car.in_hold = false
		follower.drive(car, delta)
	elif not manual.is_empty():
		car.in_hold = false
		for k: String in manual:
			car.set(k, manual[k])
	elif hold:
		car.in_hold = true


func _run() -> void:
	while main.get("is_loading"):
		await get_tree().process_frame
	no_traffic()
	Game.set_time_of_day(13.0)
	Game.set_weather("clear", true)
	_shots_before = _user_shots()
	await _wait(1.0)
	match part:
		"bench":
			await _part_bench()
		"tach":
			await _part_tach()
		"garage":
			await _part_garage()
		"console":
			await _part_console()
		"map":
			await _part_map()
		"gps":
			await _part_gps()
		"banner":
			await _part_banner()
		"race":
			await _part_race()
		"ghost":
			await _part_ghost()
		"menus":
			await _part_menus()
		"photo":
			await _part_photo()
		"phototime":
			await _part_phototime()
		"nightgarage":
			await _part_nightgarage()
		"controls":
			await _part_controls()
		"debugtime":
			await _part_debugtime()
		"telemetry":
			await _part_telemetry()
		"minimap":
			await _part_minimap()
		"stripes":
			await _part_stripes()
		"result":
			await _part_result()
		"garagefit":
			await _part_garagefit()
	follower = null
	manual = {}
	hold = false
	if get_tree().paused:
		var m := MenuBaseScript.open_menu_node(get_tree())
		if m != null:
			m.call("close_menu")
	Game.set_time_scale(1.0)
	_delete_new_shots()
	Settings.values = _settings_backup
	log_line("failures: %d" % fails)
	get_tree().quit(0 if fails == 0 else 1)


# ------------------------------------------------------------------ p14 / p22 benchmark

func _part_bench() -> void:
	Game.teleport("Sunward Festival")
	await _settle()
	# s27: default traffic (live only), so the run has traffic to keep off its road.
	if Game.traffic != null:
		Game.traffic.call("set_density", 0.6)
	await _wait(6.0)
	var traffic_before: int = Game.traffic.call("active_count") if Game.traffic != null else 0
	var d := menu(&"debug")
	await key(KEY_F2)
	await _wait(1.0)
	await shot("00_debug_menu")
	var btn: Button = d.get("_bench_button")
	var c := btn.get_global_rect().get_center()
	log_line("bench button at %s" % str(c))
	await click(c)
	await _wait(0.2)
	check(int(d.get("bench_phase")) > 0 and not bool(d.get("is_open")), "benchmark started by clicking the F2 menu button")
	var t := 0.0
	var next_log := 0.0
	var centre_dev := 0.0
	var max_kmh := 0.0
	var held_frames := 0
	var shots_done := {}
	var traffic_run := 0
	var toasts_run := 0
	var notes0 := notes.size()
	var nstack: Node = Game.hud.get("notifications")
	while int(d.get("bench_phase")) > 0 and t < 90.0:
		await get_tree().process_frame
		t += get_process_delta_time()
		var car := Game.player_car
		var ov: Control = d.get("_bench_overlay")
		if int(d.get("bench_phase")) == 2:
			max_kmh = maxf(max_kmh, car.get_speed_kmh())
			if car.in_hold:
				held_frames += 1
			if Game.traffic != null:
				traffic_run = maxi(traffic_run, int(Game.traffic.call("active_count")))
			for tt: Dictionary in nstack.get("_toasts"):
				if float(tt["age"]) < 0.1:
					toasts_run += 1
			if ov != null and ov.visible:
				centre_dev = maxf(centre_dev, absf(ov.get_global_rect().get_center().x - get_viewport().get_visible_rect().size.x * 0.5))
		if t >= next_log:
			next_log += 2.0
			var r := ov.get_global_rect() if ov != null else Rect2()
			log_line("t %.1f phase %d kmh %.1f in_hold %s thr %.2f brk %.2f gear %d overlay x %.0f..%.0f centre %.0f" % [t, int(d.get("bench_phase")), car.get_speed_kmh(), str(car.in_hold), car.in_throttle, car.in_brake, car.gear, r.position.x, r.end.x, r.get_center().x])
		for st: int in [3, 12, 33]:
			if not shots_done.has(st) and t > float(st) + 3.0:
				shots_done[st] = true
				await shot("01_running_t%02d" % st)
	await _wait(1.0)
	await shot("02_result_panel")
	var res: Dictionary = d.get("bench_result")
	log_line("[bench] %s" % JSON.stringify(res))
	check(bool(res.get("ran", false)) and not bool(res.get("cancelled", true)), "benchmark ran to the end")
	check(float(res.get("distance_km", 0.0)) > 1.2, "benchmark drove %.2f km (avg %.0f km/h, max %.0f km/h)" % [float(res.get("distance_km", 0.0)), float(res.get("avg_kmh", 0.0)), max_kmh])
	check(held_frames == 0, "car never held during the run (%d held frames)" % held_frames)
	check(centre_dev < 3.0, "benchmark banner centred (max deviation %.1f px)" % centre_dev)
	log_line("notifications emitted during the run (not shown): %s" % str(notes.slice(notes0)))
	check(traffic_before > 0 and traffic_run == 0, "s27: traffic kept off the run (%d vehicles before, max %d during the run)" % [traffic_before, traffic_run])
	check(toasts_run == 0, "s27: no toasts shown during the run (%d)" % toasts_run)
	check(float(res.get("avg_kmh", 0.0)) > 72.0, "s27: average speed %.0f km/h set by the road, not by traffic" % float(res.get("avg_kmh", 0.0)))
	check(Game.activities == null or String(Game.activities.call("get_session_id")) == "", "s27: no event left armed by the autopilot")
	if bool(d.get("is_open")):
		d.call("close_menu")
	await _wait(8.0)
	var traffic_after: int = Game.traffic.call("active_count") if Game.traffic != null else 0
	check(Game.traffic == null or (is_equal_approx(float(Game.traffic.call("effective_density")), 0.6) and traffic_after > 0),
		"s27: traffic returns after the run (density %.2f, %d vehicles)" % [float(Game.traffic.call("effective_density")) if Game.traffic != null else 0.0, traffic_after])


# ------------------------------------------------------------------ p16 tachometer

func _part_tach() -> void:
	Game.teleport("Ring Road - Mesa Straight")
	await _settle()
	car_input(false)
	var hud: Node = Game.hud.get("hud")
	var speedo: Control = hud.get("speedo")
	var cat := Game.get_car_catalog()
	var worst_gap := INF
	for i in cat.size():
		Game.spawn_car(i, true)
		await _wait(2.6)
		var r := speedo.get_global_rect()
		var crop := Rect2(r.position + Vector2(40, 20), Vector2(320, 250))
		await shot("tach_%02d_%s_unlit" % [i + 1, cat[i].id], crop, 2)
		speedo.set("_lamps", PackedFloat32Array([30.0, 30.0, 30.0]))
		await _wait(0.2)
		await shot("tach_%02d_%s_lit" % [i + 1, cat[i].id], crop, 2)
		speedo.set("_lamps", PackedFloat32Array([0.0, 0.0, 0.0]))
		var gap := _tach_gap(speedo)
		worst_gap = minf(worst_gap, gap)
		log_line("%s max_disp %d: min gap numeral<->lamp %.1f px" % [cat[i].display_name, int(speedo.call("_max_disp")), gap])
	check(worst_gap > 1.0, "no tach numeral touches an assist lamp on any car (worst gap %.1f px)" % worst_gap)
	Game.spawn_car(0, true)
	car_input(true)


## Smallest distance between a numeral glyph box and a lamp rect (negative = overlap), same maths as hud_speedo.gd.
func _tach_gap(sp: Control) -> float:
	var Style := preload("res://scripts/ui/ui_style.gd")
	var c: Vector2 = sp.call("_center")
	var ra := float(sp.get("R")) - 26.0
	var maxd: float = sp.call("_max_disp")
	var lamp_size: Vector2 = sp.get("LAMP_SIZE")
	var lamps: Array[Rect2] = []
	for i in 3:
		var lc := c + Vector2((i - 1) * float(sp.get("LAMP_DX")), float(sp.get("LAMP_Y")))
		lamps.append(Rect2(lc - lamp_size * 0.5, lamp_size).grow(2.0))
	var f := Style.font(600, true)
	var best := INF
	var rpm := 0.0
	while rpm <= maxd + 1.0:
		var a: float = sp.call("_angle", rpm)
		var tp := c + Vector2(cos(a), sin(a)) * (ra - 42.0)
		var txt := str(int(rpm / 1000.0))
		var w := f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 21).x
		var cap := f.get_ascent(21) * 0.72
		var g := Rect2(Vector2(tp.x - w * 0.5, tp.y + 8.0 - cap), Vector2(w, cap + 1.5))
		for l in lamps:
			var dx := maxf(maxf(l.position.x - g.end.x, g.position.x - l.end.x), 0.0)
			var dy := maxf(maxf(l.position.y - g.end.y, g.position.y - l.end.y), 0.0)
			var gap := Vector2(dx, dy).length() if (dx > 0.0 or dy > 0.0) else -minf(minf(g.end.x, l.end.x) - maxf(g.position.x, l.position.x), minf(g.end.y, l.end.y) - maxf(g.position.y, l.position.y))
			best = minf(best, gap)
		rpm += 1000.0
	return best


# ------------------------------------------------------------------ p19 units / p21 paint swatches

func _swatches_selected(paint: Node) -> PackedStringArray:
	var out: PackedStringArray = []
	for sw: Button in paint.get("_swatches"):
		var sb := sw.get_theme_stylebox("normal") as StyleBoxFlat
		if sb != null and sb.border_width_left >= 4:
			out.append(sw.tooltip_text)
	return out


func _texts(n: Node) -> PackedStringArray:
	var out: PackedStringArray = []
	for l in n.find_children("*", "Label", true, false):
		var lab := l as Label
		if lab.is_visible_in_tree() and lab.text != "":
			out.append(lab.text)
	return out


func _part_garage() -> void:
	Game.teleport("Sunward Festival")
	await _settle()
	var g := menu(&"garage")
	var con := menu(&"console")
	# p21: the shipped save has brute_68 = "#9e0f0dff" (red preset) and rims "#bf9433ff" (gold preset).
	var bp: Dictionary = Game.get_paint("brute_68")
	log_line("brute_68 paint after startup load: color %s (red preset %s, exact %s) rims %s" % [str(bp.get("color")), str(Game.PAINT_COLORS["red"]), str(bp.get("color") == Game.PAINT_COLORS["red"]), str(bp.get("rim_color"))])
	check(bp.get("color") == Game.PAINT_COLORS["red"] and bp.get("rim_color") == Game.PAINT_COLORS["gold"], "saved preset colours load back as the exact presets")
	await key(KEY_F1)
	await _wait(1.0)
	var pages: Array = g.get("pages")
	pages[0].call("_on_card_pressed", 2)
	await _wait(1.5)
	g.call("select_tab", 1)
	var paint: Node = pages[1]
	paint.call("set_target", 0)
	await _wait(0.6)
	var sel := _swatches_selected(paint)
	await shot("p21_01_body_loaded_from_save")
	check(sel == PackedStringArray(["Red"]), "body swatch outlined after load: %s" % str(sel))
	paint.call("set_target", 2)
	await _wait(0.4)
	sel = _swatches_selected(paint)
	await shot("p21_02_rims_loaded_from_save")
	check(sel == PackedStringArray(["Gold"]), "rim swatch outlined after load: %s" % str(sel))
	# The UI comparison alone also copes with an 8-bit colour that was not snapped (e.g. older code paths).
	bp["color"] = Color.html("#9e0f0d")
	paint.call("set_target", 0)
	await _wait(0.3)
	sel = _swatches_selected(paint)
	check(sel == PackedStringArray(["Red"]), "unsnapped 8-bit red still outlines the Red swatch: %s" % str(sel))
	check(Actions.color_name(bp["color"]) == "Red", "console colour name of a reloaded preset: %s" % Actions.color_name(bp["color"]))
	# Round trip through the real encoder / decoder.
	var enc: Dictionary = SaveGame.call("_encode", Game.paints)
	var dec: Dictionary = SaveGame.call("_decode", JSON.parse_string(JSON.stringify(enc)))
	check((dec["brute_68"] as Dictionary)["color"] == Game.PAINT_COLORS["red"], "encode -> JSON -> decode keeps the exact red preset")
	bp["color"] = Game.PAINT_COLORS["red"]
	g.call("close_menu")
	await _wait(0.5)
	await key(KEY_QUOTELEFT)
	await _wait(0.6)
	con.call("execute", "paint")
	await _wait(0.4)
	var log_text: String = (con.get("_log") as RichTextLabel).get_parsed_text()
	var last := log_text.strip_edges().get_slice("\n", log_text.strip_edges().get_slice_count("\n") - 1)
	log_line("console paint -> %s" % last)
	check(last.contains("Paint: Red"), "console 'paint' names the reloaded preset")
	await shot("p21_03_console_paint")
	await key(KEY_QUOTELEFT)
	await _wait(0.5)

	# p19: imperial units in every garage comparison.
	Settings.set_value("units_mph", true, false)
	await key(KEY_F1)
	await _wait(1.0)
	g.call("select_tab", 0)
	await _wait(0.5)
	await shot("p19_01_cars_mph")
	var cars_txt := " | ".join(_texts(pages[0]))
	g.call("select_tab", 2)
	pages[2].call("set_level", "engine", 2)
	await _wait(0.6)
	await shot("p19_02_upgrades_mph")
	var up_txt := " | ".join(_texts(pages[2]))
	g.call("select_tab", 3)
	await _wait(0.6)
	await shot("p19_03_tuning_mph")
	var tune_txt: String = (pages[3].get("_compare") as Label).text
	log_line("cars: %s" % cars_txt.substr(0, 400))
	log_line("upgrades: %s" % up_txt.substr(0, 600))
	log_line("tuning: %s" % tune_txt)
	check(cars_txt.contains(" mph") and up_txt.contains(" mph") and tune_txt.contains(" mph"), "mph shown on Cars, Upgrades and Tuning")
	check(not up_txt.get_slice("Top speed", 1).contains("km/h") and not tune_txt.get_slice("Top", 1).get_slice("Cornering", 0).contains("km/h"), "no km/h top speed left in the comparisons")
	pages[2].call("refresh")
	g.call("close_menu")
	Settings.set_value("units_mph", false, false)
	await _wait(0.5)


# ------------------------------------------------------------------ p23 console / debug input

func _console_last(con: Node) -> String:
	var t := (con.get("_log") as RichTextLabel).get_parsed_text().strip_edges()
	return t.get_slice("\n", t.get_slice_count("\n") - 1)


func _part_console() -> void:
	Game.teleport("Sunward Festival")
	await _settle()
	var con := menu(&"console")
	await key(KEY_QUOTELEFT)
	await _wait(0.6)
	# One command typed for real, the rest through execute().
	await type_text("time 12:75")
	await key(KEY_ENTER)
	await _wait(0.3)
	var tod0 := Game.get_time_of_day()
	var r := _console_last(con)
	log_line("typed 'time 12:75' -> %s (time %.3f)" % [r, tod0])
	check(r.begins_with("✗"), "time 12:75 rejected")
	var hud0 := bool(Settings.get_value("hud_visible", true))
	var cases := [["time 12:-30", false], ["time 7:99", false], ["time 24:30", false], ["time 7:59", true], ["time 6:30", true],
		["hud maybe", false], ["hud yes", false], ["help nosuch", false], ["timescale -3", false], ["timescale 1", true]]
	for cs: Array in cases:
		con.call("execute", String(cs[0]))
		await _wait(0.15)
		var line := _console_last(con)
		log_line("CMD [%s] => %s" % [cs[0], line])
		check(line.begins_with("✓") == bool(cs[1]) and (bool(cs[1]) or line.begins_with("✗")), "console '%s' %s" % [cs[0], "accepted" if cs[1] else "rejected"])
		if String(cs[0]) == "time 7:59":
			check(line.contains("07:59"), "time 7:59 reports 07:59")
	check(bool(Settings.get_value("hud_visible", true)) == hud0, "hud setting unchanged by bad input")
	con.call("execute", "help time")
	await _wait(0.15)
	log_line("CMD [help time] => %s" % _console_last(con))
	await shot("p23_01_console")
	await key(KEY_QUOTELEFT)
	await _wait(0.5)
	# Debug menu time scale field.
	var d := menu(&"debug")
	await key(KEY_F2)
	await _wait(1.0)
	var edit: LineEdit = d.get("_scale_edit")
	edit.grab_focus()
	edit.select_all()
	await type_text("-3")
	await key(KEY_ENTER)
	await _wait(0.3)
	log_line("timescale submit '-3' -> edit '%s' scale %.2f" % [edit.text, Game.get_time_scale()])
	check(edit.text == str(Game.get_time_scale()) and is_equal_approx(Game.get_time_scale(), 1.0), "debug time scale -3 rejected, field shows the applied value")
	await shot("p23_02_debug_timescale_minus3")
	# Submitting ends LineEdit editing: click into the field again like a player would.
	await click(edit.get_global_rect().get_center())
	edit.select_all()
	await type_text("2.50")
	await key(KEY_ENTER)
	await _wait(0.3)
	log_line("timescale submit '2.50' -> edit '%s' scale %.2f" % [edit.text, Game.get_time_scale()])
	check(edit.text == "2.5" and is_equal_approx(Game.get_time_scale(), 2.5), "debug time scale 2.50 applied and shown as 2.5")
	Game.set_time_scale(1.0)
	d.call("close_menu")
	await _wait(0.3)


# ------------------------------------------------------------------ p20 world map labels

func _map_overlaps(wm: Node, with_pin: bool) -> int:
	var Style := preload("res://scripts/ui/ui_style.gd")
	var pos: Array = wm.get("_region_pos")
	var fs: int = wm.call("_region_font_size")
	var n := 0
	for i in pos.size():
		var nm := String(WorldLayout.REGIONS[i]["name"]).to_upper()
		var tw := Style.text_width(nm, fs, 700, false, 6)
		var rr: Rect2 = wm.call("_region_rect", pos[i], tw, fs)
		var hits: PackedStringArray = []
		for sp: Node2D in wm.get("_sprites"):
			if not sp.visible:
				continue
			var rad := float(sp.get("radius"))
			var ir := Rect2(sp.position - Vector2(rad, rad), Vector2(rad, rad) * 2.0)
			if ir.intersects(rr):
				hits.append(String((sp.get("data") as Dictionary)["name"]))
			if bool(sp.get("show_tag")):
				var tr: Rect2 = sp.call("tag_rect")
				tr.position += sp.position
				if tr.intersects(rr):
					hits.append("tag:" + String((sp.get("data") as Dictionary)["name"]))
		if with_pin and Game.waypoint != Vector3.INF:
			var wp: Vector2 = wm.call("_to_screen", Vector2(Game.waypoint.x, Game.waypoint.z))
			if Rect2(wp + Vector2(-12, -36), Vector2(24, 41)).intersects(rr):
				hits.append("waypoint pin")
		log_line("%s at %s overlaps %s" % [nm, str(pos[i].round()), str(hits)])
		n += hits.size()
	return n


func _part_map() -> void:
	Game.teleport("Sunward Festival")
	await _settle()
	var wm: Node = Game.hud.get("world_map")
	await key(KEY_M)
	await _wait(1.2)
	await shot("p20_01_map_fit")
	check(_map_overlaps(wm, false) == 0, "fit view: no region name under a marker")
	for t: Dictionary in Game.get_teleport_targets():
		if String(t["name"]) == "Ironcrest Pass":
			Game.set_waypoint(t["position"])
	await _wait(1.0)
	await shot("p20_02_map_fit_waypoint")
	check(_map_overlaps(wm, true) == 0, "fit view + waypoint at Ironcrest Pass: no overlap")
	wm.set("_zoom", float(wm.get("_fit")) * 1.9)
	wm.set("_center", Vector2(-300, -200))
	await _wait(1.0)
	await shot("p20_03_map_zoom_tags")
	check(_map_overlaps(wm, true) == 0, "zoom 1.9x (name tags on): no tag or marker under a region name")
	Game.clear_waypoint()
	await key(KEY_M)
	await _wait(0.5)


# ------------------------------------------------------------------ p33 GPS arrival

func _drive_to(target_s: float, timeout: float) -> void:
	var t := 0.0
	while follower.s < target_s and t < timeout:
		await get_tree().process_frame
		t += get_process_delta_time()


func _part_gps() -> void:
	var ring: RoadNetwork.Road = (Game.world as World).data.network.get_road("ring")
	var s0 := 13200.0
	car_input(false)
	follower = RoadFollower.new()
	follower.setup(ring, s0, 1, ring.lane_offset(1))
	follower.target_speed = 80.0 / 3.6
	Game.main.call("teleport_to", {"position": follower.lane_point(s0), "forward": ring.flat_tangent_at(s0)})
	await _settle()
	var gps: Node = Game.hud.get("gps")
	# Activity-owned waypoint (what a race sets for its next gate).
	var wp_s := s0 + 180.0
	Game.set_waypoint(ring.point_at(wp_s), &"activity")
	notes.clear()
	var inside_active := true
	var shot_done := false
	var t := 0.0
	while follower.s < wp_s + 40.0 and t < 40.0:
		await get_tree().process_frame
		t += get_process_delta_time()
		var dist := Game.player_car.global_position.distance_to(ring.point_at(wp_s))
		if dist < 30.0 and not bool(gps.get("active")):
			inside_active = false
		if not shot_done and dist < 18.0:
			shot_done = true
			await shot("p33_01_activity_waypoint_18m")
	var route_notes := notes.filter(func(n: String) -> bool: return n.begins_with("Destination reached"))
	check(route_notes.is_empty(), "no 'Destination reached' for an activity waypoint (%d toasts)" % route_notes.size())
	check(Game.waypoint != Vector3.INF and Game.waypoint_owner == &"activity", "activity waypoint kept by the GPS (owner %s)" % Game.waypoint_owner)
	check(inside_active, "route guidance stays on inside the 32 m arrival radius")
	# Player waypoint: arrival still announced and cleared.
	wp_s = follower.s + 160.0
	Game.set_waypoint(ring.point_at(wp_s))
	notes.clear()
	await _drive_to(wp_s + 20.0, 40.0)
	await _wait(0.3)
	route_notes = notes.filter(func(n: String) -> bool: return n.begins_with("Destination reached"))
	await shot("p33_02_player_waypoint_arrived")
	check(route_notes.size() == 1 and Game.waypoint == Vector3.INF, "player waypoint: arrival toast once, waypoint cleared")
	follower = null
	car_input(true)


## Real race (needs road_race.gd to pass &"activity"): Saltwind Coast Sprint, logs every route toast.
func _part_race() -> void:
	var am: Node = Game.activities
	var rid := _arg("race", "rc_coast")
	var a: RefCounted = (am.get("by_id") as Dictionary).get(rid)
	var data: Resource = a.get("data")
	var road: RoadNetwork.Road = a.get("road")
	var gates: PackedFloat32Array = data.get("gates")
	var dr := int(data.get("dir"))
	am.call("teleport_to_activity", rid, 90.0)
	await _settle()
	car_input(false)
	var s := gates[0] - dr * 90.0
	follower = RoadFollower.new()
	follower.setup(road, s, dr, road.lane_offset(1) * dr if road.traffic else 0.0)
	follower.target_speed = 45.0 / 3.6
	notes.clear()
	var t := 0.0
	while (follower.s - gates[0]) * dr < 10.0 and t < 30.0:
		await get_tree().process_frame
		t += get_process_delta_time()
	follower.target_speed = 0.0
	t = 0.0
	while String(am.call("get_session_id")) == "" and t < 20.0:
		await get_tree().process_frame
		t += get_process_delta_time()
	log_line("session '%s' after stopping %.1f s, waypoint %s owner %s" % [String(am.call("get_session_id")), t, str(Game.waypoint.round()), Game.waypoint_owner])
	await _wait(4.5)
	follower.target_speed = 230.0 / 3.6
	var cp_shot := 0
	t = 0.0
	var last_wp := Game.waypoint
	while String(am.call("get_session_id")) != "" and t < 150.0:
		await get_tree().process_frame
		t += get_process_delta_time()
		if Game.waypoint != last_wp:
			last_wp = Game.waypoint
			log_line("t %.1f waypoint -> %s owner %s" % [t, str(Game.waypoint.round()), Game.waypoint_owner])
			if cp_shot < 2:
				cp_shot += 1
				await shot("p33_race_cp%d" % cp_shot)
	await _wait(1.0)
	await shot("p33_race_finish")
	var route_notes := notes.filter(func(n: String) -> bool: return n.begins_with("Destination reached"))
	log_line("route toasts during the race: %d; all notes: %s" % [route_notes.size(), str(notes)])
	check(route_notes.is_empty(), "no GPS 'Destination reached' toast during %s" % rid)
	follower = null
	car_input(true)


# ------------------------------------------------------------------ p34 result banner vs region popup

func _part_banner() -> void:
	var hud: Node = Game.hud.get("hud")
	var act: Node = hud.get("activity")
	var reg: Node = hud.get("region_popup")
	Game.teleport("Sunward Festival")
	await _settle()
	# A) synthetic: banner first, region change 1 s later -> popup waits for the banner.
	Game.activity_finished.emit("test_trap", {"title": "Mirror Lake Run", "score_text": "86 km/h", "personal_best": true, "medal": "Gold", "kind": "speed_trap"})
	await _wait(1.0)
	Game.region_changed.emit("Ochre Mesa")
	var both := 0
	var popup_seen := false
	var t := 0.0
	var k := 0
	while t < 11.0:
		await get_tree().process_frame
		t += get_process_delta_time()
		var b := bool(act.call("banner_visible"))
		var p := bool(reg.call("is_showing"))
		if b and p:
			both += 1
		if p and not b:
			popup_seen = true
		if t > k * 1.0:
			k += 1
			await shot("p34_A_%02d" % k)
	check(both == 0 and popup_seen, "A: region popup waited for the banner (%d overlapping frames, popup shown after: %s)" % [both, str(popup_seen)])
	# B) region popup first, banner 0.4 s later -> popup dropped and replayed after the banner.
	Game.region_changed.emit("Verdant Vale")
	await _wait(0.4)
	Game.activity_finished.emit("test_trap", {"title": "Beach Road", "score_text": "140 km/h", "personal_best": false, "medal": "Silver", "kind": "speed_trap"})
	both = 0
	popup_seen = false
	t = 0.0
	while t < 11.0:
		await get_tree().process_frame
		t += get_process_delta_time()
		var b2 := bool(act.call("banner_visible"))
		var p2 := bool(reg.call("is_showing"))
		if b2 and p2:
			both += 1
		if p2 and not b2:
			popup_seen = true
	check(both == 0 and popup_seen, "B: popup interrupted by the banner is replayed afterwards (%d overlapping frames)" % both)
	# C) natural: Beach Road speed trap ~30 m before the Verdant Vale border, driven at 140 km/h.
	var am: Node = Game.activities
	var a: RefCounted = (am.get("by_id") as Dictionary).get("st_beach_road")
	if a == null:
		log_line("st_beach_road not found, natural case skipped")
		return
	var road: RoadNetwork.Road = a.get("road")
	var gate := (a.get("data") as Resource).get("gates")[0] as float
	var s0 := gate - 420.0
	car_input(false)
	follower = RoadFollower.new()
	follower.setup(road, s0, 1, road.lane_offset(1))
	follower.target_speed = 140.0 / 3.6
	Game.main.call("teleport_to", {"position": follower.lane_point(s0), "forward": road.flat_tangent_at(s0)})
	await _settle()
	both = 0
	popup_seen = false
	var banner_seen := false
	var region_t := -1.0
	var banner_t := -1.0
	t = 0.0
	k = 0
	var regions_before := Game.world.call("region_at", Game.player_car.global_position) as String
	while follower.s < gate + 600.0 and t < 40.0:
		await get_tree().process_frame
		t += get_process_delta_time()
		var b3 := bool(act.call("banner_visible"))
		var p3 := bool(reg.call("is_showing"))
		if b3 and banner_t < 0.0:
			banner_t = t
			banner_seen = true
		if region_t < 0.0 and String(Game.world.call("region_at", Game.player_car.global_position)) != regions_before:
			region_t = t
		if b3 and p3:
			both += 1
		if p3 and not b3 and banner_seen:
			popup_seen = true
		if banner_seen and k < 8 and t > banner_t + k * 0.8:
			k += 1
			await shot("p34_C_%02d" % k)
	log_line("C: banner at %.2f s, region change at %.2f s" % [banner_t, region_t])
	check(banner_seen and both == 0, "C: Beach Road finish + border: no frame with banner and popup together (%d)" % both)
	check(region_t < 0.0 or popup_seen or t >= 40.0, "C: region popup shown after the banner")
	await _wait(6.0)
	await shot("p34_C_after")
	follower = null
	car_input(true)


# ------------------------------------------------------------------ p17 map raster (road-free base)

func _part_ghost() -> void:
	Game.teleport("Gullhaven")
	await _settle()
	var wm: Node = Game.hud.get("world_map")
	var alt := _arg("tex", "")
	for pass_i in 2:
		if pass_i == 1:
			if alt == "":
				break
			var img := Image.new()
			img.load_png_from_buffer(FileAccess.get_file_as_bytes(alt))
			img.generate_mipmaps()
			var tex := ImageTexture.create_from_image(img)
			MapData._tex = tex
			var mm: Node = Game.hud.get("minimap")
			(mm.get("_tex_rect") as TextureRect).texture = tex
			wm.set("_drawn_zoom", 0.0)
		var tag := "baked" if pass_i == 0 else "noroads"
		await _wait(1.0)
		var mr := (Game.hud.get("minimap") as Control).get_global_rect()
		await shot("p17_%s_minimap" % tag, Rect2(mr.position, Vector2(280, 280)), 3)
		await key(KEY_M)
		await _wait(1.0)
		wm.set("_center", Vector2(1000, 1330))
		wm.set("_zoom", 2.6)
		await _wait(0.8)
		await shot("p17_%s_map_maxzoom" % tag)
		await shot("p17_%s_map_maxzoom_crop" % tag, Rect2(Vector2(560, 240), Vector2(460, 300)), 2)
		wm.set("_center", Vector2(220, -600))
		await _wait(0.8)
		await shot("p17_%s_map_lake_maxzoom" % tag)
		wm.set("_zoom", 1.0)
		wm.set("_center", Vector2(1000, 1330))
		await _wait(0.8)
		await shot("p17_%s_map_zoom1" % tag)
		await key(KEY_M)
		await _wait(0.5)


# ================================================================== round 2 (playtest2) parts

func press(code: Key, unicode := 0, shift := false) -> void:
	for pressed: bool in [true, false]:
		var e := InputEventKey.new()
		e.keycode = code
		e.physical_keycode = code
		e.unicode = unicode if pressed else 0
		e.shift_pressed = shift
		e.pressed = pressed
		Input.parse_input_event(e)
		await get_tree().process_frame


func _open_ids() -> PackedStringArray:
	var out: PackedStringArray = []
	for n: Node in get_tree().get_nodes_in_group(&"sunward_menus"):
		if bool(n.get("is_open")):
			out.append(String(n.get("menu_id")))
	return out


func _focus() -> Control:
	return get_viewport().gui_get_focus_owner()


func _fname() -> String:
	var f := _focus()
	if f == null:
		return "<none>"
	var t: String = str(f.get("text")) if "text" in f else ""
	return "%s[%s]" % [f.get_class(), t]


func _button(root: Node, text: String) -> Button:
	for b in root.find_children("*", "Button", true, false):
		if (b as Button).text == text:
			return b as Button
	return null


## Waits (up to 4 s) until photo mode reports a new saved photo: the PNG is encoded in the background.
func _shot_after(ph: Node, before: String) -> void:
	var t0 := Time.get_ticks_msec()
	while String(ph.get("last_shot")) == before and Time.get_ticks_msec() - t0 < 4000:
		await get_tree().process_frame
	await _wait(0.3)


func _user_shots() -> PackedStringArray:
	var d := DirAccess.open(Shot.DIR)
	return d.get_files() if d != null else PackedStringArray()


## Photos written by this run (photo mode capture / F12) are removed again.
func _delete_new_shots() -> void:
	for f in _user_shots():
		if f not in _shots_before:
			DirAccess.remove_absolute(Shot.DIR.path_join(f))
			log_line("removed test photo %s" % f)


func _luma(img: Image, r := Rect2i()) -> float:
	if r.size.x <= 0:
		r = Rect2i(Vector2i.ZERO, img.get_size())
	var sum := 0.0
	var n := 0
	for y in range(r.position.y, r.end.y, 6):
		for x in range(r.position.x, r.end.x, 6):
			sum += img.get_pixel(x, y).get_luminance()
			n += 1
	return sum / maxf(n, 1)


func _mean_color(img: Image, r: Rect2i) -> Color:
	var acc := Color(0, 0, 0, 0)
	var n := 0
	for y in range(r.position.y, r.end.y, 3):
		for x in range(r.position.x, r.end.x, 3):
			acc += img.get_pixel(x, y)
			n += 1
	return acc / maxf(n, 1)


func _frame() -> Image:
	await RenderingServer.frame_post_draw
	return get_viewport().get_texture().get_image()


# ------------------------------------------------------------------ q8 menu hotkeys

const MENU_KEYS := {"garage": [KEY_F1, 0], "debug": [KEY_F2, 0], "console": [KEY_QUOTELEFT, 96], "map": [KEY_M, 109],
	"pause": [KEY_ESCAPE, 0], "photo": [KEY_P, 112]}
const HOTKEYS := [["Tab", KEY_TAB, 0], ["F1", KEY_F1, 0], ["F2", KEY_F2, 0], ["`", KEY_QUOTELEFT, 96], ["M", KEY_M, 109], ["P", KEY_P, 112]]


func _part_menus() -> void:
	Game.teleport("Sunward Festival")
	await _settle()
	for id: String in MENU_KEYS:
		var k: Array = MENU_KEYS[id]
		await key(k[0], k[1])
		await _wait(0.4)
		var paused := get_tree().paused
		var want_pause := id == "pause" or id == "photo"
		check(_open_ids() == PackedStringArray([id]) and paused == want_pause, "%s opens by its hotkey (open %s, paused %s)" % [id, str(_open_ids()), str(paused)])
		var ok_all := true
		for hk: Array in HOTKEYS:
			if int(hk[1]) == int(k[0]) or (id == "garage" and String(hk[0]) == "Tab"):
				continue
			await key(hk[1], hk[2])
			await _wait(0.2)
			var good := _open_ids() == PackedStringArray([id]) and get_tree().paused == paused
			ok_all = ok_all and good
			log_line("%s open + %s -> open %s paused %s overlay %s focus %s %s" % [id, hk[0], str(_open_ids()), str(get_tree().paused),
				str(Game.is_overlay_open()), _fname(), "" if good else "<-- WRONG"])
		check(ok_all, "%s: Tab / F1 / F2 / ` / M / P neither replace it, open another menu nor change the pause" % id)
		await shot("q8_%s_after_hotkeys" % id)
		await key(KEY_ESCAPE)
		await _wait(0.4)
		check(_open_ids().is_empty() and not get_tree().paused and not Game.is_overlay_open(), "Esc closes %s, nothing else opens (open %s, paused %s)" % [id, str(_open_ids()), str(get_tree().paused)])
	# Tab is still the garage key while driving.
	await key(KEY_TAB)
	await _wait(0.4)
	var tab_open := _open_ids() == PackedStringArray(["garage"])
	await key(KEY_TAB)
	await _wait(0.4)
	check(tab_open and _open_ids().is_empty(), "Tab opens and closes the garage while driving")
	# Tab / Shift+Tab move focus on the paused Settings page (the playtest repro).
	var pm := menu(&"pause")
	await key(KEY_ESCAPE)
	await _wait(0.4)
	await key(KEY_DOWN)
	await key(KEY_ENTER)
	await _wait(0.4)
	var f0 := _focus()
	log_line("pause settings focus %s" % _fname())
	await shot("q8_pause_settings_before_tab")
	await press(KEY_TAB)
	await _wait(0.2)
	var f1 := _focus()
	log_line("after Tab: focus %s open %s paused %s" % [_fname(), str(_open_ids()), str(get_tree().paused)])
	await shot("q8_pause_settings_after_tab")
	check(f0 != null and f1 != null and f1 != f0 and pm.is_ancestor_of(f1) and _open_ids() == PackedStringArray(["pause"]) and get_tree().paused,
		"Tab in pause Settings moves focus to the next setting, game stays paused")
	await press(KEY_TAB, 0, true)
	await _wait(0.2)
	check(_focus() == f0 and _open_ids() == PackedStringArray(["pause"]), "Shift+Tab moves focus back (%s)" % _fname())
	await key(KEY_ESCAPE)
	await key(KEY_ESCAPE)
	await _wait(0.4)
	check(_open_ids().is_empty() and not get_tree().paused, "Esc, Esc: back to the overview, then resume")
	# Tab in the debug menu moves focus too.
	var dm := menu(&"debug")
	await key(KEY_F2)
	await _wait(0.5)
	var d0 := _focus()
	var d0_name := _fname()
	await press(KEY_TAB)
	await _wait(0.2)
	log_line("debug Tab: %s -> %s" % [d0_name, _fname()])
	check(_focus() != null and _focus() != d0 and dm.is_ancestor_of(_focus()) and _open_ids() == PackedStringArray(["debug"]), "Tab in the debug menu moves focus, the garage stays closed")
	await key(KEY_ESCAPE)
	await _wait(0.3)
	# A scripted open over a paused menu keeps the pause (console 'photo' style hand-over).
	await key(KEY_ESCAPE)
	await _wait(0.3)
	menu(&"photo").call("open_menu")
	await _wait(0.3)
	check(_open_ids() == PackedStringArray(["photo"]) and get_tree().paused, "scripted open over the pause menu keeps the game paused")
	await key(KEY_ESCAPE)
	await _wait(0.3)
	check(_open_ids().is_empty() and not get_tree().paused, "closing the menu that took over the pause resumes")


# ------------------------------------------------------------------ q7 photo panel keyboard

func _part_photo() -> void:
	Game.teleport("Sunward Festival")
	await _settle()
	car_input(false)
	hold = true
	await _wait(1.0)
	var ph := menu(&"photo")
	var cam := (Game.camera_rig as CameraRig).camera
	await key(KEY_P, 112)
	await _wait(0.5)
	var sl: Dictionary = ph.get("_sliders")
	var fov: HSlider = sl["fov"]
	log_line("after P: open %s paused %s focus %s fov %.1f" % [str(ph.get("is_open")), str(get_tree().paused), _fname(), fov.value])
	check(bool(ph.get("is_open")) and _focus() == fov, "P opens photo mode with keyboard focus on Field of view")
	var v0 := fov.value
	await key(KEY_RIGHT)
	await key(KEY_RIGHT)
	check(is_equal_approx(fov.value, v0 + 2.0) and is_equal_approx(cam.fov, fov.value), "Right x2 on the FOV slider: %.0f -> %.0f (camera %.0f)" % [v0, fov.value, cam.fov])
	await shot("q7_01_fov_focused")
	await press(KEY_TAB)
	var tab_ok: bool = _focus() == sl["focus"]
	await key(KEY_DOWN)
	var down_ok: bool = _focus() == sl["aperture"]
	await key(KEY_UP)
	var up_ok: bool = _focus() == sl["focus"]
	check(tab_ok and down_ok and up_ok, "Tab / Down / Up move focus between the sliders (now %s)" % _fname())
	# Every slider and button can be reached with Tab.
	var seen := {}
	for i in 40:
		await press(KEY_TAB)
		var f := _focus()
		if f != null and ph.is_ancestor_of(f):
			seen[f.get_instance_id()] = true
	var reachable := 0
	for c in ph.find_children("*", "", true, false):
		var ctl := c as Control
		if ctl != null and ctl.is_visible_in_tree() and ctl.focus_mode == Control.FOCUS_ALL and (ctl is Range or ctl is BaseButton):
			reachable += 1
			if not seen.has(ctl.get_instance_id()):
				log_line("not reached by Tab: %s" % ctl.name)
	check(seen.size() >= reachable and reachable >= 14, "Tab cycles through all %d panel controls (%d reached)" % [reachable, seen.size()])
	var reset := _button(ph, "Reset")
	var n := 0
	while _focus() != reset and n < 30:
		await press(KEY_TAB)
		n += 1
	await shot("q7_02_reset_focused")
	var last0 := String(ph.get("last_shot"))
	var shots0 := _user_shots().size()
	await key(KEY_ENTER)
	# Photos are written in the background (about half a second): wait long enough to see a stray one.
	await _wait(1.5)
	log_line("Enter on Reset: fov %.1f shots %d -> %d open %s" % [fov.value, shots0, _user_shots().size(), str(ph.get("is_open"))])
	check(is_equal_approx(fov.value, 60.0) and _user_shots().size() == shots0 and bool(ph.get("is_open")), "Enter on the focused Reset resets the lens (fov %.0f) and takes no photo" % fov.value)
	await key(KEY_KP_ENTER)
	await _wait(1.5)
	check(_user_shots().size() == shots0 and bool(ph.get("is_open")) and _focus() == reset, "keypad Enter presses the focused button too, no photo")
	var capb := _button(ph, "Capture")
	n = 0
	while _focus() != capb and n < 30:
		await press(KEY_TAB, 0, true)
		n += 1
	await key(KEY_ENTER)
	await _shot_after(ph, last0)
	log_line("Enter on Capture: last_shot %s focus %s" % [String(ph.get("last_shot")).get_file(), _fname()])
	check(String(ph.get("last_shot")) != last0 and _focus() == capb and bool(ph.get("is_open")), "Enter on the focused Capture saves a photo, focus comes back to Capture")
	var last1 := String(ph.get("last_shot"))
	await key(KEY_F12)
	await _shot_after(ph, last1)
	check(String(ph.get("last_shot")) != last1 and _focus() == capb, "F12 captures and keeps the panel focus")
	var panel: Control = ph.get("_panel")
	await key(KEY_H)
	await _wait(0.2)
	var hidden_ok := not panel.visible and _focus() == null
	await shot("q7_03_panel_hidden")
	await key(KEY_H)
	await _wait(0.2)
	check(hidden_ok and panel.visible and _focus() == capb, "H hides the panel (focus dropped) and H brings it back with the focus restored")
	var ex := _button(ph, "Exit")
	n = 0
	while _focus() != ex and n < 30:
		await press(KEY_TAB)
		n += 1
	await shot("q7_04_exit_focused")
	await key(KEY_ENTER)
	await _wait(0.4)
	check(not bool(ph.get("is_open")) and not get_tree().paused and not Game.photo_mode, "Enter on the focused Exit leaves photo mode and resumes the game")
	await shot("q7_05_after_exit")
	hold = false
	car_input(true)


# ------------------------------------------------------------------ q33 photo time slider vs time-reactive nodes

func _light_state() -> Dictionary:
	var out := {}
	var car := Game.player_car
	out["headlights_on"] = car.headlights_on
	var vis := car.get_node_or_null("Visual")
	var spot_on := false
	var spot_e := 0.0
	if vis != null:
		for l: SpotLight3D in vis.get("headlights"):
			if l.is_visible_in_tree():
				spot_on = true
				spot_e = maxf(spot_e, l.light_energy)
	out["spot_visible"] = spot_on
	out["spot_energy"] = snappedf(spot_e, 0.01)
	var lamps: Node = Game.env.get("lamps") if Game.env != null else null
	var lamp_max := 0.0
	if lamps != null:
		out["lamps_lit"] = lamps.call("lit_count")
		for l: OmniLight3D in lamps.get("_lights"):
			if l.visible:
				lamp_max = maxf(lamp_max, l.light_energy)
		out["street_f"] = snappedf(float(lamps.get("street_factor")), 0.01)
	out["lamp_energy_max"] = snappedf(lamp_max, 0.01)
	out["dressing_night"] = Mats.get_param(&"night", -1.0)
	if Game.traffic != null and "_lights" in Game.traffic:
		out["traffic_lights"] = Game.traffic.get("_lights")
	out["paused"] = get_tree().paused
	return out


func _group_modes() -> Dictionary:
	var out := {}
	for n in get_tree().get_nodes_in_group(Game.TIME_REACTIVE_GROUP):
		out[n.get_instance_id()] = n.process_mode
	return out


func _photo_time_to(sl: Dictionary, right: bool) -> void:
	var n := 0
	while _focus() != sl["time"] and n < 10:
		await key(KEY_DOWN)
		n += 1
	check(_focus() == sl["time"], "Time of day slider reached with Down x%d" % n)
	for i in 40:
		await key(KEY_RIGHT if right else KEY_LEFT)


func _part_phototime() -> void:
	Game.set_time_scale(0.0)
	Game.set_time_of_day(12.0)
	Game.set_weather("clear", true)
	Game.teleport("Millbrook")
	await _settle()
	car_input(false)
	hold = true
	if Game.camera_rig != null and Game.camera_rig.has_method("set_mode"):
		Game.camera_rig.call("set_mode", 1, false)
	await _wait(2.0)
	var members: PackedStringArray = []
	for nd in get_tree().get_nodes_in_group(Game.TIME_REACTIVE_GROUP):
		var scr: Script = nd.get_script()
		members.append("%s(%s)" % [nd.name, scr.resource_path.get_file() if scr else nd.get_class()])
	log_line("time-reactive group: %s" % ", ".join(members))
	# Reference: 22:00 outside photo mode.
	Game.set_time_of_day(22.0)
	await _wait(3.0)
	var ref := _light_state()
	var img := await _frame()
	img.save_png(dir.path_join("q33_a_ref_night_no_photo.png"))
	var ref_l := _luma(img)
	log_line("reference 22:00: %s luma %.3f" % [str(ref), ref_l])
	Game.set_time_of_day(12.0)
	await _wait(3.0)
	# Photo mode at noon, slider to 22:00 with the keyboard (Down to Time of day, Right x40).
	var ph := menu(&"photo")
	await key(KEY_P, 112)
	await _wait(0.5)
	var sl: Dictionary = ph.get("_sliders")
	var probe := Timer.new()
	probe.one_shot = true
	probe.wait_time = 0.3
	Game.main.add_child(probe)
	probe.add_to_group(Game.TIME_REACTIVE_GROUP)
	var fired := [false]
	probe.timeout.connect(func() -> void: fired[0] = true)
	probe.start()
	var modes0 := _group_modes()
	await _photo_time_to(sl, true)
	var during := _group_modes()
	var all_always := true
	for id: int in during:
		all_always = all_always and during[id] == Node.PROCESS_MODE_ALWAYS
	check(absf(Game.get_time_of_day() - 22.0) < 0.01 and all_always and bool(ph.call("is_pulsing")),
		"slider at %s: every time-reactive node (%d) processes during the pulse" % [MStyle.fmt_time(Game.get_time_of_day()), during.size()])
	await key(KEY_H)
	await _wait(3.0)
	var after := _group_modes()
	var restored := not bool(ph.call("is_pulsing"))
	for id: int in modes0:
		restored = restored and after.get(id, -1) == modes0[id]
	check(restored and fired[0], "pulse ends: process modes restored, a paused Timer in the group ran its %.1f s (fired %s)" % [probe.wait_time, str(fired[0])])
	probe.queue_free()
	var st := _light_state()
	img = await _frame()
	img.save_png(dir.path_join("q33_b_photo_slider22_3s.png"))
	var ph_l := _luma(img)
	log_line("photo 22:00 (+3 s): %s luma %.3f" % [str(st), ph_l])
	check(st["spot_visible"] == ref["spot_visible"] and absf(float(st["spot_energy"]) - float(ref["spot_energy"])) < 0.5,
		"photo night: player headlights match the reference (%s %.1f vs %s %.1f)" % [str(st["spot_visible"]), float(st["spot_energy"]), str(ref["spot_visible"]), float(ref["spot_energy"])])
	check(absf(float(st["lamp_energy_max"]) - float(ref["lamp_energy_max"])) < 0.3, "photo night: street lamps at %.2f of reference %.2f" % [float(st["lamp_energy_max"]), float(ref["lamp_energy_max"])])
	check(is_equal_approx(float(st["dressing_night"]), float(ref["dressing_night"])), "photo night: house windows night %.2f (reference %.2f)" % [float(st["dressing_night"]), float(ref["dressing_night"])])
	if ref.has("traffic_lights"):
		check(st["traffic_lights"] == ref["traffic_lights"], "photo night: traffic lights %s (reference %s)" % [str(st["traffic_lights"]), str(ref["traffic_lights"])])
	check(ph_l > ref_l * 0.85, "photo night frame luma %.3f vs reference %.3f" % [ph_l, ref_l])
	await key(KEY_P, 112)
	await _wait(2.0)
	log_line("closed at 22:00: %s" % str(_light_state()))
	img = await _frame()
	img.save_png(dir.path_join("q33_c_closed_night.png"))
	# Reverse: photo mode at 22:00, slider to 12:00.
	await key(KEY_P, 112)
	await _wait(0.5)
	await _photo_time_to(sl, false)
	await key(KEY_H)
	await _wait(3.0)
	var noon := _light_state()
	img = await _frame()
	img.save_png(dir.path_join("q33_d_photo_slider12_3s.png"))
	log_line("photo 12:00 (+3 s): %s" % str(noon))
	check(not bool(noon["spot_visible"]) and float(noon["lamp_energy_max"]) < 0.2 and float(noon["dressing_night"]) < 0.2 and not bool(noon.get("traffic_lights", false)),
		"photo noon: no headlights, lamps, lit windows or traffic lights left on")
	await key(KEY_P, 112)
	await _wait(1.0)
	Game.set_time_of_day(12.0)
	hold = false
	car_input(true)
	if Game.camera_rig != null and Game.camera_rig.has_method("set_mode"):
		Game.camera_rig.call("set_mode", 0, false)


# ------------------------------------------------------------------ q11 garage at night

## Screen rect of the player car (projected body box), shrunk to its middle.
func _car_rect(cam: Camera3D) -> Rect2i:
	var car := Game.player_car
	var bs := car.data.body_size
	var t := car.global_transform
	var r := Rect2()
	for i in 8:
		var local := Vector3(float(i & 1) - 0.5, float((i >> 1) & 1), float((i >> 2) & 1) - 0.5) * bs
		var sp := cam.unproject_position(t * local)
		r = Rect2(sp, Vector2.ZERO) if i == 0 else r.expand(sp)
	var inner := Rect2(r.get_center() - r.size * 0.25, r.size * 0.5)
	return Rect2i(inner).intersection(Rect2i(Vector2i.ZERO, get_viewport().get_texture().get_size()))


func _part_nightgarage() -> void:
	Game.set_time_scale(0.0)
	Game.teleport("Ring Road - Mesa Straight")
	await _settle()
	car_input(false)
	hold = true
	await _wait(1.0)
	var g := menu(&"garage")
	var cam := (Game.camera_rig as CameraRig).camera
	var pages: Array = g.get("pages")
	var results := {}
	var cases := [["13", 13.0, "clear", ""], ["19.5", 19.5, "clear", ""], ["21.5", 21.5, "clear", ""], ["23.5", 23.5, "clear", ""],
		["storm23.5", 23.5, "storm", ""], ["festival21.5", 21.5, "clear", "Sunward Festival"]]
	for cs: Array in cases:
		if String(cs[3]) != "":
			Game.teleport(cs[3])
			await _settle()
		Game.set_time_of_day(cs[1])
		Game.set_weather(cs[2], true)
		await _wait(2.0)
		await key(KEY_F1)
		await _wait(0.5)
		g.call("select_tab", 1)
		pages[1].call("set_target", 0)
		for col: String in ["yellow", "blue"]:
			pages[1].call("pick_color", Game.PAINT_COLORS[col])
			# Fixed three-quarter front view (the idle orbit would keep turning).
			var bx := Game.player_car.global_transform.basis
			var side := (bx.x - bx.z * 0.8).normalized()
			g.set("_orbit", atan2(side.x, side.z))
			g.set("_orbit_idle", 0.0)
			await _wait(1.6)
			var img := await _frame()
			img.save_png(dir.path_join("q11_%s_%s.png" % [cs[0], col]))
			var rr := _car_rect(cam)
			var mc := _mean_color(img, rr)
			results["%s_%s" % [cs[0], col]] = mc
			var key_l: OmniLight3D = g.get("_key_light")
			log_line("%s %s: car rect %s mean (%.3f, %.3f, %.3f) luma %.3f key light %s %.2f" % [cs[0], col, str(rr), mc.r, mc.g, mc.b, mc.get_luminance(),
				str(key_l.visible if key_l else false), key_l.light_energy if key_l else 0.0])
		await key(KEY_F1)
		await _wait(0.3)
	for cs: Array in cases:
		var c: String = cs[0]
		var y: Color = results[c + "_yellow"]
		var b: Color = results[c + "_blue"]
		var yel := (y.r + y.g) * 0.5 - y.b
		var blu := b.b - (b.r + b.g) * 0.5
		check(yel > 0.05 and blu > 0.03 and y.get_luminance() > 0.1, "%s: yellow (warm %.3f, luma %.3f) and blue (cool %.3f) paint readable on the showroom car" % [c, yel, y.get_luminance(), blu])
	var kl: OmniLight3D = g.get("_key_light")
	check(kl != null and not kl.visible, "showroom lights off once the garage is closed")
	Game.set_time_of_day(13.0)
	Game.set_weather("clear", true)
	hold = false
	car_input(true)


# ------------------------------------------------------------------ q12 controls page

func _part_controls() -> void:
	var pm := menu(&"pause")
	await key(KEY_ESCAPE)
	await _wait(0.4)
	await key(KEY_DOWN)
	await key(KEY_DOWN)
	await key(KEY_ENTER)
	await _wait(0.5)
	var texts := _texts(pm)
	log_line("controls texts: %s" % " | ".join(texts))
	await shot("q12_controls")
	var i := texts.find("Rewind (hold)")
	check(i >= 0 and i + 1 < texts.size() and texts[i + 1] == "Backspace", "Controls page lists 'Rewind (hold)' with Backspace")
	var pc := texts.find("Photo: capture")
	check(pc >= 0 and texts[pc + 1] == "F12", "photo capture listed on F12")
	await key(KEY_ESCAPE)
	await _wait(0.3)
	var tip := " ".join(_texts(pm))
	check(tip.contains("Backspace to rewind"), "overview tip mentions rewind")
	await shot("q12_overview")
	await key(KEY_ESCAPE)
	await _wait(0.3)
	var hint: Node = (Game.hud.get("hud") as Node).get("hint")
	var keys: Array = hint.get("KEYS")
	check(keys.any(func(kv: Array) -> bool: return String(kv[1]) == "Rewind"), "HUD controls hint shows Backspace = Rewind")
	hint.call("show_hint")
	await _wait(1.0)
	await shot("q12_hud_hint")


# ------------------------------------------------------------------ q13 debug time readouts

func _mins(t: String) -> int:
	return t.get_slice(":", 0).to_int() * 60 + t.get_slice(":", 1).to_int()


func _part_debugtime() -> void:
	var d := menu(&"debug")
	await key(KEY_F2)
	await _wait(0.6)
	await click(_button(d, "Sunset 19:00").get_global_rect().get_center())
	await _wait(0.2)
	await click(_button(d, "60x").get_global_rect().get_center())
	var lab: Label = d.get("_time_label")
	var sl: HSlider = d.get("_time_slider")
	var vl: Label = sl.get_meta(&"value_label")
	var info: Label = d.get("_info")
	var worst := 0.0
	var same_value := true
	for k in 5:
		await _wait(1.0)
		var h := Game.get_time_of_day()
		var head := info.text.get_slice("·", 4).strip_edges()
		var dl := absi(_mins(lab.text) - _mins(MStyle.fmt_time(h)))
		var dh := absi(_mins(lab.text) - _mins(head))
		worst = maxf(worst, maxf(float(maxi(dl, dh)), absf(sl.value - h) * 60.0 - 7.5))
		same_value = same_value and vl.text == lab.text
		log_line("t+%d s at 60x: game %s label %s slider %.2f value '%s' header '%s'" % [k + 1, MStyle.fmt_time(h), lab.text, sl.value, vl.text, head])
		if k == 2:
			await shot("q13_after_3s_60x")
	check(worst <= 2.0 and same_value, "gold label, slider (value + handle) and header agree while the clock runs at 60x (worst %.1f min apart)" % worst)
	# Dragging still sets the time.
	var r := sl.get_global_rect()
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.position = r.position + Vector2(r.size.x * 0.25, r.size.y * 0.5)
	e.global_position = e.position
	e.pressed = true
	Input.parse_input_event(e)
	await get_tree().process_frame
	await _wait(0.5)
	var held_h := Game.get_time_of_day()
	var released := e.duplicate() as InputEventMouseButton
	released.pressed = false
	Input.parse_input_event(released)
	await get_tree().process_frame
	log_line("click at 25%% of the Hour slider: time %s label %s" % [MStyle.fmt_time(held_h), lab.text])
	check(absf(held_h - 6.0) < 1.0, "clicking the Hour slider still sets the time (%s)" % MStyle.fmt_time(held_h))
	await click(_button(d, "1x").get_global_rect().get_center())
	await _wait(0.2)
	Game.set_time_of_day(13.0)
	await key(KEY_F2)
	await _wait(0.3)


# ------------------------------------------------------------------ q14 telemetry wheel row

const Telemetry := preload("res://scripts/ui/telemetry.gd")


func _row_gap(bw: float, sr: String, sa: String, om: String) -> float:
	var l: Dictionary = Telemetry.wheel_row_layout(bw, sr, sa, om)
	return minf(float(l["x_sa"]) - float(l["x_sr"]) - float(l["w_sr"]), float(l["x_om"]) - float(l["x_sa"]) - float(l["w_sa"]))


func _wheel_gap(bw: float) -> float:
	var g := INF
	for w: CarController.Wheel in Game.player_car.wheels:
		g = minf(g, _row_gap(bw, "SR %+.2f" % w.slip_long, "SA %+.1f°" % rad_to_deg(w.slip_angle), "%d rad/s" % int(w.omega)))
	return g


func _part_telemetry() -> void:
	var bw := (Telemetry.W - 36.0 - 8.0) * 0.5
	var worst := INF
	for c: Array in [["SR +0.00", "SA +0.0°", "0 rad/s"], ["SR +0.05", "SA +0.8°", "194 rad/s"], ["SR -0.32", "SA -20.7°", "160 rad/s"],
			["SR -1.00", "SA -36.8°", "135 rad/s"], ["SR +9.99", "SA -123.4°", "1234 rad/s"], ["SR -0.99", "SA -89.9°", "-350 rad/s"]]:
		var gap := _row_gap(bw, c[0], c[1], c[2])
		var l: Dictionary = Telemetry.wheel_row_layout(bw, c[0], c[1], c[2])
		log_line("layout %s | %s | %s -> font %d/%d gap %.1f px" % [c[0], c[1], c[2], int(l["fs"]), int(l["fo"]), gap])
		worst = minf(worst, gap)
	check(worst >= 7.9, "wheel row: >= 8 px between slip ratio, slip angle and wheel speed in every case (worst %.1f px)" % worst)
	# Real drive: Vortex X on the expressway at full speed, then a handbrake slide.
	Settings.set_value("show_telemetry", true, false)
	Game.teleport("Expressway West")
	await _settle()
	Game.spawn_car(maxi(Game.find_car_index("vortex_x"), 0), true)
	await _wait(1.0)
	car_input(false)
	var car := Game.player_car
	var res: Dictionary = (Game.world as World).data.network.nearest(car.global_position, 40.0)
	var road: RoadNetwork.Road = res["road"]
	var s0 := float(res["s"])
	var dr := 1 if road.tangent_at(s0).dot(-car.global_transform.basis.z) >= 0.0 else -1
	follower = RoadFollower.new()
	follower.setup(road, s0, dr, road.lane_offset(1) * dr if road.traffic else 0.0)
	follower.target_speed = 300.0 / 3.6
	var live_worst := INF
	var tel: Control = Game.hud.get("telemetry")
	var crop := func() -> Rect2:
		var r := tel.get_global_rect()
		return Rect2(r.position + Vector2(0, r.size.y - 230), Vector2(r.size.x, 230))
	var t := 0.0
	var shots := 0
	var top := 0.0
	while t < 40.0 and shots < 2:
		await get_tree().process_frame
		t += get_process_delta_time()
		live_worst = minf(live_worst, _wheel_gap(bw))
		var kmh := Game.player_car.get_speed_kmh()
		top = maxf(top, kmh)
		if kmh > 150.0 + shots * 50.0:
			shots += 1
			await shot("q14_%d_%dkmh_wheels_zoom2x" % [shots, roundi(kmh)], crop.call(), 2)
			log_line("%.0f km/h shot, FL omega %.0f" % [kmh, Game.player_car.wheels[0].omega])
	follower = null
	manual = {"in_throttle": 0.4, "in_brake": 0.0, "in_handbrake": 1.0, "in_steer": 0.45}
	var max_sa := 0.0
	t = 0.0
	var slide_shot := false
	while t < 2.5:
		await get_tree().process_frame
		t += get_process_delta_time()
		for w: CarController.Wheel in Game.player_car.wheels:
			max_sa = maxf(max_sa, absf(rad_to_deg(w.slip_angle)))
		live_worst = minf(live_worst, _wheel_gap(bw))
		if not slide_shot and max_sa > 12.0:
			slide_shot = true
			await shot("q14_3_slide_wheels_zoom2x", crop.call(), 2)
			await shot("q14_3_slide_full")
	manual = {"in_throttle": 0.0, "in_brake": 1.0, "in_handbrake": 0.0, "in_steer": 0.0}
	await _wait(2.0)
	manual = {}
	check(live_worst >= 7.9, "live drive (top %.0f km/h) + slide (max slip angle %.1f°): row gap never below 8 px (worst %.1f px)" % [top, max_sa, live_worst])
	Settings.set_value("show_telemetry", false, false)
	Game.spawn_car(0, true)
	car_input(true)


# ------------------------------------------------------------------ q15 minimap region plate

func _part_minimap() -> void:
	var mm: Control = Game.hud.get("minimap")
	car_input(false)
	hold = true
	for c: Array in [["Ironcrest Pass", "IRONCREST HIGHLANDS"], ["Ring Road - Mesa Straight", "OCHRE MESA"], ["Gullhaven", "SALTWIND COAST"]]:
		Game.teleport(c[0])
		await _settle()
		await _wait(1.0)
		var rl: Label = mm.get("_region_label")
		var road: Label = mm.get("_road_label")
		var pw := float(mm.get("_plate_w"))
		var tw := Style3.text_width(rl.text, 20, 700, false, 3)
		var map_px := float(mm.get("MAP"))
		var pad := float(mm.get("PAD"))
		var plate := Rect2(mm.global_position + Vector2(pad + map_px * 0.5 - pw * 0.5, map_px + pad * 2.0 + 4.0), Vector2(pw, 58.0))
		# Label pixels = difference between a frame with and without the two labels.
		get_tree().paused = true
		await _wait(0.2)
		var a := await _frame()
		rl.visible = false
		road.visible = false
		await get_tree().process_frame
		var b := await _frame()
		rl.visible = true
		road.visible = true
		get_tree().paused = false
		var outside := 0
		var total := 0
		var box := Rect2i(plate.grow(40.0)).intersection(Rect2i(Vector2i.ZERO, a.get_size()))
		var inner := plate.grow(-2.0)
		for y in range(box.position.y, box.end.y):
			for x in range(box.position.x, box.end.x):
				if absf(a.get_pixel(x, y).get_luminance() - b.get_pixel(x, y).get_luminance()) > 0.2:
					total += 1
					if not inner.has_point(Vector2(x, y)):
						outside += 1
		log_line("%s: label '%s' %.1f px, road '%s', plate %.1f px at %s, label pixels %d, outside the plate %d" % [c[0], rl.text, tw, road.text, pw, str(plate), total, outside])
		await shot("q15_%s_zoom3x" % rl.text.to_lower().replace(" ", "_"), Rect2(plate.position - Vector2(30, 30), plate.size + Vector2(60, 50)), 3)
		check(rl.text == c[1] and pw >= tw + 36.0 and outside == 0 and total > 200, "%s: region name inside its plate (%d of %d label pixels outside)" % [c[1], outside, total])
	hold = false
	car_input(true)


# ------------------------------------------------------------------ q16 console stripes completion

func _part_stripes() -> void:
	var con := menu(&"console")
	var line: LineEdit = con.get("_line")
	await key(KEY_QUOTELEFT, 96)
	await _wait(0.6)
	var cases := [["stripes 2 ", "stripes 2 ", "red"], ["stripes 2 re", "stripes 2 red ", ""], ["stripes 2 bl", "stripes 2 bl", "blue"],
		["stripes ", "stripes ", "0   1   2   3   4   5"], ["stripes 4", "stripes 4 ", ""], ["paint red ", "paint red ", "gloss"], ["rims go", "rims gold ", ""]]
	for c: Array in cases:
		line.clear()
		await type_text(c[0])
		var before := _console_last(con)
		await key(KEY_TAB)
		await _wait(0.15)
		var tail := _console_last(con)
		var listed := tail if tail != before else ""
		log_line("'%s' + Tab -> line '%s' listed '%s'" % [c[0], line.text, listed])
		var no_finish := not (String(c[0]).begins_with("stripes") and listed.contains("gloss"))
		check(line.text == c[1] and (String(c[2]) == "" or listed.contains(c[2])) and no_finish,
			"completion of '%s' -> '%s'%s" % [c[0], c[1], "" if String(c[2]) == "" else " (lists %s)" % c[2]])
		if c[0] == "stripes 2 re" or c[0] == "stripes 2 ":
			await shot("q16_%s_tab" % String(c[0]).strip_edges().replace(" ", "_"))
	line.clear()
	await key(KEY_QUOTELEFT, 96)
	await _wait(0.4)


# ------------------------------------------------------------------ q30 result banner

func _part_result() -> void:
	var act: Node = (Game.hud.get("hud") as Node).get("activity")
	Game.teleport("Sunward Festival")
	await _settle()
	var cases := [
		["race_4th", {"title": "Highmoor Hillclimb", "score_text": "06:04.49", "personal_best": true, "medal": "", "kind": &"race", "detail": "4th of 4"}, Vector2i(4, 4), "Highmoor Hillclimb"],
		["race_1st", {"title": "Saltwind Coast Sprint", "score_text": "02:11.80", "personal_best": true, "medal": "Gold", "kind": &"race", "detail": "1st of 4"}, Vector2i(1, 4), "Saltwind Coast Sprint"],
		["time_trial", {"title": "Sunward Ring Time Trial", "score_text": "11:02.10", "personal_best": false, "medal": "Silver", "kind": &"time_trial", "detail": ""}, Vector2i.ZERO, "Sunward Ring Time Trial"],
	]
	for c: Array in cases:
		Game.activity_finished.emit("test_" + String(c[0]), c[1])
		await _wait(1.0)
		await shot("q30_%s_banner" % c[0], Rect2(Vector2(360, 200), Vector2(1200, 280)))
		var place: Vector2i = act.get("_place")
		var sub: String = act.call("banner_subtitle", c[1], place)
		check(place == c[2] and sub == c[3], "%s: banner place %s, title line '%s'" % [c[0], str(place), sub])
		await _wait(5.0)
	# Real festival flag pickup: drive into the first uncollected flag.
	var target: Dictionary = {}
	for f: Dictionary in Game.activities.call("get_collectibles"):
		if not bool(f["collected"]):
			target = f
			break
	if target.is_empty():
		log_line("all flags collected, flag case skipped")
		return
	var got := [{}]
	var cb := func(_id: String, r: Dictionary) -> void: got[0] = r
	Game.activity_finished.connect(cb)
	var pos: Vector3 = target["position"]
	var road_res: Dictionary = (Game.world as World).data.network.nearest(pos, 200.0)
	var fwd := pos - (road_res["position"] as Vector3) if not road_res.is_empty() else Vector3.FORWARD
	fwd.y = 0.0
	if fwd.length() < 2.0:
		fwd = (road_res["forward"] as Vector3) if not road_res.is_empty() else Vector3.FORWARD
		fwd.y = 0.0
	fwd = fwd.normalized()
	Game.main.call("teleport_to", {"position": pos - fwd * 14.0, "forward": fwd})
	await _settle()
	car_input(false)
	manual = {"in_throttle": 0.35, "in_brake": 0.0, "in_handbrake": 0.0, "in_steer": 0.0}
	var t := 0.0
	while (got[0] as Dictionary).is_empty() and t < 12.0:
		await get_tree().process_frame
		t += get_process_delta_time()
	manual = {"in_throttle": 0.0, "in_brake": 1.0, "in_handbrake": 0.0, "in_steer": 0.0}
	await _wait(0.9)
	await shot("q30_flag_banner")
	manual = {}
	Game.activity_finished.disconnect(cb)
	var r: Dictionary = got[0]
	log_line("flag '%s' result %s" % [target["name"], str(r)])
	var sub2: String = act.call("banner_subtitle", r, act.get("_place"))
	check(not r.is_empty() and sub2.contains(String(target["name"])), "flag '%s' picked up for real: banner title line '%s'" % [target["name"], sub2])
	car_input(true)


# ------------------------------------------------------------------ s26 garage showroom framing

## Screen rect of the car's visual mesh bounds (all AABB corners projected through the live camera).
func _car_screen_rect(cam: Camera3D) -> Rect2:
	var r := Rect2()
	var first := true
	for n in Game.player_car.get_node("Visual").find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null or not mi.is_visible_in_tree():
			continue
		var b := mi.get_aabb()
		for k in 8:
			var sp := cam.unproject_position(mi.global_transform * b.get_endpoint(k))
			r = Rect2(sp, Vector2.ZERO) if first else r.expand(sp)
			first = false
	return r


func _part_garagefit() -> void:
	var g := menu(&"garage")
	var cam := (Game.camera_rig as CameraRig).camera
	var vp := get_viewport().get_visible_rect().size
	var cases := [["mesa_castellan", "Ring Road - Mesa Straight", 13.0, "castellan_gt"], ["millbrook_kestrel", "Millbrook", 22.5, "kestrel_r4"],
		["festival_hauler", "Sunward Festival", 13.0, "hauler_2500"], ["millbrook_vortex", "Millbrook", 13.0, "vortex_x"]]
	for cs: Array in cases:
		Game.teleport(cs[1])
		await _settle()
		Game.set_time_of_day(cs[2])
		Game.spawn_car(maxi(Game.find_car_index(cs[3]), 0), true)
		car_input(false)
		hold = true
		await _wait(1.5)
		await key(KEY_F1)
		await _wait(1.5)
		var col: Control = g.get("_col")
		var worst_hidden := 0.0
		var worst_right := 0.0
		var blocked := 0
		var widths: PackedFloat32Array = []
		var car_yaw := Game.player_car.global_rotation.y
		for i in 16:
			var rel_deg := 22.5 * i
			g.set("_orbit", car_yaw + deg_to_rad(rel_deg))
			g.set("_orbit_idle", 0.0)
			await _wait(1.0)
			var left := col.get_global_rect().end.x
			var r := _car_screen_rect(cam)
			var hidden := clampf((left - r.position.x) / maxf(r.size.x, 1.0), 0.0, 1.0)
			var over_right := maxf(r.end.x - vp.x, 0.0)
			worst_hidden = maxf(worst_hidden, hidden)
			worst_right = maxf(worst_right, over_right)
			var center: Vector3 = Game.player_car.global_position + Vector3.UP * 0.6
			var q := PhysicsRayQueryParameters3D.create(cam.global_position, center, 1 | 32, [Game.player_car.get_rid()])
			var hit := Game.player_car.get_world_3d().direct_space_state.intersect_ray(q)
			if not hit.is_empty():
				blocked += 1
			widths.append(r.size.x)
			log_line("%s orbit %5.1f deg: car x %.0f..%.0f y %.0f..%.0f (column edge %.0f) hidden %.0f%% dist %.1f m h_offset %.2f %s" % [cs[0], rel_deg,
				r.position.x, r.end.x, r.position.y, r.end.y, left, hidden * 100.0, cam.global_position.distance_to(center), cam.h_offset,
				"BLOCKED by %s" % (hit["collider"] as Node).name if not hit.is_empty() else ""])
			if i % 4 == 0 or i % 4 == 1:
				await shot("%s_orbit_%03d" % [cs[0], int(rel_deg)])
		var wmin := 1e9
		var wmax := 0.0
		for w: float in widths:
			wmin = minf(wmin, w)
			wmax = maxf(wmax, w)
		var free_w := vp.x - col.get_global_rect().end.x
		check(worst_hidden <= 0.0 and worst_right <= 0.0, "%s: car inside the free area at all 16 orbit angles (worst hidden behind the column %.0f%%, past the right edge %.0f px)" % [cs[0], worst_hidden * 100.0, worst_right])
		check(wmax > free_w * 0.6, "%s: car still fills the free area (on-screen width %.0f..%.0f px of %.0f)" % [cs[0], wmin, wmax, free_w])
		check(blocked == 0, "%s: nothing (fence, wall, building) between the camera and the car (%d of 16 angles blocked)" % [cs[0], blocked])
		await key(KEY_F1)
		await _wait(0.5)
		hold = false
		car_input(true)
	Game.spawn_car(0, true)
	Game.set_time_of_day(13.0)
