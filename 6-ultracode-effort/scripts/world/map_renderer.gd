class_name MapRenderer
extends RefCounted
## Renders the top-down map image (minimap / full map / debug view) from generator data.

const ROAD_COLORS := {
	0: Color(0.98, 0.84, 0.35),   # highway
	1: Color(0.96, 0.96, 0.94),   # regional
	2: Color(0.96, 0.96, 0.94),   # mountain
	3: Color(0.9, 0.9, 0.88),     # street
	4: Color(0.78, 0.6, 0.42),    # dirt
	5: Color(0.75, 0.7, 0.62),    # gravel
	6: Color(0.92, 0.82, 0.6),    # sand
}


static func render(gen: WorldGen, size: int, debug := false) -> Image:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var half := WorldLayout.HALF
	var scale := (half * 2.0) / size
	var light := Vector3(-0.6, 0.75, -0.45).normalized()
	for j in size:
		var z := -half + (j + 0.5) * scale
		for i in size:
			var x := -half + (i + 0.5) * scale
			var h := gen.sample_height(x, z)
			var hx := gen.sample_height(x + scale, z)
			var hz := gen.sample_height(x, z + scale)
			var n := Vector3(h - hx, scale, h - hz).normalized()
			var shade := clampf(n.dot(light) * 0.9 + 0.25, 0.3, 1.15)
			var col: Color
			if h < 0.0:
				col = Color(0.16, 0.38, 0.55).lerp(Color(0.06, 0.18, 0.32), clampf(-h / 30.0, 0.0, 1.0))
				shade = 1.0
			else:
				var rw := gen.region_weights(x, z)
				var vale := Color(0.42, 0.56, 0.28)
				var mtn := Color(0.45, 0.5, 0.42) if h < 290.0 else Color(0.92, 0.93, 0.95)
				var des := Color(0.78, 0.55, 0.34)
				var coast := Color(0.55, 0.62, 0.38) if h > 5.0 else Color(0.86, 0.8, 0.62)
				col = vale * rw.r + mtn * rw.g + des * rw.b + coast * rw.a
				col.a = 1.0
			var c2 := Color(col.r * shade, col.g * shade, col.b * shade, 1.0)
			img.set_pixel(i, j, c2)
	# Water: river ribbon + lakes.
	_draw_river(img, gen, scale)
	for li in WorldLayout.LAKES.size():
		var lk: Dictionary = WorldLayout.LAKES[li]
		var level := gen.lake_level(li)
		var c := Vector2(lk["pos"][0], lk["pos"][1])
		var r: float = lk["radius"] * 1.3
		var rp := int(r / scale)
		var cx := int((c.x + half) / scale)
		var cz := int((c.y + half) / scale)
		for jj in range(cz - rp, cz + rp + 1):
			for ii in range(cx - rp, cx + rp + 1):
				if ii < 0 or jj < 0 or ii >= size or jj >= size:
					continue
				var wx := -half + (ii + 0.5) * scale
				var wz := -half + (jj + 0.5) * scale
				if gen.sample_height(wx, wz) < level:
					img.set_pixel(ii, jj, Color(0.2, 0.45, 0.62))
	# Roads (dirt first, paved on top) only in the debug view: the minimap and world map draw vector roads on top of
	# this image, and raster copies would show as a pixelated "ghost" band beside them.
	for pass_i in (2 if debug else 0):
		for r: Dictionary in gen.roads:
			var cls: int = r["class"]
			var paved := cls <= 3
			if (pass_i == 0) == paved:
				continue
			var col: Color = ROAD_COLORS.get(cls, Color.WHITE)
			var w := maxf(float(r["width"]) / scale * (1.6 if size <= 1024 else 1.2), 1.5)
			var pos: PackedVector3Array = r["pos"]
			var flags: PackedByteArray = r["flags"]
			for k in pos.size():
				var p := pos[k]
				var c3 := col
				if debug and (flags[k] & 1):
					c3 = Color(1.0, 0.3, 0.9)
				elif debug and (flags[k] & 2):
					c3 = Color(0.1, 0.1, 0.1)
				_disc(img, (p.x + half) / scale, (p.z + half) / scale, w * 0.5, c3)
	return img


static func _draw_river(img: Image, gen: WorldGen, scale: float) -> void:
	var half := WorldLayout.HALF
	# The generator's smoothed river line (the one the carve and the water ribbon use).
	var pts := gen._river_pts
	for i in pts.size() - 1:
		var a := pts[i]
		var b := pts[i + 1]
		var steps := int(a.distance_to(b) / (scale * 0.5)) + 1
		for s in steps:
			var p := a.lerp(b, float(s) / steps)
			_disc(img, (p.x + half) / scale, (p.y + half) / scale, maxf(9.0 / scale, 1.0), Color(0.2, 0.45, 0.62))


static func _disc(img: Image, cx: float, cy: float, r: float, col: Color) -> void:
	var size := img.get_width()
	var ri := int(ceil(r))
	for y in range(int(cy) - ri, int(cy) + ri + 1):
		if y < 0 or y >= size:
			continue
		for x in range(int(cx) - ri, int(cx) + ri + 1):
			if x < 0 or x >= size:
				continue
			if (x + 0.5 - cx) * (x + 0.5 - cx) + (y + 0.5 - cy) * (y + 0.5 - cy) <= r * r:
				img.set_pixel(x, y, col)
