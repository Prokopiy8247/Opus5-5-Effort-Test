extends Node
## World audio: region ambience (birds, sea, wind), rain, thunder, tunnel reverb, horns of
## traffic, UI/event stingers. Lives at /root/Main/Audio.

var main: Node
var birds: AudioStreamPlayer
var sea: AudioStreamPlayer
var wind: AudioStreamPlayer
var rain: AudioStreamPlayer
var _reverb: AudioEffectReverb
var _last_flash := 0.0
var _frame := 0
var _in_tunnel := false


func setup(m: Node) -> void:
	main = m
	name = "Audio"
	birds = _loop("birds")
	sea = _loop("sea")
	wind = _loop("wind")
	rain = _loop("rain")
	_reverb = AudioEffectReverb.new()
	_reverb.room_size = 0.6
	_reverb.damping = 0.4
	_reverb.wet = 0.0
	_reverb.dry = 1.0
	AudioServer.add_bus_effect(0, _reverb)


func _loop(kind: String) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = SoundSynth.noise_loop(kind)
	p.volume_db = -80.0
	add_child(p)
	p.play()
	return p


func play(kind: String, db: float = -6.0) -> void:
	var p := AudioStreamPlayer.new()
	p.stream = SoundSynth.one_shot(kind)
	p.volume_db = db
	add_child(p)
	p.play()
	p.finished.connect(p.queue_free)


func play_horn_at(pos: Vector3, type_key: String) -> void:
	var p := AudioStreamPlayer3D.new()
	p.stream = SoundSynth.one_shot("horn")
	p.pitch_scale = 0.75 if type_key in ["lorry", "coach", "tractor"] else 1.0
	p.unit_size = 18.0
	p.max_distance = 220.0
	add_child(p)
	p.global_position = pos
	p.play()
	p.finished.connect(p.queue_free)


func _process(delta: float) -> void:
	var _t0 := Time.get_ticks_usec()
	_process_inner(delta)
	Game.prof_add("audio_mgr", Time.get_ticks_usec() - _t0)


func _process_inner(delta: float) -> void:
	if main == null or main.player == null or Game.world == null:
		return
	var vol: float = Game.settings.get("master_volume", 0.8)
	var p: Vector3 = main.player.global_position
	var w: Color = Game.world.data.region_weights(p.x, p.z)
	var night := Game.time_of_day < 6.0 or Game.time_of_day > 21.0
	var coast_d: float = WorldGen.coast_x(p.z) - p.x
	var sea_v := clampf(1.0 - coast_d / 350.0, 0.0, 1.0)
	var rainv: float = Game.world.sky.s_rain
	_fade(birds, (w.r + w.a * 0.5) * (0.0 if night else 0.35) * (1.0 - rainv) * vol, delta)
	_fade(sea, sea_v * 0.5 * vol, delta)
	_fade(wind, (0.12 + w.g * 0.3 + w.b * 0.25 + rainv * 0.2) * vol, delta)
	_fade(rain, rainv * 0.55 * vol, delta)
	# thunder after lightning flashes
	var flash: float = Game.world.sky._flash
	if flash > 0.9 and _last_flash < 0.9:
		get_tree().create_timer(randf_range(0.6, 2.5)).timeout.connect(func() -> void: play("thunder", -4.0))
	_last_flash = flash
	# tunnel reverb
	_frame += 1
	if _frame % 15 == 0:
		_in_tunnel = false
		var nr: Dictionary = Game.world.data.nearest_road(p, 12.0)
		if not nr.is_empty():
			var road: WorldData.Road = nr.road
			_in_tunnel = road.flags[nr.seg] == 2
	var in_tunnel := _in_tunnel
	_reverb.wet = lerpf(_reverb.wet, 0.45 if in_tunnel else 0.0, clampf(delta * 3.0, 0.0, 1.0))


func _fade(pl: AudioStreamPlayer, lin: float, delta: float) -> void:
	var cur := db_to_linear(pl.volume_db)
	cur = lerpf(cur, lin, clampf(delta * 1.5, 0.0, 1.0))
	pl.volume_db = linear_to_db(maxf(cur, 0.0001))
