# PROGRESS — Horizon Drift: Four Valleys

Run ID: `run-20261023-185237` (start 2026-10-23T18:52:38+02:00). Segment 2 resumed at 19:10:27+02:00 (same session, after an MCP reconnect).

## Verified paths / ports / commands
- Project: `W:\YouTube\Opus 5.5 Effort Test\1. Opus 5.5 Forza Low Effort\1.-opus-5.5-forza-low-effort`
- Godot 4.7.2 console: `W:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe` (version `4.7.2.stable.official.ed1daf0bf`)
- Blender: MCP server `blender-opus55-low` (`uvx mcp-for-blender --port 9877`), localhost:9877. When the MCP tool was disconnected, the same addon socket was driven by `tools/bl.py` (the same endpoint). Verified `bpy.data.filepath` = the master `Opus55ForzaLowEffort.blend` in the project folder.
- Run: `godot --path .` | Shots: `godot --path . -- --shots=<dir>` | Drive tests: `-- --drivetest` | Lap: `-- --lap` | Car close-ups: `-- --carshots=<dir>`

## Milestones
1. DONE — 10 player cars + 6 traffic vehicles in Blender, exported to GLB (segment 1).
2. DONE — World generator (4 regions, 13 roads, 41.1 km, loop 20.2 km), road meshes and collision, bridges, tunnel shells, furniture.
3. DONE — Terrain streaming (WorkerThreadPool, 2 LODs plus a far mesh) with HeightMapShape3D collision.
4. DONE — Raycast vehicle, cameras, procedural audio, HUD, minimap and full map, console, garage, debug menu.
5. DONE — Traffic, weather and time of day, events, save/load, photo mode.
6. DONE — Blender kit (road furniture, nature, buildings), with settlements and POIs placed.
7. DONE — QA: drive tests, full-loop lap (104 FPS avg, no falls), functional test, docs, metrics.
8. DONE — Gamepad support removed (user request).

## Known bugs / limitations
- Car bodies are lofted low-poly shapes; the cabin pillars are simplistic.
- Tunnels are shells over terrain cuttings (the heightmap cannot have holes).
- Traffic transfers at junctions without turn signals or real lane changes; traffic drives through jump ramps kinematically.
- Holding brake at a standstill engages reverse (by design, arcade style).

## Next steps
1. Teach the autopilot to avoid traffic so long laps run without getting stuck.
2. Get drift-zone scores in an automated test, or tune drift.
3. Do an asynchronous teleport stream to remove the 100 ms hitch.
