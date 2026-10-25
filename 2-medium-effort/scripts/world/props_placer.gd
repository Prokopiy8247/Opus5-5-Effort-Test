extends Node3D
## Places settlements, landmarks and road furniture (Blender kit scenes) deterministically along the network.

const DIR: String = "res://assets/imported/props/"

var world: WorldData
var scenes: Dictionary = {}
var rng := RandomNumberGenerator.new()
var lamp_positions: Array[Vector3] = []
var rotors: Array[Node3D] = []
var night_lights: Array[Light3D] = []
var placed: Dictionary = {}
var lit_mats: Array[StandardMaterial3D] = []
var _was_night: bool = true


func _scene(nm: String) -> PackedScene:
	if not scenes.has(nm):
		scenes[nm] = load(DIR + nm + ".glb")
	return scenes[nm]


func build(w: WorldData) -> void:
	world = w
	rng.seed = 4242
	var dressing: Node = get_parent().get("dressing")
	# --- settlements
	_village(Vector2(-950, 120), 14, "Greenvale", dressing)
	_village(Vector2(-350, 1450), 8, "Saltmere Harbour", dressing)
	_village(Vector2(-1650, 200), 5, "Westcliff", dressing)
	_village(Vector2(1650, 250), 4, "Dustwater", dressing)
	for f in [Vector2(-1050, 600), Vector2(-1250, -350), Vector2(-850, -550), Vector2(-500, 880), Vector2(150, -200)]:
		_farm(f, dressing)
	_landmark("gas_station", Vector2(200, 160), dressing, 26.0)
	_landmark("gas_station", Vector2(1710, 700), dressing, 26.0)
	_landmark("diner", Vector2(-1300, 170), dressing, 16.0)
	_landmark("diner", Vector2(1450, -250), dressing, 16.0)
	_landmark("lighthouse", Vector2(1765, 1575), dressing, 14.0, false)
	_landmark("castle", Vector2(110, -1810), dressing, 28.0, false)
	for i in 7:
		var p := Vector2(760, 640) + Vector2(cos(i * 0.9) * (60 + i * 30), sin(i * 0.9) * (60 + i * 25))
		_landmark("wind_turbine", p, dressing, 8.0, false)
	for i in 3:
		var b: Node3D = _place("boat", Vector3(-380 + i * 40, 0.15, 1585 + (i % 2) * 22), rng.randf() * TAU)
		b.position.y = 0.1
	_road_signs()
	print("[props] placed ", placed)


func _place(nm: String, pos: Vector3, yaw: float, collide: bool = true) -> Node3D:
	var n: Node3D = _scene(nm).instantiate()
	n.position = pos
	n.rotation.y = yaw
	add_child(n)
	placed[nm] = placed.get(nm, 0) + 1
	var meshes: Array = n.find_children("*", "MeshInstance3D", true, false)
	for mi in meshes:
		var m3: MeshInstance3D = mi
		m3.visibility_range_end = 1400.0 if nm in ["lighthouse", "castle", "wind_turbine"] else 650.0
		if m3.name.begins_with("Rotor"):
			rotors.append(m3)
		for s in m3.mesh.get_surface_count():
			var mat: Material = m3.mesh.surface_get_material(s)
			if mat and (mat.resource_name.begins_with("WindowLit") or mat.resource_name.begins_with("Lamp")):
				if mat is StandardMaterial3D and not lit_mats.has(mat):
					lit_mats.append(mat)
	if collide and not meshes.is_empty():
		var aabb: AABB = AABB()
		var first: bool = true
		for mi in meshes:
			var bb: AABB = (mi as MeshInstance3D).transform * (mi as MeshInstance3D).mesh.get_aabb()
			aabb = bb if first else aabb.merge(bb)
			first = false
		var body := StaticBody3D.new()
		body.collision_layer = 1
		body.collision_mask = 0
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		var sz: Vector3 = aabb.size
		if nm == "gas_station":
			# only the shop building is solid; the forecourt stays drivable
			sz = Vector3(12, 4, 7)
			cs.position = Vector3(0, 2, -8)
		elif nm.begins_with("sign") or nm == "street_lamp":
			sz = Vector3(0.25, aabb.size.y, 0.25)
			cs.position = Vector3(0, aabb.size.y * 0.5, 0)
		else:
			cs.position = aabb.get_center()
		bs.size = sz
		cs.shape = bs
		body.add_child(cs)
		n.add_child(body)
	return n


func _ground(x: float, z: float, r: float) -> float:
	var m: float = world.height(x, z)
	for o in [Vector2(r, r), Vector2(-r, r), Vector2(r, -r), Vector2(-r, -r)]:
		m = minf(m, world.height(x + o.x, z + o.y))
	return m


func _free_spot(p: Vector2, r: float) -> bool:
	var q: Dictionary = world.road_query(p.x, p.y, 60.0)
	if q.ok and q.d < q.hw + r + 2.0:
		return false
	if world.height(p.x, p.y) < 1.5:
		return false
	return true


func _face_road(p: Vector2) -> float:
	var nr: Dictionary = world.nearest_road_point(Vector3(p.x, 0, p.y))
	if nr.is_empty():
		return 0.0
	var t: Transform3D = world.road_point(nr.road, nr.s)
	var d: Vector3 = t.origin - Vector3(p.x, 0, p.y)
	# local +Z of kit buildings is their front
	return atan2(d.x, d.z)


func _village(c: Vector2, count: int, vname: String, dressing: Node) -> void:
	var made: int = 0
	var tries: int = 0
	while made < count and tries < count * 30:
		tries += 1
		var a: float = rng.randf() * TAU
		var r: float = rng.randf_range(20.0, 120.0)
		var p: Vector2 = c + Vector2(cos(a), sin(a)) * r
		if not _free_spot(p, 7.0):
			continue
		var q: Dictionary = world.road_query(p.x, p.y, 60.0)
		if not q.ok or q.d > q.hw + 30.0:
			continue
		var ok: bool = true
		for e in dressing.exclusions:
			if p.distance_to(Vector2(e.x, e.y)) < e.z + 6.0:
				ok = false
				break
		if not ok:
			continue
		var nm: String = ["house_0", "house_1", "house_2"][rng.randi() % 3]
		var y: float = _ground(p.x, p.y, 5.0)
		_place(nm, Vector3(p.x, y - 0.1, p.y), _face_road(p))
		dressing.exclusions.append(Vector3(p.x, p.y, 9.0))
		made += 1
	# street lamps along the roads through the settlement
	for ri in world.roads.size():
		var rd: Dictionary = world.roads[ri]
		var pts: PackedVector3Array = rd.pts
		for i in range(0, pts.size(), 8):
			if Vector2(pts[i].x, pts[i].z).distance_to(c) < 140.0 and rd.flags[i] == 0:
				var side: float = 1.0 if (i / 8) % 2 == 0 else -1.0
				var pos: Vector3 = pts[i] + rd.right[i] * side * (rd.hw + 1.4)
				var lamp: Node3D = _place("street_lamp", Vector3(pos.x, world.height(pos.x, pos.z), pos.z), atan2(-rd.right[i].x * side, -rd.right[i].z * side) + PI * 0.5)
				lamp.rotation.y = atan2(rd.right[i].x * side, rd.right[i].z * side) + PI
				lamp_positions.append(pos)
				if (i / 8) % 2 == 1:
					continue
				var ol := OmniLight3D.new()
				ol.position = Vector3(0, 6.6, 1.6)
				ol.omni_range = 16.0
				ol.light_energy = 0.0
				ol.visible = false
				ol.shadow_enabled = false
				ol.light_color = Color(1.0, 0.8, 0.5)
				ol.distance_fade_enabled = true
				ol.distance_fade_begin = 180.0
				ol.distance_fade_length = 60.0
				lamp.add_child(ol)
				night_lights.append(ol)
	dressing.exclusions.append(Vector3(c.x, c.y, 25.0))
	set_meta("village_" + vname.to_snake_case().replace(" ", "_"), c)


func _farm(c: Vector2, dressing: Node) -> void:
	var p: Vector2 = c
	for i in 20:
		if _free_spot(p, 14.0):
			break
		p = c + Vector2(rng.randf_range(-60, 60), rng.randf_range(-60, 60))
	var yaw: float = _face_road(p)
	_place("barn", Vector3(p.x, _ground(p.x, p.y, 8.0) - 0.1, p.y), yaw)
	var hp: Vector2 = p + Vector2(cos(yaw), -sin(yaw)) * 22.0
	if _free_spot(hp, 6.0):
		_place("house_2", Vector3(hp.x, _ground(hp.x, hp.y, 5.0) - 0.1, hp.y), yaw)
	dressing.exclusions.append(Vector3(p.x, p.y, 22.0))
	# paddock fence
	for k in 10:
		var a: float = k / 10.0 * TAU
		var fp: Vector2 = p + Vector2(cos(a), sin(a)) * 34.0
		if _free_spot(fp, 2.0):
			_place("fence", Vector3(fp.x, world.height(fp.x, fp.y), fp.y), -a, false)


func _landmark(nm: String, c: Vector2, dressing: Node, r: float, face_road: bool = true) -> void:
	var p: Vector2 = c
	for i in 30:
		if _free_spot(p, r * 0.5):
			break
		var q: Dictionary = world.road_query(p.x, p.y, 60.0)
		if q.ok:
			# push away from the road along its normal
			var rd: Dictionary = world.roads[q.road]
			var rt: Vector3 = rd.right[q.seg]
			p += Vector2(rt.x, rt.z) * signf(q.side if q.side != 0.0 else 1.0) * 4.0
		else:
			break
	var yaw: float = _face_road(p) if face_road else rng.randf() * TAU
	_place(nm, Vector3(p.x, _ground(p.x, p.y, r * 0.35) - 0.05, p.y), yaw)
	dressing.exclusions.append(Vector3(p.x, p.y, r))


func _road_signs() -> void:
	for ri in world.roads.size():
		var rd: Dictionary = world.roads[ri]
		var pts: PackedVector3Array = rd.pts
		var m: int = pts.size()
		# speed limit sign near both ends
		for end in [[12, 1.0], [m - 13, -1.0]]:
			var i: int = clampi(end[0], 0, m - 1)
			if rd.flags[i] != 0 or rd.surface >= 2:
				continue
			var dirn: float = end[1]
			var pos: Vector3 = pts[i] + rd.right[i] * dirn * (rd.hw + 1.2)
			var fwd: Vector3 = (pts[mini(i + 1, m - 1)] - pts[maxi(i - 1, 0)]).normalized() * dirn
			_place("sign_speed", Vector3(pos.x, world.height(pos.x, pos.z), pos.z), atan2(fwd.x, fwd.z) + PI)
		# chevrons on the outside of sharp curves
		var last: int = -100
		var curv: PackedFloat32Array = rd.curv
		for i in range(8, m - 8):
			if absf(curv[i]) > 1.0 / 75.0 and i - last > 5 and rd.flags[i] == 0:
				last = i
				var outside: float = -signf(curv[i])
				var pos: Vector3 = pts[i] + rd.right[i] * outside * (rd.hw + 1.6)
				var to_road: Vector3 = -rd.right[i] * outside
				var fwd: Vector3 = (pts[i + 1] - pts[i - 1]).normalized()
				# face oncoming traffic of the lane that sees it on the outside
				var face: Vector3 = (-fwd + to_road * 0.6).normalized()
				_place("sign_chevron", Vector3(pos.x, world.height(pos.x, pos.z), pos.z), atan2(face.x, face.z) + PI)
	# direction boards at junctions
	for node in world.node_roads:
		if (world.node_roads[node] as Array).size() >= 3:
			var c: Vector2 = RoadLayout.NODES[node]
			var p := c + Vector2(14, 14)
			if _free_spot(p, 1.0):
				_place("sign_direction", Vector3(p.x, world.height(p.x, p.y), p.y), rng.randf() * TAU)


func _process(delta: float) -> void:
	var _pf: int = Time.get_ticks_usec()
	_inner_props(delta)
	Game.prof_add("props", _pf)


func _inner_props(delta: float) -> void:
	for r in rotors:
		r.rotate_object_local(Vector3.FORWARD, delta * 1.3)
	var night: bool = Game.sky != null and Game.sky.is_night()
	var e: float = 3.0 if night else 0.0
	if night != _was_night:
		_was_night = night
		for l in night_lights:
			l.visible = night
			l.light_energy = 2.2
	for m in lit_mats:
		m.emission_energy_multiplier = e
