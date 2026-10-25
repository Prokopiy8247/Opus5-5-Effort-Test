extends Control
## Top-left FPS / coordinates / speed readout (Settings "show_fps"), refreshed at 4 Hz.

const Style := preload("res://scripts/ui/ui_style.gd")

var _timer: float = 0.0
var _fps: float = 0.0
var _ms: float = 0.0
var _worst: float = 0.0
var _worst_acc: float = 0.0
var _sum: float = 0.0
var _frames: int = 0
var _pos := Vector3.ZERO
var _kmh: float = 0.0
var _region: String = ""


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	position = Vector2(22, 18)
	size = Vector2(360, 92)


func _process(delta: float) -> void:
	_worst_acc = maxf(_worst_acc, delta)
	_sum += delta
	_frames += 1
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = 0.25
	_fps = Engine.get_frames_per_second()
	_ms = _sum / maxf(_frames, 1) * 1000.0
	_sum = 0.0
	_frames = 0
	_worst = _worst_acc * 1000.0
	_worst_acc = 0.0
	var car := Game.player_car
	if car != null and is_instance_valid(car):
		_pos = car.global_position
		_kmh = car.get_speed_kmh()
	if Game.world is World:
		_region = (Game.world as World).region_at(_pos)
	queue_redraw()


func _draw() -> void:
	Style.draw_round_rect(self, Rect2(Vector2.ZERO, size), Style.BG, 12, 1, Style.LINE)
	var fc := Style.GOOD if _fps >= 55.0 else (Style.ACCENT if _fps >= 30.0 else Style.BAD)
	Style.draw_text(self, "%d" % int(round(_fps)), Vector2(14, 31), 26, fc, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 700, true, 0, 0.0)
	var fw := Style.text_width("%d" % int(round(_fps)), 26, 700, true)
	Style.draw_text(self, "FPS", Vector2(18 + fw, 31), 14, Style.TEXT_FAINT, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 600, false, 1, 0.0)
	Style.draw_text(self, "%.1f ms  ·  worst %.1f ms" % [_ms, _worst], Vector2(110, 30), 15, Style.TEXT_DIM, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 500, false, 0, 0.0)
	Style.draw_text(self, "X %.1f   Y %.1f   Z %.1f" % [_pos.x, _pos.y, _pos.z], Vector2(14, 56), 16, Style.TEXT, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 500, false, 0, 0.0)
	Style.draw_text(self, "%d %s  ·  %s" % [int(round(Style.speed_value(_kmh))), Style.speed_unit().to_lower(), _region], Vector2(14, 80), 16,
		Style.TEXT_DIM, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 500, false, 0, 0.0)
