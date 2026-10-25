extends Node
## GPS: A* over the road graph from the player's nearest road point to the waypoint's nearest road point.
## Graph nodes = road samples at junctions and road ends; edges = road stretches (length in metres,
## unpaved roads weighted) plus junction links (network.junctions: parent road index <-> child road end).
## Provides the route polyline (lane centre, every road sample) to the minimap, world map and the
## 3D guide ribbon; re-routes when the waypoint changes or the player strays > 40 m from the route.

signal route_changed()

const MapData := preload("res://scripts/ui/hud_map_data.gd")

const OFF_ROUTE_M := 40.0
const UNPAVED_WEIGHT := 1.35
const ARRIVE_M := 32.0
const CHECK_INTERVAL := 0.25
const REROUTE_COOLDOWN := 1.5

var active: bool = false
## Route points on the lane centre (3D), one per road sample, and cumulative distance along them.
var points := PackedVector3Array()
var cumulative := PackedFloat32Array()
## Decimated XZ polyline for 2D maps.
var points_2d := PackedVector2Array()
var destination: Vector3 = Vector3.INF
var length_m: float = 0.0
var progress: int = 0
var remaining_m: float = 0.0
var last_compute_ms: float = 0.0

var _net: RoadNetwork
var _node_pos: Array[Vector3] = []
var _node_road := PackedInt32Array()
var _node_idx := PackedInt32Array()
var _adj: Array = []
var _road_keys: Array = []
var _road_key_nodes: Array = []
var _timer: float = 0.0
var _cooldown: float = 0.0
var _pending: bool = false


func _ready() -> void:
	Game.waypoint_changed.connect(_on_waypoint_changed)
	_build_graph()
	if Game.waypoint != Vector3.INF:
		_on_waypoint_changed(Game.waypoint)


# ------------------------------------------------------------------ graph

func _build_graph() -> void:
	_net = MapData.network()
	_node_pos.clear()
	_node_road.clear()
	_node_idx.clear()
	_adj.clear()
	_road_keys.clear()
	_road_key_nodes.clear()
	if _net == null:
		return
	var keys: Array = []
	var by_id := {}
	for r in _net.roads:
		var d := {}
		if not r.loop:
			d[0] = true
			d[r.pos.size() - 1] = true
		keys.append(d)
		by_id[r.id] = r.idx
	var links: Array = []
	for j: Dictionary in _net.junctions:
		var pr: int = by_id.get(String(j.get("parent", "")), -1)
		var cr: int = by_id.get(String(j.get("child", "")), -1)
		if pr < 0 or cr < 0:
			continue
		var pi := clampi(int(j.get("parent_index", 0)), 0, _net.roads[pr].pos.size() - 1)
		var ci := 0 if int(j.get("child_end", 0)) == 0 else _net.roads[cr].pos.size() - 1
		keys[pr][pi] = true
		keys[cr][ci] = true
		links.append([pr, pi, cr, ci])
	var node_of := {}
	for r in _net.roads:
		var d2: Dictionary = keys[r.idx]
		if d2.is_empty():
			d2[0] = true
		var ks: Array = d2.keys()
		ks.sort()
		var pk := PackedInt32Array()
		var pn := PackedInt32Array()
		for k: int in ks:
			var id := _add_node(r.idx, k, r.pos[k])
			node_of[Vector2i(r.idx, k)] = id
			pk.append(k)
			pn.append(id)
		_road_keys.append(pk)
		_road_key_nodes.append(pn)
		var w := _weight(r)
		for a in range(pk.size() - 1):
			_link(pn[a], pn[a + 1], (pk[a + 1] - pk[a]) * r.ds * w, 1)
		if r.loop and pk.size() >= 2:
			var last := pk.size() - 1
			_link(pn[last], pn[0], (r.pos.size() - pk[last] + pk[0]) * r.ds * w, 1)
	for l: Array in links:
		var a2: int = node_of[Vector2i(l[0], l[1])]
		var b2: int = node_of[Vector2i(l[2], l[3])]
		_link(a2, b2, _node_pos[a2].distance_to(_node_pos[b2]), 0)


func _add_node(road: int, idx: int, pos: Vector3) -> int:
	_node_pos.append(pos)
	_node_road.append(road)
	_node_idx.append(idx)
	_adj.append([])
	return _node_pos.size() - 1


## step: +1 = walk the road forward from a to b, -1 backward, 0 = junction jump.
func _link(a: int, b: int, cost: float, step: int) -> void:
	_adj[a].append([b, cost, step])
	_adj[b].append([a, cost, -step])


func _weight(r: RoadNetwork.Road) -> float:
	return 1.0 if r.cls <= WorldLayout.RoadClass.STREET else UNPAVED_WEIGHT


## Nearest road sample to a world position: {road, index} or {}.
func _attach(pos: Vector3) -> Dictionary:
	var res := _net.nearest(pos, 300.0)
	if res.is_empty():
		res = _net.nearest(pos, 1400.0)
	if res.is_empty():
		return {}
	return {"road": (res["road"] as RoadNetwork.Road).idx, "index": int(res["index"])}


## Edges from a point on road ri at sample i to the neighbouring graph nodes: [[node, cost, step]].
func _segment_edges(ri: int, i: int) -> Array:
	var r: RoadNetwork.Road = _net.roads[ri]
	var pk: PackedInt32Array = _road_keys[ri]
	var pn: PackedInt32Array = _road_key_nodes[ri]
	var w := _weight(r)
	var n := r.pos.size()
	var out: Array = []
	var hi := pk.bsearch(i)
	if hi < pk.size() and pk[hi] == i:
		out.append([pn[hi], 0.0, 0])
		return out
	if hi < pk.size():
		out.append([pn[hi], (pk[hi] - i) * r.ds * w, 1])
	elif r.loop:
		out.append([pn[0], (n - i + pk[0]) * r.ds * w, 1])
	if hi > 0:
		out.append([pn[hi - 1], (i - pk[hi - 1]) * r.ds * w, -1])
	elif r.loop:
		out.append([pn[pk.size() - 1], (i + n - pk[pk.size() - 1]) * r.ds * w, -1])
	return out


# ------------------------------------------------------------------ routing

func _on_waypoint_changed(pos: Vector3) -> void:
	if pos == Vector3.INF or is_inf(pos.x):
		clear()
		return
	destination = pos
	_pending = true
	_cooldown = 0.0
	recompute()


func clear() -> void:
	var was := active
	active = false
	_pending = false
	destination = Vector3.INF
	points = PackedVector3Array()
	points_2d = PackedVector2Array()
	cumulative = PackedFloat32Array()
	length_m = 0.0
	remaining_m = 0.0
	progress = 0
	if was:
		route_changed.emit()


func recompute() -> bool:
	if destination == Vector3.INF:
		return false
	if _net == null:
		_build_graph()
	var car := Game.player_car
	if _net == null or car == null or not is_instance_valid(car):
		_pending = true
		return false
	var t0 := Time.get_ticks_usec()
	_pending = false
	_cooldown = REROUTE_COOLDOWN
	var ok := _route(car.global_position, destination)
	last_compute_ms = (Time.get_ticks_usec() - t0) / 1000.0
	if not ok:
		active = false
		points = PackedVector3Array()
		points_2d = PackedVector2Array()
	route_changed.emit()
	return ok


func _route(from: Vector3, to: Vector3) -> bool:
	var sa := _attach(from)
	var ga := _attach(to)
	if sa.is_empty() or ga.is_empty():
		return false
	var s_road: int = sa["road"]
	var s_i: int = sa["index"]
	var g_road: int = ga["road"]
	var g_i: int = ga["index"]
	var s_id := _add_node(s_road, s_i, _net.roads[s_road].pos[s_i])
	var g_id := _add_node(g_road, g_i, _net.roads[g_road].pos[g_i])
	for e: Array in _segment_edges(s_road, s_i):
		_adj[s_id].append(e)
	var touched: Array[int] = []
	for e: Array in _segment_edges(g_road, g_i):
		_adj[int(e[0])].append([g_id, e[1], -int(e[2])])
		touched.append(int(e[0]))
	if s_road == g_road:
		var r: RoadNetwork.Road = _net.roads[s_road]
		var w := _weight(r)
		if r.loop:
			var n := r.pos.size()
			_adj[s_id].append([g_id, posmod(g_i - s_i, n) * r.ds * w, 1])
			_adj[s_id].append([g_id, posmod(s_i - g_i, n) * r.ds * w, -1])
		elif g_i != s_i:
			_adj[s_id].append([g_id, absi(g_i - s_i) * r.ds * w, 1 if g_i > s_i else -1])
		else:
			_adj[s_id].append([g_id, 0.0, 0])
	var path := _astar(s_id, g_id)
	# Remove the temporary nodes / edges again.
	for k in range(touched.size() - 1, -1, -1):
		(_adj[touched[k]] as Array).pop_back()
	for _k in 2:
		_node_pos.pop_back()
		_adj.pop_back()
	var sn := _node_road.size()
	var s_info := [_node_road[sn - 2], _node_idx[sn - 2]]
	var g_info := [_node_road[sn - 1], _node_idx[sn - 1]]
	_node_road.resize(sn - 2)
	_node_idx.resize(sn - 2)
	if path.is_empty():
		return false
	_build_points(path, s_id, g_id, s_info, g_info)
	active = points.size() >= 2
	return active


## A* from s to g. Returns [[node, step_into_node], ...] from s to g, or [] if unreachable.
func _astar(s: int, g: int) -> Array:
	var n := _node_pos.size()
	var gs := PackedFloat32Array()
	gs.resize(n)
	gs.fill(INF)
	var fs := PackedFloat32Array()
	fs.resize(n)
	fs.fill(INF)
	var came := PackedInt32Array()
	came.resize(n)
	came.fill(-1)
	var came_step := PackedInt32Array()
	came_step.resize(n)
	var closed := PackedByteArray()
	closed.resize(n)
	var goal := _node_pos[g]
	gs[s] = 0.0
	fs[s] = _h(_node_pos[s], goal)
	var open: Array[int] = [s]
	while not open.is_empty():
		var bi := 0
		for k in range(1, open.size()):
			if fs[open[k]] < fs[open[bi]]:
				bi = k
		var u: int = open[bi]
		open.remove_at(bi)
		if u == g:
			break
		if closed[u] == 1:
			continue
		closed[u] = 1
		for e: Array in _adj[u]:
			var v: int = e[0]
			if closed[v] == 1:
				continue
			var t := gs[u] + float(e[1])
			if t < gs[v]:
				gs[v] = t
				fs[v] = t + _h(_node_pos[v], goal)
				came[v] = u
				came_step[v] = int(e[2])
				if not open.has(v):
					open.append(v)
	if came[g] < 0 and g != s:
		return []
	var out: Array = []
	var cur := g
	while cur != s:
		out.push_front([cur, came_step[cur]])
		cur = came[cur]
		if cur < 0:
			return []
	out.push_front([s, 0])
	return out


func _h(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _build_points(path: Array, s_id: int, g_id: int, s_info: Array, g_info: Array) -> void:
	var pts := PackedVector3Array()
	for k in range(path.size() - 1):
		var u: int = path[k][0]
		var v: int = path[k + 1][0]
		var step: int = path[k + 1][1]
		var ru: int = s_info[0] if u == s_id else (g_info[0] if u == g_id else _node_road[u])
		var iu: int = s_info[1] if u == s_id else (g_info[1] if u == g_id else _node_idx[u])
		var iv: int = s_info[1] if v == s_id else (g_info[1] if v == g_id else _node_idx[v])
		if step == 0:
			continue
		var r: RoadNetwork.Road = _net.roads[ru]
		var n := r.pos.size()
		var lane := r.lane_offset(1) * 0.85 * step if r.traffic else 0.0
		var i := iu
		var guard := 0
		while guard <= n:
			var np := _lane_point(r, i, lane)
			if pts.is_empty() or not pts[pts.size() - 1].is_equal_approx(np):
				pts.append(np)
			if i == iv:
				break
			i += step
			if r.loop:
				i = posmod(i, n)
			elif i < 0 or i >= n:
				break
			guard += 1
	if pts.is_empty():
		var gr: RoadNetwork.Road = _net.roads[int(g_info[0])]
		pts.append(gr.pos[int(g_info[1])])
	if pts.size() == 1:
		pts.append(pts[0])
	points = pts
	cumulative = PackedFloat32Array()
	cumulative.resize(pts.size())
	var acc := 0.0
	for k in pts.size():
		if k > 0:
			acc += pts[k].distance_to(pts[k - 1])
		cumulative[k] = acc
	length_m = acc
	progress = 0
	remaining_m = acc
	points_2d = PackedVector2Array()
	for k in range(0, pts.size(), 2):
		points_2d.append(Vector2(pts[k].x, pts[k].z))
	if pts.size() > 0 and (pts.size() - 1) % 2 != 0:
		points_2d.append(Vector2(pts[pts.size() - 1].x, pts[pts.size() - 1].z))


func _lane_point(r: RoadNetwork.Road, i: int, lane: float) -> Vector3:
	var n := r.pos.size()
	var p := r.pos[i]
	if lane == 0.0:
		return p
	var a: Vector3
	var b: Vector3
	if r.loop:
		a = r.pos[posmod(i - 1, n)]
		b = r.pos[(i + 1) % n]
	else:
		a = r.pos[maxi(i - 1, 0)]
		b = r.pos[mini(i + 1, n - 1)]
	var t := Vector2(b.x - a.x, b.z - a.z)
	if t.length_squared() < 0.0001:
		return p
	t = t.normalized()
	return p + Vector3(-t.y, 0.0, t.x) * lane


## The road end of the route (where the off-road leg to the waypoint begins).
func road_end() -> Vector3:
	return points[points.size() - 1] if points.size() > 0 else Vector3.INF


# ------------------------------------------------------------------ tracking

func _process(delta: float) -> void:
	_cooldown = maxf(_cooldown - delta, 0.0)
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = CHECK_INTERVAL
	if _pending and _cooldown <= 0.0:
		recompute()
		return
	if not active:
		return
	var car := Game.player_car
	if car == null or not is_instance_valid(car):
		return
	var pos := car.global_position
	var flat := Vector2(pos.x - destination.x, pos.z - destination.z).length()
	# Activity waypoints (race gates) are moved / cleared by their owner; only player waypoints "arrive".
	if flat < ARRIVE_M and Game.waypoint_owner == &"":
		Game.notify("Destination reached", "Waypoint cleared", &"route")
		Game.clear_waypoint()
		return
	var best := INF
	var bi := progress
	var lo := maxi(progress - 20, 0)
	var hi := mini(progress + 240, points.size() - 1)
	for i in range(lo, hi + 1):
		var q := points[i]
		var d := (q.x - pos.x) * (q.x - pos.x) + (q.z - pos.z) * (q.z - pos.z)
		if d < best:
			best = d
			bi = i
	if sqrt(best) > OFF_ROUTE_M:
		if _cooldown <= 0.0:
			recompute()
		return
	progress = bi
	remaining_m = maxf(length_m - cumulative[bi], 0.0) + Vector2(points[points.size() - 1].x - destination.x, points[points.size() - 1].z - destination.z).length()
