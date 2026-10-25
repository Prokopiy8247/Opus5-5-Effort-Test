class_name RewindBuffer
extends Node
## Rewind (hold Backspace): keeps the last 12 s of the player car's state at 20 Hz. Holding the
## key scrubs the car back through it at double speed; releasing resumes from that moment with
## the recorded velocity. Only the player car rewinds (traffic and the world keep running).

const RATE := 20.0
const SECONDS := 12.0

var _buf: Array = []          # [{xf, v, w, speed}]
var _acc := 0.0
var _scrub := 0.0
var _rewinding := false
var _idx := 0
var _car_id := 0


func _physics_process(delta: float) -> void:
	var car := Game.player_car
	if car == null or not is_instance_valid(car):
		_buf.clear()
		return
	if car.get_instance_id() != _car_id:
		_car_id = car.get_instance_id()
		_buf.clear()
		_rewinding = false
	var held := Input.is_action_pressed("rewind") and not Game.ui_blocks_driving()
	if held and (_rewinding or _buf.size() > 4):
		if not _rewinding:
			_rewinding = true
			_idx = _buf.size() - 1
			_scrub = 0.0
			car.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
			car.freeze = true
			if Game.hud != null:
				Game.hud.call("show_center", "◀◀ REWIND", 0.6, UiTheme.ACCENT2)
		_scrub += delta * RATE * 2.0
		while _scrub >= 1.0 and _idx > 0:
			_scrub -= 1.0
			_idx -= 1
		var s: Dictionary = _buf[_idx]
		car.global_transform = s["xf"]
		if Game.hud != null and Engine.get_physics_frames() % 30 == 0:
			Game.hud.call("show_center", "◀◀ REWIND", 0.6, UiTheme.ACCENT2)
		return
	if _rewinding:
		_rewinding = false
		var s: Dictionary = _buf[_idx]
		_buf.resize(_idx + 1)
		car.freeze = false
		car.reset_to(s["xf"], float(s["speed"]))
		car.linear_velocity = s["v"]
		car.angular_velocity = s["w"]
		return
	_acc += delta
	if _acc >= 1.0 / RATE:
		_acc = 0.0
		_buf.append({"xf": car.global_transform, "v": car.linear_velocity, "w": car.angular_velocity,
			"speed": maxf(car.forward_speed, 0.0)})
		if _buf.size() > int(RATE * SECONDS):
			_buf.pop_front()
