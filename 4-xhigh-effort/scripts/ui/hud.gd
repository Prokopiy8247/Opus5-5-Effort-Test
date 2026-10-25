extends Control
## In-car HUD: tachometer/speed/gear cluster (custom drawn), assist and surface indicators,
## region and road names, FPS/coordinates readout and the optional telemetry panel.

var cluster: Control
var top_left: VBoxContainer
var region_lbl: Label
var road_lbl: Label
var info_lbl: Label
var assist_box: HBoxContainer
var assist_lbls := {}
var telemetry: Label
var hint_lbl: Label
var _shown_rpm := 0.0
var _info_timer := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	cluster = Control.new()
	UITheme.place(cluster, 1.0, 1.0, -360, -350, 330, 330)
	cluster.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cluster.draw.connect(_draw_cluster)
	add_child(cluster)
	top_left = VBoxContainer.new()
	UITheme.place(top_left, 0.0, 0.0, 28, 22, 600, 80)
	top_left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(top_left)
	region_lbl = UITheme.label("", 26, UITheme.SUN, true)
	road_lbl = UITheme.label("", 19, UITheme.DIM)
	top_left.add_child(region_lbl)
	top_left.add_child(road_lbl)
	info_lbl = UITheme.label("", 17, UITheme.DIM)
	UITheme.place(info_lbl, 1.0, 0.0, -340, 18, 320, 80)
	info_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(info_lbl)
	assist_box = HBoxContainer.new()
	UITheme.place(assist_box, 1.0, 1.0, -330, -392, 300, 34)
	assist_box.add_theme_constant_override("separation", 8)
	for a: String in ["TCS", "ABS", "STM", "AUTO"]:
		var l := UITheme.label(a, 15, UITheme.DIM, true)
		var pc := PanelContainer.new()
		pc.add_theme_stylebox_override("panel", UITheme.panel_box(Color(0, 0, 0, 0.45), 6))
		pc.add_child(l)
		assist_box.add_child(pc)
		assist_lbls[a] = l
	add_child(assist_box)
	telemetry = UITheme.label("", 15, UITheme.TEXT)
	telemetry.add_theme_font_override("font", UITheme.font())
	var tp := PanelContainer.new()
	tp.name = "TelemetryPanel"
	UITheme.place(tp, 0.0, 0.5, 20, -170, 520, 260)
	tp.add_child(telemetry)
	tp.visible = false
	add_child(tp)
	hint_lbl = UITheme.label("[`] Console   [F1/Tab] Garage   [F2] Debug   [M] Map   [P] Photo   [C] Camera   [R] Reset", 15, Color(1, 1, 1, 0.55))
	UITheme.place(hint_lbl, 0.5, 1.0, -450, -34, 900, 24)
	hint_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(hint_lbl)


func _process(delta: float) -> void:
	var c := Game.player
	if c == null or not is_instance_valid(c):
		return
	_shown_rpm = lerpf(_shown_rpm, c.rpm, 1.0 - exp(-18.0 * delta))
	cluster.queue_redraw()
	_info_timer -= delta
	if _info_timer <= 0.0:
		_info_timer = 0.25
		var lines := []
		if Game.settings.show_fps:
			lines.append("%d FPS  %.1f ms" % [Engine.get_frames_per_second(), 1000.0 / maxf(Engine.get_frames_per_second(), 1.0)])
		if Game.settings.get("show_coords", false):
			var p := c.global_position
			lines.append("X %.0f  Y %.0f  Z %.0f" % [p.x, p.y, p.z])
		if Game.sky != null:
			var h := float(Game.sky.time_of_day)
			lines.append("%02d:%02d  %s" % [int(h), int(fmod(h, 1.0) * 60.0), Game.sky.weather_name()])
		info_lbl.text = "\n".join(lines)
		if Game.world != null and Game.world.has_method("region_at"):
			road_lbl.text = Game.world.roads.road_name_at(c.global_position)
	var on := Color(1.0, 0.75, 0.2)
	(assist_lbls.TCS as Label).add_theme_color_override("font_color", on if c.tcs_active else (UITheme.TEXT if c.assist_tcs else Color(1, 1, 1, 0.25)))
	(assist_lbls.ABS as Label).add_theme_color_override("font_color", on if c.abs_active else (UITheme.TEXT if c.assist_abs else Color(1, 1, 1, 0.25)))
	(assist_lbls.STM as Label).add_theme_color_override("font_color", on if c.stm_active else (UITheme.TEXT if c.assist_stm else Color(1, 1, 1, 0.25)))
	(assist_lbls.AUTO as Label).text = "AUTO" if c.auto_gear else "MAN"
	var tp := get_node("TelemetryPanel") as PanelContainer
	tp.visible = bool(Game.settings.show_telemetry)
	if tp.visible:
		var t := "TELEMETRY  %s\n" % c.data.display_name
		t += "RPM %5d  gear %s  load %.2f\n" % [c.rpm, _gear_text(c), c.engine_load]
		t += "speed %.1f km/h  slip %.1f deg\n" % [c.kmh(), rad_to_deg(c.body_slip)]
		var names := ["FL", "FR", "RL", "RR"]
		for i in c.wheels.size():
			var w := c.wheels[i]
			t += "%s %-8s Fz %5.0f  sr %+.2f  sa %+5.1f  %s\n" % [names[i], w.surface.display_name if w.surface else "-", w.fz,
				w.slip_ratio, rad_to_deg(w.slip_angle), "AIR" if not w.contact else ""]
		t += "wet %.2f  grip x%.2f  air %.1fs" % [c.wetness, c.weather_grip, c.air_time]
		telemetry.text = t


func _gear_text(c: CarController) -> String:
	if c.gear < 0:
		return "R"
	if c.gear == 0:
		return "N"
	return str(c.gear)


func _draw_cluster() -> void:
	var c := Game.player
	if c == null or not is_instance_valid(c):
		return
	var center := Vector2(165, 165)
	var r := 140.0
	var a0 := deg_to_rad(135.0)
	var span := deg_to_rad(270.0)
	var max_rpm := c.data.max_rpm
	cluster.draw_circle(center, r + 14.0, Color(0.02, 0.03, 0.06, 0.62))
	cluster.draw_arc(center, r, a0, a0 + span, 64, Color(1, 1, 1, 0.13), 10.0, true)
	var red_from := c.data.redline_rpm / max_rpm
	cluster.draw_arc(center, r, a0 + span * red_from, a0 + span, 24, Color(1.0, 0.15, 0.2, 0.55), 10.0, true)
	var f := clampf(_shown_rpm / max_rpm, 0.0, 1.0)
	var col := UITheme.CYAN.lerp(UITheme.PINK, smoothstep(0.65, 0.95, f))
	cluster.draw_arc(center, r, a0, a0 + span * f, 64, col, 10.0, true)
	# tick marks every 1000 rpm
	var k := 0
	while k * 1000.0 <= max_rpm:
		var ang := a0 + span * (k * 1000.0 / max_rpm)
		var dir := Vector2(cos(ang), sin(ang))
		cluster.draw_line(center + dir * (r - 22.0), center + dir * (r - 12.0), Color(1, 1, 1, 0.7), 2.0, true)
		cluster.draw_string(UITheme.font(true), center + dir * (r - 38.0) - Vector2(6, -6), str(k), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 1, 1, 0.65))
		k += 1
	var na := a0 + span * f
	cluster.draw_line(center + Vector2(cos(na), sin(na)) * 30.0, center + Vector2(cos(na), sin(na)) * (r - 6.0), UITheme.SUN, 3.0, true)
	var spd := Game.speed_text(c.speed_abs)
	var font := UITheme.font(true)
	var ssize := font.get_string_size(spd, HORIZONTAL_ALIGNMENT_LEFT, -1, 78)
	cluster.draw_string(font, center + Vector2(-ssize.x * 0.5, 22), spd, HORIZONTAL_ALIGNMENT_LEFT, -1, 78, UITheme.TEXT)
	var unit := Game.speed_unit()
	var usize := font.get_string_size(unit, HORIZONTAL_ALIGNMENT_LEFT, -1, 18)
	cluster.draw_string(font, center + Vector2(-usize.x * 0.5, 50), unit, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, UITheme.DIM)
	var g := _gear_text(c)
	var gcol := UITheme.PINK if c.rpm > c.data.redline_rpm * 0.94 else UITheme.SUN
	cluster.draw_string(font, center + Vector2(-12, 108), g, HORIZONTAL_ALIGNMENT_LEFT, -1, 44, gcol)
	var surf := c.surface_name.to_upper()
	cluster.draw_string(UITheme.font(), center + Vector2(-60, -52), surf, HORIZONTAL_ALIGNMENT_CENTER, 120, 15, UITheme.DIM)
