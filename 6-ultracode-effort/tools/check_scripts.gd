extends Node
## Parse/compile check for every GDScript in the project (res://scripts, res://tools).
## Runs as a scene so autoload identifiers resolve:
##   Godot_console.exe --headless --path <project> res://tools/check_scripts.tscn
## Prints "CHECK_OK n" or the failing scripts; compile errors are also printed by the engine.

func _ready() -> void:
	var files: PackedStringArray = []
	for root: String in ["res://scripts", "res://tools"]:
		_collect(root, files)
	files.remove_at(files.find("res://tools/check_scripts.gd"))
	var bad: PackedStringArray = []
	for f in files:
		var s: GDScript = ResourceLoader.load(f, "GDScript", ResourceLoader.CACHE_MODE_IGNORE)
		if s == null or not s.can_instantiate():
			bad.append(f)
	if bad.is_empty():
		print("CHECK_OK ", files.size())
	else:
		print("CHECK_FAIL ", bad)
	get_tree().quit(0 if bad.is_empty() else 1)


func _collect(dir: String, out: PackedStringArray) -> void:
	var d := DirAccess.open(dir)
	if d == null:
		return
	for f in d.get_files():
		if f.ends_with(".gd"):
			out.append(dir.path_join(f))
	for sub in d.get_directories():
		_collect(dir.path_join(sub), out)
