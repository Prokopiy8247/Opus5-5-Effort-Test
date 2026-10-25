extends Control
## Driving HUD: speedometer/tachometer, gear, assists, surface, minimap, telemetry.

var main: Node
var tach: Tach
var minimap: Minimap
var speed_label: Label
var unit_label: Label
var gear_label: Label
var info_label: Label
var road_label: Label
var assist_row: HBoxContainer
var assist_labels := {}
var telemetry: Label
var hint: Label
var hidden_hud := false
var _frame := 0


class Tach extends Control:
	var rpm := 0.0
	var redline := 7000.0
	var max_rpm := 8000.0
	var throttle := 0.0

	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.5 - 8.0
		var a0 := deg_to_rad(135.0)
		var sweep := deg_to_rad(270.0)
		draw_circle(c, r + 6.0, Color(0.03, 0.04, 0.07, 0.72))
		draw_arc(c, r, a0, a0 + sweep, 96, Color(1, 1, 1, 0.12), 10.0, true)
		var red_a := a0 + sweep * (redline / max_rpm)
		draw_arc(c, r, red_a, a0 + sweep, 32, Color(1.0, 0.25, 0.2, 0.75), 10.0, true)
		var f := clampf(rpm / max_rpm, 0.0, 1.0)
		var col := UIStyle.ACCENT if rpm < redline * 0.92 else Color(1.0, 0.3, 0.25)
		draw_arc(c, r, a0, a0 + sweep * f, 96, col, 10.0, true)
		var k := 0
		while k <= int(max_rpm / 1000.0):
			var a := a0 + sweep * (k * 1000.0 / max_rpm)
			var dir := Vector2(cos(a), sin(a))
			draw_line(c + dir * (r - 16.0), c + dir * (r - 4.0), Color(1, 1, 1, 0.7), 2.0, true)
			var font := get_theme_default_font()
			var txt := str(k)
			draw_string(font, c + dir * (r - 32.0) - Vector2(6, -6), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(1, 1, 1, 0.75))
			k += 1
		var na := a0 + sweep * f
		draw_line(c, c + Vector2(cos(na), sin(na)) * (r - 10.0), Color(1, 1, 1, 0.95), 3.0, true)
		draw_circle(c, 7.0, UIStyle.ACCENT)
		# throttle sliver
		draw_arc(c, r + 12.0, a0, a0 + sweep * throttle * 0.25, 24, UIStyle.ACCENT2, 4.0, true)


class Minimap extends Control:
	var data: WorldData
	var player: Node3D
	var roads_2d: Array = []
	var road_cls: Array = []
	var meters := 520.0
	var markers: Array = []      # [{pos: Vector2, color: Color, icon: String}]
	var route := PackedVector2Array()
	var traffic_dots := PackedVector2Array()

	func setup(d: WorldData) -> void:
		data = d
		for road in d.roads:
			var pts := PackedVector2Array()
			var step := 3
			for i in range(0, road.pts.size(), step):
				pts.append(Vector2(road.pts[i].x, road.pts[i].z))
			pts.append(Vector2(road.pts[road.pts.size() - 1].x, road.pts[road.pts.size() - 1].z))
			roads_2d.append(pts)
			road_cls.append(road.cls)
		clip_contents = true

	func _draw() -> void:
		var sz := size
		draw_rect(Rect2(Vector2.ZERO, sz), Color(0.06, 0.09, 0.12, 0.78))
		if player == null or data == null:
			return
		var p := Vector2(player.global_position.x, player.global_position.z)
		var fwd := -player.global_transform.basis.z
		var heading := atan2(fwd.x, -fwd.z)
		var scale := sz.x / meters
		var xf := Transform2D(0.0, sz * 0.5) * Transform2D(-heading, Vector2.ZERO) * Transform2D(0.0, Vector2(scale, scale), 0.0, Vector2.ZERO) * Transform2D(0.0, -p)
		draw_set_transform_matrix(xf)
		# sea hint: draw coast? keep simple: river line
		for i in roads_2d.size():
			var cls: String = road_cls[i]
			var w := 6.0
			var col := Color(0.85, 0.88, 0.92, 0.9)
			match cls:
				"highway":
					w = 11.0
					col = Color(1.0, 0.8, 0.35, 0.95)
				"regional", "mountain":
					w = 8.0
				"lane":
					w = 6.0
					col = Color(0.75, 0.78, 0.82, 0.8)
				_:
					w = 5.0
					col = Color(0.7, 0.55, 0.38, 0.85)
			draw_polyline(roads_2d[i], Color(0, 0, 0, 0.5), (w + 5.0) / scale * 0.5, false)
			draw_polyline(roads_2d[i], col, w / scale * 0.5, false)
		if route.size() > 1:
			draw_polyline(route, Color(0.3, 0.9, 1.0, 0.95), 7.0 / scale, false)
		for d in traffic_dots:
			draw_circle(d, 3.0 / scale, Color(0.9, 0.9, 0.95, 0.85))
		for m in markers:
			var mp: Vector2 = m.pos
			draw_circle(mp, 7.0 / scale, Color(0, 0, 0, 0.6))
			draw_circle(mp, 5.0 / scale, m.color)
		draw_set_transform_matrix(Transform2D.IDENTITY)
		# player arrow (always up)
		var c := sz * 0.5
		var tri := PackedVector2Array([c + Vector2(0, -11), c + Vector2(8, 9), c + Vector2(0, 5), c + Vector2(-8, 9)])
		draw_colored_polygon(tri, UIStyle.ACCENT)
		draw_polyline(PackedVector2Array([tri[0], tri[1], tri[2], tri[3], tri[0]]), Color(0, 0, 0, 0.6), 1.5)
		# north marker
		var n_dir := Vector2(sin(-heading), -cos(-heading))
		var npos := c + n_dir * (sz.x * 0.5 - 14.0)
		draw_circle(npos, 10.0, Color(0, 0, 0, 0.55))
		draw_string(get_theme_default_font(), npos + Vector2(-5, 6), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color.WHITE)
		draw_rect(Rect2(Vector2.ZERO, sz), Color(1, 1, 1, 0.15), false, 2.0)


func init_ui(m: Node) -> void:
	main = m
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# speedometer
	tach = Tach.new()
	UIStyle.place(tach, Control.PRESET_BOTTOM_RIGHT, -340, -350, -50, -60)
	tach.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(tach)
	speed_label = UIStyle.label("0", 70, UIStyle.TEXT, true)
	speed_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	speed_label.position = Vector2(45, 95)
	speed_label.size = Vector2(200, 80)
	tach.add_child(speed_label)
	unit_label = UIStyle.label("KM/H", 16, UIStyle.TEXT_DIM)
	unit_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	unit_label.position = Vector2(45, 170)
	unit_label.size = Vector2(200, 24)
	tach.add_child(unit_label)
	gear_label = UIStyle.label("1", 40, UIStyle.ACCENT, true)
	gear_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	gear_label.position = Vector2(105, 198)
	gear_label.size = Vector2(80, 50)
	tach.add_child(gear_label)
	assist_row = HBoxContainer.new()
	UIStyle.place(assist_row, Control.PRESET_BOTTOM_RIGHT, -330, -46, -40, -22)
	assist_row.add_theme_constant_override("separation", 6)
	add_child(assist_row)
	for k in ["TCS", "STM", "ABS", "AUTO"]:
		var pc := PanelContainer.new()
		var sb := UIStyle.panel(Color(0, 0, 0, 0.5), 5)
		sb.content_margin_left = 6
		sb.content_margin_right = 6
		sb.content_margin_top = 1
		sb.content_margin_bottom = 1
		pc.add_theme_stylebox_override("panel", sb)
		var l := UIStyle.label(k, 14, UIStyle.TEXT_DIM)
		pc.add_child(l)
		assist_row.add_child(pc)
		assist_labels[k] = l
	info_label = UIStyle.label("", 15, UIStyle.TEXT_DIM)
	UIStyle.place(info_label, Control.PRESET_BOTTOM_RIGHT, -460, -380, -50, -354)
	info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(info_label)
	# minimap
	minimap = Minimap.new()
	UIStyle.place(minimap, Control.PRESET_BOTTOM_LEFT, 36, -330, 326, -40)
	minimap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(minimap)
	minimap.setup(Game.world.data)
	road_label = UIStyle.label("", 17, UIStyle.TEXT)
	UIStyle.place(road_label, Control.PRESET_BOTTOM_LEFT, 38, -362, 500, -334)
	add_child(road_label)
	telemetry = UIStyle.label("", 15, UIStyle.TEXT)
	UIStyle.place(telemetry, Control.PRESET_TOP_RIGHT, -560, 16, -20, 400)
	telemetry.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(telemetry)
	hint = UIStyle.label("Tab  Garage     `  Console     F2  Debug     M  Map     C  Camera     R  Reset", 15, Color(1, 1, 1, 0.55))
	UIStyle.place(hint, Control.PRESET_CENTER_BOTTOM, -460, -30, 460, -6)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(hint)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_toggle_hud"):
		hidden_hud = not hidden_hud
		visible = not hidden_hud


func _process(_delta: float) -> void:
	var _t0 := Time.get_ticks_usec()
	_process_inner(_delta)
	Game.prof_add("hud", Time.get_ticks_usec() - _t0)


func _process_inner(_delta: float) -> void:
	if main == null or main.player == null or not is_instance_valid(main.player):
		return
	var car: Car = main.player
	tach.rpm = car.rpm
	tach.redline = car.spec.redline_rpm
	tach.max_rpm = ceilf((car.spec.redline_rpm + 600.0) / 1000.0) * 1000.0
	tach.throttle = car.throttle_applied
	tach.queue_redraw()
	speed_label.text = Game.speed_text(absf(car.forward_speed))
	unit_label.text = Game.speed_unit()
	gear_label.text = "R" if car.gear == -1 else ("N" if car.gear == 0 else str(car.gear))
	_set_assist("TCS", Game.assists.tcs, car.tcs_active)
	_set_assist("STM", Game.assists.stm, false)
	_set_assist("ABS", Game.assists.abs, car.abs_active)
	assist_labels["AUTO"].text = "AUTO" if Game.assists.auto else "MAN"
	_set_assist("AUTO", true, false)
	var surf := Game.surface(car.surface_id)
	var sname := surf.display_name
	if Game.wetness > 0.3 and not surf.is_offroad:
		sname = "Wet " + sname.to_lower()
	info_label.text = "%s    %s %s" % [sname, Game.weather_name.capitalize(), _clock()]
	minimap.player = car
	if Game.world.traffic:
		minimap.traffic_dots = (Game.world.traffic as TrafficManager).minimap_dots()
	if Game.world.activities and Game.world.activities.has_method("minimap_markers"):
		minimap.markers = Game.world.activities.minimap_markers()
	if main.get("route_2d") != null:
		minimap.route = main.route_2d
	minimap.queue_redraw()
	_frame += 1
	if _frame % 12 == 0:
		var nr: Dictionary = Game.world.data.nearest_road(car.global_position, 40.0)
		road_label.text = (nr.road as WorldData.Road).name if not nr.is_empty() else "Off road"
	var lines: PackedStringArray = []
	if Game.settings.show_fps:
		lines.append("FPS %d   frame %.1f ms" % [Engine.get_frames_per_second(), 1000.0 / maxf(Engine.get_frames_per_second(), 1)])
		var p := car.global_position
		lines.append("pos %.0f, %.0f, %.0f" % [p.x, p.y, p.z])
	if Game.settings.get("telemetry", false):
		lines.append("RPM %d  gear %d  thr %.2f" % [car.rpm, car.gear, car.throttle_applied])
		lines.append("slip lat %.2f  drift %.0f°" % [car.avg_slip(), car.drift_angle])
		lines.append("wheels on ground %d  surface %s" % [car.wheels_on_ground, surf.key])
		lines.append("grip x%.2f (weather)  mass %.0f kg" % [Game.weather_grip, car.mass])
		for w in car.wheels:
			lines.append("%s load %5.0f N  comp %.3f  slip %.2f/%.2f" % [w.name.substr(6), w.load, w.compression, w.slip_lat, w.slip_long])
	telemetry.text = "\n".join(lines)


func _set_assist(k: String, enabled: bool, active: bool) -> void:
	var l: Label = assist_labels[k]
	var col := UIStyle.TEXT_DIM
	if enabled:
		col = UIStyle.ACCENT2
	if active:
		col = UIStyle.ACCENT
	l.add_theme_color_override("font_color", col)
	l.modulate.a = 1.0 if enabled else 0.4


func _clock() -> String:
	var h := Game.time_of_day
	return "%02d:%02d" % [int(h), int(fmod(h, 1.0) * 60.0)]
