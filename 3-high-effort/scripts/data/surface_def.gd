class_name SurfaceDef
extends Resource
## Physical and audiovisual properties of a driving surface.

@export var id: int = 0
@export var key: String = "asphalt"
@export var display_name: String = "Asphalt"
## Grip multiplier per CarSpec.TireType (ROAD, SPORT, RALLY, OFFROAD, VINTAGE).
@export var grip_by_tire: PackedFloat32Array = PackedFloat32Array([1.0, 1.05, 0.95, 0.85, 0.9])
@export var rolling_resistance: float = 0.012
## Extra speed-dependent drag (soft surfaces), as a fraction of g.
@export var drag: float = 0.0
## Vertical noise amplitude in metres added to suspension (rough surfaces).
@export var bumpiness: float = 0.0
## How much rain reduces grip here (0 = not at all, 1 = fully applies the wet factor).
@export var wet_sensitivity: float = 1.0
@export var is_offroad: bool = false
@export var particle_color: Color = Color(0.6, 0.6, 0.6, 0.5)
@export var skid_marks: bool = true
@export var squeal: float = 1.0
@export var rumble: float = 0.0
