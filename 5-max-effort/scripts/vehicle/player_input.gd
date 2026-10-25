class_name PlayerInput
extends Node
## Reads the Input Map and writes driver inputs into the player's CarController.
## Keyboard steering is ramped (speed-sensitive); analogue sticks get a progressive curve.

var car: CarController
var enabled: bool = true
var _steer: float = 0.0


func _physics_process(delta: float) -> void:
	if car == null or not is_instance_valid(car):
		return
	if not enabled or Game.ui_blocks_driving():
		car.input_throttle = 0.0
		car.input_brake = 0.0
		car.input_handbrake = 0.0
		_steer = move_toward(_steer, 0.0, delta * 6.0)
		car.input_steer = _steer
		return
	var raw := Input.get_axis("steer_left", "steer_right")
	var mag := absf(raw)
	var analog := mag > 0.001 and absf(mag - 1.0) > 0.001
	if analog:
		var target := signf(raw) * pow(mag, 1.45)
		_steer = move_toward(_steer, target, delta * 9.0)
	else:
		var spd := clampf(absf(car.forward_speed) / 60.0, 0.0, 1.0)
		if mag < 0.001:
			_steer = move_toward(_steer, 0.0, delta * lerpf(6.0, 4.0, spd))
		else:
			var rate := lerpf(4.2, 1.8, spd)
			if signf(raw) != signf(_steer) and absf(_steer) > 0.01:
				rate *= 2.2
			_steer = move_toward(_steer, raw, delta * rate)
	car.input_steer = _steer
	car.input_throttle = Input.get_action_strength("accelerate")
	car.input_brake = Input.get_action_strength("brake")
	car.input_handbrake = Input.get_action_strength("handbrake")
	if Input.is_action_just_pressed("shift_up"):
		car.input_shift_up = true
	if Input.is_action_just_pressed("shift_down"):
		car.input_shift_down = true
