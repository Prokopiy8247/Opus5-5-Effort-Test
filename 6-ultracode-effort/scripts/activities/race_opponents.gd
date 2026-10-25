extends RefCounted
## AI rivals for a road race: catalog cars built with CarFactory (is_player = false) and driven along the race
## road by RoadFollower on racing-line offsets (steering assist off), with light rubber-banding.
## Speed: a curvature profile of the race road (corner speed + braking distance before it) replaces RoadFollower's
## own estimate. Cars ahead (player, other rivals, traffic) are tracked in road coordinates: a rival brakes on a
## stopping-distance curve for anything on the line it will be on, stops STOP_GAP short of a stopped car and
## picks a clear line to pass it - the oncoming lane of a single-lane road only while it is clear.
## Recovery: a rival that left the route, landed in water, fell, flipped, spun round or got stuck (not merely
## waiting behind a car) is put back on its line at a clear spot, out of the player's view when possible, with
## road speed. Rivals far from the player register terrain collider points (World.extra_physics_points).

const ActivityBase := preload("res://scripts/activities/activity_base.gd")
const PAINTS: Array[String] = ["blue", "teal", "orange", "purple", "red", "mint", "gold", "pink"]
## Racing lines as fractions of the travel half of the road (centre line = 0, paved edge = 1).
const LINES: Array[float] = [0.36, 0.64, 0.5]
## An overtake in the oncoming lane needs this many seconds of closing time to oncoming traffic (plus a margin);
## a pass under way is abandoned below ABORT_TIME.
const PASS_TIME := 6.0
const PASS_MARGIN := 40.0
const ABORT_TIME := 2.5
## Share of the cornering grip used while oncoming traffic is within CAUTION_DIST + 4 s of the rival.
const ONCOMING_GRIP := 0.72
const CAUTION_DIST := 60.0
## Gap (m) between the centre line and the body kept in that case on single-lane roads.
const ONCOMING_KEEP := 1.0
## Speed plan: lateral acceleration per unit of CarData.tire_grip (m/s^2), braking deceleration (m/s^2) and the
## sample spacing of the curvature profile (m). The plan replaces RoadFollower's own curve estimate (its lat_accel
## is set out of the way), which averages bends with the straight before them and brakes gently.
const PLAN_GRIP := 7.3
const BRAKE_DECEL := 7.5
const PROFILE_DS := 3.0
const NO_CURVE_LIMIT := 1000.0
## Following: bumper gap kept behind a slow car / a standing one (room to steer out and pass round it), time gap
## at speed, deceleration.
const STOP_GAP := 7.0
const STOP_GAP_STILL := 9.5
const TIME_GAP := 0.45
const FOLLOW_DECEL := 5.0
## Line change model used to predict where a rival will be when it reaches a car ahead: lateral speed (m/s, incl.
## steering lag), at most LAT_PER_M metres sideways per metre forward (steering geometry at low speed); side
## clearance between bodies (SIDE_MARGIN at speed, SIDE_MIN when creeping); creep speed while pulling out round a
## stopped car (its target line clear of it); a line change waits for faster cars closer than MERGE_TIME behind.
const LAT_RATE := 1.6
const LAT_PER_M := 0.2
const SIDE_MARGIN := 0.45
const SIDE_MIN := 0.15
const CREEP := 1.8
const MERGE_TIME := 2.5
## Walking pace past a car that is already clear to the side while the rival steers away from it (an oncoming car
## it stopped nose to nose with on the centre line); lateral speed back into the travel half after a pass.
const SQUEEZE := 1.2
const RETURN_RATE := 2.5
## Speed (m/s) of a back-off / retreat in reverse; a back-off ends at the latest after BACKOFF_TIME.
const REVERSE_SPEED := 2.2
const BACKOFF_TIME := 6.0
## A rival held this long by a car facing it (nose to nose) gives up and is recovered (last resort).
const STANDOFF_TIME := 9.0
## Braking (m/s^2) kept in hand while a rival is still behind a car it plans to pass.
const PASS_DECEL := 7.0
## A rival tries to pass when the car ahead holds it below this share of the speed it could go.
const PASS_WORTH := 0.88
## Recovery: off the route = more than OFF_LATERAL beyond the paved edge (or 5 m above / below the road) for
## OFF_TIME; water deeper than WATER_DEPTH or 6 m below the road / ground for WET_TIME; stuck = below 1.5 m/s for
## STUCK_TIME while nothing holds it. A recovery waits up to VIEW_WAIT for the rival and its spot to be out of view.
const OFF_LATERAL := 3.5
const OFF_TIME := 1.5
const WATER_DEPTH := 0.5
const WET_TIME := 0.8
const STUCK_TIME := 4.0
const WRONG_TIME := 2.5
const VIEW_WAIT := 4.0
const VIEW_DIST := 230.0
## Rivals farther than this from the player register terrain collider points (the player's own zone is 230 m).
const PHYS_POINT_MIN := 150.0
## Finished rivals cruise on and are removed once this far past the finish (or after RETIRE_TIME) and out of view.
const RETIRE_DIST := 150.0
const RETIRE_TIME := 45.0
## After the race (finish or cancel) every rival cruises on at CRUISE_SPEED, easing off at COAST_DECEL, and
## leaves once the camera has not seen it for LEAVE_UNSEEN seconds (at least LEAVE_NEAR m from the player).
const CRUISE_SPEED := 14.0
const COAST_DECEL := 2.5
const LEAVE_UNSEEN := 1.0
const LEAVE_NEAR := 30.0

var cars: Array[CarController] = []
var followers: Array[RoadFollower] = []
var finish_times: PackedFloat32Array = PackedFloat32Array()
var road: RoadNetwork.Road
var dir: int = 1
var finish_s: float = 0.0
## Recoveries per rival (tests read it).
var recoveries: PackedInt32Array = PackedInt32Array()
var _base_lat: PackedFloat32Array = PackedFloat32Array()
## Cornering grip each rival plans with this frame (rubber band, oncoming caution).
var _lat_now: PackedFloat32Array = PackedFloat32Array()
var _base_v: PackedFloat32Array = PackedFloat32Array()
var _line: PackedFloat32Array = PackedFloat32Array()
## Line each rival is on now (travel-relative lateral, + = right); differs from _line while passing.
var _cur: PackedFloat32Array = PackedFloat32Array()
## Line it steers for: _cur, kept further from the centre line while oncoming traffic is near.
var _aim: PackedFloat32Array = PackedFloat32Array()
## 1 while a rival is out of its own line to pass (kept for tests / debugging).
var _swing: PackedFloat32Array = PackedFloat32Array()
var _stuck: PackedFloat32Array = PackedFloat32Array()
var _off_t: PackedFloat32Array = PackedFloat32Array()
var _off_s: PackedFloat32Array = PackedFloat32Array()
var _wet_t: PackedFloat32Array = PackedFloat32Array()
var _flip_t: PackedFloat32Array = PackedFloat32Array()
var _wrong_t: PackedFloat32Array = PackedFloat32Array()
var _wait_t: PackedFloat32Array = PackedFloat32Array()
var _backoff: PackedFloat32Array = PackedFloat32Array()
## Reversing out of the oncoming lane (stopped beside the car it was passing while oncoming traffic waits).
var _retreat: PackedFloat32Array = PackedFloat32Array()
var _close_t: PackedFloat32Array = PackedFloat32Array()
## Obstacle that limits a rival this frame: gap (m, bumper to bumper), its speed along the road and 1 when it
## faces the rival; time held (standing) by such a facing car.
var _lim_gap: PackedFloat32Array = PackedFloat32Array()
var _lim_v: PackedFloat32Array = PackedFloat32Array()
var _lim_face: PackedFloat32Array = PackedFloat32Array()
var _face_t: PackedFloat32Array = PackedFloat32Array()
var _kappa: PackedFloat32Array = PackedFloat32Array()
var _phys_points: Array[Vector3] = []
var _hold: Array[Dictionary] = []
var _holding := false
var _ray := PhysicsRayQueryParameters3D.new()
var _go := false
## The race is over: the rivals only cruise off (cruise(), driven by the activity manager).
var released := false
var _unseen: PackedFloat32Array = PackedFloat32Array()


func spawn(parent: Node, r: RoadNetwork.Road, d: int, slots: Array[Transform3D], fin_s: float, player_data: CarData) -> void:
	road = r
	dir = d
	finish_s = fin_s
	_build_profile()
	var picks := _pick_cars(player_data, slots.size())
	for k in picks.size():
		var cd: CarData = picks[k].duplicate()
		var paint := {"color": Game.PAINT_COLORS[PAINTS[(k * 3 + cd.id.length()) % PAINTS.size()]], "finish": 2}
		var car := CarFactory.build(cd, paint, false)
		car.name = "Rival_%d_%s" % [k + 1, cd.id]
		# The steering assist (speed-sensitive lock + counter-steer toward the slide) is a keyboard aid: on an AI
		# that sets the wheel angle itself it cancels the steering in fast bends once the body slips a few degrees.
		car.assist_steer = false
		# Head / tail lamps like traffic (the low-beam cones of a non-player car), switched by update_lights().
		(car.get_node("Visual") as CarVisuals).add_headlights()
		parent.add_child(car)
		# Slots rest on the road (origin on the surface): frozen there for the countdown, no drop at GO.
		var xf := slots[k]
		car.place_at(xf)
		car.freeze = true
		var f := RoadFollower.new()
		var s := _nearest_s(xf.origin)
		var lateral := (xf.origin - road.point_at(s)).dot(road.right_at(s))
		f.setup(road, s, dir, lateral * dir)
		# Traffic is handled here per line (RoadFollower's own probe only knows the follower's lane).
		f.respect_traffic = false
		# The front of the grid gets the quickest car and driver: slower rivals do not hold up a train behind.
		var skill := 1.02 - 0.04 * k
		f.lat_accel = NO_CURVE_LIMIT
		f.target_speed = cd.top_speed_kmh / 3.6 * 0.96
		cars.append(car)
		followers.append(f)
		finish_times.append(-1.0)
		recoveries.append(0)
		_base_lat.append(PLAN_GRIP * cd.tire_grip * skill)
		_lat_now.append(_base_lat[k])
		_base_v.append(f.target_speed)
		_line.append(road.width * 0.5 * LINES[k % LINES.size()])
		_cur.append(_line[k])
		_aim.append(_line[k])
	# Per-rival timers (packed arrays are values: build each at full size and assign it).
	for arr: String in ["_swing", "_stuck", "_off_t", "_off_s", "_wet_t", "_flip_t", "_wrong_t", "_wait_t", "_backoff",
			"_retreat", "_close_t", "_lim_gap", "_lim_v", "_lim_face", "_face_t", "_unseen"]:
		var a := PackedFloat32Array()
		a.resize(cars.size())
		a.fill(0.0)
		set(arr, a)
	update_lights()


func _pick_cars(player_data: CarData, n: int) -> Array[CarData]:
	var pool: Array[CarData] = []
	for c in Game.get_car_catalog():
		if player_data == null or c.id != player_data.id:
			pool.append(c)
	var ref := player_data.top_speed_kmh if player_data != null else 230.0
	pool.sort_custom(func(a: CarData, b: CarData) -> bool: return absf(a.top_speed_kmh - ref) < absf(b.top_speed_kmh - ref))
	var out := pool.slice(0, mini(n, pool.size()))
	out.sort_custom(func(a: CarData, b: CarData) -> bool: return a.tire_grip > b.tire_grip)
	return out


func _nearest_s(p: Vector3) -> float:
	var res := Game.world.data.network.nearest(p, 60.0, func(rr: RoadNetwork.Road) -> bool: return rr == road) as Dictionary
	return float(res.get("s", 0.0))


func go() -> void:
	_go = true
	for car in cars:
		if is_instance_valid(car):
			car.freeze = false


# ------------------------------------------------------------------ speed plan

## Local curvature (1/m, tangent turn over 12 m) of the race road every PROFILE_DS metres, widened to the
## maximum within +-6 m so short kinks count fully.
func _build_profile() -> void:
	var n := maxi(int(road.length / PROFILE_DS), 2)
	var raw := PackedFloat32Array()
	raw.resize(n + 1)
	for i in n + 1:
		var s := i * PROFILE_DS
		raw[i] = road.flat_tangent_at(s - 6.0).angle_to(road.flat_tangent_at(s + 6.0)) / 12.0
	_kappa.resize(n + 1)
	for i in n + 1:
		var m := 0.0
		for j in range(i - 2, i + 3):
			m = maxf(m, raw[posmod(j, n + 1)] if road.loop else raw[clampi(j, 0, n)])
		_kappa[i] = m


func _kappa_at(s: float) -> float:
	var n := _kappa.size()
	var i := int(roundf((fposmod(s, road.length) if road.loop else clampf(s, 0.0, road.length)) / PROFILE_DS))
	return _kappa[posmod(i, n)] if road.loop else _kappa[clampi(i, 0, n - 1)]


## Highest speed at arclength s that still makes every bend ahead (corner speed from lat_accel, braking at
## BRAKE_DECEL before it, a short reaction allowance).
func _corner_limit(s: float, v: float, lat_accel: float) -> float:
	var reach := minf(v * v / (2.0 * BRAKE_DECEL) + 40.0, 330.0)
	var lim := INF
	var d := 0.0
	while d <= reach:
		var kk := _kappa_at(s + dir * d)
		if kk > 0.0004:
			var vc2 := lat_accel / kk
			lim = minf(lim, sqrt(vc2 + 2.0 * BRAKE_DECEL * maxf(d - v * 0.3, 0.0)))
		d += PROFILE_DS
	return lim


## Mean speed rival k could hold over the next 200 m on its own (bends included): a car ahead slower than this
## is worth passing even where the bend right here is slow.
func _free_speed(s: float, lat_accel: float, target: float) -> float:
	var sum := 0.0
	var n := 0
	var d := 0.0
	while d <= 200.0:
		sum += minf(target, sqrt(lat_accel / maxf(_kappa_at(s + dir * d), 0.0004)))
		n += 1
		d += 6.0
	return sum / n


# ------------------------------------------------------------------ driving

func physics(dt: float, player_s: float, race_time: float) -> void:
	if not _go or _holding:
		return
	update_lights()
	for k in cars.size():
		var car := cars[k]
		if not is_instance_valid(car):
			continue
		var f := followers[k]
		var done := released or finish_times[k] >= 0.0
		if done and _retire(k, race_time, dt):
			continue
		var v := car.speed_ms
		# Rubber band: rivals far ahead ease off, rivals far behind push a little harder (barely beyond their
		# planned grip in corners).
		var gap := 0.0 if released else (f.s - player_s) * dir
		var band := clampf(1.0 - gap / 600.0, 0.85, 1.22)
		var lat := _base_lat[k] * clampf(band, 0.9, 1.04)
		f.lat_accel = NO_CURVE_LIMIT
		if done:
			# Cruising off: ease down to a relaxed pace (no braking hard from race speed), stopping before the end
			# of a road that is not a loop.
			f.target_speed = maxf(CRUISE_SPEED, minf(f.target_speed, v) - COAST_DECEL * dt)
			if not road.loop:
				var left := (road.length - f.s) if dir > 0 else f.s
				f.target_speed = minf(f.target_speed, sqrt(2.0 * FOLLOW_DECEL * maxf(left - 25.0, 0.0)))
		else:
			f.target_speed = _base_v[k] * clampf(band, 0.9, 1.08)
		var traffic := _traffic_near(car.global_position, maxf(PASS_MARGIN + (v + 30.0) * PASS_TIME, 40.0 + v * v / (2.0 * FOLLOW_DECEL)))
		var oncoming := _oncoming(k, traffic)
		for o: Vector2 in oncoming:
			if o.x < CAUTION_DIST + (v + o.y) * 4.0:
				lat = minf(lat, _base_lat[k] * ONCOMING_GRIP)
		_lat_now[k] = lat
		var desired := minf(f.target_speed, _corner_limit(f.s, v, lat))
		var limit := _choose_line(k, dt, oncoming, traffic, desired)
		# lane_offset is relative to the travel direction (+ = right). Line changes to pass are quick, the drift
		# back to the racing line is slow; out of the oncoming half quickly - until the whole body is back in the
		# travel half, not just the line it aims at.
		var over := road.lanes < 2 and _lat(car.global_position, f.s) - car.data.body_size.x * 0.5 < 0.3
		var rate := 2.0 if _swing[k] > 0.0 else (RETURN_RATE if f.lane_offset < 0.0 or over else 0.6)
		f.lane_offset = move_toward(f.lane_offset, _aim[k], dt * rate)
		# Pulling out at low speed (round a stopped car, or round a car it stands nose to nose with): aim at the
		# line at once, short look-ahead.
		var pulling_out := (_swing[k] > 0.0 or _face_t[k] > 0.0) and v < 6.0
		if pulling_out:
			f.lane_offset = _cur[k]
		f.look_base = 3.0 if pulling_out else 7.0
		f.obstacle_limit = minf(limit, desired)
		f.drive(car, dt)
		_assist(k, car, dt, limit)
		if not done and (f.s - finish_s) * dir >= 0.0:
			finish_times[k] = race_time
			print("[activity] rival %s finished in %.2f" % [car.name, race_time])
		# Held = waiting or creeping behind a car (not stuck); standing nose to nose with a car that faces it counts
		# toward the stand-off fallback.
		var facing := limit < 0.5 and v < 0.5 and _lim_face[k] > 0.0
		var still_held := _face_t[k] > 0.0 and (_backoff[k] > 0.0 or limit < CREEP + 0.7)
		_face_t[k] = _face_t[k] + dt if facing or still_held else 0.0
		if not released:
			_recover(k, dt, limit < CREEP + 0.7)
	_update_physics_points()


## Throttle off at full steering lock (the car would run wide under power); firm braking to the limit at low speed
## (RoadFollower brakes gently there) with the handbrake holding a standstill; reverses a rival out of the oncoming
## lane (_retreat) or out of a nose-to-tail stop behind a stationary car so it has room to steer round it.
func _assist(k: int, car: CarController, dt: float, limit: float) -> void:
	if absf(car.in_steer) > 0.9 and car.speed_ms > 8.0:
		car.in_throttle = minf(car.in_throttle, 0.3)
	var err := followers[k].obstacle_limit - car.speed_ms
	if err < -1.0 and car.forward_speed > 0.8:
		car.in_throttle = 0.0
		car.in_brake = maxf(car.in_brake, clampf(-err * 0.4, 0.0, 1.0))
	elif followers[k].obstacle_limit < 0.3 and car.forward_speed >= 0.0 and car.forward_speed <= 0.8:
		car.in_throttle = 0.0
		car.in_brake = minf(car.in_brake, 0.25)
		car.in_handbrake = 1.0
	if _retreat[k] > 0.0:
		_retreat[k] -= dt
		if _clear_behind(k, 3.0):
			_reverse(car, 0.0)
			return
		_retreat[k] = 0.0
	var close := limit < 0.5 and car.speed_ms < 0.8 and _lim_gap[k] < _stop_gap(_lim_v[k]) - 2.0 and absf(_lim_v[k]) < 0.5
	_close_t[k] = _close_t[k] + dt if close else 0.0
	if _close_t[k] > 0.6 and _backoff[k] <= 0.0 and _clear_behind(k, 6.0):
		_backoff[k] = BACKOFF_TIME
	if _backoff[k] > 0.0:
		_backoff[k] -= dt
		var my_lat := _lat(car.global_position, followers[k].s)
		var at_edge := absf(my_lat) > road.width * 0.5 - car.data.body_size.x * 0.5
		if _lim_gap[k] >= _stop_gap(_lim_v[k]) - 1.0 or not _clear_behind(k, 3.0) or at_edge:
			_backoff[k] = 0.0
		else:
			# Reverse with the wheels turned a little away from the pass side: the nose swings towards it. Back to
			# its own line (standing across the centre line in front of an oncoming car) it reverses straight - a
			# swinging tail would only go deeper into the oncoming half - and pulls out with a short look-ahead.
			var dl := _cur[k] - my_lat
			_reverse(car, 0.0 if is_equal_approx(_cur[k], _line[k]) or absf(dl) < 0.3 else (-0.35 if dl > 0.0 else 0.35))
			return
	if car.gear == -1:
		# Out of reverse after a back-off (RoadFollower only drives forwards: in reverse its brake input would
		# keep the car rolling backwards): handbrake to a stop, then throttle selects first gear.
		car.in_brake = 0.0
		car.in_handbrake = 1.0 if car.forward_speed < -0.5 else 0.0
		car.in_throttle = 0.0 if car.forward_speed < -1.0 else maxf(car.in_throttle, 0.3)


## Backs up at walking pace (in reverse the brake pedal drives backwards; it would run up to the reverse limiter).
func _reverse(car: CarController, steer: float) -> void:
	car.in_throttle = 0.0
	car.in_brake = 0.4 if car.forward_speed > -REVERSE_SPEED else 0.0
	car.in_handbrake = 0.0
	car.in_steer = steer


func _clear_behind(k: int, dist: float) -> bool:
	var me := cars[k]
	var back := me.global_basis.z
	var reach := dist + me.data.body_size.z * 0.5
	for o in _others(k):
		var rel := o.global_position - me.global_position
		if rel.dot(back) > 0.0 and rel.length() < reach + o.data.body_size.z * 0.5:
			return false
	for o: Dictionary in _traffic_near(me.global_position, reach + 10.0):
		var rel2 := (o["position"] as Vector3) - me.global_position
		if rel2.dot(back) > 0.0 and rel2.length() < reach + float(o["length"]) * 0.5:
			return false
	return true


func _others(k: int) -> Array[CarController]:
	var out: Array[CarController] = []
	for j in cars.size():
		if j != k and is_instance_valid(cars[j]):
			out.append(cars[j])
	if Game.player_car != null and is_instance_valid(Game.player_car):
		out.append(Game.player_car)
	return out


func _traffic_near(pos: Vector3, radius: float) -> Array:
	var tm: Node = Game.traffic
	if tm == null or not tm.has_method("obstacles_near"):
		return []
	return tm.call("obstacles_near", pos, minf(radius, 400.0))


## Oncoming traffic on the race road ahead of rival k (single-lane roads only): Vector2(distance along the road,
## speed) per vehicle.
func _oncoming(k: int, traffic: Array) -> Array[Vector2]:
	var out: Array[Vector2] = []
	if road.lanes >= 2:
		return out
	var pos := cars[k].global_position
	var fs := followers[k].s
	for o: Dictionary in traffic:
		var p: Vector3 = o["position"]
		var so := _project(p, fs + dir * Vector2(p.x - pos.x, p.z - pos.z).length())
		if absf((p - road.point_at(so)).dot(road.right_at(so))) > road.width * 0.5 + 1.5:
			continue
		if (o["heading"] as Vector3).dot(road.flat_tangent_at(so) * dir) > -0.3:
			continue
		var along := _wrap((so - fs) * dir)
		if along > -6.0:
			out.append(Vector2(along, float(o["speed"])))
	return out


## True when an overtake may use (or stay in) the oncoming lane: no oncoming vehicle within `seconds` of closing
## time plus `margin` metres (measured along the road, so bends count).
func _pass_clear(oncoming: Array[Vector2], v: float, seconds: float, margin: float) -> bool:
	for o in oncoming:
		if o.x < margin + (v + o.y) * seconds:
			return false
	return true


func _wrap(along: float) -> float:
	if road.loop:
		return fposmod(along + road.length * 0.5, road.length) - road.length * 0.5
	return along


## Arclength on the race road closest to p, searched from s_hint.
func _project(p: Vector3, s_hint: float) -> float:
	var ss := s_hint
	for i in 8:
		var q := road.point_at(ss)
		var t := road.flat_tangent_at(ss)
		var step := clampf((p.x - q.x) * t.x + (p.z - q.z) * t.z, -40.0, 40.0)
		ss = fposmod(ss + step, road.length) if road.loop else clampf(ss + step, 0.0, road.length)
		if absf(step) < 0.1:
			break
	return ss


## Travel-relative lateral offset (+ = right of the travel direction) of a position at arclength s.
func _lat(p: Vector3, s: float) -> float:
	return (p - road.point_at(s)).dot(road.right_at(s)) * dir


## Cars around rival k in road coordinates: PackedFloat32Array(along, lateral, speed along the road,
## lateral half extent, longitudinal half extent, 1 when it faces the rival) - extents from the body orientation,
## so a car stopped across the road blocks every line it covers.
func _obstacles(k: int, traffic: Array, reach: float) -> Array[PackedFloat32Array]:
	var out: Array[PackedFloat32Array] = []
	var me := cars[k]
	var f := followers[k]
	var pos := me.global_position
	for o in _others(k):
		var p := o.global_position
		var bs := o.data.body_size
		_add_obstacle(out, f, pos, p, o.linear_velocity, o.global_basis.x, -o.global_basis.z, bs.x * 0.5, bs.z * 0.5, reach)
	for o: Dictionary in traffic:
		var h: Vector3 = o["heading"]
		var fwd := Vector3(h.x, 0.0, h.z).normalized()
		var right := Vector3(-fwd.z, 0.0, fwd.x)
		_add_obstacle(out, f, pos, o["position"], fwd * float(o["speed"]), right, fwd, float(o.get("width", 2.1)) * 0.5,
			float(o.get("length", 4.5)) * 0.5, reach)
	return out


func _add_obstacle(out: Array[PackedFloat32Array], f: RoadFollower, pos: Vector3, p: Vector3, vel: Vector3, bx: Vector3,
		bz: Vector3, hw: float, hl: float, reach: float) -> void:
	var dist := Vector2(p.x - pos.x, p.z - pos.z).length()
	if dist > reach + 10.0:
		return
	var so := _project(p, f.s + dir * dist)
	var along := _wrap((so - f.s) * dir)
	if along < -70.0 or along > reach:
		return
	var t := road.flat_tangent_at(so) * dir
	var r := Vector3(-t.z, 0.0, t.x)
	var half_lat := absf(bx.dot(r)) * hw + absf(bz.dot(r)) * hl
	var half_long := absf(bx.dot(t)) * hw + absf(bz.dot(t)) * hl
	if absf(p.y - road.point_at(so).y) > 6.0:
		return
	out.append(PackedFloat32Array([along, _lat(p, so), vel.dot(t), half_lat, half_long, 1.0 if bz.dot(t) < -0.5 else 0.0]))


static func _stop_gap(lead_v: float) -> float:
	return STOP_GAP_STILL if absf(lead_v) < 1.0 else STOP_GAP


## Speed that keeps a time gap to a leader `gap` metres ahead (bumper to bumper) and stops short of it.
static func _follow_speed(gap: float, lead_v: float, own_v: float) -> float:
	var room := gap - _stop_gap(lead_v) - own_v * 0.3
	if room <= 0.0:
		return 0.0
	var lv := maxf(lead_v, 0.0)
	var keep := lv + (room - own_v * TIME_GAP) / 2.0
	var stop := sqrt(lv * lv + 2.0 * FOLLOW_DECEL * room)
	return clampf(minf(keep, stop), 0.0, 120.0)


## Speed limit for rival k on line `line`: every car ahead that the rival would still overlap laterally when it
## gets there (line changes need distance). Records the limiting gap / speed for the back-off.
func _line_limit(k: int, obs: Array[PackedFloat32Array], line: float, my_lat: float, v: float, record := false) -> float:
	var me := cars[k]
	var my_hw := me.data.body_size.x * 0.5
	var my_hl := me.data.body_size.z * 0.5
	var per_m := minf(LAT_PER_M, LAT_RATE / maxf(v, 1.0))
	var margin := _side_margin(v)
	# Sideways component of the heading (travel-relative, + = right): where the nose is pointing.
	var yaw := (-me.global_basis.z).dot(road.right_at(followers[k].s)) * dir
	var lim := INF
	for o in obs:
		var gap := o[0] - my_hl - o[4]
		if gap < -0.5:
			continue
		var w := my_hw + o[3] + margin
		var lat_then := move_toward(my_lat, line, maxf(gap, 0.0) * per_m)
		# Already clear of it to the side, aiming and pointing away from it: walking pace past it is safe (an
		# oncoming car stopped nose to nose with a rival on the centre line - neither could move otherwise).
		var side := signf(my_lat - o[1])
		var squeeze := absf(o[1] - my_lat) - my_hw - o[3] >= SIDE_MIN and (line - my_lat) * side >= -0.05 and yaw * side >= -0.02
		if absf(o[1] - lat_then) >= w:
			if absf(o[1] - my_lat) < w:
				# Planned past it but still behind it: always able to stop short in case the line change lags.
				var l0 := sqrt(2.0 * PASS_DECEL * maxf(gap - 1.5, 0.0))
				if squeeze:
					l0 = maxf(l0, SQUEEZE)
				if l0 < lim:
					lim = l0
					if record:
						_lim_gap[k] = gap
						_lim_v[k] = o[2]
						_lim_face[k] = o[5]
			continue
		var l := _follow_speed(gap, o[2], v)
		if absf(o[1] - line) >= w and gap > 2.5:
			# Pulling out round it: keep rolling while the steering takes the car across.
			l = maxf(l, CREEP)
		elif squeeze:
			l = maxf(l, SQUEEZE)
		if l < lim:
			lim = l
			if record:
				_lim_gap[k] = gap
				_lim_v[k] = o[2]
				_lim_face[k] = o[5]
	return lim


static func _side_margin(v: float) -> float:
	return lerpf(SIDE_MIN, SIDE_MARGIN, clampf(v / 12.0, 0.0, 1.0))


## Rival k cannot move onto `line` now: a car beside or shortly ahead (not the one straight ahead in its own
## path) covers the lateral sweep, or a faster car comes up on that line from behind within MERGE_TIME. "Shortly"
## depends on the closing speed: falling in behind a car ahead needs room to match its speed, behind a faster one
## a few metres. `urgent` (out of the oncoming lane with traffic coming): only a car alongside blocks it.
func _merge_blocked(k: int, obs: Array[PackedFloat32Array], line: float, my_lat: float, urgent := false) -> bool:
	var me := cars[k]
	var v := me.speed_ms
	var my_hw := me.data.body_size.x * 0.5
	var my_hl := me.data.body_size.z * 0.5
	var lo := minf(my_lat, line)
	var hi := maxf(my_lat, line)
	for o in obs:
		var hl := my_hl + o[4]
		var w := my_hw + o[3] + _side_margin(v)
		if o[0] < -(hl + 3.0):
			var closing := o[2] - v
			if closing > 0.5 and (-o[0] - hl) / closing < MERGE_TIME and absf(o[1] - line) < w + 0.5:
				return true
			continue
		var gaining := maxf(v - o[2], 0.0)
		if o[0] - hl > (1.5 if urgent else 4.0 + v * 0.25 + gaining * 0.8 + gaining * gaining / (2.0 * FOLLOW_DECEL)):
			continue
		if o[1] + w > lo and o[1] - w < hi and absf(o[1] - my_lat) >= my_hw + o[3] - 0.2:
			return true
	return false


## Lines rival k may pass on: the right part of the travel half, the other travel lane on multi-lane roads,
## the oncoming lane on single-lane roads.
func _pass_lines(k: int) -> Array[float]:
	var half := road.width * 0.5
	var hw := cars[k].data.body_size.x * 0.5
	var out: Array[float] = [half - hw - 0.25]
	if road.lanes >= 2:
		out.append(half * (0.75 if _line[k] < half * 0.5 else 0.28))
	else:
		out.append(-road.lane_offset(1))
	return out


## Picks the line for rival k (own racing line, or a pass line while the own one is blocked) and returns the
## speed limit from cars ahead on it.
func _choose_line(k: int, _dt: float, oncoming: Array[Vector2], traffic: Array, desired: float) -> float:
	var me := cars[k]
	var f := followers[k]
	var v := me.speed_ms
	var reach := minf(30.0 + v * v / (2.0 * FOLLOW_DECEL) + v * TIME_GAP, 330.0)
	var obs := _obstacles(k, traffic, reach)
	var my_lat := _lat(me.global_position, f.s)
	var own := _line[k]
	var cur := _cur[k]
	var single := road.lanes < 2
	var lim_own := _line_limit(k, obs, own, my_lat, v)
	var worth := maxf(desired, _free_speed(f.s, _lat_now[k], f.target_speed))
	# Abandon a pass in the oncoming lane while the whole body still gets back into the travel half (steering lag
	# included) before oncoming traffic arrives.
	var t_back := maxf(me.data.body_size.x * 0.5 + 0.3 - my_lat, 0.0) / LAT_RATE + 1.0
	var abort := single and cur < 0.0 and not _pass_clear(oncoming, v, maxf(ABORT_TIME, t_back), 15.0)
	if not is_equal_approx(cur, own):
		# Passing: back onto the racing line once it is free; out of the oncoming lane when traffic comes.
		var merge_ok := not _merge_blocked(k, obs, own, my_lat, abort)
		if merge_ok and lim_own >= desired * 0.95:
			cur = own
		elif merge_ok and abort:
			cur = own
		elif merge_ok and absf(my_lat - cur) > 0.8 and _merge_blocked(k, obs, cur, my_lat):
			# Still crossing over and a faster car comes up on that line: let it by first.
			cur = own
	# Held up on the line it is on (racing line: by a car slower than it could go; pass line: blocked as well):
	# move to whichever other line is clearly freer.
	var lim_cur := _line_limit(k, obs, cur, my_lat, v)
	if lim_cur < (worth * PASS_WORTH if is_equal_approx(cur, own) else desired * 0.6):
		var best := lim_cur
		var cands: Array[float] = [own]
		cands.append_array(_pass_lines(k))
		for cand in cands:
			if is_equal_approx(cand, cur):
				continue
			if single and cand < 0.0 and not _pass_clear(oncoming, v, PASS_TIME, PASS_MARGIN):
				continue
			if _merge_blocked(k, obs, cand, my_lat):
				continue
			var l := _line_limit(k, obs, cand, my_lat, v)
			# Clearly freer, or (standing behind a stopped car) at least a way to creep round it.
			if l > best + 2.0 or (best < 0.5 and l >= CREEP):
				best = l
				cur = cand
	_cur[k] = cur
	_swing[k] = 0.0 if is_equal_approx(cur, own) else 1.0
	_lim_gap[k] = INF
	_lim_v[k] = 0.0
	_lim_face[k] = 0.0
	var lim := _line_limit(k, obs, cur, my_lat, v, true)
	# Oncoming traffic near on a single-lane road: the body keeps ONCOMING_KEEP clear of the centre line (the car
	# runs a little inside its line through left-hand bends) where nothing beside it on the right is in the way.
	_aim[k] = cur
	var keep := me.data.body_size.x * 0.5 + ONCOMING_KEEP
	if single and is_equal_approx(cur, own) and own < keep and not _merge_blocked(k, obs, keep, my_lat):
		for o: Vector2 in oncoming:
			if o.x < CAUTION_DIST + (v + o.y) * 4.0:
				_aim[k] = keep
				lim = minf(lim, _line_limit(k, obs, keep, my_lat, v))
				break
	if single and cur < 0.0 and not _pass_clear(oncoming, v, maxf(ABORT_TIME, t_back), 15.0):
		# Stuck in the oncoming lane beside a car with traffic coming: drop back behind it - reversing out when
		# both stand (the oncoming car waits for its lane as well).
		for o in obs:
			if absf(o[0]) < me.data.body_size.z + o[4] + 2.0 and o[1] > 0.0:
				lim = minf(lim, maxf(o[2] - 4.0, 0.0))
				if v < 1.0 and absf(o[2]) < 1.0 and _retreat[k] <= 0.0:
					_retreat[k] = 4.0
	elif _retreat[k] > 0.0 and not (single and cur < 0.0):
		_retreat[k] = 0.0
	# Anything else straight ahead (parked cars) that the road picture above does not cover.
	_ray.from = me.global_position + Vector3.UP * 0.7
	_ray.to = _ray.from + (-me.global_basis.z) * (10.0 + v * 0.9)
	var ex: Array[RID] = []
	for c in cars:
		if is_instance_valid(c):
			ex.append(c.get_rid())
	_ray.exclude = ex
	_ray.collision_mask = 4
	var hit := me.get_world_3d().direct_space_state.intersect_ray(_ray)
	var col: Object = hit.get("collider") if not hit.is_empty() else null
	if col is StaticBody3D and not (col is AnimatableBody3D):
		var hp: Vector3 = hit["position"]
		if absf(_lat(hp, _project(hp, f.s)) - my_lat) < me.data.body_size.x * 0.5 + 0.4:
			lim = minf(lim, _follow_speed(_ray.from.distance_to(hp) - me.data.body_size.z * 0.5 + 1.0, 0.0, v))
	return lim


# ------------------------------------------------------------------ recovery

func _recover(k: int, dt: float, held: bool) -> void:
	var car := cars[k]
	var f := followers[k]
	var p := car.global_position
	var s := f.s
	var on := road.point_at(s)
	var lat := _lat(p, s)
	var near := absf(lat) < road.width * 0.5 + 6.0
	# Below the road it follows (tunnels lie far under the terrain height), else below the ground.
	var ref := on.y if near else float(Game.world.height_at(p.x, p.z))
	var fell := p.y < ref - 6.0
	var wet := p.y < float(Game.world.water_level_at(p.x, p.z)) - WATER_DEPTH
	var off := absf(lat) > road.width * 0.5 + OFF_LATERAL or (near and absf(p.y - on.y) > 5.0)
	if off and _off_t[k] == 0.0:
		_off_s[k] = s
	_off_t[k] = _off_t[k] + dt if off else 0.0
	_wet_t[k] = _wet_t[k] + dt if (fell or wet) else 0.0
	_flip_t[k] = _flip_t[k] + dt if car.global_basis.y.y < 0.2 else 0.0
	var heading := (-car.global_basis.z).dot(road.flat_tangent_at(s) * dir)
	_wrong_t[k] = _wrong_t[k] + dt if heading < -0.2 else 0.0
	_stuck[k] = _stuck[k] + dt if car.speed_ms < 1.5 and not held and _backoff[k] <= 0.0 and _retreat[k] <= 0.0 else 0.0
	var reason := ""
	var target_s := s
	if _wet_t[k] > WET_TIME:
		reason = "fell" if fell else "water"
	elif _flip_t[k] > 1.0 and car.speed_ms < 3.0:
		reason = "flipped"
	elif _stuck[k] > STUCK_TIME:
		reason = "stuck"
	elif _face_t[k] > STANDOFF_TIME:
		reason = "stand-off"
	elif _wrong_t[k] > WRONG_TIME:
		reason = "wrong way"
	elif _off_t[k] > OFF_TIME:
		reason = "off route"
		# Back where it left the road (no gain from a cut across country).
		if (_off_s[k] - s) * dir < 0.0:
			target_s = _off_s[k]
	if reason == "":
		_wait_t[k] = 0.0
		return
	_wait_t[k] += dt
	var urgent := reason == "fell" or reason == "water"
	if not urgent and _wait_t[k] < VIEW_WAIT and _in_view(p + Vector3.UP * 0.7):
		return
	var spot := _free_spot(k, target_s, not urgent and _wait_t[k] < VIEW_WAIT)
	if spot.is_empty():
		return
	var s2: float = spot["s"]
	var xf: Transform3D = spot["xf"]
	var fwd := -xf.basis.z
	var cap := minf(_corner_limit(s2, 15.0, _lat_now[k]), f.target_speed)
	# Back up to road speed after a fall / run-off; a stuck, flipped or spun car restarts slowly.
	var v_floor := minf(10.0, cap) if reason in ["fell", "water", "off route"] else 0.0
	var v_place := clampf(car.linear_velocity.dot(fwd), v_floor, cap) * 0.85
	f.s = s2
	f.lane_offset = _line[k]
	_cur[k] = _line[k]
	_swing[k] = 0.0
	car.place_at(xf, fwd * v_place)
	recoveries[k] += 1
	print("[activity] rival %s recovered (%s) %.0f m back onto its line at s %.0f, %.0f km/h" % [car.name, reason,
		p.distance_to(xf.origin), s2, v_place * 3.6])
	_stuck[k] = 0.0
	_off_t[k] = 0.0
	_wet_t[k] = 0.0
	_flip_t[k] = 0.0
	_wrong_t[k] = 0.0
	_wait_t[k] = 0.0
	_backoff[k] = 0.0
	_retreat[k] = 0.0
	_close_t[k] = 0.0
	_face_t[k] = 0.0


## A clear spot on rival k's line at (or behind, else just ahead of) arclength s: {s, xf} or {} when every
## candidate is occupied (or in view while `hidden` is required).
func _free_spot(k: int, s: float, hidden: bool) -> Dictionary:
	for back: float in [0.0, -12.0, -24.0, 12.0, -36.0, -48.0, 24.0]:
		var sc := s + dir * back
		if not road.loop and (sc < 3.0 or sc > road.length - 3.0):
			continue
		var xf := _surface_xf(sc, _line[k])
		if not _spot_clear(k, xf.origin):
			continue
		if hidden and _in_view(xf.origin + Vector3.UP * 0.7):
			continue
		return {"s": sc, "xf": xf}
	return {}


## Transform resting on the road surface at arclength s, lateral `line` (travel-relative), facing the travel way.
func _surface_xf(s: float, line: float) -> Transform3D:
	var fwd := road.flat_tangent_at(s) * dir
	var base := road.surface_point(s, line * dir)
	_ray.from = base + Vector3.UP * 2.5
	_ray.to = base + Vector3.DOWN * 3.0
	_ray.collision_mask = 1
	_ray.exclude = []
	var hit := (Game.world as Node3D).get_world_3d().direct_space_state.intersect_ray(_ray)
	if hit.is_empty():
		return Transform3D(Basis.looking_at(fwd, Vector3.UP), base + Vector3.UP * 0.3)
	var n: Vector3 = hit["normal"]
	return Transform3D(Basis.looking_at(fwd.slide(n).normalized(), n), (hit["position"] as Vector3) + n * 0.05)


func _spot_clear(k: int, p: Vector3) -> bool:
	for o in _others(k):
		if o.global_position.distance_to(p) < 9.0:
			return false
	return _traffic_near(p, 10.0).is_empty()


## The player's camera can see point p (in the frustum, within VIEW_DIST, not hidden behind terrain / roads).
func _in_view(p: Vector3) -> bool:
	var rig: Node = Game.camera_rig
	if rig == null:
		return false
	var cam: Camera3D = rig.get("camera")
	if cam == null or not cam.is_inside_tree():
		return false
	var cp := cam.global_position
	if cp.distance_to(p) > VIEW_DIST or cam.is_position_behind(p) or not cam.is_position_in_frustum(p):
		return false
	_ray.from = cp
	_ray.to = p
	_ray.collision_mask = 1
	_ray.exclude = []
	return cam.get_world_3d().direct_space_state.intersect_ray(_ray).is_empty()


## Finished rivals leave once they are well past the finish (or RETIRE_TIME after finishing), every rival once the
## race is over - and only where nobody sees them go: out of the camera's view for LEAVE_UNSEEN seconds and not
## right beside the player (a look-back camera would catch it).
func _retire(k: int, race_time: float, dt: float) -> bool:
	var car := cars[k]
	if not released and (followers[k].s - finish_s) * dir <= RETIRE_DIST and race_time - finish_times[k] <= RETIRE_TIME:
		return false
	_unseen[k] = 0.0 if _in_view(car.global_position + Vector3.UP * 0.7) else _unseen[k] + dt
	var pc := Game.player_car
	if _unseen[k] < LEAVE_UNSEEN or (pc != null and is_instance_valid(pc) and car.global_position.distance_to(pc.global_position) < LEAVE_NEAR):
		return false
	car.queue_free()
	cars[k] = null
	return true


# ------------------------------------------------------------------ world colliders / holds

## Terrain colliders only stream around the player and these points: register the rivals far from the player.
func _update_physics_points() -> void:
	var w := Game.world as World
	if w == null:
		return
	var pts := w.extra_physics_points
	for p in _phys_points:
		var i := pts.find(p)
		if i >= 0:
			pts.remove_at(i)
	_phys_points.clear()
	var pc := Game.player_car
	for car in cars:
		if is_instance_valid(car) and not car.is_queued_for_deletion() and (pc == null or car.global_position.distance_to(pc.global_position) > PHYS_POINT_MIN):
			_phys_points.append(car.global_position)
	pts.append_array(_phys_points)


func _clear_physics_points() -> void:
	var w := Game.world as World
	if w == null:
		return
	for p in _phys_points:
		var i := w.extra_physics_points.find(p)
		if i >= 0:
			w.extra_physics_points.remove_at(i)
	_phys_points.clear()


## Overlay hold (menu / map / console open mid-race): rivals freeze in place and resume with their speed.
func set_hold(on: bool) -> void:
	if on == _holding:
		return
	_holding = on
	if on:
		_hold.clear()
		for car in cars:
			_hold.append(ActivityBase.hold_car(car) if is_instance_valid(car) else {})
		return
	for snap in _hold:
		ActivityBase.release_car(snap)
	_hold.clear()


## Number of rivals ahead of the player (finished rivals count when they finished first).
func ahead_of(player_s: float, race_time: float, player_finished: bool) -> int:
	var n := 0
	for k in followers.size():
		if finish_times[k] >= 0.0:
			if not player_finished or finish_times[k] <= race_time:
				n += 1
		elif not player_finished and (followers[k].s - player_s) * dir > 0.0:
			n += 1
	return n


## The race is over (finish or cancel): the rivals cruise on along their lines - still giving way and passing like
## in the race - and each leaves once out of the player's view (_retire). `owner` (the activity manager) drives
## them through cruise(); without one they are removed at once.
func release(owner: Node) -> void:
	set_hold(false)
	released = true
	if owner == null or not owner.is_inside_tree() or not owner.has_method("adopt_cruisers"):
		_clear_physics_points()
		for c in cars:
			if is_instance_valid(c):
				c.queue_free()
		cars.clear()
		return
	# Cancelled on the grid: the field drives off from there.
	go()
	owner.call("adopt_cruisers", self)


## One physics step of the rivals cruising off after the race; false once all of them have left.
func cruise(dt: float) -> bool:
	physics(dt, 0.0, 0.0)
	for c in cars:
		if is_instance_valid(c):
			return true
	_clear_physics_points()
	return false


## Head / tail lamps like traffic: on when the environment asks for lights at the car (dusk, night, fog, rain or a
## tunnel ahead).
func update_lights() -> void:
	var env: Node = Game.env
	if env == null:
		return
	var by_pos := env.has_method("lights_needed")
	for car in cars:
		if is_instance_valid(car):
			car.headlights_on = bool(env.call("lights_needed", car.global_position)) if by_pos else bool(env.call("is_night"))
