extends Node
## QA script: drive 8 s, hold rewind for 2 s, release; the car must be back where it was ~4 s earlier
## and drive on afterwards.
## Run: Godot_console.exe --path . -- --fresh --qa=script --script_path=res://tools/tests/rewind_check.gd


func _phys(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func run(_qa: Node) -> void:
	var car := Game.player_car
	var ap: Node = Game.world.call("create_autopilot", car)
	ap.set("max_speed_kmh", 100.0)
	await _phys(120 * 4)
	var p4 := car.global_position
	await _phys(120 * 4)
	var p8 := car.global_position
	ap.set("enabled", false)
	Input.action_press("rewind")
	await _phys(240)
	Input.action_release("rewind")
	await _phys(2)
	var pr := Game.player_car.global_position
	print("[rewind] travelled %.0f m in the last 4 s; after rewind %.1f m from the 4 s mark, %.0f m from the end; frozen=%s" % [
		p4.distance_to(p8), pr.distance_to(p4), pr.distance_to(p8), str(Game.player_car.freeze)])
	ap.set("enabled", true)
	await _phys(240)
	print("[rewind] 2 s after release: speed %.0f km/h, moved %.0f m" % [Game.player_car.speed_kmh, Game.player_car.global_position.distance_to(pr)])
	ap.queue_free()
