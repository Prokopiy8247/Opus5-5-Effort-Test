class_name CarFactory
extends RefCounted
## Builds a drivable CarController from CarData + the Blender-exported .glb (see docs/ASSET_CONVENTIONS.md).
## Wheels / calipers are re-parented under "Visual" so the controller can drive their local transforms.

const PAINT_SHADER := preload("res://assets/shaders/car_paint.gdshader")
const WHEEL_IDS := ["FL", "FR", "RL", "RR"]

static var _model_cache: Dictionary = {}


static func load_model(path: String) -> PackedScene:
	if path == "":
		return null
	if not _model_cache.has(path):
		_model_cache[path] = load(path) if ResourceLoader.exists(path) else null
	return _model_cache[path]


static func build(data: CarData, paint: Dictionary = {}, is_player := true) -> CarController:
	var car := CarController.new()
	car.name = "Car_" + data.id
	car.is_player = is_player
	car.collision_layer = 2 if is_player else 4
	car.collision_mask = 1 | 2 | 4 | 16 | 32   # 32 = road barriers (wheel rays ignore them)
	var visual := CarVisuals.new()
	visual.name = "Visual"
	car.add_child(visual)

	var wheel_defs: Array = []
	var scene := load_model(data.model_path)
	var body_aabb := AABB(Vector3(-data.body_size.x * 0.5, 0.15, -data.body_size.z * 0.5), data.body_size)
	var cabin_aabb := AABB()
	if scene != null:
		var model: Node3D = scene.instantiate()
		model.name = "Model"
		visual.add_child(model)
		# Materials (paint, rims, lenses) and sockets first, while the wheels are still inside the model.
		visual.setup_from_model(model, data)
		# Wheels and calipers.
		for id in WHEEL_IDS:
			var wn := model.find_child("Wheel_" + id, true, false) as Node3D
			if wn == null:
				continue
			var wxf := _relative_xf(wn, model)
			var aabb := _merged_aabb(wn, Transform3D.IDENTITY)
			var radius := maxf(aabb.size.y, aabb.size.z) * 0.5
			var width := aabb.size.x
			var pivot := Node3D.new()
			pivot.name = "WheelPivot_" + id
			pivot.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
			visual.add_child(pivot)
			wn.owner = null
			wn.get_parent().remove_child(wn)
			pivot.add_child(wn)
			wn.transform = Transform3D(wxf.basis, Vector3.ZERO)
			var cal_pivot: Node3D = null
			var cn := model.find_child("Caliper_" + id, true, false) as Node3D
			if cn != null:
				var cxf := _relative_xf(cn, model)
				cal_pivot = Node3D.new()
				cal_pivot.name = "CaliperPivot_" + id
				cal_pivot.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
				visual.add_child(cal_pivot)
				cn.owner = null
				cn.get_parent().remove_child(cn)
				cal_pivot.add_child(cn)
				cn.transform = Transform3D(cxf.basis, cxf.origin - wxf.origin)
			wheel_defs.append({"id": id, "center": wxf.origin, "radius": radius, "width": width, "node": pivot, "caliper": cal_pivot})
		# Body bounds for collision / inertia (everything except wheels).
		var b := AABB()
		var first := true
		for n: String in ["Body", "Glass"]:
			var node := model.find_child(n, true, false) as Node3D
			if node == null:
				continue
			var ab := _merged_aabb(node, _relative_xf(node, model))
			if n == "Glass":
				cabin_aabb = ab
			b = ab if first else b.merge(ab)
			first = false
		if not first:
			body_aabb = b
	else:
		_build_placeholder(car, visual, data, wheel_defs)

	_add_collision(car, data, body_aabb, cabin_aabb)
	data.body_size = body_aabb.size
	car.setup(data, wheel_defs)
	visual.car = car
	apply_paint(car, paint if not paint.is_empty() else {"color": data.default_color, "finish": int(data.default_finish)})
	return car


static func _relative_xf(node: Node3D, root: Node3D) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var n: Node = node
	while n != null and n != root:
		if n is Node3D:
			xf = (n as Node3D).transform * xf
		n = n.get_parent()
	return xf


static func _merged_aabb(node: Node3D, xf: Transform3D) -> AABB:
	var result := AABB()
	var first := true
	var stack: Array = [[node, xf]]
	while not stack.is_empty():
		var item: Array = stack.pop_back()
		var n: Node = item[0]
		var t: Transform3D = item[1]
		if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
			var ab := t * (n as MeshInstance3D).mesh.get_aabb()
			result = ab if first else result.merge(ab)
			first = false
		for c in n.get_children():
			if c is Node3D:
				stack.append([c, t * (c as Node3D).transform])
	return result


static func _add_collision(car: CarController, data: CarData, body: AABB, cabin: AABB) -> void:
	var bottom := maxf(body.position.y + 0.06, 0.2)
	var height := body.size.y
	var top_main := body.position.y + height * 0.58
	if cabin.size != Vector3.ZERO:
		top_main = minf(top_main, cabin.position.y + 0.05)
	var main := CollisionShape3D.new()
	main.name = "ColMain"
	var box := BoxShape3D.new()
	box.size = Vector3(body.size.x * 0.94, maxf(top_main - bottom, 0.25), body.size.z * 0.97)
	main.shape = box
	main.position = Vector3(body.get_center().x, bottom + box.size.y * 0.5, body.get_center().z)
	car.add_child(main)
	if cabin.size != Vector3.ZERO and cabin.size.y > 0.2:
		var cab := CollisionShape3D.new()
		cab.name = "ColCabin"
		var cbox := BoxShape3D.new()
		var ctop := cabin.position.y + cabin.size.y
		cbox.size = Vector3(cabin.size.x * 0.92, maxf(ctop - top_main, 0.15), cabin.size.z * 0.85)
		cab.shape = cbox
		cab.position = Vector3(cabin.get_center().x, top_main + cbox.size.y * 0.5, cabin.get_center().z)
		car.add_child(cab)


static func _build_placeholder(car: CarController, visual: CarVisuals, data: CarData, wheel_defs: Array) -> void:
	# Development stand-in only (used when the .glb is missing). Never shipped as a garage car.
	var body := MeshInstance3D.new()
	body.name = "Body"
	var bm := BoxMesh.new()
	bm.size = Vector3(data.body_size.x, data.body_size.y * 0.55, data.body_size.z)
	body.mesh = bm
	body.position = Vector3(0, 0.25 + bm.size.y * 0.5, 0)
	var mat := ShaderMaterial.new()
	mat.shader = PAINT_SHADER
	body.set_surface_override_material(0, mat)
	visual.add_child(body)
	visual.paint_mats.append(mat)
	var hw := data.track_front * 0.5
	for id in WHEEL_IDS:
		var front: bool = id.begins_with("F")
		var x := hw if id.ends_with("R") else -hw
		var z := -data.wheelbase * 0.5 if front else data.wheelbase * 0.5
		var r := data.wheel_radius_front if front else data.wheel_radius_rear
		var pivot := Node3D.new()
		pivot.name = "WheelPivot_" + id
		pivot.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		visual.add_child(pivot)
		var wm := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = r
		cm.bottom_radius = r
		cm.height = 0.22
		wm.mesh = cm
		wm.rotation = Vector3(0, 0, PI * 0.5)
		pivot.add_child(wm)
		wheel_defs.append({"id": id, "center": Vector3(x, r, z), "radius": r, "width": 0.22, "node": pivot, "caliper": null})


## paint: {color: Color, finish: int, stripes: int, stripe_color: Color, rim_color: Color}
static func apply_paint(car: CarController, paint: Dictionary) -> void:
	var vis := car.get_node_or_null("Visual") as CarVisuals
	if vis == null:
		return
	var color: Color = paint.get("color", Color.RED)
	var finish: int = int(paint.get("finish", 0))
	for m: ShaderMaterial in vis.paint_mats:
		m.set_shader_parameter("base_color", color)
		match finish:
			CarData.Finish.MATTE:
				m.set_shader_parameter("metallic", 0.0)
				m.set_shader_parameter("roughness", 0.62)
				m.set_shader_parameter("clearcoat_amount", 0.0)
				m.set_shader_parameter("flake_amount", 0.0)
			CarData.Finish.METALLIC:
				m.set_shader_parameter("metallic", 0.75)
				m.set_shader_parameter("roughness", 0.3)
				m.set_shader_parameter("clearcoat_amount", 1.0)
				m.set_shader_parameter("flake_amount", 0.6)
			_:
				m.set_shader_parameter("metallic", 0.0)
				m.set_shader_parameter("roughness", 0.18)
				m.set_shader_parameter("clearcoat_amount", 1.0)
				m.set_shader_parameter("flake_amount", 0.0)
		m.set_shader_parameter("stripe_mode", int(paint.get("stripes", 0)))
		m.set_shader_parameter("stripe_color", paint.get("stripe_color", Color.WHITE))
		m.set_shader_parameter("body_half_width", car.data.body_size.x * 0.5)
		m.set_shader_parameter("body_height", car.data.body_size.y)
	var rim: Color = paint.get("rim_color", Color(-1, -1, -1))
	for m: StandardMaterial3D in vis.rim_mats:
		if rim.r >= 0.0:
			m.albedo_color = rim
		else:
			m.albedo_color = vis.rim_default.get(m, m.albedo_color)
