extends Node3D
## Tunnel interiors (child of the environment controller). Finds the tunnel tubes of the road network
## (flag bit 2, the rows RoadBuilder lines with a tube) and fills each with a chain of ReflectionProbes
## whose ambient colour and reflections replace the sky's inside the tube: a dim lamp-lit interior with a
## little daylight spilling in at the portals. The interior is darkened locally, for any camera position,
## so the tube no longer looks like open air from outside and nothing global has to switch at a portal.
## depth(p) gives how far a point is inside a tube; the controller derives exposure, sun shading,
## rain shelter and headlights from it.

const OUTSIDE := -1.0e6
## depth() reports negative distances (metres before a portal) this far out along the tunnel road.
const APPROACH := 60.0
const SEG := 34.0
const MOUTH := 14.0
const BLEND := 2.5
const ROOF := 7.2
## Linear ambient light inside the tube (lamp bounce).
const INTERIOR_AMBIENT := Color(0.06, 0.047, 0.032)
## Share of the outdoor ambient that reaches a probe, by distance of its centre from the nearest portal.
const SPILL := 0.24
const SPILL_FALLOFF := 11.0
const REFLECTION := 0.3

class Span:
	var road: RoadNetwork.Road
	var s0: float
	var s1: float
	var half: float

var spans: Array[Span] = []
var built := false

var _net: RoadNetwork
var _tunnel_roads: Dictionary = {}
var _only_tunnel_roads := func(rr: RoadNetwork.Road) -> bool: return _tunnel_roads.has(rr)
var _spill_probes: Array[ReflectionProbe] = []
var _spill_k: PackedFloat32Array = PackedFloat32Array()
var _outdoor := Color(-1, -1, -1)


## Builds once the world's roads are done; returns true when ready.
func ensure_built() -> bool:
	if built:
		return true
	var w := Game.world as World
	if w == null or w.data == null or w.data.network == null or w.roads == null or not w.roads.done:
		return false
	built = true
	_net = w.data.network
	# Tube rows around a tunnel-flagged run, as WorldGen.tube_mask / RoadBuilder build them.
	var consts: Dictionary = (WorldGen as Script).get_script_constant_map()
	var pre := int(consts.get("TUBE_PRE", 2))
	var post := int(consts.get("TUBE_POST", 1))
	for r in _net.roads:
		var n := r.flags.size()
		var i := 0
		while i < n:
			if (r.flags[i] & 2) == 0:
				i += 1
				continue
			var j := i
			while j < n and (r.flags[j] & 2) != 0:
				j += 1
			var sp := Span.new()
			sp.road = r
			sp.s0 = maxi(i - pre, 0) * r.ds
			sp.s1 = mini(j + post, n - 1) * r.ds
			sp.half = r.width * 0.5 + r.shoulder + 0.6
			spans.append(sp)
			_tunnel_roads[r] = true
			_build_probes(sp, w)
			i = j
	if _outdoor.r >= 0.0:
		_apply_spill()
	return true


## Metres inside a tunnel tube along its road (> 0 inside, measured from the nearer portal), negative
## metres before a portal on the tunnel road (down to -APPROACH), OUTSIDE anywhere else, including points
## beside or above the tube.
func depth(p: Vector3) -> float:
	if not built or spans.is_empty():
		return OUTSIDE
	# Only tunnel roads: another road crossing nearby (or above the tube) must not hide the tunnel.
	var res := _net.nearest(p, 24.0, _only_tunnel_roads)
	if res.is_empty():
		return OUTSIDE
	var r: RoadNetwork.Road = res["road"]
	var c: Vector3 = res["position"]
	var s: float = float(res["s"]) + (p - c).dot(res["forward"] as Vector3)
	for sp in spans:
		if sp.road != r:
			continue
		var d := minf(s - sp.s0, sp.s1 - s)
		if d < -APPROACH:
			continue
		var y := p.y - r.point_at(s).y
		if absf(float(res["lateral"])) > sp.half + 0.8 or y > ROOF + 0.6 or y < -2.5:
			return OUTSIDE
		return d
	return OUTSIDE


## The covered volume of every tube as short straight pieces along its road, for precipitation:
## pairs [Vector4(start on the road, half width), Vector4(end on the road, roof height)]. Pieces overlap a
## little at the joints so the outside of a bend has no gap; the first and last stop at the portal collars.
func roof_segments(step := 6.0) -> Array[Vector4]:
	var out: Array[Vector4] = []
	for sp in spans:
		var a := sp.s0 - 0.4
		var b := sp.s1 + 0.4
		var n := maxi(int(ceil((b - a) / step)), 1)
		for k in n:
			var s0 := a + (b - a) * k / n
			var s1 := a + (b - a) * (k + 1) / n
			var p0 := sp.road.point_at(maxf(s0 - (0.6 if k > 0 else 0.0), a))
			var p1 := sp.road.point_at(minf(s1 + (0.6 if k < n - 1 else 0.0), b))
			out.append(Vector4(p0.x, p0.y, p0.z, sp.half + 0.3))
			out.append(Vector4(p1.x, p1.y, p1.z, ROOF + 0.3))
	return out


## Outdoor ambient light (linear colour * energy) for the daylight spill near the portals. Cheap to call
## every frame: probes are only touched when the light has changed noticeably.
func set_outdoor_ambient(c: Color) -> void:
	if _outdoor.r >= 0.0 and absf(c.r - _outdoor.r) + absf(c.g - _outdoor.g) + absf(c.b - _outdoor.b) < 0.025 * maxf(_outdoor.get_luminance(), 0.05):
		return
	_outdoor = c
	_apply_spill()


func _apply_spill() -> void:
	var c := _outdoor
	for i in _spill_probes.size():
		var k := _spill_k[i]
		_set_ambient(_spill_probes[i], INTERIOR_AMBIENT + Color(c.r * k, c.g * k, c.b * k))


## Probe ambient colours are sRGB; the level goes into the (linear) energy so it stays exact.
static func _set_ambient(probe: ReflectionProbe, linear: Color) -> void:
	var m := maxf(maxf(linear.r, linear.g), maxf(linear.b, 0.0001))
	probe.ambient_color = Color(linear.r / m, linear.g / m, linear.b / m).linear_to_srgb()
	probe.ambient_color_energy = m


func _build_probes(sp: Span, w: World) -> void:
	var length := sp.s1 - sp.s0
	if length < 6.0:
		return
	var cuts: Array[Vector2] = []
	var mouth := minf(MOUTH, length * 0.5)
	cuts.append(Vector2(sp.s0, sp.s0 + mouth + BLEND))
	var inner := length - 2.0 * mouth
	if inner > 0.0:
		var n := maxi(int(ceil(inner / SEG)), 1)
		var step := inner / n
		for k in n:
			var a := sp.s0 + mouth + k * step
			cuts.append(Vector2(a - BLEND, a + step + BLEND))
	cuts.append(Vector2(sp.s1 - mouth - BLEND, sp.s1))
	for cut in cuts:
		_add_probe(sp, w, maxf(cut.x, sp.s0), minf(cut.y, sp.s1))


func _add_probe(sp: Span, w: World, a: float, b: float) -> void:
	var r := sp.road
	var pa := r.point_at(a)
	var pb := r.point_at(b)
	var axis := pb - pa
	if axis.length() < 1.0:
		return
	var dir := axis.normalized()
	var flat := Vector3(dir.x, 0.0, dir.z).normalized()
	var side := Vector3(-flat.z, 0.0, flat.x)
	# Widen for the curve between the ends, and keep the top under the terrain so the hillside above a
	# portal never takes the tunnel ambient.
	var sag := 0.0
	var cover := INF
	var steps := maxi(int((b - a) / 3.0), 1)
	for k in steps + 1:
		var s := lerpf(a, b, float(k) / steps)
		var q := r.point_at(s)
		var rel := q - pa
		sag = maxf(sag, absf(rel.dot(side)))
		for o: float in [-sp.half, 0.0, sp.half]:
			var t := q + r.right_at(s) * o
			cover = minf(cover, w.height_at(t.x, t.z) - q.y)
	var bottom := -3.5
	var top := clampf(cover - 0.3, ROOF + 0.4, ROOF + BLEND + 0.4)
	var probe := ReflectionProbe.new()
	probe.name = "TunnelProbe"
	probe.size = Vector3(2.0 * (sp.half + BLEND + 0.6) + sag * 2.0, top - bottom, axis.length())
	probe.transform = Transform3D(Basis.looking_at(dir, Vector3.UP), (pa + pb) * 0.5 + Vector3.UP * ((top + bottom) * 0.5))
	probe.blend_distance = BLEND
	probe.interior = true
	probe.box_projection = true
	probe.intensity = REFLECTION
	probe.update_mode = ReflectionProbe.UPDATE_ONCE
	probe.ambient_mode = ReflectionProbe.AMBIENT_COLOR
	_set_ambient(probe, INTERIOR_AMBIENT)
	add_child(probe)
	var mid := (a + b) * 0.5
	var from_mouth := minf(mid - sp.s0, sp.s1 - mid)
	var k_spill := SPILL * exp(-from_mouth / SPILL_FALLOFF)
	if k_spill > 0.004:
		_spill_probes.append(probe)
		_spill_k.append(k_spill)
