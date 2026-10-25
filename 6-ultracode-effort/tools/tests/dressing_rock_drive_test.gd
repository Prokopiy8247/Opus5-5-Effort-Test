extends Node
## Rock / cactus collision regression test (playtest-3 s7 / s8 / s15) in the real game. Near each reported spot
## it finds the nearest rock or cactus (>= 0.8 m tall) in the game's own dressing data (Rules.build_chunk),
## places the car 38 m away on the flattest clear approach and drives into it with real input (accelerate held,
## steering at the prop centre until the last 4 m). Logs speed, impacts, lift above the ground near the prop and
## the physics steps in which the car centre or nose was inside the visible mesh; screenshots after the hit.
## Prints ROCKS_OK when every car that reached its prop was stopped by it and never entered the mesh.
## -- --spots="x,z,Name;..." (default: report spots)  --speed=65  --shot-dir=res://qa_output/dressing/rocks

const Rules := preload("res://scripts/world/dressing_rules.gd")
const PropLibrary := preload("res://scripts/world/prop_library.gd")

const SPOTS := ["-543,-906,Rock_C", "-1638,-507,Rock_A", "411,-1019,Cactus_B", "-1731,-1606,Rock_Large", "373,-1060,Rock_Red",
	"427,-997,Rock_Red", "-1663,-916,Rock_B", "-1332,-869,Rock_B", "-1611,-953,Rock_B", "1037,-330,Rock_Red", "-170,-757,Rock_B",
	"411,-1019,Cactus_A"]

var out_dir := "res://qa_output/dressing/rocks"
var dn: Node
var car: CarController
var impacts: Array = []


func _ready() -> void:
	out_dir = QaDirector._arg("shot-dir", out_dir)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	add_child((load("res://scenes/main.tscn") as PackedScene).instantiate())
	_run.call_deferred()


func _wait(s: float) -> void:
	await get_tree().create_timer(s, true, false, true).timeout


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out_dir.path_join(name + ".png"))


func _on_impact(strength: float, at: Vector3) -> void:
	impacts.append([strength, at])


## [name, Transform3D world, top above ground] of the rocks / cacti near (x, z).
func _props_near(x: float, z: float, r: float) -> Array:
	var res: Array = []
	var ctx: Rules.Ctx = dn.get("ctx")
	var w := Game.world as World
	var k0 := Vector2i(floori((x - r + Rules.HALF) / Rules.CHUNK), floori((z - r + Rules.HALF) / Rules.CHUNK))
	var k1 := Vector2i(floori((x + r + Rules.HALF) / Rules.CHUNK), floori((z + r + Rules.HALF) / Rules.CHUNK))
	for kj in range(k0.y, k1.y + 1):
		for ki in range(k0.x, k1.x + 1):
			var key := Vector2i(ki, kj)
			var org := Vector3(-Rules.HALF + ki * Rules.CHUNK, 0.0, -Rules.HALF + kj * Rules.CHUNK)
			var groups: Dictionary = Rules.build_chunk(ctx, key)["groups"]
			for gk: String in groups:
				var nm := gk.get_slice("|", 1)
				if not (nm.begins_with("Rock_") or nm.begins_with("Cactus_") or nm.begins_with("Tree_")) or gk.begins_with("far"):
					continue
				var buf: PackedFloat32Array = groups[gk]
				for o in range(0, buf.size(), Rules.STRIDE):
					var xf := Transform3D(Basis(Vector3(buf[o], buf[o + 4], buf[o + 8]), Vector3(buf[o + 1], buf[o + 5], buf[o + 9]),
						Vector3(buf[o + 2], buf[o + 6], buf[o + 10])), org + Vector3(buf[o + 3], buf[o + 7], buf[o + 11]))
					if Vector2(xf.origin.x - x, xf.origin.z - z).length() > r:
						continue
					var top := INF
					if not nm.begins_with("Tree_"):
						top = -INF
						for v: Vector3 in PropLibrary.mesh(nm).get_faces():
							top = maxf(top, (xf * v).y)
					res.append([nm, xf, top - w.height_at(xf.origin.x, xf.origin.z)])
	return res


func _run() -> void:
	SaveGame.enabled = false
	while Game.main == null or Game.main.is_loading:
		await get_tree().process_frame
	dn = Game.get_meta(&"dressing", null)
	while not bool(dn.get("_started")):
		await get_tree().process_frame
	Game.set_time_of_day(12.5)
	if Game.traffic != null:
		Game.traffic.set_density(0.0)
	car = Game.player_car
	var speed := QaDirector._arg("speed", "65").to_float()
	var spots: Array = SPOTS
	var arg := QaDirector._arg("spots", "")
	if arg != "":
		spots = arg.split(";")
	var w := Game.world as World
	var n := 0
	var fit_worst := 0.0
	var reached := 0
	var bad := 0
	for spec: String in spots:
		var parts := spec.split(",")
		var sx := parts[0].to_float()
		var sz := parts[1].to_float()
		var want := parts[2] if parts.size() > 2 else ""
		var all := _props_near(sx, sz, 70.0)
		# target: nearest prop of the wanted kind that a car can hit, else the nearest rock / cactus >= 0.8 m
		var best: Array = []
		var bd := INF
		for it: Array in all:
			var nm: String = it[0]
			if nm.begins_with("Tree_") or float(it[2]) < 0.8:
				continue
			var d := Vector2((it[1] as Transform3D).origin.x - sx, (it[1] as Transform3D).origin.z - sz).length() + (0.0 if want == "" or nm == want else 40.0)
			if d < bd:
				bd = d
				best = it
		if best.is_empty():
			print("[rockdrive] %s: no rock near" % spec)
			continue
		var rxf: Transform3D = best[1]
		var rp := rxf.origin
		var foot := 0.0
		for v: Vector3 in PropLibrary.mesh(best[0]).get_faces():
			var wv := rxf.basis * v
			if rxf.origin.y + wv.y > w.height_at(rp.x, rp.z) + 0.3:
				foot = maxf(foot, Vector2(wv.x, wv.z).length())
		# approach: the clear direction (no other prop within 2.5 m of the path) with the smallest grade change
		var dir := Vector3.ZERO
		var best_cost := INF
		for k in 16:
			var a := TAU * k / 16.0
			var dv := Vector3(cos(a), 0.0, sin(a))
			var clear := true
			for it: Array in all:
				if it == best:
					continue
				var o: Vector3 = (it[1] as Transform3D).origin
				var rel := o - rp
				var along := -rel.dot(dv)
				if along > -1.0 and along < 42.0 and (rel + dv * along).length() < 2.5 + (0.0 if String(it[0]).begins_with("Tree_") else 1.0):
					clear = false
					break
			if not clear:
				continue
			var cost := 0.0
			var prev := w.height_at(rp.x - dv.x * 40.0, rp.z - dv.z * 40.0)
			for s in range(1, 9):
				var p := rp - dv * (40.0 - s * 5.0)
				var h := w.height_at(p.x, p.z)
				cost += absf(h - prev)
				prev = h
			if Rules.road_dist(dn.get("ctx"), rp.x - dv.x * 38.0, rp.z - dv.z * 38.0) < 3.0:
				cost += 0.5
			if cost < best_cost:
				best_cost = cost
				dir = dv
		if dir == Vector3.ZERO:
			print("[rockdrive] %s: no clear approach to %s" % [spec, best[0]])
			continue
		n += 1
		var start := rp - dir * 38.0
		Game.main.teleport_to(w.nearest_road_point(start))
		await _wait(0.3)
		w.extra_physics_points.clear()
		w.refocus(start)
		var t := 0.0
		while w.terrain.pending_count() > 0 and t < 10.0:
			await get_tree().process_frame
			t += get_process_delta_time()
		start.y = w.height_at(start.x, start.z) + 0.5
		# collider fit: horizontal rays at 0.3 / 0.8 / 1.5 m above the ground from 8 directions, physics hit vs mesh hit
		car.place_at(Transform3D(Basis.looking_at(dir, Vector3.UP), start))
		await get_tree().create_timer(0.6, true, false, true).timeout
		var fit := _fit(best[0], rxf)
		fit_worst = maxf(fit_worst, fit.y)
		car.place_at(Transform3D(Basis.looking_at(dir, Vector3.UP), start), dir * speed / 3.6)
		Game.main.car_input.enabled = true
		Game.camera_rig.active = true
		impacts.clear()
		if not car.impact.is_connected(_on_impact):
			car.impact.connect(_on_impact)
		Input.action_press("accelerate")
		var v0 := 0.0
		var max_vy := 0.0
		var min_d := INF
		var t2 := 0.0
		var shot_done := false
		var v_at_contact := -1.0
		var hit_t := 0.0
		var d_rock := 0.0
		var rest_lift := 0.0
		var inside_c := 0
		var inside_n := 0
		var faces := PropLibrary.mesh(best[0]).get_faces()
		var inv := rxf.affine_inverse()
		while t2 < 5.0:
			await get_tree().physics_frame
			t2 += 1.0 / 120.0
			var cp := car.global_position
			var to := Vector3(rp.x - cp.x, 0.0, rp.z - cp.z)
			d_rock = to.length()
			min_d = minf(min_d, d_rock)
			if t2 < 0.3:
				v0 = car.get_speed_kmh()
			var lift := cp.y - w.height_at(cp.x, cp.z)
			if t2 < 0.4:
				rest_lift = lift
			if d_rock < foot + 3.0:
				max_vy = maxf(max_vy, lift - rest_lift)
			# visual drive-through: the car centre (0.6 m up) or its nose inside the prop mesh
			var cxf := car.global_transform
			if _inside(faces, inv * (cxf * Vector3(0, 0.6, 0))):
				inside_c += 1
			if _inside(faces, inv * (cxf * Vector3(0, 0.5, -1.9))):
				inside_n += 1
			if v_at_contact < 0.0 and not impacts.is_empty():
				v_at_contact = car.get_speed_kmh()
				hit_t = t2
			# steer at the prop centre, straight for the last 4 m
			var fwd := -car.global_transform.basis.z
			var side := fwd.cross(Vector3.UP).dot(to.normalized())
			Input.action_release("steer_left")
			Input.action_release("steer_right")
			if d_rock > 4.0 + foot:
				if side > 0.03:
					Input.action_press("steer_right", clampf(side * 3.0, 0.0, 1.0))
				elif side < -0.03:
					Input.action_press("steer_left", clampf(-side * 3.0, 0.0, 1.0))
			if not shot_done and ((not impacts.is_empty() and (car.get_speed_kmh() < 4.0 or t2 > hit_t + 0.35)) or d_rock < foot + 0.5):
				shot_done = true
				get_tree().paused = true
				await _shot("%02d_%s_a_chase" % [n, best[0]])
				var cam: Camera3D = Game.camera_rig.camera
				Game.camera_rig.active = false
				var sv := fwd.cross(Vector3.UP).normalized()
				cam.global_position = cp + sv * 9.0 + Vector3.UP * 3.0
				cam.look_at(cp.lerp(rp, 0.5) + Vector3.UP * 1.0, Vector3.UP)
				await _shot("%02d_%s_b_side" % [n, best[0]])
				Game.camera_rig.active = true
				get_tree().paused = false
			# done once stopped or well past the prop
			var past := (Vector3(cp.x, 0, cp.z) - Vector3(rp.x, 0, rp.z)).dot(dir)
			if past > foot + 6.0 or (t2 > 1.0 and car.get_speed_kmh() < 2.0):
				break
		Input.action_release("accelerate")
		Input.action_release("steer_left")
		Input.action_release("steer_right")
		var cp2 := car.global_position
		var past2 := (Vector3(cp2.x, 0, cp2.z) - Vector3(rp.x, 0, rp.z)).dot(dir)
		print("[rockdrive]    collider fit: %d rays, mean |physics - mesh| %.2f m, deepest the visible surface lies outside the collider %.2f m" % [int(fit.z), fit.x, fit.y])
		var max_imp := 0.0
		for im: Array in impacts:
			max_imp = maxf(max_imp, float(im[0]))
		var through := inside_c > 0
		var hit := max_imp > 2.0 and min_d < foot + 3.5
		if hit or through:
			reached += 1
		if through or (min_d < foot + 1.0 and not hit):
			bad += 1
		print("[rockdrive] %02d %s %.1f m tall foot %.1f m at (%.0f, %.1f, %.0f) from %s: v0 %.0f km/h, impacts %d max %.1f, v at hit %.0f, end %.0f km/h, centre min %.1f m / end %.1f m past centre, max lift above the ground near the prop %.2f m, steps with car centre / nose inside the mesh %d / %d -> %s" % [
			n, best[0], best[2], foot, rp.x, rp.y, rp.z, spec, v0, impacts.size(), max_imp, v_at_contact, car.get_speed_kmh(), min_d, past2, max_vy,
			inside_c, inside_n, "THROUGH" if through else ("STOPPED" if max_imp > 2.0 and min_d < foot + 3.5 else "MISSED")])
		await _wait(0.2)
	print("[rockdrive] %d props reached of %d, %d driven into or through" % [reached, n, bad])
	print("[rockdrive] worst collider fit: visible surface %.2f m outside the collider" % fit_worst)
	var ok := bad == 0 and reached >= maxi(n - 3, 1) and fit_worst < 0.35
	print("ROCKS_OK" if ok else "ROCKS_FAIL %d of %d" % [bad, reached])
	get_tree().quit(0 if ok else 1)


## (mean |physics hit - mesh hit|, max (physics hit distance - mesh hit distance), rays) for horizontal rays aimed
## at the prop centre from 8 directions at 0.3 / 0.8 / 1.5 m above the ground (barrier layer, pooled hulls).
func _fit(nm: String, xf: Transform3D) -> Vector3:
	var faces := PropLibrary.mesh(nm).get_faces()
	var w := Game.world as World
	var space := get_viewport().get_world_3d().direct_space_state
	var g := w.height_at(xf.origin.x, xf.origin.z)
	var sum := 0.0
	var worst := 0.0
	var n := 0
	for k in 8:
		var a := TAU * k / 8.0
		var d := Vector3(cos(a), 0.0, sin(a))
		for hgt: float in [0.3, 0.8, 1.5]:
			var target := Vector3(xf.origin.x, g + hgt, xf.origin.z)
			var from := target - d * 12.0
			var dm := _ray_mesh(faces, xf, from, d)
			if dm == INF:
				continue
			var q := PhysicsRayQueryParameters3D.create(from, target + d * 0.01, 32)
			var hit := space.intersect_ray(q)
			var dp := (from.distance_to(hit["position"]) if not hit.is_empty() else 12.0)
			sum += absf(dp - dm)
			worst = maxf(worst, dp - dm)
			n += 1
	return Vector3(sum / maxi(n, 1), worst, n)


func _ray_mesh(f: PackedVector3Array, xf: Transform3D, from: Vector3, dir: Vector3) -> float:
	var best := INF
	for i in range(0, f.size(), 3):
		var hit: Variant = Geometry3D.ray_intersects_triangle(from, dir, xf * f[i], xf * f[i + 1], xf * f[i + 2])
		if hit != null:
			best = minf(best, from.distance_to(hit))
	return best


## Ray-parity point-in-mesh test (local space).
func _inside(f: PackedVector3Array, p: Vector3) -> bool:
	var hits := 0
	var dir := Vector3(1.0, 0.0013, 0.0007)
	for i in range(0, f.size(), 3):
		var e1 := f[i + 1] - f[i]
		var e2 := f[i + 2] - f[i]
		var pv := dir.cross(e2)
		var det := e1.dot(pv)
		if absf(det) < 1e-9:
			continue
		var tv := p - f[i]
		var u := tv.dot(pv) / det
		if u < 0.0 or u > 1.0:
			continue
		var qv := tv.cross(e1)
		var v := dir.dot(qv) / det
		if v < 0.0 or u + v > 1.0:
			continue
		if e2.dot(qv) / det > 0.0:
			hits += 1
	return hits % 2 == 1
