extends "res://scripts/activities/activity_base.gd"
## Danger sign: a warning board ~135 m before a road crest or a festival ramp (tracks without traffic).
## Passing it arms the jump; takeoff is detected when all wheels leave the ground near the crest / off the ramp
## lip with the car upright, the score is the horizontal distance to the upright landing point. Rolling over
## (or a reset) ends the attempt without a score. Festival ramps have a drivable back slope and a "RAMP AHEAD"
## board for drivers coming the other way.

const AIR_MIN := 0.1
const LAND_HOLD := 0.08
const CREST_WINDOW := 70.0
## Ramp takeoffs count only off the lip: car origin from LIP_BEFORE before to LIP_AFTER past it (m along the road).
const LIP_BEFORE := 2.5
const LIP_AFTER := 8.0
## Back slope length behind the lip when the event data has none (m).
const RAMP_BACK := 10.0
## Distance of the reverse-direction warning board beyond the foot of the back slope (m).
const WARN_DIST := 65.0
## Car up-vector height (basis.y.y): takeoff needs UP_TAKEOFF, a landing UP_LAND; below CRASH_UP for
## CRASH_TIME (approach or flight) is a wipe-out.
const UP_TAKEOFF := 0.85
const UP_LAND := 0.8
const CRASH_UP := 0.55
const CRASH_TIME := 0.25

var _t := 0.0
var _air_t := 0.0
var _ground_t := 0.0
var _crash_t := 0.0
var _flying := false
var _takeoff_ok := false
var _takeoff := Vector3.ZERO
## Car origin when its rear axle crossed the ramp lip: the takeoff point of a ramp jump (the rear wheels' rays
## keep touching the back slope for a few centimetres after the lip; a car bouncing off the deck flies over it).
var _lip_cross := Vector3.INF
var _land := Vector3.ZERO
var _dist := 0.0
## Speed when the car left the ground (at the lip for ramp jumps): the "at N km/h" of the result.
var _takeoff_kmh := 0.0
var _lip_kmh := 0.0


func build() -> void:
	gates.append(manager.make_gate(self, 0, gate_s(0), &"sign", "", true, data.dir))
	gates.append(manager.make_gate(self, 1, gate_s(1), &"crest", "", false, data.dir, false))
	if _is_ramp():
		manager.make_ramp(self, gate_s(1), data.dir, float(data.extra.get("ramp_len", 11.0)), float(data.extra.get("ramp_height", 1.6)), _ramp_back())
		# Drivers coming the other way meet the back slope first: warn them on their side of the track.
		gates.append(manager.make_gate(self, 2, gate_s(1) + data.dir * (_ramp_back() + WARN_DIST), &"ramp_warn", "", false, -data.dir, false))


func _is_ramp() -> bool:
	return bool(data.extra.get("ramp", false))


func _ramp_back() -> float:
	return float(data.extra.get("ramp_back", RAMP_BACK))


func map_position() -> Vector3:
	return gate_position(1)


func discovery_points() -> PackedVector3Array:
	return PackedVector3Array([gate_position(0), gate_position(1)])


func on_gate(index: int, car: CarController, along: float) -> void:
	if index != 0 or running or cooldown > 0.0:
		return
	if along * data.dir < 4.0:
		return
	if not begin():
		return
	_t = 0.0
	_air_t = 0.0
	_ground_t = 0.0
	_crash_t = 0.0
	_flying = false
	_lip_cross = Vector3.INF
	_dist = 0.0
	_takeoff_kmh = 0.0
	_lip_kmh = 0.0
	tracker.reset(road, gate_s(0))
	manager.flash_gate(gates[0], 1.0)
	print("[activity] %s armed at %.0f km/h" % [data.id, car.get_speed_kmh()])


## A reset ends the attempt: the reset spot must never count as a takeoff or a landing.
func respawn_point() -> Dictionary:
	if running:
		cancel("Jump cancelled - car reset")
	return {}


func on_rewind() -> void:
	if running:
		cancel("Rewind used - jump cancelled")


## Takeoff spot check: off the ramp lip over its deck, or anywhere near a natural crest.
func _takeoff_zone(past_crest: float, lateral: float) -> bool:
	if not _is_ramp():
		return absf(past_crest) < CREST_WINDOW
	return past_crest > -LIP_BEFORE and past_crest < LIP_AFTER and absf(lateral) <= manager.ramp_width(road) * 0.5


## Along-road distance of the car's rear axle past the ramp lip (negative before it).
func _rear_past_lip(car: CarController) -> float:
	var lip := gate_position(1)
	var f := gate_forward(1) * data.dir
	var past := INF
	for w in car.wheels:
		if not w.front:
			past = minf(past, (car.global_transform * w.mount - lip).dot(f))
	return past


func physics(dt: float, car: CarController) -> void:
	_t += dt
	if car.freeze:
		# Car held frozen (wheel state stale): nothing counts; a hold mid-air re-arms the jump.
		_flying = false
		_air_t = 0.0
		_ground_t = 0.0
		_crash_t = 0.0
		_lip_cross = Vector3.INF
		return
	var pos := car.global_position
	var up := car.global_basis.y.y
	tracker.update(pos)
	var past_crest := (tracker.s - gate_s(1)) * data.dir
	if up < CRASH_UP:
		_crash_t += dt
		if _crash_t >= CRASH_TIME:
			cancel("Wiped out - jump not counted")
			return
	else:
		_crash_t = 0.0
	if _is_ramp() and _lip_cross == Vector3.INF and _rear_past_lip(car) >= 0.0:
		_lip_cross = pos
		_lip_kmh = car.get_speed_kmh()
		if _flying or _air_t > 0.0:
			# Bounced off the deck just before the lip: the jump is still measured from the lip.
			_takeoff = pos
			_takeoff_kmh = _lip_kmh
	if not _flying:
		if car.wheels_on_ground == 0 and up >= UP_TAKEOFF:
			if _air_t == 0.0:
				_takeoff = pos
				_takeoff_kmh = car.get_speed_kmh()
				if _lip_cross != Vector3.INF and pos.distance_to(_lip_cross) < 3.0:
					_takeoff = _lip_cross
					_takeoff_kmh = _lip_kmh
				_takeoff_ok = _takeoff_zone(past_crest, tracker.lateral(pos))
			_air_t += dt
			if _air_t >= AIR_MIN and _takeoff_ok:
				_flying = true
				_ground_t = 0.0
				manager.flash_gate(gates[1], 1.0)
				print("[activity] %s takeoff %.1f m past the %s at %.0f km/h" % [data.id, (_takeoff - gate_position(1)).dot(gate_forward(1) * data.dir),
					"lip" if _is_ramp() else "crest", _takeoff_kmh])
		else:
			_air_t = 0.0
		if past_crest > CREST_WINDOW + 40.0 or _t > 20.0:
			cancel("No air - hit the %s faster" % ("ramp" if _is_ramp() else "crest"))
			return
		hud(speed_text(car.get_speed_kmh()), "Hit the %s  ·  %s  ·  %s" % ["ramp" if _is_ramp() else "crest", near_text(-past_crest),
			target_text(0.0, true, dist_text, dist_shown)], -1.0)
		return
	_dist = Vector2(pos.x - _takeoff.x, pos.z - _takeoff.z).length()
	if car.wheels_on_ground >= 2 and up >= UP_LAND:
		if _ground_t == 0.0:
			_land = pos
		_ground_t += dt
		if _ground_t >= LAND_HOLD:
			var d := Vector2(_land.x - _takeoff.x, _land.z - _takeoff.z).length()
			print("[activity] %s landed %.1f m past the %s" % [data.id, (_land - gate_position(1)).dot(gate_forward(1) * data.dir), "lip" if _is_ramp() else "crest"])
			finish(d, true, dist_text(d), -1, "at %s" % speed_text(_takeoff_kmh), dist_shown)
			return
	else:
		_ground_t = 0.0
	if _t > 30.0:
		cancel("Jump abandoned")
		return
	hud(dist_text(_dist), "Airborne!  ·  " + target_text(_dist, true, dist_text, dist_shown), -1.0)
