class_name WorldGen
extends RefCounted
## Deterministic (seeded) world generator. Produces:
##  - natural terrain height function (also used for the far horizon terrain at runtime)
##  - processed roads (spline -> meander -> resample -> terrain profile -> grade limit -> bridges/tunnels/banking)
##  - carved heightmap (cuttings, embankments, junction pads, tunnel portal holes)
##  - surface / region / road-distance maps and a minimap image
## Run offline by tools/bake_world.gd; the runtime loads the baked files (WorldData).

const L := preload("res://scripts/world/world_layout.gd")

const CELL := 2.0
const N := 2049                      # heightmap samples per side (covers [-2048, 2048])
const MAP_N := 1025                  # 4 m maps (surface, road distance)
const REG_N := 513                   # 8 m region weight map
const DS := 3.0                      # road sample spacing (m)
const RIVER_CHORD := 40.0            # spacing of the smoothed river centreline (m)
const RIVER_BANK := 16.0             # channel half width at the bank top (m)
const RIVER_FREEBOARD := 1.8         # water stays this far below the lowest natural ground beside the channel
const TUBE_PRE := 2                  # a tunnel tube spans samples [first - TUBE_PRE, last + 1 + TUBE_POST] of a
const TUBE_POST := 1                 # tunnel-flagged run (RoadBuilder builds the tube over the same range)
const TUBE_COVER := 10.0             # terrain over a tunnel tube: at least this far above the road

var n_hills := FastNoiseLite.new()
var n_detail := FastNoiseLite.new()
var n_ridge := FastNoiseLite.new()
var n_warp := FastNoiseLite.new()
var n_mesa := FastNoiseLite.new()
var n_meander := FastNoiseLite.new()
var n_coast := FastNoiseLite.new()

var heights := PackedFloat32Array()
var natural := PackedFloat32Array()
var surface_map := PackedByteArray()
var road_dist := PackedByteArray()
var region_rgba := PackedByteArray()
var holes := {}
var roads: Array = []                # Array[Dictionary]
var junctions: Array = []
var lake_levels: Array = []
var _canyons: Array = []            # Array of {pts: PackedVector2Array, floor: PackedFloat32Array, half_floor, half_top}
var _river_pts := PackedVector2Array()
var _river_y := PackedFloat32Array()
var _river_box := Rect2()
var _skip_lakes := false
var log_lines: PackedStringArray = []


func _init() -> void:
	var s := L.SEED
	n_hills.seed = s
	n_hills.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n_hills.fractal_type = FastNoiseLite.FRACTAL_FBM
	n_hills.fractal_octaves = 4
	n_hills.frequency = 1.0 / 750.0
	n_detail.seed = s + 1
	n_detail.noise_type = FastNoiseLite.TYPE_SIMPLEX
	n_detail.fractal_type = FastNoiseLite.FRACTAL_FBM
	n_detail.fractal_octaves = 3
	n_detail.frequency = 1.0 / 90.0
	n_ridge.seed = s + 2
	n_ridge.noise_type = FastNoiseLite.TYPE_SIMPLEX
	n_ridge.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	n_ridge.fractal_octaves = 4
	n_ridge.frequency = 1.0 / 950.0
	n_warp.seed = s + 3
	n_warp.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n_warp.frequency = 1.0 / 1400.0
	n_mesa.seed = s + 4
	n_mesa.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n_mesa.fractal_type = FastNoiseLite.FRACTAL_FBM
	n_mesa.fractal_octaves = 2
	n_mesa.frequency = 1.0 / 520.0
	n_meander.seed = s + 5
	n_meander.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n_meander.fractal_type = FastNoiseLite.FRACTAL_NONE
	n_meander.frequency = 1.0
	n_coast.seed = s + 6
	n_coast.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n_coast.fractal_type = FastNoiseLite.FRACTAL_FBM
	n_coast.fractal_octaves = 3
	n_coast.frequency = 1.0 / 420.0
	_setup_features()


func _setup_features() -> void:
	# Canyons: Ochre Gorge (ring road descends through it) and Redwall Canyon (dirt trail).
	_canyons.append({"pts": PackedVector2Array([Vector2(1700, -160), Vector2(1660, -40), Vector2(1520, 160), Vector2(1440, 380), Vector2(1470, 620), Vector2(1600, 820), Vector2(1660, 980)]),
		"floor": PackedFloat32Array([96.0, 88.0, 74.0, 62.0, 52.0, 44.0, 40.0]), "half_floor": 26.0, "half_top": 95.0})
	_canyons[0]["box"] = _poly_box(_canyons[0]["pts"], 100.0)
	_canyons.append({"pts": PackedVector2Array([Vector2(960, -380), Vector2(900, -230), Vector2(760, -20), Vector2(700, 260), Vector2(820, 520), Vector2(940, 720), Vector2(980, 860)]),
		"floor": PackedFloat32Array([92.0, 84.0, 66.0, 58.0, 54.0, 48.0, 44.0]), "half_floor": 20.0, "half_top": 75.0})
	_canyons[1]["box"] = _poly_box(_canyons[1]["pts"], 80.0)
	_setup_river()


## River Wend: a smoothed centreline through the authored control points (shared by the terrain carve, the
## water ribbon, water_level_at and dressing), with water levels taken from the terrain: never above the
## authored level, always RIVER_FREEBOARD below the lowest natural ground across the channel, never rising
## downstream. So the river always runs in its valley instead of on a perched embankment.
func _setup_river() -> void:
	var ctrl := PackedVector2Array()
	var ctrl_y := PackedFloat32Array()
	for p: Array in L.RIVER:
		ctrl.append(Vector2(p[0], p[1]))
		ctrl_y.append(p[2])
	var pts := _resample(_catmull_rom(ctrl, false, 4.0), false, RIVER_CHORD)
	var n := pts.size()
	var lvl := PackedFloat32Array()
	lvl.resize(n)
	# natural_height() skips the river while _river_box is empty, and lakes are far away.
	_river_box = Rect2()
	_skip_lakes = true
	for i in n:
		var t := (pts[mini(i + 1, n - 1)] - pts[maxi(i - 1, 0)]).normalized()
		var nrm := Vector2(-t.y, t.x)
		var low := INF
		for off: float in [-48.0, -36.0, -26.0, -17.0, -9.0, 0.0, 9.0, 17.0, 26.0, 36.0, 48.0]:
			var q := pts[i] + nrm * off
			low = minf(low, natural_height(q.x, q.y))
		lvl[i] = minf(polyline_query(pts[i], ctrl, ctrl_y).y, low - RIVER_FREEBOARD)
	_skip_lakes = false
	for i in range(1, n):
		lvl[i] = minf(lvl[i], lvl[i - 1])
	for i in n:
		lvl[i] = maxf(lvl[i], L.SEA_LEVEL - 0.5)
	_river_pts = pts
	_river_y = lvl
	_river_box = _poly_box(pts, 170.0)


## River query: Vector2(distance to the centreline, water level there); INF distance outside the river area.
func river_query(p: Vector2) -> Vector2:
	if not _river_box.has_point(p):
		return Vector2(INF, 0.0)
	return polyline_query(p, _river_pts, _river_y)


## Channel cross-section height at distance d from the centreline (water level y): bed, then the bank slope
## up to the bank top (y + 1.2) at RIVER_BANK.
static func river_channel(d: float, y: float) -> float:
	return lerpf(y - 2.6, y + 1.2, smooth(5.0, RIVER_BANK, d))


static func _poly_box(pts: PackedVector2Array, margin: float) -> Rect2:
	var r := Rect2(pts[0], Vector2.ZERO)
	for p in pts:
		r = r.expand(p)
	return r.grow(margin)


static func smooth(e0: float, e1: float, x: float) -> float:
	var t := clampf((x - e0) / (e1 - e0), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


## Distance from p to a polyline, returning Vector2(distance, interpolated value along `vals`).
static func polyline_query(p: Vector2, pts: PackedVector2Array, vals: PackedFloat32Array) -> Vector2:
	var best := INF
	var best_v := 0.0
	for i in pts.size() - 1:
		var a := pts[i]
		var b := pts[i + 1]
		var ab := b - a
		var t := clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
		var d := p.distance_squared_to(a + ab * t)
		if d < best:
			best = d
			best_v = lerpf(vals[i], vals[i + 1], t)
	return Vector2(sqrt(best), best_v)


func coast_z(x: float) -> float:
	# Coastline (z of the shore) varying along x; > coast_z is sea.
	var c := 1590.0
	c = lerpf(c, 1500.0, smooth(-900.0, -300.0, x))      # central coast
	c = lerpf(c, 1470.0, smooth(300.0, 900.0, x))        # south-east cliffs
	c -= 55.0 * exp(-pow((x - 1080.0) / 160.0, 2.0))      # Gullhaven cove
	c += 110.0 * exp(-pow((x - 1790.0) / 120.0, 2.0))     # lighthouse headland
	c -= 210.0 * exp(-pow((x + 720.0) / 150.0, 2.0))      # Wend estuary mouth
	c += n_coast.get_noise_2d(x, 0.0) * 35.0
	return c


func cliff_factor(x: float) -> float:
	var f := smooth(-200.0, 500.0, x)
	f *= 1.0 - 0.85 * exp(-pow((x - 1080.0) / 200.0, 2.0))  # cove has a gentle beach
	return f


## Natural (uncarved) terrain height at world (x, z). `spur` adds the tunnel spur ridge.
func natural_height(x: float, z: float, spur := true) -> float:
	var wx := x + n_warp.get_noise_2d(x, z) * 220.0
	var wz := z + n_warp.get_noise_2d(z + 7000.0, x - 3000.0) * 220.0
	var hills := n_hills.get_noise_2d(x, z)
	var m_mtn := smooth(-280.0, -1080.0, wz) * (1.0 - smooth(-200.0, 420.0, wx))
	var m_des := smooth(180.0, 640.0, wx) * (1.0 - smooth(1000.0, 1300.0, wz))
	# Vale: rolling farmland hills.
	var h_vale := 30.0 + hills * 15.0 + n_detail.get_noise_2d(x, z) * 1.6
	# Highlands: ridged peaks rising to the north edge.
	var ridge := n_ridge.get_noise_2d(x, z) * 0.5 + 0.5
	var north := smooth(-450.0, -2000.0, wz)
	var peaks := smooth(-1300.0, -1950.0, wz)
	var h_mtn := 62.0 + north * 125.0 + ridge * ridge * (60.0 + 280.0 * peaks) + hills * 22.0 + n_detail.get_noise_2d(x, z) * 3.0
	# Desert plateau with terraced mesas.
	var mn := n_mesa.get_noise_2d(x, z)
	var h_des := 94.0 + hills * 6.0 + smooth(0.30, 0.36, mn) * 48.0 + smooth(0.55, 0.6, mn) * 30.0 + n_detail.get_noise_2d(x, z) * 1.2
	var h := lerpf(h_vale, h_mtn, m_mtn)
	h = lerpf(h, h_des, m_des * (1.0 - m_mtn))
	var p := Vector2(x, z)
	# Canyons in the plateau.
	for c: Dictionary in _canyons:
		if not (c["box"] as Rect2).has_point(p):
			continue
		var q := polyline_query(p, c["pts"], c["floor"])
		var top: float = c["half_top"]
		if q.x < top:
			var f := smooth(float(c["half_floor"]), top, q.x)
			f = f * f
			h = lerpf(q.y, maxf(h, q.y), f)
	# River valley: floodplain easing down to the bank top (or a low levee where the ground is lower), then
	# the channel; continuous at the bank so no wall forms.
	var rq := river_query(p)
	if rq.x < 160.0:
		var bank := rq.y + 1.2
		if h >= bank:
			h = lerpf(minf(h, bank + 3.0 * smooth(RIVER_BANK, 70.0, rq.x)), h, smooth(RIVER_BANK, 160.0, rq.x))
		else:
			h = lerpf(bank, h, smooth(RIVER_BANK, 48.0, rq.x))
		if rq.x < RIVER_BANK:
			h = river_channel(rq.x, rq.y)
	# Mirror Lake basin.
	for lk: Dictionary in L.LAKES:
		if _skip_lakes:
			break
		var lp := Vector2(lk["pos"][0], lk["pos"][1])
		var d := p.distance_to(lp)
		var r: float = lk["radius"]
		if d < r * 1.6:
			var level: float = lake_level(0)
			var t := smooth(r * 0.55, r * 1.25, d)
			h = lerpf(level - 6.0, maxf(h, level + 1.5), t)
	# Coast hills uplift on the south-east, then beaches / cliffs to the sea.
	h += 22.0 * smooth(200.0, 700.0, x) * smooth(900.0, 1250.0, z) * (1.0 - smooth(1350.0, 1500.0, z))
	var cz := coast_z(x)
	var dz := z - cz
	if dz > -420.0:
		var cliff := cliff_factor(x)
		var beach_h := h
		if dz < 0.0:
			beach_h = lerpf(1.6 + n_detail.get_noise_2d(x * 2.0, z * 2.0) * 0.6, h, smooth(0.0, 380.0, -dz))
		else:
			beach_h = 1.2 - dz * 0.09
		var cliff_h := h
		if dz > -28.0:
			cliff_h = lerpf(h, -7.0 - maxf(dz, 0.0) * 0.06, smooth(-28.0, 6.0, dz))
		h = lerpf(beach_h, cliff_h, cliff)
		if dz > 0.0:
			h = minf(h, -1.2 - dz * 0.07)
		h = maxf(h, -32.0)
		# The estuary channel stays open through the beach.
		if rq.x < RIVER_BANK:
			h = minf(h, river_channel(rq.x, rq.y))
	# Map edge: natural walls to the west / east / north keep the play area enclosed.
	h += 140.0 * smooth(1900.0, 2300.0, -x) + 120.0 * smooth(1920.0, 2300.0, x) * (1.0 - smooth(1300.0, 1700.0, z))
	h += 80.0 * smooth(1950.0, 2350.0, -z)
	if spur:
		var sp: Array = L.TUNNEL_SPUR
		var sd := p.distance_to(Vector2(sp[0], sp[1]))
		if sd < sp[2]:
			var k := 1.0 - sd / float(sp[2])
			h += float(sp[3]) * k * k * (3.0 - 2.0 * k)
	return h


var _lake_cache: Array = []


func lake_level(i: int) -> float:
	if _lake_cache.size() > i:
		return _lake_cache[i]
	_lake_cache.resize(L.LAKES.size())
	for j in L.LAKES.size():
		_lake_cache[j] = 0.0
	# Level = lowest natural rim height minus a margin (sampled without the lake carve).
	for j in L.LAKES.size():
		var lk: Dictionary = L.LAKES[j]
		var c := Vector2(lk["pos"][0], lk["pos"][1])
		var r: float = lk["radius"]
		var lowest := INF
		for k in 48:
			var a := TAU * k / 48.0
			var q := c + Vector2(cos(a), sin(a)) * r * 1.3
			lowest = minf(lowest, _height_no_lake(q.x, q.y))
		_lake_cache[j] = lowest - 1.0
	return _lake_cache[i]


func _height_no_lake(x: float, z: float) -> float:
	_skip_lakes = true
	var h := natural_height(x, z)
	_skip_lakes = false
	return h


func region_weights(x: float, z: float) -> Color:
	var wx := x + n_warp.get_noise_2d(x, z) * 220.0
	var wz := z + n_warp.get_noise_2d(z + 7000.0, x - 3000.0) * 220.0
	var m_mtn := smooth(-280.0, -1080.0, wz) * (1.0 - smooth(-200.0, 420.0, wx))
	var m_des := smooth(180.0, 640.0, wx) * (1.0 - smooth(1000.0, 1300.0, wz)) * (1.0 - m_mtn)
	var m_coast := smooth(-420.0, -150.0, z - coast_z(x)) * (1.0 - m_mtn)
	m_des *= 1.0 - m_coast
	var m_vale := maxf(1.0 - m_mtn - m_des - m_coast, 0.0)
	return Color(m_vale, m_mtn, m_des, m_coast)


# =================================================================== bake

func generate() -> void:
	var t0 := Time.get_ticks_msec()
	lake_level(0)
	_gen_natural()
	_log("natural terrain %d ms" % (Time.get_ticks_msec() - t0))
	t0 = Time.get_ticks_msec()
	_build_roads()
	_log("roads %d ms" % (Time.get_ticks_msec() - t0))
	t0 = Time.get_ticks_msec()
	_carve()
	_log("carve %d ms" % (Time.get_ticks_msec() - t0))
	t0 = Time.get_ticks_msec()
	_gen_maps()
	_log("maps %d ms" % (Time.get_ticks_msec() - t0))


func _log(s: String) -> void:
	log_lines.append(s)
	print("[worldgen] ", s)


func _gen_natural() -> void:
	natural.resize(N * N)
	var half := L.HALF
	for j in N:
		var z := -half + j * CELL
		var row := j * N
		for i in N:
			natural[row + i] = natural_height(-half + i * CELL, z)
	heights = natural.duplicate()


func sample_natural(x: float, z: float) -> float:
	return _bilinear(natural, x, z)


func sample_height(x: float, z: float) -> float:
	return _bilinear(heights, x, z)


func _bilinear(arr: PackedFloat32Array, x: float, z: float) -> float:
	var fx := clampf((x + L.HALF) / CELL, 0.0, N - 1.001)
	var fz := clampf((z + L.HALF) / CELL, 0.0, N - 1.001)
	var i := int(fx)
	var j := int(fz)
	var tx := fx - i
	var tz := fz - j
	var a := arr[j * N + i]
	var b := arr[j * N + i + 1]
	var c := arr[(j + 1) * N + i]
	var d := arr[(j + 1) * N + i + 1]
	return lerpf(lerpf(a, b, tx), lerpf(c, d, tx), tz)


# ------------------------------------------------------------------- roads

func _road_def(id: String) -> Dictionary:
	for r: Dictionary in roads:
		if r["id"] == id:
			return r
	return {}


func _build_roads() -> void:
	roads.clear()
	junctions.clear()
	for def: Dictionary in L.ROADS:
		var r := _process_road(def)
		roads.append(r)
		_log("road %-14s %6.0f m  bridges %d  tunnels %d" % [r["id"], r["length"], r["n_bridges"], r["n_tunnels"]])
	# Parents carry no banking across a junction mouth (the child road meets a flat cross-section).
	for j: Dictionary in junctions:
		var parent := _road_def(j["parent"])
		var bank: PackedFloat32Array = parent["bank"]
		var n := bank.size()
		var c: int = j["parent_index"]
		var span := int(60.0 / DS)
		for o in range(-span, span + 1):
			var idx := c + o
			if parent["loop"]:
				idx = posmod(idx, n)
			elif idx < 0 or idx >= n:
				continue
			bank[idx] *= smooth(0.45, 1.0, absf(float(o)) / span)
		parent["bank"] = bank
	for r: Dictionary in roads:
		if not (r["j_start"] as Dictionary).is_empty():
			_junction_tilt(r, r["j_start"], 0)
		if not (r["j_end"] as Dictionary).is_empty():
			_junction_tilt(r, r["j_end"], 1)


func _nearest_sample(r: Dictionary, p: Vector2) -> int:
	var pos: PackedVector3Array = r["pos"]
	var best := 0
	var bd := INF
	for i in pos.size():
		var d := Vector2(pos[i].x, pos[i].z).distance_squared_to(p)
		if d < bd:
			bd = d
			best = i
	return best


func _process_road(def: Dictionary) -> Dictionary:
	var cls: int = def["class"]
	var info: Dictionary = L.CLASS_INFO[cls]
	var loop: bool = def.get("loop", false)
	var ctrl := PackedVector2Array()
	for p: Array in def["pts"]:
		ctrl.append(Vector2(p[0], p[1]))
	# Snap junction endpoints onto parent roads.
	var j_start := {}
	var j_end := {}
	if def.has("from"):
		var parent := _road_def(def["from"])
		if not parent.is_empty():
			var idx := _nearest_sample(parent, ctrl[0])
			var pp: Vector3 = parent["pos"][idx]
			ctrl[0] = Vector2(pp.x, pp.z)
			j_start = {"road": def["from"], "index": idx, "y": pp.y, "apron": float(parent["width"]) * 0.5 + float(parent["shoulder"]) + 6.0}
	if def.has("to"):
		var parent2 := _road_def(def["to"])
		if not parent2.is_empty():
			var idx2 := _nearest_sample(parent2, ctrl[ctrl.size() - 1])
			var pp2: Vector3 = parent2["pos"][idx2]
			ctrl[ctrl.size() - 1] = Vector2(pp2.x, pp2.z)
			j_end = {"road": def["to"], "index": idx2, "y": pp2.y, "apron": float(parent2["width"]) * 0.5 + float(parent2["shoulder"]) + 6.0}
	# Dense centripetal Catmull-Rom.
	var dense := _catmull_rom(ctrl, loop, 1.0)
	# Meander (perpendicular noise offset, suppressed on tight curves and near ends).
	var mea: Array = def.get("meander", [0.0, 0.0])
	if float(mea[0]) > 0.0:
		dense = _meander(dense, loop, float(mea[0]), float(mea[1]), def["id"].hash())
	var pts2 := _resample(dense, loop, DS)
	var n := pts2.size()
	# Terrain profile (without the tunnel spur so the road stays low and tunnels through it).
	var terr := PackedFloat32Array()
	var minh := PackedFloat32Array()
	terr.resize(n)
	minh.resize(n)
	# Water clearance only where the road surface is over the river channel (a crossing): a road running
	# beside the river stays on its bank. The sea needs bridges too.
	var over_water := float(info["width"]) * 0.5 + float(info["shoulder"]) + RIVER_BANK + 1.0
	var run_min := INF
	for i in n:
		var p := pts2[i]
		terr[i] = natural_height(p.x, p.y, false)
		minh[i] = -INF
		var rq := river_query(p)
		if rq.x < over_water:
			minh[i] = maxf(minh[i], rq.y + 6.5 - rq.x * 0.03)
			run_min = minf(run_min, rq.x)
		if (rq.x >= over_water or i == n - 1) and run_min < INF:
			# A run over the channel that never reaches the centreline runs along the river, not across it.
			if run_min > 6.0:
				_log("WARNING road %s runs along the river inside its channel near s=%.0f (%.1f m from the centre)" % [def["id"], i * DS, run_min])
			run_min = INF
		if terr[i] < L.SEA_LEVEL + 0.3:
			# Over the sea: bridge clearance.
			minh[i] = maxf(minh[i], 9.0 if cls != L.RoadClass.STREET else 2.6)
		elif terr[i] < 2.5:
			# Dry beach: stay just above the waterline instead of riding a viaduct along the sand.
			minh[i] = maxf(minh[i], L.SEA_LEVEL + 1.0)
	var zone := PackedByteArray()
	zone.resize(n)
	for i in n:
		for tz: Array in L.TUNNEL_ZONES:
			if pts2[i].distance_to(Vector2(tz[0], tz[1])) < float(tz[2]):
				zone[i] = 1
	var win := int(float(info["smooth"]) / DS)
	var prof := _smooth_profile(terr, win, loop)
	for i in n:
		prof[i] = maxf(prof[i], minh[i])
	prof = _smooth_profile(prof, maxi(win / 3, 2), loop)
	for i in n:
		prof[i] = maxf(prof[i], minh[i] - 0.5)

	# Junction fixed heights.
	# Junction aprons: the child road follows the parent's surface while the two overlap and stays level
	# a few metres past the parent's edge, so no step forms where they meet. Anchors = inner end of each apron (+dir).
	var fixed := {}
	var anchors: Array = []
	var child_hw := float(info["width"]) * 0.5
	if not j_start.is_empty():
		anchors.append([_junction_apron(pts2, j_start, 1, fixed, child_hw), 1])
	if not j_end.is_empty():
		anchors.append([_junction_apron(pts2, j_end, -1, fixed, child_hw), -1])
	for an: Array in anchors:
		var k: int = an[0]
		var dirn: int = an[1]
		var y: float = fixed[k]
		var blend := int(70.0 / DS)
		for o in blend:
			var idx := k + o * dirn
			if idx < 0 or idx >= n:
				continue
			prof[idx] = lerpf(y, prof[idx], smooth(0.0, 1.0, float(o) / blend))
	prof = _grade_limit(prof, float(info["grade"]) * DS, loop, fixed)
	# Round off grade changes (vertical curves) so dips/crests are not sharp V shapes.
	prof = _smooth_profile(prof, 8, loop)
	prof = _grade_limit(prof, float(info["grade"]) * DS * 1.05, loop, fixed)
	# The fixed junction heights may leave a residual step next to the junction when the two ends are
	# further apart in height than the grade allows; spread any such step over 60 m.
	for an2: Array in anchors:
		var k: int = an2[0]
		var dirn2: int = an2[1]
		var span := int(60.0 / DS)
		var inner := k + span * dirn2
		if inner < 0 or inner >= n:
			continue
		var y0: float = fixed[k]
		var y1 := prof[inner]
		var lin := true
		for o in range(1, span):
			var idx := k + o * dirn2
			var want := lerpf(y0, y1, float(o) / span)
			if absf(prof[idx] - want) > 0.25:
				lin = false
		if not lin:
			for o in range(1, span):
				var idx2 := k + o * dirn2
				var t := float(o) / span
				prof[idx2] = lerpf(lerpf(y0, y1, t), prof[idx2], smooth(0.0, 1.0, t))
	# Final positions + flags.
	var pos := PackedVector3Array()
	pos.resize(n)
	for i in n:
		pos[i] = Vector3(pts2[i].x, prof[i], pts2[i].y)
	var flags := PackedByteArray()
	flags.resize(n)
	var tunnel_raw := PackedByteArray()
	tunnel_raw.resize(n)
	# Around a river crossing the bridge continues until the deck is within 3.5 m of the floodplain, so the
	# approach embankments end well clear of the channel.
	var near_cross := PackedByteArray()
	near_cross.resize(n)
	for i in n:
		if river_query(pts2[i]).x < over_water:
			for o in range(-20, 21):
				var k := i + o
				if loop:
					k = posmod(k, n)
				elif k < 0 or k >= n:
					continue
				near_cross[k] = 1
	for i in n:
		var real_terr := natural_height(pts2[i].x, pts2[i].y, true)
		var f := 0
		if prof[i] - terr[i] > 12.0 or (minh[i] > -INF and terr[i] < prof[i] - 4.0) or (near_cross[i] == 1 and prof[i] - terr[i] > 3.5):
			f |= 1  # bridge
		if zone[i] == 1 and real_terr - prof[i] > 16.0:
			f |= 2  # tunnel
		flags[i] = f
	flags = _clean_flags(flags, 1, int(24.0 / DS), int(36.0 / DS), loop)
	flags = _clean_flags(flags, 2, int(60.0 / DS), int(30.0 / DS), loop)
	for i in n:
		if flags[i] & 2:
			flags[i] = 2  # a tunnel sample is never also a bridge sample
	# Bank angle from curvature.
	var bank := PackedFloat32Array()
	bank.resize(n)
	var limit_ms := float(info["limit"]) / 3.6
	for i in n:
		var a := pts2[(i - 1 + n) % n] if loop or i > 0 else pts2[i]
		var b := pts2[i]
		var c := pts2[(i + 1) % n] if loop or i < n - 1 else pts2[i]
		var k := _curvature(a, b, c)
		bank[i] = clampf(-k * limit_ms * limit_ms / 9.81 * 0.35, -0.07, 0.07)
		if flags[i] & 2:
			bank[i] = 0.0
	bank = _smooth_profile(bank, int(40.0 / DS), loop)
	for k2: int in fixed:
		var bl := int(40.0 / DS)
		for o in bl:
			var idx2 := k2 + o if k2 == 0 else k2 - o
			if idx2 >= 0 and idx2 < n:
				bank[idx2] *= smooth(0.0, 1.0, float(o) / bl)
	var length := (n if loop else n - 1) * DS
	# Runs of each kind (a run that starts at sample 0 counts too; a loop's wrapping run counts once).
	var nb := 0
	var nt := 0
	for i in n:
		var prev := flags[(i - 1 + n) % n] if loop or i > 0 else 0
		if (flags[i] & 1) and not (prev & 1):
			nb += 1
		if (flags[i] & 2) and not (prev & 2):
			nt += 1
	if nb == 0 and (flags[0] & 1):
		nb = 1
	for k: int in [0, n - 1]:
		var dead := (j_start.is_empty() if k == 0 else j_end.is_empty()) and not loop
		if dead and (flags[k] & 1):
			_log("WARNING road %s ends on a bridge deck without a junction (s=%.0f)" % [def["id"], k * DS])
	var r := {
		"id": def["id"], "name": def["name"], "class": cls, "loop": loop,
		"width": info["width"], "lanes": info["lanes"], "shoulder": info["shoulder"],
		"limit": info["limit"], "surface": String(info["surface"]), "traffic": info["traffic"], "marking": info["marking"],
		"pos": pos, "bank": bank, "flags": flags, "length": length, "n_bridges": nb, "n_tunnels": nt,
		"j_start": j_start, "j_end": j_end,
	}
	if not j_start.is_empty():
		junctions.append({"parent": j_start["road"], "parent_index": j_start["index"], "child": def["id"], "child_end": 0})
	if not j_end.is_empty():
		junctions.append({"parent": j_end["road"], "parent_index": j_end["index"], "child": def["id"], "child_end": 1})
	return r


## Fixes the child's heights from its junction end inward: each sample takes the parent's centre height at the
## nearest parent point while the child still overlaps the parent (acute junctions run alongside it for a while,
## so a single level apron would leave the parent's grade as a lip). Returns the index of the last fixed sample.
func _junction_apron(pts: PackedVector2Array, j: Dictionary, dirn: int, fixed: Dictionary, child_hw: float) -> int:
	var parent := _road_def(j["road"])
	var ppos: PackedVector3Array = parent["pos"]
	var pn := ppos.size()
	var ploop: bool = parent["loop"]
	var reach := float(parent["width"]) * 0.5 + float(parent["shoulder"]) + child_hw + 4.0
	var n := pts.size()
	var c: int = j["index"]
	var win := int(150.0 / DS)
	var last := 0
	for o in mini(n - 1, int(150.0 / DS)):
		var i := o if dirn > 0 else n - 1 - o
		var p := pts[i]
		var bd := INF
		var by := float(j["y"])
		for w in range(-win, win + 1):
			var k := c + w
			if ploop:
				k = posmod(k, pn)
			elif k < 0 or k >= pn - 1:
				continue
			var a := ppos[k]
			var b := ppos[(k + 1) % pn]
			var ab := Vector2(b.x - a.x, b.z - a.z)
			var t := clampf((p - Vector2(a.x, a.z)).dot(ab) / maxf(ab.length_squared(), 1e-6), 0.0, 1.0)
			var d := p.distance_to(Vector2(a.x, a.z) + ab * t)
			if d < bd:
				bd = d
				by = lerpf(a.y, b.y, t)
		if bd > reach and o * DS > float(j["apron"]):
			break
		fixed[i] = by
		last = o
	j["apron_n"] = last + 1
	return last if dirn > 0 else n - 1 - last


## Child roads tilt their cross-section across the junction apron so it lies in the parent's surface plane
## (a side road meeting a graded parent square-on otherwise pokes up on the uphill side), then blend back.
func _junction_tilt(child: Dictionary, j: Dictionary, end: int) -> void:
	var parent := _road_def(j["road"])
	if parent.is_empty():
		return
	var ppos: PackedVector3Array = parent["pos"]
	var pbank: PackedFloat32Array = parent["bank"]
	var pn := ppos.size()
	var ploop: bool = parent["loop"]
	var cpos: PackedVector3Array = child["pos"]
	var cbank: PackedFloat32Array = child["bank"]
	var n := cpos.size()
	var apron_n: int = j.get("apron_n", int(ceil(float(j["apron"]) / DS)))
	var blend := int(24.0 / DS)
	var c: int = j["index"]
	var win := int(150.0 / DS)
	for o in mini(apron_n + blend, n):
		var i := o if end == 0 else n - 1 - o
		var p := Vector2(cpos[i].x, cpos[i].z)
		var bd := INF
		var t2 := Vector2.RIGHT
		var g := 0.0
		var bp := 0.0
		for w in range(-win, win + 1):
			var k := c + w
			if ploop:
				k = posmod(k, pn)
			elif k < 0 or k >= pn - 1:
				continue
			var a3 := ppos[k]
			var b3 := ppos[(k + 1) % pn]
			var a := Vector2(a3.x, a3.z)
			var ab := Vector2(b3.x, b3.z) - a
			var l2 := maxf(ab.length_squared(), 1e-6)
			var t := clampf((p - a).dot(ab) / l2, 0.0, 1.0)
			var d := p.distance_to(a + ab * t)
			if d < bd:
				bd = d
				t2 = ab / sqrt(l2)
				g = (b3.y - a3.y) / sqrt(l2)
				bp = lerpf(pbank[k], pbank[(k + 1) % pn], t)
		var i0 := maxi(i - 1, 0)
		var i1 := mini(i + 1, n - 1)
		var tc := Vector2(cpos[i1].x - cpos[i0].x, cpos[i1].z - cpos[i0].z).normalized()
		var rc := Vector2(-tc.y, tc.x)
		var rp := Vector2(-t2.y, t2.x)
		var tilt := g * t2.dot(rc) + bp * rp.dot(rc)
		var wgt := 1.0 if o < apron_n else 1.0 - smooth(0.0, 1.0, float(o - apron_n) / blend)
		cbank[i] = lerpf(cbank[i], tilt, wgt)
	child["bank"] = cbank


static func _curvature(a: Vector2, b: Vector2, c: Vector2) -> float:
	var ab := b - a
	var bc := c - b
	var cross := ab.x * bc.y - ab.y * bc.x
	var den := ab.length() * bc.length() * (a.distance_to(c))
	if den < 0.0001:
		return 0.0
	return 2.0 * cross / den


func _catmull_rom(ctrl: PackedVector2Array, loop: bool, step: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	var n := ctrl.size()
	var segs := n if loop else n - 1
	for i in segs:
		var p0 := ctrl[(i - 1 + n) % n] if (loop or i > 0) else ctrl[0] * 2.0 - ctrl[1]
		var p1 := ctrl[i]
		var p2 := ctrl[(i + 1) % n]
		var p3: Vector2
		if loop or i + 2 < n:
			p3 = ctrl[(i + 2) % n]
		else:
			p3 = p2 * 2.0 - p1
		var t0 := 0.0
		var t1 := t0 + pow(p0.distance_to(p1), 0.5)
		var t2 := t1 + pow(p1.distance_to(p2), 0.5)
		var t3 := t2 + pow(p2.distance_to(p3), 0.5)
		var seg_len := p1.distance_to(p2)
		var steps := maxi(int(seg_len / step), 2)
		for s in steps:
			var t := lerpf(t1, t2, float(s) / steps)
			var a1 := p0 * ((t1 - t) / (t1 - t0)) + p1 * ((t - t0) / (t1 - t0))
			var a2 := p1 * ((t2 - t) / (t2 - t1)) + p2 * ((t - t1) / (t2 - t1))
			var a3 := p2 * ((t3 - t) / (t3 - t2)) + p3 * ((t - t2) / (t3 - t2))
			var b1 := a1 * ((t2 - t) / (t2 - t0)) + a2 * ((t - t0) / (t2 - t0))
			var b2 := a2 * ((t3 - t) / (t3 - t1)) + a3 * ((t - t1) / (t3 - t1))
			out.append(b1 * ((t2 - t) / (t2 - t1)) + b2 * ((t - t1) / (t2 - t1)))
	if not loop:
		out.append(ctrl[n - 1])
	return out


func _meander(pts: PackedVector2Array, loop: bool, amp: float, wavelength: float, seed: int) -> PackedVector2Array:
	var n := pts.size()
	# arclength
	var s := PackedFloat32Array()
	s.resize(n)
	for i in range(1, n):
		s[i] = s[i - 1] + pts[i].distance_to(pts[i - 1])
	var total := s[n - 1]
	# curvature mask
	var mask := PackedFloat32Array()
	mask.resize(n)
	for i in n:
		var a := pts[maxi(i - 12, 0)] if not loop else pts[(i - 12 + n) % n]
		var c := pts[mini(i + 12, n - 1)] if not loop else pts[(i + 12) % n]
		var k := absf(_curvature(a, pts[i], c))
		mask[i] = 1.0 - smooth(1.0 / 380.0, 1.0 / 160.0, k)
		if not loop:
			mask[i] *= smooth(0.0, 90.0, s[i]) * smooth(0.0, 90.0, total - s[i])
	for i in n:
		for z: Array in L.NO_MEANDER_ZONES:
			var dz := pts[i].distance_to(Vector2(z[0], z[1]))
			mask[i] *= smooth(float(z[2]), float(z[2]) + 120.0, dz)
	mask = _erode(mask, 90, loop)
	mask = _smooth_profile(mask, 45, loop)
	var out := PackedVector2Array()
	out.resize(n)
	for i in n:
		var a := pts[(i - 1 + n) % n] if (loop or i > 0) else pts[i]
		var c := pts[(i + 1) % n] if (loop or i < n - 1) else pts[i]
		var t := (c - a).normalized()
		var nrm := Vector2(-t.y, t.x)
		var u := s[i] / wavelength
		if loop:
			# keep the offset periodic over the loop
			var ang := TAU * s[i] / total
			var rr := total / wavelength / TAU
			var off := n_meander.get_noise_2d(cos(ang) * rr + float(seed % 1000), sin(ang) * rr)
			out[i] = pts[i] + nrm * off * amp * 1.6 * mask[i]
		else:
			out[i] = pts[i] + nrm * n_meander.get_noise_2d(u, float(seed % 1000)) * amp * 1.6 * mask[i]
	return out


func _resample(pts: PackedVector2Array, loop: bool, step: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	var src := pts.duplicate()
	if loop:
		src.append(pts[0])
	out.append(src[0])
	var carry := 0.0
	for i in range(1, src.size()):
		var a := src[i - 1]
		var b := src[i]
		var seg := a.distance_to(b)
		var pos := step - carry
		while pos <= seg:
			out.append(a.lerp(b, pos / seg))
			pos += step
		carry = seg - (pos - step)
	if loop:
		# drop the duplicate closing point if it is too close to the start
		if out[out.size() - 1].distance_to(out[0]) < step * 0.5:
			out.remove_at(out.size() - 1)
	else:
		if out[out.size() - 1].distance_to(src[src.size() - 1]) > step * 0.3:
			out.append(src[src.size() - 1])
		else:
			out[out.size() - 1] = src[src.size() - 1]
	return out


static func _erode(v: PackedFloat32Array, half_win: int, loop: bool) -> PackedFloat32Array:
	var n := v.size()
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var m := v[i]
		for k in range(-half_win, half_win + 1, 3):
			var j := i + k
			if loop:
				j = posmod(j, n)
			elif j < 0 or j >= n:
				continue
			m = minf(m, v[j])
		out[i] = m
	return out


static func _smooth_profile(v: PackedFloat32Array, half_win: int, loop: bool) -> PackedFloat32Array:
	var n := v.size()
	if half_win <= 0 or n < 3:
		return v.duplicate()
	var out := PackedFloat32Array()
	out.resize(n)
	# prefix sums (with wrap for loops)
	var ext := PackedFloat32Array()
	var pad := half_win
	ext.resize(n + pad * 2)
	for i in ext.size():
		var k := i - pad
		if loop:
			k = posmod(k, n)
		else:
			k = clampi(k, 0, n - 1)
		ext[i] = v[k]
	var pre := PackedFloat64Array()
	pre.resize(ext.size() + 1)
	for i in ext.size():
		pre[i + 1] = pre[i] + ext[i]
	for i in n:
		var a := i
		var b := i + pad * 2 + 1
		out[i] = float((pre[b] - pre[a]) / float(b - a))
	return out


static func _grade_limit(v: PackedFloat32Array, max_step: float, loop: bool, fixed: Dictionary) -> PackedFloat32Array:
	var out := v.duplicate()
	var n := out.size()
	for it in 3:
		for k: int in fixed:
			out[k] = fixed[k]
		for i in range(1, n):
			out[i] = clampf(out[i], out[i - 1] - max_step, out[i - 1] + max_step)
		if loop:
			out[0] = clampf(out[0], out[n - 1] - max_step, out[n - 1] + max_step)
		for k: int in fixed:
			out[k] = fixed[k]
		for i in range(n - 2, -1, -1):
			out[i] = clampf(out[i], out[i + 1] - max_step, out[i + 1] + max_step)
		if loop:
			out[n - 1] = clampf(out[n - 1], out[0] - max_step, out[0] + max_step)
	for k: int in fixed:
		out[k] = fixed[k]
	return out


## Grade limit that only raises samples (keeps lower-bound constraints satisfied).
static func _raise_grade(v: PackedFloat32Array, max_step: float, loop: bool) -> PackedFloat32Array:
	var out := v.duplicate()
	var n := out.size()
	for it in 2:
		for i in range(1, n):
			out[i] = maxf(out[i], out[i - 1] - max_step)
		if loop:
			out[0] = maxf(out[0], out[n - 1] - max_step)
		for i in range(n - 2, -1, -1):
			out[i] = maxf(out[i], out[i + 1] - max_step)
		if loop:
			out[n - 1] = maxf(out[n - 1], out[0] - max_step)
	return out


static func _clean_flags(flags: PackedByteArray, bit: int, min_len: int, merge_gap: int, loop: bool) -> PackedByteArray:
	var n := flags.size()
	var f := flags.duplicate()
	# merge small gaps
	var i := 0
	while i < n:
		if not (f[i] & bit):
			var j := i
			while j < n and not (f[j] & bit):
				j += 1
			if i > 0 and j < n and (j - i) <= merge_gap:
				for k in range(i, j):
					f[k] |= bit
			i = j
		else:
			i += 1
	# remove short runs
	i = 0
	while i < n:
		if f[i] & bit:
			var j2 := i
			while j2 < n and (f[j2] & bit):
				j2 += 1
			if (j2 - i) < min_len:
				for k in range(i, j2):
					f[k] &= ~bit
			i = j2
		else:
			i += 1
	return f


# ------------------------------------------------------------------- carving

func _carve() -> void:
	var total := N * N
	var wmax := PackedFloat32Array()
	var wsum := PackedFloat32Array()
	var wtsum := PackedFloat32Array()
	wmax.resize(total)
	wsum.resize(total)
	wtsum.resize(total)
	var rdist := PackedFloat32Array()
	rdist.resize(MAP_N * MAP_N)
	rdist.fill(255.0)
	# Inside tunnels the terrain must stay above the tube (crown at +7.2 m).
	var tmin := PackedFloat32Array()
	tmin.resize(total)
	tmin.fill(-INF)
	# Nearest road surface per cell: under the road the ground follows that cross-section exactly, easing into
	# the weighted blend across the verge.
	var near_d := PackedFloat32Array()
	var near_y := PackedFloat32Array()
	var near_k := PackedFloat32Array()
	near_d.resize(total)
	near_d.fill(INF)
	near_y.resize(total)
	near_k.resize(total)
	var half := L.HALF
	for r: Dictionary in roads:
		var capped := _dead_end_caps(r)
		var pos: PackedVector3Array = capped["pos"]
		var flags: PackedByteArray = capped["flags"]
		var rbank: PackedFloat32Array = capped["bank"]
		var cap: PackedByteArray = capped["cap"]
		var loop: bool = r["loop"]
		var hw: float = float(r["width"]) * 0.5 + float(r["shoulder"])
		# Flat verge beside the shoulder; the expressway gets a wider recoverable one.
		var core := hw + (3.0 if int(r["class"]) == L.RoadClass.HIGHWAY else 1.6)
		var tube_e := hw + 0.6
		var n := pos.size()
		var segs := n if loop else n - 1
		var tube := tube_mask(flags)
		for si in segs:
			var a := pos[si]
			var b := pos[(si + 1) % n]
			var fa := flags[si]
			var fb := flags[(si + 1) % n]
			var is_tunnel := tube[si] == 1 and tube[(si + 1) % n] == 1
			var is_bridge := (fa & 1) and (fb & 1)
			# Required falloff from the terrain mismatch on both sides.
			var mid := (a + b) * 0.5
			var t2 := Vector2(b.x - a.x, b.z - a.z).normalized()
			var nrm := Vector2(-t2.y, t2.x)
			var diff := 0.0
			for off: float in [-22.0, -10.0, 0.0, 10.0, 22.0]:
				var q := Vector2(mid.x, mid.z) + nrm * off
				diff = maxf(diff, absf(sample_natural(q.x, q.y) - mid.y))
			var fall := clampf(diff * 1.6 + 4.0, 6.0, 60.0)
			var reach := core + fall
			if is_tunnel:
				reach = maxf(reach, tube_e + 18.0)
			var minx := int(floor((minf(a.x, b.x) - reach + half) / CELL))
			var maxx := int(ceil((maxf(a.x, b.x) + reach + half) / CELL))
			var minz := int(floor((minf(a.z, b.z) - reach + half) / CELL))
			var maxz := int(ceil((maxf(a.z, b.z) + reach + half) / CELL))
			minx = clampi(minx, 0, N - 1)
			maxx = clampi(maxx, 0, N - 1)
			minz = clampi(minz, 0, N - 1)
			maxz = clampi(maxz, 0, N - 1)
			var ax := a.x
			var az := a.z
			var abx := b.x - a.x
			var abz := b.z - a.z
			var ab2 := abx * abx + abz * abz
			for gz in range(minz, maxz + 1):
				var wz := -half + gz * CELL
				var row := gz * N
				for gx in range(minx, maxx + 1):
					var wx := -half + gx * CELL
					var t := clampf(((wx - ax) * abx + (wz - az) * abz) / ab2, 0.0, 1.0)
					var dx := wx - (ax + abx * t)
					var dz := wz - (az + abz * t)
					var d := sqrt(dx * dx + dz * dz)
					if d > reach:
						continue
					var idx := row + gx
					if is_tunnel:
						# Cover over the tube: cells that project inside the tube span (not in front of a portal)
						# stay TUBE_COVER above the road, easing down beside it.
						var ty := lerpf(a.y, b.y, t)
						if t > 0.0 and t < 1.0:
							tmin[idx] = maxf(tmin[idx], ty + TUBE_COVER - 0.9 * maxf(d - (tube_e + 6.0), 0.0))
						continue
					# road distance map (4 m) - only for even cells
					if (gx & 1) == 0 and (gz & 1) == 0 and cap[si] == 0 and cap[(si + 1) % n] == 0:
						var mi := (gz >> 1) * MAP_N + (gx >> 1)
						var ed := maxf(d - float(r["width"]) * 0.5, 0.0)
						if ed < rdist[mi]:
							rdist[mi] = ed
					# Just below the cambered cross-section on each side (its own edge height beyond the edge), so
					# terrain never pokes through and the high side of a banked curve gets no ditch.
					var lat := clampf((dx * -abz + dz * abx) / sqrt(ab2), -hw, hw)
					var y := lerpf(a.y, b.y, t) + lat * lerpf(rbank[si], rbank[(si + 1) % n], t) - 0.14
					if is_bridge:
						# Only lower terrain that would poke through the deck (around the deck, not the verge width).
						var nat := natural[idx]
						if nat > y - 3.0 and d < hw + 5.6:
							var w2 := 1.0 - smooth(hw + 1.6, hw + 5.6, d)
							_acc(wmax, wsum, wtsum, idx, w2, minf(nat, y - 3.5))
						continue
					var w := 1.0 if d <= core else 1.0 - smooth(core, reach, d)
					if w <= 0.0:
						continue
					_acc(wmax, wsum, wtsum, idx, w, y)
					if d < near_d[idx]:
						near_d[idx] = d
						near_y[idx] = y
						near_k[idx] = 1.0 - smooth(hw + 0.3, core + 5.0, d)
		_mark_portal_holes(r)
	for idx in total:
		var w := wmax[idx]
		if w > 0.0:
			var target := lerpf(wtsum[idx] / wsum[idx], near_y[idx], near_k[idx])
			var h := lerpf(natural[idx], target, w)
			# Embankments never fill the river channel (bridges span it) and slope down to its bank.
			if h > natural[idx]:
				h = minf(h, _river_bank_cap(idx))
			heights[idx] = h
		if tmin[idx] > -INF:
			heights[idx] = maxf(heights[idx], tmin[idx])
	_clamp_under_roads()
	road_dist.resize(MAP_N * MAP_N)
	for i in MAP_N * MAP_N:
		road_dist[i] = int(clampf(rdist[i], 0.0, 255.0))


## Hard guarantee after blending: terrain never rises through any road surface (other roads' falloffs
## can otherwise lift cells under a neighbouring road), and stays well below bridge decks.
func _clamp_under_roads() -> void:
	var half := L.HALF
	for r: Dictionary in roads:
		var capped := _dead_end_caps(r)
		var pos: PackedVector3Array = capped["pos"]
		var flags: PackedByteArray = capped["flags"]
		var rbank: PackedFloat32Array = capped["bank"]
		var n := pos.size()
		var e: float = float(r["width"]) * 0.5 + float(r["shoulder"])
		var hw := e + 0.6
		var segs := n if r["loop"] else n - 1
		var tube := tube_mask(flags)
		for si in segs:
			var a := pos[si]
			var b := pos[(si + 1) % n]
			if tube[si] == 1 and tube[(si + 1) % n] == 1:
				continue
			var deck := (flags[si] & 1) != 0 or (flags[(si + 1) % n] & 1) != 0
			var minx := clampi(int(floor((minf(a.x, b.x) - hw + half) / CELL)), 0, N - 1)
			var maxx := clampi(int(ceil((maxf(a.x, b.x) + hw + half) / CELL)), 0, N - 1)
			var minz := clampi(int(floor((minf(a.z, b.z) - hw + half) / CELL)), 0, N - 1)
			var maxz := clampi(int(ceil((maxf(a.z, b.z) + hw + half) / CELL)), 0, N - 1)
			var abx := b.x - a.x
			var abz := b.z - a.z
			var ab2 := maxf(abx * abx + abz * abz, 0.0001)
			var inv_len := 1.0 / sqrt(ab2)
			for gz in range(minz, maxz + 1):
				var wz := -half + gz * CELL
				for gx in range(minx, maxx + 1):
					var wx := -half + gx * CELL
					# Only cells beside this segment (or just past its ends, where its neighbour takes over): the
					# end point of a segment further along a grade would drag the ground under the road down.
					var tu := ((wx - a.x) * abx + (wz - a.z) * abz) / ab2
					if tu < -0.5 or tu > 1.5:
						continue
					var t := clampf(tu, 0.0, 1.0)
					var dx := wx - (a.x + abx * t)
					var dz := wz - (a.z + abz * t)
					if dx * dx + dz * dz > hw * hw:
						continue
					# Signed lateral offset (+ right): the surface height of the banked cross-section there.
					var lat := clampf((dx * -abz + dz * abx) * inv_len, -e, e)
					var y := lerpf(a.y, b.y, tu) + lat * lerpf(rbank[si], rbank[(si + 1) % n], t) - (1.6 if deck else 0.12)
					var idx := gz * N + gx
					if heights[idx] > y and not holes.has(idx):
						heights[idx] = y


## Road samples for carving: a dead end (no junction) continues 18 m along its last grade, so the blend under the
## last metres has segments on both sides (otherwise the ground there sinks below the road). "cap" marks them.
static func _dead_end_caps(r: Dictionary) -> Dictionary:
	var pos: PackedVector3Array = (r["pos"] as PackedVector3Array).duplicate()
	var flags: PackedByteArray = (r["flags"] as PackedByteArray).duplicate()
	var bank: PackedFloat32Array = (r["bank"] as PackedFloat32Array).duplicate()
	var cap := PackedByteArray()
	cap.resize(pos.size())
	if r["loop"] or pos.size() < 3:
		return {"pos": pos, "flags": flags, "bank": bank, "cap": cap}
	for end in 2:
		var n := pos.size()
		var dead: bool = (r["j_end"] if end == 0 else r["j_start"]).is_empty()
		var i := n - 1 if end == 0 else 0
		var j := n - 2 if end == 0 else 1
		if not dead or flags[i] != 0:
			continue
		var step := pos[i] - pos[j]
		step.y = clampf(step.y, -0.45, 0.45)
		var from := pos[i]
		for k in 6:
			var p := from + step * (k + 1)
			if end == 0:
				pos.append(p)
				flags.append(0)
				bank.append(bank[i])
				cap.append(1)
			else:
				pos.insert(0, p)
				flags.insert(0, 0)
				bank.insert(0, bank[0])
				cap.insert(0, 1)
	return {"pos": pos, "flags": flags, "bank": bank, "cap": cap}


static func _acc(wmax: PackedFloat32Array, wsum: PackedFloat32Array, wtsum: PackedFloat32Array, idx: int, w: float, y: float) -> void:
	var w4 := w * w * w * w + 0.0001
	wsum[idx] += w4
	wtsum[idx] += w4 * y
	if w > wmax[idx]:
		wmax[idx] = w


## Samples covered by a tunnel tube (1): each tunnel-flagged run plus TUBE_PRE / TUBE_POST samples.
static func tube_mask(flags: PackedByteArray) -> PackedByteArray:
	var n := flags.size()
	var m := PackedByteArray()
	m.resize(n)
	var i := 0
	while i < n:
		if not (flags[i] & 2):
			i += 1
			continue
		var j := i
		while j < n and (flags[j] & 2):
			j += 1
		for k in range(maxi(i - TUBE_PRE, 0), mini(j + TUBE_POST, n - 1) + 1):
			m[k] = 1
		i = j
	return m


## Highest a carve may raise cell idx near the river: natural ground inside the channel, rising 0.5 m per metre
## beyond the bank top (no limit further out).
func _river_bank_cap(idx: int) -> float:
	var p := Vector2(-L.HALF + (idx % N) * CELL, -L.HALF + (idx / N) * CELL)
	var d := river_query(p).x
	if d >= RIVER_BANK + 30.0:
		return INF
	return natural[idx] + 0.5 * maxf(d - RIVER_BANK, 0.0)


## Terrain holes at each tube portal: the grid vertices just behind the portal plane (inside the tube end,
## up to one cell diagonal) across the tube, so no terrain quad spans from the cutting floor in front of the
## portal up to the cover over the tube. RoadBuilder's portal headwall and cover block hide the cut.
func _mark_portal_holes(r: Dictionary) -> void:
	var pos: PackedVector3Array = r["pos"]
	var n := pos.size()
	var tube := tube_mask(r["flags"])
	var half_w: float = float(r["width"]) * 0.5 + float(r["shoulder"]) + 0.6 + 2.0
	var depth := CELL * 1.45
	for i in n:
		if tube[i] == 0:
			continue
		var inner := -1
		if i + 1 < n and tube[i + 1] == 1 and (i == 0 or tube[i - 1] == 0):
			inner = i + 1
		elif i > 0 and tube[i - 1] == 1 and (i == n - 1 or tube[i + 1] == 0):
			inner = i - 1
		if inner < 0:
			continue
		var p := pos[i]
		var inward := Vector2(pos[inner].x - p.x, pos[inner].z - p.z).normalized()
		var side := Vector2(-inward.y, inward.x)
		var cx := int(round((p.x + L.HALF) / CELL))
		var cz := int(round((p.z + L.HALF) / CELL))
		var rad := int(ceil((half_w + depth) / CELL)) + 1
		for gz in range(cz - rad, cz + rad + 1):
			for gx in range(cx - rad, cx + rad + 1):
				if gx < 0 or gz < 0 or gx >= N - 1 or gz >= N - 1:
					continue
				var v := Vector2(-L.HALF + gx * CELL - p.x, -L.HALF + gz * CELL - p.z)
				var along := v.dot(inward)
				if along >= 0.0 and along <= depth and absf(v.dot(side)) <= half_w:
					holes[gz * N + gx] = true


# ------------------------------------------------------------------- maps

func _gen_maps() -> void:
	# Surface ids follow Surfaces.MAP_IDS: 0 grass,1 dirt,2 sand,3 gravel,4 snow,5 asphalt,6 concrete,7 wet
	surface_map.resize(MAP_N * MAP_N)
	var half := L.HALF
	for j in MAP_N:
		var z := -half + j * 4.0
		for i in MAP_N:
			var x := -half + i * 4.0
			var h := heights[(j * 2) * N + i * 2]
			var hx := heights[(j * 2) * N + mini(i * 2 + 1, N - 1)]
			var hz := heights[mini(j * 2 + 1, N - 1) * N + i * 2]
			var slope := Vector2(hx - h, hz - h).length() / CELL
			var rw := region_weights(x, z)
			var s := 0
			var nz := n_detail.get_noise_2d(x * 0.7, z * 0.7)
			if rw.b > 0.5:
				s = 2 if nz > -0.1 else 1
			elif rw.a > 0.5 and h < 4.5:
				s = 2
			elif rw.g > 0.5:
				s = 4 if h > 300.0 + nz * 25.0 else 0
			else:
				s = 0
			if slope > 0.75:
				s = 3
			surface_map[j * MAP_N + i] = s
	region_rgba.resize(REG_N * REG_N * 4)
	for j in REG_N:
		var z2 := -half + j * 8.0
		for i in REG_N:
			var c := region_weights(-half + i * 8.0, z2)
			var o := (j * REG_N + i) * 4
			region_rgba[o] = int(c.r * 255.0)
			region_rgba[o + 1] = int(c.g * 255.0)
			region_rgba[o + 2] = int(c.b * 255.0)
			region_rgba[o + 3] = int(c.a * 255.0)


func region_at(x: float, z: float) -> int:
	var c := region_weights(x, z)
	var best := 0
	var bv := c.r
	if c.g > bv:
		best = 1
		bv = c.g
	if c.b > bv:
		best = 2
		bv = c.b
	if c.a > bv:
		best = 3
	return best
