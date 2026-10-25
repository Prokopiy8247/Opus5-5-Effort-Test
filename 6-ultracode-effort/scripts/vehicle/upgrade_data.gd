class_name UpgradeData
extends Resource
## One upgrade slot (engine, tyres, ...). Effects are per level (levels 1..3).

@export var slot: String = "engine"
@export var display_name: String = "Engine"
@export var level_names: PackedStringArray = PackedStringArray(["Stock", "Street", "Sport", "Race"])
@export var cost_per_level: int = 5000
@export var torque_per_level: float = 0.0
@export var rpm_per_level: float = 0.0
@export var grip_per_level: float = 0.0
@export var stiffness_per_level: float = 0.0
@export var lower_per_level: float = 0.0
@export var brake_per_level: float = 0.0
@export var weight_per_level: float = 0.0
@export var downforce_per_level: float = 0.0
@export var drag_per_level: float = 0.0
@export var top_speed_per_level: float = 0.0
