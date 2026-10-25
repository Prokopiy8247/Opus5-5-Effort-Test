class_name TrafficType
extends Resource
## A civilian vehicle type (res://data/traffic/*.tres).

@export var id := &"compact"
@export var display_name := "Compact"
@export var model_path := ""
@export var mass := 1100.0
@export var speed_factor := 1.0
@export var accel := 2.2
@export var decel := 4.5
@export var length := 4.0
@export var colors: Array[Color] = []
## spawn weight per road class: highway, regional, mountain, village, gravel, dirt
@export var class_weights := PackedFloat32Array([1, 1, 1, 1, 0, 0])
@export var farm_only := false
