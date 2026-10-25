extends Node3D
## Settlements and landmarks ("Settlements" under Main). Plans every POI layout once
## (dressing_settlement_plan.gd), renders props as RenderingServer MultiMeshes grouped per prop name
## and 256 m bucket (visibility ranges per prop class), adds static colliders (baked trimesh for buildings,
## box / cylinder for small props; thin props on the barrier layer), builds the generated concrete aprons and
## foundation pads, and animates wind-turbine rotors, moored boats and the lighthouse beam from this single manager.
## lamp_heads lists the extra Lamp_Street heads (fuel stations, diners) the lamp pool lights at night.
## Time-reactive (Game.TIME_REACTIVE_GROUP): it pushes the shared "night" look parameter (lit
## windows, festoon bulbs, lamp heads) itself, so a photo-mode time change while paused shows at once.

const Plan := preload("res://scripts/world/dressing_settlement_plan.gd")
const PropLibrary := preload("res://scripts/world/prop_library.gd")
const Mats := preload("res://scripts/world/dressing_materials.gd")
const Rules := preload("res://scripts/world/dressing_rules.gd")

const MB := preload("res://scripts/world/dressing_mesh_builder.gd")
const BUCKET := 256.0
const VIS_FESTOON := 700.0
const BARRIER_LAYER := 32           # car bodies collide, wheel rays ignore (as RoadBuilder rails)
const MIN_BOX := Vector3(0.3, 0.1, 0.3)
## Lamp_Street head relative to the post base (the arm reaches along -Z), as the lamp pool assumes.
const LAMP_HEAD := Vector3(0.0, 6.2, -1.75)

var items: Array[Dictionary] = []
var lamp_heads: Array[Transform3D] = []
var _rids: Array[RID] = []
var _rotors: Array = []          # [instance RID, base Transform3D, phase, speed]
var _boats: Array = []           # [instance RID, base Transform3D, phase]
var _beams: Array[Node3D] = []
var _bodies: Dictionary = {}     # Vector3i (bucket x, bucket z, layer) -> StaticBody3D
var _trimesh: Dictionary = {}    # "name@scale" -> Shape3D
var _hull_pts: Dictionary = {}
var _concrete_mat: Material
var _time: float = 0.0
var _cam := Vector3.ZERO


func _ready() -> void:
	if not (Game.world is World) or "--no-settlements" in OS.get_cmdline_user_args():
		set_process(false)
		return
	add_to_group(Game.TIME_REACTIVE_GROUP)
	var t0 := Time.get_ticks_msec()
	Rules.exclusions.clear()
	var planner := Plan.new()
	items = planner.plan(Game.world as World)
	var t1 := Time.get_ticks_msec()
	_build()
	print("[settlements] %d props, %d exclusions, built in %d ms (layout %d ms)" % [items.size(), Rules.exclusions.size(), Time.get_ticks_msec() - t0, t1 - t0])
	for l in planner.log_lines:
		print("[settlements]   ", l)
	print("[settlements]   rejected placements: ", planner.fails)


func _build() -> void:
	var scenario := get_world_3d().scenario
	var groups: Dictionary = {}
	for it in items:
		var name: String = it["name"]
		var xf: Transform3D = it["xf"]
		var anim: String = it["anim"]
		if anim == "festoon":
			_add_festoon(it["points"])
			continue
		if anim == "apron":
			_add_apron(it["points"])
			continue
		if anim == "pad":
			_add_pad(it["xf"], it["box"])
			continue
		if it.get("light", false):
			var f := -xf.basis.z
			f.y = 0.0
			lamp_heads.append(Transform3D(Basis.looking_at(f.normalized(), Vector3.UP), xf * LAMP_HEAD))
		if it.has("label"):
			_add_label(it)
		if anim == "rotor" or anim == "boat":
			var inst := RenderingServer.instance_create2(PropLibrary.mesh(name).get_rid(), scenario)
			RenderingServer.instance_set_transform(inst, xf)
			RenderingServer.instance_geometry_set_visibility_range(inst, 0.0, float(it["vis"]), 0.0, 0.0, RenderingServer.VISIBILITY_RANGE_FADE_DISABLED)
			_rids.append(inst)
			var seed: float = (it["tint"] as Color).a
			if anim == "rotor":
				_rotors.append([inst, xf, seed * TAU, 1.25 + seed * 0.35])
			else:
				_boats.append([inst, xf, seed * TAU])
		else:
			var key := "%s|%d|%d" % [name, floori(xf.origin.x / BUCKET), floori(xf.origin.z / BUCKET)]
			if not groups.has(key):
				groups[key] = []
			(groups[key] as Array).append(it)
		if anim == "beacon":
			_add_beam(it)
		_collider(it)
	for key: String in groups:
		var arr: Array = groups[key]
		var first: Dictionary = arr[0]
		var mesh := PropLibrary.mesh(first["name"])
		var buf := PackedFloat32Array()
		buf.resize(arr.size() * Rules.STRIDE)
		var k := 0
		for it: Dictionary in arr:
			var xf: Transform3D = it["xf"]
			var b := xf.basis
			var o := xf.origin
			var c: Color = it["tint"]
			var vals := [b.x.x, b.y.x, b.z.x, o.x, b.x.y, b.y.y, b.z.y, o.y, b.x.z, b.y.z, b.z.z, o.z, c.r, c.g, c.b, c.a]
			for v: float in vals:
				buf[k] = v
				k += 1
		var mm := RenderingServer.multimesh_create()
		RenderingServer.multimesh_allocate_data(mm, arr.size(), RenderingServer.MULTIMESH_TRANSFORM_3D, false, true)
		RenderingServer.multimesh_set_mesh(mm, mesh.get_rid())
		RenderingServer.multimesh_set_buffer(mm, buf)
		var inst := RenderingServer.instance_create2(mm, scenario)
		var vis: float = first["vis"]
		RenderingServer.instance_geometry_set_visibility_range(inst, 0.0, vis, 0.0, vis * 0.06, RenderingServer.VISIBILITY_RANGE_FADE_SELF)
		_rids.append(inst)
		_rids.append(mm)


func _body_for(p: Vector3, layer := 1) -> StaticBody3D:
	var key := Vector3i(floori(p.x / BUCKET), floori(p.z / BUCKET), layer)
	var body: StaticBody3D = _bodies.get(key)
	if body == null:
		body = StaticBody3D.new()
		body.name = "SettlementCol_%d_%d%s" % [key.x, key.y, "" if layer == 1 else "_b"]
		body.collision_layer = layer
		body.collision_mask = 0
		body.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		add_child(body)
		_bodies[key] = body
	return body


func _collider(it: Dictionary) -> void:
	var kind: int = it["col"]
	if kind == Plan.Col.NONE:
		return
	var name: String = it["name"]
	var xf: Transform3D = it["xf"]
	var bb := PropLibrary.aabb(name)
	var sc := xf.basis.get_scale().x
	var rot := xf.basis.orthonormalized()
	var cs := CollisionShape3D.new()
	match kind:
		Plan.Col.BOX:
			var box := BoxShape3D.new()
			box.size = (bb.size * sc).max(MIN_BOX)
			cs.shape = box
			cs.transform = Transform3D(rot, xf * bb.get_center())
		Plan.Col.CYLINDER:
			var cyl := CylinderShape3D.new()
			cyl.radius = Plan.CYL_RADIUS.get(name, 0.45 * minf(bb.size.x, bb.size.z)) * sc
			cyl.height = maxf(bb.end.y * sc, 0.5)
			cs.shape = cyl
			cs.transform = Transform3D(rot, xf.origin + Vector3.UP * cyl.height * 0.5)
		Plan.Col.CONVEX:
			cs.shape = _convex_for(name, sc)
			cs.transform = Transform3D(rot, xf.origin)
		_:
			cs.shape = _trimesh_for(name, sc)
			cs.transform = Transform3D(rot, xf.origin)
	_body_for(xf.origin, BARRIER_LAYER if name in Plan.BARRIER_PROPS else 1).add_child(cs)


## Convex hull of a small prop (rocks, cacti) from the same support points the dressing colliders use, scaled
## per instance and cached by scale.
func _convex_for(name: String, sc: float) -> Shape3D:
	var key := "%s#cvx@%.3f" % [name, sc]
	var shape: Shape3D = _trimesh.get(key)
	if shape != null:
		return shape
	var base: PackedVector3Array = _hull_pts.get(name, PackedVector3Array())
	if base.is_empty():
		base = Rules.support_points(PropLibrary.mesh(name))
		_hull_pts[name] = base
	var pts := PackedVector3Array()
	for p in base:
		pts.append(p * sc)
	var cvx := ConvexPolygonShape3D.new()
	cvx.points = pts
	_trimesh[key] = cvx
	return cvx


## Baked trimesh of a prop; scaled props (ruin walls, the keep) get their own scaled copy of the faces, so no
## scaled concave shape reaches the physics server.
func _trimesh_for(name: String, sc: float) -> Shape3D:
	var key := "%s@%.3f" % [name, sc]
	var shape: Shape3D = _trimesh.get(key)
	if shape != null:
		return shape
	shape = PropLibrary.trimesh(name)
	if absf(sc - 1.0) > 0.001:
		var src := shape as ConcavePolygonShape3D
		if src != null:
			var faces := src.get_faces()
			for i in faces.size():
				faces[i] *= sc
			var scaled := ConcavePolygonShape3D.new()
			scaled.set_faces(faces)
			shape = scaled
	_trimesh[key] = shape
	return shape


## Generated geometry (fuel-station apron, foundation pads) in the kit's concrete.
func _concrete() -> Material:
	if _concrete_mat == null:
		var m := PropLibrary.mesh("Gas_Station")
		for i in m.get_surface_count():
			var mat := m.surface_get_material(i)
			if mat != null and mat.resource_name.to_lower().contains("concrete"):
				_concrete_mat = mat
				break
		if _concrete_mat == null:
			var sm := StandardMaterial3D.new()
			sm.albedo_color = Color(0.62, 0.61, 0.58)
			sm.roughness = 0.9
			_concrete_mat = sm
	return _concrete_mat


func _add_generated(st: SurfaceTool, faces: Array[Vector3], node_name: String) -> void:
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.name = "%s_%d" % [node_name, get_child_count()]
	mi.mesh = st.commit()
	mi.material_override = _concrete()
	mi.visibility_range_end = Plan.VIS_BUILDING
	add_child(mi)
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(PackedVector3Array(faces))
	var cs := CollisionShape3D.new()
	cs.shape = shape
	_body_for(faces[0]).add_child(cs)


## Ramp between a road shoulder and a forecourt: `points` = [road side, forecourt side] pairs across its width.
## Its sides drop 1.5 m below the top so the ramp never floats over falling ground.
func _add_apron(points: PackedVector3Array) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_color(Color(0.9, 0.9, 0.88))
	var faces: Array[Vector3] = []
	var n := points.size() / 2
	var mid := Vector3.ZERO
	for p in points:
		mid += p / points.size()
	for i in n - 1:
		_quad(st, faces, [points[i * 2], points[i * 2 + 1], points[i * 2 + 3], points[i * 2 + 2]], Vector3.UP)
	var drop := Vector3.DOWN * 1.5
	for k: int in [0, n - 1]:
		var a := points[k * 2]
		var b := points[k * 2 + 1]
		_quad(st, faces, [a, a + drop, b + drop, b], (a + b) * 0.5 - mid)
	_add_generated(st, faces, "Apron")


## Foundation block under a building (local box in xf space): four sides and the top.
func _add_pad(xf: Transform3D, box: AABB) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_color(Color(0.82, 0.82, 0.8))
	var c: Array[Vector3] = []
	for k in 8:
		c.append(xf * (box.position + box.size * Vector3(k & 1, (k >> 1) & 1, (k >> 2) & 1)))
	var centre := xf * box.get_center()
	var faces: Array[Vector3] = []
	for idx: Array in [[0, 2, 3, 1], [1, 3, 7, 5], [5, 7, 6, 4], [4, 6, 2, 0], [2, 6, 7, 3]]:
		var q: Array[Vector3] = [c[idx[0]], c[idx[1]], c[idx[2]], c[idx[3]]]
		_quad(st, faces, q, (q[0] + q[2]) * 0.5 - centre)
	_add_generated(st, faces, "Pad")


## Quad q0..q3 as two triangles, wound to face `out` (front faces are clockwise).
func _quad(st: SurfaceTool, faces: Array[Vector3], q: Array[Vector3], out: Vector3) -> void:
	if (q[2] - q[0]).cross(q[1] - q[0]).dot(out) < 0.0:
		q = [q[0], q[3], q[2], q[1]]
	for t: Vector3 in [q[0], q[1], q[2], q[0], q[2], q[3]]:
		st.add_vertex(t)
		faces.append(t)


const BULB_COLORS := [Color(1.0, 0.82, 0.45), Color(1.0, 0.45, 0.3), Color(0.45, 0.85, 1.0), Color(1.0, 0.95, 0.6), Color(0.9, 0.45, 1.0)]


func _add_festoon(points: PackedVector3Array) -> void:
	var b := MB.new()
	var wire := Color(0.12, 0.12, 0.13, MB.MATTE)
	var k := 0
	for i in points.size() - 1:
		var a := points[i]
		var c := points[i + 1]
		var segs := 10
		var sag := a.distance_to(c) * 0.07
		var prev := a
		for j in range(1, segs + 1):
			var t := float(j) / segs
			var q := a.lerp(c, t) - Vector3.UP * sag * 4.0 * t * (1.0 - t)
			b.beam(prev, q, 0.025, wire)
			prev = q
			if j < segs:
				var bc: Color = BULB_COLORS[k % BULB_COLORS.size()]
				b.box(Transform3D(Basis(), q - Vector3(0, 0.12, 0)), Vector3(0.16, 0.2, 0.16), Color(bc.r, bc.g, bc.b, MB.NIGHT_LIGHT))
				k += 1
	var mi := MeshInstance3D.new()
	mi.name = "Festoon"
	mi.mesh = b.to_mesh(Mats.solid(), "Festoon")
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visibility_range_end = VIS_FESTOON
	add_child(mi)


func _add_label(it: Dictionary) -> void:
	var xf: Transform3D = it["xf"]
	var faces: Array[float] = [-1.0]
	if it.get("label_both", false):
		faces.append(1.0)
	for face in faces:
		var lbl := Label3D.new()
		lbl.text = it["label"]
		lbl.font_size = 96
		lbl.outline_size = 18
		lbl.pixel_size = float(it.get("label_size", 0.01)) * xf.basis.get_scale().x
		lbl.modulate = Color(0.12, 0.13, 0.32)
		lbl.outline_modulate = Color(1.0, 0.96, 0.88)
		lbl.double_sided = false
		lbl.visibility_range_end = 500.0
		var off: Vector3 = it.get("label_at", Vector3.ZERO)
		off.z = absf(off.z) * face
		lbl.transform = Transform3D(xf.basis.orthonormalized() * Basis(Vector3.UP, PI if face < 0.0 else 0.0), xf * off)
		add_child(lbl)


func _add_beam(it: Dictionary) -> void:
	var xf: Transform3D = it["xf"]
	var bb := PropLibrary.aabb(it["name"])
	var h := bb.end.y - 4.0 if PropLibrary.is_placeholder(it["name"]) else bb.end.y * 0.86
	var pivot := Node3D.new()
	pivot.name = "LighthouseBeam"
	pivot.position = xf.origin + Vector3.UP * h
	add_child(pivot)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = Color(1.0, 0.9, 0.65, 0.5)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segs := 10
	for dir: float in [-1.0, 1.0]:
		for i in segs:
			var a0 := TAU * i / segs
			var a1 := TAU * (i + 1) / segs
			var p0 := Vector3(dir * 0.8, cos(a0) * 0.45, sin(a0) * 0.45)
			var p1 := Vector3(dir * 0.8, cos(a1) * 0.45, sin(a1) * 0.45)
			var q0 := Vector3(dir * 90.0, cos(a0) * 7.0 - 3.0, sin(a0) * 7.0)
			var q1 := Vector3(dir * 90.0, cos(a1) * 7.0 - 3.0, sin(a1) * 7.0)
			var near_c := Color(1, 1, 1, 0.55)
			var far_c := Color(1, 1, 1, 0.0)
			for v: Array in [[p0, near_c], [q0, far_c], [q1, far_c], [p0, near_c], [q1, far_c], [p1, near_c]]:
				st.set_color(v[1])
				st.add_vertex(v[0])
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pivot.add_child(mi)
	pivot.visible = false
	_beams.append(pivot)


func _process(delta: float) -> void:
	_time += delta
	var cam := get_viewport().get_camera_3d()
	if cam != null:
		_cam = cam.global_position
	for r: Array in _rotors:
		var base: Transform3D = r[1]
		if base.origin.distance_squared_to(_cam) > 4000.0 * 4000.0:
			continue
		var ang: float = _time * float(r[3]) + float(r[2])
		RenderingServer.instance_set_transform(r[0], base * Transform3D(Basis(Vector3(0, 0, 1), ang), Vector3.ZERO))
	for b: Array in _boats:
		var base: Transform3D = b[1]
		if base.origin.distance_squared_to(_cam) > 600.0 * 600.0:
			continue
		var ph: float = b[2]
		var roll := sin(_time * 0.9 + ph) * 0.045
		var pitch := sin(_time * 0.7 + ph * 1.3) * 0.025
		var bob := sin(_time * 1.1 + ph) * 0.09
		var xf := base * Transform3D(Basis.from_euler(Vector3(pitch, 0.0, roll)), Vector3(0, bob, 0))
		RenderingServer.instance_set_transform(b[0], xf)
	var night := night_factor(Game.get_time_of_day())
	Mats.set_param(&"night", night)
	for p in _beams:
		p.visible = night > 0.2
		if p.visible:
			p.rotation.y = _time * 0.85


## Night look 0..1 by the clock (the same curve the dressing manager pushes every frame).
static func night_factor(hour: float) -> float:
	var hr := fposmod(hour, 24.0)
	if hr >= 12.0:
		return smoothstep(18.6, 20.4, hr)
	return 1.0 - smoothstep(5.2, 6.8, hr)


func _exit_tree() -> void:
	for rid in _rids:
		RenderingServer.free_rid(rid)
	_rids.clear()
