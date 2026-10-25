extends Node
## QA script: GPS route + minimap, world map, photo mode and an activity HUD, with screenshots.
## Run: Godot_console.exe --path . --resolution 1920x1080 -- --fresh --qa=script --script_path=res://tools/tests/ui_check.gd --out=qa_out/ui


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func run(qa: Node) -> void:
	var env := Game.environment as EnvironmentController
	env.set_time(15.0)
	env.time_frozen = true
	var am: Node = Game.activities
	# 1) GPS to the rally stage start
	var d: ActivityDef = am.call("find", "race_rally")
	Game.main.call("set_waypoint", d.position)
	await _frames(150)
	var nav: Node = Game.world.get_node("Navigator")
	print("[ui] route points=%d length=%.0f m" % [(nav.get("route_points") as PackedVector3Array).size(), float(nav.get("route_length"))])
	await qa.call("_shot", "ui_01_gps_minimap.png")
	# 2) world map
	var wm: Node = Game.main.get("world_map")
	wm.call("open")
	await _frames(20)
	await qa.call("_shot", "ui_02_world_map.png")
	wm.call("close")
	await _frames(10)
	# 3) photo mode with depth of field
	var pm: Node = Game.main.get("photo")
	pm.call("open")
	pm.set("_blur", 0.75)
	pm.set("_fov", 45.0)
	pm.call("_apply_dof")
	pm.call("_refresh_help")
	await _frames(40)
	await qa.call("_shot", "ui_03_photo_mode.png")
	pm.call("close")
	await _frames(10)
	# 4) activity HUD: drive into a speed zone with the autopilot
	var z: ActivityDef = am.call("find", "zone_02")
	Game.main.call("set_waypoint", Vector3.INF)
	am.call("teleport_to", z)
	await _frames(30)
	var ap: Node = Game.world.call("create_autopilot", Game.player_car)
	ap.set("max_speed_kmh", 120.0)
	ap.set("lane_offset", 1.75)
	var t := 0.0
	while t < 30.0 and am.get("active") == null:
		await get_tree().process_frame
		t += get_process_delta_time()
	await _frames(240)
	await qa.call("_shot", "ui_04_activity_hud.png")
	ap.queue_free()
	print("[ui] activity active=%s" % str(am.get("active").id if am.get("active") != null else "none"))
