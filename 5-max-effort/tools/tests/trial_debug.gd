extends Node
## QA debug: run the loop time trial with the autopilot and trace the on-route check.


func run(_qa: Node) -> void:
	Game.settings["traffic_density"] = 0.0
	var am: Node = Game.activities
	var d: ActivityDef = am.call("find", "trial_loop")
	am.call("teleport_to", d)
	for f in 60:
		await get_tree().physics_frame
	var ap: Node = Game.world.call("create_autopilot", Game.player_car)
	ap.set("max_speed_kmh", 125.0)
	ap.set("lane_offset", 1.75)
	var data: WorldData = Game.world.get("data")
	var t := 0.0
	while t < 400.0:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		var st: Dictionary = am.get("_st")
		if float(st.get("away_t", 0.0)) > 0.0 and int(t * 120) % 24 == 0:
			var p := Game.player_car.global_position
			var nr := data.nearest_road(p.x, p.z, 2)
			print("[trial] t=%.1f away=%.1f pos=%s nearest=%s ap_road=%d ap_i=%d" % [t, float(st["away_t"]), str(p.snapped(Vector3.ONE)),
				str(nr), int(ap.get("road_index")), int(ap.get("_i"))])
		if am.get("active") != null:
			set_meta("started", true)
		if am.get("active") == null and has_meta("started"):
			print("[trial] ended at t=%.1f" % t)
			break
	ap.queue_free()
