class_name ChaseCam
extends Camera3D
## Chase / far chase / hood / cockpit / bumper camera with speed FOV, collision,
## look-back, free look and impact shake. Also hosts the photo-mode free camera.

const MODES := ["Chase", "Far Chase", "Hood", "Cockpit", "Bumper"]
var target: Car
var mode := 0
var photo := false
var yaw_off := 0.0
var shake := 0.0
var _pos := Vector3.ZERO
var _look := Vector3.ZERO
var _vel_dir := Vector3.FORWARD
var _photo_yaw := 0.0
var _photo_pitch := 0.0
var mouse_look := Vector2.ZERO
var _mouse_timer := 0.0

func _ready() -> void:
	far = 6000.0
	near = 0.08

func cycle() -> void:
	mode = (mode + 1) % MODES.size()
	Game.toast("Camera: " + MODES[mode])

func snap() -> void:
	if target == null: return
	_vel_dir = -target.global_basis.z
	_pos = target.global_position - _vel_dir * 7.0 + Vector3.UP * 2.5
	global_position = _pos

func add_shake(a: float) -> void:
	shake = minf(shake + a, 1.0)

func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		var mm := e as InputEventMouseMotion
		if photo:
			_photo_yaw -= mm.relative.x * 0.004; _photo_pitch = clampf(_photo_pitch - mm.relative.y * 0.004, -1.4, 1.4)
		else:
			mouse_look.x = clampf(mouse_look.x - mm.relative.x * 0.006, -PI, PI)
			mouse_look.y = clampf(mouse_look.y - mm.relative.y * 0.004, -0.4, 0.6)
			_mouse_timer = 2.0

func enter_photo() -> void:
	photo = true
	var e := global_basis.get_euler()
	_photo_pitch = e.x; _photo_yaw = e.y

func _process(dt: float) -> void:
	if target == null: return
	if photo:
		_photo(dt)
		return
	var car := target
	var kmh := absf(car.speed) * 3.6
	var v := car.linear_velocity
	var fwd := -car.global_basis.z
	var flat_f := Vector3(fwd.x, 0, fwd.z).normalized()
	if v.length() > 3.0 and car.speed > 0.0:
		var vd := Vector3(v.x, 0, v.z).normalized()
		_vel_dir = _vel_dir.slerp(vd.lerp(flat_f, 0.5).normalized(), clampf(dt * 3.0, 0, 1))
	else:
		_vel_dir = _vel_dir.slerp(flat_f, clampf(dt * 2.0, 0, 1))
	var look_input := Input.get_axis("look_left", "look_right")
	_mouse_timer -= dt
	if _mouse_timer <= 0.0: mouse_look = mouse_look.lerp(Vector2.ZERO, clampf(dt * 3.0, 0, 1))
	yaw_off = lerpf(yaw_off, -look_input * PI * 0.5, clampf(dt * 6.0, 0, 1))
	var back := Input.is_action_pressed("look_back")
	var yaw := yaw_off + mouse_look.x + (PI if back else 0.0)
	var fov_target := 68.0 + clampf(kmh / 300.0, 0.0, 1.0) * 18.0
	if mode <= 1:
		var dist := (6.2 if mode == 0 else 9.5) + clampf(kmh / 250.0, 0, 1) * 1.6
		var height := (2.0 if mode == 0 else 3.2) + car.body_size.y * 0.35
		var dir := _vel_dir.rotated(Vector3.UP, yaw)
		var want := car.global_position - dir * dist + Vector3.UP * (height + mouse_look.y * 4.0)
		# collision
		var space := get_world_3d().direct_space_state
		var from := car.global_position + Vector3.UP * 1.2
		var q := PhysicsRayQueryParameters3D.create(from, want, 1)
		var hit := space.intersect_ray(q)
		if not hit.is_empty(): want = (hit.position as Vector3) + (from - want).normalized() * 0.4
		_pos = _pos.lerp(want, clampf(dt * 9.0, 0, 1)) if _pos.distance_to(want) < 40.0 else want
		global_position = _pos
		var look := car.global_position + Vector3.UP * (1.0 + car.body_size.y * 0.2) + dir * 2.0
		look_at(look, Vector3.UP)
	else:
		var lp: Vector3 = car.hood_pos if mode == 2 else (car.cockpit_pos if mode == 3 else car.bumper_pos)
		global_transform = car.global_transform * Transform3D(Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, mouse_look.y * 0.5), lp)
		fov_target = 74.0 + clampf(kmh / 300.0, 0.0, 1.0) * 10.0
	fov = lerpf(fov, fov_target, clampf(dt * 3.0, 0, 1))
	# shake: speed rumble + impacts
	var s := shake + clampf((kmh - 120.0) / 400.0, 0.0, 0.25) * 0.15 + car.max_slip * 0.03
	if s > 0.001:
		var t := Time.get_ticks_msec() * 0.001
		h_offset = sin(t * 37.0) * s * 0.08
		v_offset = sin(t * 53.0 + 1.3) * s * 0.06
	shake = maxf(shake - dt * 2.0, 0.0)

func _photo(dt: float) -> void:
	var mv := Vector3.ZERO
	if Input.is_key_pressed(KEY_W): mv.z -= 1
	if Input.is_key_pressed(KEY_S): mv.z += 1
	if Input.is_key_pressed(KEY_A): mv.x -= 1
	if Input.is_key_pressed(KEY_D): mv.x += 1
	if Input.is_key_pressed(KEY_E): mv.y += 1
	if Input.is_key_pressed(KEY_Q): mv.y -= 1
	if Input.is_key_pressed(KEY_LEFT): _photo_yaw += dt
	if Input.is_key_pressed(KEY_RIGHT): _photo_yaw -= dt
	if Input.is_key_pressed(KEY_UP): _photo_pitch = clampf(_photo_pitch + dt, -1.4, 1.4)
	if Input.is_key_pressed(KEY_DOWN): _photo_pitch = clampf(_photo_pitch - dt, -1.4, 1.4)
	basis = Basis.from_euler(Vector3(_photo_pitch, _photo_yaw, 0))
	var spd := 12.0 * (3.0 if Input.is_key_pressed(KEY_SHIFT) else 1.0)
	global_position += basis * mv * spd * dt
	# keep near the car
	var off := global_position - target.global_position
	if off.length() > 60.0: global_position = target.global_position + off.normalized() * 60.0
