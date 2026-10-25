extends Node
## Environment / fx regressions in the real game (needs a renderer, 1920x1080 recommended):
##   Godot_console.exe --path <project> --resolution 1920x1080 res://tools/tests/env_regression_test.tscn
##       -- [--env-test=all | any of tunnel,drive,dust,flash,rain,photo] [--shots=res://qa_output/env_regression]
## Checks: no sun inside the Ember Spur tunnel and the same interior by day and night (p40), dry tunnel in
## rain: no spray / wet surface / grip loss (p41), tunnel lighting and headlights follow the player's car,
## interior dark seen from outside (p43), no stale dust after an instant weather / time cut, also in paused
## photo mode (p44), no dust layer in rain (p45), night lightning far below daylight (p46), no rain drawn
## under the tunnel roof at the portals (q38: streak pixels with the per-drop shelter on / off, open-air
## control), photo-mode time slider applies street lamps, settlement night windows and the headlight request
## at once while the world stays frozen (q33, environment side).
## Prints "[envreg] PASS|FAIL <check>" lines and "[envreg] failures: N". Changes no user settings.

const QaAutopilot := preload("res://scripts/main/qa_autopilot.gd")
const MenuBase := preload("res://scripts/ui/menu_base.gd")
const Mats := preload("res://scripts/world/dressing_materials.gd")

var main: Node
var mode := "all"
var shots := ""
var fails := 0


func _ready() -> void:
	SaveGame.enabled = false
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--env-test="):
			mode = a.get_slice("=", 1)
		elif a.begins_with("--shots="):
			shots = a.get_slice("=", 1)
	if shots != "":
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(shots))
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(main)
	_run.call_deferred()


func _wants(part: String) -> bool:
	var parts := mode.split(",")
	return parts.has("all") or parts.has(part)


func _check(label: String, ok: bool, detail: String) -> void:
	print("[envreg] %s %s  %s" % ["PASS" if ok else "FAIL", label, detail])
	if not ok:
		fails += 1


func _wait(s: float) -> void:
	await get_tree().create_timer(s).timeout


func _settle() -> void:
	var w := Game.world as World
	var t0 := Time.get_ticks_msec()
	await get_tree().process_frame
	await get_tree().process_frame
	while not w.is_ready_near() and Time.get_ticks_msec() - t0 < 25000:
		await get_tree().process_frame


static func _lum(img: Image, x0: float, y0: float, x1: float, y1: float) -> float:
	var w := img.get_width()
	var h := img.get_height()
	var sum := 0.0
	var n := 0
	for y in range(int(y0 * h), int(y1 * h), 6):
		for x in range(int(x0 * w), int(x1 * w), 6):
			sum += img.get_pixel(x, y).get_luminance()
			n += 1
	return sum / maxf(n, 1)


## Mean luminance of the frame and of the road below a chase-camera car (the image is kept as "img").
func _shot(name: String) -> Dictionary:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if shots != "" and name != "":
		img.save_png(ProjectSettings.globalize_path(shots.path_join(name + ".png")))
	return {"frame": _lum(img, 0.0, 0.0, 1.0, 1.0), "road": _lum(img, 0.3, 0.74, 0.7, 0.92), "img": img}


static func _lum_rect(r: Dictionary, x0: float, y0: float, x1: float, y1: float) -> float:
	return _lum(r["img"] as Image, x0, y0, x1, y1)


func _rig() -> CameraRig:
	return main.get("camera_rig")


func _sun_energy() -> float:
	var sun: DirectionalLight3D = Game.env.get("sun")
	return sun.light_energy if sun.visible else 0.0


func _place(road: RoadNetwork.Road, s: float) -> void:
	main.call("teleport_to", {"position": road.surface_point(s, road.lane_offset(1)), "forward": road.flat_tangent_at(s)})


func _hold() -> void:
	var car := Game.player_car
	car.in_throttle = 0.0
	car.in_brake = 0.0
	car.in_handbrake = 1.0


func _run() -> void:
	while main.get("is_loading"):
		await get_tree().process_frame
	(main.get("car_input") as CarInput).enabled = false
	if Game.traffic != null and Game.traffic.has_method("set_density_cap"):
		Game.traffic.call("set_density_cap", 0.0)
	_rig().set_mode(0, false)
	Game.env.call("set_time_scale", 0.0)
	Game.set_time_of_day(12.0)
	Game.set_weather("clear", true)
	if Game.hud is CanvasLayer:
		(Game.hud as CanvasLayer).visible = false
	if _wants("tunnel"):
		await _tunnel()
	if _wants("drive"):
		await _drive_rain()
	if _wants("dust"):
		await _dust()
	if _wants("flash"):
		await _flash()
	if _wants("rain"):
		await _rain_shelter()
	if _wants("photo"):
		await _photo_lights()
	print("[envreg] failures: %d" % fails)
	get_tree().quit(1 if fails > 0 else 0)


func _tunnel() -> void:
	var road := (Game.world as World).data.network.get_road("ring")
	var tl: Node = Game.env.get("tunnels")
	_check("tunnel probes built", tl != null and not (tl.get("spans") as Array).is_empty(), "spans=%d" % (tl.get("spans") as Array).size() if tl else "no TunnelLight")
	var deep: Array[float] = [7275.0, 7330.0, 7400.0, 7475.0]
	var road_lum := {12: 0.0, 23: 0.0}
	for h: int in [12, 23]:
		Game.set_time_of_day(float(h))
		var max_sun := 0.0
		for s in deep:
			_place(road, s)
			await _settle()
			_hold()
			await _wait(2.0)
			var r := await _shot("tunnel_s%d_%02d" % [int(s), h])
			road_lum[h] += float(r["road"]) / deep.size()
			max_sun = maxf(max_sun, _sun_energy())
		if h == 12:
			_check("p40 no sun deep in the tunnel at noon", max_sun < 0.01 and float(road_lum[12]) < 0.12, "sun_e=%.3f road_lum=%.3f (was ~0.32)" % [max_sun, road_lum[12]])
	var ratio := float(road_lum[12]) / maxf(float(road_lum[23]), 0.001)
	_check("p40 tunnel interior alike by day and night", ratio > 0.6 and ratio < 1.6, "noon/night road %.3f/%.3f" % [road_lum[12], road_lum[23]])
	# Headlights follow the car: park inside, move the camera out of the tube.
	Game.set_time_of_day(12.0)
	_place(road, 7245.0)
	await _settle()
	_hold()
	await _wait(2.0)
	var car := Game.player_car
	var on_chase := car.headlights_on
	var rig := _rig()
	rig.active = false
	rig.global_position = car.global_position + road.right_at(7245.0) * 9.0 + Vector3(0, 2.0, 0)
	rig.look_at(car.global_position)
	await _wait(1.0)
	_check("p43 headlights follow the car, not the camera", on_chase and car.headlights_on and bool(Game.env.call("lights_needed", car.global_position)),
		"chase=%s side_cam=%s" % [str(on_chase), str(car.headlights_on)])
	# The interior seen from outside the portal is lamp-lit, not a daylit hall: compare the tube's inside
	# with and without the tunnel probes (without them it is lit by the open sky, as before the fix).
	var mouth := float(tl.get("spans")[0].get("s0")) if tl != null and not (tl.get("spans") as Array).is_empty() else 7200.0
	rig.global_position = road.surface_point(mouth - 12.0, road.lane_offset(1)) + Vector3(0, 1.6, 0)
	rig.look_at(road.surface_point(mouth + 40.0, road.lane_offset(1)) + Vector3(0, 2.0, 0))
	await _wait(2.0)
	var lit := []
	for probes_on: bool in [true, false]:
		for c in tl.get_children():
			if c is ReflectionProbe:
				(c as ReflectionProbe).visible = probes_on
		await _wait(0.5)
		var r := await _shot("tunnel_from_outside_probes_%s" % ("on" if probes_on else "off"))
		lit.append(_lum_rect(r, 0.35, 0.3, 0.65, 0.6))
	for c in tl.get_children():
		if c is ReflectionProbe:
			(c as ReflectionProbe).visible = true
	_check("p43 interior dark from outside the portal", float(lit[0]) < 0.7 * float(lit[1]) and float(Game.env.get("_tunnel_t")) < 0.01,
		"inside lum %.3f (open-sky lit %.3f) eye_t=%.2f" % [lit[0], lit[1], float(Game.env.get("_tunnel_t"))])
	rig.active = true


func _drive_rain() -> void:
	var w := Game.world as World
	var road := w.data.network.get_road("ring")
	Game.set_time_of_day(12.0)
	Game.set_weather("rain", true)
	var f := QaAutopilot.new()
	f.setup(w.data.network, road, 7052.0)
	f.target_speed = 80.0 / 3.6
	main.call("teleport_to", {"position": f.lane_point(7052.0), "forward": road.flat_tangent_at(7052.0)})
	await _settle()
	await _wait(1.0)
	var car := Game.player_car
	var fx: Node = car.get_node_or_null(^"CarEffects")
	var min_kmh := 999.0
	var min_at := ""
	var max_spray := 0.0
	var wet_hits := 0
	var max_sun := 0.0
	var lights_off := 0
	var t := 0.0
	var tl: Node = Game.env.get("tunnels")
	while f.s < 7650.0 and t < 60.0:
		await get_tree().physics_frame
		f.drive(Game.player_car)
		await get_tree().process_frame
		t += get_process_delta_time()
		var d := float(tl.call("depth", car.global_position))
		if d > 10.0:
			# Speed in the bend away from the portals (where the wet tunnel used to put the car into the wall).
			if d > 40.0 and car.get_speed_kmh() < min_kmh:
				min_kmh = car.get_speed_kmh()
				min_at = "s=%d lat=%.1f scrape=%s" % [int(f.s), (car.global_position - road.point_at(f.s)).dot(road.right_at(f.s)),
					str((fx.call(&"debug_state") as Dictionary).get("scrape", -1.0)) if fx != null else "-"]
			if fx != null:
				max_spray = maxf(max_spray, float((fx.call(&"debug_state") as Dictionary).get("spray", 0.0)))
			for wh in car.wheels:
				if wh.contact and wh.surface != null and wh.surface.id == &"asphalt_wet":
					wet_hits += 1
			if not car.headlights_on:
				lights_off += 1
		if d > 50.0:
			max_sun = maxf(max_sun, _sun_energy())
	_check("p41 dry tunnel in rain (no spray, no wet surface)", max_spray < 0.01 and wet_hits == 0, "spray=%.2f wet_wheel_samples=%d" % [max_spray, wet_hits])
	_check("p41 rain: autopilot clears the tunnel bend", min_kmh > 55.0, "min %.0f km/h at %s (dry ~70)" % [min_kmh, min_at])
	_check("p40/p43 while driving: no sun deep inside, lights on", max_sun < 0.01 and lights_off == 0, "sun_e=%.3f lights_off_frames=%d" % [max_sun, lights_off])
	Game.set_weather("clear", true)


func _dust() -> void:
	var pr: Node = Game.env.get("precipitation")
	var drift := pr.get("_drift") as GPUParticles3D
	Game.set_time_of_day(14.0)
	Game.set_weather("cloudy", true)
	Game.teleport("Ring Road - Mesa Straight")
	await _settle()
	_hold()
	await _wait(6.0)
	_check("mesa dust active in cloudy wind (reference)", drift.emitting and float(pr.get("dust_amount")) > 0.2, "dust=%.2f" % float(pr.get("dust_amount")))
	Game.set_weather("clear", true)
	Game.set_time_of_day(22.0)
	await _wait(0.3)
	var r0 := await _shot("dust_clear22_cut")
	await _wait(7.0)
	var rb := await _shot("dust_clear22_baseline")
	_check("p44 no stale dust after an instant clear + night", absf(float(r0["frame"]) - float(rb["frame"])) < 0.02, "cut %.3f vs settled %.3f" % [r0["frame"], rb["frame"]])
	# Photo mode pauses the tree: the stale particles would never expire.
	Game.set_time_of_day(14.0)
	Game.set_weather("cloudy", true)
	await _wait(7.0)
	var photo: Node = MenuBase.find_menu(get_tree(), &"photo")
	if photo != null:
		photo.call(&"open_menu")
		await _wait(0.5)
		photo.call(&"_set_weather", "clear")
		Game.set_time_of_day(22.0)
		photo.call(&"_pulse_env")
		await _wait(3.0)
		var rp := await _shot("dust_photo_clear22")
		_check("p44 no frozen dust in paused photo mode", get_tree().paused and absf(float(rp["frame"]) - float(rb["frame"])) < 0.03,
			"paused=%s photo %.3f vs settled %.3f" % [str(get_tree().paused), rp["frame"], rb["frame"]])
		photo.call(&"close_menu")
		await _wait(1.0)
	else:
		_check("p44 photo mode available", false, "photo menu not found")
	Game.set_time_of_day(15.0)
	Game.set_weather("rain", true)
	await _wait(4.0)
	await _shot("dust_mesa_rain")
	_check("p45 no dust layer in rain", not drift.emitting and float(pr.get("dust_amount")) < 0.001, "dust=%.3f emitting=%s" % [float(pr.get("dust_amount")), str(drift.emitting)])
	Game.set_weather("clear", true)


func _flash() -> void:
	Game.teleport("Ring Road - Festival Start")
	await _settle()
	_hold()
	_rig().set_mode(1, false)
	var storm: Node = Game.env.get("storm")
	Game.set_weather("clear", true)
	Game.set_time_of_day(12.0)
	await _wait(3.0)
	var noon := await _shot("flash_clear_noon")
	Game.set_weather("storm", true)
	Game.set_time_of_day(22.0)
	await _wait(3.0)
	storm.set("_timer", 9999.0)
	var base := await _shot("flash_storm_night")
	Game.env.call("strike_lightning", 900.0)
	var peak := 0.0
	for k in 4:
		# Hold the flash at its first-pulse peak so the capture does not depend on frame timing.
		storm.set("_t", 0.0)
		var r := await _shot("flash_storm_night_bolt" if k == 3 else "")
		peak = maxf(peak, float(r["frame"]))
	_check("p46 night lightning stays far below daylight", peak < 0.6 * float(noon["frame"]) and peak > float(base["frame"]) * 1.5,
		"night %.3f -> flash %.3f, clear noon %.3f (was ~0.74 vs 0.58)" % [base["frame"], peak, noon["frame"]])
	Game.set_weather("clear", true)


# ------------------------------------------------------------------ q38 rain under the tunnel roof

func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


## Share of sampled pixels whose luminance differs by more than 0.035 between two frames.
static func _diff(a: Image, b: Image) -> float:
	var n := 0
	var hit := 0
	for y in range(0, a.get_height(), 2):
		for x in range(0, a.get_width(), 2):
			n += 1
			if absf(a.get_pixel(x, y).get_luminance() - b.get_pixel(x, y).get_luminance()) > 0.035:
				hit += 1
	return float(hit) / maxf(n, 1)


## Streak pixels in the current view: frame with rain minus frame without, minus the frame-to-frame noise.
## Two passes, the smaller counts (a one-off whole-frame change during a pass is not rain).
func _streaks(rain: GPUParticles3D, name: String) -> float:
	var best := INF
	for k in 2:
		rain.visible = false
		await _frames(4)
		var n1: Image = (await _shot(""))["img"]
		await _frames(2)
		var n2: Image = (await _shot(""))["img"]
		rain.visible = true
		await _frames(4)
		var r := await _shot(name if k == 0 else "")
		var d := maxf(_diff(r["img"] as Image, n2) - _diff(n1, n2), 0.0)
		if d > 0.05:
			print("[envreg] %s pass %d: %.3f of the frame changed (mean %.4f, without rain %.4f)" % [name, k, d, r["frame"], _lum(n2, 0.0, 0.0, 1.0, 1.0)])
		best = minf(best, d)
	return best


func _rain_shelter() -> void:
	var road := (Game.world as World).data.network.get_road("ring")
	var tl: Node = Game.env.get("tunnels")
	var pr: Node = Game.env.get("precipitation")
	var rain := pr.get("_rain") as GPUParticles3D
	var storm: Node = Game.env.get("storm")
	var s0 := float(tl.get("spans")[0].get("s0")) if tl != null and not (tl.get("spans") as Array).is_empty() else 7200.0
	var segs: Array[Vector4] = tl.call("roof_segments")
	var no_segs: Array[Vector4] = []
	Game.set_time_of_day(12.0)
	Game.set_weather("storm", true)
	storm.set("_timer", 9999.0)
	_place(road, s0 - 40.0)
	await _settle()
	_hold()
	await _wait(2.0)
	var rig := _rig()
	rig.active = false
	var lane := road.lane_offset(1)
	# [name, eye s, eye lateral, eye height, look s, look lateral, look height, max streak share]. Every view
	# sees only the tube interior (the 3 m view turns slightly inward so the open portal edge stays out).
	var views: Array = [
		["rain_wall_in03", s0 + 3.0, lane, 1.6, s0 + 6.0, 5.5, 2.0, 0.0006],
		["rain_lookin_in02", s0 + 2.0, lane, 1.5, s0 + 30.0, lane, 3.0, 0.0006],
		["rain_wall_in12", s0 + 12.0, lane, 1.6, s0 + 12.0, 5.5, 2.0, 0.0006],
		["rain_lookin_out01", s0 - 1.0, lane, 1.5, s0 + 25.0, lane, 3.0, 0.0015],
	]
	for v: Array in views:
		var eye := road.surface_point(float(v[1]), float(v[2])) + Vector3.UP * float(v[3])
		var look := road.surface_point(float(v[4]), float(v[5])) + Vector3.UP * float(v[6])
		rig.global_transform = Transform3D(Basis(), eye).looking_at(look, Vector3.UP)
		# Let the tunnel eye adaptation settle (exposure eases over about a second).
		await _wait(3.0)
		var on := await _streaks(rain, String(v[0]))
		pr.call("set_shelters", no_segs)
		await _frames(3)
		var off := await _streaks(rain, String(v[0]) + "_shelter_off")
		pr.call("set_shelters", segs)
		await _frames(3)
		_check("q38 no rain under the tunnel roof: %s" % v[0], on <= float(v[7]),
			"streak pixels %.4f with the shelter, %.4f without (amount %.2f, %d covered pieces tested)" % [on, off, rain.amount_ratio, int(pr.call("shelter_count"))])
	# Open-air control: the same measurement sees the rain away from the tunnel.
	var eye2 := road.surface_point(s0 - 60.0, lane) + Vector3.UP * 1.5
	rig.global_transform = Transform3D(Basis(), eye2).looking_at(road.surface_point(s0 - 35.0, lane), Vector3.UP)
	await _wait(0.8)
	var open := await _streaks(rain, "rain_open_control")
	_check("q38 open-air control: rain is drawn outside the tunnel", open > 0.004, "streak pixels %.4f" % open)
	# Shots for the eye: the default chase camera with the car parked in the west mouth, and the mouth from outside.
	rig.active = true
	_rig().set_mode(0, false)
	for d: float in [3.0, 6.0]:
		_place(road, s0 + d)
		await _settle()
		_hold()
		await _wait(2.0)
		await _shot("rain_chase_car_in%02d" % int(d))
	rig.active = false
	rig.global_transform = Transform3D(Basis(), road.surface_point(s0 - 14.0, lane) + Vector3.UP * 1.6).looking_at(road.surface_point(s0 + 20.0, lane) + Vector3.UP * 2.5, Vector3.UP)
	await _wait(0.8)
	await _shot("rain_mouth_from_outside14")
	rig.active = true
	Game.set_weather("clear", true)


# ------------------------------------------------------------------ q33 photo-mode time slider (env side)

func _light_state() -> Dictionary:
	var lamps: Node = Game.env.get("lamps")
	var e_max := 0.0
	for l: OmniLight3D in lamps.get("_lights"):
		if l.visible:
			e_max = maxf(e_max, l.light_energy)
	return {"lit": int(lamps.call("lit_count")), "energy": e_max, "night": float(Mats.get_param(&"night", -1.0)),
		"head": Game.player_car.headlights_on, "street": float(lamps.get("street_factor")), "hour": Game.get_time_of_day()}


func _photo_lights() -> void:
	Game.set_weather("clear", true)
	Game.set_time_of_day(12.0)
	Game.teleport("Millbrook")
	await _settle()
	_hold()
	_rig().set_mode(1, false)
	await _wait(2.0)
	Game.set_time_of_day(22.0)
	await _wait(3.0)
	var ref := _light_state()
	var ref_shot := await _shot("photo_ref_night_no_photo")
	Game.set_time_of_day(12.0)
	await _wait(3.0)
	var noon := _light_state()
	var noon_shot := await _shot("photo_ref_noon_no_photo")
	var photo: Node = MenuBase.find_menu(get_tree(), &"photo")
	if photo == null:
		_check("q33 photo mode available", false, "photo menu not found")
		return
	# The clock runs (as in normal play) to show it stays frozen while photo mode applies a change.
	Game.env.call("set_time_scale", 1.0)
	photo.call(&"open_menu")
	await _wait(0.5)
	var slider := (photo.get("_sliders") as Dictionary)["time"] as HSlider
	slider.value = 22.0
	await _wait(1.5)
	var night := _light_state()
	var night_shot := await _shot("photo_slider_22")
	_check("q33 photo 12->22: street lamps lit at once", get_tree().paused and night["lit"] >= mini(int(ref["lit"]), 1) and float(night["energy"]) >= 0.95 * float(ref["energy"]),
		"lamps %d at %.2f (no photo mode: %d at %.2f; was 0-11 at 0.00-0.21)" % [night["lit"], night["energy"], ref["lit"], ref["energy"]])
	_check("q33 photo 12->22: settlement windows at night", float(night["night"]) > 0.99, "night %.2f (was 0.00)" % night["night"])
	_check("q33 photo 12->22: headlights requested, clock frozen", bool(night["head"]) and absf(float(night["hour"]) - 22.0) < 0.0005,
		"headlights_on %s, hour %.4f" % [str(night["head"]), night["hour"]])
	print("[envreg] q33 frame luminance: photo 22:00 %.3f vs no-photo 22:00 %.3f (was 0.061 vs 0.151)" % [night_shot["frame"], ref_shot["frame"]])
	slider.value = 12.0
	await _wait(1.5)
	var day := _light_state()
	var day_shot := await _shot("photo_slider_12")
	_check("q33 photo 22->12: lamps, windows and headlights off at once", int(day["lit"]) <= int(noon["lit"]) and float(day["night"]) < 0.01 and not bool(day["head"]),
		"lamps %d (noon %d), night %.2f, headlights_on %s" % [day["lit"], noon["lit"], day["night"], str(day["head"])])
	print("[envreg] q33 frame luminance: photo 12:00 %.3f vs no-photo 12:00 %.3f" % [day_shot["frame"], noon_shot["frame"]])
	photo.call(&"close_menu")
	Game.env.call("set_time_scale", 0.0)
	await _wait(1.0)
