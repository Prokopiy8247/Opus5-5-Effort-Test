extends SceneTree
## Bakes the procedural world (deterministic, seeded) into res://data/world/.
##   Godot_console.exe --headless --path <project> --script res://tools/bake_world.gd
## Outputs: heights.bin (zstd, uint16 cm), surface.png, road_dist.png, regions.png, roads.json,
## world_meta.json, minimap.png (+ qa_output/world_debug.png for inspection).

const OUT := "res://data/world/"


func _init() -> void:
	var t0 := Time.get_ticks_msec()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var gen := WorldGen.new()
	gen.generate()
	_save_heights(gen)
	_save_maps(gen)
	_save_roads(gen)
	_save_meta(gen)
	var img := MapRenderer.render(gen, 1024)
	img.save_png(OUT + "minimap.png")
	var dbg := MapRenderer.render(gen, 2048, true)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://qa_output"))
	dbg.save_png("res://qa_output/world_debug.png")
	print("[bake] total %d ms" % (Time.get_ticks_msec() - t0))
	quit(0)


func _save_heights(gen: WorldGen) -> void:
	var n := WorldGen.N * WorldGen.N
	var buf := PackedByteArray()
	buf.resize(n * 2)
	for i in n:
		var v := clampi(int(round((gen.heights[i] + 100.0) * 100.0)), 0, 65535)
		buf.encode_u16(i * 2, v)
	var f := FileAccess.open_compressed(OUT + "heights.bin", FileAccess.WRITE, FileAccess.COMPRESSION_ZSTD)
	f.store_32(WorldGen.N)
	f.store_buffer(buf)
	f.close()
	# Natural (uncarved) heights are not needed at runtime: the far terrain uses WorldGen directly.


func _save_maps(gen: WorldGen) -> void:
	var s := Image.create_from_data(WorldGen.MAP_N, WorldGen.MAP_N, false, Image.FORMAT_L8, gen.surface_map)
	s.save_png(OUT + "surface.png")
	var r := Image.create_from_data(WorldGen.MAP_N, WorldGen.MAP_N, false, Image.FORMAT_L8, gen.road_dist)
	r.save_png(OUT + "road_dist.png")
	var g := Image.create_from_data(WorldGen.REG_N, WorldGen.REG_N, false, Image.FORMAT_RGBA8, gen.region_rgba)
	g.save_png(OUT + "regions.png")


func _round_arr(arr: PackedFloat32Array, digits: float) -> Array:
	var out := []
	for v in arr:
		out.append(snappedf(v, digits))
	return out


func _save_roads(gen: WorldGen) -> void:
	var list := []
	for r: Dictionary in gen.roads:
		var pos: PackedVector3Array = r["pos"]
		var flat := []
		for p in pos:
			flat.append(snappedf(p.x, 0.01))
			flat.append(snappedf(p.y, 0.01))
			flat.append(snappedf(p.z, 0.01))
		var d := r.duplicate()
		d["pos"] = flat
		d["bank"] = _round_arr(r["bank"], 0.0001)
		d["flags"] = Array(r["flags"])
		list.append(d)
	var f := FileAccess.open(OUT + "roads.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"version": 1, "ds": WorldGen.DS, "roads": list, "junctions": gen.junctions}))
	f.close()


func _save_meta(gen: WorldGen) -> void:
	var pois := []
	for p: Dictionary in WorldLayout.POIS:
		var d := p.duplicate()
		d["y"] = gen.sample_height(p["pos"][0], p["pos"][1])
		pois.append(d)
	var lakes := []
	for i in WorldLayout.LAKES.size():
		var lk: Dictionary = WorldLayout.LAKES[i].duplicate()
		lk["level"] = gen.lake_level(i)
		lakes.append(lk)
	var stats := {"road_km": 0.0, "by_road": {}}
	var total := 0.0
	for r: Dictionary in gen.roads:
		total += float(r["length"])
		stats["by_road"][r["id"]] = snappedf(float(r["length"]), 1.0)
	stats["road_km"] = snappedf(total / 1000.0, 0.01)
	var hole_list := []
	for k: int in gen.holes:
		hole_list.append(k)
	# Smoothed river centreline with the terrain-derived water levels [x, z, water_y].
	var river := []
	for i in gen._river_pts.size():
		river.append([snappedf(gen._river_pts[i].x, 0.01), snappedf(gen._river_pts[i].y, 0.01), snappedf(gen._river_y[i], 0.01)])
	var meta := {
		"version": 1, "seed": WorldLayout.SEED, "half": WorldLayout.HALF, "cell": WorldGen.CELL, "n": WorldGen.N,
		"pois": pois, "lakes": lakes, "river": river, "stats": stats, "holes": hole_list,
		"log": Array(gen.log_lines),
	}
	var f := FileAccess.open(OUT + "world_meta.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(meta, "\t"))
	f.close()
	print("[bake] total road length %.2f km" % (total / 1000.0))
	for k: String in stats["by_road"]:
		print("   ", k, ": ", stats["by_road"][k], " m")
	var lv: PackedFloat32Array = gen._river_y
	print("[bake] river %d points, water %.1f .. %.1f m" % [lv.size(), lv[0], lv[lv.size() - 1]])
