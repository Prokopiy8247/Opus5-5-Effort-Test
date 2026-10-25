extends "res://scripts/ui/menu_base.gd"
## Debug / benchmark menu (toggle_debug_menu: F2): teleports, car spawn, time/weather/traffic,
## assists, readout toggles, car actions and a 60 s ring-road auto-drive benchmark. The benchmark runs
## on an empty road (traffic capped to 0, running event cancelled, event prompts not shown), so its pace
## and route are the same on every run.

const Actions := preload("res://scripts/ui/menu_actions.gd")
const BENCH_SECONDS := 60.0
const BENCH_SPEED_KMH := 110.0
const BENCH_START_S := 40.0
const TIME_PRESETS := [["Dawn", 6.0], ["Noon", 12.0], ["Sunset", 19.0], ["Night", 23.0]]

var _info: Label
var _teleports: VBoxContainer
var _car_buttons: Array[Button] = []
var _time_label: Label
var _time_slider: HSlider
var _scale_edit: LineEdit
var _weather_box: HFlowContainer
var _weather_buttons: Dictionary = {}
var _traffic_toggle: CheckButton
var _traffic_slider: HSlider
var _assist_toggles: Dictionary = {}
var _display_toggles: Dictionary = {}
var _bench_label: RichTextLabel
var _bench_button: Button
var _env_note: Label
var _time_dragging: bool = false

# Benchmark state: 0 idle, 1 preparing (streaming), 2 running.
var bench_phase: int = 0
var bench_result: Dictionary = {}
var _bench_follower: RoadFollower
var _bench_road: RoadNetwork.Road
var _bench_t: float = 0.0
var _bench_prep: float = 0.0
var _bench_frames: int = 0
var _bench_worst: float = 0.0
var _bench_dist: float = 0.0
var _bench_times: PackedFloat32Array = []
var _bench_last: Vector3
var _bench_stuck: float = 0.0
var _bench_overlay: PanelContainer
var _bench_overlay_label: Label
var _bench_duration: float = BENCH_SECONDS
var _last_scale: float = 1.0


func _init() -> void:
	super._init()
	menu_id = &"debug"
	toggle_action = &"toggle_debug_menu"
	hides_hud = true
	process_physics_priority = 10


func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.01, 0.015, 0.03, 0.45)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	var panel := Style.panel(Color(0.04, 0.05, 0.085, 0.94), 18, 26, 1, Color(1, 1, 1, 0.08))
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.offset_left = 48
	panel.offset_top = 40
	panel.offset_right = -48
	panel.offset_bottom = -36
	add_child(panel)
	var root := Style.vbox(14)
	panel.add_child(root)

	var head := Style.hbox(18)
	var tv := Style.vbox(4)
	tv.add_child(Style.title("Debug & Benchmark", 40))
	tv.add_child(Style.accent_bar(160, 5))
	head.add_child(tv)
	head.add_child(Style.expander())
	_info = Style.label("", 20, Style.TEXT_DIM, 500)
	_info.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(_info)
	root.add_child(head)

	var cols := Style.hbox(22)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(cols)
	cols.add_child(_column("Teleport", _build_teleport_column(), 500))
	cols.add_child(_column("Car", _build_car_column(), 540))
	cols.add_child(_column("World", _build_world_column(), 0))
	root.add_child(Style.hint_bar([["Enter", "Activate"], ["Arrows", "Navigate"], ["Esc", "Close"], ["F2", "Debug menu"]]))


func _column(title: String, content: Control, w: float) -> Control:
	var v := Style.vbox(10)
	v.custom_minimum_size = Vector2(w, 0)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL if w <= 0.0 else Control.SIZE_FILL
	var h := Style.hbox(10)
	var bar := ColorRect.new()
	bar.color = Style.ACCENT
	bar.custom_minimum_size = Vector2(4, 22)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(bar)
	h.add_child(Style.label(title.to_upper(), 22, Style.TEXT, 700, 2))
	v.add_child(h)
	var sc := Style.scroll()
	sc.add_child(content)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(sc)
	return v


func _sub(text: String) -> Label:
	var l := Style.caps(text, 16, Style.TEXT_FAINT)
	return l


# ------------------------------------------------------------------ columns

func _build_teleport_column() -> Control:
	_teleports = Style.vbox(6)
	return _teleports


func _fill_teleports() -> void:
	for c in _teleports.get_children():
		c.queue_free()
	for g: Array in Actions.grouped_targets():
		var items: Array = g[1]
		if items.is_empty():
			continue
		_teleports.add_child(Style.spacer(4))
		_teleports.add_child(_sub("%s  (%d)" % [g[0], items.size()]))
		for t: Dictionary in items:
			var b := Style.button("", _teleport.bind(String(t["name"])), 0, 42)
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			var h := Style.hbox(8)
			h.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var n := Style.label(String(t["name"]), 20, Style.TEXT, 600)
			n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			n.clip_text = true
			h.add_child(n)
			var kind := String(t.get("kind", ""))
			var tag := String(t.get("region", "")) if kind == "road" or kind == "region" else "%s · %s" % [kind.capitalize(), String(t.get("region", ""))]
			h.add_child(Style.label(tag, 16, Style.TEXT_FAINT))
			b.add_child(h)
			h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			h.offset_left = 14
			h.offset_right = -12
			_teleports.add_child(b)


func _build_car_column() -> Control:
	var v := Style.vbox(8)
	v.add_child(_sub("Spawn car"))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	var cat := Game.get_car_catalog()
	for i in cat.size():
		var b := Style.button("%d  %s" % [i + 1, cat[i].display_name], _spawn.bind(i), 0, 42)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size", 19)
		grid.add_child(b)
		_car_buttons.append(b)
	v.add_child(grid)
	v.add_child(Style.spacer(4))
	v.add_child(_sub("Car actions"))
	var acts := Style.hbox(8)
	for a: Array in [["Repair", func() -> void: Game.repair()], ["Flip reset", func() -> void: Game.flip_reset()], ["Respawn on road", func() -> void: Game.respawn()]]:
		var b := Style.button(a[0], a[1], 0, 44)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		acts.add_child(b)
	v.add_child(acts)
	v.add_child(Style.spacer(4))
	v.add_child(_sub("Benchmark"))
	_bench_button = Style.primary(Style.button("Benchmark: auto-drive %d s" % int(BENCH_SECONDS), start_benchmark, 0, 50))
	v.add_child(_bench_button)
	var bp := Style.panel(Style.CARD, 10, 12)
	_bench_label = RichTextLabel.new()
	_bench_label.bbcode_enabled = true
	_bench_label.fit_content = true
	_bench_label.scroll_active = false
	_bench_label.focus_mode = Control.FOCUS_NONE
	_bench_label.add_theme_font_size_override("normal_font_size", 19)
	_bench_label.add_theme_font_size_override("bold_font_size", 19)
	_bench_label.text = "[color=#%s]Drives the ring road from the festival on autopilot (up to %d km/h, traffic and events paused) and measures frame times. Any key cancels.[/color]" % [Style.TEXT_DIM.to_html(false), int(BENCH_SPEED_KMH)]
	bp.add_child(_bench_label)
	v.add_child(bp)
	v.add_child(Style.spacer(4))
	v.add_child(_sub("Readouts"))
	for d: Array in [["show_fps", "FPS / position / speed readout"], ["show_telemetry", "Telemetry (rpm, slip, surface)"], ["hud_visible", "HUD visible"], ["units_mph", "Imperial units (mph)"]]:
		var key: String = d[0]
		var t := Style.toggle(d[1], bool(Settings.get_value(key, false)), func(on: bool) -> void: Settings.set_value(key, on))
		_display_toggles[key] = t
		v.add_child(t)
	return v


func _build_world_column() -> Control:
	var v := Style.vbox(8)
	_env_note = Style.label("Environment system not loaded - time and weather are unavailable", 18, Style.BAD)
	_env_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_env_note.visible = false
	v.add_child(_env_note)
	var th := Style.hbox(10)
	th.add_child(_sub("Time of day"))
	th.add_child(Style.expander())
	_time_label = Style.label("12:00", 28, Style.GOLD, 700)
	th.add_child(_time_label)
	v.add_child(th)
	_time_slider = Style.slider_row("Hour", 0.0, 24.0, 0.25, 12.0, func(x: float) -> String: return Style.fmt_time(x), func(x: float) -> void:
		Game.set_time_of_day(fmod(x, 24.0))
		_time_label.text = Style.fmt_time(x), 110)
	v.add_child(_time_slider.get_meta(&"row"))
	_time_slider.drag_started.connect(func() -> void: _time_dragging = true)
	_time_slider.drag_ended.connect(func(_changed: bool) -> void: _time_dragging = false)
	var pr := Style.hbox(8)
	for p: Array in TIME_PRESETS:
		var b := Style.button("%s %s" % [p[0], Style.fmt_time(p[1])], _set_time.bind(float(p[1])), 0, 42)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size", 18)
		pr.add_child(b)
	v.add_child(pr)
	var sr := Style.hbox(8)
	var sl := Style.label("Time scale", 20, Style.TEXT_DIM)
	sl.custom_minimum_size = Vector2(110, 0)
	sl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	sr.add_child(sl)
	_scale_edit = LineEdit.new()
	_scale_edit.text = "1"
	_scale_edit.custom_minimum_size = Vector2(90, 42)
	_scale_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_scale_edit.text_submitted.connect(func(t: String) -> void: _apply_scale(t))
	sr.add_child(_scale_edit)
	for s: float in [0.0, 1.0, 10.0, 60.0]:
		var b := Style.button("%dx" % int(s), func() -> void:
			_scale_edit.text = str(int(s))
			_apply_scale(_scale_edit.text), 0, 42)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sr.add_child(b)
	v.add_child(sr)
	v.add_child(Style.spacer(4))
	v.add_child(_sub("Weather"))
	_weather_box = HFlowContainer.new()
	_weather_box.add_theme_constant_override("h_separation", 8)
	_weather_box.add_theme_constant_override("v_separation", 8)
	v.add_child(_weather_box)
	v.add_child(Style.spacer(4))
	v.add_child(_sub("Traffic"))
	_traffic_toggle = Style.toggle("Traffic", true, func(on: bool) -> void:
		var dv := _traffic_slider.value if _traffic_slider.value > 0.01 else 0.6
		Game.set_traffic_density(dv if on else 0.0)
		if on:
			Style.set_slider(_traffic_slider, dv))
	v.add_child(_traffic_toggle)
	_traffic_slider = Style.slider_row("Density", 0.0, 1.0, 0.05, 0.6, func(x: float) -> String: return "%d%%" % roundi(x * 100.0), func(x: float) -> void:
		Game.set_traffic_density(x)
		_traffic_toggle.set_pressed_no_signal(x > 0.01), 110)
	v.add_child(_traffic_slider.get_meta(&"row"))
	v.add_child(Style.spacer(4))
	v.add_child(_sub("Assists"))
	var ag := GridContainer.new()
	ag.columns = 2
	ag.add_theme_constant_override("h_separation", 8)
	ag.add_theme_constant_override("v_separation", 8)
	for a: Array in [["tcs", "Traction control"], ["stm", "Stability control"], ["abs", "ABS"], ["steering", "Steering assist"], ["auto", "Automatic gearbox"], ["line", "Braking line"]]:
		var key: String = a[0]
		var t := Style.toggle(a[1], false, func(on: bool) -> void: Game.set_assist(key, on))
		t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_assist_toggles[key] = t
		ag.add_child(t)
	v.add_child(ag)
	return v


# ------------------------------------------------------------------ actions

func _teleport(target: String) -> void:
	# Prefer the HUD's fast travel (fade + hold until the terrain has streamed in).
	if Game.hud != null and Game.hud.has_method("fast_travel"):
		close_menu()
		Game.hud.call("fast_travel", target)
	elif Game.teleport(target):
		toast("Teleported to %s" % target, Style.ACCENT)


func _spawn(i: int) -> void:
	Game.spawn_car(i, true)
	_sync_cars()
	toast("Spawned the %s" % Game.get_car_catalog()[i].display_name, Style.ACCENT)


func _set_time(h: float) -> void:
	Game.set_time_of_day(h)
	_show_time(h)


## Gold readout, slider handle and slider value follow the running clock (one exact time everywhere;
## the handle snaps to the slider's 15 min step).
func _show_time(h: float) -> void:
	var txt := Style.fmt_time(h)
	if _time_label.text == txt:
		return
	Style.set_slider(_time_slider, h)
	_time_label.text = txt
	(_time_slider.get_meta(&"value_label") as Label).text = txt


func _apply_scale(t: String) -> void:
	var s := t.strip_edges()
	if not s.is_valid_float() or s.to_float() < 0.0:
		toast("Time scale must be a number of 0 or more", Style.BAD)
		_scale_edit.text = str(_last_scale)
		return
	_last_scale = s.to_float()
	Game.set_time_scale(_last_scale)
	# Show the value actually applied (environment clamps), not the raw text.
	_last_scale = Game.get_time_scale()
	_scale_edit.text = str(_last_scale)
	toast("Time scale %sx" % str(_last_scale), Style.ACCENT)


func _set_weather(id: String) -> void:
	Game.set_weather(id, true)
	_sync_weather()


# ------------------------------------------------------------------ open / sync

func _on_opened() -> void:
	_fill_teleports()
	_sync()
	_focus_first.call_deferred()


func _focus_first() -> void:
	if not _car_buttons.is_empty():
		_car_buttons[clampi(Game.current_car_index, 0, _car_buttons.size() - 1)].grab_focus()


func _sync() -> void:
	_sync_cars()
	var has_env := Game.env != null
	_env_note.visible = not has_env
	_time_slider.editable = has_env
	_time_label.text = ""
	_show_time(Game.get_time_of_day())
	if has_env and "time_scale" in Game.env:
		_last_scale = float(Game.env.get("time_scale"))
		_scale_edit.text = str(snappedf(_last_scale, 0.01))
	_sync_weather()
	var dens := Game.get_traffic_density()
	_traffic_toggle.set_pressed_no_signal(dens > 0.01)
	Style.set_slider(_traffic_slider, dens)
	var st := Game.get_assists()
	for k: String in _assist_toggles:
		(_assist_toggles[k] as CheckButton).set_pressed_no_signal(bool(st.get(k, false)))
	for k: String in _display_toggles:
		(_display_toggles[k] as CheckButton).set_pressed_no_signal(bool(Settings.get_value(k, false)))
	_show_bench_result()


func _sync_cars() -> void:
	for i in _car_buttons.size():
		var cur := i == Game.current_car_index
		_car_buttons[i].add_theme_color_override("font_color", Style.GOLD if cur else Style.TEXT)
		_car_buttons[i].add_theme_stylebox_override("normal", Style.box(Color(0.16, 0.11, 0.08, 0.96) if cur else Color(0.12, 0.14, 0.21, 0.92), 10, 2 if cur else 1, Color(Style.ACCENT, 0.7) if cur else Style.LINE, 8))


func _sync_weather() -> void:
	var ids := Game.get_weather_ids()
	if _weather_buttons.size() != ids.size():
		for c in _weather_box.get_children():
			c.queue_free()
		_weather_buttons.clear()
		for id: Variant in ids:
			var b := Style.button(String(id).capitalize(), _set_weather.bind(String(id)), 120, 44)
			b.toggle_mode = true
			_weather_box.add_child(b)
			_weather_buttons[String(id)] = b
	var cur := String(Game.get_weather())
	for k: String in _weather_buttons:
		(_weather_buttons[k] as Button).set_pressed_no_signal(k == cur)


func _process(_delta: float) -> void:
	if is_open:
		_update_info()
	if bench_phase > 0:
		_bench_frame()


func _update_info() -> void:
	if not _time_dragging:
		_show_time(Game.get_time_of_day())
	var car := Game.player_car
	if car == null or not is_instance_valid(car):
		return
	var p := car.global_position
	var region: String = Game.world.region_at(p) if Game.world else ""
	_info.text = "%d FPS   ·   %s   ·   x %d  y %d  z %d   ·   %s   ·   %s   ·   %s" % [
		Engine.get_frames_per_second(), Style.speed_text(car.get_speed_kmh()), roundi(p.x), roundi(p.y), roundi(p.z), region,
		Style.fmt_time(Game.get_time_of_day()), String(Game.get_weather()).capitalize()]


# ------------------------------------------------------------------ benchmark

func start_benchmark(duration := BENCH_SECONDS) -> void:
	var w := Game.world as World
	_bench_road = w.data.network.get_road("ring") if w else null
	if _bench_road == null or Game.player_car == null:
		toast("Benchmark needs the open world ring road", Style.BAD)
		return
	_bench_duration = duration
	close_menu()
	if Game.activities != null and Game.activities.has_method("cancel_session"):
		Game.activities.call("cancel_session", "Event cancelled - benchmark started")
	Game.benchmark_mode = true
	# Same empty road every run: traffic ahead would set the pace and the stretch of world covered.
	_cap_traffic(true)
	_set_car_input(false)
	_bench_follower = RoadFollower.new()
	_bench_follower.setup(_bench_road, BENCH_START_S, 1, _bench_road.lane_offset(1))
	_bench_follower.target_speed = BENCH_SPEED_KMH / 3.6
	Game.main.teleport_to({"position": _bench_follower.lane_point(BENCH_START_S), "forward": _bench_road.flat_tangent_at(BENCH_START_S)})
	bench_phase = 1
	_bench_prep = 0.0
	_show_overlay("Benchmark  ·  streaming the ring road...")
	print("[bench] start ring road, %s, %.0f s" % [Game.current_car_data().display_name, duration])


func cancel_benchmark() -> void:
	if bench_phase > 0:
		_finish_benchmark(true)


func _cap_traffic(on: bool) -> void:
	if Game.traffic != null and Game.traffic.has_method("set_density_cap"):
		Game.traffic.call("set_density_cap", 0.0 if on else 1.0)


func _set_car_input(on: bool) -> void:
	var ci: Variant = Game.main.get("car_input") if Game.main else null
	if ci is CarInput:
		(ci as CarInput).enabled = on


func _physics_process(delta: float) -> void:
	if bench_phase == 0:
		return
	var car := Game.player_car
	if car == null or not is_instance_valid(car):
		_finish_benchmark(true)
		return
	# The benchmark owns the car: CarInput is disabled, so the menu hold it set while the debug menu was
	# open would otherwise stay on (no drive, brakes applied) for the whole run.
	car.in_hold = false
	if bench_phase == 1:
		# Hold still on the handbrake: a full brake pedal at standstill engages reverse.
		car.in_throttle = 0.0
		car.in_brake = 0.3
		car.in_handbrake = 1.0
		car.in_steer = 0.0
		return
	_bench_follower.drive(car, delta)


func _bench_frame() -> void:
	var dt := get_process_delta_time()
	var car := Game.player_car
	if car == null or not is_instance_valid(car):
		return
	if bench_phase == 1:
		_bench_prep += dt
		var w := Game.world as World
		var streamed := w == null or (w.terrain.pending_count() == 0 and w.roads.done)
		if (streamed and _bench_prep > 1.5) or _bench_prep > 12.0:
			bench_phase = 2
			_bench_t = 0.0
			_bench_frames = 0
			_bench_worst = 0.0
			_bench_dist = 0.0
			_bench_stuck = 0.0
			_bench_times = PackedFloat32Array()
			_bench_last = car.global_position
		return
	_bench_t += dt
	_bench_frames += 1
	if _bench_t > 2.0:
		_bench_worst = maxf(_bench_worst, dt)
		_bench_times.append(dt)
	_bench_dist += car.global_position.distance_to(_bench_last)
	_bench_last = car.global_position
	_bench_stuck = _bench_stuck + dt if car.speed_ms < 2.0 else 0.0
	if _bench_stuck > 6.0:
		_bench_stuck = 0.0
		_bench_follower.s += 20.0
		Game.main.teleport_to({"position": _bench_follower.lane_point(_bench_follower.s), "forward": _bench_road.flat_tangent_at(_bench_follower.s)})
		_bench_last = Game.player_car.global_position
	_bench_overlay_label.text = "BENCHMARK  %02d / %02d s   ·   %d FPS   ·   %.2f km   ·   any key cancels" % [
		int(_bench_t), int(_bench_duration), Engine.get_frames_per_second(), _bench_dist / 1000.0]
	if _bench_t >= _bench_duration:
		_finish_benchmark(false)


func _finish_benchmark(cancelled: bool) -> void:
	var was_running := bench_phase == 2
	bench_phase = 0
	# An event the autopilot armed on the way is dropped while its prompts are still muted.
	if Game.activities != null and Game.activities.has_method("cancel_session"):
		Game.activities.call("cancel_session", "Event cancelled - benchmark")
	Game.benchmark_mode = false
	_cap_traffic(false)
	_set_car_input(true)
	if _bench_overlay:
		_bench_overlay.visible = false
	var car := Game.player_car
	if car and is_instance_valid(car):
		car.in_throttle = 0.0
		car.in_brake = 0.0
		car.in_handbrake = 0.0
	var t := maxf(_bench_t, 0.001)
	var p1 := 0.0
	if _bench_times.size() > 10:
		var sorted := _bench_times.duplicate()
		sorted.sort()
		p1 = sorted[int(sorted.size() * 0.99)]
	bench_result = {
		"cancelled": cancelled, "ran": was_running, "seconds": t, "frames": _bench_frames,
		"avg_fps": _bench_frames / t, "worst_ms": _bench_worst * 1000.0, "p99_ms": p1 * 1000.0,
		"low1_fps": 1.0 / p1 if p1 > 0.0 else 0.0, "distance_km": _bench_dist / 1000.0,
		"avg_kmh": _bench_dist / t * 3.6, "car": Game.current_car_data().display_name if Game.current_car_data() else "",
	}
	print("[bench] %s" % JSON.stringify(bench_result))
	open_menu()


func _show_bench_result() -> void:
	if bench_result.is_empty():
		return
	var r := bench_result
	var head := "[b]Last run[/b]  %s" % r["car"]
	if r["cancelled"]:
		head += "  [color=#%s](cancelled after %d s)[/color]" % [Style.BAD.to_html(false), int(r["seconds"])]
	if not r["ran"]:
		_bench_label.text = head
		return
	var hi := Style.GOLD.to_html(false)
	_bench_label.text = head + "\n[color=#%s]Average[/color] [b][color=#%s]%.1f FPS[/color][/b]    [color=#%s]1%% low[/color] [b]%.1f FPS[/b]\n[color=#%s]Worst frame[/color] [b]%.1f ms[/b]    [color=#%s]Distance[/color] [b]%.2f km[/b] at %d km/h avg" % [
		Style.TEXT_DIM.to_html(false), hi, r["avg_fps"], Style.TEXT_DIM.to_html(false), r["low1_fps"],
		Style.TEXT_DIM.to_html(false), r["worst_ms"], Style.TEXT_DIM.to_html(false), r["distance_km"], roundi(r["avg_kmh"])]


func _show_overlay(text: String) -> void:
	if _bench_overlay == null:
		_bench_overlay = Style.panel(Style.PANEL_HI, 12, 12, 2, Style.ACCENT)
		_bench_overlay.process_mode = Node.PROCESS_MODE_ALWAYS
		_bench_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_bench_overlay.theme = Style.theme()
		_bench_overlay_label = Style.label("", 22, Style.TEXT, 600)
		_bench_overlay.add_child(_bench_overlay_label)
		get_parent().add_child(_bench_overlay)
		# Zero-width rect on the top-centre anchor that grows both ways: stays centred while the text changes.
		_bench_overlay.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
		_bench_overlay.grow_horizontal = Control.GROW_DIRECTION_BOTH
		_bench_overlay.offset_left = 0
		_bench_overlay.offset_right = 0
		_bench_overlay.offset_top = 24
		_bench_overlay.offset_bottom = 24
	_bench_overlay_label.text = text
	_bench_overlay.visible = true


func _input(event: InputEvent) -> void:
	if bench_phase > 0:
		var key := event as InputEventKey
		if key != null and key.pressed and not key.echo:
			cancel_benchmark()
			get_viewport().set_input_as_handled()
		return
	super._input(event)


func _exit_tree() -> void:
	if bench_phase > 0:
		bench_phase = 0
		Game.benchmark_mode = false
		_cap_traffic(false)
	if _bench_overlay and is_instance_valid(_bench_overlay):
		_bench_overlay.queue_free()
	super._exit_tree()
