extends Node3D
## Debug view for fx building blocks: skid segments and one-shot spark / debris bursts.

const SkidMarks := preload("res://scripts/fx/skid_marks.gd")
const FxLib := preload("res://scripts/fx/fx_library.gd")


func _ready() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -30, 0)
	add_child(sun)
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(60, 60)
	mi.mesh = pm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.4, 0.4, 0.42)
	mi.material_override = m
	add_child(mi)
	var cam := Camera3D.new()
	add_child(cam)
	cam.position = Vector3(0, 5, 9)
	cam.look_at(Vector3(0, 0.5, 0), Vector3.UP)
	cam.make_current()
	_go.call_deferred()


func _burst(pos: Vector3, mode: int) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.one_shot = true
	p.emitting = false
	p.explosiveness = 0.92
	p.amount = 48
	p.lifetime = 0.6
	p.process_material = FxLib.spark_process()
	p.draw_pass_1 = FxLib.spark_quad()
	p.material_override = FxLib.spark_material()
	p.local_coords = false
	p.fixed_fps = 0
	p.top_level = true
	p.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD_Y_TO_VELOCITY
	add_child(p)
	for i in 3:
		await get_tree().process_frame
	p.global_transform = Transform3D(Basis.IDENTITY, pos)
	if mode == 0:
		p.restart()
		p.emitting = true
	elif mode == 1:
		p.emitting = true
	else:
		await get_tree().process_frame
		p.restart()
	return p


func _go() -> void:
	var sm := SkidMarks.ensure(self) as SkidMarks
	for i in 20:
		var a := Vector3(-4.0 + i * 0.4, 0.0, -2.0)
		sm.add_segment(a, a + Vector3(0.4, 0, 0), Vector3.UP, 0.3, Color(0.03, 0.03, 0.03), 1.0, 1.0)
	_burst(Vector3(-3, 0.5, 0), 0)
	_burst(Vector3(0, 0.5, 0), 1)
	_burst(Vector3(3, 0.5, 0), 2)
	var d := GPUParticles3D.new()
	d.one_shot = true
	d.emitting = false
	d.explosiveness = 0.92
	d.amount = 16
	d.lifetime = 1.1
	d.process_material = FxLib.debris_process()
	d.draw_pass_1 = FxLib.debris_mesh()
	d.local_coords = false
	d.top_level = true
	add_child(d)
	d.global_position = Vector3(0, 0.6, 2.5)
	d.restart()
	for i in 25:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://qa_output/fx"))
	get_viewport().get_texture().get_image().save_png("res://qa_output/fx/burst_debug.png")
	get_tree().quit(0)
