class_name RoadBuilder
extends Node3D
## Builds road ribbons (render + collision), bridges, tunnel shells and road furniture
## from WorldGen road data. Everything is static and built once at load.

const PIECE := 50 # samples per mesh piece (200 m)
var world: WorldGen
var materials: Dictionary = {}

func build(w: WorldGen) -> void:
	world = w
	var concrete := StandardMaterial3D.new(); concrete.albedo_color = Color(0.62, 0.6, 0.57); concrete.roughness = 0.9
	materials["concrete"] = concrete
	var tunnel_mat := StandardMaterial3D.new(); tunnel_mat.albedo_color = Color(0.45, 0.44, 0.42); tunnel_mat.roughness = 0.95
	tunnel_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	materials["tunnel"] = tunnel_mat
	var lamp := StandardMaterial3D.new(); lamp.albedo_color = Color(1, 0.85, 0.6); lamp.emission_enabled = true
	lamp.emission = Color(1, 0.8, 0.5); lamp.emission_energy_multiplier = 3.0
	materials["lamp"] = lamp
	for ri in world.roads.size():
		_build_road(ri)

func _road_material(road: Dictionary) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = preload("res://shaders/road.gdshader")
	m.set_shader_parameter("half_width", road.width * 0.5)
	var s: int = road.surface
	match s:
		WorldGen.Surface.ASPHALT:
			m.set_shader_parameter("kind", 0)
		WorldGen.Surface.CONCRETE:
			m.set_shader_parameter("kind", 1); m.set_shader_parameter("base_color", Color(0.42, 0.41, 0.39))
		WorldGen.Surface.DIRT:
			m.set_shader_parameter("kind", 2); m.set_shader_parameter("base_color", Color(0.45, 0.32, 0.2)); m.set_shader_parameter("shoulder_color", Color(0.5, 0.4, 0.28))
		WorldGen.Surface.GRAVEL:
			m.set_shader_parameter("kind", 3); m.set_shader_parameter("base_color", Color(0.48, 0.45, 0.4)); m.set_shader_parameter("shoulder_color", Color(0.38, 0.4, 0.3))
		WorldGen.Surface.SAND:
			m.set_shader_parameter("kind", 4); m.set_shader_parameter("base_color", Color(0.78, 0.66, 0.46)); m.set_shader_parameter("shoulder_color", Color(0.8, 0.7, 0.5))
	m.set_shader_parameter("multi_lane", road.cls == "highway")
	return m

func _frame(ri: int, i: int) -> Dictionary:
	var p := world.road_point(ri, i)
	var d := world.road_dir(ri, i)
	var flat := Vector3(d.x, 0, d.z).normalized()
	var right := flat.cross(Vector3.UP).normalized()
	var curv: float = world.roads[ri].curv[posmod(i, world.roads[ri].pts.size())]
	var bank := clampf(-curv * 6.0, -0.07, 0.07)
	return {"p": p, "d": d, "r": right, "bank": bank}

func _build_road(ri: int) -> void:
	var road: Dictionary = world.roads[ri]
	var pts: PackedVector3Array = road.pts
	var n := pts.size()
	var closed: bool = road.closed
	var hw: float = road.width * 0.5
	var shoulder := 1.4 if road.surface <= WorldGen.Surface.CONCRETE else 0.6
	var mat := _road_material(road)
	var last := n if closed else n - 1
	var body := StaticBody3D.new()
	body.name = "Road_%d" % ri
	body.set_meta("surface", road.surface)
	body.set_meta("road", ri)
	body.collision_layer = 1
	add_child(body)
	var rail_xf: Array[Transform3D] = []
	var post_xf: Array[Transform3D] = []
	var pillar_xf: Array[Transform3D] = []
	var lamp_xf: Array[Transform3D] = []
	var start := 0
	while start < last:
		var end := mini(start + PIECE, last)
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var col_faces := PackedVector3Array()
		var prev: Array = []
		for i in range(start, end + 1):
			var f := _frame(ri, i)
			var p: Vector3 = f.p; var r: Vector3 = f.r; var bank: float = f.bank
			var v := float(i) * WorldGen.SAMPLE_STEP
			var bridge: bool = road.bridge[posmod(i, n)] == 1
			var skirt := 1.2 if bridge else 3.0
			var lat := [-hw - shoulder, -hw, 0.0, hw, hw + shoulder]
			var row: Array = []
			for x: float in lat:
				row.append(p + r * x + Vector3.UP * (x * sin(bank) + 0.02))
			row.push_front(row[0] + Vector3.DOWN * skirt + r * -0.5)
			row.push_back(row[row.size() - 1] + Vector3.DOWN * skirt + r * 0.5)
			var uvx := [-hw - shoulder - 0.5, -hw - shoulder, -hw, 0.0, hw, hw + shoulder, hw + shoulder + 0.5]
			if not prev.is_empty():
				for k in row.size() - 1:
					var a: Vector3 = prev[0][k]; var b: Vector3 = prev[0][k + 1]
					var c: Vector3 = row[k]; var dd: Vector3 = row[k + 1]
					var va: float = prev[1]
					_quad(st, a, b, c, dd, Vector2(uvx[k], va), Vector2(uvx[k + 1], va), Vector2(uvx[k], v), Vector2(uvx[k + 1], v))
					if k >= 1 and k <= 4:
						col_faces.append_array([a, c, b, b, c, dd])
			prev = [row, v]
			# furniture
			if i % 1 == 0 and i < last:
				_furniture(ri, i, f, hw, shoulder, rail_xf, post_xf, pillar_xf, lamp_xf)
		st.generate_normals()
		var mi := MeshInstance3D.new()
		mi.mesh = st.commit()
		mi.material_override = mat
		mi.visibility_range_end = 2600.0
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		body.add_child(mi)
		var cs := CollisionShape3D.new()
		var sh := ConcavePolygonShape3D.new()
		sh.set_faces(col_faces)
		sh.backface_collision = true
		cs.shape = sh
		body.add_child(cs)
		start = end
	_tunnels(ri)
	_multimesh("GuardRail", rail_xf, Vector3(0.12, 0.35, 4.0), Color(0.75, 0.76, 0.78), 900.0)
	_rail_collision(rail_xf)
	_multimesh("RoadPost", post_xf, Vector3(0.12, 1.0, 0.12), Color(0.95, 0.95, 0.95), 500.0)
	_multimesh("BridgePillar", pillar_xf, Vector3(1.6, 1.0, 1.6), Color(0.6, 0.58, 0.55), 2000.0)
	_multimesh("StreetLamp", lamp_xf, Vector3(0.2, 7.0, 0.2), Color(0.3, 0.3, 0.32), 900.0)

func _rail_collision(xf: Array[Transform3D]) -> void:
	if xf.is_empty(): return
	var body := StaticBody3D.new()
	body.name = "RailCollision"
	body.set_meta("surface", WorldGen.Surface.CONCRETE)
	var pm := PhysicsMaterial.new(); pm.friction = 0.2
	body.physics_material_override = pm
	var shape := BoxShape3D.new(); shape.size = Vector3(0.3, 1.4, 4.1)
	for t in xf:
		var cs := CollisionShape3D.new()
		cs.shape = shape
		cs.transform = t
		body.add_child(cs)
	add_child(body)

func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, ua: Vector2, ub: Vector2, uc: Vector2, ud: Vector2) -> void:
	st.set_uv(ua); st.add_vertex(a)
	st.set_uv(uc); st.add_vertex(c)
	st.set_uv(ub); st.add_vertex(b)
	st.set_uv(ub); st.add_vertex(b)
	st.set_uv(uc); st.add_vertex(c)
	st.set_uv(ud); st.add_vertex(d)

func _furniture(ri: int, i: int, f: Dictionary, hw: float, shoulder: float, rails: Array[Transform3D], posts: Array[Transform3D], pillars: Array[Transform3D], lamps: Array[Transform3D]) -> void:
	var road: Dictionary = world.roads[ri]
	var n: int = road.pts.size()
	var p: Vector3 = f.p; var r: Vector3 = f.r; var d: Vector3 = f.d
	var bridge: bool = road.bridge[i % n] == 1
	var tunnel: bool = road.tunnel[i % n] == 1
	var basis := Basis(r, Vector3.UP, -d.normalized())
	var land := world.water_carve(p.x, p.z, world.land_height(p.x, p.z))
	var drop := p.y - land
	var curv: float = road.curv[i % n]
	for side in [-1.0, 1.0]:
		var edge: Vector3 = p + r * side * (hw + shoulder - 0.2)
		var outer_curve: bool = absf(curv) > 0.006 and signf(-curv) == side
		if bridge or (not tunnel and (drop > 2.5 or outer_curve)):
			# kit meshes are authored with their long axis along -Z (forward)
			rails.append(Transform3D(basis, edge + Vector3.UP * 0.55))
		elif i % 12 == 0 and not tunnel:
			posts.append(Transform3D(basis, edge + Vector3.UP * 0.5))
	if bridge and i % 6 == 0:
		var h := maxf(p.y - land - 1.0, 1.0)
		pillars.append(Transform3D(Basis(r, Vector3.UP, -d.normalized()).scaled(Vector3(1, h, 1)), p + Vector3.DOWN * (1.0 + h * 0.5)))
	if road.cls == "highway" and i % 15 == 0 and not tunnel:
		lamps.append(Transform3D(Basis(r, Vector3.UP, -d.normalized()), p + r * (hw + shoulder + 0.6)))

func _multimesh(kit_name: String, xf: Array[Transform3D], size: Vector3, color: Color, vis: float) -> void:
	if xf.is_empty(): return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = Kit.mesh(kit_name, size, color)
	mm.instance_count = xf.size()
	for k in xf.size(): mm.set_instance_transform(k, xf[k])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.name = kit_name
	add_child(mmi)

func _tunnels(ri: int) -> void:
	var road: Dictionary = world.roads[ri]
	var n: int = road.pts.size()
	var hw: float = road.width * 0.5 + 1.8
	var tun: PackedByteArray = road.tunnel
	var i := 0
	while i < n:
		if tun[i] == 0:
			i += 1; continue
		var j := i
		while j < n and tun[j] == 1: j += 1
		_tunnel_shell(ri, i, j, hw)
		i = j

func _tunnel_shell(ri: int, a: int, b: int, hw: float) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var prof: Array[Vector2] = []
	var segs := 10
	for k in segs + 1:
		var ang := PI * float(k) / segs
		prof.append(Vector2(cos(ang) * hw, -0.5 + sin(ang) * 6.5))
	var prev: Array = []
	var col_faces := PackedVector3Array()
	var lights: Array[Transform3D] = []
	for i in range(a, b + 1):
		var f := _frame(ri, i)
		var p: Vector3 = f.p; var r: Vector3 = f.r
		var row: Array = []
		for q in prof: row.append(p + r * q.x + Vector3.UP * q.y)
		if not prev.is_empty():
			for k in segs:
				_quad(st, prev[k], prev[k + 1], row[k], row[k + 1], Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO)
				col_faces.append_array([prev[k], row[k], prev[k + 1], prev[k + 1], row[k], row[k + 1]])
		prev = row
		if i % 5 == 0:
			lights.append(Transform3D(Basis(r, Vector3.UP, -(f.d as Vector3).normalized()), p + Vector3.UP * 5.8))
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = materials["tunnel"]
	mi.visibility_range_end = 1500.0
	add_child(mi)
	var body := StaticBody3D.new()
	body.set_meta("surface", WorldGen.Surface.CONCRETE)
	var cs := CollisionShape3D.new()
	var sh := ConcavePolygonShape3D.new(); sh.set_faces(col_faces); sh.backface_collision = true
	cs.shape = sh; body.add_child(cs); add_child(body)
	for end in [a, b]:
		var f := _frame(ri, end)
		var portal := MeshInstance3D.new()
		portal.mesh = Kit.mesh("TunnelPortal", Vector3(hw * 2.0 + 4.0, 9.0, 1.5), Color(0.55, 0.53, 0.5))
		portal.transform = Transform3D(Basis(f.r, Vector3.UP, -(f.d as Vector3).normalized()).scaled_local(Vector3(hw / 7.0, 1.0, 1.0)), f.p)
		add_child(portal)
	_multimesh("TunnelLight", lights, Vector3(0.4, 0.15, 1.2), Color(1, 0.9, 0.7), 600.0)
