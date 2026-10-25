# PROGRESS — Sunward Roads (running log)

Re-read this file after any context reset. Newest entries at the bottom of the log.

## Verified facts (paths / ports / commands)
- Project: `W:\YouTube\Opus 5.5 Effort Test\6. Opus 5.5 Forza Ultracode Effort\6.-opus-5.5-forza-ultracode-effort`
- Run ID: `run-20261023-185356-ultracode` (start 2026-10-23T18:53:56.828+02:00, segment 2 started 19:13:32+02:00, see `.opus-5.5-forza-godot-runs/<run>/segments.txt`)
- Godot: `W:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe` → `4.7.2.stable.official.ed1daf0bf`; project uses Forward Plus, D3D12, Jolt Physics.
- Blender MCP: server `blender-opus55-ultracode` (`.mcp.json`: `uvx mcp-for-blender --port 9882`), tools `mcp__blender-opus55-ultracode__*`.
  Verified `bpy.data.filepath` = `<project>\Opus55ForzaUltracodeEffort.blend`, Blender 5.2.2 LTS, add-on protocol 13 (server expects 14; warning only, execute_code works).
- Master backup (byte-identical, SHA-256 269f49a0…1922): `backups/blender/Opus55ForzaUltracodeEffort_original_20261023-185616.blend`
- Hardware: RTX 5070, Ryzen 7 5700X3D (16 threads), 64 GB RAM.
- Godot class reference of the installed engine dumped with `--doctool` to the session scratchpad (`godot_doc/doc/classes/*.xml`) for API verification.

## User decisions (binding)
- 2026-10-23 ~21:30: **no gamepad support** — keyboard + mouse only (Input Map has no joypad events; contracts updated).
- 2026-10-24 ~07:50: **test runs must be silent and no further work on sound.** Every test launch (test scene, `--script`
  tool or `--qa` mode) now mutes the master bus automatically (`Settings.test_run`); a normal launch of the game keeps
  its sound. Audio stays as implemented; audio findings from later QA are not acted on.

## Current milestone
M1 — foundation + first car + driving model.

## Subagent / workflow usage
| When | Workflow | Model | Purpose |
|---|---|---|---|
| 19:20 | `fh5-godot-research` (5 researchers + synthesizer + critic) | claude-opus-5-5 (inherited) | Section 0 research → RESEARCH_NOTES.md, pricing page |
| 19:30 | `blender-car-garage` (serial agents, exclusive Blender access) | claude-opus-5-5 (inherited) | car_kit.py + 10 cars, QA renders, glb export, review/fix |
| 22:33 | `sunward-systems` (8 parallel implementers, disjoint files) | claude-opus-5-5 (inherited) | UI HUD, menus, environment, audio, effects, traffic, activities, dressing |
| 00:40 | `sunward-review` (5 finders + 2 adversarial verifiers per finding, 59 agents) | claude-opus-5-5 (inherited) | bug/perf review of all subsystems |
| 01:40 | `sunward-review-fixes` (3 parallel fixers, disjoint files) | claude-opus-5-5 (inherited) | fix confirmed UI / traffic+activities / dressing+audio findings |
| 02:35 | `sunward-playtest` (6 area playtesters + 1 independent reproducer per finding) | claude-opus-5-5 (inherited) | exploratory in-game QA with screenshots |
| 05:05 | `sunward-playtest-fixes` (6 parallel fixers, disjoint files) | claude-opus-5-5 (inherited) | fix the 47 reproduced playtest defects |
| 05:15 | `blender-props-traffic` (serial agents via tools/blender/mcp_call.py) | claude-opus-5-5 (inherited) | 6 traffic vehicles, nature / roadside / buildings kits, review |
| 07:35 | `sunward-playtest-r2` (5 testers + reproducers, 44 agents) | claude-opus-5-5 (inherited) | second exploratory QA round |
| 08:50 | `sunward-playtest-fixes-r2` (5 parallel fixers) | claude-opus-5-5 (inherited) | fix the 39 round-2 defects |
| 13:45 | `sunward-playtest-r3` (5 testers + reproducers) | claude-opus-5-5 (inherited) | third QA round: Blender world props, regression, performance |

Rule: while `blender-car-garage` runs, the main agent does not touch the Blender MCP.

## Log
- 19:13 Segment 2 start. Read spec. Verified Godot 4.7.2, git 2.51, Python 3.12, Blender path. Git init + baseline commit `04c18f0`.
- 19:20 Research workflow launched. 19:30 car workflow launched. Wrote `docs/ASSET_CONVENTIONS.md` (Blender↔Godot contract).
- 19:45 Core: project settings tool (`tools/setup_project.gd`), autoloads Game/Settings/SaveGame, CarData/SurfaceData/UpgradeData resources (`tools/make_game_data.gd`), raycast CarController, CarFactory, CarVisuals (paint shader), CarInput, CameraRig.
- 19:55 Drive tests (`tools/tests/drive_test.tscn`) pass for all 10 cars (placeholder bodies): see qa_output/drive_tests.json. Godot's built-in .blend importer disabled (it spawned Blender on the master file - read-only export, no modification).
- 20:10 RESEARCH_NOTES.md delivered by research workflow (pricing: Opus 5.5 $4 in / $5 5m-cache-write / $8 1h / $0.20 read / $20 out per MTok, to re-verify at end).
- 20:00-21:00 World generator (`scripts/world/world_gen.gd`, `world_layout.gd`, `tools/bake_world.gd`): seeded terrain (4 regions, river, lake, 2 canyons, coast, tunnel spur), 23 roads spline+meander+profile+grade limit, bridges/tunnels, carving, maps. Iterated layout 6x looking at qa_output/world_debug.png. Runtime: WorldData, RoadNetwork, TerrainStreamer (WorkerThreadPool LOD chunks + trimesh colliders), RoadBuilder (meshes, colliders, rails, bridges, tunnel, posts, chevrons), World node, water, far terrain, QaDirector, RoadFollower.
- Lesson: a parse error in a `--script` SceneTree tool makes Godot hang forever -> always run tools with `timeout` and check with `res://tools/check_scripts.tscn` first.

- 21:00 Systems workflow launched (8 parallel implementers, see tools/workflows/systems_workflow.js). VehicleBody3D comparison done. Rewind added.
- 21:15 Blender MCP server for this session restarted/disconnected (config unchanged; new uvx process on 9882 at 21:13). The car workflow agent keeps working (its own connection).
- 21:30 Road QA: crossing detector (tools/check_crossings.py) + roadcheck/probe QA modes. Fixed 4 unintended crossings, festival loop cusp, hairpin kinks, collider seams. Ring 20.16 km, network 41.75 km, 0 crossings. Gamepad removed (user request).

- 22:30-00:40 All 8 subsystem agents delivered (reports in qa_output/agent_reports_*.md). Integrated core change requests (tunnel false-sunk, headlights, ABS lock flag, time-scale getter, camera persist flag, respawn override, CarEffects for traffic pending). Removed gamepad paths from UI.
- 23:00-00:40 World QA fixes: camber-aware carve, terrain clamp under roads, tunnel clearance + open portals, vertical curves, bridge/rail mesh stitching bug (fins with collision), junction keep-out, level junction aprons, junction overlap, hill hold, safe teleports (30/30).
- 00:40 Review workflow (wf_796a224f-895) launched. Blender: 5/10 cars exported (kestrel, aurelia, brute, sora, castellan).

- 00:40-01:10 Hairpin kinks: meander suppressed in NO_MEANDER_ZONES (switchbacks, tunnel); ring re-lengthened via alpine/mesa lobes -> 20.26 km, network 41.87 km, 0 crossings, no curve < 20 m; teleports 30/30.
- 01:10-01:30 Roadcheck found side roads 0.5-2.2 m above/below their parent at 7 acute junctions -> junction aprons now follow the parent's height at the nearest point while overlapping; fillets blend parent edge -> child height; child lowering follows the parent's line. Only intended jump ramps remain in the roadcheck. Cars 6-7 (vortex_x, granite_rally) imported and checked in game.
- 01:35 Review workflow done: 24 findings confirmed by 2/2 adversarial verifiers, 3 rejected. Core ones fixed by me (overlay hold drove reversing cars, tunnel rebuild snapping onto the tube roof, night headlights on new cars, stale rewind buffer, g spike after rebuild, dirt reset, NPC effects cap, stale look-back, rails/posts/chevrons never drawn on long roads because of whole-road AABBs, stale streamer readiness after teleports, per-frame dispatch sort) with an in-game regression test `tools/tests/core_fix_test.tscn` (8/8 PASS). UI / traffic+activities / dressing+audio findings handed to a 3-agent fix workflow (wf_a5bc9af5-ff0).

- 02:00-02:35 All 24 review findings fixed (traffic/activities fixer A/B-verified against the old code). Junction cross-slope: side roads now tilt into the parent's surface plane across the apron (roadcheck steps 8-45 cm: 98 -> 1). Braking line assist, 19 culverts, F12 screenshots, event tags depth-tested, final validation scene (all checks pass except the 2 cars not yet exported). Car 8 imported.

- 03:00-05:10 Playtest workflow (54 agents): 47 of 48 reported defects reproduced independently -> 6-agent fix workflow (wf_fad72421-aa2) by file ownership. Barriers moved to physics layer 6 (wheel rays ignore them). Blender car workflow finished: all 10 cars + review (8 good, 2 fixed: Kestrel splitter through the wheels, Sora brake-light z-fight / inverted seats / see-through gaps), all imported and checked in game.
- 05:10 The props workflow could not see the Blender MCP tools: this session's attached `blender-opus55-ultracode` server dropped out at the 21:13 restart and the host lists no way to re-attach it (the car workflow kept the tool set it was launched with). Resolution: `tools/blender/mcp_call.py`, a stdio MCP client that launches exactly the `.mcp.json` server command (`uvx mcp-for-blender --port 9882`, asserted) and calls its tools; verified `bpy.data.filepath` is the master file and `look` returns images. Props workflow relaunched with that client (wf_00c383d5-8dd).

- 07:30-13:40 Playtest round 2 (44 agents): 39 new defects reproduced -> 5-agent fix workflow, all fixed (keyboard gearbox hunting was the main one). Blender props workflow finished through the stdio MCP client: 6 traffic vehicles, nature (24), roadside (25) and buildings/landmarks (25) kits + review; all integrated. Settlement start-up 12-25 s -> 0.35 s by pre-merging kit meshes and collision shapes offline (runtime merging did GPU readbacks). Lighthouse re-sited on the headland tip. Full regression suite green.
- 13:45 Playtest round 3 launched (world with the Blender props, regression sweep, performance).

- 13:45-22:00 Playtest round 3 (35 agents): 29 of 30 reported defects reproduced (mostly prop collisions: AABB boxes far outside the Blender buildings, drive-through fences/rocks/cacti) -> 5-agent fix workflow, all fixed; settlement rocks/cacti convex colliders, benchmark guard, minimap road label, docs by the lead. Regression suite green.
- 22:20-23:10 Final phase: clean 1080p performance lap (28.3 km, 139 FPS avg, 0.005 % frames > 33 ms, memory flat after warm-up), final validation 20/20 with documentation screenshots (`docs/screenshots/final/`), cold start ~12.4 s, final report, clean-up of test user data, metrics.

## Next three steps
1. (done) Final validation, performance, report and metrics - see OPUS_5.5_FINAL_REPORT.md.
2. Possible follow-ups: overtaking through the oncoming lane, parked cars at fuel stations, steps for raised doors.
3. -

## Known bugs
- See "Known bugs and limitations" in OPUS_5.5_FINAL_REPORT.md and "Known limitations" in DEVELOPMENT.md.
