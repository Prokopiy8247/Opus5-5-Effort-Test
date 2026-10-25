extends RefCounted
## Low-poly triangle-soup builder for the procedural placeholder props.
## Colours are authored in sRGB and stored linear; COLOR.a is a material code read by the shaders
## (foliage.gdshader: foliage mask, building_props.gdshader: surface kind). UV.x is a wave weight
## (cloth / flags) used by building_props.gdshader. Face orientation is fixed automatically from an
## "outward" hint, so primitives never need hand-ordered winding.

# Surface codes for building_props.gdshader (stored in COLOR.a).
const NIGHT_LIGHT := 0.0
const LIGHT := 0.12
const PAINT := 0.25
const GLASS := 0.5
const METAL := 0.75
const TINT := 0.9
const MATTE := 1.0

var verts := PackedVector3Array()
var norms := PackedVector3Array()
var cols := PackedColorArray()
var uvs := PackedVector2Array()
## Wave weight written to UV.x for the following triangles. With wave_len > 0 the weight varies per
## vertex along local X from wave_x0 (0 at the attachment) - linearly, or as a sine for cloth held at both ends.
var wave: float = 0.0
var wave_x0: float = 0.0
var wave_len: float = 0.0
var wave_sine: bool = false


func set_wave(amount: float, x0 := 0.0, length := 0.0, sine := false) -> void:
	wave = amount
	wave_x0 = x0
	wave_len = length
	wave_sine = sine


func _wave_at(p: Vector3) -> Vector2:
	if wave_len <= 0.0:
		return Vector2(wave, 0.0)
	var t := clampf((p.x - wave_x0) / wave_len, 0.0, 1.0)
	return Vector2(wave * (sin(t * PI) if wave_sine else t), 0.0)

static var _ico_cache: Dictionary = {}


static func lin(c: Color) -> Color:
	var l := c.srgb_to_linear()
	l.a = c.a
	return l


static func shade(c: Color, f: float) -> Color:
	return Color(c.r * f, c.g * f, c.b * f, c.a)


func tri_count() -> int:
	return verts.size() / 3


func _emit(a: Vector3, b: Vector3, c: Vector3, na: Vector3, nb: Vector3, nc: Vector3, ca: Color, cb: Color, cc: Color) -> void:
	verts.append(a)
	verts.append(b)
	verts.append(c)
	norms.append(na)
	norms.append(nb)
	norms.append(nc)
	cols.append(lin(ca))
	cols.append(lin(cb))
	cols.append(lin(cc))
	uvs.append(_wave_at(a))
	uvs.append(_wave_at(b))
	uvs.append(_wave_at(c))


## Flat triangle. If `out` is non-zero the winding is fixed so the face points along it.
func tri(a: Vector3, b: Vector3, c: Vector3, col: Color, out := Vector3.ZERO) -> void:
	var n := (c - a).cross(b - a)
	if n.length_squared() < 1e-14:
		return
	if out != Vector3.ZERO and n.dot(out) < 0.0:
		var t := b
		b = c
		c = t
		n = -n
	n = n.normalized()
	_emit(a, b, c, n, n, n, col, col, col)


## Triangle with per-vertex colours (gradients) and an explicit shading normal.
func tri_vc(a: Vector3, b: Vector3, c: Vector3, ca: Color, cb: Color, cc: Color, out: Vector3, normal := Vector3.ZERO) -> void:
	var n := (c - a).cross(b - a)
	if n.length_squared() < 1e-14:
		return
	if n.dot(out) < 0.0:
		var t := b
		b = c
		c = t
		var tc := cb
		cb = cc
		cc = tc
		n = -n
	var sn := normal.normalized() if normal != Vector3.ZERO else n.normalized()
	_emit(a, b, c, sn, sn, sn, ca, cb, cc)


## Triangle with normals blended between the face normal and the direction from `center`
## (soft, rounded lighting for foliage blobs).
func tri_soft(a: Vector3, b: Vector3, c: Vector3, col: Color, center: Vector3, soft: float) -> void:
	var n := (c - a).cross(b - a)
	if n.length_squared() < 1e-14:
		return
	var out := (a + b + c) / 3.0 - center
	if n.dot(out) < 0.0:
		var t := b
		b = c
		c = t
		n = -n
	n = n.normalized()
	_emit(a, b, c, n.lerp((a - center).normalized(), soft).normalized(), n.lerp((b - center).normalized(), soft).normalized(),
		n.lerp((c - center).normalized(), soft).normalized(), col, col, col)


func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color, out: Vector3) -> void:
	tri(a, b, c, col, out)
	tri(a, c, d, col, out)


## Two-sided quad (flags, signs, leaves): front coloured `col`, back `back`.
func quad2(a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color, back: Color, out: Vector3, gap := 0.004) -> void:
	var o := out.normalized() * gap
	quad(a + o, b + o, c + o, d + o, col, out)
	quad(a - o, b - o, c - o, d - o, back, -out)


func box(xf: Transform3D, size: Vector3, col: Color, top_col := Color(0, 0, 0, -1.0), bottom := true) -> void:
	var h := size * 0.5
	var tc := col if top_col.a < -0.5 else top_col
	var c := xf.origin
	var p := func(sx: float, sy: float, sz: float) -> Vector3: return xf * Vector3(sx * h.x, sy * h.y, sz * h.z)
	var p000: Vector3 = p.call(-1, -1, -1)
	var p100: Vector3 = p.call(1, -1, -1)
	var p010: Vector3 = p.call(-1, 1, -1)
	var p110: Vector3 = p.call(1, 1, -1)
	var p001: Vector3 = p.call(-1, -1, 1)
	var p101: Vector3 = p.call(1, -1, 1)
	var p011: Vector3 = p.call(-1, 1, 1)
	var p111: Vector3 = p.call(1, 1, 1)
	quad(p010, p110, p111, p011, tc, xf.basis.y)
	if bottom:
		quad(p000, p100, p101, p001, col, -xf.basis.y)
	quad(p000, p100, p110, p010, col, (p000 + p110) * 0.5 - c)
	quad(p001, p101, p111, p011, col, (p001 + p111) * 0.5 - c)
	quad(p000, p001, p011, p010, col, (p000 + p011) * 0.5 - c)
	quad(p100, p101, p111, p110, col, (p100 + p111) * 0.5 - c)


## Axis-aligned (optionally yawed) box given by its base centre.
func block(base: Vector3, size: Vector3, col: Color, yaw := 0.0, top_col := Color(0, 0, 0, -1.0)) -> void:
	box(Transform3D(Basis(Vector3.UP, yaw), base + Vector3(0, size.y * 0.5, 0)), size, col, top_col)


## Box spanning two points (beams, rails, braces), with a square cross-section `thick`.
func beam(a: Vector3, b: Vector3, thick: float, col: Color, up_hint := Vector3.UP) -> void:
	var d := b - a
	var l := d.length()
	if l < 0.0001:
		return
	var y := d / l
	var x := y.cross(up_hint)
	if x.length_squared() < 1e-6:
		x = y.cross(Vector3.RIGHT)
	x = x.normalized()
	var z := x.cross(y).normalized()
	box(Transform3D(Basis(x, y, z), (a + b) * 0.5), Vector3(thick, l, thick), col)


## Tapered cylinder / cone along the local +Y axis of `xf` (from y=0 to y=h).
func cyl(xf: Transform3D, r0: float, r1: float, h: float, segs: int, col: Color, cap_top := true, cap_bottom := false,
		top_col := Color(0, 0, 0, -1.0), rot := 0.0, jitter := 0.0, rng: RandomNumberGenerator = null) -> void:
	var tc := col if top_col.a < -0.5 else top_col
	var top := xf * Vector3(0, h, 0)
	var ring0: Array[Vector3] = []
	var ring1: Array[Vector3] = []
	for i in segs:
		var a := TAU * float(i) / segs + rot
		var j0 := 1.0
		var j1 := 1.0
		if rng != null and jitter > 0.0:
			j0 = 1.0 + rng.randf_range(-jitter, jitter)
			j1 = 1.0 + rng.randf_range(-jitter, jitter)
		ring0.append(xf * Vector3(cos(a) * r0 * j0, 0.0, sin(a) * r0 * j0))
		ring1.append(xf * Vector3(cos(a) * r1 * j1, h, sin(a) * r1 * j1))
	for i in segs:
		var k := (i + 1) % segs
		var am := TAU * (float(i) + 0.5) / segs + rot
		var out := xf.basis * Vector3(cos(am), 0.0, sin(am))
		if r1 > 0.0001:
			quad(ring0[i], ring0[k], ring1[k], ring1[i], col, out)
			if cap_top:
				tri(top, ring1[i], ring1[k], tc, xf.basis.y)
		else:
			tri(ring0[i], ring0[k], top, col, out + xf.basis.y * 0.1)
		if cap_bottom and r0 > 0.0001:
			tri(xf.origin, ring0[i], ring0[k], tc, -xf.basis.y)


## Cylinder between two points.
func cyl_between(a: Vector3, b: Vector3, r0: float, r1: float, segs: int, col: Color, caps := true) -> void:
	var d := b - a
	var l := d.length()
	if l < 0.0001:
		return
	var y := d / l
	var x := y.cross(Vector3.UP)
	if x.length_squared() < 1e-6:
		x = y.cross(Vector3.RIGHT)
	x = x.normalized()
	var z := x.cross(y).normalized()
	cyl(Transform3D(Basis(x, y, z), a), r0, r1, l, segs, col, caps, caps)


static func _ico(subdiv: int) -> Array:
	if _ico_cache.has(subdiv):
		return _ico_cache[subdiv]
	var t := (1.0 + sqrt(5.0)) * 0.5
	var v: Array[Vector3] = [
		Vector3(-1, t, 0), Vector3(1, t, 0), Vector3(-1, -t, 0), Vector3(1, -t, 0),
		Vector3(0, -1, t), Vector3(0, 1, t), Vector3(0, -1, -t), Vector3(0, 1, -t),
		Vector3(t, 0, -1), Vector3(t, 0, 1), Vector3(-t, 0, -1), Vector3(-t, 0, 1)]
	for i in v.size():
		v[i] = v[i].normalized()
	var f := PackedInt32Array([0, 11, 5, 0, 5, 1, 0, 1, 7, 0, 7, 10, 0, 10, 11, 1, 5, 9, 5, 11, 4, 11, 10, 2, 10, 7, 6, 7, 1, 8,
		3, 9, 4, 3, 4, 2, 3, 2, 6, 3, 6, 8, 3, 8, 9, 4, 9, 5, 2, 4, 11, 6, 2, 10, 8, 6, 7, 9, 8, 1])
	for _s in subdiv:
		var mids: Dictionary = {}
		var nf := PackedInt32Array()
		for k in range(0, f.size(), 3):
			var idx: Array[int] = [f[k], f[k + 1], f[k + 2]]
			var m: Array[int] = []
			for e in 3:
				var a := idx[e]
				var b := idx[(e + 1) % 3]
				var key := Vector2i(mini(a, b), maxi(a, b))
				if not mids.has(key):
					mids[key] = v.size()
					v.append(((v[a] + v[b]) * 0.5).normalized())
				m.append(mids[key])
			nf.append_array([idx[0], m[0], m[2], idx[1], m[1], m[0], idx[2], m[2], m[1], m[0], m[1], m[2]])
		f = nf
	var pv := PackedVector3Array(v)
	var res := [pv, f]
	_ico_cache[subdiv] = res
	return res


## Displaced icosphere ("blob"): foliage clumps and rocks. Faces darken toward the bottom (fake AO)
## and vary slightly in brightness for a hand-painted low-poly look.
func blob(center: Vector3, radii: Vector3, col: Color, rng: RandomNumberGenerator, jitter := 0.15, subdiv := 1,
		soft := 0.55, ao := 0.3, flat_below := -2.0, basis := Basis()) -> void:
	var ico := _ico(subdiv)
	var base: PackedVector3Array = ico[0]
	var f: PackedInt32Array = ico[1]
	var pts := PackedVector3Array()
	pts.resize(base.size())
	for i in base.size():
		var v := base[i]
		var k := 1.0 + rng.randf_range(-jitter, jitter)
		var p := Vector3(v.x * radii.x, v.y * radii.y, v.z * radii.z) * k
		if p.y < flat_below * radii.y:
			p.y = flat_below * radii.y
		pts[i] = center + basis * p
	for k in range(0, f.size(), 3):
		var a := pts[f[k]]
		var b := pts[f[k + 1]]
		var c := pts[f[k + 2]]
		var cen := (a + b + c) / 3.0
		var yf := clampf((cen.y - center.y) / maxf(radii.y, 0.001) * 0.5 + 0.5, 0.0, 1.0)
		var fcol := shade(col, lerpf(1.0 - ao, 1.0 + ao * 0.35, yf) * (1.0 + rng.randf_range(-0.05, 0.05)))
		if soft > 0.0:
			tri_soft(a, b, c, fcol, center, soft)
		else:
			tri(a, b, c, fcol, cen - center)


## Gable roof over a w x d rectangle at height y0, ridge along local X (or Z if ridge_z), with overhang.
func gable_roof(xf: Transform3D, w: float, d: float, y0: float, rh: float, over: float, roof_col: Color, gable_col: Color, ridge_z := false) -> void:
	var hw := w * 0.5
	var hd := d * 0.5
	if ridge_z:
		var b2 := Basis(Vector3.UP, PI * 0.5)
		xf = Transform3D(xf.basis * b2, xf.origin)
		var t := hw
		hw = hd
		hd = t
	var ox := hw + over
	var oz := hd + over
	var drop := over * rh / maxf(hd, 0.01)
	var e0 := xf * Vector3(-ox, y0 - drop, -oz)
	var e1 := xf * Vector3(ox, y0 - drop, -oz)
	var r0 := xf * Vector3(-ox, y0 + rh, 0)
	var r1 := xf * Vector3(ox, y0 + rh, 0)
	var e2 := xf * Vector3(-ox, y0 - drop, oz)
	var e3 := xf * Vector3(ox, y0 - drop, oz)
	var up := xf.basis.y
	var fz := xf.basis.z
	var under := shade(roof_col, 0.45)
	var th := up * 0.18
	quad(e0 + th, e1 + th, r1 + th, r0 + th, roof_col, up - fz)
	quad(e2 + th, e3 + th, r1 + th, r0 + th, roof_col, up + fz)
	quad(e0, e1, r1, r0, under, -up + fz)
	quad(e2, e3, r1, r0, under, -up - fz)
	# fascia boards along the eaves
	quad(e0, e1, e1 + th, e0 + th, under, -fz)
	quad(e2, e3, e3 + th, e2 + th, under, fz)
	var fx := xf.basis.x
	for s: float in [-1.0, 1.0]:
		var a := xf * Vector3(s * hw, y0, -hd)
		var b := xf * Vector3(s * hw, y0, hd)
		var c := xf * Vector3(s * hw, y0 + rh * (1.0 - 0.0), 0)
		tri(a, b, c, gable_col, fx * s)
		# verge (roof edge) undersides
		quad(xf * Vector3(s * ox, y0 - drop, -oz), xf * Vector3(s * ox, y0 + rh, 0), xf * Vector3(s * ox, y0 + rh, 0) + th, xf * Vector3(s * ox, y0 - drop, -oz) + th, under, fx * s)
		quad(xf * Vector3(s * ox, y0 - drop, oz), xf * Vector3(s * ox, y0 + rh, 0), xf * Vector3(s * ox, y0 + rh, 0) + th, xf * Vector3(s * ox, y0 - drop, oz) + th, under, fx * s)


## Window: glass pane with a frame, on a wall plane facing `n` (unit, horizontal).
## Each pane gets a unique tiny colour offset so the shader can light windows individually at night.
func window(center: Vector3, n: Vector3, w: float, h: float, frame_col: Color, rng: RandomNumberGenerator, glass := Color(0.16, 0.22, 0.28)) -> void:
	var right := Vector3.UP.cross(n).normalized()
	var up := Vector3.UP
	var c := center + n * 0.04
	var hw := w * 0.5
	var hh := h * 0.5
	var fw := 0.1
	quad(c - right * (hw + fw) - up * (hh + fw), c + right * (hw + fw) - up * (hh + fw), c + right * (hw + fw) + up * (hh + fw), c - right * (hw + fw) + up * (hh + fw), frame_col, n)
	var g := center + n * 0.07
	var gc := Color(glass.r + rng.randf() * 0.06, glass.g + rng.randf() * 0.06, glass.b + rng.randf() * 0.06, GLASS)
	quad(g - right * hw - up * hh, g + right * hw - up * hh, g + right * hw + up * hh, g - right * hw + up * hh, gc, n)
	# mullion cross
	var m := center + n * 0.09
	quad(m - right * 0.03 - up * hh, m + right * 0.03 - up * hh, m + right * 0.03 + up * hh, m - right * 0.03 + up * hh, frame_col, n)
	quad(m - right * hw - up * 0.03, m + right * hw - up * 0.03, m + right * hw + up * 0.03, m - right * hw + up * 0.03, frame_col, n)
	# sill
	box(Transform3D(Basis(right, up, n), center - up * (hh + fw + 0.04) + n * 0.1), Vector3(w + 0.35, 0.08, 0.2), frame_col)


## Flat panel on a wall (doors, signs). `n` = facing direction.
func panel(center: Vector3, n: Vector3, w: float, h: float, col: Color, depth := 0.05) -> void:
	var right := Vector3.UP.cross(n).normalized()
	var up := n.cross(right).normalized()
	box(Transform3D(Basis(right, up, n), center + n * depth * 0.5), Vector3(w, h, depth), col)


func append(other: RefCounted, xf := Transform3D.IDENTITY) -> void:
	var ov: PackedVector3Array = other.verts
	var on: PackedVector3Array = other.norms
	for i in ov.size():
		verts.append(xf * ov[i])
		norms.append((xf.basis * on[i]).normalized())
	cols.append_array(other.cols)
	uvs.append_array(other.uvs)


func to_mesh(mat: Material, mesh_name: String) -> ArrayMesh:
	var am := ArrayMesh.new()
	am.resource_name = mesh_name
	if verts.is_empty():
		return am
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	am.surface_set_material(0, mat)
	return am
