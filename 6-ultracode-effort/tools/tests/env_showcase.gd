extends Node
## Environment test bench: runs the real main scene and captures a list of time / weather / camera
## combinations per location without reloading, plus FPS samples and an optional lightning shot.
## Run: Godot_console.exe --path . --resolution 1600x900 res://tools/tests/env_showcase.tscn -- [options]
##   --spec="Sunward Festival@12@clear@0;Gullhaven@19@storm@1@bolt"   (target@hour@weather@view[@bolt])
##   --out=res://qa_output/env/show  --settle=1.2  --fps-secs=2

const SkyModel := preload("res://scripts/env/sky_model.gd")

var out_dir := "res://qa_output/env/show"


static func _arg(key: String, def: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--" + key + "="):
			return a.substr(key.length() + 3)
	return def


func _ready() -> void:
	SaveGame.enabled = false
	print("[env] settings quality=%s vsync=%s" % [Settings.get_value("quality"), Settings.get_value("vsync")])
	if _arg("reset-settings", "") == "1":
		# Restores the defaults that earlier test runs may have persisted.
		Settings.set_value("quality", 2)
		Settings.set_value("vsync", true)
		print("[env] settings restored quality=%s vsync=%s" % [Settings.get_value("quality"), Settings.get_value("vsync")])
		get_tree().quit(0)
		return
	if _arg("vsync", "1") == "0" and DisplayServer.get_name() != "headless":
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	out_dir = _arg("out", out_dir)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(main)
	_run.call_deferred()


func _wait(s: float) -> void:
	await get_tree().create_timer(s, true, false, true).timeout


func _run() -> void:
	var t := 0.0
	while Game.main == null or Game.main.is_loading:
		await get_tree().process_frame
		t += get_process_delta_time()
		if t > 70.0:
			break
	(Game.main as Node).car_input.enabled = false
	var vp_rid := get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp_rid, true)
	var env: Node = Game.env
	env.set_time_scale(0.0)
	env.lightning.connect(func(st: float) -> void: print("[env] lightning signal strength=%.2f" % st))
	var settle := _arg("settle", "1.2").to_float()
	var fps_secs := _arg("fps-secs", "2").to_float()
	var spec := _arg("spec", "Sunward Festival@12@clear@0")
	var last_target := ""
	for item in spec.split(";"):
		var f := item.split("@")
		var target := f[0]
		var hour := f[1].to_float() if f.size() > 1 else 12.0
		var weather := f[2] if f.size() > 2 else "clear"
		var view := f[3].to_int() if f.size() > 3 else 0
		var flags := f[4] if f.size() > 4 else ""
		var bolt := flags.contains("bolt")
		var rev := flags.contains("rev")
		if target + str(rev) != last_target:
			if not Game.teleport(target):
				print("[env] teleport failed ", target)
				continue
			if rev:
				for td: Dictionary in Game.get_teleport_targets():
					if String(td["name"]) == target:
						(Game.main as Node).teleport_to({"position": td["position"], "forward": -(td["forward"] as Vector3)})
			last_target = target + str(rev)
			await _wait(0.3)
			var w := Game.world as World
			var tt := 0.0
			while tt < 20.0 and (w.terrain.pending_count() > 0 or not w.roads.done):
				await get_tree().process_frame
				tt += get_process_delta_time()
			Game.player_car.freeze = false
			await _wait(1.0)
		Game.set_time_of_day(hour)
		if not flags.contains("keep"):
			Game.set_weather(weather, not flags.contains("soft"))
		Game.camera_rig.set_mode(view)
		var item_settle := settle
		for tok in flags.split("+"):
			if tok.begins_with("s") and tok.substr(1).is_valid_float():
				item_settle = tok.substr(1).to_float()
		if flags.contains("diag"):
			var car := Game.player_car
			var vis := car.get_node("Visual") as CarVisuals
			print("[env] visual xf ", vis.transform, " sockets ", vis.sockets.keys())
			for l in vis.headlights:
				print("[env] headlight local ", car.to_local(l.global_position), " dir ", car.global_transform.basis.inverse() * (-l.global_transform.basis.z), " vis ", l.visible, " e ", l.light_energy)
		if flags.contains("nolights"):
			await _wait(0.1)
			Game.player_car.headlights_on = false
		var sky_cam := flags.contains("sun") or flags.contains("moon")
		if sky_cam:
			await _wait(0.4)
			Game.camera_rig.active = false
			var dir := SkyModel.sun_direction(hour) if flags.contains("sun") else SkyModel.moon_direction(hour)
			var flat := Vector3(dir.x, 0.0, dir.z).normalized()
			var look := (dir - Vector3.UP * clampf(dir.y * 0.7, 0.08, 0.3)).normalized()
			var cpos := Game.player_car.global_position + Vector3.UP * 2.2 - flat * 7.0
			Game.camera_rig.camera.global_transform = Transform3D(Basis.looking_at(look, Vector3.UP), cpos)
		await _wait(item_settle)
		var frames := 0
		var ft := 0.0
		var worst := 0.0
		var gpu_sum := 0.0
		while ft < fps_secs:
			await get_tree().process_frame
			var d := get_process_delta_time()
			ft += d
			frames += 1
			worst = maxf(worst, d)
			gpu_sum += RenderingServer.viewport_get_measured_render_time_gpu(vp_rid)
		if bolt:
			env.strike_lightning(900.0)
			await _wait(0.03)
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		var name := "%s_%02d_%s_v%d%s" % [target.to_snake_case().replace(" ", "_").replace("-", ""), int(hour * 10.0), weather, view, ("_" + flags) if flags != "" else ""]
		var path := out_dir.path_join(name + ".png")
		img.save_png(path)
		if sky_cam:
			Game.camera_rig.active = true
		print("[env] gpu_ms=%.2f" % (gpu_sum / maxf(frames, 1)))
		print("[env] shot %s fps=%.1f worst_ms=%.1f wet=%.2f night=%s lights=%s tunnel=%s weather=%s car_wet=%.2f q=%d" % [name, frames / maxf(ft, 0.001), worst * 1000.0, env.get_wetness(), env.is_night(), env.lights_needed(), env.is_in_tunnel(), env.get_weather(), CarController.wetness, int(env.get("_caps").get("quality", -1))])
	print("[env] done")
	get_tree().quit(0)
