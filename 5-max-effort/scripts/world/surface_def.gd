class_name SurfaceDef
extends Resource
## Physical, visual and audio response of one ground surface type.

@export var id: int = 0
@export var key: StringName = &"asphalt"
@export var display_name: String = "Asphalt"
## Peak friction coefficient multiplier for a road tyre.
@export var grip: float = 1.0
## Loose surfaces have broader slip peaks (multiplies the tyre's peak slip values).
@export var slip_peak_scale: float = 1.0
## Fraction of peak grip kept while fully sliding.
@export var slide_ratio: float = 0.72
## How much an off-road tyre (offroad_grip > 1) benefits on this surface (0 = not at all).
@export var loose: float = 0.0
@export var rolling_resistance: float = 0.012
## Extra speed-proportional drag per wheel (sand, grass, mud), N per (m/s) per kN load.
@export var soft_drag: float = 0.0
## Amplitude of procedural ground noise felt through the suspension (metres).
@export var bumpiness: float = 0.0
## Grip multiplier when fully wet.
@export var wet_grip: float = 0.78
@export var dust_color: Color = Color(0.5, 0.5, 0.5, 0.0)
## 0 smoke, 1 dust, 2 gravel, 3 grass, 4 sand, 5 snow
@export var particle: int = 0
## 0 squeal, 1 gravel crunch, 2 dirt rumble, 3 grass swish, 4 sand hiss, 5 snow crunch
@export var sound: int = 0
@export var skidmarks: bool = true
@export var skid_color: Color = Color(0.05, 0.05, 0.05, 0.8)
