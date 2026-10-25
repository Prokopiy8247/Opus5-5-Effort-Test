# Sunward Roads — system contracts (for parallel implementers)

Godot 4.7.2, GDScript with static typing, Jolt physics @120 Hz with physics interpolation, Forward+.
Project root = the folder containing `project.godot`. Read `docs/ASSET_CONVENTIONS.md` too.

## Input: keyboard + mouse only
The user decided against gamepad support: do not add gamepad bindings, gamepad prompts or stick/trigger handling.
Menus must be fully usable with keyboard (arrows/Enter/Esc/Tab, `ui_*` actions) and mouse.

## Golden rules for every implementer
1. **Own only your files** (listed per system below). Never edit files owned by others or the core files
   (`scripts/core/*`, `scripts/main/*`, `scripts/vehicle/car_controller.gd|car_data.gd|car_factory.gd|car_visuals.gd|car_input.gd|tuning.gd`,
   `scripts/world/*` except those assigned to you, `scripts/camera/*`, `project.godot`, `tools/setup_project.gd`).
   If you need a core change, describe it precisely in your final report ("CORE CHANGE REQUEST") and work around it.
2. **No new `class_name`** declarations (the global class cache is only refreshed by the integrator). Reference your own
   scripts with `const Foo := preload("res://scripts/.../foo.gd")`. Existing global classes you may use:
   `CarController, CarData, CarFactory, CarVisuals, CarInput, CameraRig, SurfaceData, Surfaces, Tuning, UpgradeData,
   World, WorldData, WorldGen, WorldLayout, RoadNetwork, RoadBuilder, TerrainStreamer, MapRenderer, RoadFollower, QaDirector, TestTrack`.
3. **Never run the Godot editor or `--import`.** You may run:
   - compile check: `"W:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe" --headless --path . res://tools/check_scripts.tscn`
     (prints `CHECK_OK n`; any `SCRIPT ERROR` lines are real errors),
   - the game with QA automation (see `scripts/main/qa_director.gd`), e.g.
     `... --path . -- --qa=shots --targets="Sunward Festival" --views=0 --shot-dir=res://qa_output/<yourname>`
     `... --path . -- --qa=drive --road=ring --speed=100 --minutes=1`
     Always wrap runs in `timeout <seconds>`; a script error in a `--script` tool hangs Godot forever.
   - your own test scenes under `tools/tests/<yourname>_*.tscn|gd`.
   Write screenshots/logs only under `qa_output/<yourname>/` (git-ignored). Look at your screenshots (Read the PNG).
4. Other agents run Godot at the same time: keep test runs short (≤ 3 min), close what you start, never kill processes you did not start.
5. Do not use the Blender MCP or any external asset; everything is procedural / project-owned. Placeholder meshes are allowed
   only behind an asset lookup that switches to the Blender `.glb` automatically when it exists (see Props below), and must be
   clearly named `*_placeholder`.
6. Performance: no per-node `_process` spam for many objects (use managers), pool nodes, cap particle counts and lights.
7. Typed GDScript; small focused scripts; comments sparse and useful. Untyped `for x in [..]` over literal arrays breaks
   type inference — type the loop variable (`for x: float in [...]`).

## Scene structure (built by `scripts/main/main.gd`)
```
Main (Node3D, main.gd)            Game.main
├─ CameraRig (CameraRig)          Game.camera_rig     .camera: Camera3D, .mode, .active, .set_mode(), .add_trauma()
├─ CarInput (CarInput)            player input -> car; .enabled
├─ World (World)                  Game.world          see below
├─ Environment                    Game.env            res://scripts/env/environment_controller.gd (optional, loaded by path)
├─ Dressing / Settlements         res://scripts/world/dressing.gd, settlements.gd (optional)
├─ Traffic                        Game.traffic        res://scripts/traffic/traffic_manager.gd (optional)
├─ Activities                     Game.activities     res://scripts/activities/activity_manager.gd (optional)
├─ UI (CanvasLayer)               Game.hud            res://scripts/ui/ui_root.gd (optional)
├─ AmbientAudio                   res://scripts/audio/ambient_audio.gd (optional)
└─ PlayerCar (CarController)      Game.player_car; children added by main: Visual (CarVisuals),
                                  CarAudio (res://scripts/audio/car_audio.gd), CarEffects (res://scripts/vehicle/car_effects.gd)
```
Optional systems are instantiated with `load(path).new()`; they must work when added with `add_child` and no exported setup.
`Game.player_car` changes when the player switches car: listen to `Game.car_spawned(car)`.

## Game autoload (`scripts/core/game.gd`) — the API for menus/console/activities
Signals: `car_spawned(car)`, `notification(title, body, kind)`, `region_changed(name)`, `weather_changed(id)`,
`paint_changed()`, `stats_changed()`, `activity_update(info: Dictionary)`, `activity_finished(id, result)`,
`ui_overlay_changed(open)`, `waypoint_changed(pos)`.
Car: `get_car_catalog() -> Array[CarData]`, `find_car_index(key)`, `spawn_car(index, keep_transform)`, `respawn()`,
`flip_reset()`, `repair()`, `current_car_data()`, `effective_car_data(index)`.
World: `teleport(name) -> bool`, `get_teleport_targets() -> Array[{name, kind, position, forward, region}]`,
`set_time_of_day(h)`, `get_time_of_day()`, `set_time_scale(s)`, `set_weather(id, instant) -> bool`, `get_weather()`,
`get_weather_ids()`, `set_traffic_density(v)`, `get_traffic_density()`, `set_waypoint(pos)`, `clear_waypoint()`, `waypoint`.
Assists: `set_assist(name, on)`, `get_assists()`, `apply_assists_to(car)` — names: tcs, stm, abs, steering, auto, line.
Customisation: `get_paint(car_id) -> {color, finish(0 gloss,1 matte,2 metallic), stripes(0..5), stripe_color, rim_color}`,
`set_paint(color, finish, stripes, stripe_color)`, `set_rim_color(color)`, `PAINT_COLORS`, `get_upgrades(car_id)` (slot -> level 0..3),
`get_tuning(car_id)` (key -> value, see `Tuning.TUNE_SPEC`). After changing upgrades/tuning call `Game.spawn_car(Game.current_car_index, true)`
to rebuild the car with the new effective data.
Misc: `notify(title, body, kind)`, `record_personal_best(key, value, higher_is_better) -> bool`, `personal_bests`, `credits`,
`push_overlay(open)` (call with true when a menu opens, false when it closes; player input is disabled while >0), `is_overlay_open()`,
`photo_mode`. Settings autoload: `Settings.get_value(key)`, `Settings.set_value(key, v)`, keys in `scripts/core/settings.gd`.
SaveGame autoload: `save_now()`, `load_now()`, `has_save()`.

## Activity HUD contract
Activities call `Game.activity_update.emit(info)` every frame while active, with
`info = {"id": String, "title": String, "kind": StringName (&"speed_trap", &"speed_zone", &"drift", &"jump", &"race", &"time_trial", &"collectible"),
"primary": String (big text, e.g. "187 km/h" / "01:23.45" / "12,340 pts"), "secondary": String, "progress": float 0..1 (or -1)}`.
When finished: `Game.activity_finished.emit(id, {"title", "score_text", "personal_best": bool, "medal": String})` plus `Game.notify(...)`.
The HUD shows an activity panel while updates arrive (hide 1.5 s after the last update) and a result banner on finish.
Map markers: the activity manager implements `get_map_markers() -> Array[{name, kind, position: Vector3}]`.

## CarController (read-only for most systems)
Inputs: `in_throttle, in_brake, in_steer (-1..1, + = right), in_handbrake, in_shift_up, in_shift_down`.
State: `data: CarData`, `speed_ms`, `forward_speed`, `get_speed_kmh()`, `rpm`, `gear` (-1 reverse, 1..n), `shifting`, `engine_load`,
`throttle_applied`, `limiter_hit`, `tcs_active, abs_active, stm_active`, `body_slip_deg`, `lateral_g`, `longitudinal_g`,
`wheels_on_ground`, `air_time`, `damage`, `headlights_on`, `is_player`, `max_skid()`, `dominant_surface()`.
`wheels: Array[CarController.Wheel]` each with `id ("FL"..), front, left, contact, point (world), normal, load, surface (SurfaceData),
skid (0..1), slip_long, slip_angle, omega, length, prev_length, radius, width, node (visual pivot Node3D)`.
Signals: `gear_changed(gear)`, `impact(strength, world_position)`.
Statics: `CarController.wetness` (0..1, set by weather), `CarController.terrain_surface_lookup`.
Visual: `car.get_node("Visual") as CarVisuals` → `paint_mats`, `sockets` (Dictionary name -> Transform3D car space:
Socket_Exhaust, Socket_HeadlightL/R, Socket_CamHood/Cockpit/Bumper), `set_wetness(w)`, `set_dirt(d)`.
`car.data.cylinders, exhaust_rasp, engine_pitch, turbo, idle_rpm, redline_rpm, max_rpm` drive the engine sound.

## World (`Game.world`, `scripts/world/world.gd`)
`data: WorldData` (`height_at(x,z)`, `normal_at`, `surface_index_at`, `road_distance_at(x,z)` metres to nearest road edge,
`region_at(x,z) -> 0 vale,1 highlands,2 mesa,3 coast`, `region_weights_at(x,z) -> Color(rgba)`, `pois()`, `lake_list()`,
`network: RoadNetwork`, `half` = 2048).
`height_at(x,z)`, `ground_at(x,z)` (raycast incl. roads/bridges), `surface_at(pos)`, `region_at(pos) -> name`, `region_id_at(pos)`,
`water_level_at(x,z)` (-INF if dry), `nearest_road_point(pos, paved_only)`, `get_teleport_targets()`, `spawn_point()`,
`terrain_mat`, `water_mat`, `roads.road_mat`, `roads.tunnel_mat`, `roads.lamp_positions: PackedVector3Array` (street + tunnel lamps),
`extra_physics_points: Array[Vector3]` (append positions that need terrain colliders, e.g. physics-mode traffic; rewritten each frame by owners),
`terrain: TerrainStreamer`, `noise_detail`, `noise_large` (NoiseTexture2D).
Region names: `WorldLayout.REGIONS[i]["name"]`. Map image (1024², covers x,z in [-2048, 2048]): `res://data/world/minimap.png` — the PNGs in `data/world/` use the `keep` importer (exported as raw files, never imported as textures), so load it with `Image.load_png_from_buffer(FileAccess.get_file_as_bytes(path))` + `ImageTexture.create_from_image`, never `load()`.

## RoadNetwork (`Game.world.data.network`)
`roads: Array[RoadNetwork.Road]`, `junctions: Array[{parent, parent_index, child, child_end(0 start,1 end)}]`, `get_road(id)`,
`nearest(pos, max_dist, filter) -> {road, index, s, position, forward, distance, lateral}`.
Road: `id, name, cls (WorldLayout.RoadClass), loop, width, lanes (per direction), shoulder, limit (km/h), surface, traffic (bool),
pos: PackedVector3Array (samples every ds=3 m), bank, flags (bit1 bridge, bit2 tunnel), length, ds, j_start/j_end {road, index, y}`.
`point_at(s)`, `tangent_at(s)`, `flat_tangent_at(s)`, `right_at(s)`, `surface_point(s, lateral_offset)` (+ = right of travel dir),
`lane_offset(lane)` (lane ≥1 right side forward, ≤-1 left side), `bank_at(s)`, `flag_at(s)`.
Traffic drives on the right. `RoadFollower` (scripts/traffic/road_follower.gd) drives a CarController along a lane.
`World.refocus(pos)` re-evaluates terrain streaming immediately (called by `main._place_on` for every teleport/respawn/load).

## Traffic (`Game.traffic`) and activities (`Game.activities`) — added during integration
Traffic: `set_density(v)` / `get_density()` (the user's setting), `set_density_cap(v)` (temporary limit, used by races;
pass >= 1 to lift it), `effective_density()` (setting limited by the cap — what spawning uses), `active_count()`,
`get_stats()`, `obstacles_near(pos, radius) -> Array[{position, speed, heading, length}]`. `Game.get_traffic_density()`
returns the user's setting, also during races.
Activities: `get_map_markers()`, `get_collectibles()`, `collectible_count()`, `get_activity_list()`, `get_session_id()`,
`cancel_session(reason)`, `teleport_to_activity(id, before)`, `respawn_override(pos) -> {position, forward}` (empty when no
event owns the car), `get_ai_cars() -> Array[CarController]` (race rivals; traffic probes them like the player).

## Props (Blender kits, produced later by the Blender props pass)
Kits are `.glb` files whose top-level children are named objects (origin at base centre on the ground, Godot +Y up, -Z forward):
- `res://assets/imported/props/nature_kit.glb`: Tree_Oak_A, Tree_Oak_B, Tree_Pine_A, Tree_Pine_B, Tree_Poplar, Tree_Birch, Tree_Palm,
  Tree_Olive, Tree_Dead, Bush_A, Bush_B, Bush_Desert, Cactus_A, Cactus_B, Rock_A, Rock_B, Rock_C, Rock_Large, Rock_Red,
  Grass_Tuft, Flowers_Tuft, Reeds, Hay_Bale, Log_Pile
- `res://assets/imported/props/roadside_kit.glb`: Sign_SpeedLimit, Sign_Chevron, Sign_Danger_Jump, Sign_Direction, Delineator_Post,
  GuardRail_Post, Lamp_Street, Utility_Pole, Fence_Wood, Wall_Stone, Hedge, Bus_Stop, Bench, Mailbox, Bin, Barrier_Jersey, Cone,
  Bridge_Pier, Tunnel_Portal, Speed_Trap_Camera, Checkpoint_Arch, Festival_Banner, Flag_Pole, Fuel_Pump, Billboard
- `res://assets/imported/props/buildings_kit.glb`: House_Cottage_A, House_Cottage_B, House_Townhouse, Farmhouse, Barn_Red, Silo,
  Shed_Small, House_Chalet, House_Adobe, Gas_Station, Diner, Church, Harbour_Shed, Boathouse, Pier_Section, Boat_Fishing,
  Lighthouse, Castle_Ruin_Wall, Castle_Ruin_Tower, Wind_Turbine_Tower, Wind_Turbine_Rotor, Water_Tower, Festival_Stage,
  Festival_Tent, Viewpoint_Deck
- Traffic vehicles `res://assets/imported/traffic/<id>.glb` (same object names as cars): hatch_small, van_delivery, lorry_box,
  bus_coach, tractor_farm, pickup_work.
Use `scripts/world/prop_library.gd` (owned by the dressing implementer) to fetch meshes by name:
`PropLibrary.mesh(name) -> Mesh` (placeholder if the kit is missing), `PropLibrary.scene(name) -> Node3D`, `PropLibrary.aabb(name)`.

## Additions after the playtest fixes
- CarController: `in_hold` (gear-independent hold while a menu is open), `Wheel.covered` / `Wheel.wetness` (per-wheel;
  a ground collider with meta `covered = true` — tunnel road pieces — counts as dry), `place_at(t, vel, ang_vel, with_gear := 0)`
  (restores velocities, spins the wheels at road speed and picks a fitting gear), `in_shift_up` / `in_shift_down` are
  one-frame requests that the controller queues.
- Road pieces inside the tunnel tube: instance shader parameter `covered = 1.0` (no wetness/puddles/sky reflection) and
  collider meta `covered = true`. Barriers (rails, parapets, tunnel tube) are on physics layer 6 (value 32): car bodies
  collide with them, wheel rays (mask 1|16) do not.
- Game: `waypoint_owner: StringName` (`&""` = the player's, `&"activity"` = set by an event; the GPS does not announce
  arrival for activity waypoints), `set_waypoint(pos, owner := &"")`, `clear_waypoint()`, `benchmark_mode`.
- Environment: `lights_needed(at := Vector3.INF) -> bool` (dusk/night, low light in fog/rain/storm, or inside a tunnel;
  with `at` it tests that position for the tunnel), `get_precipitation()`, `get_rain()`, `get_wind_strength()`.
- RoadBuilder: `street_lamp_spots()` (shared by lamp posts and lamp lights; never on a road, junction mouth or fillet),
  RoadNetwork `edge_clearance(pos)`. WorldGen `river_query(p)` (smoothed river line with a cheap area test).
- Traffic: the nearest 12 cars within 150 m run physics (slot hand-over); kinematic cars within 175 m carry colliders,
  so nothing near the player is a ghost. `main._place_on` steps the player forward if a vehicle occupies the spot.

## Additions after playtest round 2
- Surfaces: `SurfaceData.paved`, `wet_id`, `wet_slide`, `slide_for(wetness)`; wet variants (`asphalt_wet`, new
  `concrete_wet`) carry the dry grip numbers and the slide factor scales continuously with wetness (no grip step at
  `CarController.WET_LOOK = 0.35`, which only switches the look/HUD name).
- CarController: `rewinding` (true while the rewind scrubs; telemetry shows the recorded state, tyres are quiet);
  automatic gearbox uses a smoothed pedal demand (keyboard taps read as part throttle) and a direct kick-down to the
  target gear. CarRewind: `is_rewinding()`; the buffer records damage; release picks a spot clear of traffic/rivals.
- Rewind vs activities: CarRewind asks `Game.activities.rewind_blocked()` (true during a race / time-trial countdown or
  run -> "Rewind is off during races") and calls `on_player_rewind()` (cancels a zone / drift / jump attempt).
- Overlays during events: the race / time-trial clock, rivals and zone timers freeze while `Game.is_overlay_open()`.
- Menus: menu hotkeys are inert while any menu is open; a scripted open takes over the closing menu's pause.
- Time-reactive group `Game.TIME_REACTIVE_GROUP` (`&"sunward_time_reactive"`): photo mode processes these nodes for a
  short pulse while paused after a time/weather change. Members: lamp pool, settlements (night windows), traffic manager
  (traffic lights), CarVisuals (head/tail lights), dressing (wind/wetness/snow).
- Traffic: `spot_margin(pos, forward, approach := true)` (free distance to approaching traffic at a spot) and
  `make_way(pos, forward)` (holds/clears approaching traffic for a placed player car); restricted vehicle types only
  use lanes from which an allowed exit exists.
- Headlights: the player's are a projected low beam; traffic headlights are dimmer cones.
- Props: `PropLibrary.trimesh(name)`; kit props load from `assets/imported/props/merged/*.res` written by
  `tools/bake_props.tscn` (re-run after re-exporting a kit).

## Additions after playtest round 3
- Settlement colliders: buildings and landmarks use their baked trimesh (`<Name>_col.res`), rocks/cacti a convex hull,
  thin props (fences, walls, poles, banners, lamps, benches, mailboxes, bins, rocks, cacti) sit on layer 6 (value 32)
  like barriers: bodies hit them, wheel rays never stand on them. Generated `Apron_*` / `Pad_*` nodes are the fuel
  station ramps and foundation pads. `Settlements.lamp_heads` (fuel-station / diner lamps) feeds the lamp pool.
- Dressing rock and cactus colliders are fitted hulls on layer 6; queries with mask 1 (`World.ground_at`, respawn snap)
  do not see them, the camera (mask 1|32) does.
- CarController: signal `shift_refused(requested)` (manual downshifts that would over-rev are refused);
  `CarData.reverse_max_kmh` (reverse limiter, 25-35 km/h). The braking line sticks to the road the car is on.
- Race rivals: lights from `lights_needed(position)`; after a race they cruise on and leave only out of view (still
  listed by `get_ai_cars()`). Traffic edges to the verge to squeeze past an oncoming race car. Traffic headlights fade
  in over 95-140 m. Festival flags register dressing exclusions (pocket + approach lane) before Dressing starts.
- Activities ignore triggers and discoveries while `Game.benchmark_mode` is on.
- Loading screen warms up render pipelines for the kit props and first-seen materials; F12 encodes/saves on a thread.
