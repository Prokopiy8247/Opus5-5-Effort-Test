extends RefCounted
## Screenshot files shared by photo mode capture and the global screenshot key (F12):
## user://screenshots/sunward_<timestamp>[_n].png.
## save_viewport_async() reads the frame back without stalling the GPU and encodes the PNG on a worker thread
## (the encode alone takes about half a second), so a capture does not freeze the game.

const DIR := "user://screenshots"

## Paths handed out by the async save and not written yet -> worker task id (-1 until it is queued).
static var _pending: Dictionary = {}


## Creates the folder and returns an unused timestamped path.
static func next_path() -> String:
	DirAccess.make_dir_recursive_absolute(DIR)
	var stamp := Time.get_datetime_string_from_system(false, true).replace(":", "-").replace(" ", "_")
	var path := DIR.path_join("sunward_%s.png" % stamp)
	var n := 1
	while FileAccess.file_exists(path) or _pending.has(path):
		n += 1
		path = DIR.path_join("sunward_%s_%d.png" % [stamp, n])
	return path


## Saves the viewport's last rendered frame; returns the path, or "" when it could not be written.
## Blocks for the readback and the encode (tools only; the game uses save_viewport_async).
static func save_viewport(vp: Viewport) -> String:
	var img := vp.get_texture().get_image() if vp != null else null
	if img == null or img.is_empty():
		return ""
	var path := next_path()
	return path if img.save_png(path) == OK else ""


## Saves the viewport's last rendered frame (call right after RenderingServer.frame_post_draw) in the
## background. `done` runs on the main thread with the path, or "" when the file could not be written.
static func save_viewport_async(vp: Viewport, done: Callable) -> void:
	if vp == null:
		done.call("")
		return
	var path := next_path()
	_pending[path] = -1
	var rd := RenderingServer.get_rendering_device()
	var tex := RenderingServer.texture_get_rd_texture(vp.get_texture().get_rid()) if rd != null else RID()
	if tex.is_valid():
		var fmt := rd.texture_get_format(tex)
		if fmt.format == RenderingDevice.DATA_FORMAT_R8G8B8A8_UNORM or fmt.format == RenderingDevice.DATA_FORMAT_R8G8B8A8_SRGB:
			var w := int(fmt.width)
			var h := int(fmt.height)
			var on_data := func(data: PackedByteArray) -> void:
				_queue_encode(path, func() -> Image: return Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, data), done)
			if rd.texture_get_data_async(tex, 0, on_data) == OK:
				return
	# No asynchronous readback (other renderer or texture format): read back now, still encode in the background.
	var img := vp.get_texture().get_image()
	if img == null or img.is_empty():
		_pending.erase(path)
		done.call("")
		return
	_queue_encode(path, func() -> Image: return img, done)


static func _queue_encode(path: String, make_image: Callable, done: Callable) -> void:
	var task := func() -> void:
		var img: Image = make_image.call()
		var ok := false
		if img != null and not img.is_empty():
			# The frame is opaque: RGB keeps the file a quarter smaller and encodes faster.
			img.convert(Image.FORMAT_RGB8)
			ok = img.save_png(path) == OK
		_encoded.call_deferred(path, ok, done)
	_pending[path] = WorkerThreadPool.add_task(task, false, "Screenshot PNG")


static func _encoded(path: String, ok: bool, done: Callable) -> void:
	var id: int = _pending.get(path, -1)
	_pending.erase(path)
	if id >= 0:
		WorkerThreadPool.wait_for_task_completion(id)
	if done.is_valid():
		done.call(path if ok else "")
