class_name CameraRig
extends Node3D
## Driving cameras: chase (near/far) with speed-dependent distance and FOV, hood, cockpit and
## bumper views from the car's CAM_* empties, free look (mouse / right stick), look back,
## camera collision, speed and impact shake, and a slow garage orbit for menus/photo previews.

enum Mode { CHASE, CHASE_FAR, HOOD, COCKPIT, BUMPER }
const MODE_NAMES := ["Chase", "Chase Far", "Hood", "Cockpit", "Bumper"]

var car: CarController
var mode: Mode = Mode.CHASE
var camera: Camera3D
var orbit_mode: bool = false
var orbit_angle: float = 0.0
var frozen: bool = false

var _yaw_smooth: float = 0.0
var _pos: Vector3 = Vector3.ZERO
var _look: Vector3 = Vector3.ZERO
var _fov: float = 70.0
var _free_yaw: float = 0.0
var _free_pitch: float = 0.0
var _free_timer: float = 0.0
var _shake: float = 0.0
var _shake_t: float = 0.0
var _query: PhysicsRayQueryParameters3D
var _snap: bool = true
var _cockpit_lag: Vector3 = Vector3.ZERO
var _mouse_look: Vector2 = Vector2.ZERO


func _ready() -> void:
	camera = Camera3D.new()
	camera.name = "Camera"
	camera.near = 0.08
	camera.far = 6000.0
	camera.fov = 70.0
	camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(camera)
	camera.make_current()
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_query = PhysicsRayQueryParameters3D.new()
	_query.collision_mask = 1
	_query.hit_back_faces = false


func set_car(c: CarController) -> void:
	if car != null and is_instance_valid(car) and car.impact.is_connected(_on_impact):
		car.impact.disconnect(_on_impact)
	car = c
	if car != null:
		car.impact.connect(_on_impact)
		_query.exclude = [car.get_rid()]
	snap()


func snap() -> void:
	_snap = true


func cycle_mode() -> void:
	mode = ((int(mode) + 1) % Mode.size()) as Mode
	snap()
	Game.show_notification("Camera", MODE_NAMES[mode], "info")


func _on_impact(strength: float, _p: Vector3) -> void:
	if Game.settings.get("camera_shake", true):
		_shake = minf(_shake + strength * 0.05, 1.0)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.is_action_pressed("free_look"):
		var m := event as InputEventMouseMotion
		_mouse_look += m.relative


func _process(delta: float) -> void:
	if car == null or not is_instance_valid(car) or frozen:
		return
	if Input.is_action_just_pressed("camera_cycle") and not Game.ui_blocks_driving():
		cycle_mode()
	var xf := car.get_global_transform_interpolated()
	var basis := xf.basis.orthonormalized()
	var speed := car.linear_velocity.length()
	var fwd := -basis.z
	var flat_fwd := Vector3(fwd.x, 0.0, fwd.z)
	if flat_fwd.length() < 0.05:
		flat_fwd = Vector3.FORWARD
	flat_fwd = flat_fwd.normalized()
	var yaw := atan2(-flat_fwd.x, -flat_fwd.z)

	# free look input
	var look_in := Vector2(Input.get_axis("look_left", "look_right"), Input.get_axis("look_up", "look_down"))
	if _mouse_look != Vector2.ZERO:
		_free_yaw -= _mouse_look.x * 0.004
		_free_pitch = clampf(_free_pitch - _mouse_look.y * 0.003, -0.6, 0.9)
		_mouse_look = Vector2.ZERO
		_free_timer = 1.5
	elif look_in.length() > 0.15:
		_free_yaw = lerpf(_free_yaw, -look_in.x * PI * 0.9, 1.0 - exp(-delta * 8.0))
		_free_pitch = lerpf(_free_pitch, look_in.y * 0.5, 1.0 - exp(-delta * 8.0))
		_free_timer = 0.6
	else:
		_free_timer -= delta
		if _free_timer <= 0.0:
			_free_yaw = lerpf(_free_yaw, 0.0, 1.0 - exp(-delta * 3.0))
			_free_pitch = lerpf(_free_pitch, 0.0, 1.0 - exp(-delta * 3.0))
	var look_back := Input.is_action_pressed("look_back") and not Game.ui_blocks_driving()

	if orbit_mode:
		_process_orbit(delta, xf)
		return
	match mode:
		Mode.CHASE, Mode.CHASE_FAR:
			_process_chase(delta, xf, yaw, speed, look_back)
		_:
			_process_attached(delta, xf, speed, look_back)
	_apply_shake(delta, speed)


func _process_chase(delta: float, xf: Transform3D, yaw: float, speed: float, look_back: bool) -> void:
	var far := mode == Mode.CHASE_FAR
	var sp := clampf(speed / 70.0, 0.0, 1.0)
	var dist := lerpf(5.6, 6.6, sp) * (1.45 if far else 1.0)
	var height := lerpf(1.75, 1.95, sp) * (1.3 if far else 1.0)
	var aabb: AABB = car.get_meta("body_aabb", AABB(Vector3(-0.9, 0, -2), Vector3(1.8, 1.4, 4)))
	var size_k := clampf(aabb.size.z / 4.2, 0.9, 1.35)
	dist *= size_k
	height *= clampf(aabb.size.y / 1.4, 0.9, 1.4)
	# yaw lag gives the slide-into-corner feel
	if _snap:
		_yaw_smooth = yaw
	else:
		var diff := wrapf(yaw - _yaw_smooth, -PI, PI)
		_yaw_smooth += diff * (1.0 - exp(-delta * lerpf(5.0, 7.5, sp)))
	var y := _yaw_smooth + _free_yaw + (PI if look_back else 0.0)
	var back := Vector3(sin(y), 0.0, cos(y))
	var pitch_off := _free_pitch
	var target_look := xf.origin + Vector3.UP * (0.95 * size_k) - back * 2.0
	var desired := xf.origin + back * dist * cos(pitch_off) + Vector3.UP * (height + dist * sin(pitch_off))
	if _snap:
		_pos = desired
		_look = target_look
		_snap = false
	else:
		var k := 1.0 - exp(-delta * 14.0)
		_pos = _pos.lerp(desired, k)
		# vertical follow is softer to hide suspension/jump bounce
		_look = _look.lerp(target_look, 1.0 - exp(-delta * 18.0))
	# collision: keep the camera in front of terrain / walls
	var from := xf.origin + Vector3.UP * 1.0
	var cam_pos := _pos
	var space := get_world_3d().direct_space_state
	_query.from = from
	_query.to = cam_pos
	var hit := space.intersect_ray(_query)
	if not hit.is_empty():
		cam_pos = (hit.position as Vector3) + (from - cam_pos).normalized() * 0.3
	# keep above ground directly below
	_query.from = cam_pos + Vector3.UP * 2.0
	_query.to = cam_pos - Vector3.UP * 1.0
	var g := space.intersect_ray(_query)
	if not g.is_empty():
		cam_pos.y = maxf(cam_pos.y, (g.position as Vector3).y + 0.45)
	var fov_target := lerpf(68.0, 86.0, clampf(speed / 75.0, 0.0, 1.0)) * (0.95 if far else 1.0)
	_fov = lerpf(_fov, fov_target, 1.0 - exp(-delta * 3.0))
	camera.fov = _fov
	camera.global_transform = Transform3D(Basis.looking_at(_look - cam_pos, Vector3.UP), cam_pos)


func _process_attached(delta: float, xf: Transform3D, speed: float, look_back: bool) -> void:
	var points: Dictionary = car.get_meta("points", {})
	var key: String = ["", "", "CAM_Hood", "CAM_Cockpit", "CAM_Bumper"][mode]
	var local: Transform3D = points.get(key, Transform3D(Basis.IDENTITY, Vector3(0, 1.2, 0.2)))
	var pos_local := local.origin
	if mode == Mode.COCKPIT:
		# head inertia from g-forces
		var target_lag := Vector3(-car.g_force.x * 0.025, -car.g_force.y * 0.01, car.g_force.z * 0.03)
		_cockpit_lag = _cockpit_lag.lerp(target_lag, 1.0 - exp(-delta * 6.0))
		pos_local += _cockpit_lag
	var cam_xf := xf * Transform3D(Basis.IDENTITY, pos_local)
	var b := xf.basis.orthonormalized()
	var yaw_extra := _free_yaw + (PI if look_back else 0.0)
	var look_basis := b * Basis(Vector3.UP, yaw_extra) * Basis(Vector3.RIGHT, -_free_pitch * 0.7 - (0.035 if mode == Mode.COCKPIT else 0.0))
	camera.global_transform = Transform3D(look_basis, cam_xf.origin)
	var fov_target := (74.0 if mode == Mode.COCKPIT else 72.0) + clampf(speed / 75.0, 0.0, 1.0) * 10.0
	_fov = lerpf(_fov, fov_target, 1.0 - exp(-delta * 3.0))
	camera.fov = _fov
	_snap = false


func _process_orbit(delta: float, xf: Transform3D) -> void:
	orbit_angle += delta * 0.25
	var aabb: AABB = car.get_meta("body_aabb", AABB(Vector3(-0.9, 0, -2), Vector3(1.8, 1.4, 4)))
	var r := maxf(aabb.size.z, 3.5) * 1.25
	var center := xf.origin + Vector3.UP * 0.7
	var pos := center + Vector3(sin(orbit_angle) * r, 1.1, cos(orbit_angle) * r)
	camera.global_transform = Transform3D(Basis.looking_at(center - pos, Vector3.UP), pos)
	camera.fov = lerpf(camera.fov, 50.0, 1.0 - exp(-delta * 3.0))
	_snap = true


func _apply_shake(delta: float, speed: float) -> void:
	_shake_t += delta
	_shake = maxf(_shake - delta * 1.8, 0.0)
	var speed_shake := 0.0
	if Game.settings.get("camera_shake", true):
		speed_shake = smoothstep(45.0, 95.0, speed) * 0.006
		if car.grounded_wheels > 0 and not Surfaces.is_paved(car.surface_under):
			speed_shake += clampf(speed / 30.0, 0.0, 1.0) * 0.008
	var amp := speed_shake + _shake * 0.06
	if amp <= 0.0:
		return
	var off := Vector3(sin(_shake_t * 37.0) + sin(_shake_t * 23.0) * 0.5, sin(_shake_t * 41.0 + 1.3) + sin(_shake_t * 17.0) * 0.5, 0.0) * amp
	camera.global_transform = camera.global_transform.translated_local(off)
