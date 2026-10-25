extends Control
## Full map (M): island map with regions, roads, places, activities, player and GPS route.
## Click to set a waypoint, right-click to clear, mouse wheel to zoom, drag to pan.

var map_tex: Texture2D
var zoom := 1.0
var pan := Vector2.ZERO
var _drag := false
var legend: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	legend = UITheme.label("MAP   ·   click: set waypoint   ·   right-click: clear   ·   wheel: zoom   ·   M / Esc: close", 17, UITheme.TEXT)
	UITheme.place(legend, 0.5, 1.0, -480, -44, 960, 30)
	legend.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(legend)


func toggle() -> void:
	visible = not visible
	Game.set_ui_focus("map", visible)
	if visible and Game.world != null:
		map_tex = Game.world.get("map_texture")
		zoom = 1.0
		pan = Vector2.ZERO
	queue_redraw()


func _map_rect() -> Rect2:
	var s := minf(size.x, size.y) * 0.9 * zoom
	var c := size * 0.5 + pan
	return Rect2(c - Vector2(s, s) * 0.5, Vector2(s, s))


func _w2s(p: Vector3) -> Vector2:
	var wd: WorldData = Game.world.wd
	var r := _map_rect()
	return r.position + Vector2((p.x + wd.half) / (wd.half * 2.0), (p.z + wd.half) / (wd.half * 2.0)) * r.size


func _s2w(s: Vector2) -> Vector3:
	var wd: WorldData = Game.world.wd
	var r := _map_rect()
	var uv := (s - r.position) / r.size
	return Vector3(uv.x * wd.half * 2.0 - wd.half, 0, uv.y * wd.half * 2.0 - wd.half)


func _gui_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			var nav: Node = Game.main.get("nav")
			if nav != null:
				nav.set_waypoint(_s2w(mb.position))
			_drag = false
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_RIGHT:
			var nav2: Node = Game.main.get("nav")
			if nav2 != null:
				nav2.clear_waypoint()
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom = minf(zoom * 1.15, 4.0)
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom = maxf(zoom / 1.15, 0.8)
		elif mb.button_index == MOUSE_BUTTON_MIDDLE:
			_drag = mb.pressed
		queue_redraw()
	elif event is InputEventMouseMotion and _drag:
		pan += (event as InputEventMouseMotion).relative
		queue_redraw()


func _process(_d: float) -> void:
	if visible:
		queue_redraw()


func _draw() -> void:
	if not visible or Game.world == null:
		return
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.03, 0.06, 0.82))
	var r := _map_rect()
	if map_tex != null:
		draw_texture_rect(map_tex, r, false)
	var wd: WorldData = Game.world.wd
	var f := UITheme.font(true)
	# region names
	var reg_pos := [Vector3(450, 0, 600), Vector3(-1250, 0, -1300), Vector3(-1250, 0, 1050), Vector3(1350, 0, -500)]
	for i in wd.regions.size():
		var sp := _w2s(reg_pos[i])
		var nm := String(wd.regions[i].name).to_upper()
		var ts := f.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 22)
		draw_string(f, sp - ts * 0.5 + Vector2(2, 2), nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(0, 0, 0, 0.6))
		draw_string(f, sp - ts * 0.5, nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(1, 1, 1, 0.92))
	# places
	for p: Dictionary in wd.pois:
		var sp := _w2s(p.pos)
		draw_circle(sp, 5.0, UITheme.CYAN)
		draw_string(UITheme.font(), sp + Vector2(8, 5), String(p.name), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 1, 1, 0.85))
	# activities
	if Game.activities != null and Game.activities.has_method("markers"):
		for m: Dictionary in Game.activities.markers():
			var sp := _w2s(m.pos)
			draw_circle(sp, 7.0, m.color)
			draw_circle(sp, 3.0, Color(0, 0, 0, 0.7))
	# route
	var nav: Node = Game.main.get("nav")
	if nav != null:
		var pts: PackedVector3Array = nav.route_points()
		if pts.size() > 1:
			var line := PackedVector2Array()
			for i in range(0, pts.size(), 4):
				line.append(_w2s(pts[i]))
			draw_polyline(line, UITheme.PINK, 4.0, true)
		if nav.waypoint() != Vector3.INF:
			var wsp := _w2s(nav.waypoint())
			draw_circle(wsp, 10.0, UITheme.PINK)
			draw_circle(wsp, 4.0, Color.WHITE)
	# player
	if Game.player != null and is_instance_valid(Game.player):
		var pp := _w2s(Game.player.global_position)
		var fwd := -Game.player.global_transform.basis.z
		var a := atan2(fwd.x, -fwd.z)
		var tri := PackedVector2Array([Vector2(0, -16), Vector2(11, 12), Vector2(0, 6), Vector2(-11, 12)])
		for i in tri.size():
			tri[i] = pp + tri[i].rotated(a)
		draw_colored_polygon(tri, UITheme.SUN)
	draw_string(f, Vector2(40, 60), "VALORIA", HORIZONTAL_ALIGNMENT_LEFT, -1, 40, UITheme.PINK)
	draw_string(UITheme.font(), Vector2(42, 90), "%.1f km of road  ·  %d places  ·  %d activities" % [
		float(wd.stats.get("road_km", 0.0)), wd.pois.size(), wd.activities.size()], HORIZONTAL_ALIGNMENT_LEFT, -1, 18, UITheme.DIM)
