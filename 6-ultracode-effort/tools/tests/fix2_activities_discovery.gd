extends Node
## Activities regression test (fix2): event discovery (map markers only after discovery; Gale Ridge Run discovered
## before it is started from its far end), the Gale Ridge start arch clear of the Sunward Ring, the Dustwater flag
## clear of the adobe houses (and collectable from the road).
##   Godot_console.exe --path . --resolution 1600x900 res://tools/tests/fix2_activities_discovery.tscn -- --cases=map,gale,arch,flag --out=res://qa_output/<dir>

const MAIN := preload("res://scenes/main.tscn")

var out_dir := "res://qa_output/fix2_activities"
var results: Dictionary = {}
var last_hud := ""
var _t := 0.0


func _ready() -> void:
	SaveGame.enabled = false
	SaveGame.pending = {}
	Game.personal_bests = {}
	Game.discovered = {}
	out_dir = _arg("out", out_dir)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	Game.activity_finished.connect(func(id: String, r: Dictionary) -> void:
		results[id] = r
		print("[dt] RESULT %s %s" % [id, JSON.stringify(r)]))
	Game.activity_update.connect(func(i: Dictionary) -> void: last_hud = "%s | %s" % [i.get("primary", ""), i.get("secondary", "")])
	Game.notification.connect(func(t: String, b: String, k: StringName) -> void:
		print("[dt] %.2f NOTIFY [%s] %s | %s  (hud: %s, session '%s')" % [_t, k, t, b, last_hud, Game.activities.get_session_id() if Game.activities != null else ""]))
	add_child(MAIN.instantiate())
	_run.call_deferred()


func _physics_process(dt: float) -> void:
	_t += dt


static func _arg(key: String, default: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--" + key + "="):
			return a.substr(key.length() + 3)
	return default


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
	print("[dt] shot ", ProjectSettings.globalize_path(path))


func _view(n: String, from: Vector3, at: Vector3) -> void:
	var cam := Camera3D.new()
	add_child(cam)
	cam.global_position = from
	cam.look_at(at, Vector3.UP if absf((at - from).normalized().y) < 0.98 else Vector3.FORWARD)
	cam.fov = 60.0
	cam.make_current()
	await _wait(0.6)
	await _shot(n)
	(Game.camera_rig.get("camera") as Camera3D).make_current()
	cam.queue_free()


func _run() -> void:
	while Game.main == null or Game.main.is_loading:
		await get_tree().process_frame
	Game.main.car_input.process_mode = Node.PROCESS_MODE_DISABLED
	var dens0: float = Game.traffic.get_density() if Game.traffic != null else 0.0
	if Game.traffic != null:
		Game.traffic.set_density(0.0)
	Game.set_time_of_day(12.0)
	Game.set_weather("clear", true)
	var cases := _arg("cases", "map,gale,arch,flag").split(",")
	if cases.has("map"):
		await _map("map_after_load")
	if cases.has("gale"):
		await _gale()
		if cases.has("map"):
			await _map("map_after_gale")
	if cases.has("arch"):
		await _arch()
	if cases.has("flag"):
		await _flag()
	if Game.traffic != null:
		Game.traffic.set_density(dens0)
	print("[dt] DONE")
	get_tree().quit(0)


func _map(n: String) -> void:
	var mgr: Node = Game.activities
	var markers: Array = mgr.get_map_markers()
	var all: Array = mgr.get_map_markers(true)
	var names := PackedStringArray()
	for m: Dictionary in markers:
		names.append(m["id"])
	print("[dt] MAP %s: discovered %s, markers %d of %d %s" % [n, str((Game.discovered.get("events", {}) as Dictionary).keys()), markers.size(), all.size(), str(names)])
	Game.hud.call("open_map")
	await _wait(1.2)
	var wm: Node = Game.hud.get("world_map")
	var act := 0
	if wm != null:
		for sp: Variant in wm.get("_sprites"):
			var data: Dictionary = (sp as Object).get("data")
			if not bool(data.get("travel", false)):
				act += 1
	print("[dt] MAP %s: world map activity sprites %d" % [n, act])
	await _shot(n)
	Game.hud.call("close_map")
	await _wait(0.8)


## Gale Ridge Run from its far end (desert_north s=1215 heading -s).
func _gale() -> void:
	var mgr: Node = Game.activities
	var road := (Game.world as World).data.network.get_road("desert_north")
	var s0 := 1215.0
	var fwd := -road.flat_tangent_at(s0)
	Game.main.teleport_to({"position": road.surface_point(s0, 0.0), "forward": fwd})
	await _wait_streamed()
	var car := Game.player_car
	car.freeze = false
	await get_tree().physics_frame
	car.linear_velocity = fwd * 25.0
	var f := RoadFollower.new()
	f.setup(road, s0, -1, 0.0)
	f.target_speed = 105.0 / 3.6
	f.lat_accel = 4.0
	var t := 0.0
	var started := -1.0
	var disc := -1.0
	var started_s := 0.0
	var disc_s := 0.0
	while t < 60.0 and not results.has("sz_gale_ridge"):
		await get_tree().physics_frame
		var dt := get_physics_process_delta_time()
		t += dt
		f.drive(Game.player_car, dt)
		if started < 0.0 and mgr.get_session_id() == "sz_gale_ridge":
			started = t
			started_s = f.s
		if disc < 0.0 and mgr.is_discovered("sz_gale_ridge"):
			disc = t
			disc_s = f.s
			await _shot("gale_discovered")
	print("[dt] GALE discovered at t=%.2f s=%.0f, zone started at t=%.2f s=%.0f, result %s" % [disc, disc_s, started, started_s,
		JSON.stringify(results.get("sz_gale_ridge", {}))])
	mgr.cancel_session("test")


## Gale Ridge Run start arch: leg distances to the Sunward Ring.
func _arch() -> void:
	var mgr: Node = Game.activities
	var act: RefCounted = mgr.by_id["sz_gale_ridge"]
	mgr.teleport_to_activity("sz_gale_ridge", 200.0)
	await _wait_streamed()
	Game.player_car.freeze = true
	var gate: Node3D = (act.get("gates") as Array)[0]
	var hw: float = act.get("half_width")
	var net := (Game.world as World).data.network
	var ring := net.get_road("ring")
	for side: float in [-1.0, 1.0]:
		var leg := gate.global_transform * Vector3(side * hw, 0.0, 0.0)
		var res := net.nearest(leg, 80.0, func(r: RoadNetwork.Road) -> bool: return r == ring)
		var d := absf(float(res.get("lateral", INF)))
		print("[dt] ARCH leg %s at %s: %.2f m from the ring centre line (ring paved edge %.2f, shoulder edge %.2f), sandbag edge %.2f m beyond the shoulder" % [
			"L" if side < 0.0 else "R", str(leg.round()), d, ring.width * 0.5, ring.width * 0.5 + ring.shoulder, d - 0.8 - (ring.width * 0.5 + ring.shoulder)])
	var g := gate.global_position
	await _view("arch_gale_overhead", g + Vector3(0.0, 55.0, 0.5), g)
	var p := ring.point_at(10704.0)
	await _view("arch_gale_from_ring", p + ring.flat_tangent_at(10704.0) * 30.0 + Vector3.UP * 2.0, g + Vector3.UP * 3.0)
	Game.player_car.freeze = false


## The Dustwater flag: clear of buildings, collectable from the road.
func _flag() -> void:
	var mgr: Node = Game.activities
	var fl: Dictionary = {}
	for x: Dictionary in mgr.get_collectibles():
		if x["id"] == "flag_dustwater":
			fl = x
	var target: Vector3 = fl["position"]
	var w := Game.world as World
	var rp: Dictionary = w.nearest_road_point(target)
	Game.main.teleport_to({"position": rp["position"], "forward": rp["forward"]})
	await _wait_streamed()
	await _wait(1.0)
	var space := Game.player_car.get_world_3d().direct_space_state
	var q := PhysicsPointQueryParameters3D.new()
	q.collision_mask = 1
	var solid := PackedStringArray()
	for h: float in [0.5, 1.5, 3.0, 4.5]:
		q.position = target + Vector3.UP * h
		for r: Dictionary in space.intersect_point(q, 4):
			solid.append("%.1f:%s" % [h, (r["collider"] as Node).name])
	var near := ""
	var st: Node = Game.main.get_node_or_null(^"Settlements")
	var best := INF
	for it: Dictionary in st.get("items"):
		var o: Vector3 = (it["xf"] as Transform3D).origin
		var dd := Vector2(o.x - target.x, o.z - target.z).length()
		if dd < best and int(it.get("col", 0)) != 0:
			best = dd
			near = "%s %.1f m" % [it["name"], dd]
	print("[dt] FLAG flag_dustwater at %s, road %.1f m away, solid colliders at the pole: %s, nearest collidable prop origin: %s, ground_at %.2f vs terrain %.2f" % [
		str(target.snappedf(0.01)), Vector2(target.x - (rp["position"] as Vector3).x, target.z - (rp["position"] as Vector3).z).length(), str(solid), near,
		w.ground_at(target.x, target.z), w.data.height_at(target.x, target.z)])
	var away := (rp["position"] as Vector3) - target
	away.y = 0.0
	await _view("flag_dustwater_street", target + away.normalized() * 16.0 + Vector3.UP * 2.5, target + Vector3.UP * 2.5)
	await _view("flag_dustwater_above", target + Vector3(-12.0, 18.0, -6.0), target)
	# Drive into it from the road (start on the road point itself: off-road spots can be occupied by buildings).
	var start: Vector3 = rp["position"]
	Game.main.teleport_to({"position": start, "forward": -away.normalized()})
	await _wait_streamed()
	var car := Game.player_car
	car.freeze = false
	var t := 0.0
	while t < 20.0 and not results.has("flag_dustwater"):
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		car = Game.player_car
		var rel := target - car.global_position
		rel.y = 0.0
		var cf := -car.global_transform.basis.z
		cf.y = 0.0
		car.in_steer = clampf(-cf.normalized().signed_angle_to(rel.normalized(), Vector3.UP) * 2.0, -1.0, 1.0)
		car.in_throttle = 0.5 if car.get_speed_kmh() < 30.0 else 0.0
		car.in_brake = 0.0
	print("[dt] FLAG collected %s after %.1f s" % [results.has("flag_dustwater"), t])
