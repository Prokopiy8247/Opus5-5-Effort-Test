class_name UiTheme
extends RefCounted
## Original UI look: dark translucent panels, warm amber accent, teal secondary, clean
## geometric system font (Bahnschrift/Segoe UI on Windows, engine default elsewhere).

const ACCENT := Color(1.0, 0.64, 0.12)
const ACCENT2 := Color(0.22, 0.86, 0.94)
const TEXT := Color(0.96, 0.97, 0.98)
const TEXT_DIM := Color(0.72, 0.76, 0.8)
const PANEL := Color(0.05, 0.06, 0.08, 0.78)
const PANEL_LIGHT := Color(0.12, 0.14, 0.18, 0.85)
const RED := Color(1.0, 0.25, 0.22)
const GOOD := Color(0.4, 0.95, 0.5)

static var _theme: Theme
static var _font: Font
static var _font_bold: Font


static func font(bold: bool = false) -> Font:
	if _font == null:
		var f := SystemFont.new()
		f.font_names = PackedStringArray(["Bahnschrift", "Segoe UI", "Arial", "Sans-Serif"])
		f.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
		f.hinting = TextServer.HINTING_LIGHT
		_font = f
		var fb := SystemFont.new()
		fb.font_names = PackedStringArray(["Bahnschrift", "Segoe UI", "Arial", "Sans-Serif"])
		fb.font_weight = 700
		_font_bold = fb
	return _font_bold if bold else _font


static func panel_style(color: Color = PANEL, radius: int = 10, border: Color = Color(1, 1, 1, 0.06)) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.corner_radius_top_left = radius
	sb.corner_radius_top_right = radius
	sb.corner_radius_bottom_left = radius
	sb.corner_radius_bottom_right = radius
	sb.border_width_left = 1
	sb.border_width_right = 1
	sb.border_width_top = 1
	sb.border_width_bottom = 1
	sb.border_color = border
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	return sb


static func get_theme() -> Theme:
	if _theme != null:
		return _theme
	var t := Theme.new()
	t.default_font = font()
	t.default_font_size = 20
	t.set_color("font_color", "Label", TEXT)
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", Color(1, 1, 1))
	t.set_color("font_pressed_color", "Button", Color(0.08, 0.08, 0.1))
	t.set_color("font_focus_color", "Button", Color(1, 1, 1))
	var normal := panel_style(Color(0.14, 0.16, 0.2, 0.9), 6)
	normal.content_margin_top = 6
	normal.content_margin_bottom = 6
	var hover := panel_style(Color(0.22, 0.25, 0.31, 0.95), 6, ACCENT * Color(1, 1, 1, 0.6))
	hover.content_margin_top = 6
	hover.content_margin_bottom = 6
	var pressed := panel_style(ACCENT, 6)
	pressed.content_margin_top = 6
	pressed.content_margin_bottom = 6
	var focus := panel_style(Color(0, 0, 0, 0), 6, ACCENT)
	t.set_stylebox("normal", "Button", normal)
	t.set_stylebox("hover", "Button", hover)
	t.set_stylebox("pressed", "Button", pressed)
	t.set_stylebox("focus", "Button", focus)
	t.set_stylebox("panel", "Panel", panel_style())
	t.set_stylebox("panel", "PanelContainer", panel_style())
	var le := panel_style(Color(0.02, 0.03, 0.04, 0.9), 4, ACCENT * Color(1, 1, 1, 0.5))
	t.set_stylebox("normal", "LineEdit", le)
	t.set_stylebox("focus", "LineEdit", le)
	t.set_color("font_color", "LineEdit", TEXT)
	t.set_color("caret_color", "LineEdit", ACCENT)
	t.set_color("default_color", "RichTextLabel", TEXT)
	t.set_font("normal_font", "RichTextLabel", font())
	t.set_font("bold_font", "RichTextLabel", font(true))
	t.set_font("mono_font", "RichTextLabel", font())
	var grabber := panel_style(ACCENT, 4)
	t.set_stylebox("grabber_area", "HSlider", panel_style(ACCENT * Color(1, 1, 1, 0.6), 3))
	t.set_stylebox("slider", "HSlider", panel_style(Color(0.2, 0.22, 0.26), 3))
	t.set_stylebox("panel", "TabContainer", panel_style(Color(0.05, 0.06, 0.08, 0.6), 6))
	_theme = t
	return t


static func label(text: String, size: int = 20, color: Color = TEXT, bold: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font(bold))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


static func class_color(cls: String) -> Color:
	match cls:
		"D":
			return Color(0.35, 0.75, 0.95)
		"C":
			return Color(0.95, 0.85, 0.3)
		"B":
			return Color(1.0, 0.55, 0.2)
		"A":
			return Color(0.95, 0.3, 0.35)
		"S1":
			return Color(0.75, 0.4, 0.95)
		"S2":
			return Color(0.3, 0.55, 1.0)
	return Color(0.8, 0.8, 0.8)
