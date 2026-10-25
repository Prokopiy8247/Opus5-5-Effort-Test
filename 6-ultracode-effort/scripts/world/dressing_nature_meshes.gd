extends RefCounted
## Procedural low-poly stand-ins for the nature kit (trees, bushes, rocks, grass, reeds, hay) and the
## far-distance tree families. Used by prop_library.gd only when the Blender kit is missing.
## Origins sit at the base centre; trunks extend ~1 m below ground so slopes never show a gap.

const MB := preload("res://scripts/world/dressing_mesh_builder.gd")

enum Far { NONE = -1, CONIFER, BROADLEAF, PALM, HEDGE }

## Per-species data used by the dressing rules (also for kit meshes): far family (NONE = no far stand-in),
## trunk radius for colliders (0 = none), foliage colour (sRGB) of the placeholder far tint, and far_k: the
## share of the mesh's silhouette area the far stand-in keeps, so a stand-in weighs as much as the model does
## at the ~600 m cross-fade, where the model's thin branches, fronds and sparse crowns fade under TAA
## (measured with the Blender kit by tools/tests/dressing_far_lod_test.gd; re-measure after re-exporting it).
const SPECIES := {
	"Tree_Oak_A": {"far": Far.BROADLEAF, "trunk": 0.38, "leaf": Color(0.30, 0.46, 0.17), "far_k": 0.9},
	"Tree_Oak_B": {"far": Far.BROADLEAF, "trunk": 0.34, "leaf": Color(0.42, 0.53, 0.2), "far_k": 0.94},
	"Tree_Pine_A": {"far": Far.CONIFER, "trunk": 0.28, "leaf": Color(0.15, 0.32, 0.18), "far_k": 0.82},
	"Tree_Pine_B": {"far": Far.CONIFER, "trunk": 0.26, "leaf": Color(0.13, 0.27, 0.2), "far_k": 0.87},
	"Tree_Poplar": {"far": Far.BROADLEAF, "trunk": 0.26, "leaf": Color(0.38, 0.53, 0.21), "far_k": 0.88},
	"Tree_Birch": {"far": Far.BROADLEAF, "trunk": 0.17, "leaf": Color(0.53, 0.64, 0.26), "far_k": 0.76},
	"Tree_Palm": {"far": Far.PALM, "trunk": 0.26, "leaf": Color(0.33, 0.53, 0.2), "far_k": 0.71},
	"Tree_Olive": {"far": Far.BROADLEAF, "trunk": 0.3, "leaf": Color(0.5, 0.57, 0.39), "far_k": 0.73},
	"Tree_Dead": {"far": Far.NONE, "trunk": 0.28, "leaf": Color(0.45, 0.4, 0.34)},
	"Hedge": {"far": Far.HEDGE, "trunk": 0.0, "leaf": Color(0.22, 0.38, 0.15), "far_k": 0.84},
}

const FOLIAGE := ["Tree_Oak_A", "Tree_Oak_B", "Tree_Pine_A", "Tree_Pine_B", "Tree_Poplar", "Tree_Birch", "Tree_Palm",
	"Tree_Olive", "Tree_Dead", "Bush_A", "Bush_B", "Bush_Desert", "Hedge", "Flowers_Tuft", "Reeds"]
const SOLID := ["Cactus_A", "Cactus_B", "Rock_A", "Rock_B", "Rock_C", "Rock_Large", "Rock_Red", "Hay_Bale", "Log_Pile"]

const BARK := Color(0.37, 0.28, 0.2, 0.0)
const BARK_DARK := Color(0.27, 0.21, 0.16, 0.0)


static func handles(name: String) -> bool:
	return name in FOLIAGE or name in SOLID or name == "Grass_Tuft"


## "foliage", "grass" or "solid" (building_props shader).
static func material_kind(name: String) -> String:
	if name == "Grass_Tuft":
		return "grass"
	return "foliage" if name in FOLIAGE else "solid"


static func _rng(name: String) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = hash(name) & 0x7fffffff
	return r


static func make(name: String) -> MB:
	var b := MB.new()
	var r := _rng(name)
	match name:
		"Tree_Oak_A":
			_broadleaf(b, r, 3.6, 0.42, Color(0.3, 0.46, 0.17, 1.0), Vector3(2.7, 2.1, 2.7), 6.4, 6, 1.0)
		"Tree_Oak_B":
			_broadleaf(b, r, 2.6, 0.38, Color(0.42, 0.53, 0.2, 1.0), Vector3(3.0, 1.6, 3.0), 5.0, 5, 0.85)
		"Tree_Pine_A":
			_conifer(b, r, 5, 2.9, 0.42, 3.3, 2.0, Color(0.15, 0.32, 0.18, 1.0))
		"Tree_Pine_B":
			_conifer(b, r, 7, 2.4, 0.27, 3.0, 2.05, Color(0.13, 0.27, 0.2, 1.0))
		"Tree_Poplar":
			_poplar(b, r)
		"Tree_Birch":
			_birch(b, r)
		"Tree_Palm":
			_palm(b, r)
		"Tree_Olive":
			_olive(b, r)
		"Tree_Dead":
			_dead(b, r)
		"Bush_A":
			_bush(b, r, Color(0.24, 0.41, 0.16, 1.0), 4, 0.95, Color(0, 0, 0, 0))
		"Bush_B":
			_bush(b, r, Color(0.3, 0.47, 0.19, 1.0), 4, 0.85, Color(0.96, 0.62, 0.78, 1.0))
		"Bush_Desert":
			_desert_bush(b, r)
		"Hedge":
			_hedge(b, r)
		"Cactus_A":
			_saguaro(b, r)
		"Cactus_B":
			_prickly_pear(b, r)
		"Rock_A":
			b.blob(Vector3(0, 0.3, 0), Vector3(0.95, 0.65, 0.85), Color(0.56, 0.54, 0.5, MB.MATTE), r, 0.24, 1, 0.0, 0.25, -0.6)
		"Rock_B":
			b.blob(Vector3(0, 0.3, 0), Vector3(1.35, 0.7, 0.8), Color(0.5, 0.49, 0.46, MB.MATTE), r, 0.26, 1, 0.0, 0.25, -0.6)
		"Rock_C":
			b.blob(Vector3(0, 0.12, 0), Vector3(1.1, 0.38, 1.0), Color(0.6, 0.58, 0.54, MB.MATTE), r, 0.22, 1, 0.0, 0.2, -0.5)
		"Rock_Large":
			b.blob(Vector3(0, 1.4, 0), Vector3(3.4, 2.5, 3.0), Color(0.53, 0.52, 0.49, MB.MATTE), r, 0.22, 1, 0.0, 0.3, -0.7)
			b.blob(Vector3(1.9, 0.9, 1.2), Vector3(2.0, 1.6, 1.9), Color(0.5, 0.49, 0.46, MB.MATTE), r, 0.25, 1, 0.0, 0.3, -0.7)
			b.blob(Vector3(-1.6, 0.6, -1.5), Vector3(1.4, 1.0, 1.3), Color(0.57, 0.55, 0.51, MB.MATTE), r, 0.25, 0, 0.0, 0.3, -0.7)
		"Rock_Red":
			_red_rock(b, r)
		"Grass_Tuft":
			_grass(b, r)
		"Flowers_Tuft":
			_flowers(b, r)
		"Reeds":
			_reeds(b, r)
		"Hay_Bale":
			_hay(b, r)
		"Log_Pile":
			_logs(b, r)
		_:
			return null
	return b


# ------------------------------------------------------------------ trees

static func _trunk(b: MB, r: RandomNumberGenerator, h: float, r0: float, r1: float, segs: int, col := BARK) -> void:
	b.cyl(Transform3D(Basis(), Vector3(0, -1.0, 0)), r0 * 1.25, r0, 1.4, segs, col, false, false)
	b.cyl(Transform3D(Basis(), Vector3(0, 0.4, 0)), r0, r1, h - 0.4, segs, col, true, false, col, 0.0, 0.06, r)


static func _broadleaf(b: MB, r: RandomNumberGenerator, trunk_h: float, tr: float, leaf: Color, main: Vector3, cy: float, clumps: int, spread: float) -> void:
	_trunk(b, r, trunk_h + 1.2, tr, tr * 0.55, 7)
	# limbs reaching into the canopy
	for i in 3:
		var a := TAU * i / 3.0 + r.randf() * 0.8
		var tip := Vector3(cos(a) * main.x * 0.55, cy - 0.6, sin(a) * main.z * 0.55)
		b.cyl_between(Vector3(0, trunk_h * 0.8, 0), tip, tr * 0.45, tr * 0.2, 5, BARK)
	b.blob(Vector3(0, cy, 0), main, leaf, r, 0.14, 1, 0.6, 0.32)
	for i in clumps:
		var a := TAU * i / clumps + r.randf() * 0.5
		var d := main.x * r.randf_range(0.55, 0.75) * spread
		var c := Vector3(cos(a) * d, cy + r.randf_range(-0.9, 0.6), sin(a) * d)
		var rad := main.x * r.randf_range(0.48, 0.62)
		var lc := MB.shade(leaf, r.randf_range(0.9, 1.08))
		b.blob(c, Vector3(rad, rad * 0.82, rad), lc, r, 0.16, 0, 0.65, 0.32)
	var top := main.y * 0.65
	b.blob(Vector3(r.randf_range(-0.4, 0.4), cy + main.y * 0.75, r.randf_range(-0.4, 0.4)), Vector3(top * 1.2, top, top * 1.2), MB.shade(leaf, 1.07), r, 0.14, 0, 0.65, 0.25)


static func _conifer(b: MB, r: RandomNumberGenerator, tiers: int, r_base: float, r_step: float, h_tier: float, spacing: float, leaf: Color) -> void:
	var total := 1.6 + spacing * (tiers - 1) + h_tier
	_trunk(b, r, total * 0.75, 0.3 * r_base / 2.6, 0.08, 6, BARK_DARK)
	for i in tiers:
		var y := 1.6 + spacing * i
		var rad := maxf(r_base - r_step * i, 0.45) * r.randf_range(0.94, 1.06)
		var hh := h_tier * (1.0 - 0.06 * i)
		var lc := MB.shade(leaf, 0.86 + 0.05 * i)
		var xf := Transform3D(Basis(), Vector3(r.randf_range(-0.05, 0.05), y, r.randf_range(-0.05, 0.05)))
		b.cyl(xf, rad, 0.0, hh, 9, lc, false, false, lc, r.randf() * TAU, 0.1, r)
		# underside so the cone looks solid from below
		var under := Transform3D(Basis(), xf.origin + Vector3(0, -0.02, 0))
		for k in 9:
			var a0 := TAU * k / 9.0
			var a1 := TAU * (k + 1) / 9.0
			b.tri(under * Vector3(0, 0.35, 0), under * Vector3(cos(a0) * rad, 0, sin(a0) * rad), under * Vector3(cos(a1) * rad, 0, sin(a1) * rad), MB.shade(leaf, 0.5), Vector3.DOWN)


static func _poplar(b: MB, r: RandomNumberGenerator) -> void:
	var leaf := Color(0.38, 0.53, 0.21, 1.0)
	_trunk(b, r, 6.0, 0.28, 0.1, 6)
	b.blob(Vector3(0, 9.2, 0), Vector3(1.75, 6.6, 1.75), leaf, r, 0.12, 1, 0.6, 0.3)
	b.blob(Vector3(0.5, 6.4, 0.3), Vector3(1.25, 3.0, 1.25), MB.shade(leaf, 0.92), r, 0.14, 0, 0.6, 0.3)
	b.blob(Vector3(-0.4, 12.6, -0.2), Vector3(1.05, 3.0, 1.05), MB.shade(leaf, 1.06), r, 0.14, 0, 0.6, 0.25)


static func _birch(b: MB, r: RandomNumberGenerator) -> void:
	var white := Color(0.9, 0.88, 0.83, 0.0)
	var mark := Color(0.16, 0.15, 0.14, 0.0)
	var leaf := Color(0.53, 0.64, 0.26, 1.0)
	var lean := Basis(Vector3(1, 0, 0.3).normalized(), 0.06)
	b.cyl(Transform3D(lean, Vector3(0, -1.0, 0)), 0.2, 0.17, 1.2, 6, white, false)
	var y := 0.2
	var rad := 0.17
	for i in 7:
		var seg := r.randf_range(0.7, 1.3)
		var col := mark if (i % 2 == 1 and r.randf() < 0.75) else white
		var hseg := 0.22 if col == mark else seg
		b.cyl(Transform3D(lean, lean * Vector3(0, y, 0)), rad, rad - 0.012, hseg, 6, col, false)
		y += hseg
		rad -= 0.012
	b.cyl(Transform3D(lean, lean * Vector3(0, y, 0)), rad, 0.03, 2.4, 5, white)
	var top := lean * Vector3(0, y, 0)
	b.cyl_between(lean * Vector3(0, 3.0, 0), lean * Vector3(1.4, 5.6, 0.5), 0.08, 0.03, 5, white)
	b.blob(top + Vector3(0, 1.2, 0), Vector3(1.6, 1.9, 1.6), leaf, r, 0.16, 1, 0.6, 0.3)
	b.blob(top + Vector3(1.0, -0.4, 0.6), Vector3(1.2, 1.2, 1.2), MB.shade(leaf, 0.93), r, 0.18, 0, 0.6, 0.3)
	b.blob(top + Vector3(-0.9, 0.2, -0.5), Vector3(1.1, 1.3, 1.1), MB.shade(leaf, 1.05), r, 0.18, 0, 0.6, 0.3)


static func _palm(b: MB, r: RandomNumberGenerator) -> void:
	var t0 := Color(0.56, 0.46, 0.33, 0.0)
	var t1 := Color(0.45, 0.36, 0.26, 0.0)
	var frond := Color(0.33, 0.53, 0.2, 1.0)
	var h := 9.2
	var n := 10
	var prev := Vector3(0, -1.0, 0)
	for i in n + 1:
		var t := float(i) / n
		var p := Vector3(1.6 * t * t, -0.2 + t * h, 0.3 * t * t)
		if i > 0:
			var rr := lerpf(0.28, 0.18, t)
			b.cyl_between(prev, p, rr * 1.05, rr, 7, t0 if i % 2 == 0 else t1, i == n)
		prev = p
	var crown := prev
	b.blob(crown, Vector3(0.45, 0.4, 0.45), Color(0.4, 0.3, 0.18, 0.0), r, 0.1, 0, 0.5, 0.2)
	for i in 3:
		var a := TAU * i / 3.0
		b.blob(crown + Vector3(cos(a) * 0.35, -0.35, sin(a) * 0.35), Vector3(0.2, 0.2, 0.2), Color(0.35, 0.25, 0.12, 0.0), r, 0.05, 0, 0.5, 0.2)
	var fronds := 9
	for i in fronds:
		var a := TAU * i / fronds + r.randf() * 0.3
		var dir := Vector3(cos(a), 0, sin(a))
		var side := Vector3(-dir.z, 0, dir.x)
		var length := r.randf_range(3.6, 4.6)
		var lift := r.randf_range(0.5, 1.1)
		var segs := 5
		var p0 := crown
		for s in segs:
			var t1v := float(s + 1) / segs
			var droop := lift * sin(t1v * PI * 0.9) - 2.2 * t1v * t1v
			var p1 := crown + dir * length * t1v + Vector3(0, droop, 0)
			var w0 := 0.75 * sin(maxf(float(s) / segs, 0.08) * PI) + 0.1
			var w1 := 0.75 * sin(t1v * PI) * (1.0 - t1v * 0.3) + 0.05
			var lc := MB.shade(frond, 0.85 + 0.15 * t1v)
			var up := Vector3.UP + (p1 - p0).normalized() * -0.3
			# shallow V cross-section, two-sided
			b.quad2(p0, p1, p1 + side * w1 + Vector3(0, 0.15 * w1, 0), p0 + side * w0 + Vector3(0, 0.15 * w0, 0), lc, MB.shade(lc, 0.75), up)
			b.quad2(p0, p1, p1 - side * w1 + Vector3(0, 0.15 * w1, 0), p0 - side * w0 + Vector3(0, 0.15 * w0, 0), lc, MB.shade(lc, 0.75), up)
			p0 = p1


static func _olive(b: MB, r: RandomNumberGenerator) -> void:
	var bark := Color(0.38, 0.33, 0.28, 0.0)
	var leaf := Color(0.5, 0.57, 0.39, 1.0)
	b.cyl(Transform3D(Basis(), Vector3(0, -1.0, 0)), 0.5, 0.42, 1.3, 7, bark, false)
	b.cyl_between(Vector3(0, 0.2, 0), Vector3(0.6, 2.3, 0.2), 0.36, 0.22, 6, bark)
	b.cyl_between(Vector3(0.1, 0.2, 0), Vector3(-0.7, 2.1, -0.4), 0.3, 0.18, 6, bark)
	b.cyl_between(Vector3(0.6, 2.2, 0.2), Vector3(1.4, 3.2, 0.9), 0.2, 0.1, 5, bark)
	b.cyl_between(Vector3(-0.7, 2.0, -0.4), Vector3(-1.5, 3.0, -0.6), 0.18, 0.1, 5, bark)
	var spots := [Vector3(0, 3.7, 0), Vector3(1.6, 3.3, 0.9), Vector3(-1.6, 3.2, -0.6), Vector3(0.4, 3.4, -1.5), Vector3(-0.6, 3.5, 1.4)]
	for i in spots.size():
		var c: Vector3 = spots[i]
		var rad := 1.55 if i == 0 else r.randf_range(1.0, 1.3)
		b.blob(c, Vector3(rad, rad * 0.6, rad), MB.shade(leaf, r.randf_range(0.92, 1.06)), r, 0.18, 1 if i == 0 else 0, 0.6, 0.3)


static func _dead(b: MB, r: RandomNumberGenerator) -> void:
	var col := Color(0.47, 0.42, 0.36, 0.0)
	_trunk(b, r, 6.5, 0.3, 0.07, 6, col)
	for i in 6:
		var y := r.randf_range(2.2, 5.5)
		var a := TAU * i / 6.0 + r.randf() * 0.6
		var l := r.randf_range(1.2, 2.6) * (1.0 - (y - 2.0) / 7.0)
		var p0 := Vector3(0, y, 0)
		var p1 := p0 + Vector3(cos(a) * l, l * r.randf_range(0.5, 0.9), sin(a) * l)
		b.cyl_between(p0, p1, 0.12 * (1.0 - y / 9.0), 0.03, 4, col)
		if r.randf() < 0.7:
			var p2 := p1 + Vector3(cos(a + 0.8) * l * 0.5, l * 0.45, sin(a + 0.8) * l * 0.5)
			b.cyl_between(p1, p2, 0.05, 0.015, 4, col)


# ------------------------------------------------------------------ shrubs, hedges, cacti

static func _bush(b: MB, r: RandomNumberGenerator, leaf: Color, clumps: int, size: float, flower: Color) -> void:
	for i in clumps:
		var a := TAU * i / clumps + r.randf() * 0.6
		var d := 0.0 if i == 0 else size * r.randf_range(0.45, 0.65)
		var rad := size * (0.8 if i == 0 else r.randf_range(0.55, 0.7))
		var c := Vector3(cos(a) * d, rad * 0.75, sin(a) * d)
		b.blob(c, Vector3(rad, rad * 0.85, rad), MB.shade(leaf, r.randf_range(0.9, 1.08)), r, 0.18, 1 if i == 0 else 0, 0.6, 0.35, -0.55)
	if flower.a > 0.0:
		for i in 14:
			var a := r.randf() * TAU
			var y := r.randf_range(0.5, 1.4) * size
			var rad := size * 0.85 * sin(acos(clampf((y - size * 0.75) / size, -1.0, 1.0)))
			var c := Vector3(cos(a) * rad, y, sin(a) * rad)
			var fc := flower if r.randf() < 0.6 else Color(0.98, 0.96, 0.92, 1.0)
			b.blob(c, Vector3(0.13, 0.11, 0.13), fc, r, 0.1, 0, 0.3, 0.1)


static func _desert_bush(b: MB, r: RandomNumberGenerator) -> void:
	var dry := Color(0.55, 0.52, 0.32, 1.0)
	b.blob(Vector3(0, 0.45, 0), Vector3(0.85, 0.55, 0.85), dry, r, 0.35, 0, 0.3, 0.35, -0.6)
	b.blob(Vector3(0.5, 0.35, -0.3), Vector3(0.55, 0.4, 0.55), MB.shade(dry, 0.9), r, 0.35, 0, 0.3, 0.35, -0.6)
	for i in 9:
		var a := r.randf() * TAU
		var p0 := Vector3(cos(a) * 0.2, 0.1, sin(a) * 0.2)
		var p1 := Vector3(cos(a) * r.randf_range(0.8, 1.2), r.randf_range(0.7, 1.2), sin(a) * r.randf_range(0.8, 1.2))
		b.cyl_between(p0, p1, 0.035, 0.008, 3, Color(0.5, 0.4, 0.3, 0.3))


static func _hedge(b: MB, r: RandomNumberGenerator) -> void:
	var leaf := Color(0.22, 0.38, 0.15, 1.0)
	var xs := [-1.75, -0.6, 0.6, 1.75]
	for i in xs.size():
		var x: float = xs[i]
		var h := r.randf_range(0.82, 0.95)
		b.blob(Vector3(x, h, r.randf_range(-0.08, 0.08)), Vector3(0.95, h + 0.05, 0.7), MB.shade(leaf, r.randf_range(0.9, 1.08)), r, 0.12, 1, 0.55, 0.38, -0.85)
	b.box(Transform3D(Basis(), Vector3(0, 0.55, 0)), Vector3(4.0, 1.1, 1.05), MB.shade(leaf, 0.8))


static func _saguaro(b: MB, r: RandomNumberGenerator) -> void:
	var g := Color(0.32, 0.5, 0.27, MB.MATTE)
	var top := Color(0.38, 0.56, 0.3, MB.MATTE)
	b.cyl(Transform3D(Basis(), Vector3(0, -0.5, 0)), 0.36, 0.33, 5.0, 8, g, false, false, g, 0.0, 0.03, r)
	b.blob(Vector3(0, 4.5, 0), Vector3(0.33, 0.35, 0.33), top, r, 0.02, 1, 0.8, 0.1)
	for s: float in [-1.0, 1.0]:
		var y := r.randf_range(1.8, 2.6)
		var out := 0.9
		b.cyl_between(Vector3(0, y, 0), Vector3(s * out, y + 0.15, 0), 0.22, 0.22, 7, g, false)
		var hh := r.randf_range(1.0, 1.8)
		b.cyl(Transform3D(Basis(), Vector3(s * out, y, 0)), 0.22, 0.2, hh, 7, g, false)
		b.blob(Vector3(s * out, y + hh, 0), Vector3(0.2, 0.22, 0.2), top, r, 0.02, 0, 0.8, 0.1)


static func _prickly_pear(b: MB, r: RandomNumberGenerator) -> void:
	var g := Color(0.36, 0.52, 0.28, MB.MATTE)
	var pads: Array[Vector3] = [Vector3(0, 0.45, 0)]
	b.blob(pads[0], Vector3(0.42, 0.5, 0.13), g, r, 0.05, 0, 0.6, 0.15, -2.0, Basis(Vector3.UP, r.randf() * TAU))
	for i in 7:
		var parent: Vector3 = pads[r.randi_range(0, pads.size() - 1)]
		var a := r.randf() * TAU
		var c := parent + Vector3(cos(a) * 0.4, r.randf_range(0.4, 0.6), sin(a) * 0.4)
		if c.y > 1.8:
			continue
		pads.append(c)
		var bas := Basis(Vector3.UP, r.randf() * TAU) * Basis(Vector3(0, 0, 1), r.randf_range(-0.5, 0.5))
		b.blob(c, Vector3(0.36, 0.42, 0.11), MB.shade(g, r.randf_range(0.92, 1.08)), r, 0.05, 0, 0.6, 0.15, -2.0, bas)
		if r.randf() < 0.5:
			b.blob(c + Vector3(0, 0.42, 0), Vector3(0.07, 0.08, 0.07), Color(0.85, 0.25, 0.4, MB.MATTE), r, 0.05, 0, 0.3, 0.0)


# ------------------------------------------------------------------ rocks

static func _red_rock(b: MB, r: RandomNumberGenerator) -> void:
	var bands: Array[Color] = [Color(0.64, 0.33, 0.2, MB.MATTE), Color(0.74, 0.47, 0.3, MB.MATTE), Color(0.6, 0.3, 0.18, MB.MATTE)]
	var y := -0.3
	var rad := 1.9
	for i in 3:
		var hh := r.randf_range(1.0, 1.3)
		b.blob(Vector3(r.randf_range(-0.25, 0.25), y + hh * 0.5, r.randf_range(-0.25, 0.25)), Vector3(rad, hh * 0.78, rad * 0.88), bands[i], r, 0.13, 1, 0.0, 0.18, -0.85)
		y += hh * 0.72
		rad *= r.randf_range(0.7, 0.82)


# ------------------------------------------------------------------ ground cover

static func _grass(b: MB, r: RandomNumberGenerator) -> void:
	var blades := 13
	for i in blades:
		var a := TAU * i / blades + r.randf() * 0.5
		var h := r.randf_range(0.2, 0.46)
		var lean := r.randf_range(0.1, 0.3)
		var dir := Vector3(cos(a), 0, sin(a))
		var side := Vector3(-dir.z, 0, dir.x)
		var base := dir * r.randf_range(0.0, 0.22)
		var w := r.randf_range(0.045, 0.075)
		var tip := base + dir * lean + Vector3(0, h, 0)
		var mid := base + dir * lean * 0.35 + Vector3(0, h * 0.55, 0) + side * 0.0
		var br := r.randf_range(0.85, 1.12)
		var c0 := Color(br, br, br, 0.0)
		var c1 := Color(br, br, br, 0.55)
		var c2 := Color(br * 1.05, br * 1.05, br * 0.95, 1.0)
		var n := dir + Vector3(0, 0.6, 0)
		b.tri_vc(base - side * w, base + side * w, mid + side * w * 0.6, c0, c0, c1, n)
		b.tri_vc(base - side * w, mid + side * w * 0.6, mid - side * w * 0.6, c0, c1, c1, n)
		b.tri_vc(mid - side * w * 0.6, mid + side * w * 0.6, tip, c1, c1, c2, n)


static func _flowers(b: MB, r: RandomNumberGenerator) -> void:
	var stem := Color(0.28, 0.44, 0.16, 0.0)
	for i in 6:
		var a := r.randf() * TAU
		var base := Vector3(cos(a), 0, sin(a)) * r.randf_range(0.02, 0.25)
		var h := r.randf_range(0.28, 0.5)
		var top := base + Vector3(r.randf_range(-0.05, 0.05), h, r.randf_range(-0.05, 0.05))
		b.cyl_between(base, top, 0.012, 0.01, 3, stem, false)
		# small leaf
		var ld := Vector3(cos(a + 1.0), 0, sin(a + 1.0))
		b.quad2(base + Vector3(0, 0.05, 0), base + ld * 0.12 + Vector3(0, 0.12, 0), base + ld * 0.06 + Vector3(0, 0.16, 0), base + Vector3(0, 0.1, 0), stem, stem, Vector3.UP)
		# five-petal head (two-sided star), white so the instance tint picks the flower colour
		var petal := Color(1.0, 1.0, 1.0, 1.0)
		var centre_c := Color(0.95, 0.75, 0.15, 0.0)
		var rad := r.randf_range(0.05, 0.08)
		for k in 5:
			var pa := TAU * k / 5.0
			var pb := pa + TAU / 10.0
			var p1 := top + Vector3(cos(pa) * rad, 0.01, sin(pa) * rad)
			var p2 := top + Vector3(cos(pb) * rad * 0.45, 0.0, sin(pb) * rad * 0.45)
			var p0 := top + Vector3(cos(pa - TAU / 10.0) * rad * 0.45, 0.0, sin(pa - TAU / 10.0) * rad * 0.45)
			b.tri(top, p0, p1, petal, Vector3.UP)
			b.tri(top, p1, p2, petal, Vector3.UP)
			b.tri(top - Vector3(0, 0.005, 0), p0 - Vector3(0, 0.005, 0), p1 - Vector3(0, 0.005, 0), petal, Vector3.DOWN)
		b.blob(top + Vector3(0, 0.012, 0), Vector3(0.022, 0.015, 0.022), centre_c, r, 0.0, 0, 0.5, 0.0)


static func _reeds(b: MB, r: RandomNumberGenerator) -> void:
	var g := Color(0.46, 0.56, 0.26, 1.0)
	for i in 12:
		var a := r.randf() * TAU
		var base := Vector3(cos(a), 0, sin(a)) * r.randf_range(0.0, 0.45)
		var h := r.randf_range(1.2, 2.0)
		var tip := base + Vector3(cos(a) * 0.3, h, sin(a) * 0.3)
		var side := Vector3(-sin(a), 0, cos(a)) * 0.04
		var lc := MB.shade(g, r.randf_range(0.85, 1.1))
		b.quad2(base - side - Vector3(0, 0.3, 0), base + side - Vector3(0, 0.3, 0), tip + side * 0.2, tip - side * 0.2, lc, MB.shade(lc, 0.8), Vector3(cos(a), 0.2, sin(a)))
	for i in 4:
		var a := r.randf() * TAU
		var base := Vector3(cos(a), 0, sin(a)) * r.randf_range(0.0, 0.3)
		var h := r.randf_range(1.5, 2.1)
		var top := base + Vector3(0, h, 0)
		b.cyl_between(base - Vector3(0, 0.3, 0), top, 0.015, 0.012, 3, Color(0.42, 0.5, 0.24, 0.6), false)
		b.cyl(Transform3D(Basis(), top - Vector3(0, 0.32, 0)), 0.045, 0.04, 0.26, 6, Color(0.36, 0.22, 0.12, 0.0))


static func _hay(b: MB, r: RandomNumberGenerator) -> void:
	var straw := Color(0.86, 0.71, 0.38, MB.MATTE)
	var end := Color(0.78, 0.62, 0.32, MB.MATTE)
	var xf := Transform3D(Basis(Vector3(0, 0, 1), PI * 0.5), Vector3(0.62, 0.7, 0))
	b.cyl(xf, 0.75, 0.75, 1.24, 14, straw, true, true, end)
	for k in 3:
		var rr := 0.62 - k * 0.2
		b.cyl(Transform3D(Basis(Vector3(0, 0, 1), -PI * 0.5), Vector3(0.63 + k * 0.004, 0.7, 0)), rr, rr, 0.01, 12, MB.shade(end, 0.88 + 0.06 * k), true, false)
		b.cyl(Transform3D(Basis(Vector3(0, 0, 1), PI * 0.5), Vector3(-0.63 - k * 0.004, 0.7, 0)), rr, rr, 0.01, 12, MB.shade(end, 0.88 + 0.06 * k), true, false)


static func _logs(b: MB, r: RandomNumberGenerator) -> void:
	var bark := Color(0.42, 0.31, 0.21, MB.MATTE)
	var cut := Color(0.82, 0.68, 0.47, MB.MATTE)
	var rows := [[-0.38, 0.0, 0.38], [-0.19, 0.19], [0.0]]
	for j in rows.size():
		var row: Array = rows[j]
		for x: float in row:
			var rad := r.randf_range(0.17, 0.21)
			var y := 0.2 + j * 0.33
			var l := r.randf_range(2.2, 2.6)
			b.cyl(Transform3D(Basis(Vector3(1, 0, 0), PI * 0.5), Vector3(x, y, -l * 0.5)), rad, rad, l, 8, bark, true, true, cut, r.randf())


# ------------------------------------------------------------------ far-distance families

## Unit-sized impostor-like meshes (1 m wide, 1 m tall, origin at base centre). The dressing scales
## them per species to the near mesh's bounds and tints them with the species foliage colour.
static func make_far(family: int) -> MB:
	var b := MB.new()
	var r := _rng("far_%d" % family)
	var bark := Color(0.35, 0.27, 0.2, 0.0)
	var white := Color(1, 1, 1, 1.0)
	match family:
		Far.CONIFER:
			b.cyl(Transform3D(Basis(), Vector3(0, -0.05, 0)), 0.035, 0.03, 0.2, 4, bark, false)
			b.cyl(Transform3D(Basis(), Vector3(0, 0.1, 0)), 0.5, 0.0, 0.9, 7, white, false, false, white, 0.3)
			b.cyl(Transform3D(Basis(), Vector3(0, 0.1, 0)), 0.5, 0.0, 0.001, 7, MB.shade(white, 0.6), false, false, white, 0.3)
		Far.BROADLEAF:
			b.cyl(Transform3D(Basis(), Vector3(0, -0.05, 0)), 0.05, 0.04, 0.45, 5, bark, false)
			b.blob(Vector3(0, 0.6, 0), Vector3(0.5, 0.38, 0.5), white, r, 0.08, 0, 0.7, 0.3)
		Far.PALM:
			b.cyl(Transform3D(Basis(), Vector3(0, -0.05, 0)), 0.03, 0.025, 0.92, 4, bark, false)
			var c := Vector3(0.08, 0.86, 0)
			for i in 6:
				var a := TAU * i / 6.0
				var d := Vector3(cos(a), 0, sin(a))
				var s := Vector3(-d.z, 0, d.x) * 0.08
				b.quad2(c, c + d * 0.5 + s - Vector3(0, 0.15, 0), c + d * 0.5 - Vector3(0, 0.2, 0), c + d * 0.5 - s - Vector3(0, 0.15, 0), white, MB.shade(white, 0.7), Vector3.UP)
		Far.HEDGE:
			b.box(Transform3D(Basis(), Vector3(0, 0.5, 0)), Vector3(1.0, 1.0, 1.0), white, MB.shade(white, 1.08))
		_:
			return null
	return b


# ------------------------------------------------------------------ far stand-ins from the real meshes

const FAR_VIEWS := 3          # silhouette directions (0, 60, 120 deg) -> six-sided rings
const FAR_LINES := 64         # horizontal sample lines over the mesh height
const FAR_CROWN_RINGS := 4


## Far-distance stand-in for a tree or hedge mesh (Blender kit or placeholder), in three steps so the work
## can run on a thread: far_source() (main thread) reads the mesh, far_arrays() (any thread) builds a six-sided
## lathe whose rings follow the mesh's side silhouettes - covered width and centre per height from three view
## directions, measured exactly as the union of the triangles' spans on horizontal sample lines - coloured with
## the mesh's own leaf / bark colour per height (material albedo x vertex colour, as foliage.gdshader draws it),
## and far_mesh() makes the ArrayMesh. It has the mesh's real size and orientation, so a far instance reuses the
## near instance's transform. COLOR.a = foliage mask.
static func far_from_mesh(m: Mesh, mat: Material, mesh_name: String, keep := 1.0) -> ArrayMesh:
	var arrays := far_arrays(far_source(m, keep))
	return far_mesh(arrays, mat, mesh_name) if not arrays.is_empty() else null


## Triangles (local space, 3 vertices each) and per-triangle colour (alpha = foliage mask) of a mesh, plus the
## share `keep` of its silhouette area the stand-in keeps.
static func far_source(m: Mesh, keep := 1.0) -> Dictionary:
	var tris := PackedVector3Array()
	var tcol := PackedColorArray()
	for s in m.get_surface_count():
		var arr := m.surface_get_arrays(s)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		if v.is_empty():
			continue
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		var vc: PackedColorArray = arr[Mesh.ARRAY_COLOR] if arr[Mesh.ARRAY_COLOR] != null else PackedColorArray()
		var alb := Color(1, 1, 1)
		var leaf_ov := -1.0
		var sm := m.surface_get_material(s) as ShaderMaterial
		if sm != null:
			var a: Variant = sm.get_shader_parameter("albedo")
			if a is Color:
				alb = (a as Color).srgb_to_linear()
			var lv: Variant = sm.get_shader_parameter("leaf_override")
			if lv != null:
				leaf_ov = float(lv)
		var n := idx.size() if not idx.is_empty() else v.size()
		for k in range(0, n - 2, 3):
			var c := Color(0, 0, 0, 0)
			for e in 3:
				var vi: int = idx[k + e] if not idx.is_empty() else k + e
				tris.append(v[vi])
				var col := vc[vi] if vi < vc.size() else Color(1, 1, 1, 1)
				c += Color(col.r * alb.r, col.g * alb.g, col.b * alb.b, leaf_ov if leaf_ov >= 0.0 else col.a) / 3.0
			tcol.append(c)
	return {"tris": tris, "cols": tcol, "k": keep}


static func far_mesh(arrays: Array, mat: Material, mesh_name: String) -> ArrayMesh:
	var am := ArrayMesh.new()
	am.resource_name = mesh_name
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	am.surface_set_material(0, mat)
	return am


static func far_arrays(src: Dictionary) -> Array:
	var tris: PackedVector3Array = src.get("tris", PackedVector3Array())
	var tcol: PackedColorArray = src.get("cols", PackedColorArray())
	if tcol.is_empty():
		return []
	var y0 := INF
	var y1 := -INF
	for p in tris:
		y0 = minf(y0, p.y)
		y1 = maxf(y1, p.y)
	var dy := maxf(y1 - y0, 0.01) / FAR_LINES
	var leaf_mask := PackedByteArray()
	leaf_mask.resize(tcol.size())
	for t in tcol.size():
		leaf_mask[t] = 1 if tcol[t].a > 0.5 else 0
	var cov := _coverage(tris, leaf_mask, y0, dy)
	# crown bottom: lowest line whose mean leaf width reaches 15 % of the widest leaf line
	var max_leaf := 0.0
	for l in FAR_LINES:
		max_leaf = maxf(max_leaf, _far_line(cov, l, 1))
	var crown_l := 0
	while crown_l < FAR_LINES - 1 and _far_line(cov, crown_l, 1) < max_leaf * 0.15:
		crown_l += 1
	var top_l := FAR_LINES - 1
	while top_l > crown_l and _far_line(cov, top_l, 0) <= 0.0:
		top_l -= 1
	var yc := y0 + crown_l * dy
	var yt := y0 + (top_l + 1) * dy
	# ring heights: trunk base and trunk top (when the crown starts clearly above the ground), crown rings
	var ring_y := PackedFloat32Array()
	var ring_band := []   # [first line, last line] averaged for each ring
	if crown_l >= 4:
		ring_y.append(y0)
		ring_band.append([0, maxi(crown_l / 3, 1)])
		ring_y.append(yc - dy * 0.5)
		ring_band.append([maxi(crown_l - 3, 0), crown_l - 1])
	var step := (yt - yc) / FAR_CROWN_RINGS
	var band := maxi(int(step / dy * 0.5), 1)
	for k in FAR_CROWN_RINGS:
		var yk := yc + k * step
		var lk := int((yk - y0) / dy)
		ring_y.append(yk)
		ring_band.append([lk if k == 0 else maxi(lk - band, crown_l), mini(lk + band, top_l)])
	# leaf / bark colour per ring from the triangles around its height (area weighted)
	var leaf_c: Array[Color] = []
	var bark_c: Array[Color] = []
	for k in ring_y.size():
		leaf_c.append(Color(0, 0, 0, 0))
		bark_c.append(Color(0, 0, 0, 0))
	for t in tcol.size():
		var a := tris[t * 3]
		var b := tris[t * 3 + 1]
		var c := tris[t * 3 + 2]
		var area := (b - a).cross(c - a).length()
		var cy := (a.y + b.y + c.y) / 3.0
		var k := 0
		for q in ring_y.size():
			if absf(ring_y[q] - cy) < absf(ring_y[k] - cy):
				k = q
		var col := tcol[t]
		var wc := Color(col.r * area, col.g * area, col.b * area, area)
		if col.a > 0.5:
			leaf_c[k] += wc
		else:
			bark_c[k] += wc
	var leaf_all := Color(0, 0, 0, 0)
	var bark_all := Color(0, 0, 0, 0)
	for k in ring_y.size():
		leaf_all += leaf_c[k]
		bark_all += bark_c[k]
	# rings: centre from the per-view centroids (least squares), radius = half the covered width per view
	var verts := PackedVector3Array()
	var colors := PackedColorArray()
	var vcen := PackedVector3Array()
	var dirs: Array[Vector3] = []
	for d in FAR_VIEWS * 2:
		var ang := PI * d / FAR_VIEWS
		dirs.append(Vector3(cos(ang), 0.0, sin(ang)))
	var last_c := Vector3.ZERO
	for k in ring_y.size():
		var l0: int = ring_band[k][0]
		var l1: int = maxi(ring_band[k][1], l0)
		var centre := Vector2.ZERO
		var rad := PackedFloat32Array()
		var len_all := 0.0
		var len_leaf := 0.0
		for vw in FAR_VIEWS:
			var la := 0.0
			var ll := 0.0
			var cs := 0.0
			for l in range(l0, l1 + 1):
				var o := (vw * FAR_LINES + l) * 3
				la += cov[o]
				ll += cov[o + 1]
				cs += cov[o + 2]
			var ang := PI * vw / FAR_VIEWS
			centre += Vector2(cos(ang), sin(ang)) * (cs / la if la > 0.0 else 0.0) * (2.0 / FAR_VIEWS)
			rad.append(maxf(la / (l1 - l0 + 1) * 0.5, 0.04))
			len_all += la
			len_leaf += ll
		var leaf_f := clampf(len_leaf / len_all, 0.0, 1.0) if len_all > 0.0 else 0.0
		var col := _avg(bark_c[k], bark_all if bark_all.a > 0.0 else leaf_all).lerp(_avg(leaf_c[k], leaf_all), leaf_f)
		col.a = 1.0 if leaf_f > 0.5 else leaf_f
		last_c = Vector3(centre.x, ring_y[k], centre.y)
		for d in dirs.size():
			verts.append(last_c + dirs[d] * rad[d % FAR_VIEWS])
			colors.append(col)
			vcen.append(last_c)
	verts.append(Vector3(last_c.x, yt, last_c.z))
	colors.append(colors[colors.size() - 1])
	vcen.append(last_c)
	var n_dir := dirs.size()
	var n_ring := verts.size() - 1
	var idx := PackedInt32Array()
	for k in ring_y.size() - 1:
		for d in n_dir:
			var a := k * n_dir + d
			var b := k * n_dir + (d + 1) % n_dir
			idx.append_array([a, a + n_dir, b, b, a + n_dir, b + n_dir])
	var apex := verts.size() - 1
	var last := (ring_y.size() - 1) * n_dir
	for d in n_dir:
		idx.append_array([last + d, apex, last + (d + 1) % n_dir])
	# scale the rings so the stand-in covers the mesh's silhouette area (three views) times k
	var lathe := PackedVector3Array()
	for i in idx:
		lathe.append(verts[i])
	var fcov := _coverage(lathe, PackedByteArray(), y0, dy)
	var a_mesh := 0.0
	var a_far := 0.0
	for i in range(0, cov.size(), 3):
		a_mesh += cov[i]
		a_far += fcov[i]
	var f := clampf(float(src.get("k", 1.0)) * a_mesh / a_far, 0.4, 2.0) if a_far > 0.0 else 1.0
	for i in n_ring:
		verts[i] = vcen[i] + (verts[i] - vcen[i]) * f
	# smooth normals; winding fixed per triangle (every lathe face has an outward horizontal normal component)
	var norms := PackedVector3Array()
	norms.resize(verts.size())
	for k in range(0, idx.size(), 3):
		var a := verts[idx[k]]
		var b := verts[idx[k + 1]]
		var c := verts[idx[k + 2]]
		var fnrm := (c - a).cross(b - a)
		var mid := (a + b + c) / 3.0
		var axis := (vcen[idx[k]] + vcen[idx[k + 1]] + vcen[idx[k + 2]]) / 3.0
		if fnrm.dot(mid - Vector3(axis.x, mid.y, axis.z)) < 0.0:
			var tmp := idx[k + 1]
			idx[k + 1] = idx[k + 2]
			idx[k + 2] = tmp
			fnrm = -fnrm
		for e in 3:
			norms[idx[k + e]] += fnrm
	for i in norms.size():
		norms[i] = norms[i].normalized() if norms[i].length_squared() > 0.0 else Vector3.UP
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = idx
	return arrays


## Silhouette coverage of a triangle list (3 vertices each) from the FAR_VIEWS directions on FAR_LINES horizontal
## lines from y0 (spacing dy): per view and line the covered length (union of the triangles' spans), the leaf
## length (triangles with leaf[t] = 1) and the sum of covered-segment centre x length.
static func _coverage(tris: PackedVector3Array, leaf: PackedByteArray, y0: float, dy: float) -> PackedFloat32Array:
	var cov := PackedFloat32Array()
	cov.resize(FAR_VIEWS * FAR_LINES * 3)
	for vw in FAR_VIEWS:
		var ang := PI * vw / FAR_VIEWS
		var u := Vector3(cos(ang), 0.0, sin(ang))
		var all_iv: Array[PackedVector2Array] = []
		var leaf_iv: Array[PackedVector2Array] = []
		for l in FAR_LINES:
			all_iv.append(PackedVector2Array())
			leaf_iv.append(PackedVector2Array())
		for t in tris.size() / 3:
			var pts: Array[Vector2] = [Vector2(tris[t * 3].dot(u), tris[t * 3].y), Vector2(tris[t * 3 + 1].dot(u), tris[t * 3 + 1].y),
				Vector2(tris[t * 3 + 2].dot(u), tris[t * 3 + 2].y)]
			var ymin := minf(pts[0].y, minf(pts[1].y, pts[2].y))
			var ymax := maxf(pts[0].y, maxf(pts[1].y, pts[2].y))
			var l0 := maxi(ceili((ymin - y0) / dy - 0.5), 0)
			var l1 := mini(floori((ymax - y0) / dy - 0.5), FAR_LINES - 1)
			var is_leaf := t < leaf.size() and leaf[t] == 1
			for l in range(l0, l1 + 1):
				var y := y0 + (l + 0.5) * dy
				var xa := INF
				var xb := -INF
				for e in 3:
					var p := pts[e]
					var q := pts[(e + 1) % 3]
					if (p.y - y) * (q.y - y) > 0.0 or p.y == q.y:
						continue
					var x := p.x + (y - p.y) * (q.x - p.x) / (q.y - p.y)
					xa = minf(xa, x)
					xb = maxf(xb, x)
				if xb - xa > 1e-4:
					all_iv[l].append(Vector2(xa, xb))
					if is_leaf:
						leaf_iv[l].append(Vector2(xa, xb))
		for l in FAR_LINES:
			var ua := _union(all_iv[l])
			var o := (vw * FAR_LINES + l) * 3
			cov[o] = ua.x
			cov[o + 1] = _union(leaf_iv[l]).x
			cov[o + 2] = ua.y
	return cov


## View-averaged coverage value of one sample line (field 0 = covered length, 1 = leaf length).
static func _far_line(cov: PackedFloat32Array, l: int, field: int) -> float:
	var s := 0.0
	for vw in FAR_VIEWS:
		s += cov[(vw * FAR_LINES + l) * 3 + field]
	return s / FAR_VIEWS


## (total length, sum of centre x length) of the union of 1D intervals (x = start, y = end).
static func _union(iv: PackedVector2Array) -> Vector2:
	if iv.is_empty():
		return Vector2.ZERO
	iv.sort()
	var total := 0.0
	var cs := 0.0
	var a := iv[0].x
	var b := iv[0].y
	for k in range(1, iv.size()):
		if iv[k].x > b:
			total += b - a
			cs += (a + b) * 0.5 * (b - a)
			a = iv[k].x
			b = iv[k].y
		else:
			b = maxf(b, iv[k].y)
	total += b - a
	cs += (a + b) * 0.5 * (b - a)
	return Vector2(total, cs)


static func _avg(c: Color, fallback: Color) -> Color:
	var src := c if c.a > 0.0 else fallback
	return Color(src.r / src.a, src.g / src.a, src.b / src.a, 1.0) if src.a > 0.0 else Color(0.2, 0.3, 0.15, 1.0)
