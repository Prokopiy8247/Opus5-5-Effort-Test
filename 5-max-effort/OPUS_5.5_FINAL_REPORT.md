# OPUS 5.5 Final Report — Ridgeline Festival (Godot 4.7, max effort)

An original open-world arcade-sim racing game in the spirit of Forza Horizon 5: a 4 km × 4 km countryside world with
41 km of roads, a 20.3 km scenic loop, ten Blender-authored cars, civilian traffic, road activities, weather and
day/night, GPS/minimap/world map, photo mode and save/load. Everything 3D was modelled through the verified Blender MCP
connection on `localhost:9881`; no external assets, no Forza/Playground/Microsoft branding.

## Run result

- `Godot_v4.7.2-stable_win64_console.exe --path .` starts without script errors and drops the player at the
  Festival Hub on the Ridgeline Loop. Headless parse/run checks are clean.
- Final validation (`tools/tests/final_check.gd`, real window 1920×1080): **44/44 PASS** — all console commands,
  save/load round trip (car, time, weather, position within 0.2 m), seven weather × time states, traffic running.
- All 10 cars selectable and drivable (garage + console), drive tests pass for every car on its real Blender model.
- The whole road network (25 roads, 40.5 km) was driven end to end by the autopilot (`network_drive`): 0 stuck points,
  0 falls through the world; the 20.3 km loop lap completes (also as the time trial, 11:08.70).
- Activities exercised end to end: speed trap, speed zone, drift zone, danger-sign jump, road race, scenic-loop time
  trial, festival boards (`activities_check`, `activities_full`).
- Performance: 60 s benchmark at 1920×1080 with traffic: avg 160 FPS, p95 10.4 ms, p99 15.3 ms, 2/9143 frames over
  33 ms; memory flat over a full lap.

## What was built

| Area | Summary |
|---|---|
| World | Seeded generator (`tools/bake_world.gd`, ~17 s): 2 m heightmap, 4 regions, river, lake, sea and beaches, slope-limited road profiles with junction cones and vertical curves, cone-cut pass valleys and cuttings with verges, bridges, tunnels, banking, carving, splat/region/road masks, 1 460 props, settlements and landmarks. GPU-displaced terrain with threaded streaming. |
| Roads | 25 roads / 41.2 km: Ridgeline Loop (20.3 km), Sunline Highway (4 lanes), main, mountain (switchbacks, tunnel), village, gravel rally stage, dirt farm and canyon tracks. Markings, shoulders, rails, reflector posts, chevrons, signs, lamps. |
| Vehicles | Custom raycast vehicle on Jolt at 120 Hz: torque curves, gearbox, diff, combined-slip tyres per surface, wet grip, aero, TCS/ESC/ABS/steering assist, braking line, rewind, roll assist, flip recovery. VehicleBody3D comparison documented. |
| Garage | 10 cars with Blender bodies, separate wheels, glass, lights, interiors, handling Resources, engine-sound profiles, class/PI labels; paint (gloss/metallic/matte/pearl, stripes), rims, 18 upgrades, tuning. |
| Traffic | Lane graph, IDM following, junction give-way, overtaking, 6 Blender vehicle types, density by region/time/setting, pooling (42), kinematic/physics LOD, crashes with hazards, horn/flash. |
| Activities | 24 generated activities (6 speed traps, 4 speed zones, 4 drift zones, 4 danger-sign jumps, 4 road races, loop time trial, 30 festival boards) with stars, PBs, credits, notifications, world labels. |
| UI | HUD (speed km/h/mph, tach, gear, assists, surface, region pop-ups, notifications, activity panel), heading-up minimap, world map with fast travel, GPS ribbon, console, garage menu, benchmark/debug menu, photo mode. |
| Environment | Day/night with sun/moon, night-lit windows and lamps, headlights; clear/cloudy/rain/fog/storm with sky, fog, rain, wet roads, audio and grip. |
| Audio | Wavetable engine synth by RPM/load, turbo and blow-off, shifts, pops, tyre squeal per surface, gravel/dirt/grass rumble, wind, impacts, horns, rain, ambience (sea, birds, crickets), activity chimes. |
| Tools/QA | Drive tests, world bake, map render, activity generator, glb inspector, contact sheets, 13 QA scripts (UI, final validation, activities, network drive, ride height, rewind, views, menus, benchmarks). |

## Car roster (all Blender-authored, drivable)

| # | Car | Class | Drive | 0–100 km/h | Top speed |
|---|---|---|---|---|---|
| 1 | Pico Furia R | Hot hatch | FWD | 6.8 s | 228 km/h |
| 2 | Alder Sedan 2.0 | Everyday sedan | FWD | 9.8 s | 205 km/h |
| 3 | Brutus 427 Fastback | Classic muscle | RWD | 7.5 s | 220 km/h |
| 4 | Kaze S Coupe | Sports coupe | RWD | 5.6 s | 262 km/h |
| 5 | Meridian GT V12 | Grand tourer | RWD | 5.1 s | 317 km/h |
| 6 | Volta X9 | Mid-engine supercar | AWD | 2.8 s | 340 km/h |
| 7 | Gravelo RS Rally | Rally hatch | AWD | 4.3 s (gravel 4.8 s) | 204 km/h |
| 8 | Tundrax 4x4 | Off-road SUV | AWD | 7.1 s | 191 km/h |
| 9 | Haulmark P30 | Pickup (open bed) | RWD | 9.2 s | 184 km/h |
| 10 | Libella Spider '58 | Vintage roadster (open) | RWD | 10.6 s | 168 km/h |

## Map regions

Saltwind Coast (west: sea, cliffs, beach, harbour, lighthouse) · Meadowbrook Vale (centre: farmland, river, Mirror Lake,
Millbrook village, castle ruin, festival hub) · Granite Crown Highlands (north: mountain gorge pass, switchbacks, tunnel,
snow line, viewpoint) · Ochre Mesa Canyonlands (east: mesas, canyons, dirt shortcuts, fuel stop, wind farm).
Screenshots: `docs/screenshots/` (world, garage, GPS/map/photo/activity, menus, weather/time, highland pass, map).

## Blender assets

Verified connection: MCP server/tool namespace `blender-opus55-max` (`mcp__blender-opus55-max__*`), host `localhost`,
port `9881`, master `Opus55ForzaMaxEffort.blend` at the verified full path below; original backed up before the first
change. Assets: 10 player cars, 6 traffic vehicles, 51 props (nature 17, settlements 12, landmarks 3, roadside 11,
festival 4, activities 4) — 67 major assets, all built by project-owned kits (`tools/blender/*.py`), inspected with the
MCP `look` tool, exported as glTF to `assets/imported/` and verified in game.

## Traffic implementation

Roads are sampled every 2 m; vehicles live on (road, sample, direction, lane offset) and move kinematically with IDM
acceleration (leader search per lane including the player), curvature-limited desired speeds, give-way at junctions,
branch choices at joins and lane changes on multi-lane roads. Within 75 m they become full physics cars (same vehicle
model as the player, simplified); crashes switch on hazards and stop them, they despawn when unseen. 42 vehicles are
pre-built at load and pooled; far vehicles update at a quarter rate.

## Performance notes

Static world nodes opt out of physics interpolation (measured 5–10 ms per MultiMeshInstance3D add otherwise, growing
with node count), worker threads build vegetation, grass and road meshes, MultiMeshes carry custom AABBs and
visibility ranges, traffic is pooled and LOD'd. Benchmark (60 s, 1920×1080, traffic on, other projects holding the
shared GPU at ~95 % before the run): avg 160 FPS, p95 10.4 ms, p99 15.3 ms, worst 59.7 ms (GPU spike), GPU time
3.8 ms, CPU render 1.6 ms, 1 070 draw calls, 2.0 M primitives, 1.0 GB VRAM; full-lap static memory 250–255 MB.
Earlier samples taken while other jobs saturated the GPU ranged from 18 to 164 FPS; the measured GPU time (3.8 ms) and
frame time (6.2 ms) of the final run leave a wide margin under the 16.7 ms budget of 60 FPS.

## Partial / not implemented

- PARTIAL: biome weather (snow line and surface dust, no regional weather events); credits economy (earned and saved,
  nothing to buy).
- NOT IMPLEMENTED: visual damage, AI race opponents, parked cars/rest areas, gamepad (omitted at the user's request).

## Follow-up (2026-10-25, after the metrics cutoff)

At the user's request the game was exported as a standalone Windows executable:
`build/RidgelineFestival/RidgelineFestival.exe` (141 MB, data pack embedded, custom icon, release template), rebuilt by
`tools/export_windows.ps1`. The exe was tested on its own: world loads in under 1.4 s, all activities load, the basic
screenshot set renders correctly, and a 20 s benchmark at 1920×1080 gave 176 FPS avg, p99 8.8 ms, 0 frames over 33 ms.
The player now spawns 40 m past the scenic-loop time-trial start gate instead of inside its post. This follow-up is not
included in the session metrics below.

## Known bugs / limitations

- The QA autopilot can roll a car when it enters hairpins/gravel at the speed limit (game assists and R recover);
  human drivers brake for the hairpins (braking line shows where).
- Highland cut walls are uniformly steep rock faces; one tree trunk near the festival spawn can block the garage orbit
  camera for a moment.
- Some QA runs print "2 ObjectDB instances were leaked at exit" (harmless).

## Controls

Keyboard + mouse: W/S throttle/brake-reverse, A/D steer, Space handbrake, E/Q gears (manual), H horn, L lights,
R reset, Backspace rewind, C camera, V look back, RMB free look, ` console, F1/Tab garage, F3 debug menu, M map,
P photo mode, F2 HUD, F12 screenshot, Esc close. Full list in DEVELOPMENT.md.

<!-- METRICS -->
## Claude Opus 5.5 Godot Forza Session Metrics

```text
Project: Godot 4.7 Forza-style open-world racing game
Effort level under test: max
Run/session identifier: run-20261023-185330-max; Claude Code session 417a090e-f30c-4f33-b4c4-3714e17336b8 (segment 2) + research subagent agent-ad97d5cda48ef9e8a
Working-directory full path: W:\YouTube\Opus 5.5 Effort Test\5. Opus 5.5 Forza Max Effort\5.-opus-5.5-forza-max-effort
Start timestamp and timezone: 2026-10-23T18:53:30.658+02:00 (Central European time, UTC+02:00) — measured (start_time.txt)
End timestamp and timezone: 2026-10-24T02:22:30+02:00 (UTC+02:00) — measured (end_time.txt)
Elapsed wall-clock time (HH:MM:SS): 07:28:59 (measured; start to end including the pause below)
Elapsed minutes: 449.0 (measured); excluding the known pause: 07:11:08 = 431.1 min
Known pauses / resumed segments: segment 1 18:53:30-18:55:12 (earlier session, wrote start_time.txt only); known pause 18:55:12 -> 19:13:03 (00:17:51, session restarted with the Blender MCP attached); segment 2 19:13:03 -> end (this session, one continuous run with automatic context compaction)

Requested model: Claude Opus 5.5
Actual model identifier(s): claude-opus-5-5 (main session and subagent, from the session logs)
Input tokens (state whether uncached or inclusive): 1,184 uncached input (main 1,006, subagent 178) — measured
Cache-read tokens: 287,894,426 (main 273,764,606, subagent 14,129,820) — measured
Cache-write tokens: 2,769,761 (main 2,217,104 as 1-hour writes, subagent 552,657 as 5-minute writes) — measured
Output tokens: 1,279,435 (main 1,167,978, subagent 111,457) — measured
Thinking/reasoning tokens (included / separate / unavailable): included in output tokens (not exposed separately by the runtime)
Deduplicated total tokens: 291,944,806 = uncached input + cache reads + cache writes + output, 592 API responses deduplicated by message id (main 277,150,694, subagent 14,794,112)
Usage source and observation cutoff: local Claude Code session logs for this project (`~/.claude/projects/W--YouTube-...-opus-5-5-forza-max-effort/417a090e-f30c-4f33-b4c4-3714e17336b8.jsonl` and its `subagents/agent-ad97d5cda48ef9e8a.jsonl`), usage metadata only; last logged response 2026-10-24T00:22:27.070Z
Unmeasured work / limitations: segment 1 (about 2 minutes, two earlier session ids with no transcript on disk) is not included; the few responses after the observation cutoff (writing this block, final commit and message) are not included; the research subagent ran in parallel with the main session (its time is not added to the wall-clock figure)

Token-only API-equivalent cost (USD): $103.67 (main session $95.85 + research subagent $7.82) — computed from measured usage
Official pricing source, verification date and tier: https://platform.claude.com/docs/en/about-claude/pricing, read 2026-10-24 during this session; Claude Opus 5.5 standard (global routing, no batch, no fast mode, no US-only multiplier; long context billed at standard rates per the page)
Rates and formula used: input $4.00/MTok, 5-minute cache writes $5.00/MTok, 1-hour cache writes $8.00/MTok, cache hits/refreshes $0.20/MTok (0.05x input), output $20.00/MTok; cost = (input*4 + cache_write_5m*5 + cache_write_1h*8 + cache_read*0.20 + output*20) / 1,000,000
Measured / estimated / unavailable, with reasons: time measured from start_time.txt/end_time.txt; tokens measured from the session logs (segment 1 unavailable, see above); cost computed from the measured tokens at the official rates (benchmark equivalent, not the user's subscription charge)

Blender MCP server/tool namespace actually used: blender-opus55-max (tools mcp__blender-opus55-max__execute_blender_code, get_scene_info, get_addon_status, look)
Blender host: localhost
Blender port: 9881
Blender master file: Opus55ForzaMaxEffort.blend
Verified full path of master file: W:\YouTube\Opus 5.5 Effort Test\5. Opus 5.5 Forza Max Effort\5.-opus-5.5-forza-max-effort\Opus55ForzaMaxEffort.blend (read back with bpy.data.filepath at 19:15 and again at the end; guarded in every build script)
Approximate number of major Blender assets created: 67 (10 player cars, 6 traffic vehicles, 51 props)
```

