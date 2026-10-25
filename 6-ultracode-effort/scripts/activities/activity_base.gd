extends RefCounted
## Shared behaviour of one road activity. The manager (activity_manager.gd) owns gates and triggers and calls
## build(), on_gate(index, car, along) from the gate triggers, physics(dt, car) while this activity is the
## running session, on_impact(strength) and cancel(reason). `along` = car velocity along the road's +s tangent.

const ActivityData := preload("res://scripts/activities/activity_data.gd")
const RouteTracker := preload("res://scripts/activities/route_tracker.gd")

const KIND_LABEL := {
	&"speed_trap": "Speed Trap", &"speed_zone": "Speed Zone", &"drift": "Drift Zone", &"jump": "Danger Sign",
	&"race": "Road Race", &"time_trial": "Time Trial", &"collectible": "Festival Flag",
}
const MEDALS: Array[String] = ["", "Bronze", "Silver", "Gold"]
## Credits for finishing, before the medal bonus.
const BASE_REWARD := {
	&"speed_trap": 300, &"speed_zone": 500, &"drift": 600, &"jump": 400, &"race": 1500, &"time_trial": 2500,
}
## Scored events (higher is better): a result below this share of the Bronze threshold earns no credits and is
## not recorded as a personal best (a drift zone driven without drifting, a walking-pace roll off a ramp).
const QUALIFY := 0.5

var data: ActivityData
var manager: Node
var road: RoadNetwork.Road
var gates: Array[Node3D] = []
var cooldown: float = 0.0
var running: bool = false
var half_width: float = 5.0
var tracker := RouteTracker.new()


func setup(d: ActivityData, mgr: Node, r: RoadNetwork.Road) -> void:
	data = d
	manager = mgr
	road = r
	half_width = mgr.road_half_width(r)


# ------------------------------------------------------------------ hooks

func build() -> void:
	pass


func on_gate(_index: int, _car: CarController, _along: float) -> void:
	pass


func physics(_dt: float, _car: CarController) -> void:
	pass


func on_impact(_strength: float) -> void:
	pass


## Speed traps may fire while this session runs.
func allows_traps() -> bool:
	return true


## Rewind contract (CarRewind via the manager): true while the session forbids a rewind (races, time trial).
func blocks_rewind() -> bool:
	return false


## The player started a rewind (not blocked): sessions whose result the rewind would falsify end here.
func on_rewind() -> void:
	pass


## While a menu / map / console is open the manager stops calling physics() (clock and timers freeze); sessions
## that time the player also have the player car held in place (true) so it resumes at the same speed.
func holds_player() -> bool:
	return running


## Overlay hold of anything else the session drives (race rivals).
func set_overlay_hold(_on: bool) -> void:
	pass


## Where a reset (Game.respawn) should put the player while this session runs: {position, forward} or {}.
func respawn_point() -> Dictionary:
	if not running or tracker.road == null:
		return {}
	var d := float(data.dir) if data.dir != 0 else signf(road.flat_tangent_at(tracker.s).dot(Game.player_car.linear_velocity) + 0.001)
	var lane := road.lane_offset(1) * d if road.traffic else 0.0
	return {"position": road.surface_point(tracker.s, lane), "forward": road.flat_tangent_at(tracker.s) * d}


func cancel(reason: String) -> void:
	if not running:
		return
	_cleanup()
	end()
	Game.notify(data.title, reason, &"warning")
	print("[activity] %s cancelled: %s" % [data.id, reason])


## Releases anything the running session holds (cars, waypoints, hidden gates).
func _cleanup() -> void:
	pass


# ------------------------------------------------------------------ helpers

func kind_label() -> String:
	return KIND_LABEL.get(data.kind, "Activity")


func gate_s(i: int) -> float:
	return data.gates[i]


## Road +s tangent at gate i.
func gate_forward(i: int) -> Vector3:
	return road.flat_tangent_at(data.gates[mini(i, data.gates.size() - 1)])


func gate_position(i: int) -> Vector3:
	return road.point_at(data.gates[i])


func map_position() -> Vector3:
	return data.position


## Points that reveal the event on the map when the player comes near (every spot it can be started from).
func discovery_points() -> PackedVector3Array:
	return PackedVector3Array([map_position()])


func begin() -> bool:
	if running or not manager.begin_session(self):
		return false
	running = true
	manager.discover(self)
	return true


func end() -> void:
	running = false
	cooldown = 3.0
	manager.end_session(self)


func hud(primary: String, secondary := "", progress := -1.0) -> void:
	Game.activity_update.emit({"id": data.id, "title": data.title, "kind": data.kind,
		"primary": primary, "secondary": secondary, "progress": progress})


## `shown` (speed_shown, dist_shown, time_shown) maps a value to the number the HUD prints for it: the result and
## the thresholds are compared as shown, so a result printed equal to a medal target earns that medal.
func medal_for(value: float, higher_better: bool, shown := Callable()) -> int:
	var v := float(shown.call(value)) if shown.is_valid() else value
	var m := 0
	for i in data.thresholds.size():
		var t := float(shown.call(data.thresholds[i])) if shown.is_valid() else data.thresholds[i]
		if (v >= t) if higher_better else (v <= t):
			m = i + 1
	return m


func threshold_text(medal: int, unit_fn: Callable) -> String:
	if data.thresholds.size() < medal or medal < 1:
		return ""
	return "%s %s" % [MEDALS[medal], unit_fn.call(data.thresholds[medal - 1])]


## Next medal the player can still reach (for the HUD), e.g. "Gold 215 km/h".
func target_text(value: float, higher_better: bool, unit_fn: Callable, shown := Callable()) -> String:
	var m := medal_for(value, higher_better, shown)
	if m >= 3:
		return "Gold pace"
	return threshold_text(m + 1, unit_fn)


## True when a result counts (credits, personal best): any medal, any finish of a timed event, else at least
## QUALIFY x the Bronze threshold.
func qualifies(value: float, higher_better: bool, medal: int) -> bool:
	if medal > 0 or not higher_better or data.thresholds.is_empty():
		return true
	return value > 0.0 and value >= data.thresholds[0] * QUALIFY


## Emits the result (HUD banner + notification), records the personal best and pays credits.
func finish(value: float, higher_better: bool, score_text: String, medal := -1, detail := "", shown := Callable()) -> Dictionary:
	if medal < 0:
		medal = medal_for(value, higher_better, shown)
	var counts := qualifies(value, higher_better, medal)
	var pb := counts and Game.record_personal_best("activity:" + data.id, value, higher_better)
	var credits := int(BASE_REWARD.get(data.kind, 300) * (1.0 + medal * 0.5)) + (250 if pb else 0) if counts else 0
	manager.award(credits)
	var result := {"title": data.title, "score_text": score_text, "personal_best": pb, "medal": MEDALS[medal],
		"stars": medal, "credits": credits, "kind": data.kind, "value": value, "detail": detail, "qualified": counts}
	Game.activity_finished.emit(data.id, result)
	var parts := PackedStringArray([score_text])
	if detail != "":
		parts.append(detail)
	if medal > 0:
		parts.append(MEDALS[medal])
	if pb:
		parts.append("New personal best!")
	parts.append("+%s CR" % fmt_int(credits) if counts else "Too low to score - no reward")
	Game.notify(data.title, "  ·  ".join(parts), &"activity")
	print("[activity] %s finished: %s medal=%s pb=%s credits=%d qualified=%s" % [data.id, score_text, MEDALS[medal], pb, credits, counts])
	_cleanup()
	end()
	return result


func personal_best() -> Variant:
	return Game.personal_bests.get("activity:" + data.id)


static func fmt_time(t: float) -> String:
	var cs := int(roundf(maxf(t, 0.0) * 100.0))
	return "%02d:%02d.%02d" % [cs / 6000, (cs / 100) % 60, cs % 100]


static func fmt_int(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if n < 0 else "") + s + out


static func mph() -> bool:
	return bool(Settings.get_value("units_mph", false))


static func speed_text(kmh: float) -> String:
	return ("%d mph" if mph() else "%d km/h") % roundi(speed_shown(kmh))


static func speed_shown(kmh: float) -> float:
	return roundf(kmh * 0.621371) if mph() else roundf(kmh)


static func dist_text(m: float) -> String:
	if mph():
		return "%d ft" % roundi(dist_shown(m))
	return "%.1f m" % dist_shown(m)


static func dist_shown(m: float) -> float:
	return roundf(m * 3.28084) if mph() else roundf(m * 10.0) / 10.0


static func time_shown(t: float) -> float:
	return roundf(maxf(t, 0.0) * 100.0) / 100.0


## Short HUD distance in whole metres / feet ("58 m", "190 ft").
static func near_text(m: float) -> String:
	if mph():
		return "%d ft" % maxi(roundi(m * 3.28084), 0)
	return "%d m" % maxi(roundi(m), 0)


## Distance along a route: metres below 2 km ("650 m", "3.6 km"), feet below 0.2 mi ("430 ft", "0.53 mi", "3.9 mi").
static func route_text(m: float) -> String:
	m = maxf(m, 0.0)
	if mph():
		var mi := m / 1609.344
		if mi < 0.2:
			return "%d ft" % (roundi(m * 3.28084 / 10.0) * 10)
		return ("%.2f mi" if mi < 2.0 else "%.1f mi") % mi
	return "%d m" % roundi(m) if m < 2000.0 else "%.1f km" % (m / 1000.0)


## Freezes a car where it is (overlay hold) and returns what release_car() needs to resume it exactly.
static func hold_car(car: CarController) -> Dictionary:
	if car == null or not is_instance_valid(car):
		return {}
	var snap := {"car": car, "xf": car.global_transform, "lv": car.linear_velocity, "av": car.angular_velocity,
		"gear": car.gear, "frozen": car.freeze}
	car.freeze = true
	return snap


## Resumes a held car with its velocities and gear, unless it was frozen already or someone moved it meanwhile
## (teleport, respawn, fast travel: then that code owns it).
static func release_car(snap: Dictionary) -> void:
	if snap.is_empty() or bool(snap["frozen"]):
		return
	var car: Variant = snap["car"]
	if not is_instance_valid(car):
		return
	var c := car as CarController
	var xf: Transform3D = snap["xf"]
	if c.freeze and c.global_position.distance_to(xf.origin) < 0.5:
		c.place_at(xf, snap["lv"], snap["av"], int(snap["gear"]))


static func ordinal(n: int) -> String:
	match n:
		1:
			return "1st"
		2:
			return "2nd"
		3:
			return "3rd"
	return "%dth" % n
