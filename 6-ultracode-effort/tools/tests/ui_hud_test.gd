extends Node
## UI / HUD test harness: runs the real main scene, drives the player car with RoadFollower, then plays
## scripted HUD scenarios (GPS route, notifications, activity panel + result banner + speed-trap flash,
## telemetry, region popup, world map, HUD toggle) and saves screenshots.
##   Godot_console.exe --path . --resolution 1920x1080 res://tools/tests/ui_hud_test.tscn -- --out=res://qa_output/ui_hud --tag=1080

var out_dir: String = "res://qa_output/ui_hud"
var tag: String = ""
var main: Node
var follower: RoadFollower
var worst: float = 0.0


func _ready() -> void:
	out_dir = _arg("out", out_dir)
	tag = _arg("tag", "")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	SaveGame.enabled = false
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(main)
	_run.call_deferred()


func _process(delta: float) -> void:
	worst = maxf(worst, delta)


func _window(label: String) -> void:
	_log("frame window %s: worst %.1f ms" % [label, worst * 1000.0])
	worst = 0.0


func _reset() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	worst = 0.0


## Average process time / frame time while driving, with the UI on or off (process disabled + hidden).
func _bench(on: bool, seconds: float) -> Vector2:
	var ui: Node = Game.hud
	ui.process_mode = Node.PROCESS_MODE_ALWAYS if on else Node.PROCESS_MODE_DISABLED
	(ui.get("hud_root") as Control).visible = on
	(ui.get("route_line") as Node3D).visible = on
	await _reset()
	var t := 0.0
	var n := 0
	var proc := 0.0
	var frame := 0.0
	while t < seconds:
		await get_tree().process_frame
		var d := get_process_delta_time()
		t += d
		frame += d
		proc += Performance.get_monitor(Performance.TIME_PROCESS)
		n += 1
	ui.process_mode = Node.PROCESS_MODE_ALWAYS
	return Vector2(proc / maxf(n, 1) * 1000.0, frame / maxf(n, 1) * 1000.0)




func gps_node() -> Node:
	return Game.hud.get("gps")


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _press(action: String) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	Input.parse_input_event(ev)
	var up := InputEventAction.new()
	up.action = action
	up.pressed = false
	Input.parse_input_event(up)


static func _arg(key: String, default: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--" + key + "="):
			return a.substr(key.length() + 3)
	return default


func _log(s: String) -> void:
	print("[ui_test] ", s)


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds, true, false, true).timeout


func _shot(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := out_dir.path_join("%s%s.png" % [shot_name, ("_" + tag) if tag != "" else ""])
	img.save_png(path)
	_log("shot %s %dx%d fps %.1f" % [ProjectSettings.globalize_path(path), img.get_width(), img.get_height(), Engine.get_frames_per_second()])


func _physics_process(delta: float) -> void:
	var car := Game.player_car
	if car != null and follower != null:
		follower.drive(car, delta)


func _drive(seconds: float) -> void:
	var t := 0.0
	while t < seconds:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()


## Routes from the current position to every POI: logs length, compute time and the largest gap
## between consecutive route points (a broken path would show a large gap).
func _gps_check(gps: Node) -> void:
	var worst_gap := 0.0
	var worst_ms := 0.0
	var fails := 0
	for t: Dictionary in Game.get_teleport_targets():
		if String(t["kind"]) == "region":
			continue
		Game.set_waypoint(t["position"])
		var pts: PackedVector3Array = gps.get("points")
		var gap := 0.0
		for i in range(1, pts.size()):
			gap = maxf(gap, Vector2(pts[i].x - pts[i - 1].x, pts[i].z - pts[i - 1].z).length())
		var ms: float = gps.get("last_compute_ms")
		worst_gap = maxf(worst_gap, gap)
		worst_ms = maxf(worst_ms, ms)
		if not bool(gps.get("active")):
			fails += 1
		_log("gps -> %-28s active=%s pts=%5d len=%7.0f m gap=%5.1f m %.1f ms" % [t["name"], gps.get("active"), pts.size(), float(gps.get("length_m")), gap, ms])
	Game.clear_waypoint()
	_log("gps check: fails=%d worst gap %.1f m worst compute %.1f ms" % [fails, worst_gap, worst_ms])


func _poi(poi_name: String) -> Vector3:
	for t: Dictionary in Game.get_teleport_targets():
		if String(t["name"]) == poi_name:
			return t["position"]
	return Vector3.INF


func _run() -> void:
	var t := 0.0
	while bool(main.get("is_loading")) and t < 60.0:
		await get_tree().process_frame
		t += get_process_delta_time()
	_log("loaded in %.1f s" % t)
	var ui: Node = Game.hud
	if ui == null:
		_log("FAIL no Game.hud")
		get_tree().quit(1)
		return
	var w := Game.world as World
	var road := w.data.network.get_road("ring")
	main.get("car_input").set("enabled", false)
	follower = RoadFollower.new()
	follower.setup(road, 60.0, 1, road.lane_offset(1))
	follower.target_speed = 105.0 / 3.6
	main.call("teleport_to", {"position": follower.lane_point(60.0), "forward": road.flat_tangent_at(60.0)})
	await _wait(1.4)
	await _shot("hud_start")
	if _arg("gps-check", "") != "":
		_gps_check(ui.get("gps"))
	# Arrival: waypoint 160 m ahead on the ring.
	Game.set_waypoint(road.point_at(follower.s + 160.0))
	var arrived := false
	var tt := 0.0
	while tt < 14.0 and not arrived:
		await _drive(0.25)
		tt += 0.25
		arrived = Game.waypoint == Vector3.INF
	_log("arrival test: arrived=%s after %.1f s, gps active=%s" % [arrived, tt, gps_node().get("active")])
	# Input actions: HUD / telemetry / map toggles.
	var root: CanvasItem = ui.get("hud_root")
	_press("toggle_hud")
	await _frames(3)
	var hidden_ok := not root.visible
	_log("after toggle_hud: ui.hud_visible=%s setting=%s root=%s" % [ui.get("hud_visible"), Settings.get_value("hud_visible"), root.visible])
	_press("toggle_hud")
	await _frames(3)
	_log("toggle_hud: hides=%s restores=%s" % [hidden_ok, root.visible])
	_press("toggle_telemetry")
	await _frames(3)
	var tel: CanvasItem = ui.get("telemetry")
	var tel_on := tel.visible
	_press("toggle_telemetry")
	await _frames(3)
	_log("toggle_telemetry: shows=%s hides=%s" % [tel_on, not tel.visible])
	_press("toggle_map")
	await _frames(3)
	var wm0: Node = ui.get("world_map")
	var map_on := bool(wm0.get("is_open")) and Game.is_overlay_open() and not root.visible
	_press("toggle_map")
	await _frames(3)
	_log("toggle_map: opens=%s closes=%s overlay=%s hud=%s" % [map_on, not bool(wm0.get("is_open")), Game.is_overlay_open(), root.visible])
	Game.photo_mode = true
	await get_tree().process_frame
	var photo_hidden := not root.visible
	Game.photo_mode = false
	await get_tree().process_frame
	_log("photo mode: hud hidden=%s restored=%s" % [photo_hidden, root.visible])
	# GPS route to Millbrook.
	var dest := _poi("Millbrook")
	Game.set_waypoint(dest)
	var gps: Node = ui.get("gps")
	_log("gps active=%s points=%d length=%.0f m compute=%.1f ms" % [gps.get("active"), (gps.get("points") as PackedVector3Array).size(), gps.get("length_m"), gps.get("last_compute_ms")])
	await _drive(7.0)
	Game.notify("Speed trap discovered", "Gale Ridge Speed Trap added to your map", &"discovery")
	await _drive(0.4)
	Game.notify("Festival flag", "3 of 20 found near Mirror Lake", &"collectible")
	await _drive(0.8)
	await _shot("hud_drive")
	if _arg("bench", "") != "":
		var vp := get_viewport().get_viewport_rid()
		RenderingServer.viewport_set_measure_render_time(vp, true)
		var on_l: Array[float] = []
		var off_l: Array[float] = []
		for k in 3:
			var r1: Vector2 = await _bench(true, 1.5)
			var c1 := RenderingServer.viewport_get_measured_render_time_cpu(vp)
			var r2: Vector2 = await _bench(false, 1.5)
			var c2 := RenderingServer.viewport_get_measured_render_time_cpu(vp)
			on_l.append(r1.y)
			off_l.append(r2.y)
			_log("bench pair %d: on %.2f ms (render cpu %.2f) | off %.2f ms (render cpu %.2f)" % [k, r1.y, c1, r2.y, c2])
		on_l.sort()
		off_l.sort()
		(ui.get("hud_root") as Control).visible = true
		_log("bench median frame: UI on %.2f ms | UI off %.2f ms" % [on_l[1], off_l[1]])
		load("res://tools/tests/ui_hud_prof.gd").reset()
		await _drive(3.0)
		_log("PROF 3s:
" + load("res://tools/tests/ui_hud_prof.gd").report())
	var cam_mode: int = Game.camera_rig.get("mode")
	Game.camera_rig.set("mode", 2)
	await _drive(1.0)
	await _shot("hud_hood")
	Game.camera_rig.set("mode", cam_mode)
	await _drive(0.6)
	await _reset()
	# Activity panel.
	for i in 90:
		Game.activity_update.emit({"id": "trap_test", "title": "Ring Road Speed Trap", "kind": &"speed_trap",
			"primary": "%d km/h" % int(Game.player_car.get_speed_kmh()), "secondary": "Target 150 km/h", "progress": i / 90.0})
		await _drive(1.0 / 60.0)
	_window("activity panel")
	await _shot("hud_activity")
	await _reset()
	Game.activity_finished.emit("trap_test", {"title": "Ring Road Speed Trap", "score_text": "%d km/h" % int(Game.player_car.get_speed_kmh()),
		"personal_best": true, "medal": "Gold"})
	Game.notify("Speed trap", "New personal best!", &"pb")
	await _drive(0.12)
	_window("finish + flash")
	await _shot("hud_flash")
	await _reset()
	await _drive(0.6)
	_window("result banner")
	await _shot("hud_result")
	await _drive(4.0)
	# Telemetry.
	Settings.set_value("show_telemetry", true, false)
	await _reset()
	await _drive(1.5)
	_window("telemetry")
	await _shot("hud_telemetry")
	Settings.set_value("show_telemetry", false, false)
	# Region popup.
	Game.region_changed.emit("Ochre Mesa")
	await _reset()
	await _drive(1.2)
	_window("region popup")
	await _shot("hud_region")
	# World map.
	await _reset()
	if _arg("bench", "") != "":
		load("res://tools/tests/ui_hud_prof.gd").reset()
	ui.call("open_map")
	var f0 := Engine.get_process_frames()
	var t0 := Time.get_ticks_msec()
	await _wait(0.5)
	_window("map open")
	_log("map fade %.2f after %d frames / %d ms" % [(ui.get("world_map") as CanvasItem).modulate.a, Engine.get_process_frames() - f0, Time.get_ticks_msec() - t0])
	await _shot("map_fit")
	var wm: Node = ui.get("world_map")
	var car_pos := Game.player_car.global_position
	wm.set("_center", Vector2(car_pos.x - 300.0, car_pos.z - 150.0))
	wm.set("_zoom", 0.75)
	var mill := _poi("Millbrook")
	await get_tree().process_frame
	var sp: Vector2 = wm.call("_to_screen", Vector2(mill.x, mill.z))
	wm.set("_mouse", sp)
	await _wait(0.4)
	await _shot("map_zoom")
	if _arg("bench", "") != "":
		_log("PROF map:
" + load("res://tools/tests/ui_hud_prof.gd").report())
	# Map click: waypoint on an empty spot, then fast travel to the hovered POI (Millbrook).
	var empty_spot: Vector2 = wm.call("_to_screen", Vector2(mill.x + 260.0, mill.z - 330.0))
	wm.call("_set_waypoint_at", empty_spot)
	_log("map click waypoint: %s gps active=%s" % [str(Game.waypoint.round()), gps_node().get("active")])
	wm.call("_set_waypoint_at", sp)
	wm.set("_mouse", sp)
	await get_tree().process_frame
	await get_tree().process_frame
	follower = null
	wm.call("_fast_travel")
	await _wait(0.25)
	await _shot("travel_fade")
	var tw := 0.0
	while bool(ui.get("_travel_busy")) and tw < 12.0:
		await _wait(0.1)
		tw += 0.1
	await _wait(0.3)
	_log("fast travel: done in %.1f s, car %.0f m from Millbrook, map open=%s" % [tw, Game.player_car.global_position.distance_to(mill), wm.get("is_open")])
	await _shot("travel_arrived")
	# HUD hidden.
	ui.call("set_hud_visible", false)
	await _drive(0.4)
	await _shot("hud_hidden")
	ui.call("set_hud_visible", true)
	Game.clear_waypoint()
	await _drive(0.5)
	_log("route cleared active=%s" % gps.get("active"))
	_log("done")
	get_tree().quit(0)
