extends Node3D
## World dressing manager ("Dressing" under Main): vegetation, rocks, hedgerows, reeds and grass.
## Per 128 m terrain chunk (TerrainStreamer grid) placement is computed deterministically on the
## WorkerThreadPool (dressing_rules.gd) and committed on the main thread, under a time budget, as one
## RenderingServer MultiMesh instance per (chunk, layer, mesh) with visibility ranges + fade.
## Near trees cross-fade per tree (dithered, foliage.gdshader `lod`) to far stand-ins generated from the
## same Blender meshes at ~600 m, hedges at ~400 m; grass lives in a small ring around the camera
## (dressing_grass.gd); trunks, rocks and cacti near the player get pooled colliders (dressing_colliders.gd).
## Global wind/wetness/snow/night parameters are pushed to the shared materials once per second.

const PropLibrary := preload("res://scripts/world/prop_library.gd")
const Rules := preload("res://scripts/world/dressing_rules.gd")
const Mats := preload("res://scripts/world/dressing_materials.gd")
const GrassField := preload("res://scripts/world/dressing_grass.gd")
const ColliderPool := preload("res://scripts/world/dressing_colliders.gd")
const Nature := preload("res://scripts/world/dressing_nature_meshes.gd")

const CHUNK := 128.0
const HALF := 2048.0
const MAX_TASKS := 3
const COMMIT_BUDGET_USEC := 1200
const FREES_PER_FRAME := 12
## layer -> [visible from, visible to, begin fade margin, end fade margin, casts shadows]
## (LOD layers: the near model's chunk range ends and the far one's begins with the per-tree cross-fade, below)
const LAYERS := {
	"tree": [0.0, 0.0, 0.0, 0.0, true],
	"far": [0.0, 1500.0, 0.0, 120.0, false],
	"bush": [0.0, 420.0, 0.0, 50.0, true],
	"rock": [0.0, 300.0, 0.0, 40.0, false],
	"rockbig": [0.0, 950.0, 0.0, 80.0, true],
	"hedge": [0.0, 0.0, 0.0, 0.0, true],
	"hedgefar": [0.0, 1150.0, 0.0, 100.0, false],
	"reed": [0.0, 260.0, 0.0, 30.0, false],
}
## LOD layers -> [mode (1 near model fades out, 2 far stand-in fades in), cross-fade start, end] (metres from
## the camera to each tree, before the quality range scale)
const LOD := {
	"tree": [1.0, 570.0, 640.0],
	"far": [2.0, 570.0, 640.0],
	"hedge": [1.0, 370.0, 420.0],
	"hedgefar": [2.0, 370.0, 420.0],
}
const QUALITY_RANGE := [0.6, 0.8, 1.0, 1.2]
const QUALITY_DENSITY := [0.55, 0.8, 1.0, 1.0]
const QUALITY_GRASS := [50.0, 75.0, 100.0, 120.0]


class DChunk:
	extends RefCounted
	var key: Vector2i
	var state: int = 0              # 1 building, 2 built
	var rids: Array[RID] = []
	var colliders := PackedFloat32Array()
	var hulls := PackedFloat32Array()
	var instances: int = 0


var world: World
var ctx: Rules.Ctx
var chunks: Dictionary = {}
var grass: GrassField
var collider_pool: ColliderPool
var stats := {"chunks": 0, "instances": 0, "max_commit_ms": 0.0, "pending": 0}
var _queue: Array = []
var _mutex := Mutex.new()
var _tasks: Dictionary = {}          # task id -> key
var _started := false
var _q_applied: int = -1
var _start_wait: float = 0.0
var _want_t: float = 0.0
var _env_t: float = 0.0
var _range_scale: float = 1.0
var _cam := Vector3.ZERO
var _n_side: int = 32
var _free_queue: Array[Vector2i] = []
var _free_set: Dictionary = {}
var _perf_acc: int = 0
var _perf_max: int = 0
var _perf_frames: int = 0
var _perf_t: float = 0.0
var _perf_log := false
var _far_task: int = -1
var _far_out: Dictionary = {}       # written by the far-mesh task only, read after it completes
var _start_ms: int = 0


func _ready() -> void:
	if not (Game.world is World) or "--no-dressing" in OS.get_cmdline_user_args():
		set_process(false)
		return
	world = Game.world
	_n_side = int(world.data.half * 2.0 / CHUNK)
	# Photo mode briefly processes this group while paused so wind / wetness / snow follow its weather changes.
	add_to_group(Game.TIME_REACTIVE_GROUP)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--qa=drive") or arg == "--dressing-log":
			_perf_log = true
	Settings.changed.connect(_on_setting)


func _on_setting(key: String, _value: Variant) -> void:
	# Settings re-emits unchanged values (e.g. clicking the selected quality button).
	if key == "quality" and _started and _quality() != _q_applied:
		_restart()


func _quality() -> int:
	return clampi(int(Settings.get_value("quality", 2)), 0, 3)


# ------------------------------------------------------------------ start-up

func _try_start(delta: float) -> void:
	if _far_task >= 0:
		if not WorkerThreadPool.is_task_completed(_far_task):
			return
		WorkerThreadPool.wait_for_task_completion(_far_task)
		_far_task = -1
		for nm: String in _far_out:
			Rules.far_meshes[nm] = Rules.make_far(nm, _far_out[nm])
		_far_out.clear()
		ctx.far_src.clear()
		_finish_start()
		return
	_start_wait += delta
	var img: Image = world.noise_large.get_image() if world.noise_large else null
	if img == null and _start_wait < 4.0:
		return
	_start_ms = Time.get_ticks_msec()
	_q_applied = _quality()
	ctx = Rules.make_ctx(world.data, img, QUALITY_DENSITY[_quality()])
	_range_scale = QUALITY_RANGE[_quality()]
	if not ctx.far_src.is_empty():
		# far stand-ins are generated from the Blender trees off the main thread; streaming starts once they exist
		var src: Dictionary = ctx.far_src
		_far_task = WorkerThreadPool.add_task(func() -> void:
			for nm: String in src:
				_far_out[nm] = Nature.far_arrays(src[nm]), false, "dressing_far")
		return
	_finish_start()


func _finish_start() -> void:
	Mats.grass().set_shader_parameter("noise_large", world.noise_large)
	Mats.grass().set_shader_parameter("noise_detail", world.noise_detail)
	grass = GrassField.new()
	grass.name = "Grass"
	add_child(grass)
	grass.setup(ctx, get_world_3d().scenario, QUALITY_GRASS[_quality()])
	collider_pool = ColliderPool.new()
	collider_pool.name = "Colliders"
	collider_pool.chunks = chunks
	collider_pool.set_hulls(ctx.hulls)
	add_child(collider_pool)
	_apply_lod()
	_started = true
	_update_env()
	print("[dressing] ready in %d ms (%d exclusions, %d row chunks, field noise %s, %d far meshes)" % [Time.get_ticks_msec() - _start_ms, ctx.excl.size(),
		ctx.rows.size(), "ok" if ctx.nl_size > 0 else "missing", Rules.far_meshes.size()])


func _restart() -> void:
	for id: int in _tasks.keys():
		WorkerThreadPool.wait_for_task_completion(id)
	_tasks.clear()
	_queue.clear()
	_free_queue.clear()
	_free_set.clear()
	for key: Vector2i in chunks.keys():
		_free_chunk(key)
	collider_pool.reset()
	_q_applied = _quality()
	ctx.density = QUALITY_DENSITY[_quality()]
	_range_scale = QUALITY_RANGE[_quality()]
	_apply_lod()
	grass.clear()
	grass.radius = QUALITY_GRASS[_quality()]
	grass.setup(ctx, get_world_3d().scenario, grass.radius)
	_want_t = 0.0


## Cross-fade distances (foliage.gdshader `lod`) on the materials of the tree / hedge models and their far
## stand-ins: only dressing draws these meshes, and every instance of them uses the same distances.
func _apply_lod() -> void:
	for nm: String in Rules.INFO_NAMES:
		var near := "hedge" if nm == "Hedge" else ("tree" if nm.begins_with("Tree_") else "")
		if near == "":
			continue
		var lod: Array = LOD[near]
		var f0: float = lod[1] * _range_scale
		var f1: float = lod[2] * _range_scale
		Mats.set_mesh_lod(PropLibrary.mesh(nm), Vector3(1.0, f0, f1))
		var fm: Mesh = Rules.far_meshes.get(nm)
		if fm != null and fm != PropLibrary.mesh(nm):
			Mats.set_mesh_lod(fm, Vector3(2.0, f0, f1))


# ------------------------------------------------------------------ streaming

func _process(delta: float) -> void:
	if not _started:
		_try_start(delta)
		return
	var t0 := Time.get_ticks_usec()
	var cam := get_viewport().get_camera_3d()
	if cam != null:
		_cam = cam.global_position
	_want_t -= delta
	if _want_t <= 0.0:
		_want_t = 0.2
		_update_wants()
	_drain_free_queue()
	_commit()
	grass.update(_cam)
	_env_t -= delta
	if _env_t <= 0.0 or get_tree().paused:
		_env_t = 1.0
		_update_env()
	var us := Time.get_ticks_usec() - t0
	_perf_acc += us
	_perf_max = maxi(_perf_max, us)
	_perf_frames += 1
	if _perf_log:
		_perf_t += delta
		if _perf_t >= 5.0:
			_perf_t = 0.0
			print("[dressing] ", summary())


func _chunk_dist(key: Vector2i) -> float:
	var cx := -HALF + (key.x + 0.5) * CHUNK
	var cz := -HALF + (key.y + 0.5) * CHUNK
	return maxf(Vector2(cx - _cam.x, cz - _cam.z).length() - CHUNK * 0.5, 0.0)


func _update_wants() -> void:
	var far_end: float = LAYERS["far"][1] * _range_scale
	var ci := floori((_cam.x + HALF) / CHUNK)
	var cj := floori((_cam.z + HALF) / CHUNK)
	var r := int(ceil(far_end / CHUNK)) + 1
	var todo: Array = []
	for j in range(maxi(cj - r, 0), mini(cj + r, _n_side - 1) + 1):
		for i in range(maxi(ci - r, 0), mini(ci + r, _n_side - 1) + 1):
			var key := Vector2i(i, j)
			if chunks.has(key):
				continue
			var d := _chunk_dist(key)
			if d < far_end:
				todo.append([d, key])
	for key: Vector2i in chunks.keys():
		var c: DChunk = chunks[key]
		if c.state == 2 and _chunk_dist(key) > far_end + 250.0 and not _free_set.has(key):
			_free_set[key] = true
			_free_queue.append(key)
	stats["pending"] = todo.size()
	if todo.is_empty():
		return
	todo.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	for item: Array in todo:
		if _tasks.size() >= MAX_TASKS:
			break
		var key: Vector2i = item[1]
		var c := DChunk.new()
		c.key = key
		c.state = 1
		chunks[key] = c
		var id := WorkerThreadPool.add_task(_task.bind(key), false, "dressing_chunk")
		_tasks[id] = key


func _task(key: Vector2i) -> void:
	var res := Rules.build_chunk(ctx, key)
	_mutex.lock()
	_queue.append(res)
	_mutex.unlock()


func _drain_free_queue() -> void:
	var n := 0
	while not _free_queue.is_empty() and n < FREES_PER_FRAME:
		var key: Vector2i = _free_queue.pop_back()
		_free_set.erase(key)
		var c: DChunk = chunks.get(key)
		if c != null and c.state == 2 and _chunk_dist(key) > LAYERS["far"][1] * _range_scale + 200.0:
			_free_chunk(key)
		n += 1


func _commit() -> void:
	for id: int in _tasks.keys():
		if WorkerThreadPool.is_task_completed(id):
			WorkerThreadPool.wait_for_task_completion(id)
			_tasks.erase(id)
			_want_t = minf(_want_t, 0.02)
	var t0 := Time.get_ticks_usec()
	while Time.get_ticks_usec() - t0 < COMMIT_BUDGET_USEC:
		_mutex.lock()
		var res: Dictionary = _queue.pop_front() if not _queue.is_empty() else {}
		_mutex.unlock()
		if res.is_empty():
			break
		_apply(res)
	stats["max_commit_ms"] = maxf(stats["max_commit_ms"], (Time.get_ticks_usec() - t0) / 1000.0)


func _apply(res: Dictionary) -> void:
	var key: Vector2i = res["key"]
	var c: DChunk = chunks.get(key)
	if c == null or c.state != 1:
		return
	var org := Vector3(-HALF + key.x * CHUNK, 0.0, -HALF + key.y * CHUNK)
	var scenario := get_world_3d().scenario
	var groups: Dictionary = res["groups"]
	for gk: String in groups:
		var buf: PackedFloat32Array = groups[gk]
		var count := buf.size() / Rules.STRIDE
		if count == 0:
			continue
		var layer := gk.get_slice("|", 0)
		var nm := gk.get_slice("|", 1)
		var mesh: Mesh = Rules.far_meshes.get(nm) if layer.ends_with("far") else PropLibrary.mesh(nm)
		if mesh == null:
			continue
		var mm := RenderingServer.multimesh_create()
		RenderingServer.multimesh_allocate_data(mm, count, RenderingServer.MULTIMESH_TRANSFORM_3D, false, true)
		RenderingServer.multimesh_set_mesh(mm, mesh.get_rid())
		# instance origins' bounds plus the props' own size (crowns, up to ~12 m out and 30 m up)
		var ob: AABB = res["bounds"].get(gk, AABB(Vector3(0.0, -50.0, 0.0), Vector3(CHUNK, 450.0, CHUNK)))
		RenderingServer.multimesh_set_custom_aabb(mm, AABB(ob.position - Vector3(12.0, 4.0, 12.0), ob.size + Vector3(24.0, 34.0, 24.0)))
		RenderingServer.multimesh_set_buffer(mm, buf)
		var inst := RenderingServer.instance_create2(mm, scenario)
		RenderingServer.instance_set_transform(inst, Transform3D(Basis(), org))
		var lp: Array = LAYERS[layer]
		RenderingServer.instance_geometry_set_cast_shadows_setting(inst, RenderingServer.SHADOW_CASTING_SETTING_ON if lp[4] else RenderingServer.SHADOW_CASTING_SETTING_OFF)
		var begin: float = lp[0] * _range_scale
		var end: float = lp[1] * _range_scale
		if LOD.has(layer):
			# The chunk ranges only bound the per-tree cross-fade: Godot measures them to the custom AABB's centre,
			# which is up to `reach` metres from any tree in the group.
			var lod: Array = LOD[layer]
			var f0: float = lod[1] * _range_scale
			var f1: float = lod[2] * _range_scale
			var reach := (ob.size * 0.5 + Vector3(0.0, 13.0, 0.0)).length() + 2.0
			if lod[0] < 1.5:
				end = f1 + reach
			else:
				begin = maxf(f0 - reach, 0.0)
		RenderingServer.instance_geometry_set_visibility_range(inst, begin, end, lp[2], lp[3], RenderingServer.VISIBILITY_RANGE_FADE_SELF)
		c.rids.append(inst)
		c.rids.append(mm)
		c.instances += count
	c.colliders = res["colliders"]
	c.hulls = res.get("hulls", PackedFloat32Array())
	c.state = 2
	stats["chunks"] += 1
	stats["instances"] += c.instances


func _free_chunk(key: Vector2i) -> void:
	var c: DChunk = chunks[key]
	for rid in c.rids:
		RenderingServer.free_rid(rid)
	if c.state == 2:
		stats["chunks"] -= 1
		stats["instances"] -= c.instances
	chunks.erase(key)


# ------------------------------------------------------------------ look parameters

func _update_env() -> void:
	var wind := 0.9
	if Game.env != null and Game.env.has_method("get_wind_strength"):
		# Follows the environment's faded wind (0.05 fog .. 1.0 storm), so sway eases with weather transitions.
		wind = 0.85 + float(Game.env.call("get_wind_strength")) * 1.45
	elif Game.env != null and Game.env.has_method("get_weather"):
		var w := String(Game.env.get_weather())
		if w.contains("storm"):
			wind = 2.3
		elif w.contains("wind"):
			wind = 1.9
		elif w.contains("rain"):
			wind = 1.5
		elif w.contains("fog") or w.contains("cloud") or w.contains("overcast"):
			wind = 1.05
	Mats.set_param(&"wind_strength", wind)
	var tm := world.terrain_mat
	if tm != null:
		var wet: Variant = tm.get_shader_parameter("wetness")
		Mats.set_param(&"wetness", float(wet) if wet != null else 0.0)
		var snow: Variant = tm.get_shader_parameter("snow_cover")
		Mats.set_param(&"snow_cover", float(snow) if snow != null else 0.0)
	var hr := fposmod(Game.get_time_of_day(), 24.0)
	var night := 0.0
	if hr >= 12.0:
		night = smoothstep(18.6, 20.4, hr)
	else:
		night = 1.0 - smoothstep(5.2, 6.8, hr)
	Mats.set_param(&"night", night)


## Debug summary for QA logs.
func summary() -> String:
	var avg := float(_perf_acc) / maxi(_perf_frames, 1) / 1000.0
	var line := "chunks=%d inst=%d tasks=%d pending=%d grass_cells=%d grass_inst=%d colliders=%d/%d r=%.0f main_ms avg=%.3f max=%.2f (commit max %.2f) col_ms avg=%.3f max=%.2f" % [
		stats["chunks"], stats["instances"], _tasks.size(), stats["pending"], grass.cell_count() if grass else 0,
		grass.instances if grass else 0, collider_pool.active if collider_pool else 0, collider_pool.pool_size() if collider_pool else 0,
		collider_pool.cut_radius if collider_pool else 0.0, avg, _perf_max / 1000.0, stats["max_commit_ms"], collider_pool.avg_ms() if collider_pool else 0.0, collider_pool.max_ms() if collider_pool else 0.0]
	_perf_acc = 0
	_perf_max = 0
	_perf_frames = 0
	stats["max_commit_ms"] = 0.0
	return line


func _exit_tree() -> void:
	if _far_task >= 0:
		WorkerThreadPool.wait_for_task_completion(_far_task)
		_far_task = -1
	for id: int in _tasks.keys():
		WorkerThreadPool.wait_for_task_completion(id)
	_tasks.clear()
	for key: Vector2i in chunks.keys():
		_free_chunk(key)
