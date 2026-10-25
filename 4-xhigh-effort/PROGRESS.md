# PROGRESS — running log (re-read after any context reset)

## Verified environment (do not re-derive)
- Project: `W:\YouTube\Opus 5.5 Effort Test\4. Opus 5.5 Forza xhigh Effort\4.-opus-5.5-forza-xhigh-effort`
- Godot: `W:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe` → `4.7.2.stable.official.ed1daf0bf` (Forward Plus, Jolt, d3d12)
- Machine: RTX 5070, Ryzen 7 5700X3D (8C/16T), 64 GB RAM, 2560x1440 @180 Hz desktop
- Git 2.51.1, Python 3.12.10 (host), Blender 5.2.2 LTS (MCP add-on protocol 13; server expects 14 — warning only)
- Blender MCP: server `blender-opus55-xhigh` (`uvx mcp-for-blender --port 9880`), tool namespace `mcp__blender-opus55-xhigh__*`
- Verified `bpy.data.filepath` = `<project>\Opus55ForzaXhighEffort.blend` (2026-10-23 19:13 and before every build via `vgk_common.guard()`)
- Master backup: `backups/blender/Opus55ForzaXhighEffort.original-20261023-191638.blend` (sha256 14FE2274…E656)
- Run dir: `.opus-5.5-forza-godot-runs/run-20261023-185306-xhigh/` (start 2026-10-23T18:53:06.634+02:00; segment 2 started 19:12:50)
- User request mid-run: **no gamepad support** (keyboard + mouse only).

## Milestones
| # | Milestone | Commit | State |
|---|---|---|---|
| 0 | Setup, research, plan, git baseline | 4e3e5a3 | done |
| 1 | First car pipeline + raycast vehicle + camera + drive tests | b63b6d7 | done |
| 2 | Open world bake, terrain streaming, road network, water, dressing | 78b64ff / 8da6aeb | done |
| 3 | Sky/day-night/weather, HUD, minimap, map + GPS, console, garage, debug, photo mode, save/load | 4fb381b | done |
| 4 | All 10 Blender cars + handling data, traffic system, road/junction fixes, loop soak | c8486a2 | done |
| 5 | Traffic fleet (6 Blender types), tyre-normal fix, gearbox short-shift | cea77eb | done |
| 6 | Blender world kit (vegetation, buildings, landmarks, road furniture, activity props) | 9649eff | done |
| 7 | Activities, procedural audio, driving VFX, rewind | bd79f1b | done |
| 8 | Road signs | 7a0a923 | done |
| 9 | Final QA pass, docs | ef169a8 + docs commit | done |
| 10 | End time, token usage, API-equivalent cost, metrics block | final commit | done |

## Verified working (automated + screenshots)
- Boots into free roam on the loop; first launch bakes the world (~30 s).
- 10 cars drive; drive tests all stable (`qa/results/drive_*.json`); VehicleBody3D comparison recorded.
- Full-loop autopilot soak without falls; traffic spawns/despawns with physics/kinematic LOD.
- Activities: trap, zone, drift, jump, race all complete in `activities_test`.
- Console (39 commands, 13 assertions), save/load round trip, audio pitch test, FX/photo screenshots.

## Final validation (2026-10-24)
- Clean launch (`--quit-after 3500`): no script errors or warnings.
- Perf: 157 FPS avg over a 10-min 1080p soak (p99 16 ms), 172.5 FPS at 720p, 314 km/h streaming p99 11 ms; no falls, no leaks.
- Activities suite, console (13/13), save/load, rewind, audio (30/30), drive tests (10/10) all pass.
- World: 40.04 km roads, 47 bridges, 602 m tunnel, 60 structures, 59,007 vegetation instances, 20 activities.

## Next three steps (if work resumes)
1. Race AI opponents (ghost cars on the race line).
2. Fences/hedgerows and 3D crops on the farm fields.
3. Visual damage and collectibles.

## Known bugs / limitations
- No race AI opponents, no visual damage, no collectibles, no fences/culverts.
- QA autopilot can leave narrow gravel roads at speed (test tool only).
- Saw-tooth terrain edge beside steep road sides visible from high aerial views.

## Useful commands
- Run with timeout: `powershell -File tools/run_godot.ps1 -Timeout 300 -Filter "ERROR|SCRIPT" -A "--path . -- --qa=screens"`
- Import: `... -A "--headless --path . --import"`; setup: `--script res://tools/setup_project.gd`; data: `--script res://tools/gen_data.gd`; bake: `--script res://tools/world_bake.gd`
- Drive test: `-A "--headless --fixed-fps 120 --path . -- --test-track --qa=drive_test --car=<id>"`
- Blender (through MCP): `exec(open(bpy.path.abspath("//tools/blender/run_build.py")).read()); build(["SolanoCoupe"], export=True)`; kit: `import kit_builder; kit_builder.build_all()`
