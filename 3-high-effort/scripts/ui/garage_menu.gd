extends Control
## Garage (Tab / F1 / Start): the 10-car roster with stats, plus Paint, Upgrades and Tuning.
## Selecting a car swaps it in place; the camera orbits the car while the garage is open.

var main: Node
var root: PanelContainer
var list: ItemList
var title: Label
var subtitle: Label
var badge_holder: HBoxContainer
var desc: Label
var stat_box: VBoxContainer
var tabs: TabContainer
var paint_box: VBoxContainer
var upgrade_box: VBoxContainer
var tune_box: VBoxContainer
var open := false
var _selected := 0

const SWATCHES := [
	Color(0.82, 0.07, 0.05), Color(0.95, 0.5, 0.05), Color(0.95, 0.8, 0.1), Color(0.45, 0.82, 0.12),
	Color(0.08, 0.45, 0.25), Color(0.1, 0.6, 0.6), Color(0.12, 0.32, 0.85), Color(0.05, 0.1, 0.3),
	Color(0.45, 0.15, 0.7), Color(0.95, 0.4, 0.65), Color(0.93, 0.93, 0.95), Color(0.7, 0.72, 0.75),
	Color(0.35, 0.36, 0.38), Color(0.03, 0.03, 0.035), Color(0.55, 0.78, 0.72), Color(0.85, 0.65, 0.2),
]


func init_ui(m: Node) -> void:
	main = m
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	root = PanelContainer.new()
	root.add_theme_stylebox_override("panel", UIStyle.panel(Color(0.03, 0.04, 0.07, 0.86), 14, Color(1, 1, 1, 0.08)))
	UIStyle.place(root, Control.PRESET_LEFT_WIDE, 30, 30, 900, -30)
	add_child(root)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	root.add_child(v)
	var head := UIStyle.label("GARAGE", 30, UIStyle.ACCENT, true)
	v.add_child(head)
	var hint := UIStyle.label("Pick a car — it is delivered right where you are. Tab to close.", 15, UIStyle.TEXT_DIM)
	v.add_child(hint)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 16)
	h.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(h)
	list = ItemList.new()
	list.custom_minimum_size = Vector2(300, 0)
	list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list.add_theme_font_size_override("font_size", 19)
	list.add_theme_stylebox_override("panel", UIStyle.panel(Color(0, 0, 0, 0.35), 8))
	list.item_selected.connect(_on_select)
	list.item_activated.connect(func(i: int) -> void: _drive(i))
	h.add_child(list)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 8)
	h.add_child(right)
	title = UIStyle.label("", 30, UIStyle.TEXT, true)
	right.add_child(title)
	subtitle = UIStyle.label("", 16, UIStyle.TEXT_DIM)
	right.add_child(subtitle)
	badge_holder = HBoxContainer.new()
	right.add_child(badge_holder)
	desc = UIStyle.label("", 16, UIStyle.TEXT)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.custom_minimum_size = Vector2(480, 0)
	right.add_child(desc)
	stat_box = VBoxContainer.new()
	right.add_child(stat_box)
	var drive_btn := UIStyle.button("DRIVE THIS CAR", 20)
	drive_btn.pressed.connect(func() -> void: _drive(_selected))
	right.add_child(drive_btn)
	tabs = TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tabs.custom_minimum_size = Vector2(0, 330)
	tabs.add_theme_font_size_override("font_size", 17)
	right.add_child(tabs)
	paint_box = VBoxContainer.new()
	paint_box.name = "Paint"
	tabs.add_child(paint_box)
	upgrade_box = VBoxContainer.new()
	upgrade_box.name = "Upgrades"
	tabs.add_child(upgrade_box)
	var tune_scroll := ScrollContainer.new()
	tune_scroll.name = "Tuning"
	tabs.add_child(tune_scroll)
	tune_box = VBoxContainer.new()
	tune_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tune_scroll.add_child(tune_box)
	for i in Game.cars.size():
		var c := Game.cars[i]
		list.add_item("%2d  %s" % [i + 1, c.display_name])
	visible = false


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("garage_menu"):
		toggle()
		get_viewport().set_input_as_handled()
	elif open and event.is_action_pressed("ui_cancel"):
		toggle()
		get_viewport().set_input_as_handled()


func toggle() -> void:
	open = not open
	visible = open
	if main.player:
		main.player.controls_enabled = not open
	main.camera.set("orbit", open)
	if open:
		_selected = Game.current_car_index
		list.select(_selected)
		_refresh()
		list.grab_focus()
	else:
		Game.save_game()


func _on_select(i: int) -> void:
	_selected = i
	_refresh()


func _drive(i: int) -> void:
	if i != Game.current_car_index:
		main.spawn_car(i, main.player.global_transform)
		main.player.controls_enabled = not open
		Tuning.apply(main.player)
	_selected = i
	_refresh()


func _refresh() -> void:
	var c := Game.cars[_selected]
	var pi := Tuning.pi_of(c)
	var cls := Tuning.class_of(pi)
	title.text = c.display_name
	subtitle.text = "%s  •  %d  •  %s  •  %s  •  %d hp  •  %.0f kg  •  %s" % [c.maker, c.year, c.body_style,
		["FWD", "RWD", "AWD"][c.drivetrain], c.power_hp, c.mass, c.engine_layout]
	for ch in badge_holder.get_children():
		ch.queue_free()
	badge_holder.add_child(UIStyle.class_badge(cls, pi, 18))
	var top := UIStyle.label("   top speed %d km/h" % roundi(c.top_speed_kmh), 16, UIStyle.TEXT_DIM)
	badge_holder.add_child(top)
	desc.text = c.description
	for ch in stat_box.get_children():
		ch.queue_free()
	var ups: Dictionary = Game.custom_for(c.id).get("upgrades", {})
	var boost := func(key: String) -> float: return float(ups.get(key, 0)) * 0.35
	var stats := [["Speed", c.stat_speed + boost.call("engine")], ["Handling", c.stat_handling + boost.call("tires") + boost.call("suspension") * 0.5],
		["Acceleration", c.stat_accel + boost.call("engine") + boost.call("weight")], ["Launch", c.stat_launch + boost.call("tires")],
		["Braking", c.stat_braking + boost.call("brakes")], ["Off-road", c.stat_offroad]]
	for s in stats:
		var row := HBoxContainer.new()
		var l := UIStyle.label(s[0], 16, UIStyle.TEXT_DIM)
		l.custom_minimum_size = Vector2(120, 0)
		row.add_child(l)
		row.add_child(UIStyle.bar(minf(s[1], 10.0), 10.0, UIStyle.ACCENT, 300.0))
		row.add_child(UIStyle.label(" %.1f" % minf(s[1], 10.0), 15, UIStyle.TEXT))
		stat_box.add_child(row)
	_build_paint(c)
	_build_upgrades(c)
	_build_tuning(c)


func _current_is_selected() -> bool:
	return _selected == Game.current_car_index and main.player != null


func _build_paint(c: CarSpec) -> void:
	for ch in paint_box.get_children():
		ch.queue_free()
	var cust := Game.custom_for(c.id)
	paint_box.add_child(UIStyle.label("Primary colour", 16, UIStyle.TEXT_DIM))
	var grid := GridContainer.new()
	grid.columns = 8
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	paint_box.add_child(grid)
	for col in SWATCHES:
		var b := Button.new()
		b.custom_minimum_size = Vector2(44, 32)
		var sb := UIStyle.panel(col, 6, Color(1, 1, 1, 0.3))
		b.add_theme_stylebox_override("normal", sb)
		b.add_theme_stylebox_override("hover", UIStyle.panel(col.lightened(0.15), 6, UIStyle.ACCENT))
		b.add_theme_stylebox_override("pressed", UIStyle.panel(col, 6, UIStyle.ACCENT))
		var cc: Color = col
		b.pressed.connect(func() -> void: _set_paint(c, cc, ""))
		grid.add_child(b)
	paint_box.add_child(UIStyle.label("Finish", 16, UIStyle.TEXT_DIM))
	var fin := HBoxContainer.new()
	paint_box.add_child(fin)
	for f in ["gloss", "metallic", "matte", "pearl"]:
		var b := UIStyle.button(f.capitalize(), 16)
		if str(cust.get("finish", c.paint_finish)) == f:
			b.add_theme_color_override("font_color", UIStyle.ACCENT)
		var ff: String = f
		b.pressed.connect(func() -> void: _set_paint(c, Color(), ff))
		fin.add_child(b)
	paint_box.add_child(UIStyle.label("Rims", 16, UIStyle.TEXT_DIM))
	var rims := HBoxContainer.new()
	paint_box.add_child(rims)
	for rc in [Color(0.78, 0.79, 0.8), Color(0.1, 0.1, 0.11), Color(0.85, 0.65, 0.2), Color(0.95, 0.95, 0.95), Color(0.35, 0.36, 0.38)]:
		var b := Button.new()
		b.custom_minimum_size = Vector2(44, 32)
		b.add_theme_stylebox_override("normal", UIStyle.panel(rc, 16, Color(1, 1, 1, 0.3)))
		b.add_theme_stylebox_override("hover", UIStyle.panel(rc, 16, UIStyle.ACCENT))
		var rcc: Color = rc
		b.pressed.connect(func() -> void:
			Game.custom_for(c.id)["rim_color"] = rcc
			if _current_is_selected():
				main.player.set_rim_color(rcc))
		rims.add_child(b)
	var reset := UIStyle.button("Factory paint", 15)
	reset.pressed.connect(func() -> void:
		var cu := Game.custom_for(c.id)
		cu.erase("color")
		cu.erase("finish")
		cu.erase("rim_color")
		if _current_is_selected():
			main.player.apply_paint(c.paint_color, c.paint_finish)
			main.player.set_rim_color(c.rim_color)
		_build_paint(c))
	paint_box.add_child(reset)


func _set_paint(c: CarSpec, col: Color, finish: String) -> void:
	var cust := Game.custom_for(c.id)
	if col != Color():
		cust["color"] = col
	if finish != "":
		cust["finish"] = finish
	if _current_is_selected():
		main.player.apply_paint(cust.get("color", c.paint_color), cust.get("finish", c.paint_finish))
	if finish != "":
		_build_paint(c)


func _build_upgrades(c: CarSpec) -> void:
	for ch in upgrade_box.get_children():
		ch.queue_free()
	var ups: Dictionary = Game.custom_for(c.id).get("upgrades", {})
	upgrade_box.add_child(UIStyle.label("Each level adds performance and raises the car's PI.", 15, UIStyle.TEXT_DIM))
	for d in Tuning.defs():
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		var l := UIStyle.label(d.display_name, 17, UIStyle.TEXT)
		l.custom_minimum_size = Vector2(160, 0)
		row.add_child(l)
		var lvl := int(ups.get(d.key, 0))
		for i in d.level_names.size():
			var b := UIStyle.button(d.level_names[i], 15)
			b.custom_minimum_size = Vector2(78, 0)
			if i == lvl:
				b.add_theme_stylebox_override("normal", UIStyle.panel(Color(0.35, 0.26, 0.08, 0.95), 8, UIStyle.ACCENT))
			var dk: String = d.key
			var ii: int = i
			b.pressed.connect(func() -> void:
				var cu := Game.custom_for(c.id)
				if not cu.has("upgrades"):
					cu["upgrades"] = {}
				cu.upgrades[dk] = ii
				if _current_is_selected():
					Tuning.apply(main.player)
				_refresh())
			row.add_child(b)
		upgrade_box.add_child(row)


func _build_tuning(c: CarSpec) -> void:
	for ch in tune_box.get_children():
		ch.queue_free()
	var cust := Game.custom_for(c.id)
	if not cust.has("tune"):
		cust["tune"] = {}
	var tune: Dictionary = cust.tune
	for key in Tuning.SLIDERS:
		var spec_s: Array = Tuning.SLIDERS[key]
		var row := HBoxContainer.new()
		var l := UIStyle.label(spec_s[3], 16, UIStyle.TEXT)
		l.custom_minimum_size = Vector2(190, 0)
		row.add_child(l)
		var sl := HSlider.new()
		sl.min_value = spec_s[0]
		sl.max_value = spec_s[1]
		sl.step = (spec_s[1] - spec_s[0]) / 40.0
		sl.value = float(tune.get(key, spec_s[2]))
		sl.custom_minimum_size = Vector2(240, 24)
		var val := UIStyle.label("%.2f %s" % [sl.value, spec_s[4]], 15, UIStyle.ACCENT)
		var kk: String = key
		sl.value_changed.connect(func(v: float) -> void:
			tune[kk] = v
			val.text = "%.2f %s" % [v, Tuning.SLIDERS[kk][4]]
			if _current_is_selected():
				Tuning.apply(main.player))
		row.add_child(sl)
		row.add_child(val)
		tune_box.add_child(row)
	var reset := UIStyle.button("Reset tuning", 15)
	reset.pressed.connect(func() -> void:
		cust["tune"] = {}
		if _current_is_selected():
			Tuning.apply(main.player)
		_build_tuning(c))
	tune_box.add_child(reset)
