extends SceneTree
## Offline world bake: godot --headless --path . --script res://tools/world_bake.gd [-- --diag]

func _init() -> void:
	var wd := WorldBaker.new().bake()
	quit(0 if wd != null else 1)
