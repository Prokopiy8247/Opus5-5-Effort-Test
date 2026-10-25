extends RefCounted
## Shared look of the Sunward menus: palette, fonts, theme and small widget factories.
## Design canvas is 1920x1080 (stretch mode canvas_items), so sizes here are 1080p pixels.

const BG := Color(0.03, 0.04, 0.07, 0.86)
const PANEL := Color(0.06, 0.075, 0.115, 0.93)
const PANEL_HI := Color(0.1, 0.12, 0.18, 0.96)
const CARD := Color(0.09, 0.105, 0.16, 0.94)
const LINE := Color(1.0, 1.0, 1.0, 0.07)
const ACCENT := Color(1.0, 0.56, 0.16)
const ACCENT_2 := Color(0.93, 0.25, 0.53)
const GOLD := Color(1.0, 0.8, 0.34)
const SKY := Color(0.38, 0.78, 1.0)
const TEXT := Color(0.96, 0.95, 0.93)
const TEXT_DIM := Color(0.7, 0.72, 0.78)
const TEXT_FAINT := Color(0.47, 0.5, 0.58)
const INK := Color(0.07, 0.05, 0.06)
const GOOD := Color(0.42, 0.9, 0.56)
const BAD := Color(1.0, 0.44, 0.4)
const CLASS_COLORS := {
	"D": Color(0.33, 0.76, 0.86), "C": Color(0.98, 0.82, 0.28), "B": Color(1.0, 0.57, 0.2),
	"A": Color(0.97, 0.32, 0.34), "S1": Color(0.84, 0.35, 0.88), "S2": Color(0.5, 0.5, 1.0), "X": Color(0.5, 0.93, 0.42),
}
const FONT_SIZE := 22
const SMALL := 18
const RADIUS := 12

static var _theme: Theme
static var _fonts: Dictionary = {}
static var _tex: Dictionary = {}


# ------------------------------------------------------------------ fonts / theme

static func font(weight := 400, spacing := 0) -> Font:
	var key := "%d_%d" % [weight, spacing]
	if _fonts.has(key):
		return _fonts[key]
	var sf := SystemFont.new()
	sf.font_names = PackedStringArray(["Bahnschrift", "Segoe UI", "Roboto", "Noto Sans", "Arial"])
	sf.font_weight = weight
	sf.allow_system_fallback = true
	sf.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_AUTO
	var f: Font = sf
	if spacing != 0:
		var fv := FontVariation.new()
		fv.base_font = sf
		fv.spacing_glyph = spacing
		f = fv
	_fonts[key] = f
	return f


static func box(bg: Color, radius := RADIUS, border := 0, border_color := LINE, pad := 10.0) -> StyleBoxFlat:
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
	s.corner_detail = 6
	return s


static func theme() -> Theme:
	if _theme != null:
		return _theme
	var t := Theme.new()
	t.default_font = font(400)
	t.default_font_size = FONT_SIZE
	# Buttons
	var normal := box(Color(0.12, 0.14, 0.21, 0.92), 10, 1, LINE, 8)
	var hover := box(Color(0.18, 0.2, 0.29, 0.96), 10, 1, Color(1, 1, 1, 0.16), 8)
	var pressed := box(ACCENT, 10, 0, LINE, 8)
	var disabled := box(Color(0.1, 0.11, 0.15, 0.6), 10, 0, LINE, 8)
	var focus := StyleBoxFlat.new()
	focus.draw_center = false
	focus.set_corner_radius_all(12)
	focus.set_border_width_all(3)
	focus.border_color = ACCENT
	focus.set_expand_margin_all(3.0)
	focus.shadow_color = Color(ACCENT, 0.35)
	focus.shadow_size = 8
	focus.anti_aliasing = true
	for type: String in ["Button", "CheckButton", "CheckBox"]:
		t.set_stylebox("normal", type, normal)
		t.set_stylebox("hover", type, hover)
		t.set_stylebox("pressed", type, pressed)
		t.set_stylebox("hover_pressed", type, pressed)
		t.set_stylebox("disabled", type, disabled)
		t.set_stylebox("focus", type, focus)
		t.set_color("font_color", type, TEXT)
		t.set_color("font_hover_color", type, Color.WHITE)
		t.set_color("font_focus_color", type, Color.WHITE)
		t.set_color("font_pressed_color", type, INK)
		t.set_color("font_hover_pressed_color", type, INK)
		t.set_color("font_disabled_color", type, TEXT_FAINT)
	# Toggles keep a neutral background; the switch icon shows the state.
	for type: String in ["CheckButton", "CheckBox"]:
		t.set_stylebox("pressed", type, normal)
		t.set_stylebox("hover_pressed", type, hover)
		t.set_color("font_pressed_color", type, TEXT)
		t.set_color("font_hover_pressed_color", type, Color.WHITE)
		t.set_constant("h_separation", type, 14)
	t.set_icon("checked", "CheckButton", _switch_tex(true))
	t.set_icon("unchecked", "CheckButton", _switch_tex(false))
	t.set_icon("checked_disabled", "CheckButton", _switch_tex(true))
	t.set_icon("unchecked_disabled", "CheckButton", _switch_tex(false))
	# Labels
	t.set_color("font_color", "Label", TEXT)
	t.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0.35))
	# Line edits
	var le := box(Color(0.03, 0.035, 0.06, 0.95), 8, 1, Color(1, 1, 1, 0.12), 8)
	var le_focus := box(Color(0.03, 0.035, 0.06, 0.95), 8, 2, ACCENT, 8)
	t.set_stylebox("normal", "LineEdit", le)
	t.set_stylebox("focus", "LineEdit", le_focus)
	t.set_stylebox("read_only", "LineEdit", le)
	t.set_color("font_color", "LineEdit", TEXT)
	t.set_color("caret_color", "LineEdit", ACCENT)
	t.set_color("selection_color", "LineEdit", Color(ACCENT, 0.35))
	t.set_color("font_placeholder_color", "LineEdit", TEXT_FAINT)
	# Sliders
	var track := box(Color(1, 1, 1, 0.1), 4, 0, LINE, 0)
	track.content_margin_top = 4
	track.content_margin_bottom = 4
	var fill := box(ACCENT, 4, 0, LINE, 0)
	fill.content_margin_top = 4
	fill.content_margin_bottom = 4
	var fill_hi := box(GOLD, 4, 0, LINE, 0)
	fill_hi.content_margin_top = 4
	fill_hi.content_margin_bottom = 4
	t.set_stylebox("slider", "HSlider", track)
	t.set_stylebox("grabber_area", "HSlider", fill)
	t.set_stylebox("grabber_area_highlight", "HSlider", fill_hi)
	t.set_icon("grabber", "HSlider", _circle_tex(24, Color.WHITE, ACCENT))
	t.set_icon("grabber_highlight", "HSlider", _circle_tex(26, Color.WHITE, GOLD))
	t.set_icon("grabber_disabled", "HSlider", _circle_tex(24, TEXT_FAINT, TEXT_FAINT))
	t.set_stylebox("focus", "HSlider", focus)
	# Scroll bars
	var sb := box(Color(1, 1, 1, 0.04), 4, 0, LINE, 0)
	sb.content_margin_left = 5
	sb.content_margin_right = 5
	var grab := box(Color(1, 1, 1, 0.22), 4, 0, LINE, 0)
	var grab_hi := box(ACCENT, 4, 0, LINE, 0)
	for type: String in ["VScrollBar", "HScrollBar"]:
		t.set_stylebox("scroll", type, sb)
		t.set_stylebox("scroll_focus", type, sb)
		t.set_stylebox("grabber", type, grab)
		t.set_stylebox("grabber_highlight", type, grab_hi)
		t.set_stylebox("grabber_pressed", type, grab_hi)
	t.set_stylebox("panel", "ScrollContainer", StyleBoxEmpty.new())
	t.set_stylebox("focus", "ScrollContainer", StyleBoxEmpty.new())
	t.set_stylebox("panel", "PanelContainer", box(PANEL, RADIUS, 1, LINE, 16))
	# Rich text
	t.set_color("default_color", "RichTextLabel", TEXT)
	t.set_font("normal_font", "RichTextLabel", font(400))
	t.set_font("bold_font", "RichTextLabel", font(700))
	t.set_font("mono_font", "RichTextLabel", font(400))
	t.set_stylebox("normal", "RichTextLabel", StyleBoxEmpty.new())
	t.set_stylebox("focus", "RichTextLabel", StyleBoxEmpty.new())
	t.set_constant("table_h_separation", "RichTextLabel", 18)
	t.set_constant("line_separation", "RichTextLabel", 2)
	# Progress bars (stat bars)
	t.set_stylebox("background", "ProgressBar", box(Color(1, 1, 1, 0.08), 4, 0, LINE, 0))
	t.set_stylebox("fill", "ProgressBar", box(ACCENT, 4, 0, LINE, 0))
	t.set_stylebox("panel", "TooltipPanel", box(PANEL_HI, 8, 1, LINE, 8))
	_theme = t
	return t


static func _circle_tex(size: int, fill_c: Color, ring: Color) -> Texture2D:
	var key := "c%d_%s_%s" % [size, fill_c.to_html(), ring.to_html()]
	if _tex.has(key):
		return _tex[key]
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var c := (size - 1) * 0.5
	var r := size * 0.5 - 1.0
	for y in size:
		for x in size:
			var d := Vector2(x - c, y - c).length()
			var a := clampf(r - d + 0.5, 0.0, 1.0)
			var col := ring if d > r - 4.0 else fill_c
			img.set_pixel(x, y, Color(col, a))
	var tex := ImageTexture.create_from_image(img)
	_tex[key] = tex
	return tex


static func _switch_tex(on: bool) -> Texture2D:
	var key := "sw%s" % on
	if _tex.has(key):
		return _tex[key]
	var w := 52
	var h := 28
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var bg := ACCENT if on else Color(0.32, 0.35, 0.42)
	var knob_x := w - h * 0.5 if on else h * 0.5
	for y in h:
		for x in w:
			var px := Vector2(x + 0.5, y + 0.5)
			var cx := clampf(px.x, h * 0.5, w - h * 0.5)
			var d := px.distance_to(Vector2(cx, h * 0.5))
			var a := clampf(h * 0.5 - d, 0.0, 1.0)
			var col := bg
			var kd := px.distance_to(Vector2(knob_x, h * 0.5))
			if kd < h * 0.5 - 3.0:
				col = col.lerp(Color.WHITE, clampf(h * 0.5 - 3.0 - kd, 0.0, 1.0))
			img.set_pixel(x, y, Color(col, a))
	var tex := ImageTexture.create_from_image(img)
	_tex[key] = tex
	return tex


# ------------------------------------------------------------------ widget factories

static func label(text: String, size := FONT_SIZE, color := TEXT, weight := 400, spacing := 0) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if weight != 400 or spacing != 0:
		l.add_theme_font_override("font", font(weight, spacing))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


static func title(text: String, size := 44) -> Label:
	var l := label(text.to_upper(), size, TEXT, 700, 3)
	l.add_theme_constant_override("shadow_offset_y", 2)
	return l


static func caps(text: String, size := SMALL, color := TEXT_DIM) -> Label:
	return label(text.to_upper(), size, color, 600, 2)


static func accent_bar(width := 120.0, height := 5.0) -> TextureRect:
	var g := Gradient.new()
	g.set_color(0, ACCENT)
	g.set_color(1, ACCENT_2)
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.width = 64
	gt.height = 4
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(1, 0)
	var tr := TextureRect.new()
	tr.texture = gt
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.custom_minimum_size = Vector2(width, height)
	tr.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return tr


## Horizontal fade for readability over the 3D view; stays near `from_alpha` until `hold` (0..1).
static func side_fade(from_alpha := 0.9, to_alpha := 0.0, color := Color(0.02, 0.025, 0.05), hold := 0.0) -> TextureRect:
	var g := Gradient.new()
	if hold > 0.0:
		g.offsets = PackedFloat32Array([0.0, hold, 1.0])
		g.colors = PackedColorArray([Color(color, from_alpha), Color(color, from_alpha * 0.9), Color(color, to_alpha)])
	else:
		g.set_color(0, Color(color, from_alpha))
		g.set_color(1, Color(color, to_alpha))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.width = 256
	gt.height = 4
	gt.fill_to = Vector2(1, 0)
	var tr := TextureRect.new()
	tr.texture = gt
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return tr


## Accent-filled call-to-action button look.
static func primary(b: Button) -> Button:
	b.add_theme_stylebox_override("normal", box(ACCENT, 10, 0, LINE, 8))
	b.add_theme_stylebox_override("hover", box(GOLD, 10, 0, LINE, 8))
	b.add_theme_stylebox_override("pressed", box(GOLD, 10, 0, LINE, 8))
	b.add_theme_color_override("font_color", INK)
	b.add_theme_color_override("font_hover_color", INK)
	b.add_theme_color_override("font_focus_color", INK)
	b.add_theme_color_override("font_pressed_color", INK)
	b.add_theme_font_override("font", font(700, 1))
	return b


static func panel(bg := PANEL, radius := RADIUS, pad := 16.0, border := 1, border_color := LINE) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", box(bg, radius, border, border_color, pad))
	return p


static func button(text: String, cb := Callable(), min_w := 0.0, min_h := 46.0) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(min_w, min_h)
	b.focus_mode = Control.FOCUS_ALL
	if cb.is_valid():
		b.pressed.connect(cb)
	return b


static func toggle(text: String, on: bool, cb: Callable) -> CheckButton:
	var b := CheckButton.new()
	b.text = text
	b.button_pressed = on
	b.custom_minimum_size = Vector2(0, 46)
	b.focus_mode = Control.FOCUS_ALL
	b.toggled.connect(cb)
	return b


static func hbox(sep := 10) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	return h


static func vbox(sep := 10) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	return v


static func spacer(h := 8.0) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


static func expander() -> Control:
	var c := Control.new()
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c.size_flags_vertical = Control.SIZE_EXPAND_FILL
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


static func scroll() -> ScrollContainer:
	var s := ScrollContainer.new()
	s.follow_focus = true
	s.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	s.size_flags_vertical = Control.SIZE_EXPAND_FILL
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return s


## Row: caption | slider | value text. `fmt` maps the value to its display string.
static func slider_row(text: String, lo: float, hi: float, step: float, value: float, fmt: Callable, cb: Callable, label_w := 250.0) -> HSlider:
	var row := hbox(14)
	row.custom_minimum_size = Vector2(0, 44)
	var cap := label(text, FONT_SIZE, TEXT_DIM)
	cap.custom_minimum_size = Vector2(label_w, 0)
	cap.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(cap)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = value
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.custom_minimum_size = Vector2(160, 30)
	s.focus_mode = Control.FOCUS_ALL
	row.add_child(s)
	var val := label(fmt.call(value), FONT_SIZE, TEXT, 600)
	val.custom_minimum_size = Vector2(96, 0)
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(val)
	s.value_changed.connect(func(v: float) -> void:
		val.text = fmt.call(v)
		cb.call(v))
	# Keyboard focus shows on the caption too (the grabber highlight alone is easy to miss).
	s.focus_entered.connect(func() -> void: cap.add_theme_color_override("font_color", ACCENT))
	s.focus_exited.connect(func() -> void: cap.add_theme_color_override("font_color", TEXT_DIM))
	s.set_meta(&"row", row)
	s.set_meta(&"value_label", val)
	s.set_meta(&"fmt", fmt)
	return s


## Updates a slider made by slider_row without firing its callback.
static func set_slider(s: HSlider, v: float) -> void:
	s.set_value_no_signal(v)
	var val: Label = s.get_meta(&"value_label")
	var fmt: Callable = s.get_meta(&"fmt")
	val.text = fmt.call(s.value)


static func class_color(cls: String) -> Color:
	return CLASS_COLORS.get(cls, TEXT_DIM)


## Class letter + PI badge with the class colour.
static func class_badge(cls: String, pi: int, size := FONT_SIZE) -> HBoxContainer:
	var h := hbox(0)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var col := class_color(cls)
	var a := PanelContainer.new()
	var sa := box(col, 6, 0, LINE, 2)
	sa.corner_radius_top_right = 0
	sa.corner_radius_bottom_right = 0
	sa.content_margin_left = size * 0.45
	sa.content_margin_right = size * 0.45
	a.add_theme_stylebox_override("panel", sa)
	a.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var la := label(cls, size, INK, 800)
	la.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	a.add_child(la)
	h.add_child(a)
	var b := PanelContainer.new()
	var sbx := box(Color(0.02, 0.02, 0.04, 0.92), 6, 2, col, 2)
	sbx.corner_radius_top_left = 0
	sbx.corner_radius_bottom_left = 0
	sbx.content_margin_left = size * 0.4
	sbx.content_margin_right = size * 0.45
	b.add_theme_stylebox_override("panel", sbx)
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(label(str(pi), size, TEXT, 700))
	h.add_child(b)
	return h


## Keyboard hint chips: [["Enter", "Select"], ...] (all but the last entry are key caps)
static func hint_bar(items: Array) -> HBoxContainer:
	var h := hbox(26)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for it: Array in items:
		var g := hbox(6)
		for k in range(0, it.size() - 1):
			if String(it[k]) == "":
				continue
			var chip := PanelContainer.new()
			var st := box(Color(1, 1, 1, 0.12), 6, 1, Color(1, 1, 1, 0.18), 1)
			st.content_margin_left = 8
			st.content_margin_right = 8
			chip.add_theme_stylebox_override("panel", st)
			chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
			chip.add_child(label(String(it[k]), SMALL - 1, TEXT, 700))
			g.add_child(chip)
		g.add_child(label(String(it[it.size() - 1]), SMALL, TEXT_DIM))
		h.add_child(g)
	return h


static func fmt_time(h: float) -> String:
	# Whole minutes first, so 7 + 59/60 h prints 07:59 rather than a float-truncated 07:58.
	var total := roundi(fposmod(h, 24.0) * 60.0) % 1440
	return "%02d:%02d" % [floori(total / 60.0), total % 60]


static func speed_text(kmh: float) -> String:
	if bool(Settings.get_value("units_mph", false)):
		return "%d mph" % roundi(kmh * 0.621371)
	return "%d km/h" % roundi(kmh)


static func bb_escape(s: String) -> String:
	return s.replace("[", "[lb]")


## Horizontal bar showing a value and an optional change: (before, after) in 0..1.
class DeltaBar extends Control:
	var before: float = 0.5
	var after: float = 0.5
	var color: Color = Color(1.0, 0.56, 0.16)

	func _init() -> void:
		custom_minimum_size = Vector2(120, 10)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func set_values(b: float, a: float) -> void:
		before = clampf(b, 0.0, 1.0)
		after = clampf(a, 0.0, 1.0)
		queue_redraw()

	func _draw() -> void:
		var h := size.y
		var w := size.x
		draw_rect(Rect2(0, 0, w, h), Color(1, 1, 1, 0.09))
		var lo := minf(before, after)
		draw_rect(Rect2(0, 0, w * lo, h), color)
		if after > before + 0.002:
			draw_rect(Rect2(w * before, 0, w * (after - before), h), Color(0.42, 0.9, 0.56))
		elif after < before - 0.002:
			draw_rect(Rect2(w * after, 0, w * (before - after), h), Color(1.0, 0.44, 0.4))
		# Segment ticks for readability.
		for i in range(1, 10):
			draw_rect(Rect2(w * i / 10.0 - 1.0, 0, 2, h), Color(0.03, 0.04, 0.07, 0.55))
