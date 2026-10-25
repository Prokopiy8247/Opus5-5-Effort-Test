extends CanvasLayer
## UI root: HUD, minimap, notifications, console, garage, debug menu, map and photo mode.

var root: Control
var hud: Control
var minimap: Control
var notes: Control
var console: PanelContainer
var garage: Control
var debug: PanelContainer
var map_screen: Control
var photo: Control


func _ready() -> void:
	root = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UITheme.theme()
	add_child(root)
	hud = _add("res://scripts/ui/hud.gd", "HUD")
	minimap = _add("res://scripts/ui/minimap.gd", "Minimap")
	UITheme.place(minimap, 0.0, 1.0, 30, -290, 260, 260)
	notes = _add("res://scripts/ui/notifications.gd", "Notifications")
	garage = _add("res://scripts/ui/garage_menu.gd", "Garage")
	debug = _add("res://scripts/ui/debug_menu.gd", "Debug")
	map_screen = _add("res://scripts/ui/map_screen.gd", "Map")
	photo = _add("res://scripts/ui/photo_mode.gd", "Photo")
	console = _add("res://scripts/ui/console.gd", "Console")
	Game.hud = self
	if Game.world != null and Game.world.get("map_texture") != null:
		minimap.call("set_map", Game.world.map_texture)
	elif minimap != null:
		minimap.visible = false


func _add(path: String, n: String) -> Control:
	if not ResourceLoader.exists(path):
		return null
	var c: Control = (load(path) as GDScript).new()
	c.name = n
	root.add_child(c)
	return c


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_console"):
		_close_except("console")
		console.toggle()
		get_viewport().set_input_as_handled()
	elif console.visible:
		return
	elif event.is_action_pressed("garage_menu"):
		_close_except("garage")
		garage.toggle()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("debug_menu"):
		_close_except("debug")
		debug.toggle()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("map") and map_screen != null:
		_close_except("map")
		map_screen.call("toggle")
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("photo_mode") and photo != null:
		_close_except("photo")
		photo.call("toggle")
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel"):
		_close_except("")


func _close_except(keep: String) -> void:
	for pair: Array in [["garage", garage], ["debug", debug], ["map", map_screen], ["photo", photo], ["console", console]]:
		var c: Control = pair[1]
		if c != null and pair[0] != keep and c.visible:
			c.call("toggle")


func _process(_d: float) -> void:
	var modal := (garage != null and garage.visible) or (map_screen != null and map_screen.visible) or (photo != null and photo.visible)
	if photo == null or not photo.visible:
		hud.visible = not modal
		minimap.visible = not modal and minimap.get("map_rect") != null and (minimap.get("map_rect") as TextureRect).texture != null


func set_hud_visible(v: bool) -> void:
	hud.visible = v
	minimap.visible = v
	notes.visible = v
