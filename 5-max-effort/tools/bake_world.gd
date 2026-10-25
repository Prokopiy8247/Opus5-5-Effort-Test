extends SceneTree
## Deterministic world generator (seeded). Produces the baked world data used by the runtime:
##   res://data/world/height.bin   zstd float32 heightmap, 2001 x 2001 @ 2 m (x,z in [-2000, 2000])
##   res://data/world/holes.bin    zstd uint8 mask (1 = terrain hole above tunnel portals)
##   res://data/world/splat.png    1024 x 1024 RGBA: R field, G desert, B forest/soil, A sand
##   res://data/world/roadmask.png 2048 x 2048 L8 road surface tint for far terrain
##   res://data/world/roads.json   road splines sampled every 2 m with elevation, bank, flags
##   res://data/world/world_meta.json  river, lake, sea, settlements, props, teleports, stats
## Run: Godot_console.exe --headless --path . --script res://tools/bake_world.gd

const L := preload("res://scripts/world/world_layout.gd")
const HALF := 2000.0
const RES := 2.0
const N := 2001
const C_RES := 4.0
const CN := 1001
const STEP := 2.0

const F_BRIDGE := 1
const F_TUNNEL := 2
const F_RAIL_L := 4
const F_RAIL_R := 8
const F_JUNCTION := 16
const F_VILLAGE := 32

var H0 := PackedFloat32Array()     # natural terrain (2 m)
var H := PackedFloat32Array()      # final terrain (2 m)
var holes := PackedByteArray()
var water_level := PackedFloat32Array()   # 2 m grid, -1000 = no inland water
var road_core := PackedByteArray()        # 2 m grid, surface id + 1 where road paved area
var n_low := FastNoiseLite.new()
var n_mid := FastNoiseLite.new()
var n_ridge := FastNoiseLite.new()
var n_warp := FastNoiseLite.new()
var n_mesa := FastNoiseLite.new()
var n_canyon := FastNoiseLite.new()
var n_detail := FastNoiseLite.new()
var roads: Array = []
var river_pts: Array[Vector3] = []
var river_width: Array[float] = []
var props: Array = []
var stats := {}
var rng := RandomNumberGenerator.new()


func _initialize() -> void:
	var t0 := Time.get_ticks_msec()
	rng.seed = L.SEED
	_setup_noise()
	_base_heights()
	print("[bake] base heights %d ms" % (Time.get_ticks_msec() - t0))
	_river()
	print("[bake] river %d ms" % (Time.get_ticks_msec() - t0))
	_build_roads()
	print("[bake] roads %d ms" % (Time.get_ticks_msec() - t0))
	_carve_roads()
	print("[bake] carve %d ms" % (Time.get_ticks_msec() - t0))
	_road_flags()
	_place_props()
	print("[bake] props %d ms" % (Time.get_ticks_msec() - t0))
	_write()
	print("[bake] done in %d ms" % (Time.get_ticks_msec() - t0))
	print("[bake] stats ", JSON.stringify(stats))
	quit()


# =================================================================================================
# noise and base terrain
func _setup_noise() -> void:
	var cfg := [
		[n_low, FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 0.0011, 4, 1],
		[n_mid, FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 0.004, 4, 2],
		[n_ridge, FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 0.0011, 4, 3],
		[n_warp, FastNoiseLite.TYPE_SIMPLEX, 0.0007, 2, 4],
		[n_mesa, FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 0.0021, 3, 5],
		[n_canyon, FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 0.0008, 1, 6],
		[n_detail, FastNoiseLite.TYPE_SIMPLEX, 0.03, 2, 7],
	]
	for c in cfg:
		var n: FastNoiseLite = c[0]
		n.noise_type = c[1]
		n.frequency = c[2]
		n.fractal_octaves = c[3]
		n.fractal_type = FastNoiseLite.FRACTAL_FBM
		n.seed = L.SEED + int(c[4]) * 101
	n_ridge.fractal_type = FastNoiseLite.FRACTAL_RIDGED


func coast_x(z: float) -> float:
	## x of the shoreline (land is east of it). Headland at the lighthouse, bay at the harbour.
	var x := -1715.0 + 45.0 * sin(z * 0.0023 + 1.1) + 30.0 * n_low.get_noise_2d(13.0, z * 0.6)
	x -= 120.0 * exp(-pow((z + 1040.0) / 150.0, 2.0))  # lighthouse headland
	x += 70.0 * exp(-pow((z - 930.0) / 120.0, 2.0))    # harbour bay
	if z > 1350.0:
		x += (z - 1350.0) * 0.12                        # southern beach recedes
	return x


func region_weights(x: float, z: float) -> Vector4:
	## x = coast, y = farmland valley, z = highlands, w = desert
	var wx := x + n_warp.get_noise_2d(x, z) * 160.0
	var wz := z + n_warp.get_noise_2d(z + 500.0, x - 300.0) * 160.0
	var high := smoothstep(-200.0, -760.0, wz)
	var desert := smoothstep(650.0, 1000.0, wx) * smoothstep(-650.0, -250.0, wz)
	var coast := smoothstep(-1150.0, -1420.0, wx)
	high *= 1.0 - coast * 0.6
	desert *= 1.0 - high
	var farm := maxf(0.0, 1.0 - coast - high - desert)
	var s := coast + farm + high + desert
	return Vector4(coast, farm, high, desert) / maxf(s, 0.001)


func _height_raw(x: float, z: float) -> float:
	var w := region_weights(x, z)
	var lo := n_low.get_noise_2d(x, z)
	var mid := n_mid.get_noise_2d(x, z)
	# farmland valley: gentle hills, lower towards the river corridor
	var farm := 26.0 + 16.0 * lo + 6.0 * mid
	# highlands: ridged mountains rising to the north
	var r := n_ridge.get_noise_2d(x, z) * 0.5 + 0.5
	var mmask := smoothstep(-250.0, -1500.0, z)
	var high := 85.0 + 125.0 * mmask + 360.0 * mmask * (0.3 + 0.7 * r * r) + 14.0 * mid
	# a ridge spur the pass road tunnels through
	high += 150.0 * exp(-pow((x - 1135.0) / 95.0, 2.0) - pow((z + 1250.0) / 170.0, 2.0))
	# desert plateau with terraced mesas and a canyon network
	var m := n_mesa.get_noise_2d(x, z)
	var mesa := smoothstep(0.18, 0.3, m) * 55.0 + smoothstep(0.42, 0.5, m) * 35.0
	var cv := absf(n_canyon.get_noise_2d(x, z))
	var canyon := (1.0 - smoothstep(0.025, 0.08, cv)) * 42.0
	var desert := 92.0 + 18.0 * lo + mesa - canyon + 4.0 * mid
	# coast hills / cliff plateau
	var coast := 34.0 + 26.0 * lo + 6.0 * mid
	var h := w.x * coast + w.y * farm + w.z * high + w.w * desert
	return h


var lake_level: float = 20.0


func _base_heights() -> void:
	# lake level: just below the lowest quarter of the natural ground around the basin
	var rim: Array[float] = []
	for k in 72:
		var a := TAU * k / 72.0
		var q := L.LAKE_CENTER + Vector2(cos(a) * L.LAKE_RADII.x, sin(a) * L.LAKE_RADII.y) * 1.25
		rim.append(_height_raw(q.x, q.y))
	rim.sort()
	lake_level = clampf(rim[18] - 1.5, 6.0, 60.0)
	# compute at 4 m, upsample to 2 m
	var C := PackedFloat32Array()
	C.resize(CN * CN)
	for iz in CN:
		var z := -HALF + iz * C_RES
		var cx := coast_x(z)
		var cliff := smoothstep(350.0, -100.0, z)   # cliffs north of the harbour, beaches south
		for ix in CN:
			var x := -HALF + ix * C_RES
			var h := _height_raw(x, z)
			# shoreline: d < 0 = sea
			var d := x - cx
			if d < 0.0:
				var depth := lerpf(-3.0, -26.0, smoothstep(0.0, -260.0, d))
				h = depth
			else:
				var land_w := smoothstep(0.0, lerpf(260.0, 45.0, cliff), d)
				var shore_h := lerpf(1.2, h * 0.35, cliff * smoothstep(0.0, 18.0, d))
				h = lerpf(shore_h, h, land_w)
				if cliff > 0.5 and d < 30.0:
					h = lerpf(-2.0, h, smoothstep(0.0, 30.0, d))
			# lake bowl
			var lp := Vector2((x - L.LAKE_CENTER.x) / L.LAKE_RADII.x, (z - L.LAKE_CENTER.y) / L.LAKE_RADII.y)
			var lr := lp.length() + n_mid.get_noise_2d(x * 2.0, z * 2.0) * 0.06
			if lr < 1.6:
				var bowl := lake_level - 1.2 - 8.0 * (1.0 - minf(lr * lr, 1.0))
				if lr < 1.0:
					h = bowl
				else:
					# shore slopes gently up to the natural ground, never below the water line
					var t := smoothstep(1.0, 1.6, lr)
					h = lerpf(lake_level + 0.4, maxf(h, lake_level + 0.4), t)
			C[iz * CN + ix] = h
	H0.resize(N * N)
	for iz in N:
		var z := -HALF + iz * RES
		var fz := float(iz) * 0.5
		var cz := mini(int(fz), CN - 2)
		var tz := fz - float(cz)
		for ix in N:
			var fx := float(ix) * 0.5
			var cx := mini(int(fx), CN - 2)
			var tx := fx - float(cx)
			var a := C[cz * CN + cx]
			var b := C[cz * CN + cx + 1]
			var c := C[(cz + 1) * CN + cx]
			var d := C[(cz + 1) * CN + cx + 1]
			var h := lerpf(lerpf(a, b, tx), lerpf(c, d, tx), tz)
			if h > 2.0:
				h += n_detail.get_noise_2d(-HALF + ix * RES, z) * 0.35
			H0[iz * N + ix] = h
	water_level.resize(N * N)
	water_level.fill(-1000.0)
	holes.resize(N * N)
	holes.fill(0)
	road_core.resize(N * N)
	road_core.fill(0)


func hget(arr: PackedFloat32Array, x: float, z: float) -> float:
	var fx := clampf((x + HALF) / RES, 0.0, float(N - 1) - 0.001)
	var fz := clampf((z + HALF) / RES, 0.0, float(N - 1) - 0.001)
	var ix := int(fx)
	var iz := int(fz)
	var tx := fx - ix
	var tz := fz - iz
	var i := iz * N + ix
	return lerpf(lerpf(arr[i], arr[i + 1], tx), lerpf(arr[i + N], arr[i + N + 1], tx), tz)


# =================================================================================================
# splines
func _catmull(points: Array, closed: bool, step: float) -> Array[Vector2]:
	## centripetal Catmull-Rom through 2D control points, resampled every `step` metres
	var P: Array[Vector2] = []
	for p in points:
		P.append(Vector2(float(p[0]), float(p[1])))
	var n := P.size()
	var dense: Array[Vector2] = []
	var segs := n if closed else n - 1
	for i in segs:
		var p0 := P[(i - 1 + n) % n] if (closed or i > 0) else P[0] * 2.0 - P[1]
		var p1 := P[i]
		var p2 := P[(i + 1) % n]
		var p3 := P[(i + 2) % n] if (closed or i + 2 < n) else P[n - 1] * 2.0 - P[n - 2]
		var seg_len := p1.distance_to(p2)
		var sub := maxi(int(seg_len / 1.0), 2)
		for k in sub:
			var t := float(k) / float(sub)
			dense.append(_cr_point(p0, p1, p2, p3, t))
	if not closed:
		dense.append(P[n - 1])
	# arc-length resample
	var out: Array[Vector2] = [dense[0]]
	var acc := 0.0
	for i in range(1, dense.size()):
		var a := dense[i - 1]
		var b := dense[i]
		var d := a.distance_to(b)
		while acc + d >= step:
			var t := (step - acc) / d
			var p := a.lerp(b, t)
			out.append(p)
			a = p
			d = a.distance_to(b)
			acc = 0.0
		acc += d
	if not closed and out[out.size() - 1].distance_to(dense[dense.size() - 1]) > step * 0.3:
		out.append(dense[dense.size() - 1])
	return out


func _cr_point(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, t: float) -> Vector2:
	var alpha := 0.5
	var t0 := 0.0
	var t1 := t0 + pow(maxf(p0.distance_to(p1), 0.01), alpha)
	var t2 := t1 + pow(maxf(p1.distance_to(p2), 0.01), alpha)
	var t3 := t2 + pow(maxf(p2.distance_to(p3), 0.01), alpha)
	var tt := lerpf(t1, t2, t)
	var a1 := p0 * ((t1 - tt) / (t1 - t0)) + p1 * ((tt - t0) / (t1 - t0))
	var a2 := p1 * ((t2 - tt) / (t2 - t1)) + p2 * ((tt - t1) / (t2 - t1))
	var a3 := p2 * ((t3 - tt) / (t3 - t2)) + p3 * ((tt - t2) / (t3 - t2))
	var b1 := a1 * ((t2 - tt) / (t2 - t0)) + a2 * ((tt - t0) / (t2 - t0))
	var b2 := a2 * ((t3 - tt) / (t3 - t1)) + a3 * ((tt - t1) / (t3 - t1))
	return b1 * ((t2 - tt) / (t2 - t1)) + b2 * ((tt - t1) / (t2 - t1))


# =================================================================================================
# river
func _river() -> void:
	var pts := _catmull(L.RIVER, false, 4.0)
	var n := pts.size()
	# water level: monotone non-increasing downstream, smoothed
	var lv := PackedFloat32Array()
	lv.resize(n)
	for i in n:
		lv[i] = hget(H0, pts[i].x, pts[i].y) - 1.6
	for i in range(1, n):
		lv[i] = minf(lv[i], lv[i - 1] - 0.004)
	for pass_i in 3:
		var sm := lv.duplicate()
		for i in n:
			var acc := 0.0
			var c := 0
			for k in range(-6, 7):
				var j := clampi(i + k, 0, n - 1)
				acc += lv[j]
				c += 1
			sm[i] = minf(acc / c, lv[i])
		lv = sm
	for i in n:
		lv[i] = maxf(lv[i], L.SEA_LEVEL + 0.1)
	var total := 0.0
	for i in n:
		if i > 0:
			total += pts[i].distance_to(pts[i - 1])
		var w := lerpf(9.0, 24.0, float(i) / float(n - 1))
		river_pts.append(Vector3(pts[i].x, lv[i], pts[i].y))
		river_width.append(w)
	stats["river_length_m"] = int(total)
	stats["lake_level_m"] = snappedf(lake_level, 0.1)
	# carve channel into H0 (accumulate the strongest influence per cell, then apply once)
	var acc_w := PackedFloat32Array()
	acc_w.resize(N * N)
	var acc_t := PackedFloat32Array()
	acc_t.resize(N * N)
	var acc_lv := PackedFloat32Array()
	acc_lv.resize(N * N)
	for i in n:
		var p := river_pts[i]
		var w := river_width[i]
		var bank := w * 0.5 + 16.0
		var dir := (Vector2(river_pts[mini(i + 1, n - 1)].x, river_pts[mini(i + 1, n - 1)].z) - Vector2(river_pts[maxi(i - 1, 0)].x, river_pts[maxi(i - 1, 0)].z)).normalized()
		var nrm := Vector2(-dir.y, dir.x)
		var a := -2.0
		while a <= 2.0:
			var l := -bank
			while l <= bank:
				var q := Vector2(p.x, p.z) + dir * a + nrm * l
				var ix := int(round((q.x + HALF) / RES))
				var iz := int(round((q.y + HALF) / RES))
				l += 1.0
				if ix < 0 or iz < 0 or ix >= N or iz >= N:
					continue
				var idx := iz * N + ix
				var c := Vector2(-HALF + ix * RES, -HALF + iz * RES) - Vector2(p.x, p.z)
				var d := absf(c.dot(nrm))
				var wt := 1.0 if d <= w * 0.5 else 1.0 - smoothstep(w * 0.5, bank, d)
				if wt > acc_w[idx]:
					acc_w[idx] = wt
					acc_t[idx] = p.y - 2.8 * (1.0 - smoothstep(0.0, w * 0.5, d)) - 0.3 if d <= w * 0.5 else p.y + 0.7
					acc_lv[idx] = p.y
					if d < w * 0.5 + 1.5:
						water_level[idx] = maxf(water_level[idx], p.y)
			a += 2.0
	for idx in N * N:
		var wt := acc_w[idx]
		if wt <= 0.0:
			continue
		var cur := H0[idx]
		var t := acc_t[idx]
		if wt >= 1.0:
			H0[idx] = minf(cur, t)
		else:
			var lowered := lerpf(cur, minf(cur, t), wt) if cur > t else cur
			# contain the water: low floodplain cells are raised just above the water level
			if lowered < acc_lv[idx] + 0.4:
				lowered = lerpf(lowered, acc_lv[idx] + 0.4, wt)
			H0[idx] = lowered
	# lake water (inside the basin only)
	for iz in N:
		var z := -HALF + iz * RES
		if absf(z - L.LAKE_CENTER.y) > L.LAKE_RADII.y * 1.2:
			continue
		for ix in N:
			var x := -HALF + ix * RES
			if absf(x - L.LAKE_CENTER.x) > L.LAKE_RADII.x * 1.2:
				continue
			var lp := Vector2((x - L.LAKE_CENTER.x) / L.LAKE_RADII.x, (z - L.LAKE_CENTER.y) / L.LAKE_RADII.y)
			var idx := iz * N + ix
			if lp.length() < 1.12 and H0[idx] < lake_level:
				water_level[idx] = lake_level


func _dist_to_polyline_local(x: float, z: float, i: int, pts: Array[Vector2]) -> float:
	var best := 1e9
	var p := Vector2(x, z)
	for k in range(maxi(i - 3, 0), mini(i + 3, pts.size() - 1)):
		var a := pts[k]
		var b := pts[k + 1]
		var ab := b - a
		var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 1e-6), 0.0, 1.0)
		best = minf(best, p.distance_to(a + ab * t))
	return best


func water_at(x: float, z: float) -> float:
	if x < coast_x(z):
		return L.SEA_LEVEL
	var fx := clampi(int(round((x + HALF) / RES)), 0, N - 1)
	var fz := clampi(int(round((z + HALF) / RES)), 0, N - 1)
	return water_level[fz * N + fx]


# =================================================================================================
# roads
func _build_roads() -> void:
	var by_name := {}
	for spec in L.ROADS:
		var cls: Dictionary = L.CLASSES[spec["class"]]
		var closed: bool = spec.get("loop", false)
		var pts := _catmull(spec["points"], closed, STEP)
		var r := {
			"name": spec["name"], "class": spec["class"], "surface": spec["surface"], "closed": closed,
			"scenic": spec.get("scenic", false), "width": cls["width"], "lanes": cls["lanes"],
			"lane_width": cls["lane_width"], "shoulder": cls["shoulder"], "median": cls["median"], "speed": cls["speed"],
			"grade": cls["grade"], "smooth": cls["smooth"], "pts": pts, "y": PackedFloat32Array(), "bank": PackedFloat32Array(),
			"flags": PackedInt32Array(), "joins": [], "spec": spec,
		}
		roads.append(r)
		by_name[spec["name"]] = roads.size() - 1
	# explicit tunnel spans from control-point markers -> nearest sample ranges
	for r in roads:
		var spec: Dictionary = r["spec"]
		var cps: Array = spec["points"]
		var ranges := []
		var open_i := -1
		for k in cps.size():
			var cp: Array = cps[k]
			if cp.size() > 2 and cp[2] == "tunnel":
				open_i = _nearest_index(r["pts"], Vector2(cp[0], cp[1]))
			elif cp.size() > 2 and cp[2] == "tunnel_end" and open_i >= 0:
				ranges.append([open_i, _nearest_index(r["pts"], Vector2(cp[0], cp[1]))])
				open_i = -1
		r["tunnels"] = ranges
	# junction snapping (endpoints onto the target road polyline)
	for ri in roads.size():
		var r: Dictionary = roads[ri]
		var spec: Dictionary = r["spec"]
		for end in ["start_join", "end_join"]:
			if not spec.has(end):
				continue
			var ti: int = by_name[spec[end]]
			var target: Dictionary = roads[ti]
			var pts: Array[Vector2] = r["pts"]
			var ep: Vector2 = pts[0] if end == "start_join" else pts[pts.size() - 1]
			var j := _nearest_index(target["pts"], ep)
			var snap: Vector2 = target["pts"][j]
			# end the minor road at the major road's edge so the meshes do not overlap
			var dir_major: Vector2 = (target["pts"][mini(j + 1, target["pts"].size() - 1)] - target["pts"][maxi(j - 1, 0)]).normalized()
			var normal := Vector2(-dir_major.y, dir_major.x)
			var inner: Vector2 = pts[1] if end == "start_join" else pts[pts.size() - 2]
			var side := signf((inner - snap).dot(normal))
			if side == 0.0:
				side = 1.0
			var edge := snap + normal * side * (float(target["width"]) * 0.5 + 0.2)
			# rebuild the minor road's end: replace samples within 20 m of the edge with a straight run
			var keep: Array[Vector2] = []
			if end == "start_join":
				var k := 0
				while k < pts.size() - 2 and pts[k].distance_to(edge) < 22.0:
					k += 1
				keep.append(edge)
				var a := edge
				var b := pts[k]
				var seg := int(a.distance_to(b) / STEP)
				for s in range(1, seg):
					keep.append(a.lerp(b, float(s) / seg))
				for m in range(k, pts.size()):
					keep.append(pts[m])
			else:
				var k := pts.size() - 1
				while k > 1 and pts[k].distance_to(edge) < 22.0:
					k -= 1
				for m in k + 1:
					keep.append(pts[m])
				var a := pts[k]
				var b := edge
				var seg := int(a.distance_to(b) / STEP)
				for s in range(1, seg):
					keep.append(a.lerp(b, float(s) / seg))
				keep.append(edge)
			r["pts"] = keep
			(r["joins"] as Array).append({"end": 0 if end == "start_join" else 1, "road": ti, "index": j, "pos": snap, "edge": edge})
	# indices into target roads may have shifted when the targets themselves were snapped
	for r in roads:
		for j in r["joins"]:
			var tgt: Dictionary = roads[j["road"]]
			j["index"] = _nearest_index(tgt["pts"], j["pos"])
			j["pos"] = tgt["pts"][j["index"]]
	# elevation profiles in dependency order (join targets first)
	var done := {}
	var order: Array[int] = []
	var guard := 0
	while order.size() < roads.size() and guard < 100:
		guard += 1
		for ri in roads.size():
			if done.has(ri):
				continue
			var ready := true
			for j in roads[ri]["joins"]:
				if not done.has(j["road"]) and j["road"] != ri:
					ready = false
			if ready:
				order.append(ri)
				done[ri] = true
	for ri in order:
		_profile(roads[ri])
	# banking, total length
	var total := 0.0
	var loop_len := 0.0
	var per := {}
	for r in roads:
		var pts: Array[Vector2] = r["pts"]
		var length := (pts.size() - 1) * STEP if not r["closed"] else pts.size() * STEP
		total += length
		per[r["name"]] = int(length)
		if r["scenic"]:
			loop_len = length
		_bank(r)
	stats["road_total_m"] = int(total)
	stats["scenic_loop_m"] = int(loop_len)
	stats["roads"] = per
	_check_crossings()


func _nearest_index(pts: Array, p: Vector2) -> int:
	var best := 0
	var bd := 1e18
	for i in pts.size():
		var d := (pts[i] as Vector2).distance_squared_to(p)
		if d < bd:
			bd = d
			best = i
	return best


func _profile(r: Dictionary) -> void:
	var pts: Array[Vector2] = r["pts"]
	var n := pts.size()
	var closed: bool = r["closed"]
	var y := PackedFloat32Array()
	y.resize(n)
	for i in n:
		y[i] = hget(H0, pts[i].x, pts[i].y)
		# never plan the road below water: aim for the bank level
		var wl := water_at(pts[i].x, pts[i].y)
		if wl > -999.0:
			y[i] = maxf(y[i], wl + 1.0)
	# moving average
	var half_k := int(float(r["smooth"]) * 0.5 / STEP)
	y = _smooth(y, half_k, closed)
	# fixed pins from junctions
	var pinned := {}
	for j in r["joins"]:
		var target: Dictionary = roads[j["road"]]
		var ty: PackedFloat32Array = target["y"]
		var yy: float = ty[j["index"]] if ty.size() > 0 else y[0]
		var idx := 0 if j["end"] == 0 else n - 1
		var delta := yy - y[idx]
		for i in n:
			var dist := float(i if j["end"] == 0 else n - 1 - i) * STEP
			y[i] += delta * (1.0 - smoothstep(0.0, 90.0, dist))
		y[idx] = yy
		pinned[idx] = yy
		# the first 8 m are flat at the junction height (clean merge)
		for k in 5:
			var ii := k if j["end"] == 0 else n - 1 - k
			y[ii] = yy
			pinned[ii] = yy
	var grades := PackedFloat32Array()
	grades.resize(n)
	for i in n:
		var gr := float(r["grade"])
		if r["class"] in ["main", "highway"]:
			gr = lerpf(gr, maxf(gr, 0.11), smoothstep(0.35, 0.75, region_weights(pts[i].x, pts[i].y).z))
		grades[i] = gr
	var grades_soft := grades.duplicate()
	for i in n:
		grades_soft[i] *= 1.05
	# tunnels: straight grade between portals
	for tr in r.get("tunnels", []):
		var a: int = tr[0]
		var b: int = tr[1]
		for i in range(a, b + 1):
			y[i] = lerpf(y[a], y[b], float(i - a) / float(maxi(b - a, 1)))
	y = _grade_limit(y, grades, closed, pinned)
	# water clearance for bridges
	var need := PackedFloat32Array()
	need.resize(n)
	var any := false
	for i in n:
		var wl := water_at(pts[i].x, pts[i].y)
		if wl > -999.0:
			var req := wl + (5.5 if r["class"] == "highway" else 4.2)
			if y[i] < req:
				need[i] = req - y[i]
				any = true
	if any:
		var add := PackedFloat32Array()
		add.resize(n)
		for i in n:
			if need[i] <= 0.0:
				continue
			for k in range(-45, 46):
				var j := i + k
				if closed:
					j = posmod(j, n)
				elif j < 0 or j >= n:
					continue
				var w := 1.0 - smoothstep(0.0, 45.0, absf(float(k)))
				add[j] = maxf(add[j], need[i] * (0.35 + 0.65 * w) if absf(k) < 10 else need[i] * w)
		for i in n:
			y[i] += add[i]
		y = _grade_limit(y, grades_soft, closed, pinned)
	y = _smooth(y, 3, closed, pinned)
	y = _grade_limit(y, grades_soft, closed, pinned)
	# vertical curves: a moving average keeps the grade limit and spreads crest/sag kinks over ~50 m
	y = _smooth(y, 12, closed, pinned)
	y = _grade_limit(y, grades_soft, closed, pinned)
	var gmax := float(r["grade"]) * STEP * 1.25
	for i in range(1, n):
		if absf(y[i] - y[i - 1]) > gmax:
			print("[bake] GRADE %s i=%d dy=%.2f pinned=%s keys=%s" % [r["name"], i, y[i] - y[i - 1], str(pinned.has(i)), str(pinned.keys())])
			break
	r["y"] = y
	# flags: bridges / tunnels
	var flags := PackedInt32Array()
	flags.resize(n)
	for tr in r.get("tunnels", []):
		for i in range(tr[0], tr[1] + 1):
			flags[i] |= F_TUNNEL
	for i in n:
		var g := hget(H0, pts[i].x, pts[i].y)
		var wl := water_at(pts[i].x, pts[i].y)
		var gap := y[i] - g
		if gap > 9.5 or (wl > -999.0 and gap > 1.5):
			flags[i] |= F_BRIDGE
	# clean spans: fill small holes, drop tiny spans, extend bridges to abutments
	flags = _clean_span(flags, F_BRIDGE, 6, 4, closed)
	flags = _clean_span(flags, F_TUNNEL, 10, 0, closed)
	for i in n:
		if flags[i] & F_TUNNEL:
			flags[i] &= ~F_BRIDGE
	if r["spec"]["class"] == "village":
		for i in n:
			flags[i] |= F_VILLAGE
	for j in r["joins"]:
		for k in 6:
			var ii: int = k if j["end"] == 0 else n - 1 - k
			flags[ii] |= F_JUNCTION
	r["flags"] = flags


func _smooth(y: PackedFloat32Array, half_k: int, closed: bool, pinned: Dictionary = {}) -> PackedFloat32Array:
	var n := y.size()
	if half_k <= 0 or n < 3:
		return y
	var out := PackedFloat32Array()
	out.resize(n)
	var prefix := PackedFloat64Array()
	prefix.resize(n + 1)
	for i in n:
		prefix[i + 1] = prefix[i] + y[i]
	for i in n:
		if pinned.has(i):
			out[i] = pinned[i]
			continue
		if closed:
			var acc := 0.0
			for k in range(-half_k, half_k + 1):
				acc += y[posmod(i + k, n)]
			out[i] = acc / float(2 * half_k + 1)
		else:
			var a := maxi(i - half_k, 0)
			var b := mini(i + half_k, n - 1)
			out[i] = float((prefix[b + 1] - prefix[a]) / float(b - a + 1))
	return out


func _grade_limit(y: PackedFloat32Array, grades: PackedFloat32Array, closed: bool, pinned: Dictionary) -> PackedFloat32Array:
	## Slope-limits a planned profile: |y[i] - y[i-1]| <= grades[i] * STEP.
	## Result = the lower slope-limited envelope L(i) = min_j(y_j + dist_g(i, j)), i.e. the road
	## follows the ground wherever that is gentle enough and cuts at full grade through anything
	## steeper (no towering embankments). Junction pins bound every sample through grade cones;
	## pins further apart than the grade allows relax the whole road to what they require.
	var n := y.size()
	if n < 2:
		return y
	var g := PackedFloat32Array()
	g.resize(n)
	for i in n:
		g[i] = grades[i] * STEP
	var keys := pinned.keys()
	keys.sort()
	var relax := 1.0
	for a in keys.size():
		for b in range(a + 1, keys.size()):
			var lo_i := int(keys[a])
			var hi_i := int(keys[b])
			var allow := 0.0
			for k in range(lo_i + 1, hi_i + 1):
				allow += g[k]
			if allow > 0.0:
				relax = maxf(relax, absf(float(pinned[keys[b]]) - float(pinned[keys[a]])) / allow * 1.12)
	if relax > 1.0:
		for i in n:
			g[i] *= relax
	var laps := 2 if closed else 1
	# pin cones (upper / lower bounds reachable from every pin at the local grade)
	var lo := PackedFloat32Array()
	var hi := PackedFloat32Array()
	lo.resize(n)
	hi.resize(n)
	lo.fill(-1e9)
	hi.fill(1e9)
	for p in pinned:
		lo[int(p)] = pinned[p]
		hi[int(p)] = pinned[p]
	for k in range(1, n * laps):
		var i := k % n
		var pi := (k - 1) % n
		lo[i] = maxf(lo[i], lo[pi] - g[i])
		hi[i] = minf(hi[i], hi[pi] + g[i])
	for k in range(n * laps - 2, -1, -1):
		var i := k % n
		var ni := (k + 1) % n
		lo[i] = maxf(lo[i], lo[ni] - g[ni])
		hi[i] = minf(hi[i], hi[ni] + g[ni])
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		out[i] = clampf(y[i], lo[i], hi[i]) if lo[i] <= hi[i] else (lo[i] + hi[i]) * 0.5
	# lower envelope
	for k in range(1, n * laps):
		var i := k % n
		out[i] = minf(out[i], out[(k - 1) % n] + g[i])
	for k in range(n * laps - 2, -1, -1):
		var i := k % n
		var ni := (k + 1) % n
		out[i] = minf(out[i], out[ni] + g[ni])
	for i in n:
		out[i] = maxf(out[i], lo[i])
	for p in pinned:
		out[int(p)] = pinned[p]
	return out


func _clean_span(flags: PackedInt32Array, bit: int, min_len: int, extend: int, _closed: bool) -> PackedInt32Array:
	var n := flags.size()
	# fill gaps shorter than 6 samples
	var i := 0
	while i < n:
		if flags[i] & bit:
			var j := i
			while j < n and flags[j] & bit:
				j += 1
			var k := j
			while k < n and not (flags[k] & bit):
				k += 1
			if k < n and k - j < 6:
				for m in range(j, k):
					flags[m] |= bit
			i = j
		else:
			i += 1
	# remove short spans, extend the rest
	i = 0
	var spans := []
	while i < n:
		if flags[i] & bit:
			var j := i
			while j < n and flags[j] & bit:
				j += 1
			spans.append([i, j - 1])
			i = j
		else:
			i += 1
	for s in spans:
		if s[1] - s[0] + 1 < min_len:
			for m in range(s[0], s[1] + 1):
				flags[m] &= ~bit
		else:
			for m in range(maxi(s[0] - extend, 0), mini(s[1] + extend, n - 1) + 1):
				flags[m] |= bit
	return flags


func _bank(r: Dictionary) -> void:
	var pts: Array[Vector2] = r["pts"]
	var n := pts.size()
	var bank := PackedFloat32Array()
	bank.resize(n)
	var closed: bool = r["closed"]
	var v := float(r["speed"]) / 3.6
	var maxb := deg_to_rad(5.5 if r["class"] in ["highway", "main"] else 4.0)
	if r["class"] in ["dirt", "gravel", "village"]:
		maxb = deg_to_rad(2.5)
	for i in n:
		var a := pts[posmod(i - 4, n)] if closed else pts[maxi(i - 4, 0)]
		var b := pts[i]
		var c := pts[posmod(i + 4, n)] if closed else pts[mini(i + 4, n - 1)]
		var d1 := (b - a).normalized()
		var d2 := (c - b).normalized()
		var turn := d1.angle_to(d2)
		var seg := maxf(a.distance_to(b) + b.distance_to(c), 1.0) * 0.5
		var curv := turn / seg
		bank[i] = clampf(atan(curv * v * v / 9.81 * 0.45), -maxb, maxb)
	bank = _smooth(bank, 6, closed)
	var flags: PackedInt32Array = r["flags"]
	for i in n:
		if flags[i] & (F_JUNCTION | F_BRIDGE):
			bank[i] *= 0.3
	r["bank"] = bank


func _check_crossings() -> void:
	var issues := []
	for a in roads.size():
		for b in range(a + 1, roads.size()):
			var pa: Array[Vector2] = roads[a]["pts"]
			var pb: Array[Vector2] = roads[b]["pts"]
			var step_a := 8
			for i in range(0, pa.size() - step_a, step_a):
				var a0 := pa[i]
				var a1 := pa[i + step_a]
				for j in range(0, pb.size() - step_a, step_a):
					var b0 := pb[j]
					if a0.distance_squared_to(b0) > 400.0 * 400.0:
						continue
					var b1 := pb[j + step_a]
					var hit = Geometry2D.segment_intersects_segment(a0, a1, b0, b1)
					if hit != null:
						var hp: Vector2 = hit
						# ignore designed junctions (endpoints)
						var near_end := false
						for jn in roads[a]["joins"] + roads[b]["joins"]:
							if (jn["pos"] as Vector2).distance_to(hp) < 40.0 or (jn["edge"] as Vector2).distance_to(hp) < 40.0:
								near_end = true
						if not near_end:
							issues.append("%s x %s at (%.0f, %.0f)" % [roads[a]["name"], roads[b]["name"], hp.x, hp.y])
	stats["unplanned_crossings"] = issues


# =================================================================================================
# terrain carving
func _carve_roads() -> void:
	H = H0.duplicate()
	var acc_w := PackedFloat32Array()
	acc_w.resize(N * N)
	var acc_wp := PackedFloat32Array()
	acc_wp.resize(N * N)
	var acc_wpt := PackedFloat32Array()
	acc_wpt.resize(N * N)
	var max_cut := 0.0
	var max_fill := 0.0
	for r in roads:
		var pts: Array[Vector2] = r["pts"]
		var y: PackedFloat32Array = r["y"]
		var flags: PackedInt32Array = r["flags"]
		var bank: PackedFloat32Array = r["bank"]
		var n := pts.size()
		var half := float(r["width"]) * 0.5
		var core := half + (1.6 if r["class"] in ["highway", "main"] else 1.0)
		var surf := 1 if r["surface"] in ["asphalt", "concrete"] else (2 if r["surface"] == "gravel" else 3)
		for i in n:
			var f := flags[i]
			if f & F_TUNNEL:
				continue  # portal holes are marked after all carving (_tunnel_holes)
			var near_bridge_end := false
			if f & F_BRIDGE:
				# keep carving near abutments only
				var prev_ok := i > 2 and not (flags[i - 3] & F_BRIDGE)
				var next_ok := i < n - 3 and not (flags[i + 3] & F_BRIDGE)
				if not (prev_ok or next_ok):
					continue
				near_bridge_end = true
			var p := pts[i]
			var dir := (pts[mini(i + 1, n - 1)] - pts[maxi(i - 1, 0)]).normalized()
			var nrm := Vector2(-dir.y, dir.x)
			var ground := hget(H0, p.x, p.y)
			var dh := absf(y[i] - ground)
			if y[i] - ground > max_fill and not (f & F_BRIDGE):
				max_fill = y[i] - ground
			if ground - y[i] > max_cut:
				max_cut = ground - y[i]
			var fall := clampf(dh * 1.5 + 6.0, 6.0, 55.0)
			if near_bridge_end:
				fall = minf(fall, 12.0)
			var reach := core + fall
			var tb := tan(bank[i])
			var a := -1.0
			while a <= 1.0:
				var l := -reach
				while l <= reach:
					var q := p + dir * a + nrm * l
					l += 1.0
					var ix := int(round((q.x + HALF) / RES))
					var iz := int(round((q.y + HALF) / RES))
					if ix < 0 or iz < 0 or ix >= N or iz >= N:
						continue
					var idx := iz * N + ix
					var c := Vector2(-HALF + ix * RES, -HALF + iz * RES) - p
					var lat := c.dot(nrm)
					var d := absf(lat)
					if d > reach:
						continue
					var lat_c := clampf(lat, -core, core)
					var t := y[i] - lat_c * tb - 0.16
					var w: float
					if d <= core:
						w = 1.0
						if d <= half:
							road_core[idx] = surf
					else:
						w = 1.0 - smoothstep(core, reach, d)
					if w > acc_w[idx]:
						acc_w[idx] = w
					var wp := w * w * w * w
					acc_wp[idx] += wp
					acc_wpt[idx] += wp * t
				a += 1.0
	for i in N * N:
		var w := acc_w[i]
		if w <= 0.0:
			continue
		var t := acc_wpt[i] / maxf(acc_wp[i], 1e-9)
		H[i] = lerpf(H0[i], t, w)
	_cone_cut()
	_tunnel_holes()
	stats["max_cut_m"] = snappedf(max_cut, 0.1)
	stats["max_fill_m"] = snappedf(max_fill, 0.1)


func _cone_cut() -> void:
	## Hillsides may not rise faster than WALL_SLOPE above any road: where grade-limited roads run
	## below steep ground (mountain passes) the terrain is cut down to the cone surface
	## V(x) = min_road(y_road + WALL_SLOPE * distance), giving clean pass valleys of bounded
	## steepness. V is a two-pass chamfer distance transform seeded with the road heights.
	const WALL_SLOPE := 1.15
	var t0 := Time.get_ticks_msec()
	var big := 1e9
	var V := PackedFloat32Array()
	V.resize(N * N)
	V.fill(big)
	for r in roads:
		var pts: Array[Vector2] = r["pts"]
		var y: PackedFloat32Array = r["y"]
		var flags: PackedInt32Array = r["flags"]
		var half := float(r["width"]) * 0.5 + 3.5   # verge before a cut wall starts
		for i in pts.size():
			# bridges seed too: ground that reaches up to a low deck (river banks) is cut below it
			if flags[i] & F_TUNNEL:
				continue
			var p := pts[i]
			var x0 := maxi(int((p.x - half + HALF) / RES), 0)
			var x1 := mini(int((p.x + half + HALF) / RES) + 1, N - 1)
			var z0 := maxi(int((p.y - half + HALF) / RES), 0)
			var z1 := mini(int((p.y + half + HALF) / RES) + 1, N - 1)
			for iz in range(z0, z1 + 1):
				for ix in range(x0, x1 + 1):
					var c := Vector2(-HALF + ix * RES, -HALF + iz * RES)
					if c.distance_to(p) <= half:
						var idx := iz * N + ix
						V[idx] = minf(V[idx], y[i] - 0.2)
	var s1 := WALL_SLOPE * RES
	var s2 := WALL_SLOPE * RES * 1.41421
	for z in N:
		var row := z * N
		for x in N:
			var idx := row + x
			var v := V[idx]
			if x > 0:
				v = minf(v, V[idx - 1] + s1)
			if z > 0:
				v = minf(v, V[idx - N] + s1)
				if x > 0:
					v = minf(v, V[idx - N - 1] + s2)
				if x < N - 1:
					v = minf(v, V[idx - N + 1] + s2)
			V[idx] = v
	for z in range(N - 1, -1, -1):
		var row := z * N
		for x in range(N - 1, -1, -1):
			var idx := row + x
			var v := V[idx]
			if x < N - 1:
				v = minf(v, V[idx + 1] + s1)
			if z < N - 1:
				v = minf(v, V[idx + N] + s1)
				if x < N - 1:
					v = minf(v, V[idx + N + 1] + s2)
				if x > 0:
					v = minf(v, V[idx + N - 1] + s2)
			V[idx] = v
	var cut_cells := 0
	var deepest := 0.0
	for i in N * N:
		if V[i] < H[i]:
			deepest = maxf(deepest, H[i] - V[i])
			H[i] = V[i]
			cut_cells += 1
	stats["cone_cut_cells"] = cut_cells
	stats["cone_cut_max_m"] = snappedf(deepest, 0.1)
	print("[bake] cone cut %d cells, deepest %.1f m in %d ms" % [cut_cells, deepest, Time.get_ticks_msec() - t0])


func _tunnel_holes() -> void:
	## open the terrain wherever the final ground is below the tunnel ceiling (portals, shallow
	## stretches), so the tube is never blocked by the surface
	var marked := 0
	for r in roads:
		var pts: Array[Vector2] = r["pts"]
		var y: PackedFloat32Array = r["y"]
		var flags: PackedInt32Array = r["flags"]
		var n := pts.size()
		var half := float(r["width"]) * 0.5 + 1.5
		for i in n:
			if flags[i] & F_TUNNEL and hget(H, pts[i].x, pts[i].y) < y[i] + 11.0:
				_mark_holes(pts, i, n, half)
				marked += 1
	stats["tunnel_hole_samples"] = marked


func _mark_holes(pts: Array[Vector2], i: int, n: int, half: float) -> void:
	var p := pts[i]
	var dir := (pts[mini(i + 1, n - 1)] - pts[maxi(i - 1, 0)]).normalized()
	var nrm := Vector2(-dir.y, dir.x)
	var reach := half + 2.0
	var x0 := maxi(int((p.x - reach + HALF) / RES), 0)
	var x1 := mini(int((p.x + reach + HALF) / RES) + 1, N - 1)
	var z0 := maxi(int((p.y - reach + HALF) / RES), 0)
	var z1 := mini(int((p.y + reach + HALF) / RES) + 1, N - 1)
	for iz in range(z0, z1 + 1):
		for ix in range(x0, x1 + 1):
			var c := Vector2(-HALF + ix * RES, -HALF + iz * RES) - p
			if absf(c.dot(dir)) <= STEP * 1.5 and absf(c.dot(nrm)) <= reach:
				holes[iz * N + ix] = 1


# =================================================================================================
# per-sample flags that need the final terrain: guard rails
func _road_flags() -> void:
	for r in roads:
		var pts: Array[Vector2] = r["pts"]
		var y: PackedFloat32Array = r["y"]
		var flags: PackedInt32Array = r["flags"]
		var n := pts.size()
		var half := float(r["width"]) * 0.5
		var mountain: bool = r["class"] == "mountain" or r["spec"].get("scenic", false)
		for i in n:
			if flags[i] & (F_TUNNEL | F_BRIDGE | F_JUNCTION):
				continue
			var dir := (pts[mini(i + 1, n - 1)] - pts[maxi(i - 1, 0)]).normalized()
			var nrm := Vector2(-dir.y, dir.x)
			for side in [-1.0, 1.0]:
				var probe: Vector2 = pts[i] + nrm * side * (half + 4.5)
				var drop := y[i] - hget(H, probe.x, probe.y)
				var limit := 2.2 if mountain else 3.2
				if drop > limit and r["class"] != "dirt":
					flags[i] |= (F_RAIL_R if side > 0.0 else F_RAIL_L)
		# continuous rails: fill gaps < 10 samples, drop runs < 8 samples
		for bit in [F_RAIL_L, F_RAIL_R]:
			flags = _clean_span(flags, bit, 8, 3, r["closed"])
		r["flags"] = flags


# =================================================================================================
# settlements, landmarks, roadside props
var _road_hash: Dictionary = {}
const HASH_CELL := 32.0


func _build_road_hash() -> void:
	_road_hash.clear()
	for ri in roads.size():
		var pts: Array[Vector2] = roads[ri]["pts"]
		for i in pts.size():
			var key := Vector2i(int(floor(pts[i].x / HASH_CELL)), int(floor(pts[i].y / HASH_CELL)))
			if not _road_hash.has(key):
				_road_hash[key] = PackedInt32Array()
			var arr: PackedInt32Array = _road_hash[key]
			arr.append(ri)
			arr.append(i)
			_road_hash[key] = arr


func _dist_to_roads(p: Vector2, max_d: float) -> float:
	var best := 1e9
	var r := int(ceil((max_d + 12.0) / HASH_CELL))
	var cx := int(floor(p.x / HASH_CELL))
	var cz := int(floor(p.y / HASH_CELL))
	for dz in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var key := Vector2i(cx + dx, cz + dz)
			if not _road_hash.has(key):
				continue
			var arr: PackedInt32Array = _road_hash[key]
			for k in range(0, arr.size(), 2):
				var rd: Dictionary = roads[arr[k]]
				var q: Vector2 = rd["pts"][arr[k + 1]]
				best = minf(best, q.distance_to(p) - float(rd["width"]) * 0.5)
	return best


func _nearest_road_point(p: Vector2) -> Dictionary:
	var best := {"d": 1e9, "road": 0, "i": 0}
	for rad in [2, 5, 12, 40]:
		var cx := int(floor(p.x / HASH_CELL))
		var cz := int(floor(p.y / HASH_CELL))
		for dz in range(-rad, rad + 1):
			for dx in range(-rad, rad + 1):
				var key := Vector2i(cx + dx, cz + dz)
				if not _road_hash.has(key):
					continue
				var arr: PackedInt32Array = _road_hash[key]
				for k in range(0, arr.size(), 2):
					var q: Vector2 = roads[arr[k]]["pts"][arr[k + 1]]
					var d := q.distance_to(p)
					if d < best["d"]:
						best = {"d": d, "road": arr[k], "i": arr[k + 1]}
		if best["d"] < 1e8:
			return best
	return best


func _slope_at(x: float, z: float) -> float:
	var h1 := hget(H, x - 2.0, z)
	var h2 := hget(H, x + 2.0, z)
	var h3 := hget(H, x, z - 2.0)
	var h4 := hget(H, x, z + 2.0)
	return Vector2((h2 - h1) / 4.0, (h4 - h3) / 4.0).length()


func _add_prop(kind: String, x: float, z: float, yaw: float, s: float = 1.0, extra: Dictionary = {}) -> void:
	var p := {"k": kind, "p": [snappedf(x, 0.01), snappedf(hget(H, x, z), 0.01), snappedf(z, 0.01)], "r": snappedf(yaw, 0.001), "s": snappedf(s, 0.01)}
	p.merge(extra)
	props.append(p)


func _place_props() -> void:
	_build_road_hash()
	# settlements: buildings face the nearest road, keep clear of roads and steep ground
	for st in L.SETTLEMENTS:
		var c := Vector2(st["pos"][0], st["pos"][1])
		var rad: float = st["radius"]
		var kind: String = st["kind"]
		var count: int = st["houses"]
		var placed: Array[Vector2] = []
		var tries := 0
		var types: Array = []
		match kind:
			"village":
				types = ["house_a", "house_b", "house_c", "house_a", "house_b", "shop", "church"]
			"harbour":
				types = ["house_b", "house_c", "boathouse", "house_a"]
			"farm":
				types = ["farmhouse", "barn", "silo", "barn"]
			"hamlet":
				types = ["house_a", "house_c", "barn"]
			"gas":
				types = ["gas_station"]
			_:
				types = []
		var special_done := {}
		while placed.size() < count and tries < 4000 and types.size() > 0:
			tries += 1
			var a := rng.randf() * TAU
			var rr := sqrt(rng.randf()) * rad
			var p := c + Vector2(cos(a), sin(a)) * rr
			var t: String = types[placed.size() % types.size()]
			if (t == "church" or t == "gas_station" or t == "silo") and special_done.has(t):
				t = types[0]
			var clear := 9.0 if t in ["barn", "church", "gas_station"] else 6.5
			if t == "gas_station":
				clear = 7.0
			var dr := _dist_to_roads(p, 40.0)
			if dr < clear or dr > (22.0 if kind != "farm" else 55.0):
				continue
			if _slope_at(p.x, p.y) > 0.28:
				continue
			if water_at(p.x, p.y) > -999.0 or hget(H, p.x, p.y) < 1.5:
				continue
			var ok := true
			for q in placed:
				if q.distance_to(p) < (17.0 if t != "silo" else 9.0):
					ok = false
					break
			if not ok:
				continue
			var nr := _nearest_road_point(p)
			var rp: Vector2 = roads[nr["road"]]["pts"][nr["i"]]
			var face := rp - p
			var yaw := atan2(face.x, face.y)
			yaw = snappedf(yaw, PI / 2.0) if kind in ["village", "harbour"] and rng.randf() < 0.3 else yaw
			_add_prop(t, p.x, p.y, yaw, 1.0, {"settlement": st["name"]})
			placed.append(p)
			special_done[t] = true
			# flatten a pad under the building
			_flatten(p, 9.0 if t != "barn" else 12.0)
		if kind == "village" or kind == "harbour" or kind == "hamlet":
			# street lamps along the settlement roads
			for r in roads:
				var pts: Array[Vector2] = r["pts"]
				var nn := pts.size()
				for i in range(0, nn, 16):
					if pts[i].distance_to(c) > rad * 1.15:
						continue
					var dir := (pts[mini(i + 1, nn - 1)] - pts[maxi(i - 1, 0)]).normalized()
					var nrm := Vector2(-dir.y, dir.x)
					var side := 1.0 if (i / 16) % 2 == 0 else -1.0
					var q := pts[i] + nrm * side * (float(r["width"]) * 0.5 + 1.6)
					_add_prop("street_lamp", q.x, q.y, atan2(-nrm.x * side, -nrm.y * side))
		if kind == "festival":
			_festival(c)
		if kind == "harbour":
			_add_prop("pier", coast_x(c.y) + 12.0, c.y - 20.0, PI * 0.5)
			_add_prop("boat", coast_x(c.y) - 25.0, c.y + 10.0, 0.4)
			_add_prop("boat", coast_x(c.y) - 40.0, c.y - 45.0, 1.9)
		if kind == "viewpoint":
			_add_prop("viewpoint", c.x, c.y, 0.0)
	# landmarks
	for lm in L.LANDMARKS:
		var p := Vector2(lm["pos"][0], lm["pos"][1])
		match lm["kind"]:
			"lighthouse":
				_flatten(p, 10.0)
				_add_prop("lighthouse", p.x, p.y, 0.0)
			"castle":
				_flatten(p, 22.0)
				_add_prop("castle_ruin", p.x, p.y, 0.6)
			"windfarm":
				for k in 7:
					var q := p + Vector2(-260.0 + k * 85.0, -40.0 + sin(k * 1.3) * 60.0)
					if _dist_to_roads(q, 30.0) > 14.0:
						_add_prop("wind_turbine", q.x, q.y, 0.8, 1.0)
	# roadside furniture along every road
	for ri in roads.size():
		var r: Dictionary = roads[ri]
		var pts: Array[Vector2] = r["pts"]
		var y: PackedFloat32Array = r["y"]
		var flags: PackedInt32Array = r["flags"]
		var n := pts.size()
		var half := float(r["width"]) * 0.5
		var paved: bool = r["surface"] in ["asphalt", "concrete"]
		var spacing := 25 if r["class"] == "highway" else 22
		for i in range(4, n - 4, spacing):
			if flags[i] & (F_TUNNEL | F_BRIDGE | F_JUNCTION | F_VILLAGE):
				continue
			if not paved:
				continue
			var dir := (pts[i + 1] - pts[i - 1]).normalized()
			var nrm := Vector2(-dir.y, dir.x)
			for side in [-1.0, 1.0]:
				if flags[i] & (F_RAIL_R if side > 0.0 else F_RAIL_L):
					continue
				var q: Vector2 = pts[i] + nrm * side * (half + 1.3)
				_add_prop("reflector_post", q.x, q.y, atan2(dir.x, dir.y) + (PI if side < 0.0 else 0.0), 1.0, {"y": y[i]})
		# curve chevrons on sharp bends
		var k := 8
		while k < n - 8:
			var d1 := (pts[k] - pts[k - 6]).normalized()
			var d2 := (pts[k + 6] - pts[k]).normalized()
			var turn := d1.angle_to(d2)
			if absf(turn) > 0.55 and not (flags[k] & (F_TUNNEL | F_BRIDGE)) and r["class"] != "dirt":
				var nrm := Vector2(-d2.y, d2.x)
				var outer := -signf(turn)
				for m in [-6, 0, 6]:
					var kk := clampi(k + m, 0, n - 1)
					var q: Vector2 = pts[kk] + nrm * outer * (half + 2.2)
					_add_prop("chevron", q.x, q.y, atan2(-d1.x, -d1.y), 1.0)
				# warning sign before the bend
				var pre := maxi(k - 40, 0)
				var dpre := (pts[mini(pre + 1, n - 1)] - pts[pre]).normalized()
				var npre := Vector2(-dpre.y, dpre.x)
				var qs: Vector2 = pts[pre] + npre * (half + 2.0)
				_add_prop("sign_curve_r" if turn > 0.0 else "sign_curve_l", qs.x, qs.y, atan2(-dpre.x, -dpre.y))
				k += 30
			else:
				k += 2
		# speed limit signs at road starts
		if not r["closed"] and paved:
			var d0 := (pts[mini(8, n - 1)] - pts[0]).normalized()
			var n0 := Vector2(-d0.y, d0.x)
			var q0: Vector2 = pts[mini(10, n - 1)] + n0 * (half + 2.0)
			_add_prop("sign_speed", q0.x, q0.y, atan2(-d0.x, -d0.y), 1.0, {"v": r["speed"]})
	# route signs at junctions
	for r in roads:
		for j in r["joins"]:
			var e: Vector2 = j["edge"]
			var tgt: Dictionary = roads[j["road"]]
			var pts: Array[Vector2] = tgt["pts"]
			var ji: int = j["index"]
			var dmaj := (pts[mini(ji + 1, pts.size() - 1)] - pts[maxi(ji - 1, 0)]).normalized()
			var nm := Vector2(-dmaj.y, dmaj.x)
			var q: Vector2 = e + nm * signf((e - (j["pos"] as Vector2)).dot(nm)) * 3.0 + dmaj * 8.0
			_add_prop("sign_route", q.x, q.y, atan2(dmaj.x, dmaj.y), 1.0, {"text": r["name"]})
	# region welcome signs on the scenic loop
	stats["props"] = props.size()


func _festival(c: Vector2) -> void:
	_flatten(c, 60.0)
	_add_prop("festival_stage", c.x - 20.0, c.y + 25.0, 0.6)
	for k in 6:
		var a := k * TAU / 6.0
		_add_prop("festival_tent", c.x + cos(a) * 42.0, c.y + sin(a) * 42.0, a + PI)
	for k in 10:
		var a := k * TAU / 10.0 + 0.2
		_add_prop("festival_flag", c.x + cos(a) * 62.0, c.y + sin(a) * 62.0, a)
	_add_prop("festival_arch", c.x + 70.0, c.y - 25.0, 1.1)


func _flatten(p: Vector2, radius: float) -> void:
	var target := hget(H, p.x, p.y)
	var reach := radius + 8.0
	var x0 := maxi(int((p.x - reach + HALF) / RES), 0)
	var x1 := mini(int((p.x + reach + HALF) / RES) + 1, N - 1)
	var z0 := maxi(int((p.y - reach + HALF) / RES), 0)
	var z1 := mini(int((p.y + reach + HALF) / RES) + 1, N - 1)
	for iz in range(z0, z1 + 1):
		for ix in range(x0, x1 + 1):
			var d := Vector2(-HALF + ix * RES, -HALF + iz * RES).distance_to(p)
			if d > reach:
				continue
			var idx := iz * N + ix
			if road_core[idx] != 0:
				continue
			var w := 1.0 - smoothstep(radius, reach, d)
			H[idx] = lerpf(H[idx], target, w)


# =================================================================================================
# output
func _write() -> void:
	var dir := "res://data/world/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var f := FileAccess.open_compressed(dir + "height.bin", FileAccess.WRITE, FileAccess.COMPRESSION_ZSTD)
	f.store_buffer(H.to_byte_array())
	f.close()
	f = FileAccess.open_compressed(dir + "holes.bin", FileAccess.WRITE, FileAccess.COMPRESSION_ZSTD)
	f.store_buffer(holes)
	f.close()
	# splat 1024: R field, G desert, B forest/soil, A sand
	var S := 1024
	var sbytes := PackedByteArray()
	sbytes.resize(S * S * 4)
	var field_n := FastNoiseLite.new()
	field_n.seed = L.SEED + 77
	field_n.frequency = 0.004
	field_n.noise_type = FastNoiseLite.TYPE_CELLULAR
	field_n.cellular_return_type = FastNoiseLite.RETURN_CELL_VALUE
	var forest_n := FastNoiseLite.new()
	forest_n.seed = L.SEED + 78
	forest_n.frequency = 0.0035
	forest_n.fractal_octaves = 3
	for py in S:
		var z := -HALF + (py + 0.5) * (2.0 * HALF / S)
		var cxs := coast_x(z)
		for px in S:
			var x := -HALF + (px + 0.5) * (2.0 * HALF / S)
			var w := region_weights(x, z)
			var h := hget(H, x, z)
			var cell := field_n.get_noise_2d(x, z) * 0.5 + 0.5
			var field := w.y * smoothstep(0.35, 0.6, w.y) * (1.0 if cell > 0.38 else 0.0)
			field *= 1.0 - smoothstep(60.0, 90.0, h)
			var fr := forest_n.get_noise_2d(x, z) * 0.5 + 0.5
			var forest := smoothstep(0.52, 0.66, fr) * (w.y * 0.8 + w.z * 1.0 + w.x * 0.5)
			forest *= 1.0 - smoothstep(380.0, 470.0, h)
			field *= 1.0 - forest
			var sand := 0.0
			var d := x - cxs
			if d < 60.0 and z > 200.0:
				sand = 1.0 - smoothstep(20.0, 60.0, d)
			if water_at(x, z) > -999.0:
				sand = maxf(sand, 0.6)
			var o := (py * S + px) * 4
			sbytes[o] = int(clampf(field, 0.0, 1.0) * 255.0)
			sbytes[o + 1] = int(clampf(w.w, 0.0, 1.0) * 255.0)
			sbytes[o + 2] = int(clampf(forest, 0.0, 1.0) * 255.0)
			sbytes[o + 3] = int(clampf(sand, 0.0, 1.0) * 255.0)
	_store_bin(dir + "splat.bin", sbytes)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://qa_out"))
	Image.create_from_data(S, S, false, Image.FORMAT_RGBA8, sbytes).save_png("res://qa_out/splat_preview.png")
	# region index map 256 (L8)
	var RG := 256
	var gbytes := PackedByteArray()
	gbytes.resize(RG * RG)
	for py in RG:
		var z := -HALF + (py + 0.5) * (2.0 * HALF / RG)
		for px in RG:
			var x := -HALF + (px + 0.5) * (2.0 * HALF / RG)
			var w := region_weights(x, z)
			var best := 0
			var bv := w.x
			if w.y > bv:
				best = 1
				bv = w.y
			if w.z > bv:
				best = 2
				bv = w.z
			if w.w > bv:
				best = 3
			gbytes[py * RG + px] = best
	_store_bin(dir + "regions.bin", gbytes)
	# road mask 2048 (L8: 0 none, 85 asphalt, 170 gravel, 255 dirt/sand)
	var R := 2048
	var rbytes := PackedByteArray()
	rbytes.resize(R * R)
	var scale := float(N - 1) / float(R)
	for py in R:
		var iz := clampi(int((py + 0.5) * scale), 0, N - 1)
		for px in R:
			var ix := clampi(int((px + 0.5) * scale), 0, N - 1)
			rbytes[py * R + px] = road_core[iz * N + ix] * 85
	_store_bin(dir + "roadmask.bin", rbytes)
	# roads json
	var out_roads := []
	for r in roads:
		var pts: Array[Vector2] = r["pts"]
		var xs := []
		var zs := []
		var ys := []
		var bs := []
		var fs := []
		for i in pts.size():
			xs.append(snappedf(pts[i].x, 0.01))
			zs.append(snappedf(pts[i].y, 0.01))
			ys.append(snappedf((r["y"] as PackedFloat32Array)[i], 0.01))
			bs.append(snappedf((r["bank"] as PackedFloat32Array)[i], 0.0001))
			fs.append((r["flags"] as PackedInt32Array)[i])
		var joins := []
		for j in r["joins"]:
			joins.append({"end": j["end"], "road": j["road"], "index": j["index"], "pos": [(j["pos"] as Vector2).x, (j["pos"] as Vector2).y]})
		out_roads.append({"name": r["name"], "class": r["class"], "surface": r["surface"], "closed": r["closed"],
			"scenic": r["scenic"], "width": r["width"], "lanes": r["lanes"], "lane_width": r["lane_width"],
			"shoulder": r["shoulder"], "median": r["median"], "speed": r["speed"], "x": xs, "y": ys, "z": zs,
			"bank": bs, "flags": fs, "joins": joins})
	f = FileAccess.open(dir + "roads.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"step": STEP, "roads": out_roads}))
	f.close()
	var rv := []
	for i in river_pts.size():
		rv.append([snappedf(river_pts[i].x, 0.1), snappedf(river_pts[i].y, 0.01), snappedf(river_pts[i].z, 0.1), river_width[i]])
	var meta := {
		"version": 1, "seed": L.SEED, "half": HALF, "res": RES, "n": N, "sea_level": L.SEA_LEVEL,
		"lake": {"center": [L.LAKE_CENTER.x, L.LAKE_CENTER.y], "radii": [L.LAKE_RADII.x, L.LAKE_RADII.y], "level": lake_level},
		"river": rv, "snow_line": L.SNOW_LINE, "props": props, "settlements": L.SETTLEMENTS, "landmarks": L.LANDMARKS,
		"teleports": L.TELEPORTS, "stats": stats,
	}
	f = FileAccess.open(dir + "world_meta.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(meta))
	f.close()


func _store_bin(path: String, bytes: PackedByteArray) -> void:
	var f := FileAccess.open_compressed(path, FileAccess.WRITE, FileAccess.COMPRESSION_ZSTD)
	f.store_buffer(bytes)
	f.close()
