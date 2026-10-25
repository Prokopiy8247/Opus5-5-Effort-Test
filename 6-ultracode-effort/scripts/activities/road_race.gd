extends "res://scripts/activities/activity_base.gd"
## Checkpoint road race (point to point along one road). Drive through the start arch and brake to a stop in
## the start zone: the grid is formed (AI rivals beside/behind the player), 3-2-1, go. Ordered checkpoint
## arches (only the next ones are shown), split times, wrong-way and missed-checkpoint handling, finish banner.

const Opponents := preload("res://scripts/activities/race_opponents.gd")

enum State { IDLE, ARMED, COUNTDOWN, RUNNING }

const STOP_KMH := 6.0
const ARM_ZONE := 110.0
const COUNTDOWN := 3.0
## Pole position (the player) this far past the start arch.
const GRID_AHEAD := 20.0
## Staggered grid behind the player: the first rival GRID_FIRST metres back (clear behind both chase cameras,
## so the countdown is not framed through its roof), then one car every GRID_GAP metres, alternating between
## two columns in the travel half.
const GRID_FIRST := 13.0
const GRID_GAP := 6.5
## Grid columns as fractions of the travel half of the road (centre line = 0, paved edge = 1).
const GRID_COLUMNS: Array[float] = [0.66, 0.33]
const PASS_LATERAL := 12.0
## Traffic density cap while a race with rivals runs (the user's setting is left alone).
const RACE_TRAFFIC := 0.15

var state: int = State.IDLE
var opponents: RefCounted = null
var _t := 0.0
var _armed_t := 0.0
var _count := 0.0
var _next := 1
var _rel_prev := -1.0
var _wrong_t := 0.0
var _wrong_warned := false
var _off_t := 0.0
var _stall_t := 0.0
var _missed := false
var _msg := ""
var _msg_t := 0.0
var _prev_waypoint := Vector3.INF
var _prev_waypoint_owner: Variant = &""
var _last_cp_t := 0.0
var _capped_traffic := false
## The car this race froze on the grid for the countdown, and where (cleanup releases only that hold).
var _held: CarController = null
var _hold_xf := Transform3D.IDENTITY


func _start_banner() -> String:
	return "RACE START"


func _finish_banner() -> String:
	return "FINISH"


func _opponent_count() -> int:
	return int(data.extra.get("opponents", 0))


func build() -> void:
	var last := data.gates.size() - 1
	for i in data.gates.size():
		if i == 0:
			gates.append(manager.make_gate(self, 0, gate_s(0), &"arch", _start_banner(), true, data.dir))
		elif i == last:
			gates.append(manager.make_gate(self, i, gate_s(i), &"arch", _finish_banner(), false, data.dir))
		else:
			var g: Node3D = manager.make_gate(self, i, gate_s(i), &"checkpoint", "CHECKPOINT %d" % i, false, data.dir)
			g.visible = false
			gates.append(g)


func allows_traps() -> bool:
	return false


## No rewind on the grid or during the race: the clock and the rivals cannot be rewound with the car.
func blocks_rewind() -> bool:
	return state == State.COUNTDOWN or state == State.RUNNING


## The grid holds the player frozen itself; while racing an open menu holds the car with the clock and rivals.
func holds_player() -> bool:
	return state == State.RUNNING


func set_overlay_hold(on: bool) -> void:
	if opponents != null:
		opponents.call("set_hold", on)


func respawn_point() -> Dictionary:
	if state != State.RUNNING:
		return {}
	var s := tracker.s
	return {"position": road.surface_point(s, road.lane_offset(1) * data.dir), "forward": road.flat_tangent_at(s) * data.dir}


## Gate node index that represents logical gate i (the time trial reuses the start arch as the finish).
func _node(i: int) -> int:
	return i


func on_gate(index: int, car: CarController, along: float) -> void:
	match state:
		State.IDLE:
			if index != 0 or cooldown > 0.0 or along * data.dir < 2.0:
				return
			if not begin():
				return
			state = State.ARMED
			_armed_t = 0.0
			tracker.reset(road, gate_s(0))
			manager.flash_gate(gates[0], 0.6)
			Game.notify(data.title, "Brake to a stop in the start zone to begin the %s" % kind_label().to_lower(), &"info")
		State.RUNNING:
			if _node(_next) == index and _next > 0:
				_pass(_next, car)


func physics(dt: float, car: CarController) -> void:
	match state:
		State.ARMED:
			_physics_armed(dt, car)
		State.COUNTDOWN:
			_physics_countdown(dt, car)
		State.RUNNING:
			_physics_running(dt, car)


func _physics_armed(dt: float, car: CarController) -> void:
	_armed_t += dt
	tracker.update(car.global_position)
	var past := (tracker.s - gate_s(0)) * data.dir
	hud("STOP TO START", "%s  ·  %s  ·  brake to a stop" % [kind_label(), route_text(data.length)], -1.0)
	# A frozen car (rewind scrubbing) reports stale speed: only a real stop forms the grid.
	if not car.freeze and car.get_speed_kmh() < STOP_KMH and past > -15.0 and past < ARM_ZONE:
		_start_countdown(car)
	elif past > ARM_ZONE + 30.0 or past < -60.0 or _armed_t > 20.0:
		running = false
		state = State.IDLE
		cooldown = 6.0
		manager.end_session(self)


## Grid slot k (0 = player): every slot is in the travel-direction half of the road, never in the oncoming lane.
## The transform rests on the road collider (a settled car's origin sits on the surface) and follows its slope.
func _grid_slot(k: int) -> Transform3D:
	var lane := road.width * 0.5 * GRID_COLUMNS[k % GRID_COLUMNS.size()] * data.dir
	var back := 0.0 if k == 0 else GRID_FIRST + (k - 1) * GRID_GAP
	var s := gate_s(0) + data.dir * (GRID_AHEAD - back)
	var fwd := road.flat_tangent_at(s) * data.dir
	var xf := Transform3D(Basis.looking_at(fwd, Vector3.UP), road.surface_point(s, lane))
	var q := PhysicsRayQueryParameters3D.create(xf.origin + Vector3.UP * 2.0, xf.origin + Vector3.DOWN * 3.0, 1)
	var hit := (manager as Node3D).get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return xf
	var n: Vector3 = hit["normal"]
	return Transform3D(Basis.looking_at(fwd.slide(n).normalized(), n), hit["position"])


func _start_countdown(car: CarController) -> void:
	var slot := _grid_slot(0)
	manager.place_player(slot.origin, -slot.basis.z)
	# The generic placement drops the car from 0.45 m; the grid holds it frozen, so seat it on the road.
	car.place_at(slot)
	car.freeze = true
	if Game.camera_rig != null and Game.camera_rig.has_method("snap"):
		Game.camera_rig.call("snap")
	_held = car
	_hold_xf = slot
	var n := _opponent_count()
	if n > 0:
		opponents = Opponents.new()
		var slots: Array[Transform3D] = []
		for k in range(1, n + 1):
			slots.append(_grid_slot(k))
		opponents.call("spawn", manager, road, data.dir, slots, gate_s(data.gates.size() - 1), car.data)
	var tm: Node = Game.traffic
	if _opponent_count() > 0 and tm != null and tm.has_method("set_density_cap"):
		tm.call("set_density_cap", RACE_TRAFFIC)
		_capped_traffic = true
	_count = COUNTDOWN
	state = State.COUNTDOWN
	_next = 1
	_show_upcoming()
	_prev_waypoint = Game.waypoint
	_prev_waypoint_owner = Game.get("waypoint_owner") if "waypoint_owner" in Game else &""
	_set_waypoint(gate_position(_next))
	print("[activity] %s grid formed, %d rivals" % [data.id, n])


## Race waypoint, tagged as the activity's when the game tracks waypoint owners.
func _set_waypoint(pos: Vector3) -> void:
	if "waypoint_owner" in Game:
		Game.call(&"set_waypoint", pos, &"activity")
	else:
		Game.set_waypoint(pos)


func _physics_countdown(dt: float, car: CarController) -> void:
	_count -= dt
	if car == _held and car.global_position.distance_squared_to(_hold_xf.origin) > 0.0025:
		# Moved on the grid (a reset during the countdown): back onto its slot, resting on the road.
		car.place_at(_hold_xf)
	car.freeze = true
	if opponents != null:
		opponents.call("update_lights")
	if _count > 0.0:
		hud(str(ceili(_count)), "%s  ·  %s" % [data.title, _goal_text()], 0.0)
		return
	car.freeze = false
	_held = null
	if opponents != null:
		opponents.call("go")
	state = State.RUNNING
	_t = 0.0
	_last_cp_t = 0.0
	_wrong_t = 0.0
	_off_t = 0.0
	_stall_t = 0.0
	_missed = false
	tracker.reset(road, gate_s(0) + data.dir * GRID_AHEAD)
	_rel_prev = (tracker.s - gate_s(_next)) * data.dir
	_msg = "GO!"
	_msg_t = 1.2


func _goal_text() -> String:
	var n := _opponent_count()
	if n > 0:
		return "Beat %d rivals" % n
	return "Gold %s" % fmt_time(data.thresholds[2]) if data.thresholds.size() >= 3 else ""


func _physics_running(dt: float, car: CarController) -> void:
	_t += dt
	_msg_t = maxf(_msg_t - dt, 0.0)
	var pos := car.global_position
	var prev_s := tracker.s
	tracker.update(pos)
	var vel_along := (tracker.s - prev_s) * data.dir / maxf(dt, 0.0001)
	# Crossing the next gate plane on the road counts as passing it (the Area3D trigger does the same).
	var rel := (tracker.s - gate_s(_next)) * data.dir
	if _rel_prev <= 0.0 and rel > 0.0:
		if absf(tracker.lateral(pos)) < half_width + PASS_LATERAL:
			_pass(_next, car)
			if state != State.RUNNING:
				return
			rel = (tracker.s - gate_s(_next)) * data.dir
		else:
			_missed = true
	elif rel > 35.0 and not _missed:
		_missed = true
		Game.notify(data.title, "Missed checkpoint - turn back", &"warning")
	_rel_prev = rel
	if opponents != null:
		opponents.call("physics", dt, tracker.s, _t)
	# Wrong way / off route / stall.
	if vel_along < -3.0:
		_wrong_t += dt
	else:
		_wrong_t = maxf(_wrong_t - dt * 2.0, 0.0)
	if _wrong_t > 1.5 and not _wrong_warned:
		_wrong_warned = true
		Game.notify(data.title, "Wrong way!", &"warning")
	elif _wrong_t == 0.0:
		_wrong_warned = false
	_off_t = _off_t + dt if tracker.distance(pos) > 140.0 else 0.0
	_stall_t = _stall_t + dt if car.speed_ms < 1.0 else 0.0
	if _off_t > 12.0:
		cancel("Race abandoned - you left the route")
		return
	if _wrong_t > 20.0 or _stall_t > 45.0:
		cancel("Race abandoned")
		return
	if data.thresholds.size() > 0 and _t > data.thresholds[0] * 2.5:
		cancel("Race abandoned - time limit")
		return
	_hud_running()


func _position() -> int:
	if opponents == null:
		return 1
	return 1 + int(opponents.call("ahead_of", tracker.s, _t, _next >= data.gates.size()))


func _hud_running() -> void:
	var n := data.gates.size() - 1
	var line: String
	if _wrong_t > 1.5:
		line = "WRONG WAY"
	elif _missed:
		line = "MISSED CHECKPOINT %d - turn back" % _next
	elif _msg_t > 0.0:
		line = _msg
	else:
		line = "Checkpoint %d/%d" % [mini(_next, n), n]
		if opponents != null:
			line += "  ·  %s of %d" % [ordinal(_position()), _opponent_count() + 1]
		elif personal_best() != null:
			line += "  ·  PB %s" % fmt_time(float(personal_best()))
	var prog := clampf((tracker.s - gate_s(0)) / (gate_s(n) - gate_s(0)), 0.0, 1.0)
	hud(fmt_time(_t), line, prog)


func _pass(i: int, car: CarController) -> void:
	var last := data.gates.size() - 1
	manager.flash_gate(gates[_node(i)], 1.0)
	_missed = false
	if i >= last:
		_finish_race(car)
		return
	if _node(i) != 0:
		gates[_node(i)].visible = false
	var split := _t - _last_cp_t
	_last_cp_t = _t
	_msg = "Checkpoint %d  ·  %s  (+%s)" % [i, fmt_time(_t), fmt_time(split)]
	_msg_t = 2.5
	_next = i + 1
	_rel_prev = (tracker.s - gate_s(_next)) * data.dir
	_show_upcoming()
	_set_waypoint(gate_position(_next))


func _show_upcoming() -> void:
	for i in range(1, data.gates.size()):
		var node := gates[_node(i)]
		if _node(i) == 0:
			continue
		var show := i >= _next and i <= _next + 1
		node.visible = show
		manager.set_gate_dim(node, 1.0 if i == _next else 0.35)


func _finish_race(_car: CarController) -> void:
	var t := _t
	var pos := _position()
	var detail := ""
	var medal := -1
	if opponents != null:
		detail = "%s of %d" % [ordinal(pos), _opponent_count() + 1]
		medal = clampi(4 - pos, 0, 3)
	print("[activity] %s finish time %.2f position %d" % [data.id, t, pos])
	finish(t, false, fmt_time(t), medal, detail, time_shown)


func _cleanup() -> void:
	_release_hold()
	if opponents != null:
		var opp := opponents
		opponents = null
		opp.call("release", manager)
	# Lift only the race cap: a density the user picked during the race (console / debug menu) stays.
	if _capped_traffic and Game.traffic != null and Game.traffic.has_method("set_density_cap"):
		Game.traffic.call("set_density_cap", 1.0)
	_capped_traffic = false
	# Put back the waypoint the race replaced, unless someone else (the player) set a new one meanwhile.
	var ours: bool = not ("waypoint_owner" in Game) or Game.get("waypoint_owner") == &"activity"
	if (state == State.COUNTDOWN or state == State.RUNNING) and ours:
		if _prev_waypoint == Vector3.INF:
			Game.clear_waypoint()
		elif "waypoint_owner" in Game:
			Game.call(&"set_waypoint", _prev_waypoint, _prev_waypoint_owner)
		else:
			Game.set_waypoint(_prev_waypoint)
	state = State.IDLE
	for i in range(1, data.gates.size()):
		var node := gates[_node(i)]
		if _node(i) != 0:
			node.visible = i == data.gates.size() - 1 and _finish_visible_idle()
			manager.set_gate_dim(node, 1.0)


## Unfreezes the player only if the countdown hold is still the race's own: the same car, still on its grid
## slot. A car moved away meanwhile (fast travel, respawn) belongs to whoever moved it, and that code may
## hold it frozen itself (ui_root.fast_travel waits for terrain streaming with the car frozen).
func _release_hold() -> void:
	if is_instance_valid(_held) and _held == Game.player_car:
		var p := _held.global_position
		if Vector2(p.x - _hold_xf.origin.x, p.z - _hold_xf.origin.z).length() < 3.0:
			_held.freeze = false
	_held = null


func _finish_visible_idle() -> bool:
	return true


func end() -> void:
	state = State.IDLE
	running = false
	cooldown = 5.0
	manager.end_session(self)
