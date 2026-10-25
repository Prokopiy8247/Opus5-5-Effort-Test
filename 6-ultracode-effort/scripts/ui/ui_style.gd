extends RefCounted
## Sunward HUD look: palette, fonts, panel styles and small formatting / drawing helpers.
## Design canvas is 1920x1080 (stretch mode canvas_items), so every size here is a 1080p pixel.

const BG := Color(0.035, 0.04, 0.07, 0.62)
const BG_STRONG := Color(0.04, 0.05, 0.085, 0.86)
const BG_SOLID := Color(0.05, 0.06, 0.1, 0.94)
const LINE := Color(1.0, 1.0, 1.0, 0.09)
const ACCENT := Color(1.0, 0.56, 0.16)
const ACCENT_2 := Color(0.93, 0.25, 0.53)
const GOLD := Color(1.0, 0.8, 0.34)
const SKY := Color(0.38, 0.78, 1.0)
const TEXT := Color(0.97, 0.96, 0.94)
const TEXT_DIM := Color(0.72, 0.74, 0.8)
const TEXT_FAINT := Color(0.47, 0.5, 0.58)
const GOOD := Color(0.42, 0.9, 0.56)
const BAD := Color(1.0, 0.36, 0.38)
const ROUTE := Color(1.0, 0.3, 0.72)
const SHADOW := Color(0.0, 0.0, 0.0, 0.55)
const INK := Color(0.06, 0.05, 0.07)

const FONT_NAMES: PackedStringArray = ["Bahnschrift", "Segoe UI", "Roboto", "Noto Sans", "Arial"]

static var _fonts: Dictionary = {}
static var _theme: Theme
static var _rr: StyleBoxFlat


## weight 300..700; condensed uses the font's width axis when it has one (Bahnschrift);
## spacing adds letter spacing in pixels (for small caps titles).
static func font(weight := 500, condensed := false, spacing := 0) -> Font:
	var key := Vector3i(weight, 1 if condensed else 0, spacing)
	if _fonts.has(key):
		return _fonts[key]
	var sf := SystemFont.new()
	sf.font_names = FONT_NAMES
	sf.font_weight = weight
	sf.font_stretch = 75 if condensed else 100
	sf.allow_system_fallback = true
	sf.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_AUTO
	var fv := FontVariation.new()
	fv.base_font = sf
	var ts := TextServerManager.get_primary_interface()
	if ts != null:
		fv.variation_opentype = {ts.name_to_tag("wght"): weight, ts.name_to_tag("wdth"): 75 if condensed else 100}
	if spacing != 0:
		fv.spacing_glyph = spacing
	_fonts[key] = fv
	return fv


static func panel(bg := BG, radius := 14, border := 1, border_color := LINE, pad := 12.0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(radius)
	s.set_border_width_all(border)
	s.border_color = border_color
	s.content_margin_left = pad + 4.0
	s.content_margin_right = pad + 4.0
	s.content_margin_top = pad
	s.content_margin_bottom = pad
	s.anti_aliasing = true
	s.corner_detail = 8
	return s


static func theme() -> Theme:
	if _theme != null:
		return _theme
	var t := Theme.new()
	t.default_font = font(500)
	t.default_font_size = 20
	t.set_color("font_color", "Label", TEXT)
	t.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0.45))
	t.set_constant("shadow_offset_y", "Label", 2)
	t.set_stylebox("panel", "PanelContainer", panel())
	t.set_stylebox("panel", "Panel", panel())
	_theme = t
	return t


static func label_settings(size: int, color := TEXT, weight := 600, condensed := false, spacing := 0, shadow := true) -> LabelSettings:
	var ls := LabelSettings.new()
	ls.font = font(weight, condensed, spacing)
	ls.font_size = size
	ls.font_color = color
	if shadow:
		ls.shadow_color = Color(0, 0, 0, 0.5)
		ls.shadow_size = 3
		ls.shadow_offset = Vector2(0, 2)
	return ls


static func label(text: String, size: int, color := TEXT, weight := 600, spacing := 0) -> Label:
	var l := Label.new()
	l.text = text
	l.label_settings = label_settings(size, color, weight, false, spacing)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## Text with a soft drop shadow, drawn from a CanvasItem's _draw(). pos = left end of the baseline.
static func draw_text(ci: CanvasItem, text: String, pos: Vector2, size: int, color := TEXT, align := HORIZONTAL_ALIGNMENT_LEFT,
		width := -1.0, weight := 600, condensed := false, spacing := 0, shadow := 0.5) -> void:
	var f := font(weight, condensed, spacing)
	if shadow > 0.0:
		ci.draw_string(f, pos + Vector2(0, maxf(size * 0.06, 1.5)), text, align, width, size, Color(0, 0, 0, shadow * color.a))
	ci.draw_string(f, pos, text, align, width, size, color)


static func text_width(text: String, size: int, weight := 600, condensed := false, spacing := 0) -> float:
	return font(weight, condensed, spacing).get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x


## Orange -> magenta festival gradient.
static func accent_at(t: float) -> Color:
	return ACCENT.lerp(ACCENT_2, clampf(t, 0.0, 1.0))


## Rounded rectangle via one shared StyleBoxFlat (draw_style_box records geometry immediately).
static func draw_round_rect(ci: CanvasItem, rect: Rect2, color: Color, radius := 10, border := 0, border_color := LINE) -> void:
	if _rr == null:
		_rr = StyleBoxFlat.new()
		_rr.anti_aliasing = true
		_rr.corner_detail = 6
	_rr.bg_color = color
	_rr.set_corner_radius_all(radius)
	_rr.set_border_width_all(border)
	_rr.border_color = border_color
	ci.draw_style_box(_rr, rect)


# ------------------------------------------------------------------ units

static func use_mph() -> bool:
	return bool(Settings.get_value("units_mph", false))


static func speed_value(kmh: float) -> float:
	return kmh * 0.621371 if use_mph() else kmh


static func speed_unit() -> String:
	return "MPH" if use_mph() else "KM/H"


static func distance_text(m: float) -> String:
	if use_mph():
		var mi := m / 1609.344
		return "%.1f mi" % mi if mi >= 0.2 else "%d ft" % int(round(m * 3.28084 / 10.0) * 10.0)
	if m >= 1000.0:
		return "%.1f km" % (m / 1000.0)
	return "%d m" % int(round(m / 10.0) * 10.0)
