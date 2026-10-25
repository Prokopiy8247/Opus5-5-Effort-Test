extends SceneTree
## Generates res://data/events/events.json from the baked road network (run after tools/bake_world.gd):
##   Godot_console.exe --headless --path <project> --script res://tools/make_events.gd
## Placement logic lives in scripts/activities/event_planner.gd (also used at runtime as a fallback).

const Planner := preload("res://scripts/activities/event_planner.gd")
const OUT := "res://data/events/events.json"


func _init() -> void:
	var wd := WorldData.new()
	if not wd.load_all():
		push_error("make_events: world data missing - run tools/bake_world.gd first")
		quit(1)
		return
	var planner := Planner.new()
	var out: Dictionary = planner.plan(wd)
	for line in planner.log_lines:
		print("[events] ", line)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT.get_base_dir()))
	var f := FileAccess.open(OUT, FileAccess.WRITE)
	if f == null:
		push_error("make_events: cannot write " + OUT)
		quit(1)
		return
	f.store_string(JSON.stringify(out, "\t"))
	f.close()
	var counts := {}
	for ev: Dictionary in out["events"]:
		counts[ev["kind"]] = int(counts.get(ev["kind"], 0)) + 1
	print("[events] wrote %d events %s -> %s" % [(out["events"] as Array).size(), str(counts), ProjectSettings.globalize_path(OUT)])
	quit(0)
