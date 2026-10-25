extends RefCounted
## Shared, procedurally built resources for vehicle effects (meshes, draw materials, particle
## process materials). Built once and cached; nothing is loaded from disk except the fx shaders.

const SOFT_SHADER := preload("res://assets/shaders/fx_soft_particle.gdshader")
const SPARK_SHADER := preload("res://assets/shaders/fx_spark.gdshader")
const FLAME_SHADER := preload("res://assets/shaders/fx_flame.gdshader")
const QUALITY_SCALE: Array[float] = [0.45, 0.7, 1.0, 1.3]

static var _cache: Dictionary = {}


## Particle count multiplier from the graphics quality setting (0 low .. 3 ultra).
static func quality_scale() -> float:
	var q := int(Settings.get_value("quality", 2))
	return QUALITY_SCALE[clampi(q, 0, QUALITY_SCALE.size() - 1)]


static func curve_tex(points: Array[Vector2], max_value := 1.0) -> CurveTexture:
	var c := Curve.new()
	c.max_value = max_value
	for p in points:
		c.add_point(p)
	var t := CurveTexture.new()
	t.width = 64
	t.curve = c
	return t


static func gradient_tex(offsets: PackedFloat32Array, colors: PackedColorArray) -> GradientTexture1D:
	var g := Gradient.new()
	g.offsets = offsets
	g.colors = colors
	var t := GradientTexture1D.new()
	t.width = 64
	t.gradient = g
	return t


# ------------------------------------------------------------------ meshes

static func quad() -> QuadMesh:
	if not _cache.has(&"quad"):
		var q := QuadMesh.new()
		q.size = Vector2.ONE
		_cache[&"quad"] = q
	return _cache[&"quad"]


static func spark_quad() -> QuadMesh:
	if not _cache.has(&"spark_quad"):
		var q := QuadMesh.new()
		q.size = Vector2(0.055, 0.5)
		_cache[&"spark_quad"] = q
	return _cache[&"spark_quad"]


static func debris_mesh() -> BoxMesh:
	if not _cache.has(&"debris_mesh"):
		var b := BoxMesh.new()
		b.size = Vector3(0.09, 0.025, 0.07)
		var m := StandardMaterial3D.new()
		m.vertex_color_use_as_albedo = true
		m.roughness = 0.55
		m.metallic = 0.1
		b.material = m
		_cache[&"debris_mesh"] = b
	return _cache[&"debris_mesh"]


## Two crossed quads along +Z (0..1) for the flame body plus a glow disc at the nozzle.
static func flame_mesh() -> ArrayMesh:
	if _cache.has(&"flame_mesh"):
		return _cache[&"flame_mesh"]
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	var body := Color(0, 0, 0)
	for axis: Vector3 in [Vector3.RIGHT, Vector3.UP]:
		var b := verts.size()
		var h := axis * 0.5
		verts.append_array(PackedVector3Array([-h, h, h + Vector3(0, 0, 1), -h + Vector3(0, 0, 1)]))
		uvs.append_array(PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]))
		cols.append_array(PackedColorArray([body, body, body, body]))
		idx.append_array(PackedInt32Array([b, b + 1, b + 2, b, b + 2, b + 3]))
	var b2 := verts.size()
	var r := 0.9
	var disc := Color(1, 0, 0)
	verts.append_array(PackedVector3Array([Vector3(-r, -r, 0.03), Vector3(r, -r, 0.03), Vector3(r, r, 0.03), Vector3(-r, r, 0.03)]))
	uvs.append_array(PackedVector2Array([Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]))
	cols.append_array(PackedColorArray([disc, disc, disc, disc]))
	idx.append_array(PackedInt32Array([b2, b2 + 1, b2 + 2, b2, b2 + 2, b2 + 3]))
	var normals := PackedVector3Array()
	normals.resize(verts.size())
	normals.fill(Vector3.UP)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_INDEX] = idx
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mat := ShaderMaterial.new()
	mat.shader = FLAME_SHADER
	am.surface_set_material(0, mat)
	_cache[&"flame_mesh"] = am
	return am


# ------------------------------------------------------------------ draw materials

## Soft lit billboard material. kind: smoke, dust, spray, exhaust, snow.
static func soft_material(kind: StringName) -> ShaderMaterial:
	var key := StringName("soft_" + String(kind))
	if _cache.has(key):
		return _cache[key]
	var m := ShaderMaterial.new()
	m.shader = SOFT_SHADER
	var p := {"density": 1.0, "softness": 0.8, "billow": 0.6, "noise_scale": 1.6, "backlight_amount": 0.45, "near_fade": 1.4, "self_light": 0.0}
	match kind:
		&"smoke":
			p.merge({"density": 0.95, "softness": 1.2, "billow": 0.85, "noise_scale": 1.5, "backlight_amount": 0.55, "self_light": 0.06, "near_fade": 2.0}, true)
		&"dust":
			p.merge({"density": 1.45, "softness": 1.4, "billow": 0.85, "noise_scale": 1.8, "backlight_amount": 0.4, "self_light": 0.24, "near_fade": 3.0}, true)
		&"snow":
			p.merge({"density": 1.1, "softness": 1.0, "billow": 0.8, "noise_scale": 2.0, "backlight_amount": 0.6, "self_light": 0.1, "near_fade": 3.0}, true)
		&"spray":
			p.merge({"density": 0.8, "softness": 0.8, "billow": 0.3, "noise_scale": 1.2, "backlight_amount": 0.6, "self_light": 0.1, "near_fade": 3.0, "bulge": 0.35}, true)
		&"exhaust":
			p.merge({"density": 0.8, "softness": 0.3, "billow": 0.7, "noise_scale": 1.5, "backlight_amount": 0.3, "near_fade": 0.8}, true)
	for k: String in p:
		m.set_shader_parameter(k, p[k])
	_cache[key] = m
	return m


static func spark_material() -> ShaderMaterial:
	if not _cache.has(&"spark_mat"):
		var m := ShaderMaterial.new()
		m.shader = SPARK_SHADER
		_cache[&"spark_mat"] = m
	return _cache[&"spark_mat"]


# ------------------------------------------------------------------ process materials

static func _base_puff(dir: Vector3, spread: float, vel: Vector2, inherit: float, gravity_y: float, damping: Vector2) -> ParticleProcessMaterial:
	var pm := ParticleProcessMaterial.new()
	pm.direction = dir.normalized()
	pm.spread = spread
	pm.initial_velocity_min = vel.x
	pm.initial_velocity_max = vel.y
	pm.inherit_velocity_ratio = inherit
	pm.gravity = Vector3(0, gravity_y, 0)
	pm.damping_min = damping.x
	pm.damping_max = damping.y
	pm.particle_flag_damping_as_friction = true
	pm.angle_min = -180.0
	pm.angle_max = 180.0
	pm.angular_velocity_min = -24.0
	pm.angular_velocity_max = 24.0
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.6
	pm.turbulence_noise_scale = 4.0
	pm.turbulence_noise_speed = Vector3(0.0, 0.25, 0.0)
	pm.turbulence_influence_min = 0.03
	pm.turbulence_influence_max = 0.08
	return pm


## Tyre smoke on hard surfaces: big, slow, lingering white-grey billows.
static func smoke_process() -> ParticleProcessMaterial:
	if _cache.has(&"smoke_proc"):
		return _cache[&"smoke_proc"]
	var pm := _base_puff(Vector3(0, 1.0, 0.55), 40.0, Vector2(0.6, 1.9), 0.12, 0.3, Vector2(1.2, 2.0))
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(0.12, 0.04, 0.22)
	pm.scale_min = 0.85
	pm.scale_max = 1.35
	pm.scale_curve = curve_tex([Vector2(0, 0.55), Vector2(0.18, 1.6), Vector2(0.55, 2.7), Vector2(1, 3.6)], 4.0)
	pm.alpha_curve = curve_tex([Vector2(0, 0), Vector2(0.05, 1), Vector2(0.4, 0.7), Vector2(1, 0)])
	pm.color = Color(0.88, 0.88, 0.9, 0.62)
	pm.lifetime_randomness = 0.35
	_cache[&"smoke_proc"] = pm
	return pm


## Dust / snow powder kicked up behind a wheel. Duplicated per wheel so each can carry its surface colour.
static func dust_process() -> ParticleProcessMaterial:
	if not _cache.has(&"dust_proc"):
		var pm := _base_puff(Vector3(0, 0.55, 1.0), 30.0, Vector2(1.5, 4.0), 0.3, -0.3, Vector2(1.4, 2.4))
		pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
		pm.emission_box_extents = Vector3(0.2, 0.06, 0.25)
		pm.scale_min = 1.0
		pm.scale_max = 1.6
		pm.scale_curve = curve_tex([Vector2(0, 0.8), Vector2(0.15, 1.9), Vector2(0.5, 3.2), Vector2(1, 4.8)], 5.0)
		pm.alpha_curve = curve_tex([Vector2(0, 0), Vector2(0.06, 1), Vector2(0.45, 0.6), Vector2(1, 0)])
		pm.color = Color(0.55, 0.45, 0.32, 0.6)
		pm.lifetime_randomness = 0.4
		_cache[&"dust_proc"] = pm
	return (_cache[&"dust_proc"] as ParticleProcessMaterial).duplicate()


## Rain spray thrown off the tyres: a fine mist plume that travels with the car and falls back.
static func spray_process() -> ParticleProcessMaterial:
	if _cache.has(&"spray_proc"):
		return _cache[&"spray_proc"]
	var pm := _base_puff(Vector3(0, 0.4, 1.0), 25.0, Vector2(2.0, 5.0), 0.75, -0.8, Vector2(1.2, 1.8))
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(0.14, 0.05, 0.12)
	pm.scale_min = 0.5
	pm.scale_max = 0.8
	pm.scale_curve = curve_tex([Vector2(0, 0.5), Vector2(0.3, 2.2), Vector2(1, 4.5)], 5.0)
	pm.alpha_curve = curve_tex([Vector2(0, 0), Vector2(0.12, 1), Vector2(0.5, 0.5), Vector2(1, 0)])
	pm.color = Color(0.82, 0.85, 0.88, 0.11)
	pm.lifetime_randomness = 0.3
	pm.turbulence_enabled = false
	_cache[&"spray_proc"] = pm
	return pm


## Light exhaust vapour at the tailpipe.
static func exhaust_process() -> ParticleProcessMaterial:
	if _cache.has(&"exhaust_proc"):
		return _cache[&"exhaust_proc"]
	var pm := _base_puff(Vector3(0, 0.12, 1.0), 10.0, Vector2(1.4, 2.6), 0.2, 0.45, Vector2(1.8, 2.8))
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.03
	pm.scale_min = 0.16
	pm.scale_max = 0.24
	pm.scale_curve = curve_tex([Vector2(0, 0.6), Vector2(0.3, 2.0), Vector2(1, 4.0)], 4.0)
	pm.alpha_curve = curve_tex([Vector2(0, 0), Vector2(0.1, 1), Vector2(1, 0)])
	pm.color = Color(0.66, 0.66, 0.68, 0.2)
	pm.lifetime_randomness = 0.3
	_cache[&"exhaust_proc"] = pm
	return pm


## Impact sparks: hot streaks that fall and cool from white-yellow to red.
static func spark_process() -> ParticleProcessMaterial:
	if _cache.has(&"spark_proc"):
		return _cache[&"spark_proc"]
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.12
	pm.direction = Vector3(0, 0.45, -1).normalized()
	pm.spread = 70.0
	pm.initial_velocity_min = 4.0
	pm.initial_velocity_max = 13.0
	pm.inherit_velocity_ratio = 0.0
	pm.gravity = Vector3(0, -9.8, 0)
	pm.damping_min = 0.4
	pm.damping_max = 1.2
	pm.particle_flag_damping_as_friction = true
	pm.scale_min = 0.55
	pm.scale_max = 1.25
	pm.color_ramp = gradient_tex(PackedFloat32Array([0.0, 0.25, 0.65, 1.0]),
		PackedColorArray([Color(1.0, 0.95, 0.75, 1.0), Color(1.0, 0.72, 0.3, 1.0), Color(1.0, 0.35, 0.08, 0.8), Color(0.8, 0.12, 0.02, 0.0)]))
	pm.lifetime_randomness = 0.55
	_cache[&"spark_proc"] = pm
	return pm


## Continuous grinding sparks while the body slides along a wall / the ground (trail behind the car).
static func scrape_process() -> ParticleProcessMaterial:
	if _cache.has(&"scrape_proc"):
		return _cache[&"scrape_proc"]
	var pm: ParticleProcessMaterial = spark_process().duplicate()
	pm.emission_sphere_radius = 0.06
	pm.direction = Vector3(0, 0.3, 1).normalized()
	pm.spread = 32.0
	pm.initial_velocity_min = 2.0
	pm.initial_velocity_max = 7.0
	pm.inherit_velocity_ratio = 0.6
	_cache[&"scrape_proc"] = pm
	return pm


## Small broken plastic / trim chunks for hard impacts.
static func debris_process() -> ParticleProcessMaterial:
	if _cache.has(&"debris_proc"):
		return _cache[&"debris_proc"]
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.25
	pm.direction = Vector3(0, 1, -0.3).normalized()
	pm.spread = 70.0
	pm.initial_velocity_min = 2.0
	pm.initial_velocity_max = 5.5
	pm.gravity = Vector3(0, -9.8, 0)
	pm.particle_flag_rotate_y = true
	pm.angle_min = -180.0
	pm.angle_max = 180.0
	pm.angular_velocity_min = -540.0
	pm.angular_velocity_max = 540.0
	pm.scale_min = 0.6
	pm.scale_max = 1.5
	pm.scale_curve = curve_tex([Vector2(0, 1), Vector2(0.75, 1), Vector2(1, 0)])
	pm.color_initial_ramp = gradient_tex(PackedFloat32Array([0.0, 0.5, 0.8, 1.0]),
		PackedColorArray([Color(0.04, 0.04, 0.045), Color(0.12, 0.12, 0.13), Color(0.3, 0.3, 0.32), Color(0.7, 0.72, 0.75)]))
	pm.lifetime_randomness = 0.3
	_cache[&"debris_proc"] = pm
	return pm
