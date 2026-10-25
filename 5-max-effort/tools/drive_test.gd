extends SceneTree
## Automated drive tests (scripted inputs, headless, fixed 120 Hz steps).
## Run:  Godot_console.exe --headless --fixed-fps 120 --path <project> --script res://tools/drive_test.gd -- [--cars=1,3] [--proto] [--quick]
## Writes qa_out/drive_tests.json and prints a markdown table.


func _initialize() -> void:
	var runner := load("res://tools/drive_test_runner.gd").new() as Node
	runner.name = "DriveTestRunner"
	root.add_child(runner)
