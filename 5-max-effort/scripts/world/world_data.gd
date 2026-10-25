class_name WorldData
extends RefCounted
## Read-only access to the baked world: heights, holes, splat masks, regions, water, roads.
## Thread-safe for reads after load_data() (used by chunk-building worker threads).

const F_BRIDGE := 1
const F_TUNNEL := 2
const F_RAIL_L := 4
const F_RAIL_R := 8
const F_JUNCTION := 16
const F_VILLAGE := 32
const DIR := "res://data/world/"
const REGION_NAMES := ["Saltwind Coast", "Meadowbrook Vale", "Granite Crown Highlands", "Ochre Mesa Canyonlands"]
const HASH_CELL := 32.0

var half: float = 2000.0
var res: float = 2.0
var n: int = 2001
var heights := PackedFloat32Array()
var holes := PackedByteArray()
var splat: Image
var splat_size: int = 1024
var regions: Image
var roads: Array = []
var meta: Dictionary = {}
var snow_line: float = 430.0
var lake_center := Vector2(-900, -350)
var lake_radii := Vector2(270, 220)
var lake_level: float = 34.0
var river: Array = []
var _splat_data := PackedByteArray()
var _region_data := PackedByteArray()
var _road_hash: Dictionary = {}
var _river_hash: Dictionary = {}


func load_data() -> bool:
	if not FileAccess.file_exists(DIR + "world_meta.json"):
		return false
	var f := FileAccess.open(DIR + "world_meta.json", FileAccess.READ)
	meta = JSON.parse_string(f.get_as_text())
	f.close()
	half = float(meta["half"])
	res = float(meta["res"])
	n = int(meta["n"])
	snow_line = float(meta.get("snow_line", 430.0))
	var lk: Dictionary = meta["lake"]
	lake_center = Vector2(lk["center"][0], lk["center"][1])
	lake_radii = Vector2(lk["radii"][0], lk["radii"][1])
	lake_level = float(lk["level"])
	river = meta.get("river", [])
	f = FileAccess.open_compressed(DIR + "height.bin", FileAccess.READ, FileAccess.COMPRESSION_ZSTD)
	heights = f.get_buffer(n * n * 4).to_float32_array()
	f.close()
	f = FileAccess.open_compressed(DIR + "holes.bin", FileAccess.READ, FileAccess.COMPRESSION_ZSTD)
	holes = f.get_buffer(n * n)
	f.close()
	_splat_data = _load_bin(DIR + "splat.bin", splat_size * splat_size * 4)
	if not _splat_data.is_empty():
		splat = Image.create_from_data(splat_size, splat_size, false, Image.FORMAT_RGBA8, _splat_data)
	_region_data = _load_bin(DIR + "regions.bin", 256 * 256)
	if not _region_data.is_empty():
		regions = Image.create_from_data(256, 256, false, Image.FORMAT_L8, _region_data)
	f = FileAccess.open(DIR + "roads.json", FileAccess.READ)
	var rj: Dictionary = JSON.parse_string(f.get_as_text())
	f.close()
	for r in rj["roads"]:
		var rr: Dictionary = r
		rr["x"] = PackedFloat32Array(r["x"])
		rr["y"] = PackedFloat32Array(r["y"])
		rr["z"] = PackedFloat32Array(r["z"])
		rr["bank"] = PackedFloat32Array(r["bank"])
		rr["flags"] = PackedInt32Array(r["flags"])
		roads.append(rr)
	_build_hashes()
	return true


static func _load_bin(path: String, size: int) -> PackedByteArray:
	if not FileAccess.file_exists(path):
		return PackedByteArray()
	var f := FileAccess.open_compressed(path, FileAccess.READ, FileAccess.COMPRESSION_ZSTD)
	var b := f.get_buffer(size)
	f.close()
	return b


func road_mask_image() -> Image:
	var b := _load_bin(DIR + "roadmask.bin", 2048 * 2048)
	if b.is_empty():
		return null
	return Image.create_from_data(2048, 2048, false, Image.FORMAT_L8, b)


func _build_hashes() -> void:
	for ri in roads.size():
		var r: Dictionary = roads[ri]
		var xs: PackedFloat32Array = r["x"]
		var zs: PackedFloat32Array = r["z"]
		for i in xs.size():
			var key := Vector2i(int(floor(xs[i] / HASH_CELL)), int(floor(zs[i] / HASH_CELL)))
			var arr: PackedInt32Array = _road_hash.get(key, PackedInt32Array())
			arr.append(ri)
			arr.append(i)
			_road_hash[key] = arr
	for i in river.size():
		var p: Array = river[i]
		var key := Vector2i(int(floor(float(p[0]) / HASH_CELL)), int(floor(float(p[2]) / HASH_CELL)))
		var arr: PackedInt32Array = _river_hash.get(key, PackedInt32Array())
		arr.append(i)
		_river_hash[key] = arr


# ------------------------------------------------------------------------------------------------
func height_at(x: float, z: float) -> float:
	var fx := clampf((x + half) / res, 0.0, float(n - 1) - 0.001)
	var fz := clampf((z + half) / res, 0.0, float(n - 1) - 0.001)
	var ix := int(fx)
	var iz := int(fz)
	var tx := fx - ix
	var tz := fz - iz
	var i := iz * n + ix
	return lerpf(lerpf(heights[i], heights[i + 1], tx), lerpf(heights[i + n], heights[i + n + 1], tx), tz)


func height_grid(ix: int, iz: int) -> float:
	return heights[clampi(iz, 0, n - 1) * n + clampi(ix, 0, n - 1)]


func is_hole(ix: int, iz: int) -> bool:
	if ix < 0 or iz < 0 or ix >= n or iz >= n:
		return false
	return holes[iz * n + ix] != 0


func normal_at(x: float, z: float) -> Vector3:
	var e := res
	var hl := height_at(x - e, z)
	var hr := height_at(x + e, z)
	var hd := height_at(x, z - e)
	var hu := height_at(x, z + e)
	return Vector3(hl - hr, 2.0 * e, hd - hu).normalized()


func splat_at(x: float, z: float) -> Color:
	if _splat_data.is_empty():
		return Color(0, 0, 0, 0)
	var fx := clampf((x + half) / (2.0 * half) * splat_size - 0.5, 0.0, splat_size - 1.001)
	var fz := clampf((z + half) / (2.0 * half) * splat_size - 0.5, 0.0, splat_size - 1.001)
	var ix := int(fx)
	var iz := int(fz)
	var tx := fx - ix
	var tz := fz - iz
	var c00 := _px(ix, iz)
	var c10 := _px(ix + 1, iz)
	var c01 := _px(ix, iz + 1)
	var c11 := _px(ix + 1, iz + 1)
	return c00.lerp(c10, tx).lerp(c01.lerp(c11, tx), tz)


func _px(ix: int, iz: int) -> Color:
	var o := (clampi(iz, 0, splat_size - 1) * splat_size + clampi(ix, 0, splat_size - 1)) * 4
	return Color(_splat_data[o] / 255.0, _splat_data[o + 1] / 255.0, _splat_data[o + 2] / 255.0, _splat_data[o + 3] / 255.0)


func region_index(x: float, z: float) -> int:
	if _region_data.is_empty():
		return 1
	var sz := regions.get_width()
	var ix := clampi(int((x + half) / (2.0 * half) * sz), 0, sz - 1)
	var iz := clampi(int((z + half) / (2.0 * half) * sz), 0, sz - 1)
	return clampi(_region_data[iz * sz + ix], 0, 3)


func region_at(x: float, z: float) -> String:
	return REGION_NAMES[region_index(x, z)]


func water_level_at(x: float, z: float) -> float:
	## -1000 when there is no water surface above the terrain here
	var h := height_at(x, z)
	if h < 0.0:
		return 0.0
	var lp := Vector2((x - lake_center.x) / lake_radii.x, (z - lake_center.y) / lake_radii.y)
	if lp.length() < 1.45 and h < lake_level:
		return lake_level
	var key := Vector2i(int(floor(x / HASH_CELL)), int(floor(z / HASH_CELL)))
	var best := -1000.0
	var bd := 1e9
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var arr: PackedInt32Array = _river_hash.get(key + Vector2i(dx, dz), PackedInt32Array())
			for i in arr:
				var p: Array = river[i]
				var d := Vector2(float(p[0]) - x, float(p[2]) - z).length()
				if d < float(p[3]) * 0.5 + 3.0 and d < bd:
					bd = d
					best = float(p[1])
	if best > -999.0 and h < best:
		return best
	return -1000.0


func surface_at(x: float, z: float) -> int:
	## terrain surface for tyres (roads carry their own collider metadata)
	var h := height_at(x, z)
	var nrm := normal_at(x, z)
	if h > snow_line + 25.0 and nrm.y > 0.75:
		return Surfaces.SNOW
	if nrm.y < 0.72:
		return Surfaces.ROCK
	var sp := splat_at(x, z)
	if sp.a > 0.5:
		return Surfaces.SAND
	if sp.g > 0.55:
		return Surfaces.SAND if sp.g > 0.8 and nrm.y > 0.97 else Surfaces.DIRT
	if sp.r > 0.5:
		return Surfaces.DIRT
	if region_index(x, z) == 2 and h > 260.0:
		return Surfaces.GRAVEL if nrm.y < 0.9 else Surfaces.GRASS
	return Surfaces.GRASS


# ------------------------------------------------------------------------------------------------
func nearest_road(x: float, z: float, max_cells: int = 8) -> Dictionary:
	## {"road": index, "i": sample index, "d": distance} or empty
	var cx := int(floor(x / HASH_CELL))
	var cz := int(floor(z / HASH_CELL))
	for rad in [1, 3, max_cells]:
		var best := {}
		var bd := 1e18
		for dz in range(-rad, rad + 1):
			for dx in range(-rad, rad + 1):
				var arr: PackedInt32Array = _road_hash.get(Vector2i(cx + dx, cz + dz), PackedInt32Array())
				for k in range(0, arr.size(), 2):
					var r: Dictionary = roads[arr[k]]
					var px: float = (r["x"] as PackedFloat32Array)[arr[k + 1]]
					var pz: float = (r["z"] as PackedFloat32Array)[arr[k + 1]]
					var d := (px - x) * (px - x) + (pz - z) * (pz - z)
					if d < bd:
						bd = d
						best = {"road": arr[k], "i": arr[k + 1], "d": sqrt(d)}
		if not best.is_empty():
			return best
	return {}


func road_point(ri: int, i: int) -> Vector3:
	var r: Dictionary = roads[ri]
	return Vector3((r["x"] as PackedFloat32Array)[i], (r["y"] as PackedFloat32Array)[i], (r["z"] as PackedFloat32Array)[i])


func road_dir(ri: int, i: int) -> Vector3:
	var r: Dictionary = roads[ri]
	var cnt: int = (r["x"] as PackedFloat32Array).size()
	var a := road_point(ri, maxi(i - 1, 0))
	var b := road_point(ri, mini(i + 1, cnt - 1))
	if r["closed"]:
		a = road_point(ri, posmod(i - 1, cnt))
		b = road_point(ri, posmod(i + 1, cnt))
	return (b - a).normalized()
