class_name InputSetup
extends RefCounted
## Registers every Input Map action (keyboard; mouse look is handled by the camera) at startup so the
## mapping lives in code. Gamepad support is intentionally not provided.

const KEYS: Dictionary = {
	"throttle": [KEY_W, KEY_UP], "brake": [KEY_S, KEY_DOWN], "steer_left": [KEY_A, KEY_LEFT],
	"steer_right": [KEY_D, KEY_RIGHT], "handbrake": [KEY_SPACE], "horn": [KEY_H],
	"camera_next": [KEY_C], "look_back": [KEY_B], "reset_car": [KEY_R], "lights": [KEY_L],
	"shift_up": [KEY_E], "shift_down": [KEY_Q], "toggle_console": [KEY_QUOTELEFT],
	"garage": [KEY_TAB, KEY_F1], "debug_menu": [KEY_F2], "map": [KEY_M], "photo_mode": [KEY_P],
	"pause": [KEY_ESCAPE], "screenshot": [KEY_F12], "tuning": [KEY_F3], "start_event": [KEY_ENTER, KEY_KP_ENTER],
}
## actions read by code but without a key binding (camera free look uses the right mouse button)
const UNBOUND: PackedStringArray = ["look_left", "look_right", "look_up", "look_down"]


static func register() -> void:
	for action in KEYS:
		_ensure(action)
		for k in KEYS[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = k
			InputMap.action_add_event(action, ev)
	for action in UNBOUND:
		_ensure(action)


static func _ensure(action: String) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action, 0.2)
