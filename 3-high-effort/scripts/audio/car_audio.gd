class_name CarAudio
extends Node
## Player car sound: engine (low/high rpm x on/off-throttle layers), turbo whine and blow-off,
## gear shifts, tyre squeal / gravel crunch per surface, wind, suspension thumps, impacts, horn.

const LOW_RPM := 1600.0
const HIGH_RPM := 4600.0

var car: Car
var eng := {}   # key -> AudioStreamPlayer
var turbo: AudioStreamPlayer
var squeal: AudioStreamPlayer
var gravel: AudioStreamPlayer
var wind: AudioStreamPlayer
var oneshot: AudioStreamPlayer
var horn: AudioStreamPlayer
var _prev_throttle := 0.0
var _prev_comp := []
var _thump_cd := 0.0


func setup(c: Car) -> void:
	car = c
	var s := car.spec
	var seed_v := s.id.hash()
	for layer: String in ["on_lo", "on_hi", "off_lo", "off_hi"]:
		var on := layer.begins_with("on")
		var base := LOW_RPM if layer.ends_with("lo") else HIGH_RPM
		var p := AudioStreamPlayer.new()
		p.stream = SoundSynth.engine(s.cylinders, s.sound_roughness, base * s.sound_base_pitch, on, seed_v + layer.hash())
		p.volume_db = -80.0
		p.bus = "Master"
		add_child(p)
		p.play()
		eng[layer] = p
	turbo = _loop("turbo", -80.0)
	squeal = _loop("squeal", -80.0)
	gravel = _loop("gravel", -80.0)
	wind = _loop("wind", -80.0)
	oneshot = AudioStreamPlayer.new()
	oneshot.max_polyphony = 4
	add_child(oneshot)
	horn = AudioStreamPlayer.new()
	horn.stream = SoundSynth.one_shot("horn")
	add_child(horn)
	car.gear_changed.connect(func(_g: int) -> void: _play("shift", -14.0))
	car.impact.connect(_on_impact)
	for w in car.wheels:
		_prev_comp.append(0.0)


func _loop(kind: String, db: float) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = SoundSynth.noise_loop(kind)
	p.volume_db = db
	add_child(p)
	p.play()
	return p


func _play(kind: String, db: float) -> void:
	var p := AudioStreamPlayer.new()
	p.stream = SoundSynth.one_shot(kind)
	p.volume_db = db
	p.pitch_scale = randf_range(0.92, 1.08)
	add_child(p)
	p.play()
	p.finished.connect(p.queue_free)


func _on_impact(s: float) -> void:
	if s > 3.0:
		_play("impact", linear_to_db(clampf(s / 25.0, 0.1, 1.0)) - 2.0)


func _unhandled_input(event: InputEvent) -> void:
	if car and car.is_player and car.controls_enabled and event.is_action_pressed("horn"):
		horn.pitch_scale = 1.0
		horn.play()


func _process(delta: float) -> void:
	var _t0 := Time.get_ticks_usec()
	_process_inner(delta)
	Game.prof_add("car_audio", Time.get_ticks_usec() - _t0)


func _process_inner(delta: float) -> void:
	if car == null or not is_instance_valid(car):
		return
	var vol: float = Game.settings.get("master_volume", 0.8)
	var rpm := car.rpm
	var thr := car.throttle_applied if car.shift_timer <= 0.0 else 0.0
	var hi := smoothstep(2000.0, 3600.0, rpm)
	var load_mix := clampf(thr * 1.2, 0.0, 1.0)
	var level := lerpf(0.45, 1.0, clampf(rpm / car.spec.redline_rpm, 0.0, 1.0))
	var g := level * vol
	_apply(eng.on_lo, g * load_mix * (1.0 - hi), rpm / (LOW_RPM * car.spec.sound_base_pitch))
	_apply(eng.on_hi, g * load_mix * hi, rpm / (HIGH_RPM * car.spec.sound_base_pitch))
	_apply(eng.off_lo, g * (1.0 - load_mix) * (1.0 - hi) * 0.75, rpm / (LOW_RPM * car.spec.sound_base_pitch))
	_apply(eng.off_hi, g * (1.0 - load_mix) * hi * 0.6, rpm / (HIGH_RPM * car.spec.sound_base_pitch))
	# turbo
	if car.spec.turbo:
		var boost := clampf((rpm - 2500.0) / 3500.0, 0.0, 1.0) * thr
		_apply(turbo, boost * 0.18 * vol, 0.7 + boost * 0.6)
		if _prev_throttle > 0.7 and thr < 0.2 and rpm > 3500.0:
			_play("blowoff", -12.0)
	_prev_throttle = thr
	# tyres
	var slip := 0.0
	var off := 0.0
	var paved := true
	if car.wheels_on_ground > 0:
		var surf := Game.surface(car.surface_id)
		paved = not surf.is_offroad
		for w in car.wheels:
			if w.contact:
				slip = maxf(slip, maxf((w.slip_lat - 1.0) * 0.6, w.slip_long))
		off = clampf(car.speed / 25.0, 0.0, 1.0) if not paved else 0.0
		var sq := clampf(slip, 0.0, 1.0) * surf.squeal
		_apply(squeal, sq * 0.55 * vol, 0.85 + clampf(car.speed / 60.0, 0.0, 0.4))
		_apply(gravel, (off * 0.5 + clampf(slip, 0.0, 1.0) * 0.4 * (0.0 if paved else 1.0)) * vol, 0.8 + off * 0.4)
	else:
		_apply(squeal, 0.0, 1.0)
		_apply(gravel, 0.0, 1.0)
	_apply(wind, clampf((car.speed - 8.0) / 70.0, 0.0, 1.0) * 0.6 * vol, 0.8 + clampf(car.speed / 80.0, 0.0, 0.6))
	# suspension thumps
	_thump_cd -= delta
	for i in car.wheels.size():
		var c := car.wheels[i].compression
		var dv: float = (c - _prev_comp[i]) / maxf(delta, 0.001)
		_prev_comp[i] = c
		if dv > 1.6 and _thump_cd <= 0.0:
			_thump_cd = 0.15
			_play("thump", linear_to_db(clampf(dv / 5.0, 0.15, 1.0)) - 4.0)


func _apply(p: AudioStreamPlayer, lin: float, pitch: float) -> void:
	p.volume_db = linear_to_db(maxf(lin, 0.0001))
	p.pitch_scale = clampf(pitch, 0.2, 4.0)
