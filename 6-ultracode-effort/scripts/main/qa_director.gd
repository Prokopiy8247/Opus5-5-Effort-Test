class_name QaDirector
extends Node
## Command-line driven QA automation (arguments after "--"):
##   --qa=shots   [--targets=a;b;c] [--views=0,2,4]  screenshots at teleport targets, then quit
##   --qa=drive   [--road=ring] [--speed=110] [--minutes=4]  autopilot lap with perf log, then quit
##   --qa=garage  screenshot of every car, then quit
##   --time=<h> --weather=<id> --car=<id|index> --traffic=<0..1>   applied in any mode
##   --shot-dir=res://qa_output/shots
## Results are written to qa_output/ (git-ignored) and printed with a "[qa]" prefix.

const QaAutopilot := preload("res://scripts/main/qa_autopilot.gd")

var mode: String = ""
var out_dir: String = "res://qa_output/shots"
var report: Dictionary = {}


func _ready() -> void:
	mode = _arg("qa", "")
	out_dir = _arg("shot-dir", out_dir)
	if mode == "":
		return
	process_mode = Node.PROCESS_MODE_ALWAYS
	SaveGame.enabled = false
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	_run.call_deferred()


static func _arg(key: String, default: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--" + key + "="):
			return a.substr(key.length() + 3)
		if a == "--" + key:
			return "1"
	return default


func log_line(s: String) -> void:
	print("[qa] ", s)


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds, true, false, true).timeout


func _wait_loaded() -> void:
	var main: Node = Game.main
	var t := 0.0
	while main.is_loading and t < 60.0:
		await get_tree().process_frame
		t += get_process_delta_time()


func _wait_streamed(max_s := 20.0) -> void:
	var t := 0.0
	await get_tree().process_frame
	if Game.world is World:
		var w := Game.world as World
		while t < max_s and (w.terrain.pending_count() > 0 or not w.roads.done):
			await get_tree().process_frame
			t += get_process_delta_time()
	await _wait(0.6)


func _apply_common() -> void:
	var car := _arg("car", "")
	if car != "":
		var i := Game.find_car_index(car)
		if i >= 0:
			Game.spawn_car(i, true)
	var tod := _arg("time", "")
	if tod != "":
		Game.set_time_of_day(tod.to_float())
	var w := _arg("weather", "")
	if w != "":
		Game.set_weather(w, true)
	var tr := _arg("traffic", "")
	if tr != "":
		Game.set_traffic_density(tr.to_float())


func shot(name: String) -> String:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := out_dir.path_join(name + ".png")
	img.save_png(path)
	log_line("shot %s %dx%d" % [ProjectSettings.globalize_path(path), img.get_width(), img.get_height()])
	return path


func _run() -> void:
	await _wait_loaded()
	_apply_common()
	await _wait(1.0)
	match mode:
		"shots":
			await _run_shots()
		"drive":
			await _run_drive()
		"garage":
			await _run_garage()
		"roadcheck":
			await _run_roadcheck()
		"probe":
			await _run_probe()
		"spot":
			await _run_spot()
		"teleports":
			await _run_teleports()
		"culverts":
			await _run_culverts()
		_:
			log_line("unknown qa mode " + mode)
	log_line("done")
	get_tree().quit(0)


func _run_shots() -> void:
	var targets := _arg("targets", "")
	var names: PackedStringArray = []
	if targets == "":
		for t: Dictionary in Game.get_teleport_targets():
			if t["kind"] != "region":
				names.append(t["name"])
	else:
		names = targets.split(";")
	var views := _arg("views", "0").split(",")
	(Game.main as Node).car_input.enabled = false
	for n in names:
		if not Game.teleport(n):
			log_line("teleport failed: " + n)
			continue
		await _wait_streamed()
		Game.player_car.freeze = false
		await _wait(1.5)
		for v in views:
			Game.camera_rig.set_mode(int(v), false)
			await _wait(0.6)
			await shot("%s_v%s" % [n.to_snake_case().replace(" ", "_"), v])
		log_line("fps at %s: %.1f" % [n, Engine.get_frames_per_second()])


func _run_garage() -> void:
	(Game.main as Node).car_input.enabled = false
	Game.teleport(_arg("at", "Sunward Festival"))
	await _wait_streamed()
	for i in Game.get_car_catalog().size():
		Game.spawn_car(i, true)
		await _wait(1.8)
		Game.camera_rig.set_mode(CameraRig.Mode.CHASE_NEAR, false)
		await _wait(0.8)
		await shot("car_%02d_%s" % [i + 1, Game.get_car_catalog()[i].id])
		Game.camera_rig.set_mode(CameraRig.Mode.COCKPIT, false)
		await _wait(0.6)
		await shot("car_%02d_%s_cockpit" % [i + 1, Game.get_car_catalog()[i].id])


## Structural check of every road: the road collider exists under every 3 m sample (no gaps/holes),
## plus grade and curve-radius statistics. Writes qa_output/roadcheck.json.
func _run_roadcheck() -> void:
	var w := Game.world as World
	var t := 0.0
	while not w.roads.done and t < 60.0:
		await get_tree().process_frame
		t += get_process_delta_time()
	await get_tree().physics_frame
	var space := get_viewport().get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.new()
	q.collision_mask = 1
	var out := {}
	var total_missing := 0
	var total_steps := 0
	for r: RoadNetwork.Road in w.data.network.roads:
		var missing := 0
		var steps := 0
		var ramps := 0
		var max_grade := 0.0
		var min_radius := INF
		var max_step := 0.0
		var n := r.count()
		var miss_s: Array = []
		for i in n:
			var p := r.pos[i]
			# Skip samples that sit inside the parent road at junction ends (child mesh is trimmed there).
			for lane: float in [0.0, r.width * 0.3, -r.width * 0.3]:
				# Jitter off the mesh vertex rows/columns (rays exactly through a shared vertex can slip).
				var sp := r.surface_point(i * r.ds + 0.37, lane + 0.21)
				q.from = sp + Vector3.UP * 3.0
				q.to = sp - Vector3.UP * 3.0
				var hit := space.intersect_ray(q)
				if not hit.is_empty() and (hit["collider"] as Node).name == &"RampBody":
					ramps += 1
					break
				if not hit.is_empty():
					var dy := absf((hit["position"] as Vector3).y - sp.y)
					if dy > 0.08 and dy <= 0.45:
						steps += 1
						if total_steps + steps <= 40:
							log_line("   step %s s=%.0f lane %+.1f: %.2f m (%s)" % [r.id, i * r.ds, lane, (hit["position"] as Vector3).y - sp.y, str((hit["collider"] as Object).get_meta(&"road", "-"))])
				if hit.is_empty() or absf((hit["position"] as Vector3).y - sp.y) > 0.45:
					missing += 1
					if miss_s.size() < 12:
						miss_s.append(snappedf(i * r.ds, 1.0))
						if hit.is_empty():
							log_line("   miss %s s=%.0f lane %+.1f: no hit (exp y %.2f)" % [r.id, i * r.ds, lane, sp.y])
						else:
							var hc: Object = hit["collider"]
							log_line("   miss %s s=%.0f lane %+.1f: hit y %.2f exp %.2f %s %s road=%s" % [r.id, i * r.ds, lane, (hit["position"] as Vector3).y, sp.y, (hc as Node).name if hc is Node else hc.get_class(), hc.get_class(), str(hc.get_meta(&"road", "-"))])
					break
			if i > 0:
				var a := r.pos[i - 1]
				var g := absf(p.y - a.y) / maxf(Vector2(p.x - a.x, p.z - a.z).length(), 0.01)
				max_grade = maxf(max_grade, g)
				max_step = maxf(max_step, absf(p.y - a.y))
			if i > 2 and i < n - 3:
				var k := absf(WorldGen._curvature(Vector2(r.pos[i - 3].x, r.pos[i - 3].z), Vector2(p.x, p.z), Vector2(r.pos[i + 3].x, r.pos[i + 3].z)))
				if k > 0.0001:
					min_radius = minf(min_radius, 1.0 / k)
		total_missing += missing
		total_steps += steps
		out[r.id] = {"samples": n, "missing_surface": missing, "on_jump_ramp": ramps, "missing_at_s": miss_s, "max_grade_pct": snappedf(max_grade * 100.0, 0.1),
			"min_radius_m": snappedf(min_radius, 0.1), "max_step_m": snappedf(max_step, 0.01), "length_m": r.length}
		log_line("road %-16s len %6.0f  missing %3d  max grade %4.1f%%  min radius %6.1f m" % [r.id, r.length, missing, max_grade * 100.0, min_radius])
	out["total_missing"] = total_missing
	out["total_steps"] = total_steps
	var f := FileAccess.open("res://qa_output/roadcheck.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(out, "	"))
	log_line("roadcheck total missing samples: %d, steps 8-45 cm: %d" % [total_missing, total_steps])


## Screenshots at arbitrary road positions: --road=<id> --s=a,b,c [--views=0,1] [--back=1 to look back]
func _run_spot() -> void:
	var w := Game.world as World
	var r := w.data.network.get_road(_arg("road", "ring"))
	(Game.main as Node).car_input.enabled = false
	for ss in _arg("s", "0").split(","):
		var sv := ss.to_float()
		var fwd := r.flat_tangent_at(sv)
		(Game.main as Node).teleport_to({"position": r.surface_point(sv, r.lane_offset(1) if r.traffic else 0.0), "forward": fwd})
		await _wait_streamed()
		Game.player_car.freeze = false
		await _wait(1.0)
		for v in _arg("views", "1").split(","):
			Game.camera_rig.set_mode(int(v), false)
			await _wait(0.6)
			await shot("spot_%s_%05d_v%s" % [r.id, int(sv), v])
		if _arg("aerial", "") != "":
			var rig := Game.camera_rig as CameraRig
			rig.active = false
			var c := Game.player_car.global_position
			var h := _arg("aerial", "30").to_float()
			rig.global_transform = Transform3D(Basis(), c + Vector3(-fwd.x * h * 0.6, h, -fwd.z * h * 0.6)).looking_at(c + fwd * 10.0, Vector3.UP)
			await _wait(0.4)
			await shot("spot_%s_%05d_aerial" % [r.id, int(sv)])
			rig.active = true
		var p := Game.player_car.global_position
		log_line("spot %s s=%.0f car=%s ground=%.2f flags=%d" % [r.id, sv, str(p.round()), w.ground_at(p.x, p.z, p.y + 5.0), r.flag_at(sv)])


## Names of the bodies overlapping a box slightly larger than the car (stuck diagnostics).
func _touching(car: CarController) -> String:
	var q := PhysicsShapeQueryParameters3D.new()
	var box := BoxShape3D.new()
	box.size = car.data.body_size + Vector3(0.6, 0.2, 0.8) if car.data else Vector3(2.4, 1.6, 5.0)
	q.shape = box
	q.transform = car.global_transform.translated_local(Vector3(0, box.size.y * 0.5 + 0.15, 0))
	q.collision_mask = 0xFFFF
	q.exclude = [car.get_rid()]
	var out: PackedStringArray = []
	for h: Dictionary in get_viewport().get_world_3d().direct_space_state.intersect_shape(q, 8):
		var c: Object = h["collider"]
		out.append("%s(%s)" % [(c as Node).name if c is Node else "?", str(c.get_meta(&"road", c.get_meta(&"surface", ""))) if c != null else ""])
	return ",".join(out)


## Lists the procedural culverts and photographs the first few from the side (--count=N).
func _run_culverts() -> void:
	var w := Game.world as World
	while not w.roads.done:
		await get_tree().process_frame
	var cps := w.roads.culvert_positions
	log_line("culverts: %d" % cps.size())
	(Game.main as Node).car_input.enabled = false
	for k in mini(cps.size(), _arg("count", "3").to_int()):
		var p := cps[k]
		var near: Dictionary = w.data.network.nearest(p, 20.0)
		var fwd: Vector3 = near.get("forward", Vector3(0, 0, -1))
		(Game.main as Node).teleport_to({"position": p, "forward": fwd})
		await _wait_streamed()
		var rt := Vector3(-fwd.z, 0, fwd.x)
		var rig := Game.camera_rig as CameraRig
		rig.active = false
		var eye := p + rt * 30.0 + fwd * 14.0
		eye.y = maxf(w.height_at(eye.x, eye.z), p.y - 6.0) + 4.0
		rig.global_transform = Transform3D(Basis(), eye).looking_at(p + rt * 10.0 - Vector3.UP * 3.0, Vector3.UP)
		await _wait(0.6)
		await shot("culvert_%02d" % k)
		rig.active = true
		log_line("culvert %d at %s road=%s" % [k, str(p.round()), near["road"].id if not near.is_empty() else "-"])


## Teleport to every target and check the car settles upright on a road surface.
func _run_teleports() -> void:
	(Game.main as Node).car_input.enabled = false
	var bad := 0
	for t: Dictionary in Game.get_teleport_targets():
		Game.teleport(String(t["name"]))
		await _wait_streamed(12.0)
		Game.player_car.freeze = false
		await _wait(2.0)
		var car := Game.player_car
		var surf := car.dominant_surface()
		var sid := String(surf.id) if surf else "none"
		var res: Dictionary = (Game.world as World).data.network.nearest(car.global_position, 50.0)
		var lat: float = absf(float(res.get("lateral", 99.0)))
		var upright := car.global_transform.basis.y.y > 0.9
		var ok := upright and car.wheels_on_ground >= 3 and (sid in ["dirt", "gravel", "sand"] or (surf != null and surf.paved)) and car.speed_ms < 2.0
		if not ok:
			bad += 1
		log_line("teleport %-28s %s surface=%s lateral=%.1f wheels=%d speed=%.1f upright=%s" % [t["name"], "OK " if ok else "BAD", sid, lat, car.wheels_on_ground, car.speed_ms, str(upright)])
	log_line("teleports bad: %d" % bad)


func _run_probe() -> void:
	var w := Game.world as World
	while not w.roads.done:
		await get_tree().process_frame
	await get_tree().physics_frame
	var r := w.data.network.get_road(_arg("road", "ring"))
	var space := get_viewport().get_world_3d().direct_space_state
	for ss in _arg("s", "0").split(","):
		var sv := ss.to_float()
		var i := int(sv / r.ds)
		log_line("probe %s s=%.0f flags=%d bank=%.4f centre=%s" % [r.id, sv, r.flags[i], r.bank[i], str(r.pos[i])])
		for lane: float in [-r.width * 0.3, 0.0, r.width * 0.3]:
			for ds: float in [-1.5, 0.0, 1.5]:
				var sp := r.surface_point(sv + ds, lane)
				var q := PhysicsRayQueryParameters3D.create(sp + Vector3.UP * 3.0, sp - Vector3.UP * 3.0, 1)
				var hit := space.intersect_ray(q)
				var txt := "none"
				if not hit.is_empty():
					var col: Object = hit["collider"]
					txt = "y=%.2f (exp %.2f) %s surf=%s road=%s" % [(hit["position"] as Vector3).y, sp.y, col.get_class(), str(col.get_meta(&"surface", "-")), str(col.get_meta(&"road", "-"))]
				log_line("   lane %+.1f ds %+.1f -> %s" % [lane, ds, txt])


func _run_drive() -> void:
	var w := Game.world as World
	if w == null:
		return
	var road := w.data.network.get_road(_arg("road", "ring"))
	var speed := _arg("speed", "100").to_float() / 3.6
	var minutes := _arg("minutes", "3").to_float()
	var start_s := _arg("start", "40").to_float()
	(Game.main as Node).car_input.enabled = false
	var car := Game.player_car
	var f := QaAutopilot.new()
	f.setup(w.data.network, road, start_s)
	f.target_speed = speed
	f.lat_accel = _arg("lat", "7.0").to_float()
	(Game.main as Node).teleport_to({"position": f.lane_point(start_s), "forward": road.flat_tangent_at(start_s)})
	await _wait_streamed()
	car.freeze = false
	var t := 0.0
	var frames := 0
	var worst := 0.0
	var dist := 0.0
	var last_pos := car.global_position
	var samples: Array = []
	var log_t := 0.0
	var shots := int(_arg("drive-shots", "0"))
	var shot_every := minutes * 60.0 / maxf(shots, 1)
	var next_shot := shot_every * 0.5
	var mem0 := Performance.get_monitor(Performance.MEMORY_STATIC)
	var stuck := 0.0
	var win_max := 0.0
	var hitches := 0
	var skip_frames := 0
	while t < minutes * 60.0:
		await get_tree().physics_frame
		car = Game.player_car
		f.drive(car)
		var dt := get_process_delta_time()
		await get_tree().process_frame
		var fdt := get_process_delta_time()
		t += fdt
		frames += 1
		if skip_frames > 0:
			skip_frames -= 1
		elif t > 3.0:
			worst = maxf(worst, fdt)
			win_max = maxf(win_max, fdt)
			if fdt > 1.0 / 30.0:
				hitches += 1
		dist += car.global_position.distance_to(last_pos)
		last_pos = car.global_position
		stuck = stuck + fdt if car.speed_ms < 2.0 else 0.0
		if stuck > 6.0:
			log_line("stuck at %s s=%.0f - recovering" % [str(car.global_position.round()), f.s])
			log_line("   freeze=%s wheels=%d gear=%d thr=%.2f brk=%.2f hold=%s session=%s touching=%s" % [str(car.freeze), car.wheels_on_ground, car.gear, car.in_throttle, car.in_brake, str(car.in_hold), str(Game.activities.call(&"get_session_id")) if Game.activities != null and Game.activities.has_method(&"get_session_id") else "-", _touching(car)])
			(Game.main as Node).teleport_to({"position": f.lane_point(f.s + 20.0), "forward": road.flat_tangent_at(f.s + 20.0)})
			f.s += 20.0
			stuck = 0.0
		if shots > 0 and t >= next_shot:
			next_shot += shot_every
			skip_frames = 3
			await shot("drive_%03d" % int(t))
		log_t += fdt
		if log_t >= 5.0:
			log_t = 0.0
			var line := {
				"t": snappedf(t, 0.1), "kmh": snappedf(car.get_speed_kmh(), 0.1), "fps": Engine.get_frames_per_second(),
				"dist_km": snappedf(dist / 1000.0, 0.01), "s": snappedf(f.s, 1.0),
				"proc_ms": snappedf(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, 0.01),
				"phys_ms": snappedf(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0, 0.01),
				"draws": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
				"prims": Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
				"mem_mb": snappedf(Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0, 0.1),
				"nodes": Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
				"region": w.region_at(car.global_position),
				"traffic": Game.traffic.active_count() if Game.traffic and Game.traffic.has_method("active_count") else -1,
				"max_frame_ms": snappedf(win_max * 1000.0, 0.1), "hitches_total": hitches,
			}
			win_max = 0.0
			samples.append(line)
			log_line(JSON.stringify(line))
		if not road.loop and f.finished:
			break
	report = {"mode": "drive", "road": road.id, "seconds": t, "frames": frames, "avg_fps": frames / maxf(t, 0.001),
		"worst_frame_ms": worst * 1000.0, "frames_over_33ms": hitches, "distance_km": dist / 1000.0,
		"mem_start_mb": mem0 / 1048576.0, "mem_end_mb": Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0,
		"terrain": w.terrain.stats, "samples": samples}
	var fa := FileAccess.open(_arg("report", "res://qa_output/drive_report.json"), FileAccess.WRITE)
	fa.store_string(JSON.stringify(report, "\t"))
	log_line("avg fps %.1f worst %.1f ms dist %.2f km" % [report["avg_fps"], report["worst_frame_ms"], report["distance_km"]])
