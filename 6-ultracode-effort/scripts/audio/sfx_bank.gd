extends RefCounted
## Procedurally synthesised sound samples (no audio files): tyres, wind, body hits, turbo, horn,
## ambient beds and animal calls, plus baked engine loops for traffic. Samples are generated on a
## WorkerThreadPool task (prefetch + poll) or synchronously (get_sample) and cached for the session.
## Also owns the Engine / Effects / Ambient buses, their Settings volumes and the tunnel reverb.

const EngineSynth := preload("res://scripts/audio/engine_synth.gd")

const RATE := 32000
const BED_RATE := 22050
const BUS_ENGINE := &"Engine"
const BUS_EFFECTS := &"Effects"
const BUS_AMBIENT := &"Ambient"

const CAR_IDS: Array[StringName] = [&"squeal", &"scrub", &"gravel", &"soft", &"wind", &"rain_roof",
	&"thump_a", &"thump_b", &"impact_light", &"impact_medium", &"impact_heavy", &"shift", &"blowoff",
	&"flutter", &"horn"]
const AMBIENT_IDS: Array[StringName] = [&"bed_vale", &"bed_highlands", &"bed_mesa", &"bed_coast",
	&"rain", &"storm", &"crickets", &"cicadas", &"gust", &"bird_0", &"bird_1", &"bird_2", &"bird_3",
	&"gull_0", &"gull_1", &"owl", &"thunder_near", &"thunder_far"]

static var _cache: Dictionary = {}
static var _queue: Array = []
static var _inflight: Dictionary = {}
static var _task: int = -1
static var _task_out: Dictionary = {}
## Total generation time in ms (diagnostics).
static var gen_msec: float = 0.0


# ------------------------------------------------------------------ cache / background generation

static func peek(id: StringName) -> AudioStreamWAV:
	return _cache.get(id) as AudioStreamWAV


## Blocking: generates the sample now if it is not cached yet.
static func get_sample(id: StringName) -> AudioStreamWAV:
	var s := peek(id)
	if s == null:
		var enc := _encode(_generate(id, null))
		s = _wav(enc)
		gen_msec += float(enc["ms"])
		_cache[id] = s
	return s


static func prefetch(ids: Array[StringName]) -> void:
	for id in ids:
		if not _cache.has(id) and not _inflight.has(id):
			_inflight[id] = true
			_queue.append([id, null])
	poll()


## Queues a baked, loopable engine sample for a (non-player) car and returns its cache key.
static func request_engine_loop(data: CarData) -> StringName:
	var key := engine_key(data)
	if not _cache.has(key) and not _inflight.has(key):
		_inflight[key] = true
		_queue.append([key, data])
	poll()
	return key


static func engine_key(data: CarData) -> StringName:
	var tag := data.id if data.id != "" else "c%d_%d" % [data.cylinders, int(data.engine_pitch * 100.0)]
	return StringName("engine:" + tag)


## Call every frame from audio nodes: merges finished work and starts the next batch.
static func poll() -> void:
	if _task >= 0:
		if not WorkerThreadPool.is_task_completed(_task):
			return
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
		for id: StringName in _task_out:
			var enc: Dictionary = _task_out[id]
			_cache[id] = _wav(enc)
			gen_msec += float(enc["ms"])
			_inflight.erase(id)
		_task_out = {}
	if _queue.is_empty():
		return
	var jobs := _queue.duplicate()
	_queue.clear()
	var out := {}
	_task_out = out
	_task = WorkerThreadPool.add_task(func() -> void:
		for j: Array in jobs:
			out[j[0]] = _encode(_generate(j[0], j[1]))
	, false, "sfx_bank")


static func is_busy() -> bool:
	return _task >= 0 or not _queue.is_empty()


static func shutdown() -> void:
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
		_task_out = {}
		_inflight.clear()


# ------------------------------------------------------------------ buses / volumes / reverb

static func ensure_buses() -> void:
	for b: StringName in [BUS_ENGINE, BUS_EFFECTS, BUS_AMBIENT]:
		if AudioServer.get_bus_index(b) < 0:
			var idx := AudioServer.bus_count
			AudioServer.add_bus(idx)
			AudioServer.set_bus_name(idx, b)
			AudioServer.set_bus_send(idx, &"Master")
	for b: StringName in [BUS_ENGINE, BUS_EFFECTS]:
		var idx := AudioServer.get_bus_index(b)
		if _find_effect(idx, "AudioEffectReverb") < 0:
			var rv := AudioEffectReverb.new()
			rv.room_size = 0.72
			rv.damping = 0.35
			rv.spread = 0.85
			rv.hipass = 0.12
			rv.predelay_msec = 35.0
			rv.predelay_feedback = 0.25
			rv.dry = 1.0
			rv.wet = 0.0
			AudioServer.add_bus_effect(idx, rv)
			AudioServer.set_bus_effect_enabled(idx, AudioServer.get_bus_effect_count(idx) - 1, false)
	var master := AudioServer.get_bus_index(&"Master")
	if master >= 0 and _find_effect(master, "AudioEffectHardLimiter") < 0 and _find_effect(master, "AudioEffectLimiter") < 0:
		var lim := AudioEffectHardLimiter.new()
		lim.ceiling_db = -0.5
		AudioServer.add_bus_effect(master, lim)
	apply_volumes()


static func _find_effect(bus: int, cls: String) -> int:
	if bus < 0:
		return -1
	for i in AudioServer.get_bus_effect_count(bus):
		if AudioServer.get_bus_effect(bus, i).get_class() == cls:
			return i
	return -1


static func apply_volumes() -> void:
	_set_bus(&"Master", float(Settings.get_value("volume_master", 0.85)))
	_set_bus(BUS_ENGINE, float(Settings.get_value("volume_engine", 1.0)))
	_set_bus(BUS_EFFECTS, float(Settings.get_value("volume_effects", 0.9)))
	_set_bus(BUS_AMBIENT, float(Settings.get_value("volume_ambient", 0.7)))


static func _set_bus(bus_name: StringName, v: float) -> void:
	var i := AudioServer.get_bus_index(bus_name)
	if i < 0:
		return
	AudioServer.set_bus_volume_db(i, linear_to_db(clampf(v, 0.0001, 2.0)))
	AudioServer.set_bus_mute(i, v <= 0.001 or (i == 0 and Settings.test_run))


## 0..1 tunnel reverb on the car buses.
static func set_tunnel_reverb(amount: float) -> void:
	for b: StringName in [BUS_ENGINE, BUS_EFFECTS]:
		var idx := AudioServer.get_bus_index(b)
		var e := _find_effect(idx, "AudioEffectReverb")
		if e < 0:
			continue
		var rv := AudioServer.get_bus_effect(idx, e) as AudioEffectReverb
		rv.wet = 0.42 * amount
		rv.dry = 1.0 - 0.15 * amount
		AudioServer.set_bus_effect_enabled(idx, e, amount > 0.005)


static func tunnel_at(pos: Vector3) -> bool:
	if not (Game.world is World):
		return false
	var w := Game.world as World
	if w.data == null:
		return false
	var res := w.data.network.nearest(pos, 30.0)
	if res.is_empty():
		return false
	var r: RoadNetwork.Road = res["road"]
	if (r.flag_at(float(res["s"])) & 2) == 0:
		return false
	var c: Vector3 = res["position"]
	return absf(float(res["lateral"])) < r.width * 0.5 + 5.0 and pos.y < c.y + 9.0 and pos.y > c.y - 4.0


# ------------------------------------------------------------------ encoding

static func _encode(d: Dictionary) -> Dictionary:
	var t0 := Time.get_ticks_usec()
	var l: PackedFloat32Array = d["l"]
	var r: PackedFloat32Array = d.get("r", PackedFloat32Array())
	var stereo := r.size() == l.size() and r.size() > 0
	var n := l.size()
	var bytes := PackedByteArray()
	bytes.resize(n * (4 if stereo else 2))
	if stereo:
		for i in n:
			bytes.encode_s16(i * 4, int(clampf(l[i], -1.0, 1.0) * 32767.0))
			bytes.encode_s16(i * 4 + 2, int(clampf(r[i], -1.0, 1.0) * 32767.0))
	else:
		for i in n:
			bytes.encode_s16(i * 2, int(clampf(l[i], -1.0, 1.0) * 32767.0))
	var ms := float(d.get("ms", 0.0)) + (Time.get_ticks_usec() - t0) / 1000.0
	return {"bytes": bytes, "rate": int(d["rate"]), "stereo": stereo, "loop": bool(d["loop"]), "frames": n,
		"meta": d.get("meta", {}), "ms": ms}


static func _wav(enc: Dictionary) -> AudioStreamWAV:
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = int(enc["rate"])
	w.stereo = bool(enc["stereo"])
	w.data = enc["bytes"]
	if bool(enc["loop"]):
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = int(enc["frames"])
	var meta: Dictionary = enc["meta"]
	for k: String in meta:
		w.set_meta(k, meta[k])
	return w


## Returns {l, r (optional), rate, loop, meta, ms} with float samples in -1..1.
static func _generate(id: StringName, data: CarData) -> Dictionary:
	var t0 := Time.get_ticks_usec()
	var d: Dictionary
	if String(id).begins_with("engine:"):
		d = _engine_loop(data)
	else:
		match id:
			&"squeal": d = _squeal()
			&"scrub": d = _scrub()
			&"gravel": d = _gravel()
			&"soft": d = _soft()
			&"wind": d = _wind()
			&"rain_roof": d = _rain_roof()
			&"thump_a": d = _thump(58.0, 3)
			&"thump_b": d = _thump(74.0, 4)
			&"impact_light": d = _impact(0.3, 21)
			&"impact_medium": d = _impact(0.65, 22)
			&"impact_heavy": d = _impact(1.0, 23)
			&"shift": d = _shift()
			&"blowoff": d = _blowoff()
			&"flutter": d = _flutter()
			&"horn": d = _horn()
			&"bed_vale": d = _bed_vale()
			&"bed_highlands": d = _bed_highlands()
			&"bed_mesa": d = _bed_mesa()
			&"bed_coast": d = _bed_coast()
			&"rain": d = _rain(false)
			&"storm": d = _rain(true)
			&"crickets": d = _crickets()
			&"cicadas": d = _cicadas()
			&"gust": d = _gust()
			&"bird_0", &"bird_1", &"bird_2", &"bird_3": d = _bird(String(id).right(1).to_int())
			&"gull_0", &"gull_1": d = _gull(String(id).right(1).to_int())
			&"owl": d = _owl()
			&"thunder_near": d = _thunder(true)
			&"thunder_far": d = _thunder(false)
			_:
				push_warning("SfxBank: unknown sample %s" % id)
				d = {"l": PackedFloat32Array([0.0, 0.0]), "rate": RATE, "loop": false}
	d["ms"] = (Time.get_ticks_usec() - t0) / 1000.0
	return d


# ------------------------------------------------------------------ DSP helpers

static func _noise(n: int, seed: int) -> PackedFloat32Array:
	var b := PackedFloat32Array()
	b.resize(n)
	var s := (seed * 7919 + 17) & 0x7FFFFFFF
	for i in n:
		s = (s * 1103515245 + 12345) & 0x7FFFFFFF
		b[i] = float(s) / 1073741824.0 - 1.0
	return b


## Smooth random curve in -1..1 (cosine interpolation between random points `hz` times a second).
static func _smooth(n: int, hz: float, seed: int, rate: int) -> PackedFloat32Array:
	var step := maxf(float(rate) / hz, 2.0)
	var pts := _noise(int(n / step) + 3, seed + 101)
	var b := PackedFloat32Array()
	b.resize(n)
	for i in n:
		var f := i / step
		var j := int(f)
		var t := 0.5 - 0.5 * cos(PI * (f - j))
		b[i] = lerpf(pts[j], pts[j + 1], t)
	return b


static func _lp(b: PackedFloat32Array, fc: float, rate: int) -> PackedFloat32Array:
	var k := 1.0 - exp(-TAU * fc / rate)
	var y := 0.0
	for i in b.size():
		y += (b[i] - y) * k
		b[i] = y
	return b


static func _hp(b: PackedFloat32Array, fc: float, rate: int) -> PackedFloat32Array:
	var k := 1.0 - exp(-TAU * fc / rate)
	var y := 0.0
	for i in b.size():
		y += (b[i] - y) * k
		b[i] = b[i] - y
	return b


## RBJ band-pass (0 dB peak).
static func _bp(b: PackedFloat32Array, fc: float, q: float, rate: int) -> PackedFloat32Array:
	var w0 := TAU * fc / rate
	var alpha := sin(w0) / (2.0 * q)
	var a0 := 1.0 + alpha
	var b0 := alpha / a0
	var a1 := -2.0 * cos(w0) / a0
	var a2 := (1.0 - alpha) / a0
	var x1 := 0.0
	var x2 := 0.0
	var y1 := 0.0
	var y2 := 0.0
	for i in b.size():
		var x := b[i]
		var y := b0 * (x - x2) - a1 * y1 - a2 * y2
		x2 = x1
		x1 = x
		y2 = y1
		y1 = y
		b[i] = y
	return b


## Normalised 2-pole resonator (rings at f with quality q).
static func _reso(b: PackedFloat32Array, f: float, q: float, rate: int) -> PackedFloat32Array:
	var w := TAU * f / rate
	var r := exp(-PI * (f / q) / rate)
	var a1 := 2.0 * r * cos(w)
	var a2 := r * r
	var g := (1.0 - r) * sqrt(1.0 + r * r - 2.0 * r * cos(2.0 * w))
	var y1 := 0.0
	var y2 := 0.0
	for i in b.size():
		var y := a1 * y1 - a2 * y2 + b[i] * g
		y2 = y1
		y1 = y
		b[i] = y
	return b


## Chamberlin state-variable filter with a per-sample cutoff (Hz). mode 0 = low-pass, 1 = band-pass.
static func _svf(b: PackedFloat32Array, cut: PackedFloat32Array, q: float, mode: int, rate: int) -> PackedFloat32Array:
	var low := 0.0
	var band := 0.0
	var damp := 1.0 / q
	# Stable while f^2 + 2*f*damp < 4.
	var fmax := (sqrt(damp * damp + 4.0) - damp) * 0.9
	for i in b.size():
		var f := minf(2.0 * sin(PI * minf(cut[i], rate * 0.25) / rate), fmax)
		low += f * band
		var high := b[i] - low - damp * band
		band += f * high
		b[i] = low if mode == 0 else band
	return b


## Decaying impulse train envelope: `density` hits per second, each decaying with `decay` seconds.
static func _spikes(n: int, density: float, decay: float, seed: int, rate: int, shape := 2.0) -> PackedFloat32Array:
	var b := PackedFloat32Array()
	b.resize(n)
	var k := exp(-1.0 / (decay * rate))
	var p := density / rate
	var s := (seed * 48271 + 11) & 0x7FFFFFFF
	var e := 0.0
	for i in n:
		s = (s * 1103515245 + 12345) & 0x7FFFFFFF
		if float(s) / 2147483648.0 < p:
			s = (s * 1103515245 + 12345) & 0x7FFFFFFF
			e += pow(float(s) / 2147483648.0, shape)
		e *= k
		b[i] = e
	return b


static func _mul(a: PackedFloat32Array, b: PackedFloat32Array) -> PackedFloat32Array:
	for i in a.size():
		a[i] *= b[i]
	return a


static func _add(a: PackedFloat32Array, b: PackedFloat32Array, g: float) -> PackedFloat32Array:
	for i in a.size():
		a[i] += b[i] * g
	return a


static func _scale(a: PackedFloat32Array, g: float) -> PackedFloat32Array:
	for i in a.size():
		a[i] *= g
	return a


static func _peak(a: PackedFloat32Array) -> float:
	var m := 0.0
	for v: float in a:
		m = maxf(m, absf(v))
	return m


static func _normalize(a: PackedFloat32Array, peak: float) -> PackedFloat32Array:
	var m := _peak(a)
	return _scale(a, peak / m) if m > 1e-6 else a


static func _normalize2(l: PackedFloat32Array, r: PackedFloat32Array, peak: float) -> void:
	var m := maxf(_peak(l), _peak(r))
	if m > 1e-6:
		_scale(l, peak / m)
		_scale(r, peak / m)


## Folds the last `xf` samples over the start so the loop point is seamless (equal-power for noise).
static func _loopify(b: PackedFloat32Array, xf: int) -> PackedFloat32Array:
	var n := b.size() - xf
	for i in xf:
		var t := float(i) / xf
		b[i] = b[i] * sqrt(t) + b[n + i] * sqrt(1.0 - t)
	b.resize(n)
	return b


static func _attack_decay(n: int, attack: float, decay: float, rate: int) -> PackedFloat32Array:
	var b := PackedFloat32Array()
	b.resize(n)
	for i in n:
		var t := float(i) / rate
		b[i] = (1.0 - exp(-t / attack)) * exp(-t / decay)
	return b


static func _const(n: int, v: float) -> PackedFloat32Array:
	var b := PackedFloat32Array()
	b.resize(n)
	b.fill(v)
	return b


static func _mono(l: PackedFloat32Array, rate: int, loop: bool) -> Dictionary:
	return {"l": l, "rate": rate, "loop": loop}


static func _stereo(l: PackedFloat32Array, r: PackedFloat32Array, rate: int, loop: bool) -> Dictionary:
	return {"l": l, "r": r, "rate": rate, "loop": loop}


# ------------------------------------------------------------------ car samples

static func _squeal() -> Dictionary:
	var xf := int(0.25 * RATE)
	var n := int(1.6 * RATE) + xf
	var fm := _smooth(n, 6.0, 11, RATE)
	var fj := _smooth(n, 37.0, 12, RATE)
	var am := _smooth(n, 21.0, 13, RATE)
	var nz := _bp(_noise(n, 14), 2300.0, 1.4, RATE)
	var b := PackedFloat32Array()
	b.resize(n)
	var p1 := 0.0
	var p2 := 0.0
	for i in n:
		var f := 1020.0 * (1.0 + 0.035 * fm[i] + 0.01 * fj[i])
		p1 += f / RATE
		p1 -= floorf(p1)
		p2 += f * 1.068 / RATE
		p2 -= floorf(p2)
		var s := sin(TAU * p1) + 0.3 * sin(TAU * 2.0 * p1) + 0.1 * sin(TAU * 3.0 * p1)
		s += 0.55 * (sin(TAU * p2) + 0.22 * sin(TAU * 2.0 * p2))
		b[i] = s * (0.68 + 0.32 * am[i]) + nz[i] * 1.1
	b = _hp(b, 380.0, RATE)
	return _mono(_normalize(_loopify(b, xf), 0.85), RATE, true)


static func _scrub() -> Dictionary:
	var xf := int(0.2 * RATE)
	var n := int(1.4 * RATE) + xf
	var fm := _smooth(n, 9.0, 31, RATE)
	var am := _smooth(n, 29.0, 32, RATE)
	var b := _bp(_noise(n, 33), 760.0, 1.2, RATE)
	var p := 0.0
	for i in n:
		p += 575.0 * (1.0 + 0.07 * fm[i]) / RATE
		p -= floorf(p)
		b[i] = (b[i] * 2.2 + 0.32 * sin(TAU * p)) * (0.6 + 0.4 * am[i])
	b = _hp(b, 180.0, RATE)
	return _mono(_normalize(_loopify(b, xf), 0.85), RATE, true)


static func _gravel() -> Dictionary:
	var xf := int(0.25 * RATE)
	var n := int(2.0 * RATE) + xf
	var fine := _bp(_mul(_noise(n, 41), _spikes(n, 1300.0, 0.0016, 42, RATE)), 3600.0, 0.7, RATE)
	var coarse := _bp(_mul(_noise(n, 43), _spikes(n, 120.0, 0.006, 44, RATE)), 1250.0, 1.0, RATE)
	var rumble := _lp(_lp(_noise(n, 45), 150.0, RATE), 150.0, RATE)
	var am := _smooth(n, 3.0, 46, RATE)
	var b := PackedFloat32Array()
	b.resize(n)
	for i in n:
		b[i] = fine[i] * 1.6 + coarse[i] * 2.4 + rumble[i] * 9.0 * (0.75 + 0.25 * am[i])
	return _mono(_normalize(_loopify(b, xf), 0.85), RATE, true)


static func _soft() -> Dictionary:
	var xf := int(0.25 * RATE)
	var n := int(2.0 * RATE) + xf
	var swish := _bp(_noise(n, 51), 1500.0, 0.6, RATE)
	var body := _lp(_lp(_noise(n, 52), 320.0, RATE), 320.0, RATE)
	var sub := _lp(_lp(_noise(n, 53), 70.0, RATE), 70.0, RATE)
	var am := _smooth(n, 2.5, 54, RATE)
	var b := PackedFloat32Array()
	b.resize(n)
	for i in n:
		b[i] = swish[i] * 0.5 * (0.55 + 0.45 * am[i]) + body[i] * 3.0 + sub[i] * 9.0
	return _mono(_normalize(_loopify(b, xf), 0.8), RATE, true)


static func _wind() -> Dictionary:
	var xf := int(0.3 * RATE)
	var n := int(3.0 * RATE) + xf
	var broad := _bp(_noise(n, 61), 650.0, 0.6, RATE)
	var low := _lp(_lp(_noise(n, 62), 170.0, RATE), 170.0, RATE)
	var whistle := _bp(_noise(n, 63), 1500.0, 9.0, RATE)
	var am := _smooth(n, 1.3, 64, RATE)
	var b := PackedFloat32Array()
	b.resize(n)
	for i in n:
		b[i] = (broad[i] * 0.8 + low[i] * 5.0 + whistle[i] * 0.6) * (0.75 + 0.25 * am[i])
	return _mono(_normalize(_loopify(b, xf), 0.8), RATE, true)


static func _rain_roof() -> Dictionary:
	var xf := int(0.25 * RATE)
	var n := int(2.5 * RATE) + xf
	var ticks := _hp(_mul(_noise(n, 71), _spikes(n, 450.0, 0.0012, 72, RATE, 3.0)), 1500.0, RATE)
	var sparse := _spikes(n, 55.0, 0.0006, 73, RATE, 2.0)
	var plink := _reso(sparse.duplicate(), 2600.0, 18.0, RATE)
	_add(plink, _reso(sparse.duplicate(), 3900.0, 22.0, RATE), 0.8)
	var drum := _lp(_spikes(n, 160.0, 0.004, 74, RATE, 2.0), 260.0, RATE)
	var hiss := _hp(_lp(_noise(n, 75), 5000.0, RATE), 800.0, RATE)
	var b := PackedFloat32Array()
	b.resize(n)
	for i in n:
		b[i] = ticks[i] * 1.0 + plink[i] * 6.0 + drum[i] * 2.5 + hiss[i] * 0.12
	b = _hp(b, 60.0, RATE)
	return _mono(_normalize(_loopify(b, xf), 0.8), RATE, true)


static func _thump(f0: float, seed: int) -> Dictionary:
	var n := int(0.4 * RATE)
	var b := PackedFloat32Array()
	b.resize(n)
	var ph := 0.0
	for i in n:
		var t := float(i) / RATE
		ph += f0 * (1.0 + 0.8 * exp(-t / 0.02)) / RATE
		b[i] = sin(TAU * ph) * (1.0 - exp(-t / 0.002)) * exp(-t / 0.075)
	var burst := _mul(_noise(n, seed), _attack_decay(n, 0.0003, 0.004, RATE))
	_add(b, _lp(burst.duplicate(), 2500.0, RATE), 0.9)
	var hit := _mul(_noise(n, seed + 9), _attack_decay(n, 0.0003, 0.01, RATE))
	_add(b, _reso(hit.duplicate(), 820.0, 14.0, RATE), 1.6)
	_add(b, _reso(hit, 1430.0, 18.0, RATE), 1.0)
	return _mono(_normalize(b, 0.9), RATE, false)


static func _impact(k: float, seed: int) -> Dictionary:
	var dur := 0.6 + 0.8 * k
	var n := int(dur * RATE)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var b := PackedFloat32Array()
	b.resize(n)
	var ph := 0.0
	var thud_decay := 0.08 + 0.12 * k
	for i in n:
		var t := float(i) / RATE
		ph += 62.0 * (1.0 + exp(-t / 0.03)) / RATE
		b[i] = sin(TAU * ph) * (1.0 - exp(-t / 0.001)) * exp(-t / thud_decay)
	var crunch := _lp(_mul(_noise(n, seed), _attack_decay(n, 0.0005, 0.03 + 0.1 * k, RATE)), 1200.0 + 3000.0 * k, RATE)
	_add(b, crunch, 0.9 + 0.6 * k)
	var burst := _mul(_noise(n, seed + 1), _attack_decay(n, 0.0002, 0.006, RATE))
	for f: float in [287.0, 613.0, 1180.0, 1950.0, 2870.0]:
		var ff := f * rng.randf_range(0.93, 1.07)
		_add(b, _reso(burst.duplicate(), ff, rng.randf_range(25.0, 45.0), RATE), (0.6 + 1.6 * k) * 2.0)
	if k > 0.5:
		var dn := _spikes(n, 22.0 * k, 0.0008, seed + 2, RATE, 1.5)
		for i in n:
			var t := float(i) / RATE
			if t < 0.05 or t > dur * 0.8:
				dn[i] = 0.0
		var glass := _reso(dn.duplicate(), 3300.0, 50.0, RATE)
		_add(glass, _reso(dn.duplicate(), 4700.0, 55.0, RATE), 1.0)
		_add(glass, _reso(dn, 6100.0, 60.0, RATE), 0.8)
		_add(b, glass, 12.0 * k)
	return _mono(_normalize(b, 0.92), RATE, false)


static func _shift() -> Dictionary:
	var n := int(0.22 * RATE)
	var b := PackedFloat32Array()
	b.resize(n)
	for i in n:
		var t := float(i) / RATE
		b[i] = sin(TAU * 115.0 * t) * (1.0 - exp(-t / 0.001)) * exp(-t / 0.025)
	var click := _bp(_mul(_noise(n, 81), _attack_decay(n, 0.0002, 0.003, RATE)), 2800.0, 1.2, RATE)
	_add(b, click, 2.0)
	var ring := _reso(_mul(_noise(n, 82), _attack_decay(n, 0.0001, 0.002, RATE)), 1650.0, 35.0, RATE)
	_add(b, ring, 3.0)
	return _mono(_normalize(b, 0.9), RATE, false)


static func _blowoff() -> Dictionary:
	var n := int(0.75 * RATE)
	var env := _attack_decay(n, 0.006, 0.2, RATE)
	var src := _mul(_noise(n, 91), env)
	var cut := PackedFloat32Array()
	cut.resize(n)
	for i in n:
		cut[i] = 900.0 + 3300.0 * exp(-float(i) / RATE / 0.3)
	var b := _svf(src.duplicate(), cut, 1.4, 1, RATE)
	_add(b, _hp(src, 5000.0, RATE), 0.15)
	return _mono(_normalize(b, 0.85), RATE, false)


static func _flutter() -> Dictionary:
	var n := int(0.9 * RATE)
	var env := _attack_decay(n, 0.004, 0.28, RATE)
	var low := _lp(_noise(n, 95), 1100.0, RATE)
	var mid := _bp(_noise(n, 96), 2200.0, 1.0, RATE)
	var b := PackedFloat32Array()
	b.resize(n)
	var ph := 0.0
	for i in n:
		var t := float(i) / RATE
		ph += lerpf(24.0, 13.0, minf(t / 0.8, 1.0)) / RATE
		var chop := pow(0.5 + 0.5 * cos(TAU * ph), 3.0)
		b[i] = (low[i] * 2.0 + mid[i] * 0.5) * chop * env[i]
	return _mono(_normalize(b, 0.85), RATE, false)


## Two-tone horn; 410 Hz and 512 Hz (and the 6 Hz vibrato) complete whole cycles in 0.5 s, so it loops exactly.
static func _horn() -> Dictionary:
	var n := int(RATE * 0.5)
	var total := n * 2
	var b := PackedFloat32Array()
	b.resize(total)
	var p1 := 0.0
	var p2 := 0.0
	for i in total:
		var t := float(i) / RATE
		var vib := 1.0 + 0.003 * sin(TAU * 6.0 * t)
		p1 += 410.0 * vib / RATE
		p1 -= floorf(p1)
		p2 += 512.0 * vib / RATE
		p2 -= floorf(p2)
		var s := 0.0
		for h in range(1, 8):
			s += (sin(TAU * h * p1) + sin(TAU * h * p2)) / h
		b[i] = s
	var res := _reso(b.duplicate(), 1250.0, 2.5, RATE)
	for i in total:
		var x := clampf((b[i] * 0.4 + res[i] * 1.6) * 0.55, -3.0, 3.0)
		b[i] = x * (27.0 + x * x) / (27.0 + 9.0 * x * x)
	return _mono(_normalize(b.slice(n, total), 0.85), RATE, true)


static func _engine_loop(data: CarData) -> Dictionary:
	var rate := 22050
	var synth := EngineSynth.new(data, float(rate), 7)
	var ref := clampf(data.idle_rpm * 0.5 + data.redline_rpm * 0.3, 1500.0, 4500.0)
	var spc := int(round(rate * 120.0 / ref))
	ref = rate * 120.0 / spc
	synth.rpm = ref
	synth.load = 0.6
	synth.render(int(0.25 * rate))
	var cycles := maxi(1, ceili(0.6 * rate / spc))
	var xf := int(0.04 * rate)
	var frames := synth.render(cycles * spc + xf)
	var b := PackedFloat32Array()
	b.resize(frames.size())
	for i in frames.size():
		b[i] = frames[i].x
	b = _normalize(_loopify(b, xf), 0.8)
	return {"l": b, "rate": rate, "loop": true, "meta": {"ref_rpm": ref}}


# ------------------------------------------------------------------ ambient beds (stereo)

static func _bed_vale() -> Dictionary:
	var xf := int(0.6 * BED_RATE)
	var n := 8 * BED_RATE + xf
	var swell := _smooth(n, 0.11, 201, BED_RATE)
	var wander := _smooth(n, 0.15, 202, BED_RATE)
	var ch: Array[PackedFloat32Array] = []
	for c in 2:
		var cut := PackedFloat32Array()
		cut.resize(n)
		for i in n:
			cut[i] = 420.0 + 240.0 * wander[i]
		var breeze := _svf(_noise(n, 210 + c), cut, 0.7, 0, BED_RATE)
		var gate := _smooth(n, 0.6, 220 + c * 7, BED_RATE)
		var rustle := _hp(_noise(n, 230 + c), 2600.0, BED_RATE)
		var b := PackedFloat32Array()
		b.resize(n)
		for i in n:
			var g := maxf(gate[i], 0.0)
			b[i] = breeze[i] * 2.2 * (0.45 + 0.55 * (0.5 + 0.5 * swell[i])) + rustle[i] * 0.3 * g * g
		ch.append(_loopify(b, xf))
	_normalize2(ch[0], ch[1], 0.7)
	return _stereo(ch[0], ch[1], BED_RATE, true)


static func _bed_highlands() -> Dictionary:
	var xf := int(0.6 * BED_RATE)
	var n := 8 * BED_RATE + xf
	var gust_c := _smooth(n, 0.17, 301, BED_RATE)
	var tone := _smooth(n, 0.23, 302, BED_RATE)
	var ch: Array[PackedFloat32Array] = []
	for c in 2:
		var cut := PackedFloat32Array()
		cut.resize(n)
		for i in n:
			cut[i] = 640.0 + 220.0 * tone[i] + 30.0 * c
		var whistle := _svf(_noise(n, 310 + c), cut, 7.0, 1, BED_RATE)
		var body := _lp(_lp(_noise(n, 320 + c), 210.0, BED_RATE), 210.0, BED_RATE)
		var hiss := _hp(_noise(n, 330 + c), 3500.0, BED_RATE)
		var b := PackedFloat32Array()
		b.resize(n)
		for i in n:
			var g := 0.25 + 0.75 * pow(0.5 + 0.5 * gust_c[i], 1.5)
			b[i] = (whistle[i] * 1.6 + body[i] * 7.0 + hiss[i] * 0.08) * g
		ch.append(_loopify(b, xf))
	_normalize2(ch[0], ch[1], 0.75)
	return _stereo(ch[0], ch[1], BED_RATE, true)


static func _bed_mesa() -> Dictionary:
	var xf := int(0.6 * BED_RATE)
	var n := 8 * BED_RATE + xf
	var swell := _smooth(n, 0.09, 401, BED_RATE)
	var ch: Array[PackedFloat32Array] = []
	for c in 2:
		var dry := _bp(_noise(n, 410 + c), 1900.0, 0.55, BED_RATE)
		var low := _lp(_lp(_noise(n, 420 + c), 140.0, BED_RATE), 140.0, BED_RATE)
		var ticks := _hp(_mul(_noise(n, 430 + c), _spikes(n, 25.0, 0.0015, 440 + c, BED_RATE)), 2500.0, BED_RATE)
		var b := PackedFloat32Array()
		b.resize(n)
		for i in n:
			var s := 0.55 + 0.45 * (0.5 + 0.5 * swell[i])
			b[i] = (dry[i] * 0.55 + low[i] * 6.0) * s + ticks[i] * 0.35
		ch.append(_loopify(b, xf))
	_normalize2(ch[0], ch[1], 0.7)
	return _stereo(ch[0], ch[1], BED_RATE, true)


## Surf: a constant distant roar plus three breaking waves on a cyclic timeline (seamless loop).
static func _bed_coast() -> Dictionary:
	var xf := int(0.6 * BED_RATE)
	var loop_len := 10.0
	var n := int(loop_len * BED_RATE) + xf
	var waves := [[0.3, 1.0, 0.8], [3.7, 0.7, 0.35], [6.6, 0.85, 0.65]]
	var ch: Array[PackedFloat32Array] = []
	for c in 2:
		var env := PackedFloat32Array()
		env.resize(n)
		var tail := PackedFloat32Array()
		tail.resize(n)
		for i in n:
			var t := float(i) / BED_RATE
			var e := 0.0
			var tl := 0.0
			for wv: Array in waves:
				var pan: float = float(wv[2]) if c == 0 else 1.0 - float(wv[2])
				var tr := fposmod(t - float(wv[0]), loop_len)
				var amp: float = float(wv[1]) * (0.5 + 0.5 * pan)
				if tr < 1.7:
					e += amp * pow(sin(PI * 0.5 * tr / 1.7), 2.0)
				else:
					var dk := exp(-(tr - 1.7) / 1.5)
					e += amp * dk
					tl += amp * dk * (1.0 - dk)
			env[i] = e
			tail[i] = tl
		var cut := PackedFloat32Array()
		cut.resize(n)
		for i in n:
			cut[i] = 300.0 + 3000.0 * minf(env[i], 1.2)
		var wash := _svf(_noise(n, 510 + c), cut, 0.6, 0, BED_RATE)
		var hiss := _hp(_noise(n, 520 + c), 3000.0, BED_RATE)
		var roar := _lp(_lp(_noise(n, 530 + c), 260.0, BED_RATE), 260.0, BED_RATE)
		var b := PackedFloat32Array()
		b.resize(n)
		for i in n:
			b[i] = wash[i] * env[i] * 1.6 + hiss[i] * tail[i] * 0.35 + roar[i] * 4.5
		ch.append(_loopify(b, xf))
	_normalize2(ch[0], ch[1], 0.8)
	return _stereo(ch[0], ch[1], BED_RATE, true)


static func _rain(storm: bool) -> Dictionary:
	var xf := int(0.4 * BED_RATE)
	var n := (6 if storm else 4) * BED_RATE + xf
	var gust := _smooth(n, 0.25, 601, BED_RATE)
	var howl_f := _smooth(n, 0.2, 602, BED_RATE)
	var ch: Array[PackedFloat32Array] = []
	for c in 2:
		var hiss := _hp(_lp(_noise(n, 610 + c), 6500.0, BED_RATE), 450.0, BED_RATE)
		var drops := _hp(_mul(_noise(n, 620 + c), _spikes(n, 1100.0 if storm else 700.0, 0.0009, 630 + c, BED_RATE, 3.0)), 1800.0, BED_RATE)
		var patter := _lp(_lp(_spikes(n, 300.0, 0.003, 640 + c, BED_RATE), 500.0, BED_RATE), 500.0, BED_RATE)
		var b := PackedFloat32Array()
		b.resize(n)
		for i in n:
			b[i] = hiss[i] * 0.55 + drops[i] * 1.2 + patter[i] * 2.0
		if storm:
			var rumble := _lp(_lp(_noise(n, 650 + c), 110.0, BED_RATE), 110.0, BED_RATE)
			var cut := PackedFloat32Array()
			cut.resize(n)
			for i in n:
				cut[i] = 420.0 + 130.0 * howl_f[i]
			var howl := _svf(_noise(n, 660 + c), cut, 5.0, 1, BED_RATE)
			for i in n:
				var g := 0.5 + 0.5 * (0.5 + 0.5 * gust[i])
				b[i] = b[i] * (1.1 + 0.3 * g) + (rumble[i] * 9.0 + howl[i] * 0.9) * g
		ch.append(_loopify(b, xf))
	_normalize2(ch[0], ch[1], 0.8)
	return _stereo(ch[0], ch[1], BED_RATE, true)


static func _crickets() -> Dictionary:
	var loop_len := 6.0
	var n := int(loop_len * BED_RATE)
	var rng := RandomNumberGenerator.new()
	rng.seed = 701
	var l := _const(n, 0.0)
	var r := _const(n, 0.0)
	for v in 5:
		var fc := rng.randf_range(3900.0, 4800.0)
		var period := loop_len / float(rng.randi_range(7, 11))
		var pulses := rng.randi_range(3, 4)
		var off := rng.randf_range(0.0, period)
		var amp := rng.randf_range(0.4, 1.0)
		var pan := rng.randf_range(0.15, 0.85)
		var gl := amp * sqrt(1.0 - pan)
		var gr := amp * sqrt(pan)
		for i in n:
			var t := float(i) / BED_RATE
			var tr := fposmod(t - off, period)
			var pi_ := int(tr / 0.034)
			if pi_ >= pulses:
				continue
			var tp := tr - pi_ * 0.034
			if tp >= 0.017:
				continue
			var e := sin(PI * tp / 0.017)
			var s := sin(TAU * fc * t) * e * e
			l[i] += s * gl
			r[i] += s * gr
	_normalize2(l, r, 0.6)
	return _stereo(l, r, BED_RATE, true)


static func _cicadas() -> Dictionary:
	var loop_len := 6.0
	var n := int(loop_len * BED_RATE)
	var buzz := _bp(_noise(n, 801), 5200.0, 3.0, BED_RATE)
	var l := _const(n, 0.0)
	var r := _const(n, 0.0)
	var voices := [[4700.0, 170.0, 0.0, 0.3], [5400.0, 205.0, 2.1, 0.7], [6100.0, 236.0, 4.0, 0.5]]
	for vc: Array in voices:
		var fc: float = vc[0]
		var pr: float = vc[1]
		var off: float = vc[2]
		var pan: float = vc[3]
		for i in n:
			var t := float(i) / BED_RATE
			var tr := fposmod(t - off, loop_len)
			var song := 0.0
			if tr < 1.4:
				song = tr / 1.4
			elif tr < 4.3:
				song = 1.0
			elif tr < 5.3:
				song = 1.0 - (tr - 4.3)
			if song <= 0.0:
				continue
			var am := pow(0.5 + 0.5 * sin(TAU * pr * t), 4.0)
			var s := (sin(TAU * fc * t) * 0.7 + buzz[i] * 1.8) * am * song
			l[i] += s * sqrt(1.0 - pan)
			r[i] += s * sqrt(pan)
	_normalize2(l, r, 0.6)
	return _stereo(l, r, BED_RATE, true)


# ------------------------------------------------------------------ ambient one-shots

static func _gust() -> Dictionary:
	var n := int(4.5 * BED_RATE)
	var flick := _smooth(n, 5.0, 901, BED_RATE)
	var env := PackedFloat32Array()
	env.resize(n)
	for i in n:
		var t := float(i) / BED_RATE
		var e := sin(PI * 0.5 * t / 1.6) if t < 1.6 else cos(PI * 0.5 * (t - 1.6) / 2.9)
		env[i] = maxf(e, 0.0) * maxf(e, 0.0) * (0.85 + 0.15 * flick[i])
	var ch: Array[PackedFloat32Array] = []
	for c in 2:
		var cut := PackedFloat32Array()
		cut.resize(n)
		var cut2 := PackedFloat32Array()
		cut2.resize(n)
		for i in n:
			cut[i] = 250.0 + 1700.0 * env[i]
			cut2[i] = 700.0 + 250.0 * env[i] + 25.0 * c
		var body := _svf(_noise(n, 910 + c), cut, 0.8, 0, BED_RATE)
		var whistle := _svf(_noise(n, 920 + c), cut2, 8.0, 1, BED_RATE)
		for i in n:
			body[i] = body[i] * env[i] * 2.0 + whistle[i] * env[i] * env[i] * 1.2
		ch.append(body)
	_normalize2(ch[0], ch[1], 0.85)
	return _stereo(ch[0], ch[1], BED_RATE, false)


static func _bird(variant: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1000 + variant * 37
	var n := int(1.3 * RATE)
	var b := _const(n, 0.0)
	var pos := int(0.02 * RATE)
	var notes := rng.randi_range(3, 7)
	var base := rng.randf_range(2600.0, 4200.0)
	var ph := 0.0
	for k in notes:
		var dur := int(rng.randf_range(0.045, 0.14) * RATE)
		if pos + dur >= n:
			break
		var f0 := base * rng.randf_range(0.8, 1.2)
		var f1 := f0 * rng.randf_range(0.7, 1.4)
		var trill := rng.randf() < 0.35
		var fm_rate := rng.randf_range(30.0, 60.0)
		for i in dur:
			var u := float(i) / dur
			var f := lerpf(f0, f1, u)
			if trill:
				f *= 1.0 + 0.08 * sin(TAU * fm_rate * float(i) / RATE)
			ph += f / RATE
			ph -= floorf(ph)
			var e := pow(sin(PI * u), 1.2)
			b[pos + i] += (sin(TAU * ph) + 0.12 * sin(TAU * 2.0 * ph)) * e
		pos += dur + int(rng.randf_range(0.03, 0.09) * RATE)
	b = _hp(b, 1500.0, RATE)
	return _mono(_normalize(b, 0.8), RATE, false)


static func _gull(variant: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = 2000 + variant * 53
	var n := int(1.6 * RATE)
	var b := _const(n, 0.0)
	var breath := _bp(_noise(n, 2100 + variant), 2500.0, 1.5, RATE)
	var pos := int(0.03 * RATE)
	var calls := rng.randi_range(2, 3)
	var ph := 0.0
	for k in calls:
		var dur := int(rng.randf_range(0.28, 0.42) * RATE)
		if pos + dur >= n:
			break
		var fb := rng.randf_range(640.0, 800.0)
		for i in dur:
			var u := float(i) / dur
			var f := fb * (1.0 + 0.45 * pow(sin(PI * minf(u * 1.6, 1.0)), 0.7) - 0.25 * u)
			ph += f / RATE
			ph -= floorf(ph)
			var s := 0.0
			for h in range(1, 7):
				s += sin(TAU * h * ph) / pow(h, 0.8)
			var e := minf(u / 0.08, 1.0) * pow(1.0 - u, 0.6)
			b[pos + i] += s * e + breath[pos + i] * e * 0.6
		pos += dur + int(rng.randf_range(0.08, 0.2) * RATE)
	var res := _reso(b.duplicate(), 1900.0, 2.0, RATE)
	_add(b, res, 2.0)
	b = _hp(b, 400.0, RATE)
	return _mono(_normalize(b, 0.8), RATE, false)


static func _owl() -> Dictionary:
	var n := int(1.8 * BED_RATE)
	var b := _const(n, 0.0)
	var breath := _lp(_noise(n, 3001), 600.0, BED_RATE)
	var ph := 0.0
	for note: Array in [[0.0, 0.38], [0.6, 0.2], [0.88, 0.42]]:
		var start := int(float(note[0]) * BED_RATE)
		var dur := int(float(note[1]) * BED_RATE)
		for i in dur:
			var u := float(i) / dur
			ph += lerpf(372.0, 348.0, u) / BED_RATE
			ph -= floorf(ph)
			var e := pow(sin(PI * u), 1.5)
			b[start + i] += (sin(TAU * ph) + 0.08 * sin(TAU * 2.0 * ph)) * e + breath[start + i] * e * 0.3
	return _mono(_normalize(b, 0.7), BED_RATE, false)


static func _thunder(near: bool) -> Dictionary:
	var n := int(7.0 * BED_RATE)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4001 if near else 4002
	var env := _const(n, 0.0)
	for j in 11:
		var t0 := rng.randf_range(0.05, 4.5) if j > 0 else (0.02 if near else 0.3)
		var att := rng.randf_range(0.08, 0.3) if near else rng.randf_range(0.3, 0.8)
		var dec := rng.randf_range(0.4, 1.4)
		var amp := rng.randf_range(0.3, 1.0) * (1.0 if j > 0 else 1.3)
		for i in range(int(t0 * BED_RATE), n):
			var t := float(i) / BED_RATE - t0
			env[i] += amp * (1.0 - exp(-t / att)) * exp(-t / dec)
	var ch: Array[PackedFloat32Array] = []
	for c in 2:
		var cut := PackedFloat32Array()
		cut.resize(n)
		for i in n:
			cut[i] = (70.0 + 220.0 * minf(env[i], 1.5)) if near else (60.0 + 110.0 * minf(env[i], 1.5))
		var rumble := _svf(_noise(n, 4010 + c), cut, 0.7, 0, BED_RATE)
		var sub := _lp(_lp(_noise(n, 4020 + c), 45.0, BED_RATE), 45.0, BED_RATE)
		var b := PackedFloat32Array()
		b.resize(n)
		for i in n:
			b[i] = (rumble[i] * 3.0 + sub[i] * 14.0) * env[i]
		if near:
			var crack := _hp(_mul(_noise(n, 4030 + c), _attack_decay(n, 0.001, 0.05, BED_RATE)), 600.0, BED_RATE)
			var rip := _bp(_mul(_noise(n, 4040 + c), _spikes(n, 2000.0, 0.002, 4050 + c, BED_RATE)), 1500.0, 0.8, BED_RATE)
			for i in mini(n, int(0.45 * BED_RATE)):
				var fade := 1.0 - float(i) / (0.45 * BED_RATE)
				b[i] += crack[i] * 1.4 + rip[i] * 2.5 * fade
		ch.append(b)
	_normalize2(ch[0], ch[1], 0.95 if near else 0.9)
	return _stereo(ch[0], ch[1], BED_RATE, false)
