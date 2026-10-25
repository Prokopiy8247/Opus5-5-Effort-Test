class_name Terrain
extends Node3D
## Chunked terrain: every chunk always has a cheap 8 m mesh; chunks near the focus get a
## 2 m mesh built on WorkerThreadPool. Collision (HeightMapShape3D, or trimesh where a
## tunnel portal punches holes) exists only around the focus.

const CHUNK_CELLS := 128
const LOD0_RADIUS := 2       # chunks (Chebyshev) around focus with the 2 m mesh
const COLLISION_RADIUS := 1  # chunks around focus with collision
const SKIRT := 6.0

var data: WorldData
var chunks_per_side := 16
var material: ShaderMaterial
var focus := Vector3.ZERO
var body: StaticBody3D

var _lod1 := {}        # Vector2i -> MeshInstance3D
var _lod0 := {}        # Vector2i -> MeshInstance3D
var _pending := {}     # Vector2i -> task id
var _results := {}     # Vector2i -> Array (mesh arrays), filled by worker threads
var _mutex := Mutex.new()
var _shapes := {}      # Vector2i -> CollisionShape3D
var _shape_tasks := {} # Vector2i -> task id
var _shape_results := {}
var _lod_dirty := true
var _has_holes := {}   # Vector2i -> bool
var _last_focus_chunk := Vector2i(-999, -999)
var stats_built := 0


func setup(world_data: WorldData) -> void:
	data = world_data
	chunks_per_side = (data.n - 1) / CHUNK_CELLS
	material = ShaderMaterial.new()
	material.shader = load("res://shaders/terrain.gdshader")
	material.set_shader_parameter("splat_tex", data.splat_tex)
	material.set_shader_parameter("biome_tex", data.biome_tex)
	material.set_shader_parameter("noise_tex", _noise_tex(1, 256, 0.012, 3))
	material.set_shader_parameter("noise_detail", _noise_tex(2, 256, 0.03, 4))
	material.set_shader_parameter("world_origin", data.origin)
	material.set_shader_parameter("world_size", (data.n - 1) * data.cell)
	body = StaticBody3D.new()
	body.name = "TerrainBody"
	body.collision_layer = 1
	body.collision_mask = 0
	body.set_meta("terrain", true)
	add_child(body)
	for cz in chunks_per_side:
		for cx in chunks_per_side:
			var c := Vector2i(cx, cz)
			_has_holes[c] = _chunk_has_holes(c)


static func _noise_tex(seed_v: int, size: int, freq: float, octaves: int) -> NoiseTexture2D:
	var nt := NoiseTexture2D.new()
	var fn := FastNoiseLite.new()
	fn.seed = seed_v
	fn.frequency = freq
	fn.fractal_octaves = octaves
	nt.noise = fn
	nt.width = size
	nt.height = size
	nt.seamless = true
	nt.generate_mipmaps = true
	return nt


## Builds all far (8 m) chunk meshes, spread over worker threads. Blocking; call during loading.
func build_far_all() -> void:
	var count := chunks_per_side * chunks_per_side
	var arrays: Array = []
	arrays.resize(count)
	var task := WorkerThreadPool.add_group_task(func(i: int) -> void:
		arrays[i] = _build_arrays(Vector2i(i % chunks_per_side, i / chunks_per_side), 4)
	, count, -1, true, "terrain_far")
	WorkerThreadPool.wait_for_group_task_completion(task)
	for i in count:
		var c := Vector2i(i % chunks_per_side, i / chunks_per_side)
		var mi := _make_mesh_instance(arrays[i], "Far_%d_%d" % [c.x, c.y])
		_lod1[c] = mi


func _make_mesh_instance(arrays: Array, nm: String) -> MeshInstance3D:
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, material)
	var mi := MeshInstance3D.new()
	mi.name = nm
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(mi)
	return mi


func _chunk_has_holes(c: Vector2i) -> bool:
	var n := data.n
	for iz in range(c.y * CHUNK_CELLS, c.y * CHUNK_CELLS + CHUNK_CELLS + 1):
		var row := iz * n
		for ix in range(c.x * CHUNK_CELLS, c.x * CHUNK_CELLS + CHUNK_CELLS + 1):
			if data.surfaces[row + ix] == WorldData.HOLE:
				return true
	return false


## Thread-safe: reads only immutable world arrays.
func _build_arrays(c: Vector2i, step: int) -> Array:
	var n := data.n
	var cell := data.cell
	var hts := data.heights
	var surf := data.surfaces
	var res := CHUNK_CELLS / step
	var vc := res + 1
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	verts.resize(vc * vc + vc * 4)
	norms.resize(vc * vc + vc * 4)
	var x0 := c.x * CHUNK_CELLS
	var z0 := c.y * CHUNK_CELLS
	var k := 0
	for j in vc:
		var iz := z0 + j * step
		for i in vc:
			var ix := x0 + i * step
			var idx := iz * n + ix
			var h := hts[idx]
			if step > 1:
				# far LOD: use the lowest nearby sample so coarse triangles never cover roads
				for oz in range(-2, 3):
					var zz := clampi(iz + oz, 0, n - 1) * n
					for ox in range(-2, 3):
						h = minf(h, hts[zz + clampi(ix + ox, 0, n - 1)])
				h -= 0.3
			verts[k] = Vector3(data.origin + ix * cell, h, data.origin + iz * cell)
			var l := hts[idx - 1] if ix > 0 else h
			var r := hts[idx + 1] if ix < n - 1 else h
			var u := hts[idx - n] if iz > 0 else h
			var d := hts[idx + n] if iz < n - 1 else h
			norms[k] = Vector3(l - r, 2.0 * cell, u - d).normalized()
			k += 1
	var idxs := PackedInt32Array()
	idxs.resize(res * res * 6 + res * 4 * 12)
	var t := 0
	for j in res:
		for i in res:
			if step == 1:
				var cidx := (z0 + j) * n + x0 + i
				if surf[cidx] == WorldData.HOLE or surf[cidx + 1] == WorldData.HOLE or surf[cidx + n] == WorldData.HOLE or surf[cidx + n + 1] == WorldData.HOLE:
					continue
			else:
				var cidx2 := (z0 + j * step + step / 2) * n + x0 + i * step + step / 2
				if surf[cidx2] == WorldData.HOLE:
					continue
			var a := j * vc + i
			var b := a + 1
			var cc := a + vc
			var dd := cc + 1
			# winding: counter-clockwise seen from above (Godot front faces)
			idxs[t] = a
			idxs[t + 1] = b
			idxs[t + 2] = cc
			idxs[t + 3] = b
			idxs[t + 4] = dd
			idxs[t + 5] = cc
			t += 6
	# skirts on the 4 edges hide cracks between LODs
	var edges := [
		range(0, vc),                              # top row (j=0)
		range((vc - 1) * vc, vc * vc),             # bottom row
		range(0, vc * vc, vc),                     # left column
		range(vc - 1, vc * vc, vc),                # right column
	]
	for e in 4:
		var ring: Array = edges[e]
		var base := k
		for vi in ring:
			verts[k] = verts[vi] - Vector3(0, SKIRT, 0)
			norms[k] = norms[vi]
			k += 1
		for q in range(ring.size() - 1):
			var top_a: int = ring[q]
			var top_b: int = ring[q + 1]
			var bot_a := base + q
			var bot_b := base + q + 1
			# both windings: skirts are seen from either side
			idxs[t] = top_a
			idxs[t + 1] = bot_a
			idxs[t + 2] = top_b
			idxs[t + 3] = top_b
			idxs[t + 4] = bot_a
			idxs[t + 5] = bot_b
			idxs[t + 6] = top_a
			idxs[t + 7] = top_b
			idxs[t + 8] = bot_a
			idxs[t + 9] = top_b
			idxs[t + 10] = bot_b
			idxs[t + 11] = bot_a
			t += 6
			t += 6
	idxs.resize(t)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_INDEX] = idxs
	return arrays


func chunk_of(p: Vector3) -> Vector2i:
	return Vector2i(clampi(int((p.x - data.origin) / (CHUNK_CELLS * data.cell)), 0, chunks_per_side - 1),
		clampi(int((p.z - data.origin) / (CHUNK_CELLS * data.cell)), 0, chunks_per_side - 1))


func _process(_delta: float) -> void:
	var _t0 := Time.get_ticks_usec()
	_process_inner(_delta)
	Game.prof_add("terrain", Time.get_ticks_usec() - _t0)


func _process_inner(_delta: float) -> void:
	if data == null:
		return
	update_streaming(false)


## Call with immediate=true while loading to build synchronously around the focus.
func update_streaming(immediate: bool) -> void:
	var fc := chunk_of(focus)
	# collect finished worker results (at most 2 uploads per frame)
	var uploads := 0
	for c in _pending.keys():
		var tid: int = _pending[c]
		if not WorkerThreadPool.is_task_completed(tid):
			continue
		WorkerThreadPool.wait_for_task_completion(tid)
		_pending.erase(c)
		_mutex.lock()
		var arr: Array = _results.get(c, [])
		_results.erase(c)
		_mutex.unlock()
		if arr.is_empty():
			continue
		if _cheb(c, chunk_of(focus)) > LOD0_RADIUS + 1:
			continue
		var mi := _make_mesh_instance(arr, "Near_%d_%d" % [c.x, c.y])
		_lod0[c] = mi
		_lod_dirty = true
		stats_built += 1
		uploads += 1
		if uploads >= 2 and not immediate:
			break
	# request missing near chunks
	for dz in range(-LOD0_RADIUS, LOD0_RADIUS + 1):
		for dx in range(-LOD0_RADIUS, LOD0_RADIUS + 1):
			var c := Vector2i(fc.x + dx, fc.y + dz)
			if c.x < 0 or c.y < 0 or c.x >= chunks_per_side or c.y >= chunks_per_side:
				continue
			if _lod0.has(c) or _pending.has(c):
				continue
			if immediate:
				var mi := _make_mesh_instance(_build_arrays(c, 1), "Near_%d_%d" % [c.x, c.y])
				_lod0[c] = mi
				_lod_dirty = true
			else:
				var cc := c
				_pending[c] = WorkerThreadPool.add_task(func() -> void:
					var a := _build_arrays(cc, 1)
					_mutex.lock()
					_results[cc] = a
					_mutex.unlock()
				, false, "terrain_near")
	# drop far-away near meshes
	for c in _lod0.keys():
		if _cheb(c, fc) > LOD0_RADIUS + 1:
			(_lod0[c] as MeshInstance3D).queue_free()
			_lod0.erase(c)
			_lod_dirty = true
	# visibility: near replaces far (only when the near set changed)
	if _lod_dirty:
		_lod_dirty = false
		for c in _lod1:
			(_lod1[c] as MeshInstance3D).visible = not _lod0.has(c)
	_collect_shapes(immediate)
	# collision
	if fc != _last_focus_chunk or immediate:
		_last_focus_chunk = fc
		_update_collision(fc)


func _cheb(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))


func _update_collision(fc: Vector2i) -> void:
	for c in _shapes.keys():
		if _cheb(c, fc) > COLLISION_RADIUS + 1:
			(_shapes[c] as CollisionShape3D).queue_free()
			_shapes.erase(c)
	for dz in range(-COLLISION_RADIUS, COLLISION_RADIUS + 1):
		for dx in range(-COLLISION_RADIUS, COLLISION_RADIUS + 1):
			var c := Vector2i(fc.x + dx, fc.y + dz)
			if c.x < 0 or c.y < 0 or c.x >= chunks_per_side or c.y >= chunks_per_side:
				continue
			if _shapes.has(c) or _shape_tasks.has(c):
				continue
			var cc := c
			_shape_tasks[c] = WorkerThreadPool.add_task(func() -> void:
				var r: Variant = _shape_data(cc)
				_mutex.lock()
				_shape_results[cc] = r
				_mutex.unlock()
			, false, "terrain_shape")


## Collects finished collision data from workers and creates the shapes (cheap, main thread).
func _collect_shapes(immediate: bool) -> void:
	for c in _shape_tasks.keys():
		var tid: int = _shape_tasks[c]
		if not immediate and not WorkerThreadPool.is_task_completed(tid):
			continue
		WorkerThreadPool.wait_for_task_completion(tid)
		_shape_tasks.erase(c)
		_mutex.lock()
		var r: Variant = _shape_results.get(c)
		_shape_results.erase(c)
		_mutex.unlock()
		if r == null or _shapes.has(c):
			continue
		_shapes[c] = _make_shape(c, r)


## Thread-safe: heightmap data or trimesh faces for one chunk.
func _shape_data(c: Vector2i) -> Variant:
	if _has_holes[c]:
		var arr := _build_arrays(c, 1)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var ids: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		var faces := PackedVector3Array()
		faces.resize(ids.size())
		for i in ids.size():
			faces[i] = v[ids[i]]
		return faces
	var n := data.n
	var w := CHUNK_CELLS + 1
	var md := PackedFloat32Array()
	md.resize(w * w)
	var x0 := c.x * CHUNK_CELLS
	var z0 := c.y * CHUNK_CELLS
	var inv := 1.0 / data.cell
	for j in w:
		var row := (z0 + j) * n + x0
		for i in w:
			md[j * w + i] = data.heights[row + i] * inv
	return md


func _make_shape(c: Vector2i, r: Variant) -> CollisionShape3D:
	var cs := CollisionShape3D.new()
	cs.name = "Col_%d_%d" % [c.x, c.y]
	var size := CHUNK_CELLS * data.cell
	if r is PackedVector3Array:
		var shape := ConcavePolygonShape3D.new()
		shape.set_faces(r)
		shape.backface_collision = true
		cs.shape = shape
	else:
		var hs := HeightMapShape3D.new()
		hs.map_width = CHUNK_CELLS + 1
		hs.map_depth = CHUNK_CELLS + 1
		hs.map_data = r
		cs.shape = hs
		cs.scale = Vector3.ONE * data.cell
		cs.position = Vector3(data.origin + c.x * size + size * 0.5, 0.0, data.origin + c.y * size + size * 0.5)
	body.add_child(cs)
	return cs


func near_chunk_count() -> int:
	return _lod0.size()


func is_ready_around(p: Vector3) -> bool:
	return _shapes.has(chunk_of(p)) and _lod0.has(chunk_of(p))
