extends SceneTree
## Generates the tileable ground textures for terrain.gdshader (albedo with roughness in alpha +
## tangent-space normal) into assets/textures/terrain/. All noise is periodic by construction
## (value noise / voronoi on a wrapped integer lattice), so the textures tile exactly.
## Everything is generated from scratch here - no external assets, self-made (see ASSET_CONVENTIONS.md).
## Run (wrapped in timeout, writes files then quits):
##   Godot_console.exe --headless --path "<project>" -s tools/make_terrain_textures.gd

const OUT_DIR := "res://assets/textures/terrain"
## Textures: name -> [size, normal strength]. Albedo RGB + roughness in alpha.
const MATS := {
	"grass": [1024, 0.6],
	"field": [512, 0.8],
	"dirt": [512, 0.95],
	"gravel": [512, 1.5],
	"sand": [512, 0.55],
	"rock": [1024, 1.7],
	"snow": [512, 0.4],
}


func _initialize() -> void:
	var t0 := Time.get_ticks_msec()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	for name: String in MATS:
		var size: int = MATS[name][0]
		var nstrength: float = MATS[name][1]
		print("[tex] %s %dx%d ..." % [name, size, size])
		var albedo := Image.create(size, size, false, Image.FORMAT_RGBA8)
		var h: PackedFloat32Array
		match name:
			"grass":
				h = _gen_grass(size, albedo)
			"field":
				h = _gen_field(size, albedo)
			"dirt":
				h = _gen_dirt(size, albedo)
			"gravel":
				h = _gen_gravel(size, albedo)
			"sand":
				h = _gen_sand(size, albedo)
			"rock":
				h = _gen_rock(size, albedo)
			"snow":
				h = _gen_snow(size, albedo)
		_write_normal(name, size, h, nstrength)
		albedo.save_png("%s/%s_albedo.png" % [OUT_DIR, name])
		print("[tex] %s done (%.1f s)" % [name, (Time.get_ticks_msec() - t0) / 1000.0])
	print("[tex] CHECK_OK all textures written to %s" % OUT_DIR)
	quit(0)


# ------------------------------------------------------------------ periodic noise helpers

## 2D integer hash -> 0..1 (wraps through the period via the caller).
static func _hash2(ix: int, iy: int, seed: int) -> float:
	var h := int(ix) * 374761393 + int(iy) * 668265263 + int(seed) * 2654435761
	h = (h ^ (h >> 13)) * 1274126177
	h = h ^ (h >> 16)
	return float(h & 0xFFFFFF) / 16777215.0


## Periodic value noise: x, y in cell units; `period` = number of cells across the texture.
static func _vnoise(x: float, y: float, period: int, seed: int) -> float:
	var ix := floori(x)
	var iy := floori(y)
	var fx := x - float(ix)
	var fy := y - float(iy)
	var u := fx * fx * (3.0 - 2.0 * fx)
	var v := fy * fy * (3.0 - 2.0 * fy)
	var x0 := posmod(ix, period)
	var y0 := posmod(iy, period)
	var x1 := (x0 + 1) % period
	var y1 := (y0 + 1) % period
	var a := _hash2(x0, y0, seed)
	var b := _hash2(x1, y0, seed)
	var c := _hash2(x0, y1, seed)
	var d := _hash2(x1, y1, seed)
	return lerpf(lerpf(a, b, u), lerpf(c, d, u), v)


## Periodic fBm built from the value noise; base period cells across the texture, doubling per octave.
static func _fbm(x: float, y: float, period: int, seed: int, octaves: int, gain := 0.5) -> float:
	var sum := 0.0
	var amp := 1.0
	var norm := 0.0
	var per := period
	for o in octaves:
		sum += _vnoise(x * float(per), y * float(per), per, seed + o * 131) * amp
		norm += amp
		amp *= gain
		per *= 2
	return sum / norm


## Periodic voronoi: returns F1 (nearest feature distance) and the feature's random value.
static func _voronoi(x: float, y: float, period: int, seed: int, jitter: float, out_feat: PackedFloat32Array) -> float:
	var ix := floori(x)
	var iy := floori(y)
	var best := 8.0
	var feat := 0.0
	for oy in range(-1, 2):
		for ox in range(-1, 2):
			var cx := ix + ox
			var cy := iy + oy
			var px := float(cx) + 0.5 + (_hash2(posmod(cx, period), posmod(cy, period), seed) - 0.5) * jitter
			var py := float(cy) + 0.5 + (_hash2(posmod(cx, period), posmod(cy, period), seed + 7331) - 0.5) * jitter
			var d := Vector2(x - px, y - py).length()
			if d < best:
				best = d
				feat = _hash2(posmod(cx, period), posmod(cy, period), seed + 99)
	out_feat[0] = feat
	return best


## Domain-warped periodic fbm (warps are themselves periodic, so tiling survives).
static func _warped_fbm(x: float, y: float, period: int, seed: int, octaves: int, warp: float) -> float:
	var wx := (_fbm(x + 0.31, y, period, seed + 11, 3) - 0.5) * warp
	var wy := (_fbm(x, y + 0.77, period, seed + 23, 3) - 0.5) * warp
	return _fbm(x + wx, y + wy, period, seed, octaves)


static func _mix(a: Color, b: Color, t: float) -> Color:
	return Color(lerpf(a.r, b.r, t), lerpf(a.g, b.g, t), lerpf(a.b, b.b, t), 1.0)


## Writes <name>_normal.png from the height field (central differences with wrap).
func _write_normal(name: String, n: int, h: PackedFloat32Array, strength: float) -> void:
	var img := Image.create(n, n, false, Image.FORMAT_RGB8)
	var s := strength * float(n) * 0.35
	for y in n:
		var yu := (y + n - 1) % n
		var yd := (y + 1) % n
		for x in n:
			var xl := (x + n - 1) % n
			var xr := (x + 1) % n
			var dx := (h[y * n + xr] - h[y * n + xl]) * s
			var dy := (h[yd * n + x] - h[yu * n + x]) * s
			var inv := 1.0 / sqrt(dx * dx + dy * dy + 1.0)
			# Godot tangent space: +X right (+U), +Y up (-V), +Z out of the surface.
			img.set_pixel(x, y, Color(clampf(-dx * inv * 0.5 + 0.5, 0.0, 1.0), clampf(dy * inv * 0.5 + 0.5, 0.0, 1.0), inv))
	img.save_png("%s/%s_normal.png" % [OUT_DIR, name])


# ------------------------------------------------------------------ materials

## Meadow grass: clumpy fbm, fine anisotropic wisps, sparse dry patches.
func _gen_grass(n: int, albedo: Image) -> PackedFloat32Array:
	var h := PackedFloat32Array()
	h.resize(n * n)
	var dark := Color(0.11, 0.22, 0.07)
	var mid := Color(0.21, 0.35, 0.10)
	var fresh := Color(0.32, 0.46, 0.14)
	var dry := Color(0.44, 0.40, 0.16)
	for y in n:
		var fy := float(y) / float(n)
		for x in n:
			var fx := float(x) / float(n)
			# Wisps: stretched noise in a rotated frame gives mown-grass direction variation.
			var u := fx - fy * 0.35
			var v := fx * 0.35 + fy
			var wisps := _fbm(u, v * 6.0, 16, 41, 4)
			var clumps := _warped_fbm(fx, fy, 6, 17, 5, 1.2)
			var patch := _fbm(fx, fy, 3, 91, 3)
			var hh := clumps * 0.62 + wisps * 0.38
			h[y * n + x] = hh
			var col := _mix(dark, mid, clampf(hh * 1.7, 0.0, 1.0))
			col = _mix(col, fresh, clampf((hh - 0.52) * 2.4, 0.0, 1.0))
			col = _mix(col, dry, clampf((patch - 0.62) * 2.6, 0.0, 0.65))
			# Sun-side brightening on wisp crests for readability up close.
			var sheen := clampf((wisps - 0.6) * 1.8, 0.0, 1.0) * 0.25
			col = _mix(col, Color(0.5, 0.55, 0.25), sheen)
			col.a = clampf(0.86 + (clumps - 0.5) * 0.12, 0.78, 0.96)
			albedo.set_pixel(x, y, col)

	return h

## Field soil: plough rows (warped so they are not dead straight) + dry stubble patches.
func _gen_field(n: int, albedo: Image) -> PackedFloat32Array:
	var h := PackedFloat32Array()
	h.resize(n * n)
	var soil_dark := Color(0.16, 0.11, 0.08)
	var soil := Color(0.27, 0.19, 0.12)
	var soil_dry := Color(0.38, 0.29, 0.18)
	var stubble := Color(0.48, 0.40, 0.22)
	for y in n:
		var fy := float(y) / float(n)
		for x in n:
			var fx := float(x) / float(n)
			var grain := _fbm(fx, fy, 48, 7, 5)
			var clod := _warped_fbm(fx, fy, 8, 29, 4, 1.0)
			var warp := (_fbm(fx, fy, 4, 53, 3) - 0.5) * 0.55
			var row_wave := absf(sin((fy + warp) * PI * 14.0))
			var row := pow(row_wave, 0.55)
			var hh := clod * 0.55 + grain * 0.2 + row * 0.25
			h[y * n + x] = hh
			var patch := _fbm(fx, fy, 3, 66, 3)
			var col := _mix(soil_dark, soil, clampf(clod * 1.6, 0.0, 1.0))
			col = _mix(col, soil_dry, clampf((patch - 0.55) * 2.2, 0.0, 0.7))
			col = _mix(col, stubble, clampf((row - 0.55) * 1.6, 0.0, 1.0) * clampf((patch - 0.3) * 2.0, 0.3, 1.0))
			col.a = clampf(0.9 + (row - 0.5) * 0.1, 0.84, 0.96)
			albedo.set_pixel(x, y, col)

	return h

## Compacted earth: lumpy surface, embedded pebbles, faint crack lines.
func _gen_dirt(n: int, albedo: Image) -> PackedFloat32Array:
	var h := PackedFloat32Array()
	h.resize(n * n)
	var base := Color(0.24, 0.19, 0.14)
	var light := Color(0.38, 0.31, 0.22)
	var pebble := Color(0.46, 0.44, 0.40)
	var feat := PackedFloat32Array()
	feat.resize(1)
	for y in n:
		var fy := float(y) / float(n)
		for x in n:
			var fx := float(x) / float(n)
			var lump := _warped_fbm(fx, fy, 10, 3, 5, 0.9)
			var grain := _fbm(fx, fy, 64, 19, 4)
			var d := _voronoi(fx * 22.0, fy * 22.0, 22, 5, 0.9, feat) / 1.5
			var cracks := _fbm(fx, fy, 6, 77, 4)
			var crack := clampf(1.0 - absf(cracks - 0.5) * 14.0, 0.0, 1.0)
			var hh := lump * 0.6 + grain * 0.15 + clampf(1.0 - d * 2.2, 0.0, 1.0) * 0.25
			h[y * n + x] = hh
			var col := _mix(base, light, clampf(lump * 1.5, 0.0, 1.0))
			var peb := clampf(1.0 - d * 3.4, 0.0, 1.0)
			col = _mix(col, pebble, peb * 0.85)
			col = _mix(col, Color(0.1, 0.08, 0.06), crack * 0.5 * (1.0 - peb))
			col.a = clampf(0.93 - peb * 0.08 + crack * 0.04, 0.8, 0.97)
			albedo.set_pixel(x, y, col)

	return h

## Gravel: crisp voronoi pebbles with per-stone shading, dark gaps.
func _gen_gravel(n: int, albedo: Image) -> PackedFloat32Array:
	var h := PackedFloat32Array()
	h.resize(n * n)
	var feat := PackedFloat32Array()
	feat.resize(1)
	for y in n:
		var fy := float(y) / float(n)
		for x in n:
			var fx := float(x) / float(n)
			var cells := 26
			var d := _voronoi(fx * cells, fy * cells, cells, 13, 1.0, feat)
			var grit := _fbm(fx, fy, 96, 31, 3)
			var stone := clampf(1.0 - d * 2.6, 0.0, 1.0)
			var dome := clampf(1.0 - d * 1.9, 0.0, 1.0)
			var shade := 0.35 + feat[0] * 0.5
			var hh := dome * 0.8 + grit * 0.2
			h[y * n + x] = hh
			var col := Color(shade * 0.75, shade * 0.73, shade * 0.7)
			col = _mix(Color(0.13, 0.12, 0.11), col, stone)
			col = _mix(col, Color(shade * 1.15, shade * 1.12, shade * 1.08), dome * dome * 0.7)
			col = _mix(col, Color(col.r * 0.85, col.g * 0.85, col.b * 0.85), grit * 0.4)
			col.a = clampf(0.72 + stone * 0.2, 0.68, 0.94)
			albedo.set_pixel(x, y, col)

	return h

## Sand: wind ripples with domain warp + fine grain.
func _gen_sand(n: int, albedo: Image) -> PackedFloat32Array:
	var h := PackedFloat32Array()
	h.resize(n * n)
	var deep := Color(0.52, 0.42, 0.28)
	var mid := Color(0.66, 0.56, 0.38)
	var light := Color(0.79, 0.70, 0.50)
	for y in n:
		var fy := float(y) / float(n)
		for x in n:
			var fx := float(x) / float(n)
			var warp := (_fbm(fx, fy, 5, 43, 3) - 0.5) * 0.8
			var ripple := absf(sin((fx * 0.3 + fy + warp) * PI * 10.0))
			var ripple_h := pow(ripple, 0.7)
			var grain := _fbm(fx, fy, 80, 57, 4)
			var drift := _warped_fbm(fx, fy, 4, 71, 4, 1.1)
			var hh := ripple_h * 0.45 + drift * 0.35 + grain * 0.2
			h[y * n + x] = hh
			var col := _mix(deep, mid, clampf(hh * 1.5, 0.0, 1.0))
			col = _mix(col, light, clampf((hh - 0.58) * 2.2, 0.0, 1.0))
			col = _mix(col, Color(0.47, 0.40, 0.30), clampf((drift - 0.62) * 2.0, 0.0, 0.5))
			col.a = clampf(0.80 + (grain - 0.5) * 0.1, 0.72, 0.9)
			albedo.set_pixel(x, y, col)

	return h

## Rock: ridged fbm with strata bands and crack seams, strong height relief.
func _gen_rock(n: int, albedo: Image) -> PackedFloat32Array:
	var h := PackedFloat32Array()
	h.resize(n * n)
	var dark := Color(0.20, 0.19, 0.18)
	var mid := Color(0.36, 0.35, 0.33)
	var light := Color(0.55, 0.53, 0.50)
	var warm := Color(0.48, 0.42, 0.36)
	for y in n:
		var fy := float(y) / float(n)
		for x in n:
			var fx := float(x) / float(n)
			var w1 := (_fbm(fx, fy, 4, 101, 3) - 0.5) * 0.7
			var w2 := (_fbm(fx, fy, 4, 113, 3) - 0.5) * 0.7
			var ridge := 1.0 - absf(_fbm(fx + w1, fy + w2, 8, 17, 6) - 0.5) * 2.0
			ridge = pow(ridge, 1.6)
			var strata := absf(sin((fy + w1 * 0.6) * PI * 7.0))
			var grain := _fbm(fx, fy, 72, 23, 4)
			var crack := clampf(1.0 - absf(_fbm(fx + w2, fy + w1, 6, 37, 4) - 0.5) * 9.0, 0.0, 1.0)
			var hh := ridge * 0.55 + strata * 0.2 + grain * 0.25
			h[y * n + x] = hh
			var col := _mix(dark, mid, clampf(hh * 1.4, 0.0, 1.0))
			col = _mix(col, light, clampf((ridge - 0.55) * 2.4, 0.0, 1.0))
			col = _mix(col, warm, clampf((grain - 0.55) * 1.6, 0.0, 0.5))
			col = _mix(col, Color(0.08, 0.08, 0.08), crack * 0.6)
			col.a = clampf(0.88 - crack * 0.1 + grain * 0.06, 0.74, 0.95)
			albedo.set_pixel(x, y, col)

	return h

## Snow: soft drifts, faint sastrugi, subtle blue shading in the hollows.
func _gen_snow(n: int, albedo: Image) -> PackedFloat32Array:
	var h := PackedFloat32Array()
	h.resize(n * n)
	var hollow := Color(0.76, 0.81, 0.90)
	var mid := Color(0.87, 0.90, 0.95)
	var crest := Color(0.96, 0.97, 1.0)
	for y in n:
		var fy := float(y) / float(n)
		for x in n:
			var fx := float(x) / float(n)
			var drift := _warped_fbm(fx, fy, 6, 5, 5, 1.0)
			var sastrugi := absf(sin((fx * 0.2 + fy + (_fbm(fx, fy, 4, 61, 3) - 0.5) * 0.5) * PI * 9.0))
			var grain := _fbm(fx, fy, 90, 87, 3)
			var hh := drift * 0.62 + pow(sastrugi, 0.8) * 0.22 + grain * 0.16
			h[y * n + x] = hh
			var col := _mix(hollow, mid, clampf(hh * 1.5, 0.0, 1.0))
			col = _mix(col, crest, clampf((hh - 0.6) * 2.4, 0.0, 1.0))
			col.a = clampf(0.62 + (grain - 0.5) * 0.08, 0.55, 0.72)
			albedo.set_pixel(x, y, col)

	return h