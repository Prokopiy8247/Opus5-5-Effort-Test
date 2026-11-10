extends Node
## Pedestrian safety / behaviour checks in the real game:
##   Godot_console.exe --path . res://tools/tests/pedestrians_verify.tscn -- --part=walk|sit|bike|insure|shots|all [--speeds=30,80,160,350]
## A car is driven (velocity forced every physics tick) straight at a person on the expressway at several speeds;
## per run it checks: no impact signal, no damage, no credits change, the person ends up clear of the car's body,
## runs (reacts) before the car arrives, never teleports in view and goes back to its activity afterwards.
## "insure": the car is placed right on top of a person (still / moving) -> instant, harmless relocation.
## Prints "[ped] PASS|FAIL ..." and "failures: N" (exit code 1 on failure). Screenshots: qa_output/task3/.

const ROAD := "expressway"
const S0 := 590.0
const CAR_HALF_W := 1.1
const CAR_HALF_L := 2.6

var main: Node
var fails := 0
var car: CarController
var mgr: Node
var fwd := Vector3.FORWARD
var driving := false
var drive_v := 0.0
var hold := true
var ped: RefCounted
var impacts := 0
var min_l := INF
var hit := false
var react_a := INF
var react_t := -1.0
var t_run := 0.0
var max_speed := 0.0
var prev_pos := Vector3.INF
var teleport_seen := false
var pass_done := false
var track := false
var pass_frames := 0
var near_impacts := 0
var base_impacts := {}
var base_damage := {}


func _arg(key: String, default: String) -> String:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--%s=" % key):
			return a.get_slice("=", 1)
	return default


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	SaveGame.enabled = false
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(main)
	_run.call_deferred()


func log_line(s: String) -> void:
	print("[ped] ", s)


func check(ok: bool, what: String) -> void:
	log_line(("PASS " if ok else "FAIL ") + what)
	if not ok:
		fails += 1


func _wait(s: float) -> void:
	await get_tree().create_timer(s).timeout


func _shot(fname: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img != null and not img.is_empty():
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://qa_output/task3"))
		img.save_png("res://qa_output/task3/%s.png" % fname)
		log_line("shot qa_output/task3/%s.png" % fname)


func _on_impact(_strength: float, pos: Vector3) -> void:
	impacts += 1
	if ped != null and pos.distance_to(ped.pos) < 6.0:
		near_impacts += 1


func _physics_process(_dt: float) -> void:
	if car == null:
		return
	if hold:
		car.in_hold = true
		return
	car.in_hold = false
	if driving:
		var v := fwd * drive_v
		v.y = car.linear_velocity.y
		car.linear_velocity = v
		car.in_throttle = 1.0
		car.in_brake = 0.0
	if track and ped != null:
		var d: Vector3 = ped.pos - car.global_position
		var a := d.dot(fwd)
		var l := d.dot(Vector3(-fwd.z, 0, fwd.x))
		if absf(a) < 3.0:
			min_l = minf(min_l, absf(l))
		if absf(a) < CAR_HALF_L + 0.1 and absf(l) < CAR_HALF_W + 0.05:
			hit = true
		if react_t < 0.0 and int(ped.reacted) > 0:
			react_t = t_run
			react_a = a
		t_run += _dt
		if a < -12.0:
			pass_frames += 1
			if pass_frames > 30:
				pass_done = true


func _process(delta: float) -> void:
	if track and ped != null and delta > 0.0:
		if prev_pos != Vector3.INF:
			var sp: float = (ped.pos - prev_pos).length() / delta
			max_speed = maxf(max_speed, sp)
			if sp > 16.0 and (ped.pos - prev_pos).length() > 0.8 and not bool(ped.get_meta(&"insured", false)):
				teleport_seen = true
		prev_pos = ped.pos


func _road_pose() -> Dictionary:
	var road: RoadNetwork.Road = Game.world.data.network.get_road(ROAD)
	var p := road.surface_point(S0, road.lane_offset(1))
	fwd = road.flat_tangent_at(S0)
	return {"position": p, "forward": fwd}


func _place_car() -> void:
	hold = true
	driving = false
	main.teleport_to(_road_pose())
	await _wait(1.0)
	car.linear_velocity = Vector3.ZERO
	car.angular_velocity = Vector3.ZERO


func _spawn_target(kind: String, dist: float) -> void:
	var pos := car.global_position + fwd * dist
	pos.y = Game.world.data.height_at(pos.x, pos.z) + 0.05
	var yaw := atan2(-fwd.x, -fwd.z)
	match kind:
		"walk":
			ped = mgr.spawn_test(0, pos, yaw, 3)
		"jog":
			ped = mgr.spawn_test(1, pos, yaw, 8)
		"sit":
			ped = mgr.spawn_seated(pos, yaw)
		"bike":
			ped = mgr.spawn_test_bike(pos, atan2(-fwd.x, -fwd.z) + PI)


func _approach(kind: String, kmh: float) -> void:
	await _place_car()
	var v := kmh / 3.6
	var dist := v * 2.6 + 25.0
	mgr.clear_all()
	ped = null
	if kind != "none":
		_spawn_target(kind, dist)
	if kind != "none" and ped == null:
		check(false, "%s: could not spawn the test person" % kind)
		return
	impacts = 0
	near_impacts = 0
	min_l = INF
	hit = false
	react_a = INF
	react_t = -1.0
	t_run = 0.0
	max_speed = 0.0
	prev_pos = Vector3.INF
	teleport_seen = false
	pass_done = false
	pass_frames = 0
	var dmg0 := car.damage
	var cr0 := Game.credits
	var ins0 := int(mgr.get_stats()["insurance_events"])
	await _wait(0.4)
	drive_v = v
	car.place_at(car.global_transform, fwd * v, Vector3.ZERO)
	hold = false
	driving = true
	track = true
	var guard := 0.0
	while not pass_done and guard < 25.0:
		await get_tree().process_frame
		guard += get_process_delta_time()
	driving = false
	track = false
	car.linear_velocity = Vector3.ZERO
	hold = true
	var tag := "%s @ %d km/h" % [kind, int(kmh)]
	if kind == "none":
		base_impacts[int(kmh)] = impacts
		base_damage[int(kmh)] = not is_equal_approx(car.damage, dmg0)
		log_line("control run without a person @ %d km/h: impacts %d, damage changed %s" % [int(kmh), impacts, str(base_damage[int(kmh)])])
		return
	var lead_t := (react_a - CAR_HALF_L) / maxf(v, 0.1) if react_t >= 0.0 else -1.0
	log_line("%s: min lateral %.2f m, reacted at %.1f m ahead (%.2f s before arrival), top ped speed %.1f m/s" % [tag, min_l, react_a, lead_t, max_speed])
	check(pass_done, "%s: car passed the person" % tag)
	var bi: int = base_impacts.get(int(kmh), 0)
	var bd: bool = base_damage.get(int(kmh), false)
	check(impacts <= bi, "%s: no impact signal from the person (%d, background without a person %d)" % [tag, impacts, bi])
	check(near_impacts == 0, "%s: no impact signal within 6 m of the person (%d)" % [tag, near_impacts])
	check(bd or is_equal_approx(car.damage, dmg0), "%s: no car damage from the person" % tag)
	check(Game.credits == cr0, "%s: no credits / fine change" % tag)
	check(not hit, "%s: person never inside the car's footprint" % tag)
	check(min_l > CAR_HALF_W + 0.5, "%s: clear of the car body by %.2f m" % [tag, min_l - CAR_HALF_W])
	check(react_t >= 0.0 and lead_t > 0.25, "%s: reacted early enough (%.2f s before arrival)" % [tag, lead_t])
	check(not teleport_seen, "%s: no teleport in view (max %.1f m/s)" % [tag, max_speed])
	check(int(mgr.get_stats()["insurance_events"]) == ins0, "%s: insurance not needed" % tag)
	var back := 0.0
	while back < 14.0 and int(ped.state) != 0:
		await _wait(0.5)
		back += 0.5
	check(int(ped.state) == 0, "%s: person calmed down and returned to the activity (%.1f s)" % [tag, back])


func _insure(moving: bool) -> void:
	await _place_car()
	mgr.clear_all()
	var tag := "insurance (%s)" % ("moving car" if moving else "car spawn")
	var v := 80.0 / 3.6 if moving else 0.0
	var pos := car.global_position + fwd * (3.0 if moving else 0.4)
	pos.y = Game.world.data.height_at(pos.x, pos.z) + 0.05
	var dmg0 := car.damage
	var cr0 := Game.credits
	impacts = 0
	ped = mgr.spawn_test(0, pos, 0.0, 5)
	ped.set_meta(&"insured", true)
	var ins0 := int(mgr.get_stats()["insurance_events"])
	drive_v = v
	hold = false
	driving = moving
	if moving:
		car.place_at(car.global_transform, fwd * v, Vector3.ZERO)
	await _wait(0.5)
	driving = false
	var d: Vector3 = ped.pos - car.global_position
	var a := d.dot(fwd)
	var l := d.dot(Vector3(-fwd.z, 0, fwd.x))
	log_line("%s: after 0.5 s the person is at a=%.1f l=%.1f" % [tag, a, l])
	check(int(mgr.get_stats()["insurance_events"]) > ins0, "%s: insurance relocation happened" % tag)
	check(absf(l) > CAR_HALF_W + 0.5 or absf(a) > CAR_HALF_L + 1.0, "%s: person is clear of the car" % tag)
	check(impacts == 0 and is_equal_approx(car.damage, dmg0) and Game.credits == cr0, "%s: no impact, damage or fine" % tag)
	check(not moving or car.linear_velocity.length() > v * 0.8, "%s: car speed not affected (%.1f m/s)" % [tag, car.linear_velocity.length()])
	car.linear_velocity = Vector3.ZERO
	hold = true


func _run() -> void:
	var t := 0.0
	while bool(main.get("is_loading")) and t < 90.0:
		await _wait(0.5)
		t += 0.5
	car = main.player_car
	mgr = Game.pedestrians
	check(car != null and mgr != null, "game ready (car + pedestrian manager)")
	if car == null or mgr == null:
		get_tree().quit(1)
		return
	car.impact.connect(_on_impact)
	main.car_input.enabled = false
	Game.set_traffic_density(0.0)
	Game.set_time_of_day(12.0)
	Game.set_weather("clear", true)
	mgr.set_auto_spawn(false)
	var part := _arg("part", "all")
	var speeds: Array[float] = []
	for s in _arg("speeds", "30,80,160,350").split(","):
		speeds.append(float(s))
	if part in ["walk", "all"]:
		for sp in speeds:
			await _approach("none", sp)
			await _approach("walk", sp)
		await _approach("jog", 80.0)
	if part in ["insure", "all"]:
		await _insure(false)
		await _insure(true)
	if part in ["sit", "all"]:
		for sp in speeds:
			await _approach("none", sp)
			await _approach("sit", sp)
	if part in ["bike", "all"]:
		for sp in speeds:
			await _approach("none", sp)
			await _approach("bike", sp)
	if part == "shots":
		await _shots()
	if part == "places":
		await _places()
	if part == "lineup":
		await _lineup()
	log_line("failures: %d" % fails)
	get_tree().quit(1 if fails > 0 else 0)


func _shots() -> void:
	hold = false
	Game.set_weather("clear", true)
	mgr.set_auto_spawn(true)
	mgr.spawn_min = 8.0
	mgr.spawn_in_view = true
	Game.set_pedestrian_density(1.0)
	for rid: String in _arg("roads", "millbrook_st,harbour_st").split(","):
		var road: RoadNetwork.Road = Game.world.data.network.get_road(rid)
		var s := road.length * 0.5
		var p := road.surface_point(s, road.lane_offset(1))
		hold = true
		main.teleport_to({"position": p, "forward": road.flat_tangent_at(s)})
		await _wait(6.0)
		log_line("%s: %s" % [rid, str(mgr.get_stats())])
		await _shot("peds_%s" % rid)
		await _wait(4.0)
		await _shot("peds_%s_b" % rid)


func _lineup() -> void:
	var road: RoadNetwork.Road = Game.world.data.network.get_road("millbrook_st")
	var s := road.length * 0.5
	var p := road.surface_point(s, 0.0)
	var f := road.flat_tangent_at(s)
	hold = true
	main.teleport_to({"position": p - f * 9.0, "forward": f})
	await _wait(1.5)
	car.visible = false
	mgr.clear_all()
	mgr.set_auto_spawn(false)
	var right := Vector3(-f.z, 0, f.x)
	var n := int(_arg("looks", "18"))
	for i in n:
		var row := i / 9
		var col := i % 9
		var q := p + right * (float(col - 4) * 1.0) + f * (float(row) * 1.8)
		q.y = Game.world.data.height_at(q.x, q.z) + 0.05
		var kind := 0
		var yaw := atan2(f.x, f.z)
		var e = mgr.spawn_test(kind, q, yaw, i)
		e.top_speed = 0.0
		e.mode = 1
	if _arg("std", "0") == "1":
		var sm := StandardMaterial3D.new()
		sm.vertex_color_use_as_albedo = true
		for ch in mgr.get_children():
			if ch is MultiMeshInstance3D:
				ch.material_override = sm
	await _wait(2.0)
	for i in 3:
		var mm: MultiMesh = mgr._mms[i]
		log_line("look %d: visible %d aabb %s verts %d pos0 %s car %s" % [i, mm.visible_instance_count, str(mm.get_aabb()), mm.mesh.surface_get_array_len(0), str(mm.get_instance_transform(0).origin), str(car.global_position)])
	await _shot("lineup")


func _places() -> void:
	mgr.set_auto_spawn(true)
	mgr.spawn_min = 0.0
	mgr.spawn_in_view = true
	Game.set_pedestrian_density(1.0)
	await _wait(3.0)
	log_line("places: %d, stats %s" % [mgr._spots.size(), str(mgr.get_stats())])
	var shown := {}
	for kind in [2, 5, 4, 3]:
		var best := -1
		for i in mgr._spots.size():
			if int(mgr._spots[i]["kind"]) == kind and not shown.has(i):
				best = i
				break
		if best < 0:
			log_line("no place of kind %d" % kind)
			continue
		shown[best] = true
		var sp: Dictionary = mgr._spots[best]
		var pos: Vector3 = sp["pos"]
		var f := Vector3(sin(float(sp["yaw"])), 0, cos(float(sp["yaw"])))
		hold = true
		main.teleport_to({"position": pos + f * 6.0 + Vector3.UP * 1.0, "forward": -f})
		await _wait(6.0)
		car.visible = false
		for k in 400:
			mgr._spawn_spot(Vector2(pos.x, pos.z))
		var cnt := 0
		for p in mgr.get_peds():
			if Vector2(p.pos.x - pos.x, p.pos.z - pos.z).length() < 15.0:
				cnt += 1
		log_line("kind %d at %s: %d people within 15 m" % [kind, str(pos), cnt])
		await _wait(1.0)
		await _shot("places_kind%d" % kind)
		car.visible = true
