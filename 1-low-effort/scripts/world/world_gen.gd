class_name WorldGen
extends RefCounted
## Deterministic world description: regions, height function, road network and a
## road raster used for terrain carving. Thread-safe for reads after build().

const HALF := 2000.0
const CELL := 4.0
const GRID := int(HALF * 2.0 / CELL) # 1000
const SAMPLE_STEP := 4.0
const SEA_LEVEL := 0.0

enum Surface { ASPHALT, CONCRETE, DIRT, GRAVEL, GRASS, SAND, SNOW }
const SURFACE_NAMES := ["asphalt", "concrete", "dirt", "gravel", "grass", "sand", "snow"]
const REGION_NAMES := ["Verdance Vale", "Highpine Ridge", "Ochre Mesa", "Saltwind Coast"]

var seed_value := 1337
var n_base := FastNoiseLite.new()
var n_ridge := FastNoiseLite.new()
var n_detail := FastNoiseLite.new()
var n_mesa := FastNoiseLite.new()

## Each road: {name, cls, surface, width, limit, pts: PackedVector3Array, closed, curv: PackedFloat32Array, length}
var roads: Array[Dictionary] = []
var junctions: Array[Dictionary] = [] # {road, idx, target_road, target_idx}
# raster: nearest road distance, road height, nearest road index, sample index
var r_dist := PackedFloat32Array()
var r_h := PackedFloat32Array()
var r_road := PackedInt32Array()
var r_idx := PackedInt32Array()

func _init(s: int = 1337) -> void:
	seed_value = s
	n_base.seed = s; n_base.frequency = 1.0 / 420.0; n_base.fractal_octaves = 4
	n_ridge.seed = s + 1; n_ridge.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n_ridge.frequency = 1.0 / 650.0; n_ridge.fractal_type = FastNoiseLite.FRACTAL_RIDGED; n_ridge.fractal_octaves = 5
	n_detail.seed = s + 2; n_detail.frequency = 1.0 / 60.0; n_detail.fractal_octaves = 3
	n_mesa.seed = s + 3; n_mesa.frequency = 1.0 / 520.0; n_mesa.fractal_octaves = 2

# ---------------------------------------------------------------- regions
static func _ss(a: float, b: float, x: float) -> float:
	return smoothstep(a, b, x)

func region_weights(x: float, z: float) -> Vector4:
	var we := _ss(-250.0, 250.0, x + 120.0 * sin(z / 410.0))
	var ws := _ss(-250.0, 250.0, z + 120.0 * sin(x / 380.0))
	return Vector4((1.0 - we) * (1.0 - ws), we * (1.0 - ws), we * ws, (1.0 - we) * ws)

func region_at(x: float, z: float) -> int:
	var w := region_weights(x, z)
	var best := 0
	for i in 4:
		if w[i] > w[best]: best = i
	return best

## distance inland from the coastline (negative = sea)
func shore_dist(x: float, z: float) -> float:
	var coast_x := -1680.0 + 90.0 * sin(z / 230.0)
	var d := x - coast_x
	# south shore along the bottom-left
	var sz := 1820.0 + 60.0 * sin(x / 200.0)
	d = minf(d, sz - z)
	# the bay crossed by the long bridge
	var bay := Vector2(x + 1560.0, (z - 980.0) * 1.8).length() - 230.0
	d = minf(d, bay)
	# smooth falloff away from the coast region
	var w := region_weights(x, z).w
	return lerpf(400.0, d, clampf(w * 1.6, 0.0, 1.0))

func river_dist(x: float, z: float) -> float:
	if x > 400.0: return 1e9
	var rz := -1080.0 + 230.0 * sin(x / 310.0) + 60.0 * sin(x / 97.0)
	return absf(z - rz)

## land height before water carving (used as road reference)
func land_height(x: float, z: float) -> float:
	var w := region_weights(x, z)
	var farm := 24.0 + 14.0 * n_base.get_noise_2d(x, z) + 2.0 * n_detail.get_noise_2d(x, z)
	var corner := clampf((x - 200.0) / 1400.0, 0.0, 1.0) * clampf((-z - 150.0) / 1300.0, 0.0, 1.0)
	var mount := 50.0 + (n_ridge.get_noise_2d(x, z) * 0.5 + 0.5) * (60.0 + 300.0 * sqrt(corner)) + 4.0 * n_detail.get_noise_2d(x, z)
	var mn := n_mesa.get_noise_2d(x, z)
	var desert := 34.0 + 55.0 * _ss(0.18, 0.26, mn) + 25.0 * _ss(0.42, 0.48, mn) + 4.0 * n_base.get_noise_2d(x * 2.0, z * 2.0)
	var coast := 16.0 + 9.0 * n_base.get_noise_2d(x + 900.0, z) + 1.5 * n_detail.get_noise_2d(x, z)
	return farm * w.x + mount * w.y + desert * w.z + coast * w.w

func water_carve(x: float, z: float, h: float) -> float:
	var sd := shore_dist(x, z)
	if sd < 120.0:
		h = lerpf(-14.0, h, _ss(-40.0, 90.0, sd))
	var rd := river_dist(x, z)
	if rd < 60.0:
		h = lerpf(-3.5, h, _ss(10.0, 55.0, rd))
	return h

func water_mask(x: float, z: float) -> float:
	var m := 1.0 - _ss(10.0, 40.0, river_dist(x, z))
	m = maxf(m, 1.0 - _ss(-20.0, 60.0, shore_dist(x, z)))
	return m

## final terrain height including road carving
func height(x: float, z: float) -> float:
	var h := water_carve(x, z, land_height(x, z))
	var rd := raster_sample(x, z)
	if rd.x < 60.0:
		var road: Dictionary = roads[int(rd.z)]
		var hw: float = road.width * 0.5 + 2.5
		var t := 1.0 - _ss(hw, hw + 26.0, rd.x)
		t *= 1.0 - water_mask(x, z)
		# tunnel sections keep the hillside (shell is drawn over a cutting anyway)
		h = lerpf(h, rd.y - 0.35, t)
	return h

func surface_at(x: float, z: float) -> int:
	var rd := raster_sample(x, z)
	if rd.z >= 0.0:
		var road: Dictionary = roads[int(rd.z)]
		if rd.x < road.width * 0.5 + 0.3:
			return road.surface
	var r := region_at(x, z)
	var h := land_height(x, z)
	if r == 1 and h > 290.0: return Surface.SNOW
	if r == 2: return Surface.SAND if n_detail.get_noise_2d(x, z) > 0.0 else Surface.DIRT
	if r == 3 and shore_dist(x, z) < 70.0: return Surface.SAND
	if r == 1: return Surface.GRAVEL
	return Surface.GRASS

func ground_color(x: float, z: float, h: float, slope: float) -> Color:
	var w := region_weights(x, z)
	var n := n_detail.get_noise_2d(x * 1.7, z * 1.7) * 0.5 + 0.5
	var farm := Color(0.28, 0.42, 0.14).lerp(Color(0.45, 0.48, 0.18), n)
	# patchwork fields
	var fx := int(floor((x + 5000.0) / 90.0)); var fz := int(floor((z + 5000.0) / 70.0))
	var fh := float(((fx * 73856093) ^ (fz * 19349663)) & 255) / 255.0
	if fh > 0.55: farm = farm.lerp(Color(0.62, 0.55, 0.25), 0.7)
	elif fh > 0.4: farm = farm.lerp(Color(0.35, 0.25, 0.15), 0.5)
	var mount := Color(0.2, 0.33, 0.14).lerp(Color(0.38, 0.36, 0.3), clampf((h - 170.0) / 120.0, 0.0, 1.0))
	if h > 290.0: mount = mount.lerp(Color(0.92, 0.93, 0.96), clampf((h - 290.0) / 30.0, 0.0, 1.0))
	var desert := Color(0.72, 0.48, 0.28).lerp(Color(0.82, 0.62, 0.4), n)
	var coast := Color(0.36, 0.5, 0.2).lerp(Color(0.5, 0.55, 0.25), n)
	var sd := shore_dist(x, z)
	if sd < 80.0: coast = coast.lerp(Color(0.86, 0.8, 0.6), 1.0 - _ss(20.0, 80.0, sd))
	var c := farm * w.x + mount * w.y + desert * w.z + coast * w.w
	if slope > 0.55: c = c.lerp(Color(0.42, 0.38, 0.34) if w.z < 0.5 else Color(0.62, 0.36, 0.22), clampf((slope - 0.55) * 3.0, 0.0, 1.0))
	if h < 1.5: c = c.lerp(Color(0.6, 0.56, 0.45), 0.7)
	var rd := raster_sample(x, z)
	if rd.z >= 0.0:
		var road: Dictionary = roads[int(rd.z)]
		var edge: float = road.width * 0.5 + 3.0
		if rd.x < edge: c = c.lerp(Color(0.38, 0.34, 0.28), 0.6 * (1.0 - _ss(edge - 2.0, edge, rd.x)))
	return c

# ---------------------------------------------------------------- roads
func _catmull(p: Array, closed: bool, step: float) -> PackedVector3Array:
	var out := PackedVector3Array()
	var n := p.size()
	var segs := n if closed else n - 1
	for i in segs:
		var p0: Vector2 = p[(i - 1 + n) % n] if (closed or i > 0) else p[0]
		var p1: Vector2 = p[i]
		var p2: Vector2 = p[(i + 1) % n]
		var p3: Vector2 = p[(i + 2) % n] if (closed or i + 2 < n) else p[n - 1]
		var seg_len := p1.distance_to(p2)
		var k := int(maxf(2.0, ceil(seg_len / step)))
		for j in k:
			var t := float(j) / k
			var t2 := t * t; var t3 := t2 * t
			var q := 0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3)
			out.append(Vector3(q.x, 0.0, q.y))
	if not closed:
		var e: Vector2 = p[n - 1]
		out.append(Vector3(e.x, 0.0, e.y))
	return _resample(out, closed, step)

func _resample(pts: PackedVector3Array, closed: bool, step: float) -> PackedVector3Array:
	var out := PackedVector3Array([pts[0]])
	var carry := 0.0
	var count := pts.size() if closed else pts.size() - 1
	for i in count:
		var a := pts[i]; var b := pts[(i + 1) % pts.size()]
		var l := a.distance_to(b)
		var d := step - carry
		while d <= l:
			out.append(a.lerp(b, d / l))
			d += step
		carry = l - (d - step)
	if closed and out[out.size() - 1].distance_to(out[0]) < step * 0.5:
		out.remove_at(out.size() - 1)
	return out

func _add_road(name: String, cls: String, surface: int, width: float, limit: float, ctrl: Array, closed: bool, wiggle: float) -> void:
	var p: Array = []
	for i in ctrl.size():
		var v: Vector2 = ctrl[i]
		p.append(v)
	# subdivide with deterministic wiggles to give long roads natural sweeps
	if wiggle > 0.0:
		var q: Array = []
		var n := p.size()
		var segs := n if closed else n - 1
		for i in segs:
			var a: Vector2 = p[i]; var b: Vector2 = p[(i + 1) % n]
			q.append(a)
			var l := a.distance_to(b)
			var k := int(l / 260.0)
			var nrm := (b - a).normalized().orthogonal()
			for j in range(1, k):
				var t := float(j) / k
				var off := wiggle * n_base.get_noise_2d(a.x + t * 37.0 * l, b.y + roads.size() * 911.0)
				q.append(a.lerp(b, t) + nrm * off * sin(PI * t))
		if not closed: q.append(p[n - 1])
		p = q
	var pts := _catmull(p, closed, SAMPLE_STEP)
	roads.append({"name": name, "cls": cls, "surface": surface, "width": width, "limit": limit,
		"pts": pts, "closed": closed, "curv": PackedFloat32Array(), "length": 0.0, "tunnel": PackedByteArray(), "bridge": PackedByteArray()})

func build() -> void:
	var A := Surface.ASPHALT
	# Grand loop through all four regions (clockwise from the farmland village)
	_add_road("Grand Valley Loop", "regional", A, 9.0, 110.0, [Vector2(-1500, -250), Vector2(-1700, -900), Vector2(-1150, -1000), Vector2(-1450, -1500), Vector2(-950, -1780), Vector2(-700, -1100), Vector2(-300, -1000), Vector2(-250, -1500), Vector2(250, -1750), Vector2(500, -1150), Vector2(800, -1100), Vector2(800, -1780), Vector2(1300, -1700), Vector2(1600, -1400), Vector2(1250, -1180), Vector2(1600, -1020), Vector2(1250, -860), Vector2(1620, -700), Vector2(1750, -250), Vector2(1100, -300), Vector2(1050, 250), Vector2(1700, 350), Vector2(1700, 900), Vector2(1100, 850), Vector2(1050, 1300), Vector2(1650, 1350), Vector2(1450, 1780), Vector2(800, 1700), Vector2(500, 1150), Vector2(150, 1700), Vector2(-350, 1450), Vector2(-700, 1780), Vector2(-1000, 1250), Vector2(-1350, 1000), Vector2(-1100, 600), Vector2(-1600, 500), Vector2(-1300, 150)], true, 60.0)
	_add_road("Crossland Highway", "highway", Surface.CONCRETE, 13.0, 140.0, [
		Vector2(-1540, 20), Vector2(-900, 80), Vector2(-300, -40), Vector2(400, 60), Vector2(1000, -60), Vector2(1700, -60)], false, 40.0)
	_add_road("Meridian Road", "regional", A, 8.5, 100.0, [
		Vector2(-250, -1450), Vector2(-350, -900), Vector2(-100, -400), Vector2(50, 300), Vector2(-100, 900), Vector2(300, 1520)], false, 60.0)
	_add_road("Orchard Lane", "lane", A, 7.0, 80.0, [
		Vector2(-1640, -760), Vector2(-1150, -950), Vector2(-800, -650), Vector2(-450, -800), Vector2(-350, -900)], false, 40.0)
	_add_road("Pinecut Gravel", "gravel", Surface.GRAVEL, 7.0, 70.0, [
		Vector2(250, -1650), Vector2(450, -1150), Vector2(850, -1000), Vector2(1000, -500), Vector2(1250, -400), Vector2(1700, -280)], false, 50.0)
	_add_road("Mesa Trail", "dirt", Surface.DIRT, 7.5, 75.0, [
		Vector2(1560, 450), Vector2(1050, 600), Vector2(700, 1000), Vector2(900, 1300), Vector2(900, 1700)], false, 60.0)
	_add_road("Dune Run", "dirt", Surface.SAND, 7.5, 70.0, [
		Vector2(-750, 1560), Vector2(-500, 1100), Vector2(-150, 800), Vector2(-100, 400), Vector2(50, 300)], false, 50.0)
	_add_road("Canyon Express", "highway", A, 11.0, 130.0, [
		Vector2(400, 60), Vector2(700, 500), Vector2(1100, 600), Vector2(1560, 450)], false, 40.0)
	_add_road("Clifftop Road", "regional", A, 8.0, 90.0, [
		Vector2(-1500, 560), Vector2(-1100, 600), Vector2(-700, 300), Vector2(-900, 80)], false, 40.0)
	_add_road("Harbour Spur", "lane", A, 7.0, 60.0, [
		Vector2(-1150, 1300), Vector2(-1400, 1500), Vector2(-1560, 1640)], false, 20.0)
	_add_road("Ridge Switchbacks", "gravel", Surface.GRAVEL, 6.5, 60.0, [
		Vector2(850, -1000), Vector2(700, -650), Vector2(950, -560), Vector2(700, -380), Vector2(1000, -300), Vector2(1000, -60)], false, 0.0)
	_add_road("Quarry Road", "regional", A, 8.0, 90.0, [
		Vector2(1100, 850), Vector2(700, 750), Vector2(500, 400), Vector2(400, 60)], false, 50.0)
	_add_road("Valley Back Road", "lane", A, 7.0, 80.0, [
		Vector2(-1150, -1000), Vector2(-950, -450), Vector2(-1100, -150), Vector2(-900, 80)], false, 50.0)
	_snap_endpoints()
	for r in roads: _compute_heights(r)
	_pin_crossings()
	for r in roads: _finish_road(r)
	_build_raster()

func _snap_endpoints() -> void:
	for ri in range(1, roads.size()):
		var r: Dictionary = roads[ri]
		var pts: PackedVector3Array = r.pts
		for end in [0, pts.size() - 1]:
			var best := 1e9; var bj := -1; var bi := -1
			for rj in roads.size():
				if rj == ri: continue
				var q: PackedVector3Array = roads[rj].pts
				for i in range(0, q.size(), 2):
					var d := Vector2(q[i].x - pts[end].x, q[i].z - pts[end].z).length()
					if d < best: best = d; bj = rj; bi = i
			if best < 60.0:
				pts[end] = Vector3(roads[bj].pts[bi].x, 0.0, roads[bj].pts[bi].z)
				junctions.append({"road": ri, "idx": end, "target_road": bj, "target_idx": bi})
		r.pts = pts

func _compute_heights(r: Dictionary) -> void:
	var pts: PackedVector3Array = r.pts
	var n := pts.size()
	var h := PackedFloat32Array(); h.resize(n)
	for i in n:
		h[i] = maxf(land_height(pts[i].x, pts[i].z), 7.0)
	var closed: bool = r.closed
	# moving-average smoothing
	for pass_i in 3:
		var s := PackedFloat32Array(); s.resize(n)
		var win := 10
		for i in n:
			var acc := 0.0; var c := 0
			for k in range(-win, win + 1):
				var j := i + k
				if closed: j = (j + n) % n
				elif j < 0 or j >= n: continue
				acc += h[j]; c += 1
			s[i] = acc / c
		h = s
	var grade := 0.11 if r.cls in ["gravel", "dirt", "lane"] else 0.09
	for pass_i in 2:
		for i in range(1, n): h[i] = clampf(h[i], h[i - 1] - grade * SAMPLE_STEP, h[i - 1] + grade * SAMPLE_STEP)
		for i in range(n - 2, -1, -1): h[i] = clampf(h[i], h[i + 1] - grade * SAMPLE_STEP, h[i + 1] + grade * SAMPLE_STEP)
	for i in n: pts[i].y = maxf(h[i], 6.0)
	r.pts = pts

func _pin_crossings() -> void:
	# mid-road crossings: later roads adopt the earlier road's height (at-grade intersection)
	var hash := {}
	for ri in roads.size():
		var pts: PackedVector3Array = roads[ri].pts
		for i in range(0, pts.size(), 2):
			var key := Vector2i(int(floor(pts[i].x / 16.0)), int(floor(pts[i].z / 16.0)))
			if not hash.has(key): hash[key] = []
			hash[key].append(Vector2i(ri, i))
	for ri in range(1, roads.size()):
		var pts: PackedVector3Array = roads[ri].pts
		var n := pts.size()
		var i := 0
		while i < n:
			var key := Vector2i(int(floor(pts[i].x / 16.0)), int(floor(pts[i].z / 16.0)))
			var hit_h := INF
			for ox in range(-1, 2):
				for oz in range(-1, 2):
					var k2 := key + Vector2i(ox, oz)
					if not hash.has(k2): continue
					for e: Vector2i in hash[k2]:
						if e.x >= ri: continue
						var q: Vector3 = roads[e.x].pts[e.y]
						if Vector2(q.x - pts[i].x, q.z - pts[i].z).length() < 6.0: hit_h = q.y
			if hit_h != INF:
				var delta := hit_h - pts[i].y
				for k in range(-45, 46):
					var j := i + k
					if roads[ri].closed: j = posmod(j, n)
					elif j < 0 or j >= n: continue
					pts[j].y += delta * (1.0 - smoothstep(0.0, 1.0, absf(k) / 45.0))
				i += 12
			i += 1
		roads[ri].pts = pts
	# junction endpoints adopt the height of the road they join; blend back over 120 m
	for j in junctions:
		var r: Dictionary = roads[j.road]
		var target_h: float = roads[j.target_road].pts[j.target_idx].y
		var pts: PackedVector3Array = r.pts
		var n := pts.size()
		var delta: float = target_h - pts[j.idx].y
		for k in 40:
			var i: int = j.idx + k if j.idx == 0 else j.idx - k
			if i < 0 or i >= n: break
			pts[i].y += delta * (1.0 - smoothstep(0.0, 1.0, k / 40.0))
		r.pts = pts

func _finish_road(r: Dictionary) -> void:
	var pts: PackedVector3Array = r.pts
	var n := pts.size()
	var curv := PackedFloat32Array(); curv.resize(n)
	var tun := PackedByteArray(); tun.resize(n)
	var bri := PackedByteArray(); bri.resize(n)
	var closed: bool = r.closed
	for i in n:
		var a := pts[(i - 3 + n) % n] if closed or i >= 3 else pts[0]
		var c := pts[(i + 3) % n] if closed or i + 3 < n else pts[n - 1]
		var d1 := Vector2(pts[i].x - a.x, pts[i].z - a.z).normalized()
		var d2 := Vector2(c.x - pts[i].x, c.z - pts[i].z).normalized()
		curv[i] = d1.angle_to(d2) / (3.0 * SAMPLE_STEP)
		var lh := land_height(pts[i].x, pts[i].z)
		tun[i] = 1 if lh > pts[i].y + 16.0 else 0
		var wh := water_carve(pts[i].x, pts[i].z, lh)
		bri[i] = 1 if (water_mask(pts[i].x, pts[i].z) > 0.3 and wh < pts[i].y - 2.0) else 0
	# require tunnels to be at least 60 m long
	var run := 0
	for i in n + 1:
		if i < n and tun[i] == 1: run += 1
		else:
			if run > 0 and run < 15:
				for k in run: tun[i - 1 - k] = 0
			run = 0
	r.curv = curv; r.tunnel = tun; r.bridge = bri
	r.length = n * SAMPLE_STEP

func _build_raster() -> void:
	var cells := GRID * GRID
	r_dist.resize(cells); r_dist.fill(1e6)
	r_h.resize(cells); r_road.resize(cells); r_road.fill(-1); r_idx.resize(cells)
	var rad := 11 # cells (44 m) covers road half-width + carving falloff
	for ri in roads.size():
		var pts: PackedVector3Array = roads[ri].pts
		var n := pts.size()
		for i in range(0, n, 2):
			var p := pts[i]
			var q := pts[(i + 2) % n] if (roads[ri].closed or i + 2 < n) else pts[n - 1]
			var cx := int((p.x + HALF) / CELL); var cz := int((p.z + HALF) / CELL)
			var seg := Vector2(q.x - p.x, q.z - p.z)
			var sl2 := maxf(seg.length_squared(), 0.0001)
			for gz in range(maxi(cz - rad, 0), mini(cz + rad + 1, GRID)):
				var wz := gz * CELL - HALF + CELL * 0.5
				var row := gz * GRID
				for gx in range(maxi(cx - rad, 0), mini(cx + rad + 1, GRID)):
					var wx := gx * CELL - HALF + CELL * 0.5
					var rel := Vector2(wx - p.x, wz - p.z)
					var t := clampf(rel.dot(seg) / sl2, 0.0, 1.0)
					var d := (rel - seg * t).length()
					var ci := row + gx
					if d < r_dist[ci]:
						r_dist[ci] = d
						r_h[ci] = lerpf(p.y, q.y, t)
						r_road[ci] = ri
						r_idx[ci] = i + (1 if t > 0.5 else 0)

## returns (distance to road, road height, road index, sample index) ; bilinear for dist/height
func raster_sample(x: float, z: float) -> Vector4:
	var fx := (x + HALF) / CELL - 0.5; var fz := (z + HALF) / CELL - 0.5
	var ix := int(floor(fx)); var iz := int(floor(fz))
	if ix < 0 or iz < 0 or ix >= GRID - 1 or iz >= GRID - 1: return Vector4(1e6, 0, -1, -1)
	var tx := fx - ix; var tz := fz - iz
	var i00 := iz * GRID + ix
	var d := lerpf(lerpf(r_dist[i00], r_dist[i00 + 1], tx), lerpf(r_dist[i00 + GRID], r_dist[i00 + GRID + 1], tx), tz)
	if d > 1e5: return Vector4(1e6, 0, -1, -1)
	var nearest := i00
	if tx > 0.5: nearest += 1
	if tz > 0.5: nearest += GRID
	var hh := r_h[nearest]
	# only blend heights between cells that reference the same road
	if r_road[i00] == r_road[i00 + 1] and r_road[i00] == r_road[i00 + GRID] and r_road[i00] == r_road[i00 + GRID + 1]:
		hh = lerpf(lerpf(r_h[i00], r_h[i00 + 1], tx), lerpf(r_h[i00 + GRID], r_h[i00 + GRID + 1], tx), tz)
	return Vector4(d, hh, r_road[nearest], r_idx[nearest])

func total_road_km() -> float:
	var t := 0.0
	for r in roads: t += r.length
	return t / 1000.0

## Road frame helpers
func road_point(ri: int, i: int) -> Vector3:
	var pts: PackedVector3Array = roads[ri].pts
	var n := pts.size()
	if roads[ri].closed: return pts[posmod(i, n)]
	return pts[clampi(i, 0, n - 1)]

func road_dir(ri: int, i: int) -> Vector3:
	var a := road_point(ri, i - 1); var b := road_point(ri, i + 1)
	var d := b - a
	return d.normalized() if d.length() > 0.01 else Vector3.FORWARD
