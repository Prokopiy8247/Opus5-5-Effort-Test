extends Node3D
## Game root. Builds environment, world, player car, camera, UI, traffic and activities, owns the
## player-car lifecycle (switching, paint, upgrades, tuning, respawn, teleport) and save/load.

const SAVE_PATH := "user://savegame.json"

var env_ctrl: EnvironmentController
var world: Node3D
var vehicles: Node3D
var skids: SkidManager
var cam_rig: CameraRig
var player_input: PlayerInput
var hud: Hud
var console: DevConsole
var garage: GarageMenu
var debug_menu: DebugMenu
var photo: Node
var minimap: Node
var world_map: Node
var car_setups: Dictionary = {}
var waypoint: Vector3 = Vector3.INF
var _region: String = ""
var _region_timer: float = 0.0
var _autosave_timer: float = 60.0
var _started: bool = false


func _ready() -> void:
	Game.main = self
	get_tree().set_auto_accept_quit(false)
	env_ctrl = EnvironmentController.new()
	env_ctrl.name = "Environment"
	add_child(env_ctrl)
	Game.environment = env_ctrl
	world = _create_world()
	add_child(world)
	Game.world = world
	vehicles = Node3D.new()
	vehicles.name = "Vehicles"
	add_child(vehicles)
	skids = SkidManager.new()
	add_child(skids)
	cam_rig = CameraRig.new()
	cam_rig.name = "CameraRig"
	add_child(cam_rig)
	Game.camera_rig = cam_rig
	player_input = PlayerInput.new()
	player_input.name = "PlayerInput"
	add_child(player_input)
	var rewind := RewindBuffer.new()
	rewind.name = "Rewind"
	add_child(rewind)
	var line := BrakingLine.new()
	line.name = "BrakingLine"
	add_child(line)
	var amb := Ambience.new()
	amb.name = "Ambience"
	add_child(amb)
	hud = Hud.new()
	hud.name = "Hud"
	add_child(hud)
	Game.hud = hud
	console = DevConsole.new()
	console.name = "Console"
	add_child(console)
	garage = GarageMenu.new()
	garage.name = "Garage"
	add_child(garage)
	debug_menu = DebugMenu.new()
	debug_menu.name = "DebugMenu"
	add_child(debug_menu)
	_create_optional_systems()

	var loaded := false
	if not Game.qa_args.has("fresh"):
		loaded = load_game()
	if not loaded:
		Game.current_car_index = clampi(int(Game.qa_args.get("car", "1")) - 1, 0, maxi(Game.car_defs.size() - 1, 0))
		_spawn_player(Game.current_car_index, world.call("spawn_transform"))
	if Game.qa_args.has("time"):
		env_ctrl.set_time(float(Game.qa_args["time"]))
	if Game.qa_args.has("weather"):
		env_ctrl.set_weather_by_name(String(Game.qa_args["weather"]))
		env_ctrl.set_weather(env_ctrl.weather, true)
	if Game.qa_args.has("qa"):
		var qa := load("res://scripts/dev/qa_runner.gd").new() as Node
		qa.name = "QaRunner"
		add_child(qa)
	_started = true
	Game.show_notification("Welcome to Ridgeline Festival", "F1 garage · ` console · F3 benchmark menu", "event")


func _create_world() -> Node3D:
	var want_test := String(Game.qa_args.get("world", "")) == "test"
	if not want_test and ResourceLoader.exists("res://scripts/world/open_world.gd") and FileAccess.file_exists("res://data/world/world_meta.json"):
		var w := (load("res://scripts/world/open_world.gd") as GDScript).new() as Node3D
		w.name = "World"
		return w
	var t := TestTrack.new()
	t.name = "World"
	return t


func _create_optional_systems() -> void:
	# systems added in later milestones are created only if their scripts exist
	var optional := [
		["res://scripts/traffic/traffic_manager.gd", "Traffic", "traffic"],
		["res://scripts/activities/activity_manager.gd", "Activities", "activities"],
		["res://scripts/ui/minimap.gd", "Minimap", ""],
		["res://scripts/ui/world_map.gd", "WorldMap", ""],
		["res://scripts/ui/photo_mode.gd", "PhotoMode", ""],
	]
	for o in optional:
		if not ResourceLoader.exists(o[0]):
			continue
		var n := (load(o[0]) as GDScript).new() as Node
		n.name = o[1]
		add_child(n)
		match o[1]:
			"Traffic":
				Game.traffic = n
			"Activities":
				Game.activities = n
			"Minimap":
				minimap = n
			"WorldMap":
				world_map = n
			"PhotoMode":
				photo = n


# =================================================================================================
# player car
func _setup_for(def: CarDefinition) -> Dictionary:
	var key := String(def.id)
	if not car_setups.has(key):
		car_setups[key] = {"upgrades": {}, "tuning": {}, "color": def.default_color, "finish": int(def.default_finish),
			"rim": "", "stripes": false}
	return car_setups[key]


func current_setup() -> Dictionary:
	if Game.car_defs.is_empty():
		return {}
	return _setup_for(Game.car_defs[Game.current_car_index])


func runtime_definition(idx: int) -> CarDefinition:
	var base := Game.car_defs[idx]
	var setup := _setup_for(base)
	return CarTuning.build(base, setup["upgrades"], setup["tuning"])


func _spawn_player(idx: int, xf: Transform3D, keep_speed: float = 0.0) -> void:
	if Game.car_defs.is_empty():
		push_error("No cars in catalogue")
		return
	idx = clampi(idx, 0, Game.car_defs.size() - 1)
	var old := Game.player_car
	var base := Game.car_defs[idx]
	var setup := _setup_for(base)
	var def := CarTuning.build(base, setup["upgrades"], setup["tuning"])
	var car := CarFactory.build(def, setup["color"], int(setup["finish"]))
	car.control_mode = CarController.ControlMode.PLAYER
	car.name = "PlayerCar"
	if old != null and is_instance_valid(old):
		# keep it in the tree until freed (engine nodes still query its transform this frame),
		# but switch it off so it cannot collide with the new car
		old.name = "PlayerCar_old"
		old.process_mode = Node.PROCESS_MODE_DISABLED
		old.collision_layer = 0
		old.collision_mask = 0
		old.freeze = true
		old.visible = false
		old.queue_free()
	vehicles.add_child(car)
	car.global_transform = xf
	car.reset_to(xf, keep_speed)
	if world.has_method("surface_at"):
		car.set_terrain_surface_callback(Callable(world, "surface_at"))
	var audio := CarAudio.new()
	audio.name = "Audio"
	car.add_child(audio)
	audio.setup(car)
	var lights := CarLights.new()
	lights.name = "Lights"
	car.add_child(lights)
	lights.setup(car, true)
	var fx := CarFx.new()
	fx.name = "Fx"
	car.add_child(fx)
	fx.setup(car, skids)
	Game.current_car_index = idx
	Game.player_car = car
	Game.paint_color = setup["color"]
	Game.paint_finish = int(setup["finish"])
	player_input.car = car
	cam_rig.set_car(car)
	hud.set_car(car)
	if String(setup.get("rim", "")) != "":
		set_rim_style(String(setup["rim"]))
	if bool(setup.get("stripes", false)):
		set_stripes(true)
	apply_assists()
	Game.car_changed.emit(car)


func switch_car(idx: int) -> void:
	if Game.player_car == null:
		_spawn_player(idx, world.call("spawn_transform"))
		return
	var car := Game.player_car
	var xf := car.global_transform
	var fwd := -xf.basis.z
	fwd.y = 0.0
	if fwd.length() < 0.1:
		fwd = Vector3.FORWARD
	# put the new car on the ground under the old one (a drop would leave it bouncing for a second)
	var pos := xf.origin + Vector3.UP * 0.6
	var q := PhysicsRayQueryParameters3D.create(xf.origin + Vector3.UP * 2.0, xf.origin + Vector3.DOWN * 4.0, 1)
	q.exclude = [car.get_rid()]
	var hit := car.get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		pos = (hit.position as Vector3) + Vector3.UP * 0.04
	var t := Transform3D(Basis.looking_at(fwd.normalized(), Vector3.UP), pos)
	var spd := maxf(car.forward_speed, 0.0)
	_spawn_player(idx, t, spd)
	Game.show_notification(Game.car_defs[idx].display_name, "%s · %s %d" % [Game.car_defs[idx].category, Game.car_defs[idx].performance_class, Game.car_defs[idx].performance_index], "info")


func _respawn_current_with_setup() -> void:
	# rebuild the car in place after upgrade/tuning changes
	switch_car(Game.current_car_index)


func set_paint(color: Color, finish: int) -> void:
	var setup := current_setup()
	setup["color"] = color
	setup["finish"] = finish
	Game.paint_color = color
	Game.paint_finish = finish
	var car := Game.player_car
	if car != null and car.has_meta("paint_material"):
		CarMaterials.set_paint(car.get_meta("paint_material") as ShaderMaterial, color, finish)


func set_stripes(on: bool) -> void:
	var setup := current_setup()
	setup["stripes"] = on
	var car := Game.player_car
	if car != null and car.has_meta("paint_material"):
		(car.get_meta("paint_material") as ShaderMaterial).set_shader_parameter("stripes", on)


func set_rim_style(key: String) -> void:
	var setup := current_setup()
	setup["rim"] = key
	var car := Game.player_car
	if car == null:
		return
	var mat := CarMaterials.get_mat(key)
	for w in car.wheels:
		if w.node == null:
			continue
		for mi in w.node.find_children("*", "MeshInstance3D", true, false):
			var m := mi as MeshInstance3D
			if m.mesh.get_surface_count() > 1:
				m.set_surface_override_material(1, mat)
		if w.node is MeshInstance3D and (w.node as MeshInstance3D).mesh.get_surface_count() > 1:
			(w.node as MeshInstance3D).set_surface_override_material(1, mat)


func apply_assists() -> void:
	var car := Game.player_car
	if car == null:
		return
	car.assist_tcs = Game.assists.get("tcs", true)
	car.assist_esc = Game.assists.get("esc", true)
	car.assist_abs = Game.assists.get("abs", true)
	car.assist_steer = Game.assists.get("steer", true)
	car.auto_gearbox = Game.assists.get("auto_gear", true)


func set_upgrade(part: String, level: int) -> String:
	if not CarTuning.PARTS.has(part):
		return "unknown part (engine|tires|suspension|brakes|weight|aero)"
	var setup := current_setup()
	var levels: Dictionary = setup["upgrades"]
	levels[part] = clampi(level, 0, 3)
	_respawn_current_with_setup()
	return "%s upgrade level %d" % [part, levels[part]]


func set_tuning(key: String, value: float) -> String:
	if not CarTuning.TUNING_DEFAULTS.has(key):
		return "unknown tuning key; keys: " + ", ".join(CarTuning.TUNING_DEFAULTS.keys())
	var rng: Array = CarTuning.TUNING_RANGES[key]
	var setup := current_setup()
	(setup["tuning"] as Dictionary)[key] = clampf(value, rng[0], rng[1])
	_respawn_current_with_setup()
	return "%s = %.3f" % [key, (setup["tuning"] as Dictionary)[key]]


func reset_tuning() -> void:
	current_setup()["tuning"] = {}
	_respawn_current_with_setup()


func tuning_summary() -> String:
	var setup := current_setup()
	return "upgrades %s\ntuning %s\nkeys: %s" % [setup.get("upgrades", {}), setup.get("tuning", {}), ", ".join(CarTuning.TUNING_DEFAULTS.keys())]


func respawn_on_road() -> void:
	var car := Game.player_car
	if car == null:
		return
	var t: Transform3D = world.call("nearest_road_transform", car.global_position, -car.global_transform.basis.z)
	car.reset_to(t)
	cam_rig.snap()


func teleport_targets() -> Array:
	var d: Dictionary = world.call("teleport_targets")
	var keys := d.keys()
	return keys


func teleport(target: String) -> bool:
	var d: Dictionary = world.call("teleport_targets")
	var key := ""
	for k in d.keys():
		if String(k).to_lower() == target.to_lower():
			key = k
	if key == "":
		for k in d.keys():
			if String(k).to_lower().contains(target.to_lower()):
				key = k
				break
	if key == "" or Game.player_car == null:
		return false
	var t: Transform3D = d[key]
	if world.has_method("prepare_area"):
		world.call("prepare_area", t.origin)
	Game.player_car.reset_to(t)
	cam_rig.snap()
	return true


func open_garage() -> void:
	garage.open()


func toggle_photo_mode() -> void:
	if photo != null and photo.has_method("toggle"):
		photo.call("toggle")
	else:
		Game.show_notification("Photo mode", "not available in this build", "info")


func set_waypoint(p: Vector3) -> void:
	waypoint = p
	if Game.world != null and Game.world.has_method("set_route_target"):
		Game.world.call("set_route_target", p)


# =================================================================================================
func _process(delta: float) -> void:
	var car := Game.player_car
	if car == null or not is_instance_valid(car):
		return
	car.wetness = env_ctrl.wetness
	RenderingServer.global_shader_parameter_set("player_pos", car.global_position)
	if Input.is_action_just_pressed("reset_car") and not Game.ui_blocks_driving():
		respawn_on_road()
	if Input.is_action_just_pressed("photo_mode") and not Game.ui_focus.has("console"):
		toggle_photo_mode()
	if Input.is_action_just_pressed("screenshot"):
		take_screenshot()
	_region_timer -= delta
	if _region_timer <= 0.0 and world.has_method("region_at"):
		_region_timer = 0.5
		var p := car.global_position
		var r := String(world.call("region_at", p.x, p.z))
		if r != _region and r != "":
			_region = r
			Game.region_entered.emit(r)
	_autosave_timer -= delta
	if _autosave_timer <= 0.0:
		_autosave_timer = 60.0
		save_game()


func take_screenshot(path: String = "") -> String:
	var img := get_viewport().get_texture().get_image()
	if path == "":
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://screenshots"))
		path = "user://screenshots/shot_%s.png" % Time.get_datetime_string_from_system().replace(":", "-")
	img.save_png(path)
	Game.show_notification("Screenshot saved", ProjectSettings.globalize_path(path), "info")
	return path


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		if _started:
			save_game()
		get_tree().quit()


# =================================================================================================
# save / load
func save_game() -> bool:
	var car := Game.player_car
	if car == null:
		return false
	var setups := {}
	for k in car_setups:
		var s: Dictionary = car_setups[k]
		setups[k] = {"upgrades": s["upgrades"], "tuning": s["tuning"], "color": (s["color"] as Color).to_html(),
			"finish": s["finish"], "rim": s.get("rim", ""), "stripes": s.get("stripes", false)}
	var xf := car.global_transform
	var data := {
		"version": 1,
		"car": String(Game.car_defs[Game.current_car_index].id),
		"position": [xf.origin.x, xf.origin.y, xf.origin.z],
		"heading": [-xf.basis.z.x, -xf.basis.z.z],
		"time": env_ctrl.time_of_day,
		"weather": env_ctrl.weather_name(),
		"settings": Game.settings,
		"assists": Game.assists,
		"setups": setups,
		"bests": Game.activities.call("get_bests") if Game.activities != null and Game.activities.has_method("get_bests") else {},
		"credits": Game.activities.call("get_credits") if Game.activities != null and Game.activities.has_method("get_credits") else 0,
		"world": world.get_class() if not world is TestTrack else "test",
	}
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(data, "  "))
	f.close()
	return true


func load_game() -> bool:
	if not FileAccess.file_exists(SAVE_PATH):
		return false
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if not parsed is Dictionary:
		return false
	var data: Dictionary = parsed
	var setups: Dictionary = data.get("setups", {})
	for k in setups:
		var s: Dictionary = setups[k]
		car_setups[k] = {"upgrades": s.get("upgrades", {}), "tuning": s.get("tuning", {}), "color": Color.html(String(s.get("color", "#cc2020"))),
			"finish": int(s.get("finish", 1)), "rim": String(s.get("rim", "")), "stripes": bool(s.get("stripes", false))}
	var st: Dictionary = data.get("settings", {})
	Game.settings.merge(st, true)
	var asst: Dictionary = data.get("assists", {})
	Game.assists.merge(asst, true)
	env_ctrl.set_time(float(data.get("time", 10.5)))
	env_ctrl.set_weather_by_name(String(data.get("weather", "clear")))
	env_ctrl.set_weather(env_ctrl.weather, true)
	if Game.activities != null and Game.activities.has_method("set_bests"):
		Game.activities.call("set_bests", data.get("bests", {}), int(data.get("credits", 0)))
	var idx := Game.find_car_index(String(data.get("car", "")))
	if idx < 0:
		idx = 0
	var pos_a: Array = data.get("position", [])
	var head_a: Array = data.get("heading", [0.0, -1.0])
	var same_world := String(data.get("world", "")) == ("test" if world is TestTrack else world.get_class())
	var t: Transform3D = world.call("spawn_transform")
	if pos_a.size() == 3 and same_world:
		var p := Vector3(pos_a[0], pos_a[1], pos_a[2])
		var h := Vector3(float(head_a[0]), 0.0, float(head_a[1]))
		# dynamic objects are not persisted: snap back onto the nearest road for a safe restart
		if world.has_method("prepare_area"):
			world.call("prepare_area", p)
		t = world.call("nearest_road_transform", p, h)
	if Game.player_car == null:
		_spawn_player(idx, t)
	else:
		_spawn_player(idx, t)
	Game.show_notification("Save loaded", Game.car_defs[idx].display_name, "info")
	return true
