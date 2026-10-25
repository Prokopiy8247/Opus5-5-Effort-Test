extends SceneTree
## Reproducible project configuration: input map, physics, rendering, autoloads, main scene.
## Run: godot --headless --path . --script res://tools/setup_project.gd

const KEY := 0
const MOUSE := 3

# Keyboard + mouse only (gamepad support intentionally not implemented, per user request).
# action -> [deadzone, [ [type, code] ... ]]
var actions := {
	"throttle": [0.1, [[KEY, KEY_W], [KEY, KEY_UP]]],
	"brake": [0.1, [[KEY, KEY_S], [KEY, KEY_DOWN]]],
	"steer_left": [0.08, [[KEY, KEY_A], [KEY, KEY_LEFT]]],
	"steer_right": [0.08, [[KEY, KEY_D], [KEY, KEY_RIGHT]]],
	"handbrake": [0.2, [[KEY, KEY_SPACE]]],
	"shift_up": [0.5, [[KEY, KEY_E]]],
	"shift_down": [0.5, [[KEY, KEY_Q]]],
	"camera_next": [0.5, [[KEY, KEY_C]]],
	"look_back": [0.5, [[KEY, KEY_B]]],
	"horn": [0.5, [[KEY, KEY_H]]],
	"reset_car": [0.5, [[KEY, KEY_R]]],
	"headlights": [0.5, [[KEY, KEY_L]]],
	"toggle_console": [0.5, [[KEY, KEY_QUOTELEFT]]],
	"garage_menu": [0.5, [[KEY, KEY_F1], [KEY, KEY_TAB]]],
	"debug_menu": [0.5, [[KEY, KEY_F2]]],
	"map": [0.5, [[KEY, KEY_M]]],
	"photo_mode": [0.5, [[KEY, KEY_P]]],
	"photo_shot": [0.5, [[KEY, KEY_F12]]],
	"rewind": [0.5, [[KEY, KEY_BACKSPACE]]],
	"waypoint": [0.5, [[KEY, KEY_G]]],
	"activity_start": [0.5, [[KEY, KEY_ENTER], [KEY, KEY_KP_ENTER]]],
	"pause": [0.5, [[KEY, KEY_ESCAPE]]],
	"free_up": [0.2, [[KEY, KEY_E]]],
	"free_down": [0.2, [[KEY, KEY_Q]]],
}

const REMOVED := ["look_left", "look_right", "look_up", "look_down"]

func _init() -> void:
	for a: String in REMOVED:
		if ProjectSettings.has_setting("input/" + a):
			ProjectSettings.set_setting("input/" + a, null)
	for a: String in actions:
		var spec: Array = actions[a]
		var events: Array = []
		for e: Array in spec[1]:
			events.append(_make_event(e))
		ProjectSettings.set_setting("input/" + a, {"deadzone": spec[0], "events": events})

	var s := {
		"application/config/name": "VALORIA: Open Road Festival",
		"application/config/description": "Original open-world arcade-sim racing game (Godot 4.7).",
		"application/run/main_scene": "res://scenes/main.tscn",
		"display/window/size/viewport_width": 1920,
		"display/window/size/viewport_height": 1080,
		"display/window/stretch/mode": "canvas_items",
		"display/window/stretch/aspect": "expand",
		"physics/common/physics_ticks_per_second": 120,
		"physics/common/max_physics_steps_per_frame": 6,
		"physics/common/physics_interpolation": true,
		"physics/3d/physics_engine": "Jolt Physics",
		"physics/jolt_physics_3d/limits/max_linear_velocity": 600.0,
		"rendering/anti_aliasing/quality/msaa_3d": 2,
		"rendering/anti_aliasing/quality/screen_space_aa": 1,
		"rendering/lights_and_shadows/directional_shadow/size": 4096,
		"rendering/lights_and_shadows/directional_shadow/soft_shadow_filter_quality": 3,
		"rendering/environment/defaults/default_clear_color": Color(0.55, 0.7, 0.9),
		"rendering/textures/default_filters/anisotropic_filtering_level": 4,
		"rendering/mesh_lod/lod_change/threshold_pixels": 1.5,
		"autoload/Game": "*res://scripts/core/game.gd",
		"shader_globals/wetness": {"type": "float", "value": 0.0},
		"shader_globals/snow_cover": {"type": "float", "value": 0.0},
	}
	for k: String in s:
		ProjectSettings.set_setting(k, s[k])
	var err := ProjectSettings.save()
	print("project settings saved: ", error_string(err))
	quit(0 if err == OK else 1)


func _make_event(e: Array) -> InputEvent:
	var ev := _make_raw(e)
	ev.device = -1
	return ev


func _make_raw(e: Array) -> InputEvent:
	var k := InputEventKey.new()
	k.physical_keycode = e[1]
	return k