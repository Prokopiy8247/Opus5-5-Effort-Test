extends Node
## Pre-merges every Blender kit prop into one mesh resource (res://assets/imported/props/merged/<Name>.res) so the
## game never merges kit meshes at runtime: reading mesh arrays back from a GPU renderer costs seconds, while this
## headless tool has them in CPU memory. Re-run after re-exporting a kit and re-importing:
##   Godot_console.exe --headless --audio-driver Dummy --path <project> res://tools/bake_props.tscn

const PropLibrary := preload("res://scripts/world/prop_library.gd")
const Plan := preload("res://scripts/world/dressing_settlement_plan.gd")


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(PropLibrary.MERGED_DIR))
	var n := 0
	var shapes := 0
	for k: String in PropLibrary.KITS:
		var path: String = PropLibrary.KIT_DIR + k
		if not ResourceLoader.exists(path):
			print("[bake_props] missing kit ", path)
			continue
		var root := (load(path) as PackedScene).instantiate()
		for name: String in PropLibrary.KITS[k]:
			var obj := root.find_child(name, false, false) as Node3D
			if obj == null:
				print("[bake_props] %s missing from %s" % [name, k])
				continue
			var m := PropLibrary._merge(obj)
			if m == null:
				continue
			var err := ResourceSaver.save(m, PropLibrary.MERGED_DIR + name + ".res", ResourceSaver.FLAG_COMPRESS)
			if err == OK:
				n += 1
			else:
				print("[bake_props] save failed %s err=%d" % [name, err])
			if int(Plan.COLLIDE.get(name, Plan.Col.NONE)) == Plan.Col.TRIMESH:
				ResourceSaver.save(m.create_trimesh_shape(), PropLibrary.MERGED_DIR + name + "_col.res", ResourceSaver.FLAG_COMPRESS)
				shapes += 1
		root.free()
	print("[bake_props] wrote %d merged props, %d trimesh shapes" % [n, shapes])
	get_tree().quit()
