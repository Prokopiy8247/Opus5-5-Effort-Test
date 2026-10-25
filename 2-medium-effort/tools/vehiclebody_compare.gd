extends Node
## Prototype comparison: Godot's built-in VehicleBody3D vs the project raycast Car on the same flat strip
## (120 Hz physics): full throttle for 40 s, then a steering step at speed. Run via the QA runner:
## godot --path . -- --qa --qa-mode=compare

var strip: StaticBody3D
var results: PackedStringArray = []


var physics_frame: Signal


func run() -> PackedStringArray:
	physics_frame = get_tree().physics_frame
	var w := Node3D.new()
	add_child(w)
	strip = StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(600, 2, 14000)
	cs.shape = bs
	strip.add_child(cs)
	strip.set_meta("road_surface", 0)
	w.add_child(strip)
	strip.position = Vector3(0, 1999, 0)
	await _test_vehiclebody(w)
	await _test_raycast(w)
	w.queue_free()
	return results


func _test_vehiclebody(w: Node3D) -> void:
	var vb := VehicleBody3D.new()
	vb.mass = 1460.0
	var body := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = Vector3(1.9, 0.7, 4.4)
	body.shape = b
	body.position = Vector3(0, 0.7, 0)
	vb.add_child(body)
	for p in [Vector3(-0.85, 0.35, -1.4), Vector3(0.85, 0.35, -1.4), Vector3(-0.85, 0.35, 1.3), Vector3(0.85, 0.35, 1.3)]:
		var wh := VehicleWheel3D.new()
		wh.position = p
		wh.wheel_radius = 0.35
		wh.wheel_rest_length = 0.2
		wh.suspension_stiffness = 60.0
		wh.suspension_max_force = 12000.0
		wh.damping_compression = 1.2
		wh.damping_relaxation = 1.6
		wh.wheel_friction_slip = 3.0
		wh.use_as_traction = true
		wh.use_as_steering = p.z < 0.0
		vb.add_child(wh)
	w.add_child(vb)
	vb.global_position = Vector3(0, 2001.0, 6500)
	await physics_frame
	var t: float = 0.0
	var vmax: float = 0.0
	var max_roll: float = 0.0
	var max_yaw: float = 0.0
	while t < 40.0:
		var v: float = vb.linear_velocity.length()
		# ~585 kW equivalent force cap
		vb.engine_force = minf(9000.0, 585000.0 / maxf(v, 5.0))
		vb.steering = 0.0
		await physics_frame
		t += 1.0 / 120.0
		vmax = maxf(vmax, vb.linear_velocity.length() * 3.6)
	var tsteer: float = 0.0
	while tsteer < 3.0:
		vb.steering = 0.05
		await physics_frame
		tsteer += 1.0 / 120.0
		max_roll = maxf(max_roll, absf(rad_to_deg(vb.global_transform.basis.get_euler().z)))
		max_yaw = maxf(max_yaw, absf(vb.angular_velocity.y))
	var flipped: bool = vb.global_transform.basis.y.y < 0.5
	results.append("VehicleBody3D : vmax %.0f km/h, steer step @speed -> max roll %.1f deg, max yaw %.2f rad/s, flipped=%s" % [vmax, max_roll, max_yaw, str(flipped)])
	vb.queue_free()


func _test_raycast(w: Node3D) -> void:
	var game: Node = get_node_or_null("/root/Game")
	var def: CarDef = load("res://data/cars/super.tres")
	var car := Car.new()
	car.setup(def)
	w.add_child(car)
	car.global_position = Vector3(50, 2000.8, 6500)
	await physics_frame
	var t: float = 0.0
	var vmax: float = 0.0
	var max_roll: float = 0.0
	var max_yaw: float = 0.0
	while t < 40.0:
		car.in_throttle = 1.0
		car.in_steer = clampf(-(car.global_position.x - 50.0) * 0.05, -0.1, 0.1)
		await physics_frame
		t += 1.0 / 120.0
		vmax = maxf(vmax, car.kmh())
	var tsteer: float = 0.0
	while tsteer < 3.0:
		car.in_steer = 0.35
		await physics_frame
		tsteer += 1.0 / 120.0
		max_roll = maxf(max_roll, absf(rad_to_deg(car.global_transform.basis.get_euler().z)))
		max_yaw = maxf(max_yaw, absf(car.angular_velocity.y))
	var flipped: bool = car.global_transform.basis.y.y < 0.5
	results.append("Raycast Car   : vmax %.0f km/h, steer step @speed -> max roll %.1f deg, max yaw %.2f rad/s, flipped=%s (Game autoload %s)" % [vmax, max_roll, max_yaw, str(flipped), "present" if game else "absent"])
