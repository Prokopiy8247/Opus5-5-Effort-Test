extends SceneTree
func _init() -> void:
	var w := WorldData.new()
	w.build()
	for p in [Vector2(-655, -1503), Vector2(-640,-1540)]:
		var q: Dictionary = w.road_query(p.x, p.y)
		print(p, " q=", q, " nat=", w.natural_height(p.x, p.y), " h=", w.height(p.x, p.y))
	for r in w.roads:
		var fl: PackedByteArray = r.flags
		var i := 0
		while i < fl.size():
			if fl[i] == 2:
				var j := i
				while j < fl.size() and fl[j] == 2: j += 1
				print("TUNNEL ", r.name, " from ", r.pts[i].round(), " len ", (j - i) * 4)
				i = j
			else:
				i += 1
	quit()
