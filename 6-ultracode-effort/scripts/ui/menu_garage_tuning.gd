extends PanelContainer
## Garage TUNING page: one slider per Tuning.TUNE_SPEC key with per-row reset, a live figure comparison,
## and Apply (rebuilds the car). Values persist in Game.tuning via SaveGame.

const Style := preload("res://scripts/ui/menu_style.gd")
const Stats := preload("res://scripts/ui/menu_car_stats.gd")
const Actions := preload("res://scripts/ui/menu_actions.gd")

var garage: Node
var pending: Dictionary = {}
var sliders: Dictionary = {}
var _help: Label
var _compare: Label
var _apply: Button


func _ready() -> void:
	add_theme_stylebox_override("panel", Style.box(Style.PANEL, 14, 1, Style.LINE, 18))
	var page := Style.vbox(10)
	add_child(page)
	var sc := Style.scroll()
	page.add_child(sc)
	var list := Style.vbox(2)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(list)
	var neutral := Style.box(Color(1, 1, 1, 0.16), 4, 0, Style.LINE, 0)
	neutral.content_margin_top = 4
	neutral.content_margin_bottom = 4
	for key: String in Tuning.TUNE_SPEC:
		var spec: Array = Tuning.TUNE_SPEC[key]
		var s := Style.slider_row(Actions.tune_label(key), float(spec[0]), float(spec[1]), 0.002 if key == "ride_height" else 0.01, float(spec[2]),
			func(v: float) -> String: return Actions.tune_text(key, v), _on_slider.bind(key), 220)
		s.add_theme_stylebox_override("grabber_area", neutral)
		s.add_theme_stylebox_override("grabber_area_highlight", neutral)
		s.tooltip_text = Actions.tune_help(key)
		s.focus_entered.connect(func() -> void: _help.text = Actions.tune_help(key))
		var row: HBoxContainer = s.get_meta(&"row")
		var rst := Style.button("Reset", func() -> void:
			pending.erase(key)
			Style.set_slider(s, float(spec[2]))
			_update(), 92, 38)
		rst.add_theme_font_size_override("font_size", 17)
		rst.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(rst)
		list.add_child(row)
		sliders[key] = s
	_help = Style.label("", 19, Style.TEXT_DIM)
	_help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	page.add_child(_help)
	var cp := Style.panel(Style.CARD, 10, 10)
	_compare = Style.label("", 20, Style.TEXT, 500)
	_compare.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cp.add_child(_compare)
	page.add_child(cp)
	var btns := Style.hbox(8)
	_apply = Style.primary(Style.button("Apply tune", apply, 0, 52))
	_apply.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btns.add_child(_apply)
	btns.add_child(Style.button("Factory defaults", func() -> void:
		pending.clear()
		for k: String in sliders:
			Style.set_slider(sliders[k], float(Tuning.TUNE_SPEC[k][2]))
		_update(), 220, 52))
	btns.add_child(Style.button("Revert", refresh, 120, 52))
	page.add_child(btns)


func focus_first() -> void:
	(sliders[Tuning.TUNE_SPEC.keys()[0]] as HSlider).grab_focus()


## Reloads the applied tune of the current car.
func refresh() -> void:
	var d := Game.current_car_data()
	if d == null:
		return
	pending = Game.get_tuning(d.id).duplicate()
	for k: String in sliders:
		Style.set_slider(sliders[k], float(pending.get(k, Tuning.TUNE_SPEC[k][2])))
	_update()


func _on_slider(v: float, key: String) -> void:
	pending[key] = v
	_update()


func apply() -> void:
	var d := Game.current_car_data()
	if d == null:
		return
	var t := Game.get_tuning(d.id)
	t.clear()
	for k: String in pending:
		if not is_equal_approx(float(pending[k]), float(Tuning.TUNE_SPEC[k][2])):
			t[k] = float(pending[k])
	Actions.rebuild_car()
	garage.toast("Tune applied to the %s" % d.display_name)


func _update() -> void:
	var d := Game.current_car_data()
	if d == null or _compare == null:
		return
	var idx := Game.current_car_index
	var rb: Dictionary = garage.ratings(idx)
	var ra := Stats.ratings(Tuning.build_effective(Game.get_car_catalog()[idx], Game.get_upgrades(d.id), pending))
	_compare.text = "%s   0-100  %.2f → %.2f s     Top  %s → %s     Cornering  %.2f → %.2f g     Braking  %.1f → %.1f m" % [
		d.display_name, rb["zero_100"], ra["zero_100"], Style.speed_text(rb["top_kmh"]), Style.speed_text(ra["top_kmh"]),
		rb["lat_g"], ra["lat_g"], rb["brake_m"], ra["brake_m"]]
	var dirty := not _same(pending, Game.get_tuning(d.id))
	_apply.disabled = not dirty
	_apply.text = "Apply tune" if dirty else "Tune applied"
	for k: String in sliders:
		var sl: HSlider = sliders[k]
		var changed := not is_equal_approx(sl.value, float(Tuning.TUNE_SPEC[k][2]))
		(sl.get_meta(&"value_label") as Label).add_theme_color_override("font_color", Style.GOLD if changed else Style.TEXT_DIM)


static func _same(a: Dictionary, b: Dictionary) -> bool:
	for k: String in Tuning.TUNE_SPEC:
		var dv := float(Tuning.TUNE_SPEC[k][2])
		if not is_equal_approx(float(a.get(k, dv)), float(b.get(k, dv))):
			return false
	return true
