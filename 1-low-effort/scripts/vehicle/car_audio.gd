class_name CarAudio
extends Node3D
## Procedural engine / turbo / tyre / wind audio for the player car (AudioStreamGenerator).

const RATE := 22050.0
var car: Car
var engine_player := AudioStreamPlayer3D.new()
var fx_player := AudioStreamPlayer.new()
var engine_pb: AudioStreamGeneratorPlayback
var fx_pb: AudioStreamGeneratorPlayback
var ph := PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
var turbo_ph := 0.0
var squeal_ph := 0.0
var lp_noise := 0.0
var lp_wind := 0.0
var bp1 := 0.0
var bp2 := 0.0
var shift_dip := 0.0
var blowoff := 0.0
var thump := 0.0
var horn := false
var horn_ph := 0.0
var _last_throttle := 0.0
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	for p: Node in [engine_player, fx_player]:
		add_child(p)
	var g := AudioStreamGenerator.new(); g.mix_rate = RATE; g.buffer_length = 0.12
	engine_player.stream = g; engine_player.unit_size = 12.0; engine_player.max_distance = 300.0
	var g2 := AudioStreamGenerator.new(); g2.mix_rate = RATE; g2.buffer_length = 0.12
	fx_player.stream = g2
	engine_player.play(); fx_player.play()
	engine_pb = engine_player.get_stream_playback()
	fx_pb = fx_player.get_stream_playback()

func on_shift() -> void:
	shift_dip = 1.0
	if car and car.spec.turbo and _last_throttle > 0.6: blowoff = 1.0

func on_impact(strength: float) -> void:
	thump = clampf(strength / 20.0, 0.2, 1.0)

func _process(dt: float) -> void:
	if car == null or engine_pb == null: return
	global_position = car.global_position
	var vol: float = Game.settings.volume
	var rpm := car.rpm
	var thr := car.in_throttle
	if _last_throttle > 0.6 and thr < 0.2 and car.spec.turbo and rpm > car.spec.peak_rpm * 0.6: blowoff = 1.0
	_last_throttle = thr
	var fire := rpm / 60.0 * car.spec.cylinders * 0.5 * car.spec.engine_voice * 0.5
	var load := 0.35 + 0.65 * thr
	var n := engine_pb.get_frames_available()
	var inc := fire / RATE
	for i in n:
		ph[0] = fmod(ph[0] + inc, 1.0); ph[1] = fmod(ph[1] + inc * 2.0, 1.0); ph[2] = fmod(ph[2] + inc * 0.5, 1.0); ph[3] = fmod(ph[3] + inc * 3.0, 1.0)
		var saw: float = (ph[0] * 2.0 - 1.0)
		var s: float = saw * 0.35 + sin(ph[1] * TAU) * 0.25 + sin(ph[2] * TAU) * 0.3 * load + sin(ph[3] * TAU) * 0.1
		lp_noise += (_rng.randf_range(-1, 1) - lp_noise) * 0.2
		s += lp_noise * 0.25 * load
		s = tanh(s * (1.2 + load)) * (0.25 + 0.3 * load) * (1.0 - shift_dip * 0.7)
		if car.spec.turbo:
			turbo_ph = fmod(turbo_ph + (900.0 + rpm * 0.9) / RATE, 1.0)
			s += sin(turbo_ph * TAU) * 0.035 * thr * clampf(rpm / car.spec.redline, 0, 1)
		if blowoff > 0.0:
			s += _rng.randf_range(-1, 1) * blowoff * 0.18
		engine_pb.push_frame(Vector2(s, s) * vol)
	shift_dip = maxf(shift_dip - dt * 8.0, 0.0)
	blowoff = maxf(blowoff - dt * 3.0, 0.0)
	# fx: tyre squeal (per surface), wind, suspension thumps, horn
	var kmh := absf(car.speed) * 3.6
	var slip := clampf((car.max_slip - 0.12) * 2.5, 0.0, 1.0)
	var on_road := car.surface <= 1
	var wind := clampf(kmh / 280.0, 0.0, 1.0)
	var m := fx_pb.get_frames_available()
	var sq_f := 900.0 + slip * 300.0
	for i in m:
		var wn := _rng.randf_range(-1, 1)
		lp_wind += (wn - lp_wind) * (0.02 + wind * 0.08)
		var s := lp_wind * wind * 0.5
		if slip > 0.0:
			if on_road:
				squeal_ph = fmod(squeal_ph + sq_f / RATE * (1.0 + 0.02 * sin(Time.get_ticks_msec() * 0.03)), 1.0)
				s += sin(squeal_ph * TAU) * 0.12 * slip + wn * 0.03 * slip
			else:
				bp1 += (wn - bp1) * 0.3; bp2 += (bp1 - bp2) * 0.3
				s += (bp1 - bp2) * 0.9 * slip
		if not on_road and kmh > 5.0:
			bp1 += (wn - bp1) * 0.15
			s += bp1 * 0.08 * clampf(kmh / 80.0, 0, 1)
		if thump > 0.0:
			s += sin(float(i) * 0.05) * thump * 0.5 + wn * thump * 0.2
		if horn:
			horn_ph = fmod(horn_ph + 410.0 / RATE, 1.0)
			s += (0.5 if horn_ph < 0.5 else -0.5) * 0.18 + sin(horn_ph * TAU * 1.26) * 0.08
		fx_pb.push_frame(Vector2(s, s) * vol)
	thump = maxf(thump - dt * 4.0, 0.0)
