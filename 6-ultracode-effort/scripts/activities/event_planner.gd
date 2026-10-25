extends RefCounted
## Places every road activity on the baked road network (deterministic, pure data).
## Used by tools/make_events.gd to write data/events/events.json, and by the activity manager at runtime
## when that file is missing or was generated for different roads (signature mismatch).
## Intents name a road and an anchor [x, z]; the planner snaps to the best nearby stretch: straightness,
## clearance from bridges / tunnels / junctions / other events, and crest sharpness for jumps.
## Every stored arclength is "cumulative" inside one event (loops may exceed the road length; Road.point_at wraps).

const VERSION := 5
const GATE_CLEAR := 22.0        # m without bridge / tunnel around a gate
const JUNCTION_CLEAR := 40.0    # m from junctions
const END_CLEAR := 30.0         # m from the ends of open roads
const SPACING := 150.0          # m between gates of different events
## Gate legs (+ sandbags, LEG_PAD past the gate half width) keep LEG_CLEAR from any other road's shoulder edge.
const LEG_PAD := 0.8
const LEG_CLEAR := 1.2
## Festival ramp: drivable back slope behind the lip (m). Every jump that would land past it on flat ground
## flies clear of it, so scoring is unchanged.
const RAMP_BACK := 10.0
const G := 9.81
## Festival flags: the ground around the spot is gentle (FLAG_RING radii) and a straight, dry, drivable line
## (APPROACH_STEP samples, terrain normal.y >= APPROACH_NORMAL) leads to it from an open road - no bridge or
## tunnel, the road level with the ground there. Collectibles clear trees and hedges from the flag pocket and along
## that line (dressing exclusions).
const FLAG_RING: Array[float] = [4.0, 8.0]
const FLAG_RING_NORMAL := 0.82
const APPROACH_MAX := 150.0
const APPROACH_STEP := 3.0
const APPROACH_NORMAL := 0.84

const SPEED_TRAPS := [
	{"id": "st_valley_express", "title": "Valley Express", "road": "expressway", "at": [-569, 151]},
	{"id": "st_mesa_climb", "title": "Mesa Climb", "road": "expressway", "at": [993, -284]},
	{"id": "st_ochre_straight", "title": "Ochre Straight", "road": "ring", "at": [1750, -460]},
	{"id": "st_beach_road", "title": "Beach Road", "road": "ring", "at": [-1282, 1344]},
	{"id": "st_mirror_lake", "title": "Mirror Lake Run", "road": "lake_road", "at": [266, -242]},
	{"id": "st_dustwater", "title": "Dustwater Dash", "road": "canyon_link", "at": [1109, -129]},
]
const SPEED_ZONES := [
	{"id": "sz_expressway", "title": "Expressway Rush", "road": "expressway", "at": [-330, 179], "length": 1000.0},
	{"id": "sz_saltwind", "title": "Saltwind Cliffs", "road": "ring", "at": [1637, 1437], "length": 900.0},
	{"id": "sz_gale_ridge", "title": "Gale Ridge Run", "road": "desert_north", "at": [1864, -687], "length": 1000.0},
	{"id": "sz_vale", "title": "Vale Sweepers", "road": "ring", "at": [-1302, 360], "length": 850.0},
]
const DRIFT_ZONES := [
	{"id": "dz_highmoor", "title": "Highmoor Switchbacks", "road": "ring", "at": [-1599, -663], "length": 1100.0},
	{"id": "dz_ember_spur", "title": "Ember Spur Esses", "road": "ring", "at": [457, -1006], "length": 850.0},
	{"id": "dz_ochre_gorge", "title": "Ochre Gorge", "road": "ring", "at": [1458, 240], "length": 750.0},
	{"id": "dz_plateau", "title": "Plateau Sideways", "road": "plateau_stage", "at": [1114, -1483], "length": 520.0},
]
## Jumps: a natural crest when the road has a clean one, else ("ramp": true, non-traffic tracks only) a festival ramp.
const JUMPS := [
	{"id": "dj_dustwater", "title": "Dustwater Drop", "road": "canyon_link", "at": [983, 297]},
	{"id": "dj_hedgerow", "title": "Hedgerow Hop", "road": "farm_track", "at": [-1480, 585], "ramp": true},
	{"id": "dj_redwall", "title": "Redwall Ramp", "road": "canyon_floor", "at": [770, 450], "ramp": true},
	{"id": "dj_lakeshore", "title": "Lakeshore Leap", "road": "lake_loop", "at": [80, -420], "ramp": true},
	{"id": "dj_pinewood", "title": "Pinewood Kicker", "road": "forest_track", "at": [-760, -200], "ramp": true},
	{"id": "dj_mesa_cut", "title": "Mesa Cut Launch", "road": "mesa_cut", "at": [1400, -680], "ramp": true},
	{"id": "dj_dune_run", "title": "Dune Run Launch", "road": "dune_track", "at": [-1300, 1520], "ramp": true},
]
const RACES := [
	{"id": "rc_highmoor", "title": "Highmoor Hillclimb", "road": "ring", "at": [-371, 727], "to": [-983, -1714],
	 "dir": 1, "spacing": 700.0, "opponents": 3},
	{"id": "rc_coast", "title": "Saltwind Coast Sprint", "road": "ring", "at": [1830, 1262], "to": [-990, 1386],
	 "dir": 1, "spacing": 650.0, "opponents": 3},
]
const TIME_TRIALS := [
	{"id": "tt_sunward_ring", "title": "Sunward Ring Time Trial", "road": "ring", "at": [-262, 770], "dir": 1, "spacing": 1500.0},
]
## Festival Flags: hidden near landmarks, viewpoints and off-road spots. "road": keep within this distance of a road.
const FLAGS := [
	{"id": "flag_festival_hill", "title": "Festival Hill", "at": [-205, 640]},
	{"id": "flag_millbrook", "title": "Millbrook Green", "at": [-1110, 700]},
	{"id": "flag_wend_farm", "title": "Wend Farm Barnyard", "at": [-1445, 470]},
	{"id": "flag_crossroads", "title": "Crossroads Diner", "at": [-735, 235]},
	{"id": "flag_mirror_lake", "title": "Mirror Lake Shore", "at": [70, -440]},
	{"id": "flag_pinewood", "title": "Pinewood Clearing", "at": [-690, -230]},
	{"id": "flag_highmoor", "title": "Highmoor Hamlet", "at": [-1490, -1385]},
	{"id": "flag_old_keep", "title": "Old Keep Ruins", "at": [-1800, -1470]},
	{"id": "flag_ironcrest", "title": "Ironcrest Viewpoint", "at": [-900, -1530]},
	# On the spur's west flank above the tunnel approach: the ridge above the portals is steep forest, reachable
	# from no road.
	{"id": "flag_ember_spur", "title": "Ember Spur Lookout", "at": [-440, -1080]},
	{"id": "flag_gale_ridge", "title": "Gale Ridge Turbines", "at": [1120, -1455]},
	{"id": "flag_mesa_fuel", "title": "Mesa Fuel", "at": [1275, -395]},
	{"id": "flag_dustwater", "title": "Dustwater Yard", "at": [1110, -40]},
	{"id": "flag_redwall", "title": "Redwall Canyon Floor", "at": [740, 200]},
	{"id": "flag_gullhaven", "title": "Gullhaven Quay", "at": [1080, 1370]},
	{"id": "flag_lighthouse", "title": "Saltwind Lighthouse", "at": [1755, 1495]},
	{"id": "flag_seabreak", "title": "Seabreak Dunes", "at": [300, 1375]},
	{"id": "flag_estuary", "title": "Estuary Beach", "at": [-880, 1480]},
	{"id": "flag_dune_run", "title": "Dune Run Hollow", "at": [-1190, 1520]},
	{"id": "flag_coast_fuel", "title": "Coast Fuel", "at": [-1620, 1150]},
]

var net: RoadNetwork
var wd: WorldData
var log_lines: PackedStringArray = []
var _head: Dictionary = {}
var _block: Dictionary = {}
var _used: Dictionary = {}


## Gate half width on a road (arch legs / gantry posts stand at +-this from the centre line).
static func gate_half_width(r: RoadNetwork.Road) -> float:
	return maxf(r.width * 0.5 + r.shoulder + 1.2, 5.2)


static func signature(network: RoadNetwork) -> String:
	var parts := PackedStringArray()
	for r in network.roads:
		parts.append("%s:%d:%d" % [r.id, roundi(r.length), r.pos.size()])
	return str(";".join(parts).hash())


func plan(world_data: WorldData) -> Dictionary:
	wd = world_data
	net = wd.network
	_prepare()
	var events: Array = []
	# Order matters: earlier events claim their stretch first.
	for it: Dictionary in TIME_TRIALS:
		_add(events, _race(it, &"time_trial"))
	for it: Dictionary in RACES:
		_add(events, _race(it, &"race"))
	for it: Dictionary in JUMPS:
		_add(events, _jump(it))
	for it: Dictionary in SPEED_TRAPS:
		_add(events, _speed_trap(it))
	for it: Dictionary in SPEED_ZONES:
		_add(events, _zone(it, &"speed_zone"))
	for it: Dictionary in DRIFT_ZONES:
		_add(events, _zone(it, &"drift"))
	for it: Dictionary in FLAGS:
		_add(events, _flag(it))
	return {"version": VERSION, "signature": signature(net), "events": events}


func _add(events: Array, ev: Dictionary) -> void:
	if not ev.is_empty():
		events.append(ev)


func _log(s: String) -> void:
	log_lines.append(s)


# ------------------------------------------------------------------ road analysis

func _prepare() -> void:
	for r in net.roads:
		var n := r.pos.size()
		var h := PackedFloat32Array()
		h.resize(n)
		for i in n:
			var a := r.pos[_wrap_i(r, i - 1)]
			var b := r.pos[_wrap_i(r, i + 1)]
			h[i] = atan2(b.z - a.z, b.x - a.x)
		_head[r.id] = h
		var blk := PackedByteArray()
		blk.resize(n)
		var gc := int(ceil(GATE_CLEAR / r.ds))
		for i in n:
			if r.flags[i] != 0:
				for k in range(-gc, gc + 1):
					var j := i + k
					if r.loop or (j >= 0 and j < n):
						blk[_wrap_i(r, j)] = 1
		if not r.loop:
			# An end that joins another road is a junction: same clearance as on the parent road.
			var ec0 := int(ceil((JUNCTION_CLEAR if r.j_start.has("road") else END_CLEAR) / r.ds))
			var ec1 := int(ceil((JUNCTION_CLEAR if r.j_end.has("road") else END_CLEAR) / r.ds))
			for k in mini(ec0, n):
				blk[k] = 1
			for k in mini(ec1, n):
				blk[n - 1 - k] = 1
		_block[r.id] = blk
		_used[r.id] = PackedFloat32Array()
	# Junctions: block the parent road around every attachment index.
	for r in net.roads:
		for j: Dictionary in [r.j_start, r.j_end]:
			if not j.has("road"):
				continue
			var parent := net.get_road(String(j["road"]))
			if parent == null:
				continue
			var blk: PackedByteArray = _block[parent.id]
			var jc := int(ceil(JUNCTION_CLEAR / parent.ds))
			var idx := int(j["index"])
			for k in range(-jc, jc + 1):
				var q := idx + k
				if parent.loop or (q >= 0 and q < parent.pos.size()):
					blk[_wrap_i(parent, q)] = 1
			_block[parent.id] = blk
	for r in net.roads:
		_block_legs_near_roads(r)


## Blocks samples where a gate leg would stand on (or against) another road: acute junction mouths, where the
## child road runs alongside its parent for tens of metres, and roads passing close by.
func _block_legs_near_roads(r: RoadNetwork.Road) -> void:
	var blk: PackedByteArray = _block[r.id]
	var reach := gate_half_width(r) + LEG_PAD
	var other := func(o: RoadNetwork.Road) -> bool: return o != r
	for i in r.pos.size():
		if blk[i] != 0:
			continue
		var c := r.pos[i]
		var right := r.right_at(i * r.ds)
		for side: float in [-1.0, 1.0]:
			var leg := c + right * side * reach
			var res := net.nearest(leg, 40.0, other)
			if res.is_empty():
				continue
			var o: RoadNetwork.Road = res["road"]
			var q: Vector3 = res["position"]
			if absf(q.y - c.y) > 6.0:
				continue
			# Distance to the other road's centre line (past its last sample when the leg is beyond its end).
			var along := maxf(absf((leg - q).dot(res["forward"] as Vector3)) - o.ds * 0.5, 0.0)
			var d := Vector2(float(res["lateral"]), along).length()
			if d < o.width * 0.5 + o.shoulder + LEG_CLEAR:
				blk[i] = 1
				break
	_block[r.id] = blk


func _wrap_i(r: RoadNetwork.Road, i: int) -> int:
	var n := r.pos.size()
	return posmod(i, n) if r.loop else clampi(i, 0, n - 1)


func _idx(r: RoadNetwork.Road, s: float) -> int:
	return _wrap_i(r, roundi(s / r.ds))


func _in_range(r: RoadNetwork.Road, s: float) -> bool:
	return r.loop or (s >= 0.0 and s <= r.length)


## Arclength of the road sample nearest to an [x, z] anchor.
func _project(r: RoadNetwork.Road, at: Array) -> float:
	var best := INF
	var bi := 0
	for i in r.pos.size():
		var p := r.pos[i]
		var d := (p.x - float(at[0])) * (p.x - float(at[0])) + (p.z - float(at[1])) * (p.z - float(at[1]))
		if d < best:
			best = d
			bi = i
	return bi * r.ds


## Heading change per metre at s (window +-k samples).
func _curv(r: RoadNetwork.Road, s: float, k := 8) -> float:
	var h: PackedFloat32Array = _head[r.id]
	var i := roundi(s / r.ds)
	var a := h[_wrap_i(r, i - k)]
	var b := h[_wrap_i(r, i + k)]
	return absf(wrapf(b - a, -PI, PI)) / (2.0 * k * r.ds)


func _min_radius(r: RoadNetwork.Road, s0: float, s1: float) -> float:
	var c := 0.00001
	var s := minf(s0, s1)
	while s <= maxf(s0, s1):
		if _in_range(r, s):
			c = maxf(c, _curv(r, s))
		s += r.ds
	return 1.0 / c


func _y(r: RoadNetwork.Road, s: float) -> float:
	return r.point_at(s).y


func _blocked(r: RoadNetwork.Road, s: float, ignore_used := false) -> bool:
	if not _in_range(r, s):
		return true
	if (_block[r.id] as PackedByteArray)[_idx(r, s)] != 0:
		return true
	if ignore_used:
		return false
	for u: float in _used[r.id]:
		if _loop_dist(r, u, s) < SPACING:
			return true
	return false


func _loop_dist(r: RoadNetwork.Road, a: float, b: float) -> float:
	if not r.loop:
		return absf(a - b)
	var d := fposmod(b - a, r.length)
	return minf(d, r.length - d)


func _use(r: RoadNetwork.Road, s: float) -> void:
	var u: PackedFloat32Array = _used[r.id]
	u.append(fposmod(s, r.length) if r.loop else s)
	_used[r.id] = u


## Nearest gate-capable arclength to `target` within +-radius (returns NAN when none).
func _find_clear(r: RoadNetwork.Road, target: float, radius: float, ignore_used := false) -> float:
	var k := 0.0
	while k <= radius:
		for s: float in [target + k, target - k]:
			if not _blocked(r, s, ignore_used):
				return s
		k += r.ds
	return NAN


static func _snap(v: float, step: float) -> float:
	return roundf(v / step) * step


## Lap/segment time of a well-driven fast car (seconds): curvature speed limit + accel/brake passes.
func _ref_time(r: RoadNetwork.Road, sa: float, sb: float, lat: float, vmax: float, standing: bool) -> float:
	var step := 6.0
	var n := maxi(int(absf(sb - sa) / step), 1)
	var dir := signf(sb - sa)
	var v := PackedFloat32Array()
	v.resize(n + 1)
	for k in n + 1:
		v[k] = minf(vmax, sqrt(lat / maxf(_curv(r, sa + dir * k * step, 6), 0.00001)))
	if standing:
		v[0] = 1.0
	for k in range(1, n + 1):
		v[k] = minf(v[k], sqrt(v[k - 1] * v[k - 1] + 2.0 * 4.0 * step))
	for k in range(n - 1, -1, -1):
		v[k] = minf(v[k], sqrt(v[k + 1] * v[k + 1] + 2.0 * 8.0 * step))
	var t := 0.0
	for k in n:
		t += step / maxf((v[k] + v[k + 1]) * 0.5, 0.5)
	return t


func _event(it: Dictionary, kind: StringName, r: RoadNetwork.Road, gates: Array, dir: int, thresholds: Array, extra := {}) -> Dictionary:
	var p := r.point_at(float(gates[0]))
	var length := absf(float(gates[gates.size() - 1]) - float(gates[0]))
	var g: Array = []
	for s: float in gates:
		g.append(snappedf(s, 0.1))
	return {"id": it["id"], "kind": String(kind), "title": it["title"], "road": r.id, "dir": dir, "gates": g,
		"thresholds": thresholds, "pos": [snappedf(p.x, 0.01), snappedf(p.y, 0.01), snappedf(p.z, 0.01)],
		"length": snappedf(length, 0.1), "extra": extra}


# ------------------------------------------------------------------ activity types

func _speed_trap(it: Dictionary) -> Dictionary:
	var r := net.get_road(it["road"])
	if r == null:
		_log("skip %s: road %s missing" % [it["id"], it["road"]])
		return {}
	var s0 := _project(r, it["at"])
	var best := NAN
	var best_score := -INF
	var best_rad := 0.0
	var s := s0 - 450.0
	while s <= s0 + 450.0:
		if not _blocked(r, s):
			var rad := minf(_min_radius(r, s - 250.0, s + 250.0), 3000.0)
			var grade := absf(_y(r, s + 30.0) - _y(r, s - 30.0)) / 60.0
			var score := rad - absf(s - s0) * 0.4 - grade * 4000.0
			if score > best_score:
				best_score = score
				best = s
				best_rad = rad
		s += r.ds
	if is_nan(best):
		_log("skip %s: no clear stretch" % it["id"])
		return {}
	if r.loop:
		best = fposmod(best, r.length)
	_use(r, best)
	var v_cap := minf(3.6 * sqrt(8.5 * best_rad), 330.0)
	var gold := _snap(minf(v_cap * 0.8, 245.0), 5.0)
	var th := [_snap(gold * 0.66, 5.0), _snap(gold * 0.82, 5.0), gold]
	_log("%-20s %-12s s=%7.1f  R=%5.0f  stars %s" % [it["id"], r.id, best, best_rad, str(th)])
	return _event(it, &"speed_trap", r, [best], 0, th, {"radius": roundf(best_rad)})


func _zone(it: Dictionary, kind: StringName) -> Dictionary:
	var r := net.get_road(it["road"])
	if r == null:
		_log("skip %s: road %s missing" % [it["id"], it["road"]])
		return {}
	var length: float = it["length"]
	var s0 := _project(r, it["at"])
	var sa := _find_clear(r, s0, 320.0)
	if is_nan(sa):
		_log("skip %s: no clear start" % it["id"])
		return {}
	if not r.loop and sa + length > r.length - END_CLEAR:
		length = r.length - END_CLEAR - sa - 5.0
	var sb := _find_clear(r, sa + length, 220.0)
	if is_nan(sb) or sb - sa < 300.0:
		_log("skip %s: no clear end" % it["id"])
		return {}
	if r.loop and sa >= r.length:
		sa -= r.length
		sb -= r.length
	_use(r, sa)
	_use(r, sb)
	var zl := sb - sa
	var th: Array
	if kind == &"speed_zone":
		var lat := 9.0 if r.surface == &"asphalt" else 6.5
		var tf := _ref_time(r, sa, sb, lat, 250.0 / 3.6, false)
		var tb := _ref_time(r, sb, sa, lat, 250.0 / 3.6, false)
		var ref := zl / maxf(tf, tb) * 3.6
		th = [_snap(ref * 0.6, 5.0), _snap(ref * 0.74, 5.0), _snap(ref * 0.86, 5.0)]
	else:
		th = [_snap(zl * 30.0, 500.0), _snap(zl * 75.0, 500.0), _snap(zl * 130.0, 500.0)]
	_log("%-20s %-12s s=%7.1f..%7.1f (%4.0f m)  thresholds %s" % [it["id"], r.id, sa, sb, zl, str(th)])
	return _event(it, kind, r, [sa, sb], 0, th)


func _slope(r: RoadNetwork.Road, s: float, d: float, span: float) -> float:
	return (_y(r, s + d * span) - _y(r, s)) / span


func _jump(it: Dictionary) -> Dictionary:
	var r := net.get_road(it["road"])
	if r == null:
		_log("skip %s: road %s missing" % [it["id"], it["road"]])
		return {}
	var s0 := _project(r, it["at"])
	if not it.get("ramp", false):
		var ev := _jump_crest(it, r, s0)
		if not ev.is_empty() or r.traffic:
			return ev
	if r.traffic:
		_log("skip %s: ramps only go on tracks without traffic" % it["id"])
		return {}
	return _jump_ramp(it, r, s0)


func _jump_crest(it: Dictionary, r: RoadNetwork.Road, s0: float) -> Dictionary:
	var best := NAN
	var best_dg := -0.09
	var s := s0 - 150.0
	while s <= s0 + 150.0:
		if _in_range(r, s - 60.0) and _in_range(r, s + 60.0):
			# (slope out) - (slope in), the same for both travel directions; negative = convex crest.
			var dg := _slope(r, s, 1.0, 12.0) + _slope(r, s, -1.0, 12.0)
			if dg < best_dg and _structure_free(r, s - 45.0, s + 45.0) and not _blocked(r, s, true):
				best_dg = dg
				best = s
		s += r.ds
	if is_nan(best):
		_log("%s: no clean crest near the anchor" % it["id"])
		return {}
	var opt := _jump_direction(r, best, 160.0)
	if opt.is_empty():
		_log("%s: no room for the danger sign" % it["id"])
		return {}
	var dir: int = opt[0]
	var sign_s: float = opt[1]
	_use(r, best)
	_use(r, sign_s)
	var v_cap := clampf(sqrt(8.5 * minf(opt[2], 3000.0)), 70.0 / 3.6, 170.0 / 3.6)
	var th: Array = []
	for f: float in [0.62, 0.8, 0.95]:
		var v := v_cap * f
		th.append(maxf(roundf(0.75 * 2.0 * v * v * (-best_dg) / G), 4.0))
	_log("%-20s %-12s crest s=%7.1f dg=%.3f dir=%d sign=%7.1f R=%4.0f  thresholds %s" % [it["id"], r.id, best, best_dg, dir, sign_s, opt[2], str(th)])
	return _event(it, &"jump", r, [sign_s, best], dir, th, {"crest_dg": snappedf(best_dg, 0.001)})


## Best travel direction toward a takeoff point: [dir, sign_s, approach_radius] or [] when no sign fits.
func _jump_direction(r: RoadNetwork.Road, at: float, approach: float) -> Array:
	var options: Array = []
	for d: int in [1, -1]:
		var sg := _find_clear(r, at - d * 135.0, 45.0)
		if not is_nan(sg):
			var ar := _min_radius(r, minf(at, at - d * approach), maxf(at, at - d * approach))
			options.append([d, sg, ar, ar * (1.15 if d == 1 else 1.0)])
	if options.is_empty():
		return []
	options.sort_custom(func(a: Array, b: Array) -> bool: return a[3] > b[3])
	return options[0]


## Festival ramp on a track without traffic: straight approach, flat-ish landing, clear of structures.
func _jump_ramp(it: Dictionary, r: RoadNetwork.Road, s0: float) -> Dictionary:
	const LEN := 11.0
	const HEIGHT := 1.6
	var best := NAN
	var best_dir := 1
	var best_score := -INF
	var best_rad := 0.0
	var s := s0 - 350.0
	while s <= s0 + 350.0:
		if not _blocked(r, s):
			for d: int in [1, -1]:
				if not r.loop and (not _in_range(r, s - d * 330.0) or not _in_range(r, s + d * (END_CLEAR + 90.0))):
					continue
				if not _structure_free(r, minf(s - d * 160.0, s + d * 90.0), maxf(s - d * 160.0, s + d * 90.0)):
					continue
				var app := minf(_min_radius(r, minf(s, s - d * 170.0), maxf(s, s - d * 170.0)), 1500.0)
				var land := minf(_min_radius(r, minf(s, s + d * 80.0), maxf(s, s + d * 80.0)), 1000.0)
				var land_slope := _slope(r, s + d * 25.0, float(d), 40.0)
				if land_slope > 0.05 or land_slope < -0.16:
					continue
				var score := app + 0.6 * land - absf(s - s0) * 0.3 + (40.0 if d == 1 else 0.0)
				if score > best_score:
					best_score = score
					best = s
					best_dir = d
					best_rad = app
		s += r.ds
	if is_nan(best) or best_rad < 110.0:
		_log("skip %s: no straight stretch for a ramp" % it["id"])
		return {}
	var sign_s := _find_clear(r, best - best_dir * 130.0, 50.0)
	if is_nan(sign_s):
		_log("skip %s: no room for the danger sign" % it["id"])
		return {}
	_use(r, best)
	_use(r, sign_s)
	var theta := atan(HEIGHT / LEN)
	var v_cap := clampf(sqrt(7.0 * best_rad), 60.0 / 3.6, 135.0 / 3.6)
	var th: Array = []
	for f: float in [0.6, 0.78, 0.95]:
		var v := v_cap * f
		var vy := v * sin(theta)
		var t := (vy + sqrt(vy * vy + 2.0 * G * HEIGHT)) / G
		th.append(maxf(roundf(0.8 * v * cos(theta) * t), 4.0))
	_log("%-20s %-12s ramp s=%7.1f dir=%d sign=%7.1f R=%4.0f  thresholds %s" % [it["id"], r.id, best, best_dir, sign_s, best_rad, str(th)])
	return _event(it, &"jump", r, [sign_s, best], best_dir, th, {"ramp": true, "ramp_len": LEN, "ramp_height": HEIGHT, "ramp_back": RAMP_BACK})


func _structure_free(r: RoadNetwork.Road, s0: float, s1: float) -> bool:
	var s := s0
	while s <= s1:
		if _in_range(r, s) and r.flag_at(s) != 0:
			return false
		s += r.ds
	return true


func _race(it: Dictionary, kind: StringName) -> Dictionary:
	var r := net.get_road(it["road"])
	if r == null:
		_log("skip %s: road %s missing" % [it["id"], it["road"]])
		return {}
	var dir: int = int(it.get("dir", 1))
	var sa := _find_clear(r, _project(r, it["at"]), 250.0)
	if is_nan(sa):
		_log("skip %s: no clear start" % it["id"])
		return {}
	if r.loop:
		sa = fposmod(sa, r.length)
	var sb: float
	if kind == &"time_trial":
		if not r.loop:
			_log("skip %s: time trials need a loop road" % it["id"])
			return {}
		sb = sa + dir * r.length
	else:
		var target := _project(r, it["to"])
		if r.loop:
			target = sa + dir * fposmod((target - sa) * dir, r.length)
		sb = _find_clear(r, target, 450.0)
		if is_nan(sb):
			_log("skip %s: no clear finish" % it["id"])
			return {}
	var total := absf(sb - sa)
	var spacing: float = it.get("spacing", 700.0)
	var n := maxi(roundi(total / spacing), 2)
	var gates: Array = [sa]
	for k in range(1, n):
		var cp := _find_clear(r, sa + dir * total * k / n, 160.0, true)
		if not is_nan(cp):
			gates.append(cp)
	gates.append(sb)
	_use(r, sa)
	if kind == &"race":
		_use(r, sb)
	var lat := 9.0 if r.surface == &"asphalt" else 6.5
	var t := _ref_time(r, sa, sb, lat, 240.0 / 3.6, true)
	var th := [snappedf(t * 1.4, 0.5), snappedf(t * 1.22, 0.5), snappedf(t * 1.1, 0.5)]
	_log("%-20s %-12s s=%7.1f..%7.1f (%5.0f m) %d gates  ref %.1f s  medals %s" % [it["id"], r.id, sa, sb, total, gates.size(), t, str(th)])
	return _event(it, kind, r, gates, dir, th, {"opponents": int(it.get("opponents", 0)), "laps": 1})


func _flag(it: Dictionary) -> Dictionary:
	var at := Vector2(float(it["at"][0]), float(it["at"][1]))
	# First pass: a spot the car can reach (gentle surroundings, drivable approach from a road); else any dry,
	# gentle spot as before.
	for strict: bool in [true, false]:
		for ring in (60 if strict else 26):
			var rad := ring * 6.0
			var steps := maxi(ring * 6, 1)
			for k in steps:
				var a := TAU * k / steps + ring * 0.7
				var x := at.x + cos(a) * rad
				var z := at.y + sin(a) * rad
				if absf(x) > WorldLayout.PLAY_HALF - 40.0 or absf(z) > WorldLayout.PLAY_HALF - 40.0:
					continue
				var h := wd.height_at(x, z)
				if wd.normal_at(x, z).y < 0.9:
					continue
				var rd := wd.road_distance_at(x, z)
				if rd < 6.0 or rd > 140.0 or _wet(wd, x, z, h, 6.0):
					continue
				var line := PackedVector3Array()
				if strict:
					if not _gentle_around(wd, x, z, h):
						continue
					line = approach(wd, Vector3(x, h, z))
					if line.is_empty():
						continue
				_log("%-20s flag at (%.0f, %.1f, %.0f) %.0f m from anchor%s" % [it["id"], x, h, z, rad,
					", approach %.0f m from the road" % line[0].distance_to(line[1]) if strict else ", NO drivable approach"])
				return {"id": it["id"], "kind": "collectible", "title": it["title"], "road": "", "dir": 0, "gates": [],
					"thresholds": [], "pos": [snappedf(x, 0.01), snappedf(h, 0.01), snappedf(z, 0.01)], "length": 0.0, "extra": {}}
	_log("skip %s: no dry, gentle ground near the anchor" % it["id"])
	return {}


## Water at (x, z): sea, within `margin` of a lake, or near the river channel (dry flag spots keep 22 m from it).
static func _wet(w: WorldData, x: float, z: float, h: float, margin: float) -> bool:
	if h < WorldLayout.SEA_LEVEL + 1.2:
		return true
	for lk: Dictionary in w.lake_list():
		if Vector2(x - float(lk["pos"][0]), z - float(lk["pos"][1])).length() < float(lk["radius"]) * 1.35 + margin:
			return true
	return w.gen.river_query(Vector2(x, z)).x < margin + 16.0


## The ground around a flag spot is gentle: no ledge on a steep, forested slope.
static func _gentle_around(w: WorldData, x: float, z: float, h: float) -> bool:
	for r in FLAG_RING:
		for k in 8:
			var a := TAU * k / 8.0
			var px := x + cos(a) * r
			var pz := z + sin(a) * r
			if w.normal_at(px, pz).y < FLAG_RING_NORMAL or absf(w.height_at(px, pz) - h) > r * 0.35:
				return false
	return true


## Shortest straight, dry, drivable line from a flag spot to an open road (16 bearings): [spot, road edge point],
## or [] when there is none. Used by the planner and by the collectibles (trees cleared along it).
static func approach(w: WorldData, p: Vector3) -> PackedVector3Array:
	var best := PackedVector3Array()
	var best_d := INF
	for b in 16:
		var a := TAU * b / 16.0
		var prev := w.height_at(p.x, p.z)
		var d := APPROACH_STEP
		while d <= minf(APPROACH_MAX, best_d):
			var x := p.x + cos(a) * d
			var z := p.z + sin(a) * d
			var h := w.height_at(x, z)
			if w.road_distance_at(x, z) < 1.0:
				var near := w.network.nearest(Vector3(x, h, z), 14.0)
				if not near.is_empty():
					var r: RoadNetwork.Road = near["road"]
					if r.flag_at(float(near["s"])) == 0 and absf((near["position"] as Vector3).y - h) < 1.2:
						best = PackedVector3Array([p, Vector3(x, h, z)])
						best_d = d
				break
			if w.normal_at(x, z).y < APPROACH_NORMAL or absf(h - prev) > APPROACH_STEP * 0.4 or _wet(w, x, z, h, 2.0):
				break
			prev = h
			d += APPROACH_STEP
	return best
