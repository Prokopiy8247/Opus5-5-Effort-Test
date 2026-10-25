extends Node3D
## Verifies HeightMapShape3D placement conventions (index order, centring, scale) with raycasts.
func _ready() -> void:
	var n := 65
	var hm := PackedFloat32Array()
	hm.resize(n * n)
	for j in n:
		for i in n:
			hm[j * n + i] = float(i) * 0.5 + float(j) * 0.1 + 100.0   # x slope 0.5/cell, z slope 0.1/cell
	var body := StaticBody3D.new()
	body.position = Vector3(1000, 0, 2000)
	var cs := CollisionShape3D.new()
	var hs := HeightMapShape3D.new()
	hs.map_width = n
	hs.map_depth = n
	hs.map_data = hm
	cs.shape = hs
	cs.scale = Vector3(2, 1, 2)
	cs.position = Vector3(64, 0, 64)
	body.add_child(cs)
	add_child(body)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var space := get_world_3d().direct_space_state
	for pt: Vector2 in [Vector2(0, 0), Vector2(10, 0), Vector2(0, 10), Vector2(127, 127), Vector2(33.3, 77.7)]:
		var wx := 1000.0 + pt.x
		var wz := 2000.0 + pt.y
		var q := PhysicsRayQueryParameters3D.create(Vector3(wx, 500, wz), Vector3(wx, -100, wz))
		var hit := space.intersect_ray(q)
		var expect := (pt.x / 2.0) * 0.5 + (pt.y / 2.0) * 0.1 + 100.0
		print("pt %s hit %s expect %.3f" % [str(pt), str(hit.get("position", "none")), expect])
	get_tree().quit(0)
