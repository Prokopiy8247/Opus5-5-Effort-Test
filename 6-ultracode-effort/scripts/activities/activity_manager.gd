extends Node3D
## Road activities ("Activities" node, Game.activities): speed traps, speed zones, drift zones, danger-sign
## jumps, checkpoint road races with AI rivals, the Sunward Ring time trial and 20 Festival Flags.
## Events are placed on the real road network by event_planner.gd (data/events/events.json; re-planned in
## memory when the file was made for other roads). Gates trigger through Area3D on layer 4 that only see the
## player body (layer 2). One session activity runs at a time; speed traps and flags are instant.
## HUD contract: Game.activity_update / Game.activity_finished (docs/SYSTEM_CONTRACTS.md); map: get_map_markers().

const Base := preload("res://scripts/activities/activity_base.gd")
const Planner := preload("res://scripts/activities/event_planner.gd")
const GateBuilder := preload("res://scripts/activities/gate_builder.gd")
const ActivityData := preload("res://scripts/activities/activity_data.gd")
const Collectibles := preload("res://scripts/activities/collectibles.gd")
const TYPES := {
	&"speed_trap": preload("res://scripts/activities/speed_trap.gd"),
	&"speed_zone": preload("res://scripts/activities/speed_zone.gd"),
	&"drift": preload("res://scripts/activities/drift_zone.gd"),
	&"jump": preload("res://scripts/activities/jump_zone.gd"),
	&"race": preload("res://scripts/activities/road_race.gd"),
	&"time_trial": preload("res://scripts/activities/time_trial.gd"),
}
const EVENTS_PATH := "res://data/events/events.json"
const TRIGGER_LAYER := 8      # physics layer 4 "triggers"
const PLAYER_MASK := 2        # physics layer 2 "player"
const TELEPORT_JUMP := 60.0   # m in one physics step = teleport (cancels the session)
const DISCOVER_RADIUS := 160.0
const DISCOVERED_KEY := "events"

var activities: Array = []
var by_id: Dictionary = {}
var session: RefCounted = null
var collectibles: Node3D
var events_source: String = ""
var _gates_root: Node3D
var _car: CarController
var _last_pos := Vector3.ZERO
var _have_last := false
var _suppress := 0
var _trigger_block := 0.0
var _discover_t := 0.0
var _flashes: Dictionary = {}
## A menu / map / console is open during a session: session physics (clock, zone timers, rivals) is paused.
var _overlay_hold := false
var _held_session: RefCounted = null
var _player_hold: Dictionary = {}
## Race rivals cruising off after their race until each is out of view (race_opponents.gd release / cruise).
var _cruisers: Array[RefCounted] = []


func _ready() -> void:
	_gates_root = Node3D.new()
	_gates_root.name = "Gates"
	add_child(_gates_root)
	# Photo mode wakes this group after a time / weather change while paused: rival lamps follow (_process).
	add_to_group(Game.TIME_REACTIVE_GROUP)
	Game.car_spawned.connect(_on_car_spawned)
	_build()
	if Game.player_car != null:
		_on_car_spawned(Game.player_car)


func _build() -> void:
	var world := Game.world
	if world == null or not (world is World):
		push_warning("[activities] no open world - activities disabled")
		return
	var wd: WorldData = (world as World).data
	var t0 := Time.get_ticks_msec()
	var flag_list: Array[ActivityData] = []
	for d: Dictionary in _load_events(wd):
		var a := ActivityData.new()
		a.fill(d)
		if a.kind == &"collectible":
			flag_list.append(a)
			continue
		var scr: Script = TYPES.get(a.kind)
		var road := wd.network.get_road(a.road_id)
		if scr == null or road == null or a.gates.is_empty():
			push_warning("[activities] skipped %s (kind %s, road %s)" % [a.id, a.kind, a.road_id])
			continue
		var act: RefCounted = scr.new()
		act.call("setup", a, self, road)
		act.call("build")
		activities.append(act)
		by_id[a.id] = act
	collectibles = Collectibles.new()
	collectibles.name = "FestivalFlags"
	add_child(collectibles)
	collectibles.call("setup", flag_list, self)
	print("[activities] %d activities + %d flags from %s in %d ms" % [activities.size(), flag_list.size(), events_source, Time.get_ticks_msec() - t0])


func _load_events(wd: WorldData) -> Array:
	var sig := Planner.signature(wd.network)
	if FileAccess.file_exists(EVENTS_PATH):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(EVENTS_PATH))
		if parsed is Dictionary and str((parsed as Dictionary).get("signature", "")) == sig \
				and int((parsed as Dictionary).get("version", 0)) == Planner.VERSION:
			events_source = "events.json"
			return (parsed as Dictionary).get("events", [])
		push_warning("[activities] %s does not match the current roads - re-planning in memory (run tools/make_events.gd)" % EVENTS_PATH)
	var out: Dictionary = Planner.new().plan(wd)
	events_source = "runtime planner"
	return out.get("events", [])


# ------------------------------------------------------------------ gates (used by activity scripts)

func road_half_width(road: RoadNetwork.Road) -> float:
	return Planner.gate_half_width(road)


## Gate frame at arclength s: origin on the road centre, -Z along travel (facing = +1 / -1 along +s).
func gate_transform(road: RoadNetwork.Road, s: float, facing: int) -> Transform3D:
	var fwd := road.flat_tangent_at(s) * (1.0 if facing >= 0 else -1.0)
	return Transform3D(Basis.looking_at(fwd, Vector3.UP), road.point_at(s))


func make_gate(act: RefCounted, index: int, s: float, style: StringName, banner: String, label := true, facing := 1, trigger := true) -> Node3D:
	var road: RoadNetwork.Road = act.get("road")
	var data: ActivityData = act.get("data")
	var hw := road_half_width(road)
	var root := GateBuilder.build(style, data.kind, hw, banner)
	root.name = "%s_%d" % [data.id, index]
	_gates_root.add_child(root)
	root.global_transform = gate_transform(road, s, facing)
	if label:
		var lb: Node3D = GateBuilder.floating_label(data.kind, String(act.call("kind_label")), data.title)
		var y := GateBuilder.gate_height(hw) + 2.6
		if style == &"sign":
			lb.position = Vector3(hw + 1.9, 6.0, 0.0)
		else:
			lb.position = Vector3(0.0, y, 0.0)
		root.add_child(lb)
	if trigger:
		var area := Area3D.new()
		area.name = "Trigger"
		area.collision_layer = TRIGGER_LAYER
		area.collision_mask = PLAYER_MASK
		area.monitorable = false
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		# Danger signs arm across the whole track (drivers cut corners); arches only between their legs.
		box.size = Vector3(2.0 * hw + (10.0 if style == &"sign" else 0.0), 8.0, 5.0)
		cs.shape = box
		cs.position = Vector3(0.0, 2.5, 0.0)
		area.add_child(cs)
		root.add_child(area)
		area.body_entered.connect(_on_trigger.bind(act, index))
	return root


## Festival jump ramp whose lip sits at arclength s_lip, rising in travel direction `dir`; its back slope
## runs `back_len` metres down to the road beyond the lip (drivable against the jump direction).
func make_ramp(act: RefCounted, s_lip: float, dir: int, length: float, height: float, back_len: float) -> Node3D:
	var road: RoadNetwork.Road = act.get("road")
	var data: ActivityData = act.get("data")
	var p1 := road.point_at(s_lip)
	var p0 := road.point_at(s_lip - dir * length)
	var fwd := (p1 - p0).normalized()
	var xf := Transform3D(Basis.looking_at(fwd, Vector3.UP), p1)
	# Road height where the back slope meets it, in the ramp's frame (the grade may change at the lip).
	var back := xf.affine_inverse() * road.point_at(s_lip + dir * back_len)
	var root := GateBuilder.ramp_node(data.kind, ramp_width(road), length, height, maxf(-back.z, 1.0), back.y)
	root.name = "%s_ramp" % data.id
	_gates_root.add_child(root)
	root.global_transform = xf
	return root


func ramp_width(road: RoadNetwork.Road) -> float:
	return road.width + 0.6


func flash_gate(root: Node3D, strength: float) -> void:
	if root == null:
		return
	_flashes[root] = strength
	_apply_flash(root, strength)


func _apply_flash(root: Node3D, v: float) -> void:
	var cur: Variant = root.get_meta(&"curtain") if root.has_meta(&"curtain") else null
	if cur is GeometryInstance3D:
		(cur as GeometryInstance3D).set_instance_shader_parameter(&"flash", v)
	var glow: Variant = root.get_meta(&"glow") if root.has_meta(&"glow") else null
	if glow is GeometryInstance3D and (glow as GeometryInstance3D).material_override is ShaderMaterial:
		(glow as GeometryInstance3D).set_instance_shader_parameter(&"glow", v)


func set_gate_dim(root: Node3D, v: float) -> void:
	var cur: Variant = root.get_meta(&"curtain") if root.has_meta(&"curtain") else null
	if cur is GeometryInstance3D:
		(cur as GeometryInstance3D).set_instance_shader_parameter(&"dim", v)


func _process(delta: float) -> void:
	if get_tree().paused:
		var sets := _cruisers.duplicate()
		var opp: Variant = session.get("opponents") if session != null else null
		if opp is RefCounted:
			sets.append(opp)
		for o: RefCounted in sets:
			o.call("update_lights")
	if _flashes.is_empty():
		return
	for root: Node3D in _flashes.keys():
		var v: float = _flashes[root] - delta * 1.6
		if v <= 0.0 or not is_instance_valid(root):
			_flashes.erase(root)
			v = 0.0
		else:
			_flashes[root] = v
		if is_instance_valid(root):
			_apply_flash(root, v)


# ------------------------------------------------------------------ sessions

func begin_session(act: RefCounted) -> bool:
	if session != null and session != act:
		return false
	session = act
	return true


func end_session(act: RefCounted) -> void:
	if session == act:
		session = null


func cancel_session(reason := "Event cancelled") -> void:
	if session != null:
		session.call("cancel", reason)


## Reset point that keeps the player on the running event's road ({position, forward} or {}). Used by
## main.respawn_on_road() (see the core change request); suppresses the teleport cancel for that move.
func respawn_override(_pos: Vector3) -> Dictionary:
	if session == null:
		return {}
	var p: Dictionary = session.call("respawn_point")
	if not p.is_empty():
		_suppress = 4
		_trigger_block = 0.3
	return p


func award(credits: int) -> void:
	if credits <= 0:
		return
	Game.credits += credits
	Game.stats_changed.emit()


## Moves the player without the teleport detector cancelling the running session.
func place_player(pos: Vector3, forward: Vector3) -> void:
	_suppress = 4
	_trigger_block = 0.3
	if Game.main != null:
		Game.main.teleport_to({"position": pos, "forward": forward})


func _on_trigger(body: Node3D, act: RefCounted, index: int) -> void:
	if OS.has_feature("debug") and OS.get_cmdline_user_args().has("--activity-debug"):
		print("[activities] trigger %s/%d by %s block=%.2f session=%s cooldown=%.2f" % [(act.get("data") as ActivityData).id, index, body.name, _trigger_block, get_session_id(), float(act.get("cooldown"))])
	if body != Game.player_car or _trigger_block > 0.0 or Game.benchmark_mode:
		return
	if Game.main == null or Game.main.is_loading or Game.photo_mode:
		return
	var car := body as CarController
	var road: RoadNetwork.Road = act.get("road")
	var data: ActivityData = act.get("data")
	var along := car.linear_velocity.dot(road.flat_tangent_at(data.gates[mini(index, data.gates.size() - 1)]))
	if session != null and session != act:
		if not (data.kind == &"speed_trap" and bool(session.call("allows_traps"))):
			return
	act.call("on_gate", index, car, along)


func _physics_process(dt: float) -> void:
	_trigger_block = maxf(_trigger_block - dt, 0.0)
	for i in range(_cruisers.size() - 1, -1, -1):
		if not bool(_cruisers[i].call("cruise", dt)):
			_cruisers.remove_at(i)
	var car := Game.player_car
	if car == null or not is_instance_valid(car):
		_have_last = false
		return
	var p := car.global_position
	if _have_last and _suppress <= 0 and p.distance_to(_last_pos) > TELEPORT_JUMP:
		_on_teleport()
	_suppress = maxi(_suppress - 1, 0)
	_last_pos = p
	_have_last = true
	for a: RefCounted in activities:
		var cd: float = a.get("cooldown")
		if cd > 0.0:
			a.set("cooldown", maxf(cd - dt, 0.0))
	var hold := session != null and Game.is_overlay_open()
	if hold != _overlay_hold or (hold and session != _held_session):
		_set_overlay_hold(hold, car)
	if session != null and not hold:
		session.call("physics", dt, car)
	_discover_t -= dt
	if _discover_t <= 0.0:
		_discover_t = 0.5
		_check_discoveries(p)


## Overlays during events: the race / time-trial clock, zone timers and rivals stop while a menu, the map or the
## console is open, and the player car is held frozen with its velocities, so everything resumes where it was.
func _set_overlay_hold(on: bool, car: CarController) -> void:
	if _held_session != null:
		_held_session.call("set_overlay_hold", false)
	Base.release_car(_player_hold)
	_player_hold = {}
	_held_session = null
	_overlay_hold = on
	if not on:
		return
	_held_session = session
	if bool(session.call("holds_player")) and car == Game.player_car:
		_player_hold = Base.hold_car(car)
	session.call("set_overlay_hold", true)


## Rewind contract (CarRewind): true while a race or the time trial counts down or runs - no rewind then.
func rewind_blocked() -> bool:
	return session != null and bool(session.call("blocks_rewind"))


## CarRewind calls this when a rewind starts: a running speed / drift zone or jump attempt ends (short reason).
func on_player_rewind() -> void:
	if session != null:
		session.call("on_rewind")


func _on_teleport() -> void:
	_trigger_block = 0.6
	if session != null:
		session.call("cancel", "Event cancelled - you left the route")


func _on_car_spawned(car: CarController) -> void:
	if _car != null and is_instance_valid(_car) and _car.impact.is_connected(_on_impact):
		_car.impact.disconnect(_on_impact)
	var switched := _car != null and _car != car
	_car = car
	if car != null:
		car.impact.connect(_on_impact)
	_have_last = false
	if switched and session != null:
		session.call("cancel", "Event cancelled - car changed")


func _on_impact(strength: float, _pos: Vector3) -> void:
	if session != null:
		session.call("on_impact", strength)


## An event is discovered near any spot it can be started from (both arches of a zone), and at the latest
## when it begins.
func _check_discoveries(p: Vector3) -> void:
	if Game.main == null or Game.main.is_loading or Game.benchmark_mode:
		return
	var seen: Dictionary = Game.discovered.get(DISCOVERED_KEY, {})
	for a: RefCounted in activities:
		if seen.has((a.get("data") as ActivityData).id):
			continue
		for mp: Vector3 in a.call("discovery_points"):
			if Vector2(mp.x - p.x, mp.z - p.z).length() < DISCOVER_RADIUS:
				discover(a)
				break


func discover(act: RefCounted) -> void:
	var data: ActivityData = act.get("data")
	var seen: Dictionary = Game.discovered.get(DISCOVERED_KEY, {})
	if seen.has(data.id):
		return
	seen[data.id] = true
	Game.discovered[DISCOVERED_KEY] = seen
	Game.notify("%s discovered" % String(act.call("kind_label")), data.title, &"discovery")


func is_discovered(id: String) -> bool:
	return (Game.discovered.get(DISCOVERED_KEY, {}) as Dictionary).has(id)


# ------------------------------------------------------------------ queries

## Map / minimap markers of the discovered road activities: {name, kind, position, id, discovered}. Events stay
## off the map until the player finds them; include_undiscovered lists every event (each with its flag).
func get_map_markers(include_undiscovered := false) -> Array:
	var out: Array = []
	for a: RefCounted in activities:
		var data: ActivityData = a.get("data")
		var found := is_discovered(data.id)
		if found or include_undiscovered:
			out.append({"name": data.title, "kind": data.kind, "position": a.call("map_position"), "id": data.id,
				"discovered": found})
	return out


## Festival Flags: {id, name, position, collected}.
func get_collectibles() -> Array:
	return collectibles.call("get_flag_positions") if collectibles != null else []


func collectible_count() -> Vector2i:
	if collectibles == null:
		return Vector2i.ZERO
	return Vector2i(int(collectibles.call("count")), (collectibles.get("flags") as Array).size())


## Summary rows for menus / tests: {id, kind, title, road, dir, gates, thresholds, position, length}.
func get_activity_list() -> Array:
	var out: Array = []
	for a: RefCounted in activities:
		var data: ActivityData = a.get("data")
		out.append({"id": data.id, "kind": data.kind, "title": data.title, "road": data.road_id, "dir": data.dir,
			"gates": data.gates, "thresholds": data.thresholds, "position": a.call("map_position"), "length": data.length})
	return out


## Takes over driving the rivals of a finished / cancelled race until they have left (race_opponents.release).
func adopt_cruisers(opp: RefCounted) -> void:
	if not _cruisers.has(opp):
		_cruisers.append(opp)


## AI cars the activities drive (race rivals are children of this node, also while they cruise off after a
## race). Traffic treats them as obstacles like the player.
func get_ai_cars() -> Array[CarController]:
	var out: Array[CarController] = []
	for c in get_children():
		if c is CarController and not c.is_queued_for_deletion():
			out.append(c as CarController)
	return out


func get_session_id() -> String:
	if session == null:
		return ""
	return (session.get("data") as ActivityData).id


## Teleports the player onto the road `before` metres ahead of an activity's first gate, facing it.
func teleport_to_activity(id: String, before := 200.0) -> bool:
	var a: RefCounted = by_id.get(id)
	if a == null:
		return false
	var data: ActivityData = a.get("data")
	var road: RoadNetwork.Road = a.get("road")
	var d := data.dir if data.dir != 0 else 1
	var s := data.gates[0] - d * before
	if not road.loop:
		s = clampf(s, 2.0, road.length - 2.0)
	var lane := road.lane_offset(1) * d if road.traffic else 0.0
	cancel_session()
	Game.main.teleport_to({"position": road.surface_point(s, lane), "forward": road.flat_tangent_at(s) * d})
	return true
