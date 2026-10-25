class_name CarCamera
extends Camera3D
## Chase / hood / bumper / cockpit camera with speed FOV, lag, collision, shake and free look.

enum Mode { CHASE_NEAR, CHASE_FAR, HOOD, BUMPER, COCKPIT }
const MODE_NAMES := ["Chase", "Chase Far", "Hood", "Bumper", "Cockpit"]

var target: Car
var mode: int = Mode.CHASE_NEAR
var free_look := Vector2.ZERO
var _mouse_look := Vector2.ZERO
var _mouse_timer := 0.0
var _shake := 0.0
var _yaw_dir := Vector3.FORWARD
var _pos := Vector3.ZERO
var _fov := 70.0
var _blend := 1.0
var _prev_mode := 0
var _ray := PhysicsRayQueryParameters3D.new()
var enabled_follow := true
## Garage view: slow orbit around the car.
var orbit := false
var _orbit_angle := 0.6


func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	near = 0.05
	far = 6000.0
	fov = 70.0
	mode = int(Game.settings.get("camera", 0))


func attach(car: Car) -> void:
	if target and target.impact.is_connected(_on_impact):
		target.impact.disconnect(_on_impact)
	target = car
	target.impact.connect(_on_impact)
	_yaw_dir = -car.global_transform.basis.z
	_pos = car.global_position - _yaw_dir * 7.0 + Vector3.UP * 2.5
	global_position = _pos


func _on_impact(s: float) -> void:
	_shake = maxf(_shake, clampf(s / 25.0, 0.0, 1.0) * 0.6)


func cycle_mode() -> void:
	_prev_mode = mode
	mode = (mode + 1) % Mode.size()
	_blend = 0.0
	Game.settings.camera = mode


func _unhandled_input(event: InputEvent) -> void:
	if not enabled_follow:
		return
	if event.is_action_pressed("camera_next"):
		cycle_mode()
	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		_mouse_look += (event as InputEventMouseMotion).relative * 0.005
		_mouse_look.y = clampf(_mouse_look.y, -0.6, 0.8)
		_mouse_timer = 1.5


func _process(delta: float) -> void:
	var _t0 := Time.get_ticks_usec()
	_process_inner(delta)
	Game.prof_add("camera", Time.get_ticks_usec() - _t0)


func _process_inner(delta: float) -> void:
	if not enabled_follow or target == null or not is_instance_valid(target):
		return
	_update(delta)


func _update(delta: float) -> void:
	var car := target
	var cxf := car.get_global_transform_interpolated()
	var car_pos := cxf.origin
	var b := cxf.basis.orthonormalized()
	var fwd := -b.z
	var up := Vector3.UP
	var vel := car.linear_velocity
	var spd := vel.length()
	# free look (right stick or right mouse drag)
	var stick := Vector2(Input.get_action_strength("look_right") - Input.get_action_strength("look_left"), 0.0)
	if Input.is_action_pressed("look_back"):
		stick.x = 2.0
	if _mouse_timer > 0.0:
		_mouse_timer -= delta
		free_look = _mouse_look
	else:
		_mouse_look = _mouse_look.lerp(Vector2.ZERO, delta * 3.0)
		free_look = free_look.lerp(Vector2(stick.x * PI * 0.5, 0.0), clampf(delta * 6.0, 0.0, 1.0))
	_blend = minf(_blend + delta * 2.5, 1.0)
	if orbit:
		if not Game.settings.get("qa_freeze_orbit", false):
			_orbit_angle += delta * 0.25
		var od := Vector3(sin(_orbit_angle), 0.0, cos(_orbit_angle))
		var target_pos := car_pos + od * 7.8 + Vector3.UP * 2.1
		_pos = target_pos
		global_position = _pos
		look_at(car_pos + Vector3.UP * 0.7 + b.x * 0.9, Vector3.UP)
		fov = lerpf(fov, 55.0, clampf(delta * 3.0, 0.0, 1.0))
		h_offset = 0.0
		v_offset = 0.0
		return
	var target_fov := 68.0 + clampf((spd - 15.0) / 60.0, 0.0, 1.0) * 18.0
	_fov = lerpf(_fov, target_fov, clampf(delta * 2.0, 0.0, 1.0))
	if mode == Mode.CHASE_NEAR or mode == Mode.CHASE_FAR:
		var far_m := mode == Mode.CHASE_FAR
		var dist := (7.2 if not far_m else 10.5) + clampf(spd / 70.0, 0.0, 1.0) * 1.6
		var height := (2.1 if not far_m else 3.0)
		# follow the heading, blending toward velocity while sliding so drifts stay framed
		var flat_fwd := Vector3(fwd.x, 0.0, fwd.z).normalized()
		var vdir := Vector3(vel.x, 0.0, vel.z)
		var desired := flat_fwd
		if spd > 6.0 and car.forward_speed > 0.0:
			desired = flat_fwd.slerp(vdir.normalized(), 0.45).normalized()
		elif car.forward_speed < -2.0:
			desired = flat_fwd
		_yaw_dir = _yaw_dir.slerp(desired, clampf(delta * 4.5, 0.0, 1.0)).normalized()
		var dir := _yaw_dir.rotated(Vector3.UP, free_look.x)
		var pivot := car_pos + up * 1.15
		var want := pivot - dir * dist + up * (height - 1.15 + free_look.y * 3.0)
		# collision: pull the camera in front of terrain / walls
		_ray.from = pivot
		_ray.to = want
		_ray.collision_mask = 1
		_ray.exclude = [car.get_rid()]
		var hit := get_world_3d().direct_space_state.intersect_ray(_ray)
		if not hit.is_empty():
			want = (hit.position as Vector3) + ((pivot - want).normalized()) * 0.4
		# keep above the ground
		if Game.world != null:
			var gh: float = Game.world.height_at(want.x, want.z) + 0.6
			want.y = maxf(want.y, gh)
		var k := clampf(delta * 12.0, 0.0, 1.0)
		_pos = _pos.lerp(want, k) if _blend >= 1.0 else _pos.lerp(want, clampf(delta * 6.0, 0.0, 1.0))
		var look_at_pt := car_pos + up * 0.9 + dir * 3.0
		global_position = _pos
		look_at(look_at_pt, Vector3.UP)
		fov = _fov
	else:
		var local := Vector3.ZERO
		match mode:
			Mode.HOOD:
				local = car.markers.get("Mk_Hood", Vector3(0, 1.25, -0.6))
			Mode.BUMPER:
				local = car.markers.get("Mk_Bumper", Vector3(0, 0.55, -2.3))
			Mode.COCKPIT:
				local = car.markers.get("Mk_Cockpit", Vector3(-0.36, 1.12, 0.2))
		var xf := Transform3D(b, cxf.origin) * Transform3D(Basis(Vector3.UP, -free_look.x) * Basis(Vector3.RIGHT, -free_look.y * 0.5 - (0.05 if mode == Mode.COCKPIT else 0.0)), local)
		if _blend < 1.0:
			global_transform = global_transform.interpolate_with(xf, _blend)
		else:
			global_transform = xf
		_pos = global_position
		fov = _fov + (4.0 if mode == Mode.COCKPIT else 0.0)
	# shake: high speed rumble + impacts
	var speed_shake := clampf((spd - 40.0) / 40.0, 0.0, 1.0) * 0.012
	if car.wheels_on_ground > 0:
		var surf := Game.surface(car.surface_id)
		speed_shake += surf.bumpiness * clampf(spd / 20.0, 0.0, 1.0) * 0.4
	_shake = maxf(_shake - delta * 1.6, 0.0)
	var amp := speed_shake + _shake * 0.12
	if amp > 0.0001:
		var t := Time.get_ticks_msec() * 0.001
		h_offset = sin(t * 37.0) * amp
		v_offset = cos(t * 43.0) * amp
	else:
		h_offset = 0.0
		v_offset = 0.0
