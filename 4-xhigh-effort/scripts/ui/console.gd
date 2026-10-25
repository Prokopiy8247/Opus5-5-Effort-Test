extends PanelContainer
## Developer console (toggle with ` / ~). Commands are testing tools and never alter free roam
## beyond what they explicitly do. Type "help" for the list.

var log_box: RichTextLabel
var input: LineEdit
var history: PackedStringArray = []
var _hist_i := 0
var commands := {}


func _ready() -> void:
	add_theme_stylebox_override("panel", UITheme.panel_box(Color(0.02, 0.03, 0.06, 0.9), 12, UITheme.CYAN.darkened(0.3)))
	UITheme.place(self, 0.0, 0.0, 20, 20, 980, 460)
	var vb := VBoxContainer.new()
	add_child(vb)
	var title := UITheme.label("CONSOLE  —  type help   (` to close)", 16, UITheme.CYAN, true)
	vb.add_child(title)
	log_box = RichTextLabel.new()
	log_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	log_box.scroll_following = true
	log_box.bbcode_enabled = true
	log_box.add_theme_font_size_override("normal_font_size", 17)
	vb.add_child(log_box)
	input = LineEdit.new()
	input.placeholder_text = "command..."
	input.text_submitted.connect(_on_submit)
	input.gui_input.connect(_on_input_gui)
	vb.add_child(input)
	visible = false
	_register()
	print_line("[color=#ffc93c]VALORIA console.[/color] Commands: " + ", ".join(commands.keys()))


func _register() -> void:
	commands = {
		"help": ["[command]", "list commands or describe one", _c_help],
		"cars": ["", "list the 10 cars", _c_cars],
		"car": ["<index|name>", "switch to a car at the current location", _c_car],
		"respawn": ["", "put the car back on the nearest road", _c_respawn],
		"reset": ["", "flip upright where you are", _c_reset],
		"repair": ["", "reset damage and stop the car", _c_repair],
		"tp": ["<region|poi|x z>", "teleport (regions: valley, highlands, canyons, coast)", _c_tp],
		"time": ["<hour> [speed]", "set time of day (0-24) and optional game hours per real minute", _c_time],
		"weather": ["<clear|cloudy|rain|fog|storm|auto>", "set weather (auto resumes the cycle)", _c_weather],
		"traffic": ["<0..1>", "traffic density (0 = off)", _c_traffic],
		"speed": ["", "toggle speedometer units km/h / mph", _c_speed],
		"fps": ["", "toggle the FPS readout", _c_fps],
		"coords": ["", "toggle coordinates readout", _c_coords],
		"telemetry": ["", "toggle telemetry panel", _c_telemetry],
		"assist": ["<abs|tcs|stm|steer|auto_gear|all> on|off", "toggle driving assists", _c_assist],
		"paint": ["<colour|#rrggbb> [gloss|metallic|matte|pearl]", "repaint the current car", _c_paint],
		"stripe": ["<0-3> [colour]", "livery stripes: 0 none, 1 twin, 2 side, 3 wide", _c_stripe],
		"upgrade": ["<engine|tires|suspension|brakes|weight|aero> <0-3>", "set an upgrade level", _c_upgrade],
		"camera": ["<chase|far|hood|cockpit|bumper>", "camera mode", _c_camera],
		"waypoint": ["<poi|x z|clear>", "set GPS waypoint", _c_waypoint],
		"pois": ["", "list points of interest", _c_pois],
		"events": ["", "list activities", _c_events],
		"event": ["<id|name>", "teleport to an activity (races: Enter at the arch starts)", _c_event],
		"save": ["", "save progress", _c_save],
		"load": ["", "load progress", _c_load],
		"bench": ["[seconds]", "benchmark drive along the loop with the autopilot", _c_bench],
		"quit": ["", "quit the game", func(_a: PackedStringArray) -> void: get_tree().quit()],
	}


func toggle() -> void:
	visible = not visible
	Game.set_ui_focus("console", visible)
	if visible:
		input.grab_focus()
		input.clear()
	else:
		input.release_focus()


func print_line(s: String) -> void:
	log_box.append_text(s + "\n")


func _on_input_gui(ev: InputEvent) -> void:
	if ev is InputEventKey and ev.pressed:
		var k := ev as InputEventKey
		if k.keycode == KEY_UP and history.size() > 0:
			_hist_i = maxi(_hist_i - 1, 0)
			input.text = history[_hist_i]
			input.caret_column = input.text.length()
			accept_event()
		elif k.keycode == KEY_DOWN and history.size() > 0:
			_hist_i = mini(_hist_i + 1, history.size())
			input.text = history[_hist_i] if _hist_i < history.size() else ""
			accept_event()
		elif k.physical_keycode == KEY_QUOTELEFT:
			toggle()
			accept_event()


func _on_submit(text: String) -> void:
	input.clear()
	text = text.strip_edges()
	if text == "":
		return
	history.append(text)
	_hist_i = history.size()
	print_line("[color=#2de1fc]> %s[/color]" % text)
	run(text)


func run(text: String) -> void:
	var parts := text.split(" ", false)
	var cmd := parts[0].to_lower()
	var args := parts.slice(1)
	if not commands.has(cmd):
		print_line("[color=#ff3d7f]Unknown command '%s'. Try help.[/color]" % cmd)
		return
	(commands[cmd][2] as Callable).call(args)


func _c_help(a: PackedStringArray) -> void:
	if a.size() > 0 and commands.has(a[0]):
		print_line("%s %s — %s" % [a[0], commands[a[0]][0], commands[a[0]][1]])
		return
	for k: String in commands:
		print_line("[color=#ffc93c]%s[/color] %s — %s" % [k, commands[k][0], commands[k][1]])


func _c_cars(_a: PackedStringArray) -> void:
	for i in Game.cars.size():
		var d := Game.cars[i]
		print_line("%2d  %-22s %s  %s  %d kW  %d kg%s" % [i + 1, d.display_name, d.car_class, d.drivetrain_name(),
			roundi(d.peak_power_kw()), roundi(d.mass), "   <" if i == Game.current_car else ""])


func _c_car(a: PackedStringArray) -> void:
	if a.is_empty():
		print_line("usage: car <index|name>")
		return
	var i := Game.car_index_by_name(" ".join(a))
	if i < 0:
		print_line("[color=#ff3d7f]No car '%s'[/color]" % " ".join(a))
		return
	Game.main.switch_car(i)
	print_line("Now driving %s" % Game.cars[i].display_name)


func _c_respawn(_a: PackedStringArray) -> void:
	Game.reset_player_to_road()


func _c_reset(_a: PackedStringArray) -> void:
	if Game.player:
		Game.player.flip_upright()


func _c_repair(_a: PackedStringArray) -> void:
	if Game.player:
		Game.player.linear_velocity = Vector3.ZERO
		Game.player.angular_velocity = Vector3.ZERO
		Game.player.flip_upright()
		print_line("Repaired.")


func _c_tp(a: PackedStringArray) -> void:
	if a.is_empty():
		print_line("usage: tp <valley|highlands|canyons|coast|poi id|x z>")
		return
	var target := Vector3.INF
	if a.size() >= 2 and a[0].is_valid_float() and a[1].is_valid_float():
		target = Vector3(float(a[0]), 0, float(a[1]))
	else:
		target = Game.main.find_place(" ".join(a))
	if target == Vector3.INF:
		print_line("[color=#ff3d7f]Unknown place '%s' (see pois)[/color]" % " ".join(a))
		return
	Game.main.teleport_to(target)
	print_line("Teleported.")


func _c_time(a: PackedStringArray) -> void:
	if a.is_empty() or not a[0].is_valid_float():
		print_line("usage: time <hour> [speed]")
		return
	Game.sky.set_time(float(a[0]))
	if a.size() > 1 and a[1].is_valid_float():
		Game.sky.time_speed = float(a[1]) / 60.0
	print_line("Time set to %s" % a[0])


func _c_weather(a: PackedStringArray) -> void:
	if a.is_empty():
		print_line("usage: weather <clear|cloudy|rain|fog|storm|auto>")
		return
	if a[0] == "auto":
		Game.sky.auto_weather = true
		print_line("Weather cycle resumed.")
		return
	if Game.sky.set_weather(a[0], a.size() > 1 and a[1] == "now"):
		Game.sky.auto_weather = false
		print_line("Weather: %s (cycle paused; 'weather auto' resumes)" % a[0])
	else:
		print_line("[color=#ff3d7f]Unknown weather[/color]")


func _c_traffic(a: PackedStringArray) -> void:
	if a.is_empty() or not a[0].is_valid_float():
		print_line("usage: traffic <0..1>")
		return
	Game.settings.traffic_density = clampf(float(a[0]), 0.0, 1.5)
	print_line("Traffic density %.2f" % Game.settings.traffic_density)


func _c_speed(_a: PackedStringArray) -> void:
	Game.settings.units_kmh = not Game.settings.units_kmh
	print_line("Units: %s" % Game.speed_unit())


func _c_fps(_a: PackedStringArray) -> void:
	Game.settings.show_fps = not Game.settings.show_fps


func _c_coords(_a: PackedStringArray) -> void:
	Game.settings.show_coords = not bool(Game.settings.get("show_coords", false))


func _c_telemetry(_a: PackedStringArray) -> void:
	Game.settings.show_telemetry = not Game.settings.show_telemetry


func _c_assist(a: PackedStringArray) -> void:
	if a.size() < 2:
		print_line("usage: assist <abs|tcs|stm|steer|auto_gear|all> on|off   now: %s" % str(Game.settings.assists))
		return
	var on := a[1] == "on" or a[1] == "1" or a[1] == "true"
	var names := ["abs", "tcs", "stm", "steer", "auto_gear"] if a[0] == "all" else [a[0]]
	for n: String in names:
		if not Game.settings.assists.has(n):
			print_line("[color=#ff3d7f]Unknown assist %s[/color]" % n)
			return
		Game.set_assist(n, on)
	print_line("Assists: %s" % str(Game.settings.assists))


const NAMED_COLORS := {"red": Color(0.78, 0.07, 0.05), "blue": Color(0.05, 0.2, 0.75), "yellow": Color(0.98, 0.75, 0.05),
	"green": Color(0.08, 0.5, 0.18), "black": Color(0.02, 0.02, 0.025), "white": Color(0.92, 0.92, 0.9),
	"silver": Color(0.65, 0.66, 0.68), "orange": Color(1.0, 0.4, 0.02), "purple": Color(0.4, 0.08, 0.6),
	"pink": Color(1.0, 0.3, 0.55), "teal": Color(0.0, 0.55, 0.55), "gold": Color(0.75, 0.55, 0.15), "grey": Color(0.3, 0.31, 0.33)}


func _c_paint(a: PackedStringArray) -> void:
	if a.is_empty():
		print_line("usage: paint <colour|#rrggbb> [gloss|metallic|matte|pearl]   colours: " + ", ".join(NAMED_COLORS.keys()))
		return
	var col: Color
	if NAMED_COLORS.has(a[0]):
		col = NAMED_COLORS[a[0]]
	elif a[0].begins_with("#") and a[0].length() == 7:
		col = Color.html(a[0])
	else:
		print_line("[color=#ff3d7f]Unknown colour[/color]")
		return
	var p := Game.paint_for(Game.player.data.id)
	p.color = col
	if a.size() > 1:
		var fi := ["gloss", "metallic", "matte", "pearl"].find(a[1])
		if fi >= 0:
			p.finish = fi
	Game.player.visual.set_paint(p.color, p.finish, p.stripe, p.stripe_color)
	print_line("Painted %s %s" % [a[0], CarMaterials.FINISH_NAMES[p.finish]])


func _c_stripe(a: PackedStringArray) -> void:
	if a.is_empty() or not a[0].is_valid_int():
		print_line("usage: stripe <0-3> [colour]")
		return
	var p := Game.paint_for(Game.player.data.id)
	p.stripe = clampi(int(a[0]), 0, 3)
	if a.size() > 1 and NAMED_COLORS.has(a[1]):
		p.stripe_color = NAMED_COLORS[a[1]]
	Game.player.visual.set_paint(p.color, p.finish, p.stripe, p.stripe_color)


func _c_upgrade(a: PackedStringArray) -> void:
	if a.size() < 2 or not a[1].is_valid_int() or not Upgrades.CATEGORIES.has(a[0]):
		print_line("usage: upgrade <%s> <0-3>" % "|".join(Upgrades.CATEGORIES))
		return
	Game.upgrades_for(Game.player.data.id)[a[0]] = clampi(int(a[1]), 0, 3)
	Game.main.apply_car_setup()
	print_line("%s set to %s" % [a[0], Upgrades.LEVEL_NAMES[clampi(int(a[1]), 0, 3)]])


func _c_camera(a: PackedStringArray) -> void:
	var modes := ["chase", "far", "hood", "cockpit", "bumper"]
	if a.is_empty() or not modes.has(a[0]):
		print_line("usage: camera <%s>" % "|".join(modes))
		return
	Game.camera.mode = modes.find(a[0]) as CarCamera.Mode


func _c_waypoint(a: PackedStringArray) -> void:
	var nav: Node = Game.main.get("nav")
	if nav == null:
		return
	if a.is_empty() or a[0] == "clear":
		nav.clear_waypoint()
		print_line("Waypoint cleared.")
		return
	var target := Vector3.INF
	if a.size() >= 2 and a[0].is_valid_float():
		target = Vector3(float(a[0]), 0, float(a[1]))
	else:
		target = Game.main.find_place(" ".join(a))
	if target == Vector3.INF:
		print_line("[color=#ff3d7f]Unknown place[/color]")
		return
	nav.set_waypoint(target)
	print_line("Waypoint set. Follow the pink line.")


func _c_pois(_a: PackedStringArray) -> void:
	for p: Dictionary in Game.world.wd.pois:
		print_line("%-12s %-30s %5.0f %5.0f" % [p.id, p.name, p.pos.x, p.pos.z])


func _c_events(_a: PackedStringArray) -> void:
	if Game.activities == null:
		return
	for e: Dictionary in Game.world.wd.activities:
		print_line("%-12s %-30s %s" % [e.type, e.name, e.id])


func _c_event(a: PackedStringArray) -> void:
	if Game.activities == null or a.is_empty():
		print_line("usage: event <id|name>  (see 'events')")
		return
	var e: Dictionary = Game.activities.find(" ".join(a))
	if e.is_empty():
		print_line("[color=#ff3d7f]No such activity[/color]")
		return
	Game.activities.teleport_to(e)
	print_line("At %s (%s)" % [e.name, e.type])


func _c_save(_a: PackedStringArray) -> void:
	print_line("Saved." if SaveSystem.save_game() else "[color=#ff3d7f]Save failed[/color]")


func _c_load(_a: PackedStringArray) -> void:
	print_line("Loaded." if SaveSystem.load_game(true) else "[color=#ff3d7f]No save found[/color]")


func _c_bench(a: PackedStringArray) -> void:
	var secs := float(a[0]) if a.size() > 0 and a[0].is_valid_float() else 60.0
	Game.main.start_benchmark(secs)
	toggle()
