# DEVELOPMENT — Verdant Ridge Festival

Original open-world arcade-sim racing game in Godot 4.7 (Forza Horizon 5 used only as a mechanics/scope reference;
no names, maps, logos, models, audio or UI art are copied).

## Toolchain (verified this session)
| Item | Value |
|---|---|
| Engine | Godot **4.7.2.stable.official.ed1daf0bf**, Forward+, d3d12, **Jolt Physics**, physics **120 Hz** |
| Godot console exe | `W:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe` |
| Language | GDScript, statically typed |
| Blender | 5.2.2 LTS, driven only through MCP server **`blender-opus55-medium`** (`uvx mcp-for-blender --port 9878`, project `.mcp.json`) |
| Blender endpoint | `localhost:9878` |
| Master .blend (verified via `bpy.data.filepath`) | `W:\YouTube\Opus 5.5 Effort Test\2. Opus 5.5 Forza Medium Effort\2.-opus-5.5-forza-medium-effort\Opus55ForzaMediumEffort.blend` |
| Backup before first edit | `backups/Opus55ForzaMediumEffort_original_20261023.blend` (git-ignored) |
| Git | 2.51.1, repo initialised in the project folder |

## Run
**Exported game:** double-click `build\VerdantRidgeFestival.exe` (Windows x86_64, single file, data embedded).
Rebuild it with `powershell -ExecutionPolicy Bypass -File tools\build_windows.ps1` (preset "Windows Desktop" in `export_presets.cfg`, release template 4.7.2).

```
Godot_v4.7.2-stable_win64_console.exe --path "<project>"                 # play
Godot_v4.7.2-stable_win64_console.exe --headless --path "<project>" --import
Godot_v4.7.2-stable_win64_console.exe --path "<project>" -- --qa --qa-mode=shots   # QA screenshots
   modes: shots | drive (--qa-drive=SEC --qa-road=NAME --qa-speed=KMH) | cars [--qa-car=id] | loop [--qa-speed=KMH] | showcase (--qa-pois=a,b --qa-hour=H --qa-weather=W)
Godot_..._console.exe --headless --path . --script res://tools/map_preview.gd       # road stats + qa/screens/map_preview.png
Godot_..._console.exe --headless --path . --script res://tools/make_car_defs.gd     # regenerate data/cars/*.tres
Godot_..._console.exe --headless --path . --script res://tools/vehiclebody_compare.gd
```
`--fresh` (user arg) ignores the save file. QA runs never read the save.

## Architecture (scripts/)
| Area | Files | Notes |
|---|---|---|
| Core | `core/game.gd` (autoload `Game`), `core/input_setup.gd`, `core/save_system.gd` | settings, catalog, signals; Input Map registered in code (keyboard; no gamepad by request); JSON save in `user://savegame.json`, autosave 60 s |
| World data | `world/world_data.gd`, `world/road_layout.gd`, `world/gps_router.gd` | seeded deterministic terrain function, regions, river/lake/sea, road splines (centripetal Catmull-Rom → 4 m samples), elevation smoothing + grade limits, bridge/tunnel flags, banking, spatial grid + 16 m distance field, carving, surface lookup, Dijkstra GPS |
| Streaming | `world/terrain_streamer.gd` | 128 m chunks (33×33 verts, 4 m), WorkerThreadPool generation (heights, normals, colours, collision faces, vegetation transforms), ≤2 uploads/frame, collision only < 300 m, unload > 900 m, far mesh (40 m) discards inside streamed radius |
| Roads | `world/road_builder.gd`, `shaders/road.gdshader` | 128 m road pieces with procedural lane markings (asphalt/concrete/dirt/gravel), junction pads, bridges (slab, parapets, MultiMesh piers), tunnel tubes + portals + lights, guard rails where the verge drops, reflector posts; trimesh collision tagged with `road_surface` metadata |
| Dressing | `world/dressing.gd`, `world/props_placer.gd`, `shaders/grass.gdshader` | per-chunk MultiMesh vegetation with 2 LOD levels + visibility ranges, tinted grass tufts; villages, farms, gas stations, diners, lighthouse, castle, wind farm, harbour boats, speed/chevron/direction signs, street lamps with night lights |
| Sky | `world/sky_weather.gd` | day/night (sun, moon, sky colours, exposure), weather clear/cloudy/rain/fog/storm/snow → cloud cover, fog, light, rain/snow particles, lightning, global `wetness` shader param, tyre grip multiplier; dynamic weather timer |
| Vehicle | `vehicle/car.gd`, `car_def.gd`, `player_input.gd`, `road_autopilot.gd`, `car_audio.gd`, `car_fx.gd`, `shaders/car_paint.gdshader` | see "Vehicle physics" |
| Camera | `camera/chase_camera.gd` | chase near/far, hood, bumper, cockpit; speed FOV/distance; drift-aware heading; camera collision; free look; look back; shake; photo free-cam |
| Traffic | `traffic/traffic_manager.gd`, `traffic_vehicle.gd` | see "Traffic" |
| Activities | `activities/activity_manager.gd` | speed traps, speed zones, drift zones, danger-sign jumps, 3 checkpoint races with 3 AI rivals, 20 km loop time trial, 20 festival boards, PBs |
| UI | `ui/ui_root.gd`, `hud.gd`, `minimap.gd`, `console.gd`, `map_screen.gd` | HUD dial, assists, surface, region popups, toasts, activity panel, telemetry; heading-up minimap; console; garage; tuning/upgrades; debug/benchmark menu; full map + waypoint; photo mode; pause |
| Tools | `tools/*.gd`, `tools/blender/*.py` | QA runner, map preview, car-def generator, VehicleBody3D comparison, Blender car/props builders |

Central managers do the per-frame work (traffic manager drives all vehicles, streamer owns chunks, props placer animates rotors/lamps); per-node `_process` is limited to the player car, camera, HUD and FX.

## Map layout (4.0 × 4.0 km playable, x east / z south)
* **Greenvale Farmlands** (centre/west): rolling hills, field patchwork, river valley with lake, village *Greenvale*, farms, hedgerow lanes.
* **Granite Highlands** (north): ridged peaks to ~270 m, snow line ~240 m, pine forests, switchback passes, a 176 m tunnel on Summit Descent, castle ruin.
* **Ochre Canyon** (east): plateau with terraced mesas, cacti, gravel/dirt trails, wind farm, gas station + diner, *Dustwater*.
* **Azure Coast** (south + west): beaches, cliffs, sea; *Saltmere Harbour* with pier and boats, *Westcliff*, lighthouse, estuary bridge.
* **Road network**: 37 roads, **41.6 km** total, junction graph of 21 nodes; **Grand Festival Loop 20.3 km** (14 roads, every region);
  highways (Valley/Central Highway, Desert Expressway), scenic, mountain (double yellow), concrete, dirt and gravel classes;
  ~3.1 km of bridges/viaducts, one tunnel; long stretches: West Coast Road + Cliffside Climb (~3.0 km), Highland Pass + Summit Descent (~4.3 km), Sunset Straight + Expressway + Seacliff (~4.5 km).

## Vehicle physics — choice and model
**Kept: project-owned raycast vehicle on `RigidBody3D` (Jolt)**. `VehicleBody3D` was prototyped in
`tools/vehiclebody_compare.gd` (same strip, same tick rate); results in "Drive tests". The built-in node exposes only a
single friction-slip value per wheel and no surface/tyre curves, load sensitivity, assists or differential behaviour, and
Godot's docs describe it as not intended for realistic vehicle simulation. The custom model gives full control:
* 4 raycast wheels (exclude self), spring + bump/rebound damping + bump stop, anti-roll bars per axle
* Pacejka-like lateral curve (B per car, C 1.45, E 0.3), load sensitivity, combined friction circle
* engine torque curve (`CarDef.torque_at`), rev limiter, launch clutch, automatic gearbox with load-aware shift points (manual Q/E optional), reverse
* FWD / RWD / AWD split with drive shares; spinning wheels when traction is exceeded (TCS off) and locking when braking (ABS off)
* aero drag area solved from peak power + design top speed; downforce split front/rear
* steering lock reduced with speed, Ackermann, steering assist (counter-steer toward velocity), ESC yaw control + outer-wheel braking, ABS, TCS, handbrake (rear lock → drift)
* surface grip/drag/bump tables (asphalt, concrete, dirt, gravel, grass, sand, snow, rock) + per-car loose-surface grip + weather grip / wetness
* air control + landing stabiliser, low-speed yaw damping, continuous collision detection, impact detection (damage, shake, sound)
* reset to nearest road (R / console), fall-through safety net (tunnel-aware)
Data per car is a `CarDef` `.tres` in `data/cars/` (generated by `tools/make_car_defs.gd`).

## Traffic
Lane graph = road splines (one lane per direction, right-hand traffic, offset ±lane/2) joined at junction nodes.
Per vehicle: IDM car-following (leaders: same-lane vehicles and the player), curve speed from look-ahead curvature,
junction slow-down + give-way (occupancy per node, 5 s deadlock breaker), random weighted route choice at nodes,
U-turn at dead ends, overtaking a stopped obstacle when the oncoming lane is clear, horn + headlight flash when blocked.
Pool of 40 `TrafficVehicle` (`RigidBody3D` frozen kinematic), max 34 active × density (console/time of day/region).
Spawn 170–720 m from the player, never inside the view within 450 m; despawn > 900 m or out of view. LOD: < 160 m collision
on + every tick, further: no collision, quarter-rate updates. Hard hits turn a vehicle dynamic ("wreck"), it is recycled
when out of view after 25 s. Types: small car, van, pickup, lorry, bus, tractor (farm/dirt roads), plus the sedan model.
~20 parked cars around settlements and gas stations.

## Blender workflow
`tools/blender/car_builder.py` (parametric lofted bodies, wheel-arch booleans, separate greenhouse glass, wheels with
pivot at axle centre, brakes, lights, interior + steering wheel) + `car_specs.py` (10 player + 6 traffic specs) and
`tools/blender/props_builder.py` (36 kit assets). All executed through the MCP `execute_blender_code` with
`exec(open(<project file>).read())`, inspected with `look`, saved to the master file, exported with
`bpy.ops.export_scene.gltf(GLB, use_selection, export_apply, +Y up)` into `assets/imported/{cars,traffic,props}/`.
Collections: `FORZA_GODOT/{Cars,Traffic,Props,Settlements,Roadside,Nature,Collision}` with `CAR_*`, `TRF_*`, `KIT_*`
sub-collections. Godot imports the .glb (mesh LODs auto-generated); materials are re-bound by name in code
(Paint → paint shader, Glass, HeadLight, TailLight, ReverseLight, Rim). Collision for cars = 2 boxes from the body AABB
(no per-triangle collision on vehicles). Forward axis: Blender +Y → Godot −Z, verified in-game.

## Controls (keyboard + mouse; gamepad intentionally not supported)
| Action | Key |
|---|---|
| Throttle / brake-reverse | W / S (↑/↓) |
| Steer | A / D (←/→) |
| Handbrake | Space |
| Shift up / down (manual) | E / Q |
| Camera / look back / free look | C / B / right mouse drag |
| Reset to road | R |
| Lights / horn | L / H |
| Start a race at its gate | Enter |
| Console | ` (~) |
| Garage | Tab or F1 |
| Debug / benchmark menu | F2 |
| Tuning & upgrades | F3 |
| Map (click = waypoint) | M |
| Photo mode | P (F12 photo) |
| Pause | Esc |

## Drive tests (automated, `--qa-mode=cars`, flat 12 km physics strip, 120 Hz, assists on)
| Car | Class | 0–100 km/h | 0–200 km/h | Top speed (design) | 100–0 km/h | Skidpad (60 m) | Roll at >150 km/h |
|---|---|---|---|---|---|---|---|
| Velora Pico GTi (FWD) | C 565 | 7.11 s | 32.09 s | 205 (212) km/h | 37.7 m | 0.74 g | 0.0° |
| Aster Meridian Touring (RWD) | B 610 | 6.54 s | 28.23 s | 221 (232) | 38.4 m | 0.76 g | 0.0° |
| Brannock Thunderhawk 440 (RWD) | A 715 | 6.46 s | 17.87 s | 252 (258) | 40.1 m | 0.75 g | 0.0° |
| Sakura Line Kestrel S (RWD) | A 745 | 5.78 s | 15.17 s | 256 (262) | 35.3 m | 0.77 g | 0.0° |
| Halden Corsair GT (RWD) | S1 845 | 5.81 s | 13.02 s | 309 (318) | 34.8 m | 0.77 g | 0.0° |
| Moretti Fabbrica Vortice R (AWD) | S2 935 | 3.03 s | 7.20 s | 341 (348) | 31.4 m | 0.79 g | 0.0° |
| Nordvik Torrent RS (AWD) | A 760 | 3.98 s | 18.10 s | 220 (226) | 38.0 m | 0.75 g | 0.0° |
| Atlas Ridgeback 4x4 (AWD) | B 625 | 6.11 s | — | 188 (196) | 45.8 m | 0.72 g | 0.0° |
| Brannock Hauler V8 (RWD) | C 585 | 7.44 s | — | 182 (188) | 45.5 m | 0.73 g | 0.0° |
| Lucent Aurelia 1600 (RWD) | D 380 | 8.88 s | — | 163 (168) | 44.4 m | 0.73 g | 0.0° |

Notes: top speed is the value reached in 50 s of full throttle (still rising slightly). Skidpad is measured by a
scripted controller and under-reads the true limit. The first test run exposed a rolling-resistance bug
(speed-proportional drag of ≈2.4 kN at 180 km/h). It was fixed, and launch, braking and grip were then tuned
(raw logs: `qa/drive_tests_run1.txt` before tuning, `qa/qa_log_cars.txt` final).

### VehicleBody3D vs raycast car (`--qa-mode=compare`, same strip, 120 Hz)
| Model | vmax after 40 s | steering step at speed: max roll | max yaw rate | flipped |
|---|---|---|---|---|
| VehicleBody3D (585 kW force cap, 4 wheels, friction_slip 3) | 335 km/h | **27.9°** | **0.00 rad/s** | no |
| Project raycast Car (Vortice R data) | 339 km/h | 0.3° | 0.46 rad/s | no |
VehicleBody3D leaned heavily and barely changed heading at speed. Its single friction value gave no useful
slip/drift behaviour. The raycast model stays planted and responds. **Decision: keep the raycast vehicle.**

### Other automated checks
| Test | Result |
|---|---|
| Grand Festival Loop, autopilot (`loop`) | completed 21.6 km in 1087 s, **0 falls/resets**, memory 178→191 MB (flat), chunk count stable ≈130, 9 autopilot snags (traffic/junction contact; fixed the junction step and tunnel portal afterwards) |
| Tunnel drive (Summit Descent from 1550 m) | passed through to the road end, 168 FPS avg, 0 frames >25 ms |
| Speed traps / zones (`events`) | 5/7 traps scored (2 runs blocked by traffic at junctions), 4/4 zones scored, race start + 3 rivals + checkpoints OK |
| Jumps (`jump`) | 37 m / 52 m / 29 m, 1.0–1.7 s air, all landed upright |
| Drift zones (`drift`) | 5/5 zones started/finished, scores 1169 and 262 where the car slid |
| Console + menus (`ui`) | all 27 console commands answered correctly; garage, debug, tuning, map/GPS, console, telemetry, photo mode screenshots; 1280×720 layout OK |
| Save/load (`save`, with `--qa-save`) | car, paint/finish, upgrades, hour, weather, PBs and position restored exactly |
| Traffic (`drive`, Valley Highway) | 20 active vehicles, 144 spawned / 124 recycled in 70 s, 6 junction yields, 1 crash reaction |

### Performance
Measured on the development machine **while 9 other Godot instances and 7 Blender instances from other projects
were running** (one Blender at ~31,000 CPU-seconds / 10 GB), so the numbers vary a lot between runs:
* typical 120–180 FPS (180 = vsync cap) at 1600×900 window / 1920×1080 viewport; loop average 118 FPS; dips to ~30–60 FPS under the heaviest outside load, at night in villages, or in storms
* game systems per frame (max ms over a 60 s run): car physics 2.3–2.8, traffic 2.4, streamer 3.6–4.7 (chunk upload ≤3.2, collision build ≤4.7), audio ≤14 (only after a long frame), HUD draw first frame 25–30 (glyph cache), others <2
* remaining spikes (>50 ms) are not game code. They were reduced by a shader warm-up pass at boot; outside load is the other main cause
* draw calls ≈450–1100, ≈0.4–0.6 M primitives per frame

## Known limitations
* Damage is a counter only (no deformation). No rewind.
* Gamepad support was removed at the user's request (keyboard + mouse only).
* Only one tunnel. Terrain is a heightfield, so portals rely on removing terrain triangles near the tunnel.
* Traffic overtakes only stopped obstacles. Lanes join at junction pads with occupancy-based give-way (no turn lanes or signals).
* Roads are smooth splines with some regular wiggle in their layout. Long uninterrupted roads reach about 2.4 km per road and 4–6 km across consecutive roads.
* The Blender MCP connection dropped late in the session. All assets had already been built, saved to the master file and exported, and no Blender work was pending.
* Performance numbers come from a heavily shared machine. See "Performance".
