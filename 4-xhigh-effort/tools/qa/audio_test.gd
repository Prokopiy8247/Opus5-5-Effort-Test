extends Node
## Offline check of the procedural engine: renders every profile at idle / mid / high RPM, writes
## WAVs to qa/tmp/audio/ for listening, and verifies the dominant pitch (autocorrelation) matches
## the firing frequency rpm/60 * cylinders/2 and that the signal is neither silent nor clipped.
##   godot --headless --path . -- --test-track --qa=audio_test

const AM := preload("res://scripts/audio/audio_manager.gd")


func _ready() -> void:
	var am: Node = AM.new()
	var out := []
	DirAccess.make_dir_recursive_absolute("res://qa/tmp/audio")
	for prof: StringName in AM.PROFILES:
		am.use_profile(prof, 7)
		var cyl: int = int(AM.PROFILES[prof].cyl)
		var pitch: float = float(AM.PROFILES[prof].pitch)
		for rpm: float in [900.0, 3500.0, 6500.0]:
			am.synth(4096, rpm, 0.8, 1.0)  # settle filters
			var buf: PackedVector2Array = am.synth(int(AM.MIX * 1.0), rpm, 0.8, 1.0)
			var mono := PackedFloat32Array()
			mono.resize(buf.size())
			var rms := 0.0
			var peak := 0.0
			for i in buf.size():
				mono[i] = buf[i].x
				rms += mono[i] * mono[i]
				peak = maxf(peak, absf(mono[i]))
			rms = sqrt(rms / mono.size())
			var expect := rpm * pitch / 60.0 * cyl / 2.0
			var f := _pitch(mono, expect)
			var level_ok := rms > 0.02 and peak < 0.999
			var strict := absf(f - expect) / expect < 0.12
			var octave := strict or absf(f - expect * 2.0) / (expect * 2.0) < 0.12 or absf(f - expect * 0.5) / (expect * 0.5) < 0.12
			out.append({"profile": String(prof), "rpm": rpm, "expect_hz": snappedf(expect, 0.1), "found_hz": snappedf(f, 0.1),
				"rms": snappedf(rms, 0.001), "peak": snappedf(peak, 0.001), "strict": strict and level_ok, "ok": octave and level_ok})
			if rpm == 3500.0:
				_write_wav("res://qa/tmp/audio/engine_%s_3500.wav" % prof, mono)
	var bad := out.filter(func(e: Dictionary) -> bool: return not e.ok)
	var strict_n := out.filter(func(e: Dictionary) -> bool: return e.strict).size()
	print("AUDIO_TEST ", JSON.stringify({"cases": out.size(), "pitch_exact": strict_n, "pitch_octave_or_exact": out.size() - bad.size(), "failed": bad}))
	for e: Dictionary in out:
		print("  ", e)
	am.free()
	get_tree().quit(0)


## Pitch by normalised autocorrelation over 0.5x .. 2x the expected period, taking the shortest
## lag whose correlation reaches 90 % of the best (avoids octave errors from sub-harmonics).
func _pitch(x: PackedFloat32Array, expect: float) -> float:
	var lo := maxi(int(AM.MIX / (expect * 2.0)), 2)
	var hi := int(AM.MIX / (expect * 0.5))
	var n := mini(x.size() - hi - 1, 8000)
	var mean := 0.0
	for i in n + hi:
		mean += x[i]
	mean /= n + hi
	var r := PackedFloat32Array()
	r.resize(hi + 1)
	var best := -1.0
	for lag in range(lo, hi + 1):
		var s := 0.0
		var e0 := 0.0
		var e1 := 0.0
		for i in n:
			var a := x[i] - mean
			var b := x[i + lag] - mean
			s += a * b
			e0 += a * a
			e1 += b * b
		r[lag] = s / sqrt(maxf(e0 * e1, 1e-12))
		best = maxf(best, r[lag])
	for lag in range(lo + 1, hi):
		if r[lag] >= 0.9 * best and r[lag] >= r[lag - 1] and r[lag] >= r[lag + 1]:
			return AM.MIX / lag
	return AM.MIX / lo


func _write_wav(path: String, data: PackedFloat32Array) -> void:
	var bytes := PackedByteArray()
	bytes.resize(data.size() * 2)
	for i in data.size():
		bytes.encode_s16(i * 2, int(clampf(data[i], -1.0, 1.0) * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = int(AM.MIX)
	w.data = bytes
	w.save_to_wav(path)
