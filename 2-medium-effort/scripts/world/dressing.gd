extends Node
## Vegetation and rock dressing per terrain chunk (Blender-authored meshes, MultiMesh, two LOD levels).
## place_in_chunk() runs on worker threads and only reads WorldData; spawn_instances() runs on the main thread.

const PROP_DIR: String = "res://assets/imported/props/"
const TYPES: Dictionary = {
	# type: [mesh, lod mesh or "", hi range, lod range, shadows]
	"pine": ["tree_pine", "tree_pine_lod", 240.0, 900.0, true],
	"oak": ["tree_oak", "tree_oak_lod", 220.0, 900.0, true],
	"birch": ["tree_birch", "tree_birch_lod", 220.0, 900.0, true],
	"palm": ["tree_palm", "tree_palm_lod", 220.0, 800.0, true],
	"cactus": ["cactus", "", 420.0, 0.0, true],
	"shrub": ["shrub", "", 260.0, 0.0, false],
	"bush": ["bush", "", 300.0, 0.0, true],
	"rock_a": ["rock_a", "", 500.0, 0.0, true],
	"rock_b": ["rock_b", "", 500.0, 0.0, true],
	"rock_red": ["rock_red", "", 600.0, 0.0, true],
}

var meshes: Dictionary = {}
var exclusions: Array[Vector3] = []  # (x, z, radius) circles kept free (settlements, gates)
var world: WorldData
var grass_mesh: Mesh
var stats_instances: int = 0


func setup(w: WorldData) -> void:
	world = w
	for t in TYPES:
		var def: Array = TYPES[t]
		meshes[t] = _load_mesh(def[0])
		if def[1] != "":
			meshes[t + "_lod"] = _load_mesh(def[1])
	grass_mesh = _make_grass_mesh()


func _load_mesh(nm: String) -> Mesh:
	var ps: PackedScene = load(PROP_DIR + nm + ".glb")
	var inst: Node = ps.instantiate()
	var mi: MeshInstance3D = _find_mesh(inst)
	var m: Mesh = mi.mesh if mi else BoxMesh.new()
	inst.free()
	return m


func _find_mesh(n: Node) -> MeshInstance3D:
	if n is MeshInstance3D:
		return n
	for c in n.get_children():
		var r: MeshInstance3D = _find_mesh(c)
		if r:
			return r
	return null


func _make_grass_mesh() -> Mesh:
	# a tuft of thin leaning blades, procedurally built (project-owned)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for k in 9:
		var base := Vector3(rng.randf_range(-0.35, 0.35), 0, rng.randf_range(-0.35, 0.35))
		var a: float = rng.randf() * TAU
		var side := Vector3(cos(a), 0, sin(a)) * 0.045
		var h: float = rng.randf_range(0.35, 0.75)
		var lean := Vector3(rng.randf_range(-0.15, 0.15), 0, rng.randf_range(-0.15, 0.15))
		st.set_normal(Vector3.UP)
		st.set_color(Color(0.62, 0.68, 0.55))
		st.add_vertex(base - side)
		st.set_color(Color(0.62, 0.68, 0.55))
		st.add_vertex(base + side)
		st.set_color(Color(1.25, 1.3, 1.0))
		st.add_vertex(base + lean + Vector3(0, h, 0))
	var m := st.commit()
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/grass.gdshader")
	m.surface_set_material(0, mat)
	return m


func _excluded(x: float, z: float) -> bool:
	for e in exclusions:
		if (x - e.x) * (x - e.x) + (z - e.y) * (z - e.y) < e.z * e.z:
			return true
	return false


## Worker thread: returns {type: Array[Transform3D]}
func place_in_chunk(w: WorldData, k: Vector2i, size: float) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector2i(k.x * 7919, k.y * 104729))
	var out: Dictionary = {}
	var ox: float = k.x * size
	var oz: float = k.y * size
	var n: int = 95
	for i in n:
		var x: float = ox + rng.randf() * size
		var z: float = oz + rng.randf() * size
		if absf(x) > 2150.0 or absf(z) > 2150.0:
			continue
		var rd: float = w.road_dist(x, z)
		if rd < 22.0:
			var q: Dictionary = w.road_query(x, z, 30.0)
			if q.ok and q.d < q.hw + 4.5:
				continue
		if _excluded(x, z):
			continue
		var h: float = w.height(x, z)
		if h < 1.2:
			continue
		var hx: float = w.height(x + 2.0, z)
		var hz: float = w.height(x, z + 2.0)
		var slope: float = Vector2(hx - h, hz - h).length() / 2.0
		var wr: Vector4 = w.region_weights(x, z)
		var pick: float = rng.randf()
		var reg: int = 0
		var acc: float = wr.x
		if pick > acc:
			acc += wr.y
			reg = 1
			if pick > acc:
				acc += wr.z
				reg = 2
				if pick > acc:
					reg = 3
		var forest: float = w.n_low.get_noise_2d(x * 1.7 + 500.0, z * 1.7)
		var r2: float = rng.randf()
		var t: String = ""
		match reg:
			0:
				if forest > 0.25:
					t = "pine" if r2 < 0.45 else ("birch" if r2 < 0.7 else "oak")
				elif r2 < 0.18:
					t = "oak"
				elif r2 < 0.24:
					t = "birch"
				elif r2 < 0.36:
					t = "bush"
				elif r2 < 0.38:
					t = "rock_a"
			1:
				if h > 215.0:
					t = "rock_a" if r2 < 0.12 else ("rock_b" if r2 < 0.2 else "")
				elif slope > 0.7:
					t = "rock_b" if r2 < 0.25 else ""
				elif r2 < 0.62:
					t = "pine"
				elif r2 < 0.7:
					t = "birch"
				elif r2 < 0.8:
					t = "rock_a"
			2:
				if r2 < 0.1:
					t = "cactus"
				elif r2 < 0.28:
					t = "shrub"
				elif r2 < 0.34:
					t = "rock_red"
			3:
				if h < 14.0 and r2 < 0.12:
					t = "palm"
				elif r2 < 0.22:
					t = "bush"
				elif r2 < 0.3:
					t = "pine"
				elif r2 < 0.34:
					t = "rock_a"
		if t == "":
			continue
		if slope > 0.8 and not t.begins_with("rock"):
			continue
		var sc: float = rng.randf_range(0.75, 1.3)
		if t.begins_with("rock"):
			sc = rng.randf_range(0.6, 2.4)
		var b := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(sc, sc * rng.randf_range(0.9, 1.15), sc))
		if not out.has(t):
			out[t] = []
		out[t].append(Transform3D(b, Vector3(x, h - 0.15 * sc, z)))
	# grass clumps on farmland / coast meadows
	var grass: Array = []
	var grass_cols: Array = []
	for i in 420:
		var x: float = ox + rng.randf() * size
		var z: float = oz + rng.randf() * size
		var wr: Vector4 = w.region_weights(x, z)
		if wr.z > 0.5 or rng.randf() > wr.x + wr.w + wr.y * 0.5:
			continue
		if w.road_dist(x, z) < 12.0:
			var q: Dictionary = w.road_query(x, z, 20.0)
			if q.ok and q.d < q.hw + 2.0:
				continue
		var h: float = w.height(x, z)
		if h < 1.5 or h > 200.0:
			continue
		var sc: float = rng.randf_range(0.8, 1.6)
		grass.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(sc, sc, sc)), Vector3(x, h - 0.05, z)))
		grass_cols.append(w.terrain_color(x, z, h, 0.0).darkened(0.1))
	if not grass.is_empty():
		out["grass"] = grass
		out["grass_cols"] = grass_cols
	return out


func spawn_instances(parent: Node3D, veg: Dictionary) -> void:
	for t in veg:
		var arr: Array = veg[t]
		if t == "grass_cols":
			continue
		if t == "grass":
			_mm(parent, grass_mesh, arr, 0.0, 150.0, false, veg.get("grass_cols", []))
			continue
		var def: Array = TYPES[t]
		_mm(parent, meshes[t], arr, 0.0, def[2], def[4])
		if def[1] != "":
			_mm(parent, meshes[t + "_lod"], arr, def[2], def[3], false)
		stats_instances += arr.size()


func _mm(parent: Node3D, mesh: Mesh, arr: Array, vmin: float, vmax: float, shadows: bool, cols: Array = []) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = not cols.is_empty()
	mm.mesh = mesh
	mm.instance_count = arr.size()
	for i in arr.size():
		mm.set_instance_transform(i, arr[i])
		if not cols.is_empty():
			mm.set_instance_color(i, cols[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.visibility_range_begin = vmin
	mmi.visibility_range_end = vmax
	if vmin > 0.0:
		mmi.visibility_range_begin_margin = 20.0
		mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mmi)
