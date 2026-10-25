class_name Surfaces
extends RefCounted
## Registry of SurfaceData resources (res://data/surfaces/<id>.tres), loaded once.

const IDS: Array[StringName] = [&"asphalt", &"concrete", &"dirt", &"gravel", &"grass", &"sand", &"snow", &"asphalt_wet", &"concrete_wet"]
const DEFAULT_ID: StringName = &"asphalt"

## Surface ids indexed by the byte value stored in the terrain surface map.
const MAP_IDS: Array[StringName] = [&"grass", &"dirt", &"sand", &"gravel", &"snow", &"asphalt", &"concrete", &"asphalt_wet"]

static var _cache: Dictionary = {}


static func get_surface(id: StringName) -> SurfaceData:
	if _cache.is_empty():
		_load_all()
	var s: SurfaceData = _cache.get(id)
	if s == null:
		s = _cache[DEFAULT_ID]
	return s


static func from_map_index(i: int) -> SurfaceData:
	return get_surface(MAP_IDS[clampi(i, 0, MAP_IDS.size() - 1)])


static func _load_all() -> void:
	for id in IDS:
		var path := "res://data/surfaces/%s.tres" % id
		var res: SurfaceData = load(path) if ResourceLoader.exists(path) else null
		if res == null:
			res = SurfaceData.new()
			res.id = id
			res.display_name = String(id).capitalize()
			push_warning("Surfaces: missing %s, using defaults" % path)
		_cache[id] = res
