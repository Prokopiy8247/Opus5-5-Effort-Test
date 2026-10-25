# Blender -> Godot asset conventions (Sunward Roads)

Single source of truth shared by the Blender authoring scripts (`tools/blender/`) and the Godot code
(`scripts/vehicle/car_factory.gd`, `scripts/world/*`). Change both sides together.

## General
- 1 Blender unit = 1 m. Master file: `Opus55ForzaUltracodeEffort.blend` (never loaded at runtime).
- Root collection `SUNWARD_GODOT` with children `Cars`, `Traffic`, `Props`, `Nature`, `Roadside`,
  `Settlements`, `Landmarks`, `Collision`. Each exported asset lives in its own child collection
  (e.g. `Cars/Car_kestrel_r4`). The default Cube/Light/Camera are moved to `_Default_Unused` (hidden,
  never exported).
- Export: glTF 2.0 binary (`.glb`), +Y up, modifiers applied, selection only, no cameras/lights/animations.
  Output under `assets/imported/<category>/`. Godot imports with `godot --headless --import`.
- No external assets, no AI generation, no downloaded textures. Materials are plain PBR values
  (base colour / metallic / roughness / emission); textures, if any, are generated procedurally in Blender
  and packed into the .glb.
- No unnamed objects (`Cube.001` etc.) in exported assets.

## Axes
- Blender is Z-up. Vehicles face **Blender +Y**. After export Godot sees the vehicle facing **-Z**
  (Godot forward), with **+X = right side**, +Y = up.
- Vehicle root origin: on the ground plane (Z=0 = bottom of tyres at rest), centred laterally,
  longitudinally at the midpoint between front and rear axles.

## Vehicle object names (player cars and traffic vehicles)
| Object | Notes |
|---|---|
| `<car_id>` (Empty) | root of the car, everything parented to it, identity transform at origin |
| `Body` | painted shell + trim/grille/chrome details. Material slots: `Paint`, `Trim`, `Chrome`, `Grille`, optional `Carbon`, `Underbody` |
| `Glass` | all windows, single material `Glass` (transparent) |
| `Interior` | seats, dash, gauges, console, door cards, floor (materials `Interior`, `InteriorDark`, optional `Gauge`) |
| `SteeringWheel` | origin at hub. Object-local +Y = steering column axis pointing toward the dashboard; rim in local XZ plane. Code spins it about its local column axis |
| `Wheel_FL`, `Wheel_FR`, `Wheel_RL`, `Wheel_RR` | tyre + rim + brake disc, **origin at axle centre, identity rotation/scale applied**, spin axis = X. Left wheels are geometry-mirrored so the rim faces outward. Materials `Rubber`, `Rim`, `BrakeDisc` |
| `Caliper_FL` ... `Caliper_RR` | origin at the same axle centre; steers with the wheel but does not spin. Material `Caliper` |
| `Lights_Head` | front lamp lenses, material `HeadlightLens` (emissive white) |
| `Lights_Tail` | rear lamp lenses, material `TaillightLens` (dim red emissive) |
| `Lights_Brake` | brake lamp lenses, material `BrakeLens` (red; code boosts emission when braking) |
| `Lights_Reverse` | reverse lamps, material `ReverseLens` (white; code enables when reversing) |
| `Socket_HeadlightL/R` | Empties at the headlamp centres (code adds SpotLight3D) |
| `Socket_Exhaust` (+ optional `Socket_Exhaust2`) | Empties at exhaust tips (code adds particles/backfire) |
| `Socket_CamHood`, `Socket_CamCockpit`, `Socket_CamBumper` | Empties for camera positions (cockpit = driver eye point) |

Material names may carry a suffix (e.g. `Paint_kestrel_r4`); Godot matches by the prefix token.

## Car roster (ids are used in file names and data)
| # | id | Name | Class / layout |
|---|---|---|---|
| 1 | `kestrel_r4` | Kestrel R4 | compact hot hatch, FWD |
| 2 | `aurelia_sedan` | Aurelia Saloon | everyday 4-door sedan, FWD |
| 3 | `brute_68` | Brute 68 | classic muscle car, RWD V8 |
| 4 | `sora_s2` | Sora S2 | sports coupe, RWD |
| 5 | `castellan_gt` | Castellan GT | front-engine grand tourer, RWD V12 |
| 6 | `vortex_x` | Vortex X | mid-engine supercar, AWD |
| 7 | `granite_rally` | Granite RS | rally car, AWD |
| 8 | `ridgeback_sx` | Ridgeback SX | off-road SUV, AWD |
| 9 | `hauler_2500` | Hauler 2500 | pickup truck, RWD-biased 4x4 |
| 10 | `lark_roadster` | Lark Roadster | vintage open roadster, RWD |
