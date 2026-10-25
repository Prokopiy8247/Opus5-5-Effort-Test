extends Node3D
## Tyre smoke (asphalt), dust/spray (loose surfaces, wet roads) and pooled skid marks for the player car.

const MAX_MARKS: int = 3000
var car: Car
var smoke: Array[GPUParticles3D] = []
var dust: Array[GPUParticles3D] = []
var marks: MultiMesh
var _mark_i: int = 0
var _last_mark: Array[Vector3] = [Vector3.INF, Vector3.INF, Vector3.INF, Vector3.INF]


func _ready() -> void:
	for i in 4:
		smoke.append(_emitter(Color(0.92, 0.92, 0.92, 0.55), 2.2, 60))
		dust.append(_emitter(Color(0.62, 0.5, 0.36, 0.28), 1.4, 28))
	var qm := QuadMesh.new()
	qm.size = Vector2(0.24, 0.6)
	qm.orientation = PlaneMesh.FACE_Y
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.03, 0.03, 0.03, 0.55)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.9
	qm.material = mat
	marks = MultiMesh.new()
	marks.transform_format = MultiMesh.TRANSFORM_3D
	marks.use_colors = true
	marks.mesh = qm
	marks.instance_count = MAX_MARKS
	marks.visible_instance_count = 0
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = marks
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.extra_cull_margin = 16384.0
	add_child(mmi)
	var audio: Node = load("res://scripts/vehicle/car_audio.gd").new()
	audio.name = "CarAudio"
	add_child(audio)
	Game.car_changed.connect(func(c: Node) -> void: car = c as Car)
	car = Game.player as Car


func _emitter(col: Color, life: float, amount: int) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = life
	p.local_coords = false
	p.emitting = false
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 50.0
	pm.initial_velocity_min = 0.5
	pm.initial_velocity_max = 2.0
	pm.gravity = Vector3(0, 0.6, 0)
	pm.damping_min = 0.5
	pm.damping_max = 1.0
	pm.scale_min = 0.8
	pm.scale_max = 1.6
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.4))
	curve.add_point(Vector2(1, 2.2))
	var ct := CurveTexture.new()
	ct.curve = curve
	pm.scale_curve = ct
	var grad := Gradient.new()
	grad.set_color(0, col)
	grad.set_color(1, Color(col.r, col.g, col.b, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = grad
	pm.color_ramp = gt
	p.process_material = pm
	var qm := QuadMesh.new()
	qm.size = Vector2(1.2, 1.2)
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	var tex := GradientTexture2D.new()
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(0.5, 0.0)
	var g2 := Gradient.new()
	g2.set_color(0, Color(1, 1, 1, 1))
	g2.set_color(1, Color(1, 1, 1, 0))
	tex.gradient = g2
	mat.albedo_texture = tex
	qm.material = mat
	p.draw_pass_1 = qm
	add_child(p)
	return p


func _process(_delta: float) -> void:
	var _pf: int = Time.get_ticks_usec()
	_inner_fx(_delta)
	Game.prof_add("fx", _pf)


func _inner_fx(_delta: float) -> void:
	if car == null or not is_instance_valid(car):
		return
	var spd: float = car.linear_velocity.length()
	var wet: float = Game.sky.wet if Game.sky else 0.0
	for i in car.wheels.size():
		var w: Dictionary = car.wheels[i]
		var contact: bool = w.contact
		var loose: bool = Car.LOOSE[w.surface] == 1
		var pos: Vector3 = car.to_global(w.anchor - Vector3(0, w.spring_len + w.radius - 0.1, 0))
		var sm: GPUParticles3D = smoke[i]
		var du: GPUParticles3D = dust[i]
		sm.global_position = pos
		du.global_position = pos
		var slip: float = w.slip
		var s_on: bool = contact and not loose and slip > 0.45 and spd > 3.0 and wet < 0.5
		sm.emitting = s_on
		if s_on:
			sm.amount_ratio = clampf((slip - 0.4) * 1.5, 0.15, 1.0)
		var d_on: bool = contact and ((loose and spd > 6.0) or (wet > 0.5 and spd > 15.0))
		du.emitting = d_on
		if d_on:
			du.amount_ratio = clampf(spd / 30.0 + slip * 0.5, 0.1, 1.0)
		# skid marks
		if contact and (slip > 0.5 or (loose and slip > 0.3)) and spd > 2.0:
			var lp: Vector3 = _last_mark[i]
			if lp == Vector3.INF or lp.distance_to(pos) > 0.5:
				var dir: Vector3 = car.linear_velocity.normalized()
				var n: Vector3 = w.normal if w.has("normal") else Vector3.UP
				var x: Vector3 = n.cross(dir).normalized()
				if x.length() < 0.5:
					x = Vector3.RIGHT
				var z: Vector3 = x.cross(n).normalized()
				var t := Transform3D(Basis(x, n, z), pos + Vector3(0, 0.03, 0))
				marks.set_instance_transform(_mark_i, t)
				var a: float = clampf(slip, 0.3, 1.0)
				marks.set_instance_color(_mark_i, Color(0.04, 0.04, 0.04, a * 0.6) if not loose else Color(0.3, 0.22, 0.14, a * 0.5))
				_mark_i = (_mark_i + 1) % MAX_MARKS
				marks.visible_instance_count = mini(marks.visible_instance_count + 1, MAX_MARKS)
				_last_mark[i] = pos
		else:
			_last_mark[i] = Vector3.INF
