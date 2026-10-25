class_name SkidMarks
extends MultiMeshInstance3D
## Ring buffer of tyre-mark quads laid at the rear contact patches while sliding.

const COUNT := 1200
var _next := 0
var _last: Array[Vector3] = [Vector3.INF, Vector3.INF]

func _ready() -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var q := PlaneMesh.new(); q.size = Vector2(0.24, 1.0)
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.02, 0.02, 0.02, 0.55)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	q.material = m
	mm.mesh = q
	mm.instance_count = COUNT
	for i in COUNT: mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ZERO), Vector3.ZERO))
	multimesh = mm
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func update_car(car: Car, active: bool) -> void:
	for k in 2:
		var w: Dictionary = car.wheels[2 + k]
		if not active or not w.contact:
			_last[k] = Vector3.INF; continue
		var p: Vector3 = (w.point as Vector3) + (w.normal as Vector3) * 0.03
		if _last[k] == Vector3.INF: _last[k] = p; continue
		var d := p - _last[k]
		var l := d.length()
		if l < 0.6: continue
		var fwd := d / l
		var n: Vector3 = w.normal
		var x := n.cross(fwd).normalized()
		var b := Basis(x, n, x.cross(n))
		multimesh.set_instance_transform(_next, Transform3D(b.scaled(Vector3(1, 1, l)), (p + _last[k]) * 0.5))
		_next = (_next + 1) % COUNT
		_last[k] = p
