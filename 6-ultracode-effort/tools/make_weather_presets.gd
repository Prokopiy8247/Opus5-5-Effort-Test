extends SceneTree
## Writes data/weather/<id>.tres (one WeatherPreset per weather state) from WeatherPreset.configure().
## Run: Godot_console.exe --headless --path <project> --script res://tools/make_weather_presets.gd

const WeatherPreset := preload("res://scripts/env/weather_preset.gd")
const IDS: Array[StringName] = [&"clear", &"cloudy", &"rain", &"fog", &"storm"]


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://data/weather"))
	var ok := 0
	for id in IDS:
		var p := WeatherPreset.new()
		p.configure(id)
		var path := "res://data/weather/%s.tres" % id
		var err := ResourceSaver.save(p, path)
		if err == OK:
			ok += 1
		print("weather preset ", path, " -> ", error_string(err))
	print("WEATHER_PRESETS_OK ", ok)
	quit(0 if ok == IDS.size() else 1)
