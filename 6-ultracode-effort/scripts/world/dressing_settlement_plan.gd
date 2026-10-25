extends RefCounted
## Deterministic layouts for every point of interest (villages, farm, hamlets, fuel stations, diners,
## harbour, lighthouse, castle ruins, wind farm, viewpoint, lake jetty, festival hub) plus street lamps.
## Buildings face the nearest road and keep >= road half width + 3 m from road centrelines. Buildings with a
## ground floor stand on the high side of their footprint (their stone plinth covers the low side), other props
## sink into slopes. Produces plain item dictionaries:
##   {name, xf: Transform3D, tint: Color (linear rgb + seed in a), vis: float, col: int, anim: String}
## (optional: light = lamp lit at night, label..., anim "festoon" / "pad" / "apron" for generated geometry)
## and registers every footprint as a dressing exclusion. Main thread, runs once at start-up.

const PropLibrary := preload("res://scripts/world/prop_library.gd")
const Rules := preload("res://scripts/world/dressing_rules.gd")

enum Col { NONE, BOX, TRIMESH, CYLINDER, CONVEX }

const VIS_LANDMARK := 3800.0
const VIS_BUILDING := 1700.0
const VIS_MEDIUM := 750.0
const VIS_SMALL := 330.0

## Buildings and landmarks collide with their pre-baked trimesh (tools/bake_props.tscn writes <Name>_col.res), so
## the car meets the visible walls, passes under eaves and porch roofs and through ruin gaps. Small props use cheap
## boxes / cylinders.
const COLLIDE := {
	"House_Cottage_A": Col.TRIMESH, "House_Cottage_B": Col.TRIMESH, "House_Townhouse": Col.TRIMESH, "Farmhouse": Col.TRIMESH,
	"Barn_Red": Col.TRIMESH, "Silo": Col.TRIMESH, "Shed_Small": Col.TRIMESH, "House_Chalet": Col.TRIMESH, "House_Adobe": Col.TRIMESH,
	"Gas_Station": Col.TRIMESH, "Diner": Col.TRIMESH, "Church": Col.TRIMESH, "Harbour_Shed": Col.TRIMESH, "Boathouse": Col.TRIMESH,
	"Pier_Section": Col.TRIMESH, "Lighthouse": Col.TRIMESH, "Castle_Ruin_Wall": Col.TRIMESH, "Castle_Ruin_Tower": Col.TRIMESH,
	"Wind_Turbine_Tower": Col.TRIMESH, "Water_Tower": Col.TRIMESH, "Festival_Stage": Col.TRIMESH, "Festival_Tent": Col.TRIMESH,
	"Viewpoint_Deck": Col.TRIMESH, "Bus_Stop": Col.TRIMESH, "Billboard": Col.TRIMESH, "Fuel_Pump": Col.TRIMESH,
	"Hay_Bale": Col.TRIMESH, "Log_Pile": Col.TRIMESH, "Lamp_Street": Col.CYLINDER, "Wall_Stone": Col.BOX, "Fence_Wood": Col.BOX,
	"Flag_Pole": Col.CYLINDER, "Festival_Banner": Col.CYLINDER, "Bench": Col.BOX, "Mailbox": Col.BOX, "Bin": Col.CYLINDER,
	"Rock_A": Col.CONVEX, "Rock_C": Col.CONVEX, "Cactus_A": Col.CONVEX, "Cactus_B": Col.CONVEX,
}
const CYL_RADIUS := {"Lamp_Street": 0.16, "Utility_Pole": 0.16, "Flag_Pole": 0.1, "Festival_Banner": 0.06, "Bin": 0.3}
## Thin props on the barrier layer: car bodies hit them, wheel rays never stand on them.
const BARRIER_PROPS := ["Fence_Wood", "Wall_Stone", "Flag_Pole", "Festival_Banner", "Lamp_Street", "Bench", "Mailbox", "Bin",
	"Rock_A", "Rock_C", "Cactus_A", "Cactus_B"]
## Props with doors / windows at the origin level ("floor" ground mode, see place()).
const FLOOR_PROPS := ["House_Cottage_A", "House_Cottage_B", "House_Townhouse", "Farmhouse", "Barn_Red", "Shed_Small",
	"House_Chalet", "House_Adobe", "Diner", "Church", "Harbour_Shed"]
const FLOOR_BURY := 0.3          # terrain allowed above a floor origin (the kit plinths top out at 0.35-0.45 m)
const PIER_FREEBOARD := 0.9      # harbour pier deck / boathouse floor above the sea
const JETTY_FREEBOARD := 0.6     # lake jetty deck / boathouse floor above the lake
const LANDMARKS := ["Lighthouse", "Wind_Turbine_Tower", "Wind_Turbine_Rotor", "Castle_Ruin_Wall", "Castle_Ruin_Tower", "Church",
	"Silo", "Water_Tower", "Festival_Stage", "Checkpoint_Arch", "Barn_Red"]
const BUILDINGS := ["House_Cottage_A", "House_Cottage_B", "House_Townhouse", "Farmhouse", "Shed_Small", "House_Chalet",
	"House_Adobe", "Gas_Station", "Diner", "Harbour_Shed", "Boathouse", "Pier_Section", "Festival_Tent", "Viewpoint_Deck"]
const MEDIUM := ["Flag_Pole", "Festival_Banner", "Billboard", "Bus_Stop", "Boat_Fishing", "Lamp_Street", "Fuel_Pump", "Hay_Bale"]

const FESTIVAL_COLORS := [Color(1.0, 0.55, 0.1), Color(0.92, 0.2, 0.55), Color(0.1, 0.72, 0.82), Color(1.0, 0.82, 0.15),
	Color(0.55, 0.3, 0.85), Color(0.55, 0.85, 0.25)]
const PASTELS := [Color(0.98, 0.93, 0.82), Color(0.97, 0.82, 0.74), Color(0.8, 0.88, 0.95), Color(0.97, 0.9, 0.62),
	Color(0.82, 0.92, 0.8), Color(1.0, 0.98, 0.95), Color(0.95, 0.76, 0.72)]
const ADOBE := [Color(1.0, 1.0, 1.0), Color(1.0, 0.92, 0.86), Color(0.94, 0.86, 0.8), Color(1.0, 0.96, 0.84)]
const SHEDS := [Color(0.45, 0.72, 0.76), Color(0.88, 0.4, 0.34), Color(0.45, 0.58, 0.82), Color(0.95, 0.95, 0.95), Color(0.95, 0.8, 0.4)]
const HULLS := [Color(0.3, 0.5, 0.88), Color(0.88, 0.3, 0.26), Color(0.35, 0.72, 0.5), Color(0.98, 0.82, 0.3), Color(1, 1, 1)]

var world: World
var data: WorldData
var net: RoadNetwork
var items: Array[Dictionary] = []
var log_lines: PackedStringArray = []
var _occupied: Array[Vector3] = []
var _rng := RandomNumberGenerator.new()
var _count_before: int = 0
var fails: Dictionary = {}


func plan(w: World) -> Array[Dictionary]:
	world = w
	data = w.data
	net = data.network
	for p: Dictionary in data.pois():
		_rng.seed = hash(String(p["name"])) & 0x7fffffff
		_count_before = items.size()
		var t0 := Time.get_ticks_usec()
		var pc := Vector3(float(p["pos"][0]), float(p.get("y", 0.0)), float(p["pos"][1]))
		var nm: String = p["name"]
		match String(p["kind"]):
			"hub":
				_festival(pc)
			"village":
				_village(pc)
			"farm":
				_farm(pc)
			"hamlet":
				if int(p.get("region", 0)) == 2:
					_hamlet(pc, "House_Adobe", 6, ADOBE)
				else:
					_hamlet(pc, "House_Chalet" if int(p.get("region", 0)) == 1 else "House_Cottage_A", 5, PASTELS)
			"gas":
				_gas(pc)
			"diner":
				_diner(pc)
			"harbour":
				_harbour(pc)
			"lighthouse":
				_lighthouse(pc)
			"castle":
				_castle(pc)
			"viewpoint":
				_viewpoint(pc)
			"landmark":
				if nm.to_lower().contains("wind"):
					_wind_farm(pc)
				elif nm.to_lower().contains("lake"):
					_jetty(pc)
		log_lines.append("%s: %d items (%.0f ms)" % [nm, items.size() - _count_before, (Time.get_ticks_usec() - t0) / 1000.0])
		# Keep the settlement cores free of trees even where nothing was placed.
		var core := {"hub": 150.0, "village": 70.0, "farm": 60.0, "hamlet": 55.0, "gas": 45.0, "diner": 40.0, "harbour": 80.0,
			"lighthouse": 45.0, "castle": 45.0, "viewpoint": 25.0}
		var cr: float = core.get(String(p["kind"]), 0.0)
		if cr > 0.0:
			Rules.register_exclusion(pc.x, pc.z, cr * 0.25, cr)
	_street_lamps()
	return items


# ------------------------------------------------------------------ helpers

static func _yaw_to(from: Vector3, to: Vector3) -> float:
	return atan2(-(to.x - from.x), -(to.z - from.z))


static func _yaw_along(dir: Vector3) -> float:
	return atan2(-dir.z, dir.x)


static func _vis(name: String) -> float:
	if name in LANDMARKS:
		return VIS_LANDMARK
	if name in BUILDINGS:
		return VIS_BUILDING
	if name in MEDIUM:
		return VIS_MEDIUM
	return VIS_SMALL


func _road_or_nearest(id: String, p: Vector3) -> RoadNetwork.Road:
	var r := net.get_road(id)
	if r != null:
		return r
	var res := net.nearest(p, 600.0)
	return res["road"] if not res.is_empty() else null


func _nearest_paved(p: Vector3, max_d := 500.0) -> Dictionary:
	return net.nearest(p, max_d, func(r: RoadNetwork.Road) -> bool: return r.traffic)


func _s_on(road: RoadNetwork.Road, p: Vector3) -> float:
	var best := INF
	var bi := 0
	for i in road.pos.size():
		var q := road.pos[i]
		var d := (q.x - p.x) * (q.x - p.x) + (q.z - p.z) * (q.z - p.z)
		if d < best:
			best = d
			bi = i
	return bi * road.ds


## n x n grid over the footprint (n = 3: corners, edge midpoints, centre; index 4 = centre).
func _footprint(xf: Transform3D, bb: AABB, n := 3) -> Array[Vector3]:
	var pts: Array[Vector3] = []
	for i in n:
		for j in n:
			pts.append(xf * Vector3(bb.position.x + bb.size.x * i / (n - 1.0), 0.0, bb.position.z + bb.size.z * j / (n - 1.0)))
	return pts


## Terrain [min, max] over a dense footprint grid.
func _height_range(xf: Transform3D, bb: AABB, n := 5) -> Vector2:
	var lo := INF
	var hi := -INF
	for q in _footprint(xf, bb, n):
		var h := data.height_at(q.x, q.z)
		lo = minf(lo, h)
		hi = maxf(hi, h)
	return Vector2(lo, hi)


func _clear_of_roads(pts: Array[Vector3], clearance: float) -> bool:
	for q in pts:
		var res := net.nearest(q, 45.0)
		if res.is_empty():
			continue
		var r: RoadNetwork.Road = res["road"]
		if float(res["distance"]) < r.width * 0.5 + clearance:
			return false
	return true


func _wet(x: float, z: float) -> bool:
	return world.water_level_at(x, z) > -INF


## Places a prop. opts: scale, y (explicit base height), ground ("min"/"max"/"avg"/"floor"), clearance (from road
## edge, default 3), roads (check, default true), overlap (default true), occupy (default true), max_drop (4.5),
## water (allowed, default false), tint, col, vis, anim, pad (extra tree-free radius), excl (register, default true).
## "floor" (default for FLOOR_PROPS): the origin goes to at most FLOOR_BURY below the highest terrain under the
## footprint, and the site is rejected when the low side would drop below the model's plinth.
func place(name: String, pos: Vector3, yaw: float, opts := {}) -> Dictionary:
	var bb := PropLibrary.aabb(name)
	var sc: float = opts.get("scale", 1.0)
	var basis := Basis(Vector3.UP, yaw).scaled(Vector3(sc, sc, sc))
	var xf := Transform3D(basis, Vector3(pos.x, 0.0, pos.z))
	var pts := _footprint(xf, bb)
	var ground := String(opts.get("ground", "floor" if name in FLOOR_PROPS else "min"))
	var hmin := INF
	var hmax := -INF
	var hsum := 0.0
	for q in (_footprint(xf, bb, 5) if ground == "floor" else pts):
		var h := data.height_at(q.x, q.z)
		hmin = minf(hmin, h)
		hmax = maxf(hmax, h)
		hsum += h
	var allow_water: bool = opts.get("water", false)
	if not allow_water:
		if hmin < 0.8:
			return _fail(name, "water")
		for qi: int in [0, 2, 4, 6, 8]:
			if _wet(pts[qi].x, pts[qi].z):
				return _fail(name, "water")
	if hmax - hmin > float(opts.get("max_drop", 4.5)):
		return _fail(name, "slope")
	var floor_y := maxf(hmin - 0.12, hmax - FLOOR_BURY)
	if ground == "floor" and not opts.has("y") and floor_y - hmin > -bb.position.y * sc - 0.1:
		return _fail(name, "slope")
	if opts.get("roads", true) and not _clear_of_roads(pts, float(opts.get("clearance", 3.0))):
		return _fail(name, "road")
	var rad := 0.5 * Vector2(bb.size.x, bb.size.z).length() * sc
	if opts.get("overlap", true):
		for o in _occupied:
			if Vector2(o.x - pos.x, o.y - pos.z).length() < (o.z + rad) * 0.82:
				return _fail(name, "overlap")
	var y: float
	if opts.has("y"):
		y = opts["y"]
	else:
		match ground:
			"max":
				y = hmax - 0.05
			"avg":
				y = hsum / pts.size()
			"floor":
				y = floor_y
			_:
				y = hmin - 0.12
	xf.origin.y = y
	var tint: Color = opts.get("tint", Color(0, 0, 0))
	var lt := tint.srgb_to_linear() if tint != Color(0, 0, 0) else Color(0, 0, 0)
	var item := {"name": name, "xf": xf, "tint": Color(lt.r, lt.g, lt.b, _rng.randf()), "vis": float(opts.get("vis", _vis(name))),
		"col": int(opts.get("col", COLLIDE.get(name, Col.NONE))), "anim": String(opts.get("anim", ""))}
	items.append(item)
	if opts.get("occupy", true):
		_occupied.append(Vector3(pos.x, pos.z, rad))
	if opts.get("excl", true):
		var core := rad * 0.9
		Rules.register_exclusion(pos.x, pos.z, core, core + float(opts.get("pad", 4.0)))
	return item


func _fail(name: String, why: String) -> Dictionary:
	var k := name + ":" + why
	fails[k] = int(fails.get(k, 0)) + 1
	return {}


## Building facing a road at arclength s on `side` (+1 right of travel), `setback` metres behind the shoulder.
func along(road: RoadNetwork.Road, s: float, side: float, setback: float, name: String, opts := {}) -> Dictionary:
	if not road.loop and (s < 0.0 or s > road.length):
		return {}
	var bb := PropLibrary.aabb(name)
	var sc: float = opts.get("scale", 1.0)
	var p := road.point_at(s)
	var rt := road.right_at(s)
	var off := road.width * 0.5 + road.shoulder + setback - bb.position.z * sc
	var pos := p + rt * side * off
	return place(name, pos, _yaw_to(pos, p), opts)


func _try_along(road: RoadNetwork.Road, s: float, sides: Array, setback: float, name: String, opts := {}, s_steps := [0.0, 5.0, -5.0, 10.0, -10.0]) -> Dictionary:
	for ds: float in s_steps:
		for side: float in sides:
			var it := along(road, s + ds, side, setback, name, opts)
			if not it.is_empty():
				return it
	return {}


## Small prop next to a road edge (benches, bins, lamps, fences); skips the 3 m building clearance.
func roadside(road: RoadNetwork.Road, s: float, side: float, extra: float, name: String, yaw_mode := "face", opts := {}) -> Dictionary:
	var p := road.point_at(s)
	var rt := road.right_at(s)
	var pos := p + rt * side * (road.width * 0.5 + road.shoulder + extra)
	var yaw := _yaw_to(pos, p)
	if yaw_mode == "along":
		yaw = _yaw_along(road.flat_tangent_at(s))
	elif yaw_mode == "away":
		yaw = _yaw_to(pos, pos + rt * side)
	var o := {"clearance": 0.6, "overlap": false, "occupy": false, "max_drop": 2.0}
	o.merge(opts, true)
	return place(name, pos, yaw, o)


func _fence_run(a: Vector3, b: Vector3, opts := {}) -> void:
	var d := b - a
	d.y = 0.0
	var l := d.length()
	if l < 1.0:
		return
	var dir := d / l
	var segs := maxi(int(round(l / 4.0)), 1)
	var o := {"clearance": 1.0, "overlap": false, "occupy": false, "excl": false, "max_drop": 1.6}
	o.merge(opts, true)
	for k in segs:
		var c := a + dir * (l * (k + 0.5) / segs)
		place("Fence_Wood", c, _yaw_along(dir), o)


func _tint(pal: Array) -> Color:
	return pal[_rng.randi() % pal.size()]


func _spiral_place(name: String, center: Vector3, yaw_fn: Callable, opts: Dictionary, max_r := 80.0, step := 6.0) -> Dictionary:
	var r := 0.0
	while r <= max_r:
		var n := maxi(1, int(TAU * r / step))
		var a0 := _rng.randf() * TAU
		for k in n:
			var a := a0 + TAU * k / n
			var p := center + Vector3(cos(a) * r, 0.0, sin(a) * r)
			var it := place(name, p, yaw_fn.call(p), opts)
			if not it.is_empty():
				return it
		r += step
	return {}


# ------------------------------------------------------------------ settlements

func _festival(pc: Vector3) -> void:
	var sp: Dictionary = world.spawn_point()
	var view: Vector3 = sp["position"]
	var hub := Vector3(pc.x, 0.0, pc.z)
	var to_hub := Vector3(hub.x - view.x, 0, hub.z - view.z)
	to_hub = to_hub.normalized() if to_hub.length() > 1.0 else Vector3(0, 0, 1)
	# main stage on the far side of the showground, facing the start line
	var stage := _spiral_place("Festival_Stage", hub + to_hub * 26.0, func(p: Vector3) -> float: return _yaw_to(p, view), {"max_drop": 3.5, "clearance": 6.0, "pad": 8.0}, 60.0)
	var stage_pos: Vector3 = (stage["xf"] as Transform3D).origin if not stage.is_empty() else hub + to_hub * 26.0
	var axis := Vector3(view.x - stage_pos.x, 0, view.z - stage_pos.z).normalized()
	var crowd := stage_pos + axis * 26.0
	var base_a := atan2(axis.z, axis.x)
	# food & merch tents on two arcs either side of the crowd area
	var placed := 0
	for k in 16:
		if placed >= 10:
			break
		var side := 1.0 if k % 2 == 0 else -1.0
		var a := base_a + side * deg_to_rad(50.0 + floorf(k * 0.5) * 25.0)
		var p := crowd + Vector3(cos(a), 0, sin(a)) * _rng.randf_range(24.0, 28.0)
		if not place("Festival_Tent", p, _yaw_to(p, crowd), {"tint": FESTIVAL_COLORS[placed % FESTIVAL_COLORS.size()], "max_drop": 2.5, "clearance": 4.0}).is_empty():
			placed += 1
	# flag ring around the showground, joined by festoon light strings
	var fb := PropLibrary.aabb("Flag_Pole")
	var hook := fb.end.y * 0.7
	var ring_pts := PackedVector3Array()
	for k in 20:
		var a := TAU * k / 20.0
		var p := crowd + Vector3(cos(a), 0, sin(a)) * 42.0
		var it := place("Flag_Pole", p, _yaw_along(Vector3(-sin(a), 0, cos(a))), {"tint": FESTIVAL_COLORS[k % FESTIVAL_COLORS.size()], "overlap": false, "occupy": false, "max_drop": 3.0, "clearance": 2.5, "pad": 0.0})
		if it.is_empty():
			if ring_pts.size() >= 2:
				_festoon(ring_pts)
			ring_pts = PackedVector3Array()
		else:
			ring_pts.append((it["xf"] as Transform3D).origin + Vector3.UP * hook)
	if ring_pts.size() >= 2:
		_festoon(ring_pts)
	if not stage.is_empty() and PropLibrary.is_placeholder("Festival_Stage"):
		stage["label"] = "SUNWARD FESTIVAL"
		stage["label_at"] = Vector3(0, 10.95, -6.0)
		stage["label_size"] = 0.018
	# hay-bale seating and bins in the crowd area
	for k in 7:
		var a := base_a + (k - 3.0) * 0.2
		var p := stage_pos + Vector3(cos(a), 0, sin(a)) * _rng.randf_range(17.0, 21.0)
		place("Hay_Bale", p, _rng.randf() * TAU, {"max_drop": 2.0, "pad": 0.5})
	for k in 4:
		var a := base_a + PI * 0.5 + k * PI * 0.33
		place("Bin", crowd + Vector3(cos(a), 0, sin(a)) * 15.0, _rng.randf() * TAU, {"overlap": false, "max_drop": 2.0, "pad": 0.0})
	# flag-lined start boulevard on the ring road around the spawn, banners on the festival side
	var ring := net.get_road("ring")
	if ring == null:
		return
	var s_spawn := _s_on(ring, view)
	var fest_side := signf((hub - ring.point_at(s_spawn)).dot(ring.right_at(s_spawn)))
	fest_side = 1.0 if fest_side == 0.0 else fest_side
	var k2 := 0
	var s := s_spawn - 70.0
	while s < s_spawn + 170.0:
		for sd: float in [-1.0, 1.0]:
			roadside(ring, s + (0.0 if sd > 0.0 else 8.0), sd, 2.6, "Flag_Pole", "along", {"tint": FESTIVAL_COLORS[k2 % FESTIVAL_COLORS.size()], "max_drop": 3.0, "pad": 0.0})
			k2 += 1
		s += 16.0
	for k in 5:
		roadside(ring, s_spawn - 40.0 + k * 45.0, fest_side, 5.0, "Festival_Banner", "face", {"tint": FESTIVAL_COLORS[(k + 2) % FESTIVAL_COLORS.size()], "max_drop": 3.0})
	roadside(ring, s_spawn + 200.0, -fest_side, 7.0, "Billboard", "face", {"max_drop": 3.5, "occupy": true, "overlap": true})
	roadside(ring, s_spawn - 110.0, fest_side, 7.0, "Billboard", "face", {"max_drop": 3.5, "occupy": true, "overlap": true})
	# inflatable start arch over the ring just ahead of the spawn point
	var bb := PropLibrary.aabb("Checkpoint_Arch")
	var need := ring.width + ring.shoulder * 2.0 + 3.0
	var sc := maxf(1.0, need / maxf(bb.size.x - 2.0, 1.0))
	for ds: float in [32.0, 45.0, 22.0, 60.0, 75.0, 90.0]:
		var sa := s_spawn + ds
		var p := ring.point_at(sa)
		var rt := ring.right_at(sa)
		var ok := ring.flag_at(sa) == 0
		for sd: float in [-1.0, 1.0]:
			var leg := p + rt * sd * bb.size.x * 0.45 * sc
			if absf(data.height_at(leg.x, leg.z) - p.y) > 0.9:
				ok = false
		if not ok:
			continue
		var arch := place("Checkpoint_Arch", p, _yaw_along(rt), {"scale": sc, "roads": false, "overlap": false, "occupy": false, "water": true,
			"max_drop": 100.0, "y": p.y - 0.15, "excl": false, "col": Col.NONE})
		if not arch.is_empty() and PropLibrary.is_placeholder("Checkpoint_Arch"):
			arch["label"] = "SUNWARD FESTIVAL"
			arch["label_at"] = Vector3(0, bb.end.y - 0.85, 0.23)
			arch["label_size"] = 0.0095
			arch["label_both"] = true
		break


## String of coloured bulbs sagging between consecutive points (rendered by settlements.gd).
func _festoon(points: PackedVector3Array) -> void:
	items.append({"name": "", "xf": Transform3D(), "tint": Color(0, 0, 0, 0), "vis": VIS_MEDIUM, "col": Col.NONE, "anim": "festoon", "points": points})


func _village(pc: Vector3) -> void:
	var road := _road_or_nearest("millbrook_st", pc)
	if road == null:
		return
	var s_poi := _s_on(road, pc)
	var e := road.width * 0.5 + road.shoulder
	var church := _try_along(road, s_poi, [1.0, -1.0], 7.0, "Church", {"pad": 6.0}, [0.0, 20.0, -20.0, 40.0, -40.0, 60.0, -60.0])
	var church_side := 0.0
	if not church.is_empty():
		var cpos: Vector3 = (church["xf"] as Transform3D).origin
		church_side = signf((cpos - road.point_at(s_poi)).dot(road.right_at(s_poi)))
		var cs := _s_on(road, cpos)
		for k in 2:
			roadside(road, cs + (k * 2 - 1) * 4.0, church_side, 1.6, "Bench")
		_fence_run(road.point_at(cs - 12.0) + road.right_at(cs - 12.0) * church_side * (e + 1.3), road.point_at(cs - 3.0) + road.right_at(cs - 3.0) * church_side * (e + 1.3))
	var houses := 0
	var s := 26.0
	while s < road.length - 26.0 and houses < 14:
		for side: float in [-1.0, 1.0]:
			if houses >= 14:
				break
			var central := road.point_at(s).distance_to(Vector3(pc.x, road.point_at(s).y, pc.z)) < 120.0
			var nm := "House_Townhouse" if central and _rng.randf() < 0.55 else ("House_Cottage_A" if _rng.randf() < 0.55 else "House_Cottage_B")
			var it := along(road, s + _rng.randf_range(-3.0, 3.0), side, _rng.randf_range(3.0, 5.5), nm, {"tint": _tint(PASTELS), "pad": 3.0})
			if it.is_empty():
				continue
			houses += 1
			var hpos: Vector3 = (it["xf"] as Transform3D).origin
			var hs := _s_on(road, hpos)
			var half_w := PropLibrary.aabb(nm).size.x * 0.5 + 0.5
			var t := road.flat_tangent_at(hs)
			var fl := road.point_at(hs) + road.right_at(hs) * side * (e + 1.3)
			_fence_run(fl - t * half_w, fl - t * 0.9)
			_fence_run(fl + t * 0.9, fl + t * half_w)
			roadside(road, hs + 1.4, side, 1.7, "Mailbox")
			if _rng.randf() < 0.45:
				var back := hpos + (hpos - road.point_at(hs)).normalized() * (PropLibrary.aabb(nm).size.z * 0.5 + 5.0) + t * _rng.randf_range(-3.0, 3.0)
				place("Shed_Small", back, _yaw_to(back, hpos), {"pad": 1.0})
		s += _rng.randf_range(22.0, 30.0)
	var stop_side := -church_side if church_side != 0.0 else 1.0
	for ds: float in [40.0, -40.0, 60.0, -60.0]:
		var it := roadside(road, s_poi + ds, stop_side, 1.0 + PropLibrary.aabb("Bus_Stop").size.z * 0.5, "Bus_Stop", "face", {"overlap": true, "occupy": true, "max_drop": 1.5})
		if not it.is_empty():
			roadside(road, s_poi + ds + 3.5, stop_side, 1.2, "Bin")
			break
	log_lines.append("Millbrook houses: %d" % houses)


func _farm(pc: Vector3) -> void:
	var res := net.nearest(pc, 400.0)
	if res.is_empty():
		return
	var road: RoadNetwork.Road = res["road"]
	var s0: float = res["s"]
	var side := signf(float(res["lateral"]))
	side = 1.0 if side == 0.0 else side
	var e := road.width * 0.5 + road.shoulder
	for ds: float in [0.0, 20.0, -20.0, 40.0, -40.0]:
		var fh := along(road, s0 + ds, side, 7.0, "Farmhouse", {"tint": Color(1.0, 0.97, 0.9), "pad": 4.0})
		if fh.is_empty():
			continue
		var o := road.point_at(s0 + ds)
		var t := road.flat_tangent_at(s0 + ds)
		var rt := road.right_at(s0 + ds) * side
		var loc := func(a: float, l: float) -> Vector3: return o + t * a + rt * (e + l)
		var face := _yaw_to(loc.call(0.0, 30.0), o)
		for a: float in [34.0, 40.0, -36.0]:
			if not place("Barn_Red", loc.call(a, 26.0), face, {"pad": 4.0, "max_drop": 5.0}).is_empty():
				break
		place("Silo", loc.call(52.0, 14.0), 0.0, {"max_drop": 5.0})
		place("Silo", loc.call(52.0, 21.0), 0.6, {"max_drop": 5.0})
		place("Shed_Small", loc.call(-18.0, 12.0), face, {"pad": 1.0})
		place("Log_Pile", loc.call(-9.0, 6.0), _yaw_along(t), {"overlap": false})
		# hay stack + scattered bales
		var hb := PropLibrary.aabb("Hay_Bale")
		var stack: Vector3 = loc.call(20.0, 44.0)
		var sy := data.height_at(stack.x, stack.z) - 0.1
		for k in 3:
			place("Hay_Bale", stack + t * (k - 1) * hb.size.x * 1.02, _yaw_along(t), {"y": sy, "overlap": false, "occupy": k == 1, "max_drop": 3.0})
		for k in 2:
			place("Hay_Bale", stack + t * (k - 0.5) * hb.size.x * 1.02, _yaw_along(t), {"y": sy + hb.size.y * 0.92, "overlap": false, "occupy": false, "max_drop": 3.0})
		for k in 9:
			place("Hay_Bale", loc.call(_rng.randf_range(-80.0, -30.0), _rng.randf_range(35.0, 85.0)), _rng.randf() * TAU, {"max_drop": 2.0, "pad": 0.5})
		# paddock
		var c0: Vector3 = loc.call(-62.0, 24.0)
		var c1: Vector3 = loc.call(-24.0, 24.0)
		var c2: Vector3 = loc.call(-24.0, 54.0)
		var c3: Vector3 = loc.call(-62.0, 54.0)
		_fence_run(c0, c1)
		_fence_run(c1, c2)
		_fence_run(c2, c3)
		_fence_run(c3, c0)
		roadside(road, s0 + ds + 9.0, side, 1.6, "Mailbox")
		return


func _hamlet(pc: Vector3, house: String, target: int, palette: Array) -> void:
	var res := _nearest_paved(pc, 450.0)
	if res.is_empty():
		res = net.nearest(pc, 450.0)
	if res.is_empty():
		return
	var road: RoadNetwork.Road = res["road"]
	var s0: float = res["s"]
	var placed: Array[Vector3] = []
	for k in [0, 1, -1, 2, -2, 3, -3, 4, -4, 5, -5]:
		if placed.size() >= target:
			break
		for side: float in [1.0, -1.0]:
			if placed.size() >= target:
				break
			var it := along(road, s0 + float(k) * 27.0 + _rng.randf_range(-3.0, 3.0), side, _rng.randf_range(3.0, 8.0), house, {"tint": _tint(palette), "pad": 3.0, "max_drop": 5.0})
			if not it.is_empty():
				placed.append((it["xf"] as Transform3D).origin)
	var desert := house == "House_Adobe"
	for hp in placed:
		var rp: Vector3 = net.nearest(hp, 80.0).get("position", hp)
		var out := Vector3(hp.x - rp.x, 0, hp.z - rp.z).normalized()
		var side_dir := out.cross(Vector3.UP)
		var bb := PropLibrary.aabb(house)
		var p := hp + side_dir * (bb.size.x * 0.5 + 2.5) + out * _rng.randf_range(-1.0, 2.0)
		if desert:
			place("Cactus_A" if _rng.randf() < 0.5 else "Cactus_B", p, _rng.randf() * TAU, {"overlap": false, "pad": 0.0})
		else:
			place("Log_Pile", p, _yaw_along(out), {"overlap": false, "pad": 0.5})
		var back := hp + out * (bb.size.z * 0.5 + 6.0)
		_fence_run(back - side_dir * 6.0, back + side_dir * 6.0)
	if desert and not placed.is_empty():
		var c := Vector3.ZERO
		for hp in placed:
			c += hp
		c /= placed.size()
		var rp2: Vector3 = net.nearest(c, 200.0).get("position", c)
		var out2 := Vector3(c.x - rp2.x, 0, c.z - rp2.z).normalized()
		_spiral_place("Water_Tower", c + out2 * 34.0, func(_p: Vector3) -> float: return 0.3, {"tint": Color(0.86, 0.93, 1.0), "max_drop": 4.0, "pad": 4.0}, 40.0)
		for k in 6:
			var a := _rng.randf() * TAU
			place("Cactus_A" if k % 2 == 0 else "Cactus_B", c + Vector3(cos(a), 0, sin(a)) * _rng.randf_range(30.0, 60.0), _rng.randf() * TAU, {"overlap": false, "pad": 0.0})
	elif not placed.is_empty():
		place("Shed_Small", placed[0] + Vector3(9, 0, 9), _rng.randf() * TAU, {"pad": 1.0})
	if not placed.is_empty():
		var bs := _s_on(road, placed[0])
		roadside(road, bs + 9.0, 1.0, 1.6, "Bench")


## Gas_Station kit geometry (local x / z): the forecourt slab (top at the origin, 3 m deep) and the shop behind it
## (walls from -2 m).
const GAS_SLAB := Rect2(-9.0, -10.6, 18.0, 14.0)
const GAS_SHOP := Rect2(-7.1, 3.4, 14.2, 8.1)


## Fuel station beside a paved road: the level forecourt never lies below the terrain under it and sits as close to
## the road height as it can; a concrete apron ramps between the road shoulder and the forecourt front, and a
## foundation skirt closes any gap under the slab where the ground falls away. Of the sites within 150 m of the POI
## the one with the gentlest apron and the smallest skirt wins.
func _gas(pc: Vector3) -> void:
	var res := _nearest_paved(pc, 450.0)
	if res.is_empty():
		return
	var road: RoadNetwork.Road = res["road"]
	var s0: float = res["s"]
	var side := signf(float(res["lateral"]))
	side = 1.0 if side == 0.0 else side
	var bb := PropLibrary.aabb("Gas_Station")
	var order: Array[float] = [0.0]
	for k in range(5, 151, 5):
		order.append_array([float(k), float(-k)])
	var oi := 0
	var st := {}
	var site := {}
	while st.is_empty() and oi < order.size():
		# gather sites nearest the POI first, until no farther one can beat the best score
		var sites: Array = []
		var best := INF
		while oi < order.size() and absf(order[oi]) * 0.004 + 0.08 <= best:
			for sd: float in [side, -side]:
				var edge_cache: Array = []
				for setback: float in [4.0, 7.0, 10.0]:
					var cand := _gas_site(road, s0 + order[oi], sd, setback, bb, edge_cache)
					if not cand.is_empty():
						var score := float(cand["grade"]) * 10.0 + float(cand["skirt"]) * 0.3 + absf(order[oi]) * 0.004 + setback * 0.02
						sites.append([score, cand])
						best = minf(best, score)
			oi += 1
		sites.sort_custom(func(x: Array, y: Array) -> bool: return x[0] < y[0])
		for entry: Array in sites:
			site = entry[1]
			var sxf: Transform3D = site["xf"]
			st = place("Gas_Station", sxf.origin, sxf.basis.get_euler().y, {"y": site["y"], "max_drop": 100.0, "pad": 8.0})
			if not st.is_empty():
				break
	if st.is_empty():
		log_lines.append("fuel station near %s: no site" % str(pc.round()))
		return
	var xf: Transform3D = st["xf"]
	var sd: float = site["sd"]
	var s1: float = site["s"]
	var apron: PackedVector3Array = site["apron"]
	items.append({"name": "", "xf": Transform3D(), "tint": Color(0, 0, 0, 0), "vis": VIS_BUILDING, "col": Col.NONE,
		"anim": "apron", "points": apron})
	var ac := (apron[0] + apron[apron.size() - 1]) * 0.5
	var ar := apron[0].distance_to(apron[apron.size() - 1]) * 0.5
	Rules.register_exclusion(ac.x, ac.z, ar + 1.0, ar + 4.0)
	var skirt: float = site["skirt"]
	var y0: float = site["y"]
	for part: Array in [[GAS_SLAB, -2.9, site["tmin"]], [GAS_SHOP, -1.95, site["tmin_shop"]]]:
		var r: Rect2 = part[0]
		var bottom: float = float(part[2]) - 0.4 - y0
		if bottom < float(part[1]) - 0.3:
			_pad(xf, AABB(Vector3(r.position.x, bottom, r.position.y), Vector3(r.size.x, float(part[1]) - bottom, r.size.y)))
	var dy := 0.19 if PropLibrary.is_placeholder("Gas_Station") else 0.0
	for px: float in [-1.0, 1.0]:
		for pz: float in [-0.12, 0.12]:
			var lp := Vector3(px * bb.size.x * 0.18, dy, bb.position.z + bb.size.z * (0.25 + pz))
			var wp := xf * lp
			place("Fuel_Pump", wp, xf.basis.get_euler().y, {"y": wp.y, "roads": false, "overlap": false, "occupy": false, "excl": false, "max_drop": 10.0})
	for k in 2:
		var corner := xf * Vector3((k * 2 - 1) * (bb.size.x * 0.5 + 1.0), 0, bb.position.z)
		var lamp := place("Lamp_Street", corner, _yaw_to(corner, road.point_at(s1)), {"clearance": 0.8, "overlap": false, "occupy": false, "max_drop": 3.0})
		if not lamp.is_empty():
			lamp["light"] = true
	roadside(road, s1 + 42.0, sd, 5.0, "Billboard", "face", {"max_drop": 3.5})
	place("Bin", xf * Vector3(bb.size.x * 0.5 - 1.5, 0, bb.end.z - 1.0), xf.basis.get_euler().y, {"overlap": false, "max_drop": 3.0})
	place("Bench", xf * Vector3(-bb.size.x * 0.5 + 2.0, 0, bb.end.z - 0.5), xf.basis.get_euler().y, {"overlap": false, "max_drop": 3.0})
	log_lines.append("%s: fuel station at %s on %s, forecourt %+.2f m to the road edge, apron grade %.1f %%, skirt %.1f m" % [
		road.name, str(xf.origin.round()), road.id, float(site["y"]) - float(site["yr"]), float(site["grade"]) * 100.0, skirt])


## Height of the road's paved edge (shoulder included) on side `sd` next to world point q (q near the road).
func _edge_point(road: RoadNetwork.Road, s_hint: float, q: Vector3, sd: float, inset := 0.0) -> Vector3:
	var s := s_hint + (q - road.point_at(s_hint)).dot(road.flat_tangent_at(s_hint))
	if road.loop:
		s = fposmod(s, road.length)
	else:
		s = clampf(s, 0.0, road.length)
	return road.surface_point(s, sd * (road.width * 0.5 + road.shoulder - inset))


## Evaluates a fuel station site (forecourt front `setback` m behind the shoulder at arclength s, side sd). Returns {}
## when the apron would be steeper than 10 %, the terrain would rise through it or the skirt would exceed 3 m.
## edge_cache keeps the road-edge points, which do not depend on the setback.
func _gas_site(road: RoadNetwork.Road, s: float, sd: float, setback: float, bb: AABB, edge_cache: Array) -> Dictionary:
	if not road.loop and (s < 20.0 or s > road.length - 20.0):
		return {}
	for k in 5:
		if road.flag_at(s + (k - 2) * 8.0) != 0:
			return {}
	var p := road.point_at(s)
	var pos := p + road.right_at(s) * sd * (road.width * 0.5 + road.shoulder + setback - bb.position.z)
	var xf := Transform3D(Basis(Vector3.UP, _yaw_to(pos, p)), Vector3(pos.x, 0.0, pos.z))
	# road side of the apron: the shoulder edge (0.3 m onto the shoulder) next to each forecourt column
	if edge_cache.is_empty():
		var pts := PackedVector3Array()
		for i in 7:
			var x := GAS_SLAB.position.x + GAS_SLAB.size.x * i / 6.0
			pts.append(_edge_point(road, s, xf * Vector3(x, 0.0, bb.position.z - setback), sd, 0.3))
		edge_cache.append(pts)
	var front: PackedVector3Array = edge_cache[0]
	var yr_lo := INF
	var yr_hi := -INF
	for e in front:
		yr_lo = minf(yr_lo, e.y)
		yr_hi = maxf(yr_hi, e.y)
	var span := setback + GAS_SLAB.position.y - bb.position.z + 0.3
	if (yr_hi - yr_lo) * 0.5 > 0.1 * span:
		return {}
	# terrain that would need an apron over 10 % or a skirt over 3 m rejects the site at once
	var t_cap := yr_lo + 0.1 * span - 0.06
	var mid := (yr_lo + yr_hi) * 0.5
	var tmax := -INF
	var tmin := INF
	var tmin_shop := INF
	for r: Rect2 in [GAS_SLAB, GAS_SHOP]:
		var t_floor := mid - (5.9 if r == GAS_SLAB else 4.9)
		for i in 7:
			for j in 7:
				var q := xf * Vector3(r.position.x + r.size.x * i / 6.0, 0.0, r.position.y + r.size.y * j / 6.0)
				var h := data.height_at(q.x, q.z)
				if h > t_cap or h < t_floor:
					return {}
				tmax = maxf(tmax, h)
				if r == GAS_SLAB:
					tmin = minf(tmin, h)
				else:
					tmin_shop = minf(tmin_shop, h)
	var y := maxf(tmax + 0.06, mid)
	var grade := maxf(y - yr_lo, yr_hi - y) / span
	var skirt := maxf(y - 2.9 - tmin, y - 1.9 - tmin_shop)
	if grade > 0.1 or skirt > 3.0:
		return {}
	var apron := PackedVector3Array()
	for i in 7:
		var x := GAS_SLAB.position.x + GAS_SLAB.size.x * i / 6.0
		var a := front[i] + Vector3.UP * 0.015
		var b := xf * Vector3(x, 0.0, GAS_SLAB.position.y)
		b.y = y + 0.005
		for t: float in [0.25, 0.5, 0.75]:
			var m := a.lerp(b, t)
			if data.height_at(m.x, m.z) > m.y + 0.03:
				return {}
		apron.append_array([a, b])
	xf.origin.y = y
	return {"xf": xf, "y": y, "yr": (yr_lo + yr_hi) * 0.5, "grade": grade, "skirt": maxf(skirt, 0.0), "tmin": tmin, "tmin_shop": tmin_shop,
		"s": s, "sd": sd, "apron": apron}


## Foundation block (local box in xf space) under a building whose own plinth stops short of the ground.
func _pad(xf: Transform3D, box: AABB) -> void:
	items.append({"name": "", "xf": xf, "tint": Color(0, 0, 0, 0), "vis": VIS_BUILDING, "col": Col.NONE, "anim": "pad", "box": box})


func _diner(pc: Vector3) -> void:
	var res := _nearest_paved(pc, 450.0)
	if res.is_empty():
		return
	var road: RoadNetwork.Road = res["road"]
	var s0: float = res["s"]
	var side := signf(float(res["lateral"]))
	side = 1.0 if side == 0.0 else side
	var it := _try_along(road, s0, [side, -side], 9.0, "Diner", {"max_drop": 2.5, "pad": 6.0}, [0.0, 15.0, -15.0, 30.0, -30.0, 50.0, -50.0])
	if it.is_empty():
		return
	var xf: Transform3D = it["xf"]
	var ds := _s_on(road, xf.origin)
	var sd := signf((xf.origin - road.point_at(ds)).dot(road.right_at(ds)))
	roadside(road, ds - 26.0, sd, 4.0, "Billboard", "face", {"max_drop": 3.5})
	for k in 2:
		var lamp := roadside(road, ds + (k * 2 - 1) * 11.0, sd, 1.5, "Lamp_Street", "face")
		if not lamp.is_empty():
			lamp["light"] = true
		place("Bench", xf * Vector3((k * 2 - 1) * 5.0, 0, PropLibrary.aabb("Diner").position.z - 1.5), xf.basis.get_euler().y + PI, {"overlap": false, "max_drop": 2.0})
	place("Bin", xf * Vector3(3.0, 0, PropLibrary.aabb("Diner").position.z - 2.0), 0.0, {"overlap": false, "max_drop": 2.0})


## Distance along `out` from p to the first point lower than 0.8 m (the shoreline), or -1.
func _shore_dist(p: Vector3, out: Vector3, max_d := 170.0) -> float:
	var d := 0.0
	while d < max_d:
		var q := p + out * d
		if data.height_at(q.x, q.z) < 0.8:
			return d
		d += 2.0
	return -1.0


func _harbour(pc: Vector3) -> void:
	var road := _road_or_nearest("harbour_st", pc)
	if road == null:
		return
	var s_poi := _s_on(road, pc)
	var p0 := road.point_at(s_poi)
	var rt0 := road.right_at(s_poi)
	var sea := 0.0
	var best := INF
	for sd: float in [1.0, -1.0]:
		var d := _shore_dist(p0, rt0 * sd)
		if d >= 0.0 and d < best:
			best = d
			sea = sd
	var pb := PropLibrary.aabb("Pier_Section")
	var seg := pb.size.z
	var deck := WorldLayout.SEA_LEVEL + PIER_FREEBOARD
	var piers := 0
	var boats := 0
	if sea != 0.0:
		for ds: float in [-35.0, 25.0, 85.0, -95.0]:
			if piers >= 3:
				break
			var sp := s_poi + ds
			if sp < 10.0 or sp > road.length - 10.0:
				continue
			var p := road.point_at(sp)
			var out := road.right_at(sp) * sea
			# the pier starts where the beach drops below its deck and runs out over the water
			var dland := _pier_start(p, out, deck, pb.size.x * 0.5)
			if dland < 0.0:
				continue
			var start := p + out * dland
			var yaw := _yaw_to(start, start + out)
			var last := Vector3.INF
			var n := 0
			for k in 4:
				var c := start + out * seg * (k + 0.5)
				if place("Pier_Section", c, yaw, {"y": deck, "water": true, "clearance": 1.0, "max_drop": 100.0, "pad": 1.0}).is_empty():
					break
				last = c
				n += 1
			if n < 2:
				continue
			piers += 1
			var side_dir := out.cross(Vector3.UP)
			for k in 2:
				var sdir := 1.0 if (k + piers) % 2 == 0 else -1.0
				var bp := last - out * seg * 0.6 * k + side_dir * sdir * (pb.size.x * 0.5 + 2.3)
				if data.height_at(bp.x, bp.z) < -1.2:
					var hull: Color = HULLS[(boats + piers) % HULLS.size()]
					if not place("Boat_Fishing", bp, yaw + (PI if _rng.randf() < 0.5 else 0.0) + _rng.randf_range(-0.06, 0.06),
							{"y": 0.0, "water": true, "roads": false, "overlap": false, "occupy": false, "max_drop": 100.0, "anim": "boat", "excl": false, "tint": hull}).is_empty():
						boats += 1
		# boathouse on piles at the waterline
		for ds: float in [55.0, -65.0, 120.0, -125.0]:
			var sp := s_poi + ds
			if sp < 10.0 or sp > road.length - 10.0:
				continue
			if not _on_piles("Boathouse", road.point_at(sp), road.right_at(sp) * sea, deck, {"clearance": 2.0, "pad": 2.0}).is_empty():
				break
		# benches and bins facing the water
		for k in 4:
			var sp := s_poi + (k - 1.5) * 18.0
			roadside(road, sp, sea, 1.4, "Bench" if k % 2 == 0 else "Bin", "away", {"water": true})
	# harbour shed and houses on the land side of the quay (the bank down to the water is far too steep)
	var land_sides: Array = [-sea] if sea != 0.0 else [1.0, -1.0]
	var sheds := 0 if _harbour_shed(road, s_poi, land_sides).is_empty() else 1
	var built := 0
	var s := 18.0
	while s < road.length - 18.0:
		for land: float in land_sides:
			var nm := "House_Townhouse" if _rng.randf() < 0.4 else "House_Cottage_A"
			var setback := _rng.randf_range(2.5, 4.5)
			var tint := _tint(PASTELS)
			for extra: float in [0.0, 5.0, 10.0]:
				if not along(road, s, land, setback + extra, nm, {"tint": tint, "pad": 2.0, "max_drop": 5.0}).is_empty():
					built += 1
					break
		s += _rng.randf_range(24.0, 30.0)
	log_lines.append("Gullhaven buildings %d, sheds %d, piers %d, boats %d" % [built, sheds, piers, boats])


## Harbour_Shed on the flattest land-side site near the quay centre (facing the road).
func _harbour_shed(road: RoadNetwork.Road, s_poi: float, sides: Array) -> Dictionary:
	var bb := PropLibrary.aabb("Harbour_Shed")
	var cands: Array = []
	for ds in range(-90, 91, 6):
		var s := s_poi + ds
		if s < 15.0 or s > road.length - 15.0:
			continue
		for side: float in sides:
			for setback: float in [3.0, 7.0, 11.0, 15.0, 19.0]:
				var p := road.point_at(s)
				var pos := p + road.right_at(s) * side * (road.width * 0.5 + road.shoulder + setback - bb.position.z)
				var hr := _height_range(Transform3D(Basis(Vector3.UP, _yaw_to(pos, p)), Vector3(pos.x, 0.0, pos.z)), bb)
				cands.append([hr.y - hr.x + absf(ds) * 0.01 + setback * 0.02, s, side, setback])
	cands.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	var tint := _tint(SHEDS)
	for k in mini(cands.size(), 40):
		var c: Array = cands[k]
		var it := along(road, c[1], c[2], c[3], "Harbour_Shed", {"tint": tint, "pad": 2.0})
		if not it.is_empty():
			# keep its yard towards the road open (no cottage in front of the doors)
			var setback: float = c[3]
			var yard: Vector3 = road.point_at(c[1]) + road.right_at(c[1]) * float(c[2]) * (road.width * 0.5 + road.shoulder + setback * 0.5)
			_occupied.append(Vector3(yard.x, yard.z, setback * 0.5 + 3.0))
			return it
	return {}


## Distance along `out` from p to the first point whose terrain is below h (0.5 m steps), or -1.
func _below_dist(p: Vector3, out: Vector3, h: float, max_d := 170.0) -> float:
	var d := 0.0
	while d < max_d:
		var q := p + out * d
		if data.height_at(q.x, q.z) < h:
			return d
		d += 0.5
	return -1.0


## Distance along `out` from p to where a pier deck (half width hw) at height `deck` can start: the ground under
## its centre line and both edges has dropped below the deck there. -1 when there is no such point.
func _pier_start(p: Vector3, out: Vector3, deck: float, hw: float) -> float:
	var d := _below_dist(p, out, deck)
	if d < 0.0:
		return -1.0
	var side := out.cross(Vector3.UP)
	var limit := d + 8.0
	while d < limit:
		var q := p + out * d
		var ok := true
		for f: float in [-1.0, 0.0, 1.0]:
			var e := q + side * hw * f
			ok = ok and data.height_at(e.x, e.z) < deck - 0.03
		if ok:
			return d
		d += 0.25
	return d


## A building on piles (origin = floor level) facing back along -out: its landward edge stands where the ground
## drops below the floor, so nothing of it is buried and its far end stands over the water.
func _on_piles(name: String, from: Vector3, out: Vector3, floor_y: float, opts: Dictionary) -> Dictionary:
	var d := _below_dist(from, out, floor_y - 0.05)
	if d < 0.0:
		return {}
	var bb := PropLibrary.aabb(name)
	var o := {"y": floor_y, "water": true, "max_drop": 100.0}
	o.merge(opts, true)
	for extra: float in [0.0, 1.0, 2.0, 3.0, 4.5]:
		var c := from + out * (d + extra - bb.position.z)
		var yaw := _yaw_to(c, c - out)
		if _height_range(Transform3D(Basis(Vector3.UP, yaw), Vector3(c.x, 0.0, c.z)), bb).y > floor_y + 0.05:
			continue
		var it := place(name, c, yaw, o)
		if not it.is_empty():
			return it
	return {}


func _lighthouse(pc: Vector3) -> void:
	var best := {}
	var best_h := -INF
	var center := pc
	var spread := 60.0
	var lr := net.get_road("lighthouse")
	var tip := pc
	if lr != null and lr.pos.size() > 2:
		# Seaward past the end of Lighthouse Point Road: the closest fairly level site to the headland tip.
		center = lr.pos[lr.pos.size() - 1]
		tip = center + lr.flat_tangent_at(lr.length) * 30.0
		spread = 70.0
	var bb := PropLibrary.aabb("Lighthouse")
	for max_step: float in [3.5, 5.0]:
		for r: float in [0.0, 6.0, 12.0, 18.0, 24.0, 30.0, 38.0, 46.0, 55.0, 64.0, 70.0]:
			if r > spread:
				break
			var n := maxi(1, int(r / 4.0))
			for k in n:
				var a := TAU * k / n
				var p := center + Vector3(cos(a), 0, sin(a)) * r
				var h := data.height_at(p.x, p.z)
				var score := -p.distance_to(tip) if lr != null else h - r * 0.05
				if score > best_h and h > 4.0:
					var xf := Transform3D(Basis(), Vector3(p.x, 0, p.z))
					var pts := _footprint(xf, bb)
					var lo := INF
					var hi := -INF
					for q in pts:
						lo = minf(lo, data.height_at(q.x, q.z))
						hi = maxf(hi, data.height_at(q.x, q.z))
					if hi - lo < max_step and lo > 1.0 and _clear_of_roads(pts, 3.0):
						best_h = score
						best = {"p": p, "step": max_step}
		if not best.is_empty():
			break
	if best.is_empty():
		log_lines.append("Lighthouse: no site found near %s" % str(center.round()))
		return
	var lp: Vector3 = best["p"]
	var rp: Vector3 = net.nearest(lp, 300.0).get("position", lp + Vector3(0, 0, -30))
	var it := place("Lighthouse", lp, _yaw_to(lp, rp), {"max_drop": float(best["step"]), "pad": 6.0, "anim": "beacon"})
	if it.is_empty():
		log_lines.append("Lighthouse: placement at %s rejected %s" % [str(lp.round()), str(fails)])
		return
	var to_road := Vector3(rp.x - lp.x, 0, rp.z - lp.z).normalized()
	var side := to_road.cross(Vector3.UP)
	place("Shed_Small", lp + to_road * 9.0 + side * 6.0, _yaw_to(lp + to_road * 9.0, rp), {"max_drop": 3.0})
	place("Bench", lp - to_road * 7.0 + side * 3.0, _yaw_to(lp, lp - to_road), {"overlap": false, "max_drop": 2.0})
	_fence_run(lp - to_road * 11.0 - side * 8.0, lp - to_road * 11.0 + side * 8.0, {"water": false})


func _castle(pc: Vector3) -> void:
	var res := net.nearest(pc, 400.0)
	var center := pc
	if not res.is_empty():
		var rp: Vector3 = res["position"]
		var road: RoadNetwork.Road = res["road"]
		var dir := Vector3(pc.x - rp.x, 0, pc.z - rp.z)
		var dist := dir.length()
		dir = dir / dist if dist > 0.5 else Vector3(-1, 0, 0)
		center = rp + dir * maxf(dist, road.width * 0.5 + 3.0 + 27.0)
	var n := 7
	var verts: Array[Vector3] = []
	var a0 := _rng.randf() * TAU
	for k in n:
		var a := a0 + TAU * k / n
		verts.append(center + Vector3(cos(a), 0, sin(a)) * _rng.randf_range(19.0, 24.0))
	var wb := PropLibrary.aabb("Castle_Ruin_Wall")
	var skip := [_rng.randi() % n, (_rng.randi() % n + 3) % n]
	for k in n:
		if k in skip:
			continue
		var a: Vector3 = verts[k]
		var b: Vector3 = verts[(k + 1) % n]
		var mid := (a + b) * 0.5
		var l := Vector2(b.x - a.x, b.z - a.z).length()
		var sc := clampf(l / maxf(wb.size.x, 1.0), 0.8, 1.45)
		place("Castle_Ruin_Wall", mid, _yaw_along(b - a), {"scale": sc, "max_drop": 7.0, "clearance": 4.0, "overlap": false, "pad": 3.0})
	for k: int in [0, 2, 5]:
		place("Castle_Ruin_Tower", verts[k], _rng.randf() * TAU, {"max_drop": 7.0, "clearance": 4.0, "overlap": false, "pad": 3.0})
	place("Castle_Ruin_Tower", center, _rng.randf() * TAU, {"scale": 1.3, "max_drop": 8.0, "clearance": 4.0, "overlap": false, "pad": 3.0})
	for k in 14:
		var a := _rng.randf() * TAU
		var p := center + Vector3(cos(a), 0, sin(a)) * _rng.randf_range(8.0, 30.0)
		place("Rock_A" if k % 2 == 0 else "Rock_C", p, _rng.randf() * TAU, {"scale": _rng.randf_range(0.35, 0.7), "overlap": false, "occupy": false, "max_drop": 5.0, "pad": 0.0, "tint": Color(0.92, 0.9, 0.85)})


func _wind_farm(pc: Vector3) -> void:
	var cands: Array = []
	var spacing := 118.0
	for j in range(-5, 6):
		for i in range(-5, 6):
			var p := pc + Vector3((i + (0.5 if j % 2 != 0 else 0.0)) * spacing, 0, j * spacing * 0.87)
			var dist := Vector2(p.x - pc.x, p.z - pc.z).length()
			if dist > 520.0:
				continue
			p += Vector3(_rng.randf_range(-12, 12), 0, _rng.randf_range(-12, 12))
			if absf(p.x) > WorldLayout.PLAY_HALF - 60.0 or absf(p.z) > WorldLayout.PLAY_HALF - 60.0:
				continue
			cands.append([data.height_at(p.x, p.z) - dist * 0.04, p])
	cands.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	var tb := PropLibrary.aabb("Wind_Turbine_Tower")
	var hub := Vector3(0.0, tb.end.y - 2.1, tb.position.z - 0.6)
	var yaw := deg_to_rad(205.0)
	var count := 0
	for c: Array in cands:
		if count >= 12:
			break
		var p: Vector3 = c[1]
		var it := place("Wind_Turbine_Tower", p, yaw, {"clearance": 22.0, "max_drop": 5.0, "pad": 10.0})
		if it.is_empty():
			continue
		var xf: Transform3D = it["xf"]
		_occupied.append(Vector3(p.x, p.z, 50.0))
		items.append({"name": "Wind_Turbine_Rotor", "xf": xf * Transform3D(Basis(), hub), "tint": Color(0, 0, 0, _rng.randf()),
			"vis": VIS_LANDMARK, "col": Col.NONE, "anim": "rotor"})
		count += 1
		if count == 1:
			log_lines.append("first wind turbine at %d,%d" % [int(p.x), int(p.z)])
	log_lines.append("wind turbines: %d" % count)


func _viewpoint(pc: Vector3) -> void:
	var res := _nearest_paved(pc, 400.0)
	if res.is_empty():
		return
	var road: RoadNetwork.Road = res["road"]
	var s0: float = res["s"]
	var e := road.width * 0.5 + road.shoulder
	var bb := PropLibrary.aabb("Viewpoint_Deck")
	for ds: float in [0.0, 12.0, -12.0, 24.0, -24.0, 40.0, -40.0, 60.0, -60.0]:
		var s := s0 + ds
		var p := road.point_at(s)
		var rt := road.right_at(s)
		var hp := data.height_at((p + rt * 25.0).x, (p + rt * 25.0).z)
		var hm := data.height_at((p - rt * 25.0).x, (p - rt * 25.0).z)
		var side := 1.0 if hp < hm else -1.0
		var pos := p + rt * side * (e + 1.2 + bb.end.z)
		var it := place("Viewpoint_Deck", pos, _yaw_to(pos, pos + rt * side), {"y": p.y - 0.42, "clearance": 0.6, "max_drop": 30.0, "pad": 2.0})
		if it.is_empty():
			continue
		for k in 2:
			roadside(road, s + (k * 2 - 1) * (bb.size.x * 0.5 + 3.0), side, 2.0, "Bench", "away", {"max_drop": 3.0})
		roadside(road, s - bb.size.x * 0.5 - 7.0, side, 1.8, "Bin", "away", {"max_drop": 3.0})
		return


func _jetty(pc: Vector3) -> void:
	var lakes := data.lake_list()
	if lakes.is_empty():
		return
	var lk: Dictionary = lakes[0]
	var c := Vector3(float(lk["pos"][0]), 0, float(lk["pos"][1]))
	var level := float(lk["level"])
	var deck := level + JETTY_FREEBOARD
	var dir := Vector3(pc.x - c.x, 0, pc.z - c.z)
	dir = dir.normalized() if dir.length() > 1.0 else Vector3(1, 0, 0)
	# the jetty starts where the bank rises to its deck and runs out over the lake
	var start := Vector3.INF
	var r := 30.0
	while r < float(lk["radius"]) * 1.6:
		var q := c + dir * r
		if data.height_at(q.x, q.z) > deck:
			start = q
			break
		r += 0.5
	if start == Vector3.INF:
		return
	var pb := PropLibrary.aabb("Pier_Section")
	var seg := pb.size.z
	var inward := -dir
	start += inward * maxf(_pier_start(start, inward, deck, pb.size.x * 0.5), 0.0)
	var yaw := _yaw_to(start, start + inward)
	var last := start
	for k in 3:
		var p := start + inward * seg * (k + 0.5)
		if place("Pier_Section", p, yaw, {"y": deck, "water": true, "max_drop": 100.0, "clearance": 2.0, "pad": 0.5}).is_empty():
			break
		last = p
	var side := inward.cross(Vector3.UP)
	place("Boat_Fishing", last + side * (pb.size.x * 0.5 + 1.6), yaw, {"scale": 0.55, "y": level, "water": true, "roads": false, "overlap": false,
		"occupy": false, "max_drop": 100.0, "anim": "boat", "excl": false, "tint": Color(0.3, 0.5, 0.88)})
	place("Bench", start + dir * 5.0 + side * 3.0, _yaw_to(start + dir * 5.0, start + inward * 10.0), {"overlap": false, "max_drop": 2.0})
	for off: float in [16.0, -16.0, 24.0, -24.0]:
		if not _on_piles("Boathouse", start + side * off + dir * 12.0, inward, deck, {"clearance": 3.0}).is_empty():
			break


## Lamp posts under RoadBuilder's street-lamp spots (STREET roads; kept off every road surface incl. junction
## mouths and corner fillets), so the lighting system's lamps have posts.
func _street_lamps() -> void:
	var n_lamps := 0
	for spot: Array in RoadBuilder.street_lamp_spots(net):
		var p: Vector3 = spot[0]
		var rp: Vector3 = spot[1]
		var gy := data.height_at(p.x, p.z)
		if absf(gy - rp.y) > 1.5:
			gy = rp.y - 0.1
		var it := place("Lamp_Street", p, _yaw_to(p, rp), {"y": gy - 0.05, "roads": false, "overlap": false, "occupy": false, "excl": false, "water": true, "max_drop": 100.0})
		if not it.is_empty():
			n_lamps += 1
	log_lines.append("street lamps: %d" % n_lamps)
