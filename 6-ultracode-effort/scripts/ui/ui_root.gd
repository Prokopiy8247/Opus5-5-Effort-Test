extends CanvasLayer
## UI root (added by main.gd as "UI", registered as Game.hud). Builds the HUD (cluster, minimap,
## notifications, telemetry, region / activity popups), the world map, GPS routing and the 3D guide
## ribbon, then the menu components (console, garage, debug, pause, photo mode) when their scripts
## exist, so menus draw on top. Owns HUD visibility (toggle_hud / F3, Settings "hud_visible", always
## hidden in photo mode), the telemetry toggle (toggle_telemetry / F4), the screenshot key (screenshot / F12,
## outside photo mode) and the fast-travel fade.

const Style := preload("res://scripts/ui/ui_style.gd")
const Shot := preload("res://scripts/ui/screenshot.gd")
const HudScript := preload("res://scripts/ui/hud.gd")
const MinimapScript := preload("res://scripts/ui/minimap.gd")
const NotificationsScript := preload("res://scripts/ui/notifications.gd")
const TelemetryScript := preload("res://scripts/ui/telemetry.gd")
const WorldMapScript := preload("res://scripts/ui/world_map.gd")
const GpsScript := preload("res://scripts/ui/gps_route.gd")
const RouteLineScript := preload("res://scripts/ui/route_line_3d.gd")
const MENU_SCRIPTS: PackedStringArray = [
	"res://scripts/ui/console.gd", "res://scripts/ui/garage_menu.gd", "res://scripts/ui/debug_menu.gd",
	"res://scripts/ui/pause_menu.gd", "res://scripts/ui/photo_mode.gd",
]

var hud_root: Control
var hud: HudScript
var minimap: MinimapScript
var notifications: NotificationsScript
var telemetry: TelemetryScript
var world_map: WorldMapScript
var gps: GpsScript
var route_line: RouteLineScript
var menus: Array[Node] = []
var hud_visible: bool = true
## Path of the last screenshot saved with the screenshot key (for tests / integration).
var last_screenshot: String = ""

var _fade: Control
var _fade_label: Label
var _travel_busy: bool = false
var _shot_busy: bool = false
var _banner: PanelContainer


func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	hud_visible = bool(Settings.get_value("hud_visible", true))
	gps = GpsScript.new()
	gps.name = "GpsRoute"
	add_child(gps)
	route_line = RouteLineScript.new()
	route_line.name = "RouteLine3D"
	route_line.gps = gps
	add_child(route_line)
	hud_root = Control.new()
	hud_root.name = "HudRoot"
	hud_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_root.theme = Style.theme()
	add_child(hud_root)
	hud_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud = HudScript.new()
	hud.name = "Hud"
	hud_root.add_child(hud)
	minimap = MinimapScript.new()
	minimap.name = "Minimap"
	minimap.gps = gps
	hud_root.add_child(minimap)
	telemetry = TelemetryScript.new()
	telemetry.name = "Telemetry"
	hud_root.add_child(telemetry)
	notifications = NotificationsScript.new()
	notifications.name = "Notifications"
	hud_root.add_child(notifications)
	world_map = WorldMapScript.new()
	world_map.name = "WorldMap"
	world_map.gps = gps
	world_map.travel_handler = fast_travel
	world_map.theme = Style.theme()
	add_child(world_map)
	_build_fade()
	for path in MENU_SCRIPTS:
		_add_menu(path)
	Settings.changed.connect(_on_setting)
	Game.photo_mode_changed.connect(_on_photo_mode)
	Game.ui_overlay_changed.connect(func(_open: bool) -> void: _apply_visibility())
	_apply_visibility()
	world_map.prewarm.call_deferred()


func _add_menu(path: String) -> void:
	if not ResourceLoader.exists(path):
		return
	var scr := load(path) as Script
	if scr == null or not scr.can_instantiate():
		push_warning("UI: menu script %s could not be instantiated" % path)
		return
	var obj: Variant = scr.new()
	if not (obj is Node):
		return
	var n := obj as Node
	n.name = path.get_file().get_basename().to_pascal_case()
	add_child(n)
	menus.append(n)


func _build_fade() -> void:
	_fade = Control.new()
	_fade.name = "TravelFade"
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.modulate.a = 0.0
	_fade.visible = false
	add_child(_fade)
	_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.035, 0.06)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var cap := Style.label("FAST TRAVEL", 18, Style.ACCENT, 700, 5)
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_fade.add_child(cap)
	cap.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	cap.offset_left = -400.0
	cap.offset_right = 400.0
	cap.offset_top = -60.0
	cap.offset_bottom = -30.0
	_fade_label = Style.label("", 44, Style.TEXT, 700)
	_fade_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_fade.add_child(_fade_label)
	_fade_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_fade_label.offset_left = -600.0
	_fade_label.offset_right = 600.0
	_fade_label.offset_top = -26.0
	_fade_label.offset_bottom = 34.0


# ------------------------------------------------------------------ public API

func set_hud_visible(v: bool) -> void:
	hud_visible = v
	if bool(Settings.get_value("hud_visible", true)) != v:
		Settings.set_value("hud_visible", v)
	_apply_visibility()


func set_telemetry_visible(v: bool) -> void:
	Settings.set_value("show_telemetry", v)


func toggle_map() -> void:
	world_map.toggle_menu()


func open_map() -> void:
	if not world_map.is_open and world_map.can_open():
		world_map.open_menu()


func close_map() -> void:
	world_map.close_menu()


func show_controls_hint() -> void:
	hud.hint.call("show_hint")


## Fade out, teleport to a named target, hold the car until the terrain around it has streamed in, fade in.
func fast_travel(target: String) -> void:
	if _travel_busy:
		return
	_travel_busy = true
	_fade_label.text = target
	_fade.visible = true
	var tw := create_tween()
	tw.tween_property(_fade, "modulate:a", 1.0, 0.35)
	await tw.finished
	var ok := Game.teleport(target)
	var car := Game.player_car
	if ok and car != null and Game.world is World:
		car.freeze = true
		var t := 0.0
		await get_tree().process_frame
		while t < 8.0 and not (Game.world as World).is_ready_near():
			await get_tree().process_frame
			t += get_process_delta_time()
		await get_tree().create_timer(0.25, true, false, true).timeout
		if is_instance_valid(car):
			car.freeze = false
	var tw2 := create_tween()
	tw2.tween_property(_fade, "modulate:a", 0.0, 0.5)
	await tw2.finished
	_fade.visible = false
	_travel_busy = false


# ------------------------------------------------------------------ visibility / toggles

## Re-evaluates HUD visibility; menus call this when they open / close (see menu_base.hides_hud).
func refresh_visibility() -> void:
	_apply_visibility()


func _apply_visibility() -> void:
	var show := hud_visible and not Game.photo_mode and not world_map.is_open
	hud_root.visible = show and not _menu_hides_hud()
	minimap.visible = bool(Settings.get_value("show_minimap", true))
	telemetry.visible = bool(Settings.get_value("show_telemetry", false))
	route_line.enabled = show


## True while an open full-screen menu (hides_hud) wants the driving HUD hidden.
func _menu_hides_hud() -> bool:
	if not is_inside_tree():
		return false
	for n: Node in get_tree().get_nodes_in_group(WorldMapScript.GROUP):
		if "hides_hud" in n and bool(n.get("hides_hud")) and bool(n.get("is_open")):
			return true
	return false


func _on_setting(key: String, value: Variant) -> void:
	match key:
		"hud_visible":
			hud_visible = bool(value)
			_apply_visibility()
		"show_minimap", "show_telemetry":
			_apply_visibility()


func _on_photo_mode(on: bool) -> void:
	if on and world_map.is_open:
		world_map.close_menu()
	_apply_visibility()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_echo():
		return
	if event.is_action_pressed("toggle_hud"):
		set_hud_visible(not hud_visible)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("toggle_telemetry"):
		set_telemetry_visible(not telemetry.visible)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("screenshot") and not Game.photo_mode:
		take_screenshot()
		get_viewport().set_input_as_handled()


## Saves the next rendered frame (HUD and open menus included) to user://screenshots in the background (no
## frame stall); photo mode has its own capture that hides the UI.
func take_screenshot() -> void:
	if _shot_busy:
		return
	_shot_busy = true
	await RenderingServer.frame_post_draw
	_shot_busy = false
	Shot.save_viewport_async(get_viewport(), _on_screenshot_saved)


func _on_screenshot_saved(path: String) -> void:
	if path == "":
		_confirm("Screenshot failed", "Could not write to %s" % Shot.DIR, &"error")
		return
	last_screenshot = path
	print("[screenshot] saved %s" % ProjectSettings.globalize_path(path))
	_confirm("Screenshot saved", "screenshots/%s" % path.get_file(), &"info")


## Confirmation that is seen right away: the toast stack lives in the HUD, so while the HUD is hidden (F3,
## world map, a full-screen menu) the open menu shows it, or else a short banner on this layer.
func _confirm(title: String, body: String, kind: StringName) -> void:
	if hud_root.visible:
		Game.notify(title, body, kind)
		return
	for m in menus:
		if bool(m.get("is_open")) and m.has_method("toast"):
			if kind == &"error":
				m.call("toast", "%s  ·  %s" % [title, body], Style.BAD)
			else:
				m.call("toast", "%s  ·  %s" % [title, body])
			return
	_show_banner("%s  ·  %s" % [title, body], Style.BAD if kind == &"error" else Style.SKY)


func _show_banner(text: String, col: Color) -> void:
	if _banner != null and is_instance_valid(_banner):
		_banner.queue_free()
	_banner = PanelContainer.new()
	_banner.name = "ShotBanner"
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner.add_theme_stylebox_override("panel", Style.panel(Style.BG_STRONG, 10, 2, col, 12.0))
	_banner.add_child(Style.label(text, 20, Style.TEXT, 600))
	add_child(_banner)
	# Zero-width rect on the top-centre anchor that grows both ways: centred whatever the text length.
	_banner.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_banner.offset_left = 0.0
	_banner.offset_right = 0.0
	_banner.offset_top = 28.0
	_banner.offset_bottom = 28.0
	_banner.modulate.a = 0.0
	var tw := _banner.create_tween()
	tw.tween_property(_banner, "modulate:a", 1.0, 0.2)
	tw.tween_interval(2.4)
	tw.tween_property(_banner, "modulate:a", 0.0, 0.4)
	tw.tween_callback(_banner.queue_free)
