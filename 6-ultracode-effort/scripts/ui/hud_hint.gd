extends Control
## Bottom controls hint (key caps + labels) that fades out ~12 s after the game has loaded.
## show_hint() brings it back (e.g. from the console / pause menu).

const Style := preload("res://scripts/ui/ui_style.gd")

const KEYS := [["`", "Console"], ["F1", "Garage"], ["F2", "Debug"], ["M", "Map"], ["C", "Camera"], ["R", "Reset"], ["Backspace", "Rewind"], ["P", "Photo"]]
const SHOW_TIME := 12.0
const FADE_TIME := 1.2

var _t: float = -1.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	anchor_top = 1.0
	anchor_bottom = 1.0
	offset_left = 350.0
	offset_right = 1300.0
	offset_top = -62.0
	offset_bottom = -20.0


func show_hint() -> void:
	_t = 0.0


func _process(delta: float) -> void:
	if _t < 0.0:
		var main: Node = Game.main
		if main == null or not bool(main.get("is_loading")):
			_t = 0.0
		return
	if _t > SHOW_TIME + FADE_TIME:
		return
	_t += delta
	queue_redraw()


func _draw() -> void:
	if _t < 0.0:
		return
	var a := clampf(_t / 0.6, 0.0, 1.0) * (1.0 - clampf((_t - SHOW_TIME) / FADE_TIME, 0.0, 1.0))
	if a <= 0.0:
		return
	var x := 0.0
	var h := 34.0
	for kv: Array in KEYS:
		var key := String(kv[0])
		var lab := String(kv[1])
		var kw := maxf(Style.text_width(key, 17, 700) + 18.0, 34.0)
		var kr := Rect2(Vector2(x, 4), Vector2(kw, h))
		Style.draw_round_rect(self, Rect2(kr.position + Vector2(0, 3), kr.size), Color(0, 0, 0, 0.45 * a), 8)
		Style.draw_round_rect(self, kr, Color(0.93, 0.93, 0.95, 0.92 * a), 8)
		Style.draw_text(self, key, kr.position + Vector2(0, 24), 17, Color(Style.INK, a), HORIZONTAL_ALIGNMENT_CENTER, kw, 700, false, 0, 0.0)
		var lw := Style.text_width(lab, 18, 600)
		Style.draw_text(self, lab, Vector2(x + kw + 8.0, 27), 18, Color(Style.TEXT, a), HORIZONTAL_ALIGNMENT_LEFT, -1.0, 600, false, 0, 0.6)
		x += kw + lw + 26.0
