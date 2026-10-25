class_name DebugMenu
extends CanvasLayer
## Benchmark / debug menu (F3): teleports, car spawn, time and weather, traffic density,
## assists, overlays, repair/flip, and live telemetry (rpm, slip, loads, surfaces, g).

var is_open: bool = false
var _root: Control
var _panel: PanelContainer
var _telemetry: Label
var _car_pick: OptionButton
var _time_slider: HSlider
var _density: HSlider
var _assist_boxes: Dictionary = {}
var _tp_box: GridContainer
var _updating: bool = false


func _ready() -> void:
	layer = 45
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.theme = UiTheme.get_theme()
	add_child(_root)
	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	_panel.offset_left = -470
	_panel.offset_top = 16
	_panel.offset_right = -16
	_panel.offset_bottom = -16
	_panel.visible = false
	_root.add_child(_panel)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_panel.add_child(scroll)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 8)
	scroll.add_child(v)
	v.add_child(UiTheme.label("BENCHMARK / DEBUG", 26, UiTheme.ACCENT, true))

	v.add_child(_section("Teleport"))
	_tp_box = GridContainer.new()
	_tp_box.columns = 2
	_tp_box.add_theme_constant_override("h_separation", 6)
	_tp_box.add_theme_constant_override("v_separation", 6)
	v.add_child(_tp_box)

	v.add_child(_section("Car"))
	var ch := HBoxContainer.new()
	v.add_child(ch)
	_car_pick = OptionButton.new()
	_car_pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ch.add_child(_car_pick)
	ch.add_child(_button("Spawn", func() -> void: Game.main.call("switch_car", _car_pick.selected)))
	var ch2 := HBoxContainer.new()
	v.add_child(ch2)
	ch2.add_child(_button("Repair / flip", func() -> void:
		if Game.player_car:
			Game.player_car.flip_upright()))
	ch2.add_child(_button("Respawn on road", func() -> void: Game.main.call("respawn_on_road")))
	ch2.add_child(_button("Garage", func() -> void:
		close()
		Game.main.call("open_garage")))

	v.add_child(_section("Time of day"))
	var th := HBoxContainer.new()
	v.add_child(th)
	_time_slider = HSlider.new()
	_time_slider.min_value = 0.0
	_time_slider.max_value = 24.0
	_time_slider.step = 0.25
	_time_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_time_slider.value_changed.connect(func(x: float) -> void:
		if not _updating and Game.environment:
			(Game.environment as EnvironmentController).set_time(x))
	th.add_child(_time_slider)
	var freeze := CheckBox.new()
	freeze.text = "Freeze"
	freeze.toggled.connect(func(on: bool) -> void:
		if Game.environment:
			(Game.environment as EnvironmentController).time_frozen = on)
	th.add_child(freeze)
	var tq := HBoxContainer.new()
	v.add_child(tq)
	for p in [["Dawn", 6.3], ["Morning", 9.0], ["Noon", 13.0], ["Sunset", 18.6], ["Night", 22.5]]:
		var hour: float = p[1]
		tq.add_child(_button(p[0], func() -> void:
			if Game.environment:
				(Game.environment as EnvironmentController).set_time(hour)))

	v.add_child(_section("Weather"))
	var wh := HBoxContainer.new()
	v.add_child(wh)
	for w in ["clear", "cloudy", "rain", "fog", "storm"]:
		var wn: String = w
		wh.add_child(_button(w.capitalize(), func() -> void:
			if Game.environment:
				(Game.environment as EnvironmentController).set_weather_by_name(wn)))

	v.add_child(_section("Traffic"))
	var trh := HBoxContainer.new()
	v.add_child(trh)
	var tr_on := CheckBox.new()
	tr_on.text = "Enabled"
	tr_on.button_pressed = true
	tr_on.toggled.connect(func(on: bool) -> void:
		Game.settings["traffic_density"] = _density.value if on else 0.0
		if Game.traffic and Game.traffic.has_method("set_density"):
			Game.traffic.call("set_density", Game.settings["traffic_density"]))
	trh.add_child(tr_on)
	_density = HSlider.new()
	_density.min_value = 0.0
	_density.max_value = 1.0
	_density.step = 0.05
	_density.value = float(Game.settings.get("traffic_density", 0.6))
	_density.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_density.value_changed.connect(func(x: float) -> void:
		Game.settings["traffic_density"] = x
		if Game.traffic and Game.traffic.has_method("set_density"):
			Game.traffic.call("set_density", x))
	trh.add_child(_density)

	v.add_child(_section("Assists"))
	var ag := GridContainer.new()
	ag.columns = 3
	v.add_child(ag)
	for a in [["tcs", "Traction"], ["esc", "Stability"], ["abs", "ABS"], ["steer", "Steer assist"], ["auto_gear", "Auto gears"], ["line", "Braking line"]]:
		var key: String = a[0]
		var cb := CheckBox.new()
		cb.text = a[1]
		cb.button_pressed = bool(Game.assists.get(key, true))
		cb.toggled.connect(func(on: bool) -> void:
			Game.assists[key] = on
			Game.main.call("apply_assists"))
		ag.add_child(cb)
		_assist_boxes[key] = cb

	v.add_child(_section("Display"))
	var dg := GridContainer.new()
	dg.columns = 3
	v.add_child(dg)
	var fps := CheckBox.new()
	fps.text = "FPS / coords"
	fps.toggled.connect(func(on: bool) -> void: Game.settings["show_fps"] = on)
	dg.add_child(fps)
	var mph := CheckBox.new()
	mph.text = "MPH"
	mph.toggled.connect(func(on: bool) -> void: Game.settings["units_mph"] = on)
	dg.add_child(mph)
	var shake := CheckBox.new()
	shake.text = "Cam shake"
	shake.button_pressed = true
	shake.toggled.connect(func(on: bool) -> void: Game.settings["camera_shake"] = on)
	dg.add_child(shake)

	v.add_child(_section("Telemetry"))
	_telemetry = UiTheme.label("", 15, UiTheme.TEXT)
	_telemetry.add_theme_font_override("font", UiTheme.font())
	v.add_child(_telemetry)
	v.add_child(UiTheme.label("F3 to close", 14, UiTheme.TEXT_DIM))


func _section(t: String) -> Label:
	var l := UiTheme.label(t.to_upper(), 16, UiTheme.ACCENT2, true)
	return l


func _button(t: String, fn: Callable) -> Button:
	var b := Button.new()
	b.text = t
	b.add_theme_font_size_override("font_size", 16)
	b.pressed.connect(fn)
	return b


func open() -> void:
	is_open = true
	_panel.visible = true
	_car_pick.clear()
	for d in Game.car_defs:
		_car_pick.add_item(d.display_name)
	_car_pick.selected = Game.current_car_index
	for c in _tp_box.get_children():
		c.queue_free()
	var targets: Array = Game.main.call("teleport_targets")
	for t in targets:
		var name_t: String = t
		_tp_box.add_child(_button(name_t, func() -> void: Game.main.call("teleport", name_t)))
	for key in _assist_boxes:
		(_assist_boxes[key] as CheckBox).set_pressed_no_signal(bool(Game.assists.get(key, true)))


func close() -> void:
	is_open = false
	_panel.visible = false


func _unhandled_input(event: InputEvent) -> void:
	if Game.ui_focus.has("console"):
		return
	if event.is_action_pressed("toggle_debug"):
		if is_open:
			close()
		else:
			open()
		get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if not is_open:
		return
	if Game.environment:
		_updating = true
		_time_slider.value = (Game.environment as EnvironmentController).time_of_day
		_updating = false
	var car := Game.player_car
	if car == null or not is_instance_valid(car):
		return
	var lines: Array[String] = []
	lines.append("%s   %d km/h   gear %s   rpm %d" % [car.definition.display_name, int(car.speed_kmh), str(car.gear), int(car.rpm)])
	lines.append("throttle %.2f  brake %.2f  steer %+.2f (%.1f°)  hb %.1f" % [car.input_throttle, car.input_brake, car.input_steer, car.steer_angle, car.input_handbrake])
	lines.append("body slip %+.1f°   g lat %+.2f  long %+.2f" % [car.body_slip_deg, car.g_force.x, car.g_force.z])
	lines.append("TCS %s  ABS %s  ESC %s  wet %.2f" % ["●" if car.tcs_active else "○", "●" if car.abs_active else "○", "●" if car.esc_active else "○", car.wetness])
	for w in car.wheels:
		lines.append("%s  %-8s load %5d N  slip %4.2f  κ %+.2f  α %+5.1f°  ω %5.1f" % [w.name, Surfaces.get_def(w.surface).display_name if w.contact else "air",
			int(w.load), w.slip, w.slip_ratio, rad_to_deg(w.slip_angle), w.omega])
	lines.append("FPS %d   draw calls %d   objects %d" % [Engine.get_frames_per_second(),
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME)])
	var p := car.global_position
	lines.append("pos %.0f, %.0f, %.0f" % [p.x, p.y, p.z])
	_telemetry.text = "\n".join(lines)
