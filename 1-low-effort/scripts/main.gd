extends Node3D
## Entry point: builds the world, spawns the player car on the Grand Valley Loop and
## owns the console command set.

var world: WorldGen
var roads: RoadBuilder
var terrain: TerrainStreamer
var sky: SkyWeather
var props: Props
var traffic: TrafficManager
var events: EventManager
var player: Car
var cam: ChaseCam
var audio: CarAudio
var hud: Hud
var menus: Menus
var fx: Node3D
var car_index := 0
var photo_mode := false
var _save_timer := 0.0
var _water: MeshInstance3D
var _smoke: GPUParticles3D
var _dust: GPUParticles3D
var _skids: SkidMarks
var _headlight_auto := true
var _ready_done := false
var _horn_held := false
var _water_t := 0.0

func _ready() -> void:
	Game.main = self
	var t0 := Time.get_ticks_msec()
	world = WorldGen.new()
	world.build()
	print("[main] world built in %d ms, %.1f km of road" % [Time.get_ticks_msec() - t0, world.total_road_km()])
	sky = SkyWeather.new(); add_child(sky)
	roads = RoadBuilder.new(); roads.name = "Roads"; add_child(roads); roads.build(world)
	print("[main] roads built at %d ms" % (Time.get_ticks_msec() - t0))
	terrain = TerrainStreamer.new(); terrain.name = "Terrain"; add_child(terrain); terrain.setup(world)
	_make_water()
	props = Props.new(); props.name = "Props"; add_child(props); props.build(world)
	var state := Game.load_game()
	car_index = clampi(int(state.get("car", 0)), 0, Game.cars.size() - 1)
	cam = ChaseCam.new(); add_child(cam); cam.current = true
	audio = CarAudio.new(); add_child(audio)
	var spawn := spawn_transform(0, 30)
	if state.has("pos"):
		var pa: Array = state.pos
		var dir_a: Array = state.get("dir", [0, 0, -1])
		var pos := Vector3(pa[0], pa[1], pa[2])
		var dir := Vector3(dir_a[0], dir_a[1], dir_a[2])
		spawn = Transform3D(Basis.looking_at(dir, Vector3.UP), pos + Vector3.UP * 1.0)
	terrain.focus = spawn.origin
	terrain.update_stream(true)
	_spawn_car(car_index, spawn)
	sky.follow = player
	if state.has("hour"): sky.set_hour(float(state.hour))
	if state.has("weather"): sky.set_weather(String(state.weather), true)
	_make_fx()
	traffic = TrafficManager.new(); traffic.name = "Traffic"; add_child(traffic); traffic.setup(world, player, cam)
	traffic.density = Game.settings.traffic_density
	events = EventManager.new(); events.name = "Events"; add_child(events); events.setup(world, player)
	hud = Hud.new(); hud.main = self; add_child(hud); hud.car = player
	hud.minimap.world = world; hud.minimap.player = player; hud.minimap.events = events
	hud.minimap.build_region_texture()
	menus = Menus.new(); menus.main = self; add_child(menus)
	print("[main] ready in %d ms" % (Time.get_ticks_msec() - t0))
	Game.toast("Welcome to %s — press F1 for the garage, ` for the console" % Game.TITLE, "event")
	_ready_done = true
	add_child(AutoTest.new())

func _make_water() -> void:
	_water = MeshInstance3D.new()
	var pm := PlaneMesh.new(); pm.size = Vector2(9000, 9000); pm.subdivide_width = 1; pm.subdivide_depth = 1
	_water.mesh = pm
	var m := ShaderMaterial.new(); m.shader = preload("res://shaders/water.gdshader")
	_water.material_override = m
	_water.position = Vector3(0, WorldGen.SEA_LEVEL, 0)
	_water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_water)

func _make_fx() -> void:
	_smoke = _particles(Color(0.85, 0.85, 0.85, 0.5), 160, 2.2, 1.5)
	_dust = _particles(Color(0.65, 0.52, 0.36, 0.5), 200, 2.6, 2.2)
	_skids = SkidMarks.new(); add_child(_skids)

func _particles(c: Color, amount: int, life: float, size: float) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = amount; p.lifetime = life; p.local_coords = false
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0); pm.spread = 50.0
	pm.initial_velocity_min = 0.5; pm.initial_velocity_max = 2.0
	pm.gravity = Vector3(0, 0.6, 0)
	pm.damping_min = 1.0; pm.damping_max = 2.0
	pm.scale_min = size * 0.6; pm.scale_max = size * 1.4
	var curve := CurveTexture.new(); var cv := Curve.new(); cv.add_point(Vector2(0, 0.3)); cv.add_point(Vector2(1, 1)); curve.curve = cv
	pm.scale_curve = curve
	var grad := GradientTexture1D.new(); var g := Gradient.new()
	g.set_color(0, c); g.set_color(1, Color(c.r, c.g, c.b, 0.0)); grad.gradient = g
	pm.color_ramp = grad
	p.process_material = pm
	var q := QuadMesh.new(); q.size = Vector2(1, 1)
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = _soft_tex()
	q.material = m
	p.draw_pass_1 = q
	p.emitting = false
	add_child(p)
	return p

func _soft_tex() -> Texture2D:
	var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	for y in 32:
		for x in 32:
			var d := Vector2(x - 15.5, y - 15.5).length() / 16.0
			img.set_pixel(x, y, Color(1, 1, 1, clampf(1.0 - d, 0, 1) ** 2))
	return ImageTexture.create_from_image(img)

func spawn_transform(ri: int, idx: int, lane: float = 0.5) -> Transform3D:
	var p := world.road_point(ri, idx)
	var d := world.road_dir(ri, idx)
	var f := Vector3(d.x, 0, d.z).normalized()
	var r := f.cross(Vector3.UP)
	var off: float = world.roads[ri].width * 0.25 * lane * 2.0
	return Transform3D(Basis.looking_at(f, Vector3.UP), p + r * off + Vector3.UP * 0.9)

func _spawn_car(i: int, xf: Transform3D) -> void:
	var old_vel := Vector3.ZERO
	if player:
		old_vel = player.linear_velocity
		player.queue_free()
	car_index = i
	var spec := Game.cars[i]
	var c := Car.new()
	c.name = "Player"
	add_child(c)
	c.setup(spec, world)
	if Game.upgrade_state.has(spec.id):
		var u: Dictionary = Game.upgrade_state[spec.id]
		for k in u.keys(): if c.upgrades.has(k): c.upgrades[k] = int(u[k])
		c.apply_tuning()
	if Game.paint_state.has(spec.id):
		c.set_paint(Game.paint_state[spec.id].color, Game.paint_state[spec.id].finish)
	c.reset_to(xf)
	c.linear_velocity = old_vel
	c.gear_changed.connect(func(_g: int) -> void: audio.on_shift())
	c.impact_cb = _on_impact
	player = c
	cam.target = c
	cam.snap()
	audio.car = c
	if hud: hud.car = c; hud.minimap.player = c
	if traffic: traffic.player = c
	if events: events.player = c
	if sky: sky.follow = c
	Game.car_changed.emit(c)

func _on_impact(strength: float, body: Node) -> void:
	cam.add_shake(clampf(strength / 30.0, 0.0, 0.8))
	audio.on_impact(strength)
	if body and body.has_meta("traffic"):
		traffic.on_player_hit(body, player.linear_velocity)

func _physics_process(_dt: float) -> void:
	if player == null: return
	var blocked: bool = menus != null and menus.any_open() or photo_mode
	if blocked:
		player.in_throttle = 0.0; player.in_brake = 0.0 if not photo_mode else 1.0; player.in_steer = 0.0
		return
	player.in_throttle = Input.get_action_strength("throttle")
	player.in_brake = Input.get_action_strength("brake")
	var st := Input.get_action_strength("steer_right") - Input.get_action_strength("steer_left")
	player.in_steer = st
	player.in_handbrake = Input.is_action_pressed("handbrake")
	player.weather_grip = sky.grip_factor * (0.92 if world.region_at(player.global_position.x, player.global_position.z) == 1 and player.global_position.y > 230.0 else 1.0)

func _process(dt: float) -> void:
	if not _ready_done: return
	terrain.focus = player.global_position + player.linear_velocity * 1.5
	_update_fx()
	audio.horn = Input.is_action_pressed("horn") and not menus.any_open()
	if _headlight_auto: player.set_lights(sky.is_night() or sky.state in ["fog", "storm"])
	_water.position.x = snappedf(player.global_position.x, 50.0)
	_water.position.z = snappedf(player.global_position.z, 50.0)
	# fell through or out of the world
	_water_t = _water_t + dt if player.global_position.y < WorldGen.SEA_LEVEL - 0.3 else 0.0
	if _water_t > 1.5:
		_water_t = 0.0
		Game.toast("Splash! Back to the road", "warn")
		exec("respawn")
	if player.global_position.y < -30.0 or absf(player.global_position.x) > 2100.0 or absf(player.global_position.z) > 2100.0:
		exec("respawn")
	_save_timer += dt
	if _save_timer > 20.0:
		_save_timer = 0.0; save_state()

func _update_fx() -> void:
	var slip := player.max_slip
	var on_road := player.surface <= 1
	var kmh := absf(player.speed) * 3.6
	var rear: Dictionary = player.wheels[2]
	var pos := player.global_position - player.global_basis.z * (rear.rest_pos as Vector3).z * -1.0
	pos = player.to_global(Vector3(0, 0.2, (rear.rest_pos as Vector3).z + 0.3))
	_smoke.global_position = pos
	_dust.global_position = pos
	_smoke.emitting = on_road and slip > 0.25 and kmh > 15.0
	_dust.emitting = (not on_road and kmh > 20.0) or (not on_road and slip > 0.2)
	_dust.amount_ratio = clampf(kmh / 120.0 + slip, 0.2, 1.0)
	_skids.update_car(player, on_road and slip > 0.3)

func _unhandled_input(e: InputEvent) -> void:
	if menus.any_open(): return
	if e.is_action_pressed("camera"): cam.cycle()
	elif e.is_action_pressed("reset_car"): exec("reset")
	elif e.is_action_pressed("shift_up"): player.shift(1)
	elif e.is_action_pressed("shift_down"): player.shift(-1)
	elif e.is_action_pressed("lights"):
		_headlight_auto = false; player.set_lights(not player.lights_on)
	elif e.is_action_pressed("photo_mode"): exec("photo")
	elif e.is_action_pressed("screenshot"): exec("screenshot")
	elif e.is_action_pressed("map"):
		hud.minimap.full = not hud.minimap.full
		if hud.minimap.full:
			Hud._at(hud.minimap, Control.PRESET_FULL_RECT, Vector2(80, 60), Vector2(-160, -120))
			hud.minimap.offset_right = -80; hud.minimap.offset_bottom = -60
			hud.minimap.mouse_filter = Control.MOUSE_FILTER_STOP
		else:
			Hud._at(hud.minimap, Control.PRESET_BOTTOM_LEFT, Vector2(28, -290), Vector2(260, 260))
			hud.minimap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	elif photo_mode and e is InputEventMouseButton and (e as InputEventMouseButton).pressed:
		var mb := e as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP: cam.fov = clampf(cam.fov - 2.0, 15.0, 100.0)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN: cam.fov = clampf(cam.fov + 2.0, 15.0, 100.0)

func save_state() -> void:
	var p := player.global_position
	var f := -player.global_basis.z
	Game.paint_state[player.spec.id] = {"color": player.paint_mat.albedo_color, "finish": int(player.paint_mat.get_meta("finish", 0))}
	Game.upgrade_state[player.spec.id] = player.upgrades.duplicate()
	Game.settings.traffic_density = traffic.density
	Game.save_game({"car": car_index, "pos": [p.x, p.y, p.z], "dir": [f.x, 0.0, f.z], "hour": sky.hour, "weather": sky.state})

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and _ready_done:
		save_state()

# ------------------------------------------------------------------ console commands
func _tp_target(name: String) -> Variant:
	var regions := {"vale": [0, 0.04], "farmland": [0, 0.04], "highpine": [0, 0.33], "mountains": [0, 0.33], "mesa": [0, 0.55], "desert": [0, 0.55],
		"coast": [0, 0.83], "loop": [0, 0.0], "highway": [1, 0.02], "meridian": [2, 0.02], "switchbacks": [10, 0.02], "pinecut": [4, 0.02],
		"mesatrail": [5, 0.02], "dunes": [6, 0.02], "canyon": [7, 0.02], "clifftop": [8, 0.02], "quarry": [11, 0.05], "backroad": [12, 0.05], "orchard": [3, 0.05]}
	if regions.has(name):
		var r: Array = regions[name]
		var ri: int = r[0]
		return [ri, int(world.roads[ri].pts.size() * float(r[1])) + 2]
	if props.pois.has(name):
		var poi: Dictionary = props.pois[name]
		return [poi.road, poi.idx]
	return null

func exec(line: String) -> String:
	var a := line.strip_edges().split(" ", false)
	if a.is_empty(): return ""
	var cmd := a[0].to_lower()
	var arg := a[1] if a.size() > 1 else ""
	match cmd:
		"help":
			return "cars | car <n|name> | respawn | reset | flip | repair | tp <place> | places | time <h> | timescale <x> | weather <clear|cloudy|rain|fog|storm>\ntraffic <0..1> | speed | fps | telemetry | units | hud | assist <tcs|abs|stm|steer|auto> on|off|toggle | assists on|off\npaint <colour|#hex> | finish <gloss|matte|metallic> | upgrade <part> <0-3> | tune <param> <value> | camera | photo | screenshot | save | load | bench | events | quit"
		"cars":
			var s := ""
			for i in Game.cars.size():
				var c := Game.cars[i]
				s += "%2d. %-22s %-16s %-4s %s\n" % [i + 1, c.display_name, c.category, ["FWD", "RWD", "AWD"][c.drivetrain], c.class_rating()]
			return s
		"car":
			var i := Game.find_car(arg)
			if i < 0: return "unknown car '%s' (try 'cars')" % arg
			var xf := player.global_transform
			xf.origin += Vector3.UP * 0.6
			xf.basis = Basis.looking_at(Vector3(-xf.basis.z.x, 0, -xf.basis.z.z).normalized(), Vector3.UP)
			_spawn_car(i, xf)
			return "spawned " + Game.cars[i].display_name
		"respawn", "reset":
			var p := player.global_position
			var rs := world.raster_sample(p.x, p.z)
			var ri := int(rs.z) if rs.z >= 0 else 0
			var idx := int(rs.w) if rs.z >= 0 else 30
			if rs.x > 300.0: ri = 0; idx = 30
			var xf := spawn_transform(ri, idx)
			# keep heading roughly as driven
			if (-player.global_basis.z).dot(-xf.basis.z) < 0.0:
				xf.basis = xf.basis.rotated(Vector3.UP, PI)
				xf.origin = spawn_transform(ri, idx, -0.5).origin
			player.reset_to(xf)
			cam.snap()
			return "respawned on %s" % world.roads[ri].name
		"flip":
			var xf := player.global_transform
			var f := Vector3(-xf.basis.z.x, 0, -xf.basis.z.z).normalized()
			player.reset_to(Transform3D(Basis.looking_at(f, Vector3.UP), xf.origin + Vector3.UP * 1.5))
			return "flipped"
		"repair":
			player.damage = 0.0
			return "repaired"
		"tp":
			var t: Variant = _tp_target(arg.to_lower())
			if t == null: return "unknown place. " + exec("places")
			var ta: Array = t
			terrain.focus = world.road_point(ta[0], ta[1])
			terrain.update_stream(true)
			player.reset_to(spawn_transform(ta[0], ta[1]))
			cam.snap()
			traffic.clear_all()
			return "teleported to %s (%s)" % [arg, world.roads[ta[0]].name]
		"places":
			return "places: vale highpine mesa coast loop highway meridian switchbacks pinecut mesatrail dunes canyon clifftop quarry backroad orchard " + " ".join(props.pois.keys())
		"time":
			if not arg.is_valid_float(): return "usage: time <hour>"
			sky.set_hour(arg.to_float())
			return "time set to %.1f" % sky.hour
		"timescale":
			sky.time_scale = arg.to_float() / 60.0
			sky.freeze_time = arg.to_float() == 0.0
			return "time scale %s game-min/sec" % arg
		"weather":
			return ("weather: " + arg) if sky.set_weather(arg.to_lower()) else "states: " + ", ".join(SkyWeather.STATES)
		"traffic":
			traffic.density = clampf(arg.to_float(), 0.0, 1.0)
			if traffic.density == 0.0: traffic.clear_all()
			return "traffic density %.2f" % traffic.density
		"speed", "units":
			Game.settings.units_kmh = not Game.settings.units_kmh
			return "units: " + ("km/h" if Game.settings.units_kmh else "mph")
		"fps":
			Game.settings.show_fps = not Game.settings.show_fps
			return "fps display " + str(Game.settings.show_fps)
		"telemetry":
			hud.show_telemetry = not hud.show_telemetry
			return "telemetry " + str(hud.show_telemetry)
		"hud":
			hud.visible = not hud.visible
			return "hud " + str(hud.visible)
		"assist":
			if not player.assists.has(arg): return "assists: tcs abs stm steer auto"
			var mode := a[2] if a.size() > 2 else "toggle"
			player.assists[arg] = (mode == "on") if mode != "toggle" else not player.assists[arg]
			if arg == "auto" and player.gear == 0: player.gear = 1
			return "%s %s" % [arg, "ON" if player.assists[arg] else "OFF"]
		"assists":
			for k in ["tcs", "abs", "stm", "steer"]: player.assists[k] = arg != "off"
			return "assists " + arg
		"paint":
			var named := {"red": Color(0.85, 0.08, 0.06), "blue": Color(0.1, 0.3, 0.85), "green": Color(0.2, 0.7, 0.2), "yellow": Color(0.95, 0.85, 0.1), "orange": Color(1, 0.5, 0.05),
				"white": Color(0.95, 0.95, 0.95), "black": Color(0.04, 0.04, 0.05), "silver": Color(0.6, 0.6, 0.62), "purple": Color(0.5, 0.15, 0.7), "pink": Color(1, 0.4, 0.6), "teal": Color(0.1, 0.6, 0.6)}
			var c: Color
			if named.has(arg.to_lower()): c = named[arg.to_lower()]
			elif Color.html_is_valid(arg): c = Color.html(arg)
			else: return "colours: " + ", ".join(named.keys()) + " or #rrggbb"
			player.set_paint(c, int(player.paint_mat.get_meta("finish", 0)))
			Game.paint_state[player.spec.id] = {"color": c, "finish": int(player.paint_mat.get_meta("finish", 0))}
			return "paint " + arg
		"finish":
			var fi := ["gloss", "matte", "metallic"].find(arg.to_lower())
			if fi < 0: return "finish gloss|matte|metallic"
			player.set_paint(player.paint_mat.albedo_color, fi)
			Game.paint_state[player.spec.id] = {"color": player.paint_mat.albedo_color, "finish": fi}
			return "finish " + arg
		"upgrade":
			if not player.upgrades.has(arg): return "parts: " + ", ".join(player.upgrades.keys())
			player.upgrades[arg] = clampi((a[2] if a.size() > 2 else "1").to_int(), 0, 3)
			player.apply_tuning()
			Game.upgrade_state[player.spec.id] = player.upgrades.duplicate()
			return "%s stage %d → class %s" % [arg, player.upgrades[arg], player.spec.class_rating()]
		"tune":
			if not player.tuning.has(arg) or a.size() < 3: return "tune params: " + ", ".join(player.tuning.keys())
			player.tuning[arg] = a[2].to_float()
			player.apply_tuning()
			return "%s = %.2f" % [arg, player.tuning[arg]]
		"camera":
			cam.cycle(); return "camera " + ChaseCam.MODES[cam.mode]
		"photo":
			photo_mode = not photo_mode
			hud.visible = not photo_mode
			if photo_mode:
				cam.enter_photo()
				sky.freeze_time = true
				var attr := CameraAttributesPractical.new()
				attr.dof_blur_far_enabled = true; attr.dof_blur_far_distance = 40.0; attr.dof_blur_amount = 0.08
				cam.attributes = attr
				return "PHOTO MODE: WASD/QE move, RMB look, wheel FOV, F12 shot, P exit"
			cam.photo = false; cam.attributes = null; sky.freeze_time = false
			return "photo mode off"
		"screenshot":
			var dir := "user://screenshots"
			DirAccess.make_dir_recursive_absolute(dir)
			var path := "%s/shot_%d.png" % [dir, Time.get_unix_time_from_system()]
			get_viewport().get_texture().get_image().save_png(path)
			Game.toast("Saved " + ProjectSettings.globalize_path(path))
			return "saved " + ProjectSettings.globalize_path(path)
		"save":
			save_state(); return "saved to " + ProjectSettings.globalize_path(Game.SAVE_PATH)
		"load":
			var st := Game.load_game()
			if st.is_empty(): return "no save"
			var pa: Array = st.pos
			_spawn_car(int(st.car), Transform3D(Basis.looking_at(Vector3(st.dir[0], 0, st.dir[2]), Vector3.UP), Vector3(pa[0], pa[1] + 1.0, pa[2])))
			sky.set_hour(float(st.hour)); sky.set_weather(String(st.weather))
			return "loaded"
		"events":
			var s := ""
			for e in events.events: s += "%-6s %-26s %s  best: %s\n" % [e.type, e.name, world.roads[e.road].name, str(Game.personal_bests.get(e.name, "-"))]
			return s
		"bench":
			return "FPS %d | draw calls %d | objects %d | primitives %d | chunks %d | traffic %d | mem %.0f MB" % [Engine.get_frames_per_second(),
				RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
				RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME),
				RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME),
				terrain.chunks.size(), traffic.active.size(), Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0]
		"quit":
			save_state(); get_tree().quit(); return "bye"
	return "unknown command '%s' — type help" % cmd
