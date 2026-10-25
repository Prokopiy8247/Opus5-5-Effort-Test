class_name WeatherPreset
extends Resource
## One weather state (res://data/weather/*.tres). SkyWeather blends between presets.

@export var id := &"clear"
@export var display_name := "Clear"
@export_range(0.0, 1.0) var cloud_coverage := 0.2
@export_range(0.0, 1.0) var cloud_darkness := 0.0
@export var fog_density := 0.00018
@export var fog_height_density := 0.0
@export var volumetric_fog := 0.0
@export_range(0.0, 1.0) var rain := 0.0
@export var lightning := false
@export var wetness := 0.0
@export var sun_energy := 1.0
@export var ambient := 1.0
@export var sky_tint := Color(1, 1, 1)
@export var wind := 2.0
## extra grip multiplier on top of surface wetness (wind gusts, standing water)
@export var grip := 1.0
@export var weight := 1.0
