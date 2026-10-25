extends Node3D
## Storm lightning: random strikes 0.7-2.6 km from the camera. Each strike builds a jagged, branching
## bolt (camera-facing ribbons, additive HDR so it blooms), plays a multi-pulse flash on a shadowless
## directional "flash" light and reports the flash level / direction for the sky and ambient.

signal struck(strength: float)

const BOLT_SHADER_CODE := """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;
uniform vec3 color = vec3(0.8, 0.86, 1.0);
uniform float energy = 0.0;
void fragment() {
	float x = 1.0 - abs(UV.x * 2.0 - 1.0);
	ALBEDO = color * energy * (x * x * 0.85 + step(0.72, x) * 2.5) * COLOR.a;
}
"""

## Average strikes per minute (0 = none).
var rate_per_minute: float = 0.0
## 0 outdoors .. 1 inside a tunnel (the flash light must not reach the tube).
var indoor: float = 0.0
## Multiplier for the flash light's energy (the environment lowers it at night against the exposure boost).
var light_scale: float = 1.0
## Current flash brightness (0..~1) and the direction from the camera towards the strike.
var flash: float = 0.0
var flash_dir: Vector3 = Vector3(0, 0.4, 1).normalized()

var _timer: float = 6.0
var _t: float = 99.0
var _pulses: Array[Vector2] = []
var _strength: float = 1.0
var _bolt: MeshInstance3D
var _bolt_mat: ShaderMaterial
var _light: DirectionalLight3D
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_rng.randomize()
	var sh := Shader.new()
	sh.code = BOLT_SHADER_CODE
	_bolt_mat = ShaderMaterial.new()
	_bolt_mat.shader = sh
	_bolt = MeshInstance3D.new()
	_bolt.name = "Bolt"
	_bolt.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_bolt.material_override = _bolt_mat
	_bolt.visible = false
	_bolt.extra_cull_margin = 4000.0
	add_child(_bolt)
	_light = DirectionalLight3D.new()
	_light.name = "FlashLight"
	_light.shadow_enabled = false
	_light.light_color = Color(0.78, 0.84, 1.0)
	_light.light_energy = 0.0
	_light.light_specular = 0.8
	_light.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	_light.visible = false
	add_child(_light)


func update(cam_pos: Vector3, delta: float) -> void:
	if rate_per_minute > 0.01:
		_timer -= delta
		if _timer <= 0.0:
			strike(cam_pos)
			_timer = clampf(-log(maxf(_rng.randf(), 0.001)) * 60.0 / rate_per_minute, 3.5, 45.0)
	else:
		_timer = maxf(_timer, 4.0)
	_t += delta
	flash = _eval(_t) * _strength
	var on := flash > 0.01
	_bolt.visible = flash > 0.04
	if _bolt.visible:
		_bolt_mat.set_shader_parameter("energy", 6.0 + flash * 30.0)
	_light.visible = on and indoor < 0.98
	_light.light_energy = flash * 1.6 * light_scale * (1.0 - indoor)


func _eval(t: float) -> float:
	if _pulses.is_empty() or t > _pulses[_pulses.size() - 1].x + 0.2:
		return 0.0
	var v := 0.0
	for p in _pulses:
		if t >= p.x:
			v = maxf(v, p.y * exp(-(t - p.x) * 16.0))
	return v


## Triggers a strike now. `dir` (optional, horizontal) forces where it lands relative to the camera.
func strike(cam_pos: Vector3, dir := Vector3.ZERO, distance := -1.0) -> void:
	if dir == Vector3.ZERO:
		var a := _rng.randf() * TAU
		dir = Vector3(sin(a), 0.0, cos(a))
	dir = Vector3(dir.x, 0.0, dir.z).normalized()
	var dist := distance if distance > 0.0 else _rng.randf_range(700.0, 2600.0)
	var base := cam_pos + dir * dist
	var ground := base.y
	if Game.world is World:
		ground = (Game.world as World).height_at(base.x, base.z)
	var top_y := maxf(ground + 520.0, 760.0)
	_build_bolt(Vector3(base.x, top_y, base.z), ground, cam_pos)
	_strength = clampf(1.15 - (dist - 700.0) / 2600.0, 0.3, 1.0)
	flash_dir = (Vector3(base.x, top_y * 0.6, base.z) - cam_pos).normalized()
	var from := Vector3(base.x, top_y, base.z)
	_light.basis = Basis.looking_at((cam_pos - from).normalized(), Vector3.UP if absf((cam_pos - from).normalized().y) < 0.98 else Vector3.FORWARD)
	_t = 0.0
	_pulses.clear()
	var t := 0.0
	var n := _rng.randi_range(2, 4)
	for i in n:
		_pulses.append(Vector2(t, 1.0 if i == 0 else _rng.randf_range(0.45, 0.95)))
		t += _rng.randf_range(0.06, 0.16)
	struck.emit(_strength)


func _build_bolt(top: Vector3, ground: float, cam: Vector3) -> void:
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	var path := _jagged(top, Vector3(top.x, ground, top.z), 28, 24.0)
	_ribbon(path, 3.2, 1.0, cam, verts, uvs, cols, idx)
	_ribbon(path, 16.0, 0.12, cam, verts, uvs, cols, idx)
	for b in _rng.randi_range(2, 4):
		var i0 := _rng.randi_range(3, path.size() / 2)
		var start := path[i0]
		var drop := (start.y - ground) * _rng.randf_range(0.25, 0.5)
		var side := Vector3(_rng.randf_range(-1.0, 1.0), 0.0, _rng.randf_range(-1.0, 1.0)).normalized() * drop * 0.6
		var br := _jagged(start, start + side + Vector3(0, -drop, 0), 10, 9.0)
		_ribbon(br, 1.8, 0.55, cam, verts, uvs, cols, idx)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_INDEX] = idx
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_bolt.mesh = am


func _jagged(a: Vector3, b: Vector3, segs: int, spread: float) -> PackedVector3Array:
	var out := PackedVector3Array()
	var off := Vector3.ZERO
	for i in segs + 1:
		var t := float(i) / segs
		if i > 0 and i < segs:
			off += Vector3(_rng.randfn(0.0, spread), 0.0, _rng.randfn(0.0, spread))
			off *= 0.8
		var p := a.lerp(b, t) + off * (1.0 - absf(t * 2.0 - 1.0) * 0.3)
		if i == segs:
			p = b + Vector3(off.x, 0.0, off.z) * 0.2
		out.append(p)
	return out


func _ribbon(path: PackedVector3Array, width: float, alpha: float, cam: Vector3, verts: PackedVector3Array,
		uvs: PackedVector2Array, cols: PackedColorArray, idx: PackedInt32Array) -> void:
	for i in path.size() - 1:
		var a := path[i]
		var b := path[i + 1]
		var side := (b - a).cross(cam - a).normalized() * width * 0.5
		var k := verts.size()
		verts.append_array([a - side, a + side, b - side, b + side])
		uvs.append_array([Vector2(0, 0), Vector2(1, 0), Vector2(0, 1), Vector2(1, 1)])
		for j in 4:
			cols.append(Color(1, 1, 1, alpha))
		idx.append_array([k, k + 1, k + 2, k + 1, k + 3, k + 2])
