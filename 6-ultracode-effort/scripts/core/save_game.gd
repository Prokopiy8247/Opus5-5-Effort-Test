extends Node
## Progress persistence (user://save.json). Autoload "SaveGame".
## Stores car, paint, upgrades, tuning, position, time, weather, personal bests, credits, discoveries.
## Dynamic objects (traffic, particles) are not persisted and are rebuilt on load.

signal saved(path: String)
signal loaded(data: Dictionary)

const PATH := "user://save.json"
const VERSION := 1
const AUTOSAVE_INTERVAL := 60.0

var pending: Dictionary = {}
var _timer: float = 0.0
var enabled: bool = true


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	pending = read_file()
	# Restore the non-spatial parts immediately so menus see them.
	if not pending.is_empty():
		_restore_progress(pending)


func _process(delta: float) -> void:
	if not enabled or Game.player_car == null:
		return
	_timer += delta
	if _timer >= AUTOSAVE_INTERVAL:
		_timer = 0.0
		save_now()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and enabled and Game.player_car != null:
		save_now()


func has_save() -> bool:
	return FileAccess.file_exists(PATH)


func read_file() -> Dictionary:
	if not FileAccess.file_exists(PATH):
		return {}
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("SaveGame: corrupt save ignored")
		return {}
	return parsed


func collect() -> Dictionary:
	var d := {
		"version": VERSION,
		"car_index": Game.current_car_index,
		"paints": _encode(Game.paints),
		"upgrades": Game.upgrades.duplicate(true),
		"tuning": Game.tuning.duplicate(true),
		"personal_bests": Game.personal_bests.duplicate(true),
		"credits": Game.credits,
		"discovered": Game.discovered.duplicate(true),
		"time_of_day": Game.get_time_of_day(),
		"weather": String(Game.get_weather()),
	}
	if Game.player_car != null and is_instance_valid(Game.player_car):
		var t := Game.player_car.global_transform
		d["position"] = [t.origin.x, t.origin.y, t.origin.z]
		var f := -t.basis.z
		d["heading"] = atan2(f.x, f.z)
	return d


func save_now() -> bool:
	var d := collect()
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f == null:
		push_warning("SaveGame: cannot write %s" % PATH)
		return false
	f.store_string(JSON.stringify(d, "\t"))
	f.close()
	pending = d
	saved.emit(PATH)
	return true


func load_now() -> Dictionary:
	pending = read_file()
	if not pending.is_empty():
		_restore_progress(pending)
		loaded.emit(pending)
	return pending


func delete_save() -> void:
	if FileAccess.file_exists(PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))
	pending = {}


func _restore_progress(d: Dictionary) -> void:
	Game.current_car_index = int(d.get("car_index", 0))
	Game.paints = _decode(d.get("paints", {}))
	Game.upgrades = _decode_upgrades(d.get("upgrades", {}))
	Game.tuning = d.get("tuning", {})
	Game.personal_bests = d.get("personal_bests", {})
	Game.credits = int(d.get("credits", 0))
	Game.discovered = d.get("discovered", {})


## JSON numbers load as floats; upgrade levels are ints everywhere else (car_id -> {slot: level}).
func _decode_upgrades(src: Variant) -> Dictionary:
	var out := {}
	if not (src is Dictionary):
		return out
	for car_id: Variant in src:
		var slots: Variant = src[car_id]
		if not (slots is Dictionary):
			continue
		var levels := {}
		for slot: Variant in slots:
			var lvl: Variant = slots[slot]
			if lvl is float or lvl is int:
				levels[String(slot)] = int(lvl)
		out[String(car_id)] = levels
	return out


## Colours are not JSON types: store them as html strings.
func _encode(paints: Dictionary) -> Dictionary:
	var out := {}
	for k: String in paints:
		var p: Dictionary = paints[k].duplicate()
		for key: String in p.keys():
			if p[key] is Color:
				p[key] = "#" + (p[key] as Color).to_html(true) if (p[key] as Color).r >= 0.0 else ""
		out[k] = p
	return out


func _decode(paints: Dictionary) -> Dictionary:
	var out := {}
	for k: String in paints:
		var p: Dictionary = paints[k].duplicate()
		for key: String in ["color", "stripe_color", "rim_color"]:
			if p.has(key):
				var s: String = str(p[key])
				p[key] = _preset_or(Color.from_string(s, Color(-1, -1, -1))) if s != "" else Color(-1, -1, -1)
		if p.has("finish"):
			p["finish"] = int(p["finish"])
		if p.has("stripes"):
			p["stripes"] = int(p["stripes"])
		out[k] = p
	return out


## 8-bit html rounds the Game.PAINT_COLORS presets: a saved preset loads back as the exact preset.
func _preset_or(c: Color) -> Color:
	if c.r < 0.0:
		return c
	var html := c.to_html(false)
	for k: String in Game.PAINT_COLORS:
		if (Game.PAINT_COLORS[k] as Color).to_html(false) == html:
			return Game.PAINT_COLORS[k]
	return c
