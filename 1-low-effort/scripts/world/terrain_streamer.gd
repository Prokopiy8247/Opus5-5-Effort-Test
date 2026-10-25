class_name TerrainStreamer
extends Node3D
## Chunked terrain around a focus point. Heights/colours/vegetation transforms are
## generated on WorkerThreadPool; meshes and collision are committed on the main
## thread with a per-frame budget. A coarse whole-map mesh covers the horizon.

const CHUNK := 128.0
const NEAR_RES := 2.0
const MID_RES := 8.0
const NEAR_R := 2      # chunks (collision + full detail)
const MID_R := 7       # chunks
const VEG_R := 4
const BUDGET := 2      # chunk commits per frame

var world: WorldGen
var focus := Vector3.ZERO
var chunks: Dictionary = {}       # Vector2i -> {lod, node, pending_lod}
var pending: Dictionary = {}      # Vector2i -> {task, lod, data}
var mat: ShaderMaterial
var veg_meshes: Dictionary = {}
var stats_built := 0
var results: Dictionary = {}
var mutex := Mutex.new()

func setup(w: WorldGen) -> void:
	world = w
	mat = ShaderMaterial.new()
	mat.shader = preload("res://shaders/terrain.gdshader")
	for k in ["TreePine", "TreeOak", "TreePalm", "Cactus", "Rock", "Bush", "GrassTuft"]:
		veg_meshes[k] = Kit.mesh(k, Vector3(1.5, 4, 1.5), Color(0.2, 0.4, 0.15))
	_build_far()

func _build_far() -> void:
	var res := 32.0
	var n := int(WorldGen.HALF * 2.0 / res) + 1
	var data := _gen_grid(-WorldGen.HALF, -WorldGen.HALF, n, res, -1.5, false)
	var mi := MeshInstance3D.new()
	mi.mesh = _make_mesh(data)
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.name = "FarTerrain"
	add_child(mi)
	# outer ring so the horizon is not a cliff edge
	var ring := MeshInstance3D.new()
	var pm := PlaneMesh.new(); pm.size = Vector2(14000, 14000)
	ring.mesh = pm
	var rm := StandardMaterial3D.new(); rm.albedo_color = Color(0.2, 0.3, 0.38)
	ring.material_override = rm
	ring.position = Vector3(0, -16, 0)
	add_child(ring)

func _gen_grid(x0: float, z0: float, n: int, res: float, y_off: float, skirt: bool) -> Dictionary:
	var hs := PackedFloat32Array(); hs.resize(n * n)
	for iz in n:
		for ix in n:
			hs[iz * n + ix] = world.height(x0 + ix * res, z0 + iz * res)
	var verts := PackedVector3Array(); var norms := PackedVector3Array(); var cols := PackedColorArray()
	verts.resize(n * n); norms.resize(n * n); cols.resize(n * n)
	for iz in n:
		for ix in n:
			var h := hs[iz * n + ix]
			var hl := hs[iz * n + maxi(ix - 1, 0)]; var hr := hs[iz * n + mini(ix + 1, n - 1)]
			var hd := hs[maxi(iz - 1, 0) * n + ix]; var hu := hs[mini(iz + 1, n - 1) * n + ix]
			var nrm := Vector3(hl - hr, 2.0 * res, hd - hu).normalized()
			var x := x0 + ix * res; var z := z0 + iz * res
			verts[iz * n + ix] = Vector3(x, h + y_off, z)
			norms[iz * n + ix] = nrm
			cols[iz * n + ix] = world.ground_color(x, z, h, 1.0 - nrm.y)
	var idx := PackedInt32Array()
	for iz in n - 1:
		for ix in n - 1:
			var a := iz * n + ix
			idx.append_array([a, a + 1, a + n, a + 1, a + n + 1, a + n])
	if skirt:
		# vertical skirts hide cracks between LODs
		var edges: Array = []
		for k in n: edges.append([k, 1]);
		var border: Array[int] = []
		for k in n: border.append(k)
		for k in range(1, n): border.append(k * n + n - 1)
		for k in range(n - 2, -1, -1): border.append((n - 1) * n + k)
		for k in range(n - 2, 0, -1): border.append(k * n)
		border.append(0)
		for k in border.size() - 1:
			var a := border[k]; var b := border[k + 1]
			var base := verts.size()
			verts.append(verts[a] + Vector3.DOWN * 4.0); verts.append(verts[b] + Vector3.DOWN * 4.0)
			norms.append(norms[a]); norms.append(norms[b]); cols.append(cols[a]); cols.append(cols[b])
			idx.append_array([a, base, b, b, base, base + 1])
	return {"verts": verts, "norms": norms, "cols": cols, "idx": idx, "hs": hs, "n": n}

func _make_mesh(d: Dictionary) -> ArrayMesh:
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = d.verts
	arr[Mesh.ARRAY_NORMAL] = d.norms
	arr[Mesh.ARRAY_COLOR] = d.cols
	arr[Mesh.ARRAY_INDEX] = d.idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m

func _veg(cx: int, cz: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector2i(cx, cz)) ^ world.seed_value
	var out: Dictionary = {}
	var x0 := cx * CHUNK; var z0 := cz * CHUNK
	var tries := 260
	for t in tries:
		var x := x0 + rng.randf() * CHUNK; var z := z0 + rng.randf() * CHUNK
		var rd := world.raster_sample(x, z)
		if rd.x < 14.0: continue
		if world.water_mask(x, z) > 0.05 or world.shore_dist(x, z) < 25.0: continue
		var h := world.height(x, z)
		if h < 1.0: continue
		var w := world.region_weights(x, z)
		var pick := rng.randf()
		var kind := ""
		var dens := 1.0
		if w.x > 0.5:
			# farmland: tree belts and hedges, fields mostly open
			var belt := absf(world.n_detail.get_noise_2d(x * 0.5, z * 0.5))
			dens = 0.9 if belt < 0.08 else 0.12
			kind = "TreeOak" if pick < 0.55 else ("Bush" if pick < 0.8 else "TreePine")
		elif w.y > 0.5:
			dens = 0.75 if h < 240.0 else 0.08
			kind = "TreePine" if pick < 0.75 else "Rock"
		elif w.z > 0.5:
			dens = 0.18
			kind = "Cactus" if pick < 0.5 else ("Rock" if pick < 0.8 else "Bush")
		else:
			dens = 0.35
			kind = "TreePalm" if (pick < 0.35 and world.shore_dist(x, z) < 300.0) else ("Bush" if pick < 0.7 else "TreeOak")
		if rng.randf() > dens: continue
		var s := rng.randf_range(0.75, 1.35)
		var b := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s, s))
		if not out.has(kind): out[kind] = []
		out[kind].append(Transform3D(b, Vector3(x, h - 0.15, z)))
	# grass tufts near roads for ground detail
	var grass: Array = []
	for t in 120:
		var x := x0 + rng.randf() * CHUNK; var z := z0 + rng.randf() * CHUNK
		var rd := world.raster_sample(x, z)
		if rd.x < 7.0 or rd.x > 45.0: continue
		if world.region_at(x, z) == 2: continue
		var h := world.height(x, z)
		if h < 1.0: continue
		grass.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(0.6, 0.5, 0.6)), Vector3(x, h, z)))
	if not grass.is_empty(): out["GrassTuft"] = grass
	return out

func _job(key: Vector2i, lod: int) -> void:
	var res := NEAR_RES if lod == 0 else MID_RES
	var n := int(CHUNK / res) + 1
	var d := _gen_grid(key.x * CHUNK, key.y * CHUNK, n, res, 0.0, true)
	if lod == 0:
		d["veg"] = _veg(key.x, key.y)
	mutex.lock()
	results[key] = d
	mutex.unlock()

func _process(_dt: float) -> void:
	update_stream()

func _want_lod(key: Vector2i, fc: Vector2i) -> int:
	var dx := absi(key.x - fc.x); var dz := absi(key.y - fc.y)
	var r := maxi(dx, dz)
	if r <= NEAR_R: return 0
	if r <= MID_R: return 1
	return -1

func update_stream(force_sync: bool = false) -> void:
	if world == null: return
	var fc := Vector2i(int(floor(focus.x / CHUNK)), int(floor(focus.z / CHUNK)))
	var lim := int(WorldGen.HALF / CHUNK)
	# schedule
	var wanted: Array = []
	for dz in range(-MID_R, MID_R + 1):
		for dx in range(-MID_R, MID_R + 1):
			var k := fc + Vector2i(dx, dz)
			if k.x < -lim or k.y < -lim or k.x >= lim or k.y >= lim: continue
			wanted.append(k)
	wanted.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return (a - fc).length_squared() < (b - fc).length_squared())
	for k: Vector2i in wanted:
		var lod := _want_lod(k, fc)
		var cur: int = chunks[k].lod if chunks.has(k) else -1
		if cur == lod: continue
		if pending.has(k): continue
		if pending.size() >= 8 and not force_sync: break
		pending[k] = {"lod": lod, "data": null, "task": -1}
		if force_sync:
			_job(k, lod)
			pending[k].data = results[k]; results.erase(k)
		else:
			pending[k].task = WorkerThreadPool.add_task(_job.bind(k, lod))
	# commit finished
	var commits := 0
	for k: Vector2i in pending.keys():
		var p: Dictionary = pending[k]
		if not force_sync:
			if p.task < 0 or not WorkerThreadPool.is_task_completed(p.task): continue
			WorkerThreadPool.wait_for_task_completion(p.task)
			mutex.lock()
			p.data = results.get(k)
			results.erase(k)
			mutex.unlock()
		if p.data == null: continue
		_commit(k, p.lod, p.data)
		pending.erase(k)
		commits += 1
		if commits >= BUDGET and not force_sync: break
	# unload far
	for k: Vector2i in chunks.keys():
		if _want_lod(k, fc) == -1 and not pending.has(k):
			chunks[k].node.queue_free()
			chunks.erase(k)

func _commit(k: Vector2i, lod: int, d: Dictionary) -> void:
	if chunks.has(k):
		chunks[k].node.queue_free()
	var root := Node3D.new()
	root.name = "Chunk_%d_%d_L%d" % [k.x, k.y, lod]
	var mi := MeshInstance3D.new()
	mi.mesh = _make_mesh(d)
	mi.material_override = mat
	if lod == 1: mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	if lod == 0:
		var body := StaticBody3D.new()
		body.set_meta("terrain", true)
		var cs := CollisionShape3D.new()
		var hm := HeightMapShape3D.new()
		var n: int = d.n
		hm.map_width = n; hm.map_depth = n
		hm.map_data = d.hs
		cs.shape = hm
		cs.scale = Vector3(NEAR_RES, 1.0, NEAR_RES)
		body.add_child(cs)
		body.position = Vector3(k.x * CHUNK + CHUNK * 0.5, 0, k.y * CHUNK + CHUNK * 0.5)
		root.add_child(body)
		var veg: Dictionary = d.veg
		for kind: String in veg.keys():
			var xfs: Array = veg[kind]
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = veg_meshes[kind]
			mm.instance_count = xfs.size()
			for i in xfs.size(): mm.set_instance_transform(i, xfs[i])
			var mmi := MultiMeshInstance3D.new()
			mmi.multimesh = mm
			mmi.visibility_range_end = 380.0 if kind != "GrassTuft" else 140.0
			mmi.visibility_range_end_margin = 30.0
			mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
			if kind == "GrassTuft" or kind == "Bush": mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			root.add_child(mmi)
	add_child(root)
	chunks[k] = {"lod": lod, "node": root}
	stats_built += 1

func shutdown() -> void:
	for k: Vector2i in pending.keys():
		var p: Dictionary = pending[k]
		if p.task >= 0: WorkerThreadPool.wait_for_task_completion(p.task)
	pending.clear()

func _exit_tree() -> void:
	shutdown()
