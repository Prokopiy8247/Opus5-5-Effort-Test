extends Node
## PropLibrary checks (no rendering needed):
##  1. every contract prop name yields a mesh (placeholder while kits are missing) with sane bounds;
##  2. the kit merge path: a simulated kit object with two parts in a non-identity parent placement is
##     merged into one ArrayMesh in the object's local space with materials kept, and vegetation
##     materials are converted to the wind/tint foliage shader.
## Prints PROPLIB_OK / PROPLIB_FAIL.

const PropLibrary := preload("res://scripts/world/prop_library.gd")


func _ready() -> void:
	var fails: PackedStringArray = []
	var total_tris := 0
	for name in PropLibrary.names():
		var m := PropLibrary.mesh(name)
		var bb := PropLibrary.aabb(name)
		var tris := 0
		for i in m.get_surface_count():
			var arr := m.surface_get_arrays(i)
			var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			tris += (idx.size() if not idx.is_empty() else (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()) / 3
		total_tris += tris
		var ok := tris > 0 and bb.size.length() > 0.2 and bb.position.y < 0.6 and bb.end.y > 0.05
		print("  %-20s %s tris=%5d size=(%.1f, %.1f, %.1f) y=[%.1f, %.1f]%s" % [name, "placeholder" if PropLibrary.is_placeholder(name) else "kit", tris,
			bb.size.x, bb.size.y, bb.size.z, bb.position.y, bb.end.y, "" if ok else "  <-- BAD"])
		if not ok:
			fails.append(name)
	for fam in 4:
		if PropLibrary.far_mesh(fam).get_surface_count() != 1:
			fails.append("far_%d" % fam)
	# simulated kit object
	var root := Node3D.new()
	var obj := Node3D.new()
	obj.name = "Tree_Test"
	obj.position = Vector3(10, 0, 5)
	obj.rotation = Vector3(0, 0.7, 0)
	root.add_child(obj)
	var trunk := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.height = 4.0
	var bark := StandardMaterial3D.new()
	bark.resource_name = "Bark_Oak"
	bark.albedo_color = Color(0.4, 0.3, 0.2)
	cm.material = bark
	trunk.mesh = cm
	trunk.position = Vector3(0, 2, 0)
	obj.add_child(trunk)
	var crown := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 2.0
	sm.height = 3.0
	var leaves := StandardMaterial3D.new()
	leaves.resource_name = "Leaves_Oak"
	leaves.albedo_color = Color(0.3, 0.6, 0.2)
	sm.material = leaves
	crown.mesh = sm
	crown.position = Vector3(0.5, 5.5, 0)
	obj.add_child(crown)
	var merged := PropLibrary._merge(obj)
	if merged == null:
		fails.append("merge returned null")
	else:
		var bb := merged.get_aabb()
		print("  merged: surfaces=%d aabb=%s" % [merged.get_surface_count(), bb])
		if merged.get_surface_count() != 2 or absf(bb.position.y) > 0.01 or absf(bb.end.y - 7.0) > 0.05 or bb.end.x > 3.0:
			fails.append("merge bounds/surfaces")
		PropLibrary._adapt_foliage("Tree_Oak_A", merged)
		var kinds: PackedStringArray = []
		for i in merged.get_surface_count():
			var mat := merged.surface_get_material(i) as ShaderMaterial
			kinds.append("none" if mat == null else str(mat.get_shader_parameter("leaf_override")))
		print("  foliage leaf flags per surface: ", kinds)
		if not ("1.0" in kinds or "1" in kinds) or not ("0.0" in kinds or "0" in kinds):
			fails.append("foliage conversion")
	root.free()
	print("  total placeholder triangles: ", total_tris)
	print("PROPLIB_OK" if fails.is_empty() else "PROPLIB_FAIL %s" % [fails])
	get_tree().quit(0 if fails.is_empty() else 1)
