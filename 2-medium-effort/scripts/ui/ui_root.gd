extends CanvasLayer
## Owns every screen: HUD, console, garage (car select + paint), tuning/upgrades, debug/benchmark menu,
## full map with waypoint, photo mode and pause/settings. Routes the toggle keys.

const ACCENT := Color(1.0, 0.36, 0.62)
const PANEL_BG := Color(0.04, 0.05, 0.09, 0.92)

var main: Node
var hud: Control
var console: PanelContainer
var garage: Control
var debug_menu: Control
var tuning: Control
var map_screen: Control
var pause_menu: Control
var photo_overlay: Control
var _garage_sel: int = 0
var _garage_widgets: Dictionary = {}
var _tuning_widgets: Dictionary = {}
var theme_res: Theme


func _ready() -> void:
	layer = 10
	main = get_parent()
	_make_theme()
	hud = load("res://scripts/ui/hud.gd").new()
	hud.name = "HUD"
	add_child(hud)
	Game.hud = hud
	console = load("res://scripts/ui/console.gd").new()
	console.main = main
	console.theme = theme_res
	add_child(console)
	_build_garage()
	_build_debug()
	_build_tuning()
	map_screen = load("res://scripts/ui/map_screen.gd").new()
	map_screen.visible = false
	add_child(map_screen)
	_build_pause()
	_build_photo()


func _make_theme() -> void:
	theme_res = Theme.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = PANEL_BG
	sb.corner_radius_top_left = 6
	sb.corner_radius_top_right = 6
	sb.corner_radius_bottom_left = 6
	sb.corner_radius_bottom_right = 6
	sb.content_margin_left = 18
	sb.content_margin_right = 18
	sb.content_margin_top = 14
	sb.content_margin_bottom = 14
	theme_res.set_stylebox("panel", "PanelContainer", sb)
	var bn := StyleBoxFlat.new()
	bn.bg_color = Color(0.12, 0.13, 0.18, 0.95)
	bn.corner_radius_top_left = 4
	bn.corner_radius_top_right = 4
	bn.corner_radius_bottom_left = 4
	bn.corner_radius_bottom_right = 4
	bn.content_margin_left = 12
	bn.content_margin_right = 12
	bn.content_margin_top = 6
	bn.content_margin_bottom = 6
	var bh: StyleBoxFlat = bn.duplicate()
	bh.bg_color = Color(0.3, 0.12, 0.22, 0.95)
	bh.border_color = ACCENT
	bh.border_width_left = 4
	var bp: StyleBoxFlat = bh.duplicate()
	bp.bg_color = ACCENT.darkened(0.3)
	theme_res.set_stylebox("normal", "Button", bn)
	theme_res.set_stylebox("hover", "Button", bh)
	theme_res.set_stylebox("pressed", "Button", bp)
	theme_res.set_stylebox("focus", "Button", bh)
	theme_res.set_font_size("font_size", "Button", 18)
	theme_res.set_font_size("font_size", "Label", 18)
	theme_res.set_color("font_color", "Label", Color(0.95, 0.95, 0.97))


func _panel(title: String, anchor_preset: int, min_size: Vector2) -> Array:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.visible = false
	root.theme = theme_res
	add_child(root)
	var pc := PanelContainer.new()
	pc.custom_minimum_size = min_size
	pc.set_anchors_preset(anchor_preset)
	root.add_child(pc)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	pc.add_child(v)
	var t := Label.new()
	t.text = title
	t.add_theme_font_size_override("font_size", 30)
	t.add_theme_color_override("font_color", ACCENT)
	v.add_child(t)
	return [root, pc, v]


func _center(pc: Control) -> void:
	pc.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_KEEP_SIZE)


# ------------------------------------------------------------------ garage
func _build_garage() -> void:
	var r: Array = _panel("GARAGE  -  choose your ride", Control.PRESET_CENTER, Vector2(1280, 720))
	garage = r[0]
	_center(r[1])
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 22)
	h.size_flags_vertical = Control.SIZE_EXPAND_FILL
	r[2].add_child(h)
	var list := VBoxContainer.new()
	list.custom_minimum_size = Vector2(420, 0)
	h.add_child(list)
	for i in Game.cars.size():
		var d: CarDef = Game.cars[i]
		var b := Button.new()
		b.text = "%2d   %s %s     [%s %d]" % [i + 1, d.maker, d.display_name, d.car_class, d.pi]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size = Vector2(0, 52)
		b.pressed.connect(_garage_select.bind(i))
		b.focus_entered.connect(_garage_select.bind(i))
		list.add_child(b)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 6)
	h.add_child(info)
	var nm := Label.new()
	nm.add_theme_font_size_override("font_size", 34)
	info.add_child(nm)
	var sub := Label.new()
	sub.add_theme_color_override("font_color", Color(1, 1, 1, 0.7))
	info.add_child(sub)
	var desc := Label.new()
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.custom_minimum_size = Vector2(700, 50)
	info.add_child(desc)
	var bars: Dictionary = {}
	for st in ["Speed", "Acceleration", "Handling", "Braking", "Off-road"]:
		var row := HBoxContainer.new()
		var l := Label.new()
		l.text = st
		l.custom_minimum_size = Vector2(160, 0)
		row.add_child(l)
		var pb := ProgressBar.new()
		pb.max_value = 10.0
		pb.custom_minimum_size = Vector2(420, 22)
		pb.show_percentage = false
		var fill := StyleBoxFlat.new()
		fill.bg_color = ACCENT
		pb.add_theme_stylebox_override("fill", fill)
		row.add_child(pb)
		var val := Label.new()
		val.custom_minimum_size = Vector2(60, 0)
		row.add_child(val)
		info.add_child(row)
		bars[st] = [pb, val]
	var spec := Label.new()
	spec.add_theme_color_override("font_color", Color(0.85, 0.9, 1.0))
	info.add_child(spec)
	var pl := Label.new()
	pl.text = "PAINT"
	pl.add_theme_color_override("font_color", ACCENT)
	info.add_child(pl)
	var sw := HBoxContainer.new()
	for cname in ["red", "orange", "yellow", "lime", "green", "teal", "blue", "purple", "pink", "white", "silver", "black", "gold"]:
		var cb := Button.new()
		cb.custom_minimum_size = Vector2(40, 34)
		var st2 := StyleBoxFlat.new()
		st2.bg_color = load("res://scripts/ui/console.gd")._parse_color(cname)
		st2.corner_radius_top_left = 4
		st2.corner_radius_bottom_right = 4
		cb.add_theme_stylebox_override("normal", st2)
		cb.tooltip_text = cname
		cb.pressed.connect(func() -> void: console.run("paint %s %s" % [cname, ["gloss", "metallic", "matte"][_garage_widgets.get("finish", 0)]]))
		sw.add_child(cb)
	info.add_child(sw)
	var fin := HBoxContainer.new()
	for fi in 3:
		var fb := Button.new()
		fb.text = ["Gloss", "Metallic", "Matte"][fi]
		fb.pressed.connect(func() -> void:
			_garage_widgets["finish"] = fi
			var car: Car = Game.player as Car
			if car:
				var p: Dictionary = Game.paint_overrides.get(car.def.id, {"color": car.def.paint_color})
				console.run("paint #%s %s" % [(p.color as Color).to_html(false), ["gloss", "metallic", "matte"][fi]]))
		fin.add_child(fb)
	for st3 in ["none", "centre", "side", "roof"]:
		var sb3 := Button.new()
		sb3.text = "Stripe: " + st3
		sb3.pressed.connect(func() -> void: console.run("stripe %s white" % st3))
		fin.add_child(sb3)
	info.add_child(fin)
	var rim := HBoxContainer.new()
	for rc in ["silver", "black", "gold", "white", "red"]:
		var rb := Button.new()
		rb.text = "Rims " + rc
		rb.pressed.connect(func() -> void: console.run("rims " + rc))
		rim.add_child(rb)
	info.add_child(rim)
	var drive := Button.new()
	drive.text = "DRIVE THIS CAR   (Enter)"
	drive.custom_minimum_size = Vector2(0, 60)
	drive.add_theme_font_size_override("font_size", 24)
	drive.pressed.connect(_garage_drive)
	info.add_child(drive)
	var hint := Label.new()
	hint.text = "Up/Down select   Enter drive   Tab / Esc close.  Paint applies to the car you are driving."
	hint.add_theme_color_override("font_color", Color(1, 1, 1, 0.5))
	info.add_child(hint)
	_garage_widgets = {"name": nm, "sub": sub, "desc": desc, "bars": bars, "spec": spec, "list": list, "finish": 0}


func car_stats(d: CarDef) -> Dictionary:
	var kw: float = d.peak_power_kw()
	return {
		"Speed": clampf(d.top_speed_kmh / 35.0, 0.0, 10.0),
		"Acceleration": clampf(kw / d.mass * 25.0, 0.0, 10.0),
		"Handling": clampf((d.grip - 0.85) / 0.4 * 7.0 + d.downforce * 1.2 + (d.lateral_stiffness - 7.0) * 0.3, 0.0, 10.0),
		"Braking": clampf(d.brake_force / d.mass * 0.9 * d.grip, 0.0, 10.0),
		"Off-road": clampf((d.loose_grip - 0.8) * 12.0 + d.rest_length * 6.0, 0.0, 10.0),
	}


func _garage_select(i: int) -> void:
	_garage_sel = i
	var d: CarDef = Game.cars[i]
	_garage_widgets.name.text = d.display_name
	_garage_widgets.sub.text = "%s   %d   ·   Class %s %d   ·   %s" % [d.maker, d.year, d.car_class, d.pi, ["Front-wheel drive", "Rear-wheel drive", "All-wheel drive"][d.drive]]
	_garage_widgets.desc.text = d.description
	var st: Dictionary = car_stats(d)
	for k in st:
		_garage_widgets.bars[k][0].value = st[k]
		_garage_widgets.bars[k][1].text = "%.1f" % st[k]
	_garage_widgets.spec.text = "%.0f kW   %.0f Nm @ %.0f rpm   %.0f kg   %d gears   top %.0f km/h   %d cyl%s" % [d.peak_power_kw(), d.peak_torque, d.peak_torque_rpm, d.mass, d.gears.size(), d.top_speed_kmh, d.cylinders, "  turbo" if d.turbo else ""]


func _garage_drive() -> void:
	main.switch_car(_garage_sel)
	_toggle(garage)


# ------------------------------------------------------------------ debug / benchmark
func _build_debug() -> void:
	var r: Array = _panel("BENCHMARK / DEBUG", Control.PRESET_CENTER_LEFT, Vector2(560, 860))
	debug_menu = r[0]
	(r[1] as Control).set_anchors_and_offsets_preset(Control.PRESET_CENTER_LEFT, Control.PRESET_MODE_KEEP_SIZE, 20)
	var v: VBoxContainer = r[2]
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(540, 780)
	v.add_child(sc)
	var g := VBoxContainer.new()
	g.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(g)
	_section(g, "Teleport: regions & long roads")
	_grid(g, ["farmland", "village", "mountains", "summit", "desert", "canyon", "coast", "harbour", "lighthouse", "castle", "lake", "windfarm", "expressway", "highway", "bridge", "gasstation"], func(x: String) -> void: console.run("tp " + x), 4)
	_section(g, "Spawn car")
	var names: Array = []
	for i in Game.cars.size():
		names.append(str(i + 1))
	_grid(g, names, func(x: String) -> void: console.run("car " + x), 10)
	_section(g, "Time of day")
	_grid(g, ["5.5", "7", "10", "13", "17.5", "19.5", "22", "freeze on", "freeze off"], func(x: String) -> void:
		if x.begins_with("freeze"):
			console.run(x)
		else:
			console.run("time " + x), 5)
	_section(g, "Weather")
	_grid(g, ["clear", "cloudy", "rain", "fog", "storm", "snow", "auto"], func(x: String) -> void: console.run("weather " + x), 4)
	_section(g, "Traffic density")
	_grid(g, ["0", "0.25", "0.5", "0.75", "1"], func(x: String) -> void: console.run("traffic " + x), 5)
	_section(g, "Assists")
	_grid(g, ["tcs on", "tcs off", "esc on", "esc off", "abs on", "abs off", "steer on", "steer off", "all on", "all off"], func(x: String) -> void: console.run("assist " + x), 4)
	_section(g, "Car")
	_grid(g, ["repair", "flip", "reset", "telemetry", "fps", "speed", "gears manual", "gears auto"], func(x: String) -> void: console.run(x), 4)
	_section(g, "Events")
	_grid(g, ["race 1", "race 2", "race 3", "race 4", "events"], func(x: String) -> void: console.out(console.run(x)), 5)


func _section(g: Control, t: String) -> void:
	var l := Label.new()
	l.text = t
	l.add_theme_color_override("font_color", ACCENT)
	g.add_child(l)


func _grid(g: Control, items: Array, cb: Callable, cols: int) -> void:
	var gc := GridContainer.new()
	gc.columns = cols
	for it in items:
		var b := Button.new()
		b.text = str(it)
		b.custom_minimum_size = Vector2(500.0 / cols, 34)
		b.pressed.connect(cb.bind(str(it)))
		gc.add_child(b)
	g.add_child(gc)


# ------------------------------------------------------------------ tuning / upgrades
func _build_tuning() -> void:
	var r: Array = _panel("TUNING & UPGRADES", Control.PRESET_CENTER_RIGHT, Vector2(620, 860))
	tuning = r[0]
	(r[1] as Control).set_anchors_and_offsets_preset(Control.PRESET_CENTER_RIGHT, Control.PRESET_MODE_KEEP_SIZE, 20)
	var v: VBoxContainer = r[2]
	var stats := Label.new()
	stats.add_theme_color_override("font_color", Color(0.85, 0.95, 1.0))
	v.add_child(stats)
	_tuning_widgets["stats"] = stats
	_section(v, "Upgrades (level 0-3)")
	for part in ["engine", "tires", "suspension", "brakes", "weight", "aero"]:
		var row := HBoxContainer.new()
		var l := Label.new()
		l.text = part.capitalize()
		l.custom_minimum_size = Vector2(150, 0)
		row.add_child(l)
		for lvl in 4:
			var b := Button.new()
			b.text = ["Stock", "Street", "Sport", "Race"][lvl]
			b.pressed.connect(func() -> void:
				console.run("upgrade %s %d" % [part, lvl])
				_refresh_tuning())
			row.add_child(b)
		v.add_child(row)
	_section(v, "Tuning")
	for t in [["final_drive", "Gearing (final drive)", 0.8, 1.25], ["tire_pressure", "Tyre pressure", -1.0, 1.0], ["camber", "Camber", -2.0, 0.0],
			["spring", "Springs", 0.7, 1.4], ["damper", "Dampers", 0.7, 1.4], ["arb", "Anti-roll bars", 0.5, 1.6], ["aero", "Aero / downforce", 0.6, 1.6], ["brake_bias", "Brake bias (front +)", -0.12, 0.12]]:
		var row := HBoxContainer.new()
		var l := Label.new()
		l.text = t[1]
		l.custom_minimum_size = Vector2(230, 0)
		row.add_child(l)
		var s := HSlider.new()
		s.min_value = t[2]
		s.max_value = t[3]
		s.step = 0.01
		s.custom_minimum_size = Vector2(260, 30)
		var val := Label.new()
		val.custom_minimum_size = Vector2(70, 0)
		s.value_changed.connect(func(x: float) -> void:
			var car: Car = Game.player as Car
			if car:
				Game.get_tuning(car.def.id)[t[0]] = x
				car.apply_mods()
			val.text = "%.2f" % x
			_refresh_tuning())
		row.add_child(s)
		row.add_child(val)
		v.add_child(row)
		_tuning_widgets[t[0]] = s
	var reset := Button.new()
	reset.text = "Reset tuning to defaults"
	reset.pressed.connect(func() -> void:
		var car: Car = Game.player as Car
		if car:
			Game.tuning.erase(car.def.id)
			car.apply_mods()
			_sync_tuning_sliders())
	v.add_child(reset)


func _sync_tuning_sliders() -> void:
	var car: Car = Game.player as Car
	if car == null:
		return
	var tu: Dictionary = Game.get_tuning(car.def.id)
	for k in tu:
		if _tuning_widgets.has(k):
			(_tuning_widgets[k] as HSlider).set_value_no_signal(tu[k])
	_refresh_tuning()


func _refresh_tuning() -> void:
	var car: Car = Game.player as Car
	if car == null:
		return
	var up: Dictionary = Game.get_upgrades(car.def.id)
	var base: Dictionary = car_stats(car.def)
	var power: float = car.def.peak_power_kw() * car.mods.power
	var txt: String = "%s %s\n" % [car.def.maker, car.def.display_name]
	txt += "Power %.0f kW (stock %.0f)   Mass %.0f kg   Grip x%.2f   Brakes x%.2f   Aero x%.2f\n" % [power, car.def.peak_power_kw(), car.mass, car.mods.grip, car.mods.brake, car.mods.aero]
	var acc: float = clampf(power / car.mass * 25.0, 0.0, 10.0)
	txt += "Acceleration %.1f -> %.1f   Handling %.1f -> %.1f   Braking %.1f -> %.1f" % [base.Acceleration, acc, base.Handling, clampf(base.Handling * car.mods.grip + (car.mods.aero - 1.0) * 0.6, 0.0, 10.0), base.Braking, clampf(base.Braking * car.mods.brake, 0.0, 10.0)]
	txt += "\nUpgrades: " + ", ".join(up.keys().map(func(k): return "%s %d" % [k, up[k]]))
	_tuning_widgets.stats.text = txt


# ------------------------------------------------------------------ pause / photo
func _build_pause() -> void:
	var r: Array = _panel("PAUSED", Control.PRESET_CENTER, Vector2(520, 520))
	pause_menu = r[0]
	_center(r[1])
	var v: VBoxContainer = r[2]
	for item in [["Resume", func() -> void: _toggle(pause_menu)], ["Garage", func() -> void:
			_toggle(pause_menu)
			_toggle(garage)], ["Save game", func() -> void: console.out(console.run("save"))],
			["Toggle km/h / mph", func() -> void: console.run("speed")], ["Toggle manual gears", func() -> void: console.run("gears " + ("auto" if Game.settings.manual_gears else "manual"))],
			["Quit to desktop", func() -> void:
				console.run("save")
				get_tree().quit()]]:
		var b := Button.new()
		b.text = item[0]
		b.custom_minimum_size = Vector2(0, 52)
		b.pressed.connect(item[1])
		v.add_child(b)
	var vol := HSlider.new()
	vol.min_value = 0.0
	vol.max_value = 1.0
	vol.step = 0.05
	vol.value = Game.settings.master_volume
	vol.value_changed.connect(func(x: float) -> void:
		Game.settings.master_volume = x
		AudioServer.set_bus_volume_db(0, linear_to_db(maxf(x, 0.001))))
	var vl := Label.new()
	vl.text = "Master volume"
	v.add_child(vl)
	v.add_child(vol)


func _build_photo() -> void:
	photo_overlay = Control.new()
	photo_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	photo_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	photo_overlay.visible = false
	add_child(photo_overlay)
	var l := Label.new()
	l.text = "PHOTO MODE   WASD/QE move (Shift fast) · mouse look · [ ] FOV · 1/2 focus · 3 DOF on/off · T time +1h · Y weather · H hide hints · F12 save photo · P exit"
	l.position = Vector2(20, 20)
	l.add_theme_font_size_override("font_size", 18)
	l.add_theme_color_override("font_color", Color(1, 1, 1, 0.85))
	l.name = "Hint"
	photo_overlay.add_child(l)


func _any_menu_open() -> bool:
	return garage.visible or debug_menu.visible or tuning.visible or map_screen.visible or pause_menu.visible or console.visible


func _toggle(c: Control) -> void:
	var opening: bool = not c.visible
	for other in [garage, debug_menu, tuning, map_screen, pause_menu]:
		if other != c:
			other.visible = false
	c.visible = opening
	if c == garage and opening:
		_garage_select(Game.current_car_index)
		var btn: Button = (_garage_widgets.list as VBoxContainer).get_child(Game.current_car_index)
		btn.grab_focus()
	if c == tuning and opening:
		_sync_tuning_sliders()
	_update_input_lock()


func _update_input_lock() -> void:
	var lock: bool = _any_menu_open()
	main.player_input.enabled = not lock and not main.camera.photo_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var car: Car = Game.player as Car
	if lock and car:
		car.in_throttle = 0.0
		car.in_brake = 0.0
		car.in_steer = 0.0
		car.in_handbrake = true


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_console"):
		console.toggle()
		_update_input_lock()
		get_viewport().set_input_as_handled()
		return
	if console.visible:
		return
	if main.camera.photo_mode:
		_photo_input(event)
		return
	if event.is_action_pressed("garage"):
		_toggle(garage)
	elif event.is_action_pressed("debug_menu"):
		_toggle(debug_menu)
	elif event.is_action_pressed("tuning"):
		_toggle(tuning)
	elif event.is_action_pressed("map"):
		_toggle(map_screen)
	elif event.is_action_pressed("photo_mode") and not _any_menu_open():
		_enter_photo()
	elif event.is_action_pressed("pause"):
		if _any_menu_open():
			for c in [garage, debug_menu, tuning, map_screen, pause_menu]:
				c.visible = false
			_update_input_lock()
		else:
			_toggle(pause_menu)
	elif event.is_action_pressed("screenshot"):
		_screenshot()
	elif garage.visible and event is InputEventKey and event.pressed and (event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER):
		_garage_drive()


var _photo_prev_scale: float = 1.0
var _dof: bool = false


func _enter_photo() -> void:
	main.camera.enter_photo()
	hud.visible = false
	photo_overlay.visible = true
	_photo_prev_scale = Engine.time_scale
	Engine.time_scale = 0.0
	Game.sky.time_frozen = true
	_update_input_lock()


func _exit_photo() -> void:
	main.camera.exit_photo()
	hud.visible = true
	photo_overlay.visible = false
	Engine.time_scale = _photo_prev_scale
	Game.sky.time_frozen = false
	var attrs: CameraAttributesPractical = main.camera.attributes
	if attrs:
		attrs.dof_blur_far_enabled = false
		attrs.dof_blur_near_enabled = false
	_update_input_lock()


func _photo_input(event: InputEvent) -> void:
	if event.is_action_pressed("photo_mode") or event.is_action_pressed("pause"):
		_exit_photo()
		return
	if not (event is InputEventKey and event.pressed):
		if event.is_action_pressed("screenshot"):
			_screenshot()
		return
	var cam: Camera3D = main.camera
	if cam.attributes == null:
		cam.attributes = CameraAttributesPractical.new()
	var attrs: CameraAttributesPractical = cam.attributes
	match event.keycode:
		KEY_BRACKETLEFT: cam.fov = clampf(cam.fov - 5.0, 15.0, 110.0)
		KEY_BRACKETRIGHT: cam.fov = clampf(cam.fov + 5.0, 15.0, 110.0)
		KEY_3:
			_dof = not _dof
			attrs.dof_blur_far_enabled = _dof
			attrs.dof_blur_near_enabled = _dof
			attrs.dof_blur_far_distance = 25.0
			attrs.dof_blur_near_distance = 2.0
			attrs.dof_blur_amount = 0.12
		KEY_1: attrs.dof_blur_far_distance = maxf(2.0, attrs.dof_blur_far_distance * 0.8)
		KEY_2: attrs.dof_blur_far_distance = attrs.dof_blur_far_distance * 1.25
		KEY_T: Game.sky.set_hour(Game.sky.hour + 1.0)
		KEY_Y:
			var i: int = SkyWeather.STATES.find(Game.sky.weather)
			Game.sky.set_weather(SkyWeather.STATES[(i + 1) % SkyWeather.STATES.size()], true)
		KEY_H: photo_overlay.get_node("Hint").visible = not photo_overlay.get_node("Hint").visible
		KEY_F12: _screenshot()


func _screenshot() -> void:
	DirAccess.make_dir_recursive_absolute("user://photos")
	var hint_vis: bool = photo_overlay.visible
	photo_overlay.visible = false
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	var path: String = "user://photos/photo_%s.png" % Time.get_datetime_string_from_system().replace(":", "-")
	img.save_png(path)
	photo_overlay.visible = hint_vis
	Game.toast("Photo saved", ProjectSettings.globalize_path(path), Color(0.4, 0.8, 1.0))
