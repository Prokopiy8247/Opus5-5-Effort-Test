class_name RoadBuilder
extends Node3D
## Builds road surfaces (banked cross-sections), collision with surface metadata, bridge decks,
## parapets and piers, tunnel tubes with lights and portals, guard rails and edge posts.

const PIECE := 48  # samples per mesh/collision piece (~192 m)

var data: WorldData
var materials := {}
var concrete_mat: StandardMaterial3D
var rail_mat: StandardMaterial3D
var tunnel_mat: StandardMaterial3D
var tunnel_light_mat: StandardMaterial3D
var post_mesh: Mesh
var reflector_mesh: Mesh
var pier_scene: PackedScene
var portal_scene: PackedScene
var _trim := {}   # road index -> Vector2i(skip_start, skip_end) samples
var guard_runs: Array = []   # [{pts: PackedVector3Array}] for debug/stats
var stats := {"pieces": 0, "bridges": 0, "tunnels": 0, "rail_m": 0.0}


func setup(world_data: WorldData, noise_a: Texture2D, noise_b: Texture2D) -> void:
	data = world_data
	var sh := load("res://shaders/road.gdshader") as Shader
	for key in ["regional", "highway", "lane", "mountain", "dirt", "gravel", "sand"]:
		var m := ShaderMaterial.new()
		m.shader = sh
		var t := 0
		match key:
			"highway":
				t = 1
			"lane":
				t = 2
			"dirt":
				t = 3
			"gravel":
				t = 4
			"sand":
				t = 5
		m.set_shader_parameter("road_type", t)
		m.set_shader_parameter("noise_tex", noise_a)
		m.set_shader_parameter("noise_detail", noise_b)
		materials[key] = m
	concrete_mat = StandardMaterial3D.new()
	concrete_mat.albedo_color = Color(0.62, 0.61, 0.58)
	concrete_mat.roughness = 0.9
	concrete_mat.uv1_triplanar = true
	concrete_mat.uv1_scale = Vector3(0.25, 0.25, 0.25)
	concrete_mat.albedo_texture = noise_b
	rail_mat = StandardMaterial3D.new()
	rail_mat.albedo_color = Color(0.72, 0.74, 0.76)
	rail_mat.metallic = 0.85
	rail_mat.roughness = 0.35
	rail_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	tunnel_mat = StandardMaterial3D.new()
	tunnel_mat.albedo_color = Color(0.5, 0.49, 0.46)
	tunnel_mat.roughness = 0.85
	tunnel_mat.uv1_triplanar = true
	tunnel_mat.uv1_scale = Vector3(0.3, 0.3, 0.3)
	tunnel_mat.albedo_texture = noise_b
	tunnel_light_mat = StandardMaterial3D.new()
	tunnel_light_mat.albedo_color = Color(1.0, 0.85, 0.55)
	tunnel_light_mat.emission_enabled = true
	tunnel_light_mat.emission = Color(1.0, 0.75, 0.4)
	tunnel_light_mat.emission_energy_multiplier = 4.0
	var pm := BoxMesh.new()
	pm.size = Vector3(0.12, 1.0, 0.12)
	post_mesh = pm
	var rm := BoxMesh.new()
	rm.size = Vector3(0.13, 0.12, 0.05)
	var refl := StandardMaterial3D.new()
	refl.albedo_color = Color(1.0, 0.55, 0.1)
	refl.emission_enabled = true
	refl.emission = Color(1.0, 0.5, 0.1)
	refl.emission_energy_multiplier = 0.6
	rm.material = refl
	reflector_mesh = rm
	if ResourceLoader.exists("res://assets/imported/props/bridge_pier.glb"):
		pier_scene = load("res://assets/imported/props/bridge_pier.glb")
	if ResourceLoader.exists("res://assets/imported/props/tunnel_portal.glb"):
		portal_scene = load("res://assets/imported/props/tunnel_portal.glb")
	_compute_trims()


func _compute_trims() -> void:
	# a branch road's mesh starts at the edge of the road it joins, so markings don't overlap
	for road in data.roads:
		var s := 0
		var e := 0
		for j in road.junctions:
			var other := data.road_by_id(j.road)
			if other == null:
				continue
			var cut := int(ceil((other.width * 0.5 - 0.6) / 4.0))
			if int(j.self_i) == 0:
				s = maxi(s, cut)
			else:
				e = maxi(e, cut)
		_trim[road.index] = Vector2i(s, e)


## Builds everything. Mesh arrays are computed on worker threads, nodes on the main thread.
func build_all() -> void:
	var jobs: Array = []
	for road in data.roads:
		var n := road.pts.size()
		var tr: Vector2i = _trim.get(road.index, Vector2i.ZERO)
		var start := tr.x
		var stop := n - 1 - tr.y
		var i := start
		while i < stop:
			var j := mini(i + PIECE, stop)
			jobs.append([road, i, j])
			i = j
	var results: Array = []
	results.resize(jobs.size())
	var task := WorkerThreadPool.add_group_task(func(k: int) -> void:
		results[k] = _piece_arrays(jobs[k][0], jobs[k][1], jobs[k][2])
	, jobs.size(), -1, true, "roads")
	WorkerThreadPool.wait_for_group_task_completion(task)
	for k in jobs.size():
		_make_piece(jobs[k][0], results[k])
	for road in data.roads:
		_build_structures(road)
	stats.pieces = jobs.size()


func _lateral(road: WorldData.Road, i: int) -> Vector3:
	var t := road.tangent(i)
	return Vector3(-t.z, 0.0, t.x)


func _bank_sign(road: WorldData.Road, i: int) -> float:
	var n := road.pts.size()
	var a := road.tangent(maxi(i - 3, 0) if not road.closed else posmod(i - 3, n))
	var b := road.tangent(mini(i + 3, n - 1) if not road.closed else posmod(i + 3, n))
	var k := b - a
	return signf(k.dot(_lateral(road, i)))


## Returns {surf: arrays, col: PackedVector3Array faces}
func _piece_arrays(road: WorldData.Road, i0: int, i1: int) -> Dictionary:
	var hw := road.width * 0.5
	var sh := road.shoulder
	var offs := PackedFloat32Array([-(hw + sh + 1.2), -(hw + sh), -hw, -hw * 0.5, 0.0, hw * 0.5, hw, hw + sh, hw + sh + 1.2])
	var drops := PackedFloat32Array([-1.1, -0.07, 0.0, 0.0, 0.015, 0.0, 0.0, -0.07, -1.1])
	var ncs := offs.size()
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	var faces := PackedVector3Array()
	var dist := float(i0) * 4.0
	var junction_drop := 0.0
	if road.junctions.size() > 0 and road.cls in ["lane", "dirt", "gravel", "sand"]:
		junction_drop = 0.03
	var rows := 0
	for i in range(i0, i1 + 1):
		var p := road.pts[i]
		var lat := _lateral(road, i)
		var bank := absf(road.bank[i]) if i < road.bank.size() else 0.0
		var bs := _bank_sign(road, i)
		var in_bridge := road.flags[i] == 1
		var in_tunnel := road.flags[i] == 2
		for c in ncs:
			var u := offs[c]
			var drop := drops[c]
			if (in_bridge or in_tunnel) and (c == 0 or c == ncs - 1):
				drop = -0.07
			var y := p.y + drop - u * bank * bs - junction_drop
			verts.append(Vector3(p.x, y, p.z) + lat * u)
			uvs.append(Vector2(u, dist))
			norms.append(Vector3.UP)
		if i > i0:
			dist += road.pts[i].distance_to(road.pts[i - 1])
			# fix the uv of this row now that dist advanced
			for c in ncs:
				uvs[rows * ncs + c] = Vector2(offs[c], dist)
		rows += 1
	for r in range(rows - 1):
		for c in range(ncs - 1):
			var a := r * ncs + c
			var b := a + 1
			var cc := a + ncs
			var d := cc + 1
			# rows advance along the road; lateral index increases to the right
			idx.append_array([a, cc, b, b, cc, d])
			if c >= 1 and c < ncs - 2:
				faces.append_array([verts[a], verts[cc], verts[b], verts[b], verts[cc], verts[d]])
	# smooth normals
	var acc := PackedVector3Array()
	acc.resize(verts.size())
	for t in range(0, idx.size(), 3):
		var va := verts[idx[t]]
		var vb := verts[idx[t + 1]]
		var vc := verts[idx[t + 2]]
		var nn := (vb - va).cross(vc - va)
		for q in 3:
			acc[idx[t + q]] += nn
	for v in acc.size():
		norms[v] = acc[v].normalized() if acc[v].length_squared() > 0.0 else Vector3.UP
		if norms[v].y < 0.0:
			norms[v] = -norms[v]
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = idx
	return {"surf": arrays, "col": faces}


func _make_piece(road: WorldData.Road, res: Dictionary) -> void:
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, res.surf)
	var mat: ShaderMaterial = materials.get(road.cls, materials["regional"])
	mesh.surface_set_material(0, mat)
	(mat as ShaderMaterial).set_shader_parameter("half_width", road.width * 0.5)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visibility_range_end = 2600.0
	var body := StaticBody3D.new()
	body.name = "Road_%s" % road.id
	body.collision_layer = 1
	body.collision_mask = 0
	body.set_meta("surface", road.surface)
	body.set_meta("road", road.id)
	var cs := CollisionShape3D.new()
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(res.col)
	cs.shape = shape
	body.add_child(cs)
	body.add_child(mi)
	add_child(body)


# ------------------------------------------------------------------ structures
func _runs(road: WorldData.Road, flag: int) -> Array:
	var out: Array = []
	var n := road.flags.size()
	var i := 0
	while i < n:
		if road.flags[i] == flag:
			var j := i
			while j < n and road.flags[j] == flag:
				j += 1
			out.append(Vector2i(i, j - 1))
			i = j
		else:
			i += 1
	return out


func _build_structures(road: WorldData.Road) -> void:
	for run in _runs(road, 1):
		_bridge(road, run.x, run.y)
		stats.bridges += 1
	for run in _runs(road, 2):
		_tunnel(road, run.x, run.y)
		stats.tunnels += 1
	_guard_rails(road)
	_edge_posts(road)


func _bridge(road: WorldData.Road, a: int, b: int) -> void:
	var n := road.pts.size()
	a = maxi(a - 2, 0)
	b = mini(b + 2, n - 1)
	var hw := road.width * 0.5 + road.shoulder
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var parapet_faces := PackedVector3Array()
	# deck slab + parapets as a swept profile (closed polygon, counter-clockwise looking along road)
	var prof := [
		Vector2(-hw - 0.35, 0.95), Vector2(-hw - 0.35, -1.4), Vector2(hw + 0.35, -1.4), Vector2(hw + 0.35, 0.95),
		Vector2(hw, 0.95), Vector2(hw, -0.05), Vector2(-hw, -0.05), Vector2(-hw, 0.95),
	]
	var rows: Array = []
	for i in range(a, b + 1):
		var p := road.pts[i]
		var lat := _lateral(road, i)
		var row := PackedVector3Array()
		for q in prof:
			row.append(p + lat * q.x + Vector3.UP * q.y)
		rows.append(row)
	for r in range(rows.size() - 1):
		var r0: PackedVector3Array = rows[r]
		var r1: PackedVector3Array = rows[r + 1]
		for q in prof.size():
			var q1 := (q + 1) % prof.size()
			if q == 5:
				continue  # deck top is the road surface itself
			_quad(st, r0[q], r0[q1], r1[q1], r1[q])
			if q in [3, 4, 6, 7, 0]:
				parapet_faces.append_array([r0[q], r0[q1], r1[q1], r0[q], r1[q1], r1[q]])
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = concrete_mat
	mi.visibility_range_end = 2600.0
	var body := StaticBody3D.new()
	body.name = "Bridge_%s_%d" % [road.id, a]
	body.collision_layer = 1
	body.set_meta("surface", Game.Surf.CONCRETE)
	var cs := CollisionShape3D.new()
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(parapet_faces)
	shape.backface_collision = true
	cs.shape = shape
	body.add_child(cs)
	body.add_child(mi)
	add_child(body)
	# piers
	var i := a + 4
	while i < b - 3:
		var p := road.pts[i]
		var ground := data.height_at(p.x, p.z)
		var depth := p.y - 1.4 - ground
		if depth > 1.5:
			_pier(p + Vector3.DOWN * 1.4, depth + 3.0, road.tangent(i), hw)
		i += 7


func _pier(top: Vector3, height: float, tangent: Vector3, hw: float) -> void:
	var node: Node3D
	if pier_scene:
		node = pier_scene.instantiate()
		node.scale = Vector3(hw / 5.0, height / 20.0, 1.0)
	else:
		var mi := MeshInstance3D.new()
		var cm := BoxMesh.new()
		cm.size = Vector3(hw * 1.4, height, 1.6)
		mi.mesh = cm
		mi.material_override = concrete_mat
		mi.position = Vector3(0, -height * 0.5, 0)
		node = Node3D.new()
		node.add_child(mi)
	node.basis = Basis.looking_at(tangent, Vector3.UP) * Basis.from_scale(node.scale)
	node.position = top
	add_child(node)


func _tunnel(road: WorldData.Road, a: int, b: int) -> void:
	var n := road.pts.size()
	a = maxi(a - 3, 0)
	b = mini(b + 3, n - 1)
	var hw := road.width * 0.5 + road.shoulder + 0.6
	var height := 6.8
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var lights := SurfaceTool.new()
	lights.begin(Mesh.PRIMITIVE_TRIANGLES)
	var col := PackedVector3Array()
	var segs := 10
	var rows: Array = []
	for i in range(a, b + 1):
		var p := road.pts[i]
		var lat := _lateral(road, i)
		var row := PackedVector3Array()
		row.append(p + lat * -hw + Vector3.DOWN * 0.3)
		for s in segs + 1:
			var ang := PI - PI * float(s) / segs
			var x := cos(ang) * hw
			var y := 2.0 + sin(ang) * (height - 2.0)
			row.append(p + lat * x + Vector3.UP * y)
		row.append(p + lat * hw + Vector3.DOWN * 0.3)
		rows.append(row)
	for r in range(rows.size() - 1):
		var r0: PackedVector3Array = rows[r]
		var r1: PackedVector3Array = rows[r + 1]
		for q in range(r0.size() - 1):
			# inward-facing
			_quad(st, r0[q + 1], r0[q], r1[q], r1[q + 1])
			col.append_array([r0[q], r0[q + 1], r1[q + 1], r0[q], r1[q + 1], r1[q]])
		# ceiling light strip every other segment
		if r % 2 == 0:
			var c0 := r0[segs / 2 + 1] + Vector3.DOWN * 0.08
			var c1 := r1[segs / 2 + 1] + Vector3.DOWN * 0.08
			var side := (r0[segs / 2 + 2] - r0[segs / 2]).normalized() * 0.25
			_quad(lights, c0 - side, c0 + side, c1 + side, c1 - side)
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = tunnel_mat
	var lm := MeshInstance3D.new()
	lights.generate_normals()
	lm.mesh = lights.commit()
	lm.material_override = tunnel_light_mat
	lm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var body := StaticBody3D.new()
	body.name = "Tunnel_%s_%d" % [road.id, a]
	body.collision_layer = 1
	body.set_meta("surface", Game.Surf.CONCRETE)
	var cs := CollisionShape3D.new()
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(col)
	shape.backface_collision = true
	cs.shape = shape
	body.add_child(cs)
	body.add_child(mi)
	body.add_child(lm)
	add_child(body)
	# a few real lights inside (cheap, no shadows)
	var i := a + 6
	while i < b - 4:
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.8, 0.5)
		l.omni_range = 18.0
		l.light_energy = 1.4
		l.shadow_enabled = false
		l.position = road.pts[i] + Vector3.UP * (height - 1.0)
		l.distance_fade_enabled = true
		l.distance_fade_begin = 120.0
		l.distance_fade_length = 40.0
		add_child(l)
		i += 12
	# portals at both ends
	for end_i: int in [a, b]:
		var p := road.pts[end_i]
		var t := road.tangent(end_i)
		if end_i == b:
			t = -t
		_portal(p, t, hw, height)


func _portal(p: Vector3, outward: Vector3, hw: float, height: float) -> void:
	# outward points away from the tunnel interior
	if portal_scene:
		var node := portal_scene.instantiate() as Node3D
		node.basis = Basis.looking_at(-outward, Vector3.UP)
		node.position = p
		node.scale = Vector3(hw / 5.5, 1.0, 1.0)
		add_child(node)
		return
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var lat := Vector3(-outward.z, 0.0, outward.x)
	var w := hw + 4.0
	var top := height + 3.5
	# facade frame around the arch opening (left, right, top bands)
	var f := p - outward * 0.2
	_quad(st, f - lat * w, f - lat * hw, f - lat * hw + Vector3.UP * top, f - lat * w + Vector3.UP * top)
	_quad(st, f + lat * hw, f + lat * w, f + lat * w + Vector3.UP * top, f + lat * hw + Vector3.UP * top)
	_quad(st, f - lat * hw + Vector3.UP * height, f + lat * hw + Vector3.UP * height, f + lat * hw + Vector3.UP * top, f - lat * hw + Vector3.UP * top)
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var m := concrete_mat.duplicate() as StandardMaterial3D
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = m
	add_child(mi)


func _guard_rails(road: WorldData.Road) -> void:
	if road.cls in ["dirt", "sand"]:
		return
	var n := road.pts.size()
	var hw := road.width * 0.5 + road.shoulder * 0.5
	for side: float in [-1.0, 1.0]:
		var run := PackedVector3Array()
		for i in n:
			var need := false
			if road.flags[i] == 0:
				var p := road.pts[i]
				var lat := _lateral(road, i) * side
				var probe := p + lat * (hw + 3.5)
				var g := data.height_at(probe.x, probe.z)
				need = g < p.y - 2.2 or (road.cls == "mountain" and g < p.y - 1.2)
				# keep junction mouths open
				for j in road.junctions:
					if absi(int(j.self_i) - i) < 6:
						need = false
				if need and _near_other_junction(road, i):
					need = false
			if need:
				var lat2 := _lateral(road, i) * side
				run.append(road.pts[i] + lat2 * (hw + 0.25))
			elif run.size() > 0:
				if run.size() >= 4:
					_rail_mesh(run, side)
				run = PackedVector3Array()
		if run.size() >= 4:
			_rail_mesh(run, side)


func _near_other_junction(road: WorldData.Road, i: int) -> bool:
	var p := road.pts[i]
	for other in data.roads:
		if other == road:
			continue
		for j in other.junctions:
			if j.road == road.id and absi(int(j.road_i) - i) < 7:
				return true
	return false


func _rail_mesh(run: PackedVector3Array, side: float) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var faces := PackedVector3Array()
	var posts := MultiMeshInstance3D.new()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = post_mesh
	mm.instance_count = run.size()
	for i in range(run.size()):
		var p := run[i]
		mm.set_instance_transform(i, Transform3D(Basis(), p + Vector3(0, 0.25, 0)))
		if i == 0:
			continue
		var q := run[i - 1]
		var lo := 0.5
		var hi := 0.85
		_quad(st, q + Vector3.UP * lo, p + Vector3.UP * lo, p + Vector3.UP * hi, q + Vector3.UP * hi)
		faces.append_array([q + Vector3.UP * 0.2, p + Vector3.UP * 0.2, p + Vector3.UP * 1.0,
			q + Vector3.UP * 0.2, p + Vector3.UP * 1.0, q + Vector3.UP * 1.0])
		stats.rail_m += p.distance_to(q)
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = rail_mat
	mi.visibility_range_end = 900.0
	posts.multimesh = mm
	posts.material_override = rail_mat
	posts.visibility_range_end = 500.0
	var body := StaticBody3D.new()
	body.name = "GuardRail"
	body.collision_layer = 1
	body.set_meta("surface", Game.Surf.CONCRETE)
	var cs := CollisionShape3D.new()
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	shape.backface_collision = true
	cs.shape = shape
	body.add_child(cs)
	body.add_child(mi)
	body.add_child(posts)
	add_child(body)


func _edge_posts(road: WorldData.Road) -> void:
	if road.cls in ["dirt", "sand", "gravel"]:
		return
	var n := road.pts.size()
	var hw := road.width * 0.5 + road.shoulder + 0.5
	var xforms: Array[Transform3D] = []
	var i := 3
	while i < n - 3:
		if road.flags[i] == 0:
			for side: float in [-1.0, 1.0]:
				var p := road.pts[i] + _lateral(road, i) * side * hw
				var g := data.height_at(p.x, p.z)
				var t := road.tangent(i)
				xforms.append(Transform3D(Basis.looking_at(t * -side, Vector3.UP), Vector3(p.x, g + 0.5, p.z)))
		i += 12
	if xforms.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var post := BoxMesh.new()
	post.size = Vector3(0.12, 1.0, 0.12)
	var pmat := StandardMaterial3D.new()
	pmat.albedo_color = Color(0.92, 0.92, 0.9)
	post.material = pmat
	mm.mesh = post
	mm.instance_count = xforms.size()
	for k in xforms.size():
		mm.set_instance_transform(k, xforms[k])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.visibility_range_end = 400.0
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)
	var mm2 := MultiMesh.new()
	mm2.transform_format = MultiMesh.TRANSFORM_3D
	mm2.mesh = reflector_mesh
	mm2.instance_count = xforms.size()
	for k in xforms.size():
		var x := xforms[k]
		x.origin += Vector3.UP * 0.38
		mm2.set_instance_transform(k, x)
	var mmi2 := MultiMeshInstance3D.new()
	mmi2.multimesh = mm2
	mmi2.visibility_range_end = 600.0
	mmi2.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi2)


static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	st.add_vertex(a)
	st.add_vertex(b)
	st.add_vertex(c)
	st.add_vertex(a)
	st.add_vertex(c)
	st.add_vertex(d)
