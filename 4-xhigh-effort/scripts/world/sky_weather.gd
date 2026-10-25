extends Node
## Day/night cycle and weather. Owns the WorldEnvironment, sun and moon lights, the sky shader,
## rain/snow particles and lightning. Weather presets (res://data/weather/*.tres) are blended
## smoothly; wetness feeds the road/terrain shaders (global "wetness") and tyre grip.

signal weather_changed(id: StringName)

const SKY_SHADER := preload("res://assets/shaders/sky.gdshader")
const WEATHER_DIR := "res://data/weather/"
const WEATHER_IDS := [&"clear", &"cloudy", &"rain", &"fog", &"storm"]

var env: Environment
var world_env: WorldEnvironment
var sun: DirectionalLight3D
var moon: DirectionalLight3D
var sky_mat: ShaderMaterial
var presets := {}
var current: WeatherPreset
var target: WeatherPreset
var blend := 1.0
var time_of_day := 9.5
var time_speed := 1.0 / 60.0   ## game hours per real second (1 hour per minute)
var frozen := false
var auto_weather := true
var wetness := 0.0
var is_night := false
var sun_dir := Vector3.UP
var _cur := {}                 ## blended numeric parameters
var _weather_timer := 420.0
var _cloud_off := Vector2.ZERO
var _flash := 0.0
var _next_flash := 8.0
var _rain: GPUParticles3D
var _snow: GPUParticles3D
var _rng := RandomNumberGenerator.new()
var _was_night := false


func _ready() -> void:
	_rng.seed = 4242
	for id: StringName in WEATHER_IDS:
		var p := load(WEATHER_DIR + String(id) + ".tres") as WeatherPreset
		if p == null:
			p = WeatherPreset.new()
			p.id = id
		presets[id] = p
	current = presets[&"clear"]
	target = current
	_cur = _params(current)
	world_env = WorldEnvironment.new()
	env = Environment.new()
	var sky := Sky.new()
	sky_mat = ShaderMaterial.new()
	sky_mat.shader = SKY_SHADER
	var cn := NoiseTexture2D.new()
	cn.width = 512
	cn.height = 512
	cn.seamless = true
	var fn := FastNoiseLite.new()
	fn.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	fn.fractal_octaves = 5
	fn.frequency = 0.008
	cn.noise = fn
	sky_mat.set_shader_parameter("cloud_noise", cn)
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_128
	sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.0
	env.glow_enabled = true
	env.glow_intensity = 0.35
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 1.1
	env.ssao_enabled = true
	env.ssao_radius = 1.4
	env.ssao_intensity = 1.4
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	env.fog_sun_scatter = 0.25
	env.fog_aerial_perspective = 0.55
	env.fog_sky_affect = 0.2
	env.fog_height = 60.0
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.18
	env.adjustment_contrast = 1.05
	world_env.environment = env
	add_child(world_env)
	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = 420.0
	sun.directional_shadow_split_1 = 0.06
	sun.directional_shadow_split_2 = 0.18
	sun.directional_shadow_split_3 = 0.45
	sun.directional_shadow_blend_splits = true
	sun.shadow_blur = 1.2
	sun.shadow_bias = 0.04
	sun.shadow_normal_bias = 1.2
	add_child(sun)
	moon = DirectionalLight3D.new()
	moon.name = "Moon"
	moon.light_color = Color(0.55, 0.65, 1.0)
	moon.shadow_enabled = false
	moon.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	add_child(moon)
	_make_particles()
	_apply(0.0)


func _params(p: WeatherPreset) -> Dictionary:
	return {"cov": p.cloud_coverage, "dark": p.cloud_darkness, "fog": p.fog_density, "hfog": p.fog_height_density,
		"vfog": p.volumetric_fog, "rain": p.rain, "wet": p.wetness, "sun": p.sun_energy, "amb": p.ambient,
		"tint": p.sky_tint, "wind": p.wind, "grip": p.grip}


func set_time(hour: float) -> void:
	time_of_day = fposmod(hour, 24.0)
	_apply(0.0)


func set_weather(id: String, instant := false) -> bool:
	var key := StringName(id.to_lower())
	if not presets.has(key):
		return false
	target = presets[key]
	if instant:
		current = target
		_cur = _params(target)
		blend = 1.0
		wetness = target.wetness
	else:
		blend = 0.0
	_weather_timer = _rng.randf_range(360.0, 600.0)
	weather_changed.emit(key)
	Game.notify("Weather", target.display_name, "small")
	return true


func weather_name() -> String:
	return target.display_name if target != null else ""


func _process(delta: float) -> void:
	if not frozen:
		time_of_day = fposmod(time_of_day + delta * time_speed, 24.0)
		if auto_weather:
			_weather_timer -= delta
			if _weather_timer <= 0.0:
				set_weather(String(_pick_weather()))
	_apply(delta)


func _pick_weather() -> StringName:
	var total := 0.0
	for id: StringName in WEATHER_IDS:
		total += (presets[id] as WeatherPreset).weight
	var r := _rng.randf() * total
	for id: StringName in WEATHER_IDS:
		r -= (presets[id] as WeatherPreset).weight
		if r <= 0.0:
			return id
	return &"clear"


func _apply(delta: float) -> void:
	# weather blending
	if blend < 1.0:
		blend = minf(blend + delta / 12.0, 1.0)
		var a := _params(current)
		var b := _params(target)
		for k: String in a:
			if a[k] is Color:
				_cur[k] = (a[k] as Color).lerp(b[k], blend)
			else:
				_cur[k] = lerpf(float(a[k]), float(b[k]), blend)
		if blend >= 1.0:
			current = target
	var wet_target := float(_cur.wet)
	wetness = move_toward(wetness, wet_target, delta * (0.05 if wet_target > wetness else 0.012))
	RenderingServer.global_shader_parameter_set("wetness", wetness)
	# sun path: rises east (+X), culminates south (+Z), sets west
	var th := (time_of_day - 6.0) / 12.0 * PI
	sun_dir = Vector3(cos(th), sin(th) * 0.88, 0.32 + 0.25 * sin(th)).normalized()
	var moon_dir := Vector3(-cos(th) * 0.8, -sin(th) * 0.8 + 0.12, -0.35).normalized()
	var elev := sun_dir.y
	var day := smoothstep(-0.08, 0.2, elev)
	var dusk := clampf(1.0 - absf(elev - 0.05) / 0.3, 0.0, 1.0)
	is_night = elev < -0.02
	sun.basis = Basis.looking_at(-sun_dir, Vector3.UP if absf(sun_dir.y) < 0.99 else Vector3.FORWARD)
	moon.basis = Basis.looking_at(-moon_dir, Vector3.UP)
	var overcast := float(_cur.cov) * float(_cur.dark)
	var sun_col := Color(1.0, 0.97, 0.9).lerp(Color(1.0, 0.55, 0.28), dusk * (1.0 - day * 0.4))
	sun.light_color = sun_col
	sun.light_energy = maxf(0.0, day * 1.75 * float(_cur.sun) * (1.0 - overcast * 0.75)) + _flash * 3.0
	sun.visible = elev > -0.1
	sun.shadow_enabled = elev > 0.02
	moon.light_energy = (1.0 - day) * 0.22 * (1.0 - overcast * 0.6)
	moon.visible = moon.light_energy > 0.01
	env.ambient_light_energy = lerpf(0.3, 0.55, day) * float(_cur.amb)
	env.tonemap_exposure = lerpf(2.2, 0.82, day)
	env.background_energy_multiplier = lerpf(1.0, 1.0, day)
	var hor := Color(0.55, 0.68, 0.84).lerp(Color(0.03, 0.045, 0.09), 1.0 - day).lerp(Color(0.95, 0.6, 0.45), dusk * 0.45)
	hor = hor.lerp(Color(0.55, 0.57, 0.6) * lerpf(0.15, 1.0, day), overcast * 0.8)
	# biome tint: dusty haze in the desert, cold haze at altitude
	var cam := get_viewport().get_camera_3d()
	var region := -1
	var cam_y := 0.0
	if cam != null and Game.world != null and Game.world.has_method("region_at"):
		region = Game.world.region_at(cam.global_position)
		cam_y = cam.global_position.y
	if region == 2:
		hor = hor.lerp(Color(0.85, 0.66, 0.48) * lerpf(0.2, 1.0, day), 0.35)
	env.fog_light_color = hor
	env.fog_light_energy = lerpf(0.4, 1.0, day)
	env.fog_density = float(_cur.fog) * (1.25 if region == 2 and float(_cur.wind) > 5.0 else 1.0)
	env.fog_height_density = float(_cur.hfog)
	var vf := float(_cur.vfog)
	env.volumetric_fog_enabled = vf > 0.001
	if env.volumetric_fog_enabled:
		env.volumetric_fog_density = vf
		env.volumetric_fog_albedo = hor
		env.volumetric_fog_length = 160.0
		env.volumetric_fog_emission = Color(0.0, 0.0, 0.0)
	# sky
	_cloud_off += Vector2(0.6, 0.25) * float(_cur.wind) * delta * 0.0008
	sky_mat.set_shader_parameter("sun_dir", sun_dir)
	sky_mat.set_shader_parameter("moon_dir", moon_dir)
	sky_mat.set_shader_parameter("cloud_coverage", float(_cur.cov))
	sky_mat.set_shader_parameter("cloud_darkness", float(_cur.dark))
	sky_mat.set_shader_parameter("cloud_offset", _cloud_off)
	sky_mat.set_shader_parameter("tint", Vector3((_cur.tint as Color).r, (_cur.tint as Color).g, (_cur.tint as Color).b))
	# lightning
	if bool(target.lightning) and blend > 0.5:
		_next_flash -= delta
		if _next_flash <= 0.0:
			_next_flash = _rng.randf_range(5.0, 16.0)
			_flash = 1.0
			if Game.audio != null and Game.audio.has_method("thunder"):
				Game.audio.thunder(_rng.randf_range(0.4, 2.5))
	_flash = maxf(_flash - delta * 3.5, 0.0)
	sky_mat.set_shader_parameter("flash", _flash * 0.8)
	# precipitation follows the camera; snow replaces rain at altitude
	var rain := float(_cur.rain)
	var snowing := cam_y > 270.0 and (rain > 0.05 or float(_cur.cov) > 0.6)
	if cam != null:
		var lead := Game.player.linear_velocity * 0.45 if Game.player != null and is_instance_valid(Game.player) else Vector3.ZERO
		_rain.global_position = cam.global_position + Vector3(0, 14, 0) + lead
		_snow.global_position = cam.global_position + Vector3(0, 10, 0)
	_rain.emitting = rain > 0.02 and not snowing
	_rain.amount_ratio = clampf(rain, 0.0, 1.0)
	_snow.emitting = snowing
	RenderingServer.global_shader_parameter_set("snow_cover", 0.6 if snowing or (rain > 0.3 and region == 1) else 0.0)
	# gameplay hooks
	if Game.player != null and is_instance_valid(Game.player):
		Game.player.wetness = wetness
		Game.player.weather_grip = float(_cur.grip)
		if not Game.headlights_manual:
			Game.player.lights_on = elev < 0.06 or float(_cur.fog) > 0.002 or overcast > 0.6
		if Game.player.visual != null:
			Game.player.visual.set_wetness(wetness)
	if is_night != _was_night:
		_was_night = is_night
		if Game.world != null and Game.world.get("structures") != null:
			Game.world.structures.call("set_night", is_night)


func _make_particles() -> void:
	_rain = GPUParticles3D.new()
	_rain.name = "Rain"
	_rain.amount = 9000
	_rain.lifetime = 1.0
	_rain.visibility_aabb = AABB(Vector3(-40, -30, -40), Vector3(80, 50, 80))
	_rain.local_coords = false
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(32, 2, 32)
	pm.direction = Vector3(0.08, -1, 0.04)
	pm.spread = 3.0
	pm.initial_velocity_min = 26.0
	pm.initial_velocity_max = 32.0
	pm.gravity = Vector3(0, -10, 0)
	pm.particle_flag_align_y = true
	_rain.process_material = pm
	var qm := QuadMesh.new()
	qm.size = Vector2(0.018, 0.7)
	var rm := StandardMaterial3D.new()
	rm.albedo_color = Color(0.75, 0.8, 0.9, 0.35)
	rm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rm.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	rm.billboard_keep_scale = true
	qm.material = rm
	_rain.draw_pass_1 = qm
	_rain.emitting = false
	add_child(_rain)
	_snow = GPUParticles3D.new()
	_snow.name = "Snow"
	_snow.amount = 4000
	_snow.lifetime = 5.0
	_snow.visibility_aabb = AABB(Vector3(-40, -30, -40), Vector3(80, 50, 80))
	_snow.local_coords = false
	var sm := ParticleProcessMaterial.new()
	sm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	sm.emission_box_extents = Vector3(30, 2, 30)
	sm.direction = Vector3(0.3, -1, 0.1)
	sm.spread = 25.0
	sm.initial_velocity_min = 1.5
	sm.initial_velocity_max = 3.0
	sm.gravity = Vector3(0, -1.2, 0)
	sm.turbulence_enabled = true
	sm.turbulence_noise_strength = 1.5
	_snow.process_material = sm
	var sq := QuadMesh.new()
	sq.size = Vector2(0.06, 0.06)
	var smat := StandardMaterial3D.new()
	smat.albedo_color = Color(1, 1, 1, 0.9)
	smat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	sq.material = smat
	_snow.draw_pass_1 = sq
	_snow.emitting = false
	add_child(_snow)
