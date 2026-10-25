# Ridgeline Festival — Development Guide

Original open-world arcade-sim racing game in the spirit of Forza Horizon 5, built with Godot 4.7 and a
Blender MCP asset pipeline. No Forza/Playground/Microsoft content or branding is used.

## 1. Toolchain (verified)

| Item | Value |
|---|---|
| Engine | Godot `4.7.2.stable.official.ed1daf0bf`, Forward+ renderer (D3D12 on Windows 11) |
| Executables | `W:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe` / `..._console.exe` |
| Physics | Jolt Physics, 120 Hz physics ticks, physics interpolation on (moving bodies only) |
| Language | GDScript with static typing (≈10.6 k lines in `scripts/`, ≈7.1 k lines of tools in `tools/`) |
| Blender | 5.2.2 LTS via MCP server `blender-opus55-max` (`uvx mcp-for-blender --port 9881`), host `localhost:9881` |
| Blender master | `W:\YouTube\Opus 5.5 Effort Test\5. Opus 5.5 Forza Max Effort\5.-opus-5.5-forza-max-effort\Opus55ForzaMaxEffort.blend` (path read back with `bpy.data.filepath`, guarded in every build script by `kit_common.guard()`) |
| Backup of the original master | `backups/blender/Opus55ForzaMaxEffort_original_2026-10-23_1913.blend` |
| Git | milestone commits, `.godot/`, `qa_out/`, backups and export outputs ignored |
| Test machine | RTX 5070, Ryzen 7 5700X3D, 64 GB RAM (shared with other projects' Godot/Blender jobs during this run) |

## 2. Running

Standalone game (no Godot needed): double-click `build/RidgelineFestival/RidgelineFestival.exe`.
Rebuild it with `powershell -ExecutionPolicy Bypass -File tools/export_windows.ps1` (uses the installed Godot 4.7.2
export templates and the "Windows Desktop" preset in `export_presets.cfg`; world data `*.bin`/`*.json` are included,
tools, QA output, docs and the Blender master are excluded). From the project with the editor build:

```text
# play (main scene launches straight into free roam at the festival on a road)
Godot_v4.7.2-stable_win64.exe --path .
# with a log
Godot_v4.7.2-stable_win64_console.exe --path .
# fresh start (ignore the save)
Godot_v4.7.2-stable_win64_console.exe --path . -- --fresh
```

Saves: `user://savegame.json` (autosave every 60 s and on quit; console `save` / `load`).

## 3. Controls (keyboard + mouse only — gamepad support intentionally omitted at the user's request)

| Action | Key |
|---|---|
| Accelerate / brake-reverse | W / S (or ↑ / ↓) |
| Steer | A / D (or ← / →) |
| Handbrake | Space |
| Shift up / down (manual gearbox) | E / Q |
| Horn / headlights | H / L |
| Reset to road | R |
| Rewind (hold) | Backspace |
| Camera cycle (chase, chase far, hood, cockpit, bumper) / look back | C / V |
| Free look | hold right mouse button |
| Console | ` (backtick) |
| Garage (cars, paint, rims, upgrades, tuning) | F1 or Tab |
| Benchmark / debug menu | F3 |
| World map (pan/zoom, waypoint, fast travel) | M |
| Photo mode | P |
| Toggle HUD / screenshot | F2 / F12 |
| Close menus | Esc |

Photo mode: WASD move, E/Q up/down, Shift faster, hold RMB to look, wheel = FOV, `[` `]` focus distance,
`-` blur amount, T / Shift+T time of day, Y weather, Enter/F12 screenshot (overlay hidden), P/Esc exit.
World map: left click = GPS waypoint, right click = clear, drag = pan, wheel = zoom, F = fast travel to the hovered
event or landmark.

## 4. Architecture

```text
scenes/main.tscn  -> scripts/main.gd (game root: environment, world, player car, camera, UI, optional systems, save/load)
scripts/core/game.gd            autoload: catalogue, settings, assists, notifications, profiler (prof_begin/prof_end)
scripts/vehicle/                car_controller (raycast vehicle), car_factory (glb -> car), car_definition (Resource),
                                car_tuning, car_materials (paint shader), car_lights, car_fx (smoke/dust), car_audio +
                                audio/engine_synth (AudioStreamGenerator), skid_manager, player_input, rewind_buffer,
                                braking_line
scripts/camera/camera_rig.gd    chase/hood/cockpit/bumper cameras, free look, collision, shake, orbit
scripts/env/environment_controller.gd   day/night, 5 weather presets, wetness, rain/fog/storm, global shader params
scripts/world/                  open_world (streaming roads, water, borders), terrain_streamer (GPU-displaced terrain,
                                threaded collision), road_builder, world_data (baked data access), prop_library,
                                prop_manager (props, smashables), vegetation_manager (threaded MultiMesh chunks + grass),
                                navigator (GPS), autopilot (QA driver), surfaces/surface_def
scripts/traffic/                traffic_manager (lane graph, IDM, junctions, LOD, pooling), traffic_types
scripts/activities/             activity_def (Resource), activity_manager (runtime)
scripts/ui/                     hud, dev_console, garage_menu, debug_menu, minimap, world_map, photo_mode, map_icons, ui_theme
assets/shaders/                 terrain, road, water, sky, foliage (wind), car_paint (clearcoat/flake/pearl/stripes),
                                night_emissive, route (GPS chevrons)
data/                           cars (10 .tres), upgrades (18), surfaces (8), traffic (6), activities (24), world (baked)
tools/                          setup_project, build_data, bake_world, render_map, build_activities, drive_test(+runner),
                                inspect_glb, contact_sheet, tests/* (QA scripts), blender/* (MCP build kits)
```

Data flow: `tools/bake_world.gd` (seed 20261023) writes `data/world/` (2 m heightmap 2001², holes, splat, regions,
road mask, `roads.json` with 2 m road samples, `world_meta.json` with props/settlements/teleports). The game streams
256 m chunks: terrain is a shared grid displaced on the GPU from the height texture, collision is built per chunk on
demand (HeightMapShape3D with holes), road meshes are built on a WorkerThreadPool group task, vegetation chunks are
generated on worker threads and turned into MultiMeshes on the main thread.

## 5. Vehicle physics (custom raycast vehicle) and the VehicleBody3D comparison

Each car is a `RigidBody3D` (Jolt, continuous collision, convex hull from the Blender `Collision_Hull`) with four
suspension raycasts at the wheel pivots exported from Blender. Springs are derived from a natural frequency with
preload so the car sits exactly at the modelled ride height (`tools/tests/ride_height_check.gd`: every car within
±1.5 cm). Tyres use a combined-slip model (normalised slip ellipse) per surface with load sensitivity and wet grip;
drivetrain: torque curve, automatic/manual gearbox with clutch-slip launch, FWD/RWD/AWD with limited-slip behaviour;
assists: TCS (grip-torque cap), ESC (yaw-rate / body-slip limiter), ABS, speed-sensitive steering assist, high-speed
yaw damping, air levelling, roll assist on two wheels, auto flip recovery; aero drag and downforce.

`tools/drive_test.gd -- --cars=1 --proto` drives the same scripted tests with Godot's `VehicleBody3D` configured like
the hot hatch:

| Model | 0–100 km/h | Top speed | 100–0 braking | Lane-change slip |
|---|---|---|---|---|
| Custom raycast vehicle (Pico Furia R) | 6.77 s | 227.7 km/h | 36.1 m | 4.0° |
| VehicleBody3D prototype | 2.5 s | 228.6 km/h | 23.3 m | 0.0° |

VehicleBody3D has no gearbox/torque curve or slip model: launches and braking are unrealistic and it cannot drift or
slide progressively, so the custom vehicle was kept (stable at 340 km/h in the drive tests, drifts recover).

### Drive-test numbers (headless, fixed 120 Hz, real Blender models — `qa_out/drive_tests.json`)

| Car | 0–100 s | 0–200 s | ¼ mile s | Top km/h | 100–0 m | Skidpad g | Lane change km/h | Jump m | Gravel 0–100 s |
|---|---|---|---|---|---|---|---|---|---|
| Pico Furia R (hot hatch, FWD) | 6.77 | 26.32 | 14.95 | 227.7 | 36.1 | 0.88 | 212 | 28.9 | 10.36 |
| Alder Sedan 2.0 (sedan, FWD) | 9.78 | 64.75 | 17.17 | 205.4 | 41.0 | 0.86 | 191 | 29.3 | 11.91 |
| Brutus 427 Fastback (muscle, RWD) | 7.47 | 24.22 | 15.20 | 219.7 | 41.8 | 0.84 | 204 | 30.1 | 13.20 |
| Kaze S Coupe (sports coupe, RWD) | 5.57 | 16.01 | 13.38 | 262.0 | 36.9 | 0.90 | 244 | 29.4 | 9.05 |
| Meridian GT V12 (grand tourer, RWD) | 5.06 | 12.41 | 12.69 | 317.1 | 35.3 | 0.91 | 250 | 29.7 | 8.05 |
| Volta X9 (mid-engine supercar, AWD) | 2.77 | 7.89 | 10.28 | 339.5 | 29.5 | 0.92 | 250 | 29.7 | 5.09 |
| Gravelo RS Rally (rally, AWD) | 4.30 | 25.54 | 12.76 | 204.4 | 37.2 | 0.88 | 190 | 29.0 | 4.76 |
| Tundrax 4x4 (off-road SUV, AWD) | 7.07 | — | 15.16 | 190.7 | 53.0 | 0.77 | 177 | 28.4 | 7.42 |
| Haulmark P30 (pickup, RWD) | 9.21 | — | 16.83 | 184.3 | 54.5 | 0.77 | 171 | 27.6 | 12.20 |
| Libella Spider '58 (vintage roadster, RWD) | 10.64 | — | 17.87 | 167.5 | 43.2 | 0.79 | 156 | 28.8 | 15.95 |

All ten pass the high-speed lane change (stable), jump landing and drift-recovery tests. Note the rally car's gravel
0–100 (4.8 s) versus the coupe (9.1 s), and the SUV/pickup body roll and long braking distances.

## 6. World

- 4 km × 4 km (`half = 2000 m`), 2 m terrain resolution, four regions: **Saltwind Coast** (west: sea, cliffs, beach,
  harbour, lighthouse), **Meadowbrook Vale** (centre/south: farmland, river, lake, village, castle ruin, festival hub),
  **Granite Crown Highlands** (north: mountain pass gorge, switchbacks, tunnel, snow above 500 m, viewpoint),
  **Ochre Mesa Canyonlands** (east: mesas, canyons, dirt shortcuts, fuel stop, wind farm).
- Road network: 25 roads, **41.2 km** (highway, main, mountain, village, gravel, dirt). **Ridgeline Loop** is a
  continuous **20.3 km** scenic loop through all four regions; Sunline Highway (2.9 km, 4 lanes) crosses the vale.
- Road profiles are slope-limited per class (highway 6 %, main 8.5 % (11 % in the highlands), mountain 10.5 %,
  gravel 16 %, dirt 18 %) using the lower slope-limited envelope with junction-height cones, then 50 m vertical
  curves; where a road runs below steep ground the terrain is cut to a 49° cone around the road (two-pass chamfer
  transform), creating pass valleys/cuttings with a 3.5 m verge. Bridges over the river/lake (pillars, rails),
  explicit tunnels with portals and lights, banked corners, lane markings, shoulders, guard rails, reflector posts,
  chevrons, speed/route/curve signs, street lamps.
- `tools/tests/network_drive.gd` drives every road end to end with the autopilot: 40.5 km, 0 stuck points, 0 falls
  through the world (4 autopilot roll-overs at the speed limit in hairpins/gravel, auto-recovered).
- Surfaces with distinct grip, rolling resistance, bumpiness, audio and particles: asphalt, concrete, dirt, gravel,
  grass, sand, snow, rock; wet asphalt via `wetness` × per-surface `wet_grip`. The surface under each wheel comes
  from collider metadata (roads/props) or the baked surface map (terrain).
- 10 settlements/POIs (Millbrook village, Saltwind Harbour, three farms, two fuel stops/diner, Pass Viewpoint,
  Lakeside Hamlet, Festival Hub) and landmarks (lighthouse, castle ruin, wind farm, Mirror Lake); 1 460 baked props.

## 7. Blender pipeline (MCP, `localhost:9881`)

1. Routing verified at the start (`get_scene_info` + `bpy.data.filepath` = master path above); every build script
   calls `kit_common.guard()` which refuses to run unless the open file is exactly the project master.
2. Assets are generated by project-owned Python kits executed through `execute_blender_code`:
   `tools/blender/carkit.py` + `car_specs.py` (player cars: lofted body cage → creased Catmull-Clark → boolean wheel
   arches → open wells for the roadster cockpit / pickup bed → separated glass, interior shell, dashboard, seats,
   steering wheel → projected lights/grilles/plates/panel gaps (BVH projection with surface snapping) → four wheels
   with tyre/rim/disc/caliper and pivots at the axle centre → convex collision hull → gameplay empties
   `CAM_*`, `FX_Exhaust_*`, `LIGHT_*` → UVs → glTF), `traffic_kit.py`/`traffic_specs.py` (6 traffic vehicles),
   `props_kit.py` (51 props).
3. Visual QA with the MCP `look` tool after every build (front/rear/side), fixes, then `kit_common.save_master()`.
4. Export `.glb` (+Y up, Blender +Y forward → Godot −Z) to `assets/imported/{cars,traffic,props}`, then
   `Godot_console.exe --headless --path . --import`; `tools/inspect_glb.gd` checks pivots/points/materials and the
   in-game QA (`--qa=shots --set=garage`, `ride_height_check`) checks scale, ride height and wheel placement.
5. Collections: `FORZA_GODOT/Cars/CAR_<id>`, `Traffic`, `Nature`, `Settlements`, `Landmarks`, `Roadside`, `Festival`,
   `Activities`, `Collision`.

Assets created in Blender: 10 player cars (43–52 k triangles each), 6 traffic vehicles, 51 props
(17 nature, 12 settlement, 3 landmark, 11 roadside, 4 festival, 4 activity) = **67 major assets**.

## 8. Traffic

Lane graph from the road samples (lanes per class, directions, speed limits, junction links from the bake),
IDM car following (including the player), curvature speed planning, give-way at junctions, lane changes/overtaking
on multi-lane roads, 6 Blender vehicle types (compact, pickup, van, lorry, bus, tractor on farm roads), density by
region × time of day × setting (`traffic <0..1>`), spawn 220–650 m from the player outside the view, despawn beyond
820 m, 42 pre-built pooled vehicles, LOD (kinematic far away at quarter rate, full physics within 75 m), crash
reaction (physics, hazard lights, stop, despawn when unseen), horn and headlight flashes.

## 9. Activities, map and assists

24 data-driven activities generated from the road geometry (`tools/build_activities.gd`): 6 speed traps, 4 speed zones,
4 drift zones, 4 danger-sign jumps (Blender ramp beside farm tracks), 4 checkpoint road races, the 20.3 km loop time
trial and 30 festival boards. Driving through a gate starts them; stars (3 targets each, from an ideal speed
profile), personal bests, credits and smashed boards are saved. GPS: A* on the junction graph with an animated ribbon;
heading-up minimap; full world map with fast travel; braking-line assist; rewind.

## 10. Performance

Final 60 s benchmark (`--qa=bench --seconds=60`, 1920×1080, autopilot on the loop, traffic on, other projects'
jobs holding the GPU at ~95 % before the run): **avg 160 FPS (6.2 ms), p95 10.4 ms, p99 15.3 ms, 2 of 9 143 frames
over 33 ms (both GPU-side spikes), worst 59.7 ms**, GPU time 3.8 ms avg (p95 5.9 ms), CPU render submission 1.6 ms,
≈1 070 draw calls, 2.0 M primitives, 1.0 GB VRAM. Largest per-tick system costs: traffic 0.38 ms avg (4.5 ms max),
vegetation 0.05 ms avg (1.5 ms max). A full 20.3 km lap keeps static memory at 250–255 MB with a stable node count.
Key measures: static world nodes opt out of
physics interpolation (adding an interpolated MultiMeshInstance3D cost 5–10 ms and grew with the node count — see
`tools/tests/mmi_cost_test.gd`), worker-thread generation for vegetation/grass/roads, custom MultiMesh AABBs,
visibility ranges, pooled traffic, distance-based traffic update rates, profiler sections printed by `--qa=bench`.
The benchmark measures wall-clock frame times (Godot clamps `get_process_delta_time()`), GPU time of the viewport and
CPU render time. During this run other projects' Godot/Blender jobs kept the shared GPU at 80–98 % utilisation, so
measured FPS are lower bounds.

## 11. Known limitations

- Visual car damage and AI race opponents are not implemented (collision response and auto flip recovery are).
- Traffic has no parked cars or rest areas.
- Credits are earned and saved but there is no shop to spend them.
- The autopilot used for QA can roll a car at the speed limit in hairpins (game assists recover it).
- Highland cut walls are uniformly steep (49°) rock faces; the GPU terrain has one shared material per region blend.
