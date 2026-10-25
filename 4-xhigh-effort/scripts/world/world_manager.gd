extends Node3D
## Open-world root: loads the baked WorldData and owns terrain streaming, roads, water,
## dressing, buildings/landmarks, boundary and map queries used by gameplay systems.

const TERRAIN_SHADER := preload("res://assets/shaders/terrain.gdshader")
const ROAD_SHADER := preload("res://assets/shaders/road.gdshader")
const WATER_SHADER := preload("res://assets/shaders/water.gdshader")

var wd: WorldData
var terrain: TerrainStreamer
var roads: RoadNetwork
var dressing: Node3D
var kit: Node
var structures: Node3D
var noise_tex: NoiseTexture2D
var noise_nrm: NoiseTexture2D
var terrain_mat: ShaderMaterial
var water_mat: ShaderMaterial
var river_mat: ShaderMaterial
var load_ms := 0
var graph: RoadGraph
var map_texture: Texture2D


func _ready() -> void:
	var t0 := Time.get_ticks_msec()
	wd = load(WorldData.resolve_path()) as WorldData
	_make_textures()
	kit = (load("res://scripts/world/kit_library.gd") as GDScript).new()
	kit.name = "Kit"
	add_child(kit)
	terrain_mat = ShaderMaterial.new()
	terrain_mat.shader = TERRAIN_SHADER
	terrain_mat.set_shader_parameter("control_map", ImageTexture.create_from_image(wd.control_img))
	terrain_mat.set_shader_parameter("detail_map", ImageTexture.create_from_image(wd.detail_img))
	terrain_mat.set_shader_parameter("noise_tex", noise_tex)
	terrain_mat.set_shader_parameter("noise_nrm", noise_nrm)
	terrain_mat.set_shader_parameter("half_size", wd.half)
	terrain = TerrainStreamer.new()
	terrain.name = "Terrain"
	add_child(terrain)
	terrain.setup(wd, terrain_mat)
	roads = RoadNetwork.new()
	roads.name = "Roads"
	add_child(roads)
	roads.setup(wd, ROAD_SHADER)
	for m: ShaderMaterial in roads.materials.values():
		m.set_shader_parameter("noise_tex", noise_tex)
		m.set_shader_parameter("noise_nrm", noise_nrm)
	_class_params()
	roads.build_all()
	graph = RoadGraph.new()
	graph.build(wd.roads)
	if wd.map_img != null:
		map_texture = ImageTexture.create_from_image(wd.map_img)
	_water()
	_boundary()
	_backdrop()
	var dscript := load("res://scripts/world/dressing.gd") as GDScript
	dressing = dscript.new()
	dressing.name = "Dressing"
	add_child(dressing)
	dressing.call("setup", self)
	var sscript := load("res://scripts/world/structures.gd") as GDScript
	if sscript != null:
		structures = sscript.new()
		structures.name = "Structures"
		add_child(structures)
		structures.call("setup", self)
	load_ms = Time.get_ticks_msec() - t0
	print("World ready in %d ms: %d road pieces, %.1f km roads" % [load_ms, roads.stats.pieces, float(wd.stats.get("road_km", 0.0))])


func _class_params() -> void:
	for r: Dictionary in wd.roads:
		var m: ShaderMaterial = roads.materials[String(r["class"])]
		m.set_shader_parameter("half_w", float(r.half_w))
		m.set_shader_parameter("lane_w", float(r.lane_w))
		m.set_shader_parameter("shoulder", float(r.shoulder))
		m.set_shader_parameter("median", float(r.median))


func _make_textures() -> void:
	var fn := FastNoiseLite.new()
	fn.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	fn.fractal_octaves = 5
	fn.frequency = 0.012
	fn.seed = 7
	noise_tex = NoiseTexture2D.new()
	noise_tex.width = 512
	noise_tex.height = 512
	noise_tex.seamless = true
	noise_tex.generate_mipmaps = true
	noise_tex.noise = fn
	var fn2 := FastNoiseLite.new()
	fn2.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	fn2.fractal_octaves = 4
	fn2.frequency = 0.03
	fn2.seed = 11
	noise_nrm = NoiseTexture2D.new()
	noise_nrm.width = 512
	noise_nrm.height = 512
	noise_nrm.seamless = true
	noise_nrm.as_normal_map = true
	noise_nrm.bump_strength = 6.0
	noise_nrm.generate_mipmaps = true
	noise_nrm.noise = fn2


func _water() -> void:
	water_mat = ShaderMaterial.new()
	water_mat.shader = WATER_SHADER
	water_mat.set_shader_parameter("noise_tex", noise_tex)
	water_mat.set_shader_parameter("noise_nrm", noise_nrm)
	var sea := MeshInstance3D.new()
	sea.name = "Sea"
	var pm := PlaneMesh.new()
	pm.size = Vector2(16000, 16000)
	pm.subdivide_width = 160
	pm.subdivide_depth = 160
	sea.mesh = pm
	sea.material_override = water_mat
	sea.position = Vector3(2000, wd.sea_level, 0)
	sea.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(sea)
	# river ribbon following the baked water level
	river_mat = ShaderMaterial.new()
	river_mat.shader = WATER_SHADER
	river_mat.set_shader_parameter("noise_tex", noise_tex)
	river_mat.set_shader_parameter("noise_nrm", noise_nrm)
	river_mat.set_shader_parameter("flow", 1.0)
	river_mat.set_shader_parameter("shallow_color", Color(0.12, 0.33, 0.3))
	var p2: PackedVector2Array = wd.river.p2
	var lv: PackedFloat32Array = wd.river.level
	var wdth: PackedFloat32Array = wd.river.width
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var s := 0.0
	for i in range(0, p2.size() - 1):
		var a := p2[i]
		var b := p2[i + 1]
		var d := (b - a).normalized()
		var rgt := Vector2(-d.y, d.x)
		var wa := wdth[i] + 3.0
		var wb := wdth[i + 1] + 3.0
		var ya := lv[i] - 0.25
		var yb := lv[i + 1] - 0.25
		var al := Vector3(a.x - rgt.x * wa, ya, a.y - rgt.y * wa)
		var ar := Vector3(a.x + rgt.x * wa, ya, a.y + rgt.y * wa)
		var bl := Vector3(b.x - rgt.x * wb, yb, b.y - rgt.y * wb)
		var br := Vector3(b.x + rgt.x * wb, yb, b.y + rgt.y * wb)
		var s2 := s + a.distance_to(b)
		for v: Array in [[al, Vector2(-wa, s)], [br, Vector2(wb, s2)], [ar, Vector2(wa, s)], [al, Vector2(-wa, s)], [bl, Vector2(-wb, s2)], [br, Vector2(wb, s2)]]:
			st.set_uv(v[1])
			st.set_normal(Vector3.UP)
			st.add_vertex(v[0])
		s = s2
	var river := MeshInstance3D.new()
	river.name = "River"
	river.mesh = st.commit()
	river.material_override = river_mat
	river.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(river)


func _boundary() -> void:
	var body := StaticBody3D.new()
	body.name = "Boundary"
	body.collision_layer = 1
	var e := wd.half - 30.0
	for spec: Array in [[Vector3(0, 0, -e), Vector3(4200, 600, 4)], [Vector3(0, 0, e), Vector3(4200, 600, 4)],
			[Vector3(-e, 0, 0), Vector3(4, 600, 4200)], [Vector3(e, 0, 0), Vector3(4, 600, 4200)]]:
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = spec[1]
		cs.shape = bs
		cs.position = spec[0]
		body.add_child(cs)
	add_child(body)


## Low-detail landscape ring outside the playable square so the horizon is never empty.
func _backdrop() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var fn := FastNoiseLite.new()
	fn.seed = 99
	fn.frequency = 0.0006
	fn.fractal_octaves = 4
	var radii := [0.0, 150.0, 600.0, 1500.0, 3000.0, 5500.0]
	var segs := 128
	var ring := []
	for ri in radii.size():
		var row := []
		for k in segs:
			var ang := TAU * k / segs
			var dir := Vector2(cos(ang), sin(ang))
			# point on the square boundary in this direction
			var sc := wd.half / maxf(absf(dir.x), absf(dir.y))
			var edge := dir * (sc - 2.0)
			var p := edge + dir * float(radii[ri])
			var he := wd.height_at(edge.x, edge.y)
			var hills := 60.0 + 220.0 * (fn.get_noise_2d(p.x, p.y) * 0.5 + 0.5)
			if he < 2.0:
				hills = -30.0
			var t := clampf(float(radii[ri]) / 1500.0, 0.0, 1.0)
			var h := lerpf(he, hills, t * t * (3.0 - 2.0 * t))
			row.append(Vector3(p.x, h - (0.5 if ri == 0 else 0.0), p.y))
		ring.append(row)
	for ri in radii.size() - 1:
		for k in segs:
			var a: Vector3 = ring[ri][k]
			var b: Vector3 = ring[ri][(k + 1) % segs]
			var c: Vector3 = ring[ri + 1][k]
			var d: Vector3 = ring[ri + 1][(k + 1) % segs]
			for v: Vector3 in [a, c, b, b, c, d]:
				st.add_vertex(v)
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.name = "Backdrop"
	mi.mesh = st.commit()
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.3, 0.36, 0.22)
	m.roughness = 1.0
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func _process(_delta: float) -> void:
	var focus := Vector3.ZERO
	if Game.player != null and is_instance_valid(Game.player):
		focus = Game.player.global_position
	elif Game.camera != null:
		focus = Game.camera.global_position
	terrain.focus = focus
	if dressing != null:
		dressing.set("focus", focus)


# ------------------------------------------------------------------ queries
func get_spawn() -> Transform3D:
	terrain.ensure_collision_at(wd.spawn.origin)
	return wd.spawn


func terrain_surface_at(p: Vector3) -> int:
	return wd.surface_at(p.x, p.z)


func height_at(x: float, z: float) -> float:
	return wd.height_at(x, z)


func region_at(p: Vector3) -> int:
	return wd.region_at(p.x, p.z)


func region_name(id: int) -> String:
	return String(wd.regions[id].name) if id >= 0 and id < wd.regions.size() else ""


func nearest_road_transform(p: Vector3) -> Transform3D:
	var n := roads.nearest(p, 2500.0)
	if n.is_empty():
		return wd.spawn
	var r: Dictionary = wd.roads[n.road]
	var pts: PackedVector3Array = r.pts
	var i: int = n.i
	# never respawn inside a tunnel or on a junction mouth
	var kind: PackedByteArray = r.kind
	var guard := 0
	while kind[i] == 2 and guard < 600:
		i = (i + 1) % pts.size()
		guard += 1
	var car_fwd := Vector3.FORWARD
	if Game.player != null:
		car_fwd = -Game.player.global_transform.basis.z
	var fwd_xf := roads.lane_transform(n.road, i, false)
	var reverse := (-fwd_xf.basis.z).dot(car_fwd) < 0.0
	var xf := roads.lane_transform(n.road, i, reverse)
	terrain.ensure_collision_at(xf.origin)
	return xf


func transform_near(p: Vector3) -> Transform3D:
	return nearest_road_transform(p)


var _ap_road := -1
var _ap_i := 0
var _ap_dir := 1


## Pure-pursuit autopilot for screenshot/benchmark drives. Locks onto one road and keeps to
## the right-hand lane in its travel direction.
func autopilot_steer(car: CarController) -> float:
	var p := car.global_position
	var fwd := -car.global_transform.basis.z
	if _ap_road < 0 or (wd.roads[_ap_road].pts as PackedVector3Array)[_ap_i].distance_to(p) > 60.0:
		var n := roads.nearest(p, 120.0)
		if n.is_empty():
			return 0.0
		_ap_road = n.road
		_ap_i = n.i
		var pts0: PackedVector3Array = wd.roads[_ap_road].pts
		var nx := mini(_ap_i + 2, pts0.size() - 1)
		_ap_dir = 1 if (pts0[nx] - pts0[_ap_i]).dot(fwd) >= 0.0 else -1
	var r: Dictionary = wd.roads[_ap_road]
	var pts: PackedVector3Array = r.pts
	var n2 := pts.size()
	var best := _ap_i
	var bd := 1e9
	for k in range(-6, 30):
		var j := _ap_i + k * _ap_dir
		j = (j + n2) % n2 if r.closed else clampi(j, 0, n2 - 1)
		var d := pts[j].distance_squared_to(p)
		if d < bd:
			bd = d
			best = j
	_ap_i = best
	var look := int(4 + car.speed_abs * 0.3)
	var ti := _ap_i + look * _ap_dir
	if not r.closed and (ti <= 0 or ti >= n2 - 1):
		_ap_dir = -_ap_dir
		ti = clampi(ti, 0, n2 - 1)
	ti = (ti + n2) % n2 if r.closed else clampi(ti, 0, n2 - 1)
	var xf := roads.lane_transform(_ap_road, ti, _ap_dir < 0)
	var tgt := xf.origin - p
	tgt.y = 0.0
	var ang := Vector3(fwd.x, 0, fwd.z).normalized().signed_angle_to(tgt.normalized(), Vector3.UP)
	# Stanley-style cross-track term against the lane centre at the nearest sample
	var here := roads.lane_transform(_ap_road, _ap_i, _ap_dir < 0)
	var lane_right := here.basis.x
	var cte := (p - here.origin).dot(lane_right)
	ang += atan(0.9 * cte / maxf(car.speed_abs, 3.0)) * 0.8
	# curvature ahead -> comfortable speed (lateral 4 m/s^2), used by autopilot_pedals()
	# the caller's cap limits the speed; the look-ahead grows with speed so braking starts in time
	var min_v := 95.0
	var ahead := clampi(60 + int(car.speed_abs * 3.0), 60, 240)
	for k in range(2, ahead, 4):
		var a := _ap_i + k * _ap_dir
		var b := a + 6 * _ap_dir
		var cc := b + 6 * _ap_dir
		if not r.closed and (mini(a, cc) < 0 or maxi(a, cc) >= n2):
			break
		var pa := pts[(a + n2) % n2]
		var pb := pts[(b + n2) % n2]
		var pc := pts[(cc + n2) % n2]
		var t1 := Vector2(pb.x - pa.x, pb.z - pa.z).normalized()
		var t2 := Vector2(pc.x - pb.x, pc.z - pb.z).normalized()
		var turn := absf(t1.angle_to(t2))
		var radius := 12.0 / maxf(turn, 0.0005)
		min_v = minf(min_v, sqrt(4.0 * radius) + k * 0.25)
	_ap_speed = min_v
	return clampf(-ang * 3.0, -1.0, 1.0)


var _ap_speed := 30.0


## Throttle/brake for the autopilot towards the curvature-limited speed (and a cap in km/h).
func autopilot_pedals(car: CarController, cap_kmh := 110.0) -> Vector2:
	var target := minf(_ap_speed, cap_kmh / 3.6)
	var err := target - car.speed
	if err > 0.0:
		return Vector2(clampf(err * 0.25 + 0.2, 0.0, 1.0), 0.0)
	return Vector2(0.0, clampf(-err * 0.18, 0.0, 1.0))
