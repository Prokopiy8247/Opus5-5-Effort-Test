class_name EngineSynth
extends RefCounted
## Real-time wavetable engine synthesiser (AudioStreamGenerator).
## One table holds one 4-stroke engine cycle (two crank revolutions) built from N cylinder
## firing pulses with per-car character (cylinder count, uneven firing for big V8s,
## timbre/resonance, roughness). Two tables (on/off load) are blended by throttle; noise,
## turbo whistle and a load-dependent low-pass are added per sample.

const TABLE := 1024
const MASK := TABLE - 1

var on_table := PackedFloat32Array()
var off_table := PackedFloat32Array()
var phase: float = 0.0
var whistle_phase: float = 0.0
var lp: float = 0.0
var lp2: float = 0.0
var noise_lp: float = 0.0
var roughness: float = 0.3
var turbo: bool = false
var _buf := PackedVector2Array()
var _seed: int = 1


func setup(def: CarDefinition) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(def.id)
	var n := maxi(def.cylinders, 1)
	roughness = def.engine_roughness
	turbo = def.turbo
	var offsets: Array[float] = []
	var amps: Array[float] = []
	var uneven := [0.0, 0.035, -0.02, 0.03, 0.0, -0.035, 0.02, -0.03, 0.01, -0.01, 0.015, -0.015]
	for c in n:
		var o := float(c) / float(n)
		if n == 8 or n <= 2:
			o += uneven[c % uneven.size()] * (0.4 + roughness)
		else:
			o += uneven[c % uneven.size()] * roughness * 0.25
		offsets.append(fposmod(o, 1.0))
		amps.append(1.0 + rng.randf_range(-0.3, 0.3) * roughness)
	on_table = _build(n, offsets, amps, 1.9 * def.engine_tone, 3.2, 0.55 + roughness * 0.4)
	off_table = _build(n, offsets, amps, 1.15 * def.engine_tone, 5.5, 0.35)
	_seed = hash(def.id) & 0x7fffffff


func _build(n: int, offsets: Array[float], amps: Array[float], harm: float, decay: float, sub: float) -> PackedFloat32Array:
	var t := PackedFloat32Array()
	t.resize(TABLE)
	var peak := 0.0001
	for i in TABLE:
		var x := float(i) / float(TABLE)
		var v := 0.0
		for c in n:
			var tc := fposmod(x - offsets[c], 1.0)
			var local := tc * float(n)
			v += amps[c] * exp(-local * decay) * sin(TAU * local * harm)
		v += 0.45 * sin(TAU * x * float(n)) + sub * 0.25 * sin(TAU * x * float(n) * 0.5 + 0.7)
		v += 0.12 * sin(TAU * x * float(n) * 3.0)
		t[i] = v
		peak = maxf(peak, absf(v))
	for i in TABLE:
		t[i] /= peak
	return t


func fill(playback: AudioStreamGeneratorPlayback, mix_rate: float, rpm: float, load: float, boost: float, volume: float, muffle: float) -> void:
	var frames := playback.get_frames_available()
	if frames <= 0:
		return
	if _buf.size() != frames:
		_buf.resize(frames)
	var inc := (rpm / 120.0) / mix_rate * float(TABLE)
	var w_inc := (2200.0 + 3800.0 * boost) / mix_rate
	# low-pass cutoff: open with load and rpm, closed when muffled (interior/off-throttle)
	var cutoff := clampf(0.18 + load * 0.45 + (rpm / 9000.0) * 0.3 - muffle * 0.25, 0.06, 0.95)
	var noise_amt := (0.05 + roughness * 0.12) * (0.4 + load)
	var whistle_amt := boost * 0.05 if turbo else 0.0
	var ph := phase
	var wph := whistle_phase
	var l1 := lp
	var l2 := lp2
	var nl := noise_lp
	var s := _seed
	for i in frames:
		ph += inc
		if ph >= TABLE:
			ph -= TABLE
		var idx := int(ph)
		var fr := ph - float(idx)
		var j := (idx + 1) & MASK
		var a := on_table[idx] + (on_table[j] - on_table[idx]) * fr
		var b := off_table[idx] + (off_table[j] - off_table[idx]) * fr
		var v := b + (a - b) * load
		# cheap LCG noise
		s = (s * 1103515245 + 12345) & 0x7fffffff
		var nz := float(s) / 1073741823.5 - 1.0
		nl += (nz - nl) * 0.35
		v += nl * noise_amt * (0.5 + absf(v))
		wph += w_inc
		if wph >= 1.0:
			wph -= 1.0
		v += sin(wph * TAU) * whistle_amt
		l1 += (v - l1) * cutoff
		l2 += (l1 - l2) * cutoff
		var out := l2 * volume
		_buf[i] = Vector2(out, out)
	phase = ph
	whistle_phase = wph
	lp = l1
	lp2 = l2
	noise_lp = nl
	_seed = s
	playback.push_buffer(_buf)
