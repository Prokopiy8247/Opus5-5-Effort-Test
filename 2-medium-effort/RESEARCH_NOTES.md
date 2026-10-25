# Research Notes: Open-World Racer (Godot 4.7), mechanics inspired by Forza Horizon 5

Scope note: mechanics only. No branded names, cars, music, or map layout are reused. Items marked (recall) come from general knowledge of the genre rather than a fetched page.

## 1) Feature inventory of FH5 (by area)

### World structure
- One large map (reported as roughly 1.5x the size of the previous Britain map) split into distinct biomes: desert, jungle, wetlands, coast, farmland, volcano with the only snow, a dense city, ruins and dunes.
- Biomes carry their own climate, so the same season looks and plays differently per region (dust storms in the dry season, tropical storms in storm season).
- Road types: long corner-to-corner highways, paved back roads, dirt tracks, and open cross-country terrain. One city has partly underground roads.
- Roads are reused: every race is a route painted over the same open-world roads and terrain. Road races stay on tarmac, dirt races use tracks, cross-country races cut through fields with checkpoint gates.
- Festival hubs act as the hub for events, car shops and the garage (recall).

### Seasons, weather, time of day
- Four seasons (labelled wet, storm, dry, hot in one guide), cycling on a fixed schedule.
- Weather is regional; storms are local, grow and spread over time.
- Effects on driving: wet surfaces cut grip, dirt turns to mud, snow and ice lower traction, dust storms and rain cut visibility (recall for the exact tuning).
- Day/night cycle changes lighting, headlight need, and visibility (recall).

### Road activities and map markers
- Listed marker types: Speed Traps, Speed Zones, Drift Zones, Danger Signs (jump challenges), Barn Finds, XP boards, Fast Travel boards, Landmarks, Expeditions, Trailblazers, Player Houses.
- Original-map counts reported by one listing: 35 speed traps, 24 danger signs, 26 speed zones, 20 drift zones.
- Mechanics (recall): speed trap scores peak speed through a gate; speed zone scores average speed over a stretch; drift zone scores a chained drift score; danger sign scores the longest air jump; each has star-style thresholds.
- Collectibles: bonus boards (smash for rewards), barn finds (hidden rare car with a hint), photo challenges.

### Cars, classes, upgrades
- Large roster grouped by body types and eras; every car has a Performance Index (PI).
- Seven classes: D (100-500), C (501-600), B (601-700), A (701-800), S1 (801-900), S2 (901-998), X (999+).
- PI is computed from stats (speed, handling, acceleration, launch, braking, offroad); any upgrade shifts PI and class.
- Customization: paint and finish, vinyl, wheels, body kits, wings (cosmetic and sometimes functional).
- Upgrades by part group (engine, drivetrain, tires and rims, aero, weight reduction, conversions); tuning sliders for tire pressure, gearing, alignment, anti-roll bars, springs, ride height, damping, aero, brake balance, differential.
- Conversions: swapping drivetrain or aspiration.

### Traffic and ambient life
- Civilian AI cars on roads, wildlife in the world, NPC drivers in races (recall).
- Driveable dust, props, destructible objects.

### HUD and navigation
- Minimap with a route line to the selected waypoint, with a large pause-menu map as well. Speedometer plus gear, tach, nitrous-style readout in some modes (recall).
- GPS-style painted route on the road surface toward the waypoint; checkpoint gates in races.
- Race HUD: position, lap/checkpoint, time, ghost splits.

### Assists and photo mode
- Assists named in sources: ABS, traction control (TCS), stability management (STM), braking line vs full racing line, automatic transmission, rewind.
- Community advice: ABS is cheap to leave on, TCS can block drifting and slow lap times in powerful cars, braking line is preferred over full line by some players.
- Rewind lets the player undo a mistake; it is a presentation-level setting rather than a physics assist.
- Photo mode (recall): free camera, aperture/focus, exposure, time of day, filters, car pose; photo challenges ask for specific car/location shots.

## 2) Adoption table (our scope)

| Feature | Decision | Reason |
|---|---|---|
| 4 biomes/regions in 4x4 km | ADAPT | Compress: each region ~1 km, with sharp visual identity and different surface grip. |
| Highways + back roads + dirt + cross-country | ADAPT | Spline roads plus open terrain; one highway loop links all regions. |
| Seasons | SKIP | Weather + time of day deliver the same variety at far less cost. |
| Regional weather | ADAPT | Global weather states with per-region modifiers (dust, fog, rain, clear). |
| Weather grip effects | ADOPT | Core driving feel: wet, dirt, sand, gravel multipliers. |
| Day/night cycle | ADOPT | Sun + sky + headlights; cheap with DirectionalLight and WorldEnvironment. |
| Speed traps | ADOPT | Simple gate trigger plus speed read. |
| Speed zones | ADOPT | Start/end trigger, average speed. |
| Drift zones | ADOPT | Drift-angle score accumulation inside a zone. |
| Danger signs / jumps | ADOPT | Ramp + air-distance measure. |
| Checkpoint races (road/dirt/cross-country) | ADOPT | Main activity; gate list + AI opponents optional. |
| Time trial | ADOPT | Reuses the race gates, adds a ghost timer. |
| Barn finds / bonus boards | ADAPT | A few collectible props (boards) only; barn finds skipped. |
| Photo challenges | SKIP | Photo mode itself is kept; challenges add scoring logic with no payoff. |
| Festival hubs | ADAPT | One garage/hub spawn point rather than a full hub. |
| Car roster of hundreds | ADAPT | 10 original cars with a shared handling model and per-car data resources. |
| PI classes D-X | ADAPT | Keep the PI number and class labels (D/C/B/A/S1/S2/X) computed from stats. |
| Customization (paint) | ADOPT | Paint color + finish via material parameters. |
| Upgrades | ADOPT | Part tiers modify stats, PI recalculated. |
| Tuning sliders | ADAPT | Small set: tire pressure, gearing, spring/ARB, downforce, brake balance. |
| Vinyl/body kits/conversions | SKIP | Heavy content cost. |
| Civilian traffic | ADOPT | Simple path-following AI on the road splines. |
| Wildlife | ADAPT | A few ambient props (birds, animals) if time allows. |
| Minimap + waypoint route | ADOPT | Top-down SubViewport camera and a drawn route line. |
| GPS road paint | ADAPT | Route ribbon/line on minimap and a 3D marker beam. |
| Assists (ABS/TCS/STM, line, rewind) | ADAPT | Toggles for ABS/TCS/STM and braking line; rewind via a ring buffer of states. |
| Photo mode | ADOPT | Free cam, FOV, time-of-day, filters, screenshot save. |
| Dev console + garage menu | ADOPT | Required by brief; console commands drive weather, time, teleport, spawn. |
| Save/load | ADOPT | JSON in user:// for cars, tuning, progress. |
| Story/campaign | SKIP | Out of scope. |
| Online/multiplayer | SKIP | Out of scope. |
| Auction house / licensed cars / music | SKIP | Out of scope; use original cars and synthesized or royalty-free audio. |

## 3) Godot technical notes (from docs fetched)

- VehicleBody3D: raycast-vehicle node, quick to set up, but the docs say it has known issues and is not meant for realistic vehicle physics. Gears are not simulated; no direct transform edits. Engine_force guidance: about 25-50 for a 1000 mass, brake about 25-30 at that mass. Keep origin low for a low center of gravity.
- Recommendation: for a game-feel racer with surface grip modifiers, build a custom raycast vehicle on RigidBody3D (4 ray or shape casts, own spring/damper, own tire force model with slip angle and per-surface friction, own gearbox). Fall back to VehicleBody3D only as a prototype.
- Jolt: built in since Godot 4.4 and default for new projects; set Project Settings > Physics > 3D > Physics Engine = Jolt Physics. Contact impulses are estimated; ray-cast face index is off by default; settings live under physics/jolt_physics_3d. Joint feature gaps exist (not needed for cars). Threading option exists but is experimental.
- MultiMeshInstance3D: one draw call for all instances, but no per-instance culling (whole multimesh is drawn or skipped). Set transform_format before instance_count. Workaround: split into chunk-sized multimeshes per area (trees, rocks, grass). Use visible_instance_count to scale. Docs page did not cover visibility ranges; per-node visibility_range_begin/end (GeometryInstance3D) can be applied to each chunk (recall, not verified from fetched page). Use mesh LODs per chunk.
- WorkerThreadPool: add_task(callable) returns an id; add_group_task(callable, elements) runs per-index in parallel. Every task must be waited on for cleanup. Only worth it for heavy work (terrain mesh generation, scatter placement, road mesh building). Do not touch the scene tree from tasks; hand results back with call_deferred.
- AudioStreamGenerator: no sound on its own; script fills the playback buffer with push_frame (Vector2 stereo) while checking get_frames_available. Default mix_rate 44100, buffer_length 0.5 s; shorter buffer lowers latency but risks crackle. Docs warn GDScript is limited for this; keep synthesis simple (a few harmonics driven by RPM), use a lower mix rate (22050) for engine tones, and fill in _process.
- Plan: use a low mix rate and phase-accumulator synthesis for engine, noise for tires and wind, one generator per player car only.

## 4) Source URLs

Fetched:
- https://docs.godotengine.org/en/stable/classes/class_vehiclebody3d.html
- https://docs.godotengine.org/en/stable/tutorials/physics/using_jolt_physics.html
- https://docs.godotengine.org/en/stable/classes/class_workerthreadpool.html
- https://docs.godotengine.org/en/stable/classes/class_audiostreamgenerator.html
- https://docs.godotengine.org/en/stable/tutorials/performance/using_multimesh.html

Seen in search results:
- https://www.windowscentral.com/forza-horizon-5-upgrading-guide
- https://forums.forza.net/t/map-locations-weather-and-environmental-biomes-in-fh5/534407
- https://www.gtplanet.net/forza-horizon-5-guide/
- https://www.pcgamer.com/uk/seasons-return-in-forza-horizon-5-with-one-important-twist
- https://www.nme.com/news/forza-horizon-5-will-bring-back-seasonal-weather-but-with-a-new-change-2970061
- https://racinggames.gg/forza/forza-horizon-5-complete-guide-to-scenery-and-seasons/
- https://guides4gamers.com/forza-horizon-5/
- https://www.gamesradar.com/forza-horizon-5-tips
- https://drifted.com/forza-horizon-5-drift-tune
- https://forums.forza.net/t/is-it-best-turning-abs-etc-off/4622

Caveat: search snippets only; FH5 pages were not fetched in full. Photo mode, HUD and activity scoring details are from recall.

## 5) Final committed feature list (priority order)

1. Custom raycast car physics on RigidBody3D with Jolt, per-surface grip, 10 original cars from data resources.
2. Drivable 4x4 km terrain with 4 regions, road splines, and a highway loop.
3. Day/night cycle and weather states (clear, rain, fog/dust) with grip effects.
4. HUD: speedometer, gear, tach, minimap with waypoint route, 3D waypoint marker.
5. Checkpoint races and time trial.
6. Road activities: speed traps, speed zones, drift zones, jumps.
7. Civilian traffic on road splines.
8. Garage menu: car select, paint, upgrades, tuning, PI and class display.
9. Dev console (weather, time, teleport, spawn, money, toggle assists).
10. Assists: ABS, TCS, STM, braking line, rewind.
11. Save/load to user://.
12. Photo mode.
13. Procedural audio (engine, tires, wind) via AudioStreamGenerator.
14. Ambient wildlife and collectible boards (stretch).
15. MultiMesh scatter with chunking and visibility ranges for foliage and rocks; WorkerThreadPool for generation (performance work, runs alongside 2).
