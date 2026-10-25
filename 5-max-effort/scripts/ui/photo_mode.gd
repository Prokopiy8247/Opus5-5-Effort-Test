extends CanvasLayer
## Photo mode (P): freezes the game (time of day and weather freeze with it), hides the HUD and
## frees the camera. WASD/arrows move, E/Q up/down, Shift faster, hold right mouse to look around,
## wheel = field of view, [ ] = focus distance, - = blur amount, T / Shift+T = time of day,
## Y = weather, Enter or F12 = screenshot (saved without the overlay), P / Esc = exit.

const SPEED := 12.0

var is_open := false
var _panel: PanelContainer
var _help: Label
var _cam: Camera3D
var _saved_xf: Transform3D
var _saved_fov: float = 70.0
var _saved_attr: CameraAttributes
var _attr: CameraAttributesPractical
var _yaw := 0.0
var _pitch := 0.0
var _fov := 60.0
var _focus := 12.0
var _blur := 0.0
var _hud_was := true
var _look := false
var _closed_frame := -1


func _ready() -> void:
	name = "PhotoMode"
	layer = 40
	process_mode = Node.PROCESS_MODE_ALWAYS
	_panel = PanelContainer.new()
	_panel.theme = UiTheme.get_theme()
	_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_panel.position = Vector2(28, 28)
	_panel.visible = false
	add_child(_panel)
	var v := VBoxContainer.new()
	_panel.add_child(v)
	v.add_child(UiTheme.label("PHOTO MODE", 26, UiTheme.ACCENT, true))
	_help = UiTheme.label("", 17, UiTheme.TEXT)
	v.add_child(_help)


func toggle() -> void:
	if is_open:
		close()
	else:
		open()


func open() -> void:
	# the P press that closed photo mode must not reopen it from main's _process in the same frame
	if is_open or Game.player_car == null or Engine.get_process_frames() == _closed_frame:
		return
	var rig := Game.camera_rig as CameraRig
	if rig == null:
		return
	is_open = true
	_cam = rig.camera
	_saved_xf = _cam.global_transform
	_saved_fov = _cam.fov
	_saved_attr = _cam.attributes
	_attr = CameraAttributesPractical.new()
	if _saved_attr is CameraAttributesPractical:
		_attr = (_saved_attr as CameraAttributesPractical).duplicate()
	_cam.attributes = _attr
	var e := _saved_xf.basis.get_euler()
	_pitch = e.x
	_yaw = e.y
	_fov = _cam.fov
	_focus = _cam.global_position.distance_to(Game.player_car.global_position)
	_blur = 0.0
	rig.frozen = true
	get_tree().paused = true
	Game.set_ui_focus("photo", true)
	if Game.hud != null:
		_hud_was = bool(Game.hud.get("visible_hud"))
		Game.hud.set("visible_hud", false)
		(Game.hud.get("root") as Control).visible = false
	_panel.visible = true
	_apply_dof()
	_refresh_help()


func close() -> void:
	if not is_open:
		return
	is_open = false
	_closed_frame = Engine.get_process_frames()
	_look = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_cam.attributes = _saved_attr
	_cam.fov = _saved_fov
	var rig := Game.camera_rig as CameraRig
	rig.frozen = false
	rig.snap()
	get_tree().paused = false
	Game.set_ui_focus("photo", false)
	if Game.hud != null:
		Game.hud.set("visible_hud", _hud_was)
	_panel.visible = false


func _unhandled_input(event: InputEvent) -> void:
	if not is_open:
		return
	if event.is_action_pressed("photo_mode") or event.is_action_pressed("pause_menu"):
		close()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT:
			_look = mb.pressed
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if _look else Input.MOUSE_MODE_VISIBLE
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_fov = clampf(_fov - 3.0, 12.0, 110.0)
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_fov = clampf(_fov + 3.0, 12.0, 110.0)
		_refresh_help()
	elif event is InputEventMouseMotion and _look:
		var mm := event as InputEventMouseMotion
		_yaw -= mm.relative.x * 0.0035
		_pitch = clampf(_pitch - mm.relative.y * 0.0035, -1.5, 1.5)
	elif event is InputEventKey and event.pressed:
		var k := (event as InputEventKey)
		match k.keycode:
			KEY_BRACKETLEFT:
				_focus = maxf(_focus / 1.15, 0.5)
				_apply_dof()
			KEY_BRACKETRIGHT:
				_focus = minf(_focus * 1.15, 2000.0)
				_apply_dof()
			KEY_MINUS:
				_blur = fmod(_blur + 0.25, 1.25)
				_apply_dof()
			KEY_T:
				var env := Game.environment as EnvironmentController
				env.set_time(fposmod(env.time_of_day + (-1.0 if k.shift_pressed else 1.0), 24.0))
			KEY_Y:
				var env2 := Game.environment as EnvironmentController
				env2.set_weather(((int(env2.weather) + 1) % EnvironmentController.WEATHER_NAMES.size()) as EnvironmentController.Weather, true)
				env2.call("_apply", 0.0, true)
			KEY_ENTER, KEY_KP_ENTER, KEY_F12:
				_capture()
		_refresh_help()


func _apply_dof() -> void:
	if _attr == null:
		return
	_attr.dof_blur_far_enabled = _blur > 0.0
	_attr.dof_blur_near_enabled = _blur > 0.0
	_attr.dof_blur_far_distance = _focus * 1.15
	_attr.dof_blur_far_transition = maxf(_focus * 0.6, 2.0)
	_attr.dof_blur_near_distance = maxf(_focus * 0.7, 0.3)
	_attr.dof_blur_near_transition = maxf(_focus * 0.35, 0.3)
	_attr.dof_blur_amount = _blur * 0.12


func _capture() -> void:
	_panel.visible = false
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	Game.main.call("take_screenshot", "")
	_panel.visible = true


func _process(delta: float) -> void:
	if not is_open or _cam == null:
		return
	var dir := Vector3.ZERO
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		dir.z -= 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		dir.z += 1.0
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		dir.x -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		dir.x += 1.0
	if Input.is_action_pressed("cam_up"):
		dir.y += 1.0
	if Input.is_action_pressed("cam_down"):
		dir.y -= 1.0
	var b := Basis.from_euler(Vector3(_pitch, _yaw, 0.0))
	var spd := SPEED * (4.0 if Input.is_action_pressed("cam_fast") else 1.0)
	var pos := _cam.global_position + (b * Vector3(dir.x, 0.0, dir.z) + Vector3.UP * dir.y) * spd * delta
	# keep the camera within 300 m of the car and above the ground
	var car := Game.player_car
	if car != null:
		var off := pos - car.global_position
		if off.length() > 300.0:
			pos = car.global_position + off.normalized() * 300.0
	if Game.world != null and Game.world.has_method("height_at"):
		pos.y = maxf(pos.y, float(Game.world.call("height_at", pos.x, pos.z)) + 0.4)
	_cam.global_transform = Transform3D(b, pos)
	_cam.fov = lerpf(_cam.fov, _fov, 1.0 - exp(-delta * 10.0))


func _refresh_help() -> void:
	var env := Game.environment as EnvironmentController
	var w: String = EnvironmentController.WEATHER_NAMES[int(env.weather)] if env != null else "-"
	_help.text = ("WASD move · E/Q up/down · Shift fast · hold RMB look\n" +
		"Wheel FOV %d° · [ ] focus %.1f m · - blur %d%%\n" +
		"T/Shift+T time %05.2f · Y weather %s\n" +
		"Enter / F12 screenshot · P / Esc exit") % [int(_fov), _focus, int(_blur * 100.0), env.time_of_day if env != null else 0.0, w]
