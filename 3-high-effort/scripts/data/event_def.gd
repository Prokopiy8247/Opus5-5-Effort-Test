class_name EventDef
extends Resource
## One activity placed on the road network.

enum Kind { SPEED_TRAP, SPEED_ZONE, DRIFT_ZONE, JUMP, RACE, TIME_TRIAL, BOARD }

@export var id: String = ""
@export var display_name: String = ""
@export var kind: Kind = Kind.SPEED_TRAP
@export var road_id: String = ""
## Start position along the road (0..1). For gates/boards this is the only position.
@export var start_frac: float = 0.0
## End position along the road (zones, races). For a loop time trial equal to start.
@export var end_frac: float = 0.0
## Optional world (x, z) positions; when set they override the fractions.
@export var start_xz: Vector2 = Vector2.INF
@export var end_xz: Vector2 = Vector2.INF
## Thresholds for 1, 2 and 3 stars (km/h, points, metres, or seconds for races: lower is better).
@export var stars: PackedFloat32Array = PackedFloat32Array([0.0, 0.0, 0.0])
@export var laps: int = 1
@export var opponents: int = 0
@export var checkpoint_spacing_m: float = 600.0
@export var reward: int = 1000
@export_multiline var description: String = ""
