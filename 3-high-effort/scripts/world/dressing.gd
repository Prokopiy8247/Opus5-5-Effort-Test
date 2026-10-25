extends Node3D
## World dressing: vegetation (per-chunk MultiMeshes), settlements and landmarks from the
## Blender kit, road signs, street lights, wind turbines and the festival site.

const PROPS := "res://assets/imported/props/"
const CHUNK := 256.0
const STEP := 10.0

var world: World
var data: WorldData
var meshes := {}
var scenes := {}
var lamps: Array[OmniLight3D] = []
var rotors: Array[Node3D] = []
var boats: Array[Node3D] = []
var window_mat: StandardMaterial3D
var stats := {"trees": 0, "shrubs": 0, "rocks": 0, "buildings": 0, "signs": 0, "lamps": 0}
var forest := FastNoiseLite.new()
var jitter := FastNoiseLite.new()
var _lights_on := false
var grass: Node3D

const SPECIES := ["tree_broadleaf", "tree_pine", "tree_poplar", "tree_umbrella", "cactus", "shrub", "shrub_dry",
	"rock_a", "rock_b", "rock_red"]


func build(w: World) -> void:
	world = w
	data = w.data
	forest.seed = 99
	forest.frequency = 1.0 / 380.0
	forest.fractal_octaves = 3
	jitter.seed = 7
	jitter.frequency = 0.9
	for s in SPECIES:
		meshes[s] = _mesh_of(s)
	await get_tree().process_frame
	_vegetation()
	await get_tree().process_frame
	_places()
	_road_signs()
	_lamp_and_window_setup()
	var gs := load("res://scripts/world/grass.gd")
	if gs:
		grass = gs.new()
		grass.name = "Grass"
		add_child(grass)
		grass.setup(world)


func _scene(name: String) -> PackedScene:
	if not scenes.has(name):
		scenes[name] = load(PROPS + name + ".glb") if ResourceLoader.exists(PROPS + name + ".glb") else null
	return scenes[name]


func _mesh_of(name: String) -> Mesh:
	var ps := _scene(name)
	if ps == null:
		return null
	var inst := ps.instantiate()
	var mi := _first_mesh(inst)
	var m: Mesh = mi.mesh if mi else null
	inst.free()
	return m


func _first_mesh(n: Node) -> MeshInstance3D:
	if n is MeshInstance3D:
		return n
	for c in n.get_children():
		var r := _first_mesh(c)
		if r:
			return r
	return null


func _spawn(name: String, pos: Vector3, yaw: float, scale: float = 1.0) -> Node3D:
	var ps := _scene(name)
	if ps == null:
		return null
	var n := ps.instantiate() as Node3D
	n.position = pos
	n.rotation.y = yaw
	n.scale = Vector3.ONE * scale
	add_child(n)
	stats.buildings += 1
	return n


func _static_box(pos: Vector3, yaw: float, size: Vector3, surface: int = Game.Surf.CONCRETE) -> void:
	var b := StaticBody3D.new()
	b.collision_layer = 1
	b.set_meta("surface", surface)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	cs.position = Vector3(0, size.y * 0.5, 0)
	b.add_child(cs)
	b.position = pos
	b.rotation.y = yaw
	add_child(b)


# ------------------------------------------------------------------ vegetation
func _vegetation() -> void:
	var cps := int(round((data.n - 1) * data.cell / CHUNK))
	var count := cps * cps
	var results: Array = []
	results.resize(count)
	var places := data.places
	var task := WorkerThreadPool.add_group_task(func(i: int) -> void:
		results[i] = _chunk_veg(Vector2i(i % cps, i / cps), places)
	, count, -1, true, "vegetation")
	WorkerThreadPool.wait_for_group_task_completion(task)
	for i in count:
		var per: Dictionary = results[i]
		for sp in per:
			var xf: PackedFloat32Array = per[sp]
			if xf.is_empty() or meshes[sp] == null:
				continue
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = meshes[sp]
			mm.instance_count = xf.size() / 12
			mm.buffer = xf
			var mmi := MultiMeshInstance3D.new()
			mmi.multimesh = mm
			var is_tree: bool = (sp as String).begins_with("tree") or sp == "cactus"
			mmi.visibility_range_end = 1500.0 if is_tree else 450.0
			mmi.visibility_range_end_margin = 60.0
			mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if is_tree else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(mmi)
			if is_tree:
				stats.trees += mm.instance_count
			elif (sp as String).begins_with("rock"):
				stats.rocks += mm.instance_count
			else:
				stats.shrubs += mm.instance_count
			# rocks and tree trunks get simple collision near roads? (kept visual: they sit off-road)


static func _push(arr: PackedFloat32Array, b: Basis, o: Vector3) -> void:
	arr.append_array([b.x.x, b.y.x, b.z.x, o.x, b.x.y, b.y.y, b.z.y, o.y, b.x.z, b.y.z, b.z.z, o.z])


func _chunk_veg(c: Vector2i, places: Array) -> Dictionary:
	var out := {}
	for s in SPECIES:
		out[s] = PackedFloat32Array()
	var x0 := data.origin + c.x * CHUNK
	var z0 := data.origin + c.y * CHUNK
	var rng := RandomNumberGenerator.new()
	rng.seed = c.x * 7919 + c.y * 104729 + 17
	var steps := int(CHUNK / STEP)
	for j in steps:
		for i in steps:
			var x := x0 + (i + rng.randf()) * STEP
			var z := z0 + (j + rng.randf()) * STEP
			var h := data.height_at(x, z)
			if h < 1.8:
				continue
			var rd := data.road_distance(x, z)
			if rd < 7.0:
				continue
			var s := data.surface_at(x, z)
			if s == Game.Surf.SNOW:
				continue
			var nrm := data.normal_at(x, z)
			var slope := 1.0 - nrm.y
			var in_place := false
			for p in places:
				var dx: float = x - p.pos[0]
				var dz: float = z - p.pos[1]
				var pr: float = p.r * (0.6 if p.type == "windfarm" else 1.0)
				if dx * dx + dz * dz < pr * pr and p.type != "windfarm":
					in_place = true
					break
			var w := data.region_weights(x, z)
			var f := forest.get_noise_2d(x, z)
			var r := rng.randf()
			var sp := ""
			var sc := rng.randf_range(0.8, 1.25)
			var region := 0
			var best := w.r
			if w.g > best:
				region = 1
				best = w.g
			if w.b > best:
				region = 2
				best = w.b
			if w.a > best:
				region = 3
			match region:
				0:
					if in_place:
						if r < 0.04:
							sp = "tree_broadleaf"
					elif f > 0.18 and slope < 0.5 and rd > 12.0:
						sp = "tree_broadleaf" if r < 0.8 else ("tree_poplar" if r < 0.9 else "shrub")
					elif r < 0.035 and rd > 12.0:
						sp = "tree_broadleaf"
					elif r < 0.07:
						sp = "shrub"
					elif rd < 30.0 and r < 0.12 and data.road_distance(x, z) > 9.0:
						sp = "tree_poplar" if f < -0.3 else ""
				1:
					if h > 330.0:
						if r < 0.08:
							sp = "rock_b" if r < 0.04 else "rock_a"
					elif f > -0.25 and slope < 0.55 and rd > 10.0 and not in_place:
						sp = "tree_pine" if r < 0.85 else "rock_a"
						sc *= 1.15
					elif r < 0.08:
						sp = "tree_pine" if r < 0.05 else "rock_a"
				2:
					if r < 0.025:
						sp = "cactus"
					elif r < 0.08:
						sp = "shrub_dry"
					elif r < 0.105:
						sp = "rock_red"
						sc *= rng.randf_range(1.0, 2.4)
				3:
					if in_place:
						continue
					if f > 0.25 and r < 0.35:
						sp = "tree_umbrella"
					elif r < 0.03:
						sp = "tree_umbrella"
					elif r < 0.09:
						sp = "shrub"
					elif r < 0.11 and slope > 0.3:
						sp = "rock_a"
			if sp == "":
				continue
			if sp.begins_with("tree") and slope > 0.6:
				continue
			var yaw := rng.randf() * TAU
			var b := Basis(Vector3.UP, yaw).scaled(Vector3.ONE * sc)
			if sp.begins_with("rock"):
				b = Basis(nrm.cross(Vector3.FORWARD).normalized() if absf(nrm.dot(Vector3.FORWARD)) < 0.99 else Vector3.RIGHT, rng.randf() * 0.3) * b
			var sink := 0.15 if sp.begins_with("tree") else 0.25
			_push(out[sp], b, Vector3(x, h - sink, z))
	return out


# ------------------------------------------------------------------ settlements
func _road_frame(road: WorldData.Road, i: int) -> Array:
	var t := road.tangent(i)
	return [road.pts[i], t, Vector3(-t.z, 0.0, t.x)]


func _ground_min(p: Vector3, half: float) -> float:
	var m := data.height_at(p.x, p.z)
	for off: Vector2 in [Vector2(half, half), Vector2(-half, half), Vector2(half, -half), Vector2(-half, -half)]:
		m = minf(m, data.height_at(p.x + off.x, p.z + off.y))
	return m


func _places() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 2024
	for p in data.places:
		var pos := Vector3(p.pos[0], 0.0, p.pos[1])
		pos.y = data.height_at(pos.x, pos.z)
		match String(p.type):
			"village":
				_village(p, pos, rng, 18 if p.r > 100.0 else 12)
			"hamlet":
				_village(p, pos, rng, 6)
			"harbour":
				_village(p, pos, rng, 7)
				_harbour(pos, rng)
			"farm":
				_farm(pos, rng)
			"gas":
				_roadside(pos, "gas_station", 14.0)
			"diner":
				_roadside(pos, "diner", 13.0)
			"lighthouse":
				_spawn("lighthouse", Vector3(pos.x, _ground_min(pos, 4.0) - 0.3, pos.z), rng.randf() * TAU)
				_static_box(Vector3(pos.x, pos.y - 1.0, pos.z), 0.0, Vector3(5.0, 22.0, 5.0))
			"castle":
				_spawn("castle_ruin", Vector3(pos.x, _ground_min(pos, 14.0) - 0.5, pos.z), 0.3)
			"windfarm":
				_windfarm(p, pos, rng)
			"viewpoint":
				_viewpoint(pos)
			"festival":
				_festival(p, pos, rng)


func _village(p: Dictionary, center: Vector3, rng: RandomNumberGenerator, count: int) -> void:
	var r: float = p.r
	var placed: Array[Vector3] = []
	var houses := ["house_cottage", "house_townhouse", "house_cottage", "house_farm"]
	# walk the roads that pass through the village and line them with houses
	for road in data.roads:
		if road.cls in ["highway", "sand"]:
			continue
		var i := 0
		while i < road.pts.size() and placed.size() < count:
			var q := road.pts[i]
			if Vector2(q.x - center.x, q.z - center.z).length() < r:
				var fr := _road_frame(road, i)
				for side: float in [-1.0, 1.0]:
					if placed.size() >= count or rng.randf() < 0.25:
						continue
					var off := road.width * 0.5 + road.shoulder + rng.randf_range(9.0, 13.0)
					var hp: Vector3 = fr[0] + fr[2] * side * off
					if data.road_distance(hp.x, hp.z) < 6.0:
						continue
					var ok := true
					for o in placed:
						if o.distance_to(hp) < 14.0:
							ok = false
							break
					if not ok:
						continue
					hp.y = _ground_min(hp, 5.0) - 0.2
					var yaw := atan2(-(fr[2] as Vector3).x * side, -(fr[2] as Vector3).z * side)
					var kind: String = houses[rng.randi() % houses.size()]
					_spawn(kind, hp, yaw)
					_static_box(hp, yaw, Vector3(8.0, 6.0, 8.0))
					placed.append(hp)
					# lamp post on the verge
					if rng.randf() < 0.55:
						var lp: Vector3 = fr[0] + fr[2] * side * (road.width * 0.5 + road.shoulder + 1.2)
						lp.y = data.height_at(lp.x, lp.z)
						_lamp(lp, yaw + PI)
				i += 6
			else:
				i += 3
	# name boards at the edges of the village
	_name_sign(p, center)


func _lamp(pos: Vector3, yaw: float) -> void:
	_spawn("lamp_post", pos, yaw)
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.82, 0.55)
	l.omni_range = 16.0
	l.light_energy = 0.0
	l.shadow_enabled = false
	l.distance_fade_enabled = true
	l.distance_fade_begin = 250.0
	l.distance_fade_length = 60.0
	l.position = pos + Basis(Vector3.UP, yaw) * Vector3(0, 6.1, 1.1)
	add_child(l)
	lamps.append(l)
	stats.lamps += 1


func _name_sign(p: Dictionary, center: Vector3) -> void:
	var nr := data.nearest_road(center, p.r + 80.0)
	if nr.is_empty():
		return
	var road: WorldData.Road = nr.road
	for dir in [-1, 1]:
		var i := clampi(int(nr.seg) + dir * int((float(p.r) + 20.0) / 4.0), 0, road.pts.size() - 1)
		var fr := _road_frame(road, i)
		var pos: Vector3 = fr[0] + fr[2] * (road.width * 0.5 + road.shoulder + 2.5) * float(dir)
		pos.y = data.height_at(pos.x, pos.z)
		var yaw := atan2((fr[1] as Vector3).x * dir, (fr[1] as Vector3).z * dir)
		var s := _spawn("sign_board", pos, yaw)
		if s:
			_label(s, String(p.name), Vector3(0, 2.4, -0.06), 0.012, Color.WHITE)
			_label(s, String(p.name), Vector3(0, 2.4, 0.06), 0.012, Color.WHITE, true)
			stats.signs += 1


func _label(parent: Node3D, text: String, pos: Vector3, px: float, col: Color, flip: bool = false) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.pixel_size = px
	l.font_size = 64
	l.outline_size = 0
	l.modulate = col
	l.position = pos
	l.double_sided = false
	if flip:
		l.rotation.y = PI
	else:
		l.rotation.y = 0.0
	l.visibility_range_end = 220.0
	parent.add_child(l)
	return l


func _harbour(pos: Vector3, rng: RandomNumberGenerator) -> void:
	# pier from the shore into the bay (east), with boats
	var shore := pos
	for k in 60:
		var q := pos + Vector3(k * 4.0, 0, 0)
		if data.height_at(q.x, q.z) < 0.5:
			shore = q
			break
	_spawn("harbour_pier", Vector3(shore.x - 4.0, 0.0, shore.z), -PI * 0.5)
	for k in 3:
		var b := _spawn("boat", Vector3(shore.x + 10.0 + k * 9.0, 0.15, shore.z + rng.randf_range(-12, 12)), rng.randf() * TAU)
		if b:
			boats.append(b)


func _farm(pos: Vector3, rng: RandomNumberGenerator) -> void:
	var yaw := rng.randf() * TAU
	var b := Basis(Vector3.UP, yaw)
	var items := [["house_farm", Vector3(0, 0, 0)], ["barn", Vector3(24, 0, 6)], ["silo", Vector3(38, 0, -6)], ["silo", Vector3(38, 0, 2)]]
	for it: Array in items:
		var p: Vector3 = pos + b * (it[1] as Vector3)
		if data.road_distance(p.x, p.z) < 8.0:
			continue
		p.y = _ground_min(p, 6.0) - 0.2
		_spawn(it[0], p, yaw)
		_static_box(p, yaw, Vector3(10.0, 6.0, 10.0) if it[0] != "silo" else Vector3(4.6, 13.0, 4.6))
	for k in 10:
		var fp: Vector3 = pos + b * Vector3(-18.0 + k * 4.2, 0, 18.0)
		if data.road_distance(fp.x, fp.z) < 5.0:
			continue
		fp.y = data.height_at(fp.x, fp.z)
		_spawn("fence", fp, yaw)


func _roadside(pos: Vector3, prop_name: String, setback: float) -> void:
	var nr := data.nearest_road(pos, 200.0)
	if nr.is_empty():
		return
	var road: WorldData.Road = nr.road
	var fr := _road_frame(road, nr.seg)
	var side := signf((pos - (fr[0] as Vector3)).dot(fr[2] as Vector3))
	if side == 0.0:
		side = 1.0
	var p: Vector3 = fr[0] + fr[2] * side * (road.width * 0.5 + road.shoulder + setback)
	p.y = _ground_min(p, 7.0) - 0.15
	var yaw := atan2((fr[2] as Vector3).x * side, (fr[2] as Vector3).z * side)
	_spawn(prop_name, p, yaw)
	# concrete apron the cars can drive onto
	var apron := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(30.0, 0.4, 26.0)
	apron.mesh = bm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.45, 0.45, 0.46)
	m.roughness = 0.9
	apron.material_override = m
	apron.position = p + Vector3(0, 0.05, 0)
	apron.rotation.y = yaw
	add_child(apron)
	_static_box(p + Vector3(0, -0.15, 0), yaw, Vector3(30.0, 0.4, 26.0))
	_lamp(p + Basis(Vector3.UP, yaw) * Vector3(-12, 0, -8), yaw)


func _windfarm(p: Dictionary, center: Vector3, rng: RandomNumberGenerator) -> void:
	var placed := 0
	var tries := 0
	while placed < 9 and tries < 200:
		tries += 1
		var a := rng.randf() * TAU
		var d := rng.randf_range(30.0, float(p.r))
		var q := center + Vector3(cos(a) * d, 0, sin(a) * d)
		if data.road_distance(q.x, q.z) < 25.0:
			continue
		q.y = data.height_at(q.x, q.z)
		var ok := true
		for c in rotors:
			if Vector2(c.global_position.x - q.x, c.global_position.z - q.z).length() < 120.0:
				ok = false
		if not ok:
			continue
		var yaw := deg_to_rad(200.0)
		_spawn("wind_turbine_tower", q - Vector3(0, 0.5, 0), yaw)
		_static_box(q, 0.0, Vector3(3.0, 60.0, 3.0))
		var hub := Node3D.new()
		hub.position = q + Vector3(0, 61.0, 0) + Basis(Vector3.UP, yaw) * Vector3(0, 0, -3.9)
		hub.rotation.y = yaw
		add_child(hub)
		var rotor := _scene("wind_turbine_rotor").instantiate() as Node3D
		rotor.rotation.x = PI * 0.5
		var spin := Node3D.new()
		hub.add_child(spin)
		spin.add_child(rotor)
		spin.rotation.z = rng.randf() * TAU
		rotors.append(spin)
		placed += 1


func _viewpoint(pos: Vector3) -> void:
	var s := _spawn("sign_board", Vector3(pos.x, data.height_at(pos.x, pos.z), pos.z), 0.0)
	if s:
		_label(s, "Crown Summit  ·  412 m", Vector3(0, 2.4, -0.06), 0.009, Color.WHITE)
	for k in 6:
		var fp := pos + Vector3(-10.0 + k * 4.2, 0, 6.0)
		fp.y = data.height_at(fp.x, fp.z)
		_spawn("fence", fp, 0.0)


func _festival(p: Dictionary, center: Vector3, rng: RandomNumberGenerator) -> void:
	var nr := data.nearest_road(center, 300.0)
	var road: WorldData.Road = nr.road
	var fr := _road_frame(road, nr.seg)
	var side := signf((center - (fr[0] as Vector3)).dot(fr[2] as Vector3))
	if side == 0.0:
		side = 1.0
	var base: Vector3 = fr[0] + fr[2] * side * (road.width * 0.5 + 38.0)
	base.y = _ground_min(base, 10.0) - 0.2
	var yaw := atan2(-(fr[2] as Vector3).x * side, -(fr[2] as Vector3).z * side)
	var b := Basis(Vector3.UP, yaw)
	var stage := _spawn("festival_stage", base + b * Vector3(0, 0, 18.0), yaw + PI)
	_static_box(base + b * Vector3(0, 0, 18.0), yaw, Vector3(18.0, 1.4, 10.0))
	if stage:
		var l := _label(stage, "VELORA  FESTIVAL", Vector3(0, 11.6, -5.6), 0.03, UIStyle.ACCENT)
		l.rotation.y = PI
		l.font_size = 96
	for k in 6:
		var tp: Vector3 = base + b * Vector3(-30.0 + k * 12.0, 0, -6.0 + (k % 2) * 6.0)
		tp.y = data.height_at(tp.x, tp.z) - 0.1
		_spawn("festival_tent", tp, rng.randf() * TAU)
		_static_box(tp, 0.0, Vector3(6.0, 2.4, 6.0))
	# arch spanning the Festival Loop right in front of the site
	var loop := data.road_by_id("festival_loop")
	var li := 0
	var lbest := INF
	for i in loop.pts.size():
		var dd := Vector2(loop.pts[i].x - center.x, loop.pts[i].z - center.z).length_squared()
		if dd < lbest:
			lbest = dd
			li = i
	var lf := _road_frame(loop, li)
	var arch := _spawn("festival_arch", (lf[0] as Vector3) + Vector3.DOWN * 0.1, 0.0)
	if arch:
		var span := (loop.width * 0.5 + loop.shoulder + 2.0) / 8.0
		arch.basis = Basis.looking_at(lf[1], Vector3.UP) * Basis.from_scale(Vector3(span, 1.0, 1.0))
		_label(arch, "VELORA FESTIVAL", Vector3(0, 8.6, -0.86), 0.02, Color.WHITE)
		_label(arch, "VELORA FESTIVAL", Vector3(0, 8.6, 0.86), 0.02, Color.WHITE, true)
		for sx: float in [-1.0, 1.0]:
			_static_box((lf[0] as Vector3) + (lf[2] as Vector3) * sx * 8.0 * span, atan2((lf[1] as Vector3).x, (lf[1] as Vector3).z), Vector3(1.4, 8.0, 1.4))
	road = loop
	nr = {"seg": li}
	for k in 14:
		var fi := clampi(int(nr.seg) - 28 + k * 4, 0, road.pts.size() - 1)
		var ff := _road_frame(road, fi)
		for s2 in [-1.0, 1.0]:
			var fp: Vector3 = ff[0] + ff[2] * s2 * (road.width * 0.5 + road.shoulder + 2.0)
			fp.y = data.height_at(fp.x, fp.z)
			_spawn("festival_flag", fp, rng.randf() * TAU)
	for k in 4:
		_lamp(base + b * Vector3(-20.0 + k * 13.0, 0, 6.0) + Vector3(0, data.height_at(base.x, base.z) - base.y, 0), yaw)


# ------------------------------------------------------------------ road furniture
func _road_signs() -> void:
	for road in data.roads:
		if road.cls in ["dirt", "sand"]:
			continue
		var n := road.pts.size()
		var i := 8
		var last := -100
		while i < n - 8:
			if road.flags[i] != 0 or i - last < 40:
				i += 2
				continue
			var a := road.tangent(i - 6)
			var c := road.tangent(i + 6)
			var turn := Vector2(a.x, a.z).angle_to(Vector2(c.x, c.z))
			if absf(turn) > 0.85:
				# chevrons on the outside of the bend
				var fr := _road_frame(road, i)
				var outside := -signf(turn)
				for k: int in [-3, 0, 3]:
					var fi := i + k
					var ff := _road_frame(road, fi)
					var sp: Vector3 = ff[0] + ff[2] * outside * (road.width * 0.5 + road.shoulder + 1.6)
					sp.y = data.height_at(sp.x, sp.z)
					var yaw := atan2(-(ff[2] as Vector3).x * outside, -(ff[2] as Vector3).z * outside)
					_spawn("sign_chevron", sp, yaw)
					stats.signs += 1
				last = i
			i += 2
	# junction direction boards on the side roads
	for road in data.roads:
		for j in road.junctions:
			var si := int(j.self_i)
			var k := clampi(si + (6 if si == 0 else -6), 0, road.pts.size() - 1)
			var fr := _road_frame(road, k)
			var dir := 1.0 if si == 0 else -1.0
			var sp: Vector3 = fr[0] + fr[2] * dir * (road.width * 0.5 + road.shoulder + 2.2)
			sp.y = data.height_at(sp.x, sp.z)
			var main := data.road_by_id(j.road)
			var yaw := atan2((fr[1] as Vector3).x * -dir, (fr[1] as Vector3).z * -dir)
			var s := _spawn("sign_board", sp, yaw)
			if s and main:
				_label(s, main.name, Vector3(0, 2.4, -0.06), 0.009, Color.WHITE)
				stats.signs += 1


func _lamp_and_window_setup() -> void:
	# the imported window material is shared by every building: light it at night
	var ps := _scene("house_cottage")
	if ps:
		var inst := ps.instantiate()
		var mi := _first_mesh(inst)
		if mi:
			for si in mi.mesh.get_surface_count():
				var m := mi.mesh.surface_get_material(si)
				if m and String(m.resource_name) == "P_Window" and m is StandardMaterial3D:
					window_mat = m
		inst.free()
	if window_mat:
		window_mat.emission_enabled = true
		window_mat.emission = Color(1.0, 0.75, 0.4)
		window_mat.emission_energy_multiplier = 0.0


func _process(delta: float) -> void:
	var _t0 := Time.get_ticks_usec()
	_process_inner(delta)
	Game.prof_add("dressing", Time.get_ticks_usec() - _t0)


func _process_inner(delta: float) -> void:
	var night := Game.time_of_day < 6.9 or Game.time_of_day > 19.3 or Game.weather_name == "storm"
	if night != _lights_on:
		_lights_on = night
		for l in lamps:
			l.light_energy = 2.2 if night else 0.0
		if window_mat:
			window_mat.emission_energy_multiplier = 1.6 if night else 0.0
	var wind: float = 0.4 + Game.world.sky.s_cloud * 0.6 if Game.world and Game.world.sky else 0.5
	for r in rotors:
		r.rotation.z += delta * (0.9 + wind)
	var t := Time.get_ticks_msec() * 0.001
	for i in boats.size():
		var b := boats[i]
		b.position.y = 0.15 + sin(t * 1.3 + i) * 0.12
		b.rotation.z = sin(t * 0.9 + i * 2.0) * 0.04
