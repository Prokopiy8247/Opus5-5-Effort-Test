extends Control
## Garage (F1 / Tab): the 10-car roster with computed stats, plus paint, upgrades and tuning.
## The camera orbits the current car while open; selecting a car swaps it in place.

const STAT_KEYS := ["speed", "accel", "handling", "braking", "offroad"]
const STAT_NAMES := ["Speed", "Acceleration", "Handling", "Braking", "Off-road"]
const SWATCHES := [Color(0.78, 0.07, 0.05), Color(1.0, 0.4, 0.02), Color(0.98, 0.75, 0.05), Color(0.08, 0.5, 0.18),
	Color(0.0, 0.55, 0.55), Color(0.05, 0.2, 0.75), Color(0.4, 0.08, 0.6), Color(1.0, 0.3, 0.55), Color(0.92, 0.92, 0.9),
	Color(0.65, 0.66, 0.68), Color(0.3, 0.31, 0.33), Color(0.02, 0.02, 0.025), Color(0.75, 0.55, 0.15), Color(0.45, 0.25, 0.12)]

var tabs: TabContainer
var car_list: ItemList
var title: Label
var subtitle: Label
var desc: Label
var specs: Label
var class_badge: Label
var bars := {}
var upgrade_buttons := {}
var tune_sliders := {}
var _orbit := 0.0
var _suppress := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.0)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	var left := PanelContainer.new()
	UITheme.place(left, 0.0, 0.0, 24, 24, 640, 1000)
	left.anchor_bottom = 1.0
	left.offset_bottom = -24
	add_child(left)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	left.add_child(vb)
	vb.add_child(UITheme.label("FESTIVAL GARAGE", 34, UITheme.PINK, true))
	vb.add_child(UITheme.label("Esc / F1 to drive  ·  ↑↓ choose  ·  Enter select", 15, UITheme.DIM))
	tabs = TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(tabs)
	_build_cars_tab()
	_build_paint_tab()
	_build_upgrades_tab()
	_build_tuning_tab()
	# right info panel
	var right := PanelContainer.new()
	UITheme.place(right, 1.0, 1.0, -760, -360, 736, 336)
	add_child(right)
	var rv := VBoxContainer.new()
	right.add_child(rv)
	var hb := HBoxContainer.new()
	class_badge = UITheme.label("A", 44, UITheme.PINK, true)
	class_badge.custom_minimum_size = Vector2(70, 0)
	hb.add_child(class_badge)
	var tv := VBoxContainer.new()
	title = UITheme.label("", 34, UITheme.TEXT, true)
	subtitle = UITheme.label("", 18, UITheme.SUN)
	tv.add_child(title)
	tv.add_child(subtitle)
	hb.add_child(tv)
	rv.add_child(hb)
	desc = UITheme.label("", 17, UITheme.DIM)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.custom_minimum_size = Vector2(700, 0)
	rv.add_child(desc)
	specs = UITheme.label("", 17, UITheme.TEXT)
	rv.add_child(specs)
	var grid := GridContainer.new()
	grid.columns = 2
	for i in STAT_KEYS.size():
		grid.add_child(UITheme.label(STAT_NAMES[i], 16, UITheme.DIM))
		var bar := Control.new()
		bar.custom_minimum_size = Vector2(520, 16)
		bar.draw.connect(_draw_bar.bind(bar, STAT_KEYS[i]))
		grid.add_child(bar)
		bars[STAT_KEYS[i]] = bar
	rv.add_child(grid)


func _build_cars_tab() -> void:
	car_list = ItemList.new()
	car_list.name = "Cars"
	car_list.add_theme_font_size_override("font_size", 22)
	car_list.add_theme_font_override("font", UITheme.font(true))
	for i in Game.cars.size():
		var d := Game.cars[i]
		car_list.add_item("%2d   %s   ·  %s %s" % [i + 1, d.display_name, d.car_class, d.drivetrain_name()])
	car_list.item_selected.connect(_on_car_selected)
	car_list.item_activated.connect(func(_i: int) -> void: toggle())
	tabs.add_child(car_list)


func _build_paint_tab() -> void:
	var vb := VBoxContainer.new()
	vb.name = "Paint"
	vb.add_child(UITheme.label("Body colour", 18, UITheme.SUN, true))
	var g := GridContainer.new()
	g.columns = 7
	for c: Color in SWATCHES:
		var b := Button.new()
		b.custom_minimum_size = Vector2(64, 46)
		var sb := UITheme.panel_box(c, 8)
		b.add_theme_stylebox_override("normal", sb)
		b.add_theme_stylebox_override("hover", UITheme.panel_box(c.lightened(0.15), 8, Color.WHITE))
		b.pressed.connect(_paint.bind("color", c))
		g.add_child(b)
	vb.add_child(g)
	vb.add_child(UITheme.label("Finish", 18, UITheme.SUN, true))
	var fb := HBoxContainer.new()
	for i in CarMaterials.FINISH_NAMES.size():
		var b := Button.new()
		b.text = CarMaterials.FINISH_NAMES[i]
		b.pressed.connect(_paint.bind("finish", i))
		fb.add_child(b)
	vb.add_child(fb)
	vb.add_child(UITheme.label("Livery stripes", 18, UITheme.SUN, true))
	var sbx := HBoxContainer.new()
	for i in 4:
		var b := Button.new()
		b.text = ["None", "Twin", "Side", "Wide"][i]
		b.pressed.connect(_paint.bind("stripe", i))
		sbx.add_child(b)
	vb.add_child(sbx)
	vb.add_child(UITheme.label("Stripe / rim colour", 18, UITheme.SUN, true))
	var g2 := GridContainer.new()
	g2.columns = 7
	for c: Color in SWATCHES:
		var b := Button.new()
		b.custom_minimum_size = Vector2(64, 34)
		b.add_theme_stylebox_override("normal", UITheme.panel_box(c, 8))
		b.pressed.connect(_paint.bind("stripe_color", c))
		b.gui_input.connect(func(ev: InputEvent) -> void:
			if ev is InputEventMouseButton and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_RIGHT and ev.pressed:
				_paint("rim", c))
		g2.add_child(b)
	vb.add_child(g2)
	vb.add_child(UITheme.label("Left click: stripes · Right click: rims", 14, UITheme.DIM))
	tabs.add_child(vb)


func _build_upgrades_tab() -> void:
	var vb := VBoxContainer.new()
	vb.name = "Upgrades"
	for cat: String in Upgrades.CATEGORIES:
		var u := Upgrades.get_upgrade(cat, 1)
		vb.add_child(UITheme.label(cat.capitalize(), 19, UITheme.SUN, true))
		var hb := HBoxContainer.new()
		var group := []
		for lvl in 4:
			var b := Button.new()
			b.text = Upgrades.LEVEL_NAMES[lvl]
			b.toggle_mode = true
			b.custom_minimum_size = Vector2(130, 36)
			b.pressed.connect(_upgrade.bind(cat, lvl))
			hb.add_child(b)
			group.append(b)
		upgrade_buttons[cat] = group
		vb.add_child(hb)
		var d := UITheme.label(u.description, 14, UITheme.DIM)
		vb.add_child(d)
	tabs.add_child(vb)


func _build_tuning_tab() -> void:
	var vb := VBoxContainer.new()
	vb.name = "Tuning"
	var defs := [["final_drive", "Final drive", 0.85, 1.15], ["brake_bias", "Brake bias (front +)", -0.12, 0.12],
		["spring", "Springs", 0.75, 1.3], ["damper", "Dampers", 0.75, 1.3], ["arb_f", "Front anti-roll", 0.5, 1.6],
		["arb_r", "Rear anti-roll", 0.5, 1.6], ["aero", "Downforce", 0.4, 1.6], ["tire_pressure", "Tyre pressure", -1.0, 1.0]]
	for d: Array in defs:
		vb.add_child(UITheme.label(d[1], 17, UITheme.SUN, true))
		var s := HSlider.new()
		s.min_value = d[2]
		s.max_value = d[3]
		s.step = 0.01
		s.custom_minimum_size = Vector2(540, 24)
		s.value_changed.connect(_tune.bind(d[0]))
		vb.add_child(s)
		tune_sliders[d[0]] = s
	var rb := Button.new()
	rb.text = "Reset tuning"
	rb.pressed.connect(func() -> void:
		Game.tuning.erase(Game.player.data.id)
		_refresh()
		Game.main.apply_car_setup())
	vb.add_child(rb)
	tabs.add_child(vb)


func toggle() -> void:
	visible = not visible
	Game.set_ui_focus("garage", visible)
	if visible:
		tabs.current_tab = 0
		_suppress = true
		car_list.select(Game.current_car)
		car_list.ensure_current_is_visible()
		_suppress = false
		car_list.grab_focus()
		_refresh()
	if Game.camera != null:
		Game.camera.enabled_follow = not visible


func _process(delta: float) -> void:
	if not visible or Game.player == null or not is_instance_valid(Game.player):
		return
	_orbit += delta * 0.25
	var car := Game.player
	var xf := car.get_global_transform_interpolated()
	var off := Vector3(sin(_orbit) * 6.2, 1.7, cos(_orbit) * 6.2)
	Game.camera.global_position = xf.origin + off + Vector3(-2.2, 0, 0).rotated(Vector3.UP, _orbit)
	Game.camera.look_at(xf.origin + Vector3(0, 0.6, 0), Vector3.UP)
	Game.camera.fov = 48.0


func _on_car_selected(i: int) -> void:
	if _suppress:
		return
	if i != Game.current_car:
		Game.main.switch_car(i, true)
	_refresh()


func _refresh() -> void:
	if Game.player == null:
		return
	var d := Game.player.data
	title.text = d.display_name
	subtitle.text = "%s %d  ·  %s  ·  %s" % [d.maker, d.model_year, d.body_style, d.drivetrain_name()]
	desc.text = d.description
	class_badge.text = d.car_class
	class_badge.add_theme_color_override("font_color", UITheme.class_color(d.car_class))
	var mods := Game.mods_for(d.id)
	specs.text = "%d kW (%d hp)  ·  %d Nm  ·  %d kg  ·  top ~%d km/h  ·  rating %d" % [
		roundi(d.peak_power_kw() * float(mods.power)), roundi(d.peak_power_kw() * float(mods.power) * 1.341),
		roundi(d.peak_torque() * float(mods.power)), roundi(d.mass * float(mods.mass)), roundi(d.top_speed_kmh * float(mods.top)),
		d.class_rating(mods)]
	for k: String in bars:
		(bars[k] as Control).queue_redraw()
	var lv := Game.upgrades_for(d.id)
	for cat: String in upgrade_buttons:
		for i in 4:
			(upgrade_buttons[cat][i] as Button).button_pressed = int(lv[cat]) == i
	var tn := Game.tuning_for(d.id)
	for k: String in tune_sliders:
		(tune_sliders[k] as HSlider).set_value_no_signal(float(tn[k]))


func _draw_bar(bar: Control, key: String) -> void:
	if Game.player == null:
		return
	var d := Game.player.data
	var base: float = d.ratings()[key]
	var up: float = d.ratings(Game.mods_for(d.id))[key]
	var w := bar.size.x
	bar.draw_rect(Rect2(0, 3, w, 10), Color(1, 1, 1, 0.1))
	bar.draw_rect(Rect2(0, 3, w * up / 10.0, 10), UITheme.PINK)
	bar.draw_rect(Rect2(0, 3, w * base / 10.0, 10), UITheme.CYAN)
	bar.draw_string(UITheme.font(true), Vector2(w - 40, 14), "%.1f" % up, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, UITheme.TEXT)


func _paint(key: String, value: Variant) -> void:
	var p := Game.paint_for(Game.player.data.id)
	p[key] = value
	Game.player.visual.set_paint(p.color, p.finish, p.stripe, p.stripe_color)
	Game.player.visual.set_rim_color(p.rim)


func _upgrade(cat: String, lvl: int) -> void:
	Game.upgrades_for(Game.player.data.id)[cat] = lvl
	Game.main.apply_car_setup()
	_refresh()


func _tune(value: float, key: String) -> void:
	Game.tuning_for(Game.player.data.id)[key] = value
	Game.main.apply_car_setup()
