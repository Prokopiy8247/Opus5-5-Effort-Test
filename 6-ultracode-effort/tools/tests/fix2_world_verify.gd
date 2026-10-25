extends Node
## World fixes verification inside the real game (main scene):
##   Godot_console.exe --path <project> --resolution 1920x1080 res://tools/tests/fix2_world_verify.tscn -- --only=forest,river,...
## Sections: forest (Pinewood Track), river (Wend channel), verge (expressway / banked edges), sky (map-edge
## horizon), tunnel (Ember Spur portals + covered road; terrain incl. chunk skirts sampled against the tube's
## cross-section along its whole length), kerb (Hedgerow Track edge drive), mirror (teleport), lamps
## (street-lamp posts), parapet (bridge parapets stop the body at their inner face on both sides, driven with
## the real keyboard input path). Prints "[fix2] ..." lines; screenshots in qa_output/fix2_world/.
## Writes no settings (traffic via Game.traffic.set_density, camera via set_mode(.., false)).

const OUT := "res://qa_output/fix2_world/"

var main: Node
var w: World
var net: RoadNetwork
var rig: CameraRig
var drive_fn := Callable()
var impacts: Array = []
var fails := 0


func _ready() -> void:
	SaveGame.enabled = false
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(main)
	_run.call_deferred()


func _physics_process(delta: float) -> void:
	if drive_fn.is_valid():
		drive_fn.call(delta)


func _log(s: String) -> void:
	print("[fix2] ", s)


func _check(label: String, ok: bool, detail: String) -> void:
	_log("%s %s  %s" % ["PASS" if ok else "FAIL", label, detail])
	if not ok:
		fails += 1


func _wait(s: float) -> void:
	await get_tree().create_timer(s).timeout


func _settle(max_ms := 20000) -> void:
	var t0 := Time.get_ticks_msec()
	await get_tree().process_frame
	while not w.is_ready_near() and Time.get_ticks_msec() - t0 < max_ms:
		await get_tree().process_frame
	await _wait(1.2)


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(OUT + name + ".png")
	_log("shot %s" % ProjectSettings.globalize_path(OUT + name + ".png"))


func _sections() -> PackedStringArray:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			return a.substr(7).split(",")
	return PackedStringArray(["forest", "river", "verge", "sky", "tunnel", "kerb", "mirror", "lamps", "parapet"])


var _hidden: Array[CanvasLayer] = []


func _hud(visible: bool) -> void:
	if not visible:
		for c in main.get_children():
			if c is CanvasLayer and (c as CanvasLayer).visible:
				(c as CanvasLayer).visible = false
				_hidden.append(c)
	else:
		for c in _hidden:
			c.visible = true
		_hidden.clear()


func _on_impact(strength: float, at: Vector3) -> void:
	if strength > 1.0:
		impacts.append([snappedf(strength, 0.1), at.round()])


func _connect_impact() -> void:
	if not _car().impact.is_connected(_on_impact):
		_car().impact.connect(_on_impact)


func _car() -> CarController:
	return Game.player_car


func _place(r: RoadNetwork.Road, s: float, lat: float, dir: float) -> void:
	main.call("teleport_to", {"position": r.surface_point(s, lat), "forward": r.flat_tangent_at(s) * dir})
	await _settle()
	_car().freeze = false


## Free camera at eye looking at `look`; the (hidden) car parks under the eye so terrain and dressing stream there.
func _free_cam(eye: Vector3, look: Vector3) -> void:
	var car := _car()
	car.visible = false
	car.freeze = true
	car.global_position = Vector3(eye.x, w.height_at(eye.x, eye.z) + 1.0, eye.z)
	w.refocus(car.global_position)
	rig.active = false
	rig.global_transform = Transform3D(Basis(), eye).looking_at(look, Vector3.UP)
	await _settle()
	rig.global_transform = Transform3D(Basis(), eye).looking_at(look, Vector3.UP)
	await _wait(0.5)


func _release_cam() -> void:
	rig.active = true
	_car().visible = true
	_car().freeze = false


func _roll_deg(car: CarController) -> float:
	var b := car.global_transform.basis
	return rad_to_deg(atan2(b.x.y, b.y.y))


func _run() -> void:
	while main.get("is_loading"):
		await get_tree().process_frame
	w = Game.world as World
	net = w.data.network
	rig = Game.camera_rig as CameraRig
	(main.get("car_input") as Node).set("enabled", false)
	if Game.traffic and Game.traffic.has_method("set_density"):
		Game.traffic.call("set_density", 0.0)
	Game.set_time_of_day(12.0)
	Game.set_weather("clear", true)
	while not w.roads.done:
		await get_tree().process_frame
	_connect_impact()
	var secs := _sections()
	for sec in secs:
		match sec:
			"forest": await _forest()
			"river": await _river()
			"verge": await _verge()
			"sky": await _sky()
			"tunnel": await _tunnel()
			"kerb": await _kerb()
			"mirror": await _mirror()
			"lamps": await _lamps()
			"parapet": await _parapet()
	_log("failures: %d" % fails)
	get_tree().quit(0)


# ------------------------------------------------------------------ p1 / p11 Pinewood Track

func _forest() -> void:
	var r := net.get_road("forest_track")
	var n := r.count()
	var nb := 0
	var max_above := -INF
	for i in n:
		if r.flags[i] & 1:
			nb += 1
		var lo := INF
		for lat: float in [-5.0, -3.0, 0.0, 3.0, 5.0]:
			var q := r.surface_point(i * r.ds, lat)
			lo = minf(lo, w.height_at(q.x, q.z))
		max_above = maxf(max_above, r.pos[i].y - lo)
	_check("p1 forest_track has no bridge samples", nb == 0, "%d of %d samples flagged bridge, deck max %.2f m above the lowest ground within 5 m" % [nb, n, max_above])
	_check("p1 forest_track follows the ground", max_above < 1.5, "max %.2f m" % max_above)
	# Drive the whole track at ~77 km/h with screenshots at s=250/540/800.
	Game.spawn_car(maxi(Game.find_car_index("granite"), 0), true)
	await _wait(0.5)
	_connect_impact()
	await _place(r, 8.0, 0.0, 1.0)
	rig.set_mode(CameraRig.Mode.CHASE_NEAR, false)
	var f := RoadFollower.new()
	f.setup(r, 8.0, 1, 0.0)
	f.target_speed = 77.0 / 3.6
	f.respect_traffic = false
	impacts.clear()
	drive_fn = func(dt: float) -> void: f.drive(_car(), dt)
	var marks := [250.0, 540.0, 800.0]
	var t0 := Time.get_ticks_msec()
	while not f.finished and f.s < r.length - 70.0 and Time.get_ticks_msec() - t0 < 120000:
		if not marks.is_empty() and f.s >= float(marks[0]):
			await _shot("forest_drive_s%d_%dkmh" % [int(marks[0]), int(_car().get_speed_kmh())])
			marks.pop_front()
		await get_tree().physics_frame
	_log("forest drive reached s=%.0f in %.1f s, impacts %s" % [f.s, (Time.get_ticks_msec() - t0) / 1000.0, str(impacts)])
	# Dead end: run off the end at ~45 km/h and see whether the car drops.
	f.target_speed = 45.0 / 3.6
	var min_wheels := 4
	var max_air := 0.0
	var y_end := r.pos[n - 1].y
	var lowest := INF
	var t1 := Time.get_ticks_msec()
	var past := 0.0
	drive_fn = func(dt: float) -> void:
		var car := _car()
		if f.s < r.length - 4.0:
			f.drive(car, dt)
		else:
			car.in_steer = 0.0
			car.in_throttle = 0.3
			car.in_brake = 0.0
	while Time.get_ticks_msec() - t1 < 25000 and past < 3.0:
		await get_tree().physics_frame
		var car := _car()
		if f.s >= r.length - 4.0:
			past += get_physics_process_delta_time()
		if f.s > r.length - 30.0:
			min_wheels = mini(min_wheels, car.wheels_on_ground)
			max_air = maxf(max_air, car.air_time)
			lowest = minf(lowest, car.global_position.y)
	drive_fn = Callable()
	_car().in_throttle = 0.0
	_car().in_brake = 0.6
	await _shot("forest_dead_end_after")
	var end_p := r.pos[n - 1]
	var end_gap := end_p.y - w.height_at(end_p.x, end_p.z)
	var hard := 0
	for im: Array in impacts:
		if float(im[0]) > 3.0:
			hard += 1
	_check("p11 dead end meets the ground (no deck end in mid-air)", absf(end_gap) < 0.5 and max_air < 0.25 and hard == 0, "road end %.2f m above the ground, min wheels %d, max air %.2f s, car y %.1f vs road end %.1f, impacts %s" % [end_gap, min_wheels, max_air, lowest, y_end, str(impacts)])
	# Side views of the track at s=250/540/800 and the end.
	_hud(false)
	for s: float in [250.0, 540.0, 800.0, r.length - 10.0]:
		var p := r.point_at(s)
		var rt := r.right_at(s)
		var eye := p + rt * 30.0
		eye.y = maxf(w.height_at(eye.x, eye.z), p.y) + 4.0
		await _free_cam(eye, p + Vector3.UP)
		await _shot("forest_side_s%d" % int(s))
	_release_cam()
	_hud(true)
	_car().in_brake = 0.0


# ------------------------------------------------------------------ p10 River Wend

func _river() -> void:
	var gen := w.data.gen
	var pts := gen._river_pts
	var ys := gen._river_y
	var walls := 0
	var worst_step := 0.0
	var worst_at := Vector2.ZERO
	var dry_bed := 0
	var overhang := 0
	var perched := 0
	var samples := 0
	var bridged := 0
	for i in pts.size() - 1:
		for k in 4:
			var t := k / 4.0
			var c := pts[i].lerp(pts[i + 1], t)
			var y := lerpf(ys[i], ys[i + 1], t)
			if y <= WorldLayout.SEA_LEVEL + 0.1:
				continue   # the mouth: river and sea meet
			# Bridge abutments and the cut under a deck are meant to be steep.
			var near := net.nearest(Vector3(c.x, 0.0, c.y), 45.0)
			if not near.is_empty() and ((near["road"] as RoadNetwork.Road).flags[int(near["index"])] & 1):
				bridged += 1
				continue
			var dir := (pts[i + 1] - pts[i]).normalized()
			var nrm := Vector2(-dir.y, dir.x)
			for side: float in [-1.0, 1.0]:
				samples += 1
				var prev := w.height_at(c.x + nrm.x * side * 12.0, c.y + nrm.y * side * 12.0)
				for d in range(13, 31):
					var q := c + nrm * side * float(d)
					var h := w.height_at(q.x, q.y)
					var st := absf(h - prev)
					if st > worst_step:
						worst_step = st
						worst_at = q
					prev = h
				var edge := c + nrm * side * 13.0
				if w.height_at(edge.x, edge.y) < y - 0.5:
					overhang += 1
				# Natural ground (the valley, without road cuttings) 40 m out.
				var out := c + nrm * side * 40.0
				if w.data.gen.natural_height(out.x, out.y) < y - 0.5:
					perched += 1
			var bed := w.height_at(c.x, c.y)
			if bed > y - 0.3:
				dry_bed += 1
			var s1 := w.height_at(c.x + nrm.x * 15.0, c.y + nrm.y * 15.0)
			var s2 := w.height_at(c.x + nrm.x * 18.0, c.y + nrm.y * 18.0)
			if absf(s1 - s2) > 2.0:
				walls += 1
	_log("river: %d bank samples (%d centre samples at bridges skipped); steps > 2 m between 15 and 18 m: %d; worst 1 m step %.2f m at %s" % [samples, bridged, walls, worst_step, str(worst_at.round())])
	_check("p10 no wall at the river banks", walls == 0 and worst_step < 1.0, "walls %d worst step %.2f" % [walls, worst_step])
	_check("p10 water ribbon never overhangs the bank", overhang == 0, "%d ribbon-edge samples with ground > 0.5 m below the water" % overhang)
	_check("p10 river not perched above its valley", perched == 0, "%d samples where the natural ground 40 m out is > 0.5 m below the water" % perched)
	_log("river: %d centre samples where the bed is above the water (ribbon hidden: bridges/estuary)" % dry_bed)
	_hud(false)
	var views := [["river_field_b", Vector3(-835, 0, -395), Vector3(-782, 0, -405), 1.8],
		["river_aerial_b", Vector3(-880, 0, -360), Vector3(-790, 0, -380), 45.0],
		["river_aerial_a", Vector3(-860, 0, -600), Vector3(-740, 0, -540), 55.0],
		["river_field_a", Vector3(-800, 0, -575), Vector3(-740, 0, -560), 1.8],
		["river_from_forest_track", Vector3(-728, 0, -300), Vector3(-810, 0, -270), 3.0],
		["river_estuary_aerial", Vector3(-640, 0, 1250), Vector3(-715, 0, 1420), 40.0],
		["river_ring_bridge_aerial", Vector3(-640, 0, 840), Vector3(-700, 0, 885), 30.0]]
	for v: Array in views:
		var eye: Vector3 = v[1]
		var look: Vector3 = v[2]
		eye.y = w.height_at(eye.x, eye.z) + float(v[3])
		look.y = w.height_at(look.x, look.z) + 1.0
		await _free_cam(eye, look)
		await _shot(v[0])
	_release_cam()
	_hud(true)


# ------------------------------------------------------------------ p2 expressway verge (banked high side)

func _verge() -> void:
	var r := net.get_road("expressway")
	var e := r.width * 0.5 + r.shoulder
	await _place(r, 650.0, r.lane_offset(2), 1.0)
	for s: float in [560.0, 620.0, 650.0, 700.0, 1100.0]:
		for side: float in [1.0, -1.0]:
			var edge := r.surface_point(s, side * e).y
			var txt := ""
			for lat: float in [8.0, e, 9.8, 11.5, 15.0, 18.0]:
				var q := r.surface_point(s, side * lat)
				txt += " %.1f:%+.2f" % [lat, w.ground_at(q.x, q.z, q.y + 5.0) - edge]
			_log("verge s=%.0f side %+.0f bank %.3f |%s" % [s, side, r.bank_at(s), txt])
	var q2 := r.surface_point(650.0, e + 0.5)
	var drop := r.surface_point(650.0, e).y - w.ground_at(q2.x, q2.z, q2.y + 5.0)
	_check("p2 no ditch beside the high-side shoulder (s=650)", drop < 0.3, "drop 0.5 m past the edge %.2f m" % drop)
	# Parked straddling the edge.
	for lat: float in [9.5, -9.5]:
		await _place(r, 650.0, lat, 1.0)
		await _wait(2.5)
		_log("parked s=650 lat %+.1f roll %.1f deg wheels %d" % [lat, _roll_deg(_car()), _car().wheels_on_ground])
		if lat > 0.0:
			_check("p2 car parked on the high-side verge sits level", absf(_roll_deg(_car())) < 12.0, "roll %.1f" % _roll_deg(_car()))
			await _shot("verge_parked_s650_lat95")
	# Dynamic (as the reproduction): lane 2 at full speed through the left-hander, target line ramping to 10 m
	# (1-2 m past the shoulder) at s=560-640 and back by s=780; roll measured while on the verge.
	for car_key: String in ["vortex", "castellan"]:
		Game.spawn_car(maxi(Game.find_car_index(car_key), 0), true)
		await _wait(0.5)
		_connect_impact()
		await _place(r, 25.0, r.lane_offset(2), 1.0)
		rig.set_mode(CameraRig.Mode.CHASE_NEAR, false)
		var f := RoadFollower.new()
		f.setup(r, 25.0, 1, r.lane_offset(2))
		f.target_speed = 80.0
		f.lat_accel = 9.0
		f.respect_traffic = false
		impacts.clear()
		var lane := r.lane_offset(2)
		drive_fn = func(dt: float) -> void:
			var wide := smoothstep(560.0, 640.0, f.s) * (1.0 - smoothstep(700.0, 780.0, f.s))
			f.lane_offset = lerpf(lane, 10.0, wide)
			f.drive(_car(), dt)
		var verge_roll := 0.0
		var verge_w := 4
		var verge_v := 0.0
		var verge_air := 0.0
		var max_lat := 0.0
		var t_edge := -1.0
		var shot_done := false
		var t0 := Time.get_ticks_msec()
		while f.s < 900.0 and Time.get_ticks_msec() - t0 < 60000:
			await get_tree().physics_frame
			var car := _car()
			if f.s < 540.0:
				continue
			var near := net.nearest(car.global_position, 30.0, func(rr: RoadNetwork.Road) -> bool: return rr == r)
			var lat := float(near.get("lateral", 0.0))
			max_lat = maxf(max_lat, lat)
			if lat > 8.0 and t_edge < 0.0:
				t_edge = Time.get_ticks_msec()
			# The first 2 s after the wheels leave the shoulder (later excursions are the follower losing grip on grass).
			if t_edge > 0.0 and Time.get_ticks_msec() - t_edge < 2000 and lat < 11.6:
				verge_roll = maxf(verge_roll, absf(_roll_deg(car)))
				verge_w = mini(verge_w, car.wheels_on_ground)
				verge_v = maxf(verge_v, car.get_speed_kmh())
				verge_air = maxf(verge_air, car.air_time)
				if not shot_done and lat > 9.3:
					shot_done = true
					await _shot("verge_%s_wide_%dkmh" % [car_key, int(car.get_speed_kmh())])
		drive_fn = Callable()
		_log("%s run: first 2 s on the verge (lat 8-11.6 m) at up to %.0f km/h: roll %.1f deg, min wheels %d, air %.2f s; max lateral %.1f m, upright %.2f, impacts %s" % [car_key, verge_v, verge_roll, verge_w, verge_air, max_lat, _car().global_transform.basis.y.y, str(impacts)])
		_check("p2 %s 1-2 m wide at %.0f km/h: no ditch roll" % [car_key, verge_v], verge_v > 150.0 and verge_roll < 12.0 and verge_air < 0.2, "roll %.1f deg (reproduction: 25-35), air %.2f s" % [verge_roll, verge_air])
		_car().in_brake = 1.0
		await _wait(2.0)
		_car().in_brake = 0.0


# ------------------------------------------------------------------ p9 skyline at the map edges

func _seethrough(cam: Camera3D, tag: String) -> int:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color.BLACK
	mat.set("disable_fog", true)
	var saved: Array = []
	var mis: Array[MeshInstance3D] = []
	for c: TerrainStreamer.Chunk in w.terrain.chunks.values():
		mis.append(c.mi)
	var far := w.get_node_or_null(^"FarTerrain") as MeshInstance3D
	if far:
		mis.append(far)
	for mi in mis:
		saved.append([mi, mi.material_override, mi.layers])
		mi.material_override = mat
		mi.layers = 1 << 19
	var mask := cam.cull_mask
	cam.cull_mask = 1 << 19
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	cam.cull_mask = mask
	for sv: Array in saved:
		(sv[0] as MeshInstance3D).material_override = sv[1]
		(sv[0] as MeshInstance3D).layers = sv[2]
	var holes := 0
	var marked := img.duplicate() as Image
	for x in range(0, img.get_width(), 2):
		var seen := false
		for y in range(0, img.get_height(), 2):
			var l := img.get_pixel(x, y).get_luminance()
			if l < 0.03:
				seen = true
			elif seen and l > 0.1:
				holes += 1
				marked.set_pixel(x, y, Color.RED)
	if holes > 0:
		marked.save_png(OUT + tag + "_terrain_only_marked.png")
	_log("sky %s: see-through pixels (2x2 grid) %d" % [tag, holes])
	return holes


func _sky() -> void:
	_check("p9 far terrain present", w.get_node_or_null(^"FarTerrain") != null, "")
	_hud(false)
	# 1) Expressway East, chase far, facing east.
	Game.teleport("Expressway East")
	await _settle()
	var p := _car().global_position
	main.call("teleport_to", {"position": p, "forward": Vector3(1, 0, 0)})
	await _settle()
	rig.set_mode(CameraRig.Mode.CHASE_FAR, false)
	await _wait(1.5)
	await _shot("sky_expressway_east_chase_far")
	var h1 := await _seethrough(rig.camera, "sky_expressway_east")
	# 2-4) Static views from the reproduction.
	var views := [["sky_east_edge_static", Vector3(1930, 150, -1110), Vector3(2060, 140, -1090), 12.0],
		["sky_east_ring_sunset", Vector3(1713, 142, -1161), Vector3(2600, 160, -1100), 19.0],
		["sky_north_gale_plateau", Vector3(1239, 117, -1562), Vector3(1366, 150, -2100), 12.0]]
	var total := h1
	for v: Array in views:
		Game.set_time_of_day(float(v[3]))
		await _free_cam(v[1], v[2])
		await _shot(v[0])
		total += await _seethrough(rig.camera, v[0])
	Game.set_time_of_day(12.0)
	_release_cam()
	rig.set_mode(CameraRig.Mode.CHASE_NEAR, false)
	_hud(true)
	_check("p9 no see-through holes at the map edge", total == 0, "%d pixels over 4 views" % total)


# ------------------------------------------------------------------ p42 tunnel portals + covered road

func _tunnel() -> void:
	var r := net.get_road("ring")
	var tube := WorldGen.tube_mask(r.flags)
	var a := -1
	var b := -1
	for i in r.count():
		if tube[i] == 1:
			if a < 0:
				a = i
			b = i
	var e_t := r.width * 0.5 + r.shoulder + 0.6
	_log("tube samples %d..%d (s %.0f..%.0f)" % [a, b, a * r.ds, b * r.ds])
	for end_i: int in [a, b]:
		var inward := 1.0 if end_i == a else -1.0
		await _place(r, end_i * r.ds - inward * 20.0, r.lane_offset(1 if inward > 0.0 else -1), inward)
		await _wait(1.0)
		# Terrain triangles (incl. chunk-edge skirts, at whatever LOD each chunk streams now) inside the tube's
		# cross-section anywhere along the tube: 15 points per triangle against the walls and the arch.
		var res_t := _terrain_in_tube(r, tube, a, b, e_t)
		_check("p42/q36 no terrain inside the tube (portal s=%.0f in focus)" % (end_i * r.ds), res_t["bad"] == 0,
			"%d of %d terrain triangles over the tube reach inside it %s" % [res_t["bad"], res_t["checked"], str(res_t["where"])])
		rig.set_mode(CameraRig.Mode.CHASE_NEAR, false)
		await _wait(0.8)
		await _shot("tunnel_portal_%d_chase_approach" % int(end_i * r.ds))
		var f := RoadFollower.new()
		f.setup(r, end_i * r.ds - inward * 20.0, int(inward), r.lane_offset(1))
		f.target_speed = 8.0
		f.respect_traffic = false
		drive_fn = func(dt: float) -> void: f.drive(_car(), dt)
		var t2 := Time.get_ticks_msec()
		while absf(f.s - (end_i * r.ds - inward * 6.0)) > 2.0 and Time.get_ticks_msec() - t2 < 15000:
			await get_tree().physics_frame
		await _shot("tunnel_portal_%d_chase_at_mouth" % int(end_i * r.ds))
		drive_fn = Callable()
		_car().in_brake = 1.0
		_hud(false)
		var p := r.pos[end_i]
		var fwd := r.flat_tangent_at(end_i * r.ds) * inward
		await _free_cam(p - fwd * 18.0 + Vector3.UP * 2.0, p + fwd * 20.0 + Vector3.UP * 3.0)
		await _shot("tunnel_portal_%d_eye18m" % int(end_i * r.ds))
		await _free_cam(p - fwd * 25.0 + Vector3.UP * 22.0, p + fwd * 6.0)
		await _shot("tunnel_portal_%d_aerial" % int(end_i * r.ds))
		await _free_cam(p + fwd * 4.0 + Vector3.UP * 40.0 + Vector3(0.1, 0, 0), p + fwd * 4.0)
		await _shot("tunnel_portal_%d_topdown" % int(end_i * r.ds))
		var inside := p + fwd * 14.0 + Vector3.UP * 2.0
		rig.active = false
		rig.global_transform = Transform3D(Basis(), inside).looking_at(p - fwd * 10.0 + Vector3.UP * 3.0, Vector3.UP)
		await _wait(0.4)
		await _shot("tunnel_portal_%d_inside_out" % int(end_i * r.ds))
		_release_cam()
		_hud(true)
		_car().in_brake = 0.0
	# Covered contract: tunnel road collider meta + instance parameter; open road not covered.
	await _place(r, (a + b) * 0.5 * r.ds, r.lane_offset(1), 1.0)
	await get_tree().physics_frame
	var res := {}
	for s: float in [(a + b) * 0.5 * r.ds, a * r.ds + 2.0, b * r.ds - 2.0, a * r.ds - 30.0, b * r.ds + 30.0]:
		var sp := r.surface_point(s, r.lane_offset(1))
		var q := PhysicsRayQueryParameters3D.create(sp + Vector3.UP * 2.0, sp - Vector3.UP * 2.0, 1)
		var hit := get_viewport().get_world_3d().direct_space_state.intersect_ray(q)
		var cov := false
		if not hit.is_empty():
			cov = bool((hit["collider"] as Object).get_meta(&"covered", false))
		res[int(s)] = cov
	var mid := int((a + b) * 0.5 * r.ds)
	_check("covered: tunnel road collider has meta covered", res[mid] and res[int(a * r.ds + 2.0)] and res[int(b * r.ds - 2.0)], str(res))
	_check("covered: open road outside the tube is not covered", not res[int(a * r.ds - 30.0)] and not res[int(b * r.ds + 30.0)], str(res))
	var n_cov := 0
	var n_road := 0
	for ch in w.roads.get_children():
		if ch is MeshInstance3D and (ch as MeshInstance3D).material_override == w.roads.road_mat:
			n_road += 1
			if float((ch as MeshInstance3D).get_instance_shader_parameter("covered")) > 0.5:
				n_cov += 1
	_check("covered: tube road pieces carry the shader parameter", n_cov >= 3, "%d of %d road meshes covered" % [n_cov, n_road])
	# Rain: the tunnel road stays dry-looking and grips as dry.
	Game.set_weather("storm", true)
	await _wait(3.0)
	rig.set_mode(CameraRig.Mode.CHASE_NEAR, false)
	await _wait(1.0)
	var wet_ids: Array = []
	for wh: CarController.Wheel in _car().wheels:
		wet_ids.append(String(wh.surface.id) if wh.surface else "-")
	await _shot("tunnel_inside_storm")
	_log("storm in tunnel: wheel surfaces %s, CarController.wetness %.2f" % [str(wet_ids), CarController.wetness])
	await _place(r, a * r.ds - 60.0, r.lane_offset(1), 1.0)
	await _wait(1.0)
	await _shot("tunnel_outside_storm")
	Game.set_weather("clear", true)
	await _wait(1.0)


## Terrain mesh triangles near the tube [a, b] with sample points inside the tube cross-section
## (|lateral| < e, above the road, below the 4.4 m walls + 2.8 m elliptic arch).
func _terrain_in_tube(r: RoadNetwork.Road, tube: PackedByteArray, a: int, b: int, e_t: float) -> Dictionary:
	var only_r := func(rr: RoadNetwork.Road) -> bool: return rr == r
	var bad := 0
	var checked := 0
	var where: Array = []
	var bary: Array[Vector3] = []
	for i in 5:
		for j in 5 - i:
			bary.append(Vector3(i, j, 4 - i - j) / 4.0)
	for c: TerrainStreamer.Chunk in w.terrain.chunks.values():
		if c.mi.mesh == null:
			continue
		var close := false
		for k in range(a, b + 1, 8):
			if c.center.distance_to(Vector2(r.pos[k].x, r.pos[k].z)) < 110.0:
				close = true
				break
		if not close:
			continue
		var arr := c.mi.mesh.surface_get_arrays(0)
		var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var ix: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		var org := c.mi.global_position
		for t in range(0, ix.size(), 3):
			var p0 := vs[ix[t]] + org
			var p1 := vs[ix[t + 1]] + org
			var p2 := vs[ix[t + 2]] + org
			var cen := (p0 + p1 + p2) / 3.0
			var size := maxf(cen.distance_to(p0), maxf(cen.distance_to(p1), cen.distance_to(p2)))
			var near := net.nearest(cen, 40.0, only_r)
			if near.is_empty() or tube[int(near["index"])] == 0 or absf(float(near["lateral"])) > e_t + size + 1.0:
				continue
			var ry := (near["position"] as Vector3).y
			if minf(p0.y, minf(p1.y, p2.y)) > ry + 7.4 or maxf(p0.y, maxf(p1.y, p2.y)) < ry:
				continue
			checked += 1
			for bc in bary:
				var q := p0 * bc.x + p1 * bc.y + p2 * bc.z
				var nq := net.nearest(q, 40.0, only_r)
				if nq.is_empty():
					continue
				var s := float(nq["s"]) + (q - (nq["position"] as Vector3)).dot(nq["forward"] as Vector3)
				if s <= a * r.ds + 0.5 or s >= b * r.ds - 0.5:
					continue
				var cp := r.point_at(s)
				var lat := absf((q - cp).dot(r.right_at(s)))
				var h := q.y - cp.y
				if lat >= e_t - 0.05 or h < 0.2:
					continue
				if h < 4.4 + 2.8 * sqrt(maxf(1.0 - (lat / e_t) * (lat / e_t), 0.0)) - 0.05:
					bad += 1
					if where.size() < 6:
						where.append("s=%.0f lat=%.1f h=%.1f chunk %s lod %d" % [s, lat, h, str(c.key), c.lod])
					break
	return {"bad": bad, "checked": checked, "where": where}


# ------------------------------------------------------------------ q4 bridge parapets

## Max lateral offset from the road centre (toward `side`) of the car's collision boxes (x) and visual body (y).
func _body_reach(r: RoadNetwork.Road, side: float) -> Vector2:
	var car := _car()
	var near := net.nearest(car.global_position, 20.0, func(rr: RoadNetwork.Road) -> bool: return rr == r)
	if near.is_empty():
		return Vector2(-INF, -INF)
	var s := float(near["s"]) + (car.global_position - (near["position"] as Vector3)).dot(near["forward"] as Vector3)
	var c := r.point_at(s)
	var rt := r.right_at(s) * side
	var col := -INF
	for n: String in ["ColMain", "ColCabin"]:
		var cs := car.get_node_or_null(NodePath(n)) as CollisionShape3D
		if cs == null or not (cs.shape is BoxShape3D):
			continue
		var hs := (cs.shape as BoxShape3D).size * 0.5
		for k in 8:
			var lp := Vector3(hs.x * (1.0 if k & 1 else -1.0), hs.y * (1.0 if k & 2 else -1.0), hs.z * (1.0 if k & 4 else -1.0))
			col = maxf(col, (cs.global_transform * lp - c).dot(rt))
	var vis := -INF
	var v := car.get_node_or_null(^"Visual") as Node3D
	if v != null:
		for mi in v.find_children("*", "MeshInstance3D", true, false):
			var m := mi as MeshInstance3D
			if not m.is_visible_in_tree() or m.mesh == null:
				continue
			var bb := m.get_aabb()
			if bb.size.length() > 8.0:
				continue
			for k in 8:
				vis = maxf(vis, (m.global_transform * bb.get_endpoint(k) - c).dot(rt))
	return Vector2(col, vis)


func _parapet() -> void:
	Game.spawn_car(0, true)
	await _wait(0.5)
	var ring := net.get_road("ring")
	var ci := main.get("car_input") as CarInput
	var e := ring.width * 0.5 + ring.shoulder
	var face := e + 0.1
	var res := {}
	# The flat Saltwind bridge (s 16488-16779) and the 10 % bridge at s 7851: steer into the parapet at
	# 20 deg and keep pushing at about 25 km/h with the keyboard (W taps + A/D held, CarInput enabled).
	for case: Array in [[16632.0, 1.0], [16632.0, -1.0], [7851.0, 1.0], [7851.0, -1.0]]:
		var s0: float = case[0]
		var side: float = case[1]
		if ring.flag_at(s0) & 1 == 0:
			_check("q4 ring s=%.0f is a bridge" % s0, false, "flag %d" % ring.flag_at(s0))
			continue
		await _place(ring, s0 - 12.0, side * 1.8, 1.0)
		var dir := ring.flat_tangent_at(s0 - 12.0).rotated(Vector3.UP, -side * deg_to_rad(20.0))
		_car().place_at(Transform3D(Basis.looking_at(dir, Vector3.UP), _car().global_position + Vector3.UP * 0.05), dir * (25.0 / 3.6))
		ci.enabled = true
		var steer := "steer_right" if side > 0.0 else "steer_left"
		Input.action_press(steer)
		var reach := Vector2(-INF, -INF)
		var t := 0.0
		while t < 3.5:
			await get_tree().physics_frame
			t += get_physics_process_delta_time()
			if _car().get_speed_kmh() < 25.0:
				Input.action_press("accelerate")
			else:
				Input.action_release("accelerate")
			var rr := _body_reach(ring, side)
			reach = Vector2(maxf(reach.x, rr.x), maxf(reach.y, rr.y))
		_hud(false)
		await _shot("parapet_%d_side%+d_chase" % [int(s0), int(side)])
		_hud(true)
		Input.action_release("accelerate")
		Input.action_release(steer)
		ci.enabled = false
		_car().in_throttle = 0.0
		_car().in_steer = 0.0
		res["%d%+d" % [int(s0), int(side)]] = reach
		_check("q4 parapet s=%.0f %s side stops the body at its inner face" % [s0, "right" if side > 0.0 else "left"], reach.x < face + 0.1 and reach.y < face + 0.2,
			"collision corner %.2f m, visual corner %.2f m (inner face %.2f, outer %.2f; was 5.40 / 5.50 on the right)" % [reach.x, reach.y, face, e + 0.5])
	var rgt: Vector2 = res.get("16632+1", Vector2.ZERO)
	var lft: Vector2 = res.get("16632-1", Vector2.ZERO)
	_check("q4 parapets alike on both sides", absf(rgt.x - lft.x) < 0.12, "right %.2f vs left %.2f" % [rgt.x, lft.x])
	# Fast glancing hits into both parapets: the car stays on the deck and upright.
	for side: float in [1.0, -1.0]:
		await _place(ring, 16560.0, side * 1.8, 1.0)
		var dir2 := ring.flat_tangent_at(16560.0).rotated(Vector3.UP, -side * deg_to_rad(12.0))
		_car().place_at(Transform3D(Basis.looking_at(dir2, Vector3.UP), _car().global_position + Vector3.UP * 0.05), dir2 * (120.0 / 3.6))
		var reach2 := -INF
		var t2 := 0.0
		while t2 < 2.0:
			await get_tree().physics_frame
			t2 += get_physics_process_delta_time()
			_car().in_throttle = 0.6
			reach2 = maxf(reach2, _body_reach(ring, side).x)
		_car().in_throttle = 0.0
		_car().in_brake = 1.0
		await _wait(1.5)
		var lat := absf(float(net.nearest(_car().global_position, 30.0, func(rr: RoadNetwork.Road) -> bool: return rr == ring).get("lateral", 99.0)))
		_check("q4 120 km/h glancing hit, %s parapet" % ("right" if side > 0.0 else "left"), reach2 < face + 0.15 and lat < e and absf(_roll_deg(_car())) < 20.0,
			"collision corner %.2f m, car %.2f m off the centre line, roll %.0f deg" % [reach2, lat, _roll_deg(_car())])
		_car().in_brake = 0.0


# ------------------------------------------------------------------ p31 banked gravel edge kerb

func _kerb() -> void:
	# Network survey: drop from the paved edge to what a wheel meets 0.3 m outside it.
	var space := get_viewport().get_world_3d().direct_space_state
	var worst := {}
	var big := 0
	var total := 0
	for r in net.roads:
		var keep := RoadBuilder.junction_keepout(net, r)
		var e := r.width * 0.5 + r.shoulder
		var rmax := 0.0
		for i in range(0, r.count(), 4):
			if r.flags[i] != 0 or keep[i] != 0:
				continue
			for side: float in [-1.0, 1.0]:
				var top := r.surface_point(i * r.ds, side * (e - 0.05))
				var q := r.surface_point(i * r.ds, side * (e + 0.3))
				if w.terrain.chunks.is_empty():
					continue
				var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(q + Vector3.UP * 3.0, q - Vector3.UP * 6.0, 1))
				var gy := w.height_at(q.x, q.z) if hit.is_empty() else (hit["position"] as Vector3).y
				gy = maxf(gy, w.height_at(q.x, q.z))
				var drop := top.y - gy
				total += 1
				rmax = maxf(rmax, drop)
				if drop > 0.3:
					big += 1
		worst[r.id] = snappedf(rmax, 0.01)
	_log("kerb survey: %d edge samples, %d with a > 0.30 m drop 0.3 m outside the edge; worst per road %s" % [total, big, str(worst)])
	var ft := net.get_road("farm_track")
	var fe := ft.width * 0.5 + ft.shoulder
	for i in range(int(336.0 / ft.ds), int(357.0 / ft.ds)):
		var txt := ""
		for side: float in [-1.0, 1.0]:
			var top := ft.surface_point(i * ft.ds, side * fe)
			var q := ft.surface_point(i * ft.ds, side * (fe + 1.5))
			txt += "  side %+.0f edge-ground %.2f" % [side, top.y - w.height_at(q.x, q.z)]
		_log("farm_track s=%.0f bank %+.3f%s" % [i * ft.ds, ft.bank[i], txt])
	# Drive from the field onto the Hedgerow Track high side toward the Wend Farm flag (default car).
	Game.spawn_car(0, true)
	await _wait(0.5)
	_connect_impact()
	var target := Vector3(-1502.1, 25.0, 561.7)
	for thr: float in [0.55, 1.0, 0.3]:
		var start := Vector3(-1519.0, 0.0, 587.0)
		start.y = w.height_at(start.x, start.z)
		main.call("teleport_to", {"position": start, "forward": (target - start).normalized()})
		await _settle()
		_car().freeze = false
		await _wait(1.0)
		impacts.clear()
		var side0 := float(net.nearest(_car().global_position, 40.0, func(rr: RoadNetwork.Road) -> bool: return rr == ft).get("lateral", 0.0))
		var t := 0.0
		var crossed := false
		var stuck := 0.0
		var vmin_edge := INF
		drive_fn = func(dt: float) -> void:
			var car := _car()
			var fw := -car.global_transform.basis.z
			fw.y = 0.0
			var to := target - car.global_position
			to.y = 0.0
			var ang := fw.normalized().signed_angle_to(to.normalized(), Vector3.UP)
			car.in_steer = clampf(-ang * 2.0, -1.0, 1.0)
			car.in_throttle = thr if car.get_speed_kmh() < 35.0 else 0.0
			car.in_brake = 0.0
		while t < 15.0 and not crossed:
			await get_tree().physics_frame
			t += get_physics_process_delta_time()
			var near := net.nearest(_car().global_position, 40.0, func(rr: RoadNetwork.Road) -> bool: return rr == ft)
			var lat := float(near.get("lateral", side0))
			if absf(lat) < fe + 2.0:
				vmin_edge = minf(vmin_edge, _car().get_speed_kmh())
			crossed = signf(lat) != signf(side0) and absf(lat) > fe + 0.5
			if t > 3.0 and _car().get_speed_kmh() < 1.0:
				stuck += get_physics_process_delta_time()
		drive_fn = Callable()
		_car().in_throttle = 0.0
		_car().in_brake = 0.5
		await _shot("kerb_flag_drive_thr%d" % int(thr * 100))
		_check("p31 drive across the Hedgerow Track high side (throttle %.2f)" % thr, crossed and stuck < 0.5, "crossed %s in %.1f s, min %.0f km/h at the edge, stuck %.1f s, impacts %s" % [str(crossed), t, vmin_edge, stuck, str(impacts)])
		_car().in_brake = 0.0


# ------------------------------------------------------------------ p13 Mirror Lake teleport

func _mirror() -> void:
	var lake: Dictionary = w.data.lake_list()[0]
	var lc := Vector2(float(lake["pos"][0]), float(lake["pos"][1]))
	for hour: float in [12.0, 19.0]:
		Game.set_time_of_day(hour)
		Game.teleport("Mirror Lake")
		await _settle()
		_car().in_handbrake = 1.0
		rig.set_mode(CameraRig.Mode.CHASE_NEAR, false)
		await _wait(2.0)
		var p := _car().global_position
		var fwd := -_car().global_transform.basis.z
		var to := Vector3(lc.x - p.x, 0, lc.y - p.z)
		var d_shore := Vector2(p.x, p.z).distance_to(lc) - float(lake["radius"])
		var ang := rad_to_deg(Vector3(fwd.x, 0, fwd.z).angle_to(to))
		_log("Mirror Lake teleport %02d:00 at %s, %.0f m from the lake centre (~%.0f m from the shore), lake %.0f deg off the heading" % [int(hour), str(p.round()), Vector2(p.x, p.z).distance_to(lc), d_shore, ang])
		await _shot("mirror_lake_chase_%02d" % int(hour))
		if hour == 12.0:
			_check("p13 Mirror Lake teleport is by the water", d_shore < 80.0 and ang < 100.0, "%.0f m from the shore, %.0f deg" % [d_shore, ang])
	_car().in_handbrake = 0.0
	Game.set_time_of_day(12.0)


# ------------------------------------------------------------------ p8 street lamps

func _lamps() -> void:
	var st := main.get_node_or_null(^"Settlements")
	var items: Array = st.get("items") if st else []
	var lamps := 0
	var on_road := 0
	for it: Dictionary in items:
		if it["name"] != "Lamp_Street":
			continue
		lamps += 1
		var p: Vector3 = (it["xf"] as Transform3D).origin
		var c := net.edge_clearance(p)
		if c < 0.5:
			on_road += 1
			_log("lamp on/near a road at %s clearance %.2f" % [str(p.round()), c])
	_check("p8 no street lamp post on any road surface", lamps > 0 and on_road == 0, "%d lamps, %d within 0.5 m of a road edge" % [lamps, on_road])
	var lp: PackedVector3Array = w.roads.lamp_positions
	var street := 0
	var bad := 0
	for p in lp:
		var near := net.nearest(p, 30.0)
		if not near.is_empty() and p.y - (near["position"] as Vector3).y > 3.0:
			continue  # tunnel lamp
		street += 1
		if net.edge_clearance(p) < 0.5:
			bad += 1
	_check("p8 lighting lamp positions off the road", bad == 0, "%d street lamp positions, %d on a road" % [street, bad])
	# Settlement colliders over any road surface (box sweep along every road).
	var space := get_viewport().get_world_3d().direct_space_state
	var sph := SphereShape3D.new()
	sph.radius = 0.5
	var qp := PhysicsShapeQueryParameters3D.new()
	qp.shape = sph
	qp.collision_mask = 0xFFFFFFFF
	var found := {}
	for r in net.roads:
		var e := r.width * 0.5 + r.shoulder - 0.4
		for i in range(0, r.count()):
			for lat in range(int(-e), int(e) + 1, 1):
				var sp := r.surface_point(i * r.ds, float(lat))
				for hgt: float in [1.0]:
					qp.transform = Transform3D(Basis(), sp + Vector3.UP * hgt)
					for h: Dictionary in space.intersect_shape(qp, 4):
						var col := h["collider"] as Node
						if col and String(col.name).begins_with("SettlementCol"):
							found[col.get_path()] = "%s s=%.0f lat %d at %s" % [r.id, i * r.ds, lat, str(sp.round())]
		await get_tree().process_frame
	for k in found:
		_log("settlement collider on road: %s %s" % [str(k), found[k]])
	_check("p8 no settlement collider over a road (sphere sweep, all roads)", found.is_empty(), "%d" % found.size())
	# Drive the old post lines (ring s=96 lat -3.05 and s=1083 lat -0.03) at 55 km/h.
	var ring := net.get_road("ring")
	for case: Array in [[96.0, -3.05], [1083.0, -0.03]]:
		var s0: float = float(case[0]) - 70.0
		await _place(ring, s0, float(case[1]), 1.0)
		var f := RoadFollower.new()
		f.setup(ring, s0, 1, float(case[1]))
		f.target_speed = 55.0 / 3.6
		f.respect_traffic = false
		impacts.clear()
		drive_fn = func(dt: float) -> void: f.drive(_car(), dt)
		var min_v := INF
		var t3 := Time.get_ticks_msec()
		while f.s < float(case[0]) + 25.0 and Time.get_ticks_msec() - t3 < 30000:
			await get_tree().physics_frame
			if f.s > float(case[0]) - 15.0:
				min_v = minf(min_v, _car().get_speed_kmh())
		drive_fn = Callable()
		_check("p8 ring s=%.0f lateral %.2f passes freely" % [float(case[0]), float(case[1])], impacts.is_empty() and min_v > 35.0, "min %.0f km/h impacts %s" % [min_v, str(impacts)])
		await _shot("lamps_ring_s%d_after" % int(case[0]))
