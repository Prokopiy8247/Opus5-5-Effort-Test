extends Node
## Drives a Car along a road (QA: full-loop tests, perf runs, attract mode).

var car: Car
var data: WorldData
var road: WorldData.Road
var idx := 0.0
var max_kmh := 170.0
var lat_acc := 6.5
var lane := 0.25
var laps := 0
var _start_idx := 0
var _travelled := 0.0
var stuck_time := 0.0


func setup(c: Car, d: WorldData, road_id: String) -> void:
	car = c
	data = d
	road = d.road_by_id(road_id)
	car.external_input = true
	var best := 0
	var bd := INF
	for i in road.pts.size():
		var dd := road.pts[i].distance_squared_to(car.global_position)
		if dd < bd:
			bd = dd
			best = i
	idx = best
	_start_idx = best


func _physics_process(delta: float) -> void:
	if car == null or road == null:
		return
	var n := road.pts.size()
	var p := car.global_position
	# advance the tracked index while the next sample is closer
	for k in 12:
		var nxt := _wrap(int(idx) + 1)
		if road.pts[nxt].distance_squared_to(p) < road.pts[_wrap(int(idx))].distance_squared_to(p):
			idx = float(nxt)
			_travelled += 4.0
		else:
			break
	if _travelled >= road.length - 8.0:
		laps += 1
		_travelled = 0.0
	var spd := car.speed
	var look := int(4.0 + spd * 0.28)
	var ti := _wrap(int(idx) + look)
	var t := road.tangent(ti)
	var right := Vector3(-t.z, 0.0, t.x)
	var target := road.pts[ti] + right * road.width * lane
	var fwd := -car.global_transform.basis.z
	fwd.y = 0.0
	var to := target - p
	to.y = 0.0
	var ang := fwd.signed_angle_to(to.normalized(), Vector3.UP)
	car.in_steer = clampf(-ang * 2.6, -1.0, 1.0)
	# speed: curvature ahead within braking distance
	var v_target := max_kmh / 3.6
	for k in range(2, 50, 3):
		var a := road.pts[_wrap(int(idx) + k - 2)]
		var b := road.pts[_wrap(int(idx) + k)]
		var c := road.pts[_wrap(int(idx) + k + 2)]
		var d1 := Vector2(b.x - a.x, b.z - a.z)
		var d2 := Vector2(c.x - b.x, c.z - b.z)
		var curv := absf(d1.angle_to(d2)) / maxf((d1.length() + d2.length()) * 0.5, 0.1)
		var vc := sqrt(lat_acc * Game.weather_grip / maxf(curv, 0.0001))
		var allowed := sqrt(vc * vc + 2.0 * 6.0 * k * 4.0)
		v_target = minf(v_target, allowed)
	var err := v_target - spd
	car.in_throttle = clampf(err * 0.35, 0.0, 1.0)
	car.in_brake = clampf(-err * 0.25, 0.0, 1.0)
	car.in_handbrake = 0.0
	if spd < 1.0 and car.in_throttle > 0.5:
		stuck_time += delta
	else:
		stuck_time = 0.0
	if stuck_time > 4.0:
		stuck_time = 0.0
		var xf := data.road_spawn(road, int(idx) + 2, road.width * lane)
		car.teleport(xf)


func _wrap(i: int) -> int:
	var n := road.pts.size()
	return posmod(i, n - 1) if road.closed else clampi(i, 0, n - 1)
