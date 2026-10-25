class_name SoundBank
extends RefCounted
## Procedurally generated, project-owned sound samples (no recorded/copyrighted audio).
## Loops and one-shots are synthesised once and cached as AudioStreamWAV (16-bit mono).

const RATE := 22050

static var _cache: Dictionary = {}


static func get_stream(key: String) -> AudioStreamWAV:
	if not _cache.has(key):
		_cache[key] = _generate(key)
	return _cache[key]


static func _wav(samples: PackedFloat32Array, loop: bool) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		var v := int(clampf(samples[i], -1.0, 1.0) * 32767.0)
		data.encode_s16(i * 2, v)
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = data
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = samples.size()
	return w


static func _crossfade_loop(s: PackedFloat32Array, fade: int) -> PackedFloat32Array:
	## Makes a buffer loop seamlessly by blending its tail into its head.
	var n := s.size()
	var out := PackedFloat32Array()
	out.resize(n - fade)
	for i in n - fade:
		out[i] = s[i]
	for i in fade:
		var t := float(i) / float(fade)
		out[i] = s[i] * t + s[n - fade + i] * (1.0 - t)
	return out


static func _normalize(s: PackedFloat32Array, peak: float) -> PackedFloat32Array:
	var m := 0.0001
	for v in s:
		m = maxf(m, absf(v))
	var k := peak / m
	for i in s.size():
		s[i] *= k
	return s


static func _generate(key: String) -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(key)
	var s := PackedFloat32Array()
	match key:
		"squeal":
			# tonal tyre squeal: narrow band noise around ~900 Hz with slow wobble
			var n := RATE * 2 + 2000
			s.resize(n)
			var bp1 := 0.0
			var bp2 := 0.0
			for i in n:
				var t := float(i) / RATE
				var f := 880.0 + sin(t * 3.1) * 60.0 + sin(t * 7.7) * 25.0
				var w := TAU * f / RATE
				var x := rng.randf_range(-1.0, 1.0)
				# resonant 2-pole filter
				var r := 0.995
				var y := x * 0.05 + 2.0 * r * cos(w) * bp1 - r * r * bp2
				bp2 = bp1
				bp1 = y
				s[i] = y + sin(TAU * f * t) * 0.15
			s = _normalize(_crossfade_loop(s, 2000), 0.8)
			return _wav(s, true)
		"gravel":
			var n := RATE * 2 + 1500
			s.resize(n)
			var lp := 0.0
			for i in n:
				var crackle := rng.randf_range(-1.0, 1.0) if rng.randf() < 0.18 else 0.0
				lp = lp * 0.55 + crackle * 0.45
				s[i] = lp + rng.randf_range(-0.15, 0.15)
			s = _normalize(_crossfade_loop(s, 1500), 0.7)
			return _wav(s, true)
		"dirt":
			var n := RATE * 2 + 1500
			s.resize(n)
			var lp := 0.0
			var lp2 := 0.0
			for i in n:
				lp = lp * 0.97 + rng.randf_range(-1.0, 1.0) * 0.03
				lp2 = lp2 * 0.8 + rng.randf_range(-1.0, 1.0) * 0.2
				s[i] = lp * 3.0 + lp2 * 0.25
			s = _normalize(_crossfade_loop(s, 1500), 0.7)
			return _wav(s, true)
		"grass":
			var n := RATE * 2 + 1500
			s.resize(n)
			var hp_prev := 0.0
			var lp := 0.0
			for i in n:
				var x := rng.randf_range(-1.0, 1.0)
				lp = lp * 0.6 + x * 0.4
				s[i] = (lp - hp_prev) * (0.6 + 0.4 * sin(float(i) / RATE * 9.0))
				hp_prev = lp * 0.9
			s = _normalize(_crossfade_loop(s, 1500), 0.5)
			return _wav(s, true)
		"wind":
			var n := RATE * 3 + 3000
			s.resize(n)
			var lp := 0.0
			var lp2 := 0.0
			for i in n:
				var t := float(i) / RATE
				lp = lp * 0.985 + rng.randf_range(-1.0, 1.0) * 0.015
				lp2 = lp2 * 0.9 + rng.randf_range(-1.0, 1.0) * 0.1
				s[i] = lp * (1.0 + 0.4 * sin(t * 1.3)) * 4.0 + lp2 * 0.3
			s = _normalize(_crossfade_loop(s, 3000), 0.8)
			return _wav(s, true)
		"rain":
			var n := RATE * 3 + 3000
			s.resize(n)
			var lp := 0.0
			for i in n:
				var drop := rng.randf_range(-1.0, 1.0) * (1.0 if rng.randf() < 0.08 else 0.25)
				lp = lp * 0.5 + drop * 0.5
				s[i] = lp
			s = _normalize(_crossfade_loop(s, 3000), 0.6)
			return _wav(s, true)
		"sea":
			var n := RATE * 6 + 4000
			s.resize(n)
			var lp := 0.0
			for i in n:
				var t := float(i) / RATE
				lp = lp * 0.96 + rng.randf_range(-1.0, 1.0) * 0.04
				var env := pow(0.5 + 0.5 * sin(t * TAU / 6.0), 2.0) * 0.8 + 0.2
				s[i] = lp * env * 4.0
			s = _normalize(_crossfade_loop(s, 4000), 0.7)
			return _wav(s, true)
		"birds":
			var n := RATE * 6
			s.resize(n)
			var chirps := 14
			for c in chirps:
				var start := rng.randi_range(0, n - RATE / 2)
				var f0 := rng.randf_range(2400.0, 4200.0)
				var dur := rng.randf_range(0.05, 0.16)
				var count := rng.randi_range(2, 5)
				for k in count:
					var st := start + int(k * dur * 1.6 * RATE)
					var len_s := int(dur * RATE)
					var ph := 0.0
					for i in len_s:
						if st + i >= n:
							break
						var t := float(i) / float(len_s)
						var f := f0 * (1.0 + 0.35 * sin(t * PI)) * (1.0 - 0.2 * t)
						ph += TAU * f / RATE
						s[st + i] += sin(ph) * sin(t * PI) * 0.4
			s = _normalize(s, 0.5)
			return _wav(s, true)
		"crickets":
			var n := RATE * 2
			s.resize(n)
			for i in n:
				var t := float(i) / RATE
				var gate := 1.0 if fmod(t * 14.0, 1.0) < 0.45 and fmod(t, 0.7) < 0.42 else 0.0
				s[i] = sin(TAU * 4300.0 * t) * gate * 0.4
			return _wav(s, true)
		"horn":
			var n := RATE
			s.resize(n)
			for i in n:
				var t := float(i) / RATE
				var a := 0.0
				for h in [1.0, 2.0, 3.0, 4.0]:
					a += sin(TAU * 410.0 * h * t) / h + sin(TAU * 515.0 * h * t) / h
				s[i] = clampf(a * 0.35, -0.9, 0.9)
			return _wav(s, true)
		"impact":
			var n := int(RATE * 0.6)
			s.resize(n)
			var lp := 0.0
			for i in n:
				var t := float(i) / RATE
				lp = lp * 0.7 + rng.randf_range(-1.0, 1.0) * 0.3
				s[i] = (sin(TAU * 62.0 * t) * 0.9 + lp * 0.8) * exp(-t * 9.0)
			s = _normalize(s, 0.95)
			return _wav(s, false)
		"thump":
			var n := int(RATE * 0.25)
			s.resize(n)
			for i in n:
				var t := float(i) / RATE
				s[i] = sin(TAU * (70.0 - t * 120.0) * t) * exp(-t * 22.0)
			s = _normalize(s, 0.9)
			return _wav(s, false)
		"shift":
			var n := int(RATE * 0.12)
			s.resize(n)
			for i in n:
				var t := float(i) / RATE
				s[i] = (rng.randf_range(-1.0, 1.0) * 0.5 + sin(TAU * 180.0 * t)) * exp(-t * 45.0)
			s = _normalize(s, 0.6)
			return _wav(s, false)
		"pop":
			var n := int(RATE * 0.09)
			s.resize(n)
			var lp := 0.0
			for i in n:
				var t := float(i) / RATE
				lp = lp * 0.4 + rng.randf_range(-1.0, 1.0) * 0.6
				s[i] = lp * exp(-t * 60.0)
			s = _normalize(s, 0.9)
			return _wav(s, false)
		"blowoff":
			var n := int(RATE * 0.45)
			s.resize(n)
			var lp := 0.0
			for i in n:
				var t := float(i) / RATE
				var x := rng.randf_range(-1.0, 1.0)
				lp = lp * (0.3 + t) + x * (0.7 - t)
				s[i] = (x - lp) * exp(-t * 7.0)
			s = _normalize(s, 0.6)
			return _wav(s, false)
		"chime":
			var n := int(RATE * 0.8)
			s.resize(n)
			for i in n:
				var t := float(i) / RATE
				s[i] = (sin(TAU * 880.0 * t) + sin(TAU * 1320.0 * t) * 0.6 + sin(TAU * 1760.0 * t) * 0.3) * exp(-t * 5.0) * 0.5
			return _wav(s, false)
		"checkpoint":
			var n := int(RATE * 0.35)
			s.resize(n)
			for i in n:
				var t := float(i) / RATE
				var f := 1046.0 if t < 0.12 else 1568.0
				s[i] = sin(TAU * f * t) * exp(-fmod(t, 0.12) * 12.0) * 0.5
			return _wav(s, false)
		"traffic_engine":
			# generic idle/drive hum for traffic vehicles (pitched by speed)
			var n := RATE + 1000
			s.resize(n)
			var ph := 0.0
			var lp := 0.0
			for i in n:
				ph += TAU * 55.0 / RATE
				lp = lp * 0.9 + rng.randf_range(-1.0, 1.0) * 0.1
				s[i] = (sin(ph) * 0.6 + sin(ph * 2.0) * 0.3 + sin(ph * 3.0) * 0.15) * (0.8 + lp) + lp * 0.3
			s = _normalize(_crossfade_loop(s, 1000), 0.7)
			return _wav(s, true)
	s.resize(RATE / 10)
	return _wav(s, false)
