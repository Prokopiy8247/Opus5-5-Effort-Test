extends Node
## Headless validation of the dressing placement rules on real world data: builds a grid of chunks
## exactly like the game (dressing_rules.gd) plus 3x3 blocks around the playtest-3 spots, and checks every
## instance against the exact road network distance, water and terrain height. Playtest-3 regressions:
## every rock / cactus standing >= HULL_MIN_H gets a hull collider with its visible transform (s7/s8/s15),
## nothing but reeds stands in water (s10), no tree trunk or bush grows inside a rock mesh (s12), bushes
## sit on slopes (s13). Also reports worker build time per chunk. Prints RULES_OK / RULES_FAIL.

const Rules := preload("res://scripts/world/dressing_rules.gd")
const PropLibrary := preload("res://scripts/world/prop_library.gd")

const TREE_CLEAR := 9.0
const SMALL_CLEAR := 2.5
const BUSH_FLOAT := 0.6
const HULL_MIN_H := 0.55
const HULL_STRIDE := 13
## Playtest-3 spots (rocks driven through, submerged hedges, trees in rocks, floating bushes).
const FOCUS: Array[Vector2] = [Vector2(-543, -906), Vector2(-1638, -507), Vector2(411, -1019), Vector2(-1731, -1606),
	Vector2(373, -1060), Vector2(427, -997), Vector2(-1663, -916), Vector2(-1332, -869), Vector2(1037, -330),
	Vector2(-170, -757), Vector2(-41, -415), Vector2(-1078, -1780), Vector2(-1533, -1134), Vector2(-709, 485),
	Vector2(-804, 17), Vector2(-814, -192), Vector2(-691, 1015), Vector2(1116, 1018), Vector2(537, 35),
	Vector2(-1636, -1303), Vector2(-1670, -1580), Vector2(-991, -1678), Vector2(1415, 1443)]

var data: WorldData
var _faces: Dictionary = {}
var _columns: Dictionary = {}


func _ready() -> void:
	data = WorldData.new()
	if not data.load_all():
		print("RULES_FAIL no world data")
		get_tree().quit(1)
		return
	var fl := FastNoiseLite.new()
	fl.seed = 12
	fl.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	fl.fractal_type = FastNoiseLite.FRACTAL_FBM
	fl.fractal_octaves = 4
	fl.frequency = 0.006
	var nt := NoiseTexture2D.new()
	nt.width = 512
	nt.height = 512
	nt.seamless = true
	nt.generate_mipmaps = true
	nt.noise = fl
	var t := 0
	while nt.get_image() == null and t < 300:
		await get_tree().process_frame
		t += 1
	var tc := Time.get_ticks_msec()
	var ctx := Rules.make_ctx(data, nt.get_image(), 1.0)
	var tc2 := Time.get_ticks_msec()
	Rules.build_far_meshes(ctx)
	print("  far stand-ins built in %d ms" % (Time.get_ticks_msec() - tc2))
	print("  make_ctx %d ms (far meshes %d, hull points %s)" % [Time.get_ticks_msec() - tc, Rules.far_meshes.size(), (ctx.get("hulls") as Array).map(func(h: PackedVector3Array) -> int: return h.size())])
	var counts: Dictionary = {}
	var viol: Dictionary = {}
	var examples: PackedStringArray = []
	var build_ms: Array[float] = []
	var n_side := int(data.half * 2.0 / Rules.CHUNK)
	var keys: Array[Vector2i] = []
	for j in range(1, n_side - 1, 3):
		for i in range(1, n_side - 1, 3):
			keys.append(Vector2i(i, j))
	for f in FOCUS:
		var c := Vector2i(floori((f.x + Rules.HALF) / Rules.CHUNK), floori((f.y + Rules.HALF) / Rules.CHUNK))
		for dj in range(-1, 2):
			for di in range(-1, 2):
				var k := c + Vector2i(di, dj)
				if k.x >= 0 and k.y >= 0 and k.x < n_side and k.y < n_side and not keys.has(k):
					keys.append(k)
	var rocks: Array = []       # [name, Transform3D world]
	var trees: Array = []       # [name, Transform3D world]
	var bushes: Array = []      # [name, Transform3D world]
	var hull_keys: Dictionary = {}
	var hull_total := 0
	for key in keys:
		var t0 := Time.get_ticks_usec()
		var res := Rules.build_chunk(ctx, key)
		build_ms.append((Time.get_ticks_usec() - t0) / 1000.0)
		var org := Vector3(-Rules.HALF + key.x * Rules.CHUNK, 0.0, -Rules.HALF + key.y * Rules.CHUNK)
		var hl: PackedFloat32Array = res.get("hulls", PackedFloat32Array())
		for k in range(0, hl.size(), HULL_STRIDE):
			hull_keys[Vector3(hl[k], hl[k + 1], hl[k + 2]).snappedf(0.01)] = Basis(Vector3(hl[k + 4], hl[k + 5], hl[k + 6]),
				Vector3(hl[k + 7], hl[k + 8], hl[k + 9]), Vector3(hl[k + 10], hl[k + 11], hl[k + 12]))
			hull_total += 1
		var groups: Dictionary = res["groups"]
		for gk: String in groups:
			var layer := gk.get_slice("|", 0)
			var nm := gk.get_slice("|", 1)
			var buf: PackedFloat32Array = groups[gk]
			var n := buf.size() / Rules.STRIDE
			counts[layer] = int(counts.get(layer, 0)) + n
			if layer.ends_with("far"):
				continue
			for k in n:
				var o := k * Rules.STRIDE
				var xf := Transform3D(Basis(Vector3(buf[o], buf[o + 4], buf[o + 8]), Vector3(buf[o + 1], buf[o + 5], buf[o + 9]),
					Vector3(buf[o + 2], buf[o + 6], buf[o + 10])), org + Vector3(buf[o + 3], buf[o + 7], buf[o + 11]))
				var p := xf.origin
				if layer == "tree":
					trees.append([nm, xf])
				elif layer.begins_with("rock"):
					rocks.append([nm, xf])
				elif layer == "bush":
					bushes.append([nm, xf])
				var near := data.network.nearest(p, 40.0)
				var edge := INF
				# a road in a tunnel below or on a bridge high above is not underfoot
				if not near.is_empty() and absf((near["position"] as Vector3).y - p.y) < 6.0:
					edge = float(near["distance"]) - (near["road"] as RoadNetwork.Road).width * 0.5
				var h := data.height_at(p.x, p.z)
				var problem := ""
				if layer == "tree" and edge < TREE_CLEAR:
					problem = "tree_near_road"
				elif layer != "tree" and edge < SMALL_CLEAR:
					problem = "prop_on_road"
				elif p.y > h + 0.15:
					problem = "floating"
				elif p.y < h - 2.5:
					problem = "sunken"
				elif layer != "reed" and h < 0.3:
					problem = "in_sea"
				elif layer != "reed" and p.y + (0.05 if layer == "tree" else 0.0) < _water_at(p.x, p.z, h) - 0.25:
					problem = "submerged"
				if problem != "":
					_flag(viol, examples, problem, "%s %s at (%.0f, %.1f, %.0f) edge=%.1f h=%.1f" % [problem, gk, p.x, p.y, p.z, edge, h])
	# s7 / s8 / s15: every rock or cactus that stands HULL_MIN_H above the ground has a hull with its own transform
	var solid := 0
	for item: Array in rocks + bushes:
		var nm: String = item[0]
		if not nm.begins_with("Rock_") and not nm.begins_with("Cactus_"):
			continue
		var xf: Transform3D = item[1]
		var top := _top_above_ground(nm, xf)
		if top < HULL_MIN_H + 0.05:
			continue
		solid += 1
		var b: Variant = hull_keys.get(xf.origin.snappedf(0.01))
		if b == null or not (b as Basis).is_equal_approx(xf.basis):
			_flag(viol, examples, "no_collider", "no_collider %s %.1f m tall at %s" % [nm, top, xf.origin.round()])
	# s12: tree trunks and bush centres never inside a rock mesh
	var grid: Dictionary = {}
	for i in rocks.size():
		var o: Vector3 = (rocks[i][1] as Transform3D).origin
		var c := Vector2i(floori(o.x / 16.0), floori(o.z / 16.0))
		var arr: Array = grid.get(c, [])
		arr.append(i)
		grid[c] = arr
	for item: Array in trees + bushes:
		var nm: String = item[0]
		var xf: Transform3D = item[1]
		var pts: Array[Vector3] = []
		if nm.begins_with("Tree_"):
			pts.append(xf.origin + Vector3(0, 1.0, 0))
			pts.append(xf.origin + Vector3(0, 2.0, 0))
		else:
			pts.append(xf.origin + Vector3(0, 0.6, 0))
		var c := Vector2i(floori(xf.origin.x / 16.0), floori(xf.origin.z / 16.0))
		var hit := ""
		for dj in range(-1, 2):
			for di in range(-1, 2):
				for ri: int in grid.get(c + Vector2i(di, dj), []):
					var rxf: Transform3D = rocks[ri][1]
					if rxf.origin.distance_to(xf.origin) > 14.0:
						continue
					for p in pts:
						if _inside(rocks[ri][0], rxf.affine_inverse() * p):
							hit = rocks[ri][0]
		if hit != "":
			_flag(viol, examples, "tree_in_rock" if nm.begins_with("Tree_") else "bush_in_rock", "%s in %s at %s" % [nm, hit, xf.origin.round()])
	# s13: bush canopy rims follow the ground (gap beyond the same bush on flat ground)
	var worst := 0.0
	for item: Array in bushes:
		var nm: String = item[0]
		if not nm.begins_with("Bush_"):
			continue
		var xf: Transform3D = item[1]
		var sy := xf.basis.get_scale().y
		var ex := 0.0
		for col: Vector3 in _low_columns(nm):
			var w := xf * col
			ex = maxf(ex, (w.y - data.height_at(w.x, w.z)) - col.y * sy)
		worst = maxf(worst, ex)
		if ex > BUSH_FLOAT:
			_flag(viol, examples, "bush_float", "bush_float %s %.2f m at %s" % [nm, ex, xf.origin.round()])
	build_ms.sort()
	var total := 0.0
	for v in build_ms:
		total += v
	print("  chunks=%d build_ms avg=%.1f median=%.1f max=%.1f" % [build_ms.size(), total / build_ms.size(), build_ms[build_ms.size() / 2], build_ms[build_ms.size() - 1]])
	print("  instances per layer: ", counts)
	print("  hull colliders %d (rocks/cacti >= %.2f m: %d), worst bush rim gap beyond flat %.2f m" % [hull_total, HULL_MIN_H, solid, worst])
	print("  violations: ", viol)
	for e in examples:
		print("    ", e)
	var bad := 0
	for k: String in viol:
		if k != "sunken":
			bad += int(viol[k])
	print("RULES_OK" if bad == 0 else "RULES_FAIL %d" % bad)
	get_tree().quit(0 if bad == 0 else 1)


func _flag(viol: Dictionary, examples: PackedStringArray, problem: String, line: String) -> void:
	viol[problem] = int(viol.get(problem, 0)) + 1
	if examples.size() < 24:
		examples.append(line)


## World.water_level_at on the raw data.
func _water_at(x: float, z: float, h: float) -> float:
	var lvl := -INF
	if h < WorldLayout.SEA_LEVEL:
		lvl = WorldLayout.SEA_LEVEL
	for lk: Dictionary in data.lake_list():
		if Vector2(x - lk["pos"][0], z - lk["pos"][1]).length() < float(lk["radius"]) * 1.3:
			lvl = maxf(lvl, float(lk["level"]))
	var q := data.gen.river_query(Vector2(x, z))
	if q.x < 13.0:
		lvl = maxf(lvl, q.y)
	return lvl


func _top_above_ground(nm: String, xf: Transform3D) -> float:
	var top := -INF
	for v: Vector3 in _mesh_faces(nm):
		top = maxf(top, (xf * v).y)
	return top - data.height_at(xf.origin.x, xf.origin.z)


func _mesh_faces(nm: String) -> PackedVector3Array:
	if not _faces.has(nm):
		_faces[nm] = PropLibrary.mesh(nm).get_faces()
	return _faces[nm]


## Ray-parity point-in-mesh test in the mesh's local space (+X ray, Moller-Trumbore).
func _inside(nm: String, p: Vector3) -> bool:
	var f := _mesh_faces(nm)
	var hits := 0
	var dir := Vector3(1.0, 0.0013, 0.0007)
	for i in range(0, f.size(), 3):
		var e1 := f[i + 1] - f[i]
		var e2 := f[i + 2] - f[i]
		var pv := dir.cross(e2)
		var det := e1.dot(pv)
		if absf(det) < 1e-9:
			continue
		var tv := p - f[i]
		var u := tv.dot(pv) / det
		if u < 0.0 or u > 1.0:
			continue
		var qv := tv.cross(e1)
		var v := dir.dot(qv) / det
		if v < 0.0 or u + v > 1.0:
			continue
		if e2.dot(qv) / det > 0.0:
			hits += 1
	return hits % 2 == 1


## Lowest mesh vertex per 0.25 m column (local space) of a bush: its canopy rim seen from below.
func _low_columns(nm: String) -> Array[Vector3]:
	if _columns.has(nm):
		return _columns[nm]
	var low: Dictionary = {}
	for v: Vector3 in _mesh_faces(nm):
		var c := Vector2i(floori(v.x / 0.25), floori(v.z / 0.25))
		if not low.has(c) or (low[c] as Vector3).y > v.y:
			low[c] = v
	var res: Array[Vector3] = []
	for c: Vector2i in low:
		res.append(low[c])
	_columns[nm] = res
	return res
