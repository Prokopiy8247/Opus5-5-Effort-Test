class_name SurfaceData
extends Resource
## Physical + presentation properties of a driving surface. One .tres per surface in res://data/surfaces/.

@export var id: StringName = &"asphalt"
@export var display_name: String = "Asphalt"
## Grip multiplier for pure road tyres.
@export var grip_road: float = 1.0
## Grip multiplier for full off-road tyres.
@export var grip_offroad: float = 0.92
## Multiplier applied to grip at full wetness (rain). 1 = unaffected.
@export var wet_grip: float = 0.74
## Extra rolling resistance coefficient (sand, grass).
@export var rolling_drag: float = 0.0
## Random suspension excitation amplitude in metres (rough surfaces).
@export var roughness: float = 0.0
## Lateral slide factor: lower values make the surface more slidey at the limit.
@export var slide_factor: float = 1.0
## Multiplier applied to slide_factor at full wetness.
@export var wet_slide: float = 1.0
## Sealed road surface (asphalt / concrete): tyre smoke and spray rather than dust, no dirt on the paint.
@export var paved: bool = false
## Presentation surface used once the road is visibly wet (HUD name, no smoke, lighter marks). It must carry
## the same grip numbers: grip keeps scaling continuously with wetness through grip_for / slide_for.
@export var wet_id: StringName = &""
## Particle colour for dust / spray kicked up by wheels.
@export var particle_color: Color = Color(0.5, 0.5, 0.5, 0.5)
## True if wheels on it leave tyre smoke (hard surfaces) instead of dust.
@export var smokes: bool = true
## Audio: tyre squeal (asphalt) vs. gravel crunch etc.  0=squeal 1=crunch 2=soft(grass/sand)
@export var audio_kind: int = 0
## Skid mark colour (alpha 0 = no marks).
@export var skid_color: Color = Color(0.05, 0.05, 0.05, 0.6)


func grip_for(offroad_tires: float, wetness: float) -> float:
	var g := lerpf(grip_road, grip_offroad, clampf(offroad_tires, 0.0, 1.0))
	return g * lerpf(1.0, wet_grip, clampf(wetness, 0.0, 1.0))


func slide_for(wetness: float) -> float:
	return slide_factor * lerpf(1.0, wet_slide, clampf(wetness, 0.0, 1.0))
