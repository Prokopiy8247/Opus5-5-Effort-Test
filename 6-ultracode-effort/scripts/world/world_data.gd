class_name WorldData
extends RefCounted
## Runtime access to the baked world (data/world/*): heights, surfaces, regions, road distance, holes,
## POIs, lakes and the road network. All lookups are thread-safe reads after load().

const DIR := "res://data/world/"

var n: int = 2049
var cell: float = 2.0
var half: float = 2048.0
var heights := PackedFloat32Array()
var surface := PackedByteArray()
var road_dist := PackedByteArray()
var regions := PackedByteArray()
var map_n: int = 1025
var reg_n: int = 513
var holes: Dictionary = {}
var meta: Dictionary = {}
var network := RoadNetwork.new()
var gen: WorldGen          # for the natural height function (far terrain)


func load_all() -> bool:
	var t0 := Time.get_ticks_msec()
	var f := FileAccess.open_compressed(DIR + "heights.bin", FileAccess.READ, FileAccess.COMPRESSION_ZSTD)
	if f == null:
		push_error("WorldData: missing %sheights.bin - run tools/bake_world.gd" % DIR)
		return false
	n = f.get_32()
	var buf := f.get_buffer(n * n * 2)
	f.close()
	heights.resize(n * n)
	for i in n * n:
		heights[i] = buf.decode_u16(i * 2) * 0.01 - 100.0
	var s_img := _png(DIR + "surface.png")
	s_img.convert(Image.FORMAT_L8)
	surface = s_img.get_data()
	map_n = s_img.get_width()
	var r_img := _png(DIR + "road_dist.png")
	r_img.convert(Image.FORMAT_L8)
	road_dist = r_img.get_data()
	var g_img := _png(DIR + "regions.png")
	g_img.convert(Image.FORMAT_RGBA8)
	regions = g_img.get_data()
	reg_n = g_img.get_width()
	var mf := FileAccess.open(DIR + "world_meta.json", FileAccess.READ)
	meta = JSON.parse_string(mf.get_as_text())
	half = float(meta.get("half", 2048.0))
	cell = float(meta.get("cell", 2.0))
	for k in meta.get("holes", []):
		holes[int(k)] = true
	network.load_json(DIR + "roads.json")
	gen = WorldGen.new()
	print("[world] data loaded in %d ms (%d roads, %.1f km)" % [Time.get_ticks_msec() - t0, network.roads.size(), network.total_length() / 1000.0])
	return true


static func _png(path: String) -> Image:
	# Raw PNG bytes (the data/world PNGs use the "keep" importer: exported as-is, never imported as textures).
	var img := Image.new()
	img.load_png_from_buffer(FileAccess.get_file_as_bytes(path))
	return img


func in_bounds(x: float, z: float) -> bool:
	return absf(x) < half and absf(z) < half


func height_at(x: float, z: float) -> float:
	if not in_bounds(x, z):
		return gen.natural_height(x, z)
	var fx := clampf((x + half) / cell, 0.0, n - 1.001)
	var fz := clampf((z + half) / cell, 0.0, n - 1.001)
	var i := int(fx)
	var j := int(fz)
	var tx := fx - i
	var tz := fz - j
	var a := heights[j * n + i]
	var b := heights[j * n + i + 1]
	var c := heights[(j + 1) * n + i]
	var d := heights[(j + 1) * n + i + 1]
	return lerpf(lerpf(a, b, tx), lerpf(c, d, tx), tz)


## Height at an integer grid vertex (clamped).
func grid_height(i: int, j: int) -> float:
	return heights[clampi(j, 0, n - 1) * n + clampi(i, 0, n - 1)]


func normal_at(x: float, z: float) -> Vector3:
	var e := cell
	var hl := height_at(x - e, z)
	var hr := height_at(x + e, z)
	var hd := height_at(x, z - e)
	var hu := height_at(x, z + e)
	return Vector3(hl - hr, 2.0 * e, hd - hu).normalized()


func surface_index_at(x: float, z: float) -> int:
	var i := clampi(int(round((x + half) / 4.0)), 0, map_n - 1)
	var j := clampi(int(round((z + half) / 4.0)), 0, map_n - 1)
	return surface[j * map_n + i]


func road_distance_at(x: float, z: float) -> float:
	var i := clampi(int(round((x + half) / 4.0)), 0, map_n - 1)
	var j := clampi(int(round((z + half) / 4.0)), 0, map_n - 1)
	return float(road_dist[j * map_n + i])


func region_weights_at(x: float, z: float) -> Color:
	var fx := clampf((x + half) / 8.0, 0.0, reg_n - 1.001)
	var fz := clampf((z + half) / 8.0, 0.0, reg_n - 1.001)
	var i := int(fx)
	var j := int(fz)
	var tx := fx - i
	var tz := fz - j
	var c := Color()
	for k in 4:
		var a := regions[(j * reg_n + i) * 4 + k]
		var b := regions[(j * reg_n + i + 1) * 4 + k]
		var cc := regions[((j + 1) * reg_n + i) * 4 + k]
		var d := regions[((j + 1) * reg_n + i + 1) * 4 + k]
		c[k] = lerpf(lerpf(a, b, tx), lerpf(cc, d, tx), tz) / 255.0
	return c


func region_at(x: float, z: float) -> int:
	var c := region_weights_at(x, z)
	var best := 0
	for k in range(1, 4):
		if c[k] > c[best]:
			best = k
	return best


func region_name(id: int) -> String:
	return WorldLayout.REGIONS[clampi(id, 0, WorldLayout.REGIONS.size() - 1)]["name"]


func is_hole(i: int, j: int) -> bool:
	return holes.has(j * n + i)


func lake_list() -> Array:
	return meta.get("lakes", [])


func pois() -> Array:
	return meta.get("pois", [])
