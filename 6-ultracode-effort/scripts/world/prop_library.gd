extends RefCounted
## Prop meshes by name (object names: docs/SYSTEM_CONTRACTS.md "Props"). Usage from any script:
##   const PropLibrary := preload("res://scripts/world/prop_library.gd")
##   PropLibrary.mesh("Tree_Oak_A"), PropLibrary.scene("Bus_Stop"), PropLibrary.aabb("Barn_Red")
## Meshes come from the Blender kits (res://assets/imported/props/*.glb, top-level object = prop) when
## the kit is imported; multi-part objects are merged into one ArrayMesh (materials kept) in the
## object's local space. Missing kits/objects fall back to procedural placeholders named
## "<Name>_placeholder", so the world is dressed now and upgrades automatically when the kits land.
## Everything is cached. Main thread only.

const MB := preload("res://scripts/world/dressing_mesh_builder.gd")
const Nature := preload("res://scripts/world/dressing_nature_meshes.gd")
const Built := preload("res://scripts/world/dressing_built_meshes.gd")
const Mats := preload("res://scripts/world/dressing_materials.gd")

const KIT_DIR := "res://assets/imported/props/"
## Pre-merged kit props written by tools/bake_props.gd (loaded instead of merging the kit scene at runtime).
const MERGED_DIR := "res://assets/imported/props/merged/"
const KITS := {
	"nature_kit.glb": ["Tree_Oak_A", "Tree_Oak_B", "Tree_Pine_A", "Tree_Pine_B", "Tree_Poplar", "Tree_Birch", "Tree_Palm",
		"Tree_Olive", "Tree_Dead", "Bush_A", "Bush_B", "Bush_Desert", "Cactus_A", "Cactus_B", "Rock_A", "Rock_B", "Rock_C",
		"Rock_Large", "Rock_Red", "Grass_Tuft", "Flowers_Tuft", "Reeds", "Hay_Bale", "Log_Pile"],
	"roadside_kit.glb": ["Sign_SpeedLimit", "Sign_Chevron", "Sign_Danger_Jump", "Sign_Direction", "Delineator_Post",
		"GuardRail_Post", "Lamp_Street", "Utility_Pole", "Fence_Wood", "Wall_Stone", "Hedge", "Bus_Stop", "Bench", "Mailbox",
		"Bin", "Barrier_Jersey", "Cone", "Bridge_Pier", "Tunnel_Portal", "Speed_Trap_Camera", "Checkpoint_Arch",
		"Festival_Banner", "Flag_Pole", "Fuel_Pump", "Billboard"],
	"buildings_kit.glb": ["House_Cottage_A", "House_Cottage_B", "House_Townhouse", "Farmhouse", "Barn_Red", "Silo",
		"Shed_Small", "House_Chalet", "House_Adobe", "Gas_Station", "Diner", "Church", "Harbour_Shed", "Boathouse",
		"Pier_Section", "Boat_Fishing", "Lighthouse", "Castle_Ruin_Wall", "Castle_Ruin_Tower", "Wind_Turbine_Tower",
		"Wind_Turbine_Rotor", "Water_Tower", "Festival_Stage", "Festival_Tent", "Viewpoint_Deck"],
}
## Kit materials whose name contains one of these are treated as foliage (wind + tint).
const LEAF_WORDS := ["leaf", "leaves", "foliage", "needle", "frond", "canopy", "crown", "hedge", "bush", "grass", "reed", "flower", "petal"]

static var _meshes: Dictionary = {}
static var _placeholder: Dictionary = {}
static var _aabbs: Dictionary = {}
static var _far: Dictionary = {}
static var _leaf: Dictionary = {}
static var _kit_scenes: Dictionary = {}
static var _kit_meshes: Dictionary = {}
static var _shapes: Dictionary = {}     # kit path -> {prop name: merged Mesh}
static var _warned: Dictionary = {}


## Mesh for a prop name (kit object or placeholder). Never null.
static func mesh(name: String) -> Mesh:
	var m: Mesh = _meshes.get(name)
	if m != null:
		return m
	m = _from_kit(name)
	_placeholder[name] = m == null
	if m == null:
		m = _make_placeholder(name)
	_meshes[name] = m
	_aabbs[name] = m.get_aabb()
	return m


## Local-space bounds of the prop (origin at the base centre).
## Concave collision shape of the prop: pre-baked by tools/bake_props.gd when available (building it from the
## mesh needs a GPU readback), otherwise created once and cached.
static func trimesh(name: String) -> Shape3D:
	var s: Shape3D = _shapes.get(name)
	if s != null:
		return s
	var sp := MERGED_DIR + name + "_col.res"
	var mp := MERGED_DIR + name + ".res"
	if not is_placeholder(name) and ResourceLoader.exists(sp) and FileAccess.get_modified_time(sp) >= FileAccess.get_modified_time(mp):
		s = load(sp) as Shape3D
	if s == null:
		s = mesh(name).create_trimesh_shape()
	_shapes[name] = s
	return s


static func aabb(name: String) -> AABB:
	if not _aabbs.has(name):
		mesh(name)
	return _aabbs[name]


static func is_placeholder(name: String) -> bool:
	if not _placeholder.has(name):
		mesh(name)
	return _placeholder[name]


## A new Node3D for the prop: the kit object (with its full hierarchy) or a placeholder MeshInstance3D.
static func scene(name: String) -> Node3D:
	var ps := _kit_scene(_kit_of(name))
	if ps != null:
		var root := ps.instantiate()
		var obj := root.find_child(name, false, false) as Node3D
		if obj != null:
			root.remove_child(obj)
			_clear_owner(obj)
			root.free()
			obj.transform = Transform3D.IDENTITY
			return obj
		root.free()
	var n := Node3D.new()
	n.name = name
	var mi := MeshInstance3D.new()
	mi.name = name + "_placeholder"
	mi.mesh = mesh(name)
	n.add_child(mi)
	return n


## Low-poly far-distance tree family mesh (see dressing_nature_meshes.gd Far enum), unit sized.
static func far_mesh(family: int) -> Mesh:
	var m: Mesh = _far.get(family)
	if m == null:
		var b: MB = Nature.make_far(family)
		m = b.to_mesh(Mats.foliage(), "Far_%d_placeholder" % family) if b != null else ArrayMesh.new()
		_far[family] = m
	return m


## Linear foliage colour of a vegetation prop (for far tints).
static func leaf_color(name: String) -> Color:
	if _leaf.has(name):
		return _leaf[name]
	mesh(name)
	if not _leaf.has(name):
		var sp: Dictionary = Nature.SPECIES.get(name, {})
		_leaf[name] = MB.lin(sp.get("leaf", Color(0.3, 0.45, 0.18)))
	return _leaf[name]


static func names() -> PackedStringArray:
	var out := PackedStringArray()
	for k: String in KITS:
		out.append_array(PackedStringArray(KITS[k]))
	return out


# ------------------------------------------------------------------ kits

static func _kit_of(name: String) -> String:
	for k: String in KITS:
		if name in KITS[k]:
			return KIT_DIR + k
	return ""


static func _kit_scene(path: String) -> PackedScene:
	if path == "":
		return null
	if _kit_scenes.has(path):
		return _kit_scenes[path]
	var ps: PackedScene = null
	if ResourceLoader.exists(path):
		ps = load(path) as PackedScene
	_kit_scenes[path] = ps
	return ps


static func _from_kit(name: String) -> Mesh:
	var path := _kit_of(name)
	if path == "":
		return null
	if not _kit_meshes.has(path):
		_kit_meshes[path] = _extract_kit(path)
	var m: Mesh = (_kit_meshes[path] as Dictionary).get(name)
	if m == null:
		if not _warned.has(name):
			_warned[name] = true
			push_warning("PropLibrary: '%s' missing from its kit, using placeholder" % name)
		return null
	if Nature.material_kind(name) == "foliage" and Nature.handles(name):
		_adapt_foliage(name, m)
	elif name == "Grass_Tuft":
		for i in m.get_surface_count():
			m.surface_set_material(i, Mats.grass())
	return m


## Instantiates a kit once and merges every contract prop in it (instantiating a whole kit per prop made a
## large kit cost seconds at startup).
static func _extract_kit(path: String) -> Dictionary:
	var out := {}
	# Fast path: pre-merged meshes, if they are at least as new as the kit export.
	var kit_time := FileAccess.get_modified_time(path)
	var all_merged := true
	for k: String in KITS:
		if KIT_DIR + k != path:
			continue
		for n: String in KITS[k]:
			var mp := MERGED_DIR + n + ".res"
			if ResourceLoader.exists(mp) and FileAccess.get_modified_time(mp) >= kit_time:
				out[n] = load(mp) as Mesh
			else:
				all_merged = false
	if all_merged and not out.is_empty():
		return out
	out.clear()
	var ps := _kit_scene(path)
	if ps == null:
		return out
	var root := ps.instantiate()
	for k: String in KITS:
		if KIT_DIR + k != path:
			continue
		for n: String in KITS[k]:
			var obj := root.find_child(n, false, false) as Node3D
			if obj != null:
				out[n] = _merge(obj)
	root.free()
	return out


static func _merge(obj: Node3D) -> Mesh:
	var parts: Array[ImporterMesh] = []
	var xforms: Array[Transform3D] = []
	_collect(obj, Transform3D.IDENTITY, parts, xforms)
	if parts.is_empty():
		return null
	var merged: ImporterMesh = parts[0]
	if parts.size() > 1 or not xforms[0].is_equal_approx(Transform3D.IDENTITY):
		merged = ImporterMesh.merge_importer_meshes(parts, xforms, true)
	if merged == null:
		return null
	var am := merged.get_mesh()
	am.resource_name = obj.name
	return am


static func _collect(n: Node, xf: Transform3D, parts: Array[ImporterMesh], xforms: Array[Transform3D]) -> void:
	var mi := n as MeshInstance3D
	if mi != null and mi.mesh != null:
		var im := ImporterMesh.from_mesh(mi.mesh)
		if im != null:
			for i in im.get_surface_count():
				var ov: Material = mi.get_surface_override_material(i) if i < mi.get_surface_override_material_count() else null
				if mi.material_override != null:
					ov = mi.material_override
				if ov != null:
					im.set_surface_material(i, ov)
			parts.append(im)
			xforms.append(xf)
	for c in n.get_children():
		var c3 := c as Node3D
		_collect(c, xf * c3.transform if c3 != null else xf, parts, xforms)


static func _adapt_foliage(name: String, m: Mesh) -> void:
	var am := m as ArrayMesh
	if am == null:
		return
	var sum := Color(0, 0, 0, 0)
	for i in am.get_surface_count():
		var src := am.surface_get_material(i)
		var mat_name := (src.resource_name if src != null else "").to_lower()
		var leaf := false
		for w: String in LEAF_WORDS:
			if mat_name.contains(w):
				leaf = true
				break
		if not name.begins_with("Tree_") and not mat_name.contains("bark") and not mat_name.contains("trunk") and not mat_name.contains("wood"):
			leaf = true
		am.surface_set_material(i, Mats.foliage_from(src, leaf))
		var bm := src as BaseMaterial3D
		if leaf and bm != null:
			var c := bm.albedo_color.srgb_to_linear()
			sum += Color(c.r, c.g, c.b, 1.0)
	if sum.a > 0.0:
		_leaf[name] = Color(sum.r / sum.a, sum.g / sum.a, sum.b / sum.a)


static func _clear_owner(n: Node) -> void:
	n.owner = null
	for c in n.get_children():
		_clear_owner(c)


# ------------------------------------------------------------------ placeholders

static func _make_placeholder(name: String) -> Mesh:
	var b: MB = null
	var mat: Material = Mats.solid()
	if Nature.handles(name):
		b = Nature.make(name)
		match Nature.material_kind(name):
			"foliage":
				mat = Mats.foliage()
			"grass":
				mat = Mats.grass()
	elif Built.handles(name):
		b = Built.make(name)
	if b == null:
		if not _warned.has(name):
			_warned[name] = true
			push_warning("PropLibrary: unknown prop '%s', using a crate placeholder" % name)
		b = MB.new()
		b.block(Vector3.ZERO, Vector3(1, 1, 1), Color(0.6, 0.5, 0.35, MB.MATTE))
	return b.to_mesh(mat, name + "_placeholder")
