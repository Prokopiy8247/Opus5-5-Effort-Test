extends SceneTree
## Bakes the deterministic world into res://data/world/.
## Run: Godot_console --headless --path . --script res://tools/bake_world.gd

func _init() -> void:
	var t := Time.get_ticks_msec()
	var gen := WorldGen.new()
	gen.generate()
	gen.export_all("res://data/world")
	gen.export_preview("res://docs/map_preview.png")
	gen.say("BAKE DONE in %d ms" % (Time.get_ticks_msec() - t))
	var fa := FileAccess.open("res://data/world/bake_log.txt", FileAccess.WRITE)
	fa.store_string("\n".join(gen.log_lines))
	quit()
