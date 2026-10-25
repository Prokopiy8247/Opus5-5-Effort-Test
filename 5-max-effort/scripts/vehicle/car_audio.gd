class_name CarAudio
extends Node
## Player-car audio: synthesised engine (EngineSynth), tyre squeal per surface, surface rumble,
## wind, horn, gear shifts, exhaust pops, turbo blow-off, impacts and landing thumps.

const MIX_RATE := 22050.0

var car: CarController
var synth := EngineSynth.new()
var interior: bool = false
var master: float = 1.0

var _engine: AudioStreamPlayer
var _playback: AudioStreamGeneratorPlayback
var _loops: Dictionary = {}
var _oneshot: AudioStreamPlayer
var _oneshot2: AudioStreamPlayer
var _horn: AudioStreamPlayer
var _rpm_smooth: float = 900.0
var _load_smooth: float = 0.0
var _prev_gear: int = 1
var _prev_throttle: float = 0.0
var _prev_air: bool = false
var _pop_cooldown: float = 0.0


func setup(c: CarController) -> void:
	car = c
	synth.setup(c.definition)
	_engine = AudioStreamPlayer.new()
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = MIX_RATE
	gen.buffer_length = 0.1
	_engine.stream = gen
	_engine.volume_db = -6.0
	_engine.bus = "Master"
	add_child(_engine)
	_engine.play()
	_playback = _engine.get_stream_playback() as AudioStreamGeneratorPlayback
	for key in ["squeal", "gravel", "dirt", "grass", "wind"]:
		var p := AudioStreamPlayer.new()
		p.stream = SoundBank.get_stream(key)
		p.volume_db = -80.0
		add_child(p)
		p.play()
		_loops[key] = p
	_horn = AudioStreamPlayer.new()
	_horn.stream = SoundBank.get_stream("horn")
	_horn.volume_db = -8.0
	add_child(_horn)
	_oneshot = AudioStreamPlayer.new()
	add_child(_oneshot)
	_oneshot2 = AudioStreamPlayer.new()
	add_child(_oneshot2)
	car.impact.connect(_on_impact)
	_rpm_smooth = c.rpm


func _on_impact(strength: float, _p: Vector3) -> void:
	_play_one(_oneshot2, "impact", clampf(-14.0 + strength * 1.2, -14.0, 2.0), randf_range(0.85, 1.1))


func _play_one(p: AudioStreamPlayer, key: String, db: float, pitch: float = 1.0) -> void:
	p.stream = SoundBank.get_stream(key)
	p.volume_db = db + linear_to_db(master)
	p.pitch_scale = pitch
	p.play()


func _set_loop(key: String, gain: float, pitch: float = 1.0) -> void:
	var p: AudioStreamPlayer = _loops[key]
	var g := gain * master
	p.volume_db = linear_to_db(maxf(g, 0.0001)) if g > 0.002 else -80.0
	p.pitch_scale = clampf(pitch, 0.3, 3.0)


func _process(delta: float) -> void:
	if car == null or not is_instance_valid(car) or _playback == null:
		return
	master = float(Game.settings.get("master_volume", 0.8))
	_rpm_smooth = lerpf(_rpm_smooth, car.rpm, 1.0 - exp(-delta * 25.0))
	var target_load := car.engine_load
	if car.limiter_timer > 0.0:
		target_load = 0.2
	_load_smooth = lerpf(_load_smooth, target_load, 1.0 - exp(-delta * 12.0))
	var muffle := 0.45 if interior else 0.0
	var vol := (0.55 + 0.45 * _load_smooth) * master * (0.8 if interior else 1.0)
	synth.fill(_playback, MIX_RATE, _rpm_smooth, _load_smooth, car.turbo_boost if car.definition.turbo else 0.0, vol * 0.85, muffle)

	# tyres: worst slip among grounded wheels, grouped by surface sound
	var squeal := 0.0
	var gravel := 0.0
	var dirt := 0.0
	var grass := 0.0
	var speed := car.linear_velocity.length()
	for w in car.wheels:
		if not w.contact:
			continue
		var sdef := Surfaces.get_def(w.surface)
		var slip_amt := smoothstep(0.9, 1.8, w.slip)
		var roll := clampf(speed / 25.0, 0.0, 1.0)
		match sdef.sound:
			0:
				squeal = maxf(squeal, slip_amt * clampf(speed / 6.0, 0.0, 1.0))
			1, 5:
				gravel = maxf(gravel, roll * 0.6 + slip_amt * 0.5)
			2:
				dirt = maxf(dirt, roll * 0.6 + slip_amt * 0.4)
			3, 4:
				grass = maxf(grass, roll * 0.5 + slip_amt * 0.4)
	_set_loop("squeal", squeal * 0.55, 0.9 + squeal * 0.25)
	_set_loop("gravel", gravel * 0.5, 0.8 + clampf(speed / 40.0, 0.0, 0.6))
	_set_loop("dirt", dirt * 0.55, 0.7 + clampf(speed / 40.0, 0.0, 0.5))
	_set_loop("grass", grass * 0.4, 0.8 + clampf(speed / 40.0, 0.0, 0.5))
	var wind := clampf(speed / 85.0, 0.0, 1.0)
	_set_loop("wind", wind * wind * (0.35 if interior else 0.7), 0.6 + wind * 0.8)

	# horn
	var horn_on := Input.is_action_pressed("horn") and car.control_mode == CarController.ControlMode.PLAYER and not Game.ui_blocks_driving()
	if horn_on and not _horn.playing:
		_horn.volume_db = -8.0 + linear_to_db(master)
		_horn.play()
	elif not horn_on and _horn.playing:
		_horn.stop()

	# gear shifts, pops, blow-off
	_pop_cooldown -= delta
	if car.gear != _prev_gear:
		if car.gear > 0 and _prev_gear > 0:
			_play_one(_oneshot, "shift", -12.0, randf_range(0.9, 1.1))
		_prev_gear = car.gear
	if car.exhaust_pop_signal > 0.9 and _pop_cooldown <= 0.0:
		_play_one(_oneshot, "pop", -6.0, randf_range(0.8, 1.25))
		_pop_cooldown = 0.08
	if car.definition.turbo and _prev_throttle > 0.7 and car.input_throttle < 0.2 and car.turbo_boost > 0.5:
		_play_one(_oneshot2, "blowoff", -9.0, randf_range(0.95, 1.1))
	_prev_throttle = car.input_throttle
	# landing thump
	var air := car.grounded_wheels == 0
	if _prev_air and not air and car.airborne_time > 0.0:
		pass
	if _prev_air and not air:
		_play_one(_oneshot2, "thump", -4.0, 0.9)
	_prev_air = air
