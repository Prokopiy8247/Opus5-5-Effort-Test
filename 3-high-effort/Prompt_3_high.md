# Claude Opus 5.5 — Godot 4.7 + Blender MCP Forza-Horizon-Style Open-World Racing Benchmark

## Run parameters (filled in by the user before launch — each agent sees only its own values)

```text
Effort level under test:  high            (low | medium | high | xhigh | max | ultracode)
Project folder:           W:\YouTube\Opus 5.5 Effort Test\3. Opus 5.5 Forza High Effort\3.-opus-5.5-forza-high-effort             (contains project.godot)
Master Blender file:      Opus55ForzaHighEffort.blend              (in the project folder)
Blender MCP host/port:    localhost : 9879
Expected MCP server name: not predeclared - discover it from the tool descriptions of the connection on the port above
Final report file:        OPUS_5.5_FINAL_REPORT.md
Run directory prefix:     .opus-5.5-forza-godot-runs/
```

The scope of the task is **identical for every effort level**. Effort only changes how deeply you reason, not how much you are expected to build. Do not shrink the scope, skip verification or stop early because of your effort setting.

---

## Mission

You are the sole lead developer, technical artist and QA engineer of the **existing Godot 4.7 project in the project folder currently opened in this Claude agent**.

Build the most complete and polished **open-world arcade-sim racing game in the spirit of Forza Horizon 5** that you can achieve during this autonomous session.

The game must be an **original project**. Use Forza Horizon 5 only as a *mechanics, structure and feature-scope reference*. Do not copy its maps, names, logos, car models, textures, audio, UI artwork, code or any proprietary content, and do not use Forza/Playground Games/Microsoft branding anywhere. Choose your own original game title.

The game launches directly into free roam in a drivable car on a long scenic road. There is no story and no campaign.

### Design pillars

1. **Long, beautiful countryside roads.** A large open world dominated by **long rural and inter-regional roads**: highways, sweeping valley roads, mountain passes with switchbacks, dirt and gravel tracks, coastal roads, bridges and tunnels. It is **not** a city game. Only **small settlements** (villages, hamlets, farms, gas stations, a few roadside points of interest).
2. **Map scale.** Target roughly **4 km × 4 km (about 16 km²)** with **40–60 km of drivable road**, including at least one continuous scenic loop of **20 km or more**. This is deliberately much smaller than the real Forza Horizon 5 map. Do not expand beyond this footprint; spend effort on road quality, driving feel, visuals and traffic. If the full footprint proves unachievable at stable performance, shrink it deliberately and document the reason, rather than shipping a slideshow.
3. **A 10-car garage.** Exactly **10 distinct, Blender-authored cars** with different classes, silhouettes and handling profiles, selectable through an in-game **console / garage menu** (Section 8).
4. **Living roads.** **Civilian road traffic** (Section 9).
5. **Forza-like feel.** Accessible, fast, satisfying arcade-sim handling; sense of speed; beautiful lighting, weather and time of day; festival-like optimistic presentation; discoverable activities along the roads.

---

# 0. Research first — use the internet

Before designing anything substantial, **use the web search / web fetch tools available to this agent to research Forza Horizon 5**. If no web tool is available, say so in `RESEARCH_NOTES.md` and continue from your own knowledge.

Research at least:

- open-world structure: biomes, regional variety, road types and how roads are used for events;
- weather/season system and its effect on driving and visibility;
- time-of-day presentation and lighting;
- road events and activities (road/dirt/cross-country races, speed traps, speed zones, drift zones, danger signs/jumps, collectibles, photo opportunities, festival hubs);
- car roster structure, classes, customization, tuning and upgrades;
- traffic, wildlife, ambient world life;
- HUD, minimap, waypoint and navigation conventions;
- photo mode and presentation features;
- how driving assists (traction control, stability, ABS, racing line) are presented.

Then research the **Godot 4.7 side** where needed, preferring the official docs and the official class reference: `VehicleBody3D`/`VehicleWheel3D` vs custom raycast vehicles on `RigidBody3D`, the Jolt Physics integration, `PhysicsDirectSpaceState3D`, procedural terrain (`ArrayMesh`, `SurfaceTool`, `HeightMapShape3D`), `MultiMeshInstance3D`, visibility ranges and occlusion culling, `WorkerThreadPool`/threaded chunk streaming, `WorldEnvironment` (SDFGI, volumetric fog, sky), `GPUParticles3D`, `AudioStreamGenerator`/`AudioStreamPolyphonic`, `InputMap`, glTF import options and collision-suffix naming, headless/CLI options. Verify claims against the installed engine rather than trusting memory — Godot's API changes between minor versions.

Write results to **`RESEARCH_NOTES.md`** in the project folder:

- a feature inventory of Forza Horizon 5 as you understand it;
- for each notable feature: **ADOPT / ADAPT / SKIP** with a one-line reason;
- source URLs;
- the final feature list you commit to, ranked by priority.

Summarize in your own words; do not copy text from sources.

---

# 1. Existing project and environment

Work directly in the current project folder, which contains `project.godot`. **Do not create another nested Godot project.**

Known environment (verify each item; do not blindly trust):

```text
Project folder:   W:\YouTube\Opus 5.5 Effort Test\3. Opus 5.5 Forza High Effort\3.-opus-5.5-forza-high-effort
Engine:           Godot 4.7.x, Forward Plus renderer (see config/features in project.godot)
Godot executable: W:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe
Godot console:    W:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe
                  (the path is an observed location; confirm that the version matches the project)
Language:         GDScript (primary). C# / GDExtension only if verified to work here, and not required.
Git:              verify with `git --version`; the project folder may or may not already be a repository
Platform:         Windows 11, PowerShell
```

Technical defaults:

- **GDScript with static typing** for gameplay systems. Keep scripts small and modular (vehicle, camera, traffic, world streaming, weather, UI, console, events, save/load).
- **Data-driven design** with custom `Resource` scripts saved as `.tres` (cars, tuning, upgrades, events, surfaces, weather presets).
- Prefer code-generated scenes and tooling scripts over hand-edited `.tscn` files where the result must be reproducible; small hand-authored scenes are fine, but keep `.tscn`/`.tres` valid text that you can review and repair.
- Terrain and roads are **procedural and project-owned**: a deterministic generator (seeded) that produces heightmap chunks, road meshes from splines (`Curve3`/`Path3D` or custom data), terrain carving along roads (cuttings and embankments), bridges and tunnels. Large terrain must be **chunked and streamed** (Section 12).
- Use the **Forward Plus** renderer features that are stable on the target machine (SDFGI or VoxelGI/baked probes, SSAO/SSIL, volumetric fog, glow, tonemapping). Choose settings by measuring, not by assumption.
- **Input Map actions** for all controls (keyboard + gamepad); **Control nodes in a `CanvasLayer`** for HUD and menus.

A packaged export is **not** required. A working editor session and a working `--path . ` run of the main scene are the baseline; an export is a stretch goal.

## 1.1 How to drive the engine (autonomy)

There is likely no Godot editor MCP in this session; do not register new MCP servers or change global/user settings. Use the command line:

1. Run the game with the **console executable** so that logs are captured: `Godot_..._console.exe --path "<project>" [scene]`. Use `--headless` for non-rendering checks, `--import` after adding or changing assets, `--quit-after N` for bounded runs, `--script` for tooling and drive-test scripts, `--check-only` / `--script` parse checks for GDScript errors.
2. For screenshots, run with a real renderer (not `--headless`) and save viewport images from a script (`get_viewport().get_texture().get_image().save_png(...)`) or use `--write-movie`. Look at the resulting images yourself (read the PNGs) — do not infer visual quality from logs.
3. Keep every setup step reproducible as a script in the project (for example `tools/*.gd`, `tools/*.ps1`, `tools/*.py` for Blender).
4. Never leave a Godot or Blender process you started running at the end; do not kill processes you did not start (other Blender/Godot instances on this machine belong to other projects).

You are responsible for parse errors, missing resources, UID/`.import` problems, shader compile errors and import settings. Do not ask me to click anything in the editor.

---

# 2. Blender MCP — mandatory

The user created the master Blender file and started a **dedicated Blender instance for this project**. Other Blender instances for other projects are running at the same time on this machine, each on its own port. This makes strict routing essential.

```text
Blender host:        localhost
Blender port:        9879
Master Blender file: ./Opus55ForzaHighEffort.blend   (in the project folder)
MCP server name:     not predeclared - discover it from the available tool descriptions and verify
```

The Blender scene is expected to be an **empty default scene** at the start. Everything has to be created by you.

## 2.1 Routing rule

Use only the MCP connection configured for **`localhost:9879`**. Determine its identity from the available tool descriptions. Never use a server that points at another port, and never touch another project's folders or `.blend` files — even to "check" them, and even if that Blender is the only one that responds.

Before making any Blender changes:

1. Record the session start time (Section 16) and resolve the project directory.
2. Confirm that the master `.blend` exists in that directory.
3. Identify the MCP connection configured for `localhost:9879`.
4. Execute a real read-only Blender MCP call: inspect the open scene and obtain the full path of the current `.blend` through an available permitted read-only operation.
5. Confirm that this path is exactly the master `.blend` in the project folder. A listening port or a matching basename alone is not confirmation.
6. Back up the master file before its first modification. Record the verified server/tool namespace, endpoint and full file path in `DEVELOPMENT.md` and the final report.

For every later Blender operation: use only this verified connection; treat the master `.blend` as the canonical editable source; preserve unrelated content; organize generated assets in clearly named collections; save the master file regularly; keep exports and backups separate from the master file.

If the Blender MCP tools are unavailable, a call fails or the opened file does not match, report the exact blocker and the minimum correction. Do not write to another Blender instance, do not silently replace Blender-authored assets with engine primitives, and do not claim a verification you did not perform.

Respect the connector's permissions and Safe Mode. Do not patch the add-on or bypass validation. Do not ask me to model, UV, rig, export or import assets manually.

## 2.2 Blender visual QA loop

For every important hero asset (cars first):

1. model it through the verified Blender MCP connection;
2. create UVs and materials;
3. inspect it visually with viewport/render feedback and revise anything lumpy, broken or placeholder-quality;
4. save the Blender source;
5. export it (Section 2.4);
6. import it into Godot (`--import`);
7. configure materials, collision, physics and gameplay scripts;
8. test it in the running game and look at a screenshot.

An asset is not finished because a file exists. It must look reasonable and work in Godot.

## 2.3 No external asset shortcuts

Do not depend on the Godot Asset Library, itch.io/Kenney/OpenGameArt packs, Quixel, Sketchfab, Poly Haven, Poly Pizza, AI 3D-generation services, ripped game assets or any downloaded character/vehicle/prop model. Create important project-specific 3D assets with Blender MCP and project-owned code. Engine built-in nodes, built-in primitive meshes, and procedurally generated project-owned textures, materials, meshes and audio are allowed. Primitives may be temporary stand-ins during development only.

## 2.4 Blender → Godot export pipeline

```text
master .blend -> Blender MCP edits -> save -> export glTF binary (.glb)
 -> res://assets/imported/... -> godot --headless --import
 -> import options (collision suffixes, materials, scale) -> scenes / Resources / scripts -> gameplay integration
```

- **glTF 2.0 (.glb) is the primary interchange format** for Godot; validate each asset. Godot can also read `.blend` directly, but that needs a Blender install path in editor settings and ties the runtime to Blender — export `.glb` instead and never load the master `.blend` at runtime.
- Author at real-world scale (1 Blender unit = 1 m). Blender is Z-up, glTF/Godot are Y-up with -Z forward: verify scale, axis orientation, forward direction and pivots after import.
- Cars: body, **four separate wheel meshes with the pivot at the axle centre**, separate steering wheel, brake discs, lights, windows with a separate glass material, interior suitable for a cockpit camera. Name parts consistently (`Body`, `Wheel_FL`, `Wheel_FR`, `Wheel_RL`, `Wheel_RR`, `Glass`, `Interior`, `Lights_*`).
- Collision: use simple convex or box collision (Godot's `-convcolonly` / `-colonly` naming suffixes in the glTF, or shapes built in code); never use per-triangle collision for vehicles.
- Provide lower-detail variants or LODs for cars and props (Godot generates mesh LODs on import; also use `visibility_range_*` and `MultiMesh` for dressing). Keep triangle counts sensible for a 10-car garage plus traffic.
- Automate exports through the MCP and scripts; do not rely on the GUI.

Organize the Blender file into clear collections, for example `FORZA_GODOT / Cars / Traffic / Props / Settlements / Roadside / Nature / Collision`. Avoid unnamed `Cube.001` objects in final assets.

---

# 3. Autonomy and workflow

I am not a Godot expert. Do **not** expect me to create scenes, assign Inspector references, configure Project Settings, import assets, fix script errors, set up materials or wire UI manually. Take ownership.

Before substantial work:

1. read this entire prompt and any local `CLAUDE.md`/`AGENTS.md`;
2. record the start timestamp (Section 16);
3. inspect the project (`project.godot`, existing files), the Godot executable and its version;
4. verify the Blender connection (Section 2.1);
5. do the research (Section 0);
6. write a concise technical plan;
7. make sure a Godot-appropriate `.gitignore` exists (`.godot/`, `*.import` is **not** ignored, export outputs, backups) and initialize Git with a baseline commit if the folder is not already a repository;
8. create `DEVELOPMENT.md`, `FEATURE_MATRIX.md`, `RESEARCH_NOTES.md`, `PROGRESS.md` and the final report.

Then work autonomously. Do not stop to ask confirmation after each subsystem. If a feature becomes a deep blocker, preserve the working game, document the limitation, move to the next high-value feature and return later. Never claim an unfinished feature works.

**Long-run discipline.** This is a very long task and your context may be compacted or reset. Maintain **`PROGRESS.md`** as a running log: current milestone, what is verified working, what is in progress, next three steps, known bugs, verified paths/ports/commands. Update it after every milestone and re-read it after any context reset. Prefer small, verifiable increments: after each change, run the game or a headless check and read the log. A broken main scene is the highest-priority bug at all times.

You may use subagents where they genuinely parallelise independent work (for example research, or reviewing a finished system). Do not let two agents write the same file or use the Blender connection at the same time, and record any subagent usage (model, purpose) for the metrics in Section 16.

---

# 4. The world

## 4.1 Regions

At least **four clearly distinguishable regions**, connected by roads, with different terrain shapes, vegetation, soil colours and lighting moods. Suggested set (choose your own names and layout):

1. **Rolling farmland and forest valley** — gentle hills, fields, hedgerows, a river with bridges, a village.
2. **Mountain highlands** — a long climbing pass with hairpins, cliff edges, a tunnel, a viewpoint, snow or alpine vegetation at the top.
3. **Arid canyon / desert plateau** — wide fast roads, mesas, dust, dirt shortcuts, a gas station.
4. **Coastal cliffs and beach road** — sea, cliffs, a long bridge, a small harbour hamlet.
5. Optional: lake district, vineyard terraces, wetlands.

## 4.2 Roads

- A connected network, not isolated strips: highways, regional roads, winding mountain roads, dirt/gravel tracks and a few cross-country shortcuts.
- Proper construction: lane markings, shoulders/curbs, banked corners, bridges, tunnels, guard rails, signs, reflectors, posts, culverts. Roads follow the terrain convincingly (cuttings and embankments rather than floating strips).
- Intersections that traffic can use.
- Several **long uninterrupted stretches (5 km+)** that are fun at speed, with varied scenery and landmarks.
- Surface types with distinct physics and audio: asphalt, concrete, dirt, gravel, grass, sand, wet asphalt. Query surface type reliably (for example from collider metadata/groups or a surface map), not by guesswork.

## 4.3 Settlements and points of interest

Only small settlements: villages, hamlets, farms, a harbour, a couple of gas stations, roadside diners, a ruined castle, a wind farm, a lighthouse. Build reusable modular kits in Blender (houses, barns, fences, signs, poles, bridges, tunnel portals, guard rails). No large city.

## 4.4 Nature and dressing

Project-owned trees, bushes, rocks, grass, flowers, crops; roadside props and signs. Use `MultiMeshInstance3D`, visibility ranges and distance fade. Cohesive silhouettes and sensible LODs matter more than quantity.

## 4.5 Sky, lighting, weather, time of day

- Full **day/night cycle** (sunrise, day, sunset, night) with vehicle and street lights.
- Weather states: **clear, cloudy, rain, fog, storm**; weather affects sky, lighting, visibility, particles, wet-looking surfaces and **tire grip**.
- Optional: biome-dependent weather rules (dust in the desert, snow at altitude).

---

# 5. Vehicle physics and driving feel — the core of the game

This is the most important system. A beautiful world is worthless if the car does not feel good.

- Prototype and compare Godot's built-in **`VehicleBody3D`** with a **project-owned raycast/spring vehicle** on a `RigidBody3D` (Jolt if available and stable). Keep the one that is stable and fun at 250+ km/h and in drifts, and justify the choice in `DEVELOPMENT.md`. Choose a physics tick rate that holds up at those speeds.
- Required: steering with speed-sensitive reduction, throttle, brake/reverse, handbrake, engine with RPM and gears (automatic gearbox at minimum), differential behaviour per drivetrain (FWD/RWD/AWD), suspension with weight transfer, tire grip model per surface, aerodynamic downforce/drag, anti-roll, body roll and pitch, wheel spin and wheel rotation visuals, brake/head/reverse lights, horn.
- Surface and weather response: grip changes on asphalt/dirt/gravel/grass/sand and when wet; dust and tire-smoke particles; skid marks or decals where practical.
- Assists with in-game toggles/console commands: traction control, stability control, ABS, steering assist, braking line help (optional), auto/manual gearbox, rewind (stretch).
- Collisions: believable impact response, stability after jump landings, damage as a bonus; the car must be recoverable (reset-to-road command). Guard against tunnelling through terrain/road at high speed (continuous collision, sensible collider thickness).
- Handling data is **data-driven**: one `Resource` per car with mass, centre of mass, power/torque curve, gear ratios, drivetrain, tire grip curves per surface, suspension stiffness/damping, downforce, brake bias, steering lock, top speed, etc.
- Verify with automated drive tests (scripted inputs, headless where possible): 0–100 km/h time, top speed, braking distance, skidpad grip, high-speed stability, jump landings, off-road traction. Write the numbers in `DEVELOPMENT.md`.

Camera: chase camera with speed-dependent FOV and distance, hood camera, cockpit camera, bumper camera, free look, smooth transitions, camera collision, subtle shake at speed and on impacts.

Audio: procedural/project-owned engine sound driven by RPM and load (`AudioStreamGenerator` or generated samples), turbo/blow-off, gear shifts, tire squeal per surface, wind at speed, suspension thumps, impacts, ambient sound per region. No copyrighted audio.

---

# 6. The garage — exactly 10 original cars

Create **10 distinct cars** with different silhouettes, proportions, drivetrains and handling. Original designs only — no real cars, manufacturer names or logos.

Suggested class spread (adapt as you like):

1. compact hot hatch (FWD);
2. everyday sedan;
3. classic muscle car (RWD, powerful, tail-happy);
4. sports coupe (RWD);
5. grand tourer (front-engine, fast, stable);
6. mid-engine supercar (AWD or RWD);
7. rally car (AWD, great on gravel/dirt);
8. off-road SUV (tall suspension, rough-road capability);
9. pickup truck (heavy, body roll);
10. vintage roadster/classic (light, slow, charming).

Each car needs: a quality Blender-authored body with visible detail and believable proportions, separate wheels, windows, lights, an interior for the cockpit view, a handling `Resource`, an engine sound profile, a performance-class label and a paint system (primary colour plus finish: gloss / matte / metallic).

Do **not** fake breadth: a car is listed only if it is drivable with its own model and handling. Never scale one mesh to pretend to be another car.

---

# 7. Customization, tuning and photo mode (after driving is solid)

- **Paint**: primary colour, finish, optional stripes/livery variants; wheel/rim styles and colours.
- **Upgrades** with real gameplay effect (engine, tires, suspension, brakes, weight reduction, aero), data-driven and visible in a stat comparison.
- **Tuning**: gearing, tire pressure, alignment, spring/damper/anti-roll, aero, brake bias (a reduced set is fine).
- **Photo mode** (stretch): free camera, FOV, depth of field, time-of-day and weather freeze, hide HUD, screenshot key.

---

# 8. Console, garage menu and benchmark/debug menu — mandatory

1. An **in-game developer console** (toggle with the backtick/tilde key, plus an on-screen hint) with at least:
   `cars` (list), `car <index|name>` (switch/spawn at current location), `respawn`, `tp <region|poi>`, `time <hour>`, `weather <state>`, `traffic <0..1>`, `speed`/`fps` toggles, `assist <name> on|off`, `paint <colour>`, `reset`, `help`.
2. A **graphical car-select / garage menu** (toggle key such as `F1` or `Tab`) listing all 10 cars with stats, so a viewer sees the roster in a video.
3. A **benchmark/debug menu** for easy demos: teleport to each region and long-road start points, spawn any car, set time and weather, toggle traffic and density, toggle assists, show FPS/coordinates/speed, repair and flip-reset, telemetry (RPM, slip, surface).

These are testing tools and must not break normal free-roam play.

---

# 9. Traffic — mandatory

Believable **civilian road traffic** across the network:

- a road/lane graph built from the road splines, with direction of travel, lanes, speed limits per road class and intersections/priorities;
- vehicles that follow lanes, keep following distance, brake for obstacles including the player, slow for corners, stop/give way at intersections, optionally overtake on long roads;
- several **distinct traffic vehicle types** (small car, van, lorry, bus, tractor on farm roads, pickup), authored in Blender; they may be simpler than player cars;
- density scaling by region/time of day and via the console;
- spawn/despawn around the player outside the camera view, **pooling**, simulation LOD (full physics near the player, kinematic movement at distance, nothing far away);
- reaction to collisions (physics response, then recover or become a stopped obstacle that despawns), horn/flash feedback;
- parked cars and rest areas as stretch features.

Traffic must not tank performance and must not make the long scenic roads feel empty or crowded; tune density deliberately.

---

# 10. Activities on the roads (after driving and traffic work)

Discoverables started by driving through them, with score/time and a HUD notification. Implement as many as are robust, in this order:

1. **Speed traps** — speed through a gate, score and personal best.
2. **Speed zones** — keep average speed over a stretch.
3. **Drift zones** — a scored drift section.
4. **Danger signs / big jumps** — long-jump distance scoring.
5. **Checkpoint road races** along the long roads (start gate, checkpoints, timer, optional simple AI opponents as stretch).
6. **Time trials** on the scenic loop.
7. **Collectibles / photo spots / hidden cars** (stretch).

No story missions, no dialogue. A persistent score/credits economy is a stretch goal only.

---

# 11. HUD, map and navigation

- Speedometer (km/h and mph option), tachometer, gear, surface/assist indicators, region name popups, event notifications.
- **Minimap** with roads, position and heading; **full map** (stretch) with regions, events and waypoint; **GPS route line** on the road (stretch).
- Clean, original, modern UI; responsive layout; readable at video resolution (test at 1920×1080 and at least one other resolution). Do not copy Forza UI artwork.

---

# 12. Performance and world streaming

- Target a stable **60 FPS** at reasonable recording settings, with 30 FPS as the floor; verify with measured frame times (`Engine.get_frames_per_second()`, `Performance` monitors, the render info counters) and report numbers.
- Streaming radius appropriate for high speed; chunked terrain with threaded generation and no main-thread hitches; `MultiMesh` and visibility ranges for dressing; occlusion culling where it helps; avoid per-node `_process` spam (prefer central managers); pool traffic and effects; avoid unbounded physics bodies; cap shadow distance and light counts deliberately.
- Verify there is no visible hitching when driving the full loop at top speed, no duplicate/leaked chunk nodes, and no memory growth over a full lap.
- Be aware of single-precision floats at 2 km from the origin; verify there is no visible jitter in physics or rendering at the map edges, and add origin shifting only if needed.

---

# 13. Save/load and settings

Persist at least: current car and paint/upgrades, position, time of day, weather, settings, personal bests (in `user://`). Recover gracefully when dynamic objects are not persisted.

---

# 14. Priority order

This project is broad. Follow this order and **do not stop early**:

1. project runs headless-clean and launches into a test scene;
2. verified Blender MCP pipeline with one polished car imported and drivable;
3. driving model and chase camera that feel good;
4. chunked terrain with the first long road and the first region;
5. HUD basics and console/garage menu for switching cars;
6. traffic foundation on the first roads;
7. remaining regions and the connected road network (40–60 km);
8. all 10 cars with handling profiles and sounds;
9. day/night cycle and weather with grip effects;
10. settlements, roadside dressing, tunnels, bridges, landmarks;
11. activities: speed traps, drift zones, jumps, races;
12. customization, tuning, photo mode;
13. minimap/map/GPS;
14. save/load;
15. polish pass: lighting, materials, VFX, audio, camera;
16. final QA, performance pass and documentation.

A strong first milestone: one polished car, a drivable stretch of terrain with a road, a good chase camera, HUD, the console switching between at least two cars, and basic traffic.

---

# 15. Quality, QA and documentation

## 15.1 Honest status

Use only `WORKING`, `PARTIAL` or `NOT IMPLEMENTED` in `FEATURE_MATRIX.md` (columns: Feature | Status | Notes). Mark `WORKING` only when there is a functional in-game path you actually exercised. Label decorative-only assets clearly. Do not populate menus with features that do not work.

## 15.2 Continuous QA

Continuously: run the project and read the log for errors and warnings, run `--import` after asset changes, run drive tests, test gameplay in a real window, capture and **look at** screenshots of key views, verify imported assets (scale, orientation, wheel pivots, materials, collision), check for missing resources, re-test traffic and streaming. Do not wait until the end to discover the project does not load.

## 15.3 Final validation

Before declaring completion verify at least: the project starts without script errors; the main scene loads; the player spawns in a car on a road; all 10 cars are selectable and drivable; the console works; traffic runs; weather and day/night work; the long loop can be driven end to end without falling through the world; activities marked WORKING behave; Blender assets import and display correctly; no major missing materials; save/load works at a basic level; performance is acceptable for recording.

## 15.4 Asset-quality gate

Visually inspect the game and reject unintentional placeholder content. Prioritize authored, finished versions of: player cars, road surfaces and road furniture, main landmarks, traffic vehicles, vegetation, settlements. Document anything left unfinished.

## 15.5 Required documents

- **`DEVELOPMENT.md`** — engine version, toolchain, architecture, systems, controls, map layout, Blender workflow, run instructions, known limitations, drive-test numbers.
- **`FEATURE_MATRIX.md`** — status table as described above.
- **`RESEARCH_NOTES.md`** — Forza Horizon 5 research and adopt/adapt/skip decisions.
- **`PROGRESS.md`** — the running log from Section 3.
- **`OPUS_5.5_FINAL_REPORT.md`** — what was built, what works, what is partial, known bugs, controls, run result, Blender assets, car roster, map regions, traffic implementation, performance notes, and the metrics block from Section 16.

Make meaningful Git milestone commits (baseline, first car, driving model, terrain + road, traffic, regions, cars, weather, activities, final). Never commit `.godot/`, caches or export outputs.

---

# 16. Session timing, token accounting and API-equivalent cost — mandatory

These metrics will be shown in a YouTube video comparing Claude Opus 5.5 at different effort levels. Measure **only this project's session**. Do not include other sessions or projects, and **do not fabricate precision**.

## 16.1 Development time

At the very beginning, before substantial work:

1. read the current OS timestamp with its timezone;
2. create a unique run directory and save the start time to `.opus-5.5-forza-godot-runs/<run-id>/start_time.txt`;
3. keep that run ID and start time unchanged for the whole task.

After final validation and report preparation, read the timestamp again and save it to `end_time.txt` in the same directory. Compute the elapsed wall-clock time. If work is resumed, append identifiable segments instead of overwriting the original start; report known pauses separately; never sum overlapping tool/subagent durations.

## 16.2 Tokens

Obtain real usage from the runtime you are running in (session usage metadata exposed by the agent or host, a usage record of this exact session, or the permitted local usage log identified reliably by session ID, working directory and timestamps). Read only relevant usage metadata; do not copy credentials or unrelated conversations into the repository.

Use mutually exclusive categories (uncached input, cache-read, cache-write, output; thinking/reasoning tokens only if separately exposed). Do not subtract cache usage from an already-uncached count and do not double count. Deduplicate events by request/message identity. A missing counter is **unknown**, not zero. Do not estimate tokens from code size, asset size, tool-call counts or elapsed time. Identify delegated subagent work separately and record the actual model of each part. If exact usage cannot be obtained, write exactly: `Exact token usage unavailable from the accessible runtime.`

## 16.3 API-equivalent price

Compute the **token-only API-equivalent cost in USD** from the verified usage using the **official Anthropic pricing for the model you actually ran as** (Claude Opus 5.5; verify the model identifier exposed by the session), at standard API pricing, from `https://platform.claude.com/docs/en/about-claude/pricing`. Record the source URL, verification date and the formula. Use the rates you read on that page at run time, not rates from memory. This is a benchmark equivalent, not the user's subscription payment. If usage, model identity or pricing cannot be verified, say so and give a clearly labeled partial figure or "unavailable".

---

# 17. Start now

Begin immediately:

1. record the start timestamp and run ID;
2. inspect the Godot project, the engine executable/version and the toolchain;
3. verify the Blender MCP connection on `localhost:9879` and the master file;
4. research Forza Horizon 5 and write `RESEARCH_NOTES.md`;
5. write the plan, then build the game autonomously.

**This is an original open-world arcade-sim racing game in the spirit of Forza Horizon 5, built on Godot 4.7, with long countryside roads, a 10-car garage selectable via console, and civilian traffic.**

**Use only the verified Blender MCP connection on `localhost:9879` with `Opus55ForzaHighEffort.blend` in the project folder, and use it actively for every important 3D asset.**

---

# 18. FINAL REQUEST — time, tokens and API-equivalent cost (do this last)

When the game, documentation and validation are finished, **calculate and report three numbers for this project**, following Section 16 exactly:

1. **Time spent** — wall-clock duration between the saved start timestamp and a fresh end timestamp, as `HH:MM:SS` plus total minutes; known pauses separately.
2. **Number of tokens** — real usage of this session (uncached input, cache-read, cache-write, output, thinking if separately exposed, and a deduplicated total), or the exact sentence `Exact token usage unavailable from the accessible runtime.`
3. **Price in API-equivalent US dollars** — token-only cost from the verified usage at the official Claude Opus 5.5 API price, or an explicit statement that it is unavailable.

Put them into this block at the bottom of `OPUS_5.5_FINAL_REPORT.md` **and** state them in your final chat message, each marked as measured, estimated or unavailable:

```text
## Claude Opus 5.5 Godot Forza Session Metrics

Project: Godot 4.7 Forza-style open-world racing game
Effort level under test: high
Run/session identifier:
Working-directory full path:
Start timestamp and timezone:
End timestamp and timezone:
Elapsed wall-clock time (HH:MM:SS):
Elapsed minutes:
Known pauses / resumed segments:

Requested model: Claude Opus 5.5
Actual model identifier(s):
Input tokens (state whether uncached or inclusive):
Cache-read tokens:
Cache-write tokens:
Output tokens:
Thinking/reasoning tokens (included / separate / unavailable):
Deduplicated total tokens:
Usage source and observation cutoff:
Unmeasured work / limitations:

Token-only API-equivalent cost (USD):
Official pricing source, verification date and tier:
Rates and formula used:
Measured / estimated / unavailable, with reasons:

Blender MCP server/tool namespace actually used:
Blender host: localhost
Blender port: 9879
Blender master file: Opus55ForzaHighEffort.blend
Verified full path of master file:
Approximate number of major Blender assets created:
```
