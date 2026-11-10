extends RefCounted
## Pavements along the town streets (STREET class roads): purely visual flat ribbons (no colliders, road meshes
## and colliders untouched) plus the walking polylines the pedestrians follow.

const WIDTH := 2.3
const GAP := 0.45
const LIFT := 0.05
const STEP := 3.0
const END_MARGIN := 9.0
const MIN_RUN := 14.0
const SHADER := preload("res://assets/shaders/sidewalk.gdshader")


class Path extends RefCounted:
	var pts := PackedVector3Array()
	var cum := PackedFloat32Array()
	var length := 0.0
	var road_id := ""
	var side := 1

	func finish() -> void:
		cum.resize(pts.size())
		var t := 0.0
		for i in pts.size():
			if i > 0:
				t += pts[i].distance_to(pts[i - 1])
			cum[i] = t
		length = t

	func _idx(s: float) -> int:
		var lo := 0
		var hi := cum.size() - 2
		while lo < hi:
			var mid := (lo + hi + 1) >> 1
			if cum[mid] <= s:
				lo = mid
			else:
				hi = mid - 1
		return lo

	func at(s: float) -> Vector3:
		s = clampf(s, 0.0, length)
		var i := _idx(s)
		var seg := maxf(cum[i + 1] - cum[i], 0.001)
		return pts[i].lerp(pts[i + 1], (s - cum[i]) / seg)

	func tangent(s: float) -> Vector3:
		var i := _idx(clampf(s, 0.0, length))
		var t := pts[i + 1] - pts[i]
		t.y = 0.0
		return t.normalized() if t.length() > 0.0001 else Vector3.FORWARD

	func closest_s(p: Vector3) -> float:
		var best := INF
		var bs := 0.0
		for i in pts.size() - 1:
			var a := pts[i]
			var ab := pts[i + 1] - a
			ab.y = 0.0
			var ap := p - a
			ap.y = 0.0
			var k := clampf(ap.dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
			var d := (a + ab * k - Vector3(p.x, a.y, p.z)).length_squared()
			if d < best:
				best = d
				bs = cum[i] + k * sqrt(ab.length_squared())
		return bs


var paths: Array[Path] = []
var mesh_node: MeshInstance3D


func build(world: Node) -> void:
	var data: WorldData = world.data
	var net: RoadNetwork = data.network
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var norms := PackedVector3Array()
	for road: RoadNetwork.Road in net.roads:
		if road.cls != WorldLayout.RoadClass.STREET:
			continue
		var off := road.width * 0.5 + road.shoulder + GAP + WIDTH * 0.5
		for side: int in [1, -1]:
			var run: Array[Vector3] = []
			var s := END_MARGIN
			while s <= road.length - END_MARGIN + 0.01:
				var q := _sample(world, data, net, road, s, side, off)
				if q.y < -9000.0 or (not run.is_empty() and absf(q.y - run[run.size() - 1].y) > 0.8):
					_flush(run, road, side, verts, uvs, norms, data)
					run = []
					if q.y < -9000.0:
						s += STEP
						continue
				run.append(q)
				s += STEP
			_flush(run, road, side, verts, uvs, norms, data)
	if verts.is_empty():
		return
	var arr: Array = []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_TEX_UV] = uvs
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	m.surface_set_material(0, mat)
	mesh_node = MeshInstance3D.new()
	mesh_node.name = "Pavements"
	mesh_node.mesh = m
	mesh_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh_node.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF


func _sample(world: Node, data: WorldData, net: RoadNetwork, road: RoadNetwork.Road, s: float, side: int, off: float) -> Vector3:
	var bad := Vector3(0, -10000.0, 0)
	if road.flag_at(s) != 0:
		return bad
	var q := road.point_at(s) + road.right_at(s) * (float(side) * off)
	var h := data.height_at(q.x, q.z)
	var wl: float = world.water_level_at(q.x, q.z)
	if wl > h - 0.25:
		return bad
	if absf(h - road.point_at(s).y) > 1.6:
		return bad
	if net.edge_clearance(q, 14.0) < GAP + WIDTH * 0.5 - 0.3:
		return bad
	q.y = h + LIFT
	return q


func _flush(run: Array[Vector3], road: RoadNetwork.Road, side: int, verts: PackedVector3Array, uvs: PackedVector2Array, norms: PackedVector3Array, data: WorldData) -> void:
	if run.size() < 2 or (run.size() - 1) * STEP < MIN_RUN:
		return
	var p := Path.new()
	p.road_id = road.id
	p.side = side
	var a: Array[Vector3] = []
	var b: Array[Vector3] = []
	for i in run.size():
		var q := run[i]
		var t := run[mini(i + 1, run.size() - 1)] - run[maxi(i - 1, 0)]
		t.y = 0.0
		t = t.normalized()
		var rt := Vector3(-t.z, 0.0, t.x) * (WIDTH * 0.5)
		var pa := q + rt
		var pb := q - rt
		pa.y = data.height_at(pa.x, pa.z) + LIFT
		pb.y = data.height_at(pb.x, pb.z) + LIFT
		a.append(pa)
		b.append(pb)
		p.pts.append(q)
	p.finish()
	paths.append(p)
	for i in run.size() - 1:
		var v0 := p.cum[i]
		var v1 := p.cum[i + 1]
		for k: Array in [[a[i], Vector2(0, v0)], [b[i], Vector2(1, v0)], [b[i + 1], Vector2(1, v1)], [a[i], Vector2(0, v0)], [b[i + 1], Vector2(1, v1)], [a[i + 1], Vector2(0, v1)]]:
			verts.append(k[0] as Vector3)
			uvs.append(k[1] as Vector2)
			norms.append(Vector3.UP)
