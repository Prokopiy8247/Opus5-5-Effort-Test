class_name TrafficManager
extends Node3D
## Civilian traffic. Vehicles follow lanes derived from the road splines (right-hand traffic),
## keep distance with the Intelligent Driver Model (other cars and the player are leaders),
## slow for curves, give way where a side road joins, and turn at junctions.
## Pooled, spawned/despawned in a ring around the player; physics only near the player.

const TYPES := {
	"city": {"path": "res://assets/imported/traffic/traffic_city.glb", "len": 3.6, "speed": 1.0, "weight": 3.0},
	"van": {"path": "res://assets/imported/traffic/traffic_van.glb", "len": 5.2, "speed": 0.95, "weight": 2.0},
	"lorry": {"path": "res://assets/imported/traffic/traffic_lorry.glb", "len": 7.3, "speed": 0.82, "weight": 1.2},
	"coach": {"path": "res://assets/imported/traffic/traffic_coach.glb", "len": 11.1, "speed": 0.85, "weight": 0.6},
	"pickup": {"path": "res://assets/imported/traffic/traffic_pickup.glb", "len": 5.0, "speed": 0.95, "weight": 1.8},
	"tractor": {"path": "res://assets/imported/traffic/traffic_tractor.glb", "len": 3.6, "speed": 0.38, "weight": 0.7},
}
const PALETTE := [Color(0.85, 0.85, 0.86), Color(0.1, 0.1, 0.11), Color(0.55, 0.06, 0.05), Color(0.12, 0.25, 0.55),
	Color(0.6, 0.62, 0.64), Color(0.2, 0.35, 0.22), Color(0.85, 0.7, 0.3), Color(0.35, 0.2, 0.12), Color(0.95, 0.95, 0.95),
	Color(0.3, 0.45, 0.65)]
const MAX_CARS := 34
const SPAWN_MIN := 160.0
const SPAWN_MAX := 650.0
const DESPAWN := 820.0
const PHYS_RANGE := 140.0

enum State { DRIVE, CRASHED, STOPPED }

class TCar:
	var node: RigidBody3D
	var type_key := ""
	var length := 4.0
	var road: WorldData.Road
	var dir := 1
	var lane := 0
	var u := 0.0
	var speed := 0.0
	var accel := 0.0
	var pref := 1.0
	var state := 0
	var timer := 0.0
	var wheels: Array[Node3D] = []
	var wheel_spin := 0.0
	var lights: Array[StandardMaterial3D] = []
	var tails: Array[StandardMaterial3D] = []
	var leader_gap := 999.0
	var leader_speed := 0.0
	var waiting := false
	var last_junction := -999
	var target_xf := Transform3D()
	var shape: CollisionShape3D
	var meshes: Array[MeshInstance3D] = []
	var shadows := true
	var active := false
	var honk_cd := 0.0

var data: WorldData
var _pool := {}           # type -> Array[TCar]
var cars: Array[TCar] = []
var _junctions_on := {}   # road index -> Array of [index_on_road, branch_road, branch_end_index]
var _curve_speed := {}    # road index -> PackedFloat32Array (m/s)
var _road_weights := PackedFloat32Array()
var _tick := 0
var _player: Car
var rng := RandomNumberGenerator.new()
var stats := {"spawned": 0, "despawned": 0, "crashes": 0}
var horn_player: AudioStreamPlayer3D


func setup(world_data: WorldData) -> void:
	data = world_data
	rng.seed = 4242
	for road in data.roads:
		_junctions_on[road.index] = []
		_curve_speed[road.index] = _curve_speeds(road)
	for road in data.roads:
		for j in road.junctions:
			var main := data.road_by_id(j.road)
			if main:
				(_junctions_on[main.index] as Array).append([int(j.road_i), road, int(j.self_i)])
	var acc := 0.0
	for road in data.roads:
		var w := road.length * (2.0 if road.cls in ["highway", "regional"] else (1.0 if road.cls in ["lane", "mountain"] else 0.45))
		acc += w
		_road_weights.append(acc)
	# pre-instantiate the pool so spawning never hitches
	for k in TYPES:
		_pool[k] = []
		var n := 7 if k in ["city", "van", "pickup"] else 4
		for i in n:
			(_pool[k] as Array).append(_make(k))
	Game.car_changed.connect(_on_car_changed)


func _curve_speeds(road: WorldData.Road) -> PackedFloat32Array:
	var n := road.pts.size()
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var a := road.pts[maxi(i - 4, 0) if not road.closed else posmod(i - 4, n)]
		var b := road.pts[i]
		var c := road.pts[mini(i + 4, n - 1) if not road.closed else posmod(i + 4, n)]
		var d1 := Vector2(b.x - a.x, b.z - a.z)
		var d2 := Vector2(c.x - b.x, c.z - b.z)
		var ang := absf(d1.angle_to(d2))
		var len := (d1.length() + d2.length()) * 0.5
		var curvature := ang / maxf(len, 0.1)
		out[i] = clampf(sqrt(2.6 / maxf(curvature, 0.0001)), 6.0, 40.0)
	return out


func _make(type_key: String) -> TCar:
	var t := TCar.new()
	t.type_key = type_key
	t.length = TYPES[type_key].len
	var body := RigidBody3D.new()
	body.name = "Traffic_" + type_key
	body.freeze = true
	body.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	body.collision_layer = Car.LAYER_TRAFFIC
	body.collision_mask = Car.LAYER_WORLD | Car.LAYER_PLAYER | Car.LAYER_TRAFFIC
	body.mass = 1400.0 if type_key in ["city", "pickup", "van"] else (5000.0 if type_key == "tractor" else 9000.0)
	body.set_meta("traffic", true)
	body.continuous_cd = true
	var model := (load(TYPES[type_key].path) as PackedScene).instantiate() as Node3D
	body.add_child(model)
	var aabb := AABB()
	var first := true
	for mi in _meshes(model):
		var xf := _rel(mi, model)
		var a := xf * mi.get_aabb()
		aabb = a if first else aabb.merge(a)
		first = false
		mi.visibility_range_end = 650.0
		mi.visibility_range_end_margin = 30.0
		mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		t.meshes.append(mi)
		var nm := String(mi.name)
		if nm.begins_with("Wheel_"):
			t.wheels.append(mi)
		for si in mi.mesh.get_surface_count():
			var m := mi.mesh.surface_get_material(si)
			if m == null:
				continue
			var mn := String(m.resource_name)
			if mn.begins_with("M_Paint") and type_key != "tractor":
				var pm := StandardMaterial3D.new()
				pm.albedo_color = PALETTE[rng.randi() % PALETTE.size()]
				pm.metallic = 0.4
				pm.roughness = 0.35
				pm.clearcoat_enabled = true
				mi.set_surface_override_material(si, pm)
			elif mn == "M_Glass":
				var g := StandardMaterial3D.new()
				g.albedo_color = Color(0.05, 0.07, 0.09, 0.75)
				g.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				g.roughness = 0.05
				mi.set_surface_override_material(si, g)
		if nm.begins_with("Lights_Head"):
			var lm := StandardMaterial3D.new()
			lm.albedo_color = Color(0.85, 0.85, 0.8)
			lm.emission_enabled = true
			lm.emission = Color(1.0, 0.92, 0.75)
			mi.material_override = lm
			t.lights.append(lm)
		elif nm.begins_with("Lights_Tail") or nm.begins_with("Lights_Brake"):
			var tm := StandardMaterial3D.new()
			tm.albedo_color = Color(0.6, 0.03, 0.03)
			tm.emission_enabled = true
			tm.emission = Color(1.0, 0.05, 0.03)
			mi.material_override = tm
			t.tails.append(tm)
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(aabb.size.x * 0.92, aabb.size.y * 0.8, aabb.size.z * 0.96)
	cs.shape = box
	cs.position = aabb.get_center() + Vector3(0, aabb.size.y * 0.05, 0)
	body.add_child(cs)
	t.shape = cs
	t.node = body
	body.visible = false
	cs.disabled = true
	add_child(body)
	body.set_meta("tcar", t)
	return t


func _meshes(n: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	var st: Array[Node] = [n]
	while not st.is_empty():
		var c: Node = st.pop_back()
		if c is MeshInstance3D:
			out.append(c)
		st.append_array(c.get_children())
	return out


func _rel(n: Node3D, anc: Node3D) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var c: Node = n
	while c != null and c != anc:
		if c is Node3D:
			xf = (c as Node3D).transform * xf
		c = c.get_parent()
	return xf


func _on_car_changed(car: Node) -> void:
	_player = car as Car
	if _player and not _player.body_entered.is_connected(_on_player_hit):
		_player.body_entered.connect(_on_player_hit)


func _on_player_hit(body: Node) -> void:
	if body.has_meta("tcar"):
		var t: TCar = body.get_meta("tcar")
		if t.state == State.DRIVE:
			_crash(t)


func _crash(t: TCar) -> void:
	t.state = State.CRASHED
	t.timer = 0.0
	stats.crashes += 1
	var vel := _travel_dir(t) * t.speed
	t.node.freeze = false
	t.node.linear_velocity = vel
	t.speed = 0.0
	for l in t.lights:
		l.emission_energy_multiplier = 4.0
	t.honk_cd = 0.0
	_honk(t)


func _honk(t: TCar) -> void:
	if t.honk_cd > 0.0:
		return
	t.honk_cd = 6.0
	var a := get_node_or_null("/root/Main/Audio")
	if a and a.has_method("play_horn_at"):
		a.play_horn_at(t.node.global_position, t.type_key)


# ------------------------------------------------------------------ lane geometry
func _travel_dir(t: TCar) -> Vector3:
	return t.road.tangent(int(t.u)) * float(t.dir)


func _lane_offset(t: TCar) -> float:
	var road := t.road
	if road.lanes >= 4:
		var lw := road.width / 4.0
		return lw * (1.5 if t.lane == 0 else 0.5)
	return road.width * 0.25


func _pose(t: TCar) -> Transform3D:
	var road := t.road
	var n := road.pts.size()
	var u := t.u
	var i0 := int(floor(u))
	var f := u - i0
	var i1 := i0 + 1
	if road.closed:
		i0 = posmod(i0, n)
		i1 = posmod(i1, n)
	else:
		i0 = clampi(i0, 0, n - 1)
		i1 = clampi(i1, 0, n - 1)
	var p := road.pts[i0].lerp(road.pts[i1], f)
	var ahead := _sample(road, u + 1.0 * t.dir)
	var behind := _sample(road, u - 1.0 * t.dir)
	var fwd := (ahead - behind).normalized()
	var flat := Vector3(fwd.x, 0.0, fwd.z).normalized()
	var right := Vector3(-flat.z, 0.0, flat.x)
	var pos := p + right * _lane_offset(t) + Vector3.UP * 0.02
	var basis := Basis.looking_at(fwd, Vector3.UP)
	return Transform3D(basis, pos)


func _sample(road: WorldData.Road, u: float) -> Vector3:
	var n := road.pts.size()
	if road.closed:
		u = fposmod(u, n - 1)
	else:
		u = clampf(u, 0.0, n - 1.001)
	var i := int(u)
	return road.pts[i].lerp(road.pts[mini(i + 1, n - 1)], u - i)


# ------------------------------------------------------------------ main loop
func _physics_process(delta: float) -> void:
	var _t0 := Time.get_ticks_usec()
	_physics_process_inner(delta)
	Game.prof_add("traffic", Time.get_ticks_usec() - _t0)


func _physics_process_inner(delta: float) -> void:
	if data == null:
		return
	if _player == null or not is_instance_valid(_player):
		_player = Game.player as Car
		if _player:
			_on_car_changed(_player)
		return
	_tick += 1
	var ppos := _player.global_position
	var cam := get_viewport().get_camera_3d()
	if _tick % 3 == 0:
		_think(ppos, 3.0 * delta)
	if _tick % 20 == 0:
		_manage_population(ppos, cam)
	var night := Game.time_of_day < 7.0 or Game.time_of_day > 19.2 or Game.weather_name in ["fog", "storm", "rain"]
	for t in cars:
		_integrate(t, delta, ppos, night)


func _think(ppos: Vector3, dt: float) -> void:
	# leaders: nearest vehicle (or the player) ahead within the lane corridor
	var pvel := _player.linear_velocity
	for t in cars:
		if t.state != State.DRIVE:
			continue
		var pos := t.node.global_position
		var fwd := _travel_dir(t)
		var best := 120.0
		var best_v := 30.0
		for o in cars:
			if o == t:
				continue
			var d := o.node.global_position - pos
			var along := d.dot(fwd)
			if along <= 0.0 or along > best:
				continue
			var lat := (d - fwd * along).length()
			if lat < 2.2:
				var gap := along - (t.length + o.length) * 0.5
				if gap < best:
					best = gap
					best_v = o.speed if o.state == State.DRIVE else 0.0
		var dp := ppos - pos
		var palong := dp.dot(fwd)
		if palong > 0.0 and palong < best + 6.0:
			var plat := (dp - fwd * palong).length()
			if plat < 2.4:
				var pgap := palong - t.length * 0.5 - 2.3
				if pgap < best:
					best = pgap
					best_v = maxf(pvel.dot(fwd), 0.0)
					# a stationary player blocking the lane gets a honk
					if pgap < 12.0 and pvel.length() < 1.0 and t.speed < 1.0:
						t.timer += dt
						if t.timer > 2.5:
							_honk(t)
							_flash(t)
		# give way when a side road ends on a main road
		t.waiting = false
		var stop_gap := _junction_stop_gap(t, ppos)
		if stop_gap < best:
			best = stop_gap
			best_v = 0.0
			t.waiting = true
		t.leader_gap = best
		t.leader_speed = best_v
		# IDM acceleration
		var v0 := _desired_speed(t)
		var a_max := 1.6
		var b := 2.8
		var s0 := 3.0
		var tg := 1.3
		var dv := t.speed - best_v
		var s_star := s0 + maxf(0.0, t.speed * tg + t.speed * dv / (2.0 * sqrt(a_max * b)))
		var acc := a_max * (1.0 - pow(t.speed / maxf(v0, 0.5), 4.0) - pow(s_star / maxf(best, 0.3), 2.0))
		t.accel = clampf(acc, -8.0, a_max)


func _flash(t: TCar) -> void:
	for l in t.lights:
		l.emission_energy_multiplier = 6.0


func _desired_speed(t: TCar) -> float:
	var road := t.road
	var limit := road.speed / 3.6 * t.pref * float(TYPES[t.type_key].speed)
	var cs: PackedFloat32Array = _curve_speed[road.index]
	var n := cs.size()
	var lowest := limit
	for k in range(0, 18, 3):
		var idx := int(t.u) + k * t.dir
		if road.closed:
			idx = posmod(idx, n)
		elif idx < 0 or idx >= n:
			break
		# allow braking distance: farther samples may be faster than the curve speed
		var v_allowed := sqrt(cs[idx] * cs[idx] + 2.0 * 2.5 * k * 4.0)
		lowest = minf(lowest, v_allowed)
	if Game.weather_grip < 0.9:
		lowest *= 0.85
	return lowest


func _junction_stop_gap(t: TCar, ppos: Vector3) -> float:
	var road := t.road
	var n := road.pts.size()
	for j in road.junctions:
		var end_i := int(j.self_i)
		var heading_to_end := (t.dir > 0 and end_i == n - 1) or (t.dir < 0 and end_i == 0)
		if not heading_to_end:
			continue
		var dist := absf(end_i - t.u) * 4.0
		if dist > 26.0:
			continue
		var main := data.road_by_id(j.road)
		var jp := main.pts[int(j.road_i)]
		# conflicting traffic: anything within 45 m of the junction on the main road
		var clear := true
		for o in cars:
			if o == t or o.road != main or o.state != State.DRIVE:
				continue
			if o.node.global_position.distance_to(jp) < 45.0 and o.speed > 1.0:
				clear = false
				break
		if clear and ppos.distance_to(jp) < 40.0 and _player.linear_velocity.length() > 2.0:
			clear = false
		if not clear:
			return maxf(dist - main.width * 0.5 - t.length * 0.5 - 1.0, 0.1)
	return 999.0


func _integrate(t: TCar, delta: float, ppos: Vector3, night: bool) -> void:
	var d := t.node.global_position.distance_to(ppos)
	t.honk_cd = maxf(t.honk_cd - delta, 0.0)
	if t.state == State.CRASHED:
		t.timer += delta
		if t.timer > 6.0 and t.node.linear_velocity.length() < 0.5:
			t.state = State.STOPPED
			t.node.freeze = true
		return
	if t.state == State.STOPPED:
		t.timer += delta
		for l in t.tails:
			l.emission_energy_multiplier = 3.0 if fmod(t.timer, 1.0) < 0.5 else 0.3
		return
	t.speed = maxf(t.speed + t.accel * delta, 0.0)
	var du := t.speed * delta / 4.0 * float(t.dir)
	t.u += du
	_advance_road(t)
	var xf := _pose(t)
	# smooth lane changes / turns
	var cur := t.node.global_transform
	var k := clampf(delta * 6.0, 0.0, 1.0)
	var smooth := Transform3D(cur.basis.slerp(xf.basis, k).orthonormalized(), cur.origin.lerp(xf.origin, minf(k * 2.5, 1.0)))
	if cur.origin.distance_to(xf.origin) > 6.0:
		smooth = xf
	t.node.global_transform = smooth
	# physics only near the player
	var near := d < PHYS_RANGE
	if t.shape.disabled == near:
		t.shape.set_deferred("disabled", not near)
	# player contact (geometric: frozen kinematic bodies do not report contacts reliably under Jolt)
	if d < 9.0 and _player:
		var local := t.node.global_transform.affine_inverse() * ppos
		var rel := (_player.linear_velocity - _travel_dir(t) * t.speed).length()
		if absf(local.x) < 1.95 and absf(local.z) < t.length * 0.5 + 2.1 and absf(local.y) < 2.5 and rel > 2.5:
			_crash(t)
			return
	# shadows only for nearby traffic
	var want_shadow := d < 110.0
	if want_shadow != t.shadows:
		t.shadows = want_shadow
		for mi in t.meshes:
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if want_shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# visuals
	if d < 200.0:
		t.wheel_spin -= t.speed * delta / 0.35
		for w in t.wheels:
			w.rotation.x = t.wheel_spin
	var braking := t.accel < -1.0 or t.speed < 0.5
	for l in t.lights:
		l.emission_energy_multiplier = lerpf(l.emission_energy_multiplier, 2.5 if night else 0.0, delta * 3.0)
	for l in t.tails:
		l.emission_energy_multiplier = 4.0 if braking else (1.0 if night else 0.0)


func _advance_road(t: TCar) -> void:
	var road := t.road
	var n := road.pts.size()
	# turning onto side roads at junctions passed on this road
	var cur_i := int(round(t.u))
	if cur_i != t.last_junction:
		for jn in _junctions_on[road.index]:
			if jn[0] == cur_i and rng.randf() < 0.28:
				var branch: WorldData.Road = jn[1]
				var b_end: int = jn[2]
				t.last_junction = cur_i
				t.road = branch
				t.lane = 0
				if b_end == 0:
					t.dir = 1
					t.u = 1.0
				else:
					t.dir = -1
					t.u = branch.pts.size() - 2.0
				t.last_junction = int(t.u)
				return
	if road.closed:
		t.u = fposmod(t.u, n - 1)
		return
	if t.u >= n - 1 or t.u <= 0.0:
		var at_end := n - 1 if t.u >= n - 1 else 0
		for j in road.junctions:
			if int(j.self_i) == at_end:
				var main := data.road_by_id(j.road)
				t.road = main
				t.u = float(j.road_i)
				t.dir = 1 if rng.randf() < 0.5 else -1
				if not main.closed:
					if int(j.road_i) >= main.pts.size() - 3:
						t.dir = -1
					elif int(j.road_i) <= 2:
						t.dir = 1
				t.lane = 0
				t.last_junction = int(j.road_i)
				return
		# dead end: turn around
		t.dir = -t.dir
		t.u = clampf(t.u, 1.0, n - 2.0)


# ------------------------------------------------------------------ population
func target_count() -> int:
	var dens: float = Game.settings.traffic_density
	var h := Game.time_of_day
	var tod := 1.0
	if h < 6.0 or h > 22.0:
		tod = 0.35
	elif h < 7.5 or h > 20.0:
		tod = 0.65
	return int(round(MAX_CARS * dens * tod))


func _manage_population(ppos: Vector3, cam: Camera3D) -> void:
	# despawn
	for t: TCar in cars.duplicate():
		var d := t.node.global_position.distance_to(ppos)
		var visible_now := cam != null and _in_view(cam, t.node.global_position) and d < 450.0
		var too_far := d > DESPAWN and not visible_now
		var dead := t.state == State.STOPPED and t.timer > 25.0 and not visible_now
		var crashed_far := t.state != State.DRIVE and d > 300.0
		if too_far or dead or crashed_far or (cars.size() > target_count() + 3 and d > 400.0 and not visible_now):
			_release(t)
	# spawn up to two per pass
	var want := target_count()
	var tries := 0
	while cars.size() < want and tries < 12:
		tries += 1
		if _try_spawn(ppos, cam):
			if tries > 2:
				break


func _in_view(cam: Camera3D, p: Vector3) -> bool:
	return not cam.is_position_behind(p) and cam.is_position_in_frustum(p)


func _pick_road() -> WorldData.Road:
	var r := rng.randf() * _road_weights[_road_weights.size() - 1]
	for i in _road_weights.size():
		if r <= _road_weights[i]:
			return data.roads[i]
	return data.roads[0]


func _pick_type(road: WorldData.Road) -> String:
	var keys: Array[String] = []
	var weights: Array[float] = []
	for k in TYPES:
		var w: float = TYPES[k].weight
		if k == "tractor" and not road.cls in ["lane", "dirt", "gravel"]:
			continue
		if k in ["coach", "lorry"] and road.cls in ["dirt", "gravel", "sand", "lane"]:
			continue
		if k == "tractor":
			w *= 3.0
		if (_pool[k] as Array).is_empty():
			continue
		keys.append(k)
		weights.append(w)
	if keys.is_empty():
		return ""
	var tot := 0.0
	for w in weights:
		tot += w
	var r := rng.randf() * tot
	for i in keys.size():
		r -= weights[i]
		if r <= 0.0:
			return keys[i]
	return keys[keys.size() - 1]


func _try_spawn(ppos: Vector3, cam: Camera3D) -> bool:
	var road := _pick_road()
	if road.cls == "sand":
		return false
	var n := road.pts.size()
	var i := rng.randi_range(2, n - 3)
	var p := road.pts[i]
	var d := p.distance_to(ppos)
	if d < SPAWN_MIN or d > SPAWN_MAX:
		return false
	if road.flags[i] == 2:
		return false
	if cam and _in_view(cam, p) and d < 420.0:
		return false
	var dir := 1 if rng.randf() < 0.5 else -1
	var lane := 0
	if road.lanes >= 4 and rng.randf() < 0.3:
		lane = 1
	for o in cars:
		if o.node.global_position.distance_to(p) < 35.0:
			return false
	var k := _pick_type(road)
	if k == "":
		return false
	var t: TCar = (_pool[k] as Array).pop_back()
	t.road = road
	t.dir = dir
	t.lane = lane
	t.u = float(i)
	t.pref = rng.randf_range(0.82, 1.04)
	t.speed = minf(road.speed / 3.6 * t.pref * float(TYPES[k].speed), (_curve_speed[road.index] as PackedFloat32Array)[i])
	t.accel = 0.0
	t.state = State.DRIVE
	t.timer = 0.0
	t.waiting = false
	t.last_junction = -999
	t.node.freeze = true
	t.node.global_transform = _pose(t)
	t.node.linear_velocity = Vector3.ZERO
	t.node.angular_velocity = Vector3.ZERO
	t.node.visible = true
	t.active = true
	cars.append(t)
	stats.spawned += 1
	return true


func _release(t: TCar) -> void:
	cars.erase(t)
	t.node.visible = false
	t.node.freeze = true
	t.shape.set_deferred("disabled", true)
	t.node.global_position = Vector3(0, -500, 0)
	t.active = false
	(_pool[t.type_key] as Array).append(t)
	stats.despawned += 1


func clear_all() -> void:
	for t: TCar in cars.duplicate():
		_release(t)


func minimap_dots() -> PackedVector2Array:
	var out := PackedVector2Array()
	for t in cars:
		var p := t.node.global_position
		out.append(Vector2(p.x, p.z))
	return out
