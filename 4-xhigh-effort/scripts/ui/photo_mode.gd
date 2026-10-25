extends Control
## Photo mode (P): pauses the game, free camera (WASD/arrows, Q/E up/down, right-drag to look), FOV, depth of field, time-of-day and weather freeze, hide UI, F12 shot.

var cam: Camera3D
var panel: PanelContainer
var fov_slider: HSlider
var dof_slider: HSlider
var time_slider: HSlider
var _yaw := 0.0
var _pitch := 0.0
var _attrs: CameraAttributesPractical
var _ui_hidden := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	panel = PanelContainer.new()
	UITheme.place(panel, 0.0, 1.0, 24, -330, 420, 306)
	add_child(panel)
	var vb := VBoxContainer.new()
	panel.add_child(vb)
	vb.add_child(UITheme.label("PHOTO MODE", 26, UITheme.PINK, true))
	vb.add_child(UITheme.label("WASD/QE move · right-drag look · F12 photo · H hide UI", 14, UITheme.DIM))
	vb.add_child(UITheme.label("Field of view", 16, UITheme.SUN))
	fov_slider = _slider(vb, 20.0, 100.0, 60.0)
	vb.add_child(UITheme.label("Depth of field (focus distance, 0 = off)", 16, UITheme.SUN))
	dof_slider = _slider(vb, 0.0, 60.0, 0.0)
	vb.add_child(UITheme.label("Time of day", 16, UITheme.SUN))
	time_slider = _slider(vb, 0.0, 24.0, 12.0)
	var hb := HBoxContainer.new()
	for w: String in ["clear", "cloudy", "rain", "fog", "storm"]:
		var b := Button.new()
		b.text = w.capitalize()
		b.pressed.connect(func() -> void: Game.sky.set_weather(w, true))
		hb.add_child(b)
	vb.add_child(hb)


func _slider(vb: VBoxContainer, a: float, b: float, v: float) -> HSlider:
	var s := HSlider.new()
	s.min_value = a
	s.max_value = b
	s.step = 0.1
	s.value = v
	s.custom_minimum_size = Vector2(380, 22)
	vb.add_child(s)
	return s


func toggle() -> void:
	visible = not visible
	Game.set_ui_focus("photo", visible)
	get_tree().paused = visible
	if Game.sky != null:
		Game.sky.frozen = visible
		Game.sky.process_mode = Node.PROCESS_MODE_ALWAYS
	if visible:
		cam = Camera3D.new()
		cam.process_mode = Node.PROCESS_MODE_ALWAYS
		Game.main.add_child(cam)
		cam.global_transform = Game.camera.global_transform
		var e := cam.global_transform.basis.get_euler()
		_yaw = e.y
		_pitch = e.x
		cam.fov = Game.camera.fov
		fov_slider.value = cam.fov
		time_slider.value = float(Game.sky.time_of_day)
		_attrs = CameraAttributesPractical.new()
		cam.attributes = _attrs
		cam.current = true
		_ui_hidden = false
		if Game.hud != null:
			Game.hud.call("set_hud_visible", false)  # clean frame: only the photo panel stays
	else:
		if cam != null:
			cam.queue_free()
			cam = null
		Game.camera.current = true
		if Game.hud != null:
			Game.hud.call("set_hud_visible", true)
		panel.visible = true


func _unhandled_input(event: InputEvent) -> void:
	if not visible or cam == null:
		return
	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		var mm := event as InputEventMouseMotion
		_yaw -= mm.relative.x * 0.004
		_pitch = clampf(_pitch - mm.relative.y * 0.004, -1.5, 1.5)
	elif event is InputEventKey and event.pressed and not event.echo:
		var k := event as InputEventKey
		if k.keycode == KEY_H:
			_ui_hidden = not _ui_hidden
			panel.visible = not _ui_hidden
		elif k.keycode == KEY_F12 or k.keycode == KEY_ENTER:
			_shot()
	elif event.is_action_pressed("photo_shot"):
		_shot()


func _shot() -> void:
	panel.visible = false
	Game.hud.call("set_hud_visible", false)
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute("user://screenshots")
	var path := "user://screenshots/valoria_%s.png" % Time.get_datetime_string_from_system().replace(":", "-")
	img.save_png(path)
	panel.visible = not _ui_hidden
	(Game.hud.get("notes") as Control).visible = true  # the driving HUD stays hidden in photo mode
	Game.notify("Photo saved", ProjectSettings.globalize_path(path), "small")


func _process(delta: float) -> void:
	if not visible or cam == null:
		return
	var mv := Vector3.ZERO
	mv.x = Input.get_axis("steer_left", "steer_right")
	mv.z = Input.get_axis("throttle", "brake")
	mv.y = Input.get_axis("free_down", "free_up")

	var b := Basis.from_euler(Vector3(_pitch, _yaw, 0))
	var speed := 12.0 * (3.0 if Input.is_key_pressed(KEY_SHIFT) else 1.0)
	var np := cam.global_position + b * mv * speed * delta
	if Game.player != null and np.distance_to(Game.player.global_position) > 80.0:
		np = Game.player.global_position + (np - Game.player.global_position).limit_length(80.0)
	cam.global_transform = Transform3D(b, np)
	cam.fov = fov_slider.value
	if absf(float(Game.sky.time_of_day) - time_slider.value) > 0.01:
		Game.sky.set_time(time_slider.value)
	_attrs.dof_blur_far_enabled = dof_slider.value > 0.5
	_attrs.dof_blur_near_enabled = dof_slider.value > 0.5
	_attrs.dof_blur_far_distance = dof_slider.value * 1.6
	_attrs.dof_blur_near_distance = maxf(dof_slider.value * 0.5, 0.5)
	_attrs.dof_blur_amount = 0.12
