extends SceneTree
## Prints measured facts about the baked world (roads, bridges, tunnels, buildings, vegetation,
## activities) for the documentation.
##   godot --headless --path . --script res://tools/qa/world_stats.gd


func _init() -> void:
	var wd: WorldData = load("res://world/generated/world_data.res")
	var roads := []
	var total := 0.0
	var bridge_m := 0.0
	var tunnel_m := 0.0
	var bridges := 0
	for r: Dictionary in wd.roads:
		var kind: PackedByteArray = r.kind
		var b := 0
		var t := 0
		var runs_b := 0
		var prev := 0
		for k in kind:
			if k == 1:
				b += 1
				if prev != 1:
					runs_b += 1
			elif k == 2:
				t += 1
			prev = k
		total += float(r.length)
		bridge_m += b * 2.0
		tunnel_m += t * 2.0
		bridges += runs_b
		roads.append("%s %s %.2f km bridges %d m tunnel %d m" % [r.id, r["class"], float(r.length) / 1000.0, b * 2, t * 2])
	var kits := {}
	for b: Dictionary in wd.buildings:
		kits[b.kit] = int(kits.get(b.kit, 0)) + 1
	var trees := 0
	for key: String in wd.trees:
		trees += (wd.trees[key] as PackedFloat32Array).size() / 6
	var acts := {}
	for a: Dictionary in wd.activities:
		acts[a.type] = int(acts.get(a.type, 0)) + 1
	print("WORLD_STATS ", JSON.stringify({"roads": wd.roads.size(), "road_km": snappedf(total / 1000.0, 0.01),
		"bridge_m": bridge_m, "bridge_count": bridges, "tunnel_m": tunnel_m, "buildings": wd.buildings.size(), "by_kit": kits,
		"vegetation_instances": trees, "activities": acts, "pois": wd.pois.size(), "regions": wd.regions.size(), "half": wd.half}))
	for line: String in roads:
		print("  ", line)
	quit(0)
