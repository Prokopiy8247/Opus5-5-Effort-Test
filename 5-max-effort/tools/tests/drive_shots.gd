extends Node
## QA script: drives a road with the autopilot and saves chase-camera screenshots at intervals.
## Args: --road=0 --from=8200 --speed=90 --shots=10 --every=6 [--time=13] [--car=kaze]
## Run: Godot_console.exe --path . -- --fresh --qa=script --script_path=res://tools/tests/drive_shots.gd --out=qa_out/drive


func run(qa: Node) -> void:
	var a := Game.qa_args
	var ri := int(a.get("road", "0"))
	var from := int(a.get("from", "0"))
	var env := Game.environment as EnvironmentController
	env.set_time(float(a.get("time", "13.0")))
	env.time_frozen = true
	if a.has("line"):
		Game.assists["line"] = true
	if a.has("car"):
		Game.main.call("switch_car", Game.find_car_index(String(a["car"])))
	var data: WorldData = Game.world.get("data")
	var p := data.road_point(ri, from)
	var h := data.road_dir(ri, from)
	Game.world.call("prepare_area", p)
	Game.player_car.reset_to(Game.world.call("nearest_road_transform", p, h))
	(Game.camera_rig as CameraRig).mode = int(a.get("cam", "0")) as CameraRig.Mode
	(Game.camera_rig as CameraRig).snap()
	for f in 30:
		await get_tree().physics_frame
	var ap: Node = Game.world.call("create_autopilot", Game.player_car)
	ap.set("max_speed_kmh", float(a.get("speed", "90")))
	ap.set("lane_offset", 1.75)
	var shots := int(a.get("shots", "10"))
	var every := float(a.get("every", "6"))
	var t := 0.0
	var next := float(a.get("start", "2.0"))
	var k := 0
	var min_y := 1e9
	var stuck := 0.0
	while k < shots:
		await get_tree().physics_frame
		var dt := get_physics_process_delta_time()
		t += dt
		var car := Game.player_car
		stuck = stuck + dt if car.speed_kmh < 5.0 else 0.0
		min_y = minf(min_y, car.global_position.y - data.height_at(car.global_position.x, car.global_position.z))
		if t >= next:
			next += every
			await qa.call("_shot", "drive_%02d.png" % k)
			print("[drive] shot %d t=%.0f pos=%s v=%.0f road_i=%d stuck=%.1f" % [k, t, str(car.global_position.snapped(Vector3.ONE)),
				car.speed_kmh, int(ap.get("_i")), stuck])
			k += 1
	print("[drive] distance=%.0f m min height above terrain=%.2f" % [float(ap.get("distance")), min_y])
	ap.queue_free()
