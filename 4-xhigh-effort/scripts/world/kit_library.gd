extends Node
## Loads Blender-authored kit pieces (res://assets/imported/kit/*.glb) and exposes their meshes by
## name with project materials applied. Each .glb holds one piece (and optional "_LOD1" variant).

const DIR := "res://assets/imported/kit/"

var _meshes := {}
var _scenes := {}


func _ready() -> void:
	# list_directory reports "x.glb" both in the editor and in an exported .pck (where only the
	# .import/.remap entries exist on disk)
	for f in ResourceLoader.list_directory(DIR):
		if f.ends_with(".glb"):
			var name := f.get_basename()
			_scenes[name] = DIR + f


func has_piece(name: String) -> bool:
	return _scenes.has(name)


## First mesh of the piece (materials mapped), cached. lod 1 returns "<name>_LOD1" when present.
func mesh(name: String, lod := 0) -> Mesh:
	var key := name + ("_LOD1" if lod == 1 else "")
	if _meshes.has(key):
		return _meshes[key]
	if not _scenes.has(name):
		return null
	var root := (load(_scenes[name]) as PackedScene).instantiate()
	var found: Mesh = null
	for n: Node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		var is_lod := String(mi.name).ends_with("_LOD1")
		if (lod == 1) == is_lod:
			found = _with_materials(mi.mesh)
			break
	if found == null and lod == 1:
		found = mesh(name, 0)
	root.free()
	_meshes[key] = found
	return found


## Instantiates the whole piece scene (for multi-part landmarks) with materials mapped.
func instance(name: String) -> Node3D:
	if not _scenes.has(name):
		return null
	var root := (load(_scenes[name]) as PackedScene).instantiate() as Node3D
	for n: Node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if String(mi.name).ends_with("_LOD1"):
			mi.queue_free()
			continue
		mi.mesh = _with_materials(mi.mesh)
	return root


func _with_materials(src: Mesh) -> Mesh:
	if src == null:
		return null
	var m := src.duplicate() as Mesh
	for i in m.get_surface_count():
		var mat := m.surface_get_material(i)
		var nm := mat.resource_name if mat != null else ""
		m.surface_set_material(i, KitMaterials.get_mat(nm, mat))
	return m
