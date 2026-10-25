class_name CarFactory
extends RefCounted
## Assembles a drivable CarController from a CarDefinition and its Blender-exported .glb:
## finds Wheel_*/Caliper_* pivots, builds convex collision from Collision_Hull (or boxes),
## applies runtime materials (paint/finish), collects attachment empties (CAM_*, FX_*, LIGHT_*).

const WHEEL_KEYS := ["FL", "FR", "RL", "RR"]

static var _suffix_re: RegEx


static func base_name(n: String) -> String:
	## strips Blender duplicate suffixes (".001" / "_001") so parts are found by their base name
	if _suffix_re == null:
		_suffix_re = RegEx.new()
		_suffix_re.compile("[._][0-9][0-9][0-9]$")
	return _suffix_re.sub(n, "")


static func find_part(root: Node, base: String) -> Node:
	for c in root.find_children("*", "", true, false):
		if base_name(String(c.name)) == base:
			return c
	return null


static func build(def: CarDefinition, color: Color, finish: int) -> CarController:
	var car := CarController.new()
	car.name = "Car_%s" % def.id
	car.collision_layer = CarController.LAYER_PLAYER
	car.collision_mask = CarController.LAYER_WORLD | CarController.LAYER_TRAFFIC
	var model := instantiate_model(def)
	model.name = "Model"
	car.add_child(model)

	# --- wheels (re-parented to the body so their transforms are in body space)
	var wheel_nodes := {}
	for key in WHEEL_KEYS:
		var n := find_part(model, "Wheel_" + key) as Node3D
		if n != null:
			_reparent_keep(n, car)
			wheel_nodes[key] = n
		var cal := find_part(model, "Caliper_" + key) as Node3D
		if cal != null:
			_reparent_keep(cal, car)
			wheel_nodes["Caliper_" + key] = cal
	if wheel_nodes.size() < 4 and def.fallback_wheel_positions.size() == 4:
		for i in 4:
			var key: String = WHEEL_KEYS[i]
			if not wheel_nodes.has(key):
				var d := Node3D.new()
				d.name = "Wheel_" + key
				d.position = def.fallback_wheel_positions[i]
				car.add_child(d)
				wheel_nodes[key] = d

	# --- collision
	var hull := find_part(model, "Collision_Hull") as MeshInstance3D
	var body_aabb := _visual_aabb(model, car)
	if hull != null and hull.mesh != null:
		var rel := relative_transform(hull, car)
		var shape := hull.mesh.create_convex_shape(true, false)
		var cs := CollisionShape3D.new()
		cs.name = "HullShape"
		cs.shape = shape
		cs.transform = rel
		car.add_child(cs)
		hull.get_parent().remove_child(hull)
		hull.queue_free()
	else:
		_add_box_collision(car, body_aabb)

	# --- materials
	var paint := CarMaterials.paint(color, finish)
	var lights := CarMaterials.apply(model, paint, true)
	for key in wheel_nodes:
		CarMaterials.apply(wheel_nodes[key], paint, false)
	car.set_meta("paint_material", paint)
	car.set_meta("light_materials", lights)

	# --- attachment points
	var points := {}
	for n in model.find_children("*", "Node3D", true, false):
		var nm := base_name(String(n.name))
		if nm.begins_with("CAM_") or nm.begins_with("FX_") or nm.begins_with("LIGHT_"):
			points[nm] = relative_transform(n, car)
	car.set_meta("points", points)
	var steering := find_part(model, "SteeringWheel") as Node3D
	if steering != null:
		car.set_meta("steering_wheel", steering)

	var body_size := body_aabb.size
	car.set_meta("body_aabb", body_aabb)
	car.setup(def, wheel_nodes, body_size)
	return car


static func instantiate_model(def: CarDefinition) -> Node3D:
	if def.model_path != "" and ResourceLoader.exists(def.model_path):
		var ps := load(def.model_path) as PackedScene
		if ps != null:
			return ps.instantiate() as Node3D
	push_warning("CarFactory: model missing for %s, using development stand-in" % def.id)
	return _standin_model(def)


static func relative_transform(n: Node, ancestor: Node) -> Transform3D:
	var t := Transform3D.IDENTITY
	var p: Node = n
	while p != null and p != ancestor:
		if p is Node3D:
			t = (p as Node3D).transform * t
		p = p.get_parent()
	return t


static func _reparent_keep(n: Node3D, new_parent: Node3D) -> void:
	var rel := relative_transform(n, new_parent)
	n.owner = null
	for c in n.find_children("*", "", true, false):
		c.owner = null
	n.get_parent().remove_child(n)
	new_parent.add_child(n)
	n.transform = rel


static func _visual_aabb(model: Node3D, car: Node3D) -> AABB:
	var result := AABB()
	var first := true
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null or base_name(String(mi.name)).begins_with("Collision"):
			continue
		var box := relative_transform(mi, car) * mi.mesh.get_aabb()
		if first:
			result = box
			first = false
		else:
			result = result.merge(box)
	if first:
		result = AABB(Vector3(-0.9, 0.2, -2.1), Vector3(1.8, 1.2, 4.2))
	return result


static func _add_box_collision(car: Node3D, aabb: AABB) -> void:
	var lower := BoxShape3D.new()
	var clearance := 0.22
	var h := maxf(aabb.size.y * 0.45, 0.3)
	lower.size = Vector3(aabb.size.x * 0.96, h, aabb.size.z * 0.97)
	var cs := CollisionShape3D.new()
	cs.name = "BoxLower"
	cs.shape = lower
	cs.position = Vector3(aabb.get_center().x, aabb.position.y + clearance + h * 0.5, aabb.get_center().z)
	car.add_child(cs)
	var upper := BoxShape3D.new()
	upper.size = Vector3(aabb.size.x * 0.8, aabb.size.y * 0.35, aabb.size.z * 0.5)
	var cs2 := CollisionShape3D.new()
	cs2.name = "BoxUpper"
	cs2.shape = upper
	cs2.position = Vector3(aabb.get_center().x, aabb.position.y + clearance + h + upper.size.y * 0.5, aabb.get_center().z + aabb.size.z * 0.05)
	car.add_child(cs2)


static func _standin_model(def: CarDefinition) -> Node3D:
	## Development stand-in only (used until the Blender model exists).
	var root := Node3D.new()
	var body := MeshInstance3D.new()
	body.name = "Body"
	var bm := BoxMesh.new()
	bm.size = Vector3(1.8, 0.6, 4.2)
	var mat := StandardMaterial3D.new()
	mat.resource_name = "Paint"
	bm.material = mat
	body.mesh = bm
	body.position = Vector3(0, 0.65, 0)
	root.add_child(body)
	var cab := MeshInstance3D.new()
	cab.name = "Cabin"
	var cm := BoxMesh.new()
	cm.size = Vector3(1.5, 0.5, 2.0)
	var gm := StandardMaterial3D.new()
	gm.resource_name = "Glass"
	cm.material = gm
	cab.mesh = cm
	cab.position = Vector3(0, 1.2, 0.2)
	root.add_child(cab)
	var pos := def.fallback_wheel_positions
	if pos.size() != 4:
		pos = PackedVector3Array([Vector3(-0.78, 0.33, -1.3), Vector3(0.78, 0.33, -1.3), Vector3(-0.78, 0.33, 1.3), Vector3(0.78, 0.33, 1.3)])
	for i in 4:
		var w := Node3D.new()
		w.name = "Wheel_" + WHEEL_KEYS[i]
		w.position = pos[i]
		var wm := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.33
		cyl.bottom_radius = 0.33
		cyl.height = 0.24
		var rm := StandardMaterial3D.new()
		rm.resource_name = "Rubber"
		cyl.material = rm
		wm.mesh = cyl
		wm.rotation = Vector3(0, 0, PI * 0.5)
		w.add_child(wm)
		root.add_child(w)
	return root
