extends Node
## Offline audio verification (no audio device needed):
##   Godot_console.exe --headless --path . res://tools/tests/audio_test.tscn
## - renders the engine synth for brute_68 / castellan_gt / sora_s2 at idle, 3000 rpm and near redline
##   (real-time sized blocks) to qa_output/audio/*.wav and checks RMS, peak, clipping, NaN, sample jumps,
##   firing frequency (autocorrelation) and dominant frequency (Goertzel scan) vs rpm/60*cyl/2,
## - renders a full rev sweep + lift-off crackle + limiter per car and checks it for glitches,
## - measures synth CPU per 60 FPS frame for all cars, compares the 10 car voices,
## - generates every SfxBank sample + traffic engine loop, checks it and saves it, and exercises
##   the background (WorkerThreadPool) generation path.
## Prints "[audio_test] ..." lines, writes qa_output/audio/audio_test.json, ends with AUDIO_TEST_OK/FAIL.

const SfxBank := preload("res://scripts/audio/sfx_bank.gd")
const EngineSynth := preload("res://scripts/audio/engine_synth.gd")
const OUT := "res://qa_output/audio"
const RATE := 22050.0
const BLOCK := 368

var report: Dictionary = {}
var failures: PackedStringArray = []


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT + "/sfx"))
	_run.call_deferred()


func _log(s: String) -> void:
	print("[audio_test] ", s)


func _fail(s: String) -> void:
	failures.append(s)
	_log("FAIL " + s)


func _car(id: String) -> CarData:
	var i := Game.find_car_index(id)
	return Game.get_car_catalog()[i] if i >= 0 else null


func _run() -> void:
	var t0 := Time.get_ticks_msec()
	var only := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			only = a.substr(7)
	if only == "" or "points" in only:
		_test_engine_points()
	if only == "" or "sweeps" in only:
		_test_sweeps()
	if only == "" or "cpu" in only:
		_test_cpu()
	if only == "" or "voices" in only:
		_test_voices()
	if only == "" or "bank" in only:
		_test_bank()
	if only == "" or "background" in only:
		await _test_background()
	if "plot" in only:
		_plots()
	if "capture" in only:
		var file := "res://qa_output/audio/drive_capture.wav"
		for a in OS.get_cmdline_user_args():
			if a.begins_with("--file="):
				file = a.substr(7)
		_analyse_capture(file)
	report["failures"] = failures
	report["seconds"] = (Time.get_ticks_msec() - t0) / 1000.0
	var f := FileAccess.open(OUT + "/audio_test.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(report, "\t"))
	f.close()
	_log("done in %.1f s, %d failures" % [report["seconds"], failures.size()])
	print("AUDIO_TEST_OK" if failures.is_empty() else "AUDIO_TEST_FAIL " + ", ".join(failures))
	get_tree().quit(0 if failures.is_empty() else 1)


# ------------------------------------------------------------------ rendering helpers

## Renders `seconds` of audio in real-time sized blocks; returns mono samples.
func _render(s: EngineSynth, seconds: float, per_block := Callable()) -> PackedFloat32Array:
	var n := int(seconds * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var pos := 0
	var blk := 0
	while pos < n:
		if per_block.is_valid():
			per_block.call(s, float(pos) / RATE)
		var m := mini(BLOCK, n - pos)
		var buf := s.render(m)
		for i in m:
			out[pos + i] = buf[i].x
		pos += m
		blk += 1
	return out


func _save(buf: PackedFloat32Array, rate: int, file: String) -> void:
	var enc := SfxBank._encode({"l": buf, "rate": rate, "loop": false})
	var w := SfxBank._wav(enc)
	w.save_to_wav(ProjectSettings.globalize_path(OUT.path_join(file)))


func _stats(b: PackedFloat32Array) -> Dictionary:
	var sum := 0.0
	var sq := 0.0
	var peak := 0.0
	var nan := 0
	var clip := 0
	var jump := 0.0
	var prev := 0.0
	for i in b.size():
		var v := b[i]
		if is_nan(v) or is_inf(v):
			nan += 1
			continue
		sum += v
		sq += v * v
		peak = maxf(peak, absf(v))
		if absf(v) >= 0.999:
			clip += 1
		if i > 0:
			jump = maxf(jump, absf(v - prev))
		prev = v
	var n := maxf(b.size(), 1)
	return {"rms": sqrt(sq / n), "peak": peak, "dc": sum / n, "nan": nan, "clip": clip, "max_jump": jump}


## Normalised autocorrelation of window w at integer lag.
func _ac(w: PackedFloat32Array, lag: int, len: int) -> float:
	var a := 0.0
	var e0 := 0.0
	var e1 := 0.0
	for i in len:
		var x := w[i]
		var y := w[i + lag]
		a += x * y
		e0 += x * x
		e1 += y * y
	return a / sqrt(maxf(e0 * e1, 1e-12))


## Clicks: single-sample steps (a delta far larger than both neighbouring deltas), i.e. discontinuities,
## not merely fast but continuous attacks.
func _clicks(b: PackedFloat32Array, from_s: float, to_s: float) -> int:
	var a := maxi(int(from_s * RATE), 2)
	var e := mini(int(to_s * RATE), b.size() - 1)
	var n := 0
	var where := PackedStringArray()
	for i in range(a, e):
		var d := absf(b[i] - b[i - 1])
		var nb := (absf(b[i - 1] - b[i - 2]) + absf(b[i + 1] - b[i])) * 0.5
		if d > 0.2 and d > nb * 3.5:
			n += 1
			if where.size() < 6:
				where.append("%.3fs(d%.2f/nb%.3f)" % [i / RATE, d, nb])
	if n > 0:
		_log("  clicks at " + " ".join(where))
	return n


func _segment_peak(b: PackedFloat32Array, from_s: float, to_s: float) -> float:
	var m := 0.0
	for i in range(int(from_s * RATE), mini(int(to_s * RATE), b.size())):
		m = maxf(m, absf(b[i]))
	return m


## Pitch near an expected period (parabolic peak of the autocorrelation in 0.8..1.25 T).
func _pitch_near(b: PackedFloat32Array, f_exp: float, at_s := 0.6, len := 4096) -> Dictionary:
	var start := int(at_s * RATE)
	var t := RATE / f_exp
	var lo := maxi(int(t * 0.8), 8)
	var hi := int(t * 1.25) + 1
	var w := b.slice(start, start + len + hi + 2)
	var best := -2.0
	var best_lag := lo
	var vals := {}
	for lag in range(lo, hi + 1):
		var r := _ac(w, lag, len)
		vals[lag] = r
		if r > best:
			best = r
			best_lag = lag
	var lag_f := float(best_lag)
	if vals.has(best_lag - 1) and vals.has(best_lag + 1):
		var a: float = vals[best_lag - 1]
		var c: float = vals[best_lag + 1]
		var den := a - 2.0 * best + c
		if absf(den) > 1e-9:
			lag_f += 0.5 * (a - c) / den
	return {"f": RATE / lag_f, "r": best}


## Strongest periodicity over a wide lag range (reveals sub-harmonic burble of uneven engines).
func _pitch_wide(b: PackedFloat32Array, f_exp: float) -> Dictionary:
	var start := int(0.6 * RATE)
	var len := 3072
	var t := RATE / f_exp
	var lo := maxi(int(t * 0.45), 8)
	var hi := int(t * 2.2) + 1
	var w := b.slice(start, start + len + hi + 2)
	var best := -2.0
	var best_lag := lo
	var step := maxi(1, int((hi - lo) / 400))
	for lag in range(lo, hi + 1, step):
		var r := _ac(w, lag, len)
		if r > best:
			best = r
			best_lag = lag
	return {"f": RATE / best_lag, "r": best}


func _goertzel(w: PackedFloat32Array, f: float) -> float:
	var k := 2.0 * cos(TAU * f / RATE)
	var s1 := 0.0
	var s2 := 0.0
	for i in w.size():
		var s := w[i] + k * s1 - s2
		s2 = s1
		s1 = s
	return s1 * s1 + s2 * s2 - k * s1 * s2


## Dominant spectral peak (Hann-windowed Goertzel scan) and the spectral centroid.
func _spectrum(b: PackedFloat32Array, f_max: float, step: float) -> Dictionary:
	var start := int(0.6 * RATE)
	var len := 4096
	var w := b.slice(start, start + len)
	for i in len:
		w[i] *= 0.5 - 0.5 * cos(TAU * i / (len - 1))
	var best := 0.0
	var best_f := 0.0
	var num := 0.0
	var den := 0.0
	var f := 20.0
	while f <= f_max:
		var p := _goertzel(w, f)
		if p > best:
			best = p
			best_f = f
		num += p * f
		den += p
		f += step
	return {"dominant": best_f, "centroid": num / maxf(den, 1e-12)}


func _setup(s: EngineSynth, rpm: float, load: float) -> void:
	s.rpm = rpm
	s.load = load
	s.volume = 1.0


# ------------------------------------------------------------------ tests

func _test_engine_points() -> void:
	var rows: Array = []
	for id: String in ["brute_68", "castellan_gt", "sora_s2"]:
		var d := _car(id)
		if d == null:
			_fail("missing car " + id)
			continue
		for rpm: float in [d.idle_rpm, 3000.0, d.redline_rpm * 0.92]:
			var s := EngineSynth.new(d, RATE)
			_setup(s, rpm, 1.0 if rpm > d.idle_rpm else 0.0)
			var b := _render(s, 1.6)
			var file := "engine_%s_%d.wav" % [id, int(rpm)]
			_save(b, int(RATE), file)
			var st := _stats(b)
			var f_fire := s.firing_hz(rpm)
			var near := _pitch_near(b, f_fire)
			var wide := _pitch_wide(b, f_fire)
			var sp := _spectrum(b, minf(f_fire * 12.0, 5000.0), maxf(1.0, f_fire / 40.0))
			var dev := absf(float(near["f"]) / f_fire - 1.0)
			var harm := float(sp["dominant"]) / f_fire
			var row := {"car": id, "rpm": rpm, "cyl": d.cylinders, "expected_firing_hz": f_fire,
				"autocorr_hz": near["f"], "autocorr_r": near["r"], "dev_pct": dev * 100.0,
				"strongest_period_hz": wide["f"], "strongest_r": wide["r"],
				"dominant_hz": sp["dominant"], "dominant_harmonic": harm, "centroid_hz": sp["centroid"],
				"rms": st["rms"], "peak": st["peak"], "clip": st["clip"], "nan": st["nan"], "max_jump": st["max_jump"], "file": file}
			rows.append(row)
			_log("%-13s %5d rpm  fire %6.1f Hz  autocorr %6.1f Hz (r %.2f, dev %.2f%%)  strongest %6.1f Hz (r %.2f)  dominant %6.1f Hz = %.2fx fire  centroid %5.0f Hz  rms %.3f peak %.3f clip %d nan %d jump %.3f" % [
				id, int(rpm), f_fire, near["f"], near["r"], dev * 100.0, wide["f"], wide["r"], sp["dominant"], harm,
				sp["centroid"], st["rms"], st["peak"], st["clip"], st["nan"], st["max_jump"]])
			if int(st["nan"]) > 0:
				_fail("%s %d NaN" % [id, rpm])
			if int(st["clip"]) > 0:
				_fail("%s %d clipping" % [id, rpm])
			if dev > 0.03:
				_fail("%s %d firing frequency off by %.1f%%" % [id, rpm, dev * 100.0])
			if float(st["rms"]) < 0.02:
				_fail("%s %d too quiet" % [id, rpm])
	report["engine_points"] = rows


func _test_sweeps() -> void:
	var rows: Array = []
	for d: CarData in Game.get_car_catalog():
		var s := EngineSynth.new(d, RATE)
		s.volume = 1.0
		var redline := d.redline_rpm
		# 0-3 s full-throttle sweep, 3-4.5 s lift-off with overrun crackle, 4.5-5.2 s limiter, 5.2-6 s idle.
		var b := _render(s, 6.0, _sweep_ctl(d))
		var file := "sweep_%s.wav" % d.id
		_save(b, int(RATE), file)
		var st := _stats(b)
		var clicks := _clicks(b, 0.05, 3.0) + _clicks(b, 5.35, 6.0)
		# rpm tracking during the sweep (centre of a 2048-sample window).
		var track := PackedStringArray()
		var worst_dev := 0.0
		for tc: float in [0.6, 1.2, 1.8, 2.4]:
			var rpm := lerpf(d.idle_rpm, redline, tc / 3.0)
			var pn := _pitch_near(b, s.firing_hz(rpm), tc - 1024.0 / RATE, 2048)
			var dev := absf(float(pn["f"]) / s.firing_hz(rpm) - 1.0)
			worst_dev = maxf(worst_dev, dev)
			track.append("%.0f/%.0f" % [pn["f"], s.firing_hz(rpm)])
		var pk_over := _segment_peak(b, 3.0, 4.5)
		var pk_lim := _segment_peak(b, 4.5, 5.2)
		rows.append({"car": d.id, "rms": st["rms"], "peak": st["peak"], "clip": st["clip"], "nan": st["nan"],
			"clicks": clicks, "pops": s.pops_fired, "rpm_track_hz": track, "rpm_track_worst_dev_pct": worst_dev * 100.0,
			"overrun_peak": pk_over, "limiter_peak": pk_lim, "file": file})
		_log("sweep %-13s rms %.3f peak %.3f clip %d nan %d clicks %d pops %d overrun_peak %.2f limiter_peak %.2f track(meas/exp Hz) %s worst %.1f%%" % [
			d.id, st["rms"], st["peak"], st["clip"], st["nan"], clicks, s.pops_fired, pk_over, pk_lim, " ".join(track), worst_dev * 100.0])
		if int(st["nan"]) > 0 or int(st["clip"]) > 0:
			_fail("sweep %s nan/clip" % d.id)
		if clicks > 0:
			_fail("sweep %s has %d clicks" % [d.id, clicks])
		if worst_dev > 0.04:
			_fail("sweep %s rpm tracking off %.1f%%" % [d.id, worst_dev * 100.0])
	report["sweeps"] = rows


func _test_cpu() -> void:
	var rows: Array = []
	var worst := 0.0
	for d: CarData in Game.get_car_catalog():
		var s := EngineSynth.new(d, RATE)
		s.volume = 1.0
		s.load = 1.0
		s.boost = 0.8 if d.turbo else 0.0
		s.whine_amp = 0.02
		s.whine_hz = 1500.0
		s.render(BLOCK)
		var total := 0
		var mx := 0
		for i in 300:
			s.rpm = lerpf(d.idle_rpm, d.redline_rpm, float(i % 100) / 100.0)
			var t := Time.get_ticks_usec()
			s.render(BLOCK)
			var us := Time.get_ticks_usec() - t
			total += us
			mx = maxi(mx, us)
		var avg := total / 300.0
		worst = maxf(worst, avg)
		rows.append({"car": d.id, "avg_us_per_60fps_frame": avg, "max_us": mx})
		_log("cpu %-13s %d samples/frame: avg %.0f us  max %d us" % [d.id, BLOCK, avg, mx])
	report["cpu"] = rows
	report["cpu_worst_avg_us"] = worst
	if worst > 1000.0:
		_fail("synth too slow: %.0f us per frame" % worst)


func _test_voices() -> void:
	var rows: Array = []
	for d: CarData in Game.get_car_catalog():
		var s := EngineSynth.new(d, RATE)
		var rpm := d.redline_rpm * 0.55
		_setup(s, rpm, 1.0)
		s.boost = 0.7 if d.turbo else 0.0
		var b := _render(s, 1.2)
		var st := _stats(b)
		var sp := _spectrum(b, 5000.0, 25.0)
		var near := _pitch_near(b, s.firing_hz(rpm))
		rows.append({"car": d.id, "cyl": d.cylinders, "rpm": rpm, "firing_hz": s.firing_hz(rpm), "autocorr_hz": near["f"],
			"centroid_hz": sp["centroid"], "rms": st["rms"]})
		_log("voice %-13s cyl %2d turbo %-5s @%5d rpm  fire %6.1f Hz  centroid %5.0f Hz  rms %.3f" % [d.id, d.cylinders, str(d.turbo), int(rpm), s.firing_hz(rpm), sp["centroid"], st["rms"]])
	report["voices"] = rows


func _test_bank() -> void:
	var rows: Array = []
	var ids: Array[StringName] = []
	ids.append_array(SfxBank.CAR_IDS)
	ids.append_array(SfxBank.AMBIENT_IDS)
	var total_ms := 0.0
	for id in ids:
		var d := SfxBank._generate(id, null)
		rows.append(_check_sample(String(id), d))
		total_ms += float(d["ms"])
	for car: CarData in Game.get_car_catalog():
		var key := SfxBank.engine_key(car)
		var d2 := SfxBank._generate(key, car)
		rows.append(_check_sample(String(key).replace(":", "_"), d2))
		total_ms += float(d2["ms"])
	report["bank"] = rows
	report["bank_total_ms"] = total_ms
	_log("bank: %d samples generated in %.0f ms total" % [rows.size(), total_ms])


func _check_sample(name: String, d: Dictionary) -> Dictionary:
	var l: PackedFloat32Array = d["l"]
	var st := _stats(l)
	var rate := int(d["rate"])
	var seam := 0.0
	if bool(d["loop"]) and l.size() > 2:
		seam = absf(l[0] - l[l.size() - 1])
	var stereo := d.has("r")
	var enc := SfxBank._encode(d)
	SfxBank._wav(enc).save_to_wav(ProjectSettings.globalize_path(OUT.path_join("sfx/%s.wav" % name)))
	_log("sfx %-22s %5.2f s %5d Hz %s loop %-5s gen %6.1f ms  rms %.3f peak %.3f nan %d seam %.3f (max step %.3f)" % [
		name, l.size() / float(rate), rate, "st" if stereo else "mo", str(d["loop"]), d["ms"], st["rms"], st["peak"], st["nan"], seam, st["max_jump"]])
	if int(st["nan"]) > 0 or float(st["peak"]) > 1.0:
		_fail("sample %s nan/over" % name)
	if float(st["rms"]) < 0.005:
		_fail("sample %s silent" % name)
	if bool(d["loop"]) and seam > maxf(float(st["max_jump"]) * 1.5, 0.05):
		_fail("sample %s loop seam %.3f" % [name, seam])
	return {"name": name, "seconds": l.size() / float(rate), "rate": rate, "stereo": stereo, "loop": d["loop"],
		"gen_ms": d["ms"], "rms": st["rms"], "peak": st["peak"], "seam": seam, "max_jump": st["max_jump"]}


func _test_background() -> void:
	var t0 := Time.get_ticks_msec()
	var ids: Array[StringName] = [&"squeal", &"bed_coast", &"gull_0"]
	SfxBank.prefetch(ids)
	var key := SfxBank.request_engine_loop(_car("vortex_x"))
	var frames := 0
	while SfxBank.is_busy() and frames < 2000:
		await get_tree().process_frame
		SfxBank.poll()
		frames += 1
	var ok := SfxBank.peek(&"squeal") != null and SfxBank.peek(&"bed_coast") != null and SfxBank.peek(key) != null
	var bed := SfxBank.peek(&"bed_coast")
	_log("background generation: %s after %d frames / %d ms (bed_coast %.1f s stereo=%s loop_end=%d)" % [
		"ok" if ok else "MISSING", frames, Time.get_ticks_msec() - t0, bed.get_length() if bed else 0.0,
		str(bed.stereo) if bed else "-", bed.loop_end if bed else 0])
	report["background_ok"] = ok
	if not ok:
		_fail("background generation")


# ------------------------------------------------------------------ plots (--only=plot)

func _sweep_ctl(d: CarData) -> Callable:
	var redline := d.redline_rpm
	return func(syn: EngineSynth, t: float) -> void:
		if t < 3.0:
			syn.rpm = lerpf(d.idle_rpm, redline, t / 3.0)
			syn.load = 1.0
			syn.boost = clampf(t / 2.0, 0.0, 1.0) if d.turbo else 0.0
			syn.miss_prob = 0.0
			syn.pop_rate = 0.0
		elif t < 4.5:
			syn.rpm = lerpf(redline, redline * 0.55, (t - 3.0) / 1.5)
			syn.load = 0.0
			syn.boost = 0.0
			syn.miss_prob = 0.18 * float(syn.prof["pops"])
			syn.pop_rate = 16.0 * float(syn.prof["pops"])
		elif t < 5.2:
			syn.rpm = d.max_rpm * (0.985 + 0.015 * sin(t * 60.0))
			syn.load = 1.0
			syn.miss_prob = 0.72
			syn.pop_rate = 6.0 * float(syn.prof["pops"])
		else:
			syn.rpm = d.idle_rpm
			syn.load = 0.0
			syn.miss_prob = 0.0
			syn.pop_rate = 0.0


func _plots() -> void:
	var ids := ["brute_68", "castellan_gt", "sora_s2", "hauler_2500", "vortex_x", "lark_roadster"]
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--cars="):
			ids = Array(a.substr(7).split(","))
	for id: String in ids:
		var d := _car(id)
		if d == null:
			continue
		var s := EngineSynth.new(d, RATE)
		s.volume = 1.0
		var b := _render(s, 6.0, _sweep_ctl(d))
		var img := _plot(b, RATE, 0.4, 2.6)
		var path := ProjectSettings.globalize_path(OUT.path_join("plot_%s.png" % id))
		img.save_png(path)
		_log("plot " + path)


func _fft(re: PackedFloat64Array, im: PackedFloat64Array) -> void:
	var n := re.size()
	var j := 0
	for i in range(1, n):
		var bit := n >> 1
		while j & bit:
			j ^= bit
			bit >>= 1
		j ^= bit
		if i < j:
			var t := re[i]
			re[i] = re[j]
			re[j] = t
			t = im[i]
			im[i] = im[j]
			im[j] = t
	var size := 2
	while size <= n:
		var half := size >> 1
		var ang := -TAU / size
		var wr := cos(ang)
		var wi := sin(ang)
		for i in range(0, n, size):
			var cr := 1.0
			var ci := 0.0
			for k in half:
				var a := i + k
				var c := a + half
				var vr := re[c] * cr - im[c] * ci
				var vi := re[c] * ci + im[c] * cr
				re[c] = re[a] - vr
				im[c] = im[a] - vi
				re[a] += vr
				im[a] += vi
				var ncr := cr * wr - ci * wi
				ci = cr * wi + ci * wr
				cr = ncr
		size <<= 1


## Analyses a recorded master mix (--audio-capture in the real game): level per second, clipping, plot.
func _analyse_capture(path: String) -> void:
	var w := AudioStreamWAV.load_from_file(ProjectSettings.globalize_path(path))
	if w == null or w.data.is_empty():
		_fail("capture missing: " + path)
		return
	var bytes := w.data
	var ch := 2 if w.stereo else 1
	var n := bytes.size() / (2 * ch)
	var rate := float(w.mix_rate)
	var mono := PackedFloat32Array()
	mono.resize(n)
	var clip := 0
	for i in n:
		var l := bytes.decode_s16(i * 2 * ch) / 32768.0
		var r := bytes.decode_s16(i * 2 * ch + 2) / 32768.0 if ch == 2 else l
		if absf(l) >= 0.999 or absf(r) >= 0.999:
			clip += 1
		mono[i] = (l + r) * 0.5
	var per_sec := PackedStringArray()
	var sec := int(rate)
	for s0 in range(0, n - sec, sec):
		var sq := 0.0
		var pk := 0.0
		for i in range(s0, s0 + sec):
			sq += mono[i] * mono[i]
			pk = maxf(pk, absf(mono[i]))
		per_sec.append("%d:%.0f/%.0f" % [s0 / sec, 20.0 * log(maxf(sqrt(sq / sec), 1e-6)) / log(10.0), 20.0 * log(maxf(pk, 1e-6)) / log(10.0)])
	var st := _stats(mono)
	_log("capture %s: %.1f s %d Hz %s  rms %.3f (%.1f dBFS) peak %.3f clipped %d nan %d" % [path, n / rate, int(rate),
		"stereo" if ch == 2 else "mono", st["rms"], 20.0 * log(maxf(float(st["rms"]), 1e-6)) / log(10.0), st["peak"], clip, st["nan"]])
	_log("capture per-second rms/peak dBFS: " + " ".join(per_sec))
	report["capture"] = {"file": path, "seconds": n / rate, "rate": rate, "rms": st["rms"], "peak": st["peak"], "clipped": clip, "per_second": per_sec}
	if clip > 0:
		_fail("capture clipped %d samples" % clip)
	var zoom_a := minf(20.0, n / rate * 0.5)
	var zoom_b := minf(30.0, n / rate - 0.1)
	var img := _plot(mono, rate, zoom_a, zoom_b)
	var out := ProjectSettings.globalize_path(path.get_basename() + "_plot.png")
	img.save_png(out)
	_log("plot " + out)


## Waveform overview, log-frequency spectrogram (20 Hz - 8 kHz) and two 60 ms zooms.
func _plot(b: PackedFloat32Array, rate: float, zoom_a: float, zoom_b: float) -> Image:
	var w := 1200
	var h_wave := 140
	var h_spec := 300
	var h_zoom := 160
	var img := Image.create(w, h_wave + h_spec + h_zoom + 12, false, Image.FORMAT_RGB8)
	img.fill(Color(0.06, 0.06, 0.08))
	var n := b.size()
	# waveform
	for x in w:
		var a := int(float(x) / w * n)
		var e := int(float(x + 1) / w * n)
		var lo := 0.0
		var hi := 0.0
		for i in range(a, e):
			lo = minf(lo, b[i])
			hi = maxf(hi, b[i])
		var y0 := int(h_wave * 0.5 - hi * h_wave * 0.48)
		var y1 := int(h_wave * 0.5 - lo * h_wave * 0.48)
		for y in range(clampi(y0, 0, h_wave - 1), clampi(y1, 0, h_wave - 1) + 1):
			img.set_pixel(x, y, Color(0.4, 0.8, 1.0))
	for x in w:
		img.set_pixel(x, int(h_wave * 0.5 - 0.95 * h_wave * 0.48), Color(0.5, 0.2, 0.2))
	# spectrogram
	var fn := 1024
	var win := PackedFloat64Array()
	win.resize(fn)
	for i in fn:
		win[i] = 0.5 - 0.5 * cos(TAU * i / (fn - 1))
	var cols := 400
	var y_top := h_wave + 6
	var re := PackedFloat64Array()
	var im := PackedFloat64Array()
	re.resize(fn)
	im.resize(fn)
	for cx in cols:
		var c := int(float(cx) / cols * (n - fn))
		for i in fn:
			re[i] = b[c + i] * win[i]
			im[i] = 0.0
		_fft(re, im)
		for y in h_spec:
			var f := 20.0 * pow(400.0, 1.0 - float(y) / h_spec)
			var bin := clampi(int(round(f / rate * fn)), 1, fn / 2 - 1)
			var mag := sqrt(re[bin] * re[bin] + im[bin] * im[bin]) / (fn * 0.25)
			var db := clampf((20.0 * log(maxf(mag, 1e-9)) / log(10.0) + 80.0) / 80.0, 0.0, 1.0)
			var col := Color(db * db, db * 0.85, 0.25 + 0.6 * (1.0 - db) * db * 2.0)
			for xx in range(cx * w / cols, (cx + 1) * w / cols):
				img.set_pixel(xx, y_top + y, col)
	# frequency grid lines (100 Hz, 1 kHz)
	for gf: float in [100.0, 1000.0]:
		var gy := int((1.0 - log(gf / 20.0) / log(400.0)) * h_spec)
		for x in range(0, w, 4):
			img.set_pixel(x, y_top + gy, Color(1, 1, 1))
	# zooms: 60 ms at zoom_a and zoom_b seconds
	var zy := y_top + h_spec + 6
	var zw := w / 2 - 6
	for zi in 2:
		var t0 := zoom_a if zi == 0 else zoom_b
		var cnt := int(0.06 * rate)
		var s0 := clampi(int(t0 * rate), 0, n - cnt - 1)
		var x_off := zi * (w / 2 + 6)
		var prev_y := -1
		for k in cnt:
			var x := x_off + int(float(k) / cnt * zw)
			var y := int(zy + h_zoom * 0.5 - b[s0 + k] * h_zoom * 0.48)
			y = clampi(y, zy, zy + h_zoom - 1)
			var ya := y if prev_y < 0 else mini(prev_y, y)
			var yb := y if prev_y < 0 else maxi(prev_y, y)
			for yy in range(ya, yb + 1):
				img.set_pixel(x, yy, Color(0.6, 1.0, 0.6))
			prev_y = y
	return img
