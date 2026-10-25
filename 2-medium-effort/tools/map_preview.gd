extends SceneTree
## Headless tool: builds the world data, prints road stats and renders a top-down map PNG.
## godot --headless --path . --script res://tools/map_preview.gd

func _init() -> void:
	var t0: int = Time.get_ticks_msec()
	var w := WorldData.new()
	w.build()
	print("build ms: ", Time.get_ticks_msec() - t0)
	var bridges: float = 0.0
	var tunnels: float = 0.0
	for r in w.roads:
		var fl: PackedByteArray = r.flags
		var nb: int = 0
		var nt: int = 0
		for f in fl:
			if f == 1: nb += 1
			elif f == 2: nt += 1
		bridges += nb * WorldData.STEP
		tunnels += nt * WorldData.STEP
		var maxk: float = 0.0
		var at: Vector3
		for ki in r.curv.size():
			if absf(r.curv[ki]) > maxk:
				maxk = absf(r.curv[ki]); at = r.pts[ki]
		if 1.0 / maxf(maxk, 0.0001) < 35.0: print("   tight at ", at)
		print("%-22s %-9s %6.0f m  minR %5.0f m  bridge %4d m  tunnel %4d m  h %.0f..%.0f" % [r.name, r.cls, r.length, 1.0 / maxf(maxk, 0.0001), nb * 4, nt * 4, r.pts[0].y, r.pts[r.pts.size() - 1].y])
	print("TOTAL road km: %.2f   loop km: %.2f   bridges m: %.0f  tunnels m: %.0f" % [w.total_length / 1000.0, w.loop_length / 1000.0, bridges, tunnels])
	var res: int = 512
	var img := Image.create(res, res, false, Image.FORMAT_RGB8)
	var t1: int = Time.get_ticks_msec()
	for py in res:
		for px in res:
			var x: float = (px + 0.5) / res * 4400.0 - 2200.0
			var z: float = (py + 0.5) / res * 4400.0 - 2200.0
			var h: float = w.natural_height(x, z)
			var c: Color
			if h < 0.0:
				c = Color(0.1, 0.3, 0.55).lerp(Color(0.05, 0.15, 0.35), clampf(-h / 15.0, 0, 1))
			else:
				c = w.terrain_color(x, z, h, 0.0)
				c = c.darkened(clampf(0.25 - h / 600.0, 0.0, 0.25))
				if int(h) % 20 == 0: c = c.darkened(0.12)
			img.set_pixel(px, py, c)
	print("map ms: ", Time.get_ticks_msec() - t1)
	for r in w.roads:
		var col := Color(0.15, 0.15, 0.15) if not r.loop else Color(0.9, 0.85, 0.2)
		if r.surface == 2 or r.surface == 3: col = Color(0.55, 0.35, 0.2)
		var pts: PackedVector3Array = r.pts
		for i in pts.size():
			var fl: int = r.flags[i]
			var cc: Color = col if fl == 0 else (Color(1, 0.2, 0.9) if fl == 1 else Color(1, 0.1, 0.1))
			var px: int = int((pts[i].x + 2200.0) / 4400.0 * res)
			var py: int = int((pts[i].z + 2200.0) / 4400.0 * res)
			for o in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1)]:
				var q: Vector2i = Vector2i(px, py) + o
				if q.x >= 0 and q.y >= 0 and q.x < res and q.y < res:
					img.set_pixelv(q, cc)
	img.save_png("res://qa/screens/map_preview.png")
	print("saved map")
	quit()
