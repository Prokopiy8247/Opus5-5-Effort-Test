extends RefCounted
## Procedural festival props for road activities: inflatable arches, speed-trap gantries, danger signs, crest
## markers, light curtains, floating labels and the Festival Flag. Meshes and materials are cached.
## Gate local space: +X = right of travel, +Y = up, -Z = travel direction (the driver approaches from +Z).
## Blender kit props are used through res://scripts/world/prop_library.gd when it exists and returns a real
## (non-placeholder) asset: Speed_Trap_Camera, Sign_Danger_Jump, Checkpoint_Arch.

const ARCH_SHADER := preload("res://assets/shaders/activity_inflatable.gdshader")
const CURTAIN_SHADER := preload("res://assets/shaders/activity_curtain.gdshader")
const SIGN_SHADER := preload("res://assets/shaders/activity_sign.gdshader")
const FLAG_SHADER := preload("res://assets/shaders/activity_flag.gdshader")
const GLOW_SHADER := preload("res://assets/shaders/activity_glow.gdshader")
const RAMP_SHADER := preload("res://assets/shaders/activity_ramp.gdshader")
const PROP_LIBRARY := "res://scripts/world/prop_library.gd"

const KIND_COLORS := {
	&"speed_trap": Color(1.0, 0.44, 0.06), &"speed_zone": Color(1.0, 0.78, 0.06), &"drift": Color(0.95, 0.16, 0.68),
	&"jump": Color(0.94, 0.14, 0.12), &"race": Color(0.13, 0.42, 1.0), &"time_trial": Color(0.0, 0.76, 0.74),
	&"collectible": Color(1.0, 0.74, 0.16),
}
const GATE_RANGE := 1500.0
const CURTAIN_RANGE := 650.0
const TEXT_RANGE := 280.0
const LABEL_RANGE := 340.0
const LEG_DEPTH := 2.5

static var _meshes: Dictionary = {}
static var _mats: Dictionary = {}
static var _prop_script: Script = null
static var _prop_checked: bool = false
static var _prop_has_check: bool = false


static func color(kind: StringName) -> Color:
	return KIND_COLORS.get(kind, Color(0.9, 0.9, 0.9))


static func gate_height(hw: float) -> float:
	return clampf(4.4 + hw * 0.32, 6.2, 8.4)


## style: &"arch", &"checkpoint", &"gantry", &"sign", &"ramp_warn" (ramp warning for the reverse direction),
## &"crest". Meta "curtain" -> MeshInstance3D when present, "glow" -> GeometryInstance3D carrying the
## per-instance `glow` parameter.
static func build(style: StringName, kind: StringName, hw: float, banner: String) -> Node3D:
	match style:
		&"arch":
			return _arch(kind, hw, banner, false)
		&"checkpoint":
			return _arch(kind, hw, banner, true)
		&"gantry":
			return _gantry(kind, hw, banner)
		&"sign":
			return _danger_sign(kind, hw, "DANGER SIGN")
		&"ramp_warn":
			return _danger_sign(kind, hw, "RAMP AHEAD")
		&"crest":
			return _crest_markers(kind, hw)
	return Node3D.new()


# ------------------------------------------------------------------ gates

static func _arch(kind: StringName, hw: float, banner: String, small: bool) -> Node3D:
	var root := Node3D.new()
	root.name = "Gate"
	var h := gate_height(hw) * (0.92 if small else 1.0)
	var tube := 0.5 if small else 0.62
	var kit := _prop("Checkpoint_Arch") if small else null
	if kit != null:
		var ab := _node_aabb(kit)
		if ab.size.x > 0.5:
			kit.scale = Vector3((2.0 * hw + 1.0) / ab.size.x, 1.0, 1.0)
		root.add_child(kit)
	else:
		var arch := MeshInstance3D.new()
		arch.name = "Arch"
		arch.mesh = arch_mesh(hw, h, tube)
		arch.material_override = _inflatable_mat(kind)
		_ranged(arch, GATE_RANGE)
		root.add_child(arch)
		root.set_meta(&"glow", arch)
		for side: float in [-1.0, 1.0]:
			var bag := MeshInstance3D.new()
			bag.mesh = _box_mesh(Vector3(1.6, 0.5, 1.6))
			bag.material_override = _plain_mat(Color(0.13, 0.14, 0.17), 0.8)
			bag.position = Vector3(side * hw, 0.12, 0.0)
			_ranged(bag, 500.0)
			root.add_child(bag)
	if banner != "":
		_add_banner(root, kind, banner, hw, h - tube - 0.1, 1.0 if small else 1.25, tube)
	_add_curtain(root, kind, hw - tube * 0.8, h - tube - 0.2)
	return root


static func _gantry(kind: StringName, hw: float, banner: String) -> Node3D:
	var root := Node3D.new()
	root.name = "Gantry"
	var h := gate_height(hw)
	var col := color(kind)
	var post_len := h + LEG_DEPTH
	for side: float in [-1.0, 1.0]:
		var post := MeshInstance3D.new()
		post.mesh = _box_mesh(Vector3(0.45, post_len, 0.45))
		post.material_override = _metal_mat(col)
		post.position = Vector3(side * hw, post_len * 0.5 - LEG_DEPTH, 0.0)
		_ranged(post, GATE_RANGE)
		root.add_child(post)
		var foot := MeshInstance3D.new()
		foot.mesh = _box_mesh(Vector3(1.1, 0.35, 1.1))
		foot.material_override = _plain_mat(Color(0.55, 0.55, 0.56), 0.9)
		foot.position = Vector3(side * hw, 0.05, 0.0)
		_ranged(foot, 500.0)
		root.add_child(foot)
	var beam := MeshInstance3D.new()
	beam.mesh = _box_mesh(Vector3(2.0 * hw + 0.9, 0.6, 0.7))
	beam.material_override = _plain_mat(Color(0.12, 0.13, 0.16), 0.5)
	beam.position = Vector3(0.0, h, 0.0)
	_ranged(beam, GATE_RANGE)
	root.add_child(beam)
	var stripe := MeshInstance3D.new()
	stripe.mesh = _box_mesh(Vector3(2.0 * hw + 0.92, 0.16, 0.72))
	stripe.material_override = _glow_box_mat(col)
	stripe.position = Vector3(0.0, h + 0.2, 0.0)
	_ranged(stripe, GATE_RANGE)
	root.add_child(stripe)
	root.set_meta(&"glow", stripe)
	var kit := _prop("Speed_Trap_Camera")
	if kit != null:
		kit.position = Vector3(hw + 1.6, 0.0, 0.0)
		root.add_child(kit)
	else:
		for face: float in [1.0, -1.0]:
			_add_camera(root, Vector3(face * 1.1, h + 0.62, 0.0), face)
	if banner != "":
		_add_banner(root, kind, banner, hw, h - 0.35, 1.15, 0.3)
	_add_curtain(root, kind, hw - 0.3, h - 0.4)
	return root


static func _add_camera(root: Node3D, at: Vector3, face: float) -> void:
	var cam := Node3D.new()
	cam.position = at
	if face < 0.0:
		cam.rotation.y = PI
	root.add_child(cam)
	var body := MeshInstance3D.new()
	body.mesh = _box_mesh(Vector3(0.55, 0.45, 0.95))
	body.material_override = _plain_mat(Color(0.86, 0.87, 0.9), 0.35)
	cam.add_child(body)
	var hood := MeshInstance3D.new()
	hood.mesh = _box_mesh(Vector3(0.65, 0.08, 1.1))
	hood.material_override = _plain_mat(Color(0.12, 0.13, 0.16), 0.5)
	hood.position = Vector3(0, 0.27, 0.05)
	cam.add_child(hood)
	var lens := MeshInstance3D.new()
	lens.mesh = _cyl_mesh(0.15, 0.15, 0.12)
	lens.material_override = _plain_mat(Color(0.03, 0.05, 0.08), 0.1)
	lens.rotation.x = PI * 0.5
	lens.position = Vector3(0, 0, 0.52)
	cam.add_child(lens)
	var tally := MeshInstance3D.new()
	tally.mesh = _box_mesh(Vector3(0.1, 0.1, 0.05))
	tally.material_override = _glow_box_mat(Color(1.0, 0.15, 0.1))
	tally.position = Vector3(0.18, 0.12, 0.48)
	cam.add_child(tally)
	for c in cam.get_children():
		_ranged(c as GeometryInstance3D, 400.0)


static func _danger_sign(kind: StringName, hw: float, plate_text: String) -> Node3D:
	var root := Node3D.new()
	root.name = "DangerSign"
	var at := Vector3(hw + 1.9, 0.0, 0.0)
	var kit := _prop("Sign_Danger_Jump")
	if kit != null:
		kit.position = at
		root.add_child(kit)
		return root
	var post_len := 4.2 + LEG_DEPTH
	for dx: float in [-1.15, 1.15]:
		var post := MeshInstance3D.new()
		post.mesh = _cyl_mesh(0.08, 0.08, post_len)
		post.material_override = _metal_mat(Color(0.75, 0.76, 0.78))
		post.position = at + Vector3(dx, post_len * 0.5 - LEG_DEPTH, -0.08)
		_ranged(post, 900.0)
		root.add_child(post)
	var back := MeshInstance3D.new()
	back.mesh = _box_mesh(Vector3(3.5, 2.45, 0.1))
	back.material_override = _plain_mat(Color(0.2, 0.21, 0.23), 0.6)
	back.position = at + Vector3(0.0, 3.0, 0.0)
	_ranged(back, 900.0)
	root.add_child(back)
	var face := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(3.4, 2.35)
	face.mesh = qm
	var mat := ShaderMaterial.new()
	mat.shader = SIGN_SHADER
	mat.set_shader_parameter("frame_color", color(kind))
	mat.set_shader_parameter("aspect", qm.size.x / qm.size.y)
	face.material_override = mat
	face.position = at + Vector3(0.0, 3.0, 0.056)
	_ranged(face, 900.0)
	root.add_child(face)
	var plate := MeshInstance3D.new()
	plate.mesh = _box_mesh(Vector3(3.5, 0.62, 0.1))
	plate.material_override = _glow_box_mat(color(kind))
	plate.position = at + Vector3(0.0, 1.45, 0.0)
	_ranged(plate, 900.0)
	root.add_child(plate)
	root.set_meta(&"glow", plate)
	var txt := _text(plate_text, 0.36, Color.WHITE)
	txt.position = at + Vector3(0.0, 1.45, 0.06)
	root.add_child(txt)
	return root


static func _crest_markers(kind: StringName, hw: float) -> Node3D:
	var root := Node3D.new()
	root.name = "CrestMarkers"
	var col := color(kind)
	for side: float in [-1.0, 1.0]:
		for k in 4:
			var seg := MeshInstance3D.new()
			seg.mesh = _cyl_mesh(0.11, 0.11, 0.42)
			seg.material_override = _plain_mat(col if k % 2 == 0 else Color(0.96, 0.96, 0.94), 0.5)
			seg.position = Vector3(side * (hw + 0.6), 0.21 + k * 0.42, 0.0)
			_ranged(seg, 600.0)
			root.add_child(seg)
		var pennant := MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = Vector2(0.9, 0.55)
		pennant.mesh = qm
		pennant.material_override = _glow_box_mat(col)
		pennant.position = Vector3(side * (hw + 0.6) - side * 0.45, 1.5, 0.0)
		pennant.rotation.y = PI * 0.5
		_ranged(pennant, 600.0)
		root.add_child(pennant)
	return root


static func _add_banner(root: Node3D, kind: StringName, text: String, hw: float, top: float, bh: float, tube: float) -> void:
	var bw := minf(2.0 * hw - 2.0 * tube - 1.2, 3.2 + text.length() * 0.62)
	var board := MeshInstance3D.new()
	board.name = "Banner"
	board.mesh = _box_mesh(Vector3(bw, bh, 0.14))
	board.material_override = _banner_mat(kind)
	board.position = Vector3(0.0, top - bh * 0.5, 0.0)
	_ranged(board, GATE_RANGE)
	root.add_child(board)
	var trim := MeshInstance3D.new()
	trim.mesh = _box_mesh(Vector3(bw + 0.12, 0.1, 0.16))
	trim.material_override = _glow_box_mat(color(kind))
	trim.position = Vector3(0.0, top - bh - 0.02, 0.0)
	_ranged(trim, 900.0)
	root.add_child(trim)
	for face: float in [1.0, -1.0]:
		var lb := _text(text, bh * 0.56, Color.WHITE)
		lb.position = board.position + Vector3(0.0, 0.0, 0.085 * face)
		if face < 0.0:
			lb.rotation.y = PI
		root.add_child(lb)


static func _add_curtain(root: Node3D, kind: StringName, half: float, height: float) -> void:
	var cur := MeshInstance3D.new()
	cur.name = "Curtain"
	var qm := QuadMesh.new()
	qm.size = Vector2(2.0 * half, height)
	cur.mesh = qm
	cur.material_override = _curtain_mat(kind)
	cur.position = Vector3(0.0, height * 0.5, 0.0)
	cur.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ranged(cur, CURTAIN_RANGE)
	root.add_child(cur)
	root.set_meta(&"curtain", cur)


# ------------------------------------------------------------------ labels

static func _text(text: String, height: float, col: Color) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = 96
	l.pixel_size = height / 96.0
	l.modulate = col
	l.outline_size = 10
	l.outline_modulate = Color(0.0, 0.0, 0.0, 0.35)
	l.shaded = false
	l.double_sided = false
	l.uppercase = true
	l.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ranged(l, TEXT_RANGE)
	return l


## Camera-facing name tag above an activity (kind line in the activity colour, title in white), constant
## on-screen size, readable from ~150 m and faded out close up and beyond LABEL_RANGE.
static func floating_label(kind: StringName, kind_text: String, title: String) -> Node3D:
	var root := Node3D.new()
	root.name = "NameTag"
	var head := _tag_label(kind_text.to_upper(), 34, color(kind).lerp(Color.WHITE, 0.15))
	head.offset = Vector2(0.0, 46.0)
	root.add_child(head)
	root.add_child(_tag_label(title, 50, Color(1.0, 0.98, 0.94)))
	return root


static func _tag_label(text: String, size: int, col: Color) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.fixed_size = true
	l.font_size = size
	l.pixel_size = 0.00105
	l.modulate = col
	l.outline_size = 16
	l.outline_modulate = Color(0.03, 0.03, 0.06, 0.9)
	l.shaded = false
	l.no_depth_test = false   # hills and buildings hide tags of events out of sight
	l.render_priority = 10
	l.outline_render_priority = 9
	l.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	l.visibility_range_begin = 30.0
	l.visibility_range_begin_margin = 8.0
	l.visibility_range_end = LABEL_RANGE
	l.visibility_range_end_margin = 60.0
	l.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	return l


# ------------------------------------------------------------------ ramp

## Jump ramp (kicker) with collision (StaticBody3D on the world layer, "concrete" surface). Local frame: lip at
## z = 0 rising to `h`, entry at z = +length slightly below the road surface; travel is toward -Z. Behind the
## lip a back slope runs down to the road at z = -back_len (local road height back_y there), so the track stays
## drivable against the jump direction; it is short enough that every scoring jump flies clear of it.
static func ramp_node(kind: StringName, width: float, length: float, h: float, back_len: float, back_y := 0.0) -> Node3D:
	var root := Node3D.new()
	root.name = "JumpRamp"
	var hw := width * 0.5
	var sink := -0.06
	var low := minf(-0.45, back_y - 0.45)
	var a := Vector3(-hw, sink, length)
	var b := Vector3(hw, sink, length)
	var c := Vector3(-hw, h, 0.0)
	var d := Vector3(hw, h, 0.0)
	var g := Vector3(-hw, back_y + sink, -back_len)
	var k := Vector3(hw, back_y + sink, -back_len)
	var a2 := Vector3(-hw, low, length)
	var b2 := Vector3(hw, low, length)
	var g2 := Vector3(-hw, low, -back_len)
	var k2 := Vector3(hw, low, -back_len)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var deck := Color(1, 0, 0)
	var side := Color(0, 1, 0)
	# Decks: UV.y = 0 at the lip, so both decks show chevrons pointing up at the lip and the lip band.
	var n_top := (a - c).cross(d - c).normalized()
	_tri(st, [a, c, d], [Vector2(0, 1), Vector2(0, 0), Vector2(1, 0)], n_top, deck)
	_tri(st, [a, d, b], [Vector2(0, 1), Vector2(1, 0), Vector2(1, 1)], n_top, deck)
	var n_back := (d - c).cross(g - c).normalized()
	_tri(st, [g, k, d], [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0)], n_back, deck)
	_tri(st, [g, d, c], [Vector2(0, 1), Vector2(1, 0), Vector2(0, 0)], n_back, deck)
	# Side walls (hazard stripes, UV in metres / 4).
	for sd: float in [-1.0, 1.0]:
		var n := Vector3(sd, 0.0, 0.0)
		var tris: Array = [[c, a, a2], [c, a2, g2], [c, g2, g]] if sd < 0.0 else [[d, b2, b], [d, k2, b2], [d, k, k2]]
		for t: Array in tris:
			var uvs: Array = []
			for p: Vector3 in t:
				uvs.append(Vector2(p.z, p.y) * 0.25)
			_tri(st, t, uvs, n, side)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var mat := ShaderMaterial.new()
	mat.shader = RAMP_SHADER
	mat.set_shader_parameter("accent", color(kind))
	mi.material_override = mat
	_ranged(mi, 900.0)
	root.add_child(mi)
	var body := StaticBody3D.new()
	body.name = "RampBody"
	body.collision_layer = 1
	body.collision_mask = 0
	body.set_meta(&"surface", &"concrete")
	var cs := CollisionShape3D.new()
	var shape := ConvexPolygonShape3D.new()
	shape.points = PackedVector3Array([a, b, c, d, g, k, a2, b2, g2, k2])
	cs.shape = shape
	body.add_child(cs)
	root.add_child(body)
	return root


static func _tri(st: SurfaceTool, pts: Array, uvs: Array, n: Vector3, col: Color) -> void:
	for i in 3:
		st.set_color(col)
		st.set_normal(n)
		st.set_uv(uvs[i])
		st.add_vertex(pts[i])


# ------------------------------------------------------------------ collectible

static func flag_node() -> Node3D:
	var root := Node3D.new()
	root.name = "FestivalFlag"
	var gold := color(&"collectible")
	var base := MeshInstance3D.new()
	base.mesh = _cyl_mesh(0.7, 0.85, 0.35)
	base.material_override = _metal_mat(gold)
	base.position = Vector3(0, 0.12, 0)
	root.add_child(base)
	var pole := MeshInstance3D.new()
	pole.mesh = _cyl_mesh(0.06, 0.08, 4.8)
	pole.material_override = _metal_mat(Color(0.95, 0.93, 0.88))
	pole.position = Vector3(0, 2.4, 0)
	root.add_child(pole)
	var tip := MeshInstance3D.new()
	tip.mesh = _sphere_mesh(0.18)
	tip.material_override = _glow_box_mat(gold)
	tip.position = Vector3(0, 4.9, 0)
	root.add_child(tip)
	var cloth := MeshInstance3D.new()
	cloth.name = "Cloth"
	var qm := QuadMesh.new()
	qm.size = Vector2(2.5, 1.55)
	qm.center_offset = Vector3(1.25, 0.0, 0.0)
	qm.subdivide_width = 18
	qm.subdivide_depth = 6
	cloth.mesh = qm
	var fm := ShaderMaterial.new()
	fm.shader = FLAG_SHADER
	cloth.material_override = fm
	cloth.position = Vector3(0.05, 3.95, 0)
	root.add_child(cloth)
	var ring := MeshInstance3D.new()
	ring.name = "Ring"
	var rq := QuadMesh.new()
	rq.size = Vector2(9.0, 9.0)
	rq.orientation = PlaneMesh.FACE_Y
	ring.mesh = rq
	ring.material_override = _glow_mat(gold, 2, 0.9)
	ring.position = Vector3(0, 0.15, 0)
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(ring)
	var glow := MeshInstance3D.new()
	glow.name = "Glow"
	var gq := QuadMesh.new()
	gq.size = Vector2(6.0, 6.0)
	glow.mesh = gq
	glow.material_override = _glow_mat(gold, 0, 0.7)
	glow.position = Vector3(0, 3.6, 0)
	glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(glow)
	var beam := MeshInstance3D.new()
	beam.name = "Beam"
	var cm := CylinderMesh.new()
	cm.top_radius = 0.6
	cm.bottom_radius = 0.6
	cm.height = 80.0
	cm.cap_top = false
	cm.cap_bottom = false
	cm.radial_segments = 12
	cm.rings = 1
	beam.mesh = cm
	beam.material_override = _glow_mat(gold, 1, 0.6)
	beam.position = Vector3(0, 40.0, 0)
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	beam.visibility_range_begin = 35.0
	beam.visibility_range_begin_margin = 10.0
	beam.visibility_range_end = 450.0
	beam.visibility_range_end_margin = 60.0
	beam.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	root.add_child(beam)
	for c in root.get_children():
		if c != beam:
			_ranged(c as GeometryInstance3D, 340.0)
	return root


# ------------------------------------------------------------------ meshes

## Inflatable arch: a tube swept along two legs and a rounded top, with chamber bulges.
static func arch_mesh(hw: float, h: float, r: float) -> ArrayMesh:
	var key := "arch_%.2f_%.2f_%.2f" % [hw, h, r]
	if _meshes.has(key):
		return _meshes[key]
	var rc := minf(2.4, hw * 0.35)
	var path := PackedVector3Array()
	var y := -LEG_DEPTH
	while y < h - rc:
		path.append(Vector3(-hw, y, 0))
		y += 0.4
	for k in 9:
		var a := PI - k * (PI * 0.5) / 8.0
		path.append(Vector3(-hw + rc + cos(a) * rc, h - rc + sin(a) * rc, 0))
	var x := -hw + rc + 0.4
	while x < hw - rc:
		path.append(Vector3(x, h, 0))
		x += 0.4
	for k in 9:
		var a2 := PI * 0.5 - k * (PI * 0.5) / 8.0
		path.append(Vector3(hw - rc + cos(a2) * rc, h - rc + sin(a2) * rc, 0))
	y = h - rc - 0.4
	while y > -LEG_DEPTH:
		path.append(Vector3(hw, y, 0))
		y -= 0.4
	path.append(Vector3(hw, -LEG_DEPTH, 0))
	var seg := 16
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	var along := 0.0
	var n := path.size()
	for i in n:
		var p := path[i]
		var t := (path[mini(i + 1, n - 1)] - path[maxi(i - 1, 0)]).normalized()
		var nrm := Vector3(-t.y, t.x, 0.0)
		if i > 0:
			along += p.distance_to(path[i - 1])
		var bulge := 1.0 + 0.07 * (0.5 + 0.5 * cos(along / 1.5 * TAU))
		for k in seg + 1:
			var a3 := TAU * k / seg
			var d := nrm * cos(a3) + Vector3(0, 0, 1) * sin(a3)
			verts.append(p + d * r * bulge)
			norms.append(d)
			uvs.append(Vector2(along, float(k) / seg))
		if i > 0:
			var b0 := (i - 1) * (seg + 1)
			var b1 := i * (seg + 1)
			for k in seg:
				idx.append_array([b0 + k, b1 + k, b0 + k + 1, b0 + k + 1, b1 + k, b1 + k + 1])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = idx
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_meshes[key] = am
	return am


static func _box_mesh(size: Vector3) -> BoxMesh:
	var key := "box_%s" % str(size)
	if not _meshes.has(key):
		var b := BoxMesh.new()
		b.size = size
		_meshes[key] = b
	return _meshes[key]


static func _cyl_mesh(top: float, bottom: float, height: float) -> CylinderMesh:
	var key := "cyl_%.3f_%.3f_%.3f" % [top, bottom, height]
	if not _meshes.has(key):
		var c := CylinderMesh.new()
		c.top_radius = top
		c.bottom_radius = bottom
		c.height = height
		c.radial_segments = 12
		c.rings = 1
		_meshes[key] = c
	return _meshes[key]


static func _sphere_mesh(r: float) -> SphereMesh:
	var key := "sph_%.3f" % r
	if not _meshes.has(key):
		var s := SphereMesh.new()
		s.radius = r
		s.height = r * 2.0
		s.radial_segments = 12
		s.rings = 6
		_meshes[key] = s
	return _meshes[key]


static func _ranged(gi: GeometryInstance3D, end: float) -> void:
	if gi == null:
		return
	gi.visibility_range_end = end
	gi.visibility_range_end_margin = end * 0.08
	gi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF


# ------------------------------------------------------------------ materials

static func _inflatable_mat(kind: StringName) -> ShaderMaterial:
	var key := "infl_" + String(kind)
	if not _mats.has(key):
		var m := ShaderMaterial.new()
		m.shader = ARCH_SHADER
		m.set_shader_parameter("base_color", color(kind))
		_mats[key] = m
	return _mats[key]


static func _curtain_mat(kind: StringName) -> ShaderMaterial:
	var key := "curtain_" + String(kind)
	if not _mats.has(key):
		var m := ShaderMaterial.new()
		m.shader = CURTAIN_SHADER
		m.set_shader_parameter("color", color(kind))
		_mats[key] = m
	return _mats[key]


static func _glow_mat(col: Color, mode: int, strength: float) -> ShaderMaterial:
	var key := "glow_%s_%d_%.2f" % [col.to_html(), mode, strength]
	if not _mats.has(key):
		var m := ShaderMaterial.new()
		m.shader = GLOW_SHADER
		m.set_shader_parameter("color", col)
		m.set_shader_parameter("mode", mode)
		m.set_shader_parameter("strength", strength)
		_mats[key] = m
	return _mats[key]


static func _banner_mat(kind: StringName) -> StandardMaterial3D:
	var key := "banner_" + String(kind)
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		var c := color(kind)
		m.albedo_color = c.darkened(0.5)
		m.roughness = 0.65
		m.emission_enabled = true
		m.emission = c.darkened(0.6)
		m.emission_energy_multiplier = 0.4
		_mats[key] = m
	return _mats[key]


static func _plain_mat(col: Color, rough: float) -> StandardMaterial3D:
	var key := "plain_%s_%.2f" % [col.to_html(), rough]
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = col
		m.roughness = rough
		_mats[key] = m
	return _mats[key]


static func _metal_mat(col: Color) -> StandardMaterial3D:
	var key := "metal_%s" % col.to_html()
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = col
		m.metallic = 0.45
		m.roughness = 0.38
		_mats[key] = m
	return _mats[key]


static func _glow_box_mat(col: Color) -> StandardMaterial3D:
	var key := "glowbox_%s" % col.to_html()
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = col
		m.roughness = 0.4
		m.emission_enabled = true
		m.emission = col
		m.emission_energy_multiplier = 0.9
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		_mats[key] = m
	return _mats[key]


# ------------------------------------------------------------------ Blender kit props

## Kit prop through PropLibrary when it exists and returns a real (non-placeholder) asset; else null.
static func _prop(prop_name: String) -> Node3D:
	if not _prop_checked:
		_prop_checked = true
		if ResourceLoader.exists(PROP_LIBRARY):
			var s := load(PROP_LIBRARY) as Script
			if s != null:
				for m: Dictionary in s.get_script_method_list():
					if m.get("name") == "scene":
						_prop_script = s
					elif m.get("name") == "is_placeholder":
						_prop_has_check = true
	if _prop_script == null:
		return null
	if _prop_has_check and bool(_prop_script.call("is_placeholder", prop_name)):
		return null
	var n: Variant = _prop_script.call("scene", prop_name)
	if not (n is Node3D):
		return null
	var node := n as Node3D
	if _is_placeholder(node):
		node.free()
		return null
	return node


static func _is_placeholder(n: Node) -> bool:
	if String(n.name).to_lower().contains("placeholder") or n.has_meta(&"placeholder"):
		return true
	for c in n.get_children():
		if String(c.name).to_lower().contains("placeholder") or c.has_meta(&"placeholder"):
			return true
	return false


static func _node_aabb(n: Node3D) -> AABB:
	var out := AABB()
	var first := true
	for c in n.find_children("*", "MeshInstance3D", true, false):
		var mi := c as MeshInstance3D
		if mi.mesh == null:
			continue
		var ab := mi.mesh.get_aabb()
		if first:
			out = ab
			first = false
		else:
			out = out.merge(ab)
	return out
