extends MultiMeshInstance3D
## Global skid-mark manager ("SkidMarks" under Game.main): one MultiMesh ring buffer of
## ground-aligned quads. Segments fade by age and before their slot is reused.
## Get it with `SkidMarks.ensure(node)` (const SkidMarks := preload("res://scripts/fx/skid_marks.gd")).

const SCRIPT_PATH := "res://scripts/fx/skid_marks.gd"
const SHADER := preload("res://assets/shaders/fx_skid.gdshader")
const NODE_NAME := "SkidMarks"
const CAPACITY := 4000
const SEQ_WRAP := 1048576
## Height above the contact point (m) to avoid z-fighting with the road.
const LIFT := 0.025

var _mm: MultiMesh
var _mat: ShaderMaterial
var _head: int = 0
var _seq: int = 0
var _count: int = 0
var _clock: float = 0.0


## Returns the shared manager, creating it under Game.main (or the current scene in tests).
static func ensure(from: Node) -> Node:
	if from == null or not from.is_inside_tree():
		return null
	var root: Node = Game.main
	if root == null or not is_instance_valid(root) or not root.is_inside_tree():
		root = from.get_tree().current_scene
	if root == null:
		return null
	var n := root.get_node_or_null(NODE_NAME)
	if n == null:
		n = (load(SCRIPT_PATH) as Script).new()
		n.name = NODE_NAME
		root.add_child(n)
	return n


func _init() -> void:
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.use_colors = true
	_mm.use_custom_data = true
	var pm := PlaneMesh.new()
	pm.size = Vector2.ONE
	_mm.mesh = pm
	_mm.instance_count = CAPACITY
	_mm.visible_instance_count = 0
	_mm.custom_aabb = AABB(Vector3(-6000, -1000, -6000), Vector3(12000, 4000, 12000))
	multimesh = _mm
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	_mat.render_priority = -2
	_mat.set_shader_parameter("capacity", float(CAPACITY))
	_mat.set_shader_parameter("seq_wrap", float(SEQ_WRAP))
	material_override = _mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	ignore_occlusion_culling = true
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	top_level = true


func _process(delta: float) -> void:
	_clock += delta
	_mat.set_shader_parameter("now", _clock)


## Lays one quad from `a` to `b` on the ground with the given normal.
## color.rgb = mark colour; alpha_a / alpha_b = opacity at each end (smooth streak start/end).
func add_segment(a: Vector3, b: Vector3, normal: Vector3, width: float, color: Color, alpha_a: float, alpha_b: float) -> void:
	var along := b - a
	var length := along.length()
	if length < 0.02 or (alpha_a <= 0.003 and alpha_b <= 0.003):
		return
	var n := normal.normalized() if normal.length_squared() > 0.01 else Vector3.UP
	var z := along / length
	var x := n.cross(z)
	if x.length_squared() < 1e-6:
		return
	x = x.normalized()
	z = x.cross(n)
	var xf := Transform3D(Basis(x * width, n, z * length), (a + b) * 0.5 + n * LIFT)
	_mm.set_instance_transform(_head, xf)
	_mm.set_instance_color(_head, Color(color.r, color.g, color.b, 1.0))
	_mm.set_instance_custom_data(_head, Color(_clock, float(_seq), clampf(alpha_a, 0.0, 1.0), clampf(alpha_b, 0.0, 1.0)))
	_head = (_head + 1) % CAPACITY
	_seq = (_seq + 1) % SEQ_WRAP
	if _count < CAPACITY:
		_count += 1
		_mm.visible_instance_count = _count
	_mat.set_shader_parameter("head_seq", float(_seq))


func segment_count() -> int:
	return _count


func clear() -> void:
	_count = 0
	_head = 0
	_mm.visible_instance_count = 0
