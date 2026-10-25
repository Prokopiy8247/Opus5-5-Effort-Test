class_name PlayerInput
extends Node
## Feeds keyboard input into the player car (with smoothing for digital steering).

var car: Car
var enabled: bool = true
var _steer: float = 0.0


func _physics_process(delta: float) -> void:
	if car == null or not is_instance_valid(car):
		return
	if not enabled:
		return
	var t: float = Input.get_action_strength("throttle")
	var b: float = Input.get_action_strength("brake")
	var raw: float = Input.get_action_strength("steer_right") - Input.get_action_strength("steer_left")
	var analog: bool = absf(raw) > 0.0 and absf(raw) < 0.99
	if analog:
		_steer = raw
	else:
		var spd: float = absf(car.speed)
		var rate: float = lerpf(4.5, 2.2, WorldData.smooth(0.0, 50.0, spd))
		if raw == 0.0:
			rate *= 1.8
		elif signf(raw) != signf(_steer):
			rate *= 2.0
		_steer = move_toward(_steer, raw, rate * delta)
	car.in_throttle = t
	car.in_brake = b
	car.in_steer = _steer
	car.in_handbrake = Input.is_action_pressed("handbrake")


func _unhandled_input(event: InputEvent) -> void:
	if car == null or not enabled:
		return
	if event.is_action_pressed("shift_up"):
		car.shift_manual(1)
	elif event.is_action_pressed("shift_down"):
		car.shift_manual(-1)
	elif event.is_action_pressed("lights"):
		car.set_lights(not car.lights_on)
		car.set_meta("manual_lights", true)
	elif event.is_action_pressed("reset_car"):
		get_tree().call_group("main", "reset_player_to_road")
