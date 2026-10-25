class_name Surfaces
extends RefCounted
## Registry of SurfaceData resources (res://data/surfaces/*.tres), indexed by SurfaceData.Kind.

const DIR := "res://data/surfaces/"
const FILES := ["asphalt", "concrete", "dirt", "gravel", "grass", "sand", "snow", "rock"]

static var _by_kind: Array[SurfaceData] = []


static func _ensure() -> void:
	if not _by_kind.is_empty():
		return
	for f: String in FILES:
		var r := load(DIR + f + ".tres") as SurfaceData
		if r == null:
			r = SurfaceData.new()
		_by_kind.append(r)


static func get_kind(kind: int) -> SurfaceData:
	_ensure()
	return _by_kind[clampi(kind, 0, _by_kind.size() - 1)]


static func all() -> Array[SurfaceData]:
	_ensure()
	return _by_kind
