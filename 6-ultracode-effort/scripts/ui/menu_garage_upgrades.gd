extends HBoxContainer
## Garage UPGRADES page: six slots (Tuning.SLOTS) with Stock..Race levels, a before/after comparison
## (PI, power, weight, grip, cornering, braking, 0-100, top speed) and Install, which rebuilds the car.

const Style := preload("res://scripts/ui/menu_style.gd")
const Stats := preload("res://scripts/ui/menu_car_stats.gd")
const Actions := preload("res://scripts/ui/menu_actions.gd")

var garage: Node
var pending: Dictionary = {}
var _level_buttons: Dictionary = {}   # slot -> Array[Button]
var _installed_labels: Dictionary = {}
var _compare: VBoxContainer
var _apply: Button


func _ready() -> void:
	add_theme_constant_override("separation", 18)
	var left := Style.vbox(8)
	left.custom_minimum_size = Vector2(560, 0)
	add_child(left)
	for slot: String in Tuning.SLOTS:
		var p := Style.panel(Style.CARD, 10, 10)
		var v := Style.vbox(6)
		p.add_child(v)
		var h := Style.hbox(10)
		h.add_child(Style.label(Actions.upgrade_name(slot), 22, Style.TEXT, 700))
		h.add_child(Style.expander())
		var inst := Style.caps("", 15, Style.TEXT_FAINT)
		h.add_child(inst)
		_installed_labels[slot] = inst
		v.add_child(h)
		var row := Style.hbox(6)
		var g := ButtonGroup.new()
		var arr: Array[Button] = []
		for lvl in Tuning.MAX_LEVEL + 1:
			var b := Style.button(Actions.level_name(slot, lvl), set_level.bind(slot, lvl), 0, 40)
			b.toggle_mode = true
			b.button_group = g
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			b.add_theme_font_size_override("font_size", 19)
			arr.append(b)
			row.add_child(b)
		_level_buttons[slot] = arr
		v.add_child(row)
		left.add_child(p)

	var right := Style.panel(Style.PANEL, 14, 20)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(right)
	var rv := Style.vbox(10)
	right.add_child(rv)
	rv.add_child(Style.caps("Before  →  after", 17, Style.TEXT_DIM))
	_compare = Style.vbox(10)
	_compare.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rv.add_child(_compare)
	var btns := Style.hbox(8)
	_apply = Style.primary(Style.button("Install upgrades", install, 0, 52))
	_apply.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btns.add_child(_apply)
	btns.add_child(Style.button("All stock", func() -> void:
		for s: String in Tuning.SLOTS:
			pending[s] = 0
		_update(), 150, 52))
	btns.add_child(Style.button("Revert", refresh, 120, 52))
	rv.add_child(btns)


func focus_first() -> void:
	var arr: Array = _level_buttons[Tuning.SLOTS[0]]
	(arr[int(pending.get(Tuning.SLOTS[0], 0))] as Button).grab_focus()


## Reloads the installed levels of the current car.
func refresh() -> void:
	var d := Game.current_car_data()
	if d == null:
		return
	pending = Game.get_upgrades(d.id).duplicate()
	_update()


func set_level(slot: String, lvl: int) -> void:
	pending[slot] = lvl
	_update()


func install() -> void:
	var d := Game.current_car_data()
	if d == null:
		return
	var installed := Game.get_upgrades(d.id)
	for s: String in Tuning.SLOTS:
		installed[s] = int(pending.get(s, 0))
	Actions.rebuild_car()
	garage.toast("Upgrades installed on the %s" % d.display_name)


func _update() -> void:
	var d := Game.current_car_data()
	if d == null or _compare == null:
		return
	var installed := Game.get_upgrades(d.id)
	var dirty := false
	for slot: String in Tuning.SLOTS:
		var arr: Array = _level_buttons[slot]
		var lvl := int(pending.get(slot, 0))
		for i in arr.size():
			(arr[i] as Button).set_pressed_no_signal(i == lvl)
		var il := int(installed.get(slot, 0))
		dirty = dirty or il != lvl
		var inst: Label = _installed_labels[slot]
		inst.text = ("Installed: " + Actions.level_name(slot, il)).to_upper()
		inst.add_theme_color_override("font_color", Style.GOLD if il != lvl else Style.TEXT_FAINT)
	var idx := Game.current_car_index
	var before := Game.effective_car_data(idx)
	var after := Tuning.build_effective(Game.get_car_catalog()[idx], pending, Game.get_tuning(d.id))
	fill_compare(_compare, before, after, garage.ratings(idx), Stats.ratings(after))
	_apply.disabled = not dirty
	_apply.text = "Install upgrades" if dirty else "Installed"


static func fill_compare(box: VBoxContainer, before: CarData, after: CarData, rb: Dictionary, ra: Dictionary) -> void:
	for c in box.get_children():
		c.queue_free()
	var hb := Style.hbox(14)
	hb.add_child(Style.class_badge(Tuning.class_for(rb["pi"]), rb["pi"], 30))
	hb.add_child(Style.label("→", 30, Style.TEXT_FAINT, 700))
	hb.add_child(Style.class_badge(Tuning.class_for(ra["pi"]), ra["pi"], 30))
	var dpi := int(ra["pi"]) - int(rb["pi"])
	if dpi != 0:
		hb.add_child(Style.label("%+d PI" % dpi, 24, Style.GOOD if dpi > 0 else Style.BAD, 700))
	box.add_child(hb)
	box.add_child(Style.spacer(4))
	var rows := [
		["Power", "%d hp", float(rb["hp"]), float(ra["hp"]), 900.0, true],
		["Weight", "%d kg", before.mass, after.mass, 2600.0, false],
		["Tyre grip", "%.2f", before.tire_grip, after.tire_grip, 1.6, true],
		["Cornering", "%.2f g", float(rb["lat_g"]), float(ra["lat_g"]), 1.7, true],
		["100-0 braking", "%.1f m", float(rb["brake_m"]), float(ra["brake_m"]), 60.0, false],
		["0-100 km/h", "%.2f s", float(rb["zero_100"]), float(ra["zero_100"]), 12.0, false],
		["Top speed", "speed", float(rb["top_kmh"]), float(ra["top_kmh"]), 380.0, true],
	]
	for r: Array in rows:
		box.add_child(_compare_row(r[0], r[1], r[2], r[3], r[4], r[5]))


static func _compare_row(text: String, fmt: String, a: float, b: float, scale_max: float, higher_better: bool) -> Control:
	var v := Style.vbox(4)
	var h := Style.hbox(10)
	var l := Style.label(text, 19, Style.TEXT_DIM, 500)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(l)
	var same := is_equal_approx(snappedf(a, 0.01), snappedf(b, 0.01))
	var better := (b > a) == higher_better
	h.add_child(Style.label(_fmt(fmt, a), 20, Style.TEXT if same else Style.TEXT_DIM, 600))
	if not same:
		h.add_child(Style.label("→", 20, Style.TEXT_FAINT))
		h.add_child(Style.label(_fmt(fmt, b), 20, Style.GOOD if better else Style.BAD, 700))
	v.add_child(h)
	var bar := Style.DeltaBar.new()
	bar.custom_minimum_size = Vector2(0, 8)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if higher_better:
		bar.set_values(a / scale_max, b / scale_max)
	else:
		bar.set_values(1.0 - a / scale_max, 1.0 - b / scale_max)
	v.add_child(bar)
	return v


## fmt "speed": x is km/h, shown in the user's units (Settings "units_mph").
static func _fmt(fmt: String, x: float) -> String:
	if fmt == "speed":
		return Style.speed_text(x)
	return fmt % (roundi(x) if fmt.contains("%d") else x)
