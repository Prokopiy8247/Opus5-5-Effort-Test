class_name WorldData
extends RefCounted
## Deterministic world description: regions, natural terrain, river/lake, the sampled road network,
## terrain carving along roads and surface lookup. Read-only after build(), so worker threads may query it.

enum Surface { ASPHALT, CONCRETE, DIRT, GRAVEL, GRASS, SAND, SNOW, ROCK }
const SURFACE_NAMES: PackedStringArray = ["asphalt", "concrete", "dirt", "gravel", "grass", "sand", "snow", "rock"]
enum Region { FARMLAND, MOUNTAINS, DESERT, COAST }
const REGION_NAMES: PackedStringArray = ["Greenvale Farmlands", "Granite Highlands", "Ochre Canyon", "Azure Coast"]

const HALF: float = 2000.0
const STEP: float = 4.0
const CELL: float = 32.0
const CELL_MARGIN: float = 64.0
const SEED: int = 51155

var n_low := FastNoiseLite.new()
var n_mid := FastNoiseLite.new()
var n_ridge := FastNoiseLite.new()
var n_mesa := FastNoiseLite.new()
var n_detail := FastNoiseLite.new()

const RIVER: PackedVector2Array = [Vector2(-650, -420), Vector2(-560, -100), Vector2(-540, 50), Vector2(-500, 300), Vector2(-150, 700), Vector2(-100, 1000), Vector2(0, 1300), Vector2(30, 1520), Vector2(50, 1750)]
const LAKE_C := Vector2(-650, -440)
const LAKE_R: float = 150.0

# --- roads ---------------------------------------------------------------
## Each road: {name, cls, surface(int), loop(bool), from, to, pts: PackedVector3Array (x,h,z),
##  right: PackedVector3Array, bank: PackedFloat32Array, flags: PackedByteArray (1 bridge, 2 tunnel),
##  dist: PackedFloat32Array, hw (road half width incl. lanes), lane, lanes, speed, length}
var roads: Array = []
var node_height: Dictionary = {}
var node_roads: Dictionary = {}  # node -> Array of [road_idx, at_start(bool)]
var grid: Dictionary = {}  # cell key -> PackedInt32Array of encoded (road<<16 | seg)
var total_length: float = 0.0
# coarse distance-to-road field (metres), used to shape valleys around roads and to keep dressing off roads
const DF_RES: float = 16.0
const DF_MIN: float = -2300.0
const DF_N: int = 288
var dfield := PackedFloat32Array()
var loop_length: float = 0.0


func _init() -> void:
	n_low.seed = SEED
	n_low.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n_low.frequency = 0.0012
	n_low.fractal_octaves = 3
	n_mid.seed = SEED + 1
	n_mid.frequency = 0.006
	n_mid.fractal_octaves = 3
	n_ridge.seed = SEED + 2
	n_ridge.frequency = 0.0014
	n_ridge.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	n_ridge.fractal_octaves = 4
	n_mesa.seed = SEED + 3
	n_mesa.frequency = 0.0026
	n_mesa.fractal_octaves = 2
	n_detail.seed = SEED + 4
	n_detail.frequency = 0.03
	n_detail.fractal_octaves = 2


static func smooth(a: float, b: float, x: float) -> float:
	var t: float = clampf((x - a) / (b - a), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


func shore_z(x: float) -> float:
	return 1600.0 + 60.0 * sin(x * 0.004) + 40.0 * sin(x * 0.011 + 1.0)


func shore_x(z: float) -> float:
	return -1800.0 + 50.0 * sin(z * 0.005) + 25.0 * sin(z * 0.017)


## Region weights (farm, mountain, desert, coast), sum = 1
func region_weights(x: float, z: float) -> Vector4:
	var m: float = smooth(-650.0, -1250.0, z + 60.0 * sin(x * 0.003))
	var d: float = smooth(500.0, 1000.0, x + 80.0 * sin(z * 0.004)) * (1.0 - m)
	var c_s: float = smooth(1150.0, 1450.0, z)
	var c_w: float = smooth(-1450.0, -1650.0, x)
	var c: float = maxf(c_s, c_w) * (1.0 - m) * (1.0 - d * 0.7)
	var f: float = maxf(0.0, 1.0 - m - d - c)
	var s: float = f + m + d + c
	return Vector4(f, m, d, c) / s


func region_at(x: float, z: float) -> int:
	var w: Vector4 = region_weights(x, z)
	var best: int = 0
	var bv: float = w.x
	for i in range(1, 4):
		if w[i] > bv:
			bv = w[i]
			best = i
	return best


func _dist_polyline(p: Vector2, line: PackedVector2Array) -> float:
	var best: float = 1e9
	for i in line.size() - 1:
		var a: Vector2 = line[i]
		var b: Vector2 = line[i + 1]
		var ab: Vector2 = b - a
		var t: float = clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
		best = minf(best, p.distance_to(a + ab * t))
	return best


func river_distance(x: float, z: float) -> float:
	return _dist_polyline(Vector2(x, z), RIVER)


func road_dist(x: float, z: float) -> float:
	if dfield.is_empty():
		return 10000.0
	var fx: float = (x - DF_MIN) / DF_RES - 0.5
	var fz: float = (z - DF_MIN) / DF_RES - 0.5
	var ix: int = clampi(int(floor(fx)), 0, DF_N - 2)
	var iz: int = clampi(int(floor(fz)), 0, DF_N - 2)
	var tx: float = clampf(fx - ix, 0.0, 1.0)
	var tz: float = clampf(fz - iz, 0.0, 1.0)
	var a: float = lerpf(dfield[iz * DF_N + ix], dfield[iz * DF_N + ix + 1], tx)
	var b: float = lerpf(dfield[(iz + 1) * DF_N + ix], dfield[(iz + 1) * DF_N + ix + 1], tx)
	return lerpf(a, b, tz)


func _build_dfield(all_pts: Array) -> void:
	dfield.resize(DF_N * DF_N)
	dfield.fill(100000.0)
	for pts2 in all_pts:
		for p in pts2:
			var cx: int = int((p.x - DF_MIN) / DF_RES)
			var cz: int = int((p.y - DF_MIN) / DF_RES)
			for oz in range(-1, 2):
				for ox in range(-1, 2):
					var ix: int = cx + ox
					var iz: int = cz + oz
					if ix < 0 or iz < 0 or ix >= DF_N or iz >= DF_N:
						continue
					var c := Vector2(DF_MIN + (ix + 0.5) * DF_RES, DF_MIN + (iz + 0.5) * DF_RES)
					var d: float = c.distance_to(p)
					if d < dfield[iz * DF_N + ix]:
						dfield[iz * DF_N + ix] = d
	var o: float = DF_RES
	var dg: float = DF_RES * 1.41421
	for iz in DF_N:
		for ix in DF_N:
			var i: int = iz * DF_N + ix
			var v: float = dfield[i]
			if ix > 0: v = minf(v, dfield[i - 1] + o)
			if iz > 0:
				v = minf(v, dfield[i - DF_N] + o)
				if ix > 0: v = minf(v, dfield[i - DF_N - 1] + dg)
				if ix < DF_N - 1: v = minf(v, dfield[i - DF_N + 1] + dg)
			dfield[i] = v
	for iz in range(DF_N - 1, -1, -1):
		for ix in range(DF_N - 1, -1, -1):
			var i: int = iz * DF_N + ix
			var v: float = dfield[i]
			if ix < DF_N - 1: v = minf(v, dfield[i + 1] + o)
			if iz < DF_N - 1:
				v = minf(v, dfield[i + DF_N] + o)
				if ix < DF_N - 1: v = minf(v, dfield[i + DF_N + 1] + dg)
				if ix > 0: v = minf(v, dfield[i + DF_N - 1] + dg)
			dfield[i] = v


## Natural terrain height before road carving.
func natural_height(x: float, z: float) -> float:
	var w: Vector4 = region_weights(x, z)
	# terrain relief is softened near roads so they run through valleys and saddles
	var rdist: float = road_dist(x, z)
	var relief: float = lerpf(0.3, 1.0, smooth(20.0, 240.0, rdist))
	var lo: float = n_low.get_noise_2d(x, z)
	var mid: float = n_mid.get_noise_2d(x, z)
	# farmland: rolling hills, broad river valley
	var farm: float = 16.0 + 11.0 * lo + 4.0 * mid
	# mountains: ridged peaks rising to the north edge
	var north: float = smooth(-700.0, -1900.0, z)
	var ridge: float = n_ridge.get_noise_2d(x, z) * 0.5 + 0.5
	var mount: float = 45.0 + 70.0 * north + 250.0 * ridge * ridge * (0.35 + north) * relief + 15.0 * mid
	# desert: plateau with terraced mesas and dunes
	var mn: float = n_mesa.get_noise_2d(x, z)
	var mesa: float = smooth(0.18, 0.26, mn) * 38.0 + smooth(0.42, 0.48, mn) * 26.0
	var desert: float = 30.0 + 8.0 * lo + mesa * relief + 1.5 * mid + smooth(1600.0, 2100.0, x) * 60.0
	# coast: low hills, higher cliffs to the east
	var coast: float = 10.0 + 8.0 * lo + 3.0 * mid + smooth(0.0, 1200.0, x) * 22.0
	var h: float = w.x * farm + w.y * mount + w.z * desert + w.w * coast
	# river valley + channel
	var rd: float = river_distance(x, z)
	var valley: float = smooth(10.0, 320.0, rd)
	h = lerpf(1.6, h, valley * valley * (3.0 - 2.0 * valley) * 0.3 + valley * 0.7)
	h = lerpf(-3.0, h, smooth(9.0, 22.0, rd))
	# lake basin
	var ld: float = Vector2(x, z).distance_to(LAKE_C)
	h = lerpf(-4.0, h, smooth(LAKE_R * 0.75, LAKE_R * 1.6, ld))
	# sea (south and west), cliffs where land is high
	var s_s: float = z - shore_z(x)
	var s_w: float = shore_x(z) - x
	var s: float = maxf(s_s, s_w)
	var beach: float = lerpf(70.0, 15.0, smooth(10.0, 30.0, h))
	var land: float = 1.0 - smooth(-beach, 35.0, s)
	h = lerpf(-16.0, h, land)
	return h


# ---------------------------------------------------------------- road building
func build() -> void:
	for key in RoadLayout.NODES:
		var p: Vector2 = RoadLayout.NODES[key]
		var hsum: float = 0.0
		for o in [Vector2.ZERO, Vector2(15, 0), Vector2(-15, 0), Vector2(0, 15), Vector2(0, -15)]:
			hsum += natural_height(p.x + o.x, p.y + o.y)
		node_height[key] = maxf(hsum / 5.0, 3.2)
		node_roads[key] = []
	var all2: Array = []
	for def in RoadLayout.ROADS:
		all2.append(_resample(def))
	_build_dfield(all2)
	for key in RoadLayout.NODES:
		var p: Vector2 = RoadLayout.NODES[key]
		var hsum: float = 0.0
		for o in [Vector2.ZERO, Vector2(15, 0), Vector2(-15, 0), Vector2(0, 15), Vector2(0, -15)]:
			hsum += natural_height(p.x + o.x, p.y + o.y)
		node_height[key] = maxf(hsum / 5.0, 3.2)
	for ri in RoadLayout.ROADS.size():
		var def: Array = RoadLayout.ROADS[ri]
		var road: Dictionary = _build_road(def, all2[ri])
		roads.append(road)
		(node_roads[def[2]] as Array).append([ri, true])
		(node_roads[def[3]] as Array).append([ri, false])
		total_length += road.length
		if road.loop:
			loop_length += road.length
	_build_grid()


func _catmull(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, t: float) -> Vector2:
	# centripetal Catmull-Rom
	var a: float = 0.5
	var t0: float = 0.0
	var t1: float = t0 + pow(maxf(p0.distance_to(p1), 0.01), a)
	var t2: float = t1 + pow(maxf(p1.distance_to(p2), 0.01), a)
	var t3: float = t2 + pow(maxf(p2.distance_to(p3), 0.01), a)
	var tt: float = lerpf(t1, t2, t)
	var a1: Vector2 = p0 * (t1 - tt) / (t1 - t0) + p1 * (tt - t0) / (t1 - t0)
	var a2: Vector2 = p1 * (t2 - tt) / (t2 - t1) + p2 * (tt - t1) / (t2 - t1)
	var a3: Vector2 = p2 * (t3 - tt) / (t3 - t2) + p3 * (tt - t2) / (t3 - t2)
	var b1: Vector2 = a1 * (t2 - tt) / (t2 - t0) + a2 * (tt - t0) / (t2 - t0)
	var b2: Vector2 = a2 * (t3 - tt) / (t3 - t1) + a3 * (tt - t1) / (t3 - t1)
	return b1 * (t2 - tt) / (t2 - t1) + b2 * (tt - t1) / (t2 - t1)


func _resample(def: Array) -> PackedVector2Array:
	var ctrl := PackedVector2Array()
	ctrl.append(RoadLayout.NODES[def[2]])
	for p in def[4]:
		ctrl.append(p)
	ctrl.append(RoadLayout.NODES[def[3]])
	# dense polyline
	var dense := PackedVector2Array()
	var n: int = ctrl.size()
	for i in n - 1:
		var p0: Vector2 = ctrl[maxi(i - 1, 0)] if i > 0 else ctrl[0] * 2.0 - ctrl[1]
		var p3: Vector2 = ctrl[i + 2] if i + 2 < n else ctrl[n - 1] * 2.0 - ctrl[n - 2]
		var segs: int = maxi(4, int(ctrl[i].distance_to(ctrl[i + 1]) / 2.0))
		for s in segs:
			dense.append(_catmull(p0, ctrl[i], ctrl[i + 1], p3, float(s) / segs))
	dense.append(ctrl[n - 1])
	# resample by arc length
	var pts2 := PackedVector2Array()
	pts2.append(dense[0])
	var acc: float = 0.0
	for i in range(1, dense.size()):
		var a: Vector2 = dense[i - 1]
		var b: Vector2 = dense[i]
		var seg: float = a.distance_to(b)
		while acc + seg >= STEP:
			var t: float = (STEP - acc) / seg
			a = a.lerp(b, t)
			pts2.append(a)
			seg = a.distance_to(b)
			acc = 0.0
		acc += seg
	if pts2[pts2.size() - 1].distance_to(dense[dense.size() - 1]) > 0.5:
		pts2.append(dense[dense.size() - 1])
	else:
		pts2[pts2.size() - 1] = dense[dense.size() - 1]
	return pts2


func _build_road(def: Array, pts2: PackedVector2Array) -> Dictionary:
	var cls: Dictionary = RoadLayout.CLASSES[def[1]]
	var m: int = pts2.size()
	# elevation profile
	var h := PackedFloat32Array()
	h.resize(m)
	var nat := PackedFloat32Array()
	nat.resize(m)
	for i in m:
		nat[i] = natural_height(pts2[i].x, pts2[i].y)
		h[i] = maxf(nat[i], 3.2)
	var h0: float = node_height[def[2]]
	var h1: float = node_height[def[3]]
	var rad: int = cls.smooth
	for pass_i in 3:
		var out := PackedFloat32Array()
		out.resize(m)
		for i in m:
			var s: float = 0.0
			var c: int = 0
			for k in range(maxi(0, i - rad), mini(m, i + rad + 1)):
				s += h[k]
				c += 1
			out[i] = s / c
		h = out
		h[0] = h0
		h[m - 1] = h1
	# grade limit (forward then backward), keep ends pinned
	var g: float = cls.grade * STEP
	for i in range(1, m):
		h[i] = clampf(h[i], h[i - 1] - g, h[i - 1] + g)
	h[m - 1] = h1
	for i in range(m - 2, -1, -1):
		h[i] = clampf(h[i], h[i + 1] - g, h[i + 1] + g)
	h[0] = h0
	for i in range(1, m):
		h[i] = clampf(h[i], h[i - 1] - g, h[i - 1] + g)
	# final light smoothing
	for pass_i in 2:
		var out2 := h.duplicate()
		for i in range(1, m - 1):
			out2[i] = (h[i - 1] + h[i] * 2.0 + h[i + 1]) * 0.25
		h = out2
	for i in m:
		h[i] = maxf(h[i], 3.0)
	# junction approach: hold the node height across the junction pad, then ease into the profile
	var total_len: float = (m - 1) * STEP
	for i in m:
		var d0: float = i * STEP
		var d1: float = total_len - d0
		if d0 < 40.0:
			h[i] = lerpf(h0, h[i], smooth(14.0, 40.0, d0))
		if d1 < 40.0:
			h[i] = lerpf(h1, h[i], smooth(14.0, 40.0, d1))
	# flags
	var flags := PackedByteArray()
	flags.resize(m)
	for i in m:
		var f: int = 0
		if nat[i] < h[i] - 12.0 or nat[i] < 0.6:
			f = 1
		elif nat[i] > h[i] + float(cls.tunnel):
			f = 2
		flags[i] = f
	_clean_runs(flags, 1, 6)
	_clean_runs(flags, 2, 20)
	# geometry: tangents, right vectors, banking
	var pts := PackedVector3Array()
	var right := PackedVector3Array()
	var bank := PackedFloat32Array()
	var dist := PackedFloat32Array()
	pts.resize(m)
	right.resize(m)
	bank.resize(m)
	dist.resize(m)
	var curv := PackedFloat32Array()
	curv.resize(m)
	for i in m:
		pts[i] = Vector3(pts2[i].x, h[i], pts2[i].y)
		var a: Vector2 = pts2[maxi(i - 1, 0)]
		var b: Vector2 = pts2[mini(i + 1, m - 1)]
		var tng: Vector2 = (b - a).normalized()
		right[i] = Vector3(-tng.y, 0.0, tng.x)  # right-hand side when facing tng (x east, z south)
		if i > 0:
			dist[i] = dist[i - 1] + pts2[i].distance_to(pts2[i - 1])
		if i > 1 and i < m - 2:
			var t1: Vector2 = (pts2[i] - pts2[i - 2]).normalized()
			var t2: Vector2 = (pts2[i + 2] - pts2[i]).normalized()
			curv[i] = t1.cross(t2) / (STEP * 2.0)
	var speed: float = cls.speed / 3.6
	for i in m:
		var s: float = 0.0
		var c: int = 0
		for k in range(maxi(0, i - 5), mini(m, i + 6)):
			s += curv[k]
			c += 1
		# bank toward the inside of the curve; positive = right side up
		var b: float = clampf(-(s / c) * speed * speed / 9.81 * 0.35, -0.08, 0.08)
		if i < 6 or i > m - 7:
			b *= 0.0
		bank[i] = b
	var hw: float = cls.lane * 1.0 + cls.shoulder
	var surf: int = SURFACE_NAMES.find(cls.surface)
	return {
		"name": def[0], "cls": def[1], "surface": surf, "loop": def[5], "from": def[2], "to": def[3],
		"pts": pts, "right": right, "bank": bank, "flags": flags, "dist": dist,
		"hw": hw, "lane": cls.lane, "shoulder": cls.shoulder, "speed": cls.speed,
		"length": dist[m - 1], "curv": curv,
	}


func _clean_runs(flags: PackedByteArray, val: int, min_len: int) -> void:
	var i: int = 0
	var m: int = flags.size()
	while i < m:
		if flags[i] == val:
			var j: int = i
			while j < m and flags[j] == val:
				j += 1
			if j - i < min_len:
				for k in range(i, j):
					flags[k] = 0
			else:
				# pad bridges by two samples so abutments sit on solid ground
				if val == 1:
					for k in range(maxi(0, i - 2), i):
						flags[k] = 1
					for k in range(j, mini(m, j + 2)):
						flags[k] = 1
					j = mini(m, j + 2)
			i = j
		else:
			i += 1


func _cell_key(cx: int, cz: int) -> int:
	return (cx + 1000) * 4096 + (cz + 1000)


func _build_grid() -> void:
	var tmp: Dictionary = {}
	for ri in roads.size():
		var pts: PackedVector3Array = roads[ri].pts
		for si in pts.size() - 1:
			var a: Vector3 = pts[si]
			var b: Vector3 = pts[si + 1]
			var x0: int = int(floor((minf(a.x, b.x) - CELL_MARGIN) / CELL))
			var x1: int = int(floor((maxf(a.x, b.x) + CELL_MARGIN) / CELL))
			var z0: int = int(floor((minf(a.z, b.z) - CELL_MARGIN) / CELL))
			var z1: int = int(floor((maxf(a.z, b.z) + CELL_MARGIN) / CELL))
			var code: int = (ri << 16) | si
			for cx in range(x0, x1 + 1):
				for cz in range(z0, z1 + 1):
					var k: int = _cell_key(cx, cz)
					if not tmp.has(k):
						tmp[k] = PackedInt32Array()
					var arr: PackedInt32Array = tmp[k]
					arr.append(code)
					tmp[k] = arr
	grid = tmp


## Nearest road info at (x,z): {ok, road, seg, t, d (unsigned lateral), side (signed), h (road height incl. bank), flag}
func road_query(x: float, z: float, max_d: float = 60.0) -> Dictionary:
	var k: int = _cell_key(int(floor(x / CELL)), int(floor(z / CELL)))
	if not grid.has(k):
		return {"ok": false}
	var arr: PackedInt32Array = grid[k]
	var best_d: float = max_d
	var best: int = -1
	var best_t: float = 0.0
	var best_side: float = 0.0
	var p := Vector2(x, z)
	for code in arr:
		var ri: int = code >> 16
		var si: int = code & 0xFFFF
		var pts: PackedVector3Array = roads[ri].pts
		var a := Vector2(pts[si].x, pts[si].z)
		var b := Vector2(pts[si + 1].x, pts[si + 1].z)
		var ab: Vector2 = b - a
		var l2: float = ab.length_squared()
		if l2 < 0.0001:
			continue
		var t: float = clampf((p - a).dot(ab) / l2, 0.0, 1.0)
		var q: Vector2 = a + ab * t
		var d: float = p.distance_to(q)
		if d < best_d:
			best_d = d
			best = code
			best_t = t
			best_side = signf(ab.cross(p - a))
	if best < 0:
		return {"ok": false}
	var ri2: int = best >> 16
	var si2: int = best & 0xFFFF
	var r: Dictionary = roads[ri2]
	var pa: Vector3 = r.pts[si2]
	var pb: Vector3 = r.pts[si2 + 1]
	var hh: float = lerpf(pa.y, pb.y, best_t)
	var bank: float = lerpf(r.bank[si2], r.bank[si2 + 1], best_t)
	var side: float = best_side * best_d
	var flag: int = r.flags[si2] if best_t < 0.5 else r.flags[si2 + 1]
	return {"ok": true, "road": ri2, "seg": si2, "t": best_t, "d": best_d, "side": side, "h": hh + bank * side, "hc": hh, "bank": bank, "flag": flag, "hw": r.hw}


## Final terrain height with road cuttings / embankments.
func height(x: float, z: float) -> float:
	var nat: float = natural_height(x, z)
	var q: Dictionary = road_query(x, z)
	if not q.ok:
		return nat
	if q.flag != 0:
		# bridges and tunnels: leave terrain alone, but keep it clear of the bridge deck
		if q.flag == 1 and q.d < q.hw + 1.5:
			return minf(nat, q.hc - 2.5)
		return nat
	var flat: float = q.hw + 2.6
	var dh: float = nat - q.hc
	var fall: float = clampf(absf(dh) * 1.5, 8.0, 56.0)
	var t: float = smooth(flat, flat + fall, q.d)
	var edge: float = q.hc - 0.32 - absf(q.bank) * q.hw
	return lerpf(edge, nat, t)


## Terrain surface (for tyre grip) at a position on the terrain (not on a road deck).
func terrain_surface(x: float, z: float, h: float) -> int:
	var w: Vector4 = region_weights(x, z)
	if h < 3.0:
		return Surface.SAND
	var dn: float = n_detail.get_noise_2d(x, z)
	if w.y > 0.5:
		if h > 230.0 + dn * 20.0:
			return Surface.SNOW
		return Surface.GRAVEL if dn > 0.2 else Surface.GRASS
	if w.z > 0.5:
		return Surface.SAND if dn > -0.1 else Surface.DIRT
	if w.w > 0.5 and h < 7.0:
		return Surface.SAND
	return Surface.GRASS


## Terrain vertex colour
func terrain_color(x: float, z: float, h: float, slope: float) -> Color:
	var w: Vector4 = region_weights(x, z)
	var dn: float = n_detail.get_noise_2d(x * 0.5, z * 0.5)
	var mid: float = n_mid.get_noise_2d(x * 2.0, z * 2.0)
	var farm := Color(0.24, 0.38, 0.11).lerp(Color(0.42, 0.46, 0.17), clampf(mid * 0.8 + 0.4, 0.0, 1.0))
	# field patchwork
	var fx: float = sin(x * 0.021 + sin(z * 0.004) * 3.0) * sin(z * 0.017)
	if fx > 0.35:
		farm = farm.lerp(Color(0.68, 0.6, 0.28), 0.55)
	elif fx < -0.5:
		farm = farm.lerp(Color(0.24, 0.36, 0.12), 0.6)
	var mount := Color(0.22, 0.34, 0.13).lerp(Color(0.34, 0.4, 0.2), clampf(mid + 0.5, 0.0, 1.0))
	mount = mount.lerp(Color(0.4, 0.38, 0.33), smooth(170.0, 230.0, h + dn * 30.0) * 0.8)
	mount = mount.lerp(Color(0.93, 0.95, 0.98), smooth(235.0, 270.0, h + dn * 25.0))
	var desert := Color(0.78, 0.52, 0.3).lerp(Color(0.66, 0.36, 0.2), clampf(mid + 0.5, 0.0, 1.0))
	desert = desert.lerp(Color(0.85, 0.7, 0.48), smooth(0.3, 0.7, dn))
	var coast := Color(0.27, 0.42, 0.15).lerp(Color(0.4, 0.46, 0.22), clampf(mid + 0.5, 0.0, 1.0))
	var c: Color = farm * w.x + mount * w.y + desert * w.z + coast * w.w
	# rock on steep slopes
	var rock := Color(0.36, 0.34, 0.31) if w.z < 0.5 else Color(0.58, 0.32, 0.19)
	c = c.lerp(rock, smooth(0.55, 0.85, slope))
	# sand near water
	c = c.lerp(Color(0.86, 0.78, 0.58), 1.0 - smooth(1.5, 4.5, h))
	c = c.lerp(Color(0.25, 0.3, 0.3), 1.0 - smooth(-2.0, 0.5, h))
	return c


## Drivable point on a road at distance s from its start, lane offset (+ = right of travel direction)
func road_point(ri: int, s: float, offset: float = 0.0) -> Transform3D:
	var r: Dictionary = roads[ri]
	var dist: PackedFloat32Array = r.dist
	s = clampf(s, 0.0, r.length - 0.01)
	var i: int = clampi(int(s / STEP), 0, dist.size() - 2)
	while i < dist.size() - 2 and dist[i + 1] < s:
		i += 1
	while i > 0 and dist[i] > s:
		i -= 1
	var t: float = (s - dist[i]) / maxf(0.001, dist[i + 1] - dist[i])
	var p: Vector3 = r.pts[i].lerp(r.pts[i + 1], t)
	var rt: Vector3 = r.right[i].lerp(r.right[i + 1], t).normalized()
	var bank: float = lerpf(r.bank[i], r.bank[i + 1], t)
	p += rt * offset
	p.y += bank * offset
	var fwd: Vector3 = (r.pts[i + 1] - r.pts[i]).normalized()
	var up: Vector3 = Vector3.UP.rotated(fwd, -bank).normalized()
	var x_axis: Vector3 = up.cross(-fwd).normalized()
	var basis := Basis(x_axis, up, -fwd).orthonormalized()
	return Transform3D(basis, p)


## Find the nearest road sample to a world position (brute force; fine for teleports/resets).
func nearest_road_point(pos: Vector3) -> Dictionary:
	var q: Dictionary = road_query(pos.x, pos.z, 200.0)
	if q.ok:
		var r: Dictionary = roads[q.road]
		return {"road": q.road, "s": r.dist[q.seg] + q.t * STEP}
	var best_d: float = 1e12
	var best: Dictionary = {}
	for ri in roads.size():
		var pts: PackedVector3Array = roads[ri].pts
		for i in range(0, pts.size(), 4):
			var d: float = Vector2(pts[i].x - pos.x, pts[i].z - pos.z).length_squared()
			if d < best_d:
				best_d = d
				best = {"road": ri, "s": roads[ri].dist[i]}
	return best
