extends SceneTree
func _init() -> void:
	var w := WorldGen.new(); w.build()
	for i in [0, 2, 10, 30, 60, 100]:
		var p := w.road_point(0, i)
		print(i, " ", p, " land=", w.land_height(p.x, p.z), " carved=", w.water_carve(p.x, p.z, w.land_height(p.x, p.z)), " h=", w.height(p.x, p.z), " tun=", w.roads[0].tunnel[i], " bri=", w.roads[0].bridge[i])
	quit()
