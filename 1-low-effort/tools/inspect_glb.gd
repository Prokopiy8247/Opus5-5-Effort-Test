extends SceneTree
func _init() -> void:
	var s: Node = (load("res://assets/imported/vehicles/car01_kestrel.glb") as PackedScene).instantiate()
	_p(s, 0)
	quit()
func _p(n: Node, d: int) -> void:
	var extra := ""
	if n is MeshInstance3D:
		var m: Mesh = (n as MeshInstance3D).mesh
		var mats: Array = []
		for i in m.get_surface_count(): mats.append(m.surface_get_material(i).resource_name)
		extra = " aabb=%s mats=%s" % [m.get_aabb(), mats]
	if n is Node3D: extra += " pos=%s" % (n as Node3D).position
	print("  ".repeat(d), n.name, " ", n.get_class(), extra)
	for c in n.get_children(): _p(c, d + 1)
