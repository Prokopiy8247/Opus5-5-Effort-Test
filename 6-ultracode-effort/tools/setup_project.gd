extends SceneTree
## Reproducible project configuration: run with
##   Godot_console.exe --headless --path <project> --script res://tools/setup_project.gd
## Writes project settings (physics, rendering, autoloads, layers) and the full Input Map to project.godot.

const AUTOLOADS := {
	"Settings": "*res://scripts/core/settings.gd",
	"Game": "*res://scripts/core/game.gd",
	"SaveGame": "*res://scripts/core/save_game.gd",
}

func _init() -> void:
	var s := {
		"application/config/name": "Sunward Roads",
		"application/config/description": "Original open-world arcade-sim racing on long countryside roads.",
		"application/run/main_scene": "res://scenes/main.tscn",
		"application/config/icon": "res://icon.svg",
		"display/window/size/viewport_width": 1920,
		"display/window/size/viewport_height": 1080,
		"display/window/size/window_width_override": 1600,
		"display/window/size/window_height_override": 900,
		"display/window/stretch/mode": "canvas_items",
		"display/window/stretch/aspect": "expand",
		"display/window/vsync/vsync_mode": 1,
		"physics/common/physics_ticks_per_second": 120,
		"physics/common/max_physics_steps_per_frame": 10,
		"physics/common/physics_interpolation": true,
		"physics/3d/physics_engine": "Jolt Physics",
		"physics/jolt_physics_3d/simulation/allow_sleep": true,
		"physics/jolt_physics_3d/limits/max_linear_velocity": 250.0,
		"physics/jolt_physics_3d/limits/world_boundary_shape_size": 8000.0,
		"rendering/anti_aliasing/quality/msaa_3d": 0,
		"rendering/anti_aliasing/quality/screen_space_aa": 1,
		"rendering/anti_aliasing/quality/use_taa": true,
		"rendering/lights_and_shadows/directional_shadow/size": 4096,
		"rendering/lights_and_shadows/directional_shadow/soft_shadow_filter_quality": 3,
		"rendering/lights_and_shadows/positional_shadow/atlas_size": 2048,
		"rendering/environment/defaults/default_clear_color": Color(0.55, 0.7, 0.9),
		"rendering/mesh_lod/lod_change/threshold_pixels": 1.0,
		"rendering/occlusion_culling/use_occlusion_culling": true,
		"rendering/textures/default_filters/anisotropic_filtering_level": 3,
		"audio/driver/mix_rate": 44100,
		# Never let the editor import the master .blend (it would spawn Blender); we export .glb ourselves.
		"filesystem/import/blender/enabled": false,
		"filesystem/import/fbx2gltf/enabled": false,
		"layer_names/3d_physics/layer_1": "world",
		"layer_names/3d_physics/layer_2": "player",
		"layer_names/3d_physics/layer_3": "traffic",
		"layer_names/3d_physics/layer_4": "triggers",
		"layer_names/3d_physics/layer_5": "props_dynamic",
	}
	for k: String in s:
		ProjectSettings.set_setting(k, s[k])

	for name: String in AUTOLOADS:
		ProjectSettings.set_setting("autoload/" + name, AUTOLOADS[name])

	_setup_input()
	var err := ProjectSettings.save()
	print("setup_project: saved project.godot err=", err)
	quit(0 if err == OK else 1)


func _key(code: Key) -> InputEventKey:
	var e := InputEventKey.new()
	e.physical_keycode = code
	return e


func _mouse(b: MouseButton) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = b
	return e


func _action(name: String, events: Array, deadzone: float = 0.2) -> void:
	ProjectSettings.set_setting("input/" + name, {"deadzone": deadzone, "events": events})


func _setup_input() -> void:
	# Keyboard + mouse only (gamepad support intentionally not provided - user decision).
	for old: String in ["look_left", "look_right", "look_up", "look_down"]:
		if ProjectSettings.has_setting("input/" + old):
			ProjectSettings.clear("input/" + old)
	# Driving
	_action("accelerate", [_key(KEY_W), _key(KEY_UP)], 0.05)
	_action("brake", [_key(KEY_S), _key(KEY_DOWN)], 0.05)
	_action("steer_left", [_key(KEY_A), _key(KEY_LEFT)], 0.12)
	_action("steer_right", [_key(KEY_D), _key(KEY_RIGHT)], 0.12)
	_action("handbrake", [_key(KEY_SPACE)])
	_action("gear_up", [_key(KEY_E)])
	_action("gear_down", [_key(KEY_Q)])
	_action("horn", [_key(KEY_H)])
	_action("headlights", [_key(KEY_L)])
	_action("reset_car", [_key(KEY_R)])
	_action("rewind", [_key(KEY_BACKSPACE)])
	# Camera
	_action("camera_next", [_key(KEY_C)])
	_action("look_back", [_key(KEY_B)])
	_action("free_look", [_mouse(MOUSE_BUTTON_RIGHT)])
	# Menus / tools
	_action("toggle_console", [_key(KEY_QUOTELEFT), _key(KEY_F10)])
	_action("toggle_garage", [_key(KEY_F1), _key(KEY_TAB)])
	_action("toggle_debug_menu", [_key(KEY_F2)])
	_action("toggle_map", [_key(KEY_M)])
	_action("toggle_hud", [_key(KEY_F3)])
	_action("toggle_photo_mode", [_key(KEY_P)])
	_action("toggle_telemetry", [_key(KEY_F4)])
	_action("screenshot", [_key(KEY_F12)])
	_action("pause", [_key(KEY_ESCAPE)])
	_action("ui_tab_next", [_key(KEY_PAGEDOWN)])
	_action("ui_tab_prev", [_key(KEY_PAGEUP)])
