extends "res://scripts/ui/menu_base.gd"
## Pause menu (pause: Esc; Esc first closes any other open menu): resume, settings,
## controls, save, load, quit. Pauses the SceneTree while open.

const Actions := preload("res://scripts/ui/menu_actions.gd")
const Stats := preload("res://scripts/ui/menu_car_stats.gd")
const PAGES: Array[String] = ["Overview", "Settings", "Controls"]
const CONTROL_ROWS := [
	["Throttle", ["accelerate"]], ["Brake / reverse", ["brake"]], ["Steer", ["steer_left", "steer_right"]],
	["Handbrake", ["handbrake"]], ["Shift up / down", ["gear_up", "gear_down"]], ["Horn", ["horn"]],
	["Headlights", ["headlights"]], ["Reset to road", ["reset_car"]], ["Rewind (hold)", ["rewind"]], ["Change camera", ["camera_next"]],
	["Look back", ["look_back"]], ["Free look", ["free_look"]], ["Map", ["toggle_map"]],
	["Garage", ["toggle_garage"]], ["Debug menu", ["toggle_debug_menu"]], ["Console", ["toggle_console"]],
	["Photo mode", ["toggle_photo_mode"]], ["Hide HUD", ["toggle_hud"]], ["Telemetry", ["toggle_telemetry"]],
	["Screenshot", ["screenshot"]], ["Pause", ["pause"]],
]
const MENU_ROWS := [
	["Menu: move", "Arrows"], ["Menu: select", "Enter"], ["Menu: back", "Esc"], ["Menu: switch tab", "Q / E"],
	["Photo: fly", "W A S D  Q E"], ["Photo: fast", "Shift"], ["Photo: look", "RMB drag"], ["Photo: zoom", "Wheel"],
	["Photo: panel", "Tab / Arrows, Enter"], ["Photo: hide UI", "H"], ["Photo: capture", "F12"],
]

var page: int = 0
var _side_buttons: Array[Button] = []
var _pages: Array[Control] = []
var _overview: VBoxContainer
var _load_button: Button
var _settings_first: Control
var _quality_buttons: Array[Button] = []
var _setting_widgets: Dictionary = {}


func _init() -> void:
	super._init()
	menu_id = &"pause"
	pauses_game = true
	hides_hud = true


func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.01, 0.015, 0.03, 0.62)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	var panel := Style.panel(Color(0.045, 0.055, 0.09, 0.96), 20, 30, 1, Color(1, 1, 1, 0.08))
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(1520, 840)
	panel.offset_left = -760
	panel.offset_right = 760
	panel.offset_top = -420
	panel.offset_bottom = 420
	add_child(panel)
	var h := Style.hbox(34)
	panel.add_child(h)

	var side := Style.vbox(10)
	side.custom_minimum_size = Vector2(340, 0)
	h.add_child(side)
	side.add_child(Style.title("Paused", 56))
	side.add_child(Style.accent_bar(150, 5))
	side.add_child(Style.label(Game.FESTIVAL_NAME, 20, Style.TEXT_DIM, 500, 1))
	side.add_child(Style.spacer(14))
	var items := [
		["Resume", close_menu], ["Settings", _show_page.bind(1, true)], ["Controls", _show_page.bind(2, true)],
		["Save game", _on_save], ["Load game", _on_load], ["Quit to desktop", func() -> void: Actions.quit_game(get_tree())],
	]
	for it: Array in items:
		var b := Style.button(it[0], it[1], 0, 54)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_font_override("font", Style.font(600, 1))
		b.add_theme_font_size_override("font_size", 24)
		side.add_child(b)
		_side_buttons.append(b)
		if it[0] == "Load game":
			_load_button = b
	side.add_child(Style.expander())
	side.add_child(Style.hint_bar([["Esc", "Back / resume"], ["Enter", "Select"]]))

	var content := Control.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(content)
	for builder: Callable in [_build_overview, _build_settings, _build_controls]:
		var p: Control = builder.call()
		p.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		p.visible = false
		content.add_child(p)
		_pages.append(p)


func _unhandled_input(event: InputEvent) -> void:
	if is_open or event.is_echo() or not event.is_action_pressed("pause"):
		return
	if not _game_ready() or Game.is_overlay_open() or Game.photo_mode or Game.benchmark_mode or open_menu_node(get_tree()) != null:
		return
	open_menu()
	get_viewport().set_input_as_handled()


func _on_back() -> bool:
	if page != 0:
		var from := page
		_show_page(0, false)
		_side_buttons[from].grab_focus()
		return true
	return false


func _on_opened() -> void:
	_refresh_overview()
	_sync_settings()
	_show_page(0, false)
	_side_buttons[0].grab_focus.call_deferred()


func show_page(i: int) -> void:
	_show_page(i, false)


func _show_page(i: int, focus: bool) -> void:
	page = i
	for k in _pages.size():
		_pages[k].visible = k == i
	if i == 0:
		_refresh_overview()
	if focus:
		if i == 1 and _settings_first:
			_settings_first.grab_focus.call_deferred()


# ------------------------------------------------------------------ overview

func _build_overview() -> Control:
	var p := Style.panel(Style.PANEL, 16, 26)
	_overview = Style.vbox(14)
	p.add_child(_overview)
	return p


func _refresh_overview() -> void:
	if _overview == null:
		return
	for c in _overview.get_children():
		c.queue_free()
	var d := Game.current_car_data()
	_overview.add_child(Style.caps("Now driving", 17, Style.ACCENT))
	if d:
		var row := Style.hbox(16)
		row.add_child(Style.label(d.display_name, 42, Style.TEXT, 700, 1))
		var pi := Tuning.performance_index(Game.effective_car_data(Game.current_car_index))
		var badge := Style.class_badge(Tuning.class_for(pi), pi, 26)
		badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(badge)
		_overview.add_child(row)
		_overview.add_child(Style.label("%s  ·  %s  ·  %s" % [d.category, d.year_style, d.drivetrain_name()], 21, Style.TEXT_DIM))
	_overview.add_child(Style.accent_bar(90, 4))
	var car := Game.player_car
	var region := "-"
	if car and is_instance_valid(car) and Game.world:
		region = Game.world.region_at(car.global_position)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 60)
	grid.add_theme_constant_override("v_separation", 16)
	var facts := [
		["Region", region], ["Time", Style.fmt_time(Game.get_time_of_day())],
		["Weather", String(Game.get_weather()).capitalize()], ["Traffic", "%d%%" % roundi(Game.get_traffic_density() * 100.0)],
		["Personal bests", str(Game.personal_bests.size())], ["Save file", "Found" if SaveGame.has_save() else "None yet"],
	]
	for f: Array in facts:
		var v := Style.vbox(0)
		v.custom_minimum_size = Vector2(300, 0)
		v.add_child(Style.caps(f[0], 15, Style.TEXT_FAINT))
		v.add_child(Style.label(f[1], 28, Style.TEXT, 600))
		grid.add_child(v)
	_overview.add_child(grid)
	if d:
		var r := Stats.ratings(Game.effective_car_data(Game.current_car_index))
		_overview.add_child(Style.spacer(4))
		_overview.add_child(Style.caps("%s  ·  0-100 in %.1f s  ·  %s top speed" % [d.display_name, r["zero_100"], Style.speed_text(r["top_kmh"])], 15, Style.TEXT_FAINT))
		for k: String in Stats.STAT_NAMES:
			var row := Style.hbox(14)
			var l := Style.label(k, 19, Style.TEXT_DIM, 500)
			l.custom_minimum_size = Vector2(150, 0)
			row.add_child(l)
			var bar := Style.DeltaBar.new()
			bar.custom_minimum_size = Vector2(300, 10)
			bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			bar.set_values(float(r[k]) / 10.0, float(r[k]) / 10.0)
			row.add_child(bar)
			var n := Style.label("%.1f" % float(r[k]), 19, Style.TEXT, 700)
			n.custom_minimum_size = Vector2(46, 0)
			n.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			row.add_child(n)
			_overview.add_child(row)
	_overview.add_child(Style.expander())
	var tip := Style.label("Tip: hold Backspace to rewind. F1 opens the garage, F2 the debug & benchmark menu, P photo mode and ` the console.", 19, Style.TEXT_FAINT)
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_overview.add_child(tip)
	if _load_button:
		_load_button.disabled = not SaveGame.has_save()


# ------------------------------------------------------------------ settings

func _build_settings() -> Control:
	var sc := Style.scroll()
	var mc := MarginContainer.new()
	mc.add_theme_constant_override("margin_right", 26)
	mc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(mc)
	var v := Style.vbox(8)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mc.add_child(v)
	v.add_child(_head("Display & HUD"))
	_settings_first = _toggle(v, "units_mph", "Imperial units (mph)")
	_toggle(v, "show_fps", "FPS / position readout")
	_toggle(v, "show_minimap", "Minimap")
	_toggle(v, "hud_visible", "HUD visible")
	v.add_child(_head("Camera"))
	_slider(v, "camera_shake", "Camera shake", 0.0, 1.5, 0.05)
	v.add_child(_head("Audio"))
	_slider(v, "volume_master", "Master volume", 0.0, 1.0, 0.05)
	_slider(v, "volume_engine", "Engine", 0.0, 1.0, 0.05)
	_slider(v, "volume_effects", "Effects", 0.0, 1.0, 0.05)
	_slider(v, "volume_ambient", "Ambient", 0.0, 1.0, 0.05)
	v.add_child(_head("Graphics"))
	var q := Style.hbox(8)
	var ql := Style.label("Quality", 22, Style.TEXT_DIM)
	ql.custom_minimum_size = Vector2(250, 0)
	ql.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	q.add_child(ql)
	var g := ButtonGroup.new()
	for i in 4:
		var b := Style.button(["Low", "Medium", "High", "Ultra"][i], func() -> void: Settings.set_value("quality", i), 0, 44)
		b.toggle_mode = true
		b.button_group = g
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_quality_buttons.append(b)
		q.add_child(b)
	v.add_child(q)
	_toggle(v, "vsync", "V-Sync")
	_toggle(v, "fullscreen", "Fullscreen")
	_slider(v, "render_scale", "Render scale", 0.5, 1.0, 0.05)
	var note := Style.label("Settings are saved automatically.", 18, Style.TEXT_FAINT)
	v.add_child(note)
	return sc


func _head(text: String) -> Control:
	var v := Style.vbox(2)
	v.add_child(Style.spacer(8))
	v.add_child(Style.caps(text, 17, Style.ACCENT))
	return v


func _toggle(parent: Control, key: String, text: String) -> CheckButton:
	var t := Style.toggle(text, bool(Settings.get_value(key, false)), func(on: bool) -> void: Settings.set_value(key, on))
	parent.add_child(t)
	_setting_widgets[key] = t
	return t


func _slider(parent: Control, key: String, text: String, lo: float, hi: float, step: float) -> HSlider:
	var s := Style.slider_row(text, lo, hi, step, float(Settings.get_value(key, hi)), func(x: float) -> String: return "%d%%" % roundi(x * 100.0),
		func(x: float) -> void: Settings.set_value(key, x))
	parent.add_child(s.get_meta(&"row"))
	_setting_widgets[key] = s
	return s


func _sync_settings() -> void:
	for k: String in _setting_widgets:
		var w: Control = _setting_widgets[k]
		if w is CheckButton:
			(w as CheckButton).set_pressed_no_signal(bool(Settings.get_value(k, false)))
		elif w is HSlider:
			Style.set_slider(w as HSlider, float(Settings.get_value(k, 1.0)))
	var qi := int(Settings.get_value("quality", 2))
	for i in _quality_buttons.size():
		_quality_buttons[i].set_pressed_no_signal(i == qi)


# ------------------------------------------------------------------ controls

func _build_controls() -> Control:
	var rows: Array = []
	for row: Array in CONTROL_ROWS:
		var keys: PackedStringArray = []
		for a: String in row[1]:
			for n in _binding_names(a):
				if n not in keys:
					keys.append(n)
		rows.append([row[0], keys])
	for row: Array in MENU_ROWS:
		rows.append([row[0], PackedStringArray([row[1]])])
	var h := Style.hbox(40)
	var half := ceili(rows.size() / 2.0)
	for part: Array in [rows.slice(0, half), rows.slice(half)]:
		var grid := GridContainer.new()
		grid.columns = 2
		grid.add_theme_constant_override("h_separation", 16)
		grid.add_theme_constant_override("v_separation", 10)
		grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		for t: String in ["Action", "Keyboard / mouse"]:
			grid.add_child(Style.caps(t, 15, Style.ACCENT))
		for r: Array in part:
			var l := Style.label(r[0], 19, Style.TEXT_DIM, 500)
			l.custom_minimum_size = Vector2(170, 0)
			grid.add_child(l)
			grid.add_child(_chips(r[1]))
		h.add_child(grid)
	return h


func _chips(names: PackedStringArray) -> Control:
	var h := Style.hbox(6)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if names.is_empty():
		h.add_child(Style.label("-", 18, Style.TEXT_FAINT))
	for n in names:
		var chip := PanelContainer.new()
		var st := Style.box(Color(1, 1, 1, 0.1), 6, 1, Color(1, 1, 1, 0.16), 2)
		st.content_margin_left = 7
		st.content_margin_right = 7
		chip.add_theme_stylebox_override("panel", st)
		chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		chip.add_child(Style.label(n, 16, Style.TEXT, 600))
		h.add_child(chip)
	return h


static func _binding_names(action: String) -> PackedStringArray:
	var out: PackedStringArray = []
	if not InputMap.has_action(action):
		return out
	for ev in InputMap.action_get_events(action):
		if ev is InputEventKey:
			out.append(_key_name(ev as InputEventKey))
		elif ev is InputEventMouseButton:
			var mb := ev as InputEventMouseButton
			out.append({1: "LMB", 2: "RMB", 3: "MMB"}.get(mb.button_index, "Mouse %d" % mb.button_index))
	return out


static func _key_name(k: InputEventKey) -> String:
	var code := k.keycode
	if k.physical_keycode != KEY_NONE:
		code = k.physical_keycode
		if DisplayServer.get_name() != "headless":
			var mapped := DisplayServer.keyboard_get_keycode_from_physical(k.physical_keycode)
			if mapped != KEY_NONE:
				code = mapped
	var s := OS.get_keycode_string(code)
	return {"QuoteLeft": "`", "Escape": "Esc", "PageUp": "PgUp", "PageDown": "PgDn", "Backspace": "Backspace", "Space": "Space"}.get(s, s)


# ------------------------------------------------------------------ actions

func _on_save() -> void:
	if Actions.save_game():
		toast("Game saved")
	else:
		toast("Could not write the save file", Style.BAD)
	_refresh_overview()


func _on_load() -> void:
	if not SaveGame.has_save():
		toast("No save file yet", Style.BAD)
		return
	close_menu()
	if Actions.load_game():
		Game.notify("Welcome back", "Save loaded", &"info")
