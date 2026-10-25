extends Node
## Save/load round trip: change car, paint, upgrades, time, weather, personal bests, credits and
## position; save; scramble everything; load; compare. An existing save file is backed up first
## and restored afterwards.
##   godot --headless --path . -- --qa=save_test --fresh


func _ready() -> void:
	_run()


func _run() -> void:
	await get_tree().create_timer(1.0).timeout
	var path := SaveSystem.PATH
	var backup := ""
	if FileAccess.file_exists(path):
		backup = FileAccess.get_file_as_string(path)
	# 1. a distinctive state
	Game.main.spawn_player(Game.car_index_by_name("RallyxTerra"), Game.player.global_transform)
	var id := Game.player.data.id
	Game.paint_for(id).color = Color(0.1, 0.8, 0.3)
	Game.paint_for(id).finish = 3
	Game.upgrades_for(id).tires = 3
	Game.sky.set_time(19.25)
	Game.sky.auto_weather = false
	Game.sky.set_weather("fog", true)
	Game.personal_bests["trap_highway"] = 251.0
	Game.credits = 4321
	Game.main.teleport_to(Game.main.find_place("lighthouse"))
	await get_tree().create_timer(0.5).timeout
	var saved_pos := Game.player.global_position
	var ok_save := SaveSystem.save_game()
	# 2. scramble
	Game.main.spawn_player(Game.car_index_by_name("AureliaRoadster"), Game.world.get_spawn())
	Game.paint_for(id).color = Color(1, 1, 1)
	Game.upgrades_for(id).tires = 0
	Game.sky.set_time(8.0)
	Game.sky.set_weather("clear", true)
	Game.personal_bests = {}
	Game.credits = 0
	await get_tree().create_timer(0.3).timeout
	# 3. load and compare
	var ok_load := SaveSystem.load_game(true)
	await get_tree().create_timer(0.3).timeout
	var r := {
		"saved": ok_save, "loaded": ok_load,
		"car": String(Game.player.data.id) == "RallyxTerra",
		"paint": (Game.paint_for(id).color as Color).is_equal_approx(Color(0.1, 0.8, 0.3)) or (Game.paint_for(id).color as Color).g > 0.75,
		"finish": int(Game.paint_for(id).finish) == 3,
		"upgrade": int(Game.upgrades_for(id).tires) == 3,
		"time": absf(float(Game.sky.time_of_day) - 19.25) < 0.1,
		"weather": String(Game.sky.target.id) == "fog",
		"pb": float(Game.personal_bests.get("trap_highway", 0.0)) == 251.0,
		"credits": Game.credits == 4321,
		"position_m": snappedf(Game.player.global_position.distance_to(saved_pos), 0.1),
	}
	r["all_ok"] = r.saved and r.loaded and r.car and r.paint and r.finish and r.upgrade and r.time and r.weather and r.pb and r.credits and float(r.position_m) < 30.0
	if backup != "":
		var f := FileAccess.open(path, FileAccess.WRITE)
		f.store_string(backup)
		f.close()
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	print("SAVE_TEST ", JSON.stringify(r))
	get_tree().quit(0)
