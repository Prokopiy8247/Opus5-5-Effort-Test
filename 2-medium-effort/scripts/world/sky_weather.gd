class_name SkyWeather
extends Node3D
## Day/night cycle (sun + moon, sky colours, exposure) and weather states (clear, cloudy, rain, fog, storm)
## that drive fog, light, cloud cover, rain particles, lightning, surface wetness and tyre grip.

const STATES: PackedStringArray = ["clear", "cloudy", "rain", "fog", "storm", "snow"]
# cloud, fog density, rain, wet target, light mult, grip
const PRESETS: Dictionary = {
	"clear": [0.05, 0.0006, 0.0, 0.0, 1.0, 1.0],
	"cloudy": [0.7, 0.0010, 0.0, 0.0, 0.62, 1.0],
	"rain": [0.9, 0.0022, 1.0, 1.0, 0.42, 0.78],
	"fog": [0.6, 0.0095, 0.0, 0.25, 0.5, 0.95],
	"storm": [1.0, 0.0035, 1.6, 1.0, 0.28, 0.72],
	"snow": [0.85, 0.004, 0.0, 0.3, 0.55, 0.8],
}

var hour: float = 9.5
var day_speed: float = 1.0 / 60.0  # in-game hours per real second (1 day = 24 min)
var time_frozen: bool = false
var weather: String = "clear"
var auto_weather: bool = true
var cloud: float = 0.05
var fog_d: float = 0.0006
var rain: float = 0.0
var wet: float = 0.0
var light_mult: float = 1.0
var grip: float = 1.0
var _target: Array = PRESETS["clear"]
var _weather_timer: float = 240.0
var _lightning_t: float = 5.0
var _flash: float = 0.0

var env: Environment
var sky_mat: ProceduralSkyMaterial
var sun: DirectionalLight3D
var moon: DirectionalLight3D
var world_env: WorldEnvironment
var rain_fx: GPUParticles3D
var snow_fx: GPUParticles3D
var follow: Node3D


func _ready() -> void:
	RenderingServer.global_shader_parameter_add("wetness", RenderingServer.GLOBAL_VAR_TYPE_FLOAT, 0.0)
	RenderingServer.global_shader_parameter_add("snow_cover", RenderingServer.GLOBAL_VAR_TYPE_FLOAT, 0.0)
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	sky_mat = ProceduralSkyMaterial.new()
	sky_mat.sun_angle_max = 20.0
	sky_mat.sun_curve = 0.12
	var cn := FastNoiseLite.new()
	cn.frequency = 0.008
	cn.fractal_octaves = 5
	var ct := NoiseTexture2D.new()
	ct.width = 1024
	ct.height = 512
	ct.seamless = true
	ct.noise = cn
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0, 0, 0, 0))
	ramp.set_color(1, Color(1, 1, 1, 1))
	ramp.set_offset(0, 0.45)
	ramp.set_offset(1, 0.8)
	ct.color_ramp = ramp
	sky_mat.sky_cover = ct
	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_128
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = 0.85
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.0
	env.tonemap_white = 6.0
	env.glow_enabled = true
	env.glow_intensity = 0.6
	env.glow_bloom = 0.05
	env.glow_hdr_threshold = 1.2
	env.ssao_enabled = true
	env.ssao_radius = 1.2
	env.ssao_intensity = 1.6
	env.fog_enabled = true
	env.fog_light_color = Color(0.7, 0.78, 0.88)
	env.fog_density = 0.0006
	env.fog_aerial_perspective = 0.55
	env.fog_sky_affect = 0.35
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.12
	env.adjustment_contrast = 1.05
	world_env = WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)
	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = 220.0
	sun.directional_shadow_split_1 = 0.06
	sun.directional_shadow_split_2 = 0.18
	sun.directional_shadow_split_3 = 0.45
	sun.shadow_blur = 1.2
	sun.light_angular_distance = 0.6
	add_child(sun)
	moon = DirectionalLight3D.new()
	moon.name = "Moon"
	moon.light_color = Color(0.55, 0.65, 0.95)
	moon.shadow_enabled = false
	add_child(moon)
	rain_fx = _make_precip(false)
	snow_fx = _make_precip(true)
	_apply_time()


func _make_precip(snow: bool) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = 6000 if not snow else 3000
	p.lifetime = 1.2 if not snow else 4.0
	p.visibility_aabb = AABB(Vector3(-40, -30, -40), Vector3(80, 60, 80))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(30, 1, 30)
	pm.direction = Vector3(0.05, -1, 0)
	pm.spread = 3.0 if not snow else 20.0
	pm.initial_velocity_min = 22.0 if not snow else 1.5
	pm.initial_velocity_max = 28.0 if not snow else 3.0
	pm.gravity = Vector3(0, -9.8, 0) if not snow else Vector3(0.3, -1.0, 0)
	p.process_material = pm
	var qm := QuadMesh.new()
	qm.size = Vector2(0.025, 0.7) if not snow else Vector2(0.08, 0.08)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.75, 0.8, 0.9, 0.35) if not snow else Color(1, 1, 1, 0.9)
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y if not snow else BaseMaterial3D.BILLBOARD_ENABLED
	qm.material = mat
	p.draw_pass_1 = qm
	p.emitting = false
	p.position = Vector3(0, 18, 0)
	add_child(p)
	return p


func set_weather(state: String, instant: bool = false) -> bool:
	if not PRESETS.has(state):
		return false
	weather = state
	_target = PRESETS[state]
	_weather_timer = randf_range(180.0, 360.0)
	if instant:
		cloud = _target[0]
		fog_d = _target[1]
		rain = _target[2]
		wet = _target[3]
		light_mult = _target[4]
		grip = _target[5]
	return true


func set_hour(h: float) -> void:
	hour = fposmod(h, 24.0)
	_apply_time()


func _process(delta: float) -> void:
	var _pf: int = Time.get_ticks_usec()
	_inner_sky(delta)
	Game.prof_add("sky", _pf)


func _inner_sky(delta: float) -> void:
	if not time_frozen:
		hour = fposmod(hour + delta * day_speed, 24.0)
	if auto_weather:
		_weather_timer -= delta
		if _weather_timer <= 0.0:
			var options: PackedStringArray = ["clear", "clear", "cloudy", "cloudy", "rain", "fog", "storm"]
			set_weather(options[randi() % options.size()])
	var k: float = clampf(delta * 0.12, 0.0, 1.0)
	cloud = lerpf(cloud, _target[0], k)
	fog_d = lerpf(fog_d, _target[1], k)
	rain = lerpf(rain, _target[2], k * 1.5)
	light_mult = lerpf(light_mult, _target[4], k)
	grip = lerpf(grip, _target[5], k)
	# surfaces get wet quickly in rain and dry slowly
	var wt: float = _target[3]
	wet = move_toward(wet, wt, delta * (0.08 if wt > wet else 0.015))
	RenderingServer.global_shader_parameter_set("wetness", wet)
	RenderingServer.global_shader_parameter_set("snow_cover", 1.0 if weather == "snow" else 0.0)
	if follow:
		var lead: Vector3 = Vector3.ZERO
		if follow is RigidBody3D:
			lead = (follow as RigidBody3D).linear_velocity * 0.6
		rain_fx.global_position = follow.global_position + Vector3(0, 16, 0) + lead
		snow_fx.global_position = follow.global_position + Vector3(0, 14, 0)
	# biome rule: precipitation falls as snow high in the Highlands
	var alpine: bool = follow != null and follow.global_position.y > 190.0
	rain_fx.emitting = rain > 0.15 and not alpine
	rain_fx.amount_ratio = clampf(rain / 1.6, 0.05, 1.0)
	snow_fx.emitting = weather == "snow" or (rain > 0.15 and alpine)
	# lightning in storms
	_flash = move_toward(_flash, 0.0, delta * 4.0)
	if weather == "storm":
		_lightning_t -= delta
		if _lightning_t <= 0.0:
			_flash = 1.0
			_lightning_t = randf_range(4.0, 14.0)
	_apply_time()


func sun_elevation() -> float:
	return sin((hour - 6.0) / 12.0 * PI)


func is_night() -> bool:
	return sun_elevation() < 0.06


func _apply_time() -> void:
	if sun == null:
		return
	# sun arcs east -> south -> west; z south is +, so the noon sun sits toward +z
	var t: float = (hour - 6.0) / 12.0 * PI
	var elev: float = sin(t)
	var sdir := Vector3(-cos(t), sin(t) * 0.93, 0.38).normalized()
	sun.look_at_from_position(Vector3.ZERO, -sdir, Vector3.UP if absf(sdir.y) < 0.99 else Vector3.FORWARD)
	moon.look_at_from_position(Vector3.ZERO, sdir, Vector3.UP if absf(sdir.y) < 0.99 else Vector3.FORWARD)
	var day: float = clampf(elev * 4.0 + 0.3, 0.0, 1.0)
	var golden: float = clampf(1.0 - absf(elev) * 4.0, 0.0, 1.0) * float(elev > -0.15)
	var sun_col := Color(1.0, 0.96, 0.9).lerp(Color(1.0, 0.55, 0.28), golden)
	sun.light_color = sun_col
	sun.light_energy = maxf(0.0, day * 1.35 * light_mult) + _flash * 2.0
	sun.visible = elev > -0.08
	moon.light_energy = (1.0 - day) * 0.28 * (1.0 - cloud * 0.6)
	moon.visible = elev < 0.1
	var overcast := Color(0.55, 0.58, 0.62)
	var top_day := Color(0.22, 0.42, 0.78).lerp(overcast * 0.85, cloud)
	var hor_day := Color(0.66, 0.76, 0.88).lerp(overcast, cloud)
	var top_night := Color(0.015, 0.025, 0.07)
	var hor_night := Color(0.05, 0.07, 0.13)
	var hor_gold := Color(1.0, 0.55, 0.3).lerp(overcast * 0.7, cloud * 0.8)
	sky_mat.sky_top_color = top_night.lerp(top_day, day)
	sky_mat.sky_horizon_color = hor_night.lerp(hor_day, day).lerp(hor_gold, golden * 0.7 * clampf(day * 3.0, 0.0, 1.0))
	sky_mat.ground_horizon_color = sky_mat.sky_horizon_color
	sky_mat.ground_bottom_color = Color(0.1, 0.11, 0.1) * maxf(day, 0.1)
	sky_mat.sky_energy_multiplier = lerpf(0.15, 1.0, day) * lerpf(1.0, 0.7, cloud) + _flash
	sky_mat.sun_angle_max = lerpf(30.0, 6.0, cloud)
	sky_mat.sky_cover_modulate = Color(1, 1, 1, clampf(0.25 + cloud, 0.0, 1.0)) * lerpf(0.08, 1.0, day)
	env.fog_density = fog_d
	env.fog_light_color = sky_mat.sky_horizon_color.lerp(Color(0.6, 0.62, 0.66), cloud * 0.5)
	env.ambient_light_energy = lerpf(0.4, 1.0, day)
	env.tonemap_exposure = lerpf(1.6, 1.0, day)
