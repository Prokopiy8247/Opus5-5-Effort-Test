extends Node3D
## Scripted in-engine test of CarAudio on the proving ground with the real audio device:
##   Godot_console.exe --path . --resolution 960x540 res://tools/tests/audio_car_test.tscn [-- --car=brute_68]
## Drives a timeline (idle/start flare, wheelspin launch + shifts, lift-off crackle/blow-off, ABS-off lock-up,
## handbrake slide, gravel, grass, horn, ramp jump, rain on the roof, an impact), logs every CarAudio layer
## level twice a second and records the master mix to qa_output/audio/car_test_<car>.wav.

const CAR_AUDIO := preload("res://scripts/audio/car_audio.gd")
const SfxBank := preload("res://scripts/audio/sfx_bank.gd")

var track: TestTrack
var car: CarController
var audio: Node
var cam: Camera3D
var rec: AudioEffectRecord
var t: float = 0.0
var _log_t: float = 0.0
var _phase: String = ""
var _ramp_done := false
var _impact_done := false
var _honked := false
var _car_id := "kestrel_r4"
var _max: Dictionary = {}


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--car="):
			_car_id = a.substr(6)
	track = TestTrack.new()
	add_child(track)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, 30, 0)
	add_child(sun)
	cam = Camera3D.new()
	add_child(cam)
	cam.make_current()
	var d: CarData = (load("res://data/cars/%s.tres" % _car_id) as CarData).duplicate(true)
	car = CarFactory.build(d, {}, true)
	add_child(car)
	car.place_at(Transform3D(Basis(), Vector3(0, 0.05, 2500.0)))
	Game.apply_assists_to(car)
	audio = CAR_AUDIO.new()
	audio.name = "CarAudio"
	car.add_child(audio)
	rec = AudioEffectRecord.new()
	AudioServer.add_bus_effect(AudioServer.get_bus_index(&"Master"), rec)
	rec.set_recording_active(true)
	print("[audio_car] car=%s driver=%s mix_rate=%d" % [_car_id, AudioServer.get_driver_name(), AudioServer.get_mix_rate()])


func _physics_process(delta: float) -> void:
	t += delta
	var thr := 0.0
	var brk := 0.0
	var hb := 0.0
	var steer := 0.0
	var surf := &"asphalt"
	var ph := ""
	car.assist_abs = true
	car.assist_tcs = true
	if t < 0.8:
		ph = "idle+start"
	elif t < 2.0:
		ph = "reverse (whine)"
		brk = 1.0
	elif t < 4.5:
		ph = "launch (TCS off)"
		thr = 1.0
		car.assist_tcs = false
	elif t < 6.0:
		ph = "lift-off"
	elif t < 8.0:
		ph = "full throttle"
		thr = 1.0
	elif t < 9.5:
		ph = "lock-up (ABS off)"
		brk = 1.0
		car.assist_abs = false
	elif t < 11.0:
		ph = "handbrake slide"
		thr = 0.6
		steer = 1.0
		hb = 1.0
	elif t < 11.5:
		ph = "recover"
	elif t < 14.5:
		ph = "gravel"
		surf = &"gravel"
		thr = 0.75
		steer = 0.15 * sin(t * 2.0)
	elif t < 17.0:
		ph = "grass"
		surf = &"grass"
		thr = 0.6
	elif t < 21.0:
		ph = "horn + ramp jump"
		thr = 1.0
		if not _honked:
			_honked = true
			audio.call("honk", 1.0)
		if not _ramp_done and t > 17.5:
			_ramp_done = true
			var f := -car.global_transform.basis.z
			f.y = 0.0
			var p := car.global_position + f.normalized() * maxf(car.speed_ms * 1.2, 20.0)
			track.add_ramp(Vector3(p.x, 0.0, p.z), 14.0, 1.8, 10.0)
	elif t < 23.5:
		ph = "rain on roof"
		thr = 0.5
		CarController.wetness = 0.9
	elif t < 25.0:
		ph = "impact"
		CarController.wetness = 0.0
		if not _impact_done:
			_impact_done = true
			car.impact.emit(9.5, car.global_position)
	else:
		_finish()
		return
	if surf != track.surface_id:
		track.set_surface(surf)
	if ph != _phase:
		_phase = ph
		print("[audio_car] t=%.1f phase: %s" % [t, ph])
	# Hold the heading straight unless the phase steers.
	if steer == 0.0:
		var fw := -car.global_transform.basis.z
		steer = clampf(-atan2(fw.x, -fw.z) * 1.5, -1.0, 1.0)
	car.in_throttle = thr
	car.in_brake = brk
	car.in_handbrake = hb
	car.in_steer = steer


func _process(delta: float) -> void:
	if car == null:
		return
	var xf := car.global_transform
	var back := xf.basis.z
	back.y = 0.0
	cam.global_transform = Transform3D(Basis.looking_at(-back.normalized(), Vector3.UP), xf.origin + back.normalized() * 6.5 + Vector3.UP * 2.2)
	_log_t += delta
	var layers: Dictionary = audio.get("_layers")
	for id: StringName in layers:
		_max[id] = maxf(float(_max.get(id, 0.0)), float(layers[id].lvl))
	if _log_t < 0.5:
		return
	_log_t = 0.0
	var parts := PackedStringArray()
	for id: StringName in layers:
		parts.append("%s=%.2f" % [id, layers[id].lvl])
	var w := car.dominant_surface()
	var syn := audio.get("synth") as RefCounted
	print("[audio_car] t=%.1f kmh=%.0f rpm=%d gear=%d skid=%.2f air=%.2f surf=%s boost=%.2f pops=%d whine=%.0fHz/%.3f | %s" % [
		t, car.get_speed_kmh(), int(car.rpm), car.gear, car.max_skid(), car.air_time, w.id if w else &"-",
		float(audio.get("_boost")), syn.get("pops_fired"), syn.get("whine_hz"), syn.get("whine_amp"), " ".join(parts)])


func _finish() -> void:
	set_physics_process(false)
	var wav := rec.get_recording()
	rec.set_recording_active(false)
	var path := ProjectSettings.globalize_path("res://qa_output/audio/car_test_%s.wav" % _car_id)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	if wav != null:
		wav.save_to_wav(path)
	print("[audio_car] layer peaks: %s" % str(_max))
	print("[audio_car] one-shots fired: %s" % str(audio.get("fired")))
	print("[audio_car] backfire signal test, synth pops=%d" % (audio.get("synth") as RefCounted).get("pops_fired"))
	print("[audio_car] capture %s (%.1f s)" % [path, wav.get_length() if wav else 0.0])
	print("AUDIO_CAR_TEST_DONE")
	get_tree().quit(0)
