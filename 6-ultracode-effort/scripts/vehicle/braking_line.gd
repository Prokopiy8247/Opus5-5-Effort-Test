extends MeshInstance3D
## Braking line assist (Settings "braking_line"): a ribbon on the road ahead of the player car, coloured per
## point by comparing the current speed with the speed the car could still brake down to for the corners
## ahead: green = fine, yellow = lift, red = brake now. Follows the road the car is on, on the car's line.
## Where the road ends, the end is a speed limit too: the turn onto the road it joins, or a stop at a dead end.
## The road is kept while the car stays on it: a side road whose first samples cross the lane in a junction
## mouth only takes over when the car turns onto it.

const AHEAD := 190.0
const STEP := 3.0
const WIDTH := 0.75
const GREEN := Color(0.15, 0.95, 0.35)
const YELLOW := Color(1.0, 0.8, 0.1)
const RED := Color(1.0, 0.12, 0.08)
## The car keeps its road up to this far beyond the paved half-width (shoulder, verge).
const KEEP_MARGIN := 2.5
## Another road takes over only while the car heads along it (within about 60 degrees).
const ALIGN_COS := 0.5

var _im := ImmediateMesh.new()
var _mat := StandardMaterial3D.new()
var _road: RoadNetwork.Road = null
var _s: float = 0.0
var _lat: float = 0.0
var _dir: float = 1.0


func _ready() -> void:
	top_level = true
	mesh = _im
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.vertex_color_use_as_albedo = true
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	material_override = _mat


func _process(_delta: float) -> void:
	_im.clear_surfaces()
	var car := Game.player_car
	if not bool(Settings.get_value("braking_line", false)) or car == null or not is_instance_valid(car) \
			or Game.photo_mode or not (Game.world is World):
		_road = null
		return
	if car.speed_ms < 4.0:
		return
	var vel := car.linear_velocity
	vel.y = 0.0
	var prev := _road
	if not _track_road((Game.world as World).data.network, car.global_position, vel):
		return
	var r := _road
	var along := vel.dot(r.flat_tangent_at(_s))
	if r != prev or absf(along) > 0.5:
		_dir = 1.0 if along >= 0.0 else -1.0
	var dir := _dir
	var hw := r.width * 0.5
	var lat := clampf(_lat, -hw + 0.5, hw - 0.5)
	var s0 := _s
	var wet := CarController.wetness
	var grip := car.data.tire_grip if car.data else 1.0
	var a_lat := 8.0 * grip * (1.0 - 0.3 * wet)
	var a_brk := 7.5 * grip * (1.0 - 0.3 * wet)
	var n := int(AHEAD / STEP)
	var ss := PackedFloat32Array()
	var vt := PackedFloat32Array()
	var road_end := false
	for k in n + 1:
		var s := s0 + dir * float(k) * STEP
		if r.loop:
			s = fposmod(s, r.length)
		elif s < 0.0 or s > r.length:
			road_end = true
			break
		var a := r.point_at(s - 6.0)
		var b := r.point_at(s)
		var c := r.point_at(s + 6.0)
		ss.append(s)
		vt.append(minf(sqrt(a_lat * _radius(a, b, c)), 120.0))
	if road_end:
		var s_end := r.length if dir > 0.0 else 0.0
		if ss.is_empty() or absf(ss[ss.size() - 1] - s_end) > 0.5:
			ss.append(s_end)
			vt.append(120.0)
		vt[vt.size() - 1] = _end_speed(r, dir, a_lat)
	var m := ss.size()
	if m < 4:
		return
	# Backward pass: the fastest speed at each point from which the corners ahead can still be made.
	for k in range(m - 2, -1, -1):
		var step := STEP if r.loop else absf(ss[k + 1] - ss[k])
		vt[k] = minf(vt[k], sqrt(vt[k + 1] * vt[k + 1] + 2.0 * a_brk * step))
	var v := car.speed_ms
	_im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP, _mat)
	for k in range(2, m):
		var s := ss[k]
		var p := r.surface_point(s, lat) + Vector3.UP * 0.07
		var rt := r.right_at(s)
		var ratio := v / maxf(vt[k], 0.1)
		var col := GREEN.lerp(YELLOW, clampf((ratio - 0.88) / 0.1, 0.0, 1.0))
		col = col.lerp(RED, clampf((ratio - 1.0) / 0.06, 0.0, 1.0))
		# Fade in near the car and out at the look-ahead limit (not at a road end: the line runs up to it).
		col.a = 0.8 * clampf(float(k - 2) / 4.0, 0.0, 1.0) * (1.0 if road_end else clampf(float(m - 1 - k) / 8.0, 0.0, 1.0))
		_im.surface_set_color(col)
		_im.surface_add_vertex(p - rt * WIDTH * 0.5)
		_im.surface_set_color(col)
		_im.surface_add_vertex(p + rt * WIDTH * 0.5)
	_im.surface_end()


## Picks the road the line follows and the car's place on it (_road, _s, _lat). The current road is kept while
## the car is on it and heading along it; another road takes over when the car is on that one and heading along
## it, closer to its direction than to the current road's (turning off at a junction); off every road surface
## the current road is kept within KEEP_MARGIN, else the nearest road wins, one along the travel direction
## before a branch crossing the car's path.
func _track_road(net: RoadNetwork, pos: Vector3, vel: Vector3) -> bool:
	var cur := {}
	if _road != null:
		cur = _fit(_road, pos, _s, vel)
		if not cur["near"]:
			# Moved along the road faster than the local search reaches (teleport, rewind, a long frame).
			var again := net.nearest(pos, 25.0, func(rr: RoadNetwork.Road) -> bool: return rr == _road)
			if not again.is_empty():
				cur = _fit(_road, pos, float(again["s"]), vel)
		if cur["on"] and cur["aligned"]:
			_take(cur)
			return true
	var other := _nearest_fit(net, pos, vel, _road)
	if not other.is_empty() and other["on"] and other["aligned"] \
			and (cur.is_empty() or not cur["near"] or float(other["align"]) > float(cur["align"])):
		_take(other)
		return true
	if not cur.is_empty() and cur["near"]:
		_take(cur)
		return true
	# Off every road surface and away from the current road (or none yet): the nearest road overall.
	var best := other if _road == null else _nearest_fit(net, pos, vel, null)
	if best.is_empty():
		_road = null
		return false
	if not best["aligned"]:
		var alt := _nearest_fit(net, pos, vel, best["road"])
		if not alt.is_empty() and alt["near"] and alt["aligned"]:
			best = alt
	_take(best)
	return true


func _take(f: Dictionary) -> void:
	_road = f["road"]
	_s = f["s"]
	_lat = f["lat"]


## _fit() on the road nearest to pos (within 25 m), skipping `skip`; {} when there is none.
func _nearest_fit(net: RoadNetwork, pos: Vector3, vel: Vector3, skip: RoadNetwork.Road) -> Dictionary:
	var near: Dictionary
	if skip == null:
		near = net.nearest(pos, 25.0)
	else:
		near = net.nearest(pos, 25.0, func(rr: RoadNetwork.Road) -> bool: return rr != skip)
	if near.is_empty():
		return {}
	return _fit(near["road"], pos, float(near["s"]), vel)


## Where pos lies on road r, measured to the centreline segments within 8 samples of s_hint (the end segments of
## a road that is not a loop are extended, so a car past its end is off it):
## {road, s, lat, on (on the paved width), near (within KEEP_MARGIN of it), align (|cos| of the heading to the
## road), aligned (heading along it)}.
static func _fit(r: RoadNetwork.Road, pos: Vector3, s_hint: float, vel: Vector3) -> Dictionary:
	var n := r.pos.size()
	var q := Vector2(pos.x, pos.z)
	var i0 := int(roundf(s_hint / r.ds))
	var best := INF
	var bs := s_hint
	var bl := 0.0
	var by := pos.y
	for i in range(i0 - 8, i0 + 8):
		if not r.loop and (i < 0 or i >= n - 1):
			continue
		var pa := r.pos[posmod(i, n)]
		var pb := r.pos[posmod(i + 1, n)]
		var a := Vector2(pa.x, pa.z)
		var ab := Vector2(pb.x, pb.z) - a
		var t := (q - a).dot(ab) / maxf(ab.length_squared(), 1e-6)
		t = clampf(t, -INF if (not r.loop and i == 0) else 0.0, INF if (not r.loop and i == n - 2) else 1.0)
		var c := a + ab * t
		var d := q.distance_squared_to(c)
		if d < best:
			best = d
			bs = (float(i) + t) * r.ds
			bl = (q - c).dot(Vector2(-ab.y, ab.x).normalized())
			by = lerpf(pa.y, pb.y, clampf(t, 0.0, 1.0))
	if r.loop:
		bs = fposmod(bs, r.length)
	# Off the road's length, or a road passing above or below (bridges): not on this road.
	var valid := best < INF and (r.loop or (bs >= 0.0 and bs <= r.length)) and absf(pos.y - by) < 5.0
	var hw := r.width * 0.5
	var v := vel.length()
	var align := absf(vel.dot(r.flat_tangent_at(bs))) / v if v > 0.5 else 1.0
	return {"road": r, "s": bs, "lat": bl, "on": valid and absf(bl) <= hw, "near": valid and absf(bl) <= hw + KEEP_MARGIN,
		"align": align, "aligned": align >= ALIGN_COS}


## Speed to arrive at the end of road r (travelling in direction dir): the turn onto the road it joins,
## or 0 at a dead end. A shallow merge is no limit.
static func _end_speed(r: RoadNetwork.Road, dir: float, a_lat: float) -> float:
	var j: Dictionary = r.j_end if dir > 0.0 else r.j_start
	var w := Game.world as World
	var parent: RoadNetwork.Road = w.data.network.get_road(String(j.get("road", ""))) if w != null and not j.is_empty() else null
	if parent == null:
		return 0.0
	var s_end := r.length if dir > 0.0 else 0.0
	var d_in := r.flat_tangent_at(s_end) * dir
	var t_p := parent.flat_tangent_at(float(j.get("index", 0)) * parent.ds)
	var turn := minf(d_in.angle_to(t_p), d_in.angle_to(-t_p))
	if turn < deg_to_rad(15.0):
		return 120.0
	# Corner radius of the junction mouth: its apron is about the tangent length of the turn.
	var radius := maxf(float(j.get("apron", 10.0)) / tan(turn * 0.5), 6.0)
	return minf(sqrt(a_lat * radius), 120.0)


static func _radius(a: Vector3, b: Vector3, c: Vector3) -> float:
	var ab := Vector2(b.x - a.x, b.z - a.z)
	var bc := Vector2(c.x - b.x, c.z - b.z)
	var cr := absf(ab.cross(bc))
	if cr < 1e-6:
		return 1e5
	return ab.length() * bc.length() * Vector2(c.x - a.x, c.z - a.z).length() / (2.0 * cr)
