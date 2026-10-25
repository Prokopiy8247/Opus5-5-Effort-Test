extends SceneTree
## Micro-benchmark of WorldGen.natural_height (diagnostics for bake speed).
func _init() -> void:
	var gen := WorldGen.new()
	var t0 := Time.get_ticks_usec()
	gen.lake_level(0)
	print("lake level ", gen.lake_level(0), " in ", (Time.get_ticks_usec() - t0) / 1000.0, " ms")
	t0 = Time.get_ticks_usec()
	var acc := 0.0
	for i in 20000:
		acc += gen.natural_height(-1500.0 + float(i % 200) * 15.0, -1500.0 + float(i / 200) * 30.0)
	var us := float(Time.get_ticks_usec() - t0) / 20000.0
	print("natural_height: %.2f us/call  (acc %.1f)" % [us, acc])
	var n := FastNoiseLite.new()
	t0 = Time.get_ticks_usec()
	for i in 100000:
		acc += n.get_noise_2d(float(i), 3.0)
	print("noise call: %.3f us" % (float(Time.get_ticks_usec() - t0) / 100000.0))
	quit(0)
