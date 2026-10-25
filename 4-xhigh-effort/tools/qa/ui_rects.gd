extends Node
## Prints the global rects of the main UI controls (layout debugging).

func _ready() -> void:
	await get_tree().create_timer(1.0).timeout
	var ui: Node = Game.hud
	for n: String in ["hud", "minimap", "notes", "garage", "debug", "console"]:
		var c: Control = ui.get(n)
		print("RECT %s %s anchors(%.1f,%.1f,%.1f,%.1f) offs(%.0f,%.0f,%.0f,%.0f)" % [n, c.get_global_rect(), c.anchor_left, c.anchor_top, c.anchor_right, c.anchor_bottom,
			c.offset_left, c.offset_top, c.offset_right, c.offset_bottom])
	var hud: Control = ui.get("hud")
	for ch in hud.get_children():
		if ch is Control:
			print("  HUD child %s %s" % [ch.name, (ch as Control).get_global_rect()])
	print("viewport ", get_viewport().get_visible_rect())
	get_tree().quit(0)
