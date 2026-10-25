class_name Rewind
extends Node
## Hold Backspace to rewind the player car through the last 10 seconds (30 snapshots per second).
## Releasing resumes with the velocities recorded at that moment.

const RATE := 30.0
const MAX := 300

var _buf: Array = []          ## [Transform3D, linear velocity, angular velocity]
var _acc := 0.0
var _car: CarController
var rewinding := false


func _physics_process(delta: float) -> void:
	var car := Game.player
	if car == null or not is_instance_valid(car):
		return
	if car != _car:
		_car = car
		_buf.clear()
	var want := Input.is_action_pressed("rewind") and not Game.input_blocked()
	if want and _buf.size() > 1:
		if not rewinding:
			rewinding = true
			Game.notify("Rewind", "", "small")
		_acc += delta
		while _acc >= 1.0 / RATE and _buf.size() > 1:
			_buf.pop_back()
			_acc -= 1.0 / RATE
		var e: Array = _buf[-1]
		car.global_transform = e[0]
		car.linear_velocity = Vector3.ZERO
		car.angular_velocity = Vector3.ZERO
		return
	if rewinding:
		rewinding = false
		var e: Array = _buf[-1]
		car.global_transform = e[0]
		car.linear_velocity = e[1]
		car.angular_velocity = e[2]
		_acc = 0.0
	_acc += delta
	if _acc >= 1.0 / RATE:
		_acc = 0.0
		if not _buf.is_empty() and (_buf[-1][0] as Transform3D).origin.distance_to(car.global_position) > 40.0:
			_buf.clear()  # teleported: history no longer applies
		_buf.append([car.global_transform, car.linear_velocity, car.angular_velocity])
		if _buf.size() > MAX:
			_buf.pop_front()
