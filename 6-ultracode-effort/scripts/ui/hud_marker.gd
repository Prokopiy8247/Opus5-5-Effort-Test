extends Node2D
## A map marker that is drawn once and then only moved / faded by its owner (minimap, world map):
## badge for a POI or activity kind with an optional name tag, or the special kinds "_pin" (waypoint)
## and "_north" (compass badge).

const Style := preload("res://scripts/ui/ui_style.gd")
const Icons := preload("res://scripts/ui/hud_icons.gd")

var kind: String = ""
var label_text: String = ""
var radius: float = 10.0
var data: Dictionary = {}
var show_tag: bool = false:
	set(v):
		if v != show_tag:
			show_tag = v
			queue_redraw()
var highlight: bool = false:
	set(v):
		if v != highlight:
			highlight = v
			queue_redraw()


func setup(marker_kind: String, text: String, r: float, marker: Dictionary = {}) -> void:
	kind = marker_kind
	label_text = text
	radius = r
	data = marker
	queue_redraw()


## Name tag rectangle in local coordinates (right of the badge).
func tag_rect() -> Rect2:
	var w := Style.text_width(label_text, 15, 600) + 14.0
	return Rect2(Vector2(radius + 8.0, -12.0), Vector2(w, 24.0))


func _draw() -> void:
	match kind:
		"_pin":
			Icons.draw_pin(self, Vector2.ZERO, radius)
		"_north":
			draw_circle(Vector2.ZERO, radius, Color(0.05, 0.06, 0.1, 0.95), true, -1.0, true)
			draw_arc(Vector2.ZERO, radius, 0.0, TAU, 24, Style.ACCENT, 2.0, true)
			Style.draw_text(self, "N", Vector2(-radius, radius * 0.5), int(radius * 1.3), Style.TEXT, HORIZONTAL_ALIGNMENT_CENTER, radius * 2.0, 700, false, 0, 0.0)
		_:
			if kind == "hub" and show_tag:
				draw_arc(Vector2.ZERO, radius * 1.7, 0.0, TAU, 32, Color(Style.ACCENT, 0.45), 2.0, true)
			Icons.draw_badge(self, kind, Vector2.ZERO, radius * (1.15 if highlight else 1.0), 1.0, highlight)
			if show_tag and not highlight and label_text != "":
				var r := tag_rect()
				Style.draw_round_rect(self, r, Color(0.03, 0.035, 0.06, 0.8), 8)
				Style.draw_text(self, label_text, r.position + Vector2(7, 17), 15, Style.TEXT, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 600, false, 0, 0.0)
