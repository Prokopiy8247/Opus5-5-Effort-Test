class_name RoadFollower
extends RefCounted
## Drives a CarController along a road lane (pure pursuit steering + curvature-limited speed).
## Shared by AI traffic (physics LOD) and the QA autopilot.
## Road mode: setup() + drive() track the lane themselves. Traffic mode: the traffic manager sets
## `target_fn` (look-ahead point on its lane-graph path) and `speed_cap`, and owns the progress.

var road: RoadNetwork.Road
var s: float = 0.0
## +1 = travel in increasing s on the right-hand lane, -1 = opposite direction.
var dir: int = 1
var lane_offset: float = 2.0
var target_speed: float = 22.0
var lat_accel: float = 4.5
## Optional obstacle speed limit (m/s) set by the traffic manager each tick.
var obstacle_limit: float = INF
var finished: bool = false
## Traffic mode: Callable(distance_ahead: float) -> Vector3 steering target.
var target_fn: Callable = Callable()
## Traffic mode: curve / junction speed cap (m/s).
var speed_cap: float = INF
var max_throttle: float = 1.0
## Pure-pursuit look-ahead = look_base + look_gain * speed (m).
var look_base: float = 7.0
var look_gain: float = 0.55
## Road mode only: slow down for traffic vehicles ahead in the lane (QA autopilot, race rivals).
var respect_traffic: bool = true


func setup(r: RoadNetwork.Road, start_s: float, direction: int, offset: float) -> void:
	road = r
	s = start_s
	dir = direction
	lane_offset = offset


## Track the closest arclength near the previous one (avoids jumping between hairpin legs).
func _track(car_pos: Vector3) -> void:
	var best := s
	var bd := INF
	var step := road.ds
	for k in range(-6, 13):
		var cand := s + dir * k * step
		if not road.loop and (cand < 0.0 or cand > road.length):
			continue
		var p := road.point_at(cand)
		var d := Vector2(p.x - car_pos.x, p.z - car_pos.z).length_squared()
		if d < bd:
			bd = d
			best = cand
	s = best
	if not road.loop and (s >= road.length - 2.0 or s <= 1.0) and dir != 0:
		finished = (dir > 0 and s >= road.length - 2.0) or (dir < 0 and s <= 1.0)


func lane_point(at_s: float) -> Vector3:
	return road.surface_point(at_s, lane_offset * dir)


## Max comfortable speed for the curvature in the next `dist` metres.
func curve_speed(dist: float) -> float:
	var v := target_speed
	var k := 0.0
	var a := road.flat_tangent_at(s)
	var steps := int(dist / 12.0)
	for i in range(1, steps + 1):
		var b := road.flat_tangent_at(s + dir * i * 12.0)
		var ang := a.angle_to(b)
		var curv := ang / (i * 12.0)
		k = maxf(k, curv)
		var vk := sqrt(lat_accel / maxf(curv, 0.0001))
		# Allow braking distance: v^2 = vk^2 + 2*a*d
		v = minf(v, sqrt(vk * vk + 2.0 * 5.0 * maxf(i * 12.0 - 15.0, 0.0)))
	return v


## Speed that keeps a time gap to a leader `gap` metres ahead (bumper to bumper) and can still stop
## behind it. Shared with the traffic manager.
static func follow_speed(gap: float, lead_v: float, own_v: float, time_gap: float) -> float:
	var room := gap - 3.0
	if room <= 0.0:
		return 0.0
	var lv := maxf(lead_v, 0.0)
	var keep := lv + (room - own_v * time_gap) / 2.5
	var stop := sqrt(lv * lv + 6.0 * room)
	return clampf(minf(keep, stop), 0.0, 90.0)


func drive(car: CarController, _delta: float) -> void:
	var pos := car.global_position
	var spd := car.linear_velocity.length()
	var look := look_base + spd * look_gain
	var target: Vector3
	var want: float
	if target_fn.is_valid():
		target = target_fn.call(look)
		want = minf(minf(target_speed, speed_cap), obstacle_limit)
	else:
		_track(pos)
		target = lane_point(s + dir * look)
		want = minf(curve_speed(look + spd * 2.5), obstacle_limit)
		if respect_traffic:
			want = minf(want, _traffic_limit(car, pos, spd))
	var fwd := -car.global_transform.basis.z
	fwd.y = 0.0
	var to := target - pos
	to.y = 0.0
	var ang := fwd.normalized().signed_angle_to(to.normalized(), Vector3.UP)
	# Positive signed angle = target to the left -> negative (left) steering input.
	if target_fn.is_valid():
		# Geometric pure pursuit (traffic): wheel angle for the arc through the target, scaled by the
		# car's speed-dependent steering range so curves are tracked without cutting.
		var sa := sin(ang) if absf(ang) < PI * 0.5 else signf(ang)
		var wheel := atan(2.0 * car.data.wheelbase * sa / maxf(look, 1.0))
		var t := clampf((absf(car.forward_speed) - 4.0) / 50.0, 0.0, 1.0)
		var range_deg := lerpf(car.data.max_steer_deg, car.data.high_speed_steer_deg, pow(t, 0.75)) if car.assist_steer \
			else lerpf(car.data.max_steer_deg, car.data.high_speed_steer_deg * 1.6, pow(t, 0.9))
		car.in_steer = clampf(-wheel / deg_to_rad(range_deg), -1.0, 1.0)
	else:
		var max_steer := deg_to_rad(car.data.max_steer_deg)
		car.in_steer = clampf(-ang / max_steer * 1.6, -1.0, 1.0)
	car.in_handbrake = 0.0
	if want < 0.3 and spd < 1.2:
		# Hold at a standstill. Brake stays below the 0.3 that selects reverse when stopped.
		car.in_throttle = 0.0
		car.in_brake = 0.25
		car.in_handbrake = 1.0
		return
	var err := want - spd
	if err > 0.0:
		car.in_throttle = clampf(err * 0.35, 0.0, max_throttle)
		car.in_brake = 0.0
	else:
		car.in_throttle = 0.0
		car.in_brake = clampf(-err * 0.25, 0.0, 1.0)
		if car.forward_speed < 1.5:
			car.in_brake = minf(car.in_brake, 0.25)


## Road mode: speed limit from traffic vehicles in this lane ahead (keeps the QA autopilot and race rivals from
## rear-ending civilian traffic, also round bends a straight probe would miss).
func _traffic_limit(car: CarController, pos: Vector3, spd: float) -> float:
	var t: Node = Game.traffic
	if t == null or not t.has_method("obstacles_near"):
		return INF
	var lim := INF
	var reach := 26.0 + spd * 5.0
	for o: Dictionary in t.obstacles_near(pos, reach):
		var op: Vector3 = o["position"]
		# Along-road distance and lane offset of the obstacle (robust on hairpins, unlike straight lines).
		var d := Vector2(op.x - pos.x, op.z - pos.z).length()
		var so := _project(op, s + dir * d)
		var along := (so - s) * dir
		if road.loop:
			along = fposmod(along + road.length * 0.5, road.length) - road.length * 0.5
		if along <= 0.5 or along > reach:
			continue
		var lat := (op - road.point_at(so)).dot(road.right_at(so))
		if absf(lat - lane_offset * dir) > 2.4:
			continue
		var heading: Vector3 = o["heading"]
		var lead_v: float = float(o["speed"]) * maxf(heading.dot(road.flat_tangent_at(so) * dir), 0.0)
		var gap := along - float(o["length"]) * 0.5 - car.data.body_size.z * 0.5
		lim = minf(lim, follow_speed(gap, lead_v, spd, 1.6))
		if lim < 3.0 and t.get("debug") == true and Engine.get_process_frames() % 60 == 0:
			print("[traffic] %s held by vehicle at %s gap %.1f lead %.1f m/s (road %s s %.0f)" % [car.name, str(op.round()), gap, lead_v, road.id, s])
	return lim


func _project(p: Vector3, s_hint: float) -> float:
	var ss := s_hint
	for i in 5:
		var q := road.point_at(ss)
		var t := road.flat_tangent_at(ss)
		var step := clampf((p.x - q.x) * t.x + (p.z - q.z) * t.z, -20.0, 20.0)
		ss = fposmod(ss + step, road.length) if road.loop else clampf(ss + step, 0.0, road.length)
		if absf(step) < 0.05:
			break
	return ss
