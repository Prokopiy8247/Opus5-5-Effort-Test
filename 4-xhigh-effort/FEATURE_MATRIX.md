# Feature matrix

Status values: `WORKING` (functional in-game path that was exercised), `PARTIAL`, `NOT IMPLEMENTED`.
"Exercised" means run in the game or by the automated scripts in `tools/qa/` (results in `qa/results/`
and screenshots reviewed during development).

| Feature | Status | Notes |
|---|---|---|
| **Core** | | |
| Project boots into free roam, player spawns in a car on a road | WORKING | Main scene `scenes/main.tscn`; spawn on the Festival Loop |
| Standalone Windows executable | WORKING | `exports/windows/VALORIA.exe` via `tools/export_windows.ps1`; verified with `--selftest` in the exported build |
| First-launch world generation | WORKING | ~30 s, deterministic seed, progress screen; `tools/world_bake.gd` regenerates |
| Save / load (car, paint, upgrades, tuning, position, time, weather, settings, PBs, credits) | WORKING | `save_test`: all fields restored, position within 0.2 m; autosave every 60 s and on quit |
| **World** | | |
| 4 × 4 km island with 4 distinct regions | WORKING | Verdana Valley, Pinecrest Highlands, Redmesa Canyons, Marisol Coast (+ festival hub) |
| Connected road network ~40 km, 20 km scenic loop, 5 km expressway | WORKING | 19 roads, junctions usable by traffic; loop driven end-to-end by autopilot without falls |
| Road construction: markings, shoulders, verges, banking, cuttings/embankments | WORKING | Baked profiles with grade limits; terrain carved to the road |
| Bridges, overpasses, tunnel | WORKING | Bridges with piers/abutments/parapets; expressway overpasses; valley tunnel with Blender portals |
| Guard rails, reflector posts, road signs, street lamps | WORKING | Signs: speed limits, curve chevrons, warning triangles, direction boards (Blender kit) |
| Culverts | NOT IMPLEMENTED | |
| Surface types with distinct physics and audio (asphalt, concrete, dirt, gravel, grass, sand, wet asphalt) | WORKING | Surface from collider metadata / surface map; wet asphalt via weather wetness; snow and rock also defined |
| Settlements and POIs (village, hamlet, farms, harbour, 2 gas stations, diner, castle, wind farm, lighthouse, viewpoints) | WORKING | 49 Blender buildings + 11 landmark instances (castle, lighthouse, festival hub, 2 viewpoints, 6 wind turbines); windows glow and street lamps light at night |
| Fences / hedgerows | NOT IMPLEMENTED | |
| Vegetation with LODs (trees, palms, cacti, bushes, rocks, grass) | WORKING | 59,007 MultiMesh instances, Blender meshes with `_LOD1`, collision near the player |
| Crops / flowers | PARTIAL | Fields are striped crop textures in the terrain shader; no 3D crop meshes |
| Water: sea, river, beaches | WORKING | |
| **Sky and weather** | | |
| Day/night cycle with sun, moon, stars, vehicle and street lights | WORKING | 1 game hour per real minute; `time` console command |
| Weather: clear, cloudy, rain, fog, storm with grip effect | WORKING | Smooth blending, rain particles, lightning + thunder, wet surfaces, grip multiplier |
| Snow at altitude | WORKING | Rain turns to snow particles high in the highlands; snowy peak |
| **Driving** | | |
| Project-owned raycast vehicle (suspension, tyres, engine, gearbox, differentials, aero, anti-roll) | WORKING | Chosen over VehicleBody3D after an automated comparison |
| Automatic and manual gearbox | WORKING | Part-throttle short-shifting, kick-down; manual with E/Q |
| Assists: TCS, ABS, stability, steering assist | WORKING | Garage/debug toggles and `assist` console command |
| Braking line assist | NOT IMPLEMENTED | Optional in the brief |
| Lights (head, brake, reverse), horn | WORKING | |
| Tyre smoke, dust, skid marks | WORKING | `fx_test` screenshots |
| Rewind | WORKING | Hold Backspace (10 s buffer); `rewind_test` |
| Reset to road / flip | WORKING | R key, `respawn` / `reset` |
| Collisions with impact response and sound | WORKING | Visual damage not modelled |
| Visual damage | NOT IMPLEMENTED | Bonus item in the brief |
| Drive tests (0–100, top speed, braking, skidpad, lane change, jump, gravel, handbrake) | WORKING | Numbers in `DEVELOPMENT.md` §4.3 |
| **Cameras** | | |
| Chase, far chase, hood, cockpit, bumper; free look; look back; collision; speed FOV; shake | WORKING | C cycles, right-drag free look, B look back |
| **Cars** | | |
| 10 distinct Blender cars, each with handling Resource, engine sound profile and class label | WORKING | Hatch, sedan, muscle, coupe, GT, supercar, rally, SUV, pickup, roadster |
| Paint: colour, finish (gloss/metallic/matte/pearl), stripes, rim colour | WORKING | Garage + `paint`/`stripe` commands |
| Upgrades with gameplay effect (engine, tyres, suspension, brakes, weight, aero) | WORKING | Stat deltas shown in the garage |
| Tuning (final drive, brake bias, springs, dampers, anti-roll, aero, tyre pressure, camber) | WORKING | Garage tuning tab |
| Rim style swap | NOT IMPLEMENTED | Rim colour only; each car keeps its authored rim design |
| **Traffic** | | |
| Lane graph, right-hand lanes, speed limits per class, junction give-way | WORKING | |
| IDM following, braking for the player and obstacles, curve slowing | WORKING | |
| Six Blender traffic types (compact, estate, van, lorry, bus, tractor) | WORKING | Tractors only on farm roads |
| Density by region / time of day / console | WORKING | `traffic <0..1>` |
| Pooling, out-of-view spawning, physics → kinematic → despawn LOD | WORKING | `traffic_test` |
| Collision reaction, horn/flash feedback, stuck despawn | WORKING | |
| Overtaking on long roads | NOT IMPLEMENTED | |
| Parked cars / rest areas | NOT IMPLEMENTED | Stretch |
| **Activities** | | |
| Speed traps (5) with personal bests | WORKING | `activities_test` |
| Speed zones (2) | WORKING | |
| Drift zones (3) | WORKING | Chain + multiplier scoring |
| Danger-sign jumps (4) | WORKING | Blender ramps with collision beside the road |
| Checkpoint road races (5) | WORKING | Enter at the arch, countdown, GPS to checkpoints; Expressway Dash completed in test |
| Time trial on the scenic loop | WORKING | Same flow as races; 13 checkpoints |
| AI race opponents | NOT IMPLEMENTED | Optional stretch |
| Collectibles / photo spots / hidden cars | NOT IMPLEMENTED | Stretch |
| Credits economy | PARTIAL | Credits are earned and saved; nothing to spend them on |
| **HUD, map, navigation** | | |
| Speedometer (km/h / mph), tachometer, gear, surface and assist indicators | WORKING | |
| Region name popups and event notifications | WORKING | |
| Minimap with roads, heading, POIs, activities, traffic, GPS route | WORKING | |
| Full map with regions, places, activities, waypoint by click | WORKING | M |
| GPS route line on the road | WORKING | G = nearest event, map click = any point |
| UI tested at more than one resolution | WORKING | 1920×1080 and 1280×720 runs |
| **Tools** | | |
| Developer console (all required commands + extras) | WORKING | `console_test`: 39 commands, 13/13 assertions |
| Garage / car-select menu with stats | WORKING | F1 / Tab |
| Benchmark / debug menu (teleports, spawn car, time, weather, traffic, assists, overlays, repair, telemetry) | WORKING | F2; `bench` console command |
| Photo mode (free camera, FOV, depth of field, time/weather freeze, hide panel, screenshot) | WORKING | P; screenshots to `user://screenshots` |
| **Audio** | | |
| Procedural engine by RPM and load (10 profiles) | WORKING | `audio_test`: 30/30 within an octave of the firing frequency |
| Turbo whistle / blow-off, gear shifts | WORKING | |
| Tyre squeal / gravel / grass by surface, wind, suspension thumps, impacts | WORKING | |
| Rain, thunder, regional ambience, night crickets, horns, traffic hum | WORKING | |
| **Performance** | | |
| 60 FPS target at recording settings | WORKING | 157 FPS avg over a 10-min soak at 1080p (p99 16 ms); 314 km/h streaming test p99 11 ms |
| Threaded terrain streaming, MultiMesh dressing, visibility ranges, pooled traffic | WORKING | |
| **Input** | | |
| Keyboard + mouse | WORKING | |
| Gamepad | NOT IMPLEMENTED | Intentionally omitted at the user's request |
