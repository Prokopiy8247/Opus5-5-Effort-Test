extends Node3D
## Civilian traffic: lanes come straight from the road splines (one lane per direction, right-hand traffic),
## IDM car following (incl. the player), curve and junction speed control, give-way at junctions,
## overtaking stopped obstacles on long roads, pooled vehicles spawned/despawned out of view,
## simulation LOD (collision + 120 Hz near the player, cheap updates far away), crash reactions, horns.

const POOL: int = 40
const NO_TRAFFIC: PackedStringArray = ["Dune Track", "Windfarm Track"]
const MAX_ACTIVE: int = 34
const SPAWN_MIN: float = 170.0
const SPAWN_MAX: float = 720.0
const DESPAWN: float = 900.0
const NEAR_R: float = 160.0
const KINDS: Array = [["t_small", 0.34], ["t_van", 0.14], ["t_pickup", 0.16], ["t_lorry", 0.12], ["t_bus", 0.07], ["t_tractor", 0.0], ["sedan_p", 0.17]]
const COLORS: Array = [Color(0.85, 0.85, 0.85), Color(0.1, 0.1, 0.12), Color(0.55, 0.06, 0.05), Color(0.12, 0.25, 0.55), Color(0.6, 0.62, 0.64), Color(0.2, 0.4, 0.25), Color(0.85, 0.65, 0.2), Color(0.95, 0.95, 0.92), Color(0.35, 0.18, 0.1)]

var world: WorldData
var pool: Array[TrafficVehicle] = []
var rng := RandomNumberGenerator.new()
var scenes: Dictionary = {}
var _spawn_t: float = 0.0
var stats: Dictionary = {"spawned": 0, "despawned": 0, "wrecks": 0, "yields": 0, "overtakes": 0}
var parked: Array[Node3D] = []
var _occupancy: Dictionary = {}  # node -> vehicle id currently inside


func setup(w: WorldData) -> void:
	world = w
	rng.seed = 777
	for k in KINDS:
		var nm: String = k[0]
		var path: String = "res://assets/imported/traffic/%s.glb" % nm if nm != "sedan_p" else "res://assets/imported/cars/sedan.glb"
		scenes[nm] = load(path)
	for i in POOL:
		var k: String = _pick_kind(false)
		if i < 3:
			k = "t_tractor"
		var tv := TrafficVehicle.new()
		add_child(tv)
		tv.setup(k, scenes[k], COLORS[rng.randi() % COLORS.size()])
		pool.append(tv)
	Game.car_changed.connect(_on_car_changed)
	_on_car_changed(Game.player)
	_place_parked()


func _pick_kind(farm: bool) -> String:
	if farm and rng.randf() < 0.25:
		return "t_tractor"
	var r: float = rng.randf()
	for k in KINDS:
		r -= k[1]
		if r <= 0.0:
			return k[0]
	return "t_small"


func _on_car_changed(c: Node) -> void:
	if c and c is Car and not (c as Car).body_entered.is_connected(_on_player_hit):
		(c as Car).body_entered.connect(_on_player_hit)


func _on_player_hit(body: Node) -> void:
	if body is TrafficVehicle:
		var tv: TrafficVehicle = body
		var car: Car = Game.player as Car
		var tv_vel: Vector3 = -tv.global_transform.basis.z * tv.v
		var rel: Vector3 = car.linear_velocity - tv_vel
		if rel.length() > 7.0 and not tv.wrecked:
			tv.wreck(rel * car.mass * 0.25)
			stats.wrecks += 1
			_horn(tv, 1.0)


func density() -> float:
	var d: float = Game.settings.traffic_density
	if Game.sky:
		var h: float = Game.sky.hour
		if h < 5.5 or h > 22.5:
			d *= 0.35
		elif (h > 7.0 and h < 9.0) or (h > 16.5 and h < 19.0):
			d *= 1.2
	var car: Node3D = Game.player as Node3D
	if car and world:
		var r: int = world.region_at(car.global_position.x, car.global_position.z)
		d *= [1.0, 0.6, 0.75, 1.0][r]
	return d


func active_count() -> int:
	var n: int = 0
	for tv in pool:
		if tv.active:
			n += 1
	return n


func _physics_process(delta: float) -> void:
	var _pf: int = Time.get_ticks_usec()
	_inner_traffic(delta)
	Game.prof_add("traffic", _pf)


func _inner_traffic(delta: float) -> void:
	var car: Car = Game.player as Car
	if world == null or car == null or not is_instance_valid(car) or delta <= 0.00001:
		return
	var ppos: Vector3 = car.global_position
	var cam: Camera3D = get_viewport().get_camera_3d()
	var night: bool = Game.sky != null and Game.sky.is_night()
	# spawn / despawn
	_spawn_t -= delta
	var target: int = int(round(MAX_ACTIVE * density()))
	var act: int = active_count()
	if _spawn_t <= 0.0 and act < target:
		_spawn_t = 0.12
		_try_spawn(ppos, cam)
	# per-lane ordering for leader search
	var lanes: Dictionary = {}
	for tv in pool:
		if tv.active and not tv.wrecked:
			var key: int = tv.road * 2 + (1 if tv.dir > 0 else 0)
			if not lanes.has(key):
				lanes[key] = []
			lanes[key].append(tv)
	# player lane projection
	var pq: Dictionary = world.road_query(ppos.x, ppos.z, 12.0)
	var player_s: float = -1.0
	var player_road: int = -1
	var player_side: float = 0.0
	if pq.ok:
		player_road = pq.road
		player_s = world.roads[pq.road].dist[pq.seg] + pq.t * WorldData.STEP
		player_side = pq.side
	var player_v: float = car.linear_velocity.length()
	_occupancy.clear()
	for tv in pool:
		if tv.active and not tv.wrecked:
			var r: Dictionary = world.roads[tv.road]
			var to_end: float = (r.length - tv.s) if tv.dir > 0 else tv.s
			if to_end < 14.0:
				var node: String = r.to if tv.dir > 0 else r.from
				_occupancy[node] = _occupancy.get(node, 0) + 1
	for tv in pool:
		if not tv.active:
			continue
		var d: float = tv.global_position.distance_to(ppos)
		if tv.wrecked:
			tv.wreck_t += delta
			var vis: bool = cam != null and _in_view(cam, tv.global_position)
			if (tv.wreck_t > 25.0 and not vis) or tv.wreck_t > 40.0 or d > DESPAWN or tv.global_position.y < -50.0:
				tv.deactivate()
				stats.despawned += 1
			continue
		var visible_now: bool = cam != null and _in_view(cam, tv.global_position)
		if d > DESPAWN or (d > SPAWN_MAX + 60.0 and not visible_now):
			tv.deactivate()
			stats.despawned += 1
			continue
		var is_near: bool = d < NEAR_R
		if is_near != tv.near:
			tv.set_near(is_near)
		# far vehicles update at a quarter rate
		tv.lod_tick += 1
		var step: float = delta
		if not is_near:
			if tv.lod_tick % 4 != 0:
				continue
			step = delta * 4.0
		_drive(tv, step, lanes, player_road, player_s, player_side, player_v, night)
		tv.horn_t = maxf(0.0, tv.horn_t - step)


func _drive(tv: TrafficVehicle, dt: float, lanes: Dictionary, p_road: int, p_s: float, p_side: float, p_v: float, night: bool) -> void:
	var r: Dictionary = world.roads[tv.road]
	var v0: float = minf(tv.v_pref, r.speed / 3.6 * (0.8 if tv.kind in ["t_lorry", "t_bus"] else 1.0))
	if tv.kind == "t_tractor":
		v0 = minf(v0, 8.5)
	# curvature ahead
	var curv: PackedFloat32Array = r.curv
	var i0: int = int(tv.s / WorldData.STEP)
	var maxk: float = 0.0
	var look: int = int(clampf(tv.v * 3.0, 20.0, 100.0) / WorldData.STEP)
	for j in range(0, look, 2):
		var ii: int = clampi(i0 + j * tv.dir, 0, curv.size() - 1)
		maxk = maxf(maxk, absf(curv[ii]))
	var grip: float = 0.55 * (Game.sky.grip if Game.sky else 1.0)
	v0 = minf(v0, sqrt(grip * 9.81 / maxf(maxk, 0.0008)))
	# junction ahead: slow down, give way if occupied
	var to_end: float = (r.length - tv.s) if tv.dir > 0 else tv.s
	var end_node: String = r.to if tv.dir > 0 else r.from
	var gap: float = 1000.0
	var lead_v: float = v0
	var n_ends: int = (world.node_roads[end_node] as Array).size()
	if n_ends >= 3 and to_end < 45.0:
		v0 = minf(v0, lerpf(6.0, v0, clampf((to_end - 10.0) / 35.0, 0.0, 1.0)))
		var occ: int = _occupancy.get(end_node, 0)
		var mine: bool = to_end < 14.0
		if occ - (1 if mine else 0) > 0 and to_end > 9.0 and tv.wait_t < 5.0:
			# someone is in the junction: stop at the line
			gap = minf(gap, to_end - 9.0)
			lead_v = 0.0
			tv.wait_t += dt
			if tv.wait_t < dt * 1.5:
				stats.yields += 1
		elif to_end > 14.0:
			tv.wait_t = 0.0
	# leader in the same lane
	var key: int = tv.road * 2 + (1 if tv.dir > 0 else 0)
	for o in lanes.get(key, []):
		if o == tv:
			continue
		var ds: float = (o.s - tv.s) * tv.dir
		if ds > 0.0 and ds < gap + (o.length + tv.length) * 0.5:
			var g: float = ds - (o.length + tv.length) * 0.5
			if g < gap:
				gap = g
				lead_v = o.v
	# wrecks / stopped obstacles in the lane (physical bodies)
	# player as leader if in our lane ahead
	if p_road == tv.road and p_s >= 0.0:
		var ds2: float = (p_s - tv.s) * tv.dir
		var in_lane: bool = signf(p_side) == signf(float(tv.dir)) or absf(p_side) < 1.2
		if ds2 > 0.0 and ds2 < 120.0 and in_lane and tv.overtake < 0.5:
			var g2: float = ds2 - tv.length * 0.5 - 2.5
			if g2 < gap:
				gap = g2
				lead_v = p_v
				if p_v < 1.0 and g2 < 12.0:
					tv.stopped_t += dt
					if tv.stopped_t > 2.5 and tv.horn_t <= 0.0:
						_horn(tv, clampf(1.0 - g2 / 30.0, 0.2, 1.0))
						tv.horn_t = 4.0
						tv.flash()
				else:
					tv.stopped_t = 0.0
	# overtake a stopped obstacle on an open road
	if gap < 25.0 and lead_v < 1.0 and tv.stopped_t > 3.0 and n_ends < 3 and r.cls != "highway":
		if _oncoming_clear(tv, lanes, 90.0):
			tv.overtake = 1.0
			tv.overtake_left = 45.0
			stats.overtakes += 1
	if tv.overtake > 0.0:
		tv.overtake_left -= tv.v * dt
		gap = 1000.0
		lead_v = v0
		if tv.overtake_left <= 0.0:
			tv.overtake = 0.0
			tv.stopped_t = 0.0
	# IDM
	var a_max: float = 1.6 if tv.kind in ["t_lorry", "t_bus", "t_tractor"] else 2.4
	var b: float = 3.5
	var s0: float = 4.0
	var T: float = 1.4
	var dv: float = tv.v - lead_v
	var s_star: float = s0 + maxf(0.0, tv.v * T + tv.v * dv / (2.0 * sqrt(a_max * b)))
	var acc: float = a_max * (1.0 - pow(tv.v / maxf(v0, 0.5), 4.0) - pow(s_star / maxf(gap, 0.5), 2.0))
	acc = clampf(acc, -9.0, a_max)
	tv.v = maxf(0.0, tv.v + acc * dt)
	tv.s += tv.v * dt * tv.dir
	# end of road: continue onto another road at the node
	if (tv.dir > 0 and tv.s >= r.length) or (tv.dir < 0 and tv.s <= 0.0):
		var over: float = (tv.s - r.length) if tv.dir > 0 else -tv.s
		_next_road(tv, end_node, over)
		r = world.roads[tv.road]
	# place on the lane
	var lane: float = r.lane * 0.5
	var off: float = lane * tv.dir * (1.0 - 2.0 * tv.overtake)
	tv.lane_off = lerpf(tv.lane_off, off, clampf(dt * 1.2, 0.0, 1.0))
	var t: Transform3D = world.road_point(tv.road, tv.s, tv.lane_off)
	if tv.dir < 0:
		t.basis = t.basis.rotated(t.basis.y, PI)
	t.basis = tv.yaw_smooth.slerp(t.basis.orthonormalized(), clampf(dt * 8.0, 0.0, 1.0)) if tv.prev_pos != Vector3.INF else t.basis
	tv.yaw_smooth = t.basis
	t.origin.y += 0.02
	tv.global_transform = t
	tv.prev_pos = t.origin
	tv.wheel_spin -= tv.v * dt / maxf(tv.wheel_r, 0.2)
	for w in tv.wheels:
		w.rotation.x = tv.wheel_spin
	tv.set_lights(acc < -1.0 or tv.v < 0.5, night)


func _oncoming_clear(tv: TrafficVehicle, lanes: Dictionary, dist: float) -> bool:
	var key: int = tv.road * 2 + (0 if tv.dir > 0 else 1)
	for o in lanes.get(key, []):
		var ds: float = (o.s - tv.s) * tv.dir
		if ds > -10.0 and ds < dist:
			return false
	return true


func _next_road(tv: TrafficVehicle, node: String, over: float) -> void:
	var options: Array = []
	for e in world.node_roads[node]:
		if e[0] != tv.road:
			options.append(e)
	var pick: Array
	if options.is_empty():
		# dead end: turn around
		pick = [tv.road, tv.dir < 0]
	else:
		# prefer roads of similar class, tractors prefer dirt
		var weights: Array = []
		var total: float = 0.0
		for e in options:
			var rr: Dictionary = world.roads[e[0]]
			var wgt: float = 1.0
			if rr.cls == world.roads[tv.road].cls:
				wgt += 1.0
			if tv.kind == "t_tractor" and rr.surface >= 2:
				wgt += 3.0
			if tv.kind in ["t_bus", "t_lorry"] and rr.surface >= 2:
				wgt *= 0.1
			if rr.to.begins_with("END") or rr.from.begins_with("END"):
				wgt *= 0.3
			if rr.name in NO_TRAFFIC:
				wgt = 0.0001
			weights.append(wgt)
			total += wgt
		var x: float = rng.randf() * total
		pick = options[0]
		for k in options.size():
			x -= weights[k]
			if x <= 0.0:
				pick = options[k]
				break
	tv.road = pick[0]
	var nr: Dictionary = world.roads[tv.road]
	if pick[1]:
		tv.dir = 1
		tv.s = minf(over, nr.length)
	else:
		tv.dir = -1
		tv.s = maxf(nr.length - over, 0.0)
	tv.wait_t = 0.0


func _in_view(cam: Camera3D, p: Vector3) -> bool:
	if cam.is_position_behind(p):
		return false
	var d: float = cam.global_position.distance_to(p)
	if d > 900.0:
		return false
	return cam.is_position_in_frustum(p)


func _try_spawn(ppos: Vector3, cam: Camera3D) -> void:
	var tv: TrafficVehicle = null
	for c in pool:
		if not c.active:
			tv = c
			break
	if tv == null:
		return
	for attempt in 12:
		var ang: float = rng.randf() * TAU
		var dist: float = rng.randf_range(SPAWN_MIN, SPAWN_MAX)
		var p := Vector3(ppos.x + cos(ang) * dist, 0, ppos.z + sin(ang) * dist)
		var q: Dictionary = world.road_query(p.x, p.z, 60.0)
		if not q.ok:
			continue
		var r: Dictionary = world.roads[q.road]
		if r.name in NO_TRAFFIC:
			continue
		var ss: float = r.dist[q.seg] + q.t * WorldData.STEP
		if ss < 20.0 or ss > r.length - 20.0:
			continue
		var d: int = 1 if rng.randf() < 0.5 else -1
		var t: Transform3D = world.road_point(q.road, ss, r.lane * 0.5 * d)
		if t.origin.distance_to(ppos) < SPAWN_MIN:
			continue
		if cam and _in_view(cam, t.origin) and t.origin.distance_to(cam.global_position) < 450.0:
			continue
		var clash: bool = false
		for o in pool:
			if o.active and o.road == q.road and absf(o.s - ss) < 45.0:
				clash = true
				break
		if clash:
			continue
		var farm: bool = world.region_at(t.origin.x, t.origin.z) == WorldData.Region.FARMLAND and r.surface >= 2
		if tv.kind == "t_tractor" and not farm and rng.randf() < 0.8:
			continue
		if r.surface >= 2 and tv.kind in ["t_bus", "t_lorry"]:
			continue
		var pref: float = r.speed / 3.6 * rng.randf_range(0.85, 1.05)
		tv.activate(q.road, d, ss, pref, r.lane * 0.5 * d)
		stats.spawned += 1
		return


func _horn(tv: TrafficVehicle, level: float) -> void:
	var car: Car = Game.player as Car
	if car == null:
		return
	var d: float = tv.global_position.distance_to(car.global_position)
	var a: Node = car.audio
	if a:
		a.ext_horn = maxf(a.ext_horn, level * clampf(1.0 - d / 80.0, 0.0, 1.0))


func _place_parked() -> void:
	var spots: Array = [Vector2(-950, 120), Vector2(-350, 1450), Vector2(200, 160), Vector2(-1650, 200), Vector2(1650, 250), Vector2(1710, 700)]
	for c in spots:
		var count: int = 0
		for ri in world.roads.size():
			var r: Dictionary = world.roads[ri]
			var pts: PackedVector3Array = r.pts
			for i in range(10, pts.size() - 10, 9):
				if count >= 5:
					break
				if Vector2(pts[i].x, pts[i].z).distance_to(c) > 110.0 or r.flags[i] != 0 or rng.randf() < 0.5:
					continue
				var side: float = 1.0 if rng.randf() < 0.5 else -1.0
				var t: Transform3D = world.road_point(ri, r.dist[i], side * (r.hw + 2.4))
				if side < 0.0:
					t.basis = t.basis.rotated(Vector3.UP, PI)
				t.origin.y = world.height(t.origin.x, t.origin.z) + 0.05
				var k: String = ["t_small", "t_van", "t_pickup", "sedan_p"][rng.randi() % 4]
				var n: Node3D = scenes[k].instantiate()
				n.transform = t
				add_child(n)
				var body := StaticBody3D.new()
				body.collision_layer = 1
				var cs := CollisionShape3D.new()
				var bs := BoxShape3D.new()
				bs.size = Vector3(1.8, 1.4, 4.4) if k != "t_van" else Vector3(2.0, 2.2, 5.2)
				cs.shape = bs
				cs.position = Vector3(0, bs.size.y * 0.5 + 0.2, 0)
				body.add_child(cs)
				n.add_child(body)
				for mi in n.find_children("*", "MeshInstance3D", true, false):
					(mi as MeshInstance3D).visibility_range_end = 500.0
				parked.append(n)
				count += 1
