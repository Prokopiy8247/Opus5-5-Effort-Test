# PROGRESS — Velora Roads (running log)

Run: `run-20261023-191202` (start 2026-10-23T19:12:02+02:00). An earlier aborted attempt left
`.opus-5.5-forza-godot-runs/run-20261023-185251/` (not part of this session's timing).

## Verified facts / commands
- Godot: `W:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe` (4.7.2.stable, Jolt, Forward+, D3D12)
- Blender MCP: server `blender-opus55-high` (`uvx mcp-for-blender --port 9879`), Blender 5.2.2, master file verified via `bpy.data.filepath`
- All QA/tool commands: see DEVELOPMENT.md. Add `--fresh` after `--` to ignore the save file, `--reset-save` to delete it.
- Always give SceneTree scripts a guaranteed quit(); a parse error leaves the process waiting.
- Only kill Godot/Blender processes started by this session (other projects run on this machine and share the GPU).

## Milestones (all done this session)
1. [x] Baseline project, git, run timing
2. [x] Blender car kit + first car exported/imported/drivable
3. [x] Raycast vehicle (Jolt, 120 Hz) + 5 camera modes; drive tests
4. [x] World generator: 4 regions, coast/bay, river, 40.5 km roads, 20.2 km loop, bridges, tunnel, hairpins
5. [x] Terrain streaming (threaded), roads, water, sky/day-night/weather
6. [x] All 10 garage cars + 6 traffic vehicles + 33 props from Blender
7. [x] HUD/minimap, console, garage (paint/upgrades/tuning), debug menu, notifications
8. [x] Traffic (lanes, IDM, junctions, pooling, LOD, crash response)
9. [x] Dressing: vegetation, grass, settlements, landmarks, signs, lamps, wind farm, festival
10. [x] Activities: traps, zones, drift, jumps, races with AI, Grand Tour time trial, boards
11. [x] Procedural audio, tyre FX, skid marks
12. [x] Map + GPS, photo mode, save/load + autosave
13. [x] QA: drive tests (dry/wet/upgraded/assists-off), full-loop test, events, crash, save/load, screenshots, perf
14. [x] Docs + final report

## Verified this session (highlights)
- Full 20 km loop driven end-to-end by autopilot, never below the surface.
- All activities fired in automated tests; race with 3 AI opponents finished.
- Save/load round trip across two processes.

## Known issues / limitations
- Performance numbers are contaminated by other projects sharing the GPU (see report).
- No damage model, no rewind, no overtaking traffic, no parked cars, no liveries.
- Junction mouths: branch-road meshes overlap the main road edge slightly.
- Manual gearbox and tuning sliders implemented but not covered by automated tests.

## Next steps (if work resumes)
1. Graphics quality presets (shadows/grass/SSAO) for weaker GPUs.
2. Traffic overtaking on the highway and parked cars at villages.
3. Visual damage and rewind.
