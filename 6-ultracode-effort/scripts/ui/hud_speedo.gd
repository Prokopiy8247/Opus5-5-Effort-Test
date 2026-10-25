extends Control
## Bottom-right instrument cluster: analog tachometer arc (redline from car data, start-up sweep),
## big digital speed with dimmed leading zeros, gear badge (flashes on the limiter / manual shift point),
## TCS / STM / ABS intervention lamps, surface name and a damage meter.
## Split into layers that redraw only when their own state changes (static dial face once per car).

const Style := preload("res://scripts/ui/ui_style.gd")

const W := 400.0
const H := 432.0
const R := 172.0
const A0 := 0.75 * PI
const SWEEP := 1.5 * PI
const SWEEP_TIME := 1.3
## Assist lamp row inside the numeral ring (numerals sit at radius R - 68, so even the ones on the
## 225 / 315 degree diagonals of a 6000 or 9000 rpm dial stay clear), above the speed digits.
const LAMP_SIZE := Vector2(44, 18)
const LAMP_DX := 50.0
const LAMP_Y := -49.0
const DIGITS_Y := 36.0

var _car: CarController
var _rpm: float = 0.0
var _speed: float = 0.0
var _sweep: float = 0.0
var _limiter: float = 0.0
var _lamps := PackedFloat32Array([0.0, 0.0, 0.0])
var _t: float = 0.0

var _static: Control
var _dial: Control
var _digits: Control
var _gear: Control
var _lamp_layer: Control
var _strip: Control
var _static_key: String = ""
var _rpm_drawn: float = -1.0
var _digits_v: int = -1
var _gear_key: String = ""
var _lamps_key: int = -1
var _strip_key: String = ""


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	anchor_left = 1.0
	anchor_right = 1.0
	anchor_top = 1.0
	anchor_bottom = 1.0
	offset_left = -W - 26.0
	offset_right = -26.0
	offset_top = -H - 12.0
	offset_bottom = -12.0
	_static = _layer(_draw_static)
	_dial = _layer(_draw_dial)
	_lamp_layer = _layer(_draw_lamps)
	_digits = _layer(_draw_digits)
	_gear = _layer(_draw_gear)
	_strip = _layer(_draw_strip)
	Game.car_spawned.connect(func(_c: CarController) -> void: _sweep = SWEEP_TIME)
	Settings.changed.connect(_on_setting)


func _on_setting(key: String, _value: Variant) -> void:
	if key == "units_mph":
		_static_key = ""
		_digits_v = -1


func _layer(fn: Callable) -> Control:
	var c := Control.new()
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.size = Vector2(W, H)
	c.draw.connect(fn)
	add_child(c)
	return c


func _center() -> Vector2:
	return Vector2(W * 0.5, R + 8.0)


func _process(delta: float) -> void:
	_t += delta
	var car := Game.player_car if Game.player_car != null and is_instance_valid(Game.player_car) else null
	if car != _car:
		_car = car
		_static_key = ""
	if _car == null or _car.data == null:
		return
	var target := _car.rpm
	if _sweep > 0.0:
		_sweep = maxf(_sweep - delta, 0.0)
		var k := 1.0 - _sweep / SWEEP_TIME
		target = _max_disp() * sin(k * PI) * 0.98 + _car.rpm * k
	_rpm = lerpf(_rpm, target, clampf(delta * (30.0 if _sweep > 0.0 else 16.0), 0.0, 1.0))
	_speed = lerpf(_speed, absf(_car.get_speed_kmh()), clampf(delta * 12.0, 0.0, 1.0))
	if _car.limiter_hit:
		_limiter = 0.22
	_limiter = maxf(_limiter - delta, 0.0)
	var act := [_car.tcs_active, _car.stm_active, _car.abs_active]
	for i in 3:
		_lamps[i] = 0.25 if act[i] else maxf(_lamps[i] - delta, 0.0)
	# Redraw each layer only when what it shows changed.
	var skey := "%d|%d|%s|%s" % [int(_max_disp()), int(_car.data.redline_rpm), Style.speed_unit(), _car.data.id]
	if skey != _static_key:
		_static_key = skey
		for l: Control in [_static, _dial, _lamp_layer, _digits, _gear, _strip]:
			l.queue_redraw()
	if absf(_rpm - _rpm_drawn) > 3.0:
		_rpm_drawn = _rpm
		_dial.queue_redraw()
	var v := int(round(Style.speed_value(_speed)))
	if v != _digits_v:
		_digits_v = v
		_digits.queue_redraw()
	var flash := _limiter > 0.0 and fmod(_t, 0.12) < 0.07
	var hint := _shift_hint() and fmod(_t, 0.2) < 0.1
	var gkey := "%s|%d|%d" % [_gear_text(), 1 if flash else 0, 1 if hint else 0]
	if gkey != _gear_key:
		_gear_key = gkey
		_gear.queue_redraw()
	var bits := 0
	var en := [_car.assist_tcs, _car.assist_stm, _car.assist_abs]
	for i in 3:
		bits |= (1 << i) if _lamps[i] > 0.0 else 0
		bits |= (8 << i) if en[i] else 0
	if bits != _lamps_key:
		_lamps_key = bits
		_lamp_layer.queue_redraw()
	var surf := _car.dominant_surface()
	var stkey := "%s|%d" % [surf.display_name if surf != null else "", int(clampf(_car.damage, 0.0, 1.0) * 40.0)]
	if stkey != _strip_key:
		_strip_key = stkey
		_strip.queue_redraw()


func _gear_text() -> String:
	var g := _car.gear
	return "R" if g < 0 else ("N" if g == 0 else str(g))


func _shift_hint() -> bool:
	return not _car.auto_gearbox and _car.gear >= 1 and _car.rpm > _car.data.redline_rpm * 0.95 and _car.gear < _car.data.gear_ratios.size()


func _max_disp() -> float:
	return ceilf(maxf(_car.data.max_rpm, _car.data.redline_rpm + 300.0) / 1000.0) * 1000.0


func _angle(rpm: float) -> float:
	return A0 + clampf(rpm / _max_disp(), 0.0, 1.0) * SWEEP


func _draw_static() -> void:
	if _car == null or _car.data == null:
		return
	var ci := _static
	var c := _center()
	var ra := R - 26.0
	var data := _car.data
	ci.draw_circle(c + Vector2(0, 6), R + 4.0, Color(0, 0, 0, 0.22), true, -1.0, true)
	ci.draw_circle(c, R, Style.BG, true, -1.0, true)
	ci.draw_circle(c, R - 64.0, Color(0, 0, 0, 0.22), true, -1.0, true)
	ci.draw_arc(c, R - 1.0, 0.0, TAU, 96, Color(1, 1, 1, 0.08), 2.0, true)
	var a_red := _angle(data.redline_rpm)
	var a_end := A0 + SWEEP
	ci.draw_arc(c, ra, A0, a_end, 72, Color(1, 1, 1, 0.1), 13.0, true)
	ci.draw_arc(c, ra, a_red, a_end, 24, Color(Style.BAD, 0.28), 13.0, true)
	ci.draw_arc(c, ra + 11.0, a_red, a_end, 24, Style.BAD, 4.0, true)
	var maxd := _max_disp()
	var rpm_i := 0.0
	while rpm_i <= maxd + 1.0:
		var a := _angle(rpm_i)
		var dir := Vector2(cos(a), sin(a))
		var major := is_zero_approx(fmod(rpm_i, 1000.0))
		var in_red := rpm_i >= data.redline_rpm - 1.0
		var tc := Style.BAD if in_red else Color(1, 1, 1, 0.85 if major else 0.4)
		ci.draw_line(c + dir * (ra - 12.0), c + dir * (ra - (26.0 if major else 19.0)), tc, 3.0 if major else 1.6, true)
		if major:
			var tp := c + dir * (ra - 42.0)
			Style.draw_text(ci, str(int(rpm_i / 1000.0)), tp + Vector2(-20, 8), 21, Style.BAD if in_red else Style.TEXT_DIM,
				HORIZONTAL_ALIGNMENT_CENTER, 40.0, 600, true, 0, 0.0)
		rpm_i += 500.0
	Style.draw_text(ci, "RPM x1000", c + Vector2(-R * 0.86, R * 0.86), 13, Style.TEXT_DIM, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 600, false, 1, 0.8)
	Style.draw_text(ci, Style.speed_unit(), c + Vector2(-60, DIGITS_Y + 28.0), 17, Style.ACCENT, HORIZONTAL_ALIGNMENT_CENTER, 120.0, 700, false, 3, 0.0)
	var gr := _gear_rect()
	Style.draw_text(ci, "GEAR", gr.position + Vector2(0, -6), 12, Style.TEXT_FAINT, HORIZONTAL_ALIGNMENT_CENTER, gr.size.x, 600, false, 2, 0.0)
	var strip := _strip_rect()
	Style.draw_round_rect(ci, strip, Style.BG, 12, 1, Style.LINE)
	Style.draw_text(ci, "DMG", strip.position + Vector2(196, 25), 14, Style.TEXT_FAINT, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 600, false, 1, 0.0)


func _draw_dial() -> void:
	if _car == null or _car.data == null:
		return
	var ci := _dial
	var c := _center()
	var ra := R - 26.0
	var a_red := _angle(_car.data.redline_rpm)
	var a_now := _angle(_rpm)
	if a_now > A0 + 0.01:
		var n := maxi(int((a_now - A0) / SWEEP * 64.0), 2)
		var pts := PackedVector2Array()
		var cols := PackedColorArray()
		for i in n + 1:
			var a := lerpf(A0, a_now, float(i) / n)
			pts.append(c + Vector2(cos(a), sin(a)) * ra)
			cols.append(Style.accent_at((a - A0) / SWEEP * 1.15) if a < a_red else Style.BAD.lightened(0.1))
		ci.draw_polyline_colors(pts, cols, 13.0, true)
	var nd := Vector2(cos(a_now), sin(a_now))
	ci.draw_line(c + nd * (ra - 60.0), c + nd * (ra + 12.0), Color(Style.ACCENT, 0.35), 12.0, true)
	ci.draw_line(c + nd * (ra - 60.0), c + nd * (ra + 12.0), Color(1, 1, 1), 4.5, true)
	ci.draw_circle(c + nd * (ra - 60.0), 4.0, Style.ACCENT, true, -1.0, true)


func _draw_lamps() -> void:
	if _car == null:
		return
	var ci := _lamp_layer
	var c := _center()
	var names: Array[String] = ["TCS", "STM", "ABS"]
	var enabled: Array[bool] = [_car.assist_tcs, _car.assist_stm, _car.assist_abs]
	for i in 3:
		var lc := c + Vector2((i - 1) * LAMP_DX, LAMP_Y)
		var rect := Rect2(lc - LAMP_SIZE * 0.5, LAMP_SIZE)
		var lit := _lamps[i] > 0.0
		if lit:
			Style.draw_round_rect(ci, rect.grow(2.0), Color(Style.ACCENT, 0.3), 8)
			Style.draw_round_rect(ci, rect, Style.ACCENT, 6)
		else:
			Style.draw_round_rect(ci, rect, Color(0, 0, 0, 0.25), 6, 1, Color(1, 1, 1, 0.22 if enabled[i] else 0.07))
		var tcol := Style.INK if lit else (Style.TEXT_DIM if enabled[i] else Color(1, 1, 1, 0.18))
		Style.draw_text(ci, names[i], rect.position + Vector2(0, 14.0), 14, tcol, HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, 700, false, 1, 0.0)


func _draw_digits() -> void:
	if _car == null:
		return
	var ci := _digits
	var c := _center()
	var v := maxi(_digits_v, 0)
	var full := ("%03d" % v) if v < 1000 else str(v)
	var lead := 0
	while lead < full.length() - 1 and full[lead] == "0":
		lead += 1
	var fs := 100
	var x0 := c.x - Style.text_width(full, fs, 700, true) * 0.5
	var base_y := c.y + DIGITS_Y
	if lead > 0:
		Style.draw_text(ci, full.substr(0, lead), Vector2(x0, base_y), fs, Color(1, 1, 1, 0.09), HORIZONTAL_ALIGNMENT_LEFT, -1.0, 700, true, 0, 0.0)
	Style.draw_text(ci, full.substr(lead), Vector2(x0 + Style.text_width(full.substr(0, lead), fs, 700, true), base_y), fs, Style.TEXT,
		HORIZONTAL_ALIGNMENT_LEFT, -1.0, 700, true, 0, 0.45)


func _gear_rect() -> Rect2:
	return Rect2(_center() + Vector2(-33, R - 84.0), Vector2(66, 60))


func _draw_gear() -> void:
	if _car == null:
		return
	var parts := _gear_key.split("|")
	var flash := parts.size() > 1 and parts[1] == "1"
	var hint := parts.size() > 2 and parts[2] == "1"
	var gr := _gear_rect()
	var gbg := Style.ACCENT_2 if flash else Color(0.04, 0.045, 0.08, 0.95)
	Style.draw_round_rect(_gear, gr, gbg, 12, 2, Style.ACCENT_2 if hint else Color(1, 1, 1, 0.16))
	Style.draw_text(_gear, _gear_text(), gr.position + Vector2(0, 47), 46, Style.TEXT, HORIZONTAL_ALIGNMENT_CENTER, gr.size.x, 700, true, 0, 0.3)


func _strip_rect() -> Rect2:
	var c := _center()
	return Rect2(Vector2(c.x - 160.0, c.y + R + 14.0), Vector2(320, 36))


func _draw_strip() -> void:
	if _car == null:
		return
	var ci := _strip
	var strip := _strip_rect()
	var surf := _car.dominant_surface()
	var sname := "AIRBORNE"
	var scol := Style.SKY
	if surf != null:
		sname = surf.display_name.to_upper()
		scol = Color(surf.particle_color, 1.0).lightened(0.25)
	ci.draw_circle(strip.position + Vector2(20, 18), 6.0, scol, true, -1.0, true)
	Style.draw_text(ci, sname, strip.position + Vector2(34, 25), 17, Style.TEXT, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 600, false, 1, 0.0)
	var dmg := clampf(_car.damage, 0.0, 1.0)
	var dc := Style.GOOD.lerp(Style.ACCENT, clampf(dmg * 2.0, 0.0, 1.0)).lerp(Style.BAD, clampf(dmg * 2.0 - 1.0, 0.0, 1.0))
	for i in 5:
		var seg := Rect2(strip.position + Vector2(236 + i * 15, 11), Vector2(12, 14))
		var fill := clampf(dmg * 5.0 - i, 0.0, 1.0)
		ci.draw_rect(seg, Color(1, 1, 1, 0.1))
		if fill > 0.0:
			ci.draw_rect(Rect2(seg.position, Vector2(seg.size.x * fill, seg.size.y)), dc)
