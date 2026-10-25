class_name Hud
extends CanvasLayer
## Driving HUD: speedometer/tachometer gauge, gear, assists, surface, region popups,
## toasts, event status, minimap, FPS/telemetry overlay.

var main: Node
var car: Car
var root := Control.new()
var gauge := Control.new()
var minimap := Minimap.new()
var toast_box := VBoxContainer.new()
var region_label := Label.new()
var event_label := Label.new()
var info_label := Label.new()
var hint_label := Label.new()
var telemetry_label := Label.new()
var show_telemetry := false
var _region := -1
var _region_t := 0.0
var font_big := 64

func _ready() -> void:
	layer = 5
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_at(gauge, Control.PRESET_BOTTOM_RIGHT, Vector2(-330, -320), Vector2(300, 300))
	gauge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	gauge.draw.connect(_draw_gauge)
	root.add_child(gauge)
	_at(minimap, Control.PRESET_BOTTOM_LEFT, Vector2(28, -290), Vector2(260, 260))
	root.add_child(minimap)
	_at(toast_box, Control.PRESET_CENTER_TOP, Vector2(-300, 90), Vector2(600, 300))
	toast_box.alignment = BoxContainer.ALIGNMENT_BEGIN
	toast_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(toast_box)
	_style(region_label, 44, Color(1, 1, 1))
	_at(region_label, Control.PRESET_CENTER_TOP, Vector2(-400, 26), Vector2(800, 60))
	region_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(region_label)
	_style(event_label, 26, Color(1, 0.9, 0.5))
	_at(event_label, Control.PRESET_CENTER_BOTTOM, Vector2(-400, -110), Vector2(800, 40))
	event_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(event_label)
	_style(info_label, 16, Color(0.9, 0.95, 1))
	info_label.position = Vector2(20, 14)
	root.add_child(info_label)
	_style(telemetry_label, 15, Color(0.7, 1, 0.8))
	telemetry_label.position = Vector2(20, 120)
	root.add_child(telemetry_label)
	_style(hint_label, 15, Color(1, 1, 1, 0.65))
	_at(hint_label, Control.PRESET_TOP_RIGHT, Vector2(-620, 14), Vector2(600, 30))
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hint_label.text = "` console   F1 garage   F2 debug   M map   C camera   P photo"
	root.add_child(hint_label)
	Game.notify.connect(_on_toast)

static func _at(c: Control, preset: int, off: Vector2, sz: Vector2) -> void:
	c.set_anchors_preset(preset)
	c.offset_left = off.x; c.offset_top = off.y
	c.offset_right = off.x + sz.x; c.offset_bottom = off.y + sz.y

func _style(l: Label, sz: int, c: Color) -> void:
	l.add_theme_font_size_override("font_size", sz)
	l.add_theme_color_override("font_color", c)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("outline_size", maxi(4, sz / 6))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE

func _on_toast(text: String, kind: String) -> void:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	var accent := {"info": Color(0.2, 0.7, 1.0), "warn": Color(1.0, 0.4, 0.2), "event": Color(1.0, 0.3, 0.65)}.get(kind, Color(0.2, 0.7, 1.0)) as Color
	sb.bg_color = Color(0.05, 0.06, 0.1, 0.82)
	sb.border_color = accent; sb.border_width_left = 6
	sb.corner_radius_top_right = 6; sb.corner_radius_bottom_right = 6
	sb.content_margin_left = 16; sb.content_margin_right = 16; sb.content_margin_top = 6; sb.content_margin_bottom = 6
	p.add_theme_stylebox_override("panel", sb)
	var l := Label.new()
	_style(l, 22 if kind == "event" else 18, Color(1, 1, 1))
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	p.add_child(l)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast_box.add_child(p)
	if toast_box.get_child_count() > 5: toast_box.get_child(0).queue_free()
	var tw := create_tween()
	tw.tween_interval(3.5 if kind == "event" else 2.2)
	tw.tween_property(p, "modulate:a", 0.0, 0.5)
	tw.tween_callback(p.queue_free)

func _process(dt: float) -> void:
	if car == null: return
	gauge.queue_redraw()
	var w: WorldGen = main.world
	var p := car.global_position
	var reg := w.region_at(p.x, p.z)
	if reg != _region:
		_region = reg; _region_t = 4.0
		region_label.text = WorldGen.REGION_NAMES[reg].to_upper()
	_region_t -= dt
	region_label.modulate.a = clampf(_region_t, 0.0, 1.0)
	event_label.text = main.events.status_text
	var s := ""
	if Game.settings.show_fps:
		s += "FPS %d   %.1f ms\n" % [Engine.get_frames_per_second(), 1000.0 / maxf(Engine.get_frames_per_second(), 1)]
	s += "%s · %s\n" % [car.spec.display_name, car.spec.class_rating()]
	s += "%02d:%02d  %s   traffic %d" % [int(main.sky.hour), int(fmod(main.sky.hour, 1.0) * 60.0), main.sky.state, main.traffic.active.size()]
	info_label.text = s
	telemetry_label.visible = show_telemetry
	if show_telemetry:
		var t := car.telemetry()
		telemetry_label.text = "POS %.0f %.0f %.0f\nRPM %d  GEAR %d\nSLIP %.2f  DRIFT %.0f°\nSURFACE %s  GRIP x%.2f\nSUSP %.2f %.2f %.2f %.2f\nDAMAGE %d%%" % [
			p.x, p.y, p.z, int(t.rpm), t.gear, t.slip, t.drift, WorldGen.SURFACE_NAMES[t.surface], car.weather_grip,
			car.wheels[0].comp, car.wheels[1].comp, car.wheels[2].comp, car.wheels[3].comp, int(car.damage * 100)]

func _draw_gauge() -> void:
	var c := Vector2(150, 150)
	var r := 130.0
	var spec := car.spec
	var a0 := deg_to_rad(135.0); var a1 := deg_to_rad(405.0)
	gauge.draw_circle(c, r + 8, Color(0.03, 0.04, 0.07, 0.72))
	gauge.draw_arc(c, r, a0, a1, 64, Color(1, 1, 1, 0.15), 10.0, true)
	var frac := clampf(car.rpm / spec.redline, 0.0, 1.0)
	var red_start := 0.88
	var col := Color(0.25, 0.8, 1.0) if frac < red_start else Color(1.0, 0.25, 0.2)
	gauge.draw_arc(c, r, a0, lerpf(a0, a1, frac), 64, col, 10.0, true)
	gauge.draw_arc(c, r, lerpf(a0, a1, red_start), a1, 16, Color(1, 0.2, 0.2, 0.5), 3.0, true)
	for k in int(spec.redline / 1000.0) + 1:
		var f := k * 1000.0 / spec.redline
		var ang := lerpf(a0, a1, f)
		var d := Vector2(cos(ang), sin(ang))
		gauge.draw_line(c + d * (r - 18), c + d * (r - 6), Color(1, 1, 1, 0.7), 2.0)
		gauge.draw_string(gauge.get_theme_default_font(), c + d * (r - 34) - Vector2(6, -6), str(k), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 1, 1, 0.7))
	var kmh := absf(car.speed) * 3.6
	var val := kmh if Game.settings.units_kmh else kmh * 0.621371
	var font := gauge.get_theme_default_font()
	gauge.draw_string(font, c + Vector2(-90, 22), "%d" % int(val), HORIZONTAL_ALIGNMENT_CENTER, 180, 64, Color(1, 1, 1))
	gauge.draw_string(font, c + Vector2(-90, 50), "KM/H" if Game.settings.units_kmh else "MPH", HORIZONTAL_ALIGNMENT_CENTER, 180, 16, Color(1, 1, 1, 0.6))
	var g := "R" if car.gear == -1 else ("N" if car.gear == 0 else str(car.gear))
	gauge.draw_string(font, c + Vector2(-30, -40), g, HORIZONTAL_ALIGNMENT_CENTER, 60, 40, Color(1, 0.85, 0.3))
	var flags := ""
	if car.assists.tcs: flags += ("[TCS] " if car.tcs_active else "TCS ")
	if car.assists.abs: flags += ("[ABS] " if car.abs_active else "ABS ")
	if car.assists.stm: flags += "STM "
	flags += "AUTO" if car.assists.auto else "MAN"
	gauge.draw_string(font, c + Vector2(-110, 82), flags, HORIZONTAL_ALIGNMENT_CENTER, 220, 13, Color(0.7, 0.9, 1, 0.8))
	gauge.draw_string(font, c + Vector2(-110, 102), WorldGen.SURFACE_NAMES[car.surface].to_upper(), HORIZONTAL_ALIGNMENT_CENTER, 220, 13, Color(1, 1, 1, 0.55))
