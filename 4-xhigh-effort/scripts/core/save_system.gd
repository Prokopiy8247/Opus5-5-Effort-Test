class_name SaveSystem
extends RefCounted
## JSON save in user://: car, paint, upgrades, tuning, position, time, weather, settings and
## personal bests. Dynamic objects (traffic, activity state) are not persisted and rebuild on load.

const PATH := "user://valoria_save.json"
const VERSION := 1


static func _color_out(c: Color) -> String:
	return c.to_html(false)


static func save_game() -> bool:
	if Game.player == null or not is_instance_valid(Game.player):
		return false
	var paint := {}
	for id: StringName in Game.paint:
		var p: Dictionary = Game.paint[id]
		paint[String(id)] = {"color": _color_out(p.color), "finish": p.finish, "stripe": p.stripe,
			"stripe_color": _color_out(p.stripe_color), "rim": _color_out(p.rim)}
	var ups := {}
	for id: StringName in Game.upgrades:
		ups[String(id)] = Game.upgrades[id]
	var tun := {}
	for id: StringName in Game.tuning:
		tun[String(id)] = Game.tuning[id]
	var p := Game.player.global_position
	var fwd := -Game.player.global_transform.basis.z
	var data := {
		"version": VERSION,
		"car": String(Game.player.data.id),
		"paint": paint, "upgrades": ups, "tuning": tun,
		"position": [p.x, p.y, p.z], "yaw": atan2(fwd.x, fwd.z),
		"time": float(Game.sky.time_of_day) if Game.sky != null else 12.0,
		"weather": String(Game.sky.target.id) if Game.sky != null else "clear",
		"auto_weather": bool(Game.sky.auto_weather) if Game.sky != null else true,
		"settings": Game.settings,
		"personal_bests": Game.personal_bests,
		"credits": Game.credits,
	}
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(data, "  "))
	f.close()
	return true


static func has_save() -> bool:
	return FileAccess.file_exists(PATH)


## restore_position: move the player to the saved spot (validated against the world bounds).
static func load_game(restore_position: bool) -> bool:
	if not has_save():
		return false
	var txt := FileAccess.get_file_as_string(PATH)
	var data: Variant = JSON.parse_string(txt)
	if not (data is Dictionary):
		return false
	var d: Dictionary = data
	for id: String in (d.get("paint", {}) as Dictionary):
		var p: Dictionary = d.paint[id]
		Game.paint[StringName(id)] = {"color": Color.html(String(p.get("color", "c81a10"))), "finish": int(p.get("finish", 1)),
			"stripe": int(p.get("stripe", 0)), "stripe_color": Color.html(String(p.get("stripe_color", "f0f0f0"))),
			"rim": Color.html(String(p.get("rim", "b0b2b6")))}
	for id: String in (d.get("upgrades", {}) as Dictionary):
		Game.upgrades[StringName(id)] = d.upgrades[id]
	for id: String in (d.get("tuning", {}) as Dictionary):
		Game.tuning[StringName(id)] = d.tuning[id]
	var s: Dictionary = d.get("settings", {})
	for k: String in s:
		if Game.settings.has(k):
			Game.settings[k] = s[k]
	Game.personal_bests = d.get("personal_bests", {})
	Game.credits = int(d.get("credits", 0))
	if Game.sky != null:
		Game.sky.set_time(float(d.get("time", 12.0)))
		Game.sky.auto_weather = bool(d.get("auto_weather", true))
		Game.sky.set_weather(String(d.get("weather", "clear")), true)
	var idx := Game.car_index_by_name(String(d.get("car", "")))
	if idx < 0:
		idx = Game.current_car
	var xf: Transform3D = Game.world.get_spawn() if Game.world != null else Transform3D.IDENTITY
	var pos: Array = d.get("position", [])
	if restore_position and pos.size() == 3 and Game.world != null and Game.world.has_method("height_at"):
		var p := Vector3(float(pos[0]), float(pos[1]), float(pos[2]))
		var half: float = Game.world.wd.half - 60.0
		var ground: float = Game.world.height_at(p.x, p.z)
		if absf(p.x) < half and absf(p.z) < half and p.y > ground - 2.0 and p.y < ground + 30.0:
			xf = Game.world.nearest_road_transform(p)
	Game.main.spawn_player(idx, Transform3D(xf.basis, xf.origin + Vector3.UP * 0.5))
	Game.apply_assists()
	return true
