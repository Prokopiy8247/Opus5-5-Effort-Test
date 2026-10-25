extends Node3D
## Civilian traffic on the road graph: pooled vehicles, right-hand lanes, IDM car following
## (the player counts as a leader), curvature speed advice, give-way at junctions, density by
## region/time/console, spawn/despawn outside the camera view and simulation LOD.

const POOL := 36
const BASE_COUNT := 26
const PHYS_IN := 125.0
const PHYS_OUT := 155.0
const DESPAWN := 650.0
const S0 := 7.0
const T_HEADWAY := 1.4
const CLASS_IDX := {"highway": 0, "regional": 1, "mountain": 2, "village": 3, "gravel": 4, "dirt": 5}
const SPEED_LIMIT := {"highway": 30.5, "regional": 22.0, "mountain": 16.5, "village": 13.5, "gravel": 11.0, "dirt": 8.5}
const TYPES_DIR := "res://data/traffic/"

var world: Node
var graph: RoadGraph
var roads: Array
var types: Array[TrafficType] = []
var pool: Array[TrafficCar] = []
var active: Array[TrafficCar] = []
var _right := []           # per road PackedVector3Array (flat right vector of the a->b direction)
var _adv := []             # per road PackedFloat32Array advisory speed (m/s)
var _lanes := {}           # lane key -> Array[TrafficCar] sorted by s
var _rng := RandomNumberGenerator.new()
var _tick := 0.0
var _edge_weights := PackedFloat32Array()
var _edge_total := 0.0
var _node_busy := {}       # node -> time left
var stats := {"spawned": 0, "despawned": 0, "physics": 0, "kinematic": 0, "crashed": 0}


func _ready() -> void:
	_rng.seed = 1337
	world = Game.world
	if world == null or world.get("graph") == null:
		set_process(false)
		set_physics_process(false)
		return
	graph = world.graph
	roads = world.wd.roads
	_load_types()
	_precompute()
	for i in POOL:
		var tt := types[i % types.size()]
		var car := TrafficCar.new()
		car.name = "Traffic%02d" % i
		add_child(car)
		car.setup(tt, tt.model_path, _prefix(tt.model_path))
		pool.append(car)


func _prefix(path: String) -> String:
	return path.get_file().get_basename()


func _load_types() -> void:
	for fname in ResourceLoader.list_directory(TYPES_DIR):
		if fname.ends_with(".tres") or fname.ends_with(".res"):
			var t := load(TYPES_DIR + fname) as TrafficType
			if t != null and ResourceLoader.exists(t.model_path):
				types.append(t)
	if types.is_empty():
		# stand-in until the Blender traffic fleet is exported: reuse the player car models
		for cd in Game.cars:
			var t := TrafficType.new()
			t.id = cd.id
			t.model_path = cd.model_path
			t.mass = cd.mass
			t.colors = [Color(0.8, 0.8, 0.82), Color(0.1, 0.2, 0.5), Color(0.5, 0.05, 0.05), Color(0.15, 0.15, 0.15)]
			types.append(t)


func _precompute() -> void:
	for r: Dictionary in roads:
		var pts: PackedVector3Array = r.pts
		var n := pts.size()
		var right := PackedVector3Array()
		right.resize(n)
		var curv := PackedFloat32Array()
		curv.resize(n)
		for i in n:
			var a := pts[(i - 2 + n) % n] if r.closed else pts[maxi(i - 2, 0)]
			var b := pts[(i + 2) % n] if r.closed else pts[mini(i + 2, n - 1)]
			var t := Vector3(b.x - a.x, 0, b.z - a.z).normalized()
			right[i] = Vector3(-t.z, 0, t.x)
		for i in n:
			var a := pts[(i - 6 + n) % n] if r.closed else pts[maxi(i - 6, 0)]
			var b := pts[i]
			var c := pts[(i + 6) % n] if r.closed else pts[mini(i + 6, n - 1)]
			var t1 := Vector2(b.x - a.x, b.z - a.z).normalized()
			var t2 := Vector2(c.x - b.x, c.z - b.z).normalized()
			var ang := absf(t1.angle_to(t2))
			var radius := 12.0 / maxf(ang, 0.0005)
			curv[i] = sqrt(2.6 * radius)
		var lim: float = SPEED_LIMIT.get(String(r["class"]), 15.0)
		var adv := PackedFloat32Array()
		adv.resize(n)
		for i in n:
			var m := lim
			for k in range(-20, 21, 2):
				var j := (i + k + n) % n if r.closed else clampi(i + k, 0, n - 1)
				m = minf(m, curv[j] + absf(k) * 0.35)
			adv[i] = maxf(m, 5.0)
		_right.append(right)
		_adv.append(adv)
	_edge_weights.resize(graph.edges.size())
	for e in graph.edges:
		var r: Dictionary = roads[e.road]
		var w := e.length * float(r.traffic)
		if r.has("start_on") and not r.has("end_on") and String(r["class"]) in ["village"]:
			w *= 0.5
		_edge_weights[e.id] = w
		_edge_total += w


func lane_offset(r: Dictionary, lane: int) -> float:
	var lw: float = r.lane_w
	if int(r.lanes) >= 2:
		return float(r.median) * 0.5 + lw * (1.5 if lane == 0 else 0.5)
	return lw * 0.5


func positions() -> Array[Vector3]:
	var out: Array[Vector3] = []
	for c in active:
		out.append(c.global_position)
	return out


# ------------------------------------------------------------------ frame
func _physics_process(delta: float) -> void:
	var player := Game.player
	if player == null or not is_instance_valid(player):
		return
	var pp := player.global_position
	for key: int in _node_busy.keys():
		_node_busy[key] = float(_node_busy[key]) - delta
		if float(_node_busy[key]) <= 0.0:
			_node_busy.erase(key)
	for car in active:
		if car.mode == TrafficCar.Mode.CRASHED:
			car.crash_timer += delta
			continue
		var accel: float = car.get_meta("accel", 0.0)
		car.speed = clampf(car.speed + accel * delta, 0.0, 45.0)
		var e := graph.edges[car.edge]
		car.s += car.speed * delta / 2.0
		if car.s >= e.count:
			_advance_edge(car)
		car.blend = car.blend.move_toward(Vector3.ZERO, car.speed * delta / 14.0 * maxf(car.blend.length(), 0.5))
		_update_ghost(car)
		var d := car.global_position.distance_to(pp)
		if car.mode == TrafficCar.Mode.KINEMATIC and d < PHYS_IN:
			car.set_mode(TrafficCar.Mode.PHYSICS)
		elif car.mode == TrafficCar.Mode.PHYSICS and d > PHYS_OUT:
			car.set_mode(TrafficCar.Mode.KINEMATIC)
			car.place_at_ghost()


func _process(delta: float) -> void:
	_tick -= delta
	if _tick > 0.0:
		return
	_tick = 0.1
	var player := Game.player
	if player == null or not is_instance_valid(player):
		return
	_rebuild_lanes()
	var cam := get_viewport().get_camera_3d()
	var pp := player.global_position
	stats.physics = 0
	stats.kinematic = 0
	stats.crashed = 0
	for car: TrafficCar in active.duplicate():
		var d := car.global_position.distance_to(pp)
		var visible_now := cam != null and cam.is_position_in_frustum(car.global_position) and d < 900.0
		match car.mode:
			TrafficCar.Mode.PHYSICS:
				stats.physics += 1
			TrafficCar.Mode.KINEMATIC:
				stats.kinematic += 1
			TrafficCar.Mode.CRASHED:
				stats.crashed += 1
		if d > DESPAWN or (d > 300.0 and not visible_now and (car.mode == TrafficCar.Mode.CRASHED or car.idle_timer > 20.0)):
			_despawn(car)
			continue
		if car.mode == TrafficCar.Mode.CRASHED:
			_try_recover(car)
			continue
		_decide(car, player)
		car.idle_timer = car.idle_timer + 0.1 if car.speed < 0.5 else 0.0
	_spawn_some(pp, cam)


func _target_count(pp: Vector3) -> int:
	var dens := float(Game.settings.traffic_density)
	if dens <= 0.0:
		return 0
	var f := 1.0
	if Game.sky != null:
		var h := float(Game.sky.time_of_day)
		if h < 5.5 or h > 22.5:
			f *= 0.35
		elif (h > 7.0 and h < 9.0) or (h > 16.5 and h < 19.0):
			f *= 1.2
	var region: int = world.region_at(pp)
	f *= [1.0, 0.65, 0.7, 0.9][clampi(region, 0, 3)]
	return clampi(int(BASE_COUNT * dens * f), 0, POOL)


# ------------------------------------------------------------------ spawning
func _spawn_some(pp: Vector3, cam: Camera3D) -> void:
	var want := _target_count(pp)
	while active.size() > want + 3:
		_despawn(_farthest(pp))
	var attempts := 6
	while active.size() < want and attempts > 0:
		attempts -= 1
		var car := _free_car()
		if car == null:
			return
		var eid := _pick_edge()
		var e := graph.edges[eid]
		if e.count < 12:
			continue
		var r: Dictionary = roads[e.road]
		if (r.kind as PackedByteArray)[e.i0 + mini(e.count / 2, e.count)] == 2 and _rng.randf() < 0.5:
			continue
		car.edge = eid
		car.dir = 1 if _rng.randf() < 0.5 else -1
		car.lane = _rng.randi() % 2 if int(r.lanes) >= 2 else 0
		car.s = _rng.randf_range(4.0, e.count - 4.0)
		_update_ghost(car)
		var pos := car.ghost.origin
		var d := pos.distance_to(pp)
		if d < 140.0 or d > 560.0:
			continue
		if d < 380.0 and cam != null and cam.is_position_in_frustum(pos):
			continue
		var too_close := false
		for o in active:
			if o.global_position.distance_to(pos) < 35.0:
				too_close = true
				break
		if too_close:
			continue
		var tt := _pick_type(r)
		if tt != car.ttype:
			# pooled body has another model: swap to a free car of the wanted type when possible
			var alt := _free_car(tt)
			if alt != null:
				alt.edge = car.edge
				alt.dir = car.dir
				alt.lane = car.lane
				alt.s = car.s
				car = alt
		car.desire = _rng.randf_range(0.85, 1.08) * car.ttype.speed_factor
		car.speed = minf(float(_adv[e.road][e.i0]) * car.desire, float(SPEED_LIMIT[String(r["class"])]) * car.desire) * 0.8
		car.next_edge = -1
		car.blend = Vector3.ZERO
		car.crash_timer = 0.0
		car.idle_timer = 0.0
		car.set_meta("accel", 0.0)
		_update_ghost(car)
		car.ghost_vel = -car.ghost.basis.z * car.speed
		car.set_mode(TrafficCar.Mode.KINEMATIC)
		car.place_at_ghost()
		if not car.ttype.colors.is_empty():
			car.visual.set_paint(car.ttype.colors[_rng.randi() % car.ttype.colors.size()], 0 if _rng.randf() < 0.6 else 1)
		car.visual.set_headlights(Game.sky != null and bool(Game.sky.is_night))
		active.append(car)
		stats.spawned += 1


func _free_car(tt: TrafficType = null) -> TrafficCar:
	for c in pool:
		if c.mode == TrafficCar.Mode.IDLE and (tt == null or c.ttype == tt):
			return c
	return null


func _farthest(pp: Vector3) -> TrafficCar:
	var best: TrafficCar = active[0]
	var bd := -1.0
	for c in active:
		var d := c.global_position.distance_to(pp)
		if d > bd:
			bd = d
			best = c
	return best


func _despawn(car: TrafficCar) -> void:
	active.erase(car)
	car.set_mode(TrafficCar.Mode.IDLE)
	car.global_position = Vector3(0, -500, 0)
	stats.despawned += 1


func _pick_edge() -> int:
	var r := _rng.randf() * _edge_total
	for i in _edge_weights.size():
		r -= _edge_weights[i]
		if r <= 0.0:
			return i
	return _edge_weights.size() - 1


func _pick_type(r: Dictionary) -> TrafficType:
	var ci: int = CLASS_IDX.get(String(r["class"]), 1)
	var total := 0.0
	var farm: bool = int(world.region_at((r.pts as PackedVector3Array)[0])) == 0
	for t in types:
		if t.farm_only and not farm:
			continue
		total += t.class_weights[ci] if ci < t.class_weights.size() else 0.0
	var x := _rng.randf() * total
	for t in types:
		if t.farm_only and not farm:
			continue
		x -= t.class_weights[ci] if ci < t.class_weights.size() else 0.0
		if x <= 0.0:
			return t
	return types[0]


# ------------------------------------------------------------------ motion
func _update_ghost(car: TrafficCar) -> void:
	var e := graph.edges[car.edge]
	var r: Dictionary = roads[e.road]
	var pts: PackedVector3Array = r.pts
	var n := pts.size()
	var sf := clampf(car.s, 0.0, float(e.count))
	if car.dir < 0:
		sf = e.count - sf
	var k0 := mini(int(floor(sf)), e.count - 1)
	var f := sf - k0
	var i0 := (e.i0 + k0) % n
	var i1 := (e.i0 + k0 + 1) % n
	var c := pts[i0].lerp(pts[i1], f)
	var rr: Vector3 = (_right[e.road] as PackedVector3Array)[i0]
	var fwd := (pts[i1] - pts[i0]).normalized() * float(car.dir)
	var off := lane_offset(r, car.lane)
	var bank := (r.bank as PackedFloat32Array)[i0]
	var pos := c + rr * float(car.dir) * off
	pos.y = c.y - off * float(car.dir) * tan(bank) + 0.02
	pos += car.blend
	var up := Vector3.UP.rotated(Vector3(fwd.x, 0, fwd.z).normalized(), bank * float(car.dir)) if absf(bank) > 0.001 else Vector3.UP
	car.ghost = Transform3D(Basis.looking_at(fwd, up), pos)
	car.ghost_vel = fwd * car.speed


func _advance_edge(car: TrafficCar) -> void:
	var e := graph.edges[car.edge]
	var old_xf := car.ghost
	var rem := car.s - e.count
	var node := e.b if car.dir > 0 else e.a
	if car.next_edge < 0:
		_choose_next(car)
	if car.next_edge < 0:
		# dead end: turn around
		car.dir = -car.dir
		car.s = 0.0
		car.next_edge = -1
		return
	_node_busy[node] = 2.0
	car.edge = car.next_edge
	car.dir = car.next_dir
	car.s = rem
	car.next_edge = -1
	var ne := graph.edges[car.edge]
	var r: Dictionary = roads[ne.road]
	if car.lane >= int(r.lanes) * 1:
		car.lane = 0
	if int(r.lanes) >= 2 and car.lane > 1:
		car.lane = 0
	_update_ghost(car)
	car.blend = (old_xf.origin - (car.ghost.origin - car.blend)).limit_length(8.0)
	car.blend.y = 0.0


func _choose_next(car: TrafficCar) -> void:
	var e := graph.edges[car.edge]
	var node := e.b if car.dir > 0 else e.a
	var options: Array = []
	var weights: Array = []
	for eid: int in graph.node_edges[node]:
		if eid == car.edge and graph.edges[eid].a != graph.edges[eid].b:
			continue
		var ne := graph.edges[eid]
		var r: Dictionary = roads[ne.road]
		var w := float(r.traffic) + 0.05
		if ne.road == e.road:
			w += 2.5
		if ne.count < 6:
			w *= 0.2
		options.append(eid)
		weights.append(w)
	if options.is_empty():
		car.next_edge = -1
		return
	var total := 0.0
	for w: float in weights:
		total += w
	var x := _rng.randf() * total
	var pick: int = options[0]
	for i in options.size():
		x -= float(weights[i])
		if x <= 0.0:
			pick = options[i]
			break
	car.next_edge = pick
	var pe := graph.edges[pick]
	car.next_dir = 1 if pe.a == node else -1


# ------------------------------------------------------------------ decisions
func _lane_key(edge: int, dir: int, lane: int) -> int:
	return edge * 8 + (0 if dir > 0 else 4) + lane


func _rebuild_lanes() -> void:
	_lanes.clear()
	for c in active:
		if c.mode == TrafficCar.Mode.CRASHED:
			continue
		var k := _lane_key(c.edge, c.dir, c.lane)
		if not _lanes.has(k):
			_lanes[k] = []
		(_lanes[k] as Array).append(c)
	for k: int in _lanes:
		(_lanes[k] as Array).sort_custom(func(a: TrafficCar, b: TrafficCar) -> bool: return a.s < b.s)


func _decide(car: TrafficCar, player: CarController) -> void:
	var e := graph.edges[car.edge]
	var r: Dictionary = roads[e.road]
	var remaining := (e.count - car.s) * 2.0
	if remaining < 70.0 and car.next_edge < 0:
		_choose_next(car)
	# desired speed: limit x personality, curvature advice ahead
	var n := (r.pts as PackedVector3Array).size()
	var look := car.s + minf(car.speed * 1.6, 30.0) / 2.0
	var sf := minf(look, float(e.count))
	if car.dir < 0:
		sf = e.count - sf
	var idx := (e.i0 + int(sf)) % n
	var v0 := minf(float(SPEED_LIMIT[String(r["class"])]), float((_adv[e.road] as PackedFloat32Array)[idx])) * car.desire
	if (r.kind as PackedByteArray)[idx] == 2:
		v0 = minf(v0, 20.0)
	if Game.sky != null and float(Game.sky.wetness) > 0.4:
		v0 *= 0.88
	car.target_speed = v0
	# leader search: same lane, then the next edge, then the player and junction stop lines
	var gap := 1e9
	var vlead := v0
	var lst: Array = _lanes.get(_lane_key(car.edge, car.dir, car.lane), [])
	var me := lst.find(car)
	if me >= 0 and me + 1 < lst.size():
		var ld: TrafficCar = lst[me + 1]
		gap = (ld.s - car.s) * 2.0 - car.ttype.length
		vlead = ld.speed if ld.mode != TrafficCar.Mode.CRASHED else 0.0
	elif car.next_edge >= 0 and remaining < 120.0:
		var nl: Array = _lanes.get(_lane_key(car.next_edge, car.next_dir, 0), [])
		if not nl.is_empty():
			var ld: TrafficCar = nl[0]
			gap = remaining + ld.s * 2.0 - car.ttype.length
			vlead = ld.speed
	# crashed cars and the player ahead in our path
	var fwd := -car.ghost.basis.z
	var pp := player.global_position
	var rel := pp - car.ghost.origin
	var along := rel.dot(fwd)
	var lateral := (rel - fwd * along).length()
	if along > 0.0 and along < 80.0 and lateral < 2.8:
		var pg := along - car.ttype.length * 0.5 - 2.5
		if pg < gap:
			gap = pg
			vlead = maxf(player.linear_velocity.dot(fwd), 0.0)
			if player.speed_abs < 2.0 and along < 25.0:
				car.blocked_by_player += 0.1
	else:
		car.blocked_by_player = 0.0
	for o in active:
		if o == car or o.mode != TrafficCar.Mode.CRASHED:
			continue
		var orel := o.global_position - car.ghost.origin
		var oal := orel.dot(fwd)
		if oal > 0.0 and oal < 60.0 and (orel - fwd * oal).length() < 2.8:
			gap = minf(gap, oal - car.ttype.length)
			vlead = 0.0
	# give way at junctions where we are on the minor road
	car.yielding = false
	if car.next_edge >= 0 and remaining < 45.0:
		var node := e.b if car.dir > 0 else e.a
		var pr: Dictionary = graph.node_priority.get(node, {})
		var mine: int = pr.get(e.road, 0)
		var top := mine
		for k: int in pr:
			top = maxi(top, int(pr[k]))
		if mine < top or graph.edges[car.next_edge].road != e.road:
			var np: Vector3 = graph.node_pos[node]
			var conflict := _node_busy.has(node)
			for o in active:
				if o == car or conflict:
					continue
				var od := o.global_position.distance_to(np)
				if od < 38.0 and graph.edges[o.edge].road != e.road and o.speed > 1.0:
					var to_node := (np - o.global_position).normalized()
					if (-o.ghost.basis.z).dot(to_node) > 0.3:
						conflict = true
			if pp.distance_to(np) < 35.0 and player.speed_abs > 2.0 and (-player.global_transform.basis.z).dot((np - pp).normalized()) > 0.3:
				conflict = true
			if conflict and mine < top:
				car.yielding = true
				gap = minf(gap, remaining - 8.0)
				vlead = 0.0
	# IDM
	var v := car.speed
	var a_max := car.ttype.accel
	var b := car.ttype.decel
	var s_star := S0 + v * T_HEADWAY + v * (v - vlead) / (2.0 * sqrt(a_max * b))
	var free_term := 1.0 - pow(v / maxf(v0, 0.5), 4.0)
	var inter := (s_star / maxf(gap, 0.5)) ** 2 if gap < 1e8 else 0.0
	var acc := clampf(a_max * (free_term - inter), -9.0, a_max)
	car.set_meta("accel", acc)
	car.visual.set_brake(acc < -1.0 or (car.yielding and v < 1.0))
	# horn when the player blocks the lane
	if car.blocked_by_player > 2.5 and car.horn_cooldown <= 0.0:
		car.horn_cooldown = 6.0
		car.visual.flash_headlights()
		if Game.audio != null and Game.audio.has_method("horn"):
			Game.audio.horn(car.global_position)


func _try_recover(car: TrafficCar) -> void:
	if car.crash_timer < 5.0:
		return
	var up := car.global_transform.basis.y.dot(Vector3.UP)
	if car.linear_velocity.length() > 1.5 or up < 0.8:
		if up < 0.3 and car.crash_timer > 12.0:
			var p := car.global_position
			car.global_transform = Transform3D(Basis.looking_at(Vector3(-car.global_transform.basis.z.x, 0, -car.global_transform.basis.z.z).normalized(), Vector3.UP), p + Vector3.UP)
		return
	var e := graph.edges[car.edge]
	var r: Dictionary = roads[e.road]
	var pts: PackedVector3Array = r.pts
	var n := pts.size()
	var best := car.s
	var bd := 1e9
	for k in range(maxi(0, int(car.s) - 20), mini(e.count, int(car.s) + 20)):
		var sf := float(k) if car.dir > 0 else float(e.count - k)
		var p := pts[(e.i0 + int(sf)) % n]
		var d := p.distance_to(car.global_position)
		if d < bd:
			bd = d
			best = k
	if bd > 7.0:
		return
	car.s = best
	car.speed = 0.0
	car.set_meta("accel", 0.0)
	_update_ghost(car)
	car.blend = car.global_position - car.ghost.origin
	car.blend.y = 0.0
	car.mode = TrafficCar.Mode.PHYSICS
	car.crash_timer = 0.0
