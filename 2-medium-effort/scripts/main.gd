extends Node3D
## Main scene bootstrap: builds the world, spawns the player car and wires every subsystem together.

const START_ROAD: String = "Harbour Coast Road"
const START_S: float = 260.0

var world: WorldData
var streamer: TerrainStreamer
var roads: RoadBuilder
var sky: SkyWeather
var camera: ChaseCamera
var player_input: PlayerInput
var car: Car
var water: MeshInstance3D
var dressing: Node
var props: Node
var traffic: Node
var activities: Node
var hud: Node
var ui: Node
var audio: Node
var fx: Node
var save: Node
var region: int = -1
var _region_t: float = 0.0
var boot_ms: int = 0
var reset_count: int = 0
var _loading: CanvasLayer


func _ready() -> void:
	add_to_group("main")
	_show_loading()
	await get_tree().process_frame
	await get_tree().process_frame
	var t0: int = Time.get_ticks_msec()
	world = WorldData.new()
	world.build()
	Game.world = world
	sky = SkyWeather.new()
	sky.name = "SkyWeather"
	add_child(sky)
	Game.sky = sky
	var noise_tex := _noise_tex()
	var tmat := ShaderMaterial.new()
	tmat.shader = load("res://shaders/terrain.gdshader")
	tmat.set_shader_parameter("noise_tex", noise_tex)
	streamer = TerrainStreamer.new()
	streamer.name = "Terrain"
	streamer.setup(world, tmat)
	add_child(streamer)
	Game.streamer = streamer
	if ResourceLoader.exists("res://scripts/world/dressing.gd"):
		dressing = load("res://scripts/world/dressing.gd").new()
		dressing.name = "Dressing"
		add_child(dressing)
		dressing.setup(world)
		streamer.dressing = dressing
	streamer.build_far_mesh()
	roads = RoadBuilder.new()
	roads.name = "Roads"
	add_child(roads)
	roads.build(world)
	_make_water(noise_tex)
	if ResourceLoader.exists("res://scripts/world/props_placer.gd"):
		props = load("res://scripts/world/props_placer.gd").new()
		props.name = "Props"
		add_child(props)
		props.build(world)
	camera = ChaseCamera.new()
	camera.name = "Camera"
	add_child(camera)
	camera.current = true
	Game.camera = camera
	player_input = PlayerInput.new()
	player_input.name = "PlayerInput"
	add_child(player_input)
	for opt in [["res://scripts/vehicle/car_fx.gd", "fx"], ["res://scripts/traffic/traffic_manager.gd", "traffic"],
			["res://scripts/activities/activity_manager.gd", "activities"], ["res://scripts/ui/ui_root.gd", "ui"],
			["res://scripts/core/save_system.gd", "save"]]:
		if ResourceLoader.exists(opt[0]):
			var n: Node = load(opt[0]).new()
			n.name = opt[1].capitalize()
			set(opt[1], n)
			add_child(n)
	Game.traffic = traffic
	Game.activities = activities
	var spawn_t: Transform3D = road_transform_by_name(START_ROAD, START_S)
	var car_index: int = 0
	if save and save.has_method("load_game"):
		var st: Dictionary = save.load_game()
		if st.has("car"):
			car_index = clampi(int(st.car), 0, Game.cars.size() - 1)
		if st.has("pos") and st.get("restore_pos", true):
			var p: Vector3 = st.pos
			var nr: Dictionary = world.nearest_road_point(p)
			if not nr.is_empty():
				spawn_t = world.road_point(nr.road, nr.s, world.roads[nr.road].lane * 0.5)
	streamer.force_load(spawn_t.origin, 300.0)
	spawn_car(car_index, spawn_t)
	if activities and activities.has_method("build"):
		activities.build(world)
	if traffic and traffic.has_method("setup"):
		traffic.setup(world)
	await _warmup()
	boot_ms = Time.get_ticks_msec() - t0
	print("[boot] world ready in %d ms, road km %.1f, loop km %.1f, road pieces %d" % [boot_ms, world.total_length / 1000.0, world.loop_length / 1000.0, roads.stats.pieces])
	_loading.queue_free()
	Game.toast(Game.TITLE, "Welcome to the festival. Press Tab for the garage, ` for the console.", Color(1.0, 0.45, 0.75))
	if "--qa" in OS.get_cmdline_user_args() or OS.get_cmdline_user_args().has("--qa"):
		var qa: Node = load("res://tools/qa_runner.gd").new()
		add_child(qa)


## Renders one instance of every model/material in front of the camera behind the loading screen so
## shader pipelines compile before play instead of stalling the first time something appears.
func _warmup() -> void:
	var holder := Node3D.new()
	add_child(holder)
	var paths: Array = []
	for dir in ["res://assets/imported/props/", "res://assets/imported/traffic/", "res://assets/imported/cars/"]:
		# ResourceLoader.list_directory also works inside exported packs (where files are remapped)
		for f in ResourceLoader.list_directory(dir):
			if f.ends_with(".glb"):
				paths.append(dir + f)
	var cam_t: Transform3D = camera.global_transform
	var i: int = 0
	for pth in paths:
		var n: Node3D = load(pth).instantiate()
		holder.add_child(n)
		n.global_position = cam_t.origin - cam_t.basis.z * (12.0 + (i % 6) * 4.0) + cam_t.basis.x * ((i % 5) - 2) * 4.0
		n.scale = Vector3.ONE * 0.2
		i += 1
	for k in 4:
		await get_tree().process_frame
	holder.queue_free()


func _show_loading() -> void:
	_loading = CanvasLayer.new()
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.06, 0.1)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_loading.add_child(bg)
	var l := Label.new()
	l.text = Game.TITLE + "\nBuilding the world..."
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.set_anchors_preset(Control.PRESET_FULL_RECT)
	l.add_theme_font_size_override("font_size", 42)
	_loading.add_child(l)
	add_child(_loading)


func _noise_tex() -> NoiseTexture2D:
	var noise := FastNoiseLite.new()
	noise.frequency = 0.04
	noise.fractal_octaves = 4
	var tex := NoiseTexture2D.new()
	tex.width = 512
	tex.height = 512
	tex.seamless = true
	tex.noise = noise
	return tex


func _make_water(tex: Texture2D) -> void:
	water = MeshInstance3D.new()
	water.name = "Water"
	var pm := PlaneMesh.new()
	pm.size = Vector2(12000, 12000)
	pm.subdivide_width = 4
	pm.subdivide_depth = 4
	water.mesh = pm
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/water.gdshader")
	m.set_shader_parameter("noise_tex", tex)
	water.material_override = m
	water.position = Vector3(0, 0.0, 0)
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(water)


func road_index(rname: String) -> int:
	for i in world.roads.size():
		if world.roads[i].name == rname:
			return i
	return 0


func road_transform_by_name(rname: String, s: float) -> Transform3D:
	var ri: int = road_index(rname)
	var t: Transform3D = world.road_point(ri, s, world.roads[ri].lane * 0.5)
	t.origin.y += 0.6
	return t


func spawn_car(index: int, t: Transform3D, keep_speed: bool = false) -> void:
	var v: float = 0.0
	if car and is_instance_valid(car):
		v = car.speed if keep_speed else 0.0
		car.queue_free()
		remove_child(car)
	Game.current_car_index = index
	var def: CarDef = Game.cars[index]
	car = Car.new()
	car.setup(def)
	car.global_transform = t
	add_child(car)
	car.global_transform = t
	var p: Dictionary = Game.paint_overrides.get(def.id, {})
	if not p.is_empty():
		car.set_paint(p.color, p.finish, p.get("stripe", 0), p.get("stripe_color", Color.WHITE))
		if p.has("rim"):
			car.set_rim_color(p.rim)
	if keep_speed and v > 1.0:
		car.set_speed_forward(v)
	Game.player = car
	camera.set_target(car)
	player_input.car = car
	sky.follow = car
	car.set_lights(sky.is_night())
	car.impact.connect(func(s: float) -> void: camera.add_shake(s))
	Game.car_changed.emit(car)


func switch_car(index: int) -> void:
	if car == null:
		return
	var t: Transform3D = car.global_transform
	# keep heading, drop any roll/pitch and lift slightly
	var fwd: Vector3 = -t.basis.z
	fwd.y = 0.0
	t = Transform3D(Basis.looking_at(fwd.normalized(), Vector3.UP), t.origin + Vector3(0, 0.5, 0))
	spawn_car(index, t, true)
	Game.toast("Now driving", Game.cars[index].maker + " " + Game.cars[index].display_name, Color(0.3, 0.75, 1.0))


func reset_player_to_road() -> void:
	if car == null:
		return
	reset_count += 1
	var nr: Dictionary = world.nearest_road_point(car.global_position)
	if nr.is_empty():
		return
	var r: Dictionary = world.roads[nr.road]
	var t: Transform3D = world.road_point(nr.road, nr.s, r.lane * 0.5)
	# keep driving direction if the car was heading the other way
	var fwd: Vector3 = -car.global_transform.basis.z
	if fwd.dot(-t.basis.z) < 0.0:
		t = world.road_point(nr.road, nr.s, -r.lane * 0.5)
		t.basis = t.basis.rotated(Vector3.UP, PI)
	t.origin.y += 0.6
	streamer.force_load(t.origin, 200.0)
	car.teleport(t)
	car.damage = 0.0


func teleport_to(t: Transform3D) -> void:
	streamer.force_load(t.origin, 300.0)
	car.teleport(t)
	camera.set_target(car)


func teleport_poi(nm: String) -> bool:
	if not RoadLayout.POIS.has(nm):
		return false
	var p: Vector2 = RoadLayout.POIS[nm]
	var nr: Dictionary = world.nearest_road_point(Vector3(p.x, 0, p.y))
	if nr.is_empty():
		return false
	var t: Transform3D = world.road_point(nr.road, nr.s, world.roads[nr.road].lane * 0.5)
	t.origin.y += 0.6
	teleport_to(t)
	return true


func _process(delta: float) -> void:
	var _pf: int = Time.get_ticks_usec()
	_inner_main(delta)
	Game.prof_add("main", _pf)


func _inner_main(delta: float) -> void:
	if car == null or not is_instance_valid(car):
		return
	streamer.focus = car.global_position + car.linear_velocity * 1.5
	car.weather_grip = sky.grip
	if sky.is_night() != car.lights_on and _region_t > 0.0 and not car.get_meta("manual_lights", false):
		car.set_lights(sky.is_night())
	_region_t += delta
	if _region_t > 0.5:
		_region_t = 0.01
		var r: int = world.region_at(car.global_position.x, car.global_position.z)
		if r != region:
			region = r
			Game.region_changed.emit(WorldData.REGION_NAMES[r])
	# safety net: fell through the world
	var cp: Vector3 = car.global_position
	if cp.y < -30.0:
		reset_player_to_road()
	elif cp.y < world.height(cp.x, cp.z) - 6.0:
		var q: Dictionary = world.road_query(cp.x, cp.z, 30.0)
		if not (q.ok and q.flag == 2 and absf(cp.y - q.hc) < 6.0):
			reset_player_to_road()
