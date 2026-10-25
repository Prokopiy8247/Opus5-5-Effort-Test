extends Node
## Playtest 3 vehicle fixes checked in the real game (main scene, real W/S/Q input where the repro used it):
##   s16 braking line keeps the ring at side-road junctions, s17 manual downshifts that would over-rev are
##   refused, s18 reverse is speed-limited.
##   Godot_console.exe --audio-driver Dummy --path <project> --resolution 1920x1080 res://tools/tests/fix4_vehicle_verify.tscn -- --part=brakeline|downshift|reverse|all
## --line-script=res://<copy of an older braking_line.gd> measures that script at the same junctions (no checks).
## Prints "[fix4v] PASS|FAIL <check>" lines and "[fix4v] failures: N"; screenshots in qa_output/fix4_vehicle/.
## Changes no user settings (live traffic density only, braking line restored).

const QaAutopilot := preload("res://scripts/main/qa_autopilot.gd")
const OUT := "res://qa_output/fix4_vehicle"
const JUNCTIONS := [[939, "vale_north"], [660, "riverside_n"], [1785, "expressway"], [8001, "lake_road"], [9498, "plateau_stage"],
	[1077, "millbrook_st"], [4956, "keep_road"]]

var main: Node
var fails := 0
## Steering-only autopilot (W/S/Q come from real input through CarInput).
var _steer: QaAutopilot = null
var _drive: QaAutopilot = null
var _t := 0.0


func _ready() -> void:
	SaveGame.enabled = false
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(main)
	_run.call_deferred()


func _arg(key: String, default: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--" + key + "="):
			return a.substr(key.length() + 3)
		if a == "--" + key:
			return "1"
	return default


func _check(label: String, ok: bool, detail: String) -> void:
	print("[fix4v] %s %s  %s" % ["PASS" if ok else "FAIL", label, detail])
	if not ok:
		fails += 1


func _physics_process(delta: float) -> void:
	_t += delta
	var car := Game.player_car
	if car == null:
		return
	if _drive != null:
		_drive.drive(car)
	elif _steer != null:
		var thr := car.in_throttle
		var brk := car.in_brake
		_steer.drive(car)
		car.in_throttle = thr
		car.in_brake = brk
		if car.forward_speed < 0.5:
			car.in_steer = 0.0


func _settle() -> void:
	var w := Game.world as World
	var t0 := Time.get_ticks_msec()
	await get_tree().process_frame
	while (w.terrain.pending_count() > 0 or not w.is_ready_near()) and Time.get_ticks_msec() - t0 < 20000:
		await get_tree().process_frame
	for i in 60:
		await get_tree().physics_frame


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [OUT, name])


func _run() -> void:
	while main.get("is_loading"):
		await get_tree().process_frame
	if Game.traffic != null and Game.traffic.has_method("set_density"):
		Game.traffic.call("set_density", 0.0)
	Game.set_time_of_day(12.0)
	Game.set_weather("clear", true)
	(Game.camera_rig as CameraRig).set_mode(CameraRig.Mode.CHASE_FAR, false)
	var part := _arg("part", "brakeline")
	if part in ["brakeline", "all"]:
		await _part_brakeline()
	if part in ["downshift", "all"]:
		await _part_downshift()
	if part in ["reverse", "all"]:
		await _part_reverse()
	if Game.traffic != null and Game.traffic.has_method("set_density"):
		Game.traffic.call("set_density", float(Settings.get_value("traffic_density", 0.6)))
	print("[fix4v] failures: %d" % fails)
	get_tree().quit(0)


func _road(id: String) -> RoadNetwork.Road:
	return (Game.world as World).data.network.get_road(id)


func _place(road: RoadNetwork.Road, s: float, ap: QaAutopilot) -> void:
	ap.setup((Game.world as World).data.network, road, s)
	main.call("teleport_to", {"position": ap.lane_point(s), "forward": road.flat_tangent_at(s)})
	await _settle()


# ------------------------------------------------------------------ s16 braking line

func _part_brakeline() -> void:
	var alt := _arg("line-script", "")
	var old := alt != ""
	var tag := "alt" if old else "new"
	Game.spawn_car(Game.find_car_index("kestrel_r4"), true)
	await get_tree().physics_frame
	main.car_input.enabled = false
	var prev_line: bool = bool(Settings.get_value("braking_line", false))
	Settings.set_value("braking_line", true, false)
	var bl := main.get_node(^"BrakingLine") as MeshInstance3D
	if old:
		# Another braking line script (e.g. a copy of the pre-fix version) instead of the game's, same measurements.
		bl.process_mode = Node.PROCESS_MODE_DISABLED
		bl.visible = false
		bl = (load(alt) as Script).new() as MeshInstance3D
		main.add_child(bl)
	var net := (Game.world as World).data.network
	var ring := _road("ring")
	var total_bad := 0
	for j: Array in JUNCTIONS:
		var js: float = float(j[0])
		var child: String = j[1]
		_drive = QaAutopilot.new()
		await _place(ring, js - 160.0, _drive)
		_drive.target_speed = 80.0 / 3.6
		var frames := 0
		var missing := 0
		var off_ring := 0
		var switches: Array[String] = []
		var last := "ring"
		var shots := 0
		var t0 := _t
		while _drive.s < js + 40.0 and _t - t0 < 40.0:
			await RenderingServer.frame_post_draw
			var cs := _drive.s
			if cs < js - 25.0 or Game.player_car.speed_ms < 4.0:
				continue
			frames += 1
			var im := bl.mesh as ImmediateMesh
			var on := "-"
			if im.get_surface_count() == 0:
				missing += 1
			else:
				var verts: PackedVector3Array = im.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
				var near := net.nearest(verts[verts.size() / 2], 25.0)
				on = (near["road"] as RoadNetwork.Road).id if not near.is_empty() else "?"
				if on != "ring":
					off_ring += 1
			var cur: Variant = bl.get("_road")
			var line_road := (cur as RoadNetwork.Road).id if cur != null else on
			if line_road != last:
				switches.append("%s->%s @s%d" % [last, line_road, int(cs)])
				last = line_road
			if (shots == 0 and cs >= js - 3.0) or (shots == 1 and cs >= js + 4.0):
				shots += 1
				get_viewport().get_texture().get_image().save_png("%s/brakeline_%s_s%d_%d.png" % [OUT, tag, int(js), shots])
		print("[fix4v] %s ring s=%d (%s): %d frames, line missing %d, ribbon off the ring %d, line road switches %s, %.0f km/h" % [
			tag, int(js), child, frames, missing, off_ring, str(switches), Game.player_car.get_speed_kmh()])
		var bad := missing + off_ring + switches.size()
		total_bad += bad
		if not old:
			_check("s16 line stays on the ring through the %s junction (s=%d)" % [child, int(js)], bad == 0 and frames > 20,
				"frames=%d missing=%d off_ring=%d switches=%s" % [frames, missing, off_ring, str(switches)])
	print("[fix4v] %s total glitch frames/switches: %d" % [tag, total_bad])
	# Turning off the ring onto a side road: the line follows the car onto it.
	if not old:
		# vale_north starts on the ring at s=939: autopilot on the ring up to the mouth, then onto vale_north.
		var vn := _road("vale_north")
		_drive = QaAutopilot.new()
		await _place(ring, 939.0 - 120.0, _drive)
		_drive.target_speed = 45.0 / 3.6
		var t1 := _t
		while _drive.s < 939.0 - 12.0 and _t - t1 < 30.0:
			await get_tree().physics_frame
		_drive.setup(net, vn, 0.0)
		_drive.target_speed = 45.0 / 3.6
		var on_side := 0
		var seen := 0
		var t2 := _t
		while _drive.s < 60.0 and _t - t2 < 20.0:
			await RenderingServer.frame_post_draw
			if _drive.s > 25.0:
				seen += 1
				var cur2: Variant = bl.get("_road")
				if cur2 != null and (cur2 as RoadNetwork.Road).id == "vale_north" and (bl.mesh as ImmediateMesh).get_surface_count() == 1:
					on_side += 1
		await _shot("brakeline_new_turnoff_vale_north")
		_check("s16 line follows the car onto a side road it turns into", seen > 10 and on_side == seen, "on vale_north %d of %d frames" % [on_side, seen])
		# r2-q5 kept: towards the T-junction at the end of millbrook_st (87 degree turn onto the ring) the line
		# stays on the side road and its end turns red at 60 km/h.
		var ms := _road("millbrook_st")
		_drive = QaAutopilot.new()
		await _place(ms, ms.length - 170.0, _drive)
		_drive.target_speed = 60.0 / 3.6
		var kept := 0
		var red_end := 0
		var near_end := 0
		var t3 := _t
		while _drive.s < ms.length - 22.0 and _t - t3 < 30.0:
			await RenderingServer.frame_post_draw
			if _drive.s < ms.length - 60.0 or Game.player_car.speed_ms < 4.0:
				continue
			near_end += 1
			var cur3: Variant = bl.get("_road")
			var im3 := bl.mesh as ImmediateMesh
			if cur3 != null and (cur3 as RoadNetwork.Road).id == "millbrook_st" and im3.get_surface_count() == 1:
				kept += 1
				var cols: PackedColorArray = im3.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
				var c_end := cols[cols.size() - 1]
				if c_end.r > 0.9 and c_end.g < 0.5:
					red_end += 1
		await _shot("brakeline_new_tjunction_millbrook_st")
		_check("r2-q5 line runs to the T-junction and its end is red", near_end > 10 and kept == near_end and red_end == near_end,
			"on millbrook_st %d / red end %d of %d frames, %.0f km/h" % [kept, red_end, near_end, Game.player_car.get_speed_kmh()])
	_drive = null
	Settings.set_value("braking_line", prev_line, false)
	main.car_input.enabled = true


# ------------------------------------------------------------------ s17 manual downshift protection

func _tap(action: StringName) -> void:
	await get_tree().physics_frame
	Input.action_press(action)
	for i in 3:
		await get_tree().physics_frame
	Input.action_release(action)


func _part_downshift() -> void:
	var xw := _road("expressway")
	for spec: Array in [["castellan_gt", 6, true], ["castellan_gt", 6, false], ["brute_68", 4, true], ["kestrel_r4", 6, true]]:
		var id: String = spec[0]
		var g0: int = spec[1]
		var lift: bool = spec[2]
		Game.spawn_car(Game.find_car_index(id), true)
		await get_tree().physics_frame
		_steer = QaAutopilot.new()
		await _place(xw, 260.0, _steer)
		var car := Game.player_car
		car.auto_gearbox = false
		var shifts: Array = []
		var refused: Array = []
		var on_gear := func(g: int) -> void: shifts.append([snappedf(_t, 0.01), g, roundi(car.get_speed_kmh()), roundi(car.rpm)])
		var on_ref := func(g: int) -> void: refused.append([snappedf(_t, 0.01), g, roundi(car.get_speed_kmh())])
		car.gear_changed.connect(on_gear)
		car.shift_refused.connect(on_ref)
		car.place_at(car.global_transform, -car.global_basis.z * 190.0 / 3.6, Vector3.ZERO, g0)
		Input.action_press(&"accelerate")
		for i in 72:
			await get_tree().physics_frame
		_t = 0.0
		var kmh0 := car.get_speed_kmh()
		var n := car.data.gear_ratios.size()
		var safe := car.gear
		while safe > 1 and car._road_rpm(safe - 1) <= car.data.redline_rpm:
			safe -= 1
		var expected := maxi(car.gear - 4, safe)
		if lift:
			Input.action_release(&"accelerate")
		for k in 4:
			await _tap(&"gear_down")
			for i in 10:
				await get_tree().physics_frame
		var rpm_max := 0.0
		var limiter := 0
		var shot_done := false
		var t_end := _t + 2.5
		while _t < t_end:
			await get_tree().physics_frame
			rpm_max = maxf(rpm_max, car.rpm)
			if car.limiter_hit:
				limiter += 1
			if not shot_done and _t > 0.79:
				shot_done = true
				await _shot("downshift_%s_%s_after_taps" % [id, "lift" if lift else "held"])
		Input.action_release(&"accelerate")
		car.gear_changed.disconnect(on_gear)
		car.shift_refused.disconnect(on_ref)
		var label := "%s from %d at %.0f km/h, %s" % [id, g0, kmh0, "lift" if lift else "W held"]
		print("[fix4v] downshift %s: shifts %s refused %s; gear %d (expected %d of %d); rpm max %.0f (max_rpm %.0f, redline %.0f); limiter frames %d; now %.0f km/h" % [
			label, str(shifts), str(refused), car.gear, expected, n, rpm_max, car.data.max_rpm, car.data.redline_rpm, limiter, car.get_speed_kmh()])
		_check("s17 over-revving downshifts refused (%s)" % label, car.gear == expected and limiter == 0 and rpm_max < car.data.max_rpm and refused.size() > 0,
			"gear %d expected %d, refused %d, rpm max %.0f / limiter %.0f, limiter frames %d" % [car.gear, expected, refused.size(), rpm_max, car.data.max_rpm, limiter])
		# Slower, a further Q tap is accepted.
		var g1 := car.gear
		Input.action_press(&"brake")
		var tb := 0.0
		while g1 > 1 and car._road_rpm(g1 - 1) > car.data.redline_rpm * 0.9 and tb < 10.0:
			await get_tree().physics_frame
			tb += 1.0 / 120.0
		Input.action_release(&"brake")
		await _tap(&"gear_down")
		for i in 40:
			await get_tree().physics_frame
		_check("s17 downshift accepted once slow enough (%s)" % id, car.gear == g1 - 1, "gear %d -> %d at %.0f km/h" % [g1, car.gear, car.get_speed_kmh()])
		_steer = null
		car.auto_gearbox = bool(Settings.get_value("auto_gearbox", true))


# ------------------------------------------------------------------ s18 reverse limit

func _part_reverse() -> void:
	var xw := _road("expressway")
	var ids: Array = Game.CAR_IDS.duplicate() if _arg("cars", "all") == "all" else _arg("cars", "").split(",")
	for id: String in ids:
		Game.spawn_car(Game.find_car_index(id), true)
		await get_tree().physics_frame
		_steer = QaAutopilot.new()
		await _place(xw, 260.0, _steer)
		var car := Game.player_car
		car.place_at(car.global_transform, -car.global_basis.z * 100.0 / 3.6, Vector3.ZERO)
		await get_tree().physics_frame
		Input.action_press(&"brake")
		_t = 0.0
		var t_stop := -1.0
		var t_rev := -1.0
		var p_rev := Vector3.ZERO
		var v35 := 0.0
		var d35 := 0.0
		var vmax := 0.0
		var shot := false
		while _t < 20.0:
			await get_tree().physics_frame
			if t_stop < 0.0 and car.forward_speed < 0.3:
				t_stop = _t
			if t_rev < 0.0 and car.gear == -1:
				t_rev = _t
				p_rev = car.global_position
			if t_rev >= 0.0:
				var back := -car.forward_speed * 3.6
				vmax = maxf(vmax, back)
				if v35 == 0.0 and _t - t_rev >= 3.5:
					v35 = back
					d35 = p_rev.distance_to(car.global_position)
				if not shot and _t - t_rev >= 8.0 and id in ["vortex_x", "brute_68", "kestrel_r4"]:
					shot = true
					await _shot("reverse_%s_8s" % id)
				if _t - t_rev >= 8.0:
					break
		var v8 := -car.forward_speed * 3.6
		Input.action_release(&"brake")
		var cap := car.data.reverse_max_kmh
		print("[fix4v] reverse %s: stop after %.2f s, reverse engaged %.2f s after the stop, %.1f km/h at +3.5 s (%.1f m), %.1f km/h at +8 s (max %.1f, limit %.0f), rpm %.0f" % [
			id, t_stop, t_rev - t_stop, v35, d35, v8, vmax, cap, car.rpm])
		_check("s18 reverse limited (%s)" % id, t_rev >= 0.0 and vmax <= cap + 1.5 and v8 >= cap - 3.0 and cap >= 25.0 and cap <= 35.0,
			"max %.1f km/h, +8 s %.1f km/h, limit %.0f" % [vmax, v8, cap])
		_steer = null
		for i in 30:
			await get_tree().physics_frame
