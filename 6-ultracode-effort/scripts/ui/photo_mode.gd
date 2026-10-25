extends "res://scripts/ui/menu_base.gd"
## Photo mode (toggle_photo_mode: P): pauses the world, frees the CameraRig's camera for flying
## (WASD/QE, right-mouse look, Shift fast), lens/exposure/roll/time/weather controls,
## H hides the panel, F12 saves user://screenshots/sunward_<timestamp>.png. P/Esc exits.
## The panel works from the keyboard: focus starts on Field of view, Tab / arrows move it, Left / Right
## adjust a slider, Enter / Space press the focused button.
## Outside photo mode F12 is handled by ui_root (plain screenshot with the HUD).
## Time / weather changes briefly un-pause Game.env and every node in Game.TIME_REACTIVE_GROUP
## (PULSE_TIME of real time), so lights, windows and headlights follow while the world stays frozen.

const Shot := preload("res://scripts/ui/screenshot.gd")
const FLY_SPEED := 7.0
const FAST_MULT := 4.0
const LEASH := 150.0
const LOOK_SENS := 0.0032
const PULSE_TIME := 0.6
const PULSE_MIN_FRAMES := 4

var _rig: CameraRig
var _cam: Camera3D
var _attr: CameraAttributesPractical
var _saved_attr: CameraAttributes
var _saved_fov: float = 65.0
var _saved_near: float = 0.1
var _pos: Vector3
var _yaw: float = 0.0
var _pitch: float = 0.0
var _roll: float = 0.0
var _panel: PanelContainer
var _hints: Control
var _flash: ColorRect
var _panel_hidden: bool = false
var _looking: bool = false
var _capturing: bool = false
var _sliders: Dictionary = {}
var _weather_box: HFlowContainer
var _weather_buttons: Dictionary = {}
## Remaining pulse (frames and real seconds) and the process mode each pulsed node had before it.
var _env_pulse: int = 0
var _pulse_left: float = 0.0
var _pulse_saved: Dictionary = {}
var _focus_before: Control
var _ray := PhysicsRayQueryParameters3D.new()
## Path of the last saved screenshot (for tests / integration).
var last_shot: String = ""


func _init() -> void:
	super._init()
	menu_id = &"photo"
	toggle_action = &"toggle_photo_mode"
	pauses_game = true
	captures_keys = true
	_ray.collision_mask = 1 | 32


func _build() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	_panel = Style.panel(Color(0.04, 0.05, 0.085, 0.9), 16, 20, 1, Color(1, 1, 1, 0.08))
	_panel.anchor_left = 1.0
	_panel.anchor_right = 1.0
	_panel.offset_left = -500
	_panel.offset_right = -36
	_panel.offset_top = 36
	add_child(_panel)
	var v := Style.vbox(8)
	_panel.add_child(v)
	v.add_child(Style.title("Photo mode", 34))
	v.add_child(Style.accent_bar(120, 4))
	v.add_child(Style.spacer(4))
	_add_slider(v, "fov", "Field of view", 15.0, 110.0, 1.0, 60.0, func(x: float) -> String: return "%d°" % roundi(x))
	_add_slider(v, "focus", "Focus distance", 0.5, 120.0, 0.5, 8.0, func(x: float) -> String: return "%.1f m" % x)
	_add_slider(v, "aperture", "Depth of field", 0.0, 1.0, 0.02, 0.0, func(x: float) -> String: return "Off" if x <= 0.001 else "%d%%" % roundi(x * 100.0))
	_add_slider(v, "exposure", "Exposure", -2.0, 2.0, 0.1, 0.0, func(x: float) -> String: return "%+.1f EV" % x)
	_add_slider(v, "roll", "Roll", -35.0, 35.0, 1.0, 0.0, func(x: float) -> String: return "%+d°" % roundi(x))
	_add_slider(v, "time", "Time of day", 0.0, 24.0, 0.25, 12.0, func(x: float) -> String: return Style.fmt_time(x))
	v.add_child(Style.spacer(2))
	v.add_child(Style.caps("Weather", 16, Style.TEXT_FAINT))
	_weather_box = HFlowContainer.new()
	_weather_box.add_theme_constant_override("h_separation", 6)
	_weather_box.add_theme_constant_override("v_separation", 6)
	v.add_child(_weather_box)
	v.add_child(Style.spacer(4))
	var btns := Style.hbox(8)
	for b: Array in [["Capture", capture], ["Hide (H)", toggle_panel], ["Reset", _reset_lens], ["Exit", close_menu]]:
		var bt := Style.button(b[0], b[1], 0, 46)
		bt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bt.add_theme_font_size_override("font_size", 19)
		btns.add_child(bt)
	v.add_child(btns)

	_hints = Style.panel(Color(0.03, 0.04, 0.07, 0.78), 12, 10)
	_hints.anchor_top = 1.0
	_hints.anchor_bottom = 1.0
	_hints.offset_left = 36
	_hints.offset_top = -82
	_hints.offset_bottom = -30
	_hints.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hints.add_child(Style.hint_bar([["W", "A", "S", "D", "Move"], ["Q", "E", "Down / up"], ["Right mouse", "Look"], ["Wheel", "Zoom"],
		["Shift", "Fast"], ["Tab", "Arrows", "Panel"], ["Enter", "Press"], ["H", "Hide UI"], ["F12", "Capture"], ["P", "Esc", "Exit"]]))
	add_child(_hints)

	_flash = ColorRect.new()
	_flash.color = Color(1, 1, 1, 0)
	_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_flash)


func _add_slider(parent: Control, key: String, text: String, lo: float, hi: float, step: float, value: float, fmt: Callable) -> void:
	var s := Style.slider_row(text, lo, hi, step, value, fmt, _on_slider.bind(key), 170)
	s.custom_minimum_size = Vector2(150, 30)
	parent.add_child(s.get_meta(&"row"))
	_sliders[key] = s


func can_open() -> bool:
	return Game.camera_rig != null and Game.player_car != null and is_instance_valid(Game.player_car) and not Game.benchmark_mode


# ------------------------------------------------------------------ enter / exit

func _on_opened() -> void:
	_rig = Game.camera_rig as CameraRig
	_cam = _rig.camera
	_rig.active = false
	_saved_attr = _cam.attributes
	_saved_fov = _cam.fov
	_saved_near = _cam.near
	_cam.near = 0.05
	var xf := _cam.global_transform
	_pos = xf.origin
	var e := xf.basis.get_euler()
	_pitch = e.x
	_yaw = e.y
	_roll = 0.0
	_attr = _make_attributes()
	_cam.attributes = _attr
	Game.photo_mode = true
	_panel_hidden = false
	_panel.visible = true
	_hints.visible = true
	Style.set_slider(_sliders["fov"], _cam.fov)
	Style.set_slider(_sliders["roll"], 0.0)
	Style.set_slider(_sliders["time"], Game.get_time_of_day())
	(_sliders["time"] as HSlider).editable = Game.env != null
	_apply_lens()
	_sync_weather()
	_focus_before = null
	_focus_panel.call_deferred()


func _on_closed() -> void:
	_set_looking(false)
	_end_env_pulse()
	_focus_before = null
	if _cam:
		_cam.attributes = _saved_attr
		_cam.fov = _saved_fov
		_cam.near = _saved_near
	if _rig:
		_rig.active = true
		_rig.snap()
	Game.photo_mode = false


func _make_attributes() -> CameraAttributesPractical:
	var base: CameraAttributes = _saved_attr
	if base == null and _cam.get_world_3d() != null:
		base = _cam.get_world_3d().camera_attributes
	var a: CameraAttributesPractical
	if base is CameraAttributesPractical:
		a = (base as CameraAttributesPractical).duplicate()
	else:
		a = CameraAttributesPractical.new()
	return a


func _reset_lens() -> void:
	Style.set_slider(_sliders["fov"], 60.0)
	Style.set_slider(_sliders["focus"], 8.0)
	Style.set_slider(_sliders["aperture"], 0.0)
	Style.set_slider(_sliders["exposure"], 0.0)
	Style.set_slider(_sliders["roll"], 0.0)
	_roll = 0.0
	_apply_lens()


# ------------------------------------------------------------------ controls

func _on_slider(v: float, key: String) -> void:
	match key:
		"time":
			Game.set_time_of_day(fmod(v, 24.0))
			_pulse_env()
		"roll":
			_roll = deg_to_rad(v)
		_:
			_apply_lens()


func _apply_lens() -> void:
	if _cam == null or _attr == null:
		return
	_cam.fov = (_sliders["fov"] as HSlider).value
	var focus := (_sliders["focus"] as HSlider).value
	var ap := (_sliders["aperture"] as HSlider).value
	_attr.dof_blur_far_enabled = ap > 0.001
	_attr.dof_blur_near_enabled = ap > 0.001 and focus > 1.5
	_attr.dof_blur_far_distance = focus * 1.12 + 0.3
	_attr.dof_blur_far_transition = focus * 0.8 + 2.0
	_attr.dof_blur_near_distance = maxf(focus * 0.55, 0.3)
	_attr.dof_blur_near_transition = maxf(focus * 0.35, 0.3)
	_attr.dof_blur_amount = ap * 0.22
	_attr.exposure_multiplier = pow(2.0, (_sliders["exposure"] as HSlider).value)


func _sync_weather() -> void:
	var ids := Game.get_weather_ids()
	if _weather_buttons.size() != ids.size():
		for c in _weather_box.get_children():
			c.queue_free()
		_weather_buttons.clear()
		for id: Variant in ids:
			var b := Style.button(String(id).capitalize(), _set_weather.bind(String(id)), 0, 40)
			b.toggle_mode = true
			b.add_theme_font_size_override("font_size", 18)
			_weather_box.add_child(b)
			_weather_buttons[String(id)] = b
		if ids.is_empty():
			_weather_box.add_child(Style.label("Weather system not loaded", 18, Style.TEXT_FAINT))
	var cur := String(Game.get_weather())
	for k: String in _weather_buttons:
		(_weather_buttons[k] as Button).set_pressed_no_signal(k == cur)


func _set_weather(id: String) -> void:
	Game.set_weather(id, true)
	_pulse_env()
	_sync_weather()


## The world is paused with the tree; let the environment and every time-reactive node (lights, lamp
## pool, windows, traffic lights - see Game.TIME_REACTIVE_GROUP) process for PULSE_TIME so a time or
## weather change shows up everywhere while the world stays frozen. Re-triggering extends the pulse.
func _pulse_env() -> void:
	var nodes: Array[Node] = []
	if Game.env != null and is_instance_valid(Game.env):
		nodes.append(Game.env)
	if is_inside_tree():
		nodes.append_array(get_tree().get_nodes_in_group(Game.TIME_REACTIVE_GROUP))
	for n in nodes:
		var id := n.get_instance_id()
		if not _pulse_saved.has(id):
			_pulse_saved[id] = n.process_mode
			n.process_mode = Node.PROCESS_MODE_ALWAYS
	_env_pulse = PULSE_MIN_FRAMES
	_pulse_left = PULSE_TIME


func _end_env_pulse() -> void:
	for id: int in _pulse_saved:
		var n := instance_from_id(id) as Node
		if n != null and is_instance_valid(n):
			n.process_mode = _pulse_saved[id]
	_pulse_saved.clear()
	_env_pulse = 0
	_pulse_left = 0.0


## True while time / weather consumers are processing despite the pause (for tests).
func is_pulsing() -> bool:
	return not _pulse_saved.is_empty()


func toggle_panel() -> void:
	_panel_hidden = not _panel_hidden
	# Hiding a Control drops its focus, so remember it first.
	if _panel_hidden:
		_store_focus()
	_panel.visible = not _panel_hidden
	_hints.visible = not _panel_hidden
	if not _panel_hidden:
		_focus_panel()


## Keyboard focus for the panel: the control focused before it was hidden, else Field of view.
func _focus_panel() -> void:
	if not is_open or _panel_hidden or not _panel.visible:
		return
	var f := _focus_before if _focus_before != null and is_instance_valid(_focus_before) and _focus_before.is_visible_in_tree() else _sliders["fov"] as Control
	_focus_before = null
	f.grab_focus()


func _store_focus() -> void:
	var f := get_viewport().gui_get_focus_owner()
	if f != null and _panel.is_ancestor_of(f):
		_focus_before = f
		f.release_focus()


func _menu_input(event: InputEvent) -> void:
	if _capturing:
		return
	var k := event as InputEventKey
	if k != null and k.pressed and not k.echo:
		# Enter / Space stay with the GUI (they press the focused button); capture has its own key.
		match k.physical_keycode:
			KEY_H:
				toggle_panel()
			KEY_F12:
				capture()
			_:
				return
		get_viewport().set_input_as_handled()
		return
	var mb := event as InputEventMouseButton
	if mb != null:
		if mb.button_index == MOUSE_BUTTON_RIGHT:
			_set_looking(mb.pressed)
			get_viewport().set_input_as_handled()
		elif mb.pressed and (mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN) and not _panel_has_mouse():
			var s: HSlider = _sliders["fov"]
			s.value += -2.0 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 2.0
			get_viewport().set_input_as_handled()
		return
	var mm := event as InputEventMouseMotion
	if mm != null and _looking:
		_yaw -= mm.relative.x * LOOK_SENS
		_pitch = clampf(_pitch - mm.relative.y * LOOK_SENS, -1.45, 1.45)
		get_viewport().set_input_as_handled()
		return


func _panel_has_mouse() -> bool:
	return _panel.visible and _panel.get_global_rect().has_point(get_viewport().get_mouse_position())


func _set_looking(on: bool) -> void:
	_looking = on
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if on else Input.MOUSE_MODE_VISIBLE


# ------------------------------------------------------------------ flying

func _process(delta: float) -> void:
	if not _pulse_saved.is_empty():
		_env_pulse -= 1
		_pulse_left -= delta
		if _env_pulse <= 0 and _pulse_left <= 0.0:
			_end_env_pulse()
	if not is_open or _rig == null:
		return
	var mv := Vector3.ZERO
	if Input.is_physical_key_pressed(KEY_W):
		mv.z -= 1.0
	if Input.is_physical_key_pressed(KEY_S):
		mv.z += 1.0
	if Input.is_physical_key_pressed(KEY_A):
		mv.x -= 1.0
	if Input.is_physical_key_pressed(KEY_D):
		mv.x += 1.0
	var up := 0.0
	if Input.is_physical_key_pressed(KEY_E):
		up += 1.0
	if Input.is_physical_key_pressed(KEY_Q):
		up -= 1.0
	var speed := FLY_SPEED * (FAST_MULT if Input.is_physical_key_pressed(KEY_SHIFT) else 1.0)
	var yaw_basis := Basis(Vector3.UP, _yaw)
	var look_basis := Basis.from_euler(Vector3(_pitch, _yaw, 0.0))
	var step := (look_basis * Vector3(mv.x, 0.0, mv.z)).limit_length(1.0) + yaw_basis * Vector3(0.0, up, 0.0)
	_pos += step * speed * delta
	_constrain()
	_rig.global_transform = Transform3D(Basis.from_euler(Vector3(_pitch, _yaw, _roll)), _pos)


func _constrain() -> void:
	var car := Game.player_car
	if car != null and is_instance_valid(car):
		var c := car.global_position
		if _pos.distance_to(c) > LEASH:
			_pos = c + (_pos - c).normalized() * LEASH
	var space := _rig.get_world_3d().direct_space_state
	_ray.from = _pos + Vector3.UP * 1.5
	_ray.to = _pos - Vector3.UP * 0.35
	var hit := space.intersect_ray(_ray)
	if not hit.is_empty():
		_pos.y = maxf(_pos.y, (hit["position"] as Vector3).y + 0.35)


# ------------------------------------------------------------------ capture

func capture() -> void:
	if _capturing or not is_open:
		return
	_capturing = true
	var was_panel := _panel.visible
	# Hiding the panel drops its focus: keep it for afterwards.
	_store_focus()
	_panel.visible = false
	_hints.visible = false
	for c in get_children():
		if c is PanelContainer and c != _panel and c != _hints:
			(c as Control).visible = false
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	# The frame is read back and encoded in the background; the UI can come back right away.
	Shot.save_viewport_async(get_viewport(), _on_photo_saved)
	_panel.visible = was_panel and not _panel_hidden
	_hints.visible = not _panel_hidden
	_capturing = false
	if not is_open:
		return
	_focus_panel()
	_flash.color = Color(1, 1, 1, 0.55)
	var tw := create_tween()
	tw.tween_property(_flash, "color:a", 0.0, 0.35)


func _on_photo_saved(path: String) -> void:
	if path != "":
		last_shot = path
		print("[photo] saved %s" % ProjectSettings.globalize_path(path))
	if not is_open:
		return
	if path != "":
		toast("Photo saved  ·  screenshots/%s" % path.get_file())
	else:
		toast("Could not save the photo", Style.BAD)
