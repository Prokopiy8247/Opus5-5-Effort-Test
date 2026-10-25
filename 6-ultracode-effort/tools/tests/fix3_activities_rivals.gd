extends Node
## Activities regression test (fix3, playtest round 2) in the real game (main scene):
##   Godot_console.exe --path . --audio-driver Dummy --resolution 1600x900 res://tools/tests/fix3_activities_rivals.tscn -- --scenario=<s>
## Scenarios (each prints "[f3] PASS ..." / "[f3] FAIL ..." lines and a SUMMARY; log + screenshots under
## qa_output/fix3_activities/, --tag=<name> prefixes the files; the traffic density is set live only and restored):
##   race     --id=rc_highmoor|rc_coast --traffic=0.6 --kmh=<player target, 0 = 90 % of top speed> --max=<s>
##            full race (the test driver follows its lane, overtakes slow traffic, never drives into rivals): rival
##            contacts with the player, one-frame jumps (other than counted recoveries), time off the route, below-
##            ground / underwater frames, far rivals without terrain colliders, camera inside a rival, every rival
##            finished or past 75 % when the race ends. --stop=<s> brakes the player to a stop <s> seconds after GO
##            and holds it --hold=<s> (rivals must pass it, never rear-end / stack / teleport). --rivalcam=<s> takes a
##            screenshot behind a rival every <s> seconds; --debug=1 logs every rival's line, limit and inputs each second.
##   tunnel   rival driven through the Ember Spur tunnel far from the player + a far rival dropped on the grass.
##   overlay  map (M), garage (Tab), debug (F2), console (`) opened mid-race with real key events: clock, rivals and
##            the player car must resume exactly.
##   rewind   rewind_blocked() in countdown / race, rewind key in a race and in a speed zone (on_player_rewind).
##   units    imperial HUD texts (jump approach, speed zone, race prompt) and the speed-zone medal at the shown value
##            (--aim=<km/h> zone average for the real run; 101.2 lands in the 61.5-62.1 mph window).
##   jump     jump result speed = takeoff speed when the player lifts before the ramp; a rewind ends an armed jump.
##   spot     debug: rival --k placed at --s0 at --kmh on the race road, logged at 10 Hz for --secs.
## Round 3 (playtest3 s19-s21):
##   standoff     --runs=4 --secs=35 --traffic=1.0: repeated Highmoor starts; rivals never stand nose to nose with
##                oncoming traffic, are back in their own half before it arrives, traffic never freezes facing them.
##   facing       deterministic stand-off (--lat, --type, --gap, --near=1): rival across the centre line, an oncoming
##                traffic car in front of it; both must get past each other without a recovery.
##   nightlights  22:30 race: every rival has lit head lamps (beams + lenses) and tail lamps on the grid and racing;
##                clear noon: lamps off.
##   release      --how=finish|cancel: after the race the rivals cruise on and only leave out of the camera's view.

const MAIN := preload("res://scenes/main.tscn")
const KEY_REWIND := 4194308

var out_dir := "res://qa_output/fix3_activities"
var _log: FileAccess
var _fails := 0
var _notes: Array[String] = []
var _impacts: Array[String] = []
var _hud: Dictionary = {}
var _results: Dictionary = {}
var _player_lane := 0.0


func _ready() -> void:
	SaveGame.enabled = false
	Game.personal_bests = {}
	Game.discovered = {}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	_log = FileAccess.open(out_dir.path_join("%s_%s.log" % [_arg("scenario", "race"), _arg("tag", "run")]), FileAccess.WRITE)
	Game.notification.connect(func(t: String, b: String, k: StringName) -> void:
		if k != &"discovery":
			_notes.append("%s | %s" % [t, b])
			_p("NOTIFY [%s] %s | %s" % [k, t, b]))
	Game.activity_update.connect(func(info: Dictionary) -> void: _hud = info)
	Game.activity_finished.connect(func(id: String, r: Dictionary) -> void:
		_results[id] = r
		_p("RESULT %s %s" % [id, JSON.stringify(r)]))
	add_child(MAIN.instantiate())
	_run.call_deferred()


static func _arg(key: String, default: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--" + key + "="):
			return a.substr(key.length() + 3)
	return default


func _p(msg: String) -> void:
	print("[f3] ", msg)
	if _log != null:
		_log.store_line(msg)
		_log.flush()


func _check(ok: bool, what: String) -> void:
	_p("%s %s" % ["PASS" if ok else "FAIL", what])
	if not ok:
		_fails += 1


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds, true, false, true).timeout


func _wait_streamed() -> void:
	await get_tree().process_frame
	var w := Game.world as World
	var t := 0.0
	while t < 20.0 and (w.terrain.pending_count() > 0 or not w.roads.done):
		await get_tree().process_frame
		t += get_process_delta_time()
	await _wait(0.5)


func _shot(n: String) -> void:
	await RenderingServer.frame_post_draw
	var path := out_dir.path_join("%s.png" % n)
	get_viewport().get_texture().get_image().save_png(path)
	_p("shot " + ProjectSettings.globalize_path(path))


func _ev(id: String) -> Dictionary:
	for e: Dictionary in Game.activities.get_activity_list():
		if e["id"] == id:
			return e
	return {}


func _road(ev: Dictionary) -> RoadNetwork.Road:
	return (Game.world as World).data.network.get_road(ev["road"])


func _key(physical: int, pressed: bool) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = physical as Key
	e.keycode = physical as Key
	e.pressed = pressed
	Input.parse_input_event(e)


func _tap(physical: int) -> void:
	_key(physical, true)
	await get_tree().process_frame
	await get_tree().process_frame
	_key(physical, false)
	await get_tree().process_frame


func _run() -> void:
	while Game.main == null or Game.main.is_loading:
		await get_tree().process_frame
	Game.main.car_input.enabled = false
	var dens0: float = Game.traffic.get_density() if Game.traffic != null else 0.0
	var mph0: bool = bool(Settings.get_value("units_mph", false))
	Game.set_time_of_day(12.0)
	Game.set_weather("clear", true)
	if Game.traffic != null:
		Game.traffic.set_density(float(_arg("traffic", "0.6")))
	Game.player_car.impact.connect(_on_player_impact)
	await _wait(1.0)
	var sc := _arg("scenario", "race")
	match sc:
		"race":
			await _race_scenario()
		"tunnel":
			await _tunnel_scenario()
		"overlay":
			await _overlay_scenario()
		"rewind":
			await _rewind_scenario()
		"units":
			await _units_scenario()
		"jump":
			await _jump_scenario()
		"spot":
			await _spot_scenario()
		"standoff":
			await _standoff_scenario()
		"facing":
			await _facing_scenario()
		"nightlights":
			await _nightlights_scenario()
		"release":
			await _release_scenario()
	Input.action_release("accelerate")
	Input.action_release("rewind")
	Game.main.car_input.enabled = true
	if Game.traffic != null:
		Game.traffic.set_density(dens0)
	Settings.set_value("units_mph", mph0, false)
	_p("units_mph restored to %s, live traffic density %.2f" % [mph0, dens0])
	_p("SUMMARY %s: %s (%d failed checks)" % [sc, "PASS" if _fails == 0 else "FAIL", _fails])
	get_tree().quit(0)


func _on_player_impact(strength: float, _pos: Vector3) -> void:
	var best := INF
	var who := ""
	for r: CarController in Game.activities.get_ai_cars():
		var d := r.global_position.distance_to(Game.player_car.global_position)
		if d < best:
			best = d
			who = r.name
	_impacts.append("%.2f (nearest rival %s %.1f m)" % [strength, who, best])
	if strength > 0.8:
		_p("PLAYER IMPACT %.2f, nearest rival %s at %.1f m" % [strength, who, best])


# ------------------------------------------------------------------ race start / player driver

## Drives the player through the start arch, stops in the zone and waits for GO. Returns the session.
func _to_running(id: String) -> RefCounted:
	var mgr: Node = Game.activities
	var act: RefCounted = mgr.by_id[id]
	var ev := _ev(id)
	var road := _road(ev)
	var d: int = ev["dir"]
	mgr.teleport_to_activity(id, 90.0)
	await _wait_streamed()
	var car := Game.player_car
	car.freeze = false
	var f := RoadFollower.new()
	f.setup(road, float(ev["gates"][0]) - d * 90.0, d, road.lane_offset(1))
	f.target_speed = 45.0 / 3.6
	var t := 0.0
	while t < 60.0 and int(act.get("state")) < 3:
		await get_tree().physics_frame
		var dt := get_physics_process_delta_time()
		t += dt
		var st := int(act.get("state"))
		if st == 1:
			f.target_speed = 0.0
		if st < 2:
			f.drive(car, dt)
	if int(act.get("state")) != 3:
		_p("race %s never started (state %d)" % [id, int(act.get("state"))])
		return null
	# The last stop-to-start brake input would select reverse at GO: hold the car neutrally instead.
	car.in_brake = 0.0
	car.in_throttle = 0.0
	car.in_handbrake = 1.0
	return act


func _player_follower(road: RoadNetwork.Road, d: int, kmh: float) -> RoadFollower:
	var car := Game.player_car
	var res := (Game.world as World).data.network.nearest(car.global_position, 40.0, func(rr: RoadNetwork.Road) -> bool: return rr == road)
	var f := RoadFollower.new()
	f.setup(road, float(res.get("s", 0.0)), d, road.lane_offset(1))
	f.target_speed = (kmh if kmh > 0.0 else car.data.top_speed_kmh * 0.9) / 3.6
	f.lat_accel = float(_arg("player-lat", "7.2"))
	return f


## Test driver overtaking: through the oncoming lane past slower traffic while nothing comes the other way
## (the player in a real race overtakes too; a follower that only queues behind a tractor never finishes).
func _player_pass(f: RoadFollower, car: CarController, road: RoadNetwork.Road) -> void:
	var fwd := -car.global_basis.z
	# Like a careful driver, never into the back of a rival: follow one ahead on the same line.
	f.obstacle_limit = INF
	for r: CarController in Game.activities.get_ai_cars():
		var rr := car.global_transform.affine_inverse() * r.global_position
		if -rr.z > 0.0 and -rr.z < 40.0 and absf(rr.x) < 2.4:
			f.obstacle_limit = minf(f.obstacle_limit, RoadFollower.follow_speed(-rr.z - 4.5, r.linear_velocity.dot(fwd), car.speed_ms, 0.8))
	var tm: Node = Game.traffic
	if tm == null or road.lanes >= 2:
		return
	var slow_ahead := false
	var beside := false
	var oncoming := INF
	for o: Dictionary in tm.call("obstacles_near", car.global_position, 300.0):
		var rel := car.global_transform.affine_inverse() * (o["position"] as Vector3)
		var same := (o["heading"] as Vector3).dot(fwd) > 0.5
		if same and -rel.z > 3.0 and -rel.z < 45.0 and absf(rel.x) < 2.5 and float(o["speed"]) < f.target_speed * 0.8:
			slow_ahead = true
		if same and -rel.z > -8.0 and -rel.z < 10.0 and rel.x > 1.2:
			beside = true
		if (o["heading"] as Vector3).dot(fwd) < -0.3 and -rel.z > -10.0:
			oncoming = minf(oncoming, -rel.z)
	var lane := road.lane_offset(1)
	_player_lane = f.lane_offset
	if f.lane_offset < 0.0:
		if (not beside and not slow_ahead) or oncoming < 220.0:
			f.lane_offset = lane
	elif slow_ahead and oncoming > 420.0 and car.speed_ms < 30.0:
		f.lane_offset = -lane


# ------------------------------------------------------------------ rival monitor

class Mon:
	var prev: Dictionary = {}
	var rec: Dictionary = {}
	var jumps := 0
	var recover_moves := 0
	var off_t: Dictionary = {}
	var off_max := 0.0
	var off_total := 0.0
	var below := 0
	var below_far := 0
	var wet := 0
	var contacts := 0
	var rival_contacts := 0
	var cam_inside := 0
	var min_dist := INF
	var seen: Dictionary = {}
	var far_no_col := 0


func _monitor(m: Mon, opp: RefCounted, dt: float, t: float) -> void:
	var w := Game.world as World
	var pc := Game.player_car
	var cars: Array = opp.get("cars")
	var fl: Array = opp.get("followers")
	var recs: PackedInt32Array = opp.get("recoveries")
	var road: RoadNetwork.Road = opp.get("road")
	var cam: Camera3D = Game.camera_rig.get("camera")
	for k in cars.size():
		var rc: CarController = cars[k]
		if not is_instance_valid(rc) or rc.is_queued_for_deletion():
			continue
		var p := rc.global_position
		var key := String(rc.name)
		if m.prev.has(key):
			var mv := (m.prev[key] as Vector3).distance_to(p)
			if mv > 3.0:
				if int(m.rec.get(key, 0)) != recs[k]:
					m.recover_moves += 1
				else:
					m.jumps += 1
					_p("JUMP %s moved %.1f m in one physics frame at t=%.2f (s %.0f)" % [key, mv, t, (fl[k] as RoadFollower).s])
		m.prev[key] = p
		m.rec[key] = recs[k]
		var s: float = (fl[k] as RoadFollower).s
		var lat := (p - road.point_at(s)).dot(road.right_at(s))
		var off := absf(lat) > road.width * 0.5 + 3.5
		if off:
			m.off_t[key] = float(m.off_t.get(key, 0.0)) + dt
			m.off_total += dt
			m.off_max = maxf(m.off_max, float(m.off_t[key]))
			if float(m.off_t[key]) > 3.0 and not m.seen.has("off" + key + str(int(t / 10.0))):
				m.seen["off" + key + str(int(t / 10.0))] = true
				_p("OFF %s %.1f m off the route for %.1f s at t=%.1f (%.0f km/h, %.0f m from player)" % [key, lat, float(m.off_t[key]), t,
					rc.get_speed_kmh(), p.distance_to(pc.global_position)])
		else:
			m.off_t[key] = 0.0
		var dist := p.distance_to(pc.global_position)
		m.min_dist = minf(m.min_dist, dist)
		var in_tunnel: bool = Game.main.call("_in_tunnel", p)
		var below_now := not in_tunnel and p.y < w.height_at(p.x, p.z) - 1.2 and absf(lat) > road.width * 0.5 + 1.0
		if below_now:
			m.below += 1
			if dist > 230.0:
				m.below_far += 1
			if not m.seen.has("b" + key + str(int(t))):
				m.seen["b" + key + str(int(t))] = true
				_p("BELOW %s %.1f m under the terrain at t=%.1f, %.0f m from player, lat %.1f" % [key, w.height_at(p.x, p.z) - p.y, t, dist, lat])
		if p.y < w.water_level_at(p.x, p.z) - 0.5:
			m.wet += 1
		if dist > 260.0 and Engine.get_physics_frames() % 60 == 0:
			if not _has_collider(p):
				m.far_no_col += 1
				_p("NO TERRAIN COLLIDER under far rival %s (%.0f m from player) at t=%.1f" % [key, dist, t])
		for b in rc.get_colliding_bodies():
			var ck := "c%s_%s" % [key, b.name]
			if float(m.seen.get(ck, -10.0)) < t - 1.0:
				if b == pc:
					m.contacts += 1
					var pl_lat: float = opp.call("_lat", pc.global_position, s)
					var rel := pc.global_transform.affine_inverse() * p
					_p("CONTACT %s with the player at t=%.2f (%.0f km/h vs %.0f km/h): rival lat %.2f (line %.2f, lane %.2f, steer %.2f) player lat %.2f (target %.2f, steer %.2f), rival rel to player lat %.1f ahead %.1f" % [
						key, t, rc.get_speed_kmh(), pc.get_speed_kmh(), lat * opp.get("dir"), (opp.get("_cur") as PackedFloat32Array)[k], (fl[k] as RoadFollower).lane_offset,
						rc.in_steer, pl_lat, _player_lane, pc.in_steer, rel.x, -rel.z])
				elif b is CarController and b.get_parent() == rc.get_parent():
					m.rival_contacts += 1
					_p("CONTACT %s with %s at t=%.2f (%.0f km/h)" % [key, b.name, t, rc.get_speed_kmh()])
			m.seen[ck] = t
		if cam != null:
			var lc := rc.global_transform.affine_inverse() * cam.global_position
			var bs := rc.data.body_size
			if absf(lc.x) < bs.x * 0.5 and lc.y > 0.0 and lc.y < bs.y and absf(lc.z) < bs.z * 0.5:
				m.cam_inside += 1


func _has_collider(p: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 30.0, p + Vector3.DOWN * 60.0, 1)
	var hit := get_viewport().get_world_3d().direct_space_state.intersect_ray(q)
	return not hit.is_empty()


func _mon_report(m: Mon, label: String) -> void:
	_p("MONITOR %s: unexplained jumps %d, recoveries %d, off-route total %.1f s (longest %.1f s), below-terrain frames %d (far %d), underwater frames %d, rival->player contacts %d, rival-rival contacts %d, camera inside a rival %d frames, min rival-player distance %.1f m, far rival without terrain collider %d" % [
		label, m.jumps, m.recover_moves, m.off_total, m.off_max, m.below, m.below_far, m.wet, m.contacts, m.rival_contacts, m.cam_inside, m.min_dist, m.far_no_col])


func _rival_line(opp: RefCounted, pc: CarController) -> String:
	var parts := PackedStringArray()
	var cars: Array = opp.get("cars")
	for k in cars.size():
		var rc: CarController = cars[k]
		if not is_instance_valid(rc):
			parts.append("R%d gone" % (k + 1))
			continue
		var rel := pc.global_transform.affine_inverse() * rc.global_position
		parts.append("R%d lat %.1f ahead %.1f %.0f km/h%s" % [k + 1, rel.x, -rel.z, rc.get_speed_kmh(), " PASS" if (opp.get("_swing") as PackedFloat32Array)[k] > 0.0 else ""])
	return ", ".join(parts)


# ------------------------------------------------------------------ scenarios

## q25 / q26 / q27: full race at a normal pace (optionally with a stop), traffic on.
func _race_scenario() -> void:
	var id := _arg("id", "rc_highmoor")
	var ev := _ev(id)
	var road := _road(ev)
	var d: int = ev["dir"]
	var act: RefCounted = await _to_running(id)
	if act == null:
		_check(false, "%s started" % id)
		return
	var opp: RefCounted = act.get("opponents")
	var f := _player_follower(road, d, float(_arg("kmh", "0")))
	var stop_at := float(_arg("stop", "-1"))
	var hold := float(_arg("hold", "14"))
	var m := Mon.new()
	var t := 0.0
	var shot_t := 0.0
	var stopped_t := -1.0
	var passed_while_stopped := 0
	var rival_s0: Dictionary = {}
	var max_t := float(_arg("max", "330"))
	var cam_k := 0
	var beside_t := 0.0
	var beside_max := 0.0
	_p("---- %s running, traffic %.2f, player %s, %s" % [id, Game.traffic.get_density() if Game.traffic != null else 0.0, Game.player_car.data.id,
		"stop at %.0f s for %.0f s" % [stop_at, hold] if stop_at >= 0.0 else "no stop"])
	while t < max_t and Game.activities.get_session_id() == id:
		await get_tree().physics_frame
		var dt := get_physics_process_delta_time()
		t += dt
		var car := Game.player_car
		if stop_at >= 0.0 and t >= stop_at and t < stop_at + hold:
			f.target_speed = 0.0
			if stopped_t < 0.0 and car.speed_ms < 0.3:
				stopped_t = t
				for k in (opp.get("cars") as Array).size():
					rival_s0[k] = ((opp.get("followers") as Array)[k] as RoadFollower).s
				_p("player stopped at t=%.1f: %s" % [t, _rival_line(opp, car)])
		elif stop_at >= 0.0 and t >= stop_at + hold and f.target_speed < 1.0:
			var tr: float = (act.get("tracker") as RefCounted).get("s")
			var p_s: float = tr
			for k in rival_s0.keys():
				var rs: float = ((opp.get("followers") as Array)[k] as RoadFollower).s
				if (rs - p_s) * d > 5.0:
					passed_while_stopped += 1
			_p("end of the stop at t=%.1f: %s; rivals ahead of the stopped player %d of %d" % [t, _rival_line(opp, car), passed_while_stopped, rival_s0.size()])
			if Game.traffic != null and Game.traffic.get_density() > 0.0:
				# With oncoming traffic a rival may wait behind the stopped player; it must not be left standing beside it.
				_p("rivals passed the stopped player: %d of %d (traffic on)" % [passed_while_stopped, rival_s0.size()])
			else:
				_check(passed_while_stopped >= 2, "%s: rivals passed the stopped player (%d of %d)" % [id, passed_while_stopped, rival_s0.size()])
			_check(beside_max < 6.0, "%s: no rival left standing beside the stopped player in the oncoming lane (longest %.1f s)" % [id, beside_max])
			f = _player_follower(road, d, float(_arg("kmh", "0")))
		if f.target_speed > 1.0:
			_player_pass(f, car, road)
		f.drive(car, dt)
		_monitor(m, opp, dt, t)
		if stopped_t >= 0.0 and t < stop_at + hold:
			# A rival standing beside the stopped player in the oncoming lane (a stand-off with oncoming traffic).
			var beside_now := false
			for rc: CarController in Game.activities.get_ai_cars():
				var rr := car.global_transform.affine_inverse() * rc.global_position
				if absf(rr.z) < 5.0 and rr.x < -2.5 and rc.speed_ms < 0.3:
					beside_now = true
			beside_t = beside_t + dt if beside_now else 0.0
			beside_max = maxf(beside_max, beside_t)
		if stopped_t >= 0.0 and t < stop_at + hold and fmod(t - stopped_t, 1.0) < dt:
			_p("  stop +%.0f s: %s" % [t - stopped_t, _rival_line(opp, car)])
			if _arg("debug", "0") == "1":
				for k in (opp.get("cars") as Array).size():
					var rc: CarController = (opp.get("cars") as Array)[k]
					var rf: RoadFollower = (opp.get("followers") as Array)[k]
					_p("    R%d lat %.2f cur %.2f lane_off %.2f lim %.2f gap %.2f backoff %.2f | steer %.2f thr %.2f brk %.2f hb %.1f gear %d" % [k + 1,
						opp.call("_lat", rc.global_position, rf.s), (opp.get("_cur") as PackedFloat32Array)[k], rf.lane_offset, rf.obstacle_limit,
						(opp.get("_lim_gap") as PackedFloat32Array)[k], (opp.get("_backoff") as PackedFloat32Array)[k], rc.in_steer, rc.in_throttle,
						rc.in_brake, rc.in_handbrake, rc.gear])
			if int(t - stopped_t) in [3, 7, 11]:
				await _shot("%s_stop_%ds" % [_arg("tag", id), int(t - stopped_t)])
		if fmod(t, 10.0) < dt:
			_p("t=%.0f player s %.0f %.0f km/h | %s | HUD %s" % [t, f.s, car.get_speed_kmh(), _rival_line(opp, car), str(_hud.get("secondary", ""))])
		if _arg("debug", "0") == "1" and fmod(t, 1.0) < dt:
			_rival_debug(opp, t)
		shot_t += dt
		if shot_t > float(_arg("rivalcam", "25")):
			shot_t = 0.0
			cam_k = (cam_k + 1) % (opp.get("cars") as Array).size()
			await _rival_cam(opp, cam_k, "%s_rival%d_t%d" % [_arg("tag", id), cam_k + 1, int(t)])
	var r: Dictionary = _results.get(id, {})
	var times: PackedFloat32Array = opp.get("finish_times")
	_p("race end t=%.1f result %s, rival finish times %s, rival recoveries %s" % [t, str(r.get("detail", "none")), str(times), str(opp.get("recoveries"))])
	_mon_report(m, id)
	_check(not r.is_empty(), "%s: player finished (%s, %s)" % [id, str(r.get("score_text", "-")), str(r.get("detail", "-"))])
	_check(m.jumps == 0, "%s: no rival teleports other than recoveries (%d)" % [id, m.jumps])
	_check(m.contacts == 0, "%s: no rival contact with the player (%d)" % [id, m.contacts])
	_check(m.off_max <= 6.0, "%s: no rival off the route longer than 6 s (longest %.1f s, total %.1f s)" % [id, m.off_max, m.off_total])
	_check(m.below_far == 0 and m.far_no_col == 0, "%s: far rivals keep terrain colliders and never sink (%d / %d)" % [id, m.below_far, m.far_no_col])
	_check(m.cam_inside == 0, "%s: camera never inside a rival (%d frames)" % [id, m.cam_inside])
	# Every rival finished or was still racing close to the end when the race ended (none stuck / lost).
	var fin := 0
	var g0 := float(ev["gates"][0])
	var g1 := float(ev["gates"][(ev["gates"] as Array).size() - 1])
	var prog := PackedStringArray()
	for k in times.size():
		var pr := (((opp.get("followers") as Array)[k] as RoadFollower).s - g0) / (g1 - g0)
		prog.append("%.0f%%" % (pr * 100.0) if times[k] < 0.0 else "finished")
		if times[k] >= 0.0 or pr > 0.75:
			fin += 1
	_check(fin == times.size() or r.is_empty(), "%s: rivals finished or near the end when the race ended (%s)" % [id, ", ".join(prog)])


func _rival_debug(opp: RefCounted, t: float) -> void:
	var tm: Node = Game.traffic
	for k in (opp.get("cars") as Array).size():
		var rc: CarController = (opp.get("cars") as Array)[k]
		if not is_instance_valid(rc):
			continue
		var rf: RoadFollower = (opp.get("followers") as Array)[k]
		var near := ""
		if tm != null:
			for o: Dictionary in tm.call("obstacles_near", rc.global_position, 60.0):
				var p: Vector3 = o["position"]
				var rel := rc.global_transform.affine_inverse() * p
				near += " [tr lat %.1f ahead %.1f %.0f km/h]" % [rel.x, -rel.z, float(o["speed"]) * 3.6]
		_p("  dbg t=%.0f R%d s %.0f lat %.2f cur %.2f lane %.2f lim %.1f gap %.1f %.0f km/h steer %.2f thr %.2f brk %.2f%s" % [t, k + 1, rf.s,
			opp.call("_lat", rc.global_position, rf.s), (opp.get("_cur") as PackedFloat32Array)[k], rf.lane_offset, rf.obstacle_limit,
			(opp.get("_lim_gap") as PackedFloat32Array)[k], rc.get_speed_kmh(), rc.in_steer, rc.in_throttle, rc.in_brake, near])


## Screenshot from a camera above / behind rival k.
func _rival_cam(opp: RefCounted, k: int, n: String) -> void:
	var rc: CarController = (opp.get("cars") as Array)[k]
	if not is_instance_valid(rc):
		return
	var cam := Camera3D.new()
	add_child(cam)
	var back := rc.global_basis.z
	back.y = 0.0
	cam.global_position = rc.global_position + back.normalized() * 14.0 + Vector3.UP * 7.0
	cam.look_at(rc.global_position + Vector3.UP * 0.5)
	cam.fov = 60.0
	cam.make_current()
	await get_tree().process_frame
	await _shot(n)
	Game.camera_rig.camera.make_current()
	cam.queue_free()


## q27: rival through the Ember Spur tunnel far from the player; a far rival dropped on the grass beside the road.
func _tunnel_scenario() -> void:
	var id := "rc_highmoor"
	var act: RefCounted = await _to_running(id)
	if act == null:
		_check(false, "race started")
		return
	var opp: RefCounted = act.get("opponents")
	var road: RoadNetwork.Road = opp.get("road")
	var cars: Array = opp.get("cars")
	var fl: Array = opp.get("followers")
	await _wait(1.0)
	# Rival 1: 60 m before the tunnel at race pace (the player waits on the grid ~7 km away). The race road's
	# finish moves beyond the tunnel so the rival is still racing there (finished rivals retire out of view).
	opp.set("finish_s", 8600.0)
	var r1: CarController = cars[0]
	var s1 := 7140.0
	var line: float = (opp.get("_line") as PackedFloat32Array)[0]
	var xf1: Transform3D = opp.call("_surface_xf", s1, line)
	r1.place_at(xf1, -xf1.basis.z * 22.0)
	(fl[0] as RoadFollower).s = s1
	(fl[0] as RoadFollower).lane_offset = line
	# Rival 2: on the grass 14 m beside the road ~1 km from the player, standing.
	var r2: CarController = cars[1]
	var s2 := 1300.0
	var side := road.surface_point(s2, 14.0)
	side.y = (Game.world as World).height_at(side.x, side.z) + 0.6
	r2.place_at(Transform3D(Basis.looking_at(road.flat_tangent_at(s2), Vector3.UP), side))
	(fl[1] as RoadFollower).s = s2
	var m := Mon.new()
	var t := 0.0
	var pf := RoadFollower.new()
	pf.setup(road, float(_ev(id)["gates"][0]) + 20.0, 1, road.lane_offset(1))
	pf.target_speed = 0.0
	var r2_min_clear := INF
	var r1_max_s := s1
	var col_ok := 0
	var col_checks := 0
	while t < 30.0:
		await get_tree().physics_frame
		var dt := get_physics_process_delta_time()
		t += dt
		pf.drive(Game.player_car, dt)
		_monitor(m, opp, dt, t)
		r1_max_s = maxf(r1_max_s, (fl[0] as RoadFollower).s)
		if is_instance_valid(r2):
			var p2 := r2.global_position
			r2_min_clear = minf(r2_min_clear, p2.y - (Game.world as World).height_at(p2.x, p2.z))
			# From 1 s on: the test teleported the rival 1 km away, the streamer needs a moment to react.
			if t > 1.0 and Engine.get_physics_frames() % 30 == 0:
				col_checks += 1
				if _has_collider(p2):
					col_ok += 1
		if not is_instance_valid(r1) or not is_instance_valid(r2):
			_check(false, "rivals 1 and 2 still in the race")
			break
		if fmod(t, 2.0) < dt:
			_p("t=%.0f R1 s %.0f %.0f km/h y-road %.2f | R2 s %.0f lat %.1f %.0f km/h clear %.2f | recoveries %s" % [t, (fl[0] as RoadFollower).s,
				r1.get_speed_kmh(), r1.global_position.y - road.point_at((fl[0] as RoadFollower).s).y, (fl[1] as RoadFollower).s,
				(r2.global_position - road.point_at((fl[1] as RoadFollower).s)).dot(road.right_at((fl[1] as RoadFollower).s)),
				r2.get_speed_kmh(), r2.global_position.y - (Game.world as World).height_at(r2.global_position.x, r2.global_position.z), str(opp.get("recoveries"))])
	_mon_report(m, "tunnel")
	var recs: PackedInt32Array = opp.get("recoveries")
	_check(r1_max_s > 7620.0, "rival drove through the Ember Spur tunnel (reached s %.0f)" % r1_max_s)
	_check(recs[0] == 0 and m.jumps == 0, "no tunnel warps / recoveries for rival 1 (recoveries %d, jumps %d)" % [recs[0], m.jumps])
	_check(r2_min_clear > -0.8 and m.below == 0, "far rival on the grass never sank (min origin height above terrain %.2f m)" % r2_min_clear)
	_check(col_ok == col_checks and col_checks > 0, "terrain collider under the far rival (%d of %d checks)" % [col_ok, col_checks])
	var lat2 := absf((r2.global_position - road.point_at((fl[1] as RoadFollower).s)).dot(road.right_at((fl[1] as RoadFollower).s)))
	_check(lat2 < road.width * 0.5 + 1.0, "far rival back on the road (lateral %.1f m, recoveries %d)" % [lat2, recs[1]])
	Game.activities.cancel_session("test")


## Debug: rival k (--k) placed at --s0 at --kmh on the race road, logged at 10 Hz for --secs.
func _spot_scenario() -> void:
	var id := _arg("id", "rc_coast")
	var act: RefCounted = await _to_running(id)
	if act == null:
		return
	var opp: RefCounted = act.get("opponents")
	var road: RoadNetwork.Road = opp.get("road")
	var k := int(_arg("k", "1"))
	var rc: CarController = (opp.get("cars") as Array)[k]
	var rf: RoadFollower = (opp.get("followers") as Array)[k]
	var s0 := float(_arg("s0", "16150"))
	var line: float = (opp.get("_line") as PackedFloat32Array)[k]
	var xf: Transform3D = opp.call("_surface_xf", s0, line)
	rc.place_at(xf, -xf.basis.z * float(_arg("kmh", "150")) / 3.6)
	rf.s = s0
	rf.lane_offset = line
	var t := 0.0
	var pf := RoadFollower.new()
	pf.setup(road, float(_ev(id)["gates"][0]) + 20.0, 1, road.lane_offset(1))
	pf.target_speed = 0.0
	while t < float(_arg("secs", "12")):
		await get_tree().physics_frame
		var dt := get_physics_process_delta_time()
		t += dt
		pf.drive(Game.player_car, dt)
		if not is_instance_valid(rc):
			break
		if fmod(t, 0.1) < dt:
			var kk: float = opp.call("_kappa_at", rf.s)
			var bend := (road.point_at(rf.s + 40.0) - road.point_at(rf.s)).dot(road.right_at(rf.s))
			_p("t=%.1f s %.0f bend(40 m, + right) %.1f wheel %.1f deg lat %.2f y-road %.2f %.0f km/h lim %.1f kappa %.4f steer %.2f thr %.2f brk %.2f wheels %d up %.2f slip %.1f rec %s" % [t, rf.s, bend, rad_to_deg(rc.steer_angle),
				opp.call("_lat", rc.global_position, rf.s), rc.global_position.y - road.point_at(rf.s).y, rc.get_speed_kmh(), rf.obstacle_limit, kk,
				rc.in_steer, rc.in_throttle, rc.in_brake, rc.wheels_on_ground, rc.global_basis.y.y, rc.body_slip_deg, str(opp.get("recoveries"))])
	Game.activities.cancel_session("test")


## q28: overlays opened mid-race with real key events.
func _overlay_scenario() -> void:
	var id := "rc_highmoor"
	var ev := _ev(id)
	var road := _road(ev)
	var act: RefCounted = await _to_running(id)
	if act == null:
		_check(false, "race started")
		return
	var opp: RefCounted = act.get("opponents")
	var f := _player_follower(road, 1, 110.0)
	var t := 0.0
	var plan := [[8.0, "map", 77], [20.0, "garage", 4194306], [32.0, "debug", 4194333], [44.0, "console", 96]]
	var i := 0
	while t < 56.0 and i < plan.size():
		await get_tree().physics_frame
		var dt := get_physics_process_delta_time()
		t += dt
		f.drive(Game.player_car, dt)
		if t < float(plan[i][0]):
			continue
		# Hand the car to the player's input (accelerate held) and press the overlay key.
		Game.main.car_input.enabled = true
		Input.action_press("accelerate")
		var car := Game.player_car
		var before := _snap(act, opp)
		await _tap(int(plan[i][2]))
		await get_tree().physics_frame
		var open1: bool = Game.is_overlay_open()
		await _wait(1.0)
		var mid := _snap(act, opp)
		await _shot("overlay_%s_open" % plan[i][1])
		await _wait(2.0)
		var late := _snap(act, opp)
		if plan[i][1] == "console":
			await _tap(96)
		else:
			await _tap(int(plan[i][2]))
		await get_tree().physics_frame
		await get_tree().physics_frame
		var after := _snap(act, opp)
		_p("%s: open %s, before %s | +1 s %s | +3 s %s | closed %s" % [plan[i][1], open1, before["txt"], mid["txt"], late["txt"], after["txt"]])
		_check(open1 and absf(float(late["clock"]) - float(before["clock"])) < 0.1, "%s open 3 s: race clock frozen (%.2f -> %.2f)" % [plan[i][1], before["clock"], late["clock"]])
		_check(absf(float(late["rival_s"]) - float(mid["rival_s"])) < 0.05, "%s: rivals frozen (sum of s %.2f -> %.2f)" % [plan[i][1], mid["rival_s"], late["rival_s"]])
		_check(not Game.is_overlay_open() and absf(float(after["kmh"]) - float(before["kmh"])) < 4.0, "%s closed: player resumes at %.0f km/h (before %.0f)" % [plan[i][1], after["kmh"], before["kmh"]])
		_check(float(after["clock"]) - float(before["clock"]) < 0.25, "%s closed: clock resumes where it stopped (%.2f -> %.2f)" % [plan[i][1], before["clock"], after["clock"]])
		await _wait(1.0)
		var on := _snap(act, opp)
		_check(float(on["clock"]) > float(after["clock"]) + 0.8, "%s: clock running again (%.2f)" % [plan[i][1], on["clock"]])
		Input.action_release("accelerate")
		Game.main.car_input.enabled = false
		f = _player_follower(road, 1, 110.0)
		i += 1
	if i < plan.size():
		_check(false, "overlay plan finished (%d of %d)" % [i, plan.size()])
	Game.activities.cancel_session("test")
	await _wait(0.5)
	await _zone_overlay("sz_vale")


## Map (M) opened in a speed zone: the zone timer stops, the car is held and resumes at the same speed.
func _zone_overlay(zid: String) -> void:
	var mgr: Node = Game.activities
	var zev := _ev(zid)
	var road := _road(zev)
	var g0: float = zev["gates"][0]
	var g1: float = zev["gates"][1]
	var d := 1 if g1 > g0 else -1
	var s0 := g0 - d * 200.0
	Game.main.teleport_to({"position": road.surface_point(s0, road.lane_offset(1) * d), "forward": road.flat_tangent_at(s0) * d})
	await _wait_streamed()
	Game.player_car.freeze = false
	var f := RoadFollower.new()
	f.setup(road, s0, d, road.lane_offset(1))
	f.target_speed = 100.0 / 3.6
	f.lat_accel = 7.0
	var t := 0.0
	while t < 30.0 and mgr.get_session_id() != zid:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		f.drive(Game.player_car, get_physics_process_delta_time())
	for i in 180:
		await get_tree().physics_frame
		f.drive(Game.player_car, get_physics_process_delta_time())
	var zone: RefCounted = mgr.by_id[zid]
	if mgr.get_session_id() != zid:
		_check(false, "%s running for the overlay check" % zid)
		return
	var t0: float = zone.get("_t")
	var kmh0 := Game.player_car.get_speed_kmh()
	Game.main.car_input.enabled = true
	Input.action_press("accelerate")
	await _tap(77)
	await _wait(2.0)
	var t1: float = zone.get("_t")
	var frozen := Game.player_car.freeze
	await _tap(77)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var kmh1 := Game.player_car.get_speed_kmh()
	var t2: float = zone.get("_t")
	Input.action_release("accelerate")
	Game.main.car_input.enabled = false
	_p("speed zone map: timer %.2f -> %.2f (2 s open) -> %.2f after close, car frozen while open %s, %.0f km/h -> %.0f km/h" % [t0, t1, t2, frozen, kmh0, kmh1])
	_check(absf(t1 - t0) < 0.1 and frozen and absf(kmh1 - kmh0) < 4.0 and mgr.get_session_id() == zid,
		"%s: map open 2 s freezes the zone timer and holds the car (resumes at %.0f km/h)" % [zid, kmh1])
	mgr.cancel_session("test")


func _snap(act: RefCounted, opp: RefCounted) -> Dictionary:
	var sum := 0.0
	var parts := PackedStringArray()
	for k in (opp.get("followers") as Array).size():
		var rf: RoadFollower = (opp.get("followers") as Array)[k]
		var rc: CarController = (opp.get("cars") as Array)[k]
		sum += rf.s
		parts.append("R%d s %.1f %.0f km/h%s" % [k + 1, rf.s, rc.get_speed_kmh() if is_instance_valid(rc) else 0.0, " frozen" if is_instance_valid(rc) and rc.freeze else ""])
	var car := Game.player_car
	return {"clock": float(act.get("_t")), "kmh": car.linear_velocity.length() * 3.6 if not car.freeze else car.get_speed_kmh(), "rival_s": sum,
		"txt": "clock %.2f player %.0f km/h%s overlay %s | %s" % [float(act.get("_t")), car.get_speed_kmh(), " frozen" if car.freeze else "",
			Game.is_overlay_open(), ", ".join(parts)]}


## q29 (activities side): rewind blocked in races, zones / jumps end on a rewind.
func _rewind_scenario() -> void:
	var mgr: Node = Game.activities
	var rewind_impl := FileAccess.get_file_as_string("res://scripts/vehicle/car_rewind.gd").contains("rewind_blocked")
	_p("car_rewind.gd calls rewind_blocked: %s" % rewind_impl)
	_check(not bool(mgr.call("rewind_blocked")), "rewind allowed with no event running")
	var id := "rc_highmoor"
	var ev := _ev(id)
	var road := _road(ev)
	var act: RefCounted = mgr.by_id[id]
	# Countdown check happens on the way to GO.
	var seen := {"countdown": false}
	var watcher := func() -> void:
		if int(act.get("state")) == 2:
			seen["countdown"] = bool(mgr.call("rewind_blocked"))
	get_tree().physics_frame.connect(watcher)
	act = await _to_running(id)
	get_tree().physics_frame.disconnect(watcher)
	_check(bool(seen["countdown"]), "rewind_blocked() true during the countdown")
	_check(bool(mgr.call("rewind_blocked")), "rewind_blocked() true while racing")
	var opp: RefCounted = act.get("opponents")
	var f := _player_follower(road, 1, 110.0)
	var t := 0.0
	while t < 8.0:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		f.drive(Game.player_car, get_physics_process_delta_time())
	var before := _snap(act, opp)
	var p0 := Game.player_car.global_position
	_notes.clear()
	Game.main.car_input.enabled = true
	_key(KEY_REWIND, true)
	await _wait(1.5)
	var during_frozen := Game.player_car.freeze
	await _shot("rewind_race_held")
	_key(KEY_REWIND, false)
	await get_tree().physics_frame
	Game.main.car_input.enabled = false
	var moved_back := (Game.player_car.global_position - p0).dot(-Game.player_car.global_basis.z) < -5.0
	var warned := 0
	for n in _notes:
		if n.contains("Rewind"):
			warned += 1
	_p("rewind key 1.5 s in the race: car frozen %s, moved back %s, rewind notices %d, before %s | after %s" % [during_frozen, moved_back, warned, before["txt"], _snap(act, opp)["txt"]])
	if rewind_impl:
		_check(not during_frozen and not moved_back and warned == 1, "rewind key in a race: no rewind, one notice")
	mgr.cancel_session("test")
	await _wait(0.5)
	_check(not bool(mgr.call("rewind_blocked")), "rewind allowed again after the race")
	# Speed zone: a rewind ends it.
	var zid := "sz_vale"
	var zev := _ev(zid)
	if zev.is_empty():
		for e: Dictionary in mgr.get_activity_list():
			if e["kind"] == &"speed_zone" and zev.is_empty():
				zev = e
		zid = zev["id"]
	await _zone_rewind(mgr, zid, zev, rewind_impl)


func _zone_rewind(mgr: Node, zid: String, zev: Dictionary, rewind_impl: bool) -> void:
	var road := _road(zev)
	var g0: float = zev["gates"][0]
	var g1: float = zev["gates"][1]
	var d := 1 if g1 > g0 else -1
	var s0 := g0 - d * 200.0
	Game.main.teleport_to({"position": road.surface_point(s0, road.lane_offset(1) * d), "forward": road.flat_tangent_at(s0) * d})
	await _wait_streamed()
	Game.player_car.freeze = false
	var f := RoadFollower.new()
	f.setup(road, s0, d, road.lane_offset(1))
	f.target_speed = 100.0 / 3.6
	var t := 0.0
	while t < 30.0 and mgr.get_session_id() != zid:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		f.drive(Game.player_car, get_physics_process_delta_time())
	_check(mgr.get_session_id() == zid, "%s started" % zid)
	_check(not bool(mgr.call("rewind_blocked")), "rewind allowed in a speed zone")
	for i in 240:
		await get_tree().physics_frame
		f.drive(Game.player_car, get_physics_process_delta_time())
	_notes.clear()
	if rewind_impl:
		Game.main.car_input.enabled = true
		_key(KEY_REWIND, true)
		await _wait(0.6)
		_key(KEY_REWIND, false)
		await get_tree().physics_frame
		Game.main.car_input.enabled = false
	else:
		mgr.call("on_player_rewind")
		await get_tree().physics_frame
	var note := ""
	for n in _notes:
		if n.contains("Rewind"):
			note = n
	_check(mgr.get_session_id() == "" and note != "", "rewind in %s ends the zone (%s)" % [zid, note])


## q9 / q10: imperial HUD texts and medals at the shown value.
func _units_scenario() -> void:
	var mgr: Node = Game.activities
	Settings.set_value("units_mph", true, false)
	# Medal table straight from the speed zone (thresholds in km/h).
	var sz: RefCounted = mgr.by_id.get("sz_vale")
	if sz == null:
		_check(false, "sz_vale exists")
		return
	var th: PackedFloat32Array = (sz.get("data") as Object).get("thresholds")
	for mph_on: bool in [true, false]:
		Settings.set_value("units_mph", mph_on, false)
		for kmh: float in [th[1] - 0.6, th[1] - 0.22, th[1] - 0.1, th[1] + 0.5, th[1] - 1.6]:
			var shown: String = sz.call("speed_text", kmh)
			var target: String = sz.call("threshold_text", 2, Callable(sz, "speed_text"))
			var medal: int = sz.call("medal_for", kmh, true, Callable(sz, "speed_shown"))
			var same := target.ends_with(shown)
			_p("%s: %.2f km/h shown '%s', Silver target '%s' -> medal %d" % ["mph" if mph_on else "km/h", kmh, shown, target, medal])
			_check((medal >= 2) == same or medal >= 2 and kmh >= th[1], "medal agrees with the shown value (%s vs %s -> %d)" % [shown, target, medal])
	Settings.set_value("units_mph", true, false)
	# Real speed zone aimed at just below the Silver threshold (shown equal in mph).
	await _zone_aim("sz_vale", float(_arg("aim", str(th[1] - 0.3))))
	var r: Dictionary = _results.get("sz_vale", {})
	_check(not r.is_empty(), "sz_vale finished")
	if not r.is_empty():
		var v: float = r["value"]
		var shown2: String = sz.call("speed_text", v)
		var silver_txt: String = sz.call("speed_text", th[1])
		_check((shown2 == silver_txt) == (String(r["medal"]) == "Silver") or v >= th[1], "zone result '%s' vs Silver '%s' -> %s" % [r["score_text"], silver_txt, r["medal"]])
	# Jump approach text and race prompt in imperial units.
	await _jump_approach_text()
	await _race_prompt_text()
	Settings.set_value("units_mph", false, false)


func _zone_aim(zid: String, avg_kmh: float) -> void:
	var mgr: Node = Game.activities
	var zev := _ev(zid)
	var road := _road(zev)
	var g0: float = zev["gates"][0]
	var g1: float = zev["gates"][1]
	var d := 1 if g1 > g0 else -1
	var s0 := g0 - d * 250.0
	Game.main.teleport_to({"position": road.surface_point(s0, road.lane_offset(1) * d), "forward": road.flat_tangent_at(s0) * d})
	await _wait_streamed()
	var car := Game.player_car
	car.freeze = false
	var f := RoadFollower.new()
	f.setup(road, s0, d, road.lane_offset(1))
	f.target_speed = avg_kmh / 3.6
	f.lat_accel = 7.5
	var length := absf(g1 - g0)
	var t := 0.0
	var tz := 0.0
	var texts: Dictionary = {}
	while t < 90.0 and not _results.has(zid):
		await get_tree().physics_frame
		var dt := get_physics_process_delta_time()
		t += dt
		if mgr.get_session_id() == zid:
			tz += dt
			var done := absf(f.s - g0)
			var t_left := length / (avg_kmh / 3.6) - tz
			f.target_speed = clampf((length - done) / maxf(t_left, 0.5) * 1.02, 10.0, 60.0)
			var sec := String(_hud.get("secondary", ""))
			if texts.size() < 4 and not texts.has(sec.get_slice("·", 1)):
				texts[sec.get_slice("·", 1)] = sec
				if texts.size() == 2:
					await _shot("units_speedzone_panel")
		f.drive(car, dt)
	for k in texts:
		_p("speed zone HUD (mph): %s" % texts[k])
	var all_imperial := true
	for k in texts:
		if String(texts[k]).contains(" m to go"):
			all_imperial = false
	_check(not texts.is_empty() and all_imperial, "speed zone distance in mi / ft with imperial units")
	await _wait(0.5)
	await _shot("units_speedzone_result")


func _jump_approach_text() -> void:
	var mgr: Node = Game.activities
	var ev := _ev("dj_hedgerow")
	var road := _road(ev)
	var s0 := float(ev["gates"][0]) - 60.0
	Game.main.teleport_to({"position": road.surface_point(s0, 0.0), "forward": road.flat_tangent_at(s0)})
	await _wait_streamed()
	Game.player_car.freeze = false
	var f := RoadFollower.new()
	f.setup(road, s0, 1, 0.0)
	f.target_speed = 80.0 / 3.6
	var t := 0.0
	var seen := PackedStringArray()
	var shot := false
	while t < 20.0 and not _results.has("dj_hedgerow"):
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		f.drive(Game.player_car, get_physics_process_delta_time())
		if mgr.get_session_id() == "dj_hedgerow" and String(_hud.get("secondary", "")).begins_with("Hit"):
			var sec := String(_hud.get("secondary", ""))
			if seen.size() < 3 and (seen.is_empty() or seen[seen.size() - 1].get_slice("·", 1) != sec.get_slice("·", 1)) and int(t * 2.0) % 3 == 0:
				seen.append(sec)
			if not shot and f.s > float(ev["gates"][0]) + 40.0:
				shot = true
				await _shot("units_jump_panel")
	_p("jump approach HUD (mph): %s" % " / ".join(seen))
	var ok := not seen.is_empty()
	for x in seen:
		if x.contains(" m ") or not x.contains(" ft"):
			ok = false
	_check(ok, "jump approach distance and target both in feet")
	await _wait(1.5)


func _race_prompt_text() -> void:
	var mgr: Node = Game.activities
	var act: RefCounted = mgr.by_id["rc_coast"]
	var ev := _ev("rc_coast")
	var road := _road(ev)
	mgr.teleport_to_activity("rc_coast", 70.0)
	await _wait_streamed()
	Game.player_car.freeze = false
	var f := RoadFollower.new()
	f.setup(road, float(ev["gates"][0]) - 70.0, 1, road.lane_offset(1))
	f.target_speed = 60.0 / 3.6
	var t := 0.0
	while t < 20.0 and int(act.get("state")) != 1:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		f.drive(Game.player_car, get_physics_process_delta_time())
	for i in 30:
		await get_tree().physics_frame
		f.drive(Game.player_car, get_physics_process_delta_time())
	var sec := String(_hud.get("secondary", ""))
	await _shot("units_race_prompt")
	_p("race prompt (mph): %s" % sec)
	_check(sec.contains(" mi") and not sec.contains(" km"), "race start prompt length in miles")
	mgr.cancel_session("test")


## q31: lift before the ramp; the result must quote the takeoff speed.
func _jump_scenario() -> void:
	var mgr: Node = Game.activities
	for id: String in ["dj_hedgerow", "dj_pinewood"]:
		var ev := _ev(id)
		if ev.is_empty():
			continue
		var road := _road(ev)
		var d: int = int(ev["dir"]) if int(ev["dir"]) != 0 else 1
		var sign_s: float = ev["gates"][0]
		var lip_s: float = ev["gates"][1]
		var s0 := sign_s - d * 60.0
		Game.main.teleport_to({"position": road.surface_point(s0, 0.0), "forward": road.flat_tangent_at(s0) * d})
		await _wait_streamed()
		var car := Game.player_car
		car.freeze = false
		await get_tree().physics_frame
		car.place_at(car.global_transform, road.flat_tangent_at(s0) * d * (105.0 / 3.6))
		var f := RoadFollower.new()
		f.setup(road, s0, d, 0.0)
		f.target_speed = 105.0 / 3.6
		var t := 0.0
		var takeoff_kmh := -1.0
		var peak := 0.0
		_results.erase(id)
		while t < 25.0 and not _results.has(id):
			await get_tree().physics_frame
			var dt := get_physics_process_delta_time()
			t += dt
			var to_lip := (lip_s - f.s) * d
			if to_lip < 60.0 and to_lip > 2.0:
				f.target_speed = 88.0 / 3.6
			if mgr.get_session_id() == id and to_lip > 0.0:
				peak = maxf(peak, car.get_speed_kmh())
			if takeoff_kmh < 0.0 and to_lip < 3.0 and car.wheels_on_ground == 0:
				takeoff_kmh = car.get_speed_kmh()
			f.drive(car, dt)
		var r: Dictionary = _results.get(id, {})
		_p("%s: peak after the sign %.0f km/h, speed when the wheels left %.0f km/h, result %s / %s" % [id, peak, takeoff_kmh, r.get("score_text", "-"), r.get("detail", "-")])
		var quoted := float(String(r.get("detail", "at -1")).get_slice(" ", 1))
		_check(not r.is_empty() and absf(quoted - takeoff_kmh) <= 3.0 and peak - quoted > 5.0, "%s result quotes the takeoff speed (%.0f) not the peak (%.0f)" % [id, quoted, peak])
		await _shot("jump_%s_result" % id)
		await _wait(3.5)
	# A rewind (real key) while a jump is armed ends the attempt.
	var ev2 := _ev("dj_hedgerow")
	var road2 := _road(ev2)
	var s2 := float(ev2["gates"][0]) - 60.0
	Game.main.teleport_to({"position": road2.surface_point(s2, 0.0), "forward": road2.flat_tangent_at(s2)})
	await _wait_streamed()
	Game.player_car.freeze = false
	var f2 := RoadFollower.new()
	f2.setup(road2, s2, 1, 0.0)
	f2.target_speed = 70.0 / 3.6
	var t2 := 0.0
	while t2 < 20.0 and mgr.get_session_id() != "dj_hedgerow":
		await get_tree().physics_frame
		t2 += get_physics_process_delta_time()
		f2.drive(Game.player_car, get_physics_process_delta_time())
	var armed: bool = mgr.get_session_id() == "dj_hedgerow"
	_notes.clear()
	Game.main.car_input.enabled = true
	_key(KEY_REWIND, true)
	await _wait(0.5)
	_key(KEY_REWIND, false)
	await get_tree().physics_frame
	Game.main.car_input.enabled = false
	var note := ""
	for n in _notes:
		if n.contains("Rewind used"):
			note = n
	_check(armed and mgr.get_session_id() == "" and note != "", "rewind while a jump is armed ends it (%s)" % note)


# ------------------------------------------------------------------ s19 (round 3): rivals vs oncoming traffic

## Repeated race starts with traffic (--runs, --secs per run; --traffic=1.0, the race caps it to 0.15). For every rival
## and every oncoming vehicle 0-15 m in front of it: the rival's left body edge against the centre line ("conflict"
## while it is in the oncoming half), both standing nose to nose ("stand-off"); traffic standing in front of a rival
## that faces it ("frozen"); rivals without progress after the grid ("stall").
func _standoff_scenario() -> void:
	var id := _arg("id", "rc_highmoor")
	var runs := int(_arg("runs", "4"))
	var secs := float(_arg("secs", "35"))
	var tot := {"meets": 0, "conflict": 0.0, "standoff": 0.0, "frozen": 0.0, "stall": 0.0, "edge": INF}
	var started := 0
	for run in runs:
		var act: RefCounted = await _to_running(id)
		if act == null:
			# The test driver can collide with traffic (density 1.0 between races) on its way to the arch.
			_p("run %d: race not started (test driver held up on the way), skipped" % run)
			Game.activities.cancel_session("test")
			await _wait(1.0)
			continue
		started += 1
		var opp: RefCounted = act.get("opponents")
		var road: RoadNetwork.Road = opp.get("road")
		var d: int = opp.get("dir")
		var f := _player_follower(road, d, float(_arg("kmh", "0")))
		var t := 0.0
		var met: Dictionary = {}
		var conflict: Dictionary = {}
		var standoff: Dictionary = {}
		var frozen: Dictionary = {}
		var hist: Dictionary = {}
		var stall: Dictionary = {}
		var r := {"meets": 0, "conflict": 0.0, "standoff": 0.0, "frozen": 0.0, "stall": 0.0, "edge": INF}
		_p("---- standoff run %d: %s, traffic setting %.2f effective %.2f" % [run, id, Game.traffic.get_density(), Game.traffic.effective_density()])
		while t < secs and Game.activities.get_session_id() == id:
			await get_tree().physics_frame
			var dt := get_physics_process_delta_time()
			t += dt
			var car := Game.player_car
			if f.target_speed > 1.0:
				_player_pass(f, car, road)
			f.drive(car, dt)
			var cars: Array = opp.get("cars")
			var fl: Array = opp.get("followers")
			var veh: Array = Game.traffic.get("vehicles")
			for k in cars.size():
				var rc: CarController = cars[k]
				if not is_instance_valid(rc):
					continue
				var rf: RoadFollower = fl[k]
				var lat: float = opp.call("_lat", rc.global_position, rf.s)
				var edge := lat - rc.data.body_size.x * 0.5
				var fwd := road.flat_tangent_at(rf.s) * d
				for v: RefCounted in veh:
					var vp: Vector3 = v.get("position")
					var rel := vp - rc.global_position
					if absf(rel.y) > 5.0 or (v.get("heading") as Vector3).dot(fwd) > -0.5:
						continue
					var along := Vector3(rel.x, 0.0, rel.z).dot(fwd)
					var vlat: float = opp.call("_lat", vp, opp.call("_project", vp, rf.s + d * along))
					var key := "%d:%d" % [k, int(v.get("uid"))]
					if along > -2.0 and along < 15.0 + rc.data.body_size.z * 0.5 and vlat < 0.5 and vlat > -road.width * 0.5 - 2.0:
						if not met.has(key):
							met[key] = true
							r["meets"] += 1
						r["edge"] = minf(r["edge"], edge)
						if edge < -0.05:
							if not conflict.has(key) or fmod(float(conflict[key]), 0.5) < dt:
								_p("CONFLICT run %d t=%.2f R%d s %.0f lat %.2f edge %.2f %.0f km/h cur %.2f lane_off %.2f swing %d | traffic #%d %s along %.1f lat %.2f %.0f km/h (%.1f s)" % [run, t, k + 1, rf.s, lat, edge,
									rc.get_speed_kmh(), (opp.get("_cur") as PackedFloat32Array)[k], rf.lane_offset, int((opp.get("_swing") as PackedFloat32Array)[k]),
									int(v.get("uid")), "PHYS" if int(v.get("mode")) == 1 else "kin", along, vlat, float(v.get("speed")) * 3.6, float(conflict.get(key, 0.0))])
							conflict[key] = float(conflict.get(key, 0.0)) + dt
							r["conflict"] = maxf(r["conflict"], conflict[key])
							if rc.speed_ms < 0.5 and float(v.get("speed")) < 0.5:
								standoff[key] = float(standoff.get(key, 0.0)) + dt
								r["standoff"] = maxf(r["standoff"], standoff[key])
								if fmod(standoff[key], 2.0) < dt:
									_p("STANDOFF run %d t=%.1f R%d s %.0f lat %.2f edge %.2f vs traffic #%d %s along %.1f lat %.2f (%.1f s)" % [run, t, k + 1, rf.s, lat, edge,
										int(v.get("uid")), "PHYS" if int(v.get("mode")) == 1 else "kin", along, vlat, standoff[key]])
				# Stall: under 2 m of progress in 3 s after the grid.
				var h: Array = hist.get(k, [])
				h.append(Vector2(t, rf.s))
				while h.size() > 1 and t - (h[0] as Vector2).x > 3.0:
					h.pop_front()
				hist[k] = h
				var prog := absf(rf.s - (h[0] as Vector2).y)
				if t > 6.0 and t - (h[0] as Vector2).x > 2.9 and prog < 2.0:
					stall[k] = float(stall.get(k, 0.0)) + dt
					r["stall"] = maxf(r["stall"], stall[k] + 3.0)
				else:
					stall[k] = 0.0
			# Traffic standing in front of a rival that faces it.
			for v2: RefCounted in veh:
				var u := int(v2.get("uid"))
				var held := false
				if float(v2.get("speed")) < 0.3:
					var hd: Vector3 = v2.get("heading")
					for rc2: CarController in Game.activities.get_ai_cars():
						var rr := rc2.global_position - (v2.get("position") as Vector3)
						var fd := rr.dot(hd)
						if fd > 0.0 and fd < 15.0 and absf(rr.dot(Vector3(-hd.z, 0.0, hd.x))) < 3.5 and (-rc2.global_basis.z).dot(hd) < -0.5:
							held = true
				frozen[u] = float(frozen.get(u, 0.0)) + dt if held else 0.0
				r["frozen"] = maxf(r["frozen"], frozen[u])
		_p("run %d: %d oncoming meets, min rival edge %.2f m, longest conflict %.1f s, longest stand-off %.1f s, traffic frozen in front of a rival %.1f s, longest rival stall %.1f s, recoveries %s" % [run,
			r["meets"], r["edge"], r["conflict"], r["standoff"], r["frozen"], r["stall"], str(opp.get("recoveries"))])
		tot["meets"] += r["meets"]
		for key2: String in ["conflict", "standoff", "frozen", "stall"]:
			tot[key2] = maxf(tot[key2], r[key2])
		tot["edge"] = minf(tot["edge"], r["edge"])
		Game.activities.cancel_session("test")
		await _wait(1.0)
	_check(started >= maxi(runs - 1, 1), "race started in %d of %d runs" % [started, runs])
	_p("STANDOFF TOTAL %d runs: %d meets, min edge %.2f m, conflict %.1f s, stand-off %.1f s, frozen %.1f s, stall %.1f s" % [runs, tot["meets"],
		tot["edge"], tot["conflict"], tot["standoff"], tot["frozen"], tot["stall"]])
	_check(tot["standoff"] < 1.0, "no rival / oncoming-traffic stand-off (longest %.1f s)" % tot["standoff"])
	_check(tot["conflict"] < 0.75, "rivals back in their own half before oncoming traffic arrives (longest overlap %.1f s, min edge %.2f m)" % [tot["conflict"], tot["edge"]])
	_check(tot["frozen"] < 4.0, "no traffic left standing in front of a facing rival (longest %.1f s)" % tot["frozen"])
	_check(tot["stall"] < 8.0, "no rival stalled after the grid (longest %.1f s)" % tot["stall"])


## Deterministic stand-off: rival 1 stands across the centre line (--lat, travel-relative) at --s0 with an oncoming
## traffic car (--type, 0 = hatch) --gap metres in front of it, the other rivals 400 m further on. The player waits on
## the grid (--near=1: 35 m behind rival 1, so the traffic car runs physics). Both must get going and pass each other.
func _facing_scenario() -> void:
	var id := "rc_highmoor"
	var act: RefCounted = await _to_running(id)
	if act == null:
		_check(false, "race started")
		return
	var opp: RefCounted = act.get("opponents")
	var road: RoadNetwork.Road = opp.get("road")
	var d: int = opp.get("dir")
	var cars: Array = opp.get("cars")
	var fl: Array = opp.get("followers")
	var near := _arg("near", "0") == "1"
	var s0 := float(_arg("s0", "330"))
	var lat0 := float(_arg("lat", "-0.1"))
	var tm: Node = Game.traffic
	var pf := RoadFollower.new()
	var ps := float(_ev(id)["gates"][0]) + 20.0
	pf.setup(road, ps, d, road.lane_offset(1))
	pf.target_speed = 0.0
	if near:
		ps = s0 - d * 35.0
		var pxf: Transform3D = opp.call("_surface_xf", ps, road.lane_offset(1))
		Game.player_car.place_at(pxf)
		pf.s = ps
	await _wait(0.5)
	var r1: CarController = cars[0]
	var line: float = (opp.get("_line") as PackedFloat32Array)[0]
	var xf: Transform3D = opp.call("_surface_xf", s0, lat0)
	r1.place_at(xf)
	(fl[0] as RoadFollower).s = s0
	(fl[0] as RoadFollower).lane_offset = line
	for k in range(1, cars.size()):
		var xk: Transform3D = opp.call("_surface_xf", s0 + d * (400.0 + 15.0 * k), (opp.get("_line") as PackedFloat32Array)[k])
		(cars[k] as CarController).place_at(xk, -xk.basis.z * 20.0)
		(fl[k] as RoadFollower).s = s0 + d * (400.0 + 15.0 * k)
	var lane: Object = null
	for l: Object in (tm.get("graph").get("lanes_by_road") as Dictionary)[road.idx]:
		if int(l.get("dir")) == -d and int(l.get("k")) == 1:
			lane = l
	var ti := int(_arg("type", "0"))
	var gap := float(_arg("gap", "4"))
	var hl: float = r1.data.body_size.z * 0.5
	var v: RefCounted = tm.call("_new_vehicle", ti, lane, s0)
	# Nose `gap` metres in front of the rival's nose (the lane runs the other way: s grows toward the rival's travel).
	v.set("s", s0 + d * (hl + gap + float(v.get("length")) * 0.5))
	v.set("speed", float(_arg("vkmh", "0")) / 3.6)
	var kx: Transform3D = v.call("kinematic_transform")
	v.set("position", kx.origin)
	v.set("heading", -kx.basis.z)
	(v.get("visual") as Node3D).transform = kx
	_p("facing: R1 at s %.0f lat %.2f (own line %.2f), traffic #%d %s at s %.1f, player %s, recoveries %s" % [s0, lat0, line, int(v.get("uid")),
		str(v.get("data").get("id")), float(v.get("s")), "35 m behind" if near else "on the grid", str(opp.get("recoveries"))])
	var t := 0.0
	var passed_t := -1.0
	var shot := 0
	var min_clear := INF
	while t < float(_arg("secs", "14")):
		await get_tree().physics_frame
		var dt := get_physics_process_delta_time()
		t += dt
		pf.drive(Game.player_car, dt)
		if not is_instance_valid(r1):
			break
		var rf: RoadFollower = fl[0]
		var vp: Vector3 = v.get("position")
		var along := (vp - r1.global_position).dot(road.flat_tangent_at(rf.s) * d)
		var lat_r: float = opp.call("_lat", r1.global_position, rf.s)
		var lat_v: float = opp.call("_lat", vp, opp.call("_project", vp, rf.s + d * along))
		var gap_lat := lat_r - lat_v - r1.data.body_size.x * 0.5 - float(v.get("half_width"))
		if absf(along) < hl + float(v.get("length")) * 0.5 - 0.3:
			min_clear = minf(min_clear, gap_lat)
		if passed_t < 0.0 and along < -(hl + float(v.get("length")) * 0.5):
			passed_t = t
			_p("facing: passed each other at t=%.1f (R1 s %.0f lat %.2f, traffic lat %.2f)" % [t, rf.s, lat_r, lat_v])
		var step := float(_arg("logstep", "1.0"))
		if fmod(t, step) < dt:
			_p("  t=%.1f R1 s %.1f lat %.2f %.0f km/h lim %.1f gap %.1f backoff %.1f steer %.2f gear %d | traffic %s along %.1f lat %.2f %.0f km/h v_target %.1f lead_gap %.1f pass_cap %.1f nudge %.2f" % [t, rf.s, lat_r,
				r1.get_speed_kmh(), rf.obstacle_limit, (opp.get("_lim_gap") as PackedFloat32Array)[0], (opp.get("_backoff") as PackedFloat32Array)[0], r1.in_steer, r1.gear,
				"PHYS" if int(v.get("mode")) == 1 else "kin", along, lat_v, float(v.get("speed")) * 3.6, float(v.get("v_target")), float(v.get("lead_gap")),
				float(v.get("pass_cap")), float(v.get("nudge")) if "nudge" in v else 0.0])
		if shot < 3 and t > 1.0 + shot * 3.0:
			shot += 1
			await _overhead(r1.global_position, "%s_facing_%d" % [_arg("tag", "near" if near else "far"), shot])
		if passed_t >= 0.0 and t > passed_t + 2.0:
			break
	var rec: PackedInt32Array = opp.get("recoveries")
	_p("facing: result passed at %.1f s, min side clearance while alongside %.2f m, R1 recoveries %d" % [passed_t, min_clear, rec[0]])
	# A rival deep in the oncoming half nose to nose with a coach has to back up ~8 m first (about 10 s in all).
	_check(passed_t >= 0.0 and passed_t < 12.0, "rival and oncoming car get past each other (after %.1f s)" % passed_t)
	_check(rec[0] == 0, "without a recovery teleport (%d)" % rec[0])
	_check(min_clear > -0.05, "no body overlap while passing (min side clearance %.2f m)" % min_clear)
	Game.activities.cancel_session("test")


func _overhead(at: Vector3, n: String) -> void:
	var cam := Camera3D.new()
	add_child(cam)
	cam.global_position = at + Vector3(0.5, 26.0, 0.5)
	cam.look_at(at, Vector3.FORWARD)
	cam.fov = 50.0
	cam.make_current()
	await get_tree().process_frame
	await _shot(n)
	Game.camera_rig.camera.make_current()
	cam.queue_free()


# ------------------------------------------------------------------ s20: rival lamps at night

func _rival_lamps(opp: RefCounted) -> Dictionary:
	var lit := 0
	var beams := 0
	var head := INF
	var tail := INF
	var n := 0
	for rc: CarController in opp.get("cars"):
		if not is_instance_valid(rc):
			continue
		n += 1
		var vis := rc.get_node("Visual") as CarVisuals
		if rc.headlights_on:
			lit += 1
		var on := 0
		for l in vis.headlights:
			if l.visible and l.light_energy > 0.5:
				on += 1
		if on >= 2:
			beams += 1
		for m: StandardMaterial3D in vis.lens.get("head", []):
			head = minf(head, m.emission_energy_multiplier)
		for m2: StandardMaterial3D in vis.lens.get("tail", []):
			tail = minf(tail, m2.emission_energy_multiplier)
	return {"n": n, "lit": lit, "beams": beams, "head": head, "tail": tail}


func _nightlights_scenario() -> void:
	var id := "rc_highmoor"
	Game.set_time_of_day(22.5)
	Game.set_time_scale(0.0)
	await _wait(1.0)
	var mgr: Node = Game.activities
	var act: RefCounted = mgr.by_id[id]
	var ev := _ev(id)
	var road := _road(ev)
	mgr.teleport_to_activity(id, 90.0)
	await _wait_streamed()
	var car := Game.player_car
	car.freeze = false
	var f := RoadFollower.new()
	f.setup(road, float(ev["gates"][0]) - 90.0, 1, road.lane_offset(1))
	f.target_speed = 45.0 / 3.6
	var t := 0.0
	var grid: Dictionary = {}
	while t < 60.0 and int(act.get("state")) < 3:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		var st := int(act.get("state"))
		if st == 1:
			f.target_speed = 0.0
		if st < 2:
			f.drive(car, get_physics_process_delta_time())
		elif grid.is_empty() and float(act.get("_count")) < 1.5:
			grid = _rival_lamps(act.get("opponents"))
			_p("NIGHT GRID (countdown): %s, lights_needed %s" % [str(grid), str(Game.env.call("lights_needed"))])
			# From in front of the grid, looking back at the rivals.
			var cam := Camera3D.new()
			add_child(cam)
			var fwd := road.flat_tangent_at(float(ev["gates"][0]) + 20.0)
			cam.global_position = car.global_position + fwd * 14.0 + Vector3.UP * 3.0
			cam.look_at(car.global_position - fwd * 14.0)
			cam.make_current()
			await get_tree().process_frame
			await _shot("night_grid_from_front")
			Game.camera_rig.camera.make_current()
			cam.queue_free()
	if int(act.get("state")) != 3:
		_check(false, "race started")
		return
	car.in_brake = 0.0
	car.in_handbrake = 1.0
	var opp: RefCounted = act.get("opponents")
	var pf := _player_follower(road, 1, 80.0)
	t = 0.0
	var race: Dictionary = {}
	while t < 12.0:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		pf.drive(car, get_physics_process_delta_time())
		if t > 8.0 and race.is_empty():
			race = _rival_lamps(opp)
			_p("NIGHT RACE (t=%.0f): %s" % [t, str(race)])
			await _rival_cam(opp, 0, "night_race_rival1_behind")
	_check(int(grid.get("n", 0)) == 3 and int(grid["lit"]) == 3 and int(grid["beams"]) == 3 and float(grid["head"]) >= 5.0 and float(grid["tail"]) >= 2.0,
		"night grid: all rivals lit (%d/%d headlights_on, %d with beams, head lens %.2f, tail lens %.2f)" % [int(grid.get("lit", 0)), int(grid.get("n", 0)),
		int(grid.get("beams", 0)), float(grid.get("head", 0.0)), float(grid.get("tail", 0.0))])
	_check(int(race.get("n", 0)) > 0 and int(race["lit"]) == int(race["n"]) and int(race["beams"]) == int(race["n"]),
		"night race: all rivals lit (%d/%d, beams %d)" % [int(race.get("lit", 0)), int(race.get("n", 0)), int(race.get("beams", 0))])
	# Daylight: lamps off again (the rivals are on open road, not in a tunnel).
	Game.set_time_of_day(12.0)
	Game.set_weather("clear", true)
	await _wait(1.5)
	var day := _rival_lamps(opp)
	_p("NOON: %s" % str(day))
	_check(int(day.get("lit", 1)) == 0 and int(day.get("beams", 1)) == 0, "clear noon: rival lamps off (%d lit)" % int(day.get("lit", -1)))
	Game.set_time_scale(1.0)
	Game.activities.cancel_session("test")


# ------------------------------------------------------------------ s21: rivals after the race

func _release_scenario() -> void:
	var how := _arg("how", "finish")
	var id := _arg("id", "rc_coast")
	var ev := _ev(id)
	var road := _road(ev)
	var act: RefCounted = await _to_running(id)
	if act == null:
		_check(false, "%s started" % id)
		return
	var opp: RefCounted = act.get("opponents")
	var car := Game.player_car
	var f := _player_follower(road, 1, float(_arg("kmh", "0")))
	var t := 0.0
	# Race a little so the field spreads out round the player (rivals ahead and behind).
	var race_secs := float(_arg("after", "14"))
	# --wait=<s>: the player holds on the grid first, so the rivals lead (they are then in front of the camera).
	var hold := float(_arg("wait", "0"))
	while t < race_secs:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		f.target_speed = 0.0 if t < hold else (float(_arg("kmh", "0")) / 3.6 if float(_arg("kmh", "0")) > 0.0 else car.data.top_speed_kmh * 0.9 / 3.6)
		_player_pass(f, car, road)
		f.drive(car, get_physics_process_delta_time())
	var cars: Array = (opp.get("cars") as Array).duplicate()
	_p("before %s at t=%.1f: %s" % [how, t, _rival_line(opp, car)])
	var car_index0 := Game.current_car_index
	if how == "cancel":
		# Same call as the garage CARS page: the session is cancelled ("car changed").
		Game.spawn_car((car_index0 + 1) % Game.get_car_catalog().size(), true)
		car = Game.player_car
	else:
		act.call("_finish_race", car)
	_p("session after %s: '%s', opponents released %s" % [how, Game.activities.get_session_id(), str(opp.get("released"))])
	var stop := RoadFollower.new()
	stop.setup(road, f.s, 1, road.lane_offset(1))
	stop.target_speed = 0.0
	var t2 := 0.0
	var gone_in_view := 0
	var gone := 0
	var seen: Dictionary = {}
	var min_v: Dictionary = {}
	var shots := [1.5, 2.5, 4.0]
	var fixed: Camera3D = null
	while t2 < float(_arg("watch", "45")):
		await get_tree().physics_frame
		var dt := get_physics_process_delta_time()
		t2 += dt
		stop.drive(car, dt)
		if fixed == null and t2 > 1.0:
			# Fixed camera above / behind the stopped player looking down the road (rivals in front and behind).
			fixed = Camera3D.new()
			add_child(fixed)
			var fw := -car.global_basis.z
			fw.y = 0.0
			fixed.global_position = car.global_position - fw.normalized() * 30.0 + Vector3.UP * 9.0
			fixed.look_at(car.global_position + fw.normalized() * 30.0)
			fixed.fov = 65.0
		for k in cars.size():
			var key := str(k)
			if not is_instance_valid(cars[k]) or (cars[k] as CarController).is_queued_for_deletion():
				if not seen.has("gone" + key):
					seen["gone" + key] = true
					gone += 1
					var was_in_view := bool(seen.get("view" + key, false))
					if was_in_view:
						gone_in_view += 1
					_p("+%.2f s R%d removed (in view the frame before: %s, %.0f m from the player)" % [t2, k + 1, was_in_view, float(seen.get("dist" + key, -1.0))])
				continue
			var rc: CarController = cars[k]
			var p := rc.global_position
			seen["view" + key] = bool(opp.call("_in_view", p + Vector3.UP * 0.7))
			seen["dist" + key] = p.distance_to(car.global_position)
			if t2 > 0.5 and t2 < 4.0:
				min_v[key] = minf(float(min_v.get(key, INF)), rc.forward_speed)
		if fmod(t2, 1.0) < dt:
			var parts := PackedStringArray()
			for k in cars.size():
				if is_instance_valid(cars[k]) and not (cars[k] as CarController).is_queued_for_deletion():
					var rc2: CarController = cars[k]
					parts.append("R%d %.0f km/h %.0f m %s" % [k + 1, rc2.forward_speed * 3.6, rc2.global_position.distance_to(car.global_position),
						"VIEW" if bool(seen.get("view" + str(k), false)) else "unseen"])
			_p("+%.0f s %s" % [t2, ", ".join(parts)])
		if not shots.is_empty() and t2 >= float(shots[0]) and fixed != null:
			fixed.make_current()
			await get_tree().process_frame
			await _shot("release_%s_%.1fs_fixed" % [how, float(shots[0])])
			Game.camera_rig.camera.make_current()
			await get_tree().process_frame
			await _shot("release_%s_%.1fs_chase" % [how, float(shots[0])])
			shots.pop_front()
		if gone == cars.size():
			break
	if fixed != null:
		fixed.queue_free()
	var slow := PackedStringArray()
	var rolling_back := 0
	for key2: String in min_v.keys():
		slow.append("R%d %.0f km/h" % [int(key2) + 1, float(min_v[key2]) * 3.6])
		if float(min_v[key2]) < 0.0:
			rolling_back += 1
	_p("after %s: %d of %d rivals left within %.0f s, %d removed while in view; min forward speed 0.5-4 s after: %s" % [how, gone, cars.size(), t2,
		gone_in_view, ", ".join(slow)])
	_check(gone_in_view == 0, "%s: no rival removed while the camera could see it (%d)" % [how, gone_in_view])
	_check(rolling_back == 0, "%s: no rival rolls backwards after the race (%d)" % [how, rolling_back])
	_check(gone == cars.size(), "%s: every rival left eventually (%d of %d within %.0f s)" % [how, gone, cars.size(), t2])
	if how == "cancel":
		Game.spawn_car(car_index0, true)
