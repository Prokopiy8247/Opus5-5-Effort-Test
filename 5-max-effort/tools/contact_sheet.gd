extends SceneTree
## Composes QA screenshots into one contact sheet (for quick visual review).
## Run: Godot_console.exe --headless --path . --script res://tools/contact_sheet.gd -- --dir=res://qa_out/garage
##      [--prefix=garage_] [--cols=2] [--w=560] [--out=res://qa_out/garage_sheet.png]


func _initialize() -> void:
	var args := {"dir": "res://qa_out", "prefix": "", "cols": "2", "w": "560", "out": ""}
	for a in OS.get_cmdline_user_args():
		var s := String(a)
		if s.begins_with("--") and s.contains("="):
			args[s.substr(2, s.find("=") - 2)] = s.substr(s.find("=") + 1)
	var dir := String(args["dir"])
	var files: Array[String] = []
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".png") and f.begins_with(String(args["prefix"])) and not f.contains("sheet"):
			files.append(f)
	files.sort()
	if files.is_empty():
		print("no images in ", dir)
		quit(1)
		return
	var cols := int(args["cols"])
	var w := int(args["w"])
	var first := Image.load_from_file(ProjectSettings.globalize_path(dir.path_join(files[0])))
	var h := int(round(float(w) * first.get_height() / first.get_width()))
	var rows := int(ceil(files.size() / float(cols)))
	var sheet := Image.create(w * cols, h * rows, false, Image.FORMAT_RGB8)
	for i in files.size():
		var img := Image.load_from_file(ProjectSettings.globalize_path(dir.path_join(files[i])))
		img.convert(Image.FORMAT_RGB8)
		img.resize(w, h, Image.INTERPOLATE_BILINEAR)
		sheet.blit_rect(img, Rect2i(0, 0, w, h), Vector2i((i % cols) * w, (i / cols) * h))
	var out := String(args["out"])
	if out == "":
		out = dir.path_join("sheet.png")
	sheet.save_png(ProjectSettings.globalize_path(out))
	print("sheet ", files.size(), " images -> ", ProjectSettings.globalize_path(out))
	quit()
