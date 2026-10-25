extends Node
## Procedural audio for the player car, synthesised into one AudioStreamGenerator:
## engine (firing-frequency harmonics shaped by RPM, load and per-car profile), turbo whine + blow-off,
## shift cut, tyre squeal (asphalt) / gravel crunch (loose), wind, suspension thumps, impacts, horn,
## and a quiet regional ambience bed (birds, sea, mountain/desert wind).

const RATE: float = 22050.0

var player: AudioStreamPlayer
var playback: AudioStreamGeneratorPlayback
var car: Car
var _ph: float = 0.0
var _ph2: float = 0.0
var _turbo_ph: float = 0.0
var _horn_ph: float = 0.0
var _rng := RandomNumberGenerator.new()
var _lp_tire: float = 0.0
var _bp_tire: float = 0.0
var _lp_wind: float = 0.0
var _lp_grav: float = 0.0
var _lp_eng: float = 0.0
var _lp_amb: float = 0.0
var _rough: float = 1.0
var _impact: float = 0.0
var _thump: float = 0.0
var _thump_ph: float = 0.0
var _blowoff: float = 0.0
var _shift_dip: float = 0.0
var _prev_throttle: float = 0.0
var _boost: float = 0.0
var _chirp_t: float = 0.0
var _chirp_f: float = 0.0
var _chirp_env: float = 0.0
var _wave_ph: float = 0.0
var horn_on: bool = false
var ext_horn: float = 0.0  # traffic horn level (0..1) mixed in
var _ext_horn_ph: float = 0.0
var smooth_rpm: float = 900.0
var smooth_load: float = 0.0


func _ready() -> void:
	player = AudioStreamPlayer.new()
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = RATE
	gen.buffer_length = 0.12
	player.stream = gen
	player.volume_db = -4.0
	add_child(player)
	player.play()
	playback = player.get_stream_playback()
	Game.car_changed.connect(_on_car)
	_on_car(Game.player)


func _on_car(c: Node) -> void:
	car = c as Car
	if car:
		car.audio = self
		car.impact.connect(func(s: float) -> void: _impact = maxf(_impact, 0.4 + s))


func on_shift(dir: int) -> void:
	_shift_dip = 1.0
	if dir > 0 and car and car.def.turbo and _boost > 0.5:
		_blowoff = 1.0


func _process(delta: float) -> void:
	var _pf: int = Time.get_ticks_usec()
	_inner_audio(delta)
	Game.prof_add("audio", _pf)


func _inner_audio(delta: float) -> void:
	if playback == null:
		return
	horn_on = Input.is_action_pressed("horn") and (Game.player != null)
	var frames: int = playback.get_frames_available()
	if frames <= 0:
		return
	var rpm: float = 0.0
	var load: float = 0.0
	var slip: float = 0.0
	var loose: bool = false
	var spd: float = 0.0
	var cyl: int = 4
	var pitch: float = 1.0
	var rough: float = 0.3
	var turbo: bool = false
	var redline: float = 7000.0
	if car and is_instance_valid(car):
		rpm = car.rpm
		load = car.in_throttle if car.gear > 0 else car.in_brake
		spd = car.linear_velocity.length()
		for w in car.wheels:
			if w.contact:
				slip = maxf(slip, w.slip)
				if Car.LOOSE[w.surface] == 1:
					loose = true
		cyl = car.def.cylinders
		pitch = car.def.sound_pitch
		rough = car.def.sound_rough
		turbo = car.def.turbo
		redline = car.def.redline
		for w in car.wheels:
			var xv: float = (w.x - w.px) * 120.0
			if xv > 2.2:
				_thump = maxf(_thump, clampf((xv - 2.2) * 0.25, 0.0, 1.0))
	if turbo:
		if load < 0.2 and _prev_throttle > 0.6 and _boost > 0.6:
			_blowoff = 1.0
		_boost = move_toward(_boost, load * clampf(rpm / redline * 1.6 - 0.3, 0.0, 1.0), delta * 2.0)
	_prev_throttle = load
	var region: int = 0
	if car and Game.world:
		region = Game.world.region_at(car.global_position.x, car.global_position.z)
	var vol: float = Game.settings.master_volume
	var buf := PackedVector2Array()
	buf.resize(frames)
	var dt: float = 1.0 / RATE
	var night: bool = Game.sky != null and Game.sky.is_night()
	for i in frames:
		smooth_rpm += (rpm - smooth_rpm) * 0.002
		smooth_load += (load - smooth_load) * 0.001
		var fire: float = smooth_rpm / 60.0 * cyl * 0.5 * pitch
		_ph = fmod(_ph + fire * dt, 1.0)
		_ph2 = fmod(_ph2 + fire * 0.5 * dt, 1.0)
		if _ph < fire * dt:
			_rough = 1.0 + _rng.randf_range(-rough, rough) * 0.6
		var a: float = TAU * _ph
		var bright: float = 0.25 + smooth_load * 0.75
		var e: float = sin(a) + 0.55 * sin(2.0 * a + 0.3) * bright + 0.32 * sin(3.0 * a + 0.7) * bright + 0.18 * sin(4.0 * a) * bright * bright + 0.35 * sin(TAU * _ph2)
		e *= _rough
		# exhaust burble: low-passed noise riding on firing pulses
		_lp_eng += (_rng.randf_range(-1.0, 1.0) * (0.3 + rough) - _lp_eng) * 0.15
		e += _lp_eng * (0.4 + (1.0 - smooth_load) * 0.6) * (0.5 + 0.5 * sin(a))
		var eng_amp: float = (0.16 + 0.22 * smooth_load) * (0.6 + 0.4 * clampf(smooth_rpm / redline, 0.0, 1.0)) * (1.0 - _shift_dip * 0.7)
		var s: float = e * eng_amp
		if turbo:
			_turbo_ph = fmod(_turbo_ph + (900.0 + smooth_rpm * 0.9) * dt, 1.0)
			s += sin(TAU * _turbo_ph) * 0.03 * _boost
			if _blowoff > 0.01:
				s += _rng.randf_range(-1.0, 1.0) * 0.12 * _blowoff
		# tyres
		var squeal: float = clampf((slip - 0.25) * 1.2, 0.0, 1.0) * clampf(spd / 6.0, 0.0, 1.0)
		var n: float = _rng.randf_range(-1.0, 1.0)
		if loose:
			_lp_grav += (n - _lp_grav) * 0.35
			s += _lp_grav * (0.06 * clampf(spd / 20.0, 0.0, 1.0) + squeal * 0.25) * (0.6 + 0.4 * _rng.randf())
		else:
			_lp_tire += (n - _lp_tire) * 0.5
			_bp_tire += (_lp_tire - _bp_tire) * 0.08
			s += (_lp_tire - _bp_tire) * squeal * 0.55 * (0.8 + 0.2 * sin(TAU * 7.0 * _ph2))
		# wind
		_lp_wind += (n - _lp_wind) * 0.02
		s += _lp_wind * clampf(spd * spd / 2500.0, 0.0, 1.2) * 0.35
		# suspension thump and impacts
		if _thump > 0.01:
			_thump_ph = fmod(_thump_ph + 55.0 * dt, 1.0)
			s += sin(TAU * _thump_ph) * _thump * 0.4
		if _impact > 0.01:
			s += n * _impact * 0.6 + sin(TAU * _thump_ph * 0.6) * _impact * 0.3
		# horn (player) and traffic horns
		if horn_on:
			_horn_ph = fmod(_horn_ph + 420.0 * dt, 1.0)
			s += (0.12 if _horn_ph < 0.5 else -0.12) + (0.08 if fmod(_horn_ph * 1.26, 1.0) < 0.5 else -0.08)
		if ext_horn > 0.01:
			_ext_horn_ph = fmod(_ext_horn_ph + 360.0 * dt, 1.0)
			s += (0.1 if _ext_horn_ph < 0.5 else -0.1) * ext_horn
		# ambience
		_lp_amb += (n - _lp_amb) * 0.01
		var amb: float = 0.0
		match region:
			0:
				if not night:
					_chirp_t -= dt
					if _chirp_t <= 0.0:
						_chirp_t = _rng.randf_range(0.3, 2.5)
						_chirp_f = _rng.randf_range(2500.0, 4200.0)
						_chirp_env = 1.0
					if _chirp_env > 0.001:
						_chirp_f *= 1.00004
						_wave_ph = fmod(_wave_ph + _chirp_f * dt, 1.0)
						amb += sin(TAU * _wave_ph) * _chirp_env * 0.02
						_chirp_env *= 0.9994
				amb += _lp_amb * 0.05
			1: amb += _lp_amb * 0.16
			2: amb += _lp_amb * 0.12
			3:
				var sw: float = 0.5 + 0.5 * sin(TAU * fmod(Time.get_ticks_msec() / 7000.0, 1.0))
				amb += _lp_amb * 0.25 * sw
		s += amb
		s = clampf(s * vol, -1.0, 1.0)
		buf[i] = Vector2(s, s)
		_impact *= 0.9996
		_thump *= 0.9993
		_blowoff *= 0.9997
		_shift_dip *= 0.9993
	playback.push_buffer(buf)
	ext_horn = move_toward(ext_horn, 0.0, delta * 1.5)
