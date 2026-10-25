class_name WorldGen
extends RefCounted
## Deterministic (seeded) world generator. Produces the baked world data consumed at runtime:
## heightmap, surface ids (+ tunnel holes), splat/biome textures, road network, places.
## Run through tools/bake_world.gd.

const N := 2049            # height samples per side
const CELL := 2.0          # metres between samples
const ORIGIN := -2048.0    # world coordinate of sample 0
const SAMPLE_STEP := 4.0   # road sampling distance
const HOLE := 255
const S_ASPHALT := 0
const S_CONCRETE := 1
const S_DIRT := 2
const S_GRAVEL := 3
const S_GRASS := 4
const S_SAND := 5
const S_SNOW := 6
const S_ROCK := 7

var plan := WorldPlan
var nz_base := FastNoiseLite.new()
var nz_detail := FastNoiseLite.new()
var nz_ridge := FastNoiseLite.new()
var nz_mesa := FastNoiseLite.new()
var nz_mask := FastNoiseLite.new()

var h0 := PackedFloat32Array()      # natural terrain (with river)
var hgt := PackedFloat32Array()     # final terrain
var cw := PackedFloat32Array()      # carve weight
var ch := PackedFloat32Array()      # carve target height
var cdist := PackedFloat32Array()   # distance of the road that set the carve
var shoulder_w := PackedFloat32Array()  # 1 near road edges (dirt shoulders)
var holes := PackedByteArray()
var surf := PackedByteArray()
var river_level := PackedFloat32Array()  # water level per river sample
var river_pts := PackedVector3Array()
var roads: Array = []   # Array of Dictionary
var places: Array = []
var log_lines := PackedStringArray()
const DN := 513           # corridor distance field resolution (8 m)
const DCELL := 8.0
var road_dist := PackedFloat32Array()


func _init() -> void:
	nz_base.seed = WorldPlan.SEED
	nz_base.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	nz_base.fractal_type = FastNoiseLite.FRACTAL_FBM
	nz_base.fractal_octaves = 4
	nz_base.frequency = 1.0 / 900.0
	nz_detail.seed = WorldPlan.SEED + 1
	nz_detail.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	nz_detail.fractal_type = FastNoiseLite.FRACTAL_FBM
	nz_detail.fractal_octaves = 3
	nz_detail.frequency = 1.0 / 160.0
	nz_ridge.seed = WorldPlan.SEED + 2
	nz_ridge.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	nz_ridge.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	nz_ridge.fractal_octaves = 5
	nz_ridge.frequency = 1.0 / 1100.0
	nz_mesa.seed = WorldPlan.SEED + 3
	nz_mesa.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	nz_mesa.fractal_type = FastNoiseLite.FRACTAL_FBM
	nz_mesa.fractal_octaves = 3
	nz_mesa.frequency = 1.0 / 420.0
	nz_mask.seed = WorldPlan.SEED + 4
	nz_mask.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	nz_mask.frequency = 1.0 / 700.0


func say(s: String) -> void:
	print(s)
	log_lines.append(s)


# ------------------------------------------------------------------ analytic fields
static func coast_x(z: float) -> float:
	var x := 1500.0 + 110.0 * sin(z * 0.0042 + 1.0) + 45.0 * sin(z * 0.013)
	# the harbour bay
	x -= 400.0 * exp(-pow((z + 160.0) / 230.0, 2.0))
	return x


func region_weights(x: float, z: float) -> Vector4:
	var n := nz_mask.get_noise_2d(x, z) * 160.0
	var d_c := Vector2(x + 2048.0, z + 2048.0).length()
	var s_sw := (-x + z) * 0.7071
	var m := 1.0 - smoothstep(1250.0, 2050.0, d_c - n)
	var d := smoothstep(380.0, 980.0, s_sw - n * 0.8) * (1.0 - m)
	var c := smoothstep(-650.0, -280.0, x - coast_x(z) + n * 0.5) * (1.0 - m) * (1.0 - d)
	var v := maxf(0.0, 1.0 - m - d - c)
	return Vector4(v, m, d, c)  # VALLEY, HIGHLANDS, MESA, COAST


func corridor(x: float, z: float) -> float:
	if road_dist.is_empty():
		return 1.0
	var fx := clampf((x - ORIGIN) / DCELL, 0.0, DN - 1.001)
	var fz := clampf((z - ORIGIN) / DCELL, 0.0, DN - 1.001)
	var ix := int(fx)
	var iz := int(fz)
	var tx := fx - ix
	var tz := fz - iz
	var i := iz * DN + ix
	var d := lerpf(lerpf(road_dist[i], road_dist[i + 1], tx), lerpf(road_dist[i + DN], road_dist[i + DN + 1], tx), tz)
	return smoothstep(25.0, 240.0, d)


func natural_height(x: float, z: float) -> float:
	var w := region_weights(x, z)
	var f := corridor(x, z)
	var base := nz_base.get_noise_2d(x, z)
	var det := nz_detail.get_noise_2d(x, z) * lerpf(0.35, 1.0, f)
	# valley: gentle rolling hills
	var hv := 34.0 + base * 26.0 + det * 6.0
	# highlands: rising toward the NW corner with ridges
	var d_c := Vector2(x + 2048.0, z + 2048.0).length()
	var ridge := nz_ridge.get_noise_2d(x, z) * 0.5 + 0.5
	var hm := 50.0 + clampf(2050.0 - d_c, 0.0, 2050.0) * 0.088 + pow(ridge, 1.6) * 170.0 * lerpf(0.08, 1.0, f) * smoothstep(2100.0, 1500.0, d_c) + det * 10.0
	# mesa: plateau with flat-topped buttes
	var mt := nz_mesa.get_noise_2d(x, z)
	var hd := 48.0 + base * 10.0 + (smoothstep(0.28, 0.36, mt) * 42.0 + smoothstep(0.55, 0.6, mt) * 25.0) * smoothstep(0.35, 1.0, f) + det * 2.5
	# coast: low plateau
	var hc := 30.0 + base * 14.0 + det * 5.0
	var h := hv * w.x + hm * w.y + hd * w.z + hc * w.w
	# shoreline: cliffs in the north, beaches in the south
	var d_in := coast_x(z) - x
	var cliff := 1.0 - smoothstep(-250.0, 450.0, z)
	var width := lerpf(220.0, 26.0, cliff)
	var shore := smoothstep(-40.0, width, d_in)
	h = lerpf(-16.0, h, shore)
	if cliff > 0.5 and d_in > 0.0 and d_in < width:
		h -= (1.0 - shore) * 6.0
	# raised rim at the three land edges keeps the world closed
	var edge := maxf(maxf(-x, absf(z)) - 1800.0, 0.0)
	if x < coast_x(z) - 300.0:
		h += pow(edge / 248.0, 1.6) * 70.0
	return h


# ------------------------------------------------------------------ helpers
static func idx(ix: int, iz: int) -> int:
	return iz * N + ix


static func to_cell(v: float) -> float:
	return (v - ORIGIN) / CELL


func sample_h(arr: PackedFloat32Array, x: float, z: float) -> float:
	var fx := clampf(to_cell(x), 0.0, N - 1.001)
	var fz := clampf(to_cell(z), 0.0, N - 1.001)
	var ix := int(fx)
	var iz := int(fz)
	var tx := fx - ix
	var tz := fz - iz
	var i := iz * N + ix
	var a := lerpf(arr[i], arr[i + 1], tx)
	var b := lerpf(arr[i + N], arr[i + N + 1], tx)
	return lerpf(a, b, tz)


static func catmull(points: Array, closed: bool, step: float) -> PackedVector2Array:
	var pts: Array[Vector2] = []
	for p in points:
		pts.append(Vector2(p[0], p[1]))
	var n := pts.size()
	var dense := PackedVector2Array()
	var segs := n if closed else n - 1
	for i in segs:
		var p0 := pts[(i - 1 + n) % n] if (closed or i > 0) else pts[0] * 2.0 - pts[1]
		var p1 := pts[i]
		var p2 := pts[(i + 1) % n]
		var p3: Vector2
		if closed or i + 2 < n:
			p3 = pts[(i + 2) % n]
		else:
			p3 = p2 * 2.0 - p1
		var length := p1.distance_to(p2)
		var sub := maxi(4, int(length / 2.0))
		for k in sub:
			var t := float(k) / sub
			var t2 := t * t
			var t3 := t2 * t
			var q := 0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3)
			dense.append(q)
	if closed:
		dense.append(pts[0])
	else:
		dense.append(pts[n - 1])
	# resample at a constant step
	var out := PackedVector2Array()
	out.append(dense[0])
	var acc := 0.0
	for i in range(1, dense.size()):
		var a := dense[i - 1]
		var b := dense[i]
		var seg := a.distance_to(b)
		while acc + seg >= step:
			var t := (step - acc) / seg
			a = a.lerp(b, t)
			seg = a.distance_to(b)
			out.append(a)
			acc = 0.0
		acc += seg
	if out[out.size() - 1].distance_to(dense[dense.size() - 1]) > step * 0.3:
		out.append(dense[dense.size() - 1])
	return out


# ------------------------------------------------------------------ stages
func generate() -> void:
	var t0 := Time.get_ticks_msec()
	_corridor_field()
	say("corridor %d ms" % (Time.get_ticks_msec() - t0))
	t0 = Time.get_ticks_msec()
	_base_heights()
	say("base heights %d ms" % (Time.get_ticks_msec() - t0))
	t0 = Time.get_ticks_msec()
	_river()
	say("river %d ms" % (Time.get_ticks_msec() - t0))
	t0 = Time.get_ticks_msec()
	cw.resize(N * N)
	cw.fill(0.0)
	ch.resize(N * N)
	ch.fill(0.0)
	cdist.resize(N * N)
	cdist.fill(1.0e9)
	shoulder_w.resize(N * N)
	shoulder_w.fill(0.0)
	holes.resize(N * N)
	holes.fill(0)
	_places_pads()
	_roads()
	say("roads %d ms" % (Time.get_ticks_msec() - t0))
	t0 = Time.get_ticks_msec()
	_combine()
	_surfaces()
	say("combine+surfaces %d ms" % (Time.get_ticks_msec() - t0))


func _corridor_field() -> void:
	road_dist.resize(DN * DN)
	road_dist.fill(1.0e6)
	var lines: Array = []
	for def in WorldPlan.ROADS:
		lines.append(catmull(def.pts, def.get("closed", false), 6.0))
	lines.append(catmull(WorldPlan.RIVER, false, 6.0))
	for pts in lines:
		for p in pts:
			var ix := clampi(int(round((p.x - ORIGIN) / DCELL)), 0, DN - 1)
			var iz := clampi(int(round((p.y - ORIGIN) / DCELL)), 0, DN - 1)
			road_dist[iz * DN + ix] = 0.0
	# two-pass chamfer distance transform
	var d1 := DCELL
	var d2 := DCELL * 1.4142
	for iz in DN:
		for ix in DN:
			var i := iz * DN + ix
			var v := road_dist[i]
			if ix > 0:
				v = minf(v, road_dist[i - 1] + d1)
			if iz > 0:
				v = minf(v, road_dist[i - DN] + d1)
				if ix > 0:
					v = minf(v, road_dist[i - DN - 1] + d2)
				if ix < DN - 1:
					v = minf(v, road_dist[i - DN + 1] + d2)
			road_dist[i] = v
	for iz in range(DN - 1, -1, -1):
		for ix in range(DN - 1, -1, -1):
			var i := iz * DN + ix
			var v := road_dist[i]
			if ix < DN - 1:
				v = minf(v, road_dist[i + 1] + d1)
			if iz < DN - 1:
				v = minf(v, road_dist[i + DN] + d1)
				if ix < DN - 1:
					v = minf(v, road_dist[i + DN + 1] + d2)
				if ix > 0:
					v = minf(v, road_dist[i + DN - 1] + d2)
			road_dist[i] = v


func _base_heights() -> void:
	# coarse 4 m grid then bilinear upsample to 2 m
	var cn := (N - 1) / 2 + 1
	var coarse := PackedFloat32Array()
	coarse.resize(cn * cn)
	for iz in cn:
		var z := ORIGIN + iz * CELL * 2.0
		for ix in cn:
			var x := ORIGIN + ix * CELL * 2.0
			coarse[iz * cn + ix] = natural_height(x, z)
	h0.resize(N * N)
	for iz in N:
		var cz := iz >> 1
		var oz := iz & 1
		for ix in N:
			var cx := ix >> 1
			var ox := ix & 1
			var i := cz * cn + cx
			var v := coarse[i]
			if ox == 1 and cx + 1 < cn:
				v = (v + coarse[i + 1]) * 0.5
			if oz == 1 and cz + 1 < cn:
				var v2 := coarse[i + cn]
				if ox == 1 and cx + 1 < cn:
					v2 = (v2 + coarse[i + cn + 1]) * 0.5
				v = (v + v2) * 0.5
			h0[iz * N + ix] = v


func _river() -> void:
	var pts := catmull(WorldPlan.RIVER, false, 6.0)
	var lv := PackedFloat32Array()
	lv.resize(pts.size())
	# water level: smoothed terrain, monotonically decreasing toward the sea
	for i in pts.size():
		var acc := 0.0
		var cnt := 0
		for k in range(-8, 9):
			var j := clampi(i + k, 0, pts.size() - 1)
			acc += sample_h(h0, pts[j].x, pts[j].y)
			cnt += 1
		lv[i] = acc / cnt - 3.0
	for i in range(1, lv.size()):
		lv[i] = minf(lv[i], lv[i - 1] - 0.02)
	for i in lv.size():
		lv[i] = maxf(lv[i], 0.2 if i < lv.size() - 20 else 0.0)
	river_pts.clear()
	for i in pts.size():
		river_pts.append(Vector3(pts[i].x, lv[i], pts[i].y))
	river_level = lv
	# carve channel
	var half := 8.0
	var bank := 16.0
	for i in range(pts.size() - 1):
		var a := pts[i]
		var b := pts[i + 1]
		var ya := lv[i]
		var yb := lv[i + 1]
		_raster_segment(a, b, half + bank + 4.0, func(ix: int, iz: int, t: float, d: float) -> void:
			var k := iz * N + ix
			var wl := lerpf(ya, yb, t)
			var bed := wl - 2.2 * (1.0 - smoothstep(0.0, half, d))
			var target := bed
			if d > half:
				target = lerpf(wl - 0.3, h0[k], smoothstep(half, half + bank, d))
			if target < h0[k]:
				h0[k] = target
		)


## Calls fn(ix, iz, t, dist) for every grid cell within radius of segment a-b.
func _raster_segment(a: Vector2, b: Vector2, radius: float, fn: Callable) -> void:
	var minx := clampi(int(floor(to_cell(minf(a.x, b.x) - radius))), 0, N - 1)
	var maxx := clampi(int(ceil(to_cell(maxf(a.x, b.x) + radius))), 0, N - 1)
	var minz := clampi(int(floor(to_cell(minf(a.y, b.y) - radius))), 0, N - 1)
	var maxz := clampi(int(ceil(to_cell(maxf(a.y, b.y) + radius))), 0, N - 1)
	var ab := b - a
	var len2 := maxf(ab.length_squared(), 1e-6)
	for iz in range(minz, maxz + 1):
		var z := ORIGIN + iz * CELL
		for ix in range(minx, maxx + 1):
			var x := ORIGIN + ix * CELL
			var t := clampf(((x - a.x) * ab.x + (z - a.y) * ab.y) / len2, 0.0, 1.0)
			var px := a.x + ab.x * t - x
			var pz := a.y + ab.y * t - z
			var d := sqrt(px * px + pz * pz)
			if d <= radius:
				fn.call(ix, iz, t, d)


func _places_pads() -> void:
	places.clear()
	for p in WorldPlan.PLACES:
		var pos := Vector2(p.pos[0], p.pos[1])
		var r: float = p.r
		var hc := sample_h(h0, pos.x, pos.y)
		var flat := 0.85 if p.type in ["village", "hamlet", "harbour", "festival", "gas", "diner", "farm"] else 0.0
		if p.type == "windfarm":
			flat = 0.0
		if p.type in ["lighthouse", "castle", "viewpoint"]:
			flat = 0.9
		if p.type == "harbour":
			hc = maxf(hc, 3.0)
		var d: Dictionary = p.duplicate(true)
		d["y"] = hc
		places.append(d)
		if flat <= 0.0:
			continue
		var rr := r * 1.3
		var minx := clampi(int(to_cell(pos.x - rr)), 0, N - 1)
		var maxx := clampi(int(to_cell(pos.x + rr)), 0, N - 1)
		var minz := clampi(int(to_cell(pos.y - rr)), 0, N - 1)
		var maxz := clampi(int(to_cell(pos.y + rr)), 0, N - 1)
		for iz in range(minz, maxz + 1):
			for ix in range(minx, maxx + 1):
				var x := ORIGIN + ix * CELL
				var z := ORIGIN + iz * CELL
				var dd := pos.distance_to(Vector2(x, z))
				var w := (1.0 - smoothstep(r * 0.75, rr, dd)) * flat
				var k := iz * N + ix
				if w > cw[k]:
					cw[k] = w
					ch[k] = hc


func _road_by_id(id: String) -> Dictionary:
	for r in roads:
		if r.id == id:
			return r
	return {}


func _nearest_on(road: Dictionary, p: Vector2) -> int:
	var pts: PackedVector2Array = road.pts2
	var best := 0
	var bd := INF
	for i in pts.size():
		var d := pts[i].distance_squared_to(p)
		if d < bd:
			bd = d
			best = i
	return best


func _roads() -> void:
	roads.clear()
	var total := 0.0
	for def in WorldPlan.ROADS:
		var info: Dictionary = WorldPlan.CLASS_INFO[def["class"]]
		var closed: bool = def.get("closed", false)
		var pts := catmull(def.pts, closed, SAMPLE_STEP)
		if def.has("wiggle"):
			pts = _wiggle(pts, closed, def.wiggle[0], def.wiggle[1])
		var n := pts.size()
		var road := {
			"id": def.id, "name": def.name, "class": def["class"], "closed": closed,
			"width": info.width, "lanes": info.lanes, "speed": info.speed, "surface": info.surface,
			"shoulder": info.shoulder, "markings": info.markings, "pts2": pts,
		}
		# terrain under the line
		var th := PackedFloat32Array()
		th.resize(n)
		for i in n:
			th[i] = sample_h(h0, pts[i].x, pts[i].y)
		# smooth
		var win := 18 if def["class"] == "highway" else (12 if def["class"] in ["regional", "mountain"] else 7)
		var y := PackedFloat32Array()
		y.resize(n)
		for i in n:
			var acc := 0.0
			var c := 0
			for k in range(-win, win + 1):
				var j := i + k
				if closed:
					j = posmod(j, n)
				else:
					j = clampi(j, 0, n - 1)
				acc += th[j]
				c += 1
			y[i] = acc / c
		# water clearance (sea and river)
		for i in n:
			var clear := 0.0
			if th[i] < 1.0:
				clear = 9.0
			y[i] = maxf(y[i], clear)
		var near_river := _river_clearance(pts)
		for i in n:
			if near_river[i] > -1000.0:
				y[i] = maxf(y[i], near_river[i] + 5.0)
		# junction pins
		var pins := {}
		var junctions: Array = []
		for key in ["start_on", "end_on"]:
			if not def.has(key):
				continue
			var other := _road_by_id(def[key])
			if other.is_empty():
				continue
			var my_i := 0 if key == "start_on" else n - 1
			var oi := _nearest_on(other, pts[my_i])
			var op: Vector2 = other.pts2[oi]
			pts[my_i] = op
			pins[my_i] = (other.y as PackedFloat32Array)[oi]
			junctions.append({"self_i": my_i, "road": other.id, "road_i": oi})
		road["pts2"] = pts
		# grade limit (iterate forward/backward, respecting pins)
		var g: float = float(def.get("grade", info.grade)) * SAMPLE_STEP
		for it in 4:
			for i in pins:
				y[i] = pins[i]
			for i in range(1, n):
				y[i] = clampf(y[i], y[i - 1] - g, y[i - 1] + g)
			for i in pins:
				y[i] = pins[i]
			for i in range(n - 2, -1, -1):
				y[i] = clampf(y[i], y[i + 1] - g, y[i + 1] + g)
		for i in pins:
			y[i] = pins[i]
		# light final smoothing
		var y2 := y.duplicate()
		for i in n:
			if pins.has(i):
				continue
			var acc := 0.0
			for k in range(-2, 3):
				var j := posmod(i + k, n) if closed else clampi(i + k, 0, n - 1)
				acc += y[j]
			y2[i] = acc / 5.0
		y = y2
		# blend into junction pins over the first/last 40 m so pinned ends are smooth
		for pi in pins:
			for k in range(1, 11):
				var j: int = pi + k if pi == 0 else pi - k
				if j < 0 or j >= n:
					continue
				y[j] = lerpf(pins[pi], y[j], float(k) / 10.0)
		road["y"] = y
		# straighten spans: across deep dips (bridges) and high ground (tunnels) the deck runs
		# straight between its abutments instead of following the smoothed terrain
		for pass_i in 2:
			var i := 1
			while i < n - 1:
				var kind := 0
				var diff_i := y[i] - th[i]
				if diff_i > 8.0:
					kind = 1
				elif -diff_i > 19.0 and def["class"] in ["regional", "mountain", "highway"]:
					kind = 2
				if kind == 0:
					i += 1
					continue
				var j := i
				while j < n - 1:
					var dj := y[j] - th[j]
					if (kind == 1 and dj > 4.0) or (kind == 2 and -dj > 12.0):
						j += 1
					else:
						break
				var a := maxi(i - 2, 0)
				var b := mini(j + 2, n - 1)
				var ya := y[a]
				var yb := y[b]
				for k in range(a + 1, b):
					if pins.has(k):
						continue
					var lin := lerpf(ya, yb, float(k - a) / float(b - a))
					y[k] = maxf(lin, 9.0) if th[k] < 1.0 else lin
				i = b + 1
		# flags: 1 = bridge, 2 = tunnel
		var flags := PackedByteArray()
		flags.resize(n)
		for i in n:
			var diff := y[i] - th[i]
			if diff > 8.0:
				flags[i] = 1
			elif -diff > 19.0 and def["class"] in ["regional", "mountain", "highway"]:
				flags[i] = 2
		_clean_flags(flags, 1, 4)
		_clean_flags(flags, 2, 18)
		# tunnels must not start right at junctions
		road["flags"] = flags
		road["junctions"] = junctions
		# banking from curvature (radians, + = bank right)
		var bank := PackedFloat32Array()
		bank.resize(n)
		for i in n:
			var a := pts[posmod(i - 3, n) if closed else maxi(i - 3, 0)]
			var b := pts[i]
			var c2 := pts[posmod(i + 3, n) if closed else mini(i + 3, n - 1)]
			var d1 := (b - a).normalized()
			var d2 := (c2 - b).normalized()
			var turn := d1.angle_to(d2)
			bank[i] = clampf(turn * 0.35, -0.07, 0.07) if road["class"] != "dirt" else 0.0
		road["bank"] = bank
		var length := (n - 1) * SAMPLE_STEP
		road["length"] = length
		total += length
		roads.append(road)
		var nb := 0
		var nt := 0
		for f in flags:
			if f == 1:
				nb += 1
			elif f == 2:
				nt += 1
		say("road %-16s %6.0f m  bridge %4.0f m  tunnel %4.0f m" % [def.id, length, nb * SAMPLE_STEP, nt * SAMPLE_STEP])
		if OS.get_environment("VELORA_DEBUG_ROAD") == def.id:
			for i in range(0, n, 5):
				if flags[i] == 0:
					continue
				say("   i=%d p=(%.0f,%.0f) th=%.1f y=%.1f f=%d" % [i, pts[i].x, pts[i].y, th[i], y[i], flags[i]])
		_carve_road(road, th)
	say("TOTAL ROAD LENGTH %.0f m" % total)


func _wiggle(pts: PackedVector2Array, closed: bool, amp: float, wavelength: float) -> PackedVector2Array:
	var n := pts.size()
	var out := PackedVector2Array()
	out.resize(n)
	for i in n:
		var a := pts[posmod(i - 10, n) if closed else maxi(i - 10, 0)]
		var b := pts[posmod(i + 10, n) if closed else mini(i + 10, n - 1)]
		var c := pts[i]
		var turn := absf((c - a).angle_to(b - c))
		var tangent := (b - a).normalized()
		var normal := Vector2(-tangent.y, tangent.x)
		var s := i * SAMPLE_STEP
		var k := amp * (1.0 - smoothstep(0.15, 0.5, turn))
		out[i] = c + normal * sin(s / wavelength * TAU) * k
	# resample the displaced line at the constant step
	var res := PackedVector2Array()
	res.append(out[0])
	var acc := 0.0
	for i in range(1, n):
		var p0 := out[i - 1]
		var p1 := out[i]
		var seg := p0.distance_to(p1)
		while acc + seg >= SAMPLE_STEP:
			var t := (SAMPLE_STEP - acc) / seg
			p0 = p0.lerp(p1, t)
			seg = p0.distance_to(p1)
			res.append(p0)
			acc = 0.0
		acc += seg
	if closed:
		res[res.size() - 1] = res[0] if res[res.size() - 1].distance_to(res[0]) < SAMPLE_STEP * 0.5 else res[res.size() - 1]
	return res


func _river_clearance(pts: PackedVector2Array) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(pts.size())
	out.fill(-10000.0)
	for i in pts.size():
		var p := pts[i]
		for j in range(0, river_pts.size(), 2):
			var rp := river_pts[j]
			if absf(rp.x - p.x) < 40.0 and absf(rp.z - p.y) < 40.0:
				if Vector2(rp.x, rp.z).distance_to(p) < 30.0:
					out[i] = maxf(out[i], rp.y)
	return out


static func _clean_flags(flags: PackedByteArray, v: int, min_len: int) -> void:
	# fill short gaps, then drop short runs
	var n := flags.size()
	var i := 0
	while i < n:
		if flags[i] != v:
			var j := i
			while j < n and flags[j] != v:
				j += 1
			if i > 0 and j < n and j - i <= 3:
				for k in range(i, j):
					flags[k] = v
			i = j
		else:
			i += 1
	i = 0
	while i < n:
		if flags[i] == v:
			var j := i
			while j < n and flags[j] == v:
				j += 1
			if j - i < min_len:
				for k in range(i, j):
					flags[k] = 0
			i = j
		else:
			i += 1


func _carve_road(road: Dictionary, th: PackedFloat32Array) -> void:
	var pts: PackedVector2Array = road.pts2
	var y: PackedFloat32Array = road.y
	var flags: PackedByteArray = road.flags
	var hw: float = road.width * 0.5 + road.shoulder + 0.6
	var n := pts.size()
	var bank: PackedFloat32Array = road.bank
	for i in range(n - 1):
		var a := pts[i]
		var b := pts[i + 1]
		var bk := maxf(absf(bank[i]), absf(bank[i + 1]))
		var ya := y[i] - 0.2
		var yb := y[i + 1] - 0.2
		var f := maxi(flags[i], flags[i + 1])
		if f == 1:
			# bridge: keep the valley, only shape the ground just under the abutments
			continue
		if f == 2:
			# tunnel interior: punch holes where the terrain would intersect the tube
			_raster_segment(a, b, hw + 2.0, func(ix: int, iz: int, t: float, d: float) -> void:
				var k := iz * N + ix
				var yr := lerpf(ya, yb, t)
				if h0[k] < yr + 10.0:
					holes[k] = 1
			)
			continue
		var maxdelta := maxf(absf(th[i] - y[i]), absf(th[i + 1] - y[i + 1]))
		var rad := hw + clampf(maxdelta * 1.7, 6.0, 46.0)
		var minx := clampi(int(floor(to_cell(minf(a.x, b.x) - rad))), 0, N - 1)
		var maxx := clampi(int(ceil(to_cell(maxf(a.x, b.x) + rad))), 0, N - 1)
		var minz := clampi(int(floor(to_cell(minf(a.y, b.y) - rad))), 0, N - 1)
		var maxz := clampi(int(ceil(to_cell(maxf(a.y, b.y) + rad))), 0, N - 1)
		var ab := b - a
		var len2 := maxf(ab.length_squared(), 1e-6)
		for iz in range(minz, maxz + 1):
			var z := ORIGIN + iz * CELL
			var row := iz * N
			for ix in range(minx, maxx + 1):
				var x := ORIGIN + ix * CELL
				var t := clampf(((x - a.x) * ab.x + (z - a.y) * ab.y) / len2, 0.0, 1.0)
				var px := a.x + ab.x * t - x
				var pz := a.y + ab.y * t - z
				var d := sqrt(px * px + pz * pz)
				if d > rad:
					continue
				var k := row + ix
				var yr := ya + (yb - ya) * t - minf(d, hw) * bk
				var w := 1.0
				if d > hw:
					var fall := clampf(absf(h0[k] - yr) * 1.6, 5.0, 44.0)
					w = 1.0 - smoothstep(0.0, fall, d - hw)
				var cur := cw[k]
				if w > cur + 0.0005 or (w > cur - 0.0005 and d < cdist[k]):
					cw[k] = w
					ch[k] = yr
					cdist[k] = d
				if d < hw + 3.0:
					var sw := 1.0 - smoothstep(hw - 1.0, hw + 3.0, d)
					if sw > shoulder_w[k]:
						shoulder_w[k] = sw


func _combine() -> void:
	if OS.get_environment("VELORA_DEBUG_CARVE") != "":
		var loop := _road_by_id("festival_loop")
		for i in [2505, 2521, 541]:
			var p: Vector2 = loop.pts2[i]
			var k := int(round(to_cell(p.y))) * N + int(round(to_cell(p.x)))
			say("carve dbg i=%d road_y=%.2f h0=%.2f cw=%.3f ch=%.2f" % [i, (loop.y as PackedFloat32Array)[i], h0[k], cw[k], ch[k]])
	hgt.resize(N * N)
	for k in N * N:
		var w := cw[k]
		hgt[k] = h0[k] if w <= 0.0 else lerpf(h0[k], ch[k], w)


func _surfaces() -> void:
	surf.resize(N * N)
	for iz in N:
		var z := ORIGIN + iz * CELL
		for ix in N:
			var k := iz * N + ix
			if holes[k] != 0:
				surf[k] = HOLE
				continue
			var x := ORIGIN + ix * CELL
			var h := hgt[k]
			var s := S_GRASS
			if ix > 0 and iz > 0 and ix < N - 1 and iz < N - 1:
				var dx := (hgt[k + 1] - hgt[k - 1]) / (2.0 * CELL)
				var dz := (hgt[k + N] - hgt[k - N]) / (2.0 * CELL)
				var slope := sqrt(dx * dx + dz * dz)
				s = _surface_rule(x, z, h, slope, k)
			surf[k] = s


func _surface_rule(x: float, z: float, h: float, slope: float, k: int) -> int:
	if h < 2.5:
		return S_SAND
	if slope > 0.85:
		return S_ROCK
	if shoulder_w[k] > 0.85:
		return S_GRAVEL
	var w := region_weights(x, z)
	if w.y > 0.5 and h > 380.0:
		return S_SNOW
	if w.y > 0.5 and (h > 320.0 or slope > 0.72):
		return S_ROCK
	if w.z > 0.5:
		return S_SAND if nz_mask.get_noise_2d(x * 2.5, z * 2.5) + nz_detail.get_noise_2d(x, z) * 0.25 > -0.05 else S_DIRT
	if w.w > 0.5 and h < 8.0:
		return S_SAND
	return S_GRASS


# ------------------------------------------------------------------ export
func export_all(dir: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var fa := FileAccess.open(dir + "/height.bin", FileAccess.WRITE)
	fa.store_buffer(hgt.to_byte_array())
	fa.close()
	fa = FileAccess.open(dir + "/surface.bin", FileAccess.WRITE)
	fa.store_buffer(surf)
	fa.close()
	fa = FileAccess.open(dir + "/roaddist.bin", FileAccess.WRITE)
	fa.store_buffer(_final_road_distance())
	fa.close()
	_export_textures(dir)
	var rj: Array = []
	for r in roads:
		var pts: PackedVector2Array = r.pts2
		var y: PackedFloat32Array = r.y
		var flat_pts: Array = []
		for i in pts.size():
			flat_pts.append([snappedf(pts[i].x, 0.01), snappedf(y[i], 0.01), snappedf(pts[i].y, 0.01)])
		var fl: Array = []
		for f in r.flags:
			fl.append(f)
		var bk: Array = []
		for b in r.bank:
			bk.append(snappedf(b, 0.0001))
		rj.append({
			"id": r.id, "name": r.name, "class": r["class"], "closed": r.closed, "width": r.width,
			"lanes": r.lanes, "speed": r.speed, "surface": r.surface, "shoulder": r.shoulder,
			"markings": r.markings, "length": r.length, "points": flat_pts, "flags": fl, "bank": bk,
			"junctions": r.junctions,
		})
	var rv: Array = []
	for p in river_pts:
		rv.append([snappedf(p.x, 0.01), snappedf(p.y, 0.01), snappedf(p.z, 0.01)])
	var pl: Array = []
	for p in places:
		var q: Dictionary = p.duplicate(true)
		q.y = sample_h(hgt, p.pos[0], p.pos[1])
		pl.append(q)
	var world := {"seed": WorldPlan.SEED, "n": N, "cell": CELL, "origin": ORIGIN, "roads": rj, "river": rv, "places": pl,
		"regions": WorldPlan.REGION_NAMES}
	fa = FileAccess.open(dir + "/world.json", FileAccess.WRITE)
	fa.store_string(JSON.stringify(world))
	fa.close()


## Distance (m, clamped 255) from every 4 m cell to the nearest final road edge.
func _final_road_distance() -> PackedByteArray:
	var R := 1025
	var C := 4.0
	var d := PackedFloat32Array()
	d.resize(R * R)
	d.fill(1.0e6)
	for r in roads:
		var pts: PackedVector2Array = r.pts2
		var hw: float = r.width * 0.5 + r.shoulder
		for p in pts:
			var ix := clampi(int(round((p.x - ORIGIN) / C)), 0, R - 1)
			var iz := clampi(int(round((p.y - ORIGIN) / C)), 0, R - 1)
			d[iz * R + ix] = minf(d[iz * R + ix], -hw)
	for k in river_pts.size():
		var rp := river_pts[k]
		var ix2 := clampi(int(round((rp.x - ORIGIN) / C)), 0, R - 1)
		var iz2 := clampi(int(round((rp.z - ORIGIN) / C)), 0, R - 1)
		d[iz2 * R + ix2] = minf(d[iz2 * R + ix2], -9.0)
	var d1 := C
	var d2 := C * 1.4142
	for iz in R:
		for ix in R:
			var i := iz * R + ix
			var v := d[i]
			if ix > 0:
				v = minf(v, d[i - 1] + d1)
			if iz > 0:
				v = minf(v, d[i - R] + d1)
				if ix > 0:
					v = minf(v, d[i - R - 1] + d2)
				if ix < R - 1:
					v = minf(v, d[i - R + 1] + d2)
			d[i] = v
	for iz in range(R - 1, -1, -1):
		for ix in range(R - 1, -1, -1):
			var i := iz * R + ix
			var v := d[i]
			if ix < R - 1:
				v = minf(v, d[i + 1] + d1)
			if iz < R - 1:
				v = minf(v, d[i + R] + d1)
				if ix < R - 1:
					v = minf(v, d[i + R + 1] + d2)
				if ix > 0:
					v = minf(v, d[i + R - 1] + d2)
			d[i] = v
	var out := PackedByteArray()
	out.resize(R * R)
	for i in R * R:
		out[i] = clampi(int(d[i]), 0, 255)
	return out


func _export_textures(dir: String) -> void:
	# splat: R grass, G soil/dirt, B sand, A rock   (2048x2048, one texel per cell)
	# biome: R valley, G highlands, B mesa, A coast (1024x1024)
	var S := N - 1
	var splat := Image.create_empty(S, S, false, Image.FORMAT_RGBA8)
	var data := PackedByteArray()
	data.resize(S * S * 4)
	for iz in S:
		for ix in S:
			var k := iz * N + ix
			var s := surf[k]
			var o := (iz * S + ix) * 4
			var r := 0
			var g := 0
			var b := 0
			var a := 0
			match s:
				S_GRASS:
					r = 255
				S_DIRT:
					g = 255
				S_GRAVEL:
					g = 130
					r = 70
					a = 55
				S_SAND:
					b = 255
				S_ROCK:
					a = 255
				S_SNOW:
					a = 255
				HOLE:
					a = 255
			data[o] = r
			data[o + 1] = g
			data[o + 2] = b
			data[o + 3] = a
	splat.set_data(S, S, false, Image.FORMAT_RGBA8, data)
	# soften the hard per-cell classes so materials blend
	var small := splat.duplicate() as Image
	small.resize(S / 2, S / 2, Image.INTERPOLATE_BILINEAR)
	small.resize(S, S, Image.INTERPOLATE_BILINEAR)
	small.save_png(dir + "/splat.png")
	var B := 1024
	var biome := Image.create_empty(B, B, false, Image.FORMAT_RGBA8)
	for iz in B:
		for ix in B:
			var x := ORIGIN + (ix + 0.5) * 4.0
			var z := ORIGIN + (iz + 0.5) * 4.0
			var w := region_weights(x, z)
			biome.set_pixel(ix, iz, Color(w.x, w.y, w.z, w.w))
	biome.save_png(dir + "/biome.png")


func export_preview(path: String) -> void:
	var P := 1024
	var img := Image.create_empty(P, P, false, Image.FORMAT_RGB8)
	var step := (N - 1) / P
	for py in P:
		for px in P:
			var ix := px * step
			var iz := py * step
			var k := iz * N + ix
			var h := hgt[k]
			var hx := hgt[mini(k + 1, N * N - 1)] - h
			var hz := hgt[mini(k + N, N * N - 1)] - h
			var shade := clampf(0.75 - (hx + hz) * 0.25, 0.25, 1.1)
			var c: Color
			if h < 0.0:
				c = Color(0.1, 0.3, 0.55)
			else:
				match int(surf[k]):
					S_GRASS: c = Color(0.35, 0.55, 0.25)
					S_SAND: c = Color(0.85, 0.75, 0.5)
					S_DIRT: c = Color(0.6, 0.45, 0.3)
					S_ROCK: c = Color(0.5, 0.48, 0.45)
					S_SNOW: c = Color(0.95, 0.95, 1.0)
					S_GRAVEL: c = Color(0.6, 0.6, 0.55)
					HOLE: c = Color(1, 0, 1)
					_: c = Color(0.4, 0.4, 0.4)
				c = c.lerp(Color(1, 1, 1), clampf(h / 600.0, 0.0, 0.4))
			img.set_pixel(px, py, c * shade)
	for r in roads:
		var pts: PackedVector2Array = r.pts2
		var flags: PackedByteArray = r.flags
		for i in pts.size():
			var px := int((pts[i].x - ORIGIN) / 4.0)
			var py := int((pts[i].y - ORIGIN) / 4.0)
			var col := Color(0.1, 0.1, 0.1)
			if r["class"] == "highway":
				col = Color(0.95, 0.85, 0.2)
			elif r["class"] in ["dirt", "gravel", "sand"]:
				col = Color(0.55, 0.3, 0.1)
			if flags[i] == 1:
				col = Color(1, 0.2, 0.2)
			elif flags[i] == 2:
				col = Color(0.8, 0.2, 1.0)
			for oy in range(-1, 2):
				for ox in range(-1, 2):
					var qx := clampi(px + ox, 0, P - 1)
					var qy := clampi(py + oy, 0, P - 1)
					img.set_pixel(qx, qy, col)
	for p in river_pts:
		var px := clampi(int((p.x - ORIGIN) / 4.0), 0, P - 1)
		var py := clampi(int((p.z - ORIGIN) / 4.0), 0, P - 1)
		img.set_pixel(px, py, Color(0.2, 0.5, 1.0))
	for p in places:
		var px := clampi(int((p.pos[0] - ORIGIN) / 4.0), 2, P - 3)
		var py := clampi(int((p.pos[1] - ORIGIN) / 4.0), 2, P - 3)
		for oy in range(-2, 3):
			for ox in range(-2, 3):
				img.set_pixel(px + ox, py + oy, Color(1, 1, 1))
	img.save_png(path)
