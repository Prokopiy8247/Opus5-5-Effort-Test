extends Node
## Grass tufts and wild flowers in small 24 m cells around the camera (built on the WorkerThreadPool,
## committed as RenderingServer MultiMeshes). The grass shader shrinks tufts toward fade_end, so the
## ring edge never pops.

const Rules := preload("res://scripts/world/dressing_rules.gd")
const PropLibrary := preload("res://scripts/world/prop_library.gd")
const Mats := preload("res://scripts/world/dressing_materials.gd")

const MAX_TASKS := 3

var ctx: Rules.Ctx
var radius: float = 100.0
var _cells: Dictionary = {}          # Vector2i -> Array[RID] (empty while building)
var _tasks: Dictionary = {}          # task id -> true
var _queue: Array = []
var _mutex := Mutex.new()
var _scenario: RID
var _last_cell := Vector2i(1 << 20, 0)
var _last_scan: int = 0
var _counts: Dictionary = {}
var instances: int = 0


func setup(context: Rules.Ctx, scenario: RID, ring_radius: float) -> void:
	ctx = context
	_scenario = scenario
	radius = ring_radius
	Mats.grass().set_shader_parameter("fade_start", radius * 0.62)
	Mats.grass().set_shader_parameter("fade_end", radius - 4.0)


func update(cam: Vector3) -> void:
	if ctx == null:
		return
	_release_tasks()
	var cs := Rules.GRASS_CELL
	var cc := Vector2i(floori(cam.x / cs), floori(cam.z / cs))
	var now := Time.get_ticks_msec()
	if cc != _last_cell or (_tasks.size() < MAX_TASKS and now - _last_scan > 200):
		_last_cell = cc
		_last_scan = now
		var r := int(ceil(radius / cs)) + 1
		var todo: Array = []
		for dz in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var k := cc + Vector2i(dx, dz)
				if _cells.has(k):
					continue
				var d := _cell_dist(k, cam)
				if d < radius:
					todo.append([d, k])
		todo.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
		for item: Array in todo:
			if _tasks.size() >= MAX_TASKS:
				break
			var key: Vector2i = item[1]
			_cells[key] = []
			var id := WorkerThreadPool.add_task(_task.bind(key), false, "dressing_grass")
			_tasks[id] = true
		for k: Vector2i in _cells.keys():
			if _cell_dist(k, cam) > radius + 30.0 and not (_cells[k] as Array).is_empty():
				_free_cell(k)
	_commit()


func _cell_dist(k: Vector2i, cam: Vector3) -> float:
	var cs := Rules.GRASS_CELL
	var cx := clampf(cam.x, k.x * cs, (k.x + 1) * cs)
	var cz := clampf(cam.z, k.y * cs, (k.y + 1) * cs)
	return Vector2(cam.x - cx, cam.z - cz).length()


func _task(key: Vector2i) -> void:
	var res := Rules.build_grass(ctx, key)
	_mutex.lock()
	_queue.append(res)
	_mutex.unlock()


func _release_tasks() -> void:
	for id: int in _tasks.keys():
		if WorkerThreadPool.is_task_completed(id):
			WorkerThreadPool.wait_for_task_completion(id)
			_tasks.erase(id)


func _commit() -> void:
	_mutex.lock()
	var batch := _queue.slice(0, 2)
	_queue = _queue.slice(2)
	_mutex.unlock()
	for res: Dictionary in batch:
		var key: Vector2i = res["cell"]
		if not _cells.has(key):
			continue
		var rids: Array = []
		var added := 0
		var groups: Dictionary = res["groups"]
		for gk: String in groups:
			var buf: PackedFloat32Array = groups[gk]
			var count := buf.size() / Rules.STRIDE
			if count == 0:
				continue
			var mesh := PropLibrary.mesh(gk.get_slice("|", 1))
			var mm := RenderingServer.multimesh_create()
			RenderingServer.multimesh_allocate_data(mm, count, RenderingServer.MULTIMESH_TRANSFORM_3D, false, true)
			RenderingServer.multimesh_set_mesh(mm, mesh.get_rid())
			RenderingServer.multimesh_set_buffer(mm, buf)
			var inst := RenderingServer.instance_create2(mm, _scenario)
			RenderingServer.instance_set_transform(inst, Transform3D(Basis(), Vector3(key.x * Rules.GRASS_CELL, 0.0, key.y * Rules.GRASS_CELL)))
			RenderingServer.instance_geometry_set_cast_shadows_setting(inst, RenderingServer.SHADOW_CASTING_SETTING_OFF)
			RenderingServer.instance_geometry_set_visibility_range(inst, 0.0, radius + 12.0, 0.0, 0.0, RenderingServer.VISIBILITY_RANGE_FADE_DISABLED)
			rids.append(inst)
			rids.append(mm)
			instances += count
			added += count
		if rids.is_empty():
			rids.append(RID())
		_cells[key] = rids
		_counts[key] = added


func _free_cell(k: Vector2i) -> void:
	for rid: RID in _cells[k]:
		if rid.is_valid():
			RenderingServer.free_rid(rid)
	instances -= int(_counts.get(k, 0))
	_counts.erase(k)
	_cells.erase(k)


func clear() -> void:
	for id: int in _tasks.keys():
		WorkerThreadPool.wait_for_task_completion(id)
	_tasks.clear()
	_queue.clear()
	for k: Vector2i in _cells.keys():
		_free_cell(k)
	_last_cell = Vector2i(1 << 20, 0)


func cell_count() -> int:
	return _cells.size()


func _exit_tree() -> void:
	clear()
