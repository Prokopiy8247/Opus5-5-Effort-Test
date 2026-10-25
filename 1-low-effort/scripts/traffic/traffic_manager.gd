class_name TrafficManager
extends Node3D
## Lane-following civilian traffic with pooling. Vehicles are frozen (kinematic)
## RigidBody3Ds driven along lanes derived from the road splines; a collision with the
## player unfreezes them into dynamic wrecks that despawn later.

const TYPES := ["tr01_compact", "tr02_van", "tr03_lorry", "tr04_bus", "tr05_tractor", "tr06_pickup"]
const PER_TYPE := 9
const MAX_ACTIVE := 40
const SPAWN_MIN := 220.0
const SPAWN_MAX := 750.0
const DESPAWN := 950.0
const A_LAT := 3.2

var world: WorldGen
var player: Car
var camera: Camera3D
var density := 0.6
var pool: Dictionary = {}       # type -> Array[RigidBody3D]
var active: Array[Dictionary] = []
var end_links: Dictionary = {}  # Vector2i(road, end_idx) -> Array[Vector2i(target_road, target_idx)]
var branch_at: Dictionary = {}  # Vector2i(road, idx) -> Array[Vector2i(branch_road, end_idx)]
var rng := RandomNumberGenerator.new()
var paints := [Color(0.85, 0.85, 0.85), Color(0.1, 0.1, 0.12), Color(0.6, 0.1, 0.1), Color(0.15, 0.3, 0.6), Color(0.75, 0.7, 0.55), Color(0.25, 0.45, 0.3), Color(0.9, 0.75, 0.2)]
var _frame := 0

func setup(w: WorldGen, p: Car, cam: Camera3D) -> void:
	world = w; player = p; camera = cam
	rng.seed = 99
	for j in world.junctions:
		var e := Vector2i(j.road, j.idx)
		if not end_links.has(e): end_links[e] = []
		end_links[e].append(Vector2i(j.target_road, j.target_idx))
		var b := Vector2i(j.target_road, j.target_idx)
		if not branch_at.has(b): branch_at[b] = []
		branch_at[b].append(Vector2i(j.road, j.idx))
	for t in TYPES:
		pool[t] = []
		var ps := load("res://assets/imported/vehicles/%s.glb" % t) as PackedScene
		for i in PER_TYPE:
			pool[t].append(_make_vehicle(ps, t))

func _make_vehicle(ps: PackedScene, t: String) -> RigidBody3D:
	var b := RigidBody3D.new()
	b.name = "Traffic_" + t
	b.freeze = true
	b.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	b.collision_layer = 2
	b.collision_mask = 1 | 2 | 4
	var m := ps.instantiate() as Node3D
	b.add_child(m)
	var wheels: Array[Node3D] = []
	var paint := StandardMaterial3D.new()
	var brake := StandardMaterial3D.new(); brake.emission_enabled = true; brake.albedo_color = Color(0.5, 0, 0); brake.emission = Color(1, 0.05, 0.02)
	var head := StandardMaterial3D.new(); head.emission_enabled = true; head.albedo_color = Color(1, 1, 0.9); head.emission = Color(1, 0.95, 0.8)
	var aabb := AABB()
	for c in m.find_children("*", "", true, false):
		if c is StaticBody3D:
			c.get_parent().remove_child(c); c.queue_free(); continue
		if c is MeshInstance3D:
			var mi := c as MeshInstance3D
			if String(mi.name).contains("_Wheel_"): wheels.append(mi)
			if String(mi.name).ends_with("_Body"): aabb = mi.mesh.get_aabb()
			mi.visibility_range_end = 650.0
			for si in mi.mesh.get_surface_count():
				var sm := mi.mesh.surface_get_material(si)
				if sm == null: continue
				if sm.resource_name == "Paint": mi.set_surface_override_material(si, paint)
				elif sm.resource_name == "LightR": mi.set_surface_override_material(si, brake)
				elif sm.resource_name == "LightF": mi.set_surface_override_material(si, head)
	var cs := CollisionShape3D.new()
	var bx := BoxShape3D.new(); bx.size = aabb.size * Vector3(0.95, 0.85, 0.97)
	cs.shape = bx; cs.position = aabb.get_center() + Vector3(0, aabb.size.y * 0.05, 0)
	b.add_child(cs)
	var sizes := {"tr01_compact": 1100.0, "tr02_van": 2200.0, "tr03_lorry": 9000.0, "tr04_bus": 11000.0, "tr05_tractor": 3500.0, "tr06_pickup": 2100.0}
	b.mass = sizes[t]
	b.set_meta("traffic", true)
	b.set_meta("wheels", wheels)
	b.set_meta("paint", paint)
	b.set_meta("brake", brake)
	b.set_meta("head", head)
	b.set_meta("length", aabb.size.z)
	b.visible = false
	b.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(b)
	return b

func _lane_offset(road: Dictionary) -> float:
	return road.width * (0.3 if road.cls == "highway" else 0.25)

func _pick_type(road: Dictionary, x: float, z: float) -> String:
	var reg := world.region_at(x, z)
	var r := rng.randf()
	if road.cls in ["lane", "gravel"] and reg == 0 and r < 0.35: return "tr05_tractor"
	if road.cls == "highway" and r < 0.25: return "tr03_lorry"
	if road.cls in ["highway", "regional"] and r < 0.33: return "tr04_bus" if r < 0.1 else "tr03_lorry"
	if road.cls == "dirt" or road.cls == "gravel": return "tr06_pickup" if r < 0.7 else "tr02_van"
	return ["tr01_compact", "tr01_compact", "tr02_van", "tr06_pickup"][rng.randi() % 4]

func _take(t: String) -> RigidBody3D:
	for b: RigidBody3D in pool[t]:
		if not b.visible: return b
	return null

func _process(dt: float) -> void:
	if player == null: return
	_frame += 1
	var target := int(MAX_ACTIVE * density)
	if active.size() < target and _frame % 3 == 0:
		_try_spawn()
	_simulate(dt)

func _try_spawn() -> void:
	var pp := player.global_position
	for attempt in 6:
		var ri := rng.randi() % world.roads.size()
		var road: Dictionary = world.roads[ri]
		var n: int = road.pts.size()
		var i := rng.randi() % n
		var p: Vector3 = road.pts[i]
		var d := p.distance_to(pp)
		if d < SPAWN_MIN or d > SPAWN_MAX: continue
		if road.tunnel[i] == 1: continue
		# out of view or far
		if camera and d < 450.0:
			var to := (p - camera.global_position).normalized()
			if to.dot(-camera.global_basis.z) > 0.2: continue
		var dir := 1 if rng.randf() < 0.5 else -1
		# keep clear of other vehicles on that lane
		var clear := true
		for v in active:
			if v.road == ri and v.dir == dir and absf(v.s - i) < 18.0: clear = false; break
		if not clear: continue
		var t := _pick_type(road, p.x, p.z)
		var b := _take(t)
		if b == null: continue
		var limit: float = road.limit / 3.6
		if t in ["tr03_lorry", "tr04_bus"]: limit = minf(limit, 85.0 / 3.6)
		if t == "tr05_tractor": limit = 32.0 / 3.6
		var v := {"body": b, "type": t, "road": ri, "dir": dir, "s": float(i), "v": limit * 0.8, "limit": limit * rng.randf_range(0.85, 1.05),
			"state": "drive", "timer": 0.0, "wait": 0.0, "len": b.get_meta("length")}
		(b.get_meta("paint") as StandardMaterial3D).albedo_color = paints[rng.randi() % paints.size()]
		b.freeze = true
		b.visible = true
		b.process_mode = Node.PROCESS_MODE_INHERIT
		active.append(v)
		_place(v)
		return

func _release(v: Dictionary) -> void:
	var b: RigidBody3D = v.body
	b.visible = false
	b.freeze = true
	b.linear_velocity = Vector3.ZERO; b.angular_velocity = Vector3.ZERO
	b.process_mode = Node.PROCESS_MODE_DISABLED
	b.global_position = Vector3(0, -500, 0)

func _road_pos(ri: int, s: float, dir: int) -> Transform3D:
	var road: Dictionary = world.roads[ri]
	var n: int = road.pts.size()
	var i0 := int(floor(s)); var t := s - i0
	var a := world.road_point(ri, i0); var b := world.road_point(ri, i0 + 1)
	var p := a.lerp(b, t)
	var f := (b - a).normalized() if a.distance_to(b) > 0.01 else world.road_dir(ri, i0)
	if dir < 0: f = -f
	var flat := Vector3(f.x, 0, f.z).normalized()
	var right := flat.cross(Vector3.UP).normalized()
	p += right * _lane_offset(road)
	var up := Vector3.UP
	var z := -f
	var x := up.cross(z).normalized()
	return Transform3D(Basis(x, z.cross(x), z), p + Vector3.UP * 0.02)

func _place(v: Dictionary) -> void:
	var b: RigidBody3D = v.body
	b.global_transform = _road_pos(v.road, v.s, v.dir)

func on_player_hit(b: Node, player_vel: Vector3) -> void:
	for v in active:
		if v.body == b and v.state == "drive":
			v.state = "wreck"; v.timer = 10.0
			var rb: RigidBody3D = b
			var fwd := -rb.global_basis.z
			rb.freeze = false
			rb.linear_velocity = fwd * v.v * float(v.dir) * 0.0 + fwd * v.v + player_vel * clampf(player.mass / rb.mass, 0.05, 1.0) * 0.5
			Game.toast("Traffic collision!", "warn")
			return

func _simulate(dt: float) -> void:
	var pp := player.global_position
	var pv := player.linear_velocity
	# lane ordering: leader lookup
	var lanes: Dictionary = {}
	for v in active:
		if v.state != "drive": continue
		var key := Vector2i(v.road, v.dir)
		if not lanes.has(key): lanes[key] = []
		lanes[key].append(v)
	var remove: Array = []
	for v in active:
		var b: RigidBody3D = v.body
		if v.state == "wreck":
			v.timer -= dt
			if v.timer <= 0.0 or b.global_position.distance_to(pp) > DESPAWN: remove.append(v)
			continue
		if b.global_position.distance_to(pp) > DESPAWN: remove.append(v); continue
		var road: Dictionary = world.roads[v.road]
		var n: int = road.pts.size()
		var closed: bool = road.closed
		# desired speed: limit, curvature ahead
		var want: float = v.limit
		for k in [4, 10, 18]:
			var si: int = int(v.s) + k * v.dir
			if not closed and (si < 0 or si >= n): continue
			var c := absf(road.curv[posmod(si, n)])
			if c > 0.0005: want = minf(want, sqrt(A_LAT / c))
		# leader on the same lane
		var gap := 1e9
		var lead_v := 0.0
		for o in lanes.get(Vector2i(v.road, v.dir), []):
			if o == v: continue
			var ds: float = (o.s - v.s) * v.dir
			if closed:
				ds = fposmod(ds, float(n))
			if ds > 0.0 and ds * WorldGen.SAMPLE_STEP < gap:
				gap = ds * WorldGen.SAMPLE_STEP - (o.len + v.len) * 0.5; lead_v = o.v
		# player as obstacle
		var to_p := pp - b.global_position
		var fwd := -b.global_basis.z
		var ahead := to_p.dot(fwd)
		var lateral := absf(to_p.dot(b.global_basis.x))
		if ahead > 0.0 and ahead < 60.0 and lateral < 2.6:
			var pspeed := pv.dot(fwd)
			if ahead - v.len * 0.5 - 2.5 < gap: gap = ahead - v.len * 0.5 - 2.5; lead_v = maxf(pspeed, 0.0)
		var safe: float = 6.0 + v.v * 1.6
		if gap < safe:
			want = minf(want, lead_v * clampf(gap / safe, 0.0, 1.0))
			if gap < 4.0: want = 0.0
		# give way at a branch end before merging
		var end_idx := n - 1 if v.dir > 0 else 0
		if not closed:
			var to_end: float = (end_idx - v.s) * v.dir
			if to_end < 8.0 and v.wait < 4.0:
				var busy := false
				for link: Vector2i in end_links.get(Vector2i(v.road, end_idx), []):
					for o in active:
						if o != v and o.road == link.x and absf(o.s - link.y) < 10.0 and o.state == "drive": busy = true
				if busy: want = 0.0; v.wait += dt
		var acc := 2.2 if v.type not in ["tr03_lorry", "tr04_bus", "tr05_tractor"] else 1.0
		var braking: bool = want < v.v - 0.5
		v.v = move_toward(v.v, want, (7.0 if braking else acc) * dt)
		v.s += v.v * dt / WorldGen.SAMPLE_STEP * v.dir
		(b.get_meta("brake") as StandardMaterial3D).emission_energy_multiplier = 4.0 if braking or v.v < 0.5 else 0.6
		# transfers at junctions
		if closed:
			v.s = fposmod(v.s, float(n))
			var key := Vector2i(v.road, int(v.s))
			if branch_at.has(key) and rng.randf() < 0.02 and v.get("last_branch", -1) != int(v.s):
				var br: Vector2i = branch_at[key][0]
				v.last_branch = int(v.s)
				_transfer(v, br.x, br.y)
		elif v.s <= 0.0 or v.s >= n - 1:
			var links: Array = end_links.get(Vector2i(v.road, 0 if v.s <= 0.0 else n - 1), [])
			if links.is_empty():
				v.dir = -v.dir; v.s = clampf(v.s, 0.0, n - 1.0)
			else:
				var l: Vector2i = links[rng.randi() % links.size()]
				_transfer_into(v, l.x, l.y)
		if v.state == "drive":
			_place(v)
			for wn: Node3D in b.get_meta("wheels"):
				wn.rotate_object_local(Vector3.RIGHT, -v.v * dt / 0.35)
	for v in remove:
		_release(v)
		active.erase(v)

func _transfer(v: Dictionary, road_i: int, end_idx: int) -> void:
	# from a through road into a branch starting at its end
	var n: int = world.roads[road_i].pts.size()
	v.road = road_i
	v.s = float(end_idx)
	v.dir = 1 if end_idx == 0 else -1
	v.wait = 0.0
	if not world.roads[road_i].closed: v.s = clampf(v.s, 0.0, n - 1.0)

func _transfer_into(v: Dictionary, road_i: int, idx: int) -> void:
	v.road = road_i
	v.s = float(idx)
	v.dir = 1 if rng.randf() < 0.5 else -1
	v.wait = 0.0
	v.last_branch = idx

func clear_all() -> void:
	for v in active: _release(v)
	active.clear()
