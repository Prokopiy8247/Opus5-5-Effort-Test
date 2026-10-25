extends Node
## Rewind check: drive for 6 s on the expressway, hold the rewind action for 2 s and verify the car
## went back along its path (and is stopped while rewinding), then release and verify it drives on.
##   godot --headless --fixed-fps 120 --path . -- --qa=rewind_test --fresh

var mode := "drive"
var path: Array[Vector3] = []


func _ready() -> void:
	Game.traffic.set_process(false)
	Game.traffic.set_physics_process(false)
	Game.main.driver.car = null
	Game.main.teleport_to(Game.main.find_place("road:highway:0.2"))
	_run()


func _run() -> void:
	await get_tree().create_timer(6.0).timeout
	var p_before := Game.player.global_position
	var v_before := Game.player.speed_abs
	mode = "hold"
	Input.action_press("rewind")
	await get_tree().create_timer(2.0).timeout
	var p_rew := Game.player.global_position
	var v_rew := Game.player.speed_abs
	Input.action_release("rewind")
	mode = "drive"
	await get_tree().create_timer(2.0).timeout
	var v_after := Game.player.speed_abs
	# where on the recorded path did we end up? (index of the closest sample)
	var best := 0
	for i in path.size():
		if path[i].distance_to(p_rew) < path[best].distance_to(p_rew):
			best = i
	var r := {"moved_back_m": snappedf(p_before.distance_to(p_rew), 0.1), "speed_before_kmh": roundi(v_before * 3.6),
		"speed_while_rewinding_kmh": roundi(v_rew * 3.6), "speed_after_release_kmh": roundi(v_after * 3.6),
		"closest_path_sample_s_ago": snappedf((path.size() - best) / 120.0, 0.1)}
	r["ok"] = float(r.moved_back_m) > 20.0 and v_rew < 1.0 and v_after > 5.0 and float(r.closest_path_sample_s_ago) > 3.0
	print("REWIND_TEST ", JSON.stringify(r))
	get_tree().quit(0)


func _physics_process(_d: float) -> void:
	var car := Game.player
	if car == null:
		return
	if mode == "drive":
		path.append(car.global_position)
		car.in_steer = Game.world.autopilot_steer(car)
		var ped: Vector2 = Game.world.autopilot_pedals(car, 120.0)
		car.in_throttle = ped.x
		car.in_brake = ped.y
	else:
		car.in_throttle = 0.0
		car.in_brake = 0.0
