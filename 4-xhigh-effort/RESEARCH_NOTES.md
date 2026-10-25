# Research notes — Forza Horizon 5 reference study and Godot 4.7 verification

Game being built: **VALORIA: Open Road Festival** (original title, original fictional region "Valoria").
Forza Horizon 5 (FH5) is used only as a *mechanics / structure / scope* reference. No names, maps,
logos, models, textures, audio, UI art or code are reused.

Web tools were available (WebSearch + WebFetch) and were used on 2026-10-23. All text below is my
own summary.

## 1. FH5 feature inventory (as understood) and decisions

### 1.1 Open-world structure
| FH5 feature | My understanding | Decision | Reason |
|---|---|---|---|
| Large map (~1.5x FH4) split into 11 biomes | Canyon, tropical coast, farmland, arid hills, jungle, living desert, rocky coast, sand desert, swamp, a city, a volcano with switchbacks | **ADAPT** | 4 km x 4 km map with 4 regions (farm valley, alpine highlands, canyon desert, coastal cliffs) — scope fixed by the brief |
| Corner-to-corner highways | Long fast roads for top-speed cruising | **ADOPT** | A ~5 km north–south expressway through the map centre |
| Huge switchback roads (tarmac + dirt) on the volcano | Signature climbing roads | **ADOPT** | Alpine pass with several hairpins, plus a gravel forest climb |
| City with underground tunnels | Dense urban area | **SKIP** (city) / **ADOPT** (tunnel) | Brief forbids a city; a mountain tunnel is kept |
| Scenic pull-offs, viewpoints | Places to stop and look | **ADOPT** | Viewpoint POIs on the pass and on the coast |
| Festival hub + outposts | Event hubs with their own race types | **ADAPT** | One festival hub at the central crossroads (decorative landmark + spawn), no progression |
| Barn finds | Hidden garages with cars to restore | **SKIP** | No progression economy; garage has all 10 cars |
| Bonus boards (250 smashables) | Collectibles | **ADAPT (stretch)** | A small set of "festival boards" collectibles if time allows |

### 1.2 Seasons, weather, time of day
| FH5 feature | My understanding | Decision | Reason |
|---|---|---|---|
| Weekly seasons (wet/storm/dry/hot) per biome | Global season rotation changes look and water levels | **SKIP** | Too big; replaced by free weather states |
| Localised weather (storms that move/grow) | Weather differs across the map | **ADAPT** | Global weather state + biome modifiers (dust in desert, snow flurries at altitude) |
| Rain / storm reduce visibility and traction | Grip lower when wet; heavy rain much lower | **ADOPT** | Weather sets a road wetness value that scales grip and road shading |
| Snow only at the volcano summit | Altitude-gated snow | **ADOPT** | Snow cover and flurries above the alpine snow line |
| Dynamic time of day, sunsets, night driving | Continuous cycle, strong sunset presentation | **ADOPT** | Full day/night cycle, sun/moon, stars, headlights, village street lights |

### 1.3 Road activities ("PR stunts") and events
| FH5 feature | My understanding | Decision | Reason |
|---|---|---|---|
| Speed traps | Pass a camera as fast as possible, star rating by speed | **ADOPT** | Gate trigger, score in km/h, personal best |
| Speed zones | Average speed over a road stretch (measured continuously) | **ADOPT** | Entry/exit gates, average of sampled speed |
| Drift zones | Score from speed x angle while staying on the road | **ADOPT** | Score accumulates while slip angle > threshold and wheels on road |
| Danger signs | Jump distance, must land cleanly (no crash/flip) | **ADOPT** | Ramps with distance measurement, fail on bad landing |
| Trailblazers | Point-to-point, any route | **ADAPT (stretch)** | A cross-country A→B timer if time allows |
| Road / dirt / cross-country races with AI | Checkpoint races | **ADAPT** | Solo checkpoint races on the long roads (AI opponents only as stretch) |
| Time trials / rivals | Lap timing vs ghost/leaderboard | **ADAPT** | Time trial on the 20 km+ scenic loop, personal best |
| Skill chains (drift, near miss, air, destruction) | Combo score with multipliers | **ADAPT (stretch)** | Small skill popup for drift/air/near-miss if time allows |

### 1.4 Cars, classes, upgrades, tuning
| FH5 feature | My understanding | Decision | Reason |
|---|---|---|---|
| Hundreds of licensed cars | Huge roster | **ADAPT** | Exactly 10 original cars (brief) |
| PI classes D/C/B/A/S1/S2/X with numeric PI | Classes by computed performance number (FH5 bands roughly D ≤500 … X ≥999) | **ADAPT** | Own class letters (E/D/C/B/A/S) + a project-own "rating" computed from power/weight/grip |
| Stat bars: speed, handling, acceleration, launch, braking (3–10) | Car summary for comparison | **ADOPT** | Five stat bars in the garage menu computed from handling data |
| Upgrades (engine, drivetrain, tires, suspension, aero, weight) | Parts change stats/PI | **ADOPT (reduced)** | Engine / tires / suspension / brakes / weight / aero levels with real effect |
| Tuning (tire pressure, gearing, alignment, ARB, springs, damping, aero, brake bias, diff) | Separate from upgrades, doesn't change stats | **ADAPT** | Reduced tuning set: final drive, brake bias, spring/damper scale, ARB, aero, tire pressure |
| Paint, wraps, rims | Livery editor | **ADAPT** | Primary colour + gloss/matte/metallic finish + stripe variant + rim colour |

### 1.5 Assists and difficulty
| FH5 feature | My understanding | Decision | Reason |
|---|---|---|---|
| ABS on/off | Biggest help for keyboard players | **ADOPT** | ABS toggle |
| Traction control, stability control | On by default for beginners, cost lap time | **ADOPT** | TCS and STM toggles, visible HUD indicator |
| Steering standard/simulation | Assisted steering vs raw | **ADOPT** | Steering assist toggle (counter-steer help + speed-sensitive lock) |
| Braking line / full racing line | On-road line showing where to brake | **ADAPT (stretch)** | GPS route line first; braking-colour line optional |
| Auto / manual gearbox | Shifting choice | **ADOPT** | Auto + manual (sequential) |
| Rewind | Time rewind | **ADAPT (stretch)** | Short rewind buffer if time allows |

### 1.6 World life, HUD, presentation
| FH5 feature | My understanding | Decision | Reason |
|---|---|---|---|
| Civilian traffic on roads | Ambient cars, collidable | **ADOPT** | Lane-graph traffic with pooling and sim LOD (brief requirement) |
| Online drivatars (AI copies of players) | Roaming AI racers | **SKIP** | No online; plain civilian traffic instead |
| Wildlife / ambient life | Birds, animals by biome | **ADAPT (stretch)** | Ambient audio per region; maybe birds |
| HUD: speedo/tach/gear, minimap with GPS route | Bottom-right gauge, bottom-left minimap | **ADAPT** | Own layout and art: gauge cluster, minimap, notifications |
| Full map with waypoints | Pause map | **ADOPT** | Map screen with regions, events, waypoint |
| GPS route line on the road | Chevron line to waypoint | **ADOPT (stretch)** | Route over the road graph |
| Photo mode (FOV, filters, DOF, time/weather, hide HUD) | Freeze game, free camera | **ADOPT (stretch)** | Free camera, FOV, DOF, time/weather freeze, hide HUD, screenshot |
| Festival presentation (bright colours, music, banners) | Optimistic tone | **ADAPT** | Bright palette, festival hub flags/banners, upbeat UI |

## 2. Godot 4.7.2 verification (installed engine, not memory)

Checked with `Godot_v4.7.2-stable_win64_console.exe --version` → `4.7.2.stable.official.ed1daf0bf`,
plus a `--doctool` dump of the installed class reference (signatures only) and the official docs.

| Topic | Finding | Consequence |
|---|---|---|
| Physics engine | project.godot already sets `3d/physics_engine="Jolt Physics"`; `physics/jolt_physics_3d/*` settings exist (CCD thresholds, velocity/position steps, max_linear_velocity = 500 m/s default) | Use Jolt; enable `continuous_cd` on player car; 120 Hz physics tick |
| HeightMapShape3D | `map_width`, `map_depth`, `map_data`; 1 unit grid spacing, centred on the shape; spacing via node scale; **NaN height punches a hole**; GodotPhysics needs uniform scale | Terrain collision per chunk with uniform scale 2 (heights pre-divided); NaN holes at tunnel portals |
| Jolt edge handling | Active-edge detection and enhanced internal edge removal reduce ghost bumps on heightmaps/trimeshes | Keep defaults on; important for wheels on road trimeshes |
| Jolt ray face index | `face_index` is -1 unless enabled | Surface type comes from collider metadata + a baked surface map, not face index |
| Kinematic contacts | Frozen kinematic bodies don't report contacts vs static unless opt-in | Traffic uses unfrozen RigidBody3D near the player |
| VehicleBody3D / VehicleWheel3D | Built in; simple friction-slip model | Compared in a prototype test (see DEVELOPMENT.md) |
| WorkerThreadPool | `add_task`, `add_group_task`, `wait_for_task_completion`, `is_task_completed` | Chunk mesh building on worker threads, node creation on main thread |
| GeometryInstance3D | `visibility_range_begin/end/_margin`, `visibility_range_fade_mode` | Terrain LOD + dressing distance fade |
| glTF import suffixes | `-col`, `-convcol`, `-colonly`, `-convcolonly`, `-noimp`, `-rigid`, `-vehicle`, `-wheel`, `-occ`; separators `-`, `$` **or `_`**, case-insensitive | Avoid object names ending in `_col`, `_wheel`, `_rigid` etc.; vehicle collision built in code |
| PhysicsRayQueryParameters3D | `exclude`, `collision_mask`, `hit_back_faces`, `hit_from_inside` | Wheel raycasts exclude own body, mask world layers |

## 3. Sources

- GTPlanet, FH5 biomes overview — https://www.gtplanet.net/here-are-the-11-biomes-featured-in-forza-horizon-5
- GTPlanet, FH5 guide hub — https://www.gtplanet.net/?p=110234
- Xbox Wire, biomes and seasons — https://news.xbox.com/en-us/?p=157849
- racinggames.gg, scenery and seasons — https://racinggames.gg/forza/forza-horizon-5-complete-guide-to-scenery-and-seasons/
- Forza forums, map/weather/biomes discussion — https://forums.forza.net/t/map-locations-weather-and-environmental-biomes-in-fh5/534407
- PR stunt types (Windows Experience blog, Series 5) — https://blogs.windows.com/windowsexperience/2022/03/08/pr-stunt-carnival-now-underway-in-forza-horizon-5-series-5-update/
- racinggames.gg, PR stunts — https://racinggames.gg/forza/forza-horizon-5-what-are-the-best-cars-for-pr-stunts
- Windows Central, upgrading guide / PI bands — https://www.windowscentral.com/forza-horizon-5-upgrading-guide
- Forza Support, PI and classes (FH3 article, series convention) — https://support.forza.net/hc/en-us/articles/360005372033-FH3-Performance-Index-and-Classes
- racinggames.gg, difficulty/assists — https://racinggames.gg/forza/forza-horizon-5-how-to-change-difficulty/
- GamesRadar, beginner tips (assists) — https://www.gamesradar.com/forza-horizon-5-tips
- Steam community discussion on assists — https://steamcommunity.com/app/1551360/discussions/0/3155328676446990761/?ctp=1
- PureXbox, Update 21 photo mode — https://purexbox.com/news/2023/05/forza-horizon-5-update-21-is-huge-featuring-all-new-photo-mode-options-and-more
- stevivor, barn finds — https://stevivor.com/guides/forza-horizon-5-barn-finds-guide-find-all-cars/
- forza.net achievements (bonus boards, outposts) — https://forza.net/news/forza-horizon-5-achievements
- Stevivor, weather/difficulty — https://stevivor.com/features/in-depth/forza-horizon-5-tourist-difficulty-changes-to-weather-detailed
- Godot docs, Jolt Physics — https://docs.godotengine.org/en/latest/tutorials/physics/using_jolt_physics.html
- Godot docs, HeightMapShape3D — https://docs.godotengine.org/en/latest/classes/class_heightmapshape3d.html
- Godot docs, node type customization (import suffixes) — https://docs.godotengine.org/en/latest/tutorials/assets_pipeline/importing_3d_scenes/node_type_customization.html

Notes on source quality: much of the FH5 coverage is pre-launch preview material (2021) or community
guides; nothing official documents exact grip values for weather, so grip multipliers are my own design.

## 4. Final committed feature list (priority order)

1. Raycast/spring vehicle on RigidBody3D (Jolt, 120 Hz) with data-driven handling, assists, chase/hood/cockpit/bumper cameras.
2. Blender-authored car pipeline (procedural builder script run through the verified MCP) → .glb → Godot.
3. Baked, seeded 4 km x 4 km heightmap with four regions, carved roads (cuttings/embankments), bridges, a tunnel; chunked + threaded streaming with LODs.
4. Road network 40–60 km with a 20 km+ scenic loop, an expressway, mountain pass, coast road, dirt/gravel tracks; road furniture.
5. HUD (speedo, tacho, gear, surface, assists), notifications, region popups.
6. Developer console, garage/car-select menu with stat bars, benchmark/debug menu.
7. Lane-graph civilian traffic (6 Blender vehicle types), pooling, sim LOD, junction give-way, collision response.
8. 10 distinct cars with own models, handling and procedural engine sound.
9. Day/night cycle and five weather states with grip, visibility, particles and wet roads.
10. Settlements, POIs and roadside dressing (Blender kit), MultiMesh vegetation.
11. Activities: speed traps, speed zones, drift zones, danger-sign jumps, checkpoint races, loop time trial.
12. Paint/finish/rims, upgrades with stat comparison, reduced tuning; photo mode.
13. Minimap, full map with waypoint, GPS route line.
14. Save/load in `user://`.
15. Polish (lighting, VFX, audio, camera) and final QA/performance documentation.
