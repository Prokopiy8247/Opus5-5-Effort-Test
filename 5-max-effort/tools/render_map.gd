extends SceneTree
## Renders the baked world into top-down map images:
##   res://data/world/map.png        clean stylised map for the in-game minimap / world map
##   qa_out/map_debug.png            debug map (bridges red, tunnels violet, rails yellow)
## Run: Godot_console.exe --headless --path . --script res://tools/render_map.gd

const S := 2048


func _initialize() -> void:
	var wd := WorldData.new()
	if not wd.load_data():
		print("world data missing")
		quit(1)
		return
	var img := Image.create(S, S, false, Image.FORMAT_RGBA8)
	var half := wd.half
	var px_m := 2.0 * half / S
	var light := Vector3(-0.6, 0.75, -0.35).normalized()
	for py in S:
		var z := -half + (py + 0.5) * px_m
		for px in S:
			var x := -half + (px + 0.5) * px_m
			var h := wd.height_at(x, z)
			var n := wd.normal_at(x, z)
			var shade := clampf(n.dot(light), 0.0, 1.0) * 0.55 + 0.55
			var col: Color
			var water := wd.water_level_at(x, z)
			if h < water - 0.05:
				var depth := clampf((water - h) / 12.0, 0.0, 1.0)
				col = Color(0.36, 0.6, 0.72).lerp(Color(0.12, 0.3, 0.48), depth)
			else:
				var sp := wd.splat_at(x, z)
				col = Color(0.47, 0.6, 0.33)
				col = col.lerp(Color(0.76, 0.69, 0.42), sp.r * 0.7)
				col = col.lerp(Color(0.78, 0.55, 0.36), sp.g)
				col = col.lerp(Color(0.24, 0.38, 0.22), sp.b * 0.85)
				col = col.lerp(Color(0.86, 0.8, 0.62), sp.a)
				var slope := 1.0 - n.y
				col = col.lerp(Color(0.52, 0.5, 0.47), smoothstep(0.25, 0.55, slope))
				col = col.lerp(Color(0.95, 0.96, 0.98), smoothstep(wd.snow_line, wd.snow_line + 60.0, h) * (1.0 - smoothstep(0.5, 0.8, slope)))
				col = Color(col.r * shade, col.g * shade, col.b * shade)
			img.set_pixel(px, py, col)
	var dbg := img.duplicate() as Image
	# roads
	for r in wd.roads:
		var w := maxf(float(r["width"]) / px_m, 1.5)
		var c := Color(0.95, 0.93, 0.88) if r["surface"] in ["asphalt", "concrete"] else Color(0.72, 0.58, 0.42)
		if r["class"] == "highway":
			c = Color(1.0, 0.82, 0.4)
		if r["scenic"]:
			c = Color(1.0, 0.95, 0.75)
		var xs: PackedFloat32Array = r["x"]
		var zs: PackedFloat32Array = r["z"]
		var fl: PackedInt32Array = r["flags"]
		for i in range(0, xs.size() - 1):
			var a := Vector2((xs[i] + half) / px_m, (zs[i] + half) / px_m)
			var b := Vector2((xs[i + 1] + half) / px_m, (zs[i + 1] + half) / px_m)
			_line(img, a, b, w, c)
			var dc := c
			if fl[i] & WorldData.F_BRIDGE:
				dc = Color(1, 0.15, 0.1)
			elif fl[i] & WorldData.F_TUNNEL:
				dc = Color(0.7, 0.2, 1.0)
			elif fl[i] & (WorldData.F_RAIL_L | WorldData.F_RAIL_R):
				dc = Color(1, 0.9, 0.1)
			_line(dbg, a, b, maxf(w, 2.5), dc)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://qa_out"))
	img.save_png("res://data/world/map.png")
	dbg.save_png("res://qa_out/map_debug.png")
	print("map written")
	quit()


func _line(img: Image, a: Vector2, b: Vector2, w: float, c: Color) -> void:
	var steps := int(maxf(a.distance_to(b), 1.0))
	var r := int(ceil(w * 0.5))
	for s in steps + 1:
		var p := a.lerp(b, float(s) / float(steps))
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if dx * dx + dy * dy > r * r + 1:
					continue
				var x := int(p.x) + dx
				var y := int(p.y) + dy
				if x >= 0 and y >= 0 and x < S and y < S:
					img.set_pixel(x, y, c)
