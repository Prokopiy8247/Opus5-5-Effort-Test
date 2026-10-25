extends Node3D
## Places baked buildings and landmarks (Blender kit pieces) with simple box collision, plus
## street lamps in front of houses whose lights are pooled near the camera at night, spinning
## wind-turbine rotors and the lighthouse beacon.

const HOUSE_KITS := ["house_a", "house_b", "house_c", "shop", "church", "gas_station", "diner", "chalet", "farmhouse"]

var world: Node
var lamps: Array[Vector3] = []          ## lamp head positions (lights pooled near the camera)
var _lamp_lights: Array[OmniLight3D] = []
var _rotors: Array[Node3D] = []
var _beacons: Array[OmniLight3D] = []
var _windows_lit := false
var placed := 0
var missing := {}


func setup(w: Node) -> void:
	world = w
	var wd: WorldData = world.wd
	var kit: Node = world.kit
	var by_kit := {}
	for b: Dictionary in wd.buildings:
		var k := String(b.kit)
		if not by_kit.has(k):
			by_kit[k] = []
		(by_kit[k] as Array).append(b)
	var lamp_xforms: Array[Transform3D] = []
	var body := StaticBody3D.new()
	body.name = "BuildingCollision"
	body.collision_layer = 1
	body.set_meta("surface", SurfaceData.Kind.CONCRETE)
	add_child(body)
	for k: String in by_kit:
		var list: Array = by_kit[k]
		var node: Node3D = kit.instance(k) if kit.has_piece(k) else null
		if node == null:
			missing[k] = list.size()
			node = _fallback(k)
		var aabb := _aabb_of(node)
		for b: Dictionary in list:
			var inst := node.duplicate() as Node3D
			inst.position = b.pos
			inst.rotation.y = float(b.yaw)
			add_child(inst)
			placed += 1
			var cs := CollisionShape3D.new()
			var bs := BoxShape3D.new()
			bs.size = Vector3(maxf(aabb.size.x, 0.5), maxf(aabb.size.y, 0.5), maxf(aabb.size.z, 0.5))
			cs.shape = bs
			cs.transform = Transform3D(Basis(Vector3.UP, float(b.yaw)), b.pos) * Transform3D(Basis.IDENTITY, aabb.get_center())
			body.add_child(cs)
			for r: Node in inst.find_children("*_Rotor", "Node3D", true, false):
				(r as Node3D).rotate_object_local(Vector3.FORWARD, randf() * TAU)
				_rotors.append(r as Node3D)
			if k == "lighthouse":
				var beacon := OmniLight3D.new()
				beacon.position = Vector3(0, 24.6, 0)
				beacon.light_color = Color(1.0, 0.92, 0.75)
				beacon.omni_range = 60.0
				beacon.light_energy = 6.0
				beacon.visible = false
				inst.add_child(beacon)
				_beacons.append(beacon)
			if k in HOUSE_KITS:
				# lamp post between the front door and the road; its head overhangs towards the road
				var basis := Basis(Vector3.UP, float(b.yaw))
				var fwd := basis * Vector3(0, 0, -1)
				var base: Vector3 = b.pos + fwd * (-aabb.position.z + 1.6)  # aabb.position.z = front face (-Z)
				base.y = world.wd.height_at(base.x, base.z) - 0.05
				lamp_xforms.append(Transform3D(basis, base))
				lamps.append(base + fwd * 1.35 + Vector3.UP * 5.75)
		node.queue_free()
	if kit.has_piece("street_lamp") and not lamp_xforms.is_empty():
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = kit.mesh("street_lamp")
		mm.instance_count = lamp_xforms.size()
		for i in lamp_xforms.size():
			mm.set_instance_transform(i, lamp_xforms[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "StreetLamps"
		mmi.multimesh = mm
		mmi.visibility_range_end = 900.0
		add_child(mmi)
	if not missing.is_empty():
		print("Structures: Blender kit pieces missing, using stand-ins: ", missing)
	for i in 10:
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.8, 0.55)
		l.light_energy = 2.2
		l.omni_range = 18.0
		l.shadow_enabled = false
		l.visible = false
		add_child(l)
		_lamp_lights.append(l)


func set_night(night: bool) -> void:
	_windows_lit = night
	var m := KitMaterials.get_mat("WindowLit", null) as StandardMaterial3D
	if m != null:
		m.emission_energy_multiplier = 1.6 if night else 0.0
	var lamp := KitMaterials.get_mat("Lamp", null) as StandardMaterial3D
	if lamp != null:
		lamp.emission_energy_multiplier = 4.0 if night else 0.2
	for bl in _beacons:
		bl.visible = night


func _process(delta: float) -> void:
	for r in _rotors:
		r.rotate_object_local(Vector3.FORWARD, delta * 1.6)
	if not _windows_lit:
		for l in _lamp_lights:
			l.visible = false
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var c := cam.global_position
	var near: Array = []
	for p in lamps:
		var d := p.distance_squared_to(c)
		if d < 160.0 * 160.0:
			near.append([d, p])
	near.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	for i in _lamp_lights.size():
		if i < near.size():
			_lamp_lights[i].position = near[i][1]
			_lamp_lights[i].visible = true
		else:
			_lamp_lights[i].visible = false


func _aabb_of(n: Node3D) -> AABB:
	var out := AABB()
	var first := true
	for c: Node in n.find_children("*", "MeshInstance3D", true, false):
		if String(c.name).ends_with("_Rotor"):
			continue  # spinning blades get no collision
		var mi := c as MeshInstance3D
		var xf := Transform3D.IDENTITY
		var cur: Node = mi
		while cur != null and cur != n:
			xf = (cur as Node3D).transform * xf
			cur = cur.get_parent()
		var a := xf * mi.get_aabb()
		out = a if first else out.merge(a)
		first = false
	if n is MeshInstance3D:
		out = (n as MeshInstance3D).get_aabb()
	return out


## Temporary stand-ins (box + roof) until the Blender settlement kit is exported.
func _fallback(k: String) -> Node3D:
	var size := Vector3(9, 6, 8)
	var col := Color(0.88, 0.82, 0.7)
	match k:
		"barn":
			size = Vector3(14, 8, 10)
			col = Color(0.6, 0.18, 0.12)
		"silo":
			size = Vector3(5, 14, 5)
			col = Color(0.75, 0.75, 0.72)
		"church":
			size = Vector3(10, 12, 18)
		"gas_station", "diner":
			size = Vector3(16, 5, 12)
			col = Color(0.9, 0.9, 0.88)
		"lighthouse":
			size = Vector3(5, 26, 5)
			col = Color(0.95, 0.95, 0.95)
		"castle":
			size = Vector3(26, 14, 22)
			col = Color(0.55, 0.52, 0.48)
		"wind_turbine":
			size = Vector3(3, 60, 3)
			col = Color(0.95, 0.95, 0.95)
		"festival":
			size = Vector3(30, 9, 20)
			col = Color(0.95, 0.4, 0.6)
		"viewpoint":
			size = Vector3(4, 1, 2)
			col = Color(0.4, 0.3, 0.2)
		"shed", "boathouse":
			size = Vector3(6, 4, 5)
			col = Color(0.5, 0.4, 0.3)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position.y = size.y * 0.5
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	mi.material_override = m
	var root := Node3D.new()
	root.add_child(mi)
	return root
