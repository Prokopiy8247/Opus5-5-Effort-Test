class_name CarMaterials
extends RefCounted
## Godot-side materials for Blender-authored vehicles. Blender material names act as tags
## (Paint, Glass, Chrome, Rubber, Rim, Trim, Interior, Seat, LightHead, LightTail, ...);
## the imported glTF materials are replaced by these so paint/finish and light states
## can be driven at runtime.

static var _cache: Dictionary = {}


static var _paint_shader: Shader


static func paint(color: Color, finish: int, stripes: bool = false) -> ShaderMaterial:
	if _paint_shader == null:
		_paint_shader = load("res://assets/shaders/car_paint.gdshader")
	var m := ShaderMaterial.new()
	m.resource_name = "PaintRuntime"
	m.shader = _paint_shader
	set_paint(m, color, finish)
	m.set_shader_parameter("stripes", stripes)
	return m


static func set_paint(m: ShaderMaterial, color: Color, finish: int) -> void:
	m.set_shader_parameter("base_color", color)
	var met := 0.05
	var rough := 0.16
	var cc := 1.0
	var ccr := 0.04
	var flake := 0.0
	var pearl := 0.0
	match finish:
		CarDefinition.Finish.METALLIC:
			met = 0.72
			rough = 0.32
			ccr = 0.05
			flake = 0.6
		CarDefinition.Finish.MATTE:
			met = 0.1
			rough = 0.7
			cc = 0.0
		CarDefinition.Finish.PEARL:
			met = 0.45
			rough = 0.24
			ccr = 0.03
			flake = 0.35
			pearl = 0.55
	m.set_shader_parameter("metallic", met)
	m.set_shader_parameter("roughness", rough)
	m.set_shader_parameter("clearcoat", cc)
	m.set_shader_parameter("clearcoat_roughness", ccr)
	m.set_shader_parameter("flake", flake)
	m.set_shader_parameter("pearl", pearl)
	# stripes contrast with the body colour
	var lum := color.get_luminance()
	m.set_shader_parameter("stripe_color", Color(0.06, 0.06, 0.07) if lum > 0.55 else Color(0.95, 0.95, 0.95))


static func _make(key: String) -> Material:
	var m := StandardMaterial3D.new()
	m.resource_name = key
	match key:
		"glass":
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.albedo_color = Color(0.06, 0.08, 0.1, 0.55)
			m.metallic = 0.2
			m.roughness = 0.03
			m.metallic_specular = 1.0
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
		"chrome":
			m.albedo_color = Color(0.85, 0.86, 0.88)
			m.metallic = 1.0
			m.roughness = 0.08
		"rubber":
			m.albedo_color = Color(0.035, 0.035, 0.038)
			m.roughness = 0.9
		"rim":
			m.albedo_color = Color(0.62, 0.63, 0.66)
			m.metallic = 0.9
			m.roughness = 0.25
		"rim_dark":
			m.albedo_color = Color(0.09, 0.09, 0.1)
			m.metallic = 0.7
			m.roughness = 0.35
		"rim_gold":
			m.albedo_color = Color(0.75, 0.58, 0.25)
			m.metallic = 0.95
			m.roughness = 0.25
		"trim":
			m.albedo_color = Color(0.03, 0.03, 0.035)
			m.roughness = 0.45
		"trim_matte":
			m.albedo_color = Color(0.06, 0.06, 0.065)
			m.roughness = 0.75
		"carbon":
			m.albedo_color = Color(0.05, 0.05, 0.055)
			m.roughness = 0.2
			m.metallic = 0.3
			m.clearcoat_enabled = true
		"interior":
			m.albedo_color = Color(0.09, 0.09, 0.095)
			m.roughness = 0.8
		"seat":
			m.albedo_color = Color(0.16, 0.11, 0.09)
			m.roughness = 0.6
		"dash":
			m.albedo_color = Color(0.05, 0.05, 0.055)
			m.roughness = 0.55
		"gauge":
			m.albedo_color = Color(0.05, 0.06, 0.08)
			m.emission_enabled = true
			m.emission = Color(0.4, 0.7, 1.0)
			m.emission_energy_multiplier = 0.6
		"light_head":
			m.albedo_color = Color(0.95, 0.95, 0.92)
			m.metallic = 0.3
			m.roughness = 0.05
			m.emission_enabled = true
			m.emission = Color(1.0, 0.96, 0.88)
			m.emission_energy_multiplier = 0.3
		"light_tail":
			m.albedo_color = Color(0.45, 0.02, 0.02)
			m.roughness = 0.1
			m.emission_enabled = true
			m.emission = Color(1.0, 0.05, 0.03)
			m.emission_energy_multiplier = 0.6
		"light_reverse":
			m.albedo_color = Color(0.85, 0.85, 0.85)
			m.roughness = 0.1
			m.emission_enabled = true
			m.emission = Color(1, 1, 1)
			m.emission_energy_multiplier = 0.0
		"light_indicator":
			m.albedo_color = Color(0.85, 0.45, 0.05)
			m.roughness = 0.1
			m.emission_enabled = true
			m.emission = Color(1.0, 0.5, 0.05)
			m.emission_energy_multiplier = 0.15
		"grille":
			m.albedo_color = Color(0.02, 0.02, 0.022)
			m.roughness = 0.5
			m.metallic = 0.4
		"plate":
			m.albedo_color = Color(0.92, 0.92, 0.86)
			m.roughness = 0.4
		"disc":
			m.albedo_color = Color(0.42, 0.42, 0.43)
			m.metallic = 0.85
			m.roughness = 0.45
		"caliper":
			m.albedo_color = Color(0.75, 0.08, 0.05)
			m.roughness = 0.35
		"under":
			m.albedo_color = Color(0.04, 0.04, 0.04)
			m.roughness = 0.95
		"exhaust":
			m.albedo_color = Color(0.5, 0.48, 0.45)
			m.metallic = 0.9
			m.roughness = 0.35
		"wood":
			m.albedo_color = Color(0.36, 0.2, 0.1)
			m.roughness = 0.4
			m.clearcoat_enabled = true
		"canvas":
			m.albedo_color = Color(0.12, 0.11, 0.1)
			m.roughness = 0.95
		"mirror":
			m.albedo_color = Color(0.9, 0.92, 0.95)
			m.metallic = 1.0
			m.roughness = 0.02
		_:
			m.albedo_color = Color(0.5, 0.5, 0.5)
			m.roughness = 0.6
	return m


static func get_mat(key: String) -> Material:
	if not _cache.has(key):
		_cache[key] = _make(key)
	return _cache[key]


static func key_for(material_name: String) -> String:
	## Maps a Blender material name (tag) to a runtime material key ("" = paint).
	var n := material_name.to_lower()
	if n.begins_with("paint"):
		return "paint"
	var table := [
		["glass", "glass"], ["chrome", "chrome"], ["rubber", "rubber"], ["tire", "rubber"],
		["rimgold", "rim_gold"], ["rimdark", "rim_dark"], ["rim", "rim"], ["trimmatte", "trim_matte"],
		["trim", "trim"], ["carbon", "carbon"], ["seat", "seat"], ["dash", "dash"], ["gauge", "gauge"],
		["interior", "interior"], ["lighthead", "light_head"], ["lighttail", "light_tail"],
		["lightreverse", "light_reverse"], ["lightind", "light_indicator"], ["grille", "grille"],
		["plate", "plate"], ["disc", "disc"], ["caliper", "caliper"], ["under", "under"],
		["exhaust", "exhaust"], ["wood", "wood"], ["canvas", "canvas"], ["mirror", "mirror"],
	]
	for pair in table:
		if n.begins_with(pair[0]):
			return pair[1]
	return ""


static func apply(root: Node, paint_mat: Material, unique_lights: bool = true) -> Dictionary:
	## Replaces materials on every mesh under root. Returns per-instance light materials
	## {"tail": mat, "reverse": mat, "head": mat} so lights can be animated per car.
	var lights := {}
	if unique_lights:
		lights["tail"] = (get_mat("light_tail") as StandardMaterial3D).duplicate()
		lights["reverse"] = (get_mat("light_reverse") as StandardMaterial3D).duplicate()
		lights["head"] = (get_mat("light_head") as StandardMaterial3D).duplicate()
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null:
			continue
		for s in mi.mesh.get_surface_count():
			var src := mi.mesh.surface_get_material(s)
			var src_name := src.resource_name if src != null else ""
			var key := key_for(src_name)
			var mat: Material
			if key == "paint":
				mat = paint_mat
			elif key == "":
				mat = src if src != null else get_mat("trim")
			elif unique_lights and key == "light_tail":
				mat = lights["tail"]
			elif unique_lights and key == "light_reverse":
				mat = lights["reverse"]
			elif unique_lights and key == "light_head":
				mat = lights["head"]
			else:
				mat = get_mat(key)
			mi.set_surface_override_material(s, mat)
	return lights
