extends Node3D
## The 4 x 4 km open world. Loads baked data (tools/bake_world.gd), builds GPU terrain chunks,
## water, roads/bridges/tunnels/rails (threaded), and streams physics around the player.
## Exposes the world interface used by main.gd (spawn/teleport/nearest road/surface/region).

const RoadBuilderS := preload("res://scripts/world/road_builder.gd")
const CHUNK := 256.0
const ORIGIN := -2048.0
const COUNT := 16
const ROAD_VIS_RANGE := 1700.0

var data := WorldData.new()
var terrain: TerrainStreamer
var props: Node
var vegetation: Node
var road_materials: Dictionary = {}
var _runs: Dictionary = {}
var _road_keys: Array[Vector2i] = []
var _road_results: Array = []
var _road_task := -1
var _road_mutex := Mutex.new()
var _road_built: Dictionary = {}
var _road_bodies: Dictionary = {}
var _pending_instancing: Array[int] = []
var _collision_points: Array = []
var _pillar_mesh: Mesh
var _post_mesh: Mesh
var _route_line: MeshInstance3D
var route: Array = []


func _ready() -> void:
	var t0 := Time.get_ticks_msec()
	# The world is static geometry. Physics interpolation (on project-wide for the cars) makes every
	# MultiMeshInstance3D keep interpolated per-instance buffers: measured 5-10 ms per node added and
	# growing with the node count (tools/tests/mmi_cost_test.gd). Moving things opt back in.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	if not data.load_data():
		push_error("OpenWorld: baked world data missing; run tools/bake_world.gd")
		return
	terrain = TerrainStreamer.new()
	terrain.name = "Terrain"
	add_child(terrain)
	terrain.setup(data)
	_build_water()
	_build_borders()
	_build_horizon()
	_make_road_materials()
	_split_road_runs()
	_start_road_build()
	for script_path in ["res://scripts/world/prop_manager.gd", "res://scripts/world/vegetation_manager.gd"]:
		if ResourceLoader.exists(script_path):
			var n := (load(script_path) as GDScript).new() as Node
			add_child(n)
			n.call("setup", self)
			if script_path.ends_with("prop_manager.gd"):
				props = n
			else:
				vegetation = n
	var nav := (load("res://scripts/world/navigator.gd") as GDScript).new() as Node3D
	add_child(nav)
	nav.call("setup", data)
	print("[world] ready in %d ms" % (Time.get_ticks_msec() - t0))


# =================================================================================================
# water
func _water_material(shallow: Color, deep: Color, depth_scale: float, flow: Vector2, strength: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://assets/shaders/water.gdshader")
	m.set_shader_parameter("shallow_color", shallow)
	m.set_shader_parameter("deep_color", deep)
	m.set_shader_parameter("depth_scale", depth_scale)
	m.set_shader_parameter("flow", flow)
	m.set_shader_parameter("wave_strength", strength)
	for key in ["noise_a", "noise_b"]:
		var nt := NoiseTexture2D.new()
		nt.width = 256
		nt.height = 256
		nt.seamless = true
		nt.as_normal_map = true
		nt.bump_strength = 6.0
		var fn := FastNoiseLite.new()
		fn.seed = 31 if key == "noise_a" else 47
		fn.frequency = 0.03 if key == "noise_a" else 0.05
		nt.noise = fn
		m.set_shader_parameter(key, nt)
	return m


func _build_water() -> void:
	var sea := MeshInstance3D.new()
	sea.name = "Sea"
	var pm := PlaneMesh.new()
	pm.size = Vector2(24000.0, 24000.0)
	sea.mesh = pm
	sea.material_override = _water_material(Color(0.14, 0.5, 0.56), Color(0.02, 0.14, 0.24), 9.0, Vector2.ZERO, 0.7)
	sea.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(sea)
	var lake := MeshInstance3D.new()
	lake.name = "Lake"
	var lm := PlaneMesh.new()
	lm.size = data.lake_radii * 2.5
	lake.mesh = lm
	lake.position = Vector3(data.lake_center.x, data.lake_level, data.lake_center.y)
	lake.material_override = _water_material(Color(0.2, 0.45, 0.42), Color(0.04, 0.16, 0.2), 5.0, Vector2.ZERO, 0.35)
	lake.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(lake)
	# river ribbon
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var normals := PackedVector3Array()
	var idx := PackedInt32Array()
	var rv := data.river
	var dist := 0.0
	for i in rv.size():
		var p: Array = rv[i]
		var c := Vector3(float(p[0]), float(p[1]), float(p[2]))
		var pa: Array = rv[maxi(i - 1, 0)]
		var pb: Array = rv[mini(i + 1, rv.size() - 1)]
		var d := Vector3(float(pb[0]) - float(pa[0]), 0.0, float(pb[2]) - float(pa[2])).normalized()
		var right := d.cross(Vector3.UP).normalized()
		var w := float(p[3]) * 0.5 + 3.0
		if i > 0:
			dist += Vector3(float(pa[0]), 0, float(pa[2])).distance_to(Vector3(c.x, 0, c.z))
		verts.append(c - right * w + Vector3.UP * 0.05)
		verts.append(c + right * w + Vector3.UP * 0.05)
		uvs.append(Vector2(-w, dist))
		uvs.append(Vector2(w, dist))
		normals.append(Vector3.UP)
		normals.append(Vector3.UP)
		if i > 0:
			var b := (i - 1) * 2
			idx.append_array(PackedInt32Array([b, b + 2, b + 3, b, b + 3, b + 1]))
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = normals
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_INDEX] = idx
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var river := MeshInstance3D.new()
	river.name = "River"
	river.mesh = am
	river.material_override = _water_material(Color(0.22, 0.42, 0.36), Color(0.07, 0.2, 0.2), 2.5, Vector2(0.0, 1.0), 0.45)
	river.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(river)


func _build_borders() -> void:
	var lim := data.half - 6.0
	for k in 4:
		var body := StaticBody3D.new()
		body.name = "Border%d" % k
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(4.0, 2000.0, 4.0 * data.half) if k < 2 else Vector3(4.0 * data.half, 2000.0, 4.0)
		cs.shape = box
		body.add_child(cs)
		match k:
			0:
				body.position = Vector3(-lim - 2.0, 500.0, 0.0)
			1:
				body.position = Vector3(lim + 2.0, 500.0, 0.0)
			2:
				body.position = Vector3(0.0, 500.0, -lim - 2.0)
			3:
				body.position = Vector3(0.0, 500.0, lim + 2.0)
		add_child(body)


func _build_horizon() -> void:
	## Low-poly distant land beyond the playable square so the horizon is never empty.
	var fn := FastNoiseLite.new()
	fn.seed = 9
	fn.frequency = 0.0006
	fn.fractal_octaves = 4
	var size := 9000.0
	var cells := 72
	var step := size * 2.0 / cells
	var verts := PackedVector3Array()
	var colors := PackedColorArray()
	var idx := PackedInt32Array()
	var inner := data.half + 40.0
	for z in cells + 1:
		for x in cells + 1:
			var px := -size + x * step
			var pz := -size + z * step
			var ex := clampf(px, -data.half + 1.0, data.half - 1.0)
			var ez := clampf(pz, -data.half + 1.0, data.half - 1.0)
			var edge_h := data.height_at(ex, ez)
			var outside := maxf(absf(px) - data.half, absf(pz) - data.half)
			var far := 40.0 + fn.get_noise_2d(px, pz) * 90.0
			if pz < -data.half:
				far += 250.0 + fn.get_noise_2d(px * 2.0, pz * 2.0) * 300.0
			if px < -data.half:
				far = -30.0
			var t := smoothstep(0.0, 1800.0, outside)
			var h := lerpf(edge_h - 3.0, far, t)
			if outside < 60.0:
				h -= 25.0
			verts.append(Vector3(px, h, pz))
			var c := Color(0.36, 0.45, 0.26)
			if px > 600.0 and pz > -500.0:
				c = Color(0.62, 0.42, 0.28)
			if h > 380.0:
				c = c.lerp(Color(0.85, 0.87, 0.9), smoothstep(380.0, 600.0, h))
			colors.append(c)
	for z in cells:
		for x in cells:
			var cx := -size + (x + 0.5) * step
			var cz := -size + (z + 0.5) * step
			if absf(cx) < inner - step * 0.5 and absf(cz) < inner - step * 0.5:
				continue
			var a := z * (cells + 1) + x
			var b := a + 1
			var c2 := a + cells + 1
			var d := c2 + 1
			idx.append_array(PackedInt32Array([a, b, d, a, d, c2]))
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_COLOR] = colors
	arr[Mesh.ARRAY_INDEX] = idx
	var st := SurfaceTool.new()
	st.create_from_arrays(arr)
	st.generate_normals()
	var mesh := st.commit()
	var mi := MeshInstance3D.new()
	mi.name = "Horizon"
	mi.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 1.0
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


# =================================================================================================
# roads
func _make_road_materials() -> void:
	var shader := load("res://assets/shaders/road.gdshader") as Shader
	var na := TerrainStreamer._noise_tex(5, 0.05, 256)
	var nb := TerrainStreamer._noise_tex(6, 0.02, 256)
	for r in data.roads:
		var key := "%s_%s" % [r["class"], r["surface"]]
		if road_materials.has(key):
			continue
		var m := ShaderMaterial.new()
		m.shader = shader
		var surf := ["asphalt", "concrete", "gravel", "dirt", "sand"].find(r["surface"])
		m.set_shader_parameter("surface", maxi(surf, 0))
		var marking := 0
		match r["class"]:
			"highway":
				marking = 3
			"main":
				marking = 1
			"mountain":
				marking = 2
			"village":
				marking = 4
		if surf >= 2:
			marking = 0
		m.set_shader_parameter("marking", marking)
		m.set_shader_parameter("half_width", float(r["width"]) * 0.5)
		m.set_shader_parameter("lane_width", float(r["lane_width"]))
		m.set_shader_parameter("median", float(r["median"]))
		m.set_shader_parameter("shoulder", float(r["shoulder"]))
		m.set_shader_parameter("base_color", Color(0.17, 0.17, 0.18) if surf == 0 else (Color(0.52, 0.52, 0.5) if surf == 1 else Color(1, 1, 1)))
		m.set_shader_parameter("noise_a", na)
		m.set_shader_parameter("noise_b", nb)
		road_materials[key] = m
	var concrete := StandardMaterial3D.new()
	concrete.albedo_color = Color(0.6, 0.59, 0.56)
	concrete.roughness = 0.85
	concrete.cull_mode = BaseMaterial3D.CULL_DISABLED
	concrete.uv1_triplanar = true
	concrete.albedo_texture = na
	road_materials["bridge"] = concrete
	var tunnel := StandardMaterial3D.new()
	tunnel.albedo_color = Color(0.5, 0.49, 0.46)
	tunnel.roughness = 0.75
	tunnel.cull_mode = BaseMaterial3D.CULL_DISABLED
	road_materials["tunnel"] = tunnel
	road_materials["portal"] = concrete
	var light := StandardMaterial3D.new()
	light.albedo_color = Color(1.0, 0.92, 0.75)
	light.emission_enabled = true
	light.emission = Color(1.0, 0.85, 0.6)
	light.emission_energy_multiplier = 4.0
	light.cull_mode = BaseMaterial3D.CULL_DISABLED
	road_materials["tunnel_light"] = light
	var rail := StandardMaterial3D.new()
	rail.albedo_color = Color(0.7, 0.72, 0.74)
	rail.metallic = 0.85
	rail.roughness = 0.35
	rail.cull_mode = BaseMaterial3D.CULL_DISABLED
	road_materials["rail"] = rail
	var pillar := BoxMesh.new()
	pillar.size = Vector3(1.0, 1.0, 1.0)
	_pillar_mesh = pillar
	var post := BoxMesh.new()
	post.size = Vector3(0.12, 0.85, 0.16)
	post.material = rail
	_post_mesh = post


func _chunk_of(x: float, z: float) -> Vector2i:
	return Vector2i(clampi(int(floor((x - ORIGIN) / CHUNK)), 0, COUNT - 1), clampi(int(floor((z - ORIGIN) / CHUNK)), 0, COUNT - 1))


func _split_road_runs() -> void:
	for ri in data.roads.size():
		var r: Dictionary = data.roads[ri]
		var xs: PackedFloat32Array = r["x"]
		var zs: PackedFloat32Array = r["z"]
		var n := xs.size()
		var closed: bool = r["closed"]
		var start := 0
		var cur := _chunk_of(xs[0], zs[0])
		for i in range(1, n):
			var k := _chunk_of(xs[i], zs[i])
			if k != cur:
				_add_run(cur, ri, start - 1, i)
				start = i
				cur = k
		_add_run(cur, ri, start - 1, n if closed else n - 1)
	_road_keys.clear()
	for k in _runs.keys():
		_road_keys.append(k)
	_road_results.resize(_road_keys.size())


func _add_run(key: Vector2i, ri: int, a: int, b: int) -> void:
	if not _runs.has(key):
		_runs[key] = []
	(_runs[key] as Array).append({"road": ri, "a": a, "b": b})


func _exit_tree() -> void:
	if _road_task >= 0:
		WorkerThreadPool.wait_for_group_task_completion(_road_task)
		_road_task = -1


func _start_road_build() -> void:
	_road_task = WorkerThreadPool.add_group_task(_build_road_chunk, _road_keys.size(), -1, false, "road meshes")


func _build_road_chunk(index: int) -> void:
	var key: Vector2i = _road_keys[index]
	var res := RoadBuilderS.build(data, _runs[key])
	_road_mutex.lock()
	_road_results[index] = res
	_pending_instancing.append(index)
	_road_mutex.unlock()


func _instance_road_chunk(index: int) -> void:
	var key: Vector2i = _road_keys[index]
	if _road_built.has(key):
		return
	var res: Dictionary = _road_results[index]
	if res == null or res.is_empty():
		return
	var mesh := ArrayMesh.new()
	var meshes: Dictionary = res["meshes"]
	var surf := 0
	for mk in meshes.keys():
		var md = meshes[mk]
		if md.verts.size() == 0:
			continue
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, md.to_arrays())
		mesh.surface_set_material(surf, road_materials.get(mk, road_materials.get("bridge")))
		surf += 1
	var holder := Node3D.new()
	holder.name = "Roads_%d_%d" % [key.x, key.y]
	add_child(holder)
	if surf > 0:
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.visibility_range_end = ROAD_VIS_RANGE
		mi.visibility_range_end_margin = 60.0
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		holder.add_child(mi)
	# pillars and rail posts
	var pillars: Array = res["pillars"]
	if not pillars.is_empty():
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = _pillar_mesh
		var xforms: Array[Transform3D] = []
		for pl in pillars:
			var p: Vector3 = pl["p"]
			var fwd: Vector3 = pl["fwd"]
			var flat := Vector3(fwd.x, 0, fwd.z).normalized()
			var right := flat.cross(Vector3.UP).normalized()
			var lats := [0.0] if float(pl["half"]) < 6.0 else [-float(pl["half"]) * 0.45, float(pl["half"]) * 0.45]
			for lat in lats:
				var q: Vector3 = p + right * lat
				var ground := data.height_at(q.x, q.z) - 1.5
				var top := q.y - float(pl["deck"])
				var h := top - ground
				if h < 1.5:
					continue
				var b := Basis(right * 2.2, Vector3.UP * h, flat * 1.4)
				xforms.append(Transform3D(b, Vector3(q.x, ground + h * 0.5, q.z)))
		mm.instance_count = xforms.size()
		for i in xforms.size():
			mm.set_instance_transform(i, xforms[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = road_materials["bridge"]
		mmi.visibility_range_end = ROAD_VIS_RANGE
		holder.add_child(mmi)
	var posts: Array = res["posts"]
	if not posts.is_empty():
		var mm2 := MultiMesh.new()
		mm2.transform_format = MultiMesh.TRANSFORM_3D
		mm2.mesh = _post_mesh
		mm2.instance_count = posts.size()
		for i in posts.size():
			var pp: Dictionary = posts[i]
			var fwd: Vector3 = pp["fwd"]
			var flat := Vector3(fwd.x, 0, fwd.z).normalized()
			mm2.set_instance_transform(i, Transform3D(Basis.looking_at(flat, Vector3.UP), (pp["p"] as Vector3) + Vector3.UP * 0.42))
		var mmi2 := MultiMeshInstance3D.new()
		mmi2.multimesh = mm2
		mmi2.visibility_range_end = 450.0
		holder.add_child(mmi2)
	for portal in res["portals"]:
		var parr := RoadBuilderS.portal_arrays(portal)
		var pmesh := ArrayMesh.new()
		pmesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, parr)
		var pmi := MeshInstance3D.new()
		pmi.mesh = pmesh
		pmi.material_override = road_materials["portal"]
		holder.add_child(pmi)
	_road_built[key] = holder


func _ensure_road_collision(key: Vector2i) -> void:
	if _road_bodies.has(key):
		return
	var index := _road_keys.find(key)
	if index < 0:
		_road_bodies[key] = []
		return
	var res = _road_results[index]
	if res == null:
		res = RoadBuilderS.build(data, _runs[key])
		_road_results[index] = res
	var bodies: Array = []
	var col: Dictionary = res["collision"]
	for sk in col.keys():
		var faces: PackedVector3Array = col[sk]
		if faces.size() < 3:
			continue
		var shape := ConcavePolygonShape3D.new()
		shape.backface_collision = true
		shape.set_faces(faces)
		var cs := CollisionShape3D.new()
		cs.shape = shape
		var body := StaticBody3D.new()
		body.collision_layer = 1
		body.collision_mask = 0
		var sid := Surfaces.ASPHALT
		match String(sk):
			"concrete", "rail":
				sid = Surfaces.CONCRETE
			"gravel":
				sid = Surfaces.GRAVEL
			"dirt":
				sid = Surfaces.DIRT
			"sand":
				sid = Surfaces.SAND
		body.set_meta("surface", sid)
		body.set_meta("road", true)
		body.add_child(cs)
		add_child(body)
		bodies.append(body)
	_road_bodies[key] = bodies


func _update_road_collision(points: Array) -> void:
	var wanted := {}
	for p in points:
		var k := _chunk_of(p.x, p.z)
		for dz in range(-1, 2):
			for dx in range(-1, 2):
				var kk := Vector2i(k.x + dx, k.y + dz)
				if kk.x >= 0 and kk.y >= 0 and kk.x < COUNT and kk.y < COUNT:
					wanted[kk] = true
	var built := 0
	for kk in wanted:
		if not _road_bodies.has(kk):
			if built >= 1:
				continue
			built += 1
		_ensure_road_collision(kk)
	for kk in _road_bodies.keys():
		if not wanted.has(kk):
			for b in _road_bodies[kk]:
				(b as Node).queue_free()
			_road_bodies.erase(kk)


# =================================================================================================
func _process(_delta: float) -> void:
	Game.prof_begin("world_process")
	if terrain == null:
		Game.prof_end("world_process")
		return
	var cam := get_viewport().get_camera_3d()
	var cam_pos := cam.global_position if cam != null else Vector3.ZERO
	terrain.update_lod(cam_pos)
	# road meshes finishing on worker threads -> instance a few per frame
	_road_mutex.lock()
	var todo: Array[int] = []
	for i in mini(_pending_instancing.size(), 6):
		todo.append(_pending_instancing.pop_front())
	_road_mutex.unlock()
	for i in todo:
		_instance_road_chunk(i)
	if _road_task >= 0 and WorkerThreadPool.is_group_task_completed(_road_task):
		WorkerThreadPool.wait_for_group_task_completion(_road_task)
		_road_task = -1
	Game.prof_end("world_process")


func _physics_process(_delta: float) -> void:
	Game.prof_begin("world_physics")
	if terrain == null:
		Game.prof_end("world_physics")
		return
	_collision_points.clear()
	if Game.player_car != null and is_instance_valid(Game.player_car):
		_collision_points.append(Game.player_car.global_position)
		_collision_points.append(Game.player_car.global_position + Game.player_car.linear_velocity * 1.6)
	if Game.traffic != null and Game.traffic.has_method("physics_points"):
		_collision_points.append_array(Game.traffic.call("physics_points"))
	if _collision_points.is_empty():
		var cam := get_viewport().get_camera_3d()
		if cam != null:
			_collision_points.append(cam.global_position)
	terrain.update_collision(_collision_points)
	_update_road_collision(_collision_points)
	Game.prof_end("world_physics")


func prepare_area(p: Vector3) -> void:
	## Synchronously makes collision and road meshes available around p (teleports, loads).
	terrain.force_collision(p)
	var k0 := _chunk_of(p.x, p.z)
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var kk := Vector2i(k0.x + dx, k0.y + dz)
			if kk.x >= 0 and kk.y >= 0 and kk.x < COUNT and kk.y < COUNT:
				_ensure_road_collision(kk)
	if vegetation != null:
		vegetation.call("prepare", p)
	var k := _chunk_of(p.x, p.z)
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var kk := Vector2i(k.x + dx, k.y + dz)
			var idx := _road_keys.find(kk)
			if idx >= 0:
				if _road_results[idx] == null:
					_road_results[idx] = RoadBuilderS.build(data, _runs[kk])
				_instance_road_chunk(idx)


# =================================================================================================
# world interface
func spawn_transform() -> Transform3D:
	var t: Array = data.meta["teleports"]["festival"]
	var p := _past_start_gate(t)
	prepare_area(p)
	return nearest_road_transform(p, Vector3(float(t[2]), 0.0, float(t[3])))


func _past_start_gate(t: Array) -> Vector3:
	## the scenic-loop time trial starts at the festival: spawn 40 m past its gate, not inside a post
	var h := Vector3(float(t[2]), 0.0, float(t[3])).normalized()
	return Vector3(float(t[0]), 0.0, float(t[1])) + h * 40.0


func teleport_targets() -> Dictionary:
	var out := {}
	var tp: Dictionary = data.meta["teleports"]
	for k in tp.keys():
		var t: Array = tp[k]
		var p := _past_start_gate(t) if k in ["festival", "loop_start"] else Vector3(float(t[0]), 0.0, float(t[1]))
		out[k] = nearest_road_transform(p, Vector3(float(t[2]), 0.0, float(t[3])))
	return out


func nearest_road_transform(pos: Vector3, heading: Vector3, lane_side: float = 1.0) -> Transform3D:
	var nr := data.nearest_road(pos.x, pos.z, 40)
	if nr.is_empty():
		var h := data.height_at(pos.x, pos.z)
		return Transform3D(Basis.IDENTITY, Vector3(pos.x, h + 1.0, pos.z))
	var ri: int = nr["road"]
	var i: int = nr["i"]
	var r: Dictionary = data.roads[ri]
	var p := data.road_point(ri, i)
	var d := data.road_dir(ri, i)
	var flat := Vector3(d.x, 0, d.z).normalized()
	var hflat := Vector3(heading.x, 0, heading.z)
	if hflat.length() > 0.1 and flat.dot(hflat) < 0.0:
		flat = -flat
	var right := flat.cross(Vector3.UP).normalized()
	var lanes: int = r["lanes"]
	var off := 0.0
	if lanes >= 2:
		off = float(r["lane_width"]) * 0.5 + float(r["median"]) * 0.5
		if lanes >= 4:
			off += float(r["lane_width"])
	var q := p + right * off * lane_side + Vector3.UP * 0.55
	return Transform3D(Basis.looking_at(flat, Vector3.UP), q)


func surface_at(x: float, z: float) -> int:
	return data.surface_at(x, z)


func region_at(x: float, z: float) -> String:
	return data.region_at(x, z)


func height_at(x: float, z: float) -> float:
	return data.height_at(x, z)


func scenic_loop_index() -> int:
	for i in data.roads.size():
		if data.roads[i]["scenic"]:
			return i
	return 0


func create_autopilot(car: CarController) -> Node:
	var ap := (load("res://scripts/world/autopilot.gd") as GDScript).new() as Node
	ap.set("world", self)
	ap.set("car", car)
	var nr := data.nearest_road(car.global_position.x, car.global_position.z, 20)
	ap.set("road_index", int(nr["road"]) if not nr.is_empty() else scenic_loop_index())
	if not nr.is_empty():
		var d := data.road_dir(int(nr["road"]), int(nr["i"]))
		ap.set("direction", 1 if d.dot(-car.global_transform.basis.z) >= 0.0 else -1)
	add_child(ap)
	return ap


func set_route_target(p: Vector3) -> void:
	if has_node("Navigator"):
		get_node("Navigator").call("set_target", p)


func qa_shot_list(set_name: String) -> Array:
	var tp: Dictionary = data.meta["teleports"]
	var shots: Array = []
	match set_name:
		"world":
			var names := ["festival", "farmland", "highlands", "pass", "canyon", "desert", "coast", "lake", "highway", "village", "summit", "lighthouse"]
			var times := [10.0, 11.0, 13.0, 15.0, 17.0, 12.0, 18.2, 9.0, 14.0, 16.0, 12.5, 19.0]
			for k in names.size():
				shots.append({"file": "world_%02d_%s.png" % [k, names[k]], "teleport": names[k], "time": times[k], "weather": "clear", "cam": 0, "wait": 70})
		"traffic":
			for k in ["highway", "festival", "village", "farmland", "desert"]:
				shots.append({"file": "traffic_%s.png" % k, "teleport": k, "time": 13.0, "weather": "clear", "cam": 0,
					"wait": 600, "autopilot": true, "ap_speed": 80.0, "ap_lane": 1.75 if k != "highway" else 5.4})
		"traffic_view":
			var vs := [["highway", Vector3(-900, 45, 1060), Vector3(-700, 20, 1080)], ["village", Vector3(-300, 40, 470), Vector3(-420, 25, 560)],
				["farmland", Vector3(-150, 35, 300), Vector3(-330, 20, 400)]]
			for k in vs.size():
				var v: Array = vs[k]
				shots.append({"file": "traffic_view_%d.png" % k, "teleport": v[0], "time": 13.0, "weather": "clear", "cam": 0, "wait": 420,
					"free_cam": [v[1], v[2]]})
		"aerial":
			var views := [
				[Vector3(-640, 160, 820), Vector3(-200, 30, 200)], [Vector3(300, 420, -300), Vector3(700, 250, -900)],
				[Vector3(1300, 300, 300), Vector3(1650, 90, 900)], [Vector3(-1200, 160, 1300), Vector3(-1600, 0, 700)],
				[Vector3(1500, 700, -600), Vector3(1100, 450, -1200)], [Vector3(-500, 220, 1500), Vector3(400, 30, 900)],
			]
			for k in views.size():
				var v: Array = views[k]
				shots.append({"file": "aerial_%02d.png" % k, "teleport": "festival", "time": 15.5, "weather": "clear", "cam": 0, "wait": 50,
					"free_cam": [v[0], v[1]]})
	return shots
