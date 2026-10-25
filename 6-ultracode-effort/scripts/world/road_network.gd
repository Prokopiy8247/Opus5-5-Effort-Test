class_name RoadNetwork
extends RefCounted
## Runtime road data (from data/world/roads.json): per-road sampled centrelines with height, banking
## and bridge/tunnel flags, junctions, and a spatial hash for nearest-road queries.
## Used by the road mesh builder, traffic lane graph, minimap/GPS, activities and respawn.

const HASH_CELL := 48.0

class Road:
	var idx: int
	var id: String
	var name: String
	var cls: int
	var loop: bool
	var width: float
	var lanes: int
	var shoulder: float
	var limit: float
	var surface: StringName
	var traffic: bool
	var marking: int
	var pos: PackedVector3Array
	var bank: PackedFloat32Array
	var flags: PackedByteArray
	var length: float
	var ds: float
	var j_start: Dictionary
	var j_end: Dictionary

	func count() -> int:
		return pos.size()

	## Continuous sample index for arclength s (wrapped for loops, clamped otherwise).
	func _fi(s: float) -> float:
		var n := pos.size()
		var f := s / ds
		if loop:
			return fposmod(f, float(n))
		return clampf(f, 0.0, float(n - 1) - 0.0001)

	func point_at(s: float) -> Vector3:
		var f := _fi(s)
		var i := int(f)
		var j := (i + 1) % pos.size() if loop else mini(i + 1, pos.size() - 1)
		return pos[i].lerp(pos[j], f - i)

	func bank_at(s: float) -> float:
		var f := _fi(s)
		var i := int(f)
		var j := (i + 1) % pos.size() if loop else mini(i + 1, pos.size() - 1)
		return lerpf(bank[i], bank[j], f - i)

	func tangent_at(s: float) -> Vector3:
		var a := point_at(s - ds)
		var b := point_at(s + ds)
		var t := b - a
		return t.normalized() if t.length() > 0.001 else Vector3.FORWARD

	func flat_tangent_at(s: float) -> Vector3:
		var t := tangent_at(s)
		t.y = 0.0
		return t.normalized()

	## Horizontal right vector (perpendicular to the travel direction).
	func right_at(s: float) -> Vector3:
		var t := flat_tangent_at(s)
		return Vector3(-t.z, 0.0, t.x)

	## Point on the road surface at lateral offset (m, + = right of travel direction), including banking.
	func surface_point(s: float, offset: float) -> Vector3:
		var p := point_at(s)
		var r := right_at(s)
		return p + r * offset + Vector3.UP * (offset * bank_at(s))

	func flag_at(s: float) -> int:
		return flags[int(round(_fi(s))) % flags.size()]

	## Lateral offset of the centre of a lane. lane >= 1: right side (forward), lane <= -1: left side.
	func lane_offset(lane: int) -> float:
		var lw := (width - 0.6) / float(lanes * 2)
		var k := absi(lane)
		var o := lw * (float(k) - 0.5)
		return o if lane > 0 else -o


var roads: Array[Road] = []
var junctions: Array = []
var ds: float = 3.0
var _hash: Dictionary = {}


func load_json(path: String) -> bool:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return false
	var d: Dictionary = JSON.parse_string(f.get_as_text())
	ds = float(d.get("ds", 3.0))
	roads.clear()
	for rd: Dictionary in d["roads"]:
		var r := Road.new()
		r.idx = roads.size()
		r.id = rd["id"]
		r.name = rd["name"]
		r.cls = int(rd["class"])
		r.loop = bool(rd["loop"])
		r.width = float(rd["width"])
		r.lanes = int(rd["lanes"])
		r.shoulder = float(rd["shoulder"])
		r.limit = float(rd["limit"])
		r.surface = StringName(rd["surface"])
		r.traffic = bool(rd["traffic"])
		r.marking = int(rd["marking"])
		r.ds = ds
		var flat: Array = rd["pos"]
		var pos := PackedVector3Array()
		pos.resize(flat.size() / 3)
		for i in pos.size():
			pos[i] = Vector3(flat[i * 3], flat[i * 3 + 1], flat[i * 3 + 2])
		r.pos = pos
		r.bank = PackedFloat32Array(rd["bank"])
		r.flags = PackedByteArray(rd["flags"])
		r.length = float(rd["length"])
		r.j_start = rd.get("j_start", {})
		r.j_end = rd.get("j_end", {})
		roads.append(r)
	junctions = d.get("junctions", [])
	_build_hash()
	return true


func get_road(id: String) -> Road:
	for r in roads:
		if r.id == id:
			return r
	return null


func total_length() -> float:
	var t := 0.0
	for r in roads:
		t += r.length
	return t


func _key(x: float, z: float) -> Vector2i:
	return Vector2i(floori(x / HASH_CELL), floori(z / HASH_CELL))


func _build_hash() -> void:
	_hash.clear()
	for r in roads:
		for i in r.pos.size():
			var k := _key(r.pos[i].x, r.pos[i].z)
			if not _hash.has(k):
				_hash[k] = PackedInt32Array()
			var arr: PackedInt32Array = _hash[k]
			arr.append(r.idx << 16 | i)
			_hash[k] = arr


## Nearest road sample to `p` (XZ distance). Returns {} if nothing within max_dist.
## Result: {road: Road, index, s, position (centre), forward, distance, lateral}
func nearest(p: Vector3, max_dist := 200.0, filter := Callable()) -> Dictionary:
	var best := INF
	var best_r := -1
	var best_i := -1
	var rad := int(ceil(max_dist / HASH_CELL))
	var c := _key(p.x, p.z)
	for dz in range(-rad, rad + 1):
		for dx in range(-rad, rad + 1):
			var arr: Variant = _hash.get(c + Vector2i(dx, dz))
			if arr == null:
				continue
			for v: int in arr:
				var ri := v >> 16
				var si := v & 0xFFFF
				var q := roads[ri].pos[si]
				var d := (q.x - p.x) * (q.x - p.x) + (q.z - p.z) * (q.z - p.z)
				if d < best:
					if filter.is_valid() and not filter.call(roads[ri]):
						continue
					best = d
					best_r = ri
					best_i = si
	if best_r < 0 or sqrt(best) > max_dist:
		return {}
	var r := roads[best_r]
	var s := best_i * r.ds
	var fwd := r.flat_tangent_at(s)
	var rt := Vector3(-fwd.z, 0, fwd.x)
	var center := r.point_at(s)
	return {"road": r, "index": best_i, "s": s, "position": center, "forward": fwd, "distance": sqrt(best), "lateral": (p - center).dot(rt)}


## Horizontal distance from p to the nearest paved edge (incl. shoulder) of ANY road within `radius`, measured
## to the centreline segments; negative when p lies on a road surface. INF when no road is that close.
func edge_clearance(p: Vector3, radius := 40.0) -> float:
	var best := INF
	var q := Vector2(p.x, p.z)
	var rad := int(ceil(radius / HASH_CELL))
	var c := _key(p.x, p.z)
	for dz in range(-rad, rad + 1):
		for dx in range(-rad, rad + 1):
			var arr: Variant = _hash.get(c + Vector2i(dx, dz))
			if arr == null:
				continue
			for v: int in arr:
				var r := roads[v >> 16]
				var i := v & 0xFFFF
				var n := r.pos.size()
				for k: int in [i - 1, i]:
					if not r.loop and (k < 0 or k >= n - 1):
						continue
					var a := Vector2(r.pos[posmod(k, n)].x, r.pos[posmod(k, n)].z)
					var b := Vector2(r.pos[posmod(k + 1, n)].x, r.pos[posmod(k + 1, n)].z)
					var ab := b - a
					var t := clampf((q - a).dot(ab) / maxf(ab.length_squared(), 1e-6), 0.0, 1.0)
					best = minf(best, q.distance_to(a + ab * t) - (r.width * 0.5 + r.shoulder))
	return best
