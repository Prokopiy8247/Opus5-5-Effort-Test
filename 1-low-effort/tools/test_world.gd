extends SceneTree
func _init() -> void:
	var t := Time.get_ticks_msec()
	var w := WorldGen.new()
	w.build()
	print("build ms ", Time.get_ticks_msec() - t)
	for r in w.roads:
		var tn := 0; var br := 0
		for v in r.tunnel: tn += v
		for v in r.bridge: br += v
		print("%s  %.2f km  tunnel %d m bridge %d m  hmin %.0f hmax %.0f" % [r.name, r.length / 1000.0, tn * 4, br * 4, _mn(r.pts), _mx(r.pts)])
	print("total km ", w.total_road_km())
	t = Time.get_ticks_msec()
	var s := 0.0
	for i in 4225: s += w.height(randf() * 4000 - 2000, randf() * 4000 - 2000)
	print("4225 heights ms ", Time.get_ticks_msec() - t)
	quit()
func _mn(p: PackedVector3Array) -> float:
	var m := 1e9
	for v in p: m = min(m, v.y)
	return m
func _mx(p: PackedVector3Array) -> float:
	var m := -1e9
	for v in p: m = max(m, v.y)
	return m
