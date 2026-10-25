extends Node
## Procedural audio (no recorded sounds). The player's engine is synthesised every frame into an
## AudioStreamGenerator from a per-profile wavetable of one engine cycle (cylinder firing pulses),
## blended between on-load and off-load tables by throttle load and pitched by RPM. Everything else
## (turbo whistle, blow-off, shift clunk, tyre squeal / gravel crunch / grass roll, wind, suspension
## thumps, impacts, horns, thunder, rain and regional ambience) is a short sample generated at start
## on a worker thread and played by looping or one-shot players.

const MIX := 22050.0
const TABLE := 1024
## engine profiles: cylinders, brightness (lowpass), roughness (pulse jitter), pitch, turbo whistle
const PROFILES := {
	&"i4": {"cyl": 4, "bright": 0.32, "rough": 0.06, "pitch": 1.0, "vol": 0.8},
	&"i4_turbo": {"cyl": 4, "bright": 0.4, "rough": 0.05, "pitch": 1.0, "vol": 0.85},
	&"i4_rally": {"cyl": 4, "bright": 0.55, "rough": 0.12, "pitch": 1.0, "vol": 0.95},
	&"i4_vintage": {"cyl": 4, "bright": 0.22, "rough": 0.16, "pitch": 0.9, "vol": 0.8},
	&"v6": {"cyl": 6, "bright": 0.38, "rough": 0.07, "pitch": 1.0, "vol": 0.85},
	&"v6_turbo": {"cyl": 6, "bright": 0.42, "rough": 0.06, "pitch": 1.0, "vol": 0.9},
	&"v8_muscle": {"cyl": 8, "bright": 0.24, "rough": 0.26, "pitch": 0.85, "vol": 1.0},
	&"v8_truck": {"cyl": 8, "bright": 0.2, "rough": 0.2, "pitch": 0.8, "vol": 0.9},
	&"v8_flat": {"cyl": 8, "bright": 0.5, "rough": 0.04, "pitch": 1.05, "vol": 0.95},
	&"v12": {"cyl": 12, "bright": 0.6, "rough": 0.03, "pitch": 1.0, "vol": 0.9},
}

var _car: CarController
var _engine: AudioStreamPlayer
var _gen: AudioStreamGeneratorPlayback
var _tab_on := PackedFloat32Array()
var _tab_off := PackedFloat32Array()
var _prof: Dictionary = PROFILES[&"v6"]
var _phase := 0.0
var _lp := 0.0
var _lp2 := 0.0
var _nlp := 0.0
var _rpm_s := 900.0
var _load_s := 0.0
var _vol_s := 0.0
var _boost := 0.0
var _prev_thr := 0.0
var _rng := RandomNumberGenerator.new()

var samples := {}                 ## name -> AudioStreamWAV (generated)
var _ready_samples := false
var _task := -1
var _loops := {}                  ## name -> AudioStreamPlayer (looping, volume driven)
var _amb := {}                    ## region ambience players
var _sfx: Array[AudioStreamPlayer3D] = []
var _sfx_i := 0
var _traffic_hum: Array[AudioStreamPlayer3D] = []
var _last_len := PackedFloat32Array()
var _thump_cd := 0.0
var _thunders: Array = []         ## pending [delay, volume]
var _horn_held := false
var _t0 := 0
var stats := {"sample_gen_ms": 0, "fill_us": 0, "fill_frames": 0}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_rng.seed = 1234
	_engine = AudioStreamPlayer.new()
	var g := AudioStreamGenerator.new()
	g.mix_rate = MIX
	g.buffer_length = 0.12
	_engine.stream = g
	_engine.volume_db = -6.0
	add_child(_engine)
	_engine.play()
	_gen = _engine.get_stream_playback() as AudioStreamGeneratorPlayback
	_t0 = Time.get_ticks_msec()
	_task = WorkerThreadPool.add_task(_generate_samples, true, "audio samples")
	Game.player_car_changed.connect(_on_car)
	Game.settings_changed.connect(_apply_volume)
	_apply_volume()


func _exit_tree() -> void:
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1


func _apply_volume() -> void:
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(float(Game.settings.get("master_volume", 0.8)), 0.0001)))


func _on_car(car: CarController) -> void:
	_car = car
	if car == null:
		return
	_prof = PROFILES.get(car.data.engine_sound, PROFILES[&"v6"])
	_build_tables(int(_prof.cyl), float(_prof.rough), hash(String(car.data.id)))
	_last_len.resize(car.wheels.size())
	for i in car.wheels.size():
		_last_len[i] = car.wheels[i].length
	if not car.gear_changed.is_connected(_on_gear):
		car.gear_changed.connect(_on_gear)


## One engine cycle (720 deg of crank) holding one exhaust pulse per cylinder.
func _build_tables(cyl: int, rough: float, seed_v: int) -> void:
	var r := RandomNumberGenerator.new()
	r.seed = seed_v
	_tab_on.resize(TABLE + 1)
	_tab_off.resize(TABLE + 1)
	_tab_on.fill(0.0)
	_tab_off.fill(0.0)
	var interval := float(TABLE) / cyl
	for k in cyl:
		var start := k * interval + r.randf_range(-rough, rough) * interval
		var amp := 1.0 + r.randf_range(-rough, rough) * 2.0
		for j in int(interval * 2.5):
			var t := float(j) / interval
			var idx := posmod(int(start) + j, TABLE)
			# sharp pressure pulse with ringing (on load) vs. a soft rounded puff (overrun)
			_tab_on[idx] += amp * exp(-t * 3.2) * sin(TAU * t * 1.6) + amp * 0.35 * exp(-t * 7.0) * sin(TAU * t * 4.3)
			_tab_off[idx] += amp * 0.6 * exp(-t * 2.2) * sin(TAU * t * 0.9)
	_tab_on = _normalised(_tab_on)
	_tab_off = _normalised(_tab_off)


func _normalised(tab: PackedFloat32Array) -> PackedFloat32Array:
	var mean := 0.0
	for i in TABLE:
		mean += tab[i]
	mean /= TABLE
	var mx := 0.0001
	for i in TABLE:
		tab[i] -= mean
		mx = maxf(mx, absf(tab[i]))
	for i in TABLE:
		tab[i] /= mx
	tab[TABLE] = tab[0]
	return tab


func _on_gear(g: int) -> void:
	if g != 0:
		_one_shot("shift", _car.global_position, -12.0, _rng.randf_range(0.9, 1.1))


# ----------------------------------------------------------------- per frame
func _process(delta: float) -> void:
	if not _ready_samples and _task >= 0 and WorkerThreadPool.is_task_completed(_task):
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
		_create_players()
		_ready_samples = true
		stats.sample_gen_ms = Time.get_ticks_msec() - _t0
		print("Audio: %d procedural samples ready in %d ms" % [samples.size(), stats.sample_gen_ms])
	if _car == null or not is_instance_valid(_car):
		_car = Game.player
		if _car != null:
			_on_car(_car)
		_fill_engine(0.0, 0.0, 0.0)
		return
	var paused := get_tree().paused
	var thr := _car.throttle_out
	var rpm := _car.rpm
	_rpm_s = lerpf(_rpm_s, rpm, minf(delta * 30.0, 1.0))
	_load_s = lerpf(_load_s, clampf(thr * 0.85 + _car.engine_load * 0.15, 0.0, 1.0), minf(delta * 10.0, 1.0))
	_vol_s = lerpf(_vol_s, 0.0 if paused else 1.0, minf(delta * 4.0, 1.0))
	_fill_engine(_rpm_s, _load_s, _vol_s)
	if not _ready_samples:
		return
	_update_turbo(delta, thr, rpm)
	_update_tyres_wind(delta)
	_update_ambience(delta)
	_update_traffic_hum()
	_update_horn()
	for t: Array in _thunders.duplicate():
		t[0] -= delta
		if t[0] <= 0.0:
			_thunders.erase(t)
			var p := _loops.get("thunder_player") as AudioStreamPlayer
			if p != null:
				p.volume_db = linear_to_db(float(t[1]))
				p.pitch_scale = _rng.randf_range(0.8, 1.1)
				p.play()


func _physics_process(delta: float) -> void:
	if _car == null or not is_instance_valid(_car) or not _ready_samples:
		return
	_thump_cd -= delta
	if _last_len.size() != _car.wheels.size():
		_last_len.resize(_car.wheels.size())
	for i in _car.wheels.size():
		var w = _car.wheels[i]
		var comp_speed: float = (_last_len[i] - float(w.length)) / maxf(delta, 1e-4)
		_last_len[i] = w.length
		if comp_speed > 1.4 and _thump_cd <= 0.0 and w.contact:
			_thump_cd = 0.18
			_one_shot("thump", _car.global_position, linear_to_db(clampf(comp_speed / 5.0, 0.15, 1.0)) - 4.0, _rng.randf_range(0.85, 1.1))


func _fill_engine(rpm: float, load: float, vol: float) -> void:
	if _gen == null or _tab_on.size() < TABLE + 1:
		return
	var n := _gen.get_frames_available()
	if n <= 0:
		return
	var t_us := Time.get_ticks_usec()
	_gen.push_buffer(synth(n, rpm, load, vol))
	stats.fill_us = int(stats.fill_us) + Time.get_ticks_usec() - t_us
	stats.fill_frames = int(stats.fill_frames) + n


## n stereo frames of engine sound continuing the running phase/filter state (also used offline
## by tools/qa/audio_test.gd).
func synth(n: int, rpm: float, load: float, vol: float) -> PackedVector2Array:
	var pitch: float = float(_prof.pitch)
	var inc := (rpm * pitch / 120.0) / MIX
	var bright: float = float(_prof.bright)
	# brighter with revs and load; the second pole tames the buzz
	var a := clampf(0.08 + bright * (0.35 + 0.5 * load) + rpm / 30000.0, 0.05, 0.95)
	var a2 := clampf(a * 1.4, 0.05, 0.98)
	var gain := vol * float(_prof.vol) * (0.35 + 0.65 * load) * clampf(0.55 + rpm / 9000.0, 0.0, 1.2)
	var noise_amt := 0.06 + 0.22 * load
	var na := clampf(0.05 + rpm / 20000.0, 0.05, 0.6)
	var buf := PackedVector2Array()
	buf.resize(n)
	var ph := _phase
	var lp := _lp
	var lp2 := _lp2
	var nlp := _nlp
	var on := _tab_on
	var off := _tab_off
	for i in n:
		ph += inc
		if ph >= 1.0:
			ph -= 1.0
		var x := ph * TABLE
		var k := int(x)
		var f := x - k
		var s_on := on[k] + (on[k + 1] - on[k]) * f
		var s_off := off[k] + (off[k + 1] - off[k]) * f
		nlp += na * ((randf() * 2.0 - 1.0) - nlp)
		var s := s_off + (s_on - s_off) * load + nlp * noise_amt
		lp += a * (s - lp)
		lp2 += a2 * (lp - lp2)
		var y := lp2 * gain * 1.4
		var o := y / (1.0 + absf(y))  # soft saturation instead of hard clipping
		buf[i] = Vector2(o, o)
	_phase = ph
	_lp = lp
	_lp2 = lp2
	_nlp = nlp
	return buf


## Selects an engine profile without a car (offline rendering in QA).
func use_profile(profile: StringName, seed_v := 1) -> void:
	_prof = PROFILES.get(profile, PROFILES[&"v6"])
	_build_tables(int(_prof.cyl), float(_prof.rough), seed_v)


func _update_turbo(delta: float, thr: float, rpm: float) -> void:
	var whistle := _loops.get("turbo") as AudioStreamPlayer
	if whistle == null:
		return
	if not _car.data.turbo:
		whistle.volume_db = -80.0
		_boost = 0.0
		return
	var target := clampf((rpm / _car.data.redline_rpm - 0.3) / 0.6, 0.0, 1.0) * thr
	_boost = move_toward(_boost, target, delta * (1.6 if target > _boost else 3.0))
	whistle.volume_db = linear_to_db(maxf(_boost * 0.22, 0.0001))
	whistle.pitch_scale = 0.55 + _boost * 0.75
	if _prev_thr > 0.6 and thr < 0.15 and _boost > 0.35:
		_one_shot("blowoff", _car.global_position, linear_to_db(_boost * 0.7), _rng.randf_range(0.9, 1.15))
		_boost *= 0.3
	_prev_thr = thr


func _update_tyres_wind(delta: float) -> void:
	var skid := 0.0
	var loose_skid := 0.0
	var roll_gravel := 0.0
	var roll_grass := 0.0
	var contacts := 0
	for w in _car.wheels:
		if not w.contact or w.surface == null:
			continue
		contacts += 1
		var s := clampf(float(w.skid), 0.0, 1.0)
		if w.surface.skid_sound == &"squeal":
			skid = maxf(skid, s)
		else:
			loose_skid = maxf(loose_skid, s)
		if w.surface.roll_sound == &"gravel":
			roll_gravel += 0.25
		elif w.surface.roll_sound == &"grass":
			roll_grass += 0.25
	var spd := _car.speed_abs
	var sp_f := clampf(spd / 25.0, 0.0, 1.0)
	_set_loop("squeal", skid * clampf(spd / 6.0, 0.0, 1.0) * 0.55, 0.85 + skid * 0.3, delta)
	_set_loop("gravel", maxf(loose_skid * 0.8, roll_gravel * sp_f * 0.45), 0.8 + sp_f * 0.4, delta)
	_set_loop("grass", roll_grass * sp_f * 0.4, 0.8 + sp_f * 0.3, delta)
	var wind := clampf(spd / 70.0, 0.0, 1.0)
	_set_loop("wind", wind * wind * 0.6 + (0.12 if _car.air_time > 0.3 else 0.0), 0.7 + wind * 0.7, delta)
	var rain := 0.0
	if Game.sky != null:
		rain = float(Game.sky.get("_cur").get("rain", 0.0)) if Game.sky.get("_cur") is Dictionary else 0.0
	_set_loop("rain", clampf(rain, 0.0, 1.0) * 0.45, 1.0, delta)


func _set_loop(name: String, vol: float, pitch: float, delta: float) -> void:
	var p := _loops.get(name) as AudioStreamPlayer
	if p == null:
		return
	var cur := db_to_linear(p.volume_db)
	var v := move_toward(cur, vol, delta * 3.0)
	p.volume_db = linear_to_db(maxf(v, 0.0001))
	p.pitch_scale = clampf(pitch, 0.3, 3.0)


func _update_ambience(delta: float) -> void:
	if Game.world == null or not Game.world.has_method("region_at"):
		return
	var region: int = Game.world.region_at(_car.global_position)
	var night: bool = Game.sky != null and bool(Game.sky.get("is_night"))
	var names := {0: "amb_valley", 1: "amb_highlands", 2: "amb_desert", 3: "amb_coast"}
	for id: int in names:
		var p := _amb.get(names[id]) as AudioStreamPlayer
		if p == null:
			continue
		var target := (0.28 if id == region else 0.0) * (0.45 if night else 1.0)
		var v := move_toward(db_to_linear(p.volume_db), target, delta * 0.15)
		p.volume_db = linear_to_db(maxf(v, 0.0001))
	var cr := _amb.get("amb_night") as AudioStreamPlayer
	if cr != null:
		var t := 0.2 if night and region != 1 else 0.0
		cr.volume_db = linear_to_db(maxf(move_toward(db_to_linear(cr.volume_db), t, delta * 0.1), 0.0001))


func _update_traffic_hum() -> void:
	if Game.traffic == null or _traffic_hum.is_empty():
		return
	var near: Array = []
	var cp := _car.global_position
	for t: Node3D in Game.traffic.active:
		var d := t.global_position.distance_squared_to(cp)
		if d < 70.0 * 70.0:
			near.append([d, t])
	near.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	for i in _traffic_hum.size():
		var p := _traffic_hum[i]
		if i < near.size():
			var t: Node3D = near[i][1]
			p.global_position = t.global_position
			var v := float(t.get("speed")) if t.get("speed") != null else 10.0
			p.pitch_scale = clampf(0.6 + v / 25.0, 0.5, 1.8)
			p.volume_db = -10.0
		else:
			p.volume_db = -80.0


func _update_horn() -> void:
	var held := Input.is_action_pressed("horn") and not Game.input_blocked()
	var p := _loops.get("horn_loop") as AudioStreamPlayer
	if p == null:
		return
	if held != _horn_held:
		_horn_held = held
		p.volume_db = -4.0 if held else -80.0
		if held and Game.traffic != null and Game.traffic.has_method("on_player_horn"):
			Game.traffic.on_player_horn(_car.global_position)


# ------------------------------------------------------------- public hooks
func impact(strength: float, at: Vector3) -> void:
	if not _ready_samples:
		return
	_one_shot("impact", at, linear_to_db(clampf(strength / 14.0, 0.12, 1.0)), _rng.randf_range(0.8, 1.15))


func horn(at: Vector3) -> void:
	if _ready_samples:
		_one_shot("horn", at, -2.0, _rng.randf_range(0.85, 1.15))


func thunder(delay: float) -> void:
	_thunders.append([delay, _rng.randf_range(0.5, 1.0)])


func ui_click() -> void:
	if _ready_samples:
		_one_shot("click", Vector3.ZERO, -8.0, 1.0, true)


func chime(good := true) -> void:
	if _ready_samples:
		_one_shot("chime" if good else "buzz", Vector3.ZERO, -6.0, 1.0, true)


func _one_shot(name: String, at: Vector3, db: float, pitch: float, flat := false) -> void:
	if not samples.has(name) or _sfx.is_empty():
		return
	var p := _sfx[_sfx_i]
	_sfx_i = (_sfx_i + 1) % _sfx.size()
	p.stream = samples[name]
	p.global_position = at if not flat and at != Vector3.ZERO else (get_viewport().get_camera_3d().global_position if get_viewport().get_camera_3d() != null else Vector3.ZERO)
	p.volume_db = db
	p.pitch_scale = pitch
	p.play()


# ---------------------------------------------------------- sample synthesis
func _create_players() -> void:
	for name: String in ["squeal", "gravel", "grass", "wind", "turbo", "rain", "horn_loop"]:
		var p := AudioStreamPlayer.new()
		p.stream = samples[name]
		p.volume_db = -80.0
		add_child(p)
		p.play()
		_loops[name] = p
	var th := AudioStreamPlayer.new()
	th.stream = samples["thunder"]
	add_child(th)
	_loops["thunder_player"] = th
	for name: String in ["amb_valley", "amb_highlands", "amb_desert", "amb_coast", "amb_night"]:
		var p := AudioStreamPlayer.new()
		p.stream = samples[name]
		p.volume_db = -80.0
		add_child(p)
		p.play()
		_amb[name] = p
	for i in 8:
		var p := AudioStreamPlayer3D.new()
		p.unit_size = 12.0
		p.max_distance = 220.0
		add_child(p)
		_sfx.append(p)
	for i in 3:
		var p := AudioStreamPlayer3D.new()
		p.stream = samples["hum"]
		p.unit_size = 8.0
		p.max_distance = 90.0
		p.volume_db = -80.0
		add_child(p)
		p.play()
		_traffic_hum.append(p)


func _generate_samples() -> void:
	var r := RandomNumberGenerator.new()
	r.seed = 99
	var out := {}
	# tyre squeal: wavering 1.1 kHz tone with harmonics and a hiss band
	out["squeal"] = _loop(1.6, func(i: int, t: float, st: Dictionary) -> float:
		var f := 1050.0 + 90.0 * sin(TAU * 5.3 * t) + 40.0 * sin(TAU * 13.0 * t)
		st.ph += f / MIX
		var tone := sin(TAU * st.ph) * 0.6 + sin(TAU * st.ph * 2.01) * 0.25 + sin(TAU * st.ph * 3.03) * 0.1
		st.n += 0.3 * ((r.randf() * 2.0 - 1.0) - st.n)
		return tone * (0.75 + 0.25 * sin(TAU * 7.0 * t)) + st.n * 0.25, {"ph": 0.0, "n": 0.0})
	# loose-surface crunch: brown noise with sparse grit impulses
	out["gravel"] = _loop(2.0, func(i: int, t: float, st: Dictionary) -> float:
		st.b = clampf(st.b + (r.randf() * 2.0 - 1.0) * 0.12, -1.0, 1.0)
		var grit := (r.randf() * 2.0 - 1.0) * (1.0 if r.randf() < 0.035 else 0.0)
		st.g += 0.5 * (grit - st.g)
		return st.b * 0.55 + st.g * 1.4, {"b": 0.0, "g": 0.0})
	out["grass"] = _loop(2.0, func(i: int, t: float, st: Dictionary) -> float:
		st.b += 0.08 * ((r.randf() * 2.0 - 1.0) - st.b)
		return st.b * 1.6 * (0.7 + 0.3 * sin(TAU * 3.0 * t)), {"b": 0.0})
	out["wind"] = _loop(3.0, func(i: int, t: float, st: Dictionary) -> float:
		st.a += 0.05 * ((r.randf() * 2.0 - 1.0) - st.a)
		st.b += 0.2 * ((r.randf() * 2.0 - 1.0) - st.b)
		return (st.a * 1.8 + st.b * 0.25) * (0.75 + 0.25 * sin(TAU * 0.7 * t)), {"a": 0.0, "b": 0.0})
	out["turbo"] = _loop(0.5, func(i: int, t: float, st: Dictionary) -> float:
		return sin(TAU * 2400.0 * t) * 0.5 + sin(TAU * 4800.0 * t) * 0.12 + (r.randf() * 2.0 - 1.0) * 0.06, {})
	out["rain"] = _loop(3.0, func(i: int, t: float, st: Dictionary) -> float:
		st.a += 0.35 * ((r.randf() * 2.0 - 1.0) - st.a)
		var drop := (r.randf() * 2.0 - 1.0) * (0.8 if r.randf() < 0.01 else 0.0)
		return st.a * 0.7 + drop, {"a": 0.0})
	out["hum"] = _loop(1.0, func(i: int, t: float, st: Dictionary) -> float:
		var f := 55.0
		return (sin(TAU * f * t) * 0.5 + sin(TAU * f * 2.0 * t) * 0.3 + sin(TAU * f * 3.0 * t) * 0.15) * (0.8 + 0.2 * sin(TAU * 9.0 * t)), {})
	out["horn_loop"] = _loop(1.0, func(i: int, t: float, st: Dictionary) -> float:
		return _horn_wave(t), {})
	out["horn"] = _shot(0.55, func(i: int, t: float, st: Dictionary) -> float:
		return _horn_wave(t * 0.92) * minf(t * 40.0, 1.0) * minf((0.55 - t) * 20.0, 1.0), {})
	out["blowoff"] = _shot(0.5, func(i: int, t: float, st: Dictionary) -> float:
		st.a += lerpf(0.6, 0.12, t / 0.5) * ((r.randf() * 2.0 - 1.0) - st.a)
		return st.a * exp(-t * 7.0) * 1.4, {"a": 0.0})
	out["shift"] = _shot(0.14, func(i: int, t: float, st: Dictionary) -> float:
		return (sin(TAU * 90.0 * t) * exp(-t * 40.0) + (r.randf() * 2.0 - 1.0) * exp(-t * 90.0) * 0.5), {})
	out["thump"] = _shot(0.25, func(i: int, t: float, st: Dictionary) -> float:
		return sin(TAU * (55.0 - 80.0 * t) * t) * exp(-t * 16.0) + (r.randf() * 2.0 - 1.0) * exp(-t * 60.0) * 0.3, {})
	out["impact"] = _shot(0.7, func(i: int, t: float, st: Dictionary) -> float:
		var thud := sin(TAU * 70.0 * t) * exp(-t * 10.0)
		var crash := (r.randf() * 2.0 - 1.0) * exp(-t * 14.0)
		var ring := (sin(TAU * 523.0 * t) + sin(TAU * 1307.0 * t) * 0.6 + sin(TAU * 2213.0 * t) * 0.3) * exp(-t * 6.0) * 0.25
		return thud * 0.8 + crash * 0.6 + ring, {})
	out["thunder"] = _shot(4.5, func(i: int, t: float, st: Dictionary) -> float:
		st.a += 0.03 * ((r.randf() * 2.0 - 1.0) - st.a)
		var env := minf(t * 6.0, 1.0) * exp(-t * 0.8) * (0.6 + 0.4 * sin(TAU * 1.3 * t + sin(TAU * 0.4 * t)))
		return st.a * 4.0 * env, {"a": 0.0})
	out["click"] = _shot(0.05, func(i: int, t: float, st: Dictionary) -> float:
		return sin(TAU * 1800.0 * t) * exp(-t * 120.0), {})
	out["chime"] = _shot(0.8, func(i: int, t: float, st: Dictionary) -> float:
		var n := 784.0 if t < 0.12 else 1175.0
		return (sin(TAU * n * t) * 0.6 + sin(TAU * n * 2.0 * t) * 0.15) * exp(-maxf(t - (0.0 if t < 0.12 else 0.12), 0.0) * 5.0), {})
	out["buzz"] = _shot(0.4, func(i: int, t: float, st: Dictionary) -> float:
		return signf(sin(TAU * 140.0 * t)) * 0.4 * exp(-t * 4.0), {})
	# regional ambience (8 s loops)
	out["amb_valley"] = _loop(8.0, func(i: int, t: float, st: Dictionary) -> float:
		st.w += 0.01 * ((r.randf() * 2.0 - 1.0) - st.w)
		return st.w * 2.0 + _birds(t, st, r, 0.9), {"w": 0.0, "bt": 0.0, "bf": 3000.0, "bp": 0.0})
	out["amb_highlands"] = _loop(8.0, func(i: int, t: float, st: Dictionary) -> float:
		st.w += 0.02 * ((r.randf() * 2.0 - 1.0) - st.w)
		var gust := 0.6 + 0.4 * sin(TAU * 0.25 * t) * sin(TAU * 0.125 * t + 1.0)
		return st.w * 3.0 * gust + _birds(t, st, r, 0.25), {"w": 0.0, "bt": 0.0, "bf": 3400.0, "bp": 0.0})
	out["amb_desert"] = _loop(8.0, func(i: int, t: float, st: Dictionary) -> float:
		st.w += 0.015 * ((r.randf() * 2.0 - 1.0) - st.w)
		var cicada := sin(TAU * 4200.0 * t) * (0.5 + 0.5 * sin(TAU * 38.0 * t)) * maxf(sin(TAU * 0.125 * t), 0.0) * 0.18
		return st.w * 2.4 + cicada, {"w": 0.0})
	out["amb_coast"] = _loop(8.0, func(i: int, t: float, st: Dictionary) -> float:
		st.w += 0.06 * ((r.randf() * 2.0 - 1.0) - st.w)
		var swell := pow(0.5 + 0.5 * sin(TAU * t / 8.0 * 2.0), 2.0)
		var gull := 0.0
		var gt := fmod(t, 4.0) - 2.3
		if gt > 0.0 and gt < 0.45:
			gull = sin(TAU * (1400.0 - 500.0 * gt) * t) * sin(PI * gt / 0.45) * 0.12
		return st.w * 1.5 * (0.25 + swell) + gull, {"w": 0.0})
	out["amb_night"] = _loop(8.0, func(i: int, t: float, st: Dictionary) -> float:
		var chirp := sin(TAU * 4600.0 * t) * maxf(sin(TAU * 26.0 * t), 0.0) * (1.0 if fmod(t, 0.9) < 0.35 else 0.0)
		var chirp2 := sin(TAU * 5100.0 * t) * maxf(sin(TAU * 31.0 * t), 0.0) * (1.0 if fmod(t + 0.4, 1.3) < 0.4 else 0.0)
		return (chirp + chirp2 * 0.7) * 0.25, {})
	samples = out


func _horn_wave(t: float) -> float:
	var a := sin(TAU * 415.0 * t)
	var b := sin(TAU * 523.0 * t)
	return clampf((a + b) * 0.9, -0.7, 0.7)


## Sporadic two-note bird calls mixed into an ambience loop.
func _birds(t: float, st: Dictionary, r: RandomNumberGenerator, density: float) -> float:
	st.bt -= 1.0 / MIX
	if st.bt <= -0.25:
		st.bt = r.randf_range(0.3, 2.2) / density
		st.bf = r.randf_range(2500.0, 4200.0)
	if st.bt < 0.0:
		var k: float = -st.bt / 0.25
		st.bp += (float(st.bf) * (1.0 + 0.25 * sin(TAU * 18.0 * k))) / MIX
		return sin(TAU * st.bp) * sin(PI * k) * 0.08
	return 0.0


func _loop(seconds: float, fn: Callable, state: Dictionary) -> AudioStreamWAV:
	var n := int(seconds * MIX)
	var fade := int(0.25 * MIX)
	var data := PackedFloat32Array()
	data.resize(n + fade)
	for i in n + fade:
		data[i] = fn.call(i, i / MIX, state)
	# crossfade the tail into the head so the loop is seamless
	for i in fade:
		var k := float(i) / fade
		data[i] = data[n + i] * (1.0 - k) + data[i] * k
	data.resize(n)
	return _wav(data, true)


func _shot(seconds: float, fn: Callable, state: Dictionary) -> AudioStreamWAV:
	var n := int(seconds * MIX)
	var data := PackedFloat32Array()
	data.resize(n)
	for i in n:
		data[i] = fn.call(i, i / MIX, state)
	return _wav(data, false)


func _wav(data: PackedFloat32Array, loop: bool) -> AudioStreamWAV:
	var mx := 0.0001
	for v in data:
		mx = maxf(mx, absf(v))
	var bytes := PackedByteArray()
	bytes.resize(data.size() * 2)
	var g := 0.9 / mx
	for i in data.size():
		bytes.encode_s16(i * 2, int(clampf(data[i] * g, -1.0, 1.0) * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = int(MIX)
	w.stereo = false
	w.data = bytes
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = data.size()
	return w
