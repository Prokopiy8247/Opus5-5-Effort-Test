extends Node3D
## Civilian traffic on the baked road network.
## - Lanes are (road, direction, lateral offset) on the 2 m road samples; junction links come
##   from the baked joins (minor road ends attach to a major road sample).
## - Car following: Intelligent Driver Model with curvature-limited desired speed, the player
##   car as a potential leader, junction give-way on minor roads, highway lane changes.
## - Simulation LOD: kinematic lane movement at distance (frozen RigidBody3D moved by this
##   manager), full raycast-vehicle physics with an AI driver within PHYSICS_RADIUS of the
##   player, despawn beyond DESPAWN_RADIUS; vehicles are pooled per type.
## - Crash reaction: physics response, then hazard stop; crashed cars despawn when unseen.

const SPAWN_MIN := 220.0
const SPAWN_MAX := 650.0
const DESPAWN_RADIUS := 820.0
const PHYSICS_RADIUS := 75.0
const PHYSICS_EXIT := 95.0
const MAX_VEHICLES := 48
const STEP := 2.0

enum Mode { KINEMATIC, DYNAMIC, CRASHED }

class Vehicle:
	extends RefCounted
	var type_id: String = ""
	var node: CarController
	var road: int = 0
	var s: float = 0.0
	var dir: int = 1
	var lane: int = 0
	var offset: float = 1.75
	var target_offset: float = 1.75
	var speed: float = 0.0
	var v0_factor: float = 1.0
	var max_kmh: float = 100.0
	var length: float = 4.4
	var mode: int = 0
	var crash_timer: float = 0.0
	var turn_plan: Dictionary = {}
	var visual_off: Vector3 = Vector3.ZERO
	var horn_timer: float = 0.0
	var acc: float = 0.0
	var think: float = 0.0
	var pending_dt: float = 0.0
	var lane_change_cd: float = 0.0
	var active: bool = false
	var stuck: float = 0.0

var world: Node
var data: WorldData
var density: float = 0.6
var vehicles: Array[Vehicle] = []
var _pool: Dictionary = {}           # type_id -> Array[CarController]
var _types: Array[Dictionary] = []
var _branches: Dictionary = {}       # road index -> Array[{j, minor, minor_end}]
var _end_links: Dictionary = {}      # "road:end" -> {road, index}
var _rng := RandomNumberGenerator.new()
var _spawn_timer: float = 0.0
var _horn_player: AudioStreamPlayer3D
var stats := {"spawned": 0, "despawned": 0, "physics": 0, "crashes": 0}
var _tick: int = 0
var _build_cd: float = 0.0
var _rx: Array[PackedFloat32Array] = []
var _ry: Array[PackedFloat32Array] = []
var _rz: Array[PackedFloat32Array] = []
var _rb: Array[PackedFloat32Array] = []
var _rclosed: Array[bool] = []


func _ready() -> void:
	_rng.seed = 4242
	density = float(Game.settings.get("traffic_density", 0.6))
	call_deferred("_late_init")


func _late_init() -> void:
	world = Game.world
	if world == null or not ("data" in world):
		set_process(false)
		set_physics_process(false)
		return
	data = world.get("data")
	_cache_roads()
	_build_links()
	_types = TrafficTypes.all()
	_prewarm()
	_horn_player = AudioStreamPlayer3D.new()
	_horn_player.stream = SoundBank.get_stream("horn")
	_horn_player.max_distance = 140.0
	_horn_player.unit_size = 8.0
	add_child(_horn_player)


func _prewarm() -> void:
	## build pooled vehicles up front so spawning never instantiates scenes mid-drive
	var counts := {"t_compact": 15, "t_van": 6, "t_lorry": 5, "t_bus": 3, "t_tractor": 5, "t_pickup": 8}
	for t in _types:
		if not ResourceLoader.exists(String(t["def"].model_path)):
			continue
		# keep each new one active until the type is done, otherwise _spawn would reuse it
		var made: Array[Vehicle] = []
		for i in counts.get(t["id"], 3):
			_spawn(t, 0, 10.0, 1, 0)
			made.append(vehicles[vehicles.size() - 1])
		for v in made:
			_despawn(v)
	stats["spawned"] = 0
	stats["despawned"] = 0


func set_density(d: float) -> void:
	density = clampf(d, 0.0, 1.0)


func physics_points() -> Array:
	var pts := []
	for v in vehicles:
		if v.mode != Mode.KINEMATIC and v.node != null:
			pts.append(v.node.global_position)
	return pts


# ------------------------------------------------------------------------------------------------
func _cache_roads() -> void:
	for r in data.roads:
		_rx.append(r["x"])
		_ry.append(r["y"])
		_rz.append(r["z"])
		_rb.append(r["bank"])
		_rclosed.append(bool(r["closed"]))


func _build_links() -> void:
	for ri in data.roads.size():
		var r: Dictionary = data.roads[ri]
		for j in r["joins"]:
			var major: int = int(j["road"])
			var idx: int = int(j["index"])
			_end_links["%d:%d" % [ri, int(j["end"])]] = {"road": major, "index": idx}
			if not _branches.has(major):
				_branches[major] = []
			(_branches[major] as Array).append({"j": idx, "minor": ri, "minor_end": int(j["end"])})


func _road_n(ri: int) -> int:
	return _rx[ri].size()


func _lane_offsets(ri: int) -> Array:
	## lateral offsets (to the right of the travel direction) of usable lanes per direction
	var r: Dictionary = data.roads[ri]
	var lw: float = r["lane_width"]
	match String(r["class"]):
		"highway":
			var m := float(r["median"]) * 0.5
			return [m + lw * 1.5, m + lw * 0.5]
		"gravel", "dirt":
			return [1.35]
		_:
			return [lw * 0.5]


func _sample(ri: int, s: float) -> Array:
	## position and forward direction at fractional sample s on road ri
	var xs := _rx[ri]
	var ys := _ry[ri]
	var zs := _rz[ri]
	var n := xs.size()
	var closed := _rclosed[ri]
	var i0 := int(floor(s))
	var t := s - float(i0)
	var a := posmod(i0, n) if closed else clampi(i0, 0, n - 1)
	var b := posmod(i0 + 1, n) if closed else clampi(i0 + 1, 0, n - 1)
	var pa := Vector3(xs[a], ys[a], zs[a])
	var pb := Vector3(xs[b], ys[b], zs[b])
	var fwd := pb - pa
	if fwd.length_squared() < 1e-6:
		var c := posmod(i0 - 1, n) if closed else clampi(i0 - 1, 0, n - 1)
		fwd = pa - Vector3(xs[c], ys[c], zs[c])
	return [pa.lerp(pb, t), fwd.normalized(), _rb[ri][a]]


func lane_transform(v: Vehicle) -> Transform3D:
	var smp := _sample(v.road, v.s)
	var p: Vector3 = smp[0]
	var fwd: Vector3 = smp[1] * float(v.dir)
	var flat := Vector3(fwd.x, 0, fwd.z).normalized()
	var right := flat.cross(Vector3.UP).normalized()
	var bank: float = smp[2] * float(v.dir)
	var pos := p + right * v.offset + Vector3.UP * (-v.offset * tan(bank) + 0.02)
	var up := (Vector3.UP + right * tan(bank)).normalized()
	var b := Basis.looking_at(fwd, up)
	return Transform3D(b, pos + v.visual_off)


# ------------------------------------------------------------------------------------------------
func _physics_process(delta: float) -> void:
	Game.prof_begin("traffic")
	if data == null:
		Game.prof_end("traffic")
		return
	var player := Game.player_car
	if player == null or not is_instance_valid(player):
		Game.prof_end("traffic")
		return
	var ppos := player.global_position
	var cam := get_viewport().get_camera_3d()
	density = float(Game.settings.get("traffic_density", density))
	# spawning
	_spawn_timer -= delta
	_build_cd -= delta
	var target := int(round(_target_count(ppos)))
	if _spawn_timer <= 0.0:
		_spawn_timer = 0.15
		if _active_count() < target:
			Game.prof_begin("traffic_spawn")
			_try_spawn(ppos, cam)
			Game.prof_end("traffic_spawn")
	# per-vehicle update (far vehicles are stepped at a quarter rate, staggered)
	_tick += 1
	var active := _active_count()
	var vi := 0
	for v in vehicles:
		vi += 1
		if not v.active:
			continue
		var pos := v.node.global_position
		var d := pos.distance_to(ppos)
		if d > DESPAWN_RADIUS or (active > target + 3 and d > SPAWN_MAX and not _visible(cam, pos)):
			_despawn(v)
			active -= 1
			continue
		match v.mode:
			Mode.KINEMATIC:
				if d < PHYSICS_RADIUS:
					Game.prof_begin("traffic_todyn")
					_to_dynamic(v)
					Game.prof_end("traffic_todyn")
				elif d > 220.0:
					v.pending_dt += delta
					if (_tick + vi) % 4 == 0:
						_update_kinematic(v, v.pending_dt, player, false)
						v.pending_dt = 0.0
				else:
					v.pending_dt = 0.0
					_update_kinematic(v, delta, player, true)
			Mode.DYNAMIC:
				if d > PHYSICS_EXIT and _near_lane(v):
					_to_kinematic(v)
				else:
					_update_dynamic(v, delta, player)
			Mode.CRASHED:
				_update_crashed(v, delta, cam, d)
	Game.prof_end("traffic")


func _target_count(ppos: Vector3) -> float:
	var hour := 12.0
	if Game.environment != null:
		hour = (Game.environment as EnvironmentController).time_of_day
	var tod := 1.0
	if hour < 5.5 or hour > 23.0:
		tod = 0.35
	elif hour < 7.0 or hour > 21.0:
		tod = 0.6
	var region := data.region_index(ppos.x, ppos.z)
	var rmul: float = [0.8, 1.0, 0.65, 0.75][region]
	return clampf(density * 38.0 * tod * rmul, 0.0, MAX_VEHICLES)


func _active_count() -> int:
	var c := 0
	for v in vehicles:
		if v.active:
			c += 1
	return c


func _visible(cam: Camera3D, p: Vector3) -> bool:
	if cam == null:
		return false
	if cam.global_position.distance_to(p) > 900.0:
		return false
	return cam.is_position_in_frustum(p + Vector3.UP)


# ------------------------------------------------------------------------------------------------
func _try_spawn(ppos: Vector3, cam: Camera3D) -> void:
	# half of the spawns go onto the road the player is driving on (ahead or behind) so the
	# road you are on feels alive; the rest are scattered over nearby roads
	Game.prof_begin("traffic_nearest")
	var own := data.nearest_road(ppos.x, ppos.z, 2)
	Game.prof_end("traffic_nearest")
	for attempt in 6:
		var ri: int
		var i: int
		if not own.is_empty() and _rng.randf() < 0.55:
			ri = own["road"]
			var n0 := _road_n(ri)
			var smin := SPAWN_MIN if not Game.qa_args.has("traffic_near") else 50.0
			var off := int(_rng.randf_range(smin, SPAWN_MAX * 0.8) / STEP) * (1 if _rng.randf() < 0.6 else -1)
			i = int(own["i"]) + off
			if data.roads[ri]["closed"]:
				i = posmod(i, n0)
			elif i < 0 or i >= n0:
				continue
		else:
			var a := _rng.randf() * TAU
			var dist := _rng.randf_range(SPAWN_MIN, SPAWN_MAX)
			var q := ppos + Vector3(cos(a), 0, sin(a)) * dist
			var nr := data.nearest_road(q.x, q.z, 3)
			if nr.is_empty() or float(nr["d"]) > 60.0:
				continue
			ri = nr["road"]
			i = nr["i"]
		var r: Dictionary = data.roads[ri]
		var n := _road_n(ri)
		if not r["closed"] and (i < 12 or i > n - 12):
			continue
		var flags: PackedInt32Array = r["flags"]
		if flags[i] & WorldData.F_TUNNEL:
			continue
		var p := data.road_point(ri, i)
		var near_ok := Game.qa_args.has("traffic_near")
		if p.distance_to(ppos) < (SPAWN_MIN * 0.9 if not near_ok else 45.0):
			continue
		if _visible(cam, p) and p.distance_to(ppos) < 420.0 and not near_ok:
			continue
		var type := _pick_type(String(r["class"]))
		if type.is_empty():
			continue
		var dir := 1 if _rng.randf() < 0.5 else -1
		var lanes := _lane_offsets(ri)
		var lane := _rng.randi_range(0, lanes.size() - 1)
		if not _lane_free(ri, float(i), dir, lane, 35.0):
			continue
		_spawn(type, ri, float(i), dir, lane)
		return


func _has_free(type_id: String) -> bool:
	for v in vehicles:
		if not v.active and v.type_id == type_id:
			return true
	return false


func _pick_type(cls: String) -> Dictionary:
	## weighted by road class; only pooled (pre-built) vehicles are used while driving, a new
	## one is built at most every few seconds when the pool of that type is exhausted
	var total := 0.0
	var options: Array[Dictionary] = []
	for pass_i in 2:
		if pass_i == 1 and (_build_cd > 0.0 or vehicles.size() >= MAX_VEHICLES):
			break
		for t in _types:
			var w: float = (t["weights"] as Dictionary).get(cls, 0.0)
			if w > 0.0 and ResourceLoader.exists(String(t["def"].model_path)) and (pass_i == 1 or _has_free(t["id"])):
				options.append(t)
				total += w
		if not options.is_empty():
			break
	if options.is_empty():
		return {}
	var pick := _rng.randf() * total
	for t in options:
		pick -= float((t["weights"] as Dictionary).get(cls, 0.0))
		if pick <= 0.0:
			return t
	return options[0]


func _lane_free(ri: int, s: float, dir: int, lane: int, gap: float) -> bool:
	for v in vehicles:
		if v.active and v.road == ri and v.dir == dir and v.lane == lane and absf(v.s - s) * STEP < gap:
			return false
	return true


func _spawn(t: Dictionary, ri: int, s: float, dir: int, lane: int) -> void:
	var v: Vehicle = null
	for existing in vehicles:
		if not existing.active and existing.type_id == t["id"]:
			v = existing
			break
	if v == null:
		Game.prof_begin("traffic_build")
		_build_cd = 4.0
		v = Vehicle.new()
		v.type_id = t["id"]
		var def: CarDefinition = t["def"]
		var palette: Array = t["colors"]
		var col: Color = palette[_rng.randi_range(0, palette.size() - 1)]
		v.node = CarFactory.build(def, col, CarDefinition.Finish.GLOSS if _rng.randf() < 0.6 else CarDefinition.Finish.METALLIC)
		v.node.name = "Traffic_%s_%d" % [t["id"], vehicles.size()]
		v.node.collision_layer = CarController.LAYER_TRAFFIC
		v.node.collision_mask = CarController.LAYER_WORLD | CarController.LAYER_PLAYER | CarController.LAYER_TRAFFIC
		v.node.control_mode = CarController.ControlMode.AI
		v.node.simplified = true
		v.node.assist_esc = true
		v.node.assist_tcs = true
		v.node.contact_monitor = true
		v.node.max_contacts_reported = 4
		v.node.body_entered.connect(_on_contact.bind(v))
		var lights := CarLights.new()
		lights.name = "Lights"
		v.node.add_child(lights)
		lights.setup(v.node, false)
		var snd := AudioStreamPlayer3D.new()
		snd.name = "Engine"
		snd.stream = SoundBank.get_stream("traffic_engine")
		snd.max_distance = 90.0
		snd.unit_size = 6.0
		snd.volume_db = -8.0
		v.node.add_child(snd)
		add_child(v.node)
		vehicles.append(v)
		v.length = float(t["length"])
		Game.prof_end("traffic_build")
	v.road = ri
	v.s = s
	v.dir = dir
	v.lane = lane
	var lanes := _lane_offsets(ri)
	v.offset = lanes[clampi(lane, 0, lanes.size() - 1)]
	v.target_offset = v.offset
	v.max_kmh = float(t["max_kmh"])
	v.v0_factor = _rng.randf_range(0.82, 1.05)
	v.speed = _desired_speed(v) * 0.8
	v.mode = Mode.KINEMATIC
	v.crash_timer = 0.0
	v.turn_plan = {}
	v.visual_off = Vector3.ZERO
	v.active = true
	v.stuck = 0.0
	v.node.visible = true
	v.node.process_mode = Node.PROCESS_MODE_INHERIT
	v.node.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	v.node.freeze = true
	v.node.global_transform = lane_transform(v)
	v.node.reset_physics_interpolation()
	var snd2 := v.node.get_node_or_null("Engine") as AudioStreamPlayer3D
	if snd2 != null:
		snd2.play()
	stats["spawned"] += 1


func _despawn(v: Vehicle) -> void:
	v.active = false
	v.node.freeze = true
	v.node.visible = false
	v.node.global_position = Vector3(0, -500, 0)
	v.node.process_mode = Node.PROCESS_MODE_DISABLED
	var snd := v.node.get_node_or_null("Engine") as AudioStreamPlayer3D
	if snd != null:
		snd.stop()
	stats["despawned"] += 1


# ------------------------------------------------------------------------------------------------
func _desired_speed(v: Vehicle) -> float:
	var r: Dictionary = data.roads[v.road]
	var limit := minf(float(r["speed"]), v.max_kmh) / 3.6 * v.v0_factor
	if (r["flags"] as PackedInt32Array)[clampi(int(v.s), 0, _road_n(v.road) - 1)] & WorldData.F_VILLAGE:
		limit = minf(limit, 40.0 / 3.6)
	# curvature ahead
	var vmax := limit
	for k in [4, 10, 18, 28]:
		var kap := _curv(v.road, v.s + float(k * v.dir))
		vmax = minf(vmax, sqrt(2.6 / maxf(kap, 1e-4)) + float(k) * 0.15)
	return maxf(vmax, 4.0)


func _curv(ri: int, s: float) -> float:
	var a: Vector3 = _sample(ri, s - 4.0)[0]
	var b: Vector3 = _sample(ri, s)[0]
	var c: Vector3 = _sample(ri, s + 4.0)[0]
	var d1 := Vector2(b.x - a.x, b.z - a.z)
	var d2 := Vector2(c.x - b.x, c.z - b.z)
	return absf(d1.angle_to(d2)) / maxf((d1.length() + d2.length()) * 0.5, 1.0)


func _leader_gap(v: Vehicle, player: CarController) -> Array:
	## returns [gap metres, leader speed] for the closest obstacle ahead in this lane
	var best_gap := 1e6
	var lead_speed := 0.0
	for o in vehicles:
		if o == v or not o.active or o.road != v.road or o.dir != v.dir:
			continue
		if absf(o.offset - v.offset) > 1.6:
			continue
		var ds := (o.s - v.s) * float(v.dir) * STEP
		if _is_closed(v.road):
			var total := float(_road_n(v.road)) * STEP
			ds = fposmod(ds, total)
		if ds > 0.0 and ds < best_gap:
			best_gap = ds - (o.length + v.length) * 0.5
			lead_speed = o.speed if o.mode == Mode.KINEMATIC else o.node.linear_velocity.length()
			if o.mode == Mode.CRASHED:
				lead_speed = 0.0
	# the player car as an obstacle in this lane
	var my := v.node.global_transform
	var rel := my.affine_inverse() * player.global_position
	if rel.z < -1.0 and rel.z > -130.0 and absf(rel.x) < 2.4:
		var g := -rel.z - (v.length + 4.3) * 0.5
		if g < best_gap:
			best_gap = g
			lead_speed = maxf(player.linear_velocity.dot(-my.basis.z), 0.0)
	# give way at the end of a minor road
	if not _is_closed(v.road):
		var n := _road_n(v.road)
		var to_end := (float(n - 1) - v.s) * STEP if v.dir > 0 else v.s * STEP
		var key := "%d:%d" % [v.road, 1 if v.dir > 0 else 0]
		if _end_links.has(key) and to_end < 45.0:
			var link: Dictionary = _end_links[key]
			if not _junction_clear(link["road"], int(link["index"]), player):
				var g2 := to_end - 4.0
				if g2 < best_gap:
					best_gap = maxf(g2, 0.1)
					lead_speed = 0.0
	return [best_gap, lead_speed]


func _is_closed(ri: int) -> bool:
	return _rclosed[ri]


func _junction_clear(major: int, j: int, player: CarController) -> bool:
	for o in vehicles:
		if not o.active or o.road != major:
			continue
		var ds := (float(j) - o.s) * float(o.dir) * STEP
		if ds > -8.0 and ds < 55.0:
			return false
	var jp := data.road_point(major, j)
	if player.global_position.distance_to(jp) < 45.0 and player.linear_velocity.length() > 3.0:
		return false
	return true


func _idm(v: Vehicle, delta: float, player: CarController) -> float:
	var v0 := _desired_speed(v)
	var lg := _leader_gap(v, player)
	var gap: float = lg[0]
	var lead: float = lg[1]
	var a_max := 1.6
	var b := 2.6
	var s0 := 3.0
	var T := 1.3
	var dv := v.speed - lead
	var s_star := s0 + v.speed * T + v.speed * dv / (2.0 * sqrt(a_max * b))
	var acc := a_max * (1.0 - pow(v.speed / maxf(v0, 0.5), 4.0))
	if gap < 1e5:
		acc -= a_max * pow(maxf(s_star, 0.0) / maxf(gap, 0.3), 2.0)
	acc = clampf(acc, -8.0, a_max)
	# honk at a stationary player blocking the lane
	if gap < 12.0 and lead < 0.5 and v.speed < 1.0:
		v.horn_timer += delta
		if v.horn_timer > 3.0:
			v.horn_timer = -4.0
			_honk(v)
	return acc


func _honk(v: Vehicle) -> void:
	_horn_player.global_position = v.node.global_position
	_horn_player.pitch_scale = _rng.randf_range(0.85, 1.15)
	_horn_player.play()
	var lm: Dictionary = v.node.get_meta("light_materials", {})
	var head: StandardMaterial3D = lm.get("head")
	if head != null:
		head.emission_energy_multiplier = 9.0


# ------------------------------------------------------------------------------------------------
func _advance(v: Vehicle, ds_samples: float) -> void:
	var n := _road_n(v.road)
	var old_s := v.s
	v.s += ds_samples * float(v.dir)
	if _is_closed(v.road):
		v.s = fposmod(v.s, float(n))
	# branch onto a minor road at a junction on this road
	if _branches.has(v.road):
		for br in _branches[v.road]:
			var j := float(br["j"])
			var crossed := (old_s < j and v.s >= j) if v.dir > 0 else (old_s > j and v.s <= j)
			if crossed and not v.turn_plan.is_empty() and v.turn_plan.get("j", -1) == int(j) and v.turn_plan.get("minor", -1) == int(br["minor"]):
				_switch_road(v, int(br["minor"]), 0.0 if int(br["minor_end"]) == 0 else float(_road_n(int(br["minor"])) - 1), 1 if int(br["minor_end"]) == 0 else -1)
				v.turn_plan = {}
				return
	# plan a turn ahead with a modest probability
	if v.turn_plan.is_empty() and _branches.has(v.road) and _rng.randf() < 0.02:
		for br in _branches[v.road]:
			var dj := (float(br["j"]) - v.s) * float(v.dir)
			if dj > 10.0 and dj < 40.0 and data.roads[int(br["minor"])]["class"] != "dirt" or (dj > 10.0 and dj < 40.0 and v.type_id == "tractor"):
				if _rng.randf() < 0.35:
					v.turn_plan = {"j": int(br["j"]), "minor": int(br["minor"])}
				break
	# end of an open road
	if not _is_closed(v.road) and (v.s >= float(n - 1) or v.s <= 0.0):
		var end := 1 if v.s >= float(n - 1) else 0
		var key := "%d:%d" % [v.road, end]
		if _end_links.has(key):
			var link: Dictionary = _end_links[key]
			var major: int = link["road"]
			var dirm := 1 if _rng.randf() < 0.5 else -1
			_switch_road(v, major, float(link["index"]), dirm)
		else:
			# dead end: turn around
			v.dir = -v.dir
			v.s = clampf(v.s, 0.0, float(n - 1))
			v.visual_off = Vector3.ZERO


func _switch_road(v: Vehicle, ri: int, s: float, dir: int) -> void:
	var before := v.node.global_transform.origin
	v.road = ri
	v.s = s
	v.dir = dir
	var lanes := _lane_offsets(ri)
	v.lane = lanes.size() - 1
	v.offset = lanes[v.lane]
	v.target_offset = v.offset
	var after := lane_transform(v).origin - v.visual_off
	v.visual_off = before - after


func _update_kinematic(v: Vehicle, delta: float, player: CarController, near: bool = true) -> void:
	v.think -= delta
	if v.think <= 0.0:
		v.think = 0.05 + _rng.randf() * 0.02
		v.acc = _idm(v, 0.06, player)
		_lane_change(v, 0.06, player)
	v.speed = maxf(v.speed + v.acc * delta, 0.0)
	v.offset = move_toward(v.offset, v.target_offset, delta * 1.2)
	_advance(v, v.speed * delta / STEP)
	v.visual_off = v.visual_off.lerp(Vector3.ZERO, 1.0 - exp(-delta * 1.8))
	var t := lane_transform(v)
	v.node.global_transform = t
	if near:
		v.node.kinematic_visuals(v.speed, delta)
		var snd := v.node.get_node_or_null("Engine") as AudioStreamPlayer3D
		if snd != null:
			snd.pitch_scale = 0.6 + v.speed / 25.0


func _lane_change(v: Vehicle, delta: float, player: CarController) -> void:
	var lanes := _lane_offsets(v.road)
	if lanes.size() < 2:
		return
	v.lane_change_cd -= delta
	if v.lane_change_cd > 0.0:
		return
	v.lane_change_cd = 2.0
	var lg := _leader_gap(v, player)
	var other := 1 - v.lane
	if float(lg[0]) < 45.0 and float(lg[1]) < v.speed * 0.85:
		if _lane_free(v.road, v.s, v.dir, other, 40.0):
			v.lane = other
			v.target_offset = lanes[other]
	elif v.lane == 1 and _lane_free(v.road, v.s, v.dir, 0, 60.0) and _rng.randf() < 0.3:
		v.lane = 0
		v.target_offset = lanes[0]


# ------------------------------------------------------------------------------------------------
func _to_dynamic(v: Vehicle) -> void:
	var t := lane_transform(v)
	v.node.freeze = false
	v.node.global_transform = t
	v.node.linear_velocity = -t.basis.z * v.speed
	v.node.angular_velocity = Vector3.ZERO
	for w in v.node.wheels:
		w.omega = v.speed / w.radius
	v.node.gear = 1
	v.mode = Mode.DYNAMIC
	stats["physics"] += 1


func _to_kinematic(v: Vehicle) -> void:
	var nr := _nearest_on_road(v)
	v.s = nr
	v.speed = v.node.linear_velocity.length()
	v.visual_off = v.node.global_position - (lane_transform(v).origin - v.visual_off)
	v.node.freeze = true
	v.mode = Mode.KINEMATIC


func _nearest_on_road(v: Vehicle) -> float:
	var p := v.node.global_position
	var best := v.s
	var bd := 1e18
	for k in range(-12, 13):
		var s := v.s + float(k)
		var q: Vector3 = _sample(v.road, s)[0]
		var d := Vector2(q.x - p.x, q.z - p.z).length_squared()
		if d < bd:
			bd = d
			best = s
	return best


func _near_lane(v: Vehicle) -> bool:
	var s := _nearest_on_road(v)
	var save := v.s
	v.s = s
	var lt := lane_transform(v)
	v.s = save
	return lt.origin.distance_to(v.node.global_position) < 2.5 and v.node.global_transform.basis.y.y > 0.9


func _update_dynamic(v: Vehicle, delta: float, player: CarController) -> void:
	var car := v.node
	# keep lane bookkeeping in sync with the physical car
	v.s = _nearest_on_road(v)
	var vel := car.linear_velocity.length()
	v.speed = vel
	var acc := _idm(v, delta, player)
	var target_speed := maxf(vel + acc * 1.2, 0.0)
	_advance(v, 0.0)
	v.offset = move_toward(v.offset, v.target_offset, delta * 1.2)
	# pure pursuit on the lane
	var look := 6.0 + vel * 0.45
	var save_s := v.s
	v.s += float(v.dir) * look / STEP
	var tgt := lane_transform(v).origin - v.visual_off
	v.s = save_s
	var local := car.global_transform.affine_inverse() * tgt
	var alpha := atan2(local.x, -local.z)
	var steer_rad := atan(2.0 * 2.7 * sin(alpha) / maxf(look, 1.0))
	var def := car.definition
	var lock := lerpf(def.steer_lock_deg, def.steer_high_speed_deg, pow(clampf(absf(car.forward_speed) / 55.0, 0.0, 1.0), 0.75))
	car.input_steer = clampf(rad_to_deg(steer_rad) / lock, -1.0, 1.0)
	var err := target_speed - vel
	car.input_throttle = clampf(err * 0.5 + 0.1, 0.0, 0.85) if err > -0.3 else 0.0
	car.input_brake = clampf(-err * 0.35, 0.0, 1.0) if err < -0.3 else 0.0
	if target_speed < 0.3 and vel < 1.0:
		car.input_brake = 1.0
	v.visual_off = v.visual_off.lerp(Vector3.ZERO, 1.0 - exp(-delta * 2.0))
	# crash detection: big deviation from the lane or tipped over
	var lt := lane_transform(v)
	if lt.origin.distance_to(car.global_position) > 6.0 or car.global_transform.basis.y.y < 0.6:
		_crash(v)
	elif vel < 0.5 and car.input_throttle > 0.3:
		v.stuck += delta
		if v.stuck > 5.0:
			_crash(v)
	else:
		v.stuck = 0.0


func _on_contact(body: Node, v: Vehicle) -> void:
	if body == Game.player_car and v.mode == Mode.DYNAMIC:
		var rel := (Game.player_car.linear_velocity - v.node.linear_velocity).length()
		if rel > 6.0:
			_crash(v)
			_honk(v)


func _crash(v: Vehicle) -> void:
	if v.mode == Mode.CRASHED:
		return
	v.mode = Mode.CRASHED
	v.crash_timer = 0.0
	v.node.input_throttle = 0.0
	v.node.input_brake = 1.0
	v.node.input_steer = 0.0
	stats["crashes"] += 1


func _update_crashed(v: Vehicle, delta: float, cam: Camera3D, d: float) -> void:
	v.crash_timer += delta
	var car := v.node
	car.input_throttle = 0.0
	car.input_brake = 1.0
	# hazard flashing
	var lm: Dictionary = car.get_meta("light_materials", {})
	var tail: StandardMaterial3D = lm.get("tail")
	if tail != null:
		tail.emission_energy_multiplier = 4.0 if fmod(v.crash_timer, 0.8) < 0.4 else 0.4
	if v.crash_timer > 6.0:
		if not _visible(cam, car.global_position) or d > 160.0:
			_despawn(v)
		elif v.crash_timer > 12.0 and _near_lane(v) and car.linear_velocity.length() < 0.5:
			# recover onto the lane and drive on
			v.mode = Mode.DYNAMIC
			v.stuck = 0.0
