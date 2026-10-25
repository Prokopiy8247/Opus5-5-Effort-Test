class_name World
extends Node3D
## Owns the open world: baked data, terrain streaming, roads, water, sky/weather, dressing,
## traffic and activities. Game.world points here.

signal load_progress(fraction: float, label: String)

var data: WorldData
var terrain: Terrain
var roads: RoadBuilder
var sky: SkyWeather
var dressing: Node3D
var traffic: Node3D
var activities: Node3D
var water_mat: ShaderMaterial
var noise_a: NoiseTexture2D
var noise_b: NoiseTexture2D
var focus_node: Node3D


func build() -> void:
	data = WorldData.new()
	load_progress.emit(0.05, "Loading world data")
	await get_tree().process_frame
	if not data.load_all():
		return
	Game.world = self
	noise_a = Terrain._noise_tex(1, 256, 0.012, 3)
	noise_b = Terrain._noise_tex(2, 256, 0.03, 4)
	sky = SkyWeather.new()
	sky.name = "SkyWeather"
	add_child(sky)
	load_progress.emit(0.15, "Shaping terrain")
	await get_tree().process_frame
	terrain = Terrain.new()
	terrain.name = "Terrain"
	add_child(terrain)
	terrain.setup(data)
	terrain.build_far_all()
	_outer_ring()
	load_progress.emit(0.45, "Paving %.1f km of road" % (_total_road_km()))
	await get_tree().process_frame
	roads = RoadBuilder.new()
	roads.name = "Roads"
	add_child(roads)
	roads.setup(data, noise_a, noise_b)
	roads.build_all()
	traffic = TrafficManager.new()
	traffic.name = "Traffic"
	add_child(traffic)
	(traffic as TrafficManager).setup(data)
	load_progress.emit(0.7, "Filling the sea and river")
	await get_tree().process_frame
	_water()
	load_progress.emit(0.75, "Planting the countryside")
	await get_tree().process_frame
	if ResourceLoader.exists("res://scripts/world/dressing.gd"):
		dressing = (load("res://scripts/world/dressing.gd") as GDScript).new()
		dressing.name = "Dressing"
		add_child(dressing)
		await dressing.build(self)
	activities = Activities.new()
	activities.name = "Activities"
	add_child(activities)
	load_progress.emit(0.95, "Waking up the roads")
	await get_tree().process_frame


func _total_road_km() -> float:
	var t := 0.0
	for r in data.roads:
		t += r.length
	return t / 1000.0


func _process(_delta: float) -> void:
	if terrain and focus_node and is_instance_valid(focus_node):
		terrain.focus = focus_node.global_position


func height_at(x: float, z: float) -> float:
	return data.height_at(x, z) if data else 0.0


func surface_at(x: float, z: float) -> int:
	return data.surface_at(x, z) if data else 0


func _water() -> void:
	water_mat = ShaderMaterial.new()
	water_mat.shader = load("res://shaders/water.gdshader")
	water_mat.set_shader_parameter("noise_tex", noise_b)
	var sea := MeshInstance3D.new()
	sea.name = "Sea"
	var pm := PlaneMesh.new()
	pm.size = Vector2(16000, 16000)
	pm.subdivide_width = 96
	pm.subdivide_depth = 96
	sea.mesh = pm
	sea.material_override = water_mat
	sea.position = Vector3(0, 0.0, 0)
	sea.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(sea)
	# river ribbon
	var rm := ShaderMaterial.new()
	rm.shader = water_mat.shader
	rm.set_shader_parameter("noise_tex", noise_b)
	rm.set_shader_parameter("flow", Vector2(0.05, 0.03))
	rm.set_shader_parameter("wave_scale", 0.0)
	rm.set_shader_parameter("shallow_color", Color(0.16, 0.32, 0.26))
	rm.set_shader_parameter("deep_color", Color(0.05, 0.16, 0.14))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pts := data.river
	for i in range(pts.size() - 1):
		var a := pts[i]
		var b := pts[i + 1]
		var t := (b - a)
		t.y = 0
		t = t.normalized()
		var lat := Vector3(-t.z, 0, t.x) * 11.0
		var a0 := a - lat
		var a1 := a + lat
		var b0 := b - lat
		var b1 := b + lat
		st.set_normal(Vector3.UP)
		st.add_vertex(a0)
		st.add_vertex(b0)
		st.add_vertex(a1)
		st.add_vertex(a1)
		st.add_vertex(b0)
		st.add_vertex(b1)
	var river := MeshInstance3D.new()
	river.name = "River"
	river.mesh = st.commit()
	river.material_override = rm
	river.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(river)


func _outer_ring() -> void:
	# low-detail hills beyond the playable square so the horizon never shows the void
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var step := 256.0
	var ext := 7168.0
	var half := -data.origin
	var fn := FastNoiseLite.new()
	fn.seed = 9
	fn.frequency = 1.0 / 1500.0
	var cnt := int(ext * 2.0 / step)
	var hgrid := PackedFloat32Array()
	hgrid.resize((cnt + 1) * (cnt + 1))
	for j in cnt + 1:
		for i in cnt + 1:
			var x := -ext + i * step
			var z := -ext + j * step
			var cx := clampf(x, -half, half)
			var cz := clampf(z, -half, half)
			var base := data.height_at(cx, cz)
			var d := maxf(maxf(absf(x) - half, absf(z) - half), 0.0)
			var h: float
			if x > half - 300.0:
				h = minf(base, 0.0) - 18.0 - d * 0.01
			else:
				h = base + d * 0.09 + (fn.get_noise_2d(x, z) * 0.5 + 0.5) * minf(d, 1500.0) * 0.25
			hgrid[j * (cnt + 1) + i] = h
	for j in cnt:
		for i in cnt:
			var x0 := -ext + i * step
			var z0 := -ext + j * step
			if x0 >= -half - 1.0 and x0 + step <= half + 1.0 and z0 >= -half - 1.0 and z0 + step <= half + 1.0:
				continue
			var v00 := Vector3(x0, hgrid[j * (cnt + 1) + i], z0)
			var v10 := Vector3(x0 + step, hgrid[j * (cnt + 1) + i + 1], z0)
			var v01 := Vector3(x0, hgrid[(j + 1) * (cnt + 1) + i], z0 + step)
			var v11 := Vector3(x0 + step, hgrid[(j + 1) * (cnt + 1) + i + 1], z0 + step)
			# keep the ring just below the playable terrain where they meet
			for v in [v00, v10, v01, v11]:
				pass
			st.add_vertex(v00)
			st.add_vertex(v10)
			st.add_vertex(v01)
			st.add_vertex(v10)
			st.add_vertex(v11)
			st.add_vertex(v01)
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.name = "OuterRing"
	mi.mesh = st.commit()
	mi.material_override = terrain.material
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	# invisible walls at the map boundary
	var walls := StaticBody3D.new()
	walls.name = "Boundary"
	walls.collision_layer = 1
	for k in 4:
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(half * 2.0, 2000.0, 10.0) if k < 2 else Vector3(10.0, 2000.0, half * 2.0)
		cs.shape = box
		match k:
			0:
				cs.position = Vector3(0, 0, -half - 5.0)
			1:
				cs.position = Vector3(0, 0, half + 5.0)
			2:
				cs.position = Vector3(-half - 5.0, 0, 0)
			3:
				cs.position = Vector3(half + 5.0, 0, 0)
		walls.add_child(cs)
	add_child(walls)
