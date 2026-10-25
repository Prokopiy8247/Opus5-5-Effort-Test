# Feature Matrix — Ridgeline Festival

Status values: `WORKING` (functional in-game path exercised during this run), `PARTIAL`, `NOT IMPLEMENTED`.
"QA" names the script or check that exercised the feature (`tools/tests/*`, `--qa=shots` sets, drive tests).

## Game flow, world and roads

| Feature | Status | Notes |
|---|---|---|
| Launch straight into free roam in a car on a road | WORKING | Spawns at the Festival Hub on the Ridgeline Loop; `--fresh` ignores the save. |
| Original title and branding | WORKING | "Ridgeline Festival"; no Forza/Playground/Microsoft names, logos or assets. |
| 4 km × 4 km world | WORKING | 4000 × 4000 m, 2 m heightmap; borders with invisible walls. |
| Four distinct regions | WORKING | Saltwind Coast, Meadowbrook Vale, Granite Crown Highlands, Ochre Mesa Canyonlands (QA `world` set, region pop-ups). |
| 40–60 km of connected roads | WORKING | 25 roads, 41.2 km; junction graph used by traffic and GPS. |
| Continuous scenic loop ≥ 20 km | WORKING | Ridgeline Loop 20.3 km driven end to end by the autopilot (`network_drive`, avg ~100 km/h). |
| Long uninterrupted stretches (5 km+) | WORKING | The loop is one continuous road through all regions (junctions only branch off it). |
| Road classes and construction | WORKING | Highway (4 lanes, median), main, mountain, village, gravel, dirt; markings, shoulders, banking, guard rails, reflector posts, chevrons, signs, lamps. |
| Roads follow terrain (cuttings/embankments), drivable grades | WORKING | Slope-limited profiles (≤ 6–18 % by class), 50 m vertical curves, cone-cut pass valleys with verges; 40.5 km driven with 0 stuck / 0 falls. |
| Bridges and tunnels | WORKING | River/lake bridges with pillars; explicit tunnels with portals, lights and terrain holes (loop tunnel driven through). |
| Intersections usable by traffic | WORKING | Junction give-way and branch choices in the traffic manager. |
| Surface types with distinct physics/audio | WORKING | Asphalt, concrete, dirt, gravel, grass, sand, snow, rock + wet asphalt (wetness × wet_grip); per-wheel surface from colliders/surface map. |
| Settlements and points of interest | WORKING | Village, harbour, 3 farms, 2 fuel stops/diner, viewpoint, hamlet, festival hub; lighthouse, castle ruin, wind farm, lake. |
| Nature and dressing | WORKING | Trees, bushes, rocks, cacti, grass, wheat, flowers, hay bales (threaded MultiMesh chunks, visibility ranges, wind shader). |
| Smashable roadside props | WORKING | Signs, posts, fences, hay bales, festival boards break into debris. |
| Terrain/road chunk streaming | WORKING | 256 m chunks, GPU-displaced terrain, threaded road meshes/vegetation/grass, on-demand collision; memory flat over a full lap (250–255 MB). |

## Sky, weather, time

| Feature | Status | Notes |
|---|---|---|
| Day/night cycle with car and street lights | WORKING | Sun/moon, night emissive windows/lamps, headlights with spot lights (QA `final_check` 10.5/18.6/22.5 h). |
| Weather: clear, cloudy, rain, fog, storm | WORKING | Sky, light, fog, rain particles, wet road look, audio (QA `final_check`). |
| Weather affects grip | WORKING | Tyre μ × per-surface wet grip by wetness (rain/storm 1.0, fog 0.35). |
| Biome weather (desert dust storms, snow at altitude) | PARTIAL | Snow-capped terrain above the 500 m snow line and dust kicked up on dirt/sand; no region-specific weather events. |

## Driving

| Feature | Status | Notes |
|---|---|---|
| Custom raycast vehicle on RigidBody3D (Jolt, 120 Hz) | WORKING | Chosen over VehicleBody3D (comparison in DEVELOPMENT.md). |
| Throttle, brake/reverse, handbrake, speed-sensitive steering | WORKING | Drive tests + manual play. |
| Engine RPM/torque curve, automatic and manual gearbox | WORKING | Auto by default; `assist auto off` + E/Q for manual. |
| FWD/RWD/AWD with differential behaviour | WORKING | Per-car drivetrain, LSD lock, AWD split. |
| Suspension, weight transfer, anti-roll, body roll/pitch | WORKING | Preloaded springs at modelled ride height (ride_height_check). |
| Tyre grip per surface, aero drag/downforce | WORKING | Combined-slip model; drive tests (skidpad 0.77–0.92 g, top speeds 167–340 km/h). |
| Wheel spin visuals, brake/head/reverse lights, horn | WORKING | |
| Dust, tyre smoke, skid marks | WORKING | Per-surface particles, MultiMesh skid marks. |
| Assists: TCS, ESC, ABS, steering assist, auto gearbox | WORKING | Console `assist`, debug menu toggles. |
| Braking-line assist | WORKING | Ribbon ahead of the car coloured blue/yellow/red from curvature and braking distance. |
| Rewind | WORKING | Hold Backspace: 12 s buffer, 2× scrub (rewind_check). |
| Collisions, reset to road, flip recovery | WORKING | R resets, automatic upright after 2.5 s on the roof, roll assist on two wheels. |
| Visual damage | NOT IMPLEMENTED | Bonus item; collisions only affect motion. |
| Automated drive tests | WORKING | `tools/drive_test.gd`: 0–100, 0–200, ¼ mile, top speed, braking, skidpad, lane change, jump, gravel, drift. |
| Cameras: chase, chase far, hood, cockpit, bumper, free look, look back, collision, shake | WORKING | C cycles; RMB free look. |
| Audio: engine synth by RPM/load, turbo blow-off, shifts, tyre squeal per surface, wind, impacts, regional ambience | WORKING | AudioStreamGenerator wavetable synth + procedural SoundBank; ambience cross-fades birds (day, vale/highlands), crickets (night), surf (coast). |

## Garage, customisation

| Feature | Status | Notes |
|---|---|---|
| Exactly 10 distinct Blender-authored cars | WORKING | Hatch, sedan, muscle fastback, coupe, GT, mid-engine supercar, rally hatch, off-road SUV, pickup, open roadster (QA `garage` set). |
| Per car: separate wheels, glass, lights, interior, handling Resource, engine sound profile, class label, paint | WORKING | inspect_glb + garage screenshots; cockpit camera shows interiors. |
| Graphical garage menu (F1/Tab) with stats | WORKING | List, stat bars, Overview/Paint/Upgrades/Tuning tabs (menus_check). |
| Paint: colour, gloss/metallic/matte/pearl, stripes; rim styles/colours | WORKING | Garage + console `paint`/`finish`. |
| Upgrades with gameplay effect | WORKING | 18 upgrades (engine, tyres, suspension, brakes, weight, aero), PI recalculated. |
| Tuning | WORKING | Final drive, brake bias, tyre balance, springs, ARB, aero (garage tab / console `tune`). |
| Photo mode | WORKING | Free camera, FOV, depth of field, time/weather change while frozen, hidden HUD, screenshot (ui_check). |

## Console, menus

| Feature | Status | Notes |
|---|---|---|
| Developer console (`) with cars, car, respawn, tp, time, weather, traffic, speed, fps, assist, paint, reset, help | WORKING | All 30 commands checked by `final_check` (PASS), plus finish, units, pos, save/load, camera, upgrade, tune, photo, event, waypoint, daylength, quit. |
| Benchmark/debug menu (F3) | WORKING | Teleports, car spawn, repair/flip, time, weather, traffic density, assists, FPS/coords, telemetry (menus_check). |

## Traffic

| Feature | Status | Notes |
|---|---|---|
| Lane graph from road splines, directions, speed limits, intersections | WORKING | |
| Following distance (IDM), braking for obstacles incl. the player, corner speeds, give way | WORKING | |
| Overtaking / lane changes on multi-lane roads | WORKING | |
| Six Blender traffic vehicle types | WORKING | Compact, pickup, van, lorry, bus, tractor (farm roads). |
| Density by region/time of day and console | WORKING | `traffic <0..1>`, debug slider (final_check: 30 active vehicles). |
| Spawn/despawn outside view, pooling, simulation LOD | WORKING | 42 pre-built pooled vehicles; kinematic far / physics near / none beyond 820 m. |
| Collision reactions, horn/flash feedback | WORKING | Crashed cars stop with hazards and despawn unseen; horns and flashes at the player. |
| Parked cars and rest areas | NOT IMPLEMENTED | Stretch goal. |

## Activities

| Feature | Status | Notes |
|---|---|---|
| Speed traps | WORKING | 6, camera gates, speed + stars + PB (activities_check). |
| Speed zones | WORKING | 4, average speed over 760 m (activities_check). |
| Drift zones | WORKING | 4, chained drift score with combo multiplier from body slip; autopilot runs scored 289–454 pts (activities_full). |
| Danger signs / jumps | WORKING | 4 Blender ramps beside farm tracks, jump distance (activities_check: 20–31 m runs). |
| Checkpoint road races | WORKING | 4 races: start/finish gates, checkpoint marker + GPS to the next checkpoint, timer, splits; Eastern Valley Dash completed in 0:37.22 (activities_full). |
| AI race opponents | NOT IMPLEMENTED | Stretch goal; races are against the clock and star targets. |
| Time trial on the scenic loop | WORKING | 20.3 km, 20 checkpoints; completed end to end in 11:08.70 (2 stars, +3 000 CR) by the autopilot. |
| Collectibles (festival boards) | WORKING | 30 smashable boards, counted and saved. |
| HUD notifications, stars, personal bests | WORKING | Saved in `user://savegame.json`. |
| Credits economy | PARTIAL | Credits are earned and saved but there is nothing to spend them on. |

## HUD, map, navigation

| Feature | Status | Notes |
|---|---|---|
| Speedometer (km/h / mph), tachometer, gear, surface and assist indicators | WORKING | `units mph`. |
| Region name pop-ups, event notifications | WORKING | |
| Minimap with roads, position and heading | WORKING | Heading-up, zooms with speed, icons, route. |
| Full world map with regions, events, waypoint | WORKING | Pan/zoom, hover info, fast travel (ui_check). |
| GPS route on the road | WORKING | A* over the junction graph, chevron ribbon, minimap/map line. |
| Readable at 1920×1080 and other resolutions | WORKING | QA at 1920×1080, 1600×900, 1280×720. |

## Persistence, input, performance, delivery

| Feature | Status | Notes |
|---|---|---|
| Save/load: car, paint/upgrades/tuning, position, time, weather, settings, bests, credits | WORKING | Round trip verified by final_check (position within 0.2 m). |
| Keyboard + mouse controls via Input Map | WORKING | |
| Gamepad support | NOT IMPLEMENTED | Intentionally omitted at the user's request during the run. |
| 60 FPS target with measured frame times | WORKING | 60 s benchmark at 1920×1080: avg 160 FPS, p95 10.4 ms, p99 15.3 ms, 2/9143 frames > 33 ms (GPU shared with other projects at ~95 %). |
| No hitching / no leaked chunk nodes / no memory growth over a lap | WORKING | Profiled systems ≤ 4.5 ms max per tick; full-lap memory 250–255 MB, node count stable. |
| Packaged Windows build (exe) | WORKING | `build/RidgelineFestival/RidgelineFestival.exe` (single 141 MB file, data embedded, custom icon) via `tools/export_windows.ps1`; tested: screenshots in all weather/time states, 20 s bench 176 FPS avg, 0 frames > 33 ms. |
