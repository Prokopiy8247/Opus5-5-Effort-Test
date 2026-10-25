# OPUS 5.5 FINAL REPORT — *Verdant Ridge Festival*

An original open-world arcade-sim racing game for **Godot 4.7.2**, inspired by Forza Horizon 5 for mechanics and
scope only. It contains no Forza / Playground / Microsoft names or content. You start in free roam on a coastal road
in a 4 × 4 km countryside with 41.6 km of roads, a 10-car garage, civilian traffic, weather, day/night and road activities.

## How to run
**Exported game:** `build\VerdantRidgeFestival.exe`. Double-click it; it is a single file with the data embedded. Rebuild with `tools\build_windows.ps1`.

From source:
```
W:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe --path "<project folder>"
```
(`-- --fresh` ignores the save file. QA automation: `-- --qa --qa-mode=shots|drive|cars|loop|events|jump|drift|ui|save|compare|perf|showcase`.)

**Run result:** the main scene loads with no script errors (headless and windowed). The world is ready in about 3–8 s,
including the shader warm-up. The game drops you into the default car on Harbour Coast Road.

## What was built
* **World:** a deterministic, seeded terrain function covering four regions: *Greenvale Farmlands*, *Granite Highlands*,
  *Ochre Canyon* and *Azure Coast*. It has a river, a lake and the sea, and terrain cuttings and embankments shaped
  along every road. Terrain is streamed in 128 m chunks generated on worker threads, over a far-terrain mesh.
* **Roads:** 37 spline roads, **41.6 km** in total, joined at 21 junctions. The **Grand Festival Loop is 20.3 km** and
  crosses every region. Road classes are highway, scenic, mountain, concrete, dirt and gravel, each with procedural
  markings. Roads have banking, about 3.1 km of bridges and viaducts, one tunnel, guard rails, reflector posts and
  speed, chevron and direction signs, plus junction pads.
* **Settlements and landmarks:** Greenvale village, Saltmere Harbour (pier and boats), Westcliff, Dustwater, 5 farms,
  2 gas stations, 2 diners, a lighthouse, a castle ruin, a 7-turbine wind farm with spinning rotors, street lamps
  that light up at night, and parked cars.
* **Nature:** MultiMesh pines, oaks, birches, palms, cacti, shrubs, bushes and rocks, each with two LOD levels, plus
  wind-swaying grass tufts tinted to the terrain.
* **Vehicle physics:** a project-owned raycast vehicle on a Jolt `RigidBody3D` at 120 Hz. It has spring/damper
  suspension with anti-roll bars, a Pacejka-style tyre model with a friction circle, engine torque curves, an
  automatic or manual gearbox, FWD/RWD/AWD, aero drag and downforce, and TCS/ESC/ABS/steering assist toggles. It also
  has a handbrake for drifting, per-surface and wet grip, air control, impact damage and reset to road.
  `VehicleBody3D` was prototyped and rejected; the numbers are in DEVELOPMENT.md.
* **Cameras:** chase near and far, hood, bumper and cockpit. FOV and shake scale with speed, the camera avoids
  clipping into terrain, and there is free look and look-back.
* **Audio:** fully procedural, with no audio files. It covers the engine (per-car cylinder count, pitch and roughness),
  turbo and blow-off, gear shifts, tyre squeal and gravel crunch, wind, suspension thumps, impacts, horns and regional
  ambience.
* **10-car garage:** each car has its own Blender model and handling `CarDef`, a class/PI label, and paint (colour,
  gloss/metallic/matte, stripes, rim colour). There are 6 upgrade parts × 4 levels with a stat comparison, plus 8
  tuning sliders.
* **Traffic:** a lane graph built from the road splines, IDM car-following that also treats the player as a leader,
  curve speeds, junction give-way and turning, U-turns at dead ends, and overtaking of stopped obstacles. There are
  6 Blender traffic types plus a sedan. Vehicles come from a pool of 40 (34 active at most, scaled by density) and
  spawn and despawn outside the view. Physics detail drops with distance from the player, crashes produce wrecks,
  and traffic uses horns and headlight flashes.
* **Activities:** 7 speed traps, 4 speed zones, 5 drift zones and 3 danger-sign jumps. There are 3 checkpoint races
  with 3 AI rivals each, a 20 km loop time trial and 20 collectible festival boards. Personal bests and credits are
  tracked.
* **UI:**
  * HUD: speedo/tach dial in km/h or mph, gear, surface, assist indicators, region pop-ups, toasts, activity panel,
    FPS/coordinates and telemetry.
  * Minimap: heading-up, with roads and icons.
  * Full map: click to set a waypoint, with a GPS route.
  * Menus: console (`` ` ``), garage (Tab/F1), benchmark/debug menu (F2), tuning (F3), photo mode (P) and pause.
* **Save/load:** car, paint, upgrades, tuning, position, time, weather, settings and personal bests are saved to
  `user://savegame.json`, with an autosave every 60 s.
* **Input:** keyboard and mouse only. Gamepad bindings were removed at the user's request during the session.

## Car roster
| # | Car | Maker | Class/PI | Drive | 0–100 | Top speed |
|---|---|---|---|---|---|---|
| 1 | Pico GTi (hot hatch) | Velora | C 565 | FWD | 7.1 s | 205 km/h |
| 2 | Meridian Touring (sedan) | Aster Motors | B 610 | RWD | 6.5 s | 221 |
| 3 | Thunderhawk 440 (muscle) | Brannock | A 715 | RWD | 6.5 s | 252 |
| 4 | Kestrel S (sports coupe) | Sakura Line | A 745 | RWD | 5.8 s | 256 |
| 5 | Corsair GT (grand tourer) | Halden | S1 845 | RWD | 5.8 s | 309 |
| 6 | Vortice R (mid-engine hypercar) | Moretti Fabbrica | S2 935 | AWD | 3.0 s | 341 |
| 7 | Torrent RS (rally) | Nordvik | A 760 | AWD | 4.0 s | 220 |
| 8 | Ridgeback 4x4 (off-road SUV) | Atlas Overland | B 625 | AWD | 6.1 s | 188 |
| 9 | Hauler V8 (pickup) | Brannock | C 585 | RWD | 7.4 s | 182 |
| 10 | Aurelia 1600 (vintage roadster) | Lucent | D 380 | RWD | 8.9 s | 163 |
All makers and models are fictional.

## Map regions
North: Granite Highlands, with switchback passes up to about 270 m, a snow line, a tunnel and the castle ruin.
East: Ochre Canyon, with mesas, cacti, gravel trails and the wind farm. Centre and west: Greenvale Farmlands, with
the river valley, lake, village and farms. South and west edges: Azure Coast, with beaches, cliffs, the harbour, the
lighthouse and the estuary bridge.

## Blender assets (all through MCP `blender-opus55-medium` on localhost:9878)
There are **52 exported assets**:
* **10 player cars**, each with body, separate glass, four wheels pivoted at the axle centre, brakes, head/tail/reverse
  lights, interior and steering wheel.
* **6 traffic vehicles.**
* **36 kit props:**
  * nature: 8 tree models (4 species, each with an LOD variant), cactus, shrub, bush and 3 rocks
  * buildings: 3 houses, barn, gas station, diner, lighthouse, castle and wind turbine
  * road furniture: fence, street lamp and 4 sign types
  * event props: 5 event gates, a jump ramp and a boat

They were generated by the reproducible scripts `tools/blender/car_builder.py`, `car_specs.py` and
`props_builder.py`, inspected with the MCP `look` tool, and saved into collections `FORZA_GODOT/{Cars, Traffic, Props,
Settlements, Roadside, Nature, Collision}` in the master file. They were exported as `.glb` into `assets/imported/`.
No downloaded or generated third-party assets were used.

## Traffic implementation
See DEVELOPMENT.md, section "Traffic". In a measured 70 s highway drive there were 20 active vehicles; 144 were
spawned and 124 recycled, with 6 junction yields and 1 crash reaction.

## Performance notes
* About 120–180 FPS typical. 180 FPS is the vsync cap.
* 118 FPS average over the full loop drive.
* Memory stayed flat over a lap: 178 → 191 MB.
* There was no chunk leak: about 130 chunks stayed loaded.
* Every per-system frame cost stayed under 5 ms, except the first HUD draw and audio catch-up after a long frame.
* All of this was measured while **9 other Godot and 7 Blender instances from other projects were running on the
  same machine**, which caused large run-to-run swings and the remaining frame spikes.

## What works / what is partial
See **FEATURE_MATRIX.md**: 56 rows WORKING, plus PARTIAL and NOT IMPLEMENTED rows with notes.

**Partial or missing:**
* Damage is a counter only.
* No rewind.
* Only one tunnel.
* Traffic overtakes only stopped obstacles.
* Long uninterrupted roads are about 2.4 km per road and 4–6 km across consecutive roads.
* No gamepad (by user request).

## Known bugs / caveats
* The QA autopilot can snag on traffic at junction pads. A human driver just steers around.
* Rare frame spikes up to about 100 ms happen on this shared machine.
* The skidpad figure (about 0.75 g) comes from a conservative scripted controller.
* The Blender MCP server disconnected late in the session. All Blender work was finished and saved before that.

## Controls
W/S throttle and brake/reverse · A/D steer · Space handbrake · E/Q shift (manual) · C camera · B look back · right
mouse drag free look · R reset · L lights · H horn · Enter start a race at its gate · `` ` `` console · Tab/F1 garage ·
F2 debug · F3 tuning · M map · P photo mode (F12 saves a photo) · Esc pause.

## Git
8+ milestone commits, from the baseline through world/car, props/UI/traffic/activities, QA and fixes, to final.
`.godot/`, backups and QA output are git-ignored.

## Claude Opus 5.5 Godot Forza Session Metrics

```text
Project: Godot 4.7 Forza-style open-world racing game
Effort level under test: medium
Run/session identifier: run-20261023-185244 / Claude Code session 477f8147-92aa-42e8-b9cd-fb351bbfb821 (segment 2); segment 1 was an earlier session whose usage log is not present locally
Working-directory full path: W:\YouTube\Opus 5.5 Effort Test\2. Opus 5.5 Forza Medium Effort\2.-opus-5.5-forza-medium-effort
Start timestamp and timezone: 2026-10-23T18:52:44.004+02:00 (Central European Summer Time, UTC+02:00) - measured
End timestamp and timezone: 2026-10-23T22:59:00.561+02:00 (Central European Summer Time, UTC+02:00) - measured
Elapsed wall-clock time (HH:MM:SS): 04:06:16 (measured, start to end, including the pause below)
Elapsed minutes: 246.3 (measured)
Known pauses / resumed segments: segment 1 18:52:44 -> ~18:56 (stopped: no Blender MCP tools in that session); pause ~18:56 -> 19:11:08 (~15 min, approximate, user re-registered the MCP server); segment 2 19:11:08.835 -> 22:59:00.561 = 03:47:52 (227.9 min, measured). Active time ~03:51 (segment 1 duration approximate).

Requested model: Claude Opus 5.5
Actual model identifier(s): claude-opus-5-5 (main agent, 196 responses); claude-sonnet-5-5 (1 research subagent, 5 responses)
Input tokens (state whether uncached or inclusive): 430 uncached (main 420 + subagent 10) - measured
Cache-read tokens: 78,724,649 (main 78,499,985 + subagent 224,664) - measured
Cache-write tokens: 626,049 (main 559,717 as 1-hour writes + subagent 66,332 as 5-minute writes) - measured
Output tokens: 385,072 (main 378,535 + subagent 6,537) - measured
Thinking/reasoning tokens (included / separate / unavailable): included in output tokens; not exposed separately
Deduplicated total tokens: 79,736,201 (main 79,438,657 + subagent 297,543), deduplicated by API message id
Usage source and observation cutoff: local Claude Code session log ~/.claude/projects/<project>/477f8147-....jsonl plus subagents/agent-a7446e7e7a60049a4.jsonl (only the message.usage fields were read); cutoff 2026-10-23T20:58:58Z (22:58:58 local)
Unmeasured work / limitations: segment 1 (~4 min, separate session, log not available locally) is not counted; the few responses after the cutoff that wrote this report are not counted; subagent WebSearch/WebFetch server-tool fees are not token costs and are excluded

Token-only API-equivalent cost (USD): $28.00 (main Opus 5.5 $27.75 + Sonnet 5.5 subagent $0.25) - computed from measured usage
Official pricing source, verification date and tier: https://platform.claude.com/docs/en/about-claude/pricing , fetched 2026-10-23, standard API pricing (no batch, no fast mode, no regional multiplier)
Rates and formula used: Opus 5.5 per MTok: input $4, 1h cache write $8, cache read $0.20, output $20. Sonnet 5.5 per MTok: input $2, 5m cache write $2.50, cache read $0.10, output $10.
  main  = 420x4 + 78,499,985x0.20 + 559,717x8 + 378,535x20 = $0.0017 + $15.7000 + $4.4777 + $7.5707 = $27.7501
  sub   = 10x2 + 224,664x0.10 + 66,332x2.50 + 6,537x10   = $0.0000 + $0.0225 + $0.1658 + $0.0654 = $0.2537
  total = $28.0038 (per-MTok products divided by 1,000,000)
Measured / estimated / unavailable, with reasons: time measured (segment-1 end and pause length approximate); tokens measured from the session log, excluding segment 1 and the post-cutoff tail; cost computed exactly from those tokens and the published rates

Blender MCP server/tool namespace actually used: blender-opus55-medium (mcp__blender-opus55-medium__*: get_addon_status, execute_blender_code, look), started by the project .mcp.json as `uvx mcp-for-blender --port 9878`
Blender host: localhost
Blender port: 9878
Blender master file: Opus55ForzaMediumEffort.blend
Verified full path of master file: W:\YouTube\Opus 5.5 Effort Test\2. Opus 5.5 Forza Medium Effort\2.-opus-5.5-forza-medium-effort\Opus55ForzaMediumEffort.blend (read with bpy.data.filepath before any edit)
Approximate number of major Blender assets created: 52 (10 player cars, 6 traffic vehicles, 36 kit props)
```

