extends PanelContainer
## Developer console (toggle with ` / ~). Commands drive the same systems as the menus.

var log_label: RichTextLabel
var input: LineEdit
var history: PackedStringArray = []
var hist_i: int = 0
var main: Node


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	custom_minimum_size = Vector2(0, 420)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.03, 0.04, 0.07, 0.9)
	sb.border_color = Color(1.0, 0.36, 0.62)
	sb.border_width_bottom = 3
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	add_theme_stylebox_override("panel", sb)
	var v := VBoxContainer.new()
	add_child(v)
	log_label = RichTextLabel.new()
	log_label.bbcode_enabled = true
	log_label.scroll_following = true
	log_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	log_label.add_theme_font_size_override("normal_font_size", 17)
	v.add_child(log_label)
	input = LineEdit.new()
	input.placeholder_text = "type a command (help)"
	input.add_theme_font_size_override("font_size", 18)
	input.text_submitted.connect(_on_submit)
	input.gui_input.connect(_on_input_key)
	v.add_child(input)
	visible = false
	out("[color=#ff5c9e]%s developer console[/color] - type [b]help[/b]" % Game.TITLE)


func toggle() -> void:
	visible = not visible
	if visible:
		input.grab_focus()
		input.clear()
	else:
		input.release_focus()


func out(t: String) -> void:
	log_label.append_text(t + "\n")


func _on_input_key(ev: InputEvent) -> void:
	if ev is InputEventKey and ev.pressed:
		if ev.keycode == KEY_UP and not history.is_empty():
			hist_i = clampi(hist_i - 1, 0, history.size() - 1)
			input.text = history[hist_i]
			input.caret_column = input.text.length()
			accept_event()
		elif ev.keycode == KEY_DOWN and not history.is_empty():
			hist_i = clampi(hist_i + 1, 0, history.size())
			input.text = history[hist_i] if hist_i < history.size() else ""
			accept_event()
		elif ev.keycode == KEY_QUOTELEFT:
			toggle()
			accept_event()


func _on_submit(t: String) -> void:
	input.clear()
	if t.strip_edges() == "":
		return
	history.append(t)
	hist_i = history.size()
	out("[color=#9ad]> %s[/color]" % t)
	out(run(t))


## Executes a command line and returns the response text (also used by automated tests).
func run(line: String) -> String:
	var parts: PackedStringArray = line.strip_edges().split(" ", false)
	if parts.is_empty():
		return ""
	var cmd: String = parts[0].to_lower()
	var args: PackedStringArray = parts.slice(1)
	var a0: String = args[0].to_lower() if args.size() > 0 else ""
	var car: Car = Game.player as Car
	match cmd:
		"help":
			return "cars | car <index|name> | respawn | reset | repair | flip | tp <place> | tp list | time <hour> | timescale <x> | freeze on|off\n" + \
				"weather <clear|cloudy|rain|fog|storm|snow|auto> | traffic <0..1> | speed | fps | telemetry | assist <tcs|esc|abs|steer|all> on|off\n" + \
				"gears auto|manual | paint <colour|#hex> [gloss|metallic|matte] | stripe <none|centre|side|roof> [colour] | rims <colour>\n" + \
				"upgrade <engine|tires|suspension|brakes|weight|aero> <0..3> | units kmh|mph | events | race <n> | save | load | quit"
		"cars":
			var s: String = ""
			for i in Game.cars.size():
				var d: CarDef = Game.cars[i]
				s += "%2d  %-18s %-16s %-3s %3d  %s\n" % [i + 1, d.display_name, d.maker, d.car_class, d.pi, ["FWD", "RWD", "AWD"][d.drive]]
			return s
		"car":
			if args.is_empty():
				return "usage: car <index|name>"
			var idx: int = Game.find_car(" ".join(args))
			if idx < 0:
				return "unknown car"
			main.switch_car(idx)
			return "switched to " + Game.cars[idx].display_name
		"respawn", "reset":
			main.reset_player_to_road()
			return "car reset to the nearest road"
		"repair":
			if car:
				car.damage = 0.0
			return "repaired"
		"flip":
			if car:
				var t: Transform3D = car.global_transform
				var f: Vector3 = -t.basis.z
				f.y = 0
				car.teleport(Transform3D(Basis.looking_at(f.normalized(), Vector3.UP), t.origin + Vector3.UP * 1.5))
			return "flipped upright"
		"tp", "teleport":
			if a0 == "" or a0 == "list":
				return "places: " + ", ".join(RoadLayout.POIS.keys())
			if a0.contains(","):
				var c: PackedStringArray = a0.split(",")
				var nr: Dictionary = Game.world.nearest_road_point(Vector3(c[0].to_float(), 0, c[1].to_float()))
				main.teleport_to(Game.world.road_point(nr.road, nr.s, Game.world.roads[nr.road].lane * 0.5).translated(Vector3.UP * 0.6))
				return "teleported"
			if Game.activities and Game.activities.has_method("teleport_to_event") and Game.activities.teleport_to_event(a0):
				return "teleported to event " + a0
			return "teleported to " + a0 if main.teleport_poi(a0) else "unknown place (tp list)"
		"time":
			if a0 == "":
				return "time is %.1f h" % Game.sky.hour
			Game.sky.set_hour(a0.to_float())
			return "time set to %.1f h" % Game.sky.hour
		"timescale":
			Game.sky.day_speed = a0.to_float() / 60.0
			return "day speed x%s" % a0
		"freeze":
			Game.sky.time_frozen = a0 != "off"
			return "time frozen" if Game.sky.time_frozen else "time running"
		"weather":
			if a0 == "auto":
				Game.sky.auto_weather = true
				return "dynamic weather on"
			Game.sky.auto_weather = false
			return ("weather -> " + a0) if Game.sky.set_weather(a0) else "states: " + ", ".join(SkyWeather.STATES)
		"traffic":
			if a0 == "":
				return "traffic density %.2f" % Game.settings.traffic_density
			Game.settings.traffic_density = clampf(a0.to_float(), 0.0, 1.0)
			return "traffic density %.2f" % Game.settings.traffic_density
		"speed":
			Game.settings.units_mph = not Game.settings.units_mph
			return "units: " + ("mph" if Game.settings.units_mph else "km/h")
		"units":
			Game.settings.units_mph = a0 == "mph"
			return "units: " + ("mph" if Game.settings.units_mph else "km/h")
		"fps":
			Game.settings.show_fps = not Game.settings.show_fps
			return "fps display " + ("on" if Game.settings.show_fps else "off")
		"telemetry":
			var hud: Node = Game.hud
			hud.show_telemetry = not hud.show_telemetry
			return "telemetry " + ("on" if hud.show_telemetry else "off")
		"assist":
			if args.size() < 2:
				return "usage: assist <tcs|esc|abs|steer|all> on|off"
			var on: bool = args[1].to_lower() == "on"
			var keys: Array = ["tcs", "esc", "abs", "steer"] if a0 == "all" else [a0]
			for k in keys:
				if not Game.settings.has("assist_" + k):
					return "unknown assist"
				Game.settings["assist_" + k] = on
			return "assist %s %s" % [a0, "on" if on else "off"]
		"gears":
			Game.settings.manual_gears = a0 == "manual"
			return "gearbox " + ("manual (Q/E)" if Game.settings.manual_gears else "automatic")
		"paint":
			if car == null or a0 == "":
				return "usage: paint <colour|#hex> [gloss|metallic|matte]"
			var col: Color = _parse_color(a0)
			var fin: int = 0
			if args.size() > 1:
				fin = ["gloss", "metallic", "matte"].find(args[1].to_lower())
				fin = maxi(fin, 0)
			var p: Dictionary = Game.paint_overrides.get(car.def.id, {})
			p.color = col
			p.finish = fin
			Game.paint_overrides[car.def.id] = p
			car.set_paint(col, fin, p.get("stripe", 0), p.get("stripe_color", Color.WHITE))
			return "painted " + col.to_html(false)
		"stripe":
			if car == null:
				return "no car"
			var mode: int = maxi(0, ["none", "centre", "side", "roof"].find(a0))
			var p2: Dictionary = Game.paint_overrides.get(car.def.id, {"color": car.def.paint_color, "finish": car.def.paint_finish})
			p2.stripe = mode
			p2.stripe_color = _parse_color(args[1]) if args.size() > 1 else Color.WHITE
			Game.paint_overrides[car.def.id] = p2
			car.set_paint(p2.color, p2.finish, mode, p2.stripe_color)
			return "stripe " + a0
		"rims":
			if car == null or a0 == "":
				return "usage: rims <colour>"
			var rc: Color = _parse_color(a0)
			var p3: Dictionary = Game.paint_overrides.get(car.def.id, {"color": car.def.paint_color, "finish": car.def.paint_finish})
			p3.rim = rc
			Game.paint_overrides[car.def.id] = p3
			car.set_rim_color(rc)
			return "rims " + rc.to_html(false)
		"upgrade":
			if car == null or args.size() < 2:
				return "usage: upgrade <engine|tires|suspension|brakes|weight|aero> <0..3>"
			var up: Dictionary = Game.get_upgrades(car.def.id)
			if not up.has(a0):
				return "unknown part"
			up[a0] = clampi(args[1].to_int(), 0, 3)
			car.apply_mods()
			return "%s upgrade level %d" % [a0, up[a0]]
		"events":
			return Game.activities.list_events() if Game.activities else "no activities"
		"race":
			if Game.activities and Game.activities.has_method("start_race_by_index"):
				return Game.activities.start_race_by_index(a0.to_int())
			return "no races"
		"save":
			var sv: Node = main.save
			return "saved" if sv and sv.save_game() else "save failed"
		"load":
			var sv2: Node = main.save
			return "loaded" if sv2 and sv2.apply_loaded() else "nothing to load"
		"quit":
			get_tree().quit()
			return "bye"
	return "unknown command '%s' (help)" % cmd


static func _parse_color(s: String) -> Color:
	var named: Dictionary = {
		"red": Color(0.8, 0.05, 0.05), "blue": Color(0.05, 0.25, 0.8), "green": Color(0.1, 0.5, 0.15),
		"yellow": Color(0.95, 0.8, 0.05), "orange": Color(1.0, 0.45, 0.05), "white": Color(0.93, 0.93, 0.93),
		"black": Color(0.03, 0.03, 0.03), "silver": Color(0.72, 0.73, 0.75), "pink": Color(1.0, 0.36, 0.62),
		"purple": Color(0.4, 0.1, 0.65), "teal": Color(0.05, 0.55, 0.55), "gold": Color(0.85, 0.65, 0.2),
		"lime": Color(0.6, 0.9, 0.1), "brown": Color(0.35, 0.2, 0.1), "grey": Color(0.4, 0.4, 0.42), "gray": Color(0.4, 0.4, 0.42),
	}
	if named.has(s.to_lower()):
		return named[s.to_lower()]
	if Color.html_is_valid(s):
		return Color.html(s)
	return Color(0.8, 0.1, 0.1)
