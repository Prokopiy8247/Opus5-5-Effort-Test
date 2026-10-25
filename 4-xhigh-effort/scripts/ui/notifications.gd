extends Control
## Toast stack (right side), large centre banners for activity results and region popups.

var stack: VBoxContainer
var banner: PanelContainer
var banner_title: Label
var banner_body: Label
var region: Label
var region_sub: Label
var _banner_t := 0.0
var _region_t := 0.0
var _last_region := -1


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack = VBoxContainer.new()
	UITheme.place(stack, 1.0, 0.0, -420, 120, 400, 500)
	stack.add_theme_constant_override("separation", 8)
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(stack)
	banner = PanelContainer.new()
	banner.add_theme_stylebox_override("panel", UITheme.panel_box(Color(0.05, 0.04, 0.1, 0.82), 18, UITheme.PINK))
	UITheme.place(banner, 0.5, 0.0, -360, 150, 720, 130)
	var vb := VBoxContainer.new()
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	banner_title = UITheme.label("", 40, UITheme.SUN, true)
	banner_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner_body = UITheme.label("", 24, UITheme.TEXT)
	banner_body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(banner_title)
	vb.add_child(banner_body)
	banner.add_child(vb)
	banner.modulate.a = 0.0
	banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(banner)
	region = UITheme.label("", 54, Color(1, 1, 1), true)
	region.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	region.add_theme_constant_override("outline_size", 10)
	region.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.45))
	UITheme.place(region, 0.5, 0.0, -600, 60, 1200, 70)
	region.modulate.a = 0.0
	add_child(region)
	region_sub = UITheme.label("", 22, UITheme.SUN)
	region_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UITheme.place(region_sub, 0.5, 0.0, -600, 126, 1200, 32)
	region_sub.modulate.a = 0.0
	add_child(region_sub)
	Game.notified.connect(_on_notify)


func _on_notify(title: String, body: String, kind: String) -> void:
	if kind == "big":
		banner_title.text = title
		banner_body.text = body
		_banner_t = 4.0
		return
	var pc := PanelContainer.new()
	var accent := UITheme.CYAN if kind == "small" else (UITheme.PINK if kind == "car" else UITheme.SUN)
	pc.add_theme_stylebox_override("panel", UITheme.panel_box(Color(0.04, 0.05, 0.1, 0.8), 10, accent))
	var vb := VBoxContainer.new()
	vb.add_child(UITheme.label(title, 22 if kind != "small" else 18, accent, true))
	if body != "":
		vb.add_child(UITheme.label(body, 17, UITheme.TEXT))
	pc.add_child(vb)
	pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_child(pc)
	pc.set_meta("t", 3.6 if kind != "small" else 2.2)
	while stack.get_child_count() > 5:
		stack.get_child(0).queue_free()
		stack.remove_child(stack.get_child(0))


func _process(delta: float) -> void:
	for ch in stack.get_children():
		var t: float = float(ch.get_meta("t", 0.0)) - delta
		ch.set_meta("t", t)
		(ch as Control).modulate.a = clampf(t / 0.5, 0.0, 1.0)
		if t <= 0.0:
			ch.queue_free()
	_banner_t -= delta
	banner.modulate.a = clampf(minf(_banner_t / 0.5, (4.0 - _banner_t) / 0.25), 0.0, 1.0)
	# region change popup
	if Game.player != null and is_instance_valid(Game.player) and Game.world != null and Game.world.has_method("region_at"):
		var r: int = Game.world.region_at(Game.player.global_position)
		if r != _last_region:
			if _last_region != -1 or Game.main.get("intro_done"):
				region.text = Game.world.region_name(r).to_upper()
				var regs: Array = Game.world.wd.regions
				region_sub.text = String(regs[r].desc) if r < regs.size() else ""
				_region_t = 4.5
			_last_region = r
			var hud: Node = Game.hud.get("hud") if Game.hud != null else null
			if hud != null:
				(hud.get("region_lbl") as Label).text = Game.world.region_name(r)
	_region_t -= delta
	var a := clampf(minf(_region_t / 0.8, (4.5 - _region_t) / 0.6), 0.0, 1.0)
	region.modulate.a = a
	region_sub.modulate.a = a
