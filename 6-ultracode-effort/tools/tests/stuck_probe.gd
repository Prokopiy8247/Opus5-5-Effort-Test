extends Node
## Vehicle diagnostics in the real world:
##   standing start with per-wheel logging:  -- --road=ring --s=8505[,8490] [--car=kestrel] [--damage=0.8]
##   barrier impacts at 100 km/h:            -- --wall=570 [--ang=20 --side=-1 --trace=1]
##   race start sequence (stop, grid, GO):   -- --race=rc_highmoor
##   Godot_console.exe --path <project> --resolution 1280x720 res://tools/tests/stuck_probe.tscn -- <mode args>

var main: Node


func _arg(key: String, default: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--" + key + "="):
			return a.substr(key.length() + 3)
	return default


func _ready() -> void:
	SaveGame.enabled = false
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(main)
	_run.call_deferred()


func _run() -> void:
	while main.get("is_loading"):
		await get_tree().process_frame
	Game.set_traffic_density(0.0)
	var w := Game.world as World
	var r := w.data.network.get_road(_arg("road", "ring"))
	(main.get("car_input") as CarInput).enabled = false
	if _arg("wall", "") != "":
		await _wall(r, _arg("wall", "560").to_float())
		get_tree().quit()
		return
	if _arg("race", "") != "":
		await _race(_arg("race", ""))
		get_tree().quit()
		return
	for sv in _arg("s", "8505").split(","):
		var s := sv.to_float()
		var ci := Game.find_car_index(_arg("car", "kestrel"))
		Game.spawn_car(maxi(ci, 0), false)
		main.call("teleport_to", {"position": r.surface_point(s, r.lane_offset(1) if r.traffic else 0.0), "forward": r.flat_tangent_at(s)})
		var t0 := Time.get_ticks_msec()
		while not w.is_ready_near() and Time.get_ticks_msec() - t0 < 20000:
			await get_tree().process_frame
		await get_tree().create_timer(1.0).timeout
		var car := Game.player_car
		car.damage = _arg("damage", "0").to_float()
		var p0 := car.global_position
		print("[probe] s=%.0f grade=%.3f start %s damage %.2f" % [s, r.tangent_at(s).y, str(p0.round()), car.damage])
		var t := 0.0
		var log_t := 0.0
		while t < 6.0:
			await get_tree().physics_frame
			car.in_throttle = 1.0
			car.in_brake = 0.0
			car.in_steer = 0.0
			t += 1.0 / 120.0
			log_t += 1.0 / 120.0
			if log_t >= 0.5:
				log_t = 0.0
				var ws := ""
				for wh in car.wheels:
					ws += " [%s c=%d om=%.1f tq=%.0f br=%.0f cap=%.0f]" % [wh.name if "name" in wh else "w", int(wh.contact), wh.omega, wh.drive_torque, wh.brake_force, wh.grip_cap]
				print("[probe] t=%.1f v=%.2f rpm=%.0f gear=%d tcs=%s dmg=%.2f%s" % [t, car.forward_speed, car.rpm, car.gear, str(car.tcs_active), car.damage, ws])
		print("[probe] moved %.1f m" % car.global_position.distance_to(p0))
	get_tree().quit()


func _race(id: String) -> void:
	var w := Game.world as World
	Game.set_traffic_density(0.6)
	Game.activities.call(&"teleport_to_activity", id, 80.0)
	var t0 := Time.get_ticks_msec()
	while not w.is_ready_near() and Time.get_ticks_msec() - t0 < 20000:
		await get_tree().process_frame
	await get_tree().create_timer(1.0).timeout
	var car := Game.player_car
	var t := 0.0
	var phase := 0
	var log_t := 0.0
	while t < 40.0:
		await get_tree().physics_frame
		t += 1.0 / 120.0
		car = Game.player_car
		var sid := str(Game.activities.call(&"get_session_id"))
		if phase == 0:
			# roll through the start gate at ~30 km/h, then brake
			car.in_throttle = 0.5 if car.speed_ms < 8.0 else 0.0
			car.in_brake = 0.0
			if sid != "":
				phase = 1
		elif phase == 1:
			car.in_throttle = 0.0
			car.in_brake = 1.0
			if car.freeze:
				phase = 2
		elif phase == 2:
			car.in_brake = 0.0
			car.in_throttle = 1.0
		log_t += 1.0 / 120.0
		if log_t >= 0.5:
			log_t = 0.0
			var ws := ""
			for wh in car.wheels:
				ws += " [c=%d om=%.1f tq=%.0f br=%.0f]" % [int(wh.contact), wh.omega, wh.drive_torque, wh.brake_force]
			print("[race] t=%.1f phase=%d session=%s freeze=%s v=%.2f rpm=%.0f gear=%d hb=%.2f pos=%s%s" % [t, phase, sid, str(car.freeze), car.forward_speed, car.rpm, car.gear, car.in_handbrake, str(car.global_position.round()), ws])


## Drive into the road edge (bridge parapet / rail) at 100 km/h with several angles; logs height and outcome.
func _wall(r: RoadNetwork.Road, s_hit: float) -> void:
	var w := Game.world as World
	var angs: Array = [10.0, 20.0, 35.0]
	var sides: Array = [-1.0, 1.0]
	if _arg("ang", "") != "":
		angs = [_arg("ang", "20").to_float()]
		sides = [_arg("side", "-1").to_float()]
	for ang_deg: float in angs:
		for side: float in sides:
			var s0 := s_hit - 25.0
			var fwd := r.flat_tangent_at(s0)
			var dir := fwd.rotated(Vector3.UP, -side * deg_to_rad(ang_deg))
			main.call("teleport_to", {"position": r.surface_point(s0, 0.0), "forward": dir})
			var t0 := Time.get_ticks_msec()
			while not w.is_ready_near() and Time.get_ticks_msec() - t0 < 20000:
				await get_tree().process_frame
			await get_tree().create_timer(0.5).timeout
			var car := Game.player_car
			car.linear_velocity = dir * 28.0
			var deck_y := r.point_at(s_hit).y
			var max_y := -INF
			var t := 0.0
			while t < 3.0:
				await get_tree().physics_frame
				car.in_throttle = 0.6
				car.in_steer = 0.0
				car.in_brake = 0.0
				t += 1.0 / 120.0
				max_y = maxf(max_y, car.global_position.y - deck_y)
				if _arg("trace", "") != "" and int(t * 120.0) % 15 == 0:
					var nn: Dictionary = w.data.network.nearest(car.global_position, 60.0)
					print("[trace] t=%.2f pos=%s s=%.1f lat=%.2f y-road=%.2f v=%.1f flag=%d" % [t, str(car.global_position), float(nn.get("s", -1.0)), float(nn.get("lateral", 99.0)), car.global_position.y - (nn["position"] as Vector3).y if not nn.is_empty() else 0.0, car.speed_ms, r.flag_at(float(nn.get("s", 0.0)))])
			var p := car.global_position
			var near: Dictionary = w.data.network.nearest(p, 50.0)
			print("[wall] angle %2.0f side %+.0f -> end y-deck %.2f max %.2f lateral %.1f speed %.1f up %.2f" % [ang_deg, side, p.y - deck_y, max_y, float(near.get("lateral", 99.0)), car.speed_ms, car.global_transform.basis.y.y])
