extends Control
## Driving HUD layer: instrument cluster (bottom-right), region popup, activity panel / result banner,
## FPS readout (Settings "show_fps") and the controls hint. Map, notifications and telemetry are
## siblings built by ui_root.gd.

const SpeedoScript := preload("res://scripts/ui/hud_speedo.gd")
const RegionScript := preload("res://scripts/ui/hud_region.gd")
const ActivityScript := preload("res://scripts/ui/hud_activity.gd")
const DebugScript := preload("res://scripts/ui/hud_debug.gd")
const HintScript := preload("res://scripts/ui/hud_hint.gd")
const Style := preload("res://scripts/ui/ui_style.gd")

## Font styles drawn once while loading so their glyph caches exist before popups first appear:
## [size, weight, condensed, spacing].
const WARM_STYLES := [[74, 700, true, 0], [48, 700, true, 0], [46, 700, true, 0], [100, 700, true, 0], [64, 700, false, 6],
	[36, 700, false, 0], [30, 700, false, 6], [26, 600, false, 0], [24, 700, false, 0], [23, 500, false, 0], [22, 700, false, 0],
	[20, 500, false, 0], [18, 700, false, 2], [18, 700, false, 4], [17, 700, false, 5], [17, 500, false, 0], [16, 500, false, 0],
	[15, 600, false, 0], [13, 700, false, 3]]
const WARM_TEXT := "ABCDEFGHIJKLMNOPQRSTUVWXYZ abcdefghijklmnopqrstuvwxyz 0123456789 .,:/%·-+°!"

var speedo: Control
var region_popup: Control
var activity: Control
var debug_readout: Control
var hint: Control


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	region_popup = _add(RegionScript, "RegionPopup")
	activity = _add(ActivityScript, "Activity")
	# Both use the band below the activity panel: the region popup gives way to the result banner.
	region_popup.set(&"banner_source", activity)
	activity.connect(&"banner_started", Callable(region_popup, &"yield_to_banner"))
	speedo = _add(SpeedoScript, "Speedometer")
	hint = _add(HintScript, "ControlsHint")
	debug_readout = _add(DebugScript, "DebugReadout")
	debug_readout.visible = bool(Settings.get_value("show_fps", true))
	Settings.changed.connect(_on_setting)
	_prewarm_fonts()


func _add(script: Script, node_name: String) -> Control:
	var c: Control = script.new()
	c.name = node_name
	add_child(c)
	return c


func _on_setting(key: String, value: Variant) -> void:
	if key == "show_fps":
		debug_readout.visible = bool(value)


func _prewarm_fonts() -> void:
	var warm := Control.new()
	warm.name = "FontWarmup"
	warm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	warm.modulate.a = 0.0
	warm.draw.connect(func() -> void:
		var y := 0.0
		for st: Array in WARM_STYLES:
			y += float(st[0])
			warm.draw_string(Style.font(int(st[1]), bool(st[2]), int(st[3])), Vector2(0, y), WARM_TEXT, HORIZONTAL_ALIGNMENT_LEFT, -1.0, int(st[0])))
	add_child(warm)
	await get_tree().process_frame
	await get_tree().process_frame
	warm.queue_free()
