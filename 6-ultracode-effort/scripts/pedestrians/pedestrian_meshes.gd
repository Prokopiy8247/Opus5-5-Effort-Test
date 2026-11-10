extends RefCounted
## Procedural low-poly people and a bicycle (no external assets). One ArrayMesh per look: flat vertex colours,
## UV.x = limb id for the vertex-shader animation (assets/shaders/pedestrian.gdshader). Unit person ~1.75 m,
## origin between the feet, facing -Z; height and build come from the instance transform.

const SHADER := preload("res://assets/shaders/pedestrian.gdshader")

const SKINS: Array[Color] = [Color(0.93, 0.76, 0.64), Color(0.84, 0.64, 0.48), Color(0.66, 0.46, 0.32), Color(0.42, 0.28, 0.2), Color(0.97, 0.82, 0.7)]

## h height scale, g girth, skin, hair colour, hair style (0 bald 1 short 2 long 3 ponytail 4 bun), top, sleeve (0 short 1 long 2 none),
## bottom, bottom type (0 long 1 shorts 2 skirt), shoes, hat (0 none 1 cap 2 beanie 3 wide), hat colour, bag (0 none 1 backpack 2 shoulder 3 hand), bag colour
static var VARIANTS: Array[Dictionary] = _make_variants()


static func _v(h: float, g: float, skin: int, hair: Color, hs: int, top: Color, sl: int, bot: Color, bt: int, shoe: Color, hat: int, hat_c: Color, bag: int, bag_c: Color) -> Dictionary:
	return {"h": h, "g": g, "skin": SKINS[skin], "hair": hair, "hs": hs, "top": top, "sl": sl, "bot": bot, "bt": bt, "shoe": shoe, "hat": hat, "hat_c": hat_c, "bag": bag, "bag_c": bag_c}


static func _make_variants() -> Array[Dictionary]:
	var none := Color(0, 0, 0)
	var out: Array[Dictionary] = []
	out.append(_v(1.0, 1.0, 0, Color(0.35, 0.22, 0.12), 1, Color(0.2, 0.4, 0.75), 0, Color(0.18, 0.2, 0.3), 0, Color(0.9, 0.9, 0.9), 0, none, 0, none))
	out.append(_v(0.94, 0.9, 1, Color(0.08, 0.06, 0.05), 2, Color(0.85, 0.25, 0.3), 1, Color(0.12, 0.12, 0.14), 0, Color(0.15, 0.15, 0.15), 0, none, 3, Color(0.9, 0.8, 0.3)))
	out.append(_v(1.08, 1.12, 2, Color(0.1, 0.08, 0.06), 1, Color(0.95, 0.85, 0.2), 0, Color(0.45, 0.35, 0.22), 1, Color(0.3, 0.2, 0.12), 1, Color(0.15, 0.3, 0.55), 1, Color(0.15, 0.4, 0.3)))
	out.append(_v(0.9, 0.85, 3, Color(0.05, 0.04, 0.04), 4, Color(0.2, 0.65, 0.5), 2, Color(0.9, 0.85, 0.75), 2, Color(0.85, 0.3, 0.35), 0, none, 2, Color(0.55, 0.2, 0.25)))
	out.append(_v(1.12, 1.0, 0, Color(0.7, 0.55, 0.25), 1, Color(0.25, 0.25, 0.28), 1, Color(0.2, 0.28, 0.4), 0, Color(0.1, 0.1, 0.1), 2, Color(0.75, 0.2, 0.15), 0, none))
	out.append(_v(0.78, 0.75, 1, Color(0.2, 0.12, 0.08), 3, Color(0.95, 0.5, 0.65), 0, Color(0.3, 0.35, 0.7), 1, Color(0.9, 0.9, 0.95), 0, none, 1, Color(0.9, 0.35, 0.5)))
	out.append(_v(1.04, 1.25, 4, Color(0.55, 0.52, 0.5), 0, Color(0.5, 0.35, 0.2), 1, Color(0.25, 0.25, 0.22), 0, Color(0.2, 0.15, 0.1), 3, Color(0.78, 0.7, 0.5), 0, none))
	out.append(_v(0.97, 0.88, 2, Color(0.08, 0.06, 0.05), 2, Color(0.95, 0.95, 0.9), 0, Color(0.15, 0.4, 0.55), 2, Color(0.7, 0.55, 0.35), 3, Color(0.9, 0.85, 0.6), 2, Color(0.2, 0.2, 0.25)))
	out.append(_v(1.06, 1.08, 3, Color(0.04, 0.04, 0.04), 1, Color(0.9, 0.45, 0.1), 0, Color(0.12, 0.12, 0.12), 1, Color(0.9, 0.9, 0.9), 1, Color(0.1, 0.1, 0.1), 1, Color(0.2, 0.2, 0.22)))
	out.append(_v(0.92, 0.95, 0, Color(0.85, 0.75, 0.45), 3, Color(0.35, 0.55, 0.3), 1, Color(0.35, 0.3, 0.5), 0, Color(0.6, 0.6, 0.6), 0, none, 3, Color(0.85, 0.85, 0.8)))
	out.append(_v(1.15, 1.15, 1, Color(0.1, 0.07, 0.05), 1, Color(0.15, 0.15, 0.17), 1, Color(0.15, 0.15, 0.17), 0, Color(0.9, 0.2, 0.2), 2, Color(0.2, 0.2, 0.2), 1, Color(0.7, 0.15, 0.15)))
	out.append(_v(0.85, 0.8, 4, Color(0.9, 0.9, 0.9), 4, Color(0.65, 0.4, 0.55), 1, Color(0.35, 0.35, 0.4), 0, Color(0.25, 0.2, 0.2), 0, none, 3, Color(0.4, 0.25, 0.2)))
	out.append(_v(1.0, 1.05, 2, Color(0.3, 0.2, 0.1), 1, Color(0.9, 0.9, 0.9), 0, Color(0.2, 0.45, 0.7), 1, Color(0.8, 0.8, 0.2), 1, Color(0.9, 0.3, 0.1), 0, none))
	out.append(_v(1.1, 0.95, 3, Color(0.04, 0.04, 0.04), 0, Color(0.15, 0.55, 0.85), 2, Color(0.9, 0.7, 0.1), 1, Color(0.1, 0.1, 0.1), 0, none, 0, none))
	out.append(_v(0.74, 0.78, 0, Color(0.9, 0.7, 0.25), 3, Color(0.9, 0.2, 0.25), 0, Color(0.25, 0.3, 0.6), 0, Color(0.9, 0.9, 0.2), 2, Color(0.2, 0.7, 0.35), 1, Color(0.2, 0.55, 0.9)))
	out.append(_v(1.02, 0.92, 1, Color(0.15, 0.1, 0.06), 2, Color(0.4, 0.15, 0.45), 1, Color(0.1, 0.1, 0.12), 0, Color(0.3, 0.3, 0.35), 3, Color(0.2, 0.15, 0.25), 2, Color(0.8, 0.7, 0.2)))
	out.append(_v(1.07, 1.18, 2, Color(0.25, 0.15, 0.08), 1, Color(0.3, 0.45, 0.25), 0, Color(0.55, 0.5, 0.35), 1, Color(0.35, 0.3, 0.2), 1, Color(0.3, 0.45, 0.25), 0, none))
	out.append(_v(0.96, 0.87, 4, Color(0.25, 0.2, 0.18), 4, Color(0.95, 0.75, 0.2), 1, Color(0.2, 0.2, 0.25), 2, Color(0.15, 0.15, 0.15), 0, none, 3, Color(0.3, 0.3, 0.7)))
	return out


class MB:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var c := PackedColorArray()
	var u := PackedVector2Array()
	var col := Color.WHITE
	var limb := 0.0

	func tri(a: Vector3, b: Vector3, d: Vector3, ref: Vector3) -> void:
		var nn := (b - a).cross(d - a)
		if nn.length() < 1e-9:
			return
		nn = nn.normalized()
		if nn.dot((a + b + d) / 3.0 - ref) < 0.0:
			nn = -nn
			var t := b
			b = d
			d = t
		for p: Vector3 in [a, d, b]:
			v.append(p)
			n.append(nn)
			c.append(col)
			u.append(Vector2(limb, 0.0))

	func quad(a: Vector3, b: Vector3, d: Vector3, e: Vector3, ref: Vector3) -> void:
		tri(a, b, d, ref)
		tri(a, d, e, ref)

	func box(ctr: Vector3, size: Vector3, taper := 1.0) -> void:
		var hx := size.x * 0.5
		var hz := size.z * 0.5
		var hy := size.y * 0.5
		var bt: Array[Vector3] = []
		var tp: Array[Vector3] = []
		for k: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
			bt.append(ctr + Vector3(k.x * hx, -hy, k.y * hz))
			tp.append(ctr + Vector3(k.x * hx * taper, hy, k.y * hz * taper))
		quad(bt[0], bt[1], bt[2], bt[3], ctr)
		quad(tp[0], tp[1], tp[2], tp[3], ctr)
		for i in 4:
			var j := (i + 1) % 4
			quad(bt[i], bt[j], tp[j], tp[i], ctr)

	func prism(ctr: Vector3, r_top: float, r_bot: float, h: float, sides := 6, sx := 1.0, sz := 1.0) -> void:
		var top: Array[Vector3] = []
		var bot: Array[Vector3] = []
		for i in sides:
			var a := TAU * float(i) / float(sides)
			top.append(ctr + Vector3(cos(a) * r_top * sx, h * 0.5, sin(a) * r_top * sz))
			bot.append(ctr + Vector3(cos(a) * r_bot * sx, -h * 0.5, sin(a) * r_bot * sz))
		for i in sides:
			var j := (i + 1) % sides
			quad(bot[i], bot[j], top[j], top[i], ctr)
			tri(ctr + Vector3(0, h * 0.5, 0), top[i], top[j], ctr)
			tri(ctr + Vector3(0, -h * 0.5, 0), bot[i], bot[j], ctr)

	func seg(x: float, y_top: float, y_bot: float, r_top: float, r_bot: float, z := 0.0) -> void:
		prism(Vector3(x, (y_top + y_bot) * 0.5, z), r_top, r_bot, y_top - y_bot, 6)

	func sphere(ctr: Vector3, r: float, sy := 1.0) -> void:
		var rings := 4
		var segs := 7
		for i in rings:
			var a0 := PI * float(i) / float(rings)
			var a1 := PI * float(i + 1) / float(rings)
			for j in segs:
				var b0 := TAU * float(j) / float(segs)
				var b1 := TAU * float(j + 1) / float(segs)
				var p00 := ctr + Vector3(sin(a0) * cos(b0) * r, cos(a0) * r * sy, sin(a0) * sin(b0) * r)
				var p01 := ctr + Vector3(sin(a0) * cos(b1) * r, cos(a0) * r * sy, sin(a0) * sin(b1) * r)
				var p10 := ctr + Vector3(sin(a1) * cos(b0) * r, cos(a1) * r * sy, sin(a1) * sin(b0) * r)
				var p11 := ctr + Vector3(sin(a1) * cos(b1) * r, cos(a1) * r * sy, sin(a1) * sin(b1) * r)
				tri(p00, p10, p11, ctr)
				tri(p00, p11, p01, ctr)

	func bar(a: Vector3, b: Vector3, r: float) -> void:
		var d := (b - a).normalized()
		var side := d.cross(Vector3.UP)
		if side.length() < 0.1:
			side = d.cross(Vector3.RIGHT)
		side = side.normalized() * r
		var up := d.cross(side).normalized() * r
		var ctr := (a + b) * 0.5
		var pa: Array[Vector3] = [a + side + up, a - side + up, a - side - up, a + side - up]
		var pb: Array[Vector3] = [b + side + up, b - side + up, b - side - up, b + side - up]
		quad(pa[0], pa[1], pa[2], pa[3], ctr)
		quad(pb[0], pb[1], pb[2], pb[3], ctr)
		for i in 4:
			var j := (i + 1) % 4
			quad(pa[i], pa[j], pb[j], pb[i], ctr)

	func disc_x(ctr: Vector3, radius: float, thick: float, sides := 14) -> void:
		var l: Array[Vector3] = []
		var r: Array[Vector3] = []
		for i in sides:
			var a := TAU * float(i) / float(sides)
			var o := Vector3(0, sin(a) * radius, cos(a) * radius)
			l.append(ctr + o + Vector3(-thick * 0.5, 0, 0))
			r.append(ctr + o + Vector3(thick * 0.5, 0, 0))
		for i in sides:
			var j := (i + 1) % sides
			quad(l[i], l[j], r[j], r[i], ctr)
			tri(ctr + Vector3(-thick * 0.5, 0, 0), l[i], l[j], ctr)
			tri(ctr + Vector3(thick * 0.5, 0, 0), r[i], r[j], ctr)

	func to_mesh() -> ArrayMesh:
		var arr: Array = []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = v
		arr[Mesh.ARRAY_NORMAL] = n
		arr[Mesh.ARRAY_COLOR] = c
		arr[Mesh.ARRAY_TEX_UV] = u
		var m := ArrayMesh.new()
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		return m


static func _lin(c: Color) -> Color:
	return c.srgb_to_linear()


static func build_person(d: Dictionary) -> ArrayMesh:
	var b := MB.new()
	var skin := _lin(d["skin"] as Color)
	var hair := _lin(d["hair"] as Color)
	var top := _lin(d["top"] as Color)
	var bot := _lin(d["bot"] as Color)
	var shoe := _lin(d["shoe"] as Color)
	var bt: int = d["bt"]
	var sl: int = d["sl"]
	for side in 2:
		var x := -0.095 if side == 0 else 0.095
		var thigh_id := 1.0 + float(side)
		var shin_id := 5.0 + float(side)
		var bare := bt != 0
		b.limb = thigh_id
		if bt == 1:
			b.col = bot
			b.seg(x, 0.93, 0.66, 0.088, 0.075)
			b.col = skin
			b.seg(x, 0.66, 0.5, 0.075, 0.062)
		else:
			b.col = skin if bare else bot
			b.seg(x, 0.93, 0.5, 0.088, 0.064)
		b.limb = shin_id
		b.col = skin if bare else bot
		b.seg(x, 0.5, 0.09, 0.062, 0.044)
		b.col = shoe
		b.box(Vector3(x, 0.045, -0.04), Vector3(0.1, 0.09, 0.27))
		var ax := -0.235 if side == 0 else 0.235
		b.limb = 3.0 + float(side)
		if sl == 1:
			b.col = top
			b.seg(ax, 1.43, 1.15, 0.05, 0.042)
		elif sl == 0:
			b.col = top
			b.seg(ax, 1.43, 1.30, 0.052, 0.05)
			b.col = skin
			b.seg(ax, 1.30, 1.15, 0.045, 0.04)
		else:
			b.col = skin
			b.seg(ax, 1.42, 1.15, 0.046, 0.04)
		b.limb = 7.0 + float(side)
		b.col = top if sl == 1 else skin
		b.seg(ax, 1.15, 0.92, 0.04, 0.034)
		b.col = skin
		b.sphere(Vector3(ax, 0.88, 0.0), 0.04)
	b.limb = 0.0
	b.col = bot
	b.box(Vector3(0, 0.945, 0), Vector3(0.31, 0.14, 0.2))
	if bt == 2:
		b.prism(Vector3(0, 0.78, 0), 0.17, 0.27, 0.4, 8)
	b.col = top
	b.box(Vector3(0, 1.22, 0), Vector3(0.31, 0.48, 0.19), 1.3)
	b.col = skin
	b.seg(0, 1.56, 1.46, 0.045, 0.05)
	b.sphere(Vector3(0, 1.645, 0), 0.105, 1.15)
	b.box(Vector3(0, 1.63, -0.108), Vector3(0.035, 0.05, 0.04))
	var hs: int = d["hs"]
	b.col = hair
	if hs >= 1:
		b.sphere(Vector3(0, 1.675, 0.012), 0.114, 0.85)
	if hs == 2:
		b.box(Vector3(0, 1.52, 0.088), Vector3(0.2, 0.36, 0.07))
	elif hs == 3:
		b.box(Vector3(0, 1.57, 0.14), Vector3(0.05, 0.18, 0.05))
	elif hs == 4:
		b.sphere(Vector3(0, 1.78, 0.03), 0.06)
	var hat: int = d["hat"]
	b.col = _lin(d["hat_c"] as Color)
	if hat == 1:
		b.prism(Vector3(0, 1.72, 0.005), 0.113, 0.118, 0.06, 8)
		b.box(Vector3(0, 1.70, -0.13), Vector3(0.17, 0.014, 0.11))
	elif hat == 2:
		b.sphere(Vector3(0, 1.70, 0.005), 0.122, 0.9)
	elif hat == 3:
		b.prism(Vector3(0, 1.725, 0), 0.25, 0.25, 0.014, 10)
		b.prism(Vector3(0, 1.77, 0), 0.1, 0.115, 0.09, 8)
	var bag: int = d["bag"]
	b.col = _lin(d["bag_c"] as Color)
	if bag == 1:
		b.limb = 0.0
		b.box(Vector3(0, 1.25, 0.185), Vector3(0.27, 0.36, 0.15))
	elif bag == 2:
		b.limb = 0.0
		b.box(Vector3(-0.265, 0.97, 0.03), Vector3(0.07, 0.2, 0.24))
		b.bar(Vector3(0.18, 1.45, -0.02), Vector3(-0.27, 1.06, 0.03), 0.012)
	elif bag == 3:
		b.limb = 8.0
		b.box(Vector3(0.235, 0.74, -0.02), Vector3(0.07, 0.22, 0.17))
	return b.to_mesh()


static func build_bike() -> ArrayMesh:
	var b := MB.new()
	var frame := _lin(Color(0.75, 0.15, 0.12))
	var dark := _lin(Color(0.08, 0.08, 0.09))
	var spoke := _lin(Color(0.7, 0.7, 0.72))
	b.limb = 0.0
	b.col = frame
	b.bar(Vector3(0, 0.3, 0.05), Vector3(0, 0.94, -0.4), 0.02)
	b.bar(Vector3(0, 0.86, 0.2), Vector3(0, 0.92, -0.4), 0.017)
	b.bar(Vector3(0, 0.3, 0.05), Vector3(0, 0.88, 0.2), 0.017)
	b.bar(Vector3(0, 0.3, 0.05), Vector3(0, 0.34, 0.48), 0.014)
	b.bar(Vector3(0, 0.84, 0.2), Vector3(0, 0.34, 0.48), 0.014)
	b.bar(Vector3(0, 0.98, -0.4), Vector3(0, 0.34, -0.52), 0.016)
	b.col = dark
	b.bar(Vector3(-0.27, 1.03, -0.42), Vector3(0.27, 1.03, -0.42), 0.014)
	b.bar(Vector3(0, 0.98, -0.4), Vector3(0, 1.03, -0.42), 0.014)
	b.box(Vector3(0, 0.915, 0.22), Vector3(0.1, 0.04, 0.22))
	b.box(Vector3(0.13, 0.3, 0.05), Vector3(0.1, 0.03, 0.06))
	b.box(Vector3(-0.13, 0.3, 0.05), Vector3(0.1, 0.03, 0.06))
	for w in 2:
		b.limb = 1.0 + float(w)
		var c := Vector3(0, 0.34, -0.52 if w == 0 else 0.48)
		b.col = dark
		b.disc_x(c, 0.34, 0.03)
		b.col = spoke
		for k in 3:
			var a := PI * float(k) / 3.0
			var o := Vector3(0, sin(a), cos(a)) * 0.3
			b.bar(c + o, c - o, 0.02)
	return b.to_mesh()


static func make_material(is_bike := false) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = SHADER
	m.set_shader_parameter("is_bike", is_bike)
	return m
