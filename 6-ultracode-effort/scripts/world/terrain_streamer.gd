class_name TerrainStreamer
extends Node3D
## Chunked terrain with distance LODs, meshes generated on the WorkerThreadPool and committed on the
## main thread under a per-frame budget. Trimesh colliders (with tunnel-portal holes) are streamed
## around "physics focus" points (player + physics-simulated traffic).

signal near_ready()

const CHUNK := 128.0
const CELLS := 64
const STRIDES := [1, 2, 4, 8]
const LOD_DIST := [300.0, 700.0, 1400.0]
const COLLIDER_RADIUS := 230.0
const MAX_TASKS := 8
const COMMITS_PER_FRAME := 6
## Chunk-edge skirts over a tunnel tube stop this far above its road (arch crown at 7.2 m).
const TUBE_CLEAR := 7.6

class Chunk:
	var key: Vector2i
	var center: Vector2
	var mi: MeshInstance3D
	var lod: int = -1
	var want: int = 3
	var building: bool = false
	var body: StaticBody3D
	var col_building: bool = false
	var want_col: bool = false

var data: WorldData
var material: Material
var focus: Vector3 = Vector3.ZERO
var physics_points: Array[Vector3] = []
var chunks: Dictionary = {}
var _n_side: int
var _results: Array = []
var _mutex := Mutex.new()
var _tasks: Dictionary = {}          # task_id -> true
var _timer: float = 0.0
var _near_ready_emitted := false
var _dirty: bool = true
var _last_focus: Vector3 = Vector3(INF, 0, INF)
var _last_phys_hash: int = 0
var _queue: Array = []               # [priority, Chunk, collider?] sorted once per wants update
var _qi: int = 0
var stats := {"meshes_built": 0, "colliders": 0, "max_commit_ms": 0.0}
## Fine grid index -> Vector2(metres outside the tube wall (< 0 above the tube), lowest skirt y) for grid
## vertices over or beside a tunnel tube, within its span. Read-only after setup (worker threads use it).
var _tube_floor: Dictionary = {}


func setup(world_data: WorldData, mat: Material) -> void:
	data = world_data
	material = mat
	_n_side = int((data.half * 2.0) / CHUNK)
	for j in _n_side:
		for i in _n_side:
			var c := Chunk.new()
			c.key = Vector2i(i, j)
			c.center = Vector2(-data.half + (i + 0.5) * CHUNK, -data.half + (j + 0.5) * CHUNK)
			var mi := MeshInstance3D.new()
			mi.name = "T_%d_%d" % [i, j]
			mi.material_override = material
			mi.position = _chunk_origin(c.key)
			add_child(mi)
			c.mi = mi
			chunks[c.key] = c
	_mark_tubes()
	_update_wants(true)


## Grid vertices over a tunnel tube and up to the coarsest LOD step beside it, inside the tube's span
## (not in front of a portal). A skirt quad that reaches over the tube has both edge vertices in here.
func _mark_tubes() -> void:
	var extra: float = data.cell * STRIDES[STRIDES.size() - 1] + 1.0
	for r in data.network.roads:
		var nn := r.pos.size()
		if nn < 2:
			continue
		var tube := WorldGen.tube_mask(r.flags)
		var wall := r.width * 0.5 + r.shoulder + 0.6
		var reach := wall + extra
		for i in nn - 1:
			if tube[i] == 0 or tube[i + 1] == 0:
				continue
			var first := i == 0 or tube[i - 1] == 0
			var last := i + 2 >= nn or tube[i + 2] == 0
			var a := r.pos[i]
			var b := r.pos[i + 1]
			var ab := Vector2(b.x - a.x, b.z - a.z)
			var ab2 := maxf(ab.length_squared(), 0.0001)
			var g0 := Vector2i(floori((minf(a.x, b.x) - reach + data.half) / data.cell), floori((minf(a.z, b.z) - reach + data.half) / data.cell))
			var g1 := Vector2i(ceili((maxf(a.x, b.x) + reach + data.half) / data.cell), ceili((maxf(a.z, b.z) + reach + data.half) / data.cell))
			for gj in range(maxi(g0.y, 0), mini(g1.y, data.n - 1) + 1):
				for gi in range(maxi(g0.x, 0), mini(g1.x, data.n - 1) + 1):
					var v := Vector2(-data.half + gi * data.cell - a.x, -data.half + gj * data.cell - a.z)
					var t := v.dot(ab) / ab2
					if (t < 0.0 and first) or (t > 1.0 and last):
						continue
					t = clampf(t, 0.0, 1.0)
					var d := (v - ab * t).length()
					if d > reach:
						continue
					var key := gj * data.n + gi
					var prev: Variant = _tube_floor.get(key)
					if prev == null or d - wall < (prev as Vector2).x:
						_tube_floor[key] = Vector2(d - wall, lerpf(a.y, b.y, t) + TUBE_CLEAR)


func _chunk_origin(k: Vector2i) -> Vector3:
	return Vector3(-data.half + k.x * CHUNK, 0.0, -data.half + k.y * CHUNK)


func _process(delta: float) -> void:
	if data == null:
		return
	_timer -= delta
	if _timer <= 0.0:
		_timer = 0.2
		var ph := 0
		for p in physics_points:
			ph = ph * 31 + int(p.x / 16.0) * 7 + int(p.z / 16.0)
		if focus.distance_to(_last_focus) > 6.0 or ph != _last_phys_hash:
			_last_focus = focus
			_last_phys_hash = ph
			_update_wants(false)
	if _dirty and _tasks.size() < MAX_TASKS:
		_dispatch()
	_commit()


## Jump the streaming focus (teleport / respawn): re-evaluates wants immediately so readiness checks
## right after the jump describe the new location, not the old one.
func refocus(pos: Vector3) -> void:
	focus = pos
	physics_points = [pos]
	_last_focus = pos
	_last_phys_hash = int(pos.x / 16.0) * 7 + int(pos.z / 16.0)
	_timer = 0.2
	_near_ready_emitted = false
	_update_wants(false)


func _update_wants(force: bool) -> void:
	var f2 := Vector2(focus.x, focus.z)
	for c: Chunk in chunks.values():
		var center := c.center
		var d := center.distance_to(f2) - CHUNK * 0.5
		var lod := 3
		for k in LOD_DIST.size():
			if d < LOD_DIST[k]:
				lod = k
				break
		c.want = lod
		var wc := false
		for p in physics_points:
			var dd := Vector2(center.x - p.x, center.y - p.z).length() - CHUNK * 0.71
			if dd < COLLIDER_RADIUS:
				wc = true
				break
		c.want_col = wc
		if not wc and c.body != null and not c.col_building:
			c.body.queue_free()
			c.body = null
	_rebuild_queue()


func _priority(c: Chunk, col: bool) -> float:
	var d := c.center.distance_to(Vector2(focus.x, focus.z))
	if col:
		return d - 10000.0
	return d + (0.0 if c.lod < 0 else 500.0 * absf(c.want - c.lod)) * (1.0 if c.want > c.lod else 0.2)


## Priority: missing colliders near physics points, then LOD changes by distance. Sorted once per wants
## update; chunks still building are picked up again when their result is committed.
func _rebuild_queue() -> void:
	_queue.clear()
	_qi = 0
	for c: Chunk in chunks.values():
		if c.want_col and c.body == null and not c.col_building:
			_queue.append([_priority(c, true), c, true])
		if c.want != c.lod and not c.building:
			_queue.append([_priority(c, false), c, false])
	_queue.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	_dirty = not _queue.is_empty()


func _dispatch() -> void:
	while _tasks.size() < MAX_TASKS and _qi < _queue.size():
		var item: Array = _queue[_qi]
		_qi += 1
		var c: Chunk = item[1]
		var col: bool = item[2]
		if col:
			if c.col_building or not c.want_col or c.body != null:
				continue
			c.col_building = true
			var id := WorkerThreadPool.add_task(_build_task.bind(c.key, 0, true, false), false, "terrain_col")
			_tasks[id] = true
		else:
			if c.building or c.want == c.lod:
				continue
			c.building = true
			var lod := c.want
			var id2 := WorkerThreadPool.add_task(_build_task.bind(c.key, lod, false, true), false, "terrain_mesh")
			_tasks[id2] = true
	if _qi >= _queue.size():
		_queue.clear()
		_qi = 0
		_dirty = false


func _build_task(key: Vector2i, lod: int, faces: bool, mesh: bool) -> void:
	var res := build_chunk_arrays(key, lod, faces, mesh)
	_mutex.lock()
	_results.append(res)
	_mutex.unlock()


func _commit() -> void:
	_mutex.lock()
	var batch := _results.slice(0, COMMITS_PER_FRAME)
	_results = _results.slice(COMMITS_PER_FRAME)
	_mutex.unlock()
	# Release finished tasks.
	for id: int in _tasks.keys():
		if WorkerThreadPool.is_task_completed(id):
			WorkerThreadPool.wait_for_task_completion(id)
			_tasks.erase(id)
	var t0 := Time.get_ticks_usec()
	var leftover: Array = []
	for res: Dictionary in batch:
		if Time.get_ticks_usec() - t0 > 4000:
			leftover.append(res)
			continue
		var c: Chunk = chunks[res["key"]]
		if res.has("arrays"):
			var am := ArrayMesh.new()
			am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, res["arrays"])
			am.custom_aabb = res["aabb"]
			c.mi.mesh = am
			c.lod = res["lod"]
			c.building = false
			if c.want != c.lod:
				# Wants moved on while this chunk was building.
				_queue.append([_priority(c, false), c, false])
				_dirty = true
			stats["meshes_built"] += 1
		if res.has("faces") or res.has("heights"):
			c.col_building = false
			if c.want_col and c.body == null:
				var body := StaticBody3D.new()
				body.name = "TC_%d_%d" % [c.key.x, c.key.y]
				body.collision_layer = 1
				body.collision_mask = 0
				body.set_meta(&"terrain", true)
				var cs := CollisionShape3D.new()
				if res.has("heights"):
					var hs := HeightMapShape3D.new()
					hs.map_width = CELLS + 1
					hs.map_depth = CELLS + 1
					hs.map_data = res["heights"]
					cs.shape = hs
					cs.scale = Vector3(data.cell, 1.0, data.cell)
					cs.position = Vector3(CHUNK * 0.5, 0.0, CHUNK * 0.5)
				else:
					var shape := ConcavePolygonShape3D.new()
					shape.set_faces(res["faces"])
					cs.shape = shape
				body.add_child(cs)
				body.position = _chunk_origin(c.key)
				add_child(body)
				c.body = body
				stats["colliders"] += 1
	if not leftover.is_empty():
		_mutex.lock()
		_results = leftover + _results
		_mutex.unlock()
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	stats["max_commit_ms"] = maxf(stats["max_commit_ms"], ms)
	if not _near_ready_emitted and is_near_ready():
		_near_ready_emitted = true
		near_ready.emit()


## True when every chunk that wants a collider has one and nearby meshes are at their wanted LOD.
func is_near_ready() -> bool:
	for c: Chunk in chunks.values():
		if c.want_col and c.body == null:
			return false
		if c.want == 0 and c.lod != 0:
			return false
	return true


func pending_count() -> int:
	var n := 0
	for c: Chunk in chunks.values():
		if c.lod != c.want or (c.want_col and c.body == null):
			n += 1
	return n


## Builds mesh arrays (and optionally collision faces) for one chunk. Thread-safe (reads only).
func build_chunk_arrays(key: Vector2i, lod: int, want_faces: bool, want_mesh: bool) -> Dictionary:
	var stride: int = STRIDES[lod]
	var cells := CELLS / stride
	var vn := cells + 1
	var gi0 := key.x * CELLS
	var gj0 := key.y * CELLS
	var org := _chunk_origin(key)
	var hgrid := PackedFloat32Array()
	hgrid.resize(vn * vn)
	var miny := INF
	var maxy := -INF
	for j in vn:
		for i in vn:
			var gi := gi0 + i * stride
			var gj := gj0 + j * stride
			var h := data.grid_height(gi, gj)
			if stride > 1:
				# Near roads use the minimum of the footprint so coarse terrain never covers the road.
				var wx := -data.half + gi * data.cell
				var wz := -data.half + gj * data.cell
				if data.road_distance_at(wx, wz) < stride * data.cell * 1.5 + 6.0:
					for oj in range(-stride / 2, stride / 2 + 1):
						for oi in range(-stride / 2, stride / 2 + 1):
							h = minf(h, data.grid_height(gi + oi, gj + oj))
			hgrid[j * vn + i] = h
			miny = minf(miny, h)
			maxy = maxf(maxy, h)
	var res := {"key": key, "lod": lod}
	var is_hole := func(i: int, j: int) -> bool:
		# Skip the quad if any fine grid vertex it covers (corners included) is a tunnel-portal hole,
		# so no triangle can bridge from road level up to the mountain across a portal.
		for oj in stride + 1:
			for oi in stride + 1:
				if data.is_hole(gi0 + i * stride + oi, gj0 + j * stride + oj):
					return true
		return false
	var has_holes := false
	var near_holes := false      # holes close enough to the chunk edge to matter for its skirts
	if not data.holes.is_empty():
		var cx0 := gi0
		var cz0 := gj0
		var m: int = STRIDES[STRIDES.size() - 1] + 1
		for k: int in data.holes:
			var hj := k / data.n
			var hi := k % data.n
			if hi >= cx0 - m and hi <= cx0 + CELLS + m and hj >= cz0 - m and hj <= cz0 + CELLS + m:
				near_holes = true
				if hi >= cx0 - 1 and hi <= cx0 + CELLS and hj >= cz0 - 1 and hj <= cz0 + CELLS:
					has_holes = true
					break
	var step := data.cell * stride
	if want_mesh:
		var verts := PackedVector3Array()
		var norms := PackedVector3Array()
		var cols := PackedColorArray()
		var idx := PackedInt32Array()
		var total_v := vn * vn + vn * 4
		verts.resize(total_v)
		norms.resize(total_v)
		cols.resize(total_v)
		for j in vn:
			for i in vn:
				var k := j * vn + i
				var lx := i * step
				var lz := j * step
				var h := hgrid[k]
				verts[k] = Vector3(lx, h, lz)
				var gi := gi0 + i * stride
				var gj := gj0 + j * stride
				var hl := data.grid_height(gi - stride, gj)
				var hr := data.grid_height(gi + stride, gj)
				var hd := data.grid_height(gi, gj - stride)
				var hu := data.grid_height(gi, gj + stride)
				norms[k] = Vector3(hl - hr, 2.0 * step, hd - hu).normalized()
				cols[k] = data.region_weights_at(org.x + lx, org.z + lz)
		for j in cells:
			for i in cells:
				if has_holes and is_hole.call(i, j):
					continue
				var a := j * vn + i
				var b := a + 1
				var c := a + vn
				var d := c + 1
				idx.append_array([a, b, c, b, d, c])
		# Skirts along the four edges.
		var skirt := 3.0 + stride * 2.0
		var base := vn * vn
		var edges := [[], [], [], []]
		for t in vn:
			edges[0].append(t)                       # top row (j=0)
			edges[1].append((vn - 1) * vn + t)       # bottom row
			edges[2].append(t * vn)                  # left column
			edges[3].append(t * vn + vn - 1)         # right column
		# No skirt along an edge stretch next to a tunnel-portal hole (on either chunk's side, at any LOD):
		# it would hang from the cover above the tube into the tunnel mouth.
		var skirt_hole := func(e: int, t: int) -> bool:
			var along0 := t * stride - 1
			var along1 := (t + 1) * stride + 1
			for a in range(along0, along1 + 1):
				for o in range(-STRIDES[STRIDES.size() - 1], STRIDES[STRIDES.size() - 1] + 1):
					var gi: int
					var gj: int
					if e < 2:
						gi = gi0 + a
						gj = (gj0 if e == 0 else gj0 + CELLS) + o
					else:
						gi = (gi0 if e == 2 else gi0 + CELLS) + o
						gj = gj0 + a
					if data.is_hole(gi, gj):
						return true
			return false
		for e in 4:
			var row: Array = edges[e]
			for t in vn:
				var src: int = row[t]
				var vi := base + e * vn + t
				verts[vi] = verts[src] - Vector3(0, skirt, 0)
				if not _tube_floor.is_empty():
					# Over a tunnel tube the skirt stops above the crown (the cover is ~10 m above the road).
					var tf: Variant = _tube_floor.get((gj0 + (src / vn) * stride) * data.n + gi0 + (src % vn) * stride)
					if tf != null and (tf as Vector2).x <= step + 0.5:
						verts[vi].y = maxf(verts[vi].y, minf((tf as Vector2).y, verts[src].y))
				norms[vi] = norms[src]
				cols[vi] = cols[src]
			for t in vn - 1:
				if near_holes and skirt_hole.call(e, t):
					continue
				var a2: int = row[t]
				var b2: int = row[t + 1]
				var c2 := base + e * vn + t
				var d2 := c2 + 1
				idx.append_array([a2, c2, b2, b2, c2, d2, a2, b2, c2, b2, d2, c2])
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_NORMAL] = norms
		arrays[Mesh.ARRAY_COLOR] = cols
		arrays[Mesh.ARRAY_INDEX] = idx
		res["arrays"] = arrays
		res["aabb"] = AABB(Vector3(0, miny - skirt, 0), Vector3(CHUNK, maxy - miny + skirt + 1.0, CHUNK))
	if want_faces and not has_holes:
		# Cheap height-field collider (built ~10x faster than a trimesh on the main thread).
		res["heights"] = hgrid
	elif want_faces:
		var faces := PackedVector3Array()
		faces.resize(cells * cells * 6)
		var fi := 0
		for j in cells:
			for i in cells:
				if has_holes and is_hole.call(i, j):
					continue
				var p00 := Vector3(i * step, hgrid[j * vn + i], j * step)
				var p10 := Vector3((i + 1) * step, hgrid[j * vn + i + 1], j * step)
				var p01 := Vector3(i * step, hgrid[(j + 1) * vn + i], (j + 1) * step)
				var p11 := Vector3((i + 1) * step, hgrid[(j + 1) * vn + i + 1], (j + 1) * step)
				faces[fi] = p00
				faces[fi + 1] = p10
				faces[fi + 2] = p01
				faces[fi + 3] = p10
				faces[fi + 4] = p11
				faces[fi + 5] = p01
				fi += 6
		faces.resize(fi)
		res["faces"] = faces
	return res


func _exit_tree() -> void:
	for id: int in _tasks.keys():
		WorkerThreadPool.wait_for_task_completion(id)
	_tasks.clear()
