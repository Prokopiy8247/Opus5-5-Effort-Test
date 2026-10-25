class_name CarCamera
extends Camera3D
## Chase (near/far), hood, cockpit and bumper cameras with speed FOV, swing during slides,
## free look, look-back, terrain collision and speed/impact shake. Runs in _process on the
## physics-interpolated car transform.

enum Mode { CHASE_NEAR, CHASE_FAR, HOOD, COCKPIT, BUMPER }
const MODE_NAMES := ["Chase", "Chase Far", "Hood", "Cockpit", "Bumper"]

var target: CarController
var mode := Mode.CHASE_NEAR
var free_look := Vector2.ZERO
var shake_amount := 0.0
var enabled_follow := true
var _dir := Vector3.FORWARD
var _pos := Vector3.ZERO
var _initialized := false
var _noise := FastNoiseLite.new()
var _t := 0.0
var _mouse_look := Vector2.ZERO
var _mouse_timer := 0.0
var _smoothed_accel := Vector3.ZERO
var _prev_vel := Vector3.ZERO
var _fov_cur := 70.0


func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_noise.frequency = 0.9
	near = 0.08
	far = 6000.0
	current = true


func set_target(car: CarController) -> void:
	target = car
	_initialized = false
	if target != null:
		target.impact.connect(_on_impact)


func next_mode() -> void:
	mode = ((mode + 1) % Mode.size()) as Mode
	_initialized = false
	Game.notify("Camera", MODE_NAMES[mode], "small")


func _on_impact(strength: float, _at: Vector3) -> void:
	shake_amount = minf(shake_amount + strength * 0.03, 0.6)


func _unhandled_input(event: InputEvent) -> void:
	if Game.input_blocked():
		return
	if event.is_action_pressed("camera_next"):
		next_mode()
	elif event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		_mouse_look += (event as InputEventMouseMotion).relative * 0.005
		_mouse_look.y = clampf(_mouse_look.y, -0.6, 0.9)
		_mouse_timer = 1.5


func _process(delta: float) -> void:
	if target == null or not is_instance_valid(target) or not enabled_follow:
		return
	_t += delta
	var xf := target.get_global_transform_interpolated()
	var car_pos := xf.origin
	var fwd := -xf.basis.z
	var vel := target.linear_velocity
	var spd := vel.length()
	var kmh := spd * 3.6
	# free look (right mouse drag), springs back when released
	if _mouse_timer > 0.0:
		_mouse_timer -= delta
		free_look = free_look.lerp(Vector2(_mouse_look.x, _mouse_look.y), 1.0 - exp(-12.0 * delta))
	else:
		_mouse_look = _mouse_look.lerp(Vector2.ZERO, 1.0 - exp(-4.0 * delta))
		free_look = free_look.lerp(Vector2.ZERO, 1.0 - exp(-8.0 * delta))
	var look_back := Input.is_action_pressed("look_back") and not Game.input_blocked()
	# acceleration for head movement
	var acc := (vel - _prev_vel) / maxf(delta, 0.001)
	_prev_vel = vel
	_smoothed_accel = _smoothed_accel.lerp(acc, 1.0 - exp(-5.0 * delta))
	shake_amount = move_toward(shake_amount, 0.0, delta * 0.8)
	var speed_shake := clampf((kmh - 120.0) / 250.0, 0.0, 1.0) * 0.012
	var surf := target.dominant_surface()
	if surf != null and not surf.paved:
		speed_shake += clampf(kmh / 150.0, 0.0, 1.0) * 0.01
	var sh := shake_amount * 0.15 + speed_shake
	var shake_off := Vector3(_noise.get_noise_2d(_t * 40.0, 0.0), _noise.get_noise_2d(0.0, _t * 40.0), 0.0) * sh

	var target_fov := 68.0
	match mode:
		Mode.CHASE_NEAR, Mode.CHASE_FAR:
			var far_mode := mode == Mode.CHASE_FAR
			var flat_fwd := Vector3(fwd.x, 0.0, fwd.z)
			if flat_fwd.length() < 0.05:
				flat_fwd = _dir
			flat_fwd = flat_fwd.normalized()
			var desired := flat_fwd
			if spd > 3.0 and target.speed > 0.0:
				var vdir := Vector3(vel.x, 0.0, vel.z).normalized()
				desired = flat_fwd.lerp(vdir, 0.3).normalized()
			if look_back:
				desired = -desired
			if not _initialized:
				_dir = desired
			var follow := 1.0 - exp(-(5.0 if not look_back else 30.0) * delta)
			_dir = _dir.slerp(desired, follow).normalized() if _dir.dot(desired) > -0.98 else desired
			var d := _dir.rotated(Vector3.UP, -free_look.x)
			var aabb_len := target.visual.body_aabb().size.z if target.visual else 4.4
			var dist := (aabb_len * 0.92 + 1.3) * (1.5 if far_mode else 1.0) + clampf(spd * 0.014, 0.0, 1.3)
			var height := (1.8 if not far_mode else 2.5) + clampf(spd * 0.003, 0.0, 0.3) + free_look.y * 2.0
			var pivot := car_pos + Vector3.UP * 1.0
			var want := pivot - d * dist + Vector3.UP * (height - 1.0)
			# collision: keep the camera out of terrain and walls
			var space := get_world_3d().direct_space_state
			var q := PhysicsRayQueryParameters3D.create(pivot, want, 1)
			q.exclude = [target.get_rid()]
			var hit := space.intersect_ray(q)
			if not hit.is_empty():
				want = hit.position + (pivot - want).normalized() * 0.35 + Vector3.UP * 0.2
			var gq := PhysicsRayQueryParameters3D.create(want + Vector3.UP * 3.0, want - Vector3.UP * 3.0, 1)
			var ghit := space.intersect_ray(gq)
			if not ghit.is_empty():
				want.y = maxf(want.y, ghit.position.y + 0.45)
			if not _initialized:
				_pos = want
				_initialized = true
			_pos = _pos.lerp(want, 1.0 - exp(-14.0 * delta))
			global_position = _pos + shake_off
			var look := car_pos + d * 4.0 + Vector3.UP * (0.62 + free_look.y * 0.5)
			look_at(look, Vector3.UP)
			target_fov = 66.0 + clampf(kmh / 300.0, 0.0, 1.0) * 16.0
		_:
			var key := "Hood"
			if mode == Mode.COCKPIT:
				key = "Cockpit"
			elif mode == Mode.BUMPER:
				key = "Bumper"
			var sock: Transform3D = target.visual.sockets.get(key, Transform3D(Basis.IDENTITY, Vector3(0, 1.1, -0.5)))
			var p := xf * sock.origin
			var basis := xf.basis.orthonormalized()
			if mode == Mode.COCKPIT:
				var local_acc := basis.inverse() * _smoothed_accel
				p += basis * Vector3(-local_acc.x * 0.004, -absf(local_acc.y) * 0.002, local_acc.z * 0.004).limit_length(0.06)
			var yaw := -free_look.x + (PI if look_back else 0.0)
			basis = basis * Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, -free_look.y * 0.6 - deg_to_rad(4.0 if mode == Mode.COCKPIT else 2.0))
			global_transform = Transform3D(basis, p + basis * shake_off * 0.5)
			_initialized = true
			target_fov = (74.0 if mode == Mode.COCKPIT else 72.0) + clampf(kmh / 300.0, 0.0, 1.0) * 10.0
	_fov_cur = lerpf(_fov_cur, target_fov, 1.0 - exp(-3.0 * delta))
	fov = _fov_cur
	if target.visual != null and target.visual.interior_mesh != null:
		target.visual.interior_mesh.visible = mode == Mode.COCKPIT or mode == Mode.CHASE_NEAR or mode == Mode.CHASE_FAR
