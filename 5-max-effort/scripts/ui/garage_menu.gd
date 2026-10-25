class_name GarageMenu
extends CanvasLayer
## Graphical garage (F1 / Tab): the 10-car roster with class/PI badges, specs, stat bars,
## paint & finish, upgrades with before/after stats, and tuning sliders. Selecting a car swaps
## the player's car in place (orbit camera preview); "Drive" closes the menu.

const SWATCHES := [Color(0.85, 0.1, 0.08), Color(0.95, 0.45, 0.05), Color(0.95, 0.8, 0.1), Color(0.55, 0.85, 0.15),
	Color(0.1, 0.55, 0.18), Color(0.05, 0.55, 0.55), Color(0.1, 0.75, 0.9), Color(0.08, 0.25, 0.8), Color(0.4, 0.1, 0.6),
	Color(0.95, 0.35, 0.6), Color(0.92, 0.92, 0.92), Color(0.65, 0.67, 0.7), Color(0.3, 0.31, 0.33), Color(0.03, 0.03, 0.035),
	Color(0.35, 0.2, 0.1), Color(0.8, 0.62, 0.2)]
const STAT_NAMES := ["speed", "acceleration", "handling", "braking", "offroad"]

var is_open: bool = false
var _root: Control
var _list: VBoxContainer
var _title: Label
var _subtitle: Label
var _desc: Label
var _specs: GridContainer
var _bars: Dictionary = {}
var _pi_label: Label
var _tabs: TabContainer
var _upgrade_rows: Dictionary = {}
var _tune_sliders: Dictionary = {}
var _selected: int = 0
var _building: bool = false


func _ready() -> void:
	layer = 40
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.theme = UiTheme.get_theme()
	_root.visible = false
	add_child(_root)
	var shade := ColorRect.new()
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0, 0, 0, 0.0)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(shade)

	# left: roster
	var left := PanelContainer.new()
	left.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	left.offset_left = 24
	left.offset_top = 24
	left.offset_right = 430
	left.offset_bottom = -24
	_root.add_child(left)
	var lv := VBoxContainer.new()
	lv.add_theme_constant_override("separation", 6)
	left.add_child(lv)
	lv.add_child(UiTheme.label("GARAGE", 34, UiTheme.ACCENT, true))
	lv.add_child(UiTheme.label("10 festival cars · click to preview", 16, UiTheme.TEXT_DIM))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	lv.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 6)
	scroll.add_child(_list)
	var drive := Button.new()
	drive.text = "DRIVE  ▶"
	drive.add_theme_font_size_override("font_size", 24)
	drive.custom_minimum_size = Vector2(0, 54)
	drive.pressed.connect(close)
	lv.add_child(drive)

	# right: details
	var right := PanelContainer.new()
	right.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	right.offset_left = -640
	right.offset_top = 24
	right.offset_right = -24
	right.offset_bottom = -24
	_root.add_child(right)
	var rv := VBoxContainer.new()
	rv.add_theme_constant_override("separation", 8)
	right.add_child(rv)
	var head := HBoxContainer.new()
	rv.add_child(head)
	var hv := VBoxContainer.new()
	hv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(hv)
	_title = UiTheme.label("", 34, UiTheme.TEXT, true)
	hv.add_child(_title)
	_subtitle = UiTheme.label("", 18, UiTheme.TEXT_DIM)
	hv.add_child(_subtitle)
	_pi_label = UiTheme.label("", 30, UiTheme.TEXT, true)
	_pi_label.custom_minimum_size = Vector2(120, 0)
	_pi_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.add_child(_pi_label)
	_desc = UiTheme.label("", 17, UiTheme.TEXT)
	_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rv.add_child(_desc)

	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rv.add_child(_tabs)
	_build_overview_tab()
	_build_paint_tab()
	_build_upgrade_tab()
	_build_tuning_tab()
	rv.add_child(UiTheme.label("F1 / Tab / Esc to close   ·   changes apply instantly", 15, UiTheme.TEXT_DIM))


func _build_overview_tab() -> void:
	var v := VBoxContainer.new()
	v.name = "Overview"
	v.add_theme_constant_override("separation", 10)
	_tabs.add_child(v)
	_specs = GridContainer.new()
	_specs.columns = 4
	_specs.add_theme_constant_override("h_separation", 18)
	_specs.add_theme_constant_override("v_separation", 6)
	v.add_child(_specs)
	for s in STAT_NAMES:
		var row := HBoxContainer.new()
		var l := UiTheme.label(s.capitalize(), 18, UiTheme.TEXT_DIM)
		l.custom_minimum_size = Vector2(150, 0)
		row.add_child(l)
		var bar := ProgressBar.new()
		bar.min_value = 0
		bar.max_value = 10
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(300, 18)
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var fill := UiTheme.panel_style(UiTheme.ACCENT, 3)
		fill.content_margin_top = 0
		fill.content_margin_bottom = 0
		bar.add_theme_stylebox_override("fill", fill)
		var bg := UiTheme.panel_style(Color(1, 1, 1, 0.08), 3)
		bg.content_margin_top = 0
		bg.content_margin_bottom = 0
		bar.add_theme_stylebox_override("background", bg)
		row.add_child(bar)
		var val := UiTheme.label("", 18, UiTheme.TEXT, true)
		val.custom_minimum_size = Vector2(60, 0)
		val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(val)
		v.add_child(row)
		_bars[s] = [bar, val]


func _build_paint_tab() -> void:
	var v := VBoxContainer.new()
	v.name = "Paint"
	v.add_theme_constant_override("separation", 12)
	_tabs.add_child(v)
	v.add_child(UiTheme.label("Colour", 18, UiTheme.TEXT_DIM))
	var grid := GridContainer.new()
	grid.columns = 8
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	v.add_child(grid)
	for c in SWATCHES:
		var b := Button.new()
		b.custom_minimum_size = Vector2(54, 40)
		var sb := UiTheme.panel_style(c, 6, Color(1, 1, 1, 0.3))
		b.add_theme_stylebox_override("normal", sb)
		b.add_theme_stylebox_override("hover", UiTheme.panel_style(c.lightened(0.15), 6, UiTheme.ACCENT))
		b.add_theme_stylebox_override("pressed", UiTheme.panel_style(c, 6, Color(1, 1, 1)))
		b.pressed.connect(func() -> void: Game.main.call("set_paint", c, Game.paint_finish))
		grid.add_child(b)
	v.add_child(UiTheme.label("Finish", 18, UiTheme.TEXT_DIM))
	var fh := HBoxContainer.new()
	fh.add_theme_constant_override("separation", 8)
	v.add_child(fh)
	for i in 4:
		var b := Button.new()
		b.text = ["Gloss", "Metallic", "Matte", "Pearl"][i]
		b.custom_minimum_size = Vector2(120, 42)
		var idx := i
		b.pressed.connect(func() -> void: Game.main.call("set_paint", Game.paint_color, idx))
		fh.add_child(b)
	v.add_child(UiTheme.label("Rims", 18, UiTheme.TEXT_DIM))
	var rh := HBoxContainer.new()
	rh.add_theme_constant_override("separation", 8)
	v.add_child(rh)
	for r in [["Silver", "rim"], ["Dark", "rim_dark"], ["Gold", "rim_gold"], ["Chrome", "chrome"]]:
		var b := Button.new()
		b.text = r[0]
		b.custom_minimum_size = Vector2(120, 42)
		var key: String = r[1]
		b.pressed.connect(func() -> void: Game.main.call("set_rim_style", key))
		rh.add_child(b)
	var stripes := CheckButton.new()
	stripes.text = "Racing stripes"
	stripes.toggled.connect(func(on: bool) -> void: Game.main.call("set_stripes", on))
	v.add_child(stripes)


func _build_upgrade_tab() -> void:
	var v := VBoxContainer.new()
	v.name = "Upgrades"
	v.add_theme_constant_override("separation", 10)
	_tabs.add_child(v)
	for part in CarTuning.PARTS:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var l := UiTheme.label(part.capitalize(), 19, UiTheme.TEXT)
		l.custom_minimum_size = Vector2(130, 0)
		row.add_child(l)
		var minus := Button.new()
		minus.text = " − "
		row.add_child(minus)
		var lvl := UiTheme.label("Stock", 18, UiTheme.ACCENT, true)
		lvl.custom_minimum_size = Vector2(250, 0)
		lvl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		row.add_child(lvl)
		var plus := Button.new()
		plus.text = " + "
		row.add_child(plus)
		var p: String = part
		minus.pressed.connect(func() -> void: _change_upgrade(p, -1))
		plus.pressed.connect(func() -> void: _change_upgrade(p, 1))
		v.add_child(row)
		_upgrade_rows[part] = lvl
	v.add_child(UiTheme.label("Stat bars on Overview show the upgraded car; PI updates live.", 15, UiTheme.TEXT_DIM))


func _build_tuning_tab() -> void:
	var scroll := ScrollContainer.new()
	scroll.name = "Tuning"
	_tabs.add_child(scroll)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 6)
	scroll.add_child(v)
	var labels := {"final_drive": "Gearing (final drive ×)", "brake_bias": "Brake bias (front)", "tire_balance": "Tyre pressure balance F/R",
		"springs": "Spring stiffness ×", "arb_front": "Anti-roll bar front ×", "arb_rear": "Anti-roll bar rear ×",
		"downforce": "Aero downforce ×", "diff_lock": "Differential lock", "ride_height": "Ride height (m)", "steer_lock": "Steering lock ×"}
	for key in labels:
		var row := HBoxContainer.new()
		var l := UiTheme.label(labels[key], 17, UiTheme.TEXT)
		l.custom_minimum_size = Vector2(260, 0)
		row.add_child(l)
		var s := HSlider.new()
		var rng: Array = CarTuning.TUNING_RANGES[key]
		s.min_value = rng[0]
		s.max_value = rng[1]
		s.step = (float(rng[1]) - float(rng[0])) / 100.0
		s.custom_minimum_size = Vector2(220, 24)
		s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(s)
		var val := UiTheme.label("", 17, UiTheme.ACCENT, true)
		val.custom_minimum_size = Vector2(60, 0)
		row.add_child(val)
		var k: String = key
		s.value_changed.connect(func(x: float) -> void:
			val.text = "%.2f" % x
			if not _building:
				Game.main.call("set_tuning", k, x)
				_refresh_details())
		v.add_child(row)
		_tune_sliders[key] = [s, val]
	var reset := Button.new()
	reset.text = "Reset tuning"
	reset.pressed.connect(func() -> void:
		Game.main.call("reset_tuning")
		_refresh_details())
	v.add_child(reset)


func _change_upgrade(part: String, delta: int) -> void:
	var setup: Dictionary = Game.main.call("current_setup")
	var levels: Dictionary = setup.get("upgrades", {})
	var lvl := clampi(int(levels.get(part, 0)) + delta, 0, 3)
	Game.main.call("set_upgrade", part, lvl)
	_refresh_details()


func open() -> void:
	if is_open:
		return
	is_open = true
	_root.visible = true
	Game.set_ui_focus("garage", true)
	if Game.hud != null:
		Game.hud.set("_region_t", 0.0)  # region pop-up would overlap the garage title
	_selected = Game.current_car_index
	_rebuild_list()
	_refresh_details()
	if Game.camera_rig != null:
		(Game.camera_rig as CameraRig).orbit_mode = true
	if Game.player_car != null:
		Game.player_car.input_brake = 1.0


func close() -> void:
	if not is_open:
		return
	is_open = false
	_root.visible = false
	Game.set_ui_focus("garage", false)
	if Game.camera_rig != null:
		(Game.camera_rig as CameraRig).orbit_mode = false
		(Game.camera_rig as CameraRig).snap()


func _unhandled_input(event: InputEvent) -> void:
	if Game.ui_focus.has("console"):
		return
	if event.is_action_pressed("toggle_garage"):
		if is_open:
			close()
		else:
			open()
		get_viewport().set_input_as_handled()
	elif is_open and event.is_action_pressed("pause_menu"):
		close()
		get_viewport().set_input_as_handled()


func _rebuild_list() -> void:
	for c in _list.get_children():
		c.queue_free()
	for i in Game.car_defs.size():
		var d := Game.car_defs[i]
		var b := Button.new()
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size = Vector2(0, 58)
		b.text = "  %s   %s\n  %s · %s" % [d.performance_class, d.display_name, d.category, d.drivetrain_label()]
		b.add_theme_font_size_override("font_size", 18)
		if i == _selected:
			b.add_theme_stylebox_override("normal", UiTheme.panel_style(Color(0.2, 0.17, 0.1, 0.95), 6, UiTheme.ACCENT))
		var idx := i
		b.pressed.connect(func() -> void: _select(idx))
		_list.add_child(b)


func _select(i: int) -> void:
	_selected = i
	if i != Game.current_car_index:
		Game.main.call("switch_car", i)
		if Game.player_car != null:
			Game.player_car.input_brake = 1.0
	_rebuild_list()
	_refresh_details()


func _refresh_details() -> void:
	if Game.car_defs.is_empty():
		return
	var base := Game.car_defs[_selected]
	var d: CarDefinition = Game.main.call("runtime_definition", _selected)
	_title.text = base.display_name
	_subtitle.text = "%s  ·  %d  ·  %s  ·  %s" % [base.maker, base.year, base.category, base.engine_label]
	_desc.text = base.description
	var pi := CarTuning.performance_index(d)
	var cls := _class_for(pi)
	_pi_label.text = "%s %d" % [cls, pi]
	_pi_label.add_theme_color_override("font_color", UiTheme.class_color(cls))
	for c in _specs.get_children():
		c.queue_free()
	var specs := [["Power", "%d kW" % int(d.power_kw)], ["Weight", "%d kg" % int(d.mass)],
		["Drive", d.drivetrain_label()], ["Gears", str(d.gear_ratios.size())],
		["Top speed", "%d km/h" % int(base.top_speed_kmh)], ["0-100", "%.1f s" % base.zero_to_100_s if base.zero_to_100_s > 0.0 else "—"],
		["Redline", "%d rpm" % int(d.redline_rpm)], ["Torque", "%d Nm" % int(d.max_torque_nm)]]
	for s in specs:
		_specs.add_child(UiTheme.label(s[0], 16, UiTheme.TEXT_DIM))
		_specs.add_child(UiTheme.label(s[1], 18, UiTheme.TEXT, true))
	var st := CarTuning.stats(d)
	for k in STAT_NAMES:
		var pair: Array = _bars[k]
		(pair[0] as ProgressBar).value = st[k]
		(pair[1] as Label).text = "%.1f" % st[k]
	var setup: Dictionary = Game.main.call("current_setup")
	var levels: Dictionary = setup.get("upgrades", {})
	for part in CarTuning.PARTS:
		var lvl := int(levels.get(part, 0))
		var u := CarTuning.get_upgrade(part, lvl)
		(_upgrade_rows[part] as Label).text = "Stock" if lvl == 0 or u == null else "L%d  %s" % [lvl, u.display_name]
	_building = true
	var tuning: Dictionary = setup.get("tuning", {})
	for key in _tune_sliders:
		var pair: Array = _tune_sliders[key]
		var val := float(tuning.get(key, CarTuning.TUNING_DEFAULTS[key]))
		if key == "brake_bias" and val < 0.0:
			val = base.brake_bias
		if key == "diff_lock" and val < 0.0:
			val = base.diff_lock
		(pair[0] as HSlider).value = val
		(pair[1] as Label).text = "%.2f" % val
	_building = false


func _class_for(pi: int) -> String:
	if pi <= 500:
		return "D"
	if pi <= 600:
		return "C"
	if pi <= 700:
		return "B"
	if pi <= 800:
		return "A"
	if pi <= 900:
		return "S1"
	return "S2"
