class_name SkyWeather
extends Node3D
## Day/night cycle and weather states (clear, cloudy, rain, fog, storm). Drives the
## sun/moon, sky colours, fog, rain particles, road wetness and the tyre grip factor.

const STATES := ["clear", "cloudy", "rain", "fog", "storm"]
const PRESETS := {
	"clear": {"cloud": 0.1, "fog": 0.0004, "rain": 0.0, "wet": 0.0, "light": 1.0, "vol": 0.0},
	"cloudy": {"cloud": 0.7, "fog": 0.0007, "rain": 0.0, "wet": 0.0, "light": 0.65, "vol": 0.0},
	"rain": {"cloud": 0.9, "fog": 0.0016, "rain": 0.7, "wet": 1.0, "light": 0.45, "vol": 0.01},
	"fog": {"cloud": 0.6, "fog": 0.009, "rain": 0.0, "wet": 0.3, "light": 0.55, "vol": 0.03},
	"storm": {"cloud": 1.0, "fog": 0.0028, "rain": 1.0, "wet": 1.0, "light": 0.3, "vol": 0.02},
}

var hour := 15.0
var time_scale := 1.0 / 60.0 # game hours per real second (1 h per minute)
var freeze_time := false
var state := "clear"
var cur := PRESETS["clear"].duplicate()
var env: Environment
var sun: DirectionalLight3D
var moon: DirectionalLight3D
var sky_mat: ProceduralSkyMaterial
var rain: GPUParticles3D
var follow: Node3D
var grip_factor := 1.0
var lightning := 0.0
var _lightning_timer := 5.0

func _ready() -> void:
	var we := WorldEnvironment.new()
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	sky_mat = ProceduralSkyMaterial.new()
	sky.sky_material = sky_mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.0
	env.glow_enabled = true
	env.glow_intensity = 0.6
	env.glow_bloom = 0.05
	env.ssao_enabled = true
	env.ssao_radius = 1.5
	env.fog_enabled = true
	env.fog_light_color = Color(0.7, 0.78, 0.88)
	env.fog_sun_scatter = 0.25
	env.fog_aerial_perspective = 0.4
	env.volumetric_fog_enabled = false
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.08
	we.environment = env
	add_child(we)
	sun = DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 220.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.light_angular_distance = 0.6
	add_child(sun)
	moon = DirectionalLight3D.new()
	moon.light_color = Color(0.55, 0.65, 0.9)
	moon.shadow_enabled = false
	add_child(moon)
	_make_rain()
	set_weather("clear", true)

func _make_rain() -> void:
	rain = GPUParticles3D.new()
	rain.amount = 6000
	rain.lifetime = 1.2
	rain.visibility_aabb = AABB(Vector3(-40, -30, -40), Vector3(80, 60, 80))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(35, 1, 35)
	pm.direction = Vector3(0.1, -1, 0)
	pm.spread = 3.0
	pm.initial_velocity_min = 22.0; pm.initial_velocity_max = 28.0
	pm.gravity = Vector3(0, -9.8, 0)
	rain.process_material = pm
	var q := QuadMesh.new(); q.size = Vector2(0.025, 0.7)
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.8, 0.85, 0.95, 0.35)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	q.material = m
	rain.draw_pass_1 = q
	rain.emitting = false
	add_child(rain)

func set_weather(s: String, instant: bool = false) -> bool:
	if not PRESETS.has(s): return false
	state = s
	if instant: cur = PRESETS[s].duplicate()
	return true

func set_hour(h: float) -> void:
	hour = fposmod(h, 24.0)

func is_night() -> bool:
	return hour < 6.3 or hour > 19.6

func _process(dt: float) -> void:
	if not freeze_time: hour = fposmod(hour + dt * time_scale, 24.0)
	var tgt: Dictionary = PRESETS[state]
	for k in cur.keys(): cur[k] = lerpf(cur[k], tgt[k], clampf(dt * 0.25, 0.0, 1.0))
	# sun path: rises at 6, sets at 20
	var t := (hour - 6.0) / 14.0
	var elev := sin(t * PI) * 62.0
	var az := lerpf(-100.0, 100.0, t)
	sun.rotation_degrees = Vector3(-elev, az, 0)
	var day := clampf(smoothstep(-6.0, 8.0, elev), 0.0, 1.0)
	var golden := clampf(1.0 - absf(elev - 6.0) / 14.0, 0.0, 1.0)
	var sun_col := Color(1.0, 0.96, 0.9).lerp(Color(1.0, 0.55, 0.3), golden)
	sun.light_color = sun_col
	sun.light_energy = day * 1.25 * cur.light
	sun.visible = elev > -4.0
	moon.rotation_degrees = Vector3(-45, az + 180.0, 0)
	moon.light_energy = (1.0 - day) * 0.12
	moon.visible = day < 0.9
	var top := Color(0.22, 0.42, 0.78).lerp(Color(0.02, 0.03, 0.08), 1.0 - day)
	var hz := Color(0.65, 0.78, 0.92).lerp(Color(1.0, 0.6, 0.38), golden * 0.8).lerp(Color(0.05, 0.06, 0.12), 1.0 - day)
	var grey := Color(0.5, 0.53, 0.57) * (0.25 + 0.75 * day)
	top = top.lerp(grey, cur.cloud * 0.85); hz = hz.lerp(grey * 1.1, cur.cloud * 0.8)
	if lightning > 0.0:
		top = top.lerp(Color(0.9, 0.9, 1.0), lightning); hz = hz.lerp(Color(0.9, 0.9, 1.0), lightning)
	sky_mat.sky_top_color = top
	sky_mat.sky_horizon_color = hz
	sky_mat.ground_horizon_color = hz
	sky_mat.ground_bottom_color = hz * 0.5
	sky_mat.sun_angle_max = 30.0
	sky_mat.sky_cover_modulate = Color(1, 1, 1, cur.cloud)
	env.ambient_light_energy = 0.35 + 0.65 * day
	env.background_energy_multiplier = 0.3 + 0.7 * day + lightning * 2.0
	env.fog_density = cur.fog
	env.fog_light_color = hz.lerp(Color(0.6, 0.62, 0.65), cur.cloud * 0.5)
	env.volumetric_fog_enabled = cur.vol > 0.002
	env.volumetric_fog_density = cur.vol
	env.tonemap_exposure = 1.0 + (1.0 - day) * 0.6
	RenderingServer.global_shader_parameter_set("wetness", cur.wet)
	rain.emitting = cur.rain > 0.1
	rain.amount_ratio = clampf(cur.rain, 0.0, 1.0)
	if follow:
		var lead := Vector3.ZERO
		if follow is RigidBody3D: lead = (follow as RigidBody3D).linear_velocity * 0.6
		rain.global_position = follow.global_position + Vector3.UP * 18.0 + lead
	grip_factor = 1.0 - 0.25 * cur.wet
	# storm lightning
	lightning = maxf(lightning - dt * 4.0, 0.0)
	if state == "storm":
		_lightning_timer -= dt
		if _lightning_timer <= 0.0:
			lightning = 1.0; _lightning_timer = randf_range(4.0, 12.0)
