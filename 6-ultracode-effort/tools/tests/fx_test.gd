extends Node3D
## Vehicle effects test bench (needs a real renderer, not --headless):
##   Godot_console.exe --path <project> --resolution 1600x900 res://tools/tests/fx_test.tscn -- [--only=donut,brake,gravel,wet,backfire,impact,sand,snow,npc] [--out=res://qa_output/fx]
## Flat asphalt / gravel / sand / snow pads, scripted donuts, lock-ups, drifts, rain, backfires and
## wall scrapes; screenshots from a scripted camera are written to --out and debug state is printed.

const EFFECTS_SCRIPT := "res://scripts/vehicle/car_effects.gd"
const DT := 1.0 / 120.0
const PADS := [
	["asphalt", -400.0, 0.0, Color(0.2, 0.205, 0.21)],
	["gravel", 0.0, 200.0, Color(0.5, 0.46, 0.4)],
	["sand", 200.0, 300.0, Color(0.78, 0.68, 0.5)],
	["snow", 300.0, 400.0, Color(0.9, 0.92, 0.95)],
]

var cam: Camera3D
var car: CarController
var fx: Node
var out_dir := "res://qa_output/fx"
var _follow := false
var _follow_world := false
var _follow_offset := Vector3(3.5, 2.0, 7.5)
var _pops := 0
var _impacts := 0
var _sun: DirectionalLight3D
var _env: Environment


func _ready() -> void:
	out_dir = _arg("out", out_dir)
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	_build_scene()
	_run.call_deferred()


func _arg(key: String, default: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--" + key + "="):
			return a.substr(key.length() + 3)
	return default


func _build_scene() -> void:
	_sun = DirectionalLight3D.new()
	_sun.rotation_degrees = Vector3(-38, -35, 0)
	_sun.shadow_enabled = true
	_sun.light_energy = 1.1
	_sun.directional_shadow_max_distance = 150.0
	add_child(_sun)
	var we := WorldEnvironment.new()
	_env = Environment.new()
	_env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	sky.sky_material = ProceduralSkyMaterial.new()
	_env.sky = sky
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	_env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	_env.fog_enabled = true
	_env.fog_density = 0.0008
	we.environment = _env
	add_child(we)
	for pad: Array in PADS:
		var x0: float = pad[1]
		var x1: float = pad[2]
		var body := StaticBody3D.new()
		body.collision_layer = 1
		body.set_meta(&"surface", StringName(pad[0]))
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(x1 - x0, 2.0, 1200.0)
		cs.shape = box
		body.position = Vector3((x0 + x1) * 0.5, -1.0, 0.0)
		body.add_child(cs)
		add_child(body)
		var mi := MeshInstance3D.new()
		var pm := PlaneMesh.new()
		pm.size = Vector2(x1 - x0, 1200.0)
		mi.mesh = pm
		mi.position = Vector3((x0 + x1) * 0.5, 0.0, 0.0)
		var m := StandardMaterial3D.new()
		m.albedo_color = pad[3]
		var nt := NoiseTexture2D.new()
		var fn := FastNoiseLite.new()
		fn.frequency = 0.08
		nt.noise = fn
		nt.seamless = true
		var ramp := Gradient.new()
		ramp.colors = PackedColorArray([Color(0.72, 0.72, 0.72), Color(1, 1, 1)])
		nt.color_ramp = ramp
		m.albedo_texture = nt
		m.uv1_scale = Vector3((x1 - x0) / 6.0, 200.0, 1.0)
		m.roughness = 0.92
		mi.material_override = m
		add_child(mi)
	# Concrete wall for the scrape test.
	var wall := StaticBody3D.new()
	wall.set_meta(&"surface", &"concrete")
	var wcs := CollisionShape3D.new()
	var wbox := BoxShape3D.new()
	wbox.size = Vector3(0.6, 1.1, 300.0)
	wcs.shape = wbox
	wall.add_child(wcs)
	var wmi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = wbox.size
	wmi.mesh = bm
	var wm := StandardMaterial3D.new()
	wm.albedo_color = Color(0.7, 0.7, 0.68)
	wmi.material_override = wm
	wall.add_child(wmi)
	wall.position = Vector3(-250.0, 0.55, -100.0)
	add_child(wall)
	cam = Camera3D.new()
	cam.fov = 60.0
	cam.far = 2000.0
	cam.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(cam)
	cam.make_current()


func _run() -> void:
	var only := _arg("only", "donut,brake,gravel,wet,backfire,impact,sand,snow,npc").split(",")
	for sc in only:
		print("=== fx scenario ", sc)
		await call("_sc_" + sc)
		CarController.wetness = 0.0
		_follow = false
		_follow_world = false
	print("FX_TEST_DONE")
	get_tree().quit(0)


func _process(delta: float) -> void:
	if _follow and car != null and is_instance_valid(car):
		var b := car.global_basis.orthonormalized()
		var flat := Vector3(b.z.x, 0, b.z.z).normalized()
		var right := Vector3(b.x.x, 0, b.x.z).normalized()
		var target := car.global_position + flat * _follow_offset.z + right * _follow_offset.x + Vector3.UP * _follow_offset.y
		if _follow_world:
			target = car.global_position + _follow_offset
		cam.global_position = cam.global_position.lerp(target, clampf(delta * 4.0, 0.0, 1.0))
		cam.look_at(car.global_position + Vector3.UP * 0.7, Vector3.UP)


func _spawn(id: String, pos: Vector3, heading := 0.0, player := true) -> CarController:
	if car != null and is_instance_valid(car):
		car.queue_free()
		await get_tree().physics_frame
	var base: CarData = load("res://data/cars/%s.tres" % id)
	var d: CarData = base.duplicate(true)
	car = CarFactory.build(d, {}, player)
	add_child(car)
	fx = (load(EFFECTS_SCRIPT) as Script).new()
	fx.name = "CarEffects"
	car.add_child(fx)
	fx.connect("backfire", func(_s: float) -> void: _pops += 1)
	car.impact.connect(func(s: float, p: Vector3) -> void:
		_impacts += 1
		print("    impact strength=%.2f at %s" % [s, str(p.snapped(Vector3.ONE * 0.01))]))
	car.place_at(Transform3D(Basis(Vector3.UP, heading), pos))
	Game.apply_assists_to(car)
	for i in 60:
		await get_tree().physics_frame
	return car


func _assists(on: bool) -> void:
	car.assist_tcs = on
	car.assist_stm = on
	car.assist_abs = on


func _hold_heading(target_yaw: float, gain := 1.6) -> void:
	var f := -car.global_transform.basis.z
	var yaw := atan2(-f.x, -f.z)
	car.in_steer = clampf(wrapf(yaw - target_yaw, -PI, PI) * gain, -1.0, 1.0)


func _drive(seconds: float, step: Callable) -> void:
	var t := 0.0
	while t < seconds:
		step.call(t)
		await get_tree().physics_frame
		t += DT


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := out_dir.path_join(name + ".png")
	img.save_png(path)
	var gpu := RenderingServer.viewport_get_measured_render_time_gpu(get_viewport().get_viewport_rid())
	print("  shot ", path.get_file(), "  ", JSON.stringify(fx.call("debug_state")), " fps=", Engine.get_frames_per_second(), " gpu_ms=", snappedf(gpu, 0.01))


func _look(from: Vector3, at: Vector3) -> void:
	cam.global_position = from
	cam.look_at(at, Vector3.UP)


# ------------------------------------------------------------------ scenarios

func _sc_donut() -> void:
	await _spawn("brute_68", Vector3(-60, 0.05, 0), 0.0)
	_assists(false)
	_look(Vector3(-50, 3.5, 9), Vector3(-60, 0.5, -4))
	_follow = true
	_follow_world = true
	_follow_offset = Vector3(9.0, 3.2, 9.0)
	await _drive(1.2, func(_t: float) -> void:
		car.in_throttle = 1.0
		car.in_steer = 0.0)
	await _drive(9.0, func(_t: float) -> void:
		car.in_throttle = 1.0
		car.in_steer = -1.0)
	await _shot("donut_a")
	await _drive(3.0, func(_t: float) -> void:
		car.in_throttle = 1.0
		car.in_steer = -1.0)
	await _shot("donut_b")
	await _drive(2.5, func(_t: float) -> void:
		car.in_throttle = 0.0
		car.in_brake = 0.3
		car.in_steer = 0.0)
	_follow = false
	var cp := car.global_position
	_look(cp + Vector3(7, 6.5, 10), cp + Vector3(-2, 0.0, -6))
	await _drive(0.3, func(_t: float) -> void: pass)
	await _shot("donut_marks")


func _sc_brake() -> void:
	await _spawn("kestrel_r4", Vector3(-150, 0.05, 250), 0.0)
	_assists(false)
	await _drive(9.0, func(_t: float) -> void:
		car.in_throttle = 1.0 if car.get_speed_kmh() < 115.0 else 0.0
		_hold_heading(0.0))
	_follow = true
	_follow_offset = Vector3(4.5, 1.6, -9.0)
	var t := 0.0
	var shot := false
	while car.get_speed_kmh() > 3.0 and t < 8.0:
		car.in_throttle = 0.0
		car.in_brake = 1.0
		_hold_heading(0.0)
		await get_tree().physics_frame
		t += DT
		if not shot and t > 0.9:
			shot = true
			await _shot("brake_lockup")
	car.in_brake = 0.0
	_follow = false
	var p := car.global_position
	_look(p + Vector3(7.0, 4.5, -3.0), p + Vector3(0, 0, 16.0))
	await _drive(3.5, func(_t: float) -> void: pass)
	await _shot("brake_marks")


func _sc_gravel() -> void:
	await _spawn("granite_rally", Vector3(100, 0.05, 300), 0.0)
	_follow = true
	_follow_offset = Vector3(2.5, 2.2, 8.0)
	await _drive(7.0, func(_t: float) -> void:
		car.in_throttle = 1.0 if car.get_speed_kmh() < 95.0 else 0.4
		_hold_heading(0.0))
	await _shot("gravel_trail")
	_assists(false)
	await _drive(2.2, func(t: float) -> void:
		car.in_throttle = 1.0
		car.in_handbrake = 1.0 if t < 0.35 else 0.0
		car.in_steer = -1.0 if t < 0.6 else clampf((car.body_slip_deg - 25.0) * 0.04, -1.0, 1.0))
	await _shot("gravel_drift")
	_follow = false
	await _drive(1.0, func(_t: float) -> void:
		car.in_throttle = 0.6
		car.in_steer = clampf(car.body_slip_deg * 0.05, -1.0, 1.0))
	await _shot("gravel_drift_after")


func _sc_wet() -> void:
	CarController.wetness = 0.85
	await _spawn("kestrel_r4", Vector3(-100, 0.05, 300), 0.0)
	_follow = true
	_follow_offset = Vector3(1.8, 1.6, 7.0)
	await _drive(8.0, func(_t: float) -> void:
		car.in_throttle = 1.0 if car.get_speed_kmh() < 120.0 else 0.5
		_hold_heading(0.0))
	await _shot("wet_spray")
	CarController.wetness = 0.0


func _sc_backfire() -> void:
	await _spawn("kestrel_r4", Vector3(-200, 0.05, 300), 0.0)
	_env.background_energy_multiplier = 0.25
	_sun.light_energy = 0.15
	_follow = true
	_follow_offset = Vector3(2.2, 0.9, 3.4)
	_pops = 0
	var lifted := false
	var t := 0.0
	var shots := 0
	while t < 10.0 and shots < 2:
		var rf := car.rpm / car.data.redline_rpm
		if not lifted and rf > 0.9 and car.gear >= 2:
			lifted = true
		car.in_throttle = 0.0 if lifted else 1.0
		_hold_heading(0.0)
		var before := _pops
		await get_tree().physics_frame
		t += DT
		if _pops > before:
			await _shot("backfire_%d" % shots)
			shots += 1
		if lifted and car.rpm / car.data.redline_rpm < 0.6:
			lifted = false
	print("  pops=", _pops)
	_env.background_energy_multiplier = 1.0
	_sun.light_energy = 1.1


func _sc_impact() -> void:
	await _spawn("kestrel_r4", Vector3(-262.0, 0.05, 40), deg_to_rad(-10.0))
	_follow = true
	_follow_offset = Vector3(-3.5, 1.6, 5.5)
	_impacts = 0
	var t := 0.0
	var scrape_shot := false
	while t < 7.0:
		var v := car.get_speed_kmh()
		car.in_throttle = 1.0 if v < 75.0 else 0.3
		_hold_heading(deg_to_rad(-10.0))
		await get_tree().physics_frame
		t += DT
		if not scrape_shot and float(fx.call("debug_state")["scrape"]) > 0.5:
			scrape_shot = true
			await _drive(0.35, func(_t: float) -> void:
				car.in_throttle = 1.0
				_hold_heading(deg_to_rad(-10.0)))
			await _shot("scrape")
			_follow_offset = Vector3(-2.0, 1.2, -6.0)
			await _drive(0.6, func(_t: float) -> void:
				car.in_throttle = 1.0
				_hold_heading(deg_to_rad(-10.0)))
			await _shot("scrape_front")
	# Head-on hit into the wall end for the impact burst + debris.
	await _spawn("kestrel_r4", Vector3(-250.0, 0.05, 110), 0.0)
	_follow = false
	_look(Vector3(-243.0, 2.0, 55.0), Vector3(-250.0, 0.6, 48.0))
	_impacts = 0
	t = 0.0
	while t < 6.0 and _impacts == 0:
		car.in_throttle = 1.0
		_hold_heading(0.0)
		await get_tree().physics_frame
		t += DT
	await _drive(0.08, func(_t: float) -> void: pass)
	await _shot("impact_hit")
	print("  impacts=", _impacts)


func _sc_sand() -> void:
	await _spawn("ridgeback_sx", Vector3(250, 0.05, 300), 0.0)
	_follow = true
	_follow_offset = Vector3(3.0, 2.2, 8.0)
	await _drive(6.0, func(_t: float) -> void:
		car.in_throttle = 1.0 if car.get_speed_kmh() < 80.0 else 0.4
		_hold_heading(0.0))
	await _shot("sand_trail")


func _sc_snow() -> void:
	await _spawn("granite_rally", Vector3(350, 0.05, 300), 0.0)
	_follow = true
	_follow_offset = Vector3(-3.0, 2.0, 8.0)
	await _drive(5.0, func(_t: float) -> void:
		car.in_throttle = 1.0 if car.get_speed_kmh() < 75.0 else 0.4
		_hold_heading(0.0))
	_assists(false)
	await _drive(1.6, func(t: float) -> void:
		car.in_throttle = 1.0
		car.in_handbrake = 1.0 if t < 0.3 else 0.0
		car.in_steer = 1.0 if t < 0.5 else clampf((car.body_slip_deg + 25.0) * 0.04, -1.0, 1.0))
	await _shot("snow_drift")


func _sc_npc() -> void:
	await _spawn("brute_68", Vector3(-120, 0.05, -100), 0.0, false)
	_assists(false)
	_look(Vector3(-106, 4.0, -86), Vector3(-120, 0.5, -104))
	await _drive(1.0, func(_t: float) -> void:
		car.in_throttle = 1.0)
	await _drive(5.0, func(_t: float) -> void:
		car.in_throttle = 1.0
		car.in_steer = 1.0)
	await _shot("npc_donut")


## GPU cost of the particle draw: alternate hiding / showing the car's effects in the same heavy
## donut-smoke shot and compare the measured GPU frame time (robust against other GPU load).
func _sc_bench() -> void:
	await _spawn("brute_68", Vector3(-60, 0.05, 0), 0.0)
	_assists(false)
	_follow = true
	_follow_world = true
	_follow_offset = Vector3(5.0, 2.2, 5.0)
	await _drive(1.0, func(_t: float) -> void:
		car.in_throttle = 1.0)
	await _drive(6.0, func(_t: float) -> void:
		car.in_throttle = 1.0
		car.in_steer = -1.0)
	var rid := get_viewport().get_viewport_rid()
	var on_sum := 0.0
	var off_sum := 0.0
	for rep in 4:
		for vis: bool in [false, true]:
			(fx as Node3D).visible = vis
			var acc := 0.0
			for f in 50:
				car.in_throttle = 1.0
				car.in_steer = -1.0
				await get_tree().process_frame
				if f >= 10:
					acc += RenderingServer.viewport_get_measured_render_time_gpu(rid)
			if vis:
				on_sum += acc / 40.0
			else:
				off_sum += acc / 40.0
	print("  bench gpu_ms fx_on=%.2f fx_off=%.2f particles_cost=%.2f" % [on_sum / 4.0, off_sum / 4.0, (on_sum - off_sum) / 4.0])
	await _shot("bench_view")


## Brake-disc glow after repeated hard ABS stops, then idle exhaust + caked dirt close-ups (dusk).
func _sc_glow() -> void:
	await _spawn("kestrel_r4", Vector3(-330, 0.05, 500), 0.0)
	car.assist_abs = true
	for stop in 3:
		if car.global_position.z < 100.0:
			car.place_at(Transform3D(Basis.IDENTITY, Vector3(car.global_position.x, 0.05, 500)))
			car.assist_abs = true
		await _drive(12.0, func(_t: float) -> void:
			car.in_brake = 0.0
			car.in_throttle = 1.0 if car.get_speed_kmh() < 175.0 else 0.0
			_hold_heading(0.0))
		var t := 0.0
		print("  stop %d from %.0f km/h z=%.0f" % [stop, car.get_speed_kmh(), car.global_position.z])
		while car.get_speed_kmh() > 2.0 and t < 10.0:
			car.in_throttle = 0.0
			car.in_brake = 1.0
			_hold_heading(0.0)
			await get_tree().physics_frame
			t += DT
		print("  stop %d heat=%s t=%.1f" % [stop, str(fx.call("debug_state")["brake_heat"]), t])
	car.in_brake = 0.3
	_env.background_energy_multiplier = 0.2
	_sun.light_energy = 0.08
	var p := car.global_position
	var b := car.global_basis.orthonormalized()
	_look(p + b.x * -2.6 + b.z * -1.6 + Vector3.UP * 0.6, p + b.z * -1.2 + b.x * -0.7 + Vector3.UP * 0.3)
	await _drive(0.3, func(_t: float) -> void: pass)
	await _shot("brake_glow")
	_env.background_energy_multiplier = 1.0
	_sun.light_energy = 1.1
	fx.call("set_dirt_level", 0.85)
	_look(p + b.x * 2.2 + b.z * 4.2 + Vector3.UP * 0.9, p + b.z * 1.6 + Vector3.UP * 0.35)
	await _drive(1.2, func(_t: float) -> void:
		car.in_brake = 0.0
		car.in_throttle = 0.25)
	await _shot("exhaust_dirt")
