class_name Minimap
extends Control
## Rotating minimap (heading-up) drawn from the road polylines; also a full map mode.

var world: WorldGen
var player: Car
var events: EventManager
var full := false
var zoom := 0.18          # px per metre in minimap mode
var waypoint := Vector2.INF
var _region_tex: ImageTexture

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func build_region_texture() -> void:
	var n := 128
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var cols := [Color(0.3, 0.45, 0.2), Color(0.42, 0.45, 0.42), Color(0.7, 0.5, 0.3), Color(0.35, 0.5, 0.35)]
	for y in n:
		for x in n:
			var wx := (x + 0.5) / n * 4000.0 - 2000.0
			var wz := (y + 0.5) / n * 4000.0 - 2000.0
			var h := world.water_carve(wx, wz, world.land_height(wx, wz))
			var c: Color = cols[world.region_at(wx, wz)]
			if h < 0.0: c = Color(0.15, 0.3, 0.5)
			c = c.darkened(0.15 - clampf(h / 600.0, 0.0, 0.3))
			c.a = 0.85
			img.set_pixel(x, y, c)
	_region_tex = ImageTexture.create_from_image(img)

func _process(_dt: float) -> void:
	queue_redraw()

func _to_screen(p: Vector2, centre: Vector2, origin: Vector2, rot: float, scale_: float) -> Vector2:
	return centre + ((p - origin) * scale_).rotated(rot)

func _draw() -> void:
	if world == null or player == null: return
	var pp := Vector2(player.global_position.x, player.global_position.z)
	var f := -player.global_basis.z
	var heading := atan2(f.x, -f.z)
	var rect := get_rect()
	var centre := rect.size * 0.5
	var sc := zoom
	var rot := -heading
	if full:
		sc = minf(rect.size.x, rect.size.y) / 4100.0
		rot = 0.0
		draw_rect(Rect2(Vector2.ZERO, rect.size), Color(0.05, 0.07, 0.1, 0.85))
		var origin := Vector2.ZERO
		var tl := _to_screen(Vector2(-2000, -2000), centre, origin, 0.0, sc)
		if _region_tex: draw_texture_rect(_region_tex, Rect2(tl, Vector2(4000, 4000) * sc), false)
		_draw_roads(centre, origin, 0.0, sc, 3.0)
		_draw_events(centre, origin, 0.0, sc)
		for i in WorldGen.REGION_NAMES.size():
			var rp := [Vector2(-1000, -1000), Vector2(1000, -1000), Vector2(1000, 1000), Vector2(-1000, 1000)][i] as Vector2
			draw_string(get_theme_default_font(), _to_screen(rp, centre, origin, 0, sc) - Vector2(60, 0), WorldGen.REGION_NAMES[i].to_upper(), HORIZONTAL_ALIGNMENT_CENTER, 140, 16, Color(1, 1, 1, 0.8))
		_draw_player(_to_screen(pp, centre, origin, 0.0, sc), heading)
		if waypoint != Vector2.INF:
			draw_circle(_to_screen(waypoint, centre, origin, 0.0, sc), 7.0, Color(1, 0.2, 0.6))
		draw_string(get_theme_default_font(), Vector2(20, rect.size.y - 20), "MAP  —  click to set waypoint, M to close", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1, 1, 1, 0.8))
		return
	# circular minimap
	var r := minf(rect.size.x, rect.size.y) * 0.5
	draw_circle(centre, r, Color(0.05, 0.08, 0.1, 0.72))
	if _region_tex:
		pass
	_draw_roads(centre, pp, rot, sc, 3.5, r)
	_draw_events(centre, pp, rot, sc, r)
	if waypoint != Vector2.INF:
		var wp := _to_screen(waypoint, centre, pp, rot, sc)
		if (wp - centre).length() > r - 8.0: wp = centre + (wp - centre).normalized() * (r - 8.0)
		draw_circle(wp, 5.0, Color(1, 0.2, 0.6))
	_draw_player(centre, 0.0)
	draw_arc(centre, r, 0, TAU, 64, Color(1, 1, 1, 0.5), 2.0, true)
	var north := centre + Vector2(0, -r + 10).rotated(rot)
	draw_string(get_theme_default_font(), north - Vector2(5, -5), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 0.5, 0.4))

func _draw_roads(centre: Vector2, origin: Vector2, rot: float, sc: float, w: float, clip: float = 1e9) -> void:
	for road in world.roads:
		var pts: PackedVector3Array = road.pts
		var col := Color(0.92, 0.92, 0.95) if road.surface <= 1 else Color(0.85, 0.7, 0.45)
		if road.cls == "highway": col = Color(1.0, 0.85, 0.4)
		var step := 3 if not full else 6
		var prev := Vector2.INF
		var line := PackedVector2Array()
		for i in range(0, pts.size() + (step if road.closed else 0), step):
			var q := pts[i % pts.size()]
			var s := _to_screen(Vector2(q.x, q.z), centre, origin, rot, sc)
			var inside := (s - centre).length() < clip
			if inside: line.append(s)
			elif line.size() > 1:
				draw_polyline(line, col, w, true); line = PackedVector2Array()
			else: line = PackedVector2Array()
		if line.size() > 1: draw_polyline(line, col, w, true)

func _draw_events(centre: Vector2, origin: Vector2, rot: float, sc: float, clip: float = 1e9) -> void:
	if events == null: return
	for e in events.events:
		var p := world.road_point(e.road, e.a)
		var s := _to_screen(Vector2(p.x, p.z), centre, origin, rot, sc)
		if (s - centre).length() > clip - 6.0: continue
		draw_circle(s, 5.0 if full else 4.0, events.colors[e.type])

func _draw_player(at: Vector2, heading: float) -> void:
	var pts := PackedVector2Array([Vector2(0, -10), Vector2(7, 8), Vector2(0, 4), Vector2(-7, 8)])
	for i in pts.size(): pts[i] = at + pts[i].rotated(heading)
	draw_colored_polygon(pts, Color(1.0, 0.35, 0.2))

func _gui_input(e: InputEvent) -> void:
	if full and e is InputEventMouseButton and (e as InputEventMouseButton).pressed:
		var sc := minf(size.x, size.y) / 4100.0
		var p := ((e as InputEventMouseButton).position - size * 0.5) / sc
		waypoint = p
		Game.toast("Waypoint set")
