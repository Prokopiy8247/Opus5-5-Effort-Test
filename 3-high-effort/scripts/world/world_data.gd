class_name WorldData
extends RefCounted
## Runtime access to the baked world: heights, surfaces, roads, places, and
## spatial queries (nearest road, region).

const RES_DIR := "res://data/world/"
## Baked data lives in res:// while developing; an exported build reads data/world/ next to the exe.
var DIR := RES_DIR
const HOLE := 255
const ROAD_CELL := 64.0

class Road:
	var id := ""
	var name := ""
	var cls := ""
	var closed := false
	var width := 8.0
	var lanes := 2
	var speed := 90.0
	var surface := 0
	var shoulder := 1.0
	var markings := true
	var length := 0.0
	var pts := PackedVector3Array()
	var flags := PackedByteArray()
	var bank := PackedFloat32Array()
	var junctions: Array = []
	var index := 0

	func tangent(i: int) -> Vector3:
		var n := pts.size()
		var a := pts[maxi(i - 1, 0)] if not closed else pts[posmod(i - 1, n)]
		var b := pts[mini(i + 1, n - 1)] if not closed else pts[posmod(i + 1, n)]
		var t := b - a
		t.y = 0.0
		return t.normalized()

	func is_dirt() -> bool:
		return surface != 0

var n := 2049
var cell := 2.0
var origin := -2048.0
var heights := PackedFloat32Array()
var surfaces := PackedByteArray()
var roads: Array[Road] = []
var river := PackedVector3Array()
var places: Array = []
var region_names: Array = []
var biome_img: Image
var splat_tex: Texture2D
var biome_tex: Texture2D
var road_dist := PackedByteArray()
var _road_grid := {}  # Vector2i -> PackedInt32Array of (road_index << 16 | seg_index)


func load_all() -> bool:
	if not FileAccess.file_exists(DIR + "height.bin"):
		var beside := OS.get_executable_path().get_base_dir().path_join("data/world/")
		if FileAccess.file_exists(beside + "height.bin"):
			DIR = beside
	var fa := FileAccess.open(DIR + "height.bin", FileAccess.READ)
	if fa == null:
		push_error("World data missing: run tools/bake_world.gd")
		return false
	heights = fa.get_buffer(fa.get_length()).to_float32_array()
	fa = FileAccess.open(DIR + "surface.bin", FileAccess.READ)
	surfaces = fa.get_buffer(fa.get_length())
	if FileAccess.file_exists(DIR + "roaddist.bin"):
		road_dist = FileAccess.get_file_as_bytes(DIR + "roaddist.bin")
	var js: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(DIR + "world.json"))
	n = int(js.n)
	cell = float(js.cell)
	origin = float(js.origin)
	region_names = js.regions
	places = js.places
	for p in js.river:
		river.append(Vector3(p[0], p[1], p[2]))
	var ri := 0
	for r in js.roads:
		var road := Road.new()
		road.id = r.id
		road.name = r.name
		road.cls = r["class"]
		road.closed = r.closed
		road.width = r.width
		road.lanes = int(r.lanes)
		road.speed = r.speed
		road.surface = int(r.surface)
		road.shoulder = r.shoulder
		road.markings = r.markings
		road.length = r.length
		road.junctions = r.junctions
		road.index = ri
		for p in r.points:
			road.pts.append(Vector3(p[0], p[1], p[2]))
		for f in r.flags:
			road.flags.append(int(f))
		for b in r.bank:
			road.bank.append(float(b))
		roads.append(road)
		ri += 1
	_build_road_grid()
	var splat_img := Image.new()
	splat_img.load_png_from_buffer(FileAccess.get_file_as_bytes(DIR + "splat.png"))
	splat_img.generate_mipmaps()
	splat_tex = ImageTexture.create_from_image(splat_img)
	biome_img = Image.new()
	biome_img.load_png_from_buffer(FileAccess.get_file_as_bytes(DIR + "biome.png"))
	var bi := biome_img.duplicate() as Image
	bi.generate_mipmaps()
	biome_tex = ImageTexture.create_from_image(bi)
	return true


# ------------------------------------------------------------------ terrain queries
func height_at(x: float, z: float) -> float:
	var fx := clampf((x - origin) / cell, 0.0, n - 1.001)
	var fz := clampf((z - origin) / cell, 0.0, n - 1.001)
	var ix := int(fx)
	var iz := int(fz)
	var tx := fx - ix
	var tz := fz - iz
	var i := iz * n + ix
	# split along the same diagonal as the terrain mesh triangles
	var h00 := heights[i]
	var h10 := heights[i + 1]
	var h01 := heights[i + n]
	var h11 := heights[i + n + 1]
	if tx + tz <= 1.0:
		return h00 + (h10 - h00) * tx + (h01 - h00) * tz
	return h11 + (h01 - h11) * (1.0 - tx) + (h10 - h11) * (1.0 - tz)


## Approximate distance (m) to the nearest road edge or river bank (4 m grid).
func road_distance(x: float, z: float) -> float:
	if road_dist.is_empty():
		return 255.0
	var ix := clampi(int(round((x - origin) / 4.0)), 0, 1024)
	var iz := clampi(int(round((z - origin) / 4.0)), 0, 1024)
	return float(road_dist[iz * 1025 + ix])


func normal_at(x: float, z: float) -> Vector3:
	var e := cell
	var hx := height_at(x + e, z) - height_at(x - e, z)
	var hz := height_at(x, z + e) - height_at(x, z - e)
	return Vector3(-hx, 2.0 * e, -hz).normalized()


func surface_at(x: float, z: float) -> int:
	var ix := clampi(int(round((x - origin) / cell)), 0, n - 1)
	var iz := clampi(int(round((z - origin) / cell)), 0, n - 1)
	var s := surfaces[iz * n + ix]
	return Game.Surf.ROCK if s == HOLE else s


func is_hole(ix: int, iz: int) -> bool:
	return surfaces[iz * n + ix] == HOLE


## Region weights (valley, highlands, mesa, coast) from the baked biome map.
func region_weights(x: float, z: float) -> Color:
	var w := biome_img.get_width()
	var px := clampi(int((x - origin) / (n - 1) / cell * w), 0, w - 1)
	var pz := clampi(int((z - origin) / (n - 1) / cell * w), 0, w - 1)
	return biome_img.get_pixel(px, pz)


func region_at(x: float, z: float) -> int:
	var c := region_weights(x, z)
	var best := 0
	var vals := [c.r, c.g, c.b, c.a]
	for i in 4:
		if vals[i] > vals[best]:
			best = i
	return best


func region_name(x: float, z: float) -> String:
	return region_names[region_at(x, z)]


# ------------------------------------------------------------------ road queries
func _build_road_grid() -> void:
	_road_grid.clear()
	for road in roads:
		var cnt := road.pts.size() - 1
		for i in cnt:
			var a := road.pts[i]
			var b := road.pts[i + 1]
			var minc := Vector2i(floori(minf(a.x, b.x) / ROAD_CELL), floori(minf(a.z, b.z) / ROAD_CELL))
			var maxc := Vector2i(floori(maxf(a.x, b.x) / ROAD_CELL), floori(maxf(a.z, b.z) / ROAD_CELL))
			for cx in range(minc.x, maxc.x + 1):
				for cz in range(minc.y, maxc.y + 1):
					var key := Vector2i(cx, cz)
					var arr: PackedInt32Array = _road_grid.get(key, PackedInt32Array())
					arr.append((road.index << 16) | i)
					_road_grid[key] = arr


## Returns {road, seg, t, point, dist, tangent} for the closest road segment, or {} if none
## within max_dist.
func nearest_road(p: Vector3, max_dist: float = 200.0, filter_dirt: bool = false) -> Dictionary:
	var best := {}
	var bd := max_dist * max_dist
	var r := int(ceil(max_dist / ROAD_CELL))
	var c := Vector2i(floori(p.x / ROAD_CELL), floori(p.z / ROAD_CELL))
	var p2 := Vector2(p.x, p.z)
	for dx in range(-r, r + 1):
		for dz in range(-r, r + 1):
			var key := Vector2i(c.x + dx, c.y + dz)
			if not _road_grid.has(key):
				continue
			for code: int in _road_grid[key]:
				var road := roads[code >> 16]
				if filter_dirt and road.is_dirt():
					continue
				var i := code & 0xFFFF
				var a := road.pts[i]
				var b := road.pts[i + 1]
				var a2 := Vector2(a.x, a.z)
				var ab := Vector2(b.x, b.z) - a2
				var t := clampf((p2 - a2).dot(ab) / maxf(ab.length_squared(), 1e-6), 0.0, 1.0)
				var q := a2 + ab * t
				var d := q.distance_squared_to(p2)
				if d < bd:
					bd = d
					best = {"road": road, "seg": i, "t": t, "point": a.lerp(b, t), "dist": sqrt(d),
						"tangent": Vector3(ab.x, 0.0, ab.y).normalized()}
	return best


func road_by_id(id: String) -> Road:
	for r in roads:
		if r.id == id:
			return r
	return null


func place_by_id(id: String) -> Dictionary:
	for p in places:
		if p.id == id:
			return p
	return {}


## Spawn transform on a road at sample index, facing along the road, in the right lane.
func road_spawn(road: Road, i: int, lane_offset: float = 2.0) -> Transform3D:
	i = clampi(i, 0, road.pts.size() - 2)
	var p := road.pts[i]
	var t := road.tangent(i)
	var right := t.cross(Vector3.UP).normalized() * -1.0
	right = Vector3(-t.z, 0.0, t.x)
	var pos := p + right * lane_offset + Vector3.UP * 0.6
	var basis := Basis.looking_at(t, Vector3.UP)
	return Transform3D(basis, pos)
