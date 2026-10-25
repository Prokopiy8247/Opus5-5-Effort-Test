extends Node3D
## Game.env: time of day, sky, sun / moon, weather (smooth ~25 s transitions), fog and aerial perspective,
## graphics presets (Settings "quality"), rain / snow / dust, lightning, wet surfaces, street + tunnel
## lamps and automatic headlights. Added by main.gd with add_child; needs no setup.
## Contract: set_time_of_day(h), get_time_of_day(), set_time_scale(s) (1 = one in-game hour per two real
## minutes, 0 = frozen), set_weather(id, instant), get_weather(), get_weather_ids(), is_night(),
## signal lightning(strength). Extras: lights_needed(at), get_wetness(), get_precipitation(), get_rain(), get_wind(),
## get_wind_strength(), get_light_level(), is_in_tunnel(), tunnel_depth(p), is_point_in_tunnel(p),
## strike_lightning(), get_weather_name(id).
## lights_needed(at := no position) -> bool: vehicles should run their lights - at night and dusk, in low light
## (fog / rain / storm presets, dark overcast) and inside tunnels. Pass a car's position to test the tunnel
## there (from 15 m before a portal; traffic: per car, a few times per second at most). Without a position
## the tunnel part follows the view (is_in_tunnel()). The player's own headlights follow the player's car.
## Tunnels are lit locally (scripts/env/tunnel_light.gd probes); the global exposure, sun shading and rain
## shelter follow how deep the camera and the player's car are inside a tube.
## Test hooks (args after "--"): --timescale=<s>  --quality=<0..3>  --tonemap=agx|filmic|aces  --novsync  --env-profile

signal lightning(strength: float)

const WeatherPreset := preload("res://scripts/env/weather_preset.gd")
const SkyModel := preload("res://scripts/env/sky_model.gd")
const LampPool := preload("res://scripts/env/lamp_pool.gd")
const Precipitation := preload("res://scripts/env/precipitation.gd")
const Lightning := preload("res://scripts/env/lightning.gd")
const GraphicsQuality := preload("res://scripts/env/graphics_quality.gd")
const TunnelLight := preload("res://scripts/env/tunnel_light.gd")
const SKY_SHADER := preload("res://assets/shaders/sky.gdshader")

const WEATHER_IDS: Array[StringName] = [&"clear", &"cloudy", &"rain", &"fog", &"storm"]
const WEATHER_DIR := "res://data/weather/"
const TRANSITION_TIME := 25.0
const SECONDS_PER_HOUR := 120.0
const WET_TIME := 30.0
const DRY_TIME := 160.0
const BASE_EXPOSURE := 1.0
const NIGHT_EXPOSURE := 2.2
const NIGHT_AMBIENT := Color(0.05, 0.07, 0.12)
const MOON_COLOR := Color(0.62, 0.72, 1.0)
## Eye adaptation inside tunnels: exposure eases to this (same by day and night, the lamps dominate)
## over the first EYE_DEPTH metres; sun and moon fade between SUN_DEPTH.x and .y metres in, where the
## tube's own shadow is no longer trusted.
const TUNNEL_EXPOSURE := 1.45
const EYE_DEPTH := 30.0
const SUN_DEPTH := Vector2(8.0, 38.0)
const TUNNEL_HAZE := Color(0.16, 0.14, 0.11)
## Headlights go on this far before a portal and off this far past it.
const LIGHTS_BEFORE_PORTAL := 15.0
const LIGHTS_AFTER_PORTAL := 30.0
## Region grading, indexed like WorldLayout.REGIONS (vale, highlands, mesa, coast).
const REGION_FOG: Array[float] = [1.0, 0.72, 1.3, 1.15]
const REGION_TINT: Array[Color] = [Color(1.0, 1.0, 0.97), Color(0.95, 0.99, 1.06), Color(1.1, 0.96, 0.82), Color(0.95, 1.0, 1.05)]
const REGION_SAT: Array[float] = [1.05, 0.98, 1.0, 1.03]

var time_of_day: float = 10.5
var time_scale: float = 1.0
var weather_id: StringName = &"clear"
var wetness: float = 0.0

var world_env: WorldEnvironment
var environment: Environment
var sky_material: ShaderMaterial
var sun: DirectionalLight3D
var moon: DirectionalLight3D
var lamps: LampPool
var precipitation: Precipitation
var storm: Lightning
var tunnels: TunnelLight

var _presets: Dictionary = {}
var _cur: WeatherPreset
var _from: WeatherPreset
var _to: WeatherPreset
var _blend: float = 1.0
var _caps: Dictionary = {}
var _el: float = 45.0
var _dark: float = 0.0
var _cloud_offset := Vector2(0.13, 0.71)
var _cirrus_offset := Vector2(0.37, 0.11)
var _wind_angle: float = 0.6
var _wind := Vector3.ZERO
var _clock: float = 0.0
var _region_w := Color(1, 0, 0, 0)
var _region_target := Color(1, 0, 0, 0)
var _region_timer: float = 0.0
var _dust: float = 0.0
var _tunnel := false
## Eye adaptation to a tunnel interior 0..1 (exposure, fog, lightning indoors).
var _tunnel_t: float = 0.0
## 0..1 how much of the sun / moon is hidden from the camera's surroundings by a tunnel.
var _sun_cover: float = 0.0
## 0..1 the camera is under a tunnel roof (rain no longer reaches it: get_precipitation()).
var _shelter_t: float = 0.0
## 0..1 the camera is so deep in a tube that no open air is near: the precipitation emitters stop
## (closer to a portal the particles hide the drops under the roof themselves).
var _deep_t: float = 0.0
var _shelters_set := false
var _tunnel_timer: float = 0.0
var _cam_depth: float = TunnelLight.OUTSIDE
var _car_depth: float = TunnelLight.OUTSIDE
var _eye_depth: float = TunnelLight.OUTSIDE
var _lights_on := false
var _env_lights := false
var _car_tunnel_lights := false
var _wet_applied: float = -1.0
var _wet_timer: float = 0.0
var _water_mats: Array[ShaderMaterial] = []
var _vol_on := false
var _ssr_on := false
var _precip: float = 0.0
var _fog_height: float = 0.0
var _ground_y: float = 0.0
var _quality_override: int = -1
var _profile := false
var _prof_us: int = 0
var _prof_max: int = 0
var _prof_frames: int = 0
var _prof_t: float = 0.0


func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_load_presets()
	_cur = WeatherPreset.new()
	_cur.copy_from(_presets[&"clear"])
	_from = WeatherPreset.new()
	_from.copy_from(_cur)
	_to = _presets[&"clear"]
	_build_environment()
	_build_lights()
	precipitation = Precipitation.new()
	precipitation.name = "Precipitation"
	add_child(precipitation)
	lamps = LampPool.new()
	lamps.name = "Lamps"
	add_child(lamps)
	storm = Lightning.new()
	storm.name = "Lightning"
	add_child(storm)
	storm.struck.connect(_on_struck)
	tunnels = TunnelLight.new()
	tunnels.name = "TunnelLight"
	add_child(tunnels)
	Game.car_spawned.connect(_on_car_spawned)
	Settings.changed.connect(_on_setting)
	_collect_water()
	_apply_quality()
	_parse_args()
	_apply(0.0)


# ------------------------------------------------------------------ contract API

func set_time_of_day(hour: float) -> void:
	time_of_day = fposmod(hour, 24.0)
	_apply(0.0)
	_lights_cut()


func get_time_of_day() -> float:
	return time_of_day


func set_time_scale(s: float) -> void:
	time_scale = maxf(s, 0.0)


func get_time_scale() -> float:
	return time_scale


func set_weather(id: StringName, instant := false) -> void:
	if not _presets.has(id):
		return
	weather_id = id
	_to = _presets[id]
	_from.copy_from(_cur)
	if instant:
		_blend = 1.0
		_cur.copy_from(_to)
		wetness = _to.wetness
		# A hard cut: particles still alive must not keep the old weather's look.
		precipitation.snap()
		_apply(0.0)
		_apply_wetness()
		_lights_cut()
	else:
		_blend = 0.0


func get_weather() -> StringName:
	return weather_id


func get_weather_ids() -> Array[StringName]:
	return WEATHER_IDS.duplicate()


func get_weather_name(id: StringName = &"") -> String:
	var p: WeatherPreset = _presets.get(id if id != &"" else weather_id)
	return p.display_name if p else String(id).capitalize()


## Street lamps 0 (off) .. 1 (full): after dusk and under very dark clouds.
func street_lamp_factor() -> float:
	return clampf(1.0 - smoothstep(-1.5, 5.0, _el) + smoothstep(0.7, 0.95, _cur.cloud_darkness) * 0.8, 0.0, 1.0)


## A hard time / weather cut (console, photo mode while paused): lamps and the player's headlights follow
## at once instead of on the next ticks, and the lamp pool skips its fades.
func _lights_cut() -> void:
	if lamps != null:
		lamps.street_factor = street_lamp_factor()
		lamps.snap()
	_update_headlights()


## Sun below the horizon (astronomical night or deep dusk).
func is_night() -> bool:
	return _el < -1.0


## Vehicles should run their lights: dusk / night, low light (fog, rain, storm, dark overcast) or a tunnel.
## `at`: a car's position for the tunnel test (traffic); without it, the view's tunnel state is used.
func lights_needed(at := Vector3.INF) -> bool:
	if _env_lights:
		return true
	if not at.is_finite():
		return _tunnel
	return tunnels.depth(at) > -LIGHTS_BEFORE_PORTAL


func get_wetness() -> float:
	return wetness


## Rain reaching the camera 0..1 (blended, zero inside tunnels).
func get_precipitation() -> float:
	return _precip


## Rainfall of the blended weather 0..1, ignoring tunnels.
func get_rain() -> float:
	return _cur.rain if _cur else 0.0


## Wind velocity in m/s (horizontal).
func get_wind() -> Vector3:
	return _wind


## Wind strength of the blended weather 0..1 (get_wind() is the velocity).
func get_wind_strength() -> float:
	return _cur.wind if _cur else 0.15


## 0 (night) .. 1 (bright day), weather included.
func get_light_level() -> float:
	return clampf((1.0 - _dark) * lerpf(1.0, 0.55, _cur.overcast), 0.0, 1.0)


## The view is inside a tunnel tube (camera, or the player's car right ahead of a chase camera).
func is_in_tunnel() -> bool:
	return _tunnel


## Metres inside a tunnel tube (> 0), before a portal on its road (< 0), or a large negative value elsewhere.
func tunnel_depth(p: Vector3) -> float:
	return tunnels.depth(p)


func is_point_in_tunnel(p: Vector3) -> bool:
	return tunnels.depth(p) > 0.0


func strike_lightning(distance := -1.0) -> void:
	var cam := get_viewport().get_camera_3d()
	var pos := cam.global_position if cam else Vector3.ZERO
	var dir := -cam.global_transform.basis.z if cam else Vector3.FORWARD
	storm.strike(pos, dir.rotated(Vector3.UP, randf_range(-0.5, 0.5)), distance)


# ------------------------------------------------------------------ setup

func _load_presets() -> void:
	for id in WEATHER_IDS:
		var path := WEATHER_DIR + String(id) + ".tres"
		var p: WeatherPreset = null
		if ResourceLoader.exists(path):
			p = load(path) as WeatherPreset
		if p == null:
			p = WeatherPreset.new()
			p.configure(id)
		_presets[id] = p


func _build_environment() -> void:
	environment = Environment.new()
	environment.background_mode = Environment.BG_SKY
	sky_material = ShaderMaterial.new()
	sky_material.shader = SKY_SHADER
	sky_material.set_shader_parameter("cloud_noise", _noise_texture(512, FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 6, 0.008, false))
	sky_material.set_shader_parameter("detail_noise", _noise_texture(256, FastNoiseLite.TYPE_CELLULAR, 3, 0.03, true))
	var sky := Sky.new()
	sky.sky_material = sky_material
	sky.process_mode = Sky.PROCESS_MODE_REALTIME
	sky.radiance_size = Sky.RADIANCE_SIZE_256
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	environment.tonemap_mode = Environment.TONE_MAPPER_AGX
	environment.tonemap_agx_contrast = 1.3
	environment.adjustment_enabled = true
	environment.glow_enabled = true
	environment.glow_intensity = 0.5
	environment.glow_strength = 1.0
	environment.glow_bloom = 0.015
	environment.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	environment.glow_hdr_threshold = 1.0
	environment.glow_hdr_scale = 2.0
	environment.glow_hdr_luminance_cap = 16.0
	var levels: Array[float] = [0.0, 0.5, 0.9, 0.8, 0.55, 0.3, 0.0]
	for i in levels.size():
		environment.set_glow_level(i, levels[i])
	environment.fog_enabled = true
	environment.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	environment.ssao_radius = 1.6
	environment.ssao_intensity = 1.8
	environment.ssao_power = 1.6
	environment.ssao_detail = 0.6
	environment.ssao_light_affect = 0.05
	environment.ssil_radius = 6.0
	environment.ssil_intensity = 0.7
	environment.ssr_max_steps = 48
	environment.ssr_fade_in = 0.2
	environment.ssr_fade_out = 2.0
	environment.ssr_depth_tolerance = 0.4
	environment.volumetric_fog_anisotropy = 0.55
	environment.volumetric_fog_ambient_inject = 0.3
	environment.volumetric_fog_sky_affect = 0.4
	environment.volumetric_fog_gi_inject = 0.0
	environment.volumetric_fog_temporal_reprojection_enabled = true
	environment.volumetric_fog_temporal_reprojection_amount = 0.9
	world_env = WorldEnvironment.new()
	world_env.name = "WorldEnvironment"
	world_env.environment = environment
	add_child(world_env)


func _noise_texture(size: int, kind: int, octaves: int, freq: float, invert: bool) -> NoiseTexture2D:
	var fn := FastNoiseLite.new()
	fn.seed = 7 + size
	fn.noise_type = kind
	fn.fractal_type = FastNoiseLite.FRACTAL_FBM
	fn.fractal_octaves = octaves
	fn.frequency = freq
	if kind == FastNoiseLite.TYPE_CELLULAR:
		fn.cellular_return_type = FastNoiseLite.RETURN_DISTANCE
	else:
		fn.domain_warp_enabled = true
		fn.domain_warp_amplitude = 22.0
		fn.domain_warp_frequency = 0.012
	var t := NoiseTexture2D.new()
	t.width = size
	t.height = size
	t.seamless = true
	t.generate_mipmaps = true
	t.invert = invert
	t.noise = fn
	return t


func _build_lights() -> void:
	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.shadow_enabled = true
	sun.light_angular_distance = 0.6
	sun.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	sun.light_specular = 1.0
	add_child(sun)
	moon = DirectionalLight3D.new()
	moon.name = "Moon"
	moon.shadow_enabled = false
	moon.light_color = MOON_COLOR
	moon.light_angular_distance = 0.8
	moon.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	moon.light_specular = 0.6
	moon.visible = false
	add_child(moon)


func _collect_water() -> void:
	_water_mats.clear()
	var w := Game.world
	if w == null:
		return
	var wm: Variant = w.get("water_mat")
	if wm is ShaderMaterial:
		_water_mats.append(wm)
	for c in w.get_children():
		if c is MeshInstance3D and (String(c.name).begins_with("River") or String(c.name).begins_with("Lake")):
			var m := (c as MeshInstance3D).material_override
			if m is ShaderMaterial and not _water_mats.has(m):
				_water_mats.append(m)


func _apply_quality() -> void:
	var q := _quality_override if _quality_override >= 0 else int(Settings.get_value("quality", 2))
	var ls: Array[DirectionalLight3D] = [sun, moon]
	_caps = GraphicsQuality.apply(environment, ls, q)
	precipitation.set_quality(q)
	lamps.max_lights = int(_caps["lights"])
	_vol_on = false
	environment.volumetric_fog_enabled = false
	_ssr_on = false
	environment.ssr_enabled = false


func _parse_args() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--timescale="):
			set_time_scale(a.get_slice("=", 1).to_float())
		elif a.begins_with("--tonemap="):
			var tm := a.get_slice("=", 1)
			environment.tonemap_mode = {"filmic": Environment.TONE_MAPPER_FILMIC, "aces": Environment.TONE_MAPPER_ACES}.get(tm, Environment.TONE_MAPPER_AGX)
		elif a == "--env-profile":
			_profile = true
		elif a == "--novsync" and DisplayServer.get_name() != "headless":
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		elif a.begins_with("--quality="):
			# Test override only; never written to the user's settings.
			_quality_override = clampi(a.get_slice("=", 1).to_int(), 0, 3)
			_apply_quality()


func _on_setting(key: String, _value: Variant) -> void:
	if key == "quality" and _quality_override < 0:
		_apply_quality()


func _on_struck(strength: float) -> void:
	lightning.emit(strength)


func _on_car_spawned(car: CarController) -> void:
	if car == null:
		return
	car.headlights_on = _lights_on
	var vis := car.get_node_or_null("Visual")
	if vis and vis.has_method("set_wetness"):
		vis.set_wetness(wetness)


# ------------------------------------------------------------------ per frame

func _process(delta: float) -> void:
	var t0 := Time.get_ticks_usec() if _profile else 0
	_tick(delta)
	if _profile:
		var us := Time.get_ticks_usec() - t0
		_prof_us += us
		_prof_max = maxi(_prof_max, us)
		_prof_frames += 1
		_prof_t += delta
		if _prof_t >= 5.0:
			print("[env] cpu avg %.3f ms max %.3f ms lamps %d lit %d" % [_prof_us / 1000.0 / _prof_frames, _prof_max / 1000.0, lamps.lamp_count, lamps.lit_count()])
			_prof_us = 0
			_prof_max = 0
			_prof_frames = 0
			_prof_t = 0.0


func _tick(delta: float) -> void:
	# While the tree is paused (photo mode pulses the environment after a time / weather change) only the
	# look is applied: the clock, weather transitions and new lightning strikes stay frozen.
	var live := not get_tree().paused
	_clock += delta
	if live:
		time_of_day = fposmod(time_of_day + delta * time_scale / SECONDS_PER_HOUR, 24.0)
	if _blend < 1.0 and live:
		_blend = minf(_blend + delta / TRANSITION_TIME, 1.0)
		_cur.blend(_from, _to, smoothstep(0.0, 1.0, _blend))
	var cam := get_viewport().get_camera_3d()
	var cam_pos := cam.global_position if cam else Vector3.ZERO
	_update_region(delta, cam_pos)
	_update_tunnel(delta, cam_pos)
	_update_wind(delta)
	_update_fog_layer(delta, cam_pos)
	storm.rate_per_minute = _cur.lightning_per_minute if live else 0.0
	storm.indoor = _tunnel_t
	storm.light_scale = _flash_scale()
	storm.update(cam_pos, delta)
	_apply(delta)
	_update_wetness(delta)
	_update_precipitation(cam_pos, delta)
	lamps.street_factor = street_lamp_factor()
	lamps.update(cam_pos, delta)
	_update_headlights()


func _update_region(delta: float, p: Vector3) -> void:
	_region_timer -= delta
	if _region_timer <= 0.0:
		_region_timer = 0.5
		var w := Game.world as World
		if w != null and w.data != null:
			var c := w.data.region_weights_at(p.x, p.z)
			var s := maxf(c.r + c.g + c.b + c.a, 0.001)
			_region_target = Color(c.r / s, c.g / s, c.b / s, c.a / s)
	var k := clampf(delta * 0.6, 0.0, 1.0) if delta > 0.0 else 1.0
	_region_w = _region_w.lerp(_region_target, k)
	var windy := smoothstep(0.3, 0.75, _cur.wind)
	# Rain and wet ground wash the blown sand out completely (a sparse remainder reads as smudges).
	_dust = _region_w.b * windy * (1.0 - smoothstep(0.05, 0.3, _cur.rain)) * (1.0 - smoothstep(0.15, 0.45, wetness))


func _region_mix_f(values: Array[float]) -> float:
	return values[0] * _region_w.r + values[1] * _region_w.g + values[2] * _region_w.b + values[3] * _region_w.a


func _region_tint() -> Color:
	var c := Color(0, 0, 0)
	for i in 4:
		c += REGION_TINT[i] * _region_w[i]
	return Color(c.r, c.g, c.b, 1.0)


## Tunnel state from what the player sees: the camera's depth inside a tube, or the player's car's depth
## minus the camera's distance behind it (a chase camera at a portal, or one pushed out of the tube by its
## collision, still counts as entering with the car). Everything eases with depth, so nothing pops at a
## portal; big jumps (teleports) snap.
func _update_tunnel(delta: float, p: Vector3) -> void:
	if not tunnels.ensure_built():
		return
	if not _shelters_set:
		_shelters_set = true
		precipitation.set_shelters(tunnels.roof_segments())
	_tunnel_timer -= delta
	var snap := delta <= 0.0
	if _tunnel_timer <= 0.0:
		_tunnel_timer = 0.1
		_cam_depth = tunnels.depth(p)
		var car := Game.player_car
		var has_car := car != null and is_instance_valid(car)
		_car_depth = tunnels.depth(car.global_position) if has_car else TunnelLight.OUTSIDE
		var eye := _cam_depth
		if has_car:
			var gap := p.distance_to(car.global_position)
			if gap < 20.0:
				eye = maxf(eye, _car_depth - gap)
		snap = snap or absf(clampf(eye, -60.0, 400.0) - clampf(_eye_depth, -60.0, 400.0)) > 30.0
		_eye_depth = eye
		_tunnel = eye > 0.0
	var eye_t := smoothstep(0.0, EYE_DEPTH, _eye_depth)
	var sun_t := smoothstep(SUN_DEPTH.x, SUN_DEPTH.y, _eye_depth)
	var shelter := smoothstep(-1.0, 5.0, _cam_depth)
	var deep := smoothstep(18.0, 28.0, _cam_depth)
	if snap:
		_tunnel_t = eye_t
		_sun_cover = sun_t
		_shelter_t = shelter
		_deep_t = deep
	else:
		_tunnel_t = move_toward(_tunnel_t, eye_t, delta * 0.9)
		_sun_cover = move_toward(_sun_cover, sun_t, delta * 2.0)
		_shelter_t = move_toward(_shelter_t, shelter, delta * 2.5)
		_deep_t = move_toward(_deep_t, deep, delta * 2.5)


func _update_wind(delta: float) -> void:
	_wind_angle += sin(_clock * 0.021) * 0.015 * delta
	var wd := Vector2(cos(_wind_angle), sin(_wind_angle))
	var strength := _cur.wind
	_wind = Vector3(wd.x, 0.0, wd.y) * (1.5 + strength * 13.0)
	var cs := _cur.cloud_speed
	_cloud_offset = (_cloud_offset + wd * 0.0022 * cs * delta).posmod(1.0)
	_cirrus_offset = (_cirrus_offset + wd.rotated(0.4) * 0.0007 * delta).posmod(1.0)


## Height fog: a low layer hugging the terrain under the camera in fog weather (hills rise out of it),
## morning mist in the valleys, and a faint sea mist otherwise. Godot's height fog is distance independent,
## so the layer height eases after the camera instead of jumping.
func _update_fog_layer(delta: float, p: Vector3) -> void:
	var w := Game.world as World
	if w != null and w.data != null:
		_ground_y = w.height_at(p.x, p.z)
	var mist := smoothstep(5.2, 6.4, time_of_day) * (1.0 - smoothstep(8.0, 10.5, time_of_day)) * (1.0 - _cur.wind) * (1.0 - _cur.rain)
	var low := _cur.low_fog
	var target := lerpf(lerpf(6.0, 24.0, mist), _ground_y + 18.0, smoothstep(0.0, 0.004, low))
	_fog_height = target if delta <= 0.0 or absf(target - _fog_height) > 60.0 else move_toward(_fog_height, target, delta * 6.0)
	environment.fog_height = _fog_height
	environment.fog_height_density = (low + mist * 0.018 + 0.006) * (1.0 - _tunnel_t)


func _light_basis(dir_to_light: Vector3) -> Basis:
	var up := Vector3.UP if absf(dir_to_light.y) < 0.995 else Vector3.FORWARD
	return Basis.looking_at(-dir_to_light, up)


func _apply(_delta: float) -> void:
	var w := _cur
	var sun_dir := SkyModel.sun_direction(time_of_day)
	var moon_dir := SkyModel.moon_direction(time_of_day)
	_el = SkyModel.elevation_deg(sun_dir)
	var moon_el := SkyModel.elevation_deg(moon_dir)
	_dark = SkyModel.darkness(_el)
	var overcast := w.overcast
	var cloud_dark := w.cloud_darkness
	var softness := w.shadow_softness
	var sky_tint: Color = w.sky_tint
	var flash: float = storm.flash
	var cols := SkyModel.sky_colors(_el)
	var zen: Color = cols[0] * sky_tint
	var hor: Color = cols[1] * sky_tint
	var glow: Color = cols[2] * (1.0 - overcast * 0.85)
	var low_sun := 1.0 - smoothstep(4.0, 22.0, _el)

	# --- sun and moon lights
	var sun_col := SkyModel.sun_color(_el)
	var sun_raw := SkyModel.sun_energy(_el)
	var sun_e := sun_raw * w.sun_energy
	# Deep in a tunnel the sun must not reach the tube (its shadow there is not reliable).
	var uncovered := 1.0 - _sun_cover
	sun.basis = _light_basis(sun_dir)
	sun.light_color = sun_col
	sun.light_energy = sun_e * uncovered
	sun.visible = sun_e * uncovered > 0.003
	sun.light_angular_distance = lerpf(0.6, 2.4, softness)
	var sun_shadow := clampf(sun_e / 0.3, 0.0, 1.0) * lerpf(1.0, 0.55, softness)
	sun.shadow_opacity = sun_shadow
	var want_sun_shadow := sun_shadow > 0.05
	if sun.shadow_enabled != want_sun_shadow:
		sun.shadow_enabled = want_sun_shadow
	var moon_vis := smoothstep(-3.0, 10.0, moon_el) * (1.0 - smoothstep(-8.0, -2.0, _el))
	var moon_e := 0.22 * moon_vis * (1.0 - overcast * 0.7) * uncovered
	moon.basis = _light_basis(moon_dir if moon_el > 2.0 else Vector3(moon_dir.x, 0.035, moon_dir.z).normalized())
	moon.light_energy = moon_e
	moon.visible = moon_e > 0.003
	var want_moon_shadow := not want_sun_shadow and moon_e > 0.05 and int(_caps.get("quality", 2)) >= 1
	if moon.shadow_enabled != want_moon_shadow:
		moon.shadow_enabled = want_moon_shadow

	# --- ambient, exposure, grading
	# Tunnel interiors get their ambient and reflections from local probes (TunnelLight); globally only
	# the eye adapts: exposure eases to the tunnel value, so the view out of a portal glares.
	# The lightning flash is scaled against the night exposure boost (flash_k), so a night strike lights
	# the scene briefly without turning it into daylight.
	var night_gain := lerpf(1.0, NIGHT_EXPOSURE, _dark)
	var flash_k := flash * _flash_scale()
	# Sky irradiance is mostly zenith blue; mixing in the horizon colour warms shadows at golden hour.
	var day_amb := hor * 0.62 + sun_col * 0.05 * (1.0 - overcast)
	var night_amb := NIGHT_AMBIENT * (1.0 + moon_vis * 0.9) * lerpf(1.0, 0.85, overcast)
	var sky_contrib := lerpf(lerpf(0.88, 0.7, low_sun), 0.4, _dark)
	environment.ambient_light_sky_contribution = sky_contrib
	environment.ambient_light_color = day_amb.lerp(night_amb, _dark)
	environment.ambient_light_energy = w.ambient_energy + flash_k * 0.8 * (1.0 - _tunnel_t)
	var outdoor_exp := BASE_EXPOSURE * w.exposure * night_gain
	environment.tonemap_exposure = lerpf(outdoor_exp, TUNNEL_EXPOSURE, _tunnel_t)
	# Linear outdoor ambient (sky radiance mixed with the sRGB ambient colour) for the portal daylight spill.
	var sky_amb := (zen * 0.5 + hor * 0.5).lerp(environment.ambient_light_color.srgb_to_linear(), 1.0 - sky_contrib) * w.ambient_energy
	tunnels.set_outdoor_ambient(sky_amb)
	environment.adjustment_saturation = w.saturation * _region_mix_f(REGION_SAT) * lerpf(1.0, 0.82, _dark) * (1.0 + 0.12 * low_sun * (1.0 - overcast) * (1.0 - _dark))
	environment.adjustment_contrast = w.contrast

	# --- fog
	var rt := _region_tint()
	var light_lum := clampf(hor.get_luminance() / 0.75, 0.025, 1.3)
	var wfog: Color = w.fog_color * light_lum
	var haze := hor.lerp(wfog, w.fog_tint) * rt
	haze = haze.lerp(Color(0.78, 0.6, 0.42) * light_lum, _dust * 0.6)
	# Inside a tunnel the air in view is lamp-lit, not daylight haze.
	var fog_col := haze.lerp(TUNNEL_HAZE, _tunnel_t)
	var vol_density := w.volumetric_density + 0.0035 * low_sun * (1.0 - overcast) * (1.0 - _dark) + _dust * 0.004
	var vol_allowed := bool(_caps.get("volumetric", false)) and (vol_density > 0.0012 or bool(_caps.get("volumetric_always", false)))
	vol_allowed = vol_allowed and vol_density > 0.0002
	if vol_allowed != _vol_on:
		_vol_on = vol_allowed
		environment.volumetric_fog_enabled = vol_allowed
	var fog_d := w.fog_density * _region_mix_f(REGION_FOG) + _dust * 0.0011
	if not _vol_on:
		fog_d += w.volumetric_density * 0.5
	environment.fog_density = fog_d
	environment.fog_light_color = fog_col
	environment.fog_light_energy = 1.0
	environment.fog_aerial_perspective = w.aerial_perspective * (1.0 - _tunnel_t)
	environment.fog_sky_affect = w.fog_sky_affect
	environment.fog_sun_scatter = (0.08 + 0.3 * low_sun) * (1.0 - overcast) * (1.0 - _dark) * uncovered
	if _vol_on:
		environment.volumetric_fog_density = vol_density
		environment.volumetric_fog_length = float(_caps.get("volumetric_length", 120.0))
		environment.volumetric_fog_albedo = Color(0.92, 0.93, 0.95).lerp(Color(0.95, 0.82, 0.66), _dust)
		# Sky light injected into the froxels would make the tube glow.
		environment.volumetric_fog_ambient_inject = 0.3 * (1.0 - 0.85 * _tunnel_t)

	# --- sky
	var ambient_col := zen * 0.5 + hor * 0.5
	var main_light := sun_col * minf(sun_raw, 1.7) * 0.55 + MOON_COLOR * moon_vis * 0.05
	var cloud_lit := (main_light * (1.0 - 0.6 * overcast) + ambient_col * 0.85) * (1.0 - 0.55 * cloud_dark)
	var cloud_shade := ambient_col * lerpf(0.78, 0.3, cloud_dark) + main_light * 0.1 * (1.0 - overcast)
	var oc_base := ambient_col * 0.75 + main_light * 0.22
	var oc_l := oc_base.get_luminance()
	var oc := Color(oc_l * 0.96, oc_l * 0.99, oc_l * 1.05).lerp(oc_base, 0.25) * (1.0 - 0.62 * cloud_dark) + glow * 0.1
	var sun_vis := smoothstep(-1.5, 0.5, _el)
	var disk := sun_col * clampf(sun_raw, 0.35, 1.0) * sun_vis
	var sm := sky_material
	sm.set_shader_parameter("sun_dir", sun_dir)
	sm.set_shader_parameter("moon_dir", moon_dir)
	sm.set_shader_parameter("light_dir", sun_dir if _el > -4.0 else moon_dir)
	sm.set_shader_parameter("sun_light", _v3(disk))
	sm.set_shader_parameter("moon_light", _v3(Color(0.78, 0.82, 0.9) * lerpf(0.5, 1.0, _dark)))
	sm.set_shader_parameter("zenith_color", _v3(zen))
	sm.set_shader_parameter("horizon_color", _v3(hor))
	sm.set_shader_parameter("glow_color", _v3(glow))
	sm.set_shader_parameter("ground_color", _v3(hor * 0.32 + Color(0.02, 0.02, 0.02) * (1.0 - _dark)))
	sm.set_shader_parameter("haze_color", _v3(haze))
	sm.set_shader_parameter("overcast_color", _v3(oc))
	sm.set_shader_parameter("cloud_lit", _v3(cloud_lit))
	sm.set_shader_parameter("cloud_shade", _v3(cloud_shade))
	sm.set_shader_parameter("stars", _dark * _dark)
	sm.set_shader_parameter("star_angle", time_of_day / 24.0 * TAU)
	sm.set_shader_parameter("overcast", overcast)
	sm.set_shader_parameter("haze", clampf(w.haze + _dust * 0.4, 0.0, 1.0))
	sm.set_shader_parameter("cloud_coverage", w.cloud_coverage)
	sm.set_shader_parameter("cloud_darkness", cloud_dark)
	sm.set_shader_parameter("cirrus", w.cirrus)
	sm.set_shader_parameter("cloud_offset", _cloud_offset)
	sm.set_shader_parameter("cirrus_offset", _cirrus_offset)
	sm.set_shader_parameter("flash", flash_k)
	sm.set_shader_parameter("flash_dir", storm.flash_dir)

	# --- SSR on wet roads
	var want_ssr := bool(_caps.get("ssr", false)) and wetness > 0.2 and _tunnel_t < 0.5
	if want_ssr != _ssr_on:
		_ssr_on = want_ssr
		environment.ssr_enabled = want_ssr


## Flash light is authored for daylight. At night the exposure boost would turn every strike into
## daylight, so the flash's light (ambient, sky, flash light) is divided by that boost and reduced further
## in full darkness: a near strike lights the night landscape, far below a clear noon.
func _flash_scale() -> float:
	return lerpf(0.65, 0.2, _dark) / lerpf(1.0, NIGHT_EXPOSURE, _dark)


static func _v3(c: Color) -> Vector3:
	return Vector3(c.r, c.g, c.b)


func _update_wetness(delta: float) -> void:
	var target := _cur.wetness
	wetness = move_toward(wetness, target, delta / (WET_TIME if target > wetness else DRY_TIME))
	_wet_timer -= delta
	if _wet_timer <= 0.0 or absf(wetness - _wet_applied) > 0.02:
		_wet_timer = 0.25
		_apply_wetness()


func _apply_wetness() -> void:
	_wet_applied = wetness
	CarController.wetness = wetness
	var w := Game.world
	if w != null:
		var tm: Variant = w.get("terrain_mat")
		if tm is ShaderMaterial:
			(tm as ShaderMaterial).set_shader_parameter("wetness", wetness * 0.55)
		var roads: Variant = w.get("roads")
		if roads is Object and (roads as Object).get("road_mat") is ShaderMaterial:
			((roads as Object).get("road_mat") as ShaderMaterial).set_shader_parameter("wetness", wetness)
	var storminess := clampf((_cur.wind - 0.25) / 0.75, 0.0, 1.0)
	for m in _water_mats:
		m.set_shader_parameter("storminess", storminess)
	_wet_car(Game.player_car)
	for c in get_tree().get_nodes_in_group("cars"):
		_wet_car(c)


func _wet_car(car: Node) -> void:
	if car == null or not is_instance_valid(car):
		return
	var vis := car.get_node_or_null("Visual")
	if vis and vis.has_method("set_wetness"):
		vis.set_wetness(wetness)


func _update_precipitation(cam_pos: Vector3, delta: float) -> void:
	_precip = _cur.rain * (1.0 - _shelter_t)
	var rain := _cur.rain * (1.0 - _deep_t)
	var alt_snow := smoothstep(165.0, 205.0, cam_pos.y) * smoothstep(0.85, 1.0, _cur.wind)
	precipitation.rain_amount = rain * (1.0 - alt_snow)
	precipitation.snow_amount = rain * alt_snow
	precipitation.dust_amount = _dust * (1.0 - _deep_t)
	precipitation.wind = _wind
	var lum := clampf((sky_material.get_shader_parameter("horizon_color") as Vector3).length() * 0.9, 0.04, 1.0)
	precipitation.tint = Color(0.66, 0.7, 0.76) * lum + Color(0.05, 0.05, 0.05)
	precipitation.update(cam_pos, delta)


## The player's lights follow the weather / daylight and the car's own position (not the camera's):
## on shortly before a portal, off a little after leaving the tube. Traffic asks lights_needed(position).
func _update_headlights() -> void:
	_env_lights = _el < (5.0 if _env_lights else 3.5) or _cur.lights_on > 0.5 or get_light_level() < (0.3 if _env_lights else 0.26)
	_car_tunnel_lights = _car_depth > (-LIGHTS_AFTER_PORTAL if _car_tunnel_lights else -LIGHTS_BEFORE_PORTAL)
	var need := _env_lights or _car_tunnel_lights
	if need == _lights_on:
		return
	_lights_on = need
	if Game.player_car and is_instance_valid(Game.player_car):
		Game.player_car.headlights_on = need
