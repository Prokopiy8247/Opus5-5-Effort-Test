class_name KitMaterials
extends RefCounted
## Project materials for world kit pieces, keyed by the Blender material name.

static var _cache := {}


static func get_mat(name: String, fallback: Material) -> Material:
	if _cache.has(name):
		return _cache[name]
	var m := StandardMaterial3D.new()
	m.resource_name = name
	var known := true
	match name:
		"Leaves", "LeavesBroad":
			m.albedo_color = Color(0.2, 0.33, 0.1)
			m.roughness = 0.85
			m.backlight_enabled = true
			m.backlight = Color(0.25, 0.35, 0.1)
		"LeavesPine":
			m.albedo_color = Color(0.1, 0.2, 0.1)
			m.roughness = 0.9
		"LeavesOlive":
			m.albedo_color = Color(0.32, 0.38, 0.2)
			m.roughness = 0.85
		"LeavesDry":
			m.albedo_color = Color(0.45, 0.4, 0.22)
			m.roughness = 0.9
		"PalmLeaf":
			m.albedo_color = Color(0.25, 0.42, 0.12)
			m.roughness = 0.8
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
		"Bark":
			m.albedo_color = Color(0.25, 0.18, 0.12)
			m.roughness = 0.95
		"BarkPale":
			m.albedo_color = Color(0.5, 0.45, 0.38)
			m.roughness = 0.9
		"Cactus":
			m.albedo_color = Color(0.25, 0.38, 0.18)
			m.roughness = 0.7
		"Rock":
			m.albedo_color = Color(0.45, 0.43, 0.4)
			m.roughness = 0.95
		"RockRed":
			m.albedo_color = Color(0.6, 0.33, 0.2)
			m.roughness = 0.95
		"Plaster":
			m.albedo_color = Color(0.9, 0.85, 0.74)
			m.roughness = 0.9
		"PlasterOchre":
			m.albedo_color = Color(0.86, 0.66, 0.4)
			m.roughness = 0.9
		"PlasterPink":
			m.albedo_color = Color(0.88, 0.7, 0.66)
			m.roughness = 0.9
		"PlasterBlue":
			m.albedo_color = Color(0.62, 0.75, 0.82)
			m.roughness = 0.9
		"RoofTile":
			m.albedo_color = Color(0.62, 0.25, 0.14)
			m.roughness = 0.8
		"RoofSlate":
			m.albedo_color = Color(0.22, 0.24, 0.27)
			m.roughness = 0.7
		"Wood", "WoodDark":
			m.albedo_color = Color(0.36, 0.22, 0.12) if name == "Wood" else Color(0.2, 0.13, 0.08)
			m.roughness = 0.85
		"Stone":
			m.albedo_color = Color(0.58, 0.55, 0.5)
			m.roughness = 0.95
		"StoneDark":
			m.albedo_color = Color(0.38, 0.36, 0.33)
			m.roughness = 0.95
		"Concrete":
			m.albedo_color = Color(0.62, 0.61, 0.58)
			m.roughness = 0.9
		"Metal", "Steel":
			m.albedo_color = Color(0.62, 0.63, 0.65)
			m.metallic = 0.85
			m.roughness = 0.35
		"MetalRed":
			m.albedo_color = Color(0.7, 0.12, 0.08)
			m.metallic = 0.4
			m.roughness = 0.45
		"WindowGlass", "Glass":
			m.albedo_color = Color(0.15, 0.2, 0.25)
			m.metallic = 0.6
			m.roughness = 0.08
		"WindowLit":
			# reads as glass by day; Structures.set_night() raises the emission after dusk
			m.albedo_color = Color(0.17, 0.21, 0.25)
			m.metallic = 0.5
			m.roughness = 0.12
			m.emission_enabled = true
			m.emission = Color(1.0, 0.75, 0.4)
			m.emission_energy_multiplier = 0.0
		"Lamp":
			m.albedo_color = Color(1.0, 0.95, 0.8)
			m.emission_enabled = true
			m.emission = Color(1.0, 0.85, 0.6)
			m.emission_energy_multiplier = 0.2
		"SignWhite":
			m.albedo_color = Color(0.92, 0.92, 0.9)
			m.roughness = 0.5
		"SignRed":
			m.albedo_color = Color(0.8, 0.1, 0.08)
			m.roughness = 0.5
		"SignBlue":
			m.albedo_color = Color(0.1, 0.3, 0.7)
			m.roughness = 0.5
		"SignGreen":
			m.albedo_color = Color(0.05, 0.4, 0.2)
			m.roughness = 0.5
		"SignYellow":
			m.albedo_color = Color(0.95, 0.75, 0.1)
			m.roughness = 0.5
		"Reflector":
			m.albedo_color = Color(1.0, 0.6, 0.1)
			m.emission_enabled = true
			m.emission = Color(1.0, 0.5, 0.05)
			m.emission_energy_multiplier = 0.4
		"Fabric", "FabricRed", "FabricBlue", "FabricYellow":
			m.albedo_color = {"Fabric": Color(0.92, 0.9, 0.85), "FabricRed": Color(0.85, 0.15, 0.25),
				"FabricBlue": Color(0.15, 0.45, 0.85), "FabricYellow": Color(0.98, 0.75, 0.1)}[name]
			m.roughness = 0.8
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
		"BarnRed":
			m.albedo_color = Color(0.55, 0.13, 0.09)
			m.roughness = 0.85
		"Hay":
			m.albedo_color = Color(0.78, 0.65, 0.35)
			m.roughness = 1.0
		"Grass":
			m.albedo_color = Color(0.3, 0.42, 0.14)
			m.roughness = 0.9
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
			m.vertex_color_use_as_albedo = true  # per-instance tint from the grass MultiMesh
		"Flower":
			m.albedo_color = Color(0.9, 0.85, 0.3)
			m.roughness = 0.8
		"White":
			m.albedo_color = Color(0.94, 0.94, 0.92)
			m.roughness = 0.6
		"Black":
			m.albedo_color = Color(0.04, 0.04, 0.045)
			m.roughness = 0.6
		_:
			known = false
	if not known:
		if fallback != null:
			_cache[name] = fallback
			return fallback
		m.albedo_color = Color(0.6, 0.6, 0.6)
	_cache[name] = m
	return m
