extends Node3D
## Pedestrians. Pooled, spawned around the player out of view. NO physics bodies or areas: people never take part
## in car collisions. Danger is computed per frame from the cars' position / velocity (time to reach the person
## and lateral distance to the car's path); a person runs sideways out of the way well before the car arrives,
## and if a car is already on top of someone (teleport, spawn) they are moved to a safe spot instantly.
## Everything is drawn with one MultiMesh per look; limbs are animated in the vertex shader.

const Meshes := preload("res://scripts/pedestrians/pedestrian_meshes.gd")
const Paths := preload("res://scripts/pedestrians/pedestrian_paths.gd")
const PropLibrary := preload("res://scripts/world/prop_library.gd")

enum Kind { WALK, JOG, SIT, STAND, PHONE, TALK, BIKE }
enum State { LIVE, FLEE, CALM, RETURN }

const MAX_PEDS := 110
const CAP_PER_LOOK := 24
const SPAWN_MIN := 100.0
const SPAWN_MAX := 230.0
const DESPAWN := 290.0
const ANIM_RANGE := 70.0
const MAX_ANIMATED := 44
const RUN_SPEED := 6.6
const LOOK_T := 1.9
const QUALITY_FACTOR: Array[float] = [0.4, 0.7, 1.0, 1.25]
const NODE_STEP := 12.0
const STATIC_SHARE := 0.45
const BIKE_SHARE := 0.1
const BIKE_CAP := 24
const BIKE_MARGIN := 7.0
const BIKE_NODE_STEP := 30.0

var _density := 0.6
var _cap := 1.0
var _target := 0
var _paths: Array[Paths.Path] = []
var _node_path := PackedInt32Array()
var _node_s := PackedFloat32Array()
var _node_pos := PackedVector2Array()
var _sidewalks: RefCounted

var _pool: Array[Ped] = []
var _active: Array[Ped] = []
var _look_count := PackedInt32Array()
var _mms: Array[MultiMesh] = []
var _mat: ShaderMaterial
var _rng := RandomNumberGenerator.new()

var _t_target := 0.0
var _t_spawn := 0.0
var _t_over := 0.0
var _last_player := Vector3.INF
var _auto_spawn := true
var spawn_min := SPAWN_MIN
var spawn_in_view := false
var _dt := 0.016

var _cp := PackedVector2Array()
var _cf := PackedVector2Array()
var _cs := PackedFloat32Array()
var _thr_r := Vector2.ZERO
var _thr_l := 0.0
var _thr_hw := 0.0
var _thr_a := 0.0
var _stat_flee := 0
var _stat_insure := 0
var _stat_spawned := 0
var _animated := 0
var _spots: Array[Dictionary] = []
var _spot_pos := PackedVector2Array()
var _spot_busy := PackedByteArray()
var _spot_groups: Array[PackedInt32Array] = []
var _spots_built := false
var _t_spots := 0.0
var _bike_mm: MultiMesh
var _bike_roads: Array[RoadNetwork.Road] = []
var _bike_nodes: Array[Vector2] = []
var _bike_juncs := {}
var _bike_ends := {}


class Ped extends RefCounted:
	var active := false
	var test := false
	var look := 0
	var kind := 0
	var state := 0
	var pos := Vector3.ZERO
	var yaw := 0.0
	var speed := 0.0
	var top_speed := 1.4
	var phase := 0.0
	var wheel := 0.0
	var mode := 0
	var h := 1.0
	var g := 1.0
	var path: Paths.Path
	var s := 0.0
	var dir := 1
	var lat := 0.0
	var lat_home := 0.0
	var lat_target := 0.0
	var flee_to := Vector3.ZERO
	var flee_cd := 0.0
	var calm_t := 0.0
	var acc := 0.0
	var run_speed := 6.6
	var pair: Ped
	var reacted := 0
	var home := Vector3.ZERO
	var home_yaw := 0.0
	var spot := -1
	var phone := false
	var road: RoadNetwork.Road
	var off := 3.0
	var ofs := Vector3.ZERO
	var turn_cd := 0.0


func _ready() -> void:
	name = "Pedestrians"
	process_mode = Node.PROCESS_MODE_PAUSABLE
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_rng.randomize()
	_density = clampf(float(Settings.get_value("pedestrian_density", 0.6)), 0.0, 1.0)
	_build_render()
	if Game.world != null:
		_build_paths()
		_build_bike_net()
	for i in MAX_PEDS:
		_pool.append(Ped.new())


func _build_render() -> void:
	_mat = Meshes.make_material(false)
	var aabb := AABB(Vector3(-2300, -300, -2300), Vector3(4600, 900, 4600))
	for i in Meshes.VARIANTS.size():
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = Meshes.build_person(Meshes.VARIANTS[i])
		mm.instance_count = CAP_PER_LOOK
		mm.visible_instance_count = 0
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = mm
		mi.material_override = _mat
		mi.custom_aabb = aabb
		add_child(mi)
		_mms.append(mm)
	_look_count.resize(Meshes.VARIANTS.size())
	_bike_mm = MultiMesh.new()
	_bike_mm.transform_format = MultiMesh.TRANSFORM_3D
	_bike_mm.use_custom_data = true
	_bike_mm.mesh = Meshes.build_bike()
	_bike_mm.instance_count = BIKE_CAP
	_bike_mm.visible_instance_count = 0
	var bmi := MultiMeshInstance3D.new()
	bmi.multimesh = _bike_mm
	bmi.material_override = Meshes.make_material(true)
	bmi.custom_aabb = aabb
	add_child(bmi)


func _build_paths() -> void:
	_sidewalks = Paths.new()
	_sidewalks.build(Game.world)
	_paths = _sidewalks.paths
	if _sidewalks.mesh_node != null:
		add_child(_sidewalks.mesh_node)
	var total := 0.0
	for pth in _paths:
		total += pth.length
	print("[pedestrians] %d pavement runs, %.0f m" % [_paths.size(), total])
	for pi in _paths.size():
		var p := _paths[pi]
		var s := 0.0
		while s < p.length:
			var q := p.at(s)
			_node_path.append(pi)
			_node_s.append(s)
			_node_pos.append(Vector2(q.x, q.z))
			s += NODE_STEP


# ----------------------------------------------------------------- public API

func set_density(v: float) -> void:
	_density = clampf(v, 0.0, 1.0)
	Settings.set_value("pedestrian_density", _density)


func get_density() -> float:
	return _density


func set_density_cap(v: float) -> void:
	_cap = clampf(v, 0.0, 1.0)


func effective_density() -> float:
	return minf(_density, _cap)


func active_count() -> int:
	var n := 0
	for p in _active:
		if not p.test:
			n += 1
	return n


func get_stats() -> Dictionary:
	return {"active": _active.size(), "target": _target, "animated": _animated, "paths": _paths.size(),
		"flee_events": _stat_flee, "insurance_events": _stat_insure, "spawned": _stat_spawned}


func set_auto_spawn(on: bool) -> void:
	_auto_spawn = on


func clear_all() -> void:
	for p: Ped in _active.duplicate():
		_release(p)


func get_peds() -> Array[Ped]:
	return _active


## Test helper: a person who walks (or jogs) along a straight synthetic path through `pos` along `yaw`.
func spawn_test(kind: int, pos: Vector3, yaw: float, look := 0) -> Ped:
	var p := _acquire()
	if p == null:
		return null
	var fwd := Vector3(-sin(yaw), 0.0, -cos(yaw))
	var path := Paths.Path.new()
	for k in range(-20, 21):
		var q := pos + fwd * (float(k) * 4.0)
		q.y = pos.y
		path.pts.append(q)
	path.finish()
	_init_ped(p, kind, look)
	p.test = true
	p.path = path
	p.s = path.length * 0.5
	p.dir = 1
	p.lat = 0.0
	p.lat_home = 0.0
	p.lat_target = 0.0
	p.pos = pos
	p.yaw = yaw
	p.speed = p.top_speed
	return p


## Test helper: a person sitting at `pos` (facing `yaw`).
func spawn_seated(pos: Vector3, yaw: float, look := 2) -> Ped:
	var p := _acquire()
	if p == null:
		return null
	_init_ped(p, Kind.SIT, look)
	p.test = true
	p.home = pos
	p.home_yaw = yaw
	p.pos = pos
	p.yaw = yaw
	return p


## Test helper: a cyclist riding along `yaw` through `pos` on a straight synthetic path.
func spawn_test_bike(pos: Vector3, yaw: float, look := 5) -> Ped:
	var p := spawn_test(Kind.WALK, pos, yaw, look)
	if p == null:
		return null
	p.kind = Kind.BIKE
	p.top_speed = 5.5
	p.speed = 5.5
	p.mode = 6
	return p


# ----------------------------------------------------------------- pool

func _acquire() -> Ped:
	for p in _pool:
		if not p.active:
			p.active = true
			_active.append(p)
			return p
	return null


func _release(p: Ped) -> void:
	if p.spot >= 0 and p.spot < _spot_busy.size():
		_spot_busy[p.spot] = 0
	p.spot = -1
	p.active = false
	p.pair = null
	p.path = null
	p.road = null
	_active.erase(p)


func _init_ped(p: Ped, kind: int, look: int) -> void:
	p.kind = kind
	p.state = State.LIVE
	p.test = false
	p.look = look
	p.h = float(Meshes.VARIANTS[look]["h"]) * _rng.randf_range(0.96, 1.05)
	p.g = float(Meshes.VARIANTS[look]["g"]) * _rng.randf_range(0.95, 1.06)
	p.phase = _rng.randf() * TAU
	p.speed = 0.0
	p.pair = null
	p.reacted = 0
	p.spot = -1
	p.phone = false
	p.road = null
	p.ofs = Vector3.ZERO
	p.turn_cd = 0.0
	p.acc = 0.0
	p.flee_cd = 0.0
	p.run_speed = _rng.randf_range(5.8, 7.6)
	p.top_speed = 1.45 * clampf(p.h, 0.8, 1.1) * _rng.randf_range(0.7, 1.15)
	if kind == Kind.JOG:
		p.top_speed = _rng.randf_range(2.6, 3.8)
	p.mode = 1


# ----------------------------------------------------------------- per frame

func _process(delta: float) -> void:
	if get_tree().paused:
		return
	_dt = minf(delta, 0.1)
	var car := Game.player_car
	if car == null or not is_instance_valid(car):
		return
	var pp := car.global_position
	if _last_player != Vector3.INF and pp.distance_to(_last_player) > 250.0:
		for p: Ped in _active.duplicate():
			if not p.test:
				_release(p)
	_last_player = pp
	_gather_cars()
	_t_target -= _dt
	if _t_target <= 0.0:
		_t_target = 1.0
		_update_target()
	if _auto_spawn:
		_t_spawn -= _dt
		if _t_spawn <= 0.0:
			_t_spawn = 0.35
			_spawn_pass(pp)
	_t_over -= _dt
	var do_over := _t_over <= 0.0
	if do_over:
		_t_over = 0.25
	var pxz := Vector2(pp.x, pp.z)
	var cam := _camera()
	var anim_pos := pp if cam == null else cam.global_position
	_animated = 0
	for p: Ped in _active.duplicate():
		var d2 := Vector2(p.pos.x - pxz.x, p.pos.z - pxz.y).length_squared()
		if not p.test and d2 > DESPAWN * DESPAWN:
			_release(p)
			continue
		p.acc += _dt
		var near_car := false
		for i in _cp.size():
			var r := _cs[i] * 2.5 + 40.0
			if (p.pos.x - _cp[i].x) * (p.pos.x - _cp[i].x) + (p.pos.z - _cp[i].y) * (p.pos.z - _cp[i].y) < r * r:
				near_car = true
				break
		if not near_car and d2 > 110.0 * 110.0 and p.acc < 0.034:
			continue
		var dt := p.acc
		p.acc = 0.0
		_step(p, dt, do_over, near_car)
	_update_overtakes(do_over)
	_write_buffers(anim_pos)


func _update_target() -> void:
	var f := effective_density()
	if Game.benchmark_mode:
		f = 0.0
	var q := clampi(int(Settings.get_value("quality", 2)), 0, 3)
	f *= QUALITY_FACTOR[q]
	var env: Node = Game.env
	if env != null:
		if env.is_night():
			f *= 0.35
		f *= 1.0 - 0.8 * clampf(float(env.get_precipitation()), 0.0, 1.0)
	_target = int(round(float(MAX_PEDS) * clampf(f, 0.0, 1.3)))


func _gather_cars() -> void:
	_cp.clear()
	_cf.clear()
	_cs.clear()
	var cars: Array[CarController] = []
	var pc := Game.player_car
	if pc != null and is_instance_valid(pc):
		cars.append(pc)
	var act: Node = Game.activities
	if act != null and act.has_method("get_ai_cars"):
		for c: CarController in act.get_ai_cars():
			if is_instance_valid(c):
				cars.append(c)
	for c in cars:
		var v := Vector2(c.linear_velocity.x, c.linear_velocity.z)
		var sp := v.length()
		var f := Vector2(-c.global_transform.basis.z.x, -c.global_transform.basis.z.z)
		if sp > 2.0:
			f = v / sp
		elif f.length() > 0.001:
			f = f.normalized()
		else:
			f = Vector2(0, -1)
		_cp.append(Vector2(c.global_position.x, c.global_position.z))
		_cf.append(f)
		_cs.append(sp)


## 0 = safe, 1 = must run, 2 = a car is on top of the person (instant relocation).
func _assess(p: Ped) -> int:
	var res := 0
	var pv := Vector2(p.pos.x, p.pos.z)
	for i in _cp.size():
		var d := pv - _cp[i]
		var f := _cf[i]
		var sp := _cs[i]
		var a := d.dot(f)
		var rgt := Vector2(-f.y, f.x)
		var l := d.dot(rgt)
		if a > -3.6 and a < 3.6 + sp * _dt * 2.5 and absf(l) < 1.8:
			_thr_r = rgt
			_thr_l = l
			_thr_a = a
			return 2
		if sp > 2.0:
			var look := maxf(14.0, sp * LOOK_T)
			if a > -3.6 and a < look:
				var hw := 2.6 + minf(maxf(a, 0.0) * 0.05, 4.0)
				if absf(l) < hw:
					_thr_r = rgt
					_thr_l = l
					_thr_hw = hw
					_thr_a = a
					res = 1
	return res


func _ground_ok(x: float, z: float, ref_y: float) -> bool:
	var w: World = Game.world
	var h := w.data.height_at(x, z)
	if absf(h - ref_y) > 3.0:
		return false
	if w.water_level_at(x, z) > h - 0.3:
		return false
	return w.data.network.edge_clearance(Vector3(x, h, z), 14.0) > 0.6


## Target on the side away from the car's path with at least `need` metres of lateral clearance.
func _find_safe(p: Ped, need: float) -> Vector3:
	var sgn := 1.0 if _thr_l >= 0.0 else -1.0
	if absf(_thr_l) < 0.25:
		sgn = 1.0 if _rng.randf() < 0.5 else -1.0
	for pass_i in 2:
		var sg := sgn if pass_i == 0 else -sgn
		var base := absf(_thr_l) if pass_i == 0 else -absf(_thr_l)
		for extra: float in [0.0, 2.5, 5.0, 8.0, 12.0]:
			var dist := maxf(need - base, 1.5) + extra
			var t := Vector2(p.pos.x, p.pos.z) + _thr_r * (sg * dist)
			if _ground_ok(t.x, t.y, p.pos.y):
				return Vector3(t.x, Game.world.data.height_at(t.x, t.y), t.y)
	var t2 := Vector2(p.pos.x, p.pos.z) + _thr_r * (sgn * maxf(need - absf(_thr_l), 1.5))
	return Vector3(t2.x, p.pos.y, t2.y)


func _step(p: Ped, dt: float, do_over: bool, near_car: bool) -> void:
	var threat := _assess(p) if near_car or p.state != State.LIVE else 0
	if threat == 2:
		_insure(p)
	elif threat == 1:
		p.flee_cd -= dt
		if p.state != State.FLEE or p.flee_cd <= 0.0:
			_begin_flee(p)
	match p.state:
		State.LIVE:
			_live(p, dt)
		State.FLEE:
			_flee(p, dt)
		State.CALM:
			p.speed = move_toward(p.speed, 0.0, 14.0 * dt)
			p.mode = 6 if p.kind == Kind.BIKE else 0
			p.calm_t -= dt
			if threat == 0 and p.calm_t <= 0.0:
				p.state = State.RETURN
		State.RETURN:
			_return(p, dt)


func _begin_flee(p: Ped) -> void:
	p.state = State.FLEE
	p.flee_cd = 0.3
	p.reacted += 1
	_stat_flee += 1
	p.flee_to = _find_safe(p, _thr_hw + 1.5)


func _insure(p: Ped) -> void:
	_stat_insure += 1
	var t := _find_safe(p, 3.8)
	p.pos = t
	p.state = State.CALM
	p.calm_t = _rng.randf_range(1.5, 2.5)
	p.speed = 0.0
	p.mode = 6 if p.kind == Kind.BIKE else 0
	p.reacted += 1


func _face(p: Ped, dir: Vector2, dt: float, rate: float) -> void:
	if dir.length() < 0.001:
		return
	var want := atan2(-dir.x, -dir.y)
	p.yaw = lerp_angle(p.yaw, want, minf(1.0, rate * dt))


func _flee(p: Ped, dt: float) -> void:
	var to := Vector2(p.flee_to.x - p.pos.x, p.flee_to.z - p.pos.z)
	var dist := to.length()
	if dist < 0.5:
		p.state = State.CALM
		p.calm_t = _rng.randf_range(1.8, 3.2)
		return
	var dir := to / dist
	var bike := p.kind == Kind.BIKE
	_face(p, dir, dt, 12.0 if bike else 22.0)
	var facing := Vector2(-sin(p.yaw), -cos(p.yaw))
	var gate := clampf(facing.dot(dir) * 1.4 - 0.2, 0.15, 1.0)
	p.speed = move_toward(p.speed, p.run_speed * (1.3 if bike else 1.0) * gate, 30.0 * dt)
	var step := minf(p.speed * dt, dist)
	p.pos.x += facing.x * step
	p.pos.z += facing.y * step
	p.pos.y = lerpf(p.pos.y, Game.world.data.height_at(p.pos.x, p.pos.z), minf(1.0, 12.0 * dt))
	p.mode = 6 if bike else 2


func _return(p: Ped, dt: float) -> void:
	var s := 0.0
	var goal := p.home
	if p.kind == Kind.BIKE:
		goal = _bike_point(p)
		s = p.s
	elif p.path != null:
		s = p.path.closest_s(p.pos)
		goal = p.path.at(s) + _perp(p.path.tangent(s)) * p.lat
	var to := Vector2(goal.x - p.pos.x, goal.z - p.pos.z)
	var dist := to.length()
	if dist < (0.5 if p.path != null or p.kind == Kind.BIKE else 0.12):
		p.state = State.LIVE
		p.s = s
		return
	var dir := to / dist
	_face(p, dir, dt, 8.0)
	p.speed = move_toward(p.speed, p.top_speed * 1.1, 3.0 * dt)
	var facing := Vector2(-sin(p.yaw), -cos(p.yaw))
	var step := minf(p.speed * dt, dist)
	p.pos.x += facing.x * step
	p.pos.z += facing.y * step
	p.pos.y = lerpf(p.pos.y, Game.world.data.height_at(p.pos.x, p.pos.z) + 0.05, minf(1.0, 8.0 * dt))
	p.mode = 6 if p.kind == Kind.BIKE else 1


func _perp(t: Vector3) -> Vector3:
	return Vector3(-t.z, 0.0, t.x)


func _live(p: Ped, dt: float) -> void:
	match p.kind:
		Kind.WALK, Kind.JOG:
			_walk(p, dt)
		Kind.BIKE:
			_ride(p, dt)
		Kind.SIT:
			p.mode = 7 if p.phone else 3
			_hold_home(p, dt)
		Kind.PHONE:
			p.mode = 4
			_hold_home(p, dt)
		Kind.TALK:
			p.mode = 5
			_hold_home(p, dt)
		_:
			p.mode = 0
			_hold_home(p, dt)


func _walk(p: Ped, dt: float) -> void:
	var path := p.path
	if path == null:
		return
	p.speed = move_toward(p.speed, p.top_speed, 1.5 * dt)
	p.s += float(p.dir) * p.speed * dt
	if p.s <= 0.0 or p.s >= path.length:
		p.s = clampf(p.s, 0.0, path.length)
		p.dir = -p.dir
		p.lat_home = -p.lat_home
		p.lat_target = p.lat_home
	p.lat = move_toward(p.lat, p.lat_target, 1.1 * dt)
	var t := path.tangent(p.s) * float(p.dir)
	var q := path.at(p.s) + _perp(path.tangent(p.s)) * p.lat
	p.pos = q
	_face(p, Vector2(t.x, t.z), dt, 9.0)
	p.mode = 2 if p.kind == Kind.JOG else 1


func _bike_point(p: Ped) -> Vector3:
	if p.road != null:
		return p.road.surface_point(p.s, float(p.dir) * p.off)
	return p.path.at(p.s)


func _bike_tangent(p: Ped) -> Vector3:
	if p.road != null:
		return p.road.flat_tangent_at(p.s) * float(p.dir)
	return p.path.tangent(p.s) * float(p.dir)


func _ride(p: Ped, dt: float) -> void:
	p.speed = move_toward(p.speed, p.top_speed, 1.2 * dt)
	var prev := p.s
	p.s += float(p.dir) * p.speed * dt
	p.turn_cd -= dt
	if p.road != null:
		_ride_junctions(p, prev)
	elif p.s <= 0.0 or p.s >= p.path.length:
		p.s = clampf(p.s, 0.0, p.path.length)
		p.dir = -p.dir
	var q := _bike_point(p)
	p.ofs = p.ofs.move_toward(Vector3.ZERO, 8.0 * dt)
	p.pos = q + p.ofs
	var t := _bike_tangent(p)
	_face(p, Vector2(t.x, t.z), dt, 5.0)
	p.mode = 6


func _bike_switch(p: Ped, road: RoadNetwork.Road, s: float, dir: int) -> void:
	var old := _bike_point(p)
	p.road = road
	p.s = s
	p.dir = dir
	p.off = _bike_offset(road)
	p.ofs = old - _bike_point(p)
	p.turn_cd = 4.0


func _ride_junctions(p: Ped, prev: float) -> void:
	var r := p.road
	var at_end := (p.dir > 0 and p.s > r.length - BIKE_MARGIN) or (p.dir < 0 and p.s < BIKE_MARGIN)
	if at_end:
		var opts: Array = _bike_ends.get(Vector2i(r.idx, 1 if p.dir > 0 else 0), [])
		if not opts.is_empty() and _rng.randf() < 0.85:
			var o: Dictionary = opts[_rng.randi() % opts.size()]
			_bike_switch(p, o["road"], float(o["s"]), int(o["dir"]) if int(o["dir"]) != 0 else (1 if _rng.randf() < 0.5 else -1))
		else:
			var old := _bike_point(p)
			p.dir = -p.dir
			p.ofs = old - _bike_point(p)
		return
	if p.turn_cd > 0.0:
		return
	for e: Dictionary in _bike_juncs.get(r.idx, []):
		var es: float = e["s"]
		if (prev - es) * (p.s - es) <= 0.0 and _rng.randf() < 0.35:
			_bike_switch(p, e["road"], float(e["to_s"]), int(e["to_dir"]))
			return


func _bike_offset(r: RoadNetwork.Road) -> float:
	return minf(r.lane_offset(r.lanes) + 1.45, r.width * 0.5 + r.shoulder - 0.3)


func _build_bike_net() -> void:
	var net: RoadNetwork = Game.world.data.network
	for r in net.roads:
		if r.traffic and r.id != "ring" and (r.cls == 3 or (r.cls == 1 and r.length < 1000.0)):
			_bike_roads.append(r)
	for r in _bike_roads:
		var s := BIKE_MARGIN + 10.0
		while s < r.length - BIKE_MARGIN - 10.0:
			_bike_nodes.append(Vector2(float(r.idx), s))
			s += BIKE_NODE_STEP
	for jd: Dictionary in net.junctions:
		var par := net.get_road(String(jd["parent"]))
		var chi := net.get_road(String(jd["child"]))
		if not (par in _bike_roads and chi in _bike_roads):
			continue
		var pi := int(jd["parent_index"])
		var ce := int(jd["child_end"])
		var ps := float(pi) * par.ds
		var inward := 1 if ce == 0 else -1
		var cs := BIKE_MARGIN + 0.5 if ce == 0 else chi.length - BIKE_MARGIN - 0.5
		if not _bike_juncs.has(par.idx):
			_bike_juncs[par.idx] = []
		_bike_juncs[par.idx].append({"s": ps, "road": chi, "to_s": cs, "to_dir": inward})
		var key := Vector2i(chi.idx, ce)
		if not _bike_ends.has(key):
			_bike_ends[key] = []
		_bike_ends[key].append({"road": par, "s": ps, "dir": 0})
	print("[pedestrians] %d cycling roads, %d junctions" % [_bike_roads.size(), _bike_ends.size()])


func _hold_home(p: Ped, dt: float) -> void:
	p.speed = 0.0
	p.pos = p.home
	p.yaw = lerp_angle(p.yaw, p.home_yaw, minf(1.0, 6.0 * dt))


func _update_overtakes(do_over: bool) -> void:
	if not do_over:
		return
	for p in _active:
		if p.state != State.LIVE or p.path == null or (p.kind != Kind.WALK and p.kind != Kind.JOG):
			continue
		var blocked := false
		for q in _active:
			if q == p or q.path != p.path or q.dir != p.dir or q.state != State.LIVE:
				continue
			var gap := (q.s - p.s) * float(p.dir)
			if gap > 0.0 and gap < 3.2 and q.speed < p.speed - 0.1 and absf(q.lat - p.lat) < 0.7:
				blocked = true
				break
		p.lat_target = -p.lat_home if blocked else p.lat_home


# ----------------------------------------------------------------- spawning

func _spawn_pass(pp: Vector3) -> void:
	if _target <= 0 or _node_path.is_empty():
		return
	var live := 0
	for p in _active:
		if not p.test:
			live += 1
	if live >= _target:
		if live > _target + 3:
			_cull_one(pp)
		return
	var pxz := Vector2(pp.x, pp.z)
	if not _spots_built:
		_t_spots -= 0.35
		if _t_spots <= 0.0:
			_t_spots = 2.0
			_build_spots()
	if not _bike_nodes.is_empty() and _rng.randf() < 0.18:
		var bikes := 0
		for p in _active:
			if not p.test and p.kind == Kind.BIKE:
				bikes += 1
		if float(bikes) < float(_target) * BIKE_SHARE and _spawn_bike(pxz):
			return
	if not _spot_pos.is_empty() and _rng.randf() < 0.5:
		var statics := 0
		for p in _active:
			if not p.test and p.kind >= Kind.SIT:
				statics += 1
		if float(statics) < float(_target) * STATIC_SHARE and _spawn_spot(pxz):
			return
	var cand: Array[int] = []
	for i in _node_pos.size():
		var d := _node_pos[i].distance_to(pxz)
		if d > spawn_min and d < SPAWN_MAX:
			cand.append(i)
	if cand.is_empty():
		return
	for attempt in 6:
		var i := cand[_rng.randi() % cand.size()]
		var path := _paths[_node_path[i]]
		var s := _node_s[i] + _rng.randf_range(-4.0, 4.0)
		var q := path.at(s)
		if (not spawn_in_view and _in_view(q)) or _taken(q, 4.0):
			continue
		_spawn_walker(path, clampf(s, 0.0, path.length), live)
		return


func _spawn_bike(pxz: Vector2) -> bool:
	for attempt in 10:
		var n := _bike_nodes[_rng.randi() % _bike_nodes.size()]
		var r := _bike_roads[0]
		for rr in _bike_roads:
			if rr.idx == int(n.x):
				r = rr
		var s := n.y + _rng.randf_range(-10.0, 10.0)
		var q := r.point_at(s)
		var d := Vector2(q.x, q.z).distance_to(pxz)
		if d < spawn_min or d > SPAWN_MAX or (not spawn_in_view and _in_view(q)) or _taken(q, 6.0):
			continue
		var look := _free_look(_rng.randi() % Meshes.VARIANTS.size())
		var p := _acquire()
		if look < 0 or p == null:
			if p != null:
				_release(p)
			return false
		_init_ped(p, Kind.BIKE, look)
		p.road = r
		p.s = s
		p.dir = 1 if _rng.randf() < 0.5 else -1
		p.off = _bike_offset(r)
		p.top_speed = _rng.randf_range(4.2, 6.9)
		p.speed = p.top_speed
		p.pos = _bike_point(p)
		var t := _bike_tangent(p)
		p.yaw = atan2(-t.x, -t.z)
		p.mode = 6
		_stat_spawned += 1
		return true
	return false


func _spawn_spot(pxz: Vector2) -> bool:
	for attempt in 8:
		var i := _rng.randi() % _spot_pos.size()
		var d := _spot_pos[i].distance_to(pxz)
		if d < spawn_min or d > SPAWN_MAX or _spot_busy[i] != 0:
			continue
		var sp := _spots[i]
		var members: PackedInt32Array = _spot_groups[int(sp["group"])]
		var ok := true
		for m in members:
			if _spot_busy[m] != 0:
				ok = false
		if not ok or (not spawn_in_view and _in_view(sp["pos"])):
			continue
		for m in members:
			var ms := _spots[m]
			var look := _free_look(_rng.randi() % Meshes.VARIANTS.size())
			var p := _acquire()
			if look < 0 or p == null:
				if p != null:
					_release(p)
				continue
			_init_ped(p, int(ms["kind"]), look)
			p.spot = m
			p.phone = bool(ms["phone"])
			p.home = ms["pos"]
			p.home_yaw = float(ms["yaw"]) + _rng.randf_range(-0.12, 0.12)
			p.pos = p.home
			p.yaw = p.home_yaw
			p.phase = _rng.randf() * TAU
			_spot_busy[m] = 1
			_stat_spawned += 1
		return true
	return false


func _taken(q: Vector3, r: float) -> bool:
	for p in _active:
		if absf(p.pos.x - q.x) < r and absf(p.pos.z - q.z) < r:
			return true
	return false


func _cull_one(pp: Vector3) -> void:
	var worst: Ped = null
	var wd := 0.0
	for p in _active:
		if p.test or p.state != State.LIVE:
			continue
		var d := Vector2(p.pos.x - pp.x, p.pos.z - pp.z).length()
		if d > wd and not _in_view(p.pos):
			wd = d
			worst = p
	if worst != null:
		_release(worst)


func _free_look(start: int) -> int:
	var n := Meshes.VARIANTS.size()
	for k in n:
		var i := (start + k) % n
		if _look_count[i] < CAP_PER_LOOK - 1:
			return i
	return -1


func _spawn_walker(path: Paths.Path, s: float, live: int) -> void:
	var r := _rng.randf()
	var kind := Kind.JOG if r < 0.14 else Kind.WALK
	var paired := kind == Kind.WALK and r > 0.62 and live + 2 <= _target + 1
	var dir := 1 if _rng.randf() < 0.5 else -1
	var look := _free_look(_rng.randi() % Meshes.VARIANTS.size())
	if look < 0:
		return
	var p := _acquire()
	if p == null:
		return
	_init_ped(p, kind, look)
	p.path = path
	p.s = s
	p.dir = dir
	p.lat_home = (0.75 if paired else 0.55) * float(dir)
	p.lat = p.lat_home
	p.lat_target = p.lat_home
	p.pos = path.at(s)
	var t := path.tangent(s) * float(dir)
	p.yaw = atan2(-t.x, -t.z)
	p.speed = p.top_speed
	_stat_spawned += 1
	if paired:
		var look2 := _free_look(_rng.randi() % Meshes.VARIANTS.size())
		var p2 := _acquire()
		if look2 >= 0 and p2 != null:
			_init_ped(p2, kind, look2)
			p2.path = path
			p2.s = s - float(dir) * 0.15
			p2.dir = dir
			p2.top_speed = p.top_speed
			p2.lat_home = 0.05 * float(dir)
			p2.lat = p2.lat_home
			p2.lat_target = p2.lat_home
			p2.pos = path.at(p2.s)
			p2.yaw = p.yaw
			p2.speed = p2.top_speed
			p.pair = p2
			p2.pair = p
		elif p2 != null:
			_release(p2)


# ----------------------------------------------------------------- places (benches, stops, cafe, pumps, quay, festival)

func _add_spot(pos: Vector3, yaw: float, kind: int, group := -1, phone := false) -> int:
	var idx := _spots.size()
	var g := group
	if g < 0:
		g = _spot_groups.size()
		_spot_groups.append(PackedInt32Array())
	_spot_groups[g].append(idx)
	_spots.append({"pos": pos, "yaw": yaw, "kind": kind, "group": g, "phone": phone})
	_spot_pos.append(Vector2(pos.x, pos.z))
	return g


func _stand_kind() -> int:
	var r := _rng.randf()
	return Kind.PHONE if r < 0.4 else Kind.STAND


func _add_circle(c: Vector3, n: int, radius: float, kind: int) -> void:
	var g := -1
	var a0 := _rng.randf() * TAU
	for k in n:
		var a := a0 + TAU * float(k) / float(n)
		var m := c + Vector3(cos(a), 0.0, sin(a)) * radius
		m.y = c.y
		g = _add_spot(m, atan2(-(c.x - m.x), -(c.z - m.z)), kind, g)


func _ground_at(x: float, z: float) -> float:
	return Game.world.data.height_at(x, z)


func _build_spots() -> void:
	var st: Node = null
	if Game.main != null:
		st = Game.main.get_node_or_null("Settlements")
	if st == null:
		return
	var items: Array = st.items
	if items.is_empty():
		return
	_spots_built = true
	var crng := RandomNumberGenerator.new()
	crng.seed = 7311
	for it in items:
		var nm: String = it["name"]
		var xf: Transform3D = it["xf"]
		var yaw := xf.basis.get_euler().y
		match nm:
			"Bench":
				for x: float in [-0.42, 0.42]:
					if crng.randf() < (0.6 if x < 0.0 else 0.4):
						_add_spot(xf * Vector3(x, 0.0, 0.1), yaw, Kind.SIT, -1, crng.randf() < 0.35)
			"Bus_Stop":
				if crng.randf() < 0.5:
					_add_spot(xf * Vector3(-0.7 + crng.randf() * 1.4, 0.03, 0.5), yaw, Kind.SIT, -1, crng.randf() < 0.4)
				if crng.randf() < 0.4:
					_add_circle(xf * Vector3(crng.randf_range(-0.8, 0.8), 0.0, -0.9), 2, 0.55, Kind.TALK)
				else:
					for k in 1 + crng.randi() % 2:
						_add_spot(xf * Vector3(-1.2 + float(k) * 2.2 + crng.randf() * 0.3, 0.0, -0.45), yaw, Kind.PHONE if crng.randf() < 0.5 else Kind.STAND)
			"Diner":
				var bb := PropLibrary.aabb("Diner")
				var c := xf * Vector3(crng.randf_range(-2.0, 2.0), 0.0, bb.position.z - 3.0)
				c.y = xf.origin.y
				_add_circle(c, 2 + crng.randi() % 2, 0.8, Kind.TALK)
				if crng.randf() < 0.6:
					var q := xf * Vector3(-5.0, 0.0, bb.position.z - 2.4)
					_add_spot(Vector3(q.x, xf.origin.y, q.z), yaw, Kind.PHONE)
			"Fuel_Pump":
				if crng.randf() < 0.55:
					var q := xf * Vector3(1.1, 0.0, 0.2)
					_add_spot(Vector3(q.x, xf.origin.y, q.z), atan2(-(xf.origin.x - q.x), -(xf.origin.z - q.z)), _stand_kind())
			"Festival_Stage":
				for k in 7:
					var a := crng.randf_range(-0.9, 0.9)
					var r := crng.randf_range(7.0, 15.0)
					var q := xf * Vector3(sin(a) * r, 0.0, PropLibrary.aabb("Festival_Stage").position.z - cos(a) * r + 3.0)
					var y := _ground_at(q.x, q.z)
					if absf(y - xf.origin.y) > 3.0:
						continue
					var cc := Vector3(q.x, y, q.z)
					if crng.randf() < 0.45:
						_add_circle(cc, 2 + crng.randi() % 2, 0.8, Kind.TALK)
					else:
						_add_spot(cc, yaw + PI + crng.randf_range(-0.3, 0.3), _stand_kind())
	_build_quay_spots(crng)
	_spot_busy.resize(_spots.size())
	print("[pedestrians] %d places for people (%d groups)" % [_spots.size(), _spot_groups.size()])


func _build_quay_spots(crng: RandomNumberGenerator) -> void:
	var road: RoadNetwork.Road = Game.world.data.network.get_road("harbour_st")
	if road == null:
		return
	var w: World = Game.world
	var s := 8.0
	while s < road.length - 8.0:
		s += 11.0
		for side: float in [1.0, -1.0]:
			var rt := road.right_at(s)
			var p := road.point_at(s) + rt * side * (road.width * 0.5 + road.shoulder + 2.4)
			var out := p + rt * side * 5.0
			var hp := _ground_at(p.x, p.z)
			if w.water_level_at(out.x, out.z) <= _ground_at(out.x, out.z) - 0.3 or w.water_level_at(p.x, p.z) > hp - 0.3:
				continue
			if not _ground_ok(p.x, p.z, hp) or crng.randf() > 0.55:
				continue
			var yaw := atan2(-(out.x - p.x), -(out.z - p.z))
			if crng.randf() < 0.35:
				_add_circle(Vector3(p.x, hp, p.z), 2, 0.7, Kind.TALK)
			else:
				_add_spot(Vector3(p.x, hp, p.z), yaw, _stand_kind())


# ----------------------------------------------------------------- rendering

func _write_buffers(anim_pos: Vector3) -> void:
	_look_count.fill(0)
	var nb := 0
	for p in _active:
		var li := p.look
		var n := _look_count[li]
		if n >= CAP_PER_LOOK:
			continue
		_look_count[li] = n + 1
		var dxz := Vector2(p.pos.x - anim_pos.x, p.pos.z - anim_pos.z).length_squared()
		var amt := 0.0
		if dxz < ANIM_RANGE * ANIM_RANGE and _animated < MAX_ANIMATED:
			amt = 1.0
			_animated += 1
			var rate := 2.0
			if p.mode == 1:
				rate = 3.3 + p.speed * 2.4
			elif p.mode == 2:
				rate = 6.0 + p.speed * 1.9
			elif p.mode == 6:
				rate = p.speed * 1.6
			p.phase = fmod(p.phase + rate * _dt, TAU * 8.0)
		var c := cos(p.yaw)
		var sn := sin(p.yaw)
		var mm := _mms[li]
		var ppos := p.pos
		if p.kind == Kind.BIKE and nb < BIKE_CAP:
			p.wheel = fmod(p.wheel - p.speed / 0.34 * _dt, TAU)
			_bike_mm.set_instance_transform(nb, Transform3D(Basis(Vector3(c, 0.0, -sn), Vector3.UP, Vector3(sn, 0.0, c)), p.pos))
			_bike_mm.set_instance_custom_data(nb, Color(p.wheel, 0.0, 0.0, 0.0))
			nb += 1
			ppos = p.pos + Vector3(sn, 0.0, c) * 0.2
		mm.set_instance_transform(n, Transform3D(Basis(Vector3(c * p.g, 0.0, -sn * p.g), Vector3(0.0, p.h, 0.0), Vector3(sn * p.g, 0.0, c * p.g)), ppos))
		mm.set_instance_custom_data(n, Color(p.phase, 0.0, float(p.mode), amt))
	for i in _mms.size():
		_mms[i].visible_instance_count = _look_count[i]
	_bike_mm.visible_instance_count = nb


func _camera() -> Camera3D:
	var rig: Node = Game.camera_rig
	if rig == null:
		return null
	return rig.get("camera") as Camera3D


func _in_view(p: Vector3) -> bool:
	var cam := _camera()
	return cam != null and cam.is_position_in_frustum(p + Vector3.UP * 1.0)
