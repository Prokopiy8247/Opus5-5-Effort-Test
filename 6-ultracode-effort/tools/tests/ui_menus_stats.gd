extends SceneTree
## Prints the garage stat figures for every car (calibration aid for scripts/ui/menu_car_stats.gd).

const Stats := preload("res://scripts/ui/menu_car_stats.gd")


func _init() -> void:
	for id: String in ["kestrel_r4", "aurelia_sedan", "brute_68", "sora_s2", "castellan_gt", "vortex_x", "granite_rally", "ridgeback_sx", "hauler_2500", "lark_roadster"]:
		var d: CarData = load("res://data/cars/%s.tres" % id)
		var r := Stats.ratings(d)
		var parts: PackedStringArray = []
		for k: String in Stats.STAT_NAMES:
			parts.append("%s %.1f" % [k, r[k]])
		print("%-14s %s %3d (auth %s %d) %4.0f hp %4.0f kg top %3.0f 0-100 %.2f brk %.1f m lat %.2f g | %s" % [id, Tuning.class_for(r["pi"]), r["pi"], d.perf_class, d.perf_index, r["hp"], r["kg"], r["top_kmh"], r["zero_100"], r["brake_m"], r["lat_g"], ", ".join(parts)])
	quit(0)
