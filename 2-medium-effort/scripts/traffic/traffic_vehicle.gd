class_name TrafficVehicle
extends RigidBody3D
## One pooled civilian vehicle. Kinematic (frozen) while driven by the TrafficManager; turns into a
## dynamic body after a hard hit, then becomes a stopped obstacle until it is recycled.

var kind: String = ""
var active: bool = false
var road: int = 0
var dir: int = 1
var s: float = 0.0
var v: float = 0.0
var v_pref: float = 20.0
var length: float = 4.5
var half_w: float = 0.9
var lane_off: float = 0.0
var overtake: float = 0.0  # 0 own lane .. 1 opposite lane
var overtake_left: float = 0.0
var wait_t: float = 0.0
var stopped_t: float = 0.0
var wrecked: bool = false
var wreck_t: float = 0.0
var near: bool = false
var horn_t: float = 0.0
var lod_tick: int = 0
var wheels: Array[Node3D] = []
var wheel_r: float = 0.33
var wheel_spin: float = 0.0
var paint: StandardMaterial3D
var tail: StandardMaterial3D
var head: StandardMaterial3D
var prev_pos: Vector3 = Vector3.ZERO
var yaw_smooth: Basis = Basis()


func setup(k: String, scene: PackedScene, color: Color) -> void:
	kind = k
	name = "Traffic_" + k
	collision_layer = 8
	collision_mask = 1 | 4 | 8
	mass = {"t_lorry": 9000.0, "t_bus": 11000.0, "t_tractor": 4000.0, "t_van": 2200.0}.get(k, 1300.0)
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	freeze = true
	continuous_cd = true
	can_sleep = true
	var pm := PhysicsMaterial.new()
	pm.friction = 0.6
	physics_material_override = pm
	var model: Node3D = scene.instantiate()
	add_child(model)
	paint = StandardMaterial3D.new()
	paint.albedo_color = color
	paint.metallic = 0.3
	paint.roughness = 0.35
	tail = StandardMaterial3D.new()
	tail.albedo_color = Color(0.5, 0.02, 0.02)
	tail.emission_enabled = true
	tail.emission = Color(1, 0.05, 0.02)
	tail.emission_energy_multiplier = 0.5
	head = StandardMaterial3D.new()
	head.albedo_color = Color(0.9, 0.9, 0.85)
	head.emission_enabled = true
	head.emission = Color(1, 0.95, 0.8)
	head.emission_energy_multiplier = 0.3
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.06, 0.08, 0.1, 0.75)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.roughness = 0.05
	glass.metallic = 0.4
	var aabb := AABB()
	var first: bool = true
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var m3: MeshInstance3D = mi
		m3.visibility_range_end = 700.0
		if m3.name.begins_with("Interior") or m3.name.begins_with("SteeringWheel") or m3.name.begins_with("Brake"):
			m3.visibility_range_end = 60.0
		for si in m3.mesh.get_surface_count():
			var mat: Material = m3.mesh.surface_get_material(si)
			if mat == null:
				continue
			var mn: String = mat.resource_name
			if mn.begins_with("Paint"):
				m3.set_surface_override_material(si, paint)
			elif mn.begins_with("TailLight"):
				m3.set_surface_override_material(si, tail)
			elif mn.begins_with("HeadLight"):
				m3.set_surface_override_material(si, head)
			elif mn.begins_with("Glass"):
				m3.set_surface_override_material(si, glass)
		if m3.name.begins_with("Wheel_"):
			wheels.append(m3)
			wheel_r = m3.mesh.get_aabb().size.y * 0.5
		if m3.name.begins_with("Body"):
			var bb: AABB = m3.transform * m3.mesh.get_aabb()
			aabb = bb if first else aabb.merge(bb)
			first = false
	length = aabb.size.z
	half_w = aabb.size.x * 0.5
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(aabb.size.x * 0.95, aabb.size.y * 0.85, aabb.size.z * 0.97)
	cs.shape = box
	cs.position = aabb.get_center() + Vector3(0, aabb.size.y * 0.05, 0)
	add_child(cs)
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3(0, aabb.size.y * 0.35, 0)
	deactivate()


func deactivate() -> void:
	active = false
	wrecked = false
	visible = false
	freeze = true
	collision_layer = 0
	collision_mask = 0
	global_position = Vector3(0, -500, 0)


func activate(ri: int, d: int, ss: float, speed_pref: float, lane: float) -> void:
	active = true
	wrecked = false
	visible = true
	freeze = true
	road = ri
	dir = d
	s = ss
	v = speed_pref * 0.8
	v_pref = speed_pref
	lane_off = lane
	overtake = 0.0
	wait_t = 0.0
	stopped_t = 0.0
	prev_pos = Vector3.INF
	yaw_smooth = Basis()


func set_near(n: bool) -> void:
	near = n
	collision_layer = 8 if n or wrecked else 0
	collision_mask = (1 | 4 | 8) if n or wrecked else 0


func wreck(impulse: Vector3) -> void:
	if wrecked:
		return
	wrecked = true
	wreck_t = 0.0
	var vel: Vector3 = (global_transform.basis * Vector3(0, 0, -1)) * v
	freeze = false
	set_near(true)
	linear_velocity = vel
	apply_central_impulse(impulse)
	v = 0.0
	tail.emission_energy_multiplier = 3.0


func set_lights(braking: bool, night: bool) -> void:
	tail.emission_energy_multiplier = 4.0 if braking else (1.2 if night else 0.3)
	head.emission_energy_multiplier = 4.0 if night else 0.3


func flash() -> void:
	head.emission_energy_multiplier = 8.0
