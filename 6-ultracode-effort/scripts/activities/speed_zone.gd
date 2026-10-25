extends "res://scripts/activities/activity_base.gd"
## Speed zone: two arches 600-1200 m apart; average speed between them, from either end.
## Fails when the player leaves the road for too long, drives the wrong way or stalls.

const OFFROAD_LIMIT := 3.0
const REVERSE_LIMIT := 1.0

var _start := 0
var _end := 1
var _sign := 1.0
var _len := 1.0
var _t := 0.0
var _off_t := 0.0
var _rev_t := 0.0
var _prog := 0.0


func build() -> void:
	var banner := "SPEED ZONE" if data.kind == &"speed_zone" else "DRIFT ZONE"
	gates.append(manager.make_gate(self, 0, gate_s(0), &"arch", banner, true, 1))
	gates.append(manager.make_gate(self, 1, gate_s(1), &"arch", banner, true, -1))


func on_gate(index: int, car: CarController, along: float) -> void:
	if running:
		if index == _end and _prog > _len * 0.85:
			_complete(car)
		return
	if cooldown > 0.0:
		return
	var other := 1 - index
	var s_dir := signf(gate_s(other) - gate_s(index))
	if along * s_dir < 3.0:
		return
	if not begin():
		return
	_start = index
	_end = other
	_sign = s_dir
	_len = absf(gate_s(other) - gate_s(index))
	_t = 0.0
	_off_t = 0.0
	_rev_t = 0.0
	_prog = 0.0
	tracker.reset(road, gate_s(index))
	manager.flash_gate(gates[index], 1.0)
	_on_start(car)


func _on_start(_car: CarController) -> void:
	pass


func physics(dt: float, car: CarController) -> void:
	_t += dt
	var pos := car.global_position
	tracker.update(pos)
	_prog = (tracker.s - gate_s(_start)) * _sign
	if absf(tracker.lateral(pos)) > half_width + 3.5:
		_off_t += dt
	else:
		_off_t = maxf(_off_t - dt * 0.5, 0.0)
	if car.linear_velocity.dot(road.flat_tangent_at(tracker.s)) * _sign < -1.5:
		_rev_t += dt
	else:
		_rev_t = 0.0
	if _off_t > _offroad_limit():
		cancel("Zone failed - you left the road")
		return
	if _rev_t > REVERSE_LIMIT:
		cancel("Zone failed - wrong way")
		return
	if _t > maxf(_len / 5.0, 40.0):
		cancel("Zone failed - too slow")
		return
	if _prog >= _len:
		_complete(car)
		return
	_tick(dt, car)


func _offroad_limit() -> float:
	return OFFROAD_LIMIT


func discovery_points() -> PackedVector3Array:
	return PackedVector3Array([gate_position(0), gate_position(1)])


func respawn_point() -> Dictionary:
	if not running:
		return {}
	var lane := road.lane_offset(1) * _sign if road.traffic else 0.0
	return {"position": road.surface_point(tracker.s, lane), "forward": road.flat_tangent_at(tracker.s) * _sign}


## A rewind would falsify the average (the clock and the distance no longer match): the zone ends.
func on_rewind() -> void:
	if running:
		cancel("Rewind used - %s cancelled" % kind_label().to_lower())


func _remaining() -> String:
	return "%s to go" % route_text(_len - maxf(_prog, 0.0))


func _tick(_dt: float, _car: CarController) -> void:
	var avg := maxf(_prog, 0.0) / maxf(_t, 0.001) * 3.6
	hud(speed_text(avg), "Average speed  ·  %s  ·  %s" % [_remaining(), target_text(avg, true, speed_text, speed_shown)],
		clampf(_prog / _len, 0.0, 1.0))


func _complete(_car: CarController) -> void:
	manager.flash_gate(gates[_end], 1.0)
	var avg := _len / maxf(_t, 0.001) * 3.6
	finish(avg, true, speed_text(avg) + " average", -1, "", speed_shown)
