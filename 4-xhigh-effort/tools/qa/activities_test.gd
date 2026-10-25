extends Node
## Automated activity check: autopilot through a speed trap, a speed zone and a drift zone, a
## straight run at a jump ramp, and a full checkpoint race (Enter-start with countdown).
##   godot --headless --fixed-fps 120 --path . -- --qa=activities_test --fresh [--only=trap,zone,drift,jump,race]

var mode := ""
var cap := 110.0
var ramp: Dictionary = {}
var log_lines: Array = []


func _ready() -> void:
	Game.traffic.set_process(false)
	Game.traffic.set_physics_process(false)
	Game.main.driver.car = null
	_run()


func _act(type: String, prefer := "") -> Dictionary:
	for a: Dictionary in Game.activities.acts:
		if String(a.type) == type and (prefer == "" or String(a.id).contains(prefer) or String(a.name).contains(prefer)):
			return a
	return {}


func _wait_result(n_before: int, timeout: float) -> Dictionary:
	var t := 0.0
	var next_log := 5.0
	while t < timeout:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		if Game.activities.results.size() > n_before:
			return Game.activities.results[-1]
		if t > next_log and Game.main.arg("verbose") != "":
			next_log += 5.0
			var am: Node = Game.activities
			var pc := Game.player
			print("  t=%.0f pos=%s v=%.0f cd=%.1f active=%s cp=%s gr=%d gear=%d rpm=%.0f thr=%.2f/%.2f brk=%.2f hb=%s sleep=%s freeze=%s up=%.2f blocked=%s" % [t, pc.global_position.snapped(Vector3.ONE), pc.speed_abs * 3.6,
				am._countdown, not am.active.is_empty(), am.active.get("cp", -1), pc.grounded, pc.gear, pc.rpm, pc.in_throttle, pc.throttle_out,
				pc.in_brake, pc.in_handbrake, pc.sleeping, pc.freeze, pc.global_transform.basis.y.y, Game.input_blocked()])
	return {}


func _run() -> void:
	var only := String(Game.main.arg("only", "trap,zone,drift,jump,race")).split(",")
	await get_tree().create_timer(1.0).timeout
	if "trap" in only:
		await _drive_through(_act("speed_trap", "highway"), 160.0, 40.0, "speed_trap")
	if "zone" in only:
		await _drive_through(_act("speed_zone", "Expressway"), 170.0, 80.0, "speed_zone")
	if "drift" in only:
		await _drive_through(_act("drift_zone"), 90.0, 90.0, "drift_zone")
	if "jump" in only:
		await _jump(_act("jump"))
	if "race" in only:
		await _race(_act("race", String(Game.main.arg("race", "Expressway"))))
	print("ACTIVITIES_TEST ", JSON.stringify(log_lines))
	get_tree().quit(0)


func _drive_through(a: Dictionary, kmh: float, timeout: float, label: String) -> void:
	if a.is_empty():
		log_lines.append({"test": label, "ok": false, "why": "missing"})
		return
	Game.activities.teleport_to(a)
	cap = kmh
	mode = "auto"
	var n: int = Game.activities.results.size()
	var r := await _wait_result(n, timeout)
	mode = ""
	log_lines.append({"test": label, "name": a.name, "ok": not r.is_empty(), "value": r.get("value", null)})


func _jump(a: Dictionary) -> void:
	if a.is_empty() or not a.has("ramp_xf"):
		log_lines.append({"test": "jump", "ok": false, "why": "missing"})
		return
	ramp = a
	var xf: Transform3D = a.ramp_xf
	var fwd := -xf.basis.z
	var p := xf.origin - fwd * 45.0
	p.y = Game.world.height_at(p.x, p.z) + 1.0
	var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 30.0, p + Vector3.DOWN * 60.0, 1)
	var hit := get_viewport().get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		p.y = float(hit.position.y) + 0.6
	Game.player.teleport(p, Vector3(fwd.x, 0, fwd.z).normalized(), 27.0)
	mode = "jump"
	var n: int = Game.activities.results.size()
	var r := await _wait_result(n, 25.0)
	mode = ""
	log_lines.append({"test": "jump", "name": a.name, "ok": not r.is_empty(), "value": r.get("value", null),
		"upright": Game.player.global_transform.basis.y.y > 0.5})


func _race(a: Dictionary) -> void:
	if a.is_empty():
		log_lines.append({"test": "race", "ok": false, "why": "missing"})
		return
	Game.activities.teleport_to(a)
	await get_tree().create_timer(0.5).timeout
	Game.player.global_position += (a.dir as Vector3) * 12.0
	await get_tree().physics_frame
	Game.activities._check_starts(Game.player, Game.player.global_position)
	var prompt_ok: bool = not Game.activities._prompt_act.is_empty()
	Game.activities.start_event(a)
	cap = 150.0
	mode = "auto"
	if DisplayServer.get_name() != "headless":
		await get_tree().create_timer(7.0).timeout
		Game.camera.mode = CarCamera.Mode.CHASE_FAR
		await get_tree().create_timer(1.0).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://qa/tmp/race_start.png")
		print("SHOT race_start")
	var n: int = Game.activities.results.size()
	var r := await _wait_result(n, 260.0)
	mode = ""
	log_lines.append({"test": "race", "name": a.name, "prompt": prompt_ok, "ok": not r.is_empty(), "time": r.get("value", null),
		"cps": (a.checkpoints as Array).size() + 1})


func _physics_process(_delta: float) -> void:
	var car := Game.player
	if car == null:
		return
	match mode:
		"auto":
			car.in_steer = Game.world.autopilot_steer(car)
			var ped: Vector2 = Game.world.autopilot_pedals(car, cap)
			car.in_throttle = ped.x
			car.in_brake = ped.y
			car.in_handbrake = false
		"jump":
			var xf: Transform3D = ramp.ramp_xf
			var lp := xf.affine_inverse() * car.global_position
			var fwd := -xf.basis.z
			var head := (-car.global_transform.basis.z).slide(Vector3.UP).normalized()
			var err := head.signed_angle_to(Vector3(fwd.x, 0, fwd.z).normalized(), Vector3.UP)
			car.in_steer = clampf(-err * 2.5 + lp.x * 0.08, -1.0, 1.0) if car.grounded > 0 else 0.0
			car.in_throttle = 1.0 if car.speed_abs * 3.6 < 105.0 else 0.0
			car.in_brake = 0.0
		_:
			car.in_throttle = 0.0
			car.in_brake = 0.3
			car.in_steer = 0.0
