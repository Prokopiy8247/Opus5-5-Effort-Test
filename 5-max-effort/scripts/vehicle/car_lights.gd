class_name CarLights
extends Node
## Head/tail/brake/reverse lights. Headlights are real SpotLight3Ds on the player car (auto at
## night, toggle with L); light lenses are emissive materials driven per car.

var car: CarController
var headlights_on: bool = false
var auto_lights: bool = true
var use_spotlights: bool = true
var _spots: Array[SpotLight3D] = []
var _mats: Dictionary = {}


func setup(c: CarController, spotlights: bool) -> void:
	car = c
	use_spotlights = spotlights
	_mats = car.get_meta("light_materials", {})
	if spotlights:
		var points: Dictionary = car.get_meta("points", {})
		for key in ["LIGHT_Head_L", "LIGHT_Head_R"]:
			var t: Transform3D = points.get(key, Transform3D(Basis.IDENTITY, Vector3(0.6 if key.ends_with("R") else -0.6, 0.7, -2.0)))
			var s := SpotLight3D.new()
			s.name = key
			s.position = t.origin + Vector3(0, 0, -0.05)
			s.rotation = Vector3(deg_to_rad(-4.0), 0.0, 0.0)
			s.spot_range = 70.0
			s.spot_angle = 32.0
			s.spot_angle_attenuation = 0.8
			s.light_energy = 0.0
			s.light_color = Color(1.0, 0.95, 0.85)
			s.shadow_enabled = key.ends_with("L")
			s.light_specular = 0.4
			s.distance_fade_enabled = false
			car.add_child(s)
			_spots.append(s)


func night_factor() -> float:
	if Game.environment != null and Game.environment.has_method("get_darkness"):
		return float(Game.environment.call("get_darkness"))
	return 0.0


func _process(_delta: float) -> void:
	if car == null or not is_instance_valid(car):
		return
	if car.control_mode == CarController.ControlMode.PLAYER and Input.is_action_just_pressed("headlights") and not Game.ui_blocks_driving():
		auto_lights = false
		headlights_on = not headlights_on
		Game.show_notification("Headlights", "On" if headlights_on else "Off", "info")
	var dark := night_factor()
	var on := headlights_on if not auto_lights else dark > 0.35
	var spot_e := 3.2 if on else 0.0
	for s in _spots:
		s.light_energy = spot_e
		s.visible = on
	var head: StandardMaterial3D = _mats.get("head")
	if head != null:
		head.emission_energy_multiplier = 6.0 if on else 0.4
	var tail: StandardMaterial3D = _mats.get("tail")
	if tail != null:
		var braking := car.input_brake > 0.1 and not car.reversing or (car.reversing and car.input_throttle > 0.1)
		var e := 0.5 + (1.6 if on else 0.0) + (4.0 if braking else 0.0)
		tail.emission_energy_multiplier = e
	var rev: StandardMaterial3D = _mats.get("reverse")
	if rev != null:
		rev.emission_energy_multiplier = 3.0 if car.gear < 0 else 0.0
