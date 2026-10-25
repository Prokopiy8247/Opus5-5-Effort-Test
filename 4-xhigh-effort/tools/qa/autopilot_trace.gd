extends Node
## Traces the autopilot: position, road distance, speed, steer and contacts every 0.25 s.

var t := 0.0
var next := 0.0


func _ready() -> void:
	Game.settings.traffic_density = 0.0
	Game.main.teleport_to(Game.main.find_place(Game.main.arg("where", "road:loop:0.02")))
	Game.main.driver.car = null


func _physics_process(delta: float) -> void:
	t += delta
	var car := Game.player
	var st: float = Game.world.autopilot_steer(car)
	car.in_steer = st
	var ped: Vector2 = Game.world.autopilot_pedals(car, 100.0)
	car.in_throttle = ped.x
	car.in_brake = ped.y
	if t >= next:
		next += 0.25
		var n: Dictionary = Game.world.roads.nearest(car.global_position, 200.0)
		var r: Dictionary = Game.world.wd.roads[n.road] if not n.is_empty() else {}
		var kind := (r.kind as PackedByteArray)[n.i] if not n.is_empty() else -1
		print("AP t=%.2f pos=(%.0f,%.1f,%.0f) kmh=%.0f steer=%+.2f road=%s i=%d dist=%.1f kind=%d ap=(%d,%d,%d) grounded=%d surf=%s" % [
			t, car.global_position.x, car.global_position.y, car.global_position.z, car.kmh(), st, r.get("id", "-"), n.get("i", -1),
			n.get("dist", -1.0), kind, Game.world._ap_road, Game.world._ap_i, Game.world._ap_dir, car.grounded, car.surface_name])
	var w0 := float(Game.main.arg("detail_from", "-1"))
	if w0 >= 0.0 and t >= w0 and t <= w0 + float(Game.main.arg("detail_len", "4")) and fmod(t, 0.1) < delta:
		var parts := []
		for w in car.wheels:
			var nm := "-"
			if w.contact and w.collider != null:
				nm = String(w.collider.get_meta("road", "terrain" if w.collider.has_meta("terrain") else String((w.collider as Node).name)))
			parts.append("%s(%.2f,len %.2f)" % [nm, w.point.y if w.contact else 0.0, w.length])
		var hits := []
		for b in car.get_colliding_bodies():
			hits.append("%s[%s]" % [b.name, String(b.get_meta("road", "terrain" if b.has_meta("terrain") else "-"))])
		print("WHEELS t=%.2f pos=%s kmh=%.1f thr=%.2f brk=%.2f gear=%d up=%.2f %s | contacts %s" % [t, str(car.global_position.snapped(Vector3(0.1,0.1,0.1))), car.kmh(), car.throttle_out, car.brake_out, car.gear, car.global_transform.basis.y.y, " ".join(parts), " ".join(hits)])
	if t > float(Game.main.arg("secs", "16")):
		get_tree().quit(0)
