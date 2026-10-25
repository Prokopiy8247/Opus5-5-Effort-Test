extends Node
## QA script: exercises every activity type in the running game with the road autopilot / scripted
## inputs and prints the recorded results (speed trap, speed zone, drift zone, road race, danger
## sign, festival board) plus screenshots.
## Run: Godot_console.exe --path . -- --fresh --qa=script --script_path=res://tools/tests/activities_check.gd --out=qa_out/act


func _wait(frames: int) -> void:
	for i in frames:
		await get_tree().physics_frame


func _drive(ap_speed: float, max_s: float, done: Callable) -> float:
	var ap: Node = Game.world.call("create_autopilot", Game.player_car)
	ap.set("max_speed_kmh", ap_speed)
	ap.set("lane_offset", 1.75)
	var t := 0.0
	var next_log := 5.0
	while t < max_s and not done.call():
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		if t > next_log:
			next_log += 5.0
			var am: Node = Game.activities
			var st: Dictionary = am.get("_st")
			var c := Game.player_car
			var act: ActivityDef = am.get("active")
			if act != null and act.points.size() > 0:
				var cpi: int = int(st.get("cp", 0))
				var tp: Vector3 = act.points[mini(cpi, act.points.size() - 1)]
				print("[act]   next cp %d at %s  dist=%.1f  dy=%.1f" % [cpi, str(tp.snapped(Vector3.ONE)), Vector2(c.global_position.x - tp.x, c.global_position.z - tp.z).length(), c.global_position.y - tp.y])
			print("[act]   t=%.0f pos=%s v=%.0f road=%d i=%d active=%s st=%s" % [t, str(c.global_position.snapped(Vector3.ONE)), c.speed_kmh,
				int(ap.get("road_index")), int(ap.get("_i")), str(am.get("active").id if am.get("active") != null else "-"),
				str({"cp": st.get("cp", -1), "off": snappedf(float(st.get("off_t", 0.0)), 0.1), "dist": int(st.get("dist", 0.0))})])
	ap.queue_free()
	return t


func _on_notify(title: String, body: String, _kind: String) -> void:
	print("[act]   notify: %s | %s" % [title, body])


func run(qa: Node) -> void:
	Game.notify.connect(_on_notify)
	var am: Node = Game.activities
	if am == null:
		print("[act] NO ACTIVITY MANAGER")
		return
	print("[act] loaded: ", am.call("console_command", ["list"]).split("\n")[0])
	Game.main.call("switch_car", Game.find_car_index("kaze"))
	await _wait(30)
	var shots := 0
	for id in ["race_valley"]:
		var d: ActivityDef = am.call("find", id)
		am.call("teleport_to", d)
		await _wait(60)
		var before: Dictionary = (am.call("get_bests") as Dictionary)["values"]
		var had := before.has(id)
		var spd := 170.0 if d.kind == ActivityDef.Kind.SPEED_TRAP else (60.0 if d.kind == ActivityDef.Kind.DRIFT_ZONE else 130.0)
		var t := await _drive(spd, 240.0, func() -> bool:
			var b: Dictionary = (am.call("get_bests") as Dictionary)["values"]
			return b.has(id) and (not had or b[id] != before.get(id)) and am.get("active") == null)
		var b2: Dictionary = (am.call("get_bests") as Dictionary)["values"]
		print("[act] %-12s %-12s result=%s after %.1f s  active=%s" % [id, d.kind_name(), str(b2.get(id, "none")), t, str(am.get("active") != null)])
		shots += 1
		await qa.call("_shot", "act_%02d_%s.png" % [shots, id])
	# danger sign: line up behind the ramp and floor it straight ahead
	var j: ActivityDef = am.call("find", "jump_01")
	am.call("teleport_to", j)
	await _wait(90)
	var car := Game.player_car
	var t2 := 0.0
	var got := false
	while t2 < 25.0:
		var to_ramp := j.prop_position - car.global_position
		to_ramp.y = 0.0
		var fwd := -car.global_transform.basis.z
		var err := fwd.signed_angle_to(to_ramp.normalized() if to_ramp.length() > 8.0 else j.heading, Vector3.UP)
		car.input_steer = clampf(-err * 2.0, -1.0, 1.0)
		car.input_throttle = 1.0 if car.speed_kmh < 150.0 else 0.0
		await get_tree().physics_frame
		t2 += get_physics_process_delta_time()
		if (am.call("get_bests") as Dictionary)["values"].has("jump_01"):
			got = true
			if t2 > 1.0:
				break
	car.input_throttle = 0.0
	car.input_steer = 0.0
	print("[act] jump_01 result=%s (%.1f s)" % [str((am.call("get_bests") as Dictionary)["values"].get("jump_01", "none")), t2])
	await qa.call("_shot", "act_jump.png")
	# festival board: drive into the closest board
	var boards: ActivityDef = am.call("find", "boards")
	var best_i := 0
	for i in boards.points.size():
		if boards.points[i].distance_to(car.global_position) < boards.points[best_i].distance_to(car.global_position):
			best_i = i
	var bp := boards.points[best_i]
	var h := Vector3(sin(boards.yaws[best_i]), 0, cos(boards.yaws[best_i]))
	var start := bp - h * 40.0
	Game.world.call("prepare_area", start)
	car.reset_to(Transform3D(Basis.looking_at(h, Vector3.UP), Vector3(start.x, float(Game.world.call("height_at", start.x, start.z)) + 0.8, start.z)))
	await _wait(40)
	var t3 := 0.0
	while t3 < 10.0 and (am.get("boards_smashed") as Dictionary).is_empty():
		var to_b := bp - car.global_position
		to_b.y = 0.0
		var err2 := (-car.global_transform.basis.z).signed_angle_to(to_b.normalized(), Vector3.UP)
		car.input_steer = clampf(-err2 * 2.0, -1.0, 1.0)
		car.input_throttle = 0.7
		await get_tree().physics_frame
		t3 += get_physics_process_delta_time()
	car.input_throttle = 0.0
	car.input_steer = 0.0
	print("[act] boards smashed=%d credits=%d" % [(am.get("boards_smashed") as Dictionary).size(), int(am.call("get_credits"))])
	print("[act] summary: ", am.call("console_command", ["list"]).split("\n")[0])
