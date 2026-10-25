extends Node3D
## Biome vegetation: trees, bushes, rocks, cacti, hay bales placed deterministically per 256 m
## chunk (worker threads compute transforms, main thread builds MultiMeshes), kept within
## VEG_RADIUS of the camera. Near-camera grass/wheat/flower clumps live in 16 m cells.

const CHUNK := 256.0
const ORIGIN := -2048.0
const COUNT := 16
const VEG_RADIUS := 1900.0
const GRASS_CELL := 32.0
const GRASS_RADIUS := 72.0

# species: name, visibility end, shadow, scale range
const SPECIES := {
	"tree_conifer": [2100.0, true, Vector2(0.75, 1.25)], "tree_conifer_b": [2100.0, true, Vector2(0.8, 1.2)],
	"tree_broadleaf": [1900.0, true, Vector2(0.8, 1.3)], "tree_broadleaf_b": [1900.0, true, Vector2(0.75, 1.2)],
	"tree_poplar": [1900.0, true, Vector2(0.8, 1.2)], "tree_umbrella_pine": [1900.0, true, Vector2(0.8, 1.2)],
	"bush": [520.0, false, Vector2(0.7, 1.4)], "bush_dry": [520.0, false, Vector2(0.6, 1.3)],
	"rock_a": [900.0, true, Vector2(0.6, 2.2)], "rock_b": [900.0, true, Vector2(0.6, 2.0)], "rock_red": [1100.0, true, Vector2(0.8, 3.0)],
	"cactus": [1100.0, true, Vector2(0.7, 1.3)], "dead_tree": [900.0, true, Vector2(0.8, 1.3)], "hay_bale": [600.0, true, Vector2(0.95, 1.05)],
}

var world: Node
var data: WorldData
var _road_mask := PackedByteArray()
var _chunks: Dictionary = {}          # Vector2i -> Node3D (built) / "pending"
var _results: Dictionary = {}         # Vector2i -> Dictionary species -> Array[Transform3D]
var _mutex := Mutex.new()
var _tasks: Dictionary = {}           # Vector2i -> task id
var _excl: Array = []
var _grass_cells: Dictionary = {}
var _grass_meshes: Dictionary = {}
var _last_cam := Vector3(INF, 0, INF)
var _mesh_aabb: Dictionary = {}       # species -> local AABB (read by workers)
var instance_total: int = 0


func setup(w: Node) -> void:
	world = w
	data = w.get("data")
	name = "Vegetation"
	var img := data.road_mask_image()
	if img != null:
		_road_mask = img.get_data()
	# buildings and landmarks keep their surroundings clear
	if w.get("props") != null:
		_excl = w.get("props").get("exclusion")
	for k in ["grass_clump", "wheat_clump", "flowers"]:
		_grass_meshes[k] = PropLibrary.mesh(k)
		_mesh_aabb[k] = _grass_meshes[k].get_aabb() if _grass_meshes[k] != null else AABB()
	for sp in SPECIES:
		var m := PropLibrary.mesh(sp)
		_mesh_aabb[sp] = m.get_aabb() if m != null else AABB()


func _exit_tree() -> void:
	# worker jobs read this node's data: let them finish before it is freed (quit / world reload)
	for k in _tasks:
		WorkerThreadPool.wait_for_task_completion(_tasks[k])
	_tasks.clear()
	for k in _grass_tasks:
		WorkerThreadPool.wait_for_task_completion(_grass_tasks[k])
	_grass_tasks.clear()


func _road_at(x: float, z: float) -> bool:
	if _road_mask.is_empty():
		return false
	var px := clampi(int((x + data.half) / (2.0 * data.half) * 2048.0), 0, 2047)
	var pz := clampi(int((z + data.half) / (2.0 * data.half) * 2048.0), 0, 2047)
	return _road_mask[pz * 2048 + px] > 0


func _near_road(x: float, z: float, r: float) -> bool:
	return _road_at(x, z) or _road_at(x + r, z) or _road_at(x - r, z) or _road_at(x, z + r) or _road_at(x, z - r)


func _excluded(x: float, z: float) -> bool:
	for e in _excl:
		var c: Vector2 = e[0]
		if absf(c.x - x) < e[1] and absf(c.y - z) < e[1]:
			return true
	return false


# ------------------------------------------------------------------------------------------------
func _generate(key: Vector2i) -> void:
	## worker thread: deterministic placement for one chunk
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(key) ^ 0x5eed
	var out: Dictionary = {}
	var x0 := ORIGIN + key.x * CHUNK
	var z0 := ORIGIN + key.y * CHUNK
	var tries := 2600
	for t in tries:
		var x := x0 + rng.randf() * CHUNK
		var z := z0 + rng.randf() * CHUNK
		if absf(x) > data.half - 30.0 or absf(z) > data.half - 30.0:
			continue
		var h := data.height_at(x, z)
		if h < 0.6:
			continue
		var roll := rng.randf()
		var sp := data.splat_at(x, z)
		var region := data.region_index(x, z)
		var nrm := data.normal_at(x, z)
		var slope := 1.0 - nrm.y
		var pick := ""
		var snow := h > data.snow_line - 20.0
		if slope > 0.33:
			if roll < 0.05:
				pick = "rock_red" if sp.g > 0.5 else ("rock_a" if rng.randf() < 0.5 else "rock_b")
		elif sp.a > 0.5:
			if roll < 0.006:
				pick = "tree_umbrella_pine"
			elif roll < 0.02:
				pick = "bush_dry"
		elif sp.g > 0.55:
			if roll < 0.014:
				pick = "cactus"
			elif roll < 0.03:
				pick = "bush_dry"
			elif roll < 0.036:
				pick = "rock_red"
			elif roll < 0.039:
				pick = "dead_tree"
		elif region == 2:
			if snow:
				if roll < 0.01:
					pick = "rock_a"
				elif roll < 0.016:
					pick = "dead_tree"
			elif roll < sp.b * 0.5 + 0.09:
				pick = "tree_conifer" if rng.randf() < 0.6 else "tree_conifer_b"
			elif roll < sp.b * 0.5 + 0.12:
				pick = "rock_b"
			elif roll < sp.b * 0.5 + 0.15:
				pick = "bush"
		elif region == 0:
			if roll < sp.b * 0.35 + 0.012:
				pick = "tree_umbrella_pine" if rng.randf() < 0.6 else "tree_conifer"
			elif roll < sp.b * 0.35 + 0.05:
				pick = "bush"
			elif roll < sp.b * 0.35 + 0.056:
				pick = "rock_a"
		else:
			# farmland valley: forests, hedgerow trees, poplars, bushes; fields get hay bales
			if sp.r > 0.55:
				if roll < 0.0025:
					pick = "hay_bale"
			elif roll < sp.b * 0.55:
				pick = ["tree_broadleaf", "tree_broadleaf_b", "tree_conifer"][rng.randi_range(0, 2)]
			elif roll < sp.b * 0.55 + 0.018:
				pick = "tree_broadleaf" if rng.randf() < 0.6 else "tree_poplar"
			elif roll < sp.b * 0.55 + 0.05:
				pick = "bush"
			elif roll < sp.b * 0.55 + 0.053:
				pick = "rock_a"
		if pick == "":
			continue
		var clear := 7.5 if pick.begins_with("tree") else 4.5
		if _near_road(x, z, clear):
			continue
		if data.water_level_at(x, z) > -999.0:
			continue
		if _excluded(x, z):
			continue
		var cfg: Array = SPECIES[pick]
		var sr: Vector2 = cfg[2]
		var s := rng.randf_range(sr.x, sr.y)
		var b := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s, s))
		if pick.begins_with("rock"):
			b = Basis(Vector3(rng.randf(), rng.randf(), rng.randf()).normalized(), rng.randf() * 0.6) * b
		var y := h - (0.25 if pick.begins_with("tree") else 0.1)
		if pick.begins_with("rock"):
			y -= slope * s * 1.4  # sink rocks on steep cut walls so their downhill side never floats
		if not out.has(pick):
			out[pick] = []
		(out[pick] as Array).append(Transform3D(b, Vector3(x, y, z)))
	# pack MultiMesh buffers on the worker (transform 12 floats + colour 4 floats per instance)
	# plus a custom AABB so the renderer never has to recompute bounds per instance
	var packed: Dictionary = {}
	for sp in out:
		var list: Array = out[sp]
		packed[sp + "#aabb"] = _bounds(list, _mesh_aabb.get(sp, AABB()), (SPECIES[sp] as Array)[2].y)
		var buf := PackedFloat32Array()
		buf.resize(list.size() * 16)
		for i in list.size():
			var t: Transform3D = list[i]
			var o := i * 16
			buf[o] = t.basis.x.x
			buf[o + 1] = t.basis.y.x
			buf[o + 2] = t.basis.z.x
			buf[o + 3] = t.origin.x
			buf[o + 4] = t.basis.x.y
			buf[o + 5] = t.basis.y.y
			buf[o + 6] = t.basis.z.y
			buf[o + 7] = t.origin.y
			buf[o + 8] = t.basis.x.z
			buf[o + 9] = t.basis.y.z
			buf[o + 10] = t.basis.z.z
			buf[o + 11] = t.origin.z
			var v := 0.88 + rng.randf() * 0.24
			buf[o + 12] = v
			buf[o + 13] = v
			buf[o + 14] = v * 0.97
			buf[o + 15] = 1.0
		packed[sp] = buf
	_mutex.lock()
	_results[key] = packed
	_mutex.unlock()


func _bounds(list: Array, local: AABB, max_scale: float) -> AABB:
	if list.is_empty():
		return AABB()
	var lo := Vector3(INF, INF, INF)
	var hi := -lo
	for t: Transform3D in list:
		lo = lo.min(t.origin)
		hi = hi.max(t.origin)
	var r := maxf(maxf(absf(local.position.x), absf(local.end.x)), maxf(absf(local.position.z), absf(local.end.z))) * max_scale * 1.8
	lo += Vector3(-r, local.position.y * max_scale * 1.8 - 1.0, -r)
	hi += Vector3(r, local.end.y * max_scale * 1.8 + 1.0, r)
	return AABB(lo, hi - lo)


func _build(key: Vector2i, out: Dictionary) -> void:
	var holder := Node3D.new()
	holder.name = "Veg_%d_%d" % [key.x, key.y]
	add_child(holder)
	for sp in out:
		if String(sp).ends_with("#aabb"):
			continue
		var buf: PackedFloat32Array = out[sp]
		var count := buf.size() / 16
		var mesh := PropLibrary.mesh(sp)
		if mesh == null or count == 0:
			continue
		Game.prof_begin("vb_mm")
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.custom_aabb = out.get(sp + "#aabb", AABB())
		mm.mesh = mesh
		mm.instance_count = count
		mm.buffer = buf
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		var cfg: Array = SPECIES[sp]
		mmi.visibility_range_end = cfg[0]
		mmi.visibility_range_end_margin = 60.0
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if cfg[1] else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		Game.prof_end("vb_mm")
		Game.prof_begin("vb_add")
		holder.add_child(mmi)
		Game.prof_end("vb_add")
		instance_total += count
	_chunks[key] = holder


func _process(_delta: float) -> void:
	Game.prof_begin("vegetation")
	var cam := get_viewport().get_camera_3d()
	if cam == null or data == null:
		Game.prof_end("vegetation")
		return
	var cp := cam.global_position
	# finished worker results -> build (a few per frame)
	var ready_keys: Array = []
	Game.prof_begin("veg_lock")
	_mutex.lock()
	Game.prof_end("veg_lock")
	for k in _results.keys():
		# never wait on a task that is still returning: a waiting main thread would pick up
		# other queued chunk jobs and stall the frame
		if _tasks.has(k) and not WorkerThreadPool.is_task_completed(_tasks[k]):
			continue
		ready_keys.append(k)
		if ready_keys.size() >= 1:
			break
	var payload: Dictionary = {}
	for k in ready_keys:
		payload[k] = _results[k]
		_results.erase(k)
	_mutex.unlock()
	for k in payload:
		Game.prof_begin("veg_wait")
		if _tasks.has(k):
			WorkerThreadPool.wait_for_task_completion(_tasks[k])
			_tasks.erase(k)
		Game.prof_end("veg_wait")
		Game.prof_begin("veg_build")
		_build(k, payload[k])
		Game.prof_end("veg_build")
	Game.prof_begin("veg_stream")
	if cp.distance_squared_to(_last_cam) > 400.0:
		_last_cam = cp
		_stream(cp)
	Game.prof_end("veg_stream")
	Game.prof_begin("veg_grass")
	_update_grass(cp)
	Game.prof_end("veg_grass")
	Game.prof_begin("veg_flush")
	_flush_grass()
	Game.prof_end("veg_flush")
	Game.prof_end("vegetation")


func _stream(cp: Vector3) -> void:
	for cz in COUNT:
		for cx in COUNT:
			var key := Vector2i(cx, cz)
			var center := Vector2(ORIGIN + (cx + 0.5) * CHUNK, ORIGIN + (cz + 0.5) * CHUNK)
			var d := center.distance_to(Vector2(cp.x, cp.z))
			if d < VEG_RADIUS:
				if not _chunks.has(key) and not _tasks.has(key):
					_tasks[key] = WorkerThreadPool.add_task(_generate.bind(key), false, "vegetation")
			elif d > VEG_RADIUS + 400.0 and _chunks.has(key):
				var n: Node = _chunks[key]
				if n != null:
					n.queue_free()
				_chunks.erase(key)


func prepare(p: Vector3) -> void:
	## synchronous generation around p (used at load/teleport so trees are present immediately)
	var key := Vector2i(int(floor((p.x - ORIGIN) / CHUNK)), int(floor((p.z - ORIGIN) / CHUNK)))
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var k := Vector2i(key.x + dx, key.y + dz)
			if k.x < 0 or k.y < 0 or k.x >= COUNT or k.y >= COUNT or _chunks.has(k) or _tasks.has(k):
				continue
			_generate(k)
			_mutex.lock()
			var out: Dictionary = _results.get(k, {})
			_results.erase(k)
			_mutex.unlock()
			_build(k, out)


# ------------------------------------------------------------------------------------------------
func _update_grass(cp: Vector3) -> void:
	var ck := Vector2i(int(floor(cp.x / GRASS_CELL)), int(floor(cp.z / GRASS_CELL)))
	var r := int(ceil(GRASS_RADIUS / GRASS_CELL))
	var wanted := {}
	for dz in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var k := Vector2i(ck.x + dx, ck.y + dz)
			if Vector2(dx, dz).length() * GRASS_CELL > GRASS_RADIUS + GRASS_CELL:
				continue
			wanted[k] = true
			if not _grass_cells.has(k) and not _grass_tasks.has(k):
				_grass_tasks[k] = WorkerThreadPool.add_task(_grass_job.bind(k), false, "grass")
	_grass_wanted = wanted
	for k in _grass_cells.keys():
		if not wanted.has(k):
			var n = _grass_cells[k]
			if n != null:
				(n as Node).queue_free()
			_grass_cells.erase(k)


var _grass_tasks: Dictionary = {}
var _grass_ready: Dictionary = {}
var _grass_wanted: Dictionary = {}


func _grass_job(k: Vector2i) -> void:
	var res := _grass_data(k)
	_mutex.lock()
	_grass_ready[k] = res
	_mutex.unlock()


func _flush_grass() -> void:
	## main thread: turn finished grass jobs into MultiMesh nodes (bounded per frame)
	_mutex.lock()
	var items := {}
	for k in _grass_ready.keys():
		if _grass_tasks.has(k) and not WorkerThreadPool.is_task_completed(_grass_tasks[k]):
			continue
		items[k] = _grass_ready[k]
		_grass_ready.erase(k)
		if items.size() >= 8:
			break
	_mutex.unlock()
	for k in items:
		if _grass_tasks.has(k):
			WorkerThreadPool.wait_for_task_completion(_grass_tasks[k])
			_grass_tasks.erase(k)
		if _grass_cells.has(k) or not _grass_wanted.has(k):
			continue
		_grass_cells[k] = _grass_node(items[k])


func _grass_data(k: Vector2i) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(k)
	var lists := {"grass_clump": PackedFloat32Array(), "wheat_clump": PackedFloat32Array(), "flowers": PackedFloat32Array()}
	for i in 256:
		var x := (k.x + rng.randf()) * GRASS_CELL
		var z := (k.y + rng.randf()) * GRASS_CELL
		if absf(x) > data.half - 5.0 or absf(z) > data.half - 5.0:
			continue
		var sp := data.splat_at(x, z)
		if sp.g > 0.45 or sp.a > 0.45:
			continue
		var h := data.height_at(x, z)
		if h > data.snow_line - 40.0 or h < 0.8:
			continue
		if _near_road(x, z, 2.5):
			continue
		var kind := "grass_clump"
		if sp.r > 0.55:
			kind = "wheat_clump"
		elif rng.randf() < 0.07:
			kind = "flowers"
		var s := rng.randf_range(0.55, 1.0)
		var b := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * 0.8, s))
		var buf: PackedFloat32Array = lists[kind]
		buf.append_array(PackedFloat32Array([b.x.x, b.y.x, b.z.x, x, b.x.y, b.y.y, b.z.y, h - 0.05, b.x.z, b.y.z, b.z.z, z]))
		lists[kind] = buf
	return lists


func _grass_aabb(buf: PackedFloat32Array, local: AABB) -> AABB:
	var lo := Vector3(INF, INF, INF)
	var hi := -lo
	for o in range(0, buf.size(), 12):
		var p := Vector3(buf[o + 3], buf[o + 7], buf[o + 11])
		lo = lo.min(p)
		hi = hi.max(p)
	var r := maxf(local.size.x, local.size.z) + 0.5
	return AABB(lo - Vector3(r, 0.5, r), hi - lo + Vector3(2.0 * r, local.end.y + 1.0, 2.0 * r))


func _grass_node(lists: Dictionary) -> Node3D:
	var holder := Node3D.new()
	add_child(holder)
	for kind in lists:
		var buf: PackedFloat32Array = lists[kind]
		if buf.is_empty() or _grass_meshes.get(kind) == null:
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.custom_aabb = _grass_aabb(buf, _mesh_aabb.get(kind, AABB()))
		mm.mesh = _grass_meshes[kind]
		mm.instance_count = buf.size() / 12
		mm.buffer = buf
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.visibility_range_end = GRASS_RADIUS + 10.0
		holder.add_child(mmi)
	return holder
