extends SceneTree
## Reproducible project configuration: project settings, autoloads and the Input Map.
## Controls are keyboard + mouse only (gamepad support intentionally not included, per user request).
## Run:  Godot_console.exe --headless --path <project> --script res://tools/setup_project.gd

const GAME_TITLE := "Ridgeline Festival"


func _initialize() -> void:
	var s := ProjectSettings
	s.set_setting("application/config/name", GAME_TITLE)
	s.set_setting("application/config/description", "Original open-world arcade-sim racing game: long countryside roads, a 10-car garage, civilian traffic.")
	s.set_setting("application/run/main_scene", "res://scenes/main.tscn")
	s.set_setting("application/config/icon", "res://icon.svg")

	# Window / display
	s.set_setting("display/window/size/viewport_width", 1920)
	s.set_setting("display/window/size/viewport_height", 1080)
	s.set_setting("display/window/size/window_width_override", 1600)
	s.set_setting("display/window/size/window_height_override", 900)
	s.set_setting("display/window/stretch/mode", "canvas_items")
	s.set_setting("display/window/stretch/aspect", "expand")
	s.set_setting("display/window/vsync/vsync_mode", 1)

	# Physics: Jolt at 120 Hz with interpolation for smooth rendering at any frame rate.
	s.set_setting("physics/3d/physics_engine", "Jolt Physics")
	s.set_setting("physics/common/physics_ticks_per_second", 120)
	s.set_setting("physics/common/max_physics_steps_per_frame", 8)
	s.set_setting("physics/common/physics_interpolation", true)
	s.set_setting("physics/jolt_physics_3d/limits/max_bodies", 10240)

	# Rendering (Forward+). Values chosen by measurement, see DEVELOPMENT.md.
	s.set_setting("rendering/anti_aliasing/quality/msaa_3d", 2)
	s.set_setting("rendering/anti_aliasing/quality/screen_space_aa", 2)
	s.set_setting("rendering/anti_aliasing/quality/use_debanding", true)
	s.set_setting("rendering/lights_and_shadows/directional_shadow/size", 4096)
	s.set_setting("rendering/lights_and_shadows/directional_shadow/soft_shadow_filter_quality", 3)
	s.set_setting("rendering/textures/default_filters/anisotropic_filtering_level", 4)

	# Autoloads
	s.set_setting("autoload/Game", "*res://scripts/core/game.gd")

	_setup_inputs()
	var err := ProjectSettings.save()
	print("[setup_project] ProjectSettings.save() -> ", error_string(err))
	quit(0 if err == OK else 1)


func _key(code: Key) -> InputEventKey:
	var e := InputEventKey.new()
	e.physical_keycode = code
	e.device = -1
	return e


func _btn(b: JoyButton) -> InputEventJoypadButton:
	var e := InputEventJoypadButton.new()
	e.button_index = b
	e.device = -1
	return e


func _axis(axis: JoyAxis, value: float) -> InputEventJoypadMotion:
	var e := InputEventJoypadMotion.new()
	e.axis = axis
	e.axis_value = value
	e.device = -1
	return e


func _mouse(b: MouseButton) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = b
	e.device = -1
	return e


func _add(action: String, events: Array, deadzone: float = 0.2) -> void:
	ProjectSettings.set_setting("input/" + action, {"deadzone": deadzone, "events": events})


func _setup_inputs() -> void:
	# Driving
	_add("accelerate", [_key(KEY_W), _key(KEY_UP)], 0.05)
	_add("brake", [_key(KEY_S), _key(KEY_DOWN)], 0.05)
	_add("steer_left", [_key(KEY_A), _key(KEY_LEFT)], 0.12)
	_add("steer_right", [_key(KEY_D), _key(KEY_RIGHT)], 0.12)
	_add("handbrake", [_key(KEY_SPACE)])
	_add("shift_up", [_key(KEY_E)])
	_add("shift_down", [_key(KEY_Q)])
	_add("horn", [_key(KEY_H)])
	_add("headlights", [_key(KEY_L)])
	_add("reset_car", [_key(KEY_R)])
	_add("rewind", [_key(KEY_BACKSPACE)])
	# Camera
	_add("camera_cycle", [_key(KEY_C)])
	_add("look_back", [_key(KEY_V)])
	_add("look_left", [], 0.2)
	_add("look_right", [], 0.2)
	_add("look_up", [], 0.2)
	_add("look_down", [], 0.2)
	_add("free_look", [_mouse(MOUSE_BUTTON_RIGHT)])
	# Menus and tools
	_add("toggle_console", [_key(KEY_QUOTELEFT)])
	_add("toggle_garage", [_key(KEY_F1), _key(KEY_TAB)])
	_add("toggle_debug", [_key(KEY_F3)])
	_add("toggle_map", [_key(KEY_M)])
	_add("toggle_hud", [_key(KEY_F2)])
	_add("photo_mode", [_key(KEY_P)])
	_add("screenshot", [_key(KEY_F12)])
	_add("pause_menu", [_key(KEY_ESCAPE)])
	_add("cam_up", [_key(KEY_E)])
	_add("cam_down", [_key(KEY_Q)])
	_add("cam_fast", [_key(KEY_SHIFT)])
