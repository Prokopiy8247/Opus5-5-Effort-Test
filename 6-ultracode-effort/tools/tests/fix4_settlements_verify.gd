extends Node
## Settlement fixes of playtest round 3, verified inside the real game (main scene) with the keyboard input path
## (Input.action_press with CarInput enabled). Regression test for the settlement collision / placement fixes:
##   Godot_console.exe --audio-driver Dummy --path <project> --resolution 1600x900 res://tools/tests/fix4_settlements_verify.tscn -- --only=data,staticgap,colgap,ruin,props,fuel,signs,lamps,shots
## (each section is about 1-2 minutes; run a few at a time)
## staticgap  bumper-height rays at every side of every building / landmark: game collider vs visible mesh (s0);
## colgap  drives into the diner, chalet, cottages, farmhouse, adobe and the Old Keep (s0) and measures the gap
##         between the car body box and the visible mesh where it stops (shape cast against an exact copy of the
##         rendered mesh on a private physics layer);
## ruin    drives through the widest gap of the Old Keep wall ring (s0);
## props   drives into flag poles, a festival banner and fences (s1 / s14);
## fuel    drives from the near lane onto both forecourts, at the pumps and the front corners (s3);
## data    pier decks / boathouse floors vs water and beach (s2), terrain against ground-floor walls (s4), the
##         harbour shed (s6), junction signs clear of every road with solid posts (s9);
## signs   drives into a junction sign post (s9);
## lamps   fuel-station and diner lamps lit at 22:30 (s5);
## shots   screenshots of the fixed places.
## Prints "[fix4s] PASS|FAIL ..." lines; screenshots in qa_output/fix4_settlements/. Writes no settings.

const PropLibrary := preload("res://scripts/world/prop_library.gd")
const Plan := preload("res://scripts/world/dressing_settlement_plan.gd")
const OUT := "res://qa_output/fix4_settlements/"
const PRIVATE := 1 << 20

var main: Node
var w: World
var net: RoadNetwork
var rig: CameraRig
var st: Node
var ci: CarInput
var fails := 0
var impacts: Array = []
var _faces: Dictionary = {}       # prop name -> PackedVector3Array (rendered mesh, local)
var _bodies: Dictionary = {}      # item index -> private StaticBody3D


func _ready() -> void:
	SaveGame.enabled = false
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(main)
	_run.call_deferred()


func _log(s: String) -> void:
	print("[fix4s] ", s)


func _check(label: String, ok: bool, detail: String) -> void:
	_log("%s %s  %s" % ["PASS" if ok else "FAIL", label, detail])
	if not ok:
		fails += 1


func _wait(s: float) -> void:
	await get_tree().create_timer(s).timeout


func _settle(max_ms := 20000) -> void:
	var t0 := Time.get_ticks_msec()
	await get_tree().process_frame
	while not w.is_ready_near() and Time.get_ticks_msec() - t0 < max_ms:
		await get_tree().process_frame
	await _wait(1.0)


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(OUT + name + ".png")
	_log("shot %s" % ProjectSettings.globalize_path(OUT + name + ".png"))


func _car() -> CarController:
	return Game.player_car


func _on_impact(strength: float, at: Vector3) -> void:
	if strength > 1.0:
		impacts.append([snappedf(strength, 0.1), at.round()])


func _sections() -> PackedStringArray:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			return a.substr(7).split(",")
	return PackedStringArray(["data", "colgap", "ruin", "props", "fuel", "signs", "lamps", "shots"])


func _run() -> void:
	while main.get("is_loading"):
		await get_tree().process_frame
	w = Game.world as World
	net = w.data.network
	rig = Game.camera_rig as CameraRig
	st = main.get_node(^"Settlements")
	ci = main.get("car_input") as CarInput
	ci.enabled = false
	if Game.traffic and Game.traffic.has_method("set_density"):
		Game.traffic.call("set_density", 0.0)
	Game.set_time_of_day(13.0)
	Game.set_weather("clear", true)
	while not w.roads.done:
		await get_tree().process_frame
	_car().impact.connect(_on_impact)
	for sec in _sections():
		match sec:
			"data": await _data()
			"colgap": await _colgap()
			"staticgap": await _staticgap()
			"ruin": await _ruin()
			"props": await _props()
			"fuel": await _fuel()
			"signs": await _signs()
			"lamps": await _lamps()
			"shots": await _shots()
	_log("done, %d failed checks" % fails)
	get_tree().quit(0 if fails == 0 else 1)


# ------------------------------------------------------------------ helpers

func _items() -> Array:
	return st.get("items")


func _find(name: String, near: Vector2, max_d := 80.0) -> int:
	var best := -1
	var bd := max_d
	var arr := _items()
	for i in arr.size():
		var it: Dictionary = arr[i]
		if it["name"] != name:
			continue
		var o: Vector3 = (it["xf"] as Transform3D).origin
		var d := Vector2(o.x - near.x, o.z - near.y).length()
		if d < bd:
			bd = d
			best = i
	return best


## Item indices of `name`, nearest to `near` first.
func _find_all(name: String, near: Vector2, n: int) -> Array[int]:
	var cands: Array = []
	var arr := _items()
	for i in arr.size():
		if arr[i]["name"] == name:
			var o: Vector3 = (arr[i]["xf"] as Transform3D).origin
			cands.append([Vector2(o.x - near.x, o.z - near.y).length(), i])
	cands.sort_custom(func(x: Array, y: Array) -> bool: return x[0] < y[0])
	var out: Array[int] = []
	for k in mini(n, cands.size()):
		out.append(int(cands[k][1]))
	return out


func _mesh_faces(name: String) -> PackedVector3Array:
	if not _faces.has(name):
		_faces[name] = PropLibrary.mesh(name).get_faces()
	return _faces[name]


## Exact copy of an item's rendered mesh on the private layer (the car never collides with it).
func _visible_body(i: int) -> StaticBody3D:
	if _bodies.has(i):
		return _bodies[i]
	var it: Dictionary = _items()[i]
	var xf: Transform3D = it["xf"]
	var src := _mesh_faces(it["name"])
	var faces := PackedVector3Array()
	faces.resize(src.size())
	for k in src.size():
		faces[k] = xf * src[k]
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	shape.backface_collision = true
	var cs := CollisionShape3D.new()
	cs.shape = shape
	var body := StaticBody3D.new()
	body.collision_layer = PRIVATE
	body.collision_mask = 0
	body.add_child(cs)
	add_child(body)
	_bodies[i] = body
	return body


## Free distance the car's body box could still move forward before touching a private (visible) mesh, and the
## private bodies involved: [distance, Array of body instance ids].
func _front_gap(max_d := 8.0) -> Array:
	var car := _car()
	var cs := car.get_node(^"ColMain") as CollisionShape3D
	var space := car.get_world_3d().direct_space_state
	var grown := (cs.shape as BoxShape3D).duplicate() as BoxShape3D
	grown.size += Vector3(0.06, 0.0, 0.06)
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = grown
	q.transform = car.global_transform * cs.transform
	q.collision_mask = PRIVATE
	var ids: Array = []
	for h: Dictionary in space.intersect_shape(q, 8):
		ids.append(int(h["collider_id"]))
	if not ids.is_empty():
		return [0.0, ids]
	q.shape = cs.shape
	q.motion = -car.global_transform.basis.z * max_d
	var r := space.cast_motion(q)
	if r[1] >= 1.0:
		return [max_d, ids]
	q.transform.origin += q.motion * r[1]
	q.motion = Vector3.ZERO
	ids.append(int(space.get_rest_info(q).get("collider_id", 0)))
	return [r[0] * max_d, ids]


## [start, target]: a target among `targets` and a start near target + dir * 18 m (rotated up to 55 deg, or closer)
## from which a box 0.5 m wider than the car's body, driven straight at the target, meets the target's own visible
## mesh at three heights and nothing else on the way. [] when there is none.
func _clear_start(targets: Array, dir_w: Vector3, ti: int) -> Array:
	var tid := _visible_body(ti).get_instance_id()
	await get_tree().physics_frame
	var cs := _car().get_node(^"ColMain") as CollisionShape3D
	var box := (cs.shape as BoxShape3D).duplicate() as BoxShape3D
	box.size.x += 0.5
	var space := get_viewport().get_world_3d().direct_space_state
	for target: Vector3 in targets:
		for ang: float in [0.0, 12.0, -12.0, 25.0, -25.0, 40.0, -40.0, 55.0, -55.0]:
			var d := dir_w.rotated(Vector3.UP, deg_to_rad(ang))
			for dist: float in [16.0, 11.0, 7.0]:
				var start := target + d * dist
				if _path_meets(space, box, start, target - d * 2.0, -d, tid):
					return [start, target]
	return []


## The box, moved over the ground (body height +-0.25 m) from a to b, first meets body `tid` at all three heights.
func _path_meets(space: PhysicsDirectSpaceState3D, box: BoxShape3D, a: Vector3, b: Vector3, fwd: Vector3, tid: int) -> bool:
	var n := maxi(int(a.distance_to(b)), 1)
	# other game obstacles (event ramps, gates, dressing colliders) on the way
	var side := fwd.cross(Vector3.UP).normalized()
	for ray: Vector2 in [Vector2(-0.9, 0.3), Vector2(0.0, 0.3), Vector2(0.9, 0.3), Vector2(-0.9, 0.7), Vector2(0.0, 0.7), Vector2(0.9, 0.7)]:
		for k in n:
			var p0 := a.lerp(b, float(k) / n) + side * ray.x
			var p1 := a.lerp(b, float(k + 1) / n) + side * ray.x
			p0.y = w.height_at(p0.x, p0.z) + ray.y
			p1.y = w.height_at(p1.x, p1.z) + ray.y
			var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(p0, p1, 1 | 32))
			if hit.is_empty():
				continue
			var col := hit["collider"] as Node
			var nm := String(col.name)
			if not nm.begins_with("SettlementCol") and not nm.begins_with("TC_") and not col.has_meta(&"road"):
				return false
			break
	for dy: float in [-0.25, 0.0, 0.25]:
		var met := false
		for k in n:
			var p0 := a.lerp(b, float(k) / n)
			var p1 := a.lerp(b, float(k + 1) / n)
			p0.y = w.height_at(p0.x, p0.z) + 0.75 + dy
			p1.y = w.height_at(p1.x, p1.z) + 0.75 + dy
			var q := PhysicsShapeQueryParameters3D.new()
			q.shape = box
			q.collision_mask = PRIVATE
			q.transform = Transform3D(Basis.looking_at(fwd, Vector3.UP), p0)
			if k == 0 and not space.intersect_shape(q, 1).is_empty():
				return false
			q.motion = p1 - p0
			var r := space.cast_motion(q)
			if r[1] >= 1.0:
				continue
			q.transform.origin += q.motion * r[1]
			q.motion = Vector3.ZERO
			if int(space.get_rest_info(q).get("collider_id", 0)) != tid:
				return false
			met = true
			break
		if not met:
			return false
	return true


## Game colliders (not terrain) within 0.15 m of the car's body box.
func _touching() -> String:
	var car := _car()
	var cs := car.get_node(^"ColMain") as CollisionShape3D
	var box := (cs.shape as BoxShape3D).duplicate() as BoxShape3D
	box.size += Vector3(0.3, 0.0, 0.3)
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = box
	q.transform = car.global_transform * cs.transform
	q.collision_mask = 1 | 32
	q.exclude = [car.get_rid()]
	var names := PackedStringArray()
	for h: Dictionary in car.get_world_3d().direct_space_state.intersect_shape(q, 8):
		var n := String((h["collider"] as Node).name)
		if not n.begins_with("TC_") and not names.has(n):
			names.append(n)
	return ",".join(names)


func _ground(x: float, z: float) -> float:
	return w.ground_at(x, z, w.height_at(x, z) + 4.0)


func _place_car(pos: Vector3, fwd: Vector3) -> void:
	fwd.y = 0.0
	main.call("teleport_to", {"position": Vector3(pos.x, _ground(pos.x, pos.z), pos.z), "forward": fwd.normalized()})
	await _settle()
	_car().freeze = false
	await _wait(0.6)


func _release() -> void:
	for a: String in ["accelerate", "brake", "steer_left", "steer_right"]:
		Input.action_release(a)


## Drives (keyboard input) from `start` at `target` holding about `kmh`. Stops when the car has come to rest after
## moving, when it is `pass_d` metres past the target along the approach, or after `timeout` s.
func _drive_at(start: Vector3, target: Vector3, kmh: float, timeout := 12.0, pass_d := 4.0, stop_fn := Callable()) -> Dictionary:
	var dir := target - start
	dir.y = 0.0
	dir = dir.normalized()
	await _place_car(start, dir)
	var car := _car()
	impacts.clear()
	ci.enabled = true
	var t := 0.0
	var v_prev := car.linear_velocity.length()
	var vmax := 0.0
	var decel := 0.0
	var v_hit := 0.0
	var rest := 0.0
	var gap_hit: Array = []
	var passed := false
	var stopped := false
	while t < timeout:
		await get_tree().physics_frame
		var dt := get_physics_process_delta_time()
		t += dt
		car = _car()
		var v := car.linear_velocity.length()
		vmax = maxf(vmax, v)
		var a := (v_prev - v) / dt
		if a > decel:
			decel = a
			v_hit = v_prev
			if a > 40.0:
				gap_hit = _front_gap()
		v_prev = v
		if v * 3.6 < kmh:
			Input.action_press("accelerate", 1.0)
		else:
			Input.action_release("accelerate")
		var to := target - car.global_position
		to.y = 0.0
		var fwd := -car.global_transform.basis.z
		fwd.y = 0.0
		var ang := atan2(-fwd.cross(to).y, fwd.dot(to))
		var steer := clampf(ang * 3.0, -1.0, 1.0)
		Input.action_release("steer_left" if steer >= 0.0 else "steer_right")
		if absf(steer) > 0.02:
			Input.action_press("steer_right" if steer > 0.0 else "steer_left", absf(steer))
		if (car.global_position - target).dot(dir) > pass_d:
			passed = true
			break
		if stop_fn.is_valid() and stop_fn.call():
			break
		rest = rest + dt if v < 0.4 and car.global_position.distance_to(start) > 1.0 else 0.0
		if rest > 0.5:
			stopped = true
			break
	_release()
	ci.enabled = false
	car.in_throttle = 0.0
	car.in_steer = 0.0
	return {"stopped": stopped, "passed": passed, "vmax": vmax * 3.6, "v_hit": v_hit * 3.6, "decel": decel, "imp": impacts.duplicate(), "t": t, "gap_hit": gap_hit}


func _brake_stop() -> void:
	var car := _car()
	car.in_brake = 1.0
	var t := 0.0
	while car.linear_velocity.length() > 0.3 and t < 4.0:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	car.in_brake = 0.0


var _hidden: Array[CanvasLayer] = []


func _hud(visible: bool) -> void:
	if not visible:
		for c in main.get_children():
			if c is CanvasLayer and (c as CanvasLayer).visible:
				(c as CanvasLayer).visible = false
				_hidden.append(c)
	else:
		for c in _hidden:
			c.visible = true
		_hidden.clear()


## Paused-physics views around the car: chase (rig), side and top (free camera).
func _views(name: String, focus: Vector3, side_dir: Vector3) -> void:
	get_tree().paused = true
	_hud(false)
	await _shot(name + "_chase")
	rig.active = false
	var sd := side_dir
	sd.y = 0.0
	sd = sd.normalized()
	rig.global_transform = Transform3D(Basis(), focus + sd * 7.0 + Vector3.UP * 1.2).looking_at(focus + Vector3.UP * 0.6, Vector3.UP)
	await get_tree().process_frame
	await _shot(name + "_side")
	rig.global_transform = Transform3D(Basis(), focus + Vector3.UP * 14.0 + sd * 0.5).looking_at(focus, Vector3.UP)
	await get_tree().process_frame
	await _shot(name + "_top")
	rig.active = true
	_hud(true)
	get_tree().paused = false


func _free_view(name: String, eye: Vector3, look: Vector3) -> void:
	eye.y = maxf(eye.y, w.height_at(eye.x, eye.z) + 1.2)
	var car := _car()
	car.freeze = true
	car.visible = false
	car.global_position = Vector3(eye.x, w.height_at(eye.x, eye.z) + 1.0, eye.z)
	w.refocus(car.global_position)
	rig.active = false
	rig.global_transform = Transform3D(Basis(), eye).looking_at(look, Vector3.UP)
	await _settle()
	rig.global_transform = Transform3D(Basis(), eye).looking_at(look, Vector3.UP)
	await _wait(0.4)
	_hud(false)
	await _shot(name)
	_hud(true)
	rig.active = true
	car.visible = true
	car.freeze = false


# ------------------------------------------------------------------ s0: colliders match the visible buildings

func _colgap() -> void:
	# [prop, near xz, local approach direction (from the building towards the car start), local target offset]
	var cases: Array = [
		["Diner", Vector2(262, 1319), Vector3(1, 0, 0), Vector3(0, 0, 0), "diner end centre"],
		["Diner", Vector2(262, 1319), Vector3(1, 0, 0), Vector3(0, 0, 2.6), "diner rounded end 2.6 m off-centre"],
		["Diner", Vector2(262, 1319), Vector3(-1, 0, 0), Vector3(0, 0, -2.6), "diner other end off-centre"],
		["Diner", Vector2(262, 1319), Vector3(0, 0, 1), Vector3(0, 0, 0), "diner back"],
		["House_Chalet", Vector2(-1505, -1307), Vector3(0, 0, -1), Vector3(0, 0, 0), "chalet front"],
		["House_Chalet", Vector2(-1505, -1307), Vector3(1, 0, 0), Vector3(0, 0, 0), "chalet side"],
		["House_Cottage_B", Vector2(-1177, 557), Vector3(0, 0, -1), Vector3(1.5, 0, 0), "cottage B front porch"],
		["House_Cottage_B", Vector2(-1177, 557), Vector3(1, 0, 0), Vector3(0, 0, 0), "cottage B side"],
		["House_Cottage_A", Vector2(-1150, 640), Vector3(0, 0, -1), Vector3(0, 0, 0), "cottage A front"],
		["Farmhouse", Vector2(-1508, 549), Vector3(0, 0, -1), Vector3(0, 0, 0), "farmhouse front"],
		["House_Adobe", Vector2(1080, -60), Vector3(0, 0, 1), Vector3(0, 0, 0), "adobe back"],
		["Castle_Ruin_Tower", Vector2(-1854, -1523), Vector3(1, 0, 0), Vector3(0, 0, 0), "keep tower"],
		["Castle_Ruin_Wall", Vector2(-1862, -1518), Vector3(0, 0, 1), Vector3(0, 0, 0), "keep wall face"],
	]
	var worst := 0.0
	var n_ok := 0
	for c: Array in cases:
		# the named instance, or the next nearest one of that prop when every approach to it is blocked
		var i := -1
		var xf := Transform3D()
		var rot := Basis()
		var dir_w := Vector3.ZERO
		var pick: Array = []
		for cand: int in _find_all(c[0], c[1], 4):
			i = cand
			xf = _items()[i]["xf"]
			for j in _items().size():
				var o: Vector3 = (_items()[j]["xf"] as Transform3D).origin
				if int(_items()[j]["col"]) != 0 and o.distance_to(xf.origin) < 45.0:
					_visible_body(j)
			rot = xf.basis.orthonormalized()
			dir_w = rot * (c[2] as Vector3)
			var targets: Array = []
			var bbt := PropLibrary.aabb(c[0])
			var face := absf((c[2] as Vector3).dot(bbt.size)) * 0.5 + (c[2] as Vector3).dot(bbt.get_center())
			for shift: float in [0.0, 2.0, -2.0, 4.0, -4.0]:
				var tl: Vector3 = (c[3] as Vector3) + (c[2] as Vector3) * face + Vector3(c[2].z, 0, c[2].x) * shift
				var tw := xf * tl
				tw.y = _ground(tw.x, tw.z) + 0.75
				targets.append(tw)
			pick = await _clear_start(targets, dir_w, i)
			if not pick.is_empty():
				break
		if pick.is_empty():
			_log("SKIP s0 %s: every approach to the 4 nearest %s meets another prop (their fences) first; covered by staticgap" % [c[4], c[0]])
			continue
		var start: Vector3 = pick[0]
		var target: Vector3 = pick[1]
		var r := await _drive_at(start, target, 30.0, 14.0, 3.0)
		var fg: Array = r["gap_hit"] if not (r["gap_hit"] as Array).is_empty() else _front_gap()
		var gap: float = fg[0]
		var own: bool = (fg[1] as Array).has(_visible_body(i).get_instance_id())
		var rest_gap: Array = _front_gap()
		var touch := _touching()
		var tag := "colgap_%s" % String(c[4]).replace(" ", "_").replace(".", "")
		dir_w = (start - target).normalized()
		await _views(tag, _car().global_position - dir_w * 1.5, dir_w.cross(Vector3.UP))
		var ok: bool = float(r["decel"]) > 40.0 and gap < 0.25 and own
		worst = maxf(worst, gap)
		n_ok += 1 if ok else 0
		_check("s0 %s (%s at %s): car stops at the visible wall" % [c[4], c[0], str(xf.origin.round())], ok,
			"approach %.0f deg off the face normal, hit at %.0f km/h, peak decel %.0f m/s2, body box to its visible mesh at the impact %.2f m%s (at rest %.2f m), touching [%s], impacts %d" % [
			rad_to_deg(dir_w.angle_to(rot * (c[2] as Vector3))), r["v_hit"], r["decel"], gap, "" if own else " (NOT this building)", rest_gap[0], touch, (r["imp"] as Array).size()])
		await _brake_stop()
	_log("colgap: %d cases ok, largest gap %.2f m" % [n_ok, worst])


func _staticgap() -> void:
	var arr := _items()
	var targets: Array = Plan.FLOOR_PROPS + ["Boathouse", "Lighthouse", "Castle_Ruin_Wall", "Castle_Ruin_Tower", "Silo", "Water_Tower",
		"Gas_Station", "Festival_Stage", "Festival_Tent", "Wind_Turbine_Tower", "Bus_Stop", "Fuel_Pump"]
	for i in arr.size():
		if int(arr[i]["col"]) != 0:
			_visible_body(i)
	for c in st.get_children():
		var mi := c as MeshInstance3D
		if mi != null and (mi.name.contains("Apron") or mi.name.contains("Pad")):
			var shape := ConcavePolygonShape3D.new()
			shape.set_faces(mi.mesh.get_faces())
			shape.backface_collision = true
			var cs := CollisionShape3D.new()
			cs.shape = shape
			var body := StaticBody3D.new()
			body.collision_layer = PRIVATE
			body.collision_mask = 0
			body.add_child(cs)
			add_child(body)
			_log("  private copy of %s: %d faces" % [mi.name, shape.get_faces().size() / 3])
	await get_tree().physics_frame
	await get_tree().physics_frame
	var space := get_viewport().get_world_3d().direct_space_state
	var lanes := 0
	var bad := 0
	var worst := 0.0
	var worst_at := ""
	var per := {}
	var thin := 0
	var thin_gaps := PackedStringArray()
	for i in arr.size():
		var nm: String = arr[i]["name"]
		if not (nm in targets):
			continue
		var xf: Transform3D = arr[i]["xf"]
		var bb := PropLibrary.aabb(nm)
		var c := bb.get_center()
		for side: Vector3 in [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)]:
			var along := Vector3(side.z, 0, side.x)
			var half_n := absf(side.dot(bb.size)) * 0.5
			var half_t := absf(along.dot(bb.size)) * 0.5
			for f: float in [-0.42, -0.25, -0.08, 0.08, 0.25, 0.42]:
				var edge := Vector3(c.x, 0.0, c.z) + side * half_n + along * half_t * 2.0 * f
				var we := xf * edge
				var gy := w.height_at(we.x, we.z)
				for h: float in [0.45, 0.9]:
					var a := xf * (edge + side * 4.0)
					var b := xf * (edge - side * half_n)
					a.y = gy + h
					b.y = gy + h
					var qg := PhysicsRayQueryParameters3D.create(a, b, 1 | 32)
					var hg := space.intersect_ray(qg)
					if hg.is_empty() or not String((hg["collider"] as Node).name).begins_with("SettlementCol"):
						continue
					var qv := PhysicsRayQueryParameters3D.create(a, b, PRIVATE)
					var hv := space.intersect_ray(qv)
					var dg := a.distance_to(hg["position"])
					var dv := a.distance_to(hv["position"]) if not hv.is_empty() else a.distance_to(b)
					var cname := String((hg["collider"] as Node).name)
					var gap := dv - dg
					if cname.ends_with("_b"):
						thin += 1
						if gap > 0.25:
							thin_gaps.append("%s %.2f" % [str(hg["position"].round()), gap])
						continue
					lanes += 1
					if gap > worst:
						worst = gap
						worst_at = "%s %s side %s lane %.2f h %.2f (collider %s)" % [nm, str(xf.origin.round()), str(side), f, h, cname]
					if gap > 0.25:
						bad += 1
						per[nm] = int(per.get(nm, 0)) + 1
						if bad <= 12:
							var sh := ((hg["collider"] as Node).get_child(int(hg["shape"])) as CollisionShape3D)
							_log("  gap %.2f m: %s %s side %s lane %.2f h %.2f collider %s shape %s at %s, hit at %s" % [gap, nm, str(xf.origin.round()), str(side), f, h, cname,
								sh.shape.get_class() if sh else "?", str(sh.global_position.round()) if sh else "?", str(hg["position"].snappedf(0.01))])
	_check("s0 bumper-height rays at every building side meet the visible wall, not an invisible collider (gap <= 0.25 m)", bad == 0 and lanes > 500,
		"%d rays on building colliders, %d with a gap over 0.25 m %s, worst %.2f m at %s" % [lanes, bad, str(per), worst, worst_at])
	_log("  %d rays stopped first by thin props (fences, mailboxes, benches, lamps); %d of them between fence rails / under a bench: %s" % [thin, thin_gaps.size(), str(thin_gaps.slice(0, 8))])


func _ruin() -> void:
	var ti := -1
	var arr := _items()
	for i in arr.size():
		if arr[i]["name"] == "Castle_Ruin_Tower" and (arr[i]["xf"] as Transform3D).basis.get_scale().x > 1.2:
			ti = i
	if ti < 0:
		_check("s0 keep centre tower", false, "missing")
		return
	var centre: Vector3 = (arr[ti]["xf"] as Transform3D).origin
	for i in arr.size():
		var nm: String = arr[i]["name"]
		if nm.begins_with("Castle_") and (arr[i]["xf"] as Transform3D).origin.distance_to(centre) < 45.0:
			_visible_body(i)
	await get_tree().physics_frame
	var space := get_viewport().get_world_3d().direct_space_state
	var open: Array[bool] = []
	for k in 180:
		var a := TAU * k / 180.0
		var d := Vector3(cos(a), 0, sin(a))
		var p1 := centre + d * 34.0
		var p2 := centre + d * 12.0
		var q := PhysicsRayQueryParameters3D.create(Vector3(p1.x, w.height_at(p1.x, p1.z) + 0.9, p1.z), Vector3(p2.x, w.height_at(p2.x, p2.z) + 0.9, p2.z), PRIVATE)
		var hit := space.intersect_ray(q)
		var q2 := PhysicsRayQueryParameters3D.create(Vector3(p1.x, w.height_at(p1.x, p1.z) + 0.9, p1.z) + d.cross(Vector3.UP) * 1.4, Vector3(p2.x, w.height_at(p2.x, p2.z) + 0.9, p2.z) + d.cross(Vector3.UP) * 1.4, PRIVATE)
		var q3 := PhysicsRayQueryParameters3D.create(Vector3(p1.x, w.height_at(p1.x, p1.z) + 0.9, p1.z) - d.cross(Vector3.UP) * 1.4, Vector3(p2.x, w.height_at(p2.x, p2.z) + 0.9, p2.z) - d.cross(Vector3.UP) * 1.4, PRIVATE)
		open.append(hit.is_empty() and space.intersect_ray(q2).is_empty() and space.intersect_ray(q3).is_empty())
	var best_len := 0
	var best_mid := -1
	for k in 180:
		if not open[k] or open[(k + 179) % 180]:
			continue
		var n := 0
		while n < 180 and open[(k + n) % 180]:
			n += 1
		if n > best_len:
			best_len = n
			best_mid = (k + int(n * 0.5)) % 180
	if best_mid < 0:
		_check("s0 Old Keep has an open gap in its wall ring", false, "no visible gap found")
		return
	var a := TAU * best_mid / 180.0
	var d := Vector3(cos(a), 0, sin(a))
	_log("keep: widest visible gap %d deg wide at %.0f deg" % [best_len * 2, rad_to_deg(a)])
	# from inside the ring (the keep stands on a hill top) out through the gap, downhill
	var start := centre + d * 11.5
	var target := centre + d * 36.0
	target.y = _ground(target.x, target.z) + 0.6
	var r := await _drive_at(start, target, 30.0, 20.0, 0.0,
		func() -> bool: return Vector2(_car().global_position.x - centre.x, _car().global_position.z - centre.z).length() > 28.0)
	var rr := Vector2(_car().global_position.x - centre.x, _car().global_position.z - centre.z).length()
	await _views("ruin_gap", _car().global_position, d.cross(Vector3.UP))
	_check("s0 the car drives through the Old Keep wall gap", rr > 27.5, "reached %.1f m from the keep centre (wall ring 19-24 m) in %.1f s, vmax %.0f km/h, peak decel %.0f m/s2, wheels on ground %d, touching [%s]" % [
		rr, r["t"], r["vmax"], r["decel"], _car().wheels_on_ground, _touching()])
	await _brake_stop()


# ------------------------------------------------------------------ s1 / s14: thin props are solid

func _props() -> void:
	var cases: Array = [
		["Flag_Pole", Vector2(-198.4, 642.6), "boulevard flag pole"],
		["Flag_Pole", Vector2(-138.0, 745.0), "showground flag ring pole"],
		["Festival_Banner", Vector2(-202.5, 659.7), "festival banner"],
		["Fence_Wood", Vector2(-1463.7, 538.2), "Wend Farm fence"],
		["Fence_Wood", Vector2(-1132.3, 484.2), "Millbrook fence s=18"],
		["Fence_Wood", Vector2(-1191.6, 614.9), "Millbrook fence s=162"],
		["Bench", Vector2(-1150.0, 640.0), "Millbrook bench"],
	]
	for c: Array in cases:
		var i := _find(c[0], c[1], 60.0)
		if i < 0:
			_check("s1 %s exists" % c[2], false, "none near %s" % str(c[1]))
			continue
		var xf: Transform3D = _items()[i]["xf"]
		var o := xf.origin
		var dir_w: Vector3
		if c[0] == "Fence_Wood" or c[0] == "Bench":
			dir_w = xf.basis.orthonormalized().z
			var rp: Vector3 = net.nearest(o, 80.0).get("position", o + dir_w)
			if (rp - o).dot(dir_w) < 0.0:
				dir_w = -dir_w
		else:
			var rp2: Vector3 = net.nearest(o, 80.0).get("position", o + Vector3.FORWARD)
			dir_w = Vector3(rp2.x - o.x, 0, rp2.z - o.z).normalized()
		for j in _items().size():
			if int(_items()[j]["col"]) != 0 and (_items()[j]["xf"] as Transform3D).origin.distance_to(o) < 40.0:
				_visible_body(j)
		var target := o
		target.y = _ground(o.x, o.z) + 0.75
		var pick := await _clear_start([target], dir_w, i)
		if pick.is_empty():
			pick = await _clear_start([target], -dir_w, i)
		if pick.is_empty():
			_check("s1 %s: a clear approach exists" % c[2], false, "every approach meets another prop first")
			continue
		dir_w = ((pick[0] as Vector3) - target).normalized()
		var r := await _drive_at(pick[0], target, 38.0, 12.0, 3.0)
		var tag := "props_%s" % String(c[2]).replace(" ", "_").replace("=", "")
		await _views(tag, _car().global_position - dir_w * 1.2, dir_w.cross(Vector3.UP))
		var ok: bool = not r["passed"] and r["stopped"] and float(r["decel"]) > 60.0
		_check("s1 %s at %s stops the car" % [c[2], str(o.round())], ok, "vmax %.0f km/h, hit at %.0f km/h, peak decel %.0f m/s2, passed through %s, touching [%s], impacts %s" % [
			r["vmax"], r["v_hit"], r["decel"], str(r["passed"]), _touching(), str(r["imp"])])
		await _brake_stop()


# ------------------------------------------------------------------ s3: fuel station forecourts reachable

func _fuel() -> void:
	var arr := _items()
	var n := 0
	for i in arr.size():
		if arr[i]["name"] != "Gas_Station":
			continue
		n += 1
		var xf: Transform3D = arr[i]["xf"]
		var rot := xf.basis.orthonormalized()
		var res := net.nearest(xf.origin, 80.0, func(r: RoadNetwork.Road) -> bool: return r.traffic)
		var road: RoadNetwork.Road = res["road"]
		var side := signf(float(res["lateral"]))
		_log("station %d at %s on %s, slab top %.2f" % [n, str(xf.origin.round()), road.id, xf.origin.y])
		# step along the forecourt front edge: physics surface 0.5 m outside vs 0.35 m inside
		var space := get_viewport().get_world_3d().direct_space_state
		var worst := 0.0
		for k in 9:
			var x := -8.4 + 16.8 * k / 8.0
			var hs: Array[float] = []
			for z: float in [-11.1, -10.25]:
				var p := xf * Vector3(x, 0.0, z)
				var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 4.0, p - Vector3.UP * 6.0, 1)
				var hit := space.intersect_ray(q)
				hs.append((hit["position"] as Vector3).y if not hit.is_empty() else -INF)
			worst = maxf(worst, absf(hs[1] - hs[0]))
		_check("s3 station %d forecourt front edge has no step" % n, worst < 0.12, "largest step across the front edge %.2f m" % worst)
		# straight at a pump (the original repro), beside the pump islands and in at the centre (stopping before the
		# central canopy column): the car must get onto the forecourt; anything it then hits stands on the forecourt
		for lane: Vector2 in [Vector2(3.26, -4.0), Vector2(-6.0, -4.0), Vector2(6.0, -4.0), Vector2(0.0, -9.0)]:
			var target := xf * Vector3(lane.x, 0.6, lane.y)
			var s0: float = float(res["s"]) + (target - road.point_at(float(res["s"]))).dot(road.flat_tangent_at(float(res["s"])))
			var lane_p := road.surface_point(s0, side * road.lane_offset(1))
			var start := lane_p - rot.z * 4.0
			var stop_z := lane.y - 1.5
			var r := await _drive_at(start, target, 32.0, 12.0, 0.0,
				func() -> bool: return (xf.affine_inverse() * _car().global_position).z > stop_z)
			var lp := xf.affine_inverse() * _car().global_position
			var tag := "fuel%d_x%+d" % [n, int(lane.x)]
			await _views(tag, _car().global_position, rot.x)
			var on_court := true
			var imp_z := PackedFloat32Array()
			for im: Array in r["imp"]:
				var iz := (xf.affine_inverse() * (im[1] as Vector3)).z
				imp_z.append(snappedf(iz, 0.1))
				on_court = on_court and iz > -10.3
			var ok: bool = lp.z > -11.0 and absf(lp.y) < 1.2 and (float(r["decel"]) < 120.0 or on_court)
			_check("s3 station %d: from the near lane onto the forecourt at x=%+.1f" % [n, lane.x], ok,
				"reached local z %.1f (forecourt front -10.6), height over slab %.2f, vmax %.0f km/h, peak decel %.0f m/s2, impacts %s at local z %s (on the forecourt: %s)" % [
				lp.z, lp.y, r["vmax"], r["decel"], str(r["imp"]), str(imp_z), str(on_court)])
			await _brake_stop()
	_check("s3 both fuel stations placed", n == 2, "%d" % n)


# ------------------------------------------------------------------ s2 / s4 / s6 / s9 data checks

func _data() -> void:
	var arr := _items()
	var piers := 0
	var bad_piers := PackedStringArray()
	var houses := 0
	var bad_walls := PackedStringArray()
	var worst_wall := -INF
	var sheds := 0
	for i in arr.size():
		var it: Dictionary = arr[i]
		var nm: String = it["name"]
		if nm == "":
			continue
		var xf: Transform3D = it["xf"]
		var o := xf.origin
		if nm == "Pier_Section":
			piers += 1
			var water := _water_ref(o)
			var buried := -INF
			for zz in 11:
				for xx: float in [-1.4, 0.0, 1.4]:
					var p := xf * Vector3(xx, 0.0, -5.0 + zz)
					buried = maxf(buried, w.height_at(p.x, p.z) - o.y)
			var fb := o.y - water
			_log("pier section at %s deck %.2f water %.2f freeboard %.2f, terrain above deck max %.2f" % [str(o.round()), o.y, water, fb, buried])
			if fb < 0.4 or fb > 1.3 or buried > 0.05:
				bad_piers.append(str(o.round()))
		elif nm == "Boathouse":
			var water2 := _water_ref(o)
			var bb := PropLibrary.aabb(nm)
			var hi := -INF
			for fx in 5:
				for fz in 5:
					var p := xf * Vector3(bb.position.x + bb.size.x * fx / 4.0, 0.0, bb.position.z + bb.size.z * fz / 4.0)
					hi = maxf(hi, w.height_at(p.x, p.z))
			var back := xf * Vector3(0.0, 0.0, bb.end.z - 0.5)
			_check("s2 boathouse at %s stands on piles above the water, nothing buried" % str(o.round()), hi <= o.y + 0.12 and o.y - water2 > 0.3 and o.y - water2 < 1.4,
				"floor %.2f, water %.2f, terrain at the water end %.2f, highest terrain under it %.2f" % [o.y, water2, w.height_at(back.x, back.z), hi])
		elif nm == "Harbour_Shed":
			sheds += 1
			_log("harbour shed at %s" % str(o.round()))
		if nm in Plan.FLOOR_PROPS:
			houses += 1
			var wall := _wall_terrain(nm, xf)
			worst_wall = maxf(worst_wall, wall)
			if wall > 0.45:
				bad_walls.append("%s %s %.2f" % [nm, str(o.round()), wall])
	_check("s2 pier decks above the water and clear of the beach", piers >= 8 and bad_piers.is_empty(), "%d sections, bad: %s" % [piers, str(bad_piers)])
	_check("s4 no ground-floor wall buried (terrain <= 0.45 m above the floor, plinth tops 0.35-0.45)", bad_walls.is_empty(),
		"%d buildings, worst %.2f m, over: %s" % [houses, worst_wall, str(bad_walls)])
	_check("s6 Gullhaven has its harbour shed", sheds >= 1, "%d Harbour_Shed" % sheds)
	var counts := {}
	for it: Dictionary in arr:
		counts[it["name"]] = int(counts.get(it["name"], 0)) + 1
	_log("counts: %s" % str(counts))
	await _sign_audit()


## Sea level, or the lake level for things up at Mirror Lake.
func _water_ref(o: Vector3) -> float:
	var lv := w.water_level_at(o.x, o.z)
	if lv > -INF:
		return lv
	for lk: Dictionary in w.data.lake_list():
		if Vector2(o.x - float(lk["pos"][0]), o.z - float(lk["pos"][1])).length() < float(lk["radius"]) * 2.0:
			return float(lk["level"])
	return WorldLayout.SEA_LEVEL


## Highest terrain 0.3 m outside the ground-floor walls (outline from the rendered mesh 0.3-2.2 m up) above the floor.
func _wall_terrain(nm: String, xf: Transform3D) -> float:
	var f := _mesh_faces(nm)
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for v in f:
		if v.y > 0.6 and v.y < 2.2:
			lo = Vector2(minf(lo.x, v.x), minf(lo.y, v.z))
			hi = Vector2(maxf(hi.x, v.x), maxf(hi.y, v.z))
	var worst := -INF
	var steps := 24
	for k in steps:
		var t := float(k) / steps
		for p2: Vector2 in [Vector2(lerpf(lo.x, hi.x, t), lo.y - 0.3), Vector2(lerpf(lo.x, hi.x, t), hi.y + 0.3), Vector2(lo.x - 0.3, lerpf(lo.y, hi.y, t)), Vector2(hi.x + 0.3, lerpf(lo.y, hi.y, t))]:
			var p := xf * Vector3(p2.x, 0.0, p2.y)
			worst = maxf(worst, w.height_at(p.x, p.z) - xf.origin.y)
	return worst


func _sign_roots() -> Array[Node3D]:
	var out: Array[Node3D] = []
	for c in w.roads.get_children():
		var n := c as Node3D
		if n == null:
			continue
		for k in n.get_children():
			if k is Label3D:
				out.append(n)
				break
	return out


func _sign_width(n: Node3D) -> float:
	for k in n.get_children():
		var mi := k as MeshInstance3D
		if mi != null and mi.mesh is BoxMesh:
			return (mi.mesh as BoxMesh).size.x
	return 0.0


func _sign_audit() -> void:
	var signs := _sign_roots()
	var on_road := PackedStringArray()
	var no_body := 0
	for n in signs:
		var wdt := _sign_width(n)
		var bad := false
		for f: float in [-0.5, -0.4, 0.4, 0.5]:
			var p := n.global_transform * Vector3(wdt * f, 0, 0)
			if net.edge_clearance(p) < 0.5:
				bad = true
		if bad:
			on_road.append(str(n.global_position.round()))
		var body := n.get_node_or_null(^"SignPosts") as StaticBody3D
		if body == null or body.get_child_count() < 2 or body.collision_layer & 32 == 0:
			no_body += 1
	_check("s9 every junction sign (posts and board ends) >= 0.5 m beyond every road's paved edge", signs.size() > 40 and on_road.is_empty(),
		"%d signs, too close: %s" % [signs.size(), str(on_road)])
	_check("s9 every junction sign has solid posts", no_body == 0, "%d of %d without a post body" % [no_body, signs.size()])


# ------------------------------------------------------------------ s9 drive

func _signs() -> void:
	var signs := _sign_roots()
	var cases: Array = [Vector2(-740, 570), Vector2(1730, -1027)]
	for c: Vector2 in cases:
		var best: Node3D = null
		var bd := INF
		for n in signs:
			var d := Vector2(n.global_position.x - c.x, n.global_position.z - c.y).length()
			if d < bd:
				bd = d
				best = n
		if best == null:
			continue
		var wdt := _sign_width(best)
		# the board's +x points to the road: inner post at +0.4 w, approached from the road edge
		var post := best.global_transform * Vector3(wdt * 0.4, 0, 0.06)
		var travel := best.global_transform.basis.z
		travel.y = 0.0
		travel = travel.normalized()
		var road_dir := best.global_transform.basis.x
		road_dir.y = 0.0
		road_dir = road_dir.normalized()
		var target := post + Vector3.UP * 0.7
		var start := target - travel * 24.0 + road_dir * 3.0
		var text := ""
		for k in best.get_children():
			if k is Label3D:
				text = (k as Label3D).text
		_log("sign '%s' at %s (%.0f m from %s), inner post %s, clearance %.2f m" % [text, str(best.global_position.round()), bd, str(c), str(post.round()), net.edge_clearance(post)])
		var r := await _drive_at(start, target, 45.0, 10.0, 2.5)
		await _views("sign_post_%d_%d" % [int(c.x), int(c.y)], _car().global_position, road_dir)
		_check("s9 a car driving into the sign post at %s stops" % str(post.round()), not r["passed"] and r["stopped"],
			"vmax %.0f km/h, hit at %.0f km/h, peak decel %.0f m/s2, touching [%s], impacts %s" % [r["vmax"], r["v_hit"], r["decel"], _touching(), str(r["imp"])])
		await _brake_stop()


# ------------------------------------------------------------------ s5 lamps at night

func _lamps() -> void:
	Game.set_time_of_day(22.5)
	var pool: Object = Game.env.get("lamps")
	await _wait(1.0)
	var pos: PackedVector3Array = pool.get("_pos")
	var heads: Array = st.get("lamp_heads")
	_log("lamp pool %d points, settlements registered %d extra lamp heads" % [pos.size(), heads.size()])
	for case: Array in [["Mesa Fuel", "Gas_Station"], ["Coast Fuel", "Gas_Station"], ["Crossroads Diner", "Diner"], ["Seabreak Diner", "Diner"]]:
		var tgt := {}
		for d: Dictionary in Game.get_teleport_targets():
			if String(d["name"]) == case[0]:
				tgt = d
		if tgt.is_empty():
			continue
		var bi := _find(case[1], Vector2((tgt["position"] as Vector3).x, (tgt["position"] as Vector3).z), 400.0)
		if bi < 0:
			continue
		var bo: Vector3 = (_items()[bi]["xf"] as Transform3D).origin
		var lamps := 0
		var lit_points := 0
		var lamp_pos: Array[Vector3] = []
		for it: Dictionary in _items():
			if it["name"] != "Lamp_Street":
				continue
			var lo: Vector3 = (it["xf"] as Transform3D).origin
			if lo.distance_to(bo) > 40.0:
				continue
			lamps += 1
			lamp_pos.append(lo)
			var head: Vector3 = (it["xf"] as Transform3D) * Vector3(0, 5.9, -1.75)
			for p in pos:
				if p.distance_to(head) < 0.6:
					lit_points += 1
					break
		if lamps == 0:
			_log("SKIP s5 %s: no Lamp_Street post was placed there" % case[0])
			continue
		var view := lamp_pos[0]
		var away := Vector3(bo.x - view.x, 0, bo.z - view.z)
		var eye := view - away.normalized() * 10.0 + Vector3.UP * 3.0 if away.length() > 0.5 else view + Vector3(8, 3, 8)
		await _free_view("night_%s" % String(case[0]).replace(" ", "_").to_lower(), eye, bo + Vector3.UP * 2.0)
		var active := 0
		for l in (pool as Node).get_children():
			var ol := l as OmniLight3D
			if ol != null and ol.visible and ol.light_energy > 0.2:
				for lp in lamp_pos:
					if Vector2(ol.global_position.x - lp.x, ol.global_position.z - lp.z).length() < 3.0:
						active += 1
						break
		_check("s5 %s lamp posts are lit at 22:30" % case[0], lamps > 0 and lit_points == lamps and active >= mini(lamps, 1),
			"%d Lamp_Street within 40 m, %d with a lamp-pool light point at the head, %d OmniLights on near them" % [lamps, lit_points, active])
	Game.set_time_of_day(13.0)
	await _wait(0.5)


# ------------------------------------------------------------------ screenshots

func _shots() -> void:
	Game.set_time_of_day(13.0)
	var views: Array = []
	var arr := _items()
	var lake_pier := _find("Pier_Section", Vector2(70, -600), 80.0)
	if lake_pier >= 0:
		var o: Vector3 = (arr[lake_pier]["xf"] as Transform3D).origin
		var rot := (arr[lake_pier]["xf"] as Transform3D).basis.orthonormalized()
		views.append(["mirror_jetty_side_low", o + rot.x * 14.0 + Vector3.UP * 1.6, o])
		views.append(["mirror_jetty_from_shore", o - rot.z * 22.0 + Vector3.UP * 3.0 + rot.x * 4.0, o + rot.z * 8.0])
	var mb := _find("Boathouse", Vector2(82, -616), 120.0)
	if mb >= 0:
		var o2: Vector3 = (arr[mb]["xf"] as Transform3D).origin
		var r2 := (arr[mb]["xf"] as Transform3D).basis.orthonormalized()
		views.append(["mirror_boathouse_side", o2 + r2.x * 16.0 + Vector3.UP * 2.0, o2])
	var gp := _find("Pier_Section", Vector2(1086, 1460), 80.0)
	if gp >= 0:
		var o3: Vector3 = (arr[gp]["xf"] as Transform3D).origin
		var r3 := (arr[gp]["xf"] as Transform3D).basis.orthonormalized()
		views.append(["gull_pier_side_low", o3 + r3.x * 16.0 + Vector3.UP * 1.5, o3])
		views.append(["gull_pier_from_beach", o3 - r3.z * 20.0 + Vector3.UP * 4.0 + r3.x * 3.0, o3 + r3.z * 6.0])
	var gb := _find("Boathouse", Vector2(1119, 1445), 150.0)
	if gb >= 0:
		var o4: Vector3 = (arr[gb]["xf"] as Transform3D).origin
		var r4 := (arr[gb]["xf"] as Transform3D).basis.orthonormalized()
		views.append(["gull_boathouse_side", o4 + r4.x * 16.0 + Vector3.UP * 2.0, o4])
		views.append(["gull_boathouse_back", o4 - r4.z * 18.0 + Vector3.UP * 3.0, o4])
	var hs := _find("Harbour_Shed", Vector2(1060, 1400), 200.0)
	if hs >= 0:
		var o5: Vector3 = (arr[hs]["xf"] as Transform3D).origin
		var r5 := (arr[hs]["xf"] as Transform3D).basis.orthonormalized()
		views.append(["gull_shed_from_road", o5 - r5.z * 34.0 + r5.x * 6.0 + Vector3.UP * 6.0, o5 + Vector3.UP * 3.0])
		views.append(["gull_shed_top", o5 + Vector3(0, 70, 0) - r5.z * 40.0, o5])
	for c: Array in [["House_Chalet", Vector2(-1464, -1320)], ["House_Chalet", Vector2(-1578, -1267)], ["House_Townhouse", Vector2(-1177, 633)],
			["House_Cottage_A", Vector2(960, 1386)], ["House_Cottage_A", Vector2(1193, 1313)], ["Farmhouse", Vector2(-1508, 549)], ["Church", Vector2(-1212, 618)]]:
		var hi := _find(c[0], c[1], 90.0)
		if hi < 0:
			continue
		var o6: Vector3 = (arr[hi]["xf"] as Transform3D).origin
		var r6 := (arr[hi]["xf"] as Transform3D).basis.orthonormalized()
		var bb := PropLibrary.aabb(c[0])
		views.append(["house_%s_%d_%d_front" % [String(c[0]).to_lower(), int(o6.x), int(o6.z)], o6 - r6.z * (bb.size.z * 0.5 + 12.0) + Vector3.UP * 1.7, o6 + Vector3.UP * 1.5])
		views.append(["house_%s_%d_%d_side" % [String(c[0]).to_lower(), int(o6.x), int(o6.z)], o6 + r6.x * (bb.size.x * 0.5 + 12.0) + Vector3.UP * 1.7, o6 + Vector3.UP * 1.5])
	for i in arr.size():
		if arr[i]["name"] == "Gas_Station":
			var o7: Vector3 = (arr[i]["xf"] as Transform3D).origin
			var r7 := (arr[i]["xf"] as Transform3D).basis.orthonormalized()
			views.append(["fuel_%d_%d_from_road" % [int(o7.x), int(o7.z)], o7 - r7.z * 30.0 + r7.x * 12.0 + Vector3.UP * 2.5, o7 - r7.z * 6.0])
			views.append(["fuel_%d_%d_side_low" % [int(o7.x), int(o7.z)], o7 + r7.x * 24.0 - r7.z * 6.0 + Vector3.UP * 1.2, o7 - r7.z * 6.0])
	var keep := _find("Castle_Ruin_Tower", Vector2(-1850, -1500), 100.0)
	if keep >= 0:
		var o8: Vector3 = (arr[keep]["xf"] as Transform3D).origin
		views.append(["keep_aerial", o8 + Vector3(30, 45, 30), o8])
	for v: Array in views:
		await _free_view(v[0], v[1], v[2])
