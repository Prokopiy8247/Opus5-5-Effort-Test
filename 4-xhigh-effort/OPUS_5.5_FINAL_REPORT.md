# VALORIA: Open Road Festival — final report (Claude Opus 5.5, effort xhigh)

An original open-world arcade-sim racing game in the spirit of Forza Horizon 5, built in Godot 4.7.2
(Forward+, Jolt Physics, GDScript) with every important 3D asset authored procedurally in Blender
through the MCP connection on `localhost:9880`. Forza Horizon 5 served only as a mechanics/scope
reference; nothing from it (names, maps, models, audio, UI art) was used.

## What was built
- **A 4 × 4 km island** with four regions — Verdana Valley (farmland, river, village, castle ruins),
  Pinecrest Highlands (switchback pass, conifer forest, snowy summit), Redmesa Canyons (desert plateau,
  mesas, gravel canyon trail) and Marisol Coast (cliffs, beaches, harbour, lighthouse, wind farm) — plus
  the Valoria Festival Grounds hub.
- **40 km of roads** on 19 roads: the 20.05 km Festival Loop through all regions, the 5.04 km Valoria
  Expressway (dual carriageway with two overpasses), mountain, valley (with tunnel), canyon gravel,
  coastal, farm and dirt roads. Roads are baked into the terrain with grade-limited profiles, banking,
  cuttings and embankments, bridges with piers/abutments, guard rails, reflector posts, road signs and
  village street lamps.
- **10 original Blender cars** with separate wheels, glass, lights, interiors and per-car handling
  Resources, sound profiles and class labels (E–S); paint finishes, stripes, rim colours, six upgrade
  categories and a tuning tab.
- **A project-owned raycast vehicle model** (120 Hz, sub-stepped tyres, gearbox, differentials, aero,
  assists) chosen over `VehicleBody3D` after an automated side-by-side test.
- **Civilian traffic** with six Blender vehicle types on a lane graph (IDM following, give-way at
  junctions, pooled physics/kinematic LOD, density by region/time/console).
- **20 activities**: speed traps, speed zones, drift zones, danger-sign jumps, checkpoint races and a
  20 km time trial, with personal bests, credits and map markers.
- **Presentation**: day/night with stars and moon, five weather states affecting grip, rain/snow,
  lightning, procedural audio (engine synthesis per profile, turbo, shifts, tyres per surface, wind,
  impacts, ambience), tyre smoke/dust/skid marks, rewind, HUD, minimap, full map with GPS, region
  popups, garage, console, debug/benchmark menu and photo mode; save/load with autosave.

## What works / what is partial / what is missing
See `FEATURE_MATRIX.md` for the full table. Summary:
- **Working:** everything listed above, verified in-game and by automated scripts in `tools/qa/`.
- **Partial:** crops are terrain textures (no 3D crops); credits are earned and saved but have no shop.
- **Not implemented:** gamepad (intentionally, at the user's request), race AI opponents, visual damage,
  collectibles/photo spots, fences, culverts, traffic overtaking, parked cars, braking-line assist, rim
  style swapping.

## Known bugs and limitations
- The QA autopilot (used only by tests and the benchmark) can run wide and leave narrow gravel roads at
  speed; the player can always reset with R.
- Synthetic engines: the heavily filtered truck V8 profile can sound an octave high.
- From high aerial views the 2 m terrain grid shows a saw-tooth edge beside steep road shoulders.
- Buildings use box collision; interiors are not modelled.

## Controls
Keyboard + mouse: W/S or arrows throttle/brake (hold brake to reverse), A/D steer, Space handbrake, E/Q
manual shifts, C camera, right-drag free look, B look back, H horn, L lights, R reset, Backspace rewind,
Enter start/abandon race, G GPS to nearest event, M map, F1/Tab garage, F2 debug, ` console, P photo
mode, F12 photo, Esc close. Full table in `DEVELOPMENT.md` §3.

## Run result
- **Standalone Windows build:** `exports/windows/VALORIA.exe` (160 MB, everything embedded; rebuild
  with `tools/export_windows.ps1`). Verified by launching the exe itself with `--selftest`: D3D12 on the
  RTX 5070, 10 cars, 42 Blender kit pieces, 60 structures, 6 traffic types with ~25 cars active, no
  errors or warnings in its log.
- Godot 4.7.2 starts the main scene without script errors; first launch bakes the world (~30 s).
- Player spawns on the Festival Loop; all 10 cars are selectable (garage, console `car <n>`, debug menu)
  and pass the automated drive tests.
- Traffic runs, weather/day-night work, activities complete, save/load round-trips, console commands
  pass their assertions, and the loop soak shows no falls (see Performance).

## Car roster
| # | Car | Class | Layout | Engine sound | 0–100 km/h | Top speed |
|---|---|---|---|---|---|---|
| 1 | Kestrel Hatch R (hot hatch) | B | FWD | turbo I4 | 5.83 s | 270 km/h |
| 2 | Corvana Sedan (family sedan) | D | FWD | I4 | 8.50 s | 230 km/h |
| 3 | Thunderhoof 68 (classic muscle) | B | RWD | cross-plane V8 | 7.51 s | 283 km/h |
| 4 | Solano RS Coupe (sports coupe) | A | RWD | twin-turbo V6 | 5.20 s | 299 km/h |
| 5 | Meridian GT V12 (grand tourer) | S | RWD | V12 | 5.26 s | 331 km/h |
| 6 | Vortex S9 (mid-engine supercar) | S | AWD | flat-plane twin-turbo V8 | 2.80 s | 355 km/h |
| 7 | Rallyx Terra (rally hatch) | A | AWD | rally turbo I4 | 3.67 s | 225 km/h |
| 8 | Ridgeback 4x4 (off-road SUV) | C | AWD | truck V8 | 5.18 s | 248 km/h |
| 9 | Haulstar 2500 (pickup) | D | RWD | truck V8 | 9.37 s | 222 km/h |
| 10 | Aurelia Roadster 58 (vintage roadster) | E | RWD | vintage I4 | 10.66 s | 175 km/h |

Full drive-test table (braking, skidpad, lane change, jump, gravel, handbrake) in `DEVELOPMENT.md` §4.3.

## Map regions
| Region | Highlights |
|---|---|
| Verdana Valley | Festival hub, Bellacqua village (church, shops, houses), two farms (barns, silos), Rocca Vecchia castle ruins, river bridges, expressway diner and fuel station |
| Pinecrest Highlands | 10- and 8-leg switchback ladders, Pinecrest Pass, summit viewpoint with hairpin drift zone, Alpe Rosa chalet hamlet, conifer forest, snow line |
| Redmesa Canyons | Mesas and buttes, gravel Canyon Trail (rally race, jump), Redmesa fuel stop, canyon overlook, cacti |
| Marisol Coast | Sea cliffs, beaches with palms, Porto Lume harbour with boathouses, Capo Faro lighthouse (night beacon), seven-turbine wind farm with spinning rotors |

## Traffic implementation
`scripts/traffic/traffic_manager.gd`: lane graph from baked road samples and junction nodes; pool of
36 vehicles, target ~26 near the player scaled by density × time of day × region; spawning out of
view on weighted edges; IDM car-following (minimum gap 7 m, headway 1.4 s) plus curvature speed
limits; junction give-way and node reservation; physics bodies PD-tracking a lane ghost within
~125 m, kinematic motion to 650 m, despawn beyond; collisions are physical, then the car recovers
or stops and despawns; horn/flash reactions; tractors restricted to farm roads.

## Blender assets
All created with the MCP server `blender-opus55-xhigh` in `Opus55ForzaXhighEffort.blend` (routing
guard on every script) and exported as glTF:
- 10 player cars (`assets/imported/cars/`), 6 traffic vehicles (`assets/imported/traffic/`);
- 42 world-kit pieces (`assets/imported/kit/`), placed as 49 buildings, 11 landmark instances,
  59,007 vegetation instances, bridge piers, signs, lamps and activity props: 10 vegetation pieces with LODs, 13 buildings, 5 landmarks
  (incl. wind turbine rotor), bridge pier and abutment, rail post, reflector post, street lamp, tunnel
  portal, 4 road signs, jump ramp, speed camera, zone banner, race arch.
Builders: `tools/blender/car_builder.py`, `car_specs.py`, `kit_builder.py`, `vgk_common.py`, `run_build.py`.

## Performance notes
Measured with `tools/qa/perf_test.gd` (autopilot with traffic, weather and full dressing) on an
RTX 5070 / Ryzen 7 5700X3D, VSync to a 180 Hz display (the 5.56 ms median is that cap):

| Run | Avg FPS | p95 / p99 frame | Worst frame | Frames > 33 ms | Memory change |
|---|---|---|---|---|---|
| 1920×1080, 10-minute Festival Loop soak | 157.0 | 11.11 / 15.99 ms | 53.8 ms | 24 of 93,742 | +7.8 MB (tree colliders near the car) |
| 1280×720, 3 minutes | 172.5 | 7.78 / 11.18 ms | 38.9 ms | 2 of 30,542 | −2.1 MB |
| 1920×1080, Vortex S9 up to 314 km/h on the expressway | 176.0 | 6.27 / 11.11 ms | 42.4 ms | 3 of 12,675 | +0.6 MB |

No falls through the world in any run; no node or memory leak beyond area-dependent tree colliders.
Techniques: threaded terrain chunks with three LODs and collision only near the car, MultiMesh
vegetation in 256/128 m cells with visibility ranges, pooled traffic with physics/kinematic LOD,
central managers instead of per-node scripts, procedural audio on a worker thread (~1 % of one core for
engine synthesis).

## Claude Opus 5.5 Godot Forza Session Metrics

```text
## Claude Opus 5.5 Godot Forza Session Metrics

Project: Godot 4.7 Forza-style open-world racing game
Effort level under test: xhigh
Run/session identifier: run-20261023-185306-xhigh (Claude Code sessions ff586b9c-15f1-40a9-ac7e-e7da45c013c8 [segment 1] and ffcc7c3f-abfc-42db-8a91-e31552a2c823 [segment 2])
Working-directory full path: W:\YouTube\Opus 5.5 Effort Test\4. Opus 5.5 Forza xhigh Effort\4.-opus-5.5-forza-xhigh-effort
Start timestamp and timezone: 2026-10-23T18:53:06.634+02:00 (Central European Summer Time; UTC 16:53:06.634Z)
End timestamp and timezone: 2026-10-24T01:35:03.583+02:00 (Central European Summer Time; UTC 23:35:03.583Z)
Elapsed wall-clock time (HH:MM:SS): 06:41:56 (measured)
Elapsed minutes: 401.95 (measured; 385.93 excluding the known pause)
Known pauses / resumed segments: segment 1 18:53:06-18:56:49 (earlier session: run dir + Blender helper scripts), pause 18:56:49-19:12:50 (16 min 01 s), segment 2 19:12:50-01:35:03 (one automatic context compaction inside segment 2, no pause)

Requested model: Claude Opus 5.5
Actual model identifier(s): claude-opus-5-5 (every API request in both session logs; effort "xhigh"; fast mode not used)
Input tokens (state whether uncached or inclusive): 878 uncached input tokens (measured)
Cache-read tokens: 200,328,653 (measured)
Cache-write tokens: 2,285,698, all 1-hour TTL; 0 five-minute writes (measured)
Output tokens: 976,871 (measured; includes thinking)
Thinking/reasoning tokens (included / separate / unavailable): included in output tokens; not exposed separately
Deduplicated total tokens: 203,592,100 (measured; sum of the four mutually exclusive categories)
Usage source and observation cutoff: per-response usage metadata in this project's Claude Code session logs (~/.claude/projects/<project>/<session>.jsonl), assistant responses deduplicated by message id (439 responses), entries before the run start excluded, observation cutoff 2026-10-24T01:35:04+02:00
Unmeasured work / limitations: a handful of API requests in the log (about 9, e.g. the context-compaction summarisation call) carry no usage record and are not included; requests made after the cutoff to write this block are not included; no subagents were used

Token-only API-equivalent cost (USD): $77.89 (measured usage x official rates)
Official pricing source, verification date and tier: https://platform.claude.com/docs/en/about-claude/pricing, read 2026-10-24 (~01:20 CEST), standard API pricing (global routing, no batch, no fast mode; full 1M context at standard rates)
Rates and formula used: Opus 5.5 = $4 / MTok input, $5 / MTok 5-min cache write, $8 / MTok 1-hour cache write, $0.20 / MTok cache hit, $20 / MTok output; cost = (878 x 4 + 2,285,698 x 8 + 200,328,653 x 0.20 + 976,871 x 20) / 1,000,000 = 0.0035 + 18.2856 + 40.0657 + 19.5374 = $77.89
Measured / estimated / unavailable, with reasons: time measured from the saved start/end timestamps; tokens measured from the session usage logs (minus the small unrecorded remainder noted above); cost computed from the measured tokens at the rates read on the official page

Blender MCP server/tool namespace actually used: blender-opus55-xhigh (mcp__blender-opus55-xhigh__*)
Blender host: localhost
Blender port: 9880
Blender master file: Opus55ForzaXhighEffort.blend
Verified full path of master file: W:\YouTube\Opus 5.5 Effort Test\4. Opus 5.5 Forza xhigh Effort\4.-opus-5.5-forza-xhigh-effort\Opus55ForzaXhighEffort.blend
Approximate number of major Blender assets created: 58 (10 player cars, 6 traffic vehicles, 42 world-kit pieces)
```
