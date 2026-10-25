extends Node3D
## Per-car sound, added as child "CarAudio" of a CarController.
## Player car: real-time procedural engine (AudioStreamGenerator, non-positional so chase and cockpit
## views sound the same) plus tyre, wind, suspension, impact, shift, turbo, horn and rain-on-roof layers.
## Other cars (traffic, is_player == false): a few positional players with a pitched, baked engine loop.
## AI can call honk(duration). backfire(strength) is emitted on exhaust pops (for flame effects).

signal backfire(strength: float)

const SfxBank := preload("res://scripts/audio/sfx_bank.gd")
const EngineSynth := preload("res://scripts/audio/engine_synth.gd")

const ENGINE_RATE := 22050.0
const FILL_SECONDS := 0.07
const FILL_MAX := 0.16
const NPC_RANGE := 120.0
const PLAYER_LAYERS: Array[StringName] = [&"squeal", &"scrub", &"gravel", &"soft", &"wind", &"rain_roof"]
const NPC_SAMPLES: Array[StringName] = [&"squeal", &"horn", &"impact_light", &"impact_medium", &"impact_heavy"]
const HORN_PITCH := {"lark_roadster": 0.78, "hauler_2500": 0.68, "ridgeback_sx": 0.84, "brute_68": 0.9,
	"vortex_x": 1.12, "castellan_gt": 1.04, "kestrel_r4": 1.08, "sora_s2": 1.06}


class Layer:
	var id: StringName
	var node: Node
	var lvl: float = 0.0


## Keeps the engine generator topped up. Runs on its own thread (immune to main-thread frame hitches,
## no main-thread cost); touches only the playback ring buffer and the synth, never the scene tree.
class Feeder:
	var gen: AudioStreamGeneratorPlayback
	var synth: RefCounted
	var rate: float = 22050.0
	var cap: int = 0
	var skips_seen: int = 0
	var fill: float = 0.05
	var fill_min: float = 0.05
	var fill_max: float = 0.16
	var feed: bool = false
	var run: bool = false
	var synth_us: int = 0

	## Tops the buffer up to the adaptive latency target; `span` = time since the previous call.
	func step(span: float) -> void:
		var avail := gen.get_frames_available()
		cap = maxi(cap, avail)
		var skips := gen.get_skips()
		if skips != skips_seen:
			skips_seen = skips
			fill = minf(fill + 0.02, fill_max)
		else:
			fill = maxf(fill - span * 0.008, fill_min)
		var target := mini(int(maxf(fill, span * 2.2) * rate), cap - 64)
		var want := mini(target - (cap - avail), avail)
		if want < 32:
			return
		var t := Time.get_ticks_usec()
		gen.push_buffer(synth.call(&"render", want))
		synth_us += Time.get_ticks_usec() - t

	func loop() -> void:
		var last := Time.get_ticks_usec()
		while run:
			var now := Time.get_ticks_usec()
			if feed:
				step(minf((now - last) / 1000000.0, 0.5))
			last = now
			OS.delay_msec(4)


var car: CarController
var is_player: bool = false
var synth: EngineSynth
var prof: Dictionary = {}
## One-shot sample id -> times played (diagnostics).
var fired: Dictionary = {}

var _inited: bool = false
var _engine: Node
var _gen: AudioStreamGeneratorPlayback
var _feeder: Feeder
var _thread: Thread
var _skips_base: int = 0
var _last_fill_us: int = 0
var _engine_key: StringName
var _engine_ref_rpm: float = 3000.0
var _layers: Dictionary = {}
var _horn: Layer
var _fx: Node
var _fx_pb: AudioStreamPlaybackPolyphonic
var _fx_idle: float = 0.0
var _horn_timer: float = 0.0

var _load: float = 0.0
var _fire: float = 1.0
var _boost: float = 0.0
var _thr_peak: float = 0.0
var _lifted: bool = false
var _lift_t: float = 99.0
var _lope_t: float = 0.0
var _start: float = 0.0
var _pops_seen: int = 0
var _prev_gear: int = 1
var _thump_cool := PackedFloat32Array()
var _thump_hit: float = 0.0
var _land_hit: float = 0.0
var _was_air: float = 0.0
var _quiet: float = 1.5
var _last_pos := Vector3.ZERO
var _flare: float = -1.0
var _tunnel: float = 0.0
var _tunnel_t: float = 0.0
var _tunnel_on: bool = false
var _range_t: float = 0.0
var _in_range: bool = true

var _qa: bool = false
var _stat_t: float = 0.0
var _stat_frames: int = 0
var _stat_synth_us: int = 0
var _stat_total_us: int = 0
var _stat_max_us: int = 0
var _stat_worst_dt: float = 0.0
var _stat_last_us: int = 0
static var _npc_us: int = 0
static var _npc_updates: int = 0
static var _npc_audible: int = 0


func _ready() -> void:
	if "--no-audio" in OS.get_cmdline_user_args():
		set_process(false)
		set_physics_process(false)
		return
	car = get_parent() as CarController
	SfxBank.ensure_buses()
	if not Settings.changed.is_connected(_on_setting):
		Settings.changed.connect(_on_setting)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--qa="):
			_qa = true


func _enter_tree() -> void:
	if _inited and is_player:
		_start_thread()


func _exit_tree() -> void:
	_stop_thread()
	if is_player and _tunnel > 0.0:
		SfxBank.set_tunnel_reverb(0.0)


func _start_thread() -> void:
	if _thread != null or _feeder == null or "--audio-main-thread" in OS.get_cmdline_user_args():
		return
	_feeder.run = true
	_feeder.fill_min = 0.05
	_thread = Thread.new()
	if _thread.start(_feeder.loop, Thread.PRIORITY_HIGH) != OK:
		_feeder.run = false
		_thread = null


func _stop_thread() -> void:
	if _thread == null:
		return
	_feeder.run = false
	_thread.wait_to_finish()
	_thread = null
	_feeder.fill_min = FILL_SECONDS


## AI horn (two-tone), also usable for the player car.
func honk(duration := 0.4) -> void:
	_horn_timer = maxf(_horn_timer, duration)


## Seconds of engine audio queued ahead of the speakers (a backfire is heard this long after it is emitted).
func engine_latency() -> float:
	if _feeder == null or _gen == null:
		return 0.0
	return maxf(_feeder.cap - _gen.get_frames_available(), 0) / ENGINE_RATE


func _init_audio() -> void:
	_inited = true
	is_player = car.is_player
	prof = EngineSynth.profile_for(car.data)
	_prev_gear = car.gear
	car.gear_changed.connect(_on_gear)
	car.impact.connect(_on_impact)
	_thump_cool.resize(car.wheels.size())
	_fx = _make_player(SfxBank.BUS_EFFECTS)
	var poly := AudioStreamPolyphonic.new()
	poly.polyphony = 12 if is_player else 4
	_fx.set(&"stream", poly)
	if is_player:
		_fx.call(&"play")
		_fx_pb = _fx.call(&"get_stream_playback") as AudioStreamPlaybackPolyphonic
	_horn = _add_layer(&"horn", SfxBank.BUS_EFFECTS)
	if is_player:
		synth = EngineSynth.new(car.data, ENGINE_RATE)
		var gen := AudioStreamGenerator.new()
		gen.mix_rate = ENGINE_RATE
		gen.buffer_length = 0.5
		var p := AudioStreamPlayer.new()
		p.name = "Engine"
		p.stream = gen
		p.bus = SfxBank.BUS_ENGINE
		add_child(p)
		p.play()
		_gen = p.get_stream_playback() as AudioStreamGeneratorPlayback
		_engine = p
		_feeder = Feeder.new()
		_feeder.gen = _gen
		_feeder.synth = synth
		_feeder.rate = ENGINE_RATE
		_feeder.fill = FILL_SECONDS
		_feeder.fill_min = FILL_SECONDS
		_feeder.fill_max = FILL_MAX
		_start_thread()
		for id in PLAYER_LAYERS:
			_add_layer(id, SfxBank.BUS_EFFECTS)
		SfxBank.prefetch(SfxBank.CAR_IDS)
	else:
		_engine = _make_player(SfxBank.BUS_ENGINE)
		_engine_key = SfxBank.request_engine_loop(car.data)
		_add_layer(&"squeal", SfxBank.BUS_EFFECTS)
		SfxBank.prefetch(NPC_SAMPLES)


func _make_player(bus: StringName) -> Node:
	var p: Node
	if is_player:
		var a := AudioStreamPlayer.new()
		a.bus = bus
		p = a
	else:
		var a3 := AudioStreamPlayer3D.new()
		a3.bus = bus
		a3.unit_size = 6.0
		a3.max_distance = NPC_RANGE
		a3.area_mask = 0
		a3.attenuation_filter_cutoff_hz = 6000.0
		a3.attenuation_filter_db = -18.0
		p = a3
	add_child(p)
	return p


func _add_layer(id: StringName, bus: StringName) -> Layer:
	var l := Layer.new()
	l.id = id
	l.node = _make_player(bus)
	_layers[id] = l
	return l


## Smoothly drives a looping layer to a linear level; stops the player when silent.
func _drive(l: Layer, target: float, pitch: float, delta: float, k_up := 14.0, k_down := 6.0) -> void:
	var k := k_up if target > l.lvl else k_down
	l.lvl += (target - l.lvl) * (1.0 - exp(-k * delta))
	if target <= 0.0 and l.lvl < 0.003:
		l.lvl = 0.0
	var n := l.node
	if l.lvl <= 0.0:
		if n.get(&"playing"):
			n.call(&"stop")
		return
	var st: AudioStream = n.get(&"stream")
	if st == null:
		st = SfxBank.peek(l.id)
		if st == null:
			return
		n.set(&"stream", st)
	n.set(&"volume_db", linear_to_db(l.lvl))
	n.set(&"pitch_scale", clampf(pitch, 0.1, 4.0))
	if not n.get(&"playing"):
		n.call(&"play", randf() * st.get_length())


func _oneshot(id: StringName, db: float, pitch: float) -> void:
	if _fx == null or (not is_player and not _in_range):
		return
	var s := SfxBank.peek(id)
	if s == null:
		return
	if not _fx.get(&"playing") or _fx_pb == null:
		_fx.call(&"play")
		_fx_pb = _fx.call(&"get_stream_playback") as AudioStreamPlaybackPolyphonic
	_fx_idle = 0.0
	_fx_pb.play_stream(s, 0.0, db, pitch, AudioServer.PLAYBACK_TYPE_DEFAULT, SfxBank.BUS_EFFECTS)
	fired[id] = int(fired.get(id, 0)) + 1


func _process(delta: float) -> void:
	if car == null or not is_instance_valid(car):
		return
	if not _inited:
		if car.data == null or car.wheels.is_empty():
			return
		_init_audio()
	SfxBank.poll()
	var t0 := Time.get_ticks_usec()
	if is_player:
		_update_player(delta)
	else:
		_update_npc(delta)
	_update_horn(delta)
	if _qa:
		if is_player:
			_stats(delta, Time.get_ticks_usec() - t0)
		else:
			_npc_us += Time.get_ticks_usec() - t0
			_npc_updates += 1
			if _in_range:
				_npc_audible += 1


func _physics_process(delta: float) -> void:
	if not _inited or not is_player or car == null or not is_instance_valid(car):
		return
	for i in car.wheels.size():
		var w := car.wheels[i]
		_thump_cool[i] = maxf(_thump_cool[i] - delta, 0.0)
		if not w.contact or _thump_cool[i] > 0.0:
			continue
		var v := (w.prev_length - w.length) / delta
		var thr := 0.9 + (w.surface.roughness * 40.0 if w.surface != null else 0.0)
		if v > thr:
			_thump_cool[i] = 0.12
			_thump_hit = maxf(_thump_hit, clampf((v - thr) / 2.5, 0.05, 1.0))
	if car.air_time > 0.0:
		_was_air = maxf(_was_air, car.air_time)
	elif _was_air > 0.0:
		if _was_air > 0.35:
			_land_hit = clampf(_was_air / 1.2, 0.35, 1.0)
		_was_air = 0.0
	# Teleports / respawns / spawn drops: no thuds while the car settles.
	var p := car.global_position
	if car.freeze or p.distance_to(_last_pos) > 8.0:
		_quiet = 1.2
	_last_pos = p
	_quiet = maxf(_quiet - delta, 0.0)
	if _quiet > 0.0:
		_thump_hit = 0.0
		_land_hit = 0.0
		_was_air = 0.0


# ------------------------------------------------------------------ player car

func _update_player(delta: float) -> void:
	if Game.main != null and bool(Game.main.get(&"is_loading")):
		# Engine off behind the loading screen; it starts (with a rev flare) when the drive begins.
		if _feeder != null:
			_feeder.feed = false
			_feeder.skips_seen = _gen.get_skips()
			_skips_base = _feeder.skips_seen
		_last_fill_us = 0
		_flare = -1.0
		return
	if _flare < 0.0:
		_flare = 1.0
		if _feeder != null:
			# Extra cushion for the stalls right after loading; relaxes to the minimum within ~10 s.
			_feeder.fill = 0.13
	if _feeder != null:
		_feeder.feed = true
	var d := car.data
	var spd := car.speed_ms
	var thr := car.throttle_applied
	var rn := clampf((car.rpm - d.idle_rpm) / maxf(d.max_rpm - d.idle_rpm, 1.0), 0.0, 1.0)
	_start = minf(_start + delta * 4.0, 1.0)
	_flare = maxf(_flare - delta * 0.9, 0.0)
	var pedal := car.in_brake if car.gear == -1 else car.in_throttle
	_thr_peak = maxf(pedal, _thr_peak - delta * 2.5)
	_lift_t += delta
	if pedal > 0.35:
		_lifted = false
	elif pedal < 0.12 and _thr_peak > 0.55 and not _lifted:
		_lifted = true
		_lift_t = 0.0
		_on_lift()
	_update_engine(delta, rn, thr, spd)
	_fill_engine(delta)
	_update_tyres(delta, spd)
	_update_body(delta, spd)
	_update_tunnel(delta)
	_flush_thumps()


func _on_lift() -> void:
	if car.data.turbo and _boost > 0.35:
		var id := &"flutter" if float(prof["pops"]) >= 1.0 else &"blowoff"
		_oneshot(id, linear_to_db(0.22 + 0.45 * _boost), randf_range(0.92, 1.08))
		_boost *= 0.25


func _update_engine(delta: float, rn: float, thr: float, spd: float) -> void:
	_lope_t += delta
	var idle_w := clampf(1.0 - rn * 4.0, 0.0, 1.0) * (1.0 - thr)
	var lope := float(prof["lope"]) * idle_w * (sin(_lope_t * 2.3) * 0.6 + sin(_lope_t * 5.9 + 1.3) * 0.4)
	# Start-up flare: the engine catches, revs up and settles to idle.
	var flare := 0.0
	if _flare > 0.0:
		var age := 1.0 - _flare
		flare = minf(age / 0.12, 1.0) * pow(_flare, 2.0) * (1.0 - rn)
	synth.rpm = car.rpm * (1.0 + lope + 1.1 * flare)
	_load += (maxf(thr, flare * 0.6) - _load) * (1.0 - exp(-delta * 16.0))
	synth.load = _load
	_fire += ((0.08 if car.shifting else 1.0) - _fire) * (1.0 - exp(-delta * 40.0))
	synth.fire_gain = _fire
	var pops := float(prof["pops"])
	var miss := 0.0
	var pop_rate := 0.0
	if car.limiter_hit:
		miss = 0.72
		pop_rate = 6.0 * pops
	elif thr < 0.08 and rn > 0.3 and spd > 4.0:
		var fresh := 1.0 if _lift_t < 1.4 else 0.25
		miss = 0.18 * pops
		pop_rate = pops * 16.0 * smoothstep(0.3, 0.9, rn) * fresh
	synth.miss_prob = miss
	synth.pop_rate = pop_rate
	if car.data.turbo:
		var spool := smoothstep(0.15, 0.6, rn) * thr
		_boost = move_toward(_boost, spool, delta * (1.3 if spool > _boost else 3.0))
	synth.boost = _boost
	if car.gear == -1:
		var v := absf(car.forward_speed)
		synth.whine_hz = 240.0 + v * 150.0
		synth.whine_amp = 0.05 * clampf(v / 2.0, 0.0, 1.0)
	elif float(prof["whine"]) > 0.0:
		synth.whine_hz = car.rpm / 60.0 * 21.0
		synth.whine_amp = float(prof["whine"]) * 0.035 * (0.3 + 0.7 * _load) * rn
	else:
		synth.whine_amp = 0.0
	synth.volume = _start


## Main-thread fallback when the engine thread is not running; also emits backfire for new pops.
func _fill_engine(delta: float) -> void:
	if _feeder == null:
		return
	if _thread == null:
		# Wall-clock frame time: the engine clamps `delta` (max physics steps) when the game runs slowly.
		var now := Time.get_ticks_usec()
		var real_dt := (now - _last_fill_us) / 1000000.0 if _last_fill_us > 0 else delta
		_last_fill_us = now
		_feeder.step(maxf(delta, minf(real_dt, 0.5)))
	if synth.pops_fired != _pops_seen:
		_pops_seen = synth.pops_fired
		backfire.emit(synth.last_pop_strength)


func _update_tyres(delta: float, spd: float) -> void:
	var sq_f := 0.0
	var sq_r := 0.0
	var lock := 0.0
	var grav := 0.0
	var grav_skid := 0.0
	var soft := 0.0
	var spin := 0.0
	for w in car.wheels:
		if not w.contact or w.surface == null:
			continue
		spin = maxf(spin, absf(w.omega * w.radius))
		var s := clampf((w.skid - 0.12) / 0.6, 0.0, 1.0)
		match w.surface.audio_kind:
			0:
				if w.front:
					sq_f = maxf(sq_f, s)
				else:
					sq_r = maxf(sq_r, s)
				if car.in_brake > 0.3 and w.slip_long > 0.1:
					lock = maxf(lock, s)
			1:
				grav += 0.25
				grav_skid = maxf(grav_skid, s)
			_:
				soft += 0.25
	var gate := clampf((maxf(spd, spin) - 0.8) / 4.0, 0.0, 1.0)
	var wob := sin(_lope_t * 7.3) * 0.015
	_drive(_layers[&"squeal"], sq_r * 0.6 * gate, 0.94 + 0.12 * sq_r + 0.1 * lock + wob, delta, 18.0, 7.0)
	_drive(_layers[&"scrub"], maxf(sq_f, lock) * 0.42 * gate, 0.9 + clampf(spd / 120.0, 0.0, 0.35) + 0.08 * lock, delta, 18.0, 7.0)
	var sf := clampf(spd / 22.0, 0.0, 1.0)
	var roll := clampf(spd / 1.5, 0.0, 1.0)
	_drive(_layers[&"gravel"], (grav * (0.15 + 0.85 * sf) * 0.65 + grav * grav_skid * 0.35) * roll, 0.75 + 0.4 * sf + 0.2 * grav_skid, delta)
	_drive(_layers[&"soft"], soft * sf * 0.55 * roll, 0.8 + 0.35 * sf, delta)


func _update_body(delta: float, spd: float) -> void:
	var cockpit := _cockpit()
	var w := clampf(spd / 70.0, 0.0, 1.25)
	_drive(_layers[&"wind"], w * w * 0.5 * (1.15 if cockpit else 1.0), 0.8 + clampf(spd / 160.0, 0.0, 0.8), delta, 4.0, 4.0)
	# Falling rain (blended, zero in tunnels), not surface wetness, which lingers long after the rain stops.
	var rain := 0.0
	if Game.env != null and Game.env.has_method(&"get_precipitation"):
		rain = clampf(float(Game.env.call(&"get_precipitation")) / 0.75, 0.0, 1.0) * (1.0 - _tunnel)
	else:
		rain = clampf((CarController.wetness - 0.3) / 0.5, 0.0, 1.0)
	_drive(_layers[&"rain_roof"], rain * (0.55 if cockpit else 0.3), 1.0, delta, 2.0, 2.0)


func _flush_thumps() -> void:
	if _land_hit > 0.0:
		_oneshot(&"thump_a", linear_to_db(0.6 + 0.4 * _land_hit), randf_range(0.8, 0.9))
		_oneshot(&"impact_light", linear_to_db(0.25 * _land_hit), randf_range(0.9, 1.05))
		_land_hit = 0.0
		_thump_hit = 0.0
	elif _thump_hit > 0.0:
		_oneshot(&"thump_a" if randf() < 0.5 else &"thump_b", linear_to_db(0.18 + 0.5 * _thump_hit), randf_range(0.9, 1.1))
		_thump_hit = 0.0


func _update_tunnel(delta: float) -> void:
	_tunnel_t -= delta
	if _tunnel_t <= 0.0:
		_tunnel_t = 0.2
		_tunnel_on = SfxBank.tunnel_at(car.global_position)
	var prev := _tunnel
	_tunnel = move_toward(_tunnel, 1.0 if _tunnel_on else 0.0, delta * 2.5)
	if _tunnel != prev:
		SfxBank.set_tunnel_reverb(_tunnel)


func _cockpit() -> bool:
	var rig := Game.camera_rig as CameraRig
	return rig != null and rig.mode == CameraRig.Mode.COCKPIT


func _on_gear(g: int) -> void:
	var prev := _prev_gear
	_prev_gear = g
	if not is_player or not _inited:
		return
	if g > prev and prev >= 1:
		_oneshot(&"shift", -15.0 + 4.0 * _load, randf_range(0.95, 1.05))
		if _load > 0.8 and float(prof["pops"]) >= 0.5:
			synth.trigger_pop(0.7 + 0.3 * randf())
	elif g == -1 or prev == -1:
		_oneshot(&"shift", -12.0, 0.8)
	else:
		_oneshot(&"shift", -19.0, 1.1)


func _on_impact(strength: float, _pos: Vector3) -> void:
	if not _inited or (is_player and _quiet > 0.0):
		return
	var k := clampf((strength - 1.5) / 12.0, 0.0, 1.0)
	var id := &"impact_light" if strength < 4.0 else (&"impact_medium" if strength < 9.0 else &"impact_heavy")
	_oneshot(id, linear_to_db(0.25 + 0.6 * k), randf_range(0.9, 1.08))


func _update_horn(delta: float) -> void:
	if _horn == null:
		return
	_horn_timer = maxf(_horn_timer - delta, 0.0)
	var on := _horn_timer > 0.0
	if is_player and not on and InputMap.has_action(&"horn") and not Game.is_overlay_open() and not Game.photo_mode:
		on = Input.is_action_pressed(&"horn")
	if not is_player and not _in_range:
		on = false
	_drive(_horn, 0.42 if on else 0.0, float(HORN_PITCH.get(car.data.id, 1.0)), delta, 60.0, 30.0)


# ------------------------------------------------------------------ other cars (cheap, positional)

func _update_npc(delta: float) -> void:
	_range_t -= delta
	if _range_t <= 0.0:
		_range_t = 0.3
		var cam := get_viewport().get_camera_3d()
		_in_range = cam == null or cam.global_position.distance_to(global_position) < NPC_RANGE
	var sq_layer: Layer = _layers[&"squeal"]
	# Positional players cost a panning update every physics tick while playing: keep idle ones stopped.
	_fx_idle += delta
	if _fx_idle > 2.5 and _fx.get(&"playing"):
		_fx.call(&"stop")
		_fx_pb = null
	if not _in_range:
		if _engine.get(&"playing"):
			_engine.call(&"stop")
		_drive(sq_layer, 0.0, 1.0, 10.0)
		return
	var st: AudioStream = _engine.get(&"stream")
	if st == null:
		st = SfxBank.peek(_engine_key)
		if st == null:
			return
		_engine.set(&"stream", st)
		_engine_ref_rpm = float(st.get_meta(&"ref_rpm", 3000.0))
	_load += (car.throttle_applied - _load) * (1.0 - exp(-delta * 8.0))
	_engine.set(&"pitch_scale", clampf(car.rpm / _engine_ref_rpm, 0.3, 3.0))
	_engine.set(&"volume_db", linear_to_db(0.22 + 0.3 * _load))
	if not _engine.get(&"playing"):
		_engine.call(&"play", randf() * st.get_length())
	var sq := 0.0
	for w in car.wheels:
		if w.contact and w.surface != null and w.surface.audio_kind == 0:
			sq = maxf(sq, clampf((w.skid - 0.15) / 0.6, 0.0, 1.0))
	_drive(sq_layer, sq * 0.6 * clampf(car.speed_ms / 4.0, 0.0, 1.0), 0.95 + 0.1 * sq, delta)


# ------------------------------------------------------------------ misc

func _on_setting(key: String, _value: Variant) -> void:
	if key.begins_with("volume_"):
		SfxBank.apply_volumes()


func _stats(delta: float, us: int) -> void:
	_stat_worst_dt = maxf(_stat_worst_dt, maxf(delta, (Time.get_ticks_usec() - _stat_last_us) / 1000000.0 if _stat_last_us > 0 else delta))
	_stat_last_us = Time.get_ticks_usec()
	_stat_frames += 1
	_stat_total_us += us
	_stat_max_us = maxi(_stat_max_us, us)
	_stat_t += delta
	if _stat_t < 5.0:
		return
	var f := maxi(_stat_frames, 1)
	var synth_us := _feeder.synth_us if _feeder else 0
	print("[audio] car=%s rpm=%d gear=%d load=%.2f boost=%.2f kmh=%.0f engine_thread=%s synth_us_per_frame=%.0f car_audio_main_thread_avg_us=%.0f max_us=%d underrun_skips_since_load=%d pops=%d bank_ms=%.0f bank_busy=%s tunnel=%.2f" % [
		car.data.id, int(car.rpm), car.gear, _load, _boost, car.get_speed_kmh(), str(_thread != null),
		float(synth_us - _stat_synth_us) / f, float(_stat_total_us) / f, _stat_max_us,
		(_gen.get_skips() - _skips_base) if _gen else -1, synth.pops_fired, SfxBank.gen_msec, str(SfxBank.is_busy()), _tunnel])
	_stat_synth_us = synth_us
	print("[audio] engine buffer target %.0f ms, worst frame %.0f ms | traffic CarAudio: %.0f us/frame total, %.1f nodes/frame, %.1f in hearing range" % [
		(_feeder.fill if _feeder else 0.0) * 1000.0, _stat_worst_dt * 1000.0, float(_npc_us) / f, float(_npc_updates) / f, float(_npc_audible) / f])
	_stat_worst_dt = 0.0
	_npc_us = 0
	_npc_updates = 0
	_npc_audible = 0
	_stat_t = 0.0
	_stat_frames = 0
	_stat_total_us = 0
	_stat_max_us = 0
