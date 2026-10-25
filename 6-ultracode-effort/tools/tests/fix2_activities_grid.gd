extends Node
## Activities regression test (fix2): race / time-trial grid. Heights of every grid car above the road during the
## countdown, a reset (R) during the countdown, the drop at GO, where rival 1 stands relative to the chase cameras,
## and the race waypoint. Screenshots: chase near / chase far / side view during the countdown.
##   Godot_console.exe --path . --resolution 1600x900 res://tools/tests/fix2_activities_grid.tscn -- --ids=rc_highmoor --out=res://qa_output/<dir>

const MAIN := preload("res://scenes/main.tscn")

var out_dir := "res://qa_output/fix2_activities"
var _ray := PhysicsRayQueryParameters3D.new()


func _ready() -> void:
	SaveGame.enabled = false
	Game.personal_bests = {}
	Game.discovered = {}
	out_dir = _arg("out", out_dir)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	Game.notification.connect(func(t: String, b: String, k: StringName) -> void:
		if k != &"discovery":
			print("[gt] NOTIFY [%s] %s | %s" % [k, t, b]))
	add_child(MAIN.instantiate())
	_run.call_deferred()


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
	print("[gt] shot ", ProjectSettings.globalize_path(path))


func _cars() -> Array[CarController]:
	var out: Array[CarController] = [Game.player_car]
	out.append_array(Game.activities.get_ai_cars())
	return out


## Origin height above the road collider (world layer) under the car.
func _height(car: CarController) -> float:
	var ex: Array[RID] = []
	for c in _cars():
		ex.append(c.get_rid())
	_ray.from = car.global_position + Vector3.UP * 1.5
	_ray.to = car.global_position + Vector3.DOWN * 3.0
	_ray.collision_mask = 1
	_ray.exclude = ex
	var hit := car.get_world_3d().direct_space_state.intersect_ray(_ray)
	return car.global_position.y - (hit["position"] as Vector3).y if not hit.is_empty() else NAN


func _heights(label: String) -> void:
	var parts := PackedStringArray()
	for c in _cars():
		parts.append("%s %.3f m%s" % [c.name, _height(c), " frozen" if c.freeze else ""])
	print("[gt]   %s: %s" % [label, ", ".join(parts)])


func _run() -> void:
	while Game.main == null or Game.main.is_loading:
		await get_tree().process_frame
	Game.main.car_input.process_mode = Node.PROCESS_MODE_DISABLED
	var dens0: float = Game.traffic.get_density() if Game.traffic != null else 0.0
	if Game.traffic != null:
		Game.traffic.set_density(0.0)
	Game.set_time_of_day(12.0)
	Game.set_weather("clear", true)
	await _wait(1.0)
	for id in _arg("ids", "rc_highmoor,rc_coast,tt_sunward_ring").split(","):
		await _grid(id)
	if Game.traffic != null:
		Game.traffic.set_density(dens0)
	print("[gt] DONE")
	get_tree().quit(0)


func _grid(id: String) -> void:
	var mgr: Node = Game.activities
	var act: RefCounted = mgr.by_id[id]
	var ev: Dictionary = {}
	for e: Dictionary in mgr.get_activity_list():
		if e["id"] == id:
			ev = e
	var road := (Game.world as World).data.network.get_road(ev["road"])
	var d: int = ev["dir"]
	Game.set_waypoint(Vector3(-100, 0, 100))
	mgr.teleport_to_activity(id, 90.0)
	await _wait_streamed()
	var car := Game.player_car
	car.freeze = false
	var s0: float = ev["gates"][0] - d * 90.0
	var f := RoadFollower.new()
	f.setup(road, s0, d, road.lane_offset(1))
	f.target_speed = 45.0 / 3.6
	var t := 0.0
	var moving_h := NAN
	while t < 40.0 and int(act.get("state")) < 2:
		await get_tree().physics_frame
		var dt := get_physics_process_delta_time()
		t += dt
		if int(act.get("state")) == 1:
			f.target_speed = 0.0
		elif car.get_speed_kmh() > 30.0:
			moving_h = _height(car)
		f.drive(car, dt)
	if int(act.get("state")) != 2:
		print("[gt] %s: no countdown (state %d)" % [id, int(act.get("state"))])
		return
	print("[gt] ---- %s countdown; driving reference height %.3f m; waypoint %s owner %s" % [id, moving_h, str(Game.waypoint.round()),
		str(Game.get("waypoint_owner")) if "waypoint_owner" in Game else "-"])
	await get_tree().physics_frame
	_heights("countdown +0.0")
	await _wait(0.3)
	_heights("countdown +0.3")
	_rival_vs_camera(id, "near")
	await _shot("grid_%s_near" % id)
	Game.camera_rig.set_mode(1, false)
	await _wait(1.4)
	_rival_vs_camera(id, "far")
	await _shot("grid_%s_far" % id)
	Game.camera_rig.set_mode(0, false)
	var side := Camera3D.new()
	add_child(side)
	var pc := Game.player_car
	var right := pc.global_basis.x
	var side_pos := pc.global_position + right * 6.5 + Vector3.UP * 0.8 + pc.global_basis.z * 3.0
	side.global_position = side_pos
	side.look_at(pc.global_position + Vector3.UP * 0.4 + pc.global_basis.z * 3.0)
	side.fov = 50.0
	side.make_current()
	await _wait(0.1)
	await _shot("grid_%s_side" % id)
	Game.camera_rig.camera.make_current()
	side.queue_free()
	# R during the countdown.
	var before := pc.global_position
	Game.respawn()
	await get_tree().physics_frame
	await get_tree().physics_frame
	print("[gt]   R in countdown: moved %.2f m, height %.3f, frozen %s, state %d" % [pc.global_position.distance_to(before), _height(pc), pc.freeze, int(act.get("state"))])
	while int(act.get("state")) == 2:
		await get_tree().physics_frame
	var y0 := pc.global_position.y
	await get_tree().physics_frame
	await get_tree().physics_frame
	_heights("GO +2 frames")
	print("[gt]   player vertical speed at GO %.2f m/s, origin moved %.3f m in 2 frames" % [pc.linear_velocity.y, pc.global_position.y - y0])
	await _wait(1.5)
	_heights("GO +1.5")
	mgr.cancel_session("test")
	await _wait(0.5)
	print("[gt]   after cancel: waypoint %s (set before: (-100, 0, 100))" % str(Game.waypoint.round()))
	Game.clear_waypoint()
	await _wait(5.5)


## Where rival 1 stands relative to the active chase camera: in front of its near plane and inside the view?
func _rival_vs_camera(id: String, label: String) -> void:
	var ai: Array[CarController] = Game.activities.get_ai_cars()
	var cam: Camera3D = Game.camera_rig.get("camera")
	var pc := Game.player_car
	var rel_cam := pc.global_transform.affine_inverse() * cam.global_position
	for r in ai:
		if not String(r.name).begins_with("Rival_1"):
			continue
		var rel := pc.global_transform.affine_inverse() * r.global_position
		var bs := r.data.body_size
		var vis := 0
		var area := Rect2()
		var first := true
		for cx: float in [-0.5, 0.5]:
			for cy: float in [0.0, 1.0]:
				for cz: float in [-0.5, 0.5]:
					var p := r.global_transform * Vector3(cx * bs.x, cy * bs.y, cz * bs.z)
					if cam.is_position_behind(p):
						continue
					vis += 1
					var sp := cam.unproject_position(p)
					if first:
						area = Rect2(sp, Vector2.ZERO)
						first = false
					else:
						area = area.expand(sp)
		var vp := get_viewport().get_visible_rect()
		var cover := area.intersection(vp).get_area() / vp.get_area() if vis > 0 else 0.0
		print("[gt]   %s %s camera: cam rel player (lat %.2f up %.2f ahead %.2f), %s rel player (lat %.2f ahead %.2f), corners in front of camera %d/8, screen cover %.1f%%" % [
			id, label, rel_cam.x, rel_cam.y, -rel_cam.z, r.name, rel.x, -rel.z, vis, cover * 100.0])
