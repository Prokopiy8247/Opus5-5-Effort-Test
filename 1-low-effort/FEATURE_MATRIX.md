# Feature matrix

| Feature | Status | Notes |
|---|---|---|
| Launch into free roam on a road | WORKING | Spawns on the Grand Valley Loop (or at the saved position) |
| 4 regions (farmland, mountains, desert, coast) | WORKING | Distinct terrain shapes, ground colours and vegetation; region popups |
| Road network 40–60 km | WORKING | 13 roads, 41.1 km total |
| Scenic loop ≥ 20 km | WORKING | Grand Valley Loop 20.2 km, closed |
| Bridges | WORKING | Automatic over the river and bay: deck, pillars, rails |
| Tunnels | PARTIAL | Shell, portals and lights over deep cuttings; the terrain is a cutting, not a bored hole |
| Lane markings, shoulders, guard rails, posts, lamps | WORKING | Shader markings; MultiMesh furniture from the Blender kit |
| Surface types with distinct grip | WORKING | Asphalt, concrete, dirt, gravel, grass, sand, snow. Road colliders carry `surface` metadata; terrain surface comes from `WorldGen.surface_at` |
| Chunked, threaded terrain streaming | WORKING | 128 m chunks, 2 LODs, WorkerThreadPool, far mesh |
| Raycast vehicle (springs, tyres, gears, drivetrains, aero, ARB) | WORKING | `scripts/vehicle/car.gd` |
| Assists TCS / ABS / STM / steering / auto gearbox | WORKING | Toggle in the console (`assist`) and in the debug menu |
| 10 distinct Blender cars with own handling | WORKING | `data/cars/*.tres` |
| Chase / far / hood / cockpit / bumper cameras | WORKING | `C` cycles; mouse (right button) for free look; `B` looks back |
| Procedural engine / turbo / tyre / wind / horn audio | WORKING | AudioStreamGenerator |
| Tyre smoke, dust, skid marks | WORKING | |
| Damage | PARTIAL | A damage value is tracked and repairable; no visual deformation |
| Day/night cycle | WORKING | Headlights switch on automatically at night |
| Weather clear / cloudy / rain / fog / storm | WORKING | Changes fog, sky, rain particles, wet roads and grip (−25% when wet) |
| Gamepad input | NOT IMPLEMENTED | Removed by user request; keyboard + mouse only |
| Civilian traffic (6 Blender types) | WORKING | Lane following, gap keeping, curve speed, give-way at branch ends, pooling, wrecks on impact |
| Traffic overtaking / turn signals | NOT IMPLEMENTED | |
| Speed traps | WORKING | 5; verified in `--functest` (all 5 recorded personal bests) |
| Speed zones | WORKING | 3; Ridge Run completed in `--functest` (avg 113–119 km/h). Others failed in the test because the autopilot hit traffic |
| Drift zones | PARTIAL | 4 zones; they start and end with the scoring logic, but the automated test (autopilot + handbrake) never produced a sustained drift score |
| Danger-sign jumps | WORKING | 3 ramps; verified 46.8 / 45.7 / 70.2 m. Freestyle jumps off road crests are also scored |
| Checkpoint races | PARTIAL | 2 (solo, no AI opponents); start gate + checkpoint progression verified, a full finish was not exercised by automation |
| Time trial on the loop | PARTIAL | 20 checkpoints; started and progressed to CP 5/20 during the autopilot lap |
| Collectibles / AI racers | NOT IMPLEMENTED | |
| Developer console | WORKING | Backtick; `help` |
| Garage menu (F1/Tab) | WORKING | Stats, paint, finish, upgrades, tuning |
| Debug / benchmark menu (F2) | WORKING | Teleports, cars, time, weather, traffic, assists, telemetry |
| Paint and finishes | WORKING | Rim colours are not implemented |
| Upgrades (6 parts × 3 stages) | WORKING | Change power, grip, brakes, mass, aero and suspension (verified via save/load test); the class label shows the base spec |
| Tuning | WORKING | Final drive, brake bias, springs, ARB, downforce, tyre pressure |
| Photo mode | WORKING | Free cam, FOV wheel, DOF, frozen time, hidden HUD, F12 |
| HUD speedo/tacho/gear/assists/surface | WORKING | km/h and mph |
| Minimap and full map with waypoint | WORKING | No GPS route line on the road |
| Save/load | WORKING | `user://savegame.json`: car, paint, upgrades, position, time, weather, settings, bests |
| Settlements and POIs | WORKING | Village, hamlet, farms, gas stations, diner, harbour, lighthouse, castle ruin, wind farm, lodge |
