extends RefCounted
## Directed lane graph over the traffic roads of a RoadNetwork (right-hand traffic).
## Lanes follow the road splines (dir +1 = increasing s on the right-hand side). Each junction
## (parent road sample <-> child road end) gets Bezier turning connectors: the parent road has right of
## way, connectors leaving the child road start at its stop line and must give way; left turns off the
## parent give way to oncoming traffic. Each lane carries a curve-speed profile with braking anticipation.

const LAT_COMFORT := 2.6
const PROFILE_DECEL := 1.6
const CONN_STEP := 1.5
const BRANCH_CLEAR := 5.0
const TURN_LAT := 2.4
const CREST_G := 4.5
const GRID := 100.0
## Turns sharper than this (acute junctions) are not driven unless they are the only way out.
const MAX_TURN_DEG := 112.0

enum Yield { NONE, MINOR, ONCOMING }


class Lane:
	var id: int
	var road: RoadNetwork.Road
	var dir: int = 1
	var k: int = 1
	var offset: float = 2.0
	var outer: bool = true
	var limit: float = 25.0
	var dead_end: bool = false
	var s_begin: float = 0.0
	var s_end: float = 0.0
	var profile: PackedFloat32Array
	var decisions: Array = []
	var outgoing: Array = []
	var incoming: Array = []
	var siblings: Array = []

	## Signed travel distance from a to b (ahead positive; loops take the nearer way round).
	func sdist(a: float, b: float) -> float:
		var d := (b - a) * dir
		if road.loop:
			d = fposmod(d, road.length)
			if d > road.length * 0.5:
				d -= road.length
		return d

	## Distance ahead from a to b; on loops always in [0, length).
	func ahead(a: float, b: float) -> float:
		if road.loop:
			return fposmod((b - a) * dir, road.length)
		return (b - a) * dir

	func advance(s: float, d: float) -> float:
		var r := s + d * dir
		return fposmod(r, road.length) if road.loop else r

	func point(s: float, off: float) -> Vector3:
		return road.surface_point(s, off * dir)

	func speed_at(s: float) -> float:
		var n := profile.size()
		var f := s / road.ds
		if road.loop:
			f = fposmod(f, float(n))
			var i := int(f)
			return lerpf(profile[i], profile[(i + 1) % n], f - i)
		f = clampf(f, 0.0, n - 1.001)
		var j := int(f)
		return lerpf(profile[j], profile[j + 1], f - j)

	## Drivable distance left on a non-loop lane (INF on loops).
	func remaining(s: float) -> float:
		return INF if road.loop else (s_end - s) * dir

	func sibling(lane_k: int) -> Lane:
		for l: Lane in siblings:
			if l.k == lane_k:
				return l
		return null


class Junction:
	var id: int
	var parent: RoadNetwork.Road
	var parent_s: float
	var center: Vector3
	var radius: float = 10.0
	var child: RoadNetwork.Road
	var child_end: int
	var stop_s: float
	var connectors: Array = []
	var parent_lanes: Array = []


class Connector:
	var id: int
	var from_lane: Lane
	var at_s: float
	var to_lane: Lane
	var to_s: float
	var junction: Junction
	var yield_mode: int = 0
	## +1 right turn, -1 left turn.
	var turn: int = 1
	var pts: PackedVector3Array
	var cum: PackedFloat32Array
	var length: float = 0.0
	var vmax: float = 8.0
	## Major-road lanes this (left) turn crosses before merging.
	var crosses: Array = []

	func _seg(c: float) -> int:
		var lo := 0
		var hi := cum.size() - 2
		while lo < hi:
			var mid := (lo + hi + 1) >> 1
			if cum[mid] <= c:
				lo = mid
			else:
				hi = mid - 1
		return lo

	func point(c: float) -> Vector3:
		c = clampf(c, 0.0, length)
		var i := _seg(c)
		var seg := cum[i + 1] - cum[i]
		return pts[i].lerp(pts[i + 1], (c - cum[i]) / maxf(seg, 0.0001))

	func tangent(c: float) -> Vector3:
		var i := _seg(clampf(c, 0.0, length))
		return (pts[i + 1] - pts[i]).normalized()

	## Arclength of the closest polyline point to p, searched around `hint`.
	func project(p: Vector3, hint: float) -> float:
		var i0 := _seg(clampf(hint, 0.0, length))
		var best := hint
		var bd := INF
		for i in range(maxi(i0 - 3, 0), mini(i0 + 6, pts.size() - 1)):
			var a := Vector2(pts[i].x, pts[i].z)
			var b := Vector2(pts[i + 1].x, pts[i + 1].z)
			var q := Vector2(p.x, p.z)
			var ab := b - a
			var t := clampf((q - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
			var d := q.distance_squared_to(a + ab * t)
			if d < bd:
				bd = d
				best = cum[i] + t * (cum[i + 1] - cum[i])
		return best


class Decision:
	var at_s: float
	var mandatory: bool = false
	var junction: Junction
	var options: Array = []


var network: RoadNetwork
var lanes: Array = []
var connectors: Array = []
var junctions: Array = []
var lanes_by_road: Dictionary = {}
## Traffic road length (m) per GRID x GRID cell, for density targets.
var road_grid: Dictionary = {}
## Lane length (m, all lanes of both directions) per cell, and per cell the road samples (road idx << 16 | sample)
## listed once per lane of each direction: spawning picks road by lane-km.
var lane_grid: Dictionary = {}
var sample_grid: Dictionary = {}


func build(net: RoadNetwork) -> void:
	network = net
	for r in net.roads:
		if not r.traffic:
			continue
		var base := _curve_speeds(r)
		var prof_f := _anticipate(base, r, 1)
		var prof_b := _anticipate(base, r, -1)
		var list: Array = []
		for d: int in [1, -1]:
			for k in range(1, r.lanes + 1):
				var l := Lane.new()
				l.id = lanes.size()
				l.road = r
				l.dir = d
				l.k = k
				l.offset = r.lane_offset(k)
				l.outer = k == r.lanes
				l.limit = r.limit / 3.6
				l.profile = prof_f if d > 0 else prof_b
				l.s_begin = 0.0 if d > 0 else r.length
				l.s_end = r.length if d > 0 else 0.0
				lanes.append(l)
				list.append(l)
		for l: Lane in list:
			for o: Lane in list:
				if o != l and o.dir == l.dir:
					l.siblings.append(o)
		lanes_by_road[r.idx] = list
		var segs := r.count() if r.loop else r.count() - 1
		for i in segs:
			var cell := Vector2i(floori(r.pos[i].x / GRID), floori(r.pos[i].z / GRID))
			road_grid[cell] = float(road_grid.get(cell, 0.0)) + r.ds
			lane_grid[cell] = float(lane_grid.get(cell, 0.0)) + r.ds * r.lanes * 2
			if not sample_grid.has(cell):
				sample_grid[cell] = PackedInt32Array()
			var arr: PackedInt32Array = sample_grid[cell]
			for _k in r.lanes:
				arr.append(r.idx << 16 | i)
			sample_grid[cell] = arr
	for jd: Dictionary in net.junctions:
		_add_junction(jd)
	# A non-loop lane without a junction decision at its far end is a dead end: never entered or spawned on.
	for l: Lane in lanes:
		if l.road.loop:
			continue
		var has_end := false
		for d: Decision in l.decisions:
			if d.mandatory:
				has_end = true
		l.dead_end = not has_end
	for l: Lane in lanes:
		var kept: Array = []
		for d: Decision in l.decisions:
			var opts: Array = []
			for cn: Connector in d.options:
				if not cn.to_lane.dead_end:
					opts.append(cn)
			d.options = opts
			if not opts.is_empty():
				kept.append(d)
		l.decisions = kept


## Kilometres of traffic road within `radius` of p (both directions counted once).
func road_km_near(p: Vector3, radius: float) -> float:
	var c := Vector2i(floori(p.x / GRID), floori(p.z / GRID))
	var n := int(ceil(radius / GRID))
	var r2 := (radius + GRID * 0.5) * (radius + GRID * 0.5)
	var total := 0.0
	for dz in range(-n, n + 1):
		for dx in range(-n, n + 1):
			var k := c + Vector2i(dx, dz)
			var cx := (k.x + 0.5) * GRID - p.x
			var cz := (k.y + 0.5) * GRID - p.z
			if cx * cx + cz * cz < r2:
				total += float(road_grid.get(k, 0.0))
	return total / 1000.0


## Breaks the lane <-> connector <-> junction reference cycles so the RefCounted graph can be freed.
func clear() -> void:
	for l: Lane in lanes:
		l.decisions.clear()
		l.outgoing.clear()
		l.incoming.clear()
		l.siblings.clear()
	for j: Junction in junctions:
		j.connectors.clear()
		j.parent_lanes.clear()
	for cn: Connector in connectors:
		cn.crosses.clear()
	lanes.clear()
	connectors.clear()
	junctions.clear()
	lanes_by_road.clear()
	sample_grid.clear()


func lanes_of(road: RoadNetwork.Road) -> Array:
	return lanes_by_road.get(road.idx, [])


## Next decision point on `lane` at or ahead of s (null when none).
func next_decision(lane: Lane, s: float) -> Decision:
	var best: Decision = null
	var bd := INF
	for d: Decision in lane.decisions:
		var a := lane.ahead(s, d.at_s)
		if not lane.road.loop and a < -0.5:
			continue
		if a < bd:
			bd = a
			best = d
	return best


## Lane piece: the stretch of a lane up to its next decision point, where nobody can leave the road. Keyed by
## that decision (a loop lane without decisions is one piece keyed by the lane itself).
func piece_key(lane: Lane, s: float) -> Object:
	var d := next_decision(lane, s)
	return d if d != null else lane


## Every lane piece: [{key, lane, s0, s1, next: Array (piece keys reachable at its end, turns and straight on)}].
## s0..s1 is the stretch in travel order (on loops s1 may be "before" s0: the piece wraps).
func pieces() -> Array:
	var out: Array = []
	for l: Lane in lanes:
		if l.dead_end:
			continue
		var ds: Array = l.decisions.duplicate()
		ds.sort_custom(func(a: Decision, b: Decision) -> bool: return l.ahead(l.s_begin, a.at_s) < l.ahead(l.s_begin, b.at_s))
		if ds.is_empty():
			if l.road.loop:
				out.append({"key": l, "lane": l, "s0": 0.0, "s1": 0.0, "next": [l]})
			continue
		for i in ds.size():
			var d: Decision = ds[i]
			var s0 := l.s_begin
			if i > 0:
				s0 = (ds[i - 1] as Decision).at_s
			elif l.road.loop:
				s0 = (ds[ds.size() - 1] as Decision).at_s
			var nxt: Array = []
			for cn: Connector in d.options:
				nxt.append(piece_key(cn.to_lane, cn.to_s))
			if not d.mandatory:
				nxt.append(piece_key(l, l.advance(d.at_s, 1.0)))
			out.append({"key": d, "lane": l, "s0": s0, "s1": d.at_s, "next": nxt})
	return out


func _add_junction(jd: Dictionary) -> void:
	var parent := network.get_road(String(jd["parent"]))
	var child := network.get_road(String(jd["child"]))
	if parent == null or child == null or not parent.traffic or not child.traffic:
		return
	var j := Junction.new()
	j.id = junctions.size()
	j.parent = parent
	j.child = child
	j.child_end = int(jd["child_end"])
	var pi := int(jd["parent_index"])
	j.parent_s = pi * parent.ds
	j.center = parent.pos[pi]
	var end_s := 0.0 if j.child_end == 0 else child.length
	var inward := 1 if j.child_end == 0 else -1
	# Stop line well clear of the major road's edge (vehicles then cross the seam rolling, not from rest).
	var edge := parent.width * 0.5 + parent.shoulder + 2.5
	var a := 0.0
	while a < 45.0:
		if _dist_to_centerline(parent, pi, child.point_at(end_s + inward * a)) >= edge:
			break
		a += 0.5
	j.stop_s = end_s + inward * a
	var ct := child.flat_tangent_at(j.stop_s)
	var pt := parent.flat_tangent_at(j.parent_s)
	var sin_a := maxf(absf(pt.cross(ct).y), 0.5)
	var branch := child.width * 0.5 / sin_a + BRANCH_CLEAR
	j.radius = maxf(edge, branch) + 2.0
	var p_lanes: Array = lanes_by_road[parent.idx]
	var c_lanes: Array = lanes_by_road[child.idx]
	j.parent_lanes = p_lanes
	# Minor road -> major road: stop line, give way, mandatory choice of direction.
	for ca: Lane in c_lanes:
		if ca.dir != -inward:
			continue
		ca.s_end = j.stop_s
		var dec := Decision.new()
		dec.at_s = j.stop_s
		dec.mandatory = true
		dec.junction = j
		var cands: Array = []
		for pl: Lane in p_lanes:
			if not pl.outer:
				continue
			var to_s := pl.advance(j.parent_s, branch)
			if not parent.loop and (to_s < 0.0 or to_s > parent.length):
				continue
			cands.append([_turn_deg(ca, j.stop_s, pl, to_s), pl, to_s])
		var any_gentle := false
		for cand: Array in cands:
			any_gentle = any_gentle or float(cand[0]) <= MAX_TURN_DEG
		for cand2: Array in cands:
			if float(cand2[0]) <= MAX_TURN_DEG or not any_gentle:
				dec.options.append(_connector(ca, j.stop_s, cand2[1], cand2[2], j, Yield.MINOR))
		if not dec.options.is_empty():
			ca.decisions.append(dec)
	# Major road -> minor road: optional turn from the outer lane.
	for pl: Lane in p_lanes:
		if not pl.outer:
			continue
		var at_s := pl.advance(j.parent_s, -branch)
		if not parent.loop and (at_s < 0.0 or at_s > parent.length):
			continue
		var dec2 := Decision.new()
		dec2.at_s = at_s
		dec2.junction = j
		for cl: Lane in c_lanes:
			if cl.dir != inward or not cl.outer or _turn_deg(pl, at_s, cl, j.stop_s) > MAX_TURN_DEG:
				continue
			var cn := _connector(pl, at_s, cl, j.stop_s, j, Yield.NONE)
			if cn.turn < 0:
				cn.yield_mode = Yield.ONCOMING
			dec2.options.append(cn)
		if not dec2.options.is_empty():
			pl.decisions.append(dec2)
	for cl: Lane in c_lanes:
		if cl.dir == inward:
			cl.s_begin = j.stop_s
	for cn: Connector in j.connectors:
		if cn.turn > 0:
			continue
		var keep_dir := cn.to_lane.dir if cn.yield_mode == Yield.MINOR else cn.from_lane.dir
		for pl: Lane in p_lanes:
			if pl.dir != keep_dir:
				cn.crosses.append(pl)
	junctions.append(j)


func _turn_deg(from: Lane, at_s: float, to: Lane, to_s: float) -> float:
	var a := from.road.flat_tangent_at(at_s) * from.dir
	var b := to.road.flat_tangent_at(to_s) * to.dir
	return rad_to_deg(a.angle_to(b))


func _connector(from: Lane, at_s: float, to: Lane, to_s: float, j: Junction, mode: int) -> Connector:
	var cn := Connector.new()
	cn.id = connectors.size()
	cn.from_lane = from
	cn.at_s = at_s
	cn.to_lane = to
	cn.to_s = to_s
	cn.junction = j
	cn.yield_mode = mode
	var a := from.point(at_s, from.offset)
	var b := to.point(to_s, to.offset)
	var ta := from.road.tangent_at(at_s) * from.dir
	var tb := to.road.tangent_at(to_s) * to.dir
	var chord := a.distance_to(b)
	var h := chord * 0.42
	var c1 := a + ta * h
	var c2 := b - tb * h
	var n := maxi(int(ceil(chord * 1.3 / CONN_STEP)), 6)
	cn.pts.resize(n + 1)
	cn.cum.resize(n + 1)
	var total := 0.0
	for i in n + 1:
		var p := a.bezier_interpolate(c1, c2, b, float(i) / n)
		# Sit on whichever road surface is underneath (junction crowns/banking), not on the straight blend.
		var y := maxf(_surface_y(from.road, at_s, p), _surface_y(to.road, to_s, p))
		if y > -INF:
			p.y = y
		if i > 0:
			total += p.distance_to(cn.pts[i - 1])
		cn.pts[i] = p
		cn.cum[i] = total
	cn.length = total
	var fa := Vector3(ta.x, 0.0, ta.z).normalized()
	var fb := Vector3(tb.x, 0.0, tb.z).normalized()
	cn.turn = 1 if Vector3(-fa.z, 0.0, fa.x).dot(fb) > 0.0 else -1
	var kmax := 0.0
	for i in range(1, n):
		var d1 := cn.pts[i] - cn.pts[i - 1]
		var d2 := cn.pts[i + 1] - cn.pts[i]
		var ang := absf(Vector2(d1.x, d1.z).angle_to(Vector2(d2.x, d2.z)))
		kmax = maxf(kmax, ang / maxf((d1.length() + d2.length()) * 0.5, 0.1))
	cn.vmax = clampf(sqrt(TURN_LAT / maxf(kmax, 0.0005)), 3.5, 26.0)
	from.outgoing.append(cn)
	to.incoming.append(cn)
	j.connectors.append(cn)
	connectors.append(cn)
	return cn


## Comfortable speed per road sample from the local curvature (measured over 18 m).
func _curve_speeds(r: RoadNetwork.Road) -> PackedFloat32Array:
	var n := r.count()
	var v := PackedFloat32Array()
	v.resize(n)
	var tans: Array[Vector3] = []
	tans.resize(n)
	for i in n:
		tans[i] = r.flat_tangent_at(i * r.ds)
	for i in n:
		var i0 := i - 3
		var i1 := i + 3
		if r.loop:
			i0 = posmod(i0, n)
			i1 = posmod(i1, n)
		else:
			i0 = maxi(i0, 0)
			i1 = mini(i1, n - 1)
		var k := tans[i0].angle_to(tans[i1]) / 18.0
		v[i] = minf(sqrt(LAT_COMFORT / maxf(k, 0.0001)), 45.0)
		# Crests: keep the wheels planted (vertical acceleration under ~half of gravity).
		var y0 := r.pos[i0].y
		var y1 := r.pos[i].y
		var y2 := r.pos[i1].y
		var crest := ((y1 - y0) / maxf((i - i0) * r.ds, 1.0) - (y2 - y1) / maxf((i1 - i) * r.ds, 1.0)) / 9.0
		if crest > 0.0005:
			v[i] = minf(v[i], sqrt(CREST_G / crest))
	return v


## Bakes braking anticipation into the profile for one travel direction.
func _anticipate(base: PackedFloat32Array, r: RoadNetwork.Road, dir: int) -> PackedFloat32Array:
	var v := base.duplicate()
	var n := v.size()
	var step := 2.0 * PROFILE_DECEL * r.ds
	for _pass in (2 if r.loop else 1):
		if dir > 0:
			for i in range(n - 1, -1, -1):
				var nx := i + 1
				if nx >= n:
					if not r.loop:
						continue
					nx = 0
				v[i] = minf(v[i], sqrt(v[nx] * v[nx] + step))
		else:
			for i in n:
				var pv := i - 1
				if pv < 0:
					if not r.loop:
						continue
					pv = n - 1
				v[i] = minf(v[i], sqrt(v[pv] * v[pv] + step))
	return v


## Arclength on r closest to p, searched from s_hint (a few projection steps).
static func project_s(r: RoadNetwork.Road, p: Vector3, s_hint: float) -> float:
	var ss := s_hint
	for k in 5:
		var q := r.point_at(ss)
		var t := r.flat_tangent_at(ss)
		var step := clampf((p.x - q.x) * t.x + (p.z - q.z) * t.z, -15.0, 15.0)
		ss = fposmod(ss + step, r.length) if r.loop else clampf(ss + step, 0.0, r.length)
		if absf(step) < 0.05:
			break
	return ss


## Road surface height under p (with banking), or -INF when p is off that road.
func _surface_y(r: RoadNetwork.Road, s_hint: float, p: Vector3) -> float:
	var ss := project_s(r, p, s_hint)
	var c := r.point_at(ss)
	var lat := (p - c).dot(r.right_at(ss))
	if absf(lat) > r.width * 0.5 + r.shoulder:
		return -INF
	return c.y + lat * r.bank_at(ss)


func _dist_to_centerline(r: RoadNetwork.Road, idx: int, p: Vector3) -> float:
	var best := INF
	var n := r.count()
	var q := Vector2(p.x, p.z)
	for i in range(idx - 25, idx + 25):
		var ia := i
		var ib := i + 1
		if r.loop:
			ia = posmod(ia, n)
			ib = posmod(ib, n)
		elif ia < 0 or ib >= n:
			continue
		var a := Vector2(r.pos[ia].x, r.pos[ia].z)
		var ab := Vector2(r.pos[ib].x, r.pos[ib].z) - a
		var t := clampf((q - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
		best = minf(best, q.distance_to(a + ab * t))
	return best
