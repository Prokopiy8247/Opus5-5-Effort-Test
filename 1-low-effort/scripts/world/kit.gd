class_name Kit
extends RefCounted
## Access to Blender-authored prop meshes exported to res://assets/imported/props/*.glb.
## Each GLB holds one or more named meshes; Kit.mesh("Name") returns the first match.

static var _cache: Dictionary = {}
static var _scenes: Dictionary = {}
const FILES := ["res://assets/imported/props/kit.glb", "res://assets/imported/props/nature.glb", "res://assets/imported/props/buildings.glb"]

static func _load_all() -> void:
	if not _scenes.is_empty(): return
	for f in FILES:
		if not ResourceLoader.exists(f):
			continue
		var ps := load(f) as PackedScene
		if ps == null: continue
		var root := ps.instantiate()
		_scenes[f] = root
		_collect(root)

static func _collect(n: Node) -> void:
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		if mi.mesh != null and not _cache.has(mi.name):
			_cache[String(mi.name)] = mi.mesh
	for c in n.get_children(): _collect(c)

static func has(name: String) -> bool:
	_load_all()
	return _cache.has(name)

static func mesh(name: String, fallback_size: Vector3 = Vector3.ONE, color: Color = Color(0.6, 0.6, 0.6)) -> Mesh:
	_load_all()
	if _cache.has(name): return _cache[name]
	var b := BoxMesh.new()
	b.size = fallback_size
	var m := StandardMaterial3D.new(); m.albedo_color = color
	b.material = m
	_cache[name] = b
	push_warning("Kit mesh missing, using fallback box: " + name)
	return b
