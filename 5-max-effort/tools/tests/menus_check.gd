extends Node
## QA script: screenshots of the garage menu (F1/Tab) and the benchmark/debug menu (F3).
## Run: Godot_console.exe --path . --resolution 1920x1080 -- --fresh --qa=script --script_path=res://tools/tests/menus_check.gd --out=qa_out/menus


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func run(qa: Node) -> void:
	var garage: Node = Game.main.get("garage")
	garage.call("open")
	await _frames(90)
	await qa.call("_shot", "menu_garage.png")
	garage.call("close")
	await _frames(10)
	var dbg: Node = Game.main.get("debug_menu")
	if dbg.has_method("open"):
		dbg.call("open")
	elif dbg.has_method("toggle"):
		dbg.call("toggle")
	await _frames(30)
	await qa.call("_shot", "menu_debug.png")
