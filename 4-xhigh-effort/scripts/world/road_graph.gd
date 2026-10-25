class_name RoadGraph
extends RefCounted
## Junction graph built from baked road samples. Nodes are junctions and road ends; edges are
## road spans between them (both directions drivable). Used by GPS routing and traffic.

class Edge:
	var id := 0
	var road := 0
	var i0 := 0          ## start sample index (inclusive)
	var i1 := 0          ## end sample index (may wrap for closed roads: i1 < i0)
	var a := 0           ## node at i0
	var b := 0           ## node at i1
	var length := 0.0
	var count := 0       ## number of sample steps

var roads: Array
var edges: Array[Edge] = []
var node_edges := {}     ## node -> Array[int] of edge ids
var node_pos := {}       ## node -> Vector3
var node_priority := {}  ## node -> Dictionary road_index -> priority
var _parent := {}


func build(world_roads: Array) -> void:
	roads = world_roads
	var index := {}
	for i in roads.size():
		index[String(roads[i].id)] = i
	var cuts := {}  # road -> sorted indices
	for ri in roads.size():
		var r: Dictionary = roads[ri]
		var n := (r.pts as PackedVector3Array).size()
		var c := {}
		if not r.closed:
			c[0] = true
			c[n - 1] = true
		for j: Dictionary in r.junctions:
			c[clampi(int(roundf(float(j.s) / 2.0)), 0, n - 1)] = true
		if r.closed and c.is_empty():
			c[0] = true
		var arr := c.keys()
		arr.sort()
		cuts[ri] = arr
	# union junction pairs into shared nodes
	for ri in roads.size():
		var r: Dictionary = roads[ri]
		var n := (r.pts as PackedVector3Array).size()
		for j: Dictionary in r.junctions:
			var oi: int = index[String(j.other)]
			var on := ((roads[oi].pts) as PackedVector3Array).size()
			var a := _key(ri, clampi(int(roundf(float(j.s) / 2.0)), 0, n - 1))
			var b := _key(oi, clampi(int(roundf(float(j.other_s) / 2.0)), 0, on - 1))
			_union(a, b)
	var node_ids := {}
	for ri in roads.size():
		var arr: Array = cuts[ri]
		var r: Dictionary = roads[ri]
		var pts: PackedVector3Array = r.pts
		var n := pts.size()
		var segs := arr.size() if r.closed else arr.size() - 1
		for k in segs:
			var i0: int = arr[k]
			var i1: int = arr[(k + 1) % arr.size()]
			var e := Edge.new()
			e.id = edges.size()
			e.road = ri
			e.i0 = i0
			e.i1 = i1
			e.count = (i1 - i0) if i1 > i0 else (n - i0 + i1)
			e.length = e.count * 2.0
			e.a = _node(node_ids, _find(_key(ri, i0)), pts[i0])
			e.b = _node(node_ids, _find(_key(ri, i1)), pts[i1])
			edges.append(e)
			(node_edges[e.a] as Array).append(e.id)
			(node_edges[e.b] as Array).append(e.id)
			for nd: int in [e.a, e.b]:
				if not node_priority.has(nd):
					node_priority[nd] = {}
				(node_priority[nd] as Dictionary)[ri] = _priority(r)


func _priority(r: Dictionary) -> int:
	return {"highway": 5, "regional": 4, "mountain": 3, "village": 2, "gravel": 1, "dirt": 0}.get(String(r["class"]), 0)


func _key(ri: int, i: int) -> int:
	return ri * 1000000 + i


func _find(k: int) -> int:
	if not _parent.has(k):
		_parent[k] = k
		return k
	var p: int = _parent[k]
	if p == k:
		return k
	var root := _find(p)
	_parent[k] = root
	return root


func _union(a: int, b: int) -> void:
	var ra := _find(a)
	var rb := _find(b)
	if ra != rb:
		_parent[ra] = rb


func _node(ids: Dictionary, root: int, pos: Vector3) -> int:
	if not ids.has(root):
		ids[root] = ids.size()
		node_edges[ids[root]] = []
		node_pos[ids[root]] = pos
	return ids[root]


## Sample index list along an edge from one end (from_a = start at node a).
func edge_indices(e: Edge, from_a: bool) -> PackedInt32Array:
	var n := (roads[e.road].pts as PackedVector3Array).size()
	var out := PackedInt32Array()
	for k in e.count + 1:
		out.append((e.i0 + k) % n)
	if not from_a:
		out.reverse()
	return out


## Locate (edge, offset steps from i0) of a road sample.
func locate(ri: int, i: int) -> Array:
	var r: Dictionary = roads[ri]
	var n := (r.pts as PackedVector3Array).size()
	for e in edges:
		if e.road != ri:
			continue
		var off := (i - e.i0 + n) % n if r.closed else i - e.i0
		if off >= 0 and off <= e.count:
			return [e, off]
	return []


## Dijkstra between two road positions; returns PackedVector3Array of samples (every 2 m).
func route(start_road: int, start_i: int, goal_road: int, goal_i: int) -> PackedVector3Array:
	var sl := locate(start_road, start_i)
	var gl := locate(goal_road, goal_i)
	if sl.is_empty() or gl.is_empty():
		return PackedVector3Array()
	var se: Edge = sl[0]
	var ge: Edge = gl[0]
	var s_off: int = sl[1]
	var g_off: int = gl[1]
	var pts_of := func(e: Edge, from_off: int, to_off: int) -> PackedVector3Array:
		var rp: PackedVector3Array = roads[e.road].pts
		var n := rp.size()
		var out := PackedVector3Array()
		var step := 1 if to_off >= from_off else -1
		var k := from_off
		while true:
			out.append(rp[(e.i0 + k) % n])
			if k == to_off:
				break
			k += step
		return out
	if se == ge:
		return pts_of.call(se, s_off, g_off)
	var dist := {}
	var prev := {}
	var open := {}
	dist[se.a] = s_off * 2.0
	dist[se.b] = (se.count - s_off) * 2.0
	open[se.a] = true
	open[se.b] = true
	while not open.is_empty():
		var best := -1
		var bd := INF
		for nd: int in open:
			if float(dist[nd]) < bd:
				bd = dist[nd]
				best = nd
		open.erase(best)
		if best == ge.a or best == ge.b:
			pass
		for eid: int in node_edges[best]:
			var e := edges[eid]
			var other := e.b if e.a == best else e.a
			var nd2 := bd + e.length
			if not dist.has(other) or nd2 < float(dist[other]):
				dist[other] = nd2
				prev[other] = [best, eid]
				open[other] = true
	var to_a := float(dist.get(ge.a, INF)) + g_off * 2.0
	var to_b := float(dist.get(ge.b, INF)) + (ge.count - g_off) * 2.0
	if to_a == INF and to_b == INF:
		return PackedVector3Array()
	var end_node := ge.a if to_a <= to_b else ge.b
	var chain := []
	var cur := end_node
	while prev.has(cur):
		var pr: Array = prev[cur]
		chain.push_front([pr[1], pr[0], cur])
		cur = pr[0]
	var out := PackedVector3Array()
	# from start position to the first node
	out.append_array(pts_of.call(se, s_off, 0 if cur == se.a else se.count))
	for step: Array in chain:
		var e := edges[int(step[0])]
		var from_a := int(step[1]) == e.a
		out.append_array(pts_of.call(e, 0 if from_a else e.count, e.count if from_a else 0))
	out.append_array(pts_of.call(ge, 0 if end_node == ge.a else ge.count, g_off))
	return out
