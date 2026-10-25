class_name RoadGraph
extends RefCounted
## Routing graph over the road network (nodes every few samples + junctions), Dijkstra GPS.

const STEP := 5

var data: WorldData
var adj := {}     # node key -> Array of [neighbour key, cost]
var pos := {}     # node key -> Vector3


static func key(road_index: int, i: int) -> int:
	return (road_index << 16) | i


func build(d: WorldData) -> void:
	data = d
	for road in d.roads:
		var n := road.pts.size()
		var idxs: Array[int] = []
		var i := 0
		while i < n:
			idxs.append(i)
			i += STEP
		if idxs[idxs.size() - 1] != n - 1:
			idxs.append(n - 1)
		# junction indices of side roads that join this one
		for other in d.roads:
			for j in other.junctions:
				if j.road == road.id and not idxs.has(int(j.road_i)):
					idxs.append(int(j.road_i))
		idxs.sort()
		for k in idxs.size():
			var a := key(road.index, idxs[k])
			pos[a] = road.pts[idxs[k]]
			if k > 0:
				_link(a, key(road.index, idxs[k - 1]), float(idxs[k] - idxs[k - 1]) * 4.0)
		if road.closed and idxs.size() > 2:
			_link(key(road.index, idxs[0]), key(road.index, idxs[idxs.size() - 1]), 4.0)
		for j in road.junctions:
			var main := d.road_by_id(j.road)
			if main:
				_link(key(road.index, int(j.self_i)), key(main.index, int(j.road_i)), 1.0)


func _link(a: int, b: int, cost: float) -> void:
	if not adj.has(a):
		adj[a] = []
	if not adj.has(b):
		adj[b] = []
	(adj[a] as Array).append([b, cost])
	(adj[b] as Array).append([a, cost])


func nearest_node(p: Vector3) -> int:
	var nr := data.nearest_road(p, 2500.0)
	if nr.is_empty():
		return -1
	var road: WorldData.Road = nr.road
	var best := -1
	var bd := INF
	for k in pos:
		if (k >> 16) != road.index:
			continue
		var d := (pos[k] as Vector3).distance_squared_to(p)
		if d < bd:
			bd = d
			best = k
	return best


## Returns the route as world points (empty if none).
func route(from: Vector3, to: Vector3) -> PackedVector3Array:
	var s := nearest_node(from)
	var t := nearest_node(to)
	var out := PackedVector3Array()
	if s < 0 or t < 0:
		return out
	var dist := {s: 0.0}
	var prev := {}
	var open: Array = [[0.0, s]]
	var done := {}
	while not open.is_empty():
		var bi := 0
		for q in open.size():
			if open[q][0] < open[bi][0]:
				bi = q
		var cur: Array = open[bi]
		open.remove_at(bi)
		var u: int = cur[1]
		if done.has(u):
			continue
		done[u] = true
		if u == t:
			break
		for e in adj.get(u, []):
			var v: int = e[0]
			var nd: float = dist[u] + e[1]
			if nd < float(dist.get(v, INF)):
				dist[v] = nd
				prev[v] = u
				open.append([nd, v])
	if not dist.has(t):
		return out
	var chain: Array[int] = [t]
	while chain[chain.size() - 1] != s:
		chain.append(prev[chain[chain.size() - 1]])
	chain.reverse()
	# expand to every road sample between consecutive nodes on the same road
	for k in chain.size():
		var a: int = chain[k]
		if k == 0:
			out.append(pos[a])
			continue
		var b: int = chain[k - 1]
		var ra := a >> 16
		if ra == (b >> 16):
			var road := data.roads[ra]
			var i0 := b & 0xFFFF
			var i1 := a & 0xFFFF
			var stp := 1 if i1 > i0 else -1
			if road.closed and absi(i1 - i0) > road.pts.size() / 2:
				out.append(pos[a])
				continue
			var i := i0 + stp
			while i != i1 + stp:
				out.append(road.pts[i])
				i += stp
		else:
			out.append(pos[a])
	return out
