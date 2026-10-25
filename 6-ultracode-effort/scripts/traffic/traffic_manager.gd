extends Node3D
## Civilian traffic (Game.traffic). Builds the lane graph, spawns/despawns pooled vehicles around the
## player outside the camera view, and runs them in two simulation LODs: physics CarControllers driven by
## RoadFollower within ~150 m (the nearest 12), kinematic lane-following visuals out to ~700 m (with a box
## collider within 175 m, so a car without a physics slot is still solid). Vehicles keep a time gap,
## slow for curves, give way at junctions, change lanes to overtake on multi-lane roads, react to crashes
## (hazard lights, recover or despawn) and honk/flash at a player who blocks them. Activity AI cars
## (Game.activities.get_ai_cars(), e.g. race rivals) are obstacles like the player.
## API: set_density(v), get_density(), set_density_cap(v), active_count(), get_stats(), stats, obstacles_near(pos, radius).

const LaneGraph := preload("res://scripts/traffic/lane_graph.gd")
const TrafficVehicle := preload("res://scripts/traffic/traffic_vehicle.gd")
const AUDIO_SCRIPT := "res://scripts/audio/car_audio.gd"
const EFFECTS_SCRIPT := "res://scripts/vehicle/car_effects.gd"
const TYPE_IDS: Array[String] = ["hatch_small", "van_delivery", "lorry_box", "bus_coach", "tractor_farm", "pickup_work"]

const PHYSICS_IN := 150.0
const PHYSICS_OUT := 175.0
## A full physics budget hands the farthest car's slot to a kinematic one at least this much nearer.
const SWAP_MARGIN := 40.0
const MAX_SWAPS := 2
## Kinematic vehicles this close to the player carry a box collider (no physics slot, still solid).
const KIN_SOLID_DIST := 175.0
## Kinematic vehicles this close to the player also brake for it (and for crashed cars).
const KIN_PROBE_DIST := 260.0
## Parked cars keep this much room to the widest vehicle allowed in the lane beside them.
const PARK_CLEARANCE := 0.3
## Traffic switches its lights on this far before a tunnel.
const TUNNEL_LIGHTS_AHEAD := 25.0
const SPAWN_MIN := 250.0
const SPAWN_MAX := 650.0
const SPAWN_FAR_VISIBLE := 520.0
const DESPAWN := 750.0
## Unseen vehicles this far behind a moving player that do not catch up are recycled to spawn ahead.
const RECYCLE_DIST := 300.0
const MAX_PHYSICS := 12
const MAX_VEHICLES := 34
const MAX_PER_KM := 9.0
const MAX_POOLED_VISUALS := 10
const MAX_POOLED_CARS := 4
const BASE_COUNT := 30.0
const TURN_CHANCE := 0.22
const B_COMFORT := 2.6
const B_MAX := 6.5
const JUNCTION_CLEAR := 50.0
const REGION_FACTOR: Array[float] = [1.0, 0.6, 0.55, 0.85]
const NIGHT_FACTOR := 0.45
const STRONG_IMPACT := 2.4
## Horizontal velocity change (m/s, ~0.25 s window) that counts as a crash when another car is close.
const JOLT_CRASH := 4.0
## Hits up to these (jolt m/s, impact strength) on a car that stays straight in its lane are shunts, not crashes.
const SHUNT_DV := 7.0
const SHUNT_IMPACT := 6.0
## Physics cars farther than this from the player register terrain-collider points (the streamer already
## keeps colliders ~230 m around the player).
const PHYSICS_POINT_MIN := 190.0
## Kinematic vehicles farther than this update at half rate.
const HALF_RATE_DIST := 350.0
const PARKED_IN := 350.0
const PARKED_OUT := 420.0
## An oncoming race rival over the centre line: traffic edges over toward the verge (this far from the paved edge)
## and squeezes past it at walking pace (faster with more room) instead of standing nose to nose with it.
const VERGE_MARGIN := 0.25
const SQUEEZE_SPEED := 2.5
const AI_WAIT_GAP := 6.0
## Traffic headlight pools fade in / out with camera distance, so the switch between the far model (lenses only)
## and the physics car (real lights) at PHYSICS_IN / PHYSICS_OUT shows no pop.
const LIGHT_FADE_BEGIN := 95.0
const LIGHT_FADE_LENGTH := 45.0
const PARKED_POI_KINDS: Array[String] = ["village", "harbour", "hamlet"]
const PARKED_TYPES: Array[String] = ["hatch_small", "van_delivery", "pickup_work"]

var graph: LaneGraph
var types: Array[Resource] = []
var vehicles: Array = []
var stats: Dictionary = {}
var debug: bool = false
var enabled: bool = true

var _density: float = 0.6
var _density_cap: float = 1.0
var _target: int = 0
var _road_km: float = 0.0
var _rng := RandomNumberGenerator.new()
var _models: Array[Dictionary] = []
var _visual_pool: Array = []
var _car_pool: Array = []
var _visual_root: Node3D
var _car_root: Node3D
var _occ_lane: Dictionary = {}
var _occ_conn: Dictionary = {}
var _busy_conns: Array = []
var _empty: Array = []
var _stats_timer: float = 0.0
var _prof := {"frames": 0, "pre": 0, "plan": 0, "move": 0, "rest": 0}
var _phys_points: Array[Vector3] = []
var _player_pos := Vector3.INF
var _player_vel := Vector3.ZERO
## CarControllers; untyped so a rival freed mid-frame can be skipped with is_instance_valid().
var _ai_cars: Array = []
var _cam_fwd := Vector3.FORWARD
var _fill: float = 0.0
var _spawn_cells: Array = []
var _spawn_cells_fill: Array = []
## Time until the next recycle of a vehicle left behind a moving player.
var _recycle_t: float = 0.0
var _lod_timer: float = 0.0
var _target_timer: float = 0.0
var _debug_timer: float = 0.0
var _uid: int = 0
var _frame: int = 0
var _night: bool = false
## Vehicles run their lights (environment's lights_needed(): dusk, night, fog / rain / storm).
var _lights: bool = false
var _cam_tunnel_hold: float = 0.0
var _by_uid: Dictionary = {}
## Vehicle uid _find_leader skips (breaking a ring of vehicles waiting on each other).
var _ignore_uid: int = -1
## Verge nudge the current _find_leader asks for (see _probe).
var _nudge_want: float = 0.0
var _body_root: Node3D
var _body_pool: Array[AnimatableBody3D] = []
var _horns: Array[AudioStreamPlayer3D] = []
var _horn_streams: Dictionary = {}
var _car_owner: Dictionary = {}
var _audio_script: Script
## Per type index: lane pieces (LaneGraph.piece_key) from which that type can drive on for good on roads it is
## allowed on (class, and region all along the way). Spawns, turns and lane changes keep to these.
var _safe: Array[Dictionary] = []
var _kits: Dictionary = {}
var _parked: Array[Dictionary] = []
var _parked_bodies: Array[StaticBody3D] = []
var _parked_timer: float = 0.0
var _promo_shape := BoxShape3D.new()
var _promo_query := PhysicsShapeQueryParameters3D.new()
var _counters := {"spawned": 0, "despawned": 0, "promotions": 0, "demotions": 0, "yield_waits": 0,
	"give_way_entries": 0, "lane_changes": 0, "honks": 0, "hazards": 0, "recovered": 0, "wrecks_removed": 0,
	"skipped_no_ground": 0, "promotion_blocked": 0, "slot_swaps": 0, "lead_cycle_ticks": 0, "shunts": 0, "recycled": 0, "made_way": 0}


func _ready() -> void:
	_rng.randomize()
	debug = OS.get_cmdline_user_args().has("--traffic-debug")
	_density = clampf(float(Settings.get_value("traffic_density", 0.6)), 0.0, 1.0)
	# Vehicle lamps follow time of day / weather: photo mode runs this node for a few frames while paused
	# (see _process). The children stay pausable, so nothing else wakes up with it.
	add_to_group(&"sunward_time_reactive")
	_visual_root = Node3D.new()
	_visual_root.name = "Visuals"
	_visual_root.process_mode = Node.PROCESS_MODE_DISABLED
	_visual_root.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(_visual_root)
	_car_root = Node3D.new()
	_car_root.name = "Cars"
	_car_root.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(_car_root)
	_body_root = Node3D.new()
	_body_root.name = "KinematicBodies"
	_body_root.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(_body_root)
	for i in 3:
		var h := AudioStreamPlayer3D.new()
		h.process_mode = Node.PROCESS_MODE_PAUSABLE
		h.name = "Horn%d" % i
		h.unit_size = 14.0
		h.max_distance = 160.0
		h.volume_db = -3.0
		h.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		add_child(h)
		_horns.append(h)
	var w := Game.world as World
	if w == null or w.data == null:
		enabled = false
		push_warning("[traffic] no open world - traffic disabled")
		return
	_load_types()
	if types.is_empty():
		enabled = false
		push_warning("[traffic] no vehicle types in res://data/traffic - traffic disabled")
		return
	var t0 := Time.get_ticks_msec()
	graph = LaneGraph.new()
	graph.build(w.data.network)
	print("[traffic] lane graph: %d lanes, %d connectors, %d junctions (%d ms)" % [graph.lanes.size(), graph.connectors.size(), graph.junctions.size(), Time.get_ticks_msec() - t0])
	_build_safe_pieces(w)
	# Far-LOD meshes are merged once per model while the loading screen is up.
	t0 = Time.get_ticks_msec()
	for ti in types.size():
		_visual_kit(ti)
	print("[traffic] %d far-LOD vehicle meshes ready (%d ms)" % [_kits.size(), Time.get_ticks_msec() - t0])
	_plan_parked(w)
	_update_stats(0.0)


func _exit_tree() -> void:
	for v: TrafficVehicle in vehicles:
		v.follower = null
	vehicles.clear()
	_occ_lane.clear()
	_occ_conn.clear()
	_car_owner.clear()
	for pool: Array in _car_pool:
		for car: CarController in pool:
			if is_instance_valid(car) and not car.is_inside_tree():
				car.free()
		pool.clear()
	for b in _body_pool:
		if is_instance_valid(b) and not b.is_inside_tree():
			b.free()
	_body_pool.clear()
	_by_uid.clear()
	if graph != null:
		graph.clear()


# ----------------------------------------------------------------- public API

## The user's density setting (Game.set_traffic_density).
func set_density(v: float) -> void:
	_density = clampf(v, 0.0, 1.0)
	_density_changed()


func get_density() -> float:
	return _density


## Temporary upper limit (e.g. while a race runs) that leaves the user's setting untouched; 1.0 lifts it.
func set_density_cap(v: float) -> void:
	_density_cap = clampf(v, 0.0, 1.0)
	_density_changed()


## Density traffic actually spawns at: the setting limited by the cap.
func effective_density() -> float:
	return minf(_density, _density_cap)


func _density_changed() -> void:
	_target_timer = 0.0
	if effective_density() <= 0.0:
		_flush_all()


func active_count() -> int:
	return vehicles.size()


func get_stats() -> Dictionary:
	return stats.duplicate(true)


## Traffic vehicles within `radius` of pos: [{position, heading, speed, length, width}] (QA autopilot, activities).
func obstacles_near(pos: Vector3, radius: float) -> Array:
	var out: Array = []
	var r2 := radius * radius
	for v: TrafficVehicle in vehicles:
		if v.position.distance_squared_to(pos) < r2:
			out.append({"position": v.position, "heading": v.heading, "speed": v.speed, "length": v.length, "width": v.half_width * 2.0})
	return out


## Respawn / teleport placement (main._clear_of_traffic): metres to spare for a car standing still at pos facing
## `forward`; negative when a vehicle is on the spot or (with `approach`) one on its way to it could not stop in
## time (1 s to react, then ~3 m/s² like RoadFollower.follow_speed, stopping a few metres short).
func spot_margin(pos: Vector3, forward: Vector3, approach := true) -> float:
	var worst := INF
	for v: TrafficVehicle in vehicles:
		worst = minf(worst, _spot_threat(v, pos, forward, approach))
	return worst


## Last resort when no spot near a respawn is safe: vehicles that would run into a car standing at pos are
## removed (they are behind it, out of the chase camera's view). Returns how many.
func make_way(pos: Vector3, forward: Vector3) -> int:
	var n := 0
	for i in range(vehicles.size() - 1, -1, -1):
		if _spot_threat(vehicles[i], pos, forward) < 0.0:
			_despawn(vehicles[i], i)
			n += 1
	_counters["made_way"] += n
	return n


func _spot_threat(v: TrafficVehicle, pos: Vector3, forward: Vector3, approach := true) -> float:
	var rel := Vector2(pos.x - v.position.x, pos.z - v.position.z)
	var d := rel.length()
	if d > 260.0:
		return INF
	var m := d - (v.length * 0.5 + 3.0)
	if not approach:
		return m
	# On its way to the spot: its planned path (lane, turn) passes the spot in the same direction.
	var q := v.path_point(d)
	var tq := v.path_point(d + 2.0) - q
	var f2 := Vector2(forward.x, forward.z).normalized()
	if Vector2(q.x - pos.x, q.z - pos.z).length() < 2.6 and Vector2(tq.x, tq.z).normalized().dot(f2) > 0.5 and rel.dot(Vector2(v.heading.x, v.heading.z)) > 0.0:
		m = minf(m, d - (v.speed * v.speed / 6.0 + v.speed + v.length * 0.5 + 6.5))
	return m


# ----------------------------------------------------------------- types / models / pools

func _load_types() -> void:
	for id in TYPE_IDS:
		var path := "res://data/traffic/%s.tres" % id
		if not ResourceLoader.exists(path):
			continue
		var d: Resource = load(path)
		if d == null:
			continue
		types.append(d)
		_models.append(_resolve_model(d))
		_visual_pool.append([])
		_car_pool.append([])


## Per type: lane pieces it may drive and that keep a way on it may take (greatest fixed point: a piece stays
## safe while one of its exits leads to a safe piece). A tractor is then never spawned where its only way out is
## the expressway, and leaves a loop road before it runs out of its region.
func _build_safe_pieces(w: World) -> void:
	var pcs := graph.pieces()
	var masks := {}
	for pc: Dictionary in pcs:
		var l: LaneGraph.Lane = pc["lane"]
		var s0: float = pc["s0"]
		var span := l.ahead(s0, pc["s1"])
		if l.road.loop and span <= 0.0:
			span = l.road.length
		var n := maxi(int(span / 20.0), 1)
		var mask := 0
		for i in n + 1:
			var p := l.point(l.advance(s0, span * i / n), l.offset)
			mask |= 1 << w.data.region_at(p.x, p.z)
		masks[pc["key"]] = mask
	_safe.clear()
	var report: PackedStringArray = []
	for ti in types.size():
		var t := types[ti]
		var allowed := 0
		for rg: int in t.allowed_regions:
			allowed |= 1 << rg
		var safe := {}
		for pc2: Dictionary in pcs:
			var cls: int = (pc2["lane"] as LaneGraph.Lane).road.cls
			var m: int = masks[pc2["key"]]
			if t.allowed_classes.has(cls) and (t.allowed_regions.is_empty() or m & ~allowed == 0):
				safe[pc2["key"]] = true
		var changed := true
		while changed:
			changed = false
			for pc3: Dictionary in pcs:
				if not safe.has(pc3["key"]):
					continue
				var way := false
				for k: Object in pc3["next"]:
					if safe.has(k):
						way = true
						break
				if not way:
					safe.erase(pc3["key"])
					changed = true
		_safe.append(safe)
		report.append("%s %d" % [t.id, safe.size()])
	print("[traffic] safe lane pieces per type (of %d): %s" % [pcs.size(), ", ".join(report)])


## The lane piece at (lane, s) keeps vehicle type ti on roads it belongs on.
func _piece_safe(ti: int, lane: LaneGraph.Lane, s: float) -> bool:
	return _safe[ti].has(graph.piece_key(lane, s))


## Picks the vehicle model: the Blender traffic export, else the closest-sized player car model, else a box.
func _resolve_model(t: Resource) -> Dictionary:
	var info := {"path": "", "placeholder": true, "fallback": null, "length": float(t.length), "width": float(t.width)}
	if ResourceLoader.exists(t.model_path):
		info["path"] = t.model_path
		info["placeholder"] = false
	else:
		var best: CarData = null
		var bd := INF
		for d: CarData in Game.get_car_catalog():
			if d.model_path == "" or not ResourceLoader.exists(d.model_path):
				continue
			var score := absf(d.body_size.z - t.length) + absf(d.body_size.y - t.height) * 0.5
			if score < bd:
				bd = score
				best = d
		if best != null:
			info["path"] = best.model_path
			info["fallback"] = best
			info["length"] = best.body_size.z
			info["width"] = best.body_size.x
			print("[traffic] PLACEHOLDER: %s model missing (%s) - using player car model %s" % [t.id, t.model_path, best.id])
		else:
			print("[traffic] PLACEHOLDER: %s model missing (%s) - using box placeholder" % [t.id, t.model_path])
	info["car_data"] = t.make_car_data(info["path"], info["fallback"])
	return info


func _take_visual(ti: int, paint: Dictionary) -> MeshInstance3D:
	var pool: Array = _visual_pool[ti]
	var vis: MeshInstance3D = pool.pop_back() if not pool.is_empty() else _make_visual(ti)
	_paint_visual(vis, paint, ti)
	# Pooled visuals keep the lens state of their last moving owner: start with every lamp dark (parked cars
	# never update them; moving vehicles re-apply theirs on the first tick, light_state = -1). Variant 0 is not
	# dark: it is the daytime state of a running car.
	var kit := _visual_kit(ti)
	for key: String in ["brake", "tail", "head"]:
		_set_lens(vis, kit[key], kit[key + "_off"], 0)
	vis.visible = true
	return vis


func _release_visual(ti: int, vis: MeshInstance3D) -> void:
	var pool: Array = _visual_pool[ti]
	if pool.size() >= MAX_POOLED_VISUALS:
		vis.queue_free()
		return
	vis.visible = false
	pool.append(vis)


## Kinematic LOD: one MeshInstance3D per vehicle with the type's merged mesh and its own paint material.
func _make_visual(ti: int) -> MeshInstance3D:
	var kit := _visual_kit(ti)
	var mi := MeshInstance3D.new()
	mi.name = "TV_%s_%d" % [types[ti].id, _uid]
	mi.mesh = kit["mesh"]
	var pm := ShaderMaterial.new()
	pm.shader = CarFactory.PAINT_SHADER
	for idx: int in kit["paint"]:
		mi.set_surface_override_material(idx, pm)
	mi.set_meta(&"paint", pm)
	_visual_root.add_child(mi)
	return mi


## Builds (once per type) the far-LOD kit: the model merged into one mesh without interior/caliper detail,
## paint and lens surface indices, and lens material variants shared by every instance.
func _visual_kit(ti: int) -> Dictionary:
	var info: Dictionary = _models[ti]
	if info.has("kit"):
		return info["kit"]
	var key: String = info["path"] if info["path"] != "" else "box:" + String(types[ti].id)
	if _kits.has(key):
		info["kit"] = _kits[key]
		return info["kit"]
	var kit := {"paint": [], "head": [], "tail": [], "brake": [], "base": {}}
	var mesh := ArrayMesh.new()
	var scene: PackedScene = CarFactory.load_model(info["path"]) if info["path"] != "" else null
	if scene != null:
		var model: Node3D = scene.instantiate()
		var stack: Array = [[model, Transform3D.IDENTITY]]
		while not stack.is_empty():
			var item: Array = stack.pop_back()
			var n: Node = item[0]
			var xf: Transform3D = item[1]
			if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
				var mi := n as MeshInstance3D
				for i in mi.mesh.get_surface_count():
					_merge_surface(mesh, kit, mi.mesh, i, xf, mi.get_active_material(i))
			for c in n.get_children():
				var cn := String(c.name)
				if c is Node3D and not (cn in ["Interior", "SteeringWheel", "Lights_Reverse"] or cn.begins_with("Caliper_") or cn.begins_with("Socket_")):
					stack.append([c, xf * (c as Node3D).transform])
		model.free()
	else:
		_box_kit(mesh, kit, types[ti])
	# Merging drops the importer's automatic LODs: regenerate them (distant traffic is the common case).
	var im := ImporterMesh.from_mesh(mesh)
	im.generate_lods(25.0, 60.0, [])
	var lod_mesh := im.get_mesh()
	kit["mesh"] = lod_mesh if lod_mesh != null and lod_mesh.get_surface_count() == mesh.get_surface_count() else mesh
	var base: Dictionary = kit["base"]
	kit["head_m"] = _lens_variants(base.get("head"), Color(1.0, 0.96, 0.88), [0.8, 6.0])
	kit["tail_m"] = _lens_variants(base.get("tail"), Color(1.0, 0.05, 0.03), [0.35, 2.2])
	kit["brake_m"] = _lens_variants(base.get("brake"), Color(1.0, 0.03, 0.02), [0.25, 5.25, 1.05, 6.05])
	for lens: String in ["head", "tail", "brake"]:
		kit[lens + "_off"] = _lens_off(base.get(lens))
	_kits[key] = kit
	info["kit"] = kit
	return kit


func _merge_surface(mesh: ArrayMesh, kit: Dictionary, src: Mesh, i: int, xf: Transform3D, mat: Material) -> void:
	var st := SurfaceTool.new()
	st.append_from(src, i, xf)
	var mname := mat.resource_name if mat != null else ""
	if mname.begins_with("Glass"):
		mat = CarVisuals._glass_material()
	st.set_material(mat)
	st.commit(mesh)
	var idx := mesh.get_surface_count() - 1
	if mname.begins_with("Paint"):
		(kit["paint"] as Array).append(idx)
	for key: String in ["head", "tail", "brake"]:
		var prefix: String = {"head": "HeadlightLens", "tail": "TaillightLens", "brake": "BrakeLens"}[key]
		if mname.begins_with(prefix) and mat is StandardMaterial3D:
			(kit[key] as Array).append(idx)
			kit["base"][key] = mat


func _lens_variants(base: Variant, emission: Color, energies: Array) -> Array:
	var out: Array = []
	if base == null:
		return out
	for e: float in energies:
		var m: StandardMaterial3D = (base as StandardMaterial3D).duplicate()
		m.emission_enabled = true
		m.emission = emission
		m.emission_energy_multiplier = e
		out.append(m)
	return out


## Unlit lens (parked cars, nobody at the wheel): one-element variant list for _set_lens.
func _lens_off(base: Variant) -> Array:
	if base == null:
		return []
	var m: StandardMaterial3D = (base as StandardMaterial3D).duplicate()
	m.emission_enabled = false
	return [m]


## Development stand-in (no model at all): painted box body, dark cabin and wheels, merged like a model.
func _box_kit(mesh: ArrayMesh, kit: Dictionary, t: Resource) -> void:
	var dark := StandardMaterial3D.new()
	dark.resource_name = "Box_placeholder_dark"
	dark.albedo_color = Color(0.08, 0.1, 0.12)
	dark.roughness = 0.2
	var body := BoxMesh.new()
	body.size = Vector3(t.width, t.height * 0.62, t.length)
	var paint := ShaderMaterial.new()
	paint.resource_name = "Paint_placeholder"
	_merge_surface(mesh, kit, body, 0, Transform3D(Basis(), Vector3(0, 0.3 + body.size.y * 0.5, 0)), paint)
	var cab := BoxMesh.new()
	cab.size = Vector3(t.width * 0.9, t.height * 0.32, t.length * 0.45)
	_merge_surface(mesh, kit, cab, 0, Transform3D(Basis(), Vector3(0, 0.3 + body.size.y + cab.size.y * 0.5, t.length * 0.05)), dark)
	for fz: float in [-0.5, 0.5]:
		for sx: float in [-0.5, 0.5]:
			var cy := CylinderMesh.new()
			cy.top_radius = t.wheel_radius
			cy.bottom_radius = t.wheel_radius
			cy.height = 0.25
			var wxf := Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3(sx * t.width * 0.86, t.wheel_radius, fz * t.wheelbase))
			_merge_surface(mesh, kit, cy, 0, wxf, dark)


func _paint_visual(vis: MeshInstance3D, paint: Dictionary, ti: int) -> void:
	var color: Color = paint["color"]
	var finish: int = paint["finish"]
	var size: Vector3 = (_models[ti]["car_data"] as CarData).body_size
	var m: ShaderMaterial = vis.get_meta(&"paint")
	m.set_shader_parameter("base_color", color)
	m.set_shader_parameter("metallic", 0.75 if finish == CarData.Finish.METALLIC else 0.0)
	m.set_shader_parameter("roughness", 0.3 if finish == CarData.Finish.METALLIC else (0.62 if finish == CarData.Finish.MATTE else 0.18))
	m.set_shader_parameter("clearcoat_amount", 0.0 if finish == CarData.Finish.MATTE else 1.0)
	m.set_shader_parameter("flake_amount", 0.6 if finish == CarData.Finish.METALLIC else 0.0)
	m.set_shader_parameter("stripe_mode", 0)
	m.set_shader_parameter("body_half_width", size.x * 0.5)
	m.set_shader_parameter("body_height", size.y)


func _take_car(ti: int, paint: Dictionary) -> CarController:
	var pool: Array = _car_pool[ti]
	var car: CarController = pool.pop_back() if not pool.is_empty() else _make_car(ti)
	CarFactory.apply_paint(car, paint)
	car.in_throttle = 0.0
	car.in_brake = 0.0
	car.in_steer = 0.0
	car.in_handbrake = 0.0
	car.repair()
	_car_root.add_child(car)
	return car


func _release_car(ti: int, car: CarController) -> void:
	_car_owner.erase(car)
	if car.get_parent() != null:
		car.get_parent().remove_child(car)
	var pool: Array = _car_pool[ti]
	if pool.size() >= MAX_POOLED_CARS:
		car.free()
		return
	pool.append(car)


## Kinematic collider (layer 4 like physics traffic; wheel rays do not see it). Pooled bodies wait out of the
## tree, so entering it places them without a sweep from their last position.
func _take_body(v: TrafficVehicle) -> void:
	var b: AnimatableBody3D = _body_pool.pop_back() if not _body_pool.is_empty() else null
	if b == null:
		b = AnimatableBody3D.new()
		b.collision_layer = 4
		b.collision_mask = 0
		b.sync_to_physics = true
		var cs := CollisionShape3D.new()
		cs.shape = BoxShape3D.new()
		b.add_child(cs)
	((b.get_child(0) as CollisionShape3D).shape as BoxShape3D).size = Vector3(v.half_width * 2.0 * 0.94, 1.0, v.length * 0.95)
	b.transform = _body_transform(v.kinematic_transform())
	_body_root.add_child(b)
	v.body = b


func _release_body(v: TrafficVehicle) -> void:
	if v.body == null:
		return
	_body_root.remove_child(v.body)
	_body_pool.append(v.body)
	v.body = null


static func _body_transform(xf: Transform3D) -> Transform3D:
	return Transform3D(xf.basis, xf.origin + xf.basis.y * 0.75)


func _make_car(ti: int) -> CarController:
	var car := CarFactory.build(_models[ti]["car_data"], {}, false)
	car.name = "Traffic_%s_%d" % [types[ti].id, _uid]
	var vis := car.get_node("Visual") as CarVisuals
	vis.add_headlights()
	for l in vis.headlights:
		l.distance_fade_enabled = true
		l.distance_fade_begin = LIGHT_FADE_BEGIN
		l.distance_fade_length = LIGHT_FADE_LENGTH
	var scr := _car_audio_script()
	if scr != null:
		var a: Node = scr.new()
		a.name = "CarAudio"
		car.add_child(a)
	if ResourceLoader.exists(EFFECTS_SCRIPT):
		var fx: Node = (load(EFFECTS_SCRIPT) as Script).new()
		fx.name = "CarEffects"
		car.add_child(fx)
	car.impact.connect(_on_car_impact.bind(car))
	return car


## The audio subsystem's CarAudio is attached to physics traffic only when it supports honk().
func _car_audio_script() -> Script:
	if _audio_script == null and ResourceLoader.exists(AUDIO_SCRIPT):
		var s: Script = load(AUDIO_SCRIPT)
		if s != null and s.can_instantiate():
			for m: Dictionary in s.get_script_method_list():
				if m["name"] == "honk":
					_audio_script = s
					break
	return _audio_script


# ----------------------------------------------------------------- main loop

func _process(delta: float) -> void:
	if not enabled:
		return
	if get_tree().paused:
		_paused_light_update(delta)
		return
	var pc := Game.player_car
	if pc == null or not is_instance_valid(pc):
		return
	var t0 := Time.get_ticks_usec()
	var pp := pc.global_position
	if _player_pos == Vector3.INF or pp.distance_to(_player_pos) > 250.0:
		if _player_pos != Vector3.INF:
			_flush_all()
		_fill = 3.0
		_target_timer = 0.0
	_player_pos = pp
	_player_vel = pc.linear_velocity
	_refresh_ai_cars()
	var cam := _camera()
	if cam != null:
		_cam_fwd = -cam.global_transform.basis.z
	_fill = maxf(_fill - delta, 0.0)
	_recycle_t -= delta
	_target_timer -= delta
	if _target_timer <= 0.0:
		_target_timer = 1.0
		_update_target()
	_update_lights(delta)
	_rebuild_occupancy()
	_frame += 1
	for v: TrafficVehicle in vehicles:
		_update_decision(v)
		var far := v.position.distance_squared_to(_player_pos) > HALF_RATE_DIST * HALF_RATE_DIST
		if v.mode == TrafficVehicle.Mode.KINEMATIC and far and (v.uid + _frame) % 2 == 1:
			v.skip_dt += delta
			v.tick_dt = 0.0
		else:
			v.tick_dt = delta + v.skip_dt
			v.skip_dt = 0.0
	var t1 := Time.get_ticks_usec()
	for v: TrafficVehicle in vehicles:
		if v.tick_dt > 0.0:
			_plan(v, v.tick_dt)
	var t2 := Time.get_ticks_usec()
	for v: TrafficVehicle in vehicles:
		if v.mode == TrafficVehicle.Mode.KINEMATIC:
			if v.tick_dt > 0.0:
				_move_kinematic(v, v.tick_dt)
		else:
			_update_physics_vehicle(v, delta)
		v.unseen_t = 0.0 if _in_view(v.position) else v.unseen_t + delta
	var t3 := Time.get_ticks_usec()
	_lod_timer -= delta
	if _lod_timer <= 0.0:
		_lod_timer = 0.2
		_update_lod()
	_despawn_pass()
	_spawn_pass()
	_parked_timer -= delta
	if _parked_timer <= 0.0:
		_parked_timer = 0.5
		_update_parked()
	_update_physics_points()
	if debug:
		_prof["frames"] += 1
		_prof["pre"] += t1 - t0
		_prof["plan"] += t2 - t1
		_prof["move"] += t3 - t2
		_prof["rest"] += Time.get_ticks_usec() - t3
	_stats_timer -= delta
	if _stats_timer <= 0.0:
		_stats_timer = 0.25
		_update_stats((Time.get_ticks_usec() - t0) / 1000.0)
	if debug:
		_debug_timer -= delta
		if _debug_timer <= 0.0:
			_debug_timer = 5.0
			_print_debug()


## Cars driven by the activities (race rivals, also while they cruise off after a race).
func _refresh_ai_cars() -> void:
	_ai_cars.clear()
	var acts: Node = Game.activities
	if acts != null and acts.has_method("get_ai_cars"):
		_ai_cars.assign(acts.call("get_ai_cars"))


## Only reached while paused when photo mode wakes the time-reactive group after changing the time or weather:
## the lamps follow the new light state, nothing moves, spawns or despawns. Physics traffic lamps are drawn by
## their CarVisuals (time-reactive themselves) from car.headlights_on.
func _paused_light_update(delta: float) -> void:
	_update_lights(delta)
	for v: TrafficVehicle in vehicles:
		if v.mode == TrafficVehicle.Mode.KINEMATIC:
			if v.visual != null:
				_update_kin_lights(v, v.light_state >= 0 and v.light_state % 2 == 1)
		elif v.car != null:
			v.car.headlights_on = _lit(v)


func _physics_process(delta: float) -> void:
	if not enabled or get_tree().paused:
		return
	for v: TrafficVehicle in vehicles:
		if v.mode != TrafficVehicle.Mode.PHYSICS or v.car == null:
			continue
		var car := v.car
		if v.hazard and not v.recovering:
			if car.speed_ms > 2.5:
				# Still rolling: brake in a straight line (ABS) and hold the lane while the car points along it;
				# a locked handbrake at speed would spin it off the road.
				v.track(car.global_position)
				var lane_dir := v.path_point(6.0) - v.path_point(0.0)
				var aligned := v.heading.dot(Vector3(lane_dir.x, 0.0, lane_dir.z).normalized()) > 0.8
				if aligned:
					v.follower.target_speed = 0.0
					v.follower.speed_cap = 0.0
					v.follower.obstacle_limit = 0.0
					v.follower.drive(car, delta)
				else:
					car.in_steer = 0.0
				car.in_throttle = 0.0
				car.in_handbrake = 0.0
				car.in_brake = v.hazard_brake
			else:
				car.in_throttle = 0.0
				car.in_steer = 0.0
				car.in_handbrake = 1.0
				car.in_brake = 0.22 if fmod(v.hazard_t, 0.8) < 0.4 else 0.0
			continue
		v.track(car.global_position)
		if v.hazard:
			# Recovering after a crash: crawl back onto the lane, pause while the player is close.
			v.follower.target_speed = 3.0
			v.follower.speed_cap = 0.0 if car.global_position.distance_to(_player_pos) < 7.0 else 3.0
			v.follower.obstacle_limit = INF
			v.follower.max_throttle = 0.8
			v.follower.drive(car, delta)
			continue
		v.follower.target_speed = v.v_desired
		v.follower.speed_cap = v.speed_cap
		v.follower.obstacle_limit = v.follow_limit
		# Full power to climb out when hung up on a kerb or seam, and on steep climbs (heavy vehicles hold
		# their speed only at full throttle, which also lets the automatic box kick down).
		var climbing := -car.global_transform.basis.z.y > 0.04
		v.follower.max_throttle = 1.0 if v.stuck_t > 1.5 or climbing else 0.7
		v.follower.drive(car, delta)


# ----------------------------------------------------------------- planning

func _rebuild_occupancy() -> void:
	for a: Array in _occ_lane.values():
		a.clear()
	for a2: Array in _occ_conn.values():
		a2.clear()
	_busy_conns.clear()
	_by_uid.clear()
	for v: TrafficVehicle in vehicles:
		_by_uid[v.uid] = v
		if v.hazard and v.offlane:
			continue
		if v.conn != null:
			if (_occ_conn.get(v.conn.id, _empty) as Array).is_empty():
				_busy_conns.append(v.conn)
			_occ_add(_occ_conn, v.conn.id, v)
		else:
			_occ_add(_occ_lane, v.lane.id, v)
			if v.prev_lane != null:
				_occ_add(_occ_lane, v.prev_lane.id, v)


func _occ_add(d: Dictionary, key: int, v: TrafficVehicle) -> void:
	var arr: Array = d.get(key, [])
	if arr.is_empty() and not d.has(key):
		d[key] = arr
	arr.append(v)


func _update_decision(v: TrafficVehicle) -> void:
	if v.conn != null:
		return
	if v.leaving and v.choice == null and v.decision != null:
		# No way on for its type: it holds before this junction until it can be removed unseen.
		return
	if v.decision != null:
		var sd := v.lane.sdist(v.s, v.decision.at_s)
		# Loops: sdist wraps at half the length, so only a small negative value means "just passed".
		var passed := sd < -0.5 and (not v.lane.road.loop or sd > -300.0)
		if v.choice != null or not passed:
			return
	v.decision = graph.next_decision(v.lane, v.s)
	v.choice = null
	v.go = false
	if v.decision != null:
		v.choice = _choose(v, v.decision)


## Turn (connector) or straight on (null) at decision d: only ways into lane pieces that are safe for v's type.
func _choose(v: TrafficVehicle, d: LaneGraph.Decision) -> LaneGraph.Connector:
	var opts: Array = []
	for cn: LaneGraph.Connector in d.options:
		if _piece_safe(v.type_index, cn.to_lane, cn.to_s):
			opts.append(cn)
	var straight := not d.mandatory and _piece_safe(v.type_index, v.lane, v.lane.advance(d.at_s, 1.0))
	if straight and (opts.is_empty() or _rng.randf() > TURN_CHANCE):
		return null
	if opts.is_empty():
		# Trapped (only a vehicle placed by hand gets here: spawns, turns and lane changes keep to safe pieces):
		# it stops before the junction and is removed once nobody sees it, never driving onto a road it does
		# not belong on.
		v.leaving = true
		return null
	return opts[_rng.randi() % opts.size()]


func _plan(v: TrafficVehicle, delta: float) -> void:
	v.honk_cd -= delta
	if v.hazard:
		v.v_target = 0.0
		v.follow_limit = 0.0
		return
	var vt := minf(v.v_desired, v.curve_limit(B_COMFORT))
	vt = minf(vt, _junction_limit(v, delta))
	if v.leaving and v.conn == null and v.choice == null and v.decision != null:
		vt = minf(vt, sqrt(2.0 * B_COMFORT * maxf(v.lane.sdist(v.s, v.decision.at_s) - v.length * 0.5 - 1.0, 0.0)))
	if v.conn == null and v.choice == null and not v.lane.road.loop:
		vt = minf(vt, sqrt(2.0 * B_COMFORT * maxf(v.lane.remaining(v.s) - 4.0, 0.0)))
	_find_leader(v)
	if v.lead_uid >= 0 and _lead_cycle_breaks(v):
		_counters["lead_cycle_ticks"] += 1
		_ignore_uid = v.lead_uid
		_find_leader(v)
		_ignore_uid = -1
	vt = minf(vt, v.pass_cap)
	if v.shaken_t > 0.0:
		# Shunted: brakes smoothly in its lane for a moment, then carries on.
		v.shaken_t -= delta
		v.shaken_v = maxf(v.shaken_v - B_COMFORT * delta, v.shaken_floor)
		vt = minf(vt, v.shaken_v)
	v.follow_limit = INF
	if v.lead_gap < INF:
		var gap := v.lead_gap
		if _behind_stopped_obstacle(v) and not v.lane.siblings.is_empty():
			# Stops a few metres further back, with room to pull out round it into the other lane.
			gap -= 5.0
		v.follow_limit = RoadFollower.follow_speed(gap, v.lead_speed, v.speed, v.time_gap)
	v.speed_cap = vt
	v.v_target = maxf(minf(vt, v.follow_limit), 0.0)
	_try_lane_change(v, delta)
	if v.mode == TrafficVehicle.Mode.PHYSICS:
		_player_reactions(v, delta)


func _junction_limit(v: TrafficVehicle, delta: float) -> float:
	if v.conn != null or v.choice == null or v.decision == null:
		return INF
	var cn := v.choice
	if cn.yield_mode == LaneGraph.Yield.NONE:
		return INF
	var d := v.lane.sdist(v.s, v.decision.at_s)
	if d > 70.0:
		return INF
	var clear := _junction_clear(cn, v)
	var front := v.length * 0.5 + 0.8
	if v.go:
		# Committed once its nose is at the line (a lorry or coach stops with its centre well behind it).
		if clear or d < front + 1.5:
			return INF
		v.go = false
	if clear and (cn.yield_mode == LaneGraph.Yield.ONCOMING or (v.speed < 4.2 and d < front + 6.0)):
		# wait_t is kept until it enters the connector: the same (patient) gap rule then holds the go.
		v.go = true
		_counters["give_way_entries"] += 1
		if v.waited:
			_counters["yield_waits"] += 1
		v.waited = false
		return INF
	if v.speed < 0.6 and d < front + 4.0:
		v.wait_t += delta
		if v.wait_t > 0.5:
			v.waited = true
	return sqrt(2.0 * B_COMFORT * maxf(d - front, 0.0))


## Give-way check: no traffic approaching on the major road within ~50 m, nobody else turning, and
## the player neither in the junction box nor about to enter it.
func _junction_clear(cn: LaneGraph.Connector, v: TrafficVehicle) -> bool:
	var j := cn.junction
	# Patience grows after 5 s at the line: shorter gaps accepted (x0.6 and 28 m from 12 s on).
	var patience := clampf((v.wait_t - 5.0) / 7.0, 0.0, 1.0)
	var range_m := lerpf(JUNCTION_CLEAR, 28.0, patience)
	# Time this vehicle needs to clear the junction (from a rolling stop, or rolling through a left turn).
	var t_clear := sqrt(2.0 * cn.length / maxf(float(v.data.accel), 0.5)) + 1.5
	if cn.yield_mode == LaneGraph.Yield.ONCOMING:
		t_clear = cn.length / maxf(v.speed, 3.0) + 1.5
	t_clear *= lerpf(1.0, 0.6, patience)
	for pl: LaneGraph.Lane in j.parent_lanes:
		if cn.yield_mode == LaneGraph.Yield.ONCOMING and pl.dir == cn.from_lane.dir:
			continue
		# A right turn out of the minor road only merges into the near side: the far carriageway is not crossed.
		if cn.yield_mode == LaneGraph.Yield.MINOR and cn.turn > 0 and pl.dir != cn.to_lane.dir:
			continue
		for w: TrafficVehicle in _occ_lane.get(pl.id, _empty):
			if w == v:
				continue
			var d := pl.sdist(w.s, j.parent_s)
			if w.speed < 0.5 and d > j.radius + 2.0:
				continue
			if d > -j.radius and d < maxf(range_m, w.speed * t_clear):
				return false
	for c2: LaneGraph.Connector in j.connectors:
		if c2 == cn:
			continue
		# Merging into the same lane from the parallel stop line (a two-lane minor road): once the other one
		# is well into its turn it is just a leader to fall in behind.
		var same_merge := c2.to_lane == cn.to_lane and c2.yield_mode == LaneGraph.Yield.MINOR and cn.yield_mode == LaneGraph.Yield.MINOR
		for w1: TrafficVehicle in _occ_conn.get(c2.id, _empty):
			if not (same_merge and w1.c > 8.0):
				return false
		# Someone at another approach already has the go: one entry at a time, also within a frame. At the
		# parallel stop line, whoever has waited longer goes first (no lane is starved by the other's stream).
		for w2: TrafficVehicle in _occ_lane.get(c2.from_lane.id, _empty):
			if w2 == v or w2.choice != c2:
				continue
			if w2.go or (same_merge and w2.wait_t > v.wait_t + 0.5):
				return false
	var pc := Game.player_car
	if pc != null and is_instance_valid(pc) and _entering_junction(j, pc, range_m):
		return false
	for o in _ai_cars:
		if is_instance_valid(o) and _entering_junction(j, o as CarController, range_m):
			return false
	return true


## A non-traffic car (player, activity AI) in the junction box or about to enter it.
func _entering_junction(j: LaneGraph.Junction, car: CarController, range_m: float) -> bool:
	var rel := j.center - car.global_position
	rel.y = 0.0
	var dist := rel.length()
	if dist < j.radius + 3.0:
		return true
	var vr := car.linear_velocity.dot(rel / maxf(dist, 0.01))
	return vr > 1.0 and dist < maxf(range_m + 5.0, vr * 4.5 + j.radius)


func _find_leader(v: TrafficVehicle) -> void:
	v.lead_gap = INF
	v.lead_speed = 0.0
	v.lead_is_player = false
	v.lead_uid = -1
	v.pass_cap = INF
	var reach := clampf(25.0 + v.speed * 5.0, 45.0, 170.0)
	if v.conn == null:
		_scan_lane(v, v.lane, v.s, 0.0, reach)
		if v.choice != null and v.decision != null:
			var dx := v.lane.sdist(v.s, v.decision.at_s)
			if dx < reach:
				_scan_conn(v, v.choice, 0.0, maxf(dx, 0.0), reach)
				_scan_lane(v, v.choice.to_lane, v.choice.to_s, maxf(dx, 0.0) + v.choice.length, reach)
	else:
		_scan_conn(v, v.conn, v.c, 0.0, reach)
		_scan_lane(v, v.conn.to_lane, v.conn.to_s, v.conn.length - v.c, reach)
	# Kinematic vehicles near the player are solid too (and may have no physics slot): they brake for it as well.
	if v.mode == TrafficVehicle.Mode.PHYSICS or v.position.distance_squared_to(_player_pos) < KIN_PROBE_DIST * KIN_PROBE_DIST:
		_probe_obstacles(v, reach)
	# Activity AI cars (race rivals) can be anywhere, also near kinematic traffic.
	_nudge_want = 0.0
	for o in _ai_cars:
		if is_instance_valid(o):
			var ai: CarController = o
			_probe(v, ai.global_position, ai.linear_velocity, ai.data.body_size.z * 0.5, ai.data.body_size.x * 0.5, reach, false, -ai.global_transform.basis.z, true)
	v.nudge = _nudge_want


func _consider(v: TrafficVehicle, w: TrafficVehicle, d: float) -> void:
	if w.uid == _ignore_uid:
		return
	var gap := d - (v.length + w.length) * 0.5
	if gap < v.lead_gap:
		v.lead_gap = gap
		v.lead_speed = w.speed
		v.lead_is_player = false
		v.lead_uid = w.uid


## `base` > 0: v reaches this lane through a connector (it is on it, or it is its chosen turn) `base` metres
## before from_s.
func _scan_lane(v: TrafficVehicle, lane: LaneGraph.Lane, from_s: float, base: float, reach: float) -> void:
	var min_d := 0.05 if base == 0.0 else -0.1
	for w: TrafficVehicle in _occ_lane.get(lane.id, _empty):
		if w == v:
			continue
		var d := lane.sdist(from_s, w.s)
		if d >= min_d and d + base < reach:
			_consider(v, w, d + base)
	var merging := v.conn != null or base > 0.0
	for cn: LaneGraph.Connector in _busy_conns:
		var on: Array = _occ_conn[cn.id]
		if cn.from_lane == lane:
			# Vehicles just turning off this lane ahead of us.
			var da := lane.sdist(from_s, cn.at_s)
			if da >= -0.1:
				for w2: TrafficVehicle in on:
					if w2 != v and w2.c < 18.0 and base + da + w2.c < reach:
						_consider(v, w2, base + da + w2.c)
		if cn.to_lane == lane and cn != v.conn and cn != v.choice:
			# Vehicles merging into this lane (v's own connector is _scan_conn's job). `entry`: distance from v
			# to where they join.
			var entry := base + lane.sdist(from_s, cn.to_s)
			for w3: TrafficVehicle in on:
				if w3 == v:
					continue
				var d3: float
				if merging:
					# Both join here (e.g. side by side from a two-lane road): whoever has less of its way to the
					# lane left goes first, the other falls in behind. Antisymmetric, so never both wait.
					d3 = entry - (cn.length - w3.c)
					if d3 < 0.0 or (d3 == 0.0 and w3.uid > v.uid):
						continue
				else:
					# Long turns come in from the side: use where they really are along the lane. Once we are
					# past where they join, they fall in behind us (they see us ahead on their target lane).
					d3 = base + lane.sdist(from_s, LaneGraph.project_s(lane.road, w3.position, cn.to_s))
					if d3 <= -v.length or (d3 < 0.0 and entry < 0.0):
						continue
				if d3 < reach:
					_consider(v, w3, maxf(d3, (v.length + w3.length) * 0.5 + 0.5))
		if cn.crosses.has(lane):
			# A left turn crossing this lane at the junction ahead: hold back until it has crossed.
			var dj := lane.sdist(from_s, cn.junction.parent_s)
			if dj > -1.0 and base + dj < reach:
				for w4: TrafficVehicle in on:
					if w4 != v and w4.uid != _ignore_uid and w4.c < cn.length - 3.0:
						var gap := base + dj - cn.junction.radius * 0.6 - v.length * 0.5
						if gap < v.lead_gap:
							v.lead_gap = gap
							v.lead_speed = 0.0
							v.lead_is_player = false
							v.lead_uid = w4.uid


## True when v's chain of leaders comes back to v (vehicles waiting on each other would stand for good) and
## v is the one that goes first: of a pair the one really ahead, of a longer ring the lowest uid.
func _lead_cycle_breaks(v: TrafficVehicle) -> bool:
	var w: TrafficVehicle = _by_uid.get(v.lead_uid)
	if w == null:
		return false
	if w.lead_uid == v.uid:
		var v_ahead := (v.position - w.position).dot(w.heading)
		var w_ahead := (w.position - v.position).dot(v.heading)
		if absf(v_ahead - w_ahead) > 0.5:
			return v_ahead > w_ahead
		return v.uid < w.uid
	var lowest := mini(v.uid, w.uid)
	var u := w
	for i in 6:
		u = _by_uid.get(u.lead_uid)
		if u == null:
			return false
		if u == v:
			return v.uid == lowest
		lowest = mini(lowest, u.uid)
	return false


func _scan_conn(v: TrafficVehicle, cn: LaneGraph.Connector, from_c: float, base: float, reach: float) -> void:
	for w: TrafficVehicle in _occ_conn.get(cn.id, _empty):
		if w == v:
			continue
		var d := w.c - from_c
		if d > 0.05 and d + base < reach:
			_consider(v, w, d + base)


## Physics LOD: the player and crashed/off-lane cars are not on the lane graph; probe them against the
## planned path instead (activity AI cars are probed in every LOD by _find_leader).
func _probe_obstacles(v: TrafficVehicle, reach: float) -> void:
	var pc := Game.player_car
	if pc != null and is_instance_valid(pc):
		_probe(v, pc.global_position, pc.linear_velocity, pc.data.body_size.z * 0.5, pc.data.body_size.x * 0.5, reach, true, -pc.global_transform.basis.z)
	for w: TrafficVehicle in vehicles:
		if w != v and w.mode == TrafficVehicle.Mode.PHYSICS and (w.hazard or w.offlane) and w.car != null:
			_probe(v, w.position, w.car.linear_velocity, w.length * 0.5, w.half_width, reach, false, w.heading)


## An obstacle off the lane graph (heading `ofwd`) against v's planned path.
func _probe(v: TrafficVehicle, pos: Vector3, vel: Vector3, half_len: float, half_w: float, reach: float, is_player: bool, ofwd: Vector3, ai := false) -> void:
	var fwd := Vector3(v.heading.x, 0.0, v.heading.z).normalized()
	var rel := pos - v.position
	rel.y = 0.0
	var fd := rel.dot(fwd)
	if fd <= 0.5 or fd > reach:
		return
	var q := v.path_point(fd)
	# Extents of the (possibly slewed) obstacle along and across v's path.
	var of := Vector3(ofwd.x, 0.0, ofwd.z).normalized()
	var c_along := absf(of.dot(fwd))
	var c_across := sqrt(maxf(1.0 - c_along * c_along, 0.0))
	var gap := fd - v.length * 0.5 - (c_along * half_len + c_across * half_w)
	# Side clearance between the two bodies: in the way only when it leaves no safe room (more at speed); a
	# car beside the lane (hard shoulder, verge) is passed, slower the closer it is.
	var clear := Vector2(pos.x - q.x, pos.z - q.z).length() - v.half_width - (c_across * half_len + c_along * half_w)
	var need := 0.3 + v.speed * 0.012
	if ai and of.dot(fwd) < -0.5 and v.conn == null and v.lane.outer and fd < 30.0 + v.speed * 2.0 and clear < need + 1.0:
		# A race rival coming the other way over the centre line (back from a pass, or stopped there): edge over
		# toward the verge as far as the paved edge allows (path_point already includes the current nudge, so
		# this settles on the nudge that leaves `need` + 0.15 m) and squeeze past slowly when that is enough.
		# Otherwise it stops in front of it as before, with the room it made, and the rival backs into its half.
		var room := maxf(v.lane.road.width * 0.5 - v.lane.offset - v.half_width - VERGE_MARGIN, 0.0)
		var want := clampf(v.nudge + need + 0.15 - clear, 0.0, room)
		_nudge_want = maxf(_nudge_want, want)
		var fit := clear + want - v.nudge
		if fit >= need:
			if fit < 1.3:
				# Tight: walking pace past it; with more room the usual pass speed for a car beside the lane.
				var pass_v0 := SQUEEZE_SPEED + (fit - need) * 8.0 if fit < need + 0.6 else 10.0 + fit * 16.0
				v.pass_cap = minf(v.pass_cap, sqrt(pass_v0 * pass_v0 + 2.0 * B_COMFORT * maxf(gap, 0.0)))
			return
		# No room yet: wait well short of it, leaving the rival space to back up and pull into its half.
		gap -= AI_WAIT_GAP
	if clear > need:
		if clear < 1.3:
			var pass_v := 10.0 + clear * 16.0
			v.pass_cap = minf(v.pass_cap, sqrt(pass_v * pass_v + 2.0 * B_COMFORT * maxf(gap, 0.0)))
		return
	if gap < v.lead_gap:
		v.lead_gap = gap
		v.lead_speed = maxf(vel.dot(fwd), 0.0)
		v.lead_is_player = is_player
		v.lead_uid = -1


func _try_lane_change(v: TrafficVehicle, delta: float) -> void:
	v.lane_change_t -= delta
	if v.lane_change_t > 0.0 or v.conn != null or v.lane.siblings.is_empty():
		return
	v.lane_change_t = 1.0
	# Pulls out from (near) standstill only round a stopped car that is not traffic queueing on the lane graph
	# (the player, a race rival, a crashed car).
	var round_stopped := _behind_stopped_obstacle(v)
	if absf(v.off - v.lane.offset) > 0.2 or (v.speed < 8.0 and not round_stopped):
		return
	if v.choice != null and v.lane.sdist(v.s, v.decision.at_s) < 350.0:
		return
	if not v.lane.road.loop and v.lane.remaining(v.s) < 300.0:
		return
	var target: LaneGraph.Lane = null
	if v.lane.outer:
		# Overtake anything slower ahead, the player included (the target lane check covers the player).
		if v.lead_gap < 75.0 and v.lead_speed < v.v_desired - 2.5:
			target = v.lane.sibling(v.lane.k - 1)
			var behind := 30.0 if round_stopped else 25.0 + maxf(v.v_desired - v.speed, 0.0) * 3.0
			if target != null and not _lane_clear(target, v, behind, 45.0):
				target = null
	else:
		# Back to the outer lane only when it does not end up right behind something slower.
		var outer := v.lane.sibling(v.lane.k + 1)
		if outer != null and _lane_clear(outer, v, 30.0, 75.0):
			target = outer
	if target != null and not _piece_safe(v.type_index, target, v.s):
		target = null
	if target != null:
		v.prev_lane = v.lane
		v.lane = target
		v.decision = null
		v.choice = null
		v.lane_change_t = 5.0
		_counters["lane_changes"] += 1


## Lead is a probed obstacle (player, AI car, crashed car: lead_uid < 0) standing close ahead.
static func _behind_stopped_obstacle(v: TrafficVehicle) -> bool:
	return v.lead_uid < 0 and v.lead_gap < 40.0 and v.lead_speed < 1.0


## Room for v in `lane` (a sibling of its lane): nobody within `behind` / `ahead` metres, both stretched by
## 5 s of closing speed (slower vehicles ahead, faster ones behind). Covers traffic, the player and AI cars.
func _lane_clear(lane: LaneGraph.Lane, v: TrafficVehicle, behind: float, ahead: float) -> bool:
	for w: TrafficVehicle in _occ_lane.get(lane.id, _empty):
		if w != v and not _room(lane.sdist(v.s, w.s), w.speed, v.speed, behind, ahead):
			return false
	if not _car_clear(lane, v, Game.player_car, behind, ahead):
		return false
	for o in _ai_cars:
		if is_instance_valid(o) and not _car_clear(lane, v, o as CarController, behind, ahead):
			return false
	return true


static func _room(d: float, other_v: float, own_v: float, behind: float, ahead: float) -> bool:
	if d >= 0.0:
		return d >= ahead + maxf(own_v - other_v, 0.0) * 5.0
	return -d >= behind + maxf(other_v - own_v, 0.0) * 5.0


## A car that is not on the lane graph (player, activity AI) does not take room in v's target lane.
func _car_clear(lane: LaneGraph.Lane, v: TrafficVehicle, car: CarController, behind: float, ahead: float) -> bool:
	if car == null or not is_instance_valid(car):
		return true
	var p := car.global_position
	var fd := (p - v.position).dot(v.heading)
	if fd < -behind - 60.0 or fd > ahead + 120.0 or absf(p.y - v.position.y) > 8.0:
		return true
	var r := lane.road
	var ps := LaneGraph.project_s(r, p, lane.advance(v.s, fd))
	var lat := (p - r.point_at(ps)).dot(r.right_at(ps)) * lane.dir
	var half := (r.width - 0.6) / float(r.lanes * 4) + car.data.body_size.x * 0.5
	if absf(lat - lane.offset) > half:
		return true
	var along := maxf(car.linear_velocity.dot(r.flat_tangent_at(ps) * lane.dir), 0.0)
	return _room(lane.sdist(v.s, ps), along, v.speed, behind, ahead)


func _player_reactions(v: TrafficVehicle, delta: float) -> void:
	var player_slow := _player_vel.length() < 1.5
	var blocked := v.lead_is_player and v.lead_gap < 18.0 and v.speed < 1.5 and player_slow
	if not blocked and v.wait_t > 3.0 and player_slow and v.choice != null:
		blocked = v.choice.junction.center.distance_to(_player_pos) < v.choice.junction.radius + 3.0
	if blocked:
		v.blocked_t += delta
		if v.blocked_t > 2.0 and v.honk_cd <= 0.0:
			_honk(v)
			v.flash_t = 0.0
			v.honk_cd = 7.0
			v.blocked_t = 0.0
	else:
		v.blocked_t = maxf(v.blocked_t - delta, 0.0)


# ----------------------------------------------------------------- LOD updates

func _move_kinematic(v: TrafficVehicle, delta: float) -> void:
	var err := v.v_target - v.speed
	var a := clampf(err * 1.3, -B_MAX, float(v.data.accel))
	v.accel_now = a
	v.speed = maxf(v.speed + a * delta, 0.0)
	if v.lead_gap < 0.3:
		# Safety net: kinematic cars never drive through the car ahead.
		v.speed = 0.0
	v.move(v.speed * delta)
	_ease_offset(v, delta)
	var xf := v.kinematic_transform()
	v.visual.transform = xf
	if v.body != null:
		v.body.transform = _body_transform(xf)
	v.position = xf.origin
	v.heading = -xf.basis.z
	_update_kin_lights(v, a < -1.0 or (v.speed < 0.3 and v.v_target < 0.5))


func _update_kin_lights(v: TrafficVehicle, braking: bool) -> void:
	var lit := _lit(v)
	var state := (1 if braking else 0) + (2 if lit else 0)
	if state == v.light_state:
		return
	v.light_state = state
	var kit: Dictionary = _models[v.type_index]["kit"]
	var mi := v.visual as MeshInstance3D
	var n := 1 if lit else 0
	_set_lens(mi, kit["brake"], kit["brake_m"], state)
	_set_lens(mi, kit["tail"], kit["tail_m"], n)
	_set_lens(mi, kit["head"], kit["head_m"], n)


## Lights on: the environment asks for them, or the vehicle is in (or about to enter) a tunnel.
func _lit(v: TrafficVehicle) -> bool:
	if _lights:
		return true
	if v.conn != null:
		return false
	var r := v.lane.road
	return (r.flag_at(v.s) & 2) != 0 or (r.flag_at(v.lane.advance(v.s, TUNNEL_LIGHTS_AHEAD)) & 2) != 0


func _set_lens(mi: MeshInstance3D, surfaces: Array, variants: Array, which: int) -> void:
	if variants.is_empty():
		return
	for idx: int in surfaces:
		mi.set_surface_override_material(idx, variants[which])


## Lane-change progress. Below 4 m/s it slows with the speed like the planned path (TrafficVehicle.path_point),
## with a small floor so a car pulling out from a standstill gets going.
func _ease_offset(v: TrafficVehicle, delta: float) -> void:
	if v.conn != null:
		return
	var rate := TrafficVehicle.LANE_CHANGE_RATE * clampf(v.speed / 4.0, 0.22, 1.0)
	v.off = move_toward(v.off, v.lane.offset + v.nudge, rate * delta)
	if v.prev_lane != null and absf(v.off - v.lane.offset - v.nudge) < 0.05:
		v.prev_lane = null


func _update_physics_vehicle(v: TrafficVehicle, delta: float) -> void:
	var car := v.car
	v.position = car.global_position
	v.heading = -car.global_transform.basis.z
	v.speed = maxf(car.forward_speed, 0.0)
	if v.prev_lane != null and v.conn == null:
		# The planned lane change never runs ahead of the car itself (probes test the planned path).
		var r := v.lane.road
		var act := (v.position - r.point_at(v.s)).dot(r.right_at(v.s)) * v.lane.dir
		v.off = clampf(v.off, act - 1.2, act + 1.2)
	_ease_offset(v, delta)
	var lit := _lit(v)
	if v.flash_t >= 0.0:
		v.flash_t += delta
		car.headlights_on = int(v.flash_t / 0.14) % 2 == 0 if v.flash_t < 0.56 else lit
		if v.flash_t >= 0.56:
			v.flash_t = -1.0
	else:
		car.headlights_on = lit
	if v.hazard:
		v.prev_vel = Vector3(car.linear_velocity.x, 0.0, car.linear_velocity.z)
		v.jolt = 0.0
		_update_hazard(v, delta)
		return
	# Collisions with other cars: Jolt spreads contact impulses over several steps, so also watch the car's own
	# horizontal velocity change over a short window.
	var vel := car.linear_velocity
	vel.y = 0.0
	v.jolt = v.jolt * exp(-delta / 0.25) + (vel - v.prev_vel).length()
	v.prev_vel = vel
	if v.jolt > JOLT_CRASH and _car_near(v.position, car, 7.0):
		if _react_to_hit(v, v.jolt, SHUNT_DV, "collision (dv %.1f)" % v.jolt):
			return
	var lat := Vector2(v.position.x, v.position.z).distance_to(_flat(v.path_point(0.0)))
	v.offlane = lat > 2.6
	v.offlane_t = v.offlane_t + delta if lat > 4.5 else 0.0
	v.flip_t = v.flip_t + delta if car.global_transform.basis.y.y < 0.4 else 0.0
	var wants_to_move := v.v_target > 3.0 and v.lead_gap > 12.0
	v.stuck_t = v.stuck_t + delta if wants_to_move and v.speed < 0.6 else 0.0
	if v.flip_t > 2.0:
		_start_hazard(v, true, "flip")
	elif v.offlane_t > 3.0:
		_start_hazard(v, false, "offlane")
	elif v.stuck_t > 8.0:
		_start_hazard(v, false, "stuck")


func _flat(p: Vector3) -> Vector2:
	return Vector2(p.x, p.z)


func _on_car_impact(strength: float, pos: Vector3, car: CarController) -> void:
	var v: TrafficVehicle = _car_owner.get(car)
	if v == null or v.hazard:
		return
	# Crashes involve another car or a solid prop. Road/terrain-only bumps (kerbs, seams, landings) are left
	# to the flip / off-lane / stuck checks.
	var solid := _car_near(pos, car)
	for b in car.get_colliding_bodies():
		if not (b.has_meta(&"surface") or b.has_meta(&"terrain")):
			solid = true
	if debug and strength >= 2.0:
		var names: PackedStringArray = []
		for b2 in car.get_colliding_bodies():
			names.append(str(b2.name) + ("(road)" if b2.has_meta(&"surface") else ("(terrain)" if b2.has_meta(&"terrain") else "")))
		print("[traffic] impact %.1f on #%d %s %s since promotion %.2f s, touching %s, y %.2f" % [strength, v.uid, v.data.id,
			("conn %d c=%.1f" % [v.conn.id, v.c]) if v.conn != null else ("%s s=%.0f" % [v.lane.road.id, v.s]),
			(Time.get_ticks_msec() - v.promoted_ms) / 1000.0, str(names), car.global_position.y])
		_debug_impact_probe.call_deferred(pos)
	if solid and strength >= STRONG_IMPACT:
		_react_to_hit(v, strength, SHUNT_IMPACT, "impact %.1f" % strength)
	elif pos.distance_to(_player_pos) < 6.0 and v.honk_cd <= 0.0:
		_honk(v)
		v.honk_cd = 5.0


## Response in proportion to a hit: a knock below `shunt_max` that leaves the car upright, straight and in its
## lane is a shunt (it brakes in lane, honks at the player, carries on); anything harder starts hazard mode.
## Returns true when hazard mode started.
func _react_to_hit(v: TrafficVehicle, severity: float, shunt_max: float, reason: String) -> bool:
	var car := v.car
	var q := v.path_point(0.0)
	var lane_dir := v.path_point(6.0) - q
	lane_dir.y = 0.0
	var straight := v.heading.dot(lane_dir.normalized()) > 0.94 and _flat(q).distance_to(_flat(v.position)) < 1.6
	if severity < shunt_max and straight and car.global_transform.basis.y.y > 0.9:
		v.jolt = 0.0
		if v.shaken_t > 0.0:
			return false
		v.shaken_t = 1.6 + severity * 0.25
		v.shaken_v = v.speed
		v.shaken_floor = v.speed * clampf(1.05 - severity * 0.09, 0.4, 0.8)
		_counters["shunts"] += 1
		if debug:
			print("[traffic] shunt #%d %s: %s at %.0f km/h -> brakes to %.0f km/h in lane" % [v.uid, v.data.id, reason, v.speed * 3.6, v.shaken_floor * 3.6])
		if v.position.distance_to(_player_pos) < 12.0 and v.honk_cd <= 0.0:
			_honk(v)
			v.honk_cd = 5.0
		return false
	_start_hazard(v, false, reason, clampf(0.3 + severity * 0.04, 0.35, 0.7))
	return true


func _car_near(pos: Vector3, except: CarController, radius := 4.0) -> bool:
	var pc := Game.player_car
	if pc != null and is_instance_valid(pc) and pc != except and pc.global_position.distance_to(pos) < radius:
		return true
	for o in _ai_cars:
		if is_instance_valid(o) and o != except and (o as CarController).global_position.distance_to(pos) < radius:
			return true
	for v: TrafficVehicle in vehicles:
		if v.car != null and v.car != except and v.position.distance_to(pos) < radius:
			return true
	return false


func _debug_impact_probe(pos: Vector3) -> void:
	var q := PhysicsShapeQueryParameters3D.new()
	var sph := SphereShape3D.new()
	sph.radius = 0.6
	q.shape = sph
	q.transform = Transform3D(Basis(), pos)
	q.collision_mask = 0xFFFF
	var names: PackedStringArray = []
	for hit: Dictionary in get_world_3d().direct_space_state.intersect_shape(q, 8):
		var col: Object = hit["collider"]
		names.append(str((col as Node).get_path()).right(60))
	print("[traffic]   bodies at impact point %s: %s" % [str(pos.snapped(Vector3.ONE * 0.01)), str(names)])


func _start_hazard(v: TrafficVehicle, wrecked: bool, reason: String, brake := 0.5) -> void:
	if v.hazard:
		return
	v.hazard_brake = brake
	v.shaken_t = 0.0
	if debug:
		var rel := _player_pos - v.position
		print("[traffic] hazard #%d %s: %s at %s (%.0f m from player, player %.1f m %s, lateral %.1f, player %.0f km/h, car %.0f km/h, lead %.1f m%s)" % [
			v.uid, v.data.id, reason, str(v.position.round()), v.position.distance_to(_player_pos), absf(rel.dot(v.heading)),
			"ahead" if rel.dot(v.heading) > 0.0 else "behind", rel.dot(v.heading.cross(Vector3.UP).normalized()), _player_vel.length() * 3.6,
			v.speed * 3.6, v.lead_gap, " (player)" if v.lead_is_player else ""])
		if v.car != null:
			var hits: PackedStringArray = []
			for b in v.car.get_colliding_bodies():
				hits.append(str(b.get_path()).right(60))
			print("[traffic]   thr %.2f brk %.2f hb %.1f steer %.2f gear %d rpm %.0f fwd %.2f wheels %d tgt %.1f cap %.1f follow %.1f hits %s" % [
				v.car.in_throttle, v.car.in_brake, v.car.in_handbrake, v.car.in_steer, v.car.gear, v.car.rpm, v.car.forward_speed,
				v.car.wheels_on_ground, v.v_target, v.speed_cap, v.follow_limit, str(hits)])
	v.hazard = true
	v.wreck = wrecked
	v.recovering = false
	v.hazard_t = 0.0
	v.recover_after = _rng.randf_range(4.5, 7.0)
	v.decision = null
	v.choice = null
	_counters["hazards"] += 1


func _update_hazard(v: TrafficVehicle, delta: float) -> void:
	v.hazard_t += delta
	var car := v.car
	v.speed = maxf(car.forward_speed, 0.0) if v.recovering else 0.0
	if v.conn == null:
		v.s = v.project_lane(v.position, v.s)
	var q := v.path_point(0.0)
	var lat := _flat(q).distance_to(_flat(v.position))
	v.offlane = lat > 2.6
	if v.wreck:
		return
	var up_y := car.global_transform.basis.y.y
	var upright := up_y > 0.85 and car.wheels_on_ground >= 3
	if up_y < 0.4 and v.hazard_t > 3.0:
		v.wreck = true
		v.recovering = false
		return
	if not v.recovering:
		if v.hazard_t < v.recover_after:
			return
		if upright and car.speed_ms < 1.0 and v.position.distance_to(_player_pos) > 9.0 and v.recoveries < 2:
			# Hazard pause over: drive slowly back onto the lane.
			v.recovering = true
			v.recover_t = 0.0
			v.recoveries += 1
		elif v.hazard_t > v.recover_after + 10.0:
			v.wreck = true
		return
	v.recover_t += delta
	var along := (v.path_point(6.0) - q).normalized()
	if lat < 1.2 and v.heading.dot(along) > 0.85:
		v.hazard = false
		v.recovering = false
		v.offlane_t = 0.0
		v.stuck_t = 0.0
		v.flip_t = 0.0
		_counters["recovered"] += 1
	elif v.recover_t > 12.0 or up_y < 0.7:
		v.recovering = false
		v.wreck = true


func _update_lod() -> void:
	var n_phys := 0
	var near: Array = []
	var phys: Array = []
	for v: TrafficVehicle in vehicles:
		var d := v.position.distance_to(_player_pos)
		if v.mode == TrafficVehicle.Mode.PHYSICS:
			if not v.hazard and d > PHYSICS_OUT:
				_to_kinematic(v)
			else:
				n_phys += 1
				if not v.hazard:
					phys.append([d, v])
		elif d < PHYSICS_IN:
			near.append([d, v])
	near.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	phys.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	var swaps := 0
	for item: Array in near:
		if n_phys >= MAX_PHYSICS:
			# Budget full: the nearest cars matter most (the player can reach them), so a clearly nearer
			# kinematic car takes the slot of the farthest physics car.
			if swaps >= MAX_SWAPS or phys.is_empty() or float(phys[0][0]) < float(item[0]) + SWAP_MARGIN:
				break
			_to_kinematic(phys.pop_front()[1])
			n_phys -= 1
			swaps += 1
			_counters["slot_swaps"] += 1
		if _to_physics(item[1]):
			n_phys += 1
	# Kinematic vehicles near the player stay solid: the ones without a slot, blocked promotions, demotions.
	for v2: TrafficVehicle in vehicles:
		var solid := v2.mode == TrafficVehicle.Mode.KINEMATIC and v2.position.distance_squared_to(_player_pos) < KIN_SOLID_DIST * KIN_SOLID_DIST
		if solid and v2.body == null:
			_take_body(v2)
		elif not solid and v2.body != null:
			_release_body(v2)


func _to_physics(v: TrafficVehicle) -> bool:
	var xf := v.kinematic_transform()
	var space := get_world_3d().direct_space_state
	# Highest ground under the nose, centre and tail: never start a body inside a road seam or kerb.
	var ground := -INF
	for f: float in [-0.35, 0.0, 0.35]:
		var at := xf.origin - xf.basis.z * (v.length * f)
		var q := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 3.0, at - Vector3.UP * 4.0, 1)
		var hit := space.intersect_ray(q)
		if not hit.is_empty():
			ground = maxf(ground, (hit["position"] as Vector3).y)
	if ground == -INF:
		_counters["skipped_no_ground"] += 1
		return false
	# Never materialise a body inside another car (the vehicle's own kinematic collider aside).
	_promo_shape.size = Vector3(v.half_width * 2.0, 1.2, v.length) * 0.95
	_promo_query.shape = _promo_shape
	_promo_query.transform = Transform3D(xf.basis, xf.origin + xf.basis.y * 0.9)
	_promo_query.collision_mask = 2 | 4
	var own: Array[RID] = []
	if v.body != null:
		own.append(v.body.get_rid())
	_promo_query.exclude = own
	var blocked := not space.intersect_shape(_promo_query, 1).is_empty()
	own.clear()
	_promo_query.exclude = own
	if blocked:
		_counters["promotion_blocked"] += 1
		return false
	_release_body(v)
	var car := _take_car(v.type_index, v.paint)
	xf.origin.y = ground + 0.12
	car.place_at(xf)
	car.linear_velocity = -xf.basis.z * v.speed
	_match_gear(car, v.speed)
	car.headlights_on = _lit(v)
	_car_owner[car] = v
	v.promoted_ms = Time.get_ticks_msec()
	v.prev_vel = Vector3(car.linear_velocity.x, 0.0, car.linear_velocity.z)
	v.jolt = 0.0
	_release_visual(v.type_index, v.visual as MeshInstance3D)
	v.visual = null
	v.car = car
	v.mode = TrafficVehicle.Mode.PHYSICS
	v.offlane_t = 0.0
	v.stuck_t = 0.0
	v.flip_t = 0.0
	_counters["promotions"] += 1
	return true


func _to_kinematic(v: TrafficVehicle) -> void:
	v.speed = maxf(v.car.forward_speed, 0.0)
	_release_car(v.type_index, v.car)
	v.car = null
	v.mode = TrafficVehicle.Mode.KINEMATIC
	v.off = v.lane.offset + v.nudge if v.conn == null else v.off
	v.prev_lane = null
	# This frame is drawn before the next kinematic move: place the pooled mesh (it still has the transform
	# of its last owner) and set its lights now, or the car blinks out and a stale copy flashes elsewhere.
	v.visual = _take_visual(v.type_index, v.paint)
	var xf := v.kinematic_transform()
	v.visual.transform = xf
	v.position = xf.origin
	v.heading = -xf.basis.z
	v.light_state = -1
	_update_kin_lights(v, v.speed < 0.3 and v.v_target < 0.5)
	_counters["demotions"] += 1


func _match_gear(car: CarController, v: float) -> void:
	var d := car.data
	var r := car.wheels[0].radius if not car.wheels.is_empty() else 0.32
	var g := 1
	var rpm := d.idle_rpm
	for i in d.gear_ratios.size():
		g = i + 1
		rpm = v / r * d.gear_ratios[i] * d.final_drive * 60.0 / TAU
		if rpm < d.redline_rpm * 0.72:
			break
	car.gear = g
	car.rpm = clampf(rpm, d.idle_rpm, d.redline_rpm)
	for w in car.wheels:
		w.omega = v / w.radius


# ----------------------------------------------------------------- spawning / despawning

func _update_target() -> void:
	var w := Game.world as World
	var c := w.data.region_weights_at(_player_pos.x, _player_pos.z)
	var sum := c.r + c.g + c.b + c.a
	var rf := 1.0
	if sum > 0.01:
		rf = (c.r * REGION_FACTOR[0] + c.g * REGION_FACTOR[1] + c.b * REGION_FACTOR[2] + c.a * REGION_FACTOR[3]) / sum
	var night := _night_amount(Game.get_time_of_day())
	_night = Game.env.is_night() if Game.env != null and Game.env.has_method("is_night") else night > 0.5
	var tf := lerpf(1.0, NIGHT_FACTOR, night)
	_road_km = graph.road_km_near(_player_pos, SPAWN_MAX)
	var dens := effective_density()
	var want := dens * BASE_COUNT * rf * tf
	_target = mini(int(round(minf(want, _road_km * MAX_PER_KM))), MAX_VEHICLES)
	if dens > 0.0 and _road_km > 0.3:
		_target = maxi(_target, 3)
	_update_spawn_cells()


## Vehicle lights follow the environment's light-needed signal (dusk, night, fog / rain / storm). Its tunnel
## part describes the camera, not the open road: while the camera is in a tunnel the outside state is kept
## (vehicles in tunnels light up on their own, see _lit).
func _update_lights(delta: float) -> void:
	var env: Node = Game.env
	if env == null:
		_lights = _night_amount(Game.get_time_of_day()) > 0.5
		return
	if env.has_method("is_in_tunnel") and bool(env.call("is_in_tunnel")):
		_cam_tunnel_hold = 1.0
		if env.has_method("is_night"):
			_lights = _lights or bool(env.call("is_night"))
		return
	if _cam_tunnel_hold > 0.0:
		# The environment's tunnel blend fades out over ~0.5 s after the portal.
		_cam_tunnel_hold -= delta
		return
	if env.has_method("lights_needed"):
		_lights = bool(env.call("lights_needed"))
	elif env.has_method("is_night"):
		_lights = bool(env.call("is_night"))


static func _night_amount(h: float) -> float:
	if h >= 7.0 and h <= 19.0:
		return 0.0
	if h < 5.0 or h > 21.0:
		return 1.0
	return (7.0 - h) * 0.5 if h < 7.0 else (h - 19.0) * 0.5


func _spawn_pass() -> void:
	if vehicles.size() >= _target:
		return
	var filling := _fill > 0.0
	var attempts := 40 if filling else 3
	var budget := 8 if filling else 1
	for i in attempts:
		if vehicles.size() >= _target or budget <= 0:
			break
		if _try_spawn(filling):
			budget -= 1


## Spawn sampling, rebuilt each second: the 100 m cells around the player weighted by lane length (a 2+2-lane
## road gets twice the share of a 1+1 road per metre), cells ahead of a moving player three times as much.
## [cumulative weight, cell] for a fill (from 60 m) and for normal spawns (from SPAWN_MIN).
func _update_spawn_cells() -> void:
	_spawn_cells_fill.clear()
	_spawn_cells.clear()
	var g := LaneGraph.GRID
	var c := Vector2i(floori(_player_pos.x / g), floori(_player_pos.z / g))
	var n := int(ceil(SPAWN_MAX / g)) + 1
	var hv := Vector2(_player_vel.x, _player_vel.z)
	var moving := hv.length() > 8.0
	var hdir := hv.normalized() if moving else Vector2.ZERO
	var tot_f := 0.0
	var tot := 0.0
	for dz in range(-n, n + 1):
		for dx in range(-n, n + 1):
			var k := c + Vector2i(dx, dz)
			var wgt: float = graph.lane_grid.get(k, 0.0)
			if wgt <= 0.0:
				continue
			var rel := Vector2((k.x + 0.5) * g - _player_pos.x, (k.y + 0.5) * g - _player_pos.z)
			var dist := rel.length()
			if dist > SPAWN_MAX + g * 0.71:
				continue
			if moving:
				wgt *= 1.0 + 2.0 * maxf(rel.normalized().dot(hdir), 0.0)
			tot_f += wgt
			_spawn_cells_fill.append([tot_f, k])
			if dist + g * 0.71 >= SPAWN_MIN:
				tot += wgt
				_spawn_cells.append([tot, k])


func _pick_cell(cells: Array) -> Vector2i:
	var r := _rng.randf() * float(cells[cells.size() - 1][0])
	var lo := 0
	var hi := cells.size() - 1
	while lo < hi:
		var mid := (lo + hi) >> 1
		if float(cells[mid][0]) < r:
			lo = mid + 1
		else:
			hi = mid
	return cells[lo][1]


func _try_spawn(filling: bool) -> bool:
	var dmin := 60.0 if filling else SPAWN_MIN
	var cells := _spawn_cells_fill if filling else _spawn_cells
	if cells.is_empty():
		return false
	var samples: PackedInt32Array = graph.sample_grid.get(_pick_cell(cells), PackedInt32Array())
	if samples.is_empty():
		return false
	var code := samples[_rng.randi() % samples.size()]
	var road: RoadNetwork.Road = graph.network.roads[code >> 16]
	var s := minf(((code & 0xFFFF) + _rng.randf()) * road.ds, road.length - 0.01)
	var lanes: Array = []
	for l: LaneGraph.Lane in graph.lanes_of(road):
		if l.dead_end:
			continue
		if not road.loop and (l.ahead(l.s_begin, s) < 12.0 or l.remaining(s) < 25.0):
			continue
		var w := 1.0 if l.outer else 0.45
		lanes.append([w, l])
	if lanes.is_empty():
		return false
	var lane: LaneGraph.Lane = _weighted(lanes)
	var lp := lane.point(s, lane.offset)
	var dp := _flat(lp).distance_to(_flat(_player_pos))
	if dp < dmin or dp > SPAWN_MAX:
		return false
	for j: LaneGraph.Junction in graph.junctions:
		if j.center.distance_squared_to(lp) < 14400.0:
			return false
	if _in_view(lp) and not (dp > SPAWN_FAR_VISIBLE or _occluded(lp) or (filling and dp > 120.0)):
		return false
	for w2: TrafficVehicle in vehicles:
		if w2.position.distance_to(lp) < 30.0:
			return false
	for w3: TrafficVehicle in _occ_lane.get(lane.id, _empty):
		if absf(lane.sdist(s, w3.s)) < 45.0:
			return false
	var region := (Game.world as World).data.region_at(lp.x, lp.z)
	var ti := _pick_type(road.cls, region, lane, s)
	if ti < 0:
		return false
	var v := _new_vehicle(ti, lane, s)
	_find_leader(v)
	if v.lead_gap < INF:
		v.speed = minf(v.speed, RoadFollower.follow_speed(v.lead_gap, v.lead_speed, v.speed, v.time_gap))
	_occ_add(_occ_lane, lane.id, v)
	return true


func _weighted(items: Array) -> Variant:
	var total := 0.0
	for it: Array in items:
		total += float(it[0])
	var r := _rng.randf() * total
	for it2: Array in items:
		r -= float(it2[0])
		if r <= 0.0:
			return it2[1]
	return items[items.size() - 1][1]


func _pick_type(cls: int, region: int, lane: LaneGraph.Lane, s: float) -> int:
	var items: Array = []
	for i in types.size():
		if types[i].allows(cls, region) and _piece_safe(i, lane, s):
			items.append([float(types[i].spawn_weight), i])
	if items.is_empty():
		return -1
	return int(_weighted(items))


func _new_vehicle(ti: int, lane: LaneGraph.Lane, s: float) -> TrafficVehicle:
	var t := types[ti]
	var v := TrafficVehicle.new()
	v.uid = _uid
	_uid += 1
	v.promoted_ms = Time.get_ticks_msec()
	v.type_index = ti
	v.data = t
	v.length = _models[ti]["length"]
	v.half_width = float(_models[ti]["width"]) * 0.5
	var pk: String = t.paints[_rng.randi() % t.paints.size()] if not t.paints.is_empty() else "white"
	var col: Color = Game.PAINT_COLORS.get(pk, Color.WHITE)
	var shade := _rng.randf_range(-0.07, 0.07)
	col = col.lightened(shade) if shade > 0.0 else col.darkened(-shade)
	v.paint = {"color": col, "finish": t.finishes[_rng.randi() % t.finishes.size()] if not t.finishes.is_empty() else 0, "stripes": 0}
	v.enter_lane(lane, s)
	v.v_desired = minf(lane.limit * float(t.limit_factor) * _rng.randf_range(0.9, 1.08), float(t.max_speed_kmh) / 3.6)
	v.corner_factor = sqrt(float(t.corner_g) * 9.81 / LaneGraph.LAT_COMFORT) * _rng.randf_range(0.95, 1.05)
	v.time_gap = float(t.time_gap) + _rng.randf_range(0.0, 0.5)
	v.speed = minf(v.v_desired, lane.speed_at(s) * v.corner_factor) * 0.9
	v.follower = RoadFollower.new()
	v.follower.road = lane.road
	v.follower.target_fn = v.path_point
	v.follower.max_throttle = 0.7
	v.follower.look_base = 4.5
	v.follower.look_gain = 0.45
	v.follower.respect_traffic = false
	v.visual = _take_visual(ti, v.paint)
	var xf := v.kinematic_transform()
	v.visual.transform = xf
	v.position = xf.origin
	v.heading = -xf.basis.z
	vehicles.append(v)
	_counters["spawned"] += 1
	return v


func _despawn_pass() -> void:
	var over := vehicles.size() > _target
	var moving := Vector2(_player_vel.x, _player_vel.z).length() > 8.0
	for i in range(vehicles.size() - 1, -1, -1):
		var v: TrafficVehicle = vehicles[i]
		var d := v.position.distance_to(_player_pos)
		var kill := d > DESPAWN
		if not kill and v.hazard:
			kill = (v.wreck and v.unseen_t > 6.0) or (d > PHYSICS_OUT and v.unseen_t > 2.0)
			if kill and v.wreck:
				_counters["wrecks_removed"] += 1
		var behind := (v.position - _player_pos).dot(_cam_fwd) < 0.0
		if not kill and over and d > 350.0 and v.unseen_t > 1.0 and behind:
			kill = true
			over = vehicles.size() - 1 > _target
		if not kill and moving and _recycle_t <= 0.0 and d > RECYCLE_DIST and v.unseen_t > 2.0 and behind:
			# Left behind a moving player and not catching up: its slot is worth more ahead (the spawn pass
			# weights the road ahead), or the budget sits in cars nobody will see again.
			var closing := (v.heading * v.speed - _player_vel).dot((_player_pos - v.position).normalized())
			if closing < 1.5:
				kill = true
				_recycle_t = 0.5
				_counters["recycled"] += 1
		if not kill and v.conn == null and v.choice == null and not v.lane.road.loop and v.lane.remaining(v.s) < 8.0 and v.unseen_t > 1.0:
			kill = true
		if not kill and v.leaving and v.unseen_t > 1.0 and (d > 60.0 or v.speed < 0.5):
			kill = true
		if kill:
			_despawn(v, i)


func _despawn(v: TrafficVehicle, index: int) -> void:
	if v.car != null:
		_release_car(v.type_index, v.car)
		v.car = null
	if v.visual != null:
		_release_visual(v.type_index, v.visual as MeshInstance3D)
		v.visual = null
	_release_body(v)
	v.follower = null
	vehicles.remove_at(index)
	_counters["despawned"] += 1


func _flush_all() -> void:
	for i in range(vehicles.size() - 1, -1, -1):
		_despawn(vehicles[i], i)


func _update_physics_points() -> void:
	var w := Game.world as World
	var pts := w.extra_physics_points
	for p in _phys_points:
		var i := pts.find(p)
		if i >= 0:
			pts.remove_at(i)
	_phys_points.clear()
	# Cars inside the player's own collider zone need no extra point (extra points only cause collider churn).
	for v: TrafficVehicle in vehicles:
		if v.mode == TrafficVehicle.Mode.PHYSICS and v.position.distance_to(_player_pos) > PHYSICS_POINT_MIN:
			_phys_points.append(v.position)
	pts.append_array(_phys_points)


# ----------------------------------------------------------------- parked cars

## Kerbside parking on village / harbour streets: deterministic slots, streamed in near the player.
func _plan_parked(w: World) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7171
	var spots: Array[Vector2] = []
	for poi: Dictionary in w.data.pois():
		if String(poi.get("kind", "")) in PARKED_POI_KINDS:
			spots.append(Vector2(float(poi["pos"][0]), float(poi["pos"][1])))
	var kinds: Array = []
	for ti in types.size():
		if String(types[ti].id) in PARKED_TYPES:
			kinds.append([1.0 if types[ti].id == "hatch_small" else 0.45, ti])
	if kinds.is_empty():
		return
	for r in graph.network.roads:
		if not r.traffic or r.cls != WorldLayout.RoadClass.STREET or r.loop:
			continue
		# Inner edge of a parked car must stay clear of the widest vehicle that may pass in the lane.
		var passing := 0.0
		for ti2 in types.size():
			if types[ti2].allowed_classes.has(r.cls):
				passing = maxf(passing, float(_models[ti2]["width"]) * 0.5)
		var keep_out := r.lane_offset(r.lanes) + passing + PARK_CLEARANCE
		var ss := 26.0
		while ss < r.length - 26.0:
			var p := r.point_at(ss)
			var near := false
			for c in spots:
				near = near or c.distance_to(Vector2(p.x, p.z)) < 230.0
			if near and rng.randf() < 0.6:
				var side := 1 if rng.randf() < 0.5 else -1
				var ti: int = _weighted(kinds)
				var t := types[ti]
				var pk: String = t.paints[rng.randi() % t.paints.size()]
				var finish: int = t.finishes[rng.randi() % t.finishes.size()]
				# All four wheels on the paved shoulder (the asphalt and its collider end at width/2 + shoulder;
				# beyond it the verge falls away), body pitched and rolled with the street like moving traffic.
				var cd: CarData = _models[ti]["car_data"]
				var half_w := float(_models[ti]["width"]) * 0.5
				var off := r.width * 0.5 + r.shoulder - maxf(cd.track_front, cd.track_rear) * 0.5 - 0.05
				var xf := TrafficVehicle.road_transform(r, ss, off * side, side)
				var other := graph.network.nearest(xf.origin, 10.0, func(rr: RoadNetwork.Road) -> bool: return rr != r)
				if other.is_empty() and off - half_w >= keep_out:
					_parked.append({"pos": xf.origin, "basis": xf.basis, "type": ti, "blocked": false,
						"paint": {"color": Game.PAINT_COLORS.get(pk, Color.WHITE), "finish": finish}})
			ss += rng.randf_range(9.0, 17.0)
	print("[traffic] %d kerbside parking slots" % _parked.size())


func _update_parked() -> void:
	for slot: Dictionary in _parked:
		if slot["blocked"]:
			continue
		var d := (slot["pos"] as Vector3).distance_to(_player_pos)
		var vis: MeshInstance3D = slot.get("vis")
		if vis == null and d < PARKED_IN:
			_spawn_parked(slot)
		elif vis != null and d > PARKED_OUT:
			_release_visual(slot["type"], vis)
			var body: StaticBody3D = slot["body"]
			(body.get_child(0) as CollisionShape3D).disabled = true
			_parked_bodies.append(body)
			slot.erase("vis")
			slot.erase("body")


func _spawn_parked(slot: Dictionary) -> void:
	var ti: int = slot["type"]
	var size := Vector3(float(_models[ti]["width"]), 1.3, float(_models[ti]["length"]))
	var xf := Transform3D(slot["basis"], slot["pos"])
	# Never park inside a settlement prop (lamp posts, benches...).
	_promo_shape.size = size * Vector3(0.95, 1.0, 0.95)
	_promo_query.shape = _promo_shape
	_promo_query.transform = Transform3D(xf.basis, xf.origin + xf.basis.y * 0.9)
	var space := get_world_3d().direct_space_state
	_promo_query.collision_mask = 1 | 32
	for hit: Dictionary in space.intersect_shape(_promo_query, 4):
		var col: Object = hit["collider"]
		if not ((col.has_meta(&"surface") and String(col.get_meta(&"road", "")) != "") or col.has_meta(&"terrain")):
			slot["blocked"] = true
			return
	_promo_query.collision_mask = 2 | 4
	if not space.intersect_shape(_promo_query, 1).is_empty():
		return
	var vis := _take_visual(ti, slot["paint"])
	vis.transform = xf
	var body: StaticBody3D = _parked_bodies.pop_back() if not _parked_bodies.is_empty() else null
	if body == null:
		body = StaticBody3D.new()
		body.collision_layer = 4
		body.collision_mask = 0
		var cs := CollisionShape3D.new()
		cs.shape = BoxShape3D.new()
		body.add_child(cs)
		add_child(body)
	var cs2 := body.get_child(0) as CollisionShape3D
	cs2.disabled = false
	(cs2.shape as BoxShape3D).size = Vector3(size.x * 0.92, 1.0, size.z * 0.95)
	body.transform = _body_transform(xf)
	slot["vis"] = vis
	slot["body"] = body


# ----------------------------------------------------------------- view helpers

func _camera() -> Camera3D:
	var rig: Node = Game.camera_rig
	if rig == null:
		return null
	var cam: Variant = rig.get("camera")
	return cam as Camera3D


func _in_view(p: Vector3) -> bool:
	var cam := _camera()
	return cam != null and cam.is_position_in_frustum(p + Vector3.UP * 1.2)


## Terrain line-of-sight test from the camera (height field only: colliders exist only near the player).
func _occluded(p: Vector3) -> bool:
	var cam := _camera()
	if cam == null:
		return true
	var a := cam.global_position
	var b := p + Vector3.UP * 1.5
	var data := (Game.world as World).data
	for i in range(1, 12):
		var q := a.lerp(b, i / 12.0)
		if data.height_at(q.x, q.z) > q.y + 0.5:
			return true
	return false


# ----------------------------------------------------------------- horn

func _honk(v: TrafficVehicle) -> void:
	_counters["honks"] += 1
	if v.car != null:
		var a := v.car.get_node_or_null("CarAudio")
		if a != null and a.has_method("honk"):
			a.call("honk")
			return
	var player: AudioStreamPlayer3D = _horns[0]
	for h in _horns:
		if not h.playing:
			player = h
			break
	player.stream = _horn_stream(float(v.data.horn_hz))
	player.global_position = v.position + Vector3.UP
	player.play()


## Procedural two-tone horn (a major third, soft-clipped), cached per pitch.
func _horn_stream(hz: float) -> AudioStreamWAV:
	var key := int(hz)
	if _horn_streams.has(key):
		return _horn_streams[key]
	var rate := 22050
	var dur := 0.62
	var n := int(rate * dur)
	var bytes := PackedByteArray()
	bytes.resize(n * 2)
	for i in n:
		var t := float(i) / rate
		var env := minf(t / 0.025, 1.0) * minf((dur - t) / 0.08, 1.0)
		var vib := 1.0 + 0.004 * sin(TAU * 5.5 * t)
		var x := tanh(2.6 * sin(TAU * hz * vib * t)) + 0.8 * tanh(2.6 * sin(TAU * hz * 1.26 * vib * t))
		bytes.encode_s16(i * 2, int(clampf(x * env * 0.42, -1.0, 1.0) * 32767.0))
	var st := AudioStreamWAV.new()
	st.format = AudioStreamWAV.FORMAT_16_BITS
	st.mix_rate = rate
	st.stereo = false
	st.data = bytes
	_horn_streams[key] = st
	return st


# ----------------------------------------------------------------- stats / debug

func _update_stats(ms: float) -> void:
	var n_phys := 0
	var waiting := 0
	var hazards := 0
	var speed_sum := 0.0
	var min_gap := INF
	var close := 0
	var by_type := {}
	for v: TrafficVehicle in vehicles:
		if v.mode == TrafficVehicle.Mode.PHYSICS:
			n_phys += 1
		if v.hazard:
			hazards += 1
		if v.wait_t > 0.5:
			waiting += 1
		speed_sum += v.speed
		if v.lead_gap < INF and not v.lead_is_player and v.speed > 3.0:
			min_gap = minf(min_gap, v.lead_gap)
			if v.lead_gap / maxf(v.speed, 0.1) < 1.2 and v.lead_speed < v.speed + 0.5:
				close += 1
		var id: String = v.data.id
		by_type[id] = int(by_type.get(id, 0)) + 1
	var pool_v := 0
	var pool_c := 0
	for p: Array in _visual_pool:
		pool_v += p.size()
	for p2: Array in _car_pool:
		pool_c += p2.size()
	stats = {
		"active": vehicles.size(), "physics": n_phys, "kinematic": vehicles.size() - n_phys, "target": _target,
		"density": effective_density(), "density_setting": _density, "ai_cars": _ai_cars.size(), "road_km": snappedf(_road_km, 0.1), "night": _night, "lights": _lights, "waiting": waiting, "hazards_now": hazards,
		"avg_kmh": snappedf(speed_sum / maxf(vehicles.size(), 1) * 3.6, 0.1),
		"min_gap_m": snappedf(min_gap, 0.1) if min_gap < INF else -1.0, "close_followers": close,
		"pool_visuals": pool_v, "pool_cars": pool_c, "update_ms": snappedf(ms, 0.01), "types": by_type,
		"placeholder_models": _placeholder_count(), "parked": _parked_count(),
	}
	stats.merge(_counters)


func _count_nodes(n: Node) -> int:
	var c := 1
	for ch in n.get_children():
		c += _count_nodes(ch)
	return c


func _placeholder_count() -> int:
	var n := 0
	for info: Dictionary in _models:
		if info["placeholder"]:
			n += 1
	return n


func _parked_count() -> int:
	var n := 0
	for slot: Dictionary in _parked:
		if slot.has("vis"):
			n += 1
	return n


func _print_debug() -> void:
	var line := stats.duplicate()
	line["nodes"] = Performance.get_monitor(Performance.OBJECT_NODE_COUNT)
	var own := _count_nodes(self)
	for pool: Array in _car_pool:
		for car: CarController in pool:
			own += _count_nodes(car)
	line["own_nodes"] = own
	line["fps"] = Engine.get_frames_per_second()
	var nf := maxf(float(_prof["frames"]), 1.0)
	line["prof_us"] = {"pre": int(_prof["pre"] / nf), "plan": int(_prof["plan"] / nf), "move": int(_prof["move"] / nf), "rest": int(_prof["rest"] / nf)}
	for k: String in _prof.keys():
		_prof[k] = 0
	print("[traffic] ", JSON.stringify(line))
	var shown := 0
	for v: TrafficVehicle in vehicles:
		if shown >= 6:
			break
		if v.position.distance_to(_player_pos) > 260.0:
			continue
		shown += 1
		var where := ("conn %d c=%.0f/%.0f" % [v.conn.id, v.c, v.conn.length]) if v.conn != null else ("%s dir %d k%d s=%.0f" % [v.lane.road.id, v.lane.dir, v.lane.k, v.s])
		print("[traffic]   #%d %s %s %s %.0f km/h tgt %.0f lead %s dist %.0f m%s%s" % [v.uid, v.data.id,
			"PHYS" if v.mode == TrafficVehicle.Mode.PHYSICS else "kin", where, v.speed * 3.6, v.v_target * 3.6,
			("%.0f m" % v.lead_gap) if v.lead_gap < INF else "-", v.position.distance_to(_player_pos),
			" WAIT" if v.wait_t > 0.5 else "", " HAZARD" if v.hazard else ""])
