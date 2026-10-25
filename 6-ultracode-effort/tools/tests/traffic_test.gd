extends Node
## Traffic integration test on the real main scene. One scenario per run (keeps runs short):
##   Godot_console.exe --path <project> --resolution 1600x900 res://tools/tests/traffic_test.tscn -- --scenario=ring [--seconds=70] [--traffic-debug]
## Scenarios: junction (festival T-junction, overhead shots), ring / expressway (traffic-aware autopilot drive,
## traffic cam shots; they keep the user's density setting unless --density= is given), block (player stops in lane -> honk), crash (player rams a traffic car at +90 km/h -> hazard,
## then recovered or removed; RESULT line),
## lens (parked cars reusing visuals pooled by lit moving cars at night must show every lamp dark - not even the
## daytime running-light glow of moving traffic).
## Regression scenarios for the playtest fixes (each logs a RESULT line with PASS/FAIL):
##   merge   - density 1.0 beside the expressway west junction: no vehicle may stand on a connector for good
##   solid   - kinematic cars near the player carry colliders, nearer cars get the physics slots, ramming one
##             that is kept kinematic (LOD updates frozen for the test) stops the player
##   lodswap - every physics -> kinematic swap draws the far-LOD mesh where the car is, in the swap frame
##   lights  - fog at noon lights all traffic, clear noon does not, the ring tunnel lights the cars inside it
##   parked  - parked cars on Gullhaven Quay (--poi=) sit on the street with all four wheels
##   overtake - traffic passes a 58 km/h player in the expressway's outer lane
##   climb   - lorry and coach hold their speed on the ring's 10 % highland climb in physics LOD
## Round-2 playtest regressions (RESULT lines too):
##   respawn  - R (real key through CarInput) beside the ring at density 1.0 while traffic closes in: never rammed
##              (5 trials per run; --at=-1184,453 for the second playtest site, --via=teleport for exact placements)
##   ram      - rear-end hits at 11-70 km/h closing on the expressway: the hit car brakes straight in its lane
##   pullout  - player stopped in the expressway's outer lane (or --where=shoulder|inject): traffic pulls out round it
##   giveway  - expressway west exit (junction 0): no head-of-queue wait of 30 s, no go taken back at the line
##   restricted - tractors / lorries / coaches only ever routed onto roads (class + region) they are allowed on
##   census   - expressway drive at density 1.0: vehicles in view (same metrics as the playtest census)
##   photo    - photo mode night switch while paused: traffic lamps follow, no vehicle moves
## Round-3 playtest regression:
##   nightswap - 22:30, oncoming expressway traffic: the headlight pool fades in, no one-frame pop at the
##               far-model -> physics swap (PHYSICS_IN)
## Every 0.5 s all vehicles are checked: correct side of the road, lateral lane error, height vs road
## surface (physics), bumper overlap / time gap, speed vs desired, junction conflicts. Report JSON + log.
## Runs with SaveGame disabled and never writes user settings (density through Game.traffic.set_density).

const MAIN := preload("res://scenes/main.tscn")
const TrafficVehicle := preload("res://scripts/traffic/traffic_vehicle.gd")
const LaneGraph := preload("res://scripts/traffic/lane_graph.gd")
const QaAutopilot := preload("res://scripts/main/qa_autopilot.gd")

var main: Node
var cam: Camera3D
var out_dir := "res://qa_output/traffic"
var scenario := "ring"
var report: Dictionary = {}
var chk := {"samples": 0, "vehicle_samples": 0, "wrong_side": 0, "lane_err_max_kin": 0.0, "lane_err_max_phys": 0.0,
	"height_err_max_phys": 0.0, "height_bad_phys": 0, "overlaps": 0, "time_gap_lt_1s": 0, "overspeed": 0,
	"junction_conflicts": 0, "max_active": 0, "max_physics": 0, "nodes_min": 1e9, "nodes_max": 0.0, "fps_min": 1e9}
var _shots := 0
var _detail_logs := 0


func _ready() -> void:
	SaveGame.enabled = false
	scenario = _arg("scenario", scenario)
	out_dir = _arg("out", out_dir)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	main = MAIN.instantiate()
	add_child(main)
	cam = Camera3D.new()
	cam.far = 5000.0
	cam.fov = 60.0
	# Placed from _process for single shots: interpolation would draw it between its last two placements.
	cam.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(cam)
	_run.call_deferred()


func _arg(key: String, default: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--" + key + "="):
			return a.substr(key.length() + 3)
	return default


func log_line(s: String) -> void:
	print("[ttest] ", s)


func _wait(t: float) -> void:
	await get_tree().create_timer(t, true, false, true).timeout


func _traffic() -> Node:
	return Game.traffic


func _run() -> void:
	while main.is_loading:
		await get_tree().process_frame
	await _wait(1.0)
	main.car_input.enabled = false
	if _arg("time", "") != "":
		Game.set_time_of_day(float(_arg("time", "12")))
		Game.set_time_scale(0.0)
	if _arg("density", "") != "":
		_traffic().set_density(float(_arg("density", "0.6")))
	log_line("scenario " + scenario)
	match scenario:
		"junction":
			await _scenario_junction()
		"ring":
			await _scenario_drive("ring", float(_arg("start", "40")), float(_arg("seconds", "70")))
		"expressway":
			await _scenario_drive("expressway", 60.0, float(_arg("seconds", "70")))
		"block":
			await _scenario_block()
		"crash":
			await _scenario_crash()
		"probe":
			await _scenario_probe()
		"watch":
			await _scenario_watch()
		"sweep":
			await _scenario_sweep()
		"lens":
			await _scenario_lens()
		"merge":
			await _scenario_merge()
		"solid":
			await _scenario_solid()
		"lodswap":
			await _scenario_lodswap()
		"lights":
			await _scenario_lights()
		"parked":
			await _scenario_parked()
		"overtake":
			await _scenario_overtake()
		"climb":
			await _scenario_climb()
		"respawn":
			await _scenario_respawn()
		"ram":
			await _scenario_ram()
		"pullout":
			await _scenario_pullout()
		"giveway":
			await _scenario_giveway()
		"restricted":
			await _scenario_restricted()
		"census":
			await _scenario_census()
		"photo":
			await _scenario_photo()
		"nightswap":
			await _scenario_nightswap()
	report["checks"] = chk
	report["stats"] = _traffic().get_stats()
	var f := FileAccess.open(out_dir.path_join("report_%s.json" % scenario), FileAccess.WRITE)
	f.store_string(JSON.stringify(report, "\t"))
	f.close()
	log_line("checks " + JSON.stringify(chk))
	log_line("stats " + JSON.stringify(_traffic().get_stats()))
	log_line("TRAFFIC_TEST_DONE")
	get_tree().quit(0)


# ----------------------------------------------------------------- scenarios

func _scenario_junction() -> void:
	var w := Game.world as World
	var t: Node = _traffic()
	t.set_density(1.0)
	var graph: LaneGraph = t.graph
	var j: LaneGraph.Junction = null
	for jj: LaneGraph.Junction in graph.junctions:
		if jj.child.id == "festival_coast" and jj.child_end == 0:
			j = jj
	var road := w.data.network.get_road("ring")
	# Park the player off the road beside the junction so it does not block anyone.
	var s := j.parent_s - 45.0
	var side := road.surface_point(s, road.width * 0.5 + road.shoulder + 14.0)
	side.y = w.height_at(side.x, side.z)
	main.teleport_to({"position": side, "forward": road.flat_tangent_at(s)})
	var t0 := 0.0
	var turns0: int = t.get_stats()["give_way_entries"]
	var close := _arg("close", "") != ""
	while t0 < 60.0:
		await _wait(0.5)
		t0 += 0.5
		_sample()
		if close:
			for v: TrafficVehicle in t.vehicles:
				if v.position.distance_to(j.center) < 22.0:
					log_line("near j: #%d %s %s %s spd %.1f tgt %.1f go %s wait %.1f steer %.2f thr %.2f pos %s" % [v.uid, v.data.id,
						"PHYS" if v.mode == TrafficVehicle.Mode.PHYSICS else "kin",
						("conn %d c=%.1f/%.1f turn %d" % [v.conn.id, v.c, v.conn.length, v.conn.turn]) if v.conn != null else ("%s dir %d s=%.1f" % [v.lane.road.id, v.lane.dir, v.s]),
						v.speed, v.v_target, v.go, v.wait_t, v.car.in_steer if v.car else 0.0, v.car.in_throttle if v.car else 0.0, str(v.position.snapped(Vector3.ONE * 0.1))])
			if int(t0 * 2.0) % 6 == 0:
				cam.global_position = j.center + Vector3(14.0, 9.0, 14.0)
				cam.look_at(j.center + Vector3(0, 0, 8), Vector3.UP)
				cam.current = true
				await _shot("jclose_%02d" % int(t0))
		elif int(t0 * 2.0) % 30 == 0:
			_look_at_overhead(j.center, 38.0)
			await _shot("junction_%02d" % int(t0))
	report["give_way_entries"] = int(t.get_stats()["give_way_entries"]) - turns0


func _scenario_drive(road_id: String, start_s: float, seconds: float) -> void:
	var w := Game.world as World
	var road := w.data.network.get_road(road_id)
	var f := RoadFollower.new()
	var lane_k := road.lanes
	f.setup(road, start_s, 1, road.lane_offset(lane_k))
	f.target_speed = 100.0 / 3.6
	main.teleport_to({"position": f.lane_point(start_s), "forward": road.flat_tangent_at(start_s)})
	await _wait(2.0)
	var t := 0.0
	var next_sample := 0.0
	var next_shot := 8.0
	var stuck := 0.0
	var dist := 0.0
	var last := Game.player_car.global_position
	while t < seconds:
		await get_tree().physics_frame
		f.drive(Game.player_car, get_physics_process_delta_time())
		await get_tree().process_frame
		var dt := get_process_delta_time()
		t += dt
		var car := Game.player_car
		dist += car.global_position.distance_to(last)
		last = car.global_position
		stuck = stuck + dt if car.speed_ms < 1.0 else 0.0
		if stuck > 20.0:
			log_line("player held up > 20 s at s=%.0f (traffic ahead) - skipping ahead" % f.s)
			f.s += 60.0
			main.teleport_to({"position": f.lane_point(f.s), "forward": road.flat_tangent_at(f.s)})
			stuck = 0.0
		if t >= next_sample:
			next_sample += 0.5
			_sample()
		if t >= next_shot:
			next_shot += 12.0
			if await _traffic_cam(true):
				await _shot("%s_phys_%03d" % [road_id, int(t)])
			if await _traffic_cam(false):
				await _shot("%s_kin_%03d" % [road_id, int(t)])
			cam.current = false
			Game.camera_rig.camera.current = true
			await _shot("%s_chase_%03d" % [road_id, int(t)])
	report["player_km"] = dist / 1000.0


func _scenario_block() -> void:
	var w := Game.world as World
	var t: Node = _traffic()
	t.set_density(1.0)
	var road := w.data.network.get_road("ring")
	var s := 900.0
	_park_player(road, s)
	var honks0: int = t.get_stats()["honks"]
	var tt := 0.0
	var queued_shot := false
	while tt < 80.0:
		await _wait(0.5)
		tt += 0.5
		_sample()
		var q := _queued_behind_player()
		if q != null and not queued_shot and q.speed < 0.5:
			queued_shot = true
			var p := Game.player_car.global_position
			var back := q.position - p
			cam.global_position = p + back * 0.5 + Vector3.UP * 6.0 + back.cross(Vector3.UP).normalized() * 9.0
			cam.look_at(p + back * 0.5, Vector3.UP)
			cam.current = true
			await _shot("block_queue")
			log_line("queued %s gap %.1f m behind the player" % [q.data.id, q.lead_gap])
		if int(t.get_stats()["honks"]) > honks0 and queued_shot:
			log_line("honk heard after %.1f s" % tt)
			break
	report["honks"] = int(t.get_stats()["honks"]) - honks0


func _scenario_crash() -> void:
	var w := Game.world as World
	var t: Node = _traffic()
	t.set_density(1.0)
	var road := w.data.network.get_road("ring")
	var s := float(_arg("crash-s", "6300"))
	_park_player(road, s)
	var victim: TrafficVehicle = null
	var tt := 0.0
	while victim == null and tt < 60.0:
		await _wait(0.5)
		tt += 0.5
		for v: TrafficVehicle in t.vehicles:
			if v.mode == TrafficVehicle.Mode.PHYSICS and not v.hazard and v.speed > 5.0 and v.conn == null:
				var d := v.position.distance_to(Game.player_car.global_position)
				if d > 30.0 and d < 120.0:
					victim = v
					break
	if victim == null:
		log_line("no physics traffic car found for the crash test")
		return
	# Rear-end ram: start 30 m behind the victim in its lane, --closing (25) m/s faster - a real crash: a moderate
	# knock is only a shunt now (the hit car brakes in its lane and carries on, see the ram scenario).
	# The player follows the victim's lane (steering round the bends) until the contact.
	var closing := float(_arg("closing", "25"))
	var vl := victim.lane
	var sb := vl.advance(victim.s, -30.0)
	var f := RoadFollower.new()
	f.setup(vl.road, sb, vl.dir, vl.offset)
	f.respect_traffic = false
	f.max_throttle = 1.0
	main.teleport_to({"position": f.lane_point(sb), "forward": vl.road.flat_tangent_at(sb) * vl.dir})
	var pc := Game.player_car
	pc.place_at(pc.global_transform, vl.road.flat_tangent_at(sb) * vl.dir * (victim.speed + closing))
	log_line("crash test: ramming %s #%d at %.0f km/h, closing %.0f km/h" % [victim.data.id, victim.uid, victim.speed * 3.6, closing * 3.6])
	var hz0: int = t.get_stats()["hazards"]
	var tr := 0.0
	while tr < 6.0 and t.vehicles.has(victim):
		await get_tree().physics_frame
		tr += get_physics_process_delta_time()
		f.target_speed = victim.speed + closing
		f.drive(pc, get_physics_process_delta_time())
		if (victim.position - pc.global_position).dot(victim.heading) - (victim.length + pc.data.body_size.z) * 0.5 < 0.3:
			break
	pc.in_throttle = 0.0
	pc.in_steer = 0.0
	tt = 0.0
	var shot_done := false
	while tt < 40.0:
		await _wait(0.25)
		tt += 0.25
		_sample()
		if victim.hazard and not shot_done and tt > 1.5:
			shot_done = true
			_aim_cam(victim.position, 11.0, 4.0)
			await _shot("crash_hazard")
		if tt > 3.0 and tt < 3.3:
			_aim_cam(victim.position, 11.0, 4.0)
			await _shot("crash_hazard_blink")
		if tt > 3.6 and tt < 3.9:
			Game.player_car.in_throttle = 0.0
			Game.player_car.in_brake = 0.25
			Game.player_car.in_handbrake = 1.0
		if tt > 4.0 and tt < 4.3:
			# Drive away (less than the flush distance) so the victim can recover or be removed once out of view.
			main.teleport_to({"position": victim.position + victim.heading * 150.0 + Vector3.UP * 0.5, "forward": victim.heading})
		if tt > 4.3 and int(tt * 4.0) % 20 == 0:
			log_line("victim #%d hazard %s wreck %s unseen %.1f in_list %s dist %.0f" % [victim.uid, victim.hazard, victim.wreck, victim.unseen_t,
				t.vehicles.has(victim), victim.position.distance_to(Game.player_car.global_position)])
	report["hazards"] = int(t.get_stats()["hazards"]) - hz0
	report["victim_state"] = "hazard=%s wreck=%s in_list=%s" % [victim.hazard, victim.wreck, t.vehicles.has(victim)]
	_result("crash", int(report["hazards"]) > 0 and (not victim.hazard or not t.vehicles.has(victim)), "hazards %d, victim at the end: %s (recovered or removed once unseen)" % [
		int(report["hazards"]), report["victim_state"]])


## Sweeps a car-body box (0.25..0.70 m above the surface) along every traffic lane and lists stretches where it
## intersects rails / bridge parts (road bodies without a road id) or props. Road and terrain surfaces are ignored.
func _scenario_sweep() -> void:
	var t: Node = _traffic()
	t.set_density(0.0)
	await _wait(1.0)
	var graph: LaneGraph = t.graph
	var space := get_viewport().world_3d.direct_space_state
	var q := PhysicsShapeQueryParameters3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.7, 0.45, 3.6)
	q.shape = box
	q.collision_mask = 1
	var total := 0
	for l: LaneGraph.Lane in graph.lanes:
		if l.dead_end:
			continue
		var r := l.road
		var start := -1.0
		var last := -1.0
		var what := ""
		var ss := 0.0
		while ss <= r.length:
			var c := r.surface_point(ss, l.offset * l.dir)
			var f := r.tangent_at(ss) * l.dir
			q.transform = Transform3D(Basis.looking_at(f, Vector3.UP), c + Vector3.UP * 0.475)
			var bad := ""
			for hit: Dictionary in space.intersect_shape(q, 6):
				var col: Object = hit["collider"]
				if col.has_meta(&"terrain") or col is CharacterBody3D or col is RigidBody3D:
					continue
				if col.has_meta(&"surface") and String(col.get_meta(&"road", "")) != "":
					continue
				bad = str((col as Node).get_parent().name) + "/" + str((col as Node).name)
				break
			if bad != "":
				if start < 0.0:
					start = ss
					what = bad
				last = ss
			elif start >= 0.0:
				var p0 := r.surface_point(start, l.offset * l.dir)
				log_line("LANE BLOCK %s dir %d k%d s %.0f-%.0f at %s : %s" % [r.id, l.dir, l.k, start, last, str(p0.round()), what])
				total += 1
				start = -1.0
			ss += 2.0
		if start >= 0.0:
			log_line("LANE BLOCK %s dir %d k%d s %.0f-%.0f : %s" % [r.id, l.dir, l.k, start, last, what])
			total += 1
	report["lane_blocks"] = total
	log_line("sweep done: %d blocked stretches" % total)


## Films --at=x,y,z in bursts while physics traffic passes (diagnoses impacts at a spot).
func _scenario_watch() -> void:
	var parts := _arg("at", "0,0,0").split(",")
	var at := Vector3(float(parts[0]), float(parts[1]), float(parts[2]))
	var w := Game.world as World
	var t: Node = _traffic()
	var park := at + Vector3(45, 0, -45)
	park.y = w.height_at(park.x, park.z)
	main.teleport_to({"position": park, "forward": Vector3(0, 0, -1)})
	var shots := 0
	var tt := 0.0
	var hz0: int = t.get_stats()["hazards"]
	while tt < float(_arg("seconds", "70")) and shots < 40:
		await _wait(0.25)
		tt += 0.25
		for v: TrafficVehicle in t.vehicles:
			if v.mode == TrafficVehicle.Mode.PHYSICS and v.position.distance_to(at) < 22.0:
				cam.global_position = at + Vector3(0.0, 3.5, 0.0) + (v.heading.cross(Vector3.UP).normalized() * 12.0)
				cam.global_position.y = maxf(cam.global_position.y, w.height_at(cam.global_position.x, cam.global_position.z) + 1.5)
				cam.look_at(v.position + Vector3.UP * 0.5, Vector3.UP)
				cam.current = true
				log_line("watch t=%.2f #%d %s %s %.0f km/h y %.2f up %.2f wheels %d %s" % [tt, v.uid, v.data.id,
					("conn %d c=%.1f" % [v.conn.id, v.c]) if v.conn != null else ("%s dir %d s=%.0f" % [v.lane.road.id, v.lane.dir, v.s]),
					v.speed * 3.6, v.position.y, v.car.global_transform.basis.y.y, v.car.wheels_on_ground, "HAZARD" if v.hazard else ""])
				await _shot("watch_%02d" % shots)
				shots += 1
				break
	report["hazards"] = int(t.get_stats()["hazards"]) - hz0


## Lists non-road/terrain colliders around --at=x,y,z (diagnoses static obstacles traffic hits).
func _scenario_probe() -> void:
	var parts := _arg("at", "0,0,0").split(",")
	var at := Vector3(float(parts[0]), float(parts[1]), float(parts[2]))
	var road := (Game.world as World).data.network.get_road("ring")
	main.teleport_to({"position": at + Vector3(30, 0, 30), "forward": road.flat_tangent_at(0.0)})
	await _wait(4.0)
	var q := PhysicsShapeQueryParameters3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(30, 8, 30)
	q.shape = box
	q.transform = Transform3D(Basis(), at + Vector3.UP * 2.0)
	q.collision_mask = 0xFFFF
	for hit: Dictionary in get_viewport().world_3d.direct_space_state.intersect_shape(q, 64):
		var col: Object = hit["collider"]
		var meta := ""
		if col.has_meta(&"surface"):
			meta = "road " + str(col.get_meta(&"road", ""))
		elif col.has_meta(&"terrain"):
			meta = "terrain"
		var shape_xf := Transform3D()
		if col is CollisionObject3D:
			var owner_id: int = (col as CollisionObject3D).shape_find_owner(int(hit["shape"]))
			shape_xf = (col as CollisionObject3D).global_transform * (col as CollisionObject3D).shape_owner_get_transform(owner_id)
		log_line("collider %s layer %d %s shape at %s" % [str((col as Node).get_path()).right(70), (col as CollisionObject3D).collision_layer, meta, str(shape_xf.origin.round())])
	# Car-sized box swept along both ring lanes (0.25..0.75 m above the surface): what would a car body touch?
	var ring := (Game.world as World).data.network.get_road("ring")
	var nr := (Game.world as World).data.network.nearest(at, 60.0, func(rr: RoadNetwork.Road) -> bool: return rr == ring)
	if not nr.is_empty():
		var bq := PhysicsShapeQueryParameters3D.new()
		var bb := BoxShape3D.new()
		bb.size = Vector3(1.8, 0.5, 4.0)
		bq.shape = bb
		bq.collision_mask = 1
		var bs0: float = nr["s"]
		for d2: int in [1, -1]:
			for k2 in range(-40, 41):
				var ss2 := bs0 + k2 * 1.5
				var off2 := ring.lane_offset(1) * d2
				var c2 := ring.surface_point(ss2, off2)
				var f2 := ring.tangent_at(ss2) * d2
				var b2 := Basis.looking_at(f2, Vector3.UP)
				bq.transform = Transform3D(b2, c2 + Vector3.UP * 0.5)
				for hit2: Dictionary in get_viewport().world_3d.direct_space_state.intersect_shape(bq, 4):
					var col2: Object = hit2["collider"]
					log_line("BOX ring dir %d s %.1f touches %s%s" % [d2, ss2, str((col2 as Node).name), " (road %s)" % col2.get_meta(&"road", "") if col2.has_meta(&"surface") else (" (terrain)" if col2.has_meta(&"terrain") else "")])
	# Dense grid at the probe point: highest hit and its collider.
	var sp := get_viewport().world_3d.direct_space_state
	var top := -INF
	var top_at := Vector3.ZERO
	var top_col := ""
	for ix in range(-12, 13):
		for iz in range(-12, 13):
			var p0 := at + Vector3(ix * 0.2, 0.0, iz * 0.2)
			var rq0 := PhysicsRayQueryParameters3D.create(p0 + Vector3.UP * 3.0, p0 - Vector3.UP * 3.0, 1)
			var h0 := sp.intersect_ray(rq0)
			if h0.is_empty():
				continue
			var y0 := (h0["position"] as Vector3).y
			if y0 > top:
				top = y0
				top_at = h0["position"]
				top_col = str((h0["collider"] as Node).name)
	log_line("grid top %.3f at %s on %s (probe y %.2f)" % [top, str(top_at.snapped(Vector3.ONE * 0.01)), top_col, at.y])
	# Surface steps along the ring lanes through the probe point.
	var space := get_viewport().world_3d.direct_space_state
	for rid: String in ["ring", "backroad"]:
		var r: RoadNetwork.Road = (Game.world as World).data.network.get_road(rid)
		var res := (Game.world as World).data.network.nearest(at, 50.0, func(rr: RoadNetwork.Road) -> bool: return rr == r)
		if res.is_empty():
			continue
		var s0: float = res["s"]
		log_line("probing %s around s %.0f" % [rid, s0])
		for d: int in [1, -1]:
			for k in range(-60, 61):
				var ss := s0 + k * 1.0
				for lat: float in [d * 0.6, d * 1.2, d * 1.8, d * 2.4, d * 3.0, d * 3.6, d * 4.2]:
					var p := r.surface_point(ss, lat)
					var rq := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 2.0, p - Vector3.UP * 2.0, 1)
					var hit := space.intersect_ray(rq)
					if hit.is_empty():
						log_line("road %s s %.0f lat %.1f: NO HIT" % [r.id, ss, lat])
						continue
					var dy := (hit["position"] as Vector3).y - p.y
					if absf(dy) > 0.04:
						var col: Object = hit["collider"]
						log_line("road %s s %.0f lat %.1f: hit dy %+.3f on %s" % [r.id, ss, lat, dy, str(col.get_meta(&"road", "?")) if col.has_meta(&"road") else str((col as Node).name)])
	_aim_cam(at, 25.0, 18.0)
	await _shot("probe")


## Night by a village: moving kinematic traffic lights its head/tail (and brake) lenses. Parked slots are then
## re-spawned from pools that hold only those lit visuals; every parked lens must be the "off" variant.
func _scenario_lens() -> void:
	var t: Node = _traffic()
	var w := Game.world as World
	Game.set_time_of_day(float(_arg("time", "23")))
	Game.set_time_scale(0.0)
	var parked: Array = t.get("_parked")
	if parked.is_empty():
		log_line("lens: no parked slots")
		return
	var p0: Vector3 = (parked[0] as Dictionary)["pos"]
	var res := w.data.network.nearest(p0, 40.0, func(r: RoadNetwork.Road) -> bool: return r.traffic)
	_park_player(res["road"], float(res["s"]))
	t.set_density(1.0)
	await _wait(float(_arg("seconds", "12")))
	var lit_ids := {}
	for v: TrafficVehicle in t.vehicles:
		if v.visual != null and v.light_state >= 1:
			lit_ids[v.visual.get_instance_id()] = v.light_state
	var spawned_before := 0
	for slot: Dictionary in parked:
		if slot.has("vis"):
			spawned_before += 1
			t.call("_release_visual", slot["type"], slot["vis"])
			var body: StaticBody3D = slot["body"]
			(body.get_child(0) as CollisionShape3D).disabled = true
			(t.get("_parked_bodies") as Array).append(body)
			slot.erase("vis")
			slot.erase("body")
	# Empty the pools so the parked slots can only get visuals released by moving traffic.
	for pool: Array in t.get("_visual_pool"):
		for vis: MeshInstance3D in pool:
			vis.queue_free()
		pool.clear()
	t.call("_flush_all")
	var pp := Game.player_car.global_position
	var parked_n := 0
	var reused_lit := 0
	var lit_parked := 0
	var base_parked := 0
	var shot_slot: Dictionary = {}
	var shot_d := INF
	for slot: Dictionary in parked:
		if slot["blocked"] or (slot["pos"] as Vector3).distance_to(pp) > 350.0:
			continue
		t.call("_spawn_parked", slot)
		if not slot.has("vis"):
			continue
		parked_n += 1
		var vis: MeshInstance3D = slot["vis"]
		var from_lit := lit_ids.has(vis.get_instance_id())
		if from_lit:
			reused_lit += 1
		var kit: Dictionary = t.call("_visual_kit", int(slot["type"]))
		var lit := false
		for key: String in ["head", "tail", "brake"]:
			for idx: int in kit[key]:
				var m := vis.get_surface_override_material(idx) as StandardMaterial3D
				if m == null:
					base_parked += 1
				elif m.emission_enabled and m.emission_energy_multiplier > 0.0:
					lit = true
		if lit:
			lit_parked += 1
			log_line("lens: LIT parked %s at %s (visual from a lit moving car: %s)" % [t.types[slot["type"]].id, str((slot["pos"] as Vector3).round()), from_lit])
		# Screenshot: the nearest reused visual that is clear of the player's own headlights.
		var dp := (slot["pos"] as Vector3).distance_to(pp)
		if from_lit and dp > 25.0 and dp < shot_d:
			shot_d = dp
			shot_slot = slot
	log_line("lens: lit moving visuals %d, parked before %d, parked re-spawned %d, reused lit visuals %d, parked with lit lenses %d, lens surfaces on base material %d" % [
		lit_ids.size(), spawned_before, parked_n, reused_lit, lit_parked, base_parked])
	report["lens"] = {"lit_moving": lit_ids.size(), "parked": parked_n, "reused_lit": reused_lit, "lit_parked": lit_parked, "base_lens_surfaces": base_parked}
	if not shot_slot.is_empty():
		var b: Basis = shot_slot["basis"]
		var at: Vector3 = shot_slot["pos"]
		# Front and rear, the player's own lights off; then the same front view with the lenses forced to the
		# daytime running-light variant (what parked cars showed before) for comparison.
		Game.player_car.headlights_on = false
		var vis2: MeshInstance3D = shot_slot["vis"]
		var kit2: Dictionary = t.call("_visual_kit", int(shot_slot["type"]))
		for view: String in ["front", "rear", "front_running_lights_for_comparison"]:
			var sgn := -1.0 if view != "rear" else 1.0
			if view.begins_with("front_running"):
				for key: String in ["head", "tail", "brake"]:
					t.call("_set_lens", vis2, kit2[key], kit2[key + "_m"], 0)
			cam.global_position = at + b.z * (7.5 * sgn) + b.x * (2.5 * -sgn) + Vector3.UP * 1.8
			cam.look_at(at + Vector3.UP * 0.6, Vector3.UP)
			cam.current = true
			await _wait(0.3)
			await _shot("lens_parked_night_" + view)
		for key2: String in ["head", "tail", "brake"]:
			t.call("_set_lens", vis2, kit2[key2], kit2[key2 + "_off"], 0)
	_result("lens", parked_n > 0 and lit_parked == 0 and base_parked == 0, "%d parked cars re-spawned at night (%d on visuals of lit moving cars), %d with a glowing lamp" % [parked_n, reused_lit, lit_parked])


# ----------------------------------------------------------------- playtest regressions

## Density 1.0 beside the Sunward Expressway west end (ring s~1785): cars from both expressway lanes merge
## into one ring lane. Fails when any vehicle stands on a connector of that junction for 15 s or more.
func _scenario_merge() -> void:
	var t: Node = _traffic()
	t.set_density(float(_arg("density", "1.0")))
	var j := _find_junction(_arg("child", "expressway"), int(_arg("end", "0")))
	if j == null:
		_result("merge", false, "junction not found")
		return
	log_line("junction %s on %s s=%.0f centre %s radius %.1f, %d connectors" % [j.child.id, j.parent.id, j.parent_s, str(j.center.round()), j.radius, j.connectors.size()])
	await _park_beside_junction(j)
	var stall := {}
	var used := {}
	var max_stall := 0.0
	var worst := "-"
	var cycles0: int = t.get_stats().get("lead_cycle_ticks", 0)
	var tt := 0.0
	var seconds := float(_arg("seconds", "120"))
	while tt < seconds:
		await _wait(0.5)
		tt += 0.5
		_hold_player()
		_sample()
		for v: TrafficVehicle in t.vehicles:
			var on_j := v.conn != null and v.conn.junction == j
			if on_j:
				used[v.uid] = true
			if on_j and v.speed < 0.3 and not v.hazard:
				var st: float = float(stall.get(v.uid, 0.0)) + 0.5
				stall[v.uid] = st
				if st > max_stall:
					max_stall = st
					worst = "#%d %s %s lead %.1f" % [v.uid, v.data.id, _where(v), v.lead_gap]
			else:
				stall.erase(v.uid)
		if int(tt * 2.0) % 40 == 0:
			var lines: PackedStringArray = []
			for v2: TrafficVehicle in t.vehicles:
				if v2.position.distance_to(j.center) < j.radius + 40.0:
					lines.append("#%d %s %s %s %.0f km/h tgt %.0f go %s wait %.1f lead %s" % [v2.uid, v2.data.id,
						"PHYS" if v2.mode == TrafficVehicle.Mode.PHYSICS else "kin", _where(v2), v2.speed * 3.6, v2.v_target * 3.6, v2.go,
						v2.wait_t, ("%.1f" % v2.lead_gap) if v2.lead_gap < INF else "-"])
			log_line("t=%.0f avg %.0f km/h, junction box:\n      %s" % [tt, float(t.get_stats()["avg_kmh"]), "\n      ".join(lines)])
			cam.global_position = j.center + Vector3(19.0, 34.0, 19.0)
			cam.look_at(j.center, Vector3.UP)
			cam.current = true
			await _shot("merge_%03d" % int(tt))
	var cycles: int = int(t.get_stats().get("lead_cycle_ticks", 0)) - cycles0
	report["merge"] = {"max_connector_stall_s": max_stall, "worst": worst, "vehicles_through": used.size(), "lead_cycle_ticks": cycles}
	_result("merge", max_stall < 15.0 and used.size() >= 3, "longest stand on a junction connector %.1f s (%s), %d vehicles used the junction, lead-cycle break ticks %d" % [
		max_stall, worst, used.size(), cycles])


## Kinematic cars near the player stay solid and the nearest cars get the physics slots:
##  A) density 1.0 beside the expressway junction: every kinematic car within 170 m carries its collider;
##  B) ring s=900, 13 cars spawned 100-145 m away fill the 12 slots, then 2 cars spawned 25-55 m away must get
##     slots (the farthest physics cars hand theirs over and turn kinematic with a collider);
##  C) ram one of those kinematic cars from behind at +36 km/h with LOD updates frozen (so it stays kinematic):
##     the player must stop at its bumper instead of passing through.
func _scenario_solid() -> void:
	var w := Game.world as World
	var t: Node = _traffic()
	t.set_density(float(_arg("density", "1.0")))
	var j := _find_junction(_arg("child", "expressway"), int(_arg("end", "0")))
	await _park_beside_junction(j)
	var space := get_viewport().world_3d.direct_space_state
	var checked := 0
	var missing := 0
	var tt := 0.0
	while tt < float(_arg("seconds", "40")):
		await _wait(1.0)
		tt += 1.0
		_hold_player()
		_sample()
		var c := _count_solid(space, 170.0)
		checked += c.x
		missing += c.y
		if int(tt) % 10 == 0:
			log_line("t=%.0f physics %d, kinematic within 170 m checked %d, without collider %d" % [tt, int(t.get_stats()["physics"]), checked, missing])
	# B) slot ordering.
	t.set_density(0.0)
	var ring := w.data.network.get_road("ring")
	var s0 := 900.0
	var park := ring.surface_point(s0, ring.width * 0.5 + ring.shoulder + 16.0)
	park.y = w.height_at(park.x, park.z)
	main.teleport_to({"position": park, "forward": ring.flat_tangent_at(s0)})
	await _settle()
	_hold_player()
	var pp := Game.player_car.global_position
	var graph: LaneGraph = t.graph
	var far_slots: Array = []
	var near_slots: Array = []
	for l: LaneGraph.Lane in graph.lanes_of(ring):
		var ss := -200.0
		while ss <= 200.0:
			var d := l.point(s0 + ss, l.offset).distance_to(pp)
			if d > 100.0 and d < 145.0:
				far_slots.append([l, s0 + ss])
			elif d > 25.0 and d < 55.0 and near_slots.size() < 2 * graph.lanes_of(ring).size():
				near_slots.append([l, s0 + ss])
			ss += 16.0
	var spawned_far: Array = []
	for k in mini(13, far_slots.size()):
		var it: Array = far_slots[k]
		spawned_far.append(t.call("_new_vehicle", 0, it[0], it[1]))
	await _wait(1.2)
	var phys_before := int(t.get_stats()["physics"])
	var swaps0: int = t.get_stats().get("slot_swaps", 0)
	var spawned_near: Array = []
	for k2 in mini(2, near_slots.size()):
		var it2: Array = near_slots[k2 * (near_slots.size() - 1)] if k2 > 0 else near_slots[0]
		spawned_near.append(t.call("_new_vehicle", 0, it2[0], it2[1]))
	await _wait(0.7)
	var near_phys := 0
	for nv: TrafficVehicle in spawned_near:
		if nv.mode == TrafficVehicle.Mode.PHYSICS:
			near_phys += 1
	var swaps: int = int(t.get_stats().get("slot_swaps", 0)) - swaps0
	var cb := _count_solid(space, 170.0)
	var order_ok := spawned_near.size() == 2 and near_phys == 2 and int(t.get_stats()["physics"]) <= 12 and cb.y == 0
	log_line("slots: %d far cars spawned -> %d physics; 2 near cars spawned -> %d of them physics, %d slot swaps, physics now %d, kinematic within 170 m %d (without collider %d)" % [
		spawned_far.size(), phys_before, near_phys, swaps, int(t.get_stats()["physics"]), cb.x, cb.y])
	# C) ram a kinematic car with a collider (LOD frozen so it stays kinematic).
	var pc := Game.player_car
	var target: TrafficVehicle = null
	var bd := INF
	for v: TrafficVehicle in t.vehicles:
		if v.mode != TrafficVehicle.Mode.KINEMATIC or v.body == null or v.conn != null or v.hazard:
			continue
		var back := v.position - v.heading * 14.0
		var free := true
		for w2: TrafficVehicle in t.vehicles:
			if w2 != v and w2.position.distance_to(back) < 10.0:
				free = false
		var d2 := v.position.distance_to(pc.global_position)
		if free and d2 < bd:
			bd = d2
			target = v
	if target == null:
		_result("solid", false, "no kinematic car with a collider to ram (A: checked %d, missing %d; B ordering ok %s)" % [checked, missing, order_ok])
		return
	t.set("_lod_timer", 1.0e9)
	log_line("ram target #%d %s kin at %.0f m %s %.0f km/h" % [target.uid, target.data.id, bd, _where(target), target.speed * 3.6])
	main.teleport_to({"position": target.position - target.heading * 14.0, "forward": target.heading})
	await get_tree().physics_frame
	var hits: Array[float] = []
	var on_hit := func(strength: float, _at: Vector3) -> void: hits.append(strength)
	pc.impact.connect(on_hit)
	pc.in_handbrake = 0.0
	pc.in_brake = 0.0
	pc.linear_velocity = target.heading * (target.speed + 10.0)
	var contact := (pc.data.body_size.z + target.length) * 0.5
	var min_d := INF
	var closing := 0.0
	var shot_done := false
	var t2 := 0.0
	while t2 < 4.0:
		await get_tree().physics_frame
		t2 += get_physics_process_delta_time()
		pc.in_throttle = 0.35
		pc.in_steer = 0.0
		var d3 := pc.global_position.distance_to(target.position)
		min_d = minf(min_d, d3)
		if d3 > contact + 2.0:
			closing = maxf(closing, (pc.linear_velocity - target.heading * target.speed).dot(target.heading) * 3.6)
		if not shot_done and d3 < contact + 0.6:
			shot_done = true
			await _shot("solid_contact_chase")
			_aim_cam(target.position, 9.0, 2.5)
			await _shot("solid_contact_side")
	pc.impact.disconnect(on_hit)
	_hold_player()
	var still_kin := target.mode == TrafficVehicle.Mode.KINEMATIC
	t.set("_lod_timer", 0.0)
	await _wait(0.6)
	var ok := missing == 0 and order_ok and min_d > contact - 1.0 and still_kin
	report["solid"] = {"kinematic_checked": checked, "without_collider": missing, "order_ok": order_ok, "slot_swaps": swaps,
		"ram_min_centre_m": min_d, "contact_m": contact, "impacts": hits.size(), "target_kinematic": still_kin}
	_result("solid", ok, "A) kinematic cars within 170 m checked %d, without collider %d; B) near cars got physics slots %d/2 via %d swaps, ordering ok %s; C) ram closing at %.0f km/h on kinematic #%d: closest centre distance %.2f m (bumper contact %.2f m), %d impacts, stayed kinematic %s, promoted once LOD resumed %s" % [
		checked, missing, near_phys, swaps, order_ok, closing, target.uid, min_d, contact, hits.size(), still_kin, target.mode == TrafficVehicle.Mode.PHYSICS])


## Kinematic vehicles within `radius` of the player: (count, count without a collider at their position).
func _count_solid(space: PhysicsDirectSpaceState3D, radius: float) -> Vector2i:
	var pp := Game.player_car.global_position
	var out := Vector2i.ZERO
	for v: TrafficVehicle in _traffic().vehicles:
		if v.mode == TrafficVehicle.Mode.KINEMATIC and v.position.distance_to(pp) < radius:
			out.x += 1
			if not _solid(space, v):
				out.y += 1
	return out


## Player on the expressway shoulder looking along the traffic: every physics -> kinematic swap must draw the
## far-LOD mesh at the car in the swap frame (a monitor runs after the traffic manager every frame).
func _scenario_lodswap() -> void:
	var w := Game.world as World
	var t: Node = _traffic()
	t.set_density(float(_arg("density", "1.0")))
	var road := w.data.network.get_road(_arg("road", "expressway"))
	var s := float(_arg("s", "600"))
	var p := road.surface_point(s, road.width * 0.5 + road.shoulder + 3.0)
	p.y = maxf(p.y, w.height_at(p.x, p.z))
	main.teleport_to({"position": p, "forward": road.flat_tangent_at(s)})
	await _settle()
	_hold_player()
	var ahead := road.surface_point(s + 180.0, road.lane_offset(1))
	cam.global_position = Game.player_car.global_position + Vector3.UP * 5.0 - road.flat_tangent_at(s) * 6.0
	cam.look_at(ahead + Vector3.UP, Vector3.UP)
	cam.fov = 35.0
	cam.current = true
	var mon := SwapWatch.new()
	mon.process_priority = 1000
	mon.test = self
	add_child(mon)
	var tt := 0.0
	while tt < float(_arg("seconds", "90")):
		await _wait(0.5)
		tt += 0.5
		_hold_player()
		if not mon.busy:
			cam.current = true
	mon.queue_free()
	cam.fov = 60.0
	report["lodswap"] = {"demotions": mon.demotions, "stale": mon.stale, "worst_m": mon.worst, "promotions": mon.promotions, "promotion_jumps": mon.promo_jumps}
	_result("lodswap", mon.demotions > 0 and mon.stale == 0 and mon.promo_jumps == 0, "%d demotions, %d drawn > 2 m from the car in the swap frame (worst %.2f m); %d promotions, %d jumps > 2 m" % [
		mon.demotions, mon.stale, mon.worst, mon.promotions, mon.promo_jumps])


class SwapWatch extends Node:
	var test: Node
	var modes: Dictionary = {}
	var vis_at: Dictionary = {}
	var demotions := 0
	var stale := 0
	var worst := 0.0
	var promotions := 0
	var promo_jumps := 0
	var shots := 0
	var busy := false

	func _process(_d: float) -> void:
		var t: Node = Game.traffic
		var cur := {}
		var cur_vis := {}
		for v: TrafficVehicle in t.vehicles:
			cur[v.uid] = v.mode
			if v.visual != null:
				cur_vis[v.uid] = v.visual.global_position
			if not modes.has(v.uid):
				continue
			var was: int = modes[v.uid]
			if was == TrafficVehicle.Mode.PHYSICS and v.mode == TrafficVehicle.Mode.KINEMATIC:
				demotions += 1
				var gap := v.visual.global_position.distance_to(v.position)
				worst = maxf(worst, gap)
				if gap > 2.0:
					stale += 1
				var cam := get_viewport().get_camera_3d()
				var seen := cam.is_position_in_frustum(v.position + Vector3.UP) and _terrain_clear(cam.global_position, v.position + Vector3.UP)
				test.call("log_line", "demotion #%d %s at %.0f m from the camera (in view %s): mesh drawn %.2f m from the car" % [v.uid, v.data.id,
					v.position.distance_to(cam.global_position), seen, gap])
				if seen and shots < 2 and not busy:
					shots += 1
					_capture.call_deferred(v.position, shots)
			elif was == TrafficVehicle.Mode.KINEMATIC and v.mode == TrafficVehicle.Mode.PHYSICS and vis_at.has(v.uid) and v.car != null:
				promotions += 1
				var prev: Vector3 = vis_at[v.uid]
				if Vector2(prev.x - v.car.global_position.x, prev.z - v.car.global_position.z).length() > 2.0:
					promo_jumps += 1
		modes = cur
		vis_at = cur_vis

	func _terrain_clear(a: Vector3, b: Vector3) -> bool:
		var data := (Game.world as World).data
		var n := int(a.distance_to(b) / 5.0) + 2
		for i in range(1, n):
			var q := a.lerp(b, float(i) / n)
			if data.height_at(q.x, q.z) > q.y + 0.3:
				return false
		return true

	## Crops of the swap frame and the next one around the demoted car.
	func _capture(real: Vector3, n: int) -> void:
		busy = true
		var cam := get_viewport().get_camera_3d()
		var sp := cam.unproject_position(real + Vector3.UP * 0.8)
		for k in 2:
			await RenderingServer.frame_post_draw
			var img := get_viewport().get_texture().get_image()
			var tag := "swap" if k == 0 else "next"
			var base: String = String(test.get("out_dir")).path_join("lodswap_%d_%s" % [n, tag])
			img.save_png(base + "_full.png")
			# unproject_position works in the stretch base size; the image has the window size.
			var px := Vector2i(sp * Vector2(img.get_size()) / get_viewport().get_visible_rect().size)
			var rect := Rect2i(px - Vector2i(80, 45), Vector2i(160, 90)).intersection(Rect2i(Vector2i.ZERO, img.get_size()))
			if rect.size.x > 20 and rect.size.y > 20:
				var crop := img.get_region(rect)
				crop.resize(rect.size.x * 4, rect.size.y * 4, Image.INTERPOLATE_NEAREST)
				crop.save_png(base + ".png")
			test.call("log_line", "shot %s (car at pixel %s)" % [ProjectSettings.globalize_path(base + "_full.png"), str(px)])
		busy = false


## Noon: fog must light all traffic near the player, clear weather none; then the ring tunnel (camera inside
## it, player outside): cars in the tunnel lit, cars on the open road not.
func _scenario_lights() -> void:
	var w := Game.world as World
	var t: Node = _traffic()
	t.set_density(1.0)
	Game.set_time_of_day(12.0)
	Game.set_time_scale(0.0)
	var x := w.data.network.get_road("expressway")
	var s := 600.0
	var p := x.surface_point(s, x.width * 0.5 + x.shoulder + 3.0)
	p.y = maxf(p.y, w.height_at(p.x, p.z))
	main.teleport_to({"position": p, "forward": x.flat_tangent_at(s)})
	await _settle()
	var out := {}
	var ok := true
	for wid: String in ["fog", "clear"]:
		Game.set_weather(wid, true)
		await _wait(3.0)
		var lit := 0
		var total := 0
		var shot_taken := false
		for k in 10:
			await _wait(2.0)
			_hold_player()
			var pp := Game.player_car.global_position
			var best: TrafficVehicle = null
			var bd := INF
			for v: TrafficVehicle in t.vehicles:
				var d := v.position.distance_to(pp)
				if d < 400.0:
					total += 1
					if _vehicle_lit(v):
						lit += 1
				if d > 25.0 and d < 90.0 and d < bd:
					bd = d
					best = v
			if best != null and not shot_taken:
				# The nearest traffic car 25-90 m away, seen from the shoulder.
				shot_taken = true
				cam.global_position = pp + Vector3.UP * 2.2
				cam.look_at(best.position + Vector3.UP * 0.8, Vector3.UP)
				cam.fov = 40.0
				cam.current = true
				await _wait(0.1)
				await _shot("lights_%s" % wid)
				cam.fov = 60.0
		out[wid] = "%d/%d lit" % [lit, total]
		log_line("lights %s at noon: %d of %d vehicle samples lit (env lights_needed %s)" % [wid, lit, total, Game.env.call("lights_needed")])
		ok = ok and total > 0 and (lit == total if wid == "fog" else lit == 0)
	# Ring tunnel, camera 60 m inside, player parked 40 m before the portal.
	var ring := w.data.network.get_road("ring")
	var s0 := -1.0
	var s1 := -1.0
	var ss := 0.0
	while ss < ring.length:
		if (ring.flag_at(ss) & 2) != 0:
			if s0 < 0.0:
				s0 = ss
			s1 = ss
		ss += 3.0
	var ps := s0 - 40.0
	var pt := ring.surface_point(ps, ring.width * 0.5 + ring.shoulder + 3.0)
	pt.y = maxf(pt.y, w.height_at(pt.x, pt.z))
	main.teleport_to({"position": pt, "forward": ring.flat_tangent_at(ps)})
	await _settle()
	var cs := s0 + 60.0
	cam.global_position = ring.surface_point(cs, 0.0) + Vector3.UP * 2.6
	cam.look_at(ring.surface_point(cs + 80.0, 0.0) + Vector3.UP, Vector3.UP)
	cam.fov = 55.0
	cam.current = true
	var in_lit := 0
	var in_total := 0
	var open_lit := 0
	var open_total := 0
	var shots := 0
	var tt := 0.0
	while tt < float(_arg("seconds", "60")):
		await _wait(0.5)
		tt += 0.5
		_hold_player()
		cam.current = true
		for v: TrafficVehicle in t.vehicles:
			if v.conn != null:
				continue
			var inside := v.lane.road == ring and (ring.flag_at(v.s) & 2) != 0
			var near_portal := v.lane.road == ring and (ring.flag_at(v.lane.advance(v.s, 40.0)) & 2) != 0
			if inside:
				in_total += 1
				in_lit += 1 if _vehicle_lit(v) else 0
				if not _vehicle_lit(v) and _detail_logs < 25:
					_detail_logs += 1
					log_line("UNLIT in tunnel #%d %s %s s=%.0f light_state %d headlights_on %s flash %.2f hazard %s" % [v.uid, v.data.id,
						"PHYS" if v.mode == TrafficVehicle.Mode.PHYSICS else "kin", v.s, v.light_state, v.car.headlights_on if v.car else false, v.flash_t, v.hazard])
				var d := v.position.distance_to(cam.global_position)
				if shots < 2 and d > 18.0 and d < 60.0 and _vehicle_lit(v) and cam.is_position_in_frustum(v.position + Vector3.UP):
					shots += 1
					await _shot("lights_tunnel_%d" % shots)
					cam.current = true
			elif not near_portal:
				open_total += 1
				open_lit += 1 if _vehicle_lit(v) else 0
	log_line("lights tunnel (clear noon, camera in the tunnel, env lights_needed %s): in tunnel %d/%d lit, open road %d/%d lit" % [Game.env.call("lights_needed"), in_lit, in_total, open_lit, open_total])
	out["tunnel"] = "%d/%d lit" % [in_lit, in_total]
	out["open_road_while_cam_in_tunnel"] = "%d/%d lit" % [open_lit, open_total]
	report["lights"] = out
	cam.fov = 60.0
	ok = ok and in_total > 0 and in_lit == in_total and open_lit == 0
	_result("lights", ok, JSON.stringify(out))


func _vehicle_lit(v: TrafficVehicle) -> bool:
	if v.mode == TrafficVehicle.Mode.KINEMATIC:
		return v.light_state >= 2
	if v.car == null or not v.car.headlights_on:
		return false
	var vis := v.car.get_node_or_null("Visual") as CarVisuals
	if vis == null or vis.headlights.is_empty():
		return true
	for l in vis.headlights:
		if l.visible and l.light_energy > 1.0:
			return true
	return false


## Parked cars at a village (--poi=Gullhaven): ray under each wheel's contact point along the car's up axis.
## Fails when any car within 220 m has a wheel more than 8 cm off the street (floating or sunk).
func _scenario_parked() -> void:
	var t: Node = _traffic()
	t.set_density(0.0)
	var poi := _arg("poi", "Gullhaven")
	Game.teleport(poi)
	await _settle()
	await _wait(2.0)
	var space := get_viewport().world_3d.direct_space_state
	var parked: Array = t.get("_parked")
	var models: Array = t.get("_models")
	var pp := Game.player_car.global_position
	var n := 0
	var bad := 0
	var worst := 0.0
	var steep: Array = []
	for slot: Dictionary in parked:
		if not slot.has("vis"):
			continue
		var at: Vector3 = slot["pos"]
		if at.distance_to(pp) > 220.0:
			continue
		n += 1
		var b: Basis = slot["basis"]
		var ti: int = slot["type"]
		var info: Dictionary = models[ti]
		var cd: CarData = info["car_data"]
		var gaps: PackedStringArray = []
		var car_worst := 0.0
		for corner: Vector2 in [Vector2(-1, 1), Vector2(1, 1), Vector2(-1, -1), Vector2(1, -1)]:
			var track := cd.track_front if corner.y > 0.0 else cd.track_rear
			var lp := at + b.x * (corner.x * track * 0.5) - b.z * (corner.y * cd.wheelbase * 0.5)
			var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(lp + b.y * 1.5, lp - b.y * 1.5, 1))
			if hit.is_empty():
				gaps.append("none")
				car_worst = 9.0
				continue
			var col: Object = hit["collider"]
			var gap := (lp - (hit["position"] as Vector3)).dot(b.y)
			gaps.append("%+.2f%s" % [gap, "" if col.has_meta(&"road") else "(terrain)"])
			if absf(gap) > absf(car_worst):
				car_worst = gap
		var res := (Game.world as World).data.network.nearest(at, 20.0, func(r: RoadNetwork.Road) -> bool: return r.traffic)
		var lat: float = float(res.get("lateral", 0.0))
		var grade := -b.z.y
		log_line("parked %s at %s lat %+.2f grade %+.1f%% roll %+.1f deg wheel gaps (FL FR RL RR) %s" % [t.types[ti].id, str(at.round()), lat, grade * 100.0,
			rad_to_deg(asin(clampf(b.x.y, -1.0, 1.0))), " ".join(gaps)])
		if absf(car_worst) > 0.08:
			bad += 1
		worst = maxf(worst, absf(car_worst))
		steep.append([absf(grade), slot])
	steep.sort_custom(func(a: Array, c: Array) -> bool: return a[0] > c[0])
	for k in mini(2, steep.size()):
		var sl: Dictionary = steep[k][1]
		var sb: Basis = sl["basis"]
		var sat: Vector3 = sl["pos"]
		# Low side view from the street.
		var side := -sb.x if (sat - pp).dot(sb.x) > 0.0 else sb.x
		cam.global_position = sat + side * 6.0 + Vector3.UP * 0.8
		cam.look_at(sat + Vector3.UP * 0.4, Vector3.UP)
		cam.current = true
		await _wait(0.2)
		await _shot("parked_%s_%d_side" % [poi, k])
		cam.global_position = sat + sb.z * 7.0 + Vector3.UP * 1.0
		cam.look_at(sat + Vector3.UP * 0.4, Vector3.UP)
		cam.current = true
		await _wait(0.2)
		await _shot("parked_%s_%d_rear" % [poi, k])
	report["parked"] = {"poi": poi, "slots_total": parked.size(), "checked": n, "bad": bad, "worst_m": worst}
	_result("parked", n > 0 and bad == 0, "%s: %d parked cars checked (of %d slots), %d with a wheel > 8 cm off the ground, worst %.3f m" % [poi, n, parked.size(), bad, worst])


## Player at 60 km/h in the expressway's outer lane at density 1.0: faster traffic must pass instead of
## following for kilometres. Fails when a car wanting 15+ km/h more sits behind the player for 30 s.
func _scenario_overtake() -> void:
	var w := Game.world as World
	var t: Node = _traffic()
	t.set_density(float(_arg("density", "1.0")))
	var road := w.data.network.get_road("expressway")
	var f := RoadFollower.new()
	var start := float(_arg("start", "200"))
	f.setup(road, start, 1, road.lane_offset(road.lanes))
	f.target_speed = float(_arg("speed", "60")) / 3.6
	f.respect_traffic = true
	main.teleport_to({"position": f.lane_point(start), "forward": road.flat_tangent_at(start)})
	await _settle()
	var follow := {}
	var behind := {}
	var max_follow := 0.0
	var worst := "-"
	var passes := 0
	var lc0: int = t.get_stats()["lane_changes"]
	var tt := 0.0
	var next := 0.0
	var next_shot := 20.0
	var pc := Game.player_car
	while tt < float(_arg("seconds", "100")) and not f.finished:
		await get_tree().physics_frame
		f.drive(pc, get_physics_process_delta_time())
		await get_tree().process_frame
		tt += get_process_delta_time()
		if tt < next:
			continue
		next += 0.5
		var pp := pc.global_position
		var pf := -pc.global_transform.basis.z
		for v: TrafficVehicle in t.vehicles:
			if v.conn != null or v.lane.road != road or v.lane.dir != 1:
				continue
			var rel := (v.position - pp).dot(pf)
			if absf(rel) > 250.0:
				continue
			if rel < -6.0:
				behind[v.uid] = true
			elif rel > 6.0 and behind.has(v.uid):
				passes += 1
				behind.erase(v.uid)
			if v.lead_is_player and v.v_desired > pc.speed_ms + 4.2:
				var ft: float = float(follow.get(v.uid, 0.0)) + 0.5
				follow[v.uid] = ft
				if ft > max_follow:
					max_follow = ft
					worst = "#%d %s wants %.0f km/h, %s lead %.0f m" % [v.uid, v.data.id, v.v_desired * 3.6, _where(v), v.lead_gap]
			else:
				follow.erase(v.uid)
		if tt >= next_shot:
			next_shot += 20.0
			log_line("t=%.0f player %.0f km/h s=%.0f passes %d lane changes +%d longest follow %.1f s (%s)" % [tt, pc.get_speed_kmh(), f.s, passes,
				int(t.get_stats()["lane_changes"]) - lc0, max_follow, worst])
			cam.global_position = pp + pf * 4.0 + Vector3.UP * 4.5 - pf.cross(Vector3.UP) * 7.0
			cam.look_at(pp - pf * 28.0, Vector3.UP)
			cam.current = true
			await _shot("overtake_%03d" % int(tt))
	report["overtake"] = {"passes": passes, "longest_follow_s": max_follow, "worst": worst, "lane_changes": int(t.get_stats()["lane_changes"]) - lc0}
	_result("overtake", max_follow < 30.0 and passes >= 1, "%d vehicles passed the player, longest time a faster car followed it %.1f s (%s), lane changes %d" % [
		passes, max_follow, worst, int(t.get_stats()["lane_changes"]) - lc0])


## One vehicle of each --types= on the ring's highland climb (dir +1 from s=4060, 10 % at s 4250-4450 and
## 4700-5000) in physics LOD, the player following. Fails when a lorry/coach averages under 25 km/h or drops
## under 12 km/h on the climb.
func _scenario_climb() -> void:
	var w := Game.world as World
	var t: Node = _traffic()
	var road := w.data.network.get_road("ring")
	var graph: LaneGraph = t.graph
	var lane: LaneGraph.Lane = null
	for l: LaneGraph.Lane in graph.lanes_of(road):
		if l.dir == 1 and l.outer:
			lane = l
	var ok := true
	var parts: PackedStringArray = []
	for type_id: String in _arg("types", "lorry_box,bus_coach,van_delivery").split(","):
		var ti := -1
		for i in t.types.size():
			if t.types[i].id == type_id:
				ti = i
		if ti < 0:
			continue
		t.set_density(0.0)
		_park_player(road, 3990.0)
		await _settle()
		_park_player(road, 3990.0)
		var v: TrafficVehicle = t.call("_new_vehicle", ti, lane, 4060.0)
		var f := RoadFollower.new()
		f.setup(road, 3990.0, 1, road.lane_offset(1))
		f.target_speed = 90.0 / 3.6
		f.respect_traffic = true
		var pc := Game.player_car
		pc.in_handbrake = 0.0
		var n := 0
		var sum := 0.0
		var vmin := INF
		var tt := 0.0
		var next := 0.0
		var shot_done := false
		var phys_samples := 0
		while tt < 170.0 and t.vehicles.has(v) and v.s < 5000.0:
			await get_tree().physics_frame
			f.drive(pc, get_physics_process_delta_time())
			await get_tree().process_frame
			tt += get_process_delta_time()
			if tt < next:
				continue
			next += 0.5
			if v.s > 4250.0 and v.conn == null:
				n += 1
				sum += v.speed
				vmin = minf(vmin, v.speed)
				if v.mode == TrafficVehicle.Mode.PHYSICS:
					phys_samples += 1
				if not shot_done and v.s > 4380.0:
					shot_done = true
					_aim_cam(v.position, 12.0, 3.5)
					await _shot("climb_%s" % type_id)
				if int(tt * 2.0) % 20 == 0 and v.car != null:
					log_line("climb %s s=%.0f %.0f km/h tgt %.0f gear %d rpm %.0f thr %.2f" % [type_id, v.s, v.speed * 3.6, v.v_target * 3.6, v.car.gear, v.car.rpm, v.car.in_throttle])
		var avg := sum / maxf(n, 1.0) * 3.6
		var heavy := type_id in ["lorry_box", "bus_coach"]
		var good := n > 20 and phys_samples > n / 2 and (not heavy or (avg >= 25.0 and vmin * 3.6 >= 12.0))
		ok = ok and good
		parts.append("%s avg %.1f km/h min %.1f km/h on s 4250-%.0f in %.0f s (%d samples, %d physics)" % [type_id, avg, vmin * 3.6, v.s, tt, n, phys_samples])
		log_line("climb " + parts[parts.size() - 1])
		t.call("_flush_all")
	report["climb"] = parts
	_result("climb", ok, "; ".join(parts))


# ----------------------------------------------------------------- round-2 playtest regressions

## q1: Kestrel R4 parked 16 m right of the Sunward Ring (Verdant Vale, near --at=-626,500), facing the flow. Each of
## --trials (5; run twice, --at=-1184,453 for the second site) waits for a traffic car in the near lane at 45-85 km/h 11-25 m short of the respawn point, then
## sends a real R key press (reset_car through CarInput; --via=teleport: an exact placement on the lane, the
## teleport / event-respawn path) and takes no further input for 4 s. Fails when traffic
## touches the respawned car (impact with a vehicle beside it, the car shoved, or a hit car going into hazard).
func _scenario_respawn() -> void:
	var w := Game.world as World
	var t: Node = _traffic()
	var cat := Game.get_car_catalog()
	for i in cat.size():
		if cat[i].id == _arg("car", "kestrel_r4"):
			Game.spawn_car(i, true)
	Game.set_weather("clear", true)
	if _arg("time", "") == "":
		Game.set_time_of_day(13.0)
		Game.set_time_scale(0.0)
	var at := _arg("at", "-626,500").split(",")
	var res := w.data.network.nearest(Vector3(float(at[0]), 0.0, float(at[1])), 200.0, func(r: RoadNetwork.Road) -> bool: return r.id == "ring")
	var road: RoadNetwork.Road = res["road"]
	var s_park: float = res["s"]
	var park := road.surface_point(s_park, road.width * 0.5 + road.shoulder + 16.0)
	park.y = w.height_at(park.x, park.z)
	var fwd := road.flat_tangent_at(s_park)
	main.teleport_to({"position": park, "forward": fwd})
	await _settle()
	t.set_density(float(_arg("density", "1.0")))
	var pc := Game.player_car
	var hit_log: Array = []
	var on_impact := func(strength: float, pos: Vector3) -> void: hit_log.append([strength, pos])
	var trials := int(_arg("trials", "5"))
	var hits := 0
	var done := 0
	var lines: PackedStringArray = []
	var made0: int = int(t.get_stats().get("made_way", 0))
	for trial in trials:
		main.car_input.enabled = false
		if pc.global_position.distance_to(park) > 3.0:
			main.teleport_to({"position": park, "forward": fwd})
			await _wait(1.0)
		_hold_player()
		var spot := w.nearest_road_point(pc.global_position)
		var spot_s: float = spot["s"]
		var cand: TrafficVehicle = null
		var tt := 0.0
		# Press R when the car is a random 11-25 m short of the point (as in the playtest repro).
		var trigger := 11.0 + 14.0 * fposmod(trial * 0.618, 1.0)
		while cand == null and tt < 90.0:
			await get_tree().process_frame
			tt += get_process_delta_time()
			_hold_player()
			for v: TrafficVehicle in t.vehicles:
				if v.conn != null or v.lane.road != road or v.lane.dir != 1 or v.hazard:
					continue
				var d := v.lane.sdist(v.s, spot_s)
				if v.speed * 3.6 >= 45.0 and v.speed * 3.6 <= 85.0 and d >= 10.0 and d <= trigger:
					cand = v
					break
		if cand == null:
			log_line("respawn trial %d: no traffic car came by" % trial)
			continue
		var cand_kmh := cand.speed * 3.6
		var cand_gap := cand.lane.sdist(cand.s, spot_s)
		var hz0: int = t.get_stats()["hazards"]
		var sh0: int = t.get_stats()["shunts"]
		var mw0: int = int(t.get_stats().get("made_way", 0))
		pc.in_throttle = 0.0
		pc.in_brake = 0.0
		pc.in_handbrake = 0.0
		main.car_input.enabled = true
		hit_log.clear()
		pc.impact.connect(on_impact)
		if _arg("via", "key") == "teleport":
			# Exact placement (teleport / event respawn path): the spot is kept and traffic makes way.
			main.teleport_to({"position": spot["position"], "forward": spot["forward"]})
		else:
			_key(KEY_R, true)
			await get_tree().process_frame
			_key(KEY_R, false)
		await get_tree().physics_frame
		var p0 := pc.global_position
		var placed := w.data.network.nearest(p0, 30.0, func(r: RoadNetwork.Road) -> bool: return r == road)
		var moved_m := road.length
		if not placed.is_empty():
			moved_m = fposmod(float(placed["s"]) - spot_s + road.length * 0.5, road.length) - road.length * 0.5
		var min_clear := INF
		var max_kmh := 0.0
		var touch := 0
		var t2 := 0.0
		var shot := false
		while t2 < 4.0:
			await get_tree().physics_frame
			t2 += get_physics_process_delta_time()
			max_kmh = maxf(max_kmh, pc.get_speed_kmh())
			var pf := -pc.global_transform.basis.z
			pf = Vector3(pf.x, 0.0, pf.z).normalized()
			for v2: TrafficVehicle in t.vehicles:
				# Gap between the two bodies (separating axis along / across the player): < 0 = touching.
				var rel := v2.position - pc.global_position
				var c_al := absf(v2.heading.dot(pf))
				var c_ac := sqrt(maxf(1.0 - c_al * c_al, 0.0))
				var along_gap := absf(rel.dot(pf)) - pc.data.body_size.z * 0.5 - (c_al * v2.length + c_ac * v2.half_width * 2.0) * 0.5
				var side_gap := absf(rel.dot(pf.cross(Vector3.UP))) - pc.data.body_size.x * 0.5 - (c_ac * v2.length + c_al * v2.half_width * 2.0) * 0.5
				min_clear = minf(min_clear, maxf(along_gap, side_gap))
				for h: Array in hit_log:
					if (h[1] as Vector3).distance_to(v2.position) < v2.length * 0.5 + 2.0:
						touch += 1
			hit_log.clear()
			if not shot and t2 > 1.5 and (trial < 2 or touch > 0):
				shot = true
				await _shot("respawn_trial%d" % trial)
		pc.impact.disconnect(on_impact)
		var hz: int = int(t.get_stats()["hazards"]) - hz0
		var sh: int = int(t.get_stats()["shunts"]) - sh0
		# No input after R: an automatic gearbox creeps at idle (~9 km/h); a shove shows as a contact or a hit car.
		var hit := touch > 0 or min_clear < 0.0 or max_kmh > 20.0 or hz + sh > 0
		done += 1
		if hit:
			hits += 1
		var line := "trial %d: %s at %.0f km/h %.1f m short of the respawn point -> placed %+.0f m along the road, %.1f m off the centre; min body gap to traffic in 4 s %.1f m, player max %.0f km/h, contacts %d, hazards/shunts %d/%d, made way %d -> %s" % [
			trial, cand.data.id, cand_kmh, cand_gap, moved_m, absf(float(placed.get("lateral", 0.0))) if not placed.is_empty() else -1.0, min_clear, max_kmh, touch, hz, sh,
			int(t.get_stats().get("made_way", 0)) - mw0, "HIT" if hit else "clear"]
		lines.append(line)
		log_line("respawn " + line)
	main.car_input.enabled = false
	report["respawn"] = lines
	_result("respawn", done >= trials and hits == 0, "%d of %d respawns next to approaching traffic were rear-ended (made way %d times)" % [hits, done, int(t.get_stats().get("made_way", 0)) - made0])


## q18: --cases (type:closing km/h) on the expressway (dir +1, outer lane, from --s=950, density 0): the player
## follows the lane at the traffic car's speed + closing, and after the contact lifts off, brakes 0.35 and holds the
## wheel straight. Fails when a hit car turns more than 15 deg off its lane or leaves the paved road within 6 s,
## or when a hit under 30 km/h closing starts hazard mode.
func _scenario_ram() -> void:
	var w := Game.world as World
	var t: Node = _traffic()
	var road := w.data.network.get_road(_arg("road", "expressway"))
	var graph: LaneGraph = t.graph
	var lane: LaneGraph.Lane = null
	for l: LaneGraph.Lane in graph.lanes_of(road):
		if l.dir == 1 and l.outer:
			lane = l
	var ok := true
	var parts: PackedStringArray = []
	var pc := Game.player_car
	var cases := _arg("cases", "van_delivery:11,van_delivery:24,van_delivery:38,van_delivery:45,hatch_small:24,hatch_small:45,hatch_small:70").split(",")
	var s0 := float(_arg("s", "950"))
	for cs: String in cases:
		var type_id := cs.get_slice(":", 0)
		var closing := float(cs.get_slice(":", 1)) / 3.6
		var ti := -1
		for i in t.types.size():
			if t.types[i].id == type_id:
				ti = i
		t.set_density(0.0)
		t.call("_flush_all")
		main.teleport_to({"position": road.surface_point(s0 - 50.0, road.lane_offset(road.lanes)), "forward": road.flat_tangent_at(s0 - 50.0)})
		await _settle()
		_hold_player()
		var v: TrafficVehicle = t.call("_new_vehicle", ti, lane, s0)
		v.speed = v.v_desired
		await _wait(0.6)
		# Start 30 m behind at the closing speed.
		var f := RoadFollower.new()
		var sp := v.s - 30.0
		f.setup(road, sp, 1, road.lane_offset(road.lanes))
		f.respect_traffic = false
		f.max_throttle = 1.0
		main.teleport_to({"position": f.lane_point(sp), "forward": road.flat_tangent_at(sp)})
		pc.place_at(pc.global_transform, road.flat_tangent_at(sp) * (v.speed + closing), Vector3.ZERO, 0)
		pc.in_handbrake = 0.0
		var tt := 0.0
		var contact := false
		var hits: Array = []
		var on_impact := func(strength: float, _pos: Vector3) -> void: hits.append(strength)
		pc.impact.connect(on_impact)
		var closing_at := 0.0
		while tt < 15.0 and t.vehicles.has(v):
			await get_tree().physics_frame
			tt += get_physics_process_delta_time()
			f.target_speed = v.speed + closing
			f.drive(pc, get_physics_process_delta_time())
			var gap := (v.position - pc.global_position).dot(v.heading) - (v.length + pc.data.body_size.z) * 0.5
			if gap < 0.25 or not hits.is_empty():
				contact = true
				closing_at = (pc.linear_velocity - v.heading * v.speed).dot(v.heading) * 3.6
				break
		if not contact:
			pc.impact.disconnect(on_impact)
			parts.append("%s %.0f: no contact" % [type_id, closing * 3.6])
			ok = false
			continue
		var phys := v.mode == TrafficVehicle.Mode.PHYSICS
		var v0 := v.speed * 3.6
		var max_yaw := 0.0
		var max_lat := 0.0
		var hazard := false
		var shaken := false
		var trace: PackedStringArray = []
		var t2 := 0.0
		var next := 0.0
		var shots := 0
		while t2 < 6.0 and t.vehicles.has(v):
			await get_tree().physics_frame
			t2 += get_physics_process_delta_time()
			pc.in_throttle = 0.0
			pc.in_brake = 0.35
			pc.in_steer = 0.0
			pc.in_handbrake = 0.0
			hazard = hazard or v.hazard
			shaken = shaken or v.shaken_t > 0.0
			if t2 < next:
				continue
			next += 0.1
			var vs := LaneGraph.project_s(road, v.position, v.s if v.conn == null else s0)
			var tan := road.flat_tangent_at(vs)
			var hf := Vector3(v.heading.x, 0.0, v.heading.z).normalized()
			var yaw := rad_to_deg(acos(clampf(hf.dot(tan), -1.0, 1.0)))
			var lat := (v.position - road.point_at(vs)).dot(road.right_at(vs))
			max_yaw = maxf(max_yaw, yaw)
			max_lat = maxf(max_lat, absf(lat))
			if int(t2 * 10.0) % 5 == 0:
				trace.append("%.1f:%.0fdeg/%.1fm/%.0fkmh%s" % [t2, yaw, lat, v.speed * 3.6, "H" if v.hazard else ("S" if v.shaken_t > 0.0 else "")])
			if (shots == 0 and t2 > 0.3) or (shots == 1 and t2 > 2.5):
				shots += 1
				_aim_cam(v.position, 13.0, 4.5)
				await _shot("ram_%s_%d_%d" % [type_id, int(closing * 3.6), shots])
		pc.impact.disconnect(on_impact)
		var paved := road.width * 0.5
		var good := max_yaw < 15.0 and max_lat < paved and (closing_at >= 30.0 or not hazard)
		ok = ok and good
		var line := "%s closing %.0f km/h (set %.0f) at %.0f km/h, %s, peak impact %.1f: %s, max yaw %.1f deg, max lateral %.1f m (paved %.2f) -> %s" % [
			type_id, closing_at, closing * 3.6, v0, "physics" if phys else "KINEMATIC", hits.max() if not hits.is_empty() else 0.0,
			"hazard" if hazard else ("shunt" if shaken else "no reaction"), max_yaw, max_lat, paved, "ok" if good else "BAD"]
		parts.append(line)
		log_line("ram " + line)
		log_line("ram trace " + " ".join(trace))
	t.call("_flush_all")
	report["ram"] = parts
	_result("ram", ok, "; ".join(parts))


## q19: player stopped in the expressway's outer lane (dir +1, --s=1100) for --seconds (120) at density 1.0, or
## parked on the hard shoulder at lateral 8.05 m (--where=shoulder), or alone with one hatch injected standing --gap (8) m
## behind it (--where=inject, --bg-density 0, must pass within 20 s). Fails when a vehicle stands behind the player for --max-stand (25) s,
## when traffic touches the player, or (shoulder) when a vehicle stops for the parked car at all.
func _scenario_pullout() -> void:
	var w := Game.world as World
	var t: Node = _traffic()
	var road := w.data.network.get_road("expressway")
	var where := _arg("where", "lane")
	var s := float(_arg("s", "1100"))
	var lat := 8.05 if where == "shoulder" else road.lane_offset(road.lanes)
	t.set_density(0.0)
	main.teleport_to({"position": road.surface_point(s, lat), "forward": road.flat_tangent_at(s)})
	await _settle()
	_hold_player()
	var pc := Game.player_car
	var touches: Array = []
	var on_impact := func(strength: float, pos: Vector3) -> void: touches.append([strength, pos])
	pc.impact.connect(on_impact)
	var lane2: LaneGraph.Lane = null
	for l: LaneGraph.Lane in (t.graph as LaneGraph).lanes_of(road):
		if l.dir == 1 and l.outer:
			lane2 = l
	var ps := LaneGraph.project_s(road, pc.global_position, s)
	var injected: TrafficVehicle = null
	var pass_t := -1.0
	if where == "inject":
		# A hatch standing --gap (8) m behind the player (bumper to bumper), as if it had stopped there.
		injected = t.call("_new_vehicle", 0, lane2, ps - float(_arg("gap", "8")) - 2.0 - pc.data.body_size.z * 0.5)
		injected.speed = 0.0
		# --bg-density: other traffic around it (the passing lane then has to clear first).
		t.set_density(float(_arg("bg-density", "0")))
	else:
		t.set_density(float(_arg("density", "1.0")))
	var seconds := float(_arg("seconds", "60" if where == "inject" else "120"))
	var stand := {}
	var behind := {}
	var passes := 0
	var max_stand := 0.0
	var worst := "-"
	var stopped_for := 0
	var lc0: int = t.get_stats()["lane_changes"]
	var honk0: int = t.get_stats()["honks"]
	var bumps := 0
	var tt := 0.0
	var next := 0.0
	var next_shot := 1.5 if where == "inject" else 15.0
	while tt < seconds:
		await get_tree().process_frame
		tt += get_process_delta_time()
		_hold_player()
		for h: Array in touches:
			for v: TrafficVehicle in t.vehicles:
				if (h[1] as Vector3).distance_to(v.position) < v.length * 0.5 + 2.0:
					bumps += 1
					log_line("t=%.1f traffic touched the player: #%d %s impact %.1f" % [tt, v.uid, v.data.id, h[0]])
		touches.clear()
		if tt < next:
			continue
		next += 0.5
		var pp := pc.global_position
		var pf := road.flat_tangent_at(ps)
		for v: TrafficVehicle in t.vehicles:
			var r := v.conn.to_lane.road if v.conn != null else v.lane.road
			if r != road or v.heading.dot(pf) < 0.5:
				continue
			var rel := (v.position - pp).dot(pf)
			if absf(rel) > 200.0:
				continue
			if rel < -6.0:
				behind[v.uid] = true
			elif rel > 6.0 and behind.has(v.uid):
				passes += 1
				behind.erase(v.uid)
				if v == injected:
					pass_t = tt
					log_line("t=%.1f the injected %s passed the player" % [tt, v.data.id])
			if rel < 0.0 and rel > -40.0 and v.speed < 0.5 and v.lead_is_player:
				var st: float = float(stand.get(v.uid, 0.0)) + 0.5
				stand[v.uid] = st
				if st == 0.5:
					stopped_for += 1
				if st > max_stand:
					max_stand = st
					worst = "#%d %s %s lead %.1f m" % [v.uid, v.data.id, _where(v), v.lead_gap]
			else:
				stand.erase(v.uid)
		if tt >= next_shot:
			next_shot += 1.0 if where == "inject" and tt < 6.0 else 15.0
			log_line("t=%.0f passes %d lane changes +%d longest stand %.1f s (%s) honks +%d" % [tt, passes, int(t.get_stats()["lane_changes"]) - lc0, max_stand, worst, int(t.get_stats()["honks"]) - honk0])
			cam.global_position = pp + pf * 10.0 + Vector3.UP * 24.0 - pf.cross(Vector3.UP) * 3.0
			cam.look_at(pp - pf * 10.0, Vector3.UP)
			cam.current = true
			await _shot("pullout_%s_%03d" % [where, int(tt)])
	pc.impact.disconnect(on_impact)
	var limit := float(_arg("max-stand", "25"))
	var good := max_stand < limit and bumps == 0 and passes >= 1
	if where == "shoulder":
		good = good and stopped_for == 0
	if where == "inject":
		good = bumps == 0 and pass_t > 0.0 and pass_t < 20.0
		log_line("injected standing hatch passed after %.1f s" % pass_t)
	report["pullout"] = {"where": where, "passes": passes, "longest_stand_s": max_stand, "worst": worst, "stopped_for_player": stopped_for, "touches": bumps,
		"honks": int(t.get_stats()["honks"]) - honk0}
	_result("pullout", good, "%s: %d vehicles passed the stopped player, %d stopped behind it, longest stand %.1f s (%s), traffic touched the player %d times, honks %d" % [
		where, passes, stopped_for, max_stand, worst, bumps, int(t.get_stats()["honks"]) - honk0])


## q22: density 1.0 for --seconds (160) beside the Sunward Expressway west end (junction 0 on the ring), with a lorry,
## a coach and a lorry placed on the expressway towards it (--inject=types). Every
## vehicle that gives way there is timed from standing at the line to entering the junction, and a go taken back
## while it stands at the line is counted. Fails on a head-of-queue wait of --max-wait (30) s or more, or any such
## revocation.
func _scenario_giveway() -> void:
	var t: Node = _traffic()
	t.set_density(float(_arg("density", "1.0")))
	var j := _find_junction(_arg("child", "expressway"), int(_arg("end", "0")))
	await _park_beside_junction(j)
	# --inject=types: heavy vehicles placed on the minor road 150 m and more before the line, 70 m apart (they
	# are the ones that waited longest in the playtest).
	var k := 0
	for type_id: String in _arg("inject", "lorry_box,bus_coach,lorry_box").split(",", false):
		for i in t.types.size():
			if t.types[i].id == type_id:
				for l: LaneGraph.Lane in (t.graph as LaneGraph).lanes_of(j.child):
					var to_j := false
					for dd: LaneGraph.Decision in l.decisions:
						to_j = to_j or (dd.mandatory and dd.junction == j)
					if l.outer and to_j:
						t.call("_new_vehicle", i, l, l.advance(j.stop_s, -150.0 - 70.0 * k))
						k += 1
	var arrive := {}
	var by_type := {}
	var last_go := {}
	var waits: Array = []
	var worst := 0.0
	var worst_s := "-"
	var revoked := 0
	var max_queue := 0
	var tt := 0.0
	var next_log := 20.0
	var seconds := float(_arg("seconds", "160"))
	while tt < seconds:
		await get_tree().process_frame
		tt += get_process_delta_time()
		_hold_player()
		var queue := 0
		for v: TrafficVehicle in t.vehicles:
			if v.conn != null:
				if arrive.has(v.uid) and v.conn.junction == j:
					var wt: float = tt - float(arrive[v.uid])
					waits.append(wt)
					by_type[v.data.id] = "%s %.1f" % [by_type.get(v.data.id, ""), wt]
					if wt > worst:
						worst = wt
						worst_s = "#%d %s turn %d" % [v.uid, v.data.id, v.conn.turn]
					arrive.erase(v.uid)
				last_go.erase(v.uid)
				continue
			if v.choice == null or v.choice.junction != j or v.choice.yield_mode != LaneGraph.Yield.MINOR or v.decision == null:
				continue
			var d := v.lane.sdist(v.s, v.decision.at_s)
			var front := v.length * 0.5 + 0.8
			if v.speed < 1.0 and d < 120.0:
				queue += 1
			if d < front + 4.0 and v.speed < 0.6 and not arrive.has(v.uid):
				arrive[v.uid] = tt
			if bool(last_go.get(v.uid, false)) and not v.go and d < front + 1.5:
				revoked += 1
				log_line("t=%.1f go taken back at the line: #%d %s d=%.1f wait %.1f" % [tt, v.uid, v.data.id, d, v.wait_t])
			last_go[v.uid] = v.go
		max_queue = maxi(max_queue, queue)
		if int(tt * 2.0) != int((tt - get_process_delta_time()) * 2.0):
			for v4: TrafficVehicle in t.vehicles:
				if arrive.has(v4.uid) and tt - float(arrive[v4.uid]) > 8.0 and v4.conn == null:
					log_line("t=%.1f #%d %s waiting %.1f s (wait_t %.1f, go %s): %s" % [tt, v4.uid, v4.data.id, tt - float(arrive[v4.uid]), v4.wait_t, v4.go, _gw_blockers(t, v4)])
		for uid: int in arrive.keys():
			var open: float = tt - float(arrive[uid])
			if open > worst:
				worst = open
				worst_s = "#%d (still waiting)" % uid
		if tt >= next_log:
			next_log += 20.0
			log_line("t=%.0f vehicles through %d, worst head wait %.1f s (%s), queue now %d (max %d), go revoked %d" % [tt, waits.size(), worst, worst_s, queue, max_queue, revoked])
			cam.global_position = j.center + Vector3(22.0, 30.0, 22.0)
			cam.look_at(j.center, Vector3.UP)
			cam.current = true
			await _shot("giveway_%03d" % int(tt))
	var avg := 0.0
	for wt2: float in waits:
		avg += wt2
	avg /= maxf(waits.size(), 1.0)
	report["giveway"] = {"through": waits.size(), "avg_wait": avg, "worst_wait": worst, "worst": worst_s, "revoked": revoked, "max_queue": max_queue, "waits_by_type": by_type}
	log_line("giveway waits at the line by type (s): %s" % JSON.stringify(by_type))
	_result("giveway", worst < float(_arg("max-wait", "30")) and revoked == 0 and waits.size() >= 3, "%d vehicles gave way and went (avg %.1f s at the line), worst head wait %.1f s (%s), queue max %d, go taken back at the line %d" % [
		waits.size(), avg, worst, worst_s, max_queue, revoked])


## What holds a vehicle at its give-way line (mirrors TrafficManager._junction_clear, for the log).
func _gw_blockers(t: Node, v: TrafficVehicle) -> String:
	var cn := v.choice
	if cn == null:
		return "no choice"
	var j := cn.junction
	var occ_lane: Dictionary = t.get("_occ_lane")
	var occ_conn: Dictionary = t.get("_occ_conn")
	var patience := clampf((v.wait_t - 5.0) / 7.0, 0.0, 1.0)
	var range_m := lerpf(50.0, 28.0, patience)
	var t_clear := (sqrt(2.0 * cn.length / maxf(float(v.data.accel), 0.5)) + 1.5) * lerpf(1.0, 0.6, patience)
	var out: PackedStringArray = []
	for pl: LaneGraph.Lane in j.parent_lanes:
		if cn.yield_mode == LaneGraph.Yield.MINOR and cn.turn > 0 and pl.dir != cn.to_lane.dir:
			continue
		for w: TrafficVehicle in occ_lane.get(pl.id, []):
			var d := pl.sdist(w.s, j.parent_s)
			if w.speed < 0.5 and d > j.radius + 2.0:
				continue
			if d > -j.radius and d < maxf(range_m, w.speed * t_clear):
				out.append("lane dir %d #%d %s d=%.0f %.0f km/h (range %.0f)" % [pl.dir, w.uid, w.data.id, d, w.speed * 3.6, maxf(range_m, w.speed * t_clear)])
	for c2: LaneGraph.Connector in j.connectors:
		if c2 == cn:
			continue
		var same_merge := c2.to_lane == cn.to_lane and c2.yield_mode == LaneGraph.Yield.MINOR and cn.yield_mode == LaneGraph.Yield.MINOR
		for w2: TrafficVehicle in occ_conn.get(c2.id, []):
			if not (same_merge and w2.c > 8.0):
				out.append("on conn %d (turn %d) #%d %s c=%.0f" % [c2.id, c2.turn, w2.uid, w2.data.id, w2.c])
		for w3: TrafficVehicle in occ_lane.get(c2.from_lane.id, []):
			if w3 != v and w3.choice == c2 and (w3.go or (same_merge and w3.wait_t > v.wait_t + 0.5)):
				out.append("#%d on conn %d's line goes first (go %s, waited %.1f s)" % [w3.uid, c2.id, w3.go, w3.wait_t])
	return "; ".join(out) if not out.is_empty() else "clear (player / AI or not at the line yet)"


## q20: (1) random walks through the lane graph with the traffic manager's own route choice, from every lane piece
## a restricted type may spawn on: every road entered must allow the type (class, and region all along); (2) a
## tractor placed on Wend Valley Road (only exit: the expressway) and a box lorry on Poppy Hill Road dir -1 (only
## exit: Orchard Backroad) in front of the player: they stop before the junction, never turn onto that road;
## (3) density 1.0 beside the Mirror Lake Road / expressway junction for --seconds (90): no vehicle on a road its
## type is not allowed on.
func _scenario_restricted() -> void:
	var w := Game.world as World
	var t: Node = _traffic()
	var graph: LaneGraph = t.graph
	var pieces := {}
	for pc: Dictionary in graph.pieces():
		pieces[pc["key"]] = pc
	var bad := 0
	var walks := 0
	var spawnable := {}
	for type_id: String in ["tractor_farm", "lorry_box", "bus_coach"]:
		var ti := -1
		for i in t.types.size():
			if t.types[i].id == type_id:
				ti = i
		var data: Resource = t.types[ti]
		var starts: Array = []
		for key: Object in pieces:
			var pc2: Dictionary = pieces[key]
			var l: LaneGraph.Lane = pc2["lane"]
			if bool(t.call("_piece_safe", ti, l, l.advance(float(pc2["s1"]), -1.0))):
				starts.append(pc2)
		spawnable[type_id] = starts.size()
		var off: PackedStringArray = []
		for key2: Object in pieces:
			var pc4: Dictionary = pieces[key2]
			var l4: LaneGraph.Lane = pc4["lane"]
			if not bool(t.call("_piece_safe", ti, l4, l4.advance(float(pc4["s1"]), -1.0))):
				var why2 := _piece_violation(data, pc4)
				off.append("%s/%d %.0f-%.0f (%s)" % [l4.road.id, l4.dir, float(pc4["s0"]), float(pc4["s1"]), why2 if why2 != "" else "no way on"])
		log_line("restricted: %s never on %s" % [type_id, ", ".join(off)])
		var rng := RandomNumberGenerator.new()
		rng.seed = 99
		for n in int(_arg("walks", "150")):
			if starts.is_empty():
				break
			var st: Dictionary = starts[rng.randi() % starts.size()]
			var v := TrafficVehicle.new()
			v.type_index = ti
			v.data = data
			v.enter_lane(st["lane"], (st["lane"] as LaneGraph.Lane).advance(float(st["s1"]), -1.0))
			walks += 1
			for step in 40:
				var d := graph.next_decision(v.lane, v.s)
				if d == null:
					break
				var cn: LaneGraph.Connector = t.call("_choose", v, d)
				if v.leaving:
					bad += 1
					log_line("restricted: %s trapped at %s" % [type_id, _where(v)])
					break
				var nl := v.lane if cn == null else cn.to_lane
				var ns := v.lane.advance(d.at_s, 1.0) if cn == null else cn.to_s
				var pk: Object = graph.piece_key(nl, ns)
				var why := _piece_violation(data, pieces.get(pk, {}))
				if why != "":
					bad += 1
					log_line("restricted: %s routed onto %s dir %d (%s)" % [type_id, nl.road.id, nl.dir, why])
					break
				v.enter_lane(nl, ns)
	log_line("restricted walks: %d walks, %d violations; spawnable pieces %s" % [walks, bad, JSON.stringify(spawnable)])
	# (2) Hand-placed restricted vehicles on trapped lanes, watched by the player.
	var placed_ok := true
	var placed_parts: PackedStringArray = []
	for spec: String in _arg("place", "tractor_farm:vale_north:1:330,lorry_box:vale_loop:-1:200").split(","):
		var bits := spec.split(":")
		t.set_density(0.0)
		t.call("_flush_all")
		var r := w.data.network.get_road(bits[1])
		var dir := int(bits[2])
		var s0 := float(bits[3])
		var ti2 := -1
		for i in t.types.size():
			if t.types[i].id == bits[0]:
				ti2 = i
		var lane: LaneGraph.Lane = null
		for l2: LaneGraph.Lane in graph.lanes_of(r):
			if l2.dir == dir and l2.outer:
				lane = l2
		var dec := graph.next_decision(lane, s0)
		var stop_p := lane.point(dec.at_s, lane.offset)
		# Player beside the road just past the stop line, looking back at the vehicle coming.
		var look := lane.point(lane.advance(dec.at_s, -40.0), lane.offset)
		var side := stop_p + (stop_p - look).normalized() * 6.0 + r.right_at(dec.at_s) * float(dir) * (r.width * 0.5 + r.shoulder + 9.0)
		side.y = w.height_at(side.x, side.z)
		main.teleport_to({"position": side, "forward": (look - side).normalized()})
		await _settle()
		_hold_player()
		var v2: TrafficVehicle = t.call("_new_vehicle", ti2, lane, s0)
		var entered := ""
		var tt := 0.0
		var shot_at := 0
		while tt < 70.0 and t.vehicles.has(v2):
			await get_tree().process_frame
			tt += get_process_delta_time()
			_hold_player()
			if v2.conn != null:
				entered = v2.conn.to_lane.road.id
				break
			if v2.decision != null and v2.lane.sdist(v2.s, dec.at_s) < 25.0 and v2.speed < 0.3 and shot_at == 0:
				shot_at = 1
				cam.global_position = side + Vector3.UP * 4.0
				cam.look_at(v2.position + Vector3.UP, Vector3.UP)
				cam.current = true
				await _shot("restricted_%s_held" % bits[0])
				log_line("restricted: %s held %.1f m before the %s junction at t=%.1f (leaving %s, in view %s)" % [bits[0], v2.lane.sdist(v2.s, dec.at_s), dec.junction.parent.id, tt, v2.leaving, v2.unseen_t == 0.0])
				break
		var removed := false
		if entered == "" and t.vehicles.has(v2):
			# Look away: it is removed once nobody sees it.
			main.teleport_to({"position": side, "forward": (side - look).normalized()})
			await _wait(3.0)
			removed = not t.vehicles.has(v2)
		var good := entered == "" and shot_at == 1 and removed
		placed_ok = placed_ok and good
		placed_parts.append("%s on %s dir %d: %s" % [bits[0], r.id, dir, ("ENTERED " + entered) if entered != "" else ("held before the junction, removed when unseen %s" % removed)])
		log_line("restricted " + placed_parts[placed_parts.size() - 1])
	# (3) Natural traffic at the Mirror Lake Road junction.
	var wrong := 0
	var seen_types := {}
	var j: LaneGraph.Junction = null
	for jj: LaneGraph.Junction in graph.junctions:
		if jj.child.id == _arg("child", "lake_road") and jj.parent.id == _arg("parent", "expressway"):
			j = jj
	if j != null:
		t.set_density(1.0)
		await _park_beside_junction(j)
		var tt3 := 0.0
		while tt3 < float(_arg("seconds", "90")):
			await _wait(0.5)
			tt3 += 0.5
			_hold_player()
			for v3: TrafficVehicle in t.vehicles:
				seen_types[v3.data.id] = int(seen_types.get(v3.data.id, 0)) + 1
				var r3 := v3.conn.to_lane.road if v3.conn != null else v3.lane.road
				var p3 := v3.position
				if not v3.data.allows(r3.cls, w.data.region_at(p3.x, p3.z)):
					wrong += 1
					if wrong < 10:
						log_line("WRONG ROAD #%d %s on %s cls %d region %d" % [v3.uid, v3.data.id, r3.id, r3.cls, w.data.region_at(p3.x, p3.z)])
		log_line("restricted natural run at %s/%s: vehicle samples by type %s, wrong-road samples %d" % [j.child.id, j.parent.id, JSON.stringify(seen_types), wrong])
	else:
		log_line("restricted: lake_road junction not found")
	report["restricted"] = {"walks": walks, "violations": bad, "placed": placed_parts, "wrong_road_samples": wrong}
	_result("restricted", bad == 0 and walks > 0 and placed_ok and wrong == 0, "%d route walks with %d violations; %s; natural run wrong-road samples %d" % [walks, bad, "; ".join(placed_parts), wrong])


## Why a lane piece is not for this type ("" when it is): road class, or a region along it.
func _piece_violation(data: Resource, pc: Dictionary) -> String:
	if pc.is_empty():
		return "no piece"
	var l: LaneGraph.Lane = pc["lane"]
	if not data.allowed_classes.has(l.road.cls):
		return "class %d" % l.road.cls
	if data.allowed_regions.is_empty():
		return ""
	var s0: float = pc["s0"]
	var span := l.ahead(s0, pc["s1"])
	if l.road.loop and span <= 0.0:
		span = l.road.length
	var w := Game.world as World
	var n := maxi(int(span / 10.0), 1)
	for i in n + 1:
		var p := l.point(l.advance(s0, span * i / n), l.offset)
		var rg := w.data.region_at(p.x, p.z)
		if not data.allowed_regions.has(rg):
			return "region %d at s=%.0f" % [rg, l.advance(s0, span * i / n)]
	return ""


## q23: QA autopilot along the expressway from --start (30) at --speed (105) km/h for --seconds (130), density 1.0,
## noon: every 0.5 s counts vehicles in the chase camera's frustum with terrain line of sight (same metrics as the
## playtest census). Fails when the expressway shows no vehicle within 700 m in more than 20 % of the samples.
func _scenario_census() -> void:
	var w := Game.world as World
	var t: Node = _traffic()
	Game.set_time_of_day(float(_arg("time", "12")))
	Game.set_time_scale(0.0)
	Game.set_weather("clear", true)
	t.set_density(float(_arg("density", "1.0")))
	var road := w.data.network.get_road("expressway")
	var ap := QaAutopilot.new()
	var start := float(_arg("start", "30"))
	ap.setup(w.data.network, road, start)
	ap.target_speed = float(_arg("speed", "105")) / 3.6
	main.teleport_to({"position": ap.lane_point(start), "forward": road.flat_tangent_at(start)})
	await _settle()
	var agg := {}
	var seconds := float(_arg("seconds", "130"))
	var tt := 0.0
	var next_c := 2.0
	var next_shot := 5.0
	while tt < seconds and not ap.finished:
		await get_tree().physics_frame
		ap.drive(Game.player_car)
		await get_tree().process_frame
		tt += get_process_delta_time()
		if tt >= next_c:
			next_c += 0.5
			_census_sample(agg, road, int(tt * 2.0) % 20 == 0, tt, ap.s)
		if tt >= next_shot:
			next_shot += 20.0
			await _shot("census_%03d" % int(tt))
	var n := maxf(float(agg.get("n", 0)), 1.0)
	var line := "samples %d | avg active %.1f target %.1f | frustum<400 %.2f LOS<400 %.2f LOS<700 %.2f | xway<650 %.2f xway LOS<700 %.2f | zero LOS<400 %.0f%% zero xway LOS<700 %.0f%% | xway share of lane length %.2f, of vehicles %.2f | xway same-dir ahead %.2f, oncoming %.2f | recycled %d" % [
		int(n), agg["active"] / n, agg["target"] / n, agg["f400"] / n, agg["l400"] / n, agg["l700"] / n, agg["x650"] / n, agg["xl700"] / n,
		agg["z400"] / n * 100.0, agg["zx700"] / n * 100.0, agg["xlen"] / maxf(agg["alllen"], 1.0), agg["x650"] / maxf(agg["active"], 1.0),
		agg["sa"] / n, agg["op"] / n, int(t.get_stats()["recycled"])]
	log_line("census " + line)
	report["census"] = agg
	_result("census", agg["zx700"] / n < 0.2 and agg["xl700"] / n >= 2.5, line)


func _census_sample(agg: Dictionary, xway: RoadNetwork.Road, log_it: bool, tt: float, s: float) -> void:
	var t: Node = _traffic()
	var gcam := Game.camera_rig.camera as Camera3D
	var cp := gcam.global_position
	var pp := Game.player_car.global_position
	var fwd := -Game.player_car.global_transform.basis.z
	var c := {"f400": 0, "l400": 0, "l700": 0, "x650": 0, "xl700": 0, "sa": 0, "op": 0}
	var xinfo: PackedStringArray = []
	for v: TrafficVehicle in t.vehicles:
		var r: RoadNetwork.Road = v.conn.to_lane.road if v.conn != null else v.lane.road
		var d := v.position.distance_to(cp)
		var inf := gcam.is_position_in_frustum(v.position + Vector3.UP * 1.2)
		var los: bool = inf and not bool(t.call("_occluded", v.position))
		if inf and d < 400.0:
			c["f400"] += 1
		if los and d < 400.0:
			c["l400"] += 1
		if los and d < 700.0:
			c["l700"] += 1
		if r == xway and v.position.distance_to(pp) < 650.0:
			c["x650"] += 1
			if los and d < 700.0:
				c["xl700"] += 1
			var ahead := (v.position - pp).dot(fwd)
			var same := v.heading.dot(fwd) > 0.0
			if same and ahead > 0.0:
				c["sa"] += 1
			if not same:
				c["op"] += 1
			xinfo.append("%s%s%.0fm" % ["S" if same else "O", "+" if ahead > 0.0 else "-", v.position.distance_to(pp)])
	var xlen := 0.0
	var alllen := 0.0
	for r2: RoadNetwork.Road in (Game.world as World).data.network.roads:
		if not r2.traffic:
			continue
		var k := 0
		for q: Vector3 in r2.pos:
			if Vector2(q.x - pp.x, q.z - pp.z).length_squared() < 650.0 * 650.0:
				k += 1
		alllen += k * r2.ds * r2.lanes
		if r2 == xway:
			xlen = k * r2.ds * r2.lanes
	for key: String in c:
		agg[key] = float(agg.get(key, 0.0)) + c[key]
	agg["n"] = float(agg.get("n", 0.0)) + 1.0
	agg["active"] = float(agg.get("active", 0.0)) + t.vehicles.size()
	agg["target"] = float(agg.get("target", 0.0)) + float(t.get_stats()["target"])
	agg["z400"] = float(agg.get("z400", 0.0)) + (1.0 if c["l400"] == 0 else 0.0)
	agg["zx700"] = float(agg.get("zx700", 0.0)) + (1.0 if c["xl700"] == 0 else 0.0)
	agg["xlen"] = float(agg.get("xlen", 0.0)) + xlen
	agg["alllen"] = float(agg.get("alllen", 0.0)) + alllen
	if log_it:
		log_line("census t=%.0f s=%.0f %.0f km/h %s | active %d target %d | LOS<400 %d <700 %d | xway<650 %d LOS<700 %d [%s]" % [tt, s, Game.player_car.get_speed_kmh(),
			(Game.world as World).region_at(pp), t.vehicles.size(), int(t.get_stats()["target"]), c["l400"], c["l700"], c["x650"], c["xl700"], ", ".join(xinfo)])


## Time-reactive group: at noon beside the ring at density 1.0, photo mode is opened with P and its time slider
## set to 22:00 while the tree is paused. Fails when traffic lamps do not follow (kinematic lenses lit, physics
## cars' headlights on) or when any vehicle moves while paused.
func _scenario_photo() -> void:
	var w := Game.world as World
	var t: Node = _traffic()
	Game.set_time_of_day(12.0)
	Game.set_time_scale(0.0)
	Game.set_weather("clear", true)
	var road := w.data.network.get_road("ring")
	var s := float(_arg("s", "900"))
	var side := road.surface_point(s, road.width * 0.5 + road.shoulder + 10.0)
	side.y = w.height_at(side.x, side.z)
	main.teleport_to({"position": side, "forward": road.flat_tangent_at(s)})
	await _settle()
	t.set_density(1.0)
	await _wait(12.0)
	main.car_input.enabled = true
	var pm: Node = null
	for n: Node in Game.hud.find_children("*", "", true, false):
		if n.get_script() != null and String((n.get_script() as Script).resource_path).ends_with("photo_mode.gd"):
			pm = n
	if pm == null:
		_result("photo", false, "photo mode not found")
		return
	_key(KEY_P, true)
	await get_tree().process_frame
	_key(KEY_P, false)
	await _wait(0.5)
	var paused := get_tree().paused
	var pos0 := {}
	var unlit0 := 0
	for v: TrafficVehicle in t.vehicles:
		pos0[v.uid] = v.position if v.car == null else v.car.global_position
		if not _vehicle_lit(v):
			unlit0 += 1
	await _shot("photo_noon")
	pm.call("_on_slider", 22.0, "time")
	var tt := 0.0
	while tt < 1.5:
		await get_tree().process_frame
		tt += get_process_delta_time()
	var lit := 0
	var unlit := 0
	var moved := 0
	var lamps_drawn := 0
	for v2: TrafficVehicle in t.vehicles:
		if not pos0.has(v2.uid):
			continue
		# Traffic's part: kinematic lenses lit, physics cars told to run their lights (their CarVisuals draw them).
		var on := v2.light_state >= 2 if v2.mode == TrafficVehicle.Mode.KINEMATIC else (v2.car != null and v2.car.headlights_on)
		if on:
			lit += 1
		else:
			unlit += 1
		if _vehicle_lit(v2):
			lamps_drawn += 1
		var p: Vector3 = v2.position if v2.car == null else v2.car.global_position
		if p.distance_to(pos0[v2.uid]) > 0.05:
			moved += 1
	var mode_back: bool = t.process_mode != Node.PROCESS_MODE_ALWAYS
	await _shot("photo_night")
	_key(KEY_P, true)
	await get_tree().process_frame
	_key(KEY_P, false)
	await _wait(0.5)
	main.car_input.enabled = false
	report["photo"] = {"paused": paused, "vehicles": pos0.size(), "unlit_before": unlit0, "lit_after": lit, "unlit_after": unlit, "lamps_drawn": lamps_drawn, "moved": moved}
	_result("photo", paused and pos0.size() > 0 and unlit == 0 and moved == 0 and mode_back, "paused %s, %d vehicles: unlit at noon %d, lit after the 22:00 switch %d (unlit %d; lamps drawn incl. physics CarVisuals %d), moved while paused %d, traffic process mode restored %s" % [
		paused, pos0.size(), unlit0, lit, unlit, lamps_drawn, moved, mode_back])


func _key(physical: int, pressed: bool) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = physical as Key
	e.keycode = physical as Key
	e.pressed = pressed
	Input.parse_input_event(e)


func _find_junction(child_id: String, end: int) -> LaneGraph.Junction:
	var graph: LaneGraph = _traffic().graph
	for jj: LaneGraph.Junction in graph.junctions:
		if jj.child.id == child_id and jj.child_end == end:
			return jj
	return null


## Player parked 16 m off the major road, 60 m before the junction (blocks nobody).
func _park_beside_junction(j: LaneGraph.Junction) -> void:
	var w := Game.world as World
	var road := j.parent
	var s := j.parent_s - 60.0
	var side := road.surface_point(s, road.width * 0.5 + road.shoulder + 16.0)
	side.y = w.height_at(side.x, side.z)
	main.teleport_to({"position": side, "forward": road.flat_tangent_at(s)})
	await _settle()
	_hold_player()


func _solid(space: PhysicsDirectSpaceState3D, v: TrafficVehicle) -> bool:
	if v.body == null or not v.body.is_inside_tree():
		return false
	var q := PhysicsPointQueryParameters3D.new()
	q.position = v.body.global_position
	q.collision_mask = 4
	for hit: Dictionary in space.intersect_point(q, 8):
		if hit["collider"] == v.body:
			return true
	return false


func _settle() -> void:
	var w := Game.world as World
	var t0 := Time.get_ticks_msec()
	await get_tree().process_frame
	while not w.is_ready_near() and Time.get_ticks_msec() - t0 < 20000:
		await get_tree().process_frame
	await _wait(1.0)


func _hold_player() -> void:
	var pc := Game.player_car
	pc.in_throttle = 0.0
	pc.in_brake = 0.25
	pc.in_handbrake = 1.0
	pc.in_steer = 0.0



func _where(v: TrafficVehicle) -> String:
	if v.conn != null:
		return "conn %d (%s, turn %d) c=%.1f/%.1f" % [v.conn.id, v.conn.junction.child.id, v.conn.turn, v.c, v.conn.length]
	return "%s dir %d k%d s=%.0f" % [v.lane.road.id, v.lane.dir, v.lane.k, v.s]


func _result(what: String, ok: bool, detail: String) -> void:
	report["result"] = {"scenario": what, "pass": ok, "detail": detail}
	log_line("RESULT %s %s: %s" % [what, "PASS" if ok else "FAIL", detail])


# ----------------------------------------------------------------- helpers

func _park_player(road: RoadNetwork.Road, s: float) -> void:
	main.teleport_to({"position": road.surface_point(s, road.lane_offset(1)), "forward": road.flat_tangent_at(s)})
	Game.player_car.in_throttle = 0.0
	Game.player_car.in_brake = 0.25
	Game.player_car.in_handbrake = 1.0


func _queued_behind_player() -> TrafficVehicle:
	for v: TrafficVehicle in _traffic().vehicles:
		if v.lead_is_player and v.lead_gap < 20.0:
			return v
	return null


## Camera `dist` from target at height h, in the first direction with terrain line of sight.
func _aim_cam(target: Vector3, dist: float, h: float) -> void:
	var w := Game.world as World
	var best := target + Vector3(dist, h, 0.0)
	for i in 8:
		var a := TAU * i / 8.0
		var p := target + Vector3(cos(a) * dist, h, sin(a) * dist)
		p.y = maxf(p.y, w.height_at(p.x, p.z) + 1.8)
		var ok := true
		for k in range(1, 8):
			var q := p.lerp(target + Vector3.UP, k / 8.0)
			if w.height_at(q.x, q.z) > q.y - 0.2:
				ok = false
				break
		if ok:
			best = p
			break
	cam.global_position = best
	cam.look_at(target + Vector3.UP * 0.6, Vector3.UP)
	cam.current = true


func _look_at_overhead(center: Vector3, h: float) -> void:
	cam.global_position = center + Vector3(0.0, h, h * 0.75)
	cam.look_at(center, Vector3.UP)
	cam.current = true


## Places the test camera beside a physics (near=true) or kinematic vehicle. Returns false if none.
func _traffic_cam(near: bool) -> bool:
	var pp := Game.player_car.global_position
	var best: TrafficVehicle = null
	var bd := INF
	for v: TrafficVehicle in _traffic().vehicles:
		var is_phys := v.mode == TrafficVehicle.Mode.PHYSICS
		if is_phys != near:
			continue
		var d := v.position.distance_to(pp)
		if d < bd:
			bd = d
			best = v
	if best == null:
		return false
	var side := best.heading.cross(Vector3.UP).normalized()
	var dist := 7.0 if near else 11.0
	var cp := best.position + side * dist * 0.8 - best.heading * dist * 0.6 + Vector3.UP * 2.2
	cp.y = maxf(cp.y, (Game.world as World).height_at(cp.x, cp.z) + 1.6)
	cam.global_position = cp
	cam.look_at(best.position + Vector3.UP * 0.8, Vector3.UP)
	cam.current = true
	log_line("cam on %s #%d %s %.0f km/h at %.0f m from player" % [best.data.id, best.uid, "PHYS" if near else "kin", best.speed * 3.6, bd])
	return true


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := out_dir.path_join(name + ".png")
	img.save_png(path)
	_shots += 1
	log_line("shot " + ProjectSettings.globalize_path(path))
	if cam.current:
		cam.current = false
		Game.camera_rig.camera.current = true


func _sample() -> void:
	var t: Node = _traffic()
	chk["samples"] += 1
	var vs: Array = t.vehicles
	var n_phys := 0
	for v: TrafficVehicle in vs:
		chk["vehicle_samples"] += 1
		var phys := v.mode == TrafficVehicle.Mode.PHYSICS
		if phys:
			n_phys += 1
		if v.hazard:
			continue
		if v.speed > v.v_desired + 2.5:
			chk["overspeed"] += 1
		if v.lead_gap < -0.5 and not v.lead_is_player:
			chk["overlaps"] += 1
			if _detail_logs < 25:
				_detail_logs += 1
				log_line("overlap #%d %s %s gap %.1f lead_v %.1f spd %.1f %s" % [v.uid, v.data.id, "PHYS" if phys else "kin", v.lead_gap,
					v.lead_speed, v.speed, ("conn %d c=%.1f" % [v.conn.id, v.c]) if v.conn != null else ("%s dir %d s=%.0f" % [v.lane.road.id, v.lane.dir, v.s])])
		if v.lead_gap < INF and v.speed > 5.0 and not v.lead_is_player and v.lead_gap / v.speed < 1.0 and v.lead_speed < v.speed:
			chk["time_gap_lt_1s"] += 1
		if v.conn != null:
			if v.conn.yield_mode == LaneGraph.Yield.MINOR and v.c > 2.0:
				_check_conflict(t, v)
			continue
		var r := v.lane.road
		var s := v.project_lane(v.position, v.s)
		var c := r.point_at(s)
		var lat := (v.position - c).dot(r.right_at(s))
		var want := v.off * v.lane.dir
		var err := absf(lat - want)
		if lat * v.lane.dir < 0.0 and absf(lat) > 0.5:
			chk["wrong_side"] += 1
		if (err > 1.5 or (lat * v.lane.dir < 0.0 and absf(lat) > 0.5)) and _detail_logs < 25:
			_detail_logs += 1
			log_line("lane error #%d %s %s %s dir %d k%d s=%.0f lat %.2f want %.2f spd %.0f km/h y %.2f road_y %.2f%s" % [v.uid, v.data.id,
				"PHYS" if phys else "kin", r.id, v.lane.dir, v.lane.k, s, lat, want, v.speed * 3.6, v.position.y,
				r.surface_point(s, lat).y, " lanechg" if v.prev_lane != null else ""])
		var key := "lane_err_max_phys" if phys else "lane_err_max_kin"
		chk[key] = maxf(chk[key], snappedf(err, 0.01))
		if phys:
			var sy := r.surface_point(s, lat).y
			var dy := absf(v.position.y - sy)
			chk["height_err_max_phys"] = maxf(chk["height_err_max_phys"], snappedf(dy, 0.01))
			if dy > 0.6:
				chk["height_bad_phys"] += 1
				if _detail_logs < 25:
					_detail_logs += 1
					log_line("height error #%d %s %s s=%.0f dy %.2f up %.2f wheels %d" % [v.uid, v.data.id, r.id, s, v.position.y - sy,
						v.car.global_transform.basis.y.y, v.car.wheels_on_ground])
	chk["max_active"] = maxi(chk["max_active"], vs.size())
	chk["max_physics"] = maxi(chk["max_physics"], n_phys)
	var nodes := Performance.get_monitor(Performance.OBJECT_NODE_COUNT)
	chk["nodes_min"] = minf(chk["nodes_min"], nodes)
	chk["nodes_max"] = maxf(chk["nodes_max"], nodes)
	if chk["samples"] > 6:
		chk["fps_min"] = minf(chk["fps_min"], Engine.get_frames_per_second())
	if chk["samples"] % 10 == 0:
		var st: Dictionary = t.get_stats()
		log_line("t=%d active %d (phys %d) target %d avg %.0f km/h waiting %d turns %d yields %d lanechg %d hazards %d honks %d nodes %d fps %d upd %.2f ms proc %.1f ms phys %.1f ms colliders %d" % [
			chk["samples"] / 2, st["active"], st["physics"], st["target"], st["avg_kmh"], st["waiting"], st["give_way_entries"],
			st["yield_waits"], st["lane_changes"], st["hazards"], st["honks"], nodes, Engine.get_frames_per_second(), st["update_ms"],
			Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
			(Game.world as World).terrain.stats["colliders"]])


## A vehicle crossing out of a minor road while a major-road vehicle approaches inside the junction box.
func _check_conflict(t: Node, v: TrafficVehicle) -> void:
	var j := v.conn.junction
	for w: TrafficVehicle in t.vehicles:
		if w == v or w.conn != null or w.hazard or w.lane.road != j.parent:
			continue
		var d := w.lane.sdist(w.s, j.parent_s)
		var crossing: bool = v.conn.crosses.has(w.lane)
		var closing: bool = w.lane == v.conn.to_lane and w.speed > v.speed + 6.0
		if d > 0.0 and d < j.radius and w.speed > 3.0 and (crossing or closing):
			chk["junction_conflicts"] += 1
			log_line("junction conflict at %s: #%d turning (turn %d, to dir %d, c %.1f/%.1f, %.1f m/s, crosses %d lanes), #%d dir %d k%d %.1f m before centre at %.1f m/s %s lead %.1f m tgt %.1f age %.1f s" % [
				j.child.id, v.uid, v.conn.turn, v.conn.to_lane.dir, v.c, v.conn.length, v.speed, v.conn.crosses.size(), w.uid, w.lane.dir, w.lane.k, d, w.speed,
				"PHYS" if w.mode == TrafficVehicle.Mode.PHYSICS else "kin", w.lead_gap, w.v_target, (Time.get_ticks_msec() - w.promoted_ms) / 1000.0])


## Playtest-3 s22: at 22:30 an oncoming car's headlight pool on the road must not switch on in one frame when the
## car changes from the far model (no lights) to the physics car (real lights) at PHYSICS_IN. The player is held on
## the expressway shoulder at --s=900, the test camera 2.4 m above it looks down the road (FOV 30). Every drawn
## frame measures the road brightness 8-32 m in front of each approaching car; the jump across the swap frame must
## stay small against the full pool brightness the car shows at ~80 m.
func _scenario_nightswap() -> void:
	var w := Game.world as World
	var t: Node = _traffic()
	t.set_density(float(_arg("density", "1.0")))
	Game.set_weather("clear", true)
	Game.set_time_of_day(22.5)
	Game.set_time_scale(0.0)
	var road := w.data.network.get_road(_arg("road", "expressway"))
	var s := float(_arg("s", "900"))
	var p := road.surface_point(s, road.width * 0.5 + road.shoulder + 1.5)
	p.y = maxf(p.y, w.height_at(p.x, p.z))
	main.teleport_to({"position": p, "forward": road.flat_tangent_at(s)})
	await _settle()
	_hold_player()
	var fwd := road.flat_tangent_at(s)
	cam.fov = 30.0
	var tracks: Dictionary = {}
	var done: Array = []
	var tt := 0.0
	var shots_taken := 0
	var frame := 0
	var prev_img: Image = null
	var after_at: Dictionary = {}
	while tt < float(_arg("seconds", "100")) and done.size() < int(_arg("cars", "4")):
		await RenderingServer.frame_post_draw
		_hold_player()
		cam.global_position = Game.player_car.global_position + Vector3.UP * 2.4
		cam.look_at(cam.global_position + fwd * 100.0 - Vector3.UP * 2.0, Vector3.UP)
		cam.current = true
		tt += get_process_delta_time()
		var img := get_viewport().get_texture().get_image()
		var scale := Vector2(img.get_size()) / get_viewport().get_visible_rect().size
		for v: TrafficVehicle in t.vehicles:
			var d := v.position.distance_to(cam.global_position)
			# Oncoming (driving toward the camera), in front of it.
			if v.heading.dot(fwd) > -0.8 or (v.position - cam.global_position).dot(fwd) < 0.0 or d > 230.0 or d < 50.0:
				continue
			var b := _pool_brightness(img, scale, v)
			if b < 0.0:
				continue
			if not tracks.has(v.uid):
				tracks[v.uid] = []
			var tr0: Array = tracks[v.uid]
			if not tr0.is_empty() and int(tr0[tr0.size() - 1][1]) == TrafficVehicle.Mode.KINEMATIC and v.mode == TrafficVehicle.Mode.PHYSICS 					and after_at.size() < 2 and prev_img != null:
				# The last far-model frame and the frame 6 frames after the swap, for a side-by-side look.
				prev_img.save_png(out_dir.path_join("nightswap_%d_a_before_%.0fm.png" % [v.uid, d]))
				after_at[v.uid] = frame + 6
			if int(after_at.get(v.uid, -1)) == frame:
				img.save_png(out_dir.path_join("nightswap_%d_b_after6f_%.0fm.png" % [v.uid, d]))
			tr0.append([d, v.mode, b])
		prev_img = img
		frame += 1
		# Finished approaches (passed below 60 m with a swap seen).
		for uid: int in tracks.keys():
			var tr: Array = tracks[uid]
			if done.has(uid) or tr.size() < 10 or float(tr[tr.size() - 1][0]) > 70.0:
				continue
			var swap := -1
			for i in range(1, tr.size()):
				if int(tr[i - 1][1]) == TrafficVehicle.Mode.KINEMATIC and int(tr[i][1]) == TrafficVehicle.Mode.PHYSICS:
					swap = i
					break
			if swap < 2 or swap + 3 >= tr.size():
				continue
			done.append(uid)
			var before := float(tr[swap - 1][2])
			var after := 0.0
			for k in range(swap, mini(swap + 3, tr.size())):
				after = maxf(after, float(tr[k][2]))
			var full := 0.0
			var at := 0.0
			for e: Array in tr:
				if float(e[0]) < 90.0 and float(e[2]) > full:
					full = float(e[2])
					at = float(e[0])
			var path := PackedStringArray()
			for e2: Array in tr:
				if int(roundf(float(e2[0]))) % 10 == 0:
					path.append("%.0fm %s %.3f" % [float(e2[0]), "P" if int(e2[1]) == 1 else "k", float(e2[2])])
			var jump := (after - before) / maxf(full - before, 0.02)
			log_line("nightswap #%d: swap at %.0f m, road brightness %.3f before -> %.3f in the next 3 frames, full pool %.3f at %.0f m: jump %.0f %% of the pool | %s" % [uid,
				float(tr[swap][0]), before, after, full, at, jump * 100.0, " ".join(path)])
			report["nightswap_%d" % uid] = {"swap_m": tr[swap][0], "before": before, "after": after, "full": full, "jump": jump}
			if shots_taken < 1:
				shots_taken += 1
				await _shot("nightswap_after_%d" % uid)
	var worst := 0.0
	var n := 0
	for key: String in report.keys():
		if key.begins_with("nightswap_"):
			n += 1
			worst = maxf(worst, float((report[key] as Dictionary)["jump"]))
	cam.fov = 60.0
	Game.set_time_scale(1.0)
	_result("nightswap", n > 0 and worst < 0.25, "%d approaching cars swapped to physics in view, worst one-frame pool jump %.0f %% of the full pool" % [n, worst * 100.0])


## Mean brightness of the road 8-32 m in front of v (screen samples, 5x5 px each); -1 when off screen.
func _pool_brightness(img: Image, scale: Vector2, v: TrafficVehicle) -> float:
	var sum := 0.0
	var cnt := 0
	var f := Vector3(v.heading.x, 0.0, v.heading.z).normalized()
	for d: float in [8.0, 14.0, 20.0, 26.0, 32.0]:
		var q := v.position + f * d
		q.y = (Game.world as World).height_at(q.x, q.z)
		var hit := get_viewport().get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(q + Vector3.UP * 4.0, q - Vector3.UP * 4.0, 1))
		if not hit.is_empty():
			q = hit["position"]
		if cam.is_position_behind(q):
			continue
		var px := Vector2i(cam.unproject_position(q) * scale)
		if px.x < 3 or px.y < 3 or px.x >= img.get_width() - 3 or px.y >= img.get_height() - 3:
			continue
		for oy in range(-2, 3):
			for ox in range(-2, 3):
				sum += img.get_pixel(px.x + ox, px.y + oy).get_luminance()
				cnt += 1
	return sum / cnt if cnt > 0 else -1.0
