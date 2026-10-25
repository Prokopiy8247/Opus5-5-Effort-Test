extends Control
## Full map (M): shaded relief, roads, places, activities, player. Click to set a GPS waypoint,
## right click to clear, wheel to zoom, drag to pan.

var main: Node
var tex: ImageTexture
var open := false
var zoom := 1.0
var pan := Vector2.ZERO
var _drag := false
var legend: Label


func init_ui(m: Node) -> void:
	main = m
	UIStyle.place(self, Control.PRESET_FULL_RECT, 0, 0, 0, 0)
	mouse_filter = Control.MOUSE_FILTER_STOP
	tex = ImageTexture.create_from_image(_render_relief())
	legend = UIStyle.label("MAP  —  click: set waypoint   right click: clear   wheel: zoom   drag: pan   M: close", 16, UIStyle.TEXT)
	UIStyle.place(legend, Control.PRESET_CENTER_BOTTOM, -450, -40, 450, -12)
	legend.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(legend)
	visible = false


func _render_relief() -> Image:
	var d: WorldData = Game.world.data
	var S := 1024
	var img := Image.create_empty(S, S, false, Image.FORMAT_RGB8)
	var step := (d.n - 1) / S
	for py in S:
		for px in S:
			var k := py * step * d.n + px * step
			var h := d.heights[k]
			var hx := d.heights[mini(k + 2, d.heights.size() - 1)] - h
			var hz := d.heights[mini(k + 2 * d.n, d.heights.size() - 1)] - h
			var shade := clampf(0.78 - (hx + hz) * 0.18, 0.35, 1.1)
			var c: Color
			if h < 0.3:
				c = Color(0.12, 0.3, 0.45)
			else:
				var w := d.biome_img.get_pixel(px * d.biome_img.get_width() / S, py * d.biome_img.get_height() / S)
				c = Color(0.36, 0.5, 0.26) * w.r + Color(0.33, 0.42, 0.3) * w.g + Color(0.7, 0.5, 0.32) * w.b + Color(0.42, 0.52, 0.32) * w.a
				c = c.lerp(Color(0.92, 0.93, 0.95), clampf((h - 300.0) / 120.0, 0.0, 0.8))
			img.set_pixel(px, py, c * shade)
	return img


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("map"):
		toggle()
		get_viewport().set_input_as_handled()


func toggle() -> void:
	open = not open
	visible = open
	if main.player:
		main.player.controls_enabled = not open
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _map_rect() -> Rect2:
	var s := minf(size.x, size.y) * 0.92 * zoom
	return Rect2(size * 0.5 - Vector2(s, s) * 0.5 + pan, Vector2(s, s))


func world_to_map(p: Vector2) -> Vector2:
	var r := _map_rect()
	var d: WorldData = Game.world.data
	var span := (d.n - 1) * d.cell
	return r.position + (p - Vector2(d.origin, d.origin)) / span * r.size.x


func map_to_world(m: Vector2) -> Vector2:
	var r := _map_rect()
	var d: WorldData = Game.world.data
	var span := (d.n - 1) * d.cell
	return Vector2(d.origin, d.origin) + (m - r.position) / r.size.x * span


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom = minf(zoom * 1.15, 6.0)
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom = maxf(zoom / 1.15, 0.6)
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_drag = false
			elif not _drag:
				var w := map_to_world(mb.position)
				main.set_waypoint(Vector3(w.x, 0, w.y))
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			main.clear_waypoint()
		queue_redraw()
	elif event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		pan += (event as InputEventMouseMotion).relative
		_drag = true
		queue_redraw()


func _process(_d: float) -> void:
	if open:
		queue_redraw()


func _draw() -> void:
	if not open:
		return
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.03, 0.05, 0.92))
	var r := _map_rect()
	draw_texture_rect(tex, r, false)
	var d: WorldData = Game.world.data
	for road in d.roads:
		var pts := PackedVector2Array()
		for i in range(0, road.pts.size(), 4):
			pts.append(world_to_map(Vector2(road.pts[i].x, road.pts[i].z)))
		var col := Color(0.95, 0.95, 0.95, 0.9)
		var w := 2.0
		match road.cls:
			"highway":
				col = Color(1.0, 0.8, 0.3)
				w = 3.5
			"regional":
				w = 2.6
			"dirt", "gravel", "sand":
				col = Color(0.85, 0.65, 0.4, 0.9)
				w = 1.6
		draw_polyline(pts, Color(0, 0, 0, 0.5), w + 2.0)
		draw_polyline(pts, col, w)
	var route: PackedVector2Array = main.route_2d
	if route.size() > 1:
		var rp := PackedVector2Array()
		for q in route:
			rp.append(world_to_map(q))
		draw_polyline(rp, Color(0.3, 0.9, 1.0), 4.0)
	var font := get_theme_default_font()
	for p in d.places:
		var mp := world_to_map(Vector2(p.pos[0], p.pos[1]))
		draw_circle(mp, 5.0, Color(1, 1, 1))
		draw_string(font, mp + Vector2(8, 5), p.name, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(1, 1, 1, 0.95))
	if Game.world.activities:
		for mk in Game.world.activities.minimap_markers():
			draw_circle(world_to_map(mk.pos), 4.5, mk.color)
	if main.waypoint != Vector3.INF:
		var wp := world_to_map(Vector2(main.waypoint.x, main.waypoint.z))
		draw_circle(wp, 9.0, Color(0.3, 0.9, 1.0))
		draw_circle(wp, 4.0, Color.WHITE)
	if main.player:
		var pp := world_to_map(Vector2(main.player.global_position.x, main.player.global_position.z))
		var f: Vector3 = -main.player.global_transform.basis.z
		var dir := Vector2(f.x, f.z).normalized()
		var side := Vector2(-dir.y, dir.x)
		draw_colored_polygon(PackedVector2Array([pp + dir * 14.0, pp - dir * 8.0 + side * 8.0, pp - dir * 4.0, pp - dir * 8.0 - side * 8.0]), UIStyle.ACCENT)
	# region labels
	var regions := [["MEADOWMERE VALLEY", Vector2(500, 700)], ["GRANITE CROWN", Vector2(-1350, -1400)], ["OCHRE MESA", Vector2(-1250, 1100)], ["SALTCLIFF COAST", Vector2(1150, -700)]]
	for rg in regions:
		draw_string(font, world_to_map(rg[1]), rg[0], HORIZONTAL_ALIGNMENT_CENTER, 300, 22, Color(1, 1, 1, 0.55))
