extends Node3D
## Ambient soundscape (added by main.gd as "AmbientAudio"). Procedural beds crossfaded by the world's
## region weights at the camera: vale breeze + birds, highland wind gusts, mesa dry wind + daytime
## cicadas, coast surf + gulls near the shore. Rain / storm beds follow the weather, thunder follows
## Game.env's lightning(strength) signal, nights are quieter with crickets and the odd owl.
## QA only: --audio-capture=<res path> [--audio-capture-seconds=N] records the master mix to a WAV.

const SfxBank := preload("res://scripts/audio/sfx_bank.gd")

const BEDS: Array[StringName] = [&"bed_vale", &"bed_highlands", &"bed_mesa", &"bed_coast", &"rain", &"storm", &"crickets", &"cicadas"]
const BIRDS: Array[StringName] = [&"bird_0", &"bird_1", &"bird_2", &"bird_3"]
const GULLS: Array[StringName] = [&"gull_0", &"gull_1"]
const RAIN_BY_WEATHER := {"rain": 0.75, "storm": 1.0}
const WIND_BY_WEATHER := {"clear": 0.15, "cloudy": 0.4, "rain": 0.55, "fog": 0.05, "storm": 1.0}

var _beds: Dictionary = {}
var _lvl: Dictionary = {}
var _target: Dictionary = {}
var _spots: Array[AudioStreamPlayer3D] = []
var _spot_i: int = 0
var _shots: AudioStreamPlayer
var _shots_pb: AudioStreamPlaybackPolyphonic
var _pending_thunder: Array = []

var _weights := Color(1, 0, 0, 0)
var _shore: float = 0.0
var _shore_t: float = 0.0
var _shore_target: float = 0.0
var _sea_dir := Vector3.FORWARD
var _rain: float = 0.0
var _rain_t: float = 0.0
var _wind: float = 0.15
var _wind_t: float = 0.15
var _storm: float = 0.0
var _storm_t: float = 0.0
var _day: float = 1.0
var _hot: float = 1.0
var _hour: float = 12.0
var _alt: float = 0.0
var _duck: float = 1.0
var _duck_t: float = 1.0
var _tunnel: float = 0.0
var _tunnel_on: bool = false
var _query_t: float = 0.0
var _bird_t: float = 2.0
var _gull_t: float = 4.0
var _owl_t: float = 12.0
var _gust_t: float = 5.0
var _thunder_t: float = 15.0
var _lightning_connected: bool = false
var _env_check_t: float = 0.0
var _frames: int = 0

var _capture: AudioEffectRecord
var _capture_path: String = ""
var _capture_left: float = 0.0
var _qa: bool = false
var _stat_t: float = 0.0
var _stat_us: int = 0
var _stat_n: int = 0
var _thunder_count: int = 0
var _spot_count: int = 0


func _ready() -> void:
	if "--no-audio" in OS.get_cmdline_user_args():
		set_process(false)
		return
	SfxBank.ensure_buses()
	if not Settings.changed.is_connected(_on_setting):
		Settings.changed.connect(_on_setting)
	for id in BEDS:
		var p := AudioStreamPlayer.new()
		p.bus = SfxBank.BUS_AMBIENT
		add_child(p)
		_beds[id] = p
		_lvl[id] = 0.0
		_target[id] = 0.0
	for i in 4:
		var s := AudioStreamPlayer3D.new()
		s.bus = SfxBank.BUS_AMBIENT
		s.unit_size = 14.0
		s.max_distance = 260.0
		s.area_mask = 0
		s.attenuation_filter_cutoff_hz = 7000.0
		add_child(s)
		_spots.append(s)
	_shots = AudioStreamPlayer.new()
	_shots.bus = SfxBank.BUS_AMBIENT
	var poly := AudioStreamPolyphonic.new()
	poly.polyphony = 6
	_shots.stream = poly
	add_child(_shots)
	_shots.play()
	_shots_pb = _shots.get_stream_playback() as AudioStreamPlaybackPolyphonic
	_connect_env()
	var cap_secs := 60.0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--qa="):
			_qa = true
		elif a.begins_with("--audio-capture="):
			_capture_path = a.substr(16)
		elif a.begins_with("--audio-capture-seconds="):
			cap_secs = a.substr(24).to_float()
	if _capture_path != "":
		_start_capture(cap_secs)


func _exit_tree() -> void:
	_finish_capture()
	SfxBank.shutdown()


func _process(delta: float) -> void:
	var t0 := Time.get_ticks_usec()
	SfxBank.poll()
	_frames += 1
	if _frames == 3:
		# Let the player car queue its own samples first.
		SfxBank.prefetch(SfxBank.AMBIENT_IDS)
	var cam := get_viewport().get_camera_3d()
	var pos := cam.global_position if cam != null else Vector3.ZERO
	_query_t -= delta
	if _query_t <= 0.0:
		_query_t = 0.25
		_query(pos)
	_shore_t -= delta
	if _shore_t <= 0.0:
		_shore_t = 1.0
		_query_shore(pos)
	if not _lightning_connected:
		_env_check_t -= delta
		if _env_check_t <= 0.0:
			_env_check_t = 1.0
			_connect_env()
	var k := 1.0 - exp(-delta / 2.5)
	_rain += (_rain_t - _rain) * k
	_wind += (_wind_t - _wind) * k
	_storm += (_storm_t - _storm) * k
	_shore += (_shore_target - _shore) * (1.0 - exp(-delta / 1.5))
	_duck += (_duck_t - _duck) * (1.0 - exp(-delta * 3.0))
	_tunnel = move_toward(_tunnel, 1.0 if _tunnel_on else 0.0, delta * 2.0)
	_update_beds(delta)
	_update_spots(delta, pos)
	_update_thunder(delta)
	_update_capture(delta)
	if _qa:
		_stat_us += Time.get_ticks_usec() - t0
		_stat_n += 1
		_stat_t += delta
		if _stat_t >= 5.0:
			_stat_t = 0.0
			_log()
			_stat_us = 0
			_stat_n = 0


# ------------------------------------------------------------------ world queries

func _query(pos: Vector3) -> void:
	if Game.world is World and (Game.world as World).data != null:
		var w := (Game.world as World).data.region_weights_at(pos.x, pos.z)
		var sum := w.r + w.g + w.b + w.a
		_weights = Color(w.r / sum, w.g / sum, w.b / sum, w.a / sum) if sum > 0.01 else Color(1, 0, 0, 0)
		_alt = clampf((pos.y - 120.0) / 300.0, 0.0, 1.0)
	_tunnel_on = SfxBank.tunnel_at(pos)
	_hour = Game.get_time_of_day()
	_day = smoothstep(5.2, 6.8, _hour) * (1.0 - smoothstep(19.2, 20.8, _hour))
	_hot = smoothstep(8.5, 11.0, _hour) * (1.0 - smoothstep(17.5, 19.5, _hour))
	var env: Node = Game.env
	if env != null and env.has_method(&"get_rain") and env.has_method(&"get_wind_strength"):
		# Blended values follow the weather transition; tunnels are ducked by _tunnel instead.
		_rain_t = clampf(float(env.call(&"get_rain")), 0.0, 1.0)
		_wind_t = clampf(float(env.call(&"get_wind_strength")), 0.0, 1.0)
	else:
		var wid := String(Game.get_weather())
		_rain_t = float(RAIN_BY_WEATHER.get(wid, 0.0))
		_wind_t = float(WIND_BY_WEATHER.get(wid, 0.2))
	_storm_t = clampf((_wind_t - 0.7) / 0.3, 0.0, 1.0) * _rain_t
	var car := Game.player_car
	var spd := car.speed_ms if car != null and is_instance_valid(car) else 0.0
	_duck_t = lerpf(1.0, 0.55, clampf(spd / 55.0, 0.0, 1.0))


## How much sea surrounds the listener (surf is loudest on the shore line) and the direction to it.
func _query_shore(pos: Vector3) -> void:
	if not (Game.world is World) or (Game.world as World).data == null:
		_shore_target = 0.0
		return
	var wd := (Game.world as World).data
	var wet := 0.0
	var total := 0.0
	var dir := Vector3.ZERO
	for ring: float in [40.0, 110.0, 220.0]:
		var wgt := 1.0 / (1.0 + ring / 80.0)
		for i in 8:
			var a := TAU * i / 8.0
			var d := Vector3(cos(a), 0.0, sin(a))
			var p := pos + d * ring
			total += wgt
			if wd.height_at(p.x, p.z) < WorldLayout.SEA_LEVEL + 0.3:
				wet += wgt
				dir += d * wgt
	var frac := wet / total
	var height_f := clampf(1.0 - (pos.y - 25.0) / 140.0, 0.3, 1.0)
	_shore_target = clampf(frac * 3.0, 0.0, 1.0) * (1.0 - clampf((frac - 0.75) * 2.0, 0.0, 0.5)) * height_f
	if dir.length() > 0.01:
		_sea_dir = dir.normalized()


# ------------------------------------------------------------------ beds

func _update_beds(delta: float) -> void:
	var w := _weights
	var night := 1.0 - _day
	var quiet := lerpf(1.0, 0.6, night)
	var windf := 0.7 + 0.6 * _wind
	var dry := 1.0 - _rain
	_target[&"bed_vale"] = w.r * 0.5 * quiet * windf
	_target[&"bed_highlands"] = w.g * (0.45 + 0.35 * _alt) * windf
	_target[&"bed_mesa"] = w.b * 0.5 * lerpf(1.0, 0.75, night) * windf
	_target[&"bed_coast"] = w.a * (0.2 + 0.8 * _shore) * 0.75 * lerpf(1.0, 0.8, night)
	_target[&"cicadas"] = w.b * _hot * 0.32 * dry
	_target[&"crickets"] = night * (w.r + w.b * 0.8 + w.a * 0.5 + w.g * 0.2) * 0.3 * dry
	_target[&"rain"] = _rain * 0.55 * (1.0 - _storm * 0.5)
	_target[&"storm"] = _storm * 0.45
	var master := _duck * lerpf(1.0, 0.18, _tunnel)
	var k := 1.0 - exp(-delta * 1.2)
	for id in BEDS:
		var lv: float = _lvl[id]
		lv += (float(_target[id]) * master - lv) * k
		_lvl[id] = lv
		var p: AudioStreamPlayer = _beds[id]
		if lv < 0.002:
			if p.playing:
				p.stop()
			continue
		if p.stream == null:
			p.stream = SfxBank.peek(id)
			if p.stream == null:
				continue
		p.volume_db = linear_to_db(lv)
		if not p.playing:
			p.play(randf() * p.stream.get_length())


# ------------------------------------------------------------------ spot sounds

func _update_spots(delta: float, pos: Vector3) -> void:
	var w := _weights
	var open := 1.0 - _tunnel
	_bird_t -= delta
	if _bird_t <= 0.0:
		var chance := (w.r + 0.35 * w.g + 0.25 * w.a) * _day * (1.0 - _rain) * open
		var dawn := 1.0 + 1.5 * smoothstep(5.0, 6.5, _hour) * (1.0 - smoothstep(7.5, 9.0, _hour))
		_bird_t = randf_range(1.2, 4.5) / maxf(chance * dawn, 0.2)
		if chance > 0.12 and randf() < chance * dawn:
			_spot(BIRDS.pick_random(), pos + _ring_offset(12.0, 40.0, 3.0, 12.0), 0.35 + 0.3 * randf(), randf_range(0.9, 1.15))
	_gull_t -= delta
	if _gull_t <= 0.0:
		_gull_t = randf_range(4.0, 11.0)
		var g := w.a * _shore * _day * (1.0 - _rain * 0.7) * open
		if g > 0.15 and randf() < g * 1.3:
			var p := pos + _sea_dir * randf_range(25.0, 70.0) + Vector3(randf_range(-30.0, 30.0), randf_range(12.0, 30.0), randf_range(-30.0, 30.0))
			_spot(GULLS.pick_random(), p, 0.55, randf_range(0.92, 1.1))
	_owl_t -= delta
	if _owl_t <= 0.0:
		_owl_t = randf_range(14.0, 30.0)
		if (1.0 - _day) * (w.r + w.g * 0.6) * (1.0 - _rain) * open > 0.4:
			_spot(&"owl", pos + _ring_offset(40.0, 80.0, 6.0, 14.0), 0.4, randf_range(0.95, 1.05))
	_gust_t -= delta
	if _gust_t <= 0.0:
		_gust_t = randf_range(5.0, 12.0)
		var hg := w.g * (0.5 + 0.5 * _alt) + w.b * 0.35
		if hg > 0.2 and randf() < hg * (0.6 + 0.6 * _wind):
			_shot(&"gust", 0.25 + 0.35 * hg, randf_range(0.85, 1.1) * (1.15 if w.b > w.g else 1.0))
	if not _lightning_connected and _storm > 0.5:
		_thunder_t -= delta
		if _thunder_t <= 0.0:
			_thunder_t = randf_range(12.0, 30.0)
			_on_lightning(randf_range(0.2, 0.55))


func _ring_offset(r0: float, r1: float, h0: float, h1: float) -> Vector3:
	var a := randf() * TAU
	var r := randf_range(r0, r1)
	return Vector3(cos(a) * r, randf_range(h0, h1), sin(a) * r)


func _spot(id: StringName, at: Vector3, lin: float, pitch: float) -> void:
	var s := SfxBank.peek(id)
	if s == null or _spots.is_empty():
		return
	var sp := _spots[_spot_i]
	_spot_i = (_spot_i + 1) % _spots.size()
	sp.stream = s
	sp.global_position = at
	sp.volume_db = linear_to_db(maxf(lin * _duck, 0.0001))
	sp.pitch_scale = pitch
	sp.play()
	_spot_count += 1


func _shot(id: StringName, lin: float, pitch: float) -> void:
	var s := SfxBank.peek(id)
	if s == null or _shots_pb == null:
		return
	if not _shots.playing:
		_shots.play()
		_shots_pb = _shots.get_stream_playback() as AudioStreamPlaybackPolyphonic
	var g := lin * _duck * lerpf(1.0, 0.3, _tunnel)
	_shots_pb.play_stream(s, 0.0, linear_to_db(maxf(g, 0.0001)), pitch, AudioServer.PLAYBACK_TYPE_DEFAULT, SfxBank.BUS_AMBIENT)


# ------------------------------------------------------------------ thunder

func _connect_env() -> void:
	var env: Node = Game.env
	if env == null or _lightning_connected:
		return
	for sig: Dictionary in env.get_signal_list():
		if String(sig["name"]) != "lightning":
			continue
		var argc := (sig["args"] as Array).size()
		var cb: Callable = _on_lightning if argc >= 1 else _on_lightning_now
		if argc > 1:
			cb = cb.unbind(argc - 1)
		env.connect(&"lightning", cb)
		_lightning_connected = true
		return


func _on_lightning_now() -> void:
	_on_lightning(0.8)


## Thunder after a distance-dependent delay: strong strikes are near (sharp crack), weak ones distant rumble.
func _on_lightning(strength: float) -> void:
	var s := clampf(strength, 0.0, 1.0)
	var delay := lerpf(3.0, 0.15, s) + randf() * 0.4
	_pending_thunder.append([delay, &"thunder_near" if s > 0.6 else &"thunder_far", 0.45 + 0.55 * s])


func _update_thunder(delta: float) -> void:
	for i in range(_pending_thunder.size() - 1, -1, -1):
		var t: Array = _pending_thunder[i]
		t[0] = float(t[0]) - delta
		if float(t[0]) <= 0.0:
			_shot(t[1], float(t[2]), randf_range(0.9, 1.05))
			_pending_thunder.remove_at(i)
			_thunder_count += 1


# ------------------------------------------------------------------ settings / QA

func _on_setting(key: String, _value: Variant) -> void:
	if key.begins_with("volume_"):
		SfxBank.apply_volumes()


func _start_capture(seconds: float) -> void:
	var master := AudioServer.get_bus_index(&"Master")
	_capture = AudioEffectRecord.new()
	AudioServer.add_bus_effect(master, _capture)
	_capture.set_recording_active(true)
	_capture_left = seconds
	print("[audio] capturing master mix for %.0f s -> %s" % [seconds, _capture_path])


func _update_capture(delta: float) -> void:
	if _capture == null:
		return
	_capture_left -= delta
	if _capture_left <= 0.0:
		_finish_capture()


func _finish_capture() -> void:
	if _capture == null:
		return
	var wav := _capture.get_recording()
	_capture.set_recording_active(false)
	var master := AudioServer.get_bus_index(&"Master")
	for i in AudioServer.get_bus_effect_count(master):
		if AudioServer.get_bus_effect(master, i) == _capture:
			AudioServer.remove_bus_effect(master, i)
			break
	_capture = null
	if wav == null:
		print("[audio] capture: no data")
		return
	var path := ProjectSettings.globalize_path(_capture_path)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var err := wav.save_to_wav(path)
	print("[audio] capture saved %s (%.1f s, err %d)" % [path, wav.get_length(), err])


func _log() -> void:
	var parts: PackedStringArray = []
	for id in BEDS:
		parts.append("%s=%.2f" % [id, float(_lvl[id])])
	print("[audio] ambient %.0f us/frame hour=%.1f weights=(%.2f,%.2f,%.2f,%.2f) shore=%.2f day=%.2f rain=%.2f storm=%.2f wind=%.2f tunnel=%.2f duck=%.2f lightning_signal=%s thunder_played=%d spots_played=%d %s" % [
		float(_stat_us) / maxi(_stat_n, 1), _hour, _weights.r, _weights.g, _weights.b, _weights.a, _shore, _day, _rain, _storm,
		_wind, _tunnel, _duck, str(_lightning_connected), _thunder_count, _spot_count, " ".join(parts)])
