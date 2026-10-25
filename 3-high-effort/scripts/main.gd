extends Node3D
## Boots the game: loading screen, world build, player car, camera, UI. Free roam starts on
## the Festival Loop next to the festival site.

var world: World
var player: Car
var camera: CarCamera
var ui: CanvasLayer
var _loading: Control
var _load_bar: ProgressBar
var _load_label: Label
var ready_to_play := false
var audio: Node
var graph: RoadGraph
var waypoint := Vector3.INF
var route_2d := PackedVector2Array()
var _route_mesh: MeshInstance3D
var _reroute_t := 0.0
var photo: Node3D
var _spawn_xform := Transform3D.IDENTITY


func _ready() -> void:
	_make_loading()
	world = World.new()
	world.name = "World"
	add_child(world)
	world.load_progress.connect(_on_progress)
	await world.build()
	_spawn_xform = _default_spawn()
	var pl: Dictionary = Game.pending_load
	if pl.has("position"):
		var p: Array = pl.position
		var pos := Vector3(p[0], p[1], p[2])
		var nr := world.data.nearest_road(pos, 300.0)
		if not nr.is_empty():
			var road: WorldData.Road = nr.road
			_spawn_xform = world.data.road_spawn(road, nr.seg, road.width * 0.25)
	audio = (load("res://scripts/audio/audio_manager.gd") as GDScript).new()
	add_child(audio)
	audio.setup(self)
	camera = CarCamera.new()
	camera.name = "CarCamera"
	add_child(camera)
	camera.current = true
	world.sky.follow = camera
	spawn_car(Game.current_car_index, _spawn_xform)
	world.terrain.focus = player.global_position
	world.terrain.update_streaming(true)
	_load_ui()
	(world.activities as Activities).setup(world, self)
	graph = RoadGraph.new()
	graph.build(world.data)
	photo = (load("res://scripts/ui/photo_mode.gd") as GDScript).new()
	photo.name = "PhotoMode"
	add_child(photo)
	photo.setup(self)
	_on_progress(1.0, "Ready")
	await get_tree().process_frame
	player.freeze = false
	_loading.queue_free()
	ready_to_play = true
	Game.toast(Game.TITLE, "Welcome to the festival. Press Tab for the garage, ` for the console.", "festival")
	if OS.get_cmdline_user_args().size() > 0:
		var qa := load("res://scripts/dev/qa_runner.gd")
		if qa:
			var q: Node = qa.new()
			q.name = "QA"
			add_child(q)


func _default_spawn() -> Transform3D:
	# on the Festival Loop ~280 m before the festival arch, driving toward it
	var loop := world.data.road_by_id("festival_loop")
	var n := loop.pts.size()
	return world.data.road_spawn(loop, n - 72, loop.width * 0.25)


func spawn_car(index: int, xform: Transform3D) -> void:
	index = clampi(index, 0, Game.cars.size() - 1)
	var vel := Vector3.ZERO
	if player:
		vel = player.linear_velocity
		xform = player.global_transform
		xform.origin += Vector3.UP * 0.5
		player.queue_free()
	Game.current_car_index = index
	player = Car.new()
	player.setup(Game.cars[index], true)
	Tuning.apply(player)
	player.freeze = not ready_to_play
	add_child(player)
	var ca := CarAudio.new()
	ca.name = "CarAudio"
	player.add_child(ca)
	ca.setup(player)
	var fx := CarFX.new()
	fx.name = "CarFX"
	player.add_child(fx)
	fx.setup(player)
	player.teleport(xform)
	player.linear_velocity = vel
	if vel.length() > 1.0:
		player.set_velocity_forward(vel.length())
	Game.player = player
	world.focus_node = player
	if camera:
		camera.attach(player)
	if world.sky:
		world.sky.follow = player
	Game.car_changed.emit(player)


func respawn_on_road() -> void:
	if player == null:
		return
	var nr := world.data.nearest_road(player.global_position, 2000.0)
	if nr.is_empty():
		player.teleport(_spawn_xform)
		return
	var road: WorldData.Road = nr.road
	var xf := world.data.road_spawn(road, nr.seg, road.width * 0.25)
	# keep the player's rough heading if it is going the other way
	var fwd := -player.global_transform.basis.z
	if fwd.dot(-xf.basis.z) < 0.0 and road.lanes >= 2:
		xf = Transform3D(xf.basis.rotated(Vector3.UP, PI), road.pts[nr.seg] - Vector3(-road.tangent(nr.seg).z, 0, road.tangent(nr.seg).x) * road.width * 0.25 + Vector3.UP * 0.6)
	player.teleport(xf)


func teleport_player(xf: Transform3D) -> void:
	world.terrain.focus = xf.origin
	world.terrain.update_streaming(true)
	player.teleport(xf)


func toggle_photo_mode() -> void:
	if photo:
		photo.toggle()


func set_waypoint(p: Vector3) -> void:
	waypoint = p
	_reroute_t = 0.0
	_update_route()
	Game.toast("Waypoint set", "Follow the blue GPS line (%.1f km)" % (_route_length() / 1000.0), "info")


func clear_waypoint() -> void:
	waypoint = Vector3.INF
	route_2d = PackedVector2Array()
	if _route_mesh:
		_route_mesh.visible = false


func _route_length() -> float:
	var l := 0.0
	for i in range(1, route_2d.size()):
		l += route_2d[i].distance_to(route_2d[i - 1])
	return l


func _update_route() -> void:
	if waypoint == Vector3.INF or player == null:
		return
	var pts := graph.route(player.global_position, waypoint)
	route_2d = PackedVector2Array()
	for p in pts:
		route_2d.append(Vector2(p.x, p.z))
	# ribbon on the road surface
	if _route_mesh == null:
		_route_mesh = MeshInstance3D.new()
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.25, 0.85, 1.0, 0.55)
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.emission_enabled = true
		m.emission = Color(0.2, 0.75, 1.0)
		m.emission_energy_multiplier = 1.4
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.no_depth_test = false
		_route_mesh.material_override = m
		_route_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_route_mesh)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(1, pts.size()):
		var a := pts[i - 1]
		var b := pts[i]
		var d := (b - a)
		d.y = 0.0
		if d.length() < 0.01:
			continue
		var side := Vector3(-d.z, 0, d.x).normalized() * 0.6
		var up := Vector3.UP * 0.12
		st.add_vertex(a - side + up)
		st.add_vertex(b - side + up)
		st.add_vertex(a + side + up)
		st.add_vertex(a + side + up)
		st.add_vertex(b - side + up)
		st.add_vertex(b + side + up)
	_route_mesh.mesh = st.commit()
	_route_mesh.visible = pts.size() > 1


var _autosave_t := 0.0


func _process(delta: float) -> void:
	_autosave_t += delta
	if _autosave_t > 60.0 and ready_to_play:
		_autosave_t = 0.0
		Game.save_game()
	if waypoint != Vector3.INF and player:
		_reroute_t += delta
		if Vector2(player.global_position.x - waypoint.x, player.global_position.z - waypoint.z).length() < 40.0:
			clear_waypoint()
			Game.toast("Destination reached", "", "event")
		elif _reroute_t > 4.0:
			_reroute_t = 0.0
			_update_route()


func _unhandled_input(event: InputEvent) -> void:
	if not ready_to_play:
		return
	if event.is_action_pressed("reset_car"):
		respawn_on_road()
	elif event.is_action_pressed("screenshot"):
		take_screenshot()


func take_screenshot(path: String = "") -> String:
	if path == "":
		DirAccess.make_dir_recursive_absolute("user://screenshots")
		path = "user://screenshots/velora_%s.png" % Time.get_datetime_string_from_system().replace(":", "-")
	var img := get_viewport().get_texture().get_image()
	img.save_png(path)
	Game.toast("Screenshot saved", ProjectSettings.globalize_path(path), "info")
	return path


func _load_ui() -> void:
	ui = CanvasLayer.new()
	ui.name = "UI"
	ui.layer = 5
	add_child(ui)
	for script_path in ["res://scripts/ui/hud.gd", "res://scripts/ui/console.gd", "res://scripts/ui/garage_menu.gd",
			"res://scripts/ui/debug_menu.gd", "res://scripts/ui/notifications.gd", "res://scripts/ui/map_screen.gd"]:
		if ResourceLoader.exists(script_path):
			var n: Node = (load(script_path) as GDScript).new()
			ui.add_child(n)
			if n.has_method("init_ui"):
				n.init_ui(self)


func _make_loading() -> void:
	var cl := CanvasLayer.new()
	cl.layer = 50
	add_child(cl)
	_loading = Control.new()
	UIStyle.place(_loading, Control.PRESET_FULL_RECT, 0, 0, 0, 0)
	cl.add_child(_loading)
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.06, 0.09)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_loading.add_child(bg)
	var title := Label.new()
	title.text = Game.TITLE.to_upper()
	title.add_theme_font_size_override("font_size", 72)
	title.add_theme_color_override("font_color", Color(1.0, 0.78, 0.3))
	UIStyle.place(title, Control.PRESET_CENTER, -400, -140, 400, -40)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_loading.add_child(title)
	_load_label = Label.new()
	UIStyle.place(_load_label, Control.PRESET_CENTER, -300, 0, 300, 30)
	_load_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_loading.add_child(_load_label)
	_load_bar = ProgressBar.new()
	UIStyle.place(_load_bar, Control.PRESET_CENTER, -300, 40, 300, 54)
	_load_bar.max_value = 1.0
	_load_bar.show_percentage = false
	_loading.add_child(_load_bar)


func _on_progress(f: float, label: String) -> void:
	print("[load %3d%%] %s  (%d ms)" % [int(f * 100.0), label, Time.get_ticks_msec()])
	if _load_bar:
		_load_bar.value = f
		_load_label.text = label
