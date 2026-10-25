class_name DevConsole
extends CanvasLayer
## In-game developer console (toggle with ` / ~). Commands are registered in a table and call
## into the running systems through Game.*; type `help` for the list.

const COLOURS := {
	"red": Color(0.85, 0.1, 0.08), "orange": Color(0.95, 0.45, 0.05), "yellow": Color(0.95, 0.8, 0.1),
	"green": Color(0.1, 0.55, 0.18), "lime": Color(0.55, 0.85, 0.15), "teal": Color(0.05, 0.55, 0.55),
	"blue": Color(0.08, 0.25, 0.8), "navy": Color(0.04, 0.08, 0.3), "purple": Color(0.4, 0.1, 0.6),
	"pink": Color(0.95, 0.35, 0.6), "white": Color(0.92, 0.92, 0.92), "silver": Color(0.65, 0.67, 0.7),
	"grey": Color(0.35, 0.36, 0.38), "gray": Color(0.35, 0.36, 0.38), "black": Color(0.03, 0.03, 0.035),
	"brown": Color(0.35, 0.2, 0.1), "gold": Color(0.8, 0.62, 0.2), "cyan": Color(0.1, 0.75, 0.9),
}

var _panel: PanelContainer
var _log: RichTextLabel
var _line: LineEdit
var _history: Array[String] = []
var _hist_idx: int = -1
var _commands: Dictionary = {}
var is_open: bool = false


func _ready() -> void:
	layer = 50
	process_mode = Node.PROCESS_MODE_ALWAYS
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UiTheme.get_theme()
	add_child(root)
	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_panel.offset_bottom = 430
	_panel.add_theme_stylebox_override("panel", UiTheme.panel_style(Color(0.02, 0.025, 0.035, 0.92), 0, UiTheme.ACCENT * Color(1, 1, 1, 0.5)))
	root.add_child(_panel)
	var v := VBoxContainer.new()
	_panel.add_child(v)
	var head := UiTheme.label("DEVELOPER CONSOLE  —  type 'help'  —  ` to close", 16, UiTheme.ACCENT, true)
	v.add_child(head)
	_log = RichTextLabel.new()
	_log.bbcode_enabled = true
	_log.scroll_following = true
	_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_log.add_theme_font_size_override("normal_font_size", 17)
	_log.add_theme_font_size_override("bold_font_size", 17)
	v.add_child(_log)
	_line = LineEdit.new()
	_line.placeholder_text = "command…"
	_line.add_theme_font_size_override("font_size", 19)
	_line.text_submitted.connect(_on_submit)
	v.add_child(_line)
	_panel.visible = false
	_register()
	print_line("[color=#ffa31f]Ridgeline Festival developer console.[/color] Type [b]help[/b].")


func print_line(t: String) -> void:
	_log.append_text(t + "\n")


func toggle() -> void:
	is_open = not is_open
	_panel.visible = is_open
	Game.set_ui_focus("console", is_open)
	if is_open:
		_line.clear()
		_line.call_deferred("grab_focus")
	else:
		_line.release_focus()


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_console"):
		toggle()
		get_viewport().set_input_as_handled()
		return
	if not is_open:
		return
	if event is InputEventKey and event.pressed:
		var k := event as InputEventKey
		if k.keycode == KEY_UP and not _history.is_empty():
			_hist_idx = clampi(_hist_idx - 1 if _hist_idx >= 0 else _history.size() - 1, 0, _history.size() - 1)
			_line.text = _history[_hist_idx]
			_line.caret_column = _line.text.length()
			get_viewport().set_input_as_handled()
		elif k.keycode == KEY_DOWN and not _history.is_empty():
			_hist_idx = mini(_hist_idx + 1, _history.size())
			_line.text = _history[_hist_idx] if _hist_idx < _history.size() else ""
			_line.caret_column = _line.text.length()
			get_viewport().set_input_as_handled()
		elif k.keycode == KEY_ESCAPE:
			toggle()
			get_viewport().set_input_as_handled()


func _on_submit(text: String) -> void:
	text = text.replace("`", "").strip_edges()
	_line.clear()
	if text == "":
		return
	_history.append(text)
	_hist_idx = -1
	print_line("[color=#7fdcf0]> %s[/color]" % text)
	execute(text)


func execute(text: String) -> void:
	var parts := text.split(" ", false)
	if parts.is_empty():
		return
	var cmd := parts[0].to_lower()
	var args: Array[String] = []
	for i in range(1, parts.size()):
		args.append(parts[i])
	if not _commands.has(cmd):
		print_line("[color=#ff6a5a]Unknown command '%s'. Type help.[/color]" % cmd)
		return
	var res = (_commands[cmd]["fn"] as Callable).call(args)
	if res is String and res != "":
		print_line(res)


func _reg(cmd: String, usage: String, fn: Callable) -> void:
	_commands[cmd] = {"usage": usage, "fn": fn}


func _register() -> void:
	_reg("help", "help — list commands", func(_a: Array[String]) -> String:
		var lines: Array[String] = []
		var keys := _commands.keys()
		keys.sort()
		for k in keys:
			lines.append("  [b]%s[/b]  %s" % [k, _commands[k]["usage"]])
		return "\n".join(lines))
	_reg("cars", "cars — list the garage", func(_a: Array[String]) -> String:
		var lines: Array[String] = []
		for i in Game.car_defs.size():
			var d := Game.car_defs[i]
			var mark := "▶" if i == Game.current_car_index else " "
			lines.append("%s %2d  %-22s %-16s %s %d  %s %d kW" % [mark, i + 1, d.display_name, d.category, d.performance_class, d.performance_index, d.drivetrain_label(), int(d.power_kw)])
		return "\n".join(lines))
	_reg("car", "car <index|name> — switch car at current location", func(a: Array[String]) -> String:
		if a.is_empty():
			return "usage: car <index|name>"
		var idx := Game.find_car_index(" ".join(a))
		if idx < 0:
			return "no such car"
		Game.main.call("switch_car", idx)
		return "switched to " + Game.car_defs[idx].display_name)
	_reg("respawn", "respawn — put the car back on the nearest road", func(_a: Array[String]) -> String:
		Game.main.call("respawn_on_road")
		return "respawned")
	_reg("reset", "reset — flip upright / repair in place", func(_a: Array[String]) -> String:
		if Game.player_car:
			Game.player_car.flip_upright()
		return "car reset")
	_reg("tp", "tp <region|poi> — teleport (tp alone lists targets)", func(a: Array[String]) -> String:
		var targets: Array = Game.main.call("teleport_targets")
		if a.is_empty():
			return "targets: " + ", ".join(targets)
		if Game.main.call("teleport", " ".join(a)):
			return "teleported"
		return "unknown target. targets: " + ", ".join(targets))
	_reg("time", "time <hour 0-24> [freeze|run] — set time of day", func(a: Array[String]) -> String:
		if Game.environment == null:
			return "no environment"
		var env := Game.environment as EnvironmentController
		if a.is_empty():
			return "time %.2f (%s)" % [env.time_of_day, "frozen" if env.time_frozen else "running"]
		env.set_time(float(a[0]))
		if a.size() > 1:
			env.time_frozen = a[1] == "freeze"
		return "time set to %.2f" % env.time_of_day)
	_reg("daylength", "daylength <minutes> — real minutes per in-game day", func(a: Array[String]) -> String:
		if a.is_empty() or Game.environment == null:
			return "usage: daylength <minutes>"
		(Game.environment as EnvironmentController).day_length_minutes = maxf(float(a[0]), 0.5)
		return "day length %s min" % a[0])
	_reg("weather", "weather <clear|cloudy|rain|fog|storm>", func(a: Array[String]) -> String:
		if a.is_empty() or Game.environment == null:
			return "usage: weather <clear|cloudy|rain|fog|storm>"
		var env := Game.environment as EnvironmentController
		var instant := a.size() > 1 and a[1] == "now"
		if env.set_weather_by_name(a[0]):
			if instant:
				env.set_weather(env.weather, true)
			return "weather → " + a[0]
		return "unknown weather")
	_reg("traffic", "traffic <0..1> — traffic density", func(a: Array[String]) -> String:
		if a.is_empty():
			return "traffic density %.2f" % float(Game.settings["traffic_density"])
		Game.settings["traffic_density"] = clampf(float(a[0]), 0.0, 1.0)
		if Game.traffic != null and Game.traffic.has_method("set_density"):
			Game.traffic.call("set_density", Game.settings["traffic_density"])
		return "traffic density %.2f" % Game.settings["traffic_density"])
	_reg("speed", "speed — toggle speedometer", func(_a: Array[String]) -> String:
		Game.settings["show_speed"] = not Game.settings.get("show_speed", true)
		if Game.hud != null:
			(Game.hud as Hud).gauge.visible = Game.settings["show_speed"]
		return "speedometer %s" % ("on" if Game.settings["show_speed"] else "off"))
	_reg("fps", "fps — toggle FPS / coordinates overlay", func(_a: Array[String]) -> String:
		Game.settings["show_fps"] = not Game.settings.get("show_fps", false)
		return "fps overlay %s" % ("on" if Game.settings["show_fps"] else "off"))
	_reg("assist", "assist <tcs|esc|abs|steer|auto|line|all> on|off", func(a: Array[String]) -> String:
		if a.size() < 2:
			return "assists: " + str(Game.assists)
		var on := a[1] == "on" or a[1] == "1" or a[1] == "true"
		var key := a[0].to_lower()
		var keys := ["tcs", "esc", "abs", "steer", "auto_gear", "line"] if key == "all" else [key if key != "auto" else "auto_gear"]
		for k in keys:
			if not Game.assists.has(k):
				return "unknown assist '%s'" % k
			Game.assists[k] = on
		Game.main.call("apply_assists")
		return "assists: " + str(Game.assists))
	_reg("paint", "paint <colour|#hex|r g b> [gloss|metallic|matte|pearl]", func(a: Array[String]) -> String:
		if a.is_empty():
			return "colours: " + ", ".join(COLOURS.keys())
		var col := Game.paint_color
		var rest := a.duplicate()
		if COLOURS.has(a[0].to_lower()):
			col = COLOURS[a[0].to_lower()]
			rest.remove_at(0)
		elif a[0].begins_with("#"):
			col = Color.html(a[0])
			rest.remove_at(0)
		elif a.size() >= 3 and a[0].is_valid_float():
			col = Color(float(a[0]), float(a[1]), float(a[2]))
			rest = rest.slice(3)
		else:
			return "unknown colour"
		var fin := Game.paint_finish
		if not rest.is_empty():
			var fi := ["gloss", "metallic", "matte", "pearl"].find(rest[0].to_lower())
			if fi >= 0:
				fin = fi
		Game.main.call("set_paint", col, fin)
		return "paint updated")
	_reg("finish", "finish <gloss|metallic|matte|pearl>", func(a: Array[String]) -> String:
		if a.is_empty():
			return "usage: finish <gloss|metallic|matte|pearl>"
		var fi := ["gloss", "metallic", "matte", "pearl"].find(a[0].to_lower())
		if fi < 0:
			return "unknown finish"
		Game.main.call("set_paint", Game.paint_color, fi)
		return "finish " + a[0])
	_reg("units", "units <kmh|mph>", func(a: Array[String]) -> String:
		Game.settings["units_mph"] = not a.is_empty() and a[0].to_lower() == "mph"
		return "units: " + Game.speed_unit())
	_reg("pos", "pos — print car position", func(_a: Array[String]) -> String:
		if Game.player_car == null:
			return "no car"
		var p := Game.player_car.global_position
		return "x=%.1f y=%.1f z=%.1f" % [p.x, p.y, p.z])
	_reg("save", "save — save game now", func(_a: Array[String]) -> String:
		return "saved" if Game.main.call("save_game") else "save failed")
	_reg("load", "load — load saved game", func(_a: Array[String]) -> String:
		return "loaded" if Game.main.call("load_game") else "no save found")
	_reg("camera", "camera — cycle camera mode", func(_a: Array[String]) -> String:
		if Game.camera_rig:
			(Game.camera_rig as CameraRig).cycle_mode()
		return "")
	_reg("upgrade", "upgrade <engine|tires|suspension|brakes|weight|aero> <0-3>", func(a: Array[String]) -> String:
		if a.size() < 2:
			return "usage: upgrade <part> <level 0-3>"
		return str(Game.main.call("set_upgrade", a[0].to_lower(), int(a[1]))))
	_reg("tune", "tune <param> <value> — e.g. tune final_drive 3.9 (tune alone lists)", func(a: Array[String]) -> String:
		if a.size() < 2:
			return str(Game.main.call("tuning_summary"))
		return str(Game.main.call("set_tuning", a[0].to_lower(), float(a[1]))))
	_reg("photo", "photo — toggle photo mode", func(_a: Array[String]) -> String:
		Game.main.call("toggle_photo_mode")
		return "")
	_reg("event", "event <list|start name|stop>", func(a: Array[String]) -> String:
		if Game.activities == null:
			return "activities not loaded"
		return str(Game.activities.call("console_command", a)))
	_reg("waypoint", "waypoint <x> <z> | clear — set GPS waypoint", func(a: Array[String]) -> String:
		if a.size() == 1 and a[0] == "clear":
			Game.main.call("set_waypoint", Vector3.INF)
			return "waypoint cleared"
		if a.size() < 2:
			return "usage: waypoint <x> <z>"
		Game.main.call("set_waypoint", Vector3(float(a[0]), 0, float(a[1])))
		return "waypoint set")
	_reg("quit", "quit — exit the game (saves first)", func(_a: Array[String]) -> String:
		Game.main.call("save_game")
		get_tree().quit()
		return "")
