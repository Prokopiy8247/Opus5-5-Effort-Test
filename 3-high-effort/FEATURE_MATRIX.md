# Feature Matrix — Velora Roads

Status values: `WORKING` (exercised in game or by an automated in-engine test this session),
`PARTIAL` (implemented but incomplete or not fully exercised), `NOT IMPLEMENTED`.

| Feature | Status | Notes |
|---|---|---|
| Boots straight into free roam on a road | WORKING | Spawn on the Festival Loop ~280 m before the festival arch; `--fresh` QA runs. |
| Original title / branding | WORKING | "Velora Roads", "Velora Festival"; no third-party names or logos. |
| Project-owned raycast vehicle (Jolt RigidBody3D, 120 Hz) | WORKING | Drive-test suite for all 10 cars (`docs/drive_tests_v1.txt`). |
| VehicleBody3D comparison | PARTIAL | Evaluated from docs only (no gearbox/engine, Jolt support undocumented); not prototyped in code. |
| Engine torque curves, clutch launch, auto gearbox | WORKING | Shift logs and 0–100/0–200 numbers in drive tests. |
| Manual gearbox (E/Q) | PARTIAL | Implemented (assist "auto" off); not exercised by an automated test. |
| FWD / RWD / AWD drivetrains | WORKING | Distinct launch/off-road numbers per drivetrain. |
| Suspension, anti-roll, weight transfer, body roll | WORKING | Loads/compression in telemetry; SUV/pickup roll more. |
| Tyre model per surface (asphalt, concrete, dirt, gravel, grass, sand, snow, rock) | WORKING | Gravel/sand 0–60 tests; surfaces from collider metadata + baked surface map. |
| Wet grip from weather | WORKING | Kestrel wet: braking 31.4 → 39.9 m, skidpad 1.21 → 1.00 g. |
| Aero drag/downforce | WORKING | Top speeds match targets; Nyx downforce raises skidpad. |
| Assists TCS / ABS / STM / steering / auto | WORKING | Sora assists-off: braking 29.8 → 34.2 m, gravel 0–60 5.1 → 8.8 s; HUD indicators. |
| Braking-line assist | NOT IMPLEMENTED | Removed from menus so nothing non-functional is offered. |
| Rewind | NOT IMPLEMENTED | Stretch goal. |
| Handbrake drifts | WORKING | Drift-zone QA reached 26° slides. |
| Jump landing stability / air control | WORKING | All cars land the ramp upright. |
| Damage | NOT IMPLEMENTED | Impacts only cause physics response, sound and camera shake. |
| Reset to road (R / console `respawn`) | WORKING | Used by autopilot stuck recovery and console. |
| Anti-tunnelling | WORKING | CCD on; 20 km loop test never below the road surface. |
| Chase / far chase / hood / bumper / cockpit cameras | WORKING | Chase + cockpit verified in screenshots; speed FOV, collision, shake, free look. |
| Engine & world audio (procedural) | PARTIAL | All layers synthesized and driven by RPM/load/slip; not verified by listening. |
| Tyre smoke / dust / spray, skid marks | WORKING | Dust visible in desert screenshots; skid marks MultiMesh ring buffer. |
| Exactly 10 Blender cars | WORKING | Hatch, saloon, muscle, coupe, GT, mid-engine AWD, rally, SUV, pickup, roadster; in-game gallery screenshots. |
| Car parts (wheels with axle pivots, glass, lights, interior, steering wheel, calipers) | WORKING | Wheels spin/steer, lights switch (night screenshot), cockpit interior. |
| Paint (colour + finish), rim colour | WORKING | Garage + console `paint`; saved per car. |
| Stripes / livery | NOT IMPLEMENTED | |
| Upgrades (engine, tyres, suspension, brakes, weight, aero) | WORKING | Fully upgraded Kestrel: 0–100 5.2 → 4.2 s, top 241 → 264 km/h; PI/class updates. |
| Tuning sliders (gearing, pressure, camber, springs, ARB, aero, brake bias) | PARTIAL | Applied to the physics model live; effect not measured by tests. |
| Credits economy | PARTIAL | Earned from events/boards and shown; upgrades are free. |
| Photo mode | WORKING | Free camera, FOV, DOF, time/weather, hidden HUD, F12. |
| Developer console (all required commands) | WORKING | `cars`, `car`, `respawn`, `tp`, `time`, `weather`, `traffic`, `speed`/`fps`, `assist`, `paint`, `reset`, `help` + extras. |
| Garage menu (10 cars, stats, PI class) | WORKING | Screenshots `docs/screenshots/ui_garage_upgrades.png`. |
| Benchmark/debug menu (F2) | WORKING | Teleports, spawn, time, weather, traffic, assists, overlays, repair, photo mode. |
| Telemetry overlay | WORKING | Console `telemetry` / debug menu (RPM, slip, surface, per-wheel loads). |
| 4 regions (valley, highlands, mesa, coast) | WORKING | Distinct terrain, vegetation, colours, region popups. |
| 4×4 km map, 40.5 km of roads, 20.2 km loop | WORKING | Bake log; full loop driven end-to-end by autopilot (864 s). |
| Highway, regional, mountain, lanes, dirt, gravel, sand roads | WORKING | 22 roads; dirt/gravel/sand use loose-surface physics. |
| Lane markings, shoulders, banking, cuttings/embankments | WORKING | Procedural road shader; terrain carve fix verified (terrain-above-road samples 1012 → 2). |
| Bridges (bay bridge, river bridges) with piers/parapets | WORKING | Screenshot `coast_bridge`. |
| Tunnel with portals and lights | WORKING | One 180 m tunnel; terrain holes + trimesh collision at portals. |
| Guard rails, edge posts/reflectors, chevrons, junction and village signs | WORKING | Blender sign kit + procedural rails. |
| Uninterrupted 5 km+ stretches | PARTIAL | The 20 km loop is continuous but has side-road junctions every 1–3 km; longest junction-free stretch is shorter than 5 km. |
| Intersections usable by traffic | WORKING | Traffic turns at junctions and transfers between roads. |
| Settlements, farms, gas stations, diner, harbour, lighthouse, castle, wind farm, festival | WORKING | Places screenshots. |
| Vegetation (trees, shrubs, rocks, cacti, grass) | WORKING | Per-chunk MultiMeshes + near grass tiles. |
| River and sea water | WORKING | Depth-faded water shader, river ribbon. |
| Day/night cycle with vehicle/street lights | WORKING | Night village screenshot (lit windows, lamps, headlights). |
| Weather: clear, cloudy, rain, fog, storm | WORKING | Rain/fog screenshots; storm adds lightning + thunder. |
| Traffic: lane graph, IDM following (incl. player), curve speeds, junction give-way, pooling, spawn ring, physics LOD | WORKING | 17–26 active cars observed; pool of 33. Give-way logic not separately measured. |
| Traffic types (city car, van, lorry, coach, pickup, tractor) | WORKING | Blender-authored; tractors only on farm roads. |
| Traffic crash response / honk / flash | WORKING | Crash test: contact → dynamic body → stopped obstacle with hazards (geometric contact check, Jolt does not report kinematic contacts). Honk audio not verified by listening. |
| Traffic overtaking, parked cars | NOT IMPLEMENTED | |
| Speed traps | WORKING | QA: Valley Radar recorded speed + PB. |
| Speed zones | WORKING | QA: Highway Haste average 156 km/h, 2 stars. |
| Drift zones | WORKING | QA: Crown Hairpins scored. |
| Danger signs / jumps | WORKING | QA: Dune Leap 21.4 m. |
| Checkpoint races with AI opponents | WORKING | QA: Coast Sprint, 3 AI cars, countdown, checkpoints, finish position. |
| Time trial (20 km Grand Tour) | WORKING | Full lap on autopilot: 20 checkpoints, 14:16.5, PB saved. |
| Collectible festival boards | WORKING | 20 boards; pickup test: "+500 credits, 1 / 20 found", persisted. |
| HUD (speed km/h/mph, tach, gear, assists, surface, region, notifications) | WORKING | Screenshot `ui_hud_drive`. |
| Minimap | WORKING | Rotating, roads, traffic dots, event markers, GPS route. |
| Full map with waypoint | WORKING | Screenshot `ui_map`. |
| GPS route line on the road | WORKING | Dijkstra over the road graph; screenshot `gps_route`. |
| Save/load (car, paint, upgrades, position, time, weather, settings, PBs, credits) | WORKING | Two-process round trip test; autosave every 60 s. |
| Input map: keyboard + mouse | WORKING | Gamepad intentionally removed at the user's request. |
| Gamepad support | NOT IMPLEMENTED | Removed by request. |
| Threaded chunk streaming, no main-thread terrain hitches | WORKING | Near meshes + collision on WorkerThreadPool (fixed a 575 ms collision hitch). |
| Performance target 60 FPS | PARTIAL | 166 fps avg / p99 11 ms before dressing on an idle GPU; 73 fps avg / p99 32 ms with full dressing while other projects loaded the shared GPU to 99 %. |
| Packaged export | NOT IMPLEMENTED | Stretch goal; baked data under `data/world` would need an export filter. |
