class_name Menus
extends CanvasLayer
## Developer console (`), garage / car select (F1/Tab) and benchmark/debug menu (F2).

var main: Node
var console := PanelContainer.new()
var con_log := RichTextLabel.new()
var con_input := LineEdit.new()
var garage := PanelContainer.new()
var car_list := ItemList.new()
var stats := RichTextLabel.new()
var upgrade_box := VBoxContainer.new()
var tuning_box := VBoxContainer.new()
var debug := PanelContainer.new()
var history: PackedStringArray = []
var hist_i := 0
var sel := 0

func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_console()
	_build_garage()
	_build_debug()

func _panel_style(alpha: float = 0.9) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.05, 0.09, alpha)
	sb.border_color = Color(1.0, 0.35, 0.6, 0.9)
	sb.border_width_top = 3
	sb.corner_radius_bottom_left = 8; sb.corner_radius_bottom_right = 8
	sb.content_margin_left = 16; sb.content_margin_right = 16; sb.content_margin_top = 12; sb.content_margin_bottom = 12
	return sb

func any_open() -> bool:
	return console.visible or garage.visible or debug.visible

# ------------------------------------------------------------ console
func _build_console() -> void:
	console.add_theme_stylebox_override("panel", _panel_style(0.88))
	Hud._at(console, Control.PRESET_TOP_WIDE, Vector2(0, 0), Vector2(0, 380))
	var v := VBoxContainer.new()
	console.add_child(v)
	var title := Label.new(); title.text = "DEVELOPER CONSOLE — type 'help'"
	title.add_theme_color_override("font_color", Color(1, 0.5, 0.75))
	v.add_child(title)
	con_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	con_log.scroll_following = true
	con_log.bbcode_enabled = true
	con_log.add_theme_font_size_override("normal_font_size", 15)
	v.add_child(con_log)
	con_input.placeholder_text = "command…"
	con_input.text_submitted.connect(_on_submit)
	con_input.gui_input.connect(_on_con_key)
	v.add_child(con_input)
	console.visible = false
	add_child(console)
	log_line("[color=#ff80c0]%s[/color] developer console ready." % Game.TITLE)

func log_line(t: String) -> void:
	con_log.append_text(t + "\n")

func _on_submit(t: String) -> void:
	con_input.clear()
	if t.strip_edges() == "": return
	history.append(t); hist_i = history.size()
	log_line("[color=#80c8ff]> " + t + "[/color]")
	log_line(main.exec(t))

func _on_con_key(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed:
		var k := e as InputEventKey
		if k.keycode == KEY_UP and history.size() > 0:
			hist_i = maxi(hist_i - 1, 0); con_input.text = history[hist_i]; con_input.caret_column = 999
		elif k.keycode == KEY_DOWN and history.size() > 0:
			hist_i = mini(hist_i + 1, history.size() - 1); con_input.text = history[hist_i]; con_input.caret_column = 999
		elif k.physical_keycode == KEY_QUOTELEFT:
			toggle_console(); con_input.accept_event()

func toggle_console() -> void:
	console.visible = not console.visible
	if console.visible:
		con_input.grab_focus()
		await get_tree().process_frame
		con_input.clear()
	else:
		con_input.release_focus()

# ------------------------------------------------------------ garage
func _build_garage() -> void:
	garage.add_theme_stylebox_override("panel", _panel_style(0.93))
	Hud._at(garage, Control.PRESET_CENTER, Vector2(-640, -360), Vector2(1280, 720))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 18)
	garage.add_child(h)
	var left := VBoxContainer.new(); left.custom_minimum_size = Vector2(330, 0)
	h.add_child(left)
	var t := Label.new(); t.text = "GARAGE"; t.add_theme_font_size_override("font_size", 34)
	t.add_theme_color_override("font_color", Color(1, 0.45, 0.7))
	left.add_child(t)
	car_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	car_list.add_theme_font_size_override("font_size", 18)
	for i in Game.cars.size():
		var s := Game.cars[i]
		car_list.add_item("%d. %s   [%s]" % [i + 1, s.display_name, s.class_rating().split(" ")[0]])
	car_list.item_selected.connect(func(i: int) -> void: sel = i; _refresh_garage())
	car_list.item_activated.connect(func(i: int) -> void: main.exec("car %d" % (i + 1)); toggle_garage())
	left.add_child(car_list)
	var drive := Button.new(); drive.text = "DRIVE THIS CAR  (Enter)"
	drive.add_theme_font_size_override("font_size", 20)
	drive.pressed.connect(func() -> void: main.exec("car %d" % (sel + 1)); toggle_garage())
	left.add_child(drive)
	var mid := VBoxContainer.new(); mid.custom_minimum_size = Vector2(430, 0)
	h.add_child(mid)
	stats.bbcode_enabled = true
	stats.fit_content = true
	stats.custom_minimum_size = Vector2(420, 300)
	stats.add_theme_font_size_override("normal_font_size", 17)
	mid.add_child(stats)
	var pl := Label.new(); pl.text = "PAINT"; mid.add_child(pl)
	var pal := HFlowContainer.new()
	var swatches := [Color(0.85, 0.1, 0.08), Color(0.95, 0.6, 0.05), Color(0.95, 0.9, 0.1), Color(0.3, 0.8, 0.2), Color(0.1, 0.55, 0.85), Color(0.12, 0.15, 0.4),
		Color(0.55, 0.2, 0.75), Color(0.95, 0.95, 0.95), Color(0.5, 0.5, 0.52), Color(0.06, 0.06, 0.07), Color(0.55, 0.85, 0.8), Color(1.0, 0.4, 0.6)]
	for c: Color in swatches:
		var b := Button.new()
		b.custom_minimum_size = Vector2(40, 32)
		var sb := StyleBoxFlat.new(); sb.bg_color = c; sb.corner_radius_top_left = 4; sb.corner_radius_bottom_right = 4
		b.add_theme_stylebox_override("normal", sb); b.add_theme_stylebox_override("hover", sb)
		b.pressed.connect(func() -> void: main.exec("paint #" + c.to_html(false)))
		pal.add_child(b)
	mid.add_child(pal)
	var fin := HBoxContainer.new()
	for f in ["gloss", "matte", "metallic"]:
		var b := Button.new(); b.text = f.capitalize()
		b.pressed.connect(func() -> void: main.exec("finish " + f))
		fin.add_child(b)
	mid.add_child(fin)
	var right := VBoxContainer.new(); right.custom_minimum_size = Vector2(380, 0)
	h.add_child(right)
	var ul := Label.new(); ul.text = "UPGRADES"; right.add_child(ul)
	right.add_child(upgrade_box)
	var tl := Label.new(); tl.text = "TUNING"; right.add_child(tl)
	right.add_child(tuning_box)
	garage.visible = false
	add_child(garage)

func toggle_garage() -> void:
	garage.visible = not garage.visible
	if garage.visible:
		sel = Game.cars.find(main.player.spec)
		car_list.select(sel)
		car_list.grab_focus()
		_refresh_garage()

func _bar(v: float) -> String:
	var n := clampi(int(v * 20.0), 0, 20)
	return "[color=#ff70b0]" + "█".repeat(n) + "[/color][color=#333a48]" + "█".repeat(20 - n) + "[/color]"

func _refresh_garage() -> void:
	var s := Game.cars[sel]
	var dt := ["FWD", "RWD", "AWD"][s.drivetrain] as String
	var accel := clampf(s.power_kw / s.mass * 1000.0 / 400.0, 0, 1)
	var txt := "[font_size=28][b]%s[/b][/font_size]\n%s · %s · [color=#ffd060]%s[/color]\n\n" % [s.display_name, s.category, dt, s.class_rating()]
	txt += "Power      %d kW (%d hp)\nWeight     %d kg\nTop speed  %d km/h\nGears      %d\n\n" % [int(s.power_kw), int(s.power_kw * 1.341), int(s.mass), int(s.top_speed_kmh), s.gear_ratios.size()]
	txt += "SPEED     %s\nACCEL     %s\nHANDLING  %s\nOFF-ROAD  %s\nBRAKING   %s\n" % [_bar(s.top_speed_kmh / 350.0), _bar(accel), _bar((s.grip - 0.8) / 0.65), _bar((s.offroad_grip - 0.6) / 0.6), _bar(s.brake_force / s.mass / 12.0)]
	stats.text = txt
	for c in upgrade_box.get_children(): c.queue_free()
	for c in tuning_box.get_children(): c.queue_free()
	var is_current: bool = main.player.spec == s
	if not is_current:
		var l := Label.new(); l.text = "Drive this car to upgrade/tune it."; upgrade_box.add_child(l)
		return
	var car: Car = main.player
	for k in car.upgrades.keys():
		var row := HBoxContainer.new()
		var l := Label.new(); l.text = "%-11s  stage %d/3" % [k.capitalize(), car.upgrades[k]]; l.custom_minimum_size = Vector2(220, 0)
		row.add_child(l)
		for d in [-1, 1]:
			var b := Button.new(); b.text = "−" if d < 0 else "+"; b.custom_minimum_size = Vector2(36, 0)
			b.pressed.connect(func() -> void: main.exec("upgrade %s %d" % [k, clampi(car.upgrades[k] + d, 0, 3)]); _refresh_garage())
			row.add_child(b)
		upgrade_box.add_child(row)
	var tunes := [["final_drive", 0.8, 1.25], ["brake_bias", 0.45, 0.75], ["spring", 0.7, 1.4], ["arb", 0.5, 1.8], ["downforce", 0.5, 1.6], ["tire_pressure", 0.85, 1.15]]
	for tu in tunes:
		var row := HBoxContainer.new()
		var l := Label.new(); l.text = (tu[0] as String).replace("_", " ").capitalize(); l.custom_minimum_size = Vector2(130, 0)
		row.add_child(l)
		var sl := HSlider.new(); sl.min_value = tu[1]; sl.max_value = tu[2]; sl.step = 0.01; sl.value = car.tuning[tu[0]]
		sl.custom_minimum_size = Vector2(170, 0)
		var vl := Label.new(); vl.text = "%.2f" % sl.value
		sl.value_changed.connect(func(v: float) -> void: main.exec("tune %s %.2f" % [tu[0], v]); vl.text = "%.2f" % v)
		row.add_child(sl); row.add_child(vl)
		tuning_box.add_child(row)

# ------------------------------------------------------------ debug menu
func _build_debug() -> void:
	debug.add_theme_stylebox_override("panel", _panel_style(0.9))
	Hud._at(debug, Control.PRESET_CENTER_RIGHT, Vector2(-470, -400), Vector2(450, 800))
	var sc := ScrollContainer.new()
	debug.add_child(sc)
	var v := VBoxContainer.new(); v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(v)
	var t := Label.new(); t.text = "BENCHMARK / DEBUG  (F2)"; t.add_theme_font_size_override("font_size", 22)
	t.add_theme_color_override("font_color", Color(1, 0.5, 0.75))
	v.add_child(t)
	_section(v, "Teleport", ["tp vale", "tp highpine", "tp mesa", "tp coast", "tp loop", "tp highway", "tp switchbacks", "tp harbour", "tp village", "tp lighthouse", "tp castle", "tp windfarm"])
	_section(v, "Spawn car", Game.cars.map(func(s: CarSpec) -> String: return "car " + s.id.split("_")[1]))
	_section(v, "Time", ["time 6.5", "time 9", "time 13", "time 18.6", "time 20.5", "time 0", "timescale 0", "timescale 1", "timescale 30"])
	_section(v, "Weather", ["weather clear", "weather cloudy", "weather rain", "weather fog", "weather storm"])
	_section(v, "Traffic", ["traffic 0", "traffic 0.3", "traffic 0.6", "traffic 1"])
	_section(v, "Assists", ["assist tcs toggle", "assist abs toggle", "assist stm toggle", "assist steer toggle", "assist auto toggle", "assists off", "assists on"])
	_section(v, "Display", ["fps", "telemetry", "units", "hud", "photo"])
	_section(v, "Car", ["repair", "flip", "respawn", "save", "load"])
	debug.visible = false
	add_child(debug)

func _section(v: VBoxContainer, title: String, cmds: Array) -> void:
	var l := Label.new(); l.text = title.to_upper(); l.add_theme_color_override("font_color", Color(0.6, 0.85, 1))
	v.add_child(l)
	var g := HFlowContainer.new()
	for c: String in cmds:
		var b := Button.new(); b.text = c
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(func() -> void: Game.toast(main.exec(c).split("\n")[0]))
		g.add_child(b)
	v.add_child(g)

func toggle_debug() -> void:
	debug.visible = not debug.visible

func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed("console"):
		toggle_console(); get_viewport().set_input_as_handled()
	elif console.visible:
		return
	elif e.is_action_pressed("garage"):
		toggle_garage(); get_viewport().set_input_as_handled()
	elif e.is_action_pressed("debug_menu"):
		toggle_debug(); get_viewport().set_input_as_handled()
	elif garage.visible and e is InputEventKey and (e as InputEventKey).pressed and (e as InputEventKey).keycode == KEY_ESCAPE:
		toggle_garage()
