# Research notes — "Horizon Drift: Four Valleys" (original title)

Web tools were available (WebSearch / WebFetch). The notes below are a summary in my own words. Forza Horizon 5 is used only as a reference for mechanics and scope.

## Forza Horizon 5 feature inventory and decisions

| Feature (FH5) | Decision | Reason |
|---|---|---|
| Large map with many biomes (about 11: desert, jungle, canyon, coast, farmland, volcano, swamp, city…) | ADAPT | 4 regions on a 4×4 km map: farmland, mountains, desert mesa, coast |
| Weekly seasons that change biomes (dry lakes open shortcuts, snow at altitude) | ADAPT | Weather states plus altitude snow colouring; no weekly seasons |
| Dynamic weather (rain, storms, fog) affects grip and visibility | ADOPT | Clear / cloudy / rain / fog / storm with a wetness → grip multiplier |
| Day/night cycle with dramatic sunsets | ADOPT | Sun and sky driven by hour; headlights and street lamps |
| Festival hubs | SKIP | Out of scope; no campaign |
| Road / dirt / cross-country races | ADAPT | Checkpoint road race plus a time trial on the 20+ km loop |
| Speed traps: speed at a single beam | ADOPT | Gate on the road, score = speed, personal best |
| Speed zones: average speed between two markers | ADOPT | Average speed over a road stretch |
| Drift zones: score from speed × angle | ADOPT | Slip angle × speed accumulation in a zone |
| Danger signs: jump ramps scored by distance | ADOPT | Ramps placed off long straights, scored by horizontal flight distance |
| Trailblazers (off-road A→B sprint) | SKIP (stretch) | Time limited |
| Collectibles, boards, barns | SKIP | Time limited |
| Car classes and performance index (D/C/B/A/S1/S2/X) | ADAPT | Own class letters computed from power/weight/grip |
| Upgrades and tuning | ADAPT | 6 upgrade categories, reduced tuning set |
| Paint, finishes, liveries | ADAPT | Colour plus gloss/matte/metallic finish, rim colour |
| Traffic (civilian cars on highways) | ADOPT | Lane-following traffic with pooling |
| Wildlife and ambient life | SKIP | Not enough time |
| HUD: speedo/tacho bottom-right, minimap bottom-left with GPS route | ADAPT | Own design; minimap with roads and heading |
| Photo mode | ADAPT | Free camera, FOV, DOF, hide HUD, screenshot |
| Assists: TCS, STM, ABS, braking line, auto/manual gearbox, rewind | ADAPT | TCS, STM, ABS, steering assist, auto/manual; no rewind |

## Godot 4.7 notes (checked against the installed 4.7.2)

- Jolt is the 3D physics engine in `project.godot`. I use a custom raycast vehicle on `RigidBody3D` with a 120 Hz tick.
- Terrain uses `HeightMapShape3D` for collision and `ArrayMesh` with vertex colours for rendering. Chunks are generated on `WorkerThreadPool`, and meshes are built on the main thread with a per-frame budget.
- Dressing uses `MultiMeshInstance3D` per chunk, with `visibility_range_end` on chunk nodes.
- The sky uses `WorldEnvironment` + `ProceduralSkyMaterial`, with volumetric fog for the fog and storm states.
- Engine and tyre audio are generated with `AudioStreamGenerator`.
- glTF: Blender +Y forward exports to glTF −Z, which is Godot's forward. The `-colonly` collision proxies are removed at runtime and replaced with code-built box shapes.

## Sources

- https://news.xbox.com/en-us/2021/07/26/exploring-the-biomes-and-seasons-of-forza-horizon-5/
- https://forza.net/news/exploring-forza-horizon-5-biomes-and-seasons
- https://racinggames.gg/forza/forza-horizon-5-complete-guide-to-scenery-and-seasons/
- https://mapmaster.io/games/forza-horizon-5-playstation/guides/Speed%20Trap
- https://mapmaster.io/games/forza-horizon-5-playstation/guides/Danger%20Sign
- https://mapmaster.io/games/forza-horizon-5-playstation/guides/Trailblazer
- https://docs.godotengine.org/en/stable/classes/class_heightmapshape3d.html
- https://platform.claude.com/docs/en/about-claude/pricing (pricing, verified 2026-10-23)

## Committed feature list (priority order)

1. Raycast vehicle with 10 data-driven cars, chase / hood / cockpit / bumper cameras
2. Procedural 4×4 km world: 4 regions, a 20+ km loop plus branch roads, bridges, tunnel shells
3. Chunked terrain streaming with collision
4. HUD, console, garage menu, debug menu, minimap
5. Lane-following traffic with 6 vehicle types
6. Day/night and weather with a grip effect
7. Speed traps, speed zones, drift zones, jumps, checkpoint race, time trial
8. Paint, upgrades, tuning, photo mode
9. Save/load
