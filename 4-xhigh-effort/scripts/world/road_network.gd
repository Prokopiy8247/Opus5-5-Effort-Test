class_name RoadNetwork
extends Node3D
## Builds road geometry and collision from baked road samples, and answers road queries
## (nearest road point, road frame, region of a road) for reset, traffic, map and GPS.

const PIECE := 64          # samples per mesh/collision piece (128 m)
const HASH_CELL := 48.0

var wd: WorldData
var roads: Array = []
var road_index := {}
var materials := {}
var concrete_mat: StandardMaterial3D
var tunnel_mat: StandardMaterial3D
var tunnel_light_mat: StandardMaterial3D
var rail_mat: StandardMaterial3D
var _hash := {}
var pillar_xforms: Array[Transform3D] = []
var abutment_xforms: Array[Transform3D] = []
var rail_post_xforms: Array[Transform3D] = []
var portal_xforms: Array[Transform3D] = []
var reflector_xforms: Array[Transform3D] = []
var sign_xforms := {"sign_speed": [], "sign_chevron": [], "sign_warning": [], "sign_direction": []}
var stats := {"pieces": 0, "tris": 0, "bridge_m": 0.0, "tunnel_m": 0.0, "rail_m": 0.0}


func setup(world_data: WorldData, road_shader: Shader) -> void:
	wd = world_data
	roads = wd.roads
	for i in roads.size():
		road_index[String(roads[i].id)] = i
	for cls: String in ["highway", "regional", "mountain", "village", "gravel", "dirt"]:
		var m := ShaderMaterial.new()
		m.shader = road_shader
		m.set_shader_parameter("road_class", ["highway", "regional", "mountain", "village", "gravel", "dirt"].find(cls))
		materials[cls] = m
	concrete_mat = StandardMaterial3D.new()
	concrete_mat.albedo_color = Color(0.62, 0.6, 0.57)
	concrete_mat.roughness = 0.9
	concrete_mat.uv1_triplanar = true
	concrete_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	tunnel_mat = StandardMaterial3D.new()
	tunnel_mat.albedo_color = Color(0.55, 0.54, 0.5)
	tunnel_mat.roughness = 0.85
	tunnel_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	tunnel_light_mat = StandardMaterial3D.new()
	tunnel_light_mat.albedo_color = Color(1.0, 0.85, 0.6)
	tunnel_light_mat.emission_enabled = true
	tunnel_light_mat.emission = Color(1.0, 0.8, 0.55)
	tunnel_light_mat.emission_energy_multiplier = 3.0
	rail_mat = StandardMaterial3D.new()
	rail_mat.albedo_color = Color(0.72, 0.73, 0.74)
	rail_mat.metallic = 0.8
	rail_mat.roughness = 0.35
	_build_hash()


## Builds every road piece. Heavy array work happens in worker threads (one group task).
func build_all() -> void:
	var jobs := []
	for ri in roads.size():
		var r: Dictionary = roads[ri]
		var n := (r.pts as PackedVector3Array).size()
		var trim := _trim_range(r)
		var k := trim.x
		while k < trim.y:
			var k2 := mini(k + PIECE, trim.y)
			jobs.append([ri, k, k2])
			k = k2
	var results := []
	results.resize(jobs.size())
	var task := WorkerThreadPool.add_group_task(func(i: int) -> void:
		results[i] = _build_piece(jobs[i][0], jobs[i][1], jobs[i][2]), jobs.size(), -1, true, "road pieces")
	WorkerThreadPool.wait_for_group_task_completion(task)
	for i in jobs.size():
		_instantiate_piece(jobs[i][0], results[i])
	_build_instances()


func _trim_range(r: Dictionary) -> Vector2i:
	var pts: PackedVector3Array = r.pts
	var n := pts.size()
	var a := 0
	var b := n - 1 if not r.closed else n
	if r.has("start_on"):
		var parent: Dictionary = roads[road_index[String(r.start_on.road)]]
		var pp := _point_at(parent, float(r.start_on.s))
		while a < n - 2 and Vector2(pts[a].x, pts[a].z).distance_to(Vector2(pp.x, pp.z)) < float(parent.half_w) - 0.6:
			a += 1
	if r.has("end_on"):
		var parent: Dictionary = roads[road_index[String(r.end_on.road)]]
		var pp := _point_at(parent, float(r.end_on.s))
		while b > a + 2 and Vector2(pts[b].x, pts[b].z).distance_to(Vector2(pp.x, pp.z)) < float(parent.half_w) - 0.6:
			b -= 1
	return Vector2i(a, b)


## Height of the parent road's surface under the first kept sample of a side road (minus 3 cm).
func _junction_height(r: Dictionary, at_start: bool, k: int) -> float:
	var key := "start_on" if at_start else "end_on"
	if not r.has(key):
		return INF
	var parent: Dictionary = roads[road_index[String(r[key].road)]]
	var ppts: PackedVector3Array = parent.pts
	var n := ppts.size()
	var x: Vector3 = (r.pts as PackedVector3Array)[k % (r.pts as PackedVector3Array).size()]
	var pi := clampi(int(float(r[key].s) / 2.0), 0, n - 1)
	var best := pi
	var bd := INF
	for o in range(-12, 13):
		var j := (pi + o + n) % n if parent.closed else clampi(pi + o, 0, n - 1)
		var d := Vector2(ppts[j].x - x.x, ppts[j].z - x.z).length_squared()
		if d < bd:
			bd = d
			best = j
	var f := _frame(parent, best)
	var pc: Vector3 = f[0]
	var t: Vector3 = f[1]
	var right := Vector3(-t.z, 0, t.x)
	var u := clampf((x - pc).dot(right), -float(parent.half_w), float(parent.half_w))
	var bank := (parent.bank as PackedFloat32Array)[best]
	return pc.y - u * tan(bank) - 0.03


func _point_at(r: Dictionary, s: float) -> Vector3:
	var pts: PackedVector3Array = r.pts
	return pts[clampi(int(s / 2.0), 0, pts.size() - 1)]


## Returns frame data at sample i: [centre, tangent, right(flat), up(banked)]
func _frame(r: Dictionary, i: int) -> Array:
	var pts: PackedVector3Array = r.pts
	var n := pts.size()
	var closed: bool = r.closed
	var ia := (i - 1 + n) % n if closed else maxi(i - 1, 0)
	var ib := (i + 1) % n if closed else mini(i + 1, n - 1)
	var c := pts[i % n]
	var t := pts[ib] - pts[ia]
	t.y = 0.0
	t = t.normalized()
	var right := Vector3(-t.z, 0.0, t.x)
	var bank := (r.bank as PackedFloat32Array)[i % n]
	var up := Vector3.UP.rotated(t, bank)
	var rb := right.rotated(t, bank)
	return [c, t, rb, up]


func _excluded(r: Dictionary, i: int) -> bool:
	# lower-priority road through an at-grade X junction: leave a gap where the other road lies
	for j: Dictionary in r.junctions:
		if j.type != "X":
			continue
		var other: Dictionary = roads[road_index[String(j.other)]]
		if _priority(other) <= _priority(r):
			continue
		if absf(float(j.s) - i * 2.0) < float(other.half_w) + 4.0:
			var op := _point_at(other, float(j.other_s))
			var p := (r.pts as PackedVector3Array)[i]
			if Vector2(p.x, p.z).distance_to(Vector2(op.x, op.z)) < float(other.half_w) - 1.0:
				return true
	return false


## True near a junction on this road: no parapets, rails or posts so side roads stay open.
func _junction_zone(r: Dictionary, i: int) -> bool:
	var s := i * 2.0
	var length: float = r.length
	for j: Dictionary in r.junctions:
		var other: Dictionary = roads[road_index[String(j.other)]]
		var clear := float(other.half_w) + 6.0
		var ds := absf(float(j.s) - s)
		if r.closed:
			ds = minf(ds, length - ds)
		if ds < clear:
			return true
	if r.has("start_on") and s < float(roads[road_index[String(r.start_on.road)]].half_w) + 8.0:
		return true
	if r.has("end_on") and length - s < float(roads[road_index[String(r.end_on.road)]].half_w) + 8.0:
		return true
	return false


## True if p lies on (or within margin of) the surface of a road other than ri.
func _on_other_road(ri: int, p: Vector3, margin := 1.5) -> bool:
	var ck := Vector2i(int(floor(p.x / HASH_CELL)), int(floor(p.z / HASH_CELL)))
	for oz in range(-1, 2):
		for ox in range(-1, 2):
			var key := ck + Vector2i(ox, oz)
			if not _hash.has(key):
				continue
			for code in (_hash[key] as PackedInt32Array):
				var oi := code / 100000
				if oi == ri:
					continue
				var q: Vector3 = (roads[oi].pts as PackedVector3Array)[code % 100000]
				var lim := float(roads[oi].half_w) + margin
				if Vector2(q.x - p.x, q.z - p.z).length_squared() < lim * lim and absf(q.y - p.y) < 6.0:
					return true
	return false


func _priority(r: Dictionary) -> int:
	return {"highway": 5, "regional": 4, "mountain": 3, "village": 2, "gravel": 1, "dirt": 0}.get(String(r["class"]), 0)


# ---------------------------------------------------------------- geometry
func _build_piece(ri: int, k0: int, k1: int) -> Dictionary:
	var r: Dictionary = roads[ri]
	var pts: PackedVector3Array = r.pts
	var n := pts.size()
	var kind: PackedByteArray = r.kind
	var hw: float = r.half_w
	var road := SurfaceTool.new()
	road.begin(Mesh.PRIMITIVE_TRIANGLES)
	var conc := SurfaceTool.new()
	conc.begin(Mesh.PRIMITIVE_TRIANGLES)
	var tun := SurfaceTool.new()
	tun.begin(Mesh.PRIMITIVE_TRIANGLES)
	var tl := SurfaceTool.new()
	tl.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rail := SurfaceTool.new()
	rail.begin(Mesh.PRIMITIVE_TRIANGLES)
	var col := PackedVector3Array()
	var has := {"road": false, "conc": false, "tun": false, "tl": false, "rail": false}
	var pillars: Array[Transform3D] = []
	var abutments: Array[Transform3D] = []
	var posts: Array[Transform3D] = []
	var portals: Array[Transform3D] = []
	var reflectors: Array[Transform3D] = []
	var signs := {"sign_speed": [], "sign_chevron": [], "sign_warning": [], "sign_direction": []}
	var last_warn := -1000.0
	var lat_surf := [-hw, -hw * 0.5, 0.0, hw * 0.5, hw]
	var prev := {}
	var trim := _trim_range(r)
	var first_k := trim.x
	var j_start := _junction_height(r, true, trim.x)
	var j_end := _junction_height(r, false, trim.y)
	var start_drop := 0.025
	var rail_l := [false, false]
	for k in range(k0, k1 + 1):
		var i := k % n
		if _excluded(r, i):
			prev = {}
			continue
		var f := _frame(r, i)
		var c: Vector3 = f[0]
		var t: Vector3 = f[1]
		var rb: Vector3 = f[2]
		var up: Vector3 = f[3]
		var s := k * 2.0
		var drop := 0.0
		# side-road mouths: sit just under the main road's banked surface, blend out over 12 m
		var jy := INF
		var jw := 0.0
		if j_start != INF and k - trim.x < 6:
			jy = j_start
			jw = 1.0 - float(k - trim.x) / 6.0
		elif j_end != INF and trim.y - k < 6:
			jy = j_end
			jw = 1.0 - float(trim.y - k) / 6.0
		if jy != INF:
			drop = (c.y - lerpf(c.y, jy, jw)) + (start_drop if jw > 0.6 else 0.0)
		var kd := kind[i]
		var sec := []
		for u: float in lat_surf:
			var crown := 0.035 * (1.0 - (u / hw) * (u / hw)) * (1.0 - jw)
			sec.append(c + rb * u + up * (crown - drop))
		var jzone := _junction_zone(r, i)
		var cur := {"sec": sec, "c": c, "rb": rb, "up": up, "s": s, "kind": kd, "t": t, "jz": jzone}
		# guard rails where the ground falls away beside the road (ground segments only)
		var rails := [false, false]
		if kd == 0 and String(r["class"]) != "dirt" and not jzone:
			for side in 2:
				var sg := -1.0 if side == 0 else 1.0
				var probe := c + Vector3(rb.x, 0, rb.z).normalized() * sg * (hw + 6.0)
				var gh := wd.height_at(probe.x, probe.z)
				rails[side] = c.y - gh > 2.6 or (String(r["class"]) in ["mountain", "highway"] and c.y - gh > 1.4)
				if rails[side] and _on_other_road(ri, c + Vector3(rb.x, 0, rb.z).normalized() * sg * (hw + 0.8)):
					rails[side] = false
		cur.rails = rails
		if not prev.is_empty():
			var ps: Array = prev.sec
			var s0: float = prev.s
			for q in 4:
				var a0: Vector3 = ps[q]
				var a1: Vector3 = ps[q + 1]
				var b0: Vector3 = sec[q]
				var b1: Vector3 = sec[q + 1]
				_quad(road, a0, a1, b1, b0, Vector2(lat_surf[q], s0), Vector2(lat_surf[q + 1], s0), Vector2(lat_surf[q + 1], s), Vector2(lat_surf[q], s))
				col.append_array([a0, b1, a1, a0, b0, b1])
			has.road = true
			var pk: int = prev.kind
			if kd == 0 and pk == 0:
				# verge + skirt down into the terrain on both sides
				for side in 2:
					var sg := -1.0 if side == 0 else 1.0
					var e0: Vector3 = ps[0 if side == 0 else 4]
					var e1: Vector3 = sec[0 if side == 0 else 4]
					var v0: Vector3 = prev.c + prev.rb * sg * (hw + 0.7) - prev.up * 0.06
					var v1: Vector3 = c + rb * sg * (hw + 0.7) - up * 0.06
					var k0v: Vector3 = prev.c + prev.rb * sg * (hw + 2.2) - Vector3.UP * 1.7
					var k1v: Vector3 = c + rb * sg * (hw + 2.2) - Vector3.UP * 1.7
					var u1 := sg * (hw + 0.7)
					var u2 := sg * (hw + 2.2)
					if side == 0:
						_quad(road, v0, e0, e1, v1, Vector2(u1, s0), Vector2(-hw, s0), Vector2(-hw, s), Vector2(u1, s))
						_quad(road, k0v, v0, v1, k1v, Vector2(u2, s0), Vector2(u1, s0), Vector2(u1, s), Vector2(u2, s))
					else:
						_quad(road, e0, v0, v1, e1, Vector2(hw, s0), Vector2(u1, s0), Vector2(u1, s), Vector2(hw, s))
						_quad(road, v0, k0v, k1v, v1, Vector2(u1, s0), Vector2(u2, s0), Vector2(u2, s), Vector2(u1, s))
					# the shoulder strip is drivable: wheels running wide keep support at road height
					col.append_array([e0, v1, v0, e0, e1, v1])
					# rails
					if rails[side] and (prev.rails as Array)[side]:
						var ra0: Vector3 = prev.c + prev.rb * sg * (hw + 0.8) + Vector3.UP * 0.55
						var ra1: Vector3 = c + rb * sg * (hw + 0.8) + Vector3.UP * 0.55
						var h2 := Vector3.UP * 0.32
						_quad(rail, ra0 - h2 * 0.5, ra1 - h2 * 0.5, ra1 + h2 * 0.5, ra0 + h2 * 0.5, Vector2(s0, 0), Vector2(s, 0), Vector2(s, 1), Vector2(s0, 1), true)
						col.append_array([ra0 - h2, ra1 - h2, ra1 + h2, ra0 - h2, ra1 + h2, ra0 + h2])
						col.append_array([ra0 - h2, ra1 + h2, ra1 - h2, ra0 - h2, ra0 + h2, ra1 + h2])
						has.rail = true
						if int(s) % 4 == 0:
							posts.append(Transform3D(Basis.looking_at(t, Vector3.UP), c + rb * sg * (hw + 0.9)))
			elif kd == 1 or pk == 1:
				# bridge deck: parapets (open at junction mouths) and underside
				for side in 2:
					if jzone or bool(prev.jz):
						continue
					var sg := -1.0 if side == 0 else 1.0
					var e0: Vector3 = ps[0 if side == 0 else 4]
					var e1: Vector3 = sec[0 if side == 0 else 4]
					if _on_other_road(ri, e0 + (e0 - prev.c).normalized() * 0.4) or _on_other_road(ri, e1 + (e1 - c).normalized() * 0.4):
						continue
					var o0: Vector3 = prev.c + prev.rb * sg * (hw + 0.45)
					var o1: Vector3 = c + rb * sg * (hw + 0.45)
					var top0: Vector3 = e0 + Vector3.UP * 0.95
					var top1: Vector3 = e1 + Vector3.UP * 0.95
					var otop0 := o0 + Vector3.UP * 0.95
					var otop1 := o1 + Vector3.UP * 0.95
					var bot0 := o0 - Vector3.UP * 1.5
					var bot1 := o1 - Vector3.UP * 1.5
					if side == 0:
						_quad(conc, e0, top0, top1, e1, Vector2(0, s0), Vector2(1, s0), Vector2(1, s), Vector2(0, s))
						_quad(conc, top0, otop0, otop1, top1, Vector2(0, s0), Vector2(1, s0), Vector2(1, s), Vector2(0, s))
						_quad(conc, otop0, bot0, bot1, otop1, Vector2(0, s0), Vector2(2, s0), Vector2(2, s), Vector2(0, s))
					else:
						_quad(conc, e1, top1, top0, e0, Vector2(0, s), Vector2(1, s), Vector2(1, s0), Vector2(0, s0))
						_quad(conc, top1, otop1, otop0, top0, Vector2(0, s), Vector2(1, s), Vector2(1, s0), Vector2(0, s0))
						_quad(conc, otop1, bot1, bot0, otop0, Vector2(0, s), Vector2(2, s), Vector2(2, s0), Vector2(0, s0))
					col.append_array([e0, top1, top0, e0, e1, top1, e0, top0, top1, e0, top1, e1])
				var l0: Vector3 = prev.c - prev.rb * (hw + 0.45) - Vector3.UP * 1.5
				var r0: Vector3 = prev.c + prev.rb * (hw + 0.45) - Vector3.UP * 1.5
				var l1: Vector3 = c - rb * (hw + 0.45) - Vector3.UP * 1.5
				var r1: Vector3 = c + rb * (hw + 0.45) - Vector3.UP * 1.5
				_quad(conc, l0, l1, r1, r0, Vector2(0, s0), Vector2(0, s), Vector2(1, s), Vector2(1, s0))
				has.conc = true
				if kd != pk:
					# abutment block where the deck meets the embankment
					var ab_c: Vector3 = c if kd == 0 else prev.c
					var gh0 := wd.height_at(ab_c.x, ab_c.z)
					var hh := maxf(ab_c.y - gh0 + 2.0, 3.0)
					abutments.append(Transform3D(Basis.looking_at(t, Vector3.UP) * Basis.from_scale(Vector3((hw + 1.0) / 4.0, hh / 10.0, 1.6)), Vector3(ab_c.x, ab_c.y - hh + 0.2, ab_c.z)))
				if kd == 1 and int(s) % 30 == 0:
					var gh := wd.height_at(c.x, c.z)
					var hgt := c.y - 1.5 - gh
					if hgt > 2.0:
						pillars.append(Transform3D(Basis.looking_at(t, Vector3.UP) * Basis.from_scale(Vector3(hw / 4.0, hgt / 10.0, 1.0)), Vector3(c.x, gh, c.z)))
			if kd == 2 or pk == 2:
				# tunnel tube (inward facing) with a ceiling light strip
				var prof := [Vector2(-hw - 0.9, -0.1), Vector2(-hw - 0.9, 4.4), Vector2(-hw * 0.55, 6.5), Vector2(0.0, 7.0),
					Vector2(hw * 0.55, 6.5), Vector2(hw + 0.9, 4.4), Vector2(hw + 0.9, -0.1)]
				for q in prof.size() - 1:
					var pa: Vector2 = prof[q]
					var pb: Vector2 = prof[q + 1]
					var a0: Vector3 = prev.c + prev.rb * pa.x + Vector3.UP * pa.y
					var a1: Vector3 = prev.c + prev.rb * pb.x + Vector3.UP * pb.y
					var b0: Vector3 = c + rb * pa.x + Vector3.UP * pa.y
					var b1: Vector3 = c + rb * pb.x + Vector3.UP * pb.y
					_quad(tun, a1, a0, b0, b1, Vector2(pb.x, s0), Vector2(pa.x, s0), Vector2(pa.x, s), Vector2(pb.x, s))
					col.append_array([a0, a1, b1, a0, b1, b0])
				has.tun = true
				if int(s) % 4 != 0:
					var la0: Vector3 = prev.c + Vector3.UP * 6.95 - prev.rb * 0.25
					var la1: Vector3 = prev.c + Vector3.UP * 6.95 + prev.rb * 0.25
					var lb0: Vector3 = c + Vector3.UP * 6.95 - rb * 0.25
					var lb1: Vector3 = c + Vector3.UP * 6.95 + rb * 0.25
					_quad(tl, la1, la0, lb0, lb1, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO)
					has.tl = true
				if pk != kd:
					var into := t if kd == 2 else -t
					# the Blender portal is authored for a tube half width of 5.4 m
					portals.append(Transform3D(Basis.looking_at(-into, Vector3.UP) * Basis.from_scale(Vector3((hw + 0.9) / 5.4, 1.0, 1.0)), (prev.c + c) * 0.5))
			# reflector posts on rural roads
			if kd == 0 and not jzone and int(s) % 50 == 0 and String(r["class"]) in ["regional", "mountain", "highway"]:
				for side in 2:
					var sg := -1.0 if side == 0 else 1.0
					if not rails[side]:
						reflectors.append(Transform3D(Basis.looking_at(t, Vector3.UP), c + Vector3(rb.x, 0, rb.z).normalized() * sg * (hw + 1.1)))
			if kd == 0:
				last_warn = _place_signs(r, i, k, s, c, t, rb, hw, jzone, trim, j_start != INF, j_end != INF, signs, last_warn)
		prev = cur
	var out := {"col": col, "pillars": pillars, "abutments": abutments, "posts": posts, "portals": portals, "reflectors": reflectors, "signs": signs}
	if has.road:
		road.generate_normals()
		out.road = road.commit_to_arrays()
	if has.conc:
		conc.generate_normals()
		out.conc = conc.commit_to_arrays()
	if has.tun:
		tun.generate_normals()
		out.tun = tun.commit_to_arrays()
	if has.tl:
		tl.generate_normals()
		out.tl = tl.commit_to_arrays()
	if has.rail:
		rail.generate_normals()
		out.rail = rail.commit_to_arrays()
	return out


func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, ua: Vector2, ub: Vector2, uc: Vector2, ud: Vector2, double := false) -> void:
	# a-b-c-d counter-clockwise when seen from the front: emit clockwise triangles for Godot
	st.set_uv(ua)
	st.add_vertex(a)
	st.set_uv(uc)
	st.add_vertex(c)
	st.set_uv(ub)
	st.add_vertex(b)
	st.set_uv(ua)
	st.add_vertex(a)
	st.set_uv(ud)
	st.add_vertex(d)
	st.set_uv(uc)
	st.add_vertex(c)
	if double:
		_quad(st, b, a, d, c, ub, ua, ud, uc)


func _instantiate_piece(ri: int, res: Dictionary) -> void:
	var r: Dictionary = roads[ri]
	var mesh := ArrayMesh.new()
	if res.has("road"):
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, res.road)
		mesh.surface_set_material(mesh.get_surface_count() - 1, materials[String(r["class"])])
	if res.has("conc"):
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, res.conc)
		mesh.surface_set_material(mesh.get_surface_count() - 1, concrete_mat)
	if res.has("tun"):
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, res.tun)
		mesh.surface_set_material(mesh.get_surface_count() - 1, tunnel_mat)
	if res.has("tl"):
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, res.tl)
		mesh.surface_set_material(mesh.get_surface_count() - 1, tunnel_light_mat)
	if res.has("rail"):
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, res.rail)
		mesh.surface_set_material(mesh.get_surface_count() - 1, rail_mat)
	if mesh.get_surface_count() == 0:
		return
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.visibility_range_end = 2600.0 if String(r["class"]) in ["highway", "regional"] else 1600.0
	mi.visibility_range_end_margin = 100.0
	mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	add_child(mi)
	var col: PackedVector3Array = res.col
	if col.size() > 0:
		var body := StaticBody3D.new()
		body.collision_layer = 1
		body.collision_mask = 0
		body.set_meta("surface", int(r.surface))
		body.set_meta("road", String(r.id))
		var shape := ConcavePolygonShape3D.new()
		shape.backface_collision = true
		shape.set_faces(col)
		var cs := CollisionShape3D.new()
		cs.shape = shape
		body.add_child(cs)
		add_child(body)
	stats.pieces += 1
	for x: Transform3D in res.pillars:
		pillar_xforms.append(x)
	for x: Transform3D in res.abutments:
		abutment_xforms.append(x)
	for x: Transform3D in res.posts:
		rail_post_xforms.append(x)
	for x: Transform3D in res.portals:
		portal_xforms.append(x)
	for x: Transform3D in res.reflectors:
		reflector_xforms.append(x)
	for key: String in res.signs:
		(sign_xforms[key] as Array).append_array(res.signs[key])


## Instanced repeated objects (code stand-ins replaced by Blender kit meshes when available).
func _build_instances() -> void:
	var kit: Node = get_parent().get("kit") if get_parent() != null else null
	_multimesh("Pillars", _kit_mesh(kit, "bridge_pillar", _box_mesh(Vector3(8.0, 10.0, 2.2), Vector3(0, 5.0, 0), concrete_mat)), pillar_xforms, 2500.0)
	_multimesh("Abutments", _kit_mesh(kit, "bridge_abutment", _box_mesh(Vector3(8.0, 10.0, 2.2), Vector3(0, 5.0, 0), concrete_mat)), abutment_xforms, 2500.0)
	_multimesh("RailPosts", _kit_mesh(kit, "rail_post", _box_mesh(Vector3(0.12, 0.8, 0.12), Vector3(0, 0.4, 0), rail_mat)), rail_post_xforms, 400.0)
	_multimesh("Reflectors", _kit_mesh(kit, "reflector_post", _box_mesh(Vector3(0.12, 1.0, 0.12), Vector3(0, 0.5, 0), concrete_mat)), reflector_xforms, 350.0)
	for key: String in sign_xforms:
		var xs: Array[Transform3D] = []
		xs.assign(sign_xforms[key])
		_multimesh(key.capitalize().replace(" ", ""), _kit_mesh(kit, key, _box_mesh(Vector3(0.6, 2.4, 0.08), Vector3(0, 1.2, 0), rail_mat)), xs, 450.0)
	for x in portal_xforms:
		var pm: Mesh = _kit_mesh(kit, "tunnel_portal", _box_mesh(Vector3(16.0, 2.0, 1.5), Vector3(0, 8.0, 0), concrete_mat))
		var mi := MeshInstance3D.new()
		mi.mesh = pm
		mi.transform = x
		add_child(mi)
		mi.create_trimesh_collision()


## Signed heading change over +-span samples around i (positive = turning left).
func _turn(r: Dictionary, i: int, span: int) -> float:
	var p: PackedVector3Array = r.pts
	var n := p.size()
	var closed: bool = r.closed
	var a := i - span
	var b := i + span
	if not closed and (a < 1 or b > n - 2):
		return 0.0
	var d0 := p[(a + 1 + n) % n] - p[(a - 1 + n) % n]
	var d1 := p[(b + 1) % n] - p[(b - 1 + n) % n]
	return Vector2(d0.x, d0.z).normalized().angle_to(Vector2(d1.x, d1.z).normalized()) * -1.0


## Speed limits each way every km, chevrons on the outside of tight bends, warning triangles before
## bends and direction boards ahead of junctions. Returns the updated last-warning position.
func _place_signs(r: Dictionary, i: int, k: int, s: float, c: Vector3, t: Vector3, rb: Vector3, hw: float, jzone: bool,
		trim: Vector2i, joins_start: bool, joins_end: bool, signs: Dictionary, last_warn: float) -> float:
	var cls := String(r["class"])
	var right := Vector3(rb.x, 0.0, rb.z).normalized()
	var fwd := Basis.looking_at(-t, Vector3.UP)    # faces traffic travelling along +t
	var back := Basis.looking_at(t, Vector3.UP)    # faces traffic travelling along -t
	var at := func(off: float) -> Vector3:
		var p := c + right * off
		p.y = clampf(wd.height_at(p.x, p.z), c.y - 1.2, c.y + 0.6)
		return p
	if k == trim.x + 30 and joins_start:
		(signs.sign_direction as Array).append(Transform3D(back, at.call(-(hw + 2.4))))
	if k == trim.y - 30 and joins_end:
		(signs.sign_direction as Array).append(Transform3D(fwd, at.call(hw + 2.4)))
	if jzone or cls == "dirt":
		return last_warn
	var si := int(s)
	if si % 1000 == 300:
		(signs.sign_speed as Array).append(Transform3D(fwd, at.call(hw + 1.7)))
	elif si % 1000 == 800:
		(signs.sign_speed as Array).append(Transform3D(back, at.call(-(hw + 1.7))))
	if si % 14 == 0:
		var turn := _turn(r, i, 10)
		if absf(turn) > 0.55:
			# outside of the bend: right of travel for a left-hander
			(signs.sign_chevron as Array).append(Transform3D(fwd, at.call((1.0 if turn > 0.0 else -1.0) * (hw + 1.4))))
	if si % 10 == 0 and s - last_warn > 160.0 and absf(_turn(r, i, 10)) < 0.25:
		if absf(_turn(r, i + 45, 10)) > 0.6:
			(signs.sign_warning as Array).append(Transform3D(fwd, at.call(hw + 1.7)))
			return s
		if absf(_turn(r, i - 45, 10)) > 0.6:
			(signs.sign_warning as Array).append(Transform3D(back, at.call(-(hw + 1.7))))
			return s
	return last_warn


func _kit_mesh(kit: Node, name: String, fallback: Mesh) -> Mesh:
	if kit != null and kit.has_method("mesh"):
		var m: Mesh = kit.mesh(name)
		if m != null:
			return m
	return fallback


func _box_mesh(size: Vector3, offset: Vector3, mat: Material) -> Mesh:
	var bm := BoxMesh.new()
	bm.size = size
	var st := SurfaceTool.new()
	st.create_from(bm, 0)
	var arr := st.commit_to_arrays()
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	for i in v.size():
		v[i] += offset
	arr[Mesh.ARRAY_VERTEX] = v
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	m.surface_set_material(0, mat)
	return m


func _multimesh(n: String, mesh: Mesh, xforms: Array[Transform3D], vis: float) -> void:
	if xforms.is_empty():
		return
	# split into spatial cells so visibility ranges can cull
	var cells := {}
	for x in xforms:
		var key := Vector2i(int(floor(x.origin.x / 512.0)), int(floor(x.origin.z / 512.0)))
		if not cells.has(key):
			cells[key] = []
		(cells[key] as Array).append(x)
	for key: Vector2i in cells:
		var list: Array = cells[key]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mesh
		mm.instance_count = list.size()
		for i in list.size():
			mm.set_instance_transform(i, list[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "%s_%d_%d" % [n, key.x, key.y]
		mmi.multimesh = mm
		mmi.visibility_range_end = vis
		mmi.visibility_range_end_margin = 50.0
		mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		add_child(mmi)


# ---------------------------------------------------------------- queries
func _build_hash() -> void:
	for ri in roads.size():
		var pts: PackedVector3Array = roads[ri].pts
		for i in pts.size():
			var key := Vector2i(int(floor(pts[i].x / HASH_CELL)), int(floor(pts[i].z / HASH_CELL)))
			if not _hash.has(key):
				_hash[key] = PackedInt32Array()
			var arr: PackedInt32Array = _hash[key]
			arr.append(ri * 100000 + i)
			_hash[key] = arr


## {road: int, i: int, pos: Vector3, dist: float} of the closest road sample, or {} if none within radius.
func nearest(p: Vector3, radius := 200.0, filter := "") -> Dictionary:
	var best := {}
	var bd := radius * radius
	var r := int(ceil(radius / HASH_CELL))
	var ck := Vector2i(int(floor(p.x / HASH_CELL)), int(floor(p.z / HASH_CELL)))
	for oz in range(-r, r + 1):
		for ox in range(-r, r + 1):
			var key := ck + Vector2i(ox, oz)
			if not _hash.has(key):
				continue
			for code in (_hash[key] as PackedInt32Array):
				var ri := code / 100000
				var i := code % 100000
				if filter != "" and String(roads[ri]["class"]) != filter:
					continue
				var q: Vector3 = (roads[ri].pts as PackedVector3Array)[i]
				var d := Vector2(q.x - p.x, q.z - p.z).length_squared()
				if d < bd:
					bd = d
					best = {"road": ri, "i": i, "pos": q, "dist": sqrt(d)}
	return best


## Transform on the right-hand lane at sample i of road ri facing the travel direction.
func lane_transform(ri: int, i: int, reverse := false) -> Transform3D:
	var r: Dictionary = roads[ri]
	var f := _frame(r, i)
	var t: Vector3 = f[1] * (-1.0 if reverse else 1.0)
	var right := Vector3(-t.z, 0, t.x)
	var lane := float(r.lane_w) * (0.5 if int(r.lanes) == 1 else 1.5) + float(r.median) * 0.5
	var pos: Vector3 = f[0] + right * lane
	return Transform3D(Basis.looking_at(t, Vector3.UP), pos)


func road_name_at(p: Vector3) -> String:
	var n := nearest(p, 30.0)
	return String(roads[n.road].name) if not n.is_empty() else ""
