extends Node3D
## Near-player grass: 64 m tiles of crossed-quad tufts (MultiMesh), generated on worker
## threads around the player, wind-animated and distance-faded in the shader.

const TILE := 64.0
const RADIUS := 2
const PER_TILE := 1100

var world: World
var data: WorldData
var mesh: ArrayMesh
var mat: ShaderMaterial
var _tiles := {}
var _pending := {}
var _results := {}
var _mutex := Mutex.new()


func setup(w: World) -> void:
	world = w
	data = w.data
	mat = ShaderMaterial.new()
	mat.shader = load("res://shaders/grass.gdshader")
	mat.set_shader_parameter("blade_tex", _blade_texture())
	mesh = _tuft_mesh()


func _tuft_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in 3:
		var a := k * PI / 3.0
		var d := Vector3(cos(a), 0, sin(a)) * 0.35
		var corners := [-d, d, d + Vector3(0, 0.55, 0), -d + Vector3(0, 0.55, 0)]
		var uvs := [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]
		for idx in [0, 1, 2, 0, 2, 3]:
			st.set_normal(Vector3.UP)
			st.set_uv(uvs[idx])
			st.add_vertex(corners[idx])
	var m := st.commit()
	m.surface_set_material(0, mat)
	return m


func _blade_texture() -> ImageTexture:
	var img := Image.create_empty(64, 64, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for b in 9:
		var x0 := rng.randf_range(6, 58)
		var lean := rng.randf_range(-10, 10)
		var hgt := rng.randf_range(34, 63)
		for y in int(hgt):
			var t := float(y) / hgt
			var x := x0 + lean * t * t
			var wdt := lerpf(2.6, 0.4, t)
			for xx in range(int(x - wdt), int(x + wdt) + 1):
				if xx >= 0 and xx < 64:
					img.set_pixel(xx, 63 - y, Color(0.75 + t * 0.25, 0.85 + t * 0.15, 0.6, 1.0))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


func _process(_delta: float) -> void:
	var _t0 := Time.get_ticks_usec()
	_process_inner(_delta)
	Game.prof_add("grass", Time.get_ticks_usec() - _t0)


func _process_inner(_delta: float) -> void:
	if data == null or Game.player == null:
		return
	var p: Vector3 = Game.player.global_position
	var tc := Vector2i(floori(p.x / TILE), floori(p.z / TILE))
	# collect finished tiles
	for t in _pending.keys():
		var tid: int = _pending[t]
		if not WorkerThreadPool.is_task_completed(tid):
			continue
		WorkerThreadPool.wait_for_task_completion(tid)
		_pending.erase(t)
		_mutex.lock()
		var buf: PackedFloat32Array = _results.get(t, PackedFloat32Array())
		_results.erase(t)
		_mutex.unlock()
		if buf.is_empty() or maxi(absi(t.x - tc.x), absi(t.y - tc.y)) > RADIUS + 1:
			_tiles[t] = null
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = false
		mm.mesh = mesh
		mm.instance_count = buf.size() / 12
		mm.buffer = buf
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.visibility_range_end = 140.0
		add_child(mmi)
		_tiles[t] = mmi
	# request / drop
	for dz in range(-RADIUS, RADIUS + 1):
		for dx in range(-RADIUS, RADIUS + 1):
			var t := Vector2i(tc.x + dx, tc.y + dz)
			if _tiles.has(t) or _pending.has(t):
				continue
			var tt := t
			_pending[t] = WorkerThreadPool.add_task(func() -> void:
				var b := _build(tt)
				_mutex.lock()
				_results[tt] = b
				_mutex.unlock()
			, false, "grass")
	for t in _tiles.keys():
		if maxi(absi(t.x - tc.x), absi(t.y - tc.y)) > RADIUS + 1:
			var n: Variant = _tiles[t]
			if n != null:
				(n as Node).queue_free()
			_tiles.erase(t)


func _build(t: Vector2i) -> PackedFloat32Array:
	var buf := PackedFloat32Array()
	var rng := RandomNumberGenerator.new()
	rng.seed = t.x * 92821 + t.y * 68917
	var x0 := t.x * TILE
	var z0 := t.y * TILE
	for k in PER_TILE:
		var x := x0 + rng.randf() * TILE
		var z := z0 + rng.randf() * TILE
		var s := data.surface_at(x, z)
		if s != Game.Surf.GRASS:
			continue
		if data.road_distance(x, z) < 1.5:
			continue
		var h := data.height_at(x, z)
		if h < 2.0:
			continue
		var w := data.region_weights(x, z)
		if w.b > 0.6 and rng.randf() < 0.7:
			continue
		var sc := rng.randf_range(0.7, 1.4) * (1.25 if w.r > 0.5 else 1.0)
		var b := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(sc, sc * rng.randf_range(0.8, 1.3), sc))
		buf.append_array([b.x.x, b.y.x, b.z.x, x, b.x.y, b.y.y, b.z.y, h - 0.05, b.x.z, b.y.z, b.z.z, z])
	return buf
