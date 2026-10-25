extends SceneTree
## Prints the node tree, bounds, wheel pivots and attachment points of an imported vehicle/prop .glb.
## Run: Godot_console.exe --headless --path . --script res://tools/inspect_glb.gd -- --glb=res://assets/imported/cars/01_pico_furia.glb


func _initialize() -> void:
	var path := ""
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with("--glb="):
			path = String(a).substr(6)
	var ps := load(path) as PackedScene
	if ps == null:
		print("FAILED to load ", path)
		quit(1)
		return
	var inst := ps.instantiate() as Node3D
	var total := AABB()
	var first := true
	var tris := 0
	for n in inst.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		var box := CarFactory.relative_transform(mi, inst) * mi.mesh.get_aabb()
		if first:
			total = box
			first = false
		else:
			total = total.merge(box)
		for s in mi.mesh.get_surface_count():
			var arr := mi.mesh.surface_get_arrays(s)
			var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
			tris += idx.size() / 3 if idx.size() > 0 else (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	print("AABB pos=", total.position, " size=", total.size, " tris=", tris)
	for n in inst.find_children("*", "Node3D", true, false):
		var nm := String(n.name)
		if nm.begins_with("Wheel_") or nm.begins_with("Caliper_") or nm.begins_with("CAM_") or nm.begins_with("FX_") or nm.begins_with("LIGHT_") or nm == "SteeringWheel":
			var t := CarFactory.relative_transform(n, inst)
			print("  %-16s pos=%s basis_x=%s basis_z=%s" % [nm, t.origin, t.basis.x, t.basis.z])
	var mats := {}
	for n in inst.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		for s in mi.mesh.get_surface_count():
			var m := mi.mesh.surface_get_material(s)
			mats[m.resource_name if m else "<none>"] = true
	print("materials: ", mats.keys())
	quit()
