# Sunward Roads — Development notes

Original open-world arcade-sim racing game on long countryside roads, built in Godot 4.7.2 with
project-owned procedural world generation and Blender-authored (via MCP) vehicles and props.
No Forza names, assets, maps or UI artwork are used; Forza Horizon 5 was only a feature-scope reference
(see `RESEARCH_NOTES.md`).

## Toolchain (verified)
| Item | Value |
|---|---|
| Engine | Godot `4.7.2.stable.official.ed1daf0bf`, Forward+, D3D12, Jolt Physics |
| Godot console | `W:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe` |
| Blender | 5.2.2 LTS, driven only through the MCP server `blender-opus55-ultracode` (`.mcp.json`: `uvx mcp-for-blender --port 9882`), tools `mcp__blender-opus55-ultracode__*` |
| Master .blend | `<project>\Opus55ForzaUltracodeEffort.blend` — path verified through a read-only MCP call (`bpy.data.filepath`) before any change; byte-identical backup in `backups/blender/` (SHA-256 `269f49a0…1922`) |
| Git | 2.51.1; repository initialised in the project folder |
| Machine | RTX 5070, Ryzen 7 5700X3D, 64 GB RAM, Windows 11 |

Godot's own `.blend` importer is disabled in project settings (`filesystem/import/blender/enabled=false`): it had
spawned a Blender process to read the master file once during the first `--import`. That was read-only (no change to
the file), but the runtime must never depend on the master `.blend`, so everything goes through exported `.glb`.

## How to run
```
# game
Godot_v4.7.2-stable_win64_console.exe --path "<project>"
# re-import after asset changes (registers new class_name scripts too)
Godot_v4.7.2-stable_win64_console.exe --headless --path "<project>" --import
# after re-exporting a Blender prop kit: re-import, then pre-merge the kit props (runtime merging needs GPU readbacks)
Godot_v4.7.2-stable_win64_console.exe --headless --path "<project>" res://tools/bake_props.tscn
# compile check of every script (prints CHECK_OK n)
Godot_v4.7.2-stable_win64_console.exe --headless --path "<project>" res://tools/check_scripts.tscn
# regenerate data
... --headless --path "<project>" --script res://tools/setup_project.gd     # project settings + input map
... --headless --path "<project>" --script res://tools/make_game_data.gd    # cars/surfaces/upgrades .tres
... --headless --path "<project>" --script res://tools/bake_world.gd        # terrain + roads (~95 s)
# automated tests / QA
... --headless --path "<project>" res://tools/tests/drive_test.tscn --fixed-fps 120 -- --car=all
... --headless --path "<project>" res://tools/tests/vehiclebody_compare.tscn --fixed-fps 120
... --path "<project>" -- --qa=shots --targets="Sunward Festival;Ironcrest Pass" --views=0,1
... --path "<project>" -- --qa=drive --road=ring --speed=110 --minutes=12 --drive-shots=8
... --path "<project>" -- --qa=garage
```
Always wrap tool runs in `timeout`: a script error inside a `--script` SceneTree tool leaves Godot running forever.

## Windows build (exe)
```
Godot_v4.7.2-stable_win64_console.exe --headless --path "<project>" --export-release "Windows Desktop" build/windows/SunwardRoads.exe
```
Needs the 4.7.2 export templates (`%APPDATA%/Godot/export_templates/4.7.2.stable`). The preset (`export_presets.cfg`)
embeds the pack, so `build/windows/SunwardRoads.exe` (~145 MB) runs on its own (no console window; the log is in
`logs/godot.log` under the user-data folder below). `build/` is gitignored.
The world data is read as raw files, so the preset adds `data/world/*` and `data/events/*.json` through its include
filter, and the PNGs in `data/world/` carry `importer="keep"` `.import` files (a `.gdignore` there would leave the
folder out of the export). Player data (settings, saves, logs) lives in `%APPDATA%/Godot/app_userdata/Sunward Roads/`;
test runs (`Settings.test_run`) never write the settings file. QA modes work on the exe too:
`SunwardRoads.exe --audio-driver Dummy -- --qa=teleports` (verified on the exported exe: 30/30 OK). In the exe,
`res://qa_output` resolves next to the exe, so run screenshot/report modes from the editor build instead.

## Controls (Input Map, set by tools/setup_project.gd) — keyboard + mouse only
Gamepad support is intentionally not provided (user decision during development).

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

## Architecture
```
scripts/core      Game (service registry + gameplay API), Settings (user://settings.cfg), SaveGame (user://save.json)
scripts/main      main.gd (builds everything, spawn/respawn/teleport), qa_director.gd (CLI automation)
scripts/vehicle   CarData / SurfaceData / UpgradeData resources, CarController (physics), CarFactory (glb -> car),
                  CarVisuals (paint/lights/steering wheel), CarInput, Tuning (upgrades + tuning -> effective data)
scripts/camera    CameraRig (chase near/far, hood, bumper, cockpit, free look, shake)
scripts/world     WorldLayout (hand-authored layout data), WorldGen (seeded generator), WorldData (baked data runtime),
                  RoadNetwork (roads, junctions, spatial hash), TerrainStreamer, RoadBuilder, World, MapRenderer
scripts/traffic   RoadFollower (lane following driver) + traffic system
scripts/env|ui|audio|fx|activities   see docs/SYSTEM_CONTRACTS.md
data/             cars/*.tres, surfaces/*.tres, upgrades/*.tres, world/* (baked), events, traffic, weather
assets/           shaders (car paint, terrain, road, water, tunnel, ...), imported/*.glb (Blender exports)
tools/            setup/data/bake tools, Blender scripts (tools/blender), tests, workflows
```
Optional subsystems are created by `main.gd` from script paths, so the game runs (degraded) while one is missing.
All cross-system calls go through the `Game` autoload; the binding contract for every subsystem is
`docs/SYSTEM_CONTRACTS.md`, the Blender/Godot asset contract is `docs/ASSET_CONVENTIONS.md`.

## Vehicle physics decision: raycast controller on Jolt RigidBody3D
Prototype comparison (`tools/tests/vehiclebody_compare.gd`, same Kestrel R4 mass/geometry/power, same manoeuvres):

| Metric | VehicleBody3D (typical params) | Project raycast controller |
|---|---|---|
| 0-100 km/h | 2.53 s (no traction/drivetrain model, unrealistic) | 6.02 s |
| Double lane change at 200 km/h, max body roll | 61.4° (nearly rolled over) | 1.2° |
| Lane change max body slip | 0.0° (friction-slip clamp, no slip dynamics) | 4.5° |
| Aero drag / downforce, surfaces, assists, diff | none built in | data-driven |

VehicleBody3D could be tuned further, but it has no gearbox, differential, aero, tyre slip curves or per-surface grip,
and its lateral friction cap makes drifts and high-speed stability hard to control. The project controller
(`scripts/vehicle/car_controller.gd`) runs at 120 Hz in `_integrate_forces`:
- one ray per wheel (start at tyre top at full bump), spring + bump/rebound dampers + progressive bump stop, anti-roll bars
  as load transfer;
- tyres: slip-angle lateral curve (rise to peak, fall to `slide_grip`) and force-request longitudinal model inside a softened
  friction ellipse; wheel spin / lock reduce lateral capacity (power oversteer, handbrake turns); load sensitivity;
  per-surface grip for road vs off-road tyres and wetness (`SurfaceData`);
- engine torque curve (Curve resource), rev limiter, engine braking, auto/manual gearbox with shift cut, smoothed pedal
  demand (keyboard taps read as part throttle) and direct kick-down to the target gear,
  FWD/RWD/AWD with limited-slip split and AWD centre coupling, reverse engagement;
- drag + front/rear downforce, rolling resistance, top-speed governor;
- assists: TCS (torque cap at traction limit), ABS, STM (yaw-rate excess damping), steering assist (speed-sensitive lock +
  counter-steer help), always-on slide catcher above 12° body slip; air control self-righting; CCD; impact detection + damage.

## Drive-test numbers (automated, `tools/tests/drive_test.gd`, flat asphalt, assists on, 120 Hz)
Run 2026-10-24 ~07:30 with every car's final Blender model (wheel positions from the exported JSON) and the final
gearbox logic:

| Car | 0-100 s | 0-200 s | Top km/h | 100-0 m | Skidpad g | 200 km/h* lane change | Jump landing (2.6 m ramp @110) | Gravel 0-100 s | Drift hold s (of 6) |
|---|---|---|---|---|---|---|---|---|---|
| Kestrel R4 | 6.03 | 21.25 | 242.4 | 43.3 | 0.97 | stable, 4.5° @200 | upright, 9.5° max tilt | 9.24 | 0.00 (grip) |
| Aurelia Saloon | 8.00 | 42.14 | 215.3 | 47.9 | 0.85 | stable, 5.3° @185 | upright, 6.9° max tilt | 10.63 | 0.00 (grip) |
| Brute 68 | 6.43 | 20.37 | 228.5 | 45.6 | 0.85 | stable, 5.6° @197 | upright, 9.0° max tilt | 11.88 | 5.24 |
| Sora S2 | 5.29 | 17.53 | 255.2 | 39.7 | 1.00 | stable, 5.0° @200 | upright, 8.6° max tilt | 9.44 | 5.40 |
| Castellan GT | 4.85 | 12.17 | 318.7 | 38.2 | 1.03 | stable, 3.8° @200 | upright, 10.1° max tilt | 9.26 | 5.22 |
| Vortex X | 2.55 | 6.89 | 346.4 | 39.1 | 1.13 | stable, 2.7° @200 | upright, 8.4° max tilt | 4.06 | 0.00 (grip) |
| Granite RS | 3.97 | 18.57 | 219.9 | 51.6 | 0.84 | stable, 6.1° @189 | upright, 10.9° max tilt | 4.63 | 0.81 |
| Ridgeback SX | 5.61 | 42.16 | 205.2 | 56.0 | 0.73 | stable, 6.5° @177 | upright, 5.4° max tilt | 6.02 | 0.00 (grip) |
| Hauler 2500 | 5.45 | - | 198.1 | 50.6 | 0.75 | stable, 6.3° @170 | upright, 2.6° max tilt | 6.13 | 2.19 |
| Lark Roadster | 9.27 | - | 164.0 | 50.5 | 0.76 | stable, 8.3° @141 | upright, 9.3° max tilt | 13.32 | 4.50 |
*or 85 % of top speed for slower cars. Drift hold = seconds within 15-55° body slip during a 6 s scripted drift (assists off);
FWD/AWD-grip cars do not hold power slides by design. Top speeds are the asymptote of a 150 s full-throttle run.
Extra checks in the same run: no gear changes while airborne (all cars); an 80 km/h cruise settles in a high gear
(3rd-6th depending on the gearbox) at 38-48 % of the redline with no gear hunting; queued manual double-taps all
register; releasing rewind at speed resumes in 4th/5th at road-speed rpm (no drop to 1st). After playtest round 2 a
`keyboard` test emulates binary W taps: holding ~100 km/h by tapping causes 0 hold shifts on all 10 cars at 40-58 % of
the redline (it used to hunt 10-26 shifts in 20 s), and flooring from a cruise kicks down straight to the target gear
(one 0.17 s shift cut). Launch, top speed, skidpad and drift numbers above were unchanged by that fix; braking moved by
up to 0.7 m.

## World generation
`WorldGen` (seed 20261023) bakes `data/world/` in ~95 s:
- natural terrain: domain-warped region masks (Verdant Vale farmland, Ironcrest Highlands ridged peaks rising north, Ochre
  Mesa plateau with terraced mesas, Saltwind Coast beaches/cliffs/cove/headland/estuary), river channel with floodplain,
  Mirror Lake basin (level from rim heights), two carved canyons, the Ember Spur ridge (tunnel), natural edge walls;
- roads: hand-authored control points (`WorldLayout.ROADS`) -> centripetal Catmull-Rom -> single-octave meander masked on
  tight curves and switched off inside `NO_MEANDER_ZONES` (hairpins, tunnel) -> 3 m resampling -> terrain profile
  (smoothed, water clearance, junction aprons, grade limit per class, vertical-curve smoothing) -> bridge flags (>12 m above
  ground or over water) and tunnel flags (only inside `TUNNEL_ZONES`) -> banking from curvature (zeroed around junctions);
  child roads snap their ends onto parent roads; while a child overlaps its parent (acute junctions run alongside for
  15-25 m) its heights follow the parent's surface at the nearest point, so no lip forms on either road;
- carving: per road segment, weighted blend of the road height into the terrain with a flat apron and slope-dependent
  falloff (cuttings and embankments), bridge spans only lower terrain under the deck, tunnel portals become holes;
- maps: surface ids (4 m), road distance (4 m), region weights (8 m), minimap image, debug image `qa_output/world_debug.png`.

Current network: **26 roads, 41.75 km**, the **Sunward Ring loop 20.26 km** (12 bridges, the Ember Spur tunnel, no curve
tighter than 20 m radius, max grade 10.3 %), Sunward Expressway (4-lane, 3.6 km), regional/mountain/street roads and
gravel/dirt/sand tracks. `tools/check_crossings.py` reports 0 unintended crossings; `--qa=roadcheck` finds a road
collider within 0.45 m under every 3 m sample of every road (the only exceptions are the three jump ramps placed on
roads on purpose).

Runtime: `TerrainStreamer` splits 4096 m into 32x32 chunks of 128 m with 4 LODs (2/4/8/16 m) built on the
WorkerThreadPool and committed under a 4 ms per-frame budget (work list sorted once per focus update, not per frame),
skirts hide LOD seams, coarse LODs use the minimum height near roads so terrain never covers the asphalt; colliders are
streamed within 230 m of physics focus points (player and physics traffic) as `HeightMapShape3D` (0.5 ms to create)
except the two tunnel-portal chunks, which need a trimesh with holes. Teleports call `World.refocus()` so readiness
checks immediately describe the new location. `RoadBuilder` generates road meshes with procedural markings (`road.gdshader`: rural, highway,
street, dirt/gravel/sand styles; wetness puddles), trimesh colliders tagged with surface metadata, guard rails where
embankments drop, delineator posts, curve chevrons, drainage culverts (pipe + headwalls where an embankment crosses a
dip), junction corner fillets and direction signs, bridge parapets/decks/piers, the tunnel tube with lamps and portals.
Road furniture is built in ~360 m pieces so each piece's visibility range is measured from its own bounds.
Barriers (guard rails, bridge parapets, the tunnel tube) live on physics layer 6: car bodies collide with them, but the
wheel rays only see drivable surfaces, so a wheel that ends up above a barrier after an impact cannot lift the car over it.

**Float precision:** the playable map spans +-2048 m around the origin. At 2048 m a 32-bit float resolves 0.24 mm, three
orders of magnitude below anything visible or relevant to the 120 Hz physics, so no origin shifting is used. Roads reach
up to 1.86 km from the origin; QA laps and screenshots out there showed no visible jitter in the car, camera or terrain.
A far horizon terrain ring (64 m grid out to 8 km) and a sea plane/river/lake water shader complete the view.

## Subsystems (implemented in parallel against docs/SYSTEM_CONTRACTS.md, integrated by the lead)
- **UI** (`scripts/ui/`): `ui_root.gd` builds the HUD (speedo/tach cluster with redline, gear, TCS/STM/ABS lamps,
  surface + damage, region popups, toasts, activity panel + result banner, FPS/coords readout, controls hint),
  rotating circular minimap with vector roads/POIs/activities/GPS route, full world map (pan/zoom, waypoint by click,
  fast travel with fade), A* GPS over the road graph plus a 3D chevron route ribbon, F4 telemetry (g-g plot, per-wheel
  load/slip/surface). Menus: console (` / F10, history, tab completion, all spec commands), garage (cars / paint /
  upgrades / tuning with before/after stats and live preview), debug/benchmark (teleports, time/weather/traffic/assists,
  60 s auto-drive benchmark), pause/settings (graphics, audio, units, save/load, controls), photo mode (free camera,
  FOV/DOF/exposure/roll, time/weather, PNG capture). Keyboard + mouse only.
- **Environment** (`scripts/env/`): custom sky shader (gradient, sun/moon/stars, animated clouds), sun arc + moon light,
  AgX tonemapping, bloom, SSAO, fog with aerial perspective, volumetric fog in fog/storm, 5 weather presets
  (`data/weather/*.tres`) with 25 s blends, rain/snow/dust particles, lightning, wetness (grip via `CarController.wetness`,
  road/terrain puddles, water storminess, wet paint), regional tints, tunnel detection, pooled street/tunnel lamps,
  automatic headlights, quality presets 0-3 (SDFGI measured and left off).
- **Audio** (`scripts/audio/`): threaded engine synthesiser per car profile (firing frequency from rpm x cylinders,
  load-dependent timbre, V8 burble / V12 / flat-4 / diesel-style), turbo spool + blow-off, overrun pops, limiter, shift
  clunks, reverse whine, per-surface tyre squeal/crunch/rumble, wind, suspension thumps, impacts, two-tone horn, rain on
  roof, region ambience beds (birds, wind, cicadas, surf, gulls, crickets), thunder, tunnel reverb. All generated in code.
- **Vehicle effects** (`scripts/vehicle/car_effects.gd`, `scripts/fx/`): tyre smoke, surface-coloured dust, rain spray,
  snow powder, ring-buffer skid marks, exhaust puffs and backfire flames synced to audio pops, impact/scrape sparks,
  dirt build-up and wash-off on the paint, brake-disc glow.
- **Dressing & settlements** (`scripts/world/dressing*.gd`, `settlements.gd`, `prop_library.gd`): per-chunk threaded
  MultiMesh vegetation with visibility ranges and far meshes, biome rules per region, grass ring around the camera,
  pooled trunk/rock colliders, settlements at every POI (437 props, turbines, lighthouse beam, festival lights).
  `PropLibrary` loads the Blender kits and falls back to procedural placeholders until they exist.
- **Traffic** (`scripts/traffic/`): `LaneGraph` built from the baked roads at startup (right-hand lanes, per-road speed
  limits with +-10 % driver variation, curve/crest speed profiles, junction connectors with stop lines and priorities:
  side roads give way, left turns yield to oncoming traffic). `TrafficManager` runs a pool of six vehicle types
  (hatch, van, lorry, coach, tractor on farm roads, pickup) as **full physics** `CarController`s within 150 m of the
  player (max 12, driven by `RoadFollower` pure pursuit with following distance, obstacle/player/rival braking and
  give-way logic) and as **kinematic** merged-mesh visuals out to ~700 m (half-rate updates beyond 350 m); nothing
  beyond 750 m. Promotion/demotion keeps position, heading, speed and gear. Spawns happen 250-650 m away, outside the
  view (or hidden by terrain / > 520 m), density = 30 x setting x region factor x night factor, capped at 9 vehicles/km.
  Crashes put a car into hazard mode (brake lights blinking), then it crawls back to its lane or becomes a wreck that
  despawns out of view; blocked cars honk and flash; light taps only cause a shunt (straight-line braking), not a spin.
  Parked cars line the village streets and follow their slope. Lane changes overtake on the 4-lane expressway, also
  around a stopped player. Spawns are weighted by lane-km with a forward bias and recycle far cars; restricted types
  (tractor, lorry, coach) only use lanes from which an allowed exit exists. Kinematic cars within 175 m carry colliders;
  the nearest 12 within 150 m run physics. Lights follow `lights_needed()` and tunnels. A respawned player is placed in
  a gap and approaching traffic makes way. Update cost 0.3-0.8 ms per frame.
- **Activities** (`scripts/activities/`): 40 events placed on the network by `EventPlanner` (`tools/make_events.gd` ->
  `data/events/events.json`): 6 speed traps, 4 speed zones, 4 drift zones (chains, combo, banking), 3 jump ramps with
  long-jump scoring, 2 checkpoint road races with 3 AI rivals (grid countdown, ordered checkpoints, wrong-way / missed
  checkpoint handling), the 20.26 km Sunward Ring time trial (13 checkpoints) and 20 festival-flag collectibles.
  Started by driving through the start gate; HUD panel, result banner with medals/stars, personal bests and credits
  (saved). Respawning during an event returns the car to that event's road. Race rivals plan corners, pass in the travel
  half, recover out of view when they leave the route and get terrain colliders far from the player; races and zones
  freeze while a menu is open; rewind is off during races and cancels a zone/jump attempt.

## QA tooling
All test launches are silent: `Settings.test_run` is set when Godot is started with a test scene, a `--script` tool or a
`--qa` mode, and the master bus is then muted (a normal launch of the game keeps its sound). `--audio-driver Dummy`
can be added to any command as well.

| Tool | Purpose |
|---|---|
| `tools/check_scripts.tscn` | compile check of every script (`CHECK_OK n`) |
| `tools/tests/drive_test.tscn` | automated drive tests (table above) |
| `tools/tests/vehiclebody_compare.tscn` | VehicleBody3D vs raycast controller |
| `tools/check_crossings.py` | finds unintended at-grade road crossings in the baked network |
| `-- --qa=roadcheck` | raycasts every road sample against the road colliders; grade/radius stats |
| `-- --qa=teleports` | teleports to every target and checks the car settles upright on a road |
| `-- --qa=drive --road=ring ...` | QA autopilot lap with FPS / frame-time / memory / node logging |
| `-- --qa=spot --road=<id> --s=a,b` | screenshots at arbitrary road positions |
| `-- --qa=shots / garage` | screenshots at targets / of every car (chase + cockpit) |
| `tools/tests/core_fix_test.tscn` | in-game regression checks for the review fixes (menu hold, tunnel rebuild, headlights, rewind, g spike, dirt, look-back, streamer readiness, braking line) |
| `tools/tests/final_validation.tscn` | Section 15.3 checklist: spawn on road, console, traffic, weather/time, all 10 cars drivable with their Blender model, save/load (`-- --shots=<dir>` for screenshots) |
| `tools/tests/stuck_probe.tscn` | vehicle diagnostics: standing starts with per-wheel logs, barrier impacts, race start sequence |
| `-- --qa=culverts` | lists and photographs the procedural culverts |
| `tools/tests/fix2_world_verify.tscn -- --only=forest,river,verge,sky,tunnel,kerb,mirror,lamps` | world regression checks from the playtest fixes |
| `tools/tests/fix2_ui_verify.tscn -- --part=<part>` | UI regression checks (benchmark, tach, maps, units, paint, console, GPS, banners) |
| `tools/tests/env_regression_test.tscn -- --env-test=all` | tunnel lighting / dry tunnel / dust / lightning checks |
| `tools/tests/fix2_activities_{ramps,grid,jumproll,discovery}.tscn` | jump ramps both directions, race grid on the road, roll-off jumps, discovery |
| `tools/tests/traffic_test.tscn -- --scenario=merge|solid|lodswap|lights|parked|overtake|climb` | traffic regression scenarios (in addition to junction/ring/expressway/block/crash/sweep) |
| `tools/tests/fix3_activities_rivals.tscn -- --scenario=race|tunnel|overlay|rewind|units|jump` | race rivals (corner planning, passing, recovery, tunnel), overlay freeze, rewind rules, imperial units, jump result |
| `tools/tests/drive_test.tscn -- --car=all` (incl. `keyboard`) | handling numbers plus a keyboard-throttle gearbox check (binary W taps: no gear hunting) |
| `tools/bake_props.tscn` | pre-merges the Blender kit props and their trimesh collision shapes |
| `tools/tests/fix4_settlements_verify.tscn -- --only=data,staticgap,colgap,ruin,props,fuel,signs,lamps,shots` | settlement colliders match the visible meshes, fuel ramps, signs off the road, lamps |
| `tools/tests/dressing_far_lod_test.tscn` / `dressing_rock_drive_test.tscn` | forest far-LOD transition (FAR_LOD_OK), rock/cactus colliders when driven into (ROCKS_OK) |
| `tools/tests/fix4_vehicle_verify.tscn -- --part=brakeline|downshift|reverse` | braking line at junctions, over-rev downshift refusal, reverse limiter |
| `tools/tests/fix4_ui_shots.tscn -- --part=f12|hidden|photo`, `fix4_ui_pipewarm.tscn -- --start=festival|seabreak|coastfuel [--nowarm]` | async screenshots, pipeline warm-up (first-sight stalls) |
| subsystem tests | `tools/tests/ui_*`, `fx_*`, `audio_*`, `env_*`, `dressing_*`, `traffic_*`, `activities_*` |

## Blender workflow
See `docs/ASSET_CONVENTIONS.md`. Cars are generated by `tools/blender/car_kit.py` (parametric loft body builder +
wheels/interior/lights/sockets helpers) driven by one script per car in `tools/blender/cars/`, executed inside the
verified Blender instance through `execute_blender_code`, visually checked with the MCP `look` tool and hero renders
(`docs/blender_cars/*.png`), saved into the master file and exported as `.glb` to `assets/imported/cars/` with a JSON
of measured dimensions in Godot coordinates. Godot builds the drivable car at runtime from the glb (`CarFactory`).
`tools/blender/mcp_call.py` is a stdio client for the same MCP server (it launches the `.mcp.json` entry,
`uvx mcp-for-blender --port 9882`, and calls `execute_blender_code` / `look` / `get_scene_info`); it was used for the
prop kits after the host session lost its attached connection to that server.

## Performance (final clean run, 1920x1080, traffic 0.6, nothing else running)
QA autopilot over 28.3 km (1.4 Sunward Ring laps, 26 min): 139 FPS average, 5 s samples median 142 / p5 88 / min 79,
10 of 217,225 frames over 33 ms, memory 395 MB at start and 428-466 MB after warm-up without growth, 6,800-7,070
nodes, up to ~5,900 draw calls. Cold start to a streamed spawn area ~12.4 s. Log: `qa_output/final_perf_lap.log`
(qa_output is not committed).

## Known limitations (living list)
- Sea level water is a flat plane (no shoreline wave geometry).
- Race rivals are good but not flawless: in rare runs a rival still touches the player once (1 contact in 1 of 3
  `fix3_activities_rivals --scenario=race` runs in the final regression).
- Buildings on slopes keep their ground floor level with the uphill side, so on the downhill side up to ~2.3 m of
  foundation shows (e.g. a Highmoor chalet door about 1.2 m above the grass, without steps).
- 8 of 92 junction direction signs are omitted because every candidate spot is on or beside a bridge.
- Seabreak Diner has no lamp posts (both candidate spots are too close to the water).
- The QA autopilot (not the player) occasionally needs its stuck-recovery in dense traffic.
- The QA tools' frame-time numbers use the process delta, which saturates at about 85 ms; longer stalls need
  wall-clock measurement (see `fix4_ui_pipewarm.tscn`).
- Gamepad input and any further audio work were dropped at the user's request.
