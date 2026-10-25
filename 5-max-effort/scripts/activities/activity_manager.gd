extends Node
## Road activities at runtime. Activities start by driving through them (no menus):
## speed traps (camera gates), speed zones and drift zones (start/end gates), danger-sign jumps
## (ramps beside farm tracks), checkpoint road races and the scenic-loop time trial (start gates),
## plus festival boards to smash. Shows live HUD panels and result notifications, awards stars and
## credits, keeps personal bests (saved through main.save_game via get_bests/set_bests).

const TRIGGER_RANGE := 220.0

var defs: Array[ActivityDef] = []
var by_id: Dictionary = {}
var bests: Dictionary = {}            # id -> best value
var stars: Dictionary = {}            # id -> stars (0..3)
var boards_smashed: Dictionary = {}   # board index -> true
var credits: int = 0
var active: ActivityDef = null
var _st: Dictionary = {}              # state of the active activity
var _prev_side: Dictionary = {}       # trigger id -> signed distance along the trigger normal
var _labels: Dictionary = {}          # id -> Label3D
var _marker: Node3D                   # next race checkpoint gate
var _jump: Dictionary = {}            # danger sign attempt in progress
var _boards: ActivityDef = null
var _cooldown: Dictionary = {}        # id -> seconds before it can trigger again
var _chime: AudioStreamPlayer


func _ready() -> void:
	name = "Activities"
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	defs = ActivityDef.load_all()
	for d in defs:
		by_id[d.id] = d
		if d.kind == ActivityDef.Kind.COLLECTIBLES:
			_boards = d
	_chime = AudioStreamPlayer.new()
	_chime.stream = SoundBank.get_stream("chime")
	_chime.volume_db = -6.0
	add_child(_chime)
	call_deferred("_late_init")


func _late_init() -> void:
	for d in defs:
		_make_label(d)
	_marker = _make_gate_marker()
	_apply_smashed()
	print("[activities] %d activities loaded" % defs.size())


# ------------------------------------------------------------------------------------------------
# world markers
func _make_label(d: ActivityDef) -> void:
	var anchor := Vector3.ZERO
	match d.kind:
		ActivityDef.Kind.COLLECTIBLES:
			return
		ActivityDef.Kind.SPEED_TRAP:
			anchor = d.prop_position + Vector3.UP * 5.6
		ActivityDef.Kind.DANGER_SIGN:
			anchor = d.prop_position + d.heading * 7.0 + Vector3.UP * 5.5
		_:
			anchor = d.position + Vector3.UP * 9.2
	var l := Label3D.new()
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.font = UiTheme.font(true)
	l.font_size = 72
	l.outline_size = 14
	l.outline_modulate = Color(0, 0, 0, 0.75)
	l.pixel_size = 0.012
	l.modulate = UiTheme.ACCENT
	l.visibility_range_end = 420.0
	l.visibility_range_end_margin = 40.0
	l.fixed_size = false
	l.position = anchor
	add_child(l)
	_labels[d.id] = l
	_refresh_label(d)


func _refresh_label(d: ActivityDef) -> void:
	var l: Label3D = _labels.get(d.id)
	if l == null:
		return
	var txt := "%s\n%s" % [d.kind_name().to_upper(), d.display_name]
	if bests.has(d.id):
		txt += "\n%s  %s" % [_star_text(int(stars.get(d.id, 0))), d.format_value(float(bests[d.id]), _mph())]
	l.text = txt


func _make_gate_marker() -> Node3D:
	var ps := PropLibrary.scene("checkpoint_gate")
	var holder := Node3D.new()
	holder.name = "CheckpointMarker"
	add_child(holder)
	if ps != null:
		var inst := ps.instantiate() as Node3D
		PropLibrary.apply_to_scene(inst)
		holder.add_child(inst)
	var beam := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.6
	cyl.bottom_radius = 0.6
	cyl.height = 60.0
	beam.mesh = cyl
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(1.0, 0.64, 0.12, 0.35)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	beam.material_override = m
	beam.position = Vector3(0, 30.0, 0)
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	holder.add_child(beam)
	holder.visible = false
	return holder


# ------------------------------------------------------------------------------------------------
func _physics_process(delta: float) -> void:
	var car := Game.player_car
	if car == null or not is_instance_valid(car):
		return
	for k in _cooldown.keys():
		_cooldown[k] = float(_cooldown[k]) - delta
		if float(_cooldown[k]) <= 0.0:
			_cooldown.erase(k)
	var p := car.global_position
	if active != null:
		_update_active(delta, car, p)
	else:
		_check_triggers(car, p)
	_update_jump(delta, car, p)


func _crossed(key: String, origin: Vector3, normal: Vector3, half_w: float, p: Vector3, both_ways: bool) -> bool:
	var rel := p - origin
	var d := rel.dot(normal)
	var side := normal.cross(Vector3.UP).normalized()
	var lat := absf(rel.dot(side))
	var had := _prev_side.has(key)
	var prev: float = _prev_side.get(key, d)
	_prev_side[key] = d
	if not had or lat > half_w or absf(rel.y) > 8.0:
		return false
	if both_ways:
		return (prev < 0.0 and d >= 0.0) or (prev > 0.0 and d <= 0.0)
	return prev < 0.0 and d >= 0.0


func _check_triggers(car: CarController, p: Vector3) -> void:
	for d in defs:
		if d.kind == ActivityDef.Kind.COLLECTIBLES or d.kind == ActivityDef.Kind.DANGER_SIGN or _cooldown.has(d.id):
			continue
		if Vector2(p.x - d.position.x, p.z - d.position.z).length() > TRIGGER_RANGE:
			_prev_side.erase(d.id)
			continue
		var half_w := d.width * 0.5 + 4.0
		if d.kind == ActivityDef.Kind.SPEED_TRAP:
			if _crossed(d.id, d.position, d.heading, half_w, p, true):
				_finish(d, absf(car.speed_kmh))
				_cooldown[d.id] = 4.0
			continue
		if _crossed(d.id, d.position, d.heading, half_w, p, false) and car.forward_speed > 1.0:
			_start(d, car)
			return


# ------------------------------------------------------------------------------------------------
func _start(d: ActivityDef, car: CarController) -> void:
	active = d
	_st = {"t": 0.0, "dist": 0.0, "off_t": 0.0, "cp": 0, "away_t": 0.0, "last_d": 1e9, "score": 0.0,
		"chain": 0.0, "chain_t": 0.0, "idle_t": 0.0, "combo": 1.0}
	_prev_side.erase(d.id + ":end")
	var title := d.kind_name().to_upper()
	Game.show_notification(title + " STARTED", d.display_name, "event")
	_play_chime(1.0)
	if d.kind == ActivityDef.Kind.RACE or d.kind == ActivityDef.Kind.TIME_TRIAL:
		_show_checkpoint(d, 0)
	if not car.impact.is_connected(_on_impact):
		car.impact.connect(_on_impact)


func _stop(reason: String) -> void:
	if active == null:
		return
	Game.show_notification(active.kind_name().to_upper(), reason, "info")
	_cooldown[active.id] = 6.0
	_end_common()


func _end_common() -> void:
	active = null
	_st = {}
	if Game.hud != null:
		Game.hud.call("hide_activity")
	if _marker != null:
		_marker.visible = false
	if Game.world != null and Game.world.has_method("set_route_target"):
		Game.world.call("set_route_target", Vector3.INF)


func _on_impact(strength: float, _point: Vector3) -> void:
	if active != null and active.kind == ActivityDef.Kind.DRIFT_ZONE and strength > 4.0:
		_st["chain"] = 0.0
		_st["chain_t"] = 0.0
		_st["combo"] = 1.0


func _update_active(delta: float, car: CarController, p: Vector3) -> void:
	var d := active
	_st["t"] = float(_st["t"]) + delta
	var t: float = _st["t"]
	var hspeed := Vector2(car.linear_velocity.x, car.linear_velocity.z).length()
	_st["dist"] = float(_st["dist"]) + hspeed * delta
	match d.kind:
		ActivityDef.Kind.SPEED_ZONE, ActivityDef.Kind.DRIFT_ZONE:
			if not _on_course(d, p, delta):
				_stop("Left the zone")
				return
			if d.kind == ActivityDef.Kind.DRIFT_ZONE:
				_drift_tick(delta, car)
			if t > maxf(d.length_m / 6.0, 60.0):
				_stop("Out of time")
				return
			if _crossed(d.id + ":end", d.end_position, d.end_heading, d.width * 0.5 + 6.0, p, false):
				if d.kind == ActivityDef.Kind.SPEED_ZONE:
					_finish(d, d.length_m / maxf(t, 0.01) * 3.6)
				else:
					_finish(d, float(_st["score"]) + float(_st["chain"]) * float(_st["combo"]))
				return
			_hud_zone(d, t)
		ActivityDef.Kind.RACE, ActivityDef.Kind.TIME_TRIAL:
			_race_tick(delta, d, p, t)


func _on_course(d: ActivityDef, p: Vector3, delta: float) -> bool:
	## leaving the zone road for more than 3 s aborts (cutting across is not allowed)
	var w: Node = Game.world
	var off := true
	if w != null and "data" in w:
		var nr: Dictionary = (w.get("data") as WorldData).nearest_road(p.x, p.z, 2)
		if not nr.is_empty() and int(nr["road"]) == d.road and float(nr["d"]) < d.width * 0.5 + 18.0:
			off = false
	_st["off_t"] = float(_st["off_t"]) + delta if off else 0.0
	return float(_st["off_t"]) < 3.0


func _drift_tick(delta: float, car: CarController) -> void:
	var slip := absf(car.body_slip_deg)
	var drifting := slip > 10.0 and slip < 80.0 and absf(car.speed_kmh) > 25.0 and car.grounded_wheels >= 2
	if drifting:
		_st["idle_t"] = 0.0
		_st["chain_t"] = float(_st["chain_t"]) + delta
		_st["combo"] = 1.0 + minf(floor(float(_st["chain_t"]) / 1.5) * 0.5, 3.0)
		_st["chain"] = float(_st["chain"]) + (absf(car.speed_kmh) * 0.6 + slip * 6.0) * delta
	else:
		_st["idle_t"] = float(_st["idle_t"]) + delta
		if float(_st["idle_t"]) > 1.0 and float(_st["chain"]) > 0.0:
			# bank the chain with its multiplier
			_st["score"] = float(_st["score"]) + float(_st["chain"]) * float(_st["combo"])
			_st["chain"] = 0.0
			_st["chain_t"] = 0.0
			_st["combo"] = 1.0


func _hud_zone(d: ActivityDef, t: float) -> void:
	if Game.hud == null:
		return
	var line1 := ""
	var line2 := ""
	if d.kind == ActivityDef.Kind.SPEED_ZONE:
		var avg := float(_st["dist"]) / maxf(t, 0.01) * 3.6
		line1 = "AVG " + d.format_value(avg, _mph())
		line2 = "%s target %s" % [_star_text(3), d.format_value(d.targets[2], _mph())]
	else:
		var total := float(_st["score"]) + float(_st["chain"]) * float(_st["combo"])
		line1 = d.format_value(total)
		line2 = "CHAIN %s  x%.1f" % [d.format_value(float(_st["chain"])), float(_st["combo"])]
	if bests.has(d.id):
		line2 += "   ·   PB " + d.format_value(float(bests[d.id]), _mph())
	Game.hud.call("show_activity", "%s · %s" % [d.kind_name().to_upper(), d.display_name], line1, line2)


func _show_checkpoint(d: ActivityDef, idx: int) -> void:
	if idx >= d.points.size() or _marker == null:
		return
	var p := d.points[idx]
	var prev := d.position if idx == 0 else d.points[idx - 1]
	var h := p - prev
	h.y = 0.0
	if h.length() < 1.0:
		h = d.heading
	h = h.normalized()
	_marker.global_transform = Transform3D(Basis(Vector3.UP, atan2(h.x, h.z)).scaled(Vector3(clampf((d.width + 5.0) / 13.0, 0.8, 2.2), 1, 1)), p)
	_marker.visible = true
	if Game.world != null and Game.world.has_method("set_route_target"):
		Game.world.call("set_route_target", p)


func _race_tick(delta: float, d: ActivityDef, p: Vector3, t: float) -> void:
	var cp: int = _st["cp"]
	var target := d.points[cp]
	var dist := Vector2(p.x - target.x, p.z - target.z).length()
	if dist < maxf(d.width * 0.5 + 9.0, 14.0) and absf(p.y - target.y) < 10.0:
		cp += 1
		_st["cp"] = cp
		_st["last_d"] = 1e9
		_st["away_t"] = 0.0
		if cp >= d.points.size():
			_finish(d, t)
			return
		_play_chime(1.25)
		Game.show_notification("Checkpoint %d / %d" % [cp, d.points.size() - 1], ActivityDef.format_time(t), "info")
		_show_checkpoint(d, cp)
		return
	# abandon when off the race road for 10 s (straight-line distance to the next checkpoint grows
	# legitimately in switchbacks, so it is not used)
	var w: Node = Game.world
	var on_road := true
	if w != null and "data" in w:
		var nr: Dictionary = (w.get("data") as WorldData).nearest_road(p.x, p.z, 2)
		on_road = not nr.is_empty() and int(nr["road"]) == d.road and float(nr["d"]) < d.width * 0.5 + 25.0
	_st["away_t"] = 0.0 if on_road else float(_st["away_t"]) + delta
	if float(_st["away_t"]) > 10.0:
		_stop("Race abandoned (left the route)")
		return
	if Game.hud != null:
		var remaining := dist
		for k in range(cp, d.points.size() - 1):
			remaining += d.points[k].distance_to(d.points[k + 1])
		var line2 := "CP %d / %d   ·   %.1f km to go" % [cp, d.points.size() - 1, remaining / 1000.0]
		if bests.has(d.id):
			line2 += "   ·   PB " + ActivityDef.format_time(float(bests[d.id]))
		Game.hud.call("show_activity", "%s · %s" % [d.kind_name().to_upper(), d.display_name], ActivityDef.format_time(t), line2)


# ------------------------------------------------------------------------------------------------
# danger signs: take-off from the ramp, distance to the first ground contact
func _update_jump(delta: float, car: CarController, p: Vector3) -> void:
	if _jump.is_empty():
		for d in defs:
			if d.kind != ActivityDef.Kind.DANGER_SIGN or _cooldown.has(d.id):
				continue
			var rel := p - d.prop_position
			if rel.length() > 14.0:
				continue
			var along := rel.dot(d.heading)
			var side := absf(rel.dot(d.heading.cross(Vector3.UP).normalized()))
			if along > 2.0 and along < 9.0 and side < 3.6 and car.forward_speed > 8.0 and car.linear_velocity.dot(d.heading) > 0.0:
				_jump = {"id": d.id, "start": p, "air": 0.0, "armed_t": 0.0}
				return
		return
	var d: ActivityDef = by_id[_jump["id"]]
	_jump["armed_t"] = float(_jump["armed_t"]) + delta
	if car.grounded_wheels == 0:
		if float(_jump["air"]) == 0.0:
			_jump["start"] = p
		_jump["air"] = float(_jump["air"]) + delta
	elif float(_jump["air"]) > 0.35 and car.grounded_wheels >= 2:
		var s: Vector3 = _jump["start"]
		var dist := Vector2(p.x - s.x, p.z - s.z).length()
		_jump = {}
		_cooldown[d.id] = 3.0
		if car.global_transform.basis.y.y > 0.5:
			_finish(d, dist)
		else:
			Game.show_notification("DANGER SIGN · " + d.display_name, "Crashed landing — no score", "info")
		return
	if float(_jump["armed_t"]) > 6.0 or (float(_jump["air"]) == 0.0 and float(_jump["armed_t"]) > 1.5):
		_jump = {}


# ------------------------------------------------------------------------------------------------
func _finish(d: ActivityDef, value: float) -> void:
	var had := bests.has(d.id)
	var better := not had or (value < float(bests[d.id]) if d.lower_is_better else value > float(bests[d.id]))
	var st := d.stars_for(value)
	var old_st := int(stars.get(d.id, 0))
	if better:
		bests[d.id] = value
	var earned := 0
	if st > old_st:
		stars[d.id] = st
		earned = (st - old_st) * d.reward
		credits += earned
	var body := "%s   %s" % [d.format_value(value, _mph()), _star_text(st)]
	if better and had:
		body += "   NEW PB"
	if earned > 0:
		body += "   +%s CR" % ActivityDef._thousands(earned)
	Game.show_notification("%s · %s" % [d.kind_name(), d.display_name], body, "event")
	if Game.hud != null:
		Game.hud.call("show_center", _star_text(st) + "  " + d.format_value(value, _mph()), 2.5,
			UiTheme.GOOD if st >= 3 else UiTheme.ACCENT)
	_play_chime(1.5 if st > 0 else 0.8)
	_refresh_label(d)
	if active == d:
		_end_common()
	if Game.main != null and Game.main.has_method("save_game"):
		Game.main.call_deferred("save_game")


func _play_chime(pitch: float) -> void:
	if _chime != null and _chime.stream != null:
		_chime.pitch_scale = pitch
		_chime.play()


static func _star_text(n: int) -> String:
	return "★".repeat(n) + "☆".repeat(3 - n)


func _mph() -> bool:
	return bool(Game.settings.get("units_mph", false))


# ------------------------------------------------------------------------------------------------
# festival boards
func on_board_smashed(pos: Vector3) -> void:
	if _boards == null:
		return
	var best := -1
	var bd := 4.0
	for i in _boards.points.size():
		var dd := _boards.points[i].distance_to(pos)
		if dd < bd:
			bd = dd
			best = i
	if best < 0 or boards_smashed.has(best):
		return
	boards_smashed[best] = true
	credits += _boards.reward
	var n := boards_smashed.size()
	var total := _boards.points.size()
	Game.show_notification("Festival Board %d / %d" % [n, total], "+%d CR" % _boards.reward, "event")
	_play_chime(1.8)
	var st := _boards.stars_for(float(n))
	if st > int(stars.get("boards", 0)):
		stars["boards"] = st
	bests["boards"] = float(n)


func _apply_smashed() -> void:
	if _boards == null or Game.world == null:
		return
	var props: Node = Game.world.get("props")
	if props == null or not props.has_method("remove_smashable_near"):
		return
	for i in boards_smashed.keys():
		var idx := int(i)
		if idx < _boards.points.size():
			props.call("remove_smashable_near", _boards.points[idx], 3.0)


# ------------------------------------------------------------------------------------------------
# save / load, map, console
func get_bests() -> Dictionary:
	return {"values": bests.duplicate(), "stars": stars.duplicate(), "boards": boards_smashed.keys()}


func get_credits() -> int:
	return credits


func set_bests(data: Dictionary, cr: int) -> void:
	credits = cr
	bests = (data.get("values", {}) as Dictionary).duplicate()
	stars = (data.get("stars", {}) as Dictionary).duplicate()
	boards_smashed.clear()
	for b in data.get("boards", []):
		boards_smashed[int(b)] = true
	for d in defs:
		_refresh_label(d)
	if is_inside_tree():
		_apply_smashed.call_deferred()


func get_markers() -> Array:
	## map / minimap icons
	var out: Array = []
	for d in defs:
		if d.kind == ActivityDef.Kind.COLLECTIBLES:
			for i in d.points.size():
				if not boards_smashed.has(i):
					out.append({"pos": d.points[i], "kind": "board", "name": "Festival Board", "stars": 0})
			continue
		var kind: String = ["trap", "zone", "drift", "jump", "race", "trial"][d.kind]
		out.append({"pos": d.prop_position if d.kind == ActivityDef.Kind.DANGER_SIGN else d.position, "kind": kind,
			"name": "%s · %s" % [d.kind_name(), d.display_name], "stars": int(stars.get(d.id, 0)), "id": d.id})
	return out


func total_stars() -> int:
	var s := 0
	for k in stars:
		s += int(stars[k])
	return s


func find(query: String) -> ActivityDef:
	var q := query.to_lower()
	if by_id.has(q):
		return by_id[q]
	for d in defs:
		if d.display_name.to_lower().contains(q) or d.id.contains(q):
			return d
	return null


func teleport_to(d: ActivityDef) -> void:
	var start := d.position - d.heading * 60.0
	var h := d.heading
	if d.kind == ActivityDef.Kind.DANGER_SIGN:
		start = d.prop_position - d.heading * 120.0
	elif d.kind == ActivityDef.Kind.COLLECTIBLES:
		return
	var w: Node = Game.world
	if w != null and w.has_method("prepare_area"):
		w.call("prepare_area", start)
	var xf: Transform3D
	if d.kind == ActivityDef.Kind.DANGER_SIGN:
		var y := float(w.call("height_at", start.x, start.z)) if w != null else start.y
		xf = Transform3D(Basis.looking_at(h, Vector3.UP), Vector3(start.x, y + 0.6, start.z))
	else:
		# on the activity's own road, 30 samples (60 m) before the gate, in the travel lane — the
		# nearest road to that point can be a crossing road
		var data: WorldData = w.get("data")
		var r: Dictionary = data.roads[d.road]
		var n := (r["x"] as PackedFloat32Array).size()
		var i := d.s0 - 30 * d.dir
		i = posmod(i, n) if r["closed"] else clampi(i, 0, n - 1)
		var p := data.road_point(d.road, i)
		var dir := data.road_dir(d.road, i) * float(d.dir)
		dir.y = 0.0
		dir = dir.normalized()
		var right := dir.cross(Vector3.UP).normalized()
		var lane := 0.0
		if int(r["lanes"]) >= 2:
			lane = float(r["lane_width"]) * 0.5 + float(r["median"]) * 0.5 + (float(r["lane_width"]) if int(r["lanes"]) >= 4 else 0.0)
		w.call("prepare_area", p)
		xf = Transform3D(Basis.looking_at(dir, Vector3.UP), p + right * lane + Vector3.UP * 0.55)
	if active != null:
		_stop("Cancelled")
	Game.player_car.reset_to(xf)
	_prev_side.clear()
	if Game.camera_rig != null:
		Game.camera_rig.call("snap")


func console_command(args: Array) -> String:
	if args.is_empty() or args[0] == "list":
		var lines: Array[String] = ["%d activities, %d stars, %d CR, boards %d/%d" % [defs.size(), total_stars(), credits,
			boards_smashed.size(), _boards.points.size() if _boards != null else 0]]
		for d in defs:
			if d.kind == ActivityDef.Kind.COLLECTIBLES:
				continue
			var pb := d.format_value(float(bests[d.id]), _mph()) if bests.has(d.id) else "—"
			lines.append("  %-13s %-12s %-28s %s  PB %s" % [d.id, d.kind_name(), d.display_name, _star_text(int(stars.get(d.id, 0))), pb])
		return "\n".join(lines)
	match String(args[0]):
		"start", "tp", "go":
			if args.size() < 2:
				return "usage: event start <id|name>"
			var d := find(" ".join(args.slice(1)))
			if d == null:
				return "no activity matching '%s'" % " ".join(args.slice(1))
			teleport_to(d)
			return "teleported to %s · %s — drive through the start" % [d.kind_name(), d.display_name]
		"stop":
			if active == null:
				return "no activity running"
			_stop("Cancelled")
			return "stopped"
	return "usage: event <list|start name|stop>"
