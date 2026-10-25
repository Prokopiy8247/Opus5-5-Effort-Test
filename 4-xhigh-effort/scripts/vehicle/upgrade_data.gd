class_name UpgradeData
extends Resource
## One upgrade level of one category (res://data/upgrades/<category>_<level>.tres).

@export var category := "engine"
@export var level := 0
@export var display_name := "Stock"
@export_multiline var description := ""
@export var cost := 0
## Multipliers merged into CarController.mods: power, grip, susp, brake, mass, aero, top.
@export var multipliers := {}
