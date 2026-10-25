extends Control
## Activity HUD (Game.activity_update / activity_finished contract): live panel top-centre that hides
## 1.5 s after the last update, a result banner on finish, and a camera flash + viewfinder frame when a
## speed trap completes.

signal banner_started()

const Style := preload("res://scripts/ui/ui_style.gd")
const Icons := preload("res://scripts/ui/hud_icons.gd")

const PANEL_W := 640.0
const PANEL_H := 118.0
const MAX_W := 980.0
const HIDE_AFTER := 1.5
const BANNER_IN := 0.35
const BANNER_HOLD := 4.0
const BANNER_OUT := 0.5
const FLASH_TIME := 0.55

var _info: Dictionary = {}
var _since: float = 99.0
var _alpha: float = 0.0
var _kinds: Dictionary = {}
var _result: Dictionary = {}
var _result_kind: String = ""
## Race finishing place / field size of the shown result ((0, 0) for other events).
var _place := Vector2i.ZERO
var _rt: float = -1.0
var _flash: float = 0.0
var _t: float = 0.0
var _flash_layer: Control
var _panel_w: float = 0.0
var _dirty: bool = true
var _alpha_drawn: float = -1.0
var _banner_was: bool = false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# The flash sits above every other HUD element.
	_flash_layer = Control.new()
	_flash_layer.name = "Flash"
	_flash_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash_layer.z_index = 100
	add_child(_flash_layer)
	_flash_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_flash_layer.draw.connect(_draw_flash)
	Game.activity_update.connect(_on_update)
	Game.activity_finished.connect(_on_finished)


func _on_update(info: Dictionary) -> void:
	# The benchmark drives through event gates on autopilot: keep its banner area clear.
	if Game.benchmark_mode:
		return
	if info != _info:
		_dirty = true
	_info = info
	_since = 0.0
	if info.has("id"):
		_kinds[String(info["id"])] = String(info.get("kind", ""))


func _on_finished(activity_id: String, result: Dictionary) -> void:
	if Game.benchmark_mode:
		return
	_result = result
	_result_kind = String(result.get("kind", _kinds.get(activity_id, "")))
	_place = _race_place(result, _result_kind)
	_dirty = true
	_rt = 0.0
	_since = maxf(_since, HIDE_AFTER)
	banner_started.emit()
	if _result_kind == "speed_trap":
		flash()


func flash() -> void:
	_flash = FLASH_TIME


## True while the result banner is on screen (the region popup waits for it).
func banner_visible() -> bool:
	return _rt >= 0.0


func _process(delta: float) -> void:
	_t += delta
	_since += delta
	var want := 1.0 if _since < HIDE_AFTER else 0.0
	_alpha = move_toward(_alpha, want, delta * (6.0 if want > _alpha else 3.0))
	if _alpha <= 0.0:
		_panel_w = 0.0
	if _rt >= 0.0:
		_rt += delta
		if _rt > BANNER_IN + BANNER_HOLD + BANNER_OUT:
			_rt = -1.0
	if _flash > 0.0:
		_flash = maxf(_flash - delta, 0.0)
		_flash_layer.queue_redraw()
	var banner := _rt >= 0.0
	if _dirty or banner or _banner_was or absf(_alpha - _alpha_drawn) > 0.001:
		_dirty = false
		_alpha_drawn = _alpha
		queue_redraw()
	_banner_was = banner


func _draw() -> void:
	if _alpha > 0.0 and not _info.is_empty():
		_draw_panel()
	if _rt >= 0.0:
		_draw_banner()


func _draw_panel() -> void:
	var a := _alpha
	var title := String(_info.get("title", "")).to_upper()
	var primary := String(_info.get("primary", ""))
	var sec := String(_info.get("secondary", ""))
	var pw := Style.text_width(primary, 48, 700, true)
	var sw := Style.text_width(sec, 20, 500) if sec != "" else 0.0
	var tw := Style.text_width(title, 18, 700, false, 2)
	var inner := maxf(pw + (sw + 32.0 if sec != "" else 0.0), tw)
	var two_rows := sec != "" and 124.0 + inner + 24.0 > MAX_W
	if two_rows:
		inner = maxf(maxf(pw, sw), tw)
	var want_w := clampf(124.0 + inner + 24.0, PANEL_W, MAX_W)
	_panel_w = want_w if (_panel_w <= 0.0 or want_w > _panel_w) else lerpf(_panel_w, want_w, 0.05)
	var w := _panel_w
	var h := PANEL_H + (28.0 if two_rows else 0.0)
	var x := (size.x - w) * 0.5
	var y := 20.0 - (1.0 - a) * 16.0
	var rect := Rect2(Vector2(x, y), Vector2(w, h))
	Style.draw_round_rect(self, rect, Color(0.035, 0.04, 0.075, 0.82 * a), 18, 1, Color(1, 1, 1, 0.08 * a))
	var top := PackedVector2Array([rect.position + Vector2(18, 1.5), rect.position + Vector2(w * 0.5, 1.5), rect.position + Vector2(w - 18, 1.5)])
	draw_polyline_colors(top, PackedColorArray([Color(Style.ACCENT, a), Color(Style.ACCENT_2, a), Color(Style.ACCENT, a)]), 3.0, true)
	var kind := String(_info.get("kind", ""))
	Icons.draw_badge(self, kind, rect.position + Vector2(56, h * 0.5), 30.0, a)
	var tx := x + 102.0
	Style.draw_text(self, title, Vector2(tx, y + 34.0), 18, Color(Style.ACCENT, a), HORIZONTAL_ALIGNMENT_LEFT, w - 124.0, 700, false, 2, 0.0)
	Style.draw_text(self, primary, Vector2(tx, y + 84.0), 48, Color(1, 1, 1, a), HORIZONTAL_ALIGNMENT_LEFT, -1.0, 700, true, 0, 0.5)
	if sec != "":
		if two_rows:
			Style.draw_text(self, sec, Vector2(tx, y + 112.0), 20, Color(Style.TEXT_DIM, a), HORIZONTAL_ALIGNMENT_LEFT, w - 124.0, 500, false, 0, 0.0)
		else:
			Style.draw_text(self, sec, Vector2(tx, y + 82.0), 20, Color(Style.TEXT_DIM, a), HORIZONTAL_ALIGNMENT_RIGHT, w - 124.0, 500, false, 0, 0.0)
	var p := float(_info.get("progress", -1.0))
	if p >= 0.0:
		var bar := Rect2(Vector2(tx, y + h - 20.0), Vector2(w - 124.0, 6.0))
		Style.draw_round_rect(self, bar, Color(1, 1, 1, 0.1 * a), 3)
		if p > 0.0:
			var fill := Rect2(bar.position, Vector2(maxf(bar.size.x * clampf(p, 0.0, 1.0), 6.0), bar.size.y))
			Style.draw_round_rect(self, fill, Color(Style.accent_at(p), a), 3)


func _medal_color(m: String) -> Color:
	var l := m.to_lower()
	if l.contains("gold") or l.contains("3"):
		return Style.GOLD
	if l.contains("silver") or l.contains("2"):
		return Color(0.82, 0.86, 0.92)
	if l.contains("bronze") or l.contains("1"):
		return Color(0.88, 0.58, 0.32)
	if l.contains("plat") or l.contains("diamond"):
		return Style.SKY
	return Style.ACCENT


func _draw_banner() -> void:
	var k_in := clampf(_rt / BANNER_IN, 0.0, 1.0)
	var e := 1.0 - pow(1.0 - k_in, 3.0)
	var k_out := clampf((_rt - BANNER_IN - BANNER_HOLD) / BANNER_OUT, 0.0, 1.0)
	var a := e * (1.0 - k_out)
	var w := 1040.0 * (0.85 + 0.15 * e)
	var h := 178.0
	var c := Vector2(size.x * 0.5, 330.0)
	var rect := Rect2(c - Vector2(w, h) * 0.5, Vector2(w, h))
	# Skewed festival stripes behind the panel.
	var sk := 40.0
	var stripe := PackedVector2Array([rect.position + Vector2(-30 + sk, -10), rect.position + Vector2(w + 30 + sk, -10),
		rect.position + Vector2(w + 30 - sk, h + 10), rect.position + Vector2(-30 - sk, h + 10)])
	draw_colored_polygon(stripe, Color(Style.ACCENT_2, 0.22 * a))
	Style.draw_round_rect(self, rect, Color(0.03, 0.035, 0.065, 0.9 * a), 20, 2, Color(Style.ACCENT, 0.55 * a))
	var kind_name := Icons.name_for(_result_kind).to_upper() if _result_kind != "" else "EVENT"
	Style.draw_text(self, kind_name + " COMPLETE", Vector2(rect.position.x, rect.position.y + 36.0), 18, Color(Style.ACCENT, a),
		HORIZONTAL_ALIGNMENT_CENTER, w, 700, false, 4, 0.0)
	var place := _place
	var sub := banner_subtitle(_result, place)
	var sub_size := 26
	while sub_size > 18 and Style.text_width(sub, sub_size, 600) > w - 80.0:
		sub_size -= 2
	Style.draw_text(self, sub, Vector2(rect.position.x, rect.position.y + 68.0), sub_size, Color(Style.TEXT_DIM, a),
		HORIZONTAL_ALIGNMENT_CENTER, w, 600, false, 0, 0.0)
	Style.draw_text(self, String(_result.get("score_text", "")), Vector2(rect.position.x, rect.position.y + 142.0), 74, Color(1, 1, 1, a),
		HORIZONTAL_ALIGNMENT_CENTER, w, 700, true, 0, 0.5)
	# [text, colour, filled]
	var badges: Array = []
	var medal := String(_result.get("medal", ""))
	if place.x > 0:
		# The place badge carries the race medal colour (1st gold .. 3rd bronze, plain grey below).
		var pc := _medal_color(["", "Gold", "Silver", "Bronze"][place.x]) if place.x <= 3 else Color(0.62, 0.65, 0.72)
		badges.append([_place_text(place), pc, true])
	elif medal != "":
		badges.append([medal.to_upper(), _medal_color(medal), true])
	if bool(_result.get("personal_best", false)):
		# A best time in a race that was not won is noted, not celebrated.
		badges.append(["NEW PERSONAL BEST" if place.x <= 1 else "PERSONAL BEST TIME", Style.ACCENT_2, place.x <= 1])
	var bx := c.x
	var widths: Array[float] = []
	var total := 0.0
	for b: Array in badges:
		var bw := Style.text_width(String(b[0]), 18, 700, false, 2) + 36.0
		widths.append(bw)
		total += bw + 12.0
	bx -= (total - 12.0) * 0.5
	for i in badges.size():
		var br := Rect2(Vector2(bx, rect.end.y - 18.0), Vector2(widths[i], 36.0))
		var bc: Color = badges[i][1]
		var filled: bool = badges[i][2]
		if filled:
			Style.draw_round_rect(self, br, Color(bc, a), 18)
		else:
			Style.draw_round_rect(self, br, Color(0.03, 0.035, 0.065, 0.95 * a), 18, 2, Color(bc, a))
		Style.draw_text(self, String(badges[i][0]), br.position + Vector2(0, 25), 18, Color(Style.INK if filled else bc, a), HORIZONTAL_ALIGNMENT_CENTER,
			br.size.x, 700, false, 2, 0.0)
		bx += widths[i] + 12.0


## Title line of the banner: the event title, plus the detail (e.g. the festival flag's name) unless the
## detail is the race position, which gets its own badge.
static func banner_subtitle(result: Dictionary, place: Vector2i) -> String:
	var sub := String(result.get("title", ""))
	var detail := String(result.get("detail", ""))
	if detail != "" and place.x == 0 and detail != sub:
		sub = detail if sub == "" else "%s  ·  %s" % [sub, detail]
	return sub


## Race result position as (place, field size), (0, 0) when the result has none. Reads "position" /
## "field" when the producer sends them, else the "4th of 4" detail of road_race.gd.
static func _race_place(result: Dictionary, kind: String) -> Vector2i:
	var pos := int(result.get("position", 0))
	var field := int(result.get("field", 0))
	if pos <= 0 and kind == "race":
		var re := RegEx.create_from_string("^\\s*(\\d+)\\s*(?:st|nd|rd|th)?\\s+of\\s+(\\d+)")
		var m := re.search(String(result.get("detail", "")))
		if m != null:
			pos = m.get_string(1).to_int()
			field = m.get_string(2).to_int()
	return Vector2i(pos, field) if pos > 0 else Vector2i.ZERO


static func _place_text(place: Vector2i) -> String:
	var n := place.x
	var suffix := "TH"
	if n % 100 < 11 or n % 100 > 13:
		suffix = ["TH", "ST", "ND", "RD", "TH", "TH", "TH", "TH", "TH", "TH"][n % 10]
	return "%d%s OF %d" % [n, suffix, place.y] if place.y > 1 else "%d%s PLACE" % [n, suffix]


func _draw_flash() -> void:
	if _flash <= 0.0:
		return
	var fl := _flash_layer
	var k := _flash / FLASH_TIME
	fl.draw_rect(Rect2(Vector2.ZERO, size), Color(1, 1, 1, 0.75 * k * k))
	# Viewfinder corners.
	var m := 60.0 + (1.0 - k) * 30.0
	var l := 90.0
	var col := Color(1, 1, 1, k)
	var corners: Array[Vector2] = [Vector2(m, m), Vector2(size.x - m, m), Vector2(m, size.y - m), Vector2(size.x - m, size.y - m)]
	for cp in corners:
		var sx := 1.0 if cp.x < size.x * 0.5 else -1.0
		var sy := 1.0 if cp.y < size.y * 0.5 else -1.0
		fl.draw_line(cp, cp + Vector2(l * sx, 0), col, 6.0, true)
		fl.draw_line(cp, cp + Vector2(0, l * sy), col, 6.0, true)
	fl.draw_circle(Vector2(size.x - m - 40.0, m + 40.0), 12.0, Color(Style.BAD, k), true, -1.0, true)
