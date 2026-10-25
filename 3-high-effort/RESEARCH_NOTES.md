# RESEARCH NOTES - Open-World Racer (Godot 4.7), inspired by Forza Horizon 5 (mechanics/structure only)

- Research date: 2026-10-23
- Author: research subagent (model: Claude Sonnet), gathered via web search + page fetches
- Scope: FH5 feature inventory, adopt/adapt/skip decisions for this project, Godot 4.7 technical caveats, final ranked feature list.
- Confidence legend used below: [S] = confirmed in a fetched/search source listed in section 5; [K] = from general game knowledge, not re-verified by a source in this session.
- Web tools worked. Several FH5 pages (official Forza support, Windows Central article body) could not be read in full; those items are marked [K] or "snippet only". Nothing here is copied text; all notes are paraphrased. No real brand names, car names, or map names will be used in the game.

---

## 1. Project constraints (recap, used for every decision below)

- ~4 x 4 km procedural map, 4 regions: farmland valley, mountain pass, desert canyon, coastal.
- 40-60 km of roads, exactly 10 original cars, civilian traffic.
- Dev console + garage menu; speed traps/zones, drift zones, jumps, checkpoint races, time trial.
- Day/night + weather (clear/cloudy/rain/fog/storm) with grip effects.
- Minimap + full map + GPS line; paint/upgrades/tuning; simple photo mode; save/load to user://.
- Explicitly out: online/multiplayer, story/campaign, real brands, weekly live-service seasons, auction house, houses/purchases, Eliminator.

---

## 2. FH5 feature inventory (by topic)

### 2.1 Open-world structure
- Setting is a fictionalised Mexico, roughly 1.5x the area of the previous game's map. [S: Xbox Wire, GTPlanet map]
- 11 distinct biomes: canyon, tropical coast, farmland, arid hills, jungle, living desert, rocky coast, sand desert, swamp, an urban colonial city, and a volcano (highest point, only snow). [S]
- Real locations are compressed and rearranged rather than geographically faithful - the map is a "greatest hits" collage, which is exactly the approach our 4-region map should take. [S]
- A central festival hub city sits near the middle; a long motorway crosses nearly corner to corner for fast cruising. [S]
- Dedicated pre-built venues exist (off-road oval/figure-eight facility, stadium, drag strips at airfields/ruins) alongside open roads. [S]
- Roads form a mixed network: tarmac highways, town streets with tunnels, dirt tracks, and off-road open terrain. Races reuse the same shared network via highlighted routes rather than separate track maps. [S/K]
- Terrain features change routing: swamp mangrove roots can be smashed through, a dry-season lake bed opens shortcuts, the volcano has both a tarmac and a dirt climb. [S]
- Audio reflects biome: canyons and the old town produce strong echo. [S]
- Key takeaway: biome = distinct look + distinct road character + distinct event flavour + distinct weather.

### 2.2 Seasons and weather
- Four seasons rotate on a weekly live-service cycle (spring/summer/autumn/winter); each season gives each biome different weather odds. [S/K]
- Weather is regional (unlike the previous game): the same moment can be a light shower in the desert and a torrential downpour in the jungle. [S: PC Gamer / TweakTown / pre-release coverage]
- Distinct weather hazards: thick dust storms in the dry season that crush visibility and can be seen approaching from afar; tropical storms hitting the coast with wind and flying debris (palms). [S]
- Wet season affects tyre smoke/heat visuals and surface wetness. [S: GTPlanet map]
- Rain darkens/glosses road, adds puddles and reduces grip; snow/ice appears only on the volcano. [S/K]
- Weather has driving consequences (grip, visibility, line choice), not just visual dressing; a difficulty-related "tourist" mode softens weather effects. [S: Stevivor headline only]
- Photo mode (later update) can override time of day and weather. [S]

### 2.3 Time of day
- Continuous day/night cycle with sun/moon, dawn and dusk golden hours, sky detail considered a showpiece (cloud art direction). [S: VGC headline / K]
- Headlights/illuminated HUD elements matter at night; auto-headlights follow time of day. [K]
- Time passes faster than real time; the Festival Playlist weekly cycle is separate from clock time. [K]

### 2.4 Road events and activities
- Race types: road, dirt, cross-country (point-to-point through open terrain with checkpoint gates), street scene/drag-style specials, plus special venue races. [S/K]
- Stunt / "PR stunt" family: Speed Traps (average speed past a fixed point, star-rated), Speed Zones (average speed over a stretch), Danger Signs (ramp jumps scored by distance), Drift Zones (scored on drift points, 1-3 stars). [S: fandom wiki, guides4gamers, mapmaster]
- Trailblazer-style cross-country timed routes. [S]
- Collectibles: bonus boards (smash for small rewards/fast-travel discounts), barn finds/treasure cars, treasure hunt hints, photo-op locations. [K, partial S]
- Festival hubs/outposts: events are unlocked by building outposts, which then spawn the event icons on the map. Horizon Rush outpost unlocks the stunt family. [S]
- Event map markers: coloured diamond-style icons on the map; starting an event places a route line on the road and a countdown. [K]
- Rewards: credits, XP, wheelspins (random reward), skill points. Star ratings (1-3) on stunts. [S/K]
- Photo challenges and car-collection challenges exist as seasonal tasks. [S/K]

### 2.5 Car roster, PI classes, customization, tuning, upgrades
- Roster is hundreds of licensed cars (we do not copy this). [S/K]
- Performance Index (PI) is a 0-999 score computed from the build's performance; classes: D (100-500), C (501-600), B (601-700), A (701-800), S1 (801-900), S2 (901-998), X (999+). Seven classes. [S: Windows Central snippet, Forza support FH3 page]
- PI changes when parts are installed, not when tuning sliders are moved. Tuning is "potential-neutral". [S]
- Upgrade categories (from the series): conversion (engine/drivetrain swaps, aspiration), engine parts, platform & handling (brakes, springs, anti-roll bars, weight reduction, chassis stiffness), drivetrain (clutch, transmission, driveshaft, differential), tyres & rims (compound, width), aero (front/rear), body kits. [K]
- Tuning sliders: tyre pressure, gear ratios/final drive, alignment (camber, toe, caster), anti-roll bars, springs, ride height, rebound/bump damping, aero downforce, brake balance/pressure, differential accel/decel. [S partial / K]
- Tunes are shareable as numeric codes (we will skip sharing). [S]
- Cosmetics: paint (colour + finish), vinyl groups, wheels, body parts, plates. [K]
- Car "Forzavista" showroom inspection and car-meet/garage presentation. [K]

### 2.6 Traffic, wildlife, ambient world life
- Light civilian traffic on roads, mostly near developed areas; community players noted it is sparse and has few pedestrians - the world is mostly vehicles and animals. [S: GTPlanet forum, opinion]
- Wildlife examples: flamingos, wild dogs, donkeys, goats, bighorn sheep; they scatter/react when approached. [S]
- Ambient decoration: fences and smashable props (signs, trees, crates), towns with market stalls and lights, birds, balloons, dust devils. [K]
- Rivals / drivatars populate routes in the live game (we skip). [S]

### 2.7 HUD, minimap, waypoint / GPS conventions
- Minimap in a corner, rotates with the car heading, shows nearby roads; roads not yet driven show in a distinct (orange) colour on map/minimap. [S]
- GPS route: a bright line painted on the road ahead (and on the minimap), with optional voice guidance; GPS voice can be disabled in audio options. [S]
- Waypoint set on the full map auto-draws a route; arrows/markers float in the world pointing to destination and event starts. [K]
- Speedometer + tachometer + gear indicator; assist icons flicker when ABS/TCS/STM intervene. [S: forum]
- HUD toggles: simple/standard/minimal, units km/h or mph. A roll indicator ("artificial horizon") can be turned off under accessibility. [S]
- Full map is a pannable/zoomable screen with filters for event types, fast-travel points, and waypoint placement. [K]
- Toast-style skill/stat popups for drifts, jumps, near misses (skill chain). [K]

### 2.8 Photo mode
- Camera-style controls: focus modes (tracking vs panning-style), aperture/depth of field, shutter, exposure (guide suggests mid value, check that tyre/rear panel detail still reads), filters/presets, hide HUD, free camera. [S: Prima Games, Forza photo guide]
- Later update added time-of-day and weather control, wheel angle controls, guides and portrait orientation. [S: Pure Xbox]
- Presets are closer to colour-grade presets than true adjustable-strength filters. [S: GTPlanet forum opinion]

### 2.9 Driving assists presentation
- Assist set: ABS (assisted braking), TCS (traction control), STM (stability management), steering assist / steering type (normal vs simulation), braking line (racing line coloured by braking zones), transmission (automatic, manual, manual with clutch), plus rewind (time reset) and difficulty presets. [S partial: community guidance / K]
- Racing line is a coloured ribbon on the road: neutral where flat out, a braking colour where lifting/braking is advised. [K, partial S: forum mentions braking line use]
- Community advice: keep ABS/TCS for beginners, STM often disliked as it blunts steering, manual gearbox yields slightly faster acceleration. [S: Forza forums, drifted.com]
- Rewind: short rewind of a few seconds on a button, limited or disabled in higher difficulty. [K]
- Assists are toggled in a settings page with a clear on/off per assist and a difficulty preset that sets them. [K]

---

## 3. Decision table

| Feature | Decision | One-line reason |
|---|---|---|
| Biome-driven open world with distinct regions | ADAPT | Use 4 hand-defined regions with a shared noise terrain and blended borders instead of 11 biomes. |
| Hub city / festival hub | ADAPT | A single "Meridian"-style hub settlement with garage and spawn, not a story festival. |
| Long corner-to-corner highway | ADAPT | One main arterial across the 4 km map to anchor the 40-60 km network. |
| Mixed road types (tarmac, dirt, mountain, town) | ADOPT | Core to variety; surface type drives grip and sound. |
| Tunnels, bridges | ADAPT | A few procedural tunnels/bridges for the mountain/coast regions only. |
| Off-road open-terrain cross-country | ADAPT | Support cross-country checkpoint gates without roads in the canyon/valley. |
| Regional weather (different per area) | SKIP | Single global weather state is cheaper and easier to explain via console. |
| Weekly seasons as live service | SKIP | No live service; replace with console-selectable weather. |
| Weather types with driving effects | ADOPT | Clear/cloudy/rain/fog/storm with grip multipliers and visibility changes. |
| Dust storm / tropical storm hazards | ADAPT | Fold into "storm" and "fog" presets (reduced visibility, wind sway on props). |
| Dynamic wetness (puddles/gloss) | ADAPT | Wetness scalar driving material roughness and grip; no true puddle sim. |
| Snow / ice | SKIP | No snow biome in the 4 regions. |
| Day/night cycle with golden hour | ADOPT | Sun/sky/ambient curves plus auto headlights; console can set time. |
| Road / dirt / cross-country races | ADAPT | Checkpoint races on road, dirt and cross-country gates only; no street-scene specials. |
| Time trial | ADOPT | Cheap to build on checkpoint code; supports ghost-less best-time storage. |
| Speed traps | ADOPT | Simple gate that measures speed at a point with 3-star thresholds. |
| Speed zones | ADOPT | Average speed over a stretch, same star system. |
| Drift zones | ADOPT | Scored drift segment with combo points and star ratings. |
| Danger sign jumps | ADOPT | Ramp markers scoring jump distance in metres. |
| Bonus boards / collectibles | ADAPT | A small number of smashable boards giving credits; skip barn finds. |
| Treasure hunts / barn finds | SKIP | Requires item economy and content we lack. |
| Photo challenges | SKIP | Needs scoring heuristics; the simple photo mode is enough. |
| Outpost-based event unlocking | ADAPT | Events unlocked by distance/credits via the garage menu, no outposts. |
| Wheelspins / random rewards | SKIP | Not needed; deterministic credits only. |
| Skill points / perks | SKIP | No progression tree in scope. |
| Credits + XP reward | ADAPT | Credits only, to pay for upgrades and paint. |
| Hundreds of licensed cars | SKIP | Exactly 10 original, brandless cars. |
| PI score + classes D to X | ADAPT | Compute a simple PI from engine/grip/mass; show classes D, C, B, A, S only for 10 cars. |
| Upgrade categories (engine, tyres, etc.) | ADAPT | 5-6 upgrade slots with stat modifiers feeding PI. |
| Engine/drivetrain swaps | SKIP | Too much content and balance work. |
| Tuning sliders (pressure, gearing, ARB, springs, alignment, brakes, diff) | ADAPT | Expose a subset that visibly changes the physics model. |
| Tune sharing codes | SKIP | Online-only. |
| Paint colour and finish | ADOPT | Simple material colour/metallic/roughness, high value, cheap. |
| Vinyl editor | SKIP | Too large; maybe a few preset stripes. |
| Showroom / Forzavista | ADAPT | Garage turntable view with doors-closed preview only. |
| Civilian traffic | ADOPT | Required; simple lane-following AI on the road graph. |
| Wildlife (herd animals) | ADAPT | A few ambient animal herds/birds, no gameplay effect. |
| Pedestrians | SKIP | Sparse in the source game too; not worth the cost. |
| Drivatar/rival AI | SKIP | Online-ish; use only checkpoint-race AI opponents if time allows. |
| Minimap with rotating heading | ADOPT | Core navigation HUD element. |
| Unexplored-road colouring on map | ADAPT | Optional; mark roads driven vs not driven on the full map. |
| Full pannable map with filters | ADOPT | Needed for waypoint and event navigation. |
| GPS line on road | ADOPT | Mesh/decal ribbon along the A* route plus minimap line. |
| GPS voice | SKIP | No VO assets; use short text prompts. |
| Speedometer/tach/gear HUD | ADOPT | Fundamental. |
| Assist icon flicker | ADOPT | Cheap feedback that teaches the assists. |
| TCS / ABS / STM / steering assist | ADAPT | Implement TCS, ABS, stability assist, steering assist; each toggleable. |
| Braking line / racing line | ADAPT | A coloured line on the race route only. |
| Auto / manual gears | ADOPT | Auto and manual (no clutch). |
| Rewind | ADAPT | Short rewind via stored transform ring buffer on a hotkey. |
| Difficulty presets | ADAPT | Three presets that set the assist toggles. |
| Photo mode (basic) | ADAPT | Free camera, FOV, DoF, exposure, hide HUD, time/weather, save PNG to user://. |
| Photo filters | ADAPT | 3-4 colour-grade presets, no adjustable strength. |
| Save/load progress | ADOPT | JSON in user:// for credits, cars, upgrades, paint, tunes, records. |
| Dev console | ADOPT | Teleport, set time/weather, give credits, spawn traffic, toggle debug. |
| Online / multiplayer / drivatars | SKIP | Out of scope. |
| Story / campaign | SKIP | Out of scope. |
| Real car brands | SKIP | Original names/designs only. |
| Auction house | SKIP | Out of scope. |
| Houses / property purchases | SKIP | Out of scope. |
| Eliminator and other live modes | SKIP | Out of scope. |
| Event Lab (track creator) | SKIP | Out of scope. |
| Smashable props | ADAPT | A handful of breakable signs/fences using simple physics bodies. |
| Echo / environment audio | ADAPT | Reverb bus changes in tunnels and canyon. |

---

## 4. Godot 4.7 technical notes and caveats

Documentation was checked on docs.godotengine.org (stable). The class pages were fetched individually; see Section 5.

### 4.1 VehicleBody3D / VehicleWheel3D
- Official class docs explicitly warn: "known issues" and "not designed for realistic vehicle physics". Treat it as an arcade-grade rig. [S]
- For realistic vehicles, docs suggest building a custom model on RigidBody3D (or CharacterBody3D). Gears are not simulated at all; gearing, RPM and torque curve must be our own code. [S]
- Control values: `engine_force` only applies via wheels with `use_as_traction` and ground contact; `brake` only works when wheels touch; `steering` is radians in code (degrees in inspector). [S]
- Documentation hint for a 1000 mass body: brake roughly 25-30, engine force roughly 25-50. Default mass is 40, so mass must be set. [S]
- Do not move/rotate the node directly during play (use control properties or teleports carefully); local forward is `Vector3.MODEL_FRONT` (i.e. -Z convention for the model front). [S]
- VehicleWheel3D defaults to keep in mind: `wheel_friction_slip` default 10.5 but docs say start near 1.0; `suspension_stiffness` guide: under 50 off-road, 50-100 race cars; `suspension_max_force` must exceed a quarter of the body mass (3-4x recommended); `damping_relaxation` should be a bit higher than `damping_compression`; `wheel_rest_length` should not be set to 0 and then repositioned; `wheel_roll_influence` low values make rollovers likely. [S]
- Jolt compatibility: the official Jolt page does not mention VehicleBody3D, and the VehicleBody3D page does not mention Jolt. A forum report on Godot 4.7.1 says VehicleBody3D works under Jolt but RigidBody3D attached via joints float away on it (not seen in Godot Physics). Joints are the main known Jolt gap. [S: forum.godotengine.org result, snippet only]
- Decision: given the weak documentation and 10 cars needing different handling, the recommended path is a custom raycast-suspension RigidBody3D vehicle (4 ray casts or shape casts, own tyre force model: slip angle lateral force + longitudinal traction + friction circle). VehicleBody3D remains an acceptable fallback. [Recommendation, based on S]

### 4.2 Jolt Physics (4.4+)
- Built-in since 4.4; per the current stable docs, new projects use Jolt by default (older projects switch under Project Settings > Physics > 3D > Physics Engine, then restart). [S]
- Supported/changed: Area3D vs SoftBody3D interactions; body_entered-style overlap signals; raycast `face_index` is -1 unless enabled (about 25% more memory for concave shapes). [S]
- Limits: many joint soft-limit properties unsupported (they warn); single-body joints treat the body as node B; kinematic-vs-static contacts are not reported by default; contact impulses are estimates; `WorldBoundaryShape3D` has a much smaller effective size; running on a separate thread is experimental. [S]
- Collision margin is handled differently (shape shrunk then margin added). Very small margin fractions can give odd results. Baumgarte stabilisation only corrects position, so deep penetrations resolve slowly. [S]
- Ghost collisions between separate bodies are not fully removed by internal-edge handling; for road surfaces use few large trimesh/heightmap pieces or a single heightfield per chunk rather than many tiny coplanar pieces. [S + inference]
- Continuous collision settings are now fractions (e.g. `continuous_cd_movement_threshold`); fast cars should have CCD enabled on the vehicle body. [S]
- A fixed temporary memory buffer exists (Temporary Memory Buffer Size setting); a big streamed world with many bodies may need it raised. [S]

### 4.3 Physics tick rate for fast vehicles
- Default fixed step is 60 Hz; docs say always use `delta` in `_physics_process`. Determinism is not guaranteed. [S]
- The physics intro page does not discuss tunnelling or the `physics_ticks_per_second` setting by name. [S]
- Recommendation (engineering judgement, not from docs): raise physics ticks to 120 Hz for stable suspension at 200+ km/h (about 55 m/s moves 0.9 m per 60 Hz step); keep tyre force logic in `_physics_process`/`_integrate_forces`, and give the car body CCD. Cost: traffic AI should run at a lower rate (e.g. 20-30 Hz) on a separate cadence. [Recommendation]
- Use `_integrate_forces()` for applying forces/velocity edits to RigidBody3D. [S]

### 4.4 MultiMeshInstance3D and visibility ranges
- MultiMesh draws many copies in one primitive; set `transform_format` BEFORE `instance_count`; use `visible_instance_count` to show a subset; allocate the maximum up front. [S]
- No per-instance frustum culling: all instances draw or none, so split world scatter (trees, rocks, grass, lamp posts) into per-chunk MultiMeshes. [S]
- Per-instance variation uses `INSTANCE_ID`/`INSTANCE_CUSTOM` in shaders. For bulk updates from script use `RenderingServer.multimesh_set_buffer()` rather than thousands of per-instance calls. [S]
- Visibility ranges live on GeometryInstance3D: `visibility_range_begin/end`, margins, and `visibility_range_fade_mode`. [S]
- Caveat: fade modes (`SELF`, `DEPENDENCIES`) only work in Forward+. In Mobile/Compatibility they act as DISABLED with hysteresis off. Use FADE_DISABLED (hysteresis margin) for cheapest manual LOD. [S]
- The MultiMesh page does not mention visibility ranges; apply the range to the MultiMeshInstance3D node of each chunk (the whole chunk fades). [S + inference]
- The MultiMesh page notes it may be out of date for 4.7; verify with a quick test.

### 4.5 WorkerThreadPool and threading
- `add_task(callable, high_priority, description)` and `add_group_task(callable, elements, tasks_needed, ...)` are available; every task must be waited on with `wait_for_task_completion` / `wait_for_group_task_completion`, or its resources leak. [S]
- Waiting can return ERR_BUSY (deadlock guard). Spreading cheap work across threads can be slower than single threaded. [S]
- Thread-safety rules: the active scene tree is not thread-safe (use `call_deferred`/`set_deferred`); you can build node trees off-tree on a thread and add them from the main thread; do not mutate one Resource from several threads; one loader at a time. [S]
- Rendering objects/GPU calls from threads are risky by default; physics is not thread-safe unless "Run on Separate Thread" is enabled (experimental with Jolt). [S]
- Safe: servers (mostly), navigation queries and resources, reading/writing GDScript array/dict elements (resizing needs a mutex). Not safe: sharing one AStar2D/AStar3D/AStarGrid2D between threads. [S]
- Plan: generate terrain chunk heights, road splines, and mesh arrays (PackedVector3Array etc.) in worker tasks; create ArrayMesh/nodes and collision shapes on the main thread. Give each worker its own AStar instance if routing is threaded. [Recommendation]

### 4.6 AudioStreamGenerator (engine sound)
- Generates audio from script: `mix_rate` (default 44100) and `buffer_length` (default 0.5 s). Shorter buffer = lower latency but higher CPU and crackle risk. [S]
- Docs say it is best used from C# or GDExtension; with GDScript, lower the mix rate (11025 or 22050 Hz are suggested). [S]
- No resampling is done; match `mix_rate_mode`/rate with your data. Push frames through `AudioStreamGeneratorPlayback` after checking `get_frames_available()`. [S]
- Engine sound plan: synthesise a looped harmonic + noise engine at 22050 Hz in blocks sized from `get_frames_available()`, driven by RPM and throttle; fallback is pitch-shifting a pre-generated looped AudioStreamWAV. [Recommendation]

### 4.7 Other cautions
- Heightmap terrain: use chunked meshes with HeightMapShape3D or trimesh per chunk; avoid very large trimesh bodies.
- All asset generation (meshes, textures, sounds) must be procedural or from the project's own folder; save games and screenshots go to `user://`.
- Always test the 4.7 docs claims against the actual editor build (the docs pages themselves flag possible staleness).

---

## 5. Source URLs (pages actually used)

Fetched in full (page body read):
1. https://docs.godotengine.org/en/stable/classes/class_vehiclebody3d.html
2. https://docs.godotengine.org/en/stable/classes/class_vehiclewheel3d.html
3. https://docs.godotengine.org/en/stable/tutorials/physics/using_jolt_physics.html
4. https://docs.godotengine.org/en/stable/tutorials/physics/physics_introduction.html
5. https://docs.godotengine.org/en/stable/classes/class_geometryinstance3d.html
6. https://docs.godotengine.org/en/stable/classes/class_visualinstance3d.html
7. https://docs.godotengine.org/en/stable/tutorials/performance/using_multimesh.html
8. https://docs.godotengine.org/en/stable/classes/class_workerthreadpool.html
9. https://docs.godotengine.org/en/stable/tutorials/performance/thread_safe_apis.html
10. https://docs.godotengine.org/en/stable/classes/class_audiostreamgenerator.html
11. https://news.xbox.com/en-us/2021/07/26/exploring-the-biomes-and-seasons-of-forza-horizon-5/
12. https://www.gtplanet.net/forza-horizon-5-map-revealed-20210809

Used via search-result summaries (snippets, not read in full):
13. https://gtplanet.net/here-are-the-11-biomes-featured-in-forza-horizon-5
14. https://www.pcgamer.com/au/seasons-return-in-forza-horizon-5-with-one-important-twist
15. https://www.tweaktown.com/news/80234/forza-horizon-5s-localized-weather-system-brings-tons-of-variety/
16. https://stevivor.com/features/in-depth/forza-horizon-5-tourist-difficulty-changes-to-weather-detailed
17. https://www.videogameschronicle.com/news/forza-horizon-5s-art-team-explains-how-it-got-the-skies-to-look-so-realistic
18. https://www.windowscentral.com/forza-horizon-5-upgrading-guide (body not retrievable; PI ranges from search snippet)
19. https://support.forza.net/hc/en-us/articles/360005372033-FH3-Performance-Index-and-Classes
20. https://forum.forza.net - https://forums.forza.net/t/lets-discuss-performance-index-classes-pi/577894
21. https://forza.fandom.com/wiki/Forza_Horizon_5/Series_5
22. https://guides4gamers.com/forza-horizon-5/maps/mexico/
23. https://mapmaster.io/games/forza-horizon-5-playstation/guides/Drift Zone
24. https://www.gfinityesports.com/forza-horizon-5/turn-off-narrator/
25. https://racinggames.gg/article/how-to-turn-off-the-artificial-horizon-in-forza-horizon-5
26. https://forums.forza.net/t/what-driver-assists-to-use/58248
27. https://drifted.com/forza-horizon-5-drift-tune
28. https://primagames.com/gaming/forza-horizon-5-photo-mode
29. https://forza.net/news/forza-photo-guide
30. https://www.purexbox.com/news/2023/05/news/2023/05/forza-horizon-5-update-21-is-huge-featuring-all-new-photo-mode-options-and-more
31. https://embed.gamereactor.eu/forza-horizon-5-to-feature-drag-racing-convertibles-and-wild-animals/
32. https://www.gtplanet.net/forum/threads/forza-horizon-5-general-discussion.399481/
33. https://gamefromscratch.com/godot-4-4-gets-native-jolt-physics-support/
34. https://forum.godotengine.org/t/jolt-physics-causing-floaty-springy-joints/142182

Total: 34 URLs (12 read in full, 22 via search snippets). Not verified directly: official FH5 support pages for assists/rewind, the full FH5 upgrade menu, bonus boards details, and the Godot VehicleBody3D+Jolt interaction (no official statement found).

---

## 6. Final committed feature list (ranked by priority)

Priority order follows build order: a feature is only started once everything above it is playable.

1. Driving model and camera
   - Custom raycast-suspension RigidBody3D car (VehicleBody3D as fallback), tyre force model with surface-type grip, engine/gearbox with auto + manual, handbrake.
   - 120 Hz physics, CCD on body, chase / hood / bumper cameras with speed-based FOV and shake.
   - Assists: TCS, ABS, stability, steering assist, rewind (transform buffer).
2. Terrain and roads
   - Chunked procedural heightmap terrain with 4 regional height/colour profiles blended at borders.
   - Spline road network generation: surface types (tarmac, dirt), banked curves, collision, road markings; worker-thread generation, main-thread mesh/collision creation.
3. HUD, console and garage menu
   - Speedo/tach/gear, assist icons, event prompts, dev console (teleport, time, weather, credits, spawn, debug), garage menu skeleton, pause/settings menu.
4. Traffic
   - Lane-following civilian cars on the road graph, simple avoidance and braking, density by region, despawn by distance, lower AI tick rate.
5. Regions and a 40-60 km road network
   - Farmland valley, mountain pass, desert canyon, coastal: distinct terrain, props, colour grading, road character; arterial plus connecting loops; props scattered with MultiMesh per chunk and visibility ranges.
6. Ten cars
   - Exactly 10 original, brandless cars covering FWD/RWD/AWD, hatch/coupe/muscle/SUV/rally/supercar style archetypes, each with its own mass, power curve, suspension and grip; procedural body meshes and PI/class label (D to S).
7. Day/night and weather grip
   - Sun/sky/ambient curves, auto headlights, clear/cloudy/rain/fog/storm with grip multiplier, visibility (fog density), wetness-driven roughness, rain/fog particles and sound, wind sway in storm.
8. Settlements, bridges, tunnels
   - Hub settlement with garage; farmland and coastal villages; a few bridges over water/canyon; tunnels in the mountain pass with reverb.
9. Activities
   - Checkpoint races (road, dirt, cross-country), time trial with saved best times, speed traps, speed zones, drift zones, danger-sign jumps, bonus boards; star ratings and credit rewards.
10. Customization, tuning, photo mode
    - Paint (colour/metallic/roughness), 5-6 upgrade slots affecting PI, tuning sliders (tyre pressure, gearing, springs, anti-roll, alignment, brakes, diff), simple photo mode (free camera, FOV, DoF, exposure, hide HUD, time/weather, PNG to user://).
11. Minimap, full map and GPS
    - Rotating minimap, pannable full map with event filters and waypoints, GPS ribbon on the road plus minimap line using road-graph A* (own AStar instance for any threaded use), driven-road colouring (optional).
12. Save/load
    - JSON in user:// for credits, owned cars, paint, upgrades, tunes, records, settings, last position, time of day and weather.
13. Polish
    - Engine audio via AudioStreamGenerator (or looped fallback), tyre/skid/wind/rain sounds, smashable props, wildlife herds/birds, post-process tuning, performance pass (LOD, chunk streaming), bug fixing, final menu/UX pass.

### Cut line if time runs short
- Keep 1-7 at full quality; trim 8 to the hub + one tunnel + one bridge; trim 9 to races, time trial, speed trap, drift zone, jump; reduce 10 to paint + tuning subset + basic photo mode; 11 minimal but functional; 12 mandatory (simple); 13 only audio and performance.
