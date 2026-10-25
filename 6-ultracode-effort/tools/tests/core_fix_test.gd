extends Node
## Regression checks for the core review fixes inside the real game (needs a renderer):
##   Godot_console.exe --path <project> --resolution 1280x720 res://tools/tests/core_fix_test.tscn
## Prints "[core] PASS|FAIL <check>" lines and "[core] failures: N". Changes no user settings.
## Playtest round 2 (vehicle): rewind restores damage and keeps the tyres quiet while scrubbing (q6, q34), the
## rewind label clears the activity panel (q32), wet grip is continuous across the wet-surface switch (q2/q37),
## switching to an attached camera view cuts instead of flying through the body (q3).

var main: Node
var fails := 0


func _ready() -> void:
	SaveGame.enabled = false
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(main)
	_run.call_deferred()


func _check(label: String, ok: bool, detail: String) -> void:
	print("[core] %s %s  %s" % ["PASS" if ok else "FAIL", label, detail])
	if not ok:
		fails += 1


func _wait(s: float) -> void:
	await get_tree().create_timer(s).timeout


func _phys(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _settle(w: World) -> void:
	var t0 := Time.get_ticks_msec()
	while not w.is_ready_near() and Time.get_ticks_msec() - t0 < 20000:
		await get_tree().process_frame
	await _wait(1.5)


func _run() -> void:
	while main.get("is_loading"):
		await get_tree().process_frame
	var w := Game.world as World
	# The live density only: Game.set_traffic_density would save the user's setting.
	if Game.traffic != null and Game.traffic.has_method("set_density"):
		Game.traffic.call("set_density", 0.0)
	Game.set_time_of_day(12.0)
	await _wait(1.0)

	# c9/c11: readiness must describe the new place right after a teleport.
	Game.teleport("Saltwind Lighthouse")
	var ready_now := w.is_ready_near()
	_check("c9 not ready right after teleport", not ready_now, "pending=%d" % w.terrain.pending_count())
	var t0 := Time.get_ticks_msec()
	await _settle(w)
	print("[core] streamed in %d ms" % (Time.get_ticks_msec() - t0))

	# c0: a non-pausing overlay while in reverse must hold the car.
	var car := Game.player_car
	car.gear = -1
	var p0 := car.global_position
	Game.push_overlay(true)
	await _wait(3.0)
	var moved := car.global_position.distance_to(p0)
	Game.push_overlay(false)
	_check("c0 overlay hold in reverse", moved < 0.3, "moved %.2f m, gear %d" % [moved, car.gear])
	await _wait(0.5)

	# c6: dirt survives a rebuild of the same car.
	var fx: Node = car.get_node_or_null(^"CarEffects")
	if fx != null:
		fx.call(&"set_dirt_level", 0.8)
	Game.spawn_car(Game.current_car_index, true)
	await _phys(3)
	car = Game.player_car
	var fx2: Node = car.get_node_or_null(^"CarEffects")
	_check("c6 dirt kept on rebuild", fx2 != null and absf(float(fx2.get(&"dirt")) - 0.8) < 0.05, "dirt=%s" % str(fx2.get(&"dirt") if fx2 else "-"))

	# c5: no g spike after a rebuild at speed.
	Game.teleport("Ring Road - Mesa Straight")
	await _settle(w)
	car = Game.player_car
	car.linear_velocity = -car.global_basis.z * 30.0
	await _phys(2)
	Game.spawn_car(Game.current_car_index, true)
	var peak := 0.0
	for i in 12:
		await get_tree().physics_frame
		peak = maxf(peak, absf(Game.player_car.longitudinal_g))
	_check("c5 no g spike after rebuild at speed", peak < 3.0, "peak long g %.1f, speed %.1f m/s" % [peak, Game.player_car.speed_ms])
	await _wait(1.0)

	# c3: rewind after a teleport must not jump back to the old place.
	car = Game.player_car
	var before := car.global_position
	await _wait(1.5)
	Game.teleport("Gullhaven")
	await _settle(w)
	var after_tp := Game.player_car.global_position
	Input.action_press(&"rewind")
	await _wait(1.5)
	Input.action_release(&"rewind")
	await _wait(0.5)
	var p_rw := Game.player_car.global_position
	_check("c3 rewind stays after teleport", p_rw.distance_to(after_tp) < 30.0 and p_rw.distance_to(before) > 200.0, "%.1f m from teleport spot, %.0f m from old spot" % [p_rw.distance_to(after_tp), p_rw.distance_to(before)])

	# c1: rebuild inside the tunnel keeps the car on the tunnel road.
	Game.teleport("Ember Spur Tunnel")
	await _settle(w)
	var y0 := Game.player_car.global_position.y
	Game.spawn_car(Game.current_car_index, true)
	await _wait(2.0)
	var y1 := Game.player_car.global_position.y
	_check("c1 rebuild in tunnel stays on road", absf(y1 - y0) < 1.0, "y %.2f -> %.2f" % [y0, y1])

	# c2: a car built at night gets its headlights.
	Game.set_time_of_day(23.0)
	await _wait(1.0)
	Game.spawn_car(Game.current_car_index, true)
	await _wait(0.5)
	var vis := Game.player_car.get_node(^"Visual") as CarVisuals
	var lit := not vis.headlights.is_empty()
	for l in vis.headlights:
		lit = lit and l.visible and l.light_energy > 1.0
	_check("c2 headlights on for a car built at night", lit and Game.player_car.headlights_on, "lights=%d on=%s" % [vis.headlights.size(), str(Game.player_car.headlights_on)])
	Game.set_time_of_day(12.0)

	# c4: look-back from an attached view starts from the car, not from stale chase state.
	var rig := Game.camera_rig as CameraRig
	rig.set_mode(CameraRig.Mode.CHASE_NEAR, false)
	await _wait(0.5)
	rig.set_mode(CameraRig.Mode.COCKPIT, false)
	await _wait(0.5)
	var target := w.nearest_road_point(Vector3(200, 0, 1200))
	var cp: Vector3 = target["position"]
	Game.player_car.place_at(Transform3D(Basis.looking_at(target["forward"], Vector3.UP), cp + Vector3.UP * 0.45))
	await _wait(1.0)
	Input.action_press(&"look_back")
	await get_tree().process_frame
	await get_tree().process_frame
	var dy := absf((rig as Node3D).global_position.y - Game.player_car.global_position.y)
	Input.action_release(&"look_back")
	_check("c4 look-back from cockpit starts at the car", dy < 6.0, "camera %.1f m above/below car (moved %.0f m)" % [dy, cp.distance_to(Vector3(0, y1, 0))])
	rig.set_mode(CameraRig.Mode.CHASE_NEAR, false)

	# Braking line: shows on the road ahead and turns red when too fast for the corner ahead.
	var prev_line: bool = bool(Settings.get_value("braking_line", false))
	Settings.set_value("braking_line", true, false)
	Game.teleport("Ring Road - Switchbacks")
	await _settle(w)
	(Game.camera_rig as CameraRig).set_mode(CameraRig.Mode.CHASE_FAR, false)
	Game.player_car.linear_velocity = -Game.player_car.global_basis.z * 30.0
	await _phys(30)
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://qa_output/core_fix"))
	img.save_png("res://qa_output/core_fix/braking_line.png")
	var bl := main.get_node(^"BrakingLine") as MeshInstance3D
	var im := bl.mesh as ImmediateMesh
	_check("braking line drawn", im.get_surface_count() == 1, "surfaces=%d" % im.get_surface_count())
	Settings.set_value("braking_line", prev_line, false)

	await _round2_checks()
	if Game.traffic != null and Game.traffic.has_method("set_density"):
		Game.traffic.call("set_density", float(Settings.get_value("traffic_density", 0.6)))

	print("[core] failures: %d" % fails)
	get_tree().quit()


func _round2_checks() -> void:
	var w := Game.world as World
	# q2/q37: the wet presentation surfaces carry the dry grip numbers, so grip does not step at the switch.
	var steps := ""
	for pair: Array in [[&"asphalt", &"asphalt_wet"], [&"concrete", &"concrete_wet"]]:
		var dry := Surfaces.get_surface(pair[0])
		var wet := Surfaces.get_surface(pair[1])
		var a := dry.grip_for(0.0, CarController.WET_LOOK) * dry.slide_for(CarController.WET_LOOK)
		var b := wet.grip_for(0.0, CarController.WET_LOOK) * wet.slide_for(CarController.WET_LOOK)
		steps += " %s %.3f/%.3f" % [pair[0], a, b]
		_check("q2/q37 %s wet switch keeps grip" % pair[0], absf(a - b) < 0.001 and dry.wet_id == pair[1] and not wet.smokes and wet.paved,
			"grip at the switch dry/wet %.3f/%.3f, wet surface smokes=%s" % [a, b, str(wet.smokes)])
	# q6 / q34 / q32: rewind over a moment the car took damage.
	Game.teleport("Ring Road - Mesa Straight")
	await _settle(w)
	var car := Game.player_car
	car.damage = 0.0
	car.linear_velocity = -car.global_basis.z * 20.0
	await _wait(1.5)
	car.damage = 0.3
	for wh in car.wheels:
		wh.skid = 1.0
	Input.action_press(&"rewind")
	await _wait(0.5)
	var quiet := car.rewinding and car.max_skid() == 0.0
	var fx: Node = car.get_node_or_null(^"CarEffects")
	var smoke := float((fx.call(&"debug_state") as Dictionary).get("smoke", 0.0)) if fx != null else 0.0
	var lbl: Label = null
	for c in car.get_node(^"CarRewind").get_children():
		if c is CanvasLayer:
			for d in c.get_children():
				if d is Label:
					lbl = d
	var rect := lbl.get_global_rect() if lbl != null else Rect2()
	Input.action_release(&"rewind")
	await _phys(3)
	_check("q6 rewind restores the damage", car.damage < 0.01, "damage %.3f after rewinding past a 0.3 hit" % car.damage)
	_check("q34 tyres quiet while scrubbing", quiet and smoke < 0.05, "rewinding=%s skid=%.2f smoke=%.2f" % [str(quiet), car.max_skid(), smoke])
	_check("q32 rewind label below the activity panel", lbl != null and rect.position.y >= 150.0 and rect.end.y <= 231.0, "label rect %s" % str(rect))
	# q3: an attached view is a cut (no blend through the body).
	var rig := Game.camera_rig as CameraRig
	rig.set_mode(CameraRig.Mode.CHASE_NEAR, false)
	await _wait(0.6)
	rig.set_mode(CameraRig.Mode.HOOD, false)
	await get_tree().process_frame
	await get_tree().process_frame
	var vis := car.get_node(^"Visual") as CarVisuals
	var bs := car.data.body_size
	var hood: Vector3 = (vis.sockets["Socket_CamHood"] as Transform3D).origin if vis.sockets.has("Socket_CamHood") else Vector3(0.0, bs.y * 0.92, -bs.z * 0.12)
	var lp := car.get_global_transform_interpolated().affine_inverse() * rig.camera.global_position
	_check("q3 attached camera view cuts", lp.distance_to(hood) < 0.5, "camera %.2f m from the hood socket 2 frames after the switch" % lp.distance_to(hood))
	rig.set_mode(CameraRig.Mode.CHASE_NEAR, false)
