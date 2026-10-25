extends Node
## s24 regression: render-pipeline compile bursts after loading. Starts a new game (save ignored in memory),
## measures the loading time and the compilations during loading, then drives the Sunward Ring on autopilot
## and logs every wall-clock frame interval (frame_post_draw to frame_post_draw) above 50 ms with the
## pipeline compilations of that frame.
##   Godot_console.exe --audio-driver Dummy --resolution 1920x1080 --path . res://tools/tests/fix4_ui_pipewarm.tscn
##     -- --start=festival|seabreak|coastfuel [--scenario=drive|rain]
## Prints "[pipewarm] PASS|FAIL ..." and "failures: N".

const OUT := "res://qa_output/fix4_ui/pipewarm"
const STARTS := {"festival": 40.0, "seabreak": 14800.0, "coastfuel": 17550.0}
const DRIVE_M := 430.0
const INFO := [RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_CANVAS, RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_MESH,
	RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_SURFACE, RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_DRAW,
	RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_SPECIALIZATION]

var main: Node
var follower: RoadFollower
var fails := 0
var _t0 := 0
var _last_us := 0
var _last_comp: Array[int] = [0, 0, 0, 0, 0]
var _frames: Array = []
var _recording := false
## The interval after a test screenshot contains its own PNG save: not counted.
var _skip_next := false
var _settings_backup: Dictionary = {}
## Loading frames: [ms, surface+draw compilations].
var _load_frames: Array = []


func _arg(key: String, default: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--%s=" % key):
			return a.get_slice("=", 1)
	return default


func log_line(s: String) -> void:
	print("[pipewarm] ", s)


func check(ok: bool, what: String) -> void:
	log_line(("PASS " if ok else "FAIL ") + what)
	if not ok:
		fails += 1


func _comp() -> Array[int]:
	var out: Array[int] = []
	for k: int in INFO:
		out.append(int(RenderingServer.get_rendering_info(k)))
	return out


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	_settings_backup = Settings.values.duplicate(true)
	SaveGame.enabled = false
	SaveGame.pending = {}
	_t0 = Time.get_ticks_msec()
	_last_comp = _comp()
	log_line("before main: compilations %s" % str(_last_comp))
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(main)
	if OS.get_cmdline_user_args().has("--nowarm"):
		# A/B: the loading screen without the pipeline warm-up viewport.
		var wv: Node = main.get("_warmup")
		if wv != null:
			wv.free()
			main.set("_warmup", null)
		log_line("pipeline warm-up disabled for this run")
	RenderingServer.frame_post_draw.connect(_on_post_draw)
	_run.call_deferred()


func _on_post_draw() -> void:
	var now := Time.get_ticks_usec()
	var c := _comp()
	if main != null and bool(main.get("is_loading")) and _last_us > 0:
		_load_frames.append([(now - _last_us) / 1000.0, c[2] + c[3] - _last_comp[2] - _last_comp[3]])
	if _recording and _last_us > 0 and _skip_next:
		_skip_next = false
	elif _recording and _last_us > 0:
		var d: Array[int] = []
		for i in c.size():
			d.append(c[i] - _last_comp[i])
		var car := Game.player_car
		_frames.append({"ms": (now - _last_us) / 1000.0, "comp": d, "s": follower.s if follower != null else -1.0,
			"pos": car.global_position if car != null else Vector3.ZERO, "kmh": car.get_speed_kmh() if car != null else 0.0})
	_last_us = now
	_last_comp = c


func _physics_process(delta: float) -> void:
	var car := Game.player_car
	if follower != null and car != null and is_instance_valid(car):
		car.in_hold = false
		follower.drive(car, delta)


func _wait(s: float) -> void:
	await get_tree().create_timer(s, true, false, true).timeout


func _settle() -> void:
	var w := Game.world as World
	var t0 := Time.get_ticks_msec()
	while w != null and not w.is_ready_near() and Time.get_ticks_msec() - t0 < 20000:
		await get_tree().process_frame
	await _wait(1.5)


func _shot(n: String) -> void:
	await RenderingServer.frame_post_draw
	_skip_next = true
	get_viewport().get_texture().get_image().save_png(OUT.path_join(n + ".png"))


func _run() -> void:
	var c_start := _comp()
	while main.get("is_loading"):
		await get_tree().process_frame
	var load_ms := Time.get_ticks_msec() - _t0
	var c_load := _comp()
	var dl: Array[int] = []
	for i in c_load.size():
		dl.append(c_load[i] - c_start[i])
	log_line("loading done in %d ms; compilations during loading canvas/mesh/surface/draw/spec = %s" % [load_ms, str(dl)])
	var lf := ""
	var lsum := 0.0
	for f: Array in _load_frames:
		lsum += float(f[0])
		if float(f[0]) > 40.0 or int(f[1]) > 0:
			lf += " %.0fms/%dc" % [f[0], f[1]]
	log_line("loading frames %d (%.0f ms after the first frame); long or compiling ones (ms/compilations):%s" % [_load_frames.size(), lsum, lf])
	if Game.traffic != null and Game.traffic.has_method("set_density"):
		Game.traffic.call("set_density", 0.0)
	var start := _arg("start", "festival")
	var scenario := _arg("scenario", "drive")
	var ring: RoadNetwork.Road = (Game.world as World).data.network.get_road("ring")
	var s0: float = STARTS.get(start, 40.0)
	if scenario == "features":
		# Runtime features that could switch on a global pipeline variant: weather, SSR, night lights.
		await _settle()
		var env_res: Environment = Game.env.get("environment") if Game.env != null else null
		for step: Array in [["rain", 13.0, "rain"], ["ssr", 13.0, "ssr"], ["fog", 13.0, "fog"], ["night", 23.0, "clear"], ["storm", 23.0, "storm"]]:
			_frames.clear()
			_recording = true
			Game.set_time_of_day(step[1])
			if step[2] == "ssr":
				if env_res != null:
					env_res.ssr_enabled = true
			else:
				Game.set_weather(step[2], true)
			await _wait(6.0)
			_recording = false
			log_line("%s: ssr %s vol fog %s" % [step[0], str(env_res.ssr_enabled if env_res else false), str(env_res.volumetric_fog_enabled if env_res else false)])
			_report("feature %s" % step[0], 100.0)
		_finish()
		return
	follower = RoadFollower.new()
	follower.setup(ring, s0, 1, ring.lane_offset(1))
	follower.respect_traffic = false
	follower.target_speed = 98.0 / 3.6
	if start != "festival":
		follower = null
		Game.main.teleport_to({"position": ring.surface_point(s0, ring.lane_offset(1)), "forward": ring.flat_tangent_at(s0)})
		await _settle()
		follower = RoadFollower.new()
		follower.setup(ring, s0, 1, ring.lane_offset(1))
		follower.respect_traffic = false
		follower.target_speed = 98.0 / 3.6
	else:
		await _wait(0.5)
	_recording = true
	var t := 0.0
	var shot_done := false
	while follower.s < s0 + DRIVE_M and t < 45.0:
		await get_tree().process_frame
		t += get_process_delta_time()
		if not shot_done and follower.s > s0 + 306.0:
			shot_done = true
			await _shot("%s_s%d" % [start, int(follower.s)])
	_recording = false
	follower = null
	_report("%s s %.0f..%.0f" % [start, s0, s0 + DRIVE_M], 100.0)
	_finish()


func _report(what: String, limit_ms: float) -> void:
	var ms: Array[float] = []
	var long: Array[String] = []
	var total := [0, 0, 0, 0, 0]
	for f: Dictionary in _frames:
		ms.append(float(f["ms"]))
		var d: Array = f["comp"]
		for i in d.size():
			total[i] += int(d[i])
		if float(f["ms"]) > 50.0 or int(d[2]) + int(d[3]) > 4:
			long.append("%.0f ms @ s=%.0f %s %.0f km/h comp=%s" % [f["ms"], f["s"], str((f["pos"] as Vector3).round()), f["kmh"], str(d)])
	ms.sort()
	var n := ms.size()
	var worst := ms[n - 1] if n > 0 else 0.0
	log_line("%s: frames %d median %.1f ms p99 %.1f ms max %.1f ms; compilations canvas/mesh/surface/draw/spec = %s" % [what, n,
		ms[n / 2] if n > 0 else 0.0, ms[int(n * 0.99)] if n > 0 else 0.0, worst, str(total)])
	for l in long:
		log_line("  slow/compiling frame: " + l)
	check(int(total[2]) + int(total[3]) <= 8, "%s: at most 8 surface/draw pipeline compilations after loading (%d)" % [what, int(total[2]) + int(total[3])])
	check(worst < limit_ms, "%s: worst wall-clock frame %.1f ms < %.0f ms" % [what, worst, limit_ms])


func _finish() -> void:
	Settings.values = _settings_backup
	log_line("failures: %d" % fails)
	get_tree().quit(0 if fails == 0 else 1)
