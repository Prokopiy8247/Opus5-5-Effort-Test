extends Control
## Developer console (toggle with ` / ~). Commands are listed by `help`.

var main: Node
var panel: PanelContainer
var log_label: RichTextLabel
var input: LineEdit
var history: PackedStringArray = []
var hist_i := -1
var open := false

const HELP := {
	"help": "list commands",
	"cars": "list the garage",
	"car <index|name>": "switch to a car at the current location",
	"respawn / reset": "put the car back on the nearest road",
	"tp <region|place|road>": "teleport (try: tp valley, tp mesa, tp coast, tp highlands, tp festival, tp loop)",
	"places": "list teleport targets",
	"time <hour> [freeze]": "set time of day (0-24)",
	"timescale <hours-per-minute>": "speed of the day cycle (default 1)",
	"weather <clear|cloudy|rain|fog|storm|auto>": "change weather",
	"traffic <0..1>": "traffic density",
	"speed / fps": "toggle speed / fps display",
	"telemetry": "toggle wheel telemetry",
	"assist <tcs|stm|abs|steer|auto> on|off": "driving assists",
	"paint <colour|#hex> [gloss|metallic|matte|pearl]": "repaint the current car",
	"units <kmh|mph>": "speed units",
	"camera <0-4>": "camera mode",
	"repair": "repair and flip upright",
	"photo": "toggle photo mode",
	"save / load": "save or load the game",
	"credits": "show credits balance",
	"events": "list activities",
	"waypoint <place>": "GPS route to a place",
	"clear": "clear the console",
}

const COLORS := {
	"red": Color(0.8, 0.08, 0.06), "blue": Color(0.1, 0.3, 0.85), "green": Color(0.15, 0.6, 0.2),
	"yellow": Color(0.95, 0.8, 0.1), "orange": Color(0.95, 0.5, 0.05), "white": Color(0.93, 0.93, 0.95),
	"black": Color(0.03, 0.03, 0.035), "silver": Color(0.7, 0.72, 0.75), "grey": Color(0.35, 0.36, 0.38),
	"purple": Color(0.45, 0.15, 0.7), "pink": Color(0.95, 0.4, 0.65), "teal": Color(0.1, 0.6, 0.6),
	"lime": Color(0.5, 0.9, 0.1), "gold": Color(0.85, 0.65, 0.2), "brown": Color(0.4, 0.25, 0.12),
	"navy": Color(0.05, 0.1, 0.3), "cream": Color(0.92, 0.88, 0.75), "mint": Color(0.55, 0.85, 0.72),
}


func init_ui(m: Node) -> void:
	main = m
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel = PanelContainer.new()
	UIStyle.place(panel, Control.PRESET_TOP_WIDE, 0, 0, 0, 440)
	panel.add_theme_stylebox_override("panel", UIStyle.panel(Color(0.02, 0.03, 0.05, 0.9), 0))
	add_child(panel)
	var v := VBoxContainer.new()
	panel.add_child(v)
	log_label = RichTextLabel.new()
	log_label.bbcode_enabled = true
	log_label.scroll_following = true
	log_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	log_label.add_theme_font_size_override("normal_font_size", 17)
	log_label.add_theme_font_size_override("bold_font_size", 17)
	v.add_child(log_label)
	input = LineEdit.new()
	input.placeholder_text = "type a command (help)"
	input.add_theme_font_size_override("font_size", 19)
	input.text_submitted.connect(_on_submit)
	input.gui_input.connect(_on_input_key)
	v.add_child(input)
	panel.visible = false
	_print("[color=#ffb84d]%s developer console[/color] — type [b]help[/b]" % Game.TITLE)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_console"):
		toggle()
		get_viewport().set_input_as_handled()


func _input(event: InputEvent) -> void:
	if open and event is InputEventKey and event.pressed and (event as InputEventKey).physical_keycode == KEY_QUOTELEFT:
		toggle()
		get_viewport().set_input_as_handled()


func toggle() -> void:
	open = not open
	panel.visible = open
	if main.player:
		main.player.controls_enabled = not open
	if open:
		input.grab_focus()
		input.text = ""
	else:
		input.release_focus()


func _on_input_key(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		var k := (event as InputEventKey).keycode
		if k == KEY_UP and history.size() > 0:
			hist_i = clampi(hist_i - 1 if hist_i >= 0 else history.size() - 1, 0, history.size() - 1)
			input.text = history[hist_i]
			input.caret_column = input.text.length()
		elif k == KEY_DOWN and history.size() > 0:
			hist_i = clampi(hist_i + 1, 0, history.size() - 1)
			input.text = history[hist_i]
		elif k == KEY_ESCAPE:
			toggle()


func _on_submit(text: String) -> void:
	text = text.strip_edges()
	input.text = ""
	if text == "":
		return
	history.append(text)
	hist_i = -1
	_print("[color=#7fd]> %s[/color]" % text)
	_print(execute(text))


func _print(s: String) -> void:
	if s != "":
		log_label.append_text(s + "\n")


## Executes a command line and returns the output text (also used by tests).
func execute(line: String) -> String:
	var parts := line.split(" ", false)
	var cmd := parts[0].to_lower()
	var args := parts.slice(1)
	var w: World = main.world
	var car: Car = main.player
	match cmd:
		"help":
			var out: PackedStringArray = []
			for k in HELP:
				out.append("[b]%s[/b] — %s" % [k, HELP[k]])
			return "\n".join(out)
		"clear":
			log_label.clear()
			return ""
		"cars":
			var out2: PackedStringArray = []
			for i in Game.cars.size():
				var c := Game.cars[i]
				var pi := Tuning.pi_of(c)
				out2.append("%2d  %-18s %-3s %d  %s  %d hp  %s" % [i + 1, c.display_name, Tuning.class_of(pi), pi,
					["FWD", "RWD", "AWD"][c.drivetrain], c.power_hp, "<- current" if i == Game.current_car_index else ""])
			return "\n".join(out2)
		"car":
			if args.is_empty():
				return "usage: car <index|name>"
			var idx := Game.car_index_by_name(" ".join(args))
			if idx < 0:
				return "no car matches '%s' (see: cars)" % " ".join(args)
			main.spawn_car(idx, car.global_transform)
			return "now driving %s" % Game.cars[idx].display_name
		"respawn", "reset":
			main.respawn_on_road()
			return "back on the road"
		"repair":
			var xf := car.global_transform
			var fwd := -xf.basis.z
			fwd.y = 0
			car.teleport(Transform3D(Basis.looking_at(fwd.normalized(), Vector3.UP), xf.origin + Vector3.UP * 1.0))
			return "repaired and upright"
		"places":
			return ", ".join(_targets().keys())
		"tp":
			if args.is_empty():
				return "usage: tp <target>  (see: places)"
			var key := " ".join(args).to_lower()
			var t := _targets()
			for k in t:
				if k.begins_with(key):
					main.teleport_player(t[k])
					return "teleported to %s" % k
			return "unknown target '%s'" % key
		"time":
			if args.is_empty():
				return "time is %.2f" % Game.time_of_day
			w.sky.set_time(float(args[0]))
			w.sky.time_frozen = args.size() > 1 and args[1] == "freeze"
			return "time set to %.1f%s" % [Game.time_of_day, " (frozen)" if w.sky.time_frozen else ""]
		"timescale":
			if args.is_empty():
				return "day speed %.2f game-hours per real minute" % (w.sky.time_speed * 60.0)
			w.sky.time_speed = float(args[0]) / 60.0
			return "day speed set"
		"weather":
			if args.is_empty():
				return "weather: %s (presets: %s)" % [Game.weather_name, ", ".join(w.sky.presets.keys())]
			if args[0] == "auto":
				w.sky.auto_weather = not w.sky.auto_weather
				return "auto weather %s" % ("on" if w.sky.auto_weather else "off")
			if w.sky.set_weather(args[0], args.size() > 1 and args[1] == "now"):
				return "weather -> %s (grip x%.2f)" % [args[0], w.sky.presets[args[0]].grip]
			return "unknown weather '%s'" % args[0]
		"traffic":
			if args.is_empty():
				return "traffic density %.2f" % Game.settings.traffic_density
			Game.settings.traffic_density = clampf(float(args[0]), 0.0, 1.0)
			return "traffic density %.2f" % Game.settings.traffic_density
		"speed":
			Game.settings.show_speed = not Game.settings.show_speed
			return "speed display %s" % Game.settings.show_speed
		"fps":
			Game.settings.show_fps = not Game.settings.show_fps
			return "fps display %s" % Game.settings.show_fps
		"telemetry":
			Game.settings["telemetry"] = not Game.settings.get("telemetry", false)
			return "telemetry %s" % Game.settings.telemetry
		"assist":
			if args.size() < 2 or not Game.assists.has(args[0]):
				return "usage: assist <%s> on|off" % "|".join(Game.assists.keys())
			Game.set_assist(args[0], args[1] in ["on", "1", "true"])
			return "%s %s" % [args[0], "on" if Game.assists[args[0]] else "off"]
		"paint":
			if args.is_empty():
				return "usage: paint <colour|#hex> [finish]. colours: " + ", ".join(COLORS.keys())
			var col: Color
			if COLORS.has(args[0]):
				col = COLORS[args[0]]
			elif Color.html_is_valid(args[0]):
				col = Color.html(args[0])
			else:
				return "unknown colour"
			var finish: String = args[1] if args.size() > 1 else str(Game.custom_for(car.spec.id).get("finish", car.spec.paint_finish))
			var c2 := Game.custom_for(car.spec.id)
			c2["color"] = col
			c2["finish"] = finish
			car.apply_paint(col, finish)
			Game.save_game()
			return "painted %s (%s)" % [args[0], finish]
		"units":
			Game.settings.units_mph = args.size() > 0 and args[0] == "mph"
			return "units %s" % Game.speed_unit()
		"camera":
			main.camera.mode = clampi(int(args[0]) if args.size() > 0 else 0, 0, 4)
			return "camera %s" % CarCamera.MODE_NAMES[main.camera.mode]
		"photo":
			if main.has_method("toggle_photo_mode"):
				main.toggle_photo_mode()
				return "photo mode toggled"
			return "photo mode unavailable"
		"save":
			Game.save_game()
			return "saved to %s" % ProjectSettings.globalize_path(Game.SAVE_PATH)
		"load":
			if Game.load_game():
				get_tree().reload_current_scene()
				return "loading..."
			return "no save found"
		"credits":
			return "credits: %d" % Game.credits
		"events":
			if w.activities and w.activities.has_method("describe"):
				return w.activities.describe()
			return "no activities"
		"waypoint":
			if args.is_empty():
				if main.has_method("clear_waypoint"):
					main.clear_waypoint()
				return "waypoint cleared"
			var t2 := _targets()
			var key2 := " ".join(args).to_lower()
			for k in t2:
				if k.begins_with(key2) and main.has_method("set_waypoint"):
					main.set_waypoint((t2[k] as Transform3D).origin)
					return "route set to %s" % k
			return "unknown place"
	return "unknown command '%s' — try help" % cmd


func _targets() -> Dictionary:
	var w: World = main.world
	var d := w.data
	var t := {}
	var regions := {
		"valley": ["river_road", 0.45], "highlands": ["festival_loop", 0.52], "mesa": ["mesa_run", 0.5],
		"coast": ["festival_loop", 0.12], "loop": ["festival_loop", 0.0], "highway": ["valley_highway", 0.05],
		"bay bridge": ["festival_loop", 0.158], "hairpins": ["festival_loop", 0.49], "tunnel": ["festival_loop", 0.405],
		"desert speedway": ["ochre_speedway", 0.05], "dunes": ["dune_track", 0.1], "gravel forest": ["pinewood_gravel", 0.1],
	}
	# structure targets found from the road flags
	var loop := d.road_by_id("festival_loop")
	if loop:
		var best_b := Vector2i(-1, -1)
		var best_t := Vector2i(-1, -1)
		var i := 0
		while i < loop.flags.size():
			var f := loop.flags[i]
			if f == 0:
				i += 1
				continue
			var j := i
			while j < loop.flags.size() and loop.flags[j] == f:
				j += 1
			if f == 1 and j - i > best_b.y - best_b.x:
				best_b = Vector2i(i, j)
			if f == 2 and j - i > best_t.y - best_t.x:
				best_t = Vector2i(i, j)
			i = j
		if best_b.x >= 0:
			regions["bay bridge"] = ["festival_loop", float(maxi(best_b.x - 25, 0)) / (loop.pts.size() - 2)]
		if best_t.x >= 0:
			regions["tunnel"] = ["festival_loop", float(maxi(best_t.x - 30, 0)) / (loop.pts.size() - 2)]
	for k in regions:
		var r := d.road_by_id(regions[k][0])
		if r:
			var i := int(regions[k][1] * (r.pts.size() - 2))
			t[k] = d.road_spawn(r, i, r.width * 0.25)
	if w.activities and w.activities.has_method("event_targets"):
		var ev: Dictionary = w.activities.event_targets()
		for k in ev:
			t[k] = ev[k]
	for p in d.places:
		var pos := Vector3(p.pos[0], 0, p.pos[1])
		var nr := d.nearest_road(pos, 400.0)
		if not nr.is_empty():
			var road: WorldData.Road = nr.road
			t[(p.name as String).to_lower()] = d.road_spawn(road, nr.seg, road.width * 0.25)
	return t
