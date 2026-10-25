extends Control
## In-game HUD: speedometer + tachometer dial, gear, surface and assist indicators, region popups,
## activity panel, notification toasts, FPS / position readout and telemetry overlay.

const ACCENT := Color(1.0, 0.36, 0.62)
const ACCENT2 := Color(1.0, 0.62, 0.1)
const BG := Color(0.04, 0.05, 0.08, 0.62)

var font: Font
var show_telemetry: bool = false
var region_text: String = ""
var region_t: float = 0.0
var toasts: Array = []  # [title, body, color, time]
var activity_title: String = ""
var activity_lines: PackedStringArray = []
var activity_color: Color = ACCENT
var minimap: Control
var _fps_smooth: float = 60.0
var _frame_ms: float = 16.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	font = ThemeDB.fallback_font
	Game.notify.connect(_on_notify)
	Game.region_changed.connect(func(n: String) -> void:
		region_text = n
		region_t = 4.0)
	minimap = load("res://scripts/ui/minimap.gd").new()
	add_child(minimap)


func _on_notify(t: String, b: String, c: Color) -> void:
	toasts.append([t, b, c, 5.0])
	if toasts.size() > 4:
		toasts.pop_front()


func set_activity(title: String, lines: PackedStringArray, color: Color = ACCENT) -> void:
	activity_title = title
	activity_lines = lines
	activity_color = color


func _process(delta: float) -> void:
	region_t = maxf(0.0, region_t - delta)
	for t in toasts:
		t[3] -= delta
	toasts = toasts.filter(func(t): return t[3] > 0.0)
	_fps_smooth = lerpf(_fps_smooth, Engine.get_frames_per_second(), 0.05)
	_frame_ms = lerpf(_frame_ms, delta * 1000.0, 0.1)
	queue_redraw()


func _sc() -> float:
	return size.y / 1080.0


func _draw() -> void:
	var _pf: int = Time.get_ticks_usec()
	_inner_draw()
	Game.prof_add("hud_draw", _pf)


func _inner_draw() -> void:
	if size.y < 200.0:
		return
	var car: Car = Game.player as Car
	var s: float = _sc()
	if car and is_instance_valid(car):
		_draw_dial(car, s)
		_draw_status(car, s)
	_draw_toasts(s)
	_draw_region(s)
	_draw_activity(s)
	if Game.settings.show_fps:
		var p: Vector3 = car.global_position if car else Vector3.ZERO
		var txt: String = "%d FPS  %.1f ms   X %.0f  Y %.0f  Z %.0f" % [roundi(_fps_smooth), _frame_ms, p.x, p.y, p.z]
		draw_string(font, Vector2(16, 30) * s, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, int(18 * s), Color(1, 1, 1, 0.8))
	if show_telemetry and car:
		_draw_telemetry(car, s)
	var hint: String = "[`] Console   [Tab] Garage   [F2] Debug   [F3] Tuning   [M] Map   [P] Photo   [C] Camera   [R] Reset"
	draw_string(font, Vector2(16, size.y - 14 * s), hint, HORIZONTAL_ALIGNMENT_LEFT, -1, int(15 * s), Color(1, 1, 1, 0.55))


func _draw_dial(car: Car, s: float) -> void:
	var c := Vector2(size.x - 190 * s, size.y - 175 * s)
	var r: float = 135.0 * s
	draw_circle(c, r + 12 * s, BG)
	var a0: float = deg_to_rad(140.0)
	var a1: float = deg_to_rad(400.0)
	var red_frac: float = car.def.redline / (ceilf(car.def.redline / 1000.0) * 1000.0 + 1000.0)
	var max_rpm: float = ceilf(car.def.redline / 1000.0) * 1000.0 + 1000.0
	# tach arc
	draw_arc(c, r, a0, a1, 64, Color(1, 1, 1, 0.15), 10 * s, true)
	var rf: float = clampf(car.rpm / max_rpm, 0.0, 1.0)
	var col: Color = ACCENT2.lerp(Color(1, 0.15, 0.1), clampf((car.rpm - car.def.redline * 0.85) / (car.def.redline * 0.15), 0.0, 1.0))
	draw_arc(c, r, a0, lerpf(a0, a1, rf), 64, col, 10 * s, true)
	draw_arc(c, r, lerpf(a0, a1, car.def.redline / max_rpm), a1, 16, Color(1, 0.1, 0.1, 0.55), 10 * s, true)
	for k in int(max_rpm / 1000.0) + 1:
		var a: float = lerpf(a0, a1, k * 1000.0 / max_rpm)
		var dir := Vector2(cos(a), sin(a))
		draw_line(c + dir * (r - 22 * s), c + dir * (r - 10 * s), Color(1, 1, 1, 0.8), 2 * s)
		draw_string(font, c + dir * (r - 38 * s) - Vector2(6, -6) * s, str(k), HORIZONTAL_ALIGNMENT_LEFT, -1, int(15 * s), Color(1, 1, 1, 0.75))
	# speed
	var spd: float = car.kmh()
	var unit: String = "KM/H"
	if Game.settings.units_mph:
		spd *= 0.621371
		unit = "MPH"
	var st: String = str(roundi(spd))
	draw_string(font, c + Vector2(-90, 22) * s, st, HORIZONTAL_ALIGNMENT_CENTER, 180 * s, int(64 * s), Color.WHITE)
	draw_string(font, c + Vector2(-90, 50) * s, unit, HORIZONTAL_ALIGNMENT_CENTER, 180 * s, int(16 * s), Color(1, 1, 1, 0.7))
	var g: String = "R" if car.gear < 0 else str(car.gear)
	if absf(car.speed) < 0.3 and car.in_throttle < 0.05 and car.gear == 1:
		g = "N"
	draw_circle(c + Vector2(0, -50) * s, 26 * s, Color(0, 0, 0, 0.5))
	draw_string(font, c + Vector2(-30, -38) * s, g, HORIZONTAL_ALIGNMENT_CENTER, 60 * s, int(36 * s), ACCENT if car.rpm < car.def.redline * 0.92 else Color(1, 0.2, 0.2))
	draw_string(font, c + Vector2(-60, 86) * s, ("MANUAL" if Game.settings.manual_gears else "AUTO"), HORIZONTAL_ALIGNMENT_CENTER, 120 * s, int(13 * s), Color(1, 1, 1, 0.6))
	# car + class tag
	var tag: String = "%s %d" % [car.def.car_class, car.def.pi]
	var tr := Rect2(c + Vector2(-48, 100) * s, Vector2(96, 26) * s)
	draw_rect(tr, _class_color(car.def.car_class))
	draw_string(font, tr.position + Vector2(0, 19 * s), tag, HORIZONTAL_ALIGNMENT_CENTER, tr.size.x, int(16 * s), Color.WHITE)


static func _class_color(cl: String) -> Color:
	match cl:
		"D": return Color(0.3, 0.75, 0.95)
		"C": return Color(0.95, 0.8, 0.2)
		"B": return Color(0.95, 0.5, 0.15)
		"A": return Color(0.9, 0.2, 0.25)
		"S1": return Color(0.65, 0.3, 0.9)
		"S2": return Color(0.25, 0.4, 0.95)
	return Color(0.2, 0.8, 0.4)


func _draw_status(car: Car, s: float) -> void:
	var x: float = size.x - 470 * s
	var y: float = size.y - 60 * s
	var items: Array = [["TCS", Game.settings.assist_tcs, car.tcs_active], ["ESC", Game.settings.assist_esc, car.esc_active], ["ABS", Game.settings.assist_abs, car.abs_active], ["STR", Game.settings.assist_steer, false]]
	for it in items:
		var on: bool = it[1]
		var act: bool = it[2]
		var col: Color = Color(1, 1, 1, 0.25) if not on else (ACCENT2 if act else Color(0.45, 0.9, 0.55))
		draw_rect(Rect2(Vector2(x, y), Vector2(48, 22) * s), Color(0, 0, 0, 0.45))
		draw_string(font, Vector2(x, y + 16 * s), it[0], HORIZONTAL_ALIGNMENT_CENTER, 48 * s, int(14 * s), col)
		x += 54 * s
	var surf: String = WorldData.SURFACE_NAMES[car.surface_now].to_upper()
	if Game.sky and Game.sky.wet > 0.3 and car.surface_now <= 1:
		surf = "WET " + surf
	draw_string(font, Vector2(size.x - 470 * s, y - 12 * s), surf, HORIZONTAL_ALIGNMENT_LEFT, -1, int(16 * s), Color(1, 1, 1, 0.8))
	if car.damage > 1.0:
		draw_string(font, Vector2(size.x - 470 * s, y - 34 * s), "DAMAGE %d%%" % roundi(car.damage), HORIZONTAL_ALIGNMENT_LEFT, -1, int(15 * s), Color(1, 0.5, 0.4, 0.9))
	if car.lights_on:
		draw_string(font, Vector2(size.x - 360 * s, y - 12 * s), "LIGHTS", HORIZONTAL_ALIGNMENT_LEFT, -1, int(14 * s), Color(0.6, 0.85, 1.0))


func _draw_toasts(s: float) -> void:
	var y: float = 70 * s
	for t in toasts:
		var a: float = clampf(t[3], 0.0, 1.0)
		var w: float = 520 * s
		var x: float = (size.x - w) * 0.5
		var col: Color = t[2]
		draw_rect(Rect2(Vector2(x, y), Vector2(w, 64 * s)), Color(BG.r, BG.g, BG.b, BG.a * a))
		draw_rect(Rect2(Vector2(x, y), Vector2(6 * s, 64 * s)), Color(col.r, col.g, col.b, a))
		draw_string(font, Vector2(x + 20 * s, y + 26 * s), t[0], HORIZONTAL_ALIGNMENT_LEFT, w - 30 * s, int(22 * s), Color(1, 1, 1, a))
		draw_string(font, Vector2(x + 20 * s, y + 50 * s), t[1], HORIZONTAL_ALIGNMENT_LEFT, w - 30 * s, int(15 * s), Color(1, 1, 1, 0.8 * a))
		y += 72 * s


func _draw_region(s: float) -> void:
	if region_t <= 0.0:
		return
	var a: float = clampf(region_t, 0.0, 1.0)
	var y: float = size.y * 0.28
	draw_string(font, Vector2(0, y), "ENTERING", HORIZONTAL_ALIGNMENT_CENTER, size.x, int(18 * s), Color(1, 1, 1, 0.7 * a))
	draw_string(font, Vector2(0, y + 48 * s), region_text.to_upper(), HORIZONTAL_ALIGNMENT_CENTER, size.x, int(44 * s), Color(1, 1, 1, a))
	draw_rect(Rect2(Vector2(size.x * 0.5 - 120 * s, y + 62 * s), Vector2(240 * s, 4 * s)), Color(ACCENT.r, ACCENT.g, ACCENT.b, a))


func _draw_activity(s: float) -> void:
	if activity_title == "":
		return
	var w: float = 380 * s
	var h: float = (44 + activity_lines.size() * 28) * s
	var p := Vector2(size.x - w - 20 * s, 60 * s)
	draw_rect(Rect2(p, Vector2(w, h)), BG)
	draw_rect(Rect2(p, Vector2(w, 5 * s)), activity_color)
	draw_string(font, p + Vector2(16, 32) * s, activity_title, HORIZONTAL_ALIGNMENT_LEFT, w, int(22 * s), Color.WHITE)
	for i in activity_lines.size():
		draw_string(font, p + Vector2(16, 62 + i * 28) * s, activity_lines[i], HORIZONTAL_ALIGNMENT_LEFT, w, int(19 * s), Color(1, 1, 1, 0.88))


func _draw_telemetry(car: Car, s: float) -> void:
	var p := Vector2(16, 50) * s
	var lines: PackedStringArray = [
		"TELEMETRY  %s" % car.def.display_name,
		"rpm %.0f  gear %d  throttle %.2f  brake %.2f  steer %.2f" % [car.rpm, car.gear, car.in_throttle, car.in_brake, car.in_steer],
		"speed %.1f m/s  drift %.1f deg  max slip %.2f  air %.2fs" % [car.speed, car.drift_angle, car.max_slip, car.air_time],
		"grip(weather) %.2f  wet %.2f  surface %s" % [car.weather_grip, Game.sky.wet if Game.sky else 0.0, WorldData.SURFACE_NAMES[car.surface_now]],
	]
	for w in car.wheels:
		lines.append("%s  load %5.0f N  slip %.2f  lat %.2f  %s%s  %s" % [w.key, w.load, w.slip, w.slip_lat, "LOCK " if w.locked else "", "SPIN " if w.spinning else "", WorldData.SURFACE_NAMES[w.surface]])
	draw_rect(Rect2(p - Vector2(8, 22) * s, Vector2(560, 22 * lines.size() + 14) * s), BG)
	for i in lines.size():
		draw_string(font, p + Vector2(0, i * 22) * s, lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, int(15 * s), Color(0.85, 1.0, 0.9))
