class_name TrafficTypes
extends RefCounted
## Civilian vehicle types: handling definition (data/traffic/*.tres), Blender model, length,
## speed cap, paint palette and spawn weights per road class.

const TYPES := [
	{"id": "t_compact", "length": 3.9, "max_kmh": 110.0,
		"weights": {"highway": 3.0, "main": 4.0, "village": 4.0, "mountain": 3.0, "gravel": 0.4},
		"colors": [Color(0.75, 0.1, 0.1), Color(0.1, 0.25, 0.6), Color(0.85, 0.85, 0.82), Color(0.15, 0.15, 0.16),
			Color(0.55, 0.57, 0.6), Color(0.2, 0.45, 0.25), Color(0.9, 0.65, 0.15), Color(0.45, 0.2, 0.5)]},
	{"id": "t_van", "length": 5.3, "max_kmh": 105.0,
		"weights": {"highway": 1.5, "main": 1.6, "village": 1.6, "mountain": 0.6},
		"colors": [Color(0.92, 0.92, 0.9), Color(0.92, 0.92, 0.9), Color(0.2, 0.35, 0.6), Color(0.85, 0.75, 0.2)]},
	{"id": "t_lorry", "length": 7.8, "max_kmh": 85.0,
		"weights": {"highway": 1.3, "main": 0.8},
		"colors": [Color(0.9, 0.9, 0.88), Color(0.7, 0.12, 0.1), Color(0.15, 0.35, 0.65), Color(0.2, 0.45, 0.25)]},
	{"id": "t_bus", "length": 11.6, "max_kmh": 90.0,
		"weights": {"highway": 0.8, "main": 0.6, "mountain": 0.25},
		"colors": [Color(0.95, 0.6, 0.1), Color(0.15, 0.45, 0.75), Color(0.9, 0.9, 0.9)]},
	{"id": "t_tractor", "length": 4.4, "max_kmh": 32.0,
		"weights": {"main": 0.2, "village": 0.4, "gravel": 2.0, "dirt": 3.0},
		"colors": [Color(0.15, 0.5, 0.15), Color(0.8, 0.12, 0.08), Color(0.2, 0.3, 0.65)]},
	{"id": "t_pickup", "length": 5.3, "max_kmh": 120.0,
		"weights": {"highway": 1.0, "main": 1.5, "mountain": 1.3, "village": 0.8, "gravel": 2.0, "dirt": 2.0},
		"colors": [Color(0.85, 0.85, 0.85), Color(0.25, 0.25, 0.27), Color(0.6, 0.15, 0.1), Color(0.35, 0.4, 0.3)]},
]

static var _cache: Array[Dictionary] = []


static func all() -> Array[Dictionary]:
	if not _cache.is_empty():
		return _cache
	for t in TYPES:
		var path := "res://data/traffic/%s.tres" % t["id"]
		if not ResourceLoader.exists(path):
			continue
		var d: Dictionary = (t as Dictionary).duplicate(true)
		d["def"] = load(path) as CarDefinition
		_cache.append(d)
	return _cache
