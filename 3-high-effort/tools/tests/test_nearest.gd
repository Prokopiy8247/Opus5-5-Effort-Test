extends SceneTree
func _init() -> void:
	var d := WorldData.new()
	d.load_all()
	print("roads ", d.roads.size(), " grid ", d._road_grid.size())
	for q in [Vector3(400, 0, 1080), Vector3(300, 0, 1150), Vector3(0, 0, 0)]:
		var nr := d.nearest_road(q, 300.0)
		print(q, " -> ", "none" if nr.is_empty() else "%s seg %d dist %.1f" % [nr.road.id, nr.seg, nr.dist])
	quit()
