extends Control
## Benchmark / debug menu (F2): teleports, car spawning, time, weather, traffic, assists,
## overlays, repair and photo mode — everything needed for a demo recording.

var main: Node
var panel: PanelContainer
var open := false
var time_slider: HSlider
var time_label: Label
var traffic_slider: HSlider
var traffic_label: Label
var car_pick: OptionButton


func init_ui(m: Node) -> void:
	main = m
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel = PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UIStyle.panel(Color(0.03, 0.04, 0.07, 0.88), 14))
	panel.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	panel.anchor_left = 1.0
	panel.offset_left = -620
	panel.offset_right = -24
	panel.offset_top = 24
	panel.offset_bottom = -24
	add_child(panel)
	var scroll := ScrollContainer.new()
	panel.add_child(scroll)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 8)
	scroll.add_child(v)
	v.add_child(UIStyle.label("BENCHMARK / DEBUG", 26, UIStyle.ACCENT, true))
	v.add_child(UIStyle.label("F2 to close. Everything here is also a console command.", 14, UIStyle.TEXT_DIM))
	# teleports
	v.add_child(_section("Teleport"))
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	v.add_child(grid)
	for t in ["valley", "highlands", "mesa", "coast", "loop", "highway", "bay bridge", "hairpins", "tunnel",
			"desert speedway", "dunes", "gravel forest", "velora festival", "meadowmere", "saltcliff harbour", "saltcliff light",
			"ravenhold ruins", "brightmoor wind farm"]:
		var b := UIStyle.button(t.capitalize(), 15)
		b.custom_minimum_size = Vector2(180, 0)
		var tt: String = t
		b.pressed.connect(func() -> void: _cmd("tp " + tt))
		grid.add_child(b)
	# car
	v.add_child(_section("Car"))
	var ch := HBoxContainer.new()
	v.add_child(ch)
	car_pick = OptionButton.new()
	car_pick.add_theme_font_size_override("font_size", 16)
	for c in Game.cars:
		car_pick.add_item(c.display_name)
	ch.add_child(car_pick)
	var spawn := UIStyle.button("Spawn", 16)
	spawn.pressed.connect(func() -> void: _cmd("car %d" % (car_pick.selected + 1)))
	ch.add_child(spawn)
	var rep := UIStyle.button("Repair / flip", 16)
	rep.pressed.connect(func() -> void: _cmd("repair"))
	ch.add_child(rep)
	var rs := UIStyle.button("Reset to road", 16)
	rs.pressed.connect(func() -> void: _cmd("respawn"))
	ch.add_child(rs)
	# time
	v.add_child(_section("Time of day"))
	var th := HBoxContainer.new()
	v.add_child(th)
	time_slider = HSlider.new()
	time_slider.min_value = 0.0
	time_slider.max_value = 24.0
	time_slider.step = 0.25
	time_slider.custom_minimum_size = Vector2(380, 24)
	time_slider.value_changed.connect(func(val: float) -> void: main.world.sky.set_time(val))
	th.add_child(time_slider)
	time_label = UIStyle.label("", 16, UIStyle.TEXT)
	th.add_child(time_label)
	var tb := HBoxContainer.new()
	v.add_child(tb)
	for p in [["Sunrise", 6.6], ["Morning", 9.0], ["Noon", 13.0], ["Golden", 18.4], ["Sunset", 19.3], ["Night", 23.0]]:
		var b := UIStyle.button(p[0], 15)
		var hv: float = p[1]
		b.pressed.connect(func() -> void: main.world.sky.set_time(hv))
		tb.add_child(b)
	var freeze := CheckButton.new()
	freeze.text = "Freeze time"
	freeze.add_theme_font_size_override("font_size", 16)
	freeze.toggled.connect(func(on: bool) -> void: main.world.sky.time_frozen = on)
	v.add_child(freeze)
	# weather
	v.add_child(_section("Weather"))
	var wb := HBoxContainer.new()
	v.add_child(wb)
	for w in ["clear", "cloudy", "rain", "fog", "storm"]:
		var b := UIStyle.button(w.capitalize(), 15)
		var ww: String = w
		b.pressed.connect(func() -> void: _cmd("weather " + ww))
		wb.add_child(b)
	var auto_w := UIStyle.button("Auto cycle", 15)
	auto_w.pressed.connect(func() -> void: _cmd("weather auto"))
	wb.add_child(auto_w)
	# traffic
	v.add_child(_section("Traffic"))
	var trh := HBoxContainer.new()
	v.add_child(trh)
	traffic_slider = HSlider.new()
	traffic_slider.min_value = 0.0
	traffic_slider.max_value = 1.0
	traffic_slider.step = 0.05
	traffic_slider.custom_minimum_size = Vector2(380, 24)
	traffic_slider.value = Game.settings.traffic_density
	traffic_slider.value_changed.connect(func(val: float) -> void: Game.settings.traffic_density = val)
	trh.add_child(traffic_slider)
	traffic_label = UIStyle.label("", 16, UIStyle.TEXT)
	trh.add_child(traffic_label)
	# assists
	v.add_child(_section("Assists"))
	var ag := GridContainer.new()
	ag.columns = 3
	v.add_child(ag)
	for a in [["tcs", "Traction control"], ["stm", "Stability control"], ["abs", "ABS"], ["steer", "Steering assist"],
			["auto", "Automatic gears"]]:
		var cb := CheckButton.new()
		cb.text = a[1]
		cb.add_theme_font_size_override("font_size", 15)
		cb.button_pressed = Game.assists[a[0]]
		var key: String = a[0]
		cb.toggled.connect(func(on: bool) -> void: Game.set_assist(key, on))
		ag.add_child(cb)
	# overlays
	v.add_child(_section("Overlays"))
	var og := HBoxContainer.new()
	v.add_child(og)
	for o in [["fps", "FPS + coords"], ["telemetry", "Telemetry"]]:
		var cb := CheckButton.new()
		cb.text = o[1]
		cb.add_theme_font_size_override("font_size", 15)
		var key: String = o[0]
		cb.button_pressed = Game.settings.get("show_fps" if key == "fps" else key, false)
		cb.toggled.connect(func(on: bool) -> void:
			if key == "fps":
				Game.settings.show_fps = on
			else:
				Game.settings[key] = on)
		og.add_child(cb)
	var photo := UIStyle.button("Photo mode (P)", 16)
	photo.pressed.connect(func() -> void:
		toggle()
		_cmd("photo"))
	v.add_child(photo)
	var units := UIStyle.button("Toggle km/h / mph", 16)
	units.pressed.connect(func() -> void: _cmd("units " + ("kmh" if Game.settings.units_mph else "mph")))
	v.add_child(units)
	visible = false


func _section(t: String) -> Label:
	var l := UIStyle.label(t.to_upper(), 17, UIStyle.ACCENT2)
	return l


func _cmd(line: String) -> void:
	var console := get_parent().get_node_or_null("Console")
	for n in get_parent().get_children():
		if n.has_method("execute"):
			var out: String = n.execute(line)
			Game.toast("Debug", out.replace("[b]", "").replace("[/b]", ""), "info")
			return


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("debug_menu"):
		toggle()
		get_viewport().set_input_as_handled()


func toggle() -> void:
	open = not open
	visible = open
	if open:
		car_pick.selected = Game.current_car_index
		traffic_slider.value = Game.settings.traffic_density


func _process(_delta: float) -> void:
	if not open:
		return
	time_label.text = " %05.2f h" % Game.time_of_day
	if not time_slider.has_focus():
		time_slider.set_value_no_signal(Game.time_of_day)
	traffic_label.text = " %d%%" % roundi(Game.settings.traffic_density * 100.0)
