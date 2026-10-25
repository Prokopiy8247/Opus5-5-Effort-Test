extends CanvasLayer
## Full world map (M): pauses the game; pan with left drag, zoom with the wheel, left click sets a
## GPS waypoint, right click clears it, F fast-travels to the hovered event/landmark. Shows the
## regions, roads, activities with stars, festival boards, landmarks, route and the player.

var tex: Texture2D
var half: float = 2000.0
var is_open := false
var _root: Control
var _canvas: Control
var _info: Label
var _legend: Label
var _zoom := 1.0
var _pan := Vector2.ZERO        # map pixel at the screen centre
var _drag := false
var _drag_moved := 0.0
var _hover: Dictionary = {}
var _markers: Array = []
var _region_labels: Array = []   # [name, world pos]


class Canvas:
	extends Control
	var owner_map: Node

	func _draw() -> void:
		owner_map.call("_draw_map", self)


func _ready() -> void:
	name = "WorldMap"
	layer = 30
	process_mode = Node.PROCESS_MODE_ALWAYS
	tex = load("res://data/world/map.png")
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.theme = UiTheme.get_theme()
	_root.visible = false
	add_child(_root)
	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.04, 0.06, 0.94)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(bg)
	_canvas = Canvas.new()
	_canvas.owner_map = self
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_STOP
	_canvas.gui_input.connect(_on_input)
	_root.add_child(_canvas)
	var title := UiTheme.label("RIDGELINE FESTIVAL · WORLD MAP", 30, UiTheme.ACCENT, true)
	title.position = Vector2(36, 24)
	_root.add_child(title)
	_info = UiTheme.label("", 20, UiTheme.TEXT)
	_info.position = Vector2(36, 66)
	_root.add_child(_info)
	_legend = UiTheme.label("", 17, UiTheme.TEXT_DIM)
	_legend.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_legend.offset_left = 36
	_legend.offset_top = -150
	_legend.offset_bottom = -20
	_root.add_child(_legend)
	_legend.text = "S speed trap   Z speed zone   D drift zone   ! danger sign   R road race   T time trial   ◆ festival board\n" + \
		"Left click: set GPS waypoint   Right click: clear   Drag: pan   Wheel: zoom   F: fast travel to hovered   M / Esc: close"


func _unhandled_input(event: InputEvent) -> void:
	if Game.ui_focus.has("console") or Game.ui_focus.has("photo"):
		return
	if event.is_action_pressed("toggle_map") or (is_open and event.is_action_pressed("pause_menu")):
		if is_open:
			close()
		elif not Game.ui_blocks_driving():
			open()
		get_viewport().set_input_as_handled()
	elif is_open and event is InputEventKey and event.pressed and not event.echo and (event as InputEventKey).keycode == KEY_F:
		_fast_travel()
		get_viewport().set_input_as_handled()


func open() -> void:
	if Game.world != null and "data" in Game.world:
		half = (Game.world.get("data") as WorldData).half
	is_open = true
	_root.visible = true
	_markers = MapIcons.markers()
	if _region_labels.is_empty():
		_compute_region_labels()
	# open on the whole map (fits the screen height); wheel-zoom towards the cursor from there
	_pan = Vector2(MapIcons.MAP_PX, MapIcons.MAP_PX) * 0.5
	_zoom = 0.92
	Game.set_ui_focus("map", true)
	get_tree().paused = true
	_update_info()
	_canvas.queue_redraw()


func close() -> void:
	is_open = false
	_root.visible = false
	Game.set_ui_focus("map", false)
	get_tree().paused = false


func _scale() -> float:
	return _canvas.size.y / MapIcons.MAP_PX * _zoom


func _to_screen(px: Vector2) -> Vector2:
	return _canvas.size * 0.5 + (px - _pan) * _scale()


func _to_px(sp: Vector2) -> Vector2:
	return _pan + (sp - _canvas.size * 0.5) / _scale()


func _on_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_zoom_at(mb.position, 1.2)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_zoom_at(mb.position, 1.0 / 1.2)
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_drag = true
				_drag_moved = 0.0
			else:
				_drag = false
				if _drag_moved < 6.0:
					var target: Vector3 = _hover.get("pos", MapIcons.px_to_world(_to_px(mb.position), half))
					Game.main.call("set_waypoint", target)
					Game.show_notification("GPS waypoint set", String(_hover.get("name", "Map location")), "info")
					_update_info()
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			Game.main.call("set_waypoint", Vector3.INF)
			_update_info()
		_canvas.queue_redraw()
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _drag:
			_pan -= mm.relative / _scale()
			_drag_moved += mm.relative.length()
		_update_hover(mm.position)
		_canvas.queue_redraw()


func _zoom_at(sp: Vector2, f: float) -> void:
	var before := _to_px(sp)
	_zoom = clampf(_zoom * f, 0.6, 6.0)
	var after := _to_px(sp)
	_pan += before - after


func _update_hover(sp: Vector2) -> void:
	_hover = {}
	var best := 16.0
	for m in _markers:
		var d := _to_screen(MapIcons.world_to_px(m["pos"], half)).distance_to(sp)
		if d < best:
			best = d
			_hover = m
	_update_info()


func _update_info() -> void:
	var lines: Array[String] = []
	if Game.activities != null:
		var am: Node = Game.activities
		lines.append("Stars %d   ·   Credits %s   ·   Festival boards %d / %d" % [int(am.call("total_stars")), str(am.call("get_credits")),
			(am.get("boards_smashed") as Dictionary).size(), 30])
	var nav: Node = Game.world.get_node_or_null("Navigator") if Game.world != null else null
	if nav != null and nav.get("target") != Vector3.INF:
		lines.append("GPS route %.1f km" % (float(nav.get("route_length")) / 1000.0))
	if not _hover.is_empty():
		var t := String(_hover["name"])
		if int(_hover.get("stars", 0)) > 0 or _hover.has("id"):
			t += "   " + "★".repeat(int(_hover.get("stars", 0))) + "☆".repeat(3 - int(_hover.get("stars", 0)))
		if _hover.has("id") and Game.activities != null:
			var bests: Dictionary = (Game.activities.call("get_bests") as Dictionary)["values"]
			var d: ActivityDef = Game.activities.call("find", String(_hover["id"]))
			if d != null and bests.has(d.id):
				t += "   PB " + d.format_value(float(bests[d.id]), bool(Game.settings.get("units_mph", false)))
		lines.append(t + "   (F: fast travel)")
	_info.text = "\n".join(lines)


func _fast_travel() -> void:
	if _hover.is_empty() or Game.player_car == null:
		return
	var m := _hover
	close()
	if m.has("id") and Game.activities != null:
		var d: ActivityDef = Game.activities.call("find", String(m["id"]))
		if d != null:
			Game.activities.call("teleport_to", d)
			return
	var p: Vector3 = m["pos"]
	Game.world.call("prepare_area", p)
	Game.player_car.reset_to(Game.world.call("nearest_road_transform", p, Vector3.FORWARD))
	if Game.camera_rig != null:
		Game.camera_rig.call("snap")


func _compute_region_labels() -> void:
	## label each region at the centroid of its land area (coarse 80 m sampling of the region map)
	var data: WorldData = Game.world.get("data")
	var sums := [Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO]
	var counts := [0, 0, 0, 0]
	var x := -half + 40.0
	while x < half:
		var z := -half + 40.0
		while z < half:
			if data.height_at(x, z) > 1.0:
				var r := data.region_index(x, z)
				sums[r] += Vector3(x, 0, z)
				counts[r] += 1
			z += 80.0
		x += 80.0
	for r in 4:
		if counts[r] > 0:
			_region_labels.append([String(WorldData.REGION_NAMES[r]).to_upper(), sums[r] / float(counts[r])])


func _draw_map(ci: Control) -> void:
	if tex == null:
		return
	var tl := _to_screen(Vector2.ZERO)
	var br := _to_screen(Vector2(MapIcons.MAP_PX, MapIcons.MAP_PX))
	ci.draw_texture_rect(tex, Rect2(tl, br - tl), false)
	ci.draw_rect(Rect2(tl, br - tl), Color(1, 1, 1, 0.25), false, 2.0)
	# region labels
	var font := UiTheme.font(true)
	for rg in _region_labels:
		var sp := _to_screen(MapIcons.world_to_px(rg[1], half))
		var txt: String = rg[0]
		var fs := int(clampf(18.0 * _zoom, 16.0, 34.0))
		var w := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		ci.draw_string_outline(font, sp - Vector2(w * 0.5, 0), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 6, Color(0, 0, 0, 0.6))
		ci.draw_string(font, sp - Vector2(w * 0.5, 0), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1, 0.85))
	# route
	var nav: Node = Game.world.get_node_or_null("Navigator") if Game.world != null else null
	if nav != null:
		var rp: PackedVector3Array = nav.get("route_points")
		if rp.size() > 1:
			var pts := PackedVector2Array()
			for q in rp:
				pts.append(_to_screen(MapIcons.world_to_px(q, half)))
			ci.draw_polyline(pts, Color(0, 0, 0, 0.55), 8.0, true)
			ci.draw_polyline(pts, MapIcons.COLORS["waypoint"], 5.0, true)
		var tgt: Vector3 = nav.get("target")
		if tgt != Vector3.INF:
			var tp := _to_screen(MapIcons.world_to_px(tgt, half))
			ci.draw_line(tp, tp + Vector2(0, -34), Color.WHITE, 3.0)
			ci.draw_colored_polygon(PackedVector2Array([tp + Vector2(0, -34), tp + Vector2(22, -27), tp + Vector2(0, -20)]),
				MapIcons.COLORS["waypoint"])
	var size := clampf(20.0 * sqrt(_zoom), 18.0, 34.0)
	for m in _markers:
		var sp := _to_screen(MapIcons.world_to_px(m["pos"], half))
		var k := String(m["kind"])
		MapIcons.draw_icon(ci, k, sp, size * (0.65 if k == "board" else 1.0), int(m.get("stars", 0)))
	if not _hover.is_empty():
		var hp := _to_screen(MapIcons.world_to_px(_hover["pos"], half))
		ci.draw_arc(hp, size * 0.85, 0.0, TAU, 32, Color.WHITE, 2.5, true)
		var nm := String(_hover["name"])
		var fs2 := 20
		var w2 := font.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, fs2).x
		ci.draw_rect(Rect2(hp + Vector2(-w2 * 0.5 - 8, -size - 34), Vector2(w2 + 16, 28)), Color(0.04, 0.05, 0.07, 0.9))
		ci.draw_string(font, hp + Vector2(-w2 * 0.5, -size - 13), nm, HORIZONTAL_ALIGNMENT_LEFT, -1, fs2, UiTheme.TEXT)
	var car := Game.player_car
	if car != null and is_instance_valid(car):
		var cp := _to_screen(MapIcons.world_to_px(car.global_position, half))
		var f := -car.global_transform.basis.z
		MapIcons.draw_arrow(ci, cp, Vector2(0, -1).angle_to(Vector2(f.x, f.z)), 16.0, UiTheme.ACCENT)
