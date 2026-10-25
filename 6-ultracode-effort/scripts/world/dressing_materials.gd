extends RefCounted
## Shared materials for dressing, settlements and placeholder props. A handful of ShaderMaterials
## shared by everything keeps state changes low; global look parameters (wind, wetness, snow, night)
## are pushed to all of them through set_param().

const FOLIAGE_SHADER := "res://assets/shaders/foliage.gdshader"
const GRASS_SHADER := "res://assets/shaders/grass.gdshader"
const BUILDING_SHADER := "res://assets/shaders/building_props.gdshader"

static var _foliage: ShaderMaterial
static var _foliage_2s: Shader
static var _grass: ShaderMaterial
static var _solid: ShaderMaterial
static var _all: Array[ShaderMaterial] = []
static var _params: Dictionary = {}


static func _register(m: ShaderMaterial) -> ShaderMaterial:
	_all.append(m)
	for k: StringName in _params:
		_apply(m, k, _params[k])
	return m


static func _apply(m: ShaderMaterial, key: StringName, value: Variant) -> void:
	if m.shader == null:
		return
	for u: Dictionary in m.shader.get_shader_uniform_list():
		if StringName(u["name"]) == key:
			m.set_shader_parameter(key, value)
			return


static func foliage() -> ShaderMaterial:
	if _foliage == null:
		_foliage = ShaderMaterial.new()
		_foliage.shader = load(FOLIAGE_SHADER)
		_register(_foliage)
	return _foliage


static func grass() -> ShaderMaterial:
	if _grass == null:
		_grass = ShaderMaterial.new()
		_grass.shader = load(GRASS_SHADER)
		_register(_grass)
	return _grass


static func solid() -> ShaderMaterial:
	if _solid == null:
		_solid = ShaderMaterial.new()
		_solid.shader = load(BUILDING_SHADER)
		_register(_solid)
	return _solid


## Wind-enabled replacement for a kit (Blender) vegetation material. Keeps albedo colour/texture.
static func foliage_from(src: Material, leaf: bool) -> ShaderMaterial:
	if _foliage_2s == null:
		var base: Shader = load(FOLIAGE_SHADER)
		_foliage_2s = Shader.new()
		_foliage_2s.code = base.code.replace("cull_back", "cull_disabled")
	var m := ShaderMaterial.new()
	m.shader = _foliage_2s
	m.set_shader_parameter("leaf_override", 1.0 if leaf else 0.0)
	var sm := src as BaseMaterial3D
	if sm != null:
		m.set_shader_parameter("albedo", sm.albedo_color)
		if sm.albedo_texture != null:
			m.set_shader_parameter("albedo_tex", sm.albedo_texture)
			m.set_shader_parameter("use_texture", true)
	return _register(m)


## Distance LOD of a dressing mesh (foliage.gdshader `lod`) on each surface material; a material shared with
## other props (the placeholder foliage material) is replaced by a mesh-private copy first.
static func set_mesh_lod(m: Mesh, lod: Vector3) -> void:
	var am := m as ArrayMesh
	for i in m.get_surface_count():
		var mat := m.surface_get_material(i) as ShaderMaterial
		if mat == null:
			continue
		if mat == _foliage and am != null:
			mat = _register(mat.duplicate() as ShaderMaterial)
			am.surface_set_material(i, mat)
		mat.set_shader_parameter(&"lod", lod)


static func get_param(key: StringName, default: Variant = null) -> Variant:
	return _params.get(key, default)


static func set_param(key: StringName, value: Variant) -> void:
	if _params.get(key) == value:
		return
	_params[key] = value
	for m in _all:
		_apply(m, key, value)
