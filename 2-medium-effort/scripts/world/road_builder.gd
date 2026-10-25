class_name RoadBuilder
extends Node3D
## Builds road decks (procedural lane-marking shader), junction pads, bridges with piers and parapets,
## tunnel tubes, guard rails and reflector posts from WorldData, in 128 m pieces with visibility ranges.

const PIECE: int = 32
const VIS_END: float = 1600.0

var world: WorldData
var mats: Dictionary = {}
var concrete_mat: StandardMaterial3D
var rail_mat: StandardMaterial3D
var tunnel_mat: StandardMaterial3D
var trim: Dictionary = {}  # "ri:start"/"ri:end" -> metres trimmed
var pier_xforms: Array[Transform3D] = []
var post_xforms: Array[Transform3D] = []
var rail_post_xforms: Array[Transform3D] = []
var tunnel_lights: Array[Vector3] = []
var stats: Dictionary = {"pieces": 0, "rail_m": 0.0}


func build(w: WorldData) -> void:
	world = w
	_make_materials()
	_compute_trims()
	for ri in world.roads.size():
		_build_road(ri)
	_build_pads()
	_build_multimeshes()


func _make_materials() -> void:
	var noise := FastNoiseLite.new()
	noise.frequency = 0.05
	noise.fractal_octaves = 4
	var tex := NoiseTexture2D.new()
	tex.width = 256
	tex.height = 256
	tex.seamless = true
	tex.noise = noise
	var shader: Shader = load("res://shaders/road.gdshader")
	for cls in RoadLayout.CLASSES:
		var c: Dictionary = RoadLayout.CLASSES[cls]
		var m := ShaderMaterial.new()
		m.shader = shader
		m.set_shader_parameter("noise_tex", tex)
		m.set_shader_parameter("lane_w", c.lane)
		m.set_shader_parameter("half_w", c.lane + c.shoulder)
		var kind: int = 0
		match c.surface:
			"concrete": kind = 1
			"dirt": kind = 2
			"gravel": kind = 3
		m.set_shader_parameter("kind", kind)
		m.set_shader_parameter("double_center", cls == "mountain")
		m.set_shader_parameter("yellow_center", cls == "highway")
		mats[cls] = m
	var pad := ShaderMaterial.new()
	pad.shader = shader
	pad.set_shader_parameter("noise_tex", tex)
	pad.set_shader_parameter("kind", 4)
	mats["pad"] = pad
	concrete_mat = StandardMaterial3D.new()
	concrete_mat.albedo_color = Color(0.62, 0.6, 0.56)
	concrete_mat.roughness = 0.9
	concrete_mat.albedo_texture = tex
	concrete_mat.uv1_scale = Vector3(0.2, 0.2, 0.2)
	concrete_mat.uv1_triplanar = true
	concrete_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	rail_mat = StandardMaterial3D.new()
	rail_mat.albedo_color = Color(0.72, 0.74, 0.76)
	rail_mat.metallic = 0.8
	rail_mat.roughness = 0.35
	rail_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	tunnel_mat = StandardMaterial3D.new()
	tunnel_mat.albedo_color = Color(0.5, 0.48, 0.45)
	tunnel_mat.roughness = 0.85
	tunnel_mat.cull_mode = BaseMaterial3D.CULL_DISABLED


func _pad_radius(node: String) -> float:
	var r: float = 0.0
	for e in world.node_roads[node]:
		r = maxf(r, world.roads[e[0]].hw)
	return r + 2.0


func _compute_trims() -> void:
	for node in world.node_roads:
		var ends: Array = world.node_roads[node]
		if ends.size() >= 3:
			var r: float = _pad_radius(node) - 1.0
			for e in ends:
				trim["%d:%s" % [e[0], "s" if e[1] else "e"]] = r


func _build_road(ri: int) -> void:
	var r: Dictionary = world.roads[ri]
	var pts: PackedVector3Array = r.pts
	var m: int = pts.size()
	var s_trim: float = trim.get("%d:s" % ri, 0.0)
	var e_trim: float = trim.get("%d:e" % ri, 0.0)
	var i0: int = int(ceil(s_trim / WorldData.STEP))
	var i1: int = m - 1 - int(ceil(e_trim / WorldData.STEP))
	if i1 <= i0 + 1:
		return
	var start: int = i0
	while start < i1:
		var end: int = mini(start + PIECE, i1)
		_build_piece(ri, start, end)
		start = end


func _xs(r: Dictionary, i: int, off: float, dy: float = 0.0) -> Vector3:
	var p: Vector3 = r.pts[i]
	var rt: Vector3 = r.right[i]
	return p + rt * off + Vector3(0, r.bank[i] * off + dy, 0)


func _build_piece(ri: int, a: int, b: int) -> void:
	var r: Dictionary = world.roads[ri]
	var hw: float = r.hw
	var flags: PackedByteArray = r.flags
	var deck := SurfaceTool.new()
	deck.begin(Mesh.PRIMITIVE_TRIANGLES)
	var conc := SurfaceTool.new()
	conc.begin(Mesh.PRIMITIVE_TRIANGLES)
	var metal := SurfaceTool.new()
	metal.begin(Mesh.PRIMITIVE_TRIANGLES)
	var tun := SurfaceTool.new()
	tun.begin(Mesh.PRIMITIVE_TRIANGLES)
	var faces := PackedVector3Array()
	var has_conc: bool = false
	var has_metal: bool = false
	var has_tun: bool = false
	var lane: float = r.lane
	for i in range(a, b):
		var j: int = i + 1
		var d0: float = r.dist[i]
		var d1: float = r.dist[j]
		var bridge: bool = flags[i] == 1 or flags[j] == 1
		var tunnel: bool = flags[i] == 2 or flags[j] == 2
		# deck: 4 columns (verge, edge, edge, verge) -> 3 quads
		var cols: Array = [-hw - 1.4, -hw, 0.0, hw, hw + 1.4]
		var dys: Array = [-0.35, 0.0, 0.0, 0.0, -0.35]
		if bridge or tunnel:
			cols = [-hw, -hw * 0.5, 0.0, hw * 0.5, hw]
			dys = [0.0, 0.0, 0.0, 0.0, 0.0]
		for c in 4:
			var p00: Vector3 = _xs(r, i, cols[c], dys[c])
			var p01: Vector3 = _xs(r, i, cols[c + 1], dys[c + 1])
			var p10: Vector3 = _xs(r, j, cols[c], dys[c])
			var p11: Vector3 = _xs(r, j, cols[c + 1], dys[c + 1])
			_quad(deck, p00, p01, p11, p10, Vector2(cols[c], d0), Vector2(cols[c + 1], d0), Vector2(cols[c + 1], d1), Vector2(cols[c], d1))
			faces.append_array([p00, p01, p11, p00, p11, p10])
		if bridge:
			has_conc = true
			# slab underside and sides, parapets
			var th: float = 1.3
			var l0: Vector3 = _xs(r, i, -hw - 0.4, 0.0)
			var r0: Vector3 = _xs(r, i, hw + 0.4, 0.0)
			var l1: Vector3 = _xs(r, j, -hw - 0.4, 0.0)
			var r1: Vector3 = _xs(r, j, hw + 0.4, 0.0)
			var dn := Vector3(0, -th, 0)
			_quad_n(conc, l0 + dn, l1 + dn, r1 + dn, r0 + dn)
			_quad_n(conc, l0, l1, l1 + dn, l0 + dn)
			_quad_n(conc, r1, r0, r0 + dn, r1 + dn)
			for side in [-1.0, 1.0]:
				var e0: Vector3 = _xs(r, i, side * (hw + 0.2), 0.0)
				var e1: Vector3 = _xs(r, j, side * (hw + 0.2), 0.0)
				var up := Vector3(0, 0.95, 0)
				var rt0: Vector3 = r.right[i] * side * 0.3
				var rt1: Vector3 = r.right[j] * side * 0.3
				_quad_n(conc, e0, e0 + up, e1 + up, e1)
				_quad_n(conc, e0 + up, e0 + up + rt0, e1 + up + rt1, e1 + up)
				_quad_n(conc, e1 + rt1, e1 + up + rt1, e0 + up + rt0, e0 + rt0)
				faces.append_array([e0, e0 + up, e1 + up, e0, e1 + up, e1])
			if i % 7 == 0:
				var p: Vector3 = r.pts[i]
				var ground: float = world.natural_height(p.x, p.z)
				var top: float = p.y - th
				if top - ground > 1.0:
					var hgt: float = top - ground + 2.0
					var bas := Basis.looking_at(Vector3(r.right[i].z, 0, -r.right[i].x) * -1.0, Vector3.UP)
					bas = bas.scaled(Vector3(hw * 1.5, hgt, 1.6))
					pier_xforms.append(Transform3D(bas, Vector3(p.x, top - hgt * 0.5, p.z)))
		elif tunnel:
			has_tun = true
			var rad: float = hw + 1.6
			var hgt2: float = 6.4
			var seg: int = 7
			for k in seg:
				var a0: float = PI * k / seg
				var a1: float = PI * (k + 1) / seg
				var o0 := Vector2(-cos(a0) * rad, sin(a0) * (hgt2 - 1.2) + 1.2)
				var o1 := Vector2(-cos(a1) * rad, sin(a1) * (hgt2 - 1.2) + 1.2)
				var q00: Vector3 = r.pts[i] + r.right[i] * o0.x + Vector3(0, o0.y, 0)
				var q01: Vector3 = r.pts[i] + r.right[i] * o1.x + Vector3(0, o1.y, 0)
				var q10: Vector3 = r.pts[j] + r.right[j] * o0.x + Vector3(0, o0.y, 0)
				var q11: Vector3 = r.pts[j] + r.right[j] * o1.x + Vector3(0, o1.y, 0)
				_quad_n(tun, q00, q10, q11, q01)
				faces.append_array([q00, q10, q11, q00, q11, q01])
			for side in [-1.0, 1.0]:
				var w0: Vector3 = r.pts[i] + r.right[i] * side * rad
				var w1: Vector3 = r.pts[j] + r.right[j] * side * rad
				var u := Vector3(0, 1.2, 0)
				_quad_n(tun, w0, w1, w1 + u, w0 + u)
				faces.append_array([w0, w1, w1 + u, w0, w1 + u, w0 + u])
			if i % 8 == 0:
				tunnel_lights.append(r.pts[i] + Vector3(0, hgt2 - 0.3, 0))
			# portals: thick concrete face where the tunnel starts or ends
			if (i > 0 and flags[i - 1] != 2) or (j < flags.size() - 1 and flags[j + 1] != 2):
				has_conc = true
				var pi_: int = i if (i > 0 and flags[i - 1] != 2) else j
				var c: Vector3 = r.pts[pi_]
				var rt: Vector3 = r.right[pi_]
				for k in 12:
					var x0: float = -rad - 9.0 + k * (rad * 2.0 + 18.0) / 12.0
					var x1: float = x0 + (rad * 2.0 + 18.0) / 12.0
					var yb0: float = 0.0
					var yb1: float = 0.0
					if absf(x0) < rad:
						yb0 = sqrt(maxf(0.0, 1.0 - (x0 / rad) * (x0 / rad))) * (hgt2 - 1.2) + 1.2
					if absf(x1) < rad:
						yb1 = sqrt(maxf(0.0, 1.0 - (x1 / rad) * (x1 / rad))) * (hgt2 - 1.2) + 1.2
					var top: float = hgt2 + 9.0
					var b0: Vector3 = c + rt * x0 + Vector3(0, yb0, 0)
					var b1: Vector3 = c + rt * x1 + Vector3(0, yb1, 0)
					_quad_n(conc, b0, b1, c + rt * x1 + Vector3(0, top, 0), c + rt * x0 + Vector3(0, top, 0))
					_quad_n(conc, c + rt * x0 + Vector3(0, top, 0), c + rt * x1 + Vector3(0, top, 0), b1, b0)
		else:
			# guard rails where the verge drops away, plus reflector posts
			for side in [-1.0, 1.0]:
				var p: Vector3 = _xs(r, i, side * (hw + 0.9))
				var probe: Vector3 = r.pts[i] + r.right[i] * side * (hw + 6.0)
				var drop: float = p.y - world.natural_height(probe.x, probe.z)
				var need_rail: bool = drop > 3.0 or (r.cls == "mountain" and drop > 1.2)
				if need_rail and r.surface <= 1:
					has_metal = true
					var q0: Vector3 = _xs(r, i, side * (hw + 0.9))
					var q1: Vector3 = _xs(r, j, side * (hw + 0.9))
					var lo := Vector3(0, 0.45, 0)
					var hi := Vector3(0, 0.8, 0)
					_quad_n(metal, q0 + lo, q1 + lo, q1 + hi, q0 + hi)
					_quad_n(metal, q1 + lo, q0 + lo, q0 + hi, q1 + hi)
					faces.append_array([q0, q1, q1 + hi, q0, q1 + hi, q0 + hi])
					stats.rail_m += WorldData.STEP
					rail_post_xforms.append(Transform3D(Basis(), q0 + Vector3(0, 0.4, 0) + r.right[i] * side * 0.12))
				elif i % 12 == 0 and r.surface <= 1:
					post_xforms.append(Transform3D(Basis.looking_at(r.right[i] * side, Vector3.UP), p + Vector3(0, 0.5, 0) + r.right[i] * side * 0.6))
	var mesh := ArrayMesh.new()
	deck.generate_normals()
	deck.commit(mesh)
	mesh.surface_set_material(0, mats[r.cls])
	if has_conc:
		conc.generate_normals()
		conc.commit(mesh)
		mesh.surface_set_material(mesh.get_surface_count() - 1, concrete_mat)
	if has_metal:
		metal.generate_normals()
		metal.commit(mesh)
		mesh.surface_set_material(mesh.get_surface_count() - 1, rail_mat)
	if has_tun:
		tun.generate_normals()
		tun.commit(mesh)
		mesh.surface_set_material(mesh.get_surface_count() - 1, tunnel_mat)
	var mi := MeshInstance3D.new()
	mi.name = "Road_%d_%d" % [ri, a]
	mi.mesh = mesh
	mi.visibility_range_end = VIS_END
	mi.visibility_range_end_margin = 100.0
	mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	add_child(mi)
	var body := StaticBody3D.new()
	body.collision_layer = 1 | 2
	body.collision_mask = 0
	body.set_meta("road_surface", r.surface)
	body.set_meta("road_index", ri)
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	shape.backface_collision = true
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	mi.add_child(body)
	stats.pieces += 1


func _quad(st: SurfaceTool, p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, u0: Vector2, u1: Vector2, u2: Vector2, u3: Vector2) -> void:
	# p0..p3 counter-clockwise when seen from above (Godot front faces are clockwise -> emit reversed)
	st.set_uv(u0); st.add_vertex(p0)
	st.set_uv(u2); st.add_vertex(p2)
	st.set_uv(u1); st.add_vertex(p1)
	st.set_uv(u0); st.add_vertex(p0)
	st.set_uv(u3); st.add_vertex(p3)
	st.set_uv(u2); st.add_vertex(p2)


func _quad_n(st: SurfaceTool, p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3) -> void:
	var uv := Vector2.ZERO
	st.set_uv(uv); st.add_vertex(p0)
	st.set_uv(uv); st.add_vertex(p2)
	st.set_uv(uv); st.add_vertex(p1)
	st.set_uv(uv); st.add_vertex(p0)
	st.set_uv(uv); st.add_vertex(p3)
	st.set_uv(uv); st.add_vertex(p2)


func _build_pads() -> void:
	for node in world.node_roads:
		var ends: Array = world.node_roads[node]
		if ends.size() == 2:
			continue
		var c2: Vector2 = RoadLayout.NODES[node]
		var h: float = world.node_height[node]
		var rad: float = _pad_radius(node) if ends.size() >= 3 else world.roads[ends[0][0]].hw + 3.5
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var faces := PackedVector3Array()
		var seg: int = 24
		var cen := Vector3(c2.x, h - 0.04, c2.y)
		for k in seg:
			var a0: float = TAU * k / seg
			var a1: float = TAU * (k + 1) / seg
			var p0: Vector3 = cen + Vector3(cos(a0) * rad, 0, sin(a0) * rad)
			var p1: Vector3 = cen + Vector3(cos(a1) * rad, 0, sin(a1) * rad)
			var q0: Vector3 = cen + Vector3(cos(a0) * (rad + 2.0), -0.4, sin(a0) * (rad + 2.0))
			var q1: Vector3 = cen + Vector3(cos(a1) * (rad + 2.0), -0.4, sin(a1) * (rad + 2.0))
			for tri in [[cen, p0, p1], [p0, q1, p1], [p0, q0, q1]]:
				for v in tri:
					st.set_uv(Vector2(v.x - cen.x, v.z - cen.z))
					st.add_vertex(v)
			faces.append_array([cen, p0, p1, p0, q1, p1, p0, q0, q1])
		st.generate_normals()
		var mi := MeshInstance3D.new()
		mi.name = "Pad_" + node
		mi.mesh = st.commit()
		mi.material_override = mats["pad"]
		mi.visibility_range_end = VIS_END
		add_child(mi)
		var body := StaticBody3D.new()
		body.collision_layer = 1 | 2
		body.collision_mask = 0
		body.set_meta("road_surface", world.roads[ends[0][0]].surface)
		var shape := ConcavePolygonShape3D.new()
		shape.set_faces(faces)
		shape.backface_collision = true
		var cs := CollisionShape3D.new()
		cs.shape = shape
		body.add_child(cs)
		mi.add_child(body)


func _build_multimeshes() -> void:
	if not pier_xforms.is_empty():
		var bm := BoxMesh.new()
		bm.size = Vector3(1, 1, 1)
		bm.material = concrete_mat
		_mm("BridgePiers", bm, pier_xforms, 2500.0)
	if not post_xforms.is_empty():
		var pm := BoxMesh.new()
		pm.size = Vector3(0.12, 1.0, 0.12)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.92, 0.92, 0.9)
		pm.material = mat
		_mm("ReflectorPosts", pm, post_xforms, 500.0)
	if not rail_post_xforms.is_empty():
		var rp := BoxMesh.new()
		rp.size = Vector3(0.1, 0.85, 0.1)
		rp.material = rail_mat
		_mm("RailPosts", rp, rail_post_xforms, 400.0)
	for p in tunnel_lights:
		var lamp := MeshInstance3D.new()
		var lb := BoxMesh.new()
		lb.size = Vector3(1.2, 0.12, 0.4)
		var lm := StandardMaterial3D.new()
		lm.emission_enabled = true
		lm.emission = Color(1.0, 0.8, 0.5)
		lm.emission_energy_multiplier = 4.0
		lb.material = lm
		lamp.mesh = lb
		lamp.position = p
		add_child(lamp)
		var ol := OmniLight3D.new()
		ol.light_color = Color(1.0, 0.82, 0.55)
		ol.omni_range = 18.0
		ol.light_energy = 2.0
		ol.position = Vector3(0, -0.4, 0)
		ol.distance_fade_enabled = true
		ol.distance_fade_begin = 150.0
		ol.distance_fade_length = 50.0
		lamp.add_child(ol)


func _mm(nm: String, mesh: Mesh, xforms: Array[Transform3D], vis: float) -> void:
	# split into spatial buckets so each MultiMesh can be culled
	var buckets: Dictionary = {}
	for t in xforms:
		var k := Vector2i(int(floor(t.origin.x / 400.0)), int(floor(t.origin.z / 400.0)))
		if not buckets.has(k):
			buckets[k] = []
		buckets[k].append(t)
	for k in buckets:
		var arr: Array = buckets[k]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mesh
		mm.instance_count = arr.size()
		for i in arr.size():
			mm.set_instance_transform(i, arr[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "%s_%d_%d" % [nm, k.x, k.y]
		mmi.multimesh = mm
		mmi.visibility_range_end = vis + 300.0
		add_child(mmi)
