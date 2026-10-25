class_name TrafficCar
extends RigidBody3D
## One pooled civilian vehicle. A "ghost" follows the lane (managed by TrafficManager); the body
## is moved kinematically at mid range, and near the player it is a dynamic body tracking the
## ghost with bounded PD forces so the player can push, spin or block it. Hard impacts switch it
## to a crashed obstacle that recovers to its lane or is despawned out of view.

enum Mode { IDLE, KINEMATIC, PHYSICS, CRASHED }

var ttype: TrafficType
var visual: CarVisual
var mode := Mode.IDLE
# lane state (owned by TrafficManager)
var edge := 0
var dir := 1
var lane := 0
var s := 0.0              ## sample steps (2 m) travelled along the edge in travel direction
var speed := 0.0
var target_speed := 20.0
var desire := 1.0          ## personal speed factor
var next_edge := -1
var next_dir := 1
var blend := Vector3.ZERO  ## decaying offset after switching edges
var ghost := Transform3D.IDENTITY
var ghost_vel := Vector3.ZERO
var yielding := false
var blocked_by_player := 0.0
var crash_timer := 0.0
var idle_timer := 0.0
var horn_cooldown := 0.0
var _half_h := 0.7
var _wheel_r := 0.33
var _rays := []
var _spin := 0.0
var _prev_v := Vector3.ZERO


func setup(tt: TrafficType, model_scene_path: String, id_prefix: String) -> void:
	ttype = tt
	mass = tt.mass
	can_sleep = false
	continuous_cd = false
	collision_layer = 4
	collision_mask = 1 | 2 | 4
	contact_monitor = true
	max_contacts_reported = 2
	visual = CarVisual.new()
	visual.name = "Visual"
	add_child(visual)
	visual.load_model(model_scene_path, id_prefix)
	for s2 in visual.head_spots:
		s2.queue_free()
	visual.head_spots.clear()
	var aabb := visual.body_aabb()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(aabb.size.x * 0.95, aabb.size.y * 0.8, aabb.size.z * 0.97)
	cs.shape = bs
	cs.position = aabb.get_center() + Vector3(0, aabb.size.y * 0.08, 0)
	add_child(cs)
	_half_h = 0.0
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3(0, aabb.size.y * 0.35, 0)
	for p in visual.wheel_rest_positions():
		_rays.append(p)
	_wheel_r = visual.wheel_radius_front
	set_mode(Mode.IDLE)


func set_mode(m: Mode) -> void:
	mode = m
	match m:
		Mode.IDLE:
			visible = false
			freeze = true
			freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
			collision_layer = 0
			process_mode = Node.PROCESS_MODE_DISABLED
		Mode.KINEMATIC:
			visible = true
			freeze = true
			freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
			collision_layer = 4
			process_mode = Node.PROCESS_MODE_INHERIT
		Mode.PHYSICS, Mode.CRASHED:
			visible = true
			collision_layer = 4
			process_mode = Node.PROCESS_MODE_INHERIT
			if freeze:
				freeze = false
				linear_velocity = ghost_vel
				angular_velocity = Vector3.ZERO
			_prev_v = linear_velocity


func place_at_ghost() -> void:
	var xf := ghost
	PhysicsServer3D.body_set_state(get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM, xf)
	global_transform = xf
	reset_physics_interpolation()


func _physics_process(delta: float) -> void:
	if mode == Mode.KINEMATIC:
		global_transform = ghost
	horn_cooldown = maxf(horn_cooldown - delta, 0.0)
	# visuals: wheels roll with speed, brake lights when slowing
	var v := linear_velocity.length() if mode >= Mode.PHYSICS else speed
	_spin = fmod(_spin + v / 0.33 * delta, TAU)
	for i in visual.wheel_spinners.size():
		visual.wheel_spinners[i].rotation.x = -_spin


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if mode != Mode.PHYSICS and mode != Mode.CRASHED:
		return
	var dt := state.step
	var xf := state.transform
	var up := xf.basis.y
	var space := state.get_space_state()
	var grounded := 0
	# four simple suspension rays keep the body riding on the road
	for p: Vector3 in _rays:
		var from := xf * (p + Vector3.UP * 0.6)
		var q := PhysicsRayQueryParameters3D.create(from, from - up * 1.4, 1)
		q.exclude = [get_rid()]
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			continue
		grounded += 1
		var dist := from.distance_to(hit.position)
		var comp := (0.65 + _wheel_r) - dist
		var vel_up := state.get_velocity_at_local_position(xf.basis * p).dot(up)
		var f := maxf(comp * mass * 9.81 * 0.25 / 0.05 - vel_up * mass * 2.0, 0.0)
		state.apply_force(up * f, xf.basis * p)
	var v := state.linear_velocity
	if mode == Mode.CRASHED:
		# rolling friction while wrecked/stopped
		if grounded > 0:
			var hv := v - up * v.dot(up)
			state.apply_central_force(-hv.limit_length(6.0) * mass * 0.9)
			state.apply_torque(-state.angular_velocity * mass * 1.2)
		return
	# bounded PD tracking of the lane ghost (collisions can overpower it)
	var e := ghost.origin - xf.origin
	e.y = 0.0
	var ve := ghost_vel - v
	ve.y = 0.0
	var fpd := (e * 6.0 + ve * 3.2) * mass
	var fmax := mass * 9.81 * 0.95
	if grounded > 0:
		state.apply_central_force(fpd.limit_length(fmax))
	var fwd := -xf.basis.z
	var gf := -ghost.basis.z
	var yaw_err := Vector3(fwd.x, 0, fwd.z).normalized().signed_angle_to(Vector3(gf.x, 0, gf.z).normalized(), Vector3.UP)
	var yaw_rate := state.angular_velocity.dot(Vector3.UP)
	state.apply_torque(Vector3.UP * (yaw_err * 5.0 - yaw_rate * 2.2) * mass * 2.2)
	# keep upright
	state.apply_torque(up.cross(ghost.basis.y) * mass * 12.0 - (state.angular_velocity - Vector3.UP * yaw_rate) * mass * 1.5)
	# hard impact or big deviation -> crashed obstacle
	var dv := (v - _prev_v).length()
	_prev_v = v
	if (dv > 3.0 and state.get_contact_count() > 0) or e.length() > 6.0 or absf(yaw_err) > 1.0:
		mode = Mode.CRASHED
		crash_timer = 0.0
