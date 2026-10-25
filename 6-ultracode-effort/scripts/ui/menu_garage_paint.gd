extends PanelContainer
## Garage PAINT page: one colour picker (swatches + HSV) applied to the body, stripes or rims,
## plus finish and stripe pattern. Every change is previewed live on the player car.

const Style := preload("res://scripts/ui/menu_style.gd")
const Actions := preload("res://scripts/ui/menu_actions.gd")
const SWATCH := Vector2(92, 58)
const TARGETS: Array[String] = ["Body", "Stripes", "Rims"]
const FINISHES: Array[String] = ["Gloss", "Matte", "Metallic"]
const STRIPES: Array[String] = ["None", "Twin", "Centre", "Side", "Rally", "Two-tone"]

var garage: Node
## 0 body, 1 stripes, 2 rims
var target: int = 0
var _target_buttons: Array[Button] = []
var _swatches: Array[Button] = []
var _finish_buttons: Array[Button] = []
var _stripe_buttons: Array[Button] = []
var _hue: HSlider
var _sat: HSlider
var _val: HSlider
var _sat_grad := Gradient.new()
var _val_grad := Gradient.new()
var _preview: Panel
var _hex_label: Label
var _syncing: bool = false


func _ready() -> void:
	add_theme_stylebox_override("panel", Style.box(Style.PANEL, 14, 1, Style.LINE, 18))
	var sc := Style.scroll()
	add_child(sc)
	var page := Style.vbox(14)
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(page)

	page.add_child(_group_row("Paint", TARGETS, _target_buttons, set_target, 150))
	var grid := GridContainer.new()
	grid.columns = 8
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	for k: String in Game.PAINT_COLORS:
		var c: Color = Game.PAINT_COLORS[k]
		var sw := Button.new()
		sw.custom_minimum_size = SWATCH
		sw.focus_mode = Control.FOCUS_ALL
		sw.tooltip_text = k.capitalize()
		for st: String in ["normal", "hover", "pressed", "hover_pressed"]:
			sw.add_theme_stylebox_override(st, Style.box(c, 10, 2 if st == "normal" else 3, Color(1, 1, 1, 0.12) if st == "normal" else Color(1, 1, 1, 0.6), 0))
		sw.set_meta(&"color", c)
		sw.pressed.connect(pick_color.bind(c))
		grid.add_child(sw)
		_swatches.append(sw)
	page.add_child(grid)

	var custom := Style.panel(Style.CARD, 12, 14)
	var cv := Style.vbox(4)
	custom.add_child(cv)
	var ch := Style.hbox(16)
	ch.add_child(Style.caps("Custom colour", 17, Style.TEXT_DIM))
	ch.add_child(Style.expander())
	_hex_label = Style.label("#FFFFFF", 20, Style.TEXT, 600)
	ch.add_child(_hex_label)
	_preview = Panel.new()
	_preview.custom_minimum_size = Vector2(120, 30)
	ch.add_child(_preview)
	cv.add_child(ch)
	_hue = _hsv_slider("Hue", 359.0, _hue_gradient())
	cv.add_child(_hue.get_meta(&"row"))
	_sat = _hsv_slider("Saturation", 100.0, _sat_grad)
	cv.add_child(_sat.get_meta(&"row"))
	_val = _hsv_slider("Brightness", 100.0, _val_grad)
	cv.add_child(_val.get_meta(&"row"))
	page.add_child(custom)

	page.add_child(_group_row("Finish", FINISHES, _finish_buttons, set_finish, 150))
	var srow := _group_row("Stripes", STRIPES, _stripe_buttons, set_stripes, 0)
	for b in _stripe_buttons:
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.add_child(srow)
	var rrow := Style.hbox(8)
	rrow.add_child(_section("Rims"))
	rrow.add_child(Style.button("Factory finish", func() -> void:
		Game.set_rim_color(Color(-1, -1, -1))
		refresh(), 220))
	var note := Style.label("Choose Rims above, then a colour, to paint the wheels", 18, Style.TEXT_FAINT)
	note.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	rrow.add_child(note)
	page.add_child(rrow)


func focus_first() -> void:
	_target_buttons[target].grab_focus()


func _group_row(title: String, names: Array[String], into: Array[Button], cb: Callable, w: float) -> HBoxContainer:
	var row := Style.hbox(8)
	row.add_child(_section(title))
	var g := ButtonGroup.new()
	for i in names.size():
		var b := Style.button(names[i], cb.bind(i), w)
		b.toggle_mode = true
		b.button_group = g
		into.append(b)
		row.add_child(b)
	return row


func _section(text: String) -> Label:
	var l := Style.caps(text, 17, Style.TEXT_DIM)
	l.custom_minimum_size = Vector2(150, 0)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return l


func _hue_gradient() -> Gradient:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 1.0 / 6.0, 2.0 / 6.0, 0.5, 4.0 / 6.0, 5.0 / 6.0, 1.0])
	g.colors = PackedColorArray([Color.RED, Color.YELLOW, Color.GREEN, Color.CYAN, Color.BLUE, Color.MAGENTA, Color.RED])
	return g


func _hsv_slider(text: String, hi: float, grad: Gradient) -> HSlider:
	var s := Style.slider_row(text, 0.0, hi, 1.0, 0.0, func(v: float) -> String: return str(roundi(v)), func(_v: float) -> void: _on_hsv(), 170)
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.width = 256
	gt.height = 8
	gt.fill_to = Vector2(1, 0)
	var track := StyleBoxTexture.new()
	track.texture = gt
	track.content_margin_top = 9
	track.content_margin_bottom = 9
	s.add_theme_stylebox_override("slider", track)
	s.add_theme_stylebox_override("grabber_area", StyleBoxEmpty.new())
	s.add_theme_stylebox_override("grabber_area_highlight", StyleBoxEmpty.new())
	return s


# ------------------------------------------------------------------ actions (public for tests)

func set_target(i: int) -> void:
	target = i
	refresh()


func pick_color(c: Color) -> void:
	_apply_color(c)
	refresh()


func set_finish(i: int) -> void:
	Game.set_paint(Actions.current_paint().get("color", Color.RED), i)
	refresh()


func set_stripes(i: int) -> void:
	Game.set_paint(Actions.current_paint().get("color", Color.RED), -1, i)
	refresh()


func _on_hsv() -> void:
	if _syncing:
		return
	var c := Color.from_hsv(_hue.value / 360.0, _sat.value / 100.0, _val.value / 100.0)
	_apply_color(c)
	_update_visuals(c)


func _apply_color(c: Color) -> void:
	var p := Actions.current_paint()
	match target:
		0:
			Game.set_paint(c)
		1:
			# Picking a stripe colour on a plain car switches twin stripes on so the change is visible.
			var stripes := int(p.get("stripes", 0))
			Game.set_paint(p.get("color", Color.RED), -1, stripes if stripes > 0 else 1, c)
			if stripes == 0:
				refresh()
		2:
			Game.set_rim_color(c)


func _target_color() -> Color:
	var p := Actions.current_paint()
	match target:
		1:
			return p.get("stripe_color", Color.WHITE)
		2:
			var rc: Color = p.get("rim_color", Color(-1, -1, -1))
			return rc if rc.r >= 0.0 else Color(0.75, 0.76, 0.78)
	return p.get("color", Color.RED)


func refresh() -> void:
	if _hue == null or Game.current_car_data() == null:
		return
	var p := Actions.current_paint()
	for i in _target_buttons.size():
		_target_buttons[i].set_pressed_no_signal(i == target)
	for i in _finish_buttons.size():
		_finish_buttons[i].set_pressed_no_signal(i == int(p.get("finish", 0)))
	for i in _stripe_buttons.size():
		_stripe_buttons[i].set_pressed_no_signal(i == int(p.get("stripes", 0)))
	var c := _target_color()
	for sw in _swatches:
		var sc: Color = sw.get_meta(&"color")
		var sel := Actions.same_color(sc, c)
		sw.add_theme_stylebox_override("normal", Style.box(sc, 10, 4 if sel else 2, Color.WHITE if sel else Color(1, 1, 1, 0.12), 0))
	_syncing = true
	Style.set_slider(_hue, c.h * 360.0)
	Style.set_slider(_sat, c.s * 100.0)
	Style.set_slider(_val, c.v * 100.0)
	_syncing = false
	_update_visuals(c)


func _update_visuals(c: Color) -> void:
	var h := _hue.value / 360.0
	var v := maxf(_val.value / 100.0, 0.25)
	_sat_grad.set_color(0, Color.from_hsv(h, 0.0, v))
	_sat_grad.set_color(1, Color.from_hsv(h, 1.0, v))
	_val_grad.set_color(0, Color.BLACK)
	_val_grad.set_color(1, Color.from_hsv(h, _sat.value / 100.0, 1.0))
	_preview.add_theme_stylebox_override("panel", Style.box(c, 8, 2, Color(1, 1, 1, 0.3), 0))
	_hex_label.text = "#" + c.to_html(false).to_upper()
