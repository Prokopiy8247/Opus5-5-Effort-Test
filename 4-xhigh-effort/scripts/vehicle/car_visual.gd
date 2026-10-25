class_name CarVisual
extends Node3D
## Instantiates a Blender-exported car (.glb), rigs wheels (steer pivot -> spin node -> mesh),
## maps materials by name to project materials and drives lights/steering wheel from the car.

const WHEEL_KEYS := ["FL", "FR", "RL", "RR"]

var model: Node3D
var prefix := ""
var body_mesh: MeshInstance3D
var glass_mesh: MeshInstance3D
var interior_mesh: MeshInstance3D
var steering_node: Node3D
var steering_basis := Basis.IDENTITY
var wheel_pivots: Array[Node3D] = []
var wheel_spinners: Array[Node3D] = []
var wheel_rest: Array[Vector3] = []
var wheel_radius_front := 0.33
var wheel_radius_rear := 0.33
var sockets := {}
var paint_mat: ShaderMaterial
var rim_mat: StandardMaterial3D
var light_mats := {}
var head_spots: Array[SpotLight3D] = []
var cockpit_only: Array[Node3D] = []
var _body_aabb := AABB()
var _headlights := false
var _brake_level := 0.0


func load_model(path: String, id: String) -> void:
	prefix = id
	var ps := load(path) as PackedScene
	model = ps.instantiate() as Node3D
	model.name = "Model"
	add_child(model)
	var nodes: Array[Node] = model.find_children("*", "Node3D", true, false)
	var wheel_nodes := {}
	var calipers := {}
	for n: Node in nodes:
		var nm := String(n.name)
		if nm.ends_with("_Body"):
			body_mesh = n as MeshInstance3D
		elif nm.ends_with("_Glass"):
			glass_mesh = n as MeshInstance3D
		elif nm.ends_with("_Interior"):
			interior_mesh = n as MeshInstance3D
		elif nm.ends_with("_Steering"):
			steering_node = n as Node3D
		elif nm.contains("_Socket_"):
			sockets[nm.get_slice("_Socket_", 1)] = _rel_xf(n)
		else:
			for k: String in WHEEL_KEYS:
				if nm.ends_with("_Wheel_" + k):
					wheel_nodes[k] = n
				elif nm.ends_with("_Caliper_" + k):
					calipers[k] = n
	_apply_materials()
	if body_mesh != null:
		_body_aabb = _rel_xf(body_mesh) * body_mesh.get_aabb()
	if steering_node != null:
		steering_basis = steering_node.transform.basis
	# wheel rig
	for k: String in WHEEL_KEYS:
		var w := wheel_nodes.get(k) as MeshInstance3D
		var xf := _rel_xf(w)
		var pivot := Node3D.new()
		pivot.name = "Pivot_" + k
		add_child(pivot)
		pivot.position = xf.origin
		var spinner := Node3D.new()
		spinner.name = "Spin_" + k
		pivot.add_child(spinner)
		w.get_parent().remove_child(w)
		spinner.add_child(w)
		w.transform = Transform3D(xf.basis, Vector3.ZERO)
		if calipers.has(k):
			var c := calipers[k] as Node3D
			var cx := _rel_xf(c)
			c.get_parent().remove_child(c)
			pivot.add_child(c)
			c.transform = Transform3D(cx.basis, cx.origin - xf.origin)
		wheel_pivots.append(pivot)
		wheel_spinners.append(spinner)
		wheel_rest.append(xf.origin)
		var r := w.get_aabb().size.y * 0.5
		if k == "FL":
			wheel_radius_front = r
		elif k == "RL":
			wheel_radius_rear = r
	_make_headlights()


func _rel_xf(n: Node) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var cur := n
	while cur != null and cur != self:
		if cur is Node3D:
			xf = (cur as Node3D).transform * xf
		cur = cur.get_parent()
	return xf


func _apply_materials() -> void:
	for n: Node in model.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null:
			continue
		for i in mi.mesh.get_surface_count():
			var src := mi.mesh.surface_get_material(i)
			var nm := src.resource_name if src != null else ""
			var m: Material
			match nm:
				"Paint":
					if paint_mat == null:
						paint_mat = CarMaterials.make_paint(Color(0.8, 0.1, 0.08), 1)
					m = paint_mat
				"Rim":
					if rim_mat == null:
						rim_mat = CarMaterials.make_rim(Color(0.75, 0.76, 0.78))
					m = rim_mat
				"LightHead", "LightTail", "LightReverse", "LightIndicator":
					if not light_mats.has(nm):
						light_mats[nm] = CarMaterials.make_light(nm)
					m = light_mats[nm]
				_:
					m = CarMaterials.shared(nm)
			mi.set_surface_override_material(i, m)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		if String(mi.name).ends_with("_Interior") or String(mi.name).ends_with("_Steering"):
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if String(mi.name).ends_with("_Glass"):
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _make_headlights() -> void:
	for side: String in ["HeadL", "HeadR"]:
		if not sockets.has(side):
			continue
		var s := SpotLight3D.new()
		s.name = "Spot_" + side
		var xf: Transform3D = sockets[side]
		s.position = xf.origin + Vector3(0, 0, -0.05)
		s.rotation_degrees = Vector3(-4.0, 0, 0)
		s.spot_range = 70.0
		s.spot_angle = 34.0
		s.spot_attenuation = 0.8
		s.light_energy = 5.0
		s.light_color = Color(1.0, 0.95, 0.85)
		s.shadow_enabled = side == "HeadL"
		s.visible = false
		s.distance_fade_enabled = true
		s.distance_fade_begin = 120.0
		s.distance_fade_length = 40.0
		add_child(s)
		head_spots.append(s)


func set_headlights(on: bool) -> void:
	_headlights = on
	for s in head_spots:
		s.visible = on
	if light_mats.has("LightHead"):
		(light_mats["LightHead"] as StandardMaterial3D).emission_energy_multiplier = 5.0 if on else 0.4
	_update_tail()


func _update_tail() -> void:
	if light_mats.has("LightTail"):
		var base := 1.4 if _headlights else 0.3
		(light_mats["LightTail"] as StandardMaterial3D).emission_energy_multiplier = lerpf(base, 6.0, _brake_level)


func set_brake(on: bool) -> void:
	var bl := 1.0 if on else 0.0
	if not is_equal_approx(bl, _brake_level):
		_brake_level = bl
		_update_tail()


func flash_headlights() -> void:
	if light_mats.has("LightHead"):
		(light_mats["LightHead"] as StandardMaterial3D).emission_energy_multiplier = 9.0
		get_tree().create_timer(0.25).timeout.connect(func() -> void: set_headlights(_headlights))


func set_paint(color: Color, finish: int, stripe_mode := 0, stripe_color := Color.WHITE) -> void:
	if paint_mat != null:
		CarMaterials.apply_paint(paint_mat, color, finish, stripe_mode, stripe_color)


func set_rim_color(c: Color) -> void:
	if rim_mat != null:
		rim_mat.albedo_color = c


func set_wetness(w: float) -> void:
	if paint_mat != null:
		paint_mat.set_shader_parameter("wetness", w)


func set_interior_visible(v: bool) -> void:
	if interior_mesh != null:
		interior_mesh.visible = true
	if body_mesh != null:
		body_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON


func wheel_rest_positions() -> Array[Vector3]:
	return wheel_rest


func body_aabb() -> AABB:
	return _body_aabb


func build_collision_shape() -> Shape3D:
	var pts := PackedVector3Array()
	if body_mesh != null and body_mesh.mesh != null:
		var hull := body_mesh.mesh.create_convex_shape(true, true) as ConvexPolygonShape3D
		var xf := _rel_xf(body_mesh)
		var floor_y := _body_aabb.position.y + 0.04
		for p in hull.points:
			var q := xf * p
			q.y = maxf(q.y, floor_y)
			pts.append(q)
	var shape := ConvexPolygonShape3D.new()
	shape.points = pts
	return shape


func update_from_car(car: CarController) -> void:
	for i in mini(4, car.wheels.size()):
		var w := car.wheels[i]
		var piv := wheel_pivots[i]
		piv.position = w.rest_pos + Vector3.UP * (w.rest_ext - w.length)
		piv.rotation = Vector3(0.0, -w.steer, 0.0)
		wheel_spinners[i].rotation = Vector3(-w.spin, 0.0, 0.0)
	if steering_node != null:
		steering_node.transform.basis = steering_basis * Basis(Vector3(0, 0, 1), -car.steer_angle * 7.0)
	var bl := 1.0 if car.brake_out > 0.05 and not car.reversing else 0.0
	if not is_equal_approx(bl, _brake_level):
		_brake_level = bl
		_update_tail()
	if light_mats.has("LightReverse"):
		(light_mats["LightReverse"] as StandardMaterial3D).emission_energy_multiplier = 4.0 if car.reversing else 0.0
	if _headlights != car.lights_on:
		set_headlights(car.lights_on)
