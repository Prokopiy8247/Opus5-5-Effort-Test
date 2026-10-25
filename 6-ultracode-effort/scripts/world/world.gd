class_name World
extends Node3D
## The open world: loads the baked data and owns terrain streaming, roads, water, far horizon terrain,
## dressing and settlements. Implements the world query API used through Game.world.

signal loaded()

var data: WorldData
var terrain: TerrainStreamer
var roads: RoadBuilder
var dressing: Node3D
var noise_detail: NoiseTexture2D
var noise_large: NoiseTexture2D
var terrain_mat: ShaderMaterial
var water_mat: ShaderMaterial
var road_dist_tex: ImageTexture
var current_region: int = -1
var _region_timer: float = 0.0
var _far_task: int = -1
var _far_result: Dictionary = {}
var _teleports: Array = []
var extra_physics_points: Array[Vector3] = []


func build() -> bool:
	data = WorldData.new()
	if not data.load_all():
		return false
	_make_noise()
	terrain_mat = ShaderMaterial.new()
	terrain_mat.shader = load("res://assets/shaders/terrain.gdshader")
	terrain_mat.set_shader_parameter("noise_large", noise_large)
	terrain_mat.set_shader_parameter("noise_detail", noise_detail)
	var rimg := Image.create_from_data(data.map_n, data.map_n, false, Image.FORMAT_L8, data.road_dist)
	road_dist_tex = ImageTexture.create_from_image(rimg)
	terrain_mat.set_shader_parameter("road_dist_tex", road_dist_tex)
	terrain_mat.set_shader_parameter("map_half", data.half)
	terrain = TerrainStreamer.new()
	terrain.name = "Terrain"
	add_child(terrain)
	terrain.setup(data, terrain_mat)
	roads = RoadBuilder.new()
	roads.name = "Roads"
	add_child(roads)
	roads.setup(data, noise_detail, noise_large)
	_build_water()
	_build_boundary()
	_far_task = WorkerThreadPool.add_task(_build_far_terrain, false, "far_terrain")
	CarController.terrain_surface_lookup = surface_at
	_build_teleports()
	return true


func _make_noise() -> void:
	var fn := FastNoiseLite.new()
	fn.seed = 11
	fn.noise_type = FastNoiseLite.TYPE_SIMPLEX
	fn.fractal_type = FastNoiseLite.FRACTAL_FBM
	fn.fractal_octaves = 5
	fn.frequency = 0.012
	noise_detail = NoiseTexture2D.new()
	noise_detail.width = 512
	noise_detail.height = 512
	noise_detail.seamless = true
	noise_detail.generate_mipmaps = true
	noise_detail.noise = fn
	var fl := FastNoiseLite.new()
	fl.seed = 12
	fl.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	fl.fractal_type = FastNoiseLite.FRACTAL_FBM
	fl.fractal_octaves = 4
	fl.frequency = 0.006
	noise_large = NoiseTexture2D.new()
	noise_large.width = 512
	noise_large.height = 512
	noise_large.seamless = true
	noise_large.generate_mipmaps = true
	noise_large.noise = fl


func _water_material() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://assets/shaders/water.gdshader")
	for k: String in ["normal_a", "normal_b"]:
		var nt := NoiseTexture2D.new()
		nt.width = 256
		nt.height = 256
		nt.seamless = true
		nt.as_normal_map = true
		nt.bump_strength = 6.0
		nt.generate_mipmaps = true
		var fn := FastNoiseLite.new()
		fn.seed = 30 + k.length()
		fn.frequency = 0.03 if k == "normal_a" else 0.05
		fn.fractal_octaves = 3
		nt.noise = fn
		m.set_shader_parameter(k, nt)
	return m


func _build_water() -> void:
	water_mat = _water_material()
	# Sea: large plane (sea level 0).
	var sea := MeshInstance3D.new()
	sea.name = "Sea"
	var pm := PlaneMesh.new()
	pm.size = Vector2(24000, 24000)
	pm.subdivide_width = 8
	pm.subdivide_depth = 8
	sea.mesh = pm
	sea.material_override = water_mat
	sea.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sea.position = Vector3(0, WorldLayout.SEA_LEVEL, 2000)
	add_child(sea)
	# River ribbon along the same centreline and water levels the terrain channel was carved from.
	var dense := PackedVector3Array()
	var rp := data.gen._river_pts
	var ry := data.gen._river_y
	for i in rp.size() - 1:
		var steps := maxi(int(rp[i].distance_to(rp[i + 1]) / 6.0), 1)
		for s in steps:
			var t := float(s) / steps
			var q := rp[i].lerp(rp[i + 1], t)
			dense.append(Vector3(q.x, lerpf(ry[i], ry[i + 1], t), q.y))
	dense.append(Vector3(rp[rp.size() - 1].x, ry[ry.size() - 1], rp[rp.size() - 1].y))
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	var along := 0.0
	for i in dense.size():
		var a := dense[maxi(i - 1, 0)]
		var b := dense[mini(i + 1, dense.size() - 1)]
		var t := Vector3(b.x - a.x, 0, b.z - a.z).normalized()
		var rt := Vector3(-t.z, 0, t.x)
		var p := dense[i]
		if i > 0:
			along += dense[i].distance_to(dense[i - 1])
		var w := 13.0
		verts.append(p - rt * w + Vector3(0, 0.0, 0))
		verts.append(p + rt * w + Vector3(0, 0.0, 0))
		uvs.append(Vector2(0, along))
		uvs.append(Vector2(1, along))
		if i > 0:
			var k := i * 2
			idx.append_array([k - 2, k, k - 1, k - 1, k, k + 1])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	var norms := PackedVector3Array()
	norms.resize(verts.size())
	norms.fill(Vector3.UP)
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = idx
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var river := MeshInstance3D.new()
	river.name = "River"
	river.mesh = am
	var rm: ShaderMaterial = water_mat.duplicate()
	rm.set_shader_parameter("flow", Vector2(0.0, 0.08))
	rm.set_shader_parameter("shallow_color", Color(0.16, 0.36, 0.3))
	river.material_override = rm
	river.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(river)
	# Lakes.
	for lk: Dictionary in data.lake_list():
		var lake := MeshInstance3D.new()
		lake.name = "Lake"
		var cm := CylinderMesh.new()
		cm.top_radius = float(lk["radius"]) * 1.35
		cm.bottom_radius = cm.top_radius
		cm.height = 0.01
		cm.radial_segments = 64
		lake.mesh = cm
		var lm: ShaderMaterial = water_mat.duplicate()
		lm.set_shader_parameter("flow", Vector2(0.004, 0.003))
		lake.material_override = lm
		lake.position = Vector3(lk["pos"][0], float(lk["level"]), lk["pos"][1])
		lake.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(lake)


func _build_boundary() -> void:
	var body := StaticBody3D.new()
	body.name = "Boundary"
	body.collision_layer = 1
	var lim := WorldLayout.PLAY_HALF + 20.0
	for d: Vector3 in [Vector3.RIGHT, Vector3.LEFT, Vector3.FORWARD, Vector3.BACK]:
		var cs := CollisionShape3D.new()
		var ws := WorldBoundaryShape3D.new()
		ws.plane = Plane(-d, -lim)
		cs.shape = ws
		body.add_child(cs)
	add_child(body)


func _build_far_terrain() -> void:
	# Horizon ring outside the detailed map, from the natural height function (worker thread). Its first band
	# (64 m) is a seam strip whose inner edge follows the detailed map edge (never above it at any LOD), so no
	# line of sight can pass between the two terrains.
	var gen := data.gen
	var step := 64.0
	var ext := 8000.0
	var half := data.half
	var inner := half + step
	var cnt := int(ext * 2.0 / step) + 1
	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	verts.resize(cnt * cnt)
	cols.resize(cnt * cnt)
	for j in cnt:
		for i in cnt:
			var x := -ext + i * step
			var z := -ext + j * step
			var used := absf(x) > inner - 1.0 or absf(z) > inner - 1.0
			verts[j * cnt + i] = Vector3(x, gen.natural_height(x, z) if used else -40.0, z)
			cols[j * cnt + i] = gen.region_weights(x, z) if used else Color(1, 0, 0, 0)
	var idx := PackedInt32Array()
	for j in cnt - 1:
		for i in cnt - 1:
			var x0 := -ext + i * step
			var z0 := -ext + j * step
			if x0 + step > -inner + 1.0 and x0 < inner - 1.0 and z0 + step > -inner + 1.0 and z0 < inner - 1.0:
				continue
			var a := j * cnt + i
			idx.append_array([a, a + 1, a + cnt, a + 1, a + cnt + 1, a + cnt])
	var node := func(x: float, z: float) -> int:
		return int(round((z + ext) / step)) * cnt + int(round((x + ext) / step))
	# Seam strips: sides 0 east (x = +half), 1 west, 2 south (z = +half), 3 north; rows run along u = -half..half.
	var seg := 8.0
	var m := int(half * 2.0 / seg)
	var last := data.n - 1
	var win := int(24.0 / data.cell)
	var rows_in: Array[PackedVector3Array] = []
	for side in 4:
		var row := PackedVector3Array()
		var fixed := last if side == 0 or side == 2 else 0
		var sgn := 1.0 if side == 0 or side == 2 else -1.0
		for k in m + 1:
			var u := -half + k * seg
			var g := int(round((u + half) / data.cell))
			var lo := INF
			for o in range(-win, win + 1):
				var gg := clampi(g + o, 0, last)
				lo = minf(lo, data.grid_height(fixed, gg) if side < 2 else data.grid_height(gg, fixed))
			row.append(Vector3(sgn * half, lo - 0.3, u) if side < 2 else Vector3(u, lo - 0.3, sgn * half))
		rows_in.append(row)
	# Shared inner corners (east/west rows end on the north (k=0) and south (k=m) rows).
	for c in 4:
		var sx := 0 if c < 2 else 1          # east / west row
		var k := 0 if c % 2 == 0 else m      # north / south end
		var sz := 3 if k == 0 else 2         # north / south row
		var kz := m if sx == 0 else 0        # east end of a z row is u = +half
		var ra := rows_in[sx]
		var rb := rows_in[sz]
		var y := minf(ra[k].y, rb[kz].y)
		ra[k] = Vector3(ra[k].x, y, ra[k].z)
		rb[kz] = Vector3(rb[kz].x, y, rb[kz].z)
		rows_in[sx] = ra
		rows_in[sz] = rb
	for side in 4:
		var row := rows_in[side]
		var sgn := 1.0 if side == 0 or side == 2 else -1.0
		var base := verts.size()
		for k in m + 1:
			var p := row[k]
			var q := Vector3(sgn * inner, 0.0, p.z) if side < 2 else Vector3(p.x, 0.0, sgn * inner)
			# Outer edge: on the ring's own edge between its 64 m vertices.
			var u := p.z if side < 2 else p.x
			var u0 := floorf((u + ext) / step) * step - ext
			var t := (u - u0) / step
			var n0: int = node.call(q.x, u0) if side < 2 else node.call(u0, q.z)
			var n1: int = node.call(q.x, u0 + step) if side < 2 else node.call(u0 + step, q.z)
			if t < 0.001:
				q.y = verts[n0].y
			else:
				q.y = lerpf(verts[n0].y, verts[n1].y, t)
			verts.append(p)
			verts.append(q)
			cols.append(gen.region_weights(p.x, p.z))
			cols.append(gen.region_weights(q.x, q.z))
		for k in m:
			var a := base + k * 2
			_far_quad(verts, idx, a, a + 2, a + 3, a + 1)
	# Corner squares between two strips and the ring's corner vertex.
	for c in 4:
		var sx := 1.0 if c < 2 else -1.0
		var sz := -1.0 if c % 2 == 0 else 1.0
		var b := verts.size()
		var corner_row: PackedVector3Array = rows_in[0 if sx > 0.0 else 1]
		verts.append(corner_row[0 if sz < 0.0 else m])
		verts.append(verts[node.call(sx * inner, sz * half)])
		verts.append(verts[node.call(sx * inner, sz * inner)])
		verts.append(verts[node.call(sx * half, sz * inner)])
		for k in 4:
			cols.append(gen.region_weights(verts[b + k].x, verts[b + k].z))
		_far_quad(verts, idx, b, b + 1, b + 2, b + 3)
	var norms := RoadBuilder._recompute_normals(verts, idx)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_INDEX] = idx
	_far_result = {"arrays": arrays}


## Two up-facing triangles for the quad a-b-c-d (any winding).
static func _far_quad(verts: PackedVector3Array, idx: PackedInt32Array, a: int, b: int, c: int, d: int) -> void:
	for tri: Array in [[a, b, c], [a, c, d]]:
		var va := verts[int(tri[0])]
		var vb := verts[int(tri[1])]
		var vc := verts[int(tri[2])]
		if (vc - va).cross(vb - va).y > 0.0:
			idx.append_array([int(tri[0]), int(tri[1]), int(tri[2])])
		else:
			idx.append_array([int(tri[0]), int(tri[2]), int(tri[1])])


func _commit_far() -> void:
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _far_result["arrays"])
	var mi := MeshInstance3D.new()
	mi.name = "FarTerrain"
	mi.mesh = am
	mi.material_override = terrain_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	_far_result = {}


func _process(delta: float) -> void:
	if _far_task >= 0 and WorkerThreadPool.is_task_completed(_far_task):
		WorkerThreadPool.wait_for_task_completion(_far_task)
		_far_task = -1
		_commit_far()
	var car := Game.player_car
	var focus := Vector3.ZERO
	if car != null and is_instance_valid(car):
		focus = car.global_position
	elif Game.camera_rig:
		focus = (Game.camera_rig as Node3D).global_position
	terrain.focus = focus
	var pts: Array[Vector3] = [focus]
	pts.append_array(extra_physics_points)
	terrain.physics_points = pts
	_region_timer -= delta
	if _region_timer <= 0.0 and car != null:
		_region_timer = 0.5
		var r := data.region_at(focus.x, focus.z)
		if r != current_region:
			current_region = r
			Game.region_changed.emit(data.region_name(r))


func is_ready_near() -> bool:
	return terrain.is_near_ready() and roads.done


## The streaming focus jumped (teleport / respawn / load): re-evaluate terrain wants now.
func refocus(pos: Vector3) -> void:
	terrain.refocus(pos)


func _exit_tree() -> void:
	if _far_task >= 0:
		WorkerThreadPool.wait_for_task_completion(_far_task)


# ------------------------------------------------------------------ query API (Game.world contract)

func height_at(x: float, z: float) -> float:
	return data.height_at(x, z)


## Surface height including roads/bridges (raycast against world geometry), falling back to terrain.
func ground_at(x: float, z: float, from_y := 2000.0) -> float:
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(Vector3(x, from_y, z), Vector3(x, -100.0, z), 1)
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return data.height_at(x, z)
	return (hit["position"] as Vector3).y


func surface_at(pos: Vector3) -> SurfaceData:
	return Surfaces.from_map_index(data.surface_index_at(pos.x, pos.z))


func region_at(pos: Vector3) -> String:
	return data.region_name(data.region_at(pos.x, pos.z))


func region_id_at(pos: Vector3) -> int:
	return data.region_at(pos.x, pos.z)


func water_level_at(x: float, z: float) -> float:
	var lvl := -INF
	if data.height_at(x, z) < WorldLayout.SEA_LEVEL:
		lvl = WorldLayout.SEA_LEVEL
	for lk: Dictionary in data.lake_list():
		if Vector2(x - lk["pos"][0], z - lk["pos"][1]).length() < float(lk["radius"]) * 1.3:
			lvl = maxf(lvl, float(lk["level"]))
	var q := data.gen.river_query(Vector2(x, z))
	if q.x < 13.0:
		lvl = maxf(lvl, q.y)
	return lvl


func nearest_road_point(pos: Vector3, paved_only := false) -> Dictionary:
	var filt := Callable()
	if paved_only:
		filt = func(r: RoadNetwork.Road) -> bool: return r.traffic
	var res := data.network.nearest(pos, 600.0, filt)
	if res.is_empty():
		res = data.network.nearest(pos, 3000.0, filt)
	if res.is_empty():
		return {"position": pos, "forward": Vector3(0, 0, -1), "road_id": "", "s": 0.0}
	var r: RoadNetwork.Road = res["road"]
	var s: float = res["s"]
	if not r.loop:
		# Never place a car hanging over the end of a dead-end road or inside a junction mouth.
		s = clampf(s, minf(14.0, r.length * 0.5), maxf(r.length - 14.0, r.length * 0.5))
	# Place on the right-hand lane facing the travel direction closest to the current heading.
	var lane := r.lane_offset(1) if r.traffic else 0.0
	var p := r.surface_point(s, lane)
	return {"position": p, "forward": r.flat_tangent_at(s), "road_id": r.id, "road_name": r.name, "s": s}


func _build_teleports() -> void:
	_teleports.clear()
	for p: Dictionary in data.pois():
		var pos := Vector3(p["pos"][0], float(p.get("y", 0.0)), p["pos"][1])
		var rp := nearest_road_point(pos)
		if p["kind"] == "landmark":
			rp = _landmark_view(pos, rp)
		_teleports.append({"name": p["name"], "kind": p["kind"], "position": rp["position"], "forward": rp["forward"], "region": WorldLayout.REGIONS[int(p["region"])]["name"]})
	# Long-road start points.
	# Long-road start points, anchored to world positions so they survive layout edits.
	var starts := [["Ring Road - Festival Start", "ring", Vector2(-200, 650)], ["Ring Road - Switchbacks", "ring", Vector2(-1640, -380)],
		["Ring Road - Alpine Pass", "ring", Vector2(-1440, -1700)], ["Ring Road - Mesa Straight", "ring", Vector2(1260, -1160)],
		["Ring Road - Ochre Gorge", "ring", Vector2(1580, 80)], ["Ring Road - Cliff Road", "ring", Vector2(900, 1350)],
		["Expressway West", "expressway", Vector2(-1500, 100)], ["Expressway East", "expressway", Vector2(1400, -450)]]
	for st: Array in starts:
		var r := data.network.get_road(st[1])
		if r == null:
			continue
		var anchor: Vector2 = st[2]
		var hit := data.network.nearest(Vector3(anchor.x, 0, anchor.y), 400.0, func(rr: RoadNetwork.Road) -> bool: return rr == r)
		if hit.is_empty():
			continue
		var s: float = clampf(float(hit["s"]), 10.0, r.length - 10.0)
		_teleports.append({"name": st[0], "kind": "road", "position": r.surface_point(s, r.lane_offset(1)), "forward": r.flat_tangent_at(s), "region": region_at(r.point_at(s))})
	for reg: Dictionary in WorldLayout.REGIONS:
		for t: Dictionary in _teleports:
			if t["region"] == reg["name"] and t["kind"] != "road":
				_teleports.append({"name": reg["name"], "kind": "region", "position": t["position"], "forward": t["forward"], "region": reg["name"]})
				break


## Teleport spot that shows a landmark: a road point near it (within 450 m) from which a chase camera sees it
## over the terrain, preferring the landmark ahead, and facing it. A landmark in a lake is the lake itself (nearest shore road wins).
## A landmark you drive through (the tunnel) keeps the nearest point.
func _landmark_view(poi: Vector3, fallback: Dictionary) -> Dictionary:
	var near := data.network.nearest(poi, 600.0)
	if near.is_empty() or ((near["road"] as RoadNetwork.Road).flags[int(near["index"])] & 2):
		return fallback
	var anchor := Vector2(poi.x, poi.z)
	for lk: Dictionary in data.lake_list():
		var lc := Vector2(float(lk["pos"][0]), float(lk["pos"][1]))
		if anchor.distance_to(lc) < float(lk["radius"]):
			anchor = lc
	var water := water_level_at(anchor.x, anchor.y)
	var ground := data.height_at(anchor.x, anchor.y)
	# Water is seen at its surface; anything on land (turbines, canyon walls) stands taller.
	var target := Vector3(anchor.x, water + 2.0 if water > ground else ground + 12.0, anchor.y)
	var best := {}
	var best_score := 450.0
	for r in data.network.roads:
		for i in range(0, r.count(), 2):
			var c := r.pos[i]
			var d := Vector2(c.x, c.z).distance_to(anchor)
			var s := i * r.ds
			if d >= best_score or (r.flags[i] & 2) or (not r.loop and (s < 20.0 or s > r.length - 20.0)):
				continue
			var fwd := r.flat_tangent_at(s)
			var to := Vector3(anchor.x - c.x, 0.0, anchor.y - c.z).normalized()
			var dir := 1.0 if fwd.dot(to) >= 0.0 else -1.0
			# Nearer is better, and so is a heading that has the landmark ahead in the chase view.
			var score := d + 80.0 * (1.0 - fwd.dot(to) * dir)
			if score >= best_score or not _line_of_sight(c - fwd * dir * 6.0 + Vector3.UP * 3.0, target):
				continue
			best_score = score
			var lane := r.lane_offset(1 if dir > 0.0 else -1) if r.traffic else 0.0
			best = {"position": r.surface_point(s, lane), "forward": fwd * dir, "road_id": r.id, "road_name": r.name, "s": s}
	return fallback if best.is_empty() else best


## True when the straight line a -> b stays above the terrain.
func _line_of_sight(a: Vector3, b: Vector3) -> bool:
	var steps := maxi(int(a.distance_to(b) / 6.0), 1)
	for k in range(1, steps):
		var p := a.lerp(b, float(k) / steps)
		if data.height_at(p.x, p.z) > p.y - 0.3:
			return false
	return true


func get_teleport_targets() -> Array:
	return _teleports


func spawn_point() -> Dictionary:
	var r := data.network.get_road("ring")
	var s := 40.0
	return {"name": "Festival", "position": r.surface_point(s, r.lane_offset(1)), "forward": r.flat_tangent_at(s)}
