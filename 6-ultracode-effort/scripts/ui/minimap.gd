extends Control
## Bottom-left circular heading-up minimap: the map texture rotated in a canvas shader, vector roads and
## the GPS route clipped to the circle, POI / activity icons, waypoint pin (clamped to the rim), player
## arrow, north badge, distance-to-waypoint chip, region and road name underneath.
## Cheap per frame: the whole road network is drawn once in "level pixels" (metres x LEVEL) and only
## rotated / scaled / moved by its transform (speed zoom = 0.7x..1.5x of LEVEL); the route redraws when
## it changes; icons are draw-once sprites. Each frame only transforms, uniforms and positions change.

const Style := preload("res://scripts/ui/ui_style.gd")
const Icons := preload("res://scripts/ui/hud_icons.gd")
const MapData := preload("res://scripts/ui/hud_map_data.gd")
const Marker := preload("res://scripts/ui/hud_marker.gd")
const SHADER := preload("res://assets/shaders/ui_minimap.gdshader")
const CLIP_SHADER := preload("res://assets/shaders/ui_minimap_overlay.gdshader")

const MAP := 260.0
const PAD := 10.0
const NEAR_M := 175.0
const FAR_M := 380.0
const LEVEL := 0.5
const MARKER_R := 8.5
const PLATE_MIN_W := 268.0
const PLATE_PAD := 20.0

var gps: Node

var _tex_rect: TextureRect
var _mat := ShaderMaterial.new()
var _clip := ShaderMaterial.new()
var _roads: Node2D
var _route: Node2D
var _ring: Control
var _markers_root: Node2D
var _sprites: Array[Marker] = []
var _marker_key: String = ""
var _pin: Marker
var _north: Marker
var _chip: Control
var _chip_text: String = ""
var _region_label: Label
var _road_label: Label
var _player := Vector2.ZERO
var _heading: float = 0.0
var _radius_m: float = NEAR_M
var _have_pos: bool = false
var _roads_drawn: bool = false
var _route_progress: int = -1
var _route_dirty: bool = true
var _marker_timer: float = 0.0
var _label_timer: float = 0.0
## Width of the backing plate under the region / road names (grows with the text).
var _plate_w: float = PLATE_MIN_W


var _road_now: RoadNetwork.Road = null

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	anchor_left = 0.0
	anchor_right = 0.0
	anchor_top = 1.0
	anchor_bottom = 1.0
	offset_left = 34.0
	offset_right = 34.0 + MAP + PAD * 2.0
	offset_top = -(MAP + PAD * 2.0 + 66.0) - 18.0
	offset_bottom = -18.0
	_mat.shader = SHADER
	_clip.shader = CLIP_SHADER
	_tex_rect = TextureRect.new()
	_tex_rect.name = "Map"
	_tex_rect.texture = MapData.map_texture()
	_tex_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_tex_rect.stretch_mode = TextureRect.STRETCH_SCALE
	_tex_rect.position = Vector2(PAD, PAD)
	_tex_rect.size = Vector2(MAP, MAP)
	_tex_rect.material = _mat
	_tex_rect.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_tex_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_tex_rect)
	_roads = _layer("Roads", _draw_roads)
	_route = _layer("Route", _draw_route)
	_markers_root = Node2D.new()
	_markers_root.name = "Markers"
	add_child(_markers_root)
	_ring = Control.new()
	_ring.name = "Ring"
	_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ring.size = Vector2(MAP + PAD * 2.0, MAP + PAD * 2.0)
	_ring.draw.connect(_draw_ring)
	add_child(_ring)
	_pin = Marker.new()
	_pin.setup("_pin", "", 7.0)
	add_child(_pin)
	_north = Marker.new()
	_north.setup("_north", "", 13.0)
	add_child(_north)
	_chip = Control.new()
	_chip.name = "Chip"
	_chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_chip.size = Vector2(MAP + PAD * 2.0, MAP + PAD * 2.0)
	_chip.draw.connect(_draw_chip)
	add_child(_chip)
	_region_label = _label(20, Style.TEXT, 700, 3, MAP + PAD * 2.0 + 6.0, 28.0)
	_road_label = _label(16, Style.TEXT_DIM, 500, 0, MAP + PAD * 2.0 + 34.0, 24.0)
	Game.region_changed.connect(func(region_name: String) -> void: _set_labels(region_name.to_upper(), _road_label.text))
	if gps != null:
		gps.route_changed.connect(func() -> void: _route_dirty = true)


func _layer(node_name: String, draw_fn: Callable) -> Node2D:
	var n := Node2D.new()
	n.name = node_name
	n.material = _clip
	n.draw.connect(draw_fn)
	add_child(n)
	return n


func _label(size_px: int, col: Color, weight: int, spacing: int, y: float, h: float) -> Label:
	var l := Label.new()
	l.label_settings = Style.label_settings(size_px, col, weight, false, spacing)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.position = Vector2(-40, y)
	l.size = Vector2(MAP + PAD * 2.0 + 80.0, h)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	return l


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	var car := Game.player_car
	var target := Vector3.ZERO
	var fwd := Vector3(0, 0, -1)
	var kmh := 0.0
	if car != null and is_instance_valid(car):
		var cxf := car.get_global_transform_interpolated()
		target = cxf.origin
		fwd = -cxf.basis.z
		kmh = car.get_speed_kmh()
	elif Game.camera_rig != null:
		var cam := (Game.camera_rig as CameraRig).camera
		if cam != null:
			target = cam.global_position
			fwd = -cam.global_transform.basis.z
	_player = Vector2(target.x, target.z)
	var flat := Vector2(fwd.x, fwd.z)
	if flat.length_squared() > 0.01:
		var h := atan2(flat.x, -flat.y)
		_heading = h if not _have_pos else lerp_angle(_heading, h, clampf(delta * 14.0, 0.0, 1.0))
	_have_pos = true
	var want := lerpf(NEAR_M, FAR_M, clampf((kmh - 40.0) / 150.0, 0.0, 1.0))
	_radius_m = lerpf(_radius_m, want, clampf(delta * 1.5, 0.0, 1.0))
	var s := (MAP * 0.5) / _radius_m
	var c := Vector2(PAD + MAP * 0.5, PAD + MAP * 0.5)
	var origin := c - (_player * s).rotated(-_heading)
	var xf := Transform2D(-_heading, Vector2(s, s), 0.0, origin)
	_mat.set_shader_parameter("center_uv", (_player + Vector2(MapData.HALF, MapData.HALF)) / (MapData.HALF * 2.0))
	_mat.set_shader_parameter("heading", _heading)
	_mat.set_shader_parameter("zoom_uv", _radius_m / (MapData.HALF * 2.0))
	if not _roads_drawn and MapData.network() != null:
		_roads_drawn = true
		_roads.queue_redraw()
	var k := s / LEVEL
	var lxf := Transform2D(-_heading, Vector2(k, k), 0.0, origin)
	_roads.transform = lxf
	_route.transform = lxf
	_clip.set_shader_parameter("center", _player * LEVEL)
	_clip.set_shader_parameter("radius", MAP * 0.5 / k)
	_clip.set_shader_parameter("feather", 1.5 / k)
	var route_on: bool = gps != null and gps.active
	_route.visible = route_on
	if route_on and (_route_dirty or absi(int(gps.progress) - _route_progress) >= 12):
		_route_dirty = false
		_route_progress = int(gps.progress)
		_route.queue_redraw()
	_marker_timer -= delta
	if _marker_timer <= 0.0:
		_marker_timer = 1.0
		_refresh_markers()
	_place_markers(xf, c)
	_label_timer -= delta
	if _label_timer <= 0.0:
		_label_timer = 0.5
		_update_labels(target)


func _refresh_markers() -> void:
	var list: Array = MapData.poi_markers()
	list.append_array(MapData.activity_markers())
	var key := ""
	for m: Dictionary in list:
		key += String(m["name"]) + "|"
	if key == _marker_key:
		return
	_marker_key = key
	for sp in _sprites:
		sp.queue_free()
	_sprites.clear()
	for m: Dictionary in list:
		var sp := Marker.new()
		var act := not bool(m.get("travel", false))
		sp.setup(String(m["kind"]), "", MARKER_R + (1.5 if act else 0.0), m)
		sp.visible = false
		_markers_root.add_child(sp)
		_sprites.append(sp)


func _place_markers(xf: Transform2D, c: Vector2) -> void:
	var r := MAP * 0.5
	for sp in _sprites:
		var wp: Vector3 = sp.data["position"]
		var lp := xf * Vector2(wp.x, wp.z)
		var d := lp.distance_to(c)
		if d < r - 12.0:
			sp.visible = true
			sp.position = lp
			sp.modulate.a = clampf((r - 12.0 - d) / 18.0, 0.0, 1.0)
		elif sp.visible:
			sp.visible = false
	_pin.visible = Game.waypoint != Vector3.INF
	if _pin.visible:
		var wl := xf * Vector2(Game.waypoint.x, Game.waypoint.z)
		var dv := wl - c
		if dv.length() > r - 14.0:
			_pin.position = c + dv.normalized() * (r - 14.0) + Vector2(0, 8)
			_pin.scale = Vector2.ONE
		else:
			_pin.position = wl
			_pin.scale = Vector2(1.25, 1.25)
	_north.position = c + Vector2(0, -1).rotated(-_heading) * (r + 1.0)
	var txt := Style.distance_text(float(gps.remaining_m)) if (gps != null and gps.active) else ""
	if txt != _chip_text:
		_chip_text = txt
		_chip.queue_redraw()


func _update_labels(pos: Vector3) -> void:
	if Game.world is World:
		var w := Game.world as World
		# Keep the current road through junction mouths while the car is still on it (nearest() alone flips to
		# the side road there).
		if _road_now != null:
			var cur := w.data.network.nearest(pos, 24.0, func(r: RoadNetwork.Road) -> bool: return r == _road_now)
			if not cur.is_empty() and absf(float(cur["lateral"])) <= _road_now.width * 0.5 + _road_now.shoulder:
				_set_labels(w.region_at(pos).to_upper(), _road_now.name)
				return
		var res := w.data.network.nearest(pos, 24.0)
		_road_now = res["road"] if not res.is_empty() else null
		_set_labels(w.region_at(pos).to_upper(), _road_now.name if _road_now != null else "Off road")


## Sets the two names and sizes the plate so both fit inside it with PLATE_PAD on each side (clear of
## the rounded corners), e.g. "IRONCREST HIGHLANDS" at 20 px / spacing 3 is ~273 px wide.
func _set_labels(region: String, road: String) -> void:
	if region == _region_label.text and road == _road_label.text:
		return
	_region_label.text = region
	_road_label.text = road
	var tw := maxf(Style.text_width(region, 20, 700, false, 3), Style.text_width(road, 16, 500))
	var pw := clampf(tw + PLATE_PAD * 2.0, PLATE_MIN_W, _region_label.size.x)
	if not is_equal_approx(pw, _plate_w):
		_plate_w = pw
		_ring.queue_redraw()


func _draw_roads() -> void:
	var h := MapData.HALF
	MapData.draw_roads(_roads, Transform2D(0.0, Vector2(LEVEL, LEVEL), 0.0, Vector2.ZERO), Rect2(-h, -h, h * 2.0, h * 2.0), 0.9)


func _draw_route() -> void:
	if gps == null or not gps.active:
		return
	var pts: PackedVector2Array = gps.points_2d
	pts = pts.slice(clampi(int(gps.progress) >> 1, 0, maxi(pts.size() - 2, 0)))
	if pts.size() < 2:
		return
	var lxf := Transform2D(0.0, Vector2(LEVEL, LEVEL), 0.0, Vector2.ZERO)
	var local := lxf * pts
	_route.draw_polyline(local, Color(0.05, 0.02, 0.06, 0.7), 8.0, true)
	_route.draw_polyline(local, Style.ROUTE, 4.6, true)
	var dest: Vector3 = gps.destination
	var re: Vector3 = gps.road_end()
	if dest != Vector3.INF and re != Vector3.INF:
		_route.draw_dashed_line(lxf * Vector2(re.x, re.z), lxf * Vector2(dest.x, dest.z), Style.ROUTE, 3.0, 8.0, true, true)


func _draw_ring() -> void:
	var c := Vector2(PAD + MAP * 0.5, PAD + MAP * 0.5)
	var r := MAP * 0.5
	# Backing band for the region / road labels (readable over bright terrain).
	Style.draw_round_rect(_ring, Rect2(Vector2(c.x - _plate_w * 0.5, MAP + PAD * 2.0 + 4.0), Vector2(_plate_w, 58.0)), Style.BG, 14)
	_ring.draw_arc(c, r + 2.0, 0.0, TAU, 96, Color(0.03, 0.03, 0.05, 0.75), 7.0, true)
	var ring := PackedVector2Array()
	var cols := PackedColorArray()
	for i in 97:
		var a := TAU * i / 96.0 - PI * 0.5
		ring.append(c + Vector2(cos(a), sin(a)) * (r + 1.5))
		cols.append(Style.accent_at(0.5 + 0.5 * sin(a - PI * 0.25)))
	_ring.draw_polyline_colors(ring, cols, 3.0, true)
	Icons.draw_player_arrow(_ring, c, 0.0, 12.0)


func _draw_chip() -> void:
	if _chip_text == "":
		return
	var c := Vector2(PAD + MAP * 0.5, PAD + MAP * 0.5)
	var tw := Style.text_width(_chip_text, 17, 700) + 30.0
	var chip := Rect2(Vector2(c.x - tw * 0.5, PAD + MAP - 16.0), Vector2(tw, 28))
	Style.draw_round_rect(_chip, chip, Color(0.05, 0.05, 0.09, 0.92), 14, 2, Style.ROUTE)
	_chip.draw_circle(chip.position + Vector2(13, 14), 4.0, Style.ROUTE, true, -1.0, true)
	Style.draw_text(_chip, _chip_text, chip.position + Vector2(20, 20), 17, Style.TEXT, HORIZONTAL_ALIGNMENT_CENTER, tw - 26.0, 700, false, 0, 0.0)
