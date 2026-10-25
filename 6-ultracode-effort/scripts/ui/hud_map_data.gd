extends RefCounted
## Shared map data for the minimap and the world map: the baked map texture, road polylines split into
## cull-friendly chunks, region label anchors and map markers (POIs + activities).

const MAP_PATH := "res://data/world/minimap.png"
const HALF := 2048.0
const CHUNK_POINTS := 40
const DETAIL_STEP := 2
const COARSE_STEP := 6
## Per road class: [casing width px, fill width px, fill colour] at "1.0" map scale.
const ROAD_STYLE := {
	0: [7.0, 4.6, Color(1.0, 0.78, 0.36)],
	1: [5.6, 3.4, Color(0.97, 0.96, 0.93)],
	2: [5.6, 3.4, Color(0.97, 0.96, 0.93)],
	3: [4.8, 2.8, Color(0.9, 0.9, 0.9)],
	4: [4.0, 2.0, Color(0.86, 0.68, 0.5)],
	5: [4.0, 2.0, Color(0.83, 0.78, 0.68)],
	6: [4.0, 2.0, Color(0.95, 0.86, 0.64)],
}

static var _tex: Texture2D
static var _chunks: Dictionary = {}
static var _chunk_net: RoadNetwork


static func map_texture() -> Texture2D:
	if _tex == null and FileAccess.file_exists(MAP_PATH):
		var img := Image.new()
		if img.load_png_from_buffer(FileAccess.get_file_as_bytes(MAP_PATH)) == OK:
			img.generate_mipmaps()
			_tex = ImageTexture.create_from_image(img)
	return _tex


static func network() -> RoadNetwork:
	if Game.world is World:
		var w := Game.world as World
		if w.data != null:
			return w.data.network
	return null


## Road polylines in world XZ, chunked: [{cls, paved, pts: PackedVector2Array, rect: Rect2}], drawn
## unpaved first so paved roads sit on top. step = road samples (3 m) per polyline point.
static func road_chunks(step := DETAIL_STEP) -> Array:
	var net := network()
	if net == null:
		return []
	if _chunk_net != net:
		_chunk_net = net
		_chunks = {}
	if _chunks.has(step):
		return _chunks[step]
	var out: Array = []
	_chunks[step] = out
	var paved: Array = []
	var unpaved: Array = []
	for r in net.roads:
		var n := r.pos.size()
		if n < 2:
			continue
		var idx: Array[int] = []
		var i := 0
		while i < n:
			idx.append(i)
			i += step
		if idx[idx.size() - 1] != n - 1:
			idx.append(n - 1)
		if r.loop:
			idx.append(0)
		var pts := PackedVector2Array()
		for k in idx:
			pts.append(Vector2(r.pos[k].x, r.pos[k].z))
			if pts.size() >= CHUNK_POINTS:
				(paved if r.cls <= 3 else unpaved).append(_chunk(r.cls, pts))
				pts = PackedVector2Array([pts[pts.size() - 1]])
		if pts.size() >= 2:
			(paved if r.cls <= 3 else unpaved).append(_chunk(r.cls, pts))
	# Highways last so they draw over the regional roads they cross.
	paved.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["cls"]) > int(b["cls"]))
	out.append_array(unpaved)
	out.append_array(paved)
	return out


static func _chunk(cls: int, pts: PackedVector2Array) -> Dictionary:
	var rect := Rect2(pts[0], Vector2.ZERO)
	for p in pts:
		rect = rect.expand(p)
	return {"cls": cls, "paved": cls <= 3, "pts": pts, "rect": rect.grow(12.0)}


## Draws the road network. xf maps world XZ to local pixels; view = visible world rect; width_scale
## scales the line widths (1.0 = minimap size).
static func draw_roads(ci: CanvasItem, xf: Transform2D, view: Rect2, width_scale: float, alpha := 1.0, step := DETAIL_STEP) -> void:
	var chunks := road_chunks(step)
	var visible: Array = []
	for ch: Dictionary in chunks:
		if (ch["rect"] as Rect2).intersects(view):
			visible.append(ch)
	var casing := Color(0.03, 0.03, 0.05, 0.55 * alpha)
	for ch: Dictionary in visible:
		var st: Array = ROAD_STYLE.get(int(ch["cls"]), ROAD_STYLE[1])
		ci.draw_polyline(xf * (ch["pts"] as PackedVector2Array), casing, float(st[0]) * width_scale, false)
	for ch: Dictionary in visible:
		var st2: Array = ROAD_STYLE.get(int(ch["cls"]), ROAD_STYLE[1])
		var col: Color = st2[2]
		col.a *= alpha
		ci.draw_polyline(xf * (ch["pts"] as PackedVector2Array), col, float(st2[1]) * width_scale, true)


## Label anchors per region: mean of its POI positions (world XZ).
static func region_centers() -> Array[Vector2]:
	var sums: Array[Vector2] = []
	var counts: Array[int] = []
	for i in WorldLayout.REGIONS.size():
		sums.append(Vector2.ZERO)
		counts.append(0)
	for p: Dictionary in WorldLayout.POIS:
		var r := int(p["region"])
		if r >= 0 and r < sums.size():
			sums[r] += Vector2(float(p["pos"][0]), float(p["pos"][1]))
			counts[r] += 1
	var out: Array[Vector2] = []
	for i in sums.size():
		out.append(sums[i] / maxf(counts[i], 1))
	return out


## Teleport targets worth showing on a map (POIs; region aliases and duplicate names skipped).
static func poi_markers() -> Array:
	var out: Array = []
	var seen := {}
	for t: Dictionary in Game.get_teleport_targets():
		var kind := String(t.get("kind", ""))
		var nm := String(t.get("name", ""))
		if kind == "region" or seen.has(nm):
			continue
		seen[nm] = true
		out.append({"name": nm, "kind": kind, "position": t["position"], "region": String(t.get("region", "")), "travel": true})
	return out


## Activity markers from the activity manager, if it is present.
static func activity_markers() -> Array:
	var out: Array = []
	var am: Node = Game.activities
	if am == null or not is_instance_valid(am) or not am.has_method("get_map_markers"):
		return out
	var list: Variant = am.call("get_map_markers")
	if list is Array:
		for m: Variant in list:
			if m is Dictionary and (m as Dictionary).has("position"):
				var d: Dictionary = (m as Dictionary).duplicate()
				d["kind"] = String(d.get("kind", "activity"))
				d["name"] = String(d.get("name", d["kind"]))
				d["travel"] = false
				out.append(d)
	return out
