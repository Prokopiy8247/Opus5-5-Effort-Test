extends PanelContainer
## Benchmark / debug menu (F2): teleports, car spawn, time, weather, traffic, assists,
## readouts, repair and the benchmark drive. Testing tool only.

var _assist_buttons := {}


func _ready() -> void:
	UITheme.place(self, 1.0, 0.0, -760, 24, 736, 980)
	anchor_bottom = 1.0
	offset_bottom = -24
	visible = false
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_theme_constant_override("separation", 6)
	scroll.add_child(vb)
	vb.add_child(UITheme.label("BENCHMARK / DEBUG", 30, UITheme.CYAN, true))
	_section(vb, "Teleport — regions")
	_row(vb, [["Verdana Valley", _tp.bind("valley")], ["Pinecrest Highlands", _tp.bind("highlands")],
		["Redmesa Canyons", _tp.bind("canyons")], ["Marisol Coast", _tp.bind("coast")]])
	_section(vb, "Teleport — places and long roads")
	_row(vb, [["Festival", _tp.bind("hub")], ["Village", _tp.bind("village")], ["Harbour", _tp.bind("harbour")], ["Lighthouse", _tp.bind("lighthouse")]])
	_row(vb, [["Summit", _tp.bind("summit")], ["Pass", _tp.bind("pass")], ["Canyon view", _tp.bind("canyon_view")], ["Tunnel", _tp.bind("tunnel")]])
	_row(vb, [["Expressway start", _tp.bind("road:highway:0.03")], ["Coast road", _tp.bind("road:loop:0.05")],
		["Hairpins", _tp.bind("road:loop:0.28")], ["Desert run", _tp.bind("road:loop:0.5")]])
	_section(vb, "Spawn car")
	var cars := []
	for i in Game.cars.size():
		cars.append([Game.cars[i].display_name, func() -> void: Game.main.switch_car(i)])
	for k in range(0, cars.size(), 3):
		_row(vb, cars.slice(k, k + 3))
	_section(vb, "Time of day")
	_row(vb, [["Sunrise 06:30", _time.bind(6.5)], ["Morning 09:00", _time.bind(9.0)], ["Noon 12:30", _time.bind(12.5)],
		["Sunset 18:40", _time.bind(18.66)], ["Night 22:30", _time.bind(22.5)]])
	_row(vb, [["Freeze time", func() -> void: Game.sky.time_speed = 0.0], ["1 h / min", func() -> void: Game.sky.time_speed = 1.0 / 60.0],
		["1 h / 6 s", func() -> void: Game.sky.time_speed = 1.0 / 6.0]])
	_section(vb, "Weather")
	_row(vb, [["Clear", _weather.bind("clear")], ["Cloudy", _weather.bind("cloudy")], ["Rain", _weather.bind("rain")],
		["Fog", _weather.bind("fog")], ["Storm", _weather.bind("storm")], ["Auto", _weather.bind("auto")]])
	_section(vb, "Traffic density")
	_row(vb, [["Off", _traffic.bind(0.0)], ["Light", _traffic.bind(0.4)], ["Normal", _traffic.bind(1.0)], ["Heavy", _traffic.bind(1.5)]])
	_section(vb, "Assists")
	var arow := []
	for a: String in ["abs", "tcs", "stm", "steer", "auto_gear"]:
		arow.append([a.to_upper(), _assist.bind(a)])
	var hb := _row(vb, arow)
	for i in hb.get_child_count():
		_assist_buttons[["abs", "tcs", "stm", "steer", "auto_gear"][i]] = hb.get_child(i)
	_section(vb, "Display")
	_row(vb, [["FPS", func() -> void: Game.settings.show_fps = not Game.settings.show_fps],
		["Coords", func() -> void: Game.settings.show_coords = not bool(Game.settings.get("show_coords", false))],
		["km/h · mph", func() -> void: Game.settings.units_kmh = not Game.settings.units_kmh],
		["Telemetry", func() -> void: Game.settings.show_telemetry = not Game.settings.show_telemetry]])
	_section(vb, "Car and benchmark")
	_row(vb, [["Flip / repair", func() -> void: Game.player.flip_upright()], ["Back to road", func() -> void: Game.reset_player_to_road()],
		["Benchmark 60 s", func() -> void:
			toggle()
			Game.main.start_benchmark(60.0)], ["Save", func() -> void: SaveSystem.save_game()]])


func _section(vb: VBoxContainer, t: String) -> void:
	vb.add_child(UITheme.label(t, 18, UITheme.SUN, true))


func _row(vb: VBoxContainer, items: Array) -> HBoxContainer:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 6)
	for it: Array in items:
		var b := Button.new()
		b.text = it[0]
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(it[1])
		hb.add_child(b)
	vb.add_child(hb)
	return hb


func toggle() -> void:
	visible = not visible
	Game.set_ui_focus("debug", visible)
	_refresh_assists()


func _refresh_assists() -> void:
	for a: String in _assist_buttons:
		var b := _assist_buttons[a] as Button
		b.text = "%s %s" % [a.to_upper(), "ON" if Game.assist(a) else "OFF"]


func _tp(where: String) -> void:
	var p: Vector3 = Game.main.find_place(where)
	if p != Vector3.INF:
		Game.main.teleport_to(p)


func _time(h: float) -> void:
	Game.sky.set_time(h)


func _weather(w: String) -> void:
	if w == "auto":
		Game.sky.auto_weather = true
	else:
		Game.sky.auto_weather = false
		Game.sky.set_weather(w)


func _traffic(d: float) -> void:
	Game.settings.traffic_density = d
	Game.notify("Traffic", "density %.1f" % d, "small")


func _assist(a: String) -> void:
	Game.set_assist(a, not Game.assist(a))
	_refresh_assists()
