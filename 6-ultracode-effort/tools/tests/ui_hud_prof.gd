extends RefCounted
## Tiny accumulating profiler used by the UI benchmark (scripts are instrumented temporarily).
static var acc: Dictionary = {}
static var cnt: Dictionary = {}

static func add(label: String, t0: int) -> void:
	acc[label] = int(acc.get(label, 0)) + Time.get_ticks_usec() - t0
	cnt[label] = int(cnt.get(label, 0)) + 1

static func report() -> String:
	var s := ""
	for k: String in acc:
		s += "%s: %.3f ms/call x%d (total %.1f ms)\n" % [k, acc[k] / 1000.0 / maxf(cnt[k], 1), cnt[k], acc[k] / 1000.0]
	return s

static func reset() -> void:
	acc.clear()
	cnt.clear()
