class_name PlayerDriver
extends Node
## Reads the Input Map (keyboard) and feeds a CarController. Inputs are ramped for smoothness.

var car: CarController
var enabled := true
var _steer := 0.0
var _thr := 0.0
var _brk := 0.0


func _physics_process(delta: float) -> void:
	if car == null or not is_instance_valid(car):
		return
	if not enabled or Game.input_blocked():
		car.in_throttle = 0.0
		car.in_brake = 0.0 if car.speed_abs > 1.0 else 0.0
		car.in_steer = move_toward(car.in_steer, 0.0, delta * 4.0)
		car.in_handbrake = car.speed_abs < 1.0
		return
	var raw_steer := Input.get_axis("steer_left", "steer_right")
	var rate := 3.2 if absf(raw_steer) > absf(_steer) and signf(raw_steer) == signf(_steer) else 6.5
	_steer = move_toward(_steer, raw_steer, rate * delta)
	_thr = move_toward(_thr, Input.get_action_strength("throttle"), 7.0 * delta)
	_brk = move_toward(_brk, Input.get_action_strength("brake"), 9.0 * delta)
	car.in_steer = _steer
	car.in_throttle = _thr
	car.in_brake = _brk
	car.in_handbrake = Input.is_action_pressed("handbrake")


func _unhandled_input(event: InputEvent) -> void:
	if car == null or Game.input_blocked():
		return
	if event.is_action_pressed("shift_up"):
		car.request_shift(1)
	elif event.is_action_pressed("shift_down"):
		car.request_shift(-1)
	elif event.is_action_pressed("headlights"):
		car.lights_on = not car.lights_on
		Game.headlights_manual = true
	elif event.is_action_pressed("reset_car"):
		Game.reset_player_to_road()

