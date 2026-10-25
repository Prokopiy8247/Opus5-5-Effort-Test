extends "res://scripts/ui/menu_base.gd"
## Developer console (toggle_console: ` / F10). Drop-down log + input line with history and tab completion.
## Commands go through the Game / Settings / SaveGame APIs only. execute(line) is public for tests.

const Actions := preload("res://scripts/ui/menu_actions.gd")
const Stats := preload("res://scripts/ui/menu_car_stats.gd")
const MAX_PARAGRAPHS := 500
const HEIGHT_FRAC := 0.46

var _panel: PanelContainer
var _log: RichTextLabel
var _line: LineEdit
var _hint: Label
var _commands: Dictionary = {}
var _order: PackedStringArray = []
var _history: PackedStringArray = []
var _hist_pos: int = -1
var _draft: String = ""
var _slide: Tween


func _init() -> void:
	super._init()
	menu_id = &"console"
	toggle_action = &"toggle_console"
	captures_keys = true


func _build() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_register_commands()
	_panel = PanelContainer.new()
	var st := Style.box(Color(0.025, 0.03, 0.055, 0.965), 0, 0, Style.LINE, 18)
	st.corner_radius_bottom_left = 16
	st.corner_radius_bottom_right = 16
	st.border_width_bottom = 3
	st.border_color = Style.ACCENT
	st.shadow_color = Color(0, 0, 0, 0.45)
	st.shadow_size = 18
	st.content_margin_left = 34
	st.content_margin_right = 34
	_panel.add_theme_stylebox_override("panel", st)
	_panel.anchor_right = 1.0
	_panel.anchor_bottom = HEIGHT_FRAC
	_panel.offset_left = 24
	_panel.offset_right = -24
	add_child(_panel)
	var v := Style.vbox(8)
	_panel.add_child(v)

	var head := Style.hbox(14)
	var dot := ColorRect.new()
	dot.color = Style.ACCENT
	dot.custom_minimum_size = Vector2(10, 10)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(dot)
	head.add_child(Style.label("CONSOLE", 22, Style.TEXT, 700, 3))
	head.add_child(Style.label(Game.GAME_TITLE, 18, Style.TEXT_FAINT, 400, 1))
	head.add_child(Style.expander())
	head.add_child(Style.hint_bar([["Tab", "Complete"], ["Up", "Down", "History"], ["Esc", "Close"]]))
	v.add_child(head)

	_log = RichTextLabel.new()
	_log.bbcode_enabled = true
	_log.scroll_following = true
	_log.selection_enabled = true
	_log.focus_mode = Control.FOCUS_NONE
	_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_log.add_theme_font_size_override("normal_font_size", 20)
	_log.add_theme_font_size_override("bold_font_size", 20)
	_log.add_theme_font_size_override("mono_font_size", 20)
	v.add_child(_log)

	_hint = Style.label("", 18, Style.TEXT_FAINT)
	_hint.clip_text = true
	_hint.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	v.add_child(_hint)

	var row := Style.hbox(10)
	var prompt := Style.label(">", 26, Style.ACCENT, 700)
	prompt.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(prompt)
	_line = LineEdit.new()
	_line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_line.placeholder_text = "Type a command - help lists them all"
	_line.keep_editing_on_text_submit = true
	_line.context_menu_enabled = false
	_line.custom_minimum_size = Vector2(0, 46)
	_line.add_theme_font_size_override("font_size", 22)
	_line.text_submitted.connect(_on_submit)
	_line.text_changed.connect(_on_text_changed)
	row.add_child(_line)
	v.add_child(row)

	_print("[color=#%s][b]%s developer console[/b][/color]  [color=#%s]type [b]help[/b] for commands, [b]cars[/b] for the garage roster[/color]" % [
		Style.ACCENT.to_html(false), Game.GAME_TITLE, Style.TEXT_DIM.to_html(false)])


func _on_opened() -> void:
	_panel.position.y = -_panel.size.y
	if _slide:
		_slide.kill()
	_slide = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_slide.tween_property(_panel, "position:y", 0.0, 0.18)
	_line.clear()
	_hist_pos = -1
	_update_hint("")
	_line.grab_focus.call_deferred()
	_line.edit.call_deferred()


func _on_closed() -> void:
	_line.unedit()


func _menu_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k == null or not k.pressed:
		return
	match k.keycode:
		KEY_TAB:
			_complete()
		KEY_UP:
			_history_step(1)
		KEY_DOWN:
			_history_step(-1)
		KEY_PAGEUP:
			_log.get_v_scroll_bar().value -= _log.size.y * 0.8
		KEY_PAGEDOWN:
			_log.get_v_scroll_bar().value += _log.size.y * 0.8
		_:
			return
	get_viewport().set_input_as_handled()


# ------------------------------------------------------------------ output

func _print(bb: String) -> void:
	_log.append_text(bb + "\n")
	while _log.get_paragraph_count() > MAX_PARAGRAPHS:
		_log.remove_paragraph(0)


func _c(col: Color, s: String) -> String:
	return "[color=#%s]%s[/color]" % [col.to_html(false), s]


func _ok(s: String) -> void:
	_print(_c(Style.GOOD, "✓ ") + s)


func _info(s: String) -> void:
	_print(_c(Style.TEXT_DIM, s))


func _err(s: String) -> void:
	_print(_c(Style.BAD, "✗ " + s))


func _table(header: Array, rows: Array) -> void:
	var bb := "[table=%d]" % header.size()
	for h: String in header:
		bb += "[cell]" + _c(Style.TEXT_FAINT, "[b]" + h.to_upper() + "[/b]") + "[/cell]"
	for r: Array in rows:
		for cell: String in r:
			bb += "[cell]" + cell + "[/cell]"
	bb += "[/table]"
	_print(bb)


# ------------------------------------------------------------------ input line

func _on_submit(text: String) -> void:
	_line.clear()
	_update_hint("")
	execute(text)


func execute(line: String) -> void:
	var text := line.strip_edges()
	if text == "":
		return
	if _history.is_empty() or _history[_history.size() - 1] != text:
		_history.append(text)
	_hist_pos = -1
	_print(_c(Style.ACCENT, "> ") + Style.bb_escape(text))
	var parts := text.split(" ", false)
	var cname := parts[0].to_lower()
	var args: PackedStringArray = parts.slice(1)
	if not _commands.has(cname):
		_err("Unknown command '%s'.%s Type [b]help[/b] for the list." % [Style.bb_escape(cname), _suggest(cname)])
		return
	(_commands[cname]["fn"] as Callable).call(args)


## " Did you mean <closest command>?" or "" when nothing is close.
func _suggest(cname: String) -> String:
	var best := ""
	var best_s := 0.0
	for c: String in _order:
		var s := c.similarity(cname)
		if s > best_s:
			best_s = s
			best = c
	return (" Did you mean [b]%s[/b]?" % best) if best_s >= 0.35 else ""


func _history_step(dir: int) -> void:
	if _history.is_empty():
		return
	if _hist_pos == -1:
		if dir < 0:
			return
		_draft = _line.text
		_hist_pos = _history.size() - 1
	else:
		_hist_pos -= dir
	if _hist_pos >= _history.size():
		_hist_pos = -1
		_set_line(_draft)
		return
	_hist_pos = clampi(_hist_pos, 0, _history.size() - 1)
	_set_line(_history[_hist_pos])


func _set_line(t: String) -> void:
	_line.text = t
	_line.caret_column = t.length()
	_update_hint(t)


func _on_text_changed(t: String) -> void:
	_update_hint(t)


func _update_hint(t: String) -> void:
	var s := t.strip_edges(true, false)
	if s == "":
		_hint.text = "Try:  cars   car 3   tp Mesa   weather rain   time 19   paint orange metallic   photo"
		return
	var cname := s.split(" ", false)[0].to_lower()
	if s.contains(" ") and _commands.has(cname):
		_hint.text = "%s  -  %s" % [_commands[cname]["usage"], _commands[cname]["help"]]
		return
	var m: PackedStringArray = []
	for c: String in _order:
		if c.begins_with(cname):
			m.append(c)
	_hint.text = "   ".join(m) if not m.is_empty() else "No command starts with '%s'" % cname


func _complete() -> void:
	var t := _line.text
	var space := t.find(" ")
	var cands: PackedStringArray = []
	var prefix := ""
	var head := ""
	if space < 0:
		prefix = t.to_lower()
		cands = _order
	else:
		var cname := t.substr(0, space).to_lower()
		if not _commands.has(cname) or not (_commands[cname]["args"] as Callable).is_valid():
			return
		var rest := t.substr(space + 1)
		var whole: bool = _commands[cname]["rest"]
		if whole or not rest.contains(" "):
			prefix = rest
			head = t.substr(0, space + 1)
		else:
			var last := rest.rfind(" ")
			prefix = rest.substr(last + 1)
			head = t.substr(0, space + 1 + last + 1)
		var argi := 0 if whole else rest.split(" ", true).size() - 1
		cands = (_commands[cname]["args"] as Callable).call(argi)
	var matches: PackedStringArray = []
	for c: String in cands:
		if c.to_lower().begins_with(prefix.to_lower()):
			matches.append(c)
	if matches.is_empty():
		return
	if matches.size() == 1:
		_set_line(head + matches[0] + ("" if head != "" and _commands.get(head.strip_edges().to_lower(), {}).get("rest", false) else " "))
		return
	var common := matches[0]
	for m: String in matches:
		while not m.to_lower().begins_with(common.to_lower()):
			common = common.substr(0, common.length() - 1)
	_set_line(head + common)
	_info("   ".join(matches))


# ------------------------------------------------------------------ commands

func _cmd(cname: String, usage: String, help: String, fn: Callable, args := Callable(), rest := false) -> void:
	_commands[cname] = {"usage": usage, "help": help, "fn": fn, "args": args, "rest": rest}
	_order.append(cname)


func _register_commands() -> void:
	_cmd("help", "help [command]", "List commands or show one command's usage", _c_help, func(_i: int) -> PackedStringArray: return _order)
	_cmd("cars", "cars", "List the garage with class and performance index", _c_cars)
	_cmd("car", "car <index|name>", "Switch to a car at the current location", _c_car, _car_args, true)
	_cmd("respawn", "respawn", "Put the car back on the nearest road", func(_a: PackedStringArray) -> void:
		Game.respawn()
		_ok("Respawned on the road"))
	_cmd("reset", "reset", "Flip the car upright where it is", func(_a: PackedStringArray) -> void:
		Game.flip_reset()
		_ok("Car reset"))
	_cmd("tp", "tp [target]", "Teleport to a region, road start or point of interest", _c_tp, _tp_args, true)
	_cmd("time", "time <hour>", "Set the time of day (e.g. 6, 19.5, 20:30)", _c_time)
	_cmd("timescale", "timescale <x>", "Day-night speed multiplier (0 freezes time)", _c_timescale)
	_cmd("weather", "weather <id> [fade]", "Change the weather instantly (fade = smooth transition)", _c_weather, _weather_args)
	_cmd("traffic", "traffic <0..1|on|off>", "Traffic density", _c_traffic, func(_i: int) -> PackedStringArray: return PackedStringArray(["on", "off", "0", "0.3", "0.6", "1"]))
	_cmd("speed", "speed", "Toggle km/h and mph", func(_a: PackedStringArray) -> void:
		var mph := not bool(Settings.get_value("units_mph", false))
		Settings.set_value("units_mph", mph)
		_ok("Speed shown in " + ("mph" if mph else "km/h")))
	_cmd("fps", "fps", "Toggle the FPS / position readout", func(_a: PackedStringArray) -> void:
		var on := not bool(Settings.get_value("show_fps", true))
		Settings.set_value("show_fps", on)
		_ok("FPS readout " + ("on" if on else "off")))
	_cmd("assist", "assist <tcs|stm|abs|steering|auto|line> [on|off]", "Toggle driving assists", _c_assist, _assist_args)
	_cmd("paint", "paint <colour|#hex> [gloss|matte|metallic]", "Repaint the current car", _c_paint, _paint_args)
	_cmd("stripes", "stripes <0-5> [colour]", "Stripes: 0 none, 1 twin, 2 centre, 3 side, 4 rally, 5 two-tone", _c_stripes, _stripe_args)
	_cmd("rims", "rims <colour|default>", "Rim colour", _c_rims, func(i: int) -> PackedStringArray:
		var a := _paint_args(i)
		a.append("default")
		return a)
	_cmd("repair", "repair", "Fix all damage", func(_a: PackedStringArray) -> void:
		Game.repair()
		_ok("Car repaired"))
	_cmd("upgrade", "upgrade <slot> <0-3>", "Set an upgrade level (rebuilds the car)", _c_upgrade, _upgrade_args)
	_cmd("tune", "tune <key> <value> | tune reset", "Adjust tuning (rebuilds the car)", _c_tune, _tune_args)
	_cmd("camera", "camera <0-4>", "0 chase, 1 far chase, 2 hood, 3 bumper, 4 cockpit", _c_camera, func(_i: int) -> PackedStringArray: return PackedStringArray(["0", "1", "2", "3", "4"]))
	_cmd("hud", "hud on|off", "Show or hide the HUD", _c_hud, func(_i: int) -> PackedStringArray: return PackedStringArray(["on", "off"]))
	_cmd("save", "save", "Save progress now", func(_a: PackedStringArray) -> void:
		if Actions.save_game():
			_ok("Game saved")
		else:
			_err("Could not write the save file"))
	_cmd("load", "load", "Load the last save and return to the saved spot", func(_a: PackedStringArray) -> void:
		if Actions.load_game():
			_ok("Save loaded - welcome back")
		else:
			_err("No save file yet - use save first"))
	_cmd("pos", "pos", "Show position, region and nearest road", _c_pos)
	_cmd("photo", "photo", "Enter photo mode", func(_a: PackedStringArray) -> void:
		var pm := find_menu(get_tree(), &"photo")
		if pm == null:
			_err("Photo mode is not available")
			return
		close_menu()
		pm.call_deferred("open_menu"))
	_cmd("clear", "clear", "Clear the console log", func(_a: PackedStringArray) -> void:
		_log.clear())
	_cmd("quit", "quit", "Save and quit to desktop", func(_a: PackedStringArray) -> void:
		_info("Bye!")
		Actions.quit_game(get_tree()))


func _c_help(a: PackedStringArray) -> void:
	if not a.is_empty():
		var cname := a[0].to_lower()
		if not _commands.has(cname):
			_err("Unknown command '%s'.%s Type [b]help[/b] for the list." % [Style.bb_escape(cname), _suggest(cname)])
			return
		var c: Dictionary = _commands[cname]
		_print(_c(Style.GOLD, c["usage"]) + "  " + _c(Style.TEXT_DIM, c["help"]))
		return
	var rows: Array = []
	for n: String in _order:
		var c: Dictionary = _commands[n]
		rows.append([_c(Style.GOLD, Style.bb_escape(c["usage"])), _c(Style.TEXT_DIM, c["help"])])
	_table(["Command", "What it does"], rows)


func _c_cars(_a: PackedStringArray) -> void:
	var rows: Array = []
	var cat := Game.get_car_catalog()
	for i in cat.size():
		var d := Game.effective_car_data(i)
		var pi := Tuning.performance_index(d)
		var cls := Tuning.class_for(pi)
		var cur := i == Game.current_car_index
		rows.append([
			_c(Style.ACCENT if cur else Style.TEXT_FAINT, str(i + 1)),
			("[b]%s[/b]" % d.display_name) + (_c(Style.ACCENT, "  < driving") if cur else ""),
			_c(Style.TEXT_DIM, "%s · %s" % [d.category, d.year_style]),
			_c(Style.class_color(cls), "[b]%s %d[/b]" % [cls, pi]),
			d.drivetrain_name(),
			"%d hp" % roundi(d.peak_power_hp()),
			"%d kg" % roundi(d.mass),
		])
	_table(["#", "Car", "Type", "Class", "Drive", "Power", "Weight"], rows)
	_info("car <index|name> switches car where you stand - F1 opens the garage")


func _car_args(_i: int) -> PackedStringArray:
	var out: PackedStringArray = []
	for d in Game.get_car_catalog():
		out.append(d.id)
	return out


func _c_car(a: PackedStringArray) -> void:
	if a.is_empty():
		var d := Game.current_car_data()
		_info("Driving %s. Usage: car <index|name>" % (d.display_name if d else "nothing"))
		return
	var key := " ".join(a)
	var i := Game.find_car_index(key)
	if i < 0:
		_err("No car matches '%s' - use cars to list them" % Style.bb_escape(key))
		return
	if not Game.spawn_car(i, true):
		_err("The car could not be spawned right now")
		return
	var d := Game.effective_car_data(i)
	var pi := Tuning.performance_index(d)
	_ok("Now driving [b]%s[/b]  %s" % [d.display_name, _c(Style.class_color(Tuning.class_for(pi)), "%s %d" % [Tuning.class_for(pi), pi])])


func _tp_args(_i: int) -> PackedStringArray:
	var out: PackedStringArray = []
	for t: Dictionary in Game.get_teleport_targets():
		out.append(String(t["name"]))
	return out


func _c_tp(a: PackedStringArray) -> void:
	if a.is_empty():
		for g: Array in Actions.grouped_targets():
			var names: PackedStringArray = []
			for t: Dictionary in g[1]:
				names.append(String(t["name"]))
			_print(_c(Style.GOLD, "[b]%s[/b]  " % g[0]) + Style.bb_escape(", ".join(names)))
		_info("tp <name> - partial names work, e.g. tp mesa")
		return
	var key := " ".join(a)
	if Game.teleport(key):
		var p := Game.player_car.global_position if Game.player_car else Vector3.ZERO
		var region: String = Game.world.region_at(p) if Game.world else ""
		_ok("Teleported to [b]%s[/b]  %s" % [Style.bb_escape(key), _c(Style.TEXT_DIM, region)])
		return
	var close: PackedStringArray = []
	for n: String in _tp_args(0):
		if n.to_lower().contains(key.to_lower()):
			close.append(n)
	_err("No teleport target '%s'%s" % [Style.bb_escape(key), (" - try: " + ", ".join(close)) if not close.is_empty() else " - tp alone lists them"])


func _c_time(a: PackedStringArray) -> void:
	if a.is_empty():
		_info("It is %s. Usage: time <hour>" % Style.fmt_time(Game.get_time_of_day()))
		return
	var s := a[0]
	var h := -1.0
	if s.contains(":"):
		var hm := s.split(":")
		if hm.size() == 2 and hm[0].is_valid_int() and hm[1].is_valid_int():
			var hh := hm[0].to_int()
			var mm := hm[1].to_int()
			if hh < 0 or hh > 24 or mm < 0 or mm > 59 or (hh == 24 and mm > 0) or hm[1].length() != 2:
				_err("Use H:MM with minutes 00-59 (e.g. time 6:30)")
				return
			h = hh + mm / 60.0
	elif s.is_valid_float():
		h = s.to_float()
	if h < 0.0 or h > 24.0:
		_err("Hour must be between 0 and 24 (e.g. time 19 or time 6:30)")
		return
	if Game.env == null:
		_err("The environment system is not loaded")
		return
	Game.set_time_of_day(fmod(h, 24.0))
	_ok("Time set to %s" % Style.fmt_time(h))


func _c_timescale(a: PackedStringArray) -> void:
	if a.is_empty() or not a[0].is_valid_float() or a[0].to_float() < 0.0:
		_err("Usage: timescale <x>  (x >= 0: 0 = frozen, 1 = default, 60 = fast)")
		return
	if Game.env == null:
		_err("The environment system is not loaded")
		return
	Game.set_time_scale(a[0].to_float())
	_ok("Time scale %s" % str(Game.get_time_scale()))


func _weather_args(_i: int) -> PackedStringArray:
	var out: PackedStringArray = []
	for w: Variant in Game.get_weather_ids():
		out.append(String(w))
	return out


func _c_weather(a: PackedStringArray) -> void:
	var ids := _weather_args(0)
	if ids.is_empty():
		_err("The weather system is not loaded")
		return
	if a.is_empty():
		_info("Weather is %s. Options: %s" % [String(Game.get_weather()), ", ".join(ids)])
		return
	var fade := a.size() > 1 and a[1].to_lower() == "fade"
	if Game.set_weather(a[0], not fade):
		_ok("Weather: [b]%s[/b]%s" % [a[0].to_lower(), " (fading in)" if fade else ""])
	else:
		_err("Unknown weather '%s' - options: %s" % [Style.bb_escape(a[0]), ", ".join(ids)])


func _c_traffic(a: PackedStringArray) -> void:
	if a.is_empty():
		_info("Traffic density %.2f. Usage: traffic <0..1|on|off>" % Game.get_traffic_density())
		return
	var v := -1.0
	match a[0].to_lower():
		"on":
			v = 0.6
		"off":
			v = 0.0
		_:
			if a[0].is_valid_float():
				v = a[0].to_float()
	if v < 0.0 or v > 1.0:
		_err("Traffic density must be between 0 and 1")
		return
	Game.set_traffic_density(v)
	_ok("Traffic density %.2f%s" % [v, "" if Game.traffic else " (traffic system not loaded)"])


func _assist_args(i: int) -> PackedStringArray:
	return PackedStringArray(["tcs", "stm", "abs", "steering", "auto", "line"]) if i == 0 else PackedStringArray(["on", "off"])


func _c_assist(a: PackedStringArray) -> void:
	var st := Game.get_assists()
	if a.is_empty():
		var parts: PackedStringArray = []
		for k: String in st:
			parts.append("%s %s" % [k, _c(Style.GOOD, "on") if st[k] else _c(Style.TEXT_FAINT, "off")])
		_print("Assists: " + "   ".join(parts))
		return
	var aname := a[0].to_lower()
	var on: bool
	if a.size() > 1:
		var w := a[1].to_lower()
		if w not in ["on", "off", "1", "0", "true", "false"]:
			_err("Use on or off")
			return
		on = w in ["on", "1", "true"]
	else:
		var key := aname
		for k: String in ["steer", "traction", "stability", "gearbox", "brakingline"]:
			if aname == k:
				key = {"steer": "steering", "traction": "tcs", "stability": "stm", "gearbox": "auto", "brakingline": "line"}[k]
		on = not bool(st.get(key, false))
	if not Game.set_assist(aname, on):
		_err("Unknown assist '%s' - tcs, stm, abs, steering, auto, line" % Style.bb_escape(aname))
		return
	_ok("Assist %s %s" % [aname, "on" if on else "off"])


func _paint_args(i: int) -> PackedStringArray:
	if i == 1:
		return PackedStringArray(Actions.FINISHES)
	var out: PackedStringArray = []
	for k: String in Game.PAINT_COLORS:
		out.append(k)
	return out


## stripes <0-5> [colour]: the style number first, then a colour name.
func _stripe_args(i: int) -> PackedStringArray:
	if i == 0:
		return PackedStringArray(["0", "1", "2", "3", "4", "5"])
	return _paint_args(0) if i == 1 else PackedStringArray()


func _c_paint(a: PackedStringArray) -> void:
	var p := Actions.current_paint()
	if a.is_empty():
		_info("Paint: %s %s. Colours: %s or #hex" % [Actions.color_name(p.get("color", Color.RED)), Actions.FINISHES[int(p.get("finish", 0))], ", ".join(_paint_args(0))])
		return
	var col := Actions.parse_color(a[0])
	if col.r < 0.0:
		_err("Unknown colour '%s' - use a name (%s) or #RRGGBB" % [Style.bb_escape(a[0]), ", ".join(_paint_args(0).slice(0, 6))])
		return
	var finish := -1
	if a.size() > 1:
		finish = Actions.FINISHES.find(a[1].to_lower())
		if finish < 0:
			_err("Finish must be gloss, matte or metallic")
			return
	Game.set_paint(col, finish)
	var swatch := "[color=#%s]■■■[/color]" % col.to_html(false)
	_ok("Paint %s %s %s" % [swatch, Actions.color_name(col), Actions.FINISHES[int(Actions.current_paint().get("finish", 0))]])


func _c_stripes(a: PackedStringArray) -> void:
	if a.is_empty() or not a[0].is_valid_int() or a[0].to_int() < 0 or a[0].to_int() > 5:
		var opts: PackedStringArray = []
		for i in Actions.STRIPE_NAMES.size():
			opts.append("%d %s" % [i, Actions.STRIPE_NAMES[i]])
		_err("Usage: stripes <0-5> [colour]  -  " + ", ".join(opts))
		return
	var p := Actions.current_paint()
	var sc := Color(-1, -1, -1)
	if a.size() > 1:
		sc = Actions.parse_color(a[1])
		if sc.r < 0.0:
			_err("Unknown stripe colour '%s'" % Style.bb_escape(a[1]))
			return
	Game.set_paint(p.get("color", Color.RED), -1, a[0].to_int(), sc)
	_ok("Stripes: %s" % Actions.STRIPE_NAMES[a[0].to_int()])


func _c_rims(a: PackedStringArray) -> void:
	if a.is_empty():
		_err("Usage: rims <colour|default>")
		return
	if a[0].to_lower() == "default":
		Game.set_rim_color(Color(-1, -1, -1))
		_ok("Rims back to factory finish")
		return
	var c := Actions.parse_color(a[0])
	if c.r < 0.0:
		_err("Unknown colour '%s'" % Style.bb_escape(a[0]))
		return
	Game.set_rim_color(c)
	_ok("Rims painted %s" % Actions.color_name(c))


func _upgrade_args(i: int) -> PackedStringArray:
	return PackedStringArray(Tuning.SLOTS) if i == 0 else PackedStringArray(["0", "1", "2", "3"])


func _c_upgrade(a: PackedStringArray) -> void:
	var d := Game.current_car_data()
	if d == null:
		return
	var ups := Game.get_upgrades(d.id)
	if a.size() < 2:
		var parts: PackedStringArray = []
		for s: String in Tuning.SLOTS:
			parts.append("%s %s" % [s, _c(Style.GOLD, "%d (%s)" % [int(ups.get(s, 0)), Actions.level_name(s, int(ups.get(s, 0)))])])
		_print("Upgrades on %s: %s" % [d.display_name, "   ".join(parts)])
		_info("Usage: upgrade <slot> <0-3>")
		return
	var slot := a[0].to_lower()
	if slot == "tyres":
		slot = "tires"
	if slot not in Tuning.SLOTS:
		_err("Unknown slot '%s' - %s" % [Style.bb_escape(slot), ", ".join(Tuning.SLOTS)])
		return
	if not a[1].is_valid_int() or a[1].to_int() < 0 or a[1].to_int() > Tuning.MAX_LEVEL:
		_err("Level must be 0..3")
		return
	var before := Tuning.performance_index(Game.effective_car_data(Game.current_car_index))
	ups[slot] = a[1].to_int()
	Actions.rebuild_car()
	var after := Tuning.performance_index(Game.effective_car_data(Game.current_car_index))
	_ok("%s -> %s   PI %d -> %s" % [Actions.upgrade_name(slot), Actions.level_name(slot, a[1].to_int()), before,
		_c(Style.class_color(Tuning.class_for(after)), "[b]%s %d[/b]" % [Tuning.class_for(after), after])])


func _tune_args(i: int) -> PackedStringArray:
	if i == 0:
		var k := PackedStringArray(Tuning.TUNE_SPEC.keys())
		k.append("reset")
		return k
	return PackedStringArray()


func _c_tune(a: PackedStringArray) -> void:
	var d := Game.current_car_data()
	if d == null:
		return
	var tune := Game.get_tuning(d.id)
	if a.is_empty():
		var rows: Array = []
		for k: String in Tuning.TUNE_SPEC:
			var spec: Array = Tuning.TUNE_SPEC[k]
			var v := float(tune.get(k, spec[2]))
			rows.append([_c(Style.GOLD, k), Actions.tune_text(k, v), _c(Style.TEXT_FAINT, "%s .. %s" % [str(spec[0]), str(spec[1])]), _c(Style.TEXT_DIM, Actions.tune_help(k))])
		_table(["Key", "Value", "Range", "Effect"], rows)
		_info("Usage: tune <key> <value>  (e.g. tune final_drive -0.1)  |  tune reset")
		return
	if a[0].to_lower() == "reset":
		tune.clear()
		Actions.rebuild_car()
		_ok("Tuning reset to factory settings")
		return
	var key := a[0].to_lower()
	if not Tuning.TUNE_SPEC.has(key):
		_err("Unknown tuning key '%s' - tune lists them" % Style.bb_escape(key))
		return
	if a.size() < 2 or not a[1].is_valid_float():
		_err("Usage: tune %s <value>" % key)
		return
	var spec2: Array = Tuning.TUNE_SPEC[key]
	var v2 := clampf(a[1].to_float(), float(spec2[0]), float(spec2[1]))
	tune[key] = v2
	Actions.rebuild_car()
	_ok("%s = %s%s" % [Actions.tune_label(key), Actions.tune_text(key, v2), "" if is_equal_approx(v2, a[1].to_float()) else _c(Style.TEXT_FAINT, " (clamped)")])


func _c_camera(a: PackedStringArray) -> void:
	var rig := Game.camera_rig as CameraRig
	if rig == null:
		return
	if a.is_empty() or not a[0].is_valid_int() or a[0].to_int() < 0 or a[0].to_int() >= CameraRig.MODE_NAMES.size():
		var opts: PackedStringArray = []
		for i in CameraRig.MODE_NAMES.size():
			opts.append("%d %s" % [i, CameraRig.MODE_NAMES[i]])
		_info("Camera is %s. Usage: camera <0-4>: %s" % [CameraRig.MODE_NAMES[rig.mode], ", ".join(opts)])
		return
	rig.set_mode(a[0].to_int())
	_ok("Camera: %s" % CameraRig.MODE_NAMES[a[0].to_int()])


func _c_hud(a: PackedStringArray) -> void:
	var on := not bool(Settings.get_value("hud_visible", true))
	if not a.is_empty():
		var w := a[0].to_lower()
		if w not in ["on", "off", "1", "0", "true", "false", "show", "hide"]:
			_err("Use on or off")
			return
		on = w in ["on", "1", "true", "show"]
	Settings.set_value("hud_visible", on)
	_ok("HUD " + ("shown" if on else "hidden"))


func _c_pos(_a: PackedStringArray) -> void:
	var car := Game.player_car
	if car == null or not is_instance_valid(car):
		_err("No car")
		return
	var p := car.global_position
	var f := -car.global_transform.basis.z
	var heading := fposmod(rad_to_deg(atan2(f.x, -f.z)), 360.0)
	var line := "x %.1f  y %.1f  z %.1f   heading %d°" % [p.x, p.y, p.z, roundi(heading)]
	if Game.world:
		line += "   region [b]%s[/b]" % Game.world.region_at(p)
		var r: Dictionary = Game.world.nearest_road_point(p)
		if r.has("road_name"):
			line += "   road %s (s %.0f m)" % [Style.bb_escape(String(r["road_name"])), float(r["s"])]
	line += "   %s" % Style.speed_text(car.get_speed_kmh())
	_print(line)
