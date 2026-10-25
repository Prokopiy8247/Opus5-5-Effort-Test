extends Node
## Save / load (user://savegame.json): car, paint, upgrades, tuning, position, time, weather, settings, bests.

const PATH: String = "user://savegame.json"
var autosave_t: float = 0.0
var loaded: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _color_to(c: Color) -> Array:
	return [c.r, c.g, c.b, c.a]


func _to_color(a: Variant) -> Color:
	if a is Array and a.size() >= 3:
		return Color(a[0], a[1], a[2], a[3] if a.size() > 3 else 1.0)
	return Color.WHITE


func save_game() -> bool:
	var car: Node3D = Game.player as Node3D
	var paints: Dictionary = {}
	for id in Game.paint_overrides:
		var p: Dictionary = Game.paint_overrides[id]
		paints[id] = {"color": _color_to(p.get("color", Color.RED)), "finish": p.get("finish", 0), "stripe": p.get("stripe", 0),
			"stripe_color": _color_to(p.get("stripe_color", Color.WHITE)), "rim": _color_to(p.get("rim", Color(0.78, 0.79, 0.8)))}
	var d: Dictionary = {
		"version": 1, "car": Game.current_car_index,
		"pos": [car.global_position.x, car.global_position.y, car.global_position.z] if car else [0, 0, 0],
		"hour": Game.sky.hour if Game.sky else 10.0, "weather": Game.sky.weather if Game.sky else "clear",
		"settings": Game.settings, "paint": paints, "upgrades": Game.upgrades, "tuning": Game.tuning,
		"bests": Game.bests, "credits": Game.credits,
	}
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(d, "  "))
	f.close()
	return true


## Reads the save into Game state; returns {car, pos} for spawning. Missing/corrupt files are ignored.
func load_game() -> Dictionary:
	var ua: PackedStringArray = OS.get_cmdline_user_args()
	if "--fresh" in ua or ("--qa" in ua and not "--qa-save" in ua):
		return {}
	if not FileAccess.file_exists(PATH):
		return {}
	var txt: String = FileAccess.get_file_as_string(PATH)
	var d: Variant = JSON.parse_string(txt)
	if not d is Dictionary:
		push_warning("save file unreadable, starting fresh")
		return {}
	loaded = d
	for k in (d.get("settings", {}) as Dictionary):
		if Game.settings.has(k):
			Game.settings[k] = d.settings[k]
	for id in (d.get("paint", {}) as Dictionary):
		var p: Dictionary = d.paint[id]
		Game.paint_overrides[id] = {"color": _to_color(p.color), "finish": int(p.finish), "stripe": int(p.get("stripe", 0)),
			"stripe_color": _to_color(p.get("stripe_color", [1, 1, 1])), "rim": _to_color(p.get("rim", [0.78, 0.79, 0.8]))}
	for id in (d.get("upgrades", {}) as Dictionary):
		var u: Dictionary = Game.get_upgrades(id)
		for k in d.upgrades[id]:
			u[k] = int(d.upgrades[id][k])
	for id in (d.get("tuning", {}) as Dictionary):
		var t: Dictionary = Game.get_tuning(id)
		for k in d.tuning[id]:
			t[k] = float(d.tuning[id][k])
	Game.bests = d.get("bests", {})
	Game.credits = int(d.get("credits", 0))
	var out: Dictionary = {"car": int(d.get("car", 0))}
	var pa: Array = d.get("pos", [])
	if pa.size() == 3:
		out["pos"] = Vector3(pa[0], pa[1], pa[2])
	call_deferred("_apply_env")
	return out


func _apply_env() -> void:
	if loaded.is_empty() or Game.sky == null:
		return
	Game.sky.set_hour(float(loaded.get("hour", 10.0)))
	Game.sky.set_weather(str(loaded.get("weather", "clear")), true)


## Re-applies the saved state at runtime (console "load").
func apply_loaded() -> bool:
	var st: Dictionary = load_game()
	if st.is_empty():
		return false
	var main: Node = get_parent()
	main.switch_car(st.car)
	if st.has("pos"):
		var nr: Dictionary = Game.world.nearest_road_point(st.pos)
		main.teleport_to(Game.world.road_point(nr.road, nr.s, Game.world.roads[nr.road].lane * 0.5).translated(Vector3.UP * 0.6))
	return true


func _process(delta: float) -> void:
	autosave_t += delta
	if autosave_t > 60.0 and Game.player:
		autosave_t = 0.0
		save_game()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and Game.player:
		save_game()
