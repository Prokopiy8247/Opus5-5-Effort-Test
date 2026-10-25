class_name SkidManager
extends MultiMeshInstance3D
## Global ring buffer of tyre skid-mark segments (one MultiMesh instance per segment).

const CAPACITY := 3000

var _next: int = 0
var _count: int = 0


func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var quad := QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)
	quad.orientation = PlaneMesh.FACE_Y
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = Color(1, 1, 1, 1)
	mat.roughness = 0.95
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	mat.render_priority = -1
	quad.material = mat
	mm.mesh = quad
	mm.instance_count = CAPACITY
	mm.visible_instance_count = 0
	multimesh = mm
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	name = "SkidMarks"


func add_segment(a: Vector3, b: Vector3, normal: Vector3, width: float, color: Color) -> void:
	var d := b - a
	var length := d.length()
	if length < 0.05 or length > 4.0:
		return
	var fwd := d / length
	var right := fwd.cross(normal).normalized()
	var up := right.cross(fwd).normalized()
	var basis := Basis(right * width, up, fwd * (length + 0.04))
	var t := Transform3D(basis, (a + b) * 0.5 + normal * 0.025)
	multimesh.set_instance_transform(_next, t)
	multimesh.set_instance_color(_next, color)
	_next = (_next + 1) % CAPACITY
	_count = mini(_count + 1, CAPACITY)
	multimesh.visible_instance_count = _count


func clear() -> void:
	_next = 0
	_count = 0
	multimesh.visible_instance_count = 0
