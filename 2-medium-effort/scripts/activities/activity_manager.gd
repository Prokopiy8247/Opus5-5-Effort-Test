extends Node3D
## Road activities started by driving through them: speed traps, speed zones, drift zones, danger-sign
## jumps, checkpoint races (with AI rivals) and the Grand Festival Loop time trial, plus festival boards.
## Personal bests persist through Game.bests (save system).

const NO_TRAFFIC_ROADS: PackedStringArray = ["Dune Track", "Windfarm Track"]

var world: WorldData
var events: Array = []  # dictionaries
var boards: Array = []  # [pos, node, taken]
var active: Dictionary = {}  # running timed event
var hud: Node
var _gate_scenes: Dictionary = {}
var rivals: Array = []  # [car, autopilot]
var countdown: float = 0.0
var boards_taken: int = 0
var _last_jump_ramp: int = -1
var _prev_pos: Vector3 = Vector3.ZERO
var pending_race: Dictionary = {}
var pending_t: float = 0.0
var stats: Dictionary = {"traps": 0, "zones": 0, "drifts": 0, "jumps": 0, "races": 0, "boards": 0}


func _gate(nm: String) -> PackedScene:
	if not _gate_scenes.has(nm):
		_gate_scenes[nm] = load("res://assets/imported/props/%s.glb" % nm)
	return _gate_scenes[nm]


func road_by_name(n: String) -> int:
	for i in world.roads.size():
		if world.roads[i].name == n:
			return i
	return -1


func build(w: WorldData) -> void:
	world = w
	hud = Game.hud
	_place_speed_traps()
	_place_zones()
	_place_drifts()
	_place_jumps()
	_place_races()
	_place_boards()
	var car: Node3D = Game.player as Node3D
	if car:
		_prev_pos = car.global_position
	Game.car_changed.connect(_on_car)
	_on_car(Game.player)
	print("[activities] ", events.size(), " events, ", boards.size(), " boards")


func _on_car(c: Node) -> void:
	if c and c is Car and not (c as Car).landed.is_connected(_on_landed):
		(c as Car).landed.connect(_on_landed)
		_prev_pos = (c as Car).global_position


# ------------------------------------------------------------------ placement
func _straightness(r: Dictionary, i0: int, n: int) -> float:
	var m: float = 0.0
	var c: PackedFloat32Array = r.curv
	for i in range(i0, mini(i0 + n, c.size())):
		m = maxf(m, absf(c[i]))
	return m


func _gate_node(scene: String, ri: int, s: float, label: String, col: Color) -> Node3D:
	var t: Transform3D = world.road_point(ri, s)
	var n: Node3D = _gate(scene).instantiate()
	n.transform = Transform3D(Basis(Vector3.UP, t.basis.get_euler().y), t.origin)
	add_child(n)
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).visibility_range_end = 900.0
	var l := Label3D.new()
	l.text = label
	l.font_size = 96
	l.pixel_size = 0.012
	l.modulate = Color.WHITE
	l.outline_modulate = col.darkened(0.4)
	l.outline_size = 18
	l.position = Vector3(0, 7.6, 0)
	l.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	l.visibility_range_end = 400.0
	n.add_child(l)
	return n


func _place_speed_traps() -> void:
	var cands: Array = []
	for ri in world.roads.size():
		var r: Dictionary = world.roads[ri]
		if r.surface >= 2 or r.length < 400.0:
			continue
		var best_i: int = -1
		var best_k: float = 1.0
		for i in range(25, r.pts.size() - 60, 10):
			var k: float = _straightness(r, i - 25, 60)
			if k < best_k and r.flags[i] == 0:
				best_k = k
				best_i = i
		if best_i >= 0:
			cands.append([best_k, ri, best_i])
	cands.sort_custom(func(a, b): return a[0] < b[0])
	for c in cands.slice(0, 7):
		var r: Dictionary = world.roads[c[1]]
		var s: float = r.dist[c[2]]
		var e: Dictionary = {"type": "trap", "name": "%s Speed Trap" % r.name.get_slice(" ", 0), "road": c[1], "s": s, "id": "trap_%d" % c[1]}
		e.node = _gate_node("gate_trap", c[1], s, "SPEED TRAP", Color(0.2, 0.5, 1.0))
		events.append(e)


func _place_zones() -> void:
	var used: Dictionary = {}
	for ev in events:
		used[ev.road] = true
	var cands: Array = []
	for ri in world.roads.size():
		var r: Dictionary = world.roads[ri]
		if r.surface >= 2 or r.length < 900.0 or used.has(ri):
			continue
		var i: int = int(r.pts.size() * 0.3)
		cands.append([_straightness(r, i, 150), ri, i])
	cands.sort_custom(func(a, b): return a[0] < b[0])
	for c in cands.slice(0, 4):
		var r: Dictionary = world.roads[c[1]]
		var s0: float = r.dist[c[2]]
		var s1: float = minf(s0 + 600.0, r.length - 30.0)
		var e: Dictionary = {"type": "zone", "name": "%s Speed Zone" % r.name.get_slice(" ", 0), "road": c[1], "s": s0, "s1": s1, "id": "zone_%d" % c[1]}
		e.node = _gate_node("gate_zone", c[1], s0, "SPEED ZONE", Color(1.0, 0.2, 0.2))
		e.node2 = _gate_node("gate_zone", c[1], s1, "ZONE END", Color(1.0, 0.2, 0.2))
		events.append(e)


func _place_drifts() -> void:
	var names: PackedStringArray = ["Highland Pass", "North Switchbacks", "Canyon Road", "Orchard Climb", "Summit Descent"]
	for nm in names:
		var ri: int = road_by_name(nm)
		if ri < 0:
			continue
		var r: Dictionary = world.roads[ri]
		# twistiest 400 m window
		var best: float = 0.0
		var bi: int = 20
		for i in range(20, r.pts.size() - 120, 10):
			var sum: float = 0.0
			for k in range(i, i + 100):
				sum += absf(r.curv[k])
			if sum > best:
				best = sum
				bi = i
		var s0: float = r.dist[bi]
		var s1: float = r.dist[mini(bi + 100, r.pts.size() - 2)]
		var e: Dictionary = {"type": "drift", "name": "%s Drift Zone" % nm.get_slice(" ", 0), "road": ri, "s": s0, "s1": s1, "id": "drift_%d" % ri}
		e.node = _gate_node("gate_drift", ri, s0, "DRIFT ZONE", Color(1.0, 0.8, 0.1))
		e.node2 = _gate_node("gate_drift", ri, s1, "DRIFT END", Color(1.0, 0.8, 0.1))
		events.append(e)


func _place_jumps() -> void:
	for spec in [["Dune Track", 0.35], ["Dune Track", 0.7], ["Windfarm Track", 0.55]]:
		var ri: int = road_by_name(spec[0])
		if ri < 0:
			continue
		var r: Dictionary = world.roads[ri]
		var s: float = r.length * spec[1]
		var t: Transform3D = world.road_point(ri, s)
		var ramp: Node3D = _gate("gate_ramp").instantiate()
		# ramp rises toward +Y in Blender = -Z in Godot = road forward
		ramp.transform = Transform3D(Basis(Vector3.UP, t.basis.get_euler().y), t.origin + Vector3(0, -0.05, 0))
		add_child(ramp)
		var body := StaticBody3D.new()
		body.collision_layer = 1 | 2
		body.set_meta("road_surface", WorldData.Surface.CONCRETE)
		var cs := CollisionShape3D.new()
		var shape := ConvexPolygonShape3D.new()
		shape.points = PackedVector3Array([Vector3(-3.5, 0, 0), Vector3(3.5, 0, 0), Vector3(3.5, 2.6, -14), Vector3(-3.5, 2.6, -14), Vector3(-3.5, 0, -14), Vector3(3.5, 0, -14)])
		cs.shape = shape
		body.add_child(cs)
		ramp.add_child(body)
		var sign_n: Node3D = _gate("sign_danger").instantiate()
		var sp: Vector3 = world.road_point(ri, maxf(0.0, s - 60.0), r.hw + 1.5).origin
		sign_n.position = Vector3(sp.x, world.height(sp.x, sp.z), sp.z)
		sign_n.rotation.y = t.basis.get_euler().y
		add_child(sign_n)
		var e: Dictionary = {"type": "jump", "name": "%s Danger Sign" % spec[0].get_slice(" ", 0), "road": ri, "s": s, "id": "jump_%d_%d" % [ri, int(s)], "pos": t.origin}
		e.node = ramp
		var l := Label3D.new()
		l.text = "DANGER SIGN"
		l.font_size = 96
		l.pixel_size = 0.012
		l.outline_size = 18
		l.outline_modulate = Color(0.6, 0.2, 0.0)
		l.position = Vector3(0, 6.0, 0)
		l.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
		ramp.add_child(l)
		events.append(e)


func _place_races() -> void:
	var races: Array = [
		["Coastal Sprint", ["Harbour Coast Road", "West Coast Road"], true],
		["Highland Hillclimb", ["Cliffside Climb", "Highland Pass"], true],
		["Ochre Canyon Dash", ["Mesa Run", "Canyon Road"], true],
		["Grand Festival Loop", [], false],
	]
	for rc in races:
		var legs: Array = []
		if rc[1].is_empty():
			for i in world.roads.size():
				if world.roads[i].loop:
					legs.append(i)
		else:
			for nm in rc[1]:
				legs.append(road_by_name(nm))
		var cps: Array = []
		var total: float = 0.0
		for li in legs.size():
			var r: Dictionary = world.roads[legs[li]]
			var s: float = 30.0 if li == 0 else 0.0
			var spacing: float = 350.0 if not rc[1].is_empty() else 900.0
			while s < r.length - 20.0:
				cps.append([legs[li], s])
				s += spacing
			total += r.length
		var last: Dictionary = world.roads[legs[legs.size() - 1]]
		if rc[1].is_empty():
			cps.append([legs[0], 30.0])  # loop finishes at the start line
		else:
			cps.append([legs[legs.size() - 1], last.length - 25.0])
		var e: Dictionary = {"type": "race", "name": rc[0], "road": legs[0], "s": 30.0, "legs": legs, "cps": cps, "rivals": rc[2], "id": "race_" + rc[0].to_snake_case(), "length": total}
		e.node = _gate_node("gate_race", legs[0], 30.0, rc[0].to_upper() if rc[2] else "TIME TRIAL: " + rc[0].to_upper(), Color(1.0, 0.36, 0.62))
		events.append(e)


func _place_boards() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.36, 0.62)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.3, 0.55)
	mat.emission_energy_multiplier = 1.2
	var mesh := BoxMesh.new()
	mesh.size = Vector3(2.4, 1.4, 0.12)
	mesh.material = mat
	var n_boards: int = 0
	var tries: int = 0
	while n_boards < 20 and tries < 400:
		tries += 1
		var ri: int = rng.randi() % world.roads.size()
		var r: Dictionary = world.roads[ri]
		var s: float = rng.randf_range(40.0, r.length - 40.0)
		var side: float = 1.0 if rng.randf() < 0.5 else -1.0
		var t: Transform3D = world.road_point(ri, s, side * (r.hw + 3.5))
		var ok: bool = t.origin.y > 2.0
		for b in boards:
			if (b[0] as Vector3).distance_to(t.origin) < 300.0:
				ok = false
		if not ok:
			continue
		var g: float = world.height(t.origin.x, t.origin.z)
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.position = Vector3(t.origin.x, g + 1.6, t.origin.z)
		mi.rotation.y = t.basis.get_euler().y
		mi.visibility_range_end = 500.0
		add_child(mi)
		var post := MeshInstance3D.new()
		var pm := BoxMesh.new()
		pm.size = Vector3(0.12, 1.6, 0.12)
		post.mesh = pm
		post.position = Vector3(0, -1.2, 0)
		mi.add_child(post)
		boards.append([mi.position, mi, false])
		n_boards += 1


# ------------------------------------------------------------------ runtime
func _road_s(car: Node3D) -> Dictionary:
	var q: Dictionary = world.road_query(car.global_position.x, car.global_position.z, 25.0)
	if not q.ok:
		return {}
	var r: Dictionary = world.roads[q.road]
	return {"road": q.road, "s": r.dist[q.seg] + q.t * WorldData.STEP, "d": q.d, "hw": r.hw}


func _crossed(prev: Dictionary, now: Dictionary, ri: int, s: float) -> bool:
	if prev.is_empty() or now.is_empty() or prev.road != ri or now.road != ri:
		return false
	if now.d > now.hw + 4.0:
		return false
	return (prev.s - s) * (now.s - s) <= 0.0 and absf(prev.s - now.s) < 30.0


var _prev_q: Dictionary = {}


func _process(delta: float) -> void:
	var _pf: int = Time.get_ticks_usec()
	_inner_activities(delta)
	Game.prof_add("activities", _pf)


func _inner_activities(delta: float) -> void:
	var car: Car = Game.player as Car
	if car == null or not is_instance_valid(car) or world == null:
		return
	var q: Dictionary = _road_s(car)
	var kmh: float = car.kmh()
	if countdown > 0.0:
		countdown -= delta
		car.in_throttle = 0.0
		car.in_brake = 1.0
		car.linear_velocity = car.linear_velocity.lerp(Vector3.ZERO, 0.2)
		_show("RACE STARTS IN", ["%d" % ceili(countdown)], Color(1.0, 0.36, 0.62))
		if countdown <= 0.0:
			get_parent().player_input.enabled = true
			active.t = 0.0
			for rv in rivals:
				(rv[0] as Car).freeze = false
			Game.toast("GO!", active.ev.name, Color(1.0, 0.36, 0.62))
		_prev_q = q
		return
	# race gates only offer the event; the player confirms with Enter
	if not pending_race.is_empty() and active.is_empty():
		pending_t -= delta
		_show(pending_race.name, ["%.1f km  ·  %s" % [pending_race.length / 1000.0, "3 rivals" if pending_race.rivals else "time trial"], "Press ENTER to start"], Color(1.0, 0.36, 0.62))
		if Input.is_action_just_pressed("start_event"):
			var e2: Dictionary = pending_race
			pending_race = {}
			_start_race(e2, car)
		elif pending_t <= 0.0:
			pending_race = {}
			_clear_show()
	# discoverable gates
	if active.is_empty():
		for e in events:
			if _crossed(_prev_q, q, e.road, e.s):
				_trigger(e, car, q)
				break
	else:
		_update_active(car, q, delta)
	# jump scoring uses the landed signal; boards by proximity
	for b in boards:
		if not b[2] and (b[0] as Vector3).distance_to(car.global_position) < 4.0:
			b[2] = true
			(b[1] as Node3D).visible = false
			boards_taken += 1
			stats.boards += 1
			Game.bests["boards"] = maxi(int(Game.bests.get("boards", 0)), boards_taken)
			Game.credits += 500
			Game.toast("Festival board smashed!", "%d / %d   +500 CR" % [boards_taken, boards.size()], Color(1.0, 0.36, 0.62))
	_update_icons(car)
	_prev_q = q


func _show(title: String, lines: Array, col: Color) -> void:
	if hud:
		hud.set_activity(title, PackedStringArray(lines), col)


func _clear_show() -> void:
	if hud:
		hud.set_activity("", PackedStringArray(), Color.WHITE)


func _best_text(id: String, v: float, higher_better: bool, unit: String, fmt: String = "%.0f") -> String:
	var prev: Variant = Game.bests.get(id)
	var is_pb: bool = prev == null or (v > float(prev) if higher_better else v < float(prev))
	if is_pb:
		Game.bests[id] = v
		Game.credits += 1000
		return "NEW PERSONAL BEST!  " + (fmt % v) + unit
	return ("Best: " + fmt + unit) % float(prev)


func _trigger(e: Dictionary, car: Car, q: Dictionary) -> void:
	match e.type:
		"trap":
			var v: float = car.kmh()
			stats.traps += 1
			var u: String = " km/h"
			var shown: float = v
			if Game.settings.units_mph:
				shown = v * 0.621371
				u = " mph"
			var stars: int = 3 if v > 200.0 else (2 if v > 150.0 else (1 if v > 100.0 else 0))
			Game.toast("%s: %d%s %s" % [e.name, roundi(shown), u, "★".repeat(stars)], _best_text(e.id, v, true, " km/h"), Color(0.2, 0.55, 1.0))
		"zone", "drift":
			active = {"ev": e, "t": 0.0, "dist": 0.0, "score": 0.0, "combo": 1.0, "drift_t": 0.0, "dir": signf(q.s - _prev_q.s) if not _prev_q.is_empty() else 1.0}
			Game.toast(e.name, "Zone started - " + ("keep your speed up!" if e.type == "zone" else "drift to score!"), Color(1.0, 0.25, 0.25) if e.type == "zone" else Color(1.0, 0.8, 0.1))
		"race":
			pending_race = e
			pending_t = 8.0


func _update_active(car: Car, q: Dictionary, delta: float) -> void:
	var e: Dictionary = active.ev
	active.t += delta
	match e.type:
		"zone":
			active.dist += car.linear_velocity.length() * delta
			var avg: float = active.dist / maxf(active.t, 0.01) * 3.6
			_show(e.name, ["Average  %.0f km/h" % avg, "Time  %.1f s" % active.t], Color(1.0, 0.25, 0.25))
			if _crossed(_prev_q, q, e.road, e.s1):
				stats.zones += 1
				Game.toast("%s: %.0f km/h average" % [e.name, avg], _best_text(e.id, avg, true, " km/h"), Color(1.0, 0.25, 0.25))
				_end_active()
			elif active.t > 90.0 or q.is_empty() or q.road != e.road:
				Game.toast(e.name, "Zone failed", Color(0.6, 0.6, 0.6))
				_end_active()
		"drift":
			var ang: float = absf(car.drift_angle)
			var v: float = car.kmh()
			if ang > 10.0 and v > 25.0 and car.grounded_wheels >= 3:
				active.drift_t += delta
				active.combo = minf(5.0, 1.0 + active.drift_t * 0.35)
				active.score += ang * v * delta * 0.6 * active.combo
			else:
				active.drift_t = maxf(0.0, active.drift_t - delta * 2.0)
				active.combo = maxf(1.0, active.combo - delta)
			_show(e.name, ["Score  %d" % roundi(active.score), "Combo  x%.1f   angle %d°" % [active.combo, roundi(ang)]], Color(1.0, 0.8, 0.1))
			if _crossed(_prev_q, q, e.road, e.s1):
				stats.drifts += 1
				var stars: int = 3 if active.score > 40000 else (2 if active.score > 20000 else (1 if active.score > 8000 else 0))
				Game.toast("%s: %d pts %s" % [e.name, roundi(active.score), "★".repeat(stars)], _best_text(e.id, active.score, true, " pts"), Color(1.0, 0.8, 0.1))
				_end_active()
			elif active.t > 120.0 or q.is_empty() or q.road != e.road:
				Game.toast(e.name, "Left the zone: %d pts" % roundi(active.score), Color(0.6, 0.6, 0.6))
				_end_active()
		"race":
			_update_race(car, delta)


func _end_active() -> void:
	active = {}
	_clear_show()
	for rv in rivals:
		if is_instance_valid(rv[0]):
			(rv[0] as Node).queue_free()
	rivals.clear()


func _on_landed(air: float, dist: float) -> void:
	var car: Car = Game.player as Car
	for e in events:
		if e.type == "jump" and (e.pos as Vector3).distance_to(car.global_position) < dist + 60.0 and dist > 5.0:
			stats.jumps += 1
			var stars: int = 3 if dist > 90.0 else (2 if dist > 60.0 else (1 if dist > 35.0 else 0))
			Game.toast("%s: %.0f m %s" % [e.name, dist, "★".repeat(stars)], _best_text(e.id, dist, true, " m") + "   air %.1f s" % air, Color(1.0, 0.55, 0.1))
			return


# ------------------------------------------------------------------ races
func _start_race(e: Dictionary, car: Car) -> void:
	active = {"ev": e, "t": 0.0, "cp": 0, "finished": false}
	var start: Transform3D = world.road_point(e.legs[0], 40.0, world.roads[e.legs[0]].lane * 0.5)
	start.origin.y += 0.6
	get_parent().teleport_to(start)
	get_parent().player_input.enabled = false
	countdown = 3.0
	stats.races += 1
	if e.rivals:
		var pool: Array = []
		for i in Game.cars.size():
			if i != Game.current_car_index:
				pool.append(i)
		pool.shuffle()
		for k in 3:
			var d: CarDef = Game.cars[pool[k]]
			var rv := Car.new()
			rv.ai_controlled = true
			rv.setup(d)
			var off: float = -world.roads[e.legs[0]].lane * 0.5 if k % 2 == 0 else world.roads[e.legs[0]].lane * 0.5
			var t: Transform3D = world.road_point(e.legs[0], 40.0 + 9.0 * (k + 1), off)
			t.origin.y += 0.6
			get_parent().add_child(rv)
			rv.global_transform = t
			rv.freeze = true
			rv.set_paint(Color.from_hsv(randf(), 0.8, 0.85), 0, 1, Color.WHITE)
			var ap := RoadAutopilot.new(world, e.legs[0], 40.0 + 9.0 * (k + 1))
			ap.lane_offset = 0.0
			ap.route = []
			for li in range(1, e.legs.size()):
				ap.route.append([e.legs[li], 1])
			ap.target_speed = 200.0 / 3.6 * (0.8 + 0.07 * k)
			rivals.append([rv, ap])
	Game.toast(e.name, "%.1f km  ·  %d checkpoints" % [e.length / 1000.0, e.cps.size()], Color(1.0, 0.36, 0.62))


func _update_race(car: Car, delta: float) -> void:
	var e: Dictionary = active.ev
	var cps: Array = e.cps
	var cp: Array = cps[active.cp]
	var cpt: Transform3D = world.road_point(cp[0], cp[1])
	var d: float = cpt.origin.distance_to(car.global_position)
	if not active.has("cp_node"):
		active.cp_node = _gate_node("gate_check", cp[0], cp[1], "CHECKPOINT", Color(1.0, 0.36, 0.62))
		if Game.hud:
			Game.hud.minimap.waypoint = Vector2(cpt.origin.x, cpt.origin.z)
	if d < world.roads[cp[0]].hw + 8.0:
		active.cp += 1
		(active.cp_node as Node).queue_free()
		active.erase("cp_node")
		if active.cp >= cps.size():
			var t: float = active.t
			var pos: int = 1
			for rv in rivals:
				var ap: RoadAutopilot = rv[1]
				if ap.finished:
					pos += 1
			Game.toast("%s finished  %s  ·  P%d" % [e.name, _fmt_time(t), pos], _best_text(e.id, t, false, "", "%.2f s"), Color(1.0, 0.36, 0.62))
			if Game.hud:
				Game.hud.minimap.waypoint = null
			Game.bests[e.id + "_pos"] = mini(int(Game.bests.get(e.id + "_pos", 9)), pos)
			_end_active()
			return
	# rivals drive with the autopilot; light rubber-banding keeps them close
	for rv in rivals:
		var rc: Car = rv[0]
		var ap: RoadAutopilot = rv[1]
		if not is_instance_valid(rc):
			continue
		var gap: float = rc.global_position.distance_to(car.global_position)
		var ahead: bool = (rc.global_position - car.global_position).dot(-car.global_transform.basis.z) > 0.0
		ap.target_speed = clampf(ap.target_speed + (delta * (-1.5 if ahead and gap > 80.0 else 1.0)), 25.0, 90.0)
		ap.update(rc, delta)
		if ap.finished:
			rc.in_throttle = 0.0
			rc.in_brake = 1.0
		if rc.global_position.y < -20.0:
			ap.finished = true
	var place: int = 1
	for rv in rivals:
		if is_instance_valid(rv[0]) and _progress(rv[1]) > _player_progress(car):
			place += 1
	_show(e.name, ["Time  %s" % _fmt_time(active.t), "Checkpoint  %d / %d" % [active.cp + 1, cps.size()], ("Position  %d / %d" % [place, rivals.size() + 1]) if not rivals.is_empty() else "Time trial"], Color(1.0, 0.36, 0.62))
	if active.t > 1800.0:
		Game.toast(e.name, "Race abandoned", Color(0.6, 0.6, 0.6))
		_end_active()


func _progress(ap: RoadAutopilot) -> float:
	var e: Dictionary = active.ev
	var idx: int = e.legs.find(ap.road)
	var acc: float = 0.0
	for i in maxi(idx, 0):
		acc += world.roads[e.legs[i]].length
	return acc + ap.s + (100000.0 if ap.finished else 0.0)


func _player_progress(car: Car) -> float:
	var e: Dictionary = active.ev
	var q: Dictionary = _road_s(car)
	if q.is_empty():
		return 0.0
	var idx: int = e.legs.find(q.road)
	if idx < 0:
		return 0.0
	var acc: float = 0.0
	for i in idx:
		acc += world.roads[e.legs[i]].length
	return acc + q.s


static func _fmt_time(t: float) -> String:
	return "%d:%05.2f" % [int(t / 60.0), fmod(t, 60.0)]


func start_race_by_index(i: int) -> String:
	var races: Array = events.filter(func(e): return e.type == "race")
	if i < 1 or i > races.size():
		return "race 1..%d" % races.size()
	_end_active()
	_start_race(races[i - 1], Game.player as Car)
	return "starting " + races[i - 1].name


func list_events() -> String:
	var s: String = ""
	for e in events:
		var b: Variant = Game.bests.get(e.id)
		s += "%-6s %-28s %s\n" % [e.type, e.name, ("best %.1f" % float(b)) if b != null else ""]
	s += "boards %d / %d" % [boards_taken, boards.size()]
	return s


func teleport_to_event(nm: String) -> bool:
	for e in events:
		if e.type == nm or e.name.to_lower().begins_with(nm):
			var t: Transform3D = world.road_point(e.road, maxf(0.0, e.s - 120.0), world.roads[e.road].lane * 0.5)
			t.origin.y += 0.6
			get_parent().teleport_to(t)
			return true
	return false


func map_icons() -> Array:
	var out: Array = []
	for e in events:
		var p: Vector3 = world.road_point(e.road, e.s).origin
		var col: Color = {"trap": Color(0.2, 0.5, 1.0), "zone": Color(1.0, 0.25, 0.25), "drift": Color(1.0, 0.75, 0.1), "jump": Color(1.0, 0.5, 0.1), "race": Color(1.0, 0.36, 0.62)}[e.type]
		var letter: String = {"trap": "T", "zone": "Z", "drift": "D", "jump": "J", "race": "R"}[e.type]
		out.append([Vector2(p.x, p.z), col, letter])
	return out


var _icon_t: float = 0.0


func _update_icons(car: Node3D) -> void:
	_icon_t -= get_process_delta_time()
	if _icon_t > 0.0 or Game.hud == null:
		return
	_icon_t = 1.0
	var mm: Node = Game.hud.minimap
	var icons: Array = []
	var p := Vector2(car.global_position.x, car.global_position.z)
	for ic in map_icons():
		if (ic[0] as Vector2).distance_to(p) < 900.0:
			icons.append(ic)
	for b in boards:
		if not b[2] and Vector2(b[0].x, b[0].z).distance_to(p) < 500.0:
			icons.append([Vector2(b[0].x, b[0].z), Color(1.0, 0.36, 0.62, 0.8), "B"])
	mm.icons = icons
