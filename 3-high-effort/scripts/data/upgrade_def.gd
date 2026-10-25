class_name UpgradeDef
extends Resource
## One upgrade category with four levels (Stock, Street, Sport, Race).
## Each level lists multipliers applied to the car's modifiers.

@export var key: String = "engine"
@export var display_name: String = "Engine"
@export var level_names: PackedStringArray = PackedStringArray(["Stock", "Street", "Sport", "Race"])
## modifier name -> per-level values (index = level). Modifier names match Car.mod_* fields.
@export var effects: Dictionary = {}
@export var pi_per_level: int = 20
@export var cost_per_level: int = 2500
