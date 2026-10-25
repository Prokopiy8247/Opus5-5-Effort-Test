class_name UITheme
extends RefCounted
## Original festival-style UI look: dark glass panels, hot pink / cyan / sunshine accents.

const PINK := Color(1.0, 0.24, 0.5)
const CYAN := Color(0.18, 0.88, 0.99)
const SUN := Color(1.0, 0.79, 0.24)
const PANEL := Color(0.04, 0.05, 0.09, 0.78)
const PANEL_LIGHT := Color(0.1, 0.12, 0.2, 0.88)
const TEXT := Color(0.96, 0.97, 1.0)
const DIM := Color(0.7, 0.74, 0.85)

static var _theme: Theme
static var _font: Font
static var _font_bold: Font


static func font(bold := false) -> Font:
	if _font == null:
		var f := SystemFont.new()
		f.font_names = PackedStringArray(["Bahnschrift", "Segoe UI", "Arial", "Noto Sans"])
		f.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
		_font = f
		var fb := SystemFont.new()
		fb.font_names = PackedStringArray(["Bahnschrift", "Segoe UI", "Arial", "Noto Sans"])
		fb.font_weight = 700
		_font_bold = fb
	return _font_bold if bold else _font


static func panel_box(col := PANEL, radius := 14, border := Color(0, 0, 0, 0)) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	if border.a > 0.0:
		sb.border_color = border
		sb.set_border_width_all(2)
	return sb


static func theme() -> Theme:
	if _theme != null:
		return _theme
	var t := Theme.new()
	t.default_font = font()
	t.default_font_size = 20
	t.set_color("font_color", "Label", TEXT)
	t.set_stylebox("panel", "PanelContainer", panel_box())
	t.set_stylebox("panel", "Panel", panel_box())
	var btn := panel_box(Color(0.12, 0.14, 0.22, 0.9), 10)
	var hov := panel_box(Color(0.22, 0.12, 0.25, 0.95), 10, PINK)
	var prs := panel_box(PINK.darkened(0.2), 10)
	var foc := panel_box(Color(0.16, 0.16, 0.28, 0.95), 10, CYAN)
	t.set_stylebox("normal", "Button", btn)
	t.set_stylebox("hover", "Button", hov)
	t.set_stylebox("pressed", "Button", prs)
	t.set_stylebox("focus", "Button", foc)
	t.set_stylebox("disabled", "Button", panel_box(Color(0.1, 0.1, 0.12, 0.6), 10))
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_pressed_color", "Button", Color.WHITE)
	t.set_font("font", "Button", font(true))
	t.set_font_size("font_size", "Button", 19)
	var le := panel_box(Color(0.02, 0.03, 0.06, 0.95), 8, CYAN.darkened(0.4))
	t.set_stylebox("normal", "LineEdit", le)
	t.set_stylebox("focus", "LineEdit", le)
	t.set_color("font_color", "LineEdit", TEXT)
	t.set_stylebox("normal", "RichTextLabel", StyleBoxEmpty.new())
	t.set_color("default_color", "RichTextLabel", TEXT)
	var grab := StyleBoxFlat.new()
	grab.bg_color = PINK
	grab.set_corner_radius_all(6)
	var slider_bg := StyleBoxFlat.new()
	slider_bg.bg_color = Color(0.2, 0.22, 0.3)
	slider_bg.set_corner_radius_all(4)
	slider_bg.content_margin_top = 3
	slider_bg.content_margin_bottom = 3
	t.set_stylebox("slider", "HSlider", slider_bg)
	t.set_stylebox("grabber_area", "HSlider", grab)
	t.set_stylebox("grabber_area_highlight", "HSlider", grab)
	t.set_stylebox("panel", "TabContainer", panel_box(PANEL_LIGHT, 12))
	t.set_stylebox("tab_selected", "TabContainer", panel_box(PINK.darkened(0.15), 8))
	t.set_stylebox("tab_unselected", "TabContainer", panel_box(Color(0.1, 0.11, 0.18, 0.9), 8))
	t.set_stylebox("tab_hovered", "TabContainer", panel_box(Color(0.2, 0.12, 0.25, 0.9), 8))
	t.set_font("font", "TabContainer", font(true))
	t.set_stylebox("panel", "ItemList", panel_box(Color(0.03, 0.04, 0.07, 0.6), 8))
	t.set_stylebox("selected", "ItemList", panel_box(PINK.darkened(0.25), 6))
	t.set_stylebox("selected_focus", "ItemList", panel_box(PINK.darkened(0.1), 6))
	_theme = t
	return t


## Anchor a control at (ax, ay) of its parent (0..1) with a pixel rect offset from that anchor.
static func place(c: Control, ax: float, ay: float, ox: float, oy: float, w: float, h: float) -> void:
	c.anchor_left = ax
	c.anchor_right = ax
	c.anchor_top = ay
	c.anchor_bottom = ay
	c.offset_left = ox
	c.offset_top = oy
	c.offset_right = ox + w
	c.offset_bottom = oy + h


static func label(text: String, size := 20, col := TEXT, bold := false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_font_override("font", font(bold))
	l.add_theme_constant_override("outline_size", 0)
	return l


static func class_color(c: String) -> Color:
	match c:
		"E":
			return Color(0.55, 0.85, 0.95)
		"D":
			return Color(0.35, 0.8, 0.45)
		"C":
			return Color(0.95, 0.85, 0.25)
		"B":
			return Color(1.0, 0.55, 0.15)
		"A":
			return Color(1.0, 0.25, 0.3)
		"S":
			return Color(0.75, 0.35, 1.0)
	return DIM
