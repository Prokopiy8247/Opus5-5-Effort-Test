extends RefCounted
## Deterministic placement rules for world dressing (trees, far trees, bushes, rocks, hedgerows,
## poplar rows, reeds, grass and flowers). Runs on WorkerThreadPool threads: only reads immutable
## world data and the Ctx snapshot, writes nothing shared. Output buffers are MultiMesh-ready
## (12 transform floats + 4 custom floats per instance, positions relative to the cell origin).
## Collider records: trunk cylinders [x, y, z, radius, height, 0] and convex hulls for rocks / cacti
## [x, y, z, hull index, basis x, basis y, basis z] (the visible instance transform, dressing_colliders.gd).

const CHUNK := 128.0
const HALF := 2048.0
const GRASS_CELL := 24.0
const TREE_ROAD_CLEAR := 9.5     # metres from the paved road edge
const STRIDE := 16
const HULL_STRIDE := 13
## Rocks and cacti whose top stands at least this high above the ground get a hull collider.
const HULL_MIN_H := 0.55
const HULL_NAMES: Array[String] = ["Rock_A", "Rock_B", "Rock_C", "Rock_Large", "Rock_Red", "Cactus_A", "Cactus_B"]
const SMALL_STEP := 6.0
const SMALL_CELLS := 21          # small-prop cells per chunk side (one bush / rock / cactus each)
const MAX_FOOT := 6.5            # largest rock footprint radius: reach of the rock overlap test
const BUSH_MAX_DROP := 1.5       # terrain drop across a bush's footprint above which it is not placed

## Settlement footprints registered before dressing starts: Vector4(x, z, core radius, tree radius).
static var exclusions: Array[Vector4] = []
## Far-distance stand-ins generated from the real tree / hedge meshes: name -> Mesh (main thread only).
static var far_meshes: Dictionary = {}


static func register_exclusion(x: float, z: float, core: float, trees: float) -> void:
	exclusions.append(Vector4(x, z, core, trees))


class Ctx:
	extends RefCounted
	var data: WorldData
	var nl := PackedByteArray()
	var nl_size: int = 0
	var n_wood := FastNoiseLite.new()
	var n_mix := FastNoiseLite.new()
	var n_patch := FastNoiseLite.new()
	var excl: Array[Vector4] = []
	## name -> {"trunk": float, "far": int, "size": Vector3}
	var info: Dictionary = {}
	## HULL_NAMES index -> support points of the prop mesh (local space), the collider hull
	var hulls: Array[PackedVector3Array] = []
	## name -> Nature.far_source() of species whose far stand-in is still to be built (build_far_meshes)
	var far_src: Dictionary = {}
	## chunk key -> PackedVector3Array of poplar-row positions (x, 0, z)
	var rows: Dictionary = {}
	var river_pts := PackedVector2Array()
	var river_y := PackedFloat32Array()
	var river_box := Rect2()
	var lakes: Array[Vector4] = []
	var density: float = 1.0

	func _init() -> void:
		for pair: Array in [[n_wood, 7101, 1.0 / 420.0, 3], [n_mix, 7102, 1.0 / 260.0, 2], [n_patch, 7103, 1.0 / 90.0, 2]]:
			var n: FastNoiseLite = pair[0]
			n.seed = pair[1]
			n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
			n.fractal_type = FastNoiseLite.FRACTAL_FBM
			n.fractal_octaves = pair[3]
			n.frequency = pair[2]


class Out:
	extends RefCounted
	var groups: Dictionary = {}
	var colliders: Array = []
	var hulls: Array = []

	func add(key: String, xf: Transform3D, custom: Color) -> void:
		var a: Array = groups.get(key, [])
		if a.is_empty():
			groups[key] = a
		var b := xf.basis
		var o := xf.origin
		a.append_array([b.x.x, b.y.x, b.z.x, o.x, b.x.y, b.y.y, b.z.y, o.y, b.x.z, b.y.z, b.z.z, o.z, custom.r, custom.g, custom.b, custom.a])

	func packed() -> Dictionary:
		var res := {}
		for k: String in groups:
			res[k] = PackedFloat32Array(groups[k])
		return res

	## Per group bounds of the instance origins (cell-relative), for MultiMesh custom AABBs and LOD reach.
	func bounds() -> Dictionary:
		var res := {}
		for k: String in groups:
			var a: Array = groups[k]
			var lo := Vector3(INF, INF, INF)
			var hi := -lo
			for i in range(0, a.size(), STRIDE):
				var p := Vector3(a[i + 3], a[i + 7], a[i + 11])
				lo = lo.min(p)
				hi = hi.max(p)
			res[k] = AABB(lo, hi - lo)
		return res


## One small prop (bush, cactus, rock) in world space, before it is committed to an Out.
class Prop:
	extends RefCounted
	var layer := ""
	var name := ""
	var xf := Transform3D()
	var custom := Color()
	var rock := false
	var foot := 0.0                  # rocks: footprint radius at ground level
	var hull := -1                   # HULL_NAMES index when the prop gets a hull collider


## Per-chunk build state for the rock overlap test.
class Build:
	extends RefCounted
	var key: Vector2i
	var org: Vector3
	## this chunk's small-prop cells: x, z, footprint radius of the cell's rock (radius 0 = no rock)
	var rock_cells := PackedFloat32Array()
	var max_foot := 0.0
	## cells of neighbouring chunks evaluated on demand: Vector3i(chunk x, chunk y, cell) -> Vector3(x, z, radius)
	var foreign: Dictionary = {}
	var chunk_ctx: Dictionary = {}   # Vector2i -> [exclusions, near_river]


# ------------------------------------------------------------------ context (main thread)

const PropLibrary := preload("res://scripts/world/prop_library.gd")
const Nature := preload("res://scripts/world/dressing_nature_meshes.gd")
const Mats := preload("res://scripts/world/dressing_materials.gd")
const INFO_NAMES: Array[String] = ["Tree_Oak_A", "Tree_Oak_B", "Tree_Pine_A", "Tree_Pine_B", "Tree_Poplar", "Tree_Birch",
	"Tree_Palm", "Tree_Olive", "Tree_Dead", "Hedge", "Bush_A", "Bush_B", "Bush_Desert", "Cactus_A", "Cactus_B",
	"Rock_A", "Rock_B", "Rock_C", "Rock_Large", "Rock_Red", "Reeds", "Grass_Tuft", "Flowers_Tuft"]
const ROW_ROAD_CLASSES := [WorldLayout.RoadClass.REGIONAL, WorldLayout.RoadClass.STREET, WorldLayout.RoadClass.GRAVEL]


## Builds the immutable snapshot the worker tasks read. `noise_large` is the terrain's large-scale
## noise image (World.noise_large) used to reproduce the shader's patchwork fields; may be null.
static func make_ctx(data: WorldData, noise_large: Image, density: float) -> Ctx:
	var ctx := Ctx.new()
	ctx.data = data
	if noise_large != null:
		var img := noise_large.duplicate() as Image
		if img.has_mipmaps():
			img.clear_mipmaps()
		if img.get_format() != Image.FORMAT_L8:
			img.convert(Image.FORMAT_L8)
		ctx.nl = img.get_data()
		ctx.nl_size = img.get_width()
	ctx.excl = exclusions.duplicate()
	ctx.river_pts = data.gen._river_pts
	ctx.river_y = data.gen._river_y
	ctx.river_box = data.gen._river_box.grow(30.0)
	for lk: Dictionary in data.lake_list():
		ctx.lakes.append(Vector4(float(lk["pos"][0]), float(lk["pos"][1]), float(lk["radius"]) * 1.35, float(lk["level"])))
	ctx.density = density
	for nm in INFO_NAMES:
		var bb := PropLibrary.aabb(nm)
		var sp: Dictionary = Nature.SPECIES.get(nm, {})
		var far: int = sp.get("far", -1)
		ctx.info[nm] = {"trunk": float(sp.get("trunk", 0.0)), "far": far, "size": bb.size}
		if far >= 0 and not far_meshes.has(nm):
			ctx.far_src[nm] = Nature.far_source(PropLibrary.mesh(nm), float(sp.get("far_k", 1.0)))
	for nm in HULL_NAMES:
		ctx.hulls.append(support_points(PropLibrary.mesh(nm)))
	_build_rows(ctx)
	return ctx


## Builds the far stand-ins still missing (Nature.far_arrays is thread-safe; dressing.gd runs it on a worker
## and calls make_far itself).
static func build_far_meshes(ctx: Ctx) -> void:
	for nm: String in ctx.far_src:
		far_meshes[nm] = make_far(nm, Nature.far_arrays(ctx.far_src[nm]))
	ctx.far_src.clear()


static func make_far(nm: String, arrays: Array) -> Mesh:
	return Nature.far_mesh(arrays, Mats.foliage(), "Far_" + nm) if not arrays.is_empty() else PropLibrary.mesh(nm)


## Collider hull of a prop mesh: its support points in the 6 axis and 48 spread directions (a convex polytope
## hugging the mesh, with its exact top, bottom and sides).
static func support_points(m: Mesh) -> PackedVector3Array:
	var uniq: Dictionary = {}
	for s in m.get_surface_count():
		for v: Vector3 in m.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]:
			uniq[v] = true
	var pts := PackedVector3Array(uniq.keys())
	var res := PackedVector3Array()
	if pts.is_empty():
		return res
	var dirs: Array[Vector3] = [Vector3.UP, Vector3.DOWN, Vector3.LEFT, Vector3.RIGHT, Vector3.FORWARD, Vector3.BACK]
	var n := 48
	for i in n:
		var y := 1.0 - 2.0 * (i + 0.5) / n
		var r := sqrt(1.0 - y * y)
		var a := i * 2.39996323
		dirs.append(Vector3(cos(a) * r, y, sin(a) * r))
	for dir in dirs:
		var best := 0
		var bd := -INF
		for k in pts.size():
			var dd := pts[k].dot(dir)
			if dd > bd:
				bd = dd
				best = k
		if not res.has(pts[best]):
			res.append(pts[best])
	return res


## Poplar rows: stretches of vale roads get a tree row just beyond the tree clearance.
static func _build_rows(ctx: Ctx) -> void:
	var noise := FastNoiseLite.new()
	noise.seed = 7201
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 1.0 / 260.0
	for r in ctx.data.network.roads:
		if not (r.cls in ROW_ROAD_CLASSES):
			continue
		var s := 0.0
		while s < r.length:
			var p := r.point_at(s)
			var v := noise.get_noise_1d(s + r.idx * 1000.0)
			if r.flag_at(s) == 0 and v > 0.3 and ctx.data.region_weights_at(p.x, p.z).r > 0.75:
				var v2 := noise.get_noise_1d(s * 0.5 + r.idx * 777.0 + 5000.0)
				var rt := r.right_at(s)
				for side: float in [-1.0, 1.0]:
					if (side > 0.0 and v2 < -0.15) or (side < 0.0 and v2 > 0.15):
						continue
					var q := p + rt * side * (r.width * 0.5 + TREE_ROAD_CLEAR + 0.5)
					var key := Vector2i(floori((q.x + HALF) / CHUNK), floori((q.z + HALF) / CHUNK))
					var arr: PackedVector3Array = ctx.rows.get(key, PackedVector3Array())
					arr.append(Vector3(q.x, 0.0, q.z))
					ctx.rows[key] = arr
			s += 9.0


# ------------------------------------------------------------------ sampling helpers

## Replicates terrain.gdshader's texture(noise_large, xz * 0.0011) (bilinear, repeat).
static func nl_at(ctx: Ctx, x: float, z: float) -> float:
	var s := ctx.nl_size
	if s == 0:
		return 0.0
	var u := x * 0.0011 * s - 0.5
	var v := z * 0.0011 * s - 0.5
	var i0 := floori(u)
	var j0 := floori(v)
	var fu := u - i0
	var fv := v - j0
	var a := posmod(i0, s)
	var b := posmod(i0 + 1, s)
	var c := posmod(j0, s) * s
	var d := posmod(j0 + 1, s) * s
	return lerpf(lerpf(ctx.nl[c + a], ctx.nl[c + b], fu), lerpf(ctx.nl[d + a], ctx.nl[d + b], fu), fv) / 255.0


## terrain.gdshader patchwork-field mask without the boundary strips (> 0.3 = crop field).
static func field_zone(h: float, slope: float, vale: float, nl: float) -> float:
	return smoothstep(0.62, 0.8, vale) * (1.0 - smoothstep(0.12, 0.2, slope)) * smoothstep(0.45, 0.6, nl) * (1.0 - smoothstep(55.0, 70.0, h))


## terrain.gdshader field "edge" factor: 0 on the meadow strips between fields, 1 inside a field.
static func field_edge(x: float, z: float, nl: float) -> float:
	var ang := 0.35 + floorf(nl * 4.0) * 0.4
	var c := cos(ang)
	var s := sin(ang)
	var lx := fposmod((c * x + s * z) / 150.0, 1.0)
	var ly := fposmod((-s * x + c * z) / 95.0, 1.0)
	return smoothstep(0.0, 0.025, lx) * smoothstep(1.0, 0.975, lx) * smoothstep(0.0, 0.04, ly) * smoothstep(1.0, 0.96, ly)


## Distance (m) to the nearest paved road edge from the baked 4 m map. The map only holds exact values
## within each road's carve reach (255 beyond), so interpolate only between valid cells and otherwise
## return the smallest neighbour (conservative near the reach boundary).
static func road_dist(ctx: Ctx, x: float, z: float) -> float:
	var d := ctx.data
	var n := d.map_n
	var fx := clampf((x + d.half) / 4.0, 0.0, n - 1.001)
	var fz := clampf((z + d.half) / 4.0, 0.0, n - 1.001)
	var i := int(fx)
	var j := int(fz)
	var tx := fx - i
	var tz := fz - j
	var m := d.road_dist
	var k := j * n + i
	var a: int = m[k]
	var b: int = m[k + 1]
	var c: int = m[k + n]
	var e: int = m[k + n + 1]
	if a == 255 or b == 255 or c == 255 or e == 255:
		return float(mini(mini(a, b), mini(c, e)))
	return lerpf(lerpf(a, b, tx), lerpf(c, e, tx), tz)


## True if any road sample lies within `margin` of the square cell (org, size).
static func roads_near(ctx: Ctx, org: Vector3, size: float, margin: float) -> bool:
	var hc := RoadNetwork.HASH_CELL
	var h: Dictionary = ctx.data.network._hash
	for j in range(floori((org.z - margin) / hc), floori((org.z + size + margin) / hc) + 1):
		for i in range(floori((org.x - margin) / hc), floori((org.x + size + margin) / hc) + 1):
			if h.has(Vector2i(i, j)):
				return true
	return false


## Road clearance for trees (>= TREE_ROAD_CLEAR from the paved edge): the baked map where it is
## conclusive, the exact network otherwise. `near` = the chunk has road samples nearby.
static func tree_clear(ctx: Ctx, x: float, z: float, near_roads: bool) -> bool:
	if not near_roads:
		return true
	var d := ctx.data
	var m := d.road_distance_at(x, z)
	if m < 255.0:
		if m - 2.9 >= TREE_ROAD_CLEAR:
			return true
		if m + 2.9 < TREE_ROAD_CLEAR:
			return false
	else:
		# Every cell within ~8 m beyond any road's carve reach (>= 4.7 m past the edge) -> far enough.
		var far := true
		for o: Vector2 in [Vector2(8, 0), Vector2(-8, 0), Vector2(0, 8), Vector2(0, -8), Vector2(6, 6), Vector2(-6, 6), Vector2(6, -6), Vector2(-6, -6)]:
			if d.road_distance_at(x + o.x, z + o.y) < 255.0:
				far = false
				break
		if far:
			return true
	var near := d.network.nearest(Vector3(x, 0.0, z), 30.0)
	if near.is_empty():
		return true
	return float(near["distance"]) - (near["road"] as RoadNetwork.Road).width * 0.5 >= TREE_ROAD_CLEAR


static func river_q(ctx: Ctx, x: float, z: float) -> Vector2:
	if not ctx.river_box.has_point(Vector2(x, z)):
		return Vector2(INF, 0.0)
	return WorldGen.polyline_query(Vector2(x, z), ctx.river_pts, ctx.river_y)


static func in_lake(ctx: Ctx, x: float, z: float, h: float, margin: float) -> bool:
	for lk in ctx.lakes:
		if (x - lk.x) * (x - lk.x) + (z - lk.y) * (z - lk.y) < lk.z * lk.z and h < lk.w + margin:
			return true
	return false


static func local_exclusions(ctx: Ctx, org: Vector3, size: float) -> Array[Vector4]:
	var res: Array[Vector4] = []
	var rect := Rect2(org.x, org.z, size, size)
	for e in ctx.excl:
		if rect.grow(e.w).has_point(Vector2(e.x, e.y)):
			res.append(e)
	return res


static func excluded(ex: Array[Vector4], x: float, z: float, trees: bool) -> bool:
	for e in ex:
		var r := e.w if trees else e.z
		if (x - e.x) * (x - e.x) + (z - e.y) * (z - e.y) < r * r:
			return true
	return false


static func pick_region(rw: Color, roll: float) -> int:
	var t := (rw.r + rw.g + rw.b + rw.a) * roll
	if t < rw.r:
		return 0
	t -= rw.r
	if t < rw.g:
		return 1
	t -= rw.g
	if t < rw.b:
		return 2
	return 3


static func _seed(key: Vector2i, layer: int) -> int:
	return hash(Vector3i(key.x, key.y, layer)) & 0x7fffffff


# ------------------------------------------------------------------ chunk build

static func build_chunk(ctx: Ctx, key: Vector2i) -> Dictionary:
	var org := Vector3(-HALF + key.x * CHUNK, 0.0, -HALF + key.y * CHUNK)
	var out := Out.new()
	var rng := RandomNumberGenerator.new()
	var ex := local_exclusions(ctx, org, CHUNK)
	var near_river := ctx.river_box.intersects(Rect2(org.x, org.z, CHUNK, CHUNK))
	var near_roads := roads_near(ctx, org, CHUNK, 40.0)
	var b := Build.new()
	b.key = key
	b.org = org
	b.chunk_ctx[key] = [ex, near_river]
	# rocks first: trees, bushes and hedgerows keep clear of them
	_small(ctx, out, b, ex, near_river)
	rng.seed = _seed(key, 1)
	_trees(ctx, out, b, rng, ex, near_river, near_roads)
	rng.seed = _seed(key, 5)
	_reeds(ctx, out, org, rng, ex, near_river)
	rng.seed = _seed(key, 3)
	_hedges(ctx, out, b, rng, ex, near_roads, near_river)
	rng.seed = _seed(key, 4)
	_rows(ctx, out, b, rng, ex, near_roads)
	return {"key": key, "groups": out.packed(), "bounds": out.bounds(), "colliders": PackedFloat32Array(out.colliders),
		"hulls": PackedFloat32Array(out.hulls)}


static func add_tree(ctx: Ctx, out: Out, name: String, p: Vector3, org: Vector3, scale: float, rng: RandomNumberGenerator, lean := 0.0, lean_axis := Vector3.ZERO) -> void:
	var yaw := rng.randf() * TAU
	var sy := scale * rng.randf_range(0.9, 1.1)
	var b := Basis(Vector3.UP, yaw).scaled(Vector3(scale, sy, scale))
	if lean != 0.0:
		var ax := lean_axis
		if ax == Vector3.ZERO:
			var la := rng.randf() * TAU
			ax = Vector3(cos(la), 0.0, sin(la))
		b = Basis(ax, lean) * b
	var origin := p - org - Vector3(0, 0.05, 0)
	var seed := rng.randf()
	var tint := Color(1.0 + rng.randf_range(-0.07, 0.07), 1.0 + rng.randf_range(-0.05, 0.05), 1.0 + rng.randf_range(-0.08, 0.04))
	out.add("tree|" + name, Transform3D(b, origin), Color(tint.r, tint.g, tint.b, seed))
	var inf: Dictionary = ctx.info.get(name, {})
	# the far stand-in is built from this mesh at its real size: same transform, same tint
	if int(inf.get("far", -1)) >= 0:
		out.add("far|" + name, Transform3D(b, origin), Color(tint.r, tint.g, tint.b, seed))
	var tr: float = inf.get("trunk", 0.0)
	if tr > 0.0:
		out.colliders.append_array([p.x, p.y, p.z, tr * scale, 7.0 * sy, 0.0])


## Trunk clearance radius of a tree species at a scale (for the rock overlap test).
static func _trunk_r(ctx: Ctx, name: String, scale: float) -> float:
	return float((ctx.info.get(name, {}) as Dictionary).get("trunk", 0.3)) * scale + 0.25


static func _trees(ctx: Ctx, out: Out, bld: Build, rng: RandomNumberGenerator, ex: Array[Vector4], near_river: bool, near_roads: bool) -> void:
	var d := ctx.data
	var org := bld.org
	var step := 4.5
	var n := int(CHUNK / step)
	for gj in n:
		for gi in n:
			var x := org.x + (gi + rng.randf()) * step
			var z := org.z + (gj + rng.randf()) * step
			var roll := rng.randf()
			var pick := rng.randf()
			var region_roll := rng.randf()
			var h := d.height_at(x, z)
			if h < 1.6:
				continue
			if excluded(ex, x, z, true) or in_lake(ctx, x, z, h, 1.5):
				continue
			var rq := river_q(ctx, x, z) if near_river else Vector2(INF, 0.0)
			if rq.x < 18.0 and h < rq.y + 4.0:
				continue
			var slope := 1.0 - d.normal_at(x, z).y
			if slope > 0.55:
				continue
			var rw := d.region_weights_at(x, z)
			var name := ""
			var scale := 1.0
			var lean := 0.0
			var lean_axis := Vector3.ZERO
			match pick_region(rw, region_roll):
				0:
					if field_zone(h, slope, rw.r, nl_at(ctx, x, z)) > 0.3:
						continue
					var wood := clampf(smoothstep(0.08, 0.3, ctx.n_wood.get_noise_2d(x, z)) + smoothstep(0.2, 0.4, slope) * 0.6, 0.0, 1.0)
					var riv := 1.0 - smoothstep(18.0, 50.0, rq.x)
					if roll > (0.66 * wood + 0.22 * riv + 0.008) * ctx.density:
						continue
					if wood > 0.25:
						if ctx.n_mix.get_noise_2d(x, z) > 0.32:
							name = "Tree_Pine_B" if pick < 0.6 else "Tree_Pine_A"
						else:
							name = "Tree_Oak_A" if pick < 0.45 else ("Tree_Oak_B" if pick < 0.75 else "Tree_Birch")
						scale = rng.randf_range(0.8, 1.15)
					elif riv > 0.3:
						name = "Tree_Poplar" if pick < 0.35 else ("Tree_Birch" if pick < 0.65 else "Tree_Oak_B")
						scale = rng.randf_range(0.85, 1.15)
					else:
						name = "Tree_Oak_A" if pick < 0.7 else "Tree_Oak_B"
						scale = rng.randf_range(1.0, 1.35)
				1:
					if h > 288.0:
						continue
					var alt := 1.0 - smoothstep(180.0, 286.0, h + ctx.n_mix.get_noise_2d(x * 3.0, z * 3.0) * 16.0)
					var forest := smoothstep(-0.32, 0.0, ctx.n_wood.get_noise_2d(x + 5000.0, z - 3000.0))
					if roll > (0.62 * forest + 0.015) * alt * (1.0 - smoothstep(0.38, 0.55, slope)) * ctx.density:
						continue
					if h < 150.0 and pick < 0.2:
						name = "Tree_Birch"
					else:
						name = "Tree_Pine_A" if pick < 0.6 else "Tree_Pine_B"
					scale = lerpf(0.6, 1.0, alt) * rng.randf_range(0.85, 1.2)
				2:
					if slope > 0.3:
						continue
					var border := rw.r + rw.a
					if roll > (0.003 + 0.03 * smoothstep(0.15, 0.45, border)) * ctx.density:
						continue
					if border > 0.2 and pick < 0.7:
						name = "Tree_Olive"
						scale = rng.randf_range(0.8, 1.1)
					else:
						name = "Tree_Dead"
						scale = rng.randf_range(0.8, 1.2)
				_:
					if h < 9.0:
						if slope > 0.3:
							continue
						var grove := smoothstep(0.0, 0.35, ctx.n_patch.get_noise_2d(x, z))
						if roll > (0.015 + 0.2 * grove) * ctx.density:
							continue
						name = "Tree_Palm"
						scale = rng.randf_range(0.85, 1.25)
						lean = rng.randf_range(0.03, 0.14)
					else:
						var woods := smoothstep(0.2, 0.42, ctx.n_wood.get_noise_2d(x, z))
						if roll > (0.025 + 0.4 * woods) * (1.0 - smoothstep(0.35, 0.5, slope)) * ctx.density:
							continue
						name = "Tree_Pine_A" if pick < 0.55 else ("Tree_Olive" if pick < 0.8 else "Tree_Oak_B")
						scale = rng.randf_range(0.75, 1.05)
						lean = -rng.randf_range(0.03, 0.09)
						lean_axis = Vector3(1, 0, 0)
			if not tree_clear(ctx, x, z, near_roads) or rock_blocks(ctx, bld, x, z, _trunk_r(ctx, name, scale)):
				continue
			add_tree(ctx, out, name, Vector3(x, h, z), org, scale, rng, lean, lean_axis)


static func _align(up: Vector3) -> Basis:
	var axis := Vector3.UP.cross(up)
	var l := axis.length()
	if l < 0.0001:
		return Basis()
	return Basis(axis / l, asin(clampf(l, 0.0, 1.0)))


## A small prop at `pos` (world): random yaw, optional slope alignment and tilt, then the (local) scale.
static func _prop(rng: RandomNumberGenerator, layer: String, name: String, pos: Vector3, scale: Vector3, tilt := 0.0, tint := Color(1, 1, 1), up := Vector3.UP) -> Prop:
	var b := Basis(Vector3.UP, rng.randf() * TAU)
	if up != Vector3.UP:
		b = _align(up) * b
	if tilt > 0.0:
		b = Basis(Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)).normalized(), rng.randf_range(-tilt, tilt)) * b
	var pr := Prop.new()
	pr.layer = layer
	pr.name = name
	pr.xf = Transform3D(b * Basis.from_scale(scale), pos)
	pr.custom = Color(tint.r, tint.g, tint.b, rng.randf())
	return pr


static func _emit(out: Out, org: Vector3, pr: Prop) -> void:
	out.add(pr.layer + "|" + pr.name, Transform3D(pr.xf.basis, pr.xf.origin - org), pr.custom)
	if pr.hull >= 0:
		var b := pr.xf.basis
		var o := pr.xf.origin
		out.hulls.append_array([o.x, o.y, o.z, float(pr.hull), b.x.x, b.x.y, b.x.z, b.y.x, b.y.y, b.y.z, b.z.x, b.z.y, b.z.z])


static func _rock(ctx: Ctx, name: String, p: Vector3, s: float, rng: RandomNumberGenerator, nrm := Vector3.UP) -> Prop:
	var big := name == "Rock_Large" or name == "Rock_Red"
	var inf: Dictionary = ctx.info.get(name, {})
	var size: Vector3 = inf.get("size", Vector3.ONE)
	var slope := 1.0 - nrm.y
	var sc := Vector3(s * rng.randf_range(0.9, 1.15), s * rng.randf_range(0.8, 1.1), s * rng.randf_range(0.9, 1.15))
	var sink := Vector3(0, -s * (0.12 + slope * 0.6 * maxf(size.x, size.z) * 0.5), 0)
	var g := 0.92 + rng.randf() * 0.16
	var pr := _prop(rng, "rockbig" if big else "rock", name, p + sink, sc, 0.1, Color(g, g, g), Vector3.UP.lerp(nrm, 0.7).normalized())
	pr.rock = true
	_fit_hull(ctx, pr, p.y)
	return pr


## Footprint radius at ground level (`ground` = terrain height under the origin) and, when the prop stands
## at least HULL_MIN_H above the ground, its hull collider (the visible instance transform).
static func _fit_hull(ctx: Ctx, pr: Prop, ground: float) -> void:
	var hi := HULL_NAMES.find(pr.name)
	if hi < 0:
		return
	var top := -INF
	var foot := 0.0
	for v in ctx.hulls[hi]:
		var w := pr.xf.basis * v
		top = maxf(top, pr.xf.origin.y + w.y)
		if pr.xf.origin.y + w.y > ground - 0.5:
			foot = maxf(foot, Vector2(w.x, w.z).length())
	pr.foot = foot
	if top - ground >= HULL_MIN_H:
		pr.hull = hi


## A bush that sits on its footprint: sunk toward the lowest terrain under its canopy rim and leaning half
## way to the terrain plane there; none where the ground drops more than BUSH_MAX_DROP across it (cliffs).
static func _bush(ctx: Ctx, name: String, p: Vector3, scale: Vector3, rng: RandomNumberGenerator, tint := Color(1, 1, 1)) -> Prop:
	var size: Vector3 = (ctx.info.get(name, {}) as Dictionary).get("size", Vector3.ONE)
	var rr := 0.42 * maxf(size.x, size.z) * maxf(scale.x, scale.z)
	var lo := INF
	var hi := -INF
	var gx := 0.0
	var gz := 0.0
	for k in 6:
		var a := TAU * k / 6.0
		var hk := ctx.data.height_at(p.x + cos(a) * rr, p.z + sin(a) * rr)
		lo = minf(lo, hk)
		hi = maxf(hi, hk)
		gx += hk * cos(a)
		gz += hk * sin(a)
	if hi - lo > BUSH_MAX_DROP:
		return null
	var nrm := Vector3(-gx / (3.0 * rr), 1.0, -gz / (3.0 * rr)).normalized()
	var sink := maxf(p.y - lo, 0.0) * 0.65 + 0.05
	return _prop(rng, "bush", name, Vector3(p.x, p.y - sink, p.z), scale, 0.0, tint, Vector3.UP.lerp(nrm, 0.5).normalized())


## One small-prop cell (at most one bush, cactus or rock). Seeded per cell, so the cells of a neighbouring
## chunk can be evaluated on their own for the rock overlap test (`rocks_only`).
static func _small_cell(ctx: Ctx, key: Vector2i, gi: int, gj: int, rng: RandomNumberGenerator, ex: Array[Vector4], near_river: bool, rocks_only := false) -> Prop:
	rng.seed = hash(Vector4i(key.x, key.y, gj * SMALL_CELLS + gi, 2)) & 0x7fffffff
	var d := ctx.data
	var x := -HALF + key.x * CHUNK + (gi + rng.randf()) * SMALL_STEP
	var z := -HALF + key.y * CHUNK + (gj + rng.randf()) * SMALL_STEP
	var roll := rng.randf()
	var pick := rng.randf()
	var region_roll := rng.randf()
	var h := d.height_at(x, z)
	if h < 0.4:
		return null
	if road_dist(ctx, x, z) < 4.0 or excluded(ex, x, z, false):
		return null
	var p := Vector3(x, h, z)
	# river banks and lake shores belong to the reed pass
	var rq := river_q(ctx, x, z) if near_river else Vector2(INF, 0.0)
	if rq.x < 20.0 or in_lake(ctx, x, z, h, 1.0):
		return null
	var nrm := d.normal_at(x, z)
	var slope := 1.0 - nrm.y
	var rw := d.region_weights_at(x, z)
	match pick_region(rw, region_roll):
		0:
			if field_zone(h, slope, rw.r, nl_at(ctx, x, z)) > 0.3:
				return null
			var wn := ctx.n_wood.get_noise_2d(x, z)
			var edge := smoothstep(-0.05, 0.12, wn) * (1.0 - smoothstep(0.22, 0.4, wn))
			if roll < (0.32 * edge + 0.012) * ctx.density:
				if not rocks_only:
					return _bush(ctx, "Bush_A" if pick < 0.6 else "Bush_B", p, Vector3.ONE * rng.randf_range(0.75, 1.3), rng)
			elif roll > 0.994:
				return _rock(ctx, "Rock_A" if pick < 0.5 else "Rock_B", p, rng.randf_range(0.45, 0.85), rng, nrm)
		1:
			var rock_p := 0.025 + 0.35 * smoothstep(0.25, 0.5, slope) + (0.05 if h > 300.0 else 0.0)
			if roll < rock_p * ctx.density:
				if pick < 0.12 and slope > 0.2:
					return _rock(ctx, "Rock_Large", p, rng.randf_range(0.6, 1.2), rng, nrm)
				var nm := "Rock_A" if pick < 0.45 else ("Rock_B" if pick < 0.8 else "Rock_C")
				return _rock(ctx, nm, p, rng.randf_range(0.6, 1.7), rng, nrm)
			elif h < 300.0 and roll > 1.0 - 0.06 * ctx.density and not rocks_only:
				return _bush(ctx, "Bush_A", p, Vector3(1.0, 0.8, 1.0) * rng.randf_range(0.6, 1.0), rng, Color(0.8, 0.9, 0.85))
		2:
			if roll < 0.07 * ctx.density:
				if not rocks_only:
					return _bush(ctx, "Bush_Desert", p, Vector3.ONE * rng.randf_range(0.7, 1.3), rng)
			elif roll < 0.085 * ctx.density and slope < 0.25:
				if not rocks_only:
					return _cactus(ctx, "Cactus_A", p, rng.randf_range(0.7, 1.25), rng)
			elif roll < 0.105 * ctx.density and slope < 0.3:
				if not rocks_only:
					return _cactus(ctx, "Cactus_B", p, rng.randf_range(0.8, 1.3), rng)
			elif roll < (0.125 + 0.2 * smoothstep(0.2, 0.5, slope)) * ctx.density:
				return _rock(ctx, "Rock_Red", p, rng.randf_range(0.5, 1.8), rng, nrm)
		_:
			if h < 4.5:
				if roll < 0.004:
					return _rock(ctx, "Rock_C", p, rng.randf_range(0.4, 0.8), rng, nrm)
			elif roll < 0.06 * ctx.density:
				if not rocks_only:
					var nm := "Bush_A" if pick < 0.7 else "Bush_B"
					return _bush(ctx, nm, p, Vector3(1.0, 0.7, 1.0) * rng.randf_range(0.7, 1.2), rng, Color(0.95, 1.0, 0.9))
			elif roll < (0.06 + 0.15 * smoothstep(0.3, 0.55, slope)) * ctx.density:
				return _rock(ctx, "Rock_B" if pick < 0.6 else "Rock_C", p, rng.randf_range(0.6, 1.6), rng, nrm)
	return null


static func _cactus(ctx: Ctx, name: String, p: Vector3, s: float, rng: RandomNumberGenerator) -> Prop:
	var pr := _prop(rng, "bush", name, p, Vector3.ONE * s)
	_fit_hull(ctx, pr, p.y)
	return pr


static func _small(ctx: Ctx, out: Out, bld: Build, ex: Array[Vector4], near_river: bool) -> void:
	var rng := RandomNumberGenerator.new()
	bld.rock_cells.resize(SMALL_CELLS * SMALL_CELLS * 3)
	var later: Array[Prop] = []
	for gj in SMALL_CELLS:
		for gi in SMALL_CELLS:
			var pr := _small_cell(ctx, bld.key, gi, gj, rng, ex, near_river)
			if pr == null:
				continue
			if not pr.rock:
				later.append(pr)
				continue
			var o := (gj * SMALL_CELLS + gi) * 3
			bld.rock_cells[o] = pr.xf.origin.x
			bld.rock_cells[o + 1] = pr.xf.origin.z
			bld.rock_cells[o + 2] = pr.foot
			bld.max_foot = maxf(bld.max_foot, pr.foot)
			_emit(out, bld.org, pr)
	# bushes and cacti never grow out of a rock
	for pr in later:
		if not rock_blocks(ctx, bld, pr.xf.origin.x, pr.xf.origin.z, 0.35):
			_emit(out, bld.org, pr)


## True if a rock's footprint (from this chunk or a neighbouring one) reaches within `r` of (x, z).
static func rock_blocks(ctx: Ctx, bld: Build, x: float, z: float, r: float) -> bool:
	if bld.max_foot > 0.0 and _rocks_in(ctx, bld, bld.key, x, z, r, r + bld.max_foot):
		return true
	var reach := r + MAX_FOOT
	var o := bld.org
	if x - reach >= o.x and x + reach < o.x + CHUNK and z - reach >= o.z and z + reach < o.z + CHUNK:
		return false
	for kj in range(floori((z - reach + HALF) / CHUNK), floori((z + reach + HALF) / CHUNK) + 1):
		for ki in range(floori((x - reach + HALF) / CHUNK), floori((x + reach + HALF) / CHUNK) + 1):
			var key := Vector2i(ki, kj)
			if key != bld.key and _rocks_in(ctx, bld, key, x, z, r, reach):
				return true
	return false


static func _rocks_in(ctx: Ctx, bld: Build, key: Vector2i, x: float, z: float, r: float, reach: float) -> bool:
	var ox := -HALF + key.x * CHUNK
	var oz := -HALF + key.y * CHUNK
	var gi0 := maxi(floori((x - reach - ox) / SMALL_STEP), 0)
	var gi1 := mini(floori((x + reach - ox) / SMALL_STEP), SMALL_CELLS - 1)
	var gj0 := maxi(floori((z - reach - oz) / SMALL_STEP), 0)
	var gj1 := mini(floori((z + reach - oz) / SMALL_STEP), SMALL_CELLS - 1)
	for gj in range(gj0, gj1 + 1):
		for gi in range(gi0, gi1 + 1):
			var rk := _rock_at(ctx, bld, key, gi, gj)
			if rk.z > 0.0 and (x - rk.x) * (x - rk.x) + (z - rk.y) * (z - rk.y) < (rk.z + r) * (rk.z + r):
				return true
	return false


## (x, z, footprint radius) of the rock in a small-prop cell, radius 0 when the cell has none.
static func _rock_at(ctx: Ctx, bld: Build, key: Vector2i, gi: int, gj: int) -> Vector3:
	if key == bld.key:
		var o := (gj * SMALL_CELLS + gi) * 3
		return Vector3(bld.rock_cells[o], bld.rock_cells[o + 1], bld.rock_cells[o + 2])
	var id := Vector3i(key.x, key.y, gj * SMALL_CELLS + gi)
	if bld.foreign.has(id):
		return bld.foreign[id]
	var res := Vector3.ZERO
	if key.x >= 0 and key.y >= 0 and key.x * CHUNK < HALF * 2.0 and key.y * CHUNK < HALF * 2.0:
		if not bld.chunk_ctx.has(key):
			var org := Vector3(-HALF + key.x * CHUNK, 0.0, -HALF + key.y * CHUNK)
			bld.chunk_ctx[key] = [local_exclusions(ctx, org, CHUNK), ctx.river_box.intersects(Rect2(org.x, org.z, CHUNK, CHUNK))]
		var cc: Array = bld.chunk_ctx[key]
		var pr := _small_cell(ctx, key, gi, gj, RandomNumberGenerator.new(), cc[0], cc[1], true)
		if pr != null and pr.rock:
			res = Vector3(pr.xf.origin.x, pr.xf.origin.z, pr.foot)
	bld.foreign[id] = res
	return res


static func _reeds(ctx: Ctx, out: Out, org: Vector3, rng: RandomNumberGenerator, ex: Array[Vector4], near_river: bool) -> void:
	var rect := Rect2(org.x, org.z, CHUNK, CHUNK)
	var near_lake := false
	for lk in ctx.lakes:
		if rect.grow(lk.z).has_point(Vector2(lk.x, lk.y)):
			near_lake = true
	if not near_river and not near_lake:
		return
	var d := ctx.data
	var step := 3.0
	var n := int(CHUNK / step)
	for gj in n:
		for gi in n:
			var x := org.x + (gi + rng.randf()) * step
			var z := org.z + (gj + rng.randf()) * step
			var roll := rng.randf()
			var h := d.height_at(x, z)
			var ok := false
			if near_river:
				var rq := river_q(ctx, x, z)
				ok = rq.x > 10.0 and rq.x < 17.5 and h < rq.y + 1.5 and h > rq.y - 1.0
			if not ok and near_lake:
				ok = in_lake(ctx, x, z, h, 0.9) and not in_lake(ctx, x, z, h, -0.5)
			if not ok or roll > 0.55 * ctx.density:
				continue
			if road_dist(ctx, x, z) < 4.0 or excluded(ex, x, z, false):
				continue
			_emit(out, org, _prop(rng, "reed", "Reeds", Vector3(x, h - 0.1, z), Vector3.ONE * rng.randf_range(1.0, 1.6)))


static func _hedges(ctx: Ctx, out: Out, bld: Build, rng: RandomNumberGenerator, ex: Array[Vector4], near_roads: bool, near_river: bool) -> void:
	var org := bld.org
	var rwc := ctx.data.region_weights_at(org.x + CHUNK * 0.5, org.z + CHUNK * 0.5)
	if rwc.r < 0.4 or ctx.nl_size == 0:
		return
	var corners := [Vector2(org.x, org.z), Vector2(org.x + CHUNK, org.z), Vector2(org.x, org.z + CHUNK), Vector2(org.x + CHUNK, org.z + CHUNK)]
	for k in 4:
		var ang := 0.35 + k * 0.4
		var c := cos(ang)
		var s := sin(ang)
		var fx0 := INF
		var fx1 := -INF
		var fy0 := INF
		var fy1 := -INF
		for q: Vector2 in corners:
			var fx := c * q.x + s * q.y
			var fy := -s * q.x + c * q.y
			fx0 = minf(fx0, fx)
			fx1 = maxf(fx1, fx)
			fy0 = minf(fy0, fy)
			fy1 = maxf(fy1, fy)
		for m in range(ceili(fx0 / 150.0), floori(fx1 / 150.0) + 1):
			_hedge_line(ctx, out, bld, rng, ex, k, c, s, 150.0 * m, fy0, fy1, true, near_roads, near_river)
		for m in range(ceili(fy0 / 95.0), floori(fy1 / 95.0) + 1):
			_hedge_line(ctx, out, bld, rng, ex, k, c, s, 95.0 * m, fx0, fx1, false, near_roads, near_river)


## Tree spot check for hedgerow oaks: dry land off the river banks and lakes, clear of rocks.
static func _tree_spot_ok(ctx: Ctx, bld: Build, x: float, z: float, h: float, near_river: bool, r: float) -> bool:
	if h < 1.6 or in_lake(ctx, x, z, h, 1.5):
		return false
	if near_river:
		var rq := river_q(ctx, x, z)
		if rq.x < 18.0 and h < rq.y + 4.0:
			return false
	return not rock_blocks(ctx, bld, x, z, r)


static func _hedge_line(ctx: Ctx, out: Out, bld: Build, rng: RandomNumberGenerator, ex: Array[Vector4], k: int, c: float, s: float, fixed: float, t0: float, t1: float, along_fy: bool, near_roads: bool, near_river: bool) -> void:
	var d := ctx.data
	var org := bld.org
	var dir := Vector3(-s, 0.0, c) if along_fy else Vector3(c, 0.0, s)
	var side := dir.cross(Vector3.UP)
	var t := ceilf(t0 / 4.0) * 4.0
	while t <= t1:
		var fx := fixed if along_fy else t
		var fy := t if along_fy else fixed
		t += 4.0
		var x := c * fx - s * fy
		var z := s * fx + c * fy
		if x < org.x or x >= org.x + CHUNK or z < org.z or z >= org.z + CHUNK:
			continue
		var nl := nl_at(ctx, x, z)
		if int(floorf(nl * 4.0)) != k:
			continue
		var h := d.height_at(x, z)
		var slope := 1.0 - d.normal_at(x, z).y
		var rw := d.region_weights_at(x, z)
		if field_zone(h, slope, rw.r, nl) < 0.45 or h < 1.5:
			continue
		if road_dist(ctx, x, z) < 3.0 or excluded(ex, x, z, true) or in_lake(ctx, x, z, h, 1.0):
			continue
		# hedgerows stop at the river: its channel and banks up to above the bank top
		if near_river:
			var rq := river_q(ctx, x, z)
			if rq.x < 18.0 and h < rq.y + 2.0:
				continue
		if rock_blocks(ctx, bld, x, z, 0.8):
			continue
		var roll := rng.randf()
		if roll < 0.07:
			continue
		var sx := rng.randf_range(1.0, 1.1)
		var sy := rng.randf_range(0.85, 1.2)
		var sz := rng.randf_range(0.9, 1.1)
		var seed := rng.randf()
		var g := 1.0 + rng.randf_range(-0.07, 0.07)
		var xf := Transform3D(Basis(dir * sx, Vector3.UP * sy, side * sz), Vector3(x, h - 0.1, z) - org)
		out.add("hedge|Hedge", xf, Color(g, g, g * 0.97, seed))
		out.add("hedgefar|Hedge", xf, Color(g, g, g * 0.97, seed))
		var tp := Vector3(x, 0.0, z) + side * 1.2
		if roll > 0.955 and tree_clear(ctx, tp.x, tp.z, near_roads) and not excluded(ex, tp.x, tp.z, true):
			tp.y = d.height_at(tp.x, tp.z)
			var oak := "Tree_Oak_A" if roll > 0.975 else "Tree_Oak_B"
			var sc := rng.randf_range(0.9, 1.25)
			if _tree_spot_ok(ctx, bld, tp.x, tp.z, tp.y, near_river, _trunk_r(ctx, oak, sc)):
				add_tree(ctx, out, oak, tp, org, sc, rng)


static func _rows(ctx: Ctx, out: Out, bld: Build, rng: RandomNumberGenerator, ex: Array[Vector4], near_roads: bool) -> void:
	var pts: PackedVector3Array = ctx.rows.get(bld.key, PackedVector3Array())
	var d := ctx.data
	for p in pts:
		var h := d.height_at(p.x, p.z)
		if h < 1.6 or not tree_clear(ctx, p.x, p.z, near_roads) or excluded(ex, p.x, p.z, true) or in_lake(ctx, p.x, p.z, h, 1.5):
			continue
		if 1.0 - d.normal_at(p.x, p.z).y > 0.4:
			continue
		var rq := river_q(ctx, p.x, p.z)
		if rq.x < 18.0:
			continue
		var sc := rng.randf_range(0.85, 1.1)
		if rock_blocks(ctx, bld, p.x, p.z, _trunk_r(ctx, "Tree_Poplar", sc)):
			continue
		add_tree(ctx, out, "Tree_Poplar", Vector3(p.x, h, p.z), bld.org, sc, rng)


# ------------------------------------------------------------------ grass cells

const FLOWERS := {
	0: [Color(0.9, 0.12, 0.08), Color(1.0, 0.83, 0.12), Color(0.97, 0.97, 0.95), Color(0.35, 0.5, 0.95)],
	1: [Color(0.65, 0.35, 0.78), Color(0.97, 0.97, 0.95), Color(1.0, 0.85, 0.2)],
	2: [Color(1.0, 0.8, 0.15), Color(1.0, 0.55, 0.15)],
	3: [Color(0.96, 0.55, 0.72), Color(0.97, 0.97, 0.95), Color(1.0, 0.85, 0.2)],
}


static func build_grass(ctx: Ctx, cell: Vector2i) -> Dictionary:
	var d := ctx.data
	var org := Vector3(cell.x * GRASS_CELL, 0.0, cell.y * GRASS_CELL)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector3i(cell.x, cell.y, 77)) & 0x7fffffff
	var ex := local_exclusions(ctx, org, GRASS_CELL)
	var near_river := ctx.river_box.intersects(Rect2(org.x, org.z, GRASS_CELL, GRASS_CELL))
	var grass := Out.new()
	var step := 1.2
	var n := int(GRASS_CELL / step)
	for gj in n:
		for gi in n:
			var x := org.x + (gi + rng.randf()) * step
			var z := org.z + (gj + rng.randf()) * step
			var roll := rng.randf()
			var pick := rng.randf()
			if absf(x) > HALF - 2.0 or absf(z) > HALF - 2.0:
				continue
			var h := d.height_at(x, z)
			if h < 0.5 or road_dist(ctx, x, z) < 3.0 or excluded(ex, x, z, false) or in_lake(ctx, x, z, h, 0.3):
				continue
			if near_river:
				var rq := river_q(ctx, x, z)
				if rq.x < 13.5 and h < rq.y + 0.8:
					continue
			var slope := 1.0 - d.normal_at(x, z).y
			if slope > 0.5:
				continue
			var rw := d.region_weights_at(x, z)
			var nl := nl_at(ctx, x, z)
			var crop := field_zone(h, slope, rw.r, nl) * field_edge(x, z, nl)
			var vale_d := lerpf(0.85, 0.04, smoothstep(0.2, 0.45, crop))
			var high_d := 0.6 * (1.0 - smoothstep(265.0, 300.0, h))
			var coast_d := 0.55 if h > 4.8 else 0.16
			var dens := (rw.r * vale_d + rw.g * high_d + rw.b * 0.11 + rw.a * coast_d) / maxf(rw.r + rw.g + rw.b + rw.a, 0.01)
			dens *= (1.0 - smoothstep(0.35, 0.5, slope)) * ctx.density
			if roll > dens:
				continue
			var p := Vector3(x, h - 0.04, z) - org
			var fp := ctx.n_patch.get_noise_2d(x * 3.0, z * 3.0)
			var flower_p := (smoothstep(0.25, 0.5, fp) * 0.35 + 0.015) * (rw.r + rw.g * 0.6 + rw.a * 0.4 + rw.b * 0.15) * (1.0 - smoothstep(0.2, 0.45, crop))
			if pick < flower_p:
				var reg := pick_region(rw, rng.randf())
				var pal: Array = FLOWERS[reg]
				var ph := hash(Vector2i(floori(x / 18.0), floori(z / 18.0))) % 97
				var col: Color = pal[(ph + (1 if rng.randf() < 0.15 else 0)) % pal.size()]
				col = col.srgb_to_linear()
				var sc := rng.randf_range(0.8, 1.3)
				grass.add("flowers|Flowers_Tuft", Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(sc, sc, sc)), p), Color(col.r, col.g, col.b, rng.randf()))
			else:
				var sc := rng.randf_range(0.8, 1.3)
				var sy := sc * rng.randf_range(0.7, 1.35)
				if rw.a > 0.5 and h < 4.8:
					sy *= 1.5
				elif rw.b > 0.5:
					sy *= 0.8
				var b := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(sc, sy, sc))
				grass.add("grass|Grass_Tuft", Transform3D(b, p), Color(rw.r, rw.g, rw.b, rng.randf()))
	return {"cell": cell, "groups": grass.packed()}
