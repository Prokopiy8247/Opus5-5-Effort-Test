# PROGRESS — running log (re-read after any context reset)

## Verified facts (do not re-derive)
- Project: `W:\YouTube\Opus 5.5 Effort Test\5. Opus 5.5 Forza Max Effort\5.-opus-5.5-forza-max-effort`
- Godot: `W:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe` → `4.7.2.stable.official.ed1daf0bf`
- Blender MCP: server `blender-opus55-max` (`.mcp.json`: `uvx mcp-for-blender --port 9881`), Blender 5.2.2 LTS,
  scene prop `blendermcp_port = 9881`, `bpy.data.filepath` = `<project>\Opus55ForzaMaxEffort.blend` (verified 19:15 CEST,
  re-verified 23:00 CEST before the garage build). Add-on protocol 13 vs server 14 (warning only; not patched per spec).
- Master backup: `backups/blender/Opus55ForzaMaxEffort_original_2026-10-23_1913.blend` (SHA256 DD32D0FF…A410).
- Run dir: `.opus-5.5-forza-godot-runs/run-20261023-185330-max/` (start_time.txt from segment 1, segments.txt).
- This session id: 417a090e-f30c-4f33-b4c4-3714e17336b8 (segment 2 start 2026-10-23T19:13:03+02:00).
- Machine: RTX 5070, Ryzen 7 5700X3D 8C/16T, 64 GB RAM. Other agents' Blender/Godot processes run concurrently and keep
  the GPU at 80-98 % for long periods — FPS numbers are lower bounds; never kill processes not started by this session.
- Git: baseline `1f42a9a`; milestones listed by `git log --oneline`.

## Commands
- Import / refresh class cache (needed after adding a `class_name`): `Godot_console.exe --headless --path . --import`
- Project settings / Input Map: `... --headless --path . --script res://tools/setup_project.gd`
- Data (.tres): `... --headless --path . --script res://tools/build_data.gd`
- World bake (deterministic, ~17 s): `... --headless --path . --script res://tools/bake_world.gd`, then
  `tools/build_activities.gd` (activities depend on road heights) and `tools/render_map.gd` (map.png)
- Drive tests: `... --headless --fixed-fps 120 --path . --script res://tools/drive_test.gd -- [--cars=1,3] [--quick] [--proto]`
- QA in a real window: `Godot_console.exe --path . --resolution 1920x1080 -- --fresh --qa=shots --set=basic|garage|world|traffic|aerial`
  or `--qa=bench --seconds=60`, or `--qa=script --script_path=res://tools/tests/<x>.gd` (ui_check, final_check,
  activities_check, ride_height_check, drive_shots, views_check, rewind_check; network_drive works headless)
- Contact sheet of screenshots: `... --headless --path . --script res://tools/contact_sheet.gd -- --dir=res://qa_out/<dir>`
- Blender (MCP execute_blender_code): `sys.path.insert(0, <project>/tools/blender)`, `import kit_common, carkit, car_specs`,
  `carkit.preview_and_export(car_specs.SPECS[id], <project>/assets/imported/cars)`, `kit_common.save_master()`

## Milestones
- [x] M0 environment verified, research done (RESEARCH_NOTES.md), git baseline
- [x] M1a custom vehicle physics + drive tests (10 handling profiles; VehicleBody3D comparison)
- [x] M1b first Blender car (01_pico_furia) → glb → drivable in game
- [x] M2 main scene, chase camera, HUD, console, garage menu, debug menu, save/load, QA runner
- [x] M3 world generator (41.2 km roads, 20.3 km loop) + GPU terrain streaming
- [x] M4 traffic (lane graph, IDM, junctions, 6 Blender vehicle types, pooling, LOD)
- [x] M5 props/nature kit (51 Blender props) + prop/vegetation managers; perf pass (physics-interpolation fix)
- [x] M6 all 10 Blender cars (commit e62787b), drive tests on the real models
- [x] M7 world fix: slope-limited roads (were up to 166 %), cone-cut pass valleys, tunnel holes, 50 m vertical curves;
      whole network driven end to end by the autopilot (`network_drive`: 40.5 km, 0 stuck / 0 falls)
- [x] M8 activities (24), GPS navigator, minimap, world map, photo mode, rewind
- [x] M9 docs (DEVELOPMENT, FEATURE_MATRIX, final report), final bench (160 FPS avg, p99 15.3 ms), metrics

## Current status
- Complete. All WORKING features in FEATURE_MATRIX.md exercised by QA scripts; `final_check` 44/44 PASS; activities
  completed end to end (race, loop time trial 11:08.70, drift scoring); docs and final report written.

## Next three steps
1. (optional) visual damage, AI race opponents, parked cars.
2. (optional) more varied cut-wall materials in the highlands.
3. (optional) packaged export.

## Follow-up requests
- 2026-10-25: Windows exe export (`tools/export_windows.ps1` -> `build/RidgelineFestival/RidgelineFestival.exe`,
  embedded pack, custom icon `assets/icon_ridgeline.svg`); spawn moved 40 m past the loop trial gate.

## User decisions during the run
- 2026-10-23 ~21:30: user asked NOT to implement gamepad support -> Input Map is keyboard + mouse only
  (tools/setup_project.gd); documented as intentionally omitted in FEATURE_MATRIX/DEVELOPMENT.

## Known issues
- Autopilot QA occasionally rolls a car at the speed limit in hairpins/gravel (4 flips in 22 km after the roll assist);
  the car rights itself automatically (flip recovery) and players can press R.
- Exit prints "2 ObjectDB instances were leaked" in some QA runs (harmless).
- Cone-cut walls in the highlands are steep (49°) rock faces; rocks on them are sunk by slope.

## Lessons (keep)
- Physics interpolation ON + MultiMeshInstance3D: every MMI add cost 5-10 ms and grew with count → static world nodes
  opt out (`physics_interpolation_mode = OFF`).
- Never `wait_for_task_completion` on an unfinished worker task from the main thread (it runs other queued jobs).
- `get_process_delta_time()` is clamped (max physics steps) → benchmarks use wall-clock frame times.
- Autoloads are unavailable in `--script` tools; new `class_name` scripts need `--import` before tools see them.

## Subagents used
- Research (general-purpose, model inherited = Claude Opus 5.5): FH5 + Godot docs research; ~303k tokens, 174 tool uses, ~33 min.
