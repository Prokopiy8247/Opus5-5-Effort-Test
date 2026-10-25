extends Control
## Full-screen world map (toggle_map / M): pan (drag, WASD / arrows) and zoom (wheel, Q/E),
## region names, vector roads, POIs, activity markers, GPS route, waypoint, player arrow, scale bar and
## legend. Left click sets a waypoint (snaps to a hovered marker), right click / Delete clears it; Enter / F
## fast-travels to the hovered / selected location. Keyboard only: a screen-centre crosshair (shown on open and
## while panning / zooming with keys, until the mouse moves) picks markers, Space sets the waypoint there
## (keyboard + mouse only, no gamepad by design). Joins the "sunward_menus" group so the menus and the map
## close each other.
## Layers: the map texture, grid, roads and route are drawn in "zoom pixels" (metres x drawn zoom) and
## panned / scaled by transform, redrawn only when the zoom drifts > 25 % or the view leaves the drawn
## window; markers are draw-once sprites; only the small dynamic layer redraws every frame.

const Style := preload("res://scripts/ui/ui_style.gd")
const Icons := preload("res://scripts/ui/hud_icons.gd")
const MapData := preload("res://scripts/ui/hud_map_data.gd")
const Marker := preload("res://scripts/ui/hud_marker.gd")

const GROUP := &"sunward_menus"
const LEGEND_W := 340.0
const MARGIN := 56.0
const MAX_ZOOM := 2.6
const HOVER_PX := 18.0
const PAN_SPEED := 900.0
const POI_ORDER := ["hub", "village", "hamlet", "farm", "diner", "gas", "landmark", "viewpoint", "castle", "harbour", "lighthouse", "road",
	"speed_trap", "speed_zone", "drift", "jump", "race", "time_trial", "collectible"]

var gps: Node
## Optional Callable(target_name: String) used for fast travel (ui_root adds a fade); falls back to Game.teleport.
var travel_handler: Callable = Callable()
var menu_id: StringName = &"map"
var is_open: bool = false
## Menu-protocol flags read by menu_base.gd: other menus ignore keys while the map is open.
var captures_keys: bool = true
var pauses_game: bool = false

var _center := Vector2.ZERO
var _zoom: float = 0.25
var _fit: float = 0.25
var _dragging: bool = false
var _drag_moved: float = 0.0
var _mouse := Vector2(-9999, -9999)
var _hover: Dictionary = {}
var _selected: Dictionary = {}
var _markers: Array = []
var _sprites: Array[Marker] = []
var _regions: Array[Vector2] = []
## Screen positions (baseline centre) of the region names, laid out with the markers.
var _region_pos: Array[Vector2] = []
## Keyboard mode: Space / Enter / hover / key zoom act on the centre crosshair instead of the mouse.
var _crosshair: bool = true
var _t: float = 0.0
var _overlay_pushed: bool = false
var _fade_tween: Tween

var _bg: Control
var _world: Node2D
var _base: Node2D
var _route_node: Node2D
var _region_layer: Control
var _markers_root: Node2D
var _dyn: Control
var _legend: Control
var _route_label: Control
var _route_text: String = ""
var _drawn_zoom: float = 0.0
var _drawn_window := Rect2()
var _view_key := Vector3.INF
var _route_progress: int = -1
var _route_dirty: bool = true
var _marker_key: String = ""


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_NONE


func _ready() -> void:
	add_to_group(GROUP)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_regions = MapData.region_centers()
	_bg = _control("Backdrop", _draw_bg)
	_world = Node2D.new()
	_world.name = "World"
	add_child(_world)
	_base = Node2D.new()
	_base.name = "Base"
	_base.draw.connect(_draw_base)
	_world.add_child(_base)
	_route_node = Node2D.new()
	_route_node.name = "Route"
	_route_node.draw.connect(_draw_route)
	_world.add_child(_route_node)
	_region_layer = _control("Regions", _draw_regions)
	_markers_root = Node2D.new()
	_markers_root.name = "Markers"
	add_child(_markers_root)
	_dyn = _control("Dynamic", _draw_dyn)
	_legend = _control("Legend", _draw_legend)
	_route_label = _control("RouteLabel", _draw_route_label)
	resized.connect(_on_resized)
	if gps != null:
		gps.route_changed.connect(func() -> void: _route_dirty = true)
	# The region names make room for the waypoint pin.
	Game.waypoint_changed.connect(func(_p: Vector3) -> void: _view_key = Vector3.INF)


func _control(node_name: String, fn: Callable) -> Control:
	var c := Control.new()
	c.name = node_name
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(c)
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	c.draw.connect(fn)
	return c


func _exit_tree() -> void:
	if is_open:
		close_menu()


func _on_resized() -> void:
	if is_open:
		_view_key = Vector3.INF
		_bg.queue_redraw()
		_legend.queue_redraw()
		_route_label.queue_redraw()


# ------------------------------------------------------------------ open / close (menu protocol)

func can_open() -> bool:
	return not Game.photo_mode and not Game.is_overlay_open() and MapData.map_texture() != null


func open_menu() -> void:
	if is_open or not is_inside_tree():
		return
	for n: Node in get_tree().get_nodes_in_group(GROUP):
		if n != self and bool(n.get("is_open")) and n.has_method("close_menu"):
			n.call("close_menu")
	is_open = true
	visible = true
	modulate.a = 0.0
	if _fade_tween:
		_fade_tween.kill()
	_fade_tween = create_tween()
	_fade_tween.tween_property(self, "modulate:a", 1.0, 0.15)
	if not _overlay_pushed:
		_overlay_pushed = true
		Game.push_overlay(true)
	_refresh_markers()
	_fit_view()
	_hover = {}
	_selected = {}
	_dragging = false
	_crosshair = true
	_view_key = Vector3.INF
	_route_dirty = true
	_refresh_highlight()
	_bg.queue_redraw()


func close_menu() -> void:
	if not is_open:
		return
	is_open = false
	visible = false
	_dragging = false
	if _overlay_pushed:
		_overlay_pushed = false
		Game.push_overlay(false)


func toggle_menu() -> void:
	if is_open:
		close_menu()
	elif can_open():
		open_menu()


func _fit_view() -> void:
	var area := _area()
	_fit = minf((area.size.y - MARGIN * 2.0) / (MapData.HALF * 2.0), (area.size.x - MARGIN * 2.0) / (MapData.HALF * 2.0))
	_zoom = _fit
	_center = Vector2.ZERO


## Draws everything once while invisible (behind the loading screen) so glyph caches, marker sprites and
## road geometry exist before the first real open.
func prewarm() -> void:
	if is_open or not is_inside_tree():
		return
	_refresh_markers()
	_fit_view()
	_drawn_zoom = 0.0
	_view_key = Vector3.INF
	_route_dirty = true
	visible = true
	modulate.a = 0.0
	_update_view()
	for c: CanvasItem in [_bg, _legend, _dyn, _region_layer, _route_label]:
		c.queue_redraw()
	await get_tree().process_frame
	await get_tree().process_frame
	if not is_open:
		visible = false


func _refresh_markers() -> void:
	var list: Array = MapData.poi_markers()
	list.append_array(MapData.activity_markers())
	var key := ""
	for m: Dictionary in list:
		key += String(m["name"]) + "|"
	_markers = list
	if key != _marker_key:
		_marker_key = key
		_build_sprites()
		_legend.queue_redraw()


func _build_sprites() -> void:
	for sp in _sprites:
		sp.queue_free()
	_sprites.clear()
	for m: Dictionary in _markers:
		var sp := Marker.new()
		var kind := String(m["kind"])
		var r := 13.0 if kind == "hub" else (11.0 if bool(m.get("travel", false)) else 10.5)
		sp.setup(kind, String(m["name"]), r, m)
		_markers_root.add_child(sp)
		_sprites.append(sp)


# ------------------------------------------------------------------ coordinates

func _area() -> Rect2:
	return Rect2(Vector2.ZERO, Vector2(maxf(size.x - LEGEND_W, 200.0), size.y))


func _to_screen(w: Vector2) -> Vector2:
	return _area().get_center() + (w - _center) * _zoom


func _to_world(s: Vector2) -> Vector2:
	return _center + (s - _area().get_center()) / _zoom


func _zoom_at(screen_pos: Vector2, factor: float) -> void:
	var before := _to_world(screen_pos)
	_zoom = clampf(_zoom * factor, _fit * 0.85, MAX_ZOOM)
	var after := _to_world(screen_pos)
	_center += before - after
	_clamp_center()


func _clamp_center() -> void:
	var h := MapData.HALF
	_center = _center.clamp(Vector2(-h, -h), Vector2(h, h))


func _view_rect() -> Rect2:
	return Rect2(_to_world(Vector2.ZERO), _area().size / _zoom)


## Screen point that Space, Enter / F, hover and key zoom act on.
func _cursor() -> Vector2:
	return _area().get_center() if _crosshair or _mouse.x < 0.0 else _mouse


# ------------------------------------------------------------------ input

func _input(event: InputEvent) -> void:
	if not is_open:
		if event.is_action_pressed("toggle_map") and not event.is_echo() and can_open():
			open_menu()
			get_viewport().set_input_as_handled()
		return
	if event.is_echo():
		return
	if event.is_action_pressed("toggle_map") or event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel"):
		close_menu()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.is_pressed():
		var k := (event as InputEventKey).physical_keycode
		var used := true
		if k == KEY_ENTER or k == KEY_KP_ENTER or k == KEY_F:
			_fast_travel()
		elif k == KEY_BACKSPACE or k == KEY_DELETE:
			Game.clear_waypoint()
		elif k == KEY_HOME:
			_fit_view()
		elif k == KEY_SPACE:
			_set_waypoint_at(_cursor())
		else:
			used = false
		if used:
			get_viewport().set_input_as_handled()


func _gui_input(event: InputEvent) -> void:
	if not is_open:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		_crosshair = false
		_mouse = mb.position
		if mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_at(mb.position, 1.18)
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_at(mb.position, 1.0 / 1.18)
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_dragging = true
				_drag_moved = 0.0
			else:
				if _dragging and _drag_moved < 6.0 and mb.position.x < _area().end.x:
					_set_waypoint_at(mb.position)
				_dragging = false
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			Game.clear_waypoint()
			_selected = {}
		accept_event()
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		_crosshair = false
		_mouse = mm.position
		if _dragging:
			_center -= mm.relative / _zoom
			_drag_moved += mm.relative.length()
			_clamp_center()
		accept_event()


func _set_waypoint_at(screen_pos: Vector2) -> void:
	var m := _marker_at(screen_pos)
	var pos: Vector3
	if not m.is_empty():
		pos = m["position"]
		_selected = m
	else:
		var w := _to_world(screen_pos)
		if absf(w.x) > MapData.HALF or absf(w.y) > MapData.HALF:
			return
		var y := 0.0
		if Game.world != null and Game.world.has_method("height_at"):
			y = float(Game.world.call("height_at", w.x, w.y))
		pos = Vector3(w.x, y, w.y)
		_selected = {}
	_refresh_highlight()
	Game.set_waypoint(pos)


func _refresh_highlight() -> void:
	for sp in _sprites:
		var nm: String = sp.data["name"]
		sp.highlight = nm == String(_hover.get("name", "~")) or nm == String(_selected.get("name", "~"))


func _fast_travel() -> void:
	var m := _hover if not _hover.is_empty() else _selected
	if m.is_empty() or not bool(m.get("travel", false)):
		return
	var target := String(m["name"])
	close_menu()
	if travel_handler.is_valid():
		travel_handler.call(target)
	else:
		Game.teleport(target)


func _marker_at(screen_pos: Vector2) -> Dictionary:
	var best: Dictionary = {}
	var bd := HOVER_PX
	for sp in _sprites:
		if not sp.visible:
			continue
		var d := sp.position.distance_to(screen_pos)
		if d < bd:
			bd = d
			best = sp.data
	return best


# ------------------------------------------------------------------ per frame

func _process(delta: float) -> void:
	if not is_open:
		return
	_t += delta
	var pan := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
		pan.x -= 1.0
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
		pan.x += 1.0
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):
		pan.y -= 1.0
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
		pan.y += 1.0
	if pan != Vector2.ZERO:
		_crosshair = true
		_center += pan.limit_length(1.0) * PAN_SPEED * delta / _zoom * 0.3
		_clamp_center()
	var zoom_in := 0.0
	if Input.is_physical_key_pressed(KEY_E) or Input.is_physical_key_pressed(KEY_EQUAL) or Input.is_physical_key_pressed(KEY_KP_ADD):
		zoom_in += 1.0
	if Input.is_physical_key_pressed(KEY_Q) or Input.is_physical_key_pressed(KEY_MINUS) or Input.is_physical_key_pressed(KEY_KP_SUBTRACT):
		zoom_in -= 1.0
	if zoom_in != 0.0:
		_crosshair = true
		_zoom_at(_cursor(), exp(zoom_in * delta * 2.2))
	_update_view()
	var hv := _marker_at(_cursor())
	if hv.get("name", "") != _hover.get("name", ""):
		_hover = hv
		_refresh_highlight()
	var rtxt := Style.distance_text(float(gps.remaining_m)) if (gps != null and gps.active) else ""
	if rtxt != _route_text:
		_route_text = rtxt
		_route_label.queue_redraw()
	_dyn.queue_redraw()


## Applies pan / zoom: transforms the world layers, redraws them when needed, repositions sprites.
func _update_view() -> void:
	var key := Vector3(_center.x, _center.y, _zoom)
	if key == _view_key and not _route_dirty:
		return
	_view_key = key
	var view := _view_rect()
	if _drawn_zoom <= 0.0 or absf(_zoom / _drawn_zoom - 1.0) > 0.25 or not _drawn_window.encloses(view.intersection(_full_rect())):
		_drawn_zoom = _zoom
		_drawn_window = view.grow_individual(view.size.x, view.size.y, view.size.x, view.size.y)
		_base.queue_redraw()
		_route_dirty = true
	var k := _zoom / _drawn_zoom
	_world.transform = Transform2D(0.0, Vector2(k, k), 0.0, _area().get_center() - _center * _zoom)
	if _route_dirty or (gps != null and absi(int(gps.progress) - _route_progress) >= 12):
		_route_dirty = false
		_route_progress = int(gps.progress) if gps != null else -1
		_route_node.queue_redraw()
	_region_layer.queue_redraw()
	_place_sprites()


func _full_rect() -> Rect2:
	return Rect2(-MapData.HALF, -MapData.HALF, MapData.HALF * 2.0, MapData.HALF * 2.0)


func _place_sprites() -> void:
	var show_names := _zoom > _fit * 1.7
	var area_end := _area().end.x
	var taken: Array[Rect2] = []
	for sp in _sprites:
		var wp: Vector3 = sp.data["position"]
		var p := _to_screen(Vector2(wp.x, wp.z))
		var vis := p.x > -30.0 and p.x < area_end - 6.0 and p.y > -30.0 and p.y < size.y + 30.0
		sp.visible = vis
		if vis:
			sp.position = p
			taken.append(Rect2(p - Vector2(sp.radius, sp.radius), Vector2(sp.radius, sp.radius) * 2.0))
	# Region names avoid the marker badges (and the waypoint pin); name tags then avoid the region names.
	taken.append_array(_layout_regions(taken))
	for sp in _sprites:
		if not sp.visible:
			continue
		var p := sp.position
		var want_tag := show_names or sp.kind == "hub"
		if want_tag:
			var r := sp.tag_rect()
			r.position += p
			for o in taken:
				if o.intersects(r.grow(2.0)) and not o.has_point(p):
					want_tag = false
					break
			if want_tag:
				taken.append(r)
		sp.show_tag = want_tag


# ------------------------------------------------------------------ drawing

func _draw_bg() -> void:
	_bg.draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.03, 0.05, 0.94))


func _draw_base() -> void:
	var z := _drawn_zoom
	var h := MapData.HALF
	var map_rect := Rect2(Vector2(-h, -h) * z, Vector2(h, h) * 2.0 * z)
	_base.draw_rect(map_rect.grow(6.0), Color(0, 0, 0, 0.5))
	var tex := MapData.map_texture()
	if tex != null:
		_base.draw_texture_rect(tex, map_rect, false, Color(0.86, 0.88, 0.92))
	var col := Color(1, 1, 1, 0.05)
	var x := -h + 512.0
	while x < h:
		_base.draw_line(Vector2(x * z, map_rect.position.y), Vector2(x * z, map_rect.end.y), col, 1.0)
		_base.draw_line(Vector2(map_rect.position.x, x * z), Vector2(map_rect.end.x, x * z), col, 1.0)
		x += 512.0
	var step := MapData.COARSE_STEP if z < 0.6 else MapData.DETAIL_STEP
	MapData.draw_roads(_base, Transform2D(0.0, Vector2(z, z), 0.0, Vector2.ZERO), _drawn_window, clampf(z / 0.45, 0.62, 2.0), 1.0, step)


func _draw_route() -> void:
	if gps == null or not gps.active or _drawn_zoom <= 0.0:
		return
	var pts: PackedVector2Array = gps.points_2d
	pts = pts.slice(clampi(int(gps.progress) >> 1, 0, maxi(pts.size() - 2, 0)))
	if pts.size() < 2:
		return
	var z := _drawn_zoom
	var lxf := Transform2D(0.0, Vector2(z, z), 0.0, Vector2.ZERO)
	var local := lxf * pts
	var w := clampf(z * 14.0, 4.0, 9.0)
	_route_node.draw_polyline(local, Color(0.05, 0.02, 0.06, 0.75), w + 4.0, true)
	_route_node.draw_polyline(local, Style.ROUTE, w, true)
	var re: Vector3 = gps.road_end()
	var dest: Vector3 = gps.destination
	if re != Vector3.INF and dest != Vector3.INF:
		_route_node.draw_dashed_line(lxf * Vector2(re.x, re.z), lxf * Vector2(dest.x, dest.z), Style.ROUTE, 3.0, 10.0, true, true)


func _region_fade() -> float:
	return 1.0 - clampf((_zoom / _fit - 2.2) / 1.2, 0.0, 1.0)


func _region_font_size() -> int:
	return int(clampf(30.0 * sqrt(_zoom / _fit), 28.0, 42.0))


## Places each region name (baseline centre in _region_pos) at the free spot closest to its anchor,
## clear of the given marker rects, the waypoint pin and the names placed before it. Returns the name rects.
func _layout_regions(icons: Array[Rect2]) -> Array[Rect2]:
	_region_pos.clear()
	var placed: Array[Rect2] = []
	if _region_fade() <= 0.0:
		return placed
	var fs := _region_font_size()
	var h := MapData.HALF
	var lo := _to_screen(Vector2(-h, -h))
	var hi := _to_screen(Vector2(h, h))
	var obstacles: Array[Rect2] = []
	for r in icons:
		obstacles.append(r.grow(3.0))
	if Game.waypoint != Vector3.INF:
		var wp := _to_screen(Vector2(Game.waypoint.x, Game.waypoint.z))
		obstacles.append(Rect2(wp + Vector2(-14.0, -40.0), Vector2(28.0, 46.0)))
	for i in mini(_regions.size(), WorldLayout.REGIONS.size()):
		var base := _to_screen(_regions[i])
		var nm := String(WorldLayout.REGIONS[i]["name"]).to_upper()
		var tw := Style.text_width(nm, fs, 700, false, 6)
		var half_w := tw * 0.5 + 16.0
		var reach := Rect2(base - Vector2(half_w * 1.6, fs * 4.0), Vector2(half_w * 3.2, fs * 8.0))
		var near: Array[Rect2] = []
		for o in obstacles:
			if o.intersects(reach):
				near.append(o)
		var best := base
		var best_cost := INF
		for off: Vector2 in _region_offsets(fs, tw):
			var p := base + off
			if hi.x - lo.x > half_w * 2.0:
				p.x = clampf(p.x, lo.x + half_w, hi.x - half_w)
			var r := _region_rect(p, tw, fs)
			var hit := 0.0
			for o in near:
				if o.intersects(r):
					hit += o.intersection(r).get_area()
			var cost := off.length() + (hit + 4000.0 if hit > 0.0 else 0.0)
			if cost < best_cost:
				best_cost = cost
				best = p
			if hit == 0.0:
				break
		_region_pos.append(best)
		var rect := _region_rect(best, tw, fs)
		placed.append(rect)
		obstacles.append(rect)
	return placed


## Glyph box of a region name drawn centred on baseline point p.
func _region_rect(p: Vector2, tw: float, fs: int) -> Rect2:
	return Rect2(p.x - tw * 0.5 - 6.0, p.y - fs * 0.8, tw + 12.0, fs * 0.95)


## Candidate label offsets from the anchor, nearest first.
func _region_offsets(fs: int, tw: float) -> Array[Vector2]:
	var out: Array[Vector2] = []
	for k in 13:
		var dy := floori((k + 1) / 2.0) * (1 if k % 2 == 1 else -1) * fs * 0.55
		for dx: float in [0.0, -0.2, 0.2, -0.4, 0.4]:
			out.append(Vector2(dx * tw, dy))
	out.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.length_squared() < b.length_squared())
	return out


func _draw_regions() -> void:
	var fade := _region_fade()
	if fade <= 0.0:
		return
	var fs := _region_font_size()
	for i in mini(_region_pos.size(), WorldLayout.REGIONS.size()):
		var p := _region_pos[i]
		var nm := String(WorldLayout.REGIONS[i]["name"]).to_upper()
		var rc: Color = (WorldLayout.REGIONS[i]["color"] as Color).lightened(0.55)
		Style.draw_text(_region_layer, nm, p + Vector2(-400, 0), fs, Color(rc, 0.92 * fade), HORIZONTAL_ALIGNMENT_CENTER, 800.0, 700, false, 6, 0.9)


func _draw_dyn() -> void:
	var ci := _dyn
	for sp in _sprites:
		if sp.kind == "hub" and sp.visible:
			var pulse := 0.5 + 0.5 * sin(_t * 3.0)
			ci.draw_arc(sp.position, sp.radius * (1.5 + pulse * 0.35), 0.0, TAU, 32, Color(Style.ACCENT, 0.6 - pulse * 0.4), 2.0, true)
	if Game.waypoint != Vector3.INF:
		Icons.draw_pin(ci, _to_screen(Vector2(Game.waypoint.x, Game.waypoint.z)), 12.0, Style.ROUTE)
	var car := Game.player_car
	if car != null and is_instance_valid(car):
		var p3 := car.global_position
		var f := -car.global_transform.basis.z
		var p := _to_screen(Vector2(p3.x, p3.z))
		var ph := fmod(_t * 0.9, 1.0)
		ci.draw_arc(p, 12.0 + ph * 26.0, 0.0, TAU, 40, Color(1, 1, 1, (1.0 - ph) * 0.7), 2.0, true)
		Icons.draw_player_arrow(ci, p, atan2(f.x, -f.z), 13.0)
	if _crosshair:
		var c := _area().get_center()
		var wc := Color(1, 1, 1, 0.85)
		ci.draw_arc(c, 16.0, 0.0, TAU, 32, wc, 2.0, true)
		for d: Vector2 in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
			ci.draw_line(c + d * 10.0, c + d * 26.0, wc, 2.0)
	_draw_scale_bar(ci)
	if not _hover.is_empty():
		_draw_card(ci, _hover)


func _draw_scale_bar(ci: CanvasItem) -> void:
	var m := 160.0 / _zoom
	var nice: Array[float] = [50.0, 100.0, 200.0, 250.0, 500.0, 1000.0, 2000.0]
	var pick := nice[0]
	for v in nice:
		if v <= m:
			pick = v
	var px := pick * _zoom
	var o := Vector2(MARGIN, size.y - MARGIN)
	var wc := Color(1, 1, 1, 0.9)
	ci.draw_line(o, o + Vector2(px, 0), wc, 3.0)
	ci.draw_line(o + Vector2(0, -8), o + Vector2(0, 2), wc, 2.0)
	ci.draw_line(o + Vector2(px, -8), o + Vector2(px, 2), wc, 2.0)
	Style.draw_text(ci, Style.distance_text(pick), o + Vector2(0, -14), 16, Style.TEXT, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 600, false, 0, 0.6)
	var n := Vector2(MARGIN + 14.0, MARGIN + 30.0)
	ci.draw_colored_polygon(PackedVector2Array([n + Vector2(0, -22), n + Vector2(10, 8), n + Vector2(0, 2), n + Vector2(-10, 8)]), wc)
	Style.draw_text(ci, "N", n + Vector2(-20, 32), 18, Style.ACCENT, HORIZONTAL_ALIGNMENT_CENTER, 40.0, 700, false, 0, 0.0)


func _draw_card(ci: CanvasItem, m: Dictionary) -> void:
	var wp: Vector3 = m["position"]
	var p := _to_screen(Vector2(wp.x, wp.z))
	var kind := String(m["kind"])
	var sub := Icons.name_for(kind)
	if String(m.get("region", "")) != "":
		sub += "  ·  " + String(m["region"])
	var car := Game.player_car
	if car != null and is_instance_valid(car):
		sub += "  ·  " + Style.distance_text(Vector2(wp.x - car.global_position.x, wp.z - car.global_position.z).length())
	var lines: Array = [["Click / Space", "Set waypoint"]]
	if bool(m.get("travel", false)):
		lines.append(["Enter / F", "Fast travel"])
	var title := String(m["name"])
	var w := maxf(maxf(Style.text_width(title, 24, 700), Style.text_width(sub, 16, 500)) + 40.0, 260.0)
	var h := 76.0 + lines.size() * 26.0
	var pos := p + Vector2(24, -h * 0.5)
	if pos.x + w > _area().end.x - 10.0:
		pos.x = p.x - 24.0 - w
	pos.y = clampf(pos.y, 10.0, size.y - h - 10.0)
	var col := Icons.color_for(kind)
	Style.draw_round_rect(ci, Rect2(pos, Vector2(w, h)), Color(0.035, 0.04, 0.07, 0.95), 14, 2, Color(col, 0.8))
	Style.draw_text(ci, title, pos + Vector2(18, 34), 24, Style.TEXT, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 700, false, 0, 0.0)
	Style.draw_text(ci, sub, pos + Vector2(18, 58), 16, Style.TEXT_DIM, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 500, false, 0, 0.0)
	var y := pos.y + 74.0
	for l: Array in lines:
		var kw := Style.text_width(String(l[0]), 14, 700) + 14.0
		Style.draw_round_rect(ci, Rect2(Vector2(pos.x + 18, y), Vector2(kw, 22)), Color(0.93, 0.93, 0.95, 0.9), 6)
		Style.draw_text(ci, String(l[0]), Vector2(pos.x + 18, y + 16), 14, Style.INK, HORIZONTAL_ALIGNMENT_CENTER, kw, 700, false, 0, 0.0)
		Style.draw_text(ci, String(l[1]), Vector2(pos.x + 28 + kw, y + 17), 16, Style.TEXT, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 600, false, 0, 0.0)
		y += 26.0


func _draw_legend() -> void:
	var ci := _legend
	var r := Rect2(Vector2(size.x - LEGEND_W, 0), Vector2(LEGEND_W, size.y))
	ci.draw_rect(r, Color(0.03, 0.035, 0.06, 0.97))
	ci.draw_line(r.position, r.position + Vector2(0, r.size.y), Color(1, 1, 1, 0.08), 1.0)
	var x := r.position.x + 28.0
	var y := 64.0
	Style.draw_text(ci, "SUNWARD ROADS", Vector2(x, y), 15, Style.ACCENT, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 700, false, 4, 0.0)
	Style.draw_text(ci, "World Map", Vector2(x, y + 40), 36, Style.TEXT, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 700, false, 0, 0.0)
	ci.draw_polyline_colors(PackedVector2Array([Vector2(x, y + 56), Vector2(x + 140, y + 56)]), PackedColorArray([Style.ACCENT, Style.ACCENT_2]), 3.0, true)
	y += 96.0
	for reg: Dictionary in WorldLayout.REGIONS:
		var rc: Color = reg["color"]
		ci.draw_circle(Vector2(x + 7, y - 6), 7.0, rc.lightened(0.2), true, -1.0, true)
		Style.draw_text(ci, String(reg["name"]), Vector2(x + 24, y), 17, Style.TEXT, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 600, false, 0, 0.0)
		y += 27.0
	y += 14.0
	var kinds := {}
	for m: Dictionary in _markers:
		kinds[String(m["kind"])] = true
	for k: String in POI_ORDER:
		if not kinds.has(k) or (k == "hamlet" and kinds.has("village")):
			continue
		Icons.draw_badge(ci, k, Vector2(x + 10, y - 6), 10.0)
		Style.draw_text(ci, Icons.name_for(k) if k != "village" else "Village / hamlet", Vector2(x + 30, y), 16, Style.TEXT_DIM,
			HORIZONTAL_ALIGNMENT_LEFT, -1.0, 500, false, 0, 0.0)
		y += 26.0
	ci.draw_line(Vector2(x, y - 6), Vector2(x + 22, y - 6), Style.ROUTE, 5.0)
	Style.draw_text(ci, "GPS route", Vector2(x + 30, y), 16, Style.TEXT_DIM, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 500, false, 0, 0.0)
	y += 26.0
	Icons.draw_pin(ci, Vector2(x + 10, y + 2), 7.0, Style.ROUTE)
	Style.draw_text(ci, "Waypoint", Vector2(x + 30, y), 16, Style.TEXT_DIM, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 500, false, 0, 0.0)
	y += 26.0
	Icons.draw_player_arrow(ci, Vector2(x + 10, y - 6), 0.0, 8.0)
	Style.draw_text(ci, "You", Vector2(x + 30, y), 16, Style.TEXT_DIM, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 500, false, 0, 0.0)
	var by := size.y - 214.0
	var help := [["LMB / Space", "Set waypoint"], ["RMB / Del", "Clear waypoint"], ["Wheel / Q E", "Zoom"], ["Drag / WASD", "Pan"],
		["Enter / F", "Fast travel"], ["M / Esc", "Close"]]
	for hl: Array in help:
		var kw := Style.text_width(String(hl[0]), 13, 700) + 12.0
		Style.draw_round_rect(ci, Rect2(Vector2(x, by), Vector2(kw, 21)), Color(0.93, 0.93, 0.95, 0.88), 5)
		Style.draw_text(ci, String(hl[0]), Vector2(x, by + 15), 13, Style.INK, HORIZONTAL_ALIGNMENT_CENTER, kw, 700, false, 0, 0.0)
		Style.draw_text(ci, String(hl[1]), Vector2(x + kw + 10, by + 16), 15, Style.TEXT_DIM, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 500, false, 0, 0.0)
		by += 27.0


func _draw_route_label() -> void:
	if _route_text == "":
		return
	Style.draw_text(_route_label, "ROUTE  %s" % _route_text, Vector2(size.x - LEGEND_W + 28.0, size.y - 238.0), 18, Style.ROUTE,
		HORIZONTAL_ALIGNMENT_LEFT, -1.0, 700, false, 2, 0.0)
