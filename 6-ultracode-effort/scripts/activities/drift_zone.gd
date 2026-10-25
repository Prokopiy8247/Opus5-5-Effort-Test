extends "res://scripts/activities/speed_zone.gd"
## Drift zone: same two-arch section as a speed zone, scored on drifting.
## Points accrue while body slip > 12 deg and speed > 30 km/h (slip x speed x dt) into a chain; the combo
## grows with sustained drifting. A chain is banked (x combo) after > 2 s of straight driving and lost on a crash.

const MIN_SLIP := 12.0
const MIN_KMH := 30.0
const STRAIGHT_RESET := 2.0
const POINTS := 0.5
const CRASH := 2.5

var _banked := 0.0
var _chain := 0.0
var _combo := 1.0
var _drift_t := 0.0
var _straight_t := 0.0
var _msg := ""
var _msg_t := 0.0


func _on_start(_car: CarController) -> void:
	_banked = 0.0
	_chain = 0.0
	_combo = 1.0
	_drift_t = 0.0
	_straight_t = 0.0
	_msg_t = 0.0


func _offroad_limit() -> float:
	return 4.0


func _tick(dt: float, car: CarController) -> void:
	var slip := absf(car.body_slip_deg)
	var kmh := car.get_speed_kmh()
	if slip > MIN_SLIP and slip < 85.0 and kmh > MIN_KMH and car.wheels_on_ground >= 2:
		_chain += minf(slip, 60.0) * kmh * dt * POINTS
		_drift_t += dt
		_straight_t = 0.0
		_combo = minf(1.0 + floorf(_drift_t / 1.5) * 0.5, 5.0)
	else:
		_straight_t += dt
		if _straight_t > STRAIGHT_RESET and _chain > 0.0:
			_bank()
	_msg_t = maxf(_msg_t - dt, 0.0)
	var total := _banked + _chain * _combo
	var line := "x%.1f combo  ·  chain %s" % [_combo, fmt_int(int(_chain))] if _chain > 0.0 else "Drift to score"
	if _msg_t > 0.0:
		line = _msg
	hud(fmt_int(int(total)) + " pts", "%s  ·  %s  ·  %s" % [line, _remaining(), target_text(total, true, _pts)],
		clampf(_prog / _len, 0.0, 1.0))


func _bank() -> void:
	if _chain > 0.0:
		_msg = "Banked %s" % fmt_int(int(_chain * _combo))
		_msg_t = 1.5
	_banked += _chain * _combo
	_chain = 0.0
	_combo = 1.0
	_drift_t = 0.0


func on_impact(strength: float) -> void:
	if running and strength > CRASH and _chain > 0.0:
		_chain = 0.0
		_combo = 1.0
		_drift_t = 0.0
		_msg = "Chain lost!"
		_msg_t = 1.5


func _complete(_car: CarController) -> void:
	_bank()
	manager.flash_gate(gates[_end], 1.0)
	if _banked < 1.0:
		cancel("No drift score - hold a slide through the zone")
		return
	finish(_banked, true, "%s pts" % fmt_int(int(_banked)))


static func _pts(v: float) -> String:
	return "%s pts" % fmt_int(int(v))
