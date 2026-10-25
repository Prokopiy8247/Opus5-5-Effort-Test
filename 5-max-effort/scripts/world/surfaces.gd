class_name Surfaces
extends RefCounted
## Registry of surface types. Colliders carry the surface id as metadata ("surface"); terrain
## surfaces are resolved from the baked world surface map. Definitions live in res://data/surfaces/.

enum { ASPHALT, CONCRETE, DIRT, GRAVEL, GRASS, SAND, SNOW, ROCK, COUNT }

const KEYS: Array[StringName] = [&"asphalt", &"concrete", &"dirt", &"gravel", &"grass", &"sand", &"snow", &"rock"]

static var _defs: Array[SurfaceDef] = []


static func ensure_loaded() -> void:
	if _defs.size() == COUNT:
		return
	_defs.clear()
	for i in COUNT:
		var path := "res://data/surfaces/%s.tres" % KEYS[i]
		var def: SurfaceDef = null
		if ResourceLoader.exists(path):
			def = load(path) as SurfaceDef
		if def == null:
			def = SurfaceDef.new()
			def.id = i
			def.key = KEYS[i]
		_defs.append(def)


static func get_def(id: int) -> SurfaceDef:
	ensure_loaded()
	return _defs[clampi(id, 0, COUNT - 1)]


static func id_from_key(k: String) -> int:
	var idx := KEYS.find(StringName(k))
	return maxi(idx, 0)


static func is_paved(id: int) -> bool:
	return id == ASPHALT or id == CONCRETE
