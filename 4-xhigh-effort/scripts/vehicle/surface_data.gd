class_name SurfaceData
extends Resource
## Physical/audio/visual behaviour of a driving surface. One .tres per surface in res://data/surfaces/.

enum Kind { ASPHALT, CONCRETE, DIRT, GRAVEL, GRASS, SAND, SNOW, ROCK }

@export var kind := Kind.ASPHALT
@export var display_name := "Asphalt"
@export var grip := 1.0
## Grip multiplier at full road wetness (1.0 = unaffected).
@export var wet_grip := 0.72
@export var rolling_resistance := 0.012
## Extra drag on tyres (sand/snow sink in), N per N of load per m/s.
@export var sink_drag := 0.0
@export var bumpiness := 0.0
## Multipliers by CarData.TireType (ROAD, SPORT, RALLY, OFFROAD, VINTAGE).
@export var tire_mults := PackedFloat32Array([1.0, 1.0, 1.0, 1.0, 1.0])
@export var paved := true
@export var particle_color := Color(0.85, 0.85, 0.85, 0.5)
@export var particle_amount := 1.0
@export var skid_sound := &"squeal"
@export var roll_sound := &""
