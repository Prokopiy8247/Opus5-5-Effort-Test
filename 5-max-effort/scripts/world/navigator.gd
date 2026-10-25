extends Node3D
## GPS: shortest route over the road network (junction graph from roads.json joins, A*) to a
## waypoint, drawn as a glowing chevron ribbon on the road and exposed to the minimap/world map.
## Recomputed every couple of seconds from the car's position, cleared on arrival.

const NODE_MERGE := 6.0
const REPLAN_EVERY := 1.6
const DRAW_AHEAD := 900.0

var data: WorldData
var target := Vector3.INF
var route_points: PackedVector3Array = PackedVector3Array()   # world points along the route
var route_length: float = 0.0
var _nodes: Array[Vector3] = []
var _adj: Array = []          # node -> Array[[node, road, from_i, to_i, length]]
var _road_nodes: Dictionary = {}   # road -> Array[[index, node]] sorted by index
var _mesh: MeshInstance3D
var _replan: float = 0.0
var _arrived: bool = false


func setup(d: WorldData) -> void:
	data = d
	name = "Navigator"
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_build_graph()
	_mesh = MeshInstance3D.new()
	_mesh.name = "RouteRibbon"
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var sm := ShaderMaterial.new()
	sm.shader = load("res://assets/shaders/route.gdshader")
	_mesh.material_override = sm
	add_child(_mesh)


# ------------------------------------------------------------------------------------------------
# graph
func _node_at(p: Vector3) -> int:
	for k in _nodes.size():
		if _nodes[k].distance_to(p) < NODE_MERGE:
			return k
	_nodes.append(p)
	_adj.append([])
	return _nodes.size() - 1


func _build_graph() -> void:
	var keys: Dictionary = {}     # road -> {index: true}
	for ri in data.roads.size():
		var r: Dictionary = data.roads[ri]
		var n := (r["x"] as PackedFloat32Array).size()
		if not keys.has(ri):
			keys[ri] = {}
		if not r["closed"]:
			keys[ri][0] = true
			keys[ri][n - 1] = true
		for j in r["joins"]:
			var tgt := int(j["road"])
			if not keys.has(tgt):
				keys[tgt] = {}
			keys[tgt][int(j["index"])] = true
			keys[ri][0 if int(j["end"]) == 0 else n - 1] = true
	# join endpoints and the joined point on the target are the same node
	for ri in data.roads.size():
		var r: Dictionary = data.roads[ri]
		var n := (r["x"] as PackedFloat32Array).size()
		var list: Array = []
		var idx := (keys[ri] as Dictionary).keys()
		idx.sort()
		if r["closed"] and idx.is_empty():
			idx = [0]
		for i in idx:
			var p := data.road_point(ri, int(i))
			for j in r["joins"]:
				var end_i := 0 if int(j["end"]) == 0 else n - 1
				if int(i) == end_i:
					p = data.road_point(int(j["road"]), int(j["index"]))
			list.append([int(i), _node_at(p)])
		_road_nodes[ri] = list
		for k in list.size() - 1:
			_link(list[k][1], list[k + 1][1], ri, list[k][0], list[k + 1][0])
		if r["closed"] and list.size() >= 1:
			_link(list[list.size() - 1][1], list[0][1], ri, list[list.size() - 1][0], list[0][0] + n)
	print("[nav] road graph: %d nodes" % _nodes.size())


func _seg_len(ri: int, a: int, b: int) -> float:
	return absf(float(b - a)) * 2.0


func _link(na: int, nb: int, ri: int, a: int, b: int) -> void:
	var length := _seg_len(ri, a, b)
	(_adj[na] as Array).append([nb, ri, a, b, length])
	(_adj[nb] as Array).append([na, ri, b, a, length])


func _locate(p: Vector3) -> Dictionary:
	## nearest road sample and the two graph nodes bracketing it
	var nr := data.nearest_road(p.x, p.z, 24)
	if nr.is_empty():
		return {}
	var ri := int(nr["road"])
	var i := int(nr["i"])
	var list: Array = _road_nodes.get(ri, [])
	var n := (data.roads[ri]["x"] as PackedFloat32Array).size()
	var closed: bool = data.roads[ri]["closed"]
	if list.is_empty():
		return {}
	var before: Array = list[list.size() - 1] if closed else list[0]
	var after: Array = list[0] if closed else list[list.size() - 1]
	var before_i := int(before[0]) - (n if closed else 0)
	var after_i := int(after[0]) + (n if closed else 0)
	for e in list:
		if int(e[0]) <= i and int(e[0]) >= before_i:
			before = e
			before_i = int(e[0])
		if int(e[0]) >= i and int(e[0]) <= after_i:
			after = e
			after_i = int(e[0])
	return {"road": ri, "i": i, "a_node": int(before[1]), "a_i": before_i, "b_node": int(after[1]), "b_i": after_i}


func _plan(from: Vector3, to: Vector3) -> PackedVector3Array:
	var s := _locate(from)
	var g := _locate(to)
	var out := PackedVector3Array()
	if s.is_empty() or g.is_empty():
		return out
	# same road segment: direct
	if int(s["road"]) == int(g["road"]) and int(s["a_node"]) == int(g["a_node"]) and int(s["b_node"]) == int(g["b_node"]):
		_append(out, int(s["road"]), int(s["i"]), int(g["i"]))
		return out
	# Dijkstra/A* from the two bracket nodes of the start to the two of the goal
	var count := _nodes.size()
	var dist := PackedFloat32Array()
	dist.resize(count)
	dist.fill(1e18)
	var prev: Array = []
	prev.resize(count)
	var open: Array = []
	var start_cost := {int(s["a_node"]): _seg_len(int(s["road"]), int(s["i"]), int(s["a_i"])),
		int(s["b_node"]): _seg_len(int(s["road"]), int(s["i"]), int(s["b_i"]))}
	for k in start_cost:
		dist[k] = minf(dist[k], start_cost[k])
		prev[k] = null
		open.append(k)
	var goal_cost := {int(g["a_node"]): _seg_len(int(g["road"]), int(g["a_i"]), int(g["i"])),
		int(g["b_node"]): _seg_len(int(g["road"]), int(g["b_i"]), int(g["i"]))}
	var done := {}
	while not open.is_empty():
		var best := 0
		for k in open.size():
			var nk: int = open[k]
			if dist[nk] + _nodes[nk].distance_to(to) < dist[open[best]] + _nodes[open[best]].distance_to(to):
				best = k
		var u: int = open[best]
		open.remove_at(best)
		if done.has(u):
			continue
		done[u] = true
		for e in _adj[u]:
			var v: int = e[0]
			var nd: float = dist[u] + float(e[4])
			if nd < dist[v]:
				dist[v] = nd
				prev[v] = [u, e]
				open.append(v)
	var end_node := -1
	var end_total := 1e18
	for k in goal_cost:
		if dist[k] + float(goal_cost[k]) < end_total:
			end_total = dist[k] + float(goal_cost[k])
			end_node = k
	if end_node < 0 or end_total >= 1e17:
		return out
	# unwind
	var chain: Array = []
	var cur := end_node
	while prev[cur] != null:
		chain.push_front(prev[cur][1])
		cur = int(prev[cur][0])
	var first_i := int(s["a_i"]) if cur == int(s["a_node"]) else int(s["b_i"])
	_append(out, int(s["road"]), int(s["i"]), first_i)
	for e in chain:
		_append(out, int(e[1]), int(e[2]), int(e[3]))
	var last_i := int(g["a_i"]) if end_node == int(g["a_node"]) else int(g["b_i"])
	_append(out, int(g["road"]), last_i, int(g["i"]))
	return out


func _append(out: PackedVector3Array, ri: int, a: int, b: int) -> void:
	var n := (data.roads[ri]["x"] as PackedFloat32Array).size()
	var closed: bool = data.roads[ri]["closed"]
	var step := 1 if b >= a else -1
	var i := a
	while true:
		var k := posmod(i, n) if closed else clampi(i, 0, n - 1)
		var p := data.road_point(ri, k)
		if out.is_empty() or out[out.size() - 1].distance_to(p) > 5.5:
			out.append(p)
		if i == b:
			break
		i += step


# ------------------------------------------------------------------------------------------------
func set_target(p: Vector3) -> void:
	target = p
	_arrived = false
	_replan = 0.0
	if p == Vector3.INF:
		route_points = PackedVector3Array()
		route_length = 0.0
		_mesh.mesh = null


func _process(delta: float) -> void:
	if target == Vector3.INF:
		return
	var car := Game.player_car
	if car == null or not is_instance_valid(car):
		return
	var p := car.global_position
	if Vector2(p.x - target.x, p.z - target.z).length() < 25.0:
		if not _arrived:
			_arrived = true
			if Game.activities == null or Game.activities.get("active") == null:
				Game.show_notification("Destination reached", "", "info")
				set_target(Vector3.INF)
		return
	_replan -= delta
	if _replan > 0.0:
		return
	_replan = REPLAN_EVERY
	route_points = _plan(p, target)
	route_length = 0.0
	for k in route_points.size() - 1:
		route_length += route_points[k].distance_to(route_points[k + 1])
	_build_ribbon(p)


func _build_ribbon(from: Vector3) -> void:
	if route_points.size() < 2:
		_mesh.mesh = null
		return
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var acc := 0.0
	var prev_l := Vector3.ZERO
	var prev_r := Vector3.ZERO
	var prev_u := 0.0
	for k in route_points.size():
		var p := route_points[k]
		var nxt := route_points[mini(k + 1, route_points.size() - 1)]
		var prv := route_points[maxi(k - 1, 0)]
		var d := nxt - prv
		d.y = 0.0
		if d.length() < 0.01:
			continue
		d = d.normalized()
		var right := d.cross(Vector3.UP).normalized()
		var c := p + right * 1.75 + Vector3.UP * 0.12
		var l := c - right * 0.7
		var r := c + right * 0.7
		if k > 0:
			acc += route_points[k - 1].distance_to(p)
			if acc > DRAW_AHEAD:
				break
			st.set_uv(Vector2(prev_u, 0))
			st.add_vertex(prev_l)
			st.set_uv(Vector2(acc / 4.0, 1))
			st.add_vertex(r)
			st.set_uv(Vector2(prev_u, 1))
			st.add_vertex(prev_r)
			st.set_uv(Vector2(prev_u, 0))
			st.add_vertex(prev_l)
			st.set_uv(Vector2(acc / 4.0, 0))
			st.add_vertex(l)
			st.set_uv(Vector2(acc / 4.0, 1))
			st.add_vertex(r)
		prev_l = l
		prev_r = r
		prev_u = acc / 4.0
	_mesh.mesh = st.commit()
