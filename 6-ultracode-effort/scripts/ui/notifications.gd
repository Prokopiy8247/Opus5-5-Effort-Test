extends Control
## Top-right toast stack for Game.notification(title, body, kind): newest on top, slide/fade in,
## smooth reflow, auto-expire (longer bodies stay longer), duplicates refresh instead of stacking.

const Style := preload("res://scripts/ui/ui_style.gd")

const W := 440.0
const GAP := 10.0
const LIFE := 4.8
const MAX_VISIBLE := 4
const IN_TIME := 0.3
const OUT_TIME := 0.45
const KIND_STYLE := {
	"info": ["INFO", Color(0.38, 0.78, 1.0)], "hub": ["FESTIVAL", Color(1.0, 0.56, 0.16)],
	"route": ["GPS", Color(1.0, 0.3, 0.72)], "success": ["COMPLETE", Color(0.42, 0.9, 0.56)],
	"warning": ["WARNING", Color(1.0, 0.36, 0.38)], "error": ["ERROR", Color(1.0, 0.36, 0.38)],
	"discovery": ["DISCOVERED", Color(0.93, 0.25, 0.53)], "activity": ["ACTIVITY", Color(1.0, 0.8, 0.34)],
	"pb": ["PERSONAL BEST", Color(0.93, 0.25, 0.53)], "reward": ["REWARD", Color(1.0, 0.8, 0.34)],
	"collectible": ["COLLECTIBLE", Color(1.0, 0.8, 0.34)], "car": ["GARAGE", Color(0.38, 0.78, 1.0)],
}

var _toasts: Array = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	anchor_left = 1.0
	anchor_right = 1.0
	offset_left = -W - 24.0
	offset_right = -24.0
	offset_top = 22.0
	offset_bottom = 700.0
	Game.notification.connect(push)


func push(title: String, body := "", kind: StringName = &"info") -> void:
	# The debug benchmark owns the screen: prompts from event gates its autopilot passes are not shown.
	if Game.benchmark_mode:
		return
	for t: Dictionary in _toasts:
		if t["title"] == title and t["body"] == body and float(t["age"]) < float(t["life"]) - OUT_TIME:
			t["age"] = minf(float(t["age"]), IN_TIME)
			return
	var k := String(kind)
	var st: Array = KIND_STYLE.get(k, [k.to_upper(), Style.ACCENT])
	var col: Color = st[1]
	var p := PanelContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := Style.panel(Style.BG_STRONG, 12, 0, Style.LINE, 10.0)
	sb.border_width_left = 6
	sb.border_color = col
	sb.content_margin_left = 20.0
	sb.shadow_color = Color(0, 0, 0, 0.3)
	sb.shadow_size = 8
	sb.shadow_offset = Vector2(0, 3)
	p.add_theme_stylebox_override("panel", sb)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 1)
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(vb)
	var inner := W - 20.0 - 16.0
	vb.add_child(_label(String(st[0]), 13, col, 700, 3, inner))
	vb.add_child(_label(title, 22, Style.TEXT, 700, 0, inner))
	if body != "":
		vb.add_child(_label(body, 17, Style.TEXT_DIM, 500, 0, inner))
	p.size = Vector2(W, 10)
	p.modulate.a = 0.0
	add_child(p)
	var life := clampf(LIFE + body.length() * 0.025, LIFE, 8.0)
	_toasts.push_front({"node": p, "title": title, "body": body, "age": 0.0, "life": life, "y": -20.0})


func _label(text: String, size_px: int, color: Color, weight: int, spacing: int, width: float) -> Label:
	var l := Label.new()
	l.text = text
	l.label_settings = Style.label_settings(size_px, color, weight, false, spacing, false)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(width, 0)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _process(delta: float) -> void:
	var y := 0.0
	var i := 0
	for t: Dictionary in _toasts.duplicate():
		var p: PanelContainer = t["node"]
		if i >= MAX_VISIBLE:
			t["life"] = minf(float(t["life"]), float(t["age"]) + OUT_TIME)
		t["age"] = float(t["age"]) + delta
		var age: float = t["age"]
		var life: float = t["life"]
		if age >= life:
			p.queue_free()
			_toasts.erase(t)
			continue
		var h := p.get_combined_minimum_size().y
		p.size = Vector2(W, h)
		var k_in := clampf(age / IN_TIME, 0.0, 1.0)
		var e_in := 1.0 - pow(1.0 - k_in, 3.0)
		var k_out := clampf((age - (life - OUT_TIME)) / OUT_TIME, 0.0, 1.0)
		t["y"] = lerpf(float(t["y"]), y, clampf(delta * 12.0, 0.0, 1.0))
		p.position = Vector2((1.0 - e_in) * 60.0 + k_out * 50.0, float(t["y"]))
		p.modulate.a = e_in * (1.0 - k_out)
		y += (h + GAP) * (1.0 - k_out)
		i += 1
