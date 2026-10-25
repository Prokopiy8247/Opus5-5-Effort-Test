# Velora Roads — Final Report (Claude Opus 5.5, effort: high)

An original open-world countryside racing game in the spirit of festival open-world racers, built in
Godot 4.7.2 with every 3D asset authored through the project's own Blender MCP connection.

## What was built

- **World**: deterministic 4 × 4 km map (seed 51122) with four regions — *Meadowmere Valley*
  (farmland, fields, river, villages), *Granite Crown Highlands* (pine forest, snow line, hairpins,
  tunnel), *Ochre Mesa* (sand, buttes, cacti) and *Saltcliff Coast* (cliffs, beaches, harbour bay).
  **40.5 km of road in 22 roads**: a **20.2 km closed Festival Loop**, a 3.8 km four-lane highway,
  regional roads, lanes, and dirt/gravel/sand tracks. A 400 m-class bay bridge, river bridges with
  piers, one 180 m tunnel with portals and lights, two hairpins, cuttings/embankments, banking,
  guard rails, reflector posts, chevrons, junction and village signs.
- **Driving**: project-owned raycast vehicle on a Jolt `RigidBody3D` at 120 Hz — suspension with
  anti-roll bars, slip-angle tyres with friction circle (power oversteer, lock-up), engine torque
  curves, clutch launch, auto/manual gearbox, FWD/RWD/AWD, downforce/drag, 8 surface types with
  per-tyre-type grip, weather grip, TCS/ABS/STM/steering assist, air control, reset to road.
- **Garage**: exactly 10 original Blender cars (hot hatch, saloon, muscle, sports coupe, GT,
  mid-engine AWD hypercar, rally car, off-road SUV, pickup, vintage roadster) with separate wheels,
  calipers, glass, lights, interior and steering wheel; paint (16 colours × gloss/metallic/matte/pearl,
  rims), six upgrade categories with PI classes, seven tuning sliders.
- **Traffic**: city car, van, box lorry, coach, farm pickup and tractor (Blender), lane following
  with IDM, curve speeds, junction give-way and turns, spawn ring with pooling, physics LOD,
  crash response (dynamic body → stopped obstacle with hazards), honk/flash.
- **World life**: vegetation MultiMeshes per chunk (broadleaf, pine, poplar, umbrella pine, cactus,
  shrubs, rocks), near-player grass, villages with lit windows and street lights, farms, gas station,
  diner, harbour with bobbing boats, lighthouse, castle ruin, spinning wind farm, festival site with
  stage, tents, flags and an arch over the loop.
- **Sky**: day/night cycle, sun/moon, procedural sky with clouds and stars, weather presets clear,
  cloudy, rain, fog, storm (lightning + thunder) driving fog, rain particles, wet surfaces and grip.
- **Activities**: 4 speed traps, 3 speed zones, 4 drift zones, 3 jump ramps (danger signs),
  3 checkpoint races with 3 AI opponents each, the 20 km *Velora Grand Tour* time trial and
  20 collectible festival boards; stars, personal bests, credits.
- **UI**: HUD (speed km/h|mph, tachometer, gear, assists, surface, weather/clock), rotating minimap
  with traffic/events/GPS, full map with click-to-waypoint and Dijkstra GPS line drawn on the road,
  notifications and region popups, developer console, garage, benchmark/debug menu, photo mode.
- **Audio**: fully procedural (engine layers by RPM/load and cylinder count, turbo/blow-off,
  shifts, squeal/gravel, wind, thumps, impacts, horn, birds/sea/wind/rain ambience, thunder,
  tunnel reverb).
- **Save/load** to `user://velora_save.json` (car, paint, upgrades, tuning, position, time,
  weather, settings, personal bests, credits) with 60 s autosave.

## What works (verified this session)
See `FEATURE_MATRIX.md` for the full table. Key verifications:
- Clean start: no script errors; loads in ~2–6 s; spawns on the Festival Loop.
- Drive tests for all 10 cars (numbers in `DEVELOPMENT.md`), plus wet (Kestrel braking 31.4 → 39.9 m,
  skidpad 1.21 → 1.00 g), fully upgraded (0–100 5.2 → 4.2 s, top 241 → 264 km/h) and assists-off
  (Sora braking 29.8 → 34.2 m, gravel 0–60 5.1 → 8.8 s).
- **Full 20 km loop driven end to end** by the autopilot (864 s, avg 83 km/h, never below the road).
- Activities fired in game: speed trap 109 km/h, speed zone avg 156 km/h ★★, drift zone 26° slides
  scored, jump 21.4 m ★, Coast Sprint vs 3 AI finished 1st ★★★, Grand Tour 14:16.5 over 20 checkpoints,
  festival board pickup persisted.
- Traffic: 17–26 active vehicles, junction turns, crash → stopped obstacle.
- Save/load round trip across two separate game processes.
- Screenshots of every key view in `docs/screenshots/` (and the latest full set in `qa_out/`).

## Partial / not implemented
- Partial: VehicleBody3D compared only on paper; manual gearbox and tuning sliders not covered by
  automated tests; procedural audio not verified by listening; credits are earned but upgrades are
  free; no junction-free 5 km stretch (the 20 km loop has side-road junctions every 1–3 km);
  60 FPS target only verified on an idle GPU (see performance).
- Not implemented: damage, rewind, braking line, liveries/stripes, traffic overtaking, parked cars,
  packaged export, gamepad (removed at the user's request mid-session).

## Known bugs
- Branch-road meshes overlap the main road edge at junction mouths (cosmetic).
- Two loop samples at one coastal junction have terrain slightly above the road edge (cosmetic).
- Engine reports some leaked RIDs/ObjectDB instances at process exit (no runtime effect).
- Garage/console/debug panels fixed-size (designed for 16:9; tested at 1600×900 window, 1920×1080 base).

## Controls
Keyboard + mouse only: W/S/A/D or arrows, Space handbrake, E/Q manual shift, C camera, B/Z/X look,
right-mouse drag free look, R reset, L lights, H horn, Tab/F1 garage, F2 debug, F3 hide HUD,
\` console, M map, P photo mode, F12 screenshot.

## Run result
`godot --path .` → loading screen → free roam on the Festival Loop. Headless smoke run:
`[load 100%] Ready`, zero script errors.

## Blender assets
Verified connection: MCP server `blender-opus55-high` → `localhost:9879`, Blender 5.2.2 LTS,
`bpy.data.filepath` = `W:\YouTube\Opus 5.5 Effort Test\3. Opus 5.5 Forza High Effort\3.-opus-5.5-forza-high-effort\Opus55ForzaHighEffort.blend`.
Original file backed up to `backups/` before the first modification. 49 asset collections
(10 cars, 6 traffic vehicles, 33 props/nature/buildings/landmarks/roadside/festival pieces), exported
to `assets/imported/{cars,traffic,props}/*.glb`. Car meshes 25–33k triangles; traffic 9–36k;
props 56–1.7k. Kits are reproducible scripts in `tools/blender/`.

## Car roster
| # | Car | Class / PI | Drivetrain | Power | Top speed |
|---|---|---|---|---|---|
| 1 | Kestrel GTi (hot hatch) | B 655 | FWD | 245 hp | 241 km/h |
| 2 | Arden S4 Saloon | D 470 | FWD | 165 hp | 201 km/h |
| 3 | Brute 69 (muscle) | B 690 | RWD | 430 hp | 238 km/h |
| 4 | Sora Coupe | A 765 | RWD | 320 hp | 261 km/h |
| 5 | Valcourt GT | S1 860 | RWD | 620 hp | 303 km/h |
| 6 | Nyx Strata (mid-engine) | S2 955 | AWD | 860 hp | 339 km/h |
| 7 | Mistral R5 (rally) | A 735 | AWD | 330 hp | 210 km/h |
| 8 | Trailhound 4x4 (SUV) | C 560 | AWD | 300 hp | 188 km/h |
| 9 | Haulmark 2500 (pickup) | D 480 | RWD | 390 hp | 183 km/h |
| 10 | Spatz Roadster (vintage) | D 310 | RWD | 95 hp | 159 km/h |
(Top speeds measured in drive tests.)

## Map regions
Valley (centre/south-east), Highlands (north-west corner, up to ~450 m peaks), Mesa (south-west),
Coast (east, sea beyond x ≈ 1.5 km, harbour bay). Preview: `docs/map_preview.png`.

## Traffic implementation
Lanes from road splines (right-hand traffic, 2 lanes per direction on the highway); frozen-kinematic
bodies moved per physics tick; IDM following with the player as a potential leader; curve speed
limits with braking look-ahead; give-way at the ends of side roads; random turns; dead-end U-turns;
spawn ring 160–650 m outside the camera view, despawn > 820 m, 33-vehicle pool, max 34 active,
density × time of day; collision within 140 m; shadows within 110 m; geometric contact check for
crashes (Jolt does not report contacts for frozen kinematic bodies).

## Performance notes
- Clean measurement (idle GPU, before vegetation/grass): **166 fps average, p99 11 ms**, 90 s autopilot drive.
- Final build with full dressing and traffic, measured while other projects' Godot/Blender
  instances kept this shared RTX 5070 at 99 % utilisation: **73 fps average, p99 32 ms**, worst
  102 ms (start-up). Script time is only ~1.5 ms/frame (instrumented), so the remaining cost is GPU.
- Memory 211 → 220 MB over the 90 s drive; node count stable; no leaked chunk nodes.
- Single-precision is fine at ±2 km; no origin shifting.

## Subagent usage
- 1 research subagent (Claude Sonnet 5.5) wrote `RESEARCH_NOTES.md` (web research on the reference game and Godot docs).
- No other subagents; all Blender work was done by the main agent on the single verified connection.

## Claude Opus 5.5 Godot Forza Session Metrics

```text
## Claude Opus 5.5 Godot Forza Session Metrics

Project: Godot 4.7 Forza-style open-world racing game
Effort level under test: high
Run/session identifier: run-20261023-191202 / Claude Code session c1314d50-1678-4464-a16c-1eb0fae71594
Working-directory full path: W:\YouTube\Opus 5.5 Effort Test\3. Opus 5.5 Forza High Effort\3.-opus-5.5-forza-high-effort
Start timestamp and timezone: 2026-10-23T19:12:02.196+02:00 (Central European Standard Time)
End timestamp and timezone: 2026-10-23T22:31:43.419+02:00 (Central European Standard Time)
Elapsed wall-clock time (HH:MM:SS): 03:19:41
Elapsed minutes: 199.7
Known pauses / resumed segments: none (single continuous segment). An earlier aborted attempt (run-20261023-185251, before this session) is excluded.

Requested model: Claude Opus 5.5
Actual model identifier(s): claude-opus-5-5 (main agent); claude-sonnet-5-5 (research subagent)
Input tokens (state whether uncached or inclusive): 476 (Opus 460 + Sonnet subagent 16) (uncached input only)
Cache-read tokens: 112,894,772 (Opus 112,406,133 + Sonnet 488,639)
Cache-write tokens: 1,574,224 (Opus 1h-TTL writes 1,522,689; Sonnet 5m-TTL writes 51,535)
Output tokens: 581,747 (Opus 564,221 + Sonnet 17,526)
Thinking/reasoning tokens (included / separate / unavailable): included in output tokens (not exposed separately)
Deduplicated total tokens: 115,051,219 (Opus 114,493,503 over 230 deduplicated requests + Sonnet 557,716 over 8 requests)
Usage source and observation cutoff: local Claude Code session log for session c1314d50-1678-4464-a16c-1eb0fae71594 (+ its subagent log), usage fields only, deduplicated by message id; cutoff last logged request 2026-10-23T20:30:58Z (22:30:58 local), read at 22:31:43 local
Unmeasured work / limitations: tokens of the final chat message and any requests after the cutoff are not included

Token-only API-equivalent cost (USD): $46.30 (Opus 5.5 $45.95 + Sonnet 5.5 subagent $0.35)
Official pricing source, verification date and tier: https://platform.claude.com/docs/en/about-claude/pricing, verified 2026-10-23, standard API pricing
Rates and formula used: Opus 5.5: input $4/MTok, 5m cache write $5/MTok, 1h cache write $8/MTok, cache read $0.20/MTok, output $20/MTok; Sonnet 5.5: $2 / $2.50 / $4 / $0.10 / $10. Cost = sum(tokens_category x rate)/1e6 per model, e.g. Opus: 460x4 + 1,522,689x8 + 112,406,133x0.20 + 564,221x20 = $45.95
Measured / estimated / unavailable, with reasons: measured (token counts from the session log; cost computed from them with the official per-token rates)

Blender MCP server/tool namespace actually used: blender-opus55-high (tools mcp__blender-opus55-high__*)
Blender host: localhost
Blender port: 9879
Blender master file: Opus55ForzaHighEffort.blend
Verified full path of master file: W:\YouTube\Opus 5.5 Effort Test\3. Opus 5.5 Forza High Effort\3.-opus-5.5-forza-high-effort\Opus55ForzaHighEffort.blend
Approximate number of major Blender assets created: 49 (10 cars, 6 traffic vehicles, 33 props)
```
