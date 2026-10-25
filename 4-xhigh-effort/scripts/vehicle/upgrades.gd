class_name Upgrades
extends RefCounted
## Registry for UpgradeData resources and conversion of upgrade levels to physics multipliers.

const DIR := "res://data/upgrades/"
const CATEGORIES := ["engine", "tires", "suspension", "brakes", "weight", "aero"]
const LEVEL_NAMES := ["Stock", "Street", "Sport", "Race"]

static var _cache := {}


static func get_upgrade(category: String, level: int) -> UpgradeData:
	var key := "%s_%d" % [category, level]
	if not _cache.has(key):
		var r := load(DIR + key + ".tres") as UpgradeData
		if r == null:
			r = UpgradeData.new()
			r.category = category
			r.level = level
		_cache[key] = r
	return _cache[key]


static func multipliers(levels: Dictionary) -> Dictionary:
	var out := {"power": 1.0, "grip": 1.0, "brake": 1.0, "mass": 1.0, "aero": 1.0, "susp": 1.0, "top": 1.0}
	for cat: String in CATEGORIES:
		var u := get_upgrade(cat, int(levels.get(cat, 0)))
		for k: String in u.multipliers:
			out[k] = float(out.get(k, 1.0)) * float(u.multipliers[k])
	return out
