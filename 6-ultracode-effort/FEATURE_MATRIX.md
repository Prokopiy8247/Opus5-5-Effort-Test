# Feature matrix — Sunward Roads

Status values: `WORKING` (exercised in a real run), `PARTIAL`, `NOT IMPLEMENTED`. Updated continuously; the final
state is summarised in `OPUS_5.5_FINAL_REPORT.md`.

| Feature | Status | Notes |
|---|---|---|
| Project runs headless-clean, main scene loads | WORKING | `check_scripts.tscn` CHECK_OK; QA runs without script errors |
| Blender MCP pipeline (verified port 9882 / master file) | WORKING | path verified via read-only `bpy.data.filepath`; backup made; car kit + glb export |
| Keyboard + mouse controls (Input Map) | WORKING | gamepad support intentionally not implemented (user request) |
| Raycast vehicle physics (Jolt, 120 Hz) | WORKING | drive tests for 10 handling profiles (DEVELOPMENT.md) |
| VehicleBody3D comparison | WORKING | `tools/tests/vehiclebody_compare.gd`, documented decision |
| Gearbox auto/manual, FWD/RWD/AWD, LSD | WORKING | drive tests; manual shifting via E/Q |
| Assists TCS / ABS / STM / steering assist | WORKING | toggles in console, debug menu, settings |
| Braking line assist | WORKING | ribbon on the road ahead, green/yellow/red from current speed vs brake-to-corner speed (`scripts/vehicle/braking_line.gd`) |
| Hill hold, rewind (hold Backspace) | WORKING | rewind scrubs the last 15 s |
| Damage (power loss) + repair / flip reset / respawn to road | WORKING | HUD damage meter; R resets to the nearest road lane |
| Chase near/far, hood, bumper, cockpit cameras, free look, shake | WORKING | cockpit verified on Blender cars |
| Procedural world 4x4 km, 4 regions | WORKING | Verdant Vale, Ironcrest Highlands, Ochre Mesa, Saltwind Coast |
| Road network 40-60 km | WORKING | 26 roads, 41.75 km, 0 unintended crossings, road collider under every 3 m sample (`--qa=roadcheck`) |
| Scenic loop >= 20 km | WORKING | Sunward Ring 20.26 km, min radius 21.6 m; driven end to end (QA autopilot laps + time-trial test) |
| Several 5 km+ uninterrupted stretches | WORKING | ring segments between junctions |
| Bridges, tunnel, guard rails, chevrons, delineators, direction signs, culverts, junction fillets | WORKING | procedural geometry; 12 ring bridges incl. Estuary Bridge, Ember Spur tunnel, 19 drainage culverts |
| Surfaces with distinct grip/audio (asphalt, wet asphalt, concrete, dirt, gravel, grass, sand, snow) | WORKING | collider metadata + terrain surface map |
| Chunked terrain streaming (threaded, LOD, colliders) | WORKING | 1024 chunks, 4 LODs, streamed height-field colliders (trimesh only at the tunnel portals), refocus on teleport |
| Garage of 10 Blender cars | WORKING | all 10 Blender models (body, glass, interior, wheels, lights, sockets) exported, reviewed, imported and driven in game (`final_validation`: 10/10 drivable with their glb) |
| HUD (speedo, tach, gear, assists, surface, region popups, notifications) | WORKING | ui_hud implementer + integration runs |
| Minimap, world map, waypoint, GPS route + 3D route line | WORKING | |
| Console (all spec commands) | WORKING | |
| Garage menu (cars, paint, upgrades, tuning) | WORKING | |
| Debug / benchmark menu | WORKING | teleports, time/weather/traffic/assists, 60 s benchmark |
| Pause / settings / save / load | WORKING | save/load round trip in `tools/tests/final_validation.tscn` (car back within 0.01 m) |
| Screenshot key (F12) | WORKING | saves `user://screenshots/*.png` while driving or in menus; photo mode has its own capture |
| Photo mode | WORKING | free camera, FOV, DOF, exposure, roll, time/weather, PNG capture |
| Day/night cycle + 5 weathers with grip effect | WORKING | wetness drives `CarController.wetness` |
| Civilian traffic (lane graph, junction priority, LOD, pooling, crash reactions) | WORKING | 6 Blender vehicle types (hatch, van, lorry, coach, tractor, pickup); physics near the player, kinematic with colliders further out, shunts/hazards, overtaking, respawn gaps |
| Activities: speed traps, speed zones, drift zones, jumps, races (+AI), time trial, collectibles | WORKING | 42 events (6 traps, 4 zones, 4 drift zones, 5 jumps, 2 races with 3 AI rivals each, ring time trial, 20 flags); rivals use the Blender cars |
| Procedural audio (engine synth, tyres, wind, impacts, horn, ambience, thunder, tunnel reverb) | WORKING | as implemented before the user stopped audio work (2026-10-24); test runs are muted, no later audio QA |
| Vehicle effects (smoke, dust, spray, skid marks, backfire, sparks, dirt) | WORKING | |
| Vegetation + settlements | WORKING | all four regions dressed with the Blender nature kit; 431 settlement props from the Blender buildings/roadside kits |
| Blender prop kits (buildings, roadside, nature) + traffic vehicle models | WORKING | 74 kit props (24 nature, 25 roadside, 25 buildings/landmarks) + 6 traffic vehicles, reviewed in Blender, all 74 contract names load from the kits (`PROPLIB_OK`), pre-merged by `tools/bake_props.tscn` |
| Windows build (standalone exe) | WORKING | `export_presets.cfg` "Windows Desktop" exports `build/windows/SunwardRoads.exe` (single 145 MB exe, pack embedded, world data included); the exported exe loads the world and passes `--qa=teleports` 30/30 |
| Traffic overtaking through the oncoming lane on two-lane roads (stretch) | NOT IMPLEMENTED | traffic changes lanes and overtakes only on the 4-lane expressway; race rivals do pass through the oncoming half when it is clear |
| Parked cars at rest areas / fuel stations (stretch) | PARTIAL | parked cars line the Millbrook and Gullhaven streets; none at the fuel stations |
| Photo spots / hidden cars (activities stretch) | NOT IMPLEMENTED | collectibles are the 20 festival flags |
| Occlusion culling | NOT IMPLEMENTED | not needed for the frame budget: visibility ranges, LODs, far meshes and chunk streaming instead |
| Gamepad support | NOT IMPLEMENTED | intentionally left out at the user's request (keyboard + mouse only) |
| Further audio work / audio QA | NOT IMPLEMENTED | stopped at the user's request on 2026-10-24; the procedural audio above stays as implemented, test runs are muted |
