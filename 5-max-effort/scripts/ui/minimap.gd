extends Node
## Heading-up minimap in the HUD's bottom-left slot: baked map image (roads, water, terrain
## shading) rotated around the player, GPS route, waypoint, activity/board/landmark icons, a north
## marker and the player arrow. Zooms out with speed.

var tex: Texture2D
var half: float = 2000.0
var _clip: Control
var _view: Control
var _frame: Control
var _zoom_m: float = 240.0
var _markers: Array = []
var _marker_t: float = 0.0


class Layer:
	extends Control
	var owner_map: Node
	var which: int = 0

	func _draw() -> void:
		owner_map.call("_draw_layer", self, which)


func _ready() -> void:
	name = "Minimap"
	tex = load("res://data/world/map.png")
	call_deferred("_attach")


func _attach() -> void:
	if Game.hud == null:
		return
	if Game.world != null and "data" in Game.world:
		half = (Game.world.get("data") as WorldData).half
	var slot: Control = Game.hud.get("minimap_slot")
	_clip = Layer.new()
	_clip.owner_map = self
	_clip.which = 0
	_clip.set_anchors_preset(Control.PRESET_FULL_RECT)
	_clip.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(_clip)
	_view = Layer.new()
	_view.owner_map = self
	_view.which = 1
	_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_clip.add_child(_view)
	_frame = Layer.new()
	_frame.owner_map = self
	_frame.which = 2
	_frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(_frame)


func _process(delta: float) -> void:
	if _view == null:
		return
	var car := Game.player_car
	if car != null and is_instance_valid(car):
		var target := lerpf(220.0, 420.0, clampf(absf(car.speed_kmh) / 220.0, 0.0, 1.0))
		_zoom_m = lerpf(_zoom_m, target, 1.0 - exp(-delta * 1.5))
	_marker_t -= delta
	if _marker_t <= 0.0:
		_marker_t = 1.0
		_markers = MapIcons.markers()
	_view.queue_redraw()
	_frame.queue_redraw()


func _basis() -> Array:
	## [player xz, forward xz, right xz]
	var car := Game.player_car
	var cam := get_viewport().get_camera_3d()
	var p := Vector3.ZERO
	var f := Vector2(0, -1)
	if car != null and is_instance_valid(car):
		p = car.global_position
	if cam != null:
		var cf := -cam.global_transform.basis.z
		if Vector2(cf.x, cf.z).length() > 0.1:
			f = Vector2(cf.x, cf.z).normalized()
	var r := Vector2(-f.y, f.x)
	return [Vector2(p.x, p.z), f, r]


func _draw_layer(ci: Control, which: int) -> void:
	var sz := ci.size
	var c := sz * 0.5
	var radius := minf(sz.x, sz.y) * 0.5
	match which:
		0:
			ci.draw_circle(c, radius, Color(0.05, 0.07, 0.09, 0.9))
		1:
			_draw_map(ci, c, radius)
		2:
			_draw_frame(ci, c, radius)


func _project(w: Vector3, b: Array, c: Vector2, k: float) -> Vector2:
	var d := Vector2(w.x, w.z) - (b[0] as Vector2)
	return c + Vector2(d.dot(b[2]), -d.dot(b[1])) * k


func _draw_map(ci: Control, c: Vector2, radius: float) -> void:
	if tex == null:
		return
	var b := _basis()
	var k := radius / _zoom_m
	var s := 2.0 * half / MapIcons.MAP_PX
	var f: Vector2 = b[1]
	var r: Vector2 = b[2]
	var p: Vector2 = b[0]
	var xa := Vector2(r.x, -f.x) * k * s
	var ya := Vector2(r.y, -f.y) * k * s
	var o := c - Vector2((p.x + half) * r.x + (p.y + half) * r.y, -((p.x + half) * f.x + (p.y + half) * f.y)) * k
	ci.draw_set_transform_matrix(Transform2D(xa, ya, o))
	var ppx := Vector2((p.x + half) / s, (p.y + half) / s)
	var span := _zoom_m * 1.6 / s
	var src := Rect2(ppx - Vector2(span, span), Vector2(span, span) * 2.0)
	ci.draw_texture_rect_region(tex, src, src, Color(1, 1, 1, 0.92))
	ci.draw_set_transform_matrix(Transform2D.IDENTITY)
	# GPS route
	var nav: Node = Game.world.get_node_or_null("Navigator") if Game.world != null else null
	if nav != null:
		var rp: PackedVector3Array = nav.get("route_points")
		if rp.size() > 1:
			var pts := PackedVector2Array()
			for q in rp:
				var sp := _project(q, b, c, k)
				pts.append(sp)
				if sp.distance_to(c) > radius * 3.0:
					break
			if pts.size() > 1:
				ci.draw_polyline(pts, Color(0, 0, 0, 0.5), 7.0, true)
				ci.draw_polyline(pts, MapIcons.COLORS["waypoint"], 4.0, true)
		var tgt: Vector3 = nav.get("target")
		if tgt != Vector3.INF:
			var tp := _project(tgt, b, c, k)
			var dv := tp - c
			if dv.length() > radius - 12.0:
				tp = c + dv.normalized() * (radius - 12.0)
			MapIcons.draw_icon(ci, "trial", tp, 18.0)
	for m in _markers:
		var sp := _project(m["pos"], b, c, k)
		if sp.distance_to(c) < radius - 6.0:
			MapIcons.draw_icon(ci, String(m["kind"]), sp, 16.0 if m["kind"] != "board" else 11.0, 0)


func _draw_frame(ci: Control, c: Vector2, radius: float) -> void:
	ci.draw_arc(c, radius - 1.5, 0.0, TAU, 72, Color(1, 1, 1, 0.55), 3.0, true)
	ci.draw_arc(c, radius + 1.5, 0.0, TAU, 72, Color(0, 0, 0, 0.45), 2.0, true)
	var b := _basis()
	var north := Vector2(-(b[2] as Vector2).y, (b[1] as Vector2).y)
	if north.length() > 0.01:
		var np := c + north.normalized() * (radius - 2.0)
		ci.draw_circle(np, 11.0, Color(0.05, 0.06, 0.08, 0.95))
		var font := UiTheme.font(true)
		ci.draw_string(font, np + Vector2(-6, 6), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, UiTheme.ACCENT)
	var car := Game.player_car
	var ang := 0.0
	if car != null and is_instance_valid(car):
		var cf := -car.global_transform.basis.z
		var cam_f: Vector2 = b[1]
		ang = cam_f.angle_to(Vector2(cf.x, cf.z))
	MapIcons.draw_arrow(ci, c, ang, 13.0, Color(1, 1, 1))
	if Game.player_car != null and Game.world != null:
		var nav: Node = Game.world.get_node_or_null("Navigator")
		if nav != null and nav.get("target") != Vector3.INF:
			var font2 := UiTheme.font(true)
			var txt := "%.1f km" % (float(nav.get("route_length")) / 1000.0)
			ci.draw_string(font2, c + Vector2(-radius, radius + 22), txt, HORIZONTAL_ALIGNMENT_CENTER, radius * 2.0, 18,
				MapIcons.COLORS["waypoint"])
