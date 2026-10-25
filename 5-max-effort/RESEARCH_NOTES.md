# Research Notes — Ridgeline Festival

Research date: 2026-10-23. Method: a research subagent (same session, model inherited: Claude Opus 5.5) used
WebSearch/WebFetch on ~56 game sources and 16 Godot documentation pages; its draft was reviewed and condensed here.
Several official Forza support pages and the fandom wiki were blocked (HTTP 403/402) — facts that rely only on
search snippets are marked *(snippet)*. Everything below is summarised in our own words. **No names, map, art,
audio, UI or text from the reference game are used in our project** — the reference game is only a source of
mechanics and scope ideas.

Engine facts were additionally verified locally against the installed engine by dumping its class reference
(`Godot_v4.7.2-stable_win64_console.exe --headless --doctool`) and by running drive tests (see DEVELOPMENT.md).

---

## 1. Feature inventory of the reference game (as understood)

### 1.1 World structure
- One continuous map with ~11 distinct biomes (canyon, tropical coast, farmland, arid hills, jungle, cactus desert,
  rocky coast, sand desert, swamp, an old town and a snow-capped volcano). Each biome has its own vegetation,
  ambient audio/reverb and seasonal behaviour; a landmark mountain is visible from most of the map.
- Road network mixes a long multi-lane highway (where the fastest speed cameras sit), twisty old-town streets and
  tunnels, mountain switchbacks (one paved, one dirt), lots of dirt roads and few barriers, so cutting across open
  terrain is normal. Roads are wider than real ones for arcade comfort.
- Events are mapped onto road geometry: tarmac sprints/circuits, dirt trails, cross-country, street races (often at
  night), drag strips; open-world stunts sit where geometry suits them (straight = speed camera, flowing section =
  average-speed zone, corner run = drift zone, crest/ramp = jump, two gates across country = timed run).
- A main festival hub plus regional outposts, each unlocking one activity family; houses as perks and fast-travel nodes.

### 1.2 Weather, seasons, time of day
- A global weekly season (hot / wet / storm / dry) with regionally different weather: rain in one biome while another
  is dry; dust storms and tropical storms as moving volumetric weather visible from afar; snow only at altitude.
- Wet tarmac clearly reduces grip, dirt turns muddy, fog/dust/rain reduce visibility.
- Continuous day/night cycle (~1 h 40 min real time per cycle, short night — unofficial figures); skies from captured
  HDR time-lapses curated into thousands of presets; photo mode can override time and weather.

### 1.3 Open-world activities
- Speed trap (speed at a camera beam), speed zone (average speed between two beams; leaving the road fails),
  drift zone (score from angle × speed through a section), danger-sign jump (distance flown, must land cleanly),
  timed point-to-point gate run. Each has three star thresholds visible on the map and a best score.
- Collectibles: smashable boards (XP and fast-travel discount), hidden "barn" cars found inside a search circle,
  photo challenges, treasure hunts, playlists with weekly tasks.
- Skill chains: named skills (drift, near miss, air, speed, wreckage, drafting, …) extend a chain with a stepped
  multiplier; a crash loses the chain, a timeout banks it; banked score feeds skill points.

### 1.4 Cars
- Huge licensed roster; one Performance Index (PI) number with class bands D/C/B/A/S1/S2/X *(snippet + guides)*.
- Upgrade shop in six groups (conversion, aero, tyres/rims, drivetrain, platform/handling, engine); upgrading parts
  unlocks matching tuning tabs (tyre pressure, gearing, alignment, anti-roll bars, springs, damping, aero, brakes,
  differential).
- Livery editor, car viewer, launch control, convertible roofs.

### 1.5 World life
- Civilian traffic (sparse online, denser solo) used as obstacles and for near-miss scoring; occasional freezes/pop
  reported by reviewers.
- Region-specific wildlife (birds, flamingos, goats, …), destructible fences/signs/cacti, wind-blown vegetation,
  biome soundscapes.

### 1.6 HUD and navigation
- Speedometer and minimap in the lower corners, mostly transparent; small gear readout that flashes at the limiter;
  skill-chain text centre screen. Many elements toggleable; units metric/imperial; accessibility options.
- World map with filterable categories; waypoint creates a GPS route shown on the minimap; the optional driving line
  doubles as an on-road route line coloured by required braking.

### 1.7 Photo mode
- Pauses the game; free camera near the car; FOV, aperture/depth of field, focus, shutter-speed blur, exposure and
  colour controls, filters; time/weather override; HUD hidden; separate drone scout camera.

### 1.8 Assists
- Driving/braking line (full / braking only / off), braking (assisted / ABS / no ABS), steering (auto / assisted /
  standard / simulation), traction control and stability control on/off, automatic/manual gearbox, damage & tyre
  wear mode, rewind, launch control, AI difficulty ladder; fewer assists → bigger payout.
- Handling is a lightly simplified simulation: per-wheel load-dependent grip, higher-than-real cornering speeds,
  forgiving slides and jumps.

---

## 2. Decisions — ADOPT / ADAPT / SKIP

| Reference feature | Decision | Reason |
|---|---|---|
| Distinct biomes/regions | **ADAPT** | 4 regions + lake/river valley inside 4×4 km (farmland valley, highlands, canyon desert, coast) instead of 11 biomes. |
| Long highway for top-speed runs | **ADOPT** | Our dual-carriageway crosses the map; hosts speed traps and the long fast stretch. |
| Mountain switchbacks, paved + dirt | **ADOPT** | Highland pass with hairpins (paved) and a gravel summit track. |
| Town street racing / old town tunnels | **SKIP** | Spec forbids a city; small villages only. Tunnels are kept on the mountain pass. |
| Dirt trails and cross-country | **ADOPT** | Dirt/gravel tracks and cross-country shortcuts with surface-specific physics. |
| Few barriers, drive almost anywhere | **ADAPT** | Open terrain is drivable; guard rails only on drops, bridges and tunnel approaches. |
| Main festival hub + outposts | **ADAPT** | One festival hub site (decorative + spawn point + garage); no unlock progression (spec: no campaign). |
| Fast travel / houses | **ADAPT** | Free teleport via console/debug menu/map to regions and long-road start points; no houses. |
| Weekly seasons | **SKIP** | Single session demo; weather states selectable instead. |
| Regional weather, dust & storms | **ADAPT** | Global weather states (clear/cloudy/rain/fog/storm) + biome rules: dust in the desert, snow particles above the snow line. |
| Wet grip penalty, mud | **ADOPT** | Wetness lowers per-surface grip (asphalt ×0.72 when fully wet). |
| Day/night cycle with short night | **ADOPT** | Continuous cycle, configurable speed, console `time <hour>`. |
| Captured HDR skies | **ADAPT** | Procedural sky shader with sun/moon/stars/clouds keyed by weather and time. |
| Speed trap | **ADOPT** | Gate on a long straight; score + personal best + star thresholds. |
| Speed zone | **ADOPT** | Average speed between two gates; leaving the road fails. |
| Drift zone | **ADOPT** | Score from slip angle × speed while on the road section. |
| Danger-sign jump | **ADOPT** | Ramps/crests with distance measurement; clean-landing rule. |
| Timed gate run (trailblazer) | **ADAPT** | Implemented as time trial on the scenic loop + checkpoint road races. |
| Road races with AI | **ADAPT** | Checkpoint races vs the clock; AI opponents only as a stretch goal. |
| Collectibles (boards, barn finds) | **ADAPT** | Smashable festival boards along roads + hidden "barn" collectibles (stretch). |
| Skill chains | **ADAPT** | Lightweight skill chain (drift, near miss, air, speed) with multiplier, banked into credits. |
| PI number + class bands | **ADAPT** | Own PI formula from power/weight, grip, top speed, aero; bands D–S2 for UI labels. |
| Upgrades unlock tuning tabs | **ADAPT** | Upgrades (engine, tyres, suspension, brakes, weight, aero) are data-driven; tuning sliders always available (reduced set). |
| Livery editor | **SKIP** | Too large; paint colour + finish + stripe variants + rim style/colour instead. |
| Car viewer | **ADAPT** | Garage menu with orbit camera around the parked car. |
| Launch control | **ADAPT** | Clutch-slip launch rpm model handles standing starts automatically. |
| Traffic | **ADOPT** | Lane-graph traffic with pooling, LOD, intersections, collision reactions (spec requirement). |
| Near-miss scoring | **ADOPT** | Part of the skill chain. |
| Wildlife | **SKIP** (stretch) | Birds as ambient particles at most; time better spent on cars/roads. |
| Destructible scenery | **ADAPT** | Smashable boards/fences only where cheap (physics props spawned on hit). |
| Lower-corner speedo + minimap | **ADOPT** | Common genre convention; own original visual design. |
| World map + waypoint + GPS line | **ADOPT** | Full map (M), click waypoint, A* route on minimap and as an on-road line. |
| Driving line coloured by braking | **ADAPT** | Optional braking-line assist computed from road curvature ahead. |
| Photo mode | **ADOPT** | Free camera, FOV, DOF, exposure, time/weather freeze, hide HUD, screenshot key. |
| Drone mode | **SKIP** | Photo-mode free camera covers it. |
| Assists TC/SC/ABS/steering/auto-gear | **ADOPT** | All implemented in the vehicle controller with console/menu toggles. |
| Rewind | **ADOPT** (stretch) | Ring buffer of car states. |
| Damage/tyre wear | **SKIP** | Cosmetic impact feedback only. |
| Online, auction, accolades, wheelspins | **SKIP** | Single-player free-roam scope. |
| Credits economy | **ADAPT** (stretch) | Persistent credits from activities, shown in HUD; no shop gating. |
| Accessibility (text size, units, colour) | **ADAPT** | Units toggle, HUD toggle, readable sizes at 1080p; colour-safe palette. |

---

## 3. Godot 4.7 engine notes that shaped the design

- **Jolt** is the project's physics engine (`physics/3d/physics_engine = "Jolt Physics"`); settings live under
  `physics/jolt_physics_3d/*` (verified in the installed class reference). Jolt treats ConcavePolygon/HeightMap edges
  with active-edge detection; ghost hits between *different* bodies remain possible → few large static bodies per tile.
- **VehicleBody3D**: the docs state it has known issues and is not intended for realistic handling (no gearbox, simple
  friction-slip tyres). Our measured comparison confirms this (see DEVELOPMENT.md) → **custom raycast vehicle on
  RigidBody3D** chosen.
- **HeightMapShape3D**: grid spacing is 1 unit; other spacings via scaling the shape node; GodotPhysics needs uniform
  scale and no scaling on dynamic bodies; Jolt supports scaled heightmaps; NaN heights create holes. We use uniform
  scale with heights pre-divided.
- **glTF import**: `-col/-convcol/-colonly/-convcolonly` suffixes exist; we build vehicle collision in code from an
  exported `Collision_Hull` mesh (convex) for precise control.
- **Visibility ranges** (`visibility_range_begin/end/_margin`, fade modes, `visibility_parent` HLOD) + automatic mesh LOD
  on import → used for dressing and props; MultiMesh for vegetation.
- **WorkerThreadPool** for chunk mesh generation; scene-tree changes only on the main thread (call_deferred).
- **Large worlds**: single precision is comfortable up to ~4–8 km from the origin; our map spans ±2 km → no origin
  shifting planned (to be verified at the map edges).
- 4.7 adds an energy-conserving clearcoat suited to car paint (used by our paint materials).

---

## 4. Final committed feature list (priority order)

1. Custom raycast vehicle physics (suspension, tyres per surface, drivetrains, gearbox, aero, assists) — data-driven per car.
2. Chase / hood / cockpit / bumper cameras with speed FOV, collision, shake.
3. Blender-authored car pipeline (MCP → .glb → Godot) — 10 original player cars with interiors.
4. Procedural, seeded 4×4 km world: heightmap with road carving, 4 regions, river, coast, chunk streaming.
5. Connected road network 40–60 km: highway, valley roads, mountain pass with hairpins and tunnel, coastal road,
   desert roads, dirt/gravel tracks, bridges, junctions; ≥20 km scenic loop and ≥5 km uninterrupted stretches.
6. HUD (speedo/tacho/gear/assists/surface), region popups, notifications.
7. Developer console, graphical garage menu, benchmark/debug menu.
8. Civilian traffic on a lane graph (6 Blender vehicle types, pooling, LOD, intersections, collisions).
9. Day/night cycle and weather (clear/cloudy/rain/fog/storm) with grip effects, rain/dust/snow particles.
10. Settlements, roadside furniture, vegetation, landmarks (lighthouse, wind farm, castle ruin, gas stations, harbour).
11. Activities: speed traps, speed zones, drift zones, jumps, checkpoint races, scenic-loop time trial.
12. Customisation (paint/finish/rims), upgrades with stat comparison, tuning sliders, photo mode.
13. Minimap, full map with waypoint, GPS route line.
14. Save/load of car, paint, upgrades, position, time, weather, settings, personal bests.
15. Audio: generated engine, tyre, wind, impact, horn and ambience sounds.
16. Polish, performance and QA.

---

## 5. Sources

Reference-game sources (read):
- https://forza.net/news/exploring-forza-horizon-5-biomes-and-seasons
- https://www.gtplanet.net/here-are-the-11-biomes-featured-in-forza-horizon-5
- https://en.wikipedia.org/wiki/Forza_Horizon_5
- https://ukstories.microsoft.com/features/forza-horizon-5-xbox-unveils-largest-ever-world-in-the-driving-franchise/
- https://news.xbox.com/en-us/2021/11/04/gaming-for-everyone-the-accessibility-features-of-forza-horizon-5/
- https://forza.net/news/forza-photo-guide
- https://gamingbolt.com/forza-horizon-5-weather-conditions-detailed-eliminator-and-super-7-return
- https://www.videogameschronicle.com/news/forza-horizon-5s-art-team-explains-how-it-got-the-skies-to-look-so-realistic
- https://www.nme.com/news/forza-horizon-5-will-bring-back-seasonal-weather-but-with-a-new-change-2970061
- https://traxion.gg/seasonal-conditions-and-unique-areas-explained-in-forza-horizon-5/
- https://racinggames.gg/forza/forza-horizon-5-mexico-map-deep-dive/
- https://mapmaster.io/games/forza-horizon-5-playstation/guides/Speed Trap (and Speed Zone, Drift Zone, Danger Sign, Trailblazer, Barn Find, Showcase, Expedition, Festival Site pages)
- https://racinggames.gg/forza/forza-horizon-5-bonus-boards-how-to-find-every-xp-and-fast-travel-board/
- https://traxion.gg/heres-how-the-festival-playlist-works-in-forza-horizon-5/
- https://www.purexbox.com/news/2023/05/forza-horizon-5-update-21-is-huge-featuring-all-new-photo-mode-options-and-more
- https://insider-gaming.com/every-skill-in-forza-horizon-5-how-to-earn-an-ultimate-skill-chain/
- https://hackernoon.com/forza-horizon-5-cars-guide-how-to-build-and-tune-for-optimal-road-race-performance
- https://racinggames.gg/article/forza-horizon-5-major-handling-upgrades-revealed
- https://caniplaythat.com/2021/11/04/forza-horizon-5-accessibility-menu-deep-dive/
- https://www.pcgamesn.com/forza-horizon-5/accessibility-tourist-difficulty
- https://www.ludo.guide/guide/forza-horizon-5/racing-line
- https://racinggames.gg/forza/forza-horizon-5-how-to-use-drone-mode-menus-controls-use
- https://www.purexbox.com/news/2021/07/new_forza_horizon_5_details_confirm_convertibles_drag_races_and_flamingos
- https://www.dsogaming.com/pc-performance-analyses/forza-horizon-5-will-only-feature-ray-tracing-in-forzavista-will-not-support-mods/
- https://www.gtplanet.net/forza-horizon-5s-new-livery-editor-revealed/
- https://www.thegamer.com/interview-playground-games-forza-horizon-5/
- https://www.carthrottle.com/post/8-things-we-learned-from-playing-forza-horizon-5
- https://mechanicsofmagic.com/?p=6144 (HUD analysis of the predecessor)
- Snippet-only (blocked): https://support.forza.net/hc/en-us/articles/360005363194-Difficulty-Assists-and-Drivatars ,
  https://support.forza.net/hc/en-us/articles/360005372033-FH3-Performance-Index-and-Classes , https://forza.fandom.com/wiki/PR_Stunts

Godot documentation (read):
- https://docs.godotengine.org/en/stable/tutorials/physics/using_jolt_physics.html
- https://docs.godotengine.org/en/stable/classes/class_vehiclebody3d.html
- https://docs.godotengine.org/en/stable/classes/class_vehiclewheel3d.html
- https://docs.godotengine.org/en/stable/classes/class_heightmapshape3d.html
- https://docs.godotengine.org/en/stable/classes/class_collisionshape3d.html
- https://docs.godotengine.org/en/stable/tutorials/assets_pipeline/importing_3d_scenes/node_type_customization.html
- https://docs.godotengine.org/en/stable/tutorials/assets_pipeline/importing_3d_scenes/advanced_import_settings.html
- https://docs.godotengine.org/en/stable/tutorials/3d/visibility_ranges.html
- https://docs.godotengine.org/en/stable/classes/class_workerthreadpool.html
- https://docs.godotengine.org/en/stable/tutorials/performance/thread_safe_apis.html
- https://docs.godotengine.org/en/stable/tutorials/physics/large_world_coordinates.html
- https://godotengine.org/releases/4.6/ , https://godotengine.org/releases/4.7/
