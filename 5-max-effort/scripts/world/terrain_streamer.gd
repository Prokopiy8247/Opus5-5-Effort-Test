class_name TerrainStreamer
extends Node3D
## 16 x 16 chunks of 256 m. Rendering: shared flat grid meshes per LOD displaced on the GPU from
## the baked heightmap texture (no CPU mesh building -> no streaming hitches); LOD by camera
## distance with skirts. Physics: HeightMapShape3D bodies only around active points (player).

const CHUNK := 256.0
const COUNT := 16
const ORIGIN := -2048.0
const LOD_STEPS := [1, 2, 4, 8]          # grid cells (2 m each) per vertex
const LOD_DIST := [300.0, 700.0, 1400.0]
const COLLISION_RADIUS := 1             # chunks around each active point

var data: WorldData
var material_lods: Array[ShaderMaterial] = []
var lod_meshes: Array[ArrayMesh] = []
var chunks: Array = []                  # [{"mi": MeshInstance3D, "lod": int, "aabb": AABB}]
var _bodies: Dictionary = {}            # Vector2i -> StaticBody3D
var _last_cam := Vector3(INF, 0, INF)
var height_tex: ImageTexture
var stats_collision_builds: int = 0
var _hdiv := PackedFloat32Array()
var _hole_rows := PackedByteArray()


func _prepare_fast_heights() -> void:
	_hdiv = data.heights.duplicate()
	var inv := 1.0 / data.res
	for i in _hdiv.size():
		_hdiv[i] *= inv
	_hole_rows.resize(data.n)
	for z in data.n:
		var row := data.holes.slice(z * data.n, (z + 1) * data.n)
		_hole_rows[z] = 1 if row.has(1) else 0


func _chunk_has_holes(gx0: int, gz0: int, w: int) -> bool:
	for z in range(maxi(gz0, 0), mini(gz0 + w, data.n)):
		if _hole_rows[z] != 0:
			return true
	return false


func setup(d: WorldData) -> void:
	data = d
	_prepare_fast_heights()
	# textures from baked data
	var himg := Image.create_from_data(d.n, d.n, false, Image.FORMAT_RF, d.heights.to_byte_array())
	height_tex = ImageTexture.create_from_image(himg)
	var hole_img := Image.create_from_data(d.n, d.n, false, Image.FORMAT_L8, _holes_bytes(d))
	var hole_tex := ImageTexture.create_from_image(hole_img)
	var splat_tex := ImageTexture.create_from_image(d.splat)
	var rimg := d.road_mask_image()
	var road_tex := ImageTexture.create_from_image(rimg) if rimg != null else null
	var na := _noise_tex(1, 0.02, 256)
	var nb := _noise_tex(2, 0.008, 256)
	var shader := load("res://assets/shaders/terrain.gdshader") as Shader
	for l in LOD_STEPS.size():
		var m := ShaderMaterial.new()
		m.shader = shader
		m.set_shader_parameter("heightmap", height_tex)
		m.set_shader_parameter("holemap", hole_tex)
		m.set_shader_parameter("splatmap", splat_tex)
		m.set_shader_parameter("roadmask", road_tex)
		m.set_shader_parameter("noise_a", na)
		m.set_shader_parameter("noise_b", nb)
		m.set_shader_parameter("world_half", d.half)
		m.set_shader_parameter("grid_res", d.res)
		m.set_shader_parameter("grid_n", float(d.n))
		m.set_shader_parameter("lod_step", float(LOD_STEPS[l]))
		m.set_shader_parameter("skirt_depth", [2.0, 4.0, 8.0, 14.0][l])
		m.set_shader_parameter("snow_line", d.snow_line)
		m.set_shader_parameter("road_sink", [0.0, 0.5, 1.2, 2.5][l])
		material_lods.append(m)
		lod_meshes.append(_grid_mesh(int(CHUNK / d.res) / LOD_STEPS[l], CHUNK))
	for cz in COUNT:
		for cx in COUNT:
			var mi := MeshInstance3D.new()
			mi.name = "T_%d_%d" % [cx, cz]
			mi.position = Vector3(ORIGIN + cx * CHUNK, 0.0, ORIGIN + cz * CHUNK)
			var hr := _chunk_height_range(cx, cz)
			var aabb := AABB(Vector3(0.0, hr.x - 16.0, 0.0), Vector3(CHUNK, hr.y - hr.x + 17.0, CHUNK))
			mi.custom_aabb = aabb
			mi.mesh = lod_meshes[3]
			mi.material_override = material_lods[3]
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
			add_child(mi)
			chunks.append({"mi": mi, "lod": 3, "aabb": AABB(mi.position + aabb.position, aabb.size)})


static func _holes_bytes(d: WorldData) -> PackedByteArray:
	var b := d.holes.duplicate()
	for i in b.size():
		if b[i] != 0:
			b[i] = 255
	return b


static func _noise_tex(seed_v: int, freq: float, size: int) -> NoiseTexture2D:
	var nt := NoiseTexture2D.new()
	nt.width = size
	nt.height = size
	nt.seamless = true
	nt.generate_mipmaps = true
	var fn := FastNoiseLite.new()
	fn.seed = seed_v
	fn.frequency = freq
	fn.fractal_octaves = 4
	nt.noise = fn
	return nt


func _chunk_height_range(cx: int, cz: int) -> Vector2:
	var lo := 1e9
	var hi := -1e9
	var x0 := ORIGIN + cx * CHUNK
	var z0 := ORIGIN + cz * CHUNK
	var step := 8.0
	var sx := 0.0
	while sx <= CHUNK:
		var sz := 0.0
		while sz <= CHUNK:
			var h := data.height_at(x0 + sx, z0 + sz)
			lo = minf(lo, h)
			hi = maxf(hi, h)
			sz += step
		sx += step
	return Vector2(lo - 4.0, hi + 4.0)


static func _grid_mesh(cells: int, size: float) -> ArrayMesh:
	## (cells+1)^2 grid plus a skirt ring (COLOR.r = 1 marks skirt vertices).
	var verts := PackedVector3Array()
	var colors := PackedColorArray()
	var normals := PackedVector3Array()
	var idx := PackedInt32Array()
	var n := cells + 1
	var cs := size / float(cells)
	for z in n:
		for x in n:
			verts.append(Vector3(x * cs, 0.0, z * cs))
			colors.append(Color(0, 0, 0, 1))
			normals.append(Vector3.UP)
	for z in cells:
		for x in cells:
			var a := z * n + x
			var b := a + 1
			var c := a + n
			var d := c + 1
			# clockwise from above: a(x,z) -> c(x,z+1)? keep consistent with Godot CW front faces
			idx.append(a)
			idx.append(b)
			idx.append(d)
			idx.append(a)
			idx.append(d)
			idx.append(c)
	# skirts: duplicate border vertices flagged as skirt, stitched to the border
	var border: Array[int] = []
	for x in n:
		border.append(x)
	for z in range(1, n):
		border.append(z * n + cells)
	for x in range(cells - 1, -1, -1):
		border.append(cells * n + x)
	for z in range(cells - 1, 0, -1):
		border.append(z * n)
	var start := verts.size()
	for bi in border:
		verts.append(verts[bi])
		colors.append(Color(1, 0, 0, 1))
		normals.append(Vector3.UP)
	var bc := border.size()
	for k in bc:
		var t0: int = border[k]
		var t1: int = border[(k + 1) % bc]
		var s0 := start + k
		var s1 := start + (k + 1) % bc
		idx.append(t0)
		idx.append(s0)
		idx.append(s1)
		idx.append(t0)
		idx.append(s1)
		idx.append(t1)
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = normals
	arr[Mesh.ARRAY_COLOR] = colors
	arr[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m


func update_lod(cam_pos: Vector3) -> void:
	if cam_pos.distance_squared_to(_last_cam) < 16.0:
		return
	_last_cam = cam_pos
	for c in chunks:
		var aabb: AABB = c["aabb"]
		var closest := Vector3(clampf(cam_pos.x, aabb.position.x, aabb.end.x), clampf(cam_pos.y, aabb.position.y, aabb.end.y), clampf(cam_pos.z, aabb.position.z, aabb.end.z))
		var d := closest.distance_to(cam_pos)
		var lod := 3
		for l in LOD_DIST.size():
			if d < LOD_DIST[l]:
				lod = l
				break
		var cur: int = c["lod"]
		if lod != cur:
			# hysteresis: only coarsen when clearly beyond the threshold
			if lod > cur and d < LOD_DIST[cur] + 25.0:
				continue
			c["lod"] = lod
			var mi: MeshInstance3D = c["mi"]
			mi.mesh = lod_meshes[lod]
			mi.material_override = material_lods[lod]


func chunk_key(x: float, z: float) -> Vector2i:
	return Vector2i(clampi(int(floor((x - ORIGIN) / CHUNK)), 0, COUNT - 1), clampi(int(floor((z - ORIGIN) / CHUNK)), 0, COUNT - 1))


func update_collision(points: Array) -> void:
	## points: Array[Vector3] needing physics (player and physics-LOD vehicles)
	var wanted := {}
	for p in points:
		var k := chunk_key(p.x, p.z)
		for dz in range(-COLLISION_RADIUS, COLLISION_RADIUS + 1):
			for dx in range(-COLLISION_RADIUS, COLLISION_RADIUS + 1):
				var kk := Vector2i(k.x + dx, k.y + dz)
				if kk.x < 0 or kk.y < 0 or kk.x >= COUNT or kk.y >= COUNT:
					continue
				wanted[kk] = true
	var built := 0
	for kk in wanted:
		if not _bodies.has(kk) and built < 2:
			_bodies[kk] = _build_body(kk)
			built += 1
	for kk in _bodies.keys():
		if not wanted.has(kk):
			var b: StaticBody3D = _bodies[kk]
			b.queue_free()
			_bodies.erase(kk)


func force_collision(p: Vector3) -> void:
	## immediate (unthrottled) collision around p, used for teleports and loads
	var k := chunk_key(p.x, p.z)
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var kk := Vector2i(k.x + dx, k.y + dz)
			if kk.x >= 0 and kk.y >= 0 and kk.x < COUNT and kk.y < COUNT and not _bodies.has(kk):
				_bodies[kk] = _build_body(kk)


func has_collision_at(x: float, z: float) -> bool:
	return _bodies.has(chunk_key(x, z))


func _build_body(k: Vector2i) -> StaticBody3D:
	var cells := int(CHUNK / data.res)
	var w := cells + 1
	if _hdiv.is_empty():
		_prepare_fast_heights()
	var gx0 := int(round((ORIGIN + k.x * CHUNK + data.half) / data.res))
	var gz0 := int(round((ORIGIN + k.y * CHUNK + data.half) / data.res))
	var arr := PackedFloat32Array()
	if gx0 >= 0 and gz0 >= 0 and gx0 + w <= data.n and gz0 + w <= data.n:
		# fast path: copy pre-divided rows
		for z in w:
			var start := (gz0 + z) * data.n + gx0
			arr.append_array(_hdiv.slice(start, start + w))
	else:
		arr.resize(w * w)
		for z in w:
			for x in w:
				arr[z * w + x] = data.height_grid(gx0 + x, gz0 + z) / data.res
	if _chunk_has_holes(gx0, gz0, w):
		for z in w:
			for x in w:
				if data.is_hole(gx0 + x, gz0 + z):
					arr[z * w + x] = NAN
	var shape := HeightMapShape3D.new()
	shape.map_width = w
	shape.map_depth = w
	shape.map_data = arr
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.scale = Vector3(data.res, data.res, data.res)
	var body := StaticBody3D.new()
	body.name = "TC_%d_%d" % [k.x, k.y]
	body.collision_layer = 1
	body.collision_mask = 0
	body.set_meta("terrain", true)
	body.position = Vector3(ORIGIN + k.x * CHUNK + CHUNK * 0.5, 0.0, ORIGIN + k.y * CHUNK + CHUNK * 0.5)
	body.add_child(cs)
	add_child(body)
	stats_collision_builds += 1
	return body
