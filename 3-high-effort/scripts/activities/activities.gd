class_name Activities
extends Node3D
## Road activities: speed traps, speed zones, drift zones, jumps, checkpoint races (with AI
## opponents), the Grand Tour time trial and collectible festival boards. Data: data/events.

const EVENT_DIR := "res://data/events/"
const COLORS := {
	EventDef.Kind.SPEED_TRAP: Color(0.75, 0.35, 1.0), EventDef.Kind.SPEED_ZONE: Color(1.0, 0.55, 0.15),
	EventDef.Kind.DRIFT_ZONE: Color(1.0, 0.3, 0.6), EventDef.Kind.JUMP: Color(1.0, 0.85, 0.15),
	EventDef.Kind.RACE: Color(0.25, 0.85, 1.0), EventDef.Kind.TIME_TRIAL: Color(0.95, 0.95, 0.95),
	EventDef.Kind.BOARD: Color(1.0, 0.7, 0.2),
}

class Placed:
	var def: EventDef
	var road: WorldData.Road
	var i0 := 0
	var i1 := 0
	var dir := 1
	var nodes: Array[Node3D] = []
	var collected := false
	var armed := false
	var checkpoints: PackedInt32Array = []

var world: World
var data: WorldData
var main: Node
var placed: Array[Placed] = []
var hud: Control
var hud_title: Label
var hud_value: Label
var hud_sub: Label
var hud_count: Label

# running event state
var running: Placed = null
var state := ""           # "zone", "drift", "jump", "countdown", "race", "result"
var t_elapsed := 0.0
var score := 0.0
var combo := 1.0
var drift_chain := 0.0
var next_cp := 0
var lap := 1
var takeoff := Vector3.ZERO
var air_t := 0.0
var countdown := 0.0
var opponents: Array[Car] = []
var _prev_pos := Vector3.ZERO
var _cooldown := 0.0
var _gate_mat_cache := {}


func setup(w: World, m: Node) -> void:
	world = w
	data = w.data
	main = m
	for f in ResourceLoader.list_directory(EVENT_DIR):
		if not f.ends_with(".tres"):
			continue
		var def := load(EVENT_DIR + f) as EventDef
		if def == null:
			continue
		var road := data.road_by_id(def.road_id)
		if road == null:
			continue
		var p := Placed.new()
		p.def = def
		p.road = road
		var n := road.pts.size()
		p.i0 = clampi(int(def.start_frac * (n - 1)), 2, n - 3)
		p.i1 = clampi(int(def.end_frac * (n - 1)), 2, n - 3)
		if def.start_xz != Vector2.INF:
			p.i0 = clampi(_nearest_index(road, def.start_xz), 2, n - 3)
		if def.end_xz != Vector2.INF:
			p.i1 = clampi(_nearest_index(road, def.end_xz), 2, n - 3)
		p.dir = 1 if p.i1 >= p.i0 else -1
		if def.kind == EventDef.Kind.TIME_TRIAL and road.closed:
			p.i1 = p.i0
			p.dir = 1
		p.collected = Game.personal_bests.has("board_" + def.id)
		_build_visuals(p)
		placed.append(p)
	_make_hud()


func _nearest_index(road: WorldData.Road, xz: Vector2) -> int:
	var best := 0
	var bd := INF
	for i in road.pts.size():
		var d := Vector2(road.pts[i].x, road.pts[i].z).distance_squared_to(xz)
		if d < bd:
			bd = d
			best = i
	return best


# ------------------------------------------------------------------ visuals
func _mat(col: Color, emit: float = 1.5) -> StandardMaterial3D:
	var key := "%s_%s" % [col.to_html(), emit]
	if _gate_mat_cache.has(key):
		return _gate_mat_cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.emission_enabled = true
	m.emission = col
	m.emission_energy_multiplier = emit
	_gate_mat_cache[key] = m
	return m


func _frame(road: WorldData.Road, i: int) -> Array:
	var t := road.tangent(i)
	return [road.pts[i], t, Vector3(-t.z, 0.0, t.x)]


func _gate(p: Placed, i: int, col: Color, label: String, tall: bool = true) -> Node3D:
	var fr := _frame(p.road, i)
	var root := Node3D.new()
	root.position = fr[0]
	root.basis = Basis.looking_at(fr[1], Vector3.UP)
	add_child(root)
	var hw := p.road.width * 0.5 + p.road.shoulder + 0.6
	for side in [-1.0, 1.0]:
		var post := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.18
		cm.bottom_radius = 0.22
		cm.height = 5.5 if tall else 2.5
		post.mesh = cm
		post.material_override = _mat(col, 1.2)
		post.position = Vector3(side * hw, cm.height * 0.5, 0)
		root.add_child(post)
	if tall:
		var bar := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(hw * 2.0 + 0.4, 0.5, 0.35)
		bar.mesh = bm
		bar.material_override = _mat(col.darkened(0.3), 0.6)
		bar.position = Vector3(0, 5.5, 0)
		root.add_child(bar)
	var l := Label3D.new()
	l.text = label
	l.font_size = 64
	l.pixel_size = 0.008
	l.outline_size = 12
	l.modulate = Color.WHITE
	l.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	l.position = Vector3(0, 6.6 if tall else 3.4, 0)
	l.visibility_range_end = 300.0
	root.add_child(l)
	p.nodes.append(root)
	return root


func _build_visuals(p: Placed) -> void:
	var def := p.def
	var col: Color = COLORS[def.kind]
	match def.kind:
		EventDef.Kind.SPEED_TRAP:
			_gate(p, p.i0, col, "%s\nSPEED TRAP" % def.display_name)
		EventDef.Kind.SPEED_ZONE:
			_gate(p, p.i0, col, "%s\nSPEED ZONE" % def.display_name)
			_gate(p, p.i1, col, "ZONE END")
		EventDef.Kind.DRIFT_ZONE:
			_gate(p, p.i0, col, "%s\nDRIFT ZONE" % def.display_name)
			_gate(p, p.i1, col, "DRIFT END")
		EventDef.Kind.JUMP:
			_ramp(p)
		EventDef.Kind.RACE, EventDef.Kind.TIME_TRIAL:
			_gate(p, p.i0, col, "%s\n%s — stop here to start" % [def.display_name, "RACE" if def.kind == EventDef.Kind.RACE else "TIME TRIAL"])
			if def.kind == EventDef.Kind.RACE:
				_gate(p, p.i1, col, "FINISH")
			_build_checkpoints(p)
		EventDef.Kind.BOARD:
			if not p.collected:
				_board(p)


func _build_checkpoints(p: Placed) -> void:
	var step := maxi(int(p.def.checkpoint_spacing_m / 4.0), 20)
	var n := p.road.pts.size()
	if p.def.kind == EventDef.Kind.TIME_TRIAL and p.road.closed:
		var total := n - 1
		var k := step
		while k < total - step / 2:
			p.checkpoints.append(posmod(p.i0 + k, n - 1))
			k += step
		p.checkpoints.append(p.i0)
	else:
		var i := p.i0 + step * p.dir
		while (p.dir > 0 and i < p.i1 - step / 3) or (p.dir < 0 and i > p.i1 + step / 3):
			p.checkpoints.append(i)
			i += step * p.dir
		p.checkpoints.append(p.i1)


func _ramp(p: Placed) -> void:
	var fr := _frame(p.road, p.i0)
	var hw := p.road.width * 0.5 + p.road.shoulder
	var body := StaticBody3D.new()
	body.name = "JumpRamp"
	body.collision_layer = 1
	body.set_meta("surface", Game.Surf.CONCRETE)
	var len := 9.0
	var hgt := 1.7
	var ang := atan2(hgt, len)
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(hw * 2.0, 0.6, sqrt(len * len + hgt * hgt))
	cs.shape = box
	body.add_child(cs)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = box.size
	mi.mesh = bm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.85, 0.7, 0.2)
	m.roughness = 0.8
	mi.material_override = m
	body.add_child(mi)
	# ramp rises along the road direction, lip at i0
	var center: Vector3 = fr[0] - (fr[1] as Vector3) * (len * 0.5) + Vector3.UP * (hgt * 0.5 - 0.25)
	body.basis = Basis.looking_at(fr[1], Vector3.UP) * Basis(Vector3.RIGHT, ang)
	body.position = center
	add_child(body)
	p.nodes.append(body)
	# danger sign before the ramp
	var si := clampi(p.i0 - 18, 0, p.road.pts.size() - 1)
	var sf := _frame(p.road, si)
	var sign := Label3D.new()
	sign.text = "⚠ %s\nDANGER SIGN" % p.def.display_name
	sign.font_size = 72
	sign.pixel_size = 0.012
	sign.outline_size = 12
	sign.modulate = Color(1.0, 0.85, 0.2)
	sign.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	sign.position = (sf[0] as Vector3) + (sf[2] as Vector3) * (hw + 2.0) + Vector3.UP * 3.0
	sign.visibility_range_end = 300.0
	add_child(sign)
	p.nodes.append(sign)


func _board(p: Placed) -> void:
	var fr := _frame(p.road, p.i0)
	var hw := p.road.width * 0.5 + p.road.shoulder
	var root := Node3D.new()
	root.position = (fr[0] as Vector3) + (fr[2] as Vector3) * (hw + 1.2)
	root.position.y = data.height_at(root.position.x, root.position.z)
	root.basis = Basis.looking_at(fr[2], Vector3.UP)
	var board := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(2.4, 1.4, 0.12)
	board.mesh = bm
	board.material_override = _mat(COLORS[EventDef.Kind.BOARD], 0.8)
	board.position = Vector3(0, 1.9, 0)
	root.add_child(board)
	var l := Label3D.new()
	l.text = "VELORA"
	l.font_size = 64
	l.pixel_size = 0.01
	l.modulate = Color(0.1, 0.1, 0.12)
	l.position = Vector3(0, 1.9, 0.07)
	root.add_child(l)
	add_child(root)
	p.nodes.append(root)


# ------------------------------------------------------------------ HUD
func _make_hud() -> void:
	hud = Control.new()
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UIStyle.place(hud, Control.PRESET_FULL_RECT, 0, 0, 0, 0)
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", UIStyle.panel(UIStyle.PANEL, 12, UIStyle.ACCENT))
	UIStyle.place(pc, Control.PRESET_CENTER_TOP, -260, 16, 260, 140)
	pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(pc)
	var v := VBoxContainer.new()
	pc.add_child(v)
	hud_title = UIStyle.label("", 18, UIStyle.ACCENT)
	hud_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(hud_title)
	hud_value = UIStyle.label("", 40, UIStyle.TEXT, true)
	hud_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(hud_value)
	hud_sub = UIStyle.label("", 16, UIStyle.TEXT_DIM)
	hud_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(hud_sub)
	hud_count = UIStyle.label("", 140, UIStyle.ACCENT, true)
	hud_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UIStyle.place(hud_count, Control.PRESET_CENTER, -300, -160, 300, 40)
	hud.add_child(hud_count)
	hud.visible = false
	if main.ui:
		main.ui.add_child(hud)
	else:
		add_child(hud)


func _show(title: String, value: String, sub: String) -> void:
	hud.visible = true
	hud_title.text = title
	hud_value.text = value
	hud_sub.text = sub


# ------------------------------------------------------------------ loop
func _crossed(p: Placed, i: int, pos: Vector3, prev: Vector3, any_dir: bool = false) -> int:
	var fr := _frame(p.road, i)
	var gp: Vector3 = fr[0]
	var t: Vector3 = fr[1]
	var s0 := (prev - gp).dot(t)
	var s1 := (pos - gp).dot(t)
	var lat := absf((pos - gp).dot(fr[2] as Vector3))
	if lat > p.road.width * 0.5 + p.road.shoulder + 4.0 or absf(pos.y - gp.y) > 8.0:
		return 0
	if s0 < 0.0 and s1 >= 0.0:
		return 1
	if any_dir and s0 > 0.0 and s1 <= 0.0:
		return -1
	return 0


func _physics_process(delta: float) -> void:
	var _t0 := Time.get_ticks_usec()
	_physics_process_inner(delta)
	Game.prof_add("activities", Time.get_ticks_usec() - _t0)


func _physics_process_inner(delta: float) -> void:
	if main == null:
		return
	var car: Car = main.player
	if car == null or not is_instance_valid(car):
		return
	var pos := car.global_position
	if _prev_pos == Vector3.ZERO or _prev_pos.distance_to(pos) > 30.0:
		_prev_pos = pos
		return
	_cooldown = maxf(_cooldown - delta, 0.0)
	if running == null:
		if _cooldown <= 0.0:
			_check_starts(car, pos)
	else:
		_update_running(car, pos, delta)
	_prev_pos = pos


func _check_starts(car: Car, pos: Vector3) -> void:
	for p in placed:
		var def := p.def
		if pos.distance_to(p.road.pts[p.i0]) > 60.0:
			p.armed = true
			continue
		match def.kind:
			EventDef.Kind.SPEED_TRAP:
				if _crossed(p, p.i0, pos, _prev_pos, true) != 0:
					_finish(p, absf(car.forward_speed) * 3.6)
					return
			EventDef.Kind.SPEED_ZONE, EventDef.Kind.DRIFT_ZONE:
				var c := _crossed(p, p.i0, pos, _prev_pos, true)
				if c != 0 and c == p.dir:
					_begin(p, "zone" if def.kind == EventDef.Kind.SPEED_ZONE else "drift")
					return
			EventDef.Kind.JUMP:
				if _crossed(p, p.i0, pos, _prev_pos) != 0 and car.speed > 8.0:
					_begin(p, "jump")
					takeoff = pos
					air_t = 0.0
					return
			EventDef.Kind.RACE, EventDef.Kind.TIME_TRIAL:
				# armed once the player has been away from the start box, so spawning on it never starts a race
				var dstart := pos.distance_to(p.road.pts[p.i0])
				if dstart > 30.0:
					p.armed = true
				elif p.armed and dstart < 10.0 and car.speed < 8.0:
					p.armed = false
					_start_race(p)
					return
			EventDef.Kind.BOARD:
				if not p.collected and Vector2(pos.x - p.nodes[0].global_position.x, pos.z - p.nodes[0].global_position.z).length() < 6.5:
					p.collected = true
					p.nodes[0].visible = false
					Game.personal_bests["board_" + def.id] = 1.0
					Game.credits += def.reward
					var got := 0
					var total := 0
					for q in placed:
						if q.def.kind == EventDef.Kind.BOARD:
							total += 1
							if q.collected:
								got += 1
					Game.toast("Festival board smashed", "+%d credits  •  %d / %d found" % [def.reward, got, total], "event")
					_sound("checkpoint")
					Game.save_game()


func _begin(p: Placed, st: String) -> void:
	running = p
	state = st
	t_elapsed = 0.0
	score = 0.0
	combo = 1.0
	drift_chain = 0.0
	_sound("checkpoint")


func _update_running(car: Car, pos: Vector3, delta: float) -> void:
	var p := running
	var def := p.def
	t_elapsed += delta
	match state:
		"zone":
			var dist := absf(p.i1 - p.i0) * 4.0
			_show(def.display_name + "  •  SPEED ZONE", "%.0f %s" % [_avg(dist), Game.speed_unit()], "average so far  •  target %s" % _target(def))
			if _crossed(p, p.i1, pos, _prev_pos, true) == p.dir:
				_finish(p, dist / maxf(t_elapsed, 0.01) * 3.6)
			elif _off_route(p, pos):
				_fail("Left the zone")
		"drift":
			if car.is_drifting:
				var pts := car.speed * absf(car.drift_angle) * 0.18 * delta
				drift_chain += pts
				combo = minf(combo + delta * 0.25, 4.0)
			else:
				if drift_chain > 0.0:
					score += drift_chain * combo
				drift_chain = 0.0
				combo = maxf(combo - delta * 0.8, 1.0)
			_show(def.display_name + "  •  DRIFT ZONE", "%d" % int(score + drift_chain * combo), "chain x%.1f  •  target %s" % [combo, _target(def)])
			if _crossed(p, p.i1, pos, _prev_pos, true) == p.dir:
				score += drift_chain * combo
				_finish(p, score)
			elif _off_route(p, pos) or (car.last_impact > 12.0 and t_elapsed > 0.5):
				car.last_impact = 0.0
				drift_chain = 0.0
				combo = 1.0
		"jump":
			if car.wheels_on_ground == 0:
				air_t += delta
			elif air_t > 0.25:
				var d := Vector2(pos.x - takeoff.x, pos.z - takeoff.z).length()
				_finish(p, d)
			elif t_elapsed > 3.0:
				running = null
				state = ""
		"countdown":
			countdown -= delta
			hud_count.text = str(int(ceil(countdown))) if countdown > 0.0 else "GO!"
			if countdown <= 0.0:
				state = "race"
				t_elapsed = 0.0
				car.controls_enabled = true
				for o in opponents:
					(o.get_node("Autopilot") as Node).set_process(true)
					o.external_input = true
					o.get_node("Autopilot").set_physics_process(true)
				_sound("fanfare")
				get_tree().create_timer(0.8).timeout.connect(func() -> void: hud_count.text = "")
		"race":
			var cp_i: int = p.checkpoints[next_cp]
			if _crossed(p, cp_i, pos, _prev_pos) != 0 or pos.distance_to(p.road.pts[cp_i]) < p.road.width * 0.5 + 4.0:
				next_cp += 1
				_sound("checkpoint")
				if next_cp >= p.checkpoints.size():
					if lap < def.laps:
						lap += 1
						next_cp = 0
					else:
						var place := _race_position(car)
						_finish(p, t_elapsed, place)
						return
			var ptxt := ""
			if opponents.size() > 0:
				ptxt = "  •  position %d / %d" % [_race_position(car), opponents.size() + 1]
			_show(def.display_name, _fmt_time(t_elapsed), "checkpoint %d / %d%s%s" % [next_cp, p.checkpoints.size(), ptxt,
				("  •  lap %d/%d" % [lap, def.laps]) if def.laps > 1 else ""])
			if pos.distance_to(p.road.pts[cp_i]) > 1500.0:
				_fail("Off course")


func _avg(dist: float) -> float:
	var v := dist / maxf(t_elapsed, 0.01) * 3.6 if t_elapsed > 0.3 else 0.0
	return v * (0.621371 if Game.settings.units_mph else 1.0)


var _route_check_t := 0.0


func _off_route(p: Placed, pos: Vector3) -> bool:
	# checked twice a second: distance to the event's own road (other roads may be closer at junctions)
	_route_check_t += get_physics_process_delta_time()
	if _route_check_t < 0.5:
		return false
	_route_check_t = 0.0
	var lo := mini(p.i0, p.i1) - 10
	var hi := maxi(p.i0, p.i1) + 10
	var best := INF
	for i in range(maxi(lo, 0), mini(hi, p.road.pts.size() - 1), 2):
		best = minf(best, p.road.pts[i].distance_squared_to(pos))
	return best > 45.0 * 45.0


func _target(def: EventDef) -> String:
	match def.kind:
		EventDef.Kind.SPEED_TRAP, EventDef.Kind.SPEED_ZONE:
			return "%d km/h" % int(def.stars[2])
		EventDef.Kind.DRIFT_ZONE:
			return "%d pts" % int(def.stars[2])
		EventDef.Kind.JUMP:
			return "%d m" % int(def.stars[2])
	return _fmt_time(def.stars[2])


func _fmt_time(t: float) -> String:
	return "%d:%05.2f" % [int(t / 60.0), fmod(t, 60.0)]


func _stars_for(def: EventDef, value: float) -> int:
	var lower_better := def.kind in [EventDef.Kind.RACE, EventDef.Kind.TIME_TRIAL]
	var s := 0
	for k in 3:
		if (lower_better and value <= def.stars[k]) or (not lower_better and value >= def.stars[k]):
			s = k + 1
	return s


func _finish(p: Placed, value: float, race_place: int = 0) -> void:
	var def := p.def
	var lower := def.kind in [EventDef.Kind.RACE, EventDef.Kind.TIME_TRIAL]
	var stars := _stars_for(def, value)
	if def.kind == EventDef.Kind.RACE and race_place > 1:
		stars = mini(stars, 1)
	var key := "event_" + def.id
	var record := Game.submit_best(key, value, not lower)
	var txt := ""
	match def.kind:
		EventDef.Kind.SPEED_TRAP, EventDef.Kind.SPEED_ZONE:
			txt = "%s %s" % [Game.speed_text(value / 3.6), Game.speed_unit()]
		EventDef.Kind.DRIFT_ZONE:
			txt = "%d points" % int(value)
		EventDef.Kind.JUMP:
			txt = "%.1f m" % value
		_:
			txt = _fmt_time(value)
			if race_place > 0:
				txt += "  •  finished %s" % ["1st", "2nd", "3rd", "4th", "5th"][clampi(race_place - 1, 0, 4)]
	var star_txt := "★".repeat(stars) + "☆".repeat(3 - stars)
	var reward := int(def.reward * (0.25 + stars * 0.25))
	Game.credits += reward
	Game.toast(def.display_name, "%s   %s   +%d CR%s" % [txt, star_txt, reward, "   NEW PERSONAL BEST" if record else ""],
		"record" if record else "event")
	_sound("fanfare" if stars >= 2 else "checkpoint")
	_end_event()


func _fail(reason: String) -> void:
	Game.toast(running.def.display_name, reason, "fail")
	_end_event()


func _end_event() -> void:
	running = null
	state = ""
	_cooldown = 4.0
	for o in opponents:
		o.queue_free()
	opponents.clear()
	if main.player:
		main.player.controls_enabled = true
	get_tree().create_timer(2.5).timeout.connect(func() -> void:
		if running == null:
			hud.visible = false)
	Game.save_game()


func _sound(kind: String) -> void:
	var a: Node = main.get("audio")
	if a and a.has_method("play"):
		a.play(kind, -6.0)


# ------------------------------------------------------------------ races
func _start_race(p: Placed) -> void:
	running = p
	state = "countdown"
	countdown = 3.5
	next_cp = 0
	lap = 1
	t_elapsed = 0.0
	var road := p.road
	var grid := data.road_spawn(road, p.i0, road.width * 0.25)
	if p.dir < 0:
		grid = Transform3D(grid.basis.rotated(Vector3.UP, PI), road.pts[p.i0] - Vector3(-road.tangent(p.i0).z, 0, road.tangent(p.i0).x) * road.width * 0.25 + Vector3.UP * 0.6)
	main.teleport_player(grid)
	main.player.controls_enabled = false
	_show(p.def.display_name, "GET READY", p.def.description)
	# AI opponents from the garage, similar class
	var ap_script := load("res://scripts/vehicle/autopilot.gd")
	var my_pi := Tuning.pi_of(main.player.spec)
	var pool: Array[int] = []
	for i in Game.cars.size():
		if i != Game.current_car_index and absi(Game.cars[i].pi - my_pi) < 220:
			pool.append(i)
	if pool.size() < p.def.opponents:
		for i in Game.cars.size():
			if i != Game.current_car_index and not pool.has(i):
				pool.append(i)
	for k in p.def.opponents:
		var spec := Game.cars[pool[k % pool.size()]]
		var o := Car.new()
		o.setup(spec, false)
		o.external_input = true
		add_child(o)
		var gi := p.i0 - (k + 1) * 3 * p.dir
		var lane := road.width * (0.25 if k % 2 == 1 else -0.25)
		var xf := data.road_spawn(road, gi, lane)
		if p.dir < 0:
			xf = Transform3D(xf.basis.rotated(Vector3.UP, PI), xf.origin)
		o.teleport(xf)
		var ap: Node = ap_script.new()
		ap.name = "Autopilot"
		o.add_child(ap)
		ap.setup(o, data, road.id)
		ap.max_kmh = minf(spec.top_speed_kmh * 0.8, 210.0) * randf_range(0.92, 1.02)
		ap.lat_acc = 7.0 + randf_range(-0.6, 0.4)
		ap.lane = 0.25 if k % 2 == 1 else -0.25
		ap.set_physics_process(false)
		opponents.append(o)


func _progress(pos: Vector3) -> float:
	var p := running
	var best := 0
	var bd := INF
	var n := p.road.pts.size()
	for i in range(0, n, 2):
		var d := p.road.pts[i].distance_squared_to(pos)
		if d < bd:
			bd = d
			best = i
	return float(best)


func _race_progress(pos: Vector3) -> float:
	var n := running.road.pts.size()
	var d := (_progress(pos) - running.i0) * running.dir
	if running.road.closed and d < -n * 0.5:
		d += n - 1
	return d


func _race_position(car: Car) -> int:
	if opponents.is_empty():
		return 1
	var mine := _race_progress(car.global_position)
	var place := 1
	for o in opponents:
		if _race_progress(o.global_position) > mine:
			place += 1
	return place


# ------------------------------------------------------------------ queries
func minimap_markers() -> Array:
	var out: Array = []
	for p in placed:
		if p.def.kind == EventDef.Kind.BOARD and p.collected:
			continue
		var q := p.road.pts[p.i0]
		out.append({"pos": Vector2(q.x, q.z), "color": COLORS[p.def.kind]})
	return out


func describe() -> String:
	var lines: PackedStringArray = []
	for p in placed:
		if p.def.kind == EventDef.Kind.BOARD:
			continue
		var best := Game.best("event_" + p.def.id, -1.0)
		lines.append("%-26s %-11s %s  best: %s" % [p.def.display_name, EventDef.Kind.keys()[p.def.kind], p.road.name,
			"-" if best < 0.0 else str(snappedf(best, 0.1))])
	var boards := 0
	var got := 0
	for p in placed:
		if p.def.kind == EventDef.Kind.BOARD:
			boards += 1
			if p.collected:
				got += 1
	lines.append("Festival boards found: %d / %d" % [got, boards])
	return "\n".join(lines)


func event_targets() -> Dictionary:
	var out := {}
	for p in placed:
		if p.def.kind == EventDef.Kind.BOARD:
			continue
		var road := p.road
		var i := clampi(p.i0 - 25 * p.dir, 0, road.pts.size() - 2)
		var xf := data.road_spawn(road, i, road.width * 0.25)
		if p.dir < 0:
			xf = Transform3D(xf.basis.rotated(Vector3.UP, PI), road.pts[i] - Vector3(-road.tangent(i).z, 0, road.tangent(i).x) * road.width * 0.25 + Vector3.UP * 0.6)
		out[p.def.display_name.to_lower()] = xf
	return out
