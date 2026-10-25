extends Node3D
## Road activities from the baked world data (world_data.activities), all started by driving:
##   speed traps (gate speed), speed zones (average speed over a stretch), drift zones (scored drift
##   chain), danger-sign jumps (Blender ramp, distance), checkpoint races and the scenic-loop time
##   trial (stop at the start arch, press Enter, 3-2-1 countdown, GPS to the next checkpoint).
## Results raise a banner and update personal bests in Game.personal_bests (saved with the game).

const COLORS := {"speed_trap": Color(1.0, 0.78, 0.2), "speed_zone": Color(1.0, 0.5, 0.15), "drift_zone": Color(0.75, 0.35, 1.0),
	"jump": Color(1.0, 0.9, 0.1), "race": Color(0.2, 0.6, 1.0), "time_trial": Color(1.0, 0.3, 0.55)}
const LABELS := {"speed_trap": "SPEED TRAP", "speed_zone": "SPEED ZONE", "drift_zone": "DRIFT ZONE", "jump": "DANGER SIGN",
	"race": "ROAD RACE", "time_trial": "TIME TRIAL"}
const RAMP_W := 2.5
const RAMP_L := 12.0
const RAMP_H := 2.8

var world: Node
var acts: Array = []                  ## activity dictionaries (world data + runtime fields)
var active: Dictionary = {}           ## the zone / race in progress
var _prev_pos := Vector3.ZERO
var _cooldown := {}                   ## id -> seconds
var _jump := {}                       ## armed / flying jump state
var _countdown := -1.0
var _cp_nodes: Array[Node3D] = []
var _panel: PanelContainer
var _panel_title: Label
var _panel_value: Label
var _panel_sub: Label
var _prompt: Label
var _count_label: Label
var _road_hw := {}
var _prompt_act: Dictionary = {}
var _flare_mat: StandardMaterial3D
var _flare_next_mat: StandardMaterial3D
var results: Array = []               ## log of finished activities (QA)


func _ready() -> void:
	world = Game.world
	if world == null or not ("wd" in world):
		return
	for r: Dictionary in world.wd.roads:
		_road_hw[String(r.id)] = float(r.half_w)
	for a: Dictionary in world.wd.activities:
		var e := a.duplicate(true)
		e["hw"] = float(_road_hw.get(String(a.road), 4.5))
		acts.append(e)
	_flare_mat = StandardMaterial3D.new()
	_flare_mat.albedo_color = Color(0.3, 0.6, 1.0, 0.35)
	_flare_mat.emission_enabled = true
	_flare_mat.emission = Color(0.25, 0.55, 1.0)
	_flare_mat.emission_energy_multiplier = 1.5
	_flare_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_flare_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_flare_next_mat = _flare_mat.duplicate()
	_flare_next_mat.albedo_color = Color(0.4, 0.85, 1.0, 0.75)
	_flare_next_mat.emission_energy_multiplier = 4.0
	_build_props()
	_build_hud()
	if Game.player != null:
		_prev_pos = Game.player.global_position


# --------------------------------------------------------------------- props
func _right(dir: Vector3) -> Vector3:
	return dir.cross(Vector3.UP).normalized()


func _ground(p: Vector3) -> float:
	var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 30.0, p + Vector3.DOWN * 60.0, 1)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	return float(hit.position.y) if not hit.is_empty() else world.height_at(p.x, p.z)


func _place_kit(piece: String, xf: Transform3D) -> Node3D:
	var kit: Node = world.kit
	var mesh: Mesh = kit.mesh(piece) if kit != null and kit.has_piece(piece) else null
	var mi := MeshInstance3D.new()
	if mesh != null:
		mi.mesh = mesh
	else:
		var bm := BoxMesh.new()
		bm.size = Vector3(1, 3, 1)
		mi.mesh = bm
	mi.transform = xf
	add_child(mi)
	return mi


func _build_props() -> void:
	for a: Dictionary in acts:
		var dir: Vector3 = (a.dir as Vector3).normalized()
		var right := _right(dir)
		var hw: float = a.hw
		var pos: Vector3 = a.pos
		match String(a.type):
			"speed_trap":
				var p := pos + right * (hw + 1.8)
				p.y = _ground(p)
				_place_kit("speedtrap_camera", Transform3D(Basis.looking_at(-right, Vector3.UP), p))
			"speed_zone", "drift_zone":
				var sc := (2.0 * hw + 3.0) / 10.0
				for end in 2:
					var gp: Vector3 = pos if end == 0 else a.end_pos
					var gd: Vector3 = dir if end == 0 else (a.end_dir as Vector3).normalized()
					_place_kit("zone_banner", Transform3D(Basis.looking_at(gd, Vector3.UP) * Basis.from_scale(Vector3(sc, 1, 1)), gp))
			"jump":
				_build_ramp(a, pos, dir, right, hw)
			"race", "time_trial":
				var sc2 := (2.0 * hw + 2.5) / 10.0
				_place_kit("race_arch", Transform3D(Basis.looking_at(dir, Vector3.UP) * Basis.from_scale(Vector3(sc2, 1, 1)), pos))
				if not a.get("lap", false):
					var f: Dictionary = a.finish
					var fd: Vector3 = (f.dir as Vector3).normalized()
					_place_kit("race_arch", Transform3D(Basis.looking_at(fd, Vector3.UP) * Basis.from_scale(Vector3(sc2, 1, 1)), f.pos))


## Kicker beside the road (inner edge 0.8 m outside the carriageway so traffic and racing lines
## never touch it), parallel to the road, with convex collision matching the Blender wedge.
func _build_ramp(a: Dictionary, pos: Vector3, dir: Vector3, right: Vector3, hw: float) -> void:
	var start := pos + right * (hw + RAMP_W + 0.8)
	start.y = _ground(start) - 0.04
	var end := start + dir * RAMP_L
	end.y = _ground(end) - 0.04
	var fwd := (end - start).normalized()
	var basis := Basis.looking_at(fwd, Vector3.UP)
	var xf := Transform3D(basis, start)
	a["ramp_xf"] = xf
	a["lip"] = xf * Vector3(0, RAMP_H, -RAMP_L)
	var body := StaticBody3D.new()
	body.name = "Ramp_" + String(a.id)
	body.transform = xf
	body.set_meta("surface", SurfaceData.Kind.CONCRETE)
	var cs := CollisionShape3D.new()
	var shape := ConvexPolygonShape3D.new()
	shape.points = PackedVector3Array([Vector3(-RAMP_W, 0, 0), Vector3(RAMP_W, 0, 0), Vector3(-RAMP_W, 0, -RAMP_L),
		Vector3(RAMP_W, 0, -RAMP_L), Vector3(-RAMP_W, RAMP_H, -RAMP_L), Vector3(RAMP_W, RAMP_H, -RAMP_L)])
	cs.shape = shape
	body.add_child(cs)
	add_child(body)
	_place_kit("jump_ramp", xf)
	# danger sign: speed-camera post re-used as the marker beside the ramp start
	var sp := start + right * (RAMP_W + 1.5) - dir * 4.0
	sp.y = _ground(sp)
	_place_kit("reflector_post", Transform3D(Basis.looking_at(-dir, Vector3.UP), sp))


# ----------------------------------------------------------------------- HUD
func _build_hud() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 4
	add_child(layer)
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)
	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", UITheme.panel_box(Color(0.05, 0.04, 0.1, 0.78), 14, UITheme.PINK))
	UITheme.place(_panel, 0.5, 0.0, -260, 18, 520, 96)
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vb := VBoxContainer.new()
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	_panel_title = UITheme.label("", 18, UITheme.SUN, true)
	_panel_value = UITheme.label("", 34, UITheme.TEXT, true)
	_panel_sub = UITheme.label("", 16, UITheme.DIM)
	for l: Label in [_panel_title, _panel_value, _panel_sub]:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vb.add_child(l)
	_panel.add_child(vb)
	_panel.visible = false
	root.add_child(_panel)
	_prompt = UITheme.label("", 22, UITheme.TEXT, true)
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.add_theme_constant_override("outline_size", 8)
	_prompt.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	UITheme.place(_prompt, 0.5, 1.0, -500, -170, 1000, 40)
	_prompt.visible = false
	root.add_child(_prompt)
	_count_label = UITheme.label("", 140, UITheme.SUN, true)
	_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_count_label.add_theme_constant_override("outline_size", 16)
	_count_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.55))
	UITheme.place(_count_label, 0.5, 0.5, -300, -180, 600, 200)
	_count_label.visible = false
	root.add_child(_count_label)


func _show_panel(title: String, value: String, sub: String, color: Color) -> void:
	_panel.visible = not _ui_hidden()
	_panel_title.text = title
	_panel_title.add_theme_color_override("font_color", color)
	_panel_value.text = value
	_panel_sub.text = sub


func _ui_hidden() -> bool:
	for k: String in Game.ui_focus:
		if k != "countdown":
			return true
	return false


# ------------------------------------------------------------------ markers
func markers() -> Array:
	var out := []
	for a: Dictionary in acts:
		out.append({"pos": a.pos, "color": COLORS.get(String(a.type), Color.WHITE), "type": a.type, "name": a.name, "id": a.id})
	return out


func find(id_or_name: String) -> Dictionary:
	var low := id_or_name.to_lower()
	for a: Dictionary in acts:
		if String(a.id).to_lower() == low or String(a.name).to_lower().contains(low):
			return a
	return {}


## Console/debug helper: drop the player just before an activity's start.
func teleport_to(a: Dictionary) -> void:
	if a.is_empty() or Game.player == null:
		return
	var dir: Vector3 = (a.dir as Vector3).normalized()
	var lane := _right(dir) * minf(2.0, float(a.hw) * 0.4)
	var back := 120.0 if String(a.type) in ["speed_trap", "speed_zone", "drift_zone", "jump"] else 25.0
	var p: Vector3 = a.pos - dir * back + lane
	p.y = _ground(p) + 0.6
	Game.player.teleport(p, dir, 0.0)
	_prev_pos = Game.player.global_position


# ------------------------------------------------------------------- update
func _physics_process(delta: float) -> void:
	var car := Game.player
	if car == null or not is_instance_valid(car) or acts.is_empty():
		return
	var p := car.global_position
	if p.distance_to(_prev_pos) > 60.0:  # teleported: no gate crossings from the jump
		_prev_pos = p
		_jump = {}
	for k: String in _cooldown.keys():
		_cooldown[k] = float(_cooldown[k]) - delta
		if _cooldown[k] <= 0.0:
			_cooldown.erase(k)
	if _countdown >= 0.0:
		_update_countdown(delta, car)
	elif not active.is_empty():
		_update_active(delta, car, p)
	else:
		_check_starts(car, p)
	_update_jump(delta, car, p)
	_prev_pos = p


func _crossed(gate_pos: Vector3, gate_dir: Vector3, hw: float, a: Vector3, b: Vector3, both_ways := false) -> bool:
	var da := (a - gate_pos).dot(gate_dir)
	var db := (b - gate_pos).dot(gate_dir)
	if not ((da < 0.0 and db >= 0.0) or (both_ways and da > 0.0 and db <= 0.0)):
		return false
	var lat := absf((b - gate_pos).dot(_right(gate_dir)))
	return lat < hw + 4.0 and absf(b.y - gate_pos.y) < 8.0


func _check_starts(car: CarController, p: Vector3) -> void:
	_prompt_act = {}
	for a: Dictionary in acts:
		var id := String(a.id)
		if _cooldown.has(id):
			continue
		var dir: Vector3 = (a.dir as Vector3).normalized()
		match String(a.type):
			"speed_trap":
				if _crossed(a.pos, dir, a.hw, _prev_pos, p, true):
					_cooldown[id] = 4.0
					_finish(a, car.speed_abs * 3.6, "%d km/h", true)
			"speed_zone", "drift_zone":
				if _crossed(a.pos, dir, a.hw, _prev_pos, p) and car.speed > 3.0:
					active = {"act": a, "t": 0.0, "score": 0.0, "chain": 0.0, "mult": 1.0, "idle": 0.0, "dist": 0.0}
					Game.notify(LABELS[a.type], String(a.name), "small")
					_chime(true)
			"race", "time_trial":
				var d := (p - (a.pos as Vector3))
				if d.length() < 22.0 and absf(d.dot(dir)) < 22.0:
					_prompt_act = a
	if not _prompt_act.is_empty():
		var a := _prompt_act
		var pb: Variant = Game.personal_bests.get(String(a.id), null)
		_prompt.text = "[ENTER]  START %s  ·  %s  ·  %.1f km%s" % [LABELS[a.type], a.name, float(a.length) / 1000.0,
			("  ·  PB " + _fmt_time(float(pb))) if pb != null else ""]
		_prompt.visible = not _ui_hidden()
	else:
		_prompt.visible = false
	if active.is_empty() and _countdown < 0.0:
		_panel.visible = false


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("activity_start") or Game.input_blocked():
		return
	if not active.is_empty() and String(active.act.type) in ["race", "time_trial"]:
		abandon("Abandoned")
		get_viewport().set_input_as_handled()
	elif not _prompt_act.is_empty() and _countdown < 0.0:
		start_event(_prompt_act)
		get_viewport().set_input_as_handled()


## Puts the player on the start line and runs the 3-2-1 countdown (races and the time trial).
func start_event(a: Dictionary) -> void:
	var car := Game.player
	if car == null:
		return
	var dir: Vector3 = (a.dir as Vector3).normalized()
	var p: Vector3 = a.pos - dir * 6.0 + _right(dir) * minf(1.8, float(a.hw) * 0.4)
	p.y = _ground(p) + 0.5
	car.teleport(p, dir, 0.0)
	_prev_pos = car.global_position
	var cps: Array = (a.checkpoints as Array).duplicate()
	cps.append(a.finish)
	active = {"act": a, "t": 0.0, "cp": 0, "cps": cps, "started": false}
	_countdown = 3.999
	Game.ui_focus["countdown"] = true
	_prompt.visible = false
	_build_flares(cps)


func _update_countdown(delta: float, car: CarController) -> void:
	car.linear_velocity = Vector3.ZERO
	car.angular_velocity = Vector3.ZERO
	var before := ceili(_countdown)
	_countdown -= delta
	var now := ceili(_countdown)
	_count_label.visible = true
	_count_label.text = str(now) if now > 0 else "GO!"
	if now != before:
		_chime(now <= 0)
	_show_panel(LABELS[active.act.type], "0:00.00", String(active.act.name), COLORS[active.act.type])
	if _countdown <= 0.0:
		_countdown = -1.0
		Game.ui_focus.erase("countdown")
		active.started = true
		_point_gps()
		get_tree().create_timer(0.8).timeout.connect(func() -> void: _count_label.visible = false)


func _update_active(delta: float, car: CarController, p: Vector3) -> void:
	var a: Dictionary = active.act
	active.t = float(active.t) + delta
	var t: float = active.t
	match String(a.type):
		"speed_zone":
			var length := float(a.end_s) - float(a.s)
			active.dist = float(active.dist) + car.speed_abs * delta
			var avg := minf(float(active.dist), length) / maxf(t, 0.01) * 3.6
			_show_panel("SPEED ZONE", "%d km/h" % roundi(avg), "%s  ·  %d m left" % [a.name, maxi(roundi(length - float(active.dist)), 0)], COLORS.speed_zone)
			if _crossed(a.end_pos, (a.end_dir as Vector3).normalized(), a.hw, _prev_pos, p):
				_end_active()
				_finish(a, length / maxf(t, 0.01) * 3.6, "%d km/h", true)
			elif _off_route(p, a.end_pos, 1.6 * length + 200.0) or t > length / 4.0:
				abandon("Left the zone")
		"drift_zone":
			var drifting := car.drift_angle > 12.0 and car.speed_abs > 8.0 and car.grounded >= 2
			if drifting:
				active.chain = float(active.chain) + car.drift_angle * car.speed_abs * delta * 0.9
				active.mult = minf(float(active.mult) + delta * 0.35, 5.0)
				active.idle = 0.0
			else:
				active.idle = float(active.idle) + delta
				if float(active.idle) > 1.2 and float(active.chain) > 0.0:
					active.score = float(active.score) + float(active.chain) * float(active.mult)
					active.chain = 0.0
					active.mult = 1.0
			if car.last_impact > 6.0 and car.last_impact != float(active.get("impact", 0.0)):
				active.chain = 0.0  # a crash loses the running chain
				active.mult = 1.0
			active.impact = car.last_impact
			var total := float(active.score) + float(active.chain) * float(active.mult)
			_show_panel("DRIFT ZONE", _fmt_int(total), "chain %s  x%.1f  ·  %s" % [_fmt_int(float(active.chain)), float(active.mult), a.name], COLORS.drift_zone)
			if _crossed(a.end_pos, (a.end_dir as Vector3).normalized(), a.hw, _prev_pos, p):
				_end_active()
				_finish(a, total, "%s pts", true)
			elif _off_route(p, a.end_pos, 1400.0) or t > 150.0:
				abandon("Left the zone")
		"race", "time_trial":
			var cps: Array = active.cps
			var i: int = active.cp
			var cp: Dictionary = cps[i]
			var cpd: Vector3 = (cp.dir as Vector3).normalized()
			var passed := _crossed(cp.pos, cpd, a.hw + 4.0, _prev_pos, p) or p.distance_to(cp.pos) < 9.0
			if passed:
				active.cp = i + 1
				print("ACT checkpoint %d/%d %s t=%.1f" % [i + 1, cps.size(), a.id, t])
				_chime(true)
				if int(active.cp) >= cps.size():
					_end_active()
					_finish(a, t, "time", false)
					return
				_point_gps()
				_refresh_flares()
			var dist_next := p.distance_to((cps[active.cp] as Dictionary).pos)
			_show_panel(LABELS[a.type], _fmt_time(t), "%s  ·  checkpoint %d/%d  ·  %d m" % [a.name, int(active.cp) + 1, cps.size(), roundi(dist_next)], COLORS[a.type])
			if dist_next > 900.0:
				abandon("Too far from the route")


func _off_route(p: Vector3, end_pos: Vector3, max_d: float) -> bool:
	return p.distance_to(end_pos) > max_d


func _end_active() -> void:
	active = {}
	_clear_flares()
	var nav: Node = Game.main.get("nav") if Game.main != null else null
	if nav != null and nav.has_method("clear_waypoint"):
		nav.clear_waypoint()


func abandon(why: String) -> void:
	if active.is_empty():
		return
	var a: Dictionary = active.act
	print("ACT abandon %s: %s" % [a.id, why])
	_cooldown[String(a.id)] = 5.0
	_end_active()
	_countdown = -1.0
	Game.ui_focus.erase("countdown")
	_count_label.visible = false
	_panel.visible = false
	Game.notify(LABELS[a.type] + " ended", why, "info")
	_chime(false)


## Records a result, compares it with the personal best and shows the banner.
func _finish(a: Dictionary, value: float, fmt: String, higher_better: bool) -> void:
	var id := String(a.id)
	var pb: Variant = Game.personal_bests.get(id, null)
	var better := pb == null or (value > float(pb) if higher_better else value < float(pb))
	if better:
		Game.personal_bests[id] = value
	var shown := _fmt_time(value) if fmt == "time" else (fmt % _fmt_int(value) if fmt.contains("%s") else fmt % roundi(value))
	var pb_txt := ""
	if pb != null:
		pb_txt = "  ·  PB " + (_fmt_time(float(pb)) if fmt == "time" else (fmt % _fmt_int(float(pb)) if fmt.contains("%s") else fmt % roundi(float(pb))))
	Game.notify("%s · %s" % [LABELS[a.type], a.name], shown + ("  ·  NEW RECORD!" if better and pb != null else pb_txt), "big")
	_chime(true)
	_cooldown[id] = 6.0
	_panel.visible = false
	results.append({"id": id, "type": a.type, "value": value, "pb": better})
	print("ACT result %s %.2f%s" % [id, value, " (PB)" if better else ""])
	if Game.has_method("add_credits"):
		Game.add_credits(500 if better else 150)


func _update_jump(delta: float, car: CarController, p: Vector3) -> void:
	if _jump.is_empty():
		for a: Dictionary in acts:
			if String(a.type) != "jump" or not a.has("ramp_xf"):
				continue
			var lp: Vector3 = (a.ramp_xf as Transform3D).affine_inverse() * p
			if absf(lp.x) < RAMP_W + 0.8 and lp.z < 0.5 and lp.z > -RAMP_L - 0.5 and lp.y > -1.0 and lp.y < 4.0 and car.speed > 8.0:
				_jump = {"act": a, "t": 0.0, "flying": false}
				print("ACT jump armed %s v=%.0f" % [a.id, car.speed_abs * 3.6])
				break
		return
	_jump.t = float(_jump.t) + delta
	var a: Dictionary = _jump.act
	if not _jump.flying:
		if car.grounded == 0 and car.air_time > 0.05:
			_jump.flying = true
			_jump.start = a.lip
			print("ACT jump takeoff v=%.0f" % (car.speed_abs * 3.6))
		elif float(_jump.t) > 3.0:
			_jump = {}
		return
	if car.grounded >= 2 and car.air_time <= 0.0:
		var s: Vector3 = _jump.start
		var d := Vector2(p.x - s.x, p.z - s.z).length()
		_jump = {}
		if d > 5.0:
			_finish(a, d, "%s m", true)
	elif float(_jump.t) > 12.0:
		_jump = {}


# ------------------------------------------------------------- checkpoints
func _build_flares(cps: Array) -> void:
	_clear_flares()
	var hw: float = active.act.hw
	for cp: Dictionary in cps:
		var root := Node3D.new()
		var dir: Vector3 = (cp.dir as Vector3).normalized()
		root.transform = Transform3D(Basis.looking_at(dir, Vector3.UP), cp.pos)
		for s in [-1.0, 1.0]:
			var mi := MeshInstance3D.new()
			var cm := CylinderMesh.new()
			cm.top_radius = 0.35
			cm.bottom_radius = 0.35
			cm.height = 9.0
			mi.mesh = cm
			mi.position = Vector3(s * (hw + 1.2), 4.5, 0)
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			root.add_child(mi)
		add_child(root)
		_cp_nodes.append(root)
	_refresh_flares()


func _refresh_flares() -> void:
	var i: int = active.get("cp", 0)
	for k in _cp_nodes.size():
		var n := _cp_nodes[k]
		n.visible = k >= i and k <= i + 2
		for c: Node in n.get_children():
			(c as MeshInstance3D).material_override = _flare_next_mat if k == i else _flare_mat


func _clear_flares() -> void:
	for n in _cp_nodes:
		n.queue_free()
	_cp_nodes.clear()


func _point_gps() -> void:
	var nav: Node = Game.main.get("nav") if Game.main != null else null
	if nav == null or active.is_empty() or not active.has("cps"):
		return
	var cp: Dictionary = (active.cps as Array)[int(active.cp)]
	nav.set_waypoint(cp.pos)


# ------------------------------------------------------------------ helpers
func _chime(good: bool) -> void:
	if Game.audio != null and Game.audio.has_method("chime"):
		Game.audio.chime(good)


static func _fmt_time(t: float) -> String:
	var m := int(t / 60.0)
	return "%d:%05.2f" % [m, t - m * 60.0]


static func _fmt_int(v: float) -> String:
	var s := str(roundi(v))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return s + out
