extends Node
## QA script: spawns every car, lets it settle and prints suspension state + ride height.
## Run: Godot_console.exe --path . -- --fresh --qa=script --script_path=res://tools/tests/ride_height_check.gd


func run(qa: Node) -> void:
	for i in Game.car_defs.size():
		Game.main.call("switch_car", i)
		var car := Game.player_car
		car.input_throttle = 0.0
		car.input_brake = 1.0
		for f in 150:
			await get_tree().physics_frame
		var d: CarDefinition = car.definition
		var line := "%-20s travel_down=%.3f up=%.3f |" % [d.id, d.travel_down, d.travel_up]
		for w in car.wheels:
			line += " %s:%s x=%.3f r=%.3f" % [w.name, "c" if w.contact else "-", w.x, w.radius]
		var space := car.get_world_3d().direct_space_state
		var q := PhysicsRayQueryParameters3D.create(car.global_position + Vector3.UP * 2.0, car.global_position + Vector3.DOWN * 3.0)
		q.exclude = [car.get_rid()]
		var hit := space.intersect_ray(q)
		var gh := (car.global_position.y - (hit.position as Vector3).y) if not hit.is_empty() else -1.0
		line += " | origin above ground=%.3f v=%.2f" % [gh, car.linear_velocity.length()]
		print("[ride] ", line)
		await qa.call("_shot", "ride_%02d.png" % (i + 1))
	Game.player_car.input_brake = 0.0
