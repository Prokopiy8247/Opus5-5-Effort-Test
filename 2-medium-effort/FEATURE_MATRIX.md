# FEATURE MATRIX — Verdant Ridge Festival

Status: **WORKING** = exercised in the running game this session (QA runner logs/screenshots in `qa/`),
**PARTIAL** = works with stated limits, **NOT IMPLEMENTED**.

| Feature | Status | Notes |
|---|---|---|
| Launch straight into free roam on a long scenic road | WORKING | spawns on Harbour Coast Road (or saved position); boot ≈ 3–8 s incl. shader warm-up |
| Headless-clean start (no script errors) | WORKING | `--headless --quit-after` runs clean |
| 4 distinct regions | WORKING | Greenvale Farmlands, Granite Highlands, Ochre Canyon, Azure Coast; region popups |
| Map footprint ~4×4 km | WORKING | playable roads within ±1.85 km; far terrain to ±3.2 km |
| Road network 40–60 km | WORKING | 41.6 km, 37 roads, 21 junctions (`tools/map_preview.gd`) |
| Scenic loop ≥ 20 km | WORKING | Grand Festival Loop 20.3 km; driven end-to-end by autopilot, 0 falls (loop test) |
| Long stretches ≥ 5 km | PARTIAL | continuous multi-road runs of 4–6 km (e.g. Sunset Straight→Expressway→Seacliff); individual roads ≤ 2.4 km |
| Road construction: markings, shoulders, banking, guard rails, reflector posts, signs | WORKING | procedural lane-marking shader; rails where verge drops; speed/chevron/direction signs |
| Bridges | WORKING | auto-detected over river/valleys/sea (≈3.1 km incl. viaducts), slab + parapets + piers; estuary bridge, harbour pier |
| Tunnels | PARTIAL | one 176 m tunnel (Summit Descent) with tube, portals, lights; drivable (verified); terrain hole handling is approximate |
| Cuttings / embankments (terrain carving) | WORKING | terrain blends to road with slope-dependent falloff |
| Intersections usable by traffic | WORKING | junction pads + give-way logic |
| Surface types with distinct physics | WORKING | asphalt, concrete, dirt, gravel, grass, sand, snow, rock (+ wet via weather); queried from collider metadata / terrain function |
| Surface-specific audio | PARTIAL | squeal on hard surfaces, gravel crunch on loose; not per-surface timbres for each type |
| Chunked, threaded terrain streaming | WORKING | WorkerThreadPool; no leaked chunks (count stable ~130), memory flat over a lap (178→191 MB) |
| Vegetation & dressing (MultiMesh, LODs, visibility ranges) | WORKING | 7 Blender tree/plant types ×2 LOD + rocks + procedural grass tufts |
| Settlements & POIs | WORKING | 4 villages/hamlets, 5 farms, 2 gas stations, 2 diners, lighthouse, castle ruin, wind farm (spinning), harbour boats, parked cars |
| River, lake, sea | WORKING | single water plane with depth tint/foam |
| Day/night cycle | WORKING | sun/moon, sky, exposure; street lamps + car headlights at night (sun-elevation based) |
| Weather: clear, cloudy, rain, fog, storm (+snow) | WORKING | console/debug/auto; rain/snow particles, lightning, fog, wet roads, grip change; rain turns to snow above 190 m |
| Custom raycast vehicle (Jolt) | WORKING | see DEVELOPMENT.md; 120 Hz; stable to 340 km/h |
| VehicleBody3D comparison | WORKING | `--qa-mode=compare`; results in DEVELOPMENT.md |
| Engine/gears/automatic + manual gearbox, reverse | WORKING | load-aware shift points; Q/E manual |
| FWD/RWD/AWD drivetrains | WORKING | per CarDef |
| Suspension, weight transfer, anti-roll, body roll/pitch | WORKING | |
| Tyre model per surface, wet grip | WORKING | |
| Aero drag + downforce | WORKING | top speeds within ~3 % of design targets |
| Assists TCS/ESC/ABS/steering assist toggles | WORKING | console `assist`, debug menu, HUD indicators |
| Handbrake drifting | WORKING | rear lock + reduced lateral grip |
| Brake / head / reverse lights, horn | WORKING | |
| Tyre smoke, dust/spray, skid marks | WORKING | pooled MultiMesh skid marks (3000) |
| Damage | PARTIAL | damage % counter (HUD), impact sound/shake; no visual deformation |
| Reset to road / flip / repair | WORKING | R key, console, debug menu; automatic fall-through safety net |
| Rewind | NOT IMPLEMENTED | stretch |
| Chase / hood / bumper / cockpit cameras, FOV & shake, camera collision, free look, look back | WORKING | C to cycle; right-mouse free look |
| Procedural engine audio per car + turbo/blow-off, shifts, wind, impacts, ambience | WORKING | single AudioStreamGenerator synth |
| 10 distinct Blender-authored cars | WORKING | hatch, sedan, muscle, coupe, GT, mid-engine super, rally, SUV, pickup, vintage roadster; each own model + CarDef |
| Separate wheels (axle pivots), brakes, glass, lights, interior, steering wheel | WORKING | |
| Paint (colour + gloss/metallic/matte), stripes, rim colours | WORKING | garage + console |
| Upgrades with gameplay effect + stat comparison | WORKING | 6 parts × 4 levels (F3) |
| Tuning (gearing, tyre pressure, camber, springs, dampers, ARB, aero, brake bias) | WORKING | F3 sliders, applied live |
| Photo mode | WORKING | free cam, FOV, DOF, time/weather change, hide hints, screenshot to `user://photos` |
| Developer console | WORKING | all commands exercised (`qa/qa_log_ui.txt`) |
| Garage menu (all 10 cars + stats) | WORKING | Tab/F1 |
| Benchmark / debug menu | WORKING | F2: teleports, spawn car, time, weather, traffic, assists, repair/flip, telemetry, FPS |
| Telemetry overlay | WORKING | per-wheel load/slip/surface |
| Civilian traffic (lane graph, IDM following, give-way, curve speeds) | WORKING | ~20 active vehicles typical |
| Traffic vehicle types (Blender) | WORKING | small car, van, pickup, lorry, bus, tractor (+ sedan) |
| Traffic pooling, spawn/despawn out of view, simulation LOD | WORKING | pool 40, near/far LOD |
| Traffic reaction to collisions, horn/flash | WORKING | wreck → dynamic body, recycled later |
| Traffic overtaking | PARTIAL | only around stopped obstacles when oncoming lane is clear |
| Parked cars / rest areas | PARTIAL | parked cars at settlements and gas stations; no dedicated rest areas |
| Speed traps | WORKING | 7, star ratings, PBs |
| Speed zones | WORKING | 4, average speed |
| Drift zones | WORKING | 5 zones; automated handbrake-drift run completed all 5, scored 1169 / 262 pts where the car slid (`qa/qa_log_drift.txt`) |
| Danger signs / jumps | WORKING | 3 ramps on no-traffic dirt tracks; automated test: 37 m / 52 m / 29 m, 1.0–1.7 s air, landed upright (`qa/qa_log_jump.txt`) |
| Checkpoint races with AI rivals | WORKING | 3 races, 3 autopilot rivals, positions, start prompt (Enter) |
| Loop time trial | WORKING | Grand Festival Loop |
| Collectibles (festival boards) | WORKING | 20 boards, credits |
| HUD (speedo km/h/mph, tach, gear, surface, assists, region, notifications) | WORKING | verified at 1920×1080 and 1280×720 |
| Minimap (roads, heading-up, icons) | WORKING | |
| Full map + waypoint + GPS route | WORKING | Dijkstra over junction graph, route on minimap |
| Save/load (car, paint, upgrades, tuning, position, time, weather, settings, PBs) | WORKING | round-trip verified (`qa/qa_log_save.txt`), autosave 60 s |
| Gamepad | NOT IMPLEMENTED | removed at the user's request; keyboard + mouse only |
| 60 FPS target | PARTIAL | 120–180 FPS typical on this machine; dips to 30–60 under heavy shared load (other projects' Godot/Blender instances running) |
| Export build (Windows .exe) | WORKING | `build/VerdantRidgeFestival.exe`, single 113 MB file with embedded pack; launched and booted without errors (D3D12, Forward+) |
