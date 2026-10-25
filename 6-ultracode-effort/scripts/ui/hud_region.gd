extends Control
## Region popup: "NOW ENTERING" + big region name + description, sliding in with a gradient
## underline, holding, then fading. Queued until the loading screen is gone, and while an activity
## result banner (same screen band) is up: a popup the banner interrupts early is shown again after it.

const Style := preload("res://scripts/ui/ui_style.gd")

const IN_TIME := 0.55
const HOLD := 3.6
const OUT_TIME := 0.7
## A popup interrupted by a result banner before it was shown this long is replayed afterwards.
const REPLAY_BEFORE := IN_TIME + 1.5

## Optional node with banner_visible() -> bool (the activity HUD), set by hud.gd.
var banner_source: Node
var _name: String = ""
var _desc: String = ""
var _color := Style.ACCENT
var _t: float = -1.0
var _queued: String = ""


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	anchor_left = 0.5
	anchor_right = 0.5
	offset_left = -560.0
	offset_right = 560.0
	offset_top = 168.0
	offset_bottom = 350.0
	Game.region_changed.connect(show_region)


func show_region(region_name: String) -> void:
	if _blocked():
		_queued = region_name
		return
	_name = region_name
	_desc = ""
	for r: Dictionary in WorldLayout.REGIONS:
		if String(r["name"]) == region_name:
			_desc = String(r.get("desc", ""))
			_color = (r.get("color", Style.ACCENT) as Color).lightened(0.35)
	_t = 0.0


func is_showing() -> bool:
	return _t >= 0.0


func _blocked() -> bool:
	var main: Node = Game.main
	return (main != null and bool(main.get("is_loading"))) or _banner_up()


func _banner_up() -> bool:
	return banner_source != null and is_instance_valid(banner_source) and bool(banner_source.call(&"banner_visible"))


## A result banner takes the band: drop the popup now, and replay it afterwards if it was barely readable.
func yield_to_banner() -> void:
	if _t < 0.0:
		return
	if _t < REPLAY_BEFORE and _queued == "":
		_queued = _name
	_t = -1.0
	queue_redraw()


func _process(delta: float) -> void:
	if _t >= 0.0 and _banner_up():
		yield_to_banner()
	if _queued != "" and not _blocked():
		var q := _queued
		_queued = ""
		show_region(q)
	if _t < 0.0:
		return
	_t += delta
	if _t > IN_TIME + HOLD + OUT_TIME:
		_t = -1.0
	queue_redraw()


func _draw() -> void:
	if _t < 0.0 or _name == "":
		return
	var k_in := clampf(_t / IN_TIME, 0.0, 1.0)
	var e_in := 1.0 - pow(1.0 - k_in, 3.0)
	var k_out := clampf((_t - IN_TIME - HOLD) / OUT_TIME, 0.0, 1.0)
	var alpha := e_in * (1.0 - k_out)
	var slide := (1.0 - e_in) * -50.0 + k_out * 30.0
	var w := size.x
	var title := _name.to_upper()
	var tw := Style.text_width(title, 64, 700, false, 6)
	var cx := w * 0.5 + slide
	# Soft backing band.
	var band := Rect2(Vector2(cx - maxf(tw + 140.0, 760.0) * 0.5, 18.0), Vector2(maxf(tw + 140.0, 760.0), 148.0))
	Style.draw_round_rect(self, band, Color(0.02, 0.025, 0.05, 0.42 * alpha), 22)
	Style.draw_text(self, "NOW ENTERING", Vector2(cx - 200.0, 46.0), 17, Color(_color.r, _color.g, _color.b, alpha),
		HORIZONTAL_ALIGNMENT_CENTER, 400.0, 700, false, 5, 0.0)
	Style.draw_text(self, title, Vector2(cx - tw * 0.5 - 20.0, 106.0), 64, Color(1, 1, 1, alpha), HORIZONTAL_ALIGNMENT_CENTER,
		tw + 40.0, 700, false, 6, 0.55)
	# Gradient underline growing from the centre.
	var lw := (tw + 60.0) * e_in
	var y := 118.0
	var pts := PackedVector2Array([Vector2(cx - lw * 0.5, y), Vector2(cx, y), Vector2(cx + lw * 0.5, y)])
	var cols := PackedColorArray([Color(Style.ACCENT.r, Style.ACCENT.g, Style.ACCENT.b, 0.0), Color(Style.ACCENT_2.r, Style.ACCENT_2.g, Style.ACCENT_2.b, alpha),
		Color(Style.ACCENT.r, Style.ACCENT.g, Style.ACCENT.b, 0.0)])
	draw_polyline_colors(pts, cols, 4.0, true)
	if _desc != "":
		Style.draw_text(self, _desc, Vector2(cx - 500.0, 150.0), 23, Color(Style.TEXT_DIM.r, Style.TEXT_DIM.g, Style.TEXT_DIM.b, alpha),
			HORIZONTAL_ALIGNMENT_CENTER, 1000.0, 500, false, 0, 0.6)
