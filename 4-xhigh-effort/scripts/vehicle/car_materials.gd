class_name CarMaterials
extends RefCounted
## Maps Blender material names (glTF material resource_name) to project materials.
## Shared materials are cached; paint, rims and lights are per-car instances.

const PAINT_SHADER := preload("res://assets/shaders/car_paint.gdshader")

enum Finish { GLOSS, METALLIC, MATTE, PEARL }
const FINISH_NAMES := ["Gloss", "Metallic", "Matte", "Pearl"]

static var _shared := {}


static func shared(mat_name: String) -> Material:
	if _shared.has(mat_name):
		return _shared[mat_name]
	var m := StandardMaterial3D.new()
	m.resource_name = mat_name
	match mat_name:
		"Glass":
			m.albedo_color = Color(0.06, 0.075, 0.09, 0.42)
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.roughness = 0.03
			m.metallic = 0.2
			m.metallic_specular = 0.9
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
		"GlassDark":
			m.albedo_color = Color(0.03, 0.04, 0.05)
			m.metallic = 0.6
			m.roughness = 0.06
		"BoxWhite":
			m.albedo_color = Color(0.9, 0.9, 0.88)
			m.roughness = 0.55
		"Trim":
			m.albedo_color = Color(0.03, 0.03, 0.032)
			m.roughness = 0.5
		"Underbody", "WheelWell":
			m.albedo_color = Color(0.015, 0.015, 0.015)
			m.roughness = 0.95
		"Chrome":
			m.albedo_color = Color(0.92, 0.92, 0.94)
			m.metallic = 1.0
			m.roughness = 0.06
		"Rubber":
			m.albedo_color = Color(0.035, 0.035, 0.037)
			m.roughness = 0.88
		"BrakeDisc":
			m.albedo_color = Color(0.4, 0.39, 0.38)
			m.metallic = 1.0
			m.roughness = 0.42
		"Caliper":
			m.albedo_color = Color(0.75, 0.1, 0.05)
			m.roughness = 0.35
		"Grille":
			m.albedo_color = Color(0.025, 0.025, 0.03)
			m.metallic = 0.4
			m.roughness = 0.4
		"Plate":
			m.albedo_color = Color(0.93, 0.91, 0.83)
			m.roughness = 0.4
		"Interior":
			m.albedo_color = Color(0.11, 0.105, 0.1)
			m.roughness = 0.85
		"Seat":
			m.albedo_color = Color(0.1, 0.065, 0.05)
			m.roughness = 0.75
		"Gauges":
			m.albedo_color = Color(0.02, 0.05, 0.07)
			m.emission_enabled = true
			m.emission = Color(0.2, 0.55, 0.75)
			m.emission_energy_multiplier = 0.35
			m.roughness = 0.15
		"Carbon":
			m.albedo_color = Color(0.04, 0.042, 0.046)
			m.metallic = 0.3
			m.roughness = 0.3
			m.clearcoat_enabled = true
		"Wood":
			m.albedo_color = Color(0.33, 0.17, 0.08)
			m.roughness = 0.35
			m.clearcoat_enabled = true
		"Canvas":
			m.albedo_color = Color(0.12, 0.1, 0.085)
			m.roughness = 0.95
		"Metal", "Steel":
			m.albedo_color = Color(0.5, 0.5, 0.52)
			m.metallic = 0.85
			m.roughness = 0.45
		_:
			m.albedo_color = Color(0.5, 0.5, 0.5)
			m.roughness = 0.6
	_shared[mat_name] = m
	return m


static func make_paint(color: Color, finish: int, stripe_mode := 0, stripe_color := Color.WHITE) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = PAINT_SHADER
	apply_paint(m, color, finish, stripe_mode, stripe_color)
	return m


static func apply_paint(m: ShaderMaterial, color: Color, finish: int, stripe_mode := 0, stripe_color := Color.WHITE) -> void:
	m.set_shader_parameter("base_color", color)
	m.set_shader_parameter("stripe_mode", stripe_mode)
	m.set_shader_parameter("stripe_color", stripe_color)
	match finish:
		Finish.GLOSS:
			m.set_shader_parameter("metallic_amount", 0.05)
			m.set_shader_parameter("roughness_amount", 0.18)
			m.set_shader_parameter("clearcoat_amount", 1.0)
			m.set_shader_parameter("flake_amount", 0.0)
			m.set_shader_parameter("pearl_amount", 0.0)
		Finish.METALLIC:
			m.set_shader_parameter("metallic_amount", 0.72)
			m.set_shader_parameter("roughness_amount", 0.3)
			m.set_shader_parameter("clearcoat_amount", 1.0)
			m.set_shader_parameter("flake_amount", 0.55)
			m.set_shader_parameter("pearl_amount", 0.0)
		Finish.MATTE:
			m.set_shader_parameter("metallic_amount", 0.1)
			m.set_shader_parameter("roughness_amount", 0.72)
			m.set_shader_parameter("clearcoat_amount", 0.0)
			m.set_shader_parameter("flake_amount", 0.0)
			m.set_shader_parameter("pearl_amount", 0.0)
		_:
			m.set_shader_parameter("metallic_amount", 0.45)
			m.set_shader_parameter("roughness_amount", 0.22)
			m.set_shader_parameter("clearcoat_amount", 1.0)
			m.set_shader_parameter("flake_amount", 0.3)
			m.set_shader_parameter("pearl_amount", 0.85)


static func make_rim(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.metallic = 1.0
	m.roughness = 0.22
	m.cull_mode = BaseMaterial3D.CULL_DISABLED  # the rim lip is a single folded sheet
	return m


static func make_light(kind: String) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.emission_enabled = true
	m.roughness = 0.08
	match kind:
		"LightHead":
			m.albedo_color = Color(0.9, 0.92, 0.95)
			m.emission = Color(1.0, 0.96, 0.88)
			m.emission_energy_multiplier = 0.4
		"LightTail":
			m.albedo_color = Color(0.45, 0.02, 0.02)
			m.emission = Color(1.0, 0.06, 0.03)
			m.emission_energy_multiplier = 0.3
		"LightReverse":
			m.albedo_color = Color(0.85, 0.85, 0.85)
			m.emission = Color(1, 1, 1)
			m.emission_energy_multiplier = 0.0
		_:
			m.albedo_color = Color(0.85, 0.4, 0.05)
			m.emission = Color(1.0, 0.5, 0.05)
			m.emission_energy_multiplier = 0.15
	return m
