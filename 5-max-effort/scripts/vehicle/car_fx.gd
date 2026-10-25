class_name CarFx
extends Node
## Tyre smoke / dust / gravel / snow particles per wheel, wet-road spray, skid marks and
## exhaust backfire flames for one car.

var car: CarController
var skids: SkidManager
var _emitters: Array[GPUParticles3D] = []
var _flames: Array[GPUParticles3D] = []
var _last_skid: Array[Vector3] = [Vector3.INF, Vector3.INF, Vector3.INF, Vector3.INF]
var _mat: ParticleProcessMaterial
var _surface_color: Color = Color(0.8, 0.8, 0.8, 0.5)
var _pop_seen: bool = false

static var _smoke_draw: QuadMesh
static var _flame_draw: QuadMesh


static func _soft_texture() -> Texture2D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 64
	tex.height = 64
	return tex


static func _draw_meshes() -> void:
	if _smoke_draw != null:
		return
	_smoke_draw = QuadMesh.new()
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = _soft_texture()
	m.proximity_fade_enabled = true
	m.proximity_fade_distance = 0.6
	_smoke_draw.material = m
	_flame_draw = QuadMesh.new()
	_flame_draw.size = Vector2(0.25, 0.25)
	var f := StandardMaterial3D.new()
	f.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	f.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	f.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	f.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	f.vertex_color_use_as_albedo = true
	f.albedo_texture = _soft_texture()
	_flame_draw.material = f


func setup(c: CarController, skid_manager: SkidManager) -> void:
	car = c
	skids = skid_manager
	_draw_meshes()
	_mat = ParticleProcessMaterial.new()
	_mat.direction = Vector3(0, 0.6, 0.4)
	_mat.spread = 35.0
	_mat.initial_velocity_min = 0.5
	_mat.initial_velocity_max = 2.0
	_mat.gravity = Vector3(0, 0.35, 0)
	_mat.damping_min = 0.8
	_mat.damping_max = 1.6
	_mat.scale_min = 0.6
	_mat.scale_max = 1.1
	var sc := Curve.new()
	sc.add_point(Vector2(0, 0.5))
	sc.add_point(Vector2(1, 3.2))
	var sct := CurveTexture.new()
	sct.curve = sc
	_mat.scale_curve = sct
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1, 1, 1, 0.55))
	ramp.set_color(1, Color(1, 1, 1, 0.0))
	var rt := GradientTexture1D.new()
	rt.gradient = ramp
	_mat.color_ramp = rt
	_mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	_mat.emission_sphere_radius = 0.18
	for w in car.wheels:
		var p := GPUParticles3D.new()
		p.amount = 48
		p.lifetime = 2.0
		p.local_coords = false
		p.process_material = _mat
		p.draw_pass_1 = _smoke_draw
		p.amount_ratio = 0.0
		p.emitting = true
		p.visibility_aabb = AABB(Vector3(-20, -5, -20), Vector3(40, 20, 40))
		p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		p.position = w.center_rest - Vector3(0, w.radius * 0.8, 0)
		car.add_child(p)
		_emitters.append(p)
	var points: Dictionary = car.get_meta("points", {})
	for key in ["FX_Exhaust_L", "FX_Exhaust_R"]:
		if not points.has(key):
			continue
		var fm := ParticleProcessMaterial.new()
		fm.direction = Vector3(0, 0, 1)
		fm.spread = 12.0
		fm.initial_velocity_min = 3.0
		fm.initial_velocity_max = 6.0
		fm.gravity = Vector3.ZERO
		var fr := Gradient.new()
		fr.set_color(0, Color(1.0, 0.85, 0.4, 1.0))
		fr.set_color(1, Color(1.0, 0.25, 0.05, 0.0))
		var ft := GradientTexture1D.new()
		ft.gradient = fr
		fm.color_ramp = ft
		var fl := GPUParticles3D.new()
		fl.amount = 10
		fl.lifetime = 0.12
		fl.one_shot = true
		fl.explosiveness = 0.9
		fl.local_coords = true
		fl.process_material = fm
		fl.draw_pass_1 = _flame_draw
		fl.emitting = false
		fl.position = (points[key] as Transform3D).origin
		car.add_child(fl)
		_flames.append(fl)


func _process(_delta: float) -> void:
	if car == null or not is_instance_valid(car):
		return
	var speed := car.linear_velocity.length()
	var wet := car.wetness
	var dominant := -1
	for i in car.wheels.size():
		var w := car.wheels[i]
		var p := _emitters[i]
		if not w.contact:
			p.amount_ratio = 0.0
			_last_skid[i] = Vector3.INF
			continue
		var sdef := Surfaces.get_def(w.surface)
		var slip := smoothstep(1.0, 2.2, w.slip)
		var amount := 0.0
		if sdef.particle == 0:
			amount = slip * clampf(speed / 8.0, 0.0, 1.0)
			if wet > 0.3 and speed > 15.0 and not w.front:
				amount = maxf(amount, wet * clampf((speed - 15.0) / 30.0, 0.0, 0.7))
				dominant = 99
		else:
			amount = clampf(speed / 22.0, 0.0, 0.8) * 0.6 + slip * 0.6
			if w.front:
				amount *= 0.5
		p.amount_ratio = clampf(amount, 0.0, 1.0)
		if dominant < 0 or sdef.particle != 0:
			dominant = w.surface
		# skid marks
		if skids != null and sdef.skidmarks and (slip > 0.15 or (sdef.particle != 0 and speed > 3.0)):
			var pt := w.point
			if _last_skid[i] == Vector3.INF:
				_last_skid[i] = pt
			elif pt.distance_to(_last_skid[i]) > 0.35:
				var col := sdef.skid_color
				if sdef.particle != 0:
					col = Color(sdef.dust_color.r * 0.55, sdef.dust_color.g * 0.5, sdef.dust_color.b * 0.45, 0.55)
				else:
					col.a = clampf(0.25 + slip * 0.6, 0.0, 0.85)
				skids.add_segment(_last_skid[i], pt, w.normal, w.width * 0.85, col)
				_last_skid[i] = pt
		else:
			_last_skid[i] = Vector3.INF
	# tint particles by the dominant surface
	var target := Color(0.85, 0.85, 0.85, 1.0)
	if dominant == 99:
		target = Color(0.9, 0.92, 0.95, 0.6)
	elif dominant >= 0:
		var sd := Surfaces.get_def(dominant)
		if sd.particle != 0:
			target = Color(sd.dust_color.r, sd.dust_color.g, sd.dust_color.b, 1.0)
	if not _surface_color.is_equal_approx(target):
		_surface_color = target
		_mat.color = target
	# exhaust flames
	if car.exhaust_pop_signal > 0.9:
		if not _pop_seen:
			for f in _flames:
				f.restart()
			_pop_seen = true
	else:
		_pop_seen = false
