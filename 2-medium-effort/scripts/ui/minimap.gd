extends Control
## Heading-up circular minimap: roads (by class), water hint, activities, waypoint + GPS route, player arrow.

const RADIUS_PX: float = 120.0
var range_m: float = 420.0
var road_lines: Array = []  # [PackedVector2Array, Color, width]
var icons: Array = []  # [Vector2 world xz, Color, String letter]
var route: PackedVector2Array = PackedVector2Array()
var waypoint: Variant = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_lines()


func _build_lines() -> void:
	road_lines.clear()
	var w: WorldData = Game.world
	if w == null:
		return
	for r in w.roads:
		var pts: PackedVector3Array = r.pts
		var line := PackedVector2Array()
		for i in range(0, pts.size(), 3):
			line.append(Vector2(pts[i].x, pts[i].z))
		line.append(Vector2(pts[pts.size() - 1].x, pts[pts.size() - 1].z))
		var col := Color(0.92, 0.92, 0.95)
		var wd: float = 3.0
		if r.cls == "highway":
			col = Color(1.0, 0.8, 0.35)
			wd = 4.0
		elif r.surface >= 2:
			col = Color(0.8, 0.62, 0.42)
			wd = 2.0
		road_lines.append([line, col, wd])


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var _pf: int = Time.get_ticks_usec()
	_inner_draw()
	Game.prof_add("minimap_draw", _pf)


func _inner_draw() -> void:
	var car: Node3D = Game.player as Node3D
	if car == null or not is_instance_valid(car):
		return
	if size.y < 200.0:
		return
	if road_lines.is_empty():
		_build_lines()
	var s: float = size.y / 1080.0
	var r: float = RADIUS_PX * s
	var c := Vector2(30 * s + r, size.y - 60 * s - r)
	draw_circle(c, r + 6 * s, Color(0.04, 0.05, 0.08, 0.7))
	draw_circle(c, r, Color(0.2, 0.28, 0.2, 0.55))
	var p := Vector2(car.global_position.x, car.global_position.z)
	var fwd: Vector3 = -car.global_transform.basis.z
	var heading: float = atan2(fwd.x, -fwd.z)  # 0 = north
	var k: float = r / range_m
	var rot := Transform2D(-heading, Vector2.ZERO)
	var cull: float = range_m * 1.5
	for rl in road_lines:
		var line: PackedVector2Array = rl[0]
		var prev: Vector2 = Vector2.INF
		var pv_in: bool = false
		for q in line:
			var d: Vector2 = q - p
			var inside: bool = absf(d.x) < cull and absf(d.y) < cull
			var sp: Vector2 = c + rot * d * k
			if prev != Vector2.INF and (inside or pv_in):
				var a: Vector2 = _clip(c, prev, r)
				var b: Vector2 = _clip(c, sp, r)
				if a != Vector2.INF and b != Vector2.INF:
					draw_line(a, b, rl[1], rl[2] * s, true)
			prev = sp
			pv_in = inside
	# GPS route
	if route.size() > 1:
		var prev2: Vector2 = Vector2.INF
		for q in route:
			var sp: Vector2 = c + rot * (q - p) * k
			if prev2 != Vector2.INF:
				var a: Vector2 = _clip(c, prev2, r)
				var b: Vector2 = _clip(c, sp, r)
				if a != Vector2.INF and b != Vector2.INF:
					draw_line(a, b, Color(1.0, 0.36, 0.62), 5.0 * s, true)
			prev2 = sp
	for ic in icons:
		var d2: Vector2 = ic[0] - p
		var sp2: Vector2 = c + rot * d2 * k
		if sp2.distance_to(c) > r - 8 * s:
			sp2 = c + (sp2 - c).normalized() * (r - 8 * s)
		draw_circle(sp2, 8 * s, ic[1])
		draw_string(ThemeDB.fallback_font, sp2 + Vector2(-6, 5) * s, ic[2], HORIZONTAL_ALIGNMENT_CENTER, 12 * s, int(12 * s), Color.WHITE)
	if waypoint != null:
		var wp: Vector2 = waypoint
		var sp3: Vector2 = c + rot * (wp - p) * k
		if sp3.distance_to(c) > r - 8 * s:
			sp3 = c + (sp3 - c).normalized() * (r - 8 * s)
		draw_circle(sp3, 9 * s, Color(1.0, 0.36, 0.62))
	# north marker
	var n_dir: Vector2 = rot * Vector2(0, -1)
	draw_string(ThemeDB.fallback_font, c + n_dir * (r - 14 * s) + Vector2(-6, 6) * s, "N", HORIZONTAL_ALIGNMENT_CENTER, 12 * s, int(15 * s), Color(1, 1, 1, 0.9))
	# player arrow
	var tri := PackedVector2Array([c + Vector2(0, -12) * s, c + Vector2(8, 9) * s, c + Vector2(0, 4) * s, c + Vector2(-8, 9) * s])
	draw_colored_polygon(tri, Color(1.0, 0.62, 0.1))


func _clip(c: Vector2, p: Vector2, r: float) -> Vector2:
	var d: Vector2 = p - c
	if d.length() <= r:
		return p
	return c + d.normalized() * r if d.length() < r * 1.02 else Vector2.INF
