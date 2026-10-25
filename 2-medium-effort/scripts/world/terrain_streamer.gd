class_name TerrainStreamer
extends Node3D
## Streams 128 m terrain chunks around the focus point. Heights, normals, colours, collision faces and
## vegetation transforms are generated on WorkerThreadPool; the main thread only uploads finished data
## (a bounded number per frame). A coarse far mesh covers the whole map underneath.

const CHUNK: float = 128.0
const RES: int = 32  # quads per side (4 m)
const LOAD_RADIUS: float = 760.0
const UNLOAD_RADIUS: float = 900.0
const COLLISION_RADIUS: float = 300.0
const MAX_UPLOADS_PER_FRAME: int = 1
const MAX_TASKS: int = 6

var world: WorldData
var focus: Vector3 = Vector3.ZERO
var material: ShaderMaterial
var dressing: Node = null  # VegetationKit (provides meshes + placement)

var _chunks: Dictionary = {}  # key Vector2i -> {node, body, state}
var _pending: Dictionary = {}  # key -> task id
var _done: Array = []
var _mutex := Mutex.new()
var stats_uploaded: int = 0
var prof: Dictionary = {"upload_ms_max": 0.0, "collision_ms_max": 0.0, "upload_ms_sum": 0.0, "collision_ms_sum": 0.0, "frame_ms_max": 0.0}
var far_mesh: MeshInstance3D


func setup(w: WorldData, mat: ShaderMaterial) -> void:
	world = w
	material = mat


func build_far_mesh() -> void:
	# whole-map low-resolution terrain (40 m), sunk slightly so near chunks always win
	var span: float = 6400.0
	var n: int = 160
	var stepf: float = span / n
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hs := PackedFloat32Array()
	hs.resize((n + 1) * (n + 1))
	for iz in n + 1:
		for ix in n + 1:
			var x: float = -span * 0.5 + ix * stepf
			var z: float = -span * 0.5 + iz * stepf
			hs[iz * (n + 1) + ix] = world.height(x, z) - 1.2
	for iz in n + 1:
		for ix in n + 1:
			var x: float = -span * 0.5 + ix * stepf
			var z: float = -span * 0.5 + iz * stepf
			var h: float = hs[iz * (n + 1) + ix]
			var hl: float = hs[iz * (n + 1) + maxi(ix - 1, 0)]
			var hr: float = hs[iz * (n + 1) + mini(ix + 1, n)]
			var hd: float = hs[maxi(iz - 1, 0) * (n + 1) + ix]
			var hu: float = hs[mini(iz + 1, n) * (n + 1) + ix]
			var nrm := Vector3(hl - hr, 2.0 * stepf, hd - hu).normalized()
			st.set_color(world.terrain_color(x, z, h, 1.0 - nrm.y * nrm.y))
			st.set_normal(nrm)
			st.set_uv(Vector2(x, z) * 0.25)
			st.add_vertex(Vector3(x, h, z))
	for iz in n:
		for ix in n:
			var a: int = iz * (n + 1) + ix
			var b: int = a + 1
			var c: int = a + n + 1
			var d: int = c + 1
			st.add_index(a); st.add_index(b); st.add_index(c)
			st.add_index(b); st.add_index(d); st.add_index(c)
	far_mesh = MeshInstance3D.new()
	far_mesh.name = "FarTerrain"
	far_mesh.mesh = st.commit()
	var fm: ShaderMaterial = material.duplicate()
	fm.set_shader_parameter("is_far", true)
	far_mesh.material_override = fm
	far_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(far_mesh)


## radius around the focus that is fully covered by loaded near chunks
func _covered_radius() -> float:
	var k: Vector2i = chunk_key(focus)
	var r: float = 0.0
	for ring in range(1, int(LOAD_RADIUS / CHUNK) + 1):
		var full: bool = true
		for dz in range(-ring, ring + 1):
			for dx in range(-ring, ring + 1):
				if maxi(absi(dx), absi(dz)) != ring:
					continue
				var kk := Vector2i(k.x + dx, k.y + dz)
				if _chunk_dist(kk) < LOAD_RADIUS - CHUNK and not _chunks.has(kk):
					full = false
		if not full:
			break
		r = ring * CHUNK
	return clampf(r - CHUNK * 0.25, 0.0, LOAD_RADIUS - CHUNK * 0.9)


func chunk_key(p: Vector3) -> Vector2i:
	return Vector2i(int(floor(p.x / CHUNK)), int(floor(p.z / CHUNK)))


func loaded_count() -> int:
	return _chunks.size()


func is_ready_around(p: Vector3, r: float = 200.0) -> bool:
	var k: Vector2i = chunk_key(p)
	var n: int = int(ceil(r / CHUNK))
	for dz in range(-n, n + 1):
		for dx in range(-n, n + 1):
			var kk := Vector2i(k.x + dx, k.y + dz)
			if not _chunks.has(kk) or _chunks[kk].body == null and _chunk_dist(kk) < COLLISION_RADIUS:
				return false
	return true


func _chunk_dist(k: Vector2i) -> float:
	var c := Vector2((k.x + 0.5) * CHUNK, (k.y + 0.5) * CHUNK)
	return c.distance_to(Vector2(focus.x, focus.z))


## Synchronous generation around a point (used at spawn / teleport so the car never falls).
func force_load(p: Vector3, r: float = 260.0) -> void:
	focus = p
	var k: Vector2i = chunk_key(p)
	var n: int = int(ceil(r / CHUNK))
	for dz in range(-n, n + 1):
		for dx in range(-n, n + 1):
			var kk := Vector2i(k.x + dx, k.y + dz)
			if _chunks.has(kk):
				if _chunks[kk].body == null:
					_add_collision(kk)
				continue
			if _pending.has(kk):
				WorkerThreadPool.wait_for_task_completion(_pending[kk])
				_pending.erase(kk)
			else:
				_generate(kk)
	_flush(1000)


func _process(_delta: float) -> void:
	var _pf: int = Time.get_ticks_usec()
	_inner_streamer(_delta)
	Game.prof_add("streamer", _pf)


func _inner_streamer(_delta: float) -> void:
	if world == null:
		return
	var _pt0: int = Time.get_ticks_usec()
	if far_mesh:
		(far_mesh.material_override as ShaderMaterial).set_shader_parameter("focus", focus)
		(far_mesh.material_override as ShaderMaterial).set_shader_parameter("hide_r", _covered_radius())
	var k: Vector2i = chunk_key(focus)
	var n: int = int(ceil(LOAD_RADIUS / CHUNK))
	# queue new chunks nearest first
	var wanted: Array = []
	for dz in range(-n, n + 1):
		for dx in range(-n, n + 1):
			var kk := Vector2i(k.x + dx, k.y + dz)
			if absf(kk.x * CHUNK) > 2600.0 or absf(kk.y * CHUNK) > 2600.0:
				continue
			var d: float = _chunk_dist(kk)
			if d < LOAD_RADIUS and not _chunks.has(kk) and not _pending.has(kk):
				wanted.append([d, kk])
	wanted.sort_custom(func(a, b): return a[0] < b[0])
	for item in wanted:
		if _pending.size() >= MAX_TASKS:
			break
		var kk: Vector2i = item[1]
		_pending[kk] = WorkerThreadPool.add_task(_generate.bind(kk), false, "terrain chunk")
	# finished tasks
	for kk in _pending.keys():
		if WorkerThreadPool.is_task_completed(_pending[kk]):
			WorkerThreadPool.wait_for_task_completion(_pending[kk])
			_pending.erase(kk)
	_flush(MAX_UPLOADS_PER_FRAME)
	# collision near the focus (at most one new shape per frame), unload far chunks
	var col_budget: int = 1
	for kk in _chunks.keys():
		var d: float = _chunk_dist(kk)
		var c: Dictionary = _chunks[kk]
		if d > UNLOAD_RADIUS:
			c.node.queue_free()
			_chunks.erase(kk)
		elif d < COLLISION_RADIUS and c.body == null and col_budget > 0:
			col_budget -= 1
			var t1: int = Time.get_ticks_usec()
			_add_collision(kk)
			var ms2: float = (Time.get_ticks_usec() - t1) / 1000.0
			prof.collision_ms_max = maxf(prof.collision_ms_max, ms2)
			prof.collision_ms_sum += ms2
		elif d > COLLISION_RADIUS + 80.0 and c.body != null:
			c.body.queue_free()
			c.body = null


func _flush(limit: int) -> void:
	var count: int = 0
	while count < limit:
		_mutex.lock()
		var item: Variant = _done.pop_front() if not _done.is_empty() else null
		_mutex.unlock()
		if item == null:
			break
		var t0: int = Time.get_ticks_usec()
		_upload(item)
		var ms: float = (Time.get_ticks_usec() - t0) / 1000.0
		prof.upload_ms_max = maxf(prof.upload_ms_max, ms)
		prof.upload_ms_sum += ms
		count += 1


# ------------------------------------------------------------ worker side
func _generate(k: Vector2i) -> void:
	var n: int = RES + 1
	var stepf: float = CHUNK / RES
	var ox: float = k.x * CHUNK
	var oz: float = k.y * CHUNK
	# heights with a 1-vertex border for normals
	var hb := PackedFloat32Array()
	hb.resize((n + 2) * (n + 2))
	var hole := PackedByteArray()
	hole.resize(n * n)
	for iz in n + 2:
		for ix in n + 2:
			var x: float = ox + (ix - 1) * stepf
			var z: float = oz + (iz - 1) * stepf
			hb[iz * (n + 2) + ix] = world.height(x, z)
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	verts.resize(n * n)
	normals.resize(n * n)
	colors.resize(n * n)
	uvs.resize(n * n)
	for iz in n:
		for ix in n:
			var bi: int = (iz + 1) * (n + 2) + ix + 1
			var h: float = hb[bi]
			var x: float = ox + ix * stepf
			var z: float = oz + iz * stepf
			var nrm := Vector3(hb[bi - 1] - hb[bi + 1], 2.0 * stepf, hb[bi - (n + 2)] - hb[bi + (n + 2)]).normalized()
			var i: int = iz * n + ix
			verts[i] = Vector3(x, h, z)
			normals[i] = nrm
			colors[i] = world.terrain_color(x, z, h, 1.0 - nrm.y * nrm.y)
			uvs[i] = Vector2(x, z) * 0.25
			# tunnel holes: terrain that would intersect a tunnel tube is removed
			var q: Dictionary = world.road_query(x, z, 20.0)
			if q.ok and q.d < q.hw + 5.0 and h > q.hc - 1.5 and h < q.hc + 13.0:
				var fl: PackedByteArray = world.roads[q.road].flags
				var near_tunnel: bool = false
				for fk in range(maxi(0, q.seg - 3), mini(fl.size(), q.seg + 5)):
					if fl[fk] == 2:
						near_tunnel = true
						break
				if near_tunnel:
					hole[i] = 1
	var idx := PackedInt32Array()
	var faces := PackedVector3Array()
	for iz in RES:
		for ix in RES:
			var a: int = iz * n + ix
			var b: int = a + 1
			var c: int = a + n
			var d: int = c + 1
			if hole[a] + hole[b] + hole[c] + hole[d] > 0:
				continue
			idx.append_array([a, b, c, b, d, c])
			faces.append_array([verts[a], verts[b], verts[c], verts[b], verts[d], verts[c]])
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = idx
	var veg: Dictionary = {}
	if dressing != null:
		veg = dressing.place_in_chunk(world, k, CHUNK)
	_mutex.lock()
	_done.append({"key": k, "arrays": arrays, "faces": faces, "veg": veg})
	_mutex.unlock()


# ------------------------------------------------------------ main thread
func _upload(item: Dictionary) -> void:
	var k: Vector2i = item.key
	if _chunks.has(k):
		return
	var mesh := ArrayMesh.new()
	if (item.arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size() > 0:
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, item.arrays)
	var mi := MeshInstance3D.new()
	mi.name = "Chunk_%d_%d" % [k.x, k.y]
	mi.mesh = mesh
	mi.material_override = material
	add_child(mi)
	if dressing != null and not item.veg.is_empty():
		dressing.spawn_instances(mi, item.veg)
	_chunks[k] = {"node": mi, "body": null, "faces": item.faces}
	stats_uploaded += 1
	if _chunk_dist(k) < COLLISION_RADIUS:
		_add_collision(k)


func _add_collision(k: Vector2i) -> void:
	var c: Dictionary = _chunks[k]
	var faces: PackedVector3Array = c.faces
	if faces.is_empty():
		return
	var body := StaticBody3D.new()
	body.name = "TerrainBody"
	body.collision_layer = 1
	body.collision_mask = 0
	body.set_meta("terrain", true)
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	shape.backface_collision = true
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	(c.node as Node3D).add_child(body)
	c.body = body


func _exit_tree() -> void:
	for kk in _pending.keys():
		WorkerThreadPool.wait_for_task_completion(_pending[kk])
	_pending.clear()
