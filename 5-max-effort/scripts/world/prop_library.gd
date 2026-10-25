class_name PropLibrary
extends RefCounted
## Loads Blender-exported props (assets/imported/props/<name>.glb) and prepares them for
## instancing: one merged Mesh per prop (for MultiMesh) with project materials swapped in
## (foliage wind shader, night-lit windows/lamps), plus the full scene for multi-part props.

const DIR := "res://assets/imported/props/"
const FOLIAGE := ["LeavesConifer", "LeavesBroad", "LeavesPoplar", "LeavesPine", "LeavesDry", "LeavesGrass", "LeavesWheat", "Cactus"]

static var _meshes: Dictionary = {}
static var _scenes: Dictionary = {}
static var _mats: Dictionary = {}


static func exists(name: String) -> bool:
	return ResourceLoader.exists(DIR + name + ".glb")


static func scene(name: String) -> PackedScene:
	if not _scenes.has(name):
		_scenes[name] = load(DIR + name + ".glb") if exists(name) else null
	return _scenes[name]


static func mesh(name: String) -> Mesh:
	## Single mesh of a one-object prop with project materials applied (cached).
	if _meshes.has(name):
		return _meshes[name]
	var ps := scene(name)
	if ps == null:
		_meshes[name] = null
		return null
	var inst := ps.instantiate()
	var found: Mesh = null
	for n in inst.find_children("*", "MeshInstance3D", true, false):
		found = (n as MeshInstance3D).mesh
		break
	inst.free()
	if found == null:
		_meshes[name] = null
		return null
	var m := found.duplicate() as Mesh
	for s in m.get_surface_count():
		var src := m.surface_get_material(s)
		var key := src.resource_name if src != null else ""
		var rep := material_for(key, src)
		if rep != null:
			m.surface_set_material(s, rep)
	_meshes[name] = m
	return m


static func material_for(key: String, src: Material) -> Material:
	if key == "":
		return null
	if _mats.has(key):
		return _mats[key]
	var out: Material = null
	if FOLIAGE.has(key):
		var sm := ShaderMaterial.new()
		sm.shader = load("res://assets/shaders/foliage.gdshader")
		var base := Color(0.2, 0.35, 0.1)
		if src is BaseMaterial3D:
			base = (src as BaseMaterial3D).albedo_color
		# darker, richer than the Blender viewport colours
		base = Color(base.r * 0.75, base.g * 0.8, base.b * 0.7)
		sm.set_shader_parameter("base_color", base)
		var sway := 0.12
		match key:
			"LeavesGrass", "LeavesWheat":
				sway = 0.25
			"Cactus":
				sway = 0.0
			"LeavesPoplar":
				sway = 0.2
		sm.set_shader_parameter("sway", sway)
		sm.set_shader_parameter("sway_height", 1.0 if key in ["LeavesGrass", "LeavesWheat"] else 9.0)
		sm.set_shader_parameter("translucency", 0.0 if key == "Cactus" else 0.35)
		out = sm
	elif key == "WindowGlass" or key == "LampLight" or key == "LedScreen":
		var sm2 := ShaderMaterial.new()
		sm2.shader = load("res://assets/shaders/night_emissive.gdshader")
		sm2.set_shader_parameter("mode", 0 if key == "WindowGlass" else 1)
		if key == "LedScreen":
			sm2.set_shader_parameter("glow_color", Color(0.3, 0.7, 1.0))
			sm2.set_shader_parameter("glow", 3.0)
		if key == "LampLight":
			sm2.set_shader_parameter("day_color", Color(0.9, 0.85, 0.7))
			sm2.set_shader_parameter("glow", 4.0)
		out = sm2
	elif src is BaseMaterial3D:
		var bm := (src as BaseMaterial3D).duplicate() as BaseMaterial3D
		bm.roughness = maxf(bm.roughness, 0.45)
		out = bm
	_mats[key] = out
	return out


static func apply_to_scene(root: Node) -> void:
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		for s in mi.mesh.get_surface_count():
			var src := mi.mesh.surface_get_material(s)
			var rep := material_for(src.resource_name if src != null else "", src)
			if rep != null:
				mi.set_surface_override_material(s, rep)
