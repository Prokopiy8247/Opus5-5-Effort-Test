extends Control
## Heading-up minimap: map texture via canvas shader plus drawn overlays (player arrow,
## activities, GPS route, waypoint and nearby traffic).

const SHADER := preload("res://assets/shaders/minimap.gdshader")

var radius_m := 300.0
var map_rect: TextureRect
var mat: ShaderMaterial
var overlay: Control
var _heading := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	map_rect = TextureRect.new()
	map_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	map_rect.stretch_mode = TextureRect.STRETCH_SCALE
	map_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	map_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mat = ShaderMaterial.new()
	mat.shader = SHADER
	map_rect.material = mat
	add_child(map_rect)
	overlay = Control.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.draw.connect(_draw_overlay)
	add_child(overlay)


func set_map(tex: Texture2D) -> void:
	map_rect.texture = tex
	mat.set_shader_parameter("map_tex", tex)


func _process(_delta: float) -> void:
	var c := Game.player
	if c == null or not is_instance_valid(c) or Game.world == null or not Game.world.has_method("region_at"):
		return
	var wd: WorldData = Game.world.wd
	var p := c.global_position
	var fwd := -c.global_transform.basis.z
	if Game.camera != null and Game.camera.mode <= CarCamera.Mode.CHASE_FAR:
		fwd = -Game.camera.global_transform.basis.z
	_heading = atan2(fwd.x, -fwd.z)
	var spd := c.speed_abs
	radius_m = lerpf(radius_m, clampf(220.0 + spd * 4.0, 220.0, 520.0), 0.02)
	mat.set_shader_parameter("center_uv", Vector2((p.x + wd.half) / (wd.half * 2.0), (p.z + wd.half) / (wd.half * 2.0)))
	mat.set_shader_parameter("rotation", _heading if Game.settings.minimap_rotate else 0.0)
	mat.set_shader_parameter("radius_uv", radius_m / (wd.half * 2.0))
	overlay.queue_redraw()


func _to_screen(w: Vector3, p: Vector3) -> Vector2:
	var rel := Vector2(w.x - p.x, w.z - p.z) / radius_m
	var a := -_heading if Game.settings.minimap_rotate else 0.0
	rel = rel.rotated(a)
	var half := size * 0.5
	return half + rel * half


func _draw_overlay() -> void:
	var c := Game.player
	if c == null or not is_instance_valid(c):
		return
	var p := c.global_position
	var half := size * 0.5
	# GPS route
	var nav: Node = Game.main.get("nav") if Game.main != null else null
	if nav != null and nav.has_method("route_points"):
		var pts: PackedVector3Array = nav.route_points()
		var line := PackedVector2Array()
		for q in pts:
			var sp := _to_screen(q, p)
			if sp.distance_to(half) < half.x * 1.25:
				line.append(sp)
		if line.size() > 1:
			overlay.draw_polyline(line, Color(1.0, 0.25, 0.55, 0.95), 5.0, true)
		if nav.has_method("waypoint") and nav.waypoint() != Vector3.INF:
			var wsp := _to_screen(nav.waypoint(), p)
			var dir := wsp - half
			if dir.length() > half.x * 0.9:
				wsp = half + dir.normalized() * half.x * 0.88
			overlay.draw_circle(wsp, 8.0, UITheme.PINK)
	# activities
	if Game.activities != null and Game.activities.has_method("markers"):
		for m: Dictionary in Game.activities.markers():
			var sp := _to_screen(m.pos, p)
			if sp.distance_to(half) < half.x * 0.92:
				overlay.draw_circle(sp, 7.0, m.color)
				overlay.draw_circle(sp, 3.0, Color(0, 0, 0, 0.6))
	# traffic
	if Game.traffic != null and Game.traffic.has_method("positions"):
		for q: Vector3 in Game.traffic.positions():
			var sp := _to_screen(q, p)
			if sp.distance_to(half) < half.x * 0.92:
				overlay.draw_circle(sp, 3.0, Color(0.9, 0.9, 0.95, 0.8))
	# player arrow
	var a := 0.0 if Game.settings.minimap_rotate else _heading
	var tri := PackedVector2Array([Vector2(0, -13), Vector2(9, 10), Vector2(0, 5), Vector2(-9, 10)])
	for i in tri.size():
		tri[i] = half + tri[i].rotated(a)
	overlay.draw_colored_polygon(tri, UITheme.SUN)
	overlay.draw_polyline(PackedVector2Array([tri[0], tri[1], tri[2], tri[3], tri[0]]), Color(0, 0, 0, 0.7), 1.5, true)
	# north marker
	var north := _to_screen(p + Vector3(0, 0, -radius_m * 0.86), p)
	overlay.draw_string(UITheme.font(true), north - Vector2(6, -6), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, UITheme.CYAN)
