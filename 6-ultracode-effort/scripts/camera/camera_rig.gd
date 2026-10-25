class_name CameraRig
extends Node3D
## Chase (near/far), hood, bumper and cockpit cameras with smooth transitions, speed-dependent FOV
## and distance, camera collision, free look (hold right mouse button and drag), look-back and shake.

enum Mode { CHASE_NEAR, CHASE_FAR, HOOD, BUMPER, COCKPIT }
const MODE_NAMES := ["Chase", "Chase Far", "Hood", "Bumper", "Cockpit"]

signal mode_changed(mode: int)

var target: CarController
var camera: Camera3D
var mode: int = Mode.CHASE_NEAR
## When false (photo mode etc.) the rig stops driving the camera.
var active: bool = true

var _yaw: float = 0.0
var _pitch: float = 0.0
var _cam_y: float = 0.0
var _trauma: float = 0.0
var _blend: float = 1.0
## Blend start pose relative to the car (a world-space start would fall behind the car at speed).
var _from_local: Transform3D
var _snap_fov := false
var _free_yaw: float = 0.0
var _free_pitch: float = 0.0
var _free_idle: float = 0.0
var _noise := FastNoiseLite.new()
var _t: float = 0.0
var _dist_smooth: float = 5.5
var _fov_smooth: float = 65.0
var _clip_k: float = 0.0
var _ray := PhysicsRayQueryParameters3D.new()
var _initialized := false


func _ready() -> void:
	top_level = true
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	camera = Camera3D.new()
	camera.name = "Camera"
	camera.near = 0.05
	camera.far = 9000.0
	camera.fov = 65.0
	camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(camera)
	camera.current = true
	_noise.seed = 7
	_noise.frequency = 0.9
	_ray.collision_mask = 1 | 32
	mode = int(Settings.get_value("camera_mode", 0))


func set_target(car: CarController) -> void:
	if target and is_instance_valid(target) and target.impact.is_connected(_on_impact):
		target.impact.disconnect(_on_impact)
	target = car
	if target:
		target.impact.connect(_on_impact)
		snap()


func snap() -> void:
	_initialized = false


func cycle_mode() -> void:
	set_mode((mode + 1) % MODE_NAMES.size())


func set_mode(m: int, persist := true) -> void:
	if m <= Mode.CHASE_FAR and mode <= Mode.CHASE_FAR and target != null and is_instance_valid(target):
		_from_local = target.get_global_transform_interpolated().affine_inverse() * global_transform
		_blend = 0.0
	else:
		# To or from a view attached to the car: cut (a blend would fly through the body).
		_blend = 1.0
		_snap_fov = true
	mode = m
	if persist:
		Settings.set_value("camera_mode", m)
	mode_changed.emit(m)


func add_trauma(amount: float) -> void:
	_trauma = clampf(_trauma + amount, 0.0, 1.0)


func _on_impact(strength: float, _pos: Vector3) -> void:
	add_trauma(clampf(strength * 0.08, 0.0, 0.7))


func _unhandled_input(event: InputEvent) -> void:
	if not active or Game.is_overlay_open():
		return
	if event.is_action_pressed("camera_next"):
		cycle_mode()
	elif event is InputEventMouseMotion and Input.is_action_pressed("free_look"):
		var mm := event as InputEventMouseMotion
		_free_yaw -= mm.relative.x * 0.005
		_free_pitch = clampf(_free_pitch - mm.relative.y * 0.004, -0.6, 0.9)
		_free_idle = 0.0


func _process(delta: float) -> void:
	if not active or target == null or not is_instance_valid(target):
		return
	_t += delta
	var t := target.get_global_transform_interpolated()
	var spd := target.linear_velocity.length()
	# Free look returns to centre shortly after the right mouse button is released.
	if not Input.is_action_pressed("free_look"):
		_free_idle += delta
		if _free_idle > 0.6:
			_free_yaw = lerp_angle(_free_yaw, 0.0, clampf(delta * 3.0, 0.0, 1.0))
			_free_pitch = lerpf(_free_pitch, 0.0, clampf(delta * 3.0, 0.0, 1.0))

	var xf: Transform3D
	var look_back := Input.is_action_pressed("look_back") and not Game.is_overlay_open()
	if mode <= Mode.CHASE_FAR or look_back:
		xf = _chase(t, delta, spd, look_back)
	else:
		xf = _attached(t, delta)
		# Chase state goes stale while attached; re-seed it when chase/look-back next runs.
		_initialized = false
	if _blend < 1.0:
		_blend = minf(_blend + delta / 0.35, 1.0)
		var e := _blend * _blend * (3.0 - 2.0 * _blend)
		xf = (t * _from_local).interpolate_with(xf, e)
	# Shake: impacts (trauma) + subtle high-speed rumble.
	_trauma = maxf(_trauma - delta * 1.4, 0.0)
	var shake_scale := float(Settings.get_value("camera_shake", 1.0))
	var amp := (_trauma * _trauma * 0.06 + clampf((spd - 35.0) / 60.0, 0.0, 1.0) * 0.0035) * shake_scale
	if amp > 0.0001:
		var rx := _noise.get_noise_2d(_t * 40.0, 0.0) * amp
		var ry := _noise.get_noise_2d(0.0, _t * 40.0) * amp
		var rz := _noise.get_noise_2d(_t * 40.0, 100.0) * amp * 0.6
		xf.basis = xf.basis * Basis.from_euler(Vector3(rx, ry, rz))
	global_transform = xf
	# FOV: wider with speed in chase views.
	var base_fov := 66.0 if mode <= Mode.CHASE_FAR else 72.0
	var target_fov := base_fov + clampf(spd / 85.0, 0.0, 1.0) * (16.0 if mode <= Mode.CHASE_FAR else 10.0)
	_fov_smooth = target_fov if _snap_fov else lerpf(_fov_smooth, target_fov, clampf(delta * 3.0, 0.0, 1.0))
	_snap_fov = false
	camera.fov = _fov_smooth
	camera.near = 0.04 if mode == Mode.COCKPIT else 0.1


func _chase(t: Transform3D, delta: float, spd: float, look_back: bool) -> Transform3D:
	var fwd := -t.basis.z
	var car_yaw := atan2(fwd.x, fwd.z)
	var target_yaw := car_yaw
	var vel := target.linear_velocity
	if spd > 6.0 and vel.dot(fwd) > 0.0:
		# Follow the direction of travel a little during slides.
		var vyaw := atan2(vel.x, vel.z)
		target_yaw = lerp_angle(car_yaw, vyaw, 0.35)
	var reseed := not _initialized
	if reseed:
		_yaw = target_yaw
		_cam_y = t.origin.y
		_pitch = 0.0
		_clip_k = 0.0
		_initialized = true
	var follow := 5.0 + clampf(spd / 40.0, 0.0, 1.0) * 3.0
	_yaw = lerp_angle(_yaw, target_yaw, 1.0 - exp(-delta * follow))
	var car_pitch := asin(clampf(fwd.y, -1.0, 1.0))
	_pitch = lerpf(_pitch, car_pitch * 0.75, 1.0 - exp(-delta * 4.0))
	var body_h := target.data.body_size.y if target.data else 1.4
	var far := mode == Mode.CHASE_FAR
	var base_dist := (7.4 if far else 5.0) + body_h * 0.6
	var dist := base_dist + clampf(spd / 80.0, 0.0, 1.0) * 1.2
	_dist_smooth = dist if reseed else lerpf(_dist_smooth, dist, 1.0 - exp(-delta * 2.0))
	var height := body_h * (1.1 if far else 0.95) + (0.9 if far else 0.45)
	var yaw := _yaw + _free_yaw + (PI if look_back else 0.0)
	var dir := Vector3(sin(yaw) * cos(_pitch), sin(_pitch), cos(yaw) * cos(_pitch))
	_cam_y = lerpf(_cam_y, t.origin.y, 1.0 - exp(-delta * 10.0))
	var anchor := Vector3(t.origin.x, _cam_y, t.origin.z)
	var pos := anchor - dir * _dist_smooth + Vector3.UP * (height + _free_pitch * 2.5)
	var look := anchor + Vector3.UP * (body_h * 0.62) + dir * (2.0 + spd * 0.04)
	# Camera collision against the world.
	var space := get_world_3d().direct_space_state
	var from := t.origin + Vector3.UP * (body_h + 0.2)
	_ray.from = from
	_ray.to = pos
	var hit := space.intersect_ray(_ray)
	var clip_k := 0.0
	if not hit.is_empty():
		pos = (hit["position"] as Vector3) + (hit["normal"] as Vector3) * 0.25
		# A wall right behind the tail would leave the camera hugging the roof: the closer the wall, the
		# higher the camera rises over the car and the more it looks down at it.
		var body_l := target.data.body_size.z if target.data else 4.3
		var back := Vector2(pos.x - t.origin.x, pos.z - t.origin.z).length()
		var need := body_l * 0.5 + 2.5
		clip_k = clampf((need - back) / (need - body_l * 0.25), 0.0, 1.0)
	_clip_k = lerpf(_clip_k, clip_k, 1.0 - exp(-delta * (10.0 if clip_k > _clip_k else 4.0)))
	if _clip_k > 0.001:
		var lifted := pos + Vector3.UP * (_clip_k * (body_h + 1.6))
		_ray.from = pos
		_ray.to = lifted
		var roof := space.intersect_ray(_ray)
		if roof.is_empty():
			pos = lifted
		else:
			pos.y = maxf(pos.y, (roof["position"] as Vector3).y - 0.25)
		look = look.lerp(anchor + Vector3.UP * (body_h * 0.3) + dir * 1.2, _clip_k)
	# Keep above ground. The probe starts below any roof over the camera (tunnel arch, bridge deck).
	var probe_top := pos + Vector3.UP * 3.0
	_ray.from = pos
	_ray.to = probe_top
	var over := space.intersect_ray(_ray)
	if not over.is_empty():
		probe_top = (over["position"] as Vector3) - Vector3.UP * 0.05
	_ray.from = probe_top
	_ray.to = pos - Vector3.UP * 2.0
	var g := space.intersect_ray(_ray)
	if not g.is_empty():
		pos.y = clampf((g["position"] as Vector3).y + 0.45, pos.y, maxf(probe_top.y - 0.2, pos.y))
	var xf := Transform3D(Basis(), pos)
	if pos.distance_to(look) > 0.01:
		xf = xf.looking_at(look, Vector3.UP)
	return xf


func _attached(t: Transform3D, _delta: float) -> Transform3D:
	var vis := target.get_node_or_null("Visual") as CarVisuals
	var key := "Socket_CamHood"
	match mode:
		Mode.BUMPER:
			key = "Socket_CamBumper"
		Mode.COCKPIT:
			key = "Socket_CamCockpit"
	var local := Transform3D.IDENTITY
	var bs := target.data.body_size if target.data else Vector3(1.8, 1.4, 4.4)
	if vis and vis.sockets.has(key):
		local.origin = (vis.sockets[key] as Transform3D).origin
	else:
		match mode:
			Mode.BUMPER:
				local.origin = Vector3(0.0, 0.55, -bs.z * 0.5 - 0.05)
			Mode.COCKPIT:
				local.origin = Vector3(-0.36, bs.y * 0.82, 0.1)
			_:
				local.origin = Vector3(0.0, bs.y * 0.92, -bs.z * 0.12)
	if mode == Mode.COCKPIT:
		# Head motion from g-forces.
		local.origin += Vector3(-target.lateral_g * 0.025, -absf(target.longitudinal_g) * 0.01, target.longitudinal_g * 0.03)
	local.basis = Basis.from_euler(Vector3(_free_pitch * 0.6 - deg_to_rad(4.0 if mode == Mode.COCKPIT else 1.5), _free_yaw, 0.0))
	return t * local
