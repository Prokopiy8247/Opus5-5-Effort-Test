extends Node3D
## Photo mode (P): pauses the game, free camera (WASD / Q E up-down, right-drag look,
## wheel FOV), F focus/DOF, [ ] time of day, 1-5 weather, H hide hints, F12 shot, P/Esc exit.

var main: Node
var cam: Camera3D
var active := false
var yaw := 0.0
var pitch := 0.0
var dof := false
var hint: Label
var _hud_layer_visible := true


func setup(m: Node) -> void:
	main = m
	process_mode = Node.PROCESS_MODE_ALWAYS
	cam = Camera3D.new()
	cam.far = 6000.0
	cam.process_mode = Node.PROCESS_MODE_ALWAYS
	var attrs := CameraAttributesPractical.new()
	attrs.dof_blur_far_enabled = false
	attrs.dof_blur_far_distance = 40.0
	attrs.dof_blur_near_enabled = false
	attrs.dof_blur_amount = 0.12
	cam.attributes = attrs
	add_child(cam)
	hint = UIStyle.label("PHOTO MODE   WASD/QE move   right-drag look   wheel FOV   F depth of field   [ ] time   1-5 weather   H hide text   F12 photo   P exit", 15, Color(1, 1, 1, 0.8))
	UIStyle.place(hint, Control.PRESET_CENTER_BOTTOM, -620, -36, 620, -10)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.visible = false


func toggle() -> void:
	active = not active
	get_tree().paused = active
	if active:
		var src: Camera3D = main.camera
		cam.global_transform = src.global_transform
		cam.fov = src.fov
		var e := cam.global_transform.basis.get_euler()
		yaw = e.y
		pitch = e.x
		cam.current = true
		main.ui.visible = false
		if hint.get_parent() == null:
			var cl := CanvasLayer.new()
			cl.layer = 20
			cl.process_mode = Node.PROCESS_MODE_ALWAYS
			add_child(cl)
			cl.add_child(hint)
		hint.visible = true
		main.world.sky.process_mode = Node.PROCESS_MODE_ALWAYS
		main.world.sky.time_frozen = true
	else:
		main.camera.current = true
		main.ui.visible = true
		hint.visible = false
		main.world.sky.process_mode = Node.PROCESS_MODE_INHERIT
		main.world.sky.time_frozen = false
		(cam.attributes as CameraAttributesPractical).dof_blur_far_enabled = false


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("photo_mode") or (active and event.is_action_pressed("ui_cancel")):
		toggle()
		get_viewport().set_input_as_handled()
		return
	if not active:
		return
	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		var mm := event as InputEventMouseMotion
		yaw -= mm.relative.x * 0.004
		pitch = clampf(pitch - mm.relative.y * 0.004, -1.4, 1.4)
	elif event is InputEventMouseButton and event.pressed:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			cam.fov = maxf(cam.fov - 3.0, 15.0)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			cam.fov = minf(cam.fov + 3.0, 100.0)
	elif event is InputEventKey and event.pressed:
		var k := (event as InputEventKey).keycode
		match k:
			KEY_F:
				dof = not dof
				var a := cam.attributes as CameraAttributesPractical
				a.dof_blur_far_enabled = dof
				a.dof_blur_near_enabled = dof
				a.dof_blur_near_distance = 2.0
				a.dof_blur_far_distance = (main.player.global_position - cam.global_position).length() + 8.0
			KEY_BRACKETLEFT:
				main.world.sky.set_time(Game.time_of_day - 0.5)
			KEY_BRACKETRIGHT:
				main.world.sky.set_time(Game.time_of_day + 0.5)
			KEY_1, KEY_2, KEY_3, KEY_4, KEY_5:
				main.world.sky.set_weather(["clear", "cloudy", "rain", "fog", "storm"][k - KEY_1], true)
			KEY_H:
				hint.visible = not hint.visible
			KEY_F12:
				hint.visible = false
				await RenderingServer.frame_post_draw
				main.take_screenshot()
				hint.visible = true


func _process(delta: float) -> void:
	if not active:
		return
	cam.basis = Basis.from_euler(Vector3(pitch, yaw, 0.0))
	var mv := Vector3.ZERO
	if Input.is_key_pressed(KEY_W):
		mv.z -= 1
	if Input.is_key_pressed(KEY_S):
		mv.z += 1
	if Input.is_key_pressed(KEY_A):
		mv.x -= 1
	if Input.is_key_pressed(KEY_D):
		mv.x += 1
	if Input.is_key_pressed(KEY_E):
		mv.y += 1
	if Input.is_key_pressed(KEY_Q):
		mv.y -= 1
	var spd := 25.0 if Input.is_key_pressed(KEY_SHIFT) else 8.0
	var np := cam.global_position + cam.basis * mv * spd * delta
	# stay within 60 m of the car and above the ground
	var cp: Vector3 = main.player.global_position
	if np.distance_to(cp) > 60.0:
		np = cp + (np - cp).normalized() * 60.0
	np.y = maxf(np.y, Game.world.height_at(np.x, np.z) + 0.3)
	cam.global_position = np
