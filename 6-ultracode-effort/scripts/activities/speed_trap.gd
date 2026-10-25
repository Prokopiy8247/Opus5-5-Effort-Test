extends "res://scripts/activities/activity_base.gd"
## Speed trap: a single camera gantry; records the speed as the player passes (either direction).

const MIN_KMH := 25.0
const REARM := 4.0


func build() -> void:
	gates.append(manager.make_gate(self, 0, gate_s(0), &"gantry", "SPEED TRAP", true, 1))


func on_gate(_index: int, car: CarController, _along: float) -> void:
	if cooldown > 0.0:
		return
	var kmh := car.get_speed_kmh()
	if kmh < MIN_KMH:
		return
	cooldown = REARM
	manager.flash_gate(gates[0], 1.0)
	var old: Variant = personal_best()
	hud(speed_text(kmh), "Speed trap" + ("  ·  PB %s" % speed_text(float(old)) if old != null else ""), 1.0)
	finish(kmh, true, speed_text(kmh), -1, "", speed_shown)


func end() -> void:
	running = false
	manager.end_session(self)
