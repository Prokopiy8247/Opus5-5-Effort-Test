class_name SoundSynth
extends RefCounted
## Project-owned procedural sounds rendered into looping AudioStreamWAV buffers.

const RATE := 44100
static var _cache := {}


static func _wav(samples: PackedFloat32Array, loop: bool) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		var v := int(clampf(samples[i], -1.0, 1.0) * 32000.0)
		bytes.encode_s16(i * 2, v)
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = bytes
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = samples.size()
	return w


## Engine loop at base_rpm. load_layer=true gives the rich on-throttle sound.
static func engine(cylinders: int, roughness: float, base_rpm: float, load_layer: bool, seed_v: int) -> AudioStreamWAV:
	var key := "eng_%d_%.2f_%d_%s_%d" % [cylinders, roughness, int(base_rpm), load_layer, seed_v]
	if _cache.has(key):
		return _cache[key]
	var fire := base_rpm / 60.0 * cylinders * 0.5
	var crank := base_rpm / 60.0
	var cycles := int(round(fire * 0.5))  # half a second, an integer number of firing cycles
	var length := int(round(cycles / fire * RATE))
	var out := PackedFloat32Array()
	out.resize(length)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var cyc_amp := PackedFloat32Array()
	var n_cyc := cycles + 2
	cyc_amp.resize(n_cyc)
	for c in n_cyc:
		cyc_amp[c] = 1.0 + rng.randf_range(-1.0, 1.0) * roughness * 0.35
	var harm := [1.0, 0.55, 0.32, 0.22, 0.12, 0.08, 0.05] if load_layer else [1.0, 0.3, 0.12, 0.06, 0.03, 0.0, 0.0]
	var sub := 0.45 * roughness if cylinders >= 8 else 0.15 * roughness
	var noise_amp := 0.06 if load_layer else 0.03
	var lp := 0.0
	for i in length:
		var t := float(i) / RATE
		var phase := t * fire
		var cidx := int(phase) % n_cyc
		var s := 0.0
		for h in harm.size():
			s += sin(TAU * phase * (h + 1)) * harm[h]
		# crank-order sub harmonic: the V8 burble
		s += sin(TAU * t * crank * 0.5 * 2.0) * sub
		# combustion pulse shape
		var pulse := pow(maxf(sin(TAU * phase), 0.0), 3.0) * (0.6 if load_layer else 0.3)
		s = s * 0.35 + pulse
		s *= cyc_amp[cidx]
		var nz := rng.randf_range(-1.0, 1.0) * noise_amp
		lp += (nz - lp) * 0.2
		s += lp
		out[i] = s * 0.42
	out = _fade_loop(_normalize(out, 0.8))
	var w := _wav(out, true)
	_cache[key] = w
	return w


static func noise_loop(kind: String) -> AudioStreamWAV:
	if _cache.has(kind):
		return _cache[kind]
	var length := RATE  # 1 s
	var out := PackedFloat32Array()
	out.resize(length)
	var rng := RandomNumberGenerator.new()
	rng.seed = kind.hash()
	var lp := 0.0
	var lp2 := 0.0
	var bp := 0.0
	for i in length:
		var t := float(i) / RATE
		var n := rng.randf_range(-1.0, 1.0)
		lp += (n - lp) * 0.08
		lp2 += (lp - lp2) * 0.08
		var s := 0.0
		match kind:
			"wind":
				s = lp2 * 2.2 * (0.8 + 0.2 * sin(TAU * t * 0.7))
			"squeal":
				# narrow-band screech around 1.1 kHz with wobble
				s = sin(TAU * t * (1100.0 + 60.0 * sin(TAU * t * 9.0))) * 0.5 + sin(TAU * t * 2230.0) * 0.18 + (n - lp) * 0.15
			"gravel":
				bp = n - lp
				s = bp * 0.6 * (0.7 + 0.3 * absf(sin(TAU * t * 23.0))) + lp2 * 0.6
			"rain":
				s = (n - lp) * 0.5 + lp * 0.4
			"sea":
				s = lp2 * 2.5 * (0.55 + 0.45 * sin(TAU * t * 1.0 - 1.5))
			"birds":
				s = lp2 * 0.15
				var chirp_t := fmod(t, 0.5)
				if chirp_t < 0.09 and int(t * 2.0) % 2 == 0:
					s += sin(TAU * (3200.0 + 2400.0 * chirp_t / 0.09) * t) * 0.35 * sin(PI * chirp_t / 0.09)
			"turbo":
				s = sin(TAU * t * 2400.0) * 0.4 + sin(TAU * t * 4810.0) * 0.12 + (n - lp) * 0.06
			"tunnel_hum":
				s = lp2 * 1.6 + sin(TAU * t * 50.0) * 0.05
			_:
				s = n
		out[i] = s
	out = _fade_loop(_normalize(out, 0.7))
	var w := _wav(out, true)
	_cache[kind] = w
	return w


static func one_shot(kind: String) -> AudioStreamWAV:
	if _cache.has("os_" + kind):
		return _cache["os_" + kind]
	var length := int(RATE * 0.6)
	var out := PackedFloat32Array()
	out.resize(length)
	var rng := RandomNumberGenerator.new()
	rng.seed = kind.hash()
	var lp := 0.0
	for i in length:
		var t := float(i) / RATE
		var n := rng.randf_range(-1.0, 1.0)
		lp += (n - lp) * 0.05
		var s := 0.0
		match kind:
			"impact":
				s = (lp * 3.0 + sin(TAU * t * 70.0) * 0.6) * exp(-t * 9.0)
			"thump":
				s = sin(TAU * t * (55.0 - t * 40.0)) * exp(-t * 14.0)
			"blowoff":
				s = (n - lp) * exp(-t * 6.0) * 0.8 * smoothstep(0.0, 0.02, t)
			"shift":
				s = (sin(TAU * t * 140.0) * 0.5 + lp) * exp(-t * 30.0)
			"horn":
				var env := smoothstep(0.0, 0.02, t) * (1.0 - smoothstep(0.45, 0.58, t))
				s = (signf(sin(TAU * t * 415.0)) * 0.35 + signf(sin(TAU * t * 523.0)) * 0.3) * env
				s = s * 0.6 + sin(TAU * t * 415.0) * 0.2 * env
			"checkpoint":
				var env2 := exp(-t * 7.0)
				s = (sin(TAU * t * 880.0) + sin(TAU * t * 1320.0) * 0.6) * env2 * (0.5 if t < 0.12 else 1.0)
			"fanfare":
				var note := 523.0 if t < 0.15 else (659.0 if t < 0.3 else 784.0)
				s = (sin(TAU * t * note) * 0.6 + sin(TAU * t * note * 2.0) * 0.2) * exp(-fmod(t, 0.15) * 6.0)
			"thunder":
				s = lp * 4.0 * exp(-t * 2.0)
			_:
				s = n * exp(-t * 10.0)
		out[i] = s
	out = _normalize(out, 0.85)
	var w := _wav(out, false)
	_cache["os_" + kind] = w
	return w


static func _normalize(a: PackedFloat32Array, peak: float) -> PackedFloat32Array:
	var m := 0.0001
	for v in a:
		m = maxf(m, absf(v))
	var k := peak / m
	for i in a.size():
		a[i] *= k
	return a


static func _fade_loop(a: PackedFloat32Array) -> PackedFloat32Array:
	# crossfade the tail into the head and drop the tail: the loop point becomes seamless
	var n := a.size()
	var f := int(n * 0.04)
	for i in f:
		var w := float(i) / f
		a[i] = a[i] * w + a[n - f + i] * (1.0 - w)
	a.resize(n - f)
	return a
