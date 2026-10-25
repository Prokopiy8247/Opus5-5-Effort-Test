extends Node
## QA debug: teleport to an activity and trace the start-trigger state.


func run(_qa: Node) -> void:
	var am: Node = Game.activities
	var id := String(Game.qa_args.get("act", "trial_loop"))
	var d: ActivityDef = am.call("find", id)
	am.call("teleport_to", d)
	for f in 60:
		await get_tree().physics_frame
	var ap: Node = Game.world.call("create_autopilot", Game.player_car)
	ap.set("max_speed_kmh", 80.0)
	ap.set("lane_offset", 1.75)
	for k in 30:
		for f in 30:
			await get_tree().physics_frame
		var p := Game.player_car.global_position
		var rel := p - d.position
		print("[dbg] %s along=%.1f lat=%.1f dy=%.1f prev=%s active=%s ap_dir=%d v=%.0f" % [id, rel.dot(d.heading),
			absf(rel.dot(d.heading.cross(Vector3.UP).normalized())), rel.y, str((am.get("_prev_side") as Dictionary).get(id, "-")),
			str(am.get("active").id if am.get("active") != null else "-"), int(ap.get("direction")), Game.player_car.speed_kmh])
		if am.get("active") != null:
			break
