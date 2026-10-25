class_name ChaseCamera
extends Camera3D
## Chase (near/far), hood, bumper and cockpit cameras with speed-dependent FOV/distance, smoothing,
## camera collision, free look, look-back and shake (speed + impacts). Also a free photo-mode camera.

enum Mode { CHASE_NEAR, CHASE_FAR, HOOD, BUMPER, COCKPIT }
const MODE_NAMES: PackedStringArray = ["Chase", "Chase Far", "Hood", "Bumper", "Cockpit"]

var target: Car
var mode: int = Mode.CHASE_NEAR
var photo_mode: bool = false
var shake: float = 0.0
var _pos: Vector3
var _look_yaw: float = 0.0
var _look_pitch: float = 0.0
var _mouse_look: Vector2 = Vector2.ZERO
var _last_mouse_t: float = 0.0
var _vel_dir: Vector3 = Vector3.FORWARD
var _noise := FastNoiseLite.new()
var _t: float = 0.0
var _photo_yaw: float = 0.0
var _photo_pitch: float = 0.0
var _last_us: int = 0


func _ready() -> void:
	near = 0.12
	far = 6000.0
	fov = 70.0
	_noise.frequency = 1.5


func set_target(c: Car) -> void:
	target = c
	if c:
		_pos = c.global_position + c.global_transform.basis.z * 7.0 + Vector3.UP * 2.5
		_vel_dir = -c.global_transform.basis.z
		global_position = _pos


func next_mode() -> void:
	mode = (mode + 1) % MODE_NAMES.size()
	if target and target.model:
		# hide the body in the cockpit view? keep it: interior is modelled
		pass


func add_shake(a: float) -> void:
	shake = minf(1.0, shake + a)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and (Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) or photo_mode):
		_mouse_look += event.relative * 0.005
		_last_mouse_t = 0.0
		if photo_mode:
			_photo_yaw -= event.relative.x * 0.004
			_photo_pitch = clampf(_photo_pitch - event.relative.y * 0.004, -1.4, 1.4)
	elif event.is_action_pressed("camera_next") and not photo_mode:
		next_mode()


func _process(delta: float) -> void:
	var _pf: int = Time.get_ticks_usec()
	_inner_camera(delta)
	Game.prof_add("camera", _pf)


func _inner_camera(delta: float) -> void:
	_t += delta
	var now: int = Time.get_ticks_usec()
	var real_dt: float = clampf((now - _last_us) / 1000000.0, 0.0, 0.1)
	_last_us = now
	if photo_mode:
		_photo_update(real_dt)
		return
	if target == null or not is_instance_valid(target):
		return
	var xf: Transform3D = target.global_transform
	var bas: Basis = xf.basis
	var v: Vector3 = target.linear_velocity
	var spd: float = v.length()
	var kmh: float = spd * 3.6
	# free look (right mouse drag)
	var lx: float = Input.get_action_strength("look_right") - Input.get_action_strength("look_left")
	var ly: float = Input.get_action_strength("look_down") - Input.get_action_strength("look_up")
	_last_mouse_t += delta
	if absf(lx) > 0.1 or absf(ly) > 0.1:
		_look_yaw = lerpf(_look_yaw, -lx * 2.6, delta * 6.0)
		_look_pitch = lerpf(_look_pitch, ly * 0.5, delta * 6.0)
	elif _last_mouse_t < 1.5:
		_look_yaw = clampf(-_mouse_look.x, -3.0, 3.0)
		_look_pitch = clampf(_mouse_look.y * 0.5, -0.4, 0.6)
	else:
		_mouse_look = _mouse_look.lerp(Vector2.ZERO, delta * 3.0)
		_look_yaw = lerpf(_look_yaw, 0.0, delta * 3.0)
		_look_pitch = lerpf(_look_pitch, 0.0, delta * 3.0)
	if Input.is_action_pressed("look_back"):
		_look_yaw = PI
	var target_fov: float = 68.0 + clampf((kmh - 40.0) / 260.0, 0.0, 1.0) * 20.0
	if mode == Mode.CHASE_NEAR or mode == Mode.CHASE_FAR:
		var fwd: Vector3 = -bas.z
		var flat_fwd := Vector3(fwd.x, 0, fwd.z).normalized()
		# blend heading toward the velocity direction so drifts are framed nicely
		if spd > 5.0:
			var vd := Vector3(v.x, 0, v.z).normalized()
			_vel_dir = _vel_dir.slerp(flat_fwd.lerp(vd, 0.35).normalized(), clampf(delta * 3.5, 0.0, 1.0))
		else:
			_vel_dir = _vel_dir.slerp(flat_fwd, clampf(delta * 3.0, 0.0, 1.0))
		var dir: Vector3 = _vel_dir.rotated(Vector3.UP, _look_yaw)
		var far_mode: bool = mode == Mode.CHASE_FAR
		var size_z: float = target.body_aabb.size.z
		var dist: float = (size_z * (1.25 if not far_mode else 1.75) + 1.6) + clampf(kmh / 300.0, 0.0, 1.0) * 1.6
		var height: float = target.body_aabb.size.y * (1.25 if not far_mode else 1.6) + 0.5 + _look_pitch * 3.0
		var focus: Vector3 = target.global_position + Vector3.UP * (target.body_aabb.size.y * 0.75)
		var desired: Vector3 = focus - dir * dist + Vector3.UP * (height - target.body_aabb.size.y * 0.75)
		# critically damped-ish follow: stiffer at speed so the car never escapes the frame
		var k: float = clampf(delta * (7.0 + spd * 0.12), 0.0, 1.0)
		_pos = _pos.lerp(desired, k)
		# keep a sensible distance range
		var off: Vector3 = _pos - focus
		var d: float = off.length()
		if d > dist * 1.35:
			_pos = focus + off / d * dist * 1.35
		# camera collision against world
		var space := get_world_3d().direct_space_state
		var q := PhysicsRayQueryParameters3D.create(focus, _pos, 1)
		q.exclude = [target.get_rid()]
		var hit: Dictionary = space.intersect_ray(q)
		var cam_pos: Vector3 = _pos
		if not hit.is_empty():
			cam_pos = hit.position + (focus - _pos).normalized() * 0.4
		global_position = cam_pos
		look_at(focus + dir * 2.5 + Vector3.UP * 0.2, Vector3.UP)
	else:
		var local: Vector3
		var ab: AABB = target.body_aabb
		match mode:
			Mode.HOOD: local = Vector3(0, ab.end.y * 0.82, ab.position.z * 0.25)
			Mode.BUMPER: local = Vector3(0, ab.position.y + ab.size.y * 0.32, ab.position.z - 0.05)
			_:
				var sw: Node3D = target.steering_wheel
				var base: Vector3 = sw.position if sw else Vector3(-0.38, 1.0, -0.3)
				local = Vector3(base.x, base.y + 0.34, base.z + 0.72)
		var b2: Basis = bas.rotated(bas.y, _look_yaw)
		global_transform = Transform3D(b2, xf * local)
		rotate_object_local(Vector3.RIGHT, -0.04 - _look_pitch * 0.4)
		target_fov += 4.0 if mode == Mode.COCKPIT else 0.0
	fov = lerpf(fov, target_fov, clampf(delta * 3.0, 0.0, 1.0))
	# shake: high speed rumble + impacts
	var sp_shake: float = clampf((kmh - 160.0) / 200.0, 0.0, 1.0) * 0.25
	var amt: float = shake + sp_shake * (0.4 if mode >= Mode.HOOD else 0.25)
	if target.surface_now >= 2 and spd > 8.0:
		amt += 0.12
	if amt > 0.001:
		var o := Vector3(_noise.get_noise_2d(_t * 40.0, 0.0), _noise.get_noise_2d(0.0, _t * 40.0), 0.0) * amt * 0.06
		global_position += global_transform.basis * o
	shake = move_toward(shake, 0.0, delta * 1.8)


func enter_photo() -> void:
	photo_mode = true
	var e: Vector3 = global_transform.basis.get_euler()
	_photo_pitch = e.x
	_photo_yaw = e.y


func exit_photo() -> void:
	photo_mode = false


func _photo_update(delta: float) -> void:
	var mv := Vector3.ZERO
	if Input.is_physical_key_pressed(KEY_W): mv.z -= 1
	if Input.is_physical_key_pressed(KEY_S): mv.z += 1
	if Input.is_physical_key_pressed(KEY_A): mv.x -= 1
	if Input.is_physical_key_pressed(KEY_D): mv.x += 1
	if Input.is_physical_key_pressed(KEY_E): mv.y += 1
	if Input.is_physical_key_pressed(KEY_Q): mv.y -= 1
	var lx: float = Input.get_action_strength("look_right") - Input.get_action_strength("look_left")
	var ly: float = Input.get_action_strength("look_down") - Input.get_action_strength("look_up")
	_photo_yaw -= lx * delta * 1.5
	_photo_pitch = clampf(_photo_pitch - ly * delta * 1.2, -1.4, 1.4)
	basis = Basis.from_euler(Vector3(_photo_pitch, _photo_yaw, 0.0))
	var spd: float = 12.0 if not Input.is_physical_key_pressed(KEY_SHIFT) else 40.0
	var np: Vector3 = global_position + basis * mv * spd * delta
	if target:
		var off: Vector3 = np - target.global_position
		if off.length() > 60.0:
			np = target.global_position + off.normalized() * 60.0
	global_position = np
