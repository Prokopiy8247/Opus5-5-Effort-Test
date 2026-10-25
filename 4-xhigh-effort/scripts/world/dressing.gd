class_name Dressing
extends Node3D
## Vegetation and rocks from the baked placements: one MultiMesh per cell, species and LOD
## (Blender mesh near, its _LOD1 far, culled by visibility range). Visibility ranges are measured to
## the cell centre, so cells are small (256 m trees, 128 m small plants) and the LOD swap is a hard
## switch: a dithered fade would ghost a whole cell, including trees right next to the camera.
## Trunk/boulder collision is created only around the focus point. Grass clumps are scattered around
## the camera on grassy ground.

const SPECIES := ["tree_broadleaf", "tree_conifer", "tree_poplar", "tree_palm", "cactus", "bush", "boulder", "tree_umbrella", "shrub_dry"]
const SPECIES_CELL := [256.0, 256.0, 256.0, 256.0, 128.0, 128.0, 128.0, 256.0, 128.0]
const NEAR_END := [330.0, 330.0, 330.0, 320.0, 230.0, 200.0, 260.0, 330.0, 180.0]
const FAR_END := [1800.0, 2000.0, 1600.0, 1300.0, 750.0, 520.0, 950.0, 1600.0, 420.0]
const COLLIDE := [0.35, 0.3, 0.25, 0.25, 0.3, -1.0, 1.2, 0.35, -1.0]
const COL_DIST := 200.0

var world: Node
var focus := Vector3.ZERO
var _near_meshes: Array[Mesh] = []
var _far_meshes: Array[Mesh] = []
var _chunk_trees := {}       # "cx,cz" -> PackedFloat32Array
var _colliders := {}         # "cx,cz" -> StaticBody3D
var _grass: MultiMeshInstance3D
var _grass_center := Vector3(1e9, 0, 0)
var _grass_task := -1
var _grass_job_obj: GrassJob


## Worker-thread grass scatter; touches only its own fields and the (read-only) world data.
class GrassJob:
	var c := Vector3.ZERO
	var wd: WorldData
	var result := PackedFloat32Array()

	func run() -> void:
		result = Dressing.scatter_grass(c, wd)
var stats := {"instances": 0, "cells": 0, "tree_colliders": 0}


func setup(w: Node) -> void:
	world = w
	var wd: WorldData = world.wd
	_chunk_trees = wd.trees
	for s in SPECIES.size():
		var kit: Node = world.kit
		var near: Mesh = kit.mesh(SPECIES[s]) if kit.has_piece(SPECIES[s]) else _fallback(s, false)
		var far: Mesh = kit.mesh(SPECIES[s], 1) if kit.has_piece(SPECIES[s]) else _fallback(s, true)
		_near_meshes.append(near)
		_far_meshes.append(far)
	# group instances per cell and species
	var cells := {}
	for key: String in _chunk_trees:
		var arr: PackedFloat32Array = _chunk_trees[key]
		for k in range(0, arr.size(), 6):
			var sp := int(arr[k + 5])
			var cs: float = SPECIES_CELL[sp]
			var ck := Vector3i(int(floor(arr[k] / cs)), int(floor(arr[k + 2] / cs)), sp)
			if not cells.has(ck):
				cells[ck] = PackedFloat32Array()
			var ca: PackedFloat32Array = cells[ck]
			ca.append_array([arr[k], arr[k + 1], arr[k + 2], arr[k + 3], arr[k + 4]])
			cells[ck] = ca
	for ck: Vector3i in cells:
		var data: PackedFloat32Array = cells[ck]
		var count := data.size() / 5
		var cs: float = SPECIES_CELL[ck.z]
		var center := Vector3((ck.x + 0.5) * cs, 0.0, (ck.y + 0.5) * cs)
		for lod in 2:
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = _near_meshes[ck.z] if lod == 0 else _far_meshes[ck.z]
			mm.instance_count = count
			for i in count:
				var o := i * 5
				var sc := data[o + 4]
				var b := Basis(Vector3.UP, data[o + 3]).scaled(Vector3(sc, sc, sc))
				mm.set_instance_transform(i, Transform3D(b, Vector3(data[o], data[o + 1] - 0.15, data[o + 2]) - center))
			var mmi := MultiMeshInstance3D.new()
			mmi.multimesh = mm
			mmi.position = center
			if lod == 0:
				mmi.visibility_range_end = NEAR_END[ck.z]
			else:
				mmi.visibility_range_begin = NEAR_END[ck.z]
				mmi.visibility_range_end = FAR_END[ck.z]
				mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
			add_child(mmi)
		stats.instances += count
		stats.cells += 1
	print("Dressing: %d instances in %d species cells" % [stats.instances, stats.cells])
	_setup_grass()


func _exit_tree() -> void:
	if _grass_task >= 0:
		WorkerThreadPool.wait_for_task_completion(_grass_task)
		_grass_task = -1


func _process(_delta: float) -> void:
	if world == null:
		return
	_update_colliders()
	_update_grass()


func _update_colliders() -> void:
	var wd: WorldData = world.wd
	for key: String in _chunk_trees:
		var parts := key.split(",")
		var cx := int(parts[0])
		var cz := int(parts[1])
		var x0 := -wd.half + cx * 256.0
		var z0 := -wd.half + cz * 256.0
		var dx := maxf(maxf(x0 - focus.x, 0.0), focus.x - (x0 + 256.0))
		var dz := maxf(maxf(z0 - focus.z, 0.0), focus.z - (z0 + 256.0))
		var d := sqrt(dx * dx + dz * dz)
		if d < COL_DIST and not _colliders.has(key):
			_colliders[key] = _make_colliders(_chunk_trees[key])
		elif d > COL_DIST + 60.0 and _colliders.has(key):
			(_colliders[key] as Node).queue_free()
			_colliders.erase(key)


func _make_colliders(arr: PackedFloat32Array) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	body.set_meta("surface", SurfaceData.Kind.ROCK)
	var n := 0
	for k in range(0, arr.size(), 6):
		var sp := int(arr[k + 5])
		var r: float = COLLIDE[sp]
		if r <= 0.0:
			continue
		var cs := CollisionShape3D.new()
		var shape := CylinderShape3D.new()
		shape.radius = r * arr[k + 4]
		shape.height = 6.0 if sp != 6 else 2.0
		cs.shape = shape
		cs.position = Vector3(arr[k], arr[k + 1] + shape.height * 0.5 - 0.3, arr[k + 2])
		body.add_child(cs)
		n += 1
	add_child(body)
	stats.tree_colliders += n
	return body


# ------------------------------------------------------------------ grass
func _setup_grass() -> void:
	_grass = MultiMeshInstance3D.new()
	_grass.name = "Grass"
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var kit: Node = world.kit
	mm.mesh = kit.mesh("grass_clump") if kit.has_piece("grass_clump") else _grass_mesh()
	mm.instance_count = 0
	_grass.multimesh = mm
	_grass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_grass)


func _update_grass() -> void:
	if _grass_task >= 0:
		if WorkerThreadPool.is_task_completed(_grass_task):
			WorkerThreadPool.wait_for_task_completion(_grass_task)
			_grass_task = -1
			var data := _grass_job_obj.result
			var mm := _grass.multimesh
			var count := data.size() / 16
			mm.instance_count = count
			if count > 0:
				mm.buffer = data
		return
	var cam := get_viewport().get_camera_3d()
	var c := cam.global_position if cam != null else focus
	if Vector2(c.x - _grass_center.x, c.z - _grass_center.z).length() > 18.0:
		_grass_center = c
		_grass_job_obj = GrassJob.new()
		_grass_job_obj.c = c
		_grass_job_obj.wd = world.wd
		_grass_task = WorkerThreadPool.add_task(_grass_job_obj.run, false, "grass")


static func scatter_grass(c: Vector3, wd: WorldData) -> PackedFloat32Array:
	var rng := RandomNumberGenerator.new()
	var out := PackedFloat32Array()
	var radius := 70.0
	var step := 1.6
	var gx0 := floorf((c.x - radius) / step) * step
	var gz0 := floorf((c.z - radius) / step) * step
	var steps := int(radius * 2.0 / step)
	for j in steps:
		for i in steps:
			var bx := gx0 + i * step
			var bz := gz0 + j * step
			rng.seed = hash(Vector2i(int(bx / step), int(bz / step)))
			var x := bx + rng.randf() * step
			var z := bz + rng.randf() * step
			var d := Vector2(x - c.x, z - c.z).length()
			if d > radius or rng.randf() > 0.55:
				continue
			var cell := wd.cell4(x, z)
			if wd.surface[cell] != SurfaceData.Kind.GRASS or wd.road_dist[cell] < 3:
				continue
			var y := wd.height_at(x, z)
			if y < 1.0:
				continue
			var s := rng.randf_range(0.6, 1.3) * (1.0 - smoothstep(radius * 0.6, radius, d) * 0.7)
			var b := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s, s))
			out.append_array([b.x.x, b.y.x, b.z.x, x, b.x.y, b.y.y, b.z.y, y - 0.05, b.x.z, b.y.z, b.z.z, z])
			var tint := rng.randf_range(0.8, 1.15)
			out.append(tint)
	# repack: 12 floats transform + colour (4 floats) per instance
	var packed := PackedFloat32Array()
	var n := out.size() / 13
	packed.resize(n * 16)
	for k in n:
		for q in 12:
			packed[k * 16 + q] = out[k * 13 + q]
		var t := out[k * 13 + 12]
		packed[k * 16 + 12] = t
		packed[k * 16 + 13] = t
		packed[k * 16 + 14] = t
		packed[k * 16 + 15] = 1.0
	return packed


func _grass_mesh() -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in 5:
		var a := TAU * k / 5.0
		var d := Vector3(cos(a), 0, sin(a))
		var side := Vector3(-d.z, 0, d.x) * 0.06
		var tip := d * 0.18 + Vector3.UP * 0.55
		st.set_normal(Vector3.UP)
		st.add_vertex(-side)
		st.add_vertex(tip)
		st.add_vertex(side)
	var m := st.commit()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.3, 0.42, 0.14)
	mat.vertex_color_use_as_albedo = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.roughness = 0.9
	m.surface_set_material(0, mat)
	return m


# ------------------------------------------------------- fallback meshes
## Temporary code stand-ins used only until the Blender nature kit is exported.
func _fallback(s: int, low: bool) -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var seg := 5 if low else 8
	match s:
		0, 7:
			_cyl(st, 0.25, 3.0, 0.0, seg, Color(0.3, 0.2, 0.12))
			_blob(st, Vector3(0, 4.2 if s == 0 else 4.6, 0), Vector3(2.6, 2.2 if s == 0 else 1.0, 2.6) * (1.0 if s == 0 else 1.5), seg, Color(0.2, 0.34, 0.1) if s == 0 else Color(0.25, 0.36, 0.15))
		1:
			_cyl(st, 0.2, 2.0, 0.0, seg, Color(0.3, 0.2, 0.12))
			for k in 3:
				_cone(st, 2.2 - k * 0.55, 2.8, 1.5 + k * 1.9, seg, Color(0.1, 0.21, 0.1))
		2:
			_cyl(st, 0.18, 2.0, 0.0, seg, Color(0.3, 0.2, 0.12))
			_blob(st, Vector3(0, 6.0, 0), Vector3(1.0, 4.5, 1.0), seg, Color(0.18, 0.32, 0.1))
		3:
			_cyl(st, 0.2, 7.0, 0.0, seg, Color(0.45, 0.38, 0.3))
			_blob(st, Vector3(0, 7.2, 0), Vector3(2.8, 0.6, 2.8), seg, Color(0.25, 0.42, 0.12))
		4:
			_cyl(st, 0.3, 4.5, 0.0, seg, Color(0.25, 0.38, 0.18))
			_blob(st, Vector3(0.7, 2.6, 0), Vector3(0.25, 1.0, 0.25), seg, Color(0.25, 0.38, 0.18))
		5:
			_blob(st, Vector3(0, 0.5, 0), Vector3(1.2, 0.8, 1.2), seg, Color(0.22, 0.32, 0.12))
		6:
			_blob(st, Vector3(0, 0.4, 0), Vector3(1.6, 1.1, 1.3), seg, Color(0.45, 0.43, 0.4))
		_:
			_blob(st, Vector3(0, 0.35, 0), Vector3(0.8, 0.5, 0.8), seg, Color(0.45, 0.4, 0.22))
	st.generate_normals()
	var m := st.commit()
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.9
	m.surface_set_material(0, mat)
	return m


func _cyl(st: SurfaceTool, r: float, h: float, y0: float, seg: int, col: Color) -> void:
	for k in seg:
		var a0 := TAU * k / seg
		var a1 := TAU * (k + 1) / seg
		var p0 := Vector3(cos(a0) * r, y0, sin(a0) * r)
		var p1 := Vector3(cos(a1) * r, y0, sin(a1) * r)
		st.set_color(col)
		for v: Vector3 in [p0, p1 + Vector3.UP * h, p1, p0, p0 + Vector3.UP * h, p1 + Vector3.UP * h]:
			st.add_vertex(v)


func _cone(st: SurfaceTool, r: float, h: float, y0: float, seg: int, col: Color) -> void:
	for k in seg:
		var a0 := TAU * k / seg
		var a1 := TAU * (k + 1) / seg
		st.set_color(col)
		st.add_vertex(Vector3(cos(a0) * r, y0, sin(a0) * r))
		st.add_vertex(Vector3(0, y0 + h, 0))
		st.add_vertex(Vector3(cos(a1) * r, y0, sin(a1) * r))


func _blob(st: SurfaceTool, c: Vector3, s: Vector3, seg: int, col: Color) -> void:
	var rings := maxi(3, seg / 2)
	for j in rings:
		var t0 := PI * j / rings
		var t1 := PI * (j + 1) / rings
		for k in seg:
			var a0 := TAU * k / seg
			var a1 := TAU * (k + 1) / seg
			var p := func(t: float, a: float) -> Vector3: return c + Vector3(sin(t) * cos(a) * s.x, cos(t) * s.y, sin(t) * sin(a) * s.z)
			st.set_color(col)
			var v00: Vector3 = p.call(t0, a0)
			var v01: Vector3 = p.call(t0, a1)
			var v10: Vector3 = p.call(t1, a0)
			var v11: Vector3 = p.call(t1, a1)
			for v: Vector3 in [v00, v01, v11, v00, v11, v10]:
				st.add_vertex(v)
