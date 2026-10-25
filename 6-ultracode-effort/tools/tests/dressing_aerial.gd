extends Node
## Dressing QA: loads the main scene, teleports to POIs and takes aerial screenshots of the
## settlements / vegetation from fixed camera offsets. Arguments (after "--"):
##   --targets="Millbrook;Gullhaven"  --dist=90 --height=60 --time=13 --shot-dir=res://qa_output/dressing/aerial
##   --at="x,z;x,z"  extra raw positions (aerial views of arbitrary spots)

var out_dir := "res://qa_output/dressing/aerial"


func _ready() -> void:
	out_dir = QaDirector._arg("shot-dir", out_dir)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(main)
	_run.call_deferred()


func _wait(s: float) -> void:
	await get_tree().create_timer(s, true, false, true).timeout


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := out_dir.path_join(name + ".png")
	img.save_png(path)
	print("[aerial] shot ", ProjectSettings.globalize_path(path))


func _run() -> void:
	SaveGame.enabled = false
	var t := 0.0
	while Game.main == null or Game.main.is_loading:
		await get_tree().process_frame
		t += get_process_delta_time()
		if t > 60.0:
			break
	var tod := QaDirector._arg("time", "13")
	Game.set_time_of_day(tod.to_float())
	Game.main.car_input.enabled = false
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	await _wait(3.0)
	await _shot("spawn_chase")
	await _perf("spawn")
	if QaDirector._arg("quality-cycle", "") != "":
		var q0: int = Settings.get_value("quality", 2)
		for q: int in [0, 3, q0]:
			Settings.set_value("quality", q, false)
			await _wait(2.5)
			var dn: Node = Game.get_meta(&"dressing", null)
			print("[aerial] quality %d -> %s" % [q, dn.summary() if dn else "-"])
	var dist := QaDirector._arg("dist", "90").to_float()
	var height := QaDirector._arg("height", "60").to_float()
	var targets: Array = []
	var tlist := QaDirector._arg("targets", "")
	if tlist != "":
		for n in tlist.split(";"):
			for d: Dictionary in Game.get_teleport_targets():
				if String(d["name"]).to_lower().begins_with(n.to_lower()):
					var poi := _poi_pos(String(d["name"]))
					targets.append([n, poi if poi != Vector3.INF else (d["position"] as Vector3)])
					break
	var at := QaDirector._arg("at", "")
	if at != "":
		for s in at.split(";"):
			var xz := s.split(",")
			var p := Vector3(xz[0].to_float(), 0, xz[1].to_float())
			targets.append(["at_%d_%d" % [int(p.x), int(p.z)], p])
	for tg: Array in targets:
		var name: String = tg[0]
		var p: Vector3 = tg[1]
		p.y = (Game.world as World).height_at(p.x, p.z)
		var rp: Dictionary = (Game.world as World).nearest_road_point(p)
		Game.main.teleport_to(rp)
		Game.camera_rig.active = true
		await _wait(0.2)
		Game.camera_rig.active = false
		var w := Game.world as World
		var t2 := 0.0
		while t2 < 15.0 and w.terrain.pending_count() > 0:
			await get_tree().process_frame
			t2 += get_process_delta_time()
		await _wait(2.5)
		var cam: Camera3D = Game.camera_rig.camera
		for k in 2:
			var ang := deg_to_rad(35.0 + k * 150.0)
			var off := Vector3(cos(ang) * dist, height, sin(ang) * dist)
			var cp := p + off
			cp.y = maxf(p.y, w.height_at(cp.x, cp.z)) + height
			cam.global_position = cp
			cam.look_at(p, Vector3.UP)
			await _wait(0.5)
			await _shot("%s_%d" % [name.to_snake_case().replace(" ", "_"), k])
		cam.global_position = p + Vector3(0, height * 2.5 + dist, 1.0)
		cam.look_at(p, Vector3.UP)
		await _wait(0.5)
		await _shot("%s_top" % name.to_snake_case().replace(" ", "_"))
		Game.camera_rig.active = true
		await _wait(1.5)
		await _shot("%s_chase" % name.to_snake_case().replace(" ", "_"))
		await _perf(name)
		var d: Node = Game.get_meta(&"dressing", null)
		if QaDirector._arg("collider-check", "") != "" and d != null:
			await get_tree().physics_frame
			await _wait(0.6)
			_collider_check(d)
		if d != null and d.has_method("summary"):
			print("[aerial] ", name, " ", d.summary(), " fps=", Engine.get_frames_per_second())
	get_tree().quit(0)


func _poi_pos(name: String) -> Vector3:
	for p: Dictionary in (Game.world as World).data.pois():
		if String(p["name"]) == name:
			return Vector3(float(p["pos"][0]), 0.0, float(p["pos"][1]))
	return Vector3.INF


func _perf(label: String) -> void:
	var vp := get_viewport().get_viewport_rid()
	var gpu := 0.0
	var cpu := 0.0
	var n := 0
	var t := 0.0
	while t < 2.0:
		await get_tree().process_frame
		t += get_process_delta_time()
		gpu += RenderingServer.viewport_get_measured_render_time_gpu(vp)
		cpu += RenderingServer.viewport_get_measured_render_time_cpu(vp)
		n += 1
	print("[aerial] perf %s gpu_ms=%.2f render_cpu_ms=%.2f fps=%.0f draws=%d prims=%d" % [label, gpu / n, cpu / n, Engine.get_frames_per_second(),
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)])


func _collider_check(d: Node) -> void:
	var space := get_viewport().get_world_3d().direct_space_state
	var pool: Node = d.get("collider_pool")
	var hits := 0
	var tried := 0
	for c in pool.get_children():
		var body := c as StaticBody3D
		if body == null or (body.get_child(0) as CollisionShape3D).disabled:
			continue
		tried += 1
		# trunks: cylinder centred on the body; rock / cactus hulls (barrier layer): origin at the sunk base
		var p := body.global_position + (Vector3(0, 0.3, 0) if body.collision_layer == 32 else Vector3.ZERO)
		var q := PhysicsRayQueryParameters3D.create(p + Vector3(4, 0, 0.05), p - Vector3(4, 0, -0.05), body.collision_layer)
		var hit := space.intersect_ray(q)
		if not hit.is_empty() and hit["collider"] == body:
			hits += 1
		elif QaDirector._arg("collider-debug", "") != "":
			var cs := body.get_child(0) as CollisionShape3D
			print("[aerial]   miss %s layer %d shape %s xf %s at %s hit %s" % [body.name, body.collision_layer, cs.shape.get_class(), cs.transform.basis.get_scale(), p.round(),
				(str((hit["collider"] as Node).name) + " " + str((hit["position"] as Vector3).round())) if not hit.is_empty() else "none"])
		if tried >= 20:
			break
	var sett: Node = Game.main.get_node_or_null("Settlements")
	var sh := 0
	var st := 0
	if sett != null:
		for it: Dictionary in sett.get("items"):
			if int(it["col"]) == 0:
				continue
			var xf: Transform3D = it["xf"]
			var top := xf.origin + Vector3.UP * 90.0
			var q2 := PhysicsRayQueryParameters3D.create(top, xf.origin - Vector3.UP * 0.5, 1)
			var hit2 := space.intersect_ray(q2)
			st += 1
			if PropLibrary_is_open(String(it["name"])):
				st -= 1
				continue
			if not hit2.is_empty() and String((hit2["collider"] as Node).name).begins_with("SettlementCol"):
				sh += 1
			elif st - sh <= 12:
				var q3 := PhysicsRayQueryParameters3D.create(top, xf.origin - Vector3.UP * 3.0, 1)
				q3.hit_back_faces = true
				q3.hit_from_inside = true
				var hit3 := space.intersect_ray(q3)
				print("[aerial]   miss ", it["name"], " at ", xf.origin.round(), " hit=", (hit2["collider"] as Node).name if not hit2.is_empty() else "none",
					" | longer ray w/ backfaces: ", (str((hit3["collider"] as Node).name) + " y=" + str(snappedf((hit3["position"] as Vector3).y - xf.origin.y, 0.01))) if not hit3.is_empty() else "none")
			if st >= 400:
				break
	print("[aerial] collider check: trees/rocks/cacti %d/%d rays hit their pooled body; settlements %d/%d downward rays hit a settlement collider" % [hits, tried, sh, st])


## Props whose centre column is legitimately empty (boards on posts).
func PropLibrary_is_open(name: String) -> bool:
	return name in ["Billboard", "Bus_Stop"]
