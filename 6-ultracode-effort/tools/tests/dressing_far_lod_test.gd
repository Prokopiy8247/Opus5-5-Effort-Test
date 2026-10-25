extends Node
## Far-LOD regression test (playtest-3 s11): every tree / hedge far stand-in (generated from its Blender model,
## dressing_nature_meshes.gd far_arrays) must weigh like the model at the ~600 m cross-fade. In the game's own
## lighting, AA and fog it draws a 5 x 5 grid of the model and of the stand-in 600 m away against a pale
## hillside backdrop and compares their integrated contrast ("ink": sum of backdrop minus pixel luminance);
## the ratio is what SPECIES.far_k calibrates. Also saves 60 m model / stand-in / old placeholder sheets.
## Prints FAR_LOD_OK or FAR_LOD_FAIL. -- --shot-dir=res://qa_output/dressing/far_lod

const PropLibrary := preload("res://scripts/world/prop_library.gd")
const Rules := preload("res://scripts/world/dressing_rules.gd")
const Nature := preload("res://scripts/world/dressing_nature_meshes.gd")
const Mats := preload("res://scripts/world/dressing_materials.gd")

const NAMES: Array[String] = ["Tree_Pine_A", "Tree_Pine_B", "Tree_Oak_A", "Tree_Oak_B", "Tree_Birch", "Tree_Poplar", "Tree_Olive", "Tree_Palm", "Hedge"]
const TOLERANCE := 0.15

var out_dir := "res://qa_output/dressing/far_lod"


func _ready() -> void:
	out_dir = QaDirector._arg("shot-dir", out_dir)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	add_child((load("res://scenes/main.tscn") as PackedScene).instantiate())
	_run.call_deferred()


func _frames(n: int) -> void:
	for k in n:
		Mats.set_param(&"wind_strength", 0.0)
		await get_tree().process_frame
	await RenderingServer.frame_post_draw


func _mm(mesh: Mesh, xf: Transform3D, custom: Color, grid: int, spacing: float) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = mesh
	mm.instance_count = grid * grid
	var k := 0
	for j in grid:
		for i in grid:
			var off := Vector3((i - (grid - 1) * 0.5) * spacing, 0.0, (j - (grid - 1) * 0.5) * spacing)
			mm.set_instance_transform(k, Transform3D(Basis(Vector3.UP, k * 2.39) * xf.basis, xf.origin + off))
			mm.set_instance_custom_data(k, custom)
			k += 1
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


func _run() -> void:
	SaveGame.enabled = false
	while Game.main == null or Game.main.is_loading:
		await get_tree().process_frame
	var dn: Node = Game.get_meta(&"dressing", null)
	while dn != null and not bool(dn.get("_started")):
		await get_tree().process_frame
	Game.set_time_of_day(13.0)
	Game.main.car_input.enabled = false
	Game.camera_rig.active = false
	var cam: Camera3D = Game.camera_rig.camera
	var fov0 := cam.fov
	var base := Vector3(0, 40, 1900)
	var backdrop := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(400, 300)
	backdrop.mesh = qm
	var bm := StandardMaterial3D.new()
	bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bm.albedo_color = Color(0.78, 0.8, 0.62)
	backdrop.material_override = bm
	add_child(backdrop)
	var fails := 0
	for dist: float in [60.0, 600.0]:
		for nm in NAMES:
			var bb := PropLibrary.aabb(nm)
			var near_mesh := PropLibrary.mesh(nm)
			var far_mesh: Mesh = Rules.far_meshes[nm]
			# measure without the cross-fade
			Mats.set_mesh_lod(near_mesh, Vector3.ZERO)
			Mats.set_mesh_lod(far_mesh, Vector3.ZERO)
			var g := 1 if dist < 100.0 else 5
			var sp := maxf(bb.size.x, bb.size.z) * 1.3
			var xf := Transform3D(Basis(), base)
			var near := _mm(near_mesh, xf, Color(1, 1, 1, 0.3), g, sp)
			var far := _mm(far_mesh, xf, Color(1, 1, 1, 0.3), g, sp)
			var fam: int = Nature.SPECIES[nm]["far"]
			var w := maxf(bb.size.x, bb.size.z)
			var fit := Vector3(w, bb.end.y, w) if fam != Nature.Far.HEDGE else Vector3(bb.size.x, bb.end.y, bb.size.z)
			var leaf := PropLibrary.leaf_color(nm)
			var old := _mm(PropLibrary.far_mesh(fam), Transform3D(Basis.from_scale(fit), base), Color(leaf.r, leaf.g, leaf.b, 0.3), g, sp)
			var centre := base + Vector3(0, bb.get_center().y, 0)
			cam.fov = rad_to_deg(2.0 * atan(bb.size.y * 0.9 / dist)) if dist < 100.0 else fov0
			cam.global_position = centre + Vector3(0, -dist * 0.15, dist)
			cam.look_at(centre, Vector3.UP)
			backdrop.global_position = centre + Vector3(0, 0, -60.0)
			backdrop.visible = dist > 100.0
			var imgs := {}
			for which: String in ["bg", "near", "far", "old"]:
				var node: Node = {"near": near, "far": far, "old": old}.get(which)
				if node != null:
					add_child(node)
				await _frames(14)
				imgs[which] = get_viewport().get_texture().get_image()
				if node != null:
					remove_child(node)
			var st := {}
			var line := "%s %d m" % [nm, int(dist)]
			for which: String in ["near", "far", "old"]:
				st[which] = _stats(imgs[which], imgs["bg"], 360 if dist < 100.0 else 120, 2 if dist < 100.0 else 1)
				var c: Color = st[which][1]
				line += " | %s px=%d mean=(%d,%d,%d) ink=%.1f" % [which, st[which][0], c.r8, c.g8, c.b8, st[which][2]]
			if dist > 100.0:
				var r: float = float(st["far"][2]) / maxf(float(st["near"][2]), 0.001)
				var ok := absf(r - 1.0) <= TOLERANCE
				line += " | far/model ink %.2f (old %.2f) %s" % [r, float(st["old"][2]) / maxf(float(st["near"][2]), 0.001), "ok" if ok else "FAIL"]
				if not ok:
					fails += 1
			else:
				var a: Image = imgs["near"]
				var wd := a.get_width()
				var sheet := Image.create(wd * 3, a.get_height(), false, a.get_format())
				sheet.blit_rect(a, Rect2i(0, 0, wd, a.get_height()), Vector2i(0, 0))
				sheet.blit_rect(imgs["far"], Rect2i(0, 0, wd, a.get_height()), Vector2i(wd, 0))
				sheet.blit_rect(imgs["old"], Rect2i(0, 0, wd, a.get_height()), Vector2i(wd * 2, 0))
				sheet.resize(wd, a.get_height() / 3)
				sheet.save_png(out_dir.path_join("%s_model_far_old.png" % nm))
			print("[far_lod] ", line)
			near.queue_free()
			far.queue_free()
			old.queue_free()
	dn.call("_apply_lod")
	print("FAR_LOD_OK" if fails == 0 else "FAR_LOD_FAIL %d" % fails)
	get_tree().quit(0 if fails == 0 else 1)


## [pixel count, mean colour, ink] over the centre crop: pixels that differ from the backdrop frame, and the
## sum of backdrop minus pixel luminance.
func _stats(img: Image, bg: Image, half: int, step: int) -> Array:
	var n := 0
	var sum := Color(0, 0, 0, 0)
	var ink := 0.0
	var cx := img.get_width() / 2
	var cy := img.get_height() / 2
	for y in range(maxi(cy - half, 0), mini(cy + half, img.get_height()), step):
		for x in range(maxi(cx - half, 0), mini(cx + half, img.get_width()), step):
			var c := img.get_pixel(x, y)
			var d := bg.get_pixel(x, y)
			ink += (d.get_luminance() - c.get_luminance()) * step * step
			if absf(c.r - d.r) + absf(c.g - d.g) + absf(c.b - d.b) > 0.04:
				n += 1
				sum += c
	return [n * step * step, sum / maxf(n, 1), ink]
