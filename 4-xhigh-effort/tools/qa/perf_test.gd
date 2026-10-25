extends Node
## Windowed performance / soak run: autopilot along the scenic loop with traffic, sampling frame
## times, draw calls, primitives, memory, node/object counts and streamer stats. Compares the first
## and last minute to detect leaks and reports falls (car below the terrain) and resets.
##   godot --path . -- --qa=perf_test --fresh --secs=600 [--cap=170]

var secs := 600.0
var cap := 170.0
var t := 0.0
var frames := PackedFloat32Array()
var samples: Array = []
var _next := 0.0
var falls := 0
var start_pos := Vector3.ZERO
var dist := 0.0
var _last := Vector3.ZERO
var max_kmh := 0.0
var hist0 := {}


func _ready() -> void:
	secs = float(Game.main.arg("secs", "600"))
	cap = float(Game.main.arg("cap", "170"))
	Game.main.driver.car = null
	Game.main.teleport_to(Game.main.find_place(String(Game.main.arg("start", "road:loop:0.01"))))
	start_pos = Game.player.global_position
	_last = start_pos


func _sample() -> Dictionary:
	var ts: Dictionary = Game.world.get("terrain").get("stats") if Game.world.get("terrain") != null else {}
	return {"t": snappedf(t, 1.0), "mem_mb": snappedf(OS.get_static_memory_usage() / 1048576.0, 0.1),
		"nodes": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		"objects": int(Performance.get_monitor(Performance.OBJECT_COUNT)),
		"draw_calls": int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		"primitives": int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)),
		"vram_mb": snappedf(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0, 0.1),
		"traffic": Game.traffic.active.size() if Game.traffic != null else 0, "terrain": ts,
		"pos": Game.player.global_position.snapped(Vector3.ONE * 10.0), "kmh": roundi(Game.player.speed_abs * 3.6)}


func _histogram() -> Dictionary:
	var h := {}
	var stack: Array[Node] = [get_tree().root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		var k := n.get_class() + ":" + String(n.get_parent().name if n.get_parent() != null else "")
		h[k] = int(h.get(k, 0)) + 1
		stack.append_array(n.get_children())
	return h


func _process(delta: float) -> void:
	t += delta
	if t > 3.0:
		frames.append(delta)
	if t >= _next:
		_next += 30.0
		samples.append(_sample())
		if samples.size() == 2:
			hist0 = _histogram()
		if Game.main.arg("verbose") != "":
			print("  ", samples[-1].t, " ", samples[-1].pos, " ", samples[-1].kmh, " km/h nodes ", samples[-1].nodes)
	if t >= secs:
		_report()


func _physics_process(_d: float) -> void:
	var car := Game.player
	if car == null:
		return
	car.in_steer = Game.world.autopilot_steer(car)
	var ped: Vector2 = Game.world.autopilot_pedals(car, cap)
	car.in_throttle = ped.x
	car.in_brake = ped.y
	car.in_handbrake = false
	var p := car.global_position
	dist += Vector2(p.x - _last.x, p.z - _last.z).length()
	_last = p
	max_kmh = maxf(max_kmh, car.speed_abs * 3.6)
	if p.y < Game.world.height_at(p.x, p.z) - 3.0:
		falls += 1
		Game.reset_player_to_road()


func _report() -> void:
	set_process(false)
	var s := frames.duplicate()
	s.sort()
	var n := s.size()
	var sum := 0.0
	for v in s:
		sum += v
	var pct := func(q: float) -> float: return s[clampi(int(n * q), 0, n - 1)] * 1000.0
	var over_33 := 0
	var over_50 := 0
	for v in s:
		if v > 1.0 / 30.0:
			over_33 += 1
		if v > 0.05:
			over_50 += 1
	var first: Dictionary = samples[1] if samples.size() > 1 else samples[0]
	var last: Dictionary = samples[-1]
	var r := {"secs": secs, "distance_km": snappedf(dist / 1000.0, 0.01), "max_kmh": roundi(max_kmh), "falls": falls,
		"fps_avg": snappedf(n / sum, 0.1), "ms_avg": snappedf(sum / n * 1000.0, 0.01), "ms_p50": snappedf(pct.call(0.5), 0.01),
		"ms_p95": snappedf(pct.call(0.95), 0.01), "ms_p99": snappedf(pct.call(0.99), 0.01), "ms_max": snappedf(s[n - 1] * 1000.0, 0.01),
		"frames_over_33ms": over_33, "frames_over_50ms": over_50, "frames": n,
		"resolution": str(DisplayServer.window_get_size()), "first": first, "last": last,
		"mem_growth_mb": snappedf(float(last.mem_mb) - float(first.mem_mb), 0.1), "node_growth": int(last.nodes) - int(first.nodes)}
	DirAccess.make_dir_recursive_absolute("res://qa/results")
	var ws := DisplayServer.window_get_size()
	var f := FileAccess.open("res://qa/results/perf_%dx%d_%ds.json" % [ws.x, ws.y, int(secs)], FileAccess.WRITE)
	f.store_string(JSON.stringify({"summary": r, "samples": samples}, "  "))
	f.close()
	print("PERF_TEST ", JSON.stringify(r))
	var h1 := _histogram()
	var deltas := []
	for k: String in h1:
		var d := int(h1[k]) - int(hist0.get(k, 0))
		if absi(d) >= 5:
			deltas.append([d, k])
	deltas.sort_custom(func(a: Array, b: Array) -> bool: return absi(a[0]) > absi(b[0]))
	print("NODE_DELTAS ", deltas.slice(0, 15))
	get_tree().quit(0)
