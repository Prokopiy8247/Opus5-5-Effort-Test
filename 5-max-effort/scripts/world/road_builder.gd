class_name RoadBuilder
extends RefCounted
## Turns baked road samples into geometry for one terrain chunk: road ribbons (UV.x = lateral
## metres, UV.y = distance), bridge parapets/undersides + pillar transforms, tunnel tubes with
## light strips and portals, guard rails + post transforms, and collision faces per surface.
## Pure data in, arrays out: safe to run on WorkerThreadPool threads.

const STEP := 2.0


class MeshData:
	extends RefCounted
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()

	func add_vertex(v: Vector3, n: Vector3, uv: Vector2) -> int:
		verts.append(v)
		normals.append(n)
		uvs.append(uv)
		return verts.size() - 1

	func quad(a: int, b: int, c: int, d: int) -> void:
		# a,b,c,d in clockwise order seen from the front side
		indices.append(a)
		indices.append(b)
		indices.append(c)
		indices.append(a)
		indices.append(c)
		indices.append(d)

	func to_arrays() -> Array:
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = verts
		arr[Mesh.ARRAY_NORMAL] = normals
		arr[Mesh.ARRAY_TEX_UV] = uvs
		arr[Mesh.ARRAY_INDEX] = indices
		return arr


static func _mesh(out: Dictionary, key: String) -> MeshData:
	var meshes: Dictionary = out["meshes"]
	if not meshes.has(key):
		meshes[key] = MeshData.new()
	return meshes[key]


static func _faces(out: Dictionary, key: String) -> PackedVector3Array:
	var col: Dictionary = out["collision"]
	if not col.has(key):
		col[key] = PackedVector3Array()
	return col[key]


static func _add_faces(out: Dictionary, key: String, m: MeshData, first_index: int) -> void:
	var f := _faces(out, key)
	for t in range(first_index, m.indices.size()):
		f.append(m.verts[m.indices[t]])
	out["collision"][key] = f


static func build(data: WorldData, runs: Array) -> Dictionary:
	var out := {"meshes": {}, "collision": {}, "pillars": [], "posts": [], "portals": []}
	for run in runs:
		_build_run(data, run, out)
	return out


static func _pt(r: Dictionary, i: int) -> Vector3:
	return Vector3((r["x"] as PackedFloat32Array)[i], (r["y"] as PackedFloat32Array)[i], (r["z"] as PackedFloat32Array)[i])


static func _build_run(data: WorldData, run: Dictionary, out: Dictionary) -> void:
	var r: Dictionary = data.roads[run["road"]]
	var n: int = (r["x"] as PackedFloat32Array).size()
	var closed: bool = r["closed"]
	var bank_arr: PackedFloat32Array = r["bank"]
	var flags: PackedInt32Array = r["flags"]
	var a: int = run["a"]
	var b: int = run["b"]
	var half := float(r["width"]) * 0.5
	var surface: String = r["surface"]
	var paved := surface == "asphalt" or surface == "concrete"
	var cls: String = r["class"]
	var key := "%s_%s" % [cls, surface]
	var lats: PackedFloat32Array
	var dys: PackedFloat32Array
	if paved:
		var crown := 0.0 if cls == "highway" else 0.035
		lats = PackedFloat32Array([-half - 0.9, -half - 0.3, -half, 0.0, half, half + 0.3, half + 0.9])
		dys = PackedFloat32Array([-0.65, -0.07, 0.0, crown, 0.0, -0.07, -0.65])
	else:
		lats = PackedFloat32Array([-half - 0.8, -half, -0.9, 0.0, 0.9, half, half + 0.8])
		dys = PackedFloat32Array([-0.45, 0.0, 0.01, 0.03, 0.01, 0.0, -0.45])
	var cols := lats.size()
	var m := _mesh(out, key)
	var first_vertex := m.verts.size()
	var first_index := m.indices.size()
	var count := b - a + 1
	var frames: Array = []
	for k in count:
		var i := a + k
		if closed:
			i = posmod(i, n)
		elif i < 0 or i >= n:
			continue
		var p := _pt(r, i)
		var ip := posmod(i - 1, n) if closed else maxi(i - 1, 0)
		var inx := posmod(i + 1, n) if closed else mini(i + 1, n - 1)
		var fwd := (_pt(r, inx) - _pt(r, ip)).normalized()
		var flat := Vector3(fwd.x, 0.0, fwd.z).normalized()
		var right := flat.cross(Vector3.UP).normalized()
		var tb := tan(bank_arr[i])
		var f := flags[i]
		var s := float(a + k) * STEP
		# junction ends: push the minor road 1 m into the major road, slightly lower
		if not closed and (f & WorldData.F_JUNCTION) and (i == 0 or i == n - 1):
			var out_dir := -fwd if i == 0 else fwd
			p += out_dir * 1.0 - Vector3.UP * 0.025
		frames.append({"p": p, "fwd": fwd, "right": right, "tb": tb, "f": f, "s": s, "i": i})
	if frames.size() < 2:
		return
	for fr in frames:
		var p: Vector3 = fr["p"]
		var right: Vector3 = fr["right"]
		var fwd: Vector3 = fr["fwd"]
		var tb: float = fr["tb"]
		var f: int = fr["f"]
		var structure := (f & (WorldData.F_BRIDGE | WorldData.F_TUNNEL)) != 0
		var rb := (right - Vector3.UP * tb).normalized()
		var nrm := rb.cross(fwd).normalized()
		for j in cols:
			var lat := lats[j]
			var dy := dys[j]
			if structure and (j == 0 or j == cols - 1):
				dy = 0.0
				lat = signf(lat) * (half + 0.3)
			var v := p + right * lat + Vector3.UP * (dy - lat * tb)
			var vn := nrm
			if (j == 0 or j == cols - 1) and not structure:
				vn = (Vector3.UP * 0.7 + right * signf(lat) * 0.7).normalized()
			m.add_vertex(v, vn, Vector2(lat, fr["s"]))
	for k in frames.size() - 1:
		for j in cols - 1:
			var A := first_vertex + k * cols + j
			var B := first_vertex + (k + 1) * cols + j
			var C := first_vertex + (k + 1) * cols + j + 1
			var D := first_vertex + k * cols + j + 1
			m.quad(A, B, C, D)
	_add_faces(out, surface, m, first_index)
	# structures along the run
	_bridges(r, frames, half, out)
	_tunnels(r, frames, half, out)
	_rails(r, frames, half, out)


# ------------------------------------------------------------------------------------------------
static func _bridges(r: Dictionary, frames: Array, half: float, out: Dictionary) -> void:
	var m := _mesh(out, "bridge")
	var first_index := m.indices.size()
	var deck := 1.3
	var k := 0
	while k < frames.size() - 1:
		var fa: Dictionary = frames[k]
		var fb: Dictionary = frames[k + 1]
		if not ((int(fa["f"]) & WorldData.F_BRIDGE) and (int(fb["f"]) & WorldData.F_BRIDGE)):
			k += 1
			continue
		for side: float in [-1.0, 1.0]:
			var la := _parapet_profile(fa, half, side, deck)
			var lb := _parapet_profile(fb, half, side, deck)
			# profile points go: inner bottom -> inner top -> outer top -> outer bottom (deck underside)
			for q in la.size() - 1:
				var p0: Vector3 = la[q]
				var p1: Vector3 = la[q + 1]
				var p2: Vector3 = lb[q + 1]
				var p3: Vector3 = lb[q]
				var nn := (p1 - p0).cross(p3 - p0).normalized() * (-side)
				if nn.length() < 0.5:
					nn = Vector3.UP
				var i0 := m.add_vertex(p0, nn, Vector2(0.0, fa["s"]))
				var i1 := m.add_vertex(p1, nn, Vector2(1.0, fa["s"]))
				var i2 := m.add_vertex(p2, nn, Vector2(1.0, fb["s"]))
				var i3 := m.add_vertex(p3, nn, Vector2(0.0, fb["s"]))
				if side > 0.0:
					m.quad(i0, i1, i2, i3)
				else:
					m.quad(i0, i3, i2, i1)
		# underside (facing down)
		var ua: Vector3 = (fa["p"] as Vector3) + Vector3.DOWN * deck
		var ub: Vector3 = (fb["p"] as Vector3) + Vector3.DOWN * deck
		var ra: Vector3 = fa["right"]
		var rbv: Vector3 = fb["right"]
		var w := half + 0.55
		var u0 := m.add_vertex(ua - ra * w, Vector3.DOWN, Vector2(0, fa["s"]))
		var u1 := m.add_vertex(ua + ra * w, Vector3.DOWN, Vector2(1, fa["s"]))
		var u2 := m.add_vertex(ub + rbv * w, Vector3.DOWN, Vector2(1, fb["s"]))
		var u3 := m.add_vertex(ub - rbv * w, Vector3.DOWN, Vector2(0, fb["s"]))
		m.quad(u0, u1, u2, u3)
		# pillars every ~30 m
		var idx := int(fa["i"])
		if idx % 15 == 0:
			(out["pillars"] as Array).append({"p": fa["p"], "fwd": fa["fwd"], "half": half, "deck": deck})
		k += 1
	_add_faces(out, "concrete", m, first_index)


static func _parapet_profile(fr: Dictionary, half: float, side: float, deck: float) -> Array:
	var p: Vector3 = fr["p"]
	var right: Vector3 = fr["right"]
	var tb: float = fr["tb"]
	var lat_in := side * (half + 0.3)
	var lat_out := side * (half + 0.55)
	var base_in := p + right * lat_in + Vector3.UP * (-lat_in * tb)
	var base_out := p + right * lat_out + Vector3.UP * (-lat_out * tb)
	return [base_in, base_in + Vector3.UP * 0.95, base_out + Vector3.UP * 0.95, base_out + Vector3.DOWN * deck]


# ------------------------------------------------------------------------------------------------
static func _tunnel_profile(half: float) -> Array:
	var w := half + 1.1
	return [Vector2(-w, -0.1), Vector2(-w, 4.3), Vector2(-w * 0.72, 5.9), Vector2(0.0, 6.5),
		Vector2(w * 0.72, 5.9), Vector2(w, 4.3), Vector2(w, -0.1)]


static func _tunnels(r: Dictionary, frames: Array, half: float, out: Dictionary) -> void:
	var m := _mesh(out, "tunnel")
	var lights := _mesh(out, "tunnel_light")
	var first_index := m.indices.size()
	var prof := _tunnel_profile(half)
	var k := 0
	while k < frames.size() - 1:
		var fa: Dictionary = frames[k]
		var fb: Dictionary = frames[k + 1]
		var ta := (int(fa["f"]) & WorldData.F_TUNNEL) != 0
		var tbb := (int(fb["f"]) & WorldData.F_TUNNEL) != 0
		if not (ta and tbb):
			k += 1
			continue
		for q in prof.size() - 1:
			var p0 := _prof_point(fa, prof[q])
			var p1 := _prof_point(fa, prof[q + 1])
			var p2 := _prof_point(fb, prof[q + 1])
			var p3 := _prof_point(fb, prof[q])
			var centre: Vector3 = (fa["p"] as Vector3) + Vector3.UP * 3.0
			var nn := (centre - (p0 + p1) * 0.5).normalized()
			var i0 := m.add_vertex(p0, nn, Vector2(float(q), fa["s"]))
			var i1 := m.add_vertex(p1, nn, Vector2(float(q + 1), fa["s"]))
			var i2 := m.add_vertex(p2, nn, Vector2(float(q + 1), fb["s"]))
			var i3 := m.add_vertex(p3, nn, Vector2(float(q), fb["s"]))
			# inner side is the front face
			m.quad(i0, i3, i2, i1)
		if int(fa["i"]) % 4 == 0:
			var c: Vector3 = _prof_point(fa, Vector2(0.0, 6.42))
			var c2: Vector3 = _prof_point(fb, Vector2(0.0, 6.42))
			var rr: Vector3 = fa["right"]
			var l0 := lights.add_vertex(c - rr * 0.18, Vector3.DOWN, Vector2.ZERO)
			var l1 := lights.add_vertex(c + rr * 0.18, Vector3.DOWN, Vector2.ZERO)
			var l2 := lights.add_vertex(c2 + rr * 0.18, Vector3.DOWN, Vector2.ZERO)
			var l3 := lights.add_vertex(c2 - rr * 0.18, Vector3.DOWN, Vector2.ZERO)
			lights.quad(l0, l3, l2, l1)
		k += 1
	_add_faces(out, "concrete", m, first_index)
	# portals at tunnel ends inside this run
	for k2 in frames.size():
		var fr: Dictionary = frames[k2]
		if not (int(fr["f"]) & WorldData.F_TUNNEL):
			continue
		var prev_out := k2 > 0 and not (int((frames[k2 - 1] as Dictionary)["f"]) & WorldData.F_TUNNEL)
		var next_out := k2 < frames.size() - 1 and not (int((frames[k2 + 1] as Dictionary)["f"]) & WorldData.F_TUNNEL)
		if prev_out or next_out:
			(out["portals"] as Array).append({"p": fr["p"], "fwd": (fr["fwd"] as Vector3) * (-1.0 if prev_out else 1.0), "half": half})


static func _prof_point(fr: Dictionary, q: Vector2) -> Vector3:
	var p: Vector3 = fr["p"]
	var right: Vector3 = fr["right"]
	return p + right * q.x + Vector3.UP * q.y


# ------------------------------------------------------------------------------------------------
static func _rails(r: Dictionary, frames: Array, half: float, out: Dictionary) -> void:
	var m := _mesh(out, "rail")
	var first_index := m.indices.size()
	for side: float in [-1.0, 1.0]:
		var bit := WorldData.F_RAIL_R if side > 0.0 else WorldData.F_RAIL_L
		var k := 0
		while k < frames.size() - 1:
			var fa: Dictionary = frames[k]
			var fb: Dictionary = frames[k + 1]
			if not ((int(fa["f"]) & bit) and (int(fb["f"]) & bit)):
				k += 1
				continue
			var lat := side * (half + 0.55)
			var a0 := _rail_pt(fa, lat, 0.42)
			var a1 := _rail_pt(fa, lat, 0.78)
			var b0 := _rail_pt(fb, lat, 0.42)
			var b1 := _rail_pt(fb, lat, 0.78)
			var nn: Vector3 = (fa["right"] as Vector3) * -side
			var i0 := m.add_vertex(a0, nn, Vector2(0, fa["s"]))
			var i1 := m.add_vertex(a1, nn, Vector2(1, fa["s"]))
			var i2 := m.add_vertex(b1, nn, Vector2(1, fb["s"]))
			var i3 := m.add_vertex(b0, nn, Vector2(0, fb["s"]))
			if side > 0.0:
				m.quad(i0, i3, i2, i1)
			else:
				m.quad(i0, i1, i2, i3)
			if int(fa["i"]) % 2 == 0:
				var base := _rail_pt(fa, lat + side * 0.12, 0.0)
				(out["posts"] as Array).append({"p": base, "fwd": fa["fwd"]})
			k += 1
	_add_faces(out, "rail", m, first_index)


static func _rail_pt(fr: Dictionary, lat: float, h: float) -> Vector3:
	var p: Vector3 = fr["p"]
	var right: Vector3 = fr["right"]
	var tb: float = fr["tb"]
	return p + right * lat + Vector3.UP * (h - lat * tb)


# ------------------------------------------------------------------------------------------------
static func portal_arrays(portal: Dictionary) -> Array:
	## Concrete portal facade around the tunnel mouth (front + back), returned as mesh arrays.
	var half: float = portal["half"]
	var p: Vector3 = portal["p"]
	var fwd: Vector3 = portal["fwd"]
	var flat := Vector3(fwd.x, 0.0, fwd.z).normalized()
	var right := flat.cross(Vector3.UP).normalized()
	var prof := _tunnel_profile(half)
	var W := half + 9.0
	var H := 13.0
	var outer := [Vector2(-W, -2.0), Vector2(-W, H * 0.6), Vector2(-W * 0.6, H), Vector2(0.0, H),
		Vector2(W * 0.6, H), Vector2(W, H * 0.6), Vector2(W, -2.0)]
	var md := MeshData.new()
	for face in [0, 1]:
		var off := flat * (0.0 if face == 0 else 1.2)
		var nn := -flat if face == 0 else flat
		var base := md.verts.size()
		for q in prof.size():
			var ip: Vector2 = prof[q]
			var op: Vector2 = outer[q]
			md.add_vertex(p + off + right * ip.x + Vector3.UP * ip.y, nn, Vector2(ip.x * 0.25, ip.y * 0.25))
			md.add_vertex(p + off + right * op.x + Vector3.UP * op.y, nn, Vector2(op.x * 0.25, op.y * 0.25))
		for q in prof.size() - 1:
			var a := base + q * 2
			var b := base + q * 2 + 1
			var c := base + (q + 1) * 2 + 1
			var d := base + (q + 1) * 2
			if face == 0:
				md.quad(a, d, c, b)
			else:
				md.quad(a, b, c, d)
	return md.to_arrays()
