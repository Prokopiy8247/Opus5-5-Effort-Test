class_name CarFX
extends Node3D
## Wheel effects for the player car: tyre smoke when sliding on paved surfaces, surface-coloured
## dust/spray on loose ground, and skid marks (a ring buffer of ground-aligned quads in one
## MultiMesh, so adding a mark costs one instance update).

const MARKS := 1600
const MARK_STEP := 0.45

var car: CarController
var _emitters: Array[GPUParticles3D] = []
var _marks: MultiMeshInstance3D
var _mark_next := 0
var _last_mark: Array[Vector3] = []


func setup(c: CarController) -> void:
	car = c
	top_level = true
	for i in c.wheels.size():
		var e := _make_emitter()
		add_child(e)
		_emitters.append(e)
		_last_mark.append(Vector3.INF)
	_marks = MultiMeshInstance3D.new()
	_marks.top_level = true
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var pm := PlaneMesh.new()
	pm.size = Vector2(1, 1)
	mm.mesh = pm
	mm.instance_count = MARKS
	mm.visible_instance_count = 0
	_marks.multimesh = mm
	_marks.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.03, 0.03, 0.03, 0.55)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.roughness = 0.9
	m.render_priority = -1
	_marks.material_override = m
	add_child(_marks)


func _make_emitter() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = 48
	p.lifetime = 1.6
	p.local_coords = false
	p.emitting = false
	p.visibility_aabb = AABB(Vector3(-20, -5, -20), Vector3(40, 20, 40))
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 55.0
	pm.initial_velocity_min = 0.6
	pm.initial_velocity_max = 2.2
	pm.gravity = Vector3(0, 0.6, 0)
	pm.damping_min = 1.5
	pm.damping_max = 2.5
	pm.scale_min = 0.8
	pm.scale_max = 1.4
	var sc := Curve.new()
	sc.add_point(Vector2(0, 0.35))
	sc.add_point(Vector2(1, 1.0))
	var sct := CurveTexture.new()
	sct.curve = sc
	pm.scale_curve = sct
	var grad := Gradient.new()
	grad.set_color(0, Color(1, 1, 1, 0.55))
	grad.set_color(1, Color(1, 1, 1, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = grad
	pm.color_ramp = gt
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(1.6, 1.6)
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX  # lit, so dust darkens at night
	mat.proximity_fade_enabled = true  # soft particles: no hard line where a puff meets the road
	mat.proximity_fade_distance = 0.8
	var tex := GradientTexture2D.new()
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	var g2 := Gradient.new()
	g2.set_color(0, Color(1, 1, 1, 1))
	g2.set_color(1, Color(1, 1, 1, 0))
	tex.gradient = g2
	tex.width = 64
	tex.height = 64
	mat.albedo_texture = tex
	q.material = mat
	p.draw_pass_1 = q
	return p


func _physics_process(_delta: float) -> void:
	if car == null or not is_instance_valid(car):
		return
	var xf := car.global_transform
	var vel := car.linear_velocity
	for i in car.wheels.size():
		var w := car.wheels[i]
		var e := _emitters[i]
		var smoke := 0.0
		var col := Color(0.85, 0.85, 0.85)
		if w.contact and w.surface != null:
			var skid := clampf(float(w.skid), 0.0, 1.0)
			if w.surface.paved:
				smoke = clampf((skid - 0.3) * 1.6, 0.0, 1.0) * clampf(car.speed_abs / 4.0, 0.3, 1.0)
				if absf(w.slip_ratio) > 0.4 and absf(w.omega * w.radius) > 4.0:
					smoke = maxf(smoke, 0.9)  # burnout
			else:
				smoke = clampf(car.speed_abs / 22.0, 0.0, 1.0) * 0.6 * w.surface.particle_amount + skid * 0.5
				if w.surface.kind == SurfaceData.Kind.GRASS:
					smoke *= 0.3  # grass throws clippings, not a dust cloud
				col = w.surface.particle_color
			col.a = 1.0
			_mark(i, w, skid)
		else:
			_last_mark[i] = Vector3.INF
		if smoke > 0.05:
			e.global_position = w.point + Vector3.UP * 0.3
			(e.process_material as ParticleProcessMaterial).color = col
			(e.process_material as ParticleProcessMaterial).initial_velocity_max = 1.0 + vel.length() * 0.05
			e.amount_ratio = clampf(smoke, 0.05, 1.0)
			e.emitting = true
		else:
			e.emitting = false
	if xf.origin.y < -500.0:
		set_physics_process(false)


func _mark(i: int, w, skid: float) -> void:
	var paved: bool = w.surface.paved
	if skid < (0.35 if paved else 0.6):
		_last_mark[i] = Vector3.INF
		return
	var p: Vector3 = w.point + (w.normal as Vector3) * 0.025
	var last := _last_mark[i]
	if last == Vector3.INF:
		_last_mark[i] = p
		return
	var d := p - last
	var ln := d.length()
	if ln < MARK_STEP:
		return
	if ln > 3.0:
		_last_mark[i] = p
		return
	var n: Vector3 = (w.normal as Vector3).normalized()
	var along := d / ln
	var side := n.cross(along).normalized()
	var width := 0.22 if paved else 0.3
	var basis := Basis(side * width, n, along * (ln + 0.05))
	var mm := _marks.multimesh
	mm.set_instance_transform(_mark_next, Transform3D(basis, (p + last) * 0.5))
	_mark_next = (_mark_next + 1) % MARKS
	mm.visible_instance_count = mini(mm.visible_instance_count + 1, MARKS)
	_last_mark[i] = p


func clear_marks() -> void:
	if _marks != null:
		_marks.multimesh.visible_instance_count = 0
		_mark_next = 0
