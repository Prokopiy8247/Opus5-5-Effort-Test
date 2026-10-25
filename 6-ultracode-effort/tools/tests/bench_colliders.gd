extends Node3D
## Measures main-thread cost of terrain collider creation: ConcavePolygonShape3D vs HeightMapShape3D.
func _ready() -> void:
	await get_tree().physics_frame
	var n := 65
	var faces := PackedVector3Array()
	var hm := PackedFloat32Array()
	hm.resize(n * n)
	for j in n:
		for i in n:
			hm[j * n + i] = sin(i * 0.3) * 3.0 + cos(j * 0.2) * 2.0
	for j in n - 1:
		for i in n - 1:
			var p00 := Vector3(i * 2, hm[j * n + i], j * 2)
			var p10 := Vector3((i + 1) * 2, hm[j * n + i + 1], j * 2)
			var p01 := Vector3(i * 2, hm[(j + 1) * n + i], (j + 1) * 2)
			var p11 := Vector3((i + 1) * 2, hm[(j + 1) * n + i + 1], (j + 1) * 2)
			faces.append_array([p00, p10, p01, p10, p11, p01])
	for rep in 3:
		var t0 := Time.get_ticks_usec()
		var body := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var sh := ConcavePolygonShape3D.new()
		sh.set_faces(faces)
		cs.shape = sh
		body.add_child(cs)
		add_child(body)
		var t1 := Time.get_ticks_usec()
		await get_tree().physics_frame
		var t2 := Time.get_ticks_usec()
		print("trimesh: create+add %.2f ms, next physics frame %.2f ms" % [(t1 - t0) / 1000.0, (t2 - t1) / 1000.0])
		var t3 := Time.get_ticks_usec()
		var body2 := StaticBody3D.new()
		var cs2 := CollisionShape3D.new()
		var hs := HeightMapShape3D.new()
		hs.map_width = n
		hs.map_depth = n
		hs.map_data = hm
		cs2.shape = hs
		cs2.scale = Vector3(2, 1, 2)
		body2.add_child(cs2)
		add_child(body2)
		var t4 := Time.get_ticks_usec()
		await get_tree().physics_frame
		var t5 := Time.get_ticks_usec()
		print("heightmap: create+add %.2f ms, next physics frame %.2f ms" % [(t4 - t3) / 1000.0, (t5 - t4) / 1000.0])
	get_tree().quit(0)
