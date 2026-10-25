class_name RoadBuilder
extends Node3D
## Builds road surface meshes (procedural markings via road.gdshader), trimesh colliders tagged with
## surface metadata, guard rails, delineator posts, curve chevrons, bridge decks/parapets/piers and
## tunnel tubes from the RoadNetwork. Geometry is generated on the WorkerThreadPool per road and
## committed on the main thread in pieces.

const PIECE := 40                 # samples per mesh/collider piece (~120 m)
const BARRIER_LAYER := 32           # physics layer 6: rails, bridge parapets, tunnel tube
const DETAIL_PIECE := 120         # samples per rail/post/sign mesh (~360 m) so visibility ranges apply locally
const SURFACE_KIND := {&"asphalt": 0, &"dirt": 1, &"gravel": 2, &"sand": 3, &"concrete": 4}

var data: WorldData
var road_mat: ShaderMaterial
var rail_mat: StandardMaterial3D
var concrete_mat: StandardMaterial3D
var tunnel_mat: ShaderMaterial
var post_mat: StandardMaterial3D
var sign_mat: StandardMaterial3D
var _results: Array = []
var _mutex := Mutex.new()
var _tasks: Array[int] = []
var pieces_built: int = 0
var done: bool = false
var lamp_positions: PackedVector3Array = PackedVector3Array()
var culvert_positions := PackedVector3Array()   # for QA
var stats := {"rail_m": 0.0, "bridge_m": 0.0, "tunnel_m": 0.0, "chevrons": 0, "posts": 0, "culverts": 0}

signal finished()


func setup(world_data: WorldData, noise_detail: Texture2D, noise_large: Texture2D) -> void:
	data = world_data
	road_mat = ShaderMaterial.new()
	road_mat.shader = load("res://assets/shaders/road.gdshader")
	road_mat.set_shader_parameter("noise_detail", noise_detail)
	road_mat.set_shader_parameter("noise_large", noise_large)
	rail_mat = StandardMaterial3D.new()
	rail_mat.albedo_color = Color(0.68, 0.7, 0.72)
	rail_mat.metallic = 0.85
	rail_mat.roughness = 0.38
	rail_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	rail_mat.vertex_color_use_as_albedo = true
	concrete_mat = StandardMaterial3D.new()
	concrete_mat.albedo_color = Color(0.62, 0.6, 0.57)
	concrete_mat.roughness = 0.9
	concrete_mat.vertex_color_use_as_albedo = true
	concrete_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	tunnel_mat = ShaderMaterial.new()
	tunnel_mat.shader = load("res://assets/shaders/tunnel.gdshader")
	post_mat = StandardMaterial3D.new()
	post_mat.vertex_color_use_as_albedo = true
	post_mat.roughness = 0.6
	sign_mat = StandardMaterial3D.new()
	sign_mat.vertex_color_use_as_albedo = true
	sign_mat.roughness = 0.5
	sign_mat.emission_enabled = true
	sign_mat.emission = Color(0.05, 0.05, 0.03)
	for spot: Array in street_lamp_spots(data.network):
		lamp_positions.append(spot[0])
	for r in data.network.roads:
		_tasks.append(WorkerThreadPool.add_task(_build_road.bind(r.idx), false, "road_build"))
	_tasks.append(WorkerThreadPool.add_task(_build_junction_fillets, false, "road_fillets"))


func _process(_delta: float) -> void:
	if done:
		return
	_mutex.lock()
	var batch := _results.slice(0, 8)
	_results = _results.slice(8)
	_mutex.unlock()
	for item: Dictionary in batch:
		_commit(item)
	var all_done := true
	for id in _tasks:
		if not WorkerThreadPool.is_task_completed(id):
			all_done = false
	if all_done:
		_mutex.lock()
		var empty := _results.is_empty()
		_mutex.unlock()
		if empty:
			for id in _tasks:
				WorkerThreadPool.wait_for_task_completion(id)
			_tasks.clear()
			done = true
			finished.emit()


func _commit(item: Dictionary) -> void:
	var kind: String = item["kind"]
	if kind == "sign_label":
		_commit_sign(item)
		return
	var mi := MeshInstance3D.new()
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, item["arrays"])
	mi.mesh = am
	mi.position = item["origin"]
	match kind:
		"road":
			mi.material_override = road_mat
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mi.set_instance_shader_parameter("road_width", item["width"])
			mi.set_instance_shader_parameter("shoulder", item["shoulder"])
			mi.set_instance_shader_parameter("lanes", item["lanes"])
			mi.set_instance_shader_parameter("marking", item["marking"])
			mi.set_instance_shader_parameter("surface_kind", item["surface_kind"])
			mi.set_instance_shader_parameter("covered", 1.0 if item.get("covered", false) else 0.0)
		"rail":
			mi.material_override = rail_mat
			mi.visibility_range_end = 700.0
			mi.visibility_range_end_margin = 50.0
			mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		"concrete":
			mi.material_override = concrete_mat
		"tunnel":
			mi.material_override = tunnel_mat
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED
		"posts":
			mi.material_override = post_mat
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mi.visibility_range_end = 450.0
			mi.visibility_range_end_margin = 40.0
			mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		"signs":
			mi.material_override = sign_mat
			mi.visibility_range_end = 600.0
	add_child(mi)
	if item.has("faces"):
		var body := StaticBody3D.new()
		# Barriers (rails, parapets, tunnel tube) are solid for car bodies but invisible to wheel rays, so a
		# wheel that ends up over a barrier after an impact cannot "stand" on it and lift the car over.
		body.collision_layer = BARRIER_LAYER if item.get("barrier", false) else 1
		body.collision_mask = 0
		body.set_meta(&"surface", item.get("surface", &"asphalt"))
		body.set_meta(&"road", item.get("road_id", ""))
		if item.get("covered", false):
			body.set_meta(&"covered", true)   # under a tunnel tube: stays dry in rain
		var cs := CollisionShape3D.new()
		var shape := ConcavePolygonShape3D.new()
		shape.set_faces(item["faces"])
		shape.backface_collision = item.get("backface", false)
		cs.shape = shape
		body.add_child(cs)
		body.position = item["origin"]
		add_child(body)
	pieces_built += 1


func _commit_sign(item: Dictionary) -> void:
	# Green direction board on two posts with the destination road name; the posts are solid (barrier layer).
	var root := Node3D.new()
	root.transform = item["xf"]
	add_child(root)
	var body := StaticBody3D.new()
	body.name = "SignPosts"
	body.collision_layer = BARRIER_LAYER
	body.collision_mask = 0
	root.add_child(body)
	var board := MeshInstance3D.new()
	var bm := BoxMesh.new()
	var w: float = item["width"]
	bm.size = Vector3(w, 1.1, 0.08)
	board.mesh = bm
	board.position = Vector3(0, 2.6, 0)
	board.material_override = _sign_board_mat()
	root.add_child(board)
	for sx: float in [-w * 0.4, w * 0.4]:
		var post := MeshInstance3D.new()
		var pm := CylinderMesh.new()
		pm.top_radius = 0.05
		pm.bottom_radius = 0.05
		pm.height = 3.2
		post.mesh = pm
		post.position = Vector3(sx, 1.6, 0.06)
		post.material_override = rail_mat
		root.add_child(post)
		var cs := CollisionShape3D.new()
		var cyl := CylinderShape3D.new()
		cyl.radius = 0.08
		cyl.height = 3.2
		cs.shape = cyl
		cs.position = post.position
		body.add_child(cs)
	for face: float in [1.0, -1.0]:
		var lbl := Label3D.new()
		lbl.text = item["text"]
		lbl.font_size = 64
		lbl.pixel_size = 0.0065
		lbl.modulate = Color(0.97, 0.97, 0.95)
		lbl.outline_size = 0
		lbl.position = Vector3(0, 2.62, 0.045 * face)
		lbl.rotation = Vector3(0, 0.0 if face > 0.0 else PI, 0)
		lbl.double_sided = false
		lbl.visibility_range_end = 220.0
		root.add_child(lbl)
	board.visibility_range_end = 600.0


var _board_mat: StandardMaterial3D

func _sign_board_mat() -> StandardMaterial3D:
	if _board_mat == null:
		_board_mat = StandardMaterial3D.new()
		_board_mat.albedo_color = Color(0.05, 0.36, 0.2)
		_board_mat.roughness = 0.45
		_board_mat.emission_enabled = true
		_board_mat.emission = Color(0.01, 0.05, 0.03)
	return _board_mat


func _push(item: Dictionary) -> void:
	_mutex.lock()
	_results.append(item)
	_mutex.unlock()


# ------------------------------------------------------------------ geometry (worker thread)

func _build_road(ri: int) -> void:
	var r: RoadNetwork.Road = data.network.roads[ri]
	var n := r.count()
	var hw := r.width * 0.5
	var e := hw + r.shoulder
	var cols := [[-(e + 1.1), -0.55], [-e, 0.0], [-hw, 0.0], [0.0, 0.0], [hw, 0.0], [e, 0.0], [e + 1.1, -0.55]]
	# Junction trimming: child roads stop at the parent's edge.
	var skip := PackedByteArray()
	skip.resize(n)
	var lower := PackedFloat32Array()
	lower.resize(n)
	for jd: Dictionary in [r.j_start, r.j_end]:
		if jd.is_empty():
			continue
		var parent := data.network.get_road(jd["road"])
		if parent == null:
			continue
		var pp := parent.pos[int(jd["index"])]
		var pe := parent.width * 0.5 + parent.shoulder
		for i in n:
			var d := Vector2(r.pos[i].x - pp.x, r.pos[i].z - pp.z).length()
			# Keep one sample row inside the parent surface so the child mesh/collider overlaps
			# the parent edge (no seam); it is lowered 3.5 cm to avoid z-fighting. At acute junctions
			# the child runs over the parent's edge for a while, so the lowering follows the parent's line.
			if d < pe - 3.2:
				skip[i] = 1
			if d < pe + 8.0 or (d < 160.0 and _dist_to_road(parent, int(jd["index"]), r.pos[i]) < pe + hw + 2.0):
				lower[i] = 0.035
	var segs := n if r.loop else n - 1
	var paved := r.surface == &"asphalt"
	var tube := WorldGen.tube_mask(r.flags)
	var start := 0
	while start < segs:
		# Pieces never straddle a bridge boundary so paved bridge decks can be concrete, nor a tunnel tube end
		# so tube pieces are entirely "covered" (dry in rain).
		var deck := paved and (r.flags[start % n] & 1) != 0
		var covered := _seg_covered(tube, start, n)
		var end := start + 1
		while end < segs and end - start < PIECE and (paved and (r.flags[end % n] & 1) != 0) == deck and _seg_covered(tube, end, n) == covered:
			end += 1
		# Neighbouring pieces overlap by one segment (no seams), except across a tube end.
		var next_cov := end < segs and _seg_covered(tube, end, n)
		var s1 := end
		if end < segs and next_cov == covered:
			s1 = mini(end + 1, segs)
		_build_piece(r, start, s1, cols, skip, lower, deck, covered)
		start = end
	_build_furniture(r)


## Segment i..i+1 lies inside a tunnel tube.
static func _seg_covered(tube: PackedByteArray, i: int, n: int) -> bool:
	return tube[i % n] == 1 and tube[(i + 1) % n] == 1


## Horizontal distance from p to the road's centreline, searched within 150 m of sample c.
static func _dist_to_road(road: RoadNetwork.Road, c: int, p: Vector3) -> float:
	var pn := road.count()
	var win := int(150.0 / road.ds)
	var bd := INF
	var q := Vector2(p.x, p.z)
	for w in range(-win, win + 1):
		var k := c + w
		if road.loop:
			k = posmod(k, pn)
		elif k < 0 or k >= pn - 1:
			continue
		var a := Vector2(road.pos[k].x, road.pos[k].z)
		var ab := Vector2(road.pos[(k + 1) % pn].x, road.pos[(k + 1) % pn].z) - a
		var t := clampf((q - a).dot(ab) / maxf(ab.length_squared(), 1e-6), 0.0, 1.0)
		bd = minf(bd, q.distance_to(a + ab * t))
	return bd


func _frame(r: RoadNetwork.Road, i: int) -> Array:
	# Returns [position, right(horizontal), bank]
	var n := r.count()
	var a := r.pos[(i - 1 + n) % n] if (r.loop or i > 0) else r.pos[i]
	var b := r.pos[(i + 1) % n] if (r.loop or i < n - 1) else r.pos[i]
	var t := b - a
	t.y = 0.0
	t = t.normalized()
	return [r.pos[i % n], Vector3(-t.z, 0.0, t.x), r.bank[i % n]]


func _build_piece(r: RoadNetwork.Road, s0: int, s1: int, cols: Array, skip: PackedByteArray, lower: PackedFloat32Array, deck := false, covered := false) -> void:
	var n := r.count()
	var origin := r.pos[s0]
	origin.y = 0.0
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	var faces := PackedVector3Array()
	var e: float = float(cols[5][0])
	var nc := cols.size()
	var rows := 0
	var prev_valid := false
	for i in range(s0, s1 + 1):
		var k := i % n
		var valid := skip[k] == 0
		var f := _frame(r, i)
		var p: Vector3 = f[0]
		var rt: Vector3 = f[1]
		var bank: float = f[2]
		var nrm := (Vector3.UP - rt * bank).normalized()
		var base := verts.size()
		for c in nc:
			var o: float = cols[c][0]
			var yo: float = cols[c][1]
			var v := p + rt * o + Vector3(0, o * bank + yo - lower[k], 0) - origin
			verts.append(v)
			norms.append(nrm)
			uvs.append(Vector2((o + e) / (2.0 * e), float(i) * r.ds / 4.0))
		if rows > 0 and valid and prev_valid:
			for c in nc - 1:
				var a := base - nc + c
				var b := a + 1
				var cc := base + c
				var d := cc + 1
				idx.append_array([a, cc, b, b, cc, d])
				# The verge skirts collide too: the edge meets the ground as a short slope, not a kerb.
				faces.append_array([verts[a], verts[cc], verts[b], verts[b], verts[cc], verts[d]])
		rows += 1
		prev_valid = valid
	# A dead end (no junction) runs out onto the ground over a short sloped apron instead of a kerb.
	if not r.loop and s1 == n - 1 and r.j_end.is_empty() and prev_valid:
		_end_apron(r, n - 1, 1.0, cols, origin, e, verts, norms, uvs, idx, faces, verts.size() - nc)
	if not r.loop and s0 == 0 and r.j_start.is_empty() and skip[0] == 0:
		_end_apron(r, 0, -1.0, cols, origin, e, verts, norms, uvs, idx, faces, 0)
	if idx.is_empty():
		return
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = idx
	var surf: StringName = &"concrete" if deck else r.surface
	_push({"kind": "road", "arrays": arrays, "origin": origin, "faces": faces, "surface": surf, "road_id": r.id,
		"width": r.width, "shoulder": r.shoulder, "lanes": r.lanes, "marking": r.marking,
		"surface_kind": SURFACE_KIND.get(surf, 0), "covered": covered})


## Row of vertices 1.4 m beyond end sample i (`out` +1 past the last sample, -1 before the first), 0.6 m lower,
## joined to the existing end row at index `row` (mesh + collision).
func _end_apron(r: RoadNetwork.Road, i: int, out: float, cols: Array, origin: Vector3, e: float, verts: PackedVector3Array,
		norms: PackedVector3Array, uvs: PackedVector2Array, idx: PackedInt32Array, faces: PackedVector3Array, row: int) -> void:
	var f := _frame(r, i)
	var p: Vector3 = f[0]
	var rt: Vector3 = f[1]
	var bank: float = f[2]
	var fwd := Vector3(rt.z, 0.0, -rt.x) * out
	var nc := cols.size()
	var base := verts.size()
	for c in nc:
		var o: float = cols[c][0]
		var yo: float = cols[c][1]
		verts.append(p + fwd * 1.4 + rt * o + Vector3(0, o * bank + yo - 0.6, 0) - origin)
		norms.append((Vector3.UP + fwd * 0.4).normalized())
		uvs.append(Vector2((o + e) / (2.0 * e), (float(i) * r.ds + out * 1.4) / 4.0))
	for c in nc - 1:
		# Rows in travel order: (first, second) = (end row, apron) past the end, (apron, end row) before the start.
		var a := (row if out > 0.0 else base) + c
		var cc := (base if out > 0.0 else row) + c
		idx.append_array([a, cc, a + 1, a + 1, cc, cc + 1])
		faces.append_array([verts[a], verts[cc], verts[a + 1], verts[a + 1], verts[cc], verts[cc + 1]])


# ------------------------------------------------------------------ furniture

func _side_needs_rail(r: RoadNetwork.Road, i: int, side: float) -> bool:
	var f := _frame(r, i)
	var p: Vector3 = f[0]
	var rt: Vector3 = f[1]
	var e := r.width * 0.5 + r.shoulder
	if r.flags[i] & 1:
		return false  # bridges get parapets
	if r.flags[i] & 2:
		return false
	var q := p + rt * side * (e + 4.0)
	var h := data.height_at(q.x, q.z)
	var drop := p.y - h
	var limit := 2.2 if r.cls != WorldLayout.RoadClass.HIGHWAY else 1.6
	var n := r.count()
	for k in range(-12, 13):
		var j := i + k
		if j >= 0 and j < n and (r.flags[j] & 1):
			limit = 0.8
			break
	return drop > limit


func _clean_mask(m: PackedByteArray, min_run: int, gap: int) -> PackedByteArray:
	return WorldGen._clean_flags(m, 1, min_run, gap, false)


## Samples where no rails / parapets / posts / signs / lamps may stand because another road joins there.
func _junction_keepout(r: RoadNetwork.Road) -> PackedByteArray:
	return junction_keepout(data.network, r)


static func junction_keepout(net: RoadNetwork, r: RoadNetwork.Road) -> PackedByteArray:
	var n := r.count()
	var keep := PackedByteArray()
	keep.resize(n)
	for jd: Dictionary in net.junctions:
		var centre := Vector3.INF
		var clear := 0.0
		if jd["child"] == r.id:
			var parent := net.get_road(jd["parent"])
			if parent == null:
				continue
			centre = parent.pos[int(jd["parent_index"])]
			clear = parent.width * 0.5 + parent.shoulder + 12.0
		elif jd["parent"] == r.id:
			var child := net.get_road(jd["child"])
			if child == null:
				continue
			centre = r.pos[int(jd["parent_index"])]
			clear = child.width * 0.5 + child.shoulder + 12.0
		else:
			continue
		for i in n:
			if Vector2(r.pos[i].x - centre.x, r.pos[i].z - centre.z).length() < clear:
				keep[i] = 1
	return keep


func _build_furniture(r: RoadNetwork.Road) -> void:
	var n := r.count()
	var paved := r.surface == &"asphalt" or r.surface == &"concrete"
	var e := r.width * 0.5 + r.shoulder
	var origin := r.pos[0]
	origin.y = 0.0
	var keep := _junction_keepout(r)
	# ---- guard rails (paved roads only) ----
	if paved:
		for side: float in [-1.0, 1.0]:
			var mask := PackedByteArray()
			mask.resize(n)
			for i in n:
				mask[i] = 1 if keep[i] == 0 and _side_needs_rail(r, i, side) else 0
			mask = _clean_mask(mask, 6, 5)
			_build_rails(r, mask, side, e + 0.45)
	# ---- bridges and tunnels ----
	var i0 := 0
	while i0 < n:
		var fl := r.flags[i0]
		if fl & 1 or fl & 2:
			var bit := 1 if fl & 1 else 2
			var j := i0
			while j < n and (r.flags[j] & bit):
				j += 1
			if bit == 1:
				# Parapets stop at junction mouths (split the bridge into runs outside keep-out zones).
				var a0 := maxi(i0 - 4, 0)
				var b0 := mini(j + 3, n - 1)
				var run_start := -1
				for k in range(a0, b0 + 2):
					var free := k <= b0 and keep[k] == 0
					if free and run_start < 0:
						run_start = k
					elif not free and run_start >= 0:
						if k - 1 - run_start >= 2:
							_build_bridge(r, run_start, k - 1)
						run_start = -1
				stats["bridge_m"] += (j - i0) * r.ds
			else:
				_build_tunnel(r, maxi(i0 - WorldGen.TUBE_PRE, 0), mini(j + WorldGen.TUBE_POST, n - 1))
				stats["tunnel_m"] += (j - i0) * r.ds
			i0 = j
		else:
			i0 += 1
	# ---- delineator posts + chevrons ----
	if paved and r.cls != WorldLayout.RoadClass.STREET:
		_build_posts_and_signs(r, e)
	# ---- drainage culverts through embankments ----
	if r.cls != WorldLayout.RoadClass.STREET:
		_build_culverts(r, e, keep)


func _build_rails(r: RoadNetwork.Road, mask: PackedByteArray, side: float, off: float) -> void:
	var n := r.count()
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var colors := PackedColorArray()
	var idx := PackedInt32Array()
	var faces := PackedVector3Array()
	var origin := r.pos[0]
	origin.y = 0.0
	var run_prev := false
	var prev_band := -1        # index of the previous band's first vertex (posts are appended in between)
	var prev_world: Array[Vector3] = []
	var prev_norm := Vector3.UP
	var post_every := maxi(int(4.0 / r.ds), 1)
	var steel := Color(0.72, 0.74, 0.76)
	for i in n:
		if i > 0 and i % DETAIL_PIECE == 0:
			# New mesh piece (local AABB, so the visibility range works); carry the last band over for stitching.
			_push_detail("rail", verts, norms, colors, idx, origin, faces)
			verts = PackedVector3Array()
			norms = PackedVector3Array()
			colors = PackedColorArray()
			idx = PackedInt32Array()
			faces = PackedVector3Array()
			origin = r.pos[i]
			origin.y = 0.0
			prev_band = -1
			if run_prev and prev_world.size() == 3:
				prev_band = 0
				for k in 3:
					verts.append(prev_world[k] - origin)
					norms.append(prev_norm)
					colors.append(steel)
		var on := mask[i] == 1
		var f := _frame(r, i)
		var p: Vector3 = f[0]
		var rt: Vector3 = f[1]
		var bank: float = f[2]
		var base_p := p + rt * side * off + Vector3(0, side * off * bank, 0) - origin
		if on:
			# W-beam approximated by a profiled band: 3 vertices (low, mid-bulge, high) on the road side.
			var b := verts.size()
			var out := rt * side
			verts.append(base_p + Vector3(0, 0.5, 0))
			verts.append(base_p + Vector3(0, 0.66, 0) - out * 0.06)
			verts.append(base_p + Vector3(0, 0.82, 0))
			for k in 3:
				norms.append(-out)
				colors.append(steel)
			if run_prev and prev_band >= 0:
				var a := prev_band
				idx.append_array([a, b, a + 1, a + 1, b, b + 1, a + 1, b + 1, a + 2, a + 2, b + 1, b + 2])
				faces.append_array([verts[a], verts[b], verts[a + 2], verts[a + 2], verts[b], verts[b + 2]])
				stats["rail_m"] += r.ds
			prev_band = b
			prev_world = [verts[b] + origin, verts[b + 1] + origin, verts[b + 2] + origin]
			prev_norm = -out
			if i % post_every == 0:
				_box(verts, norms, colors, idx, base_p + out * 0.12 + Vector3(0, 0.38, 0), Vector3(0.1, 0.76, 0.1), Color(0.6, 0.62, 0.64))
		run_prev = on
	_push_detail("rail", verts, norms, colors, idx, origin, faces)


## Pushes one roadside-detail mesh piece (rails / posts / signs); rails carry collision faces.
func _push_detail(kind: String, verts: PackedVector3Array, norms: PackedVector3Array, colors: PackedColorArray, idx: PackedInt32Array, origin: Vector3, faces := PackedVector3Array()) -> void:
	if idx.is_empty():
		return
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = idx
	if kind == "rail":
		_push({"kind": kind, "arrays": arrays, "origin": origin, "faces": faces, "surface": &"concrete", "backface": true, "barrier": true})
	else:
		_push({"kind": kind, "arrays": arrays, "origin": origin})


func _build_bridge(r: RoadNetwork.Road, a: int, b: int) -> void:
	var origin := r.pos[a]
	origin.y = 0.0
	var e := r.width * 0.5 + r.shoulder
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var colors := PackedColorArray()
	var idx := PackedInt32Array()
	var faces := PackedVector3Array()
	var conc := Color(0.66, 0.64, 0.6)
	var dark := Color(0.5, 0.49, 0.46)
	# Profile (lateral offset, height): parapet tops and deck underside, as a closed-ish strip.
	var prof := [[-e - 0.5, -0.02], [-e - 0.5, 1.0], [-e - 0.1, 1.0], [-e - 0.1, 0.05],
		[e + 0.1, 0.05], [e + 0.1, 1.0], [e + 0.5, 1.0], [e + 0.5, -0.02],
		[e + 0.5, -1.5], [-e - 0.5, -1.5]]
	var np := prof.size()
	var rows := 0
	var prev_base := -1
	var last_pier := -1000.0
	for i in range(a, b + 1):
		var f := _frame(r, i)
		var p: Vector3 = f[0]
		var rt: Vector3 = f[1]
		var bank: float = f[2]
		var base := verts.size()
		for k in np:
			var o: float = prof[k][0]
			var yo: float = prof[k][1]
			verts.append(p + rt * o + Vector3(0, o * bank + yo, 0) - origin)
			norms.append(Vector3.UP)
			colors.append(conc if k < 8 else dark)
		if rows > 0:
			for k in np:
				if k == 3:
					continue  # deck surface is the road mesh
				var k2 := (k + 1) % np
				var a0 := prev_base + k
				var a1 := prev_base + k2
				var b0 := base + k
				var b1 := base + k2
				idx.append_array([a0, b0, a1, a1, b0, b1])
				# Collision on both parapets' outer face, top and inner face (segment 2 left inner, 4 right inner).
				if k in [0, 1, 2, 4, 5, 6]:
					faces.append_array([verts[a0], verts[b0], verts[a1], verts[a1], verts[b0], verts[b1]])
		rows += 1
		prev_base = base
		# Piers every ~30 m (not at the very ends).
		var s := i * r.ds
		if s - last_pier > 30.0 and i > a + 3 and i < b - 3:
			last_pier = s
			var ground := data.height_at(p.x, p.z)
			var top := p.y - 1.5
			var bottom := minf(ground, top) - 3.0
			if top - bottom > 1.0:
				var c := Vector3(p.x, (top + bottom) * 0.5, p.z) - origin
				_box(verts, norms, colors, idx, c + rt * (e * 0.45), Vector3(1.6, top - bottom, 1.6), dark)
				_box(verts, norms, colors, idx, c - rt * (e * 0.45), Vector3(1.6, top - bottom, 1.6), dark)
				_box_oriented(verts, norms, colors, idx, Vector3(p.x, top - 0.6, p.z) - origin, rt, Vector3(-rt.z, 0, rt.x), Vector3(e * 2.0, 1.2, 2.0), dark)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = _recompute_normals(verts, idx)
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = idx
	_push({"kind": "concrete", "arrays": arrays, "origin": origin, "faces": faces, "surface": &"concrete", "backface": true, "barrier": true})


func _build_tunnel(r: RoadNetwork.Road, a: int, b: int) -> void:
	var origin := r.pos[a]
	origin.y = 0.0
	var e := r.width * 0.5 + r.shoulder + 0.6
	var prof: Array = [[-e, -0.3], [-e, 4.4]]
	for k in range(1, 8):
		var ang := PI * float(k) / 8.0
		prof.append([-cos(ang) * e, 4.4 + sin(ang) * 2.8])
	prof.append([e, 4.4])
	prof.append([e, -0.3])
	var np := prof.size()
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	var faces := PackedVector3Array()
	var rows := 0
	for i in range(a, b + 1):
		var f := _frame(r, i)
		var p: Vector3 = f[0]
		var rt: Vector3 = f[1]
		var base := verts.size()
		for k in np:
			var o: float = prof[k][0]
			var yo: float = prof[k][1]
			verts.append(p + rt * o + Vector3(0, yo, 0) - origin)
			uvs.append(Vector2(float(k) / (np - 1), i * r.ds))
		if rows > 0:
			for k in np - 1:
				var a0 := base - np + k
				var b0 := base + k
				idx.append_array([a0, a0 + 1, b0, a0 + 1, b0 + 1, b0])
				faces.append_array([verts[a0], verts[a0 + 1], verts[b0], verts[a0 + 1], verts[b0 + 1], verts[b0]])
		rows += 1
	# Portal frames at both ends (thick concrete collar).
	var colors := PackedColorArray()
	colors.resize(verts.size())
	colors.fill(Color.WHITE)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = _recompute_normals(verts, idx)
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = idx
	_push({"kind": "tunnel", "arrays": arrays, "origin": origin, "faces": faces, "surface": &"concrete", "backface": true, "barrier": true})
	_build_portal(r, a, 1.0, e, origin)
	_build_portal(r, b, -1.0, e, origin)
	# Tunnel lamps (positions only; the lighting manager pools real lights).
	var tmp := PackedVector3Array()
	for i in range(a, b + 1, maxi(int(18.0 / r.ds), 1)):
		tmp.append(r.pos[i] + Vector3(0, 6.6, 0))
	_mutex.lock()
	lamp_positions.append_array(tmp)
	_mutex.unlock()


## Portal at tube end sample i (`inward` +1: the tube continues toward +s). The terrain has holes just behind the
## portal plane (WorldGen._mark_portal_holes), so the headwall closes the face beside the collar and a cover
## block roofs the first metres of the tube; together they hide the cut from the front, sides and above.
func _build_portal(r: RoadNetwork.Road, i: int, inward: float, e: float, origin: Vector3) -> void:
	var f := _frame(r, i)
	var p: Vector3 = f[0]
	var rt: Vector3 = f[1]
	var fwd := Vector3(rt.z, 0, -rt.x)
	var inn := fwd * inward
	var bk := -fwd   # (rt, up, bk) is right-handed, so the boxes' faces wind outward
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var colors := PackedColorArray()
	var idx := PackedInt32Array()
	var c := Color(0.7, 0.68, 0.64)
	var wall := Color(0.6, 0.58, 0.55)
	var wide := e * 2.0 + 10.0
	# Collar: pillars + lintel around the opening.
	_box_oriented(verts, norms, colors, idx, p + rt * (e + 0.9) + Vector3(0, 3.6, 0) - origin, rt, bk, Vector3(1.8, 8.0, 1.4), c)
	_box_oriented(verts, norms, colors, idx, p - rt * (e + 0.9) + Vector3(0, 3.6, 0) - origin, rt, bk, Vector3(1.8, 8.0, 1.4), c)
	_box_oriented(verts, norms, colors, idx, p + Vector3(0, 8.2, 0) - origin, rt, bk, Vector3(e * 2.0 + 3.6, 2.2, 1.6), c)
	# Headwall wings beside the collar (ground to 9 m) and the cover block over the tube (7.5..12 m, 9 m deep).
	var wing := wide * 0.5 - (e + 1.8)
	for sx: float in [-1.0, 1.0]:
		_box_oriented(verts, norms, colors, idx, p + rt * sx * (e + 1.8 + wing * 0.5) + Vector3(0, 4.25, 0) + inn * 0.4 - origin, rt, bk, Vector3(wing, 9.5, 2.0), wall)
	_box_oriented(verts, norms, colors, idx, p + Vector3(0, 9.75, 0) + inn * 3.9 - origin, rt, bk, Vector3(wide, 4.5, 9.0), wall)
	# Spandrels close the gap between the tube's arch and the collar.
	for k in 8:
		var a0 := Vector2(-cos(PI * k / 8.0) * e, 4.4 + sin(PI * k / 8.0) * 2.8)
		var a1 := Vector2(-cos(PI * (k + 1) / 8.0) * e, 4.4 + sin(PI * (k + 1) / 8.0) * 2.8)
		var b := verts.size()
		for q: Vector2 in [a0, a1, Vector2(a1.x, 7.6), Vector2(a0.x, 7.6)]:
			verts.append(p + rt * q.x + Vector3(0, q.y, 0) - inn * 0.1 - origin)
			norms.append(-inn)
			colors.append(c)
		# Front faces outward (front normal = (v2 - v0) x (v1 - v0)).
		if (verts[b + 2] - verts[b]).cross(verts[b + 1] - verts[b]).dot(inn) < 0.0:
			idx.append_array([b, b + 1, b + 2, b, b + 2, b + 3])
		else:
			idx.append_array([b, b + 2, b + 1, b, b + 3, b + 2])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = idx
	_push({"kind": "concrete", "arrays": arrays, "origin": origin})


func _build_posts_and_signs(r: RoadNetwork.Road, e: float) -> void:
	var n := r.count()
	var keep := _junction_keepout(r)
	var origin := r.pos[0]
	origin.y = 0.0
	var piece := 0
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var colors := PackedColorArray()
	var idx := PackedInt32Array()
	var every := maxi(int(50.0 / r.ds), 1)
	var white := Color(0.92, 0.92, 0.9)
	var black := Color(0.05, 0.05, 0.05)
	var amber := Color(1.0, 0.55, 0.05)
	for i in range(0, n, every):
		if r.flags[i] != 0 or keep[i] != 0:
			continue
		if i / DETAIL_PIECE != piece:
			_push_detail("posts", verts, norms, colors, idx, origin)
			verts = PackedVector3Array()
			norms = PackedVector3Array()
			colors = PackedColorArray()
			idx = PackedInt32Array()
			piece = i / DETAIL_PIECE
			origin = r.pos[i]
			origin.y = 0.0
		var f := _frame(r, i)
		var p: Vector3 = f[0]
		var rt: Vector3 = f[1]
		for side: float in [-1.0, 1.0]:
			var q := p + rt * side * (e + 0.75)
			q.y = data.height_at(q.x, q.z)
			if absf(q.y - p.y) > 1.5:
				q.y = p.y - 0.1
			_box(verts, norms, colors, idx, q + Vector3(0, 0.55, 0) - origin, Vector3(0.12, 1.1, 0.12), white)
			_box(verts, norms, colors, idx, q + Vector3(0, 0.88, 0) - origin, Vector3(0.13, 0.18, 0.13), black)
			_box(verts, norms, colors, idx, q + Vector3(0, 0.95, 0) - origin + (-rt * side * 0.06), Vector3(0.06, 0.1, 0.03), amber)
			stats["posts"] += 1
	_push_detail("posts", verts, norms, colors, idx, origin)
	# Chevron boards on the outside of sharp curves.
	origin = r.pos[0]
	origin.y = 0.0
	piece = 0
	verts = PackedVector3Array()
	norms = PackedVector3Array()
	colors = PackedColorArray()
	idx = PackedInt32Array()
	var last := -1000
	for i in range(2, n - 2):
		if r.flags[i] != 0 or keep[i] != 0 or i - last < int(18.0 / r.ds):
			continue
		var a := Vector2(r.pos[i - 2].x, r.pos[i - 2].z)
		var b := Vector2(r.pos[i].x, r.pos[i].z)
		var c := Vector2(r.pos[i + 2].x, r.pos[i + 2].z)
		var k := WorldGen._curvature(a, b, c)
		if absf(k) < 1.0 / 95.0:
			continue
		last = i
		if i / DETAIL_PIECE != piece:
			_push_detail("signs", verts, norms, colors, idx, origin)
			verts = PackedVector3Array()
			norms = PackedVector3Array()
			colors = PackedColorArray()
			idx = PackedInt32Array()
			piece = i / DETAIL_PIECE
			origin = r.pos[i]
			origin.y = 0.0
		var f := _frame(r, i)
		var p: Vector3 = f[0]
		var rt: Vector3 = f[1]
		var outside := -signf(k)   # right turn (k > 0) -> outside is the left side
		var q := p + rt * outside * (e + 1.4)
		q.y = maxf(data.height_at(q.x, q.z), p.y - 0.6)
		var fwd := Vector3(rt.z, 0, -rt.x)
		_box(verts, norms, colors, idx, q + Vector3(0, 0.6, 0) - origin, Vector3(0.08, 1.2, 0.08), Color(0.3, 0.3, 0.32))
		_chevron(verts, norms, colors, idx, q + Vector3(0, 1.55, 0) - origin, rt, fwd, -outside)
		stats["chevrons"] += 1
	_push_detail("signs", verts, norms, colors, idx, origin)


## Concrete drainage culverts where an embankment crosses a dip in the ground: a pipe under the road with a
## headwall and dark opening at each toe of the embankment (visual only, the embankment carries the road).
func _build_culverts(r: RoadNetwork.Road, e: float, keep: PackedByteArray) -> void:
	var n := r.count()
	var side_h := PackedFloat32Array()
	side_h.resize(n)
	for i in n:
		var f := _frame(r, i)
		var p: Vector3 = f[0]
		var rt: Vector3 = f[1]
		var q1 := p + rt * (e + 14.0)
		var q2 := p - rt * (e + 14.0)
		side_h[i] = minf(data.height_at(q1.x, q1.z), data.height_at(q2.x, q2.z))
	var span := int(30.0 / r.ds)
	var gap := int(250.0 / r.ds)
	var origin := r.pos[0]
	origin.y = 0.0
	var piece := 0
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var colors := PackedColorArray()
	var idx := PackedInt32Array()
	var concrete := Color(0.78, 0.76, 0.72)
	var last := -gap
	for i in range(span, n - span):
		if r.flags[i] != 0 or keep[i] != 0 or i - last < gap or r.pos[i].y - side_h[i] < 2.2:
			continue
		var is_min := true
		for j in range(i - span, i + span + 1, 2):
			if side_h[j] < side_h[i] - 0.01:
				is_min = false
				break
		if not is_min or maxf(side_h[i - span], side_h[i + span]) - side_h[i] < 0.8:
			continue
		var f := _frame(r, i)
		var p: Vector3 = f[0]
		var rt: Vector3 = f[1]
		var fwd := Vector3(rt.z, 0.0, -rt.x)
		# Toe of the embankment on each side: where the ground is back down near the dip level.
		var ends: Array[Vector3] = []
		for side: float in [-1.0, 1.0]:
			var toe := Vector3.INF
			for x in range(int(e) + 2, int(e) + 34):
				var q := p + rt * side * float(x)
				var gy := data.height_at(q.x, q.z)
				if gy < side_h[i] + 1.3:
					toe = Vector3(q.x, gy, q.z)
					break
			if toe == Vector3.INF:
				break
			ends.append(toe)
		if ends.size() < 2:
			continue
		last = i
		if i / DETAIL_PIECE != piece:
			_push_detail("concrete", verts, norms, colors, idx, origin)
			verts = PackedVector3Array()
			norms = PackedVector3Array()
			colors = PackedColorArray()
			idx = PackedInt32Array()
			piece = i / DETAIL_PIECE
			origin = r.pos[i]
			origin.y = 0.0
		for k in 2:
			var side := -1.0 if k == 0 else 1.0
			var toe: Vector3 = ends[k]
			var out := rt * side
			var c := toe + Vector3(0, 0.55, 0) - origin
			_box_oriented(verts, norms, colors, idx, toe + Vector3(0, 0.8, 0) - out * 0.2 - origin, fwd, rt, Vector3(3.0, 1.6, 0.35), concrete)
			_tube(verts, norms, colors, idx, c - out * 0.3, c + out * 0.35, 0.58, concrete)
			_tube(verts, norms, colors, idx, c + out * 0.36, c + out * 0.36, 0.46, Color(0.04, 0.04, 0.04), true)
		stats["culverts"] += 1
		_mutex.lock()
		culvert_positions.append(p)
		_mutex.unlock()
	_push_detail("concrete", verts, norms, colors, idx, origin)


## Open cylinder from a to b (10 sides); `cap` instead emits a flat disc at a (used as a dark pipe opening).
static func _tube(verts: PackedVector3Array, norms: PackedVector3Array, colors: PackedColorArray, idx: PackedInt32Array, a: Vector3, b: Vector3, radius: float, col: Color, cap := false) -> void:
	var axis := (b - a).normalized() if not cap else (b - a + Vector3(0.001, 0, 0)).normalized()
	var u := axis.cross(Vector3.UP).normalized()
	var v := axis.cross(u).normalized()
	var seg := 10
	var base := verts.size()
	if cap:
		verts.append(a)
		norms.append(-u.cross(v).normalized())
		colors.append(col)
		for k in seg:
			var ang := TAU * float(k) / seg
			verts.append(a + (u * cos(ang) + v * sin(ang)) * radius)
			norms.append(-u.cross(v).normalized())
			colors.append(col)
		for k in seg:
			idx.append_array([base, base + 1 + k, base + 1 + (k + 1) % seg])
		return
	for k in seg:
		var ang := TAU * float(k) / seg
		var d := u * cos(ang) + v * sin(ang)
		verts.append_array([a + d * radius, b + d * radius])
		norms.append_array([d, d])
		colors.append_array([col, col])
	for k in seg:
		var i0 := base + k * 2
		var i1 := base + ((k + 1) % seg) * 2
		idx.append_array([i0, i1, i0 + 1, i1, i1 + 1, i0 + 1])


func _chevron(verts: PackedVector3Array, norms: PackedVector3Array, colors: PackedColorArray, idx: PackedInt32Array, c: Vector3, rt: Vector3, fwd: Vector3, dir: float) -> void:
	# Yellow board facing traffic in both directions with black arrow chevrons pointing `dir` (+1 = right).
	_box_oriented(verts, norms, colors, idx, c, rt, -fwd, Vector3(1.0, 0.75, 0.04), Color(0.98, 0.78, 0.05))
	for face: float in [-1.0, 1.0]:
		for k in 2:
			var cx := (-0.18 + k * 0.32) * dir
			var tip := c + rt * (cx + 0.14 * dir) + fwd * face * 0.03
			var top := c + rt * cx + Vector3(0, 0.26, 0) + fwd * face * 0.03
			var bot := c + rt * cx - Vector3(0, 0.26, 0) + fwd * face * 0.03
			var top2 := top + rt * 0.11 * -dir
			var bot2 := bot + rt * 0.11 * -dir
			var tip2 := tip + rt * 0.11 * -dir
			var b := verts.size()
			verts.append_array([top, tip, bot, top2, tip2, bot2])
			for m in 6:
				norms.append(fwd * face)
				colors.append(Color(0.04, 0.04, 0.04))
			idx.append_array([b + 0, b + 1, b + 3, b + 3, b + 1, b + 4, b + 4, b + 1, b + 2, b + 4, b + 2, b + 5])
			idx.append_array([b + 0, b + 3, b + 1, b + 3, b + 4, b + 1, b + 4, b + 2, b + 1, b + 4, b + 5, b + 2])


# ------------------------------------------------------------------ junction corner fillets

const SIGN_GAP := 0.9          # junction sign board end to the nearest paved edge of any road


func _junction_signs(parent: RoadNetwork.Road, child: RoadNetwork.Road, jd: Dictionary) -> void:
	# Sign on the child road ~28 m before the junction naming the road you are joining, and one on the
	# parent road ~45 m before the junction (traffic direction of increasing s) naming the side road. A spot
	# that is too close to any road, on a bridge or in a tunnel moves the sign further back (or a little closer).
	var end_i := 0 if int(jd["child_end"]) == 0 else child.count() - 1
	var dir := 1.0 if end_i == 0 else -1.0
	var w1 := maxf(parent.name.length() * 0.24 + 0.6, 2.4)
	for back: float in [28.0, 36.0, 22.0, 44.0, 55.0, 16.0, 66.0, 80.0]:
		var s_child := clampf(end_i * child.ds + dir * back, 0.0, child.length)
		var sg := _sign_spot(child, s_child, -child.flat_tangent_at(s_child) * dir, w1)
		if not sg.is_empty():
			_push({"kind": "sign_label", "xf": sg["xf"], "text": parent.name, "width": w1})
			break
	var w2 := maxf(child.name.length() * 0.24 + 0.9, 2.4)
	for back: float in [45.0, 55.0, 35.0, 65.0, 28.0, 80.0, 95.0, 110.0]:
		var sp := int(jd["parent_index"]) * parent.ds - back
		if parent.loop:
			sp = fposmod(sp, parent.length)
		elif sp <= 0.0:
			continue
		var sg := _sign_spot(parent, sp, parent.flat_tangent_at(sp), w2)
		if not sg.is_empty():
			_push({"kind": "sign_label", "xf": sg["xf"], "text": child.name + "  >", "width": w2})
			break


## Direction sign {xf} at arclength s on the right of `travel`, with its whole board (width w, posts at +-0.4 w)
## at least SIGN_GAP beyond the paved edge of every road; {} on or next to a bridge / tunnel or too close to a road.
func _sign_spot(r: RoadNetwork.Road, s: float, travel: Vector3, w: float) -> Dictionary:
	for k in 5:
		var sk := s + (k - 2) * 6.0
		if r.flag_at(fposmod(sk, r.length) if r.loop else clampf(sk, 0.0, r.length)) != 0:
			return {}
	var right := Vector3(-travel.z, 0, travel.x)
	var c := r.point_at(s) + right * (r.width * 0.5 + r.shoulder + SIGN_GAP + w * 0.5)
	for f: float in [-0.5, -0.4, 0.0, 0.4, 0.5]:
		if data.network.edge_clearance(c + right * w * f) < SIGN_GAP - 0.05:
			return {}
	c.y = maxf(data.height_at(c.x, c.z), r.point_at(s).y - 1.0)
	return {"xf": Transform3D(Basis.looking_at(-travel, Vector3.UP), c)}


static func _line_intersect(p1: Vector2, d1: Vector2, p2: Vector2, d2: Vector2) -> Vector2:
	var den := d1.x * d2.y - d1.y * d2.x
	if absf(den) < 0.0001:
		return Vector2.INF
	var t := ((p2.x - p1.x) * d2.y - (p2.y - p1.y) * d2.x) / den
	return p1 + d1 * t


## Corner fillets of a junction: the child road's frame at the parent edge plus one arc per side where the
## child's edge meets the parent's edge {a: corner point, up: along the parent edge, uc: along the child,
## o: arc centre, radius}. Shared by the fillet mesh and the street-lamp clearance check.
static func junction_corners(parent: RoadNetwork.Road, child: RoadNetwork.Road, jd: Dictionary) -> Dictionary:
	var pi_: int = int(jd["parent_index"])
	var p0 := parent.pos[pi_]
	var s_par := pi_ * parent.ds
	var t3 := parent.flat_tangent_at(s_par)
	var t := Vector2(t3.x, t3.z)
	var np := Vector2(-t.y, t.x)
	var ep := parent.width * 0.5 + parent.shoulder
	var ec := child.width * 0.5 + child.shoulder
	var end_i := 0 if int(jd["child_end"]) == 0 else child.count() - 1
	var inner_i := mini(end_i + 8, child.count() - 1) if end_i == 0 else maxi(end_i - 8, 0)
	var c0 := Vector2(child.pos[end_i].x, child.pos[end_i].z)
	var ci := Vector2(child.pos[inner_i].x, child.pos[inner_i].z)
	var d := (ci - c0).normalized()
	var nc := Vector2(-d.y, d.x)
	var side := signf(d.dot(np))
	var arcs: Array = []
	var out := {"p0": p0, "s_par": s_par, "t": t, "side": side, "ep": ep, "end_i": end_i, "c0": c0, "d": d, "nc": nc, "arcs": arcs}
	if side == 0.0:
		return out
	var edge_p := Vector2(p0.x, p0.z) + np * side * ep
	var radius := clampf(ec * 1.4, 5.0, 9.0)
	for cs: float in [-1.0, 1.0]:
		var a := _line_intersect(edge_p, t, c0 + nc * cs * ec, d)
		if a == Vector2.INF or a.distance_to(c0) > 40.0:
			continue
		var up := t * signf((a - c0).dot(t))
		if up.length() < 0.5:
			continue
		var ang := up.angle_to(d)
		if absf(ang) < 0.35 or absf(ang) > 2.8:
			continue
		arcs.append({"a": a, "up": up, "uc": d, "o": a + (up + d) * radius, "radius": radius})
	return out


func _build_junction_fillets() -> void:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	var faces := PackedVector3Array()
	var origin := Vector3.ZERO
	for jd: Dictionary in data.network.junctions:
		var parent := data.network.get_road(jd["parent"])
		var child := data.network.get_road(jd["child"])
		if parent == null or child == null:
			continue
		_junction_signs(parent, child, jd)
		var jc := junction_corners(parent, child, jd)
		var p0: Vector3 = jc["p0"]
		var s_par: float = jc["s_par"]
		var t: Vector2 = jc["t"]
		var side: float = jc["side"]
		var ep: float = jc["ep"]
		var end_i: int = jc["end_i"]
		var c0: Vector2 = jc["c0"]
		var d: Vector2 = jc["d"]
		var nc: Vector2 = jc["nc"]
		for arc: Dictionary in jc["arcs"]:
			var a: Vector2 = arc["a"]
			var up: Vector2 = arc["up"]
			var uc: Vector2 = arc["uc"]
			var o: Vector2 = arc["o"]
			var radius: float = arc["radius"]
			var b0 := verts.size()
			var ay := parent.surface_point(s_par + (a - Vector2(p0.x, p0.z)).dot(t), side * ep).y - 0.012
			verts.append(Vector3(a.x, ay, a.y))
			norms.append(Vector3.UP)
			uvs.append(Vector2(0.5, 0.0))
			var steps := 7
			var start_v := (a + up * radius) - o
			var end_v := (a + uc * radius) - o
			var a0 := atan2(start_v.y, start_v.x)
			var a1 := atan2(end_v.y, end_v.x)
			var da := wrapf(a1 - a0, -PI, PI)
			var cs0 := float(end_i) * child.ds
			var cdir := 1.0 if end_i == 0 else -1.0
			for k in steps + 1:
				var aa := a0 + da * float(k) / steps
				var q := o + Vector2(cos(aa), sin(aa)) * radius
				# Blend from the parent's edge height (arc start) to the child's height (arc end); both roads
				# may be on a grade along the arc at acute junctions.
				var py := parent.surface_point(s_par + (q - Vector2(p0.x, p0.z)).dot(t), side * ep).y
				var lat_c := (q - c0).dot(nc) * cdir
				var cy := child.surface_point(clampf(cs0 + cdir * (q - c0).dot(d), 0.0, child.length), lat_c).y
				var qy := lerpf(py, cy, float(k) / steps) - 0.012
				verts.append(Vector3(q.x, qy, q.y))
				norms.append(Vector3.UP)
				uvs.append(Vector2(0.5, float(k)))
			for k in steps:
				var i1 := b0 + 1 + k
				var i2 := b0 + 2 + k
				# Choose winding so the face points up (clockwise seen from above).
				var va := verts[b0]
				var vb := verts[i1]
				var vc := verts[i2]
				if (vc - va).cross(vb - va).y > 0.0:
					idx.append_array([b0, i1, i2])
					faces.append_array([va, vb, vc])
				else:
					idx.append_array([b0, i2, i1])
					faces.append_array([va, vc, vb])
	if idx.is_empty():
		return
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = idx
	_push({"kind": "road", "arrays": arrays, "origin": origin, "faces": faces, "surface": &"asphalt", "road_id": "junction",
		"width": 8.0, "shoulder": 0.0, "lanes": 1, "marking": 0, "surface_kind": 0})


# ------------------------------------------------------------------ street lamps

## Street-lamp spots along STREET roads (every 36 m, alternating sides, 0.9 m beyond the shoulder), kept off
## every road surface: none in a junction mouth, on a corner fillet or within 0.6 m of any road's paved edge.
## Returns [lamp position at road height, road centre point] pairs. The settlement planner stands a
## Lamp_Street post under each one and the lamp pool lights them, so both always agree.
static func street_lamp_spots(net: RoadNetwork) -> Array:
	var corners: Array[Vector3] = []      # (x, z, radius) of every corner fillet
	for jd: Dictionary in net.junctions:
		var parent := net.get_road(jd["parent"])
		var child := net.get_road(jd["child"])
		if parent == null or child == null:
			continue
		for arc: Dictionary in junction_corners(parent, child, jd)["arcs"]:
			var a: Vector2 = arc["a"]
			corners.append(Vector3(a.x, a.y, float(arc["radius"])))
	var out: Array = []
	for r in net.roads:
		if r.cls != WorldLayout.RoadClass.STREET:
			continue
		var n := r.count()
		var e := r.width * 0.5 + r.shoulder
		var keep := junction_keepout(net, r)
		var side := 1.0
		for i in range(0, n, int(36.0 / r.ds)):
			if r.flags[i] != 0 or keep[i] != 0:
				continue
			var a := r.pos[(i - 1 + n) % n] if (r.loop or i > 0) else r.pos[i]
			var b := r.pos[(i + 1) % n] if (r.loop or i < n - 1) else r.pos[i]
			var t := Vector3(b.x - a.x, 0.0, b.z - a.z).normalized()
			var rt := Vector3(-t.z, 0.0, t.x)
			for k in 2:
				var p := r.pos[i] + rt * side * (e + 0.9)
				side = -side
				if _lamp_clear(net, p, corners):
					out.append([p, r.pos[i]])
					break
	return out


static func _lamp_clear(net: RoadNetwork, p: Vector3, corners: Array[Vector3]) -> bool:
	if net.edge_clearance(p) < 0.6:
		return false
	for c in corners:
		if Vector2(p.x - c.x, p.z - c.y).length() < c.z + 1.0:
			return false
	return true


static func _box(verts: PackedVector3Array, norms: PackedVector3Array, colors: PackedColorArray, idx: PackedInt32Array, c: Vector3, size: Vector3, col: Color) -> void:
	_box_oriented(verts, norms, colors, idx, c, Vector3.RIGHT, Vector3.BACK, size, col)


static func _box_oriented(verts: PackedVector3Array, norms: PackedVector3Array, colors: PackedColorArray, idx: PackedInt32Array, c: Vector3, ax: Vector3, az: Vector3, size: Vector3, col: Color) -> void:
	var hx := ax * size.x * 0.5
	var hy := Vector3.UP * size.y * 0.5
	var hz := az * size.z * 0.5
	var dirs := [[hx, hy, hz], [-hx, hy, -hz], [hz, hy, -hx], [-hz, hy, hx], [hy, hz, hx], [-hy, -hz, hx]]
	# Each face: normal axis n, with u, v spanning vectors.
	var faces_def := [[hx, hz, hy], [-hx, -hz, hy], [hz, -hx, hy], [-hz, hx, hy], [hy, hx, hz], [-hy, -hx, hz]]
	for fd: Array in faces_def:
		var n: Vector3 = fd[0]
		var u: Vector3 = fd[1]
		var v: Vector3 = fd[2]
		var b := verts.size()
		var center := c + n
		verts.append_array([center - u - v, center + u - v, center + u + v, center - u + v])
		var nn := n.normalized()
		for k in 4:
			norms.append(nn)
			colors.append(col)
		idx.append_array([b, b + 1, b + 2, b, b + 2, b + 3])


static func _recompute_normals(verts: PackedVector3Array, idx: PackedInt32Array) -> PackedVector3Array:
	var nrm := PackedVector3Array()
	nrm.resize(verts.size())
	for t in range(0, idx.size(), 3):
		var a := verts[idx[t]]
		var b := verts[idx[t + 1]]
		var c := verts[idx[t + 2]]
		var fn := (c - a).cross(b - a)
		nrm[idx[t]] += fn
		nrm[idx[t + 1]] += fn
		nrm[idx[t + 2]] += fn
	for i in nrm.size():
		nrm[i] = nrm[i].normalized() if nrm[i].length() > 0.0 else Vector3.UP
	return nrm


func _exit_tree() -> void:
	for id in _tasks:
		WorkerThreadPool.wait_for_task_completion(id)
	_tasks.clear()
