class_name CarInput
extends Node
## Reads the Input Map and drives the player's CarController (keyboard smoothing).
## Disabled while a menu/console overlay is open or in photo mode.

var car: CarController
var enabled: bool = true
var _steer: float = 0.0
var _throttle: float = 0.0
var _brake: float = 0.0


func _ready() -> void:
	process_physics_priority = -10


func _physics_process(delta: float) -> void:
	if car == null or not is_instance_valid(car) or not enabled:
		# Disabled = the car is driven by something else (QA autopilot, benchmark).
		return
	var active := not Game.is_overlay_open() and not Game.photo_mode
	car.in_hold = not active and not Game.photo_mode
	if not active:
		car.in_throttle = 0.0
		car.in_brake = 0.0
		car.in_steer = 0.0
		car.in_handbrake = 0.0
		return
	var target := Input.get_action_strength("steer_right") - Input.get_action_strength("steer_left")
	# Keyboard steering: ramp in (slower at speed for stability), return to centre faster.
	var spd := car.speed_ms
	var rate_in := lerpf(5.0, 2.4, clampf(spd / 50.0, 0.0, 1.0))
	var rate := rate_in if absf(target) > absf(_steer) and signf(target) == signf(_steer) or _steer == 0.0 else 7.0
	_steer = move_toward(_steer, target, rate * delta)
	var thr := Input.get_action_strength("accelerate")
	var brk := Input.get_action_strength("brake")
	_throttle = move_toward(_throttle, thr, delta * (6.0 if thr > _throttle else 10.0))
	_brake = move_toward(_brake, brk, delta * (8.0 if brk > _brake else 12.0))
	car.in_steer = clampf(_steer, -1.0, 1.0)
	car.in_throttle = _throttle
	car.in_brake = _brake
	car.in_handbrake = Input.get_action_strength("handbrake")
	# One-frame requests; the controller queues them, so quick taps during a shift all count.
	if Input.is_action_just_pressed("gear_up"):
		car.in_shift_up = true
	if Input.is_action_just_pressed("gear_down"):
		car.in_shift_down = true


func _unhandled_input(event: InputEvent) -> void:
	if car == null or Game.is_overlay_open():
		return
	if event.is_action_pressed("headlights"):
		car.headlights_on = not car.headlights_on
	elif event.is_action_pressed("reset_car"):
		Game.respawn()
