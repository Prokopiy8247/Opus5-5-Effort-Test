class_name TerrainStreamer
extends Node3D
## Streams the baked heightmap as 16x16 chunks of 256 m with three LODs (2 m / 8 m / 32 m grids).
## Mesh arrays are built on WorkerThreadPool; nodes and collision are created on the main thread.
## Collision (HeightMapShape3D, NaN holes at tunnel mouths) exists only near the focus point.

const CHUNK := 256.0
const CHUNKS := 16
const LOD_CELLS := [1, 4, 16]          # heightmap cells (2 m) per vertex step
const LOD_DIST := [420.0, 1400.0]       # switch distances (to chunk rect)
const HYST := 50.0
const COLLISION_DIST := 230.0
const SKIRT := [1.5, 5.0, 14.0]
const MAX_APPLY_PER_FRAME := 3

var wd: WorldData
var material: Material
var focus := Vector3.ZERO
var _chunks := {}          # Vector2i -> {lod, mi[3], body, building[3]}
var _jobs := {}            # task_id -> [key, lod]
var _results := []         # completed arrays waiting for the main thread
var _mutex := Mutex.new()
var _hole_set := {}
var _shared_indices := {}  # lod -> PackedInt32Array (no-hole topology)
var stats := {"built": 0, "colliders": 0}


func setup(world_data: WorldData, mat: Material) -> void:
	wd = world_data
	material = mat
	for h in wd.holes:
		_hole_set[h] = true
	for lod in 3:
		_shared_indices[lod] = _grid_indices(int(128 / LOD_CELLS[lod]) + 1, -1, -1, lod)
	# coarse LOD for every chunk immediately so the whole island is visible from frame one
	for cz in CHUNKS:
		for cx in CHUNKS:
			var key := Vector2i(cx, cz)
			_chunks[key] = {"lod": -1, "mi": [null, null, null], "body": null, "building": [false, false, false]}
			var arrays := _build_arrays(cx, cz, 2)
			_apply(key, 2, arrays)


func _process(_delta: float) -> void:
	if wd == null:
		return
	_mutex.lock()
	var ready := _results.duplicate()
	_results.clear()
	_mutex.unlock()
	var applied := 0
	for r: Array in ready:
		if applied >= MAX_APPLY_PER_FRAME:
			_mutex.lock()
			_results.append(r)
			_mutex.unlock()
			continue
		_apply(r[0], r[1], r[2])
		applied += 1
	for tid: int in _jobs.keys():
		if WorkerThreadPool.is_task_completed(tid):
			WorkerThreadPool.wait_for_task_completion(tid)
			_jobs.erase(tid)
	_update_lods()


## Chunk jobs read the world data: let them finish before it is freed (scene change / quit).
func _exit_tree() -> void:
	for tid: int in _jobs.keys():
		WorkerThreadPool.wait_for_task_completion(tid)
	_jobs.clear()


func _rect_dist(key: Vector2i, p: Vector3) -> float:
	var x0 := -wd.half + key.x * CHUNK
	var z0 := -wd.half + key.y * CHUNK
	var dx := maxf(maxf(x0 - p.x, 0.0), p.x - (x0 + CHUNK))
	var dz := maxf(maxf(z0 - p.z, 0.0), p.z - (z0 + CHUNK))
	return sqrt(dx * dx + dz * dz)


func _update_lods() -> void:
	for key: Vector2i in _chunks:
		var c: Dictionary = _chunks[key]
		var d := _rect_dist(key, focus)
		var want := 2
		if d < LOD_DIST[0] or (c.lod == 0 and d < LOD_DIST[0] + HYST):
			want = 0
		elif d < LOD_DIST[1] or (c.lod == 1 and d < LOD_DIST[1] + HYST):
			want = 1
		if want != c.lod:
			if c.mi[want] != null:
				_show(key, want)
			elif not c.building[want] and _jobs.size() < 8:
				c.building[want] = true
				var tid := WorkerThreadPool.add_task(_job.bind(key, want), false, "terrain chunk")
				_jobs[tid] = [key, want]
		# free far high-detail meshes to bound memory
		if c.lod != 0 and c.mi[0] != null and d > LOD_DIST[0] + 400.0:
			(c.mi[0] as MeshInstance3D).queue_free()
			c.mi[0] = null
		# collision near the focus only
		var need_col := d < COLLISION_DIST
		if need_col and c.body == null:
			c.body = _make_collision(key)
		elif not need_col and c.body != null and d > COLLISION_DIST + 60.0:
			(c.body as Node).queue_free()
			c.body = null
			stats.colliders -= 1


func _job(key: Vector2i, lod: int) -> void:
	var arrays := _build_arrays(key.x, key.y, lod)
	_mutex.lock()
	_results.append([key, lod, arrays])
	_mutex.unlock()


func _show(key: Vector2i, lod: int) -> void:
	var c: Dictionary = _chunks[key]
	for l in 3:
		if c.mi[l] != null:
			(c.mi[l] as MeshInstance3D).visible = l == lod
	c.lod = lod


func _apply(key: Vector2i, lod: int, arrays: Array) -> void:
	var c: Dictionary = _chunks[key]
	c.building[lod] = false
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, material)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = Vector3(-wd.half + key.x * CHUNK, 0.0, -wd.half + key.y * CHUNK)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if lod < 2 else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	add_child(mi)
	if c.mi[lod] != null:
		(c.mi[lod] as MeshInstance3D).queue_free()
	c.mi[lod] = mi
	stats.built += 1
	var d := _rect_dist(key, focus)
	var want := 0 if d < LOD_DIST[0] + HYST else (1 if d < LOD_DIST[1] + HYST else 2)
	if lod == want or c.lod == -1:
		_show(key, lod)
	else:
		mi.visible = false


func _h(ix: int, iz: int) -> float:
	ix = clampi(ix, 0, wd.res - 1)
	iz = clampi(iz, 0, wd.res - 1)
	return wd.heights[iz * wd.res + ix]


func _build_arrays(cx: int, cz: int, lod: int) -> Array:
	var cells: int = LOD_CELLS[lod]
	var n := int(128 / cells) + 1
	var gx0 := cx * 128
	var gz0 := cz * 128
	var sp := wd.step * cells
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var total := n * n + 4 * n
	verts.resize(total)
	normals.resize(total)
	var res := wd.res
	var h := wd.heights
	for j in n:
		var gz := gz0 + j * cells
		for i in n:
			var gx := gx0 + i * cells
			var y := h[mini(gz, res - 1) * res + mini(gx, res - 1)]
			var hl := _h(gx - cells, gz)
			var hr := _h(gx + cells, gz)
			var hd := _h(gx, gz - cells)
			var hu := _h(gx, gz + cells)
			var idx := j * n + i
			verts[idx] = Vector3(i * sp, y, j * sp)
			normals[idx] = Vector3(hl - hr, 2.0 * sp, hd - hu).normalized()
	# skirts: border ring dropped below the surface hides LOD cracks
	var skirt: float = SKIRT[lod]
	var border := []
	for i in n:
		border.append(i)                    # north edge (j = 0)
	for i in n:
		border.append((n - 1) * n + i)      # south edge
	for j in n:
		border.append(j * n)                # west edge
	for j in n:
		border.append(j * n + n - 1)        # east edge
	for b in border.size():
		var src: int = border[b]
		verts[n * n + b] = verts[src] - Vector3(0, skirt, 0)
		normals[n * n + b] = normals[src]
	var indices: PackedInt32Array
	var has_holes := false
	if lod == 0 and not _hole_set.is_empty():
		for j in n:
			for i in n:
				if _hole_set.has((gz0 + j) * res + gx0 + i):
					has_holes = true
					break
			if has_holes:
				break
	if has_holes:
		indices = _grid_indices(n, gx0, gz0, lod)
	else:
		indices = (_shared_indices[lod] as PackedInt32Array).duplicate()
	# skirt quads
	for e in 4:
		for k in n - 1:
			var a: int = border[e * n + k]
			var b2: int = border[e * n + k + 1]
			var sa := n * n + e * n + k
			var sb := sa + 1
			# both windings: skirts must be visible from either side of a LOD seam
			indices.append_array([a, sb, b2, a, sa, sb, a, b2, sb, a, sb, sa])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	return arrays


func _grid_indices(n: int, gx0: int, gz0: int, lod: int) -> PackedInt32Array:
	var idx := PackedInt32Array()
	var res := wd.res if wd != null else 2049
	for j in n - 1:
		for i in n - 1:
			var a := j * n + i
			var b := a + 1
			var c := a + n
			var d := c + 1
			if gx0 >= 0:
				var hole := false
				for o: Vector2i in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]:
					if _hole_set.has((gz0 + j + o.y) * res + gx0 + i + o.x):
						hole = true
				if hole:
					continue
			idx.append_array([a, b, d, a, d, c])
	return idx


func _make_collision(key: Vector2i) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = "TerrainCol_%d_%d" % [key.x, key.y]
	body.set_meta("terrain", true)
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := HeightMapShape3D.new()
	var n := 129
	shape.map_width = n
	shape.map_depth = n
	var data := PackedFloat32Array()
	data.resize(n * n)
	var gx0 := key.x * 128
	var gz0 := key.y * 128
	var res := wd.res
	for j in n:
		var row := (gz0 + j) * res + gx0
		for i in n:
			var gi := row + i
			data[j * n + i] = NAN if _hole_set.has(gi) else wd.heights[gi] * 0.5
	shape.map_data = data
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.scale = Vector3(2, 2, 2)
	body.add_child(cs)
	body.position = Vector3(-wd.half + key.x * CHUNK + CHUNK * 0.5, 0.0, -wd.half + key.y * CHUNK + CHUNK * 0.5)
	add_child(body)
	stats.colliders += 1
	return body


## Synchronously make collision for the chunk containing p (used before spawning/teleporting).
func ensure_collision_at(p: Vector3) -> void:
	var key := Vector2i(clampi(int((p.x + wd.half) / CHUNK), 0, CHUNKS - 1), clampi(int((p.z + wd.half) / CHUNK), 0, CHUNKS - 1))
	for oz in range(-1, 2):
		for ox in range(-1, 2):
			var k := key + Vector2i(ox, oz)
			if _chunks.has(k) and (_chunks[k] as Dictionary).body == null and _rect_dist(k, p) < COLLISION_DIST:
				(_chunks[k] as Dictionary).body = _make_collision(k)
