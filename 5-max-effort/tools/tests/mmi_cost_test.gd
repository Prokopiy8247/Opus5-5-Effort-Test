extends Node3D
## Micro-benchmark: where does adding a MultiMeshInstance3D spend its time?
## Run: Godot --path . --resolution 1280x720 res://tools/tests/mmi_cost_test.tscn [--render-thread separate]

var cam: Camera3D


func _ready() -> void:
	cam = Camera3D.new()
	add_child(cam)
	cam.position = Vector3(0, 30, 120)
	cam.look_at(Vector3.ZERO)
	await get_tree().process_frame
	var mesh := PropLibrary.mesh("tree_broadleaf")
	var mode := "default"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--mode="):
			mode = a.substr(7)
	if mode == "interp_off":
		get_tree().physics_interpolation = false
	print("[mmi] mode=", mode)
	for round_i in 4:
		var t_alloc := 0.0
		var t_buf := 0.0
		var t_add := 0.0
		var t_reuse := 0.0
		for it in 25:
			var t0 := Time.get_ticks_usec()
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.use_colors = true
			mm.custom_aabb = AABB(Vector3(-200, -10, -200), Vector3(400, 60, 400))
			mm.mesh = mesh
			mm.instance_count = 400
			var t1 := Time.get_ticks_usec()
			var buf := PackedFloat32Array()
			buf.resize(400 * 16)
			for i in 400:
				var o := i * 16
				buf[o] = 1.0
				buf[o + 5] = 1.0
				buf[o + 10] = 1.0
				buf[o + 3] = randf_range(-200, 200)
				buf[o + 11] = randf_range(-200, 200)
				buf[o + 12] = 1.0
				buf[o + 13] = 1.0
				buf[o + 14] = 1.0
				buf[o + 15] = 1.0
			var t2 := Time.get_ticks_usec()
			mm.buffer = buf
			var t3 := Time.get_ticks_usec()
			var mmi: GeometryInstance3D
			if mode == "meshinstance":
				var mi := MeshInstance3D.new()
				mi.mesh = mesh
				mmi = mi
			else:
				var m3 := MultiMeshInstance3D.new()
				m3.multimesh = mm
				mmi = m3
			if mode == "node_interp_off":
				mmi.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
			mmi.visibility_range_end = 1900.0
			add_child(mmi)
			var t4 := Time.get_ticks_usec()
			# second buffer write on an existing multimesh (what a pooled approach would do)
			mm.buffer = buf
			var t5 := Time.get_ticks_usec()
			t_alloc += (t1 - t0) / 1000.0
			t_buf += (t3 - t2) / 1000.0
			t_add += (t4 - t3) / 1000.0
			t_reuse += (t5 - t4) / 1000.0
			await get_tree().process_frame
		print("[mmi] round %d (%d nodes): alloc %.3f  set_buffer %.3f  add_child %.3f  rewrite %.3f ms (avg)" % [
			round_i, get_child_count(), t_alloc / 25.0, t_buf / 25.0, t_add / 25.0, t_reuse / 25.0])
	# plain Node3D add for reference
	var t6 := Time.get_ticks_usec()
	for i in 25:
		add_child(Node3D.new())
	print("[mmi] plain Node3D add avg %.3f ms" % ((Time.get_ticks_usec() - t6) / 25000.0))
	print("[mmi] thread_model=", ProjectSettings.get_setting("rendering/driver/threads/thread_model"),
		" physics_interp=", ProjectSettings.get_setting("physics/common/physics_interpolation"))
	get_tree().quit()
