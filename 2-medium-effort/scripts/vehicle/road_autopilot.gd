class_name RoadAutopilot
extends RefCounted
## Simple pure-pursuit driver that follows a road lane. Used by drive tests, the QA runner and race rivals.

var world: WorldData
var road: int = 0
var s: float = 0.0
var dir: int = 1  # +1 along the road, -1 against
var target_speed: float = 25.0  # m/s cap
var lane_offset: float = 1.6
var route: Array = []  # optional list of [road, dir] to follow after the current one
var finished: bool = false


func _init(w: WorldData, ri: int, start_s: float, d: int = 1) -> void:
	world = w
	road = ri
	s = start_s
	dir = d
	lane_offset = w.roads[ri].lane * 0.5


func update(car: Car, delta: float) -> void:
	var r: Dictionary = world.roads[road]
	var pos: Vector3 = car.global_position
	# advance s to the closest point near the previous estimate
	var best_s: float = s
	var best_d: float = 1e9
	var k: float = -12.0
	while k <= 30.0:
		var ss: float = clampf(s + k * dir, 0.0, r.length)
		var p: Vector3 = world.road_point(road, ss, lane_offset * dir).origin
		var d: float = Vector2(p.x - pos.x, p.z - pos.z).length_squared()
		if d < best_d:
			best_d = d
			best_s = ss
		k += 2.0
	s = best_s
	var spd: float = car.linear_velocity.length()
	var look: float = clampf(6.0 + spd * 0.55, 8.0, 40.0)
	var ts: float = s + look * dir
	if ts > r.length or ts < 0.0:
		if not route.is_empty():
			var nxt: Array = route.pop_front()
			road = nxt[0]
			dir = nxt[1]
			s = 0.0 if dir > 0 else world.roads[road].length
			lane_offset = world.roads[road].lane * 0.5
			return
		finished = (dir > 0 and s > r.length - 6.0) or (dir < 0 and s < 6.0)
		ts = clampf(ts, 0.0, r.length)
	var tp: Vector3 = world.road_point(road, ts, lane_offset * dir).origin
	var to: Vector3 = tp - pos
	var fwd: Vector3 = -car.global_transform.basis.z
	var rt: Vector3 = car.global_transform.basis.x
	var ang: float = atan2(to.dot(rt), to.dot(fwd))
	car.in_steer = clampf(ang * 2.2, -1.0, 1.0)
	# corner speed from curvature ahead
	var maxk: float = 0.0
	var curv: PackedFloat32Array = r.curv
	var i0: int = int(s / WorldData.STEP)
	for j in range(0, int(clampf(spd * 3.0, 20.0, 150.0) / WorldData.STEP)):
		var ii: int = clampi(i0 + j * dir, 0, curv.size() - 1)
		maxk = maxf(maxk, absf(curv[ii]))
	var mu: float = car.def.grip * 0.85 * (car.weather_grip if car.surface_now < 2 else 0.75)
	var v_corner: float = sqrt(mu * 9.81 / maxf(maxk, 0.0005))
	var vt: float = minf(target_speed, v_corner)
	var err: float = vt - spd
	car.in_throttle = clampf(err * 0.35, 0.0, 1.0)
	car.in_brake = clampf(-err * 0.18, 0.0, 1.0)
	car.in_handbrake = false
