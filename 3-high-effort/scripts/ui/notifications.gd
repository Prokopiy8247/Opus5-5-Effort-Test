extends Control
## Toast notifications (event results, discoveries, region names, system messages).

var _queue: Array = []
var _box: VBoxContainer
var _region_label: Label
var _region_timer := 0.0
var _last_region := ""
var main: Node


func init_ui(m: Node) -> void:
	main = m
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box = VBoxContainer.new()
	UIStyle.place(_box, Control.PRESET_CENTER_TOP, -300, 96, 300, 600)
	_box.alignment = BoxContainer.ALIGNMENT_BEGIN
	_box.add_theme_constant_override("separation", 8)
	_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_box)
	_region_label = UIStyle.label("", 34, UIStyle.TEXT)
	UIStyle.place(_region_label, Control.PRESET_CENTER_TOP, -400, 30, 400, 80)
	_region_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_region_label.modulate.a = 0.0
	add_child(_region_label)
	Game.notify.connect(_on_notify)


func _on_notify(title: String, body: String, kind: String) -> void:
	var pc := PanelContainer.new()
	var accent := UIStyle.ACCENT
	match kind:
		"record":
			accent = Color(0.4, 1.0, 0.55)
		"fail":
			accent = UIStyle.DANGER
		"event":
			accent = UIStyle.ACCENT2
	var sb := UIStyle.panel(UIStyle.PANEL, 10, accent)
	sb.border_width_left = 5
	pc.add_theme_stylebox_override("panel", sb)
	pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var v := VBoxContainer.new()
	v.add_child(UIStyle.label(title.to_upper(), 22, accent))
	if body != "":
		var b := UIStyle.label(body, 17, UIStyle.TEXT)
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.custom_minimum_size = Vector2(560, 0)
		v.add_child(b)
	pc.add_child(v)
	_box.add_child(pc)
	pc.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(pc, "modulate:a", 1.0, 0.25)
	tw.tween_interval(3.8 if kind != "record" else 5.0)
	tw.tween_property(pc, "modulate:a", 0.0, 0.5)
	tw.tween_callback(pc.queue_free)
	while _box.get_child_count() > 4:
		_box.get_child(0).queue_free()


func _process(delta: float) -> void:
	var _t0 := Time.get_ticks_usec()
	_process_inner(delta)
	Game.prof_add("notify", Time.get_ticks_usec() - _t0)


func _process_inner(delta: float) -> void:
	if main == null or main.player == null or Game.world == null:
		return
	var p: Vector3 = main.player.global_position
	var r: String = Game.world.data.region_name(p.x, p.z)
	if r != _last_region:
		_last_region = r
		_region_label.text = r.to_upper()
		_region_timer = 4.0
	_region_timer -= delta
	_region_label.modulate.a = clampf(minf(_region_timer, 4.0 - _region_timer) * 1.5, 0.0, 1.0)
