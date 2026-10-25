extends Node3D
## Pooled StaticBody3D colliders (no surface meta) for tree trunks, rocks and cacti near the player (and
## physics-mode traffic), refreshed four times per second from the dressing chunks.
## Chunk records (dressing_rules.gd): `colliders` trunk cylinders [x, y, z, radius, height, 0] on layer 1, and
## `hulls` [x, y, z, hull index, basis x, basis y, basis z]: the prop's convex hull with the visible instance
## transform (so it rests on the ground exactly like the mesh), on the barrier layer: car bodies hit it, wheel
## rays (mask 1|16) never ride up a boulder like a ramp.

const RADIUS := 115.0
const MAX_BODIES := 448
const STRIDE := 6
const HULL_STRIDE := 13
const HULL_BIT := 0x8000
const HULL_LAYER := 32
const CHUNK := 128.0
const HALF := 2048.0

## Dictionary Vector2i -> chunk object with `state` (2 = built), `colliders` and `hulls` (PackedFloat32Array).
var chunks: Dictionary = {}
var _bodies: Array[StaticBody3D] = []
var _shapes: Array[CollisionShape3D] = []
var _cyl: Array[CylinderShape3D] = []
var _hull_shapes: Array[ConvexPolygonShape3D] = []
var _assigned: Dictionary = {}       # collider id -> body index
var _free: Array[int] = []
var _timer: float = 0.0
var active: int = 0
## Radius (m) the nearest MAX_BODIES records reach (RADIUS unless the pool is full).
var cut_radius: float = RADIUS
var _last_focus := Vector3(INF, 0.0, INF)
var _last_chunks: int = -1
var _acc_us: int = 0
var _runs: int = 0
var _max_us: int = 0


## Shared hull shapes (one per dressing_rules.HULL_NAMES entry); bodies scale and rotate them per record.
func set_hulls(points: Array[PackedVector3Array]) -> void:
	_hull_shapes.clear()
	for pts in points:
		var s := ConvexPolygonShape3D.new()
		s.points = pts
		_hull_shapes.append(s)


func _new_body() -> int:
	var i := _bodies.size()
	var body := StaticBody3D.new()
	body.name = "DressCol%d" % i
	body.collision_layer = 1
	body.collision_mask = 0
	body.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	var cs := CollisionShape3D.new()
	cs.disabled = true
	body.add_child(cs)
	add_child(body)
	_bodies.append(body)
	_shapes.append(cs)
	_cyl.append(CylinderShape3D.new())
	return i


func _focus_points() -> Array[Vector3]:
	var pts: Array[Vector3] = []
	var car := Game.player_car
	if car != null and is_instance_valid(car):
		pts.append(car.global_position)
	if Game.world is World:
		var extra: Array[Vector3] = (Game.world as World).extra_physics_points
		for k in mini(extra.size(), 6):
			pts.append(extra[k])
	return pts


## Average and worst update cost (ms) since the last call.
func avg_ms() -> float:
	var v := float(_acc_us) / maxi(_runs, 1) / 1000.0
	_acc_us = 0
	_runs = 0
	return v


func max_ms() -> float:
	var v := _max_us / 1000.0
	_max_us = 0
	return v


func pool_size() -> int:
	return _bodies.size()


## Releases every body. Call when the chunks are rebuilt: collider ids (chunk key, record index) repeat
## between builds, so a kept body would stay at the old record's position.
func reset() -> void:
	for id: int in _assigned:
		var bi: int = _assigned[id]
		_shapes[bi].disabled = true
		_free.append(bi)
	_assigned.clear()
	active = 0
	_last_chunks = -1
	_last_focus = Vector3(INF, 0.0, INF)


func _physics_process(delta: float) -> void:
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = 0.25
	var t0 := Time.get_ticks_usec()
	_update()
	var us := Time.get_ticks_usec() - t0
	_acc_us += us
	_max_us = maxi(_max_us, us)
	_runs += 1


func _update() -> void:
	var pts := _focus_points()
	if pts.is_empty():
		return
	# Nothing to do while the player is (nearly) stationary and nothing new streamed in.
	if pts.size() == 1 and pts[0].distance_squared_to(_last_focus) < 25.0 and chunks.size() == _last_chunks:
		return
	_last_focus = pts[0]
	_last_chunks = chunks.size()
	var r2 := RADIUS * RADIUS
	var ids := PackedInt64Array()
	var d2s := PackedFloat32Array()
	var refs: Array[PackedFloat32Array] = []
	var ref_idx := PackedInt32Array()
	var ks := PackedInt32Array()
	var seen: Dictionary = {}
	for f in pts:
		var i0 := floori((f.x - RADIUS + HALF) / CHUNK)
		var i1 := floori((f.x + RADIUS + HALF) / CHUNK)
		var j0 := floori((f.z - RADIUS + HALF) / CHUNK)
		var j1 := floori((f.z + RADIUS + HALF) / CHUNK)
		for j in range(j0, j1 + 1):
			for i in range(i0, i1 + 1):
				var key := Vector2i(i, j)
				if seen.has(key):
					continue
				seen[key] = true
				var c: Object = chunks.get(key)
				if c == null or int(c.get("state")) != 2:
					continue
				var base := (i * 64 + j) << 16
				for hull in 2:
					var arr: PackedFloat32Array = c.get("hulls" if hull == 1 else "colliders")
					if arr.is_empty():
						continue
					refs.append(arr)
					var ri := refs.size() - 1
					var stride := HULL_STRIDE if hull == 1 else STRIDE
					var tag := HULL_BIT if hull == 1 else 0
					var fx := f.x
					var fz := f.z
					for k in range(0, arr.size(), stride):
						var dx := arr[k] - fx
						var dz := arr[k + 2] - fz
						var d2 := dx * dx + dz * dz
						if d2 < r2:
							ids.append(base | tag | (k / stride))
							d2s.append(d2)
							ref_idx.append(ri)
							ks.append(k)
	# Keep the nearest MAX_BODIES using a distance histogram instead of a sort.
	var cut := r2
	if ids.size() > MAX_BODIES:
		var bins := PackedInt32Array()
		bins.resize(32)
		for d2 in d2s:
			bins[mini(int(d2 / r2 * 32.0), 31)] += 1
		var acc := 0
		for b in 32:
			acc += bins[b]
			if acc > MAX_BODIES:
				cut = r2 * b / 32.0
				break
	cut_radius = sqrt(cut)
	var wanted: Dictionary = {}
	for n in ids.size():
		if d2s[n] < cut:
			wanted[ids[n]] = n
	for id: int in _assigned.keys():
		if not wanted.has(id):
			var bi: int = _assigned[id]
			_shapes[bi].disabled = true
			_free.append(bi)
			_assigned.erase(id)
	for id: int in wanted:
		if _assigned.has(id):
			continue
		var bi := -1
		if not _free.is_empty():
			bi = _free.pop_back()
		elif _bodies.size() < MAX_BODIES:
			bi = _new_body()
		else:
			break
		var n: int = wanted[id]
		var arr := refs[ref_idx[n]]
		var k := ks[n]
		var pos := Vector3(arr[k], arr[k + 1], arr[k + 2])
		var cs := _shapes[bi]
		if (id & HULL_BIT) != 0:
			var hi := int(arr[k + 3])
			if hi < 0 or hi >= _hull_shapes.size():
				_free.append(bi)
				continue
			cs.shape = _hull_shapes[hi]
			cs.transform = Transform3D(Basis(Vector3(arr[k + 4], arr[k + 5], arr[k + 6]), Vector3(arr[k + 7], arr[k + 8], arr[k + 9]),
				Vector3(arr[k + 10], arr[k + 11], arr[k + 12])), Vector3.ZERO)
			_bodies[bi].collision_layer = HULL_LAYER
			_bodies[bi].global_position = pos
		else:
			var rad := maxf(arr[k + 3], 0.08)
			var h := maxf(arr[k + 4], 1.0)
			_cyl[bi].radius = rad
			_cyl[bi].height = h
			cs.shape = _cyl[bi]
			cs.transform = Transform3D.IDENTITY
			_bodies[bi].collision_layer = 1
			_bodies[bi].global_position = pos + Vector3(0, h * 0.5 - 0.6, 0)
		cs.disabled = false
		_assigned[id] = bi
	active = _assigned.size()
