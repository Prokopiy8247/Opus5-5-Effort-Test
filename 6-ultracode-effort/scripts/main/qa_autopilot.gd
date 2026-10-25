extends RefCounted
## QA autopilot: drives the player car along one road's right-hand lane as fast as the road allows.
## Bicycle-model pure pursuit steering, curvature + gradient aware speed planning, re-acquires the road
## from the network if the car leaves it. Used by QaDirector "drive" (and the debug benchmark).

var road: RoadNetwork.Road
var network: RoadNetwork
var s: float = 0.0
var lane: float = 2.0
var target_speed: float = 40.0
var lat_accel: float = 7.0
var decel: float = 6.0
var off_road: float = 0.0
var finished: bool = false


func setup(net: RoadNetwork, r: RoadNetwork.Road, start_s: float) -> void:
	network = net
	road = r
	s = start_s
	lane = r.lane_offset(1) if r.traffic else 0.0


func lane_point(at: float) -> Vector3:
	return road.surface_point(at, lane)


func _track(pos: Vector3) -> void:
	var best := s
	var bd := INF
	for k in range(-10, 30):
		var c := s + k * road.ds
		if not road.loop and (c < 0.0 or c > road.length):
			continue
		var p := road.point_at(c)
		var d := Vector2(p.x - pos.x, p.z - pos.z).length_squared()
		if d < bd:
			bd = d
			best = c
	s = best
	off_road = sqrt(bd)
	finished = not road.loop and s >= road.length - 3.0
	if off_road > 25.0:
		# Lost: re-acquire on the same road anywhere.
		var res := network.nearest(pos, 400.0, func(rr: RoadNetwork.Road) -> bool: return rr == road)
		if not res.is_empty():
			s = res["s"]


func _plan_speed(spd: float) -> float:
	var v := target_speed
	var a := road.flat_tangent_at(s)
	var dist := 0.0
	var step := 8.0
	var horizon := 40.0 + spd * spd / (2.0 * decel) * 1.4
	var prev := a
	while dist < horizon:
		dist += step
		var t := road.flat_tangent_at(s + dist)
		var curv := prev.angle_to(t) / step
		prev = t
		var g := (road.point_at(s + dist + 2.0).y - road.point_at(s + dist - 2.0).y) / 4.0
		var dec := maxf(decel + g * 9.81 * 0.8, 2.5)   # downhill reduces available deceleration
		var vk := sqrt(lat_accel / maxf(curv, 0.00008))
		v = minf(v, sqrt(vk * vk + 2.0 * dec * maxf(dist - 6.0, 0.0)))
	return v


## Speed limit from civilian traffic ahead in this lane (keeps the autopilot from rear-ending it).
func _traffic_limit(car: CarController, pos: Vector3, spd: float) -> float:
	var t: Node = Game.traffic
	if t == null or not t.has_method("obstacles_near"):
		return INF
	var lim := INF
	var reach := 26.0 + spd * 5.0
	for o: Dictionary in t.obstacles_near(pos, reach):
		var op: Vector3 = o["position"]
		var so := s + Vector2(op.x - pos.x, op.z - pos.z).length()
		for k in 5:
			var q := road.point_at(so)
			var tg := road.flat_tangent_at(so)
			so += clampf((op.x - q.x) * tg.x + (op.z - q.z) * tg.z, -20.0, 20.0)
			so = fposmod(so, road.length) if road.loop else clampf(so, 0.0, road.length)
		var along := so - s
		if road.loop:
			along = fposmod(along + road.length * 0.5, road.length) - road.length * 0.5
		if along <= 0.5 or along > reach or absf((op - road.point_at(so)).dot(road.right_at(so)) - lane) > 2.4:
			continue
		var lead_v: float = float(o["speed"]) * maxf((o["heading"] as Vector3).dot(road.flat_tangent_at(so)), 0.0)
		lim = minf(lim, RoadFollower.follow_speed(along - float(o["length"]) * 0.5 - car.data.body_size.z * 0.5, lead_v, spd, 1.6))
	return lim


func drive(car: CarController) -> void:
	var pos := car.global_position
	_track(pos)
	var spd := car.linear_velocity.length()
	var ld := 6.0 + spd * 0.45
	var target := lane_point(s + ld)
	var fwd := -car.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var to := target - pos
	to.y = 0.0
	var alpha := fwd.signed_angle_to(to.normalized(), Vector3.UP)
	var wb := maxf(car.data.wheelbase, 2.0)
	var steer_rad := atan(2.0 * wb * sin(alpha) / maxf(to.length(), 1.0))
	# Express as fraction of the currently available lock (the controller reduces lock with speed).
	var t := clampf((absf(car.forward_speed) - 4.0) / 50.0, 0.0, 1.0)
	var lock := deg_to_rad(lerpf(car.data.max_steer_deg, car.data.high_speed_steer_deg, pow(t, 0.75)))
	car.in_steer = clampf(-steer_rad / maxf(lock, 0.02), -1.0, 1.0)
	var want := minf(_plan_speed(spd), _traffic_limit(car, pos, spd))
	if off_road > 4.0:
		want = minf(want, 8.0)
	var err := want - spd
	car.in_handbrake = 0.0
	if err > 0.0:
		car.in_throttle = clampf(err * 0.4, 0.0, 1.0)
		car.in_brake = 0.0
	else:
		car.in_throttle = 0.0
		car.in_brake = clampf(-err * 0.3, 0.0, 1.0)
		if car.forward_speed < 1.5:
			car.in_brake = minf(car.in_brake, 0.25)
