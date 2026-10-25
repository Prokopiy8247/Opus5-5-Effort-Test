# Research Notes: Open-World Racer (Godot 4.7.2)

Project: an original open-world arcade-sim racer of about 4 x 4 km with 40-60 km of road, 4+ regions, 10 original Blender-authored cars, traffic, day/night and weather. Engine: Godot 4.7.2 with Jolt Physics. Blender master file: `Opus55ForzaUltracodeEffort.blend`.

## 1. Method

The research was done on 2026-10-23 as five separate web-research passes, one per topic: world structure, activities and presentation, cars and handling systems, Godot 4.7 technical notes, and API pricing. Every finding below is summarized in our own words. Long passages are not copied, and numbers come from the cited pages. Source strength varies. Developer statements (Xbox Wire, forza.net) are the most reliable, then press previews and reviews, then community guides and forums, which are weaker and are marked "(community)" where it matters. Most developer detail predates the 2021 launch, so the shipped game may differ. Every Godot claim was checked against the class reference dump of the installed Godot 4.7.2 (`--doctool` output: 771 core classes plus 258 module classes, with signatures and defaults only and empty descriptions). Behaviour that the dump cannot show was taken from docs.godotengine.org/en/stable, which is the 4.7 documentation. **Naming rule:** Forza Horizon 5 (FH5) is named only in this research file. The game uses no Forza, Horizon, Playground or Microsoft names, terms, logos or assets. Generic ideas such as a performance rating, class bands or a braking line are rebuilt under our own names. A completeness review on the same date added road classes and how events use them, the festival-site structure, roster size and car acquisition, weather visibility effects, where the assists are shown, photo challenge rules, and Godot notes on `PhysicsDirectSpaceState3D`, `MultiMeshInstance3D`, `OccluderInstance3D`, `WorldEnvironment` and `AudioStreamPolyphonic`. It also reworded present-tense lines so that nothing here reads as already built: this file describes plans only.

## 2. Forza Horizon 5 feature inventory

Decision key: **ADOPT** means build it essentially as FH5 does, with our own names and art. **ADAPT** means keep the idea but change its scale or mechanism. **SKIP** means it is out of scope.

### 2.1 World & biomes

| Feature | What it is | Decision | Reason |
|---|---|---|---|
| Map scale | Officially about 1.5x the previous game's map. No official km² figure exists. | ADAPT | Our 16 km² has to feel big through density, elevation and variety, not distance. |
| Condensed best-of geography | Real places are compressed and rearranged to fit in more variety. | ADOPT | A condensed best-of rural region is the only way to make 16 km² varied. |
| Dominant landmark peak | A volcano visible from most of the map, with a mast at the summit, used for orientation. | ADOPT | One central peak with an original observatory mast becomes our main navigation landmark. |
| Twin summit routes | Separate tarmac and dirt climbs on the same mountain. | ADOPT | We get two hill-climbs from one mountain: the hairpin pass and a gravel route. |
| Diagonal highway spine | A long motorway crossing the map corner to corner. | ADOPT | It gives the road network a fast backbone and a top-speed corridor. |
| Long drivable beach | A very long coastal beach used for off-road driving. | ADAPT | A short sand strip beside the coastal road gives an off-road surface cheaply. |
| Pre-built venues | A dune arena, a stadium and drag strips on an airfield. | ADAPT | One small airstrip for drag and top-speed runs. No stadiums. |
| 11 distinct biomes | Each biome has its own terrain shape, signature plant, soil colour, light mood and soundscape. | ADAPT | We build 4 regions. Each gets one data resource: soil tint, 2-3 plant species, rock material, ambient loop and fog offset. |
| Farmland | Green rolling hills, orchards, shallow rivers, homesteads, breakable fences. | ADOPT | Planned as our farmland/forest valley with its river and village. |
| Jungle | A dense canopy with filtered light, waterfalls and rivers. | ADAPT | Becomes a darker forest section in the valley, with an optional waterfall. |
| Canyon / arid hills | Layered rock that erodes into hoodoos, strong echoes, golden grass plains. | ADAPT | Becomes our arid canyon/desert plateau with its gas station, plus a reverb audio zone in the gorge. |
| Rocky / tropical coast | Open sea views oriented for sunsets, palms that thrash in storms. | ADAPT | Becomes our coastal cliffs and beach road, facing west for sunsets. |
| Volcano altitude | Thinner vegetation and the only snow on the map; rain turns to snow higher up. | ADAPT | Becomes the mountain highlands: grey rock, patchy snow, denser fog near the top. |
| Sand dunes, living desert, swamp | Sculpted dunes, cacti fields, and mangrove water racing. | SKIP | Expensive to sculpt and out of tone. A single shallow ford keeps the water idea. |
| Hub city | A downsized hillside city with tunnels and echoing streets. | ADAPT | Our largest settlement is a village of 20-40 buildings with a plaza and one short tunnel. |
| Small towns and ruins | Oasis and beach towns plus ruins and temples as set pieces. | ADAPT | 2-3 hamlets at junctions plus original landmarks: lighthouse, old mine, hill fort. |
| Drive-through props | Golf course, farmyards, fences you can smash through. | ADOPT | Breakable fences are cheap physics props that make the world feel physical. |
| Lesson: harsh biome edges | Press found the biome borders sometimes jarring. | ADOPT (lesson) | Blend regions with splat-mask transitions and mixed vegetation bands. |
| Lesson: LOD pop-in | Press saw vehicles, buildings and foliage pop in. | ADOPT (lesson) | Use visibility ranges with margins and per-chunk MultiMesh from day one. |

### 2.2 Roads & events

**Road classes and how events use them.** FH5 has no published road taxonomy. This table is assembled from guides and maps (mostly community sources). Event disciplines map closely onto surface types, and the layout terms "sprint" (point to point) and "circuit" (laps) apply to every discipline.

| Road class / surface | How FH5 uses it | Decision | Reason |
|---|---|---|---|
| Multi-lane motorway | The cross-map backbone. It holds speed traps, top-speed runs, night street races and the heaviest traffic. | ADOPT | Becomes our diagonal highway spine, the one place built for very high speed. |
| Twisty paved rural and mountain roads | Road-race sprints and circuits, speed zones, drift zones and the tarmac summit climb. | ADOPT | Planned as the valley, pass and coast roads that carry most of our events. |
| Town streets | Tight urban sections, used mainly by night street racing with traffic left on. | ADAPT | 1-2 village loops plus the tunnel, used by the night race. |
| Marked dirt and gravel roads | Dirt racing in two layouts: "Trail" events are longer point-to-point runs and "Scramble" events are short multi-lap loops (one guide lists a 1.1-mile loop run for 4 laps). | ADOPT | The planned gravel network gets both layouts, so a single road set yields two event types. |
| Unmarked open terrain | Cross-country circuits and point-to-point routes over fields, beach and scrub, plus A-to-B trailblazers. AWD cars with soft suspension do best. | ADAPT | Limited to the arid plateau and the beach strip, where the terrain can be checked for exploits. |
| Fixed event start points | Every event starts from a fixed marker on the map, and even player-made routes must begin at one of them. | ADOPT | Event starts will be data markers snapped to the road graph, with a `layout` field of `sprint` or `circuit`. |

| Feature | What it is | Decision | Reason |
|---|---|---|---|
| Road racing | Sprints and circuits on twisty tarmac. | ADOPT | This is the core loop. We plan 4-6 checkpoint races on highway, valley, pass and coast roads. |
| Street racing | Night races on public roads (town streets and highways) with ambient traffic left on. | ADAPT | A night-locked loop through 1-2 villages and the tunnel, with traffic on. |
| Dirt racing | Gravel and mud races in two forms, long trails and tight loops. | ADOPT | 3-4 events on our gravel network, where rain makes the grip change interesting. |
| Cross-country | Off-road checkpoint routes across open terrain. | ADAPT | 2-3 short routes over the arid plateau and the beach strip. |
| Drag | A short straight launch-and-acceleration race. | ADAPT | Held on the airstrip or a highway straight. |
| Hill-climbs | Timed tarmac and dirt climbs to the summit. | ADOPT | They become time trials on the pass and the gravel route. |
| Showcases | Scripted races against planes, hovercraft and the like. | SKIP | Each one needs custom vehicles and choreography. |
| Expeditions / story chapters | Cinematic races that build outposts and gate progress. | SKIP | We use a simple "finish N activities" unlock instead. |
| Event editor, online tours, live playlists | Live-service and user-generated layers. | SKIP | Out of scope for an offline single-player build. |
| Main festival site | The central festival site, holding menus, car purchase and fast travel. Reaching it is the first milestone. | ADOPT | The garage, car select and spawn point are planned for the main village. |
| Discipline outposts | Five themed bases, each built by finishing one expedition. They cover road, dirt, cross-country, street and stunt events, and each also serves as a fast-travel point. | ADAPT | 2-3 small activity clusters with fast travel and no construction sequences. |
| Road discovery | Undriven roads show orange on the map, and driving each one pays a small reward. | ADOPT | The planned road graph would make this simple to track, and "drive every road" suits a 40-60 km network. |

### 2.3 Weather & seasons

| Feature | What it is | Decision | Reason |
|---|---|---|---|
| Weekly season rotation | Four seasons cycle on a weekly live-service schedule. They suit Mexico's climate (dry, hot, storm, wet) rather than a temperate year, and each changes the weather mix and the landscape colours. | SKIP | We have no seasons in scope. |
| Regional weather | Different parts of the map can have different weather at the same moment. | ADAPT | One global weather state, with an altitude modifier that thickens fog and sleet on the pass. |
| Altitude snow | Rain becomes snow on the peak, and peaks keep their snow. | ADAPT | Snow decals and cold fog on the highlands. Real snowfall is optional. |
| Dust storms | Volumetric dust that light passes through. It belongs to the dry season, and inside a storm you can see only a few metres. | SKIP (as weather) | Not one of our states, but the same tech gives gravel dust trails and road haze. |
| Tropical storms | Heavy rain, strong wind, mist and violently moving palms. It belongs to the storm season. | ADAPT | This is the model for our Storm state: heavy rain, gusting foliage, lightning, lowest grip. |
| Distant visible storms | Storm cells you can see from far away and drive toward. | SKIP | It needs true regional weather. |
| Wet grip | Wet surfaces lower traction and shift the fastest lines, and mud lowers it further. Guides rate rain as what makes dirt events hardest. | ADOPT | A per-weather grip multiplier on the tyre model is the key gameplay link. |
| Puddles / aquaplaning | Community reports say FH5's version is weak or missing. | ADAPT | A few puddle zones in dips with a brief grip drop are a cheap way to stand out. |
| Weather-reactive scenery | Leaves and palms move with the wind. | ADOPT | A global `wind_strength` shader uniform driven by the weather state. |
| Visibility: fog, rain, dust | Weather mainly reduces visibility through fog density, rain haze and, at the extreme, dust storms. | ADOPT | Fog start/end, volumetric density and sky haze come from each weather key. Storm and fog keep at least 60-80 m of usable sight so races stay fair. |
| Water on windscreen and lens | Water spray and droplets collect on the windscreen and also on the third-person camera lens. Players complain that the lens drops carry into drone and photo views with no toggle (community). | ADAPT | An optional screen-space droplet overlay during rain and fords, with an off toggle in settings and automatic hiding in photo mode. |
| Dirt and wash-off | Bodywork gets muddy or dusty off-road and comes clean after driving through water (press review). | ADAPT | One `dirt_amount` parameter on the car-paint shader that rises on gravel and sand and falls in rain and fords. |

Proposed starting grip multipliers (our own numbers, since FH5 publishes none): clear 1.00, cloudy 1.00, fog 0.95, rain 0.80, storm 0.70, and a further x0.85 on gravel. Road wetness ramps up over time instead of switching instantly.

### 2.4 Time of day & lighting

| Feature | What it is | Decision | Reason |
|---|---|---|---|
| Captured HDR skies | Real skies photographed at 12K over hundreds of hours and used to drive scene lighting. | SKIP | Far beyond our scope. We use Godot's Physical or Procedural sky with keyframes instead. |
| Sky preset matrix | More than 2,000 combinations of time and weather. | ADAPT | About 6 time keys x 5 weather states for sky tint, sun energy, fog and ambient, blended at runtime. |
| Day cycle length | A full day lasts roughly 1.5 real hours and night is short (community). | ADAPT | A configurable 24-30 minute cycle with a generous night share. |
| Night extended by demand | Players liked night driving and it was lengthened. | ADOPT (lesson) | Night driving with headlights is a highlight, so it should not be rare. |
| No manual time in free roam | Time is only settable inside custom events. | ADAPT | Dev console `time` and `weather` overrides, which also help testing. |
| Sunset showcase areas | Coastal areas were laid out for sunsets. | ADOPT | The coast road faces west and the summit viewpoint faces east. |
| Headlights / tail-light bloom | Night relies on car lights, and traffic tail lights bloom too much (community). | ADOPT (lesson) | A shadowed SpotLight on the player car only, emissive traffic lights, and clamped bloom. |
| Global illumination | A new GI system, with ray tracing only in the car viewer. | ADAPT | Low-setting SDFGI or sky ambient only. No ray tracing. |
| Volumetric atmosphere | Dust and mist as 3D media that light passes through. | ADOPT | Godot volumetric fog, with density and albedo per weather state and altitude falloff. |

### 2.5 Traffic, wildlife & ambient

| Feature | What it is | Decision | Reason |
|---|---|---|---|
| Civilian traffic | Ambient civilian cars in free roam. | ADOPT | Required by our spec. They drive on a lane graph from a pool with LOD. |
| Density by road class | Reportedly heavier on highways and in towns, sparse on remote roads (community). | ADOPT | Spawn weights per road class: highway high, village medium, pass and gravel low. |
| Perceived emptiness | Critics found the world under-populated. | ADAPT | A small map can afford slightly higher density near the player, under a hard pool cap. |
| No density control | Players cannot adjust or disable traffic. | ADAPT | Density is exposed in the console and the debug menu for testing and performance. |
| Stuck or crashed traffic | Traffic jams, crashes and flips are reported. | ADOPT (lesson) | Despawn stuck or flipped cars when they are out of view and respawn them ahead on the graph. |
| Traffic vehicle set | Everyday cars, plus some local vehicles. | ADAPT | 4-6 original low-poly traffic models (hatch, sedan, pickup, van, truck, bus). |
| Animals | Goats, donkeys, flamingos and others. | ADAPT | Static or idle-animated grazing animals in fields, with no AI behaviour. |
| Birds and insects | Birds over beaches and butterflies in the jungle. | ADOPT | Cheap GPU particle flocks over the coast and valley. |
| Biome soundscapes | Distinct ambience per place, with echoes in canyons and towns. | ADOPT | Ambient audio zones plus reverb buses in tunnels and gorges. |

### 2.6 Activities

| Feature | What it is | Decision | Reason |
|---|---|---|---|
| Speed trap | A fixed camera gate records your speed as you pass. | ADOPT | One Area3D plus a speed read. 6-8 on the highway and coastal straights. |
| Speed zone | Your average speed between two gates is scored, and cutting the course fails it. | ADOPT | Two gates and an on-road check. 4-6 on the pass and the coast. |
| Drift zone | A road section scored by drift angle and speed. Stopping or leaving it resets the score. | ADOPT | Would reuse the planned drift scorer. 4-6 zones on the hairpins and gravel. |
| Danger sign | A jump scored by distance, failed by a bad landing or a crash. | ADOPT | Built on authored crests and ramps with an "upright, no hard impact" landing check. 3-5 of them. |
| Trailblazer | Get from A to B by any route, scored on time. | ADAPT | 2-3 runs, each with a tall visible finish beacon and terrain checked for exploits. |
| Star thresholds | Each activity has 1/2/3-star targets, shown on the map card. | ADOPT | Thresholds stored as data plus a personal best, tunable from the console. |
| Skill chains | Drift, near-miss, air and speed skills feed a multiplier, which a crash wipes. | ADOPT | Traffic makes near misses natural. Start with 6-7 skills and 2-3 combos. |
| Per-car perk trees | Skill points buy per-car perks. | SKIP | With 10 cars, skill score converts straight to credits/XP. |
| XP bonus boards | Smashable signs that play a jingle nearby. Ones you passed but missed show on the map. | ADOPT | 30-40 original smashable collectibles, with the proximity sound and the map reveal. |
| Fast-travel boards | Smashable signs that make fast travel cheaper. | ADAPT | No fast-travel economy. A few boards unlock extra travel points instead. |
| Barn finds | A rumour circle leads to a hidden classic car that gets restored. | ADAPT | 1-2 of our 10 cars unlock from hidden barns with an orbit-camera reveal and no timer. |
| Accolades | Auto-tracked goals whose rewards must be claimed by hand, which reviewers found tedious. | ADAPT | A progress checklist that pays out automatically. |
| Player houses | Purchasable fast-travel homes with perks. | SKIP | The main hub covers this role. |

Planned counts (our extrapolation): 4-6 road races, 1-2 night village races, 3-4 dirt, 2-3 cross-country, 6-8 speed traps, 4-6 speed zones, 4-6 drift zones, 3-5 jumps, 2-3 A-to-B runs and 30-40 boards. Time trials reuse the race routes against personal-best ghosts.

### 2.7 Cars, classes, customization, tuning & upgrades

| Feature | What it is | Decision | Reason |
|---|---|---|---|
| Roster size | Officially 426 cars were confirmed before launch, with more announced later. The count kept growing through updates and paid packs (community totals vary). | ADAPT | 10 original cars, each chosen to cover a different type and surface niche, so the roster has breadth without depth. |
| Car acquisition | Cars come from a dealer catalogue bought with credits, random reward spins, progression and event rewards, and hidden barn finds. | ADAPT | A starter car, credit purchases in the garage, and 1-2 barn finds. Random reward spins are SKIPPED: there is no economy to balance them, and they add nothing to a short game. |
| Performance rating | A single 100-999 number derived from simulated lap times. | ADAPT | Our own "Performance Rating" from a weighted formula of power-to-weight, top speed, grip, braking and launch. |
| Class bands | Seven lettered bands that cap event entry. | ADAPT | Four bands with our own labels (Street / Sport / Pro / Elite). Upgrades can lift a car one band. |
| Bands set from lap data | Band edges were fitted to roster lap times. | SKIP | Hand-set edges are enough for 10 cars. |
| Stat bars | A short bar summary per car (speed, handling, acceleration, launch, braking, off-road). | ADOPT | Cheap garage UI that reuses the rating inputs. |
| Car type tag | One category label per car, used for filters and event eligibility. | ADOPT | One enum on the car resource, with 7-8 original type names across the 10 cars. |
| Rarity, manufacturer and country tags | Extra filters and price groups. | SKIP | There is no economy or roster depth to support them. |
| Paint + finish | A colour picker plus gloss, matte, metallic and other finishes. | ADAPT | Four finish presets (Gloss/Matte/Metallic/Satin) on one shared car-paint shader. |
| Livery editor | A layered vinyl editor with design sharing. | SKIP (editor) | Ship 2-3 tintable preset liveries per car instead. |
| Rims, calipers, tint | Rim styles and colours, caliper colour, window tint. | ADAPT | About 6 shared rim meshes. Caliper and tint are single material parameters. |
| Body kits / swaps | Bumpers, widebody, engine, drivetrain and aspiration swaps. | SKIP | Too much modelling and balance work for 10 cars. |
| Upgrade categories | Tiered parts (stock to race) for engine, drivetrain, tyres, handling and aero. | ADAPT | 7 categories x 3 tiers (Stock/Sport/Race) as multiplier tables. |
| Tyre compounds | Street, sport, slick, rally, off-road and drift compounds. | ADOPT | Maps directly onto our surface x weather grip table. |
| Weight reduction | Tiered mass reduction. | ADOPT | A one-line change to the rigid-body mass. |
| Aero | Front and rear downforce parts. | ADAPT | A speed-squared downforce per axle, on Pro/Elite cars only. |
| Auto-upgrade to class cap | One button builds a car to the top of a band. | ADOPT | Useful for players and for the dev console. |
| Race parts unlock tuning | Race-tier parts unlock the matching tuning sliders. | ADAPT | Each tuning tab is gated behind that category's Race tier. |
| Tuning sliders | Tyre pressure, gearing, alignment, anti-roll bars, springs, damping, aero, brakes, differential. | ADAPT | Keep pressure, final drive, camber/toe, ARB, springs/ride height, bump/rebound, brake bias, diff lock. |
| Saved tunes | Tunes can be saved and shared online. | ADAPT | 3 local JSON presets per car in `user://`, with no sharing. |
| Load-sensitive grip / off-road penalty | Suspension load feeds grip, and grass and dirt cut grip and braking more. | ADOPT | One surface x weather table applied to both lateral grip and braking. |
| Damage | Cosmetic, or affecting performance. | SKIP (mechanical) | Cosmetic scuffs at most. |

### 2.8 Assists & difficulty

| Feature | What it is | Decision | Reason |
|---|---|---|---|
| Where assists are shown | One Difficulty page in the settings, reachable from the pause menu and before any event. AI difficulty sits at the top, then a preset that sets every assist row below it, then braking, steering, traction control, stability control, shifting, driving line, damage/tyre wear and rewind. A credit bonus for the current setup rises as assists are removed. | ADOPT | One Assists page in the pause menu and on the event-start card, using the same top-down order and a live score-multiplier readout. Our addition: small ABS/TC/SC lamps on the HUD that flash when an assist steps in (none of the sources describes such lamps in FH5). |
| Assist presets | Bundled settings, with every row still customizable. | ADOPT | Relaxed / Standard / Expert / Custom, chosen on first boot. |
| Braking assist / ABS | Auto-brake, ABS on, or ABS off, with smooth ABS modulation. | ADOPT (ABS) | ABS clamps the slip ratio. Auto-brake is used only on activity routes. |
| Steering modes | Auto-steer, assisted, standard or simulation. | ADAPT | Standard (speed-sensitive with countersteer help) and Simulation (raw). |
| Traction control | Cuts power when the wheels spin. | ADOPT | Torque reduction from the slip ratio. |
| Stability control | Limits yaw with brakes and throttle. | ADOPT | A per-wheel brake on yaw-rate error, which also helps keyboard players. |
| Shifting | Automatic, manual, or manual with clutch. | ADOPT (auto/manual) | The clutch only matters for wheel users. |
| Driving line | A line on the road with three modes: off, braking-only or full. Its colour shifts from green (keep accelerating) through yellow and orange to red (brake hard); the colour key is documented for the previous game and looks unchanged. | ADAPT | Our own ribbon style and colour-blind-safe palette, defaulting to braking-only. |
| Rewind | Rewinds the last few seconds. | ADAPT | A ring buffer of about 10 s of player state, single-player only. |
| Launch control | Holds revs for a clean start. | ADAPT | A simple RPM hold at activity starts. |
| Reward bonus for fewer assists | A credit multiplier shown live in the menu. | ADAPT | Becomes an activity score multiplier. |
| AI difficulty tiers | A named ladder of AI skill levels, with complaints about catch-up. | ADAPT | 3-4 tiers scaling AI pace and target times, with at most mild, predictable catch-up. |
| Game-speed slider | Slows the world for accessibility. | ADAPT | `Engine.time_scale` from settings and the console. Jolt stability must be tested. |

### 2.9 Cameras

| Feature | What it is | Decision | Reason |
|---|---|---|---|
| Chase near / far | Two third-person distances. | ADOPT | One spring-arm chase camera with two presets, lag, and FOV that rises with speed. |
| Hood and bumper | First-person exterior views. | ADOPT | One Marker3D per car each, which costs almost nothing. |
| Cockpit | An interior view with a working dashboard. | SKIP | It would need 10 interiors with live gauges. Stretch goal at most. |
| View cycle, look-back, FOV, shake | One-button cycling plus settings. | ADOPT | Small touches that make the cameras feel finished. |
| Drone free camera | A free-flying scouting camera with the car parked. | ADAPT | Would reuse the planned photo-mode camera with a range limit, which helps find collectibles. |

### 2.10 HUD, map & navigation

| Feature | What it is | Decision | Reason |
|---|---|---|---|
| Speedometer / tach / gear | An RPM dial, digital speed and gear. FH5's needle was criticized as hard to read. | ADOPT | Bottom-right, with an arc scaled to each car's redline, a high-contrast needle and a km/h-mph toggle. |
| Minimap | Roads, route, icons and a player arrow (layout confirmed only by fan recreations). | ADOPT | Bottom-left, round and heading-up, drawn as 2D polylines from the road graph. |
| Waypoint + GPS | A map waypoint routed along the roads. Players found the route colour hard to tell apart. | ADOPT | A* over the road graph with a strong, colour-blind-safe route colour (stretch: turn cues). |
| In-world guide line | The 3D line doubles as GPS guidance in free roam. | ADOPT | A ribbon about 150-300 m ahead along the route, readable in rain and fog. |
| Full map | Pan/zoom with icon filters and hover cards. Filters reset on every launch. | ADOPT | Filters are saved. Cards show thresholds, personal bests, waypoint and travel buttons. |
| Fast travel | Paid and restricted until a late unlock. | ADAPT | Free travel to discovered hubs and activity starts. Teleport-anywhere is console only. |
| Notification toasts | Popups for XP, discoveries and level-ups, with per-category toggles. | ADOPT | A queued toast stack with category toggles and a duration setting. |
| HUD toggles / accessibility | Per-element toggles (for example the minimap, skill readout and wrong-way warning), text scaling and colour-blind modes. Reviewers wanted backing panels. | ADOPT | Every HUD element gets a backing panel, plus text scale and palette options. |
| Voice GPS assistant | Spoken directions without subtitles. | SKIP | A short on-screen text cue is better and more accessible. |

### 2.11 Photo mode & presentation

| Feature | What it is | Decision | Reason |
|---|---|---|---|
| Photo mode | Freezes the game and gives a free camera with FOV, exposure, DOF, filters, shutter and bokeh. | ADAPT | Stretch goal: pause, orbit/free camera, FOV, exposure, DOF via CameraAttributes, a few filters, PNG save. |
| Photograph every car | A collection reward for photographing each car you own. | ADAPT | A small, satisfying set of 10, validated by on-screen size and distance. |
| Landmark photo challenges | Rotating weekly tasks, usually to photograph a given car (or car type) at a named landmark, for a cosmetic reward. Some variants leave the location open or require the photo during an event. | ADAPT | 5-8 permanent challenges at our landmarks. Each asks for a time-of-day or weather condition instead of a specific car, which shows off the day/night and weather systems. They are checked by landmark distance, on-screen size and the current weather/time key. |
| Centre-screen skill popups | Large score popups criticized as clutter. | ADAPT | A small skill readout kept off-centre. |
| Gauge start-up sweep | The needle sweeps on start and wobbles at redline (seen in fan recreations). | ADOPT | A cheap touch of polish in the HUD tween. |
| Avatar, emotes, motion-blur shutter | Character and cinematic extras. | SKIP | Not worth it for a single developer. |

## 3. Godot 4.7 technical notes

Marks: **VERIFIED-IN-DUMP** means the name, signature or default is in the installed 4.7.2 dump. **DOCS-ONLY** means the fact comes from the 4.7 online docs. **UNVERIFIED** means it comes from prior knowledge and must be tested. The dump holds signatures only, with no descriptions and no deprecated or experimental markers, and it leaves out built-in Variant types such as `@GlobalScope`, `Vector3` and `Callable`.

### 3.1 Vehicle physics: decision by drive test
- **VERIFIED-IN-DUMP**: `VehicleBody3D` has `engine_force`, `brake` and `steering`, with mass overridden to 40.0. `VehicleWheel3D` defaults: `wheel_radius` 0.5, `wheel_rest_length` 0.15, `suspension_travel` 0.2, `suspension_stiffness` 5.88, `suspension_max_force` 6000, `damping_compression` 0.83, `damping_relaxation` 0.88, `wheel_friction_slip` 10.5, `wheel_roll_influence` 0.1. It also has `get_skidinfo()`, `get_rpm()` and `is_in_contact()`.
- **DOCS-ONLY**: VehicleBody3D is a simple raycast model. The docs warn it is not for realistic physics and suggest a custom RigidBody3D for anything advanced. It has no gears, its forces scale with mass, and grip is one scalar per wheel. There is no clean way to change slip per wheel at runtime (godot-proposals #13357), and the Jolt page does not mention it.
- **VERIFIED-IN-DUMP**: The custom-car APIs are all present. RigidBody3D has `_integrate_forces(state)`, `apply_force(force, position)`, `apply_torque`, `continuous_cd`, `center_of_mass_mode`/`center_of_mass` and `inertia`. `PhysicsDirectBodyState3D` has `get_velocity_at_local_position`, `get_space_state()` and `step`. For queries there are `PhysicsRayQueryParameters3D.create(from, to, mask, exclude)`, `intersect_ray`, `cast_motion`, and ShapeCast3D's `get_closest_collision_safe_fraction()`.
- **DOCS-ONLY**: The `position` argument of `apply_force` and `get_velocity_at_local_position` is a global-space offset from the body origin, despite the parameter name. A miss from `intersect_ray` returns an empty Dictionary.
- **VERIFIED-IN-DUMP** (`PhysicsDirectSpaceState3D`): it is reached through `World3D.direct_space_state`. Its methods are `intersect_ray(PhysicsRayQueryParameters3D) -> Dictionary`, `intersect_shape(PhysicsShapeQueryParameters3D, max_results=32) -> Dictionary[]`, `cast_motion(PhysicsShapeQueryParameters3D) -> PackedFloat32Array`, `collide_shape(params, max_results=32) -> Vector3[]`, `get_rest_info(params) -> Dictionary` and `intersect_point(PhysicsPointQueryParameters3D, max_results=32) -> Dictionary[]`.
- **DOCS-ONLY**: The space state is fetched with `get_world_3d().direct_space_state` and is safe only inside `_physics_process`, because elsewhere the space may be locked. Inside `_integrate_forces` it comes from `state.get_space_state()`. An `intersect_ray` hit returns `position`, `normal`, `collider`, `collider_id`, `rid`, `shape` and `face_index`. `get_rest_info` returns `point`, `normal`, `collider_id`, `rid`, `shape` and `linear_velocity`. `cast_motion` returns `[safe_fraction, unsafe_fraction]`, which is `[1.0, 1.0]` when nothing is hit. The car's own RID is left out with the `exclude` array (or the last argument of `PhysicsRayQueryParameters3D.create`).
- **Decision**: Wheel probes will run inside `_integrate_forces` using `state.get_space_state()`: one ray per wheel, with a sphere `cast_motion` as the fallback if rays snag on edges. Traffic and AI look-ahead rays will run only in `_physics_process`, with the collision mask restricted to the road and vehicle layers.
- **Decision**: We build both a custom raycast/shapecast car (a `RigidBody3D` on Jolt with our own tyre model: slip angle, surface x weather grip, handbrake, assists) and a `VehicleBody3D` baseline with the same mass and tuning. Then we drive the same test loop with both and keep whichever is more stable and more controllable. The custom car is the expected winner. Lesson from a forum report: clamp suspension compression and add a bump-stop impulse so the car cannot sink at high speed.
- **VERIFIED-IN-DUMP**: `physics/3d/physics_engine` defaults to `"DEFAULT"`. **DOCS-ONLY**: DEFAULT still means GodotPhysics3D, and new projects only get Jolt because the template writes it. **Action**: set `3d/physics_engine="Jolt Physics"` explicitly.
- **VERIFIED-IN-DUMP**: Jolt keys live under `physics/jolt_physics_3d/*`: velocity_steps 10, position_steps 2, CCD movement threshold 0.75, max_linear_velocity 500 m/s, `queries/enable_ray_cast_face_index` false, `queries/use_enhanced_internal_edge_removal` false. **DOCS-ONLY**: `face_index` is -1 unless that flag is on, so we identify surfaces by collider group or meta. Enhanced edge removal reduces ghost bumps on heightmaps and trimeshes, so we will consider it for wheel queries.

### 3.2 Tick rate, interpolation, world size
- **VERIFIED-IN-DUMP**: `physics_ticks_per_second` 60, `max_physics_steps_per_frame` 8, `physics_interpolation` false, `Node.reset_physics_interpolation()`, `Node3D.get_global_transform_interpolated()`.
- **DOCS-ONLY**: Racing games want 60+ Hz in multiples of 60, so we plan 120 Hz and raise max steps with it. Turning interpolation on disables the jitter fix. After a teleport, set the transform and then reset interpolation. The camera is `top_level`, has interpolation off, and follows the interpolated transform in `_process`. At 360 km/h a car moves about 1.67 m per 60 Hz tick, so cars get `continuous_cd`.
- **DOCS-ONLY**: With ±2 km around the origin, single precision is fine (8192 m is the third-person guideline), so we need no double build.

### 3.3 Chunked terrain
- **VERIFIED-IN-DUMP**: `HeightMapShape3D` has `map_width`, `map_depth`, `map_data` and `update_map_data_from_image`. `ConcavePolygonShape3D.set_faces`. `ArrayMesh.add_surface_from_arrays(primitive, arrays, blend_shapes, lods, flags)`, with `Mesh.ARRAY_VERTEX`=0 through `ARRAY_INDEX`=12 and `ARRAY_MAX`=13. SurfaceTool's `generate_normals` and `generate_tangents`. FastNoiseLite (module) defaults to simplex-smooth, frequency 0.01, FBM, 5 octaves.
- **DOCS-ONLY**: Heightmap samples are 1 unit apart, centred on the shape origin, and scaled with Node3D scale. A `NAN` height makes a hole, which is useful at tunnel mouths. Images must be RF, RH or R8, and 8-bit terraces. Front faces wind clockwise. `SurfaceTool.generate_lod` is deprecated. Automatic mesh LOD happens only at import.
- **Decision**: Use 256 m chunks with 2 m cells (129x129 vertices), one StaticBody3D and one HeightMapShape3D per chunk, offset by half a span. Normals are computed analytically. Roads, bridges and tunnels are spline ribbons with ConcavePolygonShape3D, one body per surface type so grip can be looked up per collider.

### 3.4 Threading (WorkerThreadPool meshing)
- **VERIFIED-IN-DUMP**: `WorkerThreadPool.add_task(callable, high_priority, description)`, `add_group_task`, `is_task_completed`, `wait_for_task_completion`; `Mutex`; `call_deferred`; `threading/worker_pool/max_threads=-1`; `physics/3d/run_on_separate_thread=false`.
- **DOCS-ONLY**: Every task must eventually be waited on. The live scene tree is not thread-safe, so nodes are added with `add_child.call_deferred`. A resource must never be modified from two threads. Resizing a shared array needs a Mutex. The threaded render model is experimental, so we keep the default.
- **Decision**: Pool tasks will build the height, vertex, normal and UV packed arrays plus the per-chunk vegetation transforms. The main thread will poll for completion, then build the ArrayMesh, assign the collision shape and upload only a few chunks per frame.

### 3.5 Rendering at scale (MultiMesh dressing, LOD, shadows)
- **VERIFIED-IN-DUMP**: MultiMesh has `transform_format`, `use_colors`, `use_custom_data`, `instance_count`, `visible_instance_count`, `buffer` and `custom_aabb`. GeometryInstance3D has `visibility_range_begin/end`, `_margin`, `visibility_range_fade_mode` (DISABLED/SELF/DEPENDENCIES) and `lod_bias`. Node3D has `visibility_parent`. Also `rendering/occlusion_culling/use_occlusion_culling=false`, `rendering/mesh_lod/lod_change/threshold_pixels=1.0`, and on DirectionalLight3D `directional_shadow_max_distance=100`, PARALLEL_4_SPLITS. Camera3D `far` is 4000.
- **DOCS-ONLY**: MultiMesh instances are not culled individually, so we use one MultiMesh per chunk and species and set `custom_aabb`. Colour and custom-data flags can only change while `instance_count` is 0. Fade modes force transparency and cost performance, so we use plain ranges with margins as hysteresis. `visibility_parent` gives HLOD for far chunk meshes. Occlusion culling helps little in open terrain, so it is reserved for ridges and tunnel walls. Shadow distance will be 150-300 m.
- **UNVERIFIED**: The MultiMesh buffer layout is 12 floats of transform, then colour, then custom. We will confirm it by reading back `buffer` after `set_instance_transform`.
- **VERIFIED-IN-DUMP**: `MultiMeshInstance3D` has one member of its own, `multimesh`, and inherits the GeometryInstance3D visibility-range and shadow settings. `OccluderInstance3D` has `occluder` (Occluder3D), `bake_mask` (default all layers) and `bake_simplification_distance` (0.1). The shapes `ArrayOccluder3D` (`vertices`, `indices`) and `BoxOccluder3D` (`size`) exist. The occlusion project settings are `rendering/occlusion_culling/use_occlusion_culling=false`, `bvh_build_quality=2`, `occlusion_rays_per_thread=512` and `jitter_projection=true`, and `Viewport.use_occlusion_culling` is the per-viewport switch.
- **DOCS-ONLY**: A visibility range applies to the whole MultiMeshInstance3D node, not to each instance, which is another reason for one node per chunk and species. Occlusion culling has to be enabled in the project settings. Only opaque MeshInstance3D nodes are baked: MultiMeshInstance3D, particles and CSG are left out, so they need hand-placed occluders. Occluders are rasterized on the CPU (Embree), and moving one rebuilds the BVH, so occluders must stay static and hiding them is the cheap toggle. The gain is smaller on Forward+ (it already has a depth prepass) and is best indoors or behind large walls.
- **Decision**: Use one `MultiMeshInstance3D` per chunk and species, with `visibility_range_end` per species (grass short, trees long). Occlusion culling stays off at first. It is turned on only if benchmarks show it helps, with scripted `ArrayOccluder3D`/`BoxOccluder3D` shapes for ridge lines, tunnel walls and village blocks.

### 3.6 Environment, sky, fog, post
- **VERIFIED-IN-DUMP**: Environment has `tonemap_mode` (AGX=4), `volumetric_fog_*` (density default 0.05), `fog_aerial_perspective`, `fog_height_density`, `sdfgi_*`, `glow_*` and `adjustment_*`. ProceduralSkyMaterial and PhysicalSkyMaterial members are present, as are `Sky.process_mode` (REALTIME=3) and `radiance_size`, and `FogVolume`/`FogMaterial`.
- **DOCS-ONLY**: AGX keeps hue in bright scenes, with a white value of at least 6. SDFGI, SSR, SSIL and auto exposure are Forward+ only. Aerial perspective needs a sky background. Animating sky uniforms re-renders the radiance map, so a day/night cycle uses REALTIME with a small `radiance_size`.
- **VERIFIED-IN-DUMP**: `WorldEnvironment` has `environment`, `camera_attributes` and `compositor`. Environment has `sdfgi_enabled` (default false), `sdfgi_cascades` (4), `volumetric_fog_enabled` (false), `background_mode` and `fog_sky_affect` (1.0). `World3D` exposes the same `environment` and `camera_attributes`.
- **DOCS-ONLY**: Only one WorldEnvironment can be active in a scene. A Camera3D's own Environment or CameraAttributes overrides it, and the compositor falls back the same way.
- **Decision**: A single `WorldEnvironment` will be created by the world scene, and the weather/time system will edit its Environment resource in place. Photo mode will apply its DOF and exposure through a `CameraAttributesPractical` on its own camera, so the world defaults are never changed. A day/night x weather keyframe table will drive the sky, sun, ambient, fog and volumetric fog, and a FogVolume will add extra density on the highland summit.

### 3.7 Particles and skid marks
- **VERIFIED-IN-DUMP**: GPUParticles3D has `amount_ratio`, which sets rain intensity without a restart. Also `ParticleProcessMaterial`, `GPUParticlesCollisionHeightField3D` (`follow_camera_enabled`) and `Decal` (`distance_fade_*`). `rendering/limits/cluster_builder/max_clustered_elements=512`.
- **DOCS-ONLY**: GPU particles only collide with the particle-collision nodes, so a camera-following heightfield handles rain hitting the ground. Forward+ shares 512 clustered elements per view among lights, decals and probes.
- **Decision**: Skid marks will be a pooled dynamic ribbon mesh, not hundreds of Decal nodes. Decals will be used only for a few recent marks and for road paint.

### 3.8 Audio (AudioStreamGenerator engine sound)
- **VERIFIED-IN-DUMP**: AudioStreamGenerator has `mix_rate=44100`, `mix_rate_mode` (default CUSTOM) and `buffer_length=0.5`. Its playback has `push_buffer(PackedVector2Array)`, `get_frames_available()` and `can_push_buffer()`. Also `AudioStreamPolyphonic` (polyphony 32) and AudioStreamWAV (`data`, `format`, `loop_mode`, `load_from_buffer`). AudioStreamPlayer3D has `doppler_tracking`.
- **DOCS-ONLY**: The generator does not resample. The docs suggest 11025-22050 Hz when feeding it from GDScript. A short buffer lowers latency but risks crackle.
- **VERIFIED-IN-DUMP**: `AudioStreamPlaybackPolyphonic.play_stream(stream, from_offset=0, volume_db=0, pitch_scale=1.0, playback_type=0, bus=&"Master") -> int` returns a voice id (`INVALID_ID`=-1 on failure). There are also `set_stream_volume(id, db)`, `set_stream_pitch_scale(id, scale)`, `is_stream_playing(id)` and `stop_stream(id)`.
- **DOCS-ONLY**: Set the player's `stream` to an AudioStreamPolyphonic first, then call `get_stream_playback()` to get the polyphonic playback. `polyphony` caps the number of voices playing at once.
- **Decision**: A procedural engine will be synthesized per car (RPM-driven harmonics, load and redline character) at about 22050 Hz with `push_buffer`. Tyre squeal, wind and traffic will use pre-synthesized WAV loops. One-shot sounds (impacts, gear shifts, board smashes, skill chimes) will go through a single `AudioStreamPolyphonic` player per car, with pitch and volume varied per voice.

### 3.9 Input
- **VERIFIED-IN-DUMP**: `InputMap.add_action(action, deadzone=0.2)`, `action_add_event`, `Input.get_axis`, `Input.get_joy_axis`, `start_joy_vibration`. **DOCS-ONLY**: `JOY_AXIS_TRIGGER_RIGHT`=5. Older pages listed a deadzone of 0.5, so the deadzone is always passed explicitly.
- **Decision**: Actions will be registered in an autoload's `_ready()` instead of hand-writing `[input]` blocks, which also enables rebinding. Note that `load_from_project_settings()` wipes runtime actions.

### 3.10 glTF (.glb) pipeline from Blender
- **VERIFIED-IN-DUMP**: ResourceImporterScene `.import` keys: `nodes/apply_root_scale=true`, `meshes/generate_lods=true`, `meshes/create_shadow_meshes=true`, `meshes/ensure_tangents=true`, `materials/extract=0`, `nodes/use_node_type_suffixes=true`. `GLTFDocument` (module) and `EditorScenePostImport` also exist.
- **DOCS-ONLY**: Name suffixes are `-col`, `-convcol`, `-colonly`, `-noimp`, `-vcol`, `-occ`, `-rigid`, `-wheel` and `-vehicle`. glTF is +Y up with assets facing +Z. Godot's `Vector3.MODEL_FRONT` is +Z, while `Vector3.FORWARD` is -Z.
- **Decision (as implemented)**: Cars are modelled in the master `.blend` facing Blender +Y, which exports to glTF/Godot -Z (Godot `FORWARD`), so the controller uses `-basis.z` as forward (see `docs/ASSET_CONVENTIONS.md`); wheels are separate objects; vehicle collision boxes are built in code (no suffix colliders). Import LODs stay on.

### 3.11 Command line, screenshots, benchmarks
- **DOCS-ONLY**: The command-line options are `--headless`, `--import`, `--quit-after N`, `--write-movie out.png` (which forces fixed FPS), `--resolution`, `--fixed-fps` and `--print-fps`, and user arguments go after `--` (read with `OS.get_cmdline_user_args()`, VERIFIED-IN-DUMP).
- **DOCS-ONLY**: To take a screenshot, `await RenderingServer.frame_post_draw`, then `get_viewport().get_texture().get_image().save_png()`. **UNVERIFIED**: Headless runs have no GPU, so captures need a windowed run.

### 3.12 Dump vs docs discrepancies to remember
1. `DEFAULT` physics is not Jolt, so it must be set explicitly.
2. The dump shows no deprecations. For example, `SurfaceTool.generate_lod` and the MultiMesh array properties are deprecated only according to the docs.
3. The InputMap deadzone default is 0.2 in both the 4.7 dump and docs, while older pages say 0.5.
4. The "local" in `get_velocity_at_local_position` is actually a global-space offset.
5. Only the `physics/jolt_physics_3d/*` key names exist. The old `physics/jolt_3d` names are gone, and `solver_iterations` applies to GodotPhysics only.
6. glTF-specific importer options (`gltf/naming_version`, `gltf/embedded_image_handling`) are in neither the dump nor the class reference.

## 4. Pricing reference (for the final metrics)

Source: https://platform.claude.com/docs/en/about-claude/pricing, accessed 2026-10-23, prices in USD per million tokens (MTok). Model: Claude Opus 5.5 (`claude-opus-5-5`).

| Category | Rate |
|---|---|
| Base input tokens | $4 / MTok |
| 5-minute cache writes | $5 / MTok (1.25x base) |
| 1-hour cache writes | $8 / MTok (2x base) |
| Cache hits and refreshes (cache read) | $0.20 / MTok (0.05x base input for Opus 5.5) |
| Output tokens | $20 / MTok |

Modifiers listed on the page:
- **Batch API:** 50% off, so $2 input and $10 output. Caching multipliers stack with it.
- **Long context:** no long-context surcharge. The full 1M window is billed at standard rates.
- **US-only data residency (`inference_geo`):** multiplies every category by 1.1x.
- **Fast mode:** $8 input and $40 output, and it cannot be combined with Batch.
- **Thinking tokens:** billed as output tokens, in full, even when only a summary is shown. Prior-turn thinking left in context is billed as input. Source: https://platform.claude.com/docs/en/build-with-claude/thinking-steering-and-cost.

Worked example from the page: 50K input plus 15K output costs $0.20 + $0.30. These rates will be re-verified against the live pricing page at the end of the run before the final metrics block is computed.

## 5. Final committed feature list (ranked by priority)

1. **Runnable project**: Godot 4.7.2, Forward+, Jolt set explicitly, 120 Hz physics with interpolation, autoload input. A FH5 session starts straight into driving, so ours boots straight into a drivable scene.
2. **Blender to .glb pipeline**: a scripted export from `Opus55ForzaUltracodeEffort.blend` (car front = Blender +Y = Godot -Z as fixed in docs/ASSET_CONVENTIONS.md; vehicle collision built in code instead of suffixes; fixed export settings). Original cars need a repeatable art path from day one.
3. **First original car**: modelled, exported, imported with wheels and markers. It proves the pipeline end to end before the roster grows.
4. **Driving model**: a custom raycast RigidBody3D car vs a VehicleBody3D baseline, picked by drive test, with surface x weather grip. Handling is the heart of the genre: easy to pick up on a gamepad, but with a sense of weight.
5. **Assists**: ABS, traction control, stability control, auto/manual shifting, and Relaxed/Standard/Expert presets, on one Assists page (pause menu and event-start card) with HUD intervention lamps. In FH5, the assist ladder is what lets players of every skill level drive the same cars.
6. **Chase camera set**: chase near/far, hood and bumper, with speed FOV and look-back. These are FH5's core views, and the camera sells the sense of speed.
7. **Chunked terrain**: 256 m heightmap chunks meshed on WorkerThreadPool with streaming collision. It lets a 16 km² world load and run smoothly.
8. **First long road and region**: the farmland/forest valley with its river, village and a 5 km+ spline road. Farmland is FH5's calmest cruising biome and makes a natural first region.
9. **HUD**: speed/tach/gear with backing panels and a units toggle. This addresses FH5 readability complaints from the start.
10. **Dev console**: time, weather, teleport, spawn car, traffic density and time scale. FH5 cannot set time in free roam, and we need it for testing.
11. **Garage menu**: car select, stat bars and the Performance Rating band. It mirrors FH5's car-select hub with our own names.
12. **Debug / benchmark menu**: FPS, chunk and traffic counters, and a scripted benchmark route. FH5-style LOD pop-in is caught early.
13. **Civilian traffic**: lane graph, pooling, LOD, density by road class, and despawn of stuck cars. It targets the emptiness and gridlock complaints made about FH5.
14. **Mountain highlands**: hairpin pass, tunnel, viewpoint and snow, plus a gravel summit route. This is FH5's twin volcano climbs in original form.
15. **Arid canyon / desert plateau with gas station**: layered rock, a reverb gorge and golden-grass gravel roads. It comes from FH5's canyon and arid-hills biomes.
16. **Coastal cliffs and beach road**: a long bridge, the harbour hamlet, a sand strip, and a west-facing sunset road. It comes from FH5's sunset-oriented rocky coast.
17. **Full road network of 40-60 km**: a scenic loop of at least 20 km, several 5 km+ stretches, and a diagonal highway spine. FH5's fast cross-map backbone, scaled to our map.
18. **All 10 original cars**: distinct handling data, type tags and rating bands, bought in the garage or found in barns. FH5's variety comes from contrasting car types across surfaces, and our 10 have to cover those niches.
19. **Car audio**: an AudioStreamGenerator engine per car, plus tyre, wind and impact layers (one-shots through AudioStreamPolyphonic). Engine and tyre sound carry much of the sense of speed and weight.
20. **Day/night cycle**: a keyframed sky matrix, a generous night share and player headlights. Night driving was popular enough in FH5 to be extended.
21. **Weather**: clear/cloudy/rain/fog/storm with gradual wetness, a grip multiplier, per-weather visibility, rain particles, wind on foliage, an optional lens-droplet overlay and body dirt that washes off. In FH5, weather changes both grip and how far you can see.
22. **Settlements and dressing**: villages and hamlets, per-chunk MultiMesh vegetation, and breakable fences. These follow FH5's drive-through farmyards and small towns.
23. **Tunnels, bridges and landmarks**: the peak observatory mast, a lighthouse and an old mine, all visible from afar. Like FH5's volcano, they act as wayfinding landmarks.
24. **Stunt activities**: speed traps, speed zones, drift zones and danger-sign jumps with 1/2/3-star thresholds. They make up most of FH5's roadside activities.
25. **Checkpoint races and time trials**: road, dirt (trail and scramble layouts), cross-country and night-village races, all with sprint or circuit layouts and starting from markers on the road graph, plus summit time trials against personal bests. This is FH5's core race loop.
26. **Collectibles and discovery**: smashable boards with proximity sound, road discovery and 1-2 barn-find cars. FH5 uses these to reward exploration.
27. **Skill chains**: drift, near miss, air and speed with a multiplier that a crash wipes. This is the FH5 arcade feel layered on traffic.
28. **Customization, upgrades and tuning**: paint finishes, rims, preset liveries, 7 categories x 3 tiers, and tuning tabs gated by Race tier. These are FH5's garage depth at our scale.
29. **Photo mode (stretch)**: free camera, FOV/exposure/DOF through its own CameraAttributesPractical, filters, PNG save, and landmark photo challenges with time/weather conditions. FH5 uses photos to show off the world.
30. **Minimap, full map, GPS (stretch)**: a road-graph minimap, a filterable map with saved filters, A* routing and a guide ribbon. FH5-style navigation, plus answers to its colour and filter complaints.
31. **Save/load**: JSON in `user://` holding garage, tunes, progress, discoveries, settings and the last position. It gives persistent progress the way FH5's campaign does.
32. **Polish**: ambient zones, reverb, skid ribbons, dust trails, birds, toasts, and the gauge sweep. FH5's sense of place comes from layered small details.
33. **QA, performance, docs**: benchmark passes, LOD and visibility tuning, the README and the final metrics. These lessons come from FH5's pop-in criticism, and the run ends with honest measurements.

## 6. Sources

### World, biomes, weather, lighting, traffic
- https://news.xbox.com/en-us/2021/07/26/exploring-the-biomes-and-seasons-of-forza-horizon-5/
- https://videogameschronicle.com/news/forza-horizon-5s-art-team-explains-how-it-got-the-skies-to-look-so-realistic
- https://videogameschronicle.com/news/forza-horizon-5s-full-world-map-has-been-revealed
- https://gamingbolt.com/forza-horizon-5-weather-conditions-detailed-eliminator-and-super-7-return
- https://en.wikipedia.org/wiki/Forza_Horizon_5
- https://gtplanet.net/forza-horizon-5-map-revealed-20210809
- https://www.gtplanet.net/forza-horizon-5-season-change-20220310/
- https://gtplanet.net/forza-horizon-5-review-viva-la-evolucion
- https://www.carthrottle.com/post/8-things-we-learned-from-playing-forza-horizon-5
- https://www.purexbox.com/news/2021/07/new_forza_horizon_5_details_confirm_convertibles_drag_races_and_flamingos
- https://www.nme.com/news/forza-horizon-5-will-bring-back-seasonal-weather-but-with-a-new-change-2970061
- https://www.nme.com/news/forza-horizon-5-to-have-11-biomes-and-bigger-map-than-previous-game-3004141 (search summary)
- https://digistatement.com/forza-horizon-5-to-have-four-seasons-including-storm-dry-wet-hot
- https://traxion.gg/seasonal-conditions-and-unique-areas-explained-in-forza-horizon-5/
- https://traxion.gg/latest-forza-horizon-5-hotfix-update-addresses-convoy-issues/
- https://www.gfinityesports.com/forza-horizon-5/change-seasons-time/ (search summary)
- https://www.gfinityesports.com/article/change-time-of-day-night (search summary)
- https://expertbeacon.com/how-long-is-night-in-fh5/ (search summary)
- https://expertbeacon.com/what-are-all-the-race-types-in-forza-5/ (search summary)
- https://gamespot.com/articles/players-liked-forza-horizon-5-nighttime-so-much-that-its-being-extended/1100-6516047/ (search summary)
- https://www.tomsguide.com/news/forza-horizon-5-preview (search summary)
- https://destructoid.com/?p=292591 (search summary)
- https://forums.forza.net/t/lets-discuss-wet-conditions/755254 (search summary)
- https://forums.forza.net/t/custom-traffic-tool-no-hesi/728246 (search summary)
- https://forums.forza.net/t/cars-vehicle-tailights-are-way-too-bright-at-night/595692 (search summary)
- https://sportskeeda.com/esports/forza-horizon-5-good-can-better (search summary)
- https://app.betahub.io/projects/pr-8026521657/issues/319 (search summary)
- https://www.windowscentral.com/forza-horizon-5-barn-finds (search summary)
- https://news.xbox.com/en-us/2023/09/12/forza-horizon-5-event-lab-2/ (search summary)
- https://gdcvault.com/play/1024091/Shoot-for-the-Sky-The (search summary)
- https://www.ppe.pl/news/163014/forza-horizon-5-na-xbox-series-x-to-arcydzielo-digital-foundry-wychwala-produkcje-microsoftu.html (search summary)
- https://www.kotaku.com.au/?p=1247729 (search summary: dust-storm visibility, windscreen spray, body dirt and wash-off)
- https://forums.forza.net/t/water-on-lens-photo-mode/535257 (search summary, community: droplets on the camera lens)
- https://racinggames.gg/article/forza-horizon-5-trailer-breakdown-locations-cars-weather-revealed-porsche-mercedes-land-rover-e3-showcase-sandstorm-thunderstorm (search summary: dust storms by season, tropical storms in storm season)

### Road classes, event layouts, festival sites (completeness review)
- https://mapmaster.io/games/forza-horizon-5-playstation/guides/Dirt%20Racing%20Event (trail vs scramble, surfaces)
- https://sportskeeda.com/esports/what-dirt-trail-events-forza-horizon-5 (search summary: trail = point to point, scramble = circuit)
- https://guides4gamers.com/forza-horizon-5/poi/dirt-racing-events/ (search summary: scramble loop length and laps)
- https://guides4gamers.com/forza-horizon-5/poi/cross-country-racing-events/ (search summary)
- https://gtplanet.net/forza-horizon-5-season-change-20220915 (search summary: street racing at night with traffic, dirt racing on marked roads)
- https://www.gtplanet.net/forza-horizon-5-event-lab-20211110/ (custom routes must start at an existing race start point; circuit or point-to-point)
- https://progameguides.com/forza-horizon-5/what-are-the-different-festival-sites-in-forza-horizon-5/ (search summary: main site plus five outposts and their disciplines)
- https://forums.forza.net/t/horizon-festival-sites-and-campaign-gameplay-in-fh5/534577 (search summary)
- https://mapmaster.io/games/forza-horizon-5-playstation/guides/Festival%20Site (search summary)
- https://forza.fandom.com/wiki/Forza_Horizon_5/Festival_Playlist (search summary, community: weekly seasons, photo challenges)
- https://racinggames.gg/article/forza-horizon-5-meanstreets-photo-challenge-guide (search summary: photo challenge rules and variants)
- https://racinggames.gg/forza/forza-horizon-5-series-11-summer-festival-playlist-reward-cars-photo-challenge-treasure-hunt (search summary)

### Activities, HUD, navigation, photo mode
- https://racinggames.gg/forza/forza-horizon-5-what-are-the-best-cars-for-pr-stunts
- https://guides4gamers.com/forza-horizon-5/pois/speed-traps/
- https://mapmaster.io/games/forza-horizon-5-playstation/guides/Cross%20Country%20Event
- https://mapmaster.io/games/forza-horizon-5-playstation/guides/Dirt%20Racing%20Event
- https://www.gtplanet.net/forza-horizon-5-snackable-20210907/
- https://racinggames.gg/forza/forza-horizon-5-bonus-boards-how-to-find-every-xp-and-fast-travel-board/
- https://www.shacknews.com/article/127554/fast-travel-and-xp-board-location-maps-forza-horizon-5
- https://forza.net/news/forza-horizon-5-achievements
- https://www.dexerto.com/gaming/forza-horizon-5-barn-finds-explained-everything-you-need-to-know-1680127/
- https://insider-gaming.com/every-skill-in-forza-horizon-5-how-to-earn-an-ultimate-skill-chain/
- https://digitaltrends.com/?p=2926748
- https://kotaku.com/11-things-i-wish-i-knew-before-starting-forza-horizon-5-1848007497
- https://kotaku.com/before-you-start-five-settings-to-change-in-forza-hori-1848004522
- https://caniplaythat.com/2021/11/04/forza-horizon-5-accessibility-menu-deep-dive/ (also used for cars/assists)
- https://caniplaythat.com/2021/11/04/forza-horizon-5-accessibility-review-can-i-play-that/
- https://news.xbox.com/en-us/2021/11/04/gaming-for-everyone-the-accessibility-features-of-forza-horizon-5/
- https://forza.net/news/forza-photo-guide
- https://forum.cfx.re/t/release-forza-horizon-4-minimap/1283766
- https://gamesradar.com/forza-horizon-5-drift-zones (search summary)
- https://gamesradar.com/forza-horizon-5-car-mastery (search summary)
- https://mapmaster.io/games/forza-horizon-5-playstation/guides/Drift%20Zone (search summary)
- https://mapmaster.io/games/forza-horizon-5-playstation/guides/Showcase (search summary)
- https://traxion.gg/take-on-a-jumbo-jet-using-ken-blocks-v2-cossie-in-a-forza-horizon-5-showcase/ (search summary)
- https://blogs.windows.com/windowsexperience/2022/03/08/pr-stunt-carnival-now-underway-in-forza-horizon-5-series-5-update/ (search summary)
- https://www.techradar.com/how-to/forza-horizon-5-barn-finds (search summary)
- https://pcgamer.com/forza-horizon-5-fast-travel-boards-unlock-free (search summary)
- https://www.gfinityesports.com/forza-horizon-5/how-to-fast-travel-free/ (search summary)
- https://www.gfinityesports.com/forza-horizon-5/turn-off-narrator/ (search summary)
- https://primagames.com/gaming/forza-horizon-5-photo-mode (search summary)
- https://support.forza.net/hc/en-us/articles/4409280058259-Forza-Horizon-5-Accessibility-Support (search summary)
- https://www.thexboxhub.com/forza-horizon-5-festival-playlist-weekly-challenges-guide-series-25-autumn/ (search summary)
- https://racinggames.gg/forza/forza-horizon-5-series-12-spring-festival-playlist-reward-cars-treasure-hunt-photo-challenge (search summary)
- https://forums.forza.net/t/unable-to-clearly-see-route-on-hud-due-to-user-being-colour-deficit/83222 (search summary)
- https://forums.forza.net/t/simplified-hud/608259 (search summary)
- https://forums.forza.net/t/ability-to-save-map-filter-options/576309 (search summary)
- https://forums.forzamotorsport.net/t/the-tach-needle-in-fh5-isnt-clear-enough/534510 (search summary)
- https://steamcommunity.com/app/1551360/discussions/0/4759830079702268193 (search summary)
- https://djcube.co.uk/review-forza-horizon-5/ (search summary)
- https://www.gta5-mods.com/vi/scripts/forza-styled-speedometer (search summary)
- https://www.modland.net/beamng.drive-mods/other/horizon-style-tachometer-ui.html (search summary)
- https://mp1st.com/reviews/forza-horizon-5-ps5-review-hit-the-open-road (search summary)
- https://www.caradvice.com.au/caradvice/forza-horizon-5-game-review/ (search summary)

### Cars, customization, upgrades, tuning, assists, cameras
- https://racinggames.gg/forza/forza-horizon-5-how-to-change-difficulty/
- https://racinggames.gg/article/taking-the-wheel-which-driving-assists-to-turn-off-in-forza-horizon-6
- https://racinggames.gg/article/forza-horizon-5-patch-notes-march-update-brings-added-accessibility-quality-of-life-improvements-more
- https://racinggames.gg/forza/forza-horizon-5-major-handling-upgrades-revealed/
- https://racinggames.gg/forza/forza-horizon-5-winter-dry-season-challenges-car-restrictions/
- https://racinggames.gg/article/forza-horizon-5-livery-editor-powerful-design-paint-creator-release-date-news-updates
- https://sirusgaming.com/forza-horizon-5-how-to-upgrade-cars/
- https://hackernoon.com/forza-horizon-5-cars-guide-how-to-build-and-tune-for-optimal-road-race-performance
- https://gamepretty.com/forza-horizon-5-build-tuning-tips/
- https://gamepretty.com/forza-horizon-5-horizon-tours-car-requirement/
- https://www.drifted.com/forza-horizon-5-drift-tune/
- https://www.ludo.guide/guide/forza-horizon-5/racing-line
- https://steamcommunity.com/app/1551360/discussions/0/4038102696010805262/
- https://digistatement.com/forza-horizon-5-change-fov/
- https://www.windowscentral.com/forza-horizon-5-upgrading-guide (search summary)
- https://support.forza.net/hc/en-us/articles/360005372033-FH3-Performance-Index-and-Classes (search summary)
- https://forums.forza.net/t/lets-discuss-performance-index-classes-pi/577894 (search summary)
- https://forums.forza.net/t/forza-horizon-3-game-guide-faq/36955/27 (search summary)
- https://forums.forza.net/t/new-vinyl-texture-feature/550631 (search summary)
- https://techraptor.net/gaming/guides/forza-horizon-5-cosmetic-tips-and-tricks (search summary)
- https://sportskeeda.com/esports/how-paint-brake-caliper-forza-horizon-5 (search summary)
- https://forums.forza.net/t/drivatar-difficulty-in-festival-playlists/548896 (search summary)
- https://traxion.gg/how-to-complete-the-forza-horizon-5-super-street-treasure-hunt/ (search summary)
- https://www.videogameschronicle.com/news/over-420-of-forza-horizon-5s-cars-have-been-officially-confirmed (search summary: 426 cars confirmed pre-launch)
- https://pcgamer.com/forza-horizon-5-has-426-cars-and-counting (search summary)
- https://steamcommunity.com/app/1551360/discussions/0/4353368388524616540 (search summary, community: acquisition-route breakdown, unverified)
- https://www.gamesradar.com/forza-horizon-5-tips (search summary: credit bonus rises as assists are removed)
- https://support.forza.net/hc/en-us/articles/360005368213-FH3-Difficulty-and-Assists (search summary: driving-line colour key, previous game)

### Godot 4.7 (plus the installed 4.7.2 `--doctool` class dump, core and module classes)
- https://docs.godotengine.org/en/stable/classes/class_vehiclebody3d.html
- https://docs.godotengine.org/en/stable/classes/class_vehiclewheel3d.html
- https://docs.godotengine.org/en/stable/classes/class_rigidbody3d.html
- https://docs.godotengine.org/en/stable/classes/class_physicsdirectbodystate3d.html
- https://docs.godotengine.org/en/stable/classes/class_physicsdirectspacestate3d.html
- https://docs.godotengine.org/en/stable/tutorials/physics/ray-casting.html
- https://docs.godotengine.org/en/stable/classes/class_worldenvironment.html
- https://docs.godotengine.org/en/stable/classes/class_audiostreampolyphonic.html
- https://docs.godotengine.org/en/stable/classes/class_projectsettings.html
- https://docs.godotengine.org/en/stable/classes/class_heightmapshape3d.html
- https://docs.godotengine.org/en/stable/classes/class_surfacetool.html
- https://docs.godotengine.org/en/stable/classes/class_multimesh.html
- https://docs.godotengine.org/en/stable/classes/class_geometryinstance3d.html
- https://docs.godotengine.org/en/stable/classes/class_workerthreadpool.html
- https://docs.godotengine.org/en/stable/classes/class_environment.html
- https://docs.godotengine.org/en/stable/classes/class_audiostreamgenerator.html
- https://docs.godotengine.org/en/stable/classes/class_audiostreamwav.html
- https://docs.godotengine.org/en/stable/classes/class_inputmap.html
- https://docs.godotengine.org/en/stable/classes/class_resourceimporterscene.html
- https://docs.godotengine.org/en/stable/classes/class_vector3.html
- https://docs.godotengine.org/en/stable/classes/class_viewport.html
- https://docs.godotengine.org/en/stable/tutorials/physics/using_jolt_physics.html
- https://docs.godotengine.org/en/stable/tutorials/physics/interpolation/using_physics_interpolation.html
- https://docs.godotengine.org/en/stable/tutorials/physics/interpolation/advanced_physics_interpolation.html
- https://docs.godotengine.org/en/stable/tutorials/physics/troubleshooting_physics_issues.html
- https://docs.godotengine.org/en/stable/tutorials/physics/large_world_coordinates.html
- https://docs.godotengine.org/en/stable/tutorials/3d/procedural_geometry/arraymesh.html
- https://docs.godotengine.org/en/stable/tutorials/3d/visibility_ranges.html
- https://docs.godotengine.org/en/stable/tutorials/3d/occlusion_culling.html
- https://docs.godotengine.org/en/stable/tutorials/3d/mesh_lod.html
- https://docs.godotengine.org/en/stable/tutorials/3d/lights_and_shadows.html
- https://docs.godotengine.org/en/stable/tutorials/performance/thread_safe_apis.html
- https://docs.godotengine.org/en/stable/tutorials/shaders/shader_reference/sky_shader.html
- https://docs.godotengine.org/en/stable/tutorials/3d/environment_and_post_processing.html
- https://docs.godotengine.org/en/stable/tutorials/3d/particles/collision.html
- https://docs.godotengine.org/en/stable/tutorials/3d/particles/trails.html
- https://docs.godotengine.org/en/stable/tutorials/3d/using_decals.html
- https://docs.godotengine.org/en/stable/tutorials/assets_pipeline/importing_3d_scenes/node_type_customization.html
- https://docs.godotengine.org/en/stable/tutorials/assets_pipeline/importing_3d_scenes/import_configuration.html
- https://docs.godotengine.org/en/stable/tutorials/editor/command_line_tutorial.html
- https://docs.godotengine.org/en/stable/tutorials/animation/creating_movies.html
- https://registry.khronos.org/glTF/specs/2.0/glTF-2.0.html
- https://github.com/godotengine/godot-proposals/issues/13357
- https://godotengine.org/releases/4.6/ (search summary)
- https://docs.godotengine.org/en/4.2/classes/class_inputmap.html (search summary)
- https://github.com/godot-jolt/godot-jolt/releases/latest (search summary)
- https://forum.godotengine.org/t/custom-raycast-vehicle-wheels-squish-onto-the-ground-at-high-speeds/129510 (search summary)
- https://remotebranch.eu/Stowage/godot/commit/a5424c321eca013cbd5da6401c7bece4667ed2ea (search summary)

### Pricing
- https://platform.claude.com/docs/en/about-claude/pricing
- https://platform.claude.com/docs/en/build-with-claude/thinking-steering-and-cost
- https://platform.claude.com/docs/en/build-with-claude/extended-thinking
