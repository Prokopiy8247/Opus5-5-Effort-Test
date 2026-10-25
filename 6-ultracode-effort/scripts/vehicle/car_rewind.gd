extends Node
## Rewind for the player car: records its state at 30 Hz for the last 15 s.
## Hold the "rewind" action to scrub back (car frozen, 2x speed; the HUD and effects follow the recorded state);
## release to resume with the recorded velocities, gear and damage. Other vehicles are ignored while scrubbing,
## and the car resumes at a recorded spot clear of traffic and rivals. An event can veto the rewind
## (Game.activities.rewind_blocked()) and is told when one starts (on_player_rewind()).

const RATE := 30.0
const SECONDS := 15.0
## Physics layer of traffic and rival cars.
const VEHICLE_LAYER := 4
## Seconds a vehicle the car was resumed next to stays non-colliding at most (until the two are apart).
const GHOST_MAX := 3.0

var car: CarController
## [Transform3D, linear_velocity, angular_velocity, gear, rpm, damage, surface id, wheel contact bits]
var _buf: Array[Array] = []
var _acc: float = 0.0
var _rewinding: bool = false
var _cursor: float = 0.0
var _label: Label
var _layer: CanvasLayer
## The rewind key was refused during an event: notify once per press.
var _refused: bool = false
## Vehicles the car ignores while scrubbing (and right after resuming, until they are apart).
var _ghosts: Array[PhysicsBody3D] = []
var _ghost_t: float = 0.0
var _shape := BoxShape3D.new()
var _query := PhysicsShapeQueryParameters3D.new()


func _ready() -> void:
	car = get_parent() as CarController
	process_physics_priority = 5
	_layer = CanvasLayer.new()
	_layer.layer = 40
	add_child(_layer)
	_label = Label.new()
	_label.text = "<<  REWIND"
	_label.add_theme_font_size_override("font_size", 40)
	_label.add_theme_color_override("font_color", Color(1.0, 0.75, 0.3))
	_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	_label.add_theme_constant_override("outline_size", 8)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# Top centre, below the activity panel (y 20..146) and above the result banner (from y 231).
	_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_label.offset_left = -220.0
	_label.offset_right = 220.0
	_label.offset_top = 170.0
	_label.offset_bottom = 226.0
	_label.visible = false
	_layer.add_child(_label)
	_query.shape = _shape
	_query.collision_mask = VEHICLE_LAYER


func _physics_process(delta: float) -> void:
	if car == null or not car.is_player:
		return
	_update_ghosts(delta)
	var pressed := Input.is_action_pressed("rewind")
	if not pressed:
		_refused = false
	var want := pressed and not Game.is_overlay_open() and not Game.photo_mode
	# Never take over a car someone else froze (fast-travel hold, race countdown, loading).
	if want and not _rewinding and (_buf.is_empty() or car.freeze or _event_refuses()):
		want = false
	if want:
		if not _rewinding:
			_begin()
		_cursor = maxf(_cursor - delta * RATE * 2.0, 0.0)
		_show(_buf[int(_cursor)])
		return
	if _rewinding:
		_resume()
		return
	_acc += delta
	if _acc >= 1.0 / RATE:
		_acc = 0.0
		var surf := car.dominant_surface()
		var bits := 0
		for i in car.wheels.size():
			if car.wheels[i].contact:
				bits |= 1 << i
		_buf.append([car.global_transform, car.linear_velocity, car.angular_velocity, car.gear, car.rpm, car.damage,
			surf.id if surf != null else &"", bits])
		if _buf.size() > int(RATE * SECONDS):
			_buf.pop_front()


## Called whenever the car is placed elsewhere (teleport, respawn, flip, load).
func clear() -> void:
	_buf.clear()
	_acc = 0.0
	if _rewinding:
		_rewinding = false
		_label.visible = false
		car.rewinding = false
	_drop_ghosts()


func is_rewinding() -> bool:
	return _rewinding


func _event_refuses() -> bool:
	var acts: Node = Game.activities
	if acts == null or not acts.has_method(&"rewind_blocked") or not bool(acts.call(&"rewind_blocked")):
		return false
	if not _refused:
		_refused = true
		Game.notify("Rewind", "Rewind is off during races", &"warning")
	return true


func _begin() -> void:
	_rewinding = true
	_cursor = float(_buf.size() - 1)
	car.freeze = true
	car.rewinding = true
	_label.visible = true
	var acts: Node = Game.activities
	if acts != null and acts.has_method(&"on_player_rewind"):
		acts.call(&"on_player_rewind")


## Shows a recorded moment: transform plus the telemetry the HUD and effects read (the controller does not
## run while the body is frozen). Tyres are quiet while scrubbing; the wheels turn backwards.
func _show(st: Array) -> void:
	var xf: Transform3D = st[0]
	_ignore_vehicles_at(xf)
	car.global_transform = xf
	var vel: Vector3 = st[1]
	car.speed_ms = vel.length()
	car.forward_speed = vel.dot(-xf.basis.z)
	car.gear = int(st[3])
	car.rpm = float(st[4])
	car.damage = float(st[5])
	car.throttle_applied = 0.0
	car.engine_load = 0.0
	car.tcs_active = false
	car.abs_active = false
	car.stm_active = false
	car.shifting = false
	var surf: SurfaceData = Surfaces.get_surface(st[6]) if StringName(st[6]) != &"" else null
	for i in car.wheels.size():
		var w := car.wheels[i]
		w.contact = surf != null and (int(st[7]) >> i) & 1 == 1
		if surf != null:
			w.surface = surf
		w.skid = 0.0
		w.slip_long = 0.0
		w.slip_angle = 0.0
		w.omega = -2.0 * car.forward_speed / w.radius


func _resume() -> void:
	_rewinding = false
	_label.visible = false
	var i := _clear_index(int(_cursor))
	var st: Array = _buf[i]
	_buf.resize(i + 1)
	car.rewinding = false
	# Resume in the recorded gear with the wheels and engine at road speed (no idle-rpm gear hunt), and with
	# the damage the car had then.
	car.place_at(st[0], st[1], st[2], int(st[3]))
	car.damage = float(st[5])
	_ghost_t = 0.0


## The recorded moment to resume from: the scrubbed-to one if it is clear of other vehicles, else the nearest
## clear one, preferring later moments (less rewind, usually ahead of a car that was following).
func _clear_index(i0: int) -> int:
	var n := _buf.size()
	var obstacles := _obstacles(_buf[i0][0].origin)
	if obstacles.is_empty() and _overlaps(_buf[i0][0]).is_empty():
		return i0
	for k in range(i0, n, 2):
		if _spot_clear(_buf[k], obstacles):
			return k
	for k in range(i0 - 2, -1, -2):
		if _spot_clear(_buf[k], obstacles):
			return k
	return i0


func _spot_clear(st: Array, obstacles: Array[Dictionary]) -> bool:
	var xf: Transform3D = st[0]
	if not _overlaps(xf).is_empty():
		return false
	var vel: Vector3 = st[1]
	var f := -xf.basis.z
	f.y = 0.0
	f = f.normalized()
	var rt := Vector3(-f.z, 0.0, f.x)
	var bs := car.data.body_size
	for o in obstacles:
		var rel: Vector3 = o["position"] - xf.origin
		var along := rel.dot(f)
		if absf(along) > 120.0 or absf(rel.dot(rt)) > (bs.x + float(o["width"])) * 0.5 + 0.6 or absf(rel.y) > 4.0:
			continue
		var gap := absf(along) - (bs.z + float(o["length"])) * 0.5
		# Closing speed along the lane (> 0: the two are getting closer).
		var closing := (vel - (o["velocity"] as Vector3)).dot(f) * signf(along)
		if gap < 2.0 or (closing > 0.0 and gap < closing * 1.5):
			return false
	return true


## Traffic and rival cars near a point: position, velocity, length, width.
func _obstacles(at: Vector3) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var reach := 500.0
	var t: Node = Game.traffic
	if t != null and t.has_method(&"obstacles_near"):
		for o: Dictionary in t.call(&"obstacles_near", at, reach):
			out.append({"position": o["position"], "velocity": (o["heading"] as Vector3) * float(o["speed"]),
				"length": float(o.get("length", 4.5)), "width": float(o.get("width", 1.9))})
	var acts: Node = Game.activities
	if acts != null and acts.has_method(&"get_ai_cars"):
		for c: CarController in acts.call(&"get_ai_cars"):
			if c != car and is_instance_valid(c) and c.global_position.distance_to(at) < reach:
				out.append({"position": c.global_position, "velocity": c.linear_velocity,
					"length": c.data.body_size.z if c.data else 4.5, "width": c.data.body_size.x if c.data else 1.9})
	return out


## Vehicle bodies inside the car's box (plus a margin) at a transform.
func _overlaps(xf: Transform3D, margin := 0.5) -> Array[PhysicsBody3D]:
	var out: Array[PhysicsBody3D] = []
	var bs := car.data.body_size if car.data else Vector3(1.9, 1.4, 4.5)
	_shape.size = bs + Vector3(margin, 0.0, margin) * 2.0
	_query.transform = xf.translated_local(Vector3(0.0, 0.15 + bs.y * 0.5, 0.0))
	_query.exclude = [car.get_rid()]
	for h: Dictionary in car.get_world_3d().direct_space_state.intersect_shape(_query, 16):
		var b := h.get("collider") as PhysicsBody3D
		if b != null and b != car:
			out.append(b)
	return out


## While scrubbing, the frozen car passes through traffic instead of shoving it aside.
func _ignore_vehicles_at(xf: Transform3D) -> void:
	for b in _overlaps(xf, 3.0):
		if not _ghosts.has(b):
			car.add_collision_exception_with(b)
			_ghosts.append(b)


## After resuming, a vehicle still touching the car stays non-colliding until the two are apart.
func _update_ghosts(delta: float) -> void:
	if _ghosts.is_empty() or _rewinding:
		return
	_ghost_t += delta
	var near: Array[PhysicsBody3D] = []
	if _ghost_t < GHOST_MAX:
		near = _overlaps(car.global_transform, 0.3)
	for i in range(_ghosts.size() - 1, -1, -1):
		var b := _ghosts[i]
		if not is_instance_valid(b):
			_ghosts.remove_at(i)
		elif not near.has(b):
			car.remove_collision_exception_with(b)
			_ghosts.remove_at(i)


func _drop_ghosts() -> void:
	for b in _ghosts:
		if is_instance_valid(b):
			car.remove_collision_exception_with(b)
	_ghosts.clear()
