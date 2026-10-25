class_name UpgradeDef
extends Resource
## One upgrade level of one part group. Multipliers stack per level.

@export var part: String = "engine"
@export var level: int = 1
@export var display_name: String = "Street"
@export_multiline var description: String = ""
@export var torque_mult: float = 1.0
@export var mass_mult: float = 1.0
@export var grip_mult: float = 1.0
@export var offroad_mult: float = 1.0
@export var brake_mult: float = 1.0
@export var downforce_add: float = 0.0
@export var drag_mult: float = 1.0
@export var spring_mult: float = 1.0
@export var arb_mult: float = 1.0
@export var redline_add: float = 0.0
@export var price: int = 5000
