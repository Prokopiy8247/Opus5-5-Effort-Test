extends Node
## Drives a CarController along a road polyline: pure-pursuit steering, curvature-based speed
## planning with braking look-ahead, lane offset, stuck/flip recovery. Used by the benchmark
## run, QA captures and AI drivers.

var world: Node
var car: CarController
var road_index: int = 0
var lane_offset: float = 0.0
var direction: int = 1
var max_speed_kmh: float = 260.0
var lat_accel: float = 7.5
var brake_decel: float = 8.0
var distance: float = 0.0
var enabled: bool = true

var _i: int = 0
var _stuck: float = 0.0
var _last_pos: Vector3 = Vector3.ZERO
var _xs: PackedFloat32Array
var _ys: PackedFloat32Array
var _zs: PackedFloat32Array
var _n: int = 0
var _closed: bool = false


func _ready() -> void:
	var r: Dictionary = world.get("data").roads[road_index]
	_xs = r["x"]
	_ys = r["y"]
	_zs = r["z"]
	_n = _xs.size()
	_closed = r["closed"]
	if car != null:
		car.control_mode = CarController.ControlMode.AI
		_i = _nearest(car.global_position, 0, _n)
		_last_pos = car.global_position


func _idx(i: int) -> int:
	return posmod(i, _n) if _closed else clampi(i, 0, _n - 1)


func _pt(i: int) -> Vector3:
	var k := _idx(i)
	return Vector3(_xs[k], _ys[k], _zs[k])


func _nearest(p: Vector3, from: int, count: int) -> int:
	var best := from
	var bd := 1e18
	for k in count:
		var i := _idx(from + k)
		var d := Vector2(_xs[i] - p.x, _zs[i] - p.z).length_squared()
		if d < bd:
			bd = d
			best = i
	return best


func _curvature(i: int) -> float:
	var a := _pt(i - 4 * direction)
	var b := _pt(i)
	var c := _pt(i + 4 * direction)
	var d1 := Vector2(b.x - a.x, b.z - a.z)
	var d2 := Vector2(c.x - b.x, c.z - b.z)
	var ang := absf(d1.angle_to(d2))
	return ang / maxf((d1.length() + d2.length()) * 0.5, 1.0)


func _physics_process(delta: float) -> void:
	if car == null or not is_instance_valid(car) or not enabled:
		return
	var p := car.global_position
	# track progress around the current index
	var best := _i
	var bd := 1e18
	for k in range(-6, 14):
		var i := _idx(_i + k * direction)
		var d := Vector2(_xs[i] - p.x, _zs[i] - p.z).length_squared()
		if d < bd:
			bd = d
			best = i
	if bd > 40.0 * 40.0:
		best = _nearest(p, 0, _n)
	_i = best
	if not _closed and ((direction > 0 and _i >= _n - 3) or (direction < 0 and _i <= 2)):
		car.input_throttle = 0.0
		car.input_brake = 1.0
		return
	var v := car.linear_velocity.length()
	var look := 6.0 + v * 0.5
	var steps := maxi(int(look / 2.0), 2)
	var target := _pt(_i + steps * direction)
	var tnext := _pt(_i + (steps + 1) * direction)
	var tdir := (tnext - target).normalized()
	var tright := Vector3(tdir.x, 0, tdir.z).cross(Vector3.UP).normalized()
	target += tright * lane_offset
	var local := car.global_transform.affine_inverse() * target
	var alpha := atan2(local.x, -local.z)
	var wb := 2.6
	var steer_rad := atan(2.0 * wb * sin(alpha) / maxf(look, 1.0))
	var def := car.definition
	var lock := lerpf(def.steer_lock_deg, def.steer_high_speed_deg, pow(clampf(absf(car.forward_speed) / 55.0, 0.0, 1.0), 0.75))
	car.input_steer = clampf(rad_to_deg(steer_rad) / lock, -1.0, 1.0)
	# speed planning
	var v_target := max_speed_kmh / 3.6
	var k := 2
	while k < 90:
		var kap := _curvature(_i + k * direction)
		var v_allow := sqrt(lat_accel / maxf(kap, 1e-4))
		var dist := float(k) * 2.0
		var v_reach := sqrt(v_allow * v_allow + 2.0 * brake_decel * dist)
		v_target = minf(v_target, v_reach)
		k += 3
	var err := v_target - v
	car.input_throttle = clampf(err * 0.35 + 0.2, 0.0, 1.0) if err > -1.0 else 0.0
	car.input_brake = clampf(-err * 0.18, 0.0, 1.0) if err < -1.5 else 0.0
	car.input_handbrake = 0.0
	distance += car.global_position.distance_to(_last_pos)
	# stuck / flipped recovery
	if v < 1.0 and car.input_throttle > 0.5:
		_stuck += delta
	else:
		_stuck = maxf(_stuck - delta, 0.0)
	if _stuck > 3.0 or car.global_transform.basis.y.y < 0.2:
		_stuck = 0.0
		var a := _pt(_i)
		var b2 := _pt(_i + direction * 2)
		var fwd := Vector3(b2.x - a.x, 0, b2.z - a.z).normalized()
		var right := fwd.cross(Vector3.UP).normalized()
		car.reset_to(Transform3D(Basis.looking_at(fwd, Vector3.UP), a + right * lane_offset + Vector3.UP * 0.6), 8.0)
	_last_pos = car.global_position
