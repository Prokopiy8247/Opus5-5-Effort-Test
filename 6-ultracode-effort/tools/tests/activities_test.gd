extends Node
## Real-game test of the road activities: instances the main scene, then for each activity teleports the
## player just before it and drives through with RoadFollower (handbrake pulses in drift zones, stop-to-start
## for races), printing every result and saving a screenshot of each gate.
##   Godot_console.exe --path . --resolution 1600x900 res://tools/tests/activities_test.tscn -- --only=st_,dj_
## Options: --only=<id prefixes> --skip=<id prefixes> --time-scale=<n> (races / time trials)
##          --flags=<n> (collect n Festival Flags) --shots=<dir> --drift-car=<car id>
##          --traffic=<0..1> (live traffic density for this run only; the saved setting is not touched)
##          --state-test=1 (race cleanup: density changed mid-race survives, fast-travel freeze hold survives)
##          --flagclear=1 [--flag-views=<flag ids>] [--reach=<flag ids>] (playtest3 s23: no trees / hedges / trunks in a
##          flag's pocket or on its approach lane, views, drives at the flag from the road and from 8 directions)
## Races log a traffic/rival monitor: rival lateral position, physics traffic closing on a rival, contacts, hazards.

const MAIN := preload("res://scenes/main.tscn")
const TrafficVehicle := preload("res://scripts/traffic/traffic_vehicle.gd")

var shot_dir := "res://qa_output/activities"
var results: Dictionary = {}
var updates: Dictionary = {}
var _main: Node
var _mon: Dictionary = {}
var _mon_seen: Dictionary = {}


func _ready() -> void:
	SaveGame.enabled = false
	SaveGame.pending = {}
	Game.discovered = {}
	Game.personal_bests = {}
	Game.credits = 0
	shot_dir = _arg("shots", shot_dir)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(shot_dir))
	Game.activity_finished.connect(_on_finished)
	Game.activity_update.connect(_on_update)
	_main = MAIN.instantiate()
	add_child(_main)
	_run.call_deferred()


static func _arg(key: String, default: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--" + key + "="):
			return a.substr(key.length() + 3)
	return default


func _on_finished(id: String, result: Dictionary) -> void:
	results[id] = result
	print("[test] RESULT %-20s %s" % [id, JSON.stringify(result)])


func _on_update(info: Dictionary) -> void:
	var id: String = info.get("id", "")
	var u: Dictionary = updates.get(id, {"count": 0})
	u["count"] = int(u["count"]) + 1
	u["last"] = "%s | %s | %.2f" % [info.get("primary", ""), info.get("secondary", ""), float(info.get("progress", -1.0))]
	updates[id] = u


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds, true, false, true).timeout


func _wait_streamed(max_s := 20.0) -> void:
	var t := 0.0
	await get_tree().process_frame
	var w := Game.world as World
	while t < max_s and w != null and (w.terrain.pending_count() > 0 or not w.roads.done):
		await get_tree().process_frame
		t += get_process_delta_time()
	await _wait(0.5)


func _shot(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := shot_dir.path_join(shot_name + ".png")
	img.save_png(path)
	print("[test] shot ", ProjectSettings.globalize_path(path))


func _selected(id: String) -> bool:
	var only := _arg("only", "")
	var skip := _arg("skip", "")
	if only != "":
		var ok := false
		for p in only.split(","):
			if id.begins_with(p):
				ok = true
		if not ok:
			return false
	for p in skip.split(",", false):
		if id.begins_with(p):
			return false
	return true


func _run() -> void:
	while Game.main == null or Game.main.is_loading:
		await get_tree().process_frame
	Game.main.car_input.process_mode = Node.PROCESS_MODE_DISABLED
	await _wait(1.0)
	if _arg("traffic", "") != "" and Game.traffic != null:
		Game.traffic.set_density(float(_arg("traffic", "0.6")))
		print("[test] traffic density %.2f (live only, setting %.2f)" % [Game.traffic.get_density(), float(Settings.get_value("traffic_density", 0.6))])
	var mgr: Node = Game.activities
	if mgr == null:
		print("[test] FAIL no activity manager")
		get_tree().quit(1)
		return
	var list: Array = mgr.get_activity_list()
	print("[test] %d activities, flags %s, source %s" % [list.size(), str(mgr.collectible_count()), mgr.events_source])
	var tested: PackedStringArray = []
	for ev: Dictionary in list:
		if not _selected(ev["id"]):
			continue
		tested.append(ev["id"])
		print("[test] ---- %s (%s) %s" % [ev["id"], ev["kind"], ev["title"]])
		await _drive_event(ev)
		Engine.time_scale = 1.0
	if _arg("cancel-test", "0") == "1":
		await _cancel_test(mgr)
	if _arg("state-test", "0") == "1":
		await _state_test(mgr)
	var nflags := int(_arg("flags", "0"))
	if nflags > 0:
		await _collect_flags(mgr, nflags)
	if _arg("flagclear", "0") == "1":
		await _flag_clear_test(mgr)
	print("[test] ======== SUMMARY")
	for id in tested:
		var r: Dictionary = results.get(id, {})
		var u: Dictionary = updates.get(id, {})
		if r.is_empty():
			print("[test] NO RESULT %-20s hud updates %d  last: %s" % [id, int(u.get("count", 0)), u.get("last", "")])
		else:
			print("[test] OK        %-20s %s  %s  medal=%s pb=%s  hud updates %d" % [id, r["score_text"], r.get("detail", ""),
				r["medal"], r["personal_best"], int(u.get("count", 0))])
	print("[test] credits %d  markers %d" % [Game.credits, (mgr.get_map_markers() as Array).size()])
	print("[test] DONE")
	get_tree().quit(0)


# ------------------------------------------------------------------ driving

func _launch(car: CarController, fwd: Vector3, kmh: float) -> void:
	var v := kmh / 3.6
	car.linear_velocity = fwd * v
	var radius := car.wheels[0].radius if not car.wheels.is_empty() else 0.33
	var best := 1
	for g in car.data.gear_ratios.size():
		var rpm := v / radius * car.data.gear_ratios[g] * car.data.final_drive * 60.0 / TAU
		if rpm < car.data.redline_rpm * 0.85:
			best = g + 1
			break
		best = g + 1
	car.gear = best
	for w in car.wheels:
		w.omega = v / w.radius


func _drive_event(ev: Dictionary) -> void:
	var kind: StringName = ev["kind"]
	var w := Game.world as World
	var road := w.data.network.get_road(ev["road"])
	var gates: PackedFloat32Array = ev["gates"]
	var th: PackedFloat32Array = ev["thresholds"]
	var d: int = ev["dir"] if int(ev["dir"]) != 0 else 1
	var approach := 260.0
	var start_kmh := 100.0
	var target_kmh := 140.0
	var timeout := 60.0
	match kind:
		&"speed_trap":
			target_kmh = th[1] + 12.0
			start_kmh = target_kmh * 0.9
			approach = 280.0
			timeout = 25.0
		&"speed_zone":
			target_kmh = th[2] + 15.0
			start_kmh = target_kmh * 0.7
			approach = 200.0
			timeout = 70.0
		&"drift":
			target_kmh = 80.0
			start_kmh = 60.0
			approach = 120.0
			timeout = 150.0
		&"jump":
			target_kmh = 140.0 if road.surface == &"asphalt" else 105.0
			start_kmh = 80.0
			approach = 220.0
			timeout = 35.0
		&"race", &"time_trial":
			target_kmh = 45.0
			start_kmh = 40.0
			approach = 70.0
			timeout = 900.0 if kind == &"race" else 1800.0
	if kind == &"drift":
		var car_id := _arg("drift-car", "sora_s2")
		var idx := Game.find_car_index(car_id)
		if idx >= 0 and Game.current_car_index != idx:
			Game.spawn_car(idx, true)
			await _wait(0.3)
	elif Game.current_car_index != 0:
		Game.spawn_car(0, true)
		await _wait(0.3)
	var s0 := gates[0] - d * approach
	if not road.loop and int(ev["dir"]) == 0 and (s0 < 40.0 or s0 > road.length - 40.0):
		# Bidirectional event too close to the road end: run it the other way (a zone from its other gate).
		d = -d
		if gates.size() > 1:
			gates = PackedFloat32Array([gates[1], gates[0]])
		s0 = gates[0] - d * approach
	if not road.loop:
		s0 = clampf(s0, 15.0, road.length - 15.0)
	var lane := road.lane_offset(1) if road.traffic else 0.0
	var fwd := road.flat_tangent_at(s0) * d
	Game.main.teleport_to({"position": road.surface_point(s0, lane * d), "forward": fwd})
	await _wait_streamed()
	var car := Game.player_car
	car.freeze = false
	if kind == &"drift":
		car.assist_stm = false
		car.assist_tcs = false
	await get_tree().physics_frame
	_launch(car, fwd, start_kmh)
	var f := RoadFollower.new()
	f.setup(road, s0, d, lane)
	f.target_speed = target_kmh / 3.6
	f.lat_accel = 6.0 if road.surface == &"asphalt" else 3.4
	var gate_pos := road.point_at(gates[0])
	var lip_pos := road.point_at(gates[1]) if kind == &"jump" else Vector3.INF
	var lip_shot := false
	var shot_done := false
	var t := 0.0
	var pulse_t := 0.0
	var phase := 0
	var ts := float(_arg("time-scale", "1"))
	var mgr: Node = Game.activities
	var grid_shot := false
	var stuck_t := 0.0
	var stuck_s := 0.0
	if kind == &"time_trial":
		if Game.traffic != null:
			Game.traffic.set_density(0.0)
		# main.gd's fall recovery fires inside the Ember Spur tunnel (car below terrain height) - see the
		# CORE CHANGE REQUEST in the activities report; off for this lap so the tunnel can be driven.
		if _arg("tunnel-fix", "1") == "1":
			Game.main.set_physics_process(false)
	while t < timeout:
		await get_tree().physics_frame
		car = Game.player_car
		var dt := get_physics_process_delta_time()
		t += dt
		if results.has(ev["id"]):
			break
		var sess: RefCounted = mgr.session
		if kind == &"race" or kind == &"time_trial":
			var state: int = int(sess.get("state")) if sess != null and mgr.get_session_id() == ev["id"] else 0
			if phase == 0 and state == 1:
				phase = 1
				f.target_speed = 0.0
			elif phase <= 1 and state == 2:
				phase = 2
				_monitor_grid(sess, road, d)
				if not grid_shot:
					grid_shot = true
					await _wait(0.4)
					await _shot("%s_grid" % ev["id"])
			elif phase == 2 and state == 3:
				phase = 3
				var res := w.data.network.nearest(car.global_position, 40.0, func(rr: RoadNetwork.Road) -> bool: return rr == road)
				f.setup(road, float(res.get("s", gates[0])), d, lane)
				f.target_speed = (230.0 if kind == &"race" else 170.0) / 3.6
				f.lat_accel = 6.5 if kind == &"race" else 5.5
				Engine.time_scale = ts
			elif phase == 3 and state == 0 and not results.has(ev["id"]):
				print("[test] race session ended without result")
				break
			if phase == 1 and state == 0 and car.speed_ms < 0.5 and t > 20.0:
				print("[test] race never armed")
				break
		# A stuck racer does what a player would do: reset to the road (R) and keep going.
		if phase == 3:
			stuck_t += dt
			if absf(f.s - stuck_s) > 6.0:
				stuck_s = f.s
				stuck_t = 0.0
			if stuck_t > 6.0:
				stuck_t = 0.0
				await _shot("%s_stuck_%d" % [ev["id"], int(t)])
				print("[test]   stuck at %s - reset onto the race road" % str(car.global_position.round()))
				var rs_s := f.s + d * 12.0
				mgr.place_player(road.surface_point(rs_s, lane * d), road.flat_tangent_at(rs_s) * d)
				await get_tree().physics_frame
				f.setup(road, rs_s, d, lane)
				continue
		if phase == 3 and sess != null:
			_monitor_race(sess, road, d, dt)
		f.drive(car, dt)
		if t > 4.0 and t - dt <= 4.0 and car.get_speed_kmh() < 20.0:
			await _shot("%s_stuck" % ev["id"])
			print("[test]   stuck at %s" % str(car.global_position.round()))
		if fmod(t, 15.0) < dt and sess != null and sess.get("opponents") != null:
			var opp: RefCounted = sess.get("opponents")
			var info := PackedStringArray()
			for k in (opp.get("followers") as Array).size():
				var rc: CarController = (opp.get("cars") as Array)[k]
				if not is_instance_valid(rc):
					# Finished rivals leave the race once they are out of sight.
					info.append("Rival_%d done" % (k + 1))
					continue
				info.append("%s s=%.0f %.0fkm/h lat %.1f swing %.1f" % [rc.name, (opp.get("followers") as Array)[k].s, rc.get_speed_kmh(),
					_rival_lateral(opp, k, road, d), (opp.get("_swing") as PackedFloat32Array)[k]])
			print("[test]   rivals: ", ", ".join(info))
		if fmod(t, 5.0) < dt:
			print("[test]   t=%4.0f s=%7.1f %5.1f km/h  gate0 %5.0f m  session '%s'  wheels %d" % [t, f.s, car.get_speed_kmh(),
				car.global_position.distance_to(gate_pos), mgr.get_session_id(), car.wheels_on_ground])
		if kind == &"drift":
			pulse_t = _drift_inputs(car, road, f, pulse_t, dt)
		if not shot_done and car.global_position.distance_to(gate_pos) < 40.0:
			shot_done = true
			await _shot(ev["id"])
		if not lip_shot and lip_pos != Vector3.INF and car.global_position.distance_to(lip_pos) < 30.0:
			lip_shot = true
			await _shot("%s_takeoff" % ev["id"])
		if not road.loop and f.finished:
			await _wait(1.0)
			break
	Engine.time_scale = 1.0
	Game.main.set_physics_process(true)
	if not _mon.is_empty():
		_monitor_report(ev["id"])
	if not results.has(ev["id"]):
		var u: Dictionary = updates.get(ev["id"], {})
		print("[test] %s: no result after %.0f s (session %s, last hud: %s)" % [ev["id"], t, mgr.get_session_id(), u.get("last", "-")])
		mgr.cancel_session("test timeout")
	if car != null and is_instance_valid(car):
		car.assist_stm = true
		car.assist_tcs = true


# ------------------------------------------------------------------ race / traffic monitor

func _rival_lateral(opp: RefCounted, k: int, road: RoadNetwork.Road, d: int) -> float:
	var rc: CarController = (opp.get("cars") as Array)[k]
	if not is_instance_valid(rc):
		return 0.0
	var s: float = (opp.get("followers") as Array)[k].s
	return (rc.global_position - road.point_at(s)).dot(road.right_at(s)) * d


func _monitor_grid(sess: RefCounted, road: RoadNetwork.Road, d: int) -> void:
	_mon = {"rival_s": 0.0, "oncoming_s": 0.0, "min_lat": INF, "approaches": 0, "unseen": 0, "contacts": 0,
		"near_hazards": 0, "min_kmh": INF, "hazards0": _hazard_count(), "run_t": 0.0}
	_mon_seen = {}
	var opp: RefCounted = sess.get("opponents")
	var car := Game.player_car
	var res := (Game.world as World).data.network.nearest(car.global_position, 40.0, func(rr: RoadNetwork.Road) -> bool: return rr == road)
	var lats := PackedStringArray(["player %.2f" % ((car.global_position - (res["position"] as Vector3)).dot(road.right_at(float(res["s"]))) * d)])
	if opp != null:
		for k in (opp.get("cars") as Array).size():
			var rc: CarController = (opp.get("cars") as Array)[k]
			if is_instance_valid(rc):
				lats.append("%s %.2f" % [rc.name, _rival_lateral(opp, k, road, d)])
	print("[test]   grid lateral (m, + = travel half, oncoming lane centre %.2f): %s" % [-road.lane_offset(1), ", ".join(lats)])


func _hazard_count() -> int:
	return int(Game.traffic.get_stats().get("hazards", 0)) if Game.traffic != null else 0


func _monitor_race(sess: RefCounted, road: RoadNetwork.Road, d: int, dt: float) -> void:
	var opp: RefCounted = sess.get("opponents")
	if opp == null or _mon.is_empty():
		return
	var tm: Node = Game.traffic
	_mon["run_t"] = float(_mon["run_t"]) + dt
	var cars: Array = opp.get("cars")
	for k in cars.size():
		var rc: CarController = cars[k]
		if not is_instance_valid(rc):
			continue
		var lat := _rival_lateral(opp, k, road, d)
		var lp: Vector3 = _mon_seen.get("p%d" % k, rc.global_position)
		if lp.distance_to(rc.global_position) > 4.0:
			print("[test]   %s moved %.1f m in one step (recovery reset) at s=%.0f" % [rc.name, lp.distance_to(rc.global_position), (opp.get("followers") as Array)[k].s])
		_mon_seen["p%d" % k] = rc.global_position
		if absf(lat) > 8.0 and float(_mon_seen.get("far%d" % k, -10.0)) < float(_mon["run_t"]) - 2.0:
			print("[test]   %s %.1f m off its follower line point (s=%.0f, %.0f km/h)" % [rc.name, lat, (opp.get("followers") as Array)[k].s, rc.get_speed_kmh()])
			_mon_seen["far%d" % k] = _mon["run_t"]
		_mon["rival_s"] = float(_mon["rival_s"]) + dt
		_mon["min_lat"] = minf(float(_mon["min_lat"]), lat)
		if lat < 0.0:
			_mon["oncoming_s"] = float(_mon["oncoming_s"]) + dt
		if float(_mon["run_t"]) > 10.0:
			_mon["min_kmh"] = minf(float(_mon["min_kmh"]), rc.get_speed_kmh())
		for b in rc.get_colliding_bodies():
			if b is CarController and b.get_parent() != null and b.get_parent().name == "Cars":
				var key := "c%s_%s" % [rc.name, b.name]
				if float(_mon_seen.get(key, -10.0)) < float(_mon["run_t"]) - 2.0:
					_mon["contacts"] = int(_mon["contacts"]) + 1
					print("[test]   CONTACT %s with traffic %s at %.0f km/h" % [rc.name, b.name, rc.get_speed_kmh()])
				_mon_seen[key] = _mon["run_t"]
		if tm == null:
			continue
		for v: TrafficVehicle in tm.vehicles:
			var rel := rc.global_position - v.position
			rel.y = 0.0
			var dist := rel.length()
			if v.hazard and dist < 12.0 and not _mon_seen.has("h%d" % v.uid):
				_mon_seen["h%d" % v.uid] = true
				_mon["near_hazards"] = int(_mon["near_hazards"]) + 1
				print("[test]   HAZARD traffic #%d %s %.1f m from %s" % [v.uid, v.data.id, dist, rc.name])
			if v.hazard or dist > 30.0:
				continue
			var fwd := Vector3(v.heading.x, 0.0, v.heading.z).normalized()
			var fd := rel.dot(fwd)
			var closing := v.speed - rc.linear_velocity.dot(fwd)
			if fd <= 3.0 or closing <= 2.0:
				continue
			# A traffic car with this rival on its planned path ahead (body overlapping its lane) and closing on it.
			var q: Vector3 = v.path_point(fd)
			var side := Vector2(rc.global_position.x - q.x, rc.global_position.z - q.z).length()
			var lane_half := (v.lane.road.width - 0.6) / float(v.lane.road.lanes * 4)
			if side < lane_half + rc.data.body_size.x * 0.5:
				var key2 := "a%d_%s" % [v.uid, rc.name]
				if not _mon_seen.has(key2):
					_mon_seen[key2] = true
					_mon["approaches"] = int(_mon["approaches"]) + 1
					var blind: bool = v.lead_gap == INF
					if blind:
						_mon["unseen"] = int(_mon["unseen"]) + 1
					print("[test]   traffic #%d %s %s %.0f km/h has %s %.1f m ahead on its path (off path %.2f, closing %.1f m/s, rival lat %.2f): lead_gap %s v_target %.0f km/h%s" % [
						v.uid, v.data.id, "PHYS" if v.mode == TrafficVehicle.Mode.PHYSICS else "kin", v.speed * 3.6, rc.name, fd, side, closing, lat,
						("%.1f" % v.lead_gap) if not blind else "inf", v.v_target * 3.6, "  <-- NOT SEEN" if blind else ""])


func _monitor_report(id: String) -> void:
	var rs := maxf(float(_mon["rival_s"]), 0.001)
	print("[test] MONITOR %s: rival-seconds %.0f, in oncoming half %.1f s (%.1f%%), min rival lateral %.2f m, traffic approaches %d (not seen %d), rival-traffic contacts %d, hazards near rivals %d, traffic hazards %d, min rival speed after 10 s %.0f km/h, traffic stats %s" % [
		id, rs, float(_mon["oncoming_s"]), 100.0 * float(_mon["oncoming_s"]) / rs, float(_mon["min_lat"]), int(_mon["approaches"]), int(_mon["unseen"]),
		int(_mon["contacts"]), int(_mon["near_hazards"]), _hazard_count() - int(_mon["hazards0"]), float(_mon["min_kmh"]),
		JSON.stringify(Game.traffic.get_stats() if Game.traffic != null else {})])
	if Game.traffic != null and Game.traffic.has_method("effective_density"):
		print("[test]   traffic density after the race: setting %.2f, effective %.2f" % [Game.traffic.get_density(), Game.traffic.effective_density()])
	_mon = {}


# ------------------------------------------------------------------ race cleanup ownership

## 1. Traffic: the race caps the density on the grid; a density picked during the race (the live half of
##    Game.set_traffic_density, as the console 'traffic off' does) must survive the race end.
## 2. Fast travel (ui_root.fast_travel) during COUNTDOWN and RUNNING: the race cancel must not release the
##    freeze hold that waits for terrain streaming.
func _state_test(mgr: Node) -> void:
	var tm: Node = Game.traffic
	var ev: Dictionary = {}
	for e: Dictionary in mgr.get_activity_list():
		if e["id"] == _arg("state-race", "rc_coast"):
			ev = e
	if ev.is_empty() or tm == null:
		print("[test] state test: no race / traffic")
		return
	var dens0: float = tm.get_density()
	tm.set_density(0.6)
	print("[test] ---- state test on %s" % ev["id"])
	if not await _race_to_state(mgr, ev, 2):
		return
	var on_grid := "setting %.2f effective %.2f" % [tm.get_density(), _effective_density()]
	if not await _race_to_state(mgr, ev, 3):
		return
	tm.set_density(0.0)
	mgr.cancel_session("state test")
	await _wait(0.2)
	var ok: bool = is_zero_approx(tm.get_density()) and is_zero_approx(_effective_density())
	print("[test] density: on grid %s; set 0.00 mid-race; after cancel setting %.2f effective %.2f active %d -> %s" % [on_grid,
		tm.get_density(), _effective_density(), tm.active_count(), "OK" if ok else "FAIL"])
	tm.set_density(0.6)
	# A cancel on the grid (countdown, car not moved) must release the race's own freeze.
	if not await _race_to_state(mgr, ev, 2):
		return
	mgr.cancel_session("state test grid cancel")
	await get_tree().physics_frame
	print("[test] cancel during countdown on the grid: car frozen %s -> %s" % [Game.player_car.freeze, "OK" if not Game.player_car.freeze else "FAIL"])
	for st: int in [2, 3]:
		if not await _race_to_state(mgr, ev, st):
			return
		await _fast_travel_check(mgr, "countdown" if st == 2 else "running")
	tm.set_density(dens0)
	print("[test] state test done (live density back to %.2f, setting %.2f untouched)" % [tm.get_density(), float(Settings.get_value("traffic_density", 0.6))])


func _effective_density() -> float:
	var tm: Node = Game.traffic
	return float(tm.call("effective_density")) if tm.has_method("effective_density") else float(tm.get_density())


## Drives up to the race start and waits for the session state (2 countdown, 3 running).
func _race_to_state(mgr: Node, ev: Dictionary, want: int) -> bool:
	var act: RefCounted = mgr.by_id[ev["id"]]
	if mgr.get_session_id() != ev["id"]:
		while float(act.get("cooldown")) > 0.0:
			await get_tree().physics_frame
		var road := (Game.world as World).data.network.get_road(ev["road"])
		var d: int = ev["dir"] if int(ev["dir"]) != 0 else 1
		var s0: float = ev["gates"][0] - d * 70.0
		var lane := road.lane_offset(1)
		Game.main.teleport_to({"position": road.surface_point(s0, lane * d), "forward": road.flat_tangent_at(s0) * d})
		await _wait_streamed()
		Game.player_car.freeze = false
		await get_tree().physics_frame
		_launch(Game.player_car, road.flat_tangent_at(s0) * d, 40.0)
		var f := RoadFollower.new()
		f.setup(road, s0, d, lane)
		f.target_speed = 45.0 / 3.6
		var t := 0.0
		while t < 40.0 and int(act.get("state")) < want:
			await get_tree().physics_frame
			t += get_physics_process_delta_time()
			if int(act.get("state")) >= 1:
				f.target_speed = 0.0
			f.drive(Game.player_car, get_physics_process_delta_time())
	var t2 := 0.0
	while t2 < 10.0 and int(act.get("state")) < want:
		await get_tree().physics_frame
		t2 += get_physics_process_delta_time()
	var ok: bool = int(act.get("state")) == want and mgr.get_session_id() == ev["id"]
	print("[test]   %s state %d (wanted %d) car frozen %s" % [ev["id"], int(act.get("state")), want, Game.player_car.freeze])
	return ok


func _fast_travel_check(mgr: Node, label: String) -> void:
	var ui: Node = Game.hud
	var car := Game.player_car
	var start := car.global_position
	ui.call("fast_travel", "Sunward Festival")
	var t := 0.0
	var tp_t := -1.0
	var ready_t := -1.0
	var unfrozen_t := -1.0
	var cancelled := false
	while t < 15.0:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		car = Game.player_car
		if tp_t < 0.0:
			if car.global_position.distance_to(start) > 60.0:
				tp_t = t
			continue
		if mgr.get_session_id() == "":
			cancelled = true
		if ready_t < 0.0 and (Game.world as World).is_ready_near():
			ready_t = t - tp_t
		if unfrozen_t < 0.0 and not car.freeze:
			unfrozen_t = t - tp_t
			print("[test]   %s: car unfrozen %.3f s after the teleport (session '%s', terrain ready %s, fade %.2f)" % [label, unfrozen_t,
				mgr.get_session_id(), (Game.world as World).is_ready_near(), (ui.get("_fade") as Control).modulate.a])
		if not bool(ui.get("_travel_busy")):
			break
	var ok := tp_t >= 0.0 and cancelled and ready_t >= 0.0 and unfrozen_t >= ready_t + 0.2
	print("[test] fast travel during %s: teleported %s, race cancelled %s, terrain ready %.3f s, car unfrozen %.3f s after teleport -> %s" % [
		label, tp_t >= 0.0, cancelled, ready_t, unfrozen_t, "OK" if ok else "FAIL"])
	await _wait(0.5)


## Handbrake flicks into sharp corners keep the car sideways (STM/TCS are off for the drift car); the
## RoadFollower steering counter-steers, throttle is cut when the slide gets too big.
func _drift_inputs(car: CarController, road: RoadNetwork.Road, f: RoadFollower, pulse_t: float, dt: float) -> float:
	var a := road.flat_tangent_at(f.s)
	var b := road.flat_tangent_at(f.s + f.dir * 25.0)
	var turn := absf(a.signed_angle_to(b, Vector3.UP))
	var kmh := car.get_speed_kmh()
	pulse_t += dt
	car.in_brake = 0.0
	car.in_throttle = 0.9 if kmh < 70.0 else 0.45
	if turn > 0.18 and turn < 0.6 and kmh > 45.0:
		if pulse_t > 1.8:
			pulse_t = 0.0
		if pulse_t < 0.18:
			car.in_handbrake = 1.0
	if absf(car.body_slip_deg) > 45.0:
		car.in_throttle = 0.15
	return pulse_t


## Starts a speed zone, then teleports away (must cancel); starts it again, then switches car (must cancel).
func _cancel_test(mgr: Node) -> void:
	var list: Array = mgr.get_activity_list()
	var ev: Dictionary = {}
	for e: Dictionary in list:
		if e["kind"] == &"speed_zone" and e["road"] == "expressway":
			ev = e
	if ev.is_empty():
		print("[test] cancel test: no expressway speed zone")
		return
	for mode: String in ["teleport", "car switch"]:
		var w := Game.world as World
		var road := w.data.network.get_road(ev["road"])
		var s0: float = ev["gates"][0] - 120.0
		Game.main.teleport_to({"position": road.surface_point(s0, road.lane_offset(1)), "forward": road.flat_tangent_at(s0)})
		await _wait_streamed()
		await _wait(3.2)
		var f := RoadFollower.new()
		f.setup(road, s0, 1, road.lane_offset(1))
		f.target_speed = 150.0 / 3.6
		_launch(Game.player_car, road.flat_tangent_at(s0), 120.0)
		var t := 0.0
		while t < 25.0 and mgr.get_session_id() != ev["id"]:
			await get_tree().physics_frame
			t += get_physics_process_delta_time()
			f.drive(Game.player_car, get_physics_process_delta_time())
		var started: bool = mgr.get_session_id() == ev["id"]
		print("[test]   %s: car %s at %.0f km/h, %.0f m from the zone start, session '%s'" % [mode, Game.player_car.data.id,
			Game.player_car.get_speed_kmh(), Game.player_car.global_position.distance_to(road.point_at(ev["gates"][0])), mgr.get_session_id()])
		for i in 120:
			await get_tree().physics_frame
			f.drive(Game.player_car, get_physics_process_delta_time())
		if mode == "teleport":
			Game.teleport("Sunward Festival")
		else:
			Game.spawn_car(1, true)
		await _wait(0.5)
		var ok: bool = started and mgr.get_session_id() == ""
		print("[test] cancel on %s: started=%s session_after='%s' -> %s" % [mode, started, mgr.get_session_id(), "OK" if ok else "FAIL"])
		if Game.current_car_index != 0:
			Game.spawn_car(0, true)
			await _wait(0.3)


func _collect_flags(mgr: Node, n: int) -> void:
	var flags: Array = mgr.get_collectibles()
	var w := Game.world as World
	var done := 0
	for fl: Dictionary in flags:
		if done >= n:
			break
		if fl["collected"]:
			continue
		var target: Vector3 = fl["position"]
		var rp: Dictionary = w.nearest_road_point(target)
		var start: Vector3 = rp["position"]
		if start.distance_to(target) > 120.0:
			continue
		print("[test] ---- flag %s (%s)" % [fl["id"], fl["name"]])
		var away := start - target
		away.y = 0.0
		start = target + away.normalized() * 30.0
		start.y = w.height_at(start.x, start.z) + 0.3
		var to := (target - start)
		to.y = 0.0
		Game.main.teleport_to({"position": start, "forward": to.normalized()})
		await _wait_streamed()
		await _wait(3.5)
		var car := Game.player_car
		car.freeze = false
		var t := 0.0
		var shot := false
		while t < 25.0 and not results.has(fl["id"]):
			await get_tree().physics_frame
			t += get_physics_process_delta_time()
			car = Game.player_car
			var rel := target - car.global_position
			rel.y = 0.0
			var fwd := -car.global_transform.basis.z
			fwd.y = 0.0
			var ang := fwd.normalized().signed_angle_to(rel.normalized(), Vector3.UP)
			car.in_steer = clampf(-ang * 2.0, -1.0, 1.0)
			car.in_throttle = 0.55 if car.get_speed_kmh() < 35.0 else 0.0
			car.in_brake = 0.0
			if not shot and rel.length() < 16.0:
				shot = true
				await _shot(String(fl["id"]))
		done += 1
		if not results.has(fl["id"]):
			print("[test] %s: not collected" % fl["id"])


# ------------------------------------------------------------------ festival flags vs world dressing (playtest3 s23)

const Rules := preload("res://scripts/world/dressing_rules.gd")
const Planner := preload("res://scripts/activities/event_planner.gd")
const Collectibles := preload("res://scripts/activities/collectibles.gd")


## Every flag: its pocket and approach lane are in the exclusion list Dressing built its context from (registered
## in time), no tree / hedge / trunk collider in the pocket, no trunk on the approach lane (the real chunks are
## rebuilt with the game's dressing context). Then views of --flag-views flags and a drive from the road to each
## flag along its approach plus from 8 directions 22 m out (--reach=<ids>).
func _flag_clear_test(mgr: Node) -> void:
	var dressing: Node = Game.get_meta(&"dressing") if Game.has_meta(&"dressing") else null
	var t := 0.0
	while t < 20.0 and (dressing == null or dressing.get("ctx") == null):
		await get_tree().process_frame
		t += get_process_delta_time()
	if dressing == null or dressing.get("ctx") == null:
		print("[test] FLAGCLEAR FAIL no dressing context")
		return
	var ctx: RefCounted = dressing.get("ctx")
	var excl: Array = ctx.get("excl")
	var w := Game.world as World
	var bad := 0
	var cache: Dictionary = {}
	for fl: Dictionary in mgr.get_collectibles():
		var p: Vector3 = fl["position"]
		var pocket := false
		for e: Vector4 in excl:
			if is_equal_approx(e.x, p.x) and is_equal_approx(e.y, p.z) and e.w >= Collectibles.POCKET_TREES - 0.01:
				pocket = true
		var line := Planner.approach(w.data, p)
		var near := _dressing_near(ctx, cache, p, Collectibles.POCKET_TREES + 6.0)
		var lane_trunk := INF
		if line.size() == 2:
			for c: Vector4 in _dressing_near(ctx, cache, line[0].lerp(line[1], 0.5), line[0].distance_to(line[1]) * 0.5 + 8.0)["trunks"]:
				lane_trunk = minf(lane_trunk, _seg_dist(Vector2(c.x, c.z), Vector2(line[0].x, line[0].z), Vector2(line[1].x, line[1].z)) - c.w)
		var ok: bool = pocket and float(near["tree"]) >= Collectibles.POCKET_TREES - 0.5 and float(near["hedge"]) >= Collectibles.POCKET_TREES - 2.5 \
			and float(near["trunk"]) >= Collectibles.POCKET_TREES - 1.0 and (line.size() < 2 or lane_trunk >= Collectibles.LANE_TREES - 1.0)
		if not ok:
			bad += 1
		print("[test] FLAGCLEAR %-20s %s pocket registered %s, nearest tree %.1f m, hedge %.1f m, trunk collider %.1f m, rock/cactus %.1f m, approach %s, closest trunk to the approach line %.1f m" % [
			fl["id"], "ok " if ok else "BAD", pocket, near["tree"], near["hedge"], near["trunk"], near["small"],
			"%.0f m" % line[0].distance_to(line[1]) if line.size() == 2 else "none", lane_trunk])
	print("[test] FLAGCLEAR %s: %d of %d flags with dressing inside the pocket / on the approach; dressing context holds %d exclusions" % [
		"PASS" if bad == 0 else "FAIL", bad, (mgr.get_collectibles() as Array).size(), excl.size()])
	for id: String in _arg("flag-views", "").split(",", false):
		await _flag_views(mgr, id)
	for id2: String in _arg("reach", "").split(",", false):
		await _flag_reach(mgr, id2)


## Nearest tree / hedge instance, trunk collider and small collider (rock, cactus) of the rebuilt dressing chunks
## around p (horizontal distances), plus the trunk colliders as Vector4(x, y, z, radius).
func _dressing_near(ctx: RefCounted, cache: Dictionary, p: Vector3, radius: float) -> Dictionary:
	var res := {"tree": INF, "hedge": INF, "trunk": INF, "small": INF, "trunks": []}
	var k0 := Vector2i(floori((p.x - radius + Rules.HALF) / Rules.CHUNK), floori((p.z - radius + Rules.HALF) / Rules.CHUNK))
	var k1 := Vector2i(floori((p.x + radius + Rules.HALF) / Rules.CHUNK), floori((p.z + radius + Rules.HALF) / Rules.CHUNK))
	for kx in range(k0.x, k1.x + 1):
		for kz in range(k0.y, k1.y + 1):
			var key := Vector2i(kx, kz)
			if not cache.has(key):
				cache[key] = Rules.build_chunk(ctx, key)
			var ch: Dictionary = cache[key]
			var org := Vector3(-Rules.HALF + kx * Rules.CHUNK, 0.0, -Rules.HALF + kz * Rules.CHUNK)
			var groups: Dictionary = ch["groups"]
			for g: String in groups:
				var kind := "tree" if g.begins_with("tree|") else ("hedge" if g.begins_with("hedge|") else "")
				if kind == "":
					continue
				var arr: PackedFloat32Array = groups[g]
				for i in range(0, arr.size(), Rules.STRIDE):
					var d := Vector2(org.x + arr[i + 3] - p.x, org.z + arr[i + 11] - p.z).length()
					res[kind] = minf(float(res[kind]), d)
			var col: PackedFloat32Array = ch["colliders"]
			for j in range(0, col.size(), 6):
				var cd := Vector2(col[j] - p.x, col[j + 2] - p.z).length() - col[j + 3]
				if col[j + 5] == 0.0 and col[j + 4] > 5.0:
					res["trunk"] = minf(float(res["trunk"]), cd)
					(res["trunks"] as Array).append(Vector4(col[j], col[j + 1], col[j + 2], col[j + 3]))
				else:
					res["small"] = minf(float(res["small"]), cd)
	return res


static func _seg_dist(q: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var t := clampf((q - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
	return q.distance_to(a + ab * t)


func _flag_by_id(mgr: Node, id: String) -> Dictionary:
	for fl: Dictionary in mgr.get_collectibles():
		if fl["id"] == id:
			return fl
	return {}


## Ground view from 13 m (two sides) and an aerial view of a flag.
func _flag_views(mgr: Node, id: String) -> void:
	var fl := _flag_by_id(mgr, id)
	if fl.is_empty():
		return
	var w := Game.world as World
	var p: Vector3 = fl["position"]
	var line := Planner.approach(w.data, p)
	var away := (line[1] - p) if line.size() == 2 else Vector3(1, 0, 0)
	away.y = 0.0
	away = away.normalized()
	# Out of the pickup sphere (a car standing by the flag would collect it before the views).
	Game.main.teleport_to({"position": p + away * ((p.distance_to(line[1]) if line.size() == 2 else 0.0) + 14.0), "forward": -away})
	await _wait_streamed()
	await _wait(2.5)
	var cam := Camera3D.new()
	add_child(cam)
	var views := [["ground_road_side", away, 13.0, 1.8], ["ground_far_side", -away.rotated(Vector3.UP, 0.6), 13.0, 1.8], ["aerial", away.rotated(Vector3.UP, 0.3), 22.0, 26.0]]
	for vw: Array in views:
		var dirv: Vector3 = vw[1]
		var cp := p + dirv * float(vw[2])
		cp.y = maxf(w.height_at(cp.x, cp.z), p.y) + float(vw[3])
		cam.global_position = cp
		cam.look_at(p + Vector3.UP * 2.0)
		cam.fov = 60.0
		cam.make_current()
		await get_tree().process_frame
		await get_tree().process_frame
		await _shot("flag_%s_%s" % [id, vw[0]])
	Game.camera_rig.camera.make_current()
	cam.queue_free()


## Drives at a flag with the real CarInput (Input actions): from the road end of its approach, then from 8
## directions 22 m out at ~25 km/h (QA's reach test). Prints how many attempts collected it.
func _flag_reach(mgr: Node, id: String) -> void:
	var fl := _flag_by_id(mgr, id)
	if fl.is_empty():
		return
	var w := Game.world as World
	var p: Vector3 = fl["position"]
	var line := Planner.approach(w.data, p)
	var starts: Array = []
	if line.size() == 2:
		var a := line[1] - p
		a.y = 0.0
		starts.append(["road", p + a.normalized() * (a.length() + 6.0)])
	for k in 8:
		var ang := TAU * k / 8.0
		starts.append(["%d" % (k * 45), p + Vector3(cos(ang), 0.0, sin(ang)) * 22.0])
	var got := 0
	var log := PackedStringArray()
	for st: Array in starts:
		var sp: Vector3 = st[1]
		sp.y = w.height_at(sp.x, sp.z) + 0.4
		var to := p - sp
		to.y = 0.0
		Game.main.teleport_to({"position": sp, "forward": to.normalized()})
		await _wait_streamed()
		await _wait(1.0)
		# Re-arm the flag only once the car is away from it (a pickup sphere re-enabled around a car that still
		# stands in it would fire at once).
		Game.discovered.erase("festival_flags")
		mgr.collectibles.call("refresh")
		await _wait(0.5)
		results.erase(fl["id"])
		Game.main.car_input.process_mode = Node.PROCESS_MODE_INHERIT
		Game.main.car_input.enabled = true
		var t := 0.0
		var closest := INF
		while t < 14.0 and not results.has(fl["id"]):
			await get_tree().physics_frame
			t += get_physics_process_delta_time()
			var car := Game.player_car
			var rel := p - car.global_position
			rel.y = 0.0
			closest = minf(closest, rel.length())
			var fwd := -car.global_transform.basis.z
			fwd.y = 0.0
			var ang2 := fwd.normalized().signed_angle_to(rel.normalized(), Vector3.UP)
			Input.action_release("steer_left")
			Input.action_release("steer_right")
			if ang2 > 0.08:
				Input.action_press("steer_left", clampf(ang2 * 2.0, 0.2, 1.0))
			elif ang2 < -0.08:
				Input.action_press("steer_right", clampf(-ang2 * 2.0, 0.2, 1.0))
			if car.get_speed_kmh() < 25.0:
				Input.action_press("accelerate")
			else:
				Input.action_release("accelerate")
		for act: String in ["steer_left", "steer_right", "accelerate"]:
			Input.action_release(act)
		Game.main.car_input.enabled = false
		Game.main.car_input.process_mode = Node.PROCESS_MODE_DISABLED
		var ok := results.has(fl["id"])
		if ok:
			got += 1
		log.append("%s:%s" % [st[0], "ok" if ok else "%.0fm" % closest])
		if not ok:
			var pc := Game.player_car
			var hits := PackedStringArray()
			for b in pc.get_colliding_bodies():
				hits.append("%s%s" % [b.name, " (%s)" % b.get_parent().name if b.get_parent() != null else ""])
			var idx := (mgr.collectibles.get("flags") as Array).map(func(d: Resource) -> String: return d.id).find(fl["id"])
			var area: Area3D = (mgr.collectibles.get("_areas") as Array)[idx]
			print("[test]   %s start %s: stopped at %s (%.1f m from the flag, %.0f km/h), touching %s; pickup monitoring %s, scale %.2f, collected %s, car y %.1f flag y %.1f" % [id, st[0],
				str(pc.global_position.snappedf(0.1)), Vector2(p.x - pc.global_position.x, p.z - pc.global_position.z).length(), pc.get_speed_kmh(), ", ".join(hits),
				area.monitoring, area.get_parent().scale.x, bool(mgr.collectibles.call("is_collected", fl["id"])), pc.global_position.y, p.y])
			if st[0] == "road":
				await _shot("flag_%s_reach_road_fail" % id)
	print("[test] REACH %s: collected from %d of %d starts (%s)" % [id, got, starts.size(), ", ".join(log)])
