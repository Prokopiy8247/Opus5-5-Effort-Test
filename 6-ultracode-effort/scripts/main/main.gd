extends Node3D
## Main scene: builds the world, environment, player car, camera, traffic, activities and UI,
## and implements the car / teleport services used through the Game autoload.
## Command-line QA hooks (after "--"): --qa=<scenario> handled by QaDirector.

const ENV_SCRIPT := "res://scripts/env/environment_controller.gd"
const TRAFFIC_SCRIPT := "res://scripts/traffic/traffic_manager.gd"
const ACTIVITIES_SCRIPT := "res://scripts/activities/activity_manager.gd"
const UI_SCRIPT := "res://scripts/ui/ui_root.gd"
const AUDIO_SCRIPT := "res://scripts/audio/car_audio.gd"
const EFFECTS_SCRIPT := "res://scripts/vehicle/car_effects.gd"
const DRESSING_SCRIPT := "res://scripts/world/dressing.gd"
const SETTLEMENTS_SCRIPT := "res://scripts/world/settlements.gd"
const AMBIENT_SCRIPT := "res://scripts/audio/ambient_audio.gd"
## Frames the pipeline warm-up viewport renders while the loading screen is up.
const WARMUP_FRAMES := 4

var world: Node3D
var camera_rig: CameraRig
var car_input: CarInput
var player_car: CarController
var loading_layer: CanvasLayer
var loading_label: Label
var is_loading: bool = true
var _fallback_env: WorldEnvironment
var _fallback_sun: DirectionalLight3D
var _load_time: float = 0.0
var _water_timer: float = 0.0
## Loading-screen render-pipeline warm-up (see _start_pipeline_warmup).
var _warmup: SubViewport
var _warmup_frames: int = 0


func _ready() -> void:
	Game.main = self
	_build_loading_screen()
	camera_rig = CameraRig.new()
	camera_rig.name = "CameraRig"
	add_child(camera_rig)
	Game.camera_rig = camera_rig
	car_input = CarInput.new()
	car_input.name = "CarInput"
	add_child(car_input)
	var bl: Node = (load("res://scripts/vehicle/braking_line.gd") as Script).new()
	bl.name = "BrakingLine"
	add_child(bl)
	_build_world()
	_build_environment()
	_add_optional(DRESSING_SCRIPT, "Dressing", self, func(n: Node) -> void: Game.set_meta(&"dressing", n))
	_add_optional(SETTLEMENTS_SCRIPT, "Settlements", self)
	_add_optional(TRAFFIC_SCRIPT, "Traffic", self, func(n: Node) -> void: Game.traffic = n)
	_add_optional(ACTIVITIES_SCRIPT, "Activities", self, func(n: Node) -> void: Game.activities = n)
	_add_optional(UI_SCRIPT, "UI", self, func(n: Node) -> void: Game.hud = n)
	_add_optional(AMBIENT_SCRIPT, "AmbientAudio", self)
	var saved: Dictionary = SaveGame.pending
	var idx := int(saved.get("car_index", Game.current_car_index)) if not saved.is_empty() else 0
	spawn_player_car(idx, false)
	_place_initial(saved)
	_start_pipeline_warmup()
	if not saved.is_empty() and Game.env:
		if saved.has("time_of_day"):
			Game.set_time_of_day(float(saved["time_of_day"]))
		if saved.has("weather"):
			Game.set_weather(String(saved["weather"]), true)
	var qa := QaDirector.new()
	qa.name = "QaDirector"
	add_child(qa)


func _add_optional(path: String, node_name: String, parent: Node, on_added := Callable()) -> Node:
	if not ResourceLoader.exists(path):
		return null
	var scr: Script = load(path)
	if scr == null:
		return null
	var n: Node = scr.new()
	n.name = node_name
	parent.add_child(n)
	if on_added.is_valid():
		on_added.call(n)
	return n


func _build_world() -> void:
	var w := World.new()
	w.name = "World"
	add_child(w)
	if w.build():
		world = w
		Game.world = w
		return
	w.queue_free()
	push_error("World data missing - falling back to the proving ground")
	var tt := TestTrack.new()
	tt.name = "World"
	add_child(tt)
	world = tt
	Game.world = tt


func _build_environment() -> void:
	if ResourceLoader.exists(ENV_SCRIPT):
		var env: Node = _add_optional(ENV_SCRIPT, "Environment", self)
		if env != null:
			Game.env = env
			return
	# Minimal fallback lighting until the environment controller exists.
	_fallback_sun = DirectionalLight3D.new()
	_fallback_sun.rotation_degrees = Vector3(-40, 35, 0)
	_fallback_sun.shadow_enabled = true
	_fallback_sun.directional_shadow_max_distance = 350.0
	add_child(_fallback_sun)
	_fallback_env = WorldEnvironment.new()
	var env2 := Environment.new()
	env2.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var psm := ProceduralSkyMaterial.new()
	sky.sky_material = psm
	env2.sky = sky
	env2.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env2.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env2.fog_enabled = true
	env2.fog_density = 0.00015
	env2.fog_aerial_perspective = 0.6
	_fallback_env.environment = env2
	add_child(_fallback_env)


func _build_loading_screen() -> void:
	loading_layer = CanvasLayer.new()
	loading_layer.layer = 100
	add_child(loading_layer)
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.06, 0.09)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	loading_layer.add_child(bg)
	var title := Label.new()
	title.text = Game.GAME_TITLE.to_upper()
	title.add_theme_font_size_override("font_size", 72)
	title.add_theme_color_override("font_color", Color(1.0, 0.72, 0.25))
	title.set_anchors_preset(Control.PRESET_CENTER)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.position = Vector2(-400, -110)
	title.size = Vector2(800, 100)
	loading_layer.add_child(title)
	loading_label = Label.new()
	loading_label.text = "Loading the open road..."
	loading_label.add_theme_font_size_override("font_size", 24)
	loading_label.set_anchors_preset(Control.PRESET_CENTER)
	loading_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	loading_label.position = Vector2(-400, 10)
	loading_label.size = Vector2(800, 40)
	loading_layer.add_child(loading_label)


## Forward+ compiles every scene surface's pipelines again, in one frame, the first time any reflection probe
## is drawn (a renderer-wide pipeline variant). The first view of the Ember Spur tunnel probes, often from
## kilometres away on the open road, froze the game for 0.1-0.8 s. A tiny off-screen viewport with its own
## world draws a probe during loading instead, so that switch (and its recompile) happens behind the
## loading screen; surfaces created later are compiled with the variant from the start.
func _start_pipeline_warmup() -> void:
	_warmup = SubViewport.new()
	_warmup.name = "PipelineWarmup"
	_warmup.size = Vector2i(64, 64)
	_warmup.own_world_3d = true
	_warmup.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var cam := Camera3D.new()
	cam.far = 50.0
	_warmup.add_child(cam)
	var probe := ReflectionProbe.new()
	probe.size = Vector3(4.0, 4.0, 4.0)
	probe.max_distance = 10.0
	probe.position = Vector3(0.0, 0.0, -4.0)
	_warmup.add_child(probe)
	var box := MeshInstance3D.new()
	box.mesh = BoxMesh.new()
	box.position = Vector3(0.0, 0.0, -4.0)
	_warmup.add_child(box)
	add_child(_warmup)


func _process(delta: float) -> void:
	if is_loading:
		_load_time += delta
		var ready := true
		if world is World:
			var w := world as World
			ready = w.is_ready_near()
			loading_label.text = "Loading the open road...  terrain %d  roads %s" % [w.terrain.pending_count(), "ok" if w.roads.done else "building"]
		if _warmup != null:
			_warmup_frames += 1
			if _warmup_frames >= WARMUP_FRAMES:
				_warmup.queue_free()
				_warmup = null
			ready = false
		if ready or _load_time > 45.0:
			is_loading = false
			loading_layer.visible = false
			if player_car:
				player_car.freeze = false
				_snap_to_ground(player_car)
			Game.notify(Game.FESTIVAL_NAME, "Welcome to %s. Press F1 for the garage, ` for the console." % Game.GAME_TITLE, &"hub")


func _physics_process(delta: float) -> void:
	if is_loading or player_car == null or not is_instance_valid(player_car):
		return
	# Recover from water / falling out of the world.
	var p := player_car.global_position
	var sunk := false
	if world is World:
		var wl: float = (world as World).water_level_at(p.x, p.z)
		sunk = p.y < wl - 1.0
		if p.y < (world as World).height_at(p.x, p.z) - 8.0 and not _in_tunnel(p):
			sunk = true
	_water_timer = _water_timer + delta if sunk else 0.0
	if _water_timer > 0.8:
		_water_timer = 0.0
		Game.notify("Recovered", "Your car was returned to the road", &"info")
		respawn_on_road()


func _in_tunnel(p: Vector3) -> bool:
	var res: Dictionary = (world as World).data.network.nearest(p, 20.0)
	return not res.is_empty() and ((res["road"] as RoadNetwork.Road).flag_at(float(res["s"])) & 2) != 0


func _place_initial(saved: Dictionary) -> void:
	if world is World:
		var sp: Dictionary = (world as World).spawn_point()
		var pos: Vector3 = sp["position"]
		var fwd: Vector3 = sp["forward"]
		if saved.has("position"):
			var arr: Array = saved["position"]
			var sp2: Dictionary = (world as World).nearest_road_point(Vector3(arr[0], arr[1], arr[2]))
			pos = sp2["position"]
			fwd = sp2["forward"]
		_place_on(pos, fwd)
	player_car.freeze = true


func _snap_to_ground(car: CarController, vel := Vector3.ZERO) -> void:
	var p := car.global_position
	var space := get_world_3d().direct_space_state
	# Cast from just above the car: a high start would land it on a tunnel roof, overpass or bridge deck.
	var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 3.0, p - Vector3.UP * 60.0, 1)
	var hit := space.intersect_ray(q)
	if not hit.is_empty():
		var xf := car.global_transform
		xf.origin.y = (hit["position"] as Vector3).y + 0.35
		car.place_at(xf, vel)


func spawn_player_car(index: int, keep_transform: bool) -> void:
	var xf := Transform3D(Basis(), Vector3(0, 0.3, 0))
	var vel := Vector3.ZERO
	var had := player_car != null and is_instance_valid(player_car)
	if keep_transform and had:
		xf = player_car.global_transform
		vel = player_car.linear_velocity
	if had:
		# Leave the tree now so the old car's _exit_tree (dirt memory etc.) runs before the new car is built.
		remove_child(player_car)
		player_car.queue_free()
	var catalog := Game.get_car_catalog()
	if catalog.is_empty():
		push_error("No car data found in res://data/cars")
		return
	index = clampi(index, 0, catalog.size() - 1)
	Game.current_car_index = index
	var data := Game.effective_car_data(index)
	player_car = CarFactory.build(data, Game.get_paint(data.id), true)
	player_car.name = "PlayerCar"
	add_child(player_car)
	(player_car.get_node("Visual") as CarVisuals).add_headlights()
	_attach_optional(player_car)
	var f := -xf.basis.z
	f.y = 0.0
	if f.length() < 0.1:
		f = Vector3(0, 0, -1)
	player_car.place_at(Transform3D(Basis.looking_at(f.normalized(), Vector3.UP), xf.origin + Vector3.UP * (0.5 if had else 0.0)), vel)
	if had and keep_transform:
		_snap_to_ground(player_car, vel)
	if Game.env and Game.env.has_method("is_night"):
		player_car.headlights_on = Game.env.is_night()
	Game.apply_assists_to(player_car)
	Game.player_car = player_car
	car_input.car = player_car
	camera_rig.set_target(player_car)
	Game.car_spawned.emit(player_car)


func _attach_optional(car: CarController) -> void:
	var rw: Node = (load("res://scripts/vehicle/car_rewind.gd") as Script).new()
	rw.name = "CarRewind"
	car.add_child(rw)
	for path: String in [AUDIO_SCRIPT, EFFECTS_SCRIPT]:
		if ResourceLoader.exists(path):
			var n: Node = (load(path) as Script).new()
			n.name = path.get_file().get_basename().to_pascal_case()
			car.add_child(n)


func respawn_on_road() -> void:
	if player_car == null or world == null:
		return
	# During a race / zone keep the car on that event's road.
	if Game.activities != null and Game.activities.has_method("respawn_override"):
		var o: Dictionary = Game.activities.respawn_override(player_car.global_position)
		if not o.is_empty():
			_place_on(o["position"], o["forward"])
			player_car.repair()
			return
	var p: Dictionary = world.nearest_road_point(player_car.global_position)
	var fwd: Vector3 = p["forward"]
	var r: RoadNetwork.Road = null
	if world is World and p.has("road_id"):
		r = (world as World).data.network.get_road(p["road_id"])
	if r == null:
		_place_on(p["position"], fwd)
		player_car.repair()
		return
	# Keep the travel direction closest to the car's current heading.
	var dir := -1 if (-player_car.global_transform.basis.z).dot(fwd) < 0.0 else 1
	# Candidate spots for a standing car, in a gap of the traffic: the nearest point first, then further along
	# the road (and a little back), the outer lane first on multi-lane roads; never inside a junction mouth.
	var s0: float = p["s"]
	var jss: Array[float] = []
	var net := (world as World).data.network
	for jd: Dictionary in net.junctions:
		if String(jd["parent"]) == r.id:
			jss.append(float(jd["parent_index"]) * r.ds)
		elif String(jd["child"]) == r.id:
			jss.append(0.0 if int(jd["child_end"]) == 0 else r.length)
	var spots: Array = []
	for step: float in [0.0, 12.0, 24.0, -12.0, 36.0, 48.0, -24.0, 64.0, 80.0, 100.0, 120.0]:
		var s := s0 + step * dir
		if r.loop:
			s = fposmod(s, r.length)
		elif s < minf(14.0, r.length * 0.5) or s > maxf(r.length - 14.0, r.length * 0.5):
			continue
		var in_junction := false
		for js: float in jss:
			var dj := absf(s - js)
			if r.loop:
				dj = minf(dj, r.length - dj)
			in_junction = in_junction or dj < 25.0
		if step != 0.0 and in_junction:
			continue
		for k in range(r.lanes if r.traffic else 1, 0, -1):
			var lat := r.lane_offset(k) * dir if r.traffic else 0.0
			spots.append([r.surface_point(s, lat), r.flat_tangent_at(s) * dir])
	_place_on(spots[0][0], spots[0][1], spots)
	player_car.repair()


func flip_reset() -> void:
	if player_car == null:
		return
	var f := -player_car.global_transform.basis.z
	f.y = 0.0
	if f.length() < 0.1:
		f = Vector3(0, 0, -1)
	_place_on(player_car.global_position + Vector3.UP * 1.0, f.normalized())


func teleport_to(target: Dictionary) -> void:
	_place_on(target["position"], target.get("forward", Vector3(0, 0, -1)))


## Traffic near the player is solid (physics or kinematic colliders) and keeps moving, so never place the car
## inside a vehicle or in front of one that could not stop for it. With `spots` ([position, forward] pairs, e.g.
## along the road for a respawn) the first safe one is taken. An exact placement (teleport, event respawn) only
## steps forward off a vehicle standing on the spot. When nothing is safe the traffic makes way at the best
## spot. Returns [position, forward].
func _clear_of_traffic(pos: Vector3, f: Vector3, spots: Array = []) -> Array:
	var t: Node = Game.traffic
	if t == null or not t.has_method("spot_margin"):
		return [pos, f]
	if spots.is_empty():
		var p := pos
		for k in 5:
			if float(t.call("spot_margin", p, f, false)) >= 0.0:
				break
			p += f * 9.0
			if world is World:
				p.y = (world as World).ground_at(p.x, p.z, p.y + 6.0)
		if float(t.call("spot_margin", p, f)) < 0.0 and t.has_method("make_way"):
			t.call("make_way", p, f)
		return [p, f]
	var cands: Array = spots
	var best: Array = cands[0]
	var best_m := -INF
	for c: Array in cands:
		var m: float = t.call("spot_margin", c[0], c[1])
		if m >= 0.0:
			return c
		if m > best_m:
			best_m = m
			best = c
	if t.has_method("make_way"):
		t.call("make_way", best[0], best[1])
	return best


func _place_on(pos: Vector3, forward: Vector3, spots: Array = []) -> void:
	var f := Vector3(forward.x, 0, forward.z).normalized()
	if f.length() < 0.1:
		f = Vector3(0, 0, -1)
	var spot := _clear_of_traffic(pos, f, spots)
	pos = spot[0]
	var sf: Vector3 = spot[1]
	sf.y = 0.0
	if sf.length() > 0.1:
		f = sf.normalized()
	var basis := Basis.looking_at(f, Vector3.UP)
	player_car.place_at(Transform3D(basis, Vector3(pos.x, pos.y + 0.45, pos.z)))
	var rw := player_car.get_node_or_null(^"CarRewind")
	if rw != null:
		rw.call(&"clear")
	if world is World:
		(world as World).refocus(player_car.global_position)
	camera_rig.snap()
