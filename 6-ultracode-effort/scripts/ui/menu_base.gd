extends Control
## Base for the Sunward menus (console, garage, debug, pause, photo mode): one-open-at-a-time via the
## "sunward_menus" group, overlay/pause bookkeeping, fade-in, toggle and back keys. A menu's hotkey only
## works while no other menu (or the world map) is open; inside a menu only its own key / Esc close it.
## Subclasses override _build(), _on_opened(), _on_closed(), _on_back(), _menu_input().

const Style := preload("res://scripts/ui/menu_style.gd")
const GROUP := &"sunward_menus"

var menu_id: StringName = &""
var toggle_action: StringName = &""
## Pause the SceneTree while open (pause menu, photo mode).
var pauses_game: bool = false
## While open, other menus ignore keyboard input (console typing, photo mode flying).
var captures_keys: bool = false
## Hide the driving HUD (ui_root.hud_root) while open - full-screen menus.
var hides_hud: bool = false
var is_open: bool = false
var _paused_by_me: bool = false
var _overlay_pushed: bool = false
var _fade: Tween


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP


func _ready() -> void:
	add_to_group(GROUP)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = Style.theme()
	_build()


func _exit_tree() -> void:
	if is_open:
		close_menu()


# ------------------------------------------------------------------ overridables

func _build() -> void:
	pass


func _on_opened() -> void:
	pass


func _on_closed() -> void:
	pass


## Back / cancel pressed. Return true when handled internally (e.g. leaving a sub-page).
func _on_back() -> bool:
	return false


func _menu_input(_event: InputEvent) -> void:
	pass


func can_open() -> bool:
	return true


# ------------------------------------------------------------------ open / close

## Hotkeys never open a menu while another one is open (see _input); a scripted open (console 'photo',
## benchmark end) replaces the open menu and takes over its pause, so the world never resumes on its own.
func open_menu() -> void:
	if is_open or not is_inside_tree():
		return
	var inherit_pause := false
	for n: Node in get_tree().get_nodes_in_group(GROUP):
		if n != self and bool(n.get("is_open")):
			if bool(n.get("_paused_by_me")):
				n.set("_paused_by_me", false)
				inherit_pause = true
			n.call("close_menu")
	is_open = true
	visible = true
	if not _overlay_pushed:
		_overlay_pushed = true
		Game.push_overlay(true)
	# After push_overlay: ui_root re-applies HUD visibility on ui_overlay_changed.
	if hides_hud:
		_set_hud_hidden(true)
	if inherit_pause:
		_paused_by_me = true
	elif pauses_game and not get_tree().paused:
		get_tree().paused = true
		_paused_by_me = true
	modulate.a = 0.0
	if _fade:
		_fade.kill()
	_fade = create_tween()
	_fade.tween_property(self, "modulate:a", 1.0, 0.14)
	_on_opened()


func close_menu() -> void:
	if not is_open:
		return
	is_open = false
	var f := get_viewport().gui_get_focus_owner() if get_viewport() else null
	if f != null and is_ancestor_of(f):
		f.release_focus()
	_on_closed()
	visible = false
	if _overlay_pushed:
		_overlay_pushed = false
		Game.push_overlay(false)
	if hides_hud:
		_set_hud_hidden(false)
	if _paused_by_me:
		_paused_by_me = false
		get_tree().paused = false


func toggle_menu() -> void:
	if is_open:
		close_menu()
	elif can_open():
		open_menu()


func _set_hud_hidden(hidden: bool) -> void:
	var hud := Game.hud
	if hud == null or not is_instance_valid(hud):
		return
	# ui_root owns HUD visibility and checks open hides_hud menus itself, so later Settings / F3 / F4
	# re-applies keep the HUD hidden under this menu.
	if hud.has_method("refresh_visibility"):
		hud.call("refresh_visibility")
		return
	var root := hud.get("hud_root") as CanvasItem
	if root != null:
		root.visible = not hidden and bool(Settings.get_value("hud_visible", true)) and not Game.photo_mode


# ------------------------------------------------------------------ shared queries

static func find_menu(tree: SceneTree, id: StringName) -> Node:
	for n: Node in tree.get_nodes_in_group(GROUP):
		if n.get("menu_id") == id:
			return n
	return null


static func open_menu_node(tree: SceneTree) -> Node:
	for n: Node in tree.get_nodes_in_group(GROUP):
		if bool(n.get("is_open")):
			return n
	return null


func _game_ready() -> bool:
	if Game.main == null or not is_instance_valid(Game.main):
		return false
	return not bool(Game.main.get("is_loading"))


## True when another open menu owns the keyboard (console typing, photo mode) or the benchmark runs.
func _blocked_by_other() -> bool:
	if Game.benchmark_mode and menu_id != &"debug":
		return true
	for n: Node in get_tree().get_nodes_in_group(GROUP):
		if n != self and bool(n.get("is_open")) and bool(n.get("captures_keys")):
			return true
	return false


func _typing_elsewhere(event: InputEvent) -> bool:
	var f := get_viewport().gui_get_focus_owner()
	if not (f is LineEdit) or is_ancestor_of(f):
		return false
	var k := event as InputEventKey
	return k != null and k.unicode != 0


func _input(event: InputEvent) -> void:
	if event.is_echo() or not _game_ready() or _blocked_by_other() or _typing_elsewhere(event):
		return
	if not (event is InputEventKey or event is InputEventMouseButton or event is InputEventMouseMotion):
		return
	if toggle_action != &"" and event.is_action_pressed(toggle_action):
		if is_open:
			close_menu()
		elif open_menu_node(get_tree()) == null and can_open():
			open_menu()
		else:
			# Another menu (or the map) is open: its hotkeys stay inert there, so Tab remains focus navigation
			# and a pausing menu is never swapped for a live one.
			return
		get_viewport().set_input_as_handled()
		return
	if not is_open:
		return
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause"):
		if not _on_back():
			close_menu()
		get_viewport().set_input_as_handled()
		return
	_menu_input(event)


## Small transient message near the top of this menu.
func toast(text: String, color := Style.GOOD, parent: Control = null) -> void:
	var host: Control = parent if parent != null else self
	var p := Style.panel(Style.PANEL_HI, 10, 10, 2, color)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(Style.label(text, Style.FONT_SIZE, Style.TEXT, 600))
	host.add_child(p)
	p.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	p.position.y = 28.0
	p.reset_size()
	p.position.x = (host.size.x - p.get_combined_minimum_size().x) * 0.5
	var tw := p.create_tween()
	tw.tween_interval(2.2)
	tw.tween_property(p, "modulate:a", 0.0, 0.4)
	tw.tween_callback(p.queue_free)
