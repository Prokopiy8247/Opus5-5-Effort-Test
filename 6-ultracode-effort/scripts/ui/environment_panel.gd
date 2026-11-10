extends "res://scripts/ui/menu_base.gd"
## "Environment" side panel (toggle_environment: N): weather buttons, time-of-day slider with presets and
## the day-speed switch - usable while driving (no pause, the car stays under your control). A thin wrapper
## over the Game API (set_weather / set_time_of_day / set_time_scale), so the console and the F2 debug menu
## stay in sync automatically: the panel re-reads the live values every frame while open.

const TIME_PRESETS := [["Dawn", 6.0], ["Noon", 12.0], ["Sunset", 19.0], ["Night", 23.0]]
const SCALES: Array = [["Freeze", 0.0], ["1x", 1.0], ["10x", 10.0], ["60x", 60.0]]

var _time_label: Label
var _time_slider: HSlider
var _weather_box: HFlowContainer
var _weather_buttons: Dictionary = {}
var _scale_buttons: Dictionary = {}
var _env_note: Label
var _dragging: bool = false


func _init() -> void:
	super._init()
	menu_id = &"environment"
	toggle_action = &"toggle_environment"


func _build() -> void:
	# A compact side panel, not a full-screen menu: clicks and mouse look outside it keep working.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var panel := Style.panel(Color(0.045, 0.055, 0.09, 0.94), 16, 18.0, 1, Color(1, 1, 1, 0.1))
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_RIGHT)
	panel.custom_minimum_size = Vector2(440, 0)
	panel.offset_right = -28
	panel.offset_left = -28 - 440
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	add_child(panel)
	var v := Style.vbox(10)
	panel.add_child(v)

	var head := Style.hbox(12)
	var tv := Style.vbox(2)
	tv.add_child(Style.title("Environment", 30))
	tv.add_child(Style.accent_bar(120, 4))
	head.add_child(tv)
	head.add_child(Style.expander())
	_time_label = Style.label("12:00", 34, Style.GOLD, 700)
	_time_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(_time_label)
	v.add_child(head)

	_env_note = Style.label("Environment system not loaded - time and weather are unavailable", 17, Style.BAD)
	_env_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_env_note.visible = false
	v.add_child(_env_note)

	v.add_child(_caps_row("Time of day"))
	_time_slider = Style.slider_row("Hour", 0.0, 24.0, 0.25, 12.0, func(x: float) -> String: return Style.fmt_time(x), func(x: float) -> void:
		if Game.env != null:
			Game.set_time_of_day(fposmod(x, 24.0)), 96)
	_time_slider.drag_started.connect(func() -> void: _dragging = true)
	_time_slider.drag_ended.connect(func(_changed: bool) -> void: _dragging = false)
	v.add_child(_time_slider.get_meta(&"row"))
	var pr := Style.hbox(6)
	for p: Array in TIME_PRESETS:
		var b := Style.button(String(p[0]), _set_time.bind(float(p[1])), 0, 40)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size", 18)
		pr.add_child(b)
	v.add_child(pr)

	v.add_child(_caps_row("Day speed"))
	var sr := Style.hbox(6)
	var group := ButtonGroup.new()
	for s: Array in SCALES:
		var b := Style.button(String(s[0]), _set_scale.bind(float(s[1])), 0, 40)
		b.toggle_mode = true
		b.button_group = group
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size", 18)
		_scale_buttons[float(s[1])] = b
		sr.add_child(b)
	v.add_child(sr)

	v.add_child(_caps_row("Weather"))
	_weather_box = HFlowContainer.new()
	_weather_box.add_theme_constant_override("h_separation", 6)
	_weather_box.add_theme_constant_override("v_separation", 6)
	v.add_child(_weather_box)
	v.add_child(Style.spacer(2))
	v.add_child(Style.hint_bar([["Esc", "Close"], ["1-5", "Weather"], ["N", "Panel"]]))


func _caps_row(text: String) -> Control:
	var h := Style.hbox(8)
	var bar := ColorRect.new()
	bar.color = Style.ACCENT
	bar.custom_minimum_size = Vector2(3, 16)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(bar)
	h.add_child(Style.caps(text, 15, Style.TEXT_DIM))
	h.add_child(Style.expander())
	return h


func _set_time(h: float) -> void:
	Game.set_time_of_day(h)
	_show_time(h)


func _set_scale(s: float) -> void:
	Game.set_time_scale(s)
	_sync_scale()


# ------------------------------------------------------------------ open / sync

func _on_opened() -> void:
	_sync()


func _sync() -> void:
	var has_env := Game.env != null
	_env_note.visible = not has_env
	_time_slider.editable = has_env
	_show_time(Game.get_time_of_day())
	_sync_weather()
	_sync_scale()


func _show_time(h: float) -> void:
	var txt := Style.fmt_time(h)
	if _time_label.text == txt:
		return
	Style.set_slider(_time_slider, fposmod(h, 24.0))
	_time_label.text = txt
	(_time_slider.get_meta(&"value_label") as Label).text = txt


func _sync_weather() -> void:
	var ids := Game.get_weather_ids()
	if _weather_buttons.size() != ids.size():
		for c in _weather_box.get_children():
			c.queue_free()
		_weather_buttons.clear()
		var i := 0
		for id: Variant in ids:
			i += 1
			var b := Style.button("%d  %s" % [i % 10, String(id).capitalize()], _set_weather.bind(String(id)), 0, 42)
			b.toggle_mode = true
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			b.add_theme_font_size_override("font_size", 18)
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			_weather_box.add_child(b)
			_weather_buttons[String(id)] = b
	var cur := String(Game.get_weather())
	for k: String in _weather_buttons:
		(_weather_buttons[k] as Button).set_pressed_no_signal(k == cur)


func _set_weather(id: String) -> void:
	# Smooth transition (default): the weather system blends over ~25 s.
	Game.set_weather(id)


func _sync_scale() -> void:
	var s := Game.get_time_scale()
	var best := 1.0
	var best_d := INF
	for v: float in _scale_buttons:
		var d := absf(v - s)
		if d < best_d:
			best_d = d
			best = v
	for v: float in _scale_buttons:
		(_scale_buttons[v] as Button).set_pressed_no_signal(v == best)


func _process(_delta: float) -> void:
	if not is_open:
		return
	# Live sync: the clock runs (day speed), weather transitions update, console / F2 edits show up.
	if not _dragging:
		_show_time(Game.get_time_of_day())
	_sync_weather()
	_sync_scale()


func _menu_input(event: InputEvent) -> void:
	# Number keys 1..9 pick a weather (same order as the buttons) unless a modifier is held.
	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo or k.shift_pressed or k.ctrl_pressed or k.alt_pressed:
		return
	var idx := -1
	if k.keycode >= KEY_1 and k.keycode <= KEY_9:
		idx = k.keycode - KEY_1
	elif k.keycode >= KEY_KP_1 and k.keycode <= KEY_KP_9:
		idx = k.keycode - KEY_KP_1
	var ids := Game.get_weather_ids()
	if idx >= 0 and idx < ids.size():
		_set_weather(String(ids[idx]))
		get_viewport().set_input_as_handled()
