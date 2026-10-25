extends RefCounted
## Brake-disc heat: braking power heats each disc, airflow cools it; hot discs glow through the rims.
## Works on the model's `BrakeDisc*` material surfaces (duplicated per wheel); no-op for placeholder cars.

const CAPACITY_J := 750000.0
const GLOW_START := 0.4

var _car: CarController
var _mats: Array[StandardMaterial3D] = []
var _heat: PackedFloat32Array = []
var _sent: PackedFloat32Array = []


func setup(car: CarController) -> bool:
	_car = car
	var found := false
	for w in car.wheels:
		var m: StandardMaterial3D = _find_disc(w.node) if w.node != null else null
		_mats.append(m)
		found = found or m != null
	_heat.resize(_mats.size())
	_heat.fill(0.0)
	_sent.resize(_mats.size())
	_sent.fill(0.0)
	return found


func _find_disc(root: Node) -> StandardMaterial3D:
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		stack.append_array(n.get_children())
		var mi := n as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		for i in mi.mesh.get_surface_count():
			var mat := mi.mesh.surface_get_material(i)
			if mat is StandardMaterial3D and mat.resource_name.begins_with("BrakeDisc"):
				var d: StandardMaterial3D = mat.duplicate()
				d.emission_enabled = true
				d.emission = Color(0.6, 0.05, 0.01)
				d.emission_energy_multiplier = 0.0
				mi.set_surface_override_material(i, d)
				return d
	return null


func update(delta: float) -> void:
	var v := _car.speed_ms
	var ground := absf(_car.forward_speed)
	for i in _mats.size():
		var m := _mats[i]
		if m == null:
			continue
		var w := _car.wheels[i]
		var power := 0.0
		if w.contact and w.brake_force > 1.0:
			# Ground speed rather than wheel speed: ABS cycling reads as brief lock-ups in the tyre model.
			power = minf(w.brake_force, w.load * 1.3) * ground
			if not _car.assist_abs and w.skid > 0.7:
				power *= 0.3
		var h := _heat[i] + power * delta / CAPACITY_J
		h -= h * (0.03 + v * 0.0012) * delta
		_heat[i] = clampf(h, 0.0, 1.3)
		var g := clampf((_heat[i] - GLOW_START) / (1.0 - GLOW_START), 0.0, 1.0)
		if absf(g - _sent[i]) > 0.015 or (g == 0.0 and _sent[i] != 0.0):
			_sent[i] = g
			m.emission = Color(0.6, 0.05, 0.01).lerp(Color(1.0, 0.3, 0.05), g)
			m.emission_energy_multiplier = g * g * 2.4


func max_heat() -> float:
	var m := 0.0
	for h in _heat:
		m = maxf(m, h)
	return m
