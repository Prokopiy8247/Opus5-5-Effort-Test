extends Node3D
## GPS: waypoint, shortest route over the road graph, a chevron route line drawn just above the
## road surface for the next stretch, and route points for the minimap/map.

var _waypoint := Vector3.INF
var _route := PackedVector3Array()
var _line: MeshInstance3D
var _mat: StandardMaterial3D
var _timer := 0.0


func _ready() -> void:
	_line = MeshInstance3D.new()
	_line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mat = StandardMaterial3D.new()
	_mat.albedo_color = Color(1.0, 0.25, 0.55, 0.85)
	_mat.emission_enabled = true
	_mat.emission = Color(1.0, 0.2, 0.5)
	_mat.emission_energy_multiplier = 1.6
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	add_child(_line)


func waypoint() -> Vector3:
	return _waypoint


func route_points() -> PackedVector3Array:
	return _route


func set_waypoint(p: Vector3) -> void:
	_waypoint = p
	_recompute()
	Game.notify("GPS", "Route set", "small")


func clear_waypoint() -> void:
	_waypoint = Vector3.INF
	_route = PackedVector3Array()
	_line.mesh = null


## G: route to the nearest activity start (press again to clear the route).
func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("waypoint") or Game.input_blocked() or Game.player == null:
		return
	get_viewport().set_input_as_handled()
	if _waypoint != Vector3.INF:
		clear_waypoint()
		Game.notify("GPS", "Route cleared", "small")
		return
	if Game.activities == null or not Game.activities.has_method("markers"):
		return
	var p := Game.player.global_position
	var best: Dictionary = {}
	var bd := INF
	for m: Dictionary in Game.activities.markers():
		var d := p.distance_squared_to(m.pos)
		if d > 900.0 and d < bd:
			bd = d
			best = m
	if not best.is_empty():
		set_waypoint(best.pos)
		Game.notify("GPS", "Nearest event: %s" % best.name, "small")


func _process(delta: float) -> void:
	if _waypoint == Vector3.INF or Game.player == null or not is_instance_valid(Game.player):
		return
	var p := Game.player.global_position
	if Vector2(p.x - _waypoint.x, p.z - _waypoint.z).length() < 30.0:
		Game.notify("Destination reached", "", "info")
		clear_waypoint()
		return
	_timer -= delta
	if _timer <= 0.0:
		_timer = 1.5
		_recompute()


func _recompute() -> void:
	var w: Node = Game.world
	if w == null or w.get("graph") == null or Game.player == null:
		return
	var roads: RoadNetwork = w.roads
	var a := roads.nearest(Game.player.global_position, 400.0)
	var b := roads.nearest(_waypoint, 800.0)
	if a.is_empty() or b.is_empty():
		_route = PackedVector3Array()
		return
	var graph: RoadGraph = w.graph
	_route = graph.route(a.road, a.i, b.road, b.i)
	_build_line()


func _build_line() -> void:
	if _route.size() < 2:
		_line.mesh = null
		return
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var count := mini(_route.size() - 1, 450)
	for i in range(0, count, 3):
		var a := _route[i]
		var b := _route[mini(i + 2, _route.size() - 1)]
		var d := b - a
		d.y = 0.0
		if d.length() < 0.01:
			continue
		d = d.normalized()
		var r := Vector3(-d.z, 0, d.x)
		var base := a + Vector3.UP * 0.12
		var tip := base + d * 1.6
		var l := base - r * 0.9
		var rr := base + r * 0.9
		var cl := base - r * 0.9 + d * 0.6
		var cr := base + r * 0.9 + d * 0.6
		for v: Vector3 in [l, tip, cl, rr, cr, tip]:
			st.add_vertex(v)
	st.set_material(_mat)
	_line.mesh = st.commit()
