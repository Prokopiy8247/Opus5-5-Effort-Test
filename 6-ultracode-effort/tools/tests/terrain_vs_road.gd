extends SceneTree
## Compares baked terrain height with the road surface across a road section (diagnostics).
##   ... --headless --path . --script res://tools/tests/terrain_vs_road.gd -- --road=ring --from=560 --to=610
func _init() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=")
		if kv.size() == 2:
			args[kv[0]] = kv[1]
	var wd := WorldData.new()
	wd.load_all()
	var r := wd.network.get_road(args.get("road", "ring"))
	var s := float(args.get("from", "0"))
	while s <= float(args.get("to", "60")):
		var line := "s=%6.0f flag=%d " % [s, r.flag_at(s)]
		for lat: float in [-6.0, -4.9, -3.5, 0.0, 3.5, 4.9, 6.0]:
			var p := r.surface_point(s, lat)
			line += " %+.1f:%+.2f" % [lat, wd.height_at(p.x, p.z) - p.y]
		print(line)
		s += 3.0
	quit(0)
