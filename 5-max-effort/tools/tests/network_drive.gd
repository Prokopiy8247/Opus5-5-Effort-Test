extends Node
## QA script: drives every road of the network end to end with the autopilot (traffic off) and
## reports stuck points, falls below the terrain and flips. Works headless:
##   Godot_console.exe --headless --fixed-fps 120 --path . -- --fresh --qa=script
##       --script_path=res://tools/tests/network_drive.gd [--roads=0,17] [--speed=110]


func run(_qa: Node) -> void:
	Game.settings["traffic_density"] = 0.0
	if Game.traffic != null:
		Game.traffic.set("density", 0.0)
	var data: WorldData = Game.world.get("data")
	var only: Array = []
	if Game.qa_args.has("roads"):
		for s in String(Game.qa_args["roads"]).split(","):
			only.append(int(s))
	var total_issues := 0
	var total_m := 0.0
	var t_all := Time.get_ticks_msec()
	for ri in data.roads.size():
		if not only.is_empty() and not only.has(ri):
			continue
		var r: Dictionary = data.roads[ri]
		var n := (r["x"] as PackedFloat32Array).size()
		var closed: bool = r["closed"]
		var start := 8
		var p := data.road_point(ri, start)
		var h := data.road_dir(ri, start)
		Game.world.call("prepare_area", p)
		Game.player_car.reset_to(Game.world.call("nearest_road_transform", p, h))
		for f in 20:
			await get_tree().physics_frame
		var ap: Node = Game.world.call("create_autopilot", Game.player_car)
		ap.set("road_index", ri)
		ap.set("direction", 1)
		var lim := float(r["speed"])
		ap.set("max_speed_kmh", clampf(lim * 1.35, 60.0, float(Game.qa_args.get("speed", "120"))))
		ap.set("lane_offset", 1.75 if int(r["lanes"]) >= 2 else 0.0)
		var issues: Array[String] = []
		var t := 0.0
		var stuck := 0.0
		var progress := 0
		var last_i := start
		var goal := n - 6 if not closed else n + start - 10
		var max_t := float(n) * 2.0 / 8.0 + 60.0
		var car := Game.player_car
		while t < max_t:
			await get_tree().physics_frame
			var dt := get_physics_process_delta_time()
			t += dt
			var i := int(ap.get("_i"))
			var di := i - last_i
			if closed and di < -n / 2:
				di += n
			if di > 0 and di < 200:
				progress += di
			last_i = i
			if progress >= goal - start:
				break
			var pos := car.global_position
			var ground := data.height_at(pos.x, pos.z)
			if pos.y < ground - 2.0 and not (data.roads[ri]["flags"] as PackedInt32Array)[clampi(i, 0, n - 1)] & WorldData.F_TUNNEL:
				issues.append("FELL i=%d at %s (ground %.1f)" % [i, str(pos.snapped(Vector3.ONE)), ground])
				_skip(ap, data, ri, i + 25)
				continue
			if car.global_transform.basis.y.y < 0.3:
				issues.append("FLIP i=%d at %s" % [i, str(pos.snapped(Vector3.ONE))])
				_skip(ap, data, ri, i + 10)
				continue
			if Game.qa_args.has("mem") and int(t * 120.0) % 7200 == 0:
				print("[net]   mem t=%.0f progress=%.1f km static=%.1f MB nodes=%d objects=%d" % [t, progress * 0.002,
					OS.get_static_memory_usage() / 1048576.0, int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
					int(Performance.get_monitor(Performance.OBJECT_COUNT))])
			if Game.qa_args.has("trace") and int(t * 120.0) % 1200 == 0:
				print("[net]   t=%.0f i=%d progress=%d v=%.0f pos=%s" % [t, i, progress, car.speed_kmh, str(car.global_position.snapped(Vector3.ONE))])
			stuck = stuck + dt if car.speed_kmh < 3.0 else 0.0
			if stuck > 4.0:
				issues.append("STUCK i=%d at %s" % [i, str(pos.snapped(Vector3.ONE))])
				stuck = 0.0
				_skip(ap, data, ri, i + 25)
		var dist := float(progress) * 2.0
		total_m += dist
		total_issues += issues.size()
		print("[net] %-24s %-8s %5.0f / %5.0f m  %5.1f s  avg %5.1f km/h  issues %d %s" % [r["name"], r["class"], dist,
			float(n) * 2.0, t, dist / maxf(t, 0.1) * 3.6, issues.size(), "" if issues.is_empty() else str(issues)])
		ap.queue_free()
		await get_tree().physics_frame
	print("[net] TOTAL %.1f km driven, %d issues, %.0f s wall" % [total_m / 1000.0, total_issues, (Time.get_ticks_msec() - t_all) / 1000.0])


func _skip(ap: Node, data: WorldData, ri: int, i: int) -> void:
	var n := (data.roads[ri]["x"] as PackedFloat32Array).size()
	i = posmod(i, n) if data.roads[ri]["closed"] else mini(i, n - 3)
	var p := data.road_point(ri, i)
	Game.world.call("prepare_area", p)
	Game.player_car.reset_to(Game.world.call("nearest_road_transform", p, data.road_dir(ri, i)))
	ap.set("_i", i)
