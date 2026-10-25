# OPUS 5.5 FINAL REPORT — Horizon Drift: Four Valleys

An original open-world arcade-sim racing game in Godot 4.7.2, inspired by the structure of Forza Horizon 5. It has no Forza branding or assets. Everything is project-owned: procedural code plus Blender MCP assets.

## What was built
- **World**: a procedural 4 × 4 km map with 4 regions: Verdance Vale (farmland and river), Highpine Ridge (mountains and switchbacks), Ochre Mesa (desert mesas) and Saltwind Coast (cliffs, bay, sea). It has 13 roads totalling 41.1 km, including the 20.2 km Grand Valley Loop and a 4-lane highway. Roads have cuttings and embankments, banking, lane markings, shoulders, guard rails (with collision), delineator posts, highway lamps, automatic bridges (river and bay), tunnel shells with portals and lights, and junctions.
- **Terrain**: chunked and threaded (WorkerThreadPool), with 2 LODs plus a far mesh, HeightMapShape3D collision near the player, and MultiMesh vegetation (pine, oak, palm, cactus, rocks, bushes, grass).
- **Settlements / POIs**: a village with church, a hamlet, 2 farms, 2 gas stations, a diner, a harbour with pier and boats, a lighthouse, a castle ruin, a wind farm with spinning rotors, and an alpine lodge.
- **Driving**: a project-owned raycast vehicle with springs and dampers from ride frequency, anti-roll, a combined-slip tyre model, per-surface and per-weather grip, an engine torque curve, an automatic/manual gearbox, FWD/RWD/AWD, aero drag and downforce, TCS, ABS, STM, steering assist, handbrake drifts, air control, reset and flip. There are chase, far-chase, hood, cockpit and bumper cameras with speed FOV, collision and shake. Audio is procedural: engine, turbo and blow-off, tyre squeal and gravel, wind, impacts, horn. Smoke, dust and skid marks are included.
- **Garage**: 10 Blender-authored cars, each with its own handling `.tres`, sound profile, class label and paint. You switch cars from the F1 garage, the console or the F2 debug menu.
- **Traffic**: 6 Blender traffic types (compact, van, lorry, bus, tractor, pickup) in a pool of 54. Up to 40 are active (24 at default density). They follow lanes, keep gaps, slow for curves and the player, give way at branch ends, transfer at junctions, choose types by region and road class, and turn into dynamic wrecks when hit.
- **Systems**: a day/night cycle; weather (clear, cloudy, rain, fog, storm with lightning) that changes visuals and grip; events (5 speed traps, 3 speed zones, 4 drift zones, 3 ramp jumps plus freestyle jumps, 2 checkpoint races, a loop time trial); paint and finish; 6 upgrade categories × 3 stages; 6 tuning parameters; photo mode; a HUD gauge; a heading-up minimap; a full map with waypoint; save/load; a developer console; garage and debug menus.
- **Input**: keyboard and mouse only. Gamepad support was removed at your request.

## What works / what is partial
See `FEATURE_MATRIX.md`. In summary:
- **Partial**: drift-zone scoring (not proven by automation), race and time-trial finishes (progression verified, a full finish was not exercised), tunnels (shells over cuttings), damage (a value only, no deformation).
- **Not implemented**: AI racers, collectibles, traffic overtaking, GPS route line, rim colours, gamepad.

## Validation performed (this session)
- `--headless` main-scene runs: no script errors. World ready in 3–5 s.
- **Screenshot tour** (`--shots`) of all regions, rain, fog, night, sunset, cockpit, garage, console, debug menu and map. I reviewed the images.
- **Car close-ups** (`--carshots`) for all 10 cars. This found and fixed inverted body normals and painted window shells.
- **Drive tests** (`--drivetest`, flat pad, 120 Hz):

| Car | Class | 0-100 (s) | 0-200 (s) | Top (60 s) | 100-0 (m) | Skidpad (g) |
|---|---|---|---|---|---|---|
| Kestrel GTi | B | 6.1 | – | 198 | 36.4 | 0.81 |
| Meridian Saloon | C | 7.8 | – | 177 | 40.1 | 0.69 |
| Ironhorse 440 | A | 6.5 | 18.6 | 228 | 40.8 | 0.68 |
| Arrow S | A | 5.4 | 18.9 | 228 | 33.9 | 0.80 |
| Solstice GT | S2 | 5.1 | 13.9 | 254 | 33.6 | 0.85 |
| Vortex R | S2 | 2.6 | 7.2 | 288 | 29.3 | 0.98 |
| Dustrunner WRC | A | 3.7 | – | 199 | 35.0 | 0.80 |
| Ridgeback 4x4 | C | 6.0 | – | 179 | 42.7 | 0.66 |
| Haulmark 2500 | C | 7.5 | – | 181 | 44.0 | 0.66 |
| Breeze Roadster '58 | D | 9.3 | – | 141 | 42.5 | 0.55 |

All cars were stable at top speed.
- **Full loop autopilot lap** (`--lap`, real window, RTX 5070, 1600×900, traffic on): 20.5 km in 761 s, **average 104 FPS**, minimum 26 FPS. The worst frame was 107 ms, and those spikes coincide with the test's forced respawns, which stream terrain synchronously. There were **no falls through the world**, memory growth was **3.6 MB**, and loaded chunks stayed at 110–210. The autopilot got stuck 16 times on traffic or hairpin edges (an autopilot limitation; it doesn't avoid traffic).
- **Functional test** (`--functest`): all 5 speed traps recorded bests; a speed zone completed; all 3 ramp jumps scored; checkpoints progressed; traffic stayed at 24 active; rain grip = 0.75; save → switch car → load restored the car, its engine stage 2 and its blue paint.
- **Bugs found and fixed during QA**: project-default linear damping halved top speed; rails had no collision (the car fell into the river); inverted car normals; buildings placed on roads; snow line too low; stuck autopilot respawn loop; bogus teleport "jumps".

## Known bugs
- In free-driving tests the autopilot can wedge against frozen traffic. Players can push wrecks, but heavy lorries feel like walls.
- Traffic passes through jump ramps (kinematic).
- Synchronous streaming on teleport causes a one-off hitch of about 100 ms.
- Car bodies are low-poly lofts; the Vortex cabin pillars look crude.

## Controls
See `DEVELOPMENT.md`. In short: W/S/A/D drive, Space handbrake, C camera, R reset, F1 garage, F2 debug, ` console, M map, P photo, F12 screenshot.

## Blender assets (all via the port-9877 connection)
- 10 player cars and 6 traffic vehicles (separate wheels with axle pivots, brake discs, glass, lights, interior, steering wheel).
- 12 road-kit pieces (guard rail, post, pillar, lamp, tunnel portal and light, event gate, jump ramp, danger sign, 2 signs, fence).
- 7 nature pieces.
- 15 buildings and POIs (3 houses, church, barn, silo, gas station, diner, warehouse, pier, boat, lighthouse, castle ruin, wind turbine and rotor).

The source scripts are `tools/blender_cars.py` and `tools/blender_kit.py`. The exports are in `assets/imported/vehicles` and `assets/imported/props`.

## Claude Opus 5.5 Godot Forza Session Metrics

```text
Project: Godot 4.7 Forza-style open-world racing game
Effort level under test: low
Run/session identifier: run-20261023-185237 (Claude Code session 4ceb4d61-760c-4ba5-a3a0-2c34e67110df)
Working-directory full path: W:\YouTube\Opus 5.5 Effort Test\1. Opus 5.5 Forza Low Effort\1.-opus-5.5-forza-low-effort
Start timestamp and timezone: 2026-10-23T18:52:38+02:00 (measured, start_time.txt)
End timestamp and timezone: 2026-10-23T21:46:12+02:00 (measured, end_time.txt)
Elapsed wall-clock time (HH:MM:SS): 02:53:34 (measured)
Elapsed minutes: 173.6
Known pauses / resumed segments: segment 1 18:52–~19:06 (cars authored, earlier agent session); gap/reconnect ~19:06–19:08; segment 2 19:08–21:46 (this session). Pauses are not subtracted.

Requested model: Claude Opus 5.5
Actual model identifier(s): claude-opus-5-5 (all 117 deduplicated requests in the session log)
Input tokens (state whether uncached or inclusive): 238 (uncached only)
Cache-read tokens: 28,975,169
Cache-write tokens: 328,971 (all 1-hour cache writes)
Output tokens: 192,938
Thinking/reasoning tokens (included / separate / unavailable): included in output; not separately exposed
Deduplicated total tokens: 29,497,316
Usage source and observation cutoff: local Claude Code session log ~/.claude/projects/<project>/4ceb4d61-….jsonl, assistant messages deduplicated by message id; cutoff 2026-10-23T19:45:38Z (21:45:38 local)
Unmeasured work / limitations: segment 1 (18:52–19:06, the 16 vehicles) ran in an earlier session whose usage log is not present on disk, so it is unmeasured; the final report-writing turn after the cutoff is not included; no subagents were used

Token-only API-equivalent cost (USD): $12.29 (measured for segment 2 only; partial for the whole run)
Official pricing source, verification date and tier: https://platform.claude.com/docs/en/about-claude/pricing, verified 2026-10-23, standard API tier
Rates and formula used: Opus 5.5 base input $4/MTok, 1h cache write $8/MTok, cache hit $0.20/MTok, output $20/MTok.
  238×4e-6 + 28,975,169×0.2e-6 + 328,971×8e-6 + 192,938×20e-6 = 0.001 + 5.795 + 2.632 + 3.859 = $12.29
Measured / estimated / unavailable, with reasons: measured from session usage metadata for segment 2; segment 1 unavailable (log not accessible)

Blender MCP server/tool namespace actually used: blender-opus55-low (mcp__blender-opus55-low__*, `uvx mcp-for-blender --port 9877`); after the MCP tool disconnected, the same addon socket on localhost:9877 was driven by tools/bl.py (execute_code)
Blender host: localhost
Blender port: 9877
Blender master file: Opus55ForzaLowEffort.blend
Verified full path of master file: W:\YouTube\Opus 5.5 Effort Test\1. Opus 5.5 Forza Low Effort\1.-opus-5.5-forza-low-effort\Opus55ForzaLowEffort.blend (bpy.data.filepath, read-only check)
Approximate number of major Blender assets created: 50 (16 vehicles + 34 kit/nature/building assets)
```
