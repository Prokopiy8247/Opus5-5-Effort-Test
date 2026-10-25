extends HBoxContainer
## Garage CARS page: the 10-car roster as cards (left) and the focused car's sheet (right).
## Enter / click on a card spawns that car where the player is; the menu stays open.

const Style := preload("res://scripts/ui/menu_style.gd")
const Stats := preload("res://scripts/ui/menu_car_stats.gd")

## The garage menu (ratings cache + toast).
var garage: Node
var cards: Array[Button] = []
var _detail: VBoxContainer


func _ready() -> void:
	add_theme_constant_override("separation", 18)
	var sc := Style.scroll()
	sc.custom_minimum_size = Vector2(440, 0)
	sc.size_flags_horizontal = Control.SIZE_FILL
	add_child(sc)
	var list := Style.vbox(8)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(list)
	for i in Game.get_car_catalog().size():
		var card := _make_card(i)
		list.add_child(card)
		cards.append(card)
	var dp := Style.panel(Style.PANEL, 14, 22)
	dp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(dp)
	_detail = Style.vbox(12)
	dp.add_child(_detail)


func refresh() -> void:
	for i in cards.size():
		var b := cards[i]
		var r: Dictionary = garage.ratings(i)
		var cur := i == Game.current_car_index
		var slot: Control = b.find_child("BadgeSlot", true, false)
		for c in slot.get_children():
			c.queue_free()
		var badge := Style.class_badge(Tuning.class_for(r["pi"]), r["pi"], 20)
		slot.add_child(badge)
		badge.set_anchors_and_offsets_preset(Control.PRESET_CENTER_RIGHT, Control.PRESET_MODE_MINSIZE)
		(b.find_child("Tag", true, false) as Control).visible = cur
		(b.find_child("Strip", false, false) as Control).visible = cur
		(b.find_child("Name", true, false) as Label).add_theme_color_override("font_color", Style.GOLD if cur else Style.TEXT)
		var st := Style.box(Color(0.16, 0.11, 0.08, 0.96) if cur else Style.CARD, 10, 2 if cur else 1, Color(Style.ACCENT, 0.7) if cur else Style.LINE, 8)
		b.add_theme_stylebox_override("normal", st)
	show_car(Game.current_car_index)


func focus_first() -> void:
	if not cards.is_empty():
		cards[clampi(Game.current_car_index, 0, cards.size() - 1)].grab_focus()


func _make_card(i: int) -> Button:
	var d := Game.get_car_catalog()[i]
	var b := Button.new()
	b.custom_minimum_size = Vector2(420, 74)
	b.focus_mode = Control.FOCUS_ALL
	var hover := Style.box(Style.PANEL_HI, 10, 1, Color(1, 1, 1, 0.14), 8)
	b.add_theme_stylebox_override("normal", Style.box(Style.CARD, 10, 1, Style.LINE, 8))
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", hover)
	b.add_theme_stylebox_override("hover_pressed", hover)
	var mc := MarginContainer.new()
	mc.add_theme_constant_override("margin_left", 18)
	mc.add_theme_constant_override("margin_right", 14)
	mc.add_theme_constant_override("margin_top", 8)
	mc.add_theme_constant_override("margin_bottom", 8)
	b.add_child(mc)
	mc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var h := Style.hbox(10)
	mc.add_child(h)
	var v := Style.vbox(0)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	var nm := Style.label(d.display_name, 25, Style.TEXT, 700)
	nm.name = "Name"
	v.add_child(nm)
	v.add_child(Style.label("%s  ·  %s" % [d.category, d.drivetrain_name()], 17, Style.TEXT_DIM))
	h.add_child(v)
	var tag := Style.caps("Driving", 15, Style.ACCENT)
	tag.name = "Tag"
	tag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(tag)
	var badge_slot := Control.new()
	badge_slot.name = "BadgeSlot"
	badge_slot.custom_minimum_size = Vector2(92, 0)
	h.add_child(badge_slot)
	var strip := ColorRect.new()
	strip.name = "Strip"
	strip.color = Style.ACCENT
	strip.anchor_bottom = 1.0
	strip.offset_right = 5
	strip.offset_top = 10
	strip.offset_bottom = -10
	b.add_child(strip)
	_ignore_mouse(mc)
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.pressed.connect(_on_card_pressed.bind(i))
	b.focus_entered.connect(show_car.bind(i))
	b.mouse_entered.connect(show_car.bind(i))
	return b


func _ignore_mouse(n: Node) -> void:
	if n is Control:
		(n as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	for c in n.get_children():
		_ignore_mouse(c)


func _on_card_pressed(i: int) -> void:
	if i != Game.current_car_index:
		Game.spawn_car(i, true)
		garage.toast("Now driving %s" % Game.get_car_catalog()[i].display_name, Style.ACCENT)
	refresh()
	show_car(i)


func show_car(i: int) -> void:
	if _detail == null or i < 0 or i >= Game.get_car_catalog().size():
		return
	for c in _detail.get_children():
		c.queue_free()
	var d := Game.effective_car_data(i)
	var r: Dictionary = garage.ratings(i)
	var top := Style.hbox(16)
	var tv := Style.vbox(2)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.add_child(Style.label(d.display_name, 44, Style.TEXT, 700, 1))
	tv.add_child(Style.label("%s  ·  %s  ·  %s" % [d.category, d.year_style, d.drivetrain_name()], 21, Style.TEXT_DIM, 500))
	top.add_child(tv)
	var badge := Style.class_badge(Tuning.class_for(r["pi"]), r["pi"], 30)
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(badge)
	_detail.add_child(top)
	_detail.add_child(Style.accent_bar(90, 4))

	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 26)
	grid.add_theme_constant_override("v_separation", 10)
	var specs := [
		["Power", "%d hp" % roundi(r["hp"])],
		["Weight", "%s kg" % _thousands(roundi(r["kg"]))],
		["0-100 km/h", "%.1f s" % r["zero_100"]],
		["Top speed", Style.speed_text(r["top_kmh"])],
		["Power / weight", "%d hp/t" % roundi(r["hp"] / (r["kg"] / 1000.0))],
		["100-0 braking", "%.1f m" % r["brake_m"]],
		["Engine", "%d-cyl%s" % [d.cylinders, " turbo" if d.turbo else ""]],
		["Torque", "%d Nm" % roundi(d.peak_torque)],
		["Gearbox", "%d-speed" % d.gear_ratios.size()],
	]
	for s: Array in specs:
		var cell := Style.vbox(0)
		cell.custom_minimum_size = Vector2(190, 0)
		cell.add_child(Style.caps(s[0], 15, Style.TEXT_FAINT))
		cell.add_child(Style.label(s[1], 28, Style.TEXT, 700))
		grid.add_child(cell)
	_detail.add_child(grid)
	_detail.add_child(Style.spacer(2))
	for k: String in Stats.STAT_NAMES:
		_detail.add_child(stat_row(k, float(r[k])))
	_detail.add_child(Style.spacer(2))
	var blurb := Style.label(d.blurb, 21, Style.TEXT_DIM)
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	blurb.custom_minimum_size = Vector2(560, 0)
	_detail.add_child(blurb)
	_detail.add_child(Style.expander())
	if i == Game.current_car_index:
		_detail.add_child(Style.caps("You are driving this car", 18, Style.ACCENT))
	else:
		_detail.add_child(Style.hint_bar([["Enter", "Drive the %s" % d.display_name]]))


static func stat_row(text: String, v: float) -> HBoxContainer:
	var row := Style.hbox(14)
	var l := Style.label(text, 19, Style.TEXT_DIM, 500)
	l.custom_minimum_size = Vector2(150, 0)
	row.add_child(l)
	var bar := Style.DeltaBar.new()
	bar.custom_minimum_size = Vector2(300, 12)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.set_values(v / 10.0, v / 10.0)
	row.add_child(bar)
	var n := Style.label("%.1f" % v, 20, Style.TEXT, 700)
	n.custom_minimum_size = Vector2(48, 0)
	n.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(n)
	return row


static func _thousands(n: int) -> String:
	var s := str(n)
	return s.substr(0, s.length() - 3) + "," + s.substr(s.length() - 3) if s.length() > 3 else s
