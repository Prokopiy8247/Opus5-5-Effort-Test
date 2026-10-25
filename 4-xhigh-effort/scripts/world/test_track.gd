class_name TestTrack
extends Node3D
## Flat proving ground for vehicle development and automated drive tests:
## 4 km asphalt pad, gravel/grass/sand strips, a jump ramp and a marked skidpad.

func _ready() -> void:
	_add_pad("Asphalt", Vector3(0, -0.5, 0), Vector3(4000, 1, 16400), SurfaceData.Kind.ASPHALT, Color(0.16, 0.16, 0.17))
	_add_pad("Gravel", Vector3(-300, -0.49, -600), Vector3(60, 1, 1000), SurfaceData.Kind.GRAVEL, Color(0.45, 0.42, 0.38))
	_add_pad("Grass", Vector3(-380, -0.49, -600), Vector3(60, 1, 1000), SurfaceData.Kind.GRASS, Color(0.25, 0.4, 0.15))
	_add_pad("Sand", Vector3(-460, -0.49, -600), Vector3(60, 1, 1000), SurfaceData.Kind.SAND, Color(0.8, 0.7, 0.5))
	_add_ramp(Vector3(300, 0, -400))
	# skidpad ring marker (r = 40 m)
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 39.6
	tm.outer_radius = 40.4
	tm.rings = 96
	ring.mesh = tm
	ring.scale = Vector3(1, 0.01, 1)
	ring.position = Vector3(600, 0.01, 0)
	var rm := StandardMaterial3D.new()
	rm.albedo_color = Color(1, 0.8, 0.1)
	ring.material_override = rm
	add_child(ring)


func _add_pad(n: String, pos: Vector3, size: Vector3, kind: int, col: Color) -> void:
	var body := StaticBody3D.new()
	body.name = n
	body.position = pos
	body.set_meta("surface", kind)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	body.add_child(cs)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = 0.85
	m.uv1_triplanar = true
	m.uv1_scale = Vector3(0.05, 0.05, 0.05)
	var img := Image.create(64, 64, false, Image.FORMAT_RGB8)
	for y in 64:
		for x in 64:
			var line := x < 2 or y < 2
			var c := col.lightened(0.25) if line else col
			img.set_pixel(x, y, c)
	m.albedo_texture = ImageTexture.create_from_image(img)
	mi.material_override = m
	body.add_child(mi)
	add_child(body)


func _add_ramp(pos: Vector3) -> void:
	var body := StaticBody3D.new()
	body.name = "Ramp"
	body.position = pos
	body.set_meta("surface", SurfaceData.Kind.CONCRETE)
	var cs := CollisionShape3D.new()
	var shape := ConvexPolygonShape3D.new()
	var w := 8.0
	var l := 14.0
	var h := 2.4
	shape.points = PackedVector3Array([Vector3(-w / 2, 0, 0), Vector3(w / 2, 0, 0), Vector3(-w / 2, 0, -l), Vector3(w / 2, 0, -l),
			Vector3(-w / 2, h, -l), Vector3(w / 2, h, -l)])
	cs.shape = shape
	body.add_child(cs)
	var mi := MeshInstance3D.new()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var p := shape.points
	for tri: Array in [[0, 2, 4], [0, 4, 1], [1, 4, 5], [1, 5, 3], [2, 3, 5], [2, 5, 4], [0, 1, 3], [0, 3, 2]]:
		for i: int in tri:
			st.add_vertex(p[i])
	st.generate_normals()
	mi.mesh = st.commit()
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.9, 0.5, 0.1)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = m
	body.add_child(mi)
	add_child(body)


func get_spawn() -> Transform3D:
	return Transform3D(Basis.IDENTITY, Vector3(0, 0.6, 0))


func terrain_surface_at(_p: Vector3) -> int:
	return SurfaceData.Kind.ASPHALT


func nearest_road_transform(p: Vector3) -> Transform3D:
	return Transform3D(Basis.IDENTITY, Vector3(p.x, 0.8, p.z))
