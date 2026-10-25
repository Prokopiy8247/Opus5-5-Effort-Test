extends Node3D
## Rain streaks plus a "drift" layer (snow flurries at altitude or wind-blown dust in the mesa) around
## the active camera. Both are GPU particles that wrap inside a box following the camera, so the effect
## never runs dry at 250 km/h. The environment controller sets the amounts every frame via update().
## Drops inside a tunnel tube are hidden per drop (set_shelters()): the process shader gets a small
## variant built from precip_particles.gdshader that tests the covered pieces near the camera.

const PROCESS_SHADER := preload("res://assets/shaders/precip_particles.gdshader")
const RAIN_SHADER := preload("res://assets/shaders/precip_rain.gdshader")
const DRIFT_SHADER := preload("res://assets/shaders/precip_drift.gdshader")
const RAIN_AMOUNT: Array[int] = [3000, 5000, 8000, 10000]
const DRIFT_AMOUNT: Array[int] = [700, 1100, 1600, 2200]
const MAX_SHELTERS := 24            # size of the shader's shelter arrays
## Added to the process shader: a drop inside a covered piece (road segment a -> b, half width, roof height)
## collapses to nothing (zero streak and size) and shows again once it is out in the open.
const SHELTER_CODE := """uniform int shelter_count = 0;
uniform vec4 shelter_a[24];
uniform vec4 shelter_b[24];

bool sheltered(vec3 p) {
	for (int i = 0; i < shelter_count; i++) {
		vec3 a = shelter_a[i].xyz;
		vec2 ab = shelter_b[i].xz - a.xz;
		float t = dot(p.xz - a.xz, ab) / max(dot(ab, ab), 0.0001);
		if (t >= 0.0 && t <= 1.0) {
			float y = mix(a.y, shelter_b[i].y, t);
			if (distance(p.xz, a.xz + ab * t) < shelter_a[i].w && p.y > y - 2.5 && p.y < y + shelter_b[i].w) {
				return true;
			}
		}
	}
	return false;
}

"""
const SHELTER_HIDE := """	if (shelter_count > 0 && sheltered(p)) {
		TRANSFORM[0] = vec4(0.0);
		TRANSFORM[1] = vec4(0.0);
	}
"""
const SHELTER_HOOK := "	TRANSFORM[3] = vec4(p, 1.0);"

var rain_amount: float = 0.0
var snow_amount: float = 0.0
var dust_amount: float = 0.0
var wind: Vector3 = Vector3.ZERO
var tint: Color = Color(0.7, 0.74, 0.8)

var _rain: GPUParticles3D
var _drift: GPUParticles3D
var _rain_proc: ShaderMaterial
var _drift_proc: ShaderMaterial
var _rain_draw: ShaderMaterial
var _drift_draw: ShaderMaterial
var _last_pos: Vector3 = Vector3.INF
var _cam_vel: Vector3 = Vector3.ZERO
## Visible strength of each layer (opacity multiplier). Particles outlive their emitter by up to one
## lifetime, so the look keeps updating (and fades) until they are gone; snap() makes it jump.
var _rain_vis: float = 0.0
var _drift_vis: float = 0.0
var _rain_alive: float = 0.0
var _drift_alive: float = 0.0
var _drift_snow := false
var _snap := false
var _shelters: Array[Vector4] = []
var _shelter_pick := PackedInt32Array()
static var _sheltered_shader: Shader


func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_rain_proc = _proc_material(Vector3(56.0, 28.0, 56.0))
	_rain_draw = ShaderMaterial.new()
	_rain_draw.shader = RAIN_SHADER
	_rain = _make_system("Rain", _rain_proc, _rain_draw, 1.0)
	_drift_proc = _proc_material(Vector3(44.0, 22.0, 44.0))
	_drift_draw = ShaderMaterial.new()
	_drift_draw.shader = DRIFT_SHADER
	_drift = _make_system("Drift", _drift_proc, _drift_draw, 4.0)
	set_quality(int(Settings.get_value("quality", 2)))


func _proc_material(box: Vector3) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = _process_shader()
	m.set_shader_parameter("box_size", box)
	return m


static func _process_shader() -> Shader:
	if _sheltered_shader == null:
		var code := PROCESS_SHADER.code
		if not code.contains("void start()") or code.count(SHELTER_HOOK) != 1:
			push_warning("precipitation: unexpected precip_particles.gdshader layout, rain is not hidden in tunnels")
			return PROCESS_SHADER
		_sheltered_shader = Shader.new()
		_sheltered_shader.code = code.replace("void start()", SHELTER_CODE + "void start()").replace(SHELTER_HOOK, SHELTER_HIDE + SHELTER_HOOK)
	return _sheltered_shader


## Covered volumes (pairs from TunnelLight.roof_segments()): no rain, snow or dust is drawn inside them.
func set_shelters(segments: Array[Vector4]) -> void:
	_shelters = segments
	_shelter_pick = PackedInt32Array([-1])


## Sends the covered pieces nearest the precipitation boxes (up to MAX_SHELTERS) to both process materials.
func _update_shelters(center: Vector3) -> void:
	if _shelters.is_empty() and _shelter_pick.is_empty():
		return
	var reach := 46.0
	var near: Array[Vector2] = []
	for k in range(0, _shelters.size(), 2):
		var a := _shelters[k]
		var b := _shelters[k + 1]
		var a2 := Vector2(a.x, a.z)
		var ab := Vector2(b.x, b.z) - a2
		var c2 := Vector2(center.x, center.z)
		var t := clampf((c2 - a2).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
		var d := c2.distance_to(a2 + ab * t)
		if d < reach and absf(center.y - lerpf(a.y, b.y, t)) < 30.0:
			near.append(Vector2(d, k))
	if near.size() > MAX_SHELTERS:
		near.sort_custom(func(x: Vector2, y: Vector2) -> bool: return x.x < y.x)
		near.resize(MAX_SHELTERS)
	var pick := PackedInt32Array()
	for v in near:
		pick.append(int(v.y))
	if pick == _shelter_pick:
		return
	_shelter_pick = pick
	var sa := PackedVector4Array()
	var sb := PackedVector4Array()
	sa.resize(MAX_SHELTERS)
	sb.resize(MAX_SHELTERS)
	for i in pick.size():
		sa[i] = _shelters[pick[i]]
		sb[i] = _shelters[pick[i] + 1]
	for m: ShaderMaterial in [_rain_proc, _drift_proc]:
		m.set_shader_parameter("shelter_count", pick.size())
		m.set_shader_parameter("shelter_a", sa)
		m.set_shader_parameter("shelter_b", sb)


## Number of covered pieces currently tested by the particles (QA).
func shelter_count() -> int:
	return _shelter_pick.size() if not _shelter_pick.has(-1) else 0


func _make_system(n: String, proc: ShaderMaterial, draw: ShaderMaterial, life: float) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = n
	p.process_material = proc
	var q := QuadMesh.new()
	q.size = Vector2(1.0, 1.0)
	q.material = draw
	p.draw_pass_1 = q
	p.lifetime = life
	p.fixed_fps = 0
	p.interpolate = false
	p.local_coords = false
	p.emitting = false
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.visibility_aabb = AABB(Vector3(-40, -30, -40), Vector3(80, 60, 80))
	add_child(p)
	return p


func set_quality(q: int) -> void:
	q = clampi(q, 0, 3)
	if _rain.amount != RAIN_AMOUNT[q]:
		_rain.amount = RAIN_AMOUNT[q]
	if _drift.amount != DRIFT_AMOUNT[q]:
		_drift.amount = DRIFT_AMOUNT[q]


## Instant weather / time cut: the visible layers jump to their new strength (stale particles vanish
## at once instead of keeping the previous weather's colour, also while the tree is paused).
func snap() -> void:
	_snap = true


func update(cam_pos: Vector3, delta: float) -> void:
	if _last_pos == Vector3.INF or cam_pos.distance_to(_last_pos) > 40.0:
		_cam_vel = Vector3.ZERO
	elif delta > 0.0:
		_cam_vel = _cam_vel.lerp((cam_pos - _last_pos) / delta, clampf(delta * 6.0, 0.0, 1.0))
	_last_pos = cam_pos
	global_position = cam_pos
	var lead := _cam_vel * 0.3
	lead.y = 0.0
	_update_shelters(cam_pos + lead)
	var snap_now := _snap or delta <= 0.0
	_snap = false
	# Rain
	var rain_on := rain_amount > 0.01
	if rain_on != _rain.emitting:
		_rain.emitting = rain_on
	_rain_alive = _rain.lifetime * 1.2 if rain_on else maxf(_rain_alive - delta, 0.0)
	var rain_target := 1.0 if rain_on else 0.0
	_rain_vis = rain_target if snap_now else move_toward(_rain_vis, rain_target, delta / _rain.lifetime)
	if rain_on or _rain_alive > 0.0 or snap_now:
		if rain_on:
			_rain.amount_ratio = clampf(rain_amount, 0.0, 1.0)
		_rain_proc.set_shader_parameter("box_center", cam_pos + lead + Vector3(0, 2.0, 0))
		_rain_proc.set_shader_parameter("fall_velocity", Vector3(wind.x * 0.8, -11.0, wind.z * 0.8))
		_rain_proc.set_shader_parameter("camera_velocity", _cam_vel)
		_rain_proc.set_shader_parameter("streak_time", 0.028)
		_rain_proc.set_shader_parameter("min_length", 0.45)
		_rain_proc.set_shader_parameter("particle_size", 0.011)
		_rain_draw.set_shader_parameter("tint", Vector3(tint.r, tint.g, tint.b))
		_rain_draw.set_shader_parameter("opacity", lerpf(0.22, 0.42, rain_amount) * _rain_vis)
	# Drift: snow wins over dust. Sparse dust would read as separate smudges, so its opacity also
	# follows the amount, not only the particle count.
	var drift := maxf(snow_amount, dust_amount)
	var drift_on := drift > 0.01
	if drift_on:
		_drift_snow = snow_amount >= dust_amount
	var snow := _drift_snow
	if drift_on != _drift.emitting:
		_drift.emitting = drift_on
	_drift_alive = _drift.lifetime * 1.2 if drift_on else maxf(_drift_alive - delta, 0.0)
	var drift_target := (1.0 if snow else smoothstep(0.0, 0.3, drift)) if drift_on else 0.0
	_drift_vis = drift_target if snap_now else move_toward(_drift_vis, drift_target, delta / 1.5)
	if drift_on or _drift_alive > 0.0 or snap_now:
		if drift_on:
			_drift.amount_ratio = clampf(drift, 0.0, 1.0)
		_drift_proc.set_shader_parameter("box_center", cam_pos + lead)
		_drift_proc.set_shader_parameter("camera_velocity", _cam_vel)
		if snow:
			_drift_proc.set_shader_parameter("fall_velocity", Vector3(wind.x * 0.6, -1.4, wind.z * 0.6))
			_drift_proc.set_shader_parameter("turbulence", 0.9)
			_drift_proc.set_shader_parameter("streak_time", 0.012)
			_drift_proc.set_shader_parameter("min_length", 0.0)
			_drift_proc.set_shader_parameter("particle_size", 0.03)
			_drift_draw.set_shader_parameter("tint", Vector3(tint.r, tint.g, tint.b) * 1.35)
			_drift_draw.set_shader_parameter("opacity", 0.85 * _drift_vis)
			_drift_draw.set_shader_parameter("far_fade", 22.0)
		else:
			_drift_proc.set_shader_parameter("fall_velocity", Vector3(wind.x * 1.1, -0.15, wind.z * 1.1))
			_drift_proc.set_shader_parameter("turbulence", 1.6)
			_drift_proc.set_shader_parameter("streak_time", 0.0)
			_drift_proc.set_shader_parameter("min_length", 0.0)
			_drift_proc.set_shader_parameter("particle_size", 0.9)
			_drift_draw.set_shader_parameter("tint", Vector3(tint.r * 1.05, tint.g * 0.86, tint.b * 0.66))
			_drift_draw.set_shader_parameter("opacity", 0.07 * _drift_vis)
			_drift_draw.set_shader_parameter("far_fade", 30.0)
