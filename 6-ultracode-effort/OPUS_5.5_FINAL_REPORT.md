# Sunward Roads — Claude Opus 5.5 final report (effort: ultracode)

An original open-world arcade-sim racing game in the spirit of Forza Horizon 5, built on **Godot 4.7.2** (Forward+,
D3D12, Jolt Physics) with every important 3D asset authored in **Blender 5.2.2** through the verified Blender MCP
connection on `localhost:9882` (master file `Opus55ForzaUltracodeEffort.blend`). No external assets, no AI asset
generators, no Forza names or branding. Keyboard + mouse only (gamepad support was dropped at the user's request).

Run it: `Godot_v4.7.2-stable_win64.exe --path "<project>"` (main scene `res://scenes/main.tscn`). Full run, rebuild and
QA commands are in `DEVELOPMENT.md`; the per-feature status is in `FEATURE_MATRIX.md`.

## What was built

- **World:** a 4 × 4 km procedurally generated map (seed 20261023) baked offline into `data/world/`: four regions —
  *Verdant Vale* (farmland, hedgerows, forest, the River Wend, Millbrook village, Wend Farm), *Ironcrest Highlands*
  (alpine pass with hairpins, pine forest, snowy peaks, Highmoor chalets, Old Keep ruins, the Ember Spur tunnel),
  *Ochre Mesa* (desert plateau, mesas, two canyons, Dustwater, Mesa Fuel, the Gale Ridge wind farm) and *Saltwind
  Coast* (cliffs, beaches, Gullhaven harbour, the lighthouse headland, the Estuary Bridge) — plus Mirror Lake and the
  Sunward Festival hub.
- **Roads:** 26 roads, **41.75 km**, including the **Sunward Ring scenic loop of 20.26 km** (12 bridges, one 370 m tunnel,
  minimum curve radius 21.6 m), the 4-lane Sunward Expressway and regional, mountain, street and dirt/gravel/sand
  tracks; long uninterrupted ring stretches between junctions exceed 5 km. Lane markings, shoulders, banking,
  cuttings/embankments, guard rails, bridge parapets and piers, the tunnel tube with lamps, delineators, chevrons,
  junction fillets and direction signs, 19 drainage culverts. 0 unintended crossings; a road collider lies under every
  3 m sample of every road.
- **Driving:** a project-owned raycast vehicle on a Jolt `RigidBody3D` at 120 Hz (chosen over `VehicleBody3D` after a
  documented comparison): suspension with load transfer and anti-roll, slip-angle tyre model with friction ellipse,
  per-surface grip (asphalt, wet asphalt, concrete, wet concrete, dirt, gravel, grass, sand, snow), continuous wet-grip
  loss in rain, engine torque curves, auto/manual gearbox with keyboard-friendly shift logic and direct kick-down,
  FWD/RWD/AWD with LSD, aero, TCS/ABS/STM/steering assist, braking-line assist, hill hold, damage, rewind (15 s),
  respawn/flip reset; chase near/far, hood, bumper and cockpit cameras with free look, look-back and collision.
- **Garage:** exactly 10 original Blender cars with their own handling `Resource`, engine sound profile, performance
  class and paint system (colour, gloss/matte/metallic, stripes/liveries, rim colour), upgrades with stat comparison
  and tuning.
- **Traffic:** lane graph from the baked roads with junction priorities, six Blender traffic vehicle types, physics
  near the player and kinematic movement with colliders further out, pooling, spawn/despawn out of view, density by
  region/time/setting, shunts and hazards, horn/flash, overtaking on the expressway, parked cars, night lights.
- **Activities:** 42 events — 6 speed traps, 4 speed zones, 4 drift zones, 5 jumps, 2 checkpoint races with 3 AI rivals
  each, the Sunward Ring time trial and 20 festival-flag collectibles — with discovery, HUD panels, result banners,
  medals, personal bests and credits.
- **Environment:** day/night cycle with sun/moon/stars, 5 weathers (clear, cloudy, rain, fog, storm) with 25 s blends,
  wet roads/puddles and grip, lightning, regional moods, street/tunnel/car lights; vehicle effects (smoke, dust per
  surface, spray, skid marks, backfire, sparks, dirt).
- **UI:** HUD (speedo/tach, gear, assists, surface, damage, region popups, notifications), rotating minimap, world map
  with waypoint and fast travel (keyboard usable), GPS route line, console with all spec commands, garage menu, debug /
  benchmark menu, pause/settings, photo mode, F12 screenshots, telemetry.
- **Save/load** of car, paint, upgrades, tuning, position, time, weather, personal bests, credits and discoveries.
- **Audio:** procedural engine synthesiser per car and environment sounds, as implemented before the user asked to
  stop audio work on 2026-10-24 (no audio work or audio QA after that; all test runs are muted automatically).

## Run result (final validation, 2026-10-24, 1920×1080)

`tools/tests/final_validation.tscn` (Section 15.3 checklist): **20/20 PASS** — the player spawns in a car on a road;
the console works (`car`, `time`, `weather`, `traffic`, `tp`, `assist`, `paint`, `respawn`, `help`, `cars`); traffic runs
(18 vehicles); weather changes grip; **all 10 cars are drivable with their Blender model**; save/load returns the car
within 0.01 m. Screenshots of that run: `docs/screenshots/final/` (spawn, traffic, 5 weathers, 4 times of day, all 10
cars).

Final regression suite (all silent): `core_fix_test` 0 failures, `ui_menus_test` OK, `fix2_world_verify` 0 failures,
`fix4_settlements_verify` 43 PASS / 0 failed, `dressing_rock_drive_test` ROCKS_OK, `dressing_far_lod_test` FAR_LOD_OK,
`fix4_vehicle_verify` 0 failures, `env_regression_test` 0 failures, traffic scenarios junction/solid/lights PASS,
`--qa=roadcheck` 0 missing samples, `--qa=teleports` 0 of 30 bad, `fix3_activities_rivals --scenario=race` PASS in 2 of
3 runs (see known bugs). The long loop was driven end to end without falling through the world (performance lap below).

## Quality process

Besides continuous QA by the lead, the work was checked by structured multi-agent passes (details in `PROGRESS.md`):

| Pass | Found and confirmed | Fixed |
|---|---|---|
| Code review (5 finders, 2 adversarial verifiers per finding) | 24 | 24 |
| Playtest round 1 (6 area testers, independent reproduction) | 47 of 48 reported | 47 |
| Playtest round 2 | 39 of 39 | 39 |
| Playtest round 3 (incl. the Blender world props and performance) | 29 of 30 | 29 |

All fixes were verified in real runs of the game; many became permanent regression scenes (QA table in
`DEVELOPMENT.md`).

## Known bugs and limitations

- In rare runs a race rival still touches the player once (1 contact in 1 of 3 final race regression runs).
- Buildings on slopes keep their ground floor level with the uphill side, so on the downhill side up to ~2.3 m of
  foundation shows (no steps).
- 8 of 92 junction direction signs are omitted because every candidate spot is on or beside a bridge; Seabreak Diner
  has no lamp posts (too close to the water).
- Traffic overtakes only on the 4-lane expressway (no overtaking through the oncoming lane on two-lane roads); no
  parked cars at the fuel stations; no photo spots / hidden cars; no occlusion culling (not needed for the budget).
- Sea water is a flat plane without shoreline wave geometry.
- Gamepad support and any further audio work were dropped at the user's request.
- Frame-time numbers from the QA tools use the process delta (saturates at ~85 ms); see `DEVELOPMENT.md`.

## Controls (keyboard + mouse)

| Action | Key |
|---|---|
| Throttle / brake-reverse / steer | W / S / A D (or arrow keys) |
| Handbrake | Space |
| Gear up / down (manual gearbox) | E / Q |
| Horn / headlights | H / L |
| Reset to road | R |
| Rewind (hold) | Backspace |
| Camera cycle / look back / free look | C / B / hold right mouse button + drag |
| Console | ` (backtick) or F10 |
| Garage menu | F1 or Tab |
| Debug / benchmark menu | F2 |
| Map | M |
| HUD / telemetry | F3 / F4 |
| Photo mode / screenshot | P / F12 |
| Pause | Esc |

## Car roster (all Blender-authored, measured by `tools/tests/drive_test.tscn`, flat asphalt, assists on)

| Car | Type | Drive | 0-100 km/h | Top speed | 100-0 m | Skidpad |
|---|---|---|---|---|---|---|
| Kestrel R4 | compact hot hatch | FWD | 6.03 s | 242 km/h | 43.3 | 0.97 g |
| Aurelia Saloon | mid-size sedan | FWD | 8.00 s | 215 km/h | 47.9 | 0.85 g |
| Brute 68 | classic muscle fastback, V8 | RWD | 6.43 s | 229 km/h | 45.6 | 0.85 g |
| Sora S2 | compact sports coupe | RWD | 5.29 s | 255 km/h | 39.7 | 1.00 g |
| Castellan GT | front-engine V12 grand tourer | RWD | 4.85 s | 319 km/h | 38.2 | 1.03 g |
| Vortex X | mid-engine supercar | AWD | 2.55 s | 346 km/h | 39.1 | 1.13 g |
| Granite RS | rally coupe-hatch, turbo | AWD | 3.97 s | 220 km/h | 51.6 | 0.84 g |
| Ridgeback SX | off-road SUV, straight-six | AWD | 5.61 s | 205 km/h | 56.0 | 0.73 g |
| Hauler 2500 | full-size pickup, turbo-diesel V8 | 4×4 | 5.45 s | 198 km/h | 50.6 | 0.75 g |
| Lark Roadster | vintage open roadster | RWD | 9.27 s | 164 km/h | 50.5 | 0.76 g |

## Map regions

| Region | Character | Places |
|---|---|---|
| Verdant Vale | rolling farmland, hedgerows, forest, River Wend | Sunward Festival, Millbrook, Wend Farm, Crossroads Diner, Mirror Lake |
| Ironcrest Highlands | alpine pass, switchbacks, pine forest, snowy peaks | Highmoor, Ironcrest Pass viewpoint, Old Keep Ruins, Ember Spur tunnel |
| Ochre Mesa | desert plateau, mesas, canyons, dirt shortcuts | Dustwater, Mesa Fuel, Gale Ridge Wind Farm, Redwall Canyon |
| Saltwind Coast | sea cliffs, beaches, harbour, long bridge | Gullhaven, Saltwind Lighthouse, Estuary Bridge, Seabreak Diner, Coast Fuel |

## Traffic implementation

`LaneGraph` builds right-hand lanes, junction connectors, stop lines and priorities from the baked roads (side roads
give way, left turns yield). `TrafficManager` pools the six Blender vehicle types (hatch, delivery van, box lorry,
coach, farm tractor, work pickup): the nearest 12 within 150 m run as full `CarController` physics cars driven by a
pure-pursuit `RoadFollower` with following distance, give-way and obstacle/player/rival braking; cars further out move
kinematically (merged far-LOD meshes, with colliders within 175 m); nothing beyond 750 m. Spawns are weighted by lane-km
outside the view with a forward bias; density = setting × region × night factor; restricted types only use lanes with
an allowed exit. Light taps cause shunts, real crashes a hazard state with recovery or wreck removal; blocked cars honk
and flash; respawning players are placed in a traffic gap. Update cost 0.3–0.8 ms per frame.

## Blender assets

All created with Python/bmesh code run in the verified Blender instance (scripts in `tools/blender/`), visually QA'd
with the MCP `look` tool and EEVEE renders, reviewed by a separate critic pass, saved in the master file and exported
as `.glb`:

- **10 player cars** (`tools/blender/car_kit.py` + one script per car; ~50k triangles each with body, glass, interior,
  steering wheel, four wheels, calipers, light objects and camera/headlight/exhaust sockets) —
  `assets/imported/cars/`, renders in `docs/blender_cars/`.
- **6 traffic vehicles** — `assets/imported/traffic/`.
- **74 kit props**: nature (24: trees, bushes, cacti, rocks, grass, flowers, reeds, hay, logs), roadside (25: signs,
  lamps, poles, fences, walls, hedges, bus stop, barriers, piers, tunnel portal, speed camera, checkpoint arch, flags,
  fuel pump, billboard) and buildings/landmarks (25: cottages, townhouse, farmhouse, barn, silo, chalet, adobe, fuel
  station, diner, church, harbour shed, boathouse, pier, fishing boat, lighthouse, castle ruins, wind turbine tower and
  rotor, water tower, festival stage and tent, viewpoint deck) — `assets/imported/props/`, contact sheets in
  `docs/blender_props/`.

The session's attached Blender MCP tools (`mcp__blender-opus55-ultracode__*`) were used for the setup and the car
garage. After that connection dropped out of the host session, the prop kits were built through
`tools/blender/mcp_call.py`, a stdio client that launches exactly the project's `.mcp.json` server command
(`uvx mcp-for-blender --port 9882`) and calls the same tools; every agent first verified `bpy.data.filepath`.

## Performance (clean run, nothing else running, 1920×1080, traffic 0.6)

QA autopilot over **28.3 km (1.4 laps of the Sunward Ring) in 26 min**: **139 FPS average** (5 s samples: median 142,
5th percentile 88, minimum 79), **10 of 217,225 frames over 33 ms (0.005 %)**, worst frame 88.5 ms (process delta,
saturating measure). Memory 395 MB at start, 428–466 MB after warm-up with no growth over the second lap; node count
stable at 6,800–7,070; up to ~5,900 draw calls and 5.1 M primitives in the densest views. Cold start, from launching
the process until the area around the spawn is streamed, takes ~12.4 s (two runs); within that, settlements are built
in ~0.4 s and dressing is ready in ~0.38 s (kit meshes and collision shapes are pre-merged offline by
`tools/bake_props.tscn`). The 4 km map needs no origin shifting (roads reach 1.86 km from the origin).

## Claude Opus 5.5 Godot Forza Session Metrics

Project: Godot 4.7 Forza-style open-world racing game
Effort level under test: ultracode
Run/session identifier: run-20261023-185356-ultracode; Claude Code session d7ef9fbc-fae7-4e96-8b81-003b0208d2c4 (segment 2; segment 1 was an earlier short session)
Working-directory full path: W:\YouTube\Opus 5.5 Effort Test\6. Opus 5.5 Forza Ultracode Effort\6.-opus-5.5-forza-ultracode-effort
Start timestamp and timezone: 2026-10-23T18:53:56.828+02:00 (Central European Summer Time, UTC+02:00; UTC 2026-10-23T16:53:56.828Z) — measured
End timestamp and timezone: 2026-10-24T22:57:45.915+02:00 (Central European Summer Time, UTC+02:00; UTC 2026-10-24T20:57:45.915Z) — measured
Elapsed wall-clock time (HH:MM:SS): 28:03:49 — measured
Elapsed minutes: 1683.8 — measured
Known pauses / resumed segments: segment 1 18:53:56 → ~18:56 (run directory, Blender backup); gap ~18:56 → 19:13:32 (~17 min, exact length unknown, included in the wall-clock above); segment 2 19:13:32 → end. Wall-clock without that gap ≈ 27:46.

Requested model: Claude Opus 5.5
Actual model identifier(s): claude-opus-5-5 (all 12,605 deduplicated API messages, main session and every subagent/workflow agent; service tier standard, speed standard, inference_geo global)
Input tokens (state whether uncached or inclusive): 25,252 uncached input tokens — measured
Cache-read tokens: 3,352,665,504 — measured
Cache-write tokens: 95,470,773 (5-minute TTL 89,205,292; 1-hour TTL 6,265,481) — measured
Output tokens: 16,693,341 — measured
Thinking/reasoning tokens (included / separate / unavailable): 8,303,520 — included in the output tokens above (from usage.output_tokens_details)
Deduplicated total tokens: 3,464,854,870 (uncached input + cache write + cache read + output) — measured
Usage source and observation cutoff: local Claude Code transcripts of this project only (%USERPROFILE%\.claude\projects\W--YouTube-Opus-5-5-Effort-Test-6--Opus-5-5-Forza-Ultracode-Effort-6--opus-5-5-forza-ultracode-effort\: d7ef9fbc….jsonl and its 258 subagent/workflow transcripts; b6a582df….jsonl contains no API calls), `message.usage` of assistant records, deduplicated by message id; observation cutoff 2026-10-24T20:59:46Z. Split: main session 416,288,722 tokens (731 messages), subagents/workflows 3,048,566,148 tokens (11,874 messages).
Unmeasured work / limitations: segment 1 (18:53–18:56) is not in any transcript accessible to this session; ~20 main-session API requests (context compaction/summary calls or retries) have request records but no usage record; secondary small-model calls made inside tool implementations (e.g. WebFetch page summaries) are not in the transcripts; tokens spent after the observation cutoff (writing this block, the final commit) are not counted.

Token-only API-equivalent cost (USD): $1,500.65 (main session $151.87, subagents/workflows $1,348.79)
Official pricing source, verification date and tier: https://platform.claude.com/docs/en/about-claude/pricing, verified 2026-10-24, standard API pricing (no batch, no fast mode, no data-residency multiplier; the 1M context window is billed at standard rates)
Rates and formula used: Claude Opus 5.5 — base input $4/MTok, 5m cache write $5/MTok, 1h cache write $8/MTok, cache hit $0.20/MTok, output $20/MTok. Cost = (25,252 × 4 + 89,205,292 × 5 + 6,265,481 × 8 + 3,352,665,504 × 0.20 + 16,693,341 × 20) / 1,000,000 = 0.10 + 446.03 + 50.12 + 670.53 + 333.87 = $1,500.65
Measured / estimated / unavailable, with reasons: time measured from the saved timestamps; tokens measured from the session's own usage records (lower bound because of the unmeasured items above); cost computed exactly from those measured tokens at the verified official rates (token-only, excludes any per-request tool fees; no server-side web searches/fetches were recorded).

Blender MCP server/tool namespace actually used: blender-opus55-ultracode (mcp-for-blender, tools mcp__blender-opus55-ultracode__execute_blender_code / look / get_scene_info / get_addon_status); after that connection dropped out of the host session, the same server command from .mcp.json was driven through tools/blender/mcp_call.py
Blender host: localhost
Blender port: 9882
Blender master file: Opus55ForzaUltracodeEffort.blend
Verified full path of master file: W:\YouTube\Opus 5.5 Effort Test\6. Opus 5.5 Forza Ultracode Effort\6.-opus-5.5-forza-ultracode-effort\Opus55ForzaUltracodeEffort.blend (bpy.data.filepath, checked at the start of every Blender agent)
Approximate number of major Blender assets created: 90 (10 player cars, 6 traffic vehicles, 74 kit props: 24 nature, 25 roadside, 25 buildings/landmarks)
