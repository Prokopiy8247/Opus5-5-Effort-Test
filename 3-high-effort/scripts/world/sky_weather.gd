class_name SkyWeather
extends Node3D
## Day/night cycle + weather. Drives sun/moon, sky shader, fog, rain particles, lightning,
## global wetness and tyre grip (Game.weather_grip).

signal weather_changed(key: String)

const PRESET_DIR := "res://data/weather/"

var presets := {}
var current: WeatherPreset
var target: WeatherPreset
var blend := 1.0
var blend_time := 8.0
## In-game hours per real second (default: a full day in 24 minutes).
var time_speed := 1.0 / 60.0
var time_frozen := false
var auto_weather := false

var sun: DirectionalLight3D
var moon: DirectionalLight3D
var env: Environment
var world_env: WorldEnvironment
var sky_mat: ShaderMaterial
var rain_particles: GPUParticles3D
var _lightning_timer := 6.0
var _flash := 0.0
var _cloud_time := 0.0
var _auto_timer := 240.0
var follow: Node3D

# blended state
var s_cloud := 0.2
var s_dark := 0.0
var s_fog := 0.0004
var s_vfog := 0.0
var s_rain := 0.0
var s_wet := 0.0
var s_grip := 1.0
var s_sun := 1.0
var s_amb := 1.0


func _ready() -> void:
	_load_presets()
	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = 450.0
	sun.directional_shadow_blend_splits = true
	sun.shadow_bias = 0.04
	sun.shadow_normal_bias = 1.2
	sun.light_angular_distance = 0.6
	add_child(sun)
	moon = DirectionalLight3D.new()
	moon.name = "Moon"
	moon.shadow_enabled = false
	moon.light_color = Color(0.55, 0.65, 0.9)
	moon.light_energy = 0.0
	moon.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	add_child(moon)
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	sky_mat = ShaderMaterial.new()
	sky_mat.shader = load("res://shaders/sky.gdshader")
	var nt := NoiseTexture2D.new()
	var fn := FastNoiseLite.new()
	fn.seed = 77
	fn.frequency = 0.008
	fn.fractal_octaves = 5
	nt.noise = fn
	nt.width = 512
	nt.height = 512
	nt.seamless = true
	sky_mat.set_shader_parameter("cloud_noise", nt)
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_256
	sky.process_mode = Sky.PROCESS_MODE_REALTIME
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.0
	env.glow_enabled = true
	env.glow_intensity = 0.55
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 1.1
	env.ssao_enabled = true
	env.ssao_radius = 1.2
	env.ssao_intensity = 1.4
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	env.fog_density = 0.0004
	env.fog_sky_affect = 0.25
	env.fog_aerial_perspective = 0.55
	env.fog_height = 60.0
	env.fog_height_density = 0.002
	env.volumetric_fog_enabled = false
	env.volumetric_fog_density = 0.0
	env.volumetric_fog_length = 180.0
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.08
	env.adjustment_contrast = 1.04
	world_env = WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)
	_make_rain()
	var start: String = Game.weather_name if presets.has(Game.weather_name) else "clear"
	current = presets[start]
	target = current
	_apply_state(1.0)


func _load_presets() -> void:
	for f in ResourceLoader.list_directory(PRESET_DIR):
		if f.ends_with(".tres"):
			var p := load(PRESET_DIR + f) as WeatherPreset
			if p:
				presets[p.key] = p
	if presets.is_empty():
		var c := WeatherPreset.new()
		presets["clear"] = c


func set_weather(key: String, instant: bool = false) -> bool:
	if not presets.has(key):
		return false
	current = _snapshot()
	target = presets[key]
	blend = 1.0 if instant else 0.0
	Game.weather_name = key
	weather_changed.emit(key)
	if instant:
		_apply_state(1.0)
	return true


func _snapshot() -> WeatherPreset:
	var p := WeatherPreset.new()
	p.key = "blend"
	p.cloud_coverage = s_cloud
	p.cloud_darkness = s_dark
	p.fog_density = s_fog
	p.volumetric_fog = s_vfog
	p.rain = s_rain
	p.wetness = s_wet
	p.grip = s_grip
	p.sun_energy = s_sun
	p.ambient_energy = s_amb
	p.wind = target.wind if target else 0.3
	return p


func set_time(hour: float) -> void:
	Game.time_of_day = fposmod(hour, 24.0)


func _process(delta: float) -> void:
	var _t0 := Time.get_ticks_usec()
	_process_inner(delta)
	Game.prof_add("sky", Time.get_ticks_usec() - _t0)


func _process_inner(delta: float) -> void:
	if not time_frozen:
		Game.time_of_day = fposmod(Game.time_of_day + delta * time_speed, 24.0)
	if blend < 1.0:
		blend = minf(blend + delta / blend_time, 1.0)
	_apply_state(blend)
	_cloud_time += delta * (0.5 + target.wind * 2.0)
	sky_mat.set_shader_parameter("cloud_time", _cloud_time)
	if auto_weather:
		_auto_timer -= delta
		if _auto_timer <= 0.0:
			_auto_timer = randf_range(180.0, 420.0)
			var keys := ["clear", "clear", "cloudy", "cloudy", "rain", "fog", "storm"]
			set_weather(keys[randi() % keys.size()])
	# lightning
	if target.lightning and blend > 0.5:
		_lightning_timer -= delta
		if _lightning_timer <= 0.0:
			_lightning_timer = randf_range(4.0, 14.0)
			_flash = 1.0
	_flash = maxf(_flash - delta * 3.5, 0.0)
	if rain_particles and follow:
		rain_particles.global_position = follow.global_position + Vector3(0, 14, 0) + (follow.get("linear_velocity") if follow.get("linear_velocity") != null else Vector3.ZERO) * 0.45
	_update_sun()


func _apply_state(t: float) -> void:
	var a := current
	var b := target
	s_cloud = lerpf(a.cloud_coverage, b.cloud_coverage, t)
	s_dark = lerpf(a.cloud_darkness, b.cloud_darkness, t)
	s_fog = lerpf(a.fog_density, b.fog_density, t)
	s_vfog = lerpf(a.volumetric_fog, b.volumetric_fog, t)
	s_rain = lerpf(a.rain, b.rain, t)
	s_wet = lerpf(a.wetness, b.wetness, t)
	s_grip = lerpf(a.grip, b.grip, t)
	s_sun = lerpf(a.sun_energy, b.sun_energy, t)
	s_amb = lerpf(a.ambient_energy, b.ambient_energy, t)
	sky_mat.set_shader_parameter("cloud_coverage", s_cloud)
	sky_mat.set_shader_parameter("cloud_darkness", s_dark)
	env.fog_density = s_fog
	env.volumetric_fog_enabled = s_vfog > 0.001
	env.volumetric_fog_density = s_vfog
	Game.weather_grip = s_grip
	Game.wetness = s_wet
	RenderingServer.global_shader_parameter_set("wetness", s_wet)
	RenderingServer.global_shader_parameter_set("wind_strength", lerpf(a.wind, b.wind, t))
	if rain_particles:
		rain_particles.emitting = s_rain > 0.05
		rain_particles.amount_ratio = clampf(s_rain, 0.05, 1.0)


func _update_sun() -> void:
	var h := Game.time_of_day
	# sun path: rises ~6:00 in the east (+x), sets ~19:30 in the west
	var day_frac := (h - 6.0) / 13.5
	var elev := sin(day_frac * PI) * 62.0
	var azim := lerpf(100.0, 260.0, clampf(day_frac, 0.0, 1.0))
	if h < 6.0 or h > 19.5:
		elev = -10.0 - 20.0 * sin(clampf((fposmod(h - 19.5, 24.0)) / 10.5, 0.0, 1.0) * PI)
	sun.rotation_degrees = Vector3(-elev, azim, 0.0)
	var up := clampf(elev / 25.0, 0.0, 1.0)
	var golden := clampf(1.0 - absf(elev - 6.0) / 14.0, 0.0, 1.0)
	sun.light_color = Color(1.0, 0.96, 0.9).lerp(Color(1.0, 0.62, 0.32), golden * 0.85)
	sun.light_energy = maxf((up * 1.25 + golden * 0.3) * s_sun * (1.0 - s_dark * 0.7), 0.0) * (1.0 if elev > -3.0 else 0.0) + _flash * 3.0
	sun.shadow_enabled = elev > 1.0
	var night := 1.0 - smoothstep(-8.0, 6.0, elev)
	moon.rotation_degrees = Vector3(-35.0, azim + 180.0, 0.0)
	moon.light_energy = night * 0.12 * (1.0 - s_dark * 0.6)
	env.ambient_light_energy = lerpf(0.12, 1.0, smoothstep(-6.0, 15.0, elev)) * s_amb + _flash * 2.0
	env.background_energy_multiplier = lerpf(0.4, 1.0, smoothstep(-8.0, 10.0, elev)) + _flash * 3.0
	var fog_day := Color(0.66, 0.74, 0.84).lerp(Color(0.6, 0.62, 0.65), s_dark)
	var fog_col := Color(0.03, 0.04, 0.07).lerp(fog_day, smoothstep(-8.0, 12.0, elev))
	fog_col = fog_col.lerp(Color(0.95, 0.65, 0.45), golden * 0.35 * (1.0 - s_dark))
	env.fog_light_color = fog_col
	env.volumetric_fog_albedo = fog_col
	env.tonemap_exposure = lerpf(1.35, 1.0, smoothstep(-6.0, 20.0, elev))
	sky_mat.set_shader_parameter("star_strength", night)


func is_night() -> bool:
	return Game.time_of_day < 6.6 or Game.time_of_day > 19.4


func _make_rain() -> void:
	rain_particles = GPUParticles3D.new()
	rain_particles.name = "Rain"
	rain_particles.amount = 6000
	rain_particles.lifetime = 1.1
	rain_particles.visibility_aabb = AABB(Vector3(-40, -30, -40), Vector3(80, 50, 80))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(35, 2, 35)
	pm.direction = Vector3(0.1, -1, 0)
	pm.spread = 3.0
	pm.initial_velocity_min = 22.0
	pm.initial_velocity_max = 28.0
	pm.gravity = Vector3(0, -9.8, 0)
	rain_particles.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2(0.02, 0.55)
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0.8, 0.85, 0.95, 0.35)
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	quad.material = m
	rain_particles.draw_pass_1 = quad
	rain_particles.emitting = false
	add_child(rain_particles)
