extends SceneTree
func _init() -> void:
	var d := WorldData.new()
	d.load_all()
	var r := d.road_by_id("festival_loop")
	var n := r.pts.size()
	var bad := 0
	var worst := 0.0
	var wi := 0
	for i in n:
		var p := r.pts[i]
		var h := d.height_at(p.x, p.z)
		if r.flags[i] == 0 and h > p.y - 0.05:
			bad += 1
			if h - p.y > worst:
				worst = h - p.y
				wi = i
	print("loop samples ", n, " terrain-above-road ", bad, " worst ", worst, " at ", wi, " ", r.pts[wi])
	var i0 := int(0.5 * (n - 2))
	for k in range(i0 - 20, i0 + 20, 4):
		var p := r.pts[k]
		print(k, " road y ", snappedf(p.y, 0.01), " terrain ", snappedf(d.height_at(p.x, p.z), 0.01), " flag ", r.flags[k])
	quit()
