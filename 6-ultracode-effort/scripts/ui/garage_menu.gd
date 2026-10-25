extends "res://scripts/ui/menu_base.gd"
## Garage (toggle_garage: F1 / Tab): CARS | PAINT | UPGRADES | TUNING pages (menu_garage_*.gd) with a
## slow showroom orbit camera around the player car on the right of the screen. The orbit distance and the
## lens shift keep the whole car inside the free area right of the menu column at every orbit angle, and
## the camera rises over fences / walls between it and the car. In the dark (night, storm) a camera-side
## key light and a fill light switch on so paint / stripe / rim previews stay readable.
## Changes persist through SaveGame (Game.paints / upgrades / tuning).

const Stats := preload("res://scripts/ui/menu_car_stats.gd")
const PAGE_SCRIPTS: Array[Script] = [
	preload("res://scripts/ui/menu_garage_cars.gd"), preload("res://scripts/ui/menu_garage_paint.gd"),
	preload("res://scripts/ui/menu_garage_upgrades.gd"), preload("res://scripts/ui/menu_garage_tuning.gd"),
]
const TABS: Array[String] = ["Cars", "Paint", "Upgrades", "Tuning"]
const COL_W := 1120.0
## Showroom lights at full darkness (scaled by 1 - env.get_light_level(); off in daylight).
const KEY_ENERGY := 2.4
const FILL_ENERGY := 1.0
const LIGHT_RANGE := 16.0
const SHOWROOM_FOV := 34.0
## Gaps (px) between the car and the menu column / the right screen edge.
const FIT_GAP_LEFT := 28.0
const FIT_GAP_RIGHT := 40.0
## Part of the half screen height the car may use (the caption sits in the bottom right corner).
const FIT_V := 0.5
## Orbit yaw samples for the fit: one distance per car and pitch, so the car does not zoom while it turns.
const FIT_YAWS := 16
## Highest extra pitch (rad) the camera rises by to look over something between it and the car.
const LIFT_MAX := 0.5
const LIFT_STEPS := 5
## Physics layers the showroom view must not pass through: ground / buildings (1) and barriers (6: fences,
## walls, rails), which have no layer-1 collider.
const VIEW_MASK := 1 | 32

var tab: int = 0
## Page nodes in TABS order (each has refresh() and focus_first()).
var pages: Array[Control] = []
var _tab_buttons: Array[Button] = []
var _stats_cache: Dictionary = {}
var _caption_box: VBoxContainer
var _caption_name: Label
var _caption_sub: Label
var _caption_badge: Control

# Showroom camera
var _orbit: float = 0.0
var _orbit_pitch: float = 0.2
var _orbit_idle: float = 0.0
var _lift: float = 0.0
var _ray := PhysicsRayQueryParameters3D.new()
var _col: Control
var _box_car: CarController
var _box := AABB()
var _key_light: OmniLight3D
var _fill_light: OmniLight3D


func _init() -> void:
	super._init()
	menu_id = &"garage"
	toggle_action = &"toggle_garage"
	hides_hud = true
	_ray.collision_mask = VIEW_MASK


func _build() -> void:
	var fade := Style.side_fade(0.95, 0.0, Color(0.02, 0.025, 0.05), 0.68)
	fade.anchor_right = 0.86
	fade.anchor_bottom = 1.0
	add_child(fade)

	var col := Style.vbox(14)
	col.anchor_bottom = 1.0
	col.offset_left = 64
	col.offset_top = 44
	col.offset_right = 64 + COL_W
	col.offset_bottom = -34
	add_child(col)
	_col = col

	var head := Style.hbox(18)
	var tv := Style.vbox(4)
	tv.add_child(Style.title("Garage", 48))
	tv.add_child(Style.accent_bar(160, 5))
	head.add_child(tv)
	var sub := Style.label("%s  ·  %d cars" % [Game.FESTIVAL_NAME, Game.get_car_catalog().size()], 20, Style.TEXT_DIM, 500, 1)
	sub.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(sub)
	col.add_child(head)

	var tabs := Style.hbox(8)
	var group := ButtonGroup.new()
	for i in TABS.size():
		var b := Style.button(TABS[i].to_upper(), select_tab.bind(i), 168, 50)
		b.toggle_mode = true
		b.button_group = group
		b.add_theme_font_override("font", Style.font(700, 2))
		_tab_buttons.append(b)
		tabs.add_child(b)
	tabs.add_child(Style.expander())
	tabs.add_child(Style.hint_bar([["Q", "E", "Switch tab"]]))
	col.add_child(tabs)

	var stack := Control.new()
	stack.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(stack)
	for scr: Script in PAGE_SCRIPTS:
		var page: Control = scr.new()
		page.set("garage", self)
		page.visible = false
		stack.add_child(page)
		page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		pages.append(page)

	col.add_child(Style.hint_bar([["Enter", "Select"], ["Esc", "Close"], ["Mouse drag", "Orbit car"], ["F1", "Tab", "Garage"]]))
	_build_caption()
	gui_input.connect(_on_root_gui_input)
	Game.car_spawned.connect(_on_car_spawned)


func _build_caption() -> void:
	_caption_box = Style.vbox(4)
	_caption_box.anchor_left = 1.0
	_caption_box.anchor_right = 1.0
	_caption_box.anchor_top = 1.0
	_caption_box.anchor_bottom = 1.0
	_caption_box.offset_left = -700
	_caption_box.offset_right = -64
	_caption_box.offset_top = -190
	_caption_box.offset_bottom = -44
	_caption_box.alignment = BoxContainer.ALIGNMENT_END
	_caption_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_caption_box)
	_caption_name = Style.label("", 58, Style.TEXT, 700, 2)
	_caption_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_caption_name.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	_caption_name.add_theme_constant_override("shadow_offset_y", 3)
	_caption_sub = Style.label("", 22, Style.TEXT_DIM, 500, 1)
	_caption_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_caption_sub.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	_caption_sub.add_theme_constant_override("shadow_offset_y", 2)
	_caption_box.add_child(_caption_name)
	_caption_box.add_child(_caption_sub)


# ------------------------------------------------------------------ open / close / tabs

func _on_opened() -> void:
	var rig := Game.camera_rig as CameraRig
	var car := Game.player_car
	if rig:
		rig.active = false
		if car and is_instance_valid(car):
			var to := rig.global_position - car.global_position
			_orbit = atan2(to.x, to.z)
	_lift = 0.0
	if rig:
		rig.camera.fov = SHOWROOM_FOV
	_stats_cache.clear()
	_refresh_all()
	select_tab(tab)
	_ensure_lights()


func _ensure_lights() -> void:
	if _key_light != null:
		return
	_key_light = _make_light("ShowroomKey", Color(1.0, 0.96, 0.9))
	_fill_light = _make_light("ShowroomFill", Color(0.86, 0.92, 1.0))


## Plain omni lights without shadows: Node3D children of this Control are positioned in world space.
func _make_light(node_name: String, col: Color) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.name = node_name
	l.light_color = col
	l.omni_range = LIGHT_RANGE
	l.omni_attenuation = 0.6
	l.light_specular = 0.7
	l.shadow_enabled = false
	l.visible = false
	add_child(l)
	return l


func _on_closed() -> void:
	for l: OmniLight3D in [_key_light, _fill_light]:
		if l != null:
			l.visible = false
	var rig := Game.camera_rig as CameraRig
	if rig:
		rig.camera.h_offset = 0.0
		rig.active = true
		rig.snap()


func select_tab(i: int) -> void:
	tab = wrapi(i, 0, TABS.size())
	for k in pages.size():
		pages[k].visible = k == tab
		_tab_buttons[k].set_pressed_no_signal(k == tab)
	if is_open:
		pages[tab].call_deferred("focus_first")


func _menu_input(event: InputEvent) -> void:
	var dir := 0
	if event.is_action_pressed("ui_tab_next"):
		dir = 1
	elif event.is_action_pressed("ui_tab_prev"):
		dir = -1
	elif event is InputEventKey and (event as InputEventKey).pressed and not (get_viewport().gui_get_focus_owner() is LineEdit):
		match (event as InputEventKey).physical_keycode:
			KEY_E:
				dir = 1
			KEY_Q:
				dir = -1
	if dir != 0:
		select_tab(tab + dir)
		get_viewport().set_input_as_handled()


func _on_car_spawned(_car: CarController) -> void:
	if is_open:
		_refresh_all()


func _refresh_all() -> void:
	for p in pages:
		p.call("refresh")
	_refresh_caption()


func _refresh_caption() -> void:
	var d := Game.current_car_data()
	if d == null:
		return
	var r := ratings(Game.current_car_index)
	_caption_name.text = d.display_name.to_upper()
	_caption_sub.text = "%s  ·  %s  ·  %s  ·  %d hp" % [d.category, d.year_style, d.drivetrain_name(), roundi(r["hp"])]
	if _caption_badge:
		_caption_badge.queue_free()
	var row := Style.hbox(10)
	row.alignment = BoxContainer.ALIGNMENT_END
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(Style.caps("Now driving", 18, Style.ACCENT))
	row.add_child(Style.class_badge(Tuning.class_for(r["pi"]), r["pi"], 22))
	_caption_box.add_child(row)
	_caption_box.move_child(row, 0)
	_caption_badge = row


## Cached figures of a car with its current upgrades and tuning.
func ratings(i: int) -> Dictionary:
	var base := Game.get_car_catalog()[i]
	var key := "%s|%s|%s" % [base.id, str(Game.get_upgrades(base.id)), str(Game.get_tuning(base.id))]
	if not _stats_cache.has(key):
		_stats_cache[key] = Stats.ratings(Game.effective_car_data(i))
	return _stats_cache[key]


# ------------------------------------------------------------------ showroom camera

func _on_root_gui_input(event: InputEvent) -> void:
	var mm := event as InputEventMouseMotion
	if mm != null and (mm.button_mask & (MOUSE_BUTTON_MASK_LEFT | MOUSE_BUTTON_MASK_RIGHT)) != 0:
		_orbit -= mm.relative.x * 0.006
		_orbit_pitch = clampf(_orbit_pitch + mm.relative.y * 0.003, 0.02, 0.7)
		_orbit_idle = 0.0


func _process(delta: float) -> void:
	if not is_open:
		return
	var rig := Game.camera_rig as CameraRig
	var car := Game.player_car
	if rig == null or car == null or not is_instance_valid(car):
		return
	rig.active = false
	_orbit_idle += delta
	if _orbit_idle > 2.0:
		_orbit += delta * 0.11
	var t := car.get_global_transform_interpolated()
	var bs := car.data.body_size if car.data else Vector3(1.9, 1.4, 4.4)
	var box := _car_box(car)
	var center := t * box.get_center()
	var cam := rig.camera
	var vp := get_viewport().get_visible_rect().size
	var aspect := vp.x / maxf(vp.y, 1.0)
	var tan_v := tan(deg_to_rad(SHOWROOM_FOV * 0.5))
	var tan_h := tan_v * aspect
	# Free area right of the menu column in NDC x: centre m, half width hw.
	var left := _col.get_global_rect().end.x
	if tab < pages.size():
		left = maxf(left, pages[tab].get_global_rect().end.x)
	var a := 2.0 * (left + FIT_GAP_LEFT) / vp.x - 1.0
	var b := 2.0 * (vp.x - FIT_GAP_RIGHT) / vp.x - 1.0
	if b - a < 0.2:
		a = b - 0.2
	var m := (a + b) * 0.5
	var hw := (b - a) * 0.5
	var space := car.get_world_3d().direct_space_state
	_ray.exclude = [car.get_rid()]
	var dist := _fit_distance(t.basis, box, _orbit_pitch + _lift, m, hw, tan_h, tan_v)
	# Rise over a fence / wall in the way; when no lift clears the view (a house), stay low and come closer.
	var want_lift := 0.0
	for k in LIFT_STEPS + 1:
		var l := LIFT_MAX * float(k) / LIFT_STEPS
		if _view_clear(space, center, _orbit_dir(_orbit, _orbit_pitch + l) * dist):
			want_lift = l
			break
	_lift = move_toward(_lift, want_lift, delta * 0.8)
	var dir := _orbit_dir(_orbit, _orbit_pitch + _lift)
	var pos := center + dir * dist
	_ray.from = center
	_ray.to = pos
	var hit := space.intersect_ray(_ray)
	if not hit.is_empty():
		pos = (hit["position"] as Vector3) - dir * 0.3
	var d := maxf(pos.distance_to(center), 0.5)
	# Pulled in front of an obstacle: a wider lens keeps the whole car inside the free area.
	var fov := SHOWROOM_FOV
	if d < dist - 0.05:
		fov = minf(rad_to_deg(2.0 * atan(_fit_tan(t.basis, box, dir, d, m, hw, aspect) / aspect)), 100.0)
	cam.fov = lerpf(cam.fov, fov, clampf(delta * 8.0, 0.0, 1.0))
	# Lens shift (camera moved along its right axis) that puts the car centre at the free area's centre.
	cam.h_offset = -m * d * tan(deg_to_rad(cam.fov * 0.5)) * aspect
	var xf := Transform3D(Basis(), pos).looking_at(center, Vector3.UP)
	rig.global_transform = rig.global_transform.interpolate_with(xf, clampf(delta * 6.0, 0.0, 1.0))
	_place_lights(center, bs)


static func _orbit_dir(yaw: float, pitch: float) -> Vector3:
	var p := clampf(pitch, 0.02, 1.2)
	return Vector3(sin(yaw) * cos(p), sin(p), cos(yaw) * cos(p))


func _view_clear(space: PhysicsDirectSpaceState3D, center: Vector3, offset: Vector3) -> bool:
	_ray.from = center
	_ray.to = center + offset
	return space.intersect_ray(_ray).is_empty()


## Camera distance at which every corner of the car's bounds stays inside the free area for all orbit yaws
## at this pitch, with the camera shifted so the car centre sits at NDC x `m`. A corner at lateral offset x
## and depth z behind the centre projects to m + (x - m*z*tan_h) / ((d + z) * tan_h), hence the bound on d.
func _fit_distance(basis: Basis, box: AABB, pitch: float, m: float, hw: float, tan_h: float, tan_v: float) -> float:
	var c := box.get_center()
	var need := 0.0
	for i in FIT_YAWS:
		var dir := _orbit_dir(TAU * float(i) / FIT_YAWS, pitch)
		var f := -dir
		var r := f.cross(Vector3.UP).normalized()
		var u := r.cross(f)
		for k in 8:
			var rel := basis * (box.get_endpoint(k) - c)
			var x := rel.dot(r)
			var z := rel.dot(f)
			need = maxf(need, absf(x - m * z * tan_h) / (hw * tan_h) - z)
			need = maxf(need, absf(rel.dot(u)) / (FIT_V * tan_v) - z)
	return clampf(need, box.size.z * 0.6 + 2.0, 60.0)


## Horizontal lens tangent that fits the car's bounds into the free area from distance d along `dir`
## (fixed-point iteration of the bound in _fit_distance, solved for tan_h; never narrower than the showroom lens).
func _fit_tan(basis: Basis, box: AABB, dir: Vector3, d: float, m: float, hw: float, aspect: float) -> float:
	var c := box.get_center()
	var f := -dir
	var r := f.cross(Vector3.UP).normalized()
	var u := r.cross(f)
	var t := tan(deg_to_rad(SHOWROOM_FOV * 0.5)) * aspect
	for it in 3:
		var need := t
		for k in 8:
			var rel := basis * (box.get_endpoint(k) - c)
			var z := rel.dot(f)
			var depth := maxf(d + z, 0.3)
			need = maxf(need, absf(rel.dot(r) - m * z * t) / (hw * depth))
			need = maxf(need, absf(rel.dot(u)) * aspect / (FIT_V * depth))
		t = need
	return t


## The car's visual bounds (body, wheels, spoilers) in car space, cached per car.
func _car_box(car: CarController) -> AABB:
	if car == _box_car and _box.has_volume():
		return _box
	_box_car = car
	var inv := car.global_transform.affine_inverse()
	var vis := car.get_node_or_null(^"Visual")
	var found := false
	if vis != null:
		for n in vis.find_children("*", "MeshInstance3D", true, false):
			var mi := n as MeshInstance3D
			if mi.mesh == null or not mi.is_visible_in_tree():
				continue
			var b := inv * mi.global_transform * mi.get_aabb()
			_box = _box.merge(b) if found else b
			found = true
	if not found:
		var bs := car.data.body_size if car.data else Vector3(1.9, 1.4, 4.4)
		_box = AABB(Vector3(-bs.x * 0.5, 0.0, -bs.z * 0.5), bs)
	return _box


## Key light up and to the side of the orbit camera, fill light low on the far side; both fade with daylight.
func _place_lights(center: Vector3, bs: Vector3) -> void:
	if _key_light == null:
		return
	var dark := 0.0
	if Game.env != null and Game.env.has_method("get_light_level"):
		dark = 1.0 - clampf(float(Game.env.call("get_light_level")), 0.0, 1.0)
	var k := smoothstep(0.3, 0.85, dark)
	var r := bs.z * 0.5 + 2.6
	for i in 2:
		var l := _key_light if i == 0 else _fill_light
		l.visible = k > 0.01
		if not l.visible:
			continue
		var a := _orbit + (0.55 if i == 0 else PI + 0.9)
		l.light_energy = (KEY_ENERGY if i == 0 else FILL_ENERGY) * k
		l.global_position = center + Vector3(sin(a) * r, bs.y * (1.6 if i == 0 else 0.7), cos(a) * r)
