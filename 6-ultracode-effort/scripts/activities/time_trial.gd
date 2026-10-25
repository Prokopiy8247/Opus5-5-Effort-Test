extends "res://scripts/activities/road_race.gd"
## Time trial: one flying-finish lap of a loop road (the Sunward Ring) with a checkpoint every ~1.5 km.
## Same start flow as a road race (stop in the start zone, 3-2-1), no rivals; the start arch is the finish.


func _start_banner() -> String:
	return "TIME TRIAL"


func _opponent_count() -> int:
	return 0


func build() -> void:
	var last := data.gates.size() - 1
	for i in last:
		if i == 0:
			gates.append(manager.make_gate(self, 0, gate_s(0), &"arch", _start_banner(), true, data.dir))
		else:
			var g: Node3D = manager.make_gate(self, i, gate_s(i), &"checkpoint", "CHECKPOINT %d" % i, false, data.dir)
			g.visible = false
			gates.append(g)


func _node(i: int) -> int:
	return 0 if i >= data.gates.size() - 1 else i


func _finish_visible_idle() -> bool:
	return false


func _finish_race(car: CarController) -> void:
	var t := _t
	print("[activity] %s lap time %.2f" % [data.id, t])
	finish(t, false, fmt_time(t), -1, "Lap time", time_shown)
