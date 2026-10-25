class_name EventManager
extends Node3D
## Road activities: speed traps, speed zones, drift zones, jumps, a checkpoint road race
## and a time trial on the Grand Valley Loop. Detection uses the road raster, so an
## event triggers when the player's nearest road sample crosses the gate index.

var world: WorldGen
var player: Car
var events: Array[Dictionary] = []
var active: Dictionary = {}
var status_text := ""
var _last := Vector4(-1, -1, -1, -1)
var _jump: Dictionary = {}
var colors := {"trap": Color(1.0, 0.25, 0.6), "zone": Color(0.2, 0.7, 1.0), "drift": Color(1.0, 0.55, 0.1), "jump": Color(1.0, 0.85, 0.1), "race": Color(0.3, 1.0, 0.4), "trial": Color(0.8, 0.4, 1.0)}

func setup(w: WorldGen, p: Car) -> void:
	world = w; player = p
	_place_events()
	for e in events: _build_marker(e)

func _straightness(ri: int, i: int, span: int) -> float:
	var road: Dictionary = world.roads[ri]
	var n: int = road.pts.size()
	var acc := 0.0
	for k in range(-span, span + 1, 2):
		var j := i + k
		if not road.closed and (j < 0 or j >= n): return 1e9
		acc += absf(road.curv[posmod(j, n)])
	return acc

func _curviness(ri: int, a: int, b: int) -> float:
	var road: Dictionary = world.roads[ri]
	var n: int = road.pts.size()
	var acc := 0.0
	for j in range(a, b): acc += absf(road.curv[posmod(j, n)])
	return acc

func _best_straight(ri: int, from: int, to: int, span: int) -> int:
	var best := from; var bv := 1e9
	for i in range(from, to, 5):
		if world.roads[ri].tunnel[posmod(i, world.roads[ri].pts.size())] == 1: continue
		var s := _straightness(ri, i, span)
		if s < bv: bv = s; best = i
	return best

func _place_events() -> void:
	var names_trap := ["Valley Radar", "Highway Flash", "Mesa Beam", "Coast Snap", "Pine Gun"]
	var loop_n: int = world.roads[0].pts.size()
	# speed traps on long straights
	var trap_roads := [[1, 50, 770], [0, 200, 1200], [0, 2600, 3600], [7, 40, 320], [0, 4000, 4800]]
	for k in trap_roads.size():
		var tr: Array = trap_roads[k]
		var ri: int = tr[0]
		var n: int = world.roads[ri].pts.size()
		var i := _best_straight(ri, tr[1], mini(tr[2], n - 30), 25)
		events.append({"type": "trap", "name": names_trap[k], "road": ri, "a": i, "b": i})
	# speed zones
	var zr := [[1, 100, 600], [0, 1500, 2300], [2, 50, 700]]
	var zn := ["Crossland Zone", "Ridge Run Zone", "Meridian Zone"]
	for k in zr.size():
		var ri: int = zr[k][0]
		var a := _best_straight(ri, zr[k][1], zr[k][2], 50) - 50
		events.append({"type": "zone", "name": zn[k], "road": ri, "a": maxi(a, 2), "b": maxi(a, 2) + 110})
	# drift zones on the curviest sections
	var dr := [[10, 0], [4, 0], [0, -1], [5, 0]]
	var dn := ["Switchback Drift", "Pinecut Drift", "Hairpin Drift", "Mesa Drift"]
	for k in dr.size():
		var ri: int = dr[k][0]
		var n: int = world.roads[ri].pts.size()
		var best := 5; var bv := -1.0
		var lo := 5; var hi := n - 90
		if ri == 0: lo = 3200; hi = 4100
		for i in range(lo, hi, 10):
			var c := _curviness(ri, i, i + 80)
			if c > bv: bv = c; best = i
		events.append({"type": "drift", "name": dn[k], "road": ri, "a": best, "b": best + 80})
	# jumps on dirt roads: ramp on the carriageway
	for jr in [[5, "Mesa Leap"], [6, "Dune Hopper"], [4, "Pine Launch"]]:
		var ri: int = jr[0]
		var n: int = world.roads[ri].pts.size()
		var i := _best_straight(ri, 60, n - 60, 20)
		events.append({"type": "jump", "name": jr[1], "road": ri, "a": i, "b": i})
	# race along the highway and meridian road
	events.append({"type": "race", "name": "Crossland Sprint", "road": 1, "a": 10, "b": world.roads[1].pts.size() - 12, "cps": 8})
	events.append({"type": "race", "name": "Meridian Dash", "road": 2, "a": 10, "b": world.roads[2].pts.size() - 12, "cps": 8})
	# time trial: full loop
	events.append({"type": "trial", "name": "Grand Valley Time Trial", "road": 0, "a": 20, "b": 20 + loop_n, "cps": 20})

func _gate_mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c; m.emission_enabled = true; m.emission = c; m.emission_energy_multiplier = 1.5
	return m

func _frame(ri: int, i: int) -> Transform3D:
	var p := world.road_point(ri, i)
	var d := world.road_dir(ri, i)
	var f := Vector3(d.x, 0, d.z).normalized()
	var r := f.cross(Vector3.UP).normalized()
	return Transform3D(Basis(r, Vector3.UP, -f), p)

func _build_marker(e: Dictionary) -> void:
	var col: Color = colors[e.type]
	var road: Dictionary = world.roads[e.road]
	var hw: float = road.width * 0.5 + 1.5
	var gates: Array = [e.a] if e.a == e.b else [e.a, e.b]
	if e.type == "jump": gates = [e.a - 25]
	for gi in gates:
		var xf := _frame(e.road, gi)
		var gate := MeshInstance3D.new()
		gate.mesh = Kit.mesh("EventGate", Vector3(hw * 2.0, 0.4, 0.4), col)
		gate.transform = xf.scaled_local(Vector3(hw / 6.0, 1.0, 1.0))
		gate.material_override = _gate_mat(col)
		add_child(gate)
		var lbl := Label3D.new()
		lbl.text = e.name.to_upper()
		lbl.font_size = 96; lbl.outline_size = 18
		lbl.modulate = col
		lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lbl.pixel_size = 0.02
		lbl.position = xf.origin + Vector3.UP * 8.0
		lbl.visibility_range_end = 400.0
		add_child(lbl)
	if e.type == "jump":
		var xf := _frame(e.road, e.a)
		var ramp := StaticBody3D.new()
		ramp.set_meta("surface", WorldGen.Surface.CONCRETE)
		var cs := CollisionShape3D.new()
		var bx := BoxShape3D.new(); bx.size = Vector3(6.0, 0.6, 14.0)
		cs.shape = bx
		ramp.add_child(cs)
		var mi := MeshInstance3D.new()
		mi.mesh = Kit.mesh("JumpRamp", Vector3(6.0, 0.6, 14.0), Color(0.8, 0.7, 0.2))
		ramp.add_child(mi)
		var tilt := Basis(Vector3.RIGHT, deg_to_rad(11.0))
		ramp.transform = Transform3D(xf.basis * tilt, xf.origin + Vector3.UP * 1.0)
		add_child(ramp)
		var sign_xf := _frame(e.road, e.a - 30)
		var sg := MeshInstance3D.new()
		sg.mesh = Kit.mesh("DangerSign", Vector3(1.6, 1.6, 0.1), Color(1, 0.8, 0.1))
		sg.transform = Transform3D(sign_xf.basis, sign_xf.origin + sign_xf.basis.x * (hw + 1.0))
		add_child(sg)

func _process(dt: float) -> void:
	if player == null: return
	var p := player.global_position
	var rs := world.raster_sample(p.x, p.z)
	var kmh := absf(player.speed) * 3.6
	if rs.z >= 0.0 and rs.x < world.roads[int(rs.z)].width * 0.5 + 4.0:
		if _last.z == rs.z: _check_cross(int(rs.z), int(_last.w), int(rs.w), kmh)
		_last = rs
	else:
		_last = Vector4(-1, -1, -1, -1)
	_update_active(dt, kmh, rs)
	_update_jump(dt)

func _crossed(road: int, a: int, b: int, gate: int) -> bool:
	var n: int = world.roads[road].pts.size()
	gate = posmod(gate, n)
	if absi(b - a) > 20: return false
	return (a < gate and b >= gate)

func _check_cross(road: int, a: int, b: int, kmh: float) -> void:
	for e in events:
		if e.road != road: continue
		match e.type:
			"trap":
				if _crossed(road, a, b, e.a):
					var best := Game.record_best(e.name, kmh)
					Game.toast("%s  %d km/h%s" % [e.name.to_upper(), int(_disp(kmh)), "  NEW BEST!" if best else ""], "event")
			"zone", "drift":
				if not active.has(e.name) and _crossed(road, a, b, e.a):
					active[e.name] = {"e": e, "t": 0.0, "dist": 0.0, "score": 0.0, "combo": 1.0}
					Game.toast(e.name.to_upper() + " started", "event")
			"race", "trial":
				if not active.has(e.name) and _crossed(road, a, b, e.a):
					active[e.name] = {"e": e, "t": 0.0, "next": 1, "dist": 0.0}
					Game.toast(e.name.to_upper() + " — GO!", "event")

func _disp(kmh: float) -> float:
	return kmh if Game.settings.units_kmh else kmh * 0.621371

func _update_active(dt: float, kmh: float, rs: Vector4) -> void:
	status_text = ""
	var done: Array = []
	for k in active.keys():
		var a: Dictionary = active[k]
		var e: Dictionary = a.e
		a.t += dt
		var n: int = world.roads[e.road].pts.size()
		var on_road: bool = int(rs.z) == e.road
		# tolerate brief raster switches at junctions / crossings
		a.off = 0.0 if on_road else a.get("off", 0.0) + dt
		var lost: bool = a.off > 4.0
		var idx := int(rs.w)
		var span: int = e.b - e.a
		var prog := float(posmod(idx - e.a, n)) / maxf(span, 1.0) if on_road else -1.0
		match e.type:
			"zone":
				a.dist += absf(player.speed) * dt
				var avg: float = a.dist / maxf(a.t, 0.01) * 3.6
				status_text = "%s  avg %d %s" % [e.name, int(_disp(avg)), _unit()]
				if on_road and prog >= 1.0 and prog < 1.1:
					var best := Game.record_best(e.name, avg)
					Game.toast("%s  avg %d %s%s" % [e.name.to_upper(), int(_disp(avg)), _unit(), "  NEW BEST!" if best else ""], "event")
					done.append(k)
				elif lost or a.t > 120.0:
					Game.toast(e.name + " failed", "warn"); done.append(k)
			"drift":
				var ang := absf(player.drift_angle)
				if ang > 12.0 and kmh > 30.0 and ang < 100.0:
					a.score += ang * kmh * dt * 0.1 * a.combo
					a.combo = minf(a.combo + dt * 0.3, 5.0)
				else:
					a.combo = maxf(a.combo - dt * 1.5, 1.0)
				status_text = "%s  %d pts  x%.1f" % [e.name, int(a.score), a.combo]
				if on_road and prog >= 1.0 and prog < 1.1:
					var best := Game.record_best(e.name, a.score)
					Game.toast("%s  %d pts%s" % [e.name.to_upper(), int(a.score), "  NEW BEST!" if best else ""], "event")
					done.append(k)
				elif lost or a.t > 120.0:
					Game.toast(e.name + " ended", "warn"); done.append(k)
			"race", "trial":
				var cps: int = e.cps
				var next_gate: int = e.a + int(span * float(a.next) / cps)
				var gate_dist := player.global_position.distance_to(world.road_point(e.road, next_gate))
				status_text = "%s  CP %d/%d  %s" % [e.name, a.next, cps, _fmt(a.t)]
				if gate_dist < world.roads[e.road].width * 0.5 + 10.0:
					a.next += 1
					if a.next > cps:
						var best := Game.record_best(e.name, a.t, false)
						Game.toast("%s FINISHED  %s%s" % [e.name.to_upper(), _fmt(a.t), "  NEW BEST!" if best else ""], "event")
						done.append(k)
					else:
						Game.toast("Checkpoint %d/%d  %s" % [a.next - 1, cps, _fmt(a.t)], "info")
				elif a.t > 60.0 * 30.0:
					done.append(k)
	for k in done: active.erase(k)

func _update_jump(dt: float) -> void:
	var air := player.airborne_time
	if air > 0.0 and _jump.is_empty():
		_jump = {"start": player.global_position, "t": 0.0}
	if not _jump.is_empty(): _jump.t += dt
	elif air == 0.0 and not _jump.is_empty():
		var d := Vector2(player.global_position.x - _jump.start.x, player.global_position.z - _jump.start.z).length()
		# ignore teleports/respawns and tiny crest hops
		if d > 22.0 and d < 250.0 and _jump.t > 0.6:
			# attribute to the nearest jump event
			var name := "Freestyle Jump"
			for e in events:
				if e.type == "jump" and world.road_point(e.road, e.a).distance_to(_jump.start) < 40.0: name = e.name
			var best := Game.record_best(name, d)
			Game.toast("%s  %.1f m%s" % [name.to_upper(), d, "  NEW BEST!" if best else ""], "event")
		_jump = {}

func _unit() -> String:
	return "km/h" if Game.settings.units_kmh else "mph"

func _fmt(t: float) -> String:
	return "%d:%05.2f" % [int(t / 60.0), fmod(t, 60.0)]

func cancel_all() -> void:
	active.clear()
