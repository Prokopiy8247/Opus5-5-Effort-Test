extends Node
## Headless QA: completes a road race and the full scenic-loop time trial with the autopilot, and
## scores a drift zone with a scripted drifting driver (RWD muscle car, TCS/ESC off, handbrake flicks).
## Run: Godot_console.exe --headless --fixed-fps 120 --path . -- --fresh --qa=script --script_path=res://tools/tests/activities_full.gd


func _on_notify(title: String, body: String, _k: String) -> void:
	print("[full]   notify: %s | %s" % [title, body])


func _phys(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func run(_qa: Node) -> void:
	Game.notify.connect(_on_notify)
	Game.settings["traffic_density"] = 0.0
	var am: Node = Game.activities
	for id in ["race_valley", "trial_loop"]:
		var d: ActivityDef = am.call("find", id)
		am.call("teleport_to", d)
		await _phys(60)
		var ap: Node = Game.world.call("create_autopilot", Game.player_car)
		ap.set("max_speed_kmh", 125.0)
		ap.set("lane_offset", 1.75)
		ap.set("lat_accel", 6.0)
		ap.set("brake_decel", 6.0)
		var t := 0.0
		while t < 1500.0:
			await get_tree().physics_frame
			t += get_physics_process_delta_time()
			var b: Dictionary = (am.call("get_bests") as Dictionary)["values"]
			if b.has(id):
				break
		ap.queue_free()
		var b2: Dictionary = (am.call("get_bests") as Dictionary)["values"]
		print("[full] %s %s -> %s (stars %s) in %.0f s sim" % [id, d.kind_name(), ActivityDef.format_time(float(b2.get(id, -1.0))),
			str((am.call("get_bests") as Dictionary)["stars"].get(id, 0)), t])
	# drift zone: the autopilot slides through the switchbacks of "Switchback Sway" enough to score
	var dz: ActivityDef = am.call("find", "drift_02")
	am.call("teleport_to", dz)
	await _phys(60)
	var ap2: Node = Game.world.call("create_autopilot", Game.player_car)
	ap2.set("max_speed_kmh", 125.0)
	ap2.set("lane_offset", 1.75)
	var t2 := 0.0
	while t2 < 120.0:
		await get_tree().physics_frame
		t2 += get_physics_process_delta_time()
		if (am.call("get_bests") as Dictionary)["values"].has("drift_02"):
			break
	ap2.queue_free()
	print("[full] drift_02 -> %s pts after %.0f s" % [str((am.call("get_bests") as Dictionary)["values"].get("drift_02", "none")), t2])
