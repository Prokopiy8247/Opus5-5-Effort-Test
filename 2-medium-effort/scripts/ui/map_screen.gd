extends Control
## Full-screen world map: region tint, water, roads by class, settlements/POIs, activities, player.
## Left click sets a waypoint (GPS route is computed over the road graph and shown on the minimap).

var map_tex: ImageTexture
var zoom: float = 1.0
var center: Vector2 = Vector2.ZERO
var _drag: bool = false
const WORLD_SPAN: float = 4400.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP


func _render_base() -> void:
	var w: WorldData = Game.world
	if w == null:
		return
	var res: int = 256
	var img := Image.create(res, res, false, Image.FORMAT_RGB8)
	for py in res:
		for px in res:
			var x: float = (px + 0.5) / res * WORLD_SPAN - WORLD_SPAN * 0.5
			var z: float = (py + 0.5) / res * WORLD_SPAN - WORLD_SPAN * 0.5
			var h: float = w.natural_height(x, z)
			var c: Color
			if h < 0.0:
				c = Color(0.08, 0.2, 0.35)
			else:
				c = w.terrain_color(x, z, h, 0.0).darkened(0.35)
				if int(h) % 25 < 2:
					c = c.darkened(0.15)
			img.set_pixel(px, py, c)
	map_tex = ImageTexture.create_from_image(img)


func _to_screen(p: Vector2) -> Vector2:
	var side: float = minf(size.x, size.y) * 0.92 * zoom
	var origin: Vector2 = size * 0.5 - (center / WORLD_SPAN) * side
	return origin + (p / WORLD_SPAN) * side


func _to_world(sp: Vector2) -> Vector2:
	var side: float = minf(size.x, size.y) * 0.92 * zoom
	var origin: Vector2 = size * 0.5 - (center / WORLD_SPAN) * side
	return (sp - origin) / side * WORLD_SPAN


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom = clampf(zoom * 1.15, 1.0, 6.0)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom = clampf(zoom / 1.15, 1.0, 6.0)
		elif event.button_index == MOUSE_BUTTON_LEFT:
			var wp: Vector2 = _to_world(event.position)
			set_waypoint(wp)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			_drag = true
	elif event is InputEventMouseButton and not event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		_drag = false
	elif event is InputEventMouseMotion and _drag:
		var side: float = minf(size.x, size.y) * 0.92 * zoom
		center -= event.relative / side * WORLD_SPAN
	queue_redraw()


func set_waypoint(wp: Vector2) -> void:
	var mm: Node = Game.hud.minimap if Game.hud else null
	if mm == null:
		return
	mm.waypoint = wp
	mm.route = GpsRouter.route(Game.world, (Game.player as Node3D).global_position, Vector3(wp.x, 0, wp.y))
	Game.toast("Waypoint set", "%.1f km by road" % (GpsRouter.last_length / 1000.0), Color(1.0, 0.36, 0.62))


func _process(_d: float) -> void:
	if visible:
		queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.03, 0.05, 0.94))
	if map_tex == null:
		_render_base()
	var a: Vector2 = _to_screen(Vector2(-WORLD_SPAN * 0.5, -WORLD_SPAN * 0.5))
	var b: Vector2 = _to_screen(Vector2(WORLD_SPAN * 0.5, WORLD_SPAN * 0.5))
	draw_texture_rect(map_tex, Rect2(a, b - a), false)
	var w: WorldData = Game.world
	for r in w.roads:
		var pts: PackedVector3Array = r.pts
		var line := PackedVector2Array()
		for i in range(0, pts.size(), 4):
			line.append(_to_screen(Vector2(pts[i].x, pts[i].z)))
		line.append(_to_screen(Vector2(pts[pts.size() - 1].x, pts[pts.size() - 1].z)))
		var col := Color(0.95, 0.95, 0.95) if not r.loop else Color(1.0, 0.85, 0.3)
		if r.surface >= 2:
			col = Color(0.85, 0.65, 0.45)
		draw_polyline(line, col, 3.0 if r.cls != "highway" else 4.5, true)
	var f: Font = ThemeDB.fallback_font
	for i in 4:
		var rc: Vector2 = [Vector2(-900, 300), Vector2(-500, -1500), Vector2(1300, -500), Vector2(-700, 1700)][i]
		draw_string(f, _to_screen(rc), WorldData.REGION_NAMES[i].to_upper(), HORIZONTAL_ALIGNMENT_CENTER, 300, 20, Color(1, 1, 1, 0.75))
	for nm in RoadLayout.POIS:
		var p: Vector2 = RoadLayout.POIS[nm]
		var sp: Vector2 = _to_screen(p)
		draw_circle(sp, 4, Color(1, 1, 1, 0.8))
		draw_string(f, sp + Vector2(6, -4), nm.capitalize(), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 1, 1, 0.8))
	if Game.activities and Game.activities.has_method("map_icons"):
		for ic in Game.activities.map_icons():
			var sp2: Vector2 = _to_screen(ic[0])
			draw_circle(sp2, 9, ic[1])
			draw_string(f, sp2 + Vector2(-5, 5), ic[2], HORIZONTAL_ALIGNMENT_CENTER, 10, 12, Color.WHITE)
	var mm: Node = Game.hud.minimap if Game.hud else null
	if mm and mm.route.size() > 1:
		var rl := PackedVector2Array()
		for q in mm.route:
			rl.append(_to_screen(q))
		draw_polyline(rl, Color(1.0, 0.36, 0.62), 4.0, true)
	if mm and mm.waypoint != null:
		draw_circle(_to_screen(mm.waypoint), 8, Color(1.0, 0.36, 0.62))
	var car: Node3D = Game.player as Node3D
	if car:
		var cp: Vector2 = _to_screen(Vector2(car.global_position.x, car.global_position.z))
		var fwd: Vector3 = -car.global_transform.basis.z
		var d := Vector2(fwd.x, fwd.z).normalized()
		var n := Vector2(-d.y, d.x)
		draw_colored_polygon(PackedVector2Array([cp + d * 14, cp - d * 8 + n * 8, cp - d * 8 - n * 8]), Color(1.0, 0.62, 0.1))
	draw_string(f, Vector2(30, 40), "MAP  -  wheel zoom · right-drag pan · left click: set GPS waypoint · M close", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(1, 1, 1, 0.8))
	draw_string(f, Vector2(30, 66), "Road network %.1f km   ·   Grand Festival Loop %.1f km (yellow)" % [w.total_length / 1000.0, w.loop_length / 1000.0], HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1, 1, 1, 0.65))
