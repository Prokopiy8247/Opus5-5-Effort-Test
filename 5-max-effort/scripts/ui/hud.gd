class_name Hud
extends CanvasLayer
## Driving HUD: speedometer/tachometer cluster, gear, assist and surface indicators,
## notifications, region name pop-ups, activity panel, key hints and a debug overlay.

class Gauge:
	extends Control
	var car: CarController
	var _rpm_disp: float = 0.0
	var _speed_disp: float = 0.0
	var _shift_flash: float = 0.0

	func _process(delta: float) -> void:
		if car != null and is_instance_valid(car):
			_rpm_disp = lerpf(_rpm_disp, car.rpm, 1.0 - exp(-delta * 18.0))
			_speed_disp = lerpf(_speed_disp, car.speed_kmh, 1.0 - exp(-delta * 12.0))
			_shift_flash += delta
		queue_redraw()

	func _draw() -> void:
		if car == null or not is_instance_valid(car):
			return
		var def := car.definition
		var r := minf(size.x, size.y) * 0.5 - 8.0
		var c := Vector2(size.x * 0.5, size.y * 0.5)
		var a0 := deg_to_rad(135.0)
		var sweep := deg_to_rad(270.0)
		draw_circle(c, r + 4.0, Color(0.03, 0.035, 0.05, 0.62))
		draw_arc(c, r - 6.0, a0, a0 + sweep, 96, Color(1, 1, 1, 0.08), 12.0, true)
		var max_rpm := ceilf(def.redline_rpm / 1000.0 + 0.5) * 1000.0
		var red_frac := def.redline_rpm / max_rpm
		draw_arc(c, r - 6.0, a0 + sweep * red_frac, a0 + sweep, 32, Color(1.0, 0.2, 0.18, 0.45), 12.0, true)
		var frac := clampf(_rpm_disp / max_rpm, 0.0, 1.0)
		var col := UiTheme.ACCENT2.lerp(UiTheme.ACCENT, smoothstep(0.55, 0.85, frac / red_frac))
		if frac > red_frac * 0.97:
			col = UiTheme.RED if fmod(_shift_flash, 0.16) < 0.08 else Color(1, 1, 1)
		draw_arc(c, r - 6.0, a0, a0 + sweep * frac, 96, col, 12.0, true)
		var font := UiTheme.font(true)
		var steps := int(max_rpm / 1000.0)
		for i in steps + 1:
			var a := a0 + sweep * float(i) / float(steps)
			var dir := Vector2(cos(a), sin(a))
			draw_line(c + dir * (r - 18.0), c + dir * (r - 26.0), Color(1, 1, 1, 0.75), 2.0, true)
			var tp := c + dir * (r - 40.0)
			draw_string(UiTheme.font(), tp + Vector2(-8, 6), str(i), HORIZONTAL_ALIGNMENT_CENTER, 16, 15, Color(1, 1, 1, 0.7))
		var speed_txt := Game.speed_text(_speed_disp)
		draw_string(font, c + Vector2(-90, 22), speed_txt, HORIZONTAL_ALIGNMENT_CENTER, 180, 72, UiTheme.TEXT)
		draw_string(UiTheme.font(), c + Vector2(-60, 48), Game.speed_unit(), HORIZONTAL_ALIGNMENT_CENTER, 120, 17, UiTheme.TEXT_DIM)
		var g := car.gear
		var gtxt := "N" if g == 0 else ("R" if g < 0 else str(g))
		var gbox := Rect2(c + Vector2(-22, r * 0.48), Vector2(44, 40))
		draw_rect(gbox, Color(0, 0, 0, 0.55))
		draw_rect(gbox, UiTheme.ACCENT if car.shift_timer > 0.0 else Color(1, 1, 1, 0.25), false, 2.0)
		draw_string(font, gbox.position + Vector2(0, 32), gtxt, HORIZONTAL_ALIGNMENT_CENTER, 44, 30, UiTheme.TEXT)
		draw_string(UiTheme.font(), c + Vector2(-60, -r * 0.42), "x1000 rpm", HORIZONTAL_ALIGNMENT_CENTER, 120, 13, Color(1, 1, 1, 0.45))

var car: CarController
var gauge: Gauge
var _notify_box: VBoxContainer
var _region: Label
var _region_t: float = 0.0
var _debug: Label
var _hints: Label
var _hint_t: float = 14.0
var _assists: HBoxContainer
var _assist_labels: Dictionary = {}
var _surface: Label
var _activity: PanelContainer
var _act_title: Label
var _act_line1: Label
var _act_line2: Label
var _center_msg: Label
var _center_t: float = 0.0
var root: Control
var minimap_slot: Control
var visible_hud: bool = true


func _ready() -> void:
	layer = 10
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UiTheme.get_theme()
	add_child(root)

	gauge = Gauge.new()
	gauge.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	gauge.offset_left = -330
	gauge.offset_top = -330
	gauge.offset_right = -24
	gauge.offset_bottom = -24
	gauge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(gauge)

	_assists = HBoxContainer.new()
	_assists.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_assists.offset_left = -330
	_assists.offset_right = -24
	_assists.offset_top = -30
	_assists.offset_bottom = -6
	_assists.alignment = BoxContainer.ALIGNMENT_CENTER
	_assists.add_theme_constant_override("separation", 14)
	root.add_child(_assists)
	for k in ["TCS", "ABS", "ESC"]:
		var l := UiTheme.label(k, 15, Color(1, 1, 1, 0.25), true)
		_assists.add_child(l)
		_assist_labels[k] = l
	_surface = UiTheme.label("", 15, UiTheme.TEXT_DIM)
	_assists.add_child(_surface)

	_notify_box = VBoxContainer.new()
	_notify_box.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_notify_box.offset_left = -330
	_notify_box.offset_right = 330
	_notify_box.offset_top = 24
	_notify_box.alignment = BoxContainer.ALIGNMENT_BEGIN
	_notify_box.add_theme_constant_override("separation", 8)
	_notify_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_notify_box)

	_region = UiTheme.label("", 46, UiTheme.TEXT, true)
	_region.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_region.offset_left = 40
	_region.offset_top = 36
	_region.modulate.a = 0.0
	_region.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.55))
	_region.add_theme_constant_override("outline_size", 8)
	root.add_child(_region)

	_debug = UiTheme.label("", 16, UiTheme.TEXT)
	_debug.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_debug.offset_left = -430
	_debug.offset_right = -20
	_debug.offset_top = 16
	_debug.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_debug.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_debug.add_theme_constant_override("outline_size", 6)
	root.add_child(_debug)

	_hints = UiTheme.label("`  Console     F1 / Tab  Garage     F3  Debug     M  Map     P  Photo     C  Camera     R  Reset     Backspace  Rewind", 17, Color(1, 1, 1, 0.8))
	_hints.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_hints.offset_left = -560
	_hints.offset_right = 560
	_hints.offset_top = -44
	_hints.offset_bottom = -14
	_hints.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hints.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_hints.add_theme_constant_override("outline_size", 6)
	root.add_child(_hints)

	_activity = PanelContainer.new()
	_activity.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_activity.offset_left = -230
	_activity.offset_right = 230
	_activity.offset_top = 110
	_activity.visible = false
	root.add_child(_activity)
	var av := VBoxContainer.new()
	_activity.add_child(av)
	_act_title = UiTheme.label("", 22, UiTheme.ACCENT, true)
	_act_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	av.add_child(_act_title)
	_act_line1 = UiTheme.label("", 40, UiTheme.TEXT, true)
	_act_line1.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	av.add_child(_act_line1)
	_act_line2 = UiTheme.label("", 18, UiTheme.TEXT_DIM)
	_act_line2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	av.add_child(_act_line2)

	_center_msg = UiTheme.label("", 56, UiTheme.ACCENT, true)
	_center_msg.set_anchors_preset(Control.PRESET_CENTER)
	_center_msg.offset_left = -500
	_center_msg.offset_right = 500
	_center_msg.offset_top = -160
	_center_msg.offset_bottom = -90
	_center_msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_center_msg.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	_center_msg.add_theme_constant_override("outline_size", 10)
	_center_msg.modulate.a = 0.0
	root.add_child(_center_msg)

	minimap_slot = Control.new()
	minimap_slot.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	minimap_slot.offset_left = 24
	minimap_slot.offset_top = -304
	minimap_slot.offset_right = 304
	minimap_slot.offset_bottom = -24
	minimap_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(minimap_slot)

	Game.notify.connect(_on_notify)
	Game.region_entered.connect(show_region)


func set_car(c: CarController) -> void:
	car = c
	gauge.car = c


func _on_notify(title: String, body: String, kind: String) -> void:
	var p := PanelContainer.new()
	var col := UiTheme.ACCENT if kind == "event" else (UiTheme.ACCENT2 if kind == "info" else UiTheme.GOOD)
	p.add_theme_stylebox_override("panel", UiTheme.panel_style(UiTheme.PANEL, 8, col * Color(1, 1, 1, 0.8)))
	var v := VBoxContainer.new()
	p.add_child(v)
	var t := UiTheme.label(title.to_upper(), 20, col, true)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	if body != "":
		var b := UiTheme.label(body, 18, UiTheme.TEXT)
		b.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(b)
	_notify_box.add_child(p)
	p.set_meta("t", 3.2 if kind != "event" else 4.5)
	while _notify_box.get_child_count() > 4:
		_notify_box.get_child(0).queue_free()
		_notify_box.remove_child(_notify_box.get_child(0))


func show_region(region_name: String) -> void:
	_region.text = region_name.to_upper()
	_region_t = 4.0


func show_center(msg: String, duration: float = 2.0, color: Color = UiTheme.ACCENT) -> void:
	_center_msg.text = msg
	_center_msg.add_theme_color_override("font_color", color)
	_center_t = duration


func show_activity(title: String, line1: String, line2: String = "") -> void:
	_activity.visible = true
	_act_title.text = title
	_act_line1.text = line1
	_act_line2.text = line2


func hide_activity() -> void:
	_activity.visible = false


func _process(delta: float) -> void:
	if Input.is_action_just_pressed("toggle_hud") and not Game.ui_focus.has("console"):
		visible_hud = not visible_hud
	root.visible = visible_hud
	for child in _notify_box.get_children():
		var t := float(child.get_meta("t", 0.0)) - delta
		child.set_meta("t", t)
		child.modulate.a = clampf(t / 0.5, 0.0, 1.0)
		if t <= 0.0:
			child.queue_free()
	_region_t = maxf(_region_t - delta, 0.0)
	_region.modulate.a = clampf(minf(_region_t, 4.0 - _region_t) * 2.0, 0.0, 1.0) if _region_t > 0.0 else 0.0
	_center_t = maxf(_center_t - delta, 0.0)
	_center_msg.modulate.a = clampf(_center_t * 3.0, 0.0, 1.0)
	_hint_t -= delta
	_hints.modulate.a = clampf(_hint_t, 0.25, 1.0)
	if car == null or not is_instance_valid(car):
		return
	(_assist_labels["TCS"] as Label).add_theme_color_override("font_color", UiTheme.ACCENT if car.tcs_active else (Color(1, 1, 1, 0.35) if car.assist_tcs else Color(1, 1, 1, 0.1)))
	(_assist_labels["ABS"] as Label).add_theme_color_override("font_color", UiTheme.ACCENT if car.abs_active else (Color(1, 1, 1, 0.35) if car.assist_abs else Color(1, 1, 1, 0.1)))
	(_assist_labels["ESC"] as Label).add_theme_color_override("font_color", UiTheme.ACCENT if car.esc_active else (Color(1, 1, 1, 0.35) if car.assist_esc else Color(1, 1, 1, 0.1)))
	_surface.text = Surfaces.get_def(car.surface_under).display_name.to_upper()
	var show_fps: bool = Game.settings.get("show_fps", false)
	if show_fps:
		var p := car.global_position
		_debug.text = "%d FPS  %.1f ms\nX %.0f  Y %.0f  Z %.0f\n%s %s  rpm %d  slip %.2f" % [
			Engine.get_frames_per_second(), 1000.0 / maxf(Engine.get_frames_per_second(), 1.0), p.x, p.y, p.z,
			Game.speed_text(car.speed_kmh), Game.speed_unit(), car.rpm, car.wheel_slip_max()]
	else:
		_debug.text = ""
