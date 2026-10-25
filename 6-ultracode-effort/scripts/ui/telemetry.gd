extends Control
## Telemetry overlay (toggle_telemetry / F4, Settings "show_telemetry"): engine, driver inputs, assist
## flags, g-g diagram, body slip, and per-wheel load / slip ratio / slip angle / skid / surface.
## Redrawn at 20 Hz.

const Style := preload("res://scripts/ui/ui_style.gd")

const W := 476.0
const H := 584.0
const RATE := 0.05
## Minimum space between the texts of a wheel card's bottom row.
const ROW_GAP := 8.0

var _timer: float = 0.0
var _trail: Array[Vector2] = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	position = Vector2(22, 124)
	size = Vector2(W, H)


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = RATE
	var car := Game.player_car
	if car != null and is_instance_valid(car):
		_trail.append(Vector2(car.lateral_g, car.longitudinal_g))
		if _trail.size() > 40:
			_trail.remove_at(0)
	queue_redraw()


func _bar(rect: Rect2, v: float, col: Color, centered := false) -> void:
	Style.draw_round_rect(self, rect, Color(1, 1, 1, 0.08), 4)
	if centered:
		var mid := rect.position.x + rect.size.x * 0.5
		var w := rect.size.x * 0.5 * clampf(v, -1.0, 1.0)
		draw_rect(Rect2(Vector2(minf(mid, mid + w), rect.position.y), Vector2(absf(w), rect.size.y)), col)
		draw_line(Vector2(mid, rect.position.y - 2), Vector2(mid, rect.end.y + 2), Color(1, 1, 1, 0.5), 1.0)
	elif v > 0.0:
		Style.draw_round_rect(self, Rect2(rect.position, Vector2(rect.size.x * clampf(v, 0.0, 1.0), rect.size.y)), col, 4)


func _t(text: String, pos: Vector2, size_px := 16, col := Style.TEXT, weight := 500, align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0) -> void:
	Style.draw_text(self, text, pos, size_px, col, align, width, weight, false, 0, 0.0)


func _pill(text: String, pos: Vector2, on: bool, col: Color) -> float:
	var w := Style.text_width(text, 13, 700, false, 1) + 16.0
	var r := Rect2(pos, Vector2(w, 22))
	if on:
		Style.draw_round_rect(self, r, col, 6)
	else:
		Style.draw_round_rect(self, r, Color(0, 0, 0, 0.2), 6, 1, Color(1, 1, 1, 0.15))
	Style.draw_text(self, text, r.position + Vector2(0, 16), 13, Style.INK if on else Style.TEXT_FAINT, HORIZONTAL_ALIGNMENT_CENTER, w, 700, false, 1, 0.0)
	return w + 6.0


func _draw() -> void:
	var car := Game.player_car
	if car == null or not is_instance_valid(car) or car.data == null:
		return
	var d := car.data
	Style.draw_round_rect(self, Rect2(Vector2.ZERO, size), Style.BG_STRONG, 14, 1, Style.LINE)
	Style.draw_text(self, "TELEMETRY", Vector2(18, 32), 16, Style.ACCENT, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 700, false, 4, 0.0)
	_t(d.display_name, Vector2(W - 18 - 260, 32), 16, Style.TEXT_DIM, 600, HORIZONTAL_ALIGNMENT_RIGHT, 260.0)
	# Engine.
	var gtxt := "R" if car.gear < 0 else ("N" if car.gear == 0 else str(car.gear))
	Style.draw_text(self, "%d" % int(car.rpm), Vector2(18, 72), 32, Style.TEXT, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 700, true, 0, 0.0)
	_t("rpm", Vector2(18 + Style.text_width("%d" % int(car.rpm), 32, 700, true) + 6, 72), 15, Style.TEXT_FAINT)
	_t("gear %s%s" % [gtxt, "  (shift)" if car.shifting else ""], Vector2(190, 70), 18, Style.TEXT, 600)
	_t("%d %s" % [int(Style.speed_value(car.get_speed_kmh())), Style.speed_unit().to_lower()], Vector2(W - 18 - 140, 70), 18, Style.TEXT, 600, HORIZONTAL_ALIGNMENT_RIGHT, 140.0)
	var rb := Rect2(Vector2(18, 82), Vector2(W - 36, 10))
	_bar(rb, car.rpm / d.max_rpm, Style.accent_at(car.rpm / d.max_rpm))
	var rx := rb.position.x + rb.size.x * d.redline_rpm / d.max_rpm
	draw_line(Vector2(rx, rb.position.y - 3), Vector2(rx, rb.end.y + 3), Style.BAD, 2.0)
	# Inputs.
	var y := 106.0
	var rows := [["Throttle", car.in_throttle, Style.GOOD], ["Applied", car.throttle_applied, Color(0.3, 0.7, 0.45)],
		["Brake", car.in_brake, Style.BAD], ["Handbrake", car.in_handbrake, Style.ACCENT]]
	for row: Array in rows:
		_t(String(row[0]), Vector2(18, y + 12), 15, Style.TEXT_DIM)
		_bar(Rect2(Vector2(120, y), Vector2(W - 200, 14)), float(row[1]), row[2])
		_t("%d%%" % int(float(row[1]) * 100.0), Vector2(W - 70, y + 13), 15, Style.TEXT, 600, HORIZONTAL_ALIGNMENT_RIGHT, 52.0)
		y += 21.0
	_t("Steer", Vector2(18, y + 12), 15, Style.TEXT_DIM)
	_bar(Rect2(Vector2(120, y), Vector2(W - 200, 14)), car.in_steer, Style.SKY, true)
	_t("%+.1f°" % rad_to_deg(car.steer_angle), Vector2(W - 70, y + 13), 15, Style.TEXT, 600, HORIZONTAL_ALIGNMENT_RIGHT, 52.0)
	y += 26.0
	var px := 18.0
	px += _pill("TCS", Vector2(px, y), car.tcs_active, Style.ACCENT)
	px += _pill("ABS", Vector2(px, y), car.abs_active, Style.ACCENT)
	px += _pill("STM", Vector2(px, y), car.stm_active, Style.ACCENT)
	px += _pill("LIMITER", Vector2(px, y), car.limiter_hit, Style.ACCENT_2)
	px += _pill("AIR", Vector2(px, y), car.wheels_on_ground == 0, Style.SKY)
	px += _pill("AUTO" if car.auto_gearbox else "MANUAL", Vector2(px, y), true, Color(0.6, 0.62, 0.7))
	# g-g diagram.
	y += 32.0
	var gc := Vector2(76, y + 56)
	var gr := 54.0
	draw_circle(gc, gr, Color(0, 0, 0, 0.25), true, -1.0, true)
	for k: float in [0.5, 1.0]:
		draw_arc(gc, gr * k / 1.2, 0.0, TAU, 40, Color(1, 1, 1, 0.14), 1.0, true)
	draw_line(gc - Vector2(gr, 0), gc + Vector2(gr, 0), Color(1, 1, 1, 0.12), 1.0)
	draw_line(gc - Vector2(0, gr), gc + Vector2(0, gr), Color(1, 1, 1, 0.12), 1.0)
	for i in _trail.size():
		var g := _trail[i]
		var p := gc + Vector2(clampf(g.x, -1.3, 1.3), clampf(-g.y, -1.3, 1.3)) * gr / 1.2
		draw_circle(p, 2.0, Color(Style.ACCENT, float(i) / _trail.size() * 0.6), true, -1.0, true)
	var gnow := gc + Vector2(clampf(car.lateral_g, -1.3, 1.3), clampf(-car.longitudinal_g, -1.3, 1.3)) * gr / 1.2
	draw_circle(gnow, 5.0, Style.ACCENT_2, true, -1.0, true)
	_t("1.0g", gc + Vector2(gr / 1.2 - 14, -4), 11, Style.TEXT_FAINT)
	var dx := 170.0
	var dyn := [["Lateral", "%+.2f g" % car.lateral_g], ["Longitudinal", "%+.2f g" % car.longitudinal_g],
		["Body slip", "%+.1f°" % car.body_slip_deg], ["Wheels down", "%d / %d" % [car.wheels_on_ground, car.wheels.size()]],
		["Air time", "%.2f s" % car.air_time], ["Damage", "%d%%" % int(car.damage * 100.0)]]
	var dy := y + 6.0
	for row2: Array in dyn:
		_t(String(row2[0]), Vector2(dx, dy + 6), 15, Style.TEXT_DIM)
		_t(String(row2[1]), Vector2(W - 18 - 120, dy + 6), 16, Style.TEXT, 600, HORIZONTAL_ALIGNMENT_RIGHT, 120.0)
		dy += 19.0
	# Wheels.
	y += 122.0
	var bw := (W - 36 - 8) * 0.5
	var bh := 96.0
	for wi in car.wheels.size():
		var w: CarController.Wheel = car.wheels[wi]
		var col_i := 0 if w.left else 1
		var row_i := 0 if w.front else 1
		var box := Rect2(Vector2(18 + col_i * (bw + 8), y + row_i * (bh + 8)), Vector2(bw, bh))
		Style.draw_round_rect(self, box, Color(0, 0, 0, 0.22), 10, 1, Color(1, 1, 1, 0.08))
		var bp := box.position
		Style.draw_text(self, w.id.right(2), bp + Vector2(12, 24), 18, Style.ACCENT, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 700, false, 1, 0.0)
		draw_circle(bp + Vector2(48, 17), 4.5, Style.GOOD if w.contact else Color(1, 1, 1, 0.2), true, -1.0, true)
		var sname := w.surface.display_name if (w.surface != null and w.contact) else "-"
		_t(sname, bp + Vector2(60, 23), 14, Style.TEXT_DIM, 500, HORIZONTAL_ALIGNMENT_RIGHT, bw - 72.0)
		var load_k := w.load / maxf(w.static_load, 1.0)
		_t("Load", bp + Vector2(12, 49), 14, Style.TEXT_FAINT)
		_bar(Rect2(bp + Vector2(56, 38), Vector2(bw - 132, 12)), load_k / 2.5, Style.SKY)
		_t("%.1f kN" % (w.load / 1000.0), bp + Vector2(bw - 72, 49), 14, Style.TEXT, 600, HORIZONTAL_ALIGNMENT_RIGHT, 60.0)
		_t("Skid", bp + Vector2(12, 69), 14, Style.TEXT_FAINT)
		_bar(Rect2(bp + Vector2(56, 58), Vector2(bw - 132, 12)), w.skid, Style.ACCENT_2)
		_t("%d%%" % int(w.skid * 100.0), bp + Vector2(bw - 72, 69), 14, Style.TEXT, 600, HORIZONTAL_ALIGNMENT_RIGHT, 60.0)
		_wheel_row(bp, bw, "SR %+.2f" % w.slip_long, "SA %+.1f°" % rad_to_deg(w.slip_angle), "%d rad/s" % int(w.omega))


## Bottom row of a wheel card: slip ratio left, wheel speed right-aligned, slip angle at its usual column
## but kept >= ROW_GAP px from both neighbours (see wheel_row_layout), so 3-digit speeds and 2-digit
## angles never touch.
func _wheel_row(bp: Vector2, bw: float, sr: String, sa: String, om: String) -> void:
	var l := wheel_row_layout(bw, sr, sa, om)
	_t(sr, bp + Vector2(l["x_sr"], 88), l["fs"], Style.TEXT)
	_t(sa, bp + Vector2(l["x_sa"], 88), l["fs"], Style.TEXT)
	_t(om, bp + Vector2(l["x_om"], 88), l["fo"], Style.TEXT_FAINT)


## Measured layout of the wheel row (font sizes and x of each text inside a card bw wide); the font steps
## down only if the three texts cannot fit with ROW_GAP between them at all.
static func wheel_row_layout(bw: float, sr: String, sa: String, om: String) -> Dictionary:
	var fs := 15
	var fo := 13
	var x0 := 12.0
	var x1 := bw - 12.0
	var w_sr := 0.0
	var w_sa := 0.0
	var w_om := 0.0
	while true:
		w_sr = Style.text_width(sr, fs, 500)
		w_sa = Style.text_width(sa, fs, 500)
		w_om = Style.text_width(om, fo, 500)
		if x1 - x0 - w_sr - w_sa - w_om >= ROW_GAP * 2.0 or fs <= 11:
			break
		fs -= 1
		fo = mini(fo, fs - 1)
	var x_sa := maxf(minf(bw * 0.5 - 10.0, x1 - w_om - ROW_GAP - w_sa), x0 + w_sr + ROW_GAP)
	return {"fs": fs, "fo": fo, "x_sr": x0, "x_sa": x_sa, "x_om": x1 - w_om, "w_sr": w_sr, "w_sa": w_sa, "w_om": w_om}
