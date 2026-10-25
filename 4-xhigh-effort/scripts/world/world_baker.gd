class_name WorldBaker
extends RefCounted
## Seeded world bake for Valoria. Produces res://world/generated/world_data.res and qa/map_preview.png.
## Run offline: godot --headless --path . --script res://tools/world_bake.gd (or automatically on first launch).
## Stages: natural terrain (regions, peaks, mesas, coast) -> river -> POI pads -> road splines ->
## elevation profiles (smoothing, grade limits, junction/crossing pins) -> bridge/tunnel
## classification -> cut/fill carving -> maps (surface, control, detail) -> buildings, trees,
## activities -> save.

const L := preload("res://tools/world/world_layout.gd")
const HALF := 2048.0
const STEP := 2.0
const N := 2049
const N4 := 1025
const M := 1024
const INF := 1e20
const SNOW_LINE := 400.0

var nz := {}
var rng := RandomNumberGenerator.new()
var Hn := PackedFloat32Array()
var H := PackedFloat32Array()
var W4 := [PackedFloat32Array(), PackedFloat32Array(), PackedFloat32Array()]  # desert, mountain, coast at 4 m corners
var water := PackedByteArray()
var best_d := PackedFloat32Array()
var best_h := PackedFloat32Array()
var road_mask := PackedByteArray()   ## 1 near any road footprint incl. bridges and tunnels
var holes := {}
var roads: Array = []
var road_by_id := {}
var river := {}
var pois: Array = []
var _t0 := 0


var progress := 0.0


func bake(write_preview := true) -> WorldData:
	_t0 = Time.get_ticks_msec()
	rng.seed = L.SEED
	_make_noise()
	_log("noise ready")
	_natural_terrain()
	_log("natural terrain")
	_river()
	_log("river")
	for def: Dictionary in L.ROADS:
		_build_road(def)
	_log("road profiles")
	_pois_flat()
	_log("poi pads")
	_carve_roads()
	_log("carving")
	_tunnel_holes()
	var wd := WorldData.new()
	wd.seed = L.SEED
	wd.half = HALF
	wd.step = STEP
	wd.res = N
	var buildings := _place_buildings()
	_log("buildings %d" % buildings.size())
	_maps(wd)
	_log("maps")
	wd.trees = _place_trees(buildings)
	_log("trees")
	wd.heights = H
	var hl := PackedInt32Array()
	for k: int in holes:
		hl.append(k)
	wd.holes = hl
	wd.roads = _export_roads()
	wd.river = river
	wd.pois = pois
	wd.buildings = buildings
	wd.props = _place_props()
	wd.activities = _activities()
	wd.regions = L.REGIONS.duplicate(true)
	wd.spawn = _spawn()
	var total := 0.0
	var lens := {}
	for r: Dictionary in roads:
		total += float(r.length)
		lens[r.id] = snappedf(float(r.length) / 1000.0, 0.01)
	wd.stats = {"road_km": snappedf(total / 1000.0, 0.01), "roads": lens, "buildings": buildings.size()}
	print("ROAD LENGTHS km: ", lens, " total ", snappedf(total / 1000.0, 0.01))
	wd.map_img = _map_image(wd)
	var out_path := WorldData.save_path()
	DirAccess.make_dir_recursive_absolute(out_path.get_base_dir())
	var err := ResourceSaver.save(wd, out_path, ResourceSaver.FLAG_COMPRESS)
	_log("saved %s" % error_string(err))
	if write_preview:
		_preview(wd)
		wd.map_img.save_png("res://qa/map_styled.png")
		_log("preview")
	return wd


func _map_image(wd: WorldData) -> Image:
	var img := Image.create(M, M, false, Image.FORMAT_RGB8)
	for j in M:
		for i in M:
			var gi := (j * 2 + 1) * N + (i * 2 + 1)
			var h := H[gi]
			var shade := 1.0
			if i > 0 and j > 0:
				shade = clampf(1.0 + (H[gi] - H[gi - 2]) * 0.05 + (H[gi] - H[gi - 2 * N]) * 0.05, 0.62, 1.3)
			var c: Color
			if h < 0.2:
				c = Color(0.2, 0.5, 0.66).lerp(Color(0.07, 0.22, 0.42), clampf(-h / 14.0, 0.0, 1.0))
			elif water[gi] == 1:
				c = Color(0.28, 0.58, 0.78)
			else:
				var ctl := wd.control_img.get_pixel(i, j)
				var det := wd.detail_img.get_pixel(i, j)
				c = Color(0.4, 0.58, 0.28).lerp(Color(0.86, 0.56, 0.34), ctl.r).lerp(Color(0.52, 0.56, 0.47), ctl.g).lerp(Color(0.66, 0.68, 0.42), ctl.b * 0.7)
				if ctl.a > 0.05:
					c = c.lerp(Color(0.62, 0.62, 0.32), 0.35)
				c = c.lerp(Color(0.25, 0.42, 0.2), det.g * 0.45)
				c = c.lerp(Color(0.9, 0.84, 0.66), det.b * 0.8)
				c = c.lerp(Color(0.97, 0.98, 1.0), det.a)
				c = c * shade
			img.set_pixel(i, j, c)
	var cols := {"highway": [Color(1.0, 0.8, 0.22), 2], "regional": [Color(1, 1, 1), 1], "mountain": [Color(1, 0.95, 0.9), 1],
		"village": [Color(0.93, 0.93, 0.95), 1], "gravel": [Color(0.86, 0.78, 0.6), 0], "dirt": [Color(0.82, 0.68, 0.5), 0]}
	for pass_i in 2:
		for r: Dictionary in roads:
			var spec: Array = cols[r["class"]]
			var rad: int = int(spec[1]) + (1 if pass_i == 0 else 0)
			var col: Color = Color(0.1, 0.1, 0.12) if pass_i == 0 else spec[0]
			if pass_i == 0 and rad == 1 and String(r["class"]) in ["gravel", "dirt"]:
				rad = 0
			var p: PackedVector2Array = r.p2
			for k in range(0, p.size(), 2):
				var px := int((p[k].x + HALF) / 4.0)
				var pz := int((p[k].y + HALF) / 4.0)
				for oy in range(-rad, rad + 1):
					for ox in range(-rad, rad + 1):
						var x := px + ox
						var y := pz + oy
						if x >= 0 and y >= 0 and x < M and y < M:
							img.set_pixel(x, y, col)
	img.generate_mipmaps()
	return img


func _log(s: String) -> void:
	print("[%6.1fs] %s" % [(Time.get_ticks_msec() - _t0) / 1000.0, s])


# ------------------------------------------------------------------ noise
func _nl(seed_off: int, freq: float, oct: int, fractal := FastNoiseLite.FRACTAL_FBM, type := FastNoiseLite.TYPE_SIMPLEX_SMOOTH) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.seed = L.SEED + seed_off
	n.noise_type = type
	n.frequency = freq
	n.fractal_type = fractal
	n.fractal_octaves = oct
	return n


func _make_noise() -> void:
	nz.warp = _nl(1, 1.0 / 1100.0, 2)
	nz.low = _nl(2, 1.0 / 1300.0, 4)
	nz.mid = _nl(3, 1.0 / 380.0, 4)
	nz.detail = _nl(4, 1.0 / 90.0, 3)
	nz.ridge = _nl(5, 1.0 / 620.0, 5, FastNoiseLite.FRACTAL_RIDGED)
	nz.mesa = _nl(6, 1.0 / 430.0, 3)
	nz.canyon = _nl(7, 1.0 / 800.0, 3, FastNoiseLite.FRACTAL_RIDGED)
	nz.coast = _nl(8, 1.0 / 260.0, 3)
	nz.forest = _nl(9, 1.0 / 260.0, 3)
	nz.field = _nl(10, 1.0 / 95.0, 1, FastNoiseLite.FRACTAL_NONE, FastNoiseLite.TYPE_CELLULAR)
	(nz.field as FastNoiseLite).cellular_return_type = FastNoiseLite.RETURN_CELL_VALUE
	(nz.field as FastNoiseLite).cellular_jitter = 0.75
	nz.field_edge = _nl(10, 1.0 / 95.0, 1, FastNoiseLite.FRACTAL_NONE, FastNoiseLite.TYPE_CELLULAR)
	(nz.field_edge as FastNoiseLite).cellular_return_type = FastNoiseLite.RETURN_DISTANCE2_SUB
	(nz.field_edge as FastNoiseLite).cellular_jitter = 0.75
	nz.snow = _nl(11, 1.0 / 60.0, 3)
	nz.dune = _nl(12, 1.0 / 220.0, 2)


static func _ss(e0: float, e1: float, x: float) -> float:
	var t := clampf((x - e0) / (e1 - e0), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


func _coast_x(z: float) -> float:
	var c: Array = L.COAST
	var x := float(c[c.size() - 1][1])
	for i in range(1, c.size()):
		if z <= float(c[i][0]):
			var a: Array = c[i - 1]
			var b: Array = c[i]
			var t := (z - float(a[0])) / (float(b[0]) - float(a[0]))
			t = t * t * (3.0 - 2.0 * t)
			x = lerpf(float(a[1]), float(b[1]), t)
			break
	return x + (nz.coast as FastNoiseLite).get_noise_1d(z) * 45.0


func _beach(z: float) -> float:
	var w := 0.0
	for b: Array in L.BEACHES:
		w = maxf(w, _ss(float(b[0]) - 90.0, float(b[0]) + 30.0, z) * _ss(float(b[1]) + 90.0, float(b[1]) - 30.0, z))
	return w


## natural height and region weights (desert, mountain, coast) at a point
func _natural(x: float, z: float) -> Vector4:
	var warp: FastNoiseLite = nz.warp
	var wx := x + warp.get_noise_2d(x, z) * 240.0
	var wz := z + warp.get_noise_2d(x + 5000.0, z - 3000.0) * 240.0
	var dm := Vector2(wx, wz).distance_to(L.MOUNTAIN_CENTER)
	var dd := Vector2(wx, wz).distance_to(L.DESERT_CENTER)
	var s := _coast_x(z) - x
	var w_m := _ss(1200.0, 600.0, dm)
	var w_d := _ss(1260.0, 690.0, dd)
	var w_c := _ss(780.0, 380.0, s + warp.get_noise_2d(x * 0.7, z * 0.7) * 120.0)
	var tot := w_m + w_d + w_c
	if tot > 1.0:
		w_m /= tot
		w_d /= tot
		w_c /= tot
	var w_f := 1.0 - w_m - w_d - w_c
	var lo := (nz.low as FastNoiseLite).get_noise_2d(x, z)
	var mid := (nz.mid as FastNoiseLite).get_noise_2d(x, z)
	var hf := 34.0 + 16.0 * lo + 8.0 * mid + 72.0 * _ss(-1000.0, -1560.0, x) * _ss(1500.0, 1100.0, z)
	var h := hf * w_f
	if w_m > 0.0:
		var peaks := 0.0
		for p: Array in L.PEAKS:
			var ddx := x - float(p[0])
			var ddz := z - float(p[1])
			var r := float(p[3])
			peaks += float(p[2]) * exp(-(ddx * ddx + ddz * ddz) / (r * r))
		var ridge := (nz.ridge as FastNoiseLite).get_noise_2d(x, z) * 0.5 + 0.5
		h += (80.0 + peaks + 30.0 * ridge + 10.0 * mid) * w_m
	if w_d > 0.0:
		var hd := 104.0 + 8.0 * mid + 6.0 * lo
		var mesa := (nz.mesa as FastNoiseLite).get_noise_2d(x, z)
		hd += 72.0 * _ss(L.MESA_THRESHOLD, L.MESA_THRESHOLD + 0.06, mesa)
		var can := (nz.canyon as FastNoiseLite).get_noise_2d(x, z) * 0.5 + 0.5
		hd -= 44.0 * _ss(L.CANYON_THRESHOLD, L.CANYON_THRESHOLD + 0.09, can)
		hd = lerpf(hd, roundf(hd / 9.0) * 9.0, 0.3)
		h += hd * w_d
	if w_c > 0.0:
		h += (42.0 + 20.0 * lo + 8.0 * mid) * w_c
	if s < 320.0:
		var bw := _beach(z)
		var cliff := lerpf(-5.0, h, pow(_ss(0.0, 150.0, s), 0.4))
		var beach := lerpf(-1.8, h, _ss(-30.0, 300.0, s))
		var hs := lerpf(cliff, beach, bw)
		h = lerpf(hs, h, _ss(220.0, 320.0, s))
		if s < 0.0:
			h = minf(h, lerpf(-1.5, -22.0, _ss(0.0, -380.0, s)))
	return Vector4(h, w_d, w_m, w_c)


func _natural_terrain() -> void:
	var h4 := PackedFloat32Array()
	h4.resize(N4 * N4)
	var wd := PackedFloat32Array()
	var wm := PackedFloat32Array()
	var wc := PackedFloat32Array()
	wd.resize(N4 * N4)
	wm.resize(N4 * N4)
	wc.resize(N4 * N4)
	for j in N4:
		var z := -HALF + 4.0 * j
		for i in N4:
			var x := -HALF + 4.0 * i
			var v := _natural(x, z)
			var idx := j * N4 + i
			h4[idx] = v.x
			wd[idx] = v.y
			wm[idx] = v.z
			wc[idx] = v.w
	W4[0] = wd
	W4[1] = wm
	W4[2] = wc
	Hn.resize(N * N)
	water.resize(N * N)
	var det: FastNoiseLite = nz.detail
	for j in N:
		var z := -HALF + STEP * j
		var j4 := j >> 1
		var tz := 0.5 if (j & 1) else 0.0
		var j4b := mini(j4 + 1, N4 - 1)
		for i in N:
			var i4 := i >> 1
			var tx := 0.5 if (i & 1) else 0.0
			var i4b := mini(i4 + 1, N4 - 1)
			var a := lerpf(h4[j4 * N4 + i4], h4[j4 * N4 + i4b], tx)
			var b := lerpf(h4[j4b * N4 + i4], h4[j4b * N4 + i4b], tx)
			var x := -HALF + STEP * i
			var h := lerpf(a, b, tz)
			# fine detail fades out on the sea floor and on very flat fields
			h += det.get_noise_2d(x, z) * 1.6
			Hn[j * N + i] = h
			if h < 0.0:
				water[j * N + i] = 2


func _w4(x: float, z: float, k: int) -> float:
	var i := clampi(int(roundf((x + HALF) / 4.0)), 0, N4 - 1)
	var j := clampi(int(roundf((z + HALF) / 4.0)), 0, N4 - 1)
	return (W4[k] as PackedFloat32Array)[j * N4 + i]


func hn_at(x: float, z: float) -> float:
	return _bilinear(Hn, x, z)


func _bilinear(arr: PackedFloat32Array, x: float, z: float) -> float:
	var fx := clampf((x + HALF) / STEP, 0.0, N - 1.001)
	var fz := clampf((z + HALF) / STEP, 0.0, N - 1.001)
	var ix := int(fx)
	var iz := int(fz)
	var tx := fx - ix
	var tz := fz - iz
	var i0 := iz * N + ix
	return lerpf(lerpf(arr[i0], arr[i0 + 1], tx), lerpf(arr[i0 + N], arr[i0 + N + 1], tx), tz)


# ------------------------------------------------------------------ splines
func _catmull(ctrl: PackedVector2Array, closed: bool, spacing: float) -> PackedVector2Array:
	var pts := ctrl
	var n := pts.size()
	var dense := PackedVector2Array()
	var segs := n if closed else n - 1
	for i in segs:
		var p0 := pts[(i - 1 + n) % n] if (closed or i > 0) else pts[0] * 2.0 - pts[1]
		var p1 := pts[i]
		var p2 := pts[(i + 1) % n]
		var p3 := pts[(i + 2) % n] if (closed or i + 2 < n) else pts[n - 1] * 2.0 - pts[n - 2]
		# centripetal parameterisation
		var t0 := 0.0
		var t1 := t0 + pow(p0.distance_to(p1), 0.5) + 1e-4
		var t2 := t1 + pow(p1.distance_to(p2), 0.5) + 1e-4
		var t3 := t2 + pow(p2.distance_to(p3), 0.5) + 1e-4
		var steps := maxi(8, int(p1.distance_to(p2) / 1.0))
		for k in steps:
			var t := lerpf(t1, t2, float(k) / steps)
			var a1 := p0 * ((t1 - t) / (t1 - t0)) + p1 * ((t - t0) / (t1 - t0))
			var a2 := p1 * ((t2 - t) / (t2 - t1)) + p2 * ((t - t1) / (t2 - t1))
			var a3 := p2 * ((t3 - t) / (t3 - t2)) + p3 * ((t - t2) / (t3 - t2))
			var b1 := a1 * ((t2 - t) / (t2 - t0)) + a2 * ((t - t0) / (t2 - t0))
			var b2 := a2 * ((t3 - t) / (t3 - t1)) + a3 * ((t - t1) / (t3 - t1))
			dense.append(b1 * ((t2 - t) / (t2 - t1)) + b2 * ((t - t1) / (t2 - t1)))
	if not closed:
		dense.append(pts[n - 1])
	# resample to equal arc length
	var out := PackedVector2Array()
	out.append(dense[0])
	var acc := 0.0
	var prev := dense[0]
	var m := dense.size()
	var limit := m + (1 if closed else 0)
	for k in range(1, limit):
		var cur := dense[k % m]
		var seg := prev.distance_to(cur)
		while acc + seg >= spacing:
			var t := (spacing - acc) / seg
			var np := prev.lerp(cur, t)
			out.append(np)
			seg -= prev.distance_to(np)
			prev = np
			acc = 0.0
		acc += seg
		prev = cur
	if not closed and out[out.size() - 1].distance_to(pts[n - 1]) > 0.5:
		out.append(pts[n - 1])
	if closed and out[out.size() - 1].distance_to(out[0]) < spacing * 0.5:
		out.remove_at(out.size() - 1)
	return out


func _switchbacks(a: Vector2, b: Vector2, legs: int, width: float, radius: float) -> PackedVector2Array:
	var along := (b - a).normalized()
	var perp := Vector2(-along.y, along.x)
	var D := a.distance_to(b)
	var out := PackedVector2Array()
	for k in range(1, legs):
		var side := 1.0 if k % 2 == 1 else -1.0
		var base := a + along * (D * k / legs)
		var apex := base + perp * side * width * 0.5
		var c := apex - perp * side * radius
		for q in 5:
			var th := lerpf(-PI / 2.0, PI / 2.0, q / 4.0)
			out.append(c + perp * side * radius * cos(th) + along * radius * sin(th))
	out.append(b)
	return out


func _ctrl_points(def: Dictionary) -> PackedVector2Array:
	var ctrl := PackedVector2Array()
	for p: Variant in def.pts:
		if p is Dictionary:
			var lad: Dictionary = p
			var a := ctrl[ctrl.size() - 1]
			ctrl.append_array(_switchbacks(a, Vector2(lad.ladder[0], lad.ladder[1]), int(lad.legs), float(lad.width), float(lad.radius)))
		else:
			var arr: Array = p
			var b := Vector2(arr[0], arr[1])
			if arr.size() >= 4 and ctrl.size() > 0:
				ctrl.append_array(_meander(ctrl[ctrl.size() - 1], b, float(arr[2]), float(arr[3])))
			else:
				ctrl.append(b)
	return ctrl


func _meander(a: Vector2, b: Vector2, amp: float, wl: float) -> PackedVector2Array:
	var d := a.distance_to(b)
	var dir := (b - a) / d
	var perp := Vector2(-dir.y, dir.x)
	var n := maxi(2, int(d / (wl / 6.0)))
	var out := PackedVector2Array()
	for k in range(1, n):
		var t := float(k) / n
		var s := t * d
		out.append(a + dir * s + perp * amp * sin(TAU * s / wl) * sin(PI * t))
	out.append(b)
	return out


# ------------------------------------------------------------------ roads
func _nearest_on(r: Dictionary, p: Vector2) -> int:
	var pts: PackedVector2Array = r.p2
	var best := 0
	var bd := INF
	for i in pts.size():
		var d := pts[i].distance_squared_to(p)
		if d < bd:
			bd = d
			best = i
	return best


func _build_road(def: Dictionary) -> void:
	var cls: Dictionary = L.ROAD_CLASSES[def["class"]]
	var r := {"id": def.id, "name": def.name, "class": def["class"], "closed": def.get("closed", false),
		"lanes": cls.lanes, "lane_w": cls.lane_w, "shoulder": cls.shoulder, "median": cls.median,
		"speed": cls.speed, "surface": cls.surface, "scenic": def.get("scenic", false), "junctions": [],
		"traffic": cls.traffic}
	r.half_w = float(cls.lanes) * float(cls.lane_w) + float(cls.shoulder) + float(cls.median) * 0.5
	var ctrl := _ctrl_points(def)
	var pins := []  # [sample_index, elevation]
	if def.has("start_on"):
		var parent: Dictionary = road_by_id[def.start_on]
		var k := _nearest_on(parent, ctrl[0])
		ctrl[0] = (parent.p2 as PackedVector2Array)[k]
		r.start_on = {"road": def.start_on, "s": k * STEP}
	if def.has("end_on"):
		var parent: Dictionary = road_by_id[def.end_on]
		var k := _nearest_on(parent, ctrl[ctrl.size() - 1])
		ctrl[ctrl.size() - 1] = (parent.p2 as PackedVector2Array)[k]
		r.end_on = {"road": def.end_on, "s": k * STEP}
	var p2 := _catmull(ctrl, bool(r.closed), STEP)
	var n := p2.size()
	r.p2 = p2
	r.length = n * STEP if r.closed else (n - 1) * STEP
	# natural heights and water along the road
	var hn := PackedFloat32Array()
	hn.resize(n)
	var wet := PackedByteArray()
	wet.resize(n)
	for i in n:
		var p := p2[i]
		hn[i] = hn_at(p.x, p.y)
		var gi := _grid_index(p.x, p.y)
		var wmax := 0
		for o: Vector2i in [Vector2i(0, 0), Vector2i(6, 0), Vector2i(-6, 0), Vector2i(0, 6), Vector2i(0, -6), Vector2i(3, 3), Vector2i(-3, -3), Vector2i(3, -3), Vector2i(-3, 3)]:
			var gj := gi + o.y * N + o.x
			if gj >= 0 and gj < N * N:
				wmax = maxi(wmax, water[gj])
		wet[i] = wmax
	var y := hn.duplicate()
	var closed: bool = r.closed
	var win := int(float(cls.smooth) / STEP / 2.0)
	for _pass in 3:
		y = _box(y, win, closed)
	# junction pins
	if r.has("start_on"):
		var parent: Dictionary = road_by_id[r.start_on.road]
		pins.append([0, _road_y(parent, float(r.start_on.s))])
		_add_junction(r, 0.0, parent, float(r.start_on.s), "T")
	if r.has("end_on"):
		var parent: Dictionary = road_by_id[r.end_on.road]
		pins.append([n - 1, _road_y(parent, float(r.end_on.s))])
		_add_junction(r, (n - 1) * STEP, parent, float(r.end_on.s), "T")
	# crossings with earlier roads
	for other: Dictionary in roads:
		for c: Array in _crossings(r, other):
			var i: int = c[0]
			var os: float = c[1]
			var oy := _road_y(other, os)
			if _near_junction(r, i * STEP) or _near_junction(other, os):
				continue
			if def.get("overpass", false):
				pins.append([i, oy + 7.6])
				print("  overpass: %s over %s at s=%d" % [r.id, other.id, i * STEP])
			elif other.get("overpass_road", false):
				pins.append([i, oy - 7.4])
				var ok: PackedByteArray = other.kind
				var oi := int(os / STEP)
				for d in range(-int((r.half_w + 8.0) / STEP), int((r.half_w + 8.0) / STEP) + 1):
					var idx := oi + d
					if idx >= 0 and idx < ok.size():
						ok[idx] = 1
				other.kind = ok
				print("  underpass: %s under %s at s=%d" % [r.id, other.id, i * STEP])
			else:
				pins.append([i, oy])
				_add_junction(r, i * STEP, other, os, "X")
				print("  X-junction: %s x %s at s=%d" % [r.id, other.id, i * STEP])
	if def.get("overpass", false):
		r.overpass_road = true
	# water clearance
	for i in n:
		if wet[i] > 0:
			y[i] = maxf(y[i], (river_level_at(p2[i]) if wet[i] == 1 else 0.0) + 5.5)
	y = _apply_pins(y, pins, closed)
	var g := float(cls.grade)
	# grade-limited profile between the lower and upper Lipschitz envelopes of the target,
	# biased low so infeasible stretches become cuttings rather than long viaducts
	var lo := _envelope(y, g * STEP, closed, true)
	var hi := _envelope(y, g * STEP, closed, false)
	var bias := 0.0 if def.get("allow_tunnel", false) else 0.35
	for i in n:
		y[i] = lerpf(lo[i], hi[i], bias)
	for i in n:
		if wet[i] > 0:
			y[i] = maxf(y[i], (river_level_at(p2[i]) if wet[i] == 1 else 0.0) + 5.5)
	y = _apply_pins(y, pins, closed, true)
	for _it in 3:
		for i in range(1, n):
			y[i] = clampf(y[i], y[i - 1] - g * STEP, y[i - 1] + g * STEP)
		for i in range(n - 2, -1, -1):
			y[i] = clampf(y[i], y[i + 1] - g * STEP, y[i + 1] + g * STEP)
		y = _apply_pins(y, pins, closed, true)
	# vertical curves: smooth grade breaks so crests stay drivable at the design speed
	var vwin := maxi(6, int(float(cls.smooth) * 0.25 / STEP))
	y = _box(_box(y, vwin, closed), vwin, closed)
	y = _apply_pins(y, pins, closed, true)
	# classify
	var kind := PackedByteArray()
	kind.resize(n)
	var allow_tunnel: bool = def.get("allow_tunnel", false)
	for i in n:
		var d := y[i] - hn[i]
		if wet[i] > 0 or d > 9.0:
			kind[i] = 1
		elif allow_tunnel and -d > 15.0:
			kind[i] = 2
	kind = _clean_runs(kind, 1, 8)
	kind = _clean_runs(kind, 2, 40)
	r.y = y
	r.hn = hn
	r.kind = kind
	r.bank = _banking(p2, closed, float(cls.bank), float(cls.speed))
	roads.append(r)
	road_by_id[r.id] = r
	var nb := 0
	var nt := 0
	for k in kind:
		if k == 1:
			nb += 1
		elif k == 2:
			nt += 1
	var maxcut := 0.0
	var maxfill := 0.0
	for i in n:
		if kind[i] == 0:
			maxcut = maxf(maxcut, hn[i] - y[i])
			maxfill = maxf(maxfill, y[i] - hn[i])
	print("road %-11s %6.0f m  y %4.0f..%4.0f  bridge %4.0f m  tunnel %4.0f m  maxcut %4.1f  maxfill %4.1f" % [
		r.id, r.length, _min(y), _max(y), nb * STEP, nt * STEP, maxcut, maxfill])
	if OS.get_cmdline_user_args().has("--diag"):
		var line := "   "
		for i in range(0, n, 100):
			line += " %d:%d/%d%s" % [i * 2, roundi(hn[i]), roundi(y[i]), "B" if kind[i] == 1 else ("T" if kind[i] == 2 else "")]
		print(line)


func _min(a: PackedFloat32Array) -> float:
	var m := INF
	for v in a:
		m = minf(m, v)
	return m


func _max(a: PackedFloat32Array) -> float:
	var m := -INF
	for v in a:
		m = maxf(m, v)
	return m


func _grid_index(x: float, z: float) -> int:
	var i := clampi(int(roundf((x + HALF) / STEP)), 0, N - 1)
	var j := clampi(int(roundf((z + HALF) / STEP)), 0, N - 1)
	return j * N + i


func _road_y(r: Dictionary, s: float) -> float:
	var y: PackedFloat32Array = r.y
	var i := clampi(int(s / STEP), 0, y.size() - 1)
	return y[i]


func _add_junction(r: Dictionary, s: float, other: Dictionary, os: float, type: String) -> void:
	(r.junctions as Array).append({"s": s, "other": other.id, "other_s": os, "type": type})
	(other.junctions as Array).append({"s": os, "other": r.id, "other_s": s, "type": type})


func _near_junction(r: Dictionary, s: float) -> bool:
	for j: Dictionary in r.junctions:
		if absf(float(j.s) - s) < 40.0:
			return true
	if r.has("start_on") and s < 40.0:
		return true
	if r.has("end_on") and float(r.length) - s < 40.0:
		return true
	return false


func _crossings(a: Dictionary, b: Dictionary) -> Array:
	var pa: PackedVector2Array = a.p2
	var pb: PackedVector2Array = b.p2
	var grid := {}
	var cell := 64.0
	for j in range(pb.size() - 1):
		var key := Vector2i(int(floor(pb[j].x / cell)), int(floor(pb[j].y / cell)))
		if not grid.has(key):
			grid[key] = []
		(grid[key] as Array).append(j)
	var out := []
	var last := -1000
	for i in range(pa.size() - 1):
		var key := Vector2i(int(floor(pa[i].x / cell)), int(floor(pa[i].y / cell)))
		for ox in range(-1, 2):
			for oz in range(-1, 2):
				var k2 := key + Vector2i(ox, oz)
				if not grid.has(k2):
					continue
				for j: int in grid[k2]:
					var hit: Variant = Geometry2D.segment_intersects_segment(pa[i], pa[i + 1], pb[j], pb[j + 1])
					if hit != null and i - last > 20:
						out.append([i, j * STEP])
						last = i
	return out


func _box(a: PackedFloat32Array, r: int, closed: bool) -> PackedFloat32Array:
	var n := a.size()
	if r <= 0 or n < 3:
		return a
	var out := PackedFloat32Array()
	out.resize(n)
	var pre := PackedFloat64Array()
	pre.resize(n + 1)
	pre[0] = 0.0
	for i in n:
		pre[i + 1] = pre[i] + a[i]
	for i in n:
		if closed:
			var s := 0.0
			for k in range(-r, r + 1):
				s += a[(i + k + n) % n]
			out[i] = s / (2 * r + 1)
		else:
			var lo := maxi(0, i - r)
			var hi := mini(n - 1, i + r)
			out[i] = (pre[hi + 1] - pre[lo]) / (hi - lo + 1)
	return out


## Largest (lower=true) / smallest (lower=false) slope-limited function below / above a.
func _envelope(a: PackedFloat32Array, d: float, closed: bool, lower: bool) -> PackedFloat32Array:
	var n := a.size()
	var e := a.duplicate()
	var rounds := 2 if closed else 1
	for _r in rounds:
		for k in range(1, n * (2 if closed else 1)):
			var i := k % n
			var p := (k - 1) % n
			e[i] = minf(e[i], e[p] + d) if lower else maxf(e[i], e[p] - d)
		for k in range(n * (2 if closed else 1) - 2, -1, -1):
			var i := k % n
			var q := (k + 1) % n
			e[i] = minf(e[i], e[q] + d) if lower else maxf(e[i], e[q] - d)
	return e


func _apply_pins(y: PackedFloat32Array, pins: Array, closed: bool, hard := false) -> PackedFloat32Array:
	var n := y.size()
	var span := 70
	for p: Array in pins:
		var i: int = p[0]
		var target: float = p[1]
		var delta := target - y[i]
		for k in range(-span, span + 1):
			var idx := i + k
			if closed:
				idx = (idx + n) % n
			elif idx < 0 or idx >= n:
				continue
			var w := 1.0 - _ss(0.0, float(span), absf(k))
			y[idx] += delta * w if not hard else delta * w * w
		y[i] = target
	return y


func _clean_runs(kind: PackedByteArray, v: int, min_len: int) -> PackedByteArray:
	var n := kind.size()
	var i := 0
	while i < n:
		if kind[i] == v:
			var j := i
			while j < n and kind[j] == v:
				j += 1
			if j - i < min_len:
				for k in range(i, j):
					kind[k] = 0
			i = j
		else:
			i += 1
	return kind


func _banking(p: PackedVector2Array, closed: bool, max_deg: float, speed_kmh: float) -> PackedFloat32Array:
	var n := p.size()
	var bank := PackedFloat32Array()
	bank.resize(n)
	var v := speed_kmh / 3.6
	for i in n:
		var a := p[(i - 3 + n) % n] if (closed or i >= 3) else p[0]
		var b := p[i]
		var c := p[(i + 3) % n] if (closed or i + 3 < n) else p[n - 1]
		var t1 := (b - a).normalized()
		var t2 := (c - b).normalized()
		var cr := t1.x * t2.y - t1.y * t2.x
		var curv := cr / maxf(a.distance_to(c) * 0.5, 0.5)
		bank[i] = clampf(curv * v * v / 9.81 * 0.35, -deg_to_rad(max_deg), deg_to_rad(max_deg))
	return _box(_box(bank, 8, closed), 8, closed)


# ------------------------------------------------------------------ river
func river_level_at(p: Vector2) -> float:
	var pts: PackedVector2Array = river.p2
	var lv: PackedFloat32Array = river.level
	var best := 0
	var bd := INF
	for i in range(0, pts.size(), 2):
		var d := pts[i].distance_squared_to(p)
		if d < bd:
			bd = d
			best = i
	return lv[best]


func _river() -> void:
	var ctrl := PackedVector2Array()
	for p: Array in L.RIVER:
		ctrl.append(Vector2(p[0], p[1]))
	var p2 := _catmull(ctrl, false, 4.0)
	var n := p2.size()
	var h := PackedFloat32Array()
	h.resize(n)
	for i in n:
		h[i] = hn_at(p2[i].x, p2[i].y)
	h = _box(_box(h, 20, false), 20, false)
	var level := PackedFloat32Array()
	level.resize(n)
	level[0] = h[0] - 1.5
	for i in range(1, n):
		level[i] = minf(level[i - 1] - 0.004, h[i] - 1.5)
	# finish at sea level
	for i in n:
		level[i] = maxf(level[i], 0.25)
	var widths := PackedFloat32Array()
	widths.resize(n)
	for i in n:
		widths[i] = lerpf(7.0, 15.0, float(i) / n)
	river = {"p2": p2, "level": level, "width": widths}
	# carve bed (only lowers terrain)
	for i in range(0, n - 1):
		var a := p2[i]
		var b := p2[i + 1]
		var hw := widths[i]
		var R := hw + 30.0
		var i0 := maxi(0, int((minf(a.x, b.x) - R + HALF) / STEP))
		var i1 := mini(N - 1, int((maxf(a.x, b.x) + R + HALF) / STEP) + 1)
		var j0 := maxi(0, int((minf(a.y, b.y) - R + HALF) / STEP))
		var j1 := mini(N - 1, int((maxf(a.y, b.y) + R + HALF) / STEP) + 1)
		var ab := b - a
		var ll := ab.length_squared()
		for j in range(j0, j1 + 1):
			var z := -HALF + j * STEP
			for ii in range(i0, i1 + 1):
				var x := -HALF + ii * STEP
				var t := clampf(((x - a.x) * ab.x + (z - a.y) * ab.y) / ll, 0.0, 1.0)
				var d := Vector2(x, z).distance_to(a + ab * t)
				if d > R:
					continue
				var lvl := lerpf(level[i], level[i + 1], t)
				var target: float
				if d < hw:
					target = lvl - 2.2 + (d / hw) * (d / hw) * 2.0
				else:
					target = lerpf(lvl + 0.4, Hn[j * N + ii], _ss(hw, R, d))
				var idx := j * N + ii
				if target < Hn[idx]:
					Hn[idx] = target
				if d < hw + 1.0:
					water[idx] = 1


# ------------------------------------------------------------------ POIs
func _pois_flat() -> void:
	for p: Dictionary in L.POIS:
		var pos := Vector2(p.pos[0], p.pos[1])
		var y := hn_at(pos.x, pos.y)
		# pads sit at the height of the nearest road so access is level
		var best := INF
		for r: Dictionary in roads:
			var k := _nearest_on(r, pos)
			var dd := (r.p2 as PackedVector2Array)[k].distance_to(pos)
			if dd < best and dd < float(p.flat) + 80.0:
				best = dd
				y = (r.y as PackedFloat32Array)[k] - 0.2
		var flat := float(p.flat)
		pois.append({"id": p.id, "name": p.name, "type": p.type, "pos": Vector3(pos.x, y, pos.y), "region": p.region, "flat": flat})
		if flat <= 0.0:
			continue
		var R := flat + 30.0
		for j in range(maxi(0, int((pos.y - R + HALF) / STEP)), mini(N, int((pos.y + R + HALF) / STEP) + 1)):
			for i in range(maxi(0, int((pos.x - R + HALF) / STEP)), mini(N, int((pos.x + R + HALF) / STEP) + 1)):
				var d := Vector2(-HALF + i * STEP, -HALF + j * STEP).distance_to(pos)
				if d < R:
					var idx := j * N + i
					Hn[idx] = lerpf(y, Hn[idx], _ss(flat, R, d))


# ------------------------------------------------------------------ carving
func _carve_roads() -> void:
	H = Hn.duplicate()
	best_d.resize(N * N)
	best_d.fill(INF)
	best_h.resize(N * N)
	var owner := PackedInt32Array()
	owner.resize(N * N)
	owner.fill(-1)
	road_mask.resize(N * N)
	for rr: Dictionary in roads:
		var pp: PackedVector2Array = rr.p2
		var rad := int(ceil((float(rr.half_w) + 4.0) / STEP))
		for q in pp.size():
			var ci := int(roundf((pp[q].x + HALF) / STEP))
			var cj := int(roundf((pp[q].y + HALF) / STEP))
			for dj in range(-rad, rad + 1):
				var jj := cj + dj
				if jj < 0 or jj >= N:
					continue
				for di in range(-rad, rad + 1):
					var ii := ci + di
					if ii >= 0 and ii < N and di * di + dj * dj <= rad * rad:
						road_mask[jj * N + ii] = 1
	for ri in roads.size():
		var r: Dictionary = roads[ri]
		var p: PackedVector2Array = r.p2
		var y: PackedFloat32Array = r.y
		var kind: PackedByteArray = r.kind
		var bank: PackedFloat32Array = r.bank
		var hn: PackedFloat32Array = r.hn
		var n := p.size()
		var core := float(r.half_w) + 0.9
		var closed: bool = r.closed
		var segs := n if closed else n - 1
		var k := 0
		while k < segs:
			var k2 := mini(k + 2, n - 1 if not closed else k + 2)
			var ia := k % n
			var ib := k2 % n
			var skip := false
			for q in range(k, k2 + 1):
				if kind[q % n] != 0:
					skip = true
			if skip:
				k += 2
				continue
			# never stamp past a segment end that borders a tunnel or a bridge (abutments stay crisp)
			var clip_lo := kind[(k - 1 + n) % n] != 0 if (closed or k > 0) else false
			var clip_hi := kind[(k2 + 1) % n] != 0 if (closed or k2 + 1 < n) else false
			var a := p[ia]
			var b := p[ib]
			var ya := y[ia]
			var yb := y[ib]
			var dev := maxf(absf(hn[ia] - ya), absf(hn[ib] - yb))
			var R := core + clampf(dev * 1.6 + 6.0, 6.0, 46.0)
			var ab := b - a
			var ll := maxf(ab.length_squared(), 0.0001)
			var len := sqrt(ll)
			var dir := ab / len
			var right := Vector2(-dir.y, dir.x)
			var ta := tan(bank[ia])
			var tb := tan(bank[ib])
			var i0 := maxi(0, int((minf(a.x, b.x) - R + HALF) / STEP))
			var i1 := mini(N - 1, int((maxf(a.x, b.x) + R + HALF) / STEP) + 1)
			var j0 := maxi(0, int((minf(a.y, b.y) - R + HALF) / STEP))
			var j1 := mini(N - 1, int((maxf(a.y, b.y) + R + HALF) / STEP) + 1)
			for j in range(j0, j1 + 1):
				var z := -HALF + j * STEP
				var row := j * N
				for i in range(i0, i1 + 1):
					var x := -HALF + i * STEP
					var rx := x - a.x
					var rz := z - a.y
					var traw := (rx * ab.x + rz * ab.y) / ll
					if (clip_lo and traw < 0.0) or (clip_hi and traw > 1.0):
						continue
					var t := clampf(traw, 0.0, 1.0)
					var cx := a.x + ab.x * t
					var cz := a.y + ab.y * t
					var dx := x - cx
					var dz := z - cz
					var d := sqrt(dx * dx + dz * dz)
					if d > R:
						continue
					var dd := d - core
					var idx := row + i
					if dd >= best_d[idx]:
						continue
					# cells inside an earlier road's core stay with that road (junction mouths)
					if best_d[idx] <= 0.0 and owner[idx] != ri:
						continue
					var u := rx * right.x + rz * right.y
					var yc := lerpf(ya, yb, t) - clampf(u, -core, core) * lerpf(ta, tb, t) - 0.24
					var target := yc
					if dd > 0.0:
						var hh := Hn[idx]
						var blend := clampf(absf(hh - yc) * 1.6, 3.0, 46.0)
						if dd > blend:
							continue
						target = lerpf(yc, hh, _ss(0.0, blend, dd))
					best_d[idx] = dd
					best_h[idx] = target
					owner[idx] = ri
			k += 2
	for idx in N * N:
		if best_d[idx] < INF:
			H[idx] = best_h[idx]


func _tunnel_holes() -> void:
	for r: Dictionary in roads:
		var kind: PackedByteArray = r.kind
		var p: PackedVector2Array = r.p2
		var n := p.size()
		var core := float(r.half_w) + 1.0
		var tunnels := []
		var i := 0
		while i < n:
			if kind[i] == 2:
				var j := i
				while j < n and kind[j] == 2:
					j += 1
				tunnels.append([i, j - 1])
				i = j
			else:
				i += 1
		r.tunnels = tunnels
		for tun: Array in tunnels:
			for end in 2:
				var at: int = tun[end]
				var inward := 1 if end == 0 else -1
				var pa := p[at]
				var pb := p[clampi(at + inward * 3, 0, n - 1)]
				var dir := (pb - pa).normalized()
				var right := Vector2(-dir.y, dir.x)
				for j in range(int((pa.y - 30.0 + HALF) / STEP), int((pa.y + 30.0 + HALF) / STEP) + 1):
					for ii in range(int((pa.x - 30.0 + HALF) / STEP), int((pa.x + 30.0 + HALF) / STEP) + 1):
						if j < 0 or j >= N or ii < 0 or ii >= N:
							continue
						var rel := Vector2(-HALF + ii * STEP, -HALF + j * STEP) - pa
						var along := rel.dot(dir)
						var lat := rel.dot(right)
						if along >= -1.0 and along <= 7.0 and absf(lat) <= core + 1.0:
							holes[j * N + ii] = true
			print("  tunnel on %s: %d m" % [r.id, (int(tun[1]) - int(tun[0])) * STEP])


# ------------------------------------------------------------------ maps
func _maps(wd: WorldData) -> void:
	var control := Image.create(M, M, false, Image.FORMAT_RGBA8)
	var detail := Image.create(M, M, false, Image.FORMAT_RGBA8)
	var surf := PackedByteArray()
	surf.resize(M * M)
	var rd := PackedByteArray()
	rd.resize(M * M)
	var fnoise: FastNoiseLite = nz.field
	var fedge: FastNoiseLite = nz.field_edge
	var forest: FastNoiseLite = nz.forest
	var snow: FastNoiseLite = nz.snow
	var dune: FastNoiseLite = nz.dune
	for j in M:
		var z := -HALF + j * 4.0 + 2.0
		for i in M:
			var x := -HALF + i * 4.0 + 2.0
			var gi := (j * 2 + 1) * N + (i * 2 + 1)
			var h := H[gi]
			var gx := (H[gi + 1] - H[gi - 1]) / (2.0 * STEP) if i > 0 and i < M - 1 else 0.0
			var gz := (H[gi + N] - H[gi - N]) / (2.0 * STEP) if j > 0 and j < M - 1 else 0.0
			var slope := sqrt(gx * gx + gz * gz)
			var wdes := _w4(x, z, 0)
			var wmnt := _w4(x, z, 1)
			var wcst := _w4(x, z, 2)
			var wfarm := 1.0 - wdes - wmnt - wcst
			var road_edge := best_d[gi]
			var rdist := clampf(road_edge, 0.0, 255.0) if road_edge < INF else 255.0
			rd[j * M + i] = int(rdist)
			var field_code := 0
			var wat := water[gi]
			var bw := _beach(z)
			var sand := 0.0
			var s_coast := _coast_x(z) - x
			if wcst > 0.2 and s_coast < 260.0 and h < 9.0:
				sand = maxf(sand, bw * _ss(10.0, 3.0, h))
			sand = maxf(sand, _ss(1.8, 0.4, h) * (1.0 if wat == 0 else 0.0))
			if wdes > 0.5:
				sand = maxf(sand, _ss(0.25, 0.55, dune.get_noise_2d(x, z)) * _ss(0.5, 0.8, wdes) * (1.0 - _ss(0.25, 0.45, slope)))
			# farmland fields (cellular patches) on gentle slopes away from roads
			var fld := 0.0
			if wfarm > 0.55 and slope < 0.16 and rdist > 6.0 and wat == 0 and h > 3.0:
				var cv := fnoise.get_noise_2d(x, z)
				var edge := fedge.get_noise_2d(x, z)
				if edge > -0.9 and cv > 0.05:
					field_code = 1 + int(((cv - 0.05) / 0.95) * 4.99)
					fld = 1.0
			var forest_d := _ss(0.05, 0.35, forest.get_noise_2d(x, z)) * (1.0 - fld)
			var snowv := 0.0
			if h > SNOW_LINE - 60.0:
				snowv = _ss(SNOW_LINE - 40.0, SNOW_LINE + 50.0, h + snow.get_noise_2d(x, z) * 45.0) * (1.0 - _ss(0.7, 1.1, slope))
			var verge := _ss(5.0, 1.0, rdist) if rdist < 200.0 else 0.0
			control.set_pixel(i, j, Color(wdes, wmnt, wcst, field_code / 255.0 * 40.0))
			detail.set_pixel(i, j, Color(verge, forest_d, sand, snowv))
			var kind := SurfaceData.Kind.GRASS
			if snowv > 0.5:
				kind = SurfaceData.Kind.SNOW
			elif slope > 0.85:
				kind = SurfaceData.Kind.ROCK
			elif sand > 0.5:
				kind = SurfaceData.Kind.SAND
			elif verge > 0.5:
				kind = SurfaceData.Kind.GRAVEL
			elif wdes > 0.55:
				kind = SurfaceData.Kind.DIRT
			elif field_code >= 3:
				kind = SurfaceData.Kind.DIRT
			surf[j * M + i] = kind
	wd.control_img = control
	wd.detail_img = detail
	wd.surface = surf
	wd.road_dist = rd


# ------------------------------------------------------------------ buildings
const ANCHOR_KITS := ["church", "shop", "gas_station", "diner", "farmhouse", "boathouse"]
const KIT_RADIUS := {"house_a": 7.0, "house_b": 7.5, "house_c": 6.5, "shop": 8.0, "church": 12.0, "shed": 5.0,
	"boathouse": 7.0, "chalet": 7.5, "barn": 11.0, "farmhouse": 9.0, "silo": 4.0, "gas_station": 16.0, "diner": 10.5}


func _place_buildings() -> Array:
	var out := []
	var used := []
	for st: Dictionary in L.SETTLEMENTS:
		var poi := _poi(st.poi)
		var c := Vector2(poi.pos.x, poi.pos.z)
		var cands := []
		for r: Dictionary in roads:
			if r["class"] == "highway" and int(st.count) > 1:
				continue  # only single roadside services (fuel, diner) front the expressway
			var p: PackedVector2Array = r.p2
			for i in range(0, p.size(), 6):
				if p[i].distance_to(c) < float(st.radius) and (r.kind as PackedByteArray)[i] == 0:
					cands.append([r, i])
		_shuffle(cands)
		var kits: Array = st.kits
		# anchors (one each, large footprints) are placed first with a full scan of the candidates;
		# the remaining slots are filled with the ordinary kits
		var queue: Array = []
		for k: String in kits:
			if k in ANCHOR_KITS:
				queue.append(k)
		var fillers: Array = kits.filter(func(k: String) -> bool: return not (k in ANCHOR_KITS))
		if fillers.is_empty():
			fillers = kits
		while queue.size() < int(st.count):
			queue.append(fillers[rng.randi() % fillers.size()])
		var used_cand := {}
		for kit: String in queue:
			var rad: float = KIT_RADIUS.get(kit, 7.0)
			for ci in cands.size():
				if used_cand.has(ci):
					continue
				var cd: Array = cands[ci]
				var r: Dictionary = cd[0]
				var i: int = cd[1]
				var p: PackedVector2Array = r.p2
				var dir := (p[mini(i + 1, p.size() - 1)] - p[maxi(i - 1, 0)]).normalized()
				var right := Vector2(-dir.y, dir.x)
				var side := 1.0 if (ci % 2) == 0 else -1.0
				var pos := p[i] + right * side * (float(r.half_w) + rad + rng.randf_range(3.0, 7.0))
				if _blocked(pos, rad, used):
					side = -side
					pos = p[i] + right * side * (float(r.half_w) + rad + rng.randf_range(3.0, 7.0))
					if _blocked(pos, rad, used):
						continue
				var yaw := atan2(right.x * side, right.y * side)  # local -Z (front door) faces the road
				var y := _pad(pos, rad)
				out.append({"kit": kit, "pos": Vector3(pos.x, y, pos.y), "yaw": yaw, "radius": rad, "poi": st.poi})
				used.append([pos, rad])
				used_cand[ci] = true
				break
	# special landmarks
	for p: Dictionary in pois:
		var pos2 := Vector2(p.pos.x, p.pos.z)
		match p.type:
			"lighthouse", "castle", "festival", "viewpoint":
				var kit: String = {"lighthouse": "lighthouse", "castle": "castle", "festival": "festival", "viewpoint": "viewpoint"}[p.type]
				var y := H[_grid_index(pos2.x, pos2.y)]
				var yaw := _yaw_to_road(pos2)
				out.append({"kit": kit, "pos": Vector3(pos2.x, y, pos2.y), "yaw": yaw, "radius": 20.0, "poi": p.id})
				used.append([pos2, 18.0])
			"windfarm":
				for k in 7:
					var a := TAU * k / 7.0
					var tp := pos2 + Vector2(cos(a), sin(a)) * rng.randf_range(140.0, 280.0)
					if _blocked(tp, 10.0, used):
						continue
					var y := H[_grid_index(tp.x, tp.y)]
					out.append({"kit": "wind_turbine", "pos": Vector3(tp.x, y, tp.y), "yaw": rng.randf() * TAU, "radius": 6.0, "poi": p.id})
					used.append([tp, 10.0])
	return out


func _poi(id: String) -> Dictionary:
	for p: Dictionary in pois:
		if p.id == id:
			return p
	return {}


func _shuffle(a: Array) -> void:
	for i in range(a.size() - 1, 0, -1):
		var j := rng.randi() % (i + 1)
		var t: Variant = a[i]
		a[i] = a[j]
		a[j] = t


func _blocked(pos: Vector2, rad: float, used: Array) -> bool:
	for u: Array in used:
		if pos.distance_to(u[0]) < rad + float(u[1]) + 3.0:
			return true
	# footprint must stay off every road core and out of water
	for o: Vector2 in [Vector2.ZERO, Vector2(rad, 0), Vector2(-rad, 0), Vector2(0, rad), Vector2(0, -rad)]:
		var gi := _grid_index(pos.x + o.x, pos.y + o.y)
		if best_d[gi] < 2.0 or water[gi] != 0 or H[gi] < 1.0 or road_mask[gi] != 0:
			return true
	return false


func _pad(pos: Vector2, rad: float) -> float:
	var sum := 0.0
	var cnt := 0
	for o: Vector2 in [Vector2.ZERO, Vector2(rad, 0), Vector2(-rad, 0), Vector2(0, rad), Vector2(0, -rad)]:
		sum += H[_grid_index(pos.x + o.x, pos.y + o.y)]
		cnt += 1
	var y := sum / cnt
	var R := rad + 7.0
	for j in range(maxi(0, int((pos.y - R + HALF) / STEP)), mini(N, int((pos.y + R + HALF) / STEP) + 1)):
		for i in range(maxi(0, int((pos.x - R + HALF) / STEP)), mini(N, int((pos.x + R + HALF) / STEP) + 1)):
			var idx := j * N + i
			if best_d[idx] < 1.0:
				continue
			var d := Vector2(-HALF + i * STEP, -HALF + j * STEP).distance_to(pos)
			if d < R:
				H[idx] = lerpf(y, H[idx], _ss(rad + 0.5, R, d))
	return y


func _yaw_to_road(pos: Vector2) -> float:
	var best := Vector2.ZERO
	var bd := INF
	for r: Dictionary in roads:
		var p: PackedVector2Array = r.p2
		for i in range(0, p.size(), 4):
			var d := p[i].distance_squared_to(pos)
			if d < bd:
				bd = d
				best = p[i]
	var to := best - pos
	return atan2(-to.x, -to.y)


# ------------------------------------------------------------------ trees
## species: 0 broadleaf, 1 conifer, 2 poplar, 3 palm, 4 cactus, 5 bush, 6 boulder, 7 umbrella pine, 8 dry shrub
func _place_trees(buildings: Array) -> Dictionary:
	var out := {}
	var forest: FastNoiseLite = nz.forest
	var fnoise: FastNoiseLite = nz.field
	var fedge: FastNoiseLite = nz.field_edge
	var cell := 7.0
	var steps := int(4096.0 / cell)
	var bpos := []
	for b: Dictionary in buildings:
		bpos.append([Vector2(b.pos.x, b.pos.z), float(b.radius) + 4.0])
	var count := 0
	for j in steps:
		for i in steps:
			var x := -HALF + (i + rng.randf()) * cell
			var z := -HALF + (j + rng.randf()) * cell
			if absf(x) > HALF - 8.0 or absf(z) > HALF - 8.0:
				continue
			var gi := _grid_index(x, z)
			var h := H[gi]
			if h < 0.6 or water[gi] != 0 or road_mask[gi] != 0:
				continue
			var rdist := best_d[gi]
			var gx := (H[mini(gi + 1, N * N - 1)] - H[maxi(gi - 1, 0)]) / (2.0 * STEP)
			var gz := (H[mini(gi + N, N * N - 1)] - H[maxi(gi - N, 0)]) / (2.0 * STEP)
			var slope := sqrt(gx * gx + gz * gz)
			var wdes := _w4(x, z, 0)
			var wmnt := _w4(x, z, 1)
			var wcst := _w4(x, z, 2)
			var wfarm := 1.0 - wdes - wmnt - wcst
			var fden := forest.get_noise_2d(x, z)
			var r := rng.randf()
			var species := -1
			var min_road := 7.0
			if wmnt > 0.5:
				var treeline := 1.0 - _ss(SNOW_LINE - 90.0, SNOW_LINE - 10.0, h)
				if fden > -0.15 and r < 0.75 * treeline and slope < 0.9:
					species = 1
				elif r < 0.04 and slope > 0.3:
					species = 6
				elif r < 0.06 * treeline:
					species = 5
			elif wdes > 0.5:
				if r < 0.022 and slope < 0.5:
					species = 4
				elif r < 0.05:
					species = 8
				elif r < 0.065:
					species = 6
				min_road = 4.0
			elif wcst > 0.5:
				var s := _coast_x(z) - x
				if s < 300.0 and h < 14.0 and r < 0.06:
					species = 3
				elif fden > 0.15 and r < 0.35:
					species = 7
				elif r < 0.035:
					species = 5
			else:
				var in_field := slope < 0.16 and fnoise.get_noise_2d(x, z) > 0.05 and fedge.get_noise_2d(x, z) > -0.9 and wfarm > 0.55
				var hedge := fedge.get_noise_2d(x, z) <= -0.88 and wfarm > 0.55
				if hedge and r < 0.35:
					species = 0 if r < 0.25 else 5
				elif not in_field and fden > 0.12 and r < 0.6:
					species = 0 if (fden < 0.35 or r < 0.3) else 1
				elif not in_field and r < 0.03:
					species = 5 if r < 0.02 else 2
			if species < 0:
				continue
			if rdist < (min_road if species != 2 else 5.0):
				continue
			var blocked := false
			for bp: Array in bpos:
				if Vector2(x, z).distance_to(bp[0]) < float(bp[1]):
					blocked = true
					break
			if blocked:
				continue
			var near_poi := false
			for p: Dictionary in pois:
				if float(p.flat) > 0.0 and Vector2(x, z).distance_to(Vector2(p.pos.x, p.pos.z)) < float(p.flat) + 8.0:
					near_poi = true
					break
			if near_poi:
				continue
			var key := "%d,%d" % [clampi(int((x + HALF) / 256.0), 0, 15), clampi(int((z + HALF) / 256.0), 0, 15)]
			if not out.has(key):
				out[key] = PackedFloat32Array()
			var arr: PackedFloat32Array = out[key]
			arr.append_array([x, _bilinear(H, x, z), z, rng.randf() * TAU, rng.randf_range(0.75, 1.3), float(species)])
			out[key] = arr
			count += 1
	print("  trees/rocks placed: ", count)
	return out


# ------------------------------------------------------------------ props
func _place_props() -> Array:
	var out := []
	# junction signs and region welcome signs are placed at runtime from road data
	for p: Dictionary in pois:
		if p.type == "viewpoint":
			out.append({"kind": "bench", "pos": p.pos})
	return out


# ------------------------------------------------------------------ activities
func _curv_window(r: Dictionary, i: int, half: int) -> float:
	var p: PackedVector2Array = r.p2
	var n := p.size()
	var closed: bool = r.closed
	var total := 0.0
	for k in range(-half, half, 5):
		var a := i + k
		var b := a + 5
		var c := b + 5
		if not closed and (a < 0 or c >= n):
			return INF
		var t1 := (p[(b + n) % n] - p[(a + n) % n]).normalized()
		var t2 := (p[(c + n) % n] - p[(b + n) % n]).normalized()
		total += absf(t1.angle_to(t2))
	return total


func _act_pos(r: Dictionary, s: float) -> Dictionary:
	var p: PackedVector2Array = r.p2
	var y: PackedFloat32Array = r.y
	var n := p.size()
	var i := clampi(int(s / STEP), 0, n - 1)
	var dir := (p[(i + 2) % n] - p[(i - 2 + n) % n]).normalized() if r.closed else (p[mini(i + 2, n - 1)] - p[maxi(i - 2, 0)]).normalized()
	return {"pos": Vector3(p[i].x, y[i], p[i].y), "dir": Vector3(dir.x, 0, dir.y), "road": r.id, "s": i * STEP}


func _activities() -> Array:
	var out := []
	# speed traps: straightest points on chosen roads
	var traps := [["highway", "Expressway Radar"], ["loop", "Coastline Radar"], ["valley", "Riverside Radar"],
		["canyon", "Redmesa Radar"], ["orchard", "Orchard Radar"]]
	for t: Array in traps:
		var r: Dictionary = road_by_id[t[0]]
		var best := -1
		var bc := INF
		var n := (r.p2 as PackedVector2Array).size()
		for i in range(150, n - 150, 10):
			if (r.kind as PackedByteArray)[i] != 0:
				continue
			var c := _curv_window(r, i, 120)
			if c < bc and not _near_junction(r, i * STEP):
				bc = c
				best = i
		if best >= 0:
			var a := _act_pos(r, best * STEP)
			a.merge({"type": "speed_trap", "id": "trap_" + String(t[0]), "name": t[1]})
			out.append(a)
	# drift zones: twistiest 350 m windows; speed zones: medium curvature 700 m windows
	for spec: Array in [["summit", "Summit Hairpins Drift", "drift_zone", 175], ["loop", "Pinecrest Switchback Drift", "drift_zone", 175],
			["mesa", "Mesa Ridge Drift", "drift_zone", 175], ["loop", "Cliffside Speed Zone", "speed_zone", 350],
			["highway", "Expressway Speed Zone", "speed_zone", 350]]:
		if not road_by_id.has(spec[0]):
			continue
		var r: Dictionary = road_by_id[spec[0]]
		var n := (r.p2 as PackedVector2Array).size()
		var half: int = spec[3]
		var best := -1
		var bv := -INF if spec[2] == "drift_zone" else INF
		var start := half + 10
		for i in range(start, n - half - 10, 20):
			if _near_junction(r, i * STEP):
				continue
			var c := _curv_window(r, i, half)
			if c == INF:
				continue
			var used_close := false
			for o: Dictionary in out:
				if o.road == r.id and absf(float(o.s) - i * STEP) < 900.0:
					used_close = true
			if used_close:
				continue
			if spec[2] == "drift_zone" and c > bv:
				bv = c
				best = i
			elif spec[2] == "speed_zone":
				var score := absf(c - 1.2)
				if score < bv:
					bv = score
					best = i
		if best >= 0:
			var a := _act_pos(r, (best - half) * STEP)
			var e := _act_pos(r, (best + half) * STEP)
			a.merge({"type": spec[2], "id": String(spec[2]) + "_" + str(out.size()), "name": spec[1], "end_s": e.s, "end_pos": e.pos, "end_dir": e.dir})
			out.append(a)
	# checkpoint races along road sections
	for race: Array in L.RACES:
		var r: Dictionary = road_by_id[race[0]]
		var L_ := float(r.length)
		var s0 := float(race[1]) * L_
		var s1 := float(race[2]) * L_
		var cps := []
		var s := s0 + 450.0
		while s < s1 - 200.0:
			cps.append(_act_pos(r, s))
			s += 450.0
		var a := _act_pos(r, s0)
		var fin := _act_pos(r, s1)
		a.merge({"type": "race", "id": "race_" + str(out.size()), "name": race[3], "checkpoints": cps, "finish": fin,
			"length": s1 - s0})
		out.append(a)
	# time trial around the whole scenic loop
	var loop: Dictionary = road_by_id["loop"]
	var tt_cps := []
	var s2 := 1500.0
	while s2 < float(loop.length) - 300.0:
		tt_cps.append(_act_pos(loop, s2))
		s2 += 1500.0
	var tt := _act_pos(loop, 60.0)
	tt.merge({"type": "time_trial", "id": "tt_loop", "name": "Festival Loop Time Trial", "checkpoints": tt_cps,
		"finish": _act_pos(loop, 60.0), "length": float(loop.length), "lap": true})
	out.append(tt)
	# danger-sign jumps: flat open ground beside a road with a clear landing zone
	var jumps := 0
	for spec: Array in [["canyon", 0.35, "Redmesa Leap"], ["sunfield", 0.5, "Sunfield Hop"], ["windfarm", 0.45, "Windfarm Air"], ["loop", 0.55, "Desert Plateau Jump"]]:
		var r: Dictionary = road_by_id[spec[0]]
		var n := (r.p2 as PackedVector2Array).size()
		var found := false
		for tries in 60:
			var i := clampi(int(n * float(spec[1])) + tries * 7 * (1 if tries % 2 == 0 else -1), 20, n - 120)
			if (r.kind as PackedByteArray)[i] != 0 or _near_junction(r, i * STEP):
				continue
			# the jump runs along the road: ramp on the road edge, landing must be flat road ahead
			var a := _act_pos(r, i * STEP)
			var flat := true
			var y0 := float(a.pos.y)
			for k in range(6, 50, 4):
				var b := _act_pos(r, (i + k) * STEP)
				if absf(float(b.pos.y) - (y0 - k * STEP * 0.04)) > 3.5 or _curv_window(r, i + 25, 25) > 0.5:
					flat = false
					break
			if flat:
				a.merge({"type": "jump", "id": "jump_" + str(jumps), "name": spec[2]})
				out.append(a)
				jumps += 1
				found = true
				break
		if not found:
			print("  no jump site on ", spec[0])
	print("  activities: ", out.size())
	return out


# ------------------------------------------------------------------ export
func _export_roads() -> Array:
	var out := []
	for r: Dictionary in roads:
		var p: PackedVector2Array = r.p2
		var y: PackedFloat32Array = r.y
		var pts := PackedVector3Array()
		pts.resize(p.size())
		for i in p.size():
			pts[i] = Vector3(p[i].x, y[i], p[i].y)
		var d := {"id": r.id, "name": r.name, "class": r["class"], "closed": r.closed, "lanes": r.lanes,
			"lane_w": r.lane_w, "shoulder": r.shoulder, "median": r.median, "half_w": r.half_w, "speed": r.speed,
			"surface": r.surface, "scenic": r.scenic, "pts": pts, "bank": r.bank, "kind": r.kind,
			"length": r.length, "junctions": r.junctions, "traffic": r.traffic, "tunnels": r.get("tunnels", [])}
		if r.has("start_on"):
			d.start_on = r.start_on
		if r.has("end_on"):
			d.end_on = r.end_on
		out.append(d)
	return out


func _spawn() -> Transform3D:
	var r: Dictionary = road_by_id[L.SPAWN.road]
	var a := _act_pos(r, float(L.SPAWN.s))
	var right := Vector3(-a.dir.z, 0, a.dir.x)
	var pos: Vector3 = a.pos + right * float(r.lane_w) * 0.5 + Vector3.UP * 0.6
	return Transform3D(Basis.looking_at(a.dir, Vector3.UP), pos)


func _preview(wd: WorldData) -> void:
	var img := Image.create(M, M, false, Image.FORMAT_RGB8)
	for j in M:
		for i in M:
			var gi := (j * 2 + 1) * N + (i * 2 + 1)
			var h := H[gi]
			var shade := 1.0
			if i > 0 and j > 0:
				var dx := H[gi] - H[gi - 2]
				var dz := H[gi] - H[gi - 2 * N]
				shade = clampf(1.0 + (dx + dz) * 0.06, 0.45, 1.35)
			var c: Color
			if h < 0.0:
				c = Color(0.12, 0.3, 0.55).lerp(Color(0.05, 0.15, 0.35), clampf(-h / 20.0, 0.0, 1.0))
			elif water[gi] == 1:
				c = Color(0.2, 0.45, 0.7)
			else:
				var ctl := wd.control_img.get_pixel(i, j)
				var base := Color(0.35, 0.55, 0.25).lerp(Color(0.72, 0.42, 0.25), ctl.r).lerp(Color(0.45, 0.48, 0.4), ctl.g).lerp(Color(0.6, 0.62, 0.4), ctl.b * 0.6)
				if h > SNOW_LINE:
					base = base.lerp(Color(0.95, 0.95, 0.97), 0.8)
				c = base * shade
			img.set_pixel(i, j, c)
	var cols := {"highway": Color(1, 0.85, 0.2), "regional": Color(1, 1, 1), "mountain": Color(1, 0.6, 0.6),
		"village": Color(0.85, 0.85, 1), "gravel": Color(0.75, 0.7, 0.6), "dirt": Color(0.6, 0.45, 0.3)}
	for r: Dictionary in roads:
		var p: PackedVector2Array = r.p2
		var kind: PackedByteArray = r.kind
		for i in p.size():
			var c: Color = cols[r["class"]]
			if kind[i] == 1:
				c = Color(0.2, 1, 1)
			elif kind[i] == 2:
				c = Color(1, 0.2, 1)
			var px := int((p[i].x + HALF) / 4.0)
			var pz := int((p[i].y + HALF) / 4.0)
			if px >= 0 and px < M and pz >= 0 and pz < M:
				img.set_pixel(px, pz, c)
	for p: Dictionary in pois:
		var px := int((p.pos.x + HALF) / 4.0)
		var pz := int((p.pos.z + HALF) / 4.0)
		for o in range(-3, 4):
			for q in range(-3, 4):
				if px + o >= 0 and px + o < M and pz + q >= 0 and pz + q < M:
					img.set_pixel(px + o, pz + q, Color(1, 0.1, 0.1))
	for b: Dictionary in wd.buildings:
		var px := int((b.pos.x + HALF) / 4.0)
		var pz := int((b.pos.z + HALF) / 4.0)
		if px > 0 and px < M - 1 and pz > 0 and pz < M - 1:
			img.set_pixel(px, pz, Color(0.1, 0.1, 0.1))
	for a: Dictionary in wd.activities:
		var px := int((a.pos.x + HALF) / 4.0)
		var pz := int((a.pos.z + HALF) / 4.0)
		for o in range(-2, 3):
			if px + o >= 0 and px + o < M and pz >= 0 and pz < M:
				img.set_pixel(px + o, pz, Color(1, 0.5, 0))
	DirAccess.make_dir_recursive_absolute("res://qa")
	img.save_png("res://qa/map_preview.png")
