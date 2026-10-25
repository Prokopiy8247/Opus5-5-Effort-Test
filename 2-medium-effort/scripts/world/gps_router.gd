class_name GpsRouter
extends RefCounted
## Dijkstra over the junction graph (nodes = junctions, edges = roads) for the GPS route.

static var last_length: float = 0.0


static func route(w: WorldData, from: Vector3, to: Vector3) -> PackedVector2Array:
	var a: Dictionary = w.nearest_road_point(from)
	var b: Dictionary = w.nearest_road_point(to)
	if a.is_empty() or b.is_empty():
		return PackedVector2Array()
	var out := PackedVector2Array()
	if a.road == b.road:
		_append(w, out, a.road, a.s, b.s)
		last_length = absf(b.s - a.s)
		return out
	var ra: Dictionary = w.roads[a.road]
	var rb: Dictionary = w.roads[b.road]
	# start candidates: both ends of road a; goal: both ends of road b
	var dist: Dictionary = {}
	var prev: Dictionary = {}
	var open: Array = []
	dist[ra.from] = a.s
	dist[ra.to] = ra.length - a.s
	prev[ra.from] = ["start", a.road, a.s, 0.0]
	prev[ra.to] = ["start", a.road, a.s, ra.length]
	open = [ra.from, ra.to]
	var visited: Dictionary = {}
	while not open.is_empty():
		open.sort_custom(func(x, y): return dist[x] < dist[y])
		var n: String = open.pop_front()
		if visited.has(n):
			continue
		visited[n] = true
		for e in w.node_roads[n]:
			var ri: int = e[0]
			var r: Dictionary = w.roads[ri]
			var other: String = r.to if e[1] else r.from
			var nd: float = dist[n] + r.length
			if not dist.has(other) or nd < dist[other]:
				dist[other] = nd
				prev[other] = [n, ri, 0.0 if e[1] else r.length, r.length if e[1] else 0.0]
				open.append(other)
	var best: String = ""
	var best_d: float = INF
	for end in [[rb.from, b.s], [rb.to, rb.length - b.s]]:
		if dist.has(end[0]) and dist[end[0]] + end[1] < best_d:
			best_d = dist[end[0]] + end[1]
			best = end[0]
	if best == "":
		return out
	last_length = best_d
	# rebuild chain of road segments
	var chain: Array = []
	var cur: String = best
	var guard: int = 0
	while prev.has(cur) and guard < 100:
		guard += 1
		var pv: Array = prev[cur]
		chain.push_front([pv[1], pv[2], pv[3]])
		if pv[0] == "start":
			break
		cur = pv[0]
	for c in chain:
		_append(w, out, c[0], c[1], c[2])
	_append(w, out, b.road, 0.0 if best == rb.from else rb.length, b.s)
	return out


static func _append(w: WorldData, out: PackedVector2Array, ri: int, s0: float, s1: float) -> void:
	var stepf: float = 20.0 if s1 >= s0 else -20.0
	var s: float = s0
	var n: int = int(absf(s1 - s0) / 20.0)
	for i in n + 1:
		var p: Vector3 = w.road_point(ri, s).origin
		out.append(Vector2(p.x, p.z))
		s += stepf
	var pe: Vector3 = w.road_point(ri, s1).origin
	out.append(Vector2(pe.x, pe.z))
