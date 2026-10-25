class_name EnvironmentController
extends Node3D
## Day/night cycle and weather. Drives the procedural sky, sun/moon lights, fog, volumetric fog,
## SSR for wet roads, rain particles, lightning, global shader parameters (wetness, wind) and the
## grip multiplier that cars read (wetness).

signal weather_changed(name: String)

enum Weather { CLEAR, CLOUDY, RAIN, FOG, STORM }
const WEATHER_NAMES := ["clear", "cloudy", "rain", "fog", "storm"]
const PRESETS := {
	Weather.CLEAR: {"coverage": 0.28, "darkness": 0.0, "overcast": 0.0, "fog": 0.00009, "rain": 0.0, "wet": 0.0, "sun": 1.0, "wind": 0.25, "vfog": 0.0},
	Weather.CLOUDY: {"coverage": 0.72, "darkness": 0.28, "overcast": 0.38, "fog": 0.00018, "rain": 0.0, "wet": 0.0, "sun": 0.55, "wind": 0.5, "vfog": 0.0},
	Weather.RAIN: {"coverage": 0.96, "darkness": 0.62, "overcast": 0.82, "fog": 0.0006, "rain": 0.65, "wet": 1.0, "sun": 0.2, "wind": 0.75, "vfog": 0.006},
	Weather.FOG: {"coverage": 0.6, "darkness": 0.2, "overcast": 0.72, "fog": 0.0045, "rain": 0.0, "wet": 0.35, "sun": 0.32, "wind": 0.1, "vfog": 0.025},
	Weather.STORM: {"coverage": 1.0, "darkness": 0.88, "overcast": 0.95, "fog": 0.001, "rain": 1.0, "wet": 1.0, "sun": 0.07, "wind": 1.0, "vfog": 0.012},
}

var time_of_day: float = 10.5
## Real minutes per in-game day.
var day_length_minutes: float = 40.0
var time_frozen: bool = false
var weather: Weather = Weather.CLEAR
var wetness: float = 0.0
var wind: float = 0.25
var sun_elevation_deg: float = 45.0

var world_env: WorldEnvironment
var env: Environment
var sun: DirectionalLight3D
var moon: DirectionalLight3D
var sky_mat: ShaderMaterial
var rain: GPUParticles3D
var _cur: Dictionary = {}
var _day_amount: float = 1.0
var _flash: float = 0.0
var _lightning_timer: float = 8.0
var _thunder: AudioStreamPlayer
var _rain_audio: AudioStreamPlayer
var _thunder_delay: float = -1.0


func _ready() -> void:
	_cur = (PRESETS[Weather.CLEAR] as Dictionary).duplicate()
	_build()
	_apply(0.0, true)


func _build() -> void:
	sky_mat = ShaderMaterial.new()
	sky_mat.shader = load("res://assets/shaders/sky.gdshader")
	var n1 := NoiseTexture2D.new()
	n1.width = 512
	n1.height = 512
	n1.seamless = true
	var fn := FastNoiseLite.new()
	fn.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	fn.frequency = 0.008
	fn.fractal_octaves = 5
	fn.seed = 11
	n1.noise = fn
	var n2 := NoiseTexture2D.new()
	n2.width = 256
	n2.height = 256
	n2.seamless = true
	var fn2 := FastNoiseLite.new()
	fn2.noise_type = FastNoiseLite.TYPE_CELLULAR
	fn2.frequency = 0.03
	fn2.fractal_octaves = 3
	fn2.seed = 23
	n2.noise = fn2
	sky_mat.set_shader_parameter("cloud_noise", n1)
	sky_mat.set_shader_parameter("cloud_noise2", n2)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.process_mode = Sky.PROCESS_MODE_REALTIME
	sky.radiance_size = Sky.RADIANCE_SIZE_256
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.ambient_light_sky_contribution = 1.0
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.0
	env.glow_enabled = true
	env.glow_intensity = 0.55
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 1.1
	env.ssao_enabled = true
	env.ssao_radius = 1.4
	env.ssao_intensity = 1.6
	env.ssao_power = 1.4
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	env.fog_density = 0.0001
	env.fog_sun_scatter = 0.35
	env.fog_aerial_perspective = 0.4
	env.fog_sky_affect = 0.35
	env.volumetric_fog_enabled = false
	env.volumetric_fog_length = 180.0
	env.volumetric_fog_detail_spread = 1.5
	env.ssr_enabled = false
	env.ssr_max_steps = 48
	env.ssr_fade_in = 0.15
	env.ssr_fade_out = 2.0
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.14
	env.adjustment_contrast = 1.04
	world_env = WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = 420.0
	sun.directional_shadow_blend_splits = true
	sun.shadow_bias = 0.04
	sun.shadow_normal_bias = 1.2
	sun.light_angular_distance = 0.6
	add_child(sun)
	moon = DirectionalLight3D.new()
	moon.name = "Moon"
	moon.light_color = Color(0.55, 0.65, 0.9)
	moon.light_energy = 0.0
	moon.shadow_enabled = false
	moon.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	add_child(moon)

	rain = GPUParticles3D.new()
	rain.name = "Rain"
	rain.amount = 9000
	rain.lifetime = 1.4
	rain.local_coords = false
	rain.visibility_aabb = AABB(Vector3(-50, -60, -50), Vector3(100, 80, 100))
	rain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(40, 1, 40)
	pm.direction = Vector3(0.08, -1, 0.02)
	pm.spread = 3.0
	pm.initial_velocity_min = 26.0
	pm.initial_velocity_max = 32.0
	pm.gravity = Vector3(0, -9.8, 0)
	pm.collision_mode = ParticleProcessMaterial.COLLISION_DISABLED
	rain.process_material = pm
	var drop := QuadMesh.new()
	drop.size = Vector2(0.018, 0.7)
	var dm := StandardMaterial3D.new()
	dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dm.albedo_color = Color(0.75, 0.8, 0.9, 0.35)
	dm.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	drop.material = dm
	rain.draw_pass_1 = drop
	rain.amount_ratio = 0.0
	rain.emitting = true
	add_child(rain)

	_thunder = AudioStreamPlayer.new()
	_thunder.stream = SoundBank.get_stream("impact")
	add_child(_thunder)
	_rain_audio = AudioStreamPlayer.new()
	_rain_audio.stream = SoundBank.get_stream("rain")
	_rain_audio.volume_db = -80.0
	add_child(_rain_audio)
	_rain_audio.play()


func set_time(hour: float) -> void:
	time_of_day = fposmod(hour, 24.0)
	_apply(0.0, true)


func set_weather_by_name(n: String) -> bool:
	var idx := WEATHER_NAMES.find(n.to_lower())
	if idx < 0:
		return false
	set_weather(idx as Weather)
	return true


func set_weather(w: Weather, instant: bool = false) -> void:
	weather = w
	if instant:
		_cur = (PRESETS[w] as Dictionary).duplicate()
		wetness = float(_cur["wet"])
	weather_changed.emit(WEATHER_NAMES[w])


func weather_name() -> String:
	return WEATHER_NAMES[weather]


func get_darkness() -> float:
	return clampf(1.0 - _day_amount + float(_cur.get("darkness", 0.0)) * 0.35 * _day_amount, 0.0, 1.0)


func grip_multiplier() -> float:
	return 1.0


func _process(delta: float) -> void:
	if not time_frozen:
		time_of_day = fposmod(time_of_day + delta * 24.0 / (day_length_minutes * 60.0), 24.0)
	_apply(delta, false)


func _apply(delta: float, instant: bool) -> void:
	var target: Dictionary = PRESETS[weather]
	var k := 1.0 if instant else 1.0 - exp(-delta * 0.35)
	for key in target:
		_cur[key] = lerpf(float(_cur.get(key, target[key])), float(target[key]), k)
	# wetness follows rain slowly (roads dry slower than they get wet)
	var wet_target := float(target["wet"])
	var wet_rate := 0.08 if wet_target > wetness else 0.02
	wetness = wet_target if instant else move_toward(wetness, wet_target, delta * wet_rate)
	wind = float(_cur["wind"])

	# sun position
	var az := PI * (time_of_day - 12.0) / 12.0
	var elev := deg_to_rad(64.0) * sin(PI * (time_of_day - 6.0) / 12.0)
	sun_elevation_deg = rad_to_deg(elev)
	var d := Vector3(-sin(az) * cos(elev), sin(elev), cos(az) * cos(elev) * 0.85 + 0.15).normalized()
	sun.transform = Transform3D(Basis.looking_at(-d, Vector3.UP if absf(d.y) < 0.98 else Vector3.FORWARD), Vector3.ZERO)
	var moon_d := Vector3(-d.x * 0.8, maxf(-d.y, 0.25), -d.z * 0.8 + 0.2).normalized()
	moon.transform = Transform3D(Basis.looking_at(-moon_d, Vector3.UP), Vector3.ZERO)

	var e_deg := sun_elevation_deg
	_day_amount = smoothstep(-9.0, 9.0, e_deg)
	var sunset := (1.0 - smoothstep(2.0, 22.0, absf(e_deg))) * smoothstep(-10.0, 0.0, e_deg)
	var warm := Color(1.0, 0.5, 0.26)
	var white := Color(1.0, 0.97, 0.92)
	sun.light_color = warm.lerp(white, smoothstep(2.0, 26.0, e_deg))
	var sun_mult := float(_cur["sun"])
	sun.light_energy = smoothstep(-2.0, 7.0, e_deg) * 1.35 * sun_mult
	sun.visible = e_deg > -3.0
	sun.shadow_enabled = sun.light_energy > 0.05
	moon.light_energy = (1.0 - _day_amount) * 0.12 * (1.0 - float(_cur["overcast"]) * 0.7)
	moon.visible = moon.light_energy > 0.005

	sky_mat.set_shader_parameter("day_amount", _day_amount)
	sky_mat.set_shader_parameter("sunset_amount", sunset)
	sky_mat.set_shader_parameter("cloud_coverage", _cur["coverage"])
	sky_mat.set_shader_parameter("cloud_darkness", _cur["darkness"])
	sky_mat.set_shader_parameter("overcast", _cur["overcast"])
	sky_mat.set_shader_parameter("moon_dir", moon_d)

	# ambient, fog, exposure
	env.ambient_light_energy = lerpf(0.35, 1.0, _day_amount)
	var fog_day := Color(0.66, 0.74, 0.84).lerp(Color(0.62, 0.63, 0.65), float(_cur["overcast"]))
	var fog_night := Color(0.04, 0.05, 0.08)
	var fog_col := fog_night.lerp(fog_day, _day_amount)
	fog_col = fog_col.lerp(Color(0.95, 0.6, 0.38), sunset * 0.45)
	env.fog_light_color = fog_col
	env.fog_density = float(_cur["fog"])
	env.fog_sun_scatter = 0.35 * (1.0 - float(_cur["overcast"]))
	var vfog := float(_cur["vfog"])
	env.volumetric_fog_enabled = vfog > 0.002
	env.volumetric_fog_density = vfog
	env.volumetric_fog_albedo = fog_col
	env.tonemap_exposure = lerpf(1.6, 1.0, _day_amount) * lerpf(1.0, 1.25, float(_cur["overcast"]))
	env.ssr_enabled = wetness > 0.25
	env.glow_intensity = lerpf(0.9, 0.55, _day_amount)

	# rain
	var rain_amt := float(_cur["rain"])
	rain.amount_ratio = clampf(rain_amt, 0.0, 1.0)
	rain.visible = rain_amt > 0.01
	var cam := get_viewport().get_camera_3d()
	if cam != null:
		rain.global_position = cam.global_position + Vector3(0, 22, 0) + cam.global_transform.basis.z * -10.0
	_rain_audio.volume_db = linear_to_db(maxf(rain_amt * 0.6 * float(Game.settings.get("master_volume", 0.8)), 0.0001)) if rain_amt > 0.02 else -80.0

	# lightning
	_flash = maxf(_flash - delta * 4.0, 0.0)
	if weather == Weather.STORM and not instant:
		_lightning_timer -= delta
		if _lightning_timer <= 0.0:
			_lightning_timer = randf_range(5.0, 16.0)
			_flash = randf_range(0.8, 1.6)
			_thunder_delay = randf_range(0.4, 2.5)
	if _thunder_delay > 0.0:
		_thunder_delay -= delta
		if _thunder_delay <= 0.0:
			_thunder.pitch_scale = randf_range(0.35, 0.55)
			_thunder.volume_db = randf_range(-6.0, 0.0) + linear_to_db(float(Game.settings.get("master_volume", 0.8)))
			_thunder.play()
	sky_mat.set_shader_parameter("flash", _flash)
	if _flash > 0.0:
		env.ambient_light_energy += _flash * 0.8

	RenderingServer.global_shader_parameter_set("wetness", wetness)
	RenderingServer.global_shader_parameter_set("wind_strength", wind)
	RenderingServer.global_shader_parameter_set("night_amount", 1.0 - _day_amount)
