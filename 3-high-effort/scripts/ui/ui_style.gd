class_name UIStyle
extends RefCounted
## Velora Roads UI look: deep navy glass panels, warm sunset accent, teal secondary.

const ACCENT := Color(1.0, 0.72, 0.26)
const ACCENT2 := Color(0.25, 0.85, 0.82)
const PANEL := Color(0.05, 0.07, 0.11, 0.82)
const PANEL_LIGHT := Color(0.12, 0.15, 0.22, 0.9)
const TEXT := Color(0.95, 0.96, 0.98)
const TEXT_DIM := Color(0.68, 0.72, 0.8)
const DANGER := Color(1.0, 0.35, 0.3)


static func panel(color: Color = PANEL, radius: int = 10, border: Color = Color(1, 1, 1, 0.06)) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(radius)
	sb.set_border_width_all(1)
	sb.border_color = border
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	sb.shadow_color = Color(0, 0, 0, 0.25)
	sb.shadow_size = 6
	return sb


static func label(text: String, size: int = 18, color: Color = TEXT, bold: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.55))
	l.add_theme_constant_override("shadow_offset_x", 1)
	l.add_theme_constant_override("shadow_offset_y", 2)
	if bold:
		l.add_theme_constant_override("outline_size", 1)
		l.add_theme_color_override("font_outline_color", color)
	return l


static func button(text: String, size: int = 18) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", size)
	b.add_theme_stylebox_override("normal", panel(PANEL_LIGHT, 8))
	b.add_theme_stylebox_override("hover", panel(Color(0.2, 0.25, 0.35, 0.95), 8, ACCENT))
	b.add_theme_stylebox_override("pressed", panel(Color(0.32, 0.25, 0.1, 0.95), 8, ACCENT))
	b.add_theme_stylebox_override("focus", panel(Color(0.2, 0.25, 0.35, 0.95), 8, ACCENT))
	b.add_theme_color_override("font_color", TEXT)
	b.add_theme_color_override("font_hover_color", ACCENT)
	b.focus_mode = Control.FOCUS_ALL
	return b


static func bar(value: float, max_value: float, color: Color, width: float = 220.0) -> ProgressBar:
	var pb := ProgressBar.new()
	pb.min_value = 0.0
	pb.max_value = max_value
	pb.value = value
	pb.show_percentage = false
	pb.custom_minimum_size = Vector2(width, 12)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(1, 1, 1, 0.08)
	bg.set_corner_radius_all(5)
	var fg := StyleBoxFlat.new()
	fg.bg_color = color
	fg.set_corner_radius_all(5)
	pb.add_theme_stylebox_override("background", bg)
	pb.add_theme_stylebox_override("fill", fg)
	return pb


static func class_badge(cls: String, pi: int, size: int = 16) -> PanelContainer:
	var pc := PanelContainer.new()
	var sb := panel(Tuning.class_color(cls), 6, Color(1, 1, 1, 0.3))
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 2
	sb.content_margin_bottom = 2
	pc.add_theme_stylebox_override("panel", sb)
	var l := label("%s  %d" % [cls, pi], size, Color(0.05, 0.05, 0.08))
	l.remove_theme_color_override("font_shadow_color")
	pc.add_child(l)
	return pc


## Anchors a control to a preset and sets its offsets relative to those anchors.
static func place(c: Control, preset: int, left: float, top: float, right: float, bottom: float) -> void:
	c.set_anchors_preset(preset)
	c.offset_left = left
	c.offset_top = top
	c.offset_right = right
	c.offset_bottom = bottom
