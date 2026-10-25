class_name CarFX
extends Node3D
## Tyre smoke / dust / spray particles per wheel and skid marks (one MultiMesh ring buffer).

const MARKS := 1600
const MARK_STEP := 0.45

var car: Car
var emitters: Array[GPUParticles3D] = []
var mats: Array[ParticleProcessMaterial] = []
var marks: MultiMeshInstance3D
var _mark_i := 0
var _last_mark: Array[Vector3] = []
var _was_marking: Array[bool] = []


func setup(c: Car) -> void:
	car = c
	top_level = true
	global_transform = Transform3D.IDENTITY
	for w in car.wheels:
		var p := GPUParticles3D.new()
		p.amount = 90
		p.lifetime = 1.6
		p.local_coords = false
		p.emitting = false
		p.visibility_aabb = AABB(Vector3(-30, -5, -30), Vector3(60, 25, 60))
		var pm := ParticleProcessMaterial.new()
		pm.direction = Vector3(0, 1, 0)
		pm.spread = 50.0
		pm.initial_velocity_min = 0.5
		pm.initial_velocity_max = 2.5
		pm.gravity = Vector3(0, 0.6, 0)
		pm.damping_min = 1.0
		pm.damping_max = 2.0
		pm.scale_min = 0.8
		pm.scale_max = 2.0
		var curve := CurveTexture.new()
		var cv := Curve.new()
		cv.add_point(Vector2(0, 0.3))
		cv.add_point(Vector2(1, 1.0))
		curve.curve = cv
		pm.scale_curve = curve
		var grad := GradientTexture1D.new()
		var gr := Gradient.new()
		gr.set_color(0, Color(1, 1, 1, 0.55))
		gr.set_color(1, Color(1, 1, 1, 0.0))
		grad.gradient = gr
		pm.color_ramp = grad
		p.process_material = pm
		var q := QuadMesh.new()
		q.size = Vector2(1.2, 1.2)
		var m := StandardMaterial3D.new()
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		m.vertex_color_use_as_albedo = true
		m.albedo_texture = _puff_texture()
		q.material = m
		p.draw_pass_1 = q
		add_child(p)
		emitters.append(p)
		mats.append(pm)
		_last_mark.append(Vector3.INF)
		_was_marking.append(false)
	# skid marks
	marks = MultiMeshInstance3D.new()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var plane := PlaneMesh.new()
	plane.size = Vector2(0.22, 1.0)
	var sm := StandardMaterial3D.new()
	sm.albedo_color = Color(0.02, 0.02, 0.02, 0.55)
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.roughness = 0.9
	plane.material = sm
	mm.mesh = plane
	mm.instance_count = MARKS
	mm.visible_instance_count = 0
	marks.multimesh = mm
	marks.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(marks)


static var _puff: Texture2D

static func _puff_texture() -> Texture2D:
	if _puff:
		return _puff
	var img := Image.create_empty(64, 64, false, Image.FORMAT_RGBA8)
	for y in 64:
		for x in 64:
			var d := Vector2(x - 31.5, y - 31.5).length() / 31.5
			var a := clampf(1.0 - d, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a * a))
	_puff = ImageTexture.create_from_image(img)
	return _puff


func _physics_process(_delta: float) -> void:
	var _t0 := Time.get_ticks_usec()
	_physics_process_inner(_delta)
	Game.prof_add("car_fx", Time.get_ticks_usec() - _t0)


func _physics_process_inner(_delta: float) -> void:
	if car == null or not is_instance_valid(car):
		return
	var mm := marks.multimesh
	for i in car.wheels.size():
		var w := car.wheels[i]
		var em := emitters[i]
		if not w.contact:
			em.emitting = false
			_was_marking[i] = false
			continue
		var surf := Game.surface(w.surface)
		var slip := maxf((w.slip_lat - 1.1) * 0.7, w.slip_long)
		var dust := surf.is_offroad and car.speed > 6.0
		var smoke := not surf.is_offroad and slip > 0.25 and car.speed > 3.0
		var spray := Game.wetness > 0.5 and not surf.is_offroad and car.speed > 12.0
		em.emitting = dust or smoke or spray
		if em.emitting:
			var col := surf.particle_color
			if smoke:
				col = Color(0.92, 0.92, 0.92, 0.6)
			elif spray:
				col = Color(0.8, 0.85, 0.9, 0.35)
			mats[i].color = col
			em.amount_ratio = clampf(maxf(slip, car.speed / 40.0), 0.15, 1.0)
			em.global_position = w.hit_point + Vector3.UP * 0.25
		# skid marks on paved surfaces
		var marking := slip > 0.35 and not surf.is_offroad and car.speed > 2.0
		if surf.is_offroad and car.speed > 4.0:
			marking = slip > 0.2
		if marking:
			var p := w.hit_point + w.hit_normal * 0.025
			if not _was_marking[i] or _last_mark[i] == Vector3.INF:
				_last_mark[i] = p
			var d := p - _last_mark[i]
			if d.length() >= MARK_STEP:
				var mid := (p + _last_mark[i]) * 0.5
				var fwd := d.normalized()
				var right := fwd.cross(w.hit_normal).normalized()
				var basis := Basis(right, w.hit_normal, -fwd) * Basis.from_scale(Vector3(1.0, 1.0, d.length()))
				mm.set_instance_transform(_mark_i, Transform3D(basis, mid))
				_mark_i = (_mark_i + 1) % MARKS
				mm.visible_instance_count = mini(mm.visible_instance_count + 1, MARKS)
				_last_mark[i] = p
		_was_marking[i] = marking
