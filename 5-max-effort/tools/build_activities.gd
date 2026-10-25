extends SceneTree
## Generates the road activities from the baked road network (deterministic):
## speed traps on long straights, speed zones on fast flowing sections, drift zones on twisty
## mountain/gravel sections, danger-sign jumps next to farm tracks, checkpoint races along long
## roads, a time trial around the scenic loop and festival boards to smash.
## Star targets come from an ideal speed profile (lateral/accel/brake limited) of each road.
## Run: Godot_console.exe --headless --path . --script res://tools/build_activities.gd

const STEP := 2.0
const OUT := "res://data/activities/"

var data: WorldData
var _picked: Array[Vector3] = []


func _initialize() -> void:
	data = WorldData.new()
	if not data.load_data():
		push_error("world data missing")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	for f in DirAccess.get_files_at(OUT):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(OUT + f))
	var defs: Array[ActivityDef] = []
	defs.append_array(_speed_traps())
	defs.append_array(_danger_signs())
	defs.append_array(_zones(ActivityDef.Kind.SPEED_ZONE))
	defs.append_array(_zones(ActivityDef.Kind.DRIFT_ZONE))
	defs.append_array(_races())
	defs.append(_time_trial())
	defs.append(_boards())
	for d in defs:
		var err := ResourceSaver.save(d, OUT + d.id + ".tres")
		var t := ""
		for v in d.targets:
			t += d.format_value(v) + " / " if d.unit != "km/h" else "%d km/h / " % int(v)
		print("%-26s %-15s %-28s len=%5.0f m  targets: %s %s" % [d.id, d.kind_name(), d.display_name, d.length_m, t,
			"" if err == OK else "SAVE ERROR %d" % err])
	print("activities: ", defs.size())
	quit()


# ------------------------------------------------------------------------------------------------
# road helpers
func _n(ri: int) -> int:
	return (data.roads[ri]["x"] as PackedFloat32Array).size()


func _pt(ri: int, i: int) -> Vector3:
	var n := _n(ri)
	i = posmod(i, n) if data.roads[ri]["closed"] else clampi(i, 0, n - 1)
	return data.road_point(ri, i)


func _dir(ri: int, i: int, d: int) -> Vector3:
	var a := _pt(ri, i - 2 * d)
	var b := _pt(ri, i + 2 * d)
	var v := b - a
	v.y = 0.0
	return v.normalized()


func _flags(ri: int, i: int) -> int:
	var f: PackedInt32Array = data.roads[ri]["flags"]
	var n := f.size()
	return f[posmod(i, n) if data.roads[ri]["closed"] else clampi(i, 0, n - 1)]


func _curv(ri: int, i: int) -> float:
	var a := _pt(ri, i - 5)
	var b := _pt(ri, i)
	var c := _pt(ri, i + 5)
	var d1 := Vector2(b.x - a.x, b.z - a.z)
	var d2 := Vector2(c.x - b.x, c.z - b.z)
	if d1.length() < 0.1 or d2.length() < 0.1:
		return 0.0
	return absf(d1.angle_to(d2)) / ((d1.length() + d2.length()) * 0.5)


func _clean(ri: int, i0: int, i1: int, mask: int) -> bool:
	for i in range(mini(i0, i1), maxi(i0, i1) + 1):
		if _flags(ri, i) & mask:
			return false
	return true


func _far_from_picked(p: Vector3, dist: float) -> bool:
	for q in _picked:
		if Vector2(p.x - q.x, p.z - q.z).length() < dist:
			return false
	return true


func _surface_slow(ri: int) -> bool:
	return String(data.roads[ri]["class"]) in ["gravel", "dirt"]


func _profile(ri: int, i0: int, i1: int, d: int) -> PackedFloat32Array:
	## ideal speed (m/s) per sample from i0 to i1 (inclusive, stepping d) for a quick A-class car
	var count := absi(i1 - i0) + 1
	var slow := _surface_slow(ri)
	var a_lat := 6.0 if slow else 9.0
	var v_top := 52.0 if slow else 72.0
	var v := PackedFloat32Array()
	v.resize(count)
	for k in count:
		var kap := _curv(ri, i0 + k * d)
		v[k] = minf(v_top, sqrt(a_lat / maxf(kap, 1e-5)))
	v[0] = minf(v[0], 25.0)   # rolling start
	for k in range(1, count):
		var acc := minf(5.0, 170.0 / maxf(v[k - 1], 5.0)) * (0.7 if slow else 1.0)
		v[k] = minf(v[k], sqrt(v[k - 1] * v[k - 1] + 2.0 * acc * STEP))
	for k in range(count - 2, -1, -1):
		v[k] = minf(v[k], sqrt(v[k + 1] * v[k + 1] + 2.0 * (6.0 if slow else 8.5) * STEP))
	return v


func _ideal_time(ri: int, i0: int, i1: int, d: int) -> float:
	var v := _profile(ri, i0, i1, d)
	var t := 0.0
	for k in v.size() - 1:
		t += STEP / maxf((v[k] + v[k + 1]) * 0.5, 1.0)
	return t


func _region(p: Vector3) -> String:
	return data.region_at(p.x, p.z)


func _base(kind: ActivityDef.Kind, id: String, name: String, ri: int, s0: int, d: int) -> ActivityDef:
	var a := ActivityDef.new()
	a.kind = kind
	a.id = id
	a.display_name = name
	a.road = ri
	a.s0 = s0
	a.dir = d
	a.position = _pt(ri, s0)
	a.heading = _dir(ri, s0, d)
	a.width = float(data.roads[ri]["width"])
	a.region = _region(a.position)
	return a


func _roads_of(classes: Array) -> Array[int]:
	var out: Array[int] = []
	for ri in data.roads.size():
		if String(data.roads[ri]["class"]) in classes:
			out.append(ri)
	return out


# ------------------------------------------------------------------------------------------------
func _speed_traps() -> Array[ActivityDef]:
	var cands: Array = []
	for ri in _roads_of(["highway", "main", "mountain"]):
		var n := _n(ri)
		for i in range(140, n - 140, 20):
			if not _clean(ri, i - 40, i + 15, WorldData.F_TUNNEL | WorldData.F_JUNCTION | WorldData.F_VILLAGE | WorldData.F_BRIDGE):
				continue
			var worst := 0.0
			for k in range(i - 130, i + 20, 5):
				worst = maxf(worst, _curv(ri, k))
			if worst > 0.0045:
				continue
			cands.append([worst, ri, i])
	cands.sort_custom(func(x, y): return x[0] < y[0])
	var out: Array[ActivityDef] = []
	var names := ["Sunline Radar", "Valley Straight", "Ridge Flats", "Lakeside Trap", "Granary Dash", "Eastern Mile", "Coast Line"]
	for c in cands:
		if out.size() >= 6:
			break
		var ri: int = c[1]
		var i: int = c[2]
		var p := _pt(ri, i)
		if not _far_from_picked(p, 900.0):
			continue
		var a := _base(ActivityDef.Kind.SPEED_TRAP, "trap_%02d" % (out.size() + 1), names[out.size()], ri, i, 1)
		var prof := _profile(ri, i - 300 if i > 300 else 0, i, 1)
		var v_ideal := prof[prof.size() - 1] * 3.6
		a.targets = PackedFloat32Array([round(v_ideal * 0.62 / 5.0) * 5.0, round(v_ideal * 0.78 / 5.0) * 5.0,
			round(v_ideal * 0.92 / 5.0) * 5.0])
		a.unit = "km/h"
		var right := a.heading.cross(Vector3.UP).normalized()
		a.prop_position = a.position + right * (a.width * 0.5 + 2.6)
		a.prop_position.y = data.height_at(a.prop_position.x, a.prop_position.z)
		a.prop_yaw = atan2(-a.heading.x, -a.heading.z)
		a.length_m = 0.0
		a.reward = 400
		_picked.append(p)
		out.append(a)
	return out


func _zones(kind: ActivityDef.Kind) -> Array[ActivityDef]:
	var drift := kind == ActivityDef.Kind.DRIFT_ZONE
	var classes := ["mountain", "gravel", "dirt", "main"] if drift else ["highway", "main", "mountain"]
	var length := 300 if drift else 380
	var cands: Array = []
	for ri in _roads_of(classes):
		var n := _n(ri)
		if n < length + 80:
			continue
		for i in range(30, n - length - 30, 40):
			if not _clean(ri, i, i + length, WorldData.F_TUNNEL | WorldData.F_VILLAGE):
				continue
			if _flags(ri, i) & WorldData.F_JUNCTION or _flags(ri, i + length) & WorldData.F_JUNCTION:
				continue
			var turn := 0.0
			for k in range(i, i + length, 5):
				turn += _curv(ri, k) * 10.0
			var prof := _profile(ri, i, i + length, 1)
			var avg := 0.0
			for v in prof:
				avg += v
			avg /= prof.size()
			var score := 0.0
			if drift:
				score = turn * (1.0 if String(data.roads[ri]["class"]) != "main" else 0.7) if avg * 3.6 < 135.0 else -1.0
			else:
				score = avg if turn > 0.8 and turn < 4.0 else -1.0
			if score > 0.0:
				cands.append([score, ri, i, avg])
	cands.sort_custom(func(x, y): return x[0] > y[0])
	var out: Array[ActivityDef] = []
	var names := ["Hairpin Hollow", "Switchback Sway", "Gravel Ballet", "Pine Slide", "Crest Carousel"] if drift \
		else ["Ridgeline Flow", "Valley Sweepers", "Highland Rush", "Coastal Curves", "Lakeside Arc"]
	for c in cands:
		if out.size() >= 4:
			break
		var ri: int = c[1]
		var i: int = c[2]
		var p := _pt(ri, i)
		if not _far_from_picked(p, 300.0 if drift else 600.0) or not _far_from_picked(_pt(ri, i + length), 200.0 if drift else 350.0):
			continue
		var a := _base(kind, ("drift_%02d" if drift else "zone_%02d") % (out.size() + 1), names[out.size()], ri, i, 1)
		a.s1 = i + length
		a.end_position = _pt(ri, i + length)
		a.end_heading = _dir(ri, i + length, 1)
		a.length_m = length * STEP
		if drift:
			var k := a.length_m / 600.0
			a.targets = PackedFloat32Array([round(5000.0 * k / 500.0) * 500.0, round(12000.0 * k / 500.0) * 500.0,
				round(22000.0 * k / 500.0) * 500.0])
			a.unit = "pts"
		else:
			var avg_kmh: float = float(c[3]) * 3.6
			a.targets = PackedFloat32Array([round(avg_kmh * 0.6 / 5.0) * 5.0, round(avg_kmh * 0.76 / 5.0) * 5.0,
				round(avg_kmh * 0.9 / 5.0) * 5.0])
			a.unit = "km/h"
		a.reward = 500
		_picked.append(p)
		_picked.append(a.end_position)
		out.append(a)
	return out


func _danger_signs() -> Array[ActivityDef]:
	var cands: Array = []
	for ri in _roads_of(["gravel", "dirt", "main"]):
		var n := _n(ri)
		var w := float(data.roads[ri]["width"])
		for i in range(60, n - 80, 25):
			if not _clean(ri, i - 20, i + 60, WorldData.F_TUNNEL | WorldData.F_BRIDGE | WorldData.F_JUNCTION | WorldData.F_VILLAGE):
				continue
			var worst := 0.0
			for k in range(i - 20, i + 60, 5):
				worst = maxf(worst, _curv(ri, k))
			if worst > 0.006:
				continue
			var h := _dir(ri, i, 1)
			var right := h.cross(Vector3.UP).normalized()
			for side: float in [1.0, -1.0]:
				var base: Vector3 = _pt(ri, i) + right * side * (w * 0.5 + 5.5)
				# landing strip beside the road must be open, fairly flat, dry and away from other roads
				var ok := true
				var h0 := data.height_at(base.x, base.z)
				var rough := 0.0
				for k in range(0, 9):
					var q: Vector3 = base + h * (k * 12.0)
					var hq := data.height_at(q.x, q.z)
					if data.water_level_at(q.x, q.z) > -999.0 or hq < 1.0:
						ok = false
						break
					rough = maxf(rough, absf(hq - (h0 + (_pt(ri, i + k * 6).y - _pt(ri, i).y))))
					var nr := data.nearest_road(q.x, q.z, 2)
					if not nr.is_empty() and int(nr["road"]) != ri and float(nr["d"]) < 14.0:
						ok = false
						break
				if ok and rough < 1.6:
					cands.append([rough, ri, i, side])
	cands.sort_custom(func(x, y): return x[0] < y[0])
	var out: Array[ActivityDef] = []
	var names := ["Barnyard Leap", "Mesa Launch", "Orchard Hop", "Quarry Flight", "Dune Soar"]
	for c in cands:
		if out.size() >= 4:
			break
		var ri: int = c[1]
		var i: int = c[2]
		var p := _pt(ri, i)
		if not _far_from_picked(p, 420.0):
			continue
		var a := _base(ActivityDef.Kind.DANGER_SIGN, "jump_%02d" % (out.size() + 1), names[out.size()], ri, i, 1)
		var right := a.heading.cross(Vector3.UP).normalized()
		a.prop_position = a.position + right * float(c[3]) * (a.width * 0.5 + 5.5)
		a.prop_position.y = data.height_at(a.prop_position.x, a.prop_position.z) - 0.05
		a.prop_yaw = atan2(a.heading.x, a.heading.z)
		a.targets = PackedFloat32Array([30.0, 50.0, 70.0])
		a.unit = "m"
		a.reward = 500
		_picked.append(p)
		out.append(a)
	return out


func _race(id: String, name: String, ri: int, s0: int, s1: int, d: int, cp_every: int) -> ActivityDef:
	var a := _base(ActivityDef.Kind.RACE, id, name, ri, s0, d)
	a.s1 = s1
	var pts := PackedVector3Array()
	var i := s0 + cp_every * d
	while (d > 0 and i < s1 - cp_every / 3) or (d < 0 and i > s1 + cp_every / 3):
		pts.append(_pt(ri, i))
		i += cp_every * d
	pts.append(_pt(ri, s1))
	a.points = pts
	a.end_heading = _dir(ri, s1, d)
	a.length_m = absi(s1 - s0) * STEP
	var t := _ideal_time(ri, s0, s1, d)
	a.targets = PackedFloat32Array([round(t * 1.75), round(t * 1.42), round(t * 1.2)])
	a.lower_is_better = true
	a.unit = "s"
	a.reward = 800
	return a


func _races() -> Array[ActivityDef]:
	var out: Array[ActivityDef] = []
	var specs := [["race_highway", "Sunline Highway Sprint", "Sunline Highway"],
		["race_rally", "Pinewood Rally Stage", "Pinewood Rally Stage"],
		["race_ridge", "Northern Ridge Climb", "Northern Ridge Road"],
		["race_valley", "Eastern Valley Dash", "Eastern Valley Road"]]
	for s in specs:
		var ri := -1
		for k in data.roads.size():
			if String(data.roads[k]["name"]) == s[2]:
				ri = k
		if ri < 0:
			continue
		var n := _n(ri)
		var s0 := 18
		while s0 < 120 and _flags(ri, s0) & (WorldData.F_JUNCTION | WorldData.F_TUNNEL | WorldData.F_BRIDGE):
			s0 += 4
		var s1 := n - 18
		while s1 > n - 120 and _flags(ri, s1) & (WorldData.F_JUNCTION | WorldData.F_TUNNEL | WorldData.F_BRIDGE):
			s1 -= 4
		out.append(_race(s[0], s[1], ri, s0, s1, 1, 280))
	return out


func _time_trial() -> ActivityDef:
	# full scenic loop, starting at the loop_start teleport
	var ri := 0
	var start: Vector3 = Vector3.ZERO
	var tp: Dictionary = data.meta.get("teleports", {})
	if tp.has("loop_start"):
		var v: Array = tp["loop_start"]   # [x, z, dir_x, dir_z]
		start = Vector3(float(v[0]), 0.0, float(v[1]))
	var n := _n(ri)
	var best := 0
	var bd := 1e18
	for i in range(0, n, 2):
		var p := _pt(ri, i)
		var dd := Vector2(p.x - start.x, p.z - start.z).length_squared()
		if dd < bd:
			bd = dd
			best = i
	while _flags(ri, best) & (WorldData.F_JUNCTION | WorldData.F_TUNNEL | WorldData.F_BRIDGE | WorldData.F_VILLAGE):
		best = posmod(best + 6, n)
	var a := _base(ActivityDef.Kind.TIME_TRIAL, "trial_loop", "Ridgeline Loop Time Trial", ri, best, 1)
	var pts := PackedVector3Array()
	for k in range(500, n, 500):
		if n - k < 150:
			break
		pts.append(_pt(ri, best + k))
	pts.append(_pt(ri, best))
	a.points = pts
	a.s1 = best
	a.end_heading = a.heading
	a.length_m = n * STEP
	var t := 0.0
	for k in range(0, n, 1000):
		t += _ideal_time(ri, best + k, best + mini(k + 1000, n), 1)
	a.targets = PackedFloat32Array([round(t * 1.7), round(t * 1.4), round(t * 1.2)])
	a.lower_is_better = true
	a.unit = "s"
	a.reward = 1500
	return a


func _boards() -> ActivityDef:
	## festival boards to smash: spread over every region beside main, mountain, gravel and dirt roads
	var a := ActivityDef.new()
	a.kind = ActivityDef.Kind.COLLECTIBLES
	a.id = "boards"
	a.display_name = "Festival Boards"
	a.unit = "boards"
	a.reward = 150
	var rng := RandomNumberGenerator.new()
	rng.seed = 777
	var pts := PackedVector3Array()
	var yaws := PackedFloat32Array()
	var placed: Array[Vector3] = []
	var roads := _roads_of(["main", "mountain", "gravel", "dirt", "village", "highway"])
	var attempts := 0
	while pts.size() < 30 and attempts < 4000:
		attempts += 1
		var ri: int = roads[rng.randi_range(0, roads.size() - 1)]
		var n := _n(ri)
		if n < 60:
			continue
		var i := rng.randi_range(20, n - 20)
		if _flags(ri, i) & (WorldData.F_TUNNEL | WorldData.F_BRIDGE | WorldData.F_JUNCTION):
			continue
		var p := _pt(ri, i)
		var ok := true
		for q in placed:
			if q.distance_to(p) < 320.0:
				ok = false
				break
		if not ok:
			continue
		var h := _dir(ri, i, 1)
		var right := h.cross(Vector3.UP).normalized()
		var side := 1.0 if rng.randf() < 0.5 else -1.0
		var q2 := p + right * side * (float(data.roads[ri]["width"]) * 0.5 + 2.2)
		q2.y = maxf(data.height_at(q2.x, q2.z), p.y - 0.3)
		if data.water_level_at(q2.x, q2.z) > -999.0:
			continue
		placed.append(p)
		pts.append(q2)
		yaws.append(atan2(h.x, h.z))
	a.points = pts
	a.yaws = yaws
	a.targets = PackedFloat32Array([10.0, 20.0, 30.0])
	a.length_m = 0.0
	return a
