extends RefCounted
## Real-time procedural engine voice (no samples). One firing pulse per cylinder per 720 deg cycle,
## so the firing frequency is rpm / 60 * cylinders / 2. Per-cylinder strength/timing patterns give
## each engine its rhythm (V8 burble, flat-4 rumble), fixed-frequency exhaust/induction resonances
## give the timbre, plus rasp noise, overrun pops, turbo whistle and a gear-whine oscillator.
## CarAudio sets the control fields every frame and calls render().

const TAB := 256  # pulse-table entries per firing interval
const INV31 := 1.0 / 2147483648.0

## Per-car character. amp/jit: firing strength / timing offset (fraction of an interval) per cylinder,
## w_on/w_off: pulse width on/off load, f1/f2: body / rasp resonance in Hz (scaled by engine_pitch),
## g0/g1/g2: direct / body / rasp mix, lp: muffler cutoff, noise: rasp noise, click: diesel knock,
## pops: overrun crackle, whine: straight-cut gear whine, lope: idle irregularity, drive: saturation.
const PROFILES := {
	"kestrel_r4": {"amp": [1.0, 0.93, 0.98, 0.9], "jit": [0.0, 0.02, 0.0, 0.015], "w_on": 0.15, "w_off": 0.3,
		"f1": 240.0, "q1": 2.2, "f2": 1350.0, "q2": 3.5, "g0": 0.8, "g1": 0.8, "g2": 1.0, "lp": 950.0,
		"noise": 1.0, "click": 0.0, "pops": 0.7, "whine": 0.0, "lope": 0.01, "drive": 1.5, "vol": 0.9, "turbo_hz": 2700.0},
	"aurelia_sedan": {"amp": [1.0, 0.97, 1.0, 0.96], "jit": [0.0, 0.0, 0.0, 0.0], "w_on": 0.24, "w_off": 0.34,
		"f1": 200.0, "q1": 1.5, "f2": 1050.0, "q2": 2.0, "g0": 1.1, "g1": 0.6, "g2": 0.3, "lp": 520.0,
		"noise": 0.5, "click": 0.0, "pops": 0.0, "whine": 0.0, "lope": 0.004, "drive": 1.1, "vol": 0.7, "turbo_hz": 2300.0},
	"brute_68": {"amp": [1.0, 0.7, 0.94, 0.64, 1.0, 0.77, 0.9, 0.68], "jit": [0.0, 0.07, -0.03, 0.09, 0.0, 0.05, -0.04, 0.08],
		"w_on": 0.2, "w_off": 0.32, "f1": 210.0, "q1": 1.7, "f2": 1250.0, "q2": 2.6, "g0": 1.3, "g1": 0.9, "g2": 0.55,
		"lp": 640.0, "noise": 0.8, "click": 0.0, "pops": 0.55, "whine": 0.0, "lope": 0.035, "drive": 1.8, "vol": 1.0, "turbo_hz": 2000.0},
	"sora_s2": {"amp": [1.0, 0.66, 0.93, 0.6], "jit": [0.0, 0.13, 0.02, 0.11], "w_on": 0.17, "w_off": 0.3,
		"f1": 200.0, "q1": 2.0, "f2": 1150.0, "q2": 3.0, "g0": 1.1, "g1": 0.9, "g2": 0.6, "lp": 760.0,
		"noise": 0.8, "click": 0.0, "pops": 0.4, "whine": 0.0, "lope": 0.012, "drive": 1.5, "vol": 0.9, "turbo_hz": 2500.0},
	"castellan_gt": {"amp": [1.0, 0.97, 0.99, 0.96, 1.0, 0.98, 0.99, 0.97, 1.0, 0.96, 0.98, 0.97], "jit": [0.0],
		"w_on": 0.13, "w_off": 0.26, "f1": 420.0, "q1": 1.8, "f2": 2300.0, "q2": 4.0, "g0": 0.7, "g1": 0.9, "g2": 1.0,
		"lp": 1500.0, "noise": 0.6, "click": 0.0, "pops": 0.3, "whine": 0.0, "lope": 0.003, "drive": 1.7, "vol": 0.95, "turbo_hz": 2500.0},
	"vortex_x": {"amp": [1.0, 0.9, 0.99, 0.92, 0.97, 0.9, 1.0, 0.93], "jit": [0.0, 0.02, 0.0, 0.025, 0.0, 0.02, 0.0, 0.02],
		"w_on": 0.14, "w_off": 0.28, "f1": 260.0, "q1": 1.9, "f2": 1600.0, "q2": 3.6, "g0": 1.0, "g1": 0.9, "g2": 0.85,
		"lp": 1100.0, "noise": 0.75, "click": 0.0, "pops": 0.75, "whine": 0.0, "lope": 0.008, "drive": 1.9, "vol": 1.0, "turbo_hz": 3000.0},
	"granite_rally": {"amp": [1.0, 0.9, 1.0, 0.87], "jit": [0.0, 0.025, 0.0, 0.02], "w_on": 0.12, "w_off": 0.26,
		"f1": 260.0, "q1": 2.4, "f2": 1600.0, "q2": 4.5, "g0": 0.85, "g1": 0.85, "g2": 1.0, "lp": 1000.0,
		"noise": 1.0, "click": 0.0, "pops": 1.0, "whine": 0.4, "lope": 0.015, "drive": 2.0, "vol": 0.95, "turbo_hz": 2400.0},
	"ridgeback_sx": {"amp": [1.0, 0.86, 0.95, 0.88, 1.0, 0.85], "jit": [0.0, 0.02, 0.0, 0.03, 0.0, 0.02],
		"w_on": 0.22, "w_off": 0.34, "f1": 220.0, "q1": 1.6, "f2": 1150.0, "q2": 2.2, "g0": 1.15, "g1": 0.7, "g2": 0.4,
		"lp": 600.0, "noise": 0.6, "click": 0.0, "pops": 0.15, "whine": 0.0, "lope": 0.01, "drive": 1.3, "vol": 0.8, "turbo_hz": 2200.0},
	"hauler_2500": {"amp": [1.0, 0.84, 0.95, 0.8, 1.0, 0.82, 0.93, 0.86], "jit": [0.0, 0.03, -0.02, 0.04, 0.0, 0.03, -0.02, 0.03],
		"w_on": 0.09, "w_off": 0.18, "f1": 190.0, "q1": 1.3, "f2": 3400.0, "q2": 2.6, "g0": 1.2, "g1": 0.75, "g2": 0.75,
		"lp": 470.0, "noise": 1.0, "click": 0.85, "pops": 0.0, "whine": 0.0, "lope": 0.015, "drive": 1.4, "vol": 0.95, "turbo_hz": 1900.0},
	"lark_roadster": {"amp": [1.0, 0.78, 0.94, 0.72], "jit": [0.0, 0.05, -0.02, 0.06], "w_on": 0.2, "w_off": 0.32,
		"f1": 380.0, "q1": 2.8, "f2": 1350.0, "q2": 3.0, "g0": 0.35, "g1": 1.2, "g2": 0.65, "lp": 900.0,
		"noise": 0.7, "click": 0.0, "pops": 0.25, "whine": 0.0, "lope": 0.045, "drive": 1.6, "vol": 0.75, "turbo_hz": 2400.0},
}
const DEFAULT := {"amp": [1.0, 0.92, 0.97, 0.9], "jit": [0.0, 0.02, 0.0, 0.02], "w_on": 0.18, "w_off": 0.3,
	"f1": 230.0, "q1": 1.8, "f2": 1300.0, "q2": 3.0, "g0": 1.0, "g1": 0.8, "g2": 0.6, "lp": 800.0,
	"noise": 0.7, "click": 0.0, "pops": 0.3, "whine": 0.0, "lope": 0.01, "drive": 1.5, "vol": 0.9, "turbo_hz": 2400.0}

# ---- control inputs (written by CarAudio every frame) ----
var rpm: float = 900.0
var load: float = 0.0          ## 0..1 smoothed throttle actually applied
var fire_gain: float = 1.0     ## 0 = ignition cut (shift)
var miss_prob: float = 0.0     ## random misfire probability (limiter / overrun burble)
var boost: float = 0.0         ## 0..1 turbo boost (whistle + spool hiss)
var whine_hz: float = 0.0
var whine_amp: float = 0.0
var pop_rate: float = 0.0      ## overrun pops per second
var volume: float = 1.0
var pops_fired: int = 0        ## incremented on every pop (CarAudio emits backfire)
var last_pop_strength: float = 0.0

# ---- character ----
var prof: Dictionary
var rate: float
var cyl: int = 4
var idle_rpm: float = 800.0
var max_rpm: float = 7000.0
var pitch: float = 1.0
var rasp: float = 0.4
var turbo: bool = false
var amp_pat := PackedFloat32Array()
var ivl := PackedFloat32Array()
var t_on := PackedFloat32Array()
var t_off := PackedFloat32Array()
var t_nz := PackedFloat32Array()

# ---- state ----
var _rpm_cur: float = -1.0
var _gain: float = 0.0
var _k: int = 0
var _to_next: float = 0.0
var _x: float = 2.0
var _famp: float = 0.0
var _seed: int = 12345
var _lp: float = 0.0
var _r1a: float = 0.0
var _r1b: float = 0.0
var _r2a: float = 0.0
var _r2b: float = 0.0
var _dcx: float = 0.0
var _dcy: float = 0.0
var _ws: float = 0.0
var _wc: float = 1.0
var _vs: float = 0.0
var _vc: float = 1.0
var _pop: float = 0.0
var _pop_k: float = 0.99
var _pop_pending: float = 0.0


## Player cars by id; traffic / unknown cars by keyword (diesel commercial vehicles, smooth everyday cars).
static func profile_for(data: CarData) -> Dictionary:
	if PROFILES.has(data.id):
		return PROFILES[data.id]
	for k: String in ["lorry", "bus", "tractor", "van", "truck", "pickup"]:
		if k in data.id:
			return PROFILES["hauler_2500"]
	if data.category == "Traffic" or data.id.ends_with("_placeholder"):
		return PROFILES["aurelia_sedan"]
	return DEFAULT


func _init(data: CarData, mix_rate := 22050.0, seed := 0) -> void:
	rate = mix_rate
	prof = profile_for(data)
	cyl = clampi(data.cylinders, 1, 16)
	idle_rpm = data.idle_rpm
	max_rpm = maxf(data.max_rpm, idle_rpm + 500.0)
	pitch = clampf(data.engine_pitch, 0.4, 2.0)
	rasp = clampf(data.exhaust_rasp, 0.0, 1.0)
	turbo = data.turbo
	rpm = idle_rpm
	_seed = 1 + absi(hash(data.id) + seed) % 2000000000
	var amps: Array = prof["amp"]
	var jits: Array = prof["jit"]
	amp_pat.resize(cyl)
	var jit := PackedFloat32Array()
	jit.resize(cyl)
	for k in cyl:
		amp_pat[k] = float(amps[k % amps.size()])
		jit[k] = float(jits[k % jits.size()])
	ivl.resize(cyl)
	for k in cyl:
		ivl[k] = (1.0 + jit[(k + 1) % cyl] - jit[k]) / float(cyl)
	_to_next = ivl[0]
	t_on = _pulse_table(float(prof["w_on"]))
	t_off = _pulse_table(float(prof["w_off"]))
	var click := float(prof["click"])
	t_nz.resize(TAB)
	for i in TAB:
		var x := (i + 0.5) / TAB
		var knock := exp(-x / 0.025) if x < 0.3 else 0.0
		t_nz[i] = lerpf(absf(t_on[i]), knock * 1.6, click)


## Firing pulse over one interval: an alpha-function pressure pulse followed by a weaker
## reflected rarefaction, windowed to zero before the next firing (no discontinuity).
static func _pulse_table(w: float) -> PackedFloat32Array:
	var t := PackedFloat32Array()
	t.resize(TAB)
	for i in TAB:
		var x := (i + 0.5) / TAB
		var a := (x / w) * exp(1.0 - x / w)
		var x2 := x - w * 2.2
		var b := 0.0
		if x2 > 0.0:
			b = (x2 / (w * 1.6)) * exp(1.0 - x2 / (w * 1.6))
		var win := 1.0
		if x > 0.7:
			win = 0.5 + 0.5 * cos(PI * minf((x - 0.7) / 0.25, 1.0))
		t[i] = (a - 0.42 * b) * win
	return t


func trigger_pop(strength: float) -> void:
	_pop_pending = maxf(_pop_pending, strength)


func rpm_norm() -> float:
	return clampf((rpm - idle_rpm) / (max_rpm - idle_rpm), 0.0, 1.0)


func firing_hz(at_rpm: float) -> float:
	return at_rpm / 60.0 * cyl * 0.5


## Renders `frames` stereo frames (mono content) and advances the engine state.
func render(frames: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	if frames <= 0:
		return out
	out.resize(frames)
	var target_rpm := maxf(rpm, 60.0)
	if _rpm_cur < 0.0:
		_rpm_cur = target_rpm
	var inc := _rpm_cur / 120.0 / rate
	var inc1 := target_rpm / 120.0 / rate
	var dinc := (inc1 - inc) / frames
	_rpm_cur = target_rpm
	var rn := rpm_norm()
	var ld := clampf(load, 0.0, 1.0)
	var ild := 1.0 - ld
	var cylf := float(cyl)
	var fg := fire_gain * (0.55 + 0.45 * ld)
	var miss := miss_prob
	# Cycle-to-cycle combustion variation (all engines) + profile lope.
	var lope := 0.12 + float(prof["lope"]) * 4.0
	var rasp_amt := rasp * float(prof["noise"]) * (0.25 + 0.75 * ld) * (0.45 + 0.55 * rn) * 2.6
	var g0 := float(prof["g0"])
	var g1 := float(prof["g1"]) * (0.75 + 0.25 * ld)
	var g2 := float(prof["g2"]) * (0.3 + 0.7 * ld) * (0.45 + 0.9 * rn)
	var lpc := float(prof["lp"]) * pitch * (0.7 + 0.8 * ld) * (0.8 + 1.4 * rn)
	var lpk := 1.0 - exp(-TAU * minf(lpc, 2400.0) / rate)
	# Resonators (2-pole, peak gain normalised to 1).
	var c1 := _reso(float(prof["f1"]) * pitch * (0.92 + 0.16 * rn), float(prof["q1"]))
	var c2 := _reso(float(prof["f2"]) * pitch * (0.85 + 0.35 * rn), float(prof["q2"]))
	var a11 := c1.x
	var a12 := c1.y
	var n1 := c1.z
	var a21 := c2.x
	var a22 := c2.y
	var n2 := c2.z
	var hiss := boost * 0.05 if turbo else 0.0
	# Turbo whistle and gear whine: coupled-form sine oscillators.
	var wamp := 0.0
	var wf := 0.0
	if turbo and boost > 0.01:
		var whz := float(prof["turbo_hz"]) * (0.55 + 0.55 * boost) * (0.75 + 0.45 * rn)
		wf = 2.0 * sin(PI * minf(whz, rate * 0.45) / rate)
		wamp = boost * boost * 0.07
	var vamp := whine_amp
	var vf := 2.0 * sin(PI * clampf(whine_hz, 20.0, rate * 0.45) / rate)
	var ws := _ws
	var wc := _wc
	var vs := _vs
	var vc := _vc
	var m := sqrt(ws * ws + wc * wc)
	if m > 0.0001:
		ws /= m
		wc /= m
	m = sqrt(vs * vs + vc * vc)
	if m > 0.0001:
		vs /= m
		vc /= m
	# Overrun pop scheduling (at most one new pop per block).
	var pop_at := -1
	var pop_str := 0.0
	_seed = (_seed * 1103515245 + 12345) & 0x7FFFFFFF
	var pr := float(_seed) * INV31
	if _pop_pending > 0.0:
		pop_at = 0
		pop_str = _pop_pending
		_pop_pending = 0.0
	elif pop_rate > 0.0 and pr < pop_rate * frames / rate:
		_seed = (_seed * 1103515245 + 12345) & 0x7FFFFFFF
		pop_at = int(float(_seed) * INV31 * frames)
		_seed = (_seed * 1103515245 + 12345) & 0x7FFFFFFF
		var big := float(_seed) * INV31
		pop_str = 0.7 + big * 0.3 if big > 0.72 else 0.2 + big * 0.35
	if pop_at >= 0:
		pops_fired += 1
		last_pop_strength = pop_str
	var pop_k := exp(-1.0 / ((0.004 + 0.006 * minf(pop_str, 1.0)) * rate))
	var gain := _gain
	# Output stays below 0.95 full scale: the soft clipper is bounded to +-1.
	# Fewer firings per second carry less energy: partly compensate so idle stays audible in the mix.
	var rate_comp := clampf(pow(120.0 / maxf(firing_hz(target_rpm), 1.0), 0.35), 0.8, 1.8)
	var gain_t := minf(clampf(volume, 0.0, 1.0) * float(prof["vol"]) * (0.7 + 0.3 * ld) * (0.68 + 0.27 * rn) * 0.72 * rate_comp, 0.95)
	var dgain := (gain_t - gain) / frames
	# Pre-scaled so the saturator only rounds the peaks (harmonic grit) instead of squaring the wave.
	var drive := float(prof["drive"]) * (0.55 + 0.35 * ld) * 0.42
	var ton := t_on
	var toff := t_off
	var tnz := t_nz
	var amps := amp_pat
	var ivls := ivl
	var k := _k
	var to_next := _to_next
	var x := _x
	var famp := _famp
	var seed := _seed
	var lp := _lp
	var r1a := _r1a
	var r1b := _r1b
	var r2a := _r2a
	var r2b := _r2b
	var dcx := _dcx
	var dcy := _dcy
	var pe := _pop
	for i in frames:
		inc += dinc
		to_next -= inc
		if to_next <= 0.0:
			k += 1
			if k >= cyl:
				k = 0
			to_next += ivls[k]
			x = 0.0
			seed = (seed * 1103515245 + 12345) & 0x7FFFFFFF
			var r := float(seed) * INV31
			famp = amps[k] * fg * (1.0 + lope * (r - 0.5))
			seed = (seed * 1103515245 + 12345) & 0x7FFFFFFF
			if float(seed) * INV31 < miss:
				famp *= 0.06
		x += inc * cylf
		var ti := int(x * TAB)
		var p := 0.0
		var ne := 0.0
		if ti < TAB:
			p = (ton[ti] * ld + toff[ti] * ild) * famp
			ne = tnz[ti] * famp
		seed = (seed * 1103515245 + 12345) & 0x7FFFFFFF
		var nz := float(seed) * INV31 * 2.0 - 1.0
		if i == pop_at:
			pe = pop_str
		if pe > 0.0005:
			p += pe * (nz * 0.8 + 0.45)
			pe *= pop_k
		lp += (p - lp) * lpk
		var y1 := a11 * r1a - a12 * r1b + p * n1
		r1b = r1a
		r1a = y1
		# Rasp noise only through the rasp resonance (band-shaped, never raw white noise).
		var y2 := a21 * r2a - a22 * r2b + (p + nz * (ne * rasp_amt + hiss)) * n2
		r2b = r2a
		r2a = y2
		var s := lp * g0 + y1 * g1 + y2 * g2
		if wamp > 0.0:
			ws += wf * wc
			wc -= wf * ws
			s += ws * wamp
		if vamp > 0.0:
			vs += vf * vc
			vc -= vf * vs
			s += vs * vamp
		var hp := s - dcx + 0.996 * dcy
		dcx = s
		dcy = hp
		gain += dgain
		var o := clampf(hp * drive, -3.0, 3.0)
		o = o * (27.0 + o * o) / (27.0 + 9.0 * o * o) * gain
		out[i] = Vector2(o, o)
	_k = k
	_to_next = to_next
	_x = minf(x, 4.0)
	_famp = famp
	_seed = seed
	_lp = lp
	_r1a = r1a
	_r1b = r1b
	_r2a = r2a
	_r2b = r2b
	_dcx = dcx
	_dcy = dcy
	_ws = ws
	_wc = wc
	_vs = vs
	_vc = vc
	_pop = pe
	_gain = gain
	return out


## Coefficients (a1, a2, input gain) of a 2-pole resonator at f Hz with quality q.
func _reso(f: float, q: float) -> Vector3:
	var fc := clampf(f, 20.0, rate * 0.45)
	var w := TAU * fc / rate
	var r := exp(-PI * (fc / maxf(q, 0.3)) / rate)
	var a1 := 2.0 * r * cos(w)
	var a2 := r * r
	var g := (1.0 - r) * sqrt(maxf(1.0 + r * r - 2.0 * r * cos(2.0 * w), 1e-6))
	return Vector3(a1, a2, g)
